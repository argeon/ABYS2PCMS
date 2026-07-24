using Microsoft.Data.SqlClient;
using MigrationEngine.Schema;
using Serilog;
using System.Data;

namespace MigrationEngine.Loaders;

public class SqlBulkCopyLoader
{
    private readonly string _connectionString;
    private readonly int _batchSize;
    private const int MaxRetries = 3;

    public SqlBulkCopyLoader(string connectionString, int batchSize = 50000)
    {
        _connectionString = connectionString;
        _batchSize = batchSize;
    }

    public async Task<long> LoadDataAsync(
        string tableName,
        IDataReader reader,
        Action<long>? progressCallback,
        CancellationToken ct,
        IReadOnlyList<ColumnSchema>? sourceColumns = null)
    {
        // Destination metadata can be retried (fresh SQL connection each time).
        // WriteToServerAsync cannot — Oracle reader is forward-only; a failed attempt would
        // dispose/partially consume it and the next attempt hits ORA-50045 on FieldCount.
        HashSet<string>? destinationColumns = null;
        Dictionary<string, string>? destinationSqlTypes = null;

        for (var attempt = 0; attempt <= MaxRetries; attempt++)
        {
            try
            {
                using var metaConnection = new SqlConnection(_connectionString);
                await metaConnection.OpenAsync(ct);
                destinationColumns = await GetTableColumnNamesAsync(metaConnection, tableName, ct);
                destinationSqlTypes = await GetTableColumnSqlTypesAsync(metaConnection, tableName, ct);
                break;
            }
            catch (Exception ex) when (attempt < MaxRetries)
            {
                var delay = 5000 * (1 << attempt);
                Log.Warning(ex,
                    "Destination metadata attempt {Attempt}/{Total} failed for table {Table}. Retrying in {Delay}ms",
                    attempt + 1, MaxRetries + 1, tableName, delay);
                await Task.Delay(delay, ct);
            }
        }

        if (destinationColumns is null || destinationSqlTypes is null)
            throw new InvalidOperationException($"Failed to read destination metadata for table {tableName}.");

        if (reader.IsClosed)
        {
            throw new InvalidOperationException(
                $"Oracle reader is already closed for table {tableName} before bulk copy " +
                "(command/connection disposed too early — see OwnedOracleDataReader).");
        }

        var sourceToDestSqlType = BuildSourceToDestinationSqlTypeMap(
            reader, sourceColumns, destinationColumns, destinationSqlTypes);

        // leaveOpen: caller (Program) owns the Oracle reader lifetime.
        using var safeReader = new SafeDataReaderWrapper(
            reader, tableName, sourceColumns, sourceToDestSqlType, leaveOpen: true);

        try
        {
            using var connection = new SqlConnection(_connectionString);
            await connection.OpenAsync(ct);

            using var transaction = connection.BeginTransaction();
            using var bulkCopy = new SqlBulkCopy(connection, SqlBulkCopyOptions.Default, transaction)
            {
                DestinationTableName = $"[{tableName}]",
                BatchSize = _batchSize,
                BulkCopyTimeout = 0,
                EnableStreaming = false
            };

            ConfigureBulkCopyMappings(bulkCopy, safeReader, sourceColumns, destinationColumns);

            bulkCopy.SqlRowsCopied += (_, e) => progressCallback?.Invoke(e.RowsCopied);
            bulkCopy.NotifyAfter = _batchSize;

            await bulkCopy.WriteToServerAsync(safeReader, ct);
            await transaction.CommitAsync(ct);

            // Use reader row count — SqlRowsCopied only fires every NotifyAfter rows
            // so the last partial batch would be missed if we relied on e.RowsCopied.
            var totalRows = safeReader.RowsRead;
            Log.Information("Successfully loaded {Rows} rows into table {Table}", totalRows, tableName);
            return totalRows;
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Bulk copy failed for table {Table}", tableName);
            throw;
        }
    }

    private static void ConfigureBulkCopyMappings(
        SqlBulkCopy bulkCopy,
        SafeDataReaderWrapper reader,
        IReadOnlyList<ColumnSchema>? sourceColumns,
        IReadOnlySet<string> destinationColumns)
    {
        var mappingLog = new List<string>();
        for (var i = 0; i < reader.FieldCount; i++)
        {
            var srcName = reader.GetName(i);
            var destName = ResolveDestinationColumnName(srcName, sourceColumns, destinationColumns);

            if (!destinationColumns.Contains(destName))
            {
                throw new InvalidOperationException(
                    $"Bulk copy mapping failed for [{srcName}] → [{destName}]: destination column not found. " +
                    "Use Hard reset / Recreate to rebuild the table with the current spatial schema.");
            }

            bulkCopy.ColumnMappings.Add(i, destName);
            mappingLog.Add($"{srcName}→{destName}");
        }

        Log.Debug("Bulk copy column mappings for [{Table}]: {Mappings}",
            bulkCopy.DestinationTableName, string.Join(", ", mappingLog));
    }

    private static string ResolveDestinationColumnName(
        string sourceColumnName,
        IReadOnlyList<ColumnSchema>? sourceColumns,
        IReadOnlySet<string> destinationColumns)
    {
        if (sourceColumns != null)
        {
            var column = sourceColumns.FirstOrDefault(c =>
                string.Equals(c.ColumnName, sourceColumnName, StringComparison.OrdinalIgnoreCase));

            if (column != null && SpatialColumnHelper.IsSpatialColumn(column))
            {
                var wktColumn = SpatialColumnHelper.GetWktStagingColumnName(column);
                if (destinationColumns.Contains(wktColumn))
                    return wktColumn;

                if (destinationColumns.Contains(column.ColumnName))
                {
                    Log.Warning(
                        "Spatial column [{Column}]: staging [{Wkt}] not found — loading WKT into [{Column}] (legacy schema)",
                        column.ColumnName, wktColumn, column.ColumnName);
                    return column.ColumnName;
                }
            }
        }

        return sourceColumnName;
    }

    private static async Task<HashSet<string>> GetTableColumnNamesAsync(
        SqlConnection connection,
        string tableName,
        CancellationToken ct)
    {
        var sqlTypes = await GetTableColumnSqlTypesAsync(connection, tableName, ct);
        return sqlTypes.Keys.ToHashSet(StringComparer.OrdinalIgnoreCase);
    }

    private static async Task<Dictionary<string, string>> GetTableColumnSqlTypesAsync(
        SqlConnection connection,
        string tableName,
        CancellationToken ct)
    {
        const string sql = @"
            SELECT c.name, ty.name
            FROM sys.columns c
            INNER JOIN sys.tables t ON c.object_id = t.object_id
            INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
            INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
            WHERE t.name = @table AND s.name = 'dbo'";

        var columns = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        await using var cmd = new SqlCommand(sql, connection);
        cmd.Parameters.AddWithValue("@table", tableName);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            columns[reader.GetString(0)] = reader.GetString(1);
        }

        return columns;
    }

    private static Dictionary<string, string> BuildSourceToDestinationSqlTypeMap(
        IDataReader reader,
        IReadOnlyList<ColumnSchema>? sourceColumns,
        IReadOnlySet<string> destinationColumns,
        IReadOnlyDictionary<string, string> destinationSqlTypes)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < reader.FieldCount; i++)
        {
            var sourceName = reader.GetName(i);
            var destName = ResolveDestinationColumnName(sourceName, sourceColumns, destinationColumns);
            if (destinationSqlTypes.TryGetValue(destName, out var sqlType))
            {
                map[sourceName] = sqlType;
                continue;
            }

            Log.Warning(
                "Bulk copy type map: destination column [{Dest}] for source [{Source}] not found in table metadata",
                destName, sourceName);
        }

        return map;
    }

    public async Task ExecuteDdlAsync(string ddl, CancellationToken ct)
    {
        using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);

        using var cmd = new SqlCommand(ddl, connection)
        {
            CommandTimeout = 0
        };

        try
        {
            await cmd.ExecuteNonQueryAsync(ct);
        }
        catch (SqlException ex) when (IsBenignDuplicateSchemaError(ex))
        {
            Log.Warning("Skipping DDL (already exists, SqlError {ErrorNumber}): {Ddl}",
                ex.Number, ddl.Substring(0, Math.Min(120, ddl.Length)));
        }
    }

    public async Task ExecuteDdlBatchAsync(IEnumerable<string> ddlStatements, CancellationToken ct)
    {
        using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);

        foreach (var ddl in ddlStatements)
        {
            if (string.IsNullOrWhiteSpace(ddl))
                continue;

            try
            {
                using var cmd = new SqlCommand(ddl, connection)
                {
                    CommandTimeout = 0
                };

                await cmd.ExecuteNonQueryAsync(ct);
            }
            catch (SqlException ex) when (IsBenignDuplicateSchemaError(ex))
            {
                Log.Warning("Skipping DDL (already exists, SqlError {ErrorNumber}): {Ddl}",
                    ex.Number, ddl.Substring(0, Math.Min(120, ddl.Length)));
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Failed to execute DDL: {DDL}", ddl.Substring(0, Math.Min(100, ddl.Length)));
                throw;
            }
        }
    }

    /// <summary>
    /// True when the statement failed only because the target already exists (safe to skip on migration re-runs).
    /// </summary>
    private static bool IsBenignDuplicateSchemaError(SqlException ex)
    {
        return ex.Number switch
        {
            2714 => true, // There is already an object named '…' in the database (table, constraint name, etc.)
            1913 => true, // Index or statistics named '…' already exists on table '…'
            1779 => true, // Table already has a PRIMARY KEY
            _ => false
        };
    }

    public async Task<string> GetRecoveryModelAsync(CancellationToken ct)
    {
        using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);

        using var cmd = new SqlCommand("SELECT recovery_model_desc FROM sys.databases WHERE name = DB_NAME()", connection);
        var result = await cmd.ExecuteScalarAsync(ct);
        return result?.ToString() ?? "FULL";
    }

    public async Task SetRecoveryModelAsync(string databaseName, string recoveryModel, CancellationToken ct)
    {
        using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);

        var sql = $"ALTER DATABASE [{databaseName}] SET RECOVERY {recoveryModel}";
        using var cmd = new SqlCommand(sql, connection);
        await cmd.ExecuteNonQueryAsync(ct);

        Log.Information("Set database {Database} recovery model to {Model}", databaseName, recoveryModel);
    }

    public async Task<string> GetDatabaseNameAsync(CancellationToken ct)
    {
        using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);

        using var cmd = new SqlCommand("SELECT DB_NAME()", connection);
        var result = await cmd.ExecuteScalarAsync(ct);
        return result?.ToString() ?? "UNKNOWN";
    }

    public async Task DropTableAsync(string tableName, CancellationToken ct)
    {
        using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);
        using var cmd = new SqlCommand($"IF OBJECT_ID(N'[{tableName}]', N'U') IS NOT NULL DROP TABLE [{tableName}]", connection)
        {
            CommandTimeout = 0
        };
        await cmd.ExecuteNonQueryAsync(ct);
        Log.Information("Dropped table [{Table}]", tableName);
    }

    public async Task TruncateTableAsync(string tableName, CancellationToken ct)
    {
        using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);
        using var cmd = new SqlCommand($"IF OBJECT_ID(N'[{tableName}]', N'U') IS NOT NULL TRUNCATE TABLE [{tableName}]", connection)
        {
            CommandTimeout = 0
        };
        await cmd.ExecuteNonQueryAsync(ct);
        Log.Information("Truncated table [{Table}]", tableName);
    }

    public async Task<long> GetTargetRowCountAsync(string tableName, CancellationToken ct)
    {
        using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);
        using var cmd = new SqlCommand(
            $"IF OBJECT_ID(N'[{tableName}]', N'U') IS NOT NULL SELECT COUNT_BIG(*) FROM [{tableName}] ELSE SELECT CAST(0 AS BIGINT)",
            connection) { CommandTimeout = 0 };
        var result = await cmd.ExecuteScalarAsync(ct);
        return result == null || result == DBNull.Value ? 0L : Convert.ToInt64(result);
    }

    public async Task<bool> TableExistsAsync(string tableName, CancellationToken ct)
    {
        using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);
        using var cmd = new SqlCommand(
            "SELECT COUNT(1) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = @t AND TABLE_TYPE = 'BASE TABLE'",
            connection);
        cmd.Parameters.AddWithValue("@t", tableName);
        var result = await cmd.ExecuteScalarAsync(ct);
        return Convert.ToInt32(result) > 0;
    }

    public async Task<long> DeletePkRangeAsync(string tableName, string pkColumn, long startPk, long endPk, CancellationToken ct)
    {
        var sql = $"DELETE FROM [{tableName}] WHERE [{pkColumn}] >= @startPk AND [{pkColumn}] <= @endPk";
        using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);
        using var cmd = new SqlCommand(sql, connection) { CommandTimeout = 0 };
        cmd.Parameters.AddWithValue("@startPk", startPk);
        cmd.Parameters.AddWithValue("@endPk", endPk);
        var deleted = await cmd.ExecuteNonQueryAsync(ct);
        Log.Information("Deleted {Count} rows from [{Table}] for PK range [{Start},{End}]", deleted, tableName, startPk, endPk);
        return deleted;
    }
}
