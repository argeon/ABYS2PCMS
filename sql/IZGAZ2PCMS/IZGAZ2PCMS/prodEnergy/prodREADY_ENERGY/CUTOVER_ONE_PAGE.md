# Cutover — tek sayfa runbook

**Paket:** `prodREADY_ENERGY` + `prodREADY_ENERGY3007` + `90_afl_frk`  
**Canlı kök:** `sql/IZGAZ2PCMS/IZGAZ2PCMS/prodEnergy/`  
**Sunucu paket:** 195 `C:\www\MIGRATION_SCR_20260708` (`_deploy_195.ps1`)  
**Kural:** GATE_FAIL / FAIL → **DUR**. Overlay yalnız `*_ALL`. `sqlcmd -f 65001`.  
**CTAS:** FAIL → baştan `00_run_all` **YASAK** — [`NOTES_CTAS_NO_RESTART.md`](../../BACKUP/oracleCTAS3007/NOTES_CTAS_NO_RESTART.md)

Detay: [`EXIT_MAP.md`](../prodREADY_ENERGY3007/EXIT_MAP.md) · [`NOTES_CUTOVER_DEV_PLAN_20260809.md`](NOTES_CUTOVER_DEV_PLAN_20260809.md) · [`NOTES_REVIZYON_BACKLOG.md`](NOTES_REVIZYON_BACKLOG.md) · [`PAKET_PATCH_HIZALAMA.md`](../PAKET_PATCH_HIZALAMA.md)

---

## −1) Oracle CTAS (dump öncesi — geçen seferin tuzağı)

```text
Preflight TEMP/undo/TS + DOP 56|48
  → Faz A master → Faz R READING/HHD gate
  → O10–O14 → O20 → O27★ → O30–O35 → O41★ → O50–O61
  → 99_log FAIL=0 → DUMP
Patlayınca: MIG_CTAS_LOG son OK → o adımdan devam (A01 wipe yok)
```

| # | Kontrol | Beklenen |
|---|---------|----------|
| C0 | `NOTES_CTAS_NO_RESTART` okundu | resume bilinci |
| C1 | TEMP / undo / free TS | ORA-01652/01555 yok |
| C2 | O27 + O41 PASS | dump kapısı |
| C3 | FAIL sonrası | `00_run_all` baştan **yok** |

---

## 0) Önkoşul (FULL Energy başlamadan)

| # | Kontrol | Beklenen |
|---|---------|----------|
| P1 | Master / AGR / HHD 521–524 dolu | EXIT_MAP §1–2 |
| P2 | Dump + `00b_align_mgr_varchar` | bare join; COLLATE yok |
| P3 | `00c` KISMI LINEEXP | OK |
| P4 | O50 AFL + O51 STG + O59 TTK dump | FRK master hazır |
| P5 | O60 güvence iade dump | yoksa D2/E610 **ATLA** |
| P6 | `28_DEPLOY_597` + 590 `10→11→13→12→19` | R15 adopt `IOCODE<>0`; R20 TAM close |
| P7 | `613` v6 + `00e` (`MIG_613_ERR`) | open-debt only |
| P8 | Log % | energy log < %85 |

```text
CTAS dump → 00b/00c/IX → REF/MASTER/AGR/READING
  → MAP → 571 → 581 → 575
  → 590_ALL → [20b NCIX OFF] → 597_ALL → GATE → 20c
  → [probe bad_map] → E610? → 35 → 611 → 611b → 613
  → 40 → 92 → [92 DV / 93 FEE] → V95/99/97 → 90
```

---

## 1) EXEC zinciri (operatör)

| Adım | Ne | Komut / dosya | Kabul |
|------|-----|---------------|--------|
| A | Setup | `00_log` `00_map` MAP copy `00_abys` `01_linenr` | — |
| B1 | INV | `SP_MIGRATE_LS005_INVOICE` | OK |
| B2 | IL | `SP_MIGRATE_LS005_INVLINES` | OK |
| B3 | Debt PT | `SP_MIGRATE_LS005_DEBT_PAYTRANS` | OK (**O14 ile birlikte yazma**) |
| C | Eksilten | `SP_MIG_590_ALL @CLEAN=1` (deploy 10→11→**13**→12→19) | E590G PASS |
| D0 | NCIX | `20b` INV+PT **OFF** | disabled > 0 |
| D | Tahsilat | `SP_MIG_597_ALL @BatchSize=250000` | E597G **GATE_PASS** |
| D1 | Probe | bad_map IOCODE=0 = **0** (aşağı) | >0 → `20e` → ALL **`@CLEAN=0`** |
| D2 | NCIX | `20c` rebuild | disabled = 0 |
| D3 | TYPE110 | `SP_MIG_GUVENCE_IADE_ALL` | yalnız O60 var |
| E | Bank | `35_bankref…` DRY=1→0 | JOIN-only DRY |
| F | Plan | 611 + 611b | — |
| G | Split | `50e` / 613 **open-debt** | `pending_open_debt→0` |
| H | IPP | `40_…pay_apply` DRY=1→0 | — |
| I | STG | `90_afl_frk/92_stg…` DRY=1→0 | AFL_OPEN dokunma |
| J | DV | `92_INV_DV_FROM_INCOME_HEAL` DRY=1→0 | TYPE109+111 |
| K | Fee | `93_AGR_FEE_COLLECTED_HEAL` DRY=1→0 | 109+86 |
| V | FRK | `95` → `99` → `97 @OnlyDiff=1` | kabul bandı |
| Z | Log | `SP_MIG_LOG_STATUS` | FAIL yok / bilinen istisna |

SSMS sürücüler: `SSMS_CUTOVER_RUN.sql` · `SSMS_TAHSILAT_EXECS.sql` · `SSMS_POST_613_EXECS.sql`

---

## 2) Probe / kabul (kopyala-yapıştır)

```sql
-- G3 otorite (E597=FAIL paniği yok)
EXEC dbo.SP_MIG_597_GATE @AGR_ID = NULL;

-- Bad PAY map (0 beklenir). >0 → 20e; @CLEAN=1 YASAK
SELECT COUNT_BIG(*) AS pay_map_to_debt
FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
JOIN dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK) ON pt.LREF = m.ENERGY_LREF
WHERE m.OV_KIND = 'PAY_PT' AND m.ENERGY_LREF IS NOT NULL AND pt.IOCODE = 0;

SELECT
  SUM(CASE WHEN IOCODE <> 0 THEN 1 ELSE 0 END) AS pt_pay,
  SUM(CASE WHEN IOCODE = 0 THEN 1 ELSE 0 END) AS pt_debt
FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
WHERE ISNULL(CANCELED,0)=0;
-- pt_pay ≈ LS_OV_PAY_PT (~66M); map filled ≈ pt_pay

-- 613
-- pending_open_debt → 0  (50e / SSMS_POST step 0)

-- FRK
EXEC dbo.SP_AGR_FRK_ALL @Agr=NULL, @OnlyDiff=1, @WriteTable=1, @ReturnResult=0;
```

Kapılar G1–G9: `NOTES_CUTOVER_DEV_PLAN` §2F.

---

## 3) Paket / patch / yasak

| Tür | Ne | Cutover zinciri |
|-----|-----|-----------------|
| **PAKET** | 590/597 ALL, E610, 35/40/92 STG, 92 DV, 93 FEE, 95/97/99 | EVET |
| **PATCH** | `91*` residual, `91f–91i` AFL heal, hotfix/03–04 | KAPİ sonrası / kirli DB — **FULL zincire koyma** |
| **TEST YASAK** | `98_TEST_*` | Canlıda **ÇALIŞTIRMA** |
| **AÇIK KOD** | O20 ASIM gecikme; mahsup IL 162/1936 | Heal ile “çözüldü” sayma |

AFL residual (kirli DB): `90_afl_frk/NOTES_AFL_HEAL_TEST_20260811.md` — DryRun=1 önce.

---

## 4) Kill / resume

| Durum | Aksiyon |
|-------|---------|
| Plan boşa + veri güvenli | Cancel; resume script |
| 597 bad map / LOADED takılı | Probe → `20e` → ALL **`@CLEAN=0`** |
| `E597=FAIL` + sonra `E597G=PASS` | Otorite GATE |
| 613 orta | `50e_613_RESUME_OPEN_DEBT_ONLY` — borçsuz AGR yok |
| CXSYNC / DOP 48 | `MAXDOP 8`; Implicit OFF; NCIX kapalı mı |
| Log %90+ | `BACKUP LOG` / grow — koşuyu durdur |

---

## 5) Spot (zorunlu)

| Spot | Ne bak |
|------|--------|
| AGR **3** | TAM + TYPE92 → MAIN CLOSED |
| AGR **412056** | ASIM + emanet mahsup (162/1936) |
| INV **66081785** | CANCEL_REV |
| INV **147401407** / AGR 1200078 | DV: TL+DV=GT; TAH TOTAL=GT−DV |
| TTK grain | `ACCOUNT_ID = INV.ABYS_ACCOUNT_ID` — **LREF≠ACCOUNT** |

---

## 6) Gün sonu

- [ ] G1–G9 + spot yeşil veya bilinen residual listede  
- [ ] `prodREADY_*` değişiklik → `_sync_snapshot` → `_deploy_195`  
- [ ] `_tmp` heal pakete karışmadı  
- [ ] Backlog R* durumu güncellendi (`NOTES_REVIZYON_BACKLOG`)  
