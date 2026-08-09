namespace MigrationWeb.Models.Staging;

public sealed class AgreementTahsilatRequest
{
    public string OracleConnectionString { get; set; } = "";
    public string MssqlConnectionString { get; set; } = "";
    public long AgreementId { get; set; }
    public string MigrationSchema { get; set; } = "";
    /// <summary>SMS canlı tablolar şeması. Boş = Oracle bağlantı kullanıcısı.</summary>
    public string SmsSchema { get; set; } = "";
    public string EnergyNr { get; set; } = "005";
    public string EnergyPeriod { get; set; } = "01";
    public string? RunId { get; set; }
    public bool DryRun { get; set; } = true;
    public bool IncludeCloseEps { get; set; } = true;
    /// <summary>Pilot ENERGY zinciri APPLY öncesi AGR fatura zincirini temizle (569).</summary>
    public bool CleanBeforePilot { get; set; } = true;
}

public enum TahsilatSide
{
    SMS,
    ENERGY,
    BOTH
}

public enum TahsilatOp
{
    READ,
    DRY_RUN,
    APPLY,
    COMPARE,
    TEST,
    INFO
}

public sealed class TahsilatLogEvent
{
    public string RunId { get; set; } = "";
    public long AgrId { get; set; }
    public string Step { get; set; } = "";
    public string Side { get; set; } = "";
    public string Op { get; set; } = "";
    public long ElapsedMs { get; set; }
    public int? RowCount { get; set; }
    public string Outcome { get; set; } = "OK";
    public string Detail { get; set; } = "";
    public DateTime AtUtc { get; set; } = DateTime.UtcNow;
}

public sealed class TahsilatGapItem
{
    public string Code { get; set; } = "";
    public string Severity { get; set; } = "WARN";
    public string Message { get; set; } = "";
    public string? Side { get; set; }
}

public sealed class TahsilatStepDef
{
    public string Id { get; set; } = "";
    public int Ordinal { get; set; }
    public string Title { get; set; } = "";
    public string Explanation { get; set; } = "";
    public bool WritesEnergy { get; set; }
}

public sealed class TahsilatStepResult
{
    public string StepId { get; set; } = "";
    public bool Ok { get; set; }
    public string Message { get; set; } = "";
    public string RunId { get; set; } = "";
    public List<TahsilatLogEvent> Logs { get; set; } = [];
    public List<TahsilatGapItem> Gaps { get; set; } = [];
    public Dictionary<string, object?> Summary { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public List<Dictionary<string, object?>> Rows { get; set; } = [];
    public List<Dictionary<string, object?>> EnergyRows { get; set; } = [];
}

public sealed class TahsilatCatalogResponse
{
    public List<TahsilatStepDef> Steps { get; set; } = [];
}
