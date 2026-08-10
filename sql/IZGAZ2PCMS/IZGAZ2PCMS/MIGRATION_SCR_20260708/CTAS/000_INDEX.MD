# oracleCTAS3007 — CTAS INDEX (eksiksiz envanter)

Okuma/HHD (tahsilat öncesi veya paralel): `09_mig_accrue_type_map` → `LS_READING` → `LS_READING_SYNTH` → `LS_HHD_MSTR` → GATE → O11.
Katalog: `TABLE_CATALOG.md` · Dump: `DUMP_MANIFEST.txt` · Cleanup: `99_stg_cleanup.sql` · IX: `98_transfer_indexes.sql`

## Kural — Oracle INDEX / STATS

| Sınıf | Oracle INDEX + `GATHER_TABLE_STATS` |
|-------|-------------------------------------|
| **Zincir / staging** — aynı veya sonraki CTAS JOIN/MERGE/EXISTS | **Evet** (TMP_*, `LS_INVOICE`, OV feeders, O50→O51, …) |
| **Terminal DUMP** — yalnızca dump → izgazMGR; CTAS tüketici yok | **Hayır** (`ALTER TABLE … NOPARALLEL LOGGING` + RECON kalır) |

MSSQL IX: dump sonrası `00_pre_indexes` / 520. Dump öncesi join anahtarı: `98_transfer_indexes.sql` (ayrı).

## Çalıştırma sırası

| # | Dosya | Log | Ürettiği tablolar |
|---|--------|-----|-------------------|
| O0 | `00_session_parallel.sql` | — | session DOP 56 |
| O0L | `00_mig_ctas_log.sql` | — | `MIG_CTAS_LOG`, `P_MIG_CTAS_LOG` |
| O0b | `00_mig_param_full.sql` | O0b | `MIG_PARAM` (FULL — AGR filtre YOK) |
| O0b★ | `00_mig_param_pilot.sql` | O0b | `MIG_PARAM` örnek AGR (pilot overlay) |
| A01–A17 + A12b | `LS_FLAT`…`LS_SPEFEE_ADD` + `LS_BANK_ACC` | — | master CTAS (`SCHEMA_CTAS_ORDER` #1–16 + 11c) |
| A18 | `../oracleCTAS/LS_PROJECT.sql` | — | `LS_PROJECT` |
| A19 | `../oracleCTAS/LS_PROJECTLINE.sql` | — | `LS_PROJECTLINE` |
| O09 | `09_mig_accrue_type_map.sql` | — | `MIG_ACCRUE_TYPE_MAP` |
| RD | `LS_READING.sql` | — | `LS_READING` (+ABYS_ACCRUE_TYPE_ID) |
| RDs | `LS_READING_SYNTH.sql` | — | synth INSERT |
| HHD | `LS_HHD_MSTR.sql` | — | `LS_OV_HHD_MSTR`, TRAN_MAP |
| HHDg★ | `LS_HHD_MSTR_GATE.sql` | — | GATE v04 |
| KF | `LS_KFACTOR_VALUE.sql` | — | `LS_KFACTOR_VALUE` |
| AC | `LS_ADJUSTMENT_COEFFICIENT.sql` | — | `LS_ADJUSTMENT_COEFFICIENT` |
| SF | `LS_SPEFEE.sql` | — | `LS_SPEFEE` |
| O10 | `10_stg_inv_acc_inc.sql` | — | `STG_INV_ACC_INC` |
| O11 | `11_ls_invoice.sql` | O11 | `LS_INVOICE` (TYPE/EXPLAIN/READ_TRANSREF) |
| O12 | `12_ls_invlines.sql` | O12 | `LS_INVLINES` |
| O13 | `13_ls_mig_agr_list.sql` | — | `LS_MIG_AGR_LIST` |
| O14 | `14_ls_debt_paytrans.sql` | O14 | `LS_DEBT_PAYTRANS` (prefab) |
| O20 | `20_ls_eksilten_overlay.sql` | O20 | `LS_OV_EKS_*`, IADE/KISMI OV (`LS_OV_KISMI_INVLINES` dahil) |
| O27★ | `27_gate_eksilten.sql` | O27 | GATE |
| O30 | `30_ls_tahsilat_overlay.sql` | O30 | `LS_OV_PAY_ALLOC/PT` (iptal=`CANCELED=1`), TAH_INV EXPLAIN+BANK/LPD, DEBT_PAID, MAHSUP OV; MIG_PARAM filtre |
| O32 | `32_ls_ov_debt_paid_lastpaid.sql` | O32 | `LS_OV_DEBT_PAID_UPD`, `LS_OV_INV_PAY_GAP` |
| O34★★ | `34_ls_ov_pay_pt_bank_enrich.sql` | O34 | PAY_PT PAID+BANK+XTYPE + TAH_INV bank/LPD |
| O33★★ | `33_ls_invoice_close_bank_patch.sql` | O33 | INV CLOSED/LPD/BANK |
| O14b★★ | `14b_ls_debt_paytrans_rebuild.sql` | O14b | DEBT_PT final PAID/BANK |
| O35 | `35_ls_ov_id_map.sql` | O35 | `LS_OV_ID_MAP` |
| O41★ | `41_gate_tahsilat.sql` | O41 | GATE |
| O50 | `50_ls_afl_open_debt.sql` | O50 | `LS_AFL_OPEN_DEBT` |
| O51 | `51_ls_stg_inv_pay_close.sql` | O51 | `LS_STG_INV_PAY_CLOSE` |
| O52 | `52_ls_payment.sql` | O52 | `LS_PAYMENT` |
| O53 | `53_ls_eksilten_family.sql` | O53 | `LS_EKSILTEN`, `LS_PARTIAL_EKSILTEN` |
| O54 | `54_ls_artiran_emanet.sql` | O54 | `LS_ARTIRAN`, `LS_EMANET` |
| O55 | `55_ls_mahsup.sql` | O55 | `LS_MAHSUP` |
| O56★★ | `56_ls_taksit.sql` | O56 | `LS_TAKSIT` (açık+kapalı) |
| O57★★ | `57_ls_installment_plan_pay.sql` | O57 | `LS_INSTALLMENT_PLAN_PAY` |
| O58★★ | `58_gate_pilot_parity.sql` | O58 | GATE |
| O59 | `59_tuketim_tutar_kontrol.sql` | O59 | `TUKETIM_TUTAR_KONTROL` (tuketim+tutar recon) |
| O60 | `60_ls_ov_guvence_iade.sql` | O60 | `LS_OV_GUVENCE_IADE_*` (TYPE 110; ACCRUE14 tip20/12/40 + güvence gelir) + ID_MAP append |
| O61 | `61_ls_custody.sql` | O61 | `LS_CUSTODY` (register emanet/borç; PROBLEMATIC_CUSTODY; II_FIRM_PRM yok) |
| O99 | `99_log_status.sql` | — | özet |

★ hard gate · ★★ 3007 pilot

**Çalıştırılmayan SQL:** `_skip/` (O30h / 40 TAH_LOG, 31 waterfill-only, CHECK, diag_*).

## Dump zorunlu liste

`DUMP_MANIFEST.txt` — izgazMGR’ye aktarılacak tablolar.

## Doğrulama

- `@_skip/CHECK_QUERIES_ORACLE.sql`
- `@MANUAL_CHECKLIST_ORACLE.txt`
- `PILOT_FINDINGS.md` / `SCENARIO_MAP.md`

## Tam koşu (FULL — bastan)

```text
cd oracleCTAS3007
sqlplus user/pass@db @00_run_all.sql
```

(PROJECT: `../oracleCTAS/` relative — cwd = `oracleCTAS3007/`)

Snapshot: `20260708/CTAS` → `@00_RUN_ALL.SQL`

## Pilot overlay (örnek AGR)

```text
sqlplus user/pass@db @00_mig_param_pilot.sql
sqlplus user/pass@db @00_run_pilot_overlay.sql
```
