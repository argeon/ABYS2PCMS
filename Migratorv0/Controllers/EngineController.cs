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

    private IActionResult LaunchEngine(string argument, string actionPastTense)
    {
        lock (_processLock)
        {
            try
            {
                if (_runningEngineProcess != null && !_runningEngineProcess.HasExited)
                {
                    return Ok(new
                    {
                        success = false,
                        message = "Migration Engine already running",
                        pid = _runningEngineProcess.Id
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
                if (_runningEngineProcess == null || _runningEngineProcess.HasExited)
                {
                    return Ok(new
                    {
                        success = false,
                        message = "Migration Engine is not running"
                    });
                }

                var pid = _runningEngineProcess.Id;

                _runningEngineProcess.Kill(entireProcessTree: true);
                _runningEngineProcess.WaitForExit(5000);

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
                bool isRunning = _runningEngineProcess != null && !_runningEngineProcess.HasExited;

                if (isRunning)
                {
                    DateTime? startTime = null;
                    double? uptime = null;

                    try
                    {
                        startTime = _runningEngineProcess!.StartTime;
                        uptime = (DateTime.Now - startTime.Value).TotalSeconds;
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, "Could not get process start time for PID {Pid}", _runningEngineProcess!.Id);
                    }

                    return Ok(new
                    {
                        status = "running",
                        pid = _runningEngineProcess!.Id,
                        startTime = startTime?.ToString("O"),
                        uptime = uptime
                    });
                }

                var enginePath = EnginePath;
                var configPath = Path.Combine(enginePath, "appsettings.json");
                bool hasConfig = System.IO.File.Exists(configPath);

                return Ok(new
                {
                    status = "stopped",
                    hasConfiguration = hasConfig,
                    configPath = hasConfig ? configPath : null,
                    executable = EngineLauncher.FindBuiltExecutable(enginePath)
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
