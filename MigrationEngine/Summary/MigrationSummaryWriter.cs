using Microsoft.Data.SqlClient;
using MigrationEngine.Loaders;
using MigrationEngine.Schema;
using MigrationShared.Models;
using Serilog;
using System.Collections.Concurrent;

namespace MigrationEngine.Summary;

public class MigrationSummaryWriter
{
    private readonly string _connectionString;
    private const string SummaryTable = "_migration_log";

    public MigrationSummaryWriter(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task WriteSummaryAsync(
        string migrationUnid,
        string migrationName,
        List<TableSchema> tables,
        ConcurrentDictionary<string, long> sourceRowCounts,
        SqlBulkCopyLoader loader,
        CancellationToken ct)
    {
        try
        {
            await EnsureSummaryTableAsync(ct);

            using var connection = new SqlConnection(_connectionString);
            await connection.OpenAsync(ct);

            foreach (var table in tables)
            {
                var sourceCount = sourceRowCounts.TryGetValue(table.TableName, out var sc) ? sc : 0L;
                var targetCount = await loader.GetTargetRowCountAsync(table.TableName, ct);

                var status = sourceCount == 0 ? "Skipped"
                    : targetCount == sourceCount ? "Done"
                    : targetCount > 0 ? "Partial"
                    : "Failed";

                const string sql = @"
                    INSERT INTO [_migration_log]
                        (migration_unid, migration_name, table_name, source_row_count, target_row_count, status, migrated_at)
                    VALUES
                        (@unid, @name, @table, @source, @target, @status, GETUTCDATE())";

                using var cmd = new SqlCommand(sql, connection);
                cmd.Parameters.AddWithValue("@unid", migrationUnid);
                cmd.Parameters.AddWithValue("@name", migrationName);
                cmd.Parameters.AddWithValue("@table", table.TableName);
                cmd.Parameters.AddWithValue("@source", sourceCount);
                cmd.Parameters.AddWithValue("@target", targetCount);
                cmd.Parameters.AddWithValue("@status", status);
                await cmd.ExecuteNonQueryAsync(ct);

                Log.Information("[MigrationLog] {Table}: source={Source:N0}, target={Target:N0}, status={Status}",
                    table.TableName, sourceCount, targetCount, status);
            }

            Log.Information("Migration summary written to [{Table}] for UNID={Unid}", SummaryTable, migrationUnid);
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "Failed to write migration summary to target database — continuing");
        }
    }

    private async Task EnsureSummaryTableAsync(CancellationToken ct)
    {
        const string ddl = @"
            IF OBJECT_ID(N'[_migration_log]', N'U') IS NULL
            CREATE TABLE [_migration_log] (
                [id]                INT IDENTITY(1,1) PRIMARY KEY,
                [migration_unid]    NVARCHAR(50)  NOT NULL,
                [migration_name]    NVARCHAR(500) NOT NULL,
                [table_name]        NVARCHAR(255) NOT NULL,
                [source_row_count]  BIGINT        NOT NULL,
                [target_row_count]  BIGINT        NOT NULL,
                [status]            NVARCHAR(50)  NOT NULL,
                [migrated_at]       DATETIME2     NOT NULL DEFAULT GETUTCDATE()
            )";

        using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);
        using var cmd = new SqlCommand(ddl, connection) { CommandTimeout = 60 };
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
