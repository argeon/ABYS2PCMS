using MigrationShared.Models.TransferStudio;
using MigrationShared.TransferStudio;

namespace MigrationWeb.Services.TransferStudio;

public class TransferStudioDataService : IDisposable
{
    private readonly TransferStudioRepository _repo;

    public TransferStudioDataService(string sqlitePath)
    {
        _repo = new TransferStudioRepository(sqlitePath);
    }

    public List<TransferRecipeSummary> ListRecipes() => _repo.ListRecipes();

    public (int id, TransferRecipeDocument doc)? GetRecipe(int id) => _repo.GetRecipe(id);

    public int SaveRecipe(TransferRecipeDocument doc, TransferRecipeStatus status, int? id = null) =>
        _repo.SaveRecipe(doc, status, id);

    public bool DeleteRecipe(int id) => _repo.DeleteRecipe(id);

    public int CreateRun(int recipeId, string runUuid, string executionMode, string phase, string? paramsJson) =>
        _repo.CreateRun(recipeId, runUuid, executionMode, phase, paramsJson);

    public void UpdateRun(int runId, string status, long totalOk, long totalError, string? lastBridgeKey, bool completed = false) =>
        _repo.UpdateRun(runId, status, totalOk, totalError, lastBridgeKey, completed);

    public List<TransferRunSummary> ListRuns(int? recipeId = null, int limit = 50) =>
        _repo.ListRuns(recipeId, limit);

    public void LogEvent(TransferEventLogEntry entry) => _repo.InsertEvent(entry);

    public List<TransferEventLogEntry> GetEvents(int runId, int limit = 200) =>
        _repo.GetEvents(runId, limit);

    public int SaveValidationResult(TransferValidationRunResult result, int? transferRunId) =>
        _repo.SaveValidationResult(result, transferRunId);

    public TransferValidationRunResult? GetLatestValidation(int recipeId) =>
        _repo.GetLatestValidation(recipeId);

    public List<PipelineProjectSummary> ListPipelineProjects() => _repo.ListPipelineProjects();

    public PipelineProjectDocument? GetPipelineDocument(int id) => _repo.GetPipelineDocument(id);

    public int SavePipelineProject(PipelineProjectDocument doc, int? id = null) =>
        _repo.SavePipelineProject(doc, id);

    public bool DeletePipelineProject(int id) => _repo.DeletePipelineProject(id);

    public PipelineValidationRunResult? GetLatestPipelineValidation(int projectId) =>
        _repo.GetLatestPipelineValidation(projectId);

    public int SavePipelineValidationRun(PipelineValidationRunResult result) =>
        _repo.SavePipelineValidationRun(result);

    public void Dispose() => _repo.Dispose();
}
