# MSSQL koşu — index / timeout / paralel (64–128 core)

## Sıra (paralel YASAK olanlar)

| Adım | Paralel? | Neden |
|------|----------|--------|
| `00b` → `00c` → `00_pre_indexes` | **Sıralı** | tip + LINEEXP + IX |
| `10/11/12/19` deploy | sıralı | SP oluşturma |
| `SP_MIG_590_ALL` | tek session | INSERT→WIRE→GATE bağımlı |
| `SP_MIG_597_ALL` | 590 **bitmeden** başlama | tahsilat eksilten üstüne |
| 590 ∥ 597 | **HAYIR** | kilit / yarım MAP |
| 613 worker’lar | **Evet** (AGR shard) | ayrı SP, AGR bazlı |

## MAXDOP

| Yer | Değer | Not |
|-----|-------|-----|
| `00_pre_indexes` CREATE INDEX | **48** | SORT_IN_TEMPDB |
| `00c` UPDATE batch | **48** | 128 verme (CXPACKET) |
| `10_590` KISMI INSERT | **48** | batch 50K |
| Diğer 590/597 OPTION | çoğu **24** | yükseltmek isteğe bağlı 48 |

Sunucu şu an `cpu_count≈64`. 128 logical olsa bile tek query’de **48–64** yeterli; 128 genelde yavaşlatır.

## Index ihtiyacı (dump sonrası)

`prodEnergy/00_pre_indexes.sql` çalıştır — eklenenler:

- `IX_MIG_LS_OV_KISMI_INVLINES_INV` (INVOICEREF)
- `IX_MIG_LS_OV_KISMI_INVLINES_INC` (ABYS_INCOME_ID)
- `IX_MIG_LS_OV_KISMI_PAYTRANS_INV`
- `IX_MIG_LS_OV_IADE_INVLINES_SRC`
- mevcut: PAY_PT / MAP / INV / IL AGR+LREF

## Uzun koşu / timeout riskleri

| Risk | Ne olur | Önlem |
|------|---------|--------|
| 00c tek UPDATE 557K | log/lock uzun | **batch 100K** (00c) |
| 590 KISMI tek INSERT 557K | log full, SSMS timeout | **batch 50K** (10_590) |
| IADE_IL cursor satır satır | yavaş (tam IADE çoksa) | bilinçli; KISMI değil |
| SSMS 10 dk timeout | kesilir | `sqlcmd -I` / Command Timeout 0 |
| tempdb / log | MAXDOP+batch disk | G: SORT_IN_TEMPDB; log grow izle |

## Önerilen komut sırası

```text
1) sqlcmd -I -i 00b_align_mgr_varchar.sql
2) sqlcmd -I -i 00c_enrich_mgr_kismi_lineexp.sql
3) sqlcmd -I -d izgazMGR -i ..\00_pre_indexes.sql
4) Deploy 10→11→12→19 (QI ON)
5) EXEC SP_MIG_590_ALL @AGR_ID=NULL, @CLEAN=1, @DEBUG=1
6) (opsiyonel) EXEC SP_MIG_597_ALL ...
```

Pilot: `@AGR_ID=197168` — full 557K yerine dar scope.
