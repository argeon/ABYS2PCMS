# Senaryo → tablo matrisi (Faz2 CTAS / wizard grain)

Wizard (`/staging/tahsilat`) ile aynı grain; **MAP / SRC_KEY yok** (doğal ABYS ID).

| Senaryo | Oracle tablo | Kaynak | Not |
|---------|--------------|--------|-----|
| Makbuz | `LS_PAYMENT` | O52 ← `LS_OV_PAY_PT` PAY + ALLOC_RN=1 | Mahsup ayrı |
| Alloc | `LS_OV_PAY_ALLOC` | O30 (overlay) | Wizard live |
| Kapama adayı | `LS_STG_INV_PAY_CLOSE` | O51 | Energy 92 apply |
| Açık borç | `LS_AFL_OPEN_DEBT` | O50 | FRK master |
| Tam eksilten | `LS_EKSILTEN` | O53 ← EKS_CLASS TAM | ASIM yok |
| Kısmi eksilten | `LS_PARTIAL_EKSILTEN` | O53 ← EKS_CLASS KISMI | |
| ASIM | `LS_OV_EKS_SKIP` | O20 | Manuel; CTAS aile dışı |
| Artıran | `LS_ARTIRAN` | O54 ← INVOICE tip 3/10/41 | |
| Emanet | `LS_EMANET` | O54 ← ACCRUE=14 | |
| Eksilten-kapama | tip2 TAM / `LS_EKSILTEN` | O20/O53 | Wizard `iptalEmanet` KIND=EKSILTEN_CLOSE |
| Tahsilat iptal | tip9 / `PAY_PT.CANCELED` | O30 TMP_PAY_CANCEL | KIND=PAY_CANCEL |
| İptal→emanet | tip12 / ACCRUE14+tip9 | overlay dışı | KIND=CANCEL_EMANET |
| Emanet→borç mahsup | tip6/24 + `REF_DEPOSIT_*` | O30 MAHSUP_SRC | KIND=EMANET_MAHSUP; aynı emanet→çoklu fatura |
| Mahsup | `LS_MAHSUP` | O55 ← MAHSUP_SRC | |
| Taksit | `LS_TAKSIT` | O56 ← AFL T | 611 yazılmaz |

## Dump (izgazMGR)

```text
LS_PAYMENT, LS_EKSILTEN, LS_PARTIAL_EKSILTEN, LS_ARTIRAN, LS_EMANET,
LS_MAHSUP, LS_TAKSIT
(+ mevcut: LS_AFL_OPEN_DEBT, LS_STG_INV_PAY_CLOSE, LS_OV_*)
```

Index: `prodEnergy/00_pre_indexes.sql` (izgazMGR bloğu).

## Energy

Bu aile **INSERT etmez**. Kapama: `92_stg_inv_pay_close_apply.sql` (MIN UPDATE).
