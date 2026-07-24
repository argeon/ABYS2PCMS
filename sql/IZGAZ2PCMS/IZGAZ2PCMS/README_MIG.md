# Migratorv0 — Script düzeni (3 hane + versiyon)

## Yedek

- Tam klasör: `../IZGAZ2PCMS_backup_20260711_202348`
- SQL-only: `../IZGAZ2PCMS_sql_backup_20260711_202348`
- User ID offset (+10000) öncesi: `../IZGAZ2PCMS_backup_userid_offset_20260712_145040`

## User ID mapping

- Kural: `LS_USER.USERID = IT_USER.ID + 10000` (`ABYS_ID = IT_USER.ID`)
- Canlı FK (`ADDUSER` / `UPDUSER` / `CREATED_USER_ID` / …): insert anında `FN_MIG_MAP_USER_USERID` → ABYS + 10000
- Native PCMS bandı: `USERID 1..10000` (seed `ADDUSER=1` vb. offset yok)
- `ABYS_*_USER_ID` audit kolonları ham ABYS id kalır
- Post-UPDATE user remap yok (`910` obsolete)

## Tek giriş (SP oluşturma)

**Sadece bu dosyayı açıp çalıştırın** — tek tek SP dosyası açmaya gerek yok:

```text
deploy_create_all_sps.sql
```

SSMS: `energy` bağlıyken çalıştırın (`:r` açık olmalı).  
sqlcmd:

```bat
sqlcmd -S 172.16.1.192 -d energy -U pcms -P *** -C -I -i deploy_create_all_sps.sql
```

Bu dosya `setup` / `migrate` (CREATE OR ALTER) / `wire` / `post` yükler.  
**Veri aktarımı** (`EXEC SP_MIGRATE_*`) yoktur.

## İsim kuralı

```text
NNN_DOMAIN_ENTITY__ROLE.sql
```

| Birler | Rol |
|--------|-----|
| 0 | setup |
| 1 | migrate |
| 2 | wire / post |
| 3 | check |
| 9 | adhoc |

| Yüzler | Faz |
|--------|-----|
| 100 | INFRA |
| 110–140 | REF |
| 200–240 | MASTER |
| 300–350 | AGR |
| 500–520 | READ |
| 530–541 | WO |
| 550–553 | COMM |
| 560–561 | OPR |
| 600 | LEGAL |
| 900 | OPS |

## Versiyon kontrolü

1. Her dosya başlığında: `SCRIPT_ID`, `SCRIPT_NO`, `VERSION`
2. Tablo: `energy.dbo.MIG_SCRIPT_CATALOG` (`EXPECTED_VERSION` / `DEPLOYED_VERSION`)
3. `deploy_create_all_sps.sql` her adımda:
   - `SP_MIG_SCRIPT_ASSERT` → dosya sürümü ≠ katalog ise **hata**
   - `:r` script
   - `SP_MIG_SCRIPT_MARK_DEPLOYED`

Sürüm artırırken **dosya VERSION + seed EXPECTED_VERSION** birlikte güncellenir.

Audit:

```sql
EXEC energy.dbo.SP_MIG_SCRIPT_AUDIT @RaiseOnDrift = 1;
```

## Eski → yeni (özet)

| Eski | Yeni |
|------|------|
| 00/01 mig_log | 100/101_INFRA_MIGLOG__* |
| 10/11 it_user | 110/111_REF_IT_USER__* |
| 10/12 cs_register | 200/201_MASTER_SUBSCR__* |
| 19/20 items | 240/241_MASTER_ITEMS__* (+242 post) |
| 46/47/48 agr | 300/301/303_AGR_AGR__* |
| 38 wire | 322_AGR_CLOSE__wire |
| 98/99 | 910/900_OPS_* |

Meta: `_script_catalog_meta.json`

## Klasör notları

- `oracleCTAS/`, `oracleControl/` — numaralanmaz, deploy dışı
- Numarasız kalan kök SQL (`02_`, `03_`, `04_`, …) — yardımcı / manuel
