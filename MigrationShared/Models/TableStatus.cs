using MigrationShared.Enums;

namespace MigrationShared.Models;

public class TableStatus
{
    public string TableName { get; set; } = string.Empty;
    public MigrationPhase Phase { get; set; }
    public MigrationStatus Status { get; set; }
    public long RowsLoaded { get; set; }
    public long TotalRows { get; set; }
    public double PercentComplete => TotalRows > 0 ? (RowsLoaded * 100.0 / TotalRows) : 0;
    public double RowsPerSecond { get; set; }
    public List<string> Warnings { get; set; } = new();
    public DateTime? StartTime { get; set; }
    public DateTime? EndTime { get; set; }
    public string? ErrorMessage { get; set; }
}
