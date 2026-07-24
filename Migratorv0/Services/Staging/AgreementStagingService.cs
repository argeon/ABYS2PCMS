using System.Data;
using MigrationWeb.Models.Staging;
using Oracle.ManagedDataAccess.Client;

namespace MigrationWeb.Services.Staging;

public sealed class AgreementStagingService
{
    private readonly ILogger<AgreementStagingService> _logger;

    public AgreementStagingService(ILogger<AgreementStagingService> logger) => _logger = logger;

    public async Task<(bool Ok, string Message)> TestConnectionAsync(string connectionString, CancellationToken ct = default)
    {
        try
        {
            await using var conn = new OracleConnection(connectionString);
            await conn.OpenAsync(ct);
            await using var cmd = new OracleCommand("SELECT 1 FROM DUAL", conn);
            await cmd.ExecuteScalarAsync(ct);
            return (true, "Bağlantı başarılı.");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Oracle staging connection test failed");
            return (false, ex.Message);
        }
    }

    public async Task<AgreementStagingPayload> LoadAsync(AgreementStagingLoadRequest request, CancellationToken ct = default)
    {
        var schema = SanitizeIdentifier(request.StagingSchema);
        var agrId = request.AgreementId;
        var payload = new AgreementStagingPayload();

        await using var conn = new OracleConnection(request.OracleConnectionString);
        await conn.OpenAsync(ct);

        if (!await TableExistsAsync(conn, schema, "STG_INVOICE", ct))
        {
            payload.Warnings.Add($"{schema}.STG_INVOICE bulunamadı. Önce pilot CTAS scriptini çalıştırın.");
            return payload;
        }

        payload.Invoices = await LoadInvoicesAsync(conn, schema, agrId, ct);

        payload.InvLines = await LoadInvLinesAsync(conn, schema, agrId, ct);

        payload.PayTrans = await QueryAsync(conn, $@"
SELECT P.LREF, P.INVOICEREF, P.PT_KIND, P.PT_TYPE, P.IOCODE,
       P.CROSSREF, P.PAYTYPE, P.INST_NR,
       TO_CHAR(P.DATE_,'YYYY-MM-DD') DATE_,
       P.PAYABLETOTAL, P.PAID, P.CANCELED,
       P.SOURCE_ORACLE_ACCOUNT_ID, P.SOURCE_ORACLE_ACTION_ID, P.SRC_ACTION_TYPE,
       V.INV_KIND, V.GRANDTOTAL INV_GRANDTOTAL
  FROM {schema}.STG_PAYTRANS P
  LEFT JOIN {schema}.STG_INVOICE V ON V.LREF = P.INVOICEREF
 WHERE P.SOURCE_ORACLE_ACCOUNT_ID IN (SELECT ID FROM {schema}.STG_PILOT_ACC WHERE AGREEMENT_ID = :agrId)
    OR V.SRC_AGREEMENT_ID = :agrId
 ORDER BY P.DATE_, P.LREF", agrId, ct);

        payload.PayTransIncome = await QueryAsync(conn, $@"
SELECT PI.LREF, PI.PAYTRANSREF, PI.LINENR, PI.DEBT_INVOICEREF, PI.DEBT_PAYTRANSREF,
       PI.INCOME_AMOUNT, PI.SRC_INCOME_ID, PI.SOURCE_ORACLE_INCOME_ID,
       PI.SOURCE_ORACLE_ACTION_ID, PI.SOURCE_ORACLE_ACCOUNT_ID,
       P.PT_KIND, P.CROSSREF
  FROM {schema}.STG_PAYTRANS_INCOME PI
  JOIN {schema}.STG_PAYTRANS P ON P.LREF = PI.PAYTRANSREF
 WHERE PI.SOURCE_ORACLE_ACCOUNT_ID IN (SELECT ID FROM {schema}.STG_PILOT_ACC WHERE AGREEMENT_ID = :agrId)
 ORDER BY PI.PAYTRANSREF, PI.LINENR", agrId, ct);

        if (await TableExistsAsync(conn, schema, "STG_SPEFEE", ct))
        {
            var hasInvLineRef = await ColumnExistsAsync(conn, schema, "STG_SPEFEE", "INVLINEREF", ct);
            payload.SpeFee = await QueryAsync(conn, $@"
SELECT SP.LREF, SP.INVOICEREF, {(hasInvLineRef ? "SP.INVLINEREF" : "CAST(NULL AS NUMBER(12))")} INVLINEREF,
       SP.LINEEXP, SP.SRC_INCOME_ID, SP.GRANDTOTAL,
       SP.STATUS, SP.SOURCE_ORACLE_ACCOUNT_ID, SP.SOURCE_ORACLE_ACTION_ID,
       SP.SOURCE_ORACLE_INCOME_ID
  FROM {schema}.STG_SPEFEE SP
 WHERE SP.CLIENTREF = :agrId
 ORDER BY SP.SOURCE_ORACLE_ACTION_ID, SP.SRC_INCOME_ID", agrId, ct);
        }

        if (await TableExistsAsync(conn, schema, "STG_ADVANCE_LEDGER", ct))
        {
            payload.AdvanceLedger = await QueryAsync(conn, $@"
SELECT L.LREF, L.SRC_REGISTER_ID, L.SRC_AGREEMENT_ID, L.SRC_ACCRUE_TYPE, L.DIRECTION,
       L.AMOUNT, L.STATUS_NET, TO_CHAR(L.TRANS_DATE,'YYYY-MM-DD') TRANS_DATE,
       L.SOURCE_ACTION_TYPE, L.CAUSE_CODE, L.REF_ACC_ID, L.REF_ACT_ID,
       L.SOURCE_ORACLE_ACCOUNT_ID, L.SOURCE_ORACLE_ACTION_ID, L.PARENT_LREF, L.CANCELED
  FROM {schema}.STG_ADVANCE_LEDGER L
 WHERE L.SRC_AGREEMENT_ID = :agrId
 ORDER BY L.TRANS_DATE, L.LREF", agrId, ct);

            if (await TableExistsAsync(conn, schema, "STG_ADV_LEDGER_INCOME", ct))
            {
                payload.AdvanceLedgerIncome = await QueryAsync(conn, $@"
SELECT LI.LREF, LI.LEDGER_LREF, LI.DIRECTION, LI.SRC_INCOME_ID, LI.AMOUNT,
       LI.SOURCE_ORACLE_ACCOUNT_ID, LI.SOURCE_ORACLE_ACTION_ID, LI.SOURCE_ORACLE_INCOME_ID
  FROM {schema}.STG_ADV_LEDGER_INCOME LI
  JOIN {schema}.STG_ADVANCE_LEDGER L ON L.LREF = LI.LEDGER_LREF
 WHERE L.SRC_AGREEMENT_ID = :agrId
 ORDER BY LI.LEDGER_LREF, LI.LREF", agrId, ct);
            }
        }

        payload.InstallmentPlan = await LoadInstallmentPlanAsync(conn, agrId, schema, ct);

        if (await TableExistsAsync(conn, schema, "STG_MAHSUP_POOL", ct))
        {
            payload.MahsupPool = await QueryAsync(conn, $@"
SELECT AGREEMENT_ID, SOURCE_ORACLE_ACCOUNT_ID, SOURCE_ORACLE_ACTION_ID,
       TARGET_ACCOUNT_ID, TARGET_DEBT_ACTION_ID, TARGET_DEBT_PT,
       MAHSUP_TUTAR, PAY_APPLIED, DURUM
  FROM {schema}.STG_MAHSUP_POOL
 WHERE AGREEMENT_ID = :agrId
 ORDER BY SOURCE_ORACLE_ACTION_ID, TARGET_DEBT_PT", agrId, ct);
        }

        if (await TableExistsAsync(conn, schema, "STG_RECON_DIFF", ct))
        {
            payload.ReconDiff = await QueryAsync(conn, $@"
SELECT SEVERITY, KATEGORI, AGREEMENT_ID,
       SOURCE_ORACLE_ACCOUNT_ID ACCOUNT_ID,
       KAYNAK_NET, STAGING_NET, FARK, SUSPECT_ACTION_IDS, SEBEP
  FROM {schema}.STG_RECON_DIFF
 WHERE AGREEMENT_ID = :agrId AND NVL(IGNORED,0) = 0
 ORDER BY DECODE(SEVERITY,'CRITICAL',1,'WARN',2,'INFO',3), KATEGORI", agrId, ct);
        }

        var accRows = await QueryAsync(conn, $@"
SELECT COUNT(*) CNT FROM {schema}.STG_PILOT_ACC WHERE AGREEMENT_ID = :agrId", agrId, ct);

        payload.Summary = BuildSummary(payload, agrId, accRows.FirstOrDefault());
        payload.Summary.Abys = await LoadAbysSummaryAsync(conn, agrId, ct);
        return payload;
    }

    private async Task<AgreementAbysSummary?> LoadAbysSummaryAsync(
        OracleConnection conn, long agrId, CancellationToken ct)
    {
        try
        {
            await using var cmd = new OracleCommand(@"
SELECT
  (SELECT COUNT(DISTINCT X.ID) FROM SMS.CS_ACCOUNT A
      JOIN SMS.CS_ACCOUNT_ACTION X ON X.ACCOUNT_ID=A.ID
      JOIN SMS.CS_ACTION_TYPE_PRM T ON T.ID=X.ACTION_TYPE_ID
     WHERE A.AGREEMENT_ID=:agrId AND T.TYPE=1 AND T.STATUS=1)
  + (SELECT COUNT(*) FROM SMS.CS_ACCOUNT A
      WHERE A.AGREEMENT_ID=:agrId AND A.ACCRUE_TYPE_ID=26) FATURA_ADET,
  (SELECT COUNT(*) FROM SMS.CS_ACCOUNT A
     WHERE A.AGREEMENT_ID=:agrId AND A.ACCRUE_TYPE_ID IN (1,2,26)
       AND NVL(A.TOTAL_DEBT,0) <= NVL(A.TOTAL_CREDIT,0)+0.01
       AND EXISTS (SELECT 1 FROM SMS.CS_ACCOUNT_ACTION X
                    JOIN SMS.CS_ACTION_TYPE_PRM T ON T.ID=X.ACTION_TYPE_ID
                   WHERE X.ACCOUNT_ID=A.ID AND T.TYPE=1)) ODENMIS_FATURA,
  (SELECT COUNT(*) FROM SMS.CS_ACCOUNT A
     WHERE A.AGREEMENT_ID=:agrId AND A.ACCRUE_TYPE_ID IN (1,2)
       AND NVL(A.TOTAL_DEBT,0) > NVL(A.TOTAL_CREDIT,0)+0.01) GECIKMIS_BORC,
  (SELECT SUM(GREATEST(NVL(A.TOTAL_DEBT,0)-NVL(A.TOTAL_CREDIT,0),0))
     FROM SMS.CS_ACCOUNT A
    WHERE A.AGREEMENT_ID=:agrId AND A.ACCRUE_TYPE_ID=2)
  + (SELECT SUM(GREATEST(NVL(A.TOTAL_DEBT,0)-NVL(A.TOTAL_CREDIT,0),0))
       FROM SMS.CS_ACCOUNT A
      WHERE A.AGREEMENT_ID=:agrId AND A.ACCRUE_TYPE_ID=1
        AND A.TOTAL_DEBT>NVL(A.TOTAL_CREDIT,0)+0.01) TOPLAM_BORC,
  (SELECT NVL(SUM(GREATEST(NVL(A.TOTAL_DEBT,0)-NVL(A.TOTAL_CREDIT,0),0)),0)
     FROM SMS.CS_ACCOUNT A WHERE A.AGREEMENT_ID=:agrId AND A.ACCRUE_TYPE_ID=5) DEPOZITO,
  (SELECT NVL(SUM(I.AMOUNT*T.STATUS),0) FROM SMS.CS_ACCOUNT A
      JOIN SMS.CS_ACCOUNT_ACTION X ON X.ACCOUNT_ID=A.ID
      JOIN SMS.CS_ACCOUNT_INCOME I ON I.ACCOUNT_ACTION_ID=X.ID
      JOIN SMS.CS_ACTION_TYPE_PRM T ON T.ID=X.ACTION_TYPE_ID
     WHERE A.AGREEMENT_ID=:agrId AND A.ACCRUE_TYPE_ID=14) EMANET
FROM DUAL", conn) { BindByName = true };
            cmd.Parameters.Add("agrId", OracleDbType.Int64).Value = agrId;
            await using var r = await cmd.ExecuteReaderAsync(ct);
            if (!await r.ReadAsync(ct)) return null;
            return new AgreementAbysSummary
            {
                FaturaAdet = Convert.ToInt32(r.GetValue(0)),
                OdenmisFaturaAdet = Convert.ToInt32(r.GetValue(1)),
                GecikmisBorcAdet = Convert.ToInt32(r.GetValue(2)),
                ToplamBorc = r.IsDBNull(3) ? 0 : Convert.ToDecimal(r.GetValue(3)),
                DepozitoTutar = r.IsDBNull(4) ? 0 : Convert.ToDecimal(r.GetValue(4)),
                EmanetTutar = r.IsDBNull(5) ? 0 : Convert.ToDecimal(r.GetValue(5))
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "ABYS summary query failed for agreement {AgrId}", agrId);
            return null;
        }
    }

    private static AgreementStagingSummary BuildSummary(
        AgreementStagingPayload p, long agrId, Dictionary<string, object?>? accRow)
    {
        static decimal Dec(object? v) => v switch
        {
            null => 0,
            decimal d => d,
            double dbl => (decimal)dbl,
            float f => (decimal)f,
            int i => i,
            long l => l,
            _ => decimal.TryParse(v.ToString(), out var x) ? x : 0
        };

        static int Int(object? v) => v switch
        {
            null => 0,
            int i => i,
            long l => (int)l,
            decimal d => (int)d,
            _ => int.TryParse(v.ToString(), out var x) ? x : 0
        };

        var accrue = p.PayTrans.Where(r => string.Equals(Str(r, "PT_KIND"), "ACCRUE", StringComparison.OrdinalIgnoreCase)).ToList();
        var payments = p.PayTrans.Where(r => string.Equals(Str(r, "PT_KIND"), "PAYMENT", StringComparison.OrdinalIgnoreCase)).ToList();
        var tahakkuk = p.Invoices.Where(r => Str(r, "INV_KIND") is "MAIN" or "GECIKME" or "ARTTIRAN").ToList();
        var openDebts = accrue
            .Select(r => Dec(r.GetValueOrDefault("PAYABLETOTAL")) - Dec(r.GetValueOrDefault("PAID")))
            .Where(b => b > 0.01m)
            .ToList();

        return new AgreementStagingSummary
        {
            AgreementId = agrId,
            AccountCount = accRow != null ? Int(accRow.Values.First()) : 0,
            InvoiceCount = p.Invoices.Count,
            InvLinesCount = p.InvLines.Count,
            PayTransCount = p.PayTrans.Count,
            PayTransIncomeCount = p.PayTransIncome.Count,
            SpeFeeCount = p.SpeFee.Count,
            AdvanceLedgerCount = p.AdvanceLedger.Count,
            InstallmentPlanCount = p.InstallmentPlan.Count,
            ReconCount = p.ReconDiff.Count,
            InvoiceGrandTotal = tahakkuk.Sum(r => Dec(r.GetValueOrDefault("GRANDTOTAL"))),
            AccruePayableTotal = accrue.Sum(r => Dec(r.GetValueOrDefault("PAYABLETOTAL"))),
            AccruePaidTotal = accrue.Sum(r => Dec(r.GetValueOrDefault("PAID"))),
            PaymentTotal = payments.Sum(r => Dec(r.GetValueOrDefault("PAYABLETOTAL"))),
            SpeFeeTotal = p.SpeFee.Sum(r => Dec(r.GetValueOrDefault("GRANDTOTAL"))),
            LedgerAmountTotal = p.AdvanceLedger.Sum(r => Dec(r.GetValueOrDefault("AMOUNT"))),
            LedgerCreditNet = p.AdvanceLedger.Sum(r => Dec(r.GetValueOrDefault("STATUS_NET"))),
            TahakkukCount = tahakkuk.Count,
            PaidTahakkukCount = tahakkuk.Count(r => Int(r.GetValueOrDefault("CLOSED")) == 1),
            OpenDebtCount = openDebts.Count,
            TotalDebtBalance = openDebts.Sum(),
            HasInvoiceDebt = openDebts.Count > 0
        };
    }

    private static string? Str(Dictionary<string, object?> row, string key) =>
        row.TryGetValue(key, out var v) ? v?.ToString() : null;

    private async Task<List<Dictionary<string, object?>>> LoadInvoicesAsync(
        OracleConnection conn, string schema, long agrId, CancellationToken ct)
    {
        var hasExplain = await ColumnExistsAsync(conn, schema, "STG_INVOICE", "EXPLAIN", ct);
        var hasFitno = await ColumnExistsAsync(conn, schema, "STG_INVOICE", "FITNO", ct);
        var hasClientRef = await ColumnExistsAsync(conn, schema, "STG_INVOICE", "CLIENTREF", ct);
        var hasOwnerRef = await ColumnExistsAsync(conn, schema, "STG_INVOICE", "OWNERREF", ct);
        var hasOwnerType = await ColumnExistsAsync(conn, schema, "STG_INVOICE", "OWNERTYPE", ct);

        var sql = $@"
SELECT V.LREF, V.INV_KIND, V.SOURCE_ORACLE_ACCOUNT_ID, V.SOURCE_ORACLE_ACTION_ID,
       V.SRC_AGREEMENT_ID, V.SRC_ACCRUE_TYPE,
       TO_CHAR(V.DATE_,'YYYY-MM-DD') DATE_,
       V.TLTOTAL, V.TAX, V.GRANDTOTAL, V.PAYABLETOTAL, V.INV_TYPE, V.IOCODE, V.CANCELED, V.CLOSED,
       V.INVOICECROSSREF, V.RETURN_SOURCE_INVREF, V.RETURN_TARGET_INVREF, V.LAWDETAILREF,
       {(hasFitno ? "V.FITNO" : "CAST(NULL AS NUMBER(12))")} FITNO,
       {(hasClientRef ? "V.CLIENTREF" : "CAST(NULL AS NUMBER(12))")} CLIENTREF,
       {(hasOwnerRef ? "V.OWNERREF" : "CAST(NULL AS NUMBER(12))")} OWNERREF,
       {(hasOwnerType ? "V.OWNERTYPE" : "CAST(NULL AS NUMBER(6))")} OWNERTYPE,
       {(hasExplain ? "V.EXPLAIN" : "CAST(NULL AS VARCHAR2(200))")} EXPLAIN,
       NVL(ATL.VALUE, 'Tahakkuk '||V.SRC_ACCRUE_TYPE) ACCRUE_TYPE_NAME
  FROM {schema}.STG_INVOICE V
  LEFT JOIN SMS.CS_ACCRUE_TYPE_PRM_LNG ATL ON ATL.PRM_ID = V.SRC_ACCRUE_TYPE AND ATL.LANG_ID = 1
 WHERE V.SRC_AGREEMENT_ID = :agrId
 ORDER BY V.DATE_, V.LREF";

        return await QueryAsync(conn, sql, agrId, ct);
    }

    private async Task<List<Dictionary<string, object?>>> LoadInvLinesAsync(
        OracleConnection conn, string schema, long agrId, CancellationToken ct)
    {
        var hasIsDiscount = await ColumnExistsAsync(conn, schema, "STG_INVLINES", "IS_DISCOUNT", ct);
        var hasCanceled = await ColumnExistsAsync(conn, schema, "STG_INVLINES", "CANCELED", ct);
        var hasLineExp = await ColumnExistsAsync(conn, schema, "STG_INVLINES", "LINEEXP", ct);

        var isDiscountCol = hasIsDiscount
            ? "IL.IS_DISCOUNT"
            : "NVL((SELECT NVL(CI.IS_DISCOUNT,0) FROM SMS.CS_ACCOUNT_INCOME CI WHERE CI.ID = IL.SOURCE_ORACLE_INCOME_ID AND ROWNUM = 1),0)";
        var canceledCol = hasCanceled ? "IL.CANCELED" : "0";
        var lineExpCol = hasLineExp ? "IL.LINEEXP" : "CAST(NULL AS VARCHAR2(200))";
        var gelirAdi = hasLineExp
            ? "NVL(IPL.VALUE, NVL(IL.LINEEXP, 'Gelir '||IL.TRANSTYPE))"
            : "NVL(IPL.VALUE, 'Gelir '||IL.TRANSTYPE)";

        var sql = $@"
SELECT IL.LREF, IL.INVOICEREF, IL.LINE_TYPE, IL.TRANSTYPE, IL.AMOUNT,
       IL.SRC_INCOME_ID, IL.SOURCE_ORACLE_INCOME_ID, IL.SOURCE_ORACLE_ACTION_ID,
       IL.SOURCE_ORACLE_ACCOUNT_ID, V.INV_KIND,
       {isDiscountCol} IS_DISCOUNT, {canceledCol} CANCELED, {lineExpCol} LINEEXP,
       NVL(IP.CODE, TO_CHAR(IL.TRANSTYPE)) GELIR_KODU,
       {gelirAdi} GELIR_ADI
  FROM {schema}.STG_INVLINES IL
  JOIN {schema}.STG_INVOICE V ON V.LREF = IL.INVOICEREF
  LEFT JOIN SMS.CS_INCOME_PRM IP ON IP.ID = CASE WHEN IL.SRC_INCOME_ID <> -1 THEN IL.SRC_INCOME_ID ELSE IL.TRANSTYPE END
  LEFT JOIN SMS.CS_INCOME_PRM_LNG IPL ON IPL.PRM_ID = IP.ID AND IPL.LANG_ID = 1
 WHERE V.SRC_AGREEMENT_ID = :agrId AND IL.SRC_INCOME_ID <> -1
 ORDER BY IL.INVOICEREF, IL.LREF";

        return await QueryAsync(conn, sql, agrId, ct);
    }

    private async Task<List<Dictionary<string, object?>>> LoadInstallmentPlanAsync(
        OracleConnection conn, long agrId, string schema, CancellationToken ct)
    {
        if (await TableExistsAsync(conn, schema, "STG_INSTALLMENT_PLAN", ct))
        {
            var stg = await QueryAsync(conn, $@"
SELECT INS.ID INSTALLMENT_ID, INS.AGREEMENT_ID, INS.INSTALLMENT_NUMBER, INS.TOTAL_AMOUNT,
       INS.MONTHLY_AMOUNT, TO_CHAR(INS.INSTALLMENT_DATE,'YYYY-MM-DD') INSTALLMENT_DATE,
       IP.ID PLAN_ROW_ID, IP.INST_NR, IP.AMOUNT, IP.LATE_CHARGE, IP.OVERDUE,
       TO_CHAR(IP.DUE_DATE,'YYYY-MM-DD') DUE_DATE, TO_CHAR(IP.EXPIRY_DATE,'YYYY-MM-DD') EXPIRY_DATE,
       TO_CHAR(IP.PAYMENT_DATE,'YYYY-MM-DD') PAYMENT_DATE,
       IP.PAYMENT_ACTION_ID, IP.RECEIPT_SERIAL, IP.RECEIPT_NUMBER, IP.POOL_ID
  FROM {schema}.STG_INSTALLMENT INS
  JOIN {schema}.STG_INSTALLMENT_PLAN IP ON IP.INSTALLMENT_ID = INS.ID
 WHERE INS.AGREEMENT_ID = :agrId
 ORDER BY INS.ID, IP.INST_NR", agrId, ct);
            if (stg.Count > 0)
                return stg;
        }

        if (!await TableExistsAsync(conn, "SMS", "CS_INSTALLMENT", ct))
            return [];

        try
        {
            return await QueryAsync(conn, @"
SELECT INS.ID INSTALLMENT_ID, INS.AGREEMENT_ID, INS.INSTALLMENT_NUMBER, INS.TOTAL_AMOUNT,
       INS.MONTHLY_AMOUNT, TO_CHAR(INS.INSTALLMENT_DATE,'YYYY-MM-DD') INSTALLMENT_DATE,
       IP.ID PLAN_ROW_ID, IP.ORDER_NUMBER INST_NR, IP.AMOUNT, IP.LATE_CHARGE, IP.OVERDUE,
       TO_CHAR(IP.DUE_DATE,'YYYY-MM-DD') DUE_DATE,
       TO_CHAR(IP.EXPIRY_DATE,'YYYY-MM-DD') EXPIRY_DATE,
       TO_CHAR(IP.PAYMENT_DATE,'YYYY-MM-DD') PAYMENT_DATE,
       IP.CASH_ID PAYMENT_ACTION_ID, IP.RECEIPT_SERIAL, IP.RECEIPT_NUMBER, IP.POOL_ID
  FROM SMS.CS_INSTALLMENT INS
  JOIN SMS.CS_INSTALLMENT_PLAN IP ON IP.INSTALLMENT_ID = INS.ID
 WHERE INS.AGREEMENT_ID = :agrId
 ORDER BY INS.ID, IP.ORDER_NUMBER", agrId, ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Installment plan query failed for agreement {AgrId}", agrId);
            return [];
        }
    }

    private static async Task<bool> ColumnExistsAsync(
        OracleConnection conn, string owner, string tableName, string columnName, CancellationToken ct)
    {
        await using var cmd = new OracleCommand(@"
SELECT COUNT(*) FROM ALL_TAB_COLUMNS
 WHERE OWNER = :owner AND TABLE_NAME = :tbl AND COLUMN_NAME = :col", conn);
        cmd.Parameters.Add("owner", OracleDbType.Varchar2).Value = owner.ToUpperInvariant();
        cmd.Parameters.Add("tbl", OracleDbType.Varchar2).Value = tableName.ToUpperInvariant();
        cmd.Parameters.Add("col", OracleDbType.Varchar2).Value = columnName.ToUpperInvariant();
        var n = Convert.ToInt32(await cmd.ExecuteScalarAsync(ct));
        return n > 0;
    }

    private static async Task<bool> TableExistsAsync(
        OracleConnection conn, string owner, string tableName, CancellationToken ct)
    {
        await using var cmd = new OracleCommand(@"
SELECT COUNT(*) FROM ALL_TABLES WHERE OWNER = :owner AND TABLE_NAME = :tbl", conn);
        cmd.Parameters.Add("owner", OracleDbType.Varchar2).Value = owner.ToUpperInvariant();
        cmd.Parameters.Add("tbl", OracleDbType.Varchar2).Value = tableName.ToUpperInvariant();
        var n = Convert.ToInt32(await cmd.ExecuteScalarAsync(ct));
        return n > 0;
    }

    private static async Task<List<Dictionary<string, object?>>> QueryAsync(
        OracleConnection conn, string sql, long agrId, CancellationToken ct)
    {
        var rows = new List<Dictionary<string, object?>>();
        await using var cmd = new OracleCommand(sql, conn) { BindByName = true };
        cmd.Parameters.Add("agrId", OracleDbType.Int64).Value = agrId;
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        var names = Enumerable.Range(0, reader.FieldCount).Select(reader.GetName).ToArray();

        while (await reader.ReadAsync(ct))
        {
            var row = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
            for (var i = 0; i < names.Length; i++)
                row[names[i]] = reader.IsDBNull(i) ? null : reader.GetValue(i);
            rows.Add(row);
        }
        return rows;
    }

    private static string SanitizeIdentifier(string value)
    {
        var v = (value ?? "SMS_AUDIT").Trim().ToUpperInvariant();
        if (!System.Text.RegularExpressions.Regex.IsMatch(v, @"^[A-Z][A-Z0-9_]*$"))
            throw new ArgumentException("Geçersiz staging şema adı.");
        return v;
    }
}
