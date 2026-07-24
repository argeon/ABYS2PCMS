using MigrationShared.Enums;

namespace MigrationShared.Models;

public class CheckpointRecord
{
    public int Id { get; set; }
    public int RunId { get; set; }
    public string TableName { get; set; } = string.Empty;
    public string PartitionKey { get; set; } = string.Empty;
    public MigrationStatus Status { get; set; }
    public long RowsProcessed { get; set; }
    public long TotalRows { get; set; }
    public DateTime? StartTime { get; set; }
    public DateTime? EndTime { get; set; }
    public string? ErrorMessage { get; set; }
    public long? StartPkValue { get; set; }
    public long? EndPkValue { get; set; }
}
