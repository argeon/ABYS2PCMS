using MigrationShared.Enums;

namespace MigrationShared.Models;

public class ProgressEvent
{
    public string TableName { get; set; } = string.Empty;
    public string PartitionKey { get; set; } = string.Empty;
    public MigrationStatus Status { get; set; }
    public long RowsProcessed { get; set; }
    public long TotalRows { get; set; }
    public double PercentComplete { get; set; }
    public double RowsPerSecond { get; set; }
    public string Phase { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    public string? Warning { get; set; }
}
