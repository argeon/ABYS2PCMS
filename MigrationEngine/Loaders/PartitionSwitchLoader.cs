using Microsoft.Data.SqlClient;
using Serilog;

namespace MigrationEngine.Loaders;

/// <summary>
/// Implements the MSSQL Partition Switch strategy for large-table migrations.
/// Instead of INSERT...SELECT (which copies all rows), staging tables are
/// switched into partitions of the target via ALTER TABLE...SWITCH (metadata-only,
/// near-instant). Requires the target to be a partitioned heap (no clustered index).
/// </summary>
public class PartitionSwitchLoader
{
    private readonly string _connectionString;

    public PartitionSwitchLoader(string connectionString)
    {
        _connectionString = connectionString;
    }

    public static string PfName(string table) => $"pf_mig_{SafeName(table)}";
    public static string PsName(string table) => $"ps_mig_{SafeName(table)}";

    private static string SafeName(string n) =>
        new string(n.Select(c => char.IsLetterOrDigit(c) || c == '_' ? c : '_').ToArray());

    private static string Q(string n) => $"[{n.Replace("]", "]]")}]";

    /// <summary>
    /// Checks whether the target table has a clustered index.
    /// SWITCH requires both the staging table and the target partition to have the same index structure.
    /// For data-only migrations (no indexes migrated) the target is a heap, so SWITCH works directly.
    /// </summary>
    public async Task<bool> HasClusteredIndexAsync(string tableName, CancellationToken ct)
    {
        await using var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);
        const string sql = "SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID(@t, 'U') AND type = 1";
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@t", $"dbo.{tableName}");
        var result = await cmd.ExecuteScalarAsync(ct);
        return Convert.ToInt32(result) > 0;
    }

    private async Task<List<ColumnDef>> GetColumnDefsAsync(string tableName, SqlConnection conn, CancellationToken ct)
    {
        const string sql = @"
            SELECT c.name, tp.name AS type_name, c.max_length, c.precision, c.scale, c.is_nullable
            FROM sys.columns c
            JOIN sys.types tp ON c.user_type_id = tp.user_type_id
            WHERE c.object_id = OBJECT_ID(@t, 'U')
            ORDER BY c.column_id";

        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@t", $"dbo.{tableName}");

        var cols = new List<ColumnDef>();
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            cols.Add(new ColumnDef
            {
                Name = reader.GetString(0),
                TypeName = reader.GetString(1),
                MaxLength = reader.GetInt16(2),
                Precision = reader.GetByte(3),
                Scale = reader.GetByte(4),
                IsNullable = reader.GetBoolean(5)
            });
        }
        return cols;
    }

    private static string BuildColumnTypeDecl(ColumnDef c)
    {
        return c.TypeName.ToLowerInvariant() switch
        {
            "varchar"  => c.MaxLength == -1 ? "varchar(MAX)"  : $"varchar({c.MaxLength})",
            "nvarchar" => c.MaxLength == -1 ? "nvarchar(MAX)" : $"nvarchar({c.MaxLength / 2})",
            "char"     => $"char({c.MaxLength})",
            "nchar"    => $"nchar({c.MaxLength / 2})",
            "varbinary"=> c.MaxLength == -1 ? "varbinary(MAX)" : $"varbinary({c.MaxLength})",
            "binary"   => $"binary({c.MaxLength})",
            "decimal" or "numeric" => $"{c.TypeName}({c.Precision},{c.Scale})",
            "datetime2"     => c.Scale < 7 ? $"datetime2({c.Scale})"     : "datetime2",
            "time"          => c.Scale < 7 ? $"time({c.Scale})"          : "time",
            "datetimeoffset"=> c.Scale < 7 ? $"datetimeoffset({c.Scale})" : "datetimeoffset",
            _ => c.TypeName
        };
    }

    /// <summary>
    /// Prepares the target table for partition switching:
    /// <list type="number">
    ///   <item>Renames the existing (empty) target to a backup name — never drops it outright.</item>
    ///   <item>Creates partition function + scheme with the supplied boundaries.</item>
    ///   <item>Re-creates the target as a partitioned heap on the partition scheme.</item>
    ///   <item>On any failure: renames backup back + cleans up partial objects → returns false.</item>
    ///   <item>On success: drops the backup (it was empty).</item>
    /// </list>
    /// Returns false if the target has a clustered index (falls back to INSERT/SELECT merge).
    /// </summary>
    public async Task<bool> PreparePartitionedTargetAsync(
        string targetTable,
        string pkColumn,
        IReadOnlyList<long> boundaries,
        CancellationToken ct)
    {
        await using var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);

        // Clustered index check — SWITCH needs same structure on both sides
        const string idxCheck = "SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID(@t, 'U') AND type = 1";
        await using (var idxCmd = new SqlCommand(idxCheck, conn))
        {
            idxCmd.Parameters.AddWithValue("@t", $"dbo.{targetTable}");
            if (Convert.ToInt32(await idxCmd.ExecuteScalarAsync(ct)) > 0)
            {
                Log.Warning("[PartitionSwitch] [{Table}] has a clustered index — requires heap. Falling back to INSERT/SELECT.", targetTable);
                return false;
            }
        }

        var cols = await GetColumnDefsAsync(targetTable, conn, ct);
        if (cols.Count == 0)
        {
            Log.Warning("[PartitionSwitch] Could not read column defs for [{Table}]. Falling back to INSERT/SELECT.", targetTable);
            return false;
        }

        var pfName  = PfName(targetTable);
        var psName  = PsName(targetTable);
        var tgt     = Q(targetTable);
        var pkCol   = Q(pkColumn);
        var bakName = $"__mig_orig_{SafeName(targetTable)}";

        var pkDef      = cols.FirstOrDefault(c => c.Name.Equals(pkColumn, StringComparison.OrdinalIgnoreCase));
        var pkTypeDecl = pkDef != null ? BuildColumnTypeDecl(pkDef) : "bigint";
        var boundaryValues = string.Join(", ", boundaries);
        var colDefs = string.Join(",\n    ", cols.Select(c =>
            $"{Q(c.Name)} {BuildColumnTypeDecl(c)} {(c.IsNullable ? "NULL" : "NOT NULL")}"));

        // Step 1: Rename original table to backup (safe — reversible on failure)
        await using (var renCmd = new SqlCommand(
            $"EXEC sp_rename 'dbo.{targetTable}', '{bakName}';", conn) { CommandTimeout = 60 })
        {
            await renCmd.ExecuteNonQueryAsync(ct);
        }
        Log.Debug("[PartitionSwitch] Renamed [{Tgt}] → [{Bak}]", targetTable, bakName);

        bool setupOk = false;
        try
        {
            // Step 2–4: partition function, scheme, new partitioned table
            var createSteps = new (string label, string sql)[]
            {
                ("create pf",  $"CREATE PARTITION FUNCTION [{pfName}] ({pkTypeDecl}) AS RANGE RIGHT FOR VALUES ({boundaryValues});"),
                ("create ps",  $"CREATE PARTITION SCHEME [{psName}] AS PARTITION [{pfName}] ALL TO ([PRIMARY]);"),
                ("create tbl", $"CREATE TABLE [dbo].{tgt} (\n    {colDefs}\n) ON [{psName}]({pkCol});")
            };

            foreach (var (label, sql) in createSteps)
            {
                await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 300 };
                await cmd.ExecuteNonQueryAsync(ct);
                Log.Debug("[PartitionSwitch] {Label} OK for [{Table}]", label, targetTable);
            }

            setupOk = true;
        }
        catch (Exception ex)
        {
            Log.Error(ex, "[PartitionSwitch] Setup failed for [{Table}] — restoring original table", targetTable);
        }
        finally
        {
            if (!setupOk)
            {
                // Restore original: rename backup back to original name
                try
                {
                    await using var restCmd = new SqlCommand(
                        $"EXEC sp_rename 'dbo.{bakName}', '{targetTable}';", conn) { CommandTimeout = 60 };
                    await restCmd.ExecuteNonQueryAsync(ct);
                    Log.Information("[PartitionSwitch] Original [{Table}] restored.", targetTable);
                }
                catch (Exception restEx)
                {
                    Log.Error(restEx, "[PartitionSwitch] CRITICAL: Could not restore [{Table}] — backup is [{Bak}]!", targetTable, bakName);
                }

                // Clean up any partial partition objects
                foreach (var ddl in new[]
                {
                    $"IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = '{psName}') DROP PARTITION SCHEME [{psName}];",
                    $"IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = '{pfName}') DROP PARTITION FUNCTION [{pfName}];"
                })
                {
                    try
                    {
                        await using var cleanCmd = new SqlCommand(ddl, conn) { CommandTimeout = 60 };
                        await cleanCmd.ExecuteNonQueryAsync(ct);
                    }
                    catch { }
                }
            }
        }

        if (!setupOk) return false;

        // Drop the backup (was an empty table — safe to discard)
        try
        {
            await using var dropBak = new SqlCommand($"DROP TABLE [dbo].{Q(bakName)};", conn) { CommandTimeout = 60 };
            await dropBak.ExecuteNonQueryAsync(ct);
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "[PartitionSwitch] Could not drop backup [{Bak}] — manual cleanup needed", bakName);
        }

        Log.Information("[PartitionSwitch] [{Table}] partitioned heap ready ({N} partitions, pk=[{PkCol}])",
            targetTable, boundaries.Count + 1, pkColumn);
        return true;
    }

    /// <summary>
    /// Adds a CHECK constraint to each staging table so MSSQL can verify the rows
    /// fall within the corresponding partition range before allowing SWITCH.
    /// </summary>
    public async Task AddSwitchConstraintsAsync(
        string pkColumn,
        IReadOnlyList<(string stagingTable, long minPk, long maxPk)> partitions,
        CancellationToken ct)
    {
        var tasks = partitions.Select(async p =>
        {
            var stg            = Q(p.stagingTable);
            var constraintName = $"CK_mig_sw_{SafeName(p.stagingTable)}";
            var sql =
                $"ALTER TABLE [dbo].{stg} ADD CONSTRAINT [{constraintName}] " +
                $"CHECK ({Q(pkColumn)} >= {p.minPk} AND {Q(pkColumn)} <= {p.maxPk});";

            await using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync(ct);
            await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 120 };
            await cmd.ExecuteNonQueryAsync(ct);
            Log.Debug("[PartitionSwitch] CHECK constraint on [{Stg}]: pk [{Min},{Max}]", p.stagingTable, p.minPk, p.maxPk);
        });

        await Task.WhenAll(tasks);
    }

    /// <summary>
    /// Performs ALTER TABLE staging SWITCH TO target PARTITION N for every partition.
    /// This is a metadata-only operation — no rows are physically moved.
    /// </summary>
    public async Task SwitchAllPartitionsAsync(
        string targetTable,
        IReadOnlyList<(string stagingTable, int partitionNumber)> partitions,
        CancellationToken ct)
    {
        foreach (var (stagingTable, partNum) in partitions)
        {
            var sql = $"ALTER TABLE [dbo].{Q(stagingTable)} SWITCH TO [dbo].{Q(targetTable)} PARTITION {partNum};";

            await using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync(ct);
            await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 300 };
            await cmd.ExecuteNonQueryAsync(ct);
            Log.Information("[PartitionSwitch] SWITCH [{Stg}] → [{Tgt}] PARTITION {N} (instant)", stagingTable, targetTable, partNum);
        }
    }

    /// <summary>
    /// After all partitions are switched: merges every boundary (collapsing back to a simple heap)
    /// and drops the partition function and scheme.
    /// </summary>
    public async Task CleanupPartitionObjectsAsync(
        string targetTable,
        IReadOnlyList<long> boundaries,
        CancellationToken ct)
    {
        var pfName = PfName(targetTable);
        var psName = PsName(targetTable);

        await using var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);

        // Merge boundaries one at a time (smallest first avoids ordering issues)
        foreach (var b in boundaries.OrderBy(x => x))
        {
            try
            {
                await using var cmd = new SqlCommand(
                    $"ALTER PARTITION FUNCTION [{pfName}]() MERGE RANGE ({b});", conn)
                { CommandTimeout = 600 };
                await cmd.ExecuteNonQueryAsync(ct);
            }
            catch (Exception ex)
            {
                Log.Warning(ex, "[PartitionSwitch] Could not merge boundary {B} for [{Table}]", b, targetTable);
            }
        }

        foreach (var (kind, sql) in new[]
        {
            ("partition scheme",   $"DROP PARTITION SCHEME [{psName}];"),
            ("partition function", $"DROP PARTITION FUNCTION [{pfName}];")
        })
        {
            try
            {
                await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 60 };
                await cmd.ExecuteNonQueryAsync(ct);
            }
            catch (Exception ex)
            {
                Log.Warning(ex, "[PartitionSwitch] Could not drop {Kind} for [{Table}]", kind, targetTable);
            }
        }

        Log.Information("[PartitionSwitch] Partition objects cleaned up for [{Table}]", targetTable);
    }

    private sealed record ColumnDef
    {
        public string Name     { get; init; } = "";
        public string TypeName { get; init; } = "";
        public short  MaxLength { get; init; }
        public byte   Precision { get; init; }
        public byte   Scale     { get; init; }
        public bool   IsNullable{ get; init; }
    }
}
