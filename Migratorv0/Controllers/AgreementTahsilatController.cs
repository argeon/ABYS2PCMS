using Microsoft.AspNetCore.Mvc;
using MigrationWeb.Models.Staging;
using MigrationWeb.Services.Staging;

namespace MigrationWeb.Controllers;

[Route("api/staging/tahsilat")]
[ApiController]
public class AgreementTahsilatController : ControllerBase
{
    private readonly AgreementTahsilatOrchestrator _orch;
    private readonly AgreementPilotLogStore _logStore;
    private readonly ILogger<AgreementTahsilatController> _logger;

    public AgreementTahsilatController(
        AgreementTahsilatOrchestrator orch,
        AgreementPilotLogStore logStore,
        ILogger<AgreementTahsilatController> logger)
    {
        _orch = orch;
        _logStore = logStore;
        _logger = logger;
    }

    [HttpGet("catalog")]
    public IActionResult Catalog() =>
        Ok(new { success = true, data = new TahsilatCatalogResponse { Steps = AgreementTahsilatOrchestrator.Catalog.ToList() } });

    [HttpPost("step/{stepId}")]
    public async Task<IActionResult> RunStep(string stepId, [FromBody] AgreementTahsilatRequest request, CancellationToken ct)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(stepId))
                return Ok(new { success = false, error = "stepId gerekli." });

            var result = await _orch.RunStepAsync(stepId, request, ct);
            return Ok(new { success = result.Ok, data = result, error = result.Ok ? null : result.Message });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Tahsilat step API failed {Step}", stepId);
            return Ok(new { success = false, error = ex.Message });
        }
    }

    /// <summary>Doğrulama için saklanan pilot log paketleri (şifresiz).</summary>
    [HttpGet("pilot-logs")]
    public IActionResult ListPilotLogs([FromQuery] int take = 40) =>
        Ok(new { success = true, data = new { root = _logStore.Root, runs = _logStore.ListRuns(take) } });

    [HttpGet("pilot-logs/{runId}")]
    public IActionResult GetPilotLog(string runId)
    {
        var pack = _logStore.GetRunPack(runId);
        if (pack == null)
            return Ok(new { success = false, error = $"Run bulunamadı: {runId}" });
        return Ok(new { success = true, data = pack });
    }
}
