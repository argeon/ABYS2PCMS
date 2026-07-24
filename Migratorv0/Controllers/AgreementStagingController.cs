using Microsoft.AspNetCore.Mvc;
using MigrationWeb.Models.Staging;
using MigrationWeb.Services.Staging;

namespace MigrationWeb.Controllers;

[Route("api/staging/agreement")]
[ApiController]
public class AgreementStagingController : ControllerBase
{
    private readonly AgreementStagingService _service;
    private readonly ILogger<AgreementStagingController> _logger;

    public AgreementStagingController(AgreementStagingService service, ILogger<AgreementStagingController> logger)
    {
        _service = service;
        _logger = logger;
    }

    [HttpPost("test")]
    public async Task<IActionResult> Test([FromBody] AgreementStagingLoadRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.OracleConnectionString))
            return Ok(new { success = false, error = "Oracle bağlantı dizesi gerekli." });

        var (ok, message) = await _service.TestConnectionAsync(request.OracleConnectionString, ct);
        return Ok(new { success = ok, message });
    }

    [HttpPost("load")]
    public async Task<IActionResult> Load([FromBody] AgreementStagingLoadRequest request, CancellationToken ct)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.OracleConnectionString))
                return Ok(new { success = false, error = "Oracle bağlantı dizesi gerekli." });
            if (request.AgreementId <= 0)
                return Ok(new { success = false, error = "Geçerli bir sözleşme ID girin." });

            var payload = await _service.LoadAsync(request, ct);
            return Ok(new { success = true, data = payload });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Agreement staging load failed for {AgrId}", request.AgreementId);
            return Ok(new { success = false, error = ex.Message });
        }
    }
}
