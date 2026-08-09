using MigrationWeb.Models.Staging;

namespace MigrationWeb.Services.Staging;

public sealed class AgreementTahsilatOrchestrator
{
    private readonly AgreementSmsReadService _sms;
    private readonly AgreementEnergyWriteService _energy;
    private readonly AgreementPilotMgrLoadService _pilotDump;
    private readonly AgreementTahsilatRunLog _runLog;
    private readonly AgreementPilotLogStore _logStore;
    private readonly ILogger<AgreementTahsilatOrchestrator> _logger;

    // In-memory close candidates per run (APPLY uses last closeCandidates load)
    private readonly Dictionary<string, List<Dictionary<string, object?>>> _closeByRun =
        new(StringComparer.OrdinalIgnoreCase);

    public AgreementTahsilatOrchestrator(
        AgreementSmsReadService sms,
        AgreementEnergyWriteService energy,
        AgreementPilotMgrLoadService pilotDump,
        AgreementTahsilatRunLog runLog,
        AgreementPilotLogStore logStore,
        ILogger<AgreementTahsilatOrchestrator> logger)
    {
        _sms = sms;
        _energy = energy;
        _pilotDump = pilotDump;
        _runLog = runLog;
        _logStore = logStore;
        _logger = logger;
    }

    public static IReadOnlyList<TahsilatStepDef> Catalog { get; } =
    [
        new()
        {
            Id = "connTest", Ordinal = 0, Title = "Bağlantı testi",
            Explanation = "SMS=Oracle ve ENERGY=MSSQL bağlantılarını sizin tanımladığınız değerlerle dener. Şifre loglanmaz."
        },
        new()
        {
            Id = "summary", Ordinal = 1, Title = "SMS özet",
            Explanation = "ACCRUE kırılımı: Tahakkuk Adet / Toplam / Ödenen / Borç (AMOUNT×STATUS). TOTAL_DEBT kullanılmaz."
        },
        new()
        {
            Id = "okumaBilgisi", Ordinal = 2, Title = "Okuma bilgisi durumu",
            Explanation = "Yalnız tüketim tahakkukları (ACCRUE_TYPE_ID 1,2,9,26,329): CS_READING.ACCOUNT_ID kontrol. Okuma varsa OK; yoksa OLUSTURULACAK."
        },
        new()
        {
            Id = "payments", Ordinal = 3, Title = "Makbuz / tahsilat (SMS)",
            Explanation = "LS_OV_PAY_PT varsa oradan; yoksa tip 3/7 action fallback + gap (Faz2 CTAS adayı)."
        },
        new()
        {
            Id = "alloc", Ordinal = 4, Title = "Alloc PAY→MAIN",
            Explanation = "LS_OV_PAY_ALLOC (O30) veya canlı INCOME_ID eşleme. T3: SUM(ALLOC)≤PAY_FULL soft gate."
        },
        new()
        {
            Id = "eslesme", Ordinal = 5, Title = "Tahakkuk ↔ Tahsilat eşleşme",
            Explanation = "Kritik omurga: MATCHED / TAHAKKUK_ONLY / TAHSILAT_ONLY. Açık borç = TAHAKKUK_ONLY MAIN_AMT (AMOUNT×STATUS). Tercihen O30 LS_OV_PAY_ALLOC."
        },
        new()
        {
            Id = "closeCandidates", Ordinal = 6, Title = "Kapama adayları (SMS O51)",
            Explanation = "FIX_KIND: AFL_OPEN = hesap BALANCE>0 (AMOUNT×STATUS); CLOSE_* ödenen. LS_STG_INV_PAY_CLOSE yoksa canlı O51 kaba."
        },
        new()
        {
            Id = "energyInvoices", Ordinal = 7, Title = "ENERGY faturalar (okuma)",
            Explanation = "OWNERREF=AGR ile LS_{nr}_{period}_INVOICE + borç PAYTRANS durumunu gösterir."
        },
        new()
        {
            Id = "applyClose", Ordinal = 8, Title = "Kapama DRY_RUN / APPLY", WritesEnergy = true,
            Explanation = "CLOSE_FULL/EPS adaylarında PAYTRANS.PAID=PAYABLETOTAL ve INVOICE.CLOSED+LASTPAIDDATE. Önce DryRun=true ile sayım; sonra Apply."
        },
        new()
        {
            Id = "pilotDumpMgr", Ordinal = 9, Title = "Pilot dump → izgazMGR", WritesEnergy = true,
            Explanation = "Pilot: izgazMGR DB + LS_INVOICE/INVLINES yoksa oluşturur; Oracle MIGRATION CTAS + SMS taksit yükler. Prod'da CTAS sonrası dump zaten vardır. DRY_RUN sayım; APPLY create+sil+yükle."
        },
        new()
        {
            Id = "pilotEnergyChain", Ordinal = 10, Title = "Pilot ENERGY zinciri", WritesEnergy = true,
            Explanation = "Tek AGR: izgazMGR→ENERGY. INVOICE(571)→INVLINES→PAYTRANS(575)→INSTALLMENT_PLAN(611)+WIRE. CleanBeforePilot=569. Dump adımından sonra."
        },
        new()
        {
            Id = "pilotFullChain", Ordinal = 11, Title = "Pilot tam zincir (dump+ENERGY)", WritesEnergy = true,
            Explanation = "Sırayla pilotDumpMgr + pilotEnergyChain. DRY_RUN her ikisini sayar; APPLY önce izgazMGR yükler sonra ENERGY yazar."
        },
        new()
        {
            Id = "mahsup", Ordinal = 12, Title = "Mahsup",
            Explanation = "tip6/24 + REF_DEPOSIT: emanet (iptal/ACCRUE14) başka fatura borcuna mahsup edilebilir (çoklu fatura). LS_OV_MAHSUP_SRC / live."
        },
        new()
        {
            Id = "taksit", Ordinal = 13, Title = "Taksit",
            Explanation = "SMS: INSTALLMENT_ID + CS_INSTALLMENT (açık+kapalı+iptal TÜM taksitler). ENERGY: INST_NR>0 veya EXPLAIN taksit. Durum: ACIK/KAPALI/IPTAL. Faz2 LS_TAKSIT."
        },
        new()
        {
            Id = "tamEksilten", Ordinal = 14, Title = "Tam eksilten",
            Explanation = "SMS: LS_OV_EKS_CLASS KIND=TAM (O20) veya live tip2. ENERGY: IADE / FICHENO I* / RETURN_* / EXPLAIN. Kıyas gap."
        },
        new()
        {
            Id = "kismiEksilten", Ordinal = 15, Title = "Kısmi eksilten",
            Explanation = "SMS: LS_OV_EKS_CLASS KIND=KISMI. ENERGY: EXPLAIN Kismi Eksilten. Kıyas gap → LS_PARTIAL_EKSILTEN Faz2."
        },
        new()
        {
            Id = "asimEksilten", Ordinal = 16, Title = "ASIM eksilten",
            Explanation = "EKS>TAH (LS_OV_EKS_SKIP / KIND=ASIM). Overlay skip — manuel gap."
        },
        new()
        {
            Id = "iptalEmanet", Ordinal = 17, Title = "İptal / Emanet / Eksilten-kapama",
            Explanation = "EMANET_GIRIS (tip20 güvence) | CANCEL_EMANET (tip12 çıkış) | EMANET_MAHSUP (tip6 REF_DEPOSIT→borç) | PAY_CANCEL | EKSILTEN_CLOSE."
        },
        new()
        {
            Id = "frk", Ordinal = 18, Title = "FRK / gap özeti",
            Explanation =
                "AFL = Açık Fatura Listesi. Ödenecek açık fatura varsa AFL ile adet+tutar eşleşmeli. " +
                "AFL vs ENERGY (ABYS_ACCOUNT_ID) → MATCH|AMT_DIFF|ONLY_AFL|ONLY_EN; harici (emanet) ayrı."
        }
    ];

    public async Task<TahsilatStepResult> RunStepAsync(string stepId, AgreementTahsilatRequest req, CancellationToken ct)
    {
        var runId = string.IsNullOrWhiteSpace(req.RunId) ? Guid.NewGuid().ToString("N")[..12] : req.RunId!;
        req.RunId = runId;
        var result = new TahsilatStepResult { StepId = stepId, RunId = runId, Ok = true };

        try
        {
            switch (stepId)
            {
                case "connTest":
                    await ConnTestAsync(req, result, ct);
                    break;
                case "summary":
                    await SummaryAsync(req, result, ct);
                    break;
                case "okumaBilgisi":
                    await OkumaBilgisiAsync(req, result, ct);
                    break;
                case "payments":
                    await PaymentsAsync(req, result, ct);
                    break;
                case "alloc":
                    await AllocAsync(req, result, ct);
                    break;
                case "eslesme":
                    await EslesmeAsync(req, result, ct);
                    break;
                case "closeCandidates":
                    await CloseCandidatesAsync(req, result, ct);
                    break;
                case "energyInvoices":
                    await EnergyInvoicesAsync(req, result, ct);
                    break;
                case "applyClose":
                    await ApplyCloseAsync(req, result, ct);
                    break;
                case "pilotDumpMgr":
                    await PilotDumpMgrAsync(req, result, ct);
                    break;
                case "pilotEnergyChain":
                    await PilotEnergyChainAsync(req, result, ct);
                    break;
                case "pilotFullChain":
                    await PilotFullChainAsync(req, result, ct);
                    break;
                case "mahsup":
                    await ScenarioCompareAsync(req, result, "mahsup", ct);
                    break;
                case "taksit":
                    await ScenarioCompareAsync(req, result, "taksit", ct);
                    break;
                case "tamEksilten":
                    await ScenarioCompareAsync(req, result, "tamEksilten", ct);
                    break;
                case "kismiEksilten":
                    await ScenarioCompareAsync(req, result, "kismiEksilten", ct);
                    break;
                case "asimEksilten":
                    await AsimAsync(req, result, ct);
                    break;
                case "iptalEmanet":
                    await IptalEmanetAsync(req, result, ct);
                    break;
                case "frk":
                    await FrkAsync(req, result, ct);
                    break;
                default:
                    result.Ok = false;
                    result.Message = $"Bilinmeyen adım: {stepId}";
                    break;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Tahsilat step {Step} failed Agr={Agr} Run={Run}", stepId, req.AgreementId, runId);
            result.Ok = false;
            result.Message = ex.Message;
            result.Logs.Add(new TahsilatLogEvent
            {
                RunId = runId,
                AgrId = req.AgreementId,
                Step = stepId,
                Side = "BOTH",
                Op = "INFO",
                Outcome = "FAIL",
                Detail = ex.Message
            });
            EmitLogs(result.Logs);
            PersistPilotLogs(result, req.AgreementId);
            return result;
        }

        EmitLogs(result.Logs);
        TrackGaps(result);
        PersistPilotLogs(result, req.AgreementId);
        if (string.IsNullOrEmpty(result.Message))
            result.Message = result.Ok ? "OK" : "FAIL";
        return result;
    }

    private void EmitLogs(IEnumerable<TahsilatLogEvent> logs)
    {
        foreach (var e in logs)
        {
            _runLog.Append(e.RunId, e);
            try { _logStore.AppendEvent(e); } catch (Exception ex) { _logger.LogWarning(ex, "Pilot log event yazılamadı"); }
            var line =
                $"TahsilatLog RunId={e.RunId} Agr={e.AgrId} Step={e.Step} Side={e.Side} Op={e.Op} " +
                $"Ms={e.ElapsedMs} Rows={e.RowCount} Outcome={e.Outcome} Detail={e.Detail}";
            if (e.Outcome is "FAIL" or "CRITICAL")
                _logger.LogError("{Line}", line);
            else if (e.Outcome is "WARN" or "SKIP")
                _logger.LogWarning("{Line}", line);
            else
                _logger.LogInformation("{Line}", line);
        }
    }

    private void TrackGaps(TahsilatStepResult result)
    {
        if (result.Gaps.Count > 0)
        {
            _runLog.AppendGaps(result.RunId, result.Gaps);
            try
            {
                var agr = result.Logs.FirstOrDefault()?.AgrId ?? 0;
                _logStore.AppendGaps(result.RunId, agr, result.Gaps);
            }
            catch (Exception ex) { _logger.LogWarning(ex, "Pilot gap log yazılamadı"); }
        }
    }

    private void PersistPilotLogs(TahsilatStepResult result, long agrId)
    {
        try
        {
            var dir = _logStore.PersistStep(result, agrId);
            result.Summary["pilotLogDir"] = dir;
            result.Summary["pilotLogShare"] = Path.Combine(dir, "SHARE.md");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Pilot step log persist failed Run={Run}", result.RunId);
        }
    }

    private async Task ConnTestAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.OracleConnectionString))
        {
            result.Ok = false;
            result.Message = "SMS Oracle bağlantısı gerekli.";
            return;
        }
        if (string.IsNullOrWhiteSpace(req.MssqlConnectionString))
        {
            result.Ok = false;
            result.Message = "ENERGY MSSQL bağlantısı gerekli.";
            return;
        }

        var (smsOk, smsMsg) = await _sms.TestAsync(req.OracleConnectionString, ct);
        result.Logs.Add(new TahsilatLogEvent
        {
            RunId = result.RunId, AgrId = req.AgreementId, Step = "connTest", Side = "SMS", Op = "TEST",
            Outcome = smsOk ? "OK" : "FAIL", Detail = smsMsg
        });

        var (enOk, enMsg) = await _energy.TestAsync(req.MssqlConnectionString, ct);
        result.Logs.Add(new TahsilatLogEvent
        {
            RunId = result.RunId, AgrId = req.AgreementId, Step = "connTest", Side = "ENERGY", Op = "TEST",
            Outcome = enOk ? "OK" : "FAIL", Detail = enMsg
        });

        result.Ok = smsOk && enOk;
        result.Message = $"{smsMsg} | {enMsg}";
        result.Summary["smsOk"] = smsOk;
        result.Summary["energyOk"] = enOk;
        result.Summary["tablePrefix"] = _energy.TablePrefix(req);
    }

    private async Task SummaryAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireOracle(req);
        RequireAgr(req);
        var (summary, rows, gaps, log) = await _sms.LoadSummaryAsync(req, result.RunId, ct);
        result.Summary = summary;
        result.Rows = rows;
        result.Gaps = gaps;
        result.Logs.Add(log);
        result.Ok = gaps.All(g => g.Severity != "CRITICAL");
        result.Message = result.Ok
            ? $"SMS özet OK — adet={summary.GetValueOrDefault("ACCOUNT_CNT")} borç={summary.GetValueOrDefault("TOPLAM_BORC")}"
            : "SMS özet CRITICAL gap";
    }

    private async Task OkumaBilgisiAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireOracle(req);
        RequireAgr(req);
        var (rows, gaps, log) = await _sms.LoadReadingStatusAsync(req, result.RunId, ct);
        result.Rows = rows;
        result.Gaps = gaps;
        result.Logs.Add(log);
        var okCnt = rows.Count(r => Convert.ToString(r.GetValueOrDefault("OKUMA_DURUMU")) == "OK");
        var createCnt = rows.Count(r => Convert.ToString(r.GetValueOrDefault("OKUMA_DURUMU")) == "OLUSTURULACAK");
        result.Summary["count"] = rows.Count;
        result.Summary["ok"] = okCnt;
        result.Summary["olusturulacak"] = createCnt;
        result.Summary["accrueFilter"] = "1,2,9,26,329";
        result.Ok = gaps.All(g => g.Severity != "CRITICAL");
        result.Message = result.Ok
            ? $"Tüketim okuma (ACCRUE 1/2/9/26/329): OK={okCnt} OLUSTURULACAK={createCnt}"
            : "Okuma bilgisi CRITICAL gap";
    }

    private async Task PaymentsAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireOracle(req);
        RequireAgr(req);
        var (rows, gaps, log) = await _sms.LoadPaymentsAsync(req, result.RunId, ct);
        result.Rows = rows;
        result.Gaps = gaps;
        result.Logs.Add(log);
        result.Summary["count"] = rows.Count;
        result.Message = $"{rows.Count} tahsilat satırı";
    }

    private async Task AllocAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireOracle(req);
        RequireAgr(req);
        var (rows, gaps, log) = await _sms.LoadAllocAsync(req, result.RunId, ct);
        result.Rows = rows;
        result.Gaps = gaps;
        result.Logs.Add(log);
        static decimal Db(Dictionary<string, object?> r, string key) =>
            Convert.ToDecimal(r.GetValueOrDefault(key) ?? 0m);
        var sumAlloc = rows.Sum(r => Db(r, "ALLOC_AMT"));
        var sumMain = rows.Sum(r => Db(r, "MAIN_PAYABLE") != 0m ? Db(r, "MAIN_PAYABLE") : Db(r, "MAIN_AMT"));
        var sumRaw = rows.Sum(r => Db(r, "RAW_ALLOC"));
        result.Summary["count"] = rows.Count;
        result.Summary["sumAlloc"] = sumAlloc;
        result.Summary["sumMainPayable"] = sumMain;
        result.Summary["sumRaw"] = sumRaw;
        result.Ok = gaps.All(g => g.Severity != "CRITICAL");
        result.Message = sumMain > 0
            ? $"{rows.Count} alloc | ΣALLOC≈{sumAlloc:0.##} | Σfatura(MAIN)≈{sumMain:0.##}"
            : $"{rows.Count} alloc satırı (ΣALLOC≈{sumAlloc:0.##})";
    }

    private async Task EslesmeAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireOracle(req);
        RequireAgr(req);
        var (rows, gaps, log) = await _sms.LoadEslesmeAsync(req, result.RunId, ct);
        result.Rows = rows;
        result.Gaps = gaps;
        result.Logs.Add(log);
        static decimal Db(Dictionary<string, object?> r, string key) =>
            Convert.ToDecimal(r.GetValueOrDefault(key) ?? 0m);
        var matched = rows.Count(r => Convert.ToString(r.GetValueOrDefault("MATCH_STATUS")) == "MATCHED");
        var tahOnly = rows.Count(r => Convert.ToString(r.GetValueOrDefault("MATCH_STATUS")) == "TAHAKKUK_ONLY");
        var tahsilOnly = rows.Count(r => Convert.ToString(r.GetValueOrDefault("MATCH_STATUS")) == "TAHSILAT_ONLY");
        var openUnmatched = rows
            .Where(r => Convert.ToString(r.GetValueOrDefault("MATCH_STATUS")) == "TAHAKKUK_ONLY")
            .Sum(r => Math.Max(0m, Db(r, "MAIN_AMT")));
        var matchedAlloc = rows
            .Where(r => Convert.ToString(r.GetValueOrDefault("MATCH_STATUS")) == "MATCHED")
            .Sum(r => Db(r, "ALLOC_AMT"));
        result.Summary["matched"] = matched;
        result.Summary["tahakkukOnly"] = tahOnly;
        result.Summary["tahsilatOnly"] = tahsilOnly;
        result.Summary["matchedAllocSum"] = matchedAlloc;
        result.Summary["tahakkukOnlyOpenSum"] = openUnmatched;
        result.Ok = gaps.All(g => g.Severity != "CRITICAL");
        result.Message =
            $"Eşleşme: MATCHED={matched} (alloc≈{matchedAlloc:0.##}) | TAHAKKUK_ONLY={tahOnly} (açık≈{openUnmatched:0.##}) | TAHSILAT_ONLY={tahsilOnly}";
    }

    private async Task AsimAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireOracle(req);
        RequireAgr(req);
        var (rows, gaps, log) = await _sms.LoadAsimEksiltenAsync(req, result.RunId, ct);
        result.Rows = rows;
        result.Gaps = gaps;
        result.Logs.Add(log);
        result.Summary["count"] = rows.Count;
        result.Message = rows.Count > 0 ? $"{rows.Count} ASIM (incele)" : "ASIM yok";
    }

    private async Task IptalEmanetAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireOracle(req);
        RequireAgr(req);
        var (rows, gaps, log) = await _sms.LoadIptalEmanetAsync(req, result.RunId, ct);
        result.Rows = rows;
        result.Gaps.AddRange(gaps);
        result.Logs.Add(log);

        static string KindOf(Dictionary<string, object?> r) =>
            Convert.ToString(r.GetValueOrDefault("KIND")) ?? "";
        var eksClose = rows.Count(r => KindOf(r) == "EKSILTEN_CLOSE");
        var payCancel = rows.Count(r => KindOf(r) == "PAY_CANCEL");
        var cancelEmanet = rows.Count(r => KindOf(r) == "CANCEL_EMANET");
        var emanetGiris = rows.Count(r => KindOf(r) == "EMANET_GIRIS");
        var emanetMahsup = rows.Count(r => KindOf(r) == "EMANET_MAHSUP");
        result.Summary["count"] = rows.Count;
        result.Summary["eksiltenClose"] = eksClose;
        result.Summary["payCancel"] = payCancel;
        result.Summary["cancelEmanet"] = cancelEmanet;
        result.Summary["emanetGiris"] = emanetGiris;
        result.Summary["emanetMahsup"] = emanetMahsup;

        if (!string.IsNullOrWhiteSpace(req.MssqlConnectionString))
        {
            try
            {
                var (enRows, gapsEn, logEn) = await _energy.LoadScenarioSpotAsync(req, result.RunId, "iptalEmanet", ct);
                result.EnergyRows = enRows;
                result.Gaps.AddRange(gapsEn);
                result.Logs.Add(logEn);
                result.Summary["energyCount"] = enRows.Count;
            }
            catch (Exception ex)
            {
                result.Gaps.Add(new TahsilatGapItem
                {
                    Code = "ENERGY_IPTAL_SPOT_FAIL",
                    Severity = "WARN",
                    Side = "ENERGY",
                    Message = $"ENERGY iptal/emanet spot: {ex.Message}"
                });
            }
        }

        result.Ok = result.Gaps.All(g => g.Severity != "CRITICAL");
        result.Message =
            $"EKSILTEN_CLOSE={eksClose} PAY_CANCEL={payCancel} EMANET_GIRIS={emanetGiris} CANCEL_EMANET={cancelEmanet} EMANET_MAHSUP={emanetMahsup}";
    }

    private async Task CloseCandidatesAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireOracle(req);
        RequireAgr(req);
        var (rows, gaps, log) = await _sms.LoadCloseCandidatesAsync(req, result.RunId, ct);
        result.Rows = rows;
        result.Gaps = gaps;
        result.Logs.Add(log);
        _closeByRun[result.RunId] = rows;
        result.Summary["count"] = rows.Count;
        result.Summary["closeFull"] = rows.Count(r => Convert.ToString(r.GetValueOrDefault("FIX_KIND")) == "CLOSE_FULL");
        result.Summary["closeEps"] = rows.Count(r => Convert.ToString(r.GetValueOrDefault("FIX_KIND")) == "CLOSE_EPS");
        result.Summary["aflOpen"] = rows.Count(r => Convert.ToString(r.GetValueOrDefault("FIX_KIND")) == "AFL_OPEN");
        result.Summary["keepOpen"] = rows.Count(r => Convert.ToString(r.GetValueOrDefault("FIX_KIND")) == "KEEP_OPEN");
        result.Summary["noPay"] = rows.Count(r => Convert.ToString(r.GetValueOrDefault("FIX_KIND")) == "NO_PAY");
        result.Ok = gaps.All(g => g.Severity != "CRITICAL");
        result.Message = result.Ok
            ? $"Aday: {rows.Count} (CLOSE cache RunId={result.RunId})"
            : "Kapama adayı okunamadı";
    }

    private async Task EnergyInvoicesAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireMssql(req);
        RequireAgr(req);
        var (rows, gaps, log) = await _energy.LoadInvoicesByOwnerAsync(req, result.RunId, ct);
        result.EnergyRows = rows;
        result.Gaps = gaps;
        result.Logs.Add(log);
        result.Summary["count"] = rows.Count;
        result.Summary["tablePrefix"] = _energy.TablePrefix(req);
        result.Ok = gaps.All(g => g.Severity != "CRITICAL");
        result.Message = $"{rows.Count} ENERGY fatura/PT";
    }

    private async Task ApplyCloseAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireOracle(req);
        RequireMssql(req);
        RequireAgr(req);

        // CRITICAL gap'ler yalnızca bilgi (store/log); APPLY kilidi yok.

        if (!_closeByRun.TryGetValue(result.RunId, out var candidates) || candidates.Count == 0)
        {
            var (rows, gapsLoad, logLoad) = await _sms.LoadCloseCandidatesAsync(req, result.RunId, ct);
            result.Logs.Add(logLoad);
            result.Gaps.AddRange(gapsLoad);
            candidates = rows;
            _closeByRun[result.RunId] = rows;
        }

        var (summary, preview, gaps, log) = await _energy.ApplyCloseAsync(req, result.RunId, candidates, ct);
        result.Summary = summary;
        result.EnergyRows = preview;
        result.Gaps.AddRange(gaps);
        result.Logs.Add(log);
        result.Ok = gaps.All(g => g.Severity != "CRITICAL") && log.Outcome is "OK" or "SKIP" or "WARN";
        result.Message = req.DryRun
            ? $"DRY_RUN: ptNeed={summary.GetValueOrDefault("ptNeedUpdate")} invNeed={summary.GetValueOrDefault("invNeedClosed")}"
            : $"APPLY: pt={summary.GetValueOrDefault("ptUpdated")} inv={summary.GetValueOrDefault("invUpdated")}";
    }

    private async Task PilotDumpMgrAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireOracle(req);
        RequireMssql(req);
        RequireAgr(req);

        var (summary, preview, gaps, log) =
            await _pilotDump.DumpAgrToMgrAsync(req, result.RunId, ct);
        result.Summary = summary;
        result.Rows = preview;
        result.Gaps.AddRange(gaps);
        result.Logs.Add(log);
        result.Ok = gaps.All(g => g.Severity != "CRITICAL") && log.Outcome is "OK" or "SKIP" or "WARN";
        result.Message = req.DryRun
            ? $"DRY_RUN dump AGR={req.AgreementId}: oraInv={summary.GetValueOrDefault("oraInvoice")} mgrInv={summary.GetValueOrDefault("mgrInvoiceBefore")} oraLines={summary.GetValueOrDefault("oraInvlines")} oraInst={summary.GetValueOrDefault("oraInstallment")}"
            : $"APPLY dump AGR={req.AgreementId}: insInv={summary.GetValueOrDefault("insertedInvoice")} lines={summary.GetValueOrDefault("insertedInvlines")} inst={summary.GetValueOrDefault("insertedInstallment")} plan={summary.GetValueOrDefault("insertedInstPlan")}";
    }

    private async Task PilotEnergyChainAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireMssql(req);
        RequireAgr(req);

        // CRITICAL gap'ler yalnızca bilgi (store/log); APPLY kilidi yok.

        var (summary, previewSms, previewEn, gaps, log) =
            await _energy.ApplyPilotEnergyChainAsync(req, result.RunId, ct);
        result.Summary = summary;
        result.Rows = previewSms;
        result.EnergyRows = previewEn;
        result.Gaps.AddRange(gaps);
        result.Logs.Add(log);
        result.Ok = gaps.All(g => g.Severity != "CRITICAL") && log.Outcome is "OK" or "SKIP" or "WARN";
        result.Message = req.DryRun
            ? $"DRY_RUN pilot AGR={req.AgreementId}: srcInv={summary.GetValueOrDefault("srcInvoice")} enInv={summary.GetValueOrDefault("enInvoice")} srcLines={summary.GetValueOrDefault("srcInvlines")} srcInst={summary.GetValueOrDefault("srcInstallment")}"
            : $"APPLY pilot AGR={req.AgreementId}: inv={summary.GetValueOrDefault("invoiceOutcome")} lines={summary.GetValueOrDefault("invlinesInserted")} pt={summary.GetValueOrDefault("paytransOutcome")} inst={summary.GetValueOrDefault("installmentOutcome")} taksitPt={summary.GetValueOrDefault("taksitPtInserted")} split={summary.GetValueOrDefault("taksitSplitOutcome")}";
    }

    private async Task PilotFullChainAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireOracle(req);
        RequireMssql(req);
        RequireAgr(req);

        var dumpResult = new TahsilatStepResult { StepId = "pilotDumpMgr", RunId = result.RunId, Ok = true };
        await PilotDumpMgrAsync(req, dumpResult, ct);
        result.Logs.AddRange(dumpResult.Logs);
        result.Gaps.AddRange(dumpResult.Gaps);
        foreach (var kv in dumpResult.Summary)
            result.Summary[$"dump_{kv.Key}"] = kv.Value;
        result.Rows = dumpResult.Rows;

        if (!dumpResult.Ok)
        {
            result.Ok = false;
            result.Message = $"Tam zincir durdu (dump): {dumpResult.Message}";
            return;
        }

        // Dump CRITICAL (ör. NO_CTAS) APPLY kilidine girmesin diye dump-only kodları ignore listesinde değil;
        // ENERGY'ye geçmeden önce dump OK olmalı — yukarıda return.
        // Dump WARN'ları ENERGY APPLY'ı kilitlemesin: FRK dışı dump kodlarını apply ignore'a alma;
        // buraya geldiysek dump OK.

        var energyResult = new TahsilatStepResult { StepId = "pilotEnergyChain", RunId = result.RunId, Ok = true };
        await PilotEnergyChainAsync(req, energyResult, ct);
        result.Logs.AddRange(energyResult.Logs);
        result.Gaps.AddRange(energyResult.Gaps);
        foreach (var kv in energyResult.Summary)
            result.Summary[$"energy_{kv.Key}"] = kv.Value;
        result.EnergyRows = energyResult.EnergyRows;
        if (energyResult.Rows.Count > 0)
            result.Rows = energyResult.Rows;

        result.Ok = dumpResult.Ok && energyResult.Ok;
        result.Message = req.DryRun
            ? $"DRY_RUN tam zincir AGR={req.AgreementId}: dump OK → energy {energyResult.Message}"
            : $"APPLY tam zincir AGR={req.AgreementId}: dump OK → energy {energyResult.Message}";
        result.Summary["dumpOk"] = dumpResult.Ok;
        result.Summary["energyOk"] = energyResult.Ok;
    }

    private async Task ScenarioCompareAsync(
        AgreementTahsilatRequest req, TahsilatStepResult result, string scenario, CancellationToken ct)
    {
        RequireOracle(req);
        RequireMssql(req);
        RequireAgr(req);

        List<Dictionary<string, object?>> smsRows;
        List<TahsilatGapItem> gapsSms;
        TahsilatLogEvent logSms;

        switch (scenario)
        {
            case "mahsup":
                (smsRows, gapsSms, logSms) = await _sms.LoadMahsupAsync(req, result.RunId, ct);
                break;
            case "taksit":
                (smsRows, gapsSms, logSms) = await _sms.LoadTaksitAsync(req, result.RunId, ct);
                break;
            case "tamEksilten":
                (smsRows, gapsSms, logSms) = await _sms.LoadEksiltenAsync(req, result.RunId, "TAM", ct);
                break;
            case "kismiEksilten":
                (smsRows, gapsSms, logSms) = await _sms.LoadEksiltenAsync(req, result.RunId, "KISMI", ct);
                break;
            default:
                throw new ArgumentException(scenario);
        }

        result.Rows = smsRows;
        result.Gaps.AddRange(gapsSms);
        result.Logs.Add(logSms);

        var (enRows, gapsEn, logEn) = await _energy.LoadScenarioSpotAsync(req, result.RunId, scenario, ct);
        result.EnergyRows = enRows;
        result.Gaps.AddRange(gapsEn);
        result.Logs.Add(logEn);

        var smsCnt = smsRows.Count;
        var enCnt = enRows.Count;
        result.Summary["smsCount"] = smsCnt;
        result.Summary["energyCount"] = enCnt;
        result.Summary["delta"] = enCnt - smsCnt;
        result.Summary["scenario"] = scenario;

        // Taksit için özel özet istatistikleri
        if (scenario == "taksit")
        {
            static string DurumOf(Dictionary<string, object?> r, string key) =>
                Convert.ToString(r.GetValueOrDefault(key)) ?? "";

            var smsAcik = smsRows.Count(r => DurumOf(r, "TAKSIT_DURUMU") == "ACIK");
            var smsKapali = smsRows.Count(r => DurumOf(r, "TAKSIT_DURUMU") == "KAPALI");
            var smsIptal = smsRows.Count(r => DurumOf(r, "TAKSIT_DURUMU") == "IPTAL");
            var smsFazla = smsRows.Count(r => DurumOf(r, "TAKSIT_DURUMU") == "FAZLA_ODEME");

            var enAcik = enRows.Count(r => DurumOf(r, "EN_TAKSIT_DURUMU") == "ACIK");
            var enKapali = enRows.Count(r => DurumOf(r, "EN_TAKSIT_DURUMU") == "KAPALI");
            var enIptal = enRows.Count(r => DurumOf(r, "EN_TAKSIT_DURUMU") == "IPTAL");
            var enKismi = enRows.Count(r => DurumOf(r, "EN_TAKSIT_DURUMU") == "KISMI_ODEME");

            result.Summary["smsAcik"] = smsAcik;
            result.Summary["smsKapali"] = smsKapali;
            result.Summary["smsIptal"] = smsIptal;
            result.Summary["smsFazla"] = smsFazla;
            result.Summary["enAcik"] = enAcik;
            result.Summary["enKapali"] = enKapali;
            result.Summary["enIptal"] = enIptal;
            result.Summary["enKismi"] = enKismi;

            result.Gaps.Add(new TahsilatGapItem
            {
                Code = "TAKSIT_DURUM_SUMMARY",
                Severity = "INFO",
                Side = "BOTH",
                Message = $"SMS: ACIK={smsAcik} KAPALI={smsKapali} IPTAL={smsIptal} FAZLA={smsFazla} | " +
                          $"ENERGY: ACIK={enAcik} KAPALI={enKapali} IPTAL={enIptal} KISMI={enKismi}"
            });

            // Durum uyuşmazlık kontrolü
            if (smsAcik > 0 && enAcik == 0)
            {
                result.Gaps.Add(new TahsilatGapItem
                {
                    Code = "TAKSIT_ACIK_MISMATCH",
                    Severity = "WARN",
                    Side = "BOTH",
                    Message = $"SMS'te {smsAcik} açık taksit var ama ENERGY'de tespit edilemedi - INST_NR/EXPLAIN kontrolü gerekli."
                });
            }

            if (smsIptal > 0 && enIptal == 0)
            {
                result.Gaps.Add(new TahsilatGapItem
                {
                    Code = "TAKSIT_IPTAL_MISMATCH",
                    Severity = "WARN",
                    Side = "BOTH",
                    Message = $"SMS'te {smsIptal} iptal taksit var ama ENERGY'de CANCELED=1 tespit edilemedi."
                });
            }

            if (smsKapali > 0 && enKapali == 0 && enCnt > 0)
            {
                result.Gaps.Add(new TahsilatGapItem
                {
                    Code = "TAKSIT_KAPALI_MISMATCH",
                    Severity = "INFO",
                    Side = "BOTH",
                    Message = $"SMS'te {smsKapali} kapalı taksit var ama ENERGY'de CLOSED=1 tespit edilemedi."
                });
            }
        }

        var outcome = "OK";
        if (smsCnt > 0 && enCnt == 0)
        {
            outcome = "WARN";
            result.Gaps.Add(new TahsilatGapItem
            {
                Code = $"{scenario.ToUpperInvariant()}_SMS_ONLY",
                Severity = "WARN",
                Side = "BOTH",
                Message = $"SMS'te {smsCnt} {scenario} var, ENERGY spot'ta 0 — aktarım/CTAS eksik olabilir."
            });
        }
        else if (smsCnt == 0 && enCnt > 0)
        {
            outcome = "WARN";
            result.Gaps.Add(new TahsilatGapItem
            {
                Code = $"{scenario.ToUpperInvariant()}_ENERGY_ONLY",
                Severity = "WARN",
                Side = "BOTH",
                Message = $"ENERGY'de {enCnt} {scenario} izi var, SMS sınıflamada 0 — eşleme/filtre kontrol."
            });
        }

        result.Logs.Add(new TahsilatLogEvent
        {
            RunId = result.RunId,
            AgrId = req.AgreementId,
            Step = scenario,
            Side = "BOTH",
            Op = "COMPARE",
            RowCount = Math.Abs(enCnt - smsCnt),
            Outcome = outcome,
            Detail = $"sms={smsCnt} energy={enCnt} delta={enCnt - smsCnt}"
        });

        result.Message = $"{scenario}: SMS={smsCnt} ENERGY={enCnt}";
        result.Ok = result.Gaps.All(g => g.Severity != "CRITICAL");
    }

    private async Task FrkAsync(AgreementTahsilatRequest req, TahsilatStepResult result, CancellationToken ct)
    {
        RequireOracle(req);
        RequireMssql(req);
        RequireAgr(req);

        const decimal eps = 0.02m;

        var (afl, gapsAfl, logAfl) = await _sms.LoadAflAsync(req, result.RunId, ct);
        result.Logs.Add(logAfl);
        result.Gaps.AddRange(gapsAfl);

        var (smsLive, gapsLive, logLive) = await _sms.LoadSmsOpenDebtAsync(req, result.RunId, ct);
        result.Logs.Add(logLive);
        result.Gaps.AddRange(gapsLive);

        var (enOpen, gapsEn, logEn) = await _energy.LoadOpenDebtByAccountAsync(req, result.RunId, ct);
        result.Logs.Add(logEn);
        result.Gaps.AddRange(gapsEn);
        result.EnergyRows = enOpen;

        static long Fid(Dictionary<string, object?> r)
        {
            var v = r.GetValueOrDefault("FATURAID");
            return v == null ? 0L : Convert.ToInt64(Convert.ToDecimal(v));
        }
        static decimal Bal(Dictionary<string, object?> r, string key)
        {
            var v = r.GetValueOrDefault(key);
            return v == null ? 0m : Convert.ToDecimal(v);
        }
        static int MigScope(Dictionary<string, object?> r)
        {
            var v = r.GetValueOrDefault("MIG_IN_SCOPE");
            return v == null ? 1 : Convert.ToInt32(Convert.ToDecimal(v));
        }

        // --- 1) SMS canlı açık ↔ AFL: ödenmemiş/BALANCE mutlaka AFL’de ve tutar eşit ---
        var aflById = afl.Where(r => Fid(r) > 0).GroupBy(Fid).ToDictionary(g => g.Key, g => g.First());
        var smsById = smsLive.Where(r => Fid(r) > 0).GroupBy(Fid).ToDictionary(g => g.Key, g => g.First());
        var aflFromTable = gapsAfl.All(g => g.Code != "NO_LS_AFL_OPEN_DEBT");

        var missingSamples = new List<string>();
        var smsAflDiffSamples = new List<string>();
        var missingInAfl = 0;
        var smsAflAmtDiff = 0;
        if (aflFromTable)
        {
            foreach (var (fid, smsRow) in smsById)
            {
                var smsBal = Bal(smsRow, "BALANCE");
                if (smsBal <= eps) continue;
                if (!aflById.TryGetValue(fid, out var aflRow))
                {
                    missingInAfl++;
                    if (missingSamples.Count < 5)
                        missingSamples.Add($"{fid}:{smsBal:0.##}");
                }
                else
                {
                    var aflBal = Bal(aflRow, "BALANCE");
                    if (Math.Abs(aflBal - smsBal) > eps)
                    {
                        smsAflAmtDiff++;
                        if (smsAflDiffSamples.Count < 5)
                            smsAflDiffSamples.Add($"{fid} SMS={smsBal:0.##}/AFL={aflBal:0.##}");
                    }
                }
            }
        }

        if (missingInAfl > 0)
            result.Gaps.Add(new TahsilatGapItem
            {
                Code = "SMS_OPEN_NOT_IN_AFL",
                Severity = "WARN",
                Side = "SMS",
                Message = $"{missingInAfl} ödenmemiş/BALANCE canlı SMS’te var, AFL CTAS’ta yok (ör. {string.Join(", ", missingSamples)}). AFL dump güncellemesi; ENERGY↔AFL eşleşmesini engellemez."
            });
        if (smsAflAmtDiff > 0)
            result.Gaps.Add(new TahsilatGapItem
            {
                Code = "SMS_AFL_AMT_DIFF",
                Severity = "WARN",
                Side = "SMS",
                Message = $"{smsAflAmtDiff} satırda SMS≠AFL tutar (ör. {string.Join("; ", smsAflDiffSamples)})."
            });

        // --- 2) AFL (mig scope) ↔ ENERGY açık (ABYS_ACCOUNT_ID) — 91 FRK grain ---
        var aflMig = afl.Where(r => Fid(r) > 0 && MigScope(r) == 1).GroupBy(Fid).ToDictionary(g => g.Key, g => g.First());
        var aflOther = afl.Where(r => Fid(r) > 0 && MigScope(r) != 1).ToList();
        var enById = enOpen.Where(r => Fid(r) > 0).GroupBy(Fid).ToDictionary(g => g.Key, g => g.First());

        var allIds = aflMig.Keys.Union(enById.Keys).OrderBy(x => x).ToList();
        var compare = new List<Dictionary<string, object?>>();
        var match = 0;
        var amtDiff = 0;
        var onlyAfl = 0;
        var onlyEn = 0;
        var onlyEnBal = 0;
        decimal onlyEnSum = 0m, onlyAflSum = 0m, amtDiffAbs = 0m;
        var onlyEnSamples = new List<string>();
        var onlyAflSamples = new List<string>();
        var amtDiffSamples = new List<string>();

        foreach (var fid in allIds)
        {
            aflMig.TryGetValue(fid, out var a);
            enById.TryGetValue(fid, out var e);
            var aflBal = a == null ? (decimal?)null : Bal(a, "BALANCE");
            var enBal = e == null ? (decimal?)null : Bal(e, "EN_BAL");
            var delta = (enBal ?? 0m) - (aflBal ?? 0m);
            string kind;
            string? note;
            if (a == null)
            {
                kind = "ONLY_EN";
                onlyEn++;
                if ((enBal ?? 0m) > eps) { onlyEnBal++; onlyEnSum += enBal ?? 0m; }
                note = (enBal ?? 0m) > eps
                    ? "ENERGY açık, AFL yok — AFL’de olmalı"
                    : "ENERGY CLOSED=0/kalan≈0, AFL yok";
                if (onlyEnSamples.Count < 5)
                    onlyEnSamples.Add($"{fid}:{enBal:0.##}");
            }
            else if (e == null)
            {
                kind = "ONLY_AFL";
                onlyAfl++;
                onlyAflSum += aflBal ?? 0m;
                note = "AFL açık, ENERGY kalan yok/0 — kapama veya dump kontrol";
                if (onlyAflSamples.Count < 5)
                    onlyAflSamples.Add($"{fid}:{aflBal:0.##}");
            }
            else if (Math.Abs(delta) <= eps)
            {
                kind = "MATCH";
                match++;
                note = null;
            }
            else
            {
                kind = "AMT_DIFF";
                amtDiff++;
                amtDiffAbs += Math.Abs(delta);
                note = "Bakiye farkı";
                if (amtDiffSamples.Count < 5)
                    amtDiffSamples.Add($"{fid} Δ={delta:0.##}");
            }

            compare.Add(new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase)
            {
                ["FATURAID"] = fid,
                ["SOZLESME"] = req.AgreementId,
                ["AFL_BAL"] = aflBal,
                ["EN_BAL"] = enBal,
                ["DELTA"] = Math.Round(delta, 2),
                ["KIND"] = kind,
                ["TAKSIT"] = a?.GetValueOrDefault("TAKSIT_DURUMU"),
                ["YT"] = a?.GetValueOrDefault("YT_DURUMU"),
                ["MIG_IN_SCOPE"] = a == null ? null : MigScope(a),
                ["OPEN_INV_CNT"] = e?.GetValueOrDefault("OPEN_INV_CNT"),
                ["NOTE"] = note
            });
        }

        if (onlyEnBal > 0)
            result.Gaps.Add(new TahsilatGapItem
            {
                Code = "FRK_ONLY_EN",
                Severity = "CRITICAL",
                Side = "BOTH",
                Message = $"{onlyEnBal} ENERGY açık (Σ≈{onlyEnSum:0.##}) AFL’de yok — ödenmemiş AFL’de olmalı (ör. {string.Join(", ", onlyEnSamples)})."
            });
        else if (onlyEn > 0)
            result.Gaps.Add(new TahsilatGapItem
            {
                Code = "FRK_EN_CLOSED0_NO_AFL",
                Severity = "WARN",
                Side = "BOTH",
                Message = $"{onlyEn} ENERGY CLOSED=0/kalan≈0, AFL yok (ör. {string.Join(", ", onlyEnSamples)})."
            });
        if (onlyAfl > 0)
            result.Gaps.Add(new TahsilatGapItem
            {
                Code = "FRK_ONLY_AFL",
                Severity = "WARN",
                Side = "BOTH",
                Message = $"{onlyAfl} AFL açık (Σ≈{onlyAflSum:0.##}) ENERGY’de kalan yok (ör. {string.Join(", ", onlyAflSamples)})."
            });
        if (amtDiff > 0)
            result.Gaps.Add(new TahsilatGapItem
            {
                Code = "FRK_AMT_DIFF",
                Severity = "WARN",
                Side = "BOTH",
                Message = $"{amtDiff} tutar farkı |ΣΔ|≈{amtDiffAbs:0.##} (ör. {string.Join("; ", amtDiffSamples)})."
            });

        // Harici açık (emanet / MIG_IN_SCOPE=0)
        foreach (var o in aflOther)
        {
            var fid = Fid(o);
            var bal = Bal(o, "BALANCE");
            compare.Add(new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase)
            {
                ["FATURAID"] = fid,
                ["SOZLESME"] = req.AgreementId,
                ["AFL_BAL"] = bal,
                ["EN_BAL"] = enById.TryGetValue(fid, out var e) ? Bal(e, "EN_BAL") : null,
                ["DELTA"] = null,
                ["KIND"] = "HARICI_ACIK",
                ["TAKSIT"] = o.GetValueOrDefault("TAKSIT_DURUMU"),
                ["YT"] = o.GetValueOrDefault("YT_DURUMU"),
                ["MIG_IN_SCOPE"] = 0,
                ["ACCRUE_TYPE_ID"] = o.GetValueOrDefault("ACCRUE_TYPE_ID"),
                ["NOTE"] = "Emanet/kapsam dışı açık borç — ayrı kontrol"
            });
        }
        if (aflOther.Count > 0)
            result.Gaps.Add(new TahsilatGapItem
            {
                Code = "FRK_HARICI_ACIK",
                Severity = "INFO",
                Side = "SMS",
                Message = $"{aflOther.Count} harici açık (MIG_IN_SCOPE=0 / emanet) — tutar≈{aflOther.Sum(r => Bal(r, "BALANCE")):0.##}."
            });

        if (match > 0 && onlyEn + onlyAfl + amtDiff + missingInAfl == 0 && aflOther.Count == 0)
            result.Gaps.Add(new TahsilatGapItem
            {
                Code = "FRK_ALL_MATCH",
                Severity = "INFO",
                Side = "BOTH",
                Message = $"Tüm mig-scope açık borçlar eşleşti (MATCH={match})."
            });

        result.Rows = compare
            .OrderBy(r => Convert.ToString(r["KIND"]) == "MATCH" ? 1 : 0)
            .ThenByDescending(r => Math.Abs(Bal(r, "DELTA")))
            .ThenBy(r => Fid(r))
            .ToList();

        result.Summary["smsLiveOpen"] = smsLive.Count;
        result.Summary["aflOpen"] = afl.Count;
        result.Summary["aflMigOpen"] = aflMig.Count;
        result.Summary["energyOpen"] = enOpen.Count;
        result.Summary["match"] = match;
        result.Summary["amtDiff"] = amtDiff;
        result.Summary["onlyAfl"] = onlyAfl;
        result.Summary["onlyEn"] = onlyEn;
        result.Summary["hariciAcik"] = aflOther.Count;
        result.Summary["smsOpenNotInAfl"] = missingInAfl;
        result.Summary["smsAflAmtDiff"] = smsAflAmtDiff;
        result.Summary["deltaOpen"] = enOpen.Count - aflMig.Count;
        var cntMatch = aflMig.Count == enById.Count;
        var frkOk = match > 0 && amtDiff == 0 && onlyAfl == 0 && onlyEn == 0 && missingInAfl == 0 && smsAflAmtDiff == 0
                    && cntMatch;
        result.Summary["aflCntMatch"] = cntMatch ? 1 : 0;
        result.Summary["frkCorrect"] = frkOk ? 1 : 0;

        if (frkOk)
        {
            result.Gaps.Add(new TahsilatGapItem
            {
                Code = "FRK_AFL_OK",
                Severity = "INFO",
                Side = "BOTH",
                Message =
                    $"AFL (açık fatura listesi) doğru: adet={aflMig.Count} MATCH={match} (ENERGY açık ile tutar+adet eşleşti)."
            });
        }
        else if (aflMig.Count == 0 && enById.Count == 0)
        {
            result.Gaps.Add(new TahsilatGapItem
            {
                Code = "FRK_NO_OPEN",
                Severity = "INFO",
                Side = "BOTH",
                Message = "AFL ve ENERGY’de açık fatura yok — ödenecek açık yok (liste boş, tutarlı)."
            });
        }

        result.Logs.Add(new TahsilatLogEvent
        {
            RunId = result.RunId,
            AgrId = req.AgreementId,
            Step = "frk",
            Side = "BOTH",
            Op = "COMPARE",
            RowCount = compare.Count,
            Outcome = onlyEnBal > 0 ? "WARN" : (amtDiff + onlyAfl + missingInAfl > 0 ? "WARN" : "OK"),
            Detail =
                $"AFL=açık fatura listesi CNT_AFL={aflMig.Count} CNT_EN={enById.Count} " +
                $"MATCH={match} AMT_DIFF={amtDiff} ONLY_AFL={onlyAfl} ONLY_EN={onlyEn} HARICI={aflOther.Count} SMS∉AFL={missingInAfl}" +
                (frkOk ? " | DOĞRU" : "")
        });

        // Bu FRK turunda CRITICAL yoksa eski FRK_ONLY_EN / SMS_OPEN kilidini temizle
        if (onlyEnBal == 0)
            _runLog.RemoveGapsByCodes(result.RunId, "FRK_ONLY_EN", "SMS_OPEN_NOT_IN_AFL");

        result.Ok = result.Gaps.All(g => g.Severity != "CRITICAL");
        result.Message = frkOk
            ? $"FRK DOĞRU — AFL açık fatura listesi adet={aflMig.Count} tutar MATCH={match}"
            : $"FRK MATCH={match} AMT_DIFF={amtDiff} ONLY_AFL={onlyAfl} ONLY_EN={onlyEn} | AFL_CNT={aflMig.Count} EN_CNT={enById.Count} SMS∉AFL={missingInAfl} harici={aflOther.Count}";
    }

    private static void RequireOracle(AgreementTahsilatRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.OracleConnectionString))
            throw new InvalidOperationException("SMS Oracle bağlantısı gerekli.");
    }

    private static void RequireMssql(AgreementTahsilatRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.MssqlConnectionString))
            throw new InvalidOperationException("ENERGY MSSQL bağlantısı gerekli.");
    }

    private static void RequireAgr(AgreementTahsilatRequest req)
    {
        if (req.AgreementId <= 0)
            throw new InvalidOperationException("Geçerli AGREEMENT_ID gerekli.");
    }
}
