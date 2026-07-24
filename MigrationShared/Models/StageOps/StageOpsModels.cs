namespace MigrationShared.Models.StageOps;

public static class StageOpsSurfaces
{
    public const string Ctas = "ctas";
    public const string TransferSql = "transfer-sql";
    public const string ProdSql = "prod-sql";

    public static readonly string[] All = [Ctas, TransferSql, ProdSql];

    public static bool IsValid(string? surface) =>
        !string.IsNullOrWhiteSpace(surface) &&
        All.Contains(surface, StringComparer.OrdinalIgnoreCase);
}

public enum StageKind
{
    OracleCtas = 1,
    SpMigrate = 2,
    SqlScript = 3,
    Manual = 4
}

public enum StageStatus
{
    Ready = 0,
    Queued = 1,
    Running = 2,
    Done = 3,
    Failed = 4,
    Skipped = 5,
    Invalid = 6
}

public class StageDefinition
{
    public string Id { get; set; } = string.Empty;
    public string Surface { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Domain { get; set; } = string.Empty;
    public StageKind Kind { get; set; }
    public string? Path { get; set; }
    public string? ProcedureName { get; set; }
    public int SortOrder { get; set; }
    public long? EstimatedRows { get; set; }
    public List<string> DependsOn { get; set; } = new();
    public List<string> Writes { get; set; } = new();
    public List<string> Reads { get; set; } = new();
    public bool ParallelSafe { get; set; } = true;
    public int SlotCost { get; set; } = 1;
    public bool RecreateOnRetry { get; set; } = true;
    public string Status { get; set; } = nameof(StageStatus.Ready);
    public string? SyntaxStatus { get; set; }
    public string? AnalysisJson { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class StageRunSummary
{
    public int Id { get; set; }
    public string RunUuid { get; set; } = string.Empty;
    public string Surface { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public int MaxParallel { get; set; }
    public int TotalStages { get; set; }
    public int DoneCount { get; set; }
    public int FailedCount { get; set; }
    public int RunningCount { get; set; }
    public long TotalRows { get; set; }
    public string? ParamsJson { get; set; }
    public DateTime StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
}

public class StageRunItem
{
    public long Id { get; set; }
    public int RunId { get; set; }
    public string StageId { get; set; } = string.Empty;
    public string StageName { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public int? ExitCode { get; set; }
    public long ElapsedMs { get; set; }
    public long? Rows { get; set; }
    public double? RowsPerSec { get; set; }
    public string? LogPath { get; set; }
    public string? DetailJson { get; set; }
    public DateTime? StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
}

public class StageEventEntry
{
    public long Id { get; set; }
    public int RunId { get; set; }
    public string? StageId { get; set; }
    public string Level { get; set; } = "Info";
    public string Message { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}

public class ScriptAnalysisResult
{
    public bool SyntaxOk { get; set; }
    public List<string> SyntaxErrors { get; set; } = new();
    public List<string> Reads { get; set; } = new();
    public List<string> Writes { get; set; } = new();
    public List<string> Calls { get; set; } = new();
    public List<string> SuggestedDependsOn { get; set; } = new();
    public List<string> Warnings { get; set; } = new();
}

public class SchemaGateResult
{
    public bool Compatible { get; set; }
    public string? SourceObject { get; set; }
    public string? TargetObject { get; set; }
    public List<SchemaDriftItem> Drift { get; set; } = new();
    public string? Detail { get; set; }
}

public class SchemaDriftItem
{
    public string Column { get; set; } = string.Empty;
    public string? SourceType { get; set; }
    public string? TargetType { get; set; }
    public string Issue { get; set; } = string.Empty;
}

public class StartStageRunRequest
{
    public List<string> StageIds { get; set; } = new();
    public int MaxParallel { get; set; } = 2;
    public bool Resume { get; set; }
    public bool HardReset { get; set; }
    public bool SkipSchemaGate { get; set; }
}

public class UploadScriptResult
{
    public string StageId { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public ScriptAnalysisResult Analysis { get; set; } = new();
    public bool Accepted { get; set; }
}
