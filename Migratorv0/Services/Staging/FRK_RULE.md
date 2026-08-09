# FRK / gap özeti (Adım 14)

## AFL nedir?

**AFL = Açık Fatura Listesi** (`LS_AFL_OPEN_DEBT` / O50).

Ödenecek durumda **açık** faturaların listesidir. Kapalı / ödenmiş faturalar AFL’de olmamalıdır.

## Doğru kabul (zorunlu)

Ödenecek açık fatura varsa, AFL ile şunlar **birlikte** eşleşmeli:

1. **Adet** — açık fatura sayısı = AFL satır sayısı (grain: `FATURAID` / `ABYS_ACCOUNT_ID`)
2. **Tutar** — her satırda `BALANCE` ≈ ENERGY kalan (`EN_BAL = Σ(PAYABLE−PAID)`) (±0.02)

İkisi de tutuyorsa FRK **doğrudur** (`MATCH`, `ONLY_AFL=0`, `ONLY_EN=0`, `AMT_DIFF=0`).

## Kural özeti

1. Fatura **ödenmemiş** veya **BALANCE > 0** ise **AFL’de mutlaka** olmalı.
2. SMS canlı bakiye (`SUM(STATUS×AMOUNT)`) ile AFL `BALANCE` **eşit** olmalı (±0.02).
3. ENERGY açık borç AFL ile kıyaslanır (grain yukarıdaki).
4. **Harici açık** (`MIG_IN_SCOPE=0`, örn. emanet 14) ayrı satır / `HARICI_ACIK`.

## KIND

| KIND | Anlam |
|------|--------|
| **MATCH** | AFL ≈ ENERGY (adet+tutar satır bazında OK) |
| **AMT_DIFF** | İkisi de var, tutar farkı |
| **ONLY_AFL** | AFL’de açık var, ENERGY’de kalan yok |
| **ONLY_EN** | ENERGY’de açık var, AFL’de yok → açık fatura AFL’de olmalı |
| **HARICI_ACIK** | Kapsam dışı / emanet |

## Kaynak

- AFL: `LS_AFL_OPEN_DEBT` (O50) veya canlı O50 SQL
- ENERGY: `91_afl_frk_compare_log.sql` ile aynı grain
- Bakiye: `SMS_BALANCE_RULE.md` (`TOTAL_DEBT`/`CREDIT` yok)
