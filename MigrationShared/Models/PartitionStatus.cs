namespace MigrationShared.Models;

/// <summary>
/// One row per table_checkpoints partition for the active migration run.
/// </summary>
public class PartitionStatus
{
    public int Id { get; set; }
    public string TableName { get; set; } = string.Empty;
    public string PartitionKey { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public long RowsProcessed { get; set; }
    public long TotalRows { get; set; }
    public DateTime? StartTime { get; set; }
    public DateTime? EndTime { get; set; }
    public string? ErrorMessage { get; set; }
}
