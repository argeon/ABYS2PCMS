using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Options;
using MigrationShared.Enums;
using MigrationShared.Models;

namespace MigrationWeb.Services;

public class DashboardDataService
{
    private readonly string _connectionString;
    private readonly ILogger<DashboardDataService> _logger;

    public DashboardDataService(IOptions<CheckpointOptions> options, ILogger<DashboardDataService> logger)
    {
        var dbPath = options.Value.SqlitePath;
        _connectionString = $"Data Source={dbPath};Mode=ReadOnly";
        _logger = logger;
    }

    public async Task<MigrationSummary?> GetCurrentSummary()
    {
        try
        {
            if (!File.Exists(GetDbPath()))
                return null;

            using var connection = new SqliteConnection(_connectionString);
            await connection.OpenAsync();

            // table_checkpoints = partition satırı; özet sayılar tablo bazında türetilir.
            const string sql = @"
                WITH run AS (SELECT MAX(run_id) AS rid FROM migration_runs),
                tc AS (
                    SELECT * FROM table_checkpoints WHERE run_id = (SELECT rid FROM run)
                ),
                per_table AS (
                    SELECT
                        table_name,
                        MAX(CASE WHEN status = 'Failed' THEN 1 ELSE 0 END) AS has_fail,
                        MAX(CASE WHEN status = 'Running' THEN 1 ELSE 0 END) AS has_run,
                        COUNT(*) AS n_parts,
                        SUM(CASE WHEN status IN ('Done','Skipped') THEN 1 ELSE 0 END) AS n_done_skip
                    FROM tc
                    GROUP BY table_name
                ),
                cls AS (
                    SELECT
                        table_name,
                        CASE
                            WHEN has_fail = 1 THEN 'Failed'
                            WHEN has_run = 1 THEN 'Running'
                            WHEN n_done_skip = n_parts AND n_parts > 0 THEN 'Completed'
                            ELSE 'Pending'
                        END AS bucket
                    FROM per_table
                ),
                tbl_counts AS (
                    SELECT
                        COUNT(*) AS total_tables,
                        COALESCE(SUM(CASE WHEN bucket = 'Completed' THEN 1 ELSE 0 END), 0) AS completed_tables,
                        COALESCE(SUM(CASE WHEN bucket = 'Running' THEN 1 ELSE 0 END), 0) AS running_tables,
                        COALESCE(SUM(CASE WHEN bucket = 'Pending' THEN 1 ELSE 0 END), 0) AS pending_tables,
                        COALESCE(SUM(CASE WHEN bucket = 'Failed' THEN 1 ELSE 0 END), 0) AS failed_tables
                    FROM cls
                ),
                row_totals AS (
                    SELECT
                        COALESCE(SUM(rows_processed), 0) AS total_rows_processed,
                        COALESCE(SUM(total_rows), 0) AS total_rows_expected
                    FROM tc
                )
                SELECT
                    mr.run_id,
                    mr.start_time,
                    mr.status,
                    COALESCE(k.total_tables, 0),
                    COALESCE(k.completed_tables, 0),
                    COALESCE(k.running_tables, 0),
                    COALESCE(k.pending_tables, 0),
                    COALESCE(k.failed_tables, 0),
                    rt.total_rows_processed,
                    rt.total_rows_expected
                FROM migration_runs mr
                CROSS JOIN tbl_counts k
                CROSS JOIN row_totals rt
                WHERE mr.run_id = (SELECT rid FROM run)";

            using var cmd = new SqliteCommand(sql, connection);

            int runId;
            DateTime startTime;
            string mrStatus;
            int total;
            int completed;
            int running;
            int pending;
            int failed;
            long totalRowsProcessed;
            long totalRowsExpected;

            await using (var reader = await cmd.ExecuteReaderAsync())
            {
                if (!await reader.ReadAsync())
                    return null;

                runId = reader.GetInt32(0);
                startTime = TryReadDateTime(reader, 1) ?? DateTime.UtcNow;
                mrStatus = reader.GetString(2);
                total = reader.GetInt32(3);
                completed = reader.GetInt32(4);
                running = reader.GetInt32(5);
                pending = reader.GetInt32(6);
                failed = reader.GetInt32(7);
                totalRowsProcessed = reader.GetInt64(8);
                totalRowsExpected = reader.GetInt64(9);
            }

            var elapsed = DateTime.UtcNow - startTime;
            var rowsPerSecond = await GetCurrentThroughputAsync(connection);
            
            // Calculate estimated remaining time
            TimeSpan? estimatedRemaining = null;
            if (rowsPerSecond > 0 && totalRowsExpected > totalRowsProcessed)
            {
                var remainingRows = totalRowsExpected - totalRowsProcessed;
                var remainingSeconds = remainingRows / rowsPerSecond;
                estimatedRemaining = TimeSpan.FromSeconds(remainingSeconds);
            }
            
            // Calculate estimated completion time
            DateTime? estimatedCompletionTime = null;
            if (estimatedRemaining.HasValue && estimatedRemaining.Value.TotalSeconds > 0)
            {
                estimatedCompletionTime = DateTime.Now.Add(estimatedRemaining.Value);
            }

            _logger.LogDebug(
                "Migration Summary - RunId: {RunId}, Source: {Source:N0}, Loaded: {Loaded:N0}, Match: {Match:P2}, Throughput: {Throughput:N0} rows/s",
                runId, totalRowsExpected, totalRowsProcessed, 
                totalRowsExpected > 0 ? (double)totalRowsProcessed / totalRowsExpected : 0,
                rowsPerSecond);

            return new MigrationSummary
            {
                RunId = runId,
                StartTime = startTime,
                Status = ParseStoredStatus(mrStatus),
                TotalTables = total,
                CompletedTables = completed,
                RunningTables = running,
                PendingTables = pending,
                FailedTables = failed,
                TotalRowsProcessed = totalRowsProcessed,
                TotalRowsExpected = totalRowsExpected,
                TotalRowsSource = totalRowsExpected,  // Oracle (kaynak)
                TotalRowsLoaded = totalRowsProcessed,  // MSSQL (hedef)
                OverallPercentComplete = total > 0 ? completed * 100.0 / total : 0,
                ElapsedTime = elapsed,
                EstimatedRemaining = estimatedRemaining,
                EstimatedCompletionTime = estimatedCompletionTime,
                CurrentRowsPerSecond = rowsPerSecond
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving migration summary");
            return null;
        }
    }

    private async Task<double> GetCurrentThroughputAsync(SqliteConnection connection)
    {
        const string sql = @"
            SELECT AVG(rows_per_second) 
            FROM progress_events 
            WHERE timestamp >= datetime('now', '-10 seconds') 
            AND rows_per_second > 0";

        using var cmd = new SqliteCommand(sql, connection);
        var result = await cmd.ExecuteScalarAsync();
        return result != null && result != DBNull.Value ? Convert.ToDouble(result) : 0;
    }

    public async Task<List<TableStatus>> GetTableStatuses()
    {
        try
        {
            if (!File.Exists(GetDbPath()))
                return new List<TableStatus>();

            using var connection = new SqliteConnection(_connectionString);
            await connection.OpenAsync();

            const string sql = @"
                SELECT 
                    table_name,
                    status,
                    SUM(rows_processed) as rows_loaded,
                    SUM(total_rows) as total_rows,
                    MIN(start_time) as start_time,
                    MAX(end_time) as end_time,
                    MAX(error_message) as error_message
                FROM table_checkpoints
                WHERE run_id = (SELECT MAX(run_id) FROM migration_runs)
                GROUP BY table_name, status
                ORDER BY table_name";

            var statuses = new List<TableStatus>();
            using var cmd = new SqliteCommand(sql, connection);
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                var status = new TableStatus
                {
                    TableName = reader.GetString(0),
                    Status = ParseStoredStatus(reader.GetString(1)),
                    RowsLoaded = reader.GetInt64(2),
                    TotalRows = reader.GetInt64(3),
                    StartTime = reader.IsDBNull(4) ? null : DateTime.Parse(reader.GetString(4)),
                    EndTime = reader.IsDBNull(5) ? null : DateTime.Parse(reader.GetString(5)),
                    ErrorMessage = reader.IsDBNull(6) ? null : reader.GetString(6),
                    Phase = MigrationPhase.Load
                };

                statuses.Add(status);
            }

            return statuses;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving table statuses");
            return new List<TableStatus>();
        }
    }

    /// <summary>
    /// All partition checkpoints for the latest run (one row per partition for live progress).
    /// </summary>
    public async Task<List<PartitionStatus>> GetPartitionStatuses()
    {
        try
        {
            if (!File.Exists(GetDbPath()))
                return new List<PartitionStatus>();

            using var connection = new SqliteConnection(_connectionString);
            await connection.OpenAsync();

            const string sql = @"
                SELECT 
                    id,
                    table_name,
                    partition_key,
                    status,
                    rows_processed,
                    total_rows,
                    start_time,
                    end_time,
                    error_message
                FROM table_checkpoints
                WHERE run_id = (SELECT MAX(run_id) FROM migration_runs)
                ORDER BY table_name, partition_key";

            var list = new List<PartitionStatus>();
            using var cmd = new SqliteCommand(sql, connection);
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                list.Add(new PartitionStatus
                {
                    Id = reader.GetInt32(0),
                    TableName = reader.GetString(1),
                    PartitionKey = reader.GetString(2),
                    Status = reader.GetString(3),
                    RowsProcessed = reader.GetInt64(4),
                    TotalRows = reader.GetInt64(5),
                    StartTime = TryReadDateTime(reader, 6),
                    EndTime = TryReadDateTime(reader, 7),
                    ErrorMessage = reader.IsDBNull(8) ? null : reader.GetString(8)
                });
            }

            return list;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving partition statuses");
            return new List<PartitionStatus>();
        }
    }

    public async Task<List<ProgressEvent>> GetRecentEvents(int limit = 100)
    {
        try
        {
            if (!File.Exists(GetDbPath()))
                return new List<ProgressEvent>();

            using var connection = new SqliteConnection(_connectionString);
            await connection.OpenAsync();

            const string sql = @"
                SELECT 
                    timestamp, table_name, partition_key, phase, status, 
                    rows_processed, total_rows, rows_per_second, message, warning
                FROM progress_events
                WHERE run_id = (SELECT MAX(run_id) FROM migration_runs)
                ORDER BY id DESC
                LIMIT @limit";

            var events = new List<ProgressEvent>();
            using var cmd = new SqliteCommand(sql, connection);
            cmd.Parameters.AddWithValue("@limit", limit);
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                events.Add(new ProgressEvent
                {
                    Timestamp = DateTime.Parse(reader.GetString(0)),
                    TableName = reader.IsDBNull(1) ? string.Empty : reader.GetString(1),
                    PartitionKey = reader.IsDBNull(2) ? string.Empty : reader.GetString(2),
                    Phase = reader.IsDBNull(3) ? string.Empty : reader.GetString(3),
                    Status = reader.IsDBNull(4) ? MigrationStatus.Pending : ParseStoredStatus(reader.GetString(4)),
                    RowsProcessed = reader.IsDBNull(5) ? 0 : reader.GetInt64(5),
                    TotalRows = reader.IsDBNull(6) ? 0 : reader.GetInt64(6),
                    RowsPerSecond = reader.IsDBNull(7) ? 0 : reader.GetDouble(7),
                    Message = reader.IsDBNull(8) ? string.Empty : reader.GetString(8),
                    Warning = reader.IsDBNull(9) ? null : reader.GetString(9)
                });
            }

            return events;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving recent events");
            return new List<ProgressEvent>();
        }
    }

    private string GetDbPath()
    {
        var builder = new SqliteConnectionStringBuilder(_connectionString);
        return builder.DataSource;
    }

    private static DateTime? TryReadDateTime(SqliteDataReader reader, int ordinal)
    {
        if (reader.IsDBNull(ordinal))
            return null;
        var s = reader.GetString(ordinal);
        if (string.IsNullOrWhiteSpace(s))
            return null;
        if (DateTime.TryParse(s, System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.RoundtripKind, out var dt))
            return dt;
        return DateTime.TryParse(s, out dt) ? dt : null;
    }

    /// <summary>
    /// migration_runs.status uses engine strings (RUNNING, COMPLETED); table_checkpoints use enum names (Pending, Running, …).
    /// </summary>
    private static MigrationStatus ParseStoredStatus(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return MigrationStatus.Pending;

        return raw.Trim().ToUpperInvariant() switch
        {
            "RUNNING" => MigrationStatus.Running,
            "COMPLETED" => MigrationStatus.Done,
            "FAILED" => MigrationStatus.Failed,
            _ => Enum.TryParse<MigrationStatus>(raw, ignoreCase: true, out var parsed)
                ? parsed
                : MigrationStatus.Pending
        };
    }
}
