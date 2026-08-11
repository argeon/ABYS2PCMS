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
| DV / FEE heal | `92` / `93` pakette; DryRun→APPLY runbook’ta |
| O20 / mahsup IL | **DONE 2026-08-11** — O20 `tah.tut`∈(1,3,10,41); O30 `LS_OV_TAH_INVLINES` + 597 TAH_IL |

Detay: `NOTES_REVIZYON_BACKLOG` 「2026-08-11 05:00」 · `NOTES_AFL_HEAL_TEST_20260811.md`

---

## B) 05:00 — DATA AKTARIM TESTİ (saha)

### B0 — Preflight (T−30 dk)

```text
[ ] CTAS: NOTES_CTAS_NO_RESTART — FAIL→resume; 00_run_all baştan YASAK
[ ] CTAS DV: 130–132 güncel TOTAL_DV (ACCRUE 5/6/21/341); eskiyse 130’dan tekrar
[ ] CTAS soft: @925_DIAG_DV_TYPE109_V01 — BAD_DV0=0
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
| Son | 92 DV / 93 FEE → 95/99/97 → spot → imza |

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
