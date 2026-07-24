namespace MigrationShared.Models;

public class MigrationHistory
{
    public int Id { get; set; }
    public int RunId { get; set; }
    public string MigrationName { get; set; } = string.Empty;
    public string SourceConnection { get; set; } = string.Empty;
    public string TargetConnection { get; set; } = string.Empty;
    public string SourceSchema { get; set; } = string.Empty;
    public int TableCount { get; set; }
    public long TotalRows { get; set; }
    public DateTime StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public int? DurationSeconds { get; set; }
    public string Status { get; set; } = string.Empty;
    public string ConfigJson { get; set; } = string.Empty;
}

public class ConnectionProfile
{
    public int Id { get; set; }
    public string ProfileName { get; set; } = string.Empty;
    public string ConnectionType { get; set; } = string.Empty; // "Oracle" or "MSSQL"
    public string? Host { get; set; }
    public string? Port { get; set; }
    public string? ServiceName { get; set; }
    public string? DatabaseName { get; set; }
    public string? Username { get; set; }
    public string? SchemaName { get; set; }
    public string? AuthType { get; set; }
    public bool TrustCert { get; set; }
    public string? ConnectionString { get; set; }
    /// <summary>
    /// Full migration configuration as JSON: tables, parallelism, schema options, etc.
    /// Set when the user saves a "full migration profile" from the wizard.
    /// </summary>
    public string? ConfigJson { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? LastUsedAt { get; set; }
    public int UseCount { get; set; }
    public bool IsDeleted { get; set; }
    public DateTime? DeletedAt { get; set; }
}

public class MigrationMetric
{
    public int Id { get; set; }
    public int RunId { get; set; }
    public string TableName { get; set; } = string.Empty;
    public string MetricType { get; set; } = string.Empty; // "throughput", "duration", "memory", etc.
    public double MetricValue { get; set; }
    public DateTime RecordedAt { get; set; }
}

public class ThreadMonitoring
{
    public int Id { get; set; }
    public int RunId { get; set; }
    public int PartitionId { get; set; }
    public string TableName { get; set; } = string.Empty;
    public int ThreadId { get; set; }
    public string Status { get; set; } = string.Empty; // "RUNNING", "COMPLETED", "ERROR"
    public DateTime StartedAt { get; set; }
    public DateTime LastHeartbeat { get; set; }
    public long RowsProcessed { get; set; }
    public long TotalRows { get; set; }
    public double CurrentSpeed { get; set; } // rows/sec
    public DateTime? EstimatedCompletion { get; set; }
}

public class PerformanceSummary
{
    public int Id { get; set; }
    public int RunId { get; set; }
    public int TotalDurationSeconds { get; set; }
    public double AvgRowsPerSecond { get; set; }
    public double PeakRowsPerSecond { get; set; }
    public long TotalBytesTransferred { get; set; }
    public int TotalErrors { get; set; }
    public int TotalWarnings { get; set; }
    public double ParallelEfficiency { get; set; }
    public int SchemaPhaseDuration { get; set; }
    public int LoadPhaseDuration { get; set; }
    public int IndexPhaseDuration { get; set; }
    public int ValidationPhaseDuration { get; set; }
}

public class TableStatistics
{
    public int Id { get; set; }
    public int RunId { get; set; }
    public string TableName { get; set; } = string.Empty;
    public long OracleRowCount { get; set; }
    public long MssqlRowCount { get; set; }
    public double OracleSizeMb { get; set; }
    public double MssqlSizeMb { get; set; }
    public int LoadDurationSeconds { get; set; }
    public double AvgRowsPerSecond { get; set; }
    public int PartitionCount { get; set; }
    public int RetryCount { get; set; }
    public string ValidationStatus { get; set; } = string.Empty;
}

public class ErrorLog
{
    public int Id { get; set; }
    public int RunId { get; set; }
    public string? TableName { get; set; }
    public int? PartitionId { get; set; }
    public string ErrorType { get; set; } = string.Empty;
    public string ErrorMessage { get; set; } = string.Empty;
    public string? StackTrace { get; set; }
    public DateTime OccurredAt { get; set; }
    public int RetryAttempt { get; set; }
    public bool Resolved { get; set; }
}

public class ComparisonSnapshot
{
    public int Id { get; set; }
    public int RunId1 { get; set; }
    public int RunId2 { get; set; }
    public string ComparisonMetric { get; set; } = string.Empty;
    public double RunValue1 { get; set; }
    public double RunValue2 { get; set; }
    public double ImprovementPercent { get; set; }
    public DateTime CreatedAt { get; set; }
}
