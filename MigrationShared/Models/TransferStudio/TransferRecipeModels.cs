namespace MigrationShared.Models.TransferStudio;

public enum TransferRecipeStatus
{
    Draft = 0,
    Approved = 1,
    Archived = 2
}

public enum TransferExecutionMode
{
    Engine = 0,
    SqlScript = 1
}

public enum TransferPhaseType
{
    InsertSelect = 0,
    FkResolve = 1
}

public enum ContentCompareStrategy
{
    SampleByKey = 0,
    FixedKeys = 1,
    FullExcept = 2,
    CustomSql = 3
}

public enum ContentCompareKind
{
    Exact = 0,
    StringTrimIgnoreCase = 1,
    Decimal = 2,
    DateTime = 3,
    DateOnly = 4,
    NullEquivalent = 5,
    Custom = 6
}

public enum MetricGateType
{
    RowCount = 0,
    MissingByBridge = 1,
    BridgeNotNull = 2,
    SumBridgeKey = 3,
    CustomSql = 4
}

public class TransferEndpoints
{
    public int? SourceProfileId { get; set; }
    public string SourceConnectionString { get; set; } = string.Empty;
    public string SourceDatabase { get; set; } = string.Empty;
    public string SourceSchema { get; set; } = "dbo";
    public string SourceTable { get; set; } = string.Empty;

    public int? TargetProfileId { get; set; }
    public string TargetConnectionString { get; set; } = string.Empty;
    public string TargetDatabase { get; set; } = string.Empty;
    public string TargetSchema { get; set; } = "dbo";
    public string TargetTable { get; set; } = string.Empty;
}

public class BridgeKeyConfig
{
    public string SourceKeyColumn { get; set; } = string.Empty;
    public string TargetBridgeColumn { get; set; } = string.Empty;
    public string? TargetIdentityColumn { get; set; }
    public string? SourceFilter { get; set; }
}

public class TargetDdlStep
{
    public string Action { get; set; } = string.Empty;
    public string? ObjectName { get; set; }
    public string? ColumnName { get; set; }
    public string? DataType { get; set; }
    public string? Details { get; set; }
}

public class TransferBatchConfig
{
    public string BatchKeyColumn { get; set; } = string.Empty;
    public int BatchSize { get; set; } = 2000;
    public bool Resume { get; set; } = true;
    public int MaxErrors { get; set; } = 200;
    public string OnBatchError { get; set; } = "SingleRowRetry";
    public bool AllowHardReset { get; set; }
}

public class SourceJoinDefinition
{
    public string Alias { get; set; } = string.Empty;
    public string TableOrSubquery { get; set; } = string.Empty;
    public string JoinCondition { get; set; } = string.Empty;
    public bool IsSubquery { get; set; }
}

public class LookupMapDefinition
{
    public string Name { get; set; } = string.Empty;
    public List<LookupMapRow> Rows { get; set; } = new();
    public string JoinOn { get; set; } = string.Empty;
}

public class LookupMapRow
{
    public int Key { get; set; }
    public string Value { get; set; } = string.Empty;
}

public class ColumnMappingDefinition
{
    public string TargetColumn { get; set; } = string.Empty;
    public string SourceExpression { get; set; } = string.Empty;
    public bool ResolveInLaterPhase { get; set; }
    public bool IncludeInContentValidation { get; set; } = true;
    public string? ValidateAfterPhase { get; set; }
}

public class FkResolveStep
{
    public string TargetTable { get; set; } = string.Empty;
    public string TargetSchema { get; set; } = "dbo";
    public string Column { get; set; } = string.Empty;
    public string LookupTable { get; set; } = string.Empty;
    public string LookupSchema { get; set; } = "dbo";
    public string LookupBridgeColumn { get; set; } = string.Empty;
    public string LookupTargetColumn { get; set; } = string.Empty;
}

public class TransferPhaseDefinition
{
    public string Name { get; set; } = string.Empty;
    public TransferPhaseType PhaseType { get; set; } = TransferPhaseType.InsertSelect;
    public List<SourceJoinDefinition> SourceJoins { get; set; } = new();
    public List<LookupMapDefinition> Lookups { get; set; } = new();
    public List<ColumnMappingDefinition> ColumnMappings { get; set; } = new();
    public List<FkResolveStep> FkResolves { get; set; } = new();
}

public class MetricValidationRule
{
    public MetricGateType GateType { get; set; } = MetricGateType.RowCount;
    public bool Enabled { get; set; } = true;
    public string? SourceSql { get; set; }
    public string? TargetSql { get; set; }
    public string? ExpectedRelation { get; set; } = "Equal";
}

public class ContentCompareRule
{
    public string Label { get; set; } = string.Empty;
    public string SourceExpression { get; set; } = string.Empty;
    public string TargetExpression { get; set; } = string.Empty;
    public ContentCompareKind CompareAs { get; set; } = ContentCompareKind.Exact;
    public decimal? Tolerance { get; set; }
    public string? ValidateAfterPhase { get; set; }
}

public class ContentValidationProfile
{
    public bool Enabled { get; set; } = true;
    public ContentCompareStrategy Strategy { get; set; } = ContentCompareStrategy.SampleByKey;
    public int SampleSize { get; set; } = 100;
    public List<int> FixedKeys { get; set; } = new();
    public int MaxReportedMismatches { get; set; } = 50;
    public List<ContentCompareRule> Rules { get; set; } = new();
    public string? CustomSql { get; set; }
}

public class TransferValidationProfile
{
    public List<MetricValidationRule> Metrics { get; set; } = new();
    public ContentValidationProfile Content { get; set; } = new();
}

public class TransferExecutionSettings
{
    public TransferExecutionMode Mode { get; set; } = TransferExecutionMode.Engine;
    public string DefaultRunPhase { get; set; } = "ALL";
    public bool Debug { get; set; }
}

public class TransferRecipeDocument
{
    public string MigrationId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public TransferEndpoints Endpoints { get; set; } = new();
    public BridgeKeyConfig Bridge { get; set; } = new();
    public List<TargetDdlStep> PreDeploySteps { get; set; } = new();
    public TransferBatchConfig Batch { get; set; } = new();
    public List<TransferPhaseDefinition> Phases { get; set; } = new();
    public TransferValidationProfile Validation { get; set; } = new();
    public TransferExecutionSettings Execution { get; set; } = new();
}

public class TransferRecipeSummary
{
    public int Id { get; set; }
    public string MigrationId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public TransferRecipeStatus Status { get; set; }
    public int Version { get; set; }
    public int SortOrder { get; set; }
    public string SourceTable { get; set; } = string.Empty;
    public string TargetTable { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}

public class TransferRunSummary
{
    public int Id { get; set; }
    public int RecipeId { get; set; }
    public string RunUuid { get; set; } = string.Empty;
    public string RecipeName { get; set; } = string.Empty;
    public string Phase { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public long TotalOk { get; set; }
    public long TotalError { get; set; }
    public string? LastBridgeKey { get; set; }
    public DateTime StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
}

public class TransferEventLogEntry
{
    public long Id { get; set; }
    public int RunId { get; set; }
    public string Level { get; set; } = "Info";
    public string? Phase { get; set; }
    public int? BatchNo { get; set; }
    public string? BridgeFrom { get; set; }
    public string? BridgeTo { get; set; }
    public string? BridgeKey { get; set; }
    public string Message { get; set; } = string.Empty;
    public int? RowCount { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class ValidationGateOutcome
{
    public string GateType { get; set; } = string.Empty;
    public bool Passed { get; set; }
    public string? SourceValue { get; set; }
    public string? TargetValue { get; set; }
    public string? Detail { get; set; }
}

public class ContentMismatchRow
{
    public string BridgeKey { get; set; } = string.Empty;
    public string ColumnLabel { get; set; } = string.Empty;
    public string? SourceValue { get; set; }
    public string? TargetValue { get; set; }
    public string CompareAs { get; set; } = string.Empty;
    public string? Phase { get; set; }
}

public class TransferValidationRunResult
{
    public int ValidationRunId { get; set; }
    public int RecipeId { get; set; }
    public string Phase { get; set; } = string.Empty;
    public bool AllPassed { get; set; }
    public List<ValidationGateOutcome> Metrics { get; set; } = new();
    public List<ContentMismatchRow> ContentMismatches { get; set; } = new();
    public DateTime EvaluatedAt { get; set; }
}
