using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using MigrationShared.Models.StageOps;
using MigrationShared.StageOps;
using Oracle.ManagedDataAccess.Client;

namespace MigrationWeb.Services.StageOps;

public class StageOpsPaths
{
    public string SqlitePath { get; set; } = string.Empty;
    public string StageOpsRoot { get; set; } = string.Empty;
    public string SqlRoot { get; set; } = string.Empty;
    public string ScriptsUploadRoot { get; set; } = string.Empty;
}

public class StageOpsDataService : IDisposable
{
    private readonly StageOpsRepository _repo;
    private readonly StageOpsPaths _paths;
    private readonly object _seedLock = new();
    private bool _seeded;

    public StageOpsDataService(StageOpsPaths paths)
    {
        _paths = paths;
        _repo = new StageOpsRepository(paths.SqlitePath);
        EnsureSeeded();
    }

    public StageOpsRepository Repo => _repo;
    public StageOpsPaths Paths => _paths;

    public void EnsureSeeded()
    {
        lock (_seedLock)
        {
            if (_seeded) return;
            SeedSurface(StageOpsSurfaces.Ctas, "ctas_manifest.json");
            SeedSurface(StageOpsSurfaces.TransferSql, "transfer_sql_manifest.json");
            SeedSurface(StageOpsSurfaces.ProdSql, "prod_sql_manifest.json");
            _seeded = true;
        }
    }

    private void SeedSurface(string surface, string fileName)
    {
        var path = Path.Combine(_paths.StageOpsRoot, fileName);
        if (!File.Exists(path)) return;

        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        if (!doc.RootElement.TryGetProperty("stages", out var stages)) return;

        var order = 0;
        foreach (var el in stages.EnumerateArray())
        {
            order++;
            var id = el.GetProperty("id").GetString()!;
            if (_repo.GetStage(id) != null) continue;

            var kindStr = el.TryGetProperty("kind", out var k) ? k.GetString() ?? "SqlScript" : "SqlScript";
            Enum.TryParse<StageKind>(kindStr, true, out var kind);

            var stage = new StageDefinition
            {
                Id = id,
                Surface = surface,
                Name = el.TryGetProperty("name", out var n) ? n.GetString() ?? id : id,
                Domain = el.TryGetProperty("domain", out var d) ? d.GetString() ?? "" : "",
                Kind = kind == 0 ? StageKind.SqlScript : kind,
                Path = el.TryGetProperty("path", out var p) ? p.GetString() : null,
                ProcedureName = el.TryGetProperty("procedureName", out var pr) ? pr.GetString() : null,
                SortOrder = el.TryGetProperty("sortOrder", out var so) ? so.GetInt32() : order,
                EstimatedRows = el.TryGetProperty("estimatedRows", out var er) ? er.GetInt64() : null,
                DependsOn = ReadStringArray(el, "dependsOn"),
                Writes = ReadStringArray(el, "writes"),
                Reads = ReadStringArray(el, "reads"),
                ParallelSafe = !el.TryGetProperty("parallelSafe", out var ps) || ps.GetBoolean(),
                SlotCost = el.TryGetProperty("slotCost", out var sc) ? sc.GetInt32() : 1,
                RecreateOnRetry = !el.TryGetProperty("recreateOnRetry", out var rr) || rr.GetBoolean(),
                Status = nameof(StageStatus.Ready),
                SyntaxStatus = "Seed"
            };
            _repo.UpsertStage(stage);
        }
    }

    private static List<string> ReadStringArray(JsonElement el, string name)
    {
        if (!el.TryGetProperty(name, out var arr) || arr.ValueKind != JsonValueKind.Array)
            return new List<string>();
        return arr.EnumerateArray().Select(x => x.GetString() ?? "").Where(x => x.Length > 0).ToList();
    }

    public void Dispose() => _repo.Dispose();
}

public class StageOpsScriptAnalyzer
{
    // Bracketed / dotted identifiers: [dbo].[T], dbo.T, SCHEMA.TABLE
    private const string Ident = @"(?:\[?[A-Za-z0-9_$#]+\]?\.){0,2}\[?[A-Za-z0-9_$#]+\]?";

    private static readonly Regex ObjectRef = new(
        $@"\b(?:FROM|JOIN|INTO|UPDATE|TABLE|DELETE\s+FROM|MERGE\s+INTO)\s+({Ident})",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex ExecRef = new(
        $@"\bEXEC(?:UTE)?\s+(?:dbo\.)?({Ident})",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex CtasTarget = new(
        $@"CREATE\s+TABLE\s+({Ident})\s+(?:NOLOGGING\s+|PARALLEL\s+\d+\s+|STORAGE\s*\([^)]*\)\s+)*AS\b",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex InsertInto = new(
        $@"\bINSERT\s+(?:/\*.*?\*/\s*)*(?:INTO\s+)?({Ident})",
        RegexOptions.IgnoreCase | RegexOptions.Compiled | RegexOptions.Singleline);

    private static readonly Regex CreateProc = new(
        $@"\bCREATE\s+(?:OR\s+REPLACE\s+)?(?:PROC(?:EDURE)?|FUNCTION)\s+({Ident})",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public ScriptAnalysisResult Analyze(string surface, string fileName, string content, IEnumerable<StageDefinition> library)
    {
        var result = new ScriptAnalysisResult();
        var errors = new List<string>();

        if (string.IsNullOrWhiteSpace(content))
            errors.Add("Dosya boş");

        // Light syntax heuristics (no DB round-trip — keeps upload fast)
        var openParens = content.Count(c => c == '(');
        var closeParens = content.Count(c => c == ')');
        if (openParens != closeParens)
            errors.Add($"Parantez dengesiz: ( {openParens} ) {closeParens}");

        if (surface == StageOpsSurfaces.Ctas)
        {
            if (!content.Contains("CREATE", StringComparison.OrdinalIgnoreCase))
                errors.Add("Oracle CTAS bekleniyor: CREATE TABLE … AS bulunamadı");
            if (content.Contains("\r\nGO\r\n", StringComparison.OrdinalIgnoreCase) ||
                content.Contains("\nGO\n", StringComparison.OrdinalIgnoreCase))
                errors.Add("Uyarı: GO batch ayırıcısı Oracle sqlplus için tipik değil");
        }
        else
        {
            // T-SQL: unmatched quotes rough check
            var quoteCount = content.Count(c => c == '\'');
            if (quoteCount % 2 != 0)
                errors.Add("Tek tırnak (') sayısı tek — olası string hatası");
        }

        result.SyntaxErrors = errors;
        result.SyntaxOk = errors.Count == 0 || errors.All(e => e.StartsWith("Uyarı", StringComparison.OrdinalIgnoreCase));
        if (errors.Any(e => !e.StartsWith("Uyarı", StringComparison.OrdinalIgnoreCase)))
            result.SyntaxOk = false;

        foreach (Match m in CtasTarget.Matches(content))
            AddUnique(result.Writes, NormalizeIdent(m.Groups[1].Value));

        foreach (Match m in InsertInto.Matches(content))
            AddUnique(result.Writes, NormalizeIdent(m.Groups[1].Value));

        foreach (Match m in CreateProc.Matches(content))
            AddUnique(result.Writes, NormalizeIdent(m.Groups[1].Value));

        foreach (Match m in ObjectRef.Matches(content))
        {
            var name = NormalizeIdent(m.Groups[1].Value);
            if (name is "SELECT" or "SET" or "AS" or "ON" or "WHERE" or "INTO" or "VALUES" or "WITH") continue;
            var keyword = m.Value.TrimStart();
            if (keyword.StartsWith("INTO", StringComparison.OrdinalIgnoreCase) ||
                keyword.StartsWith("UPDATE", StringComparison.OrdinalIgnoreCase) ||
                keyword.StartsWith("TABLE", StringComparison.OrdinalIgnoreCase) ||
                keyword.StartsWith("DELETE", StringComparison.OrdinalIgnoreCase) ||
                keyword.StartsWith("MERGE", StringComparison.OrdinalIgnoreCase) ||
                keyword.StartsWith("CREATE", StringComparison.OrdinalIgnoreCase))
                AddUnique(result.Writes, name);
            else
                AddUnique(result.Reads, name);
        }

        foreach (Match m in ExecRef.Matches(content))
            AddUnique(result.Calls, NormalizeIdent(m.Groups[1].Value));

        var lib = library.ToList();
        foreach (var other in lib)
        {
            if (other.Writes.Count == 0) continue;
            if (result.Reads.Any(r => other.Writes.Any(w => NamesMatch(r, w))))
                AddUnique(result.SuggestedDependsOn, other.Id);
        }

        var writeConflicts = lib.Where(o =>
            o.Writes.Any(w => result.Writes.Any(rw => NamesMatch(w, rw)))).Select(o => o.Id).ToList();
        if (writeConflicts.Count > 0)
            result.Warnings.Add("Aynı hedefe yazan stage’ler: " + string.Join(", ", writeConflicts));

        if (result.Writes.Count == 0 && result.Calls.Count == 0 && surface != StageOpsSurfaces.Ctas)
            result.Warnings.Add("Yazılan tablo / EXEC çağrısı çıkarılamadı — ilişki analizi sınırlı");
        else if (result.Writes.Count == 0 && surface == StageOpsSurfaces.Ctas)
            result.Warnings.Add("CTAS hedef tablo adı çıkarılamadı — CREATE TABLE … AS desenini kontrol edin");

        return result;
    }

    private static string NormalizeIdent(string raw)
    {
        var cleaned = raw.Replace("[", "").Replace("]", "").Trim();
        return cleaned.ToUpperInvariant();
    }

    private static bool NamesMatch(string a, string b)
    {
        var aa = a.Contains('.') ? a.Split('.').Last() : a;
        var bb = b.Contains('.') ? b.Split('.').Last() : b;
        return string.Equals(aa, bb, StringComparison.OrdinalIgnoreCase);
    }

    private static void AddUnique(List<string> list, string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        if (!list.Contains(value, StringComparer.OrdinalIgnoreCase))
            list.Add(value);
    }
}

public class StageOpsSchemaGateService
{
    private readonly StageOpsPaths _paths;
    private readonly ILogger<StageOpsSchemaGateService> _logger;

    public StageOpsSchemaGateService(StageOpsPaths paths, ILogger<StageOpsSchemaGateService> logger)
    {
        _paths = paths;
        _logger = logger;
    }

    public async Task<SchemaGateResult> CheckAsync(StageDefinition stage, string surface, CancellationToken ct = default)
    {
        var result = new SchemaGateResult
        {
            SourceObject = stage.Reads.FirstOrDefault() ?? stage.Name,
            TargetObject = stage.Writes.FirstOrDefault() ?? stage.ProcedureName ?? stage.Name,
            Compatible = true
        };

        if (string.Equals(stage.SyntaxStatus, "Invalid", StringComparison.OrdinalIgnoreCase))
        {
            result.Compatible = false;
            result.Drift.Add(new SchemaDriftItem { Column = "*", Issue = "Script syntax Invalid" });
            result.Detail = "Syntax geçersiz";
            return result;
        }

        var cfg = StageOpsConnectionConfig.FromEnvAndFile(Path.Combine(_paths.StageOpsRoot, "stage_ops.config.json"));

        try
        {
            if (surface == StageOpsSurfaces.Ctas)
                return await CheckOracleCtasAsync(stage, cfg, result, ct);
            if (surface == StageOpsSurfaces.ProdSql)
                return await CheckProdParityAsync(stage, cfg, result, ct);

            result.Detail = "TRANSFER SQL için şema gate opsiyonel — MIG_LOG kullanılır";
            return result;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Schema gate failed for {StageId}", stage.Id);
            result.Compatible = false;
            result.Detail = "Şema kontrolü hata: " + ex.Message;
            result.Drift.Add(new SchemaDriftItem { Column = "*", Issue = ex.Message });
            return result;
        }
    }

    /// <summary>Sync wrapper for call sites that are not async yet.</summary>
    public SchemaGateResult Check(StageDefinition stage, string surface) =>
        CheckAsync(stage, surface).GetAwaiter().GetResult();

    private static async Task<SchemaGateResult> CheckOracleCtasAsync(
        StageDefinition stage, StageOpsConnectionConfig cfg, SchemaGateResult result, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(cfg.OracleOdp))
        {
            result.Detail = "Oracle ODP yok (STAGEOPS_ORACLE_ODP). Gate bilgilendirme modunda geçti.";
            return result;
        }

        await using var conn = new OracleConnection(cfg.OracleOdp);
        await conn.OpenAsync(ct);

        var missing = new List<string>();
        foreach (var read in stage.Reads.DefaultIfEmpty())
        {
            if (string.IsNullOrWhiteSpace(read)) continue;
            var (owner, table) = SplitOracleName(read);
            await using var cmd = new OracleCommand(
                "SELECT COUNT(*) FROM ALL_TABLES WHERE OWNER = :o AND TABLE_NAME = :t", conn);
            cmd.Parameters.Add("o", owner);
            cmd.Parameters.Add("t", table);
            var count = Convert.ToInt32(await cmd.ExecuteScalarAsync(ct));
            if (count == 0)
            {
                missing.Add($"{owner}.{table}");
                result.Drift.Add(new SchemaDriftItem
                {
                    Column = "*",
                    SourceType = $"{owner}.{table}",
                    Issue = "Kaynak tablo Oracle'da yok"
                });
            }
        }

        // If no Reads declared, try Name as table under SMS / MIGRATION
        if (stage.Reads.Count == 0 && !string.IsNullOrWhiteSpace(stage.Name))
        {
            result.Detail = "Reads listesi boş — kaynak varlık kontrolü atlandı (manifest'e reads ekleyin). ODP bağlantısı OK.";
            return result;
        }

        if (missing.Count > 0)
        {
            result.Compatible = false;
            result.Detail = "Eksik kaynak tablolar: " + string.Join(", ", missing);
        }
        else
        {
            result.Compatible = true;
            result.Detail = "Oracle kaynak tablolar mevcut";
        }

        return result;
    }

    private static async Task<SchemaGateResult> CheckProdParityAsync(
        StageDefinition stage, StageOpsConnectionConfig cfg, SchemaGateResult result, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(cfg.MssqlConnectionString) || string.IsNullOrWhiteSpace(cfg.ProdConnectionString))
        {
            result.Detail = "energy/PROD bağlantısı yok (STAGEOPS_MSSQL_* / STAGEOPS_PROD_*). Gate bilgilendirme modunda geçti.";
            return result;
        }

        var tableName = stage.Writes.FirstOrDefault() ?? stage.Name;
        if (string.IsNullOrWhiteSpace(tableName) || stage.Kind == StageKind.Manual)
        {
            result.Detail = "Manuel / tablo tanımsız stage — gate atlandı";
            return result;
        }

        var (schema, table) = SplitMssqlName(tableName);
        var sourceCols = await LoadMssqlColumnsAsync(cfg.MssqlConnectionString, schema, table, ct);
        var targetCols = await LoadMssqlColumnsAsync(cfg.ProdConnectionString, schema, table, ct);

        result.SourceObject = $"energy.{schema}.{table}";
        result.TargetObject = $"prod.{schema}.{table}";

        if (sourceCols.Count == 0)
        {
            result.Compatible = false;
            result.Detail = $"Kaynak tablo yok: {schema}.{table}";
            result.Drift.Add(new SchemaDriftItem { Column = "*", Issue = "Kaynak tablo bulunamadı" });
            return result;
        }

        if (targetCols.Count == 0)
        {
            result.Compatible = false;
            result.Detail = $"PROD tablo yok: {schema}.{table}";
            result.Drift.Add(new SchemaDriftItem { Column = "*", Issue = "PROD tablo bulunamadı" });
            return result;
        }

        foreach (var kv in sourceCols)
        {
            if (!targetCols.TryGetValue(kv.Key, out var tgt))
            {
                result.Drift.Add(new SchemaDriftItem
                {
                    Column = kv.Key,
                    SourceType = kv.Value,
                    Issue = "PROD'da kolon yok"
                });
                continue;
            }
            if (!string.Equals(NormalizeType(kv.Value), NormalizeType(tgt), StringComparison.OrdinalIgnoreCase))
            {
                result.Drift.Add(new SchemaDriftItem
                {
                    Column = kv.Key,
                    SourceType = kv.Value,
                    TargetType = tgt,
                    Issue = "Tip uyumsuz"
                });
            }
        }

        foreach (var kv in targetCols)
        {
            if (!sourceCols.ContainsKey(kv.Key))
            {
                result.Drift.Add(new SchemaDriftItem
                {
                    Column = kv.Key,
                    TargetType = kv.Value,
                    Issue = "Kaynakta kolon yok (PROD ekstra)"
                });
            }
        }

        result.Compatible = result.Drift.Count == 0;
        result.Detail = result.Compatible
            ? $"Şema uyumlu ({sourceCols.Count} kolon)"
            : $"{result.Drift.Count} drift";
        return result;
    }

    private static async Task<Dictionary<string, string>> LoadMssqlColumnsAsync(
        string cs, string schema, string table, CancellationToken ct)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        await using var conn = new SqlConnection(cs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(@"
            SELECT COLUMN_NAME, DATA_TYPE +
                   CASE
                     WHEN CHARACTER_MAXIMUM_LENGTH IS NOT NULL THEN '(' + CAST(CHARACTER_MAXIMUM_LENGTH AS varchar(20)) + ')'
                     WHEN NUMERIC_PRECISION IS NOT NULL THEN '(' + CAST(NUMERIC_PRECISION AS varchar(20)) + ',' + CAST(ISNULL(NUMERIC_SCALE,0) AS varchar(20)) + ')'
                     ELSE ''
                   END +
                   CASE WHEN IS_NULLABLE = 'NO' THEN ' NOT NULL' ELSE '' END AS FULL_TYPE
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = @s AND TABLE_NAME = @t
            ORDER BY ORDINAL_POSITION", conn);
        cmd.Parameters.AddWithValue("@s", schema);
        cmd.Parameters.AddWithValue("@t", table);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
            map[r.GetString(0)] = r.GetString(1);
        return map;
    }

    private static (string owner, string table) SplitOracleName(string name)
    {
        var parts = name.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length >= 2) return (parts[^2].ToUpperInvariant(), parts[^1].ToUpperInvariant());
        return ("SMS", parts[0].ToUpperInvariant());
    }

    private static (string schema, string table) SplitMssqlName(string name)
    {
        var parts = name.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length >= 2) return (parts[^2], parts[^1]);
        return ("dbo", parts[0]);
    }

    private static string NormalizeType(string t) =>
        t.Replace(" ", "", StringComparison.Ordinal).ToUpperInvariant();
}

public class StageOpsOrchestrator
{
    private readonly StageOpsDataService _data;
    private readonly StageOpsSchemaGateService _gate;
    private readonly ILogger<StageOpsOrchestrator> _logger;

    public StageOpsOrchestrator(
        StageOpsDataService data,
        StageOpsSchemaGateService gate,
        ILogger<StageOpsOrchestrator> logger)
    {
        _data = data;
        _gate = gate;
        _logger = logger;
    }

    public async Task<(int runId, string runUuid)> StartAsync(string surface, StartStageRunRequest request, CancellationToken ct = default)
    {
        var stages = request.StageIds
            .Select(id => _data.Repo.GetStage(id))
            .Where(s => s != null && s.Surface.Equals(surface, StringComparison.OrdinalIgnoreCase))
            .Cast<StageDefinition>()
            .OrderBy(s => s.SortOrder)
            .ToList();

        if (stages.Count == 0)
            throw new InvalidOperationException("Seçili stage bulunamadı");

        if (stages.Any(s => string.Equals(s.Status, nameof(StageStatus.Invalid), StringComparison.OrdinalIgnoreCase)))
            throw new InvalidOperationException("Invalid syntax’lı stage seçilemez");

        EnsureConnectionsConfigured(surface);

        if (!request.SkipSchemaGate &&
            (surface == StageOpsSurfaces.Ctas || surface == StageOpsSurfaces.ProdSql))
        {
            foreach (var stage in stages)
            {
                var gate = await _gate.CheckAsync(stage, surface, ct);
                _data.Repo.SaveSchemaCheck(surface, stage.Id, null, gate);
                if (!gate.Compatible)
                    throw new InvalidOperationException($"Şema uyumsuz: {stage.Id} — {gate.Detail}");
            }
        }

        // CTAS: aynı writes[] hedefe sahip stage'leri aynı run'da paralel başlatma — sırala
        if (surface == StageOpsSurfaces.Ctas)
        {
            var writeOwners = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var s in stages)
            {
                foreach (var w in s.Writes)
                {
                    var key = w.Contains('.') ? w.Split('.').Last() : w;
                    if (writeOwners.TryGetValue(key, out var other) && other != s.Id)
                        throw new InvalidOperationException(
                            $"Aynı hedefe yazan stage'ler aynı anda seçilemez: {other} ve {s.Id} → {w}");
                    writeOwners[key] = s.Id;
                }
            }
        }

        var runUuid = Guid.NewGuid().ToString("N");
        var maxParallel = surface == StageOpsSurfaces.Ctas
            ? Math.Max(1, request.MaxParallel)
            : 1;

        var paramsJson = JsonSerializer.Serialize(new
        {
            request.Resume,
            request.HardReset,
            request.MaxParallel,
            stageIds = stages.Select(s => s.Id).ToList()
        });

        var runId = _data.Repo.CreateRun(surface, runUuid, maxParallel, stages.Count, paramsJson);
        _data.Repo.LogEvent(runId, "Info", $"Run başladı: {stages.Count} stage, parallel={maxParallel}");

        foreach (var stage in stages)
            _data.Repo.CreateRunItem(runId, stage.Id, stage.Name);

        _ = Task.Run(() => ExecuteRun(runId, runUuid, surface, stages, maxParallel, request), CancellationToken.None);
        await Task.CompletedTask;
        return (runId, runUuid);
    }

    private void ExecuteRun(int runId, string runUuid, string surface, List<StageDefinition> stages, int maxParallel, StartStageRunRequest request)
    {
        try
        {
            _data.Repo.UpdateRun(runId, "Running", 0, 0, 0, 0);
            var oneScript = Path.Combine(_data.Paths.StageOpsRoot, "Invoke-StageOne.ps1");
            var configPath = Path.Combine(_data.Paths.StageOpsRoot, "stage_ops.config.json");
            var items = _data.Repo.GetRunItems(runId).ToDictionary(i => i.StageId, i => i.Id);

            using var gate = new SemaphoreSlim(maxParallel);
            var tasks = stages.Select(async stage =>
            {
                await gate.WaitAsync();
                try
                {
                    var itemId = items[stage.Id];
                    _data.Repo.UpdateRunItem(itemId, "Running", null, 0, null, null, null, null, started: true);
                    _data.Repo.UpdateStageStatus(stage.Id, nameof(StageStatus.Running));
                    _data.Repo.LogEvent(runId, "Info", $"START {stage.Id}", stage.Id);
                    RefreshRunCounts(runId);

                    var stageJson = JsonSerializer.Serialize(new
                    {
                        id = stage.Id,
                        name = stage.Name,
                        kind = stage.Kind.ToString(),
                        path = stage.Path,
                        procedureName = stage.ProcedureName
                    });

                    var stageJsonPath = Path.Combine(Path.GetTempPath(), $"stageops_{runUuid}_{stage.Id}.json");
                    await File.WriteAllTextAsync(stageJsonPath, stageJson);

                    var command =
                        $"$j = Get-Content -Raw -LiteralPath '{stageJsonPath.Replace("'", "''")}'; " +
                        $"& '{oneScript.Replace("'", "''")}' -Surface '{surface}' -StageJson $j " +
                        $"-ConfigPath '{configPath.Replace("'", "''")}' -RunUuid '{runUuid}'" +
                        (request.Resume ? " -Resume" : "") +
                        (request.HardReset ? " -HardReset" : "");

                    var sw = System.Diagnostics.Stopwatch.StartNew();
                    var psi = new System.Diagnostics.ProcessStartInfo
                    {
                        FileName = "powershell.exe",
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        WorkingDirectory = _data.Paths.StageOpsRoot
                    };
                    psi.ArgumentList.Add("-NoProfile");
                    psi.ArgumentList.Add("-ExecutionPolicy");
                    psi.ArgumentList.Add("Bypass");
                    psi.ArgumentList.Add("-Command");
                    psi.ArgumentList.Add(command);

                    using var proc = System.Diagnostics.Process.Start(psi)
                        ?? throw new InvalidOperationException("powershell başlatılamadı");
                    var stdout = await proc.StandardOutput.ReadToEndAsync();
                    var stderr = await proc.StandardError.ReadToEndAsync();
                    await proc.WaitForExitAsync();
                    sw.Stop();
                    try { File.Delete(stageJsonPath); } catch { /* ignore */ }

                    var logPath = Path.Combine(_data.Paths.StageOpsRoot, "logs", surface, runUuid, $"{stage.Id}.log");
                    var ok = proc.ExitCode == 0;
                    var status = ok ? "Done" : "Failed";
                    var logText = ReadLogSafe(logPath, 6000);
                    var detail = JsonSerializer.Serialize(new
                    {
                        log = logText,
                        stdout = Trim(stdout),
                        stderr = Trim(stderr)
                    });

                    _data.Repo.UpdateRunItem(itemId, status, proc.ExitCode, sw.ElapsedMilliseconds, null, null, logPath, detail, completed: true);
                    _data.Repo.UpdateStageStatus(stage.Id, ok ? nameof(StageStatus.Done) : nameof(StageStatus.Failed));
                    var errSummary = ok
                        ? $"{status} {stage.Id} exit={proc.ExitCode} {sw.ElapsedMilliseconds}ms"
                        : $"{status} {stage.Id} exit={proc.ExitCode}: {(logText ?? stderr ?? stdout).Trim().Split('\n').LastOrDefault(l => !string.IsNullOrWhiteSpace(l)) ?? "see log"}";
                    _data.Repo.LogEvent(runId, ok ? "Info" : "Error", errSummary, stage.Id);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Stage {StageId} failed", stage.Id);
                    if (items.TryGetValue(stage.Id, out var itemId))
                        _data.Repo.UpdateRunItem(itemId, "Failed", -1, 0, null, null, null, ex.Message, completed: true);
                    _data.Repo.UpdateStageStatus(stage.Id, nameof(StageStatus.Failed));
                    _data.Repo.LogEvent(runId, "Error", $"FAIL {stage.Id}: {ex.Message}", stage.Id);
                }
                finally
                {
                    gate.Release();
                    RefreshRunCounts(runId);
                }
            }).ToArray();

            Task.WaitAll(tasks);
            RefreshRunCounts(runId, complete: true);

            // Persist artifact summary
            var artDir = Path.Combine(_data.Paths.StageOpsRoot, "artifacts", surface, runUuid);
            Directory.CreateDirectory(artDir);
            var summary = new
            {
                runId,
                runUuid,
                surface,
                items = _data.Repo.GetRunItems(runId)
            };
            File.WriteAllText(Path.Combine(artDir, "result.json"), JsonSerializer.Serialize(summary, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Run {RunId} failed", runId);
            _data.Repo.LogEvent(runId, "Error", ex.Message);
            _data.Repo.UpdateRun(runId, "Failed", 0, stages.Count, 0, 0, complete: true);
        }
    }

    private void RefreshRunCounts(int runId, bool complete = false)
    {
        var items = _data.Repo.GetRunItems(runId);
        var done = items.Count(i => i.Status == "Done");
        var failed = items.Count(i => i.Status == "Failed");
        var running = items.Count(i => i.Status == "Running");
        var totalRows = items.Sum(i => i.Rows ?? 0);
        var status = complete
            ? (failed > 0 ? "Failed" : "Done")
            : (running > 0 ? "Running" : (done + failed >= items.Count ? (failed > 0 ? "Failed" : "Done") : "Running"));
        _data.Repo.UpdateRun(runId, status, done, failed, running, totalRows, complete || status is "Done" or "Failed");
    }

    private void EnsureConnectionsConfigured(string surface)
    {
        var path = StageOpsConnectionsStore.DefaultPath(_data.Paths.StageOpsRoot);
        var doc = StageOpsConnectionsStore.Load(path);
        var cfgPath = Path.Combine(_data.Paths.StageOpsRoot, "stage_ops.config.json");
        var live = StageOpsConnectionConfig.FromEnvAndFile(cfgPath);

        if (surface == StageOpsSurfaces.Ctas)
        {
            if (string.IsNullOrWhiteSpace(live.OracleSqlplus) &&
                string.IsNullOrWhiteSpace(doc.OracleCtas.SqlplusConnect))
                throw new InvalidOperationException(
                    "CTAS Oracle bağlantısı yok. Stage Ops → Bağlantılar sayfasından sqlplus connect tanımlayın.");
        }
        else if (surface == StageOpsSurfaces.TransferSql)
        {
            if (string.IsNullOrWhiteSpace(live.MssqlConnectionString) && !doc.MssqlStage2.IsConfigured)
                throw new InvalidOperationException(
                    "MSSQL Stage 2 (energy) bağlantısı yok. Stage Ops → Bağlantılar sayfasından tanımlayın.");
        }
        else if (surface == StageOpsSurfaces.ProdSql)
        {
            if (string.IsNullOrWhiteSpace(live.ProdConnectionString) && !doc.MssqlProd.IsConfigured &&
                !doc.MssqlStage2.IsConfigured)
                throw new InvalidOperationException(
                    "PROD / Stage 2 MSSQL bağlantısı yok. Stage Ops → Bağlantılar sayfasından tanımlayın.");
        }
    }

    private static string Trim(string s) =>
        s.Length <= 4000 ? s : s[..4000] + "…";

    private static string? ReadLogSafe(string path, int maxChars)
    {
        try
        {
            if (!File.Exists(path)) return null;
            var text = File.ReadAllText(path);
            if (string.IsNullOrWhiteSpace(text)) return null;
            return text.Length <= maxChars ? text : "…\n" + text[^maxChars..];
        }
        catch
        {
            return null;
        }
    }
}
