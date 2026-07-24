namespace MigrationShared.Models;

public class ValidationResult
{
    public string TableName { get; set; } = string.Empty;
    public long OracleCount { get; set; }
    public long MssqlCount { get; set; }
    public bool CountMatch => OracleCount == MssqlCount;
    public long? OracleChecksum { get; set; }
    public long? MssqlChecksum { get; set; }
    public bool ChecksumMatch => OracleChecksum == MssqlChecksum;

    /// <summary>Per-gate outcomes (RowCount, PK aggregates, etc.).</summary>
    public List<ValidationGateResult> Gates { get; set; } = new();

    public bool AllGatesPassed => Gates.Count == 0 ? CountMatch : Gates.All(g => g.Passed);

    public string? ErrorMessage { get; set; }
}
