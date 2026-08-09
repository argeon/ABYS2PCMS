using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Options;
using MigrationEngine.Checkpoint;
using MigrationShared.Enums;
using MigrationShared.Models;
using MigrationWeb.Services;
using MigrationWeb.Services.MssqlCopy;

namespace MigrationWeb.Controllers;

/// <summary>
/// Isolated MSSQL→MSSQL wizard API. Does not touch Oracle MigrationEngine / WizardController.
/// </summary>
[Route("api/wizard-mssql")]
[ApiController]
public class WizardMssqlController : ControllerBase
{
    private readonly ILogger<WizardMssqlController> _logger;
    private readonly HistoryDataService _historyService;
    private readonly IWebHostEnvironment _environment;
    private readonly IOptions<MssqlCopyCheckpointOptions> _checkpointOptions;
    private readonly IOptions<CheckpointOptions> _historyCheckpointOptions;

    public WizardMssqlController(
        ILogger<WizardMssqlController> logger,
        HistoryDataService historyService,
        IWebHostEnvironment environment,
        IOptions<MssqlCopyCheckpointOptions> checkpointOptions,
        IOptions<CheckpointOptions> historyCheckpointOptions)
    {
        _logger = logger;
        _historyService = historyService;
        _environment = environment;
        _checkpointOptions = checkpointOptions;
        _historyCheckpointOptions = historyCheckpointOptions;
    }

    private string EnginePath => MssqlCopyEngineLauncher.GetEngineDirectory(_environment.ContentRootPath);

    [HttpPost("test-source")]
    public Task<IActionResult> TestSource([FromBody] MssqlSideConnectionRequest request) =>
        TestMssqlAsync(request, "source");

    [HttpPost("test-target")]
    public Task<IActionResult> TestTarget([FromBody] MssqlSideConnectionRequest request) =>
        TestMssqlAsync(request, "target");

    private async Task<IActionResult> TestMssqlAsync(MssqlSideConnectionRequest request, string side)
    {
        try
        {
            var cs = BuildMssqlConnectionString(request);
            await using var connection = new SqlConnection(cs);
            await connection.OpenAsync();
            await using var cmd = new SqlCommand("SELECT DB_NAME()", connection);
            var databaseName = await cmd.ExecuteScalarAsync();
            return Ok(new { success = true, connectionString = cs, databaseName, side });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "MSSQL {Side} connection test failed", side);
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpPost("list-tables")]
    public async Task<IActionResult> ListTables([FromBody] MssqlListTablesRequest request)
    {
        try
        {
            var schema = string.IsNullOrWhiteSpace(request.Schema) ? "dbo" : request.Schema.Trim();
            var includeViews = request.IncludeViews ?? true;
            // Default light: skip per-view base resolve (was N+1 and froze the UI).
            // Set includeViewBases=true only when needed.
            var includeViewBases = request.IncludeViewBases ?? false;

            await using var connection = new SqlConnection(request.ConnectionString);
            await connection.OpenAsync();

            // Fast catalog: partition rows only for tables; views get 0 (engine estimates later).
            var sql = includeViews
                ? @"
SELECT o.name AS object_name,
       CASE o.type WHEN 'V' THEN 'VIEW' ELSE 'TABLE' END AS object_type,
       CASE WHEN o.type = 'U' THEN ISNULL(ps.row_count, 0) ELSE 0 END AS estimated_rows
FROM sys.objects o
INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
LEFT JOIN (
    SELECT p.object_id, SUM(p.rows) AS row_count
    FROM sys.partitions p
    WHERE p.index_id IN (0, 1)
    GROUP BY p.object_id
) ps ON ps.object_id = o.object_id AND o.type = 'U'
WHERE s.name = @schema AND o.is_ms_shipped = 0 AND o.type IN ('U', 'V')
ORDER BY o.name"
                : @"
SELECT t.name AS object_name,
       'TABLE' AS object_type,
       ISNULL(ps.row_count, 0) AS estimated_rows
FROM sys.tables t
INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
LEFT JOIN (
    SELECT p.object_id, SUM(p.rows) AS row_count
    FROM sys.partitions p
    WHERE p.index_id IN (0, 1)
    GROUP BY p.object_id
) ps ON ps.object_id = t.object_id
WHERE s.name = @schema AND t.is_ms_shipped = 0
ORDER BY t.name";

            await using var cmd = new SqlCommand(sql, connection) { CommandTimeout = 60 };
            cmd.Parameters.AddWithValue("@schema", schema);

            var pending = new List<(string name, string type, long rows)>();
            await using (var reader = await cmd.ExecuteReaderAsync())
            {
                while (await reader.ReadAsync())
                {
                    pending.Add((
                        reader.GetString(0),
                        reader.GetString(1),
                        reader.IsDBNull(2) ? 0L : Convert.ToInt64(reader.GetValue(2))));
                }
            }

            Dictionary<string, List<string>>? basesByView = null;
            if (includeViews && includeViewBases)
                basesByView = await ResolveAllViewBaseTablesAsync(connection, schema);

            var tables = pending.Select(item =>
            {
                IReadOnlyList<string> baseTables = Array.Empty<string>();
                if (item.type == "VIEW" && basesByView != null
                    && basesByView.TryGetValue(item.name, out var bases))
                    baseTables = bases;

                return (object)new
                {
                    name = item.name,
                    objectType = item.type,
                    rowCount = item.rows,
                    baseTables
                };
            }).ToList();

            return Ok(new
            {
                success = true,
                tables,
                schema,
                count = tables.Count,
                includeViews,
                includeViewBases
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to list MSSQL tables");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    private static async Task<Dictionary<string, List<string>>> ResolveAllViewBaseTablesAsync(
        SqlConnection conn, string schema)
    {
        const string sql = @"
SELECT o.name AS view_name,
       ISNULL(rs.name, @schema) AS ref_schema,
       ro.name AS ref_name
FROM sys.sql_expression_dependencies d
INNER JOIN sys.objects o ON o.object_id = d.referencing_id
INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
INNER JOIN sys.objects ro ON ro.object_id = d.referenced_id
INNER JOIN sys.schemas rs ON rs.schema_id = ro.schema_id
WHERE s.name = @schema AND o.type = 'V'
  AND ro.type = 'U' AND ISNULL(ro.is_ms_shipped, 0) = 0";

        var map = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 60 };
        cmd.Parameters.AddWithValue("@schema", schema);
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var view = reader.GetString(0);
            var fq = $"{reader.GetString(1)}.{reader.GetString(2)}";
            if (!map.TryGetValue(view, out var list))
            {
                list = new List<string>();
                map[view] = list;
            }
            if (!list.Contains(fq, StringComparer.OrdinalIgnoreCase))
                list.Add(fq);
        }
        return map;
    }

    [HttpPost("check-target-data")]
    public async Task<IActionResult> CheckTargetData([FromBody] MssqlCheckTargetDataRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.MssqlConnectionString))
            return Ok(new { success = false, error = "Hedef MSSQL bağlantı dizesi gerekli." });

        var tables = request.Tables ?? new List<string>();
        if (tables.Count == 0)
            return Ok(new { success = false, error = "En az bir tablo seçilmeli." });

        var schema = string.IsNullOrWhiteSpace(request.Schema) ? "dbo" : request.Schema.Trim();

        try
        {
            await using var conn = new SqlConnection(request.MssqlConnectionString);
            await conn.OpenAsync();

            var details = new List<object>();
            long totalRows = 0;
            var hasAnyRows = false;

            foreach (var raw in tables.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                if (!IsSafeSqlTableName(raw))
                {
                    details.Add(new { table = raw, exists = false, rowCount = 0L, note = "Geçersiz tablo adı" });
                    continue;
                }

                var (exists, rows) = await GetRowEstimateAsync(conn, schema, raw);
                if (exists && rows > 0)
                    hasAnyRows = true;
                totalRows += rows;
                details.Add(new { table = raw, exists, rowCount = rows });
            }

            return Ok(new { success = true, hasAnyRows, totalRows, details });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "check-target-data failed");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpPost("clear-target-tables")]
    public async Task<IActionResult> ClearTargetTables([FromBody] MssqlCheckTargetDataRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.MssqlConnectionString))
            return Ok(new { success = false, error = "Hedef MSSQL bağlantı dizesi gerekli." });

        var tables = request.Tables ?? new List<string>();
        if (tables.Count == 0)
            return Ok(new { success = false, error = "En az bir tablo seçilmeli." });

        var schema = string.IsNullOrWhiteSpace(request.Schema) ? "dbo" : request.Schema.Trim();
        var results = new List<object>();
        var allOk = true;

        try
        {
            await using var conn = new SqlConnection(request.MssqlConnectionString);
            await conn.OpenAsync();

            foreach (var raw in tables.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                if (!IsSafeSqlTableName(raw))
                {
                    results.Add(new { table = raw, ok = false, error = "Geçersiz tablo adı" });
                    allOk = false;
                    continue;
                }

                var (exists, _) = await GetRowEstimateAsync(conn, schema, raw);
                if (!exists)
                {
                    results.Add(new { table = raw, ok = true, skipped = true, message = "Tablo yok; atlandı" });
                    continue;
                }

                try
                {
                    var fq = BracketQualified(schema, raw);
                    await using var cmd = new SqlCommand($"TRUNCATE TABLE {fq}", conn) { CommandTimeout = 0 };
                    await cmd.ExecuteNonQueryAsync();
                    results.Add(new { table = raw, ok = true });
                }
                catch (Exception ex)
                {
                    results.Add(new { table = raw, ok = false, error = ex.Message });
                    allOk = false;
                }
            }

            return Ok(new { success = allOk, results });
        }
        catch (Exception ex)
        {
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpPost("check-retry-needed")]
    public async Task<IActionResult> CheckRetryNeeded([FromBody] MssqlCheckTargetDataRequest request)
    {
        var tables = request.Tables ?? new List<string>();
        var schema = string.IsNullOrWhiteSpace(request.Schema) ? "dbo" : request.Schema.Trim();
        var result = new List<object>();

        try
        {
            HashSet<string> checkpointTables = new(StringComparer.OrdinalIgnoreCase);
            var sqlitePath = _checkpointOptions.Value.SqlitePath;
            if (System.IO.File.Exists(sqlitePath))
            {
                using var repo = new CheckpointRepository(sqlitePath);
                var incomplete = repo.FindLastIncompleteRun();
                if (incomplete.HasValue)
                {
                    foreach (var t in repo.GetRunTableSummary(incomplete.Value.runId))
                        checkpointTables.Add(t.tableName);
                }
            }

            if (!string.IsNullOrWhiteSpace(request.MssqlConnectionString))
            {
                await using var conn = new SqlConnection(request.MssqlConnectionString);
                await conn.OpenAsync();

                foreach (var raw in tables.Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    if (!IsSafeSqlTableName(raw)) continue;
                    var (exists, rows) = await GetRowEstimateAsync(conn, schema, raw);
                    var hasTargetData = exists && rows > 0;
                    var hasCheckpoint = checkpointTables.Contains(raw);
                    if (hasTargetData || hasCheckpoint)
                    {
                        result.Add(new
                        {
                            tableName = raw,
                            hasTargetData,
                            hasCheckpoint,
                            rowCount = rows
                        });
                    }
                }
            }

            return Ok(new { success = true, tables = result });
        }
        catch (Exception ex)
        {
            return Ok(new { success = false, error = ex.Message, tables = Array.Empty<object>() });
        }
    }

    [HttpPost("table-transfer-status")]
    public async Task<IActionResult> TableTransferStatus([FromBody] MssqlTableTransferStatusRequest request)
    {
        try
        {
            var schema = string.IsNullOrWhiteSpace(request.Schema) ? "dbo" : request.Schema.Trim();
            var rows = new List<object>();

            Dictionary<string, string> checkpointStatus = new(StringComparer.OrdinalIgnoreCase);
            var sqlitePath = _checkpointOptions.Value.SqlitePath;
            if (System.IO.File.Exists(sqlitePath))
            {
                using var repo = new CheckpointRepository(sqlitePath);
                var incomplete = repo.FindLastIncompleteRun();
                if (incomplete.HasValue)
                {
                    foreach (var t in repo.GetRunTableSummary(incomplete.Value.runId))
                    {
                        var status = t.failed > 0 ? "Failed"
                            : t.done == t.total && t.total > 0 ? "Done"
                            : t.pending > 0 ? "Pending" : "Running";
                        checkpointStatus[t.tableName] = status;
                    }
                }
            }

            await using var src = new SqlConnection(request.SourceConnectionString);
            await using var tgt = new SqlConnection(request.TargetConnectionString);
            await src.OpenAsync();
            await tgt.OpenAsync();

            foreach (var table in (request.Tables ?? new List<string>()).Distinct(StringComparer.OrdinalIgnoreCase))
            {
                if (!IsSafeSqlTableName(table)) continue;
                long srcCount = 0, tgtCount = 0;
                var srcExists = false;
                var tgtExists = false;
                try
                {
                    var (se, _) = await GetRowEstimateAsync(src, schema, table);
                    srcExists = se;
                    if (se) srcCount = await CountExactAsync(src, schema, table);
                }
                catch { /* ignore */ }

                try
                {
                    var (te, _) = await GetRowEstimateAsync(tgt, schema, table);
                    tgtExists = te;
                    if (te) tgtCount = await CountExactAsync(tgt, schema, table);
                }
                catch { /* ignore */ }

                checkpointStatus.TryGetValue(table, out var cpStatus);
                rows.Add(new
                {
                    table,
                    sourceExists = srcExists,
                    targetExists = tgtExists,
                    sourceCount = srcCount,
                    targetCount = tgtCount,
                    match = srcExists && tgtExists && srcCount == tgtCount,
                    checkpointStatus = cpStatus ?? "-"
                });
            }

            return Ok(new { success = true, tables = rows });
        }
        catch (Exception ex)
        {
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpPost("start-migration")]
    public async Task<IActionResult> StartMigration([FromBody] MssqlStartMigrationRequest request)
    {
        try
        {
            var degreeOfParallelism = request.DegreeOfParallelism is > 0 and <= 64 ? request.DegreeOfParallelism.Value : 8;
            var batchSize = request.BatchSize is > 0 ? request.BatchSize.Value : 50_000;
            var tables = request.Tables ?? new List<string>();
            if (tables.Count == 0)
                return Ok(new { success = false, error = "Select at least one table before saving." });

            if (string.IsNullOrWhiteSpace(request.SourceConnectionString) ||
                string.IsNullOrWhiteSpace(request.TargetConnectionString))
                return Ok(new { success = false, error = "Source and target connection strings are required." });

            var enginePath = EnginePath;
            if (!Directory.Exists(enginePath))
            {
                Directory.CreateDirectory(enginePath);
            }

            // Relative to MssqlCopyEngine exe directory (portable across hosts).
            const string checkpointDbPath = "mssql_copy_checkpoint.db";
            var schema = string.IsNullOrWhiteSpace(request.Schema) ? "dbo" : request.Schema.Trim();

            var validationMode = Enum.TryParse<ValidationMode>(request.ValidationMode, ignoreCase: true, out var vm)
                ? vm
                : ValidationMode.CountOnly;

            // Reuse MigrationConfig shape: Oracle* = source MSSQL, Mssql* = target MSSQL
            var config = new
            {
                Migration = new
                {
                    OracleConnectionString = request.SourceConnectionString,
                    MssqlConnectionString = request.TargetConnectionString,
                    OracleSchema = schema,
                    DegreeOfParallelism = degreeOfParallelism,
                    BatchSize = batchSize,
                    Tables = tables,
                    ExcludeTables = Array.Empty<string>(),
                    MigrateIndexes = request.MigrateIndexes,
                    MigrateTriggers = request.MigrateTriggers,
                    MigrateForeignKeys = request.MigrateForeignKeys,
                    MigratePrimaryKeys = request.MigratePrimaryKeys,
                    MigrateUniqueConstraints = request.MigrateUniqueConstraints,
                    MigrateCheckConstraints = request.MigrateCheckConstraints,
                    ValidationMode = validationMode,
                    ValidatePerTableAfterLoad = request.ValidatePerTableAfterLoad,
                    ValidationFailFast = request.ValidationFailFast,
                    AutoStart = request.AutoStart,
                    UseBulkLoggedRecovery = false,
                    TableRetryModes = (request.TableRetryModes ?? new Dictionary<string, string>())
                        .Where(kv => Enum.TryParse<TableRetryMode>(kv.Value, true, out _))
                        .ToDictionary(kv => kv.Key, kv => Enum.Parse<TableRetryMode>(kv.Value, true))
                },
                Checkpoint = new { SqlitePath = checkpointDbPath }
            };

            var configPath = Path.Combine(enginePath, "appsettings.json");
            await System.IO.File.WriteAllTextAsync(configPath, JsonSerializer.Serialize(config, new JsonSerializerOptions
            {
                WriteIndented = true,
                Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
            }));

            return Ok(new { success = true, configPath, enginePath });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to save MSSQL copy configuration");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpGet("resume-info")]
    public IActionResult GetResumeInfo()
    {
        try
        {
            var sqlitePath = _checkpointOptions.Value.SqlitePath;
            if (!System.IO.File.Exists(sqlitePath))
                return Ok(new { hasResumable = false });

            using var repo = new CheckpointRepository(sqlitePath);
            var incomplete = repo.FindLastIncompleteRun();
            if (!incomplete.HasValue)
                return Ok(new { hasResumable = false });

            var (runId, startTime, cfg) = incomplete.Value;
            var summary = repo.GetRunTableSummary(runId);
            return Ok(new
            {
                hasResumable = true,
                runId,
                startedAt = startTime,
                tableCount = summary.Count,
                doneCount = summary.Count(t => t.done == t.total && t.total > 0),
                pendingCount = summary.Count(t => t.pending > 0 || t.failed > 0),
                oracleSchema = cfg?.OracleSchema,
                tables = summary.Select(t => new
                {
                    tableName = t.tableName,
                    done = t.done,
                    pending = t.pending,
                    failed = t.failed,
                    total = t.total,
                    isComplete = t.done == t.total && t.total > 0
                })
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get MSSQL copy resume info");
            return Ok(new { hasResumable = false });
        }
    }

    [HttpGet("progress")]
    public IActionResult GetProgress()
    {
        try
        {
            var sqlitePath = _checkpointOptions.Value.SqlitePath;
            if (!System.IO.File.Exists(sqlitePath))
                return Ok(new { success = true, hasRun = false });

            using var repo = new CheckpointRepository(sqlitePath);
            var incomplete = repo.FindLastIncompleteRun();

            int runId;
            DateTime startedAt;
            string status;
            MigrationConfig? cfg;

            if (incomplete.HasValue)
            {
                runId = incomplete.Value.runId;
                startedAt = incomplete.Value.startTime;
                status = "RUNNING";
                cfg = incomplete.Value.config;
            }
            else
            {
                // Latest run (completed/failed)
                using var connection = new SqliteConnection($"Data Source={sqlitePath}");
                connection.Open();
                using var cmd = new SqliteCommand(@"
SELECT run_id, start_time, status, config_json
FROM migration_runs
ORDER BY run_id DESC
LIMIT 1", connection);
                using var reader = cmd.ExecuteReader();
                if (!reader.Read())
                    return Ok(new { success = true, hasRun = false });

                runId = reader.GetInt32(0);
                startedAt = DateTime.Parse(reader.GetString(1));
                status = reader.GetString(2);
                cfg = null;
                try { cfg = JsonSerializer.Deserialize<MigrationConfig>(reader.GetString(3)); } catch { /* ignore */ }
            }

            // Row-level progress (partition summary alone hides Running + rows_processed)
            var rows = new List<(string tableName, string status, long rowsProcessed, long totalRows, string? error)>();
            using (var connection = new SqliteConnection($"Data Source={sqlitePath}"))
            {
                connection.Open();
                using var cmd = new SqliteCommand(@"
SELECT table_name, status, rows_processed, total_rows, error_message
FROM table_checkpoints
WHERE run_id = @runId
ORDER BY
  CASE status
    WHEN 'Running' THEN 0
    WHEN 'Failed' THEN 1
    WHEN 'Pending' THEN 2
    ELSE 3
  END,
  table_name", connection);
                cmd.Parameters.AddWithValue("@runId", runId);
                using var reader = cmd.ExecuteReader();
                while (reader.Read())
                {
                    rows.Add((
                        reader.GetString(0),
                        reader.GetString(1),
                        reader.IsDBNull(2) ? 0L : reader.GetInt64(2),
                        reader.IsDBNull(3) ? 0L : reader.GetInt64(3),
                        reader.IsDBNull(4) ? null : reader.GetString(4)));
                }
            }

            var running = rows.Count(t => t.status.Equals("Running", StringComparison.OrdinalIgnoreCase));
            var doneCount = rows.Count(t => t.status.Equals("Done", StringComparison.OrdinalIgnoreCase));
            var failedCount = rows.Count(t => t.status.Equals("Failed", StringComparison.OrdinalIgnoreCase));

            return Ok(new
            {
                success = true,
                hasRun = true,
                runId,
                status,
                startedAt,
                schema = cfg?.OracleSchema,
                degreeOfParallelism = cfg?.DegreeOfParallelism ?? 0,
                summary = new
                {
                    total = rows.Count,
                    done = doneCount,
                    running,
                    failed = failedCount,
                    pending = rows.Count - doneCount - running - failedCount
                },
                tables = rows.Select(t =>
                {
                    var percent = t.totalRows > 0
                        ? Math.Round(100.0 * Math.Min(t.rowsProcessed, t.totalRows) / t.totalRows, 1)
                        : t.status.Equals("Done", StringComparison.OrdinalIgnoreCase) ? 100.0
                        : t.status.Equals("Running", StringComparison.OrdinalIgnoreCase) ? 1.0
                        : 0.0;
                    return new
                    {
                        tableName = t.tableName,
                        status = t.status,
                        rowsProcessed = t.rowsProcessed,
                        totalRows = t.totalRows,
                        done = t.status.Equals("Done", StringComparison.OrdinalIgnoreCase) ? 1 : 0,
                        pending = t.status.Equals("Pending", StringComparison.OrdinalIgnoreCase) ? 1 : 0,
                        failed = t.status.Equals("Failed", StringComparison.OrdinalIgnoreCase) ? 1 : 0,
                        total = 1,
                        percent,
                        error = t.error
                    };
                })
            });
        }
        catch (Exception ex)
        {
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpGet("connection-profiles")]
    public IActionResult GetConnectionProfiles([FromQuery] string? type = null)
    {
        try
        {
            var profiles = _historyService.GetConnectionProfiles(type ?? "MssqlCopy");
            return Ok(new { success = true, profiles });
        }
        catch (Exception ex)
        {
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpPost("save-profile")]
    public IActionResult SaveProfile([FromBody] MssqlSaveProfileRequest request)
    {
        try
        {
            using var connection = new SqliteConnection($"Data Source={_historyCheckpointOptions.Value.SqlitePath}");
            connection.Open();
            ConnectionProfileSchemaMigrator.EnsureColumns(connection);

            string? configJson = null;
            if (request.Tables != null && request.Tables.Count > 0)
            {
                configJson = JsonSerializer.Serialize(new
                {
                    sourceConnectionString = request.SourceConnectionString,
                    targetConnectionString = request.TargetConnectionString,
                    schema = request.Schema ?? "dbo",
                    sourcePassword = request.SourcePassword,
                    targetPassword = request.TargetPassword,
                    sourceHost = request.SourceHost,
                    sourceUsername = request.SourceUsername,
                    sourceDatabase = request.SourceDatabase,
                    sourceAuthType = request.SourceAuthType,
                    sourceTrustCert = request.SourceTrustCert,
                    targetHost = request.TargetHost,
                    targetUsername = request.TargetUsername,
                    targetDatabase = request.TargetDatabase,
                    targetAuthType = request.TargetAuthType,
                    targetTrustCert = request.TargetTrustCert,
                    tables = request.Tables,
                    degreeOfParallelism = request.DegreeOfParallelism ?? 4,
                    batchSize = request.BatchSize ?? 50000,
                    migrateIndexes = request.MigrateIndexes,
                    migrateTriggers = request.MigrateTriggers,
                    migrateForeignKeys = request.MigrateForeignKeys,
                    migratePrimaryKeys = request.MigratePrimaryKeys,
                    migrateUniqueConstraints = request.MigrateUniqueConstraints,
                    migrateCheckConstraints = request.MigrateCheckConstraints,
                    validationMode = request.ValidationMode,
                    validatePerTableAfterLoad = request.ValidatePerTableAfterLoad,
                    validationFailFast = request.ValidationFailFast,
                    autoStart = request.AutoStart
                });
            }

            const string sql = @"INSERT INTO connection_profiles
                (profile_name, connection_type, host, port, service_name, database_name,
                 username, schema_name, auth_type, trust_cert, connection_string, config_json, created_at, use_count,
                 is_deleted, deleted_at)
                VALUES (@name, @type, @host, NULL, NULL, @database, @username, @schema,
                        @authType, @trustCert, @connectionString, @configJson, @createdAt, 0, 0, NULL)
                ON CONFLICT(profile_name) DO UPDATE SET
                    connection_type = excluded.connection_type,
                    host = excluded.host,
                    database_name = excluded.database_name,
                    username = excluded.username,
                    schema_name = excluded.schema_name,
                    auth_type = excluded.auth_type,
                    trust_cert = excluded.trust_cert,
                    connection_string = excluded.connection_string,
                    config_json = excluded.config_json,
                    is_deleted = 0,
                    deleted_at = NULL";

            using var cmd = new SqliteCommand(sql, connection);
            cmd.Parameters.AddWithValue("@name", request.ProfileName ?? "MssqlCopy");
            cmd.Parameters.AddWithValue("@type", "MssqlCopy");
            cmd.Parameters.AddWithValue("@host", (object?)request.SourceHost ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@database", (object?)request.SourceDatabase ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@username", (object?)request.SourceUsername ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@schema", (object?)(request.Schema ?? "dbo") ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@authType", (object?)request.SourceAuthType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@trustCert", request.SourceTrustCert ? 1 : 0);
            cmd.Parameters.AddWithValue("@connectionString", (object?)request.SourceConnectionString ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@configJson", (object?)configJson ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@createdAt", DateTime.UtcNow.ToString("O"));
            cmd.ExecuteNonQuery();

            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to save MSSQL copy profile");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    private static string BuildMssqlConnectionString(MssqlSideConnectionRequest request)
    {
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = request.Server,
            InitialCatalog = request.Database
        };

        if (request.AuthType == "sql")
        {
            builder.UserID = request.Username;
            builder.Password = request.Password;
        }
        else
        {
            builder.IntegratedSecurity = true;
        }

        builder.TrustServerCertificate = request.TrustCert || request.AuthType == "sql";
        return builder.ConnectionString;
    }

    private static bool IsSafeSqlTableName(string name) =>
        !string.IsNullOrWhiteSpace(name) && Regex.IsMatch(name, @"^[A-Za-z_][A-Za-z0-9_]*$");

    private static string BracketQualified(string schema, string table) =>
        $"[{schema.Replace("]", "]]")}].[{table.Replace("]", "]]")}]";

    private static async Task<(bool exists, long rows)> GetRowEstimateAsync(SqlConnection conn, string schema, string table)
    {
        const string sql = @"
SELECT ISNULL(SUM(p.rows), 0)
FROM sys.tables t
INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
LEFT JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE s.name = @schema AND t.name = @table
GROUP BY t.object_id";

        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@table", table);
        var val = await cmd.ExecuteScalarAsync();
        if (val == null || val == DBNull.Value)
            return (false, 0);
        return (true, Convert.ToInt64(val));
    }

    private static async Task<long> CountExactAsync(SqlConnection conn, string schema, string table)
    {
        await using var cmd = new SqlCommand($"SELECT COUNT_BIG(*) FROM {BracketQualified(schema, table)}", conn)
        {
            CommandTimeout = 0
        };
        return Convert.ToInt64(await cmd.ExecuteScalarAsync());
    }
}

public class MssqlSideConnectionRequest
{
    public string Server { get; set; } = "";
    public string AuthType { get; set; } = "sql";
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    public string Database { get; set; } = "";
    public bool TrustCert { get; set; } = true;
}

public class MssqlListTablesRequest
{
    public string ConnectionString { get; set; } = "";
    public string Schema { get; set; } = "dbo";
    /// <summary>Include views in catalog (default true).</summary>
    public bool? IncludeViews { get; set; }
    /// <summary>Resolve view→base tables in one batch (slower; default false).</summary>
    public bool? IncludeViewBases { get; set; }
}

public class MssqlCheckTargetDataRequest
{
    public string MssqlConnectionString { get; set; } = "";
    public string Schema { get; set; } = "dbo";
    public List<string>? Tables { get; set; }
}

public class MssqlTableTransferStatusRequest
{
    public string SourceConnectionString { get; set; } = "";
    public string TargetConnectionString { get; set; } = "";
    public string Schema { get; set; } = "dbo";
    public List<string>? Tables { get; set; }
}

public class MssqlStartMigrationRequest
{
    public string SourceConnectionString { get; set; } = "";
    public string TargetConnectionString { get; set; } = "";
    public string Schema { get; set; } = "dbo";
    public List<string>? Tables { get; set; }
    public int? DegreeOfParallelism { get; set; }
    public int? BatchSize { get; set; }
    public bool MigrateIndexes { get; set; }
    public bool MigrateTriggers { get; set; }
    public bool MigrateForeignKeys { get; set; }
    public bool MigratePrimaryKeys { get; set; } = true;
    public bool MigrateUniqueConstraints { get; set; }
    public bool MigrateCheckConstraints { get; set; }
    public string? ValidationMode { get; set; }
    public bool ValidatePerTableAfterLoad { get; set; } = true;
    public bool ValidationFailFast { get; set; }
    public bool AutoStart { get; set; }
    public Dictionary<string, string>? TableRetryModes { get; set; }
}

public class MssqlSaveProfileRequest
{
    public string? ProfileName { get; set; }
    public string? SourceConnectionString { get; set; }
    public string? TargetConnectionString { get; set; }
    public string? Schema { get; set; }
    public string? SourcePassword { get; set; }
    public string? TargetPassword { get; set; }
    public string? SourceHost { get; set; }
    public string? SourceUsername { get; set; }
    public string? SourceDatabase { get; set; }
    public string? SourceAuthType { get; set; }
    public bool SourceTrustCert { get; set; } = true;
    public string? TargetHost { get; set; }
    public string? TargetUsername { get; set; }
    public string? TargetDatabase { get; set; }
    public string? TargetAuthType { get; set; }
    public bool TargetTrustCert { get; set; } = true;
    public List<string>? Tables { get; set; }
    public int? DegreeOfParallelism { get; set; }
    public int? BatchSize { get; set; }
    public bool MigrateIndexes { get; set; }
    public bool MigrateTriggers { get; set; }
    public bool MigrateForeignKeys { get; set; }
    public bool MigratePrimaryKeys { get; set; } = true;
    public bool MigrateUniqueConstraints { get; set; }
    public bool MigrateCheckConstraints { get; set; }
    public string? ValidationMode { get; set; }
    public bool ValidatePerTableAfterLoad { get; set; }
    public bool ValidationFailFast { get; set; }
    public bool AutoStart { get; set; }
}

public class MssqlCopyCheckpointOptions
{
    public string SqlitePath { get; set; } = "mssql_copy_checkpoint.db";
}
