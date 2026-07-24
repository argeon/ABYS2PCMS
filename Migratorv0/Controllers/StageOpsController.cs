using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using MigrationShared.Models.StageOps;
using MigrationWeb.Services.StageOps;
using Oracle.ManagedDataAccess.Client;

namespace MigrationWeb.Controllers;

[ApiController]
[Route("api/stage-ops")]
public class StageOpsController : ControllerBase
{
    private static readonly JsonSerializerOptions CamelJson = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    private readonly StageOpsDataService _data;
    private readonly StageOpsScriptAnalyzer _analyzer;
    private readonly StageOpsSchemaGateService _gate;
    private readonly StageOpsOrchestrator _orchestrator;
    private readonly StageOpsMigLogService _migLog;
    private readonly ILogger<StageOpsController> _logger;

    public StageOpsController(
        StageOpsDataService data,
        StageOpsScriptAnalyzer analyzer,
        StageOpsSchemaGateService gate,
        StageOpsOrchestrator orchestrator,
        StageOpsMigLogService migLog,
        ILogger<StageOpsController> logger)
    {
        _data = data;
        _analyzer = analyzer;
        _gate = gate;
        _orchestrator = orchestrator;
        _migLog = migLog;
        _logger = logger;
    }

    [HttpGet("{surface}/stages")]
    public IActionResult ListStages(string surface)
    {
        if (!StageOpsSurfaces.IsValid(surface)) return BadRequest("Invalid surface");
        return Ok(_data.Repo.ListStages(surface));
    }

    [HttpPost("{surface}/stages/{stageId}/status")]
    public IActionResult MarkStatus(string surface, string stageId, [FromBody] MarkStatusRequest body)
    {
        var stage = _data.Repo.GetStage(stageId);
        if (stage == null || !stage.Surface.Equals(surface, StringComparison.OrdinalIgnoreCase))
            return NotFound();
        _data.Repo.UpdateStageStatus(stageId, body.Status);
        return Ok(new { stageId, body.Status });
    }

    [HttpPost("{surface}/runs")]
    public async Task<IActionResult> StartRun(string surface, [FromBody] StartStageRunRequest request)
    {
        if (!StageOpsSurfaces.IsValid(surface)) return BadRequest("Invalid surface");
        try
        {
            var (runId, runUuid) = await _orchestrator.StartAsync(surface, request);
            return Ok(new { runId, runUuid, message = "Run başlatıldı" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("{surface}/runs")]
    public IActionResult ListRuns(string surface, [FromQuery] int limit = 40)
    {
        if (!StageOpsSurfaces.IsValid(surface)) return BadRequest("Invalid surface");
        return Ok(_data.Repo.ListRuns(surface, limit));
    }

    [HttpGet("runs/{runId:int}")]
    public IActionResult GetRun(int runId)
    {
        var run = _data.Repo.GetRun(runId);
        if (run == null) return NotFound();
        var items = _data.Repo.GetRunItems(runId).Select(i =>
        {
            var logText = ReadLogTail(i.LogPath, 8000);
            return new
            {
                i.Id,
                i.RunId,
                i.StageId,
                i.StageName,
                i.Status,
                i.ExitCode,
                i.ElapsedMs,
                i.Rows,
                i.RowsPerSec,
                i.LogPath,
                i.DetailJson,
                i.StartedAt,
                i.CompletedAt,
                logText
            };
        }).ToList();

        return Ok(new
        {
            run,
            items,
            events = _data.Repo.GetEvents(runId)
        });
    }

    private static string? ReadLogTail(string? path, int maxChars)
    {
        if (string.IsNullOrWhiteSpace(path) || !System.IO.File.Exists(path))
            return null;
        try
        {
            var text = System.IO.File.ReadAllText(path);
            if (text.Length <= maxChars) return text;
            return "…\n" + text[^maxChars..];
        }
        catch
        {
            return null;
        }
    }

    [HttpPost("{surface}/upload")]
    [RequestSizeLimit(50_000_000)]
    public async Task<IActionResult> Upload(string surface, List<IFormFile> files)
    {
        if (!StageOpsSurfaces.IsValid(surface)) return BadRequest("Invalid surface");
        if (files == null || files.Count == 0) return BadRequest("Dosya yok");

        Directory.CreateDirectory(Path.Combine(_data.Paths.ScriptsUploadRoot, surface));
        var library = _data.Repo.ListStages(surface);
        var results = new List<UploadScriptResult>();

        foreach (var file in files)
        {
            if (!file.FileName.EndsWith(".sql", StringComparison.OrdinalIgnoreCase))
            {
                results.Add(new UploadScriptResult
                {
                    StageId = "",
                    FileName = Path.GetFileName(file.FileName),
                    Analysis = new ScriptAnalysisResult
                    {
                        SyntaxOk = false,
                        SyntaxErrors = { "Sadece .sql dosyaları kabul edilir" }
                    },
                    Accepted = false
                });
                continue;
            }

            await using var stream = file.OpenReadStream();
            using var reader = new StreamReader(stream);
            var content = await reader.ReadToEndAsync();

            var safeName = Path.GetFileName(file.FileName);
            var dest = Path.Combine(_data.Paths.ScriptsUploadRoot, surface, safeName);
            await System.IO.File.WriteAllTextAsync(dest, content);

            var analysis = _analyzer.Analyze(surface, safeName, content, library);
            var stageId = $"{surface.ToUpperInvariant().Replace('-', '_')}_{Path.GetFileNameWithoutExtension(safeName)}"
                .Replace(' ', '_');

            var relPath = Path.GetRelativePath(_data.Paths.SqlRoot, dest).Replace('\\', '/');
            var stage = new StageDefinition
            {
                Id = stageId,
                Surface = surface,
                Name = Path.GetFileNameWithoutExtension(safeName),
                Domain = "UPLOAD",
                Kind = surface == StageOpsSurfaces.Ctas ? StageKind.OracleCtas :
                    surface == StageOpsSurfaces.TransferSql ? StageKind.SqlScript : StageKind.SqlScript,
                Path = relPath,
                SortOrder = 9000 + library.Count + results.Count,
                Writes = analysis.Writes,
                Reads = analysis.Reads,
                DependsOn = analysis.SuggestedDependsOn,
                Status = analysis.SyntaxOk ? nameof(StageStatus.Ready) : nameof(StageStatus.Invalid),
                SyntaxStatus = analysis.SyntaxOk ? "Ok" : "Invalid",
                AnalysisJson = JsonSerializer.Serialize(analysis, CamelJson),
                ParallelSafe = surface == StageOpsSurfaces.Ctas
            };

            _data.Repo.UpsertStage(stage);
            _data.Repo.SaveAnalysis(stageId, surface, safeName, analysis);
            library.Add(stage);

            results.Add(new UploadScriptResult
            {
                StageId = stageId,
                FileName = safeName,
                Analysis = analysis,
                Accepted = analysis.SyntaxOk
            });
        }

        if (results.Count == 0)
            return BadRequest(new { error = "İşlenecek .sql dosyası yok" });

        return Ok(results);
    }

    [HttpPost("{surface}/stages/{stageId}/schema-check")]
    public async Task<IActionResult> SchemaCheck(string surface, string stageId, CancellationToken ct)
    {
        var stage = _data.Repo.GetStage(stageId);
        if (stage == null) return NotFound();
        var result = await _gate.CheckAsync(stage, surface, ct);
        _data.Repo.SaveSchemaCheck(surface, stageId, null, result);
        return Ok(result);
    }

    [HttpGet("transfer-sql/mig-log")]
    public async Task<IActionResult> MigLog([FromQuery] string? migrationCode, CancellationToken ct) =>
        Ok(await _migLog.GetSummaryAsync(migrationCode, ct));

    [HttpGet("runs/{runId:int}/items/{itemId:long}/log")]
    public IActionResult DownloadLog(int runId, long itemId)
    {
        var item = _data.Repo.GetRunItems(runId).FirstOrDefault(i => i.Id == itemId);
        if (item?.LogPath == null || !System.IO.File.Exists(item.LogPath))
            return NotFound(new { error = "Log dosyası yok" });
        var bytes = System.IO.File.ReadAllBytes(item.LogPath);
        return File(bytes, "text/plain", Path.GetFileName(item.LogPath));
    }

    [HttpGet("results")]
    public IActionResult AllResults([FromQuery] string? surface, [FromQuery] int limit = 100)
    {
        var runs = _data.Repo.ListRuns(
            string.IsNullOrWhiteSpace(surface) ? null : surface, limit);
        return Ok(runs);
    }

    [HttpGet("connections")]
    public IActionResult GetConnections()
    {
        var path = StageOpsConnectionsStore.DefaultPath(_data.Paths.StageOpsRoot);
        var doc = StageOpsConnectionsStore.Load(path);
        return Ok(new
        {
            connections = ToEditModel(doc),
            status = StageOpsConnectionsStore.StatusSummary(doc),
            path
        });
    }

    [HttpPut("connections")]
    public IActionResult SaveConnections([FromBody] StageOpsConnectionsDocument body)
    {
        if (body == null) return BadRequest(new { error = "Body gerekli" });
        var path = StageOpsConnectionsStore.DefaultPath(_data.Paths.StageOpsRoot);
        var existing = StageOpsConnectionsStore.Load(path);

        MergeOracle(existing.OracleCtas, body.OracleCtas);
        MergeMssql(existing.MssqlStage1, body.MssqlStage1);
        MergeMssql(existing.MssqlStage2, body.MssqlStage2);
        MergeMssql(existing.MssqlProd, body.MssqlProd);

        StageOpsConnectionsStore.Save(path, body);
        return Ok(new
        {
            message = "Bağlantılar kaydedildi",
            status = StageOpsConnectionsStore.StatusSummary(body),
            connections = ToEditModel(body)
        });
    }

    [HttpGet("connections/status")]
    public IActionResult ConnectionsStatus()
    {
        var path = StageOpsConnectionsStore.DefaultPath(_data.Paths.StageOpsRoot);
        var doc = StageOpsConnectionsStore.Load(path);
        return Ok(StageOpsConnectionsStore.StatusSummary(doc));
    }

    /// <summary>
    /// Formdaki (veya kayıtlı) bağlantıyı canlı test eder.
    /// slot: oracleCtas | mssqlStage1 | mssqlStage2 | mssqlProd
    /// </summary>
    [HttpPost("connections/test")]
    public async Task<IActionResult> TestConnection([FromBody] StageOpsConnectionTestRequest request, CancellationToken ct)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.Slot))
            return BadRequest(new { success = false, error = "slot gerekli" });

        var path = StageOpsConnectionsStore.DefaultPath(_data.Paths.StageOpsRoot);
        var saved = StageOpsConnectionsStore.Load(path);
        var slot = request.Slot.Trim().ToLowerInvariant();

        try
        {
            if (slot is "oraclectas" or "oracle")
            {
                var ora = request.Oracle ?? new StageOpsOracleConnection();
                MergeOracle(saved.OracleCtas, ora);
                return Ok(await TestOracleAsync(ora, ct));
            }

            var mssql = request.Mssql ?? new StageOpsMssqlConnection();
            var existing = slot switch
            {
                "mssqlstage1" or "stage1" => saved.MssqlStage1,
                "mssqlstage2" or "stage2" => saved.MssqlStage2,
                "mssqlprod" or "prod" => saved.MssqlProd,
                _ => null
            };
            if (existing == null)
                return BadRequest(new { success = false, error = $"Bilinmeyen slot: {request.Slot}" });

            MergeMssql(existing, mssql);
            if (string.IsNullOrWhiteSpace(mssql.Server))
                mssql.Server = existing.Server;
            if (string.IsNullOrWhiteSpace(mssql.Database))
                mssql.Database = existing.Database;
            if (string.IsNullOrWhiteSpace(mssql.User))
                mssql.User = existing.User;
            if (string.IsNullOrWhiteSpace(mssql.AuthType))
                mssql.AuthType = existing.AuthType;

            return Ok(await TestMssqlAsync(mssql, ct));
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Stage Ops connection test failed for {Slot}", request.Slot);
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpGet("meta")]
    public IActionResult Meta() => Ok(new
    {
        surfaces = StageOpsSurfaces.All,
        stageOpsRoot = _data.Paths.StageOpsRoot
    });

    private static async Task<object> TestOracleAsync(StageOpsOracleConnection ora, CancellationToken ct)
    {
        var odp = ora.OdpConnectionString?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(odp) || odp == "***")
            odp = BuildOdpFromSqlplus(ora.SqlplusConnect);

        if (string.IsNullOrWhiteSpace(odp))
            return new { success = false, error = "Oracle bağlantısı eksik (sqlplus veya ODP)" };

        await using var conn = new OracleConnection(odp);
        await conn.OpenAsync(ct);
        await using var cmd = new OracleCommand("SELECT USER, SYS_CONTEXT('USERENV','DB_NAME') FROM DUAL", conn);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        string? user = null, db = null;
        if (await reader.ReadAsync(ct))
        {
            user = reader.IsDBNull(0) ? null : reader.GetString(0);
            db = reader.IsDBNull(1) ? null : reader.GetString(1);
        }
        return new { success = true, message = $"Oracle OK — {user}@{db}", user, database = db };
    }

    private static async Task<object> TestMssqlAsync(StageOpsMssqlConnection mssql, CancellationToken ct)
    {
        if (!mssql.IsConfigured)
            return new { success = false, error = "Server / Database (ve SQL Auth ise User) gerekli" };
        if (string.Equals(mssql.AuthType, "Sql", StringComparison.OrdinalIgnoreCase) &&
            string.IsNullOrEmpty(mssql.Password))
            return new { success = false, error = "Şifre boş — formu doldurun veya önce kaydedin" };

        var cs = mssql.ToSqlConnectionString();
        await using var conn = new SqlConnection(cs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand("SELECT DB_NAME(), SUSER_SNAME()", conn);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        string? db = null, login = null;
        if (await reader.ReadAsync(ct))
        {
            db = reader.IsDBNull(0) ? null : reader.GetString(0);
            login = reader.IsDBNull(1) ? null : reader.GetString(1);
        }
        return new { success = true, message = $"MSSQL OK — {login} @ {db}", database = db, login };
    }

    private static string? BuildOdpFromSqlplus(string? sqlplus)
    {
        if (string.IsNullOrWhiteSpace(sqlplus)) return null;
        // user/password@host:port/service  or  user/password@//host:port/service
        var m = Regex.Match(sqlplus.Trim(),
            @"^(?<user>[^/@]+)/(?<pass>[^@]+)@(?://)?(?<host>[^:/]+)(?::(?<port>\d+))?/(?<svc>.+)$");
        if (!m.Success) return null;
        var port = m.Groups["port"].Success ? m.Groups["port"].Value : "1521";
        return $"User Id={m.Groups["user"].Value};Password={m.Groups["pass"].Value};Data Source={m.Groups["host"].Value}:{port}/{m.Groups["svc"].Value};";
    }

    private static void MergeOracle(StageOpsOracleConnection existing, StageOpsOracleConnection incoming)
    {
        if (IsSecretPlaceholder(incoming.SqlplusConnect) && !string.IsNullOrWhiteSpace(existing.SqlplusConnect))
            incoming.SqlplusConnect = existing.SqlplusConnect;
        if (IsSecretPlaceholder(incoming.OdpConnectionString) || string.IsNullOrWhiteSpace(incoming.OdpConnectionString))
        {
            if (!string.IsNullOrWhiteSpace(existing.OdpConnectionString))
                incoming.OdpConnectionString = existing.OdpConnectionString;
        }
    }

    private static void MergeMssql(StageOpsMssqlConnection existing, StageOpsMssqlConnection incoming)
    {
        if (incoming == null) return;
        if (IsSecretPlaceholder(incoming.Password) || string.IsNullOrEmpty(incoming.Password))
        {
            if (!string.IsNullOrEmpty(existing.Password))
                incoming.Password = existing.Password;
        }
    }

    private static bool IsSecretPlaceholder(string? value) =>
        string.IsNullOrWhiteSpace(value) || value == "***" || value.Contains("/***@", StringComparison.Ordinal);

    private static object ToEditModel(StageOpsConnectionsDocument doc) => new
    {
        oracleCtas = new
        {
            sqlplusConnect = doc.OracleCtas.SqlplusConnect,
            odpConnectionString = string.IsNullOrWhiteSpace(doc.OracleCtas.OdpConnectionString) ? "" : "***",
            odpConfigured = !string.IsNullOrWhiteSpace(doc.OracleCtas.OdpConnectionString),
            profileId = doc.OracleCtas.ProfileId,
            profileName = doc.OracleCtas.ProfileName
        },
        mssqlStage1 = ToMssqlEdit(doc.MssqlStage1),
        mssqlStage2 = ToMssqlEdit(doc.MssqlStage2),
        mssqlProd = ToMssqlEdit(doc.MssqlProd)
    };

    private static object ToMssqlEdit(StageOpsMssqlConnection c) => new
    {
        server = c.Server,
        database = c.Database,
        user = c.User,
        password = "",
        passwordConfigured = !string.IsNullOrEmpty(c.Password),
        authType = c.AuthType,
        trustCert = c.TrustCert,
        profileId = c.ProfileId,
        profileName = c.ProfileName
    };
}

public class MarkStatusRequest
{
    public string Status { get; set; } = "Done";
}

public class StageOpsConnectionTestRequest
{
    public string Slot { get; set; } = string.Empty;
    public StageOpsOracleConnection? Oracle { get; set; }
    public StageOpsMssqlConnection? Mssql { get; set; }
}
