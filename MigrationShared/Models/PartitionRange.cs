namespace MigrationShared.Models;

public class PartitionRange
{
    public int PartitionNumber { get; set; }
    public string? StartRowId { get; set; }
    public string? EndRowId { get; set; }
    /// <summary>
    /// When true, ROWID extract uses &lt;= EndRowId (last partition).
    /// Other partitions keep exclusive &lt; EndRowId to avoid double-counting boundaries.
    /// </summary>
    public bool EndRowIdInclusive { get; set; }
    public long? StartPkValue { get; set; }
    public long? EndPkValue { get; set; }
    public string PartitionKey => $"{PartitionNumber}";
}
