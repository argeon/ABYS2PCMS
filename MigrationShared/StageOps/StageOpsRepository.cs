using System.Text.Json;
using Microsoft.Data.Sqlite;
using MigrationShared.Models.StageOps;

namespace MigrationShared.StageOps;

public class StageOpsRepository : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    private readonly SqliteConnection _connection;
    private readonly object _lock = new();

    public StageOpsRepository(string sqlitePath)
    {
        var dir = Path.GetDirectoryName(sqlitePath);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);

        _connection = new SqliteConnection($"Data Source={sqlitePath}");
        _connection.Open();
        InitializeSchema();
    }

    private void InitializeSchema()
    {
        using (var wal = new SqliteCommand("PRAGMA journal_mode=WAL;", _connection))
            wal.ExecuteNonQuery();

        foreach (var sql in StageOpsSchema.GetAllSchemaCommands())
        {
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.ExecuteNonQuery();
        }
    }

    private void EnsureOpen()
    {
        if (_connection.State != System.Data.ConnectionState.Open)
            _connection.Open();
    }

    public List<StageDefinition> ListStages(string surface)
    {
        const string sql = @"
            SELECT stage_id, surface, name, domain, kind, path, procedure_name, sort_order,
                   estimated_rows, depends_on_json, writes_json, reads_json, parallel_safe,
                   slot_cost, recreate_on_retry, status, syntax_status, analysis_json, updated_at
            FROM stage_scripts
            WHERE surface = @surface
            ORDER BY sort_order, name";

        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@surface", surface);
            using var reader = cmd.ExecuteReader();
            var list = new List<StageDefinition>();
            while (reader.Read())
                list.Add(ReadStage(reader));
            return list;
        }
    }

    public StageDefinition? GetStage(string stageId)
    {
        const string sql = @"
            SELECT stage_id, surface, name, domain, kind, path, procedure_name, sort_order,
                   estimated_rows, depends_on_json, writes_json, reads_json, parallel_safe,
                   slot_cost, recreate_on_retry, status, syntax_status, analysis_json, updated_at
            FROM stage_scripts WHERE stage_id = @id";

        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@id", stageId);
            using var reader = cmd.ExecuteReader();
            return reader.Read() ? ReadStage(reader) : null;
        }
    }

    public void UpsertStage(StageDefinition stage)
    {
        const string sql = @"
            INSERT INTO stage_scripts (
                stage_id, surface, name, domain, kind, path, procedure_name, sort_order,
                estimated_rows, depends_on_json, writes_json, reads_json, parallel_safe,
                slot_cost, recreate_on_retry, status, syntax_status, analysis_json, created_at, updated_at)
            VALUES (
                @stage_id, @surface, @name, @domain, @kind, @path, @procedure_name, @sort_order,
                @estimated_rows, @depends_on_json, @writes_json, @reads_json, @parallel_safe,
                @slot_cost, @recreate_on_retry, @status, @syntax_status, @analysis_json, @now, @now)
            ON CONFLICT(stage_id) DO UPDATE SET
                name = excluded.name,
                domain = excluded.domain,
                kind = excluded.kind,
                path = excluded.path,
                procedure_name = excluded.procedure_name,
                sort_order = excluded.sort_order,
                estimated_rows = excluded.estimated_rows,
                depends_on_json = excluded.depends_on_json,
                writes_json = excluded.writes_json,
                reads_json = excluded.reads_json,
                parallel_safe = excluded.parallel_safe,
                slot_cost = excluded.slot_cost,
                recreate_on_retry = excluded.recreate_on_retry,
                status = excluded.status,
                syntax_status = excluded.syntax_status,
                analysis_json = excluded.analysis_json,
                updated_at = excluded.updated_at";

        var now = DateTime.UtcNow.ToString("O");
        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(sql, _connection);
            BindStage(cmd, stage, now);
            cmd.ExecuteNonQuery();
        }
    }

    public void UpdateStageStatus(string stageId, string status)
    {
        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(
                "UPDATE stage_scripts SET status = @status, updated_at = @now WHERE stage_id = @id",
                _connection);
            cmd.Parameters.AddWithValue("@status", status);
            cmd.Parameters.AddWithValue("@now", DateTime.UtcNow.ToString("O"));
            cmd.Parameters.AddWithValue("@id", stageId);
            cmd.ExecuteNonQuery();
        }
    }

    public int CreateRun(string surface, string runUuid, int maxParallel, int totalStages, string? paramsJson)
    {
        var now = DateTime.UtcNow.ToString("O");
        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(@"
                INSERT INTO stage_runs (run_uuid, surface, status, max_parallel, total_stages, params_json, started_at, updated_at)
                VALUES (@uuid, @surface, 'Queued', @max, @total, @params, @now, @now);
                SELECT last_insert_rowid();", _connection);
            cmd.Parameters.AddWithValue("@uuid", runUuid);
            cmd.Parameters.AddWithValue("@surface", surface);
            cmd.Parameters.AddWithValue("@max", maxParallel);
            cmd.Parameters.AddWithValue("@total", totalStages);
            cmd.Parameters.AddWithValue("@params", (object?)paramsJson ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@now", now);
            return Convert.ToInt32(cmd.ExecuteScalar());
        }
    }

    public void UpdateRun(int runId, string status, int done, int failed, int running, long totalRows, bool complete = false)
    {
        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(@"
                UPDATE stage_runs SET
                    status = @status,
                    done_count = @done,
                    failed_count = @failed,
                    running_count = @running,
                    total_rows = @rows,
                    updated_at = @now,
                    completed_at = CASE WHEN @complete = 1 THEN @now ELSE completed_at END
                WHERE id = @id", _connection);
            cmd.Parameters.AddWithValue("@status", status);
            cmd.Parameters.AddWithValue("@done", done);
            cmd.Parameters.AddWithValue("@failed", failed);
            cmd.Parameters.AddWithValue("@running", running);
            cmd.Parameters.AddWithValue("@rows", totalRows);
            cmd.Parameters.AddWithValue("@now", DateTime.UtcNow.ToString("O"));
            cmd.Parameters.AddWithValue("@complete", complete ? 1 : 0);
            cmd.Parameters.AddWithValue("@id", runId);
            cmd.ExecuteNonQuery();
        }
    }

    public long CreateRunItem(int runId, string stageId, string stageName)
    {
        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(@"
                INSERT INTO stage_run_items (run_id, stage_id, stage_name, status)
                VALUES (@run, @stage, @name, 'Queued');
                SELECT last_insert_rowid();", _connection);
            cmd.Parameters.AddWithValue("@run", runId);
            cmd.Parameters.AddWithValue("@stage", stageId);
            cmd.Parameters.AddWithValue("@name", stageName);
            return Convert.ToInt64(cmd.ExecuteScalar());
        }
    }

    public void UpdateRunItem(long itemId, string status, int? exitCode, long elapsedMs, long? rows, double? rowsPerSec, string? logPath, string? detailJson, bool started = false, bool completed = false)
    {
        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(@"
                UPDATE stage_run_items SET
                    status = @status,
                    exit_code = @exit,
                    elapsed_ms = @elapsed,
                    row_count = @rows,
                    rows_per_sec = @rps,
                    log_path = COALESCE(@log, log_path),
                    detail_json = COALESCE(@detail, detail_json),
                    started_at = CASE WHEN @started = 1 THEN COALESCE(started_at, @now) ELSE started_at END,
                    completed_at = CASE WHEN @completed = 1 THEN @now ELSE completed_at END
                WHERE id = @id", _connection);
            cmd.Parameters.AddWithValue("@status", status);
            cmd.Parameters.AddWithValue("@exit", (object?)exitCode ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@elapsed", elapsedMs);
            cmd.Parameters.AddWithValue("@rows", (object?)rows ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@rps", (object?)rowsPerSec ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@log", (object?)logPath ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@detail", (object?)detailJson ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@started", started ? 1 : 0);
            cmd.Parameters.AddWithValue("@completed", completed ? 1 : 0);
            cmd.Parameters.AddWithValue("@now", DateTime.UtcNow.ToString("O"));
            cmd.Parameters.AddWithValue("@id", itemId);
            cmd.ExecuteNonQuery();
        }
    }

    public List<StageRunSummary> ListRuns(string? surface, int limit = 50)
    {
        var sql = @"
            SELECT id, run_uuid, surface, status, max_parallel, total_stages, done_count, failed_count,
                   running_count, total_rows, params_json, started_at, completed_at
            FROM stage_runs
            WHERE (@surface IS NULL OR surface = @surface)
            ORDER BY id DESC
            LIMIT @limit";

        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@surface", (object?)surface ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@limit", limit);
            using var reader = cmd.ExecuteReader();
            var list = new List<StageRunSummary>();
            while (reader.Read())
            {
                list.Add(new StageRunSummary
                {
                    Id = reader.GetInt32(0),
                    RunUuid = reader.GetString(1),
                    Surface = reader.GetString(2),
                    Status = reader.GetString(3),
                    MaxParallel = reader.GetInt32(4),
                    TotalStages = reader.GetInt32(5),
                    DoneCount = reader.GetInt32(6),
                    FailedCount = reader.GetInt32(7),
                    RunningCount = reader.GetInt32(8),
                    TotalRows = reader.GetInt64(9),
                    ParamsJson = reader.IsDBNull(10) ? null : reader.GetString(10),
                    StartedAt = DateTime.Parse(reader.GetString(11)),
                    CompletedAt = reader.IsDBNull(12) ? null : DateTime.Parse(reader.GetString(12))
                });
            }
            return list;
        }
    }

    public StageRunSummary? GetRun(int runId)
    {
        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(@"
                SELECT id, run_uuid, surface, status, max_parallel, total_stages, done_count, failed_count,
                       running_count, total_rows, params_json, started_at, completed_at
                FROM stage_runs WHERE id = @id", _connection);
            cmd.Parameters.AddWithValue("@id", runId);
            using var reader = cmd.ExecuteReader();
            if (!reader.Read()) return null;
            return new StageRunSummary
            {
                Id = reader.GetInt32(0),
                RunUuid = reader.GetString(1),
                Surface = reader.GetString(2),
                Status = reader.GetString(3),
                MaxParallel = reader.GetInt32(4),
                TotalStages = reader.GetInt32(5),
                DoneCount = reader.GetInt32(6),
                FailedCount = reader.GetInt32(7),
                RunningCount = reader.GetInt32(8),
                TotalRows = reader.GetInt64(9),
                ParamsJson = reader.IsDBNull(10) ? null : reader.GetString(10),
                StartedAt = DateTime.Parse(reader.GetString(11)),
                CompletedAt = reader.IsDBNull(12) ? null : DateTime.Parse(reader.GetString(12))
            };
        }
    }

    public List<StageRunItem> GetRunItems(int runId)
    {
        const string sql = @"
            SELECT id, run_id, stage_id, stage_name, status, exit_code, elapsed_ms, row_count,
                   rows_per_sec, log_path, detail_json, started_at, completed_at
            FROM stage_run_items WHERE run_id = @run ORDER BY id";

        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@run", runId);
            using var reader = cmd.ExecuteReader();
            var list = new List<StageRunItem>();
            while (reader.Read())
            {
                list.Add(new StageRunItem
                {
                    Id = reader.GetInt64(0),
                    RunId = reader.GetInt32(1),
                    StageId = reader.GetString(2),
                    StageName = reader.GetString(3),
                    Status = reader.GetString(4),
                    ExitCode = reader.IsDBNull(5) ? null : reader.GetInt32(5),
                    ElapsedMs = reader.GetInt64(6),
                    Rows = reader.IsDBNull(7) ? null : reader.GetInt64(7),
                    RowsPerSec = reader.IsDBNull(8) ? null : reader.GetDouble(8),
                    LogPath = reader.IsDBNull(9) ? null : reader.GetString(9),
                    DetailJson = reader.IsDBNull(10) ? null : reader.GetString(10),
                    StartedAt = reader.IsDBNull(11) ? null : DateTime.Parse(reader.GetString(11)),
                    CompletedAt = reader.IsDBNull(12) ? null : DateTime.Parse(reader.GetString(12))
                });
            }
            return list;
        }
    }

    public void LogEvent(int runId, string level, string message, string? stageId = null)
    {
        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(@"
                INSERT INTO stage_events (run_id, stage_id, level, message, created_at)
                VALUES (@run, @stage, @level, @msg, @now)", _connection);
            cmd.Parameters.AddWithValue("@run", runId);
            cmd.Parameters.AddWithValue("@stage", (object?)stageId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@level", level);
            cmd.Parameters.AddWithValue("@msg", message);
            cmd.Parameters.AddWithValue("@now", DateTime.UtcNow.ToString("O"));
            cmd.ExecuteNonQuery();
        }
    }

    public List<StageEventEntry> GetEvents(int runId, int limit = 200)
    {
        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(@"
                SELECT id, run_id, stage_id, level, message, created_at
                FROM stage_events WHERE run_id = @run
                ORDER BY id DESC LIMIT @limit", _connection);
            cmd.Parameters.AddWithValue("@run", runId);
            cmd.Parameters.AddWithValue("@limit", limit);
            using var reader = cmd.ExecuteReader();
            var list = new List<StageEventEntry>();
            while (reader.Read())
            {
                list.Add(new StageEventEntry
                {
                    Id = reader.GetInt64(0),
                    RunId = reader.GetInt32(1),
                    StageId = reader.IsDBNull(2) ? null : reader.GetString(2),
                    Level = reader.GetString(3),
                    Message = reader.GetString(4),
                    CreatedAt = DateTime.Parse(reader.GetString(5))
                });
            }
            return list;
        }
    }

    public void SaveAnalysis(string stageId, string surface, string fileName, ScriptAnalysisResult analysis)
    {
        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(@"
                INSERT INTO script_analyses (stage_id, surface, file_name, syntax_ok, result_json, analyzed_at)
                VALUES (@stage, @surface, @file, @ok, @json, @now)", _connection);
            cmd.Parameters.AddWithValue("@stage", stageId);
            cmd.Parameters.AddWithValue("@surface", surface);
            cmd.Parameters.AddWithValue("@file", fileName);
            cmd.Parameters.AddWithValue("@ok", analysis.SyntaxOk ? 1 : 0);
            cmd.Parameters.AddWithValue("@json", JsonSerializer.Serialize(analysis, JsonOptions));
            cmd.Parameters.AddWithValue("@now", DateTime.UtcNow.ToString("O"));
            cmd.ExecuteNonQuery();
        }
    }

    public void SaveSchemaCheck(string surface, string stageId, int? runId, SchemaGateResult result)
    {
        lock (_lock)
        {
            EnsureOpen();
            using var cmd = new SqliteCommand(@"
                INSERT INTO stage_schema_checks (surface, stage_id, run_id, compatible, result_json, checked_at)
                VALUES (@surface, @stage, @run, @ok, @json, @now)", _connection);
            cmd.Parameters.AddWithValue("@surface", surface);
            cmd.Parameters.AddWithValue("@stage", stageId);
            cmd.Parameters.AddWithValue("@run", (object?)runId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ok", result.Compatible ? 1 : 0);
            cmd.Parameters.AddWithValue("@json", JsonSerializer.Serialize(result, JsonOptions));
            cmd.Parameters.AddWithValue("@now", DateTime.UtcNow.ToString("O"));
            cmd.ExecuteNonQuery();
        }
    }

    public void Dispose() => _connection.Dispose();

    private static StageDefinition ReadStage(SqliteDataReader reader) => new()
    {
        Id = reader.GetString(0),
        Surface = reader.GetString(1),
        Name = reader.GetString(2),
        Domain = reader.GetString(3),
        Kind = Enum.TryParse<StageKind>(reader.GetString(4), out var k) ? k : StageKind.SqlScript,
        Path = reader.IsDBNull(5) ? null : reader.GetString(5),
        ProcedureName = reader.IsDBNull(6) ? null : reader.GetString(6),
        SortOrder = reader.GetInt32(7),
        EstimatedRows = reader.IsDBNull(8) ? null : reader.GetInt64(8),
        DependsOn = DeserializeList(reader.GetString(9)),
        Writes = DeserializeList(reader.GetString(10)),
        Reads = DeserializeList(reader.GetString(11)),
        ParallelSafe = reader.GetInt32(12) == 1,
        SlotCost = reader.GetInt32(13),
        RecreateOnRetry = reader.GetInt32(14) == 1,
        Status = reader.GetString(15),
        SyntaxStatus = reader.IsDBNull(16) ? null : reader.GetString(16),
        AnalysisJson = reader.IsDBNull(17) ? null : reader.GetString(17),
        UpdatedAt = reader.IsDBNull(18) ? null : DateTime.Parse(reader.GetString(18))
    };

    private static void BindStage(SqliteCommand cmd, StageDefinition stage, string now)
    {
        cmd.Parameters.AddWithValue("@stage_id", stage.Id);
        cmd.Parameters.AddWithValue("@surface", stage.Surface);
        cmd.Parameters.AddWithValue("@name", stage.Name);
        cmd.Parameters.AddWithValue("@domain", stage.Domain);
        cmd.Parameters.AddWithValue("@kind", stage.Kind.ToString());
        cmd.Parameters.AddWithValue("@path", (object?)stage.Path ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@procedure_name", (object?)stage.ProcedureName ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@sort_order", stage.SortOrder);
        cmd.Parameters.AddWithValue("@estimated_rows", (object?)stage.EstimatedRows ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@depends_on_json", JsonSerializer.Serialize(stage.DependsOn, JsonOptions));
        cmd.Parameters.AddWithValue("@writes_json", JsonSerializer.Serialize(stage.Writes, JsonOptions));
        cmd.Parameters.AddWithValue("@reads_json", JsonSerializer.Serialize(stage.Reads, JsonOptions));
        cmd.Parameters.AddWithValue("@parallel_safe", stage.ParallelSafe ? 1 : 0);
        cmd.Parameters.AddWithValue("@slot_cost", stage.SlotCost);
        cmd.Parameters.AddWithValue("@recreate_on_retry", stage.RecreateOnRetry ? 1 : 0);
        cmd.Parameters.AddWithValue("@status", stage.Status);
        cmd.Parameters.AddWithValue("@syntax_status", (object?)stage.SyntaxStatus ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@analysis_json", (object?)stage.AnalysisJson ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@now", now);
    }

    private static List<string> DeserializeList(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<List<string>>(json, JsonOptions) ?? new List<string>();
        }
        catch
        {
            return new List<string>();
        }
    }
}
