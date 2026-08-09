using Microsoft.AspNetCore.Mvc;
using MigrationWeb.Services.MssqlCopy;
using System.Diagnostics;

namespace MigrationWeb.Controllers;

[Route("api/mssql-copy-engine")]
[ApiController]
public class MssqlCopyEngineController : ControllerBase
{
    private readonly ILogger<MssqlCopyEngineController> _logger;
    private readonly IWebHostEnvironment _environment;
    private static Process? _runningEngineProcess;
    private static readonly object _processLock = new();

    public MssqlCopyEngineController(ILogger<MssqlCopyEngineController> logger, IWebHostEnvironment environment)
    {
        _logger = logger;
        _environment = environment;
    }

    private string EnginePath => MssqlCopyEngineLauncher.GetEngineDirectory(_environment.ContentRootPath);

    [HttpPost("start")]
    public IActionResult StartEngine() => LaunchEngine("--run", "started");

    [HttpPost("resume")]
    public IActionResult ResumeEngine() => LaunchEngine("--resume", "resumed");

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
                        message = "MSSQL Copy Engine already running",
                        pid = _runningEngineProcess.Id
                    });
                }

                var enginePath = EnginePath;
                if (!Directory.Exists(enginePath))
                {
                    return Ok(new
                    {
                        success = false,
                        error = $"MssqlCopyEngine directory not found at: {enginePath}"
                    });
                }

                var startInfo = MssqlCopyEngineLauncher.CreateStartInfo(enginePath, argument);
                _runningEngineProcess = Process.Start(startInfo);

                if (_runningEngineProcess == null)
                    return Ok(new { success = false, error = "Failed to start MSSQL Copy Engine process" });

                _logger.LogInformation(
                    "MSSQL Copy Engine {Action} with PID: {Pid}",
                    actionPastTense,
                    _runningEngineProcess.Id);

                return Ok(new
                {
                    success = true,
                    message = $"MSSQL Copy Engine {actionPastTense} successfully",
                    pid = _runningEngineProcess.Id,
                    path = enginePath
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to {Action} MSSQL Copy Engine", actionPastTense);
                return Ok(new { success = false, error = ex.Message });
            }
        }
    }

    [HttpPost("stop")]
    public IActionResult StopEngine()
    {
        lock (_processLock)
        {
            try
            {
                if (_runningEngineProcess == null || _runningEngineProcess.HasExited)
                    return Ok(new { success = false, message = "MSSQL Copy Engine is not running" });

                var pid = _runningEngineProcess.Id;
                _runningEngineProcess.Kill(entireProcessTree: true);
                _runningEngineProcess.WaitForExit(5000);
                _runningEngineProcess = null;

                return Ok(new { success = true, message = "MSSQL Copy Engine stopped successfully", pid });
            }
            catch (Exception ex)
            {
                return Ok(new { success = false, error = ex.Message });
            }
        }
    }

    [HttpGet("status")]
    public IActionResult GetEngineStatus()
    {
        lock (_processLock)
        {
            try
            {
                var isRunning = _runningEngineProcess != null && !_runningEngineProcess.HasExited;
                if (isRunning)
                {
                    return Ok(new
                    {
                        status = "running",
                        pid = _runningEngineProcess!.Id,
                        startTime = _runningEngineProcess.StartTime.ToString("O"),
                        uptime = (DateTime.Now - _runningEngineProcess.StartTime).TotalSeconds
                    });
                }

                var configPath = Path.Combine(EnginePath, "appsettings.json");
                var hasConfig = System.IO.File.Exists(configPath);
                return Ok(new
                {
                    status = "stopped",
                    hasConfiguration = hasConfig,
                    configPath = hasConfig ? configPath : null,
                    executable = MssqlCopyEngineLauncher.FindBuiltExecutable(EnginePath)
                });
            }
            catch (Exception ex)
            {
                return Ok(new { status = "error", error = ex.Message });
            }
        }
    }

    [HttpPost("build")]
    public IActionResult BuildEngine()
    {
        var enginePath = EnginePath;
        if (!Directory.Exists(enginePath))
            return Ok(new { success = false, error = $"MssqlCopyEngine directory not found at: {enginePath}" });

        var (success, output, error) = MssqlCopyEngineLauncher.Build(enginePath);
        return Ok(new
        {
            success,
            output,
            error,
            executable = MssqlCopyEngineLauncher.FindBuiltExecutable(enginePath)
        });
    }
}
