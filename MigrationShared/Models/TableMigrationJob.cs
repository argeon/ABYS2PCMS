namespace MigrationShared.Models;

public class TableMigrationJob
{
    public string TableName { get; set; } = string.Empty;
    public long EstimatedRowCount { get; set; }
    public List<PartitionRange> Partitions { get; set; } = new();
    public string? PrimaryKeyColumn { get; set; }
    public bool IsNumericPrimaryKey { get; set; }
}
