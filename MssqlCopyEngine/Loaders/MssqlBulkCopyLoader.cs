using Microsoft.Data.SqlClient;
using Serilog;

namespace MssqlCopyEngine.Loaders;

public sealed class MssqlBulkCopyLoader
{
    private readonly string _targetConnectionString;
    private readonly int _batchSize;

    public MssqlBulkCopyLoader(string targetConnectionString, int batchSize)
    {
        _targetConnectionString = targetConnectionString;
        _batchSize = batchSize > 0 ? batchSize : 50_000;
    }

    public async Task<long> CopyTableAsync(
        string sourceConnectionString,
        string schema,
        string tableName,
        bool keepIdentity,
        IReadOnlyList<string>? columnNames,
        Action<long>? progressCallback,
        CancellationToken ct)
    {
        var fq = Qualify(schema, tableName);
        var columns = columnNames is { Count: > 0 }
            ? columnNames.ToList()
            : await GetInsertableColumnsAsync(sourceConnectionString, schema, tableName, ct);

        if (columns.Count == 0)
            throw new InvalidOperationException($"No insertable columns found for {fq}");

        // SqlBulkCopy fails when source LCID (e.g. 1055 TR) != destination LCID (e.g. 1033 EN).
        // Force SELECT expressions to the destination column collation for character types.
        var targetCollations = await GetColumnCollationsAsync(_targetConnectionString, schema, tableName, ct);
        var targetDbCollation = await GetDatabaseCollationAsync(_targetConnectionString, ct);
        var sourceTypes = await GetColumnDataTypesAsync(sourceConnectionString, schema, tableName, ct);

        var selectParts = new List<string>(columns.Count);
        foreach (var col in columns)
        {
            var q = $"[{col.Replace("]", "]]")}]";
            sourceTypes.TryGetValue(col, out var dataType);
            if (IsCharacterType(dataType))
            {
                var collation = targetCollations.TryGetValue(col, out var colCollation) && !string.IsNullOrWhiteSpace(colCollation)
                    ? colCollation
                    : targetDbCollation;
                if (!string.IsNullOrWhiteSpace(collation))
                {
                    // Alias keeps the original column name for SqlBulkCopy mappings
                    selectParts.Add($"{q} COLLATE {collation} AS {q}");
                    continue;
                }
            }

            selectParts.Add(q);
        }

        var selectList = string.Join(", ", selectParts);

        await using var sourceConn = new SqlConnection(sourceConnectionString);
        await sourceConn.OpenAsync(ct);

        await using var selectCmd = new SqlCommand($"SELECT {selectList} FROM {fq}", sourceConn)
        {
            CommandTimeout = 0
        };
        // SequentialAccess helps large row/LOB streaming
        await using var reader = await selectCmd.ExecuteReaderAsync(System.Data.CommandBehavior.SequentialAccess, ct);

        await using var targetConn = new SqlConnection(_targetConnectionString);
        await targetConn.OpenAsync(ct);

        // KeepNulls only — no CheckConstraints/TableLock (parallel-safe; constraints after load).
        var options = SqlBulkCopyOptions.KeepNulls;
        if (keepIdentity)
            options |= SqlBulkCopyOptions.KeepIdentity;

        using var bulk = new SqlBulkCopy(targetConn, options, null)
        {
            DestinationTableName = fq,
            BatchSize = _batchSize,
            BulkCopyTimeout = 0,
            NotifyAfter = Math.Min(5_000, Math.Max(500, _batchSize / 10)),
            EnableStreaming = true
        };

        foreach (var col in columns)
            bulk.ColumnMappings.Add(col, col);

        long rowsCopied = 0;
        bulk.SqlRowsCopied += (_, e) =>
        {
            rowsCopied = e.RowsCopied;
            try { progressCallback?.Invoke(e.RowsCopied); }
            catch (Exception ex) { Log.Warning(ex, "Progress callback failed for {Table}", fq); }
        };

        await bulk.WriteToServerAsync(reader, ct);

        if (rowsCopied == 0)
        {
            // Empty table or NotifyAfter never fired for tiny tables
            await using var countCmd = new SqlCommand($"SELECT COUNT_BIG(*) FROM {fq}", targetConn) { CommandTimeout = 0 };
            rowsCopied = Convert.ToInt64(await countCmd.ExecuteScalarAsync(ct));
        }
        else
        {
            // Final partial batch may not raise SqlRowsCopied — reconcile with COUNT when close
            await using var countCmd = new SqlCommand($"SELECT COUNT_BIG(*) FROM {fq}", targetConn) { CommandTimeout = 0 };
            var exact = Convert.ToInt64(await countCmd.ExecuteScalarAsync(ct));
            if (exact > rowsCopied)
                rowsCopied = exact;
        }

        progressCallback?.Invoke(rowsCopied);
        Log.Information("Bulk copied {Rows} rows into {Table}", rowsCopied, fq);
        return rowsCopied;
    }

    public static async Task TruncateAsync(string targetCs, string schema, string tableName, CancellationToken ct)
    {
        var fq = Qualify(schema, tableName);
        await using var conn = new SqlConnection(targetCs);
        await conn.OpenAsync(ct);

        // Prefer TRUNCATE; fall back to DELETE when FK references block truncate
        try
        {
            await using var cmd = new SqlCommand($"TRUNCATE TABLE {fq}", conn) { CommandTimeout = 0 };
            await cmd.ExecuteNonQueryAsync(ct);
        }
        catch (SqlException)
        {
            Log.Warning("TRUNCATE failed for {Table}; falling back to DELETE", fq);
            await using var cmd = new SqlCommand($"DELETE FROM {fq}", conn) { CommandTimeout = 0 };
            await cmd.ExecuteNonQueryAsync(ct);
        }
    }

    public static async Task ExecuteDdlAsync(string targetCs, string ddl, CancellationToken ct)
    {
        await using var conn = new SqlConnection(targetCs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(ddl, conn) { CommandTimeout = 0 };
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public static async Task EnsureSchemaAsync(string targetCs, string schema, CancellationToken ct)
    {
        if (string.Equals(schema, "dbo", StringComparison.OrdinalIgnoreCase))
            return;

        var sql = $@"
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = @schema)
    EXEC(N'CREATE SCHEMA [{schema.Replace("]", "]]")}]');";
        await using var conn = new SqlConnection(targetCs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@schema", schema);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public static async Task<bool> TableExistsAsync(string targetCs, string schema, string tableName, CancellationToken ct)
    {
        await using var conn = new SqlConnection(targetCs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(@"
SELECT 1 FROM sys.tables t
INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = @schema AND t.name = @table", conn);
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@table", tableName);
        var val = await cmd.ExecuteScalarAsync(ct);
        return val != null && val != DBNull.Value;
    }

    public static async Task<long> CountRowsAsync(string cs, string schema, string tableName, CancellationToken ct)
    {
        var fq = Qualify(schema, tableName);
        await using var conn = new SqlConnection(cs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand($"SELECT COUNT_BIG(*) FROM {fq}", conn) { CommandTimeout = 0 };
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct));
    }

    public static async Task<List<string>> GetInsertableColumnsAsync(
        string cs, string schema, string tableName, CancellationToken ct)
    {
        // Tables and views (materialize via SELECT *)
        const string sql = @"
SELECT c.name
FROM sys.columns c
INNER JOIN sys.objects o ON o.object_id = c.object_id
INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
INNER JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE s.name = @schema AND o.name = @table
  AND o.type IN ('U', 'V')
  AND c.is_computed = 0
  AND c.is_column_set = 0
  AND ty.name NOT IN ('timestamp', 'rowversion')
ORDER BY c.column_id";

        var cols = new List<string>();
        await using var conn = new SqlConnection(cs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@table", tableName);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
            cols.Add(reader.GetString(0));
        return cols;
    }

    public static async Task<Dictionary<string, string>> GetColumnCollationsAsync(
        string cs, string schema, string tableName, CancellationToken ct)
    {
        const string sql = @"
SELECT c.name, c.collation_name
FROM sys.columns c
INNER JOIN sys.objects o ON o.object_id = c.object_id
INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name = @schema AND o.name = @table
  AND o.type IN ('U', 'V')
  AND c.collation_name IS NOT NULL";

        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        await using var conn = new SqlConnection(cs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@table", tableName);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
            map[reader.GetString(0)] = reader.GetString(1);
        return map;
    }

    public static async Task<Dictionary<string, string>> GetColumnDataTypesAsync(
        string cs, string schema, string tableName, CancellationToken ct)
    {
        const string sql = @"
SELECT c.name, ty.name
FROM sys.columns c
INNER JOIN sys.objects o ON o.object_id = c.object_id
INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
INNER JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE s.name = @schema AND o.name = @table AND o.type IN ('U', 'V')";

        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        await using var conn = new SqlConnection(cs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@table", tableName);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
            map[reader.GetString(0)] = reader.GetString(1);
        return map;
    }

    public static async Task<string?> GetDatabaseCollationAsync(string cs, CancellationToken ct)
    {
        await using var conn = new SqlConnection(cs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand("SELECT CONVERT(sysname, DATABASEPROPERTYEX(DB_NAME(), 'Collation'))", conn);
        var val = await cmd.ExecuteScalarAsync(ct);
        return val as string;
    }

    private static bool IsCharacterType(string? dataType) =>
        dataType is not null && dataType.ToLowerInvariant() is
            "varchar" or "nvarchar" or "char" or "nchar" or "text" or "ntext" or "sysname";

    private static string Qualify(string schema, string table) =>
        $"[{schema.Replace("]", "]]")}].[{table.Replace("]", "]]")}]";
}
