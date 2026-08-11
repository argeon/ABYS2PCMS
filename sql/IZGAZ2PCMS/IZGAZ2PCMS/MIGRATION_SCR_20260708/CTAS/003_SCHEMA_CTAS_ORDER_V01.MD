# ORACLE CTAS — Çalışma Sırası

**Klasör:** `oracleCTAS3007/` · Okuma/RMS: `oracleCTAS/`  
**Tam koşu:** `@00_run_all.sql` (Faz A master + okuma + tahsilat) · Dump: `DUMP_MANIFEST.txt`  
★ = hard gate (FAIL → DUR) · ★★ = 3007 pilot adımı

| # | Dosya Adı | Oluşacak Tablo | Amacı | Beklenen Sonuç |
|---|-----------|----------------|--------|----------------|
| 1 | `LS_FLAT.sql` | `LS_FLAT` | SMS bina/daire/kapı + abone + tesisat + servis kutusu bilgisini Energy `LS_FLAT` şemasına taşımak; sözleşme/FLATID wire’ın fiziksel anahtarı | Kaynak `GIS_BUILDING_FLAT` ile satır sayısı yakın; `ABYS_INSTALLATION_ID` dolu satırlar Energy migrate filtresine uygun; index/stats tamam |
| 2 | `LS_ITEMS.sql` | `LS_ITEMS` | Sayaç envanterini (meter, model, marka, ambar, kalibrasyon, son endeks) staging’e almak; Energy `LS_005_ITEMS` (240/241) kaynağı | `LREF/METER_ID = CS_METER.ID`; PRODDATE/LASTENDEX mantıklı; dump sonrası Identity ile aynı anahtar korunur |
| 3 | `LS_REGISTER.sql` | `LS_REGISTER` | Abone/firma sicillerini taşımak; Energy `LS_005_SUBSCR` / `LS_005_FIRM` kaynağı | `CNT = CS_REGISTER`; `ABYS_ID = ID`; LOGO BLOB alınmaz (bilinçli); silinen/kayıp bayraklar korunur |
| 4 | `LS_IT_USER.sql` | `LS_IT_USER` | SMS kullanıcılarını (`IT_USER`) staging’e almak; Energy `LS_USER` (110/111) kaynağı | `CNT = IT_USER`; `ABYS_ID = ID`; PICTURE BLOB alınmaz; LOCATION→WKT; Energy’de `USERID = ABYS_ID + 10000` |
| 5 | `LS_AGREEMENT.sql` | `LS_AGREEMENT` (+ `STG_TARIFF_MAP`) | KUL + ABN sözleşmelerini tek staging tabloda üretmek; tarife map, ISACTIVE/PARID CTAS içi wire | KUL: `LREF = CS_AGREEMENT.ID`; ABN: AGR sonrası ardışık LREF; tarife map satırları >0; FLATID/COUNTERSN Energy’de FLAT/ITEMS migrate sonrası dolar |
| 6 | `LS_AGR_CLOSE.sql` | `LS_AGR_CLOSE` | Sözleşme kapatma başvurularını taşımak; Energy `LS_005_01_AGR_CLOSE` | ABYS bridge kolonları dolu; kapatma nedeni/tarih/register bağları korunmuş; 2. geçiş placeholder kolonlar NULL kabul |
| 7 | `LS_AGR_GUARANTY.sql` | `LS_AGR_GUARANTY` | Teminat + mektup (UNION). **GTYPE39 TOTAL/MUSTTL:** güvence gelirleri; **23032 damga hariç** (DV faturada) | GTYPE dağılımı mantıklı; aynı AGRID’de çok satır OK; ORA-01790 yok |
| 8 | `LS_AGR_DEVICE.sql` | `LS_AGR_DEVICE` | Sözleşmeye bağlı cihaz/proje/atama bilgisini üretmek (`F_GET_LAST_*` ile) | Satır sayısı >0; ABYS bridge dolu; süre uzun olabilir (scalar PL/SQL → parallel fiilen seri) — timeout değilse OK |
| 9 | `LS_AGR_SERVQ.sql` | `LS_AGR_SERVQ` | Servis ekipmanı (KUL tesisat + ABN abone dalları) → Energy `LS_005_01_AGR_SERVEQ_TR` | TP2=`KUL` ve `ABN` satırları oluşmuş; sayaç/endeks join’leri boş değil; dump hazır |
| 10 | `LS_FITMENTFEE.sql` | `LS_FITMENT_FEE` | Bağlantı/tesisat ücretlerini hesaplayıp staging’e yazmak (`F_GET_CALCULATE_BBS`) | Tesisatsızlar düşer, çoklu tesisat fan-out üretebilir (bilinçli); Energy `LS_005_01_AGR_FITMENTFEE_TR` |
| 11 | `LS_AGREEMENT_AUTO_PAYMENT_LOG.sql` | `LS_AGREEMENT_AUTO_PAYMENT_LOG` | Talimatlı aboneler ve banka talimat geçmişini taşımak → Energy `LS_BNK_TALIMAT` | `CNT = CS_AGREEMENT_AUTO_PAYMENT_LOG`; aktif (`CANCEL_DATE` null) / iptal ayrımı doğrulanır |
| 11b | `LS_BANK_CONFIRM.sql` | `LS_BANK_CONFIRM` | Banka mutabakat/onay kayitlarini staging'e almak → Energy `LS_BNK_MUTABAKAT_DETAY` (364/365) | `CNT = CS_BANK_CONFIRM`; `ABYS_ID = ID`; APPROVAL_STATUS / TYPE dagilimi dogrulanir |
| 11c | `LS_BANK_ACC.sql` | `LS_BANK_ACC` | `IT_CASH` JOIN `IT_BANK_PRM` → Energy `LS_BANK_ACC` (125/126) | `CNT = IT_CASH∩BANK`; `ABYS_ID = ID`; BANK_ID dolu |
| 12 | `LS_INSTALLMENT.sql` | `LS_INSTALLMENT` | Taksit planı başlıklarını SMS’ten birebir staging’e almak | `ABYS_ID = ID`; kolon seti kaynakla uyumlu; #13 için önkoşul |
| 13 | `LS_INSTALLMENT_PLAN.sql` | `LS_INSTALLMENT_PLAN` | Taksit plan satırlarını (taksit no, vade, tutar) staging’e almak | Önkoşul #12; `INSTALLMENT_ID` başlığa bağlanır; orphan plan satırı olmamalı |
| 14 | `LS_WORK.sql` | `LS_WORK` | İş emri/randevu (`WO_WORK`) → Energy `LS_005_01_CS_APPOINTMENT` (530/531) | `LREF = WO_WORK.ID`; ASSINGSTATUS sözlüğü korunur; WKT lokasyon dönüşür; wire alanları NULL bırakılır |
| 15 | `LS_WORK_RESULT.sql` | `LS_WORK_RESULT` | İş emri sonuçlarını (`WO_WORK_RESULT`) → Energy `LS_005_01_WO_WORK_RESULT` (540/541) | Önkoşul #14; `WORK_ID` orphan = 0; Pass4 enrich kolonları NULL kabul |
| 16 | `LS_SPEFEE_ADD.sql` | `LS_SPEFEE_ADD` | `ROUND_VALUE ≠ 0` olan sözleşmelerde önceki aydan devir tutarını SPEFEE formatında üretmek | Kaynak filtre satır sayısı = CTAS CNT; GRANDTOTAL=ROUND_VALUE; mümkünse reading/index bağları dolu; hedef Energy `LS_005_01_SPEFEE` |
| 16b | `09_mig_accrue_type_map.sql` | `MIG_ACCRUE_TYPE_MAP` | ABYS ACCRUE → PCMS TYPE + EXPLAIN PREFIX/FMT + NEEDS_READING | Seed satırları dolu; STG_KEEP; dump yok |
| 17 | `LS_READING.sql` | `LS_READING` (+ STG_RD_* → DROP) | Sayaç okuma + `ABYS_ACCRUE_TYPE_ID` (organik=account ACCRUE) | STG_RD DROP; sonra #17b synth |
| 17b | `LS_READING_SYNTH.sql` | `LS_READING` (INSERT) | NEEDS_READING gap → sentetik TRAN (LREF≥1.5e9, creator personel) | Gap CNT = map∩okumasız; ABYS_NOTE MIG_SYNTH% |
| 18 | `LS_HHD_MSTR.sql` | `LS_OV_HHD_MSTR` (+ MAP) | HHD master + READ_NO; EOD grain; orphan=prsnl+TRUNC; synth orphan += ACCRUE / ROUTE_GRP | Önkoşul #17b; GATE v04 PASS; TMP/EOD/ORPHAN DROP |
| 18g | `LS_HHD_MSTR_GATE.sql` | — (GATE) | MAP+SKIP=READING; orphan tekil (+ACCRUE); READ_NO monotonik | **PASS** |
| 19 | `LS_KFACTOR_VALUE.sql` | `LS_KFACTOR_VALUE` | Günlük/aylık ısıl değer ve kromatograf verisini (servis kutusu bazlı) taşımak | UK `(ACTION_DATE, SERVICE_BOX_ID, IS_MONTHLY)` ihlali yok; IS_MONTHLY 0/1 ayrımı doğru |
| 20 | `LS_ADJUSTMENT_COEFFICIENT.sql` | `LS_ADJUSTMENT_COEFFICIENT` | Fatura düzeltme katsayılarını (tip/yıl/ay/debth) staging’e almak | Tip-yıl-ay-debth kombinasyonları tekil/tutarlı; dump → izgazMGR |
| 21 | `LS_SPEFEE.sql` | `LS_SPEFEE` | Hesaba eklenen özel ücretleri (`CS_ACCOUNT_ADD`) SPEFEE formatında üretmek | ABYS_* bridge dolu; #16 ile aynı Energy hedef (`LS_005_01_SPEFEE`) ama farklı kaynak grain |
| 22 | `00_session_parallel.sql` | — (session) | Tahsilat CTAS oturumunu DOP 56 parallel query/DML’e almak (O0) | Session parallel açık; `MIG_CTAS_LOG`’a O0 OK yazılır; TEMP/PGA riski bilinci |
| 23 | `00_mig_ctas_log.sql` | `MIG_CTAS_LOG` + `P_MIG_CTAS_LOG` | Her adımın START/OK/FAIL kaydını tutacak log altyapısını kurmak (O0L) | Sequence + tablo + proc mevcut; `@99_log_status` ile izlenebilir |
| 24 | `00_mig_param_full.sql` | `MIG_PARAM` | Pilot AGR filtresini kapatıp FULL üretim moduna geçmek (O0b) | `MIG_PARAM` boş/FULL; sonraki adımlar tüm hesapları kapsar |
| 25 | `10_stg_inv_acc_inc.sql` | `STG_INV_ACC_INC` | O10 fee pivot. **DV ayırımı:** ACCRUE **5/6→109**, **21/341→111** → `TOTAL_DV`; diğer ACCRUE’da damga TL’de | `#26` önkoşulu |
| 26 | `11_ls_invoice.sql` | `LS_INVOICE` | Ana faturalar (O11). **`DV=TOTAL_DV`** (sabit 0 değil) | `LREF = CS_ACCOUNT_ACTION.ID`; TYPE←map; EXPLAIN=EXISTING+map; READ_TRANSREF←LS_READING; ACCRUE≠14 |
| 27 | `12_ls_invlines.sql` | `LS_INVLINES` | Fatura kalemleri (O12). **TYPE 109/111:** damga `TL=0`,`DV=amt`; diğer TYPE’da damga TL’de | `LREF = CS_ACCOUNT_INCOME.ID`; `INVOICEREF = LS_INVOICE.LREF`; LINENR dolu; orphan satır yok |
| 28 | `13_ls_mig_agr_list.sql` | `LS_MIG_AGR_LIST` | Energy `adim_full` / LOOP’un kullanacağı sözleşme listesini çıkarmak (O13) | Distinct AGR seti; dump → izgazMGR; canlı DISTINCT yerine bu tablo kullanılır |
| 29 | `14_ls_debt_paytrans.sql` | `LS_DEBT_PAYTRANS` | IOCODE=0 borç faturalarından borç paytrans prefab üretmek (O14); Energy 575 karşılığı | `CNT ≈` IOCODE=0 fatura sayısı; PAID/BANK henüz final değil → #36’te yeniden yazılır |
| 30 | `20_ls_eksilten_overlay.sql` | `LS_OV_EKS_CLASS`, `LS_OV_EKS_SKIP`, `LS_OV_IADE_*`, `LS_OV_KISMI_*`, `LS_OV_MAIN_UPD` | Tam/kısmi eksilten (iade) senaryolarını SRC_KEY map ile overlay tablolara ayırmak (O20); sentetik INT LREF yok | `tah.tut` = ACTION_TYPE **1,3,10,41** (gecikme dahil; sahte ASIM yok); TAM/KISMI dolu; SRC_KEY; #31 gate |
| 31 | `27_gate_eksilten.sql` | — (GATE) | Eksilten overlay bütünlüğünü hard kontrol etmek (O27★) | **PASS**: TAM=IADE=IADE_PT ve KISMI_HDR=KISMI_PT sayıları eşit; FAIL → zincir DUR, dump yok |
| 32 | `30_ls_tahsilat_overlay.sql` | `LS_OV_PAY_ALLOC`, `LS_OV_PAY_PT`, `LS_OV_TAH_INVOICE`, `LS_OV_TAH_INVLINES`, `LS_OV_MAHSUP_*`, `LS_OV_CANCEL_*`, … | Ödeme–fatura eşlemesini (alloc/PT), tahakkuk, mahsup ve iptal overlay’lerini üretmek (O30); `MIG_PARAM.AGR_ID` doluysa pilot scope | PAY_PT `SRC_KEY=PAY_PT|{PAY}|{MAIN}`; iptal PAY `CANCELED=1` + ALLOC; TAH_INV EXPLAIN=`TAHSILAT`/`TAHSILAT IPTAL` + BANK; **mahsup TYPE101 IL 162/1936** (`LS_OV_TAH_INVLINES`); DEBT_PAID / mahsup/cancel dolu |
| 33 | `32_ls_ov_debt_paid_lastpaid.sql` | `LS_OV_DEBT_PAID_UPD`, `LS_OV_INV_PAY_GAP` | Ödemesi olan ama CLOSED/LPD eksik faturalar için DEBT_PAID güncelleme seti üretmek (O32) | PAID_AMT/CLOSED/LASTPAIDDATE dolu; gap diag tablosu ödeme-var-ama-kapalı-değil vakalarını listeler |
| 34 | `34_ls_ov_pay_pt_bank_enrich.sql` | `LS_OV_PAY_PT` + `LS_OV_TAH_INVOICE` (enrich) | PAY_PT PAID/bank/makbuz/LPD/XTYPE + TAH_INV bank/LPD senkron (O34★★) | `PAID = PAYABLETOTAL`; PAY_PT ve TAH_INV BANKREF / BANK_RECORD_REF / LPD dolu |
| 35 | `33_ls_invoice_close_bank_patch.sql` | `LS_INVOICE` (UPDATE) | LS_INVOICE üzerinde CLOSED, LASTPAIDDATE, BANK alanlarını ödemeye göre patch’lemek (O33★★) | Kapama adayı faturalarda CLOSED=1; LPD ve BANKREF son ödeme ile hizalı |
| 36 | `14b_ls_debt_paytrans_rebuild.sql` | `LS_DEBT_PAYTRANS` (yeniden) | O33 sonrası borç PT’yi final PAID/BANK/LPD/XTYPE ile yeniden üretmek (O14b★★) | CLOSED faturalarda `PAID = PAYABLETOTAL`; banka/LPD/XTYPE fatura ile uyumlu |
| 37 | `35_ls_ov_id_map.sql` | `LS_OV_ID_MAP` | Tüm overlay SRC_KEY’lerini tek haritada toplamak; Energy IDENTITY sonrası LREF bağlamak için (O35) | SRC_KEY unique; LREF_HINT dolu olanlar INT-safe; `ENERGY_LREF` Oracle’da NULL (MSSQL insert sonrası dolar) |
| 38 | `41_gate_tahsilat.sql` | — (GATE) | Tahsilat overlay + fatura/PT tutarlılığını hard kontrol etmek (O41★) | **PASS**; FAIL → DUR, dump yok |
| 39 | `50_ls_afl_open_debt.sql` | `LS_AFL_OPEN_DEBT` | Hesap bazlı açık borç anlık görüntüsü (FRK master) üretmek (O50) | AS_OF ≈ SYSDATE; açık bakiyeli hesap grain’i dolu; FRK karşılaştırma kaynağı |
| 40 | `51_ls_stg_inv_pay_close.sql` | `LS_STG_INV_PAY_CLOSE` | Fatura + ödeme + DEBT_PAID + AFL’yi tek kapama-aday staging tabloda birleştirmek (O51) | Close candidate / wizard join hızlı çalışır; banka/vezne isimleri mümkünse dolu |
| 41 | `52_ls_payment.sql` | `LS_PAYMENT` | Makbuz grain’inde tahsilat kayıtlarını üretmek (senaryo/wizard aynı grain) (O52) | BANKA_ID, BANK_RECORD_REF, makbuz no dolu; PAY grain PT ile tutarlı |
| 42 | `53_ls_eksilten_family.sql` | `LS_EKSILTEN`, `LS_PARTIAL_EKSILTEN` | Overlay sınıflamasından Energy’ye gidecek tam/kısmi eksilten family tablolarını üretmek (O53) | Önkoşul O20; TAM → LS_EKSILTEN, KISMI → LS_PARTIAL_EKSILTEN; sayımlar KIND ile uyumlu |
| 43 | `54_ls_artiran_emanet.sql` | `LS_ARTIRAN`, `LS_EMANET` | Artıran tahakkuk + emanet (ACCRUE=14) kayıtlarını staging’e almak (O54) | Önkoşul O11; artiran fatura seti + emanet account seti oluşmuş |
| 43b | `60_ls_ov_guvence_iade.sql` | `LS_OV_GUVENCE_IADE_*`, `STG_GUV_IADE_PIVOT` | ACCRUE14 tip20/12/40 + güvence gelirlerinden TYPE **110** overlay (O60); ID_MAP append | `TEDIYE≠0`; EXPLAIN mahsup kalan; dump zorunlu |
| 44 | `55_ls_mahsup.sql` | `LS_MAHSUP` | Mahsup işlemlerini Energy mahsup grain’ine hazır tabloya yazmak (O55) | Önkoşul O30 MAHSUP_SRC; mahsup satırları dump’a hazır |
| 45 | `56_ls_taksit.sql` | `LS_TAKSIT` | Taksit hesaplarının açık/kapalı/iptal/fazla durumunu tek tabloda üretmek (O56★★) | ACIK/KAPALI/IPTAL/FAZLA sayımları >0 (veriye göre); kapalı taksitler de dahil |
| 46 | `57_ls_installment_plan_pay.sql` | `LS_INSTALLMENT_PLAN_PAY` | Taksit plan satırı ödemelerini (vade sırası + ödeme tarihi) üretmek (O57★★) | `ORDER_NUMBER = INST_NR`; IS_PAID / PAYMENT_DATE / BANKREF dolu olanlar tutarlı |
| 47 | `58_gate_pilot_parity.sql` | — (GATE) | Pilot parity: zorunlu tablo/kolon + PAY_PAID_GAP + PAY_NO_XREF kontrolleri (O58★★) | **GATE_PASS**; PASS olmadan dump yok |
| 48 | `99_log_status.sql` | — (özet) | `MIG_CTAS_LOG` üzerinden tüm adımların durum özetini göstermek (O99) | FAIL / GATE_FAIL = 0; tüm core adımlar OK |
| 48b | `98_transfer_indexes.sql` | — (IX) | Dump öncesi Oracle join IX (READING LREF/ACCOUNT, MSTR, invoice) | Idempotent |
| 48c | `99_stg_cleanup.sql` | — (DROP) | STG_DROP TMP/STG_RD (Gate PASS sonrası) | DUMP tabloları kalır |
| 49 | `DUMP_MANIFEST.txt` + `TABLE_CATALOG.md` | LS_INVOICE, LS_READING, LS_OV_HHD_*, LS_OV_*, … | Oracle `MIGRATION` → izgazMGR; sınıf kataloğu | O58 PASS sonrası; kolon kritikleri manifest’te |

