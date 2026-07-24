using Microsoft.Data.SqlClient;
using Serilog;

namespace MigrationEngine.Loaders;

/// <summary>
/// Manages per-partition staging tables on MSSQL.
/// Each partition is bulk-copied into its own staging table to avoid
/// lock contention on the final target table during parallel loads.
/// After all partitions complete, staging tables are merged into the
/// target ordered by ascending row count (smallest-first), then dropped.
/// </summary>
public class StagingMergeLoader
{
    private readonly string _connectionString;

    public StagingMergeLoader(string connectionString)
    {
        _connectionString = connectionString;
    }

    /// <summary>Returns a deterministic staging table name for a given table/partition index.</summary>
    public static string StagingTableName(string baseTable, int partitionIndex)
    {
        // Prefix with __mig_ so they're easy to identify and clean up
        var safe = new string(baseTable.Select(c => char.IsLetterOrDigit(c) || c == '_' ? c : '_').ToArray());
        return $"__mig_{safe}_s{partitionIndex}";
    }

    /// <summary>
    /// Drops the staging table if it exists, then creates an empty copy of <paramref name="sourceTable"/>.
    /// Uses SELECT TOP 0 * INTO to replicate column types without constraints or indexes.
    /// </summary>
    public async Task CreateStagingTableAsync(string sourceTable, string stagingTable, CancellationToken ct)
    {
        var src = QuoteName(sourceTable);
        var stg = QuoteName(stagingTable);
        var sql =
            $"IF OBJECT_ID(N'[dbo].{stg}', N'U') IS NOT NULL DROP TABLE [dbo].{stg}; " +
            $"SELECT TOP 0 * INTO [dbo].{stg} FROM [dbo].{src};";

        await using var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 300 };
        await cmd.ExecuteNonQueryAsync(ct);
        Log.Debug("Staging table [dbo].{Stg} created from [dbo].{Src}", stagingTable, sourceTable);
    }

    /// <summary>Drops a staging table if it exists.</summary>
    public async Task DropStagingTableAsync(string stagingTable, CancellationToken ct)
    {
        var stg = QuoteName(stagingTable);
        var sql = $"IF OBJECT_ID(N'[dbo].{stg}', N'U') IS NOT NULL DROP TABLE [dbo].{stg};";

        await using var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 60 };
        await cmd.ExecuteNonQueryAsync(ct);
    }

    /// <summary>Returns the exact row count of a staging table.</summary>
    public async Task<long> GetRowCountAsync(string stagingTable, CancellationToken ct)
    {
        var stg = QuoteName(stagingTable);
        await using var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand($"SELECT COUNT_BIG(*) FROM [dbo].{stg}", conn) { CommandTimeout = 300 };
        var result = await cmd.ExecuteScalarAsync(ct);
        return result is null or DBNull ? 0L : Convert.ToInt64(result);
    }

    /// <summary>
    /// Merges staging tables into <paramref name="targetTable"/> in ascending row-count order
    /// (smallest first) to minimise page splits and logging. Returns total rows inserted.
    /// </summary>
    public async Task<long> MergeIntoTargetAsync(
        string targetTable,
        IReadOnlyList<string> stagingTables,
        CancellationToken ct)
    {
        // Get row counts to determine merge order
        var counts = new List<(string table, long rows)>(stagingTables.Count);
        foreach (var st in stagingTables)
        {
            var cnt = await GetRowCountAsync(st, ct);
            counts.Add((st, cnt));
            Log.Information("Staging {Table}: {Rows:N0} rows", st, cnt);
        }
        counts.Sort((a, b) => a.rows.CompareTo(b.rows));

        long totalMerged = 0;
        var tgt = QuoteName(targetTable);

        foreach (var (st, expected) in counts)
        {
            if (expected == 0)
            {
                Log.Debug("Staging {Table} is empty, skipping merge", st);
                continue;
            }

            var stg = QuoteName(st);
            var sql = $"INSERT INTO [dbo].{tgt} SELECT * FROM [dbo].{stg};";

            await using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync(ct);
            await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 0 };
            var affected = await cmd.ExecuteNonQueryAsync(ct);
            totalMerged += affected;
            Log.Information("Merged {Rows:N0} rows from staging [{St}] into [{Tgt}]", affected, st, targetTable);
        }

        return totalMerged;
    }

    /// <summary>
    /// Drop all staging tables for a given base table (cleanup after merge or on error).
    /// Ignores individual drop failures.
    /// </summary>
    public async Task DropAllStagingTablesAsync(IEnumerable<string> stagingTables, CancellationToken ct)
    {
        foreach (var st in stagingTables)
        {
            try
            {
                await DropStagingTableAsync(st, ct);
            }
            catch (Exception ex)
            {
                Log.Warning(ex, "Failed to drop staging table {Table} — manual cleanup may be needed", st);
            }
        }
    }

    private static string QuoteName(string name) => $"[{name.Replace("]", "]]")}]";
}
