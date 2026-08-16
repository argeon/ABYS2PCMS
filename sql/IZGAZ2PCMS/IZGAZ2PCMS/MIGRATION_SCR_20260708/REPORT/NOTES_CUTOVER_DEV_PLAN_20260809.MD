# Cutover geliştirme planı — sorunsuz / eksiksiz aktarım (2026-08-09)

Kaynak: canlı cutover notları (597 v5c, WIRE/GATE, 20c, 611/613, paket/snapshot sapması)  
+ `NOTES_597_PERF_SAFE.md` + `EXIT_MAP.md` + `MIGRATION_SCR_20260708/ENERGY`.

**Tek doğru paket yolu:** `prodREADY_ENERGY` + `prodREADY_ENERGY3007`  
**Arşiv kopya:** `MIGRATION_SCR_20260708/ENERGY` (`_sync_snapshot.ps1`)  
**Yasak referans:** `_tmp_*` (ops scratch; paket sayılmaz)

**Operatör tek giriş:** [`CUTOVER_ONE_PAGE.md`](CUTOVER_ONE_PAGE.md)  
**Gün planı (05:00 test):** [`NOTES_CUTOVER_DAY_20260811.md`](NOTES_CUTOVER_DAY_20260811.md)

---

## 0a) Revizyon disiplini (zorunlu)

Canlıda öğrenilen her fix **aynı gün** ana koda alınır — `_tmp` / “sonra” yok.  
Takip: [`NOTES_REVIZYON_BACKLOG.md`](NOTES_REVIZYON_BACKLOG.md) (R01…).  
Kapanış: backlog DONE/PARTIAL + `_sync_snapshot` + `_deploy_195` (CTAS/ENERGY/REPORT).

**Sonraki FULL hazırlık:** backlog **「SONRAKI AKTARIM — hazırlık」** (R15 probe, 20b, CLEAN=0, R12/R16–R18).  
**2026-08-11 05:00 data aktarım testi:** `NOTES_CUTOVER_DAY_20260811.md` + backlog TTK/AFL bölümü.  
Ops: [`NOTES_597_OPS_HEAL.md`](NOTES_597_OPS_HEAL.md) R08/R09/R15.

## 0) Durum — 2026-08-10 kapanış (planın zemini)

| Alan | Durum |
|------|--------|
| 571/581/575 + 590 | Önceki cutover’da büyük ölçüde tamam; FULL’da yeniden |
| 590 TAM MAIN close | **R20 DONE** — `13` + `19` WIRE→TAM_CLOSE→GATE |
| 597 INSERT+WIRE+GATE | R01–R02/R15–R16; otorite `E597G`; bad_map→GATE_FAIL |
| INV/PT NCIX | FULL: **20b OFF → ALL → 20c** zorunlu |
| 611 + 611b | Önceki cutover DONE |
| 613 | open-debt `50e` + v6/`MIG_613_ERR` (R07); resume ile bitir |
| 35 / 40 / 92 STG | Script hazır (R10–R13); APPLY post-613; R12 SP taşıma cutover sonu |
| 92 DV / 93 FEE | Pakette; DryRun→APPLY (`RUN_ORDER` D3/D4) |
| AFL residual 91f–i | 195+196 APPLY (2026-08-10); **FULL zincire koyma** |
| TTK | 196 reload `07082026` 72.0M; join = `ABYS_ACCOUNT_ID` |
| Paket senkronu | snapshot + 195 mirror; **CTAS paket hazır damgası 2026-08-11 ~07:57** |

---

## 1) Hedef mimari (bir sonraki FULL için)

```text
CTAS dump → prep/IX/collation
  → REF/MASTER/AGR/READING (önkoşul)
  → MAP → 571 → 581 → 575(+576)
  → 590_ALL (10→11→13_TAM→12→19)
  → [20b INV+PT NCIX OFF]
  → 597_ALL (v5c hard rules)
  → GATE_PASS → probe bad_map → 20c
  → E610? → 35 BANKREF → 611 → 611b → 613 (open-debt only)
  → 40 IPP → 92 STG CLOSE → 92 DV / 93 FEE
  → VALIDATE 95/99/97 → 90
  → (kirli DB) 91f–i residual — paket zinciri DIŞI
```

**Hard rules (geri dönüş yok):**
1. `#temp` yok → fiziksel `MIG_*_STG_*`
2. Hot path’te MGR `LS_OV_ID_MAP` UPDATE yok → `20a` offline
3. Filtered IX: `IOCODE = 0` (`ISNULL(IOCODE,0)` yasak)
4. Scalar `FN_SAFE_SMALLDT_DEP` hot path yok → inline CASE
5. `IMPLICIT_TRANSACTIONS OFF`; dış BEGIN TRAN yok; kısa TRAN sadece MERGE+MAP_OUT
6. FULL: INV+PT NCIX DISABLE → INSERT → GATE → REBUILD
7. Overlay EXEC sadece `*_ALL` (tek INSERT yasak)
8. Deploy: çalışan SP varken ALTER yok; `sqlcmd -f 65001`
9. Bad map varken `@CLEAN=1` YASAK → önce `20e`
10. 597 adopt hint yalnız `IOCODE<>0`

---

## 2) Faz planı

### Faz A — Paket bütünlüğü (P0, kod/ops)

| # | İş | Durum |
|---|-----|--------|
| A1 | Sync-map: `50e_613_RESUME…`, `SSMS_POST_613`, `SSMS_TAHSILAT` | DONE (snapshot) |
| A2 | `_sync_snapshot` + index | DONE 2026-08-09 |
| A3 | `CUTOVER_ONE_PAGE.md` | **DONE 2026-08-10** |
| A4 | `_tmp` ≠ paket | sürekli |
| A5 | `_deploy_195` CTAS/ENERGY/REPORT | DONE |

### Faz B — Canlıyı bitir / test günü (P0)

**Amaç:** 613 + post zincir **veya** 05:00 FULL/residual test (`NOTES_CUTOVER_DAY_20260811`).

| # | İş | Kabul |
|---|----|--------|
| B1 | `50e_613_RESUME_OPEN_DEBT_ONLY` | `pending_open_debt→0` |
| B2 | Açık borçlu AGR’de `INST_NR>0` veya ERR skip | `SPLIT_OK` |
| B3 | `40_…pay_apply` DRY=1→0 | IPP apply |
| B4 | `35_bankref…` DRY=1→0 | BANKREF LREF |
| B5 | `92_stg…` DRY=1→0 | STG close |
| B5b | `92_INV_DV…` + `93_FEE…` DRY=1→0 | TYPE109/111 + fee |
| B6 | GATE + `SP_AGR_FRK_ALL @OnlyDiff=1` + 95/99 | FRK kabul bandı |
| B7 | Opsiyonel `20a` | cutover bloklamaz |

### Faz C — 597 motoru (P1 — çoğu DONE)

| # | İş | Durum |
|---|-----|--------|
| C1–C4 | hint / FORCE ORDER / adopt / GATE IOCODE | DONE R01–R02/R15 |
| C5 | 20b/20c runbook | ONE_PAGE + RUN_ORDER |
| C6 | Log %85 | ONE_PAGE |
| C7 | ALL FAIL vs GATE_PASS | NOTES_597_OPS R08 |

### Faz D — 613 performans (P1)

| # | İş | Durum |
|---|-----|--------|
| D1 | open-debt pending | DONE |
| D2 | MAXDOP 8 | R07 kısmen |
| D3 | `MIG_613_ERR` | DONE R07 |
| D4–D5 | progress / paralel | TODO sonraki FULL |

### Faz E — Operasyon iskeleti

| # | İş | Durum |
|---|-----|--------|
| E1 | SSMS step şeması | var (`SSMS_*`) |
| E2 | Kabul sorgu bloğu | ONE_PAGE §2 |
| E3–E5 | Kill / collation / LOADED | ops notes |

### Faz F — Doğrulama matrisi (P0)

| Kapı | Sorgu / EXEC | Beklenen |
|------|----------------|----------|
| G1 | STG_PAY left / MAP_PAY = MGR_PAY | 0 / eşit |
| G2 | MAP_TAH = MGR_TAH | eşit |
| G3 | `SP_MIG_597_GATE` | GATE_PASS |
| G4 | PAY `IOCODE<>0` CROSSREF NULL | 0 |
| G5 | INV/PT NCIX disabled | 0 (post-20c) |
| G6 | 613 `pending_open_debt` | 0 |
| G7 | EN_PLAN = MGR_PLAN | eşit |
| G8 | `SP_AGR_FRK_ALL @OnlyDiff=1` | kabul bandı |
| G9 | 95/99/90 checklist | FAIL=0 veya bilinen istisna |

---

## 3) Öncelik sırası (2026-08-11)

```text
05:00 TEST / CUTOVER
  CUTOVER_ONE_PAGE + NOTES_CUTOVER_DAY_20260811
  → (kirli) 91f–i DryRun  VEYA  (FULL) B→…→V
  → spot + G1–G9

POST / paket
  ~~R12~~ DONE 2026-08-11 (35/40/92 → SP)
  ~~R16 HEAP→IX / R17 / R18~~ DONE 2026-08-11
```

---

## 4) Bilinçli residual (blok değil — dokümante et)

- Plan `INVOICE_REF` NULL (~10k): iptal/edge; 611b sonrası beklenen bant.
- PAY_PT MAP’te `IOCODE=0` satırlar: debt/overlay doğası; GATE tahsilat kapsamı dışında (filled map’te **0** olmalı — R15/R16).
- `E597=FAIL` + sonraki `E597G=GATE_PASS`: otorite GATE.
- Identity path / hint collide: LREF dolu + IOCODE≠0 → adopt.
- Emanet TTK miss (~757k); AFL eps gürültüsü; AFL open + PAID odası yok.
- ~~Açık kod: O20 ASIM gecikme; mahsup IL 162/1936~~ → **DONE 2026-08-11** (O20 tah∈1,3,10,41; `LS_OV_TAH_INVLINES` + 597 TAH_IL). Spot: AGR 412056.

---

## 5) Tanım: “eksiksiz aktarım”

1. EXIT_MAP sırası tamam (dump→…→90)  
2. G1–G9 kapıları PASS  
3. Repo `prodREADY_*` = `MIGRATION_SCR_20260708` = 195 deploy (diff yok)  
4. Ops scratch (`_tmp`) pakete karışmamış  
5. Bir sonraki FULL: hard rules + 613 open-debt + MAXDOP + 20b/20c ile **temiz koşu**  

---

## 6) Riskler

| Risk | Mitigasyon |
|------|------------|
| 613 sessiz ERR | `MIG_613_ERR` (D3) |
| Log %90+ | ONE_PAGE / BACKUP LOG |
| Deploy drift | A5 + sync |
| ALL FAIL paniği | C7 + G3 |
| DOP 48 thrash | MAXDOP 8 |
| Boş 613 turu | D1 (yapıldı) |
| Bad map + CLEAN=1 | 20e önce; CLEAN=0 |
| 91f–i FULL’a gömme | PAKET_PATCH_HIZALAMA |
