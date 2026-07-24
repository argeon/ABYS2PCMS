using System.Text.Json;
using Microsoft.Data.Sqlite;
using MigrationShared.Models.TransferStudio;
using MigrationShared.TransferStudio;

namespace MigrationShared.TransferStudio;

public class TransferStudioRepository : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    private readonly SqliteConnection _connection;
    private readonly object _lock = new();

    public TransferStudioRepository(string sqlitePath)
    {
        var connectionString = $"Data Source={sqlitePath}";
        _connection = new SqliteConnection(connectionString);
        _connection.Open();
        InitializeSchema();
    }

    private void InitializeSchema()
    {
        using (var wal = new SqliteCommand("PRAGMA journal_mode=WAL;", _connection))
            wal.ExecuteNonQuery();

        foreach (var sql in TransferStudioSchema.GetAllSchemaCommands())
        {
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.ExecuteNonQuery();
        }
    }

    public List<TransferRecipeSummary> ListRecipes()
    {
        const string sql = @"
            SELECT id, migration_id, name, status, version, sort_order, config_json, created_at, updated_at
            FROM transfer_recipes
            ORDER BY sort_order, name";

        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            using var reader = cmd.ExecuteReader();
            var list = new List<TransferRecipeSummary>();
            while (reader.Read())
            {
                var doc = DeserializeDocument(reader.GetString(6));
                list.Add(new TransferRecipeSummary
                {
                    Id = reader.GetInt32(0),
                    MigrationId = reader.GetString(1),
                    Name = reader.GetString(2),
                    Status = Enum.Parse<TransferRecipeStatus>(reader.GetString(3)),
                    Version = reader.GetInt32(4),
                    SortOrder = reader.GetInt32(5),
                    SourceTable = FormatTable(doc.Endpoints.SourceSchema, doc.Endpoints.SourceTable),
                    TargetTable = FormatTable(doc.Endpoints.TargetSchema, doc.Endpoints.TargetTable),
                    CreatedAt = DateTime.Parse(reader.GetString(7)),
                    UpdatedAt = DateTime.Parse(reader.GetString(8))
                });
            }

            return list;
        }
    }

    public TransferRecipeDocument? GetRecipeDocument(int id)
    {
        lock (_lock)
        {
            using var cmd = new SqliteCommand(
                "SELECT config_json FROM transfer_recipes WHERE id = @id", _connection);
            cmd.Parameters.AddWithValue("@id", id);
            var json = cmd.ExecuteScalar() as string;
            return json == null ? null : DeserializeDocument(json);
        }
    }

    public (int id, TransferRecipeDocument doc)? GetRecipe(int id)
    {
        lock (_lock)
        {
            using var cmd = new SqliteCommand(
                "SELECT config_json FROM transfer_recipes WHERE id = @id", _connection);
            cmd.Parameters.AddWithValue("@id", id);
            using var reader = cmd.ExecuteReader();
            if (!reader.Read())
                return null;

            var doc = DeserializeDocument(reader.GetString(0));
            return (id, doc);
        }
    }

    public int SaveRecipe(TransferRecipeDocument doc, TransferRecipeStatus status, int? existingId = null)
    {
        var now = DateTime.UtcNow.ToString("o");
        var json = JsonSerializer.Serialize(doc, JsonOptions);

        lock (_lock)
        {
            if (existingId is > 0)
            {
                using var cmd = new SqliteCommand(@"
                    UPDATE transfer_recipes
                    SET migration_id = @mid, name = @name, status = @status,
                        version = version + 1, sort_order = @sort, config_json = @json, updated_at = @now
                    WHERE id = @id", _connection);
                cmd.Parameters.AddWithValue("@mid", doc.MigrationId);
                cmd.Parameters.AddWithValue("@name", doc.Name);
                cmd.Parameters.AddWithValue("@status", status.ToString());
                cmd.Parameters.AddWithValue("@sort", doc.SortOrder);
                cmd.Parameters.AddWithValue("@json", json);
                cmd.Parameters.AddWithValue("@now", now);
                cmd.Parameters.AddWithValue("@id", existingId.Value);
                cmd.ExecuteNonQuery();
                return existingId.Value;
            }

            using var insert = new SqliteCommand(@"
                INSERT INTO transfer_recipes (migration_id, name, status, version, sort_order, config_json, created_at, updated_at)
                VALUES (@mid, @name, @status, 1, @sort, @json, @now, @now);
                SELECT last_insert_rowid();", _connection);
            insert.Parameters.AddWithValue("@mid", doc.MigrationId);
            insert.Parameters.AddWithValue("@name", doc.Name);
            insert.Parameters.AddWithValue("@status", status.ToString());
            insert.Parameters.AddWithValue("@sort", doc.SortOrder);
            insert.Parameters.AddWithValue("@json", json);
            insert.Parameters.AddWithValue("@now", now);
            return Convert.ToInt32(insert.ExecuteScalar());
        }
    }

    public bool DeleteRecipe(int id)
    {
        lock (_lock)
        {
            using var cmd = new SqliteCommand("DELETE FROM transfer_recipes WHERE id = @id", _connection);
            cmd.Parameters.AddWithValue("@id", id);
            return cmd.ExecuteNonQuery() > 0;
        }
    }

    public int CreateRun(int recipeId, string runUuid, string executionMode, string phase, string? paramsJson)
    {
        var now = DateTime.UtcNow.ToString("o");
        lock (_lock)
        {
            using var cmd = new SqliteCommand(@"
                INSERT INTO transfer_runs
                    (recipe_id, run_uuid, execution_mode, phase, status, params_json, started_at, updated_at)
                VALUES (@recipeId, @uuid, @mode, @phase, 'Running', @params, @now, @now);
                SELECT last_insert_rowid();", _connection);
            cmd.Parameters.AddWithValue("@recipeId", recipeId);
            cmd.Parameters.AddWithValue("@uuid", runUuid);
            cmd.Parameters.AddWithValue("@mode", executionMode);
            cmd.Parameters.AddWithValue("@phase", phase);
            cmd.Parameters.AddWithValue("@params", (object?)paramsJson ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@now", now);
            return Convert.ToInt32(cmd.ExecuteScalar());
        }
    }

    public void UpdateRun(int runId, string status, long totalOk, long totalError, string? lastBridgeKey, bool completed = false)
    {
        var now = DateTime.UtcNow.ToString("o");
        lock (_lock)
        {
            using var cmd = new SqliteCommand(@"
                UPDATE transfer_runs
                SET status = @status, total_ok = @ok, total_error = @err,
                    last_bridge_key = @key, updated_at = @now,
                    completed_at = CASE WHEN @completed = 1 THEN @now ELSE completed_at END
                WHERE id = @id", _connection);
            cmd.Parameters.AddWithValue("@status", status);
            cmd.Parameters.AddWithValue("@ok", totalOk);
            cmd.Parameters.AddWithValue("@err", totalError);
            cmd.Parameters.AddWithValue("@key", (object?)lastBridgeKey ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@now", now);
            cmd.Parameters.AddWithValue("@completed", completed ? 1 : 0);
            cmd.Parameters.AddWithValue("@id", runId);
            cmd.ExecuteNonQuery();
        }
    }

    public List<TransferRunSummary> ListRuns(int? recipeId = null, int limit = 50)
    {
        var sql = recipeId == null
            ? @"SELECT r.id, r.recipe_id, r.run_uuid, tr.name, r.phase, r.status,
                       r.total_ok, r.total_error, r.last_bridge_key, r.started_at, r.completed_at
                FROM transfer_runs r
                JOIN transfer_recipes tr ON tr.id = r.recipe_id
                ORDER BY r.started_at DESC LIMIT @limit"
            : @"SELECT r.id, r.recipe_id, r.run_uuid, tr.name, r.phase, r.status,
                       r.total_ok, r.total_error, r.last_bridge_key, r.started_at, r.completed_at
                FROM transfer_runs r
                JOIN transfer_recipes tr ON tr.id = r.recipe_id
                WHERE r.recipe_id = @recipeId
                ORDER BY r.started_at DESC LIMIT @limit";

        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            cmd.Parameters.AddWithValue("@limit", limit);
            if (recipeId != null)
                cmd.Parameters.AddWithValue("@recipeId", recipeId.Value);

            using var reader = cmd.ExecuteReader();
            var list = new List<TransferRunSummary>();
            while (reader.Read())
            {
                list.Add(new TransferRunSummary
                {
                    Id = reader.GetInt32(0),
                    RecipeId = reader.GetInt32(1),
                    RunUuid = reader.GetString(2),
                    RecipeName = reader.GetString(3),
                    Phase = reader.GetString(4),
                    Status = reader.GetString(5),
                    TotalOk = reader.GetInt64(6),
                    TotalError = reader.GetInt64(7),
                    LastBridgeKey = reader.IsDBNull(8) ? null : reader.GetString(8),
                    StartedAt = DateTime.Parse(reader.GetString(9)),
                    CompletedAt = reader.IsDBNull(10) ? null : DateTime.Parse(reader.GetString(10))
                });
            }

            return list;
        }
    }

    public void InsertEvent(TransferEventLogEntry entry)
    {
        lock (_lock)
        {
            using var cmd = new SqliteCommand(@"
                INSERT INTO transfer_event_log
                    (run_id, level, phase, batch_no, bridge_from, bridge_to, bridge_key, message, row_count, created_at)
                VALUES (@runId, @level, @phase, @batch, @from, @to, @key, @msg, @rows, @at)", _connection);
            cmd.Parameters.AddWithValue("@runId", entry.RunId);
            cmd.Parameters.AddWithValue("@level", entry.Level);
            cmd.Parameters.AddWithValue("@phase", (object?)entry.Phase ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@batch", (object?)entry.BatchNo ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@from", (object?)entry.BridgeFrom ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@to", (object?)entry.BridgeTo ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@key", (object?)entry.BridgeKey ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@msg", entry.Message);
            cmd.Parameters.AddWithValue("@rows", (object?)entry.RowCount ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@at", entry.CreatedAt.ToString("o"));
            cmd.ExecuteNonQuery();
        }
    }

    public List<TransferEventLogEntry> GetEvents(int runId, int limit = 200)
    {
        lock (_lock)
        {
            using var cmd = new SqliteCommand(@"
                SELECT id, run_id, level, phase, batch_no, bridge_from, bridge_to, bridge_key, message, row_count, created_at
                FROM transfer_event_log
                WHERE run_id = @runId
                ORDER BY id DESC LIMIT @limit", _connection);
            cmd.Parameters.AddWithValue("@runId", runId);
            cmd.Parameters.AddWithValue("@limit", limit);

            using var reader = cmd.ExecuteReader();
            var list = new List<TransferEventLogEntry>();
            while (reader.Read())
            {
                list.Add(new TransferEventLogEntry
                {
                    Id = reader.GetInt64(0),
                    RunId = reader.GetInt32(1),
                    Level = reader.GetString(2),
                    Phase = reader.IsDBNull(3) ? null : reader.GetString(3),
                    BatchNo = reader.IsDBNull(4) ? null : reader.GetInt32(4),
                    BridgeFrom = reader.IsDBNull(5) ? null : reader.GetString(5),
                    BridgeTo = reader.IsDBNull(6) ? null : reader.GetString(6),
                    BridgeKey = reader.IsDBNull(7) ? null : reader.GetString(7),
                    Message = reader.GetString(8),
                    RowCount = reader.IsDBNull(9) ? null : reader.GetInt32(9),
                    CreatedAt = DateTime.Parse(reader.GetString(10))
                });
            }

            list.Reverse();
            return list;
        }
    }

    public int SaveValidationResult(TransferValidationRunResult result, int? transferRunId)
    {
        lock (_lock)
        {
            using var tx = _connection.BeginTransaction();

            using (var vr = new SqliteCommand(@"
                INSERT INTO transfer_validation_runs (recipe_id, transfer_run_id, phase, all_passed, evaluated_at)
                VALUES (@recipeId, @runId, @phase, @passed, @at);
                SELECT last_insert_rowid();", _connection, tx))
            {
                vr.Parameters.AddWithValue("@recipeId", result.RecipeId);
                vr.Parameters.AddWithValue("@runId", (object?)transferRunId ?? DBNull.Value);
                vr.Parameters.AddWithValue("@phase", result.Phase);
                vr.Parameters.AddWithValue("@passed", result.AllPassed ? 1 : 0);
                vr.Parameters.AddWithValue("@at", result.EvaluatedAt.ToString("o"));
                result.ValidationRunId = Convert.ToInt32(vr.ExecuteScalar());
            }

            foreach (var gate in result.Metrics)
            {
                using var g = new SqliteCommand(@"
                    INSERT INTO transfer_validation_gates
                        (validation_run_id, gate_type, passed, source_value, target_value, detail)
                    VALUES (@vr, @type, @passed, @src, @tgt, @detail)", _connection, tx);
                g.Parameters.AddWithValue("@vr", result.ValidationRunId);
                g.Parameters.AddWithValue("@type", gate.GateType);
                g.Parameters.AddWithValue("@passed", gate.Passed ? 1 : 0);
                g.Parameters.AddWithValue("@src", (object?)gate.SourceValue ?? DBNull.Value);
                g.Parameters.AddWithValue("@tgt", (object?)gate.TargetValue ?? DBNull.Value);
                g.Parameters.AddWithValue("@detail", (object?)gate.Detail ?? DBNull.Value);
                g.ExecuteNonQuery();
            }

            foreach (var row in result.ContentMismatches)
            {
                using var m = new SqliteCommand(@"
                    INSERT INTO transfer_content_mismatches
                        (validation_run_id, bridge_key, column_label, source_value, target_value, compare_as, phase)
                    VALUES (@vr, @key, @col, @src, @tgt, @cmp, @phase)", _connection, tx);
                m.Parameters.AddWithValue("@vr", result.ValidationRunId);
                m.Parameters.AddWithValue("@key", row.BridgeKey);
                m.Parameters.AddWithValue("@col", row.ColumnLabel);
                m.Parameters.AddWithValue("@src", (object?)row.SourceValue ?? DBNull.Value);
                m.Parameters.AddWithValue("@tgt", (object?)row.TargetValue ?? DBNull.Value);
                m.Parameters.AddWithValue("@cmp", row.CompareAs);
                m.Parameters.AddWithValue("@phase", (object?)row.Phase ?? DBNull.Value);
                m.ExecuteNonQuery();
            }

            tx.Commit();
            return result.ValidationRunId;
        }
    }

    public TransferValidationRunResult? GetLatestValidation(int recipeId)
    {
        lock (_lock)
        {
            int validationRunId;
            string phase;
            int allPassed;
            string evaluatedAt;

            using (var cmd = new SqliteCommand(@"
                SELECT id, phase, all_passed, evaluated_at
                FROM transfer_validation_runs
                WHERE recipe_id = @recipeId
                ORDER BY id DESC LIMIT 1", _connection))
            {
                cmd.Parameters.AddWithValue("@recipeId", recipeId);
                using var reader = cmd.ExecuteReader();
                if (!reader.Read())
                    return null;
                validationRunId = reader.GetInt32(0);
                phase = reader.GetString(1);
                allPassed = reader.GetInt32(2);
                evaluatedAt = reader.GetString(3);
            }

            var result = new TransferValidationRunResult
            {
                ValidationRunId = validationRunId,
                RecipeId = recipeId,
                Phase = phase,
                AllPassed = allPassed == 1,
                EvaluatedAt = DateTime.Parse(evaluatedAt)
            };

            using (var gates = new SqliteCommand(@"
                SELECT gate_type, passed, source_value, target_value, detail
                FROM transfer_validation_gates WHERE validation_run_id = @id", _connection))
            {
                gates.Parameters.AddWithValue("@id", validationRunId);
                using var reader = gates.ExecuteReader();
                while (reader.Read())
                {
                    result.Metrics.Add(new ValidationGateOutcome
                    {
                        GateType = reader.GetString(0),
                        Passed = reader.GetInt32(1) == 1,
                        SourceValue = reader.IsDBNull(2) ? null : reader.GetString(2),
                        TargetValue = reader.IsDBNull(3) ? null : reader.GetString(3),
                        Detail = reader.IsDBNull(4) ? null : reader.GetString(4)
                    });
                }
            }

            using (var mismatches = new SqliteCommand(@"
                SELECT bridge_key, column_label, source_value, target_value, compare_as, phase
                FROM transfer_content_mismatches WHERE validation_run_id = @id
                LIMIT 200", _connection))
            {
                mismatches.Parameters.AddWithValue("@id", validationRunId);
                using var reader = mismatches.ExecuteReader();
                while (reader.Read())
                {
                    result.ContentMismatches.Add(new ContentMismatchRow
                    {
                        BridgeKey = reader.GetString(0),
                        ColumnLabel = reader.GetString(1),
                        SourceValue = reader.IsDBNull(2) ? null : reader.GetString(2),
                        TargetValue = reader.IsDBNull(3) ? null : reader.GetString(3),
                        CompareAs = reader.GetString(4),
                        Phase = reader.IsDBNull(5) ? null : reader.GetString(5)
                    });
                }
            }

            return result;
        }
    }

    public List<PipelineProjectSummary> ListPipelineProjects()
    {
        const string sql = @"
            SELECT id, name, config_json, created_at, updated_at
            FROM pipeline_projects ORDER BY updated_at DESC";

        lock (_lock)
        {
            using var cmd = new SqliteCommand(sql, _connection);
            using var reader = cmd.ExecuteReader();
            var list = new List<PipelineProjectSummary>();
            while (reader.Read())
            {
                var doc = DeserializePipeline(reader.GetString(2));
                list.Add(new PipelineProjectSummary
                {
                    Id = reader.GetInt32(0),
                    Name = reader.GetString(1),
                    OracleRunId = doc.OracleRunId,
                    StepCount = doc.Steps.Count,
                    CreatedAt = DateTime.Parse(reader.GetString(3)),
                    UpdatedAt = DateTime.Parse(reader.GetString(4))
                });
            }

            return list;
        }
    }

    public PipelineProjectDocument? GetPipelineDocument(int id)
    {
        lock (_lock)
        {
            using var cmd = new SqliteCommand("SELECT config_json FROM pipeline_projects WHERE id = @id", _connection);
            cmd.Parameters.AddWithValue("@id", id);
            var json = cmd.ExecuteScalar() as string;
            return json == null ? null : DeserializePipeline(json);
        }
    }

    public int SavePipelineProject(PipelineProjectDocument doc, int? existingId = null)
    {
        var now = DateTime.UtcNow.ToString("o");
        var json = JsonSerializer.Serialize(doc, JsonOptions);

        lock (_lock)
        {
            if (existingId is > 0)
            {
                using var cmd = new SqliteCommand(@"
                    UPDATE pipeline_projects SET name = @name, config_json = @json, updated_at = @now
                    WHERE id = @id", _connection);
                cmd.Parameters.AddWithValue("@name", doc.Name);
                cmd.Parameters.AddWithValue("@json", json);
                cmd.Parameters.AddWithValue("@now", now);
                cmd.Parameters.AddWithValue("@id", existingId.Value);
                cmd.ExecuteNonQuery();
                return existingId.Value;
            }

            using var insert = new SqliteCommand(@"
                INSERT INTO pipeline_projects (name, config_json, created_at, updated_at)
                VALUES (@name, @json, @now, @now);
                SELECT last_insert_rowid();", _connection);
            insert.Parameters.AddWithValue("@name", doc.Name);
            insert.Parameters.AddWithValue("@json", json);
            insert.Parameters.AddWithValue("@now", now);
            return Convert.ToInt32(insert.ExecuteScalar());
        }
    }

    public bool DeletePipelineProject(int id)
    {
        lock (_lock)
        {
            using var cmd = new SqliteCommand("DELETE FROM pipeline_projects WHERE id = @id", _connection);
            cmd.Parameters.AddWithValue("@id", id);
            return cmd.ExecuteNonQuery() > 0;
        }
    }

    public int SavePipelineValidationRun(PipelineValidationRunResult result)
    {
        var json = JsonSerializer.Serialize(result, JsonOptions);
        lock (_lock)
        {
            using var cmd = new SqliteCommand(@"
                INSERT INTO pipeline_validation_runs (project_id, all_passed, result_json, evaluated_at)
                VALUES (@pid, @passed, @json, @at);
                SELECT last_insert_rowid();", _connection);
            cmd.Parameters.AddWithValue("@pid", result.ProjectId);
            cmd.Parameters.AddWithValue("@passed", result.AllPassed ? 1 : 0);
            cmd.Parameters.AddWithValue("@json", json);
            cmd.Parameters.AddWithValue("@at", result.EvaluatedAt.ToString("o"));
            result.ValidationRunId = Convert.ToInt32(cmd.ExecuteScalar());
            return result.ValidationRunId;
        }
    }

    public PipelineValidationRunResult? GetLatestPipelineValidation(int projectId)
    {
        lock (_lock)
        {
            using var cmd = new SqliteCommand(@"
                SELECT id, result_json FROM pipeline_validation_runs
                WHERE project_id = @pid ORDER BY id DESC LIMIT 1", _connection);
            cmd.Parameters.AddWithValue("@pid", projectId);
            using var reader = cmd.ExecuteReader();
            if (!reader.Read())
                return null;

            var result = JsonSerializer.Deserialize<PipelineValidationRunResult>(reader.GetString(1), JsonOptions);
            if (result != null)
                result.ValidationRunId = reader.GetInt32(0);
            return result;
        }
    }

    private static PipelineProjectDocument DeserializePipeline(string json) =>
        JsonSerializer.Deserialize<PipelineProjectDocument>(json, JsonOptions) ?? new PipelineProjectDocument();

    private static TransferRecipeDocument DeserializeDocument(string json) =>
        JsonSerializer.Deserialize<TransferRecipeDocument>(json, JsonOptions)
        ?? new TransferRecipeDocument();

    private static string FormatTable(string schema, string table) =>
        string.IsNullOrWhiteSpace(table) ? "" : $"{schema}.{table}";

    public void Dispose()
    {
        _connection.Dispose();
    }
}
