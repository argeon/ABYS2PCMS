# oracleCTAS3007 — Prod CTAS (eksiksiz / pilot-hardened)

Tam envanter: **[INDEX.md](INDEX.md)** · Dump: **[DUMP_MANIFEST.txt](DUMP_MANIFEST.txt)** · Pilot: **[PILOT_FINDINGS.md](PILOT_FINDINGS.md)**

Bu klasörde **yalnızca `00_run_all.sql` / `00_run_pilot_overlay.sql` zinciri** vardır. Çalıştırılmayan SQL’ler: **`_skip/`**.

## Tam sıra (FULL)

```text
O0 → O0L → O0b(FULL)
→ Faz A: LS_FLAT…SPEFEE_ADD → LS_PROJECT → LS_PROJECTLINE
→ O09 → READING → SYNTH → HHD → HHD_GATE → KFACTOR → ADJUSTMENT → SPEFEE
→ O10 → O11 → O12 → O13 → O14
→ O20 → O27★ → O30 → O32 → O34★★ → O33★★ → O14b★★ → O35
→ O41★ → O50 → O51 → O52 → O53 → O54 → O55 → O56★★ → O57★★ → O58★★
→ O59 → O60 → O98 IX → O99 log
→ dump (DUMP_MANIFEST.txt)
```

```bash
sqlplus user/pass@SMS @00_run_all.sql
```

## Pilot / örnek AGR (5 saatlik FULL yerine)

```text
@@00_session_parallel.sql
@@00_mig_ctas_log.sql
@@00_mig_param_pilot.sql      -- AGR listesi (197168, 5727, …)
-- LS_INVOICE yoksa: @@10 @@11 @@12 @@14
@@00_run_pilot_overlay.sql    -- O30→O41 (bank/makbuz/iptal)
→ dump ilgili AGR satırları veya wizard pilotDumpMgr
→ Energy SP_MIG_597_ALL @AGR_ID=…
```

`MIG_PARAM.AGR_ID` doluysa O10/O11/O30 yalnız o sözleşmeler. Overlay tablolar **pilot-scope** olur — prod full dump için `@@00_mig_param_full.sql` + `@@00_run_all.sql`.

## 3007’de tamamlananlar

| Konu | Adım |
|------|------|
| INSTALLMENT ref | O11 `NVL(acc,aa)` |
| PAY_PT PAID + banka/makbuz/XTYPE | O34 |
| TAH_INV EXPLAIN + BANK/LPD | O30 CTAS + O34 MERGE |
| INV CLOSED / LPD / BANK | O33 |
| DEBT_PT final PAID/BANK | O14b |
| MIG_PARAM AGR filtre (opsiyonel) | O10/O11/O30 |
| AFL AS_OF = SYSDATE | O50 |
| Taksit açık+kapalı | O56 |
| Plan satır ödemeleri | O57 |
| Pilot parity gate (TAH bank kol) | O58 |
| PAYMENT BANK_RECORD_REF | O52 |
| Iptal PAY → PAY_PT CANCELED=1; waterfill yalniz gecerli | O30 (2026-08-02c) |
| Waterfill-only (ops) | `_skip/31_…` (O30 ile sync) |
| TAH_LOG soft/diag (ops) | `_skip/30_HOTFIX_…` / `_skip/40_…` |
| WHENEVER + log standardı | tüm core SQL |
| Spot check | `_skip/CHECK_QUERIES_ORACLE.sql` |

## Log

`MIG_CTAS_LOG` + `DBMS_OUTPUT`. **GATE_FAIL → dump yok.**

## Sonraki

1. Dump → izgazMGR (`DUMP_MANIFEST.txt`) + `00b_align_mgr_varchar.sql`
2. Energy: deploy `20/21/22/29` (QI ON) → `SP_MIG_597_ALL`
3. Cutover: **[../prodEnergy/prodREADY_ENERGY3007/](../prodEnergy/prodREADY_ENERGY3007/)**
4. Wizard `/staging/tahsilat` tek-AGR spot (pilotEnergyChain)
