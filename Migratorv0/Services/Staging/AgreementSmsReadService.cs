using System.Data;
using System.Diagnostics;
using MigrationWeb.Models.Staging;
using Oracle.ManagedDataAccess.Client;

namespace MigrationWeb.Services.Staging;

/// <summary>
/// SMS (Oracle) okuma. Bakiye kuralı: SUM(AMOUNT*STATUS) — TOTAL_DEBT/CREDIT kullanma.
/// Detay: <c>SMS_BALANCE_RULE.md</c> / eşleşme: <c>ESLESME_RULE.md</c>.
/// </summary>
public sealed class AgreementSmsReadService
{
    private readonly ILogger<AgreementSmsReadService> _logger;

    public AgreementSmsReadService(ILogger<AgreementSmsReadService> logger) => _logger = logger;

    public async Task<(bool Ok, string Message)> TestAsync(string cs, CancellationToken ct)
    {
        try
        {
            await using var conn = new OracleConnection(cs);
            await conn.OpenAsync(ct);
            await using var cmd = new OracleCommand("SELECT 1 FROM DUAL", conn);
            await cmd.ExecuteScalarAsync(ct);
            return (true, "SMS (Oracle) bağlantı OK.");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "SMS Oracle test failed");
            return (false, ex.Message);
        }
    }

    public async Task<(Dictionary<string, object?> Summary, List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadSummaryAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var sms = Sanitize(req.SmsSchema);

        await using var conn = new OracleConnection(req.OracleConnectionString);
        await conn.OpenAsync(ct);

        // ABYS bakiyesi = SUM(AMOUNT*STATUS); TOTAL_DEBT/CREDIT stale kalabiliyor.
        // Adet: en az 1 income'u olan hesap. Toplam: TAHAKKUK(action=1); EMANET(14): STATUS>0.
        // Ödenen = Toplam - Borç (Borç = net income bakiyesi).
        var rows = await QueryAsync(conn, $@"
SELECT
  L.VALUE AS ACCRUE_NAME,
  A.ACCRUE_TYPE_ID,
  COUNT(*) AS TAHAKKUK_ADET,
  ROUND(SUM(X.TOPLAM_TUTAR), 2) AS TOPLAM_TUTAR,
  ROUND(SUM(X.TOPLAM_TUTAR) - SUM(X.TOPLAM_BORC), 2) AS ODENEN_TUTAR,
  ROUND(SUM(X.TOPLAM_BORC), 2) AS TOPLAM_BORC
FROM {sms}.CS_ACCOUNT A
JOIN {sms}.CS_ACCRUE_TYPE_PRM_LNG L
  ON L.PRM_ID = A.ACCRUE_TYPE_ID AND L.LANG_ID = 1
JOIN (
  SELECT
    A2.ID,
    A2.ACCRUE_TYPE_ID,
    CASE
      WHEN A2.ACCRUE_TYPE_ID = 14 THEN
        NVL((SELECT SUM(AI.AMOUNT)
               FROM {sms}.CS_ACCOUNT_ACTION AA
               JOIN {sms}.CS_ACCOUNT_INCOME AI ON AI.ACCOUNT_ACTION_ID = AA.ID
              WHERE AA.ACCOUNT_ID = A2.ID AND AI.STATUS > 0), 0)
      ELSE
        NVL((SELECT SUM(AI.AMOUNT)
               FROM {sms}.CS_ACCOUNT_ACTION AA
               JOIN {sms}.CS_ACCOUNT_INCOME AI ON AI.ACCOUNT_ACTION_ID = AA.ID
              WHERE AA.ACCOUNT_ID = A2.ID AND AA.ACTION_TYPE_ID = 1), 0)
    END AS TOPLAM_TUTAR,
    NVL((SELECT SUM(AI.AMOUNT * AI.STATUS)
           FROM {sms}.CS_ACCOUNT_ACTION AA
           JOIN {sms}.CS_ACCOUNT_INCOME AI ON AI.ACCOUNT_ACTION_ID = AA.ID
          WHERE AA.ACCOUNT_ID = A2.ID), 0) AS TOPLAM_BORC
  FROM {sms}.CS_ACCOUNT A2
  WHERE A2.AGREEMENT_ID = :agrId
    AND A2.ACCRUE_TYPE_ID IN (1, 2, 5, 14, 26, 329)
) X ON X.ID = A.ID
WHERE A.AGREEMENT_ID = :agrId
  AND A.ACCRUE_TYPE_ID IN (1, 2, 5, 14, 26, 329)
  AND EXISTS (
    SELECT 1
      FROM {sms}.CS_ACCOUNT_ACTION AA
      JOIN {sms}.CS_ACCOUNT_INCOME AI ON AI.ACCOUNT_ACTION_ID = AA.ID
     WHERE AA.ACCOUNT_ID = A.ID
  )
GROUP BY L.VALUE, A.ACCRUE_TYPE_ID
ORDER BY TAHAKKUK_ADET DESC", req.AgreementId, ct);

        var accountCnt = rows.Sum(r => (int)ToLong(r, "TAHAKKUK_ADET"));
        var openBal = rows.Sum(r => Convert.ToDecimal(r.GetValueOrDefault("TOPLAM_BORC") ?? 0m));
        var openCnt = rows.Count(r => Convert.ToDecimal(r.GetValueOrDefault("TOPLAM_BORC") ?? 0m) > 0.01m);
        var toplamTutar = rows.Sum(r => Convert.ToDecimal(r.GetValueOrDefault("TOPLAM_TUTAR") ?? 0m));
        var odenen = rows.Sum(r => Convert.ToDecimal(r.GetValueOrDefault("ODENEN_TUTAR") ?? 0m));

        var summary = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase)
        {
            ["AGREEMENT_ID"] = req.AgreementId,
            ["ACCOUNT_CNT"] = accountCnt,
            ["FATURA_CNT"] = rows
                .Where(r => new[] { 1L, 2L, 26L }.Contains(ToLong(r, "ACCRUE_TYPE_ID")))
                .Sum(r => (int)ToLong(r, "TAHAKKUK_ADET")),
            ["OPEN_BALANCE_SUM"] = openBal,
            ["OPEN_ACCOUNT_CNT"] = openCnt,
            ["TOPLAM_TUTAR"] = toplamTutar,
            ["ODENEN_TUTAR"] = odenen,
            ["TOPLAM_BORC"] = openBal
        };

        if (accountCnt == 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "SMS_NO_AGR",
                Severity = "CRITICAL",
                Side = "SMS",
                Message = $"SMS'te AGREEMENT_ID={req.AgreementId} için gelir hareketi olan hesap yok."
            });

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, "summary", "SMS", "READ", sw.ElapsedMilliseconds,
            accountCnt, gaps.Count == 0 ? "OK" : "WARN",
            $"accounts={accountCnt} openBal={openBal} toplam={toplamTutar} odenen={odenen}");
        return (summary, rows, gaps, log);
    }

    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadPaymentsAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var mig = Sanitize(req.MigrationSchema);
        var sms = Sanitize(req.SmsSchema);

        await using var conn = new OracleConnection(req.OracleConnectionString);
        await conn.OpenAsync(ct);

        List<Dictionary<string, object?>> rows;
        string source;

        if (await TableExistsAsync(conn, mig, "LS_PAYMENT", ct))
        {
            source = $"{mig}.LS_PAYMENT";
            rows = await QueryAsync(conn, $@"
SELECT P.PAY_LREF AS LREF, P.MAIN_LREF_FIRST AS MAIN_LREF, P.FATURAID, P.SOZLESME,
       P.PAY_AMT AS PAYABLETOTAL, P.PAY_AMT AS PAY_FULL_AMT, P.PAY_DATE,
       P.CANCELED, P.BANKA_ID AS BANK_ID, P.VEZNE_ID AS CASH_ID,
       P.TAH_MAKBUZ_NO AS RECEIPT_NUMBER, P.USERID AS CREATED_USER_ID
  FROM {mig}.LS_PAYMENT P
 WHERE P.SOZLESME = :agrId
 ORDER BY P.PAY_DATE DESC NULLS LAST, P.PAY_LREF DESC
 FETCH FIRST 500 ROWS ONLY", req.AgreementId, ct);
        }
        else if (await TableExistsAsync(conn, mig, "LS_OV_PAY_PT", ct))
        {
            source = $"{mig}.LS_OV_PAY_PT";
            rows = await QueryAsync(conn, $@"
SELECT P.ABYS_ID AS LREF, P.CROSSREF_MAIN_LREF AS MAIN_LREF, P.ABYS_ACCOUNT_ID AS FATURAID,
       P.ABYS_AGREEMENT_ID AS SOZLESME, P.PAYABLETOTAL, P.PAY_FULL_AMT,
       P.DATE_ AS PAY_DATE, P.CANCELED, P.CASH_ID, P.RECEIPT_NUMBER,
       P.ABYS_ACTION_TYPE_ID AS ACTION_TYPE_ID, P.OV_KIND
  FROM {mig}.LS_OV_PAY_PT P
 WHERE P.ABYS_AGREEMENT_ID = :agrId
   AND P.OV_KIND = 'PAY'
   AND NVL(P.ALLOC_RN,1) = 1
 ORDER BY P.DATE_ DESC NULLS LAST, P.ABYS_ID DESC
 FETCH FIRST 500 ROWS ONLY", req.AgreementId, ct);
        }
        else
        {
            source = $"{sms} live ATP.TYPE=2 (tahsilat)";
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_LS_OV_PAY_PT",
                Severity = "WARN",
                Side = "SMS",
                Message = "LS_PAYMENT / LS_OV_PAY_PT yok — canlı SMS tahsilat (ATP.TYPE=2). O30/O52 CTAS önerilir."
            });
            rows = await QueryAsync(conn, $@"
SELECT ACT.ID AS LREF, ACC.ID AS FATURAID, ACC.AGREEMENT_ID AS SOZLESME,
       ACT.ACTION_TYPE_ID, ACT.ACTION_DATE AS PAY_DATE,
       CAST(ROUND(ABS(NVL(AMT.TUT,0)),2) AS NUMBER(15,3)) AS PAYABLETOTAL,
       CAST(ROUND(ABS(NVL(AMT.TUT,0)),2) AS NUMBER(15,3)) AS PAY_FULL_AMT,
       ACT.CREATED_USER_ID, ACT.UPDATED_USER_ID,
       ACT.BANK_ID, ACT.CASH_ID, ACT.RECEIPT_NUMBER
  FROM {sms}.CS_ACCOUNT_ACTION ACT
  JOIN {sms}.CS_ACCOUNT ACC ON ACC.ID = ACT.ACCOUNT_ID
  JOIN {sms}.CS_ACTION_TYPE_PRM ATP ON ATP.ID = ACT.ACTION_TYPE_ID AND ATP.TYPE = 2
  LEFT JOIN (
    SELECT AI.ACCOUNT_ACTION_ID, SUM(AI.AMOUNT * AI.STATUS) TUT
      FROM {sms}.CS_ACCOUNT_INCOME AI
     GROUP BY AI.ACCOUNT_ACTION_ID
  ) AMT ON AMT.ACCOUNT_ACTION_ID = ACT.ID
 WHERE ACC.AGREEMENT_ID = :agrId
   AND ACT.ACTION_TYPE_ID NOT IN (6, 24, 36, 37, 39, 44)
 ORDER BY ACT.ACTION_DATE DESC NULLS LAST, ACT.ID DESC
 FETCH FIRST 500 ROWS ONLY", req.AgreementId, ct);
        }

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, "payments", "SMS", "READ", sw.ElapsedMilliseconds,
            rows.Count, "OK", $"source={source} rows={rows.Count}");
        return (rows, gaps, log);
    }

    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadCloseCandidatesAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var mig = Sanitize(req.MigrationSchema);
        var sms = Sanitize(req.SmsSchema);

        await using var conn = new OracleConnection(req.OracleConnectionString);
        await conn.OpenAsync(ct);

        List<Dictionary<string, object?>> rows;
        string source;

        if (await TableExistsAsync(conn, mig, "LS_STG_INV_PAY_CLOSE", ct))
        {
            source = $"{mig}.LS_STG_INV_PAY_CLOSE";
            rows = await QueryAsync(conn, $@"
SELECT S.MAIN_LREF, S.FATURAID, S.SOZLESME, S.FIX_KIND, S.WANT_CLOSED, S.WANT_LPD,
       S.PAYABLE_AMT, S.OV_PAID_AMT, S.AFL_OPEN
  FROM {mig}.LS_STG_INV_PAY_CLOSE S
 WHERE S.SOZLESME = :agrId
 ORDER BY CASE S.FIX_KIND
            WHEN 'AFL_OPEN' THEN 1 WHEN 'CLOSE_FULL' THEN 2 WHEN 'CLOSE_EPS' THEN 3
            WHEN 'KEEP_OPEN' THEN 4 ELSE 5 END,
          S.MAIN_LREF
 FETCH FIRST 2000 ROWS ONLY", req.AgreementId, ct);
        }
        else
        {
            source = $"{sms} live AMOUNT×STATUS → FIX_KIND (O51 kaba)";
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_LS_STG_INV_PAY_CLOSE",
                Severity = "WARN",
                Side = "SMS",
                Message = "LS_STG_INV_PAY_CLOSE yok — canlı kapama adayı (BALANCE=SUM(AMOUNT×STATUS); AFL_OPEN=açık hesap). O51 CTAS önerilir."
            });
            // O51: AFL_OPEN = hesap LS_AFL'de (BALANCE>0). TOTAL_DEBT/CREDIT kullanma.
            rows = await QueryAsync(conn, $@"
WITH acc_bal AS (
  SELECT aa.ACCOUNT_ID,
         CAST(ROUND(SUM(ai.STATUS * ai.AMOUNT), 2) AS NUMBER(15,3)) AS BALANCE
    FROM {sms}.CS_ACCOUNT_ACTION aa
    JOIN {sms}.CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = aa.ID
    JOIN {sms}.CS_ACCOUNT a ON a.ID = aa.ACCOUNT_ID
   WHERE a.AGREEMENT_ID = :agrId
   GROUP BY aa.ACCOUNT_ID
),
main_amt AS (
  SELECT g.ID AS MAIN_LREF,
         g.ACCOUNT_ID,
         CAST(ROUND(ABS(SUM(ai.AMOUNT * ai.STATUS)), 2) AS NUMBER(15,3)) AS PAYABLE_AMT
    FROM {sms}.CS_ACCOUNT_ACTION g
    JOIN {sms}.CS_ACCOUNT a ON a.ID = g.ACCOUNT_ID
    JOIN {sms}.CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = g.ID
   WHERE a.AGREEMENT_ID = :agrId
     AND g.ACTION_TYPE_ID IN (1, 3, 10, 41)
     AND NVL(a.ACCRUE_TYPE_ID, -1) <> 14
   GROUP BY g.ID, g.ACCOUNT_ID
  HAVING ABS(SUM(ai.AMOUNT * ai.STATUS)) > 0.0001
),
pay_on_acc AS (
  SELECT pay.ACCOUNT_ID,
         CAST(ROUND(ABS(SUM(pi.AMOUNT * pi.STATUS)), 2) AS NUMBER(15,3)) AS PAID_AMT,
         COUNT(DISTINCT pay.ID) AS PAY_CNT
    FROM {sms}.CS_ACCOUNT_ACTION pay
    JOIN {sms}.CS_ACCOUNT a ON a.ID = pay.ACCOUNT_ID
    JOIN {sms}.CS_ACTION_TYPE_PRM atp ON atp.ID = pay.ACTION_TYPE_ID AND atp.TYPE = 2
    JOIN {sms}.CS_ACCOUNT_INCOME pi ON pi.ACCOUNT_ACTION_ID = pay.ID
   WHERE a.AGREEMENT_ID = :agrId
     AND pay.ACTION_TYPE_ID NOT IN (6, 24, 36, 37, 39, 44)
   GROUP BY pay.ACCOUNT_ID
)
SELECT
  CAST(m.MAIN_LREF AS NUMBER(12)) AS MAIN_LREF,
  CAST(m.ACCOUNT_ID AS NUMBER(12)) AS FATURAID,
  CAST(a.AGREEMENT_ID AS NUMBER(12)) AS SOZLESME,
  CAST(
    CASE
      WHEN NVL(b.BALANCE, 0) > 0.01 THEN 'AFL_OPEN'
      WHEN NVL(p.PAY_CNT, 0) = 0 AND m.PAYABLE_AMT <= 0.01 THEN 'CLOSE_FULL'
      WHEN NVL(p.PAY_CNT, 0) = 0 THEN 'NO_PAY'
      WHEN NVL(b.BALANCE, 0) <= 0.01 THEN 'CLOSE_FULL'
      ELSE 'KEEP_OPEN'
    END AS VARCHAR2(16)
  ) AS FIX_KIND,
  CAST(
    CASE
      WHEN NVL(b.BALANCE, 0) > 0.01 THEN 0
      WHEN NVL(b.BALANCE, 0) <= 0.01 THEN 1
      ELSE 0
    END AS NUMBER(1)
  ) AS WANT_CLOSED,
  CAST(NULL AS DATE) AS WANT_LPD,
  m.PAYABLE_AMT,
  CAST(ROUND(NVL(p.PAID_AMT, 0), 2) AS NUMBER(15,3)) AS OV_PAID_AMT,
  CAST(CASE WHEN NVL(b.BALANCE, 0) > 0.01 THEN 1 ELSE 0 END AS NUMBER(1)) AS AFL_OPEN,
  CAST(ROUND(NVL(b.BALANCE, 0), 2) AS NUMBER(15,3)) AS AFL_BAL
FROM main_amt m
JOIN {sms}.CS_ACCOUNT a ON a.ID = m.ACCOUNT_ID
LEFT JOIN acc_bal b ON b.ACCOUNT_ID = m.ACCOUNT_ID
LEFT JOIN pay_on_acc p ON p.ACCOUNT_ID = m.ACCOUNT_ID
ORDER BY
  CASE
    WHEN NVL(b.BALANCE, 0) > 0.01 THEN 1
    WHEN NVL(b.BALANCE, 0) <= 0.01 AND NVL(p.PAY_CNT, 0) > 0 THEN 2
    WHEN NVL(p.PAY_CNT, 0) = 0 THEN 5
    ELSE 4
  END,
  m.MAIN_LREF
FETCH FIRST 2000 ROWS ONLY", req.AgreementId, ct);
        }

        var closeCnt = rows.Count(r =>
        {
            var k = Convert.ToString(r.GetValueOrDefault("FIX_KIND")) ?? "";
            return k is "CLOSE_FULL" or "CLOSE_EPS";
        });
        var aflCnt = rows.Count(r => Convert.ToString(r.GetValueOrDefault("FIX_KIND")) == "AFL_OPEN");
        var keepCnt = rows.Count(r => Convert.ToString(r.GetValueOrDefault("FIX_KIND")) == "KEEP_OPEN");
        var noPayCnt = rows.Count(r => Convert.ToString(r.GetValueOrDefault("FIX_KIND")) == "NO_PAY");

        if (rows.Count == 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_CLOSE_ROWS",
                Severity = "WARN",
                Side = "SMS",
                Message = "Bu sözleşme için kapama adayı satırı yok."
            });
        if (keepCnt > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "KEEP_OPEN_PARTIAL",
                Severity = "WARN",
                Side = "SMS",
                Message = $"{keepCnt} fatura KEEP_OPEN (kısmi tahsilat) — tahakkuk↔tahsilat tam eşleşmedi, otomatik kapama yok."
            });
        if (noPayCnt > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_PAY_UNMATCHED",
                Severity = "WARN",
                Side = "SMS",
                Message = $"{noPayCnt} fatura NO_PAY — tahsilat overlay’de yok / eşleşmedi."
            });

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, "closeCandidates", "SMS", "READ", sw.ElapsedMilliseconds,
            rows.Count, "OK",
            $"source={source} total={rows.Count} close={closeCnt} afl_open={aflCnt} keep_open={keepCnt} no_pay={noPayCnt}");
        return (rows, gaps, log);
    }

    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadAflAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var mig = Sanitize(req.MigrationSchema);
        var sms = Sanitize(req.SmsSchema);

        await using var conn = new OracleConnection(req.OracleConnectionString);
        await conn.OpenAsync(ct);

        List<Dictionary<string, object?>> rows;
        string source;
        if (await TableExistsAsync(conn, mig, "LS_AFL_OPEN_DEBT", ct))
        {
            source = $"{mig}.LS_AFL_OPEN_DEBT";
            var cols = await GetColumnsAsync(conn, mig, "LS_AFL_OPEN_DEBT", ct);
            var yt = cols.Contains("YT_DURUMU") ? "A.YT_DURUMU" : "CAST(NULL AS VARCHAR2(3))";
            var accrue = cols.Contains("ACCRUE_TYPE_ID") ? "A.ACCRUE_TYPE_ID" : "CAST(NULL AS NUMBER)";
            var migScope = cols.Contains("MIG_IN_SCOPE") ? "A.MIG_IN_SCOPE" : "CAST(1 AS NUMBER(1))";
            rows = await QueryAsync(conn, $@"
SELECT A.FATURAID, A.SOZLESME_HESABI AS SOZLESME, A.BALANCE, A.TAKSIT_DURUMU, A.INSTALLMENT_ID,
       {yt} AS YT_DURUMU, {accrue} AS ACCRUE_TYPE_ID, {migScope} AS MIG_IN_SCOPE
  FROM {mig}.LS_AFL_OPEN_DEBT A
 WHERE A.SOZLESME_HESABI = :agrId
   AND NVL(A.BALANCE, 0) > 0.01
 ORDER BY A.BALANCE DESC
 FETCH FIRST 2000 ROWS ONLY", req.AgreementId, ct);
        }
        else
        {
            source = $"{sms} live SUM(AMOUNT×STATUS) (O50)";
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_LS_AFL_OPEN_DEBT",
                Severity = "WARN",
                Side = "SMS",
                Message = "LS_AFL_OPEN_DEBT yok — canlı SMS AMOUNT×STATUS açık borç (O50)."
            });
            rows = await QuerySmsOpenDebtAsync(conn, sms, req.AgreementId, ct);
        }

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, "afl", "SMS", "READ", sw.ElapsedMilliseconds,
            rows.Count, "OK", $"source={source} open_rows={rows.Count}");
        return (rows, gaps, log);
    }

    /// <summary>
    /// Canlı SMS açık borç (O50 grain): FATURAID=CS_ACCOUNT.ID, BALANCE=SUM(STATUS×AMOUNT)&gt;0.
    /// AFL tablosu yoksa proxy; varsa FRK’te AFL bütünlüğü kontrolü için.
    /// </summary>
    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadSmsOpenDebtAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var sms = Sanitize(req.SmsSchema);
        await using var conn = new OracleConnection(req.OracleConnectionString);
        await conn.OpenAsync(ct);
        var rows = await QuerySmsOpenDebtAsync(conn, sms, req.AgreementId, ct);
        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, "smsOpenDebt", "SMS", "READ", sw.ElapsedMilliseconds,
            rows.Count, "OK", $"open_rows={rows.Count}");
        return (rows, gaps, log);
    }

    private static async Task<List<Dictionary<string, object?>>> QuerySmsOpenDebtAsync(
        OracleConnection conn, string sms, long agrId, CancellationToken ct)
    {
        return await QueryAsync(conn, $@"
SELECT CAST(a.ID AS NUMBER(12)) AS FATURAID,
       CAST(a.AGREEMENT_ID AS NUMBER(12)) AS SOZLESME,
       CAST(ROUND(SUM(ai.STATUS * ai.AMOUNT), 2) AS NUMBER(15,3)) AS BALANCE,
       CASE WHEN a.INSTALLMENT_ID IS NOT NULL THEN 'T' ELSE 'N' END AS TAKSIT_DURUMU,
       a.INSTALLMENT_ID,
       CASE WHEN a.LEGAL_PROCEEDING_ID IS NOT NULL THEN 'VAR' ELSE 'YOK' END AS YT_DURUMU,
       a.ACCRUE_TYPE_ID,
       CAST(CASE WHEN NVL(a.ACCRUE_TYPE_ID, -1) <> 14 THEN 1 ELSE 0 END AS NUMBER(1)) AS MIG_IN_SCOPE
  FROM {sms}.CS_ACCOUNT a
  JOIN {sms}.CS_ACCOUNT_ACTION aa ON aa.ACCOUNT_ID = a.ID
  JOIN {sms}.CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = aa.ID
 WHERE a.AGREEMENT_ID = :agrId
 GROUP BY a.ID, a.AGREEMENT_ID, a.INSTALLMENT_ID, a.LEGAL_PROCEEDING_ID, a.ACCRUE_TYPE_ID
HAVING SUM(ai.STATUS * ai.AMOUNT) > 0.01
 ORDER BY 3 DESC
 FETCH FIRST 2000 ROWS ONLY", agrId, ct);
    }

    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadMahsupAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var sms = Sanitize(req.SmsSchema);
        var mig = Sanitize(req.MigrationSchema);

        await using var conn = new OracleConnection(req.OracleConnectionString);
        await conn.OpenAsync(ct);

        List<Dictionary<string, object?>> rows;
        string source;

        if (await TableExistsAsync(conn, mig, "LS_OV_MAHSUP_SRC", ct))
        {
            source = $"{mig}.LS_OV_MAHSUP_SRC";
            rows = await QueryAsync(conn, $@"
SELECT M.PAY_SRC_KEY, M.PAY_LREF, M.MAIN_LREF, M.ABYS_AGREEMENT_ID AS SOZLESME,
       M.ACCOUNT_ID, M.ACTION_TYPE_ID, M.PAYABLETOTAL, M.DEP_ACCOUNT_ID, M.DEP_ACTION_ID,
       M.CASH_ID, M.RECEIPT_NUMBER, M.OV_KIND
  FROM {mig}.LS_OV_MAHSUP_SRC M
 WHERE M.ABYS_AGREEMENT_ID = :agrId
 ORDER BY M.MAIN_LREF, M.PAY_LREF
 FETCH FIRST 500 ROWS ONLY", req.AgreementId, ct);
        }
        else if (await TableExistsAsync(conn, mig, "LS_OV_PAY_PT", ct))
        {
            source = $"{mig}.LS_OV_PAY_PT OV_KIND=MAHSUP";
            rows = await QueryAsync(conn, $@"
SELECT P.SRC_KEY AS PAY_SRC_KEY, P.LREF AS PAY_LREF, P.CROSSREF_MAIN_LREF AS MAIN_LREF,
       P.ABYS_AGREEMENT_ID AS SOZLESME, P.ABYS_ACCOUNT_ID AS ACCOUNT_ID,
       P.ABYS_ACTION_TYPE_ID AS ACTION_TYPE_ID, P.PAYABLETOTAL,
       P.REF_DEPOSIT_ACCOUNT_ID AS DEP_ACCOUNT_ID, P.CASH_ID, P.RECEIPT_NUMBER,
       P.OV_KIND
  FROM {mig}.LS_OV_PAY_PT P
 WHERE P.ABYS_AGREEMENT_ID = :agrId
   AND P.OV_KIND = 'MAHSUP'
   AND NVL(P.CANCELED, 0) = 0
 ORDER BY P.DATE_ DESC NULLS LAST
 FETCH FIRST 500 ROWS ONLY", req.AgreementId, ct);
        }
        else
        {
            source = $"{sms}.CS_ACCOUNT_ACTION ACTION_TYPE_ID 6/24";
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_LS_OV_MAHSUP",
                Severity = "WARN",
                Side = "SMS",
                Message = "LS_OV_MAHSUP_SRC / PAY_PT yok — SMS action 6/24 fallback. Faz2 CTAS adayı."
            });
            rows = await QueryAsync(conn, $@"
SELECT CAST(ACT.ID AS NUMBER(12)) AS ACTION_ID,
       CAST(ACC.ID AS NUMBER(12)) AS ACCOUNT_ID,
       CAST(ACC.AGREEMENT_ID AS NUMBER(12)) AS SOZLESME,
       ACT.ACTION_TYPE_ID,
       ACT.ACTION_DATE AS PAY_DATE,
       CAST(ROUND(ABS(NVL(AMT.TUT,0)),2) AS NUMBER(15,3)) AS PAYABLETOTAL,
       CAST(ACT.REF_DEPOSIT_ACCOUNT_ID AS NUMBER(12)) AS DEP_ACCOUNT_ID,
       CAST(ACT.REF_DEPOSIT_ACCOUNT_ACTION_ID AS NUMBER(12)) AS DEP_ACTION_ID,
       CAST(DEP.ACCRUE_TYPE_ID AS NUMBER(10)) AS DEP_ACCRUE_TYPE_ID,
       CASE
         WHEN ACT.REF_DEPOSIT_ACCOUNT_ID IS NOT NULL
          AND NVL(DEP.ACCRUE_TYPE_ID, -1) = 14 THEN 'EMANET_MAHSUP'
         WHEN ACT.REF_DEPOSIT_ACCOUNT_ID IS NOT NULL THEN 'DEP_MAHSUP'
         ELSE 'MAHSUP'
       END AS MAHSUP_KIND,
       ACT.CREATED_USER_ID
  FROM {sms}.CS_ACCOUNT_ACTION ACT
  JOIN {sms}.CS_ACCOUNT ACC ON ACC.ID = ACT.ACCOUNT_ID
  LEFT JOIN {sms}.CS_ACCOUNT DEP ON DEP.ID = ACT.REF_DEPOSIT_ACCOUNT_ID
  LEFT JOIN (
    SELECT AI.ACCOUNT_ACTION_ID, SUM(AI.AMOUNT * AI.STATUS) TUT
      FROM {sms}.CS_ACCOUNT_INCOME AI
     GROUP BY AI.ACCOUNT_ACTION_ID
  ) AMT ON AMT.ACCOUNT_ACTION_ID = ACT.ID
 WHERE ACC.AGREEMENT_ID = :agrId
   AND ACT.ACTION_TYPE_ID IN (6, 24)
   AND ABS(NVL(AMT.TUT, 0)) > 0.0001
 ORDER BY ACT.ACTION_DATE DESC NULLS LAST, ACT.ID DESC
 FETCH FIRST 500 ROWS ONLY", req.AgreementId, ct);
        }

        var emanetMah = rows.Count(r =>
        {
            var k = Convert.ToString(r.GetValueOrDefault("MAHSUP_KIND")) ?? "";
            if (k == "EMANET_MAHSUP") return true;
            var dep = r.GetValueOrDefault("DEP_ACCOUNT_ID");
            return dep != null;
        });
        var multiDep = rows
            .Where(r => r.GetValueOrDefault("DEP_ACCOUNT_ID") != null)
            .GroupBy(r => Convert.ToString(r["DEP_ACCOUNT_ID"])!)
            .Count(g => g.Select(x => Convert.ToString(x.GetValueOrDefault("ACCOUNT_ID") ?? x.GetValueOrDefault("FATURAID"))).Distinct().Count() > 1);

        if (rows.Count == 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "MAHSUP_NONE",
                Severity = "INFO",
                Side = "SMS",
                Message = "Bu sözleşmede mahsup kaydı yok."
            });
        else if (emanetMah > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "EMANET_TO_DEBT_MAHSUP",
                Severity = "INFO",
                Side = "SMS",
                Message = $"{emanetMah} mahsup REF_DEPOSIT ile (emanet/iptal bakiyesi → fatura borcu); {multiDep} emanet çoklu faturaya."
            });

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, "mahsup", "SMS", "READ", sw.ElapsedMilliseconds,
            rows.Count, "OK", $"source={source} rows={rows.Count}");
        return (rows, gaps, log);
    }

    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadTaksitAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var mig = Sanitize(req.MigrationSchema);
        var sms = Sanitize(req.SmsSchema);

        await using var conn = new OracleConnection(req.OracleConnectionString);
        await conn.OpenAsync(ct);

        List<Dictionary<string, object?>> rows;
        string source;

        // YENI: Hem açık hem kapalı taksitleri getir, durum tespiti yap
        source = $"{sms}.CS_ACCOUNT+CS_INSTALLMENT (TÜM TAKSİTLER)";
        gaps.Add(new TahsilatGapItem
        {
            Code = "TAKSIT_ALL_INCLUSIVE",
            Severity = "INFO",
            Side = "SMS",
            Message = "Taksitler açık+kapalı+iptal dahil tüm durumlarla getiriliyor."
        });

        // Gerçek SMS şema: INSTALLMENT_NUMBER / TOTAL_AMOUNT / MONTHLY_AMOUNT / INSTALLMENT_DATE / DUE_DATE
        // (SEQUENCE_NUMBER, END_DATE vb. uydurma kolonlar → ORA-00904)
        var instCols = await GetColumnsAsync(conn, sms, "CS_INSTALLMENT", ct);
        var accCols = await GetColumnsAsync(conn, sms, "CS_ACCOUNT", ct);
        var noCol = FirstCol(instCols, "INSTALLMENT_NUMBER", "SEQUENCE_NUMBER", "ORDER_NUMBER", "INSTALLMENT_COUNT");
        var totalCntCol = FirstCol(instCols, "TOTAL_INSTALLMENTS", "INSTALLMENT_COUNT", "COUNT_");
        var amtCol = FirstCol(instCols, "TOTAL_AMOUNT", "MONTHLY_AMOUNT", "AMOUNT");
        var startCol = FirstCol(instCols, "INSTALLMENT_DATE", "START_DATE", "CREATE_DATE", "CREATED_TIMESTAMP");
        var endCol = FirstCol(instCols, "DUE_DATE", "END_DATE", "EXPIRY_DATE");
        var cancelCauseCol = FirstCol(instCols, "CANCEL_CAUSE_ID");
        var cancelDateCol = FirstCol(instCols, "CANCELLATION_DATE", "CANCEL_DATE");
        var cancelUserCol = FirstCol(instCols, "CANCELLATION_USER_ID", "CANCEL_USER_ID");
        var accDateCol = FirstCol(accCols,
            "CREATED_TIMESTAMP", "CREATE_DATE", "CREATION_DATE", "ACCOUNT_DATE", "OPEN_DATE", "START_DATE");

        var noExpr = noCol != null ? $"inst.{noCol}" : "NULL";
        var totalCntExpr = totalCntCol != null
            ? $"inst.{totalCntCol}"
            : (await TableExistsAsync(conn, sms, "CS_INSTALLMENT_PLAN", ct)
                ? $"(SELECT COUNT(*) FROM {sms}.CS_INSTALLMENT_PLAN p WHERE p.INSTALLMENT_ID = inst.ID)"
                : "NULL");
        var amtExpr = amtCol != null ? $"inst.{amtCol}" : "NULL";
        var startExpr = startCol != null ? $"inst.{startCol}" : "NULL";
        var endExpr = endCol != null ? $"inst.{endCol}" : "NULL";
        var accDateExpr = accDateCol != null ? $"a.{accDateCol}" : "CAST(NULL AS DATE)";

        var cancelParts = new List<string>();
        if (cancelCauseCol != null) cancelParts.Add($"inst.{cancelCauseCol} IS NOT NULL");
        if (cancelDateCol != null) cancelParts.Add($"inst.{cancelDateCol} IS NOT NULL");
        if (cancelUserCol != null) cancelParts.Add($"inst.{cancelUserCol} IS NOT NULL");
        var instCancelExpr = cancelParts.Count > 0
            ? $"CASE WHEN ({string.Join(" OR ", cancelParts)}) THEN 1 ELSE 0 END"
            : "0";

        rows = await QueryAsync(conn, $@"
WITH agr_acc AS (
  SELECT a.ID AS ACCOUNT_ID,
         a.AGREEMENT_ID,
         a.INSTALLMENT_ID,
         a.ACCRUE_TYPE_ID,
         {accDateExpr} AS HESAP_TARIH
    FROM {sms}.CS_ACCOUNT a
   WHERE a.AGREEMENT_ID = :agrId
     AND a.INSTALLMENT_ID IS NOT NULL
),
taksit_base AS (
  SELECT
    aa.ACCOUNT_ID AS FATURAID,
    aa.AGREEMENT_ID AS SOZLESME,
    aa.INSTALLMENT_ID,
    aa.ACCRUE_TYPE_ID,
    aa.HESAP_TARIH,
    {noExpr} AS TAKSIT_NO,
    {totalCntExpr} AS TOPLAM_TAKSIT,
    {amtExpr} AS TAKSIT_TUTARI,
    {startExpr} AS TAKSIT_BASLANGIC,
    {endExpr} AS TAKSIT_BITIS,
    {instCancelExpr} AS INST_IPTAL
  FROM agr_acc aa
  JOIN {sms}.CS_INSTALLMENT inst ON inst.ID = aa.INSTALLMENT_ID
),
agr_inc AS (
  SELECT aa.ACCOUNT_ID,
         aa.ID AS ACTION_ID,
         aa.ACTION_TYPE_ID,
         aa.ACTION_DATE,
         ai.AMOUNT,
         ai.STATUS
    FROM {sms}.CS_ACCOUNT_ACTION aa
    JOIN agr_acc a ON a.ACCOUNT_ID = aa.ACCOUNT_ID
    JOIN {sms}.CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = aa.ID
),
bal AS (
  SELECT
    ACCOUNT_ID,
    SUM(STATUS * AMOUNT) AS BALANCE,
    SUM(CASE WHEN STATUS > 0 THEN AMOUNT * STATUS ELSE 0 END) AS TOTAL_DEBT,
    SUM(CASE WHEN STATUS < 0 THEN ABS(AMOUNT * STATUS) ELSE 0 END) AS TOTAL_CREDIT
  FROM agr_inc
  GROUP BY ACCOUNT_ID
),
pay_info AS (
  SELECT
    ACCOUNT_ID,
    COUNT(DISTINCT ACTION_ID) AS TAHSILAT_ADET,
    SUM(ABS(AMOUNT * STATUS)) AS TAHSILAT_TUTAR,
    MAX(ACTION_DATE) AS SON_TAHSILAT_TARIH
  FROM agr_inc
  WHERE ACTION_TYPE_ID = 3
  GROUP BY ACCOUNT_ID
),
iptal_info AS (
  SELECT
    ACCOUNT_ID,
    COUNT(DISTINCT ACTION_ID) AS IPTAL_ADET,
    SUM(ABS(AMOUNT * STATUS)) AS IPTAL_TUTAR,
    MAX(ACTION_DATE) AS SON_IPTAL_TARIH
  FROM agr_inc
  WHERE ACTION_TYPE_ID = 9
  GROUP BY ACCOUNT_ID
)
SELECT
  t.FATURAID,
  t.SOZLESME,
  t.INSTALLMENT_ID,
  t.TAKSIT_NO,
  t.TOPLAM_TAKSIT,
  CAST(ROUND(NVL(t.TAKSIT_TUTARI, 0), 2) AS NUMBER(15,3)) AS TAKSIT_TUTARI,
  CAST(ROUND(NVL(b.BALANCE, 0), 2) AS NUMBER(15,3)) AS BALANCE,
  CAST(ROUND(NVL(b.TOTAL_DEBT, 0), 2) AS NUMBER(15,3)) AS TOTAL_DEBT,
  CAST(ROUND(NVL(b.TOTAL_CREDIT, 0), 2) AS NUMBER(15,3)) AS TOTAL_CREDIT,
  CAST(ROUND(NVL(p.TAHSILAT_TUTAR, 0), 2) AS NUMBER(15,3)) AS TAHSILAT_TUTAR,
  p.TAHSILAT_ADET,
  p.SON_TAHSILAT_TARIH,
  CAST(ROUND(NVL(i.IPTAL_TUTAR, 0), 2) AS NUMBER(15,3)) AS IPTAL_TUTAR,
  i.IPTAL_ADET,
  i.SON_IPTAL_TARIH,
  t.ACCRUE_TYPE_ID,
  t.HESAP_TARIH,
  t.TAKSIT_BASLANGIC,
  t.TAKSIT_BITIS,
  CASE
    WHEN t.INST_IPTAL = 1 OR NVL(i.IPTAL_ADET, 0) > 0 THEN 'IPTAL'
    WHEN ABS(NVL(b.BALANCE, 0)) <= 0.01 THEN 'KAPALI'
    WHEN NVL(b.BALANCE, 0) > 0.01 THEN 'ACIK'
    WHEN NVL(b.BALANCE, 0) < -0.01 THEN 'FAZLA_ODEME'
    ELSE 'BILINMIYOR'
  END AS TAKSIT_DURUMU,
  'T' AS TAKSIT_FLAG
FROM taksit_base t
LEFT JOIN bal b ON b.ACCOUNT_ID = t.FATURAID
LEFT JOIN pay_info p ON p.ACCOUNT_ID = t.FATURAID
LEFT JOIN iptal_info i ON i.ACCOUNT_ID = t.FATURAID
ORDER BY t.TAKSIT_NO, t.FATURAID
FETCH FIRST 500 ROWS ONLY", req.AgreementId, ct);

        var acik = rows.Count(r => Convert.ToString(r.GetValueOrDefault("TAKSIT_DURUMU")) == "ACIK");
        var kapali = rows.Count(r => Convert.ToString(r.GetValueOrDefault("TAKSIT_DURUMU")) == "KAPALI");
        var iptal = rows.Count(r => Convert.ToString(r.GetValueOrDefault("TAKSIT_DURUMU")) == "IPTAL");
        var fazla = rows.Count(r => Convert.ToString(r.GetValueOrDefault("TAKSIT_DURUMU")) == "FAZLA_ODEME");

        if (rows.Count == 0)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "TAKSIT_NONE",
                Severity = "INFO",
                Side = "SMS",
                Message = "Sözleşmede taksitli hesap yok."
            });
        }
        else
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "TAKSIT_SUMMARY",
                Severity = "INFO",
                Side = "SMS",
                Message = $"Taksit özet: ACIK={acik} KAPALI={kapali} IPTAL={iptal} FAZLA_ODEME={fazla} (Toplam={rows.Count})"
            });
        }

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, "taksit", "SMS", "READ", sw.ElapsedMilliseconds,
            rows.Count, "OK", $"source={source} rows={rows.Count} ACIK={acik} KAPALI={kapali} IPTAL={iptal}");
        return (rows, gaps, log);
    }

    /// <summary>KIND = TAM | KISMI (O20 LS_OV_EKS_CLASS).</summary>
    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadEksiltenAsync(AgreementTahsilatRequest req, string runId, string kind, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var mig = Sanitize(req.MigrationSchema);
        var sms = Sanitize(req.SmsSchema);
        kind = (kind ?? "").Trim().ToUpperInvariant();
        if (kind is not ("TAM" or "KISMI"))
            throw new ArgumentException("kind must be TAM or KISMI");

        var step = kind == "TAM" ? "tamEksilten" : "kismiEksilten";

        await using var conn = new OracleConnection(req.OracleConnectionString);
        await conn.OpenAsync(ct);

        List<Dictionary<string, object?>> rows;
        string source;

        if (await TableExistsAsync(conn, mig, "LS_OV_EKS_CLASS", ct))
        {
            source = $"{mig}.LS_OV_EKS_CLASS KIND={kind}";
            rows = await QueryAsync(conn, $@"
SELECT EC.EKS_ACTION_ID, EC.ACCOUNT_ID, EC.AGREEMENT_ID AS SOZLESME, EC.KIND,
       EC.EKS_AMT, EC.TAH_AMT, EC.MAIN_LREF, EC.MAIN_ACTION_ID,
       EC.EKS_DATE, EC.EKS_USER_ID, EC.MAIN_PAYABLETOTAL, EC.OWNERREF
  FROM {mig}.LS_OV_EKS_CLASS EC
 WHERE EC.AGREEMENT_ID = :agrId
   AND EC.KIND = '{kind}'
 ORDER BY EC.EKS_DATE DESC NULLS LAST, EC.EKS_ACTION_ID DESC
 FETCH FIRST 500 ROWS ONLY", req.AgreementId, ct);
        }
        else
        {
            source = $"{sms} live ACTION_TYPE_ID=2 classify";
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_LS_OV_EKS_CLASS",
                Severity = "WARN",
                Side = "SMS",
                Message = $"LS_OV_EKS_CLASS yok — live SMS tip2 sınıflama ({kind}). Faz2 / O20 CTAS adayı."
            });
            // Live: tip2 eksilten; TAM ≈ eks>=tah*0.995, KISMI aksi (ASIM hariç basit)
            rows = await QueryAsync(conn, $@"
SELECT * FROM (
  SELECT ACT.ID AS EKS_ACTION_ID, ACC.ID AS ACCOUNT_ID, ACC.AGREEMENT_ID AS SOZLESME,
         CASE
           WHEN NVL(EKS.TUT,0) > NVL(TAH.TUT,0) + 0.01 THEN 'ASIM'
           WHEN NVL(EKS.TUT,0) >= NVL(TAH.TUT,0) * 0.995 THEN 'TAM'
           ELSE 'KISMI'
         END AS KIND,
         NVL(EKS.TUT,0) AS EKS_AMT, NVL(TAH.TUT,0) AS TAH_AMT,
         ACT.ACTION_DATE AS EKS_DATE, ACT.CREATED_USER_ID AS EKS_USER_ID
    FROM {sms}.CS_ACCOUNT_ACTION ACT
    JOIN {sms}.CS_ACCOUNT ACC ON ACC.ID = ACT.ACCOUNT_ID
    LEFT JOIN (
      SELECT AI.ACCOUNT_ACTION_ID, SUM(ABS(AI.AMOUNT)) TUT
        FROM {sms}.CS_ACCOUNT_INCOME AI GROUP BY AI.ACCOUNT_ACTION_ID
    ) EKS ON EKS.ACCOUNT_ACTION_ID = ACT.ID
    LEFT JOIN (
      SELECT X.ACCOUNT_ID, SUM(ABS(I.AMOUNT)) TUT
        FROM {sms}.CS_ACCOUNT_ACTION X
        JOIN {sms}.CS_ACCOUNT_INCOME I ON I.ACCOUNT_ACTION_ID = X.ID
       WHERE X.ACTION_TYPE_ID = 1
       GROUP BY X.ACCOUNT_ID
    ) TAH ON TAH.ACCOUNT_ID = ACT.ACCOUNT_ID
   WHERE ACC.AGREEMENT_ID = :agrId
     AND ACT.ACTION_TYPE_ID = 2
     AND NVL(ACC.ACCRUE_TYPE_ID, -1) <> 14
) Z
 WHERE Z.KIND = '{kind}'
 ORDER BY Z.EKS_DATE DESC NULLS LAST
 FETCH FIRST 500 ROWS ONLY", req.AgreementId, ct);
        }

        if (rows.Count == 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = kind == "TAM" ? "TAM_EKS_NONE" : "KISMI_EKS_NONE",
                Severity = "INFO",
                Side = "SMS",
                Message = $"Bu sözleşmede {kind} eksilten yok."
            });

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, step, "SMS", "READ", sw.ElapsedMilliseconds,
            rows.Count, "OK", $"source={source} kind={kind} rows={rows.Count}");
        return (rows, gaps, log);
    }

    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadAllocAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var mig = Sanitize(req.MigrationSchema);
        var sms = Sanitize(req.SmsSchema);

        await using var conn = new OracleConnection(req.OracleConnectionString);
        await conn.OpenAsync(ct);

        List<Dictionary<string, object?>> rows;
        string source;

        if (await TableExistsAsync(conn, mig, "LS_OV_PAY_ALLOC", ct))
        {
            source = $"{mig}.LS_OV_PAY_ALLOC";
            // Kolon adları O30'a göre değişken olabilir — ALL_TAB_COLUMNS ile güvenli seçim
            var cols = await GetColumnsAsync(conn, mig, "LS_OV_PAY_ALLOC", ct);
            var agrCol = FirstCol(cols, "ABYS_AGREEMENT_ID", "AGREEMENT_ID", "SOZLESME");
            var payCol = FirstCol(cols, "PAY_LREF", "PAY_ID", "LREF");
            var mainCol = FirstCol(cols, "MAIN_LREF", "CROSSREF_MAIN_LREF");
            var allocCol = FirstCol(cols, "ALLOC_AMT", "ALLOC_PAY_CAP", "RAW_ALLOC", "PAY_AMT");
            var rawCol = FirstCol(cols, "RAW_ALLOC");
            var mainPayCol = FirstCol(cols, "MAIN_PAYABLE", "MAIN_PAYABLETOTAL", "PAYABLETOTAL");
            var accCol = FirstCol(cols, "ABYS_ACCOUNT_ID", "ACCOUNT_ID", "FATURAID");
            var typeCol = FirstCol(cols, "MAIN_ACTION_TYPE_ID", "ACTION_TYPE_ID");
            if (agrCol == null || payCol == null || mainCol == null)
            {
                gaps.Add(new TahsilatGapItem
                {
                    Code = "ALLOC_COLS_UNKNOWN",
                    Severity = "WARN",
                    Side = "SMS",
                    Message = $"LS_OV_PAY_ALLOC kolon eşleşmedi (agr/pay/main). Mevcut: {string.Join(',', cols.Take(12))}…"
                });
                rows = [];
            }
            else
            {
                var allocExpr = allocCol != null ? $"A.{allocCol}" : "NULL";
                var rawExpr = rawCol != null ? $"A.{rawCol}" : allocExpr;
                var mainPayExpr = mainPayCol != null ? $"A.{mainPayCol}" : "NULL";
                var accExpr = accCol != null ? $"A.{accCol}" : "NULL";
                var typeExpr = typeCol != null ? $"A.{typeCol}" : "NULL";
                rows = await QueryAsync(conn, $@"
SELECT A.{payCol} AS PAY_LREF, A.{mainCol} AS MAIN_LREF, A.{agrCol} AS SOZLESME,
       CAST({accExpr} AS NUMBER(12)) AS FATURAID,
       CAST(ROUND({allocExpr}, 2) AS NUMBER(15,3)) AS ALLOC_AMT,
       CAST(ROUND({rawExpr}, 2) AS NUMBER(15,3)) AS RAW_ALLOC,
       CAST(ROUND({mainPayExpr}, 2) AS NUMBER(15,3)) AS MAIN_PAYABLE,
       CAST(ROUND({mainPayExpr}, 2) AS NUMBER(15,3)) AS MAIN_AMT,
       {typeExpr} AS MAIN_ACTION_TYPE_ID
  FROM {mig}.LS_OV_PAY_ALLOC A
 WHERE A.{agrCol} = :agrId
 ORDER BY A.{payCol}, A.{mainCol}
 FETCH FIRST 2000 ROWS ONLY", req.AgreementId, ct);
            }
        }
        else if (await TableExistsAsync(conn, mig, "LS_OV_PAY_PT", ct))
        {
            source = $"{mig}.LS_OV_PAY_PT (MAIN aggregate)";
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_LS_OV_PAY_ALLOC",
                Severity = "WARN",
                Side = "SMS",
                Message = "LS_OV_PAY_ALLOC yok — PAY_PT MAIN kırılımı. Faz2/O30."
            });
            rows = await QueryAsync(conn, $@"
SELECT P.LREF AS PAY_LREF, P.CROSSREF_MAIN_LREF AS MAIN_LREF,
       P.ABYS_AGREEMENT_ID AS SOZLESME, P.ABYS_ACCOUNT_ID AS FATURAID,
       P.PAYABLETOTAL AS ALLOC_AMT, P.PAYABLETOTAL AS RAW_ALLOC,
       P.PAY_FULL_AMT, P.CANCELED, P.OV_KIND
  FROM {mig}.LS_OV_PAY_PT P
 WHERE P.ABYS_AGREEMENT_ID = :agrId
   AND P.CROSSREF_MAIN_LREF IS NOT NULL
   AND NVL(P.CANCELED,0)=0
 ORDER BY P.LREF, P.CROSSREF_MAIN_LREF
 FETCH FIRST 2000 ROWS ONLY", req.AgreementId, ct);
        }
        else
        {
            source = $"{sms} live INCOME_ID pay→main (O30 waterfill kaba)";
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_ALLOC_SOURCE",
                Severity = "WARN",
                Side = "SMS",
                Message = "PAY_ALLOC/PAY_PT yok — canlı SMS income-eşleme + MAIN_PAYABLE tavanı. O30 CTAS önerilir."
            });
            rows = await QueryLiveAllocAsync(conn, sms, req.AgreementId, ct);
        }

        // Gate T3 soft: aynı PAY için SUM(ALLOC) — sadece ALLOC_AMT sayısal ise
        if (rows.Count > 0 && rows[0].ContainsKey("ALLOC_AMT") && rows[0].ContainsKey("PAY_LREF"))
        {
            var over = rows
                .Where(r => r.GetValueOrDefault("PAY_LREF") != null)
                .GroupBy(r => Convert.ToString(r["PAY_LREF"])!)
                .Select(g => new
                {
                    Pay = g.Key,
                    Sum = g.Sum(x =>
                    {
                        var v = x.GetValueOrDefault("ALLOC_AMT");
                        return v == null ? 0m : Convert.ToDecimal(v);
                    }),
                    Full = g.Select(x =>
                    {
                        var v = x.GetValueOrDefault("PAY_FULL_AMT");
                        return v == null ? (decimal?)null : Convert.ToDecimal(v);
                    }).FirstOrDefault(x => x != null)
                })
                .Where(x => x.Full != null && x.Sum > x.Full.Value + 0.02m)
                .Take(20)
                .ToList();
            if (over.Count > 0)
                gaps.Add(new TahsilatGapItem
                {
                    Code = "ALLOC_GT_PAY_FULL",
                    Severity = "WARN",
                    Side = "SMS",
                    Message = $"T3: {over.Count}+ PAY'de SUM(ALLOC)>PAY_FULL (ör. PAY={over[0].Pay})."
                });
        }

        if (rows.Count == 0 && gaps.All(g => g.Severity != "CRITICAL"))
            gaps.Add(new TahsilatGapItem
            {
                Code = "ALLOC_NONE",
                Severity = "INFO",
                Side = "SMS",
                Message = "Bu sözleşme için alloc satırı yok."
            });

        // Fatura tavanı aşıldı mı? (RAW > MAIN_PAYABLE — waterfill öncesi)
        if (rows.Count > 0 && rows[0].ContainsKey("MAIN_PAYABLE"))
        {
            var overMain = rows.Count(r =>
            {
                var raw = Convert.ToDecimal(r.GetValueOrDefault("RAW_ALLOC") ?? r.GetValueOrDefault("ALLOC_AMT") ?? 0m);
                var main = Convert.ToDecimal(r.GetValueOrDefault("MAIN_PAYABLE") ?? 0m);
                return main > 0.01m && raw > main + 0.02m;
            });
            if (overMain > 0)
                gaps.Add(new TahsilatGapItem
                {
                    Code = "RAW_GT_MAIN_PAYABLE",
                    Severity = "INFO",
                    Side = "SMS",
                    Message = $"{overMain} satırda RAW_ALLOC > MAIN_PAYABLE — ALLOC fatura tavanına kısıldı."
                });
        }

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, "alloc", "SMS", "READ", sw.ElapsedMilliseconds,
            rows.Count, gaps.Any(g => g.Severity == "CRITICAL") ? "FAIL" : "OK",
            $"source={source} rows={rows.Count}");
        return (rows, gaps, log);
    }

    /// <summary>
    /// Canlı PAY→MAIN alloc (O30 waterfill basitleştirilmiş; LS_INVOICE yok).
    /// Income kırılımında ABS yok (işaretli SUM) — aksi halde devir satırları RAW’ı şişirir.
    /// RAW/ALLOC pozitif: ABS(Σ işaretli PAY_AMT). PAY_FULL/MAIN = ABS(aksiyon neti).
    /// ALLOC_AMT ≤ MAIN_PAYABLE ve Σ(ALLOC) ≤ PAY_FULL.
    /// </summary>
    private static async Task<List<Dictionary<string, object?>>> QueryLiveAllocAsync(
        OracleConnection conn, string sms, long agrId, CancellationToken ct)
    {
        return await QueryAsync(conn, $@"
WITH agr_acc AS (
  SELECT /*+ MATERIALIZE */ ID AS ACCOUNT_ID
    FROM {sms}.CS_ACCOUNT
   WHERE AGREEMENT_ID = :agrId
),
pay_inc AS (
  SELECT pay.ID AS PAY_LREF,
         pay.ACCOUNT_ID,
         CAST(:agrId AS NUMBER(12)) AS AGREEMENT_ID,
         pay.ACTION_DATE,
         pi.INCOME_ID,
         CAST(ROUND(SUM(pi.AMOUNT * pi.STATUS), 2) AS NUMBER(15,3)) AS PAY_AMT
    FROM agr_acc a
    JOIN {sms}.CS_ACCOUNT_ACTION pay ON pay.ACCOUNT_ID = a.ACCOUNT_ID
    JOIN {sms}.CS_ACTION_TYPE_PRM atp ON atp.ID = pay.ACTION_TYPE_ID AND atp.TYPE = 2
    JOIN {sms}.CS_ACCOUNT_INCOME pi ON pi.ACCOUNT_ACTION_ID = pay.ID
   WHERE pay.ACTION_TYPE_ID NOT IN (6, 24, 36, 37, 39, 44)
   GROUP BY pay.ID, pay.ACCOUNT_ID, pay.ACTION_DATE, pi.INCOME_ID
  HAVING ABS(SUM(pi.AMOUNT * pi.STATUS)) > 0.0001
),
main_inc AS (
  SELECT g.ID AS MAIN_LREF,
         g.ACCOUNT_ID,
         g.ACTION_DATE,
         g.ACTION_TYPE_ID,
         ai.INCOME_ID,
         CAST(g.ACCOUNT_ID AS NUMBER(12)) AS FATURAID,
         CAST(:agrId AS NUMBER(12)) AS SOZLESME
    FROM agr_acc a
    JOIN {sms}.CS_ACCOUNT_ACTION g ON g.ACCOUNT_ID = a.ACCOUNT_ID
    JOIN {sms}.CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = g.ID
   WHERE g.ACTION_TYPE_ID IN (1, 3, 10, 41)
),
picked AS (
  SELECT pi.PAY_LREF,
         pi.PAY_AMT,
         pi.ACTION_DATE AS PAY_ACTION_DATE,
         mi.MAIN_LREF,
         mi.FATURAID,
         mi.SOZLESME,
         mi.ACTION_TYPE_ID AS MAIN_ACTION_TYPE_ID,
         ROW_NUMBER() OVER (
           PARTITION BY pi.PAY_LREF, pi.INCOME_ID, mi.ACTION_TYPE_ID
           ORDER BY mi.ACTION_DATE ASC, mi.MAIN_LREF ASC
         ) AS RN
    FROM pay_inc pi
    JOIN main_inc mi
      ON mi.ACCOUNT_ID = pi.ACCOUNT_ID
     AND mi.INCOME_ID = pi.INCOME_ID
),
raw_by_pm AS (
  SELECT PAY_LREF, MAIN_LREF, FATURAID, SOZLESME, MAIN_ACTION_TYPE_ID,
         MAX(PAY_ACTION_DATE) AS PAY_ACTION_DATE,
         CAST(ROUND(ABS(SUM(PAY_AMT)), 2) AS NUMBER(15,3)) AS RAW_ALLOC
    FROM picked
   WHERE RN = 1
   GROUP BY PAY_LREF, MAIN_LREF, FATURAID, SOZLESME, MAIN_ACTION_TYPE_ID
  HAVING ABS(SUM(PAY_AMT)) > 0.0001
),
main_pay AS (
  SELECT AI.ACCOUNT_ACTION_ID AS MAIN_LREF,
         CAST(ROUND(ABS(SUM(AI.AMOUNT * AI.STATUS)), 2) AS NUMBER(15,3)) AS MAIN_PAYABLE
    FROM {sms}.CS_ACCOUNT_INCOME AI
   WHERE AI.ACCOUNT_ACTION_ID IN (SELECT MAIN_LREF FROM raw_by_pm)
   GROUP BY AI.ACCOUNT_ACTION_ID
),
pay_full AS (
  SELECT AI.ACCOUNT_ACTION_ID AS PAY_LREF,
         CAST(ROUND(ABS(SUM(AI.AMOUNT * AI.STATUS)), 2) AS NUMBER(15,3)) AS PAY_FULL_AMT
    FROM {sms}.CS_ACCOUNT_INCOME AI
   WHERE AI.ACCOUNT_ACTION_ID IN (SELECT PAY_LREF FROM raw_by_pm)
   GROUP BY AI.ACCOUNT_ACTION_ID
),
joined AS (
  SELECT r.PAY_LREF, r.MAIN_LREF, r.FATURAID, r.SOZLESME, r.MAIN_ACTION_TYPE_ID,
         r.PAY_ACTION_DATE, r.RAW_ALLOC,
         NVL(mp.MAIN_PAYABLE, 0) AS MAIN_PAYABLE,
         NVL(pf.PAY_FULL_AMT, r.RAW_ALLOC) AS PAY_FULL_AMT,
         CASE NVL(r.MAIN_ACTION_TYPE_ID, 99)
           WHEN 1 THEN 0 WHEN 3 THEN 1 WHEN 41 THEN 2 WHEN 10 THEN 3 ELSE 4
         END AS MAIN_PRI,
         CAST(ROUND(
           CASE
             WHEN NVL(mp.MAIN_PAYABLE, 0) > 0 AND r.RAW_ALLOC > mp.MAIN_PAYABLE
             THEN mp.MAIN_PAYABLE
             ELSE r.RAW_ALLOC
           END
         , 2) AS NUMBER(15,3)) AS RAW_MAIN_CAP
    FROM raw_by_pm r
    LEFT JOIN main_pay mp ON mp.MAIN_LREF = r.MAIN_LREF
    LEFT JOIN pay_full pf ON pf.PAY_LREF = r.PAY_LREF
),
pay_wf AS (
  SELECT j.*,
         CAST(ROUND(
           GREATEST(0,
             LEAST(
               j.RAW_MAIN_CAP,
               GREATEST(0,
                 j.PAY_FULL_AMT
                 - NVL(SUM(j.RAW_MAIN_CAP) OVER (
                     PARTITION BY j.PAY_LREF
                     ORDER BY j.MAIN_PRI, j.MAIN_LREF
                     ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                   ), 0)
               )
             )
           )
         , 2) AS NUMBER(15,3)) AS ALLOC_PAY_CAP
    FROM joined j
),
main_wf AS (
  SELECT p.*,
         CAST(ROUND(
           GREATEST(0,
             LEAST(
               p.ALLOC_PAY_CAP,
               CASE
                 WHEN p.MAIN_PAYABLE > 0 THEN
                   GREATEST(0,
                     p.MAIN_PAYABLE
                     - NVL(SUM(p.ALLOC_PAY_CAP) OVER (
                         PARTITION BY p.MAIN_LREF
                         ORDER BY p.PAY_ACTION_DATE, p.PAY_LREF
                         ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                       ), 0)
                   )
                 ELSE p.ALLOC_PAY_CAP
               END
             )
           )
         , 2) AS NUMBER(15,3)) AS ALLOC_AMT
    FROM pay_wf p
)
SELECT PAY_LREF, MAIN_LREF, FATURAID, SOZLESME,
       ALLOC_AMT, RAW_ALLOC,
       MAIN_PAYABLE, MAIN_PAYABLE AS MAIN_AMT,
       PAY_FULL_AMT, MAIN_ACTION_TYPE_ID
  FROM main_wf
 WHERE ALLOC_AMT > 0.0001
 ORDER BY PAY_LREF, MAIN_LREF
 FETCH FIRST 500 ROWS ONLY", agrId, ct);
    }

    /// <summary>
    /// Tahakkuk (MAIN tip1/3/10/41) ↔ tahsilat (ATP.TYPE=2) eşleşme durumu.
    /// MATCHED | TAHAKKUK_ONLY | TAHSILAT_ONLY
    /// </summary>
    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadEslesmeAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var mig = Sanitize(req.MigrationSchema);
        var sms = Sanitize(req.SmsSchema);

        await using var conn = new OracleConnection(req.OracleConnectionString);
        await conn.OpenAsync(ct);

        List<Dictionary<string, object?>> rows;
        string source;

        if (await TableExistsAsync(conn, mig, "LS_OV_PAY_ALLOC", ct))
        {
            source = $"{mig}.LS_OV_PAY_ALLOC + live MAIN/PAY";
            var cols = await GetColumnsAsync(conn, mig, "LS_OV_PAY_ALLOC", ct);
            var agrCol = FirstCol(cols, "ABYS_AGREEMENT_ID", "AGREEMENT_ID", "SOZLESME");
            var payCol = FirstCol(cols, "PAY_LREF", "PAY_ID", "LREF");
            var mainCol = FirstCol(cols, "MAIN_LREF", "CROSSREF_MAIN_LREF");
            var allocCol = FirstCol(cols, "ALLOC_AMT", "ALLOC_PAY_CAP", "RAW_ALLOC", "PAY_AMT");
            if (agrCol == null || payCol == null || mainCol == null)
            {
                gaps.Add(new TahsilatGapItem
                {
                    Code = "ESLESME_ALLOC_COLS",
                    Severity = "WARN",
                    Side = "SMS",
                    Message = "LS_OV_PAY_ALLOC kolonları eksik — canlı income eşleşme kullanılacak."
                });
                rows = await QueryLiveEslesmeAsync(conn, sms, req.AgreementId, ct);
                source = $"{sms} live INCOME_ID (alloc kolon yok)";
            }
            else
            {
                var allocExpr = allocCol != null ? $"A.{allocCol}" : "NULL";
                rows = await QueryAsync(conn, $@"
WITH agr_acc AS (
  SELECT /*+ MATERIALIZE */ ID AS ACCOUNT_ID
    FROM {sms}.CS_ACCOUNT
   WHERE AGREEMENT_ID = :agrId
),
alloc AS (
  SELECT A.{payCol} AS PAY_LREF, A.{mainCol} AS MAIN_LREF, A.{agrCol} AS SOZLESME,
         {allocExpr} AS ALLOC_AMT
    FROM {mig}.LS_OV_PAY_ALLOC A
   WHERE A.{agrCol} = :agrId
),
main_all AS (
  SELECT CAST(g.ID AS NUMBER(12)) AS MAIN_LREF,
         CAST(acc.ACCOUNT_ID AS NUMBER(12)) AS FATURAID,
         CAST(:agrId AS NUMBER(12)) AS SOZLESME,
         g.ACTION_TYPE_ID AS MAIN_ACTION_TYPE_ID,
         CAST(ROUND(ABS(NVL(amt.TUT,0)),2) AS NUMBER(15,3)) AS MAIN_AMT
    FROM agr_acc acc
    JOIN {sms}.CS_ACCOUNT_ACTION g ON g.ACCOUNT_ID = acc.ACCOUNT_ID
    LEFT JOIN (
      SELECT AI.ACCOUNT_ACTION_ID, SUM(AI.AMOUNT * AI.STATUS) TUT
        FROM {sms}.CS_ACCOUNT_INCOME AI
        JOIN {sms}.CS_ACCOUNT_ACTION aa ON aa.ID = AI.ACCOUNT_ACTION_ID
        JOIN agr_acc a2 ON a2.ACCOUNT_ID = aa.ACCOUNT_ID
       GROUP BY AI.ACCOUNT_ACTION_ID
    ) amt ON amt.ACCOUNT_ACTION_ID = g.ID
   WHERE g.ACTION_TYPE_ID IN (1, 3, 10, 41)
),
pay_all AS (
  SELECT CAST(pay.ID AS NUMBER(12)) AS PAY_LREF,
         CAST(acc.ACCOUNT_ID AS NUMBER(12)) AS FATURAID,
         CAST(:agrId AS NUMBER(12)) AS SOZLESME,
         CAST(ROUND(ABS(NVL(amt.TUT,0)),2) AS NUMBER(15,3)) AS PAY_AMT
    FROM agr_acc acc
    JOIN {sms}.CS_ACCOUNT_ACTION pay ON pay.ACCOUNT_ID = acc.ACCOUNT_ID
    JOIN {sms}.CS_ACTION_TYPE_PRM atp ON atp.ID = pay.ACTION_TYPE_ID AND atp.TYPE = 2
    LEFT JOIN (
      SELECT AI.ACCOUNT_ACTION_ID, SUM(AI.AMOUNT * AI.STATUS) TUT
        FROM {sms}.CS_ACCOUNT_INCOME AI
        JOIN {sms}.CS_ACCOUNT_ACTION aa ON aa.ID = AI.ACCOUNT_ACTION_ID
        JOIN agr_acc a2 ON a2.ACCOUNT_ID = aa.ACCOUNT_ID
       GROUP BY AI.ACCOUNT_ACTION_ID
    ) amt ON amt.ACCOUNT_ACTION_ID = pay.ID
   WHERE pay.ACTION_TYPE_ID NOT IN (6, 24, 36, 37, 39, 44)
     AND ABS(NVL(amt.TUT,0)) > 0.0001
)
SELECT 'MATCHED' AS MATCH_STATUS, a.PAY_LREF, a.MAIN_LREF, a.SOZLESME,
       m.FATURAID, a.ALLOC_AMT, m.MAIN_AMT, p.PAY_AMT, m.MAIN_ACTION_TYPE_ID
  FROM alloc a
  LEFT JOIN main_all m ON m.MAIN_LREF = a.MAIN_LREF
  LEFT JOIN pay_all p ON p.PAY_LREF = a.PAY_LREF
UNION ALL
SELECT 'TAHAKKUK_ONLY', CAST(NULL AS NUMBER), m.MAIN_LREF, m.SOZLESME,
       m.FATURAID, CAST(NULL AS NUMBER), m.MAIN_AMT, CAST(NULL AS NUMBER), m.MAIN_ACTION_TYPE_ID
  FROM main_all m
 WHERE NOT EXISTS (SELECT 1 FROM alloc a WHERE a.MAIN_LREF = m.MAIN_LREF)
UNION ALL
SELECT 'TAHSILAT_ONLY', p.PAY_LREF, CAST(NULL AS NUMBER), p.SOZLESME,
       p.FATURAID, CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), p.PAY_AMT, CAST(NULL AS NUMBER)
  FROM pay_all p
 WHERE NOT EXISTS (SELECT 1 FROM alloc a WHERE a.PAY_LREF = p.PAY_LREF)
ORDER BY 1, 3 NULLS LAST, 2 NULLS LAST
FETCH FIRST 500 ROWS ONLY", req.AgreementId, ct);
            }
        }
        else
        {
            source = $"{sms} live INCOME_ID eşleşme";
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_LS_OV_PAY_ALLOC_ESLESME",
                Severity = "WARN",
                Side = "SMS",
                Message = "LS_OV_PAY_ALLOC yok — eşleşme canlı INCOME_ID ile (yaklaşık). O30 CTAS önerilir."
            });
            rows = await QueryLiveEslesmeAsync(conn, sms, req.AgreementId, ct);
        }

        var matched = rows.Count(r => Convert.ToString(r.GetValueOrDefault("MATCH_STATUS")) == "MATCHED");
        var tahOnly = rows.Count(r => Convert.ToString(r.GetValueOrDefault("MATCH_STATUS")) == "TAHAKKUK_ONLY");
        var tahsilOnly = rows.Count(r => Convert.ToString(r.GetValueOrDefault("MATCH_STATUS")) == "TAHSILAT_ONLY");
        var tahOnlyOpen = rows
            .Where(r => Convert.ToString(r.GetValueOrDefault("MATCH_STATUS")) == "TAHAKKUK_ONLY")
            .Sum(r => Math.Max(0m, Convert.ToDecimal(r.GetValueOrDefault("MAIN_AMT") ?? 0m)));
        var tahOnlyZero = rows.Count(r =>
            Convert.ToString(r.GetValueOrDefault("MATCH_STATUS")) == "TAHAKKUK_ONLY"
            && Math.Abs(Convert.ToDecimal(r.GetValueOrDefault("MAIN_AMT") ?? 0m)) < 0.01m);
        var matchedAlloc = rows
            .Where(r => Convert.ToString(r.GetValueOrDefault("MATCH_STATUS")) == "MATCHED")
            .Sum(r => Convert.ToDecimal(r.GetValueOrDefault("ALLOC_AMT") ?? 0m));
        var tahsilOnlyAmt = rows
            .Where(r => Convert.ToString(r.GetValueOrDefault("MATCH_STATUS")) == "TAHSILAT_ONLY")
            .Sum(r => Convert.ToDecimal(r.GetValueOrDefault("PAY_AMT") ?? 0m));


        if (tahOnly > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "TAHAKKUK_NO_TAHSILAT",
                Severity = tahOnlyOpen > 0.01m ? "WARN" : "INFO",
                Side = "SMS",
                Message = $"{tahOnly} TAHAKKUK_ONLY (açık borç≈{tahOnlyOpen:0.##} TL; sıfır tutar={tahOnlyZero})."
            });
        if (tahsilOnly > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "TAHSILAT_NO_TAHAKKUK",
                Severity = "WARN",
                Side = "SMS",
                Message = $"{tahsilOnly} TAHSILAT_ONLY (pay≈{tahsilOnlyAmt:0.##} TL) — yetim tahsilat."
            });
        if (tahOnly == 0 && tahsilOnly == 0 && matched > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "ESLESME_ALL_OK",
                Severity = "INFO",
                Side = "SMS",
                Message = $"Tüm satırlar eşleşti (MATCHED={matched}, alloc≈{matchedAlloc:0.##})."
            });
        else if (rows.Count == 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "ESLESME_NONE",
                Severity = "WARN",
                Side = "SMS",
                Message = "Bu sözleşmede tahakkuk/tahsilat satırı yok."
            });

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, "eslesme", "SMS", "READ", sw.ElapsedMilliseconds,
            rows.Count, "OK",
            $"source={source} matched={matched} alloc={matchedAlloc} tah_only={tahOnly} open={tahOnlyOpen} tahsil_only={tahsilOnly}");
        return (rows, gaps, log);
    }

    private static async Task<List<Dictionary<string, object?>>> QueryLiveEslesmeAsync(
        OracleConnection conn, string sms, long agrId, CancellationToken ct)
    {
        // AGR önce — CS_ACCOUNT_INCOME full GROUP BY yok (eski sürüm tüm tabloyu tarıyordu).
        return await QueryAsync(conn, $@"
WITH agr_acc AS (
  SELECT /*+ MATERIALIZE */ ID AS ACCOUNT_ID
    FROM {sms}.CS_ACCOUNT
   WHERE AGREEMENT_ID = :agrId
),
pay_inc AS (
  SELECT pay.ID AS PAY_LREF, pay.ACCOUNT_ID, CAST(:agrId AS NUMBER(12)) AS AGREEMENT_ID,
         pay.ACTION_DATE, pi.INCOME_ID,
         CAST(ROUND(SUM(pi.AMOUNT * pi.STATUS), 2) AS NUMBER(15,3)) AS PAY_AMT
    FROM agr_acc a
    JOIN {sms}.CS_ACCOUNT_ACTION pay ON pay.ACCOUNT_ID = a.ACCOUNT_ID
    JOIN {sms}.CS_ACTION_TYPE_PRM atp ON atp.ID = pay.ACTION_TYPE_ID AND atp.TYPE = 2
    JOIN {sms}.CS_ACCOUNT_INCOME pi ON pi.ACCOUNT_ACTION_ID = pay.ID
   WHERE pay.ACTION_TYPE_ID NOT IN (6, 24, 36, 37, 39, 44)
   GROUP BY pay.ID, pay.ACCOUNT_ID, pay.ACTION_DATE, pi.INCOME_ID
  HAVING ABS(SUM(pi.AMOUNT * pi.STATUS)) > 0.0001
),
main_inc AS (
  SELECT g.ID AS MAIN_LREF, g.ACCOUNT_ID, g.ACTION_DATE, g.ACTION_TYPE_ID, ai.INCOME_ID,
         CAST(g.ACCOUNT_ID AS NUMBER(12)) AS FATURAID,
         CAST(:agrId AS NUMBER(12)) AS SOZLESME,
         CAST(ROUND(ai.AMOUNT * ai.STATUS, 2) AS NUMBER(15,3)) AS INC_AMT
    FROM agr_acc a
    JOIN {sms}.CS_ACCOUNT_ACTION g ON g.ACCOUNT_ID = a.ACCOUNT_ID
    JOIN {sms}.CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = g.ID
   WHERE g.ACTION_TYPE_ID IN (1, 3, 10, 41)
),
picked AS (
  SELECT pi.PAY_LREF, pi.PAY_AMT, pi.AGREEMENT_ID AS SOZLESME, mi.MAIN_LREF, mi.FATURAID,
         mi.ACTION_TYPE_ID AS MAIN_ACTION_TYPE_ID,
         ROW_NUMBER() OVER (
           PARTITION BY pi.PAY_LREF, pi.INCOME_ID, mi.ACTION_TYPE_ID
           ORDER BY mi.MAIN_LREF ASC
         ) AS RN
    FROM pay_inc pi
    JOIN main_inc mi
      ON mi.ACCOUNT_ID = pi.ACCOUNT_ID
     AND mi.INCOME_ID = pi.INCOME_ID
),
alloc AS (
  SELECT PAY_LREF, MAIN_LREF, SOZLESME, FATURAID, MAIN_ACTION_TYPE_ID,
         CAST(ROUND(ABS(SUM(PAY_AMT)), 2) AS NUMBER(15,3)) AS ALLOC_AMT
    FROM picked WHERE RN = 1
   GROUP BY PAY_LREF, MAIN_LREF, SOZLESME, FATURAID, MAIN_ACTION_TYPE_ID
  HAVING ABS(SUM(PAY_AMT)) > 0.0001
),
main_all AS (
  SELECT MAIN_LREF, FATURAID, SOZLESME, ACTION_TYPE_ID AS MAIN_ACTION_TYPE_ID,
         CAST(ROUND(SUM(INC_AMT), 2) AS NUMBER(15,3)) AS MAIN_AMT
    FROM main_inc
   GROUP BY MAIN_LREF, FATURAID, SOZLESME, ACTION_TYPE_ID
),
pay_all AS (
  SELECT PAY_LREF,
         CAST(MAX(ACCOUNT_ID) AS NUMBER(12)) AS FATURAID,
         CAST(MAX(AGREEMENT_ID) AS NUMBER(12)) AS SOZLESME,
         CAST(ROUND(ABS(SUM(PAY_AMT)), 2) AS NUMBER(15,3)) AS PAY_AMT
    FROM pay_inc
   GROUP BY PAY_LREF
)
SELECT 'MATCHED' AS MATCH_STATUS, a.PAY_LREF, a.MAIN_LREF, a.SOZLESME,
       a.FATURAID, a.ALLOC_AMT, m.MAIN_AMT, p.PAY_AMT, a.MAIN_ACTION_TYPE_ID
  FROM alloc a
  LEFT JOIN main_all m ON m.MAIN_LREF = a.MAIN_LREF
  LEFT JOIN pay_all p ON p.PAY_LREF = a.PAY_LREF
UNION ALL
SELECT 'TAHAKKUK_ONLY', CAST(NULL AS NUMBER), m.MAIN_LREF, m.SOZLESME,
       m.FATURAID, CAST(NULL AS NUMBER), m.MAIN_AMT, CAST(NULL AS NUMBER), m.MAIN_ACTION_TYPE_ID
  FROM main_all m
 WHERE NOT EXISTS (SELECT 1 FROM alloc a WHERE a.MAIN_LREF = m.MAIN_LREF)
UNION ALL
SELECT 'TAHSILAT_ONLY', p.PAY_LREF, CAST(NULL AS NUMBER), p.SOZLESME,
       p.FATURAID, CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), p.PAY_AMT, CAST(NULL AS NUMBER)
  FROM pay_all p
 WHERE NOT EXISTS (SELECT 1 FROM alloc a WHERE a.PAY_LREF = p.PAY_LREF)
ORDER BY 1, 3 NULLS LAST, 2 NULLS LAST
FETCH FIRST 500 ROWS ONLY", agrId, ct);
    }

    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadAsimEksiltenAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var mig = Sanitize(req.MigrationSchema);

        await using var conn = new OracleConnection(req.OracleConnectionString);
        await conn.OpenAsync(ct);

        List<Dictionary<string, object?>> rows;
        if (await TableExistsAsync(conn, mig, "LS_OV_EKS_SKIP", ct))
        {
            rows = await QueryAsync(conn, $@"
SELECT S.EKS_ACTION_ID, S.ACCOUNT_ID, S.MAIN_LREF, S.EKS_AMT, S.TAH_AMT, S.REASON,
       A.AGREEMENT_ID AS SOZLESME
  FROM {mig}.LS_OV_EKS_SKIP S
  LEFT JOIN {Sanitize(req.SmsSchema)}.CS_ACCOUNT A ON A.ID = S.ACCOUNT_ID
 WHERE A.AGREEMENT_ID = :agrId OR S.ACCOUNT_ID IN (
       SELECT ID FROM {Sanitize(req.SmsSchema)}.CS_ACCOUNT WHERE AGREEMENT_ID = :agrId)
 FETCH FIRST 200 ROWS ONLY", req.AgreementId, ct);
        }
        else if (await TableExistsAsync(conn, mig, "LS_OV_EKS_CLASS", ct))
        {
            rows = await QueryAsync(conn, $@"
SELECT EC.EKS_ACTION_ID, EC.ACCOUNT_ID, EC.AGREEMENT_ID AS SOZLESME, EC.KIND,
       EC.EKS_AMT, EC.TAH_AMT, EC.MAIN_LREF, EC.EKS_DATE
  FROM {mig}.LS_OV_EKS_CLASS EC
 WHERE EC.AGREEMENT_ID = :agrId AND EC.KIND = 'ASIM'
 FETCH FIRST 200 ROWS ONLY", req.AgreementId, ct);
        }
        else
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_EKS_ASIM_SOURCE",
                Severity = "INFO",
                Side = "SMS",
                Message = "ASIM kaynağı yok (EKS_SKIP/EKS_CLASS)."
            });
            rows = [];
        }

        if (rows.Count > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "ASIM_EKSILTEN",
                Severity = "WARN",
                Side = "SMS",
                Message = $"{rows.Count} ASIM eksilten (EKS>TAH) — manuel inceleme; overlay skip."
            });
        else if (gaps.Count == 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "ASIM_NONE",
                Severity = "INFO",
                Side = "SMS",
                Message = "ASIM eksilten yok."
            });

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, "asimEksilten", "SMS", "READ", sw.ElapsedMilliseconds,
            rows.Count, rows.Count > 0 ? "WARN" : "OK", $"asim_rows={rows.Count}");
        return (rows, gaps, log);
    }

    /// <summary>
    /// Kovalar: EKSILTEN_CLOSE | PAY_CANCEL | CANCEL_EMANET (tip12) |
    /// EMANET_MAHSUP (REF_DEPOSIT → başka fatura borcu tip6/24).
    /// </summary>
    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadIptalEmanetAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var sms = Sanitize(req.SmsSchema);
        var mig = Sanitize(req.MigrationSchema);

        await using var conn = new OracleConnection(req.OracleConnectionString);
        await conn.OpenAsync(ct);

        List<Dictionary<string, object?>> rows;
        string source;

        if (await TableExistsAsync(conn, mig, "LS_OV_EKS_CLASS", ct)
            && await TableExistsAsync(conn, mig, "LS_OV_PAY_PT", ct))
        {
            source = $"{mig} EKS/PAY_PT + live EMANET_MAHSUP";
            rows = await QueryAsync(conn, $@"
WITH {AgrIncomeCte(sms)}
SELECT CAST('EKSILTEN_CLOSE' AS VARCHAR2(20)) AS KIND,
       CAST(EC.EKS_ACTION_ID AS NUMBER(12)) AS ACTION_ID,
       CAST(EC.ACCOUNT_ID AS NUMBER(12)) AS FATURAID,
       CAST(EC.AGREEMENT_ID AS NUMBER(12)) AS SOZLESME,
       CAST(EC.MAIN_LREF AS NUMBER(12)) AS MAIN_LREF,
       CAST(NULL AS NUMBER(12)) AS PAY_LREF,
       CAST(NULL AS NUMBER(12)) AS DEP_ACCOUNT_ID,
       CAST(ROUND(EC.EKS_AMT, 2) AS NUMBER(15,3)) AS AMT,
       EC.EKS_DATE AS ACTION_DATE,
       CAST('tip2 TAM eksilten → MAIN kapama' AS VARCHAR2(100)) AS NOTE
  FROM {mig}.LS_OV_EKS_CLASS EC
 WHERE EC.AGREEMENT_ID = :agrId AND EC.KIND = 'TAM'
UNION ALL
SELECT CAST('PAY_CANCEL' AS VARCHAR2(20)),
       CAST(P.ABYS_ID AS NUMBER(12)),
       CAST(P.ABYS_ACCOUNT_ID AS NUMBER(12)),
       CAST(P.ABYS_AGREEMENT_ID AS NUMBER(12)),
       CAST(P.CROSSREF_MAIN_LREF AS NUMBER(12)),
       CAST(P.LREF AS NUMBER(12)),
       CAST(NULL AS NUMBER(12)),
       CAST(ROUND(P.PAYABLETOTAL, 2) AS NUMBER(15,3)),
       P.DATE_,
       CAST('PAY_PT CANCELED=1 (tip9 makbuz)' AS VARCHAR2(100))
  FROM {mig}.LS_OV_PAY_PT P
 WHERE P.ABYS_AGREEMENT_ID = :agrId AND NVL(P.CANCELED, 0) = 1
UNION ALL
SELECT CAST('CANCEL_EMANET' AS VARCHAR2(20)),
       CAST(aa.ID AS NUMBER(12)),
       CAST(a.ACCOUNT_ID AS NUMBER(12)),
       CAST(:agrId AS NUMBER(12)),
       CAST(aa.REF_DEPOSIT_ACCOUNT_ID AS NUMBER(12)),
       CAST(NULL AS NUMBER(12)),
       CAST(a.ACCOUNT_ID AS NUMBER(12)),
       CAST(ROUND(ABS(NVL(amt.TUT, 0)), 2) AS NUMBER(15,3)),
       aa.ACTION_DATE,
       CAST(
         'tip12 EMANET ÇIKIŞI' ||
         CASE WHEN aa.REF_DEPOSIT_ACCOUNT_ID IS NOT NULL
              THEN ' → borç fatura ' || TO_CHAR(aa.REF_DEPOSIT_ACCOUNT_ID)
              ELSE '' END
         AS VARCHAR2(100)
       )
  FROM agr_acc a
  JOIN {sms}.CS_ACCOUNT_ACTION aa ON aa.ACCOUNT_ID = a.ACCOUNT_ID
  LEFT JOIN agr_inc amt ON amt.ACCOUNT_ACTION_ID = aa.ID
 WHERE aa.ACTION_TYPE_ID = 12
UNION ALL
SELECT CAST('EMANET_GIRIS' AS VARCHAR2(20)),
       CAST(aa.ID AS NUMBER(12)),
       CAST(a.ACCOUNT_ID AS NUMBER(12)),
       CAST(:agrId AS NUMBER(12)),
       CAST(NULL AS NUMBER(12)),
       CAST(NULL AS NUMBER(12)),
       CAST(NVL(aa.REF_DEPOSIT_ACCOUNT_ID, a.ACCOUNT_ID) AS NUMBER(12)),
       CAST(ROUND(ABS(NVL(amt.TUT, 0)), 2) AS NUMBER(15,3)),
       aa.ACTION_DATE,
       CAST('tip20 EMANET GİRİŞİ — güvence (162/1936) / iptal bakiyesi' AS VARCHAR2(100))
  FROM agr_acc a
  JOIN {sms}.CS_ACCOUNT_ACTION aa ON aa.ACCOUNT_ID = a.ACCOUNT_ID
  JOIN {sms}.CS_ACCOUNT acc ON acc.ID = a.ACCOUNT_ID
  LEFT JOIN agr_inc amt ON amt.ACCOUNT_ACTION_ID = aa.ID
 WHERE aa.ACTION_TYPE_ID = 20
   AND NVL(acc.ACCRUE_TYPE_ID, -1) = 14
UNION ALL
SELECT * FROM (
{EmanetMahsupSelectSql(sms)}
)
ORDER BY 1, 2
FETCH FIRST 500 ROWS ONLY", req.AgreementId, ct);
        }
        else
        {
            source = $"{sms} live tip2/9/12 + EMANET_MAHSUP";
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_OV_IPTAL_SOURCE",
                Severity = "WARN",
                Side = "SMS",
                Message = "LS_OV_EKS_CLASS/PAY_PT yok — canlı tip2/9/12 + emanet→mahsup."
            });
            rows = await QueryLiveIptalEmanetAsync(conn, sms, req.AgreementId, ct);
        }

        var eksClose = rows.Count(r => Convert.ToString(r.GetValueOrDefault("KIND")) == "EKSILTEN_CLOSE");
        var payCancel = rows.Count(r => Convert.ToString(r.GetValueOrDefault("KIND")) == "PAY_CANCEL");
        var cancelEmanet = rows.Count(r => Convert.ToString(r.GetValueOrDefault("KIND")) == "CANCEL_EMANET");
        var emanetGiris = rows.Count(r => Convert.ToString(r.GetValueOrDefault("KIND")) == "EMANET_GIRIS");
        var emanetMahsup = rows.Count(r => Convert.ToString(r.GetValueOrDefault("KIND")) == "EMANET_MAHSUP");
        var multiDep = rows
            .Where(r => Convert.ToString(r.GetValueOrDefault("KIND")) == "EMANET_MAHSUP")
            .GroupBy(r => Convert.ToString(r.GetValueOrDefault("DEP_ACCOUNT_ID")) ?? "")
            .Count(g => g.Key.Length > 0 && g.Select(x => Convert.ToString(x.GetValueOrDefault("FATURAID"))).Distinct().Count() > 1);

        if (eksClose > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "EKSILTEN_CLOSE",
                Severity = "INFO",
                Side = "SMS",
                Message = $"{eksClose} fatura EKSILTEN (TAM) ile kapatılmış — IADE/CANCEL_PAY zinciri."
            });
        if (payCancel > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "PAY_CANCEL",
                Severity = "WARN",
                Side = "SMS",
                Message = $"{payCancel} tahsilat iptal (tip9/CANCELED) — emanet oluşumu adayı."
            });
        if (emanetGiris > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "EMANET_GIRIS",
                Severity = "INFO",
                Side = "SMS",
                Message = $"{emanetGiris} tip20 EMANET GİRİŞİ (güvence 162/1936 veya iptal bakiyesi) — ACCRUE14."
            });
        if (cancelEmanet > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "CANCEL_EMANET",
                Severity = "WARN",
                Side = "SMS",
                Message = $"{cancelEmanet} tip12 EMANET ÇIKIŞI — güvence/emanet → borç mahsup kaynağı."
            });
        if (emanetMahsup > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "EMANET_MAHSUP",
                Severity = "INFO",
                Side = "SMS",
                Message = $"{emanetMahsup} emanet→borç mahsup (REF_DEPOSIT); {multiDep} emanet birden fazla faturaya."
            });
        if (rows.Count == 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "IPTAL_EMANET_NONE",
                Severity = "INFO",
                Side = "SMS",
                Message = "Eksilten-kapama / tahsilat iptal / emanet mahsup yok."
            });

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, "iptalEmanet", "SMS", "READ", sw.ElapsedMilliseconds,
            rows.Count, "OK",
            $"source={source} eks_close={eksClose} pay_cancel={payCancel} emanet_giris={emanetGiris} cancel_emanet={cancelEmanet} emanet_mahsup={emanetMahsup}");
        return (rows, gaps, log);
    }

    /// <summary>tip6/24 + REF_DEPOSIT_ACCOUNT_ID → borç faturası (emanet/iptal bakiyesi mahsup).
    /// Dış sorguda <c>agr_inc</c> CTE (AGR gelir toplamı) tanımlı olmalı.</summary>
    private static string EmanetMahsupSelectSql(string sms) => $@"
SELECT CAST('EMANET_MAHSUP' AS VARCHAR2(20)) AS KIND,
       CAST(mah.ID AS NUMBER(12)) AS ACTION_ID,
       CAST(mah.ACCOUNT_ID AS NUMBER(12)) AS FATURAID,
       CAST(debt.AGREEMENT_ID AS NUMBER(12)) AS SOZLESME,
       CAST(NULL AS NUMBER(12)) AS MAIN_LREF,
       CAST(NULL AS NUMBER(12)) AS PAY_LREF,
       CAST(mah.REF_DEPOSIT_ACCOUNT_ID AS NUMBER(12)) AS DEP_ACCOUNT_ID,
       CAST(ROUND(ABS(NVL(amt.TUT, 0)), 2) AS NUMBER(15,3)) AS AMT,
       mah.ACTION_DATE AS ACTION_DATE,
       CAST(
         'emanet/dep ' || TO_CHAR(mah.REF_DEPOSIT_ACCOUNT_ID) ||
         CASE WHEN NVL(dep.ACCRUE_TYPE_ID, -1) = 14 THEN ' (ACCRUE14)' ELSE '' END ||
         ' → borç fatura ' || TO_CHAR(mah.ACCOUNT_ID) ||
         CASE WHEN mah.REF_DEPOSIT_ACCOUNT_ACTION_ID IS NOT NULL
              THEN ' via tip12=' || TO_CHAR(mah.REF_DEPOSIT_ACCOUNT_ACTION_ID)
              ELSE '' END
         AS VARCHAR2(100)
       ) AS NOTE
  FROM {sms}.CS_ACCOUNT_ACTION mah
  JOIN {sms}.CS_ACCOUNT debt ON debt.ID = mah.ACCOUNT_ID
  LEFT JOIN {sms}.CS_ACCOUNT dep ON dep.ID = mah.REF_DEPOSIT_ACCOUNT_ID
  LEFT JOIN agr_inc amt ON amt.ACCOUNT_ACTION_ID = mah.ID
 WHERE debt.AGREEMENT_ID = :agrId
   AND mah.ACTION_TYPE_ID IN (6, 24)
   AND mah.REF_DEPOSIT_ACCOUNT_ID IS NOT NULL
   AND ABS(NVL(amt.TUT, 0)) > 0.0001
";

    /// <summary>AGR hesaplarına kısıtlı income toplamı — full CS_ACCOUNT_INCOME GROUP BY yok.</summary>
    private static string AgrIncomeCte(string sms) => $@"
agr_acc AS (
  SELECT /*+ MATERIALIZE */ ID AS ACCOUNT_ID
    FROM {sms}.CS_ACCOUNT
   WHERE AGREEMENT_ID = :agrId
),
agr_inc AS (
  SELECT AI.ACCOUNT_ACTION_ID, SUM(AI.AMOUNT * AI.STATUS) TUT
    FROM agr_acc a
    JOIN {sms}.CS_ACCOUNT_ACTION aa ON aa.ACCOUNT_ID = a.ACCOUNT_ID
    JOIN {sms}.CS_ACCOUNT_INCOME AI ON AI.ACCOUNT_ACTION_ID = aa.ID
   GROUP BY AI.ACCOUNT_ACTION_ID
)";

    private static async Task<List<Dictionary<string, object?>>> QueryLiveIptalEmanetAsync(
        OracleConnection conn, string sms, long agrId, CancellationToken ct)
    {
        return await QueryAsync(conn, $@"
WITH {AgrIncomeCte(sms)},
tah AS (
  SELECT x.ACCOUNT_ID, SUM(ABS(i.AMOUNT)) AS TUT
    FROM agr_acc a
    JOIN {sms}.CS_ACCOUNT_ACTION x ON x.ACCOUNT_ID = a.ACCOUNT_ID
    JOIN {sms}.CS_ACCOUNT_INCOME i ON i.ACCOUNT_ACTION_ID = x.ID
   WHERE x.ACTION_TYPE_ID = 1
   GROUP BY x.ACCOUNT_ID
),
eks_tam AS (
  SELECT e.ID AS ACTION_ID, e.ACCOUNT_ID, e.ACTION_DATE,
         CAST(ROUND(SUM(ABS(ai.AMOUNT)), 2) AS NUMBER(15,3)) AS EKS_AMT
    FROM agr_acc a
    JOIN {sms}.CS_ACCOUNT_ACTION e ON e.ACCOUNT_ID = a.ACCOUNT_ID
    JOIN {sms}.CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = e.ID
    LEFT JOIN tah t ON t.ACCOUNT_ID = e.ACCOUNT_ID
   WHERE e.ACTION_TYPE_ID = 2
     AND EXISTS (
           SELECT 1 FROM {sms}.CS_ACCOUNT acc
            WHERE acc.ID = e.ACCOUNT_ID AND NVL(acc.ACCRUE_TYPE_ID, -1) <> 14
         )
   GROUP BY e.ID, e.ACCOUNT_ID, e.ACTION_DATE
  HAVING SUM(ABS(ai.AMOUNT)) >= NVL(MAX(t.TUT), 0) * 0.995
),
pay_cancel AS (
  SELECT can.ID AS CANCEL_ID, can.ACCOUNT_ID, can.ACTION_DATE,
         pay.ID AS PAY_LREF,
         CAST(ROUND(ABS(SUM(pi.AMOUNT * pi.STATUS)), 2) AS NUMBER(15,3)) AS PAY_AMT,
         acc.ACCRUE_TYPE_ID
    FROM agr_acc a
    JOIN {sms}.CS_ACCOUNT_ACTION can ON can.ACCOUNT_ID = a.ACCOUNT_ID
    JOIN {sms}.CS_ACCOUNT acc ON acc.ID = can.ACCOUNT_ID
    JOIN {sms}.CS_ACCOUNT_ACTION pay
      ON pay.ACCOUNT_ID = can.ACCOUNT_ID
     AND pay.ACTION_TYPE_ID <> 9
     AND EXISTS (
           SELECT 1 FROM {sms}.CS_ACTION_TYPE_PRM atp
            WHERE atp.ID = pay.ACTION_TYPE_ID AND atp.TYPE = 2
         )
     AND can.CASH_ID = pay.CASH_ID
     AND can.RECEIPT_NUMBER = pay.RECEIPT_NUMBER
     AND NVL(can.BANK_PAYMENT_DATE, DATE '1900-01-01')
       = NVL(pay.BANK_PAYMENT_DATE, DATE '1900-01-01')
    JOIN {sms}.CS_ACCOUNT_INCOME pi ON pi.ACCOUNT_ACTION_ID = pay.ID
   WHERE can.ACTION_TYPE_ID = 9
   GROUP BY can.ID, can.ACCOUNT_ID, can.ACTION_DATE, pay.ID, acc.ACCRUE_TYPE_ID
)
SELECT CAST('EKSILTEN_CLOSE' AS VARCHAR2(20)) AS KIND,
       CAST(e.ACTION_ID AS NUMBER(12)) AS ACTION_ID,
       CAST(e.ACCOUNT_ID AS NUMBER(12)) AS FATURAID,
       CAST(:agrId AS NUMBER(12)) AS SOZLESME,
       CAST(NULL AS NUMBER(12)) AS MAIN_LREF,
       CAST(NULL AS NUMBER(12)) AS PAY_LREF,
       CAST(NULL AS NUMBER(12)) AS DEP_ACCOUNT_ID,
       e.EKS_AMT AS AMT,
       e.ACTION_DATE,
       CAST('tip2 TAM — fatura eksilten kapama' AS VARCHAR2(100)) AS NOTE
  FROM eks_tam e
UNION ALL
SELECT CAST('PAY_CANCEL' AS VARCHAR2(20)),
       CAST(p.CANCEL_ID AS NUMBER(12)),
       CAST(p.ACCOUNT_ID AS NUMBER(12)),
       CAST(:agrId AS NUMBER(12)),
       CAST(NULL AS NUMBER(12)),
       CAST(p.PAY_LREF AS NUMBER(12)),
       CAST(NULL AS NUMBER(12)),
       p.PAY_AMT,
       p.ACTION_DATE,
       CAST('tip9 ↔ makbuz — tahsilat iptal (emanet adayı)' AS VARCHAR2(100))
  FROM pay_cancel p
 WHERE NVL(p.ACCRUE_TYPE_ID, -1) <> 14
UNION ALL
SELECT CAST('CANCEL_EMANET' AS VARCHAR2(20)),
       CAST(p.CANCEL_ID AS NUMBER(12)),
       CAST(p.ACCOUNT_ID AS NUMBER(12)),
       CAST(:agrId AS NUMBER(12)),
       CAST(NULL AS NUMBER(12)),
       CAST(p.PAY_LREF AS NUMBER(12)),
       CAST(p.ACCOUNT_ID AS NUMBER(12)),
       p.PAY_AMT,
       p.ACTION_DATE,
       CAST('tip9 iptal + ACCRUE=14 emanet hesabı' AS VARCHAR2(100))
  FROM pay_cancel p
 WHERE p.ACCRUE_TYPE_ID = 14
UNION ALL
SELECT CAST('CANCEL_EMANET' AS VARCHAR2(20)),
       CAST(aa.ID AS NUMBER(12)),
       CAST(a.ACCOUNT_ID AS NUMBER(12)),
       CAST(:agrId AS NUMBER(12)),
       CAST(aa.REF_DEPOSIT_ACCOUNT_ID AS NUMBER(12)),
       CAST(NULL AS NUMBER(12)),
       CAST(a.ACCOUNT_ID AS NUMBER(12)),
       CAST(ROUND(ABS(NVL(amt.TUT, 0)), 2) AS NUMBER(15,3)),
       aa.ACTION_DATE,
       CAST(
         'tip12 EMANET ÇIKIŞI' ||
         CASE WHEN aa.REF_DEPOSIT_ACCOUNT_ID IS NOT NULL
              THEN ' → borç fatura ' || TO_CHAR(aa.REF_DEPOSIT_ACCOUNT_ID)
              ELSE '' END
         AS VARCHAR2(100)
       )
  FROM agr_acc a
  JOIN {sms}.CS_ACCOUNT_ACTION aa ON aa.ACCOUNT_ID = a.ACCOUNT_ID
  LEFT JOIN agr_inc amt ON amt.ACCOUNT_ACTION_ID = aa.ID
 WHERE aa.ACTION_TYPE_ID = 12
UNION ALL
SELECT CAST('EMANET_GIRIS' AS VARCHAR2(20)),
       CAST(aa.ID AS NUMBER(12)),
       CAST(a.ACCOUNT_ID AS NUMBER(12)),
       CAST(:agrId AS NUMBER(12)),
       CAST(NULL AS NUMBER(12)),
       CAST(NULL AS NUMBER(12)),
       CAST(NVL(aa.REF_DEPOSIT_ACCOUNT_ID, a.ACCOUNT_ID) AS NUMBER(12)),
       CAST(ROUND(ABS(NVL(amt.TUT, 0)), 2) AS NUMBER(15,3)),
       aa.ACTION_DATE,
       CAST('tip20 EMANET GİRİŞİ — güvence (162/1936) / iptal bakiyesi' AS VARCHAR2(100))
  FROM agr_acc a
  JOIN {sms}.CS_ACCOUNT_ACTION aa ON aa.ACCOUNT_ID = a.ACCOUNT_ID
  JOIN {sms}.CS_ACCOUNT acc ON acc.ID = a.ACCOUNT_ID
  LEFT JOIN agr_inc amt ON amt.ACCOUNT_ACTION_ID = aa.ID
 WHERE aa.ACTION_TYPE_ID = 20
   AND NVL(acc.ACCRUE_TYPE_ID, -1) = 14
UNION ALL
{EmanetMahsupSelectSql(sms)}
ORDER BY 1, 2
FETCH FIRST 500 ROWS ONLY", agrId, ct);
    }

    /// <summary>
    /// Okuma bilgisi: yalnızca tüketim tahakkukları (ACCRUE_TYPE_ID IN 1,2,9,26,329).
    /// CS_READING.ACCOUNT_ID eşleşmesi varsa OK; yoksa OLUSTURULACAK.
    /// </summary>
    public async Task<(List<Dictionary<string, object?>> Rows, List<TahsilatGapItem> Gaps, TahsilatLogEvent Log)>
        LoadReadingStatusAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var sms = Sanitize(req.SmsSchema);

        // Tüketim tahakkuk tipleri — okuma kontrolü sadece bunlar için
        const string ConsumptionAccrueFilter = "ACC.ACCRUE_TYPE_ID IN (1, 2, 9, 26, 329)";

        await using var conn = new OracleConnection(req.OracleConnectionString);
        await conn.OpenAsync(ct);

        if (!await TableExistsAsync(conn, sms, "CS_READING", ct))
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_CS_READING",
                Severity = "CRITICAL",
                Side = "SMS",
                Message = $"{sms}.CS_READING tablosu yok."
            });
            sw.Stop();
            return ([], gaps, MakeLog(runId, req.AgreementId, "okumaBilgisi", "SMS", "READ",
                sw.ElapsedMilliseconds, 0, "FAIL", "CS_READING missing"));
        }

        if (!await ColumnExistsAsync(conn, sms, "CS_READING", "ACCOUNT_ID", ct))
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "NO_CS_READING_ACCOUNT_ID",
                Severity = "CRITICAL",
                Side = "SMS",
                Message = "CS_READING.ACCOUNT_ID kolonu yok — okuma-hesap eşlemesi yapılamaz."
            });
            sw.Stop();
            return ([], gaps, MakeLog(runId, req.AgreementId, "okumaBilgisi", "SMS", "READ",
                sw.ElapsedMilliseconds, 0, "FAIL", "ACCOUNT_ID column missing"));
        }

        var hasStatus = await ColumnExistsAsync(conn, sms, "CS_READING", "STATUS", ct);
        var statusExpr = hasStatus ? "R.STATUS" : "CAST(NULL AS NUMBER)";

        // Sadece tüketim tahakkukları (1,2,9,26,329)
        var rows = await QueryAsync(conn, $@"
SELECT
  ACC.ID AS ACCOUNT_ID,
  ACC.AGREEMENT_ID AS SOZLESME,
  ACC.ACCRUE_TYPE_ID,
  RD.READING_ID,
  RD.READING_STATUS,
  RD.READING_CNT,
  CASE WHEN NVL(RD.READING_CNT, 0) > 0 THEN 'OK' ELSE 'OLUSTURULACAK' END AS OKUMA_DURUMU
FROM {sms}.CS_ACCOUNT ACC
LEFT JOIN (
  SELECT R.ACCOUNT_ID,
         MAX(R.ID) AS READING_ID,
         MAX({statusExpr}) AS READING_STATUS,
         COUNT(*) AS READING_CNT
    FROM {sms}.CS_READING R
   WHERE R.ACCOUNT_ID IS NOT NULL
   GROUP BY R.ACCOUNT_ID
) RD ON RD.ACCOUNT_ID = ACC.ID
WHERE ACC.AGREEMENT_ID = :agrId
  AND {ConsumptionAccrueFilter}
ORDER BY CASE WHEN NVL(RD.READING_CNT, 0) > 0 THEN 1 ELSE 0 END, ACC.ID
FETCH FIRST 500 ROWS ONLY", req.AgreementId, ct);

        var okCnt = rows.Count(r => Convert.ToString(r.GetValueOrDefault("OKUMA_DURUMU")) == "OK");
        var createCnt = rows.Count(r => Convert.ToString(r.GetValueOrDefault("OKUMA_DURUMU")) == "OLUSTURULACAK");

        if (createCnt > 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "READING_CREATE_NEEDED",
                Severity = "WARN",
                Side = "SMS",
                Message = $"{createCnt} tüketim tahakkukunda (ACCRUE 1/2/9/26/329) CS_READING yok → OLUSTURULACAK. {okCnt} OK."
            });
        else if (rows.Count == 0)
            gaps.Add(new TahsilatGapItem
            {
                Code = "READING_NO_CONSUMPTION_ACCOUNTS",
                Severity = "INFO",
                Side = "SMS",
                Message = "Sözleşmede tüketim tahakkuku (ACCRUE_TYPE_ID 1,2,9,26,329) yok — okuma kontrolü kapsam dışı."
            });
        else
            gaps.Add(new TahsilatGapItem
            {
                Code = "READING_ALL_OK",
                Severity = "INFO",
                Side = "SMS",
                Message = $"Tüm {okCnt} tüketim tahakkukunda okuma kaydı var (ACCOUNT_ID eşleşti)."
            });

        sw.Stop();
        var log = MakeLog(runId, req.AgreementId, "okumaBilgisi", "SMS", "READ", sw.ElapsedMilliseconds,
            rows.Count, "OK",
            $"tuketimAccrue=1,2,9,26,329 accounts={rows.Count} ok={okCnt} create={createCnt}");
        return (rows, gaps, log);
    }

    private static string? FirstCol(HashSet<string> cols, params string[] names)
    {
        foreach (var n in names)
            if (cols.Contains(n)) return n;
        return null;
    }

    private static async Task<HashSet<string>> GetColumnsAsync(
        OracleConnection conn, string owner, string table, CancellationToken ct)
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        await using var cmd = new OracleCommand(
            "SELECT COLUMN_NAME FROM ALL_TAB_COLUMNS WHERE OWNER=:o AND TABLE_NAME=:t", conn);
        cmd.Parameters.Add("o", OracleDbType.Varchar2).Value = owner;
        cmd.Parameters.Add("t", OracleDbType.Varchar2).Value = table;
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
            set.Add(r.GetString(0));
        return set;
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

    private static string Sanitize(string id)
    {
        if (string.IsNullOrWhiteSpace(id) || !id.All(c => char.IsLetterOrDigit(c) || c == '_'))
            throw new ArgumentException($"Geçersiz identifier: {id}");
        return id.ToUpperInvariant();
    }

    private static async Task<bool> TableExistsAsync(OracleConnection conn, string owner, string table, CancellationToken ct)
    {
        await using var cmd = new OracleCommand(
            "SELECT COUNT(*) FROM ALL_TABLES WHERE OWNER=:o AND TABLE_NAME=:t", conn);
        cmd.Parameters.Add("o", OracleDbType.Varchar2).Value = owner;
        cmd.Parameters.Add("t", OracleDbType.Varchar2).Value = table;
        var n = Convert.ToInt32(await cmd.ExecuteScalarAsync(ct));
        return n > 0;
    }

    private static async Task<bool> ColumnExistsAsync(
        OracleConnection conn, string owner, string table, string column, CancellationToken ct)
    {
        await using var cmd = new OracleCommand(
            "SELECT COUNT(*) FROM ALL_TAB_COLUMNS WHERE OWNER=:o AND TABLE_NAME=:t AND COLUMN_NAME=:c", conn);
        cmd.Parameters.Add("o", OracleDbType.Varchar2).Value = owner;
        cmd.Parameters.Add("t", OracleDbType.Varchar2).Value = table;
        cmd.Parameters.Add("c", OracleDbType.Varchar2).Value = column;
        var n = Convert.ToInt32(await cmd.ExecuteScalarAsync(ct));
        return n > 0;
    }

    private static async Task<Dictionary<string, object?>?> QueryOneAsync(
        OracleConnection conn, string sql, long agrId, CancellationToken ct)
    {
        var rows = await QueryAsync(conn, sql, agrId, ct);
        return rows.FirstOrDefault();
    }

    private static async Task<List<Dictionary<string, object?>>> QueryAsync(
        OracleConnection conn, string sql, long agrId, CancellationToken ct)
    {
        // Oracle 11.2: FETCH FIRST ... ROWS ONLY yok → ROWNUM sarmala
        sql = RewriteFetchFirstForOracle11(sql);
        await using var cmd = new OracleCommand(sql, conn) { BindByName = true };
        cmd.Parameters.Add("agrId", OracleDbType.Int64).Value = agrId;
        var list = new List<Dictionary<string, object?>>();
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
            list.Add(ReadRow(reader));
        return list;
    }

    /// <summary>11g uyumu: ... FETCH FIRST n ROWS ONLY → SELECT * FROM (...) WHERE ROWNUM &lt;= n</summary>
    private static string RewriteFetchFirstForOracle11(string sql)
    {
        var m = System.Text.RegularExpressions.Regex.Match(
            sql,
            @"\s+FETCH\s+FIRST\s+(\d+)\s+ROWS\s+ONLY\s*;?\s*$",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.Singleline);
        if (!m.Success) return sql;
        var n = m.Groups[1].Value;
        var inner = sql[..m.Index].TrimEnd();
        return $"SELECT * FROM (\n{inner}\n) Q__LIM WHERE ROWNUM <= {n}";
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

    private static long ToLong(Dictionary<string, object?>? row, string key)
    {
        if (row == null || !row.TryGetValue(key, out var v) || v == null) return 0;
        return Convert.ToInt64(v);
    }
}
