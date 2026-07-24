using Microsoft.Data.Sqlite;
using MigrationShared.Models;
using System.Text.Json;

namespace MigrationEngine.Checkpoint;

public class ExtendedCheckpointRepository
{
    private readonly string _connectionString;

    public ExtendedCheckpointRepository(string sqlitePath)
    {
        _connectionString = $"Data Source={sqlitePath}";
        InitializeExtendedSchema();
    }

    private void InitializeExtendedSchema()
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        foreach (var schema in ExtendedCheckpointSchema.GetAllExtendedSchemas())
        {
            using var cmd = new SqliteCommand(schema, connection);
            cmd.ExecuteNonQuery();
        }
    }

    #region Migration History

    public int CreateMigrationHistory(string migrationName, string sourceConn, string targetConn, 
        string sourceSchema, int tableCount, string configJson, int runId)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = @"INSERT INTO migration_history 
            (run_id, migration_name, source_connection, target_connection, source_schema, 
             table_count, started_at, status, config_json)
            VALUES (@runId, @name, @source, @target, @schema, @tableCount, @startedAt, @status, @config);
            SELECT last_insert_rowid();";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);
        cmd.Parameters.AddWithValue("@name", migrationName);
        cmd.Parameters.AddWithValue("@source", MaskPassword(sourceConn));
        cmd.Parameters.AddWithValue("@target", MaskPassword(targetConn));
        cmd.Parameters.AddWithValue("@schema", sourceSchema);
        cmd.Parameters.AddWithValue("@tableCount", tableCount);
        cmd.Parameters.AddWithValue("@startedAt", DateTime.UtcNow.ToString("O"));
        cmd.Parameters.AddWithValue("@status", "RUNNING");
        cmd.Parameters.AddWithValue("@config", configJson);

        return Convert.ToInt32(cmd.ExecuteScalar()!);
    }

    public void CompleteMigrationHistory(int historyId, long totalRows)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = @"UPDATE migration_history 
            SET completed_at = @completedAt, 
                duration_seconds = @duration, 
                total_rows = @totalRows,
                status = 'COMPLETED'
            WHERE id = @id";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@id", historyId);
        cmd.Parameters.AddWithValue("@completedAt", DateTime.UtcNow.ToString("O"));
        
        var startedAt = GetHistoryStartTime(historyId);
        var duration = (int)(DateTime.UtcNow - startedAt).TotalSeconds;
        cmd.Parameters.AddWithValue("@duration", duration);
        cmd.Parameters.AddWithValue("@totalRows", totalRows);

        cmd.ExecuteNonQuery();
    }

    public List<MigrationHistory> GetMigrationHistory(int limit = 50)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = @"SELECT * FROM migration_history 
            ORDER BY started_at DESC LIMIT @limit";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@limit", limit);

        var history = new List<MigrationHistory>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            history.Add(new MigrationHistory
            {
                Id = reader.GetInt32(0),
                RunId = reader.GetInt32(1),
                MigrationName = reader.GetString(2),
                SourceConnection = reader.GetString(3),
                TargetConnection = reader.GetString(4),
                SourceSchema = reader.GetString(5),
                TableCount = reader.GetInt32(6),
                TotalRows = reader.IsDBNull(7) ? 0 : reader.GetInt64(7),
                StartedAt = DateTime.Parse(reader.GetString(8)),
                CompletedAt = reader.IsDBNull(9) ? null : DateTime.Parse(reader.GetString(9)),
                DurationSeconds = reader.IsDBNull(10) ? null : reader.GetInt32(10),
                Status = reader.GetString(11),
                ConfigJson = reader.GetString(12)
            });
        }

        return history;
    }

    private DateTime GetHistoryStartTime(int historyId)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = "SELECT started_at FROM migration_history WHERE id = @id";
        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@id", historyId);

        var result = cmd.ExecuteScalar();
        return DateTime.Parse(result!.ToString()!);
    }

    #endregion

    #region Connection Profiles

    public int SaveConnectionProfile(ConnectionProfile profile)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();
        ConnectionProfileSchemaMigrator.EnsureColumns(connection);

        var sql = @"INSERT OR REPLACE INTO connection_profiles
            (profile_name, connection_type, host, port, service_name, database_name, 
             username, schema_name, auth_type, trust_cert, connection_string, created_at, use_count)
            VALUES (@name, @type, @host, @port, @service, @database, @username, @schema, 
                    @authType, @trustCert, @connectionString, @createdAt, @useCount);
            SELECT last_insert_rowid();";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@name", profile.ProfileName);
        cmd.Parameters.AddWithValue("@type", profile.ConnectionType);
        cmd.Parameters.AddWithValue("@host", profile.Host ?? (object)DBNull.Value);
        cmd.Parameters.AddWithValue("@port", profile.Port ?? (object)DBNull.Value);
        cmd.Parameters.AddWithValue("@service", profile.ServiceName ?? (object)DBNull.Value);
        cmd.Parameters.AddWithValue("@database", profile.DatabaseName ?? (object)DBNull.Value);
        cmd.Parameters.AddWithValue("@username", profile.Username ?? (object)DBNull.Value);
        cmd.Parameters.AddWithValue("@schema", profile.SchemaName ?? (object)DBNull.Value);
        cmd.Parameters.AddWithValue("@authType", profile.AuthType ?? (object)DBNull.Value);
        cmd.Parameters.AddWithValue("@trustCert", profile.TrustCert ? 1 : 0);
        cmd.Parameters.AddWithValue("@connectionString", profile.ConnectionString ?? (object)DBNull.Value);
        cmd.Parameters.AddWithValue("@createdAt", DateTime.UtcNow.ToString("O"));
        cmd.Parameters.AddWithValue("@useCount", profile.UseCount);

        return Convert.ToInt32(cmd.ExecuteScalar()!);
    }

    public List<ConnectionProfile> GetConnectionProfiles(string? connectionType = null)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();
        ConnectionProfileSchemaMigrator.EnsureColumns(connection);

        var sql = connectionType == null
            ? @"SELECT id, profile_name, connection_type, host, port, service_name, database_name,
                      username, schema_name, auth_type, trust_cert, connection_string, created_at, last_used_at, use_count,
                      COALESCE(is_deleted, 0), deleted_at
               FROM connection_profiles
               WHERE COALESCE(is_deleted, 0) = 0
               ORDER BY last_used_at DESC, profile_name"
            : @"SELECT id, profile_name, connection_type, host, port, service_name, database_name,
                      username, schema_name, auth_type, trust_cert, connection_string, created_at, last_used_at, use_count,
                      COALESCE(is_deleted, 0), deleted_at
               FROM connection_profiles
               WHERE connection_type = @type AND COALESCE(is_deleted, 0) = 0
               ORDER BY last_used_at DESC, profile_name";

        using var cmd = new SqliteCommand(sql, connection);
        if (connectionType != null)
            cmd.Parameters.AddWithValue("@type", connectionType);

        var profiles = new List<ConnectionProfile>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            profiles.Add(new ConnectionProfile
            {
                Id = reader.GetInt32(0),
                ProfileName = reader.GetString(1),
                ConnectionType = reader.GetString(2),
                Host = reader.IsDBNull(3) ? null : reader.GetString(3),
                Port = reader.IsDBNull(4) ? null : reader.GetString(4),
                ServiceName = reader.IsDBNull(5) ? null : reader.GetString(5),
                DatabaseName = reader.IsDBNull(6) ? null : reader.GetString(6),
                Username = reader.IsDBNull(7) ? null : reader.GetString(7),
                SchemaName = reader.IsDBNull(8) ? null : reader.GetString(8),
                AuthType = reader.IsDBNull(9) ? null : reader.GetString(9),
                TrustCert = reader.GetInt32(10) == 1,
                ConnectionString = reader.IsDBNull(11) ? null : reader.GetString(11),
                CreatedAt = DateTime.Parse(reader.GetString(12)),
                LastUsedAt = reader.IsDBNull(13) ? null : DateTime.Parse(reader.GetString(13)),
                UseCount = reader.GetInt32(14),
                IsDeleted = reader.GetInt32(15) == 1,
                DeletedAt = reader.IsDBNull(16) ? null : DateTime.Parse(reader.GetString(16))
            });
        }

        return profiles;
    }

    public void UpdateProfileUsage(string profileName)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = @"UPDATE connection_profiles 
            SET last_used_at = @lastUsed, use_count = use_count + 1 
            WHERE profile_name = @name AND COALESCE(is_deleted, 0) = 0";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@name", profileName);
        cmd.Parameters.AddWithValue("@lastUsed", DateTime.UtcNow.ToString("O"));
        cmd.ExecuteNonQuery();
    }

    #endregion

    #region Thread Monitoring

    public void UpdateThreadMonitoring(int runId, int partitionId, string tableName, 
        int threadId, string status, long rowsProcessed, long totalRows, double currentSpeed)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        DateTime? eta = null;
        if (currentSpeed > 0 && rowsProcessed < totalRows)
        {
            var remainingRows = totalRows - rowsProcessed;
            var secondsRemaining = remainingRows / currentSpeed;
            eta = DateTime.UtcNow.AddSeconds(secondsRemaining);
        }

        var sql = @"INSERT OR REPLACE INTO thread_monitoring 
            (run_id, partition_id, table_name, thread_id, status, started_at, last_heartbeat, 
             rows_processed, total_rows, current_speed, estimated_completion)
            VALUES (@runId, @partitionId, @tableName, @threadId, @status, 
                    COALESCE((SELECT started_at FROM thread_monitoring WHERE partition_id = @partitionId), @now),
                    @now, @rowsProcessed, @totalRows, @speed, @eta)";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);
        cmd.Parameters.AddWithValue("@partitionId", partitionId);
        cmd.Parameters.AddWithValue("@tableName", tableName);
        cmd.Parameters.AddWithValue("@threadId", threadId);
        cmd.Parameters.AddWithValue("@status", status);
        cmd.Parameters.AddWithValue("@now", DateTime.UtcNow.ToString("O"));
        cmd.Parameters.AddWithValue("@rowsProcessed", rowsProcessed);
        cmd.Parameters.AddWithValue("@totalRows", totalRows);
        cmd.Parameters.AddWithValue("@speed", currentSpeed);
        cmd.Parameters.AddWithValue("@eta", eta?.ToString("O") ?? (object)DBNull.Value);

        cmd.ExecuteNonQuery();
    }

    public List<ThreadMonitoring> GetActiveThreads(int runId)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = @"SELECT * FROM thread_monitoring 
            WHERE run_id = @runId AND status = 'RUNNING'
            ORDER BY table_name, partition_id";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);

        var threads = new List<ThreadMonitoring>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            threads.Add(new ThreadMonitoring
            {
                Id = reader.GetInt32(0),
                RunId = reader.GetInt32(1),
                PartitionId = reader.GetInt32(2),
                TableName = reader.GetString(3),
                ThreadId = reader.GetInt32(4),
                Status = reader.GetString(5),
                StartedAt = DateTime.Parse(reader.GetString(6)),
                LastHeartbeat = DateTime.Parse(reader.GetString(7)),
                RowsProcessed = reader.GetInt64(8),
                TotalRows = reader.GetInt64(9),
                CurrentSpeed = reader.GetDouble(10),
                EstimatedCompletion = reader.IsDBNull(11) ? null : DateTime.Parse(reader.GetString(11))
            });
        }

        return threads;
    }

    #endregion

    #region Metrics

    public void RecordMetric(int runId, string tableName, string metricType, double value)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = @"INSERT INTO migration_metrics 
            (run_id, table_name, metric_type, metric_value, recorded_at)
            VALUES (@runId, @tableName, @metricType, @value, @recordedAt)";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);
        cmd.Parameters.AddWithValue("@tableName", tableName);
        cmd.Parameters.AddWithValue("@metricType", metricType);
        cmd.Parameters.AddWithValue("@value", value);
        cmd.Parameters.AddWithValue("@recordedAt", DateTime.UtcNow.ToString("O"));

        cmd.ExecuteNonQuery();
    }

    public List<MigrationMetric> GetMetrics(int runId, string? tableName = null, string? metricType = null)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = "SELECT * FROM migration_metrics WHERE run_id = @runId";
        if (tableName != null) sql += " AND table_name = @tableName";
        if (metricType != null) sql += " AND metric_type = @metricType";
        sql += " ORDER BY recorded_at";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);
        if (tableName != null) cmd.Parameters.AddWithValue("@tableName", tableName);
        if (metricType != null) cmd.Parameters.AddWithValue("@metricType", metricType);

        var metrics = new List<MigrationMetric>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            metrics.Add(new MigrationMetric
            {
                Id = reader.GetInt32(0),
                RunId = reader.GetInt32(1),
                TableName = reader.GetString(2),
                MetricType = reader.GetString(3),
                MetricValue = reader.GetDouble(4),
                RecordedAt = DateTime.Parse(reader.GetString(5))
            });
        }

        return metrics;
    }

    #endregion

    #region Performance Summary

    public void SavePerformanceSummary(PerformanceSummary summary)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = @"INSERT OR REPLACE INTO performance_summary 
            (run_id, total_duration_seconds, avg_rows_per_second, peak_rows_per_second,
             total_bytes_transferred, total_errors, total_warnings, parallel_efficiency,
             schema_phase_duration, load_phase_duration, index_phase_duration, validation_phase_duration)
            VALUES (@runId, @duration, @avgSpeed, @peakSpeed, @bytes, @errors, @warnings, @efficiency,
                    @schemaDuration, @loadDuration, @indexDuration, @validationDuration)";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", summary.RunId);
        cmd.Parameters.AddWithValue("@duration", summary.TotalDurationSeconds);
        cmd.Parameters.AddWithValue("@avgSpeed", summary.AvgRowsPerSecond);
        cmd.Parameters.AddWithValue("@peakSpeed", summary.PeakRowsPerSecond);
        cmd.Parameters.AddWithValue("@bytes", summary.TotalBytesTransferred);
        cmd.Parameters.AddWithValue("@errors", summary.TotalErrors);
        cmd.Parameters.AddWithValue("@warnings", summary.TotalWarnings);
        cmd.Parameters.AddWithValue("@efficiency", summary.ParallelEfficiency);
        cmd.Parameters.AddWithValue("@schemaDuration", summary.SchemaPhaseDuration);
        cmd.Parameters.AddWithValue("@loadDuration", summary.LoadPhaseDuration);
        cmd.Parameters.AddWithValue("@indexDuration", summary.IndexPhaseDuration);
        cmd.Parameters.AddWithValue("@validationDuration", summary.ValidationPhaseDuration);

        cmd.ExecuteNonQuery();
    }

    public PerformanceSummary? GetPerformanceSummary(int runId)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = "SELECT * FROM performance_summary WHERE run_id = @runId";
        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);

        using var reader = cmd.ExecuteReader();
        if (reader.Read())
        {
            return new PerformanceSummary
            {
                Id = reader.GetInt32(0),
                RunId = reader.GetInt32(1),
                TotalDurationSeconds = reader.GetInt32(2),
                AvgRowsPerSecond = reader.GetDouble(3),
                PeakRowsPerSecond = reader.GetDouble(4),
                TotalBytesTransferred = reader.GetInt64(5),
                TotalErrors = reader.GetInt32(6),
                TotalWarnings = reader.GetInt32(7),
                ParallelEfficiency = reader.GetDouble(8),
                SchemaPhaseDuration = reader.GetInt32(9),
                LoadPhaseDuration = reader.GetInt32(10),
                IndexPhaseDuration = reader.GetInt32(11),
                ValidationPhaseDuration = reader.GetInt32(12)
            };
        }

        return null;
    }

    #endregion

    #region Comparison

    public void CreateComparison(int runId1, int runId2)
    {
        var summary1 = GetPerformanceSummary(runId1);
        var summary2 = GetPerformanceSummary(runId2);

        if (summary1 == null || summary2 == null) return;

        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        SaveComparisonMetric(connection, runId1, runId2, "avg_throughput", 
            summary1.AvgRowsPerSecond, summary2.AvgRowsPerSecond);
        SaveComparisonMetric(connection, runId1, runId2, "peak_throughput", 
            summary1.PeakRowsPerSecond, summary2.PeakRowsPerSecond);
        SaveComparisonMetric(connection, runId1, runId2, "total_duration", 
            summary1.TotalDurationSeconds, summary2.TotalDurationSeconds);
        SaveComparisonMetric(connection, runId1, runId2, "parallel_efficiency", 
            summary1.ParallelEfficiency, summary2.ParallelEfficiency);
    }

    private void SaveComparisonMetric(SqliteConnection connection, int runId1, int runId2, 
        string metric, double value1, double value2)
    {
        var improvement = ((value2 - value1) / value1) * 100;

        var sql = @"INSERT INTO comparison_snapshots 
            (run_id_1, run_id_2, comparison_metric, run_1_value, run_2_value, improvement_percent, created_at)
            VALUES (@runId1, @runId2, @metric, @value1, @value2, @improvement, @createdAt)";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId1", runId1);
        cmd.Parameters.AddWithValue("@runId2", runId2);
        cmd.Parameters.AddWithValue("@metric", metric);
        cmd.Parameters.AddWithValue("@value1", value1);
        cmd.Parameters.AddWithValue("@value2", value2);
        cmd.Parameters.AddWithValue("@improvement", improvement);
        cmd.Parameters.AddWithValue("@createdAt", DateTime.UtcNow.ToString("O"));

        cmd.ExecuteNonQuery();
    }

    #endregion

    #region Error Logging

    public int LogError(int runId, string? tableName, int? partitionId, string errorType, 
        string errorMessage, string? stackTrace, int retryAttempt = 0)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = @"INSERT INTO error_log 
            (run_id, table_name, partition_id, error_type, error_message, stack_trace, 
             occurred_at, retry_attempt, resolved)
            VALUES (@runId, @tableName, @partitionId, @errorType, @errorMessage, @stackTrace, 
                    @occurredAt, @retryAttempt, 0);
            SELECT last_insert_rowid();";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);
        cmd.Parameters.AddWithValue("@tableName", tableName ?? (object)DBNull.Value);
        cmd.Parameters.AddWithValue("@partitionId", partitionId ?? (object)DBNull.Value);
        cmd.Parameters.AddWithValue("@errorType", errorType);
        cmd.Parameters.AddWithValue("@errorMessage", errorMessage);
        cmd.Parameters.AddWithValue("@stackTrace", stackTrace ?? (object)DBNull.Value);
        cmd.Parameters.AddWithValue("@occurredAt", DateTime.UtcNow.ToString("O"));
        cmd.Parameters.AddWithValue("@retryAttempt", retryAttempt);

        return Convert.ToInt32(cmd.ExecuteScalar()!);
    }

    public void MarkErrorResolved(int errorId)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = @"UPDATE error_log SET resolved = 1 WHERE id = @id";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@id", errorId);
        cmd.ExecuteNonQuery();
    }

    public List<ErrorLog> GetErrorsByRunId(int runId)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = @"SELECT * FROM error_log 
            WHERE run_id = @runId 
            ORDER BY occurred_at DESC";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);

        var errors = new List<ErrorLog>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            errors.Add(new ErrorLog
            {
                Id = reader.GetInt32(0),
                RunId = reader.GetInt32(1),
                TableName = reader.IsDBNull(2) ? null : reader.GetString(2),
                PartitionId = reader.IsDBNull(3) ? null : reader.GetInt32(3),
                ErrorType = reader.GetString(4),
                ErrorMessage = reader.GetString(5),
                StackTrace = reader.IsDBNull(6) ? null : reader.GetString(6),
                OccurredAt = DateTime.Parse(reader.GetString(7)),
                RetryAttempt = reader.GetInt32(8),
                Resolved = reader.GetInt32(9) == 1
            });
        }

        return errors;
    }

    public List<ErrorLog> GetErrorsByTable(int runId, string tableName)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = @"SELECT * FROM error_log 
            WHERE run_id = @runId AND table_name = @tableName 
            ORDER BY occurred_at DESC";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);
        cmd.Parameters.AddWithValue("@tableName", tableName);

        var errors = new List<ErrorLog>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            errors.Add(new ErrorLog
            {
                Id = reader.GetInt32(0),
                RunId = reader.GetInt32(1),
                TableName = reader.IsDBNull(2) ? null : reader.GetString(2),
                PartitionId = reader.IsDBNull(3) ? null : reader.GetInt32(3),
                ErrorType = reader.GetString(4),
                ErrorMessage = reader.GetString(5),
                StackTrace = reader.IsDBNull(6) ? null : reader.GetString(6),
                OccurredAt = DateTime.Parse(reader.GetString(7)),
                RetryAttempt = reader.GetInt32(8),
                Resolved = reader.GetInt32(9) == 1
            });
        }

        return errors;
    }

    public Dictionary<string, int> GetErrorStatsByType(int runId)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = @"SELECT error_type, COUNT(*) as count 
            FROM error_log 
            WHERE run_id = @runId 
            GROUP BY error_type
            ORDER BY count DESC";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);

        var stats = new Dictionary<string, int>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            stats[reader.GetString(0)] = reader.GetInt32(1);
        }

        return stats;
    }

    public void InsertValidationGateResults(int runId, string phase, IReadOnlyList<ValidationResult> results)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();
        using var tx = connection.BeginTransaction();

        const string sql = @"
            INSERT INTO validation_gates 
            (run_id, table_name, gate_type, phase, passed, oracle_value, mssql_value, message, evaluated_at)
            VALUES (@runId, @tableName, @gateType, @phase, @passed, @oracleValue, @mssqlValue, @message, @evaluatedAt)";

        foreach (var r in results)
        {
            foreach (var g in r.Gates)
            {
                using var cmd = new SqliteCommand(sql, connection, tx);
                cmd.Parameters.AddWithValue("@runId", runId);
                cmd.Parameters.AddWithValue("@tableName", r.TableName);
                cmd.Parameters.AddWithValue("@gateType", g.GateType);
                cmd.Parameters.AddWithValue("@phase", phase);
                cmd.Parameters.AddWithValue("@passed", g.Passed ? 1 : 0);
                cmd.Parameters.AddWithValue("@oracleValue", (object?)g.OracleValue ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@mssqlValue", (object?)g.MssqlValue ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@message", (object?)g.Detail ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@evaluatedAt", DateTime.UtcNow.ToString("O"));
                cmd.ExecuteNonQuery();
            }
        }

        tx.Commit();
    }

    public List<ValidationGateRecord> GetValidationGatesForRun(int runId)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        const string sql = @"
            SELECT id, run_id, table_name, gate_type, phase, passed, oracle_value, mssql_value, message, evaluated_at
            FROM validation_gates
            WHERE run_id = @runId
            ORDER BY table_name, id";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);

        var list = new List<ValidationGateRecord>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            list.Add(new ValidationGateRecord
            {
                Id = reader.GetInt32(0),
                RunId = reader.GetInt32(1),
                TableName = reader.GetString(2),
                GateType = reader.GetString(3),
                Phase = reader.GetString(4),
                Passed = reader.GetInt32(5) == 1,
                OracleValue = reader.IsDBNull(6) ? null : reader.GetString(6),
                MssqlValue = reader.IsDBNull(7) ? null : reader.GetString(7),
                Message = reader.IsDBNull(8) ? null : reader.GetString(8),
                EvaluatedAt = DateTime.Parse(reader.GetString(9), null, System.Globalization.DateTimeStyles.RoundtripKind)
            });
        }

        return list;
    }

    public void FailMigrationHistory(int historyId, string errorReason)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        var sql = @"UPDATE migration_history 
            SET completed_at = @completedAt, 
                duration_seconds = @duration, 
                status = 'FAILED'
            WHERE id = @id";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@id", historyId);
        cmd.Parameters.AddWithValue("@completedAt", DateTime.UtcNow.ToString("O"));
        
        var startedAt = GetHistoryStartTime(historyId);
        var duration = (int)(DateTime.UtcNow - startedAt).TotalSeconds;
        cmd.Parameters.AddWithValue("@duration", duration);

        cmd.ExecuteNonQuery();
    }

    #endregion

    private string MaskPassword(string connectionString)
    {
        return System.Text.RegularExpressions.Regex.Replace(
            connectionString, 
            @"(Password|Pwd)=[^;]+", 
            "$1=***", 
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
    }
}
