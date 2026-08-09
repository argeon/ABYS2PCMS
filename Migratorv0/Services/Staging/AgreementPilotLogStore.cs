using System.Text;
using System.Text.Json;
using MigrationWeb.Models.Staging;

namespace MigrationWeb.Services.Staging;

/// <summary>
/// Doğrulama loglarını diskte saklar — paylaşım için RunId klasörü.
/// Şifre / connection string yazılmaz.
/// </summary>
public sealed class AgreementPilotLogStore
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly object _gate = new();
    private readonly ILogger<AgreementPilotLogStore> _logger;

    public string Root { get; }

    public AgreementPilotLogStore(IWebHostEnvironment env, ILogger<AgreementPilotLogStore> logger)
    {
        _logger = logger;
        Root = Path.Combine(env.ContentRootPath, "App_Data", "tahsilat-pilot");
        Directory.CreateDirectory(Root);
    }

    public string RunDir(string runId) => Path.Combine(Root, Sanitize(runId));

    public void EnsureRun(string runId, long agrId)
    {
        var dir = RunDir(runId);
        Directory.CreateDirectory(dir);
        Directory.CreateDirectory(Path.Combine(dir, "steps"));

        var metaPath = Path.Combine(dir, "meta.json");
        lock (_gate)
        {
            if (!File.Exists(metaPath))
            {
                WriteJson(metaPath, new
                {
                    runId,
                    agrId,
                    startedAtUtc = DateTime.UtcNow,
                    note = "Bağlantı dizeleri / şifreler bu pakette yoktur."
                });
                WriteShareMd(dir, runId, agrId);
            }
            else
            {
                // agr güncelle
                try
                {
                    var raw = File.ReadAllText(metaPath);
                    using var doc = JsonDocument.Parse(raw);
                    var started = doc.RootElement.TryGetProperty("startedAtUtc", out var s)
                        ? s.GetDateTime()
                        : DateTime.UtcNow;
                    WriteJson(metaPath, new
                    {
                        runId,
                        agrId,
                        startedAtUtc = started,
                        updatedAtUtc = DateTime.UtcNow,
                        note = "Bağlantı dizeleri / şifreler bu pakette yoktur."
                    });
                }
                catch
                {
                    /* keep existing */
                }
            }
        }
    }

    public void AppendEvent(TahsilatLogEvent ev)
    {
        EnsureRun(ev.RunId, ev.AgrId);
        var line = JsonSerializer.Serialize(new
        {
            ev.RunId,
            ev.AgrId,
            ev.Step,
            ev.Side,
            ev.Op,
            ev.ElapsedMs,
            ev.RowCount,
            ev.Outcome,
            ev.Detail,
            atUtc = ev.AtUtc
        }, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
        lock (_gate)
        {
            File.AppendAllText(Path.Combine(RunDir(ev.RunId), "events.jsonl"), line + Environment.NewLine, Encoding.UTF8);
        }
    }

    public void AppendGaps(string runId, long agrId, IEnumerable<TahsilatGapItem> gaps)
    {
        EnsureRun(runId, agrId);
        lock (_gate)
        {
            var path = Path.Combine(RunDir(runId), "gaps.jsonl");
            foreach (var g in gaps)
            {
                if (string.Equals(g.Code, "APPLY_LOCKED", StringComparison.OrdinalIgnoreCase))
                    continue;
                var line = JsonSerializer.Serialize(new
                {
                    runId,
                    agrId,
                    g.Code,
                    g.Severity,
                    g.Message,
                    g.Side,
                    atUtc = DateTime.UtcNow
                }, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
                File.AppendAllText(path, line + Environment.NewLine, Encoding.UTF8);
            }
        }
    }

    public string PersistStep(TahsilatStepResult result, long agrId)
    {
        EnsureRun(result.RunId, agrId);
        var stamp = DateTime.UtcNow.ToString("yyyyMMdd_HHmmss");
        var safeStep = Sanitize(result.StepId);
        var path = Path.Combine(RunDir(result.RunId), "steps", $"{safeStep}_{stamp}.json");
        WriteJson(path, new
        {
            result.StepId,
            result.Ok,
            result.Message,
            result.RunId,
            agrId,
            atUtc = DateTime.UtcNow,
            summary = result.Summary,
            gaps = result.Gaps,
            logs = result.Logs,
            rowCount = result.Rows.Count,
            energyRowCount = result.EnergyRows.Count,
            // Önizleme satırları (paylaşım için sınırlı)
            rowsPreview = result.Rows.Take(50).ToList(),
            energyRowsPreview = result.EnergyRows.Take(50).ToList()
        });

        // Son adım snapshot
        WriteJson(Path.Combine(RunDir(result.RunId), "latest-step.json"), new
        {
            result.StepId,
            result.Ok,
            result.Message,
            result.RunId,
            agrId,
            atUtc = DateTime.UtcNow,
            summary = result.Summary,
            gapCount = result.Gaps.Count,
            criticalCount = result.Gaps.Count(g => g.Severity == "CRITICAL")
        });

        if (result.StepId is "pilotDumpMgr" or "pilotEnergyChain" or "pilotFullChain")
        {
            WriteJson(Path.Combine(RunDir(result.RunId), "validation.json"), new
            {
                result.StepId,
                result.Ok,
                result.Message,
                result.RunId,
                agrId,
                atUtc = DateTime.UtcNow,
                summary = result.Summary,
                gaps = result.Gaps
            });
        }

        _logger.LogInformation("Pilot log kaydedildi: {Path}", path);
        return RunDir(result.RunId);
    }

    public IReadOnlyList<object> ListRuns(int take = 50)
    {
        if (!Directory.Exists(Root)) return [];
        return Directory.GetDirectories(Root)
            .OrderByDescending(Directory.GetLastWriteTimeUtc)
            .Take(take)
            .Select(d =>
            {
                var id = Path.GetFileName(d);
                var meta = Path.Combine(d, "meta.json");
                long? agr = null;
                DateTime? started = null;
                if (File.Exists(meta))
                {
                    try
                    {
                        using var doc = JsonDocument.Parse(File.ReadAllText(meta));
                        if (doc.RootElement.TryGetProperty("agrId", out var a))
                            agr = a.GetInt64();
                        if (doc.RootElement.TryGetProperty("startedAtUtc", out var s))
                            started = s.GetDateTime();
                    }
                    catch { /* ignore */ }
                }
                return (object)new
                {
                    runId = id,
                    agrId = agr,
                    startedAtUtc = started,
                    path = d,
                    updatedAtUtc = Directory.GetLastWriteTimeUtc(d)
                };
            })
            .ToList();
    }

    public object? GetRunPack(string runId)
    {
        var dir = RunDir(runId);
        if (!Directory.Exists(dir)) return null;

        string? meta = File.Exists(Path.Combine(dir, "meta.json"))
            ? File.ReadAllText(Path.Combine(dir, "meta.json"))
            : null;
        string? validation = File.Exists(Path.Combine(dir, "validation.json"))
            ? File.ReadAllText(Path.Combine(dir, "validation.json"))
            : null;
        string? latest = File.Exists(Path.Combine(dir, "latest-step.json"))
            ? File.ReadAllText(Path.Combine(dir, "latest-step.json"))
            : null;
        string? share = File.Exists(Path.Combine(dir, "SHARE.md"))
            ? File.ReadAllText(Path.Combine(dir, "SHARE.md"))
            : null;

        var steps = Directory.Exists(Path.Combine(dir, "steps"))
            ? Directory.GetFiles(Path.Combine(dir, "steps"), "*.json")
                .OrderBy(f => f)
                .Select(Path.GetFileName)
                .ToList()
            : [];

        return new
        {
            runId,
            path = dir,
            meta,
            validation,
            latestStep = latest,
            shareMd = share,
            stepFiles = steps,
            eventsLines = CountLines(Path.Combine(dir, "events.jsonl")),
            gapsLines = CountLines(Path.Combine(dir, "gaps.jsonl"))
        };
    }

    private void WriteShareMd(string dir, string runId, long agrId)
    {
        var md = $"""
            # Pilot doğrulama paketi

            - **RunId:** `{runId}`
            - **AGR:** `{agrId}`
            - **Klasör:** `{dir}`

            ## Paylaşılacaklar

            1. Bu klasörün tamamı (zip)
            2. Özellikle: `validation.json`, `gaps.jsonl`, `events.jsonl`, `steps/*.json`
            3. `SHARE.md` (bu dosya)

            ## İçermeyenler

            - Oracle / MSSQL connection string
            - Şifreler

            ## Beklenen pilot sıra

            1. `pilotDumpMgr` — Oracle `MIGRATION.LS_*` (+ SMS taksit) → `izgazMGR`
            2. `pilotEnergyChain` — `izgazMGR` → `LS_005_01_*`
            """;
        File.WriteAllText(Path.Combine(dir, "SHARE.md"), md, Encoding.UTF8);
    }

    private static void WriteJson(string path, object value)
    {
        var json = JsonSerializer.Serialize(value, JsonOpts);
        File.WriteAllText(path, json, Encoding.UTF8);
    }

    private static string Sanitize(string s)
    {
        foreach (var c in Path.GetInvalidFileNameChars())
            s = s.Replace(c, '_');
        return string.IsNullOrWhiteSpace(s) ? "unknown" : s.Trim();
    }

    private static int CountLines(string path)
    {
        if (!File.Exists(path)) return 0;
        var n = 0;
        using var sr = new StreamReader(path, Encoding.UTF8);
        while (sr.ReadLine() != null) n++;
        return n;
    }
}
