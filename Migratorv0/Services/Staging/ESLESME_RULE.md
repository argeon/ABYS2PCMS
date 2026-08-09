# Tahakkuk ↔ Tahsilat eşleşme (Adım 5) — kritik yapı

Bu adım migration zincirinin **omurgasıdır**: hangi tahakkuk (MAIN) hangi tahsilata (PAY) bağlandı,
hangisi açık kaldı, hangisi “yetim” ödeme.

## Üç kova
| MATCH_STATUS | Anlam |
|---|---|
| **MATCHED** | PAY↔MAIN bağlandı (O30 `LS_OV_PAY_ALLOC` veya canlı INCOME_ID heuristic) |
| **TAHAKKUK_ONLY** | MAIN var, tahsilat eşleşmedi → açık borç / eksik alloc adayı |
| **TAHSILAT_ONLY** | PAY var, tahakkuk eşleşmedi → yetim tahsilat / yanlış income |

## Bakiye ile ilişki (zorunlu)
Eşleşmeyen açık tahakkuk tutarı ≈ hesap net bakiyesi:

`SUM(AMOUNT × STATUS)` — bkz. `SMS_BALANCE_RULE.md`

Örnek AGR **197168** (TEST, live INCOME_ID; O30 yok):
- MATCHED ≈ 245 (alloc ~110.028)
- TAHAKKUK_ONLY ≈ 12 (içinde **amt=299** açık borç + sıfır tutarlı gürültü)
- TAHSILAT_ONLY ≈ 4 (pay ~120)

→ Özet adımındaki **299 TL açık borç**, eşleşmede `TAHAKKUK_ONLY` olarak görünmeli.

## Kaynak önceliği
1. **`MIGRATION.LS_OV_PAY_ALLOC`** (O30 waterfill) — kesin alloc; `SUM(ALLOC)≤PAY_FULL`, MAIN payable cap
2. Yoksa **canlı heuristic**: aynı `ACCOUNT_ID` + `INCOME_ID` yeterli (`CS_ACCOUNT_ACTION` bağı).
   **Tarih/saat filtresi yok** — `ACTION_DATE` karşılaştırması yanıltır (tahsilat çoğu `00:00:00`, tahakkuk gün içi saat).

Canlı yol **yaklaşık**; O30 CTAS yoksa gap WARN (`NO_LS_OV_PAY_ALLOC_ESLESME`).

## MAIN / PAY tanımı (kod)
- MAIN: `ACTION_TYPE_ID IN (1, 3, 10, 41)` — tahakkuk / arttıran / gecikme ailesi
- PAY: `CS_ACTION_TYPE_PRM.TYPE = 2`, hariç `(6,24,36,37,39,44)` (mahsup/virman sınıfı)

## Dikkat
- UI `FETCH FIRST 500` — büyük sözleşmede kesilir
- Canlı sorgu **AGR hesaplarından** başlar; `CS_ACCOUNT_INCOME` full `GROUP BY` yapılmaz (eski sürüm çok yavaştı)
- Sıfır tutarlı `TAHAKKUK_ONLY` gürültü; asıl kritik olan **pozitif net borç** satırları
- MATCHED satırında `ALLOC` ile MAIN net tutar sapması ayrıca kontrol edilmeli (T3 soft gate → Alloc adımı)

Referans: `AgreementSmsReadService.LoadEslesmeAsync` / `QueryLiveEslesmeAsync`.
