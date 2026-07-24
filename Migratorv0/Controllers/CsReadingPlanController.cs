using Microsoft.AspNetCore.Mvc;
using MigrationShared.Models;
using MigrationWeb.Services.Migrate;

namespace MigrationWeb.Controllers;

[Route("api/migrate/cs-reading-plan")]
[ApiController]
public class CsReadingPlanController : ControllerBase
{
    private readonly CsReadingPlanMigrationService _service;
    private readonly ILogger<CsReadingPlanController> _logger;

    public CsReadingPlanController(
        CsReadingPlanMigrationService service,
        ILogger<CsReadingPlanController> logger)
    {
        _service = service;
        _logger = logger;
    }

    [HttpGet("definition")]
    public IActionResult GetDefinition()
    {
        var def = _service.LoadDefinition();
        return Ok(new
        {
            success = true,
            definition = def,
            meta = new
            {
                sourceTable = $"{def.OracleSchema}.{CsReadingPlanMigrationDefinition.SourceTable}",
                locationColumn = CsReadingPlanMigrationDefinition.LocationColumn,
                wgs84Srid = CsReadingPlanMigrationDefinition.Wgs84Srid
            }
        });
    }

    [HttpPost("definition")]
    public async Task<IActionResult> SaveDefinition([FromBody] CsReadingPlanMigrationDefinition definition, CancellationToken ct)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(definition.OracleConnectionString)
                || string.IsNullOrWhiteSpace(definition.MssqlConnectionString))
            {
                return Ok(new { success = false, error = "Oracle ve MSSQL bağlantı dizeleri gerekli." });
            }

            await _service.SaveDefinitionAsync(definition, ct);
            return Ok(new { success = true, path = _service.DefinitionPath });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Save CS_READING_PLAN definition failed");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpPost("preview")]
    public async Task<IActionResult> Preview([FromBody] CsReadingPlanMigrationDefinition definition, CancellationToken ct)
    {
        try
        {
            var preview = await _service.GetPreviewAsync(definition, ct);
            return Ok(new { success = true, preview });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "CS_READING_PLAN preview failed");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpPost("start")]
    public async Task<IActionResult> Start([FromBody] CsReadingPlanMigrationDefinition definition, CancellationToken ct)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(definition.OracleConnectionString)
                || string.IsNullOrWhiteSpace(definition.MssqlConnectionString))
            {
                return Ok(new { success = false, error = "Oracle ve MSSQL bağlantı dizeleri gerekli." });
            }

            await _service.SaveDefinitionAsync(definition, ct);
            var config = _service.BuildMigrationConfig(definition);
            await _service.WriteEngineAppSettingsAsync(config, ct);

            var (success, pid, error) = _service.StartEngine("--run");
            if (!success)
                return Ok(new { success = false, error });

            return Ok(new
            {
                success = true,
                pid,
                message = "CS_READING_PLAN aktarımı başlatıldı (C# Migration Engine). LOCATION → geography WGS84.",
                targetTable = definition.TargetTableName,
                enginePath = _service.EngineDirectory
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "CS_READING_PLAN start failed");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpPost("resume")]
    public async Task<IActionResult> Resume(CancellationToken ct)
    {
        try
        {
            var definition = _service.LoadDefinition();
            if (string.IsNullOrWhiteSpace(definition.OracleConnectionString))
                return Ok(new { success = false, error = "Kayıtlı aktarım tanımı bulunamadı." });

            var config = _service.BuildMigrationConfig(definition);
            await _service.WriteEngineAppSettingsAsync(config, ct);

            var (success, pid, error) = _service.StartEngine("--resume");
            if (!success)
                return Ok(new { success = false, error });

            return Ok(new { success = true, pid, message = "Aktarım kaldığı yerden devam ediyor." });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "CS_READING_PLAN resume failed");
            return Ok(new { success = false, error = ex.Message });
        }
    }
}
