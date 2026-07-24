# Oracle CTAS prod2 — energy-yakin staged FULL paket

Pilot `oracleCTAS/*.sql` dosyalarina dokunulmaz. Bu paket `prod/` yerine kullanilir.

## Stage haritasi

| # | Dosya | Uretir / yapar | Energy karsiligi |
|---|--------|----------------|------------------|
| 00 | `00_session_parallel.sql` | DOP session | — |
| 00b | `00_mig_param_full.sql` | `MIG_PARAM` bos | — |
| 10 | `10_stg_inv_acc_inc.sql` | `STG_INV_ACC_INC` | — (Oracle-only) |
| 11 | `11_ls_invoice.sql` | `LS_INVOICE` + `ABYS_ID` | `LS_005_01_INVOICE` (571) |
| 12 | `12_ls_invlines.sql` | `LS_INVLINES` + `ABYS_ID` | `LS_005_01_INVLINES` (581) |
| 13 | `13_ls_mig_agr_list.sql` | `LS_MIG_AGR_LIST` | LOOP driver |
| 14 | `14_ls_debt_paytrans.sql` | `LS_DEBT_PAYTRANS` | `LS_005_01_PAYTRANS` IOCODE=0 (575) |
| 20 | `20_ls_eksilten_overlay.sql` | `LS_OV_*` eksilten + AGR ix | 590 apply |
| 27 | `27_gate_eksilten.sql` | TAM↔IADE hard gate | — |
| 30 | `30_ls_tahsilat_overlay.sql` | `LS_OV_*` tahsilat + AGR ix | 597 apply |
| 40 | `40_ls_tahsilat_log.sql` | `LS_OV_TAH_LOG` | diagnostic |
| 41 | `41_gate_tahsilat.sql` | PAY_PT=ALLOC, NO_XREF=0 | — |

## Calistirma

```text
sqlplus ... @00_run_all.sql
# veya
.\00_run_all.ps1
```

## DOP (60c / 128GB EE)

- CTAS / index: **PARALLEL 52**
- Aggregate STG / AGR list: **PARALLEL 28**
- Stats degree: **32**

## Dump (Migratorv0 → izgazMGR)

Zorunlu tablolar:

- `LS_INVOICE`, `LS_INVLINES`
- `LS_MIG_AGR_LIST` (yeni)
- `LS_DEBT_PAYTRANS` (yeni — 575 yerine bulk)
- `LS_OV_*` (eksilten + tahsilat); log istege bagli

## Energy hiz notu

1. izgazMGR'de `adim3_verify_indexes.sql` + OV AGR index mirror
2. `adim_full_fatura_run`: DISTINCT yerine `LS_MIG_AGR_LIST`
3. 575: `LS_DEBT_PAYTRANS` INSERT…SELECT (INVOICE'dan turetmeyi atla)
4. 571/590/597: tip cast'ler NUMBER(12)/NUMBER(3) sayesinde sade

## Geri donus

- `prod/` eski paket oldugu gibi kalir
- Oracle: CTAS tablolari `PURGE` + `prod2` yeniden
