# Büyük Ölçekli CTAS Migrasyonu: Oracle → izgazMGR (MSSQL Staging) → ENERGY

## Veri Hacmi
- **75 milyon fatura** (LS_INVOICE)
- **350 milyon INCOME satırı** (LS_INVLINES - PCMS'de daha fazla)
- **Eş değer tahsilat** (~75M LS_PAYMENT, LS_OV_PAY_ALLOC)
- **Toplam tahmini:** ~600-700M satır

## 3 Aşamalı Migrasyon Stratejisi

### **Aşama 1: Oracle CTAS Oluşturma** (prod2/00_run_all.sql)
### **Aşama 2: Oracle → izgazMGR Transfer** (Bulk Export/Import)
### **Aşama 3: izgazMGR → ENERGY Transfer** (Staged Bulk Copy)

---

## Aşama 1: Oracle CTAS Oluşturma

### CTAS Execution Order (prod2/00_run_all.sql)

```sql
-- Toplam ~17 CTAS + gate
-- Bağımlılık zinciri:
--   10 → 11 → 12 → 13 → 14
--        ↓
--   20 → 27 (gate)
--        ↓
--   30 → 40 → 41 (gate)
--        ↓
--   50 → 51 → 52 → 53 → 54 → 55 → 56
```

| Sıra | CTAS | Satır Tahmini | Süre (örnek) | Öncelik |
|------|------|---------------|--------------|---------|
| 10 | STG_INV_ACC_INC | 500M | 3-4 saat | 🔴 KRİTİK |
| 11 | **LS_INVOICE** | **75M** | 1.5 saat | 🔴 KRİTİK |
| 12 | **LS_INVLINES** | **350M** | 4-5 saat | 🔴 KRİTİK |
| 13 | LS_MIG_AGR_LIST | 500K | 5 dk | ORTA |
| 14 | LS_DEBT_PAYTRANS | 150M | 2 saat | 🔴 KRİTİK |
| 20 | LS_EKSILTEN_OVERLAY | 20M | 30 dk | ORTA |
| 27 | GATE_EKSILTEN | 0 (kontrol) | 10 dk | GATE |
| 30 | LS_TAHSILAT_OVERLAY | 100M | 2 saat | 🔴 KRİTİK |
| 40 | LS_TAHSILAT_LOG | 75M | 1.5 saat | 🔴 KRİTİK |
| 41 | GATE_TAHSILAT | 0 (kontrol) | 10 dk | GATE |
| 50 | LS_AFL_OPEN_DEBT | 10M | 20 dk | YÜKSEK |
| 51 | LS_STG_INV_PAY_CLOSE | 5M | 10 dk | YÜKSEK |
| 52 | LS_PAYMENT | 75M | 1 saat | YÜKSEK |
| 53 | LS_EKSILTEN_FAMILY | 15M | 15 dk | ORTA |
| 54 | LS_ARTIRAN_EMANET | 5M | 10 dk | ORTA |
| 55 | LS_MAHSUP | 10M | 15 dk | ORTA |
| 56 | LS_TAKSIT | 20M | 20 dk | ORTA |

**Toplam Tahmini Süre:** 18-22 saat (paralel değil, sıralı)

### Performans Optimizasyonu

```sql
-- 00_session_parallel.sql
ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 16;
ALTER SESSION SET OPTIMIZER_MODE = ALL_ROWS;
ALTER SESSION SET DB_FILE_MULTIBLOCK_READ_COUNT = 128;
ALTER SESSION SET WORKAREA_SIZE_POLICY = AUTO;
ALTER SESSION SET PGA_AGGREGATE_TARGET = 20G;
```

### Monitoring

```sql
-- CTAS progress tracking
SELECT 
    OPNAME,
    TARGET,
    SOFAR,
    TOTALWORK,
    ROUND((SOFAR/TOTALWORK)*100, 2) AS PCT_COMPLETE,
    TIME_REMAINING/60 AS MIN_REMAINING,
    ELAPSED_SECONDS/60 AS MIN_ELAPSED
FROM V$SESSION_LONGOPS
WHERE TIME_REMAINING > 0
ORDER BY TIME_REMAINING DESC;
```

---

## Aşama 2: Oracle → izgazMGR Transfer

### Strategi: Partition-Based Bulk Export/Import

#### Avantajlar:
- ✅ Parallel transfer (birden fazla partition aynı anda)
- ✅ Hata durumunda restart (sadece başarısız partition)
- ✅ Progress tracking (partition bazında)
- ✅ Network bant genişliği optimizasyonu

### Partition Stratejisi

```sql
-- LS_INVOICE: AGREEMENT_ID bazında partition (örnek: 500K/partition)
-- 75M fatura ÷ 500K = ~150 partition

-- LS_INVLINES: INVOICE_ID range bazında (örnek: 2M/partition)
-- 350M satır ÷ 2M = ~175 partition
```

### Transfer Metodu: SQL Server Integration Services (SSIS) veya BCP

#### Yöntem 1: BCP (Recommended for Large Scale)

**장장점:**
- En hızlı bulk transfer
- Minimum loglama
- Parallel işlem desteği

```bash
# Oracle Export (SqlPlus + spool)
# Her partition için ayrı CSV

# Örnek: LS_INVOICE partition 1
sqlplus user/pass@db <<EOF
SET COLSEP '|'
SET LINESIZE 32767
SET PAGESIZE 0
SET TRIMSPOOL ON
SET HEADSEP OFF
SET FEEDBACK OFF
SET ECHO OFF
SPOOL ls_invoice_p001.csv
SELECT /*+ PARALLEL(16) */
    LREF, OWNERREF, FICHENO, EXPLAIN, CLOSED, PAYABLETOTAL, ...
FROM MIG_IZGAZPR.LS_INVOICE
WHERE MOD(OWNERREF, 150) = 0  -- Partition 1
ORDER BY LREF;
SPOOL OFF
EOF

# MSSQL Import (BCP)
bcp izgazMGR.dbo.LS_INVOICE in ls_invoice_p001.csv \
    -S mssql_server \
    -U user -P pass \
    -t "|" \
    -c \
    -b 100000 \
    -h "TABLOCK" \
    -e ls_invoice_p001.err
```

#### Yöntem 2: Oracle Data Pump + SQL Server BCP (Faster)

```bash
# Step 1: Oracle export to .dmp
expdp user/pass@db \
    directory=DATA_PUMP_DIR \
    tables=MIG_IZGAZPR.LS_INVOICE:P001 \
    dumpfile=ls_invoice_p001.dmp \
    parallel=4 \
    compression=ALL \
    logfile=ls_invoice_p001.log

# Step 2: Convert .dmp to CSV (Python/Java tool)
# Step 3: BCP import to MSSQL
```

#### Yöntem 3: Linked Server (Simplest, Slowest)

```sql
-- MSSQL'de Oracle linked server tanımla
EXEC sp_addlinkedserver 
    @server = 'ORACLE_SMS',
    @srvproduct = 'Oracle',
    @provider = 'OraOLEDB.Oracle',
    @datasrc = 'IZGAZSMS';

-- Bulk INSERT via OPENQUERY (partition bazında)
INSERT INTO izgazMGR.dbo.LS_INVOICE WITH (TABLOCK)
SELECT * 
FROM OPENQUERY(ORACLE_SMS, '
    SELECT /*+ PARALLEL(16) */
        LREF, OWNERREF, ...
    FROM MIG_IZGAZPR.LS_INVOICE
    WHERE MOD(OWNERREF, 150) = 0
') AS src;
```

### Paralel Transfer Script (PowerShell)

```powershell
# Transfer-OracleCTAS.ps1
# Paralel partition transfer

param(
    [string]$OracleConnStr,
    [string]$MssqlConnStr,
    [string]$TableName,
    [int]$TotalPartitions = 150,
    [int]$MaxParallel = 8
)

$jobs = @()

for ($i = 0; $i -lt $TotalPartitions; $i++) {
    $partition = $i
    
    # Start parallel job
    $job = Start-Job -ScriptBlock {
        param($p, $table, $oraConn, $mssqlConn)
        
        # 1. Extract from Oracle
        $csvFile = "${table}_p${p}.csv"
        sqlplus $oraConn <<EOF
        SET COLSEP '|'
        SET PAGESIZE 0
        SET FEEDBACK OFF
        SPOOL $csvFile
        SELECT * FROM MIG_IZGAZPR.$table
        WHERE MOD(OWNERREF, $TotalPartitions) = $p;
        SPOOL OFF
EOF
        
        # 2. Load to MSSQL
        bcp "izgazMGR.dbo.$table" in $csvFile `
            -S $mssqlConn `
            -t "|" `
            -c `
            -b 100000 `
            -h "TABLOCK" `
            -e "${csvFile}.err"
        
        Remove-Item $csvFile
        
    } -ArgumentList $partition, $TableName, $OracleConnStr, $MssqlConnStr
    
    $jobs += $job
    
    # Throttle parallel jobs
    while (($jobs | Where-Object { $_.State -eq 'Running' }).Count -ge $MaxParallel) {
        Start-Sleep -Seconds 5
    }
}

# Wait for all jobs
$jobs | Wait-Job | Receive-Job
```

### Transfer Önceliği ve Grup

**Grup 1: Kritik Core (Paralel başlat)**
```
LS_INVOICE       (75M)  - 8 paralel stream
LS_INVLINES      (350M) - 16 paralel stream
LS_DEBT_PAYTRANS (150M) - 8 paralel stream
```

**Grup 2: Tahsilat (Grup 1 bittikten sonra)**
```
LS_TAHSILAT_OVERLAY (100M)
LS_TAHSILAT_LOG     (75M)
LS_PAYMENT          (75M)
```

**Grup 3: Yardımcı (En son)**
```
LS_AFL_OPEN_DEBT, LS_STG_INV_PAY_CLOSE, LS_EKSILTEN_FAMILY, 
LS_MAHSUP, LS_TAKSIT, LS_ARTIRAN_EMANET
```

### İzgazMGR Table Creation

```sql
-- izgazMGR'de tablolar önceden oluşturulmalı
-- Index'ler SONRA (bulk load daha hızlı)

CREATE TABLE izgazMGR.dbo.LS_INVOICE (
    LREF BIGINT NOT NULL,
    OWNERREF BIGINT,
    FICHENO VARCHAR(50),
    EXPLAIN VARCHAR(500),
    CLOSED BIT,
    CANCELED BIT,
    PAYABLETOTAL DECIMAL(18,2),
    DATE_ DATETIME,
    ABYS_ACCOUNT_ID BIGINT,
    -- ... diğer kolonlar
    CONSTRAINT PK_LS_INVOICE PRIMARY KEY NONCLUSTERED (LREF)
        WITH (DATA_COMPRESSION = PAGE)
) ON [PRIMARY];
-- NOT: INDEX'LER SONRA EKLENECEK (post_load_indexes.sql)

CREATE TABLE izgazMGR.dbo.LS_INVLINES (
    INVLINE_ID BIGINT IDENTITY(1,1) NOT NULL,
    INVOICE_LREF BIGINT NOT NULL,
    LINETYPE SMALLINT,
    LINENR SMALLINT,
    AMOUNT DECIMAL(18,2),
    DESCRIPTION VARCHAR(500),
    -- ... diğer kolonlar
    CONSTRAINT PK_LS_INVLINES PRIMARY KEY NONCLUSTERED (INVLINE_ID)
        WITH (DATA_COMPRESSION = PAGE)
) ON [PRIMARY];
```

### Post-Load Indexing

```sql
-- post_load_indexes.sql
-- Bulk load bittikten SONRA çalıştır

-- LS_INVOICE
CREATE NONCLUSTERED INDEX IX_LS_INVOICE_OWNERREF 
    ON izgazMGR.dbo.LS_INVOICE(OWNERREF) 
    INCLUDE (LREF, CLOSED, PAYABLETOTAL)
    WITH (DATA_COMPRESSION = PAGE, ONLINE = ON, MAXDOP = 16);

CREATE NONCLUSTERED INDEX IX_LS_INVOICE_ABYS_ACCOUNT 
    ON izgazMGR.dbo.LS_INVOICE(ABYS_ACCOUNT_ID) 
    INCLUDE (LREF, CLOSED)
    WITH (DATA_COMPRESSION = PAGE, ONLINE = ON, MAXDOP = 16);

-- LS_INVLINES
CREATE NONCLUSTERED INDEX IX_LS_INVLINES_INVOICE 
    ON izgazMGR.dbo.LS_INVLINES(INVOICE_LREF) 
    INCLUDE (LINENR, AMOUNT)
    WITH (DATA_COMPRESSION = PAGE, ONLINE = ON, MAXDOP = 16);

-- LS_DEBT_PAYTRANS
CREATE NONCLUSTERED INDEX IX_LS_DEBT_PAYTRANS_INVOICE 
    ON izgazMGR.dbo.LS_DEBT_PAYTRANS(INVOICEREF)
    WITH (DATA_COMPRESSION = PAGE, ONLINE = ON, MAXDOP = 16);

-- Statistics update
UPDATE STATISTICS izgazMGR.dbo.LS_INVOICE WITH FULLSCAN;
UPDATE STATISTICS izgazMGR.dbo.LS_INVLINES WITH FULLSCAN;
UPDATE STATISTICS izgazMGR.dbo.LS_DEBT_PAYTRANS WITH FULLSCAN;
```

---

## Aşama 3: izgazMGR → ENERGY Transfer

### Strategi: Chunked Batch Processing

75M fatura + 350M lines için doğrudan bulk insert yerine **batch-based incremental** transfer:

```sql
-- Batch size: 500K rows per iteration
DECLARE @BatchSize INT = 500000;
DECLARE @LastLref BIGINT = 0;
DECLARE @RowsInserted INT = 1;

WHILE @RowsInserted > 0
BEGIN
    -- Insert batch
    INSERT INTO ENERGY.dbo.LS_315_0126_INVOICE WITH (TABLOCK)
    SELECT TOP (@BatchSize)
        src.LREF,
        src.OWNERREF,
        src.FICHENO,
        src.EXPLAIN,
        src.CLOSED,
        src.PAYABLETOTAL,
        ...
    FROM izgazMGR.dbo.LS_INVOICE src
    WHERE src.LREF > @LastLref
      AND src.OWNERREF IN (SELECT AGREEMENT_ID FROM ENERGY.dbo.LS_315_0126_AGREEMENT)
    ORDER BY src.LREF;
    
    SET @RowsInserted = @@ROWCOUNT;
    SET @LastLref = (SELECT MAX(LREF) FROM ENERGY.dbo.LS_315_0126_INVOICE);
    
    -- Progress log
    RAISERROR('Inserted %d rows, last LREF=%d', 0, 1, @RowsInserted, @LastLref) WITH NOWAIT;
    
    -- Checkpoint (optional)
    CHECKPOINT;
END
```

### Paralel Transfer (AGREEMENT_ID Ranges)

```sql
-- 8 paralel worker, her biri farklı AGREEMENT_ID range
-- Worker 1: AGR % 8 = 0
-- Worker 2: AGR % 8 = 1
-- ...

-- Worker script template
DECLARE @Mod INT = 0;  -- 0-7 arası değişecek

INSERT INTO ENERGY.dbo.LS_315_0126_INVOICE WITH (TABLOCK)
SELECT 
    src.LREF,
    src.OWNERREF,
    ...
FROM izgazMGR.dbo.LS_INVOICE src
WHERE src.OWNERREF % 8 = @Mod
  AND src.OWNERREF IN (SELECT AGREEMENT_ID FROM ENERGY.dbo.LS_315_0126_AGREEMENT)
ORDER BY src.LREF;
```

---

## Monitoring ve Loglama

### Transfer Progress Tracking Table

```sql
CREATE TABLE izgazMGR.dbo.CTAS_TRANSFER_LOG (
    LOG_ID INT IDENTITY(1,1) PRIMARY KEY,
    TABLE_NAME VARCHAR(100),
    PARTITION_ID INT,
    PHASE VARCHAR(50),  -- EXPORT, IMPORT, INDEX, VALIDATE
    START_TIME DATETIME,
    END_TIME DATETIME,
    ROW_COUNT BIGINT,
    STATUS VARCHAR(20),  -- RUNNING, SUCCESS, FAILED
    ERROR_MESSAGE VARCHAR(MAX),
    DURATION_SECONDS AS DATEDIFF(SECOND, START_TIME, END_TIME)
);

-- Log örneği
INSERT INTO izgazMGR.dbo.CTAS_TRANSFER_LOG
    (TABLE_NAME, PARTITION_ID, PHASE, START_TIME, STATUS)
VALUES
    ('LS_INVOICE', 1, 'EXPORT', GETDATE(), 'RUNNING');
```

### Real-Time Dashboard Query

```sql
-- Transfer progress overview
SELECT 
    TABLE_NAME,
    PHASE,
    COUNT(*) AS TOTAL_PARTITIONS,
    SUM(CASE WHEN STATUS='SUCCESS' THEN 1 ELSE 0 END) AS COMPLETED,
    SUM(CASE WHEN STATUS='RUNNING' THEN 1 ELSE 0 END) AS RUNNING,
    SUM(CASE WHEN STATUS='FAILED' THEN 1 ELSE 0 END) AS FAILED,
    SUM(ROW_COUNT) AS TOTAL_ROWS,
    AVG(DURATION_SECONDS) AS AVG_DURATION_SEC
FROM izgazMGR.dbo.CTAS_TRANSFER_LOG
WHERE START_TIME > DATEADD(HOUR, -24, GETDATE())
GROUP BY TABLE_NAME, PHASE
ORDER BY TABLE_NAME, PHASE;
```

---

## Hata Yönetimi ve Rollback

### Restart Failed Partitions

```sql
-- Failed partitions listesi
SELECT 
    TABLE_NAME,
    PARTITION_ID,
    ERROR_MESSAGE
FROM izgazMGR.dbo.CTAS_TRANSFER_LOG
WHERE STATUS = 'FAILED'
  AND PHASE = 'IMPORT';

-- Sadece başarısız partition'ları yeniden transfer et
```

### Rollback Strategy

```sql
-- Option 1: Drop and recreate table (hızlı ama risky)
DROP TABLE izgazMGR.dbo.LS_INVOICE;
-- Recreate...

-- Option 2: Truncate and reload (index'ler korunur)
TRUNCATE TABLE izgazMGR.dbo.LS_INVOICE;

-- Option 3: Delete specific partition
DELETE FROM izgazMGR.dbo.LS_INVOICE
WHERE OWNERREF % 150 = 42;  -- Partition 42
```

---

## Tahmini Süre (Toplam)

| Aşama | İşlem | Süre (Optimistik) | Süre (Gerçekçi) |
|-------|-------|-------------------|-----------------|
| 1 | Oracle CTAS | 18 saat | 24 saat |
| 2 | Oracle → izgazMGR | 12 saat (paralel) | 18 saat |
| 3 | izgazMGR → ENERGY | 8 saat (paralel) | 12 saat |
| | Index oluşturma | 4 saat | 6 saat |
| | Validation | 2 saat | 4 saat |
| **TOPLAM** | | **44 saat** | **64 saat (2.5 gün)** |

---

## Checklist

### Pre-Migration
- [ ] Oracle tablespace yeterli mi? (500GB+ gerekli)
- [ ] MSSQL disk yeterli mi? (1TB+ gerekli)
- [ ] Network bandwidth test (Oracle ↔ MSSQL)
- [ ] Backup: Hem Oracle hem MSSQL
- [ ] Test run: Küçük bir AGR subset'i ile

### Migration
- [ ] CTAS'lar başarılı (00_run_all.sql)
- [ ] Oracle export tamamlandı (tüm partitions)
- [ ] izgazMGR import tamamlandı
- [ ] izgazMGR index'ler oluşturuldu
- [ ] izgazMGR → ENERGY transfer tamamlandı
- [ ] ENERGY index'ler oluşturuldu

### Post-Migration
- [ ] Row count validation (Oracle = izgazMGR = ENERGY)
- [ ] Sample data spot check (100-1000 random rows)
- [ ] Wizard smoke test (örnek AGR'ler)
- [ ] Performance test (query response times)

---

## Optimizasyon Tips

1. **Oracle CTAS:** 
   - `PARALLEL 16` kullan
   - `NOLOGGING` (risky ama hızlı)
   - Geceleri çalıştır (low load)

2. **Transfer:**
   - Partition size optimize et (2-5M rows ideal)
   - Network compression kullan
   - Parallel streams (8-16)

3. **MSSQL:**
   - Bulk insert için `TABLOCK` hint
   - `RECOVERY SIMPLE` moda geç (geçici)
   - Index oluşturmayı SONRA yap
   - `DATA_COMPRESSION = PAGE` kullan

4. **Monitoring:**
   - Her partition için ayrı log
   - Real-time progress dashboard
   - Alert on failures

---

## Sonraki Adım

1. **Pilot test:** 100K agreement (~5M fatura, ~25M lines)
2. **Performance tuning** pilot sonuçlarına göre
3. **Full migration** cutover window'da
