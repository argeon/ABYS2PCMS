# Zorunlu revizyon backlog — atlama YASAK

**Kural:** Canlıda öğrenilen fix `_tmp`’te kalmaz. Aynı gün `prodREADY_*` + snapshot sync + 195 kopya.  
**Bu cutover’da kaçanlar** aşağıda; kapanmadan “DONE” yazma.

Son güncelleme: 2026-08-09 (R07–R11 gömüldü)

---

## HARD RULES (her deploy’da)

1. `#temp` yok → `MIG_*_STG_*`
2. Hot path MGR MAP UPDATE yok → `20a` offline
3. Filtered IX / debt: `IOCODE = 0` (`ISNULL(IOCODE,0)` yasak)
4. Scalar `FN_SAFE_*` hot path yok
5. `IMPLICIT_TRANSACTIONS OFF`; dış BEGIN TRAN yok
6. FULL: 20b NCIX OFF → load → GATE → 20c / 572
7. Overlay sadece `*_ALL`
8. `sqlcmd -f 65001`
9. `RAISERROR` parametresi: sadece INT/string değişken — **BIT / CAST ifade YASAK**
10. Ağır UPDATE/INSERT: `OPTION (MAXDOP 8)` (sunucu max 48 CXSYNC öldürür)
11. 613 kuyruk: **sadece açık borçlu AGR** (`pending_open_debt`)
12. Paket yolu: `prodREADY_*` → `_sync_snapshot` → 195 `MIGRATION_SCR_*` (+ `SRC_prodREADY_*`)
13. 613 canonic: `prodREADY_ENERGY3007/613_INSTALLMENT_DEBT_SPLIT__pilot_agr.sql` (v6+)

---

## BACKLOG (kod — ana dosyaya göm)

| ID | Durum | Dosya | İş |
|----|--------|-------|-----|
| R01 | DONE | `20_597_INSERT.sql` | PAY hint MERGE OUTPUT + MAP_OUT; batch-first FORCE ORDER; adopt |
| R02 | DONE | `22_597_GATE.sql` | CROSSREF `IOCODE<>0`; MAXDOP 8 |
| R03 | DONE | `50e_TAKSIT_EXECS.sql` | open-debt pending filter |
| R04 | DONE | `50e_613_RESUME_OPEN_DEBT_ONLY.sql` | resume-only script |
| R05 | DONE | `40_…pay_apply.sql` | RAISERROR BIT → `@DryRunInt` |
| R06 | DONE | `40_…pay_apply.sql` | UPDATEs: `IOCODE=0`, `INST_NR>0`, `OPTION (MAXDOP 8)` |
| R07 | DONE | `613…v6` + `00e` + `50e` | MAXDOP/IOCODE; `MIG_613_ERR`; CATCH→tablo; canonic 3007 path |
| R08 | DONE | `NOTES_597_OPS_HEAL.md` | E597 FAIL vs E597G GATE_PASS |
| R09 | DONE | `20d_597_LOADED_MAP_HEAL.sql` + notes | LOADED↔MAP NCIX-off kalıbı |
| R10 | DONE | `35_bankref_resolve_abys.sql` | `@DryRunInt`; MAXDOP 8; `IOCODE=0`; dış TRAN kaldırıldı |
| R11 | DONE | `92_stg_inv_pay_close_apply.sql` | physical `MIG_92_STG_*`; MAXDOP 8; `IOCODE=0` |
| R12 | TODO — **cutover bitince** | 35 / 40 / 92 (+ opsiyonel 20c) | Script → `CREATE OR ALTER PROCEDURE`; `10f` checklist; `SSMS_POST` sadece `EXEC @DRY_RUN,@AGR_ID` |
| R13 | DONE (2026-08-09) | `35_bankref…` | DRY sayım: scalar `FN_MIG_RESOLVE_BANK_LREF` → `LS_BANK.ABYS_ID` JOIN (RBAR öldürdü) |

### R12 not (cutover bitince)

- Amaç: sunucu gövdesi = paket; DRY/APPLY parametre; “hangi dosya / DRY=0 unuttuk” yok.
- Kalıp: `NN_xxx.sql` → `SP_MIG_35_BANKREF_RESOLVE` / `SP_MIG_40_IPP_APPLY` / `SP_MIG_92_STG_CLOSE`.
- Driver: `EXEC … @DRY_RUN=1|0, @AGR_ID=NULL|-1|>0`.
- Mid-cutover’da **yapma** — 35/92 script ile bitsin; sonra taşı.

---

## Bu aktarımda yapılan hatalar (tekrarlama)

1. Fix’i sadece canlı/session’da bırakmak → sonraki koşu eski gövde  
2. Snapshot sync unutmak → 195 eski dosya  
3. 613’te 81k boş tur (borçsuz AGR)  
4. DOP 48 + CXSYNC → “yavaşladı” panik  
5. GATE IOCODE=0 false FAIL  
6. `RAISERROR(..., @BIT)` / `CAST` parametre  
7. `_tmp` heal’i paket sanmak  
8. ALL FAIL log’una bakıp işi bitmiş saymamak / GATE’i atlamak  
9. Revizyonu “sonra” deyip atlamak  

---

## Kapanış checklist (cutover END öncesi)

- [x] R06–R11 kodlandı  
- [x] `_sync_snapshot.ps1` (BACKUP/20260708) — 2026-08-09  
- [x] 195 `ENERGY` + `SRC_prodREADY_*` + `SRC_90_afl_frk` robocopy  
- [ ] `28_DEPLOY_597` (GATE MAXDOP sonrası — opsiyonel bu cutover)  
- [ ] 613 SP deploy (`00e` + `613…v6`) — sonraki 613 koşusunda  
- [ ] G1–G9 kabul kapıları (`NOTES_CUTOVER_DEV_PLAN_20260809.md`)  

---

## Referans

- Plan: `NOTES_CUTOVER_DEV_PLAN_20260809.md`  
- Ops heal: `NOTES_597_OPS_HEAL.md`  
- Perf: `NOTES_597_PERF_SAFE.md`  
- Exit: `../prodREADY_ENERGY3007/EXIT_MAP.md`  
