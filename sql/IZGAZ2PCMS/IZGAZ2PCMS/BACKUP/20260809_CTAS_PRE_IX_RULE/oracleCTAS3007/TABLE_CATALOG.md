# CTAS3007 TABLE CATALOG — STG / DUMP / DIAG

Sınıf etiketleri: **DUMP** (izgazMGR), **STG_KEEP**, **STG_DROP**, **DIAG**.
Dump listesi = yalnız DUMP → [`DUMP_MANIFEST.txt`](DUMP_MANIFEST.txt).
Cleanup = [`99_stg_cleanup.sql`](99_stg_cleanup.sql). Transfer IX = [`98_transfer_indexes.sql`](98_transfer_indexes.sql).

| Adım | Tablo | Sınıf | Tüketici | Not |
|------|-------|-------|----------|-----|
| 09 | `MIG_ACCRUE_TYPE_MAP` | STG_KEEP | SYNTH, O11 | Seed; dump yok |
| 00L | `MIG_CTAS_LOG` | STG_KEEP | O99 | |
| 10 | `STG_INV_ACC_INC` | STG_KEEP | O11–O14 | O11 sonrası yeniden koşu yoksa DROP serbest |
| — | `STG_TARIFF_MAP` | STG_DROP* | LS_AGREEMENT | *sonra kullanılmıyorsa |
| LS_READING | `STG_RD_*` | STG_DROP | MAIN sonrası | Script sonu DROP |
| LS_READING | `LS_READING` | DUMP | 521, O11, MSTR | + `ABYS_ACCRUE_TYPE_ID` |
| LS_READING_SYNTH | `STG_RD_SYNTH_GAP` | STG_DROP | INSERT sonrası | |
| LS_HHD_MSTR | `TMP_HHD_TRAN_KEY`, `LS_OV_HHD_MSTR_EOD/ORPHAN` | STG_DROP | MSTR+MAP+READ_NO sonrası | |
| LS_HHD_MSTR | `LS_OV_HHD_MSTR`, `LS_OV_HHD_TRAN_MAP` | DUMP | 524 | + `ROUTE_GRP` / `IS_SYNTH` |
| LS_HHD_MSTR | `LS_OV_HHD_MSTR_SKIP` | DIAG | GATE | Opsiyonel dump |
| O11 | `LS_INVOICE` | DUMP | 571 | TYPE/EXPLAIN/READ_TRANSREF |
| O12–O57 | `LS_*` / `LS_OV_*` | DUMP | Energy | Manifest |
| O30 | `TMP_MIG_ACC`, `TMP_PAY_CANCEL`, … | STG_DROP | O30 sonu / 99 | |
| O33 | `TMP_O33_*` | STG_DROP | O33 sonu / 99 | |
| O51 | `TMP_STG_PAY_AGG`, `TMP_STG_BANK_NM` | STG_DROP | O51 sonu / 99 | |
| O32 | `LS_OV_INV_PAY_GAP` | DIAG | Opsiyonel | |
| O61 | `LS_CUSTODY` | DUMP | Recon (emanet/borç); ENERGY zorunlu yük değil | |
| _skip/40 | `LS_OV_TAH_LOG` | DIAG | Opsiyonel | |

## Okuma zinciri sırası

1. `09_mig_accrue_type_map.sql`
2. `LS_READING.sql` (organik + ABYS_ACCRUE_TYPE_ID; STG_RD DROP)
3. `LS_READING_SYNTH.sql`
4. `LS_HHD_MSTR.sql` → GATE → DIAG
5. `11_ls_invoice.sql` (map TYPE/EXPLAIN; READ_TRANSREF ← LS_READING)
6. Dump DUMP tabloları → `98_transfer_indexes` / 520–524 / `00_pre_indexes`

Gate FAIL ise STG_DROP yok (`99_stg_cleanup` çalıştırma).
