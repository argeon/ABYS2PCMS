# Cutover — tek sayfa runbook

**Paket:** `prodREADY_ENERGY` + `prodREADY_ENERGY3007` + `90_afl_frk`  
**Canlı kök:** `sql/IZGAZ2PCMS/IZGAZ2PCMS/prodEnergy/`  
**Sunucu paket:** 195 `C:\www\MIGRATION_SCR_20260708` (`_deploy_195.ps1`)  
**Kural:** GATE_FAIL / FAIL → **DUR**. Overlay yalnız `*_ALL`. `sqlcmd -f 65001`.  
**CTAS:** FAIL → baştan `00_run_all` **YASAK** — [`NOTES_CTAS_NO_RESTART.md`](../../BACKUP/oracleCTAS3007/NOTES_CTAS_NO_RESTART.md)

Detay: [`EXIT_MAP.md`](../prodREADY_ENERGY3007/EXIT_MAP.md) · [`NOTES_CUTOVER_DEV_PLAN_20260809.md`](NOTES_CUTOVER_DEV_PLAN_20260809.md) · [`NOTES_REVIZYON_BACKLOG.md`](NOTES_REVIZYON_BACKLOG.md) · [`PAKET_PATCH_HIZALAMA.md`](../PAKET_PATCH_HIZALAMA.md)

---

## −1) Oracle CTAS (dump öncesi)

```text
cd MIGRATION_SCR_20260708\CTAS
sqlplus ... @00_RUN_ALL.SQL
```

- Ad: `NNN_NAME_Vnn.SQL` · map: `_ctas_nnn_map.ps1`
- FAIL → o NNN’den devam — baştan RUNALL **YASAK**
- [`NOTES_CTAS_NO_RESTART.md`](../../BACKUP/oracleCTAS3007/NOTES_CTAS_NO_RESTART.md)

| # | Kontrol | Beklenen |
|---|---------|----------|
| C0 | `00_RUN_ALL` + NNN_NAME_VER | tek orch |
| C1 | TEMP / undo / TS | ORA-01652 yok |
| C1b | DV: `130–132` TOTAL_DV + `@925_DIAG_DV…` | kod diskte **OK**; koşuda BAD_DV0=0 |
| C1c | GUAR `026` 23032 hariç | kod **OK**; eskiyse @@026 + spot 4346 |
| C1d | O20/O30 | tah∈(1,3,10,41) + `LS_OV_TAH_INVLINES` — kod **OK** |
| C2 | GATE_EKSILTEN + GATE_TAHSILAT PASS | dump kapısı |
| C3 | FAIL sonrası | baştan RUNALL **yok** |

---

## 0) Önkoşul (FULL Energy başlamadan)

| # | Kontrol | Beklenen |
|---|---------|----------|
| P1 | Master / AGR / HHD 521–524 dolu | EXIT_MAP §1–2 |
| P2 | Dump + `00b` + `00i` + **`SP_MIG_IX_MGR_ENSURE` → `PRECHECK`** | bare join; R16; R22 FAIL=DUR |
| P3 | `00c` KISMI LINEEXP | OK |
| P4 | O50 AFL + O51 STG + O59 TTK dump | FRK master hazır |
| P5 | O60 güvence iade dump | yoksa D2/E610 **ATLA** |
| P6 | `28_DEPLOY_597` + 590 `10→11→13→12→19` + deploy `26*` | R15 adopt; R20 TAM; R22 NCIX SP |
| P7 | `613` v6 + `00e` staging (`MIG_613_ERR`); IP IX = **611 sonrası** `SP_MIG_IX_IP_AGR` | open-debt only |
| P8 | Log % | energy log < %85 |

```text
CTAS dump → 00b/00c → EXEC IX_MGR_ENSURE → IX_PRECHECK
  → MAP → 571→572 → 581→582 → 575→576
  → 590_ALL → NCIX_DISABLE → 597_ALL → GATE → probe → NCIX_REBUILD
  → E610? → 35 → 611 → IX_IP_AGR → 613
  → 40 → 92 → [92 DV / 93 FEE] → V95/99/97 → 90
```

---

## 1) EXEC zinciri (operatör)

| Adım | Ne | Komut / dosya | Kabul |
|------|-----|---------------|--------|
| A | Setup | `00_log` `00_map` MAP copy `00_abys` `01_linenr` + deploy `26*` | — |
| A1 | IX gate | `SP_MIG_IX_MGR_ENSURE` → `SP_MIG_IX_PRECHECK` | FAIL=DUR |
| B1 | INV | `SP_MIGRATE_LS005_INVOICE` → **`SP_MIG_INVOICE_POST_INDEXES`** | OK |
| B2 | IL | `SP_MIGRATE_LS005_INVLINES` → **`SP_MIG_INVLINES_POST_INDEXES`** | OK |
| B3 | Debt PT | `SP_MIGRATE_LS005_DEBT_PAYTRANS` → **`SP_MIG_DEBT_PAYTRANS_POST_INDEXES`** | OK (**O14 ile birlikte yazma**) |
| C | Eksilten | `SP_MIG_590_ALL @CLEAN=1` (deploy 10→11→**13**→12→19) | E590G PASS |
| D0 | NCIX | `SP_MIG_597_NCIX_DISABLE` | disabled > 0 |
| D | Tahsilat | `SP_MIG_597_ALL @BatchSize=250000` | E597G **GATE_PASS** |
| D1 | Probe | bad_map IOCODE=0 = **0** (aşağı) | >0 → `SP_MIG_20E_BAD_MAP_HEAL` → ALL **`@CLEAN=0`** |
| D2 | NCIX | `SP_MIG_597_NCIX_REBUILD` | disabled = 0 |
| D3 | TYPE110 | `SP_MIG_GUVENCE_IADE_ALL` | yalnız O60 var |
| E | Bank | `EXEC SP_MIG_35_BANKREF_RESOLVE @DRY_RUN` | R12 |
| F | Plan | 611 + 611b → **`SP_MIG_IX_IP_AGR`** | — |
| G | Split | `50e` / 613 **open-debt** | `pending_open_debt→0` |
| H | IPP | `EXEC SP_MIG_40_IPP_APPLY @DRY_RUN` | R12 |
| I | STG | `EXEC SP_MIG_92_STG_CLOSE @DRY_RUN` | R12; AFL_OPEN dokunma |
| J | DV | `SP_MIG_INV_DV_FROM_INCOME` DRY=1→0 | TYPE109+111 |
| K | Fee | `SP_MIG_93_AGR_FEE_COLLECTED` DRY=1→0 | 109+86 |
| V | FRK | `SP_MIG_95_TTK_AFL_RAPOR` → `SP_MIG_99_AFL_EN_FRK` → `SP_AGR_FRK_ALL @OnlyDiff=1` | kabul bandı |
| Z | Log | `SP_MIG_LOG_STATUS` | FAIL yok / bilinen istisna |

SSMS sürücüler: `SSMS_CUTOVER_RUN.sql` · `SSMS_TAHSILAT_EXECS.sql` · `SSMS_POST_613_EXECS.sql` · plan: `NOTES_IX_SP_ORCH_PLAN_20260811.md`

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
| **AÇIK KOD** | ~~O20 ASIM / mahsup IL~~ → **DONE 2026-08-11** (CTAS+597); ~~DV/GUAR/FEE CTAS kod~~ → paket+195 ~07:57; kalan: O60/E610 TYPE110 + R21 Oracle/311 | Heal ile “çözüldü” sayma YASAK — kod/dump |

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
