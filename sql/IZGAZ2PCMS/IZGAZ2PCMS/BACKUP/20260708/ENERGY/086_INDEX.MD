# prodREADY_ENERGY3007 — INDEX

CTAS3007 dump → izgazMGR → ENERGY cutover runbook.

**Tam çıkış envanteri:** [EXIT_MAP.md](EXIT_MAP.md) (ÖNKOŞUL master/HHD + EVET cutover + YOK/DIAG gap)

| # | Dosya | Amaç | Todo |
|---|-------|------|------|
| — | Önkoşul master/HHD | 111…365, 521/524, 585 — `ProdIzgazMgr2Energy/` (EXIT_MAP §1–2) | pre-req |
| 00a | `00a_dump_transfer_audit.sql` | Dump row/IX/kalite taraması (LOADING tespiti) | dump-audit |
| 00ix | `00_ix_online_safe.sql` | ONLINE IX; BULK süren tabloları atlar | dump-ix |
| 00d | `00d_perf_bank_indexes.sql` | PAY_LREF / TAH ABYS / MAP KIND+AGR (597 bank hiz) | dump-ix |
| 00e | `00e_taksit_staging.sql` | 611/613/40 physical staging + IX (`MIG_*_STG_*`) | taksit-stg |
| 00e | `00e_mgr_cs_installment_indexes.sql` | MGR `CS_INSTALLMENT(AGR)` + `CS_IP(INSTALLMENT_ID)` | taksit-stg |
| 00e | `00e_energy_installment_plan_indexes.sql` | **P0** energy `IP(ABYS_AGREEMENT_ID)` — 613 scan engeli (6h kök neden) | taksit-stg |
| IX | `../00_pre_indexes.sql` | Tam IX seti (TAH dump bitince) | dump-ix |
| 00b | `../prodREADY_ENERGY/00b_align_mgr_varchar.sql` | Dump sonrası OV nvarchar→varchar | dump-prep |
| 00c | `../prodREADY_ENERGY/00c_enrich_mgr_kismi_lineexp.sql` | KISMI LINEEXP gelir adı | dump-prep |
| 00 | `00_izgazmgr_gate_checkpoint.sql` | Manifest + kolon + LREF + PAY_PAID_GAP + SUM checkpoint | mgr-gate |
| 01 | `01_PILOT_SPOT.md` | Wizard tek-AGR `pilotEnergyChain` | pilot-spot |
| 05 | `05_collation_cp1254.sql` | energy DB CP1254 (sqlcmd -I) | collation |
| 05b | `05b_columns_cp1254.sql` | energy kolon CP1254 | collation |
| 05c | `05c_izgazmgr_collation_cp1254.sql` | izgazMGR DB+kolon CP1254 | collation |
| 10 | `10_setup_and_map.sql` | log/map/abys/linenr + MAP copy + SP deploy pointer | energy-setup |
| 10f | `10f_DEPLOY_FINANCIAL_SP.sql` | Finansal SP checklist + varlık kontrol (deploy sqlcmd) | deploy |
| 20 | `20_main_load_571_581_575.sql` | 571 → 581 → 575 (`NULL`/`>0`/`-1`) | main-load |
| 30 | `30_overlay_590_597.sql` | 590_ALL → 597_ALL (`NULL`/`>0`/`-1`) | overlay |
| 30e | `30_EXEC_FINANCIAL_CHAIN.sql` | Açık EXEC: 571→597→611→613 (`NULL`/`>0`/`-1`) | exec |
| 30c | `30c_EXEC_FULL_CHAIN.sql` | **PROD FULL:** 571→597 `@AGR_ID=NULL` (+00d index guard) | exec-full |
| 30b | `30b_EXEC_NO_AGR_CHAIN.sql` | NO_AGR: 571→575→590→597 `@AGR_ID=-1` (FULL sonrası gerekmez) | no-agr |
| 36 | `36_backfill_null_agr_owner.sql` | **KULLANMA (primary değil)** — opsiyonel diag backfill | no-agr |
| 35 | `35_bankref_resolve_abys.sql` | Bank fix (`NULL`/`>0`/`-1`) | bankref |
| 35b | `35b_fix_bankref_*.sql` | (opsiyonel) tek-AGR re-apply | bankref-pilot |
| 40 | `40_installment_plan_pay_apply.sql` | O57 → INST PAID + tahsilat CROSSREF + CLOSED | post-taksit-close |
| 50 | `50_post_taksit_close_afl.sql` | 611/613 + 92 + AFL checklist | post-taksit-close |
| 50e | `50e_TAKSIT_EXECS.sql` | EXEC sırası: 611→wire→613→40 (operator) | post-taksit-close |
| 90 | `90_check_queries.sql` | Delta + taksit + FRK soft | validate |
| 91 | `91_debt_pt_dup_cleanup.sql` | DUP_2X soft-cancel (CP=1 asla KEEP) | **PATCH** residual |
| 91b | `91b_false_installment_plan_ref_cleanup.sql` | FALSE_REF: yan fatura `INSTALLMENT_PLAN_REF` temizle (kanonik=`plan.INVOICE_REF`) | **PATCH** residual |
| 91c | `91c_tah_crossref_paid_detect.sql` | Tespit: borç PAID &lt; LEAST(SUM tahsilat, PAYABLE) | **PATCH** diag |
| 91d | `91d_debt_paid_sync_from_tah.sql` | Heal: PAID ← tahsilat toplamı (cap PAYABLE); opsiyonel CLOSED | **PATCH** residual |
| — | `RUN_ORDER.sql` / `MANUAL_CHECKLIST.txt` / `README.md` / `EXIT_MAP.md` | Operatör sırası + envanter | — |
| — | [`../PAKET_PATCH_HIZALAMA.md`](../PAKET_PATCH_HIZALAMA.md) | PAKET vs PATCH vs AÇIK KOD | hizalama |
| — | [`../HOTFIX_ANLIK_ENVANTER.md`](../HOTFIX_ANLIK_ENVANTER.md) · [`../patch/README.md`](../patch/README.md) | Hotfix / residual / TEST yasak | patch |

**PAKET validate (cutover sonrası):** `90_afl_frk/95` → `99` → `97 @OnlyDiff=1`  
**PAKET deploy:** `../prodREADY_ENERGY/28_DEPLOY_597.sql` (v5) · E610 `60→69` (O60)  
**AÇIK (heal yok):** `NOTES_CANLI_AKTARIM_REV_20260807` — O20 ASIM · TAM MAIN · mahsup IL

SP gövdeleri: [../prodREADY_ENERGY/](../prodREADY_ENERGY/) (overlay) · [../../ProdIzgazMgr2Energy/prodENERGY/](../../ProdIzgazMgr2Energy/prodENERGY/) (migrate)
Oracle CTAS: [../../oracleCTAS3007/](../../oracleCTAS3007/)
