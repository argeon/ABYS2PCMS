# izgazMGR → ENERGY Transfer - Quick Start Guide

## Pre-requisites Checklist

✅ MIGRATOR uygulaması Oracle CTAS'ları izgazMGR'ye aktardı  
✅ izgazMGR'de tablolar hazır: `LS_INVOICE`, `LS_INVLINES`, `LS_DEBT_PAYTRANS`, vb.  
✅ ENERGY DB'de hedef tablolar oluşturuldu: `LS_315_0126_INVOICE`, etc.  
✅ LREF INT kontrolü yapıldı (MAX < 2,147,483,647)  
✅ Disk space yeterli (ENERGY: 1TB+)  

---

## Step-by-Step Execution

### **STEP 1: Validation Checkpoints (5 dk)**

```sql
-- izgazMGR'de çalıştır
USE izgazMGR;

-- Transfer_IzgazMGR_To_ENERGY_Complete.sql dosyasının ilk bölümünü çalıştır
-- (STEP 1: VALIDATION CHECKPOINTS bölümü)

-- Checkpoints oluşturuldu mu kontrol et:
SELECT * FROM dbo.CTAS_VALIDATION_CHECKPOINT ORDER BY CHECKPOINT_TIME DESC;

-- LREF overflow kontrolü:
SELECT 
    TABLE_NAME,
    MAX_LREF,
    LREF_INT_OVERFLOW_CHECK,
    CASE 
        WHEN LREF_INT_OVERFLOW_CHECK = 'OVERFLOW' THEN '❌ HATA: INT limiti aşıldı!'
        WHEN LREF_INT_OVERFLOW_CHECK = 'WARNING' THEN '⚠️ DİKKAT: Limite yakın'
        ELSE '✅ Güvenli'
    END AS STATUS_TR
FROM dbo.CTAS_VALIDATION_CHECKPOINT
ORDER BY TABLE_NAME;
```

**Beklenen Çıktı:**
```
TABLE_NAME        MAX_LREF      LREF_INT_OVERFLOW_CHECK  STATUS_TR
LS_INVOICE        1234567890    SAFE                     ✅ Güvenli
LS_INVLINES       1234567890    SAFE                     ✅ Güvenli
...
```

---

### **STEP 2A: Test Transfer (Pilot - 15 dk)**

Önce küçük bir pilot test yapın (1 worker, 1M rows):

```sql
-- Worker 0 test (izgazMGR)
EXEC izgazMGR.dbo.sp_Transfer_To_ENERGY_Parallel 
    @SourceTable = 'LS_AFL_OPEN_DEBT',  -- Küçük tablo (~10M rows)
    @TargetDatabase = 'IZGAZ',
    @TargetTablePrefix = 'LS_315_0126',
    @WorkerId = 0,
    @TotalWorkers = 1,  -- Tek worker (test için)
    @BatchSize = 100000,
    @PreserveIdentity = 0;  -- AFL için IDENTITY preserve gerekmez

-- Progress izle:
SELECT 
    WORKER_ID,
    BATCH_ID,
    STATUS,
    ROW_COUNT,
    DATEDIFF(SECOND, START_TIME, GETDATE()) AS ELAPSED_SEC,
    ROWS_PER_SECOND
FROM izgazMGR.dbo.ENERGY_TRANSFER_LOG
WHERE TABLE_NAME = 'LS_AFL_OPEN_DEBT'
ORDER BY BATCH_ID DESC;

-- Validation:
EXEC izgazMGR.dbo.sp_Validate_Transfer_Against_Checkpoint 
    @SourceTable = 'LS_AFL_OPEN_DEBT',
    @TargetDatabase = 'IZGAZ',
    @TargetTablePrefix = 'LS_315_0126';
```

**Beklenti:** ~10M rows, ~5-10 dakika, ✅ PASS

---

### **STEP 2B: Full Transfer - LS_INVOICE (16 parallel workers - 3-4 saat)**

#### **Execution Plan:**

**16 SSMS Window açın** ve aşağıdaki komutları paralel çalıştırın:

**Window 1 (Worker 0):**
```sql
USE izgazMGR;
EXEC dbo.sp_Transfer_To_ENERGY_Parallel 
    @SourceTable = 'LS_INVOICE',
    @WorkerId = 0,
    @TotalWorkers = 16,
    @BatchSize = 500000,
    @PreserveIdentity = 1;  -- LREF preservation
```

**Window 2 (Worker 1):**
```sql
USE izgazMGR;
EXEC dbo.sp_Transfer_To_ENERGY_Parallel 
    @SourceTable = 'LS_INVOICE',
    @WorkerId = 1,
    @TotalWorkers = 16,
    @BatchSize = 500000,
    @PreserveIdentity = 1;
```

**Windows 3-16 (Workers 2-15):** Aynı pattern, sadece `@WorkerId` değiştir (2, 3, 4, ..., 15)

#### **Progress Monitoring:**

**Real-time dashboard (ayrı bir SSMS window):**
```sql
-- Her 30 saniyede bir çalıştır
USE izgazMGR;

-- Worker status
SELECT 
    WORKER_ID,
    MAX(BATCH_ID) AS CURRENT_BATCH,
    SUM(ROW_COUNT) AS TOTAL_ROWS,
    MAX(END_TIME) AS LAST_UPDATE,
    AVG(ROWS_PER_SECOND) AS AVG_RATE,
    CASE 
        WHEN MAX(STATUS) = 'RUNNING' THEN '🟢 Running'
        WHEN MAX(STATUS) = 'FAILED' THEN '🔴 Failed'
        WHEN MAX(STATUS) = 'SUCCESS' AND MAX(END_TIME) > DATEADD(MINUTE, -1, GETDATE()) THEN '🟢 Active'
        ELSE '⚪ Completed'
    END AS STATUS
FROM dbo.ENERGY_TRANSFER_LOG
WHERE TABLE_NAME = 'LS_INVOICE'
  AND START_TIME > DATEADD(HOUR, -6, GETDATE())
GROUP BY WORKER_ID
ORDER BY WORKER_ID;

-- Overall progress
SELECT 
    COUNT(DISTINCT WORKER_ID) AS ACTIVE_WORKERS,
    SUM(ROW_COUNT) AS TOTAL_ROWS_TRANSFERRED,
    AVG(ROWS_PER_SECOND) AS AVG_RATE_ALL_WORKERS,
    DATEDIFF(MINUTE, MIN(START_TIME), GETDATE()) AS ELAPSED_MINUTES,
    CASE 
        WHEN SUM(ROW_COUNT) > 0 
        THEN CAST(SUM(ROW_COUNT) AS FLOAT) / 75000000 * 100
        ELSE 0
    END AS PCT_COMPLETE
FROM dbo.ENERGY_TRANSFER_LOG
WHERE TABLE_NAME = 'LS_INVOICE'
  AND START_TIME > DATEADD(HOUR, -6, GETDATE())
  AND STATUS = 'SUCCESS';
```

**Beklenen çıktı (örnek - 30 dakika sonra):**
```
ACTIVE_WORKERS: 16
TOTAL_ROWS_TRANSFERRED: 18,750,000  (75M'nin %25'i)
AVG_RATE_ALL_WORKERS: 10,000 rows/sec
ELAPSED_MINUTES: 30
PCT_COMPLETE: 25%

Tahmini kalan süre: 90 dakika
```

#### **Failed Batch Recovery:**

Eğer bir worker başarısız olursa:

```sql
-- Failed batches
SELECT * 
FROM izgazMGR.dbo.ENERGY_TRANSFER_LOG
WHERE TABLE_NAME = 'LS_INVOICE'
  AND STATUS = 'FAILED'
ORDER BY START_TIME DESC;

-- Restart failed worker
-- Örnek: Worker 5 failed
EXEC izgazMGR.dbo.sp_Transfer_To_ENERGY_Parallel 
    @SourceTable = 'LS_INVOICE',
    @WorkerId = 5,  -- Failed worker ID
    @TotalWorkers = 16,
    @BatchSize = 500000,
    @PreserveIdentity = 1;
```

---

### **STEP 2C: LS_INVLINES Transfer (16 workers - 6-8 saat)**

LS_INVOICE tamamlandıktan sonra, aynı pattern ile LS_INVLINES:

```sql
-- Window 1 (Worker 0)
EXEC izgazMGR.dbo.sp_Transfer_To_ENERGY_Parallel 
    @SourceTable = 'LS_INVLINES',
    @WorkerId = 0,
    @TotalWorkers = 16,
    @BatchSize = 2000000,  -- Daha büyük batch (350M rows)
    @PreserveIdentity = 0;  -- INVLINES için IDENTITY_INSERT gerekmez

-- Windows 2-16: Workers 1-15 (aynı pattern)
```

---

### **STEP 2D: Diğer Tablolar (Sıralı veya paralel)**

```sql
-- LS_DEBT_PAYTRANS (150M rows - 4-5 saat, 16 workers)
EXEC izgazMGR.dbo.sp_Transfer_To_ENERGY_Parallel 
    @SourceTable = 'LS_DEBT_PAYTRANS',
    @WorkerId = 0,
    @TotalWorkers = 16,
    @BatchSize = 1000000;

-- Küçük tablolar (tek worker, hızlı)
EXEC izgazMGR.dbo.sp_Transfer_To_ENERGY_Parallel 
    @SourceTable = 'LS_AFL_OPEN_DEBT', @WorkerId = 0, @TotalWorkers = 1;

EXEC izgazMGR.dbo.sp_Transfer_To_ENERGY_Parallel 
    @SourceTable = 'LS_STG_INV_PAY_CLOSE', @WorkerId = 0, @TotalWorkers = 1;

EXEC izgazMGR.dbo.sp_Transfer_To_ENERGY_Parallel 
    @SourceTable = 'LS_PAYMENT', @WorkerId = 0, @TotalWorkers = 1;

EXEC izgazMGR.dbo.sp_Transfer_To_ENERGY_Parallel 
    @SourceTable = 'LS_MAHSUP', @WorkerId = 0, @TotalWorkers = 1;

EXEC izgazMGR.dbo.sp_Transfer_To_ENERGY_Parallel 
    @SourceTable = 'LS_TAKSIT', @WorkerId = 0, @TotalWorkers = 1;
```

---

### **STEP 3: Validation (30 dk)**

Tüm transferler bittikten sonra:

```sql
-- Tüm tabloları validate et
EXEC izgazMGR.dbo.sp_Validate_Transfer_Against_Checkpoint @SourceTable = 'LS_INVOICE';
EXEC izgazMGR.dbo.sp_Validate_Transfer_Against_Checkpoint @SourceTable = 'LS_INVLINES';
EXEC izgazMGR.dbo.sp_Validate_Transfer_Against_Checkpoint @SourceTable = 'LS_DEBT_PAYTRANS';
EXEC izgazMGR.dbo.sp_Validate_Transfer_Against_Checkpoint @SourceTable = 'LS_AFL_OPEN_DEBT';
EXEC izgazMGR.dbo.sp_Validate_Transfer_Against_Checkpoint @SourceTable = 'LS_PAYMENT';

-- Sample spot check (random 1000 rows)
SELECT TOP 1000 
    mgr.LREF,
    mgr.OWNERREF,
    mgr.PAYABLETOTAL AS MGR_TOTAL,
    en.PAYABLETOTAL AS EN_TOTAL,
    CASE 
        WHEN en.LREF IS NULL THEN '❌ MISSING_IN_ENERGY'
        WHEN ABS(mgr.PAYABLETOTAL - en.PAYABLETOTAL) > 0.01 THEN '⚠️ AMOUNT_DIFF'
        ELSE '✅ OK'
    END AS STATUS
FROM izgazMGR.dbo.LS_INVOICE mgr
LEFT JOIN IZGAZ.dbo.LS_315_0126_INVOICE en ON en.LREF = mgr.LREF
WHERE mgr.OWNERREF % 1000 = 0  -- Sample
ORDER BY NEWID();
```

**Beklenen:** Tüm tablolar ✅ PASS, spot check %99+ OK

---

### **STEP 4: Index Creation (4-6 saat)**

```sql
-- ENERGY DB'de çalıştır
USE IZGAZ;
GO

-- LS_INVOICE indexes
CREATE NONCLUSTERED INDEX IX_LS_INVOICE_OWNERREF 
    ON dbo.LS_315_0126_INVOICE(OWNERREF) 
    INCLUDE (LREF, CLOSED, PAYABLETOTAL)
    WITH (DATA_COMPRESSION = PAGE, ONLINE = ON, MAXDOP = 16, SORT_IN_TEMPDB = ON);

CREATE NONCLUSTERED INDEX IX_LS_INVOICE_ABYS_ACCOUNT 
    ON dbo.LS_315_0126_INVOICE(ABYS_ACCOUNT_ID) 
    INCLUDE (LREF, CLOSED)
    WITH (DATA_COMPRESSION = PAGE, ONLINE = ON, MAXDOP = 16, SORT_IN_TEMPDB = ON);

-- LS_INVLINES indexes
CREATE NONCLUSTERED INDEX IX_LS_INVLINES_INVOICE 
    ON dbo.LS_315_0126_INVLINES(INVOICE_LREF) 
    INCLUDE (LINENR, AMOUNT, LINETYPE)
    WITH (DATA_COMPRESSION = PAGE, ONLINE = ON, MAXDOP = 16, SORT_IN_TEMPDB = ON);

-- LS_PAYTRANS indexes
CREATE NONCLUSTERED INDEX IX_LS_PAYTRANS_INVOICE 
    ON dbo.LS_315_0126_PAYTRANS(INVOICEREF)
    WITH (DATA_COMPRESSION = PAGE, ONLINE = ON, MAXDOP = 16, SORT_IN_TEMPDB = ON);

CREATE NONCLUSTERED INDEX IX_LS_PAYTRANS_OWNER 
    ON dbo.LS_315_0126_PAYTRANS(OWNERREF)
    WITH (DATA_COMPRESSION = PAGE, ONLINE = ON, MAXDOP = 16, SORT_IN_TEMPDB = ON);

-- Update statistics
UPDATE STATISTICS dbo.LS_315_0126_INVOICE WITH FULLSCAN;
UPDATE STATISTICS dbo.LS_315_0126_INVLINES WITH FULLSCAN;
UPDATE STATISTICS dbo.LS_315_0126_PAYTRANS WITH FULLSCAN;

PRINT 'Indexes created successfully'
```

---

## Timeline (16 Workers)

| Aktivite | Süre | Kümülatif |
|----------|------|-----------|
| Validation Checkpoints | 5 dk | 0:05 |
| Pilot Test | 15 dk | 0:20 |
| LS_INVOICE Transfer | 3-4 saat | 4:20 |
| LS_INVLINES Transfer | 6-8 saat | 12:20 |
| LS_DEBT_PAYTRANS Transfer | 4-5 saat | 17:20 |
| Diğer Tablolar | 2-3 saat | 20:20 |
| Validation | 30 dk | 20:50 |
| Index Creation | 4-6 saat | 26:50 |
| **TOPLAM** | | **~27 saat (1+ gün)** |

---

## Troubleshooting

### Sorun 1: "LREF INT overflow"
```sql
-- Kontrol
SELECT MAX(LREF) FROM izgazMGR.dbo.LS_INVOICE;
-- Eğer > 2,147,483,647 ise: ENERGY'de BIGINT kullan (schema değişikliği gerekli)
```

### Sorun 2: "Worker timeout / hang"
```sql
-- Worker'ı kill et
KILL <spid>; -- SSMS Activity Monitor'den bul

-- Yeniden başlat (aynı WorkerId)
EXEC izgazMGR.dbo.sp_Transfer_To_ENERGY_Parallel ... @WorkerId=X;
```

### Sorun 3: "Disk full"
```sql
-- ENERGY disk space kontrol
EXEC sp_spaceused;

-- Log dosyası shrink (geçici)
DBCC SHRINKFILE(2, 10240);  -- 10GB'a düşür
```

### Sorun 4: "Performance degradation"
```sql
-- Statistics update (transfer sırasında)
UPDATE STATISTICS izgazMGR.dbo.LS_INVOICE;

-- Checkpoint frequency artır
-- Her 5 batch'te bir CHECKPOINT; (SP içinde modify et)
```

---

## Success Criteria

✅ Tüm tablolar ✅ PASS validation  
✅ Row count match (Diff < 100)  
✅ LREF range match  
✅ Sum amounts match (Diff < ±0.01)  
✅ Spot check %99+ OK  
✅ Indexes oluşturuldu  
✅ Wizard smoke test (örnek AGR) başarılı  

---

## Next Steps After Transfer

1. **Wizard Test:** 10-20 örnek sözleşme ile wizard'ı test et
2. **Performance Test:** Query response times kontrol et
3. **UAT:** Business team ile acceptance testing
4. **Go-Live Plan:** Production cutover schedule

---

**Hazır mısınız? STEP 1'den başlayın! 🚀**
