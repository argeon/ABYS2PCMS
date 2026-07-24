namespace MigrationShared.Models.TransferStudio;

public class PipelineStepDefinition
{
    public int RecipeId { get; set; }
    /// <summary>Oracle tablo adı (Aşama 1 eşlemesi).</summary>
    public string OracleTable { get; set; } = string.Empty;
    public string? Label { get; set; }
    public int SortOrder { get; set; }
}

public class PipelineProjectDocument
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    /// <summary>Oracle → MSSQL-1 migration run (migration_checkpoint.db).</summary>
    public int? OracleRunId { get; set; }
    public List<PipelineStepDefinition> Steps { get; set; } = new();
    /// <summary>E2E spot check için sabit business key listesi.</summary>
    public List<long> E2eFixedKeys { get; set; } = new();
    public bool FailFast { get; set; } = true;
}

public class PipelineProjectSummary
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public int? OracleRunId { get; set; }
    public int StepCount { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}

public enum PipelineStageKind
{
    Stage1_OracleToMssql1 = 1,
    Stage2_Mssql1ToMssql2_Insert = 2,
    Stage3_Mssql1ToMssql2_Update = 3,
    E2E_Chain = 4
}

public class PipelineStepValidationResult
{
    public int RecipeId { get; set; }
    public string? Label { get; set; }
    public string OracleTable { get; set; } = string.Empty;
    public PipelineStageKind Stage { get; set; }
    public bool Passed { get; set; }
    public List<ValidationGateOutcome> Gates { get; set; } = new();
    public List<ContentMismatchRow> ContentMismatches { get; set; } = new();
    public List<E2eKeyCheckResult> E2eChecks { get; set; } = new();
    public string? Error { get; set; }
}

public class E2eKeyCheckResult
{
    public long Key { get; set; }
    public bool OraclePresent { get; set; }
    public bool Stage1Present { get; set; }
    public bool Stage2Present { get; set; }
    public bool Passed { get; set; }
    public string? Detail { get; set; }
}

public class PipelineValidationRunResult
{
    public int ValidationRunId { get; set; }
    public int ProjectId { get; set; }
    public bool AllPassed { get; set; }
    public DateTime EvaluatedAt { get; set; }
    public List<PipelineStepValidationResult> Steps { get; set; } = new();
}
