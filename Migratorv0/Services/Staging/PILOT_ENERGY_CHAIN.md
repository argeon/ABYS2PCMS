# Pilot ENERGY zinciri (`/staging/tahsilat`)

## Amaç

Tek `AGREEMENT_ID` ile tam pilot:

```text
① Oracle CTAS (MIGRATION.LS_*)  — sqlplus / prod2 (MIG_PARAM.AGR_ID)
② Wizard: pilotDumpMgr           — CTAS + SMS taksit → izgazMGR
③ Wizard: pilotEnergyChain       — izgazMGR → LS_005_01_*
   (veya ②+③ = pilotFullChain)
```

| Tablo (ENERGY) | İşlem |
|----------------|--------|
| `LS_005_01_INVOICE` | INSERT (`SP_MIGRATE_LS005_INVOICE` @AGR_ID) |
| `LS_005_01_INVLINES` | INSERT (AGR filtreli, 581 map) |
| `LS_005_01_PAYTRANS` | INSERT borç PT (`SP_MIGRATE_LS005_DEBT_PAYTRANS` @AGR_ID) |
| `LS_005_01_*` tahsilat | TYPE=101 INV + IOCODE=1 PT (`CROSSREF`→borç PT) — 597 veya direct |
| `LS_005_01_INSTALLMENT_PLAN` | INSERT + WIRE (`611` + `SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE`) |

Hizalama: `CLOSED=1` borçlarda PT `PAID=PAYABLETOTAL` + tahsilat fişi (banka SP modeli).

## Önkoşul

1. ENERGY’de hedef tablolar `LS_005_01_INVOICE` / `INVLINES` / `PAYTRANS` (NR=005 Period=01)
2. MSSQL bağlantısı **energy** DB; **aynı instance**’ta `izgazMGR` görünür
3. Wizard: NR=`005`, Period=`01`
4. Önce **pilotDumpMgr APPLY** (`izgazMGR.LS_INVOICE` dolu)

Pilot ENERGY APPLY artık:
- Eksik `ABYS_*` kolonlarını otomatik ekler (00_abys_columns eşdeğeri)
- 571/575 SP yoksa veya patlarsa **doğrudan INSERT** (`LREF = ABYS_ACTION_ID`, borç PT IOCODE=0)
- 569 yoksa AGR zincirini (PT→lines→invoice) direct siler
- **Tahsilat zinciri:** `SP_MIGRATE_TAHSILAT_OVERLAY_AGR` (597 + `LS_OV_*`) veya CLOSED borçlardan direct TYPE=101 / IOCODE=1

İdeal: production SP’leri deploy (`571`/`575`/`569`/`597`).

## Pilot dump (`pilotDumpMgr`)

Prod’da CTAS sonrası MIGRATOR zaten `izgazMGR.LS_*` doldurur. Pilot boş ortamda:

1. `izgazMGR` DB yoksa `CREATE DATABASE`
2. `LS_INVOICE` / `LS_INVLINES` yoksa Oracle CTAS şemasından (yoksa fallback DDL) oluştur
3. 571 index: `IX_MIG_LSINV_ACTION` (+ AGR)
4. AGR satırlarını Oracle CTAS + SMS taksitten yükle

## Kullanım

1. `/staging/tahsilat` → Sözleşme ID
2. **9. Pilot dump → izgazMGR** — DRY_RUN sayım; APPLY sil+yükle
3. **10. Pilot ENERGY zinciri** — DRY_RUN sayım; APPLY (CleanBeforePilot)
4. veya **11. Pilot tam zincir** (dump+ENERGY tek tık)
5. Doğrulama: taksit / frk / kapama…

## Doğrulama logları (paylaşım)

Her adım şuraya yazılır (şifre yok):

`Migratorv0/App_Data/tahsilat-pilot/{runId}/`

| Dosya | İçerik |
|-------|--------|
| `SHARE.md` | Ne paylaşılacak |
| `meta.json` | RunId, AGR |
| `events.jsonl` | Adım logları |
| `gaps.jsonl` | Gap’ler |
| `steps/*.json` | Summary + önizleme |
| `validation.json` | Dump/ENERGY sonrası özet |

API: `GET /api/staging/tahsilat/pilot-logs` · `GET /api/staging/tahsilat/pilot-logs/{runId}`

## Tahsilat zinciri (TYPE=101)

Banka SP modeli: borç `IOCODE=0` sonrası kapalı faturalar için:
`INVOICE TYPE=101 IOCODE=1` → `INVLINES` → `PAYTRANS IOCODE=1 CROSSREF=borç PT` → borç `CLOSED/PAID`.

LIVE dump artık **brüt borç** + **hesap bakiyesi CLOSED** yazar (eski net≈0 tutar yüzünden aday bulunmuyordu).

**Yeniden koşu:** `pilotDumpMgr` APPLY → `pilotEnergyChain` APPLY (Clean). Summary: `tahsilatInv` / `tahsilatPt` / `enPaytransTahsilat` > 0.

## APPLY sırası (ENERGY)

```
569 CLEAN → 571 INVOICE → INVLINES → 575 DEBT PT → 611/WIRE → CLOSED sync → tahsilat TYPE=101
```

## Notlar

- `CleanBeforePilot`: `SP_MIG_CLEAN_INVOICE_CHAIN_BY_AGR` + AGR installment silme
- LREF = INT `ABYS_ACTION_ID` (1..2147483647)
- Full load için bu adım değil; production 571/581/575 batch kullanın
- Wizard Oracle CTAS DDL çalıştırmaz — yalnızca CTAS çıktısını izgazMGR’ye taşır
