using Microsoft.AspNetCore.Mvc;
using MigrationEngine.Checkpoint;
using MigrationShared.Models;

namespace MigrationWeb.Controllers;

[Route("api/[controller]")]
[ApiController]
public class ErrorsController : ControllerBase
{
    private readonly ExtendedCheckpointRepository _extendedCheckpoint;
    private readonly ILogger<ErrorsController> _logger;

    public ErrorsController(ILogger<ErrorsController> logger, IConfiguration configuration)
    {
        _logger = logger;
        
        var sqlitePath = configuration.GetValue<string>("Checkpoint:SqlitePath") ?? "migration_checkpoint.db";
        var fullPath = Path.Combine(Directory.GetCurrentDirectory(), "..", "MigrationEngine", sqlitePath);
        
        _extendedCheckpoint = new ExtendedCheckpointRepository(fullPath);
    }

    /// <summary>
    /// Tüm hataları getirir
    /// </summary>
    [HttpGet]
    public IActionResult GetAllErrors([FromQuery] int? runId = null, [FromQuery] string? tableName = null)
    {
        try
        {
            List<ErrorLog> errors;
            
            if (runId.HasValue && !string.IsNullOrEmpty(tableName))
            {
                errors = _extendedCheckpoint.GetErrorsByTable(runId.Value, tableName);
            }
            else if (runId.HasValue)
            {
                errors = _extendedCheckpoint.GetErrorsByRunId(runId.Value);
            }
            else
            {
                // Tüm hatalar - son 100 migration run'ındaki hatalar
                errors = GetAllRecentErrors(100);
            }
            
            return Ok(errors);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve errors");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Belirli bir run'daki hataları getirir
    /// </summary>
    [HttpGet("run/{runId}")]
    public IActionResult GetErrorsByRun(int runId)
    {
        try
        {
            var errors = _extendedCheckpoint.GetErrorsByRunId(runId);
            return Ok(errors);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve errors for run {RunId}", runId);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Belirli bir tablodaki hataları getirir
    /// </summary>
    [HttpGet("run/{runId}/table/{tableName}")]
    public IActionResult GetErrorsByTable(int runId, string tableName)
    {
        try
        {
            var errors = _extendedCheckpoint.GetErrorsByTable(runId, tableName);
            return Ok(errors);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve errors for table {Table}", tableName);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Hata tiplerine göre istatistik
    /// </summary>
    [HttpGet("run/{runId}/stats")]
    public IActionResult GetErrorStats(int runId)
    {
        try
        {
            var stats = _extendedCheckpoint.GetErrorStatsByType(runId);
            return Ok(stats);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve error stats for run {RunId}", runId);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Hatayı çözüldü olarak işaretle
    /// </summary>
    [HttpPost("{errorId}/resolve")]
    public IActionResult MarkAsResolved(int errorId)
    {
        try
        {
            _extendedCheckpoint.MarkErrorResolved(errorId);
            _logger.LogInformation("Error {ErrorId} marked as resolved", errorId);
            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to mark error {ErrorId} as resolved", errorId);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Çözülmemiş hataları getirir
    /// </summary>
    [HttpGet("unresolved")]
    public IActionResult GetUnresolvedErrors([FromQuery] int limit = 100)
    {
        try
        {
            var allErrors = GetAllRecentErrors(limit);
            var unresolved = allErrors.Where(e => !e.Resolved).ToList();
            return Ok(unresolved);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve unresolved errors");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Tüm hatalar için özet istatistikler
    /// </summary>
    [HttpGet("summary")]
    public IActionResult GetErrorSummary()
    {
        try
        {
            var allErrors = GetAllRecentErrors(100);
            
            var summary = new
            {
                totalErrors = allErrors.Count,
                unresolvedErrors = allErrors.Count(e => !e.Resolved),
                resolvedErrors = allErrors.Count(e => e.Resolved),
                affectedTables = allErrors.Where(e => !string.IsNullOrEmpty(e.TableName))
                    .Select(e => e.TableName)
                    .Distinct()
                    .Count(),
                errorTypes = allErrors.GroupBy(e => e.ErrorType)
                    .Select(g => new { type = g.Key, count = g.Count() })
                    .OrderByDescending(x => x.count)
                    .ToList(),
                errorsByTable = allErrors.Where(e => !string.IsNullOrEmpty(e.TableName))
                    .GroupBy(e => e.TableName)
                    .Select(g => new { table = g.Key, count = g.Count() })
                    .OrderByDescending(x => x.count)
                    .Take(10)
                    .ToList()
            };
            
            return Ok(summary);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve error summary");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    // Helper method - tüm son hataları getir (run_id'leri history'den al)
    private List<ErrorLog> GetAllRecentErrors(int maxRuns)
    {
        try
        {
            var history = _extendedCheckpoint.GetMigrationHistory(maxRuns);
            var runIds = history.Select(h => h.RunId).Distinct().ToList();
            
            var allErrors = new List<ErrorLog>();
            foreach (var runId in runIds)
            {
                var errors = _extendedCheckpoint.GetErrorsByRunId(runId);
                allErrors.AddRange(errors);
            }
            
            return allErrors.OrderByDescending(e => e.OccurredAt).ToList();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to get recent errors, returning empty list");
            return new List<ErrorLog>();
        }
    }
}
