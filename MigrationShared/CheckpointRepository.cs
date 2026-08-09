using Microsoft.Data.Sqlite;
using MigrationShared.Enums;
using MigrationShared.Models;
using Serilog;
using System.Text.Json;

namespace MigrationEngine.Checkpoint;

public class CheckpointRepository : IDisposable
{
    private readonly string _connectionString;
    private readonly SqliteConnection _connection;
    private readonly object _lock = new();

    public CheckpointRepository(string sqlitePath)
    {
        _connectionString = $"Data Source={sqlitePath}";
        _connection = new SqliteConnection(_connectionString);
        _connection.Open();
        InitializeSchema();
    }

    private void InitializeSchema()
    {
        using (var wal = new SqliteCommand("PRAGMA journal_mode=WAL;", _connection))
        {
            wal.ExecuteNonQuery();
        }

        foreach (var command in CheckpointSchema.GetSchemaCommands())
        {
            using var cmd = new SqliteCommand(command, _connection);
            cmd.ExecuteNonQuery();
        }
        
        // Initialize extended schema for history & metrics
        foreach (var schema in ExtendedCheckpointSchema.GetAllExtendedSchemas())
        {
            using var cmd = new SqliteCommand(schema, _connection);
            cmd.ExecuteNonQuery();
        }

        // Add start_pk / end_pk columns to existing DBs (ignore if already exist)
        foreach (var migrateSql in new[]
                 {
                     CheckpointSchema.MigrateAddStartPk,
                     CheckpointSchema.MigrateAddEndPk,
                     CheckpointSchema.MigrateAddRunEndTime
                 })
        {
            try
            {
                using var cmd = new SqliteCommand(migrateSql, _connection);
                cmd.ExecuteNonQuery();
            }
            catch { /* column already exists */ }
        }

        ConnectionProfileSchemaMigrator.EnsureColumns(_connection);
    }

    public int CreateNewRun(MigrationConfig config)
    {
        const string sql = @"
            INSERT INTO migration_runs (start_time, config_json, status)
            VALUES (@startTime, @configJson, @status);
            SELECT last_insert_rowid();";

        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@startTime", DateTime.UtcNow.ToString("o"));
            cmd.Parameters.AddWithValue("@configJson", JsonSerializer.Serialize(config));
            cmd.Parameters.AddWithValue("@status", "RUNNING");
            return Convert.ToInt32(cmd.ExecuteScalar());
        }
    }

    public void UpdateRunStatus(int runId, string status)
    {
        var terminal = status.Equals("COMPLETED", StringComparison.OrdinalIgnoreCase)
            || status.Equals("DONE", StringComparison.OrdinalIgnoreCase)
            || status.Equals("FAILED", StringComparison.OrdinalIgnoreCase)
            || status.Equals("STOPPED", StringComparison.OrdinalIgnoreCase);

        lock (_lock)
        {
            if (terminal)
            {
                try
                {
                    using var cmd = new SqliteCommand(
                        "UPDATE migration_runs SET status = @status, end_time = @endTime WHERE run_id = @runId",
                        _connection);
                    cmd.Parameters.AddWithValue("@status", status);
                    cmd.Parameters.AddWithValue("@runId", runId);
                    cmd.Parameters.AddWithValue("@endTime", DateTime.UtcNow.ToString("o"));
                    cmd.ExecuteNonQuery();
                    return;
                }
                catch (SqliteException)
                {
                    // end_time column may be missing on older DBs until migrate runs
                }
            }

            using var fallback = new SqliteCommand(
                "UPDATE migration_runs SET status = @status WHERE run_id = @runId",
                _connection);
            fallback.Parameters.AddWithValue("@status", status);
            fallback.Parameters.AddWithValue("@runId", runId);
            fallback.ExecuteNonQuery();
        }
    }

    public CheckpointRecord GetOrCreatePartitionCheckpoint(int runId, string tableName, string partitionKey, long totalRows,
        long? startPk = null, long? endPk = null)
    {
        lock (_lock)
        {
            const string selectSql = @"
                SELECT id, run_id, table_name, partition_key, status, rows_processed, total_rows,
                       start_time, end_time, error_message, start_pk, end_pk
                FROM table_checkpoints
                WHERE run_id = @runId AND table_name = @tableName AND partition_key = @partitionKey";

            using var selectCmd = new SqliteCommand(selectSql, _connection);
            selectCmd.Parameters.AddWithValue("@runId", runId);
            selectCmd.Parameters.AddWithValue("@tableName", tableName);
            selectCmd.Parameters.AddWithValue("@partitionKey", partitionKey);

            using var reader = selectCmd.ExecuteReader();
            if (reader.Read())
            {
                return new CheckpointRecord
                {
                    Id = reader.GetInt32(0),
                    RunId = reader.GetInt32(1),
                    TableName = reader.GetString(2),
                    PartitionKey = reader.GetString(3),
                    Status = Enum.Parse<MigrationStatus>(reader.GetString(4)),
                    RowsProcessed = reader.GetInt64(5),
                    TotalRows = reader.GetInt64(6),
                    StartTime = reader.IsDBNull(7) ? null : DateTime.Parse(reader.GetString(7)),
                    EndTime = reader.IsDBNull(8) ? null : DateTime.Parse(reader.GetString(8)),
                    ErrorMessage = reader.IsDBNull(9) ? null : reader.GetString(9),
                    StartPkValue = reader.IsDBNull(10) ? null : reader.GetInt64(10),
                    EndPkValue = reader.IsDBNull(11) ? null : reader.GetInt64(11)
                };
            }
            reader.Close();

            const string insertSql = @"
                INSERT INTO table_checkpoints (run_id, table_name, partition_key, status, rows_processed, total_rows, start_pk, end_pk)
                VALUES (@runId, @tableName, @partitionKey, @status, 0, @totalRows, @startPk, @endPk);
                SELECT last_insert_rowid();";

            using var insertCmd = new SqliteCommand(insertSql, _connection);
            insertCmd.Parameters.AddWithValue("@runId", runId);
            insertCmd.Parameters.AddWithValue("@tableName", tableName);
            insertCmd.Parameters.AddWithValue("@partitionKey", partitionKey);
            insertCmd.Parameters.AddWithValue("@status", MigrationStatus.Pending.ToString());
            insertCmd.Parameters.AddWithValue("@totalRows", totalRows);
            insertCmd.Parameters.AddWithValue("@startPk", startPk.HasValue ? startPk.Value : DBNull.Value);
            insertCmd.Parameters.AddWithValue("@endPk", endPk.HasValue ? endPk.Value : DBNull.Value);

            var id = Convert.ToInt32(insertCmd.ExecuteScalar());

            return new CheckpointRecord
            {
                Id = id,
                RunId = runId,
                TableName = tableName,
                PartitionKey = partitionKey,
                Status = MigrationStatus.Pending,
                RowsProcessed = 0,
                TotalRows = totalRows,
                StartPkValue = startPk,
                EndPkValue = endPk
            };
        }
    }

    public void UpdatePartitionProgress(int checkpointId, long rowsProcessed)
    {
        const string sql = @"
            UPDATE table_checkpoints
            SET rows_processed = @rowsProcessed,
                start_time = COALESCE(start_time, @now),
                status = @status
            WHERE id = @id";

        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@rowsProcessed", rowsProcessed);
            cmd.Parameters.AddWithValue("@now", DateTime.UtcNow.ToString("o"));
            cmd.Parameters.AddWithValue("@status", MigrationStatus.Running.ToString());
            cmd.Parameters.AddWithValue("@id", checkpointId);
            cmd.ExecuteNonQuery();
        }
    }

    public void CompletePartition(int checkpointId, long? finalRowsProcessed = null)
    {
        const string sql = @"
            UPDATE table_checkpoints
            SET status = @status,
                end_time = @endTime,
                rows_processed = COALESCE(@finalRowsProcessed, rows_processed)
            WHERE id = @id";

        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@status", MigrationStatus.Done.ToString());
            cmd.Parameters.AddWithValue("@endTime", DateTime.UtcNow.ToString("o"));
            cmd.Parameters.AddWithValue("@finalRowsProcessed", finalRowsProcessed.HasValue ? finalRowsProcessed.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@id", checkpointId);
            cmd.ExecuteNonQuery();
        }
    }

    public void FailPartition(int checkpointId, string errorMessage)
    {
        const string sql = @"
            UPDATE table_checkpoints
            SET status = @status, end_time = @endTime, error_message = @errorMessage
            WHERE id = @id";

        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@status", MigrationStatus.Failed.ToString());
            cmd.Parameters.AddWithValue("@endTime", DateTime.UtcNow.ToString("o"));
            cmd.Parameters.AddWithValue("@errorMessage", errorMessage);
            cmd.Parameters.AddWithValue("@id", checkpointId);
            cmd.ExecuteNonQuery();
        }
    }

    public List<CheckpointRecord> GetPendingPartitions(int runId)
    {
        const string sql = @"
            SELECT id, run_id, table_name, partition_key, status, rows_processed, total_rows,
                   start_time, end_time, error_message
            FROM table_checkpoints
            WHERE run_id = @runId AND status IN (@pending, @failed)";

        lock (_lock)
        {
            var partitions = new List<CheckpointRecord>();
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@runId", runId);
            cmd.Parameters.AddWithValue("@pending", MigrationStatus.Pending.ToString());
            cmd.Parameters.AddWithValue("@failed", MigrationStatus.Failed.ToString());

            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                partitions.Add(new CheckpointRecord
                {
                    Id = reader.GetInt32(0),
                    RunId = reader.GetInt32(1),
                    TableName = reader.GetString(2),
                    PartitionKey = reader.GetString(3),
                    Status = Enum.Parse<MigrationStatus>(reader.GetString(4)),
                    RowsProcessed = reader.GetInt64(5),
                    TotalRows = reader.GetInt64(6),
                    StartTime = reader.IsDBNull(7) ? null : DateTime.Parse(reader.GetString(7)),
                    EndTime = reader.IsDBNull(8) ? null : DateTime.Parse(reader.GetString(8)),
                    ErrorMessage = reader.IsDBNull(9) ? null : reader.GetString(9)
                });
            }

            return partitions;
        }
    }

    public List<(string tableName, string partitionKey, long? startPk, long? endPk)> GetFailedPartitionsWithPkRanges(int runId)
    {
        const string sql = @"
            SELECT table_name, partition_key, start_pk, end_pk
            FROM table_checkpoints
            WHERE run_id = @runId AND status = 'Failed' AND start_pk IS NOT NULL AND end_pk IS NOT NULL";

        lock (_lock)
        {
            var result = new List<(string, string, long?, long?)>();
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@runId", runId);
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                result.Add((
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetInt64(2),
                    reader.IsDBNull(3) ? null : reader.GetInt64(3)
                ));
            }
            return result;
        }
    }

    public void WriteProgressEvent(int runId, ProgressEvent evt)
    {
        const string sql = @"
            INSERT INTO progress_events
            (run_id, timestamp, table_name, partition_key, phase, status, rows_processed,
             total_rows, rows_per_second, message, warning)
            VALUES (@runId, @timestamp, @tableName, @partitionKey, @phase, @status,
                    @rowsProcessed, @totalRows, @rowsPerSecond, @message, @warning)";

        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@runId", runId);
            cmd.Parameters.AddWithValue("@timestamp", evt.Timestamp.ToString("o"));
            cmd.Parameters.AddWithValue("@tableName", evt.TableName);
            cmd.Parameters.AddWithValue("@partitionKey", evt.PartitionKey);
            cmd.Parameters.AddWithValue("@phase", evt.Phase);
            cmd.Parameters.AddWithValue("@status", evt.Status.ToString());
            cmd.Parameters.AddWithValue("@rowsProcessed", evt.RowsProcessed);
            cmd.Parameters.AddWithValue("@totalRows", evt.TotalRows);
            cmd.Parameters.AddWithValue("@rowsPerSecond", evt.RowsPerSecond);
            cmd.Parameters.AddWithValue("@message", evt.Message);
            cmd.Parameters.AddWithValue("@warning", (object?)evt.Warning ?? DBNull.Value);
            cmd.ExecuteNonQuery();
        }
    }

    public (int runId, DateTime startTime, MigrationConfig? config)? FindLastIncompleteRun()
    {
        const string sql = @"
            SELECT run_id, start_time, config_json
            FROM migration_runs
            WHERE status = 'RUNNING'
            ORDER BY run_id DESC
            LIMIT 1";

        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            using var reader = cmd.ExecuteReader();
            if (!reader.Read()) return null;

            var runId = reader.GetInt32(0);
            var startTime = DateTime.Parse(reader.GetString(1));
            MigrationConfig? cfg = null;
            try { cfg = JsonSerializer.Deserialize<MigrationConfig>(reader.GetString(2)); } catch { }
            return (runId, startTime, cfg);
        }
    }

    /// <summary>
    /// Last run that still has Pending/Failed/Running partitions (even if run was marked COMPLETED).
    /// Used by --continue-tables when the parent run already closed.
    /// </summary>
    public (int runId, DateTime startTime, MigrationConfig? config, string status)? FindLastRunWithIncompleteWork()
    {
        const string sql = @"
            SELECT r.run_id, r.start_time, r.config_json, r.status
            FROM migration_runs r
            WHERE r.status = 'RUNNING'
               OR EXISTS (
                    SELECT 1 FROM table_checkpoints t
                    WHERE t.run_id = r.run_id
                      AND t.status IN ('Pending', 'Failed', 'Running')
               )
            ORDER BY r.run_id DESC
            LIMIT 1";

        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            using var reader = cmd.ExecuteReader();
            if (!reader.Read()) return null;

            var runId = reader.GetInt32(0);
            var startTime = DateTime.Parse(reader.GetString(1));
            MigrationConfig? cfg = null;
            try { cfg = JsonSerializer.Deserialize<MigrationConfig>(reader.GetString(2)); } catch { }
            var status = reader.IsDBNull(3) ? "" : reader.GetString(3);
            return (runId, startTime, cfg, status);
        }
    }

    /// <summary>Tables that still have work left (Pending / Failed / Running partitions).</summary>
    public List<string> GetTablesNeedingWork(int runId)
    {
        const string sql = @"
            SELECT DISTINCT table_name
            FROM table_checkpoints
            WHERE run_id = @runId AND status IN ('Pending', 'Failed', 'Running')
            ORDER BY table_name";

        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@runId", runId);
            using var reader = cmd.ExecuteReader();
            var list = new List<string>();
            while (reader.Read())
                list.Add(reader.GetString(0));
            return list;
        }
    }

    public void ReopenRun(int runId)
    {
        lock (_lock)
        {
            try
            {
                using var cmd = new SqliteCommand(
                    "UPDATE migration_runs SET status = 'RUNNING', end_time = NULL WHERE run_id = @runId",
                    _connection);
                cmd.Parameters.AddWithValue("@runId", runId);
                cmd.ExecuteNonQuery();
            }
            catch (SqliteException)
            {
                using var fallback = new SqliteCommand(
                    "UPDATE migration_runs SET status = 'RUNNING' WHERE run_id = @runId",
                    _connection);
                fallback.Parameters.AddWithValue("@runId", runId);
                fallback.ExecuteNonQuery();
            }
        }
    }

    public int ResetInterruptedPartitions(int runId, IReadOnlyCollection<string>? tableNames = null)
    {
        lock (_lock)
        {
            if (tableNames == null || tableNames.Count == 0)
            {
                const string sql = @"
                    UPDATE table_checkpoints
                    SET status = 'Pending', error_message = 'Reset after interruption', start_time = NULL
                    WHERE run_id = @runId AND status = 'Running'";
                using var cmd = new SqliteCommand(sql, _connection);
                cmd.Parameters.AddWithValue("@runId", runId);
                return cmd.ExecuteNonQuery();
            }

            var total = 0;
            foreach (var table in tableNames.Where(t => !string.IsNullOrWhiteSpace(t)).Distinct(StringComparer.OrdinalIgnoreCase))
            {
                using var cmd = new SqliteCommand(@"
                    UPDATE table_checkpoints
                    SET status = 'Pending', error_message = 'Reset after interruption', start_time = NULL
                    WHERE run_id = @runId AND status = 'Running' AND table_name = @table", _connection);
                cmd.Parameters.AddWithValue("@runId", runId);
                cmd.Parameters.AddWithValue("@table", table);
                total += cmd.ExecuteNonQuery();
            }
            return total;
        }
    }

    /// <summary>
    /// Tables that have at least one Failed partition in the run.
    /// </summary>
    public List<string> GetTablesWithFailedPartitions(int runId)
    {
        const string sql = @"
            SELECT DISTINCT table_name
            FROM table_checkpoints
            WHERE run_id = @runId AND status = 'Failed'
            ORDER BY table_name";

        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@runId", runId);
            using var reader = cmd.ExecuteReader();
            var list = new List<string>();
            while (reader.Read())
                list.Add(reader.GetString(0));
            return list;
        }
    }

    /// <summary>
    /// Re-queue Failed partitions for --resume / --retry-failed.
    /// When <paramref name="tableNames"/> is null/empty, all Failed partitions in the run are reset.
    /// Otherwise only the listed tables are touched.
    /// </summary>
    public int ResetFailedPartitions(int runId, IReadOnlyCollection<string>? tableNames = null)
    {
        lock (_lock)
        {
            if (tableNames == null || tableNames.Count == 0)
            {
                const string sqlAll = @"
                    UPDATE table_checkpoints
                    SET status = 'Pending',
                        error_message = 'Reset failed partition for resume',
                        start_time = NULL,
                        end_time = NULL,
                        rows_processed = 0
                    WHERE run_id = @runId AND status = 'Failed'";
                using var cmd = new SqliteCommand(sqlAll, _connection);
                cmd.Parameters.AddWithValue("@runId", runId);
                return cmd.ExecuteNonQuery();
            }

            var total = 0;
            foreach (var table in tableNames.Where(t => !string.IsNullOrWhiteSpace(t)).Distinct(StringComparer.OrdinalIgnoreCase))
            {
                using var cmd = new SqliteCommand(@"
                    UPDATE table_checkpoints
                    SET status = 'Pending',
                        error_message = 'Reset failed partition for resume',
                        start_time = NULL,
                        end_time = NULL,
                        rows_processed = 0
                    WHERE run_id = @runId AND status = 'Failed' AND table_name = @table", _connection);
                cmd.Parameters.AddWithValue("@runId", runId);
                cmd.Parameters.AddWithValue("@table", table);
                total += cmd.ExecuteNonQuery();
            }
            return total;
        }
    }

    public List<(string tableName, int done, int pending, int failed, int total)> GetRunTableSummary(int runId)
    {
        const string sql = @"
            SELECT table_name,
                   SUM(CASE WHEN status = 'Done'    THEN 1 ELSE 0 END) AS done,
                   SUM(CASE WHEN status = 'Pending' THEN 1 ELSE 0 END) AS pending,
                   SUM(CASE WHEN status = 'Failed'  THEN 1 ELSE 0 END) AS failed,
                   COUNT(*) AS total
            FROM table_checkpoints
            WHERE run_id = @runId
            GROUP BY table_name
            ORDER BY table_name";

        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@runId", runId);
            using var reader = cmd.ExecuteReader();

            var result = new List<(string, int, int, int, int)>();
            while (reader.Read())
                result.Add((reader.GetString(0), reader.GetInt32(1), reader.GetInt32(2), reader.GetInt32(3), reader.GetInt32(4)));
            return result;
        }
    }

    /// <summary>
    /// Belirtilen tablo için bu run'daki tüm partition kayıtlarını siler.
    /// Recreate / Truncate modunda tabloyu sıfırdan başlatmadan önce çağrılır.
    /// </summary>
    public void ResetTablePartitions(int runId, string tableName)
    {
        const string sql = "DELETE FROM table_checkpoints WHERE run_id = @runId AND table_name = @tableName";
        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@runId", runId);
            cmd.Parameters.AddWithValue("@tableName", tableName);
            var deleted = cmd.ExecuteNonQuery();
            Log.Information("Reset checkpoint: deleted {Count} partition record(s) for [{Table}]", deleted, tableName);
        }
    }

    /// <summary>
    /// Bu run'da checkpoint kaydı olan (daha önce başlatılmış) tablo adlarını döner.
    /// </summary>
    public HashSet<string> GetTablesWithCheckpoint(int runId)
    {
        const string sql = "SELECT DISTINCT table_name FROM table_checkpoints WHERE run_id = @runId";
        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@runId", runId);
            using var reader = cmd.ExecuteReader();
            var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            while (reader.Read()) result.Add(reader.GetString(0));
            return result;
        }
    }

    public void Dispose()
    {
        _connection?.Dispose();
    }
}
