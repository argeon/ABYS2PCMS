# LS_WORK → LS_005_01_CS_APPOINTMENT Migration Mapping

Kaynak: `izgazMGR.dbo.LS_WORK` (Oracle `SMS.WO_WORK` CTAS çıktısı)
Hedef: `energy.dbo.LS_005_01_CS_APPOINTMENT`

Pattern: dump-style INSERT + ABYS_ bridge + IDENTITY_INSERT ON.  
**Aktarım sırasında prm/meter/AGR JOIN yok.** User: `FN_MIG_MAP_USER_USERID` (+10000, aritmetik).  
Child: `LS_005_01_WO_WORK_RESULT.WORK_ID` = bu tablonun `LREF` (`541` migrate, bu SP'den sonra).

Önemli CTAS farkları Pass 1'de handle:
- `ASSINGPERSON` decimal ID → NVARCHAR string
- `ABYS_LOCATION_WKT` geography → `STAsText()`
- User +10000; ham → `ABYS_APPUSER` / `ABYS_ADDUSER` / …

---

## 1. Migrate sırası

| Sıra | Adım | Zorunlu? |
|---|---|---|
| 1 | `530` setup (ABYS_ kolonlar) | Evet |
| 2 | `531` Pass 1 dump INSERT | Evet |
| 3 | `541` WO_WORK_RESULT | Evet (parent sonrası) |
| 4 | FK wire / ASSINGPERSON isim / DAY15DEBTREF… | Hayır — proje sonu |

---

## 2. Kaynak: izgazMGR.dbo.LS_WORK

CTAS ile hedef kolon adına yakın üretilmiş staging. PK: `LREF` (= `WO_WORK.ID` = `ABYS_ID`).

Önemli farklar (CTAS → energy):

| Staging | Not |
|---|---|
| `ASSINGPERSON` `decimal` | Kullanıcı **ID** (isim değil); Pass 1 string cast, isim wire sonra |
| `ABYS_LOCATION_WKT` `geography` | Hedef `NVARCHAR(MAX)` → `.STAsText()` |
| `CANCELLED` `decimal` | → `BIT` |
| User kolonları | Ham ABYS id → insert’te +10000 |
| `bigint` PK/FK | Hedef `INT` — `LREF` 1..2147483647 |

---

## 3. Hedef ABYS_ bridge (setup ALTER)

Canlı DDL + migration için eklenecek `ABYS_*` kolonlar → `530_WO_CS_APPOINTMENT__setup.sql`.

---

## 4. Pass 1 kolon eşleştirme

| Hedef | Kaynak | Dönüşüm |
|---|---|---|
| LREF | LREF | IDENTITY_INSERT, INT |
| TYPEID | TYPEID | INT (NULLable) |
| AGRID | AGRID | ham INT |
| FITNO | FITNO | BIGINT |
| BINAID | BINAID | INT |
| SDATE | SDATE | `FN_SAFE_SMALLDT_*` |
| STATID | STATID | INT |
| APPUSER | APPUSER | `FN_MIG_MAP_USER_USERID` |
| ADDR | ADDR | LEFT 600 |
| CNTID | CNTID | INT |
| CNTSN | CNTSN | LEFT 20 |
| CNTMODEL | CNTMODEL | LEFT 10 |
| READENDEX | READENDEX | INT |
| CURRENTENDEX | CURRENTENDEX | INT |
| PRCUSER | PRCUSER | `FN_MIG_MAP_USER_USERID` |
| PRCDATE | PRCDATE | `FN_SAFE_SMALLDT_*` |
| ADDDATE | ADDDATE | `FN_SAFE_SMALLDT_*` |
| ADDUSER | ADDUSER | `FN_MIG_MAP_USER_USERID` |
| UPDUSER | UPDUSER | `FN_MIG_MAP_USER_USERID` |
| UPDDATE | UPDDATE | `FN_SAFE_SMALLDT_*` |
| CANCELLED | CANCELLED | BIT |
| CANCEL_DATE | CANCEL_DATE | DATETIME |
| CANCEL_DESCRIPTION | CANCEL_DESCRIPTION | LEFT 500 |
| DAY15DEBTREF | DAY15DEBTREF | INT (2. pass doldurulabilir) |
| OBJECTIONREF | OBJECTIONREF | INT |
| CLOSEREF | CLOSEREF | INT |
| CUSTREF | CUSTREF | INT ham |
| CUSTYPE | CUSTYPE | TINYINT |
| IS_INDUSTRY | IS_INDUSTRY | BIT |
| CUSTNAME | CUSTNAME | LEFT 250 (`530` ALTER NVARCHAR(250)) |
| IS_PREPAID | IS_PREPAID | BIT |
| DELETED | DELETED | BIT |
| INVCOUNT | INVCOUNT | INT |
| INVTOTAL | INVTOTAL | FLOAT |
| PAIDDATE | PAIDDATE | `FN_SAFE_SMALLDT_*` |
| GUVENCE_BEDELI | GUVENCE_BEDELI | DECIMAL |
| USULSUZINVCOUNT | USULSUZINVCOUNT | INT |
| LAWSTATID | LAWSTATID | INT |
| READ_STATUS | READ_STATUS | LEFT 50 |
| CNT_STATUS | CNT_STATUS | LEFT 50 |
| LASTREAD_DATE | LASTREAD_DATE | DATETIME |
| DATE_DIFF | DATE_DIFF | INT |
| TP1 | TP1 | LEFT 50 |
| AGRSTATID | AGRSTATID | LEFT 50 |
| ASSINGDATE | ASSINGDATE | DATETIME |
| ASSINGSTATUS | ASSINGSTATUS | SMALLINT (8/9/10 açık) |
| ASSINGPERSON | ASSINGPERSON | ID→NVARCHAR(50); isim wire sonra |
| WO_DATE | WO_DATE | DATETIME |
| WO_APPOINTMENT_DATE | WO_APPOINTMENT_DATE | DATE |
| PARENT_ID | PARENT_ID | INT ham (self) |
| WO_TYPE_ID | WO_TYPE_ID | INT |
| WO_CAUSE_ID | WO_CAUSE_ID | INT |
| WORK_ORDER_PROCESS_ID | WORK_ORDER_PROCESS_ID | TINYINT |
| WORK_ORDER_PROCESS_TIMESTAMP | WORK_ORDER_PROCESS_TIMESTAMP | DATETIME |
| WORK_ORDER_PROCESS_USER_ID | WORK_ORDER_PROCESS_USER_ID | `FN_MIG_MAP_USER_USERID` |
| ABYS_* | ABYS_* | tip cast; LOCATION → STAsText |

---

## 5. Açık kararlar

1. **ASSINGSTATUS 8/9/10** — olduğu gibi taşınır.
2. **ASSINGPERSON isim** — proje sonu `LS_USER` join (offset’li USERID).
3. **TYPEID / BINAID / TP1 / CNT_STATUS** — CTAS ne yazdıysa ham; lookup wire isteğe bağlı.
4. **DAY15DEBTREF / OBJECTIONREF / CLOSEREF** — ilgili migration sonrası UPDATE.

---

## 6. Scriptler

| Dosya | Rol |
|---|---|
| `530_WO_CS_APPOINTMENT__setup.sql` | ABYS_ + validate |
| `531_WO_CS_APPOINTMENT__migrate.sql` | `SP_MIGRATE_LS005_CS_APPOINTMENT` |

```sql
EXEC energy.dbo.SP_MIGRATE_LS005_CS_APPOINTMENT
     @RESUME = 1, @BATCH_SIZE = 5000, @DEBUG = 1;
```
