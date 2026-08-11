# Cutover gün planı — 2026-08-11

**Amaç:** Data aktarım testi (05:00) + cutover operasyon notları.  
**Ortam:** 196 `SQLTESTLIVE` / energy (test) · 195 `SQLMIG01` (referans / mirror).  
**Operatör girişi:** [`CUTOVER_ONE_PAGE.md`](CUTOVER_ONE_PAGE.md)

---

## A) Bu sabaha kadar hazır olanlar (2026-08-10 kapanış)

| Alan | Durum |
|------|--------|
| TTK master | `07082026` reload 196 — **72.019.250** satır + IX |
| AFL as-of | O50 cutover `2026-08-08` |
| 91f–91i AFL heal | 195+196 APPLY; FRK post-91i OK |
| R15–R20 | adopt IOCODE≠0, GATE bad-map FAIL, TAM MAIN close, 91e |
| Paket mirror | `_sync_snapshot` + `_deploy_195` (CTAS/ENERGY/REPORT) |
| DV / FEE heal | `92` pakette; **`93` FEE 196 APPLY 2026-08-10** (SET_1=280.987; KUL FC=1≈307.890) |
| AGR_GUARANTY | **R21 PARTIAL** — CTAS 026 kod DONE (23032 hariç, 195); Oracle re-run + Energy 311 AÇIK (§2b0) |
| O20 / mahsup IL | **DONE 2026-08-11** — O20 `tah.tut`∈(1,3,10,41); O30 `LS_OV_TAH_INVLINES` + 597 TAH_IL |
| CTAS paket+195 | **DONE ~07:57** — `_deploy_195` CTAS=84; DV/GUAR/O20/O30/FEE diskte |
| CTAS decimal | **KOŞULDU 2026-08-11 ~09:20+** — tutar `CAST NUMBER(18,3)` / ROUND 3 (scale kaybı önleme; O10+ overlay) |

Detay: `NOTES_REVIZYON_BACKLOG` 「2026-08-11 05:00」 · `NOTES_AFL_HEAL_TEST_20260811.md`

---

## B) 05:00 — DATA AKTARIM TESTİ (saha)

### B0 — Preflight (T−30 dk)

```text
[x] CTAS paket+195: DV/GUAR/O20/O30/FEE kod hazır — deploy 07:57 (CTAS=84)
[ ] CTAS koşu: NOTES_CTAS_NO_RESTART — FAIL→resume; 00_run_all baştan YASAK
[ ] CTAS DV koşu: 130–132 eskiyse tekrar; @925_DIAG — BAD_DV0=0
[ ] CTAS GUAR koşu: 026 eskiyse @@026 tekrar; spot 1200078 TOTAL=4346
[ ] CTAS: TEMP/undo/TS + O27/O41 PASS + 99_log FAIL=0 (dump öncesi)
[x] energy log % < 85                         ← 196 ~5.9% (07:34)
[x] TTK satır ≈ 72.019.250; IX ACCOUNT_ID / AGREEMENT_ID var
[x] LS_AFL_OPEN_DEBT dolu (~280k); MIG_AGR_FRK_ALL var
[x] 28_DEPLOY_597 + 13_590_TAM_MAIN_CLOSE sunucuda (R15/R20 gövde) — 07:35 taze deploy
[x] NCIX durumu not alındı (20b/20c)          ← INV disabled=15; PT disabled=0
[ ] Results to Text + sqlcmd -f 65001
```

**196 energy önlem stamp (2026-08-11 ~07:35):**

| Kontrol | Sonuç |
|---------|--------|
| R15 INSERT / R16 GATE / R20 ALL | body OK; `28`+`13`+`19` redeploy |
| bad_map PAY→debt | **0** |
| `MIG_613_ERR` + 613 v6 | CREATE + redeploy |
| O60 `LS_OV_GUVENCE_IADE` | **yok → D2/E610 ATLA** |
| O30 `LS_OV_TAH_INVLINES` | **yok** — mahsup IL spot dump sonrası; kod hazır |
| `LS_OV_EKS_CLASS` | var (TAM close için) |

**195 sync (2026-08-11 ~07:40):** `_deploy_195` OK (CTAS=84 ENERGY=266 REPORT=38). SP-only redeploy (`00e`+613+20/21/22/29+13/19) — R15/R16/R20 OK, bad_map=0, `MIG_613_ERR` var. **Log %99.43** → `28` index DDL atlandı; FULL öncesi `BACKUP LOG` / grow şart. O30/O60 yok → aynı ATLA.

**195 sync (2026-08-11 ~07:46):** `_deploy_195` tekrar (CTAS=84 ENERGY=266 REPORT=38). Energy SP `20/21/22/29` redeploy — R15 adopt + identity keyset + R16 GATE marker =1.

**195 sync (2026-08-11 ~07:57):** `_deploy_195` CTAS aşaması (CTAS=84 ENERGY=266 REPORT=38). Paket hazır damgası: O20/O30/DV/GUAR/FEE + NOTES_CTAS_NO_RESTART. Koşu anı checklist açık.

**Energy R17/R18 (2026-08-11 ~08:00):** `SSMS_TAHSILAT` step 11 probe+20e; `RUN_ORDER` D gömülü; `20_597_INSERT` CLEAN MAXDOP 8. `_deploy_195` OK. Sunucuda R18 için `28_DEPLOY_597` / `20` redeploy şart.

**Energy R12/R16/MAXDOP (2026-08-11):** 35/40/92 → SP; `SSMS_POST` EXEC; `00i` HEAP→PK; 597 kalan MAXDOP 8. Deploy: 35+40+92 sql + `28`/`20` + opsiyonel `00i` (dump sonrası).

**Energy R22 P0+P1 (2026-08-11):** `26*` SP (`IX_PRECHECK`/`IX_MGR_ENSURE`/`597_NCIX_*`/`IX_IP_AGR`); RUN_ORDER/30c/SSMS/ONE_PAGE = 571→572… + EXEC-only NCIX. Sunucu: sqlcmd deploy `26*` once; `10f` STATUS OK.

**Energy R23 (2026-08-11):** `SP_MIG_20E_BAD_MAP_HEAL` / `SP_MIG_INV_DV_FROM_INCOME` / `SP_MIG_93_AGR_FEE_COLLECTED` / `SP_MIG_95_TTK_AFL_RAPOR` / `SP_MIG_99_AFL_EN_FRK`. Deploy once + `10f` STATUS.

**CTAS decimal (2026-08-11 ~09:20+):** Operatör — tutar kolonları `NUMBER(18,3)` revizyonlu paket koşuldu (O10 header: scale kaybı önleme). Dump→MGR sonrası kontrol: izgazMGR tutar kolonları `decimal(22,0)` olmamalı (kuruş kesilmesin); gerekirse dump schema + `01_diag_kurus_src_en`.

### B1 — Kirli DB residual (FULL değilse)

Sıra: `NOTES_AFL_HEAL_TEST` §2 — **hepsi önce DryRun=1→0 aday**.

```text
1) 91f DryRun → APPLY (aday>0)
2) 91g …
3) 91h …   ★ büyük etki
4) 91i …   (MinAbs=10)
5) SP_AGR_FRK_ALL @OnlyDiff=1
6) Kabul: en_gt_afl ~0–20; material DELTA_KALAN_NET<=-10 bandı
```

**Çalıştırma:** `SP_MIG_597_ALL @CLEAN=1` · full WIRE · `98_TEST_*` — **hayır**.

### B2 — FULL / yeniden yükleme (yeni dump geldiyse)

`CUTOVER_ONE_PAGE` §1 zinciri. Kritik unutulanlar:

```text
★ 590 deploy: 10 → 11 → 13_TAM_MAIN_CLOSE → 12 → 19
★ 20b NCIX OFF → 597 → GATE → probe → 20c
★ bad_map >0 → 20e; CLEAN=1 YASAK
★ 613 yalnız open-debt (50e)
★ D2 E610 yalnız O60 dump varsa
★ D3/D4: 92 DV + 93 FEE DryRun→APPLY
★ Validate: 95 → 99 → 97 @OnlyDiff=1
```

### B3 — Spot (test geçişi)

| Spot | Beklenen |
|------|----------|
| AGR 3 | TAM; MAIN CLOSED; DELTA_KALAN≈0 veya bilinen |
| AGR 412056 | O20 sonrası TAM/ASIM doğru; mahsup TYPE101 **IL 162/1936** (dump+597 sonrası) |
| INV 147401407 | DV≠0; TAH TOTAL=GT−DV |
| TTK miss (emanet hariç) | ~110 (borç dilimi); join = ACCOUNT_ID |
| CANCEL_REV INV 66081785 | AFL-gate davranışı |

```sql
-- TTK var / INV yok (emanet hariç) — ~110
SELECT COUNT_BIG(*)
FROM energy.dbo.TUKETIM_TUTAR_KONTROL b WITH (NOLOCK)
WHERE ISNULL(b.ACCRUE_TYPE_ID, -1) <> 14
  AND NOT EXISTS (
      SELECT 1 FROM energy.dbo.LS_005_01_INVOICE i WITH (NOLOCK)
      WHERE i.ABYS_ACCOUNT_ID = b.ACCOUNT_ID
  );
```

---

## C) Saatlik ritim (öneri)

| Saat | Odak |
|------|------|
| 05:00–05:30 | Preflight + TTK/AFL sanity |
| 05:30–… | FULL ise B→C→D (571…597); değilse B1 residual |
| Orta | Probe bad_map + GATE; log % |
| Post-597 | 35 → 611 → 613 → 40 → 92 |
| Son | 92 DV / 93 FEE (196 FEE APPLY yapılmış; FULL reload sonrası tekrar) → 95/99/97 → spot → imza |

ETA yoksa: Messages `RAISERROR` + `MIG_STEP_LOG` + PT/INV count.

---

## D) Karar matrisi (test sonucu)

| Sonuç | Anlam | Sonraki |
|-------|--------|---------|
| GATE_PASS + bad_map=0 + spot OK | Test geçti | Residual dokümante; canlı cutover aynı zincir |
| GATE_PASS ama FRK material şişik | Patch/açık kod | 91f–i DryRun; ASIM/mahsup notu |
| bad_map >0 | R15 regress | `20e` + adopt deploy; CLEAN=0 |
| 613 pending açık | open-debt filter / ERR tablo | `50e` resume; `MIG_613_ERR` |
| TTK miss >>110 (emanet dışı) | dump/join | grain kontrol; O59 |

---

## E) Bilinçli residual (FAIL sayma)

1. Emanet TTK miss (~757k) — `@ExcludeEmanet=1`  
2. AFL eps gürültüsü (`|DELTA|<10`) — material band kullan  
3. AFL open + EN low + PAID odası yok (~498)  
4. Plan `INVOICE_REF` NULL (~10k)  
5. IPP join miss  
6. `E597=FAIL` log + sonraki `E597G=PASS` — otorite GATE  

---

## F) Canlı cutover’a taşıma checklist

FULL canlı öncesi (backlog A1–A7 + R16–R18 kısmen):

- [ ] 195 paket = repo (`_deploy_195`)  
- [ ] `CUTOVER_ONE_PAGE` + bu gün notu okundu  
- [x] O20 ASIM / mahsup IL — CTAS+597 deploy (2026-08-11); spot 412056 doğrula  
- [x] O60 + E610 planı net — **ATLA** (196’da OV yok, 07:35)  
- [ ] Kill politikası + log backup sorumlusu  
- [ ] Imza satırı: operatör / saat / ortam  

**Operatör:** _______________ **Ortam:** 196 / 195 / canlı  
**Başlangıç:** _______ **Bitiş:** _______ **Sonuç:** PASS / PARTIAL / FAIL  
**Not:** _______________________________________________
