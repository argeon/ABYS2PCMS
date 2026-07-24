using Microsoft.AspNetCore.Mvc;
using MigrationShared.Models.TransferStudio;
using MigrationWeb.Services;
using MigrationWeb.Services.TransferStudio;

namespace MigrationWeb.Controllers;

[Route("api/transfer-studio/pipeline")]
[ApiController]
public class PipelineController : ControllerBase
{
    private readonly TransferStudioDataService _transferData;
    private readonly OracleCheckpointReader _oracleReader;
    private readonly PipelineValidationOrchestrator _orchestrator;
    private readonly ILogger<PipelineController> _logger;

    public PipelineController(
        TransferStudioDataService transferData,
        OracleCheckpointReader oracleReader,
        PipelineValidationOrchestrator orchestrator,
        ILogger<PipelineController> logger)
    {
        _transferData = transferData;
        _oracleReader = oracleReader;
        _orchestrator = orchestrator;
        _logger = logger;
    }

    [HttpGet("projects")]
    public IActionResult ListProjects() => Ok(_transferData.ListPipelineProjects());

    [HttpGet("projects/{id:int}")]
    public IActionResult GetProject(int id)
    {
        var doc = _transferData.GetPipelineDocument(id);
        return doc == null ? NotFound() : Ok(new { id, document = doc });
    }

    [HttpPost("projects")]
    public IActionResult CreateProject([FromBody] SavePipelineRequest request)
    {
        if (request.Document == null || string.IsNullOrWhiteSpace(request.Document.Name))
            return BadRequest(new { error = "Proje adı gerekli." });

        var id = _transferData.SavePipelineProject(request.Document);
        return Ok(new { id });
    }

    [HttpPut("projects/{id:int}")]
    public IActionResult UpdateProject(int id, [FromBody] SavePipelineRequest request)
    {
        if (request.Document == null)
            return BadRequest(new { error = "Geçersiz proje." });

        var savedId = _transferData.SavePipelineProject(request.Document, id);
        return Ok(new { id = savedId });
    }

    [HttpDelete("projects/{id:int}")]
    public IActionResult DeleteProject(int id)
    {
        if (!_transferData.DeletePipelineProject(id))
            return NotFound();
        return Ok(new { success = true });
    }

    [HttpGet("oracle-runs")]
    public IActionResult ListOracleRuns() => Ok(_oracleReader.ListOracleRuns());

    [HttpPost("projects/{id:int}/validate")]
    public async Task<IActionResult> ValidateProject(
        int id,
        [FromBody] PipelineValidateRequest? request,
        CancellationToken ct)
    {
        try
        {
            var result = await _orchestrator.ValidateProjectAsync(
                id,
                request?.IncludeContent ?? true,
                request?.IncludeE2e ?? true,
                ct);
            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Pipeline validasyon hatası project {Id}", id);
            return Ok(new { error = ex.Message });
        }
    }

    [HttpGet("projects/{id:int}/validation/latest")]
    public IActionResult GetLatestValidation(int id)
    {
        var result = _transferData.GetLatestPipelineValidation(id);
        return result == null ? NotFound() : Ok(result);
    }

    [HttpPost("projects/sample-it-user")]
    public IActionResult CreateItUserPipelineSample()
    {
        var recipes = _transferData.ListRecipes();
        var itUser = recipes.FirstOrDefault(r =>
            r.MigrationId.Equals("IT_USER", StringComparison.OrdinalIgnoreCase));

        if (itUser == null)
        {
            var doc = TransferRecipeSamples.CreateItUserSample();
            var recipeId = _transferData.SaveRecipe(doc, TransferRecipeStatus.Draft);
            itUser = _transferData.ListRecipes().First(r => r.Id == recipeId);
        }

        var project = new PipelineProjectDocument
        {
            Name = "Oracle → MSSQL → MSSQL (IT_USER)",
            Description = "3 aşamalı örnek: Oracle run bağlayın, Aşama 1+2+3+E2E validasyon.",
            Steps =
            [
                new PipelineStepDefinition
                {
                    RecipeId = itUser.Id,
                    OracleTable = "IT_USER",
                    Label = "Kullanıcılar",
                    SortOrder = 10
                }
            ],
            E2eFixedKeys = [1, 2, 3],
            FailFast = true
        };

        var id = _transferData.SavePipelineProject(project);
        return Ok(new { id, document = project });
    }
}

public class SavePipelineRequest
{
    public PipelineProjectDocument? Document { get; set; }
}

public class PipelineValidateRequest
{
    public bool IncludeContent { get; set; } = true;
    public bool IncludeE2e { get; set; } = true;
}
