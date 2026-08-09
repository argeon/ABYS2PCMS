# prodREADY_ENERGY3007 — Pilot spot (tek AGR)

CTAS3007 izgazMGR’de + gate PASS sonrası, full cutover öncesi.

**Aktif retest:** AGR `197168` — hızlı: `@00_mig_param_pilot` + `@00_run_pilot_overlay` + dump (bkz. `oracleCTAS3007/PILOT_FINDINGS.md` § Plan 197168). Dump sonrası: `00b_align_mgr_varchar` + `00c_enrich_mgr_kismi_lineexp` (KISMI LINEEXP gelir adı). MGR bank/makbuz NULL iken 597 koşturma.

## Wizard

1. `/staging/tahsilat` → AGR (ör. `943373`)
2. CleanBeforePilot = ON
3. **ENERGY’ye aktar** / `pilotEnergyChain` APPLY  
   (MGR zaten doluysa dump atlanabilir; Clean ENERGY zinciri yeterli)

## Beklenen summary / gap

| Alan | Beklenen |
|------|----------|
| `tahsilatPt` / `enPaytransTahsilat` | > 0 |
| `taksitPtInserted` veya ENERGY INST_NR | > 0 |
| `taksitTahsilatPt` / `taksitTahsilatUpdated` | > 0 (ödenen satır) |
| `FRK_AFL_OK` / MATCH | AFL ↔ ENERGY açık hizalı |
| `NO_LS_OV_PAY_PT` | olmamalı (CTAS dump var) |

## Spot SQL (energy)

```sql
DECLARE @Agr BIGINT = 943373;

-- Taksitli fatura + PAID/banka
SELECT inv.LREF, inv.CLOSED, inv.LASTPAIDDATE, inv.BANKREF, inv.BANK_RECORD_REF,
       inv.INSTALLMENT_PLAN_REF, inv.ABYS_INSTALLMENT_ID,
       pt.LREF PT, pt.INST_NR, pt.PAYTYPE, pt.PAYABLETOTAL, pt.PAID,
       pt.BANKREF PT_BANK, pt.BANK_RECORD_REF PT_REC, pt.LASTPAIDDATE PT_LPD, pt.XTYPE
FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
JOIN energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
  ON pt.INVOICEREF = inv.LREF AND ISNULL(pt.IOCODE,0)=0 AND ISNULL(pt.CANCELED,0)=0
WHERE inv.OWNERREF = @Agr AND ISNULL(inv.INSTALLMENT_PLAN_REF,0) > 0
ORDER BY inv.LREF, pt.INST_NR;

-- Tahsilat CROSSREF
SELECT debt.INST_NR, debt.PAID debtPaid, pay.PAID payPaid, pay.PAYTYPE,
       pay.BANKREF, pay.BANK_RECORD_REF, pay.LASTPAIDDATE, pay.XTYPE
FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
JOIN energy.dbo.LS_005_01_PAYTRANS debt WITH (NOLOCK)
  ON debt.INVOICEREF = inv.LREF AND ISNULL(debt.IOCODE,0)=0 AND ISNULL(debt.INST_NR,0)>0
JOIN energy.dbo.LS_005_01_PAYTRANS pay WITH (NOLOCK)
  ON pay.CROSSREF = debt.LREF AND ISNULL(pay.IOCODE,0)=1
WHERE inv.OWNERREF = @Agr;
```

## Pass kriteri

- Ödenen taksit satırlarında `debt.PAID ≈ PAYABLETOTAL` ve tahsilat `pay.PAID` dolu
- Hepsi ödendiyse `inv.CLOSED=1` + `LASTPAIDDATE`/`BANKREF` son taksit
- FRK: mig-scope açık borç ENERGY ile eşleşir

FAIL → full 571/590/597 yok; CTAS dump / O34 / O57 kolonları kontrol.
