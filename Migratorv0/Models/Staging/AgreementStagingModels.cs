namespace MigrationWeb.Models.Staging;

public sealed class AgreementStagingLoadRequest
{
    public string OracleConnectionString { get; set; } = "";
    public string StagingSchema { get; set; } = "SMS_AUDIT";
    public long AgreementId { get; set; }
}

public sealed class AgreementStagingSummary
{
    public long AgreementId { get; set; }
    public int AccountCount { get; set; }
    public int InvoiceCount { get; set; }
    public int InvLinesCount { get; set; }
    public int PayTransCount { get; set; }
    public int PayTransIncomeCount { get; set; }
    public int SpeFeeCount { get; set; }
    public int AdvanceLedgerCount { get; set; }
    public int InstallmentPlanCount { get; set; }
    public int ReconCount { get; set; }
    public decimal InvoiceGrandTotal { get; set; }
    public decimal AccruePayableTotal { get; set; }
    public decimal AccruePaidTotal { get; set; }
    public decimal PaymentTotal { get; set; }
    public decimal SpeFeeTotal { get; set; }
    public decimal LedgerAmountTotal { get; set; }
    public decimal LedgerCreditNet { get; set; }
    public int TahakkukCount { get; set; }
    public int PaidTahakkukCount { get; set; }
    public int OpenDebtCount { get; set; }
    public decimal TotalDebtBalance { get; set; }
    public bool HasInvoiceDebt { get; set; }
    public AgreementAbysSummary? Abys { get; set; }
}

/// <summary>ABYS kaynak (CS_ACCOUNT) metrikleri — panel kıyası için.</summary>
public sealed class AgreementAbysSummary
{
    public int FaturaAdet { get; set; }
    public int OdenmisFaturaAdet { get; set; }
    public int GecikmisBorcAdet { get; set; }
    public decimal ToplamBorc { get; set; }
    public decimal DepozitoTutar { get; set; }
    public decimal EmanetTutar { get; set; }
}

public sealed class AgreementStagingPayload
{
    public AgreementStagingSummary Summary { get; set; } = new();
    public List<Dictionary<string, object?>> Invoices { get; set; } = [];
    public List<Dictionary<string, object?>> InvLines { get; set; } = [];
    public List<Dictionary<string, object?>> PayTrans { get; set; } = [];
    public List<Dictionary<string, object?>> PayTransIncome { get; set; } = [];
    public List<Dictionary<string, object?>> SpeFee { get; set; } = [];
    public List<Dictionary<string, object?>> AdvanceLedger { get; set; } = [];
    public List<Dictionary<string, object?>> AdvanceLedgerIncome { get; set; } = [];
    public List<Dictionary<string, object?>> InstallmentPlan { get; set; } = [];
    public List<Dictionary<string, object?>> MahsupPool { get; set; } = [];
    public List<Dictionary<string, object?>> ReconDiff { get; set; } = [];
    public List<string> Warnings { get; set; } = [];
}
