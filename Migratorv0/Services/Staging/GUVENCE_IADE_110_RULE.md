# TYPE 110 — GÜVENCE BEDELİ İADE (Oracle’dan türet)

## Karar
- **Kaynak:** Oracle SMS (`CS_ACCOUNT` / `CS_ACCOUNT_ACTION` / `CS_ACCOUNT_INCOME`)
- **Değil:** `energy.LS_005_01_AGR_GUARANTY` üzerinden 110 üretmek
- **Pipeline:** **CTAS O60** → dump → **ENERGY E610** (`SP_MIG_GUVENCE_IADE_ALL`)
- PCMS: `CreateIadeFarkAgr` → `INVOICE.TYPE = 110`
- `EXPLAIN` = `UPPER(FITNO + ' Mahsuplaşma sonrası kalan bedel')`
- Gelir: **823** / kırılım **162 / 1936**

## Oracle CTAS (O60)
| Dosya | Çıktı |
|--------|--------|
| `oracleCTAS3007/60_ls_ov_guvence_iade.sql` | `LS_OV_GUVENCE_IADE_INVOICE/INVLINES/PAYTRANS` + ID_MAP append |
| Dump | `DUMP_MANIFEST.txt` |

## ENERGY E610 (hazır — EXEC kapalı)
| Dosya | Rol |
|--------|-----|
| `prodREADY_ENERGY/60_GUVENCE_IADE_INSERT.sql` | DDL `MIG_610_STG_*` + OV IX + `SP_MIG_GUVENCE_IADE_INSERT` |
| `61_GUVENCE_IADE_WIRE.sql` | IL ABYS_ID + PAYTRANS |
| `62_GUVENCE_IADE_GATE.sql` | TYPE110 + EXPLAIN + MAP + PT |
| `69_GUVENCE_IADE_ALL.sql` | INSERT→WIRE→GATE |
| `69x_GUVENCE_IADE_EXEC.sql` | deploy notu + **EXEC yorumda** |

Kurallar:
- `#temp` yok — fiziksel `MIG_610_STG_INV/IL/MAP_OUT`
- Index staging/OV içinde `IF NOT EXISTS` CREATE
- FK dokunma; gereksiz NCIX disable yok (PT volume küçük)
- WHILE: processed DELETE + `@BatchN=0 BREAK`
- MAP seed OV’den (ID_MAP append eksikse)

```sql
-- deploy sonrasi (O60 dump var iken):
EXEC energy.dbo.SP_MIG_GUVENCE_IADE_ALL
    @AGR_ID=NULL, @CLEAN=1, @DEBUG=1, @BatchSize=20000;
```

## Güvence gelir seti
`162, 163, 164, 165, 1936, 3198, 3199, 7649, 7650, 7651, 7652, 12531, 23032`

## Canlı aktarım revizyon (2026-08-07)

- Full reload günü: **O60 dump şart** + deploy `60→69` + `EXEC SP_MIG_GUVENCE_IADE_ALL` (`RUN_ORDER` D2).
- TYPE110 = mahsuplaşma **sonrası kalan** güvence iade; mahsup’un kendisi (162/1936 + tip12/6) → `EMANET_MAHSUP_RULE.md`.
- Spot: AGR `412056` — Energy’de TYPE110 yoktu (OV dump yok); mahsup TYPE101 IL’siz.
- Checklist / diğer FRK revizyonları: `prodREADY_ENERGY/NOTES_CANLI_AKTARIM_REV_20260807.md`

## İlgili
- `EMANET_MAHSUP_RULE.md` · O54 `LS_EMANET`
- PCMS `Mahsuplas` / `CreateIadeFarkAgr`
