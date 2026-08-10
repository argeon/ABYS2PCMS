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
| Açık kod | O20 ASIM gecikme · mahsup IL 162/1936 — **hâlâ CTAS işi** |

Detay: `NOTES_REVIZYON_BACKLOG` 「2026-08-11 05:00」 · `NOTES_AFL_HEAL_TEST_20260811.md`

---

## B) 05:00 — DATA AKTARIM TESTİ (saha)

### B0 — Preflight (T−30 dk)

```text
[ ] CTAS: NOTES_CTAS_NO_RESTART — FAIL→resume; 00_run_all baştan YASAK
[ ] CTAS: TEMP/undo/TS + O27/O41 PASS + 99_log FAIL=0 (dump öncesi)
[ ] energy log % < 85
[ ] TTK satır ≈ 72.019.250; IX ACCOUNT_ID / AGREEMENT_ID var
[ ] LS_AFL_OPEN_DEBT dolu; MIG_AGR_FRK_ALL var (yoksa 97 seed)
[ ] 28_DEPLOY_597 + 13_590_TAM_MAIN_CLOSE sunucuda (R15/R20 gövde)
[ ] NCIX durumu not alındı (20b/20c)
[ ] Results to Text + sqlcmd -f 65001
```

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
| AGR 412056 | ASIM görüntüsü; mahsup IL varsa 162/1936 |
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
- [ ] O20 ASIM / mahsup IL — kabul: bilinçli gap veya CTAS deploy  
- [ ] O60 + E610 planı net (ATLA veya EXEC)  
- [ ] Kill politikası + log backup sorumlusu  
- [ ] Imza satırı: operatör / saat / ortam  

**Operatör:** _______________ **Ortam:** 196 / 195 / canlı  
**Başlangıç:** _______ **Bitiş:** _______ **Sonuç:** PASS / PARTIAL / FAIL  
**Not:** _______________________________________________
