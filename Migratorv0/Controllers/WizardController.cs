using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Options;
using Oracle.ManagedDataAccess.Client;
using Microsoft.Data.SqlClient;
using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;
using MigrationEngine.Checkpoint;
using MigrationShared.Enums;
using MigrationShared.Models;
using MigrationWeb.Services;

namespace MigrationWeb.Controllers;

[Route("api/[controller]")]
[ApiController]
public class WizardController : ControllerBase
{
    private readonly ILogger<WizardController> _logger;
    private readonly IConfiguration _configuration;
    private readonly HistoryDataService _historyService;
    private readonly IWebHostEnvironment _environment;
    private readonly IOptions<CheckpointOptions> _checkpointOptions;

    public WizardController(
        ILogger<WizardController> logger,
        IConfiguration configuration,
        HistoryDataService historyService,
        IWebHostEnvironment environment,
        IOptions<CheckpointOptions> checkpointOptions)
    {
        _logger = logger;
        _configuration = configuration;
        _historyService = historyService;
        _environment = environment;
        _checkpointOptions = checkpointOptions;
    }

    [HttpPost("test-oracle")]
    public async Task<IActionResult> TestOracleConnection([FromBody] OracleConnectionRequest request)
    {
        try
        {
            var connectionString =
                $"User Id={request.Username};Password={request.Password};Data Source={request.Host}:{request.Port}/{request.Service};" +
                "Max Pool Size=200;Min Pool Size=0;Connection Timeout=180;Validate Connection=true;";
            
            using var connection = new OracleConnection(connectionString);
            await connection.OpenAsync();

            var tableCountSql = $"SELECT COUNT(*) FROM all_tables WHERE owner = :schema";
            using var cmd = new OracleCommand(tableCountSql, connection);
            cmd.Parameters.Add("schema", OracleDbType.Varchar2).Value = request.Schema.ToUpper();
            
            var tableCount = Convert.ToInt32(await cmd.ExecuteScalarAsync());

            return Ok(new
            {
                success = true,
                connectionString = connectionString,
                tableCount = tableCount
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Oracle connection test failed");
            return Ok(new
            {
                success = false,
                error = ex.Message
            });
        }
    }

    [HttpPost("test-mssql")]
    public async Task<IActionResult> TestMssqlConnection([FromBody] MssqlConnectionRequest request)
    {
        try
        {
            var connectionString = BuildMssqlConnectionString(request);
            
            using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync();

            using var cmd = new SqlCommand("SELECT DB_NAME()", connection);
            var databaseName = await cmd.ExecuteScalarAsync();

            return Ok(new
            {
                success = true,
                connectionString = connectionString,
                databaseName = databaseName
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "MSSQL connection test failed");
            return Ok(new
            {
                success = false,
                error = ex.Message
            });
        }
    }

    [HttpPost("list-tables")]
    public async Task<IActionResult> ListTables([FromBody] ListTablesRequest request)
    {
        try
        {
            using var connection = new OracleConnection(request.ConnectionString);
            await connection.OpenAsync();

            var sql = @"
                SELECT 
                    table_name,
                    COALESCE(num_rows, 0) as estimated_rows
                FROM all_tables
                WHERE owner = :schema
                ORDER BY table_name";

            using var cmd = new OracleCommand(sql, connection);
            cmd.Parameters.Add("schema", OracleDbType.Varchar2).Value = request.Schema.ToUpper();

            var tables = new List<object>();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                tables.Add(new
                {
                    name = reader.GetString(0),
                    rowCount = reader.IsDBNull(1) ? 0 : reader.GetInt64(1)
                });
            }

            return Ok(new
            {
                success = true,
                tables = tables
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to list tables");
            return Ok(new
            {
                success = false,
                error = ex.Message
            });
        }
    }

    /// <summary>
    /// Seçilen tablolar için hedef MSSQL (varsayılan dbo) üzerinde yaklaşık satır sayısını döner.
    /// </summary>
    [HttpPost("check-target-data")]
    public async Task<IActionResult> CheckTargetData([FromBody] CheckTargetDataRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.MssqlConnectionString))
            return Ok(new { success = false, error = "MSSQL bağlantı dizesi gerekli." });

        var tables = request.Tables ?? new List<string>();
        if (tables.Count == 0)
            return Ok(new { success = false, error = "En az bir tablo seçilmeli." });

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
                    details.Add(new { table = raw, exists = false, rowCount = 0L, note = "Geçersiz tablo adı (yalnızca harf, rakam, _)" });
                    continue;
                }

                var (exists, rows) = await GetMssqlUserTableRowEstimateAsync(conn, raw);
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

    /// <summary>
    /// Seçilen dbo tablolarında TRUNCATE dener. FK sırası veya izin hatalarında tablo bazında hata döner.
    /// </summary>
    [HttpPost("clear-target-tables")]
    public async Task<IActionResult> ClearTargetTables([FromBody] CheckTargetDataRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.MssqlConnectionString))
            return Ok(new { success = false, error = "MSSQL bağlantı dizesi gerekli." });

        var tables = request.Tables ?? new List<string>();
        if (tables.Count == 0)
            return Ok(new { success = false, error = "En az bir tablo seçilmeli." });

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

                var (exists, _) = await GetMssqlUserTableRowEstimateAsync(conn, raw);
                if (!exists)
                {
                    results.Add(new { table = raw, ok = true, skipped = true, message = "Tablo yok; atlandı" });
                    continue;
                }

                try
                {
                    var fq = BracketQualifiedDboTable(raw);
                    await using var cmd = new SqlCommand($"TRUNCATE TABLE {fq}", conn) { CommandTimeout = 0 };
                    await cmd.ExecuteNonQueryAsync();
                    results.Add(new { table = raw, ok = true });
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "TRUNCATE failed for {Table}", raw);
                    results.Add(new { table = raw, ok = false, error = ex.Message });
                    allOk = false;
                }
            }

            return Ok(new { success = allOk, results });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "clear-target-tables failed");
            return Ok(new { success = false, error = ex.Message, results });
        }
    }

    private static bool IsSafeSqlTableName(string name) =>
        !string.IsNullOrWhiteSpace(name)
        && name.Length <= 128
        && name.All(c => char.IsLetterOrDigit(c) || c == '_');

    private static string BracketQualifiedDboTable(string name) =>
        $"[dbo].[{name.Replace("]", "]]")}]";

    private static async Task<(bool exists, long rows)> GetMssqlUserTableRowEstimateAsync(SqlConnection conn, string table)
    {
        await using (var idCmd = new SqlCommand(
                         "SELECT OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@tbl), N'U')", conn))
        {
            idCmd.Parameters.Add("@tbl", System.Data.SqlDbType.NVarChar, 128).Value = table;
            var oidObj = await idCmd.ExecuteScalarAsync();
            if (oidObj is null or DBNull)
                return (false, 0);
            var oid = Convert.ToInt32(oidObj);
            if (oid <= 0)
                return (false, 0);

            await using var rowCmd = new SqlCommand(
                """
                SELECT COALESCE(SUM(CAST(p.rows AS BIGINT)), 0)
                FROM sys.partitions p
                WHERE p.object_id = @oid AND (p.index_id = 0 OR p.index_id = 1)
                """,
                conn);
            rowCmd.Parameters.Add("@oid", System.Data.SqlDbType.Int).Value = oid;
            var sumObj = await rowCmd.ExecuteScalarAsync();
            var rows = sumObj is null or DBNull ? 0L : Convert.ToInt64(sumObj);
            return (true, rows);
        }
    }

    private Dictionary<string, string> LoadLatestTableStatuses()
    {
        var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var sqlite = new SqliteConnection($"Data Source={_checkpointOptions.Value.SqlitePath}");
            sqlite.Open();
            const string sql = @"
                WITH run AS (SELECT MAX(run_id) AS rid FROM migration_runs),
                x AS (
                  SELECT table_name,
                         MAX(CASE WHEN status='Failed' THEN 1 ELSE 0 END) AS has_failed,
                         MAX(CASE WHEN status='Running' THEN 1 ELSE 0 END) AS has_running,
                         SUM(CASE WHEN status IN ('Done','Skipped') THEN 1 ELSE 0 END) AS done_or_skipped,
                         COUNT(*) AS total_parts
                  FROM table_checkpoints
                  WHERE run_id = (SELECT rid FROM run)
                  GROUP BY table_name
                )
                SELECT table_name,
                       CASE
                         WHEN has_failed = 1 THEN 'Failed'
                         WHEN has_running = 1 THEN 'Running'
                         WHEN total_parts > 0 AND done_or_skipped = total_parts THEN 'Completed'
                         ELSE 'Pending'
                       END AS status
                FROM x";
            using var cmd = new SqliteCommand(sql, sqlite);
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                dict[reader.GetString(0)] = reader.GetString(1);
            }
        }
        catch
        {
        }
        return dict;
    }

    private static async Task<long> GetOracleTableCountAsync(OracleConnection conn, string schema, string table)
    {
        var sql = $"SELECT COUNT(*) FROM \"{schema.ToUpperInvariant()}\".\"{table.ToUpperInvariant()}\"";
        await using var cmd = new OracleCommand(sql, conn);
        var val = await cmd.ExecuteScalarAsync();
        return val is null or DBNull ? 0L : Convert.ToInt64(val);
    }

    private static async Task<long> GetMssqlTableCountAsync(SqlConnection conn, string table)
    {
        try
        {
            var sql = $"SELECT COUNT_BIG(*) FROM {BracketQualifiedDboTable(table)}";
            await using var cmd = new SqlCommand(sql, conn);
            var val = await cmd.ExecuteScalarAsync();
            return val is null or DBNull ? 0L : Convert.ToInt64(val);
        }
        catch
        {
            return 0L;
        }
    }

    [HttpPost("table-transfer-status")]
    public async Task<IActionResult> GetTableTransferStatus([FromBody] TableTransferStatusRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.OracleConnectionString) ||
            string.IsNullOrWhiteSpace(request.OracleSchema) ||
            string.IsNullOrWhiteSpace(request.MssqlConnectionString))
        {
            return Ok(new { success = false, error = "Oracle/MSSQL bağlantı bilgileri eksik." });
        }

        var tables = request.Tables?.Where(t => !string.IsNullOrWhiteSpace(t))
            .Select(t => t.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList() ?? new List<string>();
        if (tables.Count == 0)
            return Ok(new { success = false, error = "En az bir tablo seçilmelidir." });

        try
        {
            await using var oracle = new OracleConnection(request.OracleConnectionString);
            await oracle.OpenAsync();
            await using var mssql = new SqlConnection(request.MssqlConnectionString);
            await mssql.OpenAsync();

            var latestStatus = LoadLatestTableStatuses();
            var result = new List<object>();
            foreach (var table in tables)
            {
                if (!IsSafeSqlTableName(table) || !IsSafeSqlTableName(request.OracleSchema))
                {
                    result.Add(new
                    {
                        tableName = table,
                        sourceRows = 0L,
                        targetRows = 0L,
                        difference = 0L,
                        matched = false,
                        transferStatus = "InvalidName",
                        message = "Geçersiz tablo/schema adı"
                    });
                    continue;
                }

                var sourceRows = await GetOracleTableCountAsync(oracle, request.OracleSchema, table);
                var targetRows = await GetMssqlTableCountAsync(mssql, table);
                var diff = sourceRows - targetRows;
                result.Add(new
                {
                    tableName = table,
                    sourceRows,
                    targetRows,
                    difference = diff,
                    matched = diff == 0,
                    transferStatus = latestStatus.TryGetValue(table, out var st) ? st : "Unknown"
                });
            }

            return Ok(new { success = true, tables = result });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to fetch table transfer status");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    /// <summary>
    /// Seçilen tablolar arasında hedefte verisi olan veya checkpoint kaydı bulunanları döner.
    /// Bu tablolar için kullanıcıdan retry modu (Recreate/Truncate/Resume) istenir.
    /// </summary>
    [HttpPost("check-retry-needed")]
    public async Task<IActionResult> CheckRetryNeeded([FromBody] CheckRetryNeededRequest request)
    {
        var tables = request.Tables?.Where(t => !string.IsNullOrWhiteSpace(t))
            .Select(t => t.Trim().ToUpper())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList() ?? new();

        if (tables.Count == 0)
            return Ok(new { success = true, tables = Array.Empty<object>() });

        var result = new List<object>();

        // Hedef tablolarda veri var mı?
        HashSet<string> hasTargetData = new(StringComparer.OrdinalIgnoreCase);
        if (!string.IsNullOrWhiteSpace(request.MssqlConnectionString))
        {
            try
            {
                await using var conn = new SqlConnection(request.MssqlConnectionString);
                await conn.OpenAsync();
                foreach (var t in tables)
                {
                    if (!IsSafeSqlTableName(t)) continue;
                    var (exists, rows) = await GetMssqlUserTableRowEstimateAsync(conn, t);
                    if (exists && rows > 0)
                        hasTargetData.Add(t);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "check-retry-needed: MSSQL check failed");
            }
        }

        // Checkpoint'te bu tablolara ait kayıt var mı?
        HashSet<string> hasCheckpoint = new(StringComparer.OrdinalIgnoreCase);
        try
        {
            var enginePath = Path.GetFullPath(Path.Combine(_environment.ContentRootPath, "..", "MigrationEngine"));
            var appsettingsPath = Path.Combine(enginePath, "appsettings.json");
            if (System.IO.File.Exists(appsettingsPath))
            {
                var cfg = new ConfigurationBuilder().AddJsonFile(appsettingsPath).Build();
                var sqlitePath = cfg["Checkpoint:SqlitePath"];
                if (!string.IsNullOrWhiteSpace(sqlitePath) && System.IO.File.Exists(sqlitePath))
                {
                    using var repo = new CheckpointRepository(sqlitePath);
                    var incomplete = repo.FindLastIncompleteRun();
                    if (incomplete.HasValue)
                    {
                        var tablesWithCp = repo.GetTablesWithCheckpoint(incomplete.Value.runId);
                        foreach (var t in tablesWithCp) hasCheckpoint.Add(t);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "check-retry-needed: checkpoint check failed");
        }

        foreach (var t in tables)
        {
            var inTarget = hasTargetData.Contains(t);
            var inCheckpoint = hasCheckpoint.Contains(t);
            if (inTarget || inCheckpoint)
            {
                result.Add(new
                {
                    tableName = t,
                    hasTargetData = inTarget,
                    hasCheckpoint = inCheckpoint
                });
            }
        }

        return Ok(new { success = true, tables = result });
    }

    [HttpPost("start-migration")]
    public async Task<IActionResult> StartMigration([FromBody] StartMigrationRequest request)
    {
        try
        {
            var degreeOfParallelism = request.OracleParallel is > 0 and <= 128
                ? request.OracleParallel.Value
                : (request.DegreeOfParallelism is > 0 and <= 128 ? request.DegreeOfParallelism.Value : 56);
            var sqlMaxDop = request.SqlMaxDop is > 0 and <= 128
                ? request.SqlMaxDop.Value
                : (request.PartitionDegreeOfParallelism is > 0 and <= 128
                    ? request.PartitionDegreeOfParallelism.Value
                    : 48);
            var tableParallelism = request.TableParallelism is > 0 and <= 32
                ? request.TableParallelism.Value
                : 2;
            var batchSize = request.BatchSize is > 0 ? request.BatchSize.Value : 50_000;
            var fetchSizeMb = request.FetchSizeMB is > 0 ? request.FetchSizeMB.Value : 50;
            var validationMaxRows = request.ValidationMaxRowsForExtendedGates is >= 0
                ? request.ValidationMaxRowsForExtendedGates!.Value
                : 5_000_000;

            var validationMode = Enum.TryParse<ValidationMode>(request.ValidationMode, ignoreCase: true, out var vm)
                ? vm
                : ValidationMode.Balanced;

            var tables = request.Tables ?? new List<string>();
            if (tables.Count == 0)
            {
                return Ok(new { success = false, error = "Select at least one table before saving." });
            }

            var enginePath = Path.GetFullPath(Path.Combine(_environment.ContentRootPath, "..", "MigrationEngine"));

            if (!Directory.Exists(enginePath))
            {
                _logger.LogError("MigrationEngine directory not found at: {Path}", enginePath);
                return Ok(new
                {
                    success = false,
                    error = $"MigrationEngine directory not found at: {enginePath}"
                });
            }

            // Relative: engine exe directory (works on both dev and deployed hosts).
            // Absolute local paths break when appsettings is copied to another machine.
            const string checkpointDbPath = "migration_checkpoint.db";

            var config = new
            {
                Migration = new
                {
                    OracleConnectionString = request.OracleConnectionString,
                    MssqlConnectionString = request.MssqlConnectionString,
                    OracleSchema = request.OracleSchema,
                    DegreeOfParallelism = degreeOfParallelism,
                    OracleParallel = degreeOfParallelism,
                    TableParallelism = tableParallelism,
                    BatchSize = batchSize,
                    FetchSizeMB = fetchSizeMb,
                    Tables = tables,
                    ExcludeTables = new string[] { },
                    MigrateIndexes = request.MigrateIndexes,
                    MigrateTriggers = request.MigrateTriggers,
                    MigrateForeignKeys = request.MigrateForeignKeys,
                    MigratePrimaryKeys = request.MigratePrimaryKeys,
                    MigrateUniqueConstraints = request.MigrateUniqueConstraints,
                    MigrateCheckConstraints = request.MigrateCheckConstraints,
                    ValidationMode = validationMode,
                    ValidationMaxRowsForExtendedGates = validationMaxRows,
                    ValidatePerTableAfterLoad = request.ValidatePerTableAfterLoad,
                    ValidationFailFast = request.ValidationFailFast,
                    EnableCompositePkHash = request.EnableCompositePkHash,
                    AutoStart = request.AutoStart,
                    ParallelPartitionLoad = request.ParallelPartitionLoad,
                    PartitionDegreeOfParallelism = sqlMaxDop,
                    SqlMaxDop = sqlMaxDop,
                    UseStagingMerge = request.UseStagingMerge,
                    UsePartitionSwitch = request.UsePartitionSwitch,
                    UseBulkLoggedRecovery = request.UseBulkLoggedRecovery,
                    TableRetryModes = request.TableRetryModes
                        .Where(kv => Enum.TryParse<TableRetryMode>(kv.Value, true, out _))
                        .ToDictionary(kv => kv.Key, kv => Enum.Parse<TableRetryMode>(kv.Value, true))
                },
                Checkpoint = new
                {
                    SqlitePath = checkpointDbPath
                },
                Serilog = new
                {
                    MinimumLevel = new { Default = "Information" },
                    WriteTo = new object[]
                    {
                        new { Name = "Console" },
                        new { Name = "File", Args = new { path = "logs/migration-.log", rollingInterval = "Day" } }
                    }
                }
            };

            var configPath = Path.Combine(enginePath, "appsettings.json");

            await System.IO.File.WriteAllTextAsync(configPath, JsonSerializer.Serialize(config, new JsonSerializerOptions
            {
                WriteIndented = true,
                Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
            }));

            _logger.LogInformation("Configuration saved successfully to: {Path}", configPath);
            _logger.LogInformation("Selected tables: {Tables}", string.Join(", ", tables));

            return Ok(new
            {
                success = true,
                configPath = configPath,
                enginePath = enginePath
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to save configuration");
            return Ok(new
            {
                success = false,
                error = ex.Message
            });
        }
    }

    /// <summary>
    /// Checkpoint DB'de yarıda kalan (RUNNING) bir migration varsa özet bilgisini döndürür.
    /// </summary>
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

            var tablesSummary = summary.Select(t => new
            {
                tableName = t.tableName,
                done      = t.done,
                pending   = t.pending,
                failed    = t.failed,
                total     = t.total,
                isComplete = t.done == t.total && t.total > 0
            }).ToList();

            return Ok(new
            {
                hasResumable    = true,
                runId           = runId,
                startedAt       = startTime,
                tableCount      = summary.Count,
                doneCount       = summary.Count(t => t.done == t.total && t.total > 0),
                pendingCount    = summary.Count(t => t.pending > 0 || t.failed > 0),
                oracleSchema    = cfg?.OracleSchema,
                tables          = tablesSummary
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get resume info");
            return Ok(new { hasResumable = false });
        }
    }

    [HttpGet("connection-profiles")]
    public IActionResult GetConnectionProfiles([FromQuery] string? type = null)
    {
        try
        {
            var profiles = _historyService.GetConnectionProfiles(type);
            return Ok(new { success = true, profiles = profiles });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get connection profiles");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpPost("save-profile")]
    public IActionResult SaveProfile([FromBody] SaveProfileRequest request)
    {
        try
        {
            using var connection = new SqliteConnection($"Data Source={_checkpointOptions.Value.SqlitePath}");
            connection.Open();
            ConnectionProfileSchemaMigrator.EnsureColumns(connection);

            // Build config JSON when migration fields are present
            string? configJson = null;
            if (request.Tables != null && request.Tables.Count > 0)
            {
                var cfg = new
                {
                    oracleConnectionString = request.OracleConnectionString,
                    mssqlConnectionString = request.MssqlConnectionString,
                    oracleSchema = request.OracleSchema,
                    oraclePassword = request.OraclePassword,
                    mssqlPassword = request.MssqlPassword,
                    mssqlHost = request.MssqlHost,
                    mssqlUsername = request.MssqlUsername,
                    mssqlDatabase = request.MssqlDatabase,
                    mssqlAuthType = request.MssqlAuthType,
                    mssqlTrustCert = request.MssqlTrustCert,
                    tables = request.Tables,
                    degreeOfParallelism = request.OracleParallel ?? request.DegreeOfParallelism ?? 56,
                    oracleParallel = request.OracleParallel ?? request.DegreeOfParallelism ?? 56,
                    tableParallelism = request.TableParallelism ?? 2,
                    batchSize = request.BatchSize ?? 50000,
                    fetchSizeMB = request.FetchSizeMB ?? 50,
                    migrateIndexes = request.MigrateIndexes,
                    migrateTriggers = request.MigrateTriggers,
                    migrateForeignKeys = request.MigrateForeignKeys,
                    migratePrimaryKeys = request.MigratePrimaryKeys,
                    migrateUniqueConstraints = request.MigrateUniqueConstraints,
                    migrateCheckConstraints = request.MigrateCheckConstraints,
                    validationMode = request.ValidationMode ?? "Balanced",
                    validationMaxRowsForExtendedGates = request.ValidationMaxRowsForExtendedGates ?? 5_000_000,
                    validatePerTableAfterLoad = request.ValidatePerTableAfterLoad,
                    validationFailFast = request.ValidationFailFast,
                    enableCompositePkHash = request.EnableCompositePkHash,
                    parallelPartitionLoad = request.ParallelPartitionLoad,
                    partitionDegreeOfParallelism = request.SqlMaxDop ?? request.PartitionDegreeOfParallelism ?? 48,
                    sqlMaxDop = request.SqlMaxDop ?? request.PartitionDegreeOfParallelism ?? 48,
                    useStagingMerge = request.UseStagingMerge,
                    usePartitionSwitch = request.UsePartitionSwitch,
                    useBulkLoggedRecovery = request.UseBulkLoggedRecovery
                };
                configJson = JsonSerializer.Serialize(cfg, new JsonSerializerOptions { WriteIndented = false });
            }
            else if (!string.IsNullOrWhiteSpace(request.OraclePassword)
                     || !string.IsNullOrWhiteSpace(request.MssqlPassword)
                     || !string.IsNullOrWhiteSpace(request.OracleConnectionString)
                     || !string.IsNullOrWhiteSpace(request.MssqlConnectionString))
            {
                var cfg = new
                {
                    oracleConnectionString = request.OracleConnectionString ?? request.ConnectionString,
                    mssqlConnectionString = request.MssqlConnectionString,
                    oraclePassword = request.OraclePassword,
                    mssqlPassword = request.MssqlPassword,
                    mssqlHost = request.MssqlHost,
                    mssqlUsername = request.MssqlUsername,
                    mssqlDatabase = request.MssqlDatabase,
                    mssqlAuthType = request.MssqlAuthType,
                    mssqlTrustCert = request.MssqlTrustCert
                };
                configJson = JsonSerializer.Serialize(cfg, new JsonSerializerOptions { WriteIndented = false });
            }

            var databaseName = request.ConnectionType == "Migration"
                ? (request.MssqlDatabase ?? request.DatabaseName)
                : request.DatabaseName;

            var sql = @"INSERT INTO connection_profiles
                (profile_name, connection_type, host, port, service_name, database_name,
                 username, schema_name, auth_type, trust_cert, connection_string, config_json, created_at, use_count,
                 is_deleted, deleted_at)
                VALUES (@name, @type, @host, @port, @service, @database, @username, @schema,
                        @authType, @trustCert, @connectionString, @configJson, @createdAt, @useCount, 0, NULL)
                ON CONFLICT(profile_name) DO UPDATE SET
                    connection_type = excluded.connection_type,
                    host = excluded.host,
                    port = excluded.port,
                    service_name = excluded.service_name,
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
            cmd.Parameters.AddWithValue("@name", request.ProfileName);
            cmd.Parameters.AddWithValue("@type", request.ConnectionType);
            cmd.Parameters.AddWithValue("@host", request.Host ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@port", request.Port ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@service", request.ServiceName ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@database", databaseName ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@username", request.Username ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@schema", request.SchemaName ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@authType", request.AuthType ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@trustCert", request.TrustCert ? 1 : 0);
            cmd.Parameters.AddWithValue("@connectionString", request.ConnectionString ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@configJson", configJson ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@createdAt", DateTime.UtcNow.ToString("O"));
            cmd.Parameters.AddWithValue("@useCount", 0);
            cmd.ExecuteNonQuery();

            _logger.LogInformation("Saved profile: {ProfileName} (hasMigrationConfig={HasConfig})",
                request.ProfileName, configJson != null);

            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to save profile");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpGet("validation-gates/{runId:int}")]
    public IActionResult GetValidationGates(int runId)
    {
        try
        {
            var repo = new ExtendedCheckpointRepository(_checkpointOptions.Value.SqlitePath);
            var gates = repo.GetValidationGatesForRun(runId);
            return Ok(new { success = true, gates });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load validation gates for run {RunId}", runId);
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpGet("migration-history")]
    public IActionResult GetMigrationHistory([FromQuery] int limit = 50)
    {
        try
        {
            var history = _historyService.GetMigrationHistory(limit);
            return Ok(new { success = true, history = history });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get migration history");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpGet("active-threads/{runId}")]
    public IActionResult GetActiveThreads(int runId)
    {
        try
        {
            var threads = _historyService.GetActiveThreads(runId);
            return Ok(new { success = true, threads = threads });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get active threads");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpGet("performance/{runId}")]
    public IActionResult GetPerformance(int runId)
    {
        try
        {
            var summary = _historyService.GetPerformanceSummary(runId);
            return Ok(new { success = true, summary = summary });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get performance summary");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpGet("compare/{runId1}/{runId2}")]
    public IActionResult CompareRuns(int runId1, int runId2)
    {
        try
        {
            var comparison = _historyService.GetRunComparison(runId1, runId2);
            return Ok(new { success = true, comparison = comparison });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to compare runs");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    private string BuildMssqlConnectionString(MssqlConnectionRequest request)
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

        // Varsayılan: güvenilmeyen sertifika zinciri (kurumsal CA) hatasını önle
        builder.TrustServerCertificate = request.TrustCert || request.AuthType == "sql";

        return builder.ConnectionString;
    }
}

public class CheckRetryNeededRequest
{
    public string MssqlConnectionString { get; set; } = string.Empty;
    public List<string> Tables { get; set; } = new();
}

public class OracleConnectionRequest
{
    public string Host { get; set; } = string.Empty;
    public string Port { get; set; } = string.Empty;
    public string Service { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string Schema { get; set; } = string.Empty;
}

public class MssqlConnectionRequest
{
    public string Server { get; set; } = string.Empty;
    public string AuthType { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string Database { get; set; } = string.Empty;
    public bool TrustCert { get; set; }
}

public class ListTablesRequest
{
    public string ConnectionString { get; set; } = string.Empty;
    public string Schema { get; set; } = string.Empty;
}

public class CheckTargetDataRequest
{
    public string MssqlConnectionString { get; set; } = string.Empty;
    public List<string> Tables { get; set; } = new();
}

public class StartMigrationRequest
{
    public string OracleConnectionString { get; set; } = string.Empty;
    public string MssqlConnectionString { get; set; } = string.Empty;
    public string OracleSchema { get; set; } = string.Empty;
    public List<string> Tables { get; set; } = new();

    /// <summary>Nullable so JSON null (e.g. client NaN) does not fail model binding.</summary>
    public int? DegreeOfParallelism { get; set; }

    /// <summary>Oracle extract slice count per table (preferred over DegreeOfParallelism).</summary>
    public int? OracleParallel { get; set; }

    /// <summary>How many tables/packages run concurrently. Independent of OracleParallel.</summary>
    public int? TableParallelism { get; set; }

    public int? BatchSize { get; set; }
    public int? FetchSizeMB { get; set; }

    public bool MigrateIndexes { get; set; }
    public bool MigrateTriggers { get; set; }
    public bool MigrateForeignKeys { get; set; }
    public bool MigratePrimaryKeys { get; set; } = true;
    public bool MigrateUniqueConstraints { get; set; }
    public bool MigrateCheckConstraints { get; set; }

    /// <summary>Strict | Balanced | CountOnly (case-insensitive). Non-parseable values default to Balanced.</summary>
    public string? ValidationMode { get; set; }
    public long? ValidationMaxRowsForExtendedGates { get; set; }
    public bool ValidatePerTableAfterLoad { get; set; }
    public bool ValidationFailFast { get; set; }
    public bool EnableCompositePkHash { get; set; }

    /// <summary>When true, <c>dotnet run</c> in MigrationEngine starts migration without <c>--run</c>.</summary>
    public bool AutoStart { get; set; }

    public bool ParallelPartitionLoad { get; set; } = true;
    public int? PartitionDegreeOfParallelism { get; set; }

    /// <summary>MSSQL-side partition concurrency (maps to PartitionDegreeOfParallelism). Default 48.</summary>
    public int? SqlMaxDop { get; set; }

    /// <summary>
    /// When true, each partition is loaded into a dedicated staging table first.
    /// After all partitions complete they are merged (smallest-first) into the final table.
    /// Eliminates lock contention during concurrent writes.
    /// </summary>
    public bool UseStagingMerge { get; set; }

    /// <summary>Uses MSSQL Partition Switch instead of INSERT/SELECT for the merge phase (near-instant).</summary>
    public bool UsePartitionSwitch { get; set; }

    /// <summary>Sets the database to BULK_LOGGED recovery during the migration, restores original afterwards.</summary>
    public bool UseBulkLoggedRecovery { get; set; } = true;

    /// <summary>
    /// Tablo başına retry modu. Key: tablo adı, Value: "Resume" | "Truncate" | "Recreate"
    /// </summary>
    public Dictionary<string, string> TableRetryModes { get; set; } = new();
}

public class SaveProfileRequest
{
    public string ProfileName { get; set; } = string.Empty;
    public string ConnectionType { get; set; } = string.Empty;
    public string? Host { get; set; }
    public string? Port { get; set; }
    public string? ServiceName { get; set; }
    public string? DatabaseName { get; set; }
    public string? Username { get; set; }
    public string? SchemaName { get; set; }
    public string? AuthType { get; set; }
    public bool TrustCert { get; set; }
    public string? ConnectionString { get; set; }

    // Full migration config (optional — set when saving a full migration profile from wizard step 5)
    public string? OracleConnectionString { get; set; }
    public string? MssqlConnectionString { get; set; }
    public string? OracleSchema { get; set; }
    public List<string>? Tables { get; set; }
    public int? DegreeOfParallelism { get; set; }
    public int? OracleParallel { get; set; }
    public int? TableParallelism { get; set; }
    public int? BatchSize { get; set; }
    public int? FetchSizeMB { get; set; }
    public bool MigrateIndexes { get; set; }
    public bool MigrateTriggers { get; set; }
    public bool MigrateForeignKeys { get; set; }
    public bool MigratePrimaryKeys { get; set; } = true;
    public bool MigrateUniqueConstraints { get; set; }
    public bool MigrateCheckConstraints { get; set; }
    public string? ValidationMode { get; set; }
    public bool ValidatePerTableAfterLoad { get; set; }
    public bool ValidationFailFast { get; set; }
    public bool EnableCompositePkHash { get; set; }
    public bool ParallelPartitionLoad { get; set; } = true;
    public int? PartitionDegreeOfParallelism { get; set; }
    public int? SqlMaxDop { get; set; }
    public bool UseStagingMerge { get; set; }
    public bool UsePartitionSwitch { get; set; }
    public bool UseBulkLoggedRecovery { get; set; } = true;
    public string? OraclePassword { get; set; }
    public string? MssqlPassword { get; set; }
    public string? MssqlHost { get; set; }
    public string? MssqlUsername { get; set; }
    public string? MssqlDatabase { get; set; }
    public string? MssqlAuthType { get; set; }
    public bool? MssqlTrustCert { get; set; }
    public int? ValidationMaxRowsForExtendedGates { get; set; }
}

public class TableTransferStatusRequest
{
    public string OracleConnectionString { get; set; } = string.Empty;
    public string OracleSchema { get; set; } = string.Empty;
    public string MssqlConnectionString { get; set; } = string.Empty;
    public List<string> Tables { get; set; } = new();
}
