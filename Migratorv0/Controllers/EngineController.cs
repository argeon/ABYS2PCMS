using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc;
using MigrationWeb.Services;
using System.Diagnostics;

namespace MigrationWeb.Controllers;

[Route("api/[controller]")]
[ApiController]
public class EngineController : ControllerBase
{
    private readonly ILogger<EngineController> _logger;
    private readonly IWebHostEnvironment _environment;
    private static Process? _runningEngineProcess;
    private static readonly object _processLock = new();
    private static int? _lastExitCode;
    private static string? _lastExitMessage;

    public EngineController(ILogger<EngineController> logger, IWebHostEnvironment environment)
    {
        _logger = logger;
        _environment = environment;
    }

    private string EnginePath => EngineLauncher.GetEngineDirectory(_environment.ContentRootPath);

    /// <summary>
    /// Migration Engine'i başlat
    /// </summary>
    [HttpPost("start")]
    public IActionResult StartEngine()
    {
        return LaunchEngine("--run", "started");
    }

    /// <summary>
    /// Yarıda kalan migration'ı --resume flag ile devam ettirir
    /// </summary>
    [HttpPost("resume")]
    public IActionResult ResumeEngine()
    {
        return LaunchEngine("--resume", "resumed");
    }

    /// <summary>
    /// Sadece Failed partition içeren tabloları yeniden dener (--retry-failed).
    /// Body opsiyonel: { "tables": ["LS_X"] } — verilirse yalnızca o tablolar.
    /// </summary>
    [HttpPost("retry-failed")]
    public IActionResult RetryFailedEngine([FromBody] RetryFailedRequest? request)
    {
        var args = "--retry-failed";
        var tables = NormalizeTables(request?.Tables);
        if (tables.Count > 0)
            args += " --tables=" + string.Join(",", tables);
        return LaunchEngine(args, "retry-failed");
    }

    /// <summary>
    /// Bekleyen / yarım / hatalı tabloları tekil (veya liste) olarak devam ettirir.
    /// Body zorunlu: { "tables": ["CS_AGREEMENT"] }
    /// </summary>
    [HttpPost("continue-tables")]
    public IActionResult ContinueTablesEngine([FromBody] RetryFailedRequest? request)
    {
        var tables = NormalizeTables(request?.Tables);
        if (tables.Count == 0)
        {
            return Ok(new
            {
                success = false,
                error = "tables gerekli — örn. { \"tables\": [\"CS_AGREEMENT\"] }"
            });
        }

        var args = "--continue-tables --tables=" + string.Join(",", tables);
        return LaunchEngine(args, "continue-tables");
    }

    public sealed class RetryFailedRequest
    {
        public List<string>? Tables { get; set; }
    }

    private static List<string> NormalizeTables(IEnumerable<string>? tables) =>
        (tables ?? Enumerable.Empty<string>())
            .Where(t => !string.IsNullOrWhiteSpace(t))
            .Select(t => t.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

    private IActionResult LaunchEngine(string argument, string actionPastTense)
    {
        lock (_processLock)
        {
            try
            {
                // IIS recycle loses static handle — also detect orphan exe
                if (IsEngineProcessAlive(out var existingPid))
                {
                    return Ok(new
                    {
                        success = false,
                        message = "Migration Engine already running",
                        pid = existingPid
                    });
                }

                var enginePath = EnginePath;
                if (!Directory.Exists(enginePath))
                {
                    _logger.LogError("MigrationEngine directory not found at: {Path}", enginePath);
                    return Ok(new
                    {
                        success = false,
                        error = $"MigrationEngine directory not found at: {enginePath}"
                    });
                }

                var startInfo = EngineLauncher.CreateStartInfo(enginePath, argument);
                _logger.LogInformation(
                    "Launching Migration Engine: {Exe} {Args}",
                    startInfo.FileName,
                    startInfo.Arguments);
                _runningEngineProcess = Process.Start(startInfo);

                if (_runningEngineProcess == null)
                {
                    return Ok(new
                    {
                        success = false,
                        error = "Failed to start Migration Engine process"
                    });
                }

                _lastExitCode = null;
                _lastExitMessage = null;
                try
                {
                    _runningEngineProcess.EnableRaisingEvents = true;
                    _runningEngineProcess.Exited += (_, _) =>
                    {
                        try
                        {
                            _lastExitCode = _runningEngineProcess?.ExitCode;
                            if (_lastExitCode is int code and not 0)
                                _lastExitMessage = $"MigrationEngine exit code {code}";
                        }
                        catch { /* ignore */ }
                    };
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Could not attach Exited handler");
                }

                _logger.LogInformation(
                    "Migration Engine {Action} with PID: {Pid} ({FileName} {Arguments})",
                    actionPastTense,
                    _runningEngineProcess.Id,
                    startInfo.FileName,
                    startInfo.Arguments);

                return Ok(new
                {
                    success = true,
                    message = $"Migration Engine {actionPastTense} successfully",
                    pid = _runningEngineProcess.Id,
                    path = enginePath
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to {Action} Migration Engine", actionPastTense);
                return Ok(new
                {
                    success = false,
                    error = ex.Message
                });
            }
        }
    }

    private static bool IsEngineProcessAlive(out int? pid)
    {
        pid = null;
        if (_runningEngineProcess != null && !_runningEngineProcess.HasExited)
        {
            pid = _runningEngineProcess.Id;
            return true;
        }

        try
        {
            var procs = Process.GetProcessesByName("MigrationEngine");
            if (procs.Length > 0)
            {
                pid = procs[0].Id;
                foreach (var p in procs.Skip(1)) p.Dispose();
                // Keep first for tracking if static was lost
                if (_runningEngineProcess == null || _runningEngineProcess.HasExited)
                    _runningEngineProcess = procs[0];
                else
                    procs[0].Dispose();
                return true;
            }
        }
        catch
        {
            // ignore
        }

        return false;
    }

    /// <summary>
    /// Migration Engine'i durdur
    /// </summary>
    [HttpPost("stop")]
    public IActionResult StopEngine()
    {
        lock (_processLock)
        {
            try
            {
                if (!IsEngineProcessAlive(out var livePid) || _runningEngineProcess == null)
                {
                    return Ok(new
                    {
                        success = false,
                        message = "Migration Engine is not running"
                    });
                }

                var pid = livePid ?? _runningEngineProcess.Id;

                _runningEngineProcess.Kill(entireProcessTree: true);
                _runningEngineProcess.WaitForExit(5000);
                _lastExitCode = _runningEngineProcess.HasExited ? _runningEngineProcess.ExitCode : -1;
                _lastExitMessage = "Stopped by user";
                _runningEngineProcess = null;

                _logger.LogInformation("Migration Engine stopped (PID: {Pid})", pid);

                return Ok(new
                {
                    success = true,
                    message = "Migration Engine stopped successfully",
                    pid = pid
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to stop Migration Engine");
                return Ok(new
                {
                    success = false,
                    error = ex.Message
                });
            }
        }
    }

    /// <summary>
    /// Migration Engine durumunu kontrol et
    /// </summary>
    [HttpGet("status")]
    public IActionResult GetEngineStatus()
    {
        lock (_processLock)
        {
            try
            {
                bool isRunning = IsEngineProcessAlive(out var pid);

                if (isRunning && _runningEngineProcess != null)
                {
                    DateTime? startTime = null;
                    double? uptime = null;

                    try
                    {
                        startTime = _runningEngineProcess.StartTime;
                        uptime = (DateTime.Now - startTime.Value).TotalSeconds;
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, "Could not get process start time for PID {Pid}", pid);
                    }

                    return Ok(new
                    {
                        status = "running",
                        pid,
                        startTime = startTime?.ToString("O"),
                        uptime = uptime
                    });
                }

                var enginePath = EnginePath;
                var configPath = Path.Combine(enginePath, "appsettings.json");
                bool hasConfig = System.IO.File.Exists(configPath);
                var lastFatal = TryReadLastFatalError(enginePath);

                return Ok(new
                {
                    status = "stopped",
                    hasConfiguration = hasConfig,
                    configPath = hasConfig ? configPath : null,
                    executable = EngineLauncher.FindBuiltExecutable(enginePath),
                    lastExitCode = _lastExitCode,
                    lastExitMessage = _lastExitMessage,
                    lastFatalError = lastFatal
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to get engine status");
                return Ok(new
                {
                    status = "error",
                    error = ex.Message
                });
            }
        }
    }

    private static string? TryReadLastFatalError(string enginePath)
    {
        try
        {
            var dbPath = Path.Combine(enginePath, "migration_checkpoint.db");
            if (!System.IO.File.Exists(dbPath))
                return null;

            using var conn = new Microsoft.Data.Sqlite.SqliteConnection($"Data Source={dbPath};Mode=ReadOnly");
            conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = """
                SELECT error_message FROM error_log
                WHERE error_type = 'FATAL_ERROR'
                ORDER BY id DESC LIMIT 1
                """;
            var o = cmd.ExecuteScalar();
            return o?.ToString();
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// MigrationEngine projesini derler
    /// </summary>
    [HttpPost("build")]
    public IActionResult BuildEngine()
    {
        var enginePath = EnginePath;
        if (!Directory.Exists(enginePath))
        {
            return Ok(new
            {
                success = false,
                error = $"MigrationEngine directory not found at: {enginePath}"
            });
        }

        var (success, output, error) = EngineLauncher.Build(enginePath);
        var exePath = EngineLauncher.FindBuiltExecutable(enginePath);

        return Ok(new
        {
            success,
            output,
            error,
            executable = exePath
        });
    }
}
