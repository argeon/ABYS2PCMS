using System.Data;
using System.Diagnostics;
using MigrationWeb.Models.Staging;
using Microsoft.Data.SqlClient;
using Oracle.ManagedDataAccess.Client;

namespace MigrationWeb.Services.Staging;

/// <summary>
/// Tek AGR: Oracle CTAS (MIGRATION.LS_*) + SMS taksit → izgazMGR.dbo.*
/// ENERGY MSSQL bağlantısı aynı instance'ta izgazMGR görmeli (three-part name).
/// </summary>
public sealed class AgreementPilotMgrLoadService
{
    private readonly ILogger<AgreementPilotMgrLoadService> _logger;

    public AgreementPilotMgrLoadService(ILogger<AgreementPilotMgrLoadService> logger) => _logger = logger;

    public async Task<(
            Dictionary<string, object?> Summary,
            List<Dictionary<string, object?>> Preview,
            List<TahsilatGapItem> Gaps,
            TahsilatLogEvent Log)>
        DumpAgrToMgrAsync(AgreementTahsilatRequest req, string runId, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var gaps = new List<TahsilatGapItem>();
        var summary = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
        var preview = new List<Dictionary<string, object?>>();
        var agr = req.AgreementId;
        var op = req.DryRun ? "DRY_RUN" : "APPLY";

        summary["agreementId"] = agr;

        await using var ora = new OracleConnection(req.OracleConnectionString);
        await using var mssql = new SqlConnection(req.MssqlConnectionString);
        await ora.OpenAsync(ct);
        await mssql.OpenAsync(ct);

        var oracleUser = await GetOracleCurrentUserAsync(ora, ct);
        var (mig, sms, schemaNote) = await ResolveSchemasAsync(ora, req, oracleUser, ct);
        summary["oracleUser"] = oracleUser;
        summary["migrationSchema"] = mig;
        summary["smsSchema"] = sms;
        summary["schemaResolve"] = schemaNote;

        // Pilot: izgazMGR + LS_INVOICE/LS_INVLINES yoksa oluştur (prod'da CTAS sonrası zaten vardır)
        var schemaState = await EnsureIzgazMgrSchemaAsync(ora, mssql, mig, sms, apply: !req.DryRun, ct);
        summary["mgrSchema"] = schemaState;
        if (schemaState.StartsWith("FAIL:", StringComparison.OrdinalIgnoreCase))
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_MGR_SCHEMA_FAIL",
                Severity = req.DryRun ? "WARN" : "CRITICAL",
                Side = "ENERGY",
                Message = schemaState
            });
            if (!req.DryRun)
            {
                sw.Stop();
                return (summary, preview, gaps,
                    MakeLog(runId, agr, "pilotDumpMgr", "BOTH", op, sw.ElapsedMilliseconds, 0, "FAIL", schemaState));
            }
        }
        else if (!await MssqlObjectExistsAsync(mssql, "izgazMGR.dbo.LS_INVOICE", ct) && req.DryRun)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_MGR_WOULD_CREATE",
                Severity = "INFO",
                Side = "ENERGY",
                Message = "APPLY ile izgazMGR.dbo.LS_INVOICE (+ INVLINES/taksit) oluşturulacak, sonra CTAS satırları yüklenecek."
            });
        }

        // MIG_PARAM seed — bağlı Oracle kullanıcısı / ekran şeması
        var migParamState = await EnsureMigParamAsync(ora, mig, oracleUser, agr, apply: !req.DryRun, ct);
        summary["migParam"] = migParamState;

        var oraInv = await OracleCountAsync(ora, $"{mig}.LS_INVOICE", "ABYS_AGREEMENT_ID", agr, ct);
        var oraLines = await OracleCountAsync(ora, $"{mig}.LS_INVLINES", "ABYS_AGREEMENT_ID", agr, ct);
        var oraInstIds = await OracleInstallmentIdsForAgrAsync(ora, sms, agr, ct);
        var oraInst = oraInstIds.Count;
        var oraInstPlan = await OracleCountInstallmentPlanAsync(ora, sms, agr, ct);
        var liveMain = await CountLiveMainActionsAsync(ora, sms, agr, ct);

        summary["oraInvoice"] = oraInv;
        summary["oraInvlines"] = oraLines;
        summary["oraInstallment"] = oraInst;
        summary["oraInstallmentPlan"] = oraInstPlan;
        summary["liveMainActions"] = liveMain;
        summary["invoiceSource"] = oraInv > 0 ? "CTAS" : (liveMain > 0 ? "LIVE_SMS" : "NONE");

        var mgrInv = await MssqlCountAsync(mssql, "izgazMGR.dbo.LS_INVOICE", "ABYS_AGREEMENT_ID", agr, ct);
        var mgrLines = await MssqlCountAsync(mssql, "izgazMGR.dbo.LS_INVLINES", "ABYS_AGREEMENT_ID", agr, ct);
        var mgrInst = await MssqlCountAsync(mssql, "izgazMGR.dbo.CS_INSTALLMENT", "AGREEMENT_ID", agr, ct);
        var mgrInstPlan = await MssqlCountInstallmentPlanAsync(mssql, agr, ct);

        summary["mgrInvoiceBefore"] = mgrInv;
        summary["mgrInvlinesBefore"] = mgrLines;
        summary["mgrInstallmentBefore"] = mgrInst;
        summary["mgrInstallmentPlanBefore"] = mgrInstPlan;

        preview.Add(Row("LS_INVOICE", oraInv > 0 ? oraInv : liveMain, mgrInv,
            oraInv > 0 ? "CTAS→izgazMGR" : "LIVE SMS→izgazMGR (CTAS yok)"));
        preview.Add(Row("LS_INVLINES", oraLines, mgrLines, oraInv > 0 ? "CTAS→izgazMGR" : "LIVE income→izgazMGR"));
        preview.Add(Row("CS_INSTALLMENT", oraInst, mgrInst, "SMS→izgazMGR"));
        preview.Add(Row("CS_INSTALLMENT_PLAN", oraInstPlan, mgrInstPlan, "SMS→izgazMGR"));

        if (oraInv == 0 && liveMain == 0)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_NO_CTAS_INVOICE",
                Severity = req.DryRun ? "WARN" : "CRITICAL",
                Side = "SMS",
                Message =
                    $"Oracle {mig}.LS_INVOICE yok ve canlı MAIN action da yok (AGR={agr}). CTAS veya SMS tahakkuk kontrol."
            });
        }
        else if (oraInv == 0)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_LIVE_FALLBACK",
                Severity = "INFO",
                Side = "SMS",
                Message =
                    $"{mig}.LS_INVOICE boş — APPLY canlı SMS'ten ~{liveMain} MAIN fatura (+ income satır) izgazMGR'ye yazacak (pilot CTAS-lite). Prod'da CTAS tercih edilir."
            });
        }
        else if (oraLines == 0)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_NO_CTAS_INVLINES",
                Severity = "WARN",
                Side = "SMS",
                Message = $"{mig}.LS_INVLINES AGR={agr} boş — 12_ls_invlines CTAS kontrol."
            });
        }

        if (req.DryRun)
        {
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_DUMP_DRY_RUN",
                Severity = "INFO",
                Side = "BOTH",
                Message =
                    $"DRY_RUN: APPLY ile AGR={agr} izgazMGR silinip {(oraInv > 0 ? "CTAS" : "LIVE SMS")} + taksit yüklenecek. liveMain={liveMain}."
            });
            sw.Stop();
            return (summary, preview, gaps,
                MakeLog(runId, agr, "pilotDumpMgr", "BOTH", "DRY_RUN", sw.ElapsedMilliseconds,
                    (int)Math.Min(oraInv > 0 ? oraInv : liveMain, int.MaxValue),
                    gaps.Any(g => g.Severity == "CRITICAL") ? "FAIL" : "OK",
                    $"oraInv={oraInv} liveMain={liveMain} mgrInv={mgrInv}"));
        }

        if (gaps.Any(g => g.Severity == "CRITICAL"))
        {
            sw.Stop();
            return (summary, preview, gaps,
                MakeLog(runId, agr, "pilotDumpMgr", "BOTH", "APPLY", sw.ElapsedMilliseconds, 0, "FAIL", "blocked"));
        }

        try
        {
            var delLines = await DeleteMgrAgrAsync(mssql, "izgazMGR.dbo.LS_INVLINES", "ABYS_AGREEMENT_ID", agr, ct);
            var delInv = await DeleteMgrAgrAsync(mssql, "izgazMGR.dbo.LS_INVOICE", "ABYS_AGREEMENT_ID", agr, ct);
            var delPlan = await DeleteMgrInstallmentPlanAsync(mssql, ora, sms, agr, ct);
            var delInst = await DeleteMgrInstallmentAsync(mssql, ora, sms, agr, ct);
            summary["deletedInvlines"] = delLines;
            summary["deletedInvoice"] = delInv;
            summary["deletedInstPlan"] = delPlan;
            summary["deletedInstallment"] = delInst;

            int insInv;
            int insLines;
            if (oraInv > 0)
            {
                insInv = await CopyOracleToMgrAsync(ora, mssql, $"{mig}.LS_INVOICE", "izgazMGR.dbo.LS_INVOICE",
                    "ABYS_AGREEMENT_ID", agr, ct);
                insLines = await CopyOracleToMgrAsync(ora, mssql, $"{mig}.LS_INVLINES", "izgazMGR.dbo.LS_INVLINES",
                    "ABYS_AGREEMENT_ID", agr, ct);
                summary["fillMode"] = "CTAS";
            }
            else
            {
                insInv = await MaterializeLiveInvoiceAsync(ora, mssql, sms, agr, ct);
                insLines = await MaterializeLiveInvlinesAsync(ora, mssql, sms, agr, ct);
                summary["fillMode"] = "LIVE_SMS";
            }

            // AGREEMENT_ID boş olabilir — hesap.INSTALLMENT_ID üzerinden de çek (SMS taksit adımı gibi)
            var insInst = await CopyCsInstallmentForAgrAsync(ora, mssql, sms, agr, ct);
            var insPlan = await CopyInstallmentPlanAsync(ora, mssql, sms, agr, ct);

            summary["insertedInvoice"] = insInv;
            summary["insertedInvlines"] = insLines;
            summary["insertedInstallment"] = insInst;
            summary["insertedInstPlan"] = insPlan;

            mgrInv = await MssqlCountAsync(mssql, "izgazMGR.dbo.LS_INVOICE", "ABYS_AGREEMENT_ID", agr, ct);
            mgrLines = await MssqlCountAsync(mssql, "izgazMGR.dbo.LS_INVLINES", "ABYS_AGREEMENT_ID", agr, ct);
            mgrInst = await MssqlCountAsync(mssql, "izgazMGR.dbo.CS_INSTALLMENT", "AGREEMENT_ID", agr, ct);
            mgrInstPlan = await MssqlCountInstallmentPlanAsync(mssql, agr, ct);
            summary["mgrInvoiceAfter"] = mgrInv;
            summary["mgrInvlinesAfter"] = mgrLines;
            summary["mgrInstallmentAfter"] = mgrInst;
            summary["mgrInstallmentPlanAfter"] = mgrInstPlan;

            preview =
            [
                Row("LS_INVOICE", oraInv > 0 ? oraInv : liveMain, mgrInv, $"after APPLY ({summary["fillMode"]})"),
                Row("LS_INVLINES", oraLines, mgrLines, $"after APPLY ({summary["fillMode"]})"),
                Row("CS_INSTALLMENT", oraInst, mgrInst, "after APPLY"),
                Row("CS_INSTALLMENT_PLAN", oraInstPlan, mgrInstPlan, "after APPLY")
            ];

            if (insInv == 0)
            {
                gaps.Add(new TahsilatGapItem
                {
                    Code = "PILOT_DUMP_ZERO_INVOICE",
                    Severity = "CRITICAL",
                    Side = "BOTH",
                    Message = "APPLY sonrası izgazMGR'ye fatura yazılamadı."
                });
            }
            else if (oraInv > 0 && mgrInv != oraInv)
            {
                gaps.Add(new TahsilatGapItem
                {
                    Code = "PILOT_DUMP_COUNT_MISMATCH",
                    Severity = "WARN",
                    Side = "BOTH",
                    Message = $"LS_INVOICE ora={oraInv} mgr={mgrInv} — kolon farkı veya filtre."
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Pilot dump AGR={Agr} failed", agr);
            gaps.Add(new TahsilatGapItem
            {
                Code = "PILOT_DUMP_FAIL",
                Severity = "CRITICAL",
                Side = "BOTH",
                Message = ex.Message
            });
            sw.Stop();
            return (summary, preview, gaps,
                MakeLog(runId, agr, "pilotDumpMgr", "BOTH", "APPLY", sw.ElapsedMilliseconds, 0, "FAIL", ex.Message));
        }

        sw.Stop();
        var ok = !gaps.Any(g => g.Severity == "CRITICAL");
        return (summary, preview, gaps,
            MakeLog(runId, agr, "pilotDumpMgr", "BOTH", "APPLY", sw.ElapsedMilliseconds,
                (int)Math.Min(Convert.ToInt64(summary.GetValueOrDefault("insertedInvoice") ?? 0), int.MaxValue),
                ok ? "OK" : "FAIL",
                $"insInv={summary.GetValueOrDefault("insertedInvoice")} lines={summary.GetValueOrDefault("insertedInvlines")} inst={summary.GetValueOrDefault("insertedInstallment")}"));
    }

    /// <summary>
    /// Pilot: izgazMGR DB + LS_INVOICE/LS_INVLINES (+ taksit) yoksa oluştur.
    /// Prod'da CTAS→dump sonrası tablolar zaten vardır; bu yol yalnızca pilot boş ortam içindir.
    /// </summary>
    private async Task<string> EnsureIzgazMgrSchemaAsync(
        OracleConnection ora,
        SqlConnection mssql,
        string mig,
        string sms,
        bool apply,
        CancellationToken ct)
    {
        var actions = new List<string>();
        try
        {
            var dbExists = await DatabaseExistsAsync(mssql, "izgazMGR", ct);
            if (!dbExists)
            {
                if (!apply)
                    return "would_create_db+tables";
                await using (var cmd = new SqlCommand(
                    "IF DB_ID(N'izgazMGR') IS NULL CREATE DATABASE [izgazMGR];", mssql))
                {
                    cmd.CommandTimeout = 120;
                    await cmd.ExecuteNonQueryAsync(ct);
                }
                actions.Add("created_db");
            }

            var invCreated = await EnsureMgrTableAsync(
                ora, mssql, $"{mig}.LS_INVOICE", "izgazMGR.dbo.LS_INVOICE", apply, ct,
                fallbackDdl: PilotLsInvoiceFallbackDdl);
            if (invCreated == "would_create") return "would_create_LS_INVOICE";
            if (invCreated == "created") actions.Add("LS_INVOICE");
            if (invCreated.StartsWith("FAIL:", StringComparison.Ordinal)) return invCreated;

            var linesCreated = await EnsureMgrTableAsync(
                ora, mssql, $"{mig}.LS_INVLINES", "izgazMGR.dbo.LS_INVLINES", apply, ct,
                fallbackDdl: PilotLsInvlinesFallbackDdl);
            if (linesCreated == "would_create") return "would_create_LS_INVLINES";
            if (linesCreated == "created") actions.Add("LS_INVLINES");

            var instCreated = await EnsureMgrTableAsync(
                ora, mssql, $"{sms}.CS_INSTALLMENT", "izgazMGR.dbo.CS_INSTALLMENT", apply, ct,
                fallbackDdl: null);
            if (instCreated == "created") actions.Add("CS_INSTALLMENT");

            var planCreated = await EnsureMgrTableAsync(
                ora, mssql, $"{sms}.CS_INSTALLMENT_PLAN", "izgazMGR.dbo.CS_INSTALLMENT_PLAN", apply, ct,
                fallbackDdl: null);
            if (planCreated == "created") actions.Add("CS_INSTALLMENT_PLAN");

            if (apply && await MssqlObjectExistsAsync(mssql, "izgazMGR.dbo.LS_INVOICE", ct))
            {
                // Eski CTAS/iskelet tabloda bu kolonlar yoksa LIVE dump atlıyordu → ENERGY'de taksit eşleşmez
                await EnsureMgrColumnAsync(mssql, "izgazMGR.dbo.LS_INVOICE", "BANKREF", "BIGINT NULL", ct);
                await EnsureMgrColumnAsync(mssql, "izgazMGR.dbo.LS_INVOICE", "BANK_RECORD_REF", "NVARCHAR(50) NULL", ct);
                await EnsureMgrColumnAsync(mssql, "izgazMGR.dbo.LS_INVOICE", "ABYS_ACCOUNT_ID", "BIGINT NULL", ct);
                await EnsureMgrColumnAsync(mssql, "izgazMGR.dbo.LS_INVOICE", "ABYS_INSTALLMENT_ID", "BIGINT NULL", ct);
                await EnsureMgrColumnAsync(mssql, "izgazMGR.dbo.LS_INVOICE", "ABYS_AGREEMENT_ID", "BIGINT NULL", ct);
                await EnsureMgrColumnAsync(mssql, "izgazMGR.dbo.LS_INVOICE", "INSTALLMENT_PLAN_REF", "BIGINT NULL", ct);
                await EnsureIndexAsync(mssql,
                    "izgazMGR.dbo.LS_INVOICE", "IX_MIG_LSINV_ACTION",
                    "CREATE NONCLUSTERED INDEX [IX_MIG_LSINV_ACTION] ON izgazMGR.dbo.LS_INVOICE ([ABYS_ACTION_ID]);",
                    ct);
                await EnsureIndexAsync(mssql,
                    "izgazMGR.dbo.LS_INVOICE", "IX_MIG_LSINV_AGR",
                    "CREATE NONCLUSTERED INDEX [IX_MIG_LSINV_AGR] ON izgazMGR.dbo.LS_INVOICE ([ABYS_AGREEMENT_ID]);",
                    ct);
                actions.Add("indexes_invoice");
            }

            if (apply && await MssqlObjectExistsAsync(mssql, "izgazMGR.dbo.LS_INVLINES", ct))
            {
                await EnsureIndexAsync(mssql,
                    "izgazMGR.dbo.LS_INVLINES", "IX_MIG_LSINVLINES_LREF",
                    "CREATE NONCLUSTERED INDEX [IX_MIG_LSINVLINES_LREF] ON izgazMGR.dbo.LS_INVLINES ([LREF]);",
                    ct);
                await EnsureIndexAsync(mssql,
                    "izgazMGR.dbo.LS_INVLINES", "IX_MIG_LSINVLINES_AGR",
                    "CREATE NONCLUSTERED INDEX [IX_MIG_LSINVLINES_AGR] ON izgazMGR.dbo.LS_INVLINES ([ABYS_AGREEMENT_ID]);",
                    ct);
                actions.Add("indexes_invlines");
            }

            return actions.Count == 0 ? "exists" : "ok:" + string.Join(",", actions);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "EnsureIzgazMgrSchema failed");
            return "FAIL:" + ex.Message;
        }
    }

    private async Task<string> EnsureMgrTableAsync(
        OracleConnection ora,
        SqlConnection mssql,
        string oracleTable,
        string mssqlThreePart,
        bool apply,
        CancellationToken ct,
        string? fallbackDdl)
    {
        if (await MssqlObjectExistsAsync(mssql, mssqlThreePart, ct))
            return "exists";

        if (!apply)
            return "would_create";

        if (await OracleTableExistsAsync(ora, oracleTable, ct))
        {
            var ddl = await BuildCreateTableFromOracleAsync(ora, oracleTable, mssqlThreePart, ct);
            await using var cmd = new SqlCommand(ddl, mssql) { CommandTimeout = 120 };
            await cmd.ExecuteNonQueryAsync(ct);
            _logger.LogInformation("Created {Table} from Oracle {Ora}", mssqlThreePart, oracleTable);
            return "created";
        }

        if (!string.IsNullOrWhiteSpace(fallbackDdl))
        {
            await using var cmd = new SqlCommand(fallbackDdl, mssql) { CommandTimeout = 120 };
            await cmd.ExecuteNonQueryAsync(ct);
            _logger.LogInformation("Created {Table} from pilot fallback DDL (Oracle CTAS henüz yok)", mssqlThreePart);
            return "created";
        }

        return "skip_no_oracle_no_fallback";
    }

    private static async Task EnsureIndexAsync(
        SqlConnection mssql, string threePart, string indexName, string createSql, CancellationToken ct)
    {
        // threePart = izgazMGR.dbo.LS_INVOICE
        var parts = threePart.Split('.');
        if (parts.Length != 3) return;
        var db = parts[0].Trim('[', ']');
        await using var probe = new SqlCommand($@"
SELECT COUNT(*)
  FROM {db}.sys.indexes i
  INNER JOIN {db}.sys.tables t ON t.object_id = i.object_id
  INNER JOIN {db}.sys.schemas s ON s.schema_id = t.schema_id
 WHERE i.name = @ix AND s.name = N'dbo' AND t.name = @tbl", mssql);
        probe.Parameters.AddWithValue("@ix", indexName);
        probe.Parameters.AddWithValue("@tbl", parts[2].Trim('[', ']'));
        var n = Convert.ToInt32(await probe.ExecuteScalarAsync(ct) ?? 0);
        if (n > 0) return;
        try
        {
            await using var cmd = new SqlCommand(createSql, mssql) { CommandTimeout = 300 };
            await cmd.ExecuteNonQueryAsync(ct);
        }
        catch (SqlException ex) when (ex.Number == 1913 || ex.Number == 1834)
        {
            // index already exists / duplicate
        }
    }

    private static async Task EnsureMgrColumnAsync(
        SqlConnection mssql, string threePart, string columnName, string sqlType, CancellationToken ct)
    {
        var parts = threePart.Split('.');
        if (parts.Length != 3) return;
        var db = parts[0].Trim('[', ']');
        var tbl = parts[2].Trim('[', ']');
        await using var probe = new SqlCommand($@"
SELECT COUNT(*)
  FROM {db}.sys.columns c
  INNER JOIN {db}.sys.tables t ON t.object_id = c.object_id
  INNER JOIN {db}.sys.schemas s ON s.schema_id = t.schema_id
 WHERE s.name = N'dbo' AND t.name = @tbl AND c.name = @col", mssql);
        probe.Parameters.AddWithValue("@tbl", tbl);
        probe.Parameters.AddWithValue("@col", columnName);
        if (Convert.ToInt32(await probe.ExecuteScalarAsync(ct) ?? 0) > 0) return;
        await using var alter = new SqlCommand(
            $"ALTER TABLE {threePart} ADD [{columnName}] {sqlType};", mssql)
        { CommandTimeout = 60 };
        await alter.ExecuteNonQueryAsync(ct);
    }

    private static async Task<bool> DatabaseExistsAsync(SqlConnection mssql, string dbName, CancellationToken ct)
    {
        await using var cmd = new SqlCommand("SELECT CASE WHEN DB_ID(@db) IS NULL THEN 0 ELSE 1 END", mssql);
        cmd.Parameters.AddWithValue("@db", dbName);
        return Convert.ToInt32(await cmd.ExecuteScalarAsync(ct) ?? 0) == 1;
    }

    private static async Task<string> BuildCreateTableFromOracleAsync(
        OracleConnection ora, string oracleTable, string mssqlThreePart, CancellationToken ct)
    {
        var parts = oracleTable.Split('.', 2);
        await using var cmd = ora.CreateCommand();
        cmd.BindByName = true;
        cmd.CommandText = @"
SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH, DATA_PRECISION, DATA_SCALE, NULLABLE
  FROM ALL_TAB_COLUMNS
 WHERE OWNER = :own AND TABLE_NAME = :tn
 ORDER BY COLUMN_ID";
        cmd.Parameters.Add("own", parts[0].ToUpperInvariant());
        cmd.Parameters.Add("tn", parts[1].ToUpperInvariant());

        var cols = new List<string>();
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
        {
            var name = r.GetString(0);
            var dtype = r.GetString(1);
            var len = r.IsDBNull(2) ? 0 : Convert.ToInt32(r.GetValue(2));
            int? prec = r.IsDBNull(3) ? null : Convert.ToInt32(r.GetValue(3));
            int? scale = r.IsDBNull(4) ? null : Convert.ToInt32(r.GetValue(4));
            var nullable = string.Equals(r.GetString(5), "Y", StringComparison.OrdinalIgnoreCase);
            var sqlType = MapOracleTypeToSql(dtype, len, prec, scale);
            cols.Add($"[{name}] {sqlType} {(nullable ? "NULL" : "NULL")}"); // pilot: hepsi NULL (bulk copy güvenli)
        }

        if (cols.Count == 0)
            throw new InvalidOperationException($"{oracleTable}: kolon yok — CREATE atlandı.");

        return $"CREATE TABLE {mssqlThreePart} (\n  " + string.Join(",\n  ", cols) + "\n);";
    }

    private static string MapOracleTypeToSql(string dataType, int length, int? precision, int? scale)
    {
        var dt = dataType.ToUpperInvariant();
        return dt switch
        {
            // Tutar: FLOAT kullanma — nokta sonrasi haneler/bulk round-trip kaybi
            "NUMBER" when scale is > 0 =>
                $"DECIMAL({Math.Clamp(precision ?? 18, scale.Value + 1, 38)},{Math.Clamp(scale.Value, 0, 10)})",
            "NUMBER" when precision is null or 0 => "DECIMAL(38,10)",
            "NUMBER" when precision is <= 4 => "SMALLINT",
            "NUMBER" when precision is <= 9 => "INT",
            "NUMBER" when precision is <= 18 => "BIGINT",
            "NUMBER" => $"DECIMAL({Math.Min(precision ?? 38, 38)},0)",
            "FLOAT" or "BINARY_FLOAT" or "BINARY_DOUBLE" => "FLOAT",
            "DATE" or "TIMESTAMP" or "TIMESTAMP(6)" => "DATETIME2",
            "VARCHAR2" or "NVARCHAR2" or "CHAR" or "NCHAR" =>
                length is > 0 and <= 4000 ? $"NVARCHAR({Math.Min(length, 4000)})" : "NVARCHAR(MAX)",
            "CLOB" or "NCLOB" or "LONG" => "NVARCHAR(MAX)",
            "BLOB" or "RAW" => "VARBINARY(MAX)",
            _ => "NVARCHAR(400)"
        };
    }

    // 571'in okuduğu temel kolonlar — Oracle CTAS henüz yokken pilot iskelet
    private const string PilotLsInvoiceFallbackDdl = """
        CREATE TABLE izgazMGR.dbo.LS_INVOICE (
            LREF BIGINT NULL,
            ABYS_ACTION_ID BIGINT NULL,
            ABYS_ACCOUNT_ID BIGINT NULL,
            ABYS_ACTION_TYPE_ID BIGINT NULL,
            ABYS_ACCRUE_TYPE_ID BIGINT NULL,
            ABYS_REGISTER_ID BIGINT NULL,
            ABYS_AGREEMENT_ID BIGINT NULL,
            ABYS_INSTALLATION_ID BIGINT NULL,
            ABYS_METER_ID BIGINT NULL,
            ABYS_AREA_ID BIGINT NULL,
            ABYS_PROJECT_ID BIGINT NULL,
            ABYS_TARIFF_TYPE_ID BIGINT NULL,
            ABYS_SKB_TARIFF_TYPE_ID BIGINT NULL,
            ABYS_SUBSCRIBER_TYPE_ID BIGINT NULL,
            ABYS_READING_DATE DATETIME2 NULL,
            ABYS_IS_E_BILL FLOAT NULL,
            ABYS_IS_FPS FLOAT NULL,
            ABYS_DO_DISCHARGE FLOAT NULL,
            ABYS_INSTALLMENT_ID BIGINT NULL,
            ABYS_GROUP_ACCOUNT_ID BIGINT NULL,
            ABYS_BILL_TYPE_ID BIGINT NULL,
            ABYS_BILL_SERIAL NVARCHAR(50) NULL,
            ABYS_BILL_ORDER_NUMBER BIGINT NULL,
            ABYS_BILL_NUMBER NVARCHAR(100) NULL,
            ABYS_CONSUMPTION FLOAT NULL,
            ABYS_M3 FLOAT NULL,
            ABYS_KWH FLOAT NULL,
            ABYS_CUSTOMER_BILL_TYPE BIGINT NULL,
            ABYS_REF_DEPOSIT_ACCOUNT_ID BIGINT NULL,
            ABYS_REF_DEP_ACC_ACTION_ID BIGINT NULL,
            ABYS_POOL_ID BIGINT NULL,
            ABYS_CREATED_USER_ID BIGINT NULL,
            ABYS_UPDATED_USER_ID BIGINT NULL,
            ABYS_VERSION BIGINT NULL,
            ABYS_ID BIGINT NULL,
            TRNSACTION_TYPE_ID BIGINT NULL,
            IOCODE FLOAT NULL,
            FICHENO NVARCHAR(45) NULL,
            DATE_ DATETIME2 NULL,
            DUEDATE DATETIME2 NULL,
            [TYPE] FLOAT NULL,
            CLIENTREF BIGINT NULL,
            TLTOTAL DECIMAL(18,3) NULL,
            CURID FLOAT NULL,
            CURTOTAL DECIMAL(18,3) NULL,
            ACCRUE_TYPE_ID BIGINT NULL,
            EXPLAIN NVARCHAR(250) NULL,
            CANCELED FLOAT NULL,
            OWNERREF BIGINT NULL,
            OWNERTYPE FLOAT NULL,
            LOGOREF BIGINT NULL,
            TAX DECIMAL(18,3) NULL,
            DV DECIMAL(18,3) NULL,
            GRANDTOTAL DECIMAL(18,3) NULL,
            PRINTCOUNT BIGINT NULL,
            PAYABLETOTAL DECIMAL(18,3) NULL,
            READ_TRANSREF BIGINT NULL,
            INTERESTRATE DECIMAL(18,6) NULL,
            GAS_OPEN_FEE DECIMAL(18,3) NULL,
            DETACH_ATTACH_FEE DECIMAL(18,3) NULL,
            TEST_FEE DECIMAL(18,3) NULL,
            SPEC_SERV_FEE DECIMAL(18,3) NULL,
            FIXED_FEE DECIMAL(18,3) NULL,
            EXPEND_FEE DECIMAL(18,3) NULL,
            DEFAULT_FINE DECIMAL(18,3) NULL,
            DEFAULT_FINETAX DECIMAL(18,3) NULL,
            FITNO BIGINT NULL,
            CHEQUEREF BIGINT NULL,
            ADDDATE DATETIME2 NULL,
            ADDUSER BIGINT NULL,
            UPDDATE DATETIME2 NULL,
            UPDUSER BIGINT NULL,
            LAWDETAILREF BIGINT NULL,
            BANKREF BIGINT NULL,
            CUSTBNK_ACC NVARCHAR(20) NULL,
            BANK_STAT BIGINT NULL,
            BANK_CANCELLED FLOAT NULL,
            BANK_RECORD_REF NVARCHAR(50) NULL,
            ILLEGAL_USE_FEE DECIMAL(18,3) NULL,
            LOGO_FIRMNR BIGINT NULL,
            LOGO_FICHEREF BIGINT NULL,
            LOGO_FICHENO NVARCHAR(100) NULL,
            DISCOUNT_ADDITION FLOAT NULL,
            RETURN_SOURCE_INVREF BIGINT NULL,
            RETURN_TARGET_INVREF BIGINT NULL,
            CLOSED FLOAT NULL,
            CCCONFIRMCODE NVARCHAR(50) NULL,
            BANKACCREF BIGINT NULL,
            XTYPE BIGINT NULL,
            BN_TYPE BIGINT NULL,
            OLOC_ID BIGINT NULL,
            OLREF BIGINT NULL,
            LASTPAIDDATE DATETIME2 NULL,
            IS_DUPLICATE_PAYMENT FLOAT NULL,
            PRJ_INV_REF BIGINT NULL,
            IS_LAW FLOAT NULL,
            ISSENDINVOICE FLOAT NULL,
            ISAPPROVEINVOICE FLOAT NULL,
            SUCCESSCODE NVARCHAR(100) NULL,
            ETTN NVARCHAR(100) NULL,
            ARCHIVENO BIGINT NULL,
            INVPRENAME NVARCHAR(5) NULL,
            ISBUYUKSANAYIFATURA FLOAT NULL,
            INVOICERETURNMESSAGE NVARCHAR(400) NULL,
            CANCELEARCHIVEINVOICEISSEND FLOAT NULL,
            AMOUNT DECIMAL(18,3) NULL,
            ARCHIVE_SEND_STATUS BIGINT NULL,
            ARCHIVE_MAIL_SEND_STATUS BIGINT NULL,
            ARCHIVE_SEND_DATE DATETIME2 NULL,
            ARCHIVE_MAIL_SEND_DATE DATETIME2 NULL,
            PERIOD NVARCHAR(50) NULL,
            HAS_DISCOUNT FLOAT NULL,
            DISCOUNT_AMOUNT DECIMAL(18,3) NULL,
            DISCOUNT_REMAIN_AMOUNT DECIMAL(18,3) NULL,
            DISCOUNT_USED_AMOUNT DECIMAL(18,3) NULL,
            CANCEL_DATE DATETIME2 NULL,
            CANCEL_REASON_ID BIGINT NULL,
            CANCEL_USER_ID BIGINT NULL,
            DESCRIPTION NVARCHAR(400) NULL,
            INSTALLMENT_PLAN_REF BIGINT NULL,
            TAX_TEVKIFAT DECIMAL(18,3) NULL,
            QMIN DECIMAL(18,6) NULL,
            QMAX DECIMAL(18,6) NULL,
            ARCHIVE_CANCEL_DATE DATETIME2 NULL,
            ARCHIVE_LAST_PROCESS_DATE DATETIME2 NULL
        );
        """;

    private const string PilotLsInvlinesFallbackDdl = """
        CREATE TABLE izgazMGR.dbo.LS_INVLINES (
            LREF BIGINT NULL,
            INVOICEREF BIGINT NULL,
            CLIENTREF BIGINT NULL,
            DATE_ DATETIME2 NULL,
            [TYPE] FLOAT NULL,
            LINENR FLOAT NULL,
            TLTOTAL FLOAT NULL,
            CURID FLOAT NULL,
            CURRATE FLOAT NULL,
            CURTOTAL FLOAT NULL,
            FIRSTREAD FLOAT NULL,
            LASTREAD FLOAT NULL,
            TRANSTYPE BIGINT NULL,
            CANCELED FLOAT NULL,
            TAX FLOAT NULL,
            GRANDTOTAL FLOAT NULL,
            LINEEXP NVARCHAR(300) NULL,
            LINETYPE BIGINT NULL,
            DV FLOAT NULL,
            FITNO NVARCHAR(100) NULL,
            CNTREF BIGINT NULL,
            LOGO_FIRMNR BIGINT NULL,
            LOGO_FICHEREF BIGINT NULL,
            LOGO_FICHENO NVARCHAR(100) NULL,
            XTYPE BIGINT NULL,
            UNITPRICE DECIMAL(18,6) NULL,
            SPEREF BIGINT NULL,
            AMOUNT DECIMAL(18,3) NULL,
            FIRST_DATE DATETIME2 NULL,
            LAST_DATE DATETIME2 NULL,
            [DAY] FLOAT NULL,
            ABYS_ID BIGINT NULL,
            ABYS_INCOME_ROW_ID BIGINT NULL,
            ABYS_INCOME_ID BIGINT NULL,
            ABYS_ACTION_ID BIGINT NULL,
            ABYS_ACCOUNT_ID BIGINT NULL,
            ABYS_REGISTER_ID BIGINT NULL,
            ABYS_AGREEMENT_ID BIGINT NULL,
            ABYS_ACTION_TYPE_ID BIGINT NULL,
            ABYS_ACCRUE_TYPE_ID BIGINT NULL,
            ABYS_IS_DISCOUNT FLOAT NULL,
            ABYS_IS_VAT_INCOME FLOAT NULL,
            ABYS_IS_DEPOSIT FLOAT NULL,
            ABYS_IS_OVERDUE_INCOME FLOAT NULL,
            ABYS_IS_LEGAL_FEE FLOAT NULL,
            ABYS_INCOME_CODE NVARCHAR(100) NULL,
            ABYS_AMOUNT_RAW FLOAT NULL,
            ABYS_STATUS FLOAT NULL,
            ABYS_QUANTITY FLOAT NULL,
            ABYS_UNIT_PRICE FLOAT NULL,
            ABYS_AMOUNT1 FLOAT NULL,
            ABYS_AMOUNT2 FLOAT NULL,
            ABYS_AMOUNT3 FLOAT NULL,
            ABYS_AMOUNT4 FLOAT NULL,
            ABYS_AMOUNT5 FLOAT NULL
        );
        """;

    private async Task<(string Mig, string Sms, string Note)> ResolveSchemasAsync(
        OracleConnection ora,
        AgreementTahsilatRequest req,
        string oracleUser,
        CancellationToken ct)
    {
        var requestedMig = string.IsNullOrWhiteSpace(req.MigrationSchema)
            ? null
            : SanitizeIdent(req.MigrationSchema, oracleUser);
        var requestedSms = string.IsNullOrWhiteSpace(req.SmsSchema)
            ? null
            : SanitizeIdent(req.SmsSchema, oracleUser);

        // SMS şema: ekran değeri varsa ve varsa kullan; yoksa bağlı kullanıcı
        string sms;
        if (requestedSms != null && await OracleUserExistsAsync(ora, requestedSms, ct))
            sms = requestedSms;
        else
            sms = oracleUser;

        // CTAS/mig şema: ekran değeri mevcut Oracle user/schema ise kullan; değilse bağlı kullanıcı
        string mig;
        string note;
        if (requestedMig != null && await OracleUserExistsAsync(ora, requestedMig, ct))
        {
            mig = requestedMig;
            note = $"mig={mig} (ekran), sms={sms}, login={oracleUser}";
        }
        else if (requestedMig != null)
        {
            mig = oracleUser;
            note = $"mig={requestedMig} yok → login user {oracleUser}; sms={sms}";
        }
        else
        {
            mig = oracleUser;
            note = $"mig/sms = login user {oracleUser}";
        }

        return (mig, sms, note);
    }

    private static async Task<string> GetOracleCurrentUserAsync(OracleConnection ora, CancellationToken ct)
    {
        await using var cmd = ora.CreateCommand();
        cmd.CommandText = "SELECT USER FROM DUAL";
        var u = Convert.ToString(await cmd.ExecuteScalarAsync(ct));
        if (string.IsNullOrWhiteSpace(u))
            throw new InvalidOperationException("Oracle USER alınamadı.");
        return SanitizeIdent(u, u);
    }

    private static async Task<bool> OracleUserExistsAsync(OracleConnection ora, string userOrSchema, CancellationToken ct)
    {
        await using var cmd = ora.CreateCommand();
        cmd.BindByName = true;
        // ALL_USERS: gerçek kullanıcı; syn/schema için ALL_USERS yeterli (ORA-01918 önleme)
        cmd.CommandText = "SELECT COUNT(*) FROM ALL_USERS WHERE USERNAME = :u";
        cmd.Parameters.Add("u", userOrSchema.ToUpperInvariant());
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct) ?? 0) > 0;
    }

    private async Task<string> EnsureMigParamAsync(
        OracleConnection ora, string mig, string oracleUser, long agr, bool apply, CancellationToken ct)
    {
        try
        {
            // MIG_PARAM her zaman bağlı kullanıcının şemasında tutulur (yazma yetkisi kesin)
            var owner = oracleUser;

            await using (var probe = ora.CreateCommand())
            {
                probe.BindByName = true;
                probe.CommandText = @"
SELECT COUNT(*) FROM ALL_TABLES WHERE OWNER = :own AND TABLE_NAME = 'MIG_PARAM'";
                probe.Parameters.Add("own", owner.ToUpperInvariant());
                var exists = Convert.ToInt64(await probe.ExecuteScalarAsync(ct) ?? 0) > 0;
                if (!exists)
                {
                    if (!apply) return $"would_create_{owner}.MIG_PARAM+seed";
                    await using var create = ora.CreateCommand();
                    // Unqualified = current user schema (ekrandaki Oracle kullanıcı)
                    create.CommandText = "CREATE TABLE MIG_PARAM (REG_ID NUMBER(12), AGR_ID NUMBER(12))";
                    await create.ExecuteNonQueryAsync(ct);
                }
            }

            // Okuma: önce ekran mig şeması, yoksa owner
            var readSchema = await OracleTableExistsAsync(ora, $"{mig}.MIG_PARAM", ct) ? mig : owner;

            await using (var cnt = ora.CreateCommand())
            {
                cnt.BindByName = true;
                cnt.CommandText = $"SELECT COUNT(*) FROM {readSchema}.MIG_PARAM WHERE AGR_ID = :agr";
                cnt.Parameters.Add("agr", agr);
                var n = Convert.ToInt64(await cnt.ExecuteScalarAsync(ct) ?? 0);
                if (n > 0) return apply ? $"already_present:{readSchema}" : $"present:{readSchema}";
                if (!apply) return $"would_seed:{readSchema}";
                await using var ins = ora.CreateCommand();
                ins.BindByName = true;
                ins.CommandText = $"INSERT INTO {owner}.MIG_PARAM (AGR_ID) VALUES (:agr)";
                ins.Parameters.Add("agr", agr);
                await ins.ExecuteNonQueryAsync(ct);
                await using var commit = ora.CreateCommand();
                commit.CommandText = "COMMIT";
                await commit.ExecuteNonQueryAsync(ct);
                return $"seeded:{owner}";
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "MIG_PARAM seed failed");
            return $"error:{ex.Message}";
        }
    }

    private static async Task<long> CountLiveMainActionsAsync(
        OracleConnection ora, string sms, long agr, CancellationToken ct)
    {
        await using var cmd = ora.CreateCommand();
        cmd.BindByName = true;
        cmd.CommandText = $@"
SELECT COUNT(*)
  FROM {sms}.CS_ACCOUNT_ACTION aa
  JOIN {sms}.CS_ACCOUNT acc ON acc.ID = aa.ACCOUNT_ID
 WHERE acc.AGREEMENT_ID = :agr
   AND aa.ACTION_TYPE_ID IN (1, 3, 10, 41)
   AND NVL(acc.ACCRUE_TYPE_ID, -1) <> 14
   AND aa.ID BETWEEN 1 AND 2147483647";
        cmd.Parameters.Add("agr", agr);
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct) ?? 0);
    }

    /// <summary>
    /// Pilot CTAS-lite: SMS MAIN action → izgazMGR.LS_INVOICE (STG_INV_ACC_INC yok).
    /// Tutar = SUM(AMOUNT×STATUS); CLOSED = net≈0.
    /// </summary>
    private async Task<int> MaterializeLiveInvoiceAsync(
        OracleConnection ora, SqlConnection mssql, string sms, long agr, CancellationToken ct)
    {
        if (!await MssqlObjectExistsAsync(mssql, "izgazMGR.dbo.LS_INVOICE", ct))
            return 0;

        var msCols = await MssqlColumnsAsync(mssql, "izgazMGR.dbo.LS_INVOICE", ct);
        await using var cmd = ora.CreateCommand();
        cmd.BindByName = true;
        cmd.CommandTimeout = 600;
        var hasAtp = await OracleTableExistsAsync(ora, $"{sms}.CS_ACTION_TYPE_PRM", ct);
        var lastPayExpr = hasAtp
            ? "MAX(CASE WHEN NVL(atp.TYPE,0) = 2 OR aa2.ACTION_TYPE_ID = 3 THEN aa2.ACTION_DATE END)"
            : "MAX(CASE WHEN aa2.ACTION_TYPE_ID = 3 THEN aa2.ACTION_DATE END)";
        var lastBankExpr = hasAtp
            ? "MAX(CASE WHEN NVL(atp.TYPE,0) = 2 OR aa2.ACTION_TYPE_ID = 3 THEN aa2.BANK_ID END)"
            : "MAX(CASE WHEN aa2.ACTION_TYPE_ID = 3 THEN aa2.BANK_ID END)";
        var lastReceiptExpr = hasAtp
            ? "MAX(CASE WHEN NVL(atp.TYPE,0) = 2 OR aa2.ACTION_TYPE_ID = 3 THEN TO_CHAR(aa2.RECEIPT_NUMBER) END)"
            : "MAX(CASE WHEN aa2.ACTION_TYPE_ID = 3 THEN TO_CHAR(aa2.RECEIPT_NUMBER) END)";
        var atpJoin = hasAtp
            ? $"LEFT JOIN {sms}.CS_ACTION_TYPE_PRM atp ON atp.ID = aa2.ACTION_TYPE_ID"
            : "";

        // 11g uyumlu — FETCH FIRST yok; AGR zaten küçük
        cmd.CommandText = $@"
SELECT aa.ID AS LREF,
       aa.ID AS ABYS_ACTION_ID,
       aa.ID AS ABYS_ID,
       acc.ID AS ABYS_ACCOUNT_ID,
       aa.ACTION_TYPE_ID AS ABYS_ACTION_TYPE_ID,
       acc.ACCRUE_TYPE_ID AS ABYS_ACCRUE_TYPE_ID,
       acc.REGISTER_ID AS ABYS_REGISTER_ID,
       acc.AGREEMENT_ID AS ABYS_AGREEMENT_ID,
       acc.INSTALLATION_ID AS ABYS_INSTALLATION_ID,
       acc.METER_ID AS ABYS_METER_ID,
       acc.AREA_ID AS ABYS_AREA_ID,
       acc.PROJECT_ID AS ABYS_PROJECT_ID,
       acc.TARIFF_TYPE_ID AS ABYS_TARIFF_TYPE_ID,
       acc.SKB_TARIFF_TYPE_ID AS ABYS_SKB_TARIFF_TYPE_ID,
       acc.SUBSCRIBER_TYPE_ID AS ABYS_SUBSCRIBER_TYPE_ID,
       acc.READING_DATE AS ABYS_READING_DATE,
       CASE WHEN NVL(acc.IS_E_BILL,0)=0 THEN 0 ELSE 1 END AS ABYS_IS_E_BILL,
       CASE WHEN NVL(acc.IS_FPS,0)=0 THEN 0 ELSE 1 END AS ABYS_IS_FPS,
       CASE WHEN NVL(acc.DO_DISCHARGE,0)=0 THEN 0 ELSE 1 END AS ABYS_DO_DISCHARGE,
       acc.INSTALLMENT_ID AS ABYS_INSTALLMENT_ID,
       acc.GROUP_ACCOUNT_ID AS ABYS_GROUP_ACCOUNT_ID,
       aa.BILL_TYPE_ID AS ABYS_BILL_TYPE_ID,
       aa.BILL_SERIAL AS ABYS_BILL_SERIAL,
       aa.BILL_ORDER_NUMBER AS ABYS_BILL_ORDER_NUMBER,
       aa.BILL_NUMBER AS ABYS_BILL_NUMBER,
       aa.CONSUMPTION AS ABYS_CONSUMPTION,
       aa.M3 AS ABYS_M3,
       aa.KWH AS ABYS_KWH,
       aa.CUSTOMER_BILL_TYPE AS ABYS_CUSTOMER_BILL_TYPE,
       aa.REF_DEPOSIT_ACCOUNT_ID AS ABYS_REF_DEPOSIT_ACCOUNT_ID,
       aa.REF_DEPOSIT_ACCOUNT_ACTION_ID AS ABYS_REF_DEP_ACC_ACTION_ID,
       aa.POOL_ID AS ABYS_POOL_ID,
       aa.CREATED_USER_ID AS ABYS_CREATED_USER_ID,
       aa.UPDATED_USER_ID AS ABYS_UPDATED_USER_ID,
       aa.VERSION AS ABYS_VERSION,
       acc.ACCRUE_TYPE_ID AS TRNSACTION_TYPE_ID,
       CAST(0 AS NUMBER(3)) AS IOCODE,
       CAST(SUBSTR(NVL(aa.BILL_SERIAL,'') || TO_CHAR(aa.BILL_ORDER_NUMBER), 1, 45) AS VARCHAR2(45)) AS FICHENO,
       CAST(aa.ACTION_DATE AS DATE) AS DATE_,
       CAST(acc.EXPIRY_DATE AS DATE) AS DUEDATE,
       CAST(
         CASE
           WHEN acc.ACCRUE_TYPE_ID = 443 THEN 121
           WHEN aa.ACTION_TYPE_ID IN (3, 10, 41) THEN 93
           ELSE 119
         END AS NUMBER(3)
       ) AS TYPE,
       acc.REGISTER_ID AS CLIENTREF,
       CAST(ROUND(NVL(inc.DEBT_AMT, NVL(ab.ACC_DEBT,0)), 3) AS NUMBER(18,3)) AS TLTOTAL,
       CAST(160 AS NUMBER(10)) AS CURID,
       CAST(ROUND(NVL(inc.DEBT_AMT, NVL(ab.ACC_DEBT,0)), 3) AS NUMBER(18,3)) AS CURTOTAL,
       acc.ACCRUE_TYPE_ID AS ACCRUE_TYPE_ID,
       CAST(NULL AS VARCHAR2(250)) AS EXPLAIN,
       CAST(0 AS NUMBER(1)) AS CANCELED,
       acc.AGREEMENT_ID AS OWNERREF,
       CAST(91 AS NUMBER(3)) AS OWNERTYPE,
       CAST(NULL AS NUMBER(10)) AS LOGOREF,
       CAST(0 AS NUMBER(18,3)) AS TAX,
       CAST(0 AS NUMBER(18,3)) AS DV,
       CAST(ROUND(NVL(inc.DEBT_AMT, NVL(ab.ACC_DEBT,0)), 3) AS NUMBER(18,3)) AS GRANDTOTAL,
       NVL(aa.BILL_PRINT_NUMBER, 0) AS PRINTCOUNT,
       CAST(ROUND(NVL(inc.DEBT_AMT, NVL(ab.ACC_DEBT,0)), 3) AS NUMBER(18,3)) AS PAYABLETOTAL,
       CAST(NULL AS NUMBER(12)) AS READ_TRANSREF,
       CAST(NULL AS NUMBER(18,6)) AS INTERESTRATE,
       CAST(0 AS NUMBER(18,3)) AS GAS_OPEN_FEE,
       CAST(0 AS NUMBER(18,3)) AS DETACH_ATTACH_FEE,
       CAST(0 AS NUMBER(18,3)) AS TEST_FEE,
       CAST(0 AS NUMBER(18,3)) AS SPEC_SERV_FEE,
       CAST(0 AS NUMBER(18,3)) AS FIXED_FEE,
       CAST(0 AS NUMBER(18,3)) AS EXPEND_FEE,
       CAST(0 AS NUMBER(18,3)) AS DEFAULT_FINE,
       CAST(0 AS NUMBER(18,3)) AS DEFAULT_FINETAX,
       acc.INSTALLATION_ID AS FITNO,
       CAST(NULL AS NUMBER(10)) AS CHEQUEREF,
       CAST(aa.CREATED_TIMESTAMP AS DATE) AS ADDDATE,
       CASE WHEN aa.CREATED_USER_ID IS NULL THEN NULL ELSE aa.CREATED_USER_ID + 10000 END AS ADDUSER,
       CAST(aa.UPDATED_TIMESTAMP AS DATE) AS UPDDATE,
       CASE WHEN aa.UPDATED_USER_ID IS NULL THEN NULL ELSE aa.UPDATED_USER_ID + 10000 END AS UPDUSER,
       aa.LEGAL_PROCEEDING_ID AS LAWDETAILREF,
       COALESCE(ab.LAST_BANK_ID, aa.BANK_ID) AS BANKREF,
       CAST(SUBSTR(NVL(ab.LAST_RECEIPT, TO_CHAR(aa.RECEIPT_NUMBER)), 1, 50) AS VARCHAR2(50)) AS BANK_RECORD_REF,
       CAST(CASE WHEN ABS(NVL(ab.ACC_NET,0)) <= 0.01 THEN 1 ELSE 0 END AS NUMBER(1)) AS CLOSED,
       CAST(CASE WHEN ABS(NVL(ab.ACC_NET,0)) <= 0.01 THEN 1 ELSE 0 END AS NUMBER(1)) AS CLOSED_CALC,
       CAST(ROUND(NVL(inc.DEBT_AMT, NVL(ab.ACC_DEBT,0)), 3) AS NUMBER(18,3)) AS AMOUNT,
       ab.LAST_PAY_DATE AS LASTPAIDDATE,
       CAST(0 AS NUMBER(1)) AS IS_DUPLICATE_PAYMENT,
       CAST(CASE WHEN aa.LEGAL_PROCEEDING_ID IS NOT NULL THEN 1 ELSE 0 END AS NUMBER(1)) AS IS_LAW,
       acc.TARIFF_TYPE_ID AS BN_TYPE,
       acc.INSTALLATION_ID AS OLOC_ID,
       acc.ID AS OLREF,
       -- PLAN_ID = CS_INSTALLMENT.ID (hesap); action.INSTALLMENT_ID çoğu zaman NULL
       NVL(acc.INSTALLMENT_ID, aa.INSTALLMENT_ID) AS INSTALLMENT_PLAN_REF,
       CAST(SUBSTR(NVL(aa.DESCRIPTION, acc.DESCRIPTION), 1, 400) AS VARCHAR2(400)) AS DESCRIPTION,
       acc.PERIOD AS PERIOD
  FROM {sms}.CS_ACCOUNT_ACTION aa
  JOIN {sms}.CS_ACCOUNT acc ON acc.ID = aa.ACCOUNT_ID
  LEFT JOIN (
    SELECT AI.ACCOUNT_ACTION_ID,
           SUM(CASE WHEN AI.STATUS > 0 THEN AI.AMOUNT * AI.STATUS ELSE 0 END) AS DEBT_AMT,
           SUM(AI.AMOUNT * AI.STATUS) AS NET_AMT
      FROM {sms}.CS_ACCOUNT_INCOME AI
      JOIN {sms}.CS_ACCOUNT_ACTION x ON x.ID = AI.ACCOUNT_ACTION_ID
      JOIN {sms}.CS_ACCOUNT a2 ON a2.ID = x.ACCOUNT_ID
     WHERE a2.AGREEMENT_ID = :agr
     GROUP BY AI.ACCOUNT_ACTION_ID
  ) inc ON inc.ACCOUNT_ACTION_ID = aa.ID
  LEFT JOIN (
    SELECT aa2.ACCOUNT_ID,
           SUM(ai2.AMOUNT * ai2.STATUS) AS ACC_NET,
           SUM(CASE WHEN ai2.STATUS > 0 THEN ai2.AMOUNT * ai2.STATUS ELSE 0 END) AS ACC_DEBT,
           {lastPayExpr} AS LAST_PAY_DATE,
           {lastBankExpr} AS LAST_BANK_ID,
           {lastReceiptExpr} AS LAST_RECEIPT
      FROM {sms}.CS_ACCOUNT_ACTION aa2
      JOIN {sms}.CS_ACCOUNT a3 ON a3.ID = aa2.ACCOUNT_ID
      JOIN {sms}.CS_ACCOUNT_INCOME ai2 ON ai2.ACCOUNT_ACTION_ID = aa2.ID
      {atpJoin}
     WHERE a3.AGREEMENT_ID = :agr
     GROUP BY aa2.ACCOUNT_ID
  ) ab ON ab.ACCOUNT_ID = acc.ID
 WHERE acc.AGREEMENT_ID = :agr
   AND aa.ACTION_TYPE_ID IN (1, 3, 10, 41)
   AND NVL(acc.ACCRUE_TYPE_ID, -1) <> 14
   AND aa.ID BETWEEN 1 AND 2147483647
   AND NVL(inc.DEBT_AMT, NVL(ab.ACC_DEBT,0)) > 0.01";
        cmd.Parameters.Add("agr", agr);

        await using var reader = await cmd.ExecuteReaderAsync(ct);
        var table = new DataTable();
        var names = new List<string>();
        for (var i = 0; i < reader.FieldCount; i++)
        {
            var name = reader.GetName(i);
            if (string.Equals(name, "CLOSED_CALC", StringComparison.OrdinalIgnoreCase))
                continue; // merge into CLOSED below
            if (!msCols.Contains(name, StringComparer.OrdinalIgnoreCase))
                continue;
            if (table.Columns.Contains(name)) continue;
            names.Add(name);
            table.Columns.Add(name, typeof(object));
        }

        // Ensure CLOSED maps from CLOSED_CALC if present
        var closedCalcOrd = -1;
        for (var i = 0; i < reader.FieldCount; i++)
            if (string.Equals(reader.GetName(i), "CLOSED_CALC", StringComparison.OrdinalIgnoreCase))
                closedCalcOrd = i;

        var ordMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < reader.FieldCount; i++)
            ordMap[reader.GetName(i)] = i;

        while (await reader.ReadAsync(ct))
        {
            var row = table.NewRow();
            foreach (var name in names)
            {
                if (!ordMap.TryGetValue(name, out var oi) || reader.IsDBNull(oi))
                {
                    row[name] = DBNull.Value;
                    continue;
                }
                if (string.Equals(name, "CLOSED", StringComparison.OrdinalIgnoreCase) && closedCalcOrd >= 0
                    && !reader.IsDBNull(closedCalcOrd))
                    row[name] = NormalizeOracleValue(reader.GetValue(closedCalcOrd));
                else
                    row[name] = NormalizeOracleValue(reader.GetValue(oi));
            }
            table.Rows.Add(row);
        }

        if (table.Rows.Count == 0) return 0;

        using var bulk = new SqlBulkCopy(mssql, SqlBulkCopyOptions.KeepIdentity | SqlBulkCopyOptions.KeepNulls, null)
        {
            DestinationTableName = "izgazMGR.dbo.LS_INVOICE",
            BatchSize = 5000,
            BulkCopyTimeout = 600
        };
        foreach (DataColumn col in table.Columns)
            bulk.ColumnMappings.Add(col.ColumnName, col.ColumnName);
        await bulk.WriteToServerAsync(table, ct);
        _logger.LogInformation("Live materialize LS_INVOICE AGR={Agr} rows={N}", agr, table.Rows.Count);
        return table.Rows.Count;
    }

    private async Task<int> MaterializeLiveInvlinesAsync(
        OracleConnection ora, SqlConnection mssql, string sms, long agr, CancellationToken ct)
    {
        if (!await MssqlObjectExistsAsync(mssql, "izgazMGR.dbo.LS_INVLINES", ct))
            return 0;

        var msCols = await MssqlColumnsAsync(mssql, "izgazMGR.dbo.LS_INVLINES", ct);
        await using var cmd = ora.CreateCommand();
        cmd.BindByName = true;
        cmd.CommandTimeout = 600;
        cmd.CommandText = $@"
SELECT ai.ID AS LREF,
       aa.ID AS INVOICEREF,
       acc.REGISTER_ID AS CLIENTREF,
       CAST(aa.ACTION_DATE AS DATE) AS DATE_,
       CAST(0 AS NUMBER(3)) AS TYPE,
       CAST(ROW_NUMBER() OVER (PARTITION BY aa.ID ORDER BY ai.ID) AS NUMBER(5)) AS LINENR,
       CAST(ROUND(ai.AMOUNT * ai.STATUS, 3) AS NUMBER(18,3)) AS TLTOTAL,
       CAST(160 AS NUMBER(10)) AS CURID,
       CAST(1 AS NUMBER(18,6)) AS CURRATE,
       CAST(ROUND(ai.AMOUNT * ai.STATUS, 3) AS NUMBER(18,3)) AS CURTOTAL,
       CAST(NULL AS NUMBER(18,6)) AS FIRSTREAD,
       CAST(NULL AS NUMBER(18,6)) AS LASTREAD,
       CAST(0 AS NUMBER(10)) AS TRANSTYPE,
       CAST(0 AS NUMBER(1)) AS CANCELED,
       CAST(0 AS NUMBER(18,3)) AS TAX,
       CAST(ROUND(ai.AMOUNT * ai.STATUS, 3) AS NUMBER(18,3)) AS GRANDTOTAL,
       CAST(TO_CHAR(ai.INCOME_ID) AS VARCHAR2(300)) AS LINEEXP,
       CAST(0 AS NUMBER(10)) AS LINETYPE,
       CAST(0 AS NUMBER(18,3)) AS DV,
       CAST(NULL AS VARCHAR2(100)) AS FITNO,
       CAST(NULL AS NUMBER(10)) AS CNTREF,
       CAST(NULL AS NUMBER(10)) AS XTYPE,
       CAST(NULL AS NUMBER(18,6)) AS UNITPRICE,
       CAST(NULL AS NUMBER(10)) AS SPEREF,
       CAST(NULL AS NUMBER(18,6)) AS AMOUNT,
       ai.ID AS ABYS_ID,
       ai.ID AS ABYS_INCOME_ROW_ID,
       ai.INCOME_ID AS ABYS_INCOME_ID,
       aa.ID AS ABYS_ACTION_ID,
       acc.ID AS ABYS_ACCOUNT_ID,
       acc.REGISTER_ID AS ABYS_REGISTER_ID,
       acc.AGREEMENT_ID AS ABYS_AGREEMENT_ID,
       aa.ACTION_TYPE_ID AS ABYS_ACTION_TYPE_ID,
       acc.ACCRUE_TYPE_ID AS ABYS_ACCRUE_TYPE_ID,
       CAST(0 AS NUMBER(1)) AS ABYS_IS_DISCOUNT,
       CAST(0 AS NUMBER(1)) AS ABYS_IS_VAT_INCOME,
       CAST(0 AS NUMBER(1)) AS ABYS_IS_DEPOSIT,
       CAST(0 AS NUMBER(1)) AS ABYS_IS_OVERDUE_INCOME,
       CAST(0 AS NUMBER(1)) AS ABYS_IS_LEGAL_FEE,
       CAST(TO_CHAR(ai.INCOME_ID) AS VARCHAR2(100)) AS ABYS_INCOME_CODE,
       CAST(ai.AMOUNT AS NUMBER(18,3)) AS ABYS_AMOUNT_RAW,
       ai.STATUS AS ABYS_STATUS,
       CAST(NULL AS NUMBER(18,6)) AS ABYS_QUANTITY,
       CAST(NULL AS NUMBER(18,6)) AS ABYS_UNIT_PRICE
  FROM {sms}.CS_ACCOUNT_INCOME ai
  JOIN {sms}.CS_ACCOUNT_ACTION aa ON aa.ID = ai.ACCOUNT_ACTION_ID
  JOIN {sms}.CS_ACCOUNT acc ON acc.ID = aa.ACCOUNT_ID
 WHERE acc.AGREEMENT_ID = :agr
   AND aa.ACTION_TYPE_ID IN (1, 3, 10, 41)
   AND NVL(acc.ACCRUE_TYPE_ID, -1) <> 14
   AND aa.ID BETWEEN 1 AND 2147483647
   AND ai.ID BETWEEN 1 AND 2147483647";
        cmd.Parameters.Add("agr", agr);

        await using var reader = await cmd.ExecuteReaderAsync(ct);
        var table = new DataTable();
        var names = new List<string>();
        for (var i = 0; i < reader.FieldCount; i++)
        {
            var name = reader.GetName(i);
            if (!msCols.Contains(name, StringComparer.OrdinalIgnoreCase)) continue;
            if (table.Columns.Contains(name)) continue;
            names.Add(name);
            table.Columns.Add(name, typeof(object));
        }

        var ordMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < reader.FieldCount; i++)
            ordMap[reader.GetName(i)] = i;

        while (await reader.ReadAsync(ct))
        {
            var row = table.NewRow();
            foreach (var name in names)
            {
                if (!ordMap.TryGetValue(name, out var oi) || reader.IsDBNull(oi))
                    row[name] = DBNull.Value;
                else
                    row[name] = NormalizeOracleValue(reader.GetValue(oi));
            }
            table.Rows.Add(row);
        }

        if (table.Rows.Count == 0) return 0;

        using var bulk = new SqlBulkCopy(mssql, SqlBulkCopyOptions.KeepIdentity | SqlBulkCopyOptions.KeepNulls, null)
        {
            DestinationTableName = "izgazMGR.dbo.LS_INVLINES",
            BatchSize = 5000,
            BulkCopyTimeout = 600
        };
        foreach (DataColumn col in table.Columns)
            bulk.ColumnMappings.Add(col.ColumnName, col.ColumnName);
        await bulk.WriteToServerAsync(table, ct);
        _logger.LogInformation("Live materialize LS_INVLINES AGR={Agr} rows={N}", agr, table.Rows.Count);
        return table.Rows.Count;
    }

    private async Task<int> CopyOracleToMgrAsync(
        OracleConnection ora,
        SqlConnection mssql,
        string oracleTable,
        string mssqlThreePart,
        string agrColumn,
        long agr,
        CancellationToken ct)
    {
        if (!await OracleTableExistsAsync(ora, oracleTable, ct))
        {
            _logger.LogWarning("Oracle tablo yok: {Table}", oracleTable);
            return 0;
        }
        if (!await MssqlObjectExistsAsync(mssql, mssqlThreePart, ct))
        {
            _logger.LogWarning("MSSQL tablo yok: {Table}", mssqlThreePart);
            return 0;
        }

        var oraCols = await OracleColumnsAsync(ora, oracleTable, ct);
        var msCols = await MssqlColumnsAsync(mssql, mssqlThreePart, ct);
        var common = oraCols
            .Where(c => msCols.Contains(c, StringComparer.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (common.Count == 0)
            throw new InvalidOperationException($"{oracleTable} ↔ {mssqlThreePart}: ortak kolon yok.");

        var colList = string.Join(", ", common.Select(c => $"\"{c}\""));
        var sql = $"SELECT {colList} FROM {oracleTable} WHERE {agrColumn} = :agr";

        await using var cmd = ora.CreateCommand();
        cmd.BindByName = true;
        cmd.CommandText = sql;
        cmd.Parameters.Add("agr", agr);
        cmd.CommandTimeout = 600;

        await using var reader = await cmd.ExecuteReaderAsync(ct);
        var table = new DataTable();
        for (var i = 0; i < reader.FieldCount; i++)
            table.Columns.Add(common[i], typeof(object));

        while (await reader.ReadAsync(ct))
        {
            var row = table.NewRow();
            for (var i = 0; i < reader.FieldCount; i++)
                row[i] = reader.IsDBNull(i) ? DBNull.Value : NormalizeOracleValue(reader.GetValue(i));
            table.Rows.Add(row);
        }

        if (table.Rows.Count == 0) return 0;

        using var bulk = new SqlBulkCopy(mssql, SqlBulkCopyOptions.KeepIdentity | SqlBulkCopyOptions.KeepNulls, null)
        {
            DestinationTableName = mssqlThreePart,
            BatchSize = 5000,
            BulkCopyTimeout = 600
        };
        foreach (DataColumn col in table.Columns)
            bulk.ColumnMappings.Add(col.ColumnName, col.ColumnName);
        await bulk.WriteToServerAsync(table, ct);
        return table.Rows.Count;
    }

    /// <summary>
    /// CS_INSTALLMENT: AGREEMENT_ID = agr VEYA CS_ACCOUNT.INSTALLMENT_ID (AGR hesapları).
    /// </summary>
    private async Task<int> CopyCsInstallmentForAgrAsync(
        OracleConnection ora, SqlConnection mssql, string sms, long agr, CancellationToken ct)
    {
        var oraTable = $"{sms}.CS_INSTALLMENT";
        var dest = "izgazMGR.dbo.CS_INSTALLMENT";
        if (!await OracleTableExistsAsync(ora, oraTable, ct)) return 0;
        if (!await MssqlObjectExistsAsync(mssql, dest, ct)) return 0;

        var oraCols = await OracleColumnsAsync(ora, oraTable, ct);
        var msCols = await MssqlColumnsAsync(mssql, dest, ct);
        var common = oraCols
            .Where(c => msCols.Contains(c, StringComparer.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (common.Count == 0) return 0;

        var colList = string.Join(", ", common.Select(c => $"i.\"{c}\""));
        var hasAcc = await OracleTableExistsAsync(ora, $"{sms}.CS_ACCOUNT", ct);
        var sql = hasAcc
            ? $@"
SELECT {colList}
  FROM {sms}.CS_INSTALLMENT i
 WHERE i.AGREEMENT_ID = :agr
    OR i.ID IN (
         SELECT a.INSTALLMENT_ID FROM {sms}.CS_ACCOUNT a
          WHERE a.AGREEMENT_ID = :agr2 AND a.INSTALLMENT_ID IS NOT NULL
       )"
            : $@"SELECT {colList} FROM {sms}.CS_INSTALLMENT i WHERE i.AGREEMENT_ID = :agr";

        await using var cmd = ora.CreateCommand();
        cmd.BindByName = true;
        cmd.CommandText = sql;
        cmd.Parameters.Add("agr", agr);
        if (hasAcc) cmd.Parameters.Add("agr2", agr);
        cmd.CommandTimeout = 600;
        return await BulkOracleReaderToMgrAsync(cmd, mssql, dest, common, ct);
    }

    private async Task<int> CopyInstallmentPlanAsync(
        OracleConnection ora, SqlConnection mssql, string sms, long agr, CancellationToken ct)
    {
        var oraTable = $"{sms}.CS_INSTALLMENT_PLAN";
        var dest = "izgazMGR.dbo.CS_INSTALLMENT_PLAN";
        if (!await OracleTableExistsAsync(ora, oraTable, ct)) return 0;
        if (!await MssqlObjectExistsAsync(mssql, dest, ct)) return 0;

        var oraCols = await OracleColumnsAsync(ora, oraTable, ct);
        var msCols = await MssqlColumnsAsync(mssql, dest, ct);
        var common = oraCols
            .Where(c => msCols.Contains(c, StringComparer.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (common.Count == 0) return 0;

        var colList = string.Join(", ", common.Select(c => $"p.\"{c}\""));
        var hasAcc = await OracleTableExistsAsync(ora, $"{sms}.CS_ACCOUNT", ct);
        var sql = hasAcc
            ? $@"
SELECT {colList}
  FROM {sms}.CS_INSTALLMENT_PLAN p
 WHERE p.INSTALLMENT_ID IN (
       SELECT i.ID FROM {sms}.CS_INSTALLMENT i WHERE i.AGREEMENT_ID = :agr
       UNION
       SELECT a.INSTALLMENT_ID FROM {sms}.CS_ACCOUNT a
        WHERE a.AGREEMENT_ID = :agr2 AND a.INSTALLMENT_ID IS NOT NULL
 )"
            : $@"
SELECT {colList}
  FROM {sms}.CS_INSTALLMENT_PLAN p
 WHERE p.INSTALLMENT_ID IN (
       SELECT i.ID FROM {sms}.CS_INSTALLMENT i WHERE i.AGREEMENT_ID = :agr
 )";

        await using var cmd = ora.CreateCommand();
        cmd.BindByName = true;
        cmd.CommandText = sql;
        cmd.Parameters.Add("agr", agr);
        if (hasAcc) cmd.Parameters.Add("agr2", agr);
        cmd.CommandTimeout = 600;
        return await BulkOracleReaderToMgrAsync(cmd, mssql, dest, common, ct);
    }

    private static async Task<int> BulkOracleReaderToMgrAsync(
        OracleCommand cmd, SqlConnection mssql, string dest, List<string> common, CancellationToken ct)
    {
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        var table = new DataTable();
        for (var i = 0; i < reader.FieldCount; i++)
            table.Columns.Add(common[i], typeof(object));
        while (await reader.ReadAsync(ct))
        {
            var row = table.NewRow();
            for (var i = 0; i < reader.FieldCount; i++)
                row[i] = reader.IsDBNull(i) ? DBNull.Value : NormalizeOracleValue(reader.GetValue(i));
            table.Rows.Add(row);
        }
        if (table.Rows.Count == 0) return 0;

        using var bulk = new SqlBulkCopy(mssql, SqlBulkCopyOptions.KeepIdentity | SqlBulkCopyOptions.KeepNulls, null)
        {
            DestinationTableName = dest,
            BatchSize = 5000,
            BulkCopyTimeout = 600
        };
        foreach (DataColumn col in table.Columns)
            bulk.ColumnMappings.Add(col.ColumnName, col.ColumnName);
        await bulk.WriteToServerAsync(table, ct);
        return table.Rows.Count;
    }

    private static object NormalizeOracleValue(object value)
    {
        return value switch
        {
            decimal d when d == decimal.Truncate(d) && d >= int.MinValue && d <= int.MaxValue
                => Convert.ToInt32(d),
            decimal d when d == decimal.Truncate(d) && d >= long.MinValue && d <= long.MaxValue
                => Convert.ToInt64(d),
            _ => value
        };
    }

    private static async Task<long> OracleCountAsync(
        OracleConnection ora, string table, string col, long agr, CancellationToken ct)
    {
        if (!await OracleTableExistsAsync(ora, table, ct)) return 0;
        await using var cmd = ora.CreateCommand();
        cmd.BindByName = true;
        cmd.CommandText = $"SELECT COUNT(*) FROM {table} WHERE {col} = :agr";
        cmd.Parameters.Add("agr", agr);
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct) ?? 0);
    }

    private static async Task<long> OracleCountInstallmentPlanAsync(
        OracleConnection ora, string sms, long agr, CancellationToken ct)
    {
        if (!await OracleTableExistsAsync(ora, $"{sms}.CS_INSTALLMENT_PLAN", ct)) return 0;
        if (!await OracleTableExistsAsync(ora, $"{sms}.CS_INSTALLMENT", ct)) return 0;
        await using var cmd = ora.CreateCommand();
        cmd.BindByName = true;
        // AGR + hesap.INSTALLMENT_ID (AGREEMENT_ID boş header'lar dahil)
        cmd.CommandText = $@"
SELECT COUNT(*) FROM {sms}.CS_INSTALLMENT_PLAN p
 WHERE p.INSTALLMENT_ID IN (
       SELECT i.ID FROM {sms}.CS_INSTALLMENT i WHERE i.AGREEMENT_ID = :agr
       UNION
       SELECT a.INSTALLMENT_ID FROM {sms}.CS_ACCOUNT a
        WHERE a.AGREEMENT_ID = :agr2 AND a.INSTALLMENT_ID IS NOT NULL
 )";
        cmd.Parameters.Add("agr", agr);
        cmd.Parameters.Add("agr2", agr);
        try { return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct) ?? 0); }
        catch
        {
            cmd.Parameters.Clear();
            cmd.CommandText = $@"
SELECT COUNT(*) FROM {sms}.CS_INSTALLMENT_PLAN p
 WHERE p.INSTALLMENT_ID IN (SELECT i.ID FROM {sms}.CS_INSTALLMENT i WHERE i.AGREEMENT_ID = :agr)";
            cmd.Parameters.Add("agr", agr);
            return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct) ?? 0);
        }
    }

    private static async Task<long> MssqlCountAsync(
        SqlConnection conn, string threePart, string col, long agr, CancellationToken ct)
    {
        if (!await MssqlObjectExistsAsync(conn, threePart, ct)) return 0;
        await using var cmd = new SqlCommand($"SELECT COUNT_BIG(*) FROM {threePart} WITH (NOLOCK) WHERE {col} = @agr", conn);
        cmd.Parameters.AddWithValue("@agr", agr);
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct) ?? 0);
    }

    private static async Task<long> MssqlCountInstallmentPlanAsync(SqlConnection conn, long agr, CancellationToken ct)
    {
        if (!await MssqlObjectExistsAsync(conn, "izgazMGR.dbo.CS_INSTALLMENT_PLAN", ct)) return 0;
        if (!await MssqlObjectExistsAsync(conn, "izgazMGR.dbo.CS_INSTALLMENT", ct)) return 0;
        await using var cmd = new SqlCommand(@"
SELECT COUNT_BIG(*)
  FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN ip WITH (NOLOCK)
 INNER JOIN izgazMGR.dbo.CS_INSTALLMENT ins WITH (NOLOCK) ON ins.ID = ip.INSTALLMENT_ID
 WHERE ins.AGREEMENT_ID = @agr", conn);
        cmd.Parameters.AddWithValue("@agr", agr);
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct) ?? 0);
    }

    private static async Task<int> DeleteMgrAgrAsync(
        SqlConnection conn, string threePart, string col, long agr, CancellationToken ct)
    {
        if (!await MssqlObjectExistsAsync(conn, threePart, ct)) return 0;
        await using var cmd = new SqlCommand($"DELETE FROM {threePart} WHERE {col} = @agr", conn);
        cmd.Parameters.AddWithValue("@agr", agr);
        cmd.CommandTimeout = 300;
        return await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task<HashSet<long>> OracleInstallmentIdsForAgrAsync(
        OracleConnection ora, string sms, long agr, CancellationToken ct)
    {
        var ids = new HashSet<long>();
        if (!await OracleTableExistsAsync(ora, $"{sms}.CS_INSTALLMENT", ct)) return ids;
        await using var cmd = ora.CreateCommand();
        cmd.BindByName = true;
        cmd.CommandTimeout = 180;
        var hasAcc = await OracleTableExistsAsync(ora, $"{sms}.CS_ACCOUNT", ct);
        cmd.CommandText = hasAcc
            ? $@"
SELECT DISTINCT x.ID FROM (
  SELECT i.ID FROM {sms}.CS_INSTALLMENT i WHERE i.AGREEMENT_ID = :agr
  UNION ALL
  SELECT a.INSTALLMENT_ID FROM {sms}.CS_ACCOUNT a
   WHERE a.AGREEMENT_ID = :agr2 AND a.INSTALLMENT_ID IS NOT NULL
) x"
            : $"SELECT i.ID FROM {sms}.CS_INSTALLMENT i WHERE i.AGREEMENT_ID = :agr";
        cmd.Parameters.Add("agr", agr);
        if (hasAcc) cmd.Parameters.Add("agr2", agr);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
            if (!r.IsDBNull(0)) ids.Add(Convert.ToInt64(r.GetValue(0)));
        return ids;
    }

    private static async Task<int> DeleteMgrInstallmentAsync(
        SqlConnection mssql, OracleConnection ora, string sms, long agr, CancellationToken ct)
    {
        if (!await MssqlObjectExistsAsync(mssql, "izgazMGR.dbo.CS_INSTALLMENT", ct)) return 0;
        var ids = await OracleInstallmentIdsForAgrAsync(ora, sms, agr, ct);
        var n = 0;
        await using (var byAgr = new SqlCommand(
            "DELETE FROM izgazMGR.dbo.CS_INSTALLMENT WHERE AGREEMENT_ID = @agr", mssql))
        {
            byAgr.Parameters.AddWithValue("@agr", agr);
            byAgr.CommandTimeout = 300;
            n += await byAgr.ExecuteNonQueryAsync(ct);
        }
        foreach (var batch in ids.Chunk(200))
        {
            var list = string.Join(",", batch);
            await using var cmd = new SqlCommand(
                $"DELETE FROM izgazMGR.dbo.CS_INSTALLMENT WHERE ID IN ({list})", mssql)
            { CommandTimeout = 300 };
            n += await cmd.ExecuteNonQueryAsync(ct);
        }
        return n;
    }

    private static async Task<int> DeleteMgrInstallmentPlanAsync(
        SqlConnection mssql, OracleConnection ora, string sms, long agr, CancellationToken ct)
    {
        if (!await MssqlObjectExistsAsync(mssql, "izgazMGR.dbo.CS_INSTALLMENT_PLAN", ct)) return 0;
        var ids = await OracleInstallmentIdsForAgrAsync(ora, sms, agr, ct);
        var n = 0;
        if (await MssqlObjectExistsAsync(mssql, "izgazMGR.dbo.CS_INSTALLMENT", ct))
        {
            await using var byJoin = new SqlCommand(@"
DELETE ip FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN ip
 INNER JOIN izgazMGR.dbo.CS_INSTALLMENT ins ON ins.ID = ip.INSTALLMENT_ID
 WHERE ins.AGREEMENT_ID = @agr", mssql);
            byJoin.Parameters.AddWithValue("@agr", agr);
            byJoin.CommandTimeout = 300;
            n += await byJoin.ExecuteNonQueryAsync(ct);
        }
        foreach (var batch in ids.Chunk(200))
        {
            var list = string.Join(",", batch);
            await using var cmd = new SqlCommand(
                $"DELETE FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN WHERE INSTALLMENT_ID IN ({list})", mssql)
            { CommandTimeout = 300 };
            n += await cmd.ExecuteNonQueryAsync(ct);
        }
        return n;
    }

    private static async Task<bool> OracleTableExistsAsync(OracleConnection ora, string qualified, CancellationToken ct)
    {
        var parts = qualified.Split('.', 2);
        if (parts.Length != 2) return false;
        await using var cmd = ora.CreateCommand();
        cmd.BindByName = true;
        cmd.CommandText = @"
SELECT COUNT(*) FROM ALL_TABLES
 WHERE OWNER = :own AND TABLE_NAME = :tn";
        cmd.Parameters.Add("own", parts[0].ToUpperInvariant());
        cmd.Parameters.Add("tn", parts[1].ToUpperInvariant());
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct) ?? 0) > 0;
    }

    private static async Task<List<string>> OracleColumnsAsync(OracleConnection ora, string qualified, CancellationToken ct)
    {
        var parts = qualified.Split('.', 2);
        await using var cmd = ora.CreateCommand();
        cmd.BindByName = true;
        cmd.CommandText = @"
SELECT COLUMN_NAME FROM ALL_TAB_COLUMNS
 WHERE OWNER = :own AND TABLE_NAME = :tn
 ORDER BY COLUMN_ID";
        cmd.Parameters.Add("own", parts[0].ToUpperInvariant());
        cmd.Parameters.Add("tn", parts[1].ToUpperInvariant());
        var list = new List<string>();
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
            list.Add(r.GetString(0));
        return list;
    }

    private static async Task<HashSet<string>> MssqlColumnsAsync(SqlConnection conn, string threePart, CancellationToken ct)
    {
        // izgazMGR.dbo.LS_INVOICE
        var parts = threePart.Split('.');
        if (parts.Length != 3) return new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var db = parts[0].Trim('[', ']');
        var schema = parts[1].Trim('[', ']');
        var table = parts[2].Trim('[', ']');
        await using var cmd = new SqlCommand($@"
SELECT COLUMN_NAME
  FROM {db}.INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_SCHEMA = @schema AND TABLE_NAME = @table", conn);
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@table", table);
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
            set.Add(r.GetString(0));
        return set;
    }

    private static async Task<bool> MssqlObjectExistsAsync(SqlConnection conn, string threePart, CancellationToken ct)
    {
        await using var cmd = new SqlCommand(
            "SELECT CASE WHEN OBJECT_ID(@name, 'U') IS NULL THEN 0 ELSE 1 END", conn);
        cmd.Parameters.AddWithValue("@name", threePart);
        return Convert.ToInt32(await cmd.ExecuteScalarAsync(ct) ?? 0) == 1;
    }

    private static Dictionary<string, object?> Row(string layer, long src, long mgr, string note) =>
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["LAYER"] = layer,
            ["ORACLE"] = src,
            ["IZGAZMGR"] = mgr,
            ["DELTA"] = mgr - src,
            ["NOTE"] = note
        };

    private static string SanitizeIdent(string? value, string fallback)
    {
        var s = string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
        if (s.Any(c => !(char.IsLetterOrDigit(c) || c == '_')))
            throw new ArgumentException($"Geçersiz şema adı: {s}");
        return s;
    }

    private static TahsilatLogEvent MakeLog(
        string runId, long agr, string step, string side, string op, long ms, int rows, string outcome, string detail) =>
        new()
        {
            RunId = runId,
            AgrId = agr,
            Step = step,
            Side = side,
            Op = op,
            ElapsedMs = ms,
            RowCount = rows,
            Outcome = outcome,
            Detail = detail,
            AtUtc = DateTime.UtcNow
        };
}
