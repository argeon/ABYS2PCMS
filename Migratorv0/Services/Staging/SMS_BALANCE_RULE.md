# SMS / ABYS bakiye kuralı (kritik)

## Gerçek bakiye
```text
SUM(CS_ACCOUNT_INCOME.AMOUNT * CS_ACCOUNT_INCOME.STATUS)
  via CS_ACCOUNT_ACTION (ACCOUNT_ID)
```

- `STATUS > 0` → borç / tahakkuk tarafı  
- `STATUS < 0` → ödeme / alacak tarafı  
- Net açık borç = bu toplam (ör. AGR 197168 EL TERMİNALİ → **299**)

## Kullanma
`CS_ACCOUNT.TOTAL_DEBT` / `TOTAL_CREDIT` — çoğu ortamda **stale**.  
Açık borç, SMS özet, kapama adayı, AFL fallback için **kullanma**.

## Özet / rapor (tahsilat wizard)
| Alan | Kaynak |
|------|--------|
| Tahakkuk adet | Income’u olan hesap (`EXISTS` income); boş hesap sayılmaz |
| Toplam tutar | `ACTION_TYPE_ID = 1` (TAHAKKUK); **EMANET (14)** → `STATUS > 0` tutarları |
| Toplam borç | `SUM(AMOUNT * STATUS)` |
| Ödenen | `Toplam tutar − Toplam borç` |

Referans implementasyon: `AgreementSmsReadService.LoadSummaryAsync`.

## Not
Aynı kural staging viewer / close-candidate / AFL open-debt fallback yollarında da uygulanmalı; hâlâ `TOTAL_DEBT/CREDIT` gören yerler düzeltilmeli.

Tahakkuk↔tahsilat eşleşme (Adım 5) için bkz. `ESLESME_RULE.md` — açık borç satırları `TAHAKKUK_ONLY` ile buradaki net bakiyeye bağlanır.
