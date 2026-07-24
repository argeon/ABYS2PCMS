using Microsoft.Data.Sqlite;
using MigrationShared.Models;
using MigrationEngine.Checkpoint;

namespace MigrationWeb.Services;

public class HistoryDataService
{
    private readonly string _connectionString;

    public HistoryDataService(string sqlitePath)
    {
        _connectionString = $"Data Source={sqlitePath}";
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

    public List<ConnectionProfile> GetConnectionProfiles(string? connectionType = null, bool includeDeleted = false)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();
        ConnectionProfileSchemaMigrator.EnsureColumns(connection);

        var filters = new List<string>();
        if (!includeDeleted)
            filters.Add("COALESCE(is_deleted, 0) = 0");
        if (connectionType != null)
            filters.Add("connection_type = @type");

        var where = filters.Count > 0 ? "WHERE " + string.Join(" AND ", filters) : "";
        var sql = $@"SELECT id, profile_name, connection_type, host, port, service_name, database_name,
                      username, schema_name, auth_type, trust_cert, connection_string, config_json,
                      created_at, last_used_at, use_count, COALESCE(is_deleted, 0), deleted_at
               FROM connection_profiles
               {where}
               ORDER BY COALESCE(is_deleted, 0), (last_used_at IS NULL), last_used_at DESC, use_count DESC, profile_name";

        using var cmd = new SqliteCommand(sql, connection);
        if (connectionType != null)
            cmd.Parameters.AddWithValue("@type", connectionType);

        var profiles = new List<ConnectionProfile>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
            profiles.Add(ReadProfile(reader));

        return profiles;
    }

    public ConnectionProfile? GetConnectionProfileById(int id, bool includeDeleted = true)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();
        ConnectionProfileSchemaMigrator.EnsureColumns(connection);

        var deletedFilter = includeDeleted ? "" : " AND COALESCE(is_deleted, 0) = 0";
        var sql = $@"SELECT id, profile_name, connection_type, host, port, service_name, database_name,
                      username, schema_name, auth_type, trust_cert, connection_string, config_json,
                      created_at, last_used_at, use_count, COALESCE(is_deleted, 0), deleted_at
               FROM connection_profiles
               WHERE id = @id{deletedFilter}
               LIMIT 1";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@id", id);

        using var reader = cmd.ExecuteReader();
        return reader.Read() ? ReadProfile(reader) : null;
    }

    public bool UpdateConnectionProfile(ConnectionProfile profile)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();
        ConnectionProfileSchemaMigrator.EnsureColumns(connection);

        var sql = @"UPDATE connection_profiles SET
                profile_name = @name,
                connection_type = @type,
                host = @host,
                port = @port,
                service_name = @service,
                database_name = @database,
                username = @username,
                schema_name = @schema,
                auth_type = @authType,
                trust_cert = @trustCert,
                connection_string = @connectionString,
                config_json = @configJson
            WHERE id = @id AND COALESCE(is_deleted, 0) = 0";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@id", profile.Id);
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
        cmd.Parameters.AddWithValue("@configJson", profile.ConfigJson ?? (object)DBNull.Value);

        return cmd.ExecuteNonQuery() > 0;
    }

    public bool SoftDeleteConnectionProfile(int id)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();
        ConnectionProfileSchemaMigrator.EnsureColumns(connection);

        var sql = @"UPDATE connection_profiles
            SET is_deleted = 1, deleted_at = @deletedAt
            WHERE id = @id AND COALESCE(is_deleted, 0) = 0";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@id", id);
        cmd.Parameters.AddWithValue("@deletedAt", DateTime.UtcNow.ToString("O"));
        return cmd.ExecuteNonQuery() > 0;
    }

    public bool RestoreConnectionProfile(int id)
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();
        ConnectionProfileSchemaMigrator.EnsureColumns(connection);

        var sql = @"UPDATE connection_profiles
            SET is_deleted = 0, deleted_at = NULL
            WHERE id = @id AND COALESCE(is_deleted, 0) = 1";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@id", id);
        return cmd.ExecuteNonQuery() > 0;
    }

    private static ConnectionProfile ReadProfile(SqliteDataReader reader)
    {
        return new ConnectionProfile
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
            ConfigJson = reader.IsDBNull(12) ? null : reader.GetString(12),
            CreatedAt = DateTime.Parse(reader.GetString(13)),
            LastUsedAt = reader.IsDBNull(14) ? null : DateTime.Parse(reader.GetString(14)),
            UseCount = reader.GetInt32(15),
            IsDeleted = reader.GetInt32(16) == 1,
            DeletedAt = reader.IsDBNull(17) ? null : DateTime.Parse(reader.GetString(17))
        };
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

    public Dictionary<string, object> GetRunComparison(int runId1, int runId2)
    {
        var summary1 = GetPerformanceSummary(runId1);
        var summary2 = GetPerformanceSummary(runId2);

        if (summary1 == null || summary2 == null)
            return new Dictionary<string, object>();

        return new Dictionary<string, object>
        {
            ["duration"] = new
            {
                run1 = summary1.TotalDurationSeconds,
                run2 = summary2.TotalDurationSeconds,
                improvement = CalculateImprovement(summary1.TotalDurationSeconds, summary2.TotalDurationSeconds)
            },
            ["avgThroughput"] = new
            {
                run1 = summary1.AvgRowsPerSecond,
                run2 = summary2.AvgRowsPerSecond,
                improvement = CalculateImprovement(summary1.AvgRowsPerSecond, summary2.AvgRowsPerSecond)
            },
            ["peakThroughput"] = new
            {
                run1 = summary1.PeakRowsPerSecond,
                run2 = summary2.PeakRowsPerSecond,
                improvement = CalculateImprovement(summary1.PeakRowsPerSecond, summary2.PeakRowsPerSecond)
            },
            ["parallelEfficiency"] = new
            {
                run1 = summary1.ParallelEfficiency,
                run2 = summary2.ParallelEfficiency,
                improvement = CalculateImprovement(summary1.ParallelEfficiency, summary2.ParallelEfficiency)
            }
        };
    }

    private double CalculateImprovement(double value1, double value2)
    {
        if (value1 == 0) return 0;
        return ((value2 - value1) / value1) * 100;
    }
}
