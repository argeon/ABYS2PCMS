# IT_COMMUNICATION_LOG → LS_COMMUNICATION_LOG Migration Mapping

Kaynak: `izgazMGR.dbo.IT_COMMUNICATION_LOG` (Oracle `SMS.IT_COMMUNICATION_LOG` / `izgazmgr`)  
Hedef: `energy.dbo.LS_COMMUNICATION_LOG`

**Kritik:** Hedef tabloda zaten native PCMS kaydı var (~13M ABYS kaydı eklenecek).  
`LREF` = IDENTITY (yeni numara). Kaynak `ID` → `ABYS_ID` (köprü).  
`COMPANY_ID` = **5** (statik).

---

## 1. Migrate sırası

| Sıra | Adım | Zorunlu? |
|---|---|---|
| 1 | `550` setup (`ABYS_ID` + UX + validate) | Evet |
| 2 | `551` Pass 1 batch INSERT | Evet |
| 3 | `553` check | Hayır |

```sql
EXEC energy.dbo.SP_MIGRATE_LS_COMMUNICATION_LOG
     @RESUME = 1, @BATCH_SIZE = 2000, @DEBUG = 1;
```

HARD_RESET yalnızca `ABYS_ID IS NOT NULL` satırlarını siler (native veri korunur).

---

## 2. Pass 1 kolon eşleştirme

| Hedef | Kaynak | Dönüşüm |
|---|---|---|
| LREF | — | IDENTITY (IDENTITY_INSERT yok) |
| ABYS_ID | ID | INT, unique filtered index |
| GROUP_ID | — | NULL |
| DATA_DATE | STARTING_DATE | `CAST(... AS DATE)` |
| COMPANY_ID | — | **5** |
| AGREEMENT_ID | AGREEMENT_ID | INT |
| METER_STATUS_ID | SUB_CODE | `TRY_CAST` → INT (sayı değilse NULL) |
| REGISTER_ID | REGISTER_ID | INT |
| READING_DATE | — | NULL |
| SEND_DATE | SUBMISSION_DATE | `FN_SAFE_DT` |
| DELIVERY_DATE | DELIVERY_DATE | `FN_SAFE_DT` |
| COMMUNICATION_CAUSE | COMMUNICATION_CAUSE | INT |
| COMMUNICATION_SUB_CAUSE | — | NULL |
| COMMUNICATION_TYPE | COMMUNICATION_TYPE | INT |
| COMMUNICATION_CONTENT | CONTENT | `NVARCHAR(MAX)` → ntext |
| GSM_NUMBER | MOBILE_PHONE / PHONE_1 / PHONE_2 | `COALESCE`, LEFT 150 |
| DESCRIPTION | DESCRIPTION / NOTE | `COALESCE`, LEFT 150 |
| EMAIL | EMAIL | LEFT 150 |
| STATUS | STATUS | INT |
| CREATED_TIMESTAMP | CREATED_TIMESTAMP | `FN_SAFE_DT` |
| CREATED_USER | CREATED_USER_ID | `FN_MIG_MAP_USER_USERID` (+10000) |
| UPDATED_TIMESTAMP | UPDATED_TIMESTAMP | `FN_SAFE_DT` |
| UPDATED_USER | UPDATED_USER_ID | `FN_MIG_MAP_USER_USERID` |
| TRANSACTION_ID | TRANSACTION_CODE | LEFT 100 |
| RESULT_STATUS_CODE | RESULT | INT |
| RESULT_STATUS | — | NULL |
| POOL_REF | POOL_ID | INT |
| INVOICE_ID | ACCOUNT_ID | INT (tahakkuk no) |

---

## 3. Aktarılmayan kaynak kolonlar (Pass 1)

`RELATIONAL_ID`, `MAIL_ID`, `UNIT_TYPE_ID`, `APPOINTMENT_DATE`, `CALL_NUMBER`, `NOTE` (DESCRIPTION’a coalesce), `VERSION`, `SHIPPING_STATUS`, `SHIPPING_FIRM`, `DUPLICATED_ID`, `PRIORITY`, `IS_UNREACHABLE_CALL`, `CALL_DATE`, `DEBT_TRACING_ID`, `PARENT_ID`, `SHIPPING_BARCODE_NO`, `CANCELLATION_*`, `TOTAL_DEBT`, `DEBT_BILL_COUNT`, `APPROVAL_*`, `DOC_ID`, `SMS_PROFILE_ID`.

İhtiyaç halinde sonraki pass’ta `ABYS_*` mirror kolonları eklenebilir.

---

## 4. Scriptler

| Dosya | Rol |
|---|---|
| `550_COMM_LOG__setup.sql` | `ABYS_ID` + UX + validate |
| `551_COMM_LOG__migrate.sql` | `SP_MIGRATE_LS_COMMUNICATION_LOG` |
| `553_COMM_LOG__check.sql` | sayım / orphan / örnek |
