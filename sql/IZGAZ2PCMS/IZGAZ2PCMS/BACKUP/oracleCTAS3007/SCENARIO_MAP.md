# Senaryo → tablo matrisi (oracleCTAS3007)

Wizard (`/staging/tahsilat`) ile aynı grain. Overlay: MAP/SRC_KEY. Senaryo ailesi: **doğal ABYS ID**.

| Senaryo | Oracle tablo | Kaynak | Not |
|---------|--------------|--------|-----|
| Makbuz | `LS_PAYMENT` | O52 ← `LS_OV_PAY_PT` PAY + ALLOC_RN=1 | BANK_RECORD_REF dolu (3007) |
| Alloc | `LS_OV_PAY_ALLOC` | O30 | waterfill |
| Tahsilat PT | `LS_OV_PAY_PT` | O30 + **O34** | PAID/banka/LPD/XTYPE |
| Kapama adayı | `LS_STG_INV_PAY_CLOSE` | O51 | Energy apply |
| Açık borç | `LS_AFL_OPEN_DEBT` | O50 | FRK master |
| Fatura kapama patch | `LS_INVOICE` | **O33** | CLOSED/LPD/BANK |
| Debt PAID overlay | `LS_OV_DEBT_PAID_UPD` | O32 | + BANKREF (3007) |
| Tam eksilten | `LS_EKSILTEN` | O53 ← EKS_CLASS TAM | |
| Kısmi eksilten | `LS_PARTIAL_EKSILTEN` | O53 ← KISMI | |
| ASIM | `LS_OV_EKS_SKIP` | O20 | aile dışı |
| Artıran / Emanet | `LS_ARTIRAN` / `LS_EMANET` | O54 | |
| Mahsup | `LS_MAHSUP` | O55 | |
| Taksit hesap | `LS_TAKSIT` | **O56** | açık+kapalı (balance durum) |
| Taksit satır ödeme | `LS_INSTALLMENT_PLAN_PAY` | **O57** | INST_NR PAID kaynağı |

## Dump (izgazMGR) — zorunlu set

```text
LS_INVOICE, LS_INVLINES, LS_DEBT_PAYTRANS,
LS_OV_PAY_ALLOC, LS_OV_PAY_PT, LS_OV_TAH_INVOICE, LS_OV_DEBT_PAID_UPD,
LS_OV_ID_MAP, LS_AFL_OPEN_DEBT, LS_STG_INV_PAY_CLOSE,
LS_PAYMENT, LS_EKSILTEN, LS_PARTIAL_EKSILTEN, LS_ARTIRAN, LS_EMANET,
LS_MAHSUP, LS_TAKSIT, LS_INSTALLMENT_PLAN_PAY
(+ CS_INSTALLMENT / CS_INSTALLMENT_PLAN dump — Energy 611)
```

## Energy mapping (özet)

| CTAS | Energy |
|------|--------|
| O11/O12 | 571 / INVLINES |
| O14 | 575 borç PT |
| O30/O34 | 597 tahsilat overlay |
| O32/O33 | CLOSED + LPD + banka wire |
| O50 | FRK / AFL |
| O51 | 92 close apply |
| O56/O57 | 611 plan + 613 split + satır PAID |
