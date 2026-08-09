using System.Data;
using System.Diagnostics;
using System.Text;
using MigrationWeb.Models.Staging;
using Microsoft.Data.SqlClient;

namespace MigrationWeb.Services.Staging;

public sealed class AgreementEnergyWriteService
{
    private readonly ILogger<AgreementEnergyWriteService> _logger;

    public AgreementEnergyWriteService(ILogger<AgreementEnergyWriteService> logger) => _logger = logger;

    public string TablePrefix(AgreementTahsilatRequest req)
    {
        var nr = (req.EnergyNr ?? "005").Trim().PadLeft(3, '0');
        var period = (req.EnergyPeriod ?? "01").Trim().PadLeft(2, '0');
        return $"LS_{nr}_{period}";
    }

    public async Task<(bool Ok, string Message)> TestAsync(string cs, CancellationToken ct)
    {
        try
        {
            await using var conn = new SqlConnection(cs);
            await conn.OpenAsync(ct);
            await using var cmd = new SqlCommand("SELECT 1", conn);
            await cmd.ExecuteScalarAsync(ct);
            return (true, "ENERGY (MSSQL) bağlantı OK.");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "ENERGY MSSQL test failed");
            return (false, ex.Message);
        }
    }

    /// <summary>
    /// scenario: mahsup | taksit | tamEksilten | kismiEksilten — ENERGY tarafı spot okuma.
    /// </summary>
    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadScenarioSpotAsync(AgreementTahsilatRequest req, string runId, string scenario, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var prefix = TablePrefix(req);
        var inv = $"dbo.{prefix}_INVOICE";
        var pt = $"dbo.{prefix}_PAYTRANS";

        await using var conn = new SqlConnection(req.MssqlConnectionString);
        await conn.OpenAsync(ct);

        if (!await TableExistsAsync(conn, "dbo", $"{prefix}_INVOICE", ct))
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_ENERGY_INVOICE",
                Severity = "CRITICAL",
                Side = "ENERGY",
                Message = $"{inv} yok."
            });
            sw.Stop();
            return ([], gaps, MakeLog(runId, req.AgreementId, scenario, "ENERGY", "READ",
                sw.ElapsedMilliseconds, 0, "FAIL", "invoice missing"));
        }

        string sql = scenario switch
        {
            "mahsup" => $@"
SELECT TOP 300 inv.LREF, inv.OWNERREF, inv.FICHENO, inv.EXPLAIN, inv.CLOSED, inv.PAYABLETOTAL,
       pt.LREF AS PT_LREF, pt.PAYABLETOTAL AS PT_PAYABLE, pt.PAID, pt.PAYTYPE, pt.IOCODE
FROM {inv} inv WITH (NOLOCK)
LEFT JOIN {pt} pt WITH (NOLOCK)
  ON pt.INVOICEREF = inv.LREF AND ISNULL(pt.CANCELED,0)=0
WHERE inv.OWNERREF = @agrId AND ISNULL(inv.CANCELED,0)=0
  AND (
    UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%MAHSUP%'
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%MAHŞUP%'
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%EMANET%'
    OR ISNULL(pt.PAYTYPE,0) IN (6, 24, 12)
  )
ORDER BY inv.LREF DESC",
            "taksit" => "", // Dinamik SQL, aşağıda set edilecek
            "tamEksilten" => BuildTamEksiltenSql(inv, hasInvoiceCrossRef: true, hasReturnCols: true),
            "iptalEmanet" => $@"
SELECT TOP 300 inv.LREF, inv.OWNERREF, inv.FICHENO, inv.EXPLAIN, inv.CLOSED, inv.CANCELED, inv.PAYABLETOTAL,
       pt.LREF AS PT_LREF, pt.PAYABLETOTAL AS PT_PAYABLE, pt.PAID, pt.CANCELED AS PT_CANCELED,
       pt.CANCELLATIONPAYMENT, pt.PAYTYPE, pt.IOCODE
FROM {inv} inv WITH (NOLOCK)
LEFT JOIN {pt} pt WITH (NOLOCK)
  ON pt.INVOICEREF = inv.LREF
WHERE inv.OWNERREF = @agrId
  AND (
    ISNULL(inv.CANCELED,0)=1
    OR ISNULL(pt.CANCELED,0)=1
    OR ISNULL(pt.CANCELLATIONPAYMENT,0)=1
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%EMANET%'
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%IPTAL%'
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%İPTAL%'
    OR UPPER(ISNULL(inv.FICHENO,'')) LIKE 'I%'
  )
ORDER BY inv.LREF DESC",
            "kismiEksilten" => $@"
SELECT TOP 300 inv.LREF, inv.OWNERREF, inv.FICHENO, inv.EXPLAIN, inv.CLOSED, inv.PAYABLETOTAL, inv.TYPE
FROM {inv} inv WITH (NOLOCK)
WHERE inv.OWNERREF = @agrId AND ISNULL(inv.CANCELED,0)=0
  AND (
    UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%KISMI EKS%'
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%KISMİ EKS%'
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%KISMI EKSILTEN%'
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%PARTIAL%'
  )
ORDER BY inv.LREF DESC",
            _ => throw new ArgumentException($"Unknown scenario: {scenario}")
        };

        // tamEksilten: şemada olmayan kolonları (INVOICECROSSREF / RETURN_*) düş
        if (scenario == "tamEksilten")
        {
            var hasCross = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "INVOICECROSSREF", ct);
            var hasRetSrc = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "RETURN_SOURCE_INVREF", ct);
            var hasRetTgt = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "RETURN_TARGET_INVREF", ct);
            var hasReturn = hasRetSrc && hasRetTgt;
            sql = BuildTamEksiltenSql(inv, hasCross, hasReturn);
            if (!hasCross || !hasReturn)
                gaps.Add(new TahsilatGapItem
                {
                    Code = "ENERGY_TAM_EKS_COLS",
                    Severity = "INFO",
                    Side = "ENERGY",
                    Message = $"Tam eksilten kolonlar kısmi: INVOICECROSSREF={(hasCross ? "var" : "yok")}, RETURN_*={(hasReturn ? "var" : "yok")} — EXPLAIN/FICHENO ile."
                });
        }
        else if (scenario == "taksit")
        {
            var hasCancelPay = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "CANCELLATIONPAYMENT", ct);
            var hasPaymentDate = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "PAYMENTDATE", ct);
            var hasLastPaid = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "LASTPAIDDATE", ct);
            var hasInvLastPaid = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "LASTPAIDDATE", ct);
            var hasAbysAcc = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "ABYS_ACCOUNT_ID", ct);
            var hasExplain = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "EXPLAIN", ct);
            var hasInstNr = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "INST_NR", ct);

            var cancelPaySel = hasCancelPay ? ", pt.CANCELLATIONPAYMENT" : ", CAST(NULL AS INT) AS CANCELLATIONPAYMENT";
            var paymentDateSel = hasPaymentDate
                ? ", pt.PAYMENTDATE AS SON_ODEME_TARIH"
                : hasLastPaid
                    ? ", pt.LASTPAIDDATE AS SON_ODEME_TARIH"
                    : hasInvLastPaid
                        ? ", inv.LASTPAIDDATE AS SON_ODEME_TARIH"
                        : ", CAST(NULL AS DATETIME) AS SON_ODEME_TARIH";
            var faturaIdSel = hasAbysAcc ? "inv.ABYS_ACCOUNT_ID AS FATURAID" : "CAST(NULL AS BIGINT) AS FATURAID";
            var explainSel = hasExplain ? "LEFT(inv.EXPLAIN, 100) AS EXPLAIN" : "CAST(NULL AS NVARCHAR(100)) AS EXPLAIN";
            var instNrSel = hasInstNr ? "pt.INST_NR AS TAKSIT_NO" : "CAST(NULL AS INT) AS TAKSIT_NO";
            var hasPlanRef = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "INSTALLMENT_PLAN_REF", ct);
            var explainPred = hasExplain ? "UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%TAKSIT%'" : "1=0";
            var instNrPred = hasInstNr ? "ISNULL(pt.INST_NR,0) > 0" : "1=0";
            var planRefPred = hasPlanRef ? "ISNULL(inv.INSTALLMENT_PLAN_REF,0) > 0" : "1=0";
            var tespitTipi = hasExplain && hasInstNr
                ? @"CASE
        WHEN ISNULL(pt.INST_NR,0) > 0 THEN 'INST_NR'
        WHEN UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%TAKSIT%' THEN 'EXPLAIN'
        WHEN ISNULL(inv.INSTALLMENT_PLAN_REF,0) > 0 THEN 'PLAN_REF'
        ELSE 'MANUAL'
    END"
                : hasInstNr
                    ? "CASE WHEN ISNULL(pt.INST_NR,0) > 0 THEN 'INST_NR' ELSE 'MANUAL' END"
                    : hasExplain
                        ? "CASE WHEN UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%TAKSIT%' THEN 'EXPLAIN' ELSE 'MANUAL' END"
                        : "'MANUAL'";
            var planRefSel = hasPlanRef ? "inv.INSTALLMENT_PLAN_REF" : "CAST(NULL AS INT) AS INSTALLMENT_PLAN_REF";

            sql = $@"
SELECT TOP 500 
    inv.LREF,
    inv.OWNERREF,
    {faturaIdSel},
    inv.FICHENO,
    {explainSel},
    {planRefSel},
    inv.CLOSED,
    inv.CANCELED,
    inv.PAYABLETOTAL,
    inv.DATE_ AS FATURA_TARIH,
    pt.LREF AS PT_LREF,
    {instNrSel},
    pt.PAYABLETOTAL AS PT_PAYABLE,
    pt.PAID AS PT_PAID,
    pt.CANCELED AS PT_CANCELED
    {cancelPaySel}
    {paymentDateSel},
    pt.PAYTYPE,
    CASE
        WHEN ISNULL(inv.CANCELED,0) = 1 OR ISNULL(pt.CANCELED,0) = 1 THEN 'IPTAL'
        WHEN ISNULL(inv.CLOSED,0) = 1 AND ISNULL(pt.PAID,0) >= ISNULL(pt.PAYABLETOTAL,0) THEN 'KAPALI'
        WHEN ISNULL(pt.PAID,0) > 0 AND ISNULL(pt.PAID,0) < ISNULL(pt.PAYABLETOTAL,0) THEN 'KISMI_ODEME'
        WHEN ISNULL(pt.PAID,0) = 0 THEN 'ACIK'
        ELSE 'DIGER'
    END AS EN_TAKSIT_DURUMU,
    {tespitTipi} AS TESPIT_TIPI
FROM {inv} inv WITH (NOLOCK)
LEFT JOIN {pt} pt WITH (NOLOCK)
    ON pt.INVOICEREF = inv.LREF 
   AND ISNULL(pt.CANCELED,0) = 0
   AND ({(hasInstNr ? "ISNULL(pt.INST_NR,0) > 0" : "1=1")})
WHERE inv.OWNERREF = @agrId
  AND (
    {explainPred}
    OR {instNrPred}
    OR {planRefPred}
  )
ORDER BY {(hasInstNr ? "pt.INST_NR, " : "")}inv.LREF DESC";
        }
        else if (scenario == "iptalEmanet")
        {
            var hasCancelPay = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "CANCELLATIONPAYMENT", ct);
            var cancelPaySel = hasCancelPay ? ", pt.CANCELLATIONPAYMENT" : "";
            var cancelPayWhere = hasCancelPay ? " OR ISNULL(pt.CANCELLATIONPAYMENT,0)=1" : "";
            sql = $@"
SELECT TOP 300 inv.LREF, inv.OWNERREF, inv.FICHENO, inv.EXPLAIN, inv.CLOSED, inv.CANCELED, inv.PAYABLETOTAL,
       pt.LREF AS PT_LREF, pt.PAYABLETOTAL AS PT_PAYABLE, pt.PAID, pt.CANCELED AS PT_CANCELED
       {cancelPaySel}, pt.PAYTYPE, pt.IOCODE
FROM {inv} inv WITH (NOLOCK)
LEFT JOIN {pt} pt WITH (NOLOCK)
  ON pt.INVOICEREF = inv.LREF
WHERE inv.OWNERREF = @agrId
  AND (
    ISNULL(inv.CANCELED,0)=1
    OR ISNULL(pt.CANCELED,0)=1
    {cancelPayWhere}
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%EMANET%'
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%IPTAL%'
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%İPTAL%'
    OR UPPER(ISNULL(inv.FICHENO,'')) LIKE 'I%'
  )
ORDER BY inv.LREF DESC";
        }

        List<Dictionary<string, object?>> rows;
        try
        {
            rows = await QueryAsync(conn, sql, req.AgreementId, ct);
        }
        catch (SqlException ex) when (scenario is "iptalEmanet" &&
            (ex.Message.Contains("CANCELLATIONPAYMENT", StringComparison.OrdinalIgnoreCase)
             || ex.Message.Contains("Invalid column", StringComparison.OrdinalIgnoreCase)))
        {
            rows = await QueryAsync(conn, $@"
SELECT TOP 300 inv.LREF, inv.OWNERREF, inv.FICHENO, inv.EXPLAIN, inv.CLOSED, inv.CANCELED, inv.PAYABLETOTAL,
       pt.LREF AS PT_LREF, pt.PAYABLETOTAL AS PT_PAYABLE, pt.PAID, pt.CANCELED AS PT_CANCELED
FROM {inv} inv WITH (NOLOCK)
LEFT JOIN {pt} pt WITH (NOLOCK) ON pt.INVOICEREF = inv.LREF
WHERE inv.OWNERREF = @agrId
  AND (
    ISNULL(inv.CANCELED,0)=1 OR ISNULL(pt.CANCELED,0)=1
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%EMANET%'
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%IPTAL%'
    OR UPPER(ISNULL(inv.FICHENO,'')) LIKE 'I%'
  )
ORDER BY inv.LREF DESC", req.AgreementId, ct);
            gaps.Add(new TahsilatGapItem
            {
                Code = "ENERGY_IPTAL_COLS",
                Severity = "INFO",
                Side = "ENERGY",
                Message = "CANCELLATIONPAYMENT yok — iptal spot CANCELED/EXPLAIN ile."
            });
        }
        catch (SqlException ex) when (scenario is "tamEksilten" &&
            (ex.Message.Contains("INVOICECROSSREF", StringComparison.OrdinalIgnoreCase)
             || ex.Message.Contains("RETURN_", StringComparison.OrdinalIgnoreCase)))
        {
            rows = await QueryAsync(conn, BuildTamEksiltenSql(inv, hasInvoiceCrossRef: false, hasReturnCols: false),
                req.AgreementId, ct);
            gaps.Add(new TahsilatGapItem
            {
                Code = "ENERGY_NO_RETURN_COLS",
                Severity = "INFO",
                Side = "ENERGY",
                Message = "IADE kolonları yok/hatalı — spot EXPLAIN/FICHENO ile."
            });
        }

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, scenario, "ENERGY", "READ", sw.ElapsedMilliseconds,
            rows.Count, "OK", $"scenario={scenario} rows={rows.Count} prefix={prefix}");
        return (rows, gaps, log);
    }

    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadInvoicesByOwnerAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var prefix = TablePrefix(req);
        var inv = $"dbo.{prefix}_INVOICE";
        var pt = $"dbo.{prefix}_PAYTRANS";

        await using var conn = new SqlConnection(req.MssqlConnectionString);
        await conn.OpenAsync(ct);

        if (!await TableExistsAsync(conn, "dbo", $"{prefix}_INVOICE", ct))
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_ENERGY_INVOICE",
                Severity = "CRITICAL",
                Side = "ENERGY",
                Message = $"energy.{inv} yok."
            });
            sw.Stop();
            return ([], gaps, MakeLog(runId, req.AgreementId, "energyInvoices", "ENERGY", "READ",
                sw.ElapsedMilliseconds, 0, "FAIL", $"{inv} missing"));
        }

        var rows = await QueryAsync(conn, $@"
SELECT TOP 500
  inv.LREF, inv.OWNERREF, inv.CLOSED, inv.LASTPAIDDATE, inv.PAYABLETOTAL, inv.CANCELED,
  pt.LREF AS PT_LREF, pt.PAYABLETOTAL AS PT_PAYABLE, pt.PAID AS PT_PAID, pt.IOCODE
FROM {inv} inv WITH (NOLOCK)
LEFT JOIN {pt} pt WITH (NOLOCK)
  ON pt.INVOICEREF = inv.LREF AND ISNULL(pt.IOCODE,0)=0 AND ISNULL(pt.CANCELED,0)=0
WHERE inv.OWNERREF = @agrId AND ISNULL(inv.CANCELED,0)=0
ORDER BY inv.LREF DESC", req.AgreementId, ct);

        sw.Stop();
        var open = rows.Count(r => Convert.ToInt32(r.GetValueOrDefault("CLOSED") ?? 0) == 0);
        var log = MakeLog(runId, req.AgreementId, "energyInvoices", "ENERGY", "READ",
            sw.ElapsedMilliseconds, rows.Count, "OK",
            $"table={prefix} rows={rows.Count} open_closed0={open}");
        return (rows, gaps, log);
    }

    /// <summary>
    /// ENERGY açık borç — hesap grain (FATURAID = ABYS_ACCOUNT_ID).
    /// EN_BAL = Σ(PAYABLETOTAL − PAID) borç PT (IOCODE=0); CLOSED=0 satırlar da dahil.
    /// </summary>
    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadOpenDebtByAccountAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var prefix = TablePrefix(req);
        var invName = $"{prefix}_INVOICE";
        var ptName = $"{prefix}_PAYTRANS";
        var inv = $"dbo.{invName}";
        var pt = $"dbo.{ptName}";

        await using var conn = new SqlConnection(req.MssqlConnectionString);
        await conn.OpenAsync(ct);

        if (!await TableExistsAsync(conn, "dbo", invName, ct))
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_ENERGY_INVOICE",
                Severity = "CRITICAL",
                Side = "ENERGY",
                Message = $"energy.{inv} yok."
            });
            sw.Stop();
            return ([], gaps, MakeLog(runId, req.AgreementId, "frkEnOpen", "ENERGY", "READ",
                sw.ElapsedMilliseconds, 0, "FAIL", "invoice missing"));
        }

        if (!await ColumnExistsAsync(conn, "dbo", invName, "ABYS_ACCOUNT_ID", ct))
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_ABYS_ACCOUNT_ID",
                Severity = "WARN",
                Side = "ENERGY",
                Message = $"{inv}.ABYS_ACCOUNT_ID yok — FRK grain düştü; CLOSED=0 sayım fallback."
            });
            var fallback = await QueryAsync(conn, $@"
SELECT TOP 2000
  inv.LREF AS FATURAID, inv.OWNERREF AS SOZLESME,
  CONVERT(DECIMAL(18,2), inv.PAYABLETOTAL) AS EN_BAL,
  ISNULL(inv.CLOSED,0) AS CLOSED, CAST(1 AS INT) AS OPEN_INV_CNT
FROM {inv} inv WITH (NOLOCK)
WHERE inv.OWNERREF = @agrId AND ISNULL(inv.CANCELED,0)=0 AND ISNULL(inv.CLOSED,0)=0
ORDER BY inv.LREF DESC", req.AgreementId, ct);
            sw.Stop();
            return (fallback, gaps, MakeLog(runId, req.AgreementId, "frkEnOpen", "ENERGY", "READ",
                sw.ElapsedMilliseconds, fallback.Count, "WARN", "no ABYS_ACCOUNT_ID"));
        }

        var hasCancelPay = await ColumnExistsAsync(conn, "dbo", ptName, "CANCELLATIONPAYMENT", ct);
        var cancelPayExpr = hasCancelPay
            ? "ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0"
            : "1=1";

        var rows = await QueryAsync(conn, $@"
SELECT
  inv.ABYS_ACCOUNT_ID AS FATURAID,
  MAX(inv.OWNERREF) AS SOZLESME,
  CONVERT(DECIMAL(18,2), SUM(
    CASE
      WHEN ISNULL(pt.CANCELED, 0) = 0 AND {cancelPayExpr}
      THEN CONVERT(DECIMAL(18,2), pt.PAYABLETOTAL)
         - CONVERT(DECIMAL(18,2), ISNULL(pt.PAID, 0))
      ELSE 0
    END
  )) AS EN_BAL,
  SUM(CASE WHEN ISNULL(inv.CLOSED, 0) = 0 THEN 1 ELSE 0 END) AS OPEN_INV_CNT,
  MAX(CASE WHEN ISNULL(inv.CLOSED, 0) = 0 THEN 1 ELSE 0 END) AS HAS_CLOSED0
FROM {inv} inv WITH (NOLOCK)
INNER JOIN {pt} pt WITH (NOLOCK)
  ON pt.INVOICEREF = inv.LREF AND ISNULL(pt.IOCODE, 0) = 0
WHERE inv.OWNERREF = @agrId
  AND inv.ABYS_ACCOUNT_ID IS NOT NULL
  AND ISNULL(inv.IOCODE, 0) = 0
  AND ISNULL(inv.CANCELED, 0) = 0
GROUP BY inv.ABYS_ACCOUNT_ID
HAVING CONVERT(DECIMAL(18,2), SUM(
    CASE
      WHEN ISNULL(pt.CANCELED, 0) = 0 AND {cancelPayExpr}
      THEN CONVERT(DECIMAL(18,2), pt.PAYABLETOTAL)
         - CONVERT(DECIMAL(18,2), ISNULL(pt.PAID, 0))
      ELSE 0
    END
  )) > 0.02
   OR MAX(CASE WHEN ISNULL(inv.CLOSED, 0) = 0 THEN 1 ELSE 0 END) = 1
ORDER BY EN_BAL DESC", req.AgreementId, ct);

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, "frkEnOpen", "ENERGY", "READ",
            sw.ElapsedMilliseconds, rows.Count, "OK",
            $"prefix={prefix} open_accounts={rows.Count}");
        return (rows, gaps, log);
    }

    private static async Task<bool> ColumnExistsAsync(
        SqlConnection conn, string schema, string table, string column, CancellationToken ct)
    {
        await using var cmd = new SqlCommand(@"
SELECT 1
  FROM sys.columns c
  JOIN sys.tables t ON t.object_id = c.object_id
  JOIN sys.schemas s ON s.schema_id = t.schema_id
 WHERE s.name = @s AND t.name = @t AND c.name = @c", conn);
        cmd.Parameters.AddWithValue("@s", schema);
        cmd.Parameters.AddWithValue("@t", table);
        cmd.Parameters.AddWithValue("@c", column);
        return await cmd.ExecuteScalarAsync(ct) != null;
    }

    /// <summary>
    /// Kapama: CLOSE_* aday MAIN_LREF listesi ile PAID/CLOSED/LPD.
    /// DRY_RUN=true ise sadece sayım.
    /// </summary>
    public async Task<(Dictionary<string, object?> Summary, List<Dictionary<string, object?>> Preview,
            List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        ApplyCloseAsync(
            AgreementTahsilatRequest req,
            string runId,
            IReadOnlyList<Dictionary<string, object?>> closeCandidates,
            CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var prefix = TablePrefix(req);
        var invTable = $"dbo.{prefix}_INVOICE";
        var ptTable = $"dbo.{prefix}_PAYTRANS";
        var op = req.DryRun ? "DRY_RUN" : "APPLY";

        var wantClose = closeCandidates
            .Where(r =>
            {
                var kind = Convert.ToString(r.GetValueOrDefault("FIX_KIND")) ?? "";
                if (kind == "CLOSE_FULL") return true;
                if (kind == "CLOSE_EPS" && req.IncludeCloseEps) return true;
                return false;
            })
            .Where(r => Convert.ToInt32(r.GetValueOrDefault("WANT_CLOSED") ?? 0) == 1)
            .ToList();

        if (wantClose.Count == 0)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_APPLY_CANDIDATES",
                Severity = "WARN",
                Side = "ENERGY",
                Message = "CLOSE_FULL/EPS adayı yok — APPLY atlandı."
            });
            sw.Stop();
            return (new Dictionary<string, object?> { ["candidateCount"] = 0 }, [], gaps,
                MakeLog(runId, req.AgreementId, "applyClose", "ENERGY", op, sw.ElapsedMilliseconds,
                    0, "SKIP", "no CLOSE_* candidates"));
        }

        await using var conn = new SqlConnection(req.MssqlConnectionString);
        await conn.OpenAsync(ct);

        if (!await TableExistsAsync(conn, "dbo", $"{prefix}_INVOICE", ct) ||
            !await TableExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", ct))
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_ENERGY_TABLES",
                Severity = "CRITICAL",
                Side = "ENERGY",
                Message = $"{prefix}_INVOICE / PAYTRANS yok."
            });
            sw.Stop();
            return (new Dictionary<string, object?>(), [], gaps,
                MakeLog(runId, req.AgreementId, "applyClose", "ENERGY", op, sw.ElapsedMilliseconds,
                    0, "FAIL", "target tables missing"));
        }

        await using (var create = new SqlCommand(@"
IF OBJECT_ID('tempdb..#AGR_CLOSE') IS NOT NULL DROP TABLE #AGR_CLOSE;
CREATE TABLE #AGR_CLOSE (
  MAIN_LREF INT NOT NULL PRIMARY KEY,
  FIX_KIND VARCHAR(16) NOT NULL,
  WANT_LPD DATETIME2(3) NULL,
  PAYABLE_AMT DECIMAL(18,2) NULL,
  OV_PAID_AMT DECIMAL(18,2) NULL
);", conn))
        {
            await create.ExecuteNonQueryAsync(ct);
        }

        var inserted = 0;
        foreach (var batch in wantClose.Chunk(200))
        {
            var sb = new StringBuilder();
            sb.Append("INSERT INTO #AGR_CLOSE (MAIN_LREF, FIX_KIND, WANT_LPD, PAYABLE_AMT, OV_PAID_AMT) VALUES ");
            var first = true;
            var cmd = new SqlCommand { Connection = conn };
            var i = 0;
            foreach (var r in batch)
            {
                var main = ToInt(r, "MAIN_LREF");
                if (main <= 0) continue;
                if (!first) sb.Append(',');
                first = false;
                sb.Append($"(@m{i}, @k{i}, @d{i}, @p{i}, @o{i})");
                cmd.Parameters.AddWithValue($"@m{i}", main);
                var kind = Convert.ToString(r.GetValueOrDefault("FIX_KIND")) ?? "CLOSE_FULL";
                if (kind.Length > 16) kind = kind[..16];
                cmd.Parameters.AddWithValue($"@k{i}", kind);
                var lpd = r.GetValueOrDefault("WANT_LPD");
                cmd.Parameters.AddWithValue($"@d{i}", ParseDate(lpd) ?? (object)DBNull.Value);
                cmd.Parameters.AddWithValue($"@p{i}", ToDec(r, "PAYABLE_AMT") ?? (object)DBNull.Value);
                cmd.Parameters.AddWithValue($"@o{i}", ToDec(r, "OV_PAID_AMT") ?? (object)DBNull.Value);
                i++;
                inserted++;
            }
            if (i == 0) continue;
            cmd.CommandText = sb.ToString();
            await cmd.ExecuteNonQueryAsync(ct);
            await cmd.DisposeAsync();
        }

        var preview = await QueryAsync(conn, $@"
SELECT TOP 200
  c.MAIN_LREF, c.FIX_KIND, c.WANT_LPD, c.PAYABLE_AMT, c.OV_PAID_AMT,
  inv.CLOSED AS EN_CLOSED, inv.LASTPAIDDATE AS EN_LPD, inv.OWNERREF,
  pt.LREF AS PT_LREF, pt.PAYABLETOTAL AS PT_PAYABLE, pt.PAID AS PT_PAID,
  CASE WHEN ABS(CONVERT(DECIMAL(18,2), ISNULL(pt.PAID,0)) - CONVERT(DECIMAL(18,2), pt.PAYABLETOTAL)) > 0.01
       THEN 1 ELSE 0 END AS PT_NEED_UPDATE,
  CASE WHEN ISNULL(inv.CLOSED,0)=0 THEN 1 ELSE 0 END AS INV_NEED_CLOSED
FROM #AGR_CLOSE c
LEFT JOIN {invTable} inv WITH (NOLOCK) ON inv.LREF = c.MAIN_LREF
LEFT JOIN {ptTable} pt WITH (NOLOCK)
  ON pt.INVOICEREF = c.MAIN_LREF AND ISNULL(pt.IOCODE,0)=0 AND ISNULL(pt.CANCELED,0)=0
ORDER BY c.MAIN_LREF", req.AgreementId, ct);

        // LEFT JOIN invoice miss: OWNERREF and EN_CLOSED both null (inv row absent)
        var notInEnergy = preview.Count(r =>
            r.GetValueOrDefault("OWNERREF") == null && r.GetValueOrDefault("EN_CLOSED") == null);

        var ptNeed = preview.Count(r => Convert.ToInt32(r.GetValueOrDefault("PT_NEED_UPDATE") ?? 0) == 1);
        var invNeed = preview.Count(r => Convert.ToInt32(r.GetValueOrDefault("INV_NEED_CLOSED") ?? 0) == 1);

        if (notInEnergy > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "STG_NOT_IN_ENERGY",
                Severity = "CRITICAL",
                Side = "BOTH",
                Message = $"{notInEnergy} CLOSE adayı ENERGY invoice/paytrans'ta yok (MAIN_LREF eşleşmedi)."
            });

        var summary = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase)
        {
            ["candidateCount"] = inserted,
            ["previewCount"] = preview.Count,
            ["ptNeedUpdate"] = ptNeed,
            ["invNeedClosed"] = invNeed,
            ["notInEnergy"] = notInEnergy,
            ["dryRun"] = req.DryRun,
            ["tablePrefix"] = prefix
        };

        if (req.DryRun)
        {
            sw.Stop();
            return (summary, preview, gaps,
                MakeLog(runId, req.AgreementId, "applyClose", "ENERGY", "DRY_RUN", sw.ElapsedMilliseconds,
                    preview.Count, gaps.Any(g => g.Severity == "CRITICAL") ? "WARN" : "OK",
                    $"candidates={inserted} ptNeed={ptNeed} invNeed={invNeed} missing={notInEnergy}"));
        }

        // APPLY
        int ptUpdated;
        await using (var updPt = new SqlCommand($@"
UPDATE pt SET pt.PAID = pt.PAYABLETOTAL
FROM {ptTable} pt
INNER JOIN #AGR_CLOSE c ON c.MAIN_LREF = pt.INVOICEREF
WHERE ISNULL(pt.IOCODE,0)=0 AND ISNULL(pt.CANCELED,0)=0
  AND ABS(CONVERT(DECIMAL(18,2), ISNULL(pt.PAID,0)) - CONVERT(DECIMAL(18,2), pt.PAYABLETOTAL)) > 0.01;", conn))
        {
            ptUpdated = await updPt.ExecuteNonQueryAsync(ct);
        }

        int invUpdated;
        await using (var updInv = new SqlCommand($@"
UPDATE inv SET
  inv.CLOSED = 1,
  inv.LASTPAIDDATE = COALESCE(
      CASE WHEN c.WANT_LPD IS NOT NULL AND c.WANT_LPD >= '1900-01-01' AND c.WANT_LPD < '2079-06-07'
           THEN CONVERT(DATETIME, c.WANT_LPD) END,
      inv.LASTPAIDDATE,
      CASE WHEN GETDATE() >= '1900-01-01' AND GETDATE() < '2079-06-07' THEN GETDATE() END)
FROM {invTable} inv
INNER JOIN #AGR_CLOSE c ON c.MAIN_LREF = inv.LREF
WHERE ISNULL(inv.CLOSED,0)=0
   OR (inv.LASTPAIDDATE IS NULL AND c.WANT_LPD IS NOT NULL);", conn))
        {
            invUpdated = await updInv.ExecuteNonQueryAsync(ct);
        }

        summary["ptUpdated"] = ptUpdated;
        summary["invUpdated"] = invUpdated;

        // Kapama sonrası tahsilat fişi (TYPE=101 / IOCODE=1) — sadece PAID/CLOSED yetmez
        try
        {
            var tahsilat = await ApplyTahsilatChainAsync(conn, prefix, req.AgreementId,
                await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "ABYS_AGREEMENT_ID", ct),
                await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "OWNERREF", ct),
                gaps, ct);
            summary["tahsilatOutcome"] = tahsilat.Mode;
            summary["tahsilatInv"] = tahsilat.InvInserted;
            summary["tahsilatPt"] = tahsilat.PtInserted;
        }
        catch (Exception exTah)
        {
            _logger.LogWarning(exTah, "applyClose tahsilat chain Agr={Agr}", req.AgreementId);
            gaps.Add(new TahsilatGapItem
            {
                Code = "APPLY_CLOSE_TAHSILAT_FAIL",
                Severity = "WARN",
                Side = "ENERGY",
                Message = $"Kapama OK ama tahsilat zinciri: {exTah.Message}"
            });
        }

        sw.Stop();
        _logger.LogInformation(
            "Tahsilat APPLY close RunId={RunId} Agr={Agr} PT={Pt} INV={Inv}",
            runId, req.AgreementId, ptUpdated, invUpdated);

        return (summary, preview, gaps,
            MakeLog(runId, req.AgreementId, "applyClose", "ENERGY", "APPLY", sw.ElapsedMilliseconds,
                ptUpdated + invUpdated, "OK",
                $"ptUpdated={ptUpdated} invUpdated={invUpdated} candidates={inserted} tahInv={summary.GetValueOrDefault("tahsilatInv")}"));
    }

    /// <summary>
    /// Tek AGR pilot: izgazMGR → LS_{nr}_{period}_INVOICE / INVLINES / PAYTRANS / INSTALLMENT_PLAN.
    /// DRY_RUN: sayım + hizalama uçları. APPLY: 569 clean (ops) → 571 → INVLINES AGR → 575 → 611 → WIRE.
    /// </summary>
    public async Task<(
            Dictionary<string, object?> Summary,
            List<Dictionary<string, object?>> PreviewSms,
            List<Dictionary<string, object?>> PreviewEnergy,
            List<TahsilatGapItem> Gaps,
            TahsilatLogEvent Log)>
        ApplyPilotEnergyChainAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var summary = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
        var prefix = TablePrefix(req);
        var op = req.DryRun ? "DRY_RUN" : "APPLY";
        var agr = req.AgreementId;

        await using var conn = new SqlConnection(req.MssqlConnectionString);
        await conn.OpenAsync(ct);

        // Hedef tablolar — INVOICE/INVLINES/PAYTRANS zorunlu; INSTALLMENT_PLAN opsiyonel (taksitsiz AGR)
        var required = new[] { "INVOICE", "INVLINES", "PAYTRANS" };
        foreach (var t in required)
        {
            if (!await TableExistsAsync(conn, "dbo", $"{prefix}_{t}", ct))
            {
                gaps.Add(new TahsilatGapItem
                {
                    Code = "NO_ENERGY_TABLE",
                    Severity = "CRITICAL",
                    Side = "ENERGY",
                    Message = $"dbo.{prefix}_{t} yok — ENERGY DB / NR={req.EnergyNr} Period={req.EnergyPeriod} kontrol."
                });
            }
        }

        var hasInstPlanTable = await TableExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", ct);
        if (!hasInstPlanTable)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_ENERGY_INSTALLMENT_PLAN",
                Severity = "WARN",
                Side = "ENERGY",
                Message = $"dbo.{prefix}_INSTALLMENT_PLAN yok — 611/WIRE atlanacak (taksitsiz pilot OK)."
            });
        }

        if (gaps.Any(g => g.Severity == "CRITICAL"))
        {
            var missing = string.Join(", ", gaps.Where(g => g.Code == "NO_ENERGY_TABLE").Select(g => g.Message));
            sw.Stop();
            return (summary, [], [], gaps,
                MakeLog(runId, agr, "pilotEnergyChain", "ENERGY", op, sw.ElapsedMilliseconds, 0, "FAIL",
                    string.IsNullOrEmpty(missing) ? "target missing" : missing));
        }

        summary["hasInstallmentPlanTable"] = hasInstPlanTable;

        // izgazMGR erişimi (aynı instance — production SP modeli)
        var hasMgrInv = await ObjectExistsAsync(conn, "izgazMGR.dbo.LS_INVOICE", ct);
        var hasMgrLines = await ObjectExistsAsync(conn, "izgazMGR.dbo.LS_INVLINES", ct);
        var hasMgrInst = await ObjectExistsAsync(conn, "izgazMGR.dbo.CS_INSTALLMENT", ct);
        if (!hasMgrInv)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_IZGAZMGR_LS_INVOICE",
                Severity = "CRITICAL",
                Side = "ENERGY",
                Message = "izgazMGR.dbo.LS_INVOICE yok — önce adım pilotDumpMgr (APPLY) ile oluştur/doldur; ENERGY CS aynı instance'ta izgazMGR görmeli."
            });
            sw.Stop();
            return (summary, [], [], gaps,
                MakeLog(runId, agr, "pilotEnergyChain", "ENERGY", op, sw.ElapsedMilliseconds, 0, "FAIL", "izgazMGR missing"));
        }

        if (!string.Equals(prefix, "LS_005_01", StringComparison.OrdinalIgnoreCase))
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_PREFIX_SP_MISMATCH",
                Severity = "WARN",
                Side = "ENERGY",
                Message = $"UI prefix={prefix} ama production SP'ler LS_005_01_* yazar. Pilot için NR=005 Period=01 kullanın."
            });
        }

        var invTable = $"{prefix}_INVOICE";
        var hasEnAbysAgr = await ColumnExistsAsync(conn, "dbo", invTable, "ABYS_AGREEMENT_ID", ct);
        var hasEnOwner = await ColumnExistsAsync(conn, "dbo", invTable, "OWNERREF", ct);
        var hasEnAbysId = await ColumnExistsAsync(conn, "dbo", invTable, "ABYS_ID", ct);
        var hasEnAbysAcc = await ColumnExistsAsync(conn, "dbo", invTable, "ABYS_ACCOUNT_ID", ct);
        summary["enHasAbysAgreementId"] = hasEnAbysAgr;
        summary["enHasOwnerRef"] = hasEnOwner;

        if (!hasEnAbysAgr && !hasEnOwner)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_NO_AGR_COLUMN",
                Severity = "CRITICAL",
                Side = "ENERGY",
                Message = $"{invTable} üzerinde ABYS_AGREEMENT_ID ve OWNERREF yok — ENERGY şema / 00_abys_columns kontrol."
            });
            sw.Stop();
            return (summary, [], [], gaps,
                MakeLog(runId, agr, "pilotEnergyChain", "ENERGY", op, sw.ElapsedMilliseconds, 0, "FAIL", "no AGR column"));
        }

        if (!hasEnAbysAgr)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_NO_ABYS_AGR_COL",
                Severity = "WARN",
                Side = "ENERGY",
                Message =
                    $"{invTable}.ABYS_AGREEMENT_ID yok — filtre OWNERREF ile. 571 APPLY için 00_abys_columns.sql deploy edin (SP ABYS kolon yazar)."
            });
        }

        var invAgr = InvAgrPredicate("inv", hasEnAbysAgr, hasEnOwner, "@agr");
        var invAgrId = InvAgrPredicate("inv", hasEnAbysAgr, hasEnOwner, "@agrId");

        var hasInstAbysAgr = false;
        var hasInstOwner = false;
        if (hasInstPlanTable)
        {
            hasInstAbysAgr = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_AGREEMENT_ID", ct);
            hasInstOwner = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "OWNERREF", ct);
        }

        // --- Sayım (SMS/staging uçları vs ENERGY) ---
        var srcInv = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
 WHERE ABYS_AGREEMENT_ID = @agr
   AND ABYS_ACTION_ID BETWEEN 1 AND 2147483647", agr, ct);

        var srcLines = hasMgrLines
            ? await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*)
  FROM izgazMGR.dbo.LS_INVLINES l WITH (NOLOCK)
 WHERE l.ABYS_AGREEMENT_ID = @agr
   AND l.LREF BETWEEN 1 AND 2147483647", agr, ct)
            : 0L;

        var srcInst = hasMgrInst
            ? await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*)
  FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN ip WITH (NOLOCK)
  INNER JOIN izgazMGR.dbo.CS_INSTALLMENT ins WITH (NOLOCK) ON ins.ID = ip.INSTALLMENT_ID
 WHERE ins.AGREEMENT_ID = @agr
   AND ip.ID BETWEEN 1 AND 2147483647", agr, ct)
            : 0L;

        var enInv = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{invTable} inv WITH (NOLOCK)
 WHERE {invAgr}", agr, ct);

        var enLines = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*)
  FROM dbo.{prefix}_INVLINES il WITH (NOLOCK)
 WHERE EXISTS (
    SELECT 1 FROM dbo.{invTable} inv WITH (NOLOCK)
     WHERE inv.LREF = il.INVOICEREF
       AND {invAgr}
 )", agr, ct);

        var enPt = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*)
  FROM dbo.{prefix}_PAYTRANS pt WITH (NOLOCK)
 WHERE ISNULL(pt.IOCODE,0)=0
   AND EXISTS (
    SELECT 1 FROM dbo.{invTable} inv WITH (NOLOCK)
     WHERE inv.LREF = pt.INVOICEREF
       AND {invAgr}
 )", agr, ct);

        var enInst = 0L;
        if (hasInstPlanTable && (hasInstAbysAgr || hasInstOwner))
        {
            var instPred = InvAgrPredicate("ip", hasInstAbysAgr, hasInstOwner, "@agr");
            enInst = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{prefix}_INSTALLMENT_PLAN ip WITH (NOLOCK)
 WHERE {instPred}", agr, ct);
        }

        var badInt = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
 WHERE ABYS_AGREEMENT_ID = @agr
   AND (ABYS_ACTION_ID IS NULL OR ABYS_ACTION_ID < 1 OR ABYS_ACTION_ID > 2147483647)", agr, ct);

        summary["srcInvoice"] = srcInv;
        summary["srcInvlines"] = srcLines;
        summary["srcInstallment"] = srcInst;
        summary["enInvoice"] = enInv;
        summary["enInvlines"] = enLines;
        summary["enPaytrans"] = enPt;
        summary["enInstallment"] = enInst;
        summary["badIntLref"] = badInt;
        summary["tablePrefix"] = prefix;
        summary["cleanBeforePilot"] = req.CleanBeforePilot;

        var compareRows = new List<Dictionary<string, object?>>
        {
            Row("INVOICE", srcInv, enInv, "LREF=ABYS_ACTION_ID INT"),
            Row("INVLINES", srcLines, enLines, "LREF IDENTITY_INSERT"),
            Row("PAYTRANS_DEBT", srcInv, enPt, "575: INVOICE→PT IOCODE=0"),
            Row("INSTALLMENT_PLAN", srcInst, enInst, "611+WIRE")
        };

        if (badInt > 0)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_BAD_INT_LREF",
                Severity = "CRITICAL",
                Side = "BOTH",
                Message = $"{badInt} kaynak ABYS_ACTION_ID INT dışı (1..2147483647)."
            });
        }

        if (srcInv == 0)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_NO_SRC_INVOICE",
                Severity = "WARN",
                Side = "SMS",
                Message = $"izgazMGR.LS_INVOICE'da AGR={agr} yok — dump/CTAS kontrol."
            });
        }

        // Spot ENERGY preview — yalnızca var olan kolonlar
        var previewCols = new List<string> { "inv.LREF", "inv.PAYABLETOTAL", "inv.CLOSED", "inv.CANCELED", "inv.FICHENO" };
        if (hasEnOwner) previewCols.Insert(1, "inv.OWNERREF");
        if (hasEnAbysId) previewCols.Insert(1, "inv.ABYS_ID");
        if (hasEnAbysAcc) previewCols.Insert(hasEnAbysId ? 2 : 1, "inv.ABYS_ACCOUNT_ID");
        if (hasEnAbysAgr) previewCols.Add("inv.ABYS_AGREEMENT_ID");
        var lrefEq = hasEnAbysId
            ? "CASE WHEN inv.LREF = inv.ABYS_ID THEN 1 ELSE 0 END AS LREF_EQ_ABYS"
            : "CAST(NULL AS INT) AS LREF_EQ_ABYS";
        var energyPreview = await QueryAsync(conn, $@"
SELECT TOP 100 {string.Join(", ", previewCols)},
       {lrefEq}
  FROM dbo.{invTable} inv WITH (NOLOCK)
 WHERE {invAgrId}
 ORDER BY inv.LREF", agr, ct);

        if (req.DryRun)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_DRY_RUN",
                Severity = "INFO",
                Side = "ENERGY",
                Message = $"DRY_RUN: APPLY ile 571→INVLINES→575→611(+WIRE) yazılacak. CleanBeforePilot={req.CleanBeforePilot}."
            });
            sw.Stop();
            return (summary, compareRows, energyPreview, gaps,
                MakeLog(runId, agr, "pilotEnergyChain", "ENERGY", "DRY_RUN", sw.ElapsedMilliseconds,
                    (int)Math.Min(srcInv, int.MaxValue), "OK",
                    $"srcInv={srcInv} enInv={enInv} srcLines={srcLines} srcInst={srcInst}"));
        }

        // APPLY: ABYS kolonlarını her zaman ensure et (INVOICE var, INVLINES/PAYTRANS eksik olabilir)
        {
            var added = await EnsurePilotAbysColumnsAsync(conn, prefix, ct);
            summary["abysColumnsAdded"] = added;
            hasEnAbysAgr = await ColumnExistsAsync(conn, "dbo", invTable, "ABYS_AGREEMENT_ID", ct);
            hasEnAbysId = await ColumnExistsAsync(conn, "dbo", invTable, "ABYS_ID", ct);
            hasEnAbysAcc = await ColumnExistsAsync(conn, "dbo", invTable, "ABYS_ACCOUNT_ID", ct);
            invAgr = InvAgrPredicate("inv", hasEnAbysAgr, hasEnOwner, "@agr");
            invAgrId = InvAgrPredicate("inv", hasEnAbysAgr, hasEnOwner, "@agrId");
            if (added > 0)
            {
                gaps.Add(new TahsilatGapItem
                {
                    Code = "PILOT_ABYS_COLS_ENSURED",
                    Severity = "INFO",
                    Side = "ENERGY",
                    Message = $"{added} ABYS kolon eklendi ({invTable}/INVLINES/PAYTRANS)."
                });
            }
            if (!hasEnAbysAgr && !hasEnOwner)
            {
                gaps.Add(new TahsilatGapItem
                {
                    Code = "PILOT_ABYS_COLS_REQUIRED",
                    Severity = "CRITICAL",
                    Side = "ENERGY",
                    Message =
                        $"{invTable}.ABYS_AGREEMENT_ID/OWNERREF yok — ALTER yetkisi veya 00_abys_columns.sql."
                });
                sw.Stop();
                return (summary, compareRows, energyPreview, gaps,
                    MakeLog(runId, agr, "pilotEnergyChain", "ENERGY", "APPLY", sw.ElapsedMilliseconds, 0, "FAIL",
                        "ABYS columns missing"));
            }
        }

        // ========== APPLY ==========
        var has571 = await ProcExistsAsync(conn, "dbo", "SP_MIGRATE_LS005_INVOICE", ct);
        var has575 = await ProcExistsAsync(conn, "dbo", "SP_MIGRATE_LS005_DEBT_PAYTRANS", ct);
        var has611 = await ProcExistsAsync(conn, "dbo", "SP_MIGRATE_LS005_INSTALLMENT_PLAN", ct);
        var has569 = await ProcExistsAsync(conn, "dbo", "SP_MIG_CLEAN_INVOICE_CHAIN_BY_AGR", ct);
        var hasWire = await ProcExistsAsync(conn, "dbo", "SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE", ct);
        summary["has571"] = has571;
        summary["has575"] = has575;
        summary["transferMode"] = has571 && has575 ? "SP" : "DIRECT";

        if (!has571 || !has575)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_SP_FALLBACK",
                Severity = "WARN",
                Side = "ENERGY",
                Message =
                    $"SP eksik (571={(has571 ? "var" : "yok")} 575={(has575 ? "var" : "yok")}) — izgazMGR→ENERGY doğrudan INSERT kullanılacak."
            });
        }

        try
        {
            // 1) Clean
            if (req.CleanBeforePilot && has569)
            {
                await ExecProcAsync(conn, "dbo.SP_MIG_CLEAN_INVOICE_CHAIN_BY_AGR", ct,
                    ("@AGRID", agr), ("@DEBUG", 1));
                summary["cleaned"] = "SP569";
            }
            else if (req.CleanBeforePilot)
            {
                var cleaned = await CleanEnergyAgrChainAsync(conn, prefix, agr, hasEnAbysAgr, hasEnOwner, ct);
                summary["cleaned"] = $"DIRECT:{cleaned}";
                if (!has569)
                {
                    gaps.Add(new TahsilatGapItem
                    {
                        Code = "PILOT_CLEAN_DIRECT",
                        Severity = "INFO",
                        Side = "ENERGY",
                        Message = "569 yok — PT/INVLINES/INVOICE AGR silindi (direct)."
                    });
                }
            }

            if (req.CleanBeforePilot && hasInstPlanTable && (hasInstAbysAgr || hasInstOwner))
            {
                var instDelPred = InvAgrPredicate("ip", hasInstAbysAgr, hasInstOwner, "@agr");
                await using (var delInst = new SqlCommand($@"
DELETE ip FROM dbo.{prefix}_INSTALLMENT_PLAN ip
 WHERE {instDelPred}", conn))
                {
                    delInst.Parameters.AddWithValue("@agr", agr);
                    delInst.CommandTimeout = 120;
                    summary["installmentDeleted"] = await delInst.ExecuteNonQueryAsync(ct);
                }
            }

            // 2) INVOICE
            if (has571)
            {
                try
                {
                    await ExecProcAsync(conn, "dbo.SP_MIGRATE_LS005_INVOICE", ct,
                        ("@BATCH_SIZE", 50000), ("@AGR_ID", agr), ("@RESUME", 0), ("@HARD_RESET", 0), ("@DEBUG", 1));
                    summary["invoiceOutcome"] = "SP571";
                }
                catch (Exception ex571)
                {
                    _logger.LogWarning(ex571, "571 failed — direct invoice insert Agr={Agr}", agr);
                    var n = await InsertInvoiceByAgrAsync(conn, prefix, agr, ct);
                    summary["invoiceOutcome"] = $"DIRECT_AFTER_571_FAIL:{n}";
                    gaps.Add(new TahsilatGapItem
                    {
                        Code = "PILOT_571_FALLBACK",
                        Severity = "WARN",
                        Side = "ENERGY",
                        Message = $"571 hata → direct INSERT {n} fatura. {ex571.Message}"
                    });
                }
            }
            else
            {
                var n = await InsertInvoiceByAgrAsync(conn, prefix, agr, ct);
                summary["invoiceOutcome"] = $"DIRECT:{n}";
                summary["invoiceInserted"] = n;
            }

            // 3) INVLINES — yalnızca kaynak∩hedef kolonlar (ENERGY'de FIRST_DATE/ABYS yok olabilir)
            var linesInserted = 0;
            if (hasMgrLines)
            {
                try
                {
                    linesInserted = await InsertInvlinesByAgrAsync(conn, prefix, agr, hasEnAbysAgr, hasEnOwner, ct);
                }
                catch (Exception exLines)
                {
                    _logger.LogWarning(exLines, "INVLINES insert failed Agr={Agr}", agr);
                    gaps.Add(new TahsilatGapItem
                    {
                        Code = "PILOT_INVLINES_FAIL",
                        Severity = "WARN",
                        Side = "ENERGY",
                        Message = $"INVLINES atlandı: {exLines.Message}"
                    });
                    summary["invlinesOutcome"] = "FAIL";
                }
            }
            summary["invlinesInserted"] = linesInserted;

            // 4) PAYTRANS borç
            if (has575)
            {
                try
                {
                    await ExecProcAsync(conn, "dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS", ct,
                        ("@BATCH_SIZE", 50000), ("@AGR_ID", agr), ("@RESUME", 0), ("@DEBUG", 1));
                    summary["paytransOutcome"] = "SP575";
                }
                catch (Exception ex575)
                {
                    _logger.LogWarning(ex575, "575 failed — direct debt PT Agr={Agr}", agr);
                    var n = await InsertDebtPaytransByAgrAsync(conn, prefix, agr, hasEnAbysAgr, hasEnOwner, ct);
                    summary["paytransOutcome"] = $"DIRECT_AFTER_575_FAIL:{n}";
                    gaps.Add(new TahsilatGapItem
                    {
                        Code = "PILOT_575_FALLBACK",
                        Severity = "WARN",
                        Side = "ENERGY",
                        Message = $"575 hata → direct PT {n}. {ex575.Message}"
                    });
                }
            }
            else
            {
                var n = await InsertDebtPaytransByAgrAsync(conn, prefix, agr, hasEnAbysAgr, hasEnOwner, ct);
                summary["paytransOutcome"] = $"DIRECT:{n}";
                summary["paytransInserted"] = n;
            }

            // 5) INSTALLMENT_PLAN 611 (yoksa izgazMGR → direct)
            if (hasInstPlanTable && has611)
            {
                try
                {
                    await ExecProcAsync(conn, "dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN", ct,
                        ("@BATCH_SIZE", 5000), ("@AGR_ID", agr), ("@RESUME", 0), ("@HARD_RESET", 0), ("@DEBUG", 1));
                    summary["installmentOutcome"] = "SP611";
                }
                catch (Exception ex611)
                {
                    _logger.LogWarning(ex611, "611 failed — direct installment plan Agr={Agr}", agr);
                    var nPlan = await InsertInstallmentPlanDirectAsync(conn, prefix, agr, ct);
                    summary["installmentOutcome"] = $"DIRECT_AFTER_611_FAIL:{nPlan}";
                    gaps.Add(new TahsilatGapItem
                    {
                        Code = "PILOT_611_FALLBACK",
                        Severity = "WARN",
                        Side = "ENERGY",
                        Message = $"611 hata → direct plan {nPlan}. {ex611.Message}"
                    });
                }
            }
            else if (hasInstPlanTable)
            {
                var nPlan = await InsertInstallmentPlanDirectAsync(conn, prefix, agr, ct);
                summary["installmentOutcome"] = $"DIRECT:{nPlan}";
                if (nPlan == 0 && hasMgrInst)
                {
                    gaps.Add(new TahsilatGapItem
                    {
                        Code = "PILOT_611_MISSING",
                        Severity = "WARN",
                        Side = "ENERGY",
                        Message = "SP_MIGRATE_LS005_INSTALLMENT_PLAN yok — direct plan 0 satır (izgazMGR taksit dump kontrol)."
                    });
                }
            }
            else
                summary["installmentOutcome"] = "SKIP_NO_TABLE";

            // 6) WIRE installment ↔ invoice
            if (hasInstPlanTable && hasWire)
            {
                try
                {
                    await ExecProcAsync(conn, "dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE", ct,
                        ("@AGR_ID", agr), ("@DEBUG", 1));
                    summary["wireOutcome"] = "OK";
                }
                catch (Exception exWire)
                {
                    summary["wireOutcome"] = "FAIL:" + exWire.Message;
                    _logger.LogWarning(exWire, "WIRE installment failed Agr={Agr}", agr);
                }
            }
            else
                summary["wireOutcome"] = !hasInstPlanTable ? "SKIP_NO_TABLE" : "SKIP_NO_SP";

            // 6a) Fatura INSTALLMENT_PLAN_REF / ABYS_INSTALLMENT_ID doldur (611b yalnızca plan.INVOICE_REF yazar)
            try
            {
                var wiredRefs = await WireInvoiceInstallmentRefsAsync(
                    conn, prefix, agr, hasEnAbysAgr, hasEnOwner, gaps, ct);
                summary["installmentRefWired"] = wiredRefs;
            }
            catch (Exception exWireRef)
            {
                _logger.LogWarning(exWireRef, "WireInvoiceInstallmentRefs failed Agr={Agr}", agr);
                summary["installmentRefWired"] = "FAIL:" + exWireRef.Message;
                gaps.Add(new TahsilatGapItem
                {
                    Code = "PILOT_INSTALLMENT_REF_FAIL",
                    Severity = "WARN",
                    Side = "ENERGY",
                    Message = $"INSTALLMENT_PLAN_REF wire: {exWireRef.Message}"
                });
            }

            // 6b) Borç PT → taksit PT (SP_TAKSIT_OLUSTUR / 613 mantığı: INST_NR, PAYTYPE=120)
            try
            {
                var split = await ApplyInstallmentDebtSplitAsync(conn, prefix, agr, hasEnAbysAgr, hasEnOwner, gaps, ct);
                summary["taksitSplitOutcome"] = split.Mode;
                summary["taksitPtInserted"] = split.PtInserted;
                summary["taksitPlansWired"] = split.PlansWired;
            }
            catch (Exception exSplit)
            {
                _logger.LogWarning(exSplit, "Taksit split failed Agr={Agr}", agr);
                summary["taksitSplitOutcome"] = "FAIL:" + exSplit.Message;
                summary["taksitPtInserted"] = 0;
                gaps.Add(new TahsilatGapItem
                {
                    Code = "PILOT_TAKSIT_SPLIT_FAIL",
                    Severity = "WARN",
                    Side = "ENERGY",
                    Message = $"Taksit PT split: {exSplit.Message}"
                });
            }

            // 7) SMS/izgazMGR kapalı faturaları ENERGY'ye yansıt + PAID hizala
            var synced = await SyncClosedFromMgrAsync(conn, prefix, agr, hasEnAbysAgr, hasEnOwner, ct);
            summary["closedSyncedFromMgr"] = synced;
            var aligned = await AlignClosedInvoicesAsync(conn, prefix, agr, hasEnAbysAgr, hasEnOwner, ct);
            summary["alignedClosed"] = aligned;

            // 8) Tahsilat zinciri: TYPE=101 INV + IOCODE=1 PT (CROSSREF→borç PT) — banka SP örneği
            var tahsilat = await ApplyTahsilatChainAsync(conn, prefix, agr, hasEnAbysAgr, hasEnOwner, gaps, ct);
            summary["tahsilatOutcome"] = tahsilat.Mode;
            summary["tahsilatInv"] = tahsilat.InvInserted;
            summary["tahsilatPt"] = tahsilat.PtInserted;
            summary["tahsilatDebtClosed"] = tahsilat.DebtClosed;

            // 8b) Ödenen taksit satırları: PAID + banka/makbuz/tarih + (hepsi ödendiyse) CLOSED
            try
            {
                var instPay = await ApplyInstallmentTahsilatFromPlanAsync(
                    conn, prefix, agr, hasEnAbysAgr, hasEnOwner, gaps, ct);
                summary["taksitTahsilatOutcome"] = instPay.Mode;
                summary["taksitTahsilatPt"] = instPay.PtInserted;
                summary["taksitTahsilatUpdated"] = instPay.Updated;
                summary["taksitInvClosed"] = instPay.DebtClosed;
            }
            catch (Exception exInstPay)
            {
                _logger.LogWarning(exInstPay, "Installment tahsilat failed Agr={Agr}", agr);
                summary["taksitTahsilatOutcome"] = "FAIL:" + exInstPay.Message;
                gaps.Add(new TahsilatGapItem
                {
                    Code = "PILOT_TAKSIT_TAHSILAT_FAIL",
                    Severity = "WARN",
                    Side = "ENERGY",
                    Message = $"Taksit tahsilat: {exInstPay.Message}"
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Pilot ENERGY chain failed Agr={Agr}", agr);
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_APPLY_FAIL",
                Severity = "CRITICAL",
                Side = "ENERGY",
                Message = ex.Message
            });
            sw.Stop();
            return (summary, compareRows, energyPreview, gaps,
                MakeLog(runId, agr, "pilotEnergyChain", "ENERGY", "APPLY", sw.ElapsedMilliseconds, 0, "FAIL", ex.Message));
        }

        // Post counts + preview
        enInv = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{invTable} inv WITH (NOLOCK)
 WHERE {invAgr}", agr, ct);
        enLines = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{prefix}_INVLINES il WITH (NOLOCK)
 WHERE EXISTS (SELECT 1 FROM dbo.{invTable} inv WITH (NOLOCK)
   WHERE inv.LREF=il.INVOICEREF AND {invAgr})", agr, ct);
        enPt = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{prefix}_PAYTRANS pt WITH (NOLOCK)
 WHERE ISNULL(pt.IOCODE,0)=0 AND EXISTS (SELECT 1 FROM dbo.{invTable} inv WITH (NOLOCK)
   WHERE inv.LREF=pt.INVOICEREF AND {invAgr})", agr, ct);
        var enPayPt = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{prefix}_PAYTRANS pt WITH (NOLOCK)
 WHERE ISNULL(pt.IOCODE,0)=1 AND EXISTS (SELECT 1 FROM dbo.{invTable} inv WITH (NOLOCK)
   WHERE inv.LREF=pt.INVOICEREF AND {invAgr})", agr, ct);
        var enTahInv = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{invTable} inv WITH (NOLOCK)
 WHERE {invAgr} AND ISNULL(inv.IOCODE,0)=1 AND ISNULL(inv.[TYPE],0)=101", agr, ct);
        if (hasInstPlanTable && (hasInstAbysAgr || hasInstOwner))
        {
            var instPredAfter = InvAgrPredicate("ip", hasInstAbysAgr, hasInstOwner, "@agr");
            enInst = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{prefix}_INSTALLMENT_PLAN ip WITH (NOLOCK)
 WHERE {instPredAfter}", agr, ct);
        }
        else
            enInst = 0L;

        summary["enInvoiceAfter"] = enInv;
        summary["enInvlinesAfter"] = enLines;
        summary["enPaytransAfter"] = enPt;
        summary["enPaytransTahsilat"] = enPayPt;
        summary["enTahsilatInvoice"] = enTahInv;
        summary["enInstallmentAfter"] = enInst;

        compareRows =
        [
            Row("INVOICE", srcInv, enInv, "after APPLY"),
            Row("INVLINES", srcLines, enLines, "after APPLY"),
            Row("PAYTRANS_DEBT", srcInv, enPt, "after APPLY"),
            Row("PAYTRANS_TAH", 0, enPayPt, "IOCODE=1 TYPE=101 zincir"),
            Row("INSTALLMENT_PLAN", srcInst, enInst, "after APPLY")
        ];

        if (enPayPt == 0 && enInv > 0)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_NO_TAHSILAT_CHAIN",
                Severity = "WARN",
                Side = "ENERGY",
                Message =
                    "Borç yüklendi ama tahsilat PT (IOCODE=1) yok. 597 overlay (LS_OV_*) veya CLOSED borç adayı kontrol."
            });
        }

        energyPreview = await QueryAsync(conn, $@"
SELECT TOP 100 {string.Join(", ", previewCols)},
       {lrefEq}
  FROM dbo.{invTable} inv WITH (NOLOCK)
 WHERE {invAgrId}
 ORDER BY inv.LREF", agr, ct);

        if (srcInv > 0 && enInv == 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_INV_NOT_LOADED",
                Severity = "CRITICAL",
                Side = "ENERGY",
                Message = "APPLY sonrası ENERGY'de fatura yok — 571 log / AGR resolve kontrol."
            });

        sw.Stop();
        return (summary, compareRows, energyPreview, gaps,
            MakeLog(runId, agr, "pilotEnergyChain", "ENERGY", "APPLY", sw.ElapsedMilliseconds,
                (int)Math.Min(enInv, int.MaxValue),
                gaps.Any(g => g.Severity == "CRITICAL") ? "FAIL" : "OK",
                $"enInv={enInv} enLines={enLines} enPt={enPt} enInst={enInst}"));
    }

    private static Dictionary<string, object?> Row(string layer, long src, long en, string note) =>
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["LAYER"] = layer,
            ["SRC"] = src,
            ["ENERGY"] = en,
            ["DELTA"] = en - src,
            ["NOTE"] = note
        };

    /// <summary>00_abys_columns eşdeğeri — pilot için eksik ABYS_* kolonlarını NULL ekler.</summary>
    private async Task<int> EnsurePilotAbysColumnsAsync(SqlConnection conn, string prefix, CancellationToken ct)
    {
        var specs = new (string Table, string Col, string Def)[]
        {
            ($"{prefix}_INVOICE", "ABYS_ID", "BIGINT NULL"),
            ($"{prefix}_INVOICE", "ABYS_ACCOUNT_ID", "BIGINT NULL"),
            ($"{prefix}_INVOICE", "ABYS_ACTION_TYPE_ID", "BIGINT NULL"),
            ($"{prefix}_INVOICE", "ABYS_ACCRUE_TYPE_ID", "SMALLINT NULL"),
            ($"{prefix}_INVOICE", "ABYS_REGISTER_ID", "BIGINT NULL"),
            ($"{prefix}_INVOICE", "ABYS_AGREEMENT_ID", "BIGINT NULL"),
            ($"{prefix}_INVOICE", "ABYS_INSTALLATION_ID", "BIGINT NULL"),
            ($"{prefix}_INVOICE", "ABYS_METER_ID", "BIGINT NULL"),
            ($"{prefix}_INVOICE", "ABYS_INSTALLMENT_ID", "BIGINT NULL"),
            ($"{prefix}_INVOICE", "ABYS_ADDUSER", "BIGINT NULL"),
            ($"{prefix}_INVOICE", "ABYS_UPDUSER", "BIGINT NULL"),
            ($"{prefix}_INVLINES", "ABYS_ID", "BIGINT NULL"),
            ($"{prefix}_INVLINES", "ABYS_AGREEMENT_ID", "BIGINT NULL"),
            ($"{prefix}_INVLINES", "ABYS_INCOME_ROW_ID", "BIGINT NULL"),
            ($"{prefix}_INVLINES", "ABYS_INCOME_ID", "BIGINT NULL"),
            ($"{prefix}_INVLINES", "ABYS_ACTION_ID", "BIGINT NULL"),
            ($"{prefix}_INVLINES", "ABYS_ACCOUNT_ID", "BIGINT NULL"),
            ($"{prefix}_INVLINES", "ABYS_REGISTER_ID", "BIGINT NULL"),
            ($"{prefix}_INVLINES", "ABYS_ACTION_TYPE_ID", "BIGINT NULL"),
            ($"{prefix}_INVLINES", "ABYS_ACCRUE_TYPE_ID", "SMALLINT NULL"),
            ($"{prefix}_INVLINES", "ABYS_IS_DISCOUNT", "DECIMAL(22,0) NULL"),
            ($"{prefix}_INVLINES", "ABYS_IS_VAT_INCOME", "DECIMAL(22,0) NULL"),
            ($"{prefix}_INVLINES", "ABYS_IS_DEPOSIT", "DECIMAL(22,0) NULL"),
            ($"{prefix}_INVLINES", "ABYS_IS_OVERDUE_INCOME", "DECIMAL(22,0) NULL"),
            ($"{prefix}_INVLINES", "ABYS_IS_LEGAL_FEE", "DECIMAL(22,0) NULL"),
            ($"{prefix}_INVLINES", "ABYS_INCOME_CODE", "NVARCHAR(10) NULL"),
            ($"{prefix}_INVLINES", "ABYS_AMOUNT_RAW", "DECIMAL(15,2) NULL"),
            ($"{prefix}_INVLINES", "ABYS_STATUS", "SMALLINT NULL"),
            ($"{prefix}_INVLINES", "ABYS_QUANTITY", "DECIMAL(15,3) NULL"),
            ($"{prefix}_INVLINES", "ABYS_UNIT_PRICE", "DECIMAL(19,8) NULL"),
            ($"{prefix}_INVLINES", "ABYS_AMOUNT1", "DECIMAL(15,2) NULL"),
            ($"{prefix}_INVLINES", "ABYS_AMOUNT2", "DECIMAL(15,2) NULL"),
            ($"{prefix}_INVLINES", "ABYS_AMOUNT3", "DECIMAL(15,2) NULL"),
            ($"{prefix}_INVLINES", "ABYS_AMOUNT4", "DECIMAL(15,2) NULL"),
            ($"{prefix}_INVLINES", "ABYS_AMOUNT5", "DECIMAL(15,2) NULL"),
            ($"{prefix}_PAYTRANS", "ABYS_ID", "BIGINT NULL"),
            ($"{prefix}_PAYTRANS", "ABYS_ACCOUNT_ID", "BIGINT NULL"),
            ($"{prefix}_PAYTRANS", "ABYS_AGREEMENT_ID", "BIGINT NULL"),
            ($"{prefix}_PAYTRANS", "ABYS_INVOICE_LREF", "INT NULL"),
            ($"{prefix}_PAYTRANS", "ABYS_ACTION_TYPE_ID", "BIGINT NULL"),
            ($"{prefix}_PAYTRANS", "ABYS_ACCRUE_TYPE_ID", "SMALLINT NULL"),
            ($"{prefix}_PAYTRANS", "ABYS_REGISTER_ID", "BIGINT NULL"),
            ($"{prefix}_PAYTRANS", "ABYS_ADDUSER", "BIGINT NULL"),
            ($"{prefix}_PAYTRANS", "ABYS_UPDUSER", "BIGINT NULL"),
        };

        var added = 0;
        foreach (var (table, col, def) in specs)
        {
            if (!await TableExistsAsync(conn, "dbo", table, ct)) continue;
            if (await ColumnExistsAsync(conn, "dbo", table, col, ct)) continue;
            try
            {
                await using var cmd = new SqlCommand(
                    $"ALTER TABLE dbo.[{table}] ADD [{col}] {def};", conn) { CommandTimeout = 60 };
                await cmd.ExecuteNonQueryAsync(ct);
                added++;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Pilot ABYS column add failed {Table}.{Col}", table, col);
            }
        }

        return added;
    }

    private static async Task<int> CleanEnergyAgrChainAsync(
        SqlConnection conn, string prefix, long agr, bool hasAbysAgr, bool hasOwner, CancellationToken ct)
    {
        var pred = InvAgrPredicate("inv", hasAbysAgr, hasOwner, "@agr");
        var total = 0;
        await using (var delPt = new SqlCommand($@"
DELETE pt FROM dbo.{prefix}_PAYTRANS pt
 INNER JOIN dbo.{prefix}_INVOICE inv ON inv.LREF = pt.INVOICEREF
 WHERE {pred}", conn) { CommandTimeout = 180 })
        {
            delPt.Parameters.AddWithValue("@agr", agr);
            total += await delPt.ExecuteNonQueryAsync(ct);
        }

        await using (var delLines = new SqlCommand($@"
DELETE il FROM dbo.{prefix}_INVLINES il
 INNER JOIN dbo.{prefix}_INVOICE inv ON inv.LREF = il.INVOICEREF
 WHERE {pred}", conn) { CommandTimeout = 180 })
        {
            delLines.Parameters.AddWithValue("@agr", agr);
            total += await delLines.ExecuteNonQueryAsync(ct);
        }

        await using (var delInv = new SqlCommand($@"
DELETE inv FROM dbo.{prefix}_INVOICE inv
 WHERE {pred}", conn) { CommandTimeout = 180 })
        {
            delInv.Parameters.AddWithValue("@agr", agr);
            total += await delInv.ExecuteNonQueryAsync(ct);
        }

        return total;
    }

    /// <summary>SP 571 yoksa: izgazMGR.LS_INVOICE → ENERGY INVOICE (LREF=ABYS_ACTION_ID).</summary>
    private async Task<int> InsertInvoiceByAgrAsync(SqlConnection conn, string prefix, long agr, CancellationToken ct)
    {
        var hasLastPaidDst = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "LASTPAIDDATE", ct);
        var hasLastPaidSrc = await MgrColumnExistsAsync(conn, "LS_INVOICE", "LASTPAIDDATE", ct);
        var lastPaidCol = hasLastPaidDst && hasLastPaidSrc ? ", LASTPAIDDATE" : "";
        var lastPaidSel = hasLastPaidDst && hasLastPaidSrc
            ? @",
    CASE WHEN s.LASTPAIDDATE IS NULL OR s.LASTPAIDDATE < '19000101' OR s.LASTPAIDDATE > '20790606' THEN NULL
         ELSE CAST(s.LASTPAIDDATE AS SMALLDATETIME) END"
            : hasLastPaidDst ? ", NULL" : "";

        var hasBankRefDst = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "BANKREF", ct);
        var hasBankRefSrc = await MgrColumnExistsAsync(conn, "LS_INVOICE", "BANKREF", ct);
        var hasBankRecDst = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "BANK_RECORD_REF", ct);
        var hasBankRecSrc = await MgrColumnExistsAsync(conn, "LS_INVOICE", "BANK_RECORD_REF", ct);
        var bankRefCol = hasBankRefDst && hasBankRefSrc ? ", BANKREF" : "";
        var bankRefSel = hasBankRefDst && hasBankRefSrc ? ", CAST(s.BANKREF AS INT)" : hasBankRefDst ? ", NULL" : "";
        var bankRecCol = hasBankRecDst && hasBankRecSrc ? ", BANK_RECORD_REF" : "";
        var bankRecSel = hasBankRecDst && hasBankRecSrc
            ? ", LEFT(CAST(s.BANK_RECORD_REF AS NVARCHAR(50)), 50) COLLATE DATABASE_DEFAULT"
            : hasBankRecDst ? ", NULL" : "";

        var hasPlanRefDst = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "INSTALLMENT_PLAN_REF", ct);
        var hasPlanRefSrc = await MgrColumnExistsAsync(conn, "LS_INVOICE", "INSTALLMENT_PLAN_REF", ct);
        var hasAbysInstSrc = await MgrColumnExistsAsync(conn, "LS_INVOICE", "ABYS_INSTALLMENT_ID", ct);
        // PLAN_ID = CS_INSTALLMENT.ID → INSTALLMENT_PLAN_REF + ABYS_INSTALLMENT_ID
        var planRefCol = hasPlanRefDst ? ", INSTALLMENT_PLAN_REF" : "";
        var planRefSel = hasPlanRefDst
            ? (hasPlanRefSrc && hasAbysInstSrc
                ? ", CAST(COALESCE(NULLIF(s.INSTALLMENT_PLAN_REF,0), s.ABYS_INSTALLMENT_ID) AS INT)"
                : hasPlanRefSrc
                    ? ", CAST(s.INSTALLMENT_PLAN_REF AS INT)"
                    : hasAbysInstSrc
                        ? ", CAST(s.ABYS_INSTALLMENT_ID AS INT)"
                        : ", NULL")
            : "";

        await using (var on = new SqlCommand($"SET IDENTITY_INSERT dbo.{prefix}_INVOICE ON;", conn))
            await on.ExecuteNonQueryAsync(ct);

        try
        {
            await using var cmd = new SqlCommand($@"
INSERT INTO dbo.{prefix}_INVOICE (
    LREF, IOCODE, FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF,
    TLTOTAL, CURID, CURTOTAL, CANCELED, OWNERREF, OWNERTYPE,
    TAX, DV, GRANDTOTAL, PRINTCOUNT, PAYABLETOTAL, CLOSED, AMOUNT,
    ADDDATE, ADDUSER, UPDDATE, UPDUSER{lastPaidCol}{bankRefCol}{bankRecCol}{planRefCol},
    ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_ACCRUE_TYPE_ID,
    ABYS_REGISTER_ID, ABYS_AGREEMENT_ID, ABYS_INSTALLMENT_ID
)
SELECT
    CAST(s.ABYS_ACTION_ID AS INT),
    CAST(ISNULL(s.IOCODE, 0) AS TINYINT),
    LEFT(CAST(s.FICHENO AS NVARCHAR(45)), 16) COLLATE DATABASE_DEFAULT,
    CASE WHEN s.DATE_ IS NULL OR s.DATE_ < '19000101' OR s.DATE_ > '20790606' THEN NULL
         ELSE CAST(s.DATE_ AS SMALLDATETIME) END,
    CASE WHEN s.DUEDATE IS NULL OR s.DUEDATE < '19000101' OR s.DUEDATE > '20790606' THEN NULL
         ELSE CAST(s.DUEDATE AS SMALLDATETIME) END,
    CAST(s.[TYPE] AS TINYINT),
    CAST(s.CLIENTREF AS INT),
    CAST(s.TLTOTAL AS FLOAT),
    CASE WHEN s.CURID IS NULL THEN CAST(160 AS SMALLINT)
         WHEN CAST(s.CURID AS BIGINT) BETWEEN -32768 AND 32767 THEN CAST(s.CURID AS SMALLINT)
         ELSE CAST(160 AS SMALLINT) END,
    CAST(s.CURTOTAL AS FLOAT),
    CASE WHEN ISNULL(s.CANCELED,0)<>0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
    CAST(COALESCE(s.OWNERREF, s.ABYS_AGREEMENT_ID) AS INT),
    CAST(ISNULL(s.OWNERTYPE, 0) AS TINYINT),
    CAST(s.TAX AS FLOAT),
    CAST(s.DV AS FLOAT),
    CAST(s.GRANDTOTAL AS FLOAT),
    CAST(s.PRINTCOUNT AS INT),
    CAST(s.PAYABLETOTAL AS FLOAT),
    CASE WHEN ISNULL(s.CLOSED,0)<>0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
    CAST(s.AMOUNT AS FLOAT),
    CASE WHEN s.ADDDATE IS NULL OR s.ADDDATE < '19000101' OR s.ADDDATE > '20790606' THEN NULL
         ELSE CAST(s.ADDDATE AS SMALLDATETIME) END,
    CAST(s.ADDUSER AS INT),
    CASE WHEN s.UPDDATE IS NULL OR s.UPDDATE < '19000101' OR s.UPDDATE > '20790606' THEN NULL
         ELSE CAST(s.UPDDATE AS SMALLDATETIME) END,
    CAST(s.UPDUSER AS INT){lastPaidSel}{bankRefSel}{bankRecSel}{planRefSel},
    CAST(s.ABYS_ACTION_ID AS BIGINT),
    CAST(s.ABYS_ACCOUNT_ID AS BIGINT),
    CAST(s.ABYS_ACTION_TYPE_ID AS BIGINT),
    CAST(s.ABYS_ACCRUE_TYPE_ID AS SMALLINT),
    CAST(s.ABYS_REGISTER_ID AS BIGINT),
    CAST(s.ABYS_AGREEMENT_ID AS BIGINT),
    CAST(s.ABYS_INSTALLMENT_ID AS BIGINT)
FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
WHERE s.ABYS_AGREEMENT_ID = @agr
  AND s.ABYS_ACTION_ID BETWEEN 1 AND 2147483647
  AND NOT EXISTS (
      SELECT 1 FROM dbo.{prefix}_INVOICE t WITH (NOLOCK)
       WHERE t.LREF = CAST(s.ABYS_ACTION_ID AS INT)
  )", conn)
            {
                CommandTimeout = 600
            };
            cmd.Parameters.AddWithValue("@agr", agr);
            return await cmd.ExecuteNonQueryAsync(ct);
        }
        finally
        {
            await using var off = new SqlCommand($"SET IDENTITY_INSERT dbo.{prefix}_INVOICE OFF;", conn);
            await off.ExecuteNonQueryAsync(ct);
        }
    }

    /// <summary>SP 575 yoksa: ENERGY INVOICE (IOCODE=0) → borç PAYTRANS.</summary>
    private async Task<int> InsertDebtPaytransByAgrAsync(
        SqlConnection conn, string prefix, long agr, bool hasAbysAgr, bool hasOwner, CancellationToken ct)
    {
        var pred = InvAgrPredicate("inv", hasAbysAgr, hasOwner, "@agr");
        var hasPtAbys = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "ABYS_ID", ct);
        var hasPtBank = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "BANKREF", ct);
        var hasInvBank = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "BANKREF", ct);
        var abysInsertCols = hasPtAbys
            ? @",
    ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_ACCRUE_TYPE_ID,
    ABYS_REGISTER_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF"
            : "";
        var abysSelectCols = hasPtAbys
            ? @",
    inv.ABYS_ID, inv.ABYS_ACCOUNT_ID, inv.ABYS_ACTION_TYPE_ID, inv.ABYS_ACCRUE_TYPE_ID,
    inv.ABYS_REGISTER_ID, inv.ABYS_AGREEMENT_ID, inv.LREF"
            : "";
        var bankCol = hasPtBank ? ", BANKREF" : "";
        var bankSel = hasPtBank
            ? (hasInvBank ? ", inv.BANKREF" : ", CAST(NULL AS INT)")
            : "";

        await using var cmd = new SqlCommand($@"
INSERT INTO dbo.{prefix}_PAYTRANS (
    INVOICEREF, INVLINEREF, DATE_, [TYPE], CLIENTREF, CLIENT_TYPE,
    IOCODE, TLTOTAL, PAID, DUEDATE, PAYTYPE, CURID, CURRATE, CURTOTAL,
    CROSSREF, TRANSTYPE, CANCELED, TAX, GRANDTOTAL, LINETYPE, INST_NR, DV,
    PAYABLETOTAL, ADDDATE, ADDUSER, XTYPE, IS_LAW, PAYCURID
    {abysInsertCols}{bankCol}
)
SELECT
    inv.LREF, NULL, inv.DATE_, inv.[TYPE], inv.CLIENTREF, inv.OWNERTYPE,
    CAST(0 AS TINYINT), inv.TLTOTAL, CAST(0 AS FLOAT), inv.DUEDATE,
    CAST(174 AS INT), inv.CURID, CAST(1 AS FLOAT), inv.CURTOTAL,
    NULL, CAST(113 AS INT), inv.CANCELED, ISNULL(inv.TAX, 0), inv.GRANDTOTAL,
    CAST(103 AS INT), CAST(0 AS INT), ISNULL(inv.DV, 0), inv.PAYABLETOTAL,
    inv.ADDDATE, inv.ADDUSER, ISNULL(inv.XTYPE, 1), inv.IS_LAW, ISNULL(inv.CURID, 160)
    {abysSelectCols}{bankSel}
FROM dbo.{prefix}_INVOICE inv WITH (NOLOCK)
WHERE {pred}
  AND ISNULL(inv.IOCODE, 0) = 0
  AND NOT EXISTS (
      SELECT 1 FROM dbo.{prefix}_PAYTRANS pt WITH (NOLOCK)
       WHERE pt.INVOICEREF = inv.LREF AND ISNULL(pt.IOCODE, 0) = 0
  )", conn)
        {
            CommandTimeout = 600
        };
        cmd.Parameters.AddWithValue("@agr", agr);
        return await cmd.ExecuteNonQueryAsync(ct);
    }

    private async Task<int> InsertInvlinesByAgrAsync(
        SqlConnection conn, string prefix, long agr, bool hasAbysAgr, bool hasOwner, CancellationToken ct)
    {
        var srcCols = await GetMssqlColumnsAsync(conn, "izgazMGR", "dbo", "LS_INVLINES", ct);
        var dstCols = await GetMssqlColumnsAsync(conn, null, "dbo", $"{prefix}_INVLINES", ct);
        if (srcCols.Count == 0 || dstCols.Count == 0)
            return 0;

        bool Src(string c) => srcCols.Contains(c);
        bool Dst(string c) => dstCols.Contains(c);
        string SrcOrNull(string col, string castExpr) =>
            Src(col) ? castExpr : "NULL";

        var insertCols = new List<string>();
        var selectExprs = new List<string>();

        void Map(string dest, string expr)
        {
            if (!Dst(dest)) return;
            insertCols.Add(dest == "TYPE" || dest == "DAY" ? $"[{dest}]" : dest);
            selectExprs.Add(expr);
        }

        Map("LREF", SrcOrNull("LREF", "CAST(s.LREF AS INT)"));
        Map("INVOICEREF", SrcOrNull("INVOICEREF", "CAST(s.INVOICEREF AS INT)"));
        Map("CLIENTREF", SrcOrNull("CLIENTREF", "CAST(s.CLIENTREF AS INT)"));
        Map("DATE_", Src("DATE_")
            ? "CASE WHEN s.DATE_ IS NULL OR s.DATE_ < '19000101' OR s.DATE_ > '20790606' THEN NULL ELSE CAST(s.DATE_ AS SMALLDATETIME) END"
            : "NULL");
        Map("TYPE", SrcOrNull("TYPE", "CAST(s.[TYPE] AS TINYINT)"));
        Map("LINENR", SrcOrNull("LINENR", "CAST(s.LINENR AS TINYINT)"));
        Map("TLTOTAL", SrcOrNull("TLTOTAL", "CAST(s.TLTOTAL AS FLOAT)"));
        Map("CURID", "CAST(160 AS SMALLINT)");
        Map("CURRATE", "CAST(1 AS FLOAT)");
        Map("CURTOTAL", Src("CURTOTAL") ? "CAST(s.CURTOTAL AS FLOAT)" : SrcOrNull("TLTOTAL", "CAST(s.TLTOTAL AS FLOAT)"));
        Map("FIRSTREAD", SrcOrNull("FIRSTREAD", "CAST(s.FIRSTREAD AS FLOAT)"));
        Map("LASTREAD", SrcOrNull("LASTREAD", "CAST(s.LASTREAD AS FLOAT)"));
        Map("TRANSTYPE", SrcOrNull("TRANSTYPE", "CAST(s.TRANSTYPE AS INT)"));
        Map("CANCELED", Src("CANCELED")
            ? "CASE WHEN ISNULL(s.CANCELED,0)<>0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END"
            : "CAST(0 AS BIT)");
        Map("TAX", SrcOrNull("TAX", "CAST(s.TAX AS FLOAT)"));
        Map("GRANDTOTAL", SrcOrNull("GRANDTOTAL", "CAST(s.GRANDTOTAL AS FLOAT)"));
        Map("LINEEXP", Src("LINEEXP") ? "LEFT(CAST(s.LINEEXP AS NVARCHAR(300)), 150) COLLATE DATABASE_DEFAULT" : "NULL");
        Map("LINETYPE", SrcOrNull("LINETYPE", "CAST(s.LINETYPE AS INT)"));
        Map("DV", SrcOrNull("DV", "CAST(s.DV AS FLOAT)"));
        Map("FITNO", Src("FITNO") ? "LEFT(CAST(s.FITNO AS NVARCHAR(100)), 50) COLLATE DATABASE_DEFAULT" : "NULL");
        Map("CNTREF", SrcOrNull("CNTREF", "CAST(s.CNTREF AS INT)"));
        Map("LOGO_FIRMNR", SrcOrNull("LOGO_FIRMNR", "CAST(s.LOGO_FIRMNR AS INT)"));
        Map("LOGO_FICHEREF", SrcOrNull("LOGO_FICHEREF", "CAST(s.LOGO_FICHEREF AS INT)"));
        Map("LOGO_FICHENO", Src("LOGO_FICHENO") ? "LEFT(CAST(s.LOGO_FICHENO AS NVARCHAR(100)), 50) COLLATE DATABASE_DEFAULT" : "NULL");
        Map("XTYPE", SrcOrNull("XTYPE", "CAST(s.XTYPE AS INT)"));
        Map("UNITPRICE", Src("UNITPRICE")
            ? "CAST(s.UNITPRICE AS FLOAT)"
            : SrcOrNull("ABYS_UNIT_PRICE", "CAST(s.ABYS_UNIT_PRICE AS FLOAT)"));
        Map("SPEREF", SrcOrNull("SPEREF", "CAST(s.SPEREF AS INT)"));
        Map("AMOUNT", Src("AMOUNT")
            ? "CAST(s.AMOUNT AS FLOAT)"
            : SrcOrNull("ABYS_QUANTITY", "CAST(s.ABYS_QUANTITY AS FLOAT)"));

        // ENERGY PCMS INVLINES'ta FIRST_DATE/LAST_DATE/DAY yok — yalnızca hedefte varsa
        Map("FIRST_DATE", SrcOrNull("FIRST_DATE", "s.FIRST_DATE"));
        Map("LAST_DATE", SrcOrNull("LAST_DATE", "s.LAST_DATE"));
        Map("DAY", SrcOrNull("DAY", "s.[DAY]"));

        // ABYS bridge — hedefte yoksa Map atlar; kaynakta yoksa NULL
        Map("ABYS_ID", Src("ABYS_INCOME_ROW_ID")
            ? "CAST(s.ABYS_INCOME_ROW_ID AS BIGINT)"
            : SrcOrNull("ABYS_ID", "CAST(s.ABYS_ID AS BIGINT)"));
        Map("ABYS_INCOME_ROW_ID", SrcOrNull("ABYS_INCOME_ROW_ID", "CAST(s.ABYS_INCOME_ROW_ID AS BIGINT)"));
        Map("ABYS_INCOME_ID", SrcOrNull("ABYS_INCOME_ID", "CAST(s.ABYS_INCOME_ID AS BIGINT)"));
        Map("ABYS_ACTION_ID", SrcOrNull("ABYS_ACTION_ID", "CAST(s.ABYS_ACTION_ID AS BIGINT)"));
        Map("ABYS_ACCOUNT_ID", SrcOrNull("ABYS_ACCOUNT_ID", "CAST(s.ABYS_ACCOUNT_ID AS BIGINT)"));
        Map("ABYS_REGISTER_ID", SrcOrNull("ABYS_REGISTER_ID", "CAST(s.ABYS_REGISTER_ID AS BIGINT)"));
        Map("ABYS_AGREEMENT_ID", SrcOrNull("ABYS_AGREEMENT_ID", "CAST(s.ABYS_AGREEMENT_ID AS BIGINT)"));
        Map("ABYS_ACTION_TYPE_ID", SrcOrNull("ABYS_ACTION_TYPE_ID", "CAST(s.ABYS_ACTION_TYPE_ID AS BIGINT)"));
        Map("ABYS_ACCRUE_TYPE_ID", SrcOrNull("ABYS_ACCRUE_TYPE_ID", "CAST(s.ABYS_ACCRUE_TYPE_ID AS SMALLINT)"));
        Map("ABYS_IS_DISCOUNT", SrcOrNull("ABYS_IS_DISCOUNT", "s.ABYS_IS_DISCOUNT"));
        Map("ABYS_IS_VAT_INCOME", SrcOrNull("ABYS_IS_VAT_INCOME", "s.ABYS_IS_VAT_INCOME"));
        Map("ABYS_IS_DEPOSIT", SrcOrNull("ABYS_IS_DEPOSIT", "s.ABYS_IS_DEPOSIT"));
        Map("ABYS_IS_OVERDUE_INCOME", SrcOrNull("ABYS_IS_OVERDUE_INCOME", "s.ABYS_IS_OVERDUE_INCOME"));
        Map("ABYS_IS_LEGAL_FEE", SrcOrNull("ABYS_IS_LEGAL_FEE", "s.ABYS_IS_LEGAL_FEE"));
        Map("ABYS_INCOME_CODE", Src("ABYS_INCOME_CODE") ? "LEFT(CAST(s.ABYS_INCOME_CODE AS NVARCHAR(100)), 10) COLLATE DATABASE_DEFAULT" : "NULL");
        Map("ABYS_AMOUNT_RAW", SrcOrNull("ABYS_AMOUNT_RAW", "CAST(s.ABYS_AMOUNT_RAW AS DECIMAL(15,2))"));
        Map("ABYS_STATUS", SrcOrNull("ABYS_STATUS", "CAST(s.ABYS_STATUS AS SMALLINT)"));
        Map("ABYS_QUANTITY", SrcOrNull("ABYS_QUANTITY", "CAST(s.ABYS_QUANTITY AS DECIMAL(15,3))"));
        Map("ABYS_UNIT_PRICE", SrcOrNull("ABYS_UNIT_PRICE", "CAST(s.ABYS_UNIT_PRICE AS DECIMAL(19,8))"));
        Map("ABYS_AMOUNT1", SrcOrNull("ABYS_AMOUNT1", "CAST(s.ABYS_AMOUNT1 AS DECIMAL(15,2))"));
        Map("ABYS_AMOUNT2", SrcOrNull("ABYS_AMOUNT2", "CAST(s.ABYS_AMOUNT2 AS DECIMAL(15,2))"));
        Map("ABYS_AMOUNT3", SrcOrNull("ABYS_AMOUNT3", "CAST(s.ABYS_AMOUNT3 AS DECIMAL(15,2))"));
        Map("ABYS_AMOUNT4", SrcOrNull("ABYS_AMOUNT4", "CAST(s.ABYS_AMOUNT4 AS DECIMAL(15,2))"));
        Map("ABYS_AMOUNT5", SrcOrNull("ABYS_AMOUNT5", "CAST(s.ABYS_AMOUNT5 AS DECIMAL(15,2))"));

        if (insertCols.Count < 2 || !insertCols.Contains("LREF"))
            return 0;

        var invPred = InvAgrPredicate("inv", hasAbysAgr, hasOwner, "@agr");
        var agrFilter = Src("ABYS_AGREEMENT_ID")
            ? "s.ABYS_AGREEMENT_ID = @agr"
            : $"EXISTS (SELECT 1 FROM dbo.{prefix}_INVOICE inv WITH (NOLOCK) WHERE inv.LREF = CAST(s.INVOICEREF AS INT) AND {invPred})";

        await using (var on = new SqlCommand($"SET IDENTITY_INSERT dbo.{prefix}_INVLINES ON;", conn))
            await on.ExecuteNonQueryAsync(ct);

        try
        {
            await using var cmd = new SqlCommand($@"
INSERT INTO dbo.{prefix}_INVLINES (
    {string.Join(", ", insertCols)}
)
SELECT
    {string.Join(",\n    ", selectExprs)}
FROM izgazMGR.dbo.LS_INVLINES s WITH (NOLOCK)
WHERE {agrFilter}
  AND s.LREF BETWEEN 1 AND 2147483647
  AND EXISTS (SELECT 1 FROM dbo.{prefix}_INVOICE inv WITH (NOLOCK) WHERE inv.LREF = CAST(s.INVOICEREF AS INT))
  AND NOT EXISTS (SELECT 1 FROM dbo.{prefix}_INVLINES t WITH (NOLOCK) WHERE t.LREF = CAST(s.LREF AS INT))", conn)
            {
                CommandTimeout = 600
            };
            cmd.Parameters.AddWithValue("@agr", agr);
            return await cmd.ExecuteNonQueryAsync(ct);
        }
        finally
        {
            await using var off = new SqlCommand($"SET IDENTITY_INSERT dbo.{prefix}_INVLINES OFF;", conn);
            await off.ExecuteNonQueryAsync(ct);
        }
    }

    private static async Task<HashSet<string>> GetMssqlColumnsAsync(
        SqlConnection conn, string? database, string schema, string table, CancellationToken ct)
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var sql = database == null
            ? @"SELECT c.name FROM sys.columns c
               JOIN sys.tables t ON t.object_id = c.object_id
               JOIN sys.schemas s ON s.schema_id = t.schema_id
               WHERE s.name = @sch AND t.name = @tbl"
            : $@"SELECT c.name FROM {database}.sys.columns c
               JOIN {database}.sys.tables t ON t.object_id = c.object_id
               JOIN {database}.sys.schemas s ON s.schema_id = t.schema_id
               WHERE s.name = @sch AND t.name = @tbl";
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@sch", schema);
        cmd.Parameters.AddWithValue("@tbl", table);
        try
        {
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
                set.Add(r.GetString(0));
        }
        catch
        {
            /* cross-db erişim yoksa boş */
        }
        return set;
    }

    private sealed record TahsilatChainResult(
        string Mode, int InvInserted, int PtInserted, int DebtClosed, int Updated = 0);

    /// <summary>
    /// Banka tahsilat örneği: TYPE=101 INV (IOCODE=1) + INVLINES + PAYTRANS (IOCODE=1, CROSSREF=borç PT)
    /// + borç INV CLOSED + borç PT PAID.
    /// Öncelik: SP_MIGRATE_TAHSILAT_OVERLAY_AGR (597); yoksa CLOSED borçlardan direct.
    /// </summary>
    private async Task<TahsilatChainResult> ApplyTahsilatChainAsync(
        SqlConnection conn, string prefix, long agr, bool hasAbysAgr, bool hasOwner,
        List<TahsilatGapItem> gaps, CancellationToken ct)
    {
        var has597 = await ProcExistsAsync(conn, "dbo", "SP_MIGRATE_TAHSILAT_OVERLAY_AGR", ct);
        var hasOvPay = await ObjectExistsAsync(conn, "izgazMGR.dbo.LS_OV_PAY_PT", ct);

        if (has597 && hasOvPay)
        {
            try
            {
                await ExecProcAsync(conn, "dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR", ct,
                    ("@AGR_ID", agr), ("@CLEAN", 1), ("@DEBUG", 1));
                var payCnt = await CountTahsilatPaytransAsync(conn, prefix, agr, hasAbysAgr, hasOwner, ct);
                gaps.Add(new TahsilatGapItem
                {
                    Code = "PILOT_TAHSILAT_597",
                    Severity = "INFO",
                    Side = "ENERGY",
                    Message = $"597 SP_MIGRATE_TAHSILAT_OVERLAY_AGR OK — tahsilat PT≈{payCnt}."
                });
                return new TahsilatChainResult("SP597", 0, (int)Math.Min(payCnt, int.MaxValue), 0);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "597 tahsilat overlay failed Agr={Agr} — direct fallback", agr);
                gaps.Add(new TahsilatGapItem
                {
                    Code = "PILOT_597_FALLBACK",
                    Severity = "WARN",
                    Side = "ENERGY",
                    Message = $"597 hata → direct tahsilat zinciri. {ex.Message}"
                });
            }
        }
        else if (!hasOvPay)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_NO_OV_PAY",
                Severity = "INFO",
                Side = "ENERGY",
                Message = "izgazMGR.LS_OV_PAY_PT yok — CLOSED borçlardan direct TYPE=101 tahsilat zinciri."
            });
        }

        return await BuildTahsilatChainDirectAsync(conn, prefix, agr, hasAbysAgr, hasOwner, gaps, ct);
    }

    private async Task<long> CountTahsilatPaytransAsync(
        SqlConnection conn, string prefix, long agr, bool hasAbysAgr, bool hasOwner, CancellationToken ct)
    {
        var pred = InvAgrPredicate("inv", hasAbysAgr, hasOwner, "@agr");
        return await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{prefix}_PAYTRANS pt WITH (NOLOCK)
 INNER JOIN dbo.{prefix}_INVOICE inv WITH (NOLOCK) ON inv.LREF = pt.INVOICEREF
 WHERE {pred} AND ISNULL(pt.IOCODE,0)=1", agr, ct);
    }

    /// <summary>
    /// CLOSED / tam ödenmiş borç faturaları için banka SP benzeri tahsilat fişi üretir.
    /// </summary>
    private async Task<TahsilatChainResult> BuildTahsilatChainDirectAsync(
        SqlConnection conn, string prefix, long agr, bool hasAbysAgr, bool hasOwner,
        List<TahsilatGapItem> gaps, CancellationToken ct)
    {
        var pred = InvAgrPredicate("inv", hasAbysAgr, hasOwner, "@agr");
        var hasCancelPay = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "CANCELLATIONPAYMENT", ct);
        var hasClientType = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "CLIENT_TYPE", ct);
        var hasBnType = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "BN_TYPE", ct);
        var hasFitno = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "FITNO", ct);
        var hasDv = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "DV", ct);
        var hasLastPaid = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "LASTPAIDDATE", ct);
        var hasInvlines = await TableExistsAsync(conn, "dbo", $"{prefix}_INVLINES", ct);
        var hasPtBnType = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "BN_TYPE", ct);
        var hasInvBankRef = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "BANKREF", ct);
        var hasInvBankRec = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "BANK_RECORD_REF", ct);
        var hasPtBankRef = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "BANKREF", ct);
        var hasPtBankRec = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "BANK_RECORD_REF", ct);
        var hasPtLastPaid = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "LASTPAIDDATE", ct);
        var hasPtXtype = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "XTYPE", ct);
        var hasInvXtype = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "XTYPE", ct);
        var hasInstNrCol = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "INST_NR", ct);
        var hasMgrBankRef = await MgrColumnExistsAsync(conn, "LS_INVOICE", "BANKREF", ct);
        var hasMgrBankRec = await MgrColumnExistsAsync(conn, "LS_INVOICE", "BANK_RECORD_REF", ct);
        var hasMgrClosedCalc = await MgrColumnExistsAsync(conn, "LS_INVOICE", "CLOSED_CALC", ct);
        var skipInstInvSql = hasInstNrCol
            ? $@"
  AND NOT EXISTS (
      SELECT 1 FROM dbo.{prefix}_PAYTRANS inst WITH (NOLOCK)
       WHERE inst.INVOICEREF = inv.LREF
         AND ISNULL(inst.IOCODE,0)=0 AND ISNULL(inst.CANCELED,0)=0
         AND ISNULL(inst.INST_NR,0) > 0
  )"
            : "";
        var mgrClosedPred = hasMgrClosedCalc
            ? "(ISNULL(s.CLOSED,0)=1 OR ISNULL(s.CLOSED_CALC,0)=1)"
            : "ISNULL(s.CLOSED,0)=1";

        // izgazMGR genelde Latin1, ENERGY CP1254 — COLLATE olmadan COALESCE/CASE collation conflict verir
        var bankRefSel = hasInvBankRef
            ? (hasMgrBankRef
                ? "COALESCE(inv.BANKREF, s.BANKREF) AS BANKREF"
                : "inv.BANKREF AS BANKREF")
            : "CAST(NULL AS INT) AS BANKREF";
        var bankRecSel = hasInvBankRec
            ? (hasMgrBankRec
                ? @"COALESCE(
    CAST(s.BANK_RECORD_REF AS NVARCHAR(50)) COLLATE DATABASE_DEFAULT,
    CAST(inv.BANK_RECORD_REF AS NVARCHAR(50)) COLLATE DATABASE_DEFAULT
  ) AS BANK_RECORD_REF"
                : "CAST(inv.BANK_RECORD_REF AS NVARCHAR(50)) COLLATE DATABASE_DEFAULT AS BANK_RECORD_REF")
            : "CAST(NULL AS NVARCHAR(50)) AS BANK_RECORD_REF";
        var mgrJoin = @"LEFT JOIN izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
    ON CAST(s.ABYS_ACTION_ID AS INT) = inv.LREF AND s.ABYS_AGREEMENT_ID = @agrId";

        var candidates = await QueryAsync(conn, $@"
SELECT TOP 2000
  inv.LREF AS DEBT_INV,
  pt.LREF AS DEBT_PT,
  inv.FICHENO, inv.CLIENTREF, inv.OWNERREF, inv.OWNERTYPE,
  inv.CURID,
  CASE WHEN ISNULL(inv.PAYABLETOTAL,0) > 0.01 THEN inv.PAYABLETOTAL
       WHEN ISNULL(pt.PAYABLETOTAL,0) > 0.01 THEN pt.PAYABLETOTAL
       WHEN ISNULL(inv.TLTOTAL,0) > 0.01 THEN inv.TLTOTAL
       ELSE inv.GRANDTOTAL END AS PAYABLETOTAL,
  inv.TLTOTAL, inv.GRANDTOTAL, inv.TAX,
  inv.DATE_ AS DEBT_DATE,
  {(hasLastPaid ? "inv.LASTPAIDDATE" : "CAST(NULL AS DATETIME)")} AS LASTPAIDDATE,
  {(hasBnType ? "inv.BN_TYPE" : "CAST(NULL AS INT)")} AS BN_TYPE,
  {(hasFitno ? "inv.FITNO" : "CAST(NULL AS BIGINT)")} AS FITNO,
  {(hasDv ? "inv.DV" : "CAST(0 AS FLOAT)")} AS DV,
  {(hasInvXtype ? "inv.XTYPE" : "CAST(1 AS INT)")} AS XTYPE,
  {bankRefSel},
  {bankRecSel}
FROM dbo.{prefix}_INVOICE inv WITH (NOLOCK)
INNER JOIN dbo.{prefix}_PAYTRANS pt WITH (NOLOCK)
  ON pt.INVOICEREF = inv.LREF
 AND ISNULL(pt.IOCODE,0)=0
 AND ISNULL(pt.CANCELED,0)=0
{mgrJoin}
WHERE {pred.Replace("@agr", "@agrId")}
  AND ISNULL(inv.IOCODE,0)=0
  AND ISNULL(inv.CANCELED,0)=0
  AND (
        ISNULL(inv.CLOSED,0)=1
     OR ISNULL(pt.PAID,0) + 0.01 >= ISNULL(NULLIF(pt.PAYABLETOTAL,0), inv.PAYABLETOTAL)
     OR EXISTS (
          SELECT 1 FROM izgazMGR.dbo.LS_INVOICE sx WITH (NOLOCK)
           WHERE CAST(sx.ABYS_ACTION_ID AS INT) = inv.LREF
             AND sx.ABYS_AGREEMENT_ID = @agrId
             AND {mgrClosedPred.Replace("s.", "sx.")}
        )
  )
  AND (
        ISNULL(inv.PAYABLETOTAL,0) > 0.01
     OR ISNULL(pt.PAYABLETOTAL,0) > 0.01
     OR ISNULL(inv.TLTOTAL,0) > 0.01
  )
  AND NOT EXISTS (
      SELECT 1 FROM dbo.{prefix}_PAYTRANS pay WITH (NOLOCK)
       WHERE pay.CROSSREF = pt.LREF AND ISNULL(pay.IOCODE,0)=1 AND ISNULL(pay.CANCELED,0)=0
  )
  {skipInstInvSql}
ORDER BY inv.LREF", agr, ct);

        if (candidates.Count == 0)
        {
            var debtCnt = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{prefix}_INVOICE inv WITH (NOLOCK)
 WHERE {pred} AND ISNULL(inv.IOCODE,0)=0", agr, ct);
            var closedCnt = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{prefix}_INVOICE inv WITH (NOLOCK)
 WHERE {pred} AND ISNULL(inv.IOCODE,0)=0 AND ISNULL(inv.CLOSED,0)=1", agr, ct);
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_TAHSILAT_NO_CANDIDATE",
                Severity = "WARN",
                Side = "ENERGY",
                Message =
                    $"Tahsilat zinciri adayı yok (borç={debtCnt} CLOSED={closedCnt}). " +
                    "pilotDumpMgr APPLY yeniden (brüt borç+hesap bakiyesi CLOSED) sonra pilotEnergyChain Clean APPLY."
            });
            return new TahsilatChainResult("DIRECT_EMPTY", 0, 0, 0);
        }

        var invIns = 0;
        var ptIns = 0;
        var closed = 0;

        foreach (var row in candidates)
        {
            var debtInv = Convert.ToInt32(row["DEBT_INV"] ?? 0);
            var debtPt = Convert.ToInt32(row["DEBT_PT"] ?? 0);
            if (debtInv <= 0 || debtPt <= 0) continue;

            var payable = Convert.ToDecimal(row.GetValueOrDefault("PAYABLETOTAL") ?? 0m);
            var curId = row.GetValueOrDefault("CURID") ?? 160;
            var clientRef = row.GetValueOrDefault("CLIENTREF");
            var ownerRef = row.GetValueOrDefault("OWNERREF") ?? agr;
            var ownerType = row.GetValueOrDefault("OWNERTYPE") ?? 91;
            var fiche = Convert.ToString(row.GetValueOrDefault("FICHENO")) ?? $"T{debtInv}";
            var payDate = row.GetValueOrDefault("LASTPAIDDATE") ?? row.GetValueOrDefault("DEBT_DATE") ?? DateTime.Now;
            if (payDate is string ps && DateTime.TryParse(ps, out var pdt)) payDate = pdt;
            var bnType = row.GetValueOrDefault("BN_TYPE");
            var fitno = row.GetValueOrDefault("FITNO");
            var dv = row.GetValueOrDefault("DV") ?? 0d;
            var grand = row.GetValueOrDefault("GRANDTOTAL") ?? payable;
            var tl = row.GetValueOrDefault("TLTOTAL") ?? payable;
            var bankRef = row.GetValueOrDefault("BANKREF");
            var bankRec = Convert.ToString(row.GetValueOrDefault("BANK_RECORD_REF"));
            if (string.IsNullOrWhiteSpace(bankRec)) bankRec = null;

            int newInvLref;
            await using (var cmdInv = new SqlCommand($@"
INSERT INTO dbo.{prefix}_INVOICE (
    FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF, TLTOTAL, CURID, CURTOTAL,
    CANCELED, OWNERREF, OWNERTYPE, IOCODE, GRANDTOTAL, TAX, PAYABLETOTAL,
    ADDDATE, ADDUSER, CLOSED
    {(hasFitno ? ", FITNO" : "")}
    {(hasDv ? ", DV" : "")}
    {(hasBnType ? ", BN_TYPE" : "")}
    {(hasLastPaid ? ", LASTPAIDDATE" : "")}
    {(hasInvBankRef ? ", BANKREF" : "")}
    {(hasInvBankRec ? ", BANK_RECORD_REF" : "")}
)
VALUES (
    @fiche, @payDate, @payDate, 101, @clientRef, @payable, @curId, @payable,
    0, @ownerRef, @ownerType, 1, @grand, 0, @payable,
    GETDATE(), 20001, 0
    {(hasFitno ? ", @fitno" : "")}
    {(hasDv ? ", @dv" : "")}
    {(hasBnType ? ", @bnType" : "")}
    {(hasLastPaid ? ", @payDate" : "")}
    {(hasInvBankRef ? ", @bankRef" : "")}
    {(hasInvBankRec ? ", @bankRec" : "")}
);
SELECT CAST(SCOPE_IDENTITY() AS INT);", conn) { CommandTimeout = 60 })
            {
                cmdInv.Parameters.AddWithValue("@fiche", Left(fiche, 16));
                cmdInv.Parameters.AddWithValue("@payDate", SafeSmallDt(payDate));
                cmdInv.Parameters.AddWithValue("@clientRef", clientRef ?? DBNull.Value);
                cmdInv.Parameters.AddWithValue("@payable", Convert.ToDouble(payable));
                cmdInv.Parameters.AddWithValue("@curId", curId ?? 160);
                cmdInv.Parameters.AddWithValue("@ownerRef", ownerRef ?? agr);
                cmdInv.Parameters.AddWithValue("@ownerType", ownerType ?? 91);
                cmdInv.Parameters.AddWithValue("@grand", Convert.ToDouble(grand));
                if (hasFitno) cmdInv.Parameters.AddWithValue("@fitno", fitno ?? DBNull.Value);
                if (hasDv) cmdInv.Parameters.AddWithValue("@dv", Convert.ToDouble(dv));
                if (hasBnType) cmdInv.Parameters.AddWithValue("@bnType", bnType ?? DBNull.Value);
                if (hasInvBankRef) cmdInv.Parameters.AddWithValue("@bankRef", bankRef ?? DBNull.Value);
                if (hasInvBankRec)
                    cmdInv.Parameters.AddWithValue("@bankRec",
                        string.IsNullOrWhiteSpace(bankRec) ? DBNull.Value : Left(bankRec, 50));
                var idObj = await cmdInv.ExecuteScalarAsync(ct);
                newInvLref = idObj == null || idObj == DBNull.Value ? 0 : Convert.ToInt32(idObj);
            }

            if (newInvLref <= 0) continue;
            invIns++;

            int? newLineLref = null;
            if (hasInvlines)
            {
                try
                {
                    await using var cmdLine = new SqlCommand($@"
INSERT INTO dbo.{prefix}_INVLINES (
    INVOICEREF, CLIENTREF, DATE_, [TYPE], LINENR, TLTOTAL, CURID, CURRATE, CURTOTAL,
    TRANSTYPE, CANCELED, GRANDTOTAL{(hasDv ? ", DV" : "")}{(hasFitno ? ", FITNO" : "")}
)
VALUES (
    @inv, @clientRef, @payDate, 101, 1, @tl, @curId, 1, @payable,
    173, 0, @grand{(hasDv ? ", @dv" : "")}{(hasFitno ? ", @fitno" : "")}
);
SELECT CAST(SCOPE_IDENTITY() AS INT);", conn) { CommandTimeout = 60 };
                    cmdLine.Parameters.AddWithValue("@inv", newInvLref);
                    cmdLine.Parameters.AddWithValue("@clientRef", clientRef ?? DBNull.Value);
                    cmdLine.Parameters.AddWithValue("@payDate", SafeSmallDt(payDate));
                    cmdLine.Parameters.AddWithValue("@tl", Convert.ToDouble(tl));
                    cmdLine.Parameters.AddWithValue("@curId", curId ?? 160);
                    cmdLine.Parameters.AddWithValue("@payable", Convert.ToDouble(payable));
                    cmdLine.Parameters.AddWithValue("@grand", Convert.ToDouble(grand));
                    if (hasDv) cmdLine.Parameters.AddWithValue("@dv", Convert.ToDouble(dv));
                    if (hasFitno) cmdLine.Parameters.AddWithValue("@fitno", fitno ?? DBNull.Value);
                    var lineObj = await cmdLine.ExecuteScalarAsync(ct);
                    if (lineObj != null && lineObj != DBNull.Value)
                        newLineLref = Convert.ToInt32(lineObj);
                }
                catch (Exception exLine)
                {
                    _logger.LogDebug(exLine, "Tahsilat INVLINES skip DebtInv={Debt}", debtInv);
                }
            }

            var cancelPayCol = hasCancelPay ? ", CANCELLATIONPAYMENT" : "";
            var cancelPayVal = hasCancelPay ? ", 0" : "";
            var clientTypeCol = hasClientType ? ", CLIENT_TYPE" : "";
            var clientTypeVal = hasClientType ? ", @ownerType" : "";
            var bnPtCol = hasPtBnType ? ", BN_TYPE" : "";
            var bnPtVal = hasPtBnType ? ", @bnType" : "";
            var bankPtCol = hasPtBankRef ? ", BANKREF" : "";
            var bankPtVal = hasPtBankRef ? ", @bankRef" : "";
            var bankRecPtCol = hasPtBankRec ? ", BANK_RECORD_REF" : "";
            var bankRecPtVal = hasPtBankRec ? ", @bankRec" : "";
            var lpdPtCol = hasPtLastPaid ? ", LASTPAIDDATE" : "";
            var lpdPtVal = hasPtLastPaid ? ", @payDate" : "";
            var xtypePtCol = hasPtXtype ? ", XTYPE" : "";
            var xtypePtVal = hasPtXtype ? ", @xType" : "";
            var xTypeVal = hasInvXtype
                ? (row.GetValueOrDefault("XTYPE") ?? 1)
                : 1;

            await using (var cmdPt = new SqlCommand($@"
INSERT INTO dbo.{prefix}_PAYTRANS (
    INVOICEREF, INVLINEREF, DATE_, [TYPE], CLIENTREF, IOCODE, TLTOTAL, PAID, DUEDATE,
    PAYTYPE, CURID, CURRATE, CURTOTAL, CROSSREF, TRANSTYPE, CANCELED,
    GRANDTOTAL, PAYABLETOTAL, ADDUSER, ADDDATE
    {clientTypeCol}{cancelPayCol}{bnPtCol}{bankPtCol}{bankRecPtCol}{lpdPtCol}{xtypePtCol}
)
VALUES (
    @tahInv, @lineRef, @payDate, 101, @clientRef, 1, @payable, @payable, @payDate,
    174, @curId, 1, @payable, @debtPt, 173, 0,
    @grand, @payable, 20001, GETDATE()
    {clientTypeVal}{cancelPayVal}{bnPtVal}{bankPtVal}{bankRecPtVal}{lpdPtVal}{xtypePtVal}
);", conn) { CommandTimeout = 60 })
            {
                cmdPt.Parameters.AddWithValue("@tahInv", newInvLref);
                cmdPt.Parameters.AddWithValue("@lineRef", (object?)newLineLref ?? DBNull.Value);
                cmdPt.Parameters.AddWithValue("@payDate", SafeSmallDt(payDate));
                cmdPt.Parameters.AddWithValue("@clientRef", clientRef ?? DBNull.Value);
                cmdPt.Parameters.AddWithValue("@payable", Convert.ToDouble(payable));
                cmdPt.Parameters.AddWithValue("@curId", curId ?? 160);
                cmdPt.Parameters.AddWithValue("@debtPt", debtPt);
                cmdPt.Parameters.AddWithValue("@grand", Convert.ToDouble(grand));
                if (hasClientType) cmdPt.Parameters.AddWithValue("@ownerType", ownerType ?? 91);
                if (hasPtBnType) cmdPt.Parameters.AddWithValue("@bnType", bnType ?? DBNull.Value);
                if (hasPtBankRef) cmdPt.Parameters.AddWithValue("@bankRef", bankRef ?? DBNull.Value);
                if (hasPtBankRec)
                    cmdPt.Parameters.AddWithValue("@bankRec",
                        string.IsNullOrWhiteSpace(bankRec) ? DBNull.Value : Left(bankRec, 50));
                if (hasPtXtype) cmdPt.Parameters.AddWithValue("@xType", xTypeVal ?? 1);
                await cmdPt.ExecuteNonQueryAsync(ct);
                ptIns++;
            }

            // Borç kapat + banka alanları (banka SP örneği)
            await using (var upd = new SqlCommand($@"
UPDATE dbo.{prefix}_INVOICE SET
  CLOSED = 1
  {(hasLastPaid ? ", LASTPAIDDATE = @payDate" : "")}
  {(hasInvBankRef ? ", BANKREF = COALESCE(@bankRef, BANKREF)" : "")}
  {(hasInvBankRec ? ", BANK_RECORD_REF = COALESCE(@bankRec, BANK_RECORD_REF)" : "")}
  {(hasInvXtype ? ", XTYPE = COALESCE(XTYPE, @xType)" : "")}
WHERE LREF = @debtInv;
UPDATE dbo.{prefix}_PAYTRANS SET
  PAID = PAYABLETOTAL,
  PAYTYPE = COALESCE(NULLIF(PAYTYPE,0), 174)
  {(hasPtBankRef ? ", BANKREF = COALESCE(@bankRef, BANKREF)" : "")}
  {(hasPtBankRec ? ", BANK_RECORD_REF = COALESCE(@bankRec, BANK_RECORD_REF)" : "")}
  {(hasPtLastPaid ? ", LASTPAIDDATE = @payDate" : "")}
  {(hasPtXtype ? ", XTYPE = COALESCE(@xType, XTYPE, 1)" : "")}
WHERE LREF = @debtPt AND ISNULL(IOCODE,0)=0;", conn) { CommandTimeout = 60 })
            {
                upd.Parameters.AddWithValue("@debtInv", debtInv);
                upd.Parameters.AddWithValue("@debtPt", debtPt);
                upd.Parameters.AddWithValue("@payDate", SafeSmallDt(payDate));
                if (hasInvBankRef || hasPtBankRef)
                    upd.Parameters.AddWithValue("@bankRef", bankRef ?? DBNull.Value);
                if (hasInvBankRec || hasPtBankRec)
                    upd.Parameters.AddWithValue("@bankRec",
                        string.IsNullOrWhiteSpace(bankRec) ? DBNull.Value : Left(bankRec, 50));
                if (hasInvXtype || hasPtXtype)
                    upd.Parameters.AddWithValue("@xType", xTypeVal ?? 1);
                closed += await upd.ExecuteNonQueryAsync(ct) > 0 ? 1 : 0;
            }
        }

        return new TahsilatChainResult("DIRECT", invIns, ptIns, closed);
    }

    /// <summary>
    /// Ödenen taksit satırları:
    /// Öncelik CTAS O57 izgazMGR.LS_INSTALLMENT_PLAN_PAY; yoksa CS_INSTALLMENT_PLAN.PAYMENT_DATE.
    /// borç PT PAID + banka/makbuz/tarih; TYPE=101 tahsilat; hepsi ödendiyse CLOSED.
    /// </summary>
    private async Task<TahsilatChainResult> ApplyInstallmentTahsilatFromPlanAsync(
        SqlConnection conn, string prefix, long agr, bool hasAbysAgr, bool hasOwner,
        List<TahsilatGapItem> gaps, CancellationToken ct)
    {
        var hasInstNr = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "INST_NR", ct);
        if (!hasInstNr)
            return new TahsilatChainResult("SKIP_NO_INST_NR", 0, 0, 0);

        var hasIpp = await ObjectExistsAsync(conn, "izgazMGR.dbo.LS_INSTALLMENT_PLAN_PAY", ct);
        var hasCsPlan = await ObjectExistsAsync(conn, "izgazMGR.dbo.CS_INSTALLMENT_PLAN", ct);
        if (!hasIpp && !hasCsPlan)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_TAKSIT_NO_PLAN_SRC",
                Severity = "WARN",
                Side = "ENERGY",
                Message = "izgazMGR.LS_INSTALLMENT_PLAN_PAY / CS_INSTALLMENT_PLAN yok — taksit tahsilat atlandı."
            });
            return new TahsilatChainResult("SKIP_NO_PLAN", 0, 0, 0);
        }

        var pred = InvAgrPredicate("inv", hasAbysAgr, hasOwner, "@agrId");
        var hasAbysInst = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "ABYS_INSTALLMENT_ID", ct);
        var hasInvPlanRef = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "INSTALLMENT_PLAN_REF", ct);
        var planIdExpr = hasAbysInst && hasInvPlanRef
            ? "COALESCE(inv.ABYS_INSTALLMENT_ID, CAST(NULLIF(inv.INSTALLMENT_PLAN_REF,0) AS BIGINT))"
            : hasAbysInst ? "inv.ABYS_INSTALLMENT_ID"
            : hasInvPlanRef ? "CAST(NULLIF(inv.INSTALLMENT_PLAN_REF,0) AS BIGINT)"
            : "CAST(NULL AS BIGINT)";

        string? orderCol = null;
        string receiptExpr;
        string payDateExpr;
        string bankRefSel;
        string planJoinSql;
        string planSourceTag;

        if (hasIpp)
        {
            planSourceTag = "LS_INSTALLMENT_PLAN_PAY";
            payDateExpr = "ipp.PAYMENT_DATE";
            bankRefSel = "COALESCE(ipp.BANKREF, " + (await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "BANKREF", ct)
                ? "inv.BANKREF" : "CAST(NULL AS INT)") + ") AS BANKREF";
            receiptExpr = "CAST(ipp.BANK_RECORD_REF AS NVARCHAR(50)) COLLATE DATABASE_DEFAULT";
            planJoinSql = $@"
INNER JOIN izgazMGR.dbo.LS_INSTALLMENT_PLAN_PAY ipp WITH (NOLOCK)
  ON ipp.INSTALLMENT_ID = {planIdExpr}
 AND CAST(ipp.ORDER_NUMBER AS INT) = pt.INST_NR
 AND ISNULL(ipp.IS_PAID,0)=1
 AND ipp.PAYMENT_DATE IS NOT NULL
 AND (ipp.AGREEMENT_ID = @agrId OR ipp.AGREEMENT_ID IS NULL)";
        }
        else
        {
            planSourceTag = "CS_INSTALLMENT_PLAN";
            var planCols = await GetMssqlColumnsAsync(conn, "izgazMGR", "dbo", "CS_INSTALLMENT_PLAN", ct);
            orderCol = planCols.Contains("ORDER_NUMBER") ? "ORDER_NUMBER"
                : planCols.Contains("INSTALLMENT_NUMBER") ? "INSTALLMENT_NUMBER" : null;
            if (orderCol == null || !planCols.Contains("PAYMENT_DATE"))
            {
                gaps.Add(new TahsilatGapItem
                {
                    Code = "PILOT_TAKSIT_PLAN_COLS",
                    Severity = "WARN",
                    Side = "ENERGY",
                    Message = "CS_INSTALLMENT_PLAN.ORDER_NUMBER/PAYMENT_DATE yok — taksit tahsilat atlandı."
                });
                return new TahsilatChainResult("SKIP_PLAN_COLS", 0, 0, 0);
            }

            receiptExpr = planCols.Contains("RECEIPT_NUMBER") && planCols.Contains("RECEIPT_SERIAL")
                ? @"COALESCE(
    NULLIF(CAST(ip.RECEIPT_NUMBER AS NVARCHAR(50)) COLLATE DATABASE_DEFAULT, ''),
    NULLIF(CAST(ip.RECEIPT_SERIAL AS NVARCHAR(50)) COLLATE DATABASE_DEFAULT, ''))"
                : planCols.Contains("RECEIPT_NUMBER")
                    ? "CAST(ip.RECEIPT_NUMBER AS NVARCHAR(50))"
                    : planCols.Contains("RECEIPT_SERIAL")
                        ? "CAST(ip.RECEIPT_SERIAL AS NVARCHAR(50))"
                        : "CAST(NULL AS NVARCHAR(50))";

            var hasEnPlanPay = await TableExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", ct)
                && await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_PAYMENT_DATE", ct);
            var enPlanPayJoin = hasEnPlanPay
                ? $@"
LEFT JOIN dbo.{prefix}_INSTALLMENT_PLAN enpl WITH (NOLOCK)
  ON enpl.PAYTRANS_REF = pt.LREF
  OR (enpl.INVOICE_REF = inv.LREF AND ISNULL(enpl.INSTALLMENT_COUNT,0) = pt.INST_NR)"
                : "";
            payDateExpr = hasEnPlanPay
                ? "COALESCE(ip.PAYMENT_DATE, enpl.ABYS_PAYMENT_DATE)"
                : "ip.PAYMENT_DATE";
            bankRefSel = (await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "BANKREF", ct)
                ? "inv.BANKREF" : "CAST(NULL AS INT)") + " AS BANKREF";
            planJoinSql = $@"
INNER JOIN izgazMGR.dbo.CS_INSTALLMENT_PLAN ip WITH (NOLOCK)
  ON ip.INSTALLMENT_ID = {planIdExpr}
 AND CAST(ip.{orderCol} AS INT) = pt.INST_NR
{enPlanPayJoin}";
        }

        // Plan satırında BANK yok — fatura BANKREF; makbuz RECEIPT_* ile BANK_RECORD_REF
        var hasCancelPay = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "CANCELLATIONPAYMENT", ct);
        var hasClientType = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "CLIENT_TYPE", ct);
        var hasBnType = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "BN_TYPE", ct);
        var hasPtBnType = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "BN_TYPE", ct);
        var hasFitno = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "FITNO", ct);
        var hasDv = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "DV", ct);
        var hasInvLastPaid = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "LASTPAIDDATE", ct);
        var hasInvBankRef = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "BANKREF", ct);
        var hasInvBankRec = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "BANK_RECORD_REF", ct);
        var hasInvXtype = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "XTYPE", ct);
        var hasPtBankRef = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "BANKREF", ct);
        var hasPtBankRec = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "BANK_RECORD_REF", ct);
        var hasPtLastPaid = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "LASTPAIDDATE", ct);
        var hasPtXtype = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "XTYPE", ct);
        var hasInvlines = await TableExistsAsync(conn, "dbo", $"{prefix}_INVLINES", ct);

        var candidates = await QueryAsync(conn, $@"
SELECT
  inv.LREF AS DEBT_INV,
  pt.LREF AS DEBT_PT,
  pt.INST_NR,
  CASE WHEN ISNULL(pt.PAYABLETOTAL,0) > 0.01 THEN pt.PAYABLETOTAL
       ELSE inv.PAYABLETOTAL END AS PAYABLETOTAL,
  inv.FICHENO, inv.CLIENTREF, inv.OWNERREF, inv.OWNERTYPE, inv.CURID,
  inv.TLTOTAL, inv.GRANDTOTAL, inv.TAX, inv.DATE_ AS DEBT_DATE,
  {(hasBnType ? "inv.BN_TYPE" : "CAST(NULL AS INT)")} AS BN_TYPE,
  {(hasFitno ? "inv.FITNO" : "CAST(NULL AS BIGINT)")} AS FITNO,
  {(hasDv ? "inv.DV" : "CAST(0 AS FLOAT)")} AS DV,
  {(hasInvXtype ? "ISNULL(inv.XTYPE,1)" : "CAST(1 AS INT)")} AS XTYPE,
  {(hasInvBankRef ? "inv.BANKREF" : "CAST(NULL AS INT)")} AS INV_BANKREF,
  {payDateExpr} AS PAY_DATE,
  {bankRefSel},
  {receiptExpr} AS BANK_RECORD_REF,
  CAST({planIdExpr} AS BIGINT) AS PLAN_ID
FROM dbo.{prefix}_INVOICE inv WITH (NOLOCK)
INNER JOIN dbo.{prefix}_PAYTRANS pt WITH (NOLOCK)
  ON pt.INVOICEREF = inv.LREF
 AND ISNULL(pt.IOCODE,0)=0 AND ISNULL(pt.CANCELED,0)=0
 AND ISNULL(pt.INST_NR,0) > 0
{planJoinSql}
WHERE {pred}
  AND ISNULL(inv.IOCODE,0)=0 AND ISNULL(inv.CANCELED,0)=0
  AND {planIdExpr} IS NOT NULL
  AND {payDateExpr} IS NOT NULL
ORDER BY inv.LREF, pt.INST_NR", agr, ct);

        gaps.Add(new TahsilatGapItem
        {
            Code = "PILOT_TAKSIT_SRC",
            Severity = "INFO",
            Side = "ENERGY",
            Message = $"Taksit tahsilat kaynak={planSourceTag} aday={candidates.Count}."
        });

        // Önce mevcut tahsilat (CROSSREF) satırlarında PAID/banka boşsa doldur — PAYMENT_DATE olmasa da
        var repaired = await RepairExistingInstallmentTahsilatAsync(
            conn, prefix, agr, hasAbysAgr, hasOwner,
            hasPtBankRef, hasPtBankRec, hasPtLastPaid, hasPtXtype,
            hasInvBankRef, hasInvBankRec, hasInvLastPaid, hasInvXtype, ct);

        if (candidates.Count == 0)
        {
            var openInst = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{prefix}_PAYTRANS pt WITH (NOLOCK)
 INNER JOIN dbo.{prefix}_INVOICE inv WITH (NOLOCK) ON inv.LREF = pt.INVOICEREF
 WHERE {pred}
   AND ISNULL(pt.IOCODE,0)=0 AND ISNULL(pt.CANCELED,0)=0 AND ISNULL(pt.INST_NR,0)>0
   AND ISNULL(pt.PAID,0) + 0.01 < ISNULL(pt.PAYABLETOTAL,0)", agr, ct);
            if (openInst > 0 && repaired == 0)
            {
                gaps.Add(new TahsilatGapItem
                {
                    Code = "PILOT_TAKSIT_TAHSILAT_NONE",
                    Severity = "INFO",
                    Side = "ENERGY",
                    Message =
                        $"Taksit borç PT açık≈{openInst} ama {planSourceTag} ödeme eşleşmesi yok."
                });
            }
            return new TahsilatChainResult(repaired > 0 ? "REPAIR" : "DIRECT_EMPTY", 0, 0, 0, repaired);
        }

        var invIns = 0;
        var ptIns = 0;
        var updated = 0;
        var touchedInv = new HashSet<int>();

        foreach (var row in candidates)
        {
            var debtInv = Convert.ToInt32(row["DEBT_INV"] ?? 0);
            var debtPt = Convert.ToInt32(row["DEBT_PT"] ?? 0);
            var instNr = Convert.ToInt32(row.GetValueOrDefault("INST_NR") ?? 0);
            if (debtInv <= 0 || debtPt <= 0 || instNr <= 0) continue;

            var payable = Convert.ToDecimal(row.GetValueOrDefault("PAYABLETOTAL") ?? 0m);
            if (payable < 0.01m) continue;

            var payDate = row.GetValueOrDefault("PAY_DATE") ?? row.GetValueOrDefault("DEBT_DATE") ?? DateTime.Now;
            if (payDate is string ps && DateTime.TryParse(ps, out var pdt)) payDate = pdt;
            var bankRef = row.GetValueOrDefault("BANKREF") ?? row.GetValueOrDefault("INV_BANKREF");
            var bankRec = Convert.ToString(row.GetValueOrDefault("BANK_RECORD_REF"));
            if (string.IsNullOrWhiteSpace(bankRec)) bankRec = null;
            var curId = row.GetValueOrDefault("CURID") ?? 160;
            var clientRef = row.GetValueOrDefault("CLIENTREF");
            var ownerRef = row.GetValueOrDefault("OWNERREF") ?? agr;
            var ownerType = row.GetValueOrDefault("OWNERTYPE") ?? 91;
            var fiche = Convert.ToString(row.GetValueOrDefault("FICHENO")) ?? $"T{debtInv}";
            var bnType = row.GetValueOrDefault("BN_TYPE");
            var fitno = row.GetValueOrDefault("FITNO");
            var dv = row.GetValueOrDefault("DV") ?? 0d;
            var grand = row.GetValueOrDefault("GRANDTOTAL") ?? payable;
            var tl = row.GetValueOrDefault("TLTOTAL") ?? payable;
            var xType = row.GetValueOrDefault("XTYPE") ?? 1;

            // Mevcut tahsilat PT varsa sadece PAID/banka/tarih doldur
            long existingPayLref;
            await using (var findPay = new SqlCommand($@"
SELECT TOP 1 LREF FROM dbo.{prefix}_PAYTRANS WITH (NOLOCK)
 WHERE CROSSREF = @debtPt AND ISNULL(IOCODE,0)=1 AND ISNULL(CANCELED,0)=0", conn))
            {
                findPay.Parameters.AddWithValue("@debtPt", debtPt);
                var o = await findPay.ExecuteScalarAsync(ct);
                existingPayLref = o == null || o == DBNull.Value ? 0L : Convert.ToInt64(o);
            }

            if (existingPayLref > 0)
            {
                await using var updPay = new SqlCommand($@"
UPDATE dbo.{prefix}_PAYTRANS SET
  PAID = PAYABLETOTAL,
  PAYTYPE = COALESCE(NULLIF(PAYTYPE,0), 174),
  DATE_ = COALESCE(DATE_, @payDate)
  {(hasPtBankRef ? ", BANKREF = COALESCE(@bankRef, BANKREF)" : "")}
  {(hasPtBankRec ? ", BANK_RECORD_REF = COALESCE(@bankRec, BANK_RECORD_REF)" : "")}
  {(hasPtLastPaid ? ", LASTPAIDDATE = @payDate" : "")}
  {(hasPtXtype ? ", XTYPE = COALESCE(@xType, XTYPE, 1)" : "")}
WHERE LREF = @payPt;
UPDATE dbo.{prefix}_PAYTRANS SET
  PAID = PAYABLETOTAL,
  PAYTYPE = COALESCE(NULLIF(PAYTYPE,0), 120)
  {(hasPtBankRef ? ", BANKREF = COALESCE(@bankRef, BANKREF)" : "")}
  {(hasPtBankRec ? ", BANK_RECORD_REF = COALESCE(@bankRec, BANK_RECORD_REF)" : "")}
  {(hasPtLastPaid ? ", LASTPAIDDATE = @payDate" : "")}
  {(hasPtXtype ? ", XTYPE = COALESCE(@xType, XTYPE, 1)" : "")}
WHERE LREF = @debtPt AND ISNULL(IOCODE,0)=0;", conn) { CommandTimeout = 60 };
                updPay.Parameters.AddWithValue("@payPt", existingPayLref);
                updPay.Parameters.AddWithValue("@debtPt", debtPt);
                updPay.Parameters.AddWithValue("@payDate", SafeSmallDt(payDate));
                if (hasPtBankRef) updPay.Parameters.AddWithValue("@bankRef", bankRef ?? DBNull.Value);
                if (hasPtBankRec)
                    updPay.Parameters.AddWithValue("@bankRec",
                        string.IsNullOrWhiteSpace(bankRec) ? DBNull.Value : Left(bankRec!, 50));
                if (hasPtXtype) updPay.Parameters.AddWithValue("@xType", xType ?? 1);
                updated += await updPay.ExecuteNonQueryAsync(ct) > 0 ? 1 : 0;
                touchedInv.Add(debtInv);
                continue;
            }

            int newInvLref;
            await using (var cmdInv = new SqlCommand($@"
INSERT INTO dbo.{prefix}_INVOICE (
    FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF, TLTOTAL, CURID, CURTOTAL,
    CANCELED, OWNERREF, OWNERTYPE, IOCODE, GRANDTOTAL, TAX, PAYABLETOTAL,
    ADDDATE, ADDUSER, CLOSED
    {(hasFitno ? ", FITNO" : "")}
    {(hasDv ? ", DV" : "")}
    {(hasBnType ? ", BN_TYPE" : "")}
    {(hasInvLastPaid ? ", LASTPAIDDATE" : "")}
    {(hasInvBankRef ? ", BANKREF" : "")}
    {(hasInvBankRec ? ", BANK_RECORD_REF" : "")}
    {(hasInvXtype ? ", XTYPE" : "")}
)
VALUES (
    @fiche, @payDate, @payDate, 101, @clientRef, @payable, @curId, @payable,
    0, @ownerRef, @ownerType, 1, @grand, 0, @payable,
    GETDATE(), 20001, 0
    {(hasFitno ? ", @fitno" : "")}
    {(hasDv ? ", @dv" : "")}
    {(hasBnType ? ", @bnType" : "")}
    {(hasInvLastPaid ? ", @payDate" : "")}
    {(hasInvBankRef ? ", @bankRef" : "")}
    {(hasInvBankRec ? ", @bankRec" : "")}
    {(hasInvXtype ? ", @xType" : "")}
);
SELECT CAST(SCOPE_IDENTITY() AS INT);", conn) { CommandTimeout = 60 })
            {
                cmdInv.Parameters.AddWithValue("@fiche", Left($"T{instNr}-{fiche}", 16));
                cmdInv.Parameters.AddWithValue("@payDate", SafeSmallDt(payDate));
                cmdInv.Parameters.AddWithValue("@clientRef", clientRef ?? DBNull.Value);
                cmdInv.Parameters.AddWithValue("@payable", Convert.ToDouble(payable));
                cmdInv.Parameters.AddWithValue("@curId", curId ?? 160);
                cmdInv.Parameters.AddWithValue("@ownerRef", ownerRef ?? agr);
                cmdInv.Parameters.AddWithValue("@ownerType", ownerType ?? 91);
                cmdInv.Parameters.AddWithValue("@grand", Convert.ToDouble(grand));
                if (hasFitno) cmdInv.Parameters.AddWithValue("@fitno", fitno ?? DBNull.Value);
                if (hasDv) cmdInv.Parameters.AddWithValue("@dv", Convert.ToDouble(dv));
                if (hasBnType) cmdInv.Parameters.AddWithValue("@bnType", bnType ?? DBNull.Value);
                if (hasInvBankRef) cmdInv.Parameters.AddWithValue("@bankRef", bankRef ?? DBNull.Value);
                if (hasInvBankRec)
                    cmdInv.Parameters.AddWithValue("@bankRec",
                        string.IsNullOrWhiteSpace(bankRec) ? DBNull.Value : Left(bankRec!, 50));
                if (hasInvXtype) cmdInv.Parameters.AddWithValue("@xType", xType ?? 1);
                var idObj = await cmdInv.ExecuteScalarAsync(ct);
                newInvLref = idObj == null || idObj == DBNull.Value ? 0 : Convert.ToInt32(idObj);
            }

            if (newInvLref <= 0) continue;
            invIns++;

            int? newLineLref = null;
            if (hasInvlines)
            {
                try
                {
                    await using var cmdLine = new SqlCommand($@"
INSERT INTO dbo.{prefix}_INVLINES (
    INVOICEREF, CLIENTREF, DATE_, [TYPE], LINENR, TLTOTAL, CURID, CURRATE, CURTOTAL,
    TRANSTYPE, CANCELED, GRANDTOTAL{(hasDv ? ", DV" : "")}{(hasFitno ? ", FITNO" : "")}
)
VALUES (
    @inv, @clientRef, @payDate, 101, 1, @tl, @curId, 1, @payable,
    173, 0, @grand{(hasDv ? ", @dv" : "")}{(hasFitno ? ", @fitno" : "")}
);
SELECT CAST(SCOPE_IDENTITY() AS INT);", conn) { CommandTimeout = 60 };
                    cmdLine.Parameters.AddWithValue("@inv", newInvLref);
                    cmdLine.Parameters.AddWithValue("@clientRef", clientRef ?? DBNull.Value);
                    cmdLine.Parameters.AddWithValue("@payDate", SafeSmallDt(payDate));
                    cmdLine.Parameters.AddWithValue("@tl", Convert.ToDouble(tl));
                    cmdLine.Parameters.AddWithValue("@curId", curId ?? 160);
                    cmdLine.Parameters.AddWithValue("@payable", Convert.ToDouble(payable));
                    cmdLine.Parameters.AddWithValue("@grand", Convert.ToDouble(grand));
                    if (hasDv) cmdLine.Parameters.AddWithValue("@dv", Convert.ToDouble(dv));
                    if (hasFitno) cmdLine.Parameters.AddWithValue("@fitno", fitno ?? DBNull.Value);
                    var lineObj = await cmdLine.ExecuteScalarAsync(ct);
                    if (lineObj != null && lineObj != DBNull.Value)
                        newLineLref = Convert.ToInt32(lineObj);
                }
                catch (Exception exLine)
                {
                    _logger.LogDebug(exLine, "Taksit tahsilat INVLINES skip DebtInv={Debt} Inst={N}", debtInv, instNr);
                }
            }

            await using (var cmdPt = new SqlCommand($@"
INSERT INTO dbo.{prefix}_PAYTRANS (
    INVOICEREF, INVLINEREF, DATE_, [TYPE], CLIENTREF, IOCODE, TLTOTAL, PAID, DUEDATE,
    PAYTYPE, CURID, CURRATE, CURTOTAL, CROSSREF, TRANSTYPE, CANCELED,
    GRANDTOTAL, PAYABLETOTAL, ADDUSER, ADDDATE, INST_NR
    {(hasClientType ? ", CLIENT_TYPE" : "")}
    {(hasCancelPay ? ", CANCELLATIONPAYMENT" : "")}
    {(hasPtBnType ? ", BN_TYPE" : "")}
    {(hasPtBankRef ? ", BANKREF" : "")}
    {(hasPtBankRec ? ", BANK_RECORD_REF" : "")}
    {(hasPtLastPaid ? ", LASTPAIDDATE" : "")}
    {(hasPtXtype ? ", XTYPE" : "")}
)
VALUES (
    @tahInv, @lineRef, @payDate, 101, @clientRef, 1, @payable, @payable, @payDate,
    174, @curId, 1, @payable, @debtPt, 173, 0,
    @grand, @payable, 20001, GETDATE(), @instNr
    {(hasClientType ? ", @ownerType" : "")}
    {(hasCancelPay ? ", 0" : "")}
    {(hasPtBnType ? ", @bnType" : "")}
    {(hasPtBankRef ? ", @bankRef" : "")}
    {(hasPtBankRec ? ", @bankRec" : "")}
    {(hasPtLastPaid ? ", @payDate" : "")}
    {(hasPtXtype ? ", @xType" : "")}
);", conn) { CommandTimeout = 60 })
            {
                cmdPt.Parameters.AddWithValue("@tahInv", newInvLref);
                cmdPt.Parameters.AddWithValue("@lineRef", (object?)newLineLref ?? DBNull.Value);
                cmdPt.Parameters.AddWithValue("@payDate", SafeSmallDt(payDate));
                cmdPt.Parameters.AddWithValue("@clientRef", clientRef ?? DBNull.Value);
                cmdPt.Parameters.AddWithValue("@payable", Convert.ToDouble(payable));
                cmdPt.Parameters.AddWithValue("@curId", curId ?? 160);
                cmdPt.Parameters.AddWithValue("@debtPt", debtPt);
                cmdPt.Parameters.AddWithValue("@grand", Convert.ToDouble(grand));
                cmdPt.Parameters.AddWithValue("@instNr", instNr);
                if (hasClientType) cmdPt.Parameters.AddWithValue("@ownerType", ownerType ?? 91);
                if (hasPtBnType) cmdPt.Parameters.AddWithValue("@bnType", bnType ?? DBNull.Value);
                if (hasPtBankRef) cmdPt.Parameters.AddWithValue("@bankRef", bankRef ?? DBNull.Value);
                if (hasPtBankRec)
                    cmdPt.Parameters.AddWithValue("@bankRec",
                        string.IsNullOrWhiteSpace(bankRec) ? DBNull.Value : Left(bankRec!, 50));
                if (hasPtXtype) cmdPt.Parameters.AddWithValue("@xType", xType ?? 1);
                await cmdPt.ExecuteNonQueryAsync(ct);
                ptIns++;
            }

            await using (var updDebt = new SqlCommand($@"
UPDATE dbo.{prefix}_PAYTRANS SET
  PAID = PAYABLETOTAL,
  PAYTYPE = COALESCE(NULLIF(PAYTYPE,0), 120)
  {(hasPtBankRef ? ", BANKREF = COALESCE(@bankRef, BANKREF)" : "")}
  {(hasPtBankRec ? ", BANK_RECORD_REF = COALESCE(@bankRec, BANK_RECORD_REF)" : "")}
  {(hasPtLastPaid ? ", LASTPAIDDATE = @payDate" : "")}
  {(hasPtXtype ? ", XTYPE = COALESCE(@xType, XTYPE, 1)" : "")}
WHERE LREF = @debtPt AND ISNULL(IOCODE,0)=0;", conn) { CommandTimeout = 60 })
            {
                updDebt.Parameters.AddWithValue("@debtPt", debtPt);
                updDebt.Parameters.AddWithValue("@payDate", SafeSmallDt(payDate));
                if (hasPtBankRef) updDebt.Parameters.AddWithValue("@bankRef", bankRef ?? DBNull.Value);
                if (hasPtBankRec)
                    updDebt.Parameters.AddWithValue("@bankRec",
                        string.IsNullOrWhiteSpace(bankRec) ? DBNull.Value : Left(bankRec!, 50));
                if (hasPtXtype) updDebt.Parameters.AddWithValue("@xType", xType ?? 1);
                await updDebt.ExecuteNonQueryAsync(ct);
            }

            touchedInv.Add(debtInv);
        }

        // Tüm taksitler ödendiyse faturayı kapat — LASTPAIDDATE/BANKREF = son ödenen taksit
        var closed = 0;
        foreach (var invLref in touchedInv)
        {
            await using var closeCmd = new SqlCommand($@"
;WITH debt AS (
  SELECT pt.LREF, pt.PAID, pt.PAYABLETOTAL, pt.INST_NR,
         {(hasPtLastPaid ? "pt.LASTPAIDDATE" : "CAST(NULL AS DATETIME)")} AS LPD,
         {(hasPtBankRef ? "pt.BANKREF" : "CAST(NULL AS INT)")} AS BANKREF,
         {(hasPtBankRec ? "pt.BANK_RECORD_REF" : "CAST(NULL AS NVARCHAR(50))")} AS BANK_RECORD_REF
    FROM dbo.{prefix}_PAYTRANS pt WITH (NOLOCK)
   WHERE pt.INVOICEREF = @inv AND ISNULL(pt.IOCODE,0)=0 AND ISNULL(pt.CANCELED,0)=0
     AND ISNULL(pt.INST_NR,0) > 0
),
agg AS (
  SELECT
    COUNT(*) AS N,
    SUM(CASE WHEN ISNULL(PAID,0)+0.01 >= ISNULL(PAYABLETOTAL,0) THEN 1 ELSE 0 END) AS PAID_N,
    MAX(LPD) AS MAX_LPD
  FROM debt
),
lastPay AS (
  SELECT TOP 1 BANKREF, BANK_RECORD_REF, LPD
    FROM debt
   WHERE ISNULL(PAID,0)+0.01 >= ISNULL(PAYABLETOTAL,0)
   ORDER BY ISNULL(LPD, '19000101') DESC, INST_NR DESC
)
UPDATE inv SET
  inv.CLOSED = CASE WHEN a.N > 0 AND a.N = a.PAID_N THEN CAST(1 AS BIT) ELSE inv.CLOSED END
  {(hasInvLastPaid ? ", inv.LASTPAIDDATE = COALESCE(lp.LPD, a.MAX_LPD, inv.LASTPAIDDATE)" : "")}
  {(hasInvBankRef ? ", inv.BANKREF = COALESCE(lp.BANKREF, inv.BANKREF)" : "")}
  {(hasInvBankRec ? ", inv.BANK_RECORD_REF = COALESCE(lp.BANK_RECORD_REF, inv.BANK_RECORD_REF)" : "")}
FROM dbo.{prefix}_INVOICE inv
CROSS JOIN agg a
LEFT JOIN lastPay lp ON 1=1
WHERE inv.LREF = @inv
  AND a.N > 0 AND a.N = a.PAID_N;", conn) { CommandTimeout = 60 };
            closeCmd.Parameters.AddWithValue("@inv", invLref);
            closed += await closeCmd.ExecuteNonQueryAsync(ct) > 0 ? 1 : 0;
        }

        gaps.Add(new TahsilatGapItem
        {
            Code = "PILOT_TAKSIT_TAHSILAT",
            Severity = "INFO",
            Side = "ENERGY",
            Message =
                $"Taksit tahsilat: aday={candidates.Count} yeniPT={ptIns} güncellenen={updated} " +
                $"CLOSED={closed}."
        });

        return new TahsilatChainResult("INST_PLAN", invIns, ptIns, closed, updated + repaired);
    }

    /// <summary>
    /// Mevcut taksit tahsilat zincirinde PAID=0 kalan debt/pay PT'leri doldurur.
    /// </summary>
    private async Task<int> RepairExistingInstallmentTahsilatAsync(
        SqlConnection conn, string prefix, long agr, bool hasAbysAgr, bool hasOwner,
        bool hasPtBankRef, bool hasPtBankRec, bool hasPtLastPaid, bool hasPtXtype,
        bool hasInvBankRef, bool hasInvBankRec, bool hasInvLastPaid, bool hasInvXtype,
        CancellationToken ct)
    {
        var pred = InvAgrPredicate("inv", hasAbysAgr, hasOwner, "@agr");
        var payXtype = hasPtXtype
            ? (hasInvXtype
                ? ", pay.XTYPE = COALESCE(pay.XTYPE, inv.XTYPE, 1)"
                : ", pay.XTYPE = COALESCE(pay.XTYPE, 1)")
            : "";
        var debtXtype = hasPtXtype
            ? (hasInvXtype
                ? ", debt.XTYPE = COALESCE(debt.XTYPE, pay.XTYPE, inv.XTYPE, 1)"
                : ", debt.XTYPE = COALESCE(debt.XTYPE, pay.XTYPE, 1)")
            : "";
        var payBankRec = hasPtBankRec
            ? (hasInvBankRec
                ? ", pay.BANK_RECORD_REF = COALESCE(pay.BANK_RECORD_REF, inv.BANK_RECORD_REF)"
                : ", pay.BANK_RECORD_REF = pay.BANK_RECORD_REF")
            : "";
        if (hasPtBankRec && !hasInvBankRec)
            payBankRec = ""; // keep existing
        var payBankRef = hasPtBankRef
            ? (hasInvBankRef
                ? ", pay.BANKREF = COALESCE(pay.BANKREF, inv.BANKREF)"
                : "")
            : "";
        var payLpd = hasPtLastPaid
            ? (hasInvLastPaid
                ? ", pay.LASTPAIDDATE = COALESCE(pay.LASTPAIDDATE, pay.DATE_, inv.LASTPAIDDATE)"
                : ", pay.LASTPAIDDATE = COALESCE(pay.LASTPAIDDATE, pay.DATE_)")
            : "";

        await using var cmd = new SqlCommand($@"
UPDATE pay SET
  pay.PAID = pay.PAYABLETOTAL,
  pay.PAYTYPE = COALESCE(NULLIF(pay.PAYTYPE,0), 174)
  {payLpd}{payBankRef}{payBankRec}{payXtype}
FROM dbo.{prefix}_PAYTRANS pay
INNER JOIN dbo.{prefix}_PAYTRANS debt ON debt.LREF = pay.CROSSREF
INNER JOIN dbo.{prefix}_INVOICE inv ON inv.LREF = debt.INVOICEREF
WHERE {pred}
  AND ISNULL(pay.IOCODE,0)=1 AND ISNULL(pay.CANCELED,0)=0
  AND ISNULL(debt.IOCODE,0)=0 AND ISNULL(debt.CANCELED,0)=0
  AND ISNULL(debt.INST_NR,0) > 0
  AND ISNULL(pay.PAID,0) + 0.01 < ISNULL(pay.PAYABLETOTAL,0);

UPDATE debt SET
  debt.PAID = debt.PAYABLETOTAL,
  debt.PAYTYPE = COALESCE(NULLIF(debt.PAYTYPE,0), 120)
  {(hasPtLastPaid ? ", debt.LASTPAIDDATE = COALESCE(debt.LASTPAIDDATE, pay.DATE_" + (hasInvLastPaid ? ", inv.LASTPAIDDATE" : "") + ")" : "")}
  {(hasPtBankRef ? ", debt.BANKREF = COALESCE(debt.BANKREF, pay.BANKREF" + (hasInvBankRef ? ", inv.BANKREF" : "") + ")" : "")}
  {(hasPtBankRec ? ", debt.BANK_RECORD_REF = COALESCE(debt.BANK_RECORD_REF, pay.BANK_RECORD_REF" + (hasInvBankRec ? ", inv.BANK_RECORD_REF" : "") + ")" : "")}
  {debtXtype}
FROM dbo.{prefix}_PAYTRANS debt
INNER JOIN dbo.{prefix}_PAYTRANS pay ON pay.CROSSREF = debt.LREF AND ISNULL(pay.IOCODE,0)=1 AND ISNULL(pay.CANCELED,0)=0
INNER JOIN dbo.{prefix}_INVOICE inv ON inv.LREF = debt.INVOICEREF
WHERE {pred}
  AND ISNULL(debt.IOCODE,0)=0 AND ISNULL(debt.CANCELED,0)=0
  AND ISNULL(debt.INST_NR,0) > 0
  AND ISNULL(debt.PAID,0) + 0.01 < ISNULL(debt.PAYABLETOTAL,0);

;WITH debt AS (
  SELECT inv.LREF AS INV_LREF, pt.INST_NR, pt.PAID, pt.PAYABLETOTAL,
         {(hasPtLastPaid ? "pt.LASTPAIDDATE" : "CAST(NULL AS DATETIME)")} AS LPD,
         {(hasPtBankRef ? "pt.BANKREF" : "CAST(NULL AS INT)")} AS BANKREF,
         {(hasPtBankRec ? "CAST(pt.BANK_RECORD_REF AS NVARCHAR(50))" : "CAST(NULL AS NVARCHAR(50))")} AS BANK_RECORD_REF
    FROM dbo.{prefix}_INVOICE inv WITH (NOLOCK)
   INNER JOIN dbo.{prefix}_PAYTRANS pt WITH (NOLOCK)
      ON pt.INVOICEREF = inv.LREF AND ISNULL(pt.IOCODE,0)=0 AND ISNULL(pt.CANCELED,0)=0
     AND ISNULL(pt.INST_NR,0) > 0
   WHERE {pred}
),
agg AS (
  SELECT INV_LREF,
         COUNT(*) AS N,
         SUM(CASE WHEN ISNULL(PAID,0)+0.01 >= ISNULL(PAYABLETOTAL,0) THEN 1 ELSE 0 END) AS PAID_N
    FROM debt GROUP BY INV_LREF
),
lastPay AS (
  SELECT d.INV_LREF, d.BANKREF, d.BANK_RECORD_REF, d.LPD,
         ROW_NUMBER() OVER (PARTITION BY d.INV_LREF ORDER BY ISNULL(d.LPD,'19000101') DESC, d.INST_NR DESC) AS rn
    FROM debt d
   WHERE ISNULL(d.PAID,0)+0.01 >= ISNULL(d.PAYABLETOTAL,0)
)
UPDATE inv SET
  inv.CLOSED = 1
  {(hasInvLastPaid ? ", inv.LASTPAIDDATE = COALESCE(lp.LPD, inv.LASTPAIDDATE)" : "")}
  {(hasInvBankRef ? ", inv.BANKREF = COALESCE(lp.BANKREF, inv.BANKREF)" : "")}
  {(hasInvBankRec ? ", inv.BANK_RECORD_REF = COALESCE(lp.BANK_RECORD_REF, inv.BANK_RECORD_REF)" : "")}
FROM dbo.{prefix}_INVOICE inv
INNER JOIN agg a ON a.INV_LREF = inv.LREF AND a.N > 0 AND a.N = a.PAID_N
LEFT JOIN lastPay lp ON lp.INV_LREF = inv.LREF AND lp.rn = 1
WHERE ISNULL(inv.CLOSED,0)=0;", conn) { CommandTimeout = 180 };
        cmd.Parameters.AddWithValue("@agr", agr);
        try { return await cmd.ExecuteNonQueryAsync(ct); }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "RepairExistingInstallmentTahsilat Agr={Agr}", agr);
            return 0;
        }
    }

    private sealed record TaksitSplitResult(string Mode, int PtInserted, int PlansWired);

    /// <summary>
    /// ENERGY faturalarına INSTALLMENT_PLAN_REF + ABYS_INSTALLMENT_ID basar (izgazMGR / hesap taksiti).
    /// 611b yalnızca plan.INVOICE_REF yazar — fatura PLAN_REF boş kalırdı.
    /// </summary>
    private async Task<int> WireInvoiceInstallmentRefsAsync(
        SqlConnection conn, string prefix, long agr, bool hasAbysAgr, bool hasOwner,
        List<TahsilatGapItem> gaps, CancellationToken ct)
    {
        var hasPlanRef = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "INSTALLMENT_PLAN_REF", ct);
        var hasAbysInst = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "ABYS_INSTALLMENT_ID", ct);
        if (!hasPlanRef && !hasAbysInst) return 0;

        var pred = InvAgrPredicate("inv", hasAbysAgr, hasOwner, "@agr");
        var n = 0;

        // 1) izgazMGR.LS_INVOICE → ENERGY (LREF = ABYS_ACTION_ID)
        if (await ObjectExistsAsync(conn, "izgazMGR.dbo.LS_INVOICE", ct))
        {
            var mgrHasAbys = await MgrColumnExistsAsync(conn, "LS_INVOICE", "ABYS_INSTALLMENT_ID", ct);
            var mgrHasPlan = await MgrColumnExistsAsync(conn, "LS_INVOICE", "INSTALLMENT_PLAN_REF", ct);
            if (mgrHasAbys || mgrHasPlan)
            {
                var setParts = new List<string>();
                if (hasAbysInst && mgrHasAbys)
                    setParts.Add("inv.ABYS_INSTALLMENT_ID = COALESCE(inv.ABYS_INSTALLMENT_ID, s.ABYS_INSTALLMENT_ID)");
                if (hasPlanRef)
                {
                    if (mgrHasPlan && mgrHasAbys)
                        setParts.Add(
                            "inv.INSTALLMENT_PLAN_REF = COALESCE(NULLIF(inv.INSTALLMENT_PLAN_REF,0), NULLIF(s.INSTALLMENT_PLAN_REF,0), s.ABYS_INSTALLMENT_ID)");
                    else if (mgrHasPlan)
                        setParts.Add(
                            "inv.INSTALLMENT_PLAN_REF = COALESCE(NULLIF(inv.INSTALLMENT_PLAN_REF,0), s.INSTALLMENT_PLAN_REF)");
                    else if (mgrHasAbys)
                        setParts.Add(
                            "inv.INSTALLMENT_PLAN_REF = COALESCE(NULLIF(inv.INSTALLMENT_PLAN_REF,0), s.ABYS_INSTALLMENT_ID)");
                }

                if (setParts.Count > 0)
                {
                    await using var cmd = new SqlCommand($@"
UPDATE inv SET {string.Join(",\n  ", setParts)}
  FROM dbo.{prefix}_INVOICE inv
 INNER JOIN izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
    ON CAST(s.ABYS_ACTION_ID AS INT) = inv.LREF
   AND s.ABYS_AGREEMENT_ID = @agr
 WHERE {pred}
   AND ISNULL(inv.IOCODE,0)=0
   AND (
        {(mgrHasAbys ? "s.ABYS_INSTALLMENT_ID IS NOT NULL" : "1=0")}
     OR {(mgrHasPlan ? "NULLIF(s.INSTALLMENT_PLAN_REF,0) IS NOT NULL" : "1=0")}
   )", conn) { CommandTimeout = 180 };
                    cmd.Parameters.AddWithValue("@agr", agr);
                    n += await cmd.ExecuteNonQueryAsync(ct);
                }
            }
        }

        // 2) ABYS_INSTALLMENT_ID dolu ama PLAN_REF boş → PLAN_REF = ABYS_INSTALLMENT_ID (SP_TAKSIT / 611 PLAN_ID)
        if (hasPlanRef && hasAbysInst)
        {
            await using var cmd2 = new SqlCommand($@"
UPDATE inv SET inv.INSTALLMENT_PLAN_REF = CAST(inv.ABYS_INSTALLMENT_ID AS INT)
  FROM dbo.{prefix}_INVOICE inv
 WHERE {pred}
   AND ISNULL(inv.IOCODE,0)=0
   AND inv.ABYS_INSTALLMENT_ID IS NOT NULL
   AND ISNULL(inv.INSTALLMENT_PLAN_REF,0)=0", conn) { CommandTimeout = 120 };
            cmd2.Parameters.AddWithValue("@agr", agr);
            n += await cmd2.ExecuteNonQueryAsync(ct);
        }

        // 3) izgazMGR CS_INSTALLMENT → hesap (ABYS_ACCOUNT_ID) üzerinden backfill
        if (hasAbysInst && await ObjectExistsAsync(conn, "izgazMGR.dbo.CS_INSTALLMENT", ct)
            && await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "ABYS_ACCOUNT_ID", ct))
        {
            // LS_INVOICE üzerinde ABYS_ACCOUNT_ID + ABYS_INSTALLMENT_ID zaten varsa yukarıda doldu.
            // Hesap→taksit: mgr invoice satırlarından account başına installment
            if (await ObjectExistsAsync(conn, "izgazMGR.dbo.LS_INVOICE", ct)
                && await MgrColumnExistsAsync(conn, "LS_INVOICE", "ABYS_ACCOUNT_ID", ct)
                && await MgrColumnExistsAsync(conn, "LS_INVOICE", "ABYS_INSTALLMENT_ID", ct))
            {
                await using var cmd3 = new SqlCommand($@"
UPDATE inv SET
  inv.ABYS_INSTALLMENT_ID = COALESCE(inv.ABYS_INSTALLMENT_ID, m.ABYS_INSTALLMENT_ID)
  {(hasPlanRef ? ", inv.INSTALLMENT_PLAN_REF = COALESCE(NULLIF(inv.INSTALLMENT_PLAN_REF,0), CAST(m.ABYS_INSTALLMENT_ID AS INT))" : "")}
  FROM dbo.{prefix}_INVOICE inv
 INNER JOIN (
      SELECT ABYS_ACCOUNT_ID, MAX(ABYS_INSTALLMENT_ID) AS ABYS_INSTALLMENT_ID
        FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
       WHERE ABYS_AGREEMENT_ID = @agr
         AND ABYS_INSTALLMENT_ID IS NOT NULL
         AND ABYS_ACCOUNT_ID IS NOT NULL
       GROUP BY ABYS_ACCOUNT_ID
  ) m ON m.ABYS_ACCOUNT_ID = inv.ABYS_ACCOUNT_ID
 WHERE {pred}
   AND ISNULL(inv.IOCODE,0)=0
   AND (inv.ABYS_INSTALLMENT_ID IS NULL OR ISNULL(inv.INSTALLMENT_PLAN_REF,0)=0)", conn)
                { CommandTimeout = 180 };
                cmd3.Parameters.AddWithValue("@agr", agr);
                n += await cmd3.ExecuteNonQueryAsync(ct);
            }
        }

        // 4) Plan.INVOICE_REF doldur (WIRE SP yoksa / eksik kaldıysa)
        if (await TableExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", ct) && hasAbysInst)
        {
            var hasPlanAbysInst = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_INSTALLMENT_ID", ct);
            var hasPlanAbysAgr = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_AGREEMENT_ID", ct);
            var hasPlanOwner = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "OWNERREF", ct);
            var planAgrPred = hasPlanAbysAgr && hasPlanOwner
                ? "(pl.ABYS_AGREEMENT_ID = @agr OR pl.OWNERREF = @agr)"
                : hasPlanAbysAgr ? "pl.ABYS_AGREEMENT_ID = @agr"
                : hasPlanOwner ? "pl.OWNERREF = @agr"
                : "1=1";
            await using var cmd4 = new SqlCommand($@"
UPDATE pl SET
  pl.INVOICE_REF = inv.LREF,
  pl.INVOICE_OLD_DUEDATE = ISNULL(pl.INVOICE_OLD_DUEDATE, inv.DUEDATE)
  FROM dbo.{prefix}_INSTALLMENT_PLAN pl
 INNER JOIN (
      SELECT ABYS_INSTALLMENT_ID, LREF, DUEDATE,
             ROW_NUMBER() OVER (PARTITION BY ABYS_INSTALLMENT_ID ORDER BY LREF) AS rn
        FROM dbo.{prefix}_INVOICE WITH (NOLOCK)
       WHERE {(hasAbysAgr ? "ABYS_AGREEMENT_ID = @agr" : "OWNERREF = @agr")}
         AND ABYS_INSTALLMENT_ID IS NOT NULL
         AND ISNULL(IOCODE,0)=0
  ) inv ON inv.rn = 1 AND (
        pl.PLAN_ID = inv.ABYS_INSTALLMENT_ID
     OR {(hasPlanAbysInst ? "pl.ABYS_INSTALLMENT_ID = inv.ABYS_INSTALLMENT_ID" : "1=0")}
  )
 WHERE pl.INVOICE_REF IS NULL
   AND {planAgrPred}", conn)
            { CommandTimeout = 180 };
            cmd4.Parameters.AddWithValue("@agr", agr);
            try { n += await cmd4.ExecuteNonQueryAsync(ct); }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "Plan INVOICE_REF wire soft-fail Agr={Agr}", agr);
            }
        }

        var withPlan = hasPlanRef
            ? await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{prefix}_INVOICE inv WITH (NOLOCK)
 WHERE {pred} AND ISNULL(inv.IOCODE,0)=0 AND ISNULL(inv.INSTALLMENT_PLAN_REF,0)>0", agr, ct)
            : 0L;

        if (withPlan == 0 && n == 0)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_NO_INSTALLMENT_REF",
                Severity = "WARN",
                Side = "ENERGY",
                Message =
                    "INSTALLMENT_PLAN_REF / ABYS_INSTALLMENT_ID boş. " +
                    "pilotDumpMgr APPLY (CS_INSTALLMENT + LIVE INSTALLMENT_ID) sonra Clean ENERGY zinciri."
            });
        }

        return n;
    }

    /// <summary>
    /// SP_TAKSIT_OLUSTUR / 613: ana borç PT iptal → INST_NR>0 taksit PT (PAYTYPE=120) + plan wire.
    /// </summary>
    private async Task<TaksitSplitResult> ApplyInstallmentDebtSplitAsync(
        SqlConnection conn, string prefix, long agr, bool hasAbysAgr, bool hasOwner,
        List<TahsilatGapItem> gaps, CancellationToken ct)
    {
        var hasNorm = await ProcExistsAsync(conn, "dbo", "SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR", ct);
        var hasSplit = await ProcExistsAsync(conn, "dbo", "SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR", ct);
        if (hasNorm || hasSplit)
        {
            try
            {
                if (hasNorm)
                    await ExecProcAsync(conn, "dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR", ct,
                        ("@AGR_ID", agr), ("@DEBUG", 1));
                if (hasSplit)
                    await ExecProcAsync(conn, "dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR", ct,
                        ("@AGR_ID", agr), ("@DEBUG", 1), ("@DO_RESEED", 0));

                var ptCnt = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{prefix}_PAYTRANS pt WITH (NOLOCK)
 INNER JOIN dbo.{prefix}_INVOICE inv WITH (NOLOCK) ON inv.LREF = pt.INVOICEREF
 WHERE {InvAgrPredicate("inv", hasAbysAgr, hasOwner, "@agr")}
   AND ISNULL(pt.IOCODE,0)=0 AND ISNULL(pt.CANCELED,0)=0 AND ISNULL(pt.INST_NR,0)>0", agr, ct);
                var wired = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{prefix}_INSTALLMENT_PLAN pl WITH (NOLOCK)
 WHERE {(hasAbysAgr ? "pl.ABYS_AGREEMENT_ID = @agr" : "pl.OWNERREF = @agr")}
   AND pl.PAYTRANS_REF IS NOT NULL", agr, ct);

                if (ptCnt == 0)
                {
                    gaps.Add(new TahsilatGapItem
                    {
                        Code = "PILOT_TAKSIT_SPLIT_EMPTY",
                        Severity = "WARN",
                        Side = "ENERGY",
                        Message = "613 SP çalıştı ama INST_NR>0 PT yok — direct split deneniyor."
                    });
                    return await BuildInstallmentDebtSplitDirectAsync(conn, prefix, agr, hasAbysAgr, hasOwner, gaps, ct);
                }

                return new TaksitSplitResult("SP613", (int)ptCnt, (int)wired);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "613 taksit split failed Agr={Agr} — direct", agr);
                gaps.Add(new TahsilatGapItem
                {
                    Code = "PILOT_613_FALLBACK",
                    Severity = "WARN",
                    Side = "ENERGY",
                    Message = $"613 hata → direct taksit split. {ex.Message}"
                });
            }
        }

        return await BuildInstallmentDebtSplitDirectAsync(conn, prefix, agr, hasAbysAgr, hasOwner, gaps, ct);
    }

    /// <summary>izgazMGR CS_INSTALLMENT(_PLAN) → ENERGY INSTALLMENT_PLAN (611 yoksa).</summary>
    private async Task<int> InsertInstallmentPlanDirectAsync(
        SqlConnection conn, string prefix, long agr, CancellationToken ct)
    {
        if (!await ObjectExistsAsync(conn, "izgazMGR.dbo.CS_INSTALLMENT", ct)) return 0;
        if (!await TableExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", ct)) return 0;

        var hasMgrPlan = await ObjectExistsAsync(conn, "izgazMGR.dbo.CS_INSTALLMENT_PLAN", ct);
        var hasAbysAgr = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_AGREEMENT_ID", ct);
        var hasAbysId = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_ID", ct);
        var hasAbysInst = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_INSTALLMENT_ID", ct);
        var hasOrder = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_ORDER_NUMBER", ct);
        var hasDue = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_DUE_DATE", ct);
        var hasAmt = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_AMOUNT", ct);

        var mgrPlanCols = hasMgrPlan
            ? await GetMssqlColumnsAsync(conn, "izgazMGR", "dbo", "CS_INSTALLMENT_PLAN", ct)
            : new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var mgrInstCols = await GetMssqlColumnsAsync(conn, "izgazMGR", "dbo", "CS_INSTALLMENT", ct);

        bool Mp(string c) => mgrPlanCols.Contains(c);
        bool Mi(string c) => mgrInstCols.Contains(c);

        if (!hasMgrPlan || !Mp("ID") || !Mp("INSTALLMENT_ID"))
        {
            // Plan satırı yok — header'dan tek satır üretme; split eşit bölecek
            return 0;
        }

        var orderExpr = Mp("ORDER_NUMBER") ? "CAST(ip.ORDER_NUMBER AS INT)"
            : Mp("INSTALLMENT_NUMBER") ? "CAST(ip.INSTALLMENT_NUMBER AS INT)"
            : "CAST(1 AS INT)";
        var amtExpr = Mp("AMOUNT")
            ? "CAST(ISNULL(ip.AMOUNT,0) + ISNULL(" + (Mp("LATE_CHARGE") ? "ip.LATE_CHARGE" : "0") + ",0) + ISNULL(" +
              (Mp("OVERDUE") ? "ip.OVERDUE" : "0") + ",0) AS DECIMAL(18,2))"
            : "CAST(0 AS DECIMAL(18,2))";
        var dueExpr = Mp("EXPIRY_DATE") ? "ip.EXPIRY_DATE"
            : Mp("DUE_DATE") ? "ip.DUE_DATE"
            : "NULL";
        var cancelActive = Mi("CANCEL_CAUSE_ID") || Mi("CANCELLATION_DATE")
            ? $@"CASE WHEN {(Mi("CANCEL_CAUSE_ID") ? "ins.CANCEL_CAUSE_ID IS NULL" : "1=1")}
             AND {(Mi("CANCELLATION_DATE") ? "ins.CANCELLATION_DATE IS NULL" : "1=1")}
             AND {(Mi("CANCELLATION_USER_ID") ? "ins.CANCELLATION_USER_ID IS NULL" : "1=1")}
            THEN 1 ELSE 0 END"
            : "1";

        var extraIns = new List<string>();
        var extraSel = new List<string>();
        if (hasAbysAgr) { extraIns.Add("ABYS_AGREEMENT_ID"); extraSel.Add("CAST(ins.AGREEMENT_ID AS BIGINT)"); }
        if (hasAbysId) { extraIns.Add("ABYS_ID"); extraSel.Add("CAST(ip.ID AS BIGINT)"); }
        if (hasAbysInst) { extraIns.Add("ABYS_INSTALLMENT_ID"); extraSel.Add("CAST(ip.INSTALLMENT_ID AS BIGINT)"); }
        if (hasOrder) { extraIns.Add("ABYS_ORDER_NUMBER"); extraSel.Add(orderExpr); }
        if (hasDue) { extraIns.Add("ABYS_DUE_DATE"); extraSel.Add(dueExpr); }
        if (hasAmt) { extraIns.Add("ABYS_AMOUNT"); extraSel.Add(amtExpr); }

        var extraInsSql = extraIns.Count > 0 ? ", " + string.Join(", ", extraIns) : "";
        var extraSelSql = extraSel.Count > 0 ? ", " + string.Join(", ", extraSel) : "";
        var notExists = hasAbysId
            ? "AND NOT EXISTS (SELECT 1 FROM dbo." + prefix + "_INSTALLMENT_PLAN t WITH (NOLOCK) WHERE t.ABYS_ID = CAST(ip.ID AS BIGINT))"
            : "AND NOT EXISTS (SELECT 1 FROM dbo." + prefix + "_INSTALLMENT_PLAN t WITH (NOLOCK) WHERE t.PLAN_ID = CAST(ip.INSTALLMENT_ID AS BIGINT) AND t.INSTALLMENT_COUNT = " + orderExpr + ")";

        await using var cmd = new SqlCommand($@"
INSERT INTO dbo.{prefix}_INSTALLMENT_PLAN (
    INSTALLMENT_TYPE_ID, OWNERREF, INVOICE_REF, PAYTRANS_REF,
    TOTAL_AMOUNT, INSTALLMENT_COUNT, ISACTIVE, PLAN_ID,
    ADDDATE, ADDUSER
    {extraInsSql}
)
SELECT
    CAST(ISNULL({(Mi("INSTALLMENT_TYPE_ID") ? "ins.INSTALLMENT_TYPE_ID" : "1")}, 1) AS INT),
    CAST(ISNULL(ins.AGREEMENT_ID, @agr) AS INT),
    NULL, NULL,
    {amtExpr},
    {orderExpr},
    CAST(({cancelActive}) AS BIT),
    CAST(ip.INSTALLMENT_ID AS BIGINT),
    GETDATE(), 20001
    {extraSelSql}
FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN ip WITH (NOLOCK)
INNER JOIN izgazMGR.dbo.CS_INSTALLMENT ins WITH (NOLOCK) ON ins.ID = ip.INSTALLMENT_ID
WHERE (ins.AGREEMENT_ID = @agr
    OR EXISTS (
         SELECT 1 FROM dbo.{prefix}_INVOICE inv WITH (NOLOCK)
          WHERE inv.ABYS_INSTALLMENT_ID = ins.ID
            AND (inv.ABYS_AGREEMENT_ID = @agr OR inv.OWNERREF = @agr)
       ))
  {notExists}", conn) { CommandTimeout = 300 };
        cmd.Parameters.AddWithValue("@agr", agr);
        return await cmd.ExecuteNonQueryAsync(ct);
    }

    /// <summary>SP_TAKSIT_OLUSTUR benzeri: fatura başına plan satırlarından taksit borç PT.</summary>
    private async Task<TaksitSplitResult> BuildInstallmentDebtSplitDirectAsync(
        SqlConnection conn, string prefix, long agr, bool hasAbysAgr, bool hasOwner,
        List<TahsilatGapItem> gaps, CancellationToken ct)
    {
        // QueryAsync @agrId bağlar — predicate'de @agrId kullan
        var pred = InvAgrPredicate("inv", hasAbysAgr, hasOwner, "@agrId");
        var hasInstNr = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "INST_NR", ct);
        var hasExplain = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "EXPLAIN", ct);
        var hasPlanTable = await TableExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", ct);
        var hasInvPlanRef = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "INSTALLMENT_PLAN_REF", ct);
        var hasAbysInst = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "ABYS_INSTALLMENT_ID", ct);
        if (!hasInstNr)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_NO_INST_NR",
                Severity = "WARN",
                Side = "ENERGY",
                Message = $"{prefix}_PAYTRANS.INST_NR yok — taksit split atlandı."
            });
            return new TaksitSplitResult("SKIP_NO_INST_NR", 0, 0);
        }

        // Aday: PLAN_REF / ABYS_INSTALLMENT_ID / plan.INVOICE_REF / mgr taksit hesabı
        var invSql = $@"
SELECT inv.LREF AS INV_LREF,
       inv.CLIENTREF, inv.OWNERREF, inv.OWNERTYPE, inv.[TYPE] AS INV_TYPE,
       inv.CURID, inv.DATE_, inv.DUEDATE, inv.PAYABLETOTAL, inv.BN_TYPE,
       {(hasAbysInst && hasInvPlanRef
           ? "COALESCE(inv.ABYS_INSTALLMENT_ID, CAST(NULLIF(inv.INSTALLMENT_PLAN_REF,0) AS BIGINT))"
           : hasAbysInst ? "inv.ABYS_INSTALLMENT_ID"
           : hasInvPlanRef ? "CAST(NULLIF(inv.INSTALLMENT_PLAN_REF,0) AS BIGINT)"
           : "CAST(NULL AS BIGINT)")} AS ABYS_INSTALLMENT_ID,
       {(hasInvPlanRef && hasAbysInst
           ? "COALESCE(NULLIF(inv.INSTALLMENT_PLAN_REF,0), CAST(inv.ABYS_INSTALLMENT_ID AS INT))"
           : hasInvPlanRef ? "NULLIF(inv.INSTALLMENT_PLAN_REF,0)"
           : "CAST(NULL AS BIGINT)")} AS INSTALLMENT_PLAN_REF
FROM dbo.{prefix}_INVOICE inv WITH (NOLOCK)
WHERE {pred}
  AND ISNULL(inv.IOCODE,0)=0
  AND ISNULL(inv.CANCELED,0)=0
  AND ISNULL(inv.PAYABLETOTAL,0) > 0.01
  AND (
        {(hasAbysInst ? "inv.ABYS_INSTALLMENT_ID IS NOT NULL" : "1=0")}
     OR {(hasInvPlanRef ? "ISNULL(inv.INSTALLMENT_PLAN_REF,0) > 0" : "1=0")}
     OR EXISTS (
          SELECT 1 FROM dbo.{prefix}_INSTALLMENT_PLAN pl WITH (NOLOCK)
           WHERE pl.INVOICE_REF = inv.LREF
              OR ({(hasAbysInst ? "pl.PLAN_ID = inv.ABYS_INSTALLMENT_ID" : "1=0")})
              OR ({(hasInvPlanRef ? "pl.PLAN_ID = inv.INSTALLMENT_PLAN_REF" : "1=0")})
       )
  )
  AND NOT EXISTS (
      SELECT 1 FROM dbo.{prefix}_PAYTRANS pt WITH (NOLOCK)
       WHERE pt.INVOICEREF = inv.LREF AND ISNULL(pt.IOCODE,0)=0
         AND ISNULL(pt.CANCELED,0)=0 AND ISNULL(pt.INST_NR,0)>0
  )";

        var invoices = await QueryAsync(conn, invSql, agr, ct);
        if (invoices.Count == 0 && await ObjectExistsAsync(conn, "izgazMGR.dbo.LS_INVOICE", ct)
            && await MgrColumnExistsAsync(conn, "LS_INVOICE", "ABYS_INSTALLMENT_ID", ct))
        {
            var abysSel = hasAbysInst
                ? "COALESCE(inv.ABYS_INSTALLMENT_ID, s.ABYS_INSTALLMENT_ID)"
                : "s.ABYS_INSTALLMENT_ID";
            var planSel = hasInvPlanRef
                ? "COALESCE(NULLIF(inv.INSTALLMENT_PLAN_REF,0), NULLIF(s.INSTALLMENT_PLAN_REF,0), s.ABYS_INSTALLMENT_ID)"
                : "COALESCE(NULLIF(s.INSTALLMENT_PLAN_REF,0), s.ABYS_INSTALLMENT_ID)";
            invoices = await QueryAsync(conn, $@"
SELECT inv.LREF AS INV_LREF,
       inv.CLIENTREF, inv.OWNERREF, inv.OWNERTYPE, inv.[TYPE] AS INV_TYPE,
       inv.CURID, inv.DATE_, inv.DUEDATE, inv.PAYABLETOTAL, inv.BN_TYPE,
       {abysSel} AS ABYS_INSTALLMENT_ID,
       {planSel} AS INSTALLMENT_PLAN_REF
FROM dbo.{prefix}_INVOICE inv WITH (NOLOCK)
INNER JOIN izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
  ON CAST(s.ABYS_ACTION_ID AS INT) = inv.LREF AND s.ABYS_AGREEMENT_ID = @agrId
WHERE {pred}
  AND ISNULL(inv.IOCODE,0)=0 AND ISNULL(inv.CANCELED,0)=0
  AND ISNULL(inv.PAYABLETOTAL,0) > 0.01
  AND s.ABYS_INSTALLMENT_ID IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dbo.{prefix}_PAYTRANS pt WITH (NOLOCK)
       WHERE pt.INVOICEREF = inv.LREF AND ISNULL(pt.IOCODE,0)=0
         AND ISNULL(pt.CANCELED,0)=0 AND ISNULL(pt.INST_NR,0)>0
  )", agr, ct);
        }

        if (invoices.Count == 0)
        {
            var mgrInstN = 0L;
            var mgrWithAbys = 0L;
            var enWithAbys = 0L;
            try
            {
                if (await ObjectExistsAsync(conn, "izgazMGR.dbo.CS_INSTALLMENT", ct))
                    mgrInstN = await ScalarLongAsync(conn,
                        "SELECT COUNT_BIG(*) FROM izgazMGR.dbo.CS_INSTALLMENT WITH (NOLOCK) WHERE AGREEMENT_ID=@agr",
                        agr, ct);
                if (await MgrColumnExistsAsync(conn, "LS_INVOICE", "ABYS_INSTALLMENT_ID", ct))
                    mgrWithAbys = await ScalarLongAsync(conn, @"
SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
 WHERE ABYS_AGREEMENT_ID=@agr AND ABYS_INSTALLMENT_ID IS NOT NULL", agr, ct);
                if (hasAbysInst)
                    enWithAbys = await ScalarLongAsync(conn, $@"
SELECT COUNT_BIG(*) FROM dbo.{prefix}_INVOICE inv WITH (NOLOCK)
 WHERE {pred} AND inv.ABYS_INSTALLMENT_ID IS NOT NULL AND ISNULL(inv.IOCODE,0)=0", agr, ct);
            }
            catch { /* diag only */ }

            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_TAKSIT_NO_CANDIDATE",
                Severity = "WARN",
                Side = "ENERGY",
                Message =
                    $"Taksit PT split adayı yok. mgrCS_INSTALLMENT={mgrInstN} mgrInvWithAbysInst={mgrWithAbys} " +
                    $"enInvWithAbysInst={enWithAbys}. izgazMGR.LS_INVOICE.ABYS_INSTALLMENT_ID kolonu/dump kontrol; " +
                    "pilotDumpMgr APPLY sonra Clean ENERGY."
            });
            return new TaksitSplitResult("DIRECT_EMPTY", 0, 0);
        }

        var ptIns = 0;
        var wired = 0;
        var hasPlanAbysAgrCol = hasPlanTable &&
            await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_AGREEMENT_ID", ct);
        var hasPlanAbysInstCol = hasPlanTable &&
            await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_INSTALLMENT_ID", ct);
        var hasClientType = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "CLIENT_TYPE", ct);
        var hasBnTypePt = await ColumnExistsAsync(conn, "dbo", $"{prefix}_PAYTRANS", "BN_TYPE", ct);
        var hasInvExplain = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INVOICE", "EXPLAIN", ct);

        foreach (var inv in invoices)
        {
            var invLref = Convert.ToInt32(inv["INV_LREF"] ?? 0);
            if (invLref <= 0) continue;
            var planId = Convert.ToInt64(inv.GetValueOrDefault("ABYS_INSTALLMENT_ID")
                ?? inv.GetValueOrDefault("INSTALLMENT_PLAN_REF") ?? 0);
            var payable = Convert.ToDecimal(inv.GetValueOrDefault("PAYABLETOTAL") ?? 0m);
            var clientRef = inv.GetValueOrDefault("CLIENTREF") ?? DBNull.Value;
            var ownerType = inv.GetValueOrDefault("OWNERTYPE") ?? 91;
            var invType = inv.GetValueOrDefault("INV_TYPE") ?? 1;
            var curId = inv.GetValueOrDefault("CURID") ?? 160;
            var bnType = inv.GetValueOrDefault("BN_TYPE") ?? DBNull.Value;
            object dueBase = inv.GetValueOrDefault("DUEDATE") ?? inv.GetValueOrDefault("DATE_") ?? DateTime.Now;
            if (dueBase is DateTime dd && dd.Date < DateTime.Today) dueBase = DateTime.Today;

            var lines = await LoadPlanLinesForInvoiceAsync(conn, prefix, invLref, planId, ct);
            if (lines.Count == 0 && planId > 0 &&
                await ObjectExistsAsync(conn, "izgazMGR.dbo.CS_INSTALLMENT_PLAN", ct))
            {
                lines = await LoadMgrPlanLinesAsync(conn, planId, ct);
            }

            // Eşit böl (SP_TAKSIT_OLUSTUR) — plan satırı yoksa
            if (lines.Count == 0)
            {
                var n = await ResolveInstallmentCountAsync(conn, planId, payable, ct);
                if (n < 2) continue;
                var unit = Math.Round(payable / n, 2, MidpointRounding.AwayFromZero);
                var first = payable - unit * (n - 1);
                for (var i = 1; i <= n; i++)
                {
                    var amt = i == 1 ? first : unit;
                    var due = AddInstallmentDue((DateTime)SafeSmallDt(dueBase), i);
                    lines.Add(new Dictionary<string, object?>
                    {
                        ["PLAN_LREF"] = null,
                        ["INST_NR"] = i,
                        ["INST_AMT"] = amt,
                        ["DUE_DATE"] = due,
                        ["PLAN_ID"] = planId > 0 ? planId : invLref
                    });
                }
            }

            if (lines.Count == 0) continue;

            // Ana borç PT iptal (SP_TAKSIT_OLUSTUR: UPDATE CANCELED=1)
            await using (var cancel = new SqlCommand($@"
UPDATE dbo.{prefix}_PAYTRANS SET CANCELED = 1
 WHERE INVOICEREF = @inv AND ISNULL(IOCODE,0)=0 AND ISNULL(INST_NR,0)=0 AND ISNULL(CANCELED,0)=0", conn))
            {
                cancel.Parameters.AddWithValue("@inv", invLref);
                await cancel.ExecuteNonQueryAsync(ct);
            }

            long usedPlanId = planId;
            if (usedPlanId <= 0)
                usedPlanId = Convert.ToInt64(lines[0].GetValueOrDefault("PLAN_ID") ?? invLref);

            DateTime? lastDue = null;
            foreach (var line in lines.OrderBy(l => Convert.ToInt32(l.GetValueOrDefault("INST_NR") ?? 0)))
            {
                var instNr = Convert.ToInt32(line.GetValueOrDefault("INST_NR") ?? 0);
                if (instNr <= 0) continue;
                var amt = Convert.ToDouble(line.GetValueOrDefault("INST_AMT") ?? 0d);
                if (amt < 0.01) continue;
                var due = line.GetValueOrDefault("DUE_DATE") ?? dueBase;
                lastDue = (DateTime)SafeSmallDt(due);
                var planLref = line.GetValueOrDefault("PLAN_LREF");

                var explainCol = hasExplain ? ", EXPLAIN" : "";
                var explainVal = hasExplain ? ", @explain" : "";
                var clientTypeCol = hasClientType ? ", CLIENT_TYPE" : "";
                var clientTypeVal = hasClientType ? ", @ownerType" : "";
                var bnCol = hasBnTypePt ? ", BN_TYPE" : "";
                var bnVal = hasBnTypePt ? ", @bnType" : "";
                await using var insPt = new SqlCommand($@"
INSERT INTO dbo.{prefix}_PAYTRANS (
    INVOICEREF, DATE_, [TYPE], CLIENTREF, IOCODE,
    TLTOTAL, PAID, DUEDATE, PAYTYPE, CURID, CURRATE, CURTOTAL,
    TRANSTYPE, CANCELED, TAX, GRANDTOTAL, LINETYPE, INST_NR, DV,
    PAYABLETOTAL, ADDDATE, ADDUSER, PAYCURID
    {clientTypeCol}{bnCol}{explainCol}
)
VALUES (
    @inv, GETDATE(), @type, @client, 0,
    @amt, 0, @due, 120, @curId, 1, @amt,
    113, 0, 0, @amt, 103, @instNr, 0,
    @amt, GETDATE(), 20001, @curId
    {clientTypeVal}{bnVal}{explainVal}
);
SELECT CAST(SCOPE_IDENTITY() AS INT);", conn) { CommandTimeout = 60 };
                insPt.Parameters.AddWithValue("@inv", invLref);
                insPt.Parameters.AddWithValue("@type", invType ?? 1);
                insPt.Parameters.AddWithValue("@client", clientRef ?? DBNull.Value);
                if (hasClientType) insPt.Parameters.AddWithValue("@ownerType", ownerType ?? 91);
                insPt.Parameters.AddWithValue("@amt", amt);
                insPt.Parameters.AddWithValue("@due", SafeSmallDt(due));
                insPt.Parameters.AddWithValue("@curId", curId ?? 160);
                insPt.Parameters.AddWithValue("@instNr", instNr);
                if (hasBnTypePt) insPt.Parameters.AddWithValue("@bnType", bnType ?? DBNull.Value);
                if (hasExplain)
                    insPt.Parameters.AddWithValue("@explain", $"{instNr}.TAKSIT");
                var newPtObj = await insPt.ExecuteScalarAsync(ct);
                var newPt = newPtObj == null || newPtObj == DBNull.Value ? 0 : Convert.ToInt32(newPtObj);
                if (newPt <= 0) continue;
                ptIns++;

                if (hasPlanTable && planLref != null && planLref != DBNull.Value)
                {
                    await using var wire = new SqlCommand($@"
UPDATE dbo.{prefix}_INSTALLMENT_PLAN SET
  PAYTRANS_REF = @pt, INVOICE_REF = @inv,
  INVOICE_OLD_DUEDATE = ISNULL(INVOICE_OLD_DUEDATE, @oldDue)
WHERE LREF = @planLref", conn);
                    wire.Parameters.AddWithValue("@pt", newPt);
                    wire.Parameters.AddWithValue("@inv", invLref);
                    wire.Parameters.AddWithValue("@oldDue", SafeSmallDt(inv.GetValueOrDefault("DUEDATE")));
                    wire.Parameters.AddWithValue("@planLref", planLref);
                    wired += await wire.ExecuteNonQueryAsync(ct) > 0 ? 1 : 0;
                }
                else if (hasPlanTable)
                {
                    await using var insPl = new SqlCommand($@"
INSERT INTO dbo.{prefix}_INSTALLMENT_PLAN (
    INSTALLMENT_TYPE_ID, OWNERREF, INVOICE_REF, PAYTRANS_REF,
    TOTAL_AMOUNT, INSTALLMENT_COUNT, ISACTIVE, PLAN_ID,
    ADDDATE, ADDUSER, INVOICE_OLD_DUEDATE
    {(hasPlanAbysAgrCol ? ", ABYS_AGREEMENT_ID" : "")}
    {(hasPlanAbysInstCol ? ", ABYS_INSTALLMENT_ID" : "")}
)
VALUES (
    1, @owner, @inv, @pt,
    @amt, @instNr, 1, @planId,
    GETDATE(), 20001, @oldDue
    {(hasPlanAbysAgrCol ? ", @agr" : "")}
    {(hasPlanAbysInstCol ? ", @planId" : "")}
)", conn);
                    insPl.Parameters.AddWithValue("@owner", inv.GetValueOrDefault("OWNERREF") ?? agr);
                    insPl.Parameters.AddWithValue("@inv", invLref);
                    insPl.Parameters.AddWithValue("@pt", newPt);
                    insPl.Parameters.AddWithValue("@amt", amt);
                    insPl.Parameters.AddWithValue("@instNr", instNr);
                    insPl.Parameters.AddWithValue("@planId", usedPlanId);
                    insPl.Parameters.AddWithValue("@oldDue", SafeSmallDt(inv.GetValueOrDefault("DUEDATE")));
                    if (hasPlanAbysAgrCol) insPl.Parameters.AddWithValue("@agr", agr);
                    try
                    {
                        wired += await insPl.ExecuteNonQueryAsync(ct) > 0 ? 1 : 0;
                    }
                    catch (Exception exPl)
                    {
                        _logger.LogDebug(exPl, "Installment plan insert skip Inv={Inv} Inst={N}", invLref, instNr);
                    }
                }
            }

            if (hasInvPlanRef && usedPlanId > 0)
            {
                await using var updInv = new SqlCommand($@"
UPDATE dbo.{prefix}_INVOICE SET
  INSTALLMENT_PLAN_REF = @planId
  {(hasAbysInst ? ", ABYS_INSTALLMENT_ID = COALESCE(ABYS_INSTALLMENT_ID, @planId)" : "")}
  {(lastDue != null ? ", DUEDATE = @lastDue" : "")}
  {(hasInvExplain ? ", EXPLAIN = CASE WHEN UPPER(ISNULL(EXPLAIN,'')) LIKE '%TAKSIT%' THEN EXPLAIN ELSE LEFT(CONCAT(ISNULL(EXPLAIN,''), ' TAKSIT'), 250) END" : "")}
WHERE LREF = @inv", conn);
                updInv.Parameters.AddWithValue("@planId", usedPlanId);
                updInv.Parameters.AddWithValue("@inv", invLref);
                if (lastDue != null) updInv.Parameters.AddWithValue("@lastDue", SafeSmallDt(lastDue));
                await updInv.ExecuteNonQueryAsync(ct);
            }
        }

        if (ptIns == 0)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_TAKSIT_NO_SPLIT",
                Severity = "WARN",
                Side = "ENERGY",
                Message =
                    $"Taksitli fatura adayı={invoices.Count} ama PT split 0. " +
                    "pilotDumpMgr ile CS_INSTALLMENT(+PLAN) yükleyip Clean APPLY tekrarlayın."
            });
        }

        return new TaksitSplitResult("DIRECT", ptIns, wired);
    }

    private async Task<List<Dictionary<string, object?>>> LoadPlanLinesForInvoiceAsync(
        SqlConnection conn, string prefix, int invLref, long planId, CancellationToken ct)
    {
        if (!await TableExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", ct))
            return [];
        var hasOrder = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_ORDER_NUMBER", ct);
        var hasDue = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_DUE_DATE", ct);
        var hasExp = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_EXPIRY_DATE", ct);
        var hasAbysInst = await ColumnExistsAsync(conn, "dbo", $"{prefix}_INSTALLMENT_PLAN", "ABYS_INSTALLMENT_ID", ct);
        var orderExpr = hasOrder
            ? "CAST(ISNULL(pl.INSTALLMENT_COUNT, pl.ABYS_ORDER_NUMBER) AS INT)"
            : "CAST(ISNULL(pl.INSTALLMENT_COUNT, 0) AS INT)";
        var dueExpr = hasDue && hasExp ? "ISNULL(pl.ABYS_DUE_DATE, pl.ABYS_EXPIRY_DATE)"
            : hasDue ? "pl.ABYS_DUE_DATE"
            : hasExp ? "pl.ABYS_EXPIRY_DATE"
            : "NULL";
        var planMatch = hasAbysInst
            ? "(pl.INVOICE_REF = @inv OR pl.PLAN_ID = @planId OR pl.ABYS_INSTALLMENT_ID = @planId)"
            : "(pl.INVOICE_REF = @inv OR pl.PLAN_ID = @planId)";

        await using var cmd = new SqlCommand($@"
SELECT pl.LREF AS PLAN_LREF,
       {orderExpr} AS INST_NR,
       CONVERT(DECIMAL(18,2), ISNULL(pl.TOTAL_AMOUNT,0)) AS INST_AMT,
       {dueExpr} AS DUE_DATE,
       CAST(ISNULL(pl.PLAN_ID, @planId) AS BIGINT) AS PLAN_ID
FROM dbo.{prefix}_INSTALLMENT_PLAN pl WITH (NOLOCK)
WHERE ISNULL(pl.ISACTIVE,1)=1
  AND {planMatch}
  AND {orderExpr} > 0
ORDER BY {orderExpr}, pl.LREF", conn) { CommandTimeout = 120 };
        cmd.Parameters.AddWithValue("@inv", invLref);
        cmd.Parameters.AddWithValue("@planId", planId > 0 ? planId : (object)DBNull.Value);
        return await ReadDictRowsAsync(cmd, ct);
    }

    private async Task<List<Dictionary<string, object?>>> LoadMgrPlanLinesAsync(
        SqlConnection conn, long planId, CancellationToken ct)
    {
        if (planId <= 0) return [];
        var cols = await GetMssqlColumnsAsync(conn, "izgazMGR", "dbo", "CS_INSTALLMENT_PLAN", ct);
        if (!cols.Contains("INSTALLMENT_ID")) return [];
        var orderCol = cols.Contains("ORDER_NUMBER") ? "ORDER_NUMBER"
            : cols.Contains("INSTALLMENT_NUMBER") ? "INSTALLMENT_NUMBER" : null;
        if (orderCol == null) return [];
        var amtExpr = cols.Contains("AMOUNT")
            ? "CONVERT(DECIMAL(18,2), ISNULL(ip.AMOUNT,0)+ISNULL(" +
              (cols.Contains("LATE_CHARGE") ? "ip.LATE_CHARGE" : "0") + ",0)+ISNULL(" +
              (cols.Contains("OVERDUE") ? "ip.OVERDUE" : "0") + ",0))"
            : "CAST(0 AS DECIMAL(18,2))";
        var dueCol = cols.Contains("EXPIRY_DATE") ? "ip.EXPIRY_DATE"
            : cols.Contains("DUE_DATE") ? "ip.DUE_DATE" : "NULL";

        await using var cmd = new SqlCommand($@"
SELECT CAST(NULL AS INT) AS PLAN_LREF,
       CAST(ip.{orderCol} AS INT) AS INST_NR,
       {amtExpr} AS INST_AMT,
       {dueCol} AS DUE_DATE,
       CAST(ip.INSTALLMENT_ID AS BIGINT) AS PLAN_ID
FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN ip WITH (NOLOCK)
WHERE ip.INSTALLMENT_ID = @planId
  AND CAST(ip.{orderCol} AS INT) > 0
ORDER BY CAST(ip.{orderCol} AS INT)", conn) { CommandTimeout = 120 };
        cmd.Parameters.AddWithValue("@planId", planId);
        return await ReadDictRowsAsync(cmd, ct);
    }

    private static async Task<int> ResolveInstallmentCountAsync(
        SqlConnection conn, long planId, decimal payable, CancellationToken ct)
    {
        if (planId <= 0) return 0;
        if (!await ObjectExistsAsync(conn, "izgazMGR.dbo.CS_INSTALLMENT_PLAN", ct))
        {
            // Header'da TOTAL_INSTALLMENTS varsa
            if (await ObjectExistsAsync(conn, "izgazMGR.dbo.CS_INSTALLMENT", ct))
            {
                var cols = await GetMssqlColumnsAsync(conn, "izgazMGR", "dbo", "CS_INSTALLMENT", ct);
                var cntCol = cols.Contains("TOTAL_INSTALLMENTS") ? "TOTAL_INSTALLMENTS"
                    : cols.Contains("INSTALLMENT_COUNT") ? "INSTALLMENT_COUNT"
                    : cols.Contains("INSTALLMENT_NUMBER") ? "INSTALLMENT_NUMBER"
                    : null;
                if (cntCol != null)
                {
                    await using var c = new SqlCommand(
                        $"SELECT CAST({cntCol} AS INT) FROM izgazMGR.dbo.CS_INSTALLMENT WITH (NOLOCK) WHERE ID=@id",
                        conn);
                    c.Parameters.AddWithValue("@id", planId);
                    var o = await c.ExecuteScalarAsync(ct);
                    var n = o == null || o == DBNull.Value ? 0 : Convert.ToInt32(o);
                    if (n >= 2 && n <= 120) return n;
                }
            }
            return 0;
        }
        await using var cmd = new SqlCommand(@"
SELECT COUNT(*) FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN WITH (NOLOCK)
 WHERE INSTALLMENT_ID = @id", conn);
        cmd.Parameters.AddWithValue("@id", planId);
        var cnt = Convert.ToInt32(await cmd.ExecuteScalarAsync(ct) ?? 0);
        return cnt >= 2 ? cnt : 0;
    }

    private static DateTime AddInstallmentDue(DateTime baseDue, int instNr)
    {
        var d = baseDue.Date.AddDays(30 * (instNr - 1));
        if (d.DayOfWeek == DayOfWeek.Saturday) d = d.AddDays(2);
        else if (d.DayOfWeek == DayOfWeek.Sunday) d = d.AddDays(1);
        return d;
    }

    private static async Task<List<Dictionary<string, object?>>> ReadDictRowsAsync(
        SqlCommand cmd, CancellationToken ct)
    {
        var list = new List<Dictionary<string, object?>>();
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
        {
            var row = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
            for (var i = 0; i < r.FieldCount; i++)
                row[r.GetName(i)] = r.IsDBNull(i) ? null : r.GetValue(i);
            list.Add(row);
        }
        return list;
    }

    private static string Left(string s, int n) =>
        string.IsNullOrEmpty(s) ? s : s.Length <= n ? s : s[..n];

    private static object SafeSmallDt(object? v)
    {
        if (v == null || v == DBNull.Value) return DateTime.Now;
        DateTime dt;
        if (v is DateTime d) dt = d;
        else if (!DateTime.TryParse(Convert.ToString(v), out dt)) return DateTime.Now;
        if (dt < new DateTime(1900, 1, 1) || dt > new DateTime(2079, 6, 6))
            return DateTime.Now;
        return dt;
    }

    private static async Task<bool> MgrColumnExistsAsync(
        SqlConnection conn, string table, string column, CancellationToken ct)
    {
        await using var cmd = new SqlCommand(@"
SELECT 1
  FROM izgazMGR.sys.columns c
  JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
  JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
 WHERE s.name = N'dbo' AND t.name = @t AND c.name = @c", conn);
        cmd.Parameters.AddWithValue("@t", table);
        cmd.Parameters.AddWithValue("@c", column);
        try { return await cmd.ExecuteScalarAsync(ct) != null; }
        catch { return false; }
    }

    /// <summary>izgazMGR CLOSED / CLOSED_CALC → ENERGY CLOSED=1 (LIVE dump CLOSED hep 0).</summary>
    private async Task<int> SyncClosedFromMgrAsync(
        SqlConnection conn, string prefix, long agr, bool hasAbysAgr, bool hasOwner, CancellationToken ct)
    {
        if (!await ObjectExistsAsync(conn, "izgazMGR.dbo.LS_INVOICE", ct)) return 0;
        var hasCalc = await MgrColumnExistsAsync(conn, "LS_INVOICE", "CLOSED_CALC", ct);
        var closedExpr = hasCalc
            ? "(ISNULL(s.CLOSED,0)=1 OR ISNULL(s.CLOSED_CALC,0)=1)"
            : "ISNULL(s.CLOSED,0)=1";
        var pred = InvAgrPredicate("inv", hasAbysAgr, hasOwner, "@agr");
        await using var cmd = new SqlCommand($@"
UPDATE inv SET inv.CLOSED = 1
  FROM dbo.{prefix}_INVOICE inv
 INNER JOIN izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
    ON CAST(s.ABYS_ACTION_ID AS INT) = inv.LREF
   AND s.ABYS_AGREEMENT_ID = @agr
 WHERE {pred}
   AND ISNULL(inv.IOCODE,0)=0
   AND ISNULL(inv.CLOSED,0)=0
   AND {closedExpr}", conn) { CommandTimeout = 180 };
        cmd.Parameters.AddWithValue("@agr", agr);
        try { return await cmd.ExecuteNonQueryAsync(ct); }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "SyncClosedFromMgr failed Agr={Agr}", agr);
            return 0;
        }
    }

    private async Task<int> AlignClosedInvoicesAsync(
        SqlConnection conn, string prefix, long agr, bool hasAbysAgr, bool hasOwner, CancellationToken ct)
    {
        var pred = InvAgrPredicate("inv", hasAbysAgr, hasOwner, "@agr");
        await using var cmd = new SqlCommand($@"
UPDATE pt
   SET pt.PAID = pt.PAYABLETOTAL
  FROM dbo.{prefix}_PAYTRANS pt
  INNER JOIN dbo.{prefix}_INVOICE inv ON inv.LREF = pt.INVOICEREF
 WHERE {pred}
   AND ISNULL(inv.CLOSED,0)=1
   AND ISNULL(inv.CANCELED,0)=0
   AND ISNULL(pt.IOCODE,0)=0
   AND ISNULL(pt.CANCELED,0)=0
   AND ISNULL(pt.PAID,0) < ISNULL(pt.PAYABLETOTAL,0)", conn)
        {
            CommandTimeout = 120
        };
        cmd.Parameters.AddWithValue("@agr", agr);
        return await cmd.ExecuteNonQueryAsync(ct);
    }

    /// <summary>ENERGY invoice/plan AGR filtresi — ABYS kolonu yoksa OWNERREF.</summary>
    private static string InvAgrPredicate(string alias, bool hasAbysAgr, bool hasOwner, string param = "@agr")
    {
        if (hasAbysAgr && hasOwner)
            return $"({alias}.ABYS_AGREEMENT_ID = {param} OR {alias}.OWNERREF = {param})";
        if (hasAbysAgr)
            return $"{alias}.ABYS_AGREEMENT_ID = {param}";
        if (hasOwner)
            return $"{alias}.OWNERREF = {param}";
        return "1 = 0";
    }

    private static async Task<bool> ObjectExistsAsync(SqlConnection conn, string threePartName, CancellationToken ct)
    {
        var parts = threePartName.Split('.');
        if (parts.Length != 3) return false;
        await using var cmd = new SqlCommand(@"
SELECT 1
  FROM izgazMGR.sys.tables t
  JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
 WHERE s.name = @sch AND t.name = @tbl", conn);
        cmd.Parameters.AddWithValue("@sch", parts[1]);
        cmd.Parameters.AddWithValue("@tbl", parts[2]);
        try { return await cmd.ExecuteScalarAsync(ct) != null; }
        catch { return false; }
    }

    private static async Task<bool> ProcExistsAsync(SqlConnection conn, string schema, string name, CancellationToken ct)
    {
        await using var cmd = new SqlCommand(@"
SELECT 1 FROM sys.procedures p
JOIN sys.schemas s ON s.schema_id = p.schema_id
WHERE s.name = @s AND p.name = @n", conn);
        cmd.Parameters.AddWithValue("@s", schema);
        cmd.Parameters.AddWithValue("@n", name);
        return await cmd.ExecuteScalarAsync(ct) != null;
    }

    private static async Task<long> ScalarLongAsync(SqlConnection conn, string sql, long agr, CancellationToken ct)
    {
        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 180 };
        if (System.Text.RegularExpressions.Regex.IsMatch(sql, @"@agrId\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            cmd.Parameters.AddWithValue("@agrId", agr);
        if (System.Text.RegularExpressions.Regex.IsMatch(sql, @"@agr\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            cmd.Parameters.AddWithValue("@agr", agr);
        var o = await cmd.ExecuteScalarAsync(ct);
        return o == null || o == DBNull.Value ? 0L : Convert.ToInt64(o);
    }

    private static async Task ExecProcAsync(
        SqlConnection conn, string procName, CancellationToken ct, params (string Name, object Value)[] args)
    {
        await using var cmd = new SqlCommand(procName, conn)
        {
            CommandType = CommandType.StoredProcedure,
            CommandTimeout = 0
        };
        foreach (var (name, value) in args)
            cmd.Parameters.AddWithValue(name, value ?? DBNull.Value);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static string BuildTamEksiltenSql(string inv, bool hasInvoiceCrossRef, bool hasReturnCols)
    {
        var extraSelect = "";
        var extraWhere = "";
        if (hasInvoiceCrossRef)
            extraSelect += ", inv.INVOICECROSSREF";
        if (hasReturnCols)
        {
            extraSelect += ", inv.RETURN_SOURCE_INVREF, inv.RETURN_TARGET_INVREF";
            extraWhere += @"
    OR inv.RETURN_SOURCE_INVREF IS NOT NULL
    OR inv.RETURN_TARGET_INVREF IS NOT NULL";
        }

        return $@"
SELECT TOP 300 inv.LREF, inv.OWNERREF, inv.FICHENO, inv.EXPLAIN, inv.CLOSED, inv.PAYABLETOTAL, inv.TYPE
       {extraSelect}
FROM {inv} inv WITH (NOLOCK)
WHERE inv.OWNERREF = @agrId AND ISNULL(inv.CANCELED,0)=0
  AND (
    UPPER(ISNULL(inv.FICHENO,'')) LIKE 'I%'
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%IADE%'
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%TAM EKS%'
    OR UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%EKSILTEN%'
    {extraWhere}
  )
ORDER BY inv.LREF DESC";
    }

    private static TahsilatLogEvent MakeLog(
        string runId, long agrId, string step, string side, string op,
        long ms, int? rows, string outcome, string detail) => new()
    {
        RunId = runId,
        AgrId = agrId,
        Step = step,
        Side = side,
        Op = op,
        ElapsedMs = ms,
        RowCount = rows,
        Outcome = outcome,
        Detail = detail
    };

    private static async Task<bool> TableExistsAsync(SqlConnection conn, string schema, string table, CancellationToken ct)
    {
        await using var cmd = new SqlCommand(
            "SELECT 1 FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id WHERE s.name=@s AND t.name=@t",
            conn);
        cmd.Parameters.AddWithValue("@s", schema);
        cmd.Parameters.AddWithValue("@t", table);
        var o = await cmd.ExecuteScalarAsync(ct);
        return o != null;
    }

    private static async Task<List<Dictionary<string, object?>>> QueryAsync(
        SqlConnection conn, string sql, long agrId, CancellationToken ct)
    {
        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 300 };
        // @agrId ve @agr ayrı token — Contains("@agr") @agrId'yi de yakalar, word-boundary kullan
        if (System.Text.RegularExpressions.Regex.IsMatch(sql, @"@agrId\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            cmd.Parameters.AddWithValue("@agrId", agrId);
        if (System.Text.RegularExpressions.Regex.IsMatch(sql, @"@agr\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            cmd.Parameters.AddWithValue("@agr", agrId);
        var list = new List<Dictionary<string, object?>>();
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
            list.Add(ReadRow(reader));
        return list;
    }

    private static Dictionary<string, object?> ReadRow(IDataRecord r)
    {
        var d = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < r.FieldCount; i++)
        {
            var v = r.IsDBNull(i) ? null : r.GetValue(i);
            if (v is DateTime dt) v = dt.ToString("yyyy-MM-dd HH:mm:ss");
            d[r.GetName(i)] = v;
        }
        return d;
    }

    private static int ToInt(Dictionary<string, object?> r, string key)
    {
        if (!r.TryGetValue(key, out var v) || v == null) return 0;
        return Convert.ToInt32(Convert.ToDecimal(v));
    }

    private static decimal? ToDec(Dictionary<string, object?> r, string key)
    {
        if (!r.TryGetValue(key, out var v) || v == null) return null;
        return Convert.ToDecimal(v);
    }

    private static DateTime? ParseDate(object? v)
    {
        if (v == null) return null;
        if (v is DateTime dt) return dt;
        if (DateTime.TryParse(Convert.ToString(v), out var p)) return p;
        return null;
    }
}
 