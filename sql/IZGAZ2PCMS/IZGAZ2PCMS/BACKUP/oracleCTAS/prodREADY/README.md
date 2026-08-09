# oracleCTAS / prodREADY — Oracle CTAS (MAP) + sağlam log

## Log (zorunlu)

| Ne | Nerede |
|----|--------|
| Canlı satır | `DBMS_OUTPUT`: `YYYY-MM-DD HH24:MI:SS \| Oxx \| STATUS \| ...` |
| Kalıcı tablo | `MIGRATION.MIG_CTAS_LOG` |
| Özet | `@99_log_status.sql` |
| Dosya | `tee logs/01_oracle_ctas/Oxx_yyyymmdd_hhmm.log` |

STATUS: `START` · `OK` · `FAIL` · `GATE_PASS` · `GATE_FAIL` · `INFO`

**GATE_FAIL / FAIL → dur, dump yok.**

## Sıra

```text
O0 (session+log) → O0b → O10 → O11 → O12 → O13 → O14
→ O20 → O27★ → O30 → O32 → O35★ → O40? → O41★ → O50 → O51
→ O52 → O53 → O54 → O55 → O56 → @99_log_status.sql
→ dump (LS_* + LS_OV_* + LS_STG_INV_PAY_CLOSE + senaryo ailesi)
```

O51 `LS_STG_INV_PAY_CLOSE`: MAIN grain ara tablo (AFL + PAY_PT + DEBT_PAID) → energy `INVOICE.LREF` join ile CLOSED/LPD/PAID temizligi.

Faz2 senaryo ailesi (wizard grain; MAP yok): O52–O56. Matris: `SCENARIO_MAP.md`.

Sonraki: `prodEnergy/prodREADY_ENERGY/` + tek-AGR wizard `/staging/tahsilat`.

## Manuel takip

| Dosya | Ne |
|-------|-----|
| `MANUAL_CHECKLIST_ORACLE.txt` | Adım adım checkbox (saat/sonuç/cnt) |
| `CHECK_QUERIES_ORACLE.sql` | Ara/kapanış spot SELECT |
| `SCENARIO_MAP.md` | Senaryo → tablo (PAYMENT/EKSILTEN/MAHSUP/TAKSIT…) |
| `../../CUTOVER_MANUAL_CHECKLIST.txt` | Oracle+Dump+Energy tek dosya |

## Model

- Overlay energy: sentetik INT LREF yok → `SRC_KEY` + `LS_OV_ID_MAP`
- Senaryo diag ailesi (O52–O56): **doğal ID**, MAP/SRC_KEY yok
- `CURID=160`, `LINENR`+`LINENR_SRC`, FORCE PARALLEL 56
- Detay: `DESIGN_MAP.txt`
