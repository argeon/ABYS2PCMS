namespace MigrationShared.Models;

public enum ValidationMode
{
    /// <summary>Row count plus all applicable PK/data gates (subject to row thresholds).</summary>
    Strict = 0,

    /// <summary>Row count plus PK gates when row count is below ValidationMaxRowsForExtendedGates.</summary>
    Balanced = 1,

    /// <summary>Oracle vs MSSQL row counts only.</summary>
    CountOnly = 2
}

public enum ValidationGateKind
{
    RowCount,
    SumIntegerPk,
    SumDecimalPk,
    PkMinMaxString,
    PkMinMaxDateTime
}

public class ValidationGateResult
{
    public string GateType { get; set; } = string.Empty;
    public bool Passed { get; set; }
    public string? OracleValue { get; set; }
    public string? MssqlValue { get; set; }
    public string? Detail { get; set; }
}

public class ValidationGateRecord
{
    public int Id { get; set; }
    public int RunId { get; set; }
    public string TableName { get; set; } = string.Empty;
    public string GateType { get; set; } = string.Empty;
    public string Phase { get; set; } = "Final";
    public bool Passed { get; set; }
    public string? OracleValue { get; set; }
    public string? MssqlValue { get; set; }
    public string? Message { get; set; }
    public DateTime EvaluatedAt { get; set; }
}
