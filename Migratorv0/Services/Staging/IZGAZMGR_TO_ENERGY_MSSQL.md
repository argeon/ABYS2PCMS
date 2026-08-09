# izgazMGR → ENERGY (MSSQL → MSSQL)

## Gerçek yol (yeniden yazma yok)

MIGRATOR Oracle CTAS'ları **izgazMGR**'ye aktardıktan sonra ENERGY yükleme **mevcut SP'lerle** yapılır:

| Sıra | Script | SP | Kaynak | Hedef |
|------|--------|-----|--------|--------|
| 1 | `571_INVOICE__migrate.sql` | `SP_MIGRATE_LS005_INVOICE` | `izgazMGR.dbo.LS_INVOICE` | `energy.dbo.LS_005_01_INVOICE` |
| 2 | `581_INVLINES__migrate.sql` | `SP_MIGRATE_LS005_INVLINES` | `izgazMGR.dbo.LS_INVLINES` | `energy.dbo.LS_005_01_INVLINES` |
| 3 | `575_INVOICE_DEBT_PAYTRANS__migrate.sql` | `SP_MIGRATE_LS005_DEBT_PAYTRANS` | **ENERGY INVOICE** (IOCODE=0) | `energy.dbo.LS_005_01_PAYTRANS` |

**Önemli:** Borç PAYTRANS izgazMGR'den kopyalanmaz; ENERGY'deki INVOICE'dan türetilir.

Overlay (590/597) ana yükleme değildir — 571/581/575 **sonrası**.

## LREF = INT

```
LREF (ENERGY INVOICE) = ABYS_ACTION_ID
Aralık zorunlu: 1 .. 2147483647
```

- `IDENTITY_INSERT` ile yazılır
- Kaynakta `ABYS_ACTION_ID` INT dışı / NULL / duplicate → **DUR**
- Preflight: `IZGAZMGR_TO_ENERGY_MSSQL_RUNBOOK.sql` bölüm A

## Çalıştırma

Tek dosya: [`IZGAZMGR_TO_ENERGY_MSSQL_RUNBOOK.sql`](IZGAZMGR_TO_ENERGY_MSSQL_RUNBOOK.sql)

1. **A Preflight** — BAD_INT=0, duplicate yok
2. **B Pilot** — `@AGR_ID = 31986` (veya bilinen sözleşme); yorum satırlarını aç
3. Spot: wizard + `LREF = ABYS_ID`
4. **C Full** — `@AGR_ID = NULL`; sıra 571 → 581 → 575
5. **D Validation** — SRC≈TGT, orphan 0, 573/577 check

### Pilot komut (özet)

```sql
USE energy;
EXEC dbo.SP_MIGRATE_LS005_INVOICE      @BATCH_SIZE=50000, @AGR_ID=31986, @DEBUG=1;
EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS @BATCH_SIZE=50000, @AGR_ID=31986, @DEBUG=1;
-- INVLINES SP'de @AGR_ID yok; pilot doğrulama INVOICE+PT ile, full'de 581 ayrı
```

### Full komut (özet)

```sql
USE energy;
EXEC dbo.SP_MIGRATE_LS005_INVOICE      @BATCH_SIZE=50000,  @AGR_ID=NULL, @RESUME=0, @DEBUG=1;
-- 572 post
EXEC dbo.SP_MIGRATE_LS005_INVLINES     @BATCH_SIZE=100000, @RESUME=0, @DEBUG=1;
-- 582 post
EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS @BATCH_SIZE=50000,  @AGR_ID=NULL, @RESUME=0, @DEBUG=1;
-- 576 post
```

Kesilirse: `@RESUME = 1` (HARD_RESET kullanma).

## Performans notları (mevcut SP'lerden)

| Tablo | Batch | Not |
|-------|-------|-----|
| INVOICE | 50K | Full: PREPARE_LOAD; pilot: index DISABLE yok |
| INVLINES | 100K+ | Kaynak **LREF index** şart (KEYSET); yoksa O(n²). Recovery **BULK_LOGGED** önerilir |
| DEBT PT | 50K | INVOICE LREF bridge; INT filtre |

## Validasyon uçları

| Kontrol | Beklenen |
|---------|----------|
| SRC count ≈ TGT (ABYS) | Diff ~0 |
| SRC MIN/MAX key = TGT MIN/MAX LREF | Eşit |
| `LREF <> ABYS_ID` | 0 |
| Orphan INVLINES / debt PT | 0 |
| BAD_INT | 0 |
| `573_INVOICE__check.sql` | SRC_ABYS_ACTION_ID_OUT_OF_INT = 0 |

## Sonrası

```
590 eksilten overlay → 597 tahsilat overlay → AFL FRK → 613 taksit ops
```

## Bu klasördeki eski / yanlış notlar

- `LS_315_0126_*` prefix'li örnekler **bu ortamın hedefi değil** → `LS_005_01_*`
- Oracle→izgazMGR PowerShell dump scripti burada **kullanılmaz** (MIGRATOR zaten yapıyor)
- Generic `SELECT *` kopya SP'leri production kolon map'ini karşılamaz → **571/581/575 kullan**
