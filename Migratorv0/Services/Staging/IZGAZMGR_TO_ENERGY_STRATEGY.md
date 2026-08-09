# izgazMGR → ENERGY Bulk Transfer Stratejisi (Güncellenmiş)

## Durum Özeti

✅ **ADIM 0 (TAMAMLANDI):** Oracle CTAS'lar → izgazMGR (MIGRATOR uygulaması tarafından)
🎯 **ADIM 1:** izgazMGR'den ENERGY'ye bulk transfer + validation
🎯 **ADIM 2:** Aktarım execution

## Kritik Constraint: LREF INT Limiti

### LREF Tanımı
```sql
-- Oracle CTAS
LREF = CS_ACCOUNT_ACTION.ID  -- NUMBER

-- MSSQL izgazMGR & ENERGY
LREF INT  -- Max: 2,147,483,647
```

### Risk Analizi
```sql
-- izgazMGR'de LREF range kontrol
SELECT 
    'LS_INVOICE' AS TABLE_NAME,
    MIN(LREF) AS MIN_LREF,
    MAX(LREF) AS MAX_LREF,
    MAX(LREF) - MIN(LREF) + 1 AS RANGE_SIZE,
    COUNT(*) AS ROW_COUNT,
    CASE 
        WHEN MAX(LREF) > 2147483647 THEN '❌ INT OVERFLOW!'
        WHEN MAX(LREF) > 1500000000 THEN '⚠️ YAKIN LİMİTE'
        ELSE '✅ GÜVENLÎ'
    END AS STATUS
FROM izgazMGR.dbo.LS_INVOICE;
```

**Beklenen Sonuç:**
- 75M fatura, LREF max ~2B → Güvenli
- Ama **IDENTITY_INSERT** kullanılırsa LREF sequence korunmalı

---

## ADIM 1: Transfer Script Hazırlığı

### 1.1 izgazMGR'de Validation Veri Uçları

**Amaç:** Transfer öncesi/sonrası karşılaştırma için snapshot al

```sql
-- =============================================================================
-- Create_Validation_Checkpoints.sql (izgazMGR'de çalıştır)
-- =============================================================================

USE izgazMGR;
GO

-- Validation checkpoint tablosu
IF OBJECT_ID('dbo.CTAS_VALIDATION_CHECKPOINT', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CTAS_VALIDATION_CHECKPOINT (
        CHECKPOINT_ID INT IDENTITY(1,1) PRIMARY KEY,
        TABLE_NAME VARCHAR(100),
        CHECKPOINT_TIME DATETIME DEFAULT GETDATE(),
        ROW_COUNT BIGINT,
        MIN_LREF INT,
        MAX_LREF INT,
        LREF_RANGE_SIZE BIGINT,
        SUM_PAYABLETOTAL DECIMAL(22,2),
        SUM_AMOUNT DECIMAL(22,2),
        SAMPLE_FIRST_10_LREF VARCHAR(MAX),
        SAMPLE_LAST_10_LREF VARCHAR(MAX),
        CHECKSUM_VALUE BIGINT
    );
END
GO

-- Checkpoint procedure
CREATE OR ALTER PROCEDURE dbo.sp_Create_CTAS_Checkpoint
    @TableName VARCHAR(100),
    @AmountColumn VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Sql NVARCHAR(MAX);
    DECLARE @RowCount BIGINT;
    DECLARE @MinLref INT;
    DECLARE @MaxLref INT;
    DECLARE @RangeSize BIGINT;
    DECLARE @SumPayable DECIMAL(22,2);
    DECLARE @SumAmount DECIMAL(22,2);
    DECLARE @First10 VARCHAR(MAX);
    DECLARE @Last10 VARCHAR(MAX);
    DECLARE @Checksum BIGINT;
    
    -- Row count
    SET @Sql = N'SELECT @cnt = COUNT_BIG(*) FROM dbo.' + @TableName;
    EXEC sp_executesql @Sql, N'@cnt BIGINT OUTPUT', @cnt = @RowCount OUTPUT;
    
    -- LREF range
    SET @Sql = N'SELECT @min = MIN(LREF), @max = MAX(LREF) FROM dbo.' + @TableName;
    EXEC sp_executesql @Sql, 
        N'@min INT OUTPUT, @max INT OUTPUT', 
        @min = @MinLref OUTPUT, 
        @max = @MaxLref OUTPUT;
    
    SET @RangeSize = CAST(@MaxLref AS BIGINT) - CAST(@MinLref AS BIGINT) + 1;
    
    -- Sum amounts
    IF @TableName = 'LS_INVOICE'
        SET @Sql = N'SELECT @sum = SUM(PAYABLETOTAL) FROM dbo.' + @TableName;
    ELSE IF @AmountColumn IS NOT NULL
        SET @Sql = N'SELECT @sum = SUM(' + @AmountColumn + ') FROM dbo.' + @TableName;
    ELSE
        SET @Sql = N'SELECT @sum = 0';
    
    EXEC sp_executesql @Sql, N'@sum DECIMAL(22,2) OUTPUT', @sum = @SumPayable OUTPUT;
    
    -- First 10 LREFs (for spot check)
    SET @Sql = N'SELECT @first = STRING_AGG(CAST(LREF AS VARCHAR), '','') 
                 FROM (SELECT TOP 10 LREF FROM dbo.' + @TableName + ' ORDER BY LREF) t';
    EXEC sp_executesql @Sql, N'@first VARCHAR(MAX) OUTPUT', @first = @First10 OUTPUT;
    
    -- Last 10 LREFs
    SET @Sql = N'SELECT @last = STRING_AGG(CAST(LREF AS VARCHAR), '','') 
                 FROM (SELECT TOP 10 LREF FROM dbo.' + @TableName + ' ORDER BY LREF DESC) t';
    EXEC sp_executesql @Sql, N'@last VARCHAR(MAX) OUTPUT', @last = @Last10 OUTPUT;
    
    -- Checksum (sample-based for performance)
    SET @Sql = N'SELECT @chk = CHECKSUM_AGG(CHECKSUM(*)) 
                 FROM (SELECT TOP 100000 * FROM dbo.' + @TableName + ' ORDER BY LREF) t';
    EXEC sp_executesql @Sql, N'@chk BIGINT OUTPUT', @chk = @Checksum OUTPUT;
    
    -- Insert checkpoint
    INSERT INTO dbo.CTAS_VALIDATION_CHECKPOINT (
        TABLE_NAME, ROW_COUNT, MIN_LREF, MAX_LREF, LREF_RANGE_SIZE,
        SUM_PAYABLETOTAL, SUM_AMOUNT, SAMPLE_FIRST_10_LREF, SAMPLE_LAST_10_LREF,
        CHECKSUM_VALUE
    ) VALUES (
        @TableName, @RowCount, @MinLref, @MaxLref, @RangeSize,
        @SumPayable, @SumAmount, @First10, @Last10, @Checksum
    );
    
    -- Display
    SELECT * FROM dbo.CTAS_VALIDATION_CHECKPOINT 
    WHERE CHECKPOINT_ID = SCOPE_IDENTITY();
END
GO

-- Create checkpoints for all tables
EXEC dbo.sp_Create_CTAS_Checkpoint @TableName = 'LS_INVOICE';
EXEC dbo.sp_Create_CTAS_Checkpoint @TableName = 'LS_INVLINES', @AmountColumn = 'AMOUNT';
EXEC dbo.sp_Create_CTAS_Checkpoint @TableName = 'LS_DEBT_PAYTRANS', @AmountColumn = 'PAYABLETOTAL';
EXEC dbo.sp_Create_CTAS_Checkpoint @TableName = 'LS_TAHSILAT_OVERLAY';
EXEC dbo.sp_Create_CTAS_Checkpoint @TableName = 'LS_TAHSILAT_LOG';
EXEC dbo.sp_Create_CTAS_Checkpoint @TableName = 'LS_PAYMENT';
EXEC dbo.sp_Create_CTAS_Checkpoint @TableName = 'LS_AFL_OPEN_DEBT';
EXEC dbo.sp_Create_CTAS_Checkpoint @TableName = 'LS_STG_INV_PAY_CLOSE';
EXEC dbo.sp_Create_CTAS_Checkpoint @TableName = 'LS_EKSILTEN_FAMILY';
EXEC dbo.sp_Create_CTAS_Checkpoint @TableName = 'LS_MAHSUP';
EXEC dbo.sp_Create_CTAS_Checkpoint @TableName = 'LS_TAKSIT';

-- View checkpoints
SELECT * FROM dbo.CTAS_VALIDATION_CHECKPOINT ORDER BY CHECKPOINT_TIME DESC;
GO
```

### 1.2 ENERGY Table Preparation

```sql
-- =============================================================================
-- Prepare_ENERGY_Tables.sql (ENERGY DB'de çalıştır)
-- =============================================================================

USE IZGAZ;
GO

DECLARE @TablePrefix VARCHAR(50) = 'LS_315_0126';  -- Ortama göre değiştir

-- LS_INVOICE
IF OBJECT_ID('dbo.' + @TablePrefix + '_INVOICE', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.LS_315_0126_INVOICE (
        LREF INT NOT NULL,  -- INT CONSTRAINT!
        ABYS_ACTION_ID INT,
        ABYS_ACCOUNT_ID INT,
        OWNERREF INT,       -- AGREEMENT_ID
        FICHENO VARCHAR(50),
        EXPLAIN VARCHAR(500),
        CLOSED BIT DEFAULT 0,
        CANCELED BIT DEFAULT 0,
        PAYABLETOTAL DECIMAL(18,2),
        DATE_ DATETIME,
        LASTPAIDDATE DATETIME,
        -- ... diğer kolonlar
        
        CONSTRAINT PK_LS_INVOICE PRIMARY KEY NONCLUSTERED (LREF)
            WITH (DATA_COMPRESSION = PAGE)
    ) ON [PRIMARY];
END

-- LS_INVLINES  
IF OBJECT_ID('dbo.' + @TablePrefix + '_INVLINES', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.LS_315_0126_INVLINES (
        INVLINE_ID BIGINT IDENTITY(1,1) NOT NULL,
        INVOICE_LREF INT NOT NULL,  -- FK to INVOICE.LREF
        LINETYPE SMALLINT,
        LINENR SMALLINT,
        AMOUNT DECIMAL(18,2),
        DESCRIPTION VARCHAR(500),
        -- ... diğer kolonlar
        
        CONSTRAINT PK_LS_INVLINES PRIMARY KEY NONCLUSTERED (INVLINE_ID)
            WITH (DATA_COMPRESSION = PAGE)
    ) ON [PRIMARY];
END

-- LS_PAYTRANS (LS_DEBT_PAYTRANS mapping)
IF OBJECT_ID('dbo.' + @TablePrefix + '_PAYTRANS', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.LS_315_0126_PAYTRANS (
        LREF BIGINT IDENTITY(1,1) NOT NULL,
        INVOICEREF INT NOT NULL,  -- FK to INVOICE.LREF
        OWNERREF INT,
        PAYABLETOTAL DECIMAL(18,2),
        PAID DECIMAL(18,2) DEFAULT 0,
        INST_NR INT,
        PAYTYPE INT,
        CANCELED BIT DEFAULT 0,
        CANCELLATIONPAYMENT BIT,
        PAYMENTDATE DATETIME,
        -- ... diğer kolonlar
        
        CONSTRAINT PK_LS_PAYTRANS PRIMARY KEY NONCLUSTERED (LREF)
            WITH (DATA_COMPRESSION = PAGE)
    ) ON [PRIMARY];
END

PRINT 'ENERGY tables created successfully'
GO
```

---

## ADIM 2: Bulk Transfer Execution

### 2.1 Optimized Transfer Strategy

**Parallelization:** OWNERREF (AGREEMENT_ID) bazında partition

```sql
-- =============================================================================
-- Transfer_IzgazMGR_To_ENERGY_Optimized.sql
-- =============================================================================

USE izgazMGR;
GO

-- Configuration
DECLARE @TargetDB VARCHAR(100) = 'IZGAZ';
DECLARE @TablePrefix VARCHAR(50) = 'LS_315_0126';
DECLARE @WorkerId INT = 0;         -- 0-15 (16 parallel workers)
DECLARE @TotalWorkers INT = 16;
DECLARE @BatchSize INT = 500000;

-- =============================================================================
-- Stored Procedure: Chunked Transfer with IDENTITY Preservation
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.sp_Transfer_CTAS_To_ENERGY_Chunked
    @SourceTable VARCHAR(100),
    @TargetTable VARCHAR(200),
    @WorkerId INT,
    @TotalWorkers INT,
    @BatchSize INT = 500000,
    @PreserveIdentity BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Sql NVARCHAR(MAX);
    DECLARE @MinLref INT;
    DECLARE @MaxLref INT;
    DECLARE @CurrentLref INT;
    DECLARE @BatchCount INT = 0;
    DECLARE @TotalRows BIGINT = 0;
    DECLARE @StartTime DATETIME = GETDATE();
    
    -- Get LREF range for this worker
    SELECT 
        @MinLref = MIN(LREF),
        @MaxLref = MAX(LREF)
    FROM dbo.@SourceTable
    WHERE OWNERREF % @TotalWorkers = @WorkerId;
    
    SET @CurrentLref = @MinLref;
    
    RAISERROR('Worker %d: LREF range %d - %d', 0, 1, @WorkerId, @MinLref, @MaxLref) WITH NOWAIT;
    
    WHILE @CurrentLref <= @MaxLref
    BEGIN
        SET @BatchCount = @BatchCount + 1;
        
        BEGIN TRY
            -- IDENTITY_INSERT ON (if preserving LREF)
            IF @PreserveIdentity = 1
                EXEC('SET IDENTITY_INSERT ' + @TargetTable + ' ON');
            
            -- Batch insert
            SET @Sql = N'
                INSERT INTO ' + @TargetTable + ' WITH (TABLOCK)
                SELECT TOP (' + CAST(@BatchSize AS VARCHAR) + ') *
                FROM izgazMGR.dbo.' + @SourceTable + '
                WHERE OWNERREF % ' + CAST(@TotalWorkers AS VARCHAR) + ' = ' + CAST(@WorkerId AS VARCHAR) + '
                  AND LREF BETWEEN @minLref AND @maxLref
                  AND LREF >= @currentLref
                ORDER BY LREF';
            
            EXEC sp_executesql @Sql, 
                N'@minLref INT, @maxLref INT, @currentLref INT',
                @minLref = @MinLref,
                @maxLref = @MaxLref,
                @currentLref = @CurrentLref;
            
            DECLARE @RowsInserted INT = @@ROWCOUNT;
            SET @TotalRows = @TotalRows + @RowsInserted;
            
            IF @PreserveIdentity = 1
                EXEC('SET IDENTITY_INSERT ' + @TargetTable + ' OFF');
            
            -- Update cursor
            SET @Sql = N'SELECT @newLref = MAX(LREF) FROM ' + @TargetTable + ' WHERE LREF > @currentLref';
            EXEC sp_executesql @Sql, 
                N'@currentLref INT, @newLref INT OUTPUT', 
                @currentLref = @CurrentLref,
                @newLref = @CurrentLref OUTPUT;
            
            SET @CurrentLref = @CurrentLref + 1;
            
            -- Progress
            IF @BatchCount % 10 = 0
            BEGIN
                DECLARE @ElapsedMin DECIMAL(10,2) = DATEDIFF(SECOND, @StartTime, GETDATE()) / 60.0;
                DECLARE @RowsPerMin DECIMAL(15,2) = @TotalRows / NULLIF(@ElapsedMin, 0);
                
                RAISERROR('Worker %d: Batch %d, Total rows %d, Elapsed %.2f min, Rate %.0f rows/min', 
                    0, 1, @WorkerId, @BatchCount, @TotalRows, @ElapsedMin, @RowsPerMin) WITH NOWAIT;
                
                CHECKPOINT;
            END
            
            IF @RowsInserted = 0 BREAK;  -- No more rows
            
        END TRY
        BEGIN CATCH
            IF @PreserveIdentity = 1
                EXEC('SET IDENTITY_INSERT ' + @TargetTable + ' OFF');
            
            DECLARE @ErrMsg NVARCHAR(MAX) = ERROR_MESSAGE();
            RAISERROR('Worker %d Batch %d failed: %s', 16, 1, @WorkerId, @BatchCount, @ErrMsg);
            RETURN -1;
        END CATCH
    END
    
    RAISERROR('Worker %d completed: %d batches, %d total rows', 0, 1, @WorkerId, @BatchCount, @TotalRows) WITH NOWAIT;
    RETURN 0;
END
GO

-- =============================================================================
-- Execution Plan (16 parallel workers)
-- =============================================================================

-- Worker 0 (SSMS Window 1)
EXEC dbo.sp_Transfer_CTAS_To_ENERGY_Chunked
    @SourceTable = 'LS_INVOICE',
    @TargetTable = 'IZGAZ.dbo.LS_315_0126_INVOICE',
    @WorkerId = 0,
    @TotalWorkers = 16,
    @BatchSize = 500000,
    @PreserveIdentity = 1;

-- Worker 1 (SSMS Window 2)
-- ... same pattern for workers 1-15

GO
```

### 2.2 Simplified Single-Worker Version (Test/Small volumes)

```sql
-- Single-shot transfer (no partitioning)
-- Use for smaller tables or testing

INSERT INTO IZGAZ.dbo.LS_315_0126_AFL_OPEN_DEBT WITH (TABLOCK)
SELECT * 
FROM izgazMGR.dbo.LS_AFL_OPEN_DEBT
ORDER BY FATURAID;

INSERT INTO IZGAZ.dbo.LS_315_0126_STG_INV_PAY_CLOSE WITH (TABLOCK)
SELECT * 
FROM izgazMGR.dbo.LS_STG_INV_PAY_CLOSE
ORDER BY ACCOUNT_ID;

-- Etc for smaller tables (< 10M rows)
```

---

## Validation After Transfer

### Checkpoint Comparison

```sql
-- =============================================================================
-- Validate_Transfer_Against_Checkpoint.sql
-- =============================================================================

USE izgazMGR;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Validate_Transfer
    @SourceTable VARCHAR(100),
    @TargetTable VARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Get original checkpoint
    DECLARE @OriginalRowCount BIGINT;
    DECLARE @OriginalMinLref INT;
    DECLARE @OriginalMaxLref INT;
    DECLARE @OriginalSum DECIMAL(22,2);
    DECLARE @OriginalChecksum BIGINT;
    
    SELECT TOP 1
        @OriginalRowCount = ROW_COUNT,
        @OriginalMinLref = MIN_LREF,
        @OriginalMaxLref = MAX_LREF,
        @OriginalSum = SUM_PAYABLETOTAL,
        @OriginalChecksum = CHECKSUM_VALUE
    FROM dbo.CTAS_VALIDATION_CHECKPOINT
    WHERE TABLE_NAME = @SourceTable
    ORDER BY CHECKPOINT_TIME DESC;
    
    -- Get target stats
    DECLARE @Sql NVARCHAR(MAX);
    DECLARE @TargetRowCount BIGINT;
    DECLARE @TargetMinLref INT;
    DECLARE @TargetMaxLref INT;
    DECLARE @TargetSum DECIMAL(22,2);
    DECLARE @TargetChecksum BIGINT;
    
    SET @Sql = N'SELECT 
        @cnt = COUNT_BIG(*),
        @min = MIN(LREF),
        @max = MAX(LREF)
    FROM ' + @TargetTable;
    EXEC sp_executesql @Sql, 
        N'@cnt BIGINT OUTPUT, @min INT OUTPUT, @max INT OUTPUT',
        @cnt = @TargetRowCount OUTPUT,
        @min = @TargetMinLref OUTPUT,
        @max = @TargetMaxLref OUTPUT;
    
    -- Sum validation
    IF @SourceTable = 'LS_INVOICE'
        SET @Sql = N'SELECT @sum = SUM(PAYABLETOTAL) FROM ' + @TargetTable;
    ELSE
        SET @Sql = N'SELECT @sum = 0';
    EXEC sp_executesql @Sql, N'@sum DECIMAL(22,2) OUTPUT', @sum = @TargetSum OUTPUT;
    
    -- Checksum (sample)
    SET @Sql = N'SELECT @chk = CHECKSUM_AGG(CHECKSUM(*)) 
                 FROM (SELECT TOP 100000 * FROM ' + @TargetTable + ' ORDER BY LREF) t';
    EXEC sp_executesql @Sql, N'@chk BIGINT OUTPUT', @chk = @TargetChecksum OUTPUT;
    
    -- Comparison
    SELECT 
        @SourceTable AS SOURCE_TABLE,
        @TargetTable AS TARGET_TABLE,
        @OriginalRowCount AS ORIGINAL_COUNT,
        @TargetRowCount AS TARGET_COUNT,
        @OriginalRowCount - @TargetRowCount AS DIFF_COUNT,
        @OriginalMinLref AS ORIGINAL_MIN_LREF,
        @TargetMinLref AS TARGET_MIN_LREF,
        @OriginalMaxLref AS ORIGINAL_MAX_LREF,
        @TargetMaxLref AS TARGET_MAX_LREF,
        @OriginalSum AS ORIGINAL_SUM,
        @TargetSum AS TARGET_SUM,
        @OriginalSum - @TargetSum AS DIFF_SUM,
        @OriginalChecksum AS ORIGINAL_CHECKSUM,
        @TargetChecksum AS TARGET_CHECKSUM,
        CASE 
            WHEN @OriginalRowCount = @TargetRowCount 
                AND @OriginalMinLref = @TargetMinLref
                AND @OriginalMaxLref = @TargetMaxLref
                AND ABS(@OriginalSum - @TargetSum) < 0.01
            THEN '✅ PASS'
            WHEN ABS(@OriginalRowCount - @TargetRowCount) < 100
            THEN '⚠️ WARN'
            ELSE '❌ FAIL'
        END AS STATUS;
END
GO

-- Run validations
EXEC dbo.sp_Validate_Transfer 'LS_INVOICE', 'IZGAZ.dbo.LS_315_0126_INVOICE';
EXEC dbo.sp_Validate_Transfer 'LS_INVLINES', 'IZGAZ.dbo.LS_315_0126_INVLINES';
EXEC dbo.sp_Validate_Transfer 'LS_DEBT_PAYTRANS', 'IZGAZ.dbo.LS_315_0126_PAYTRANS';
```

---

## Execution Checklist

### Pre-Transfer
- [ ] izgazMGR'de validation checkpoints oluştur
- [ ] ENERGY'de hedef tablolar oluştur (index'siz)
- [ ] LREF INT overflow kontrolü (MAX < 2.1B)
- [ ] Disk space kontrolü (ENERGY: 1TB+)
- [ ] RECOVERY SIMPLE mod (geçici)

### Transfer
- [ ] 16 paralel worker başlat (OWNERREF % 16)
- [ ] Progress monitoring (her 10 batch)
- [ ] Hata durumunda restart capability

### Post-Transfer
- [ ] Validation: row count, LREF range, checksums
- [ ] Create indexes (ONLINE=ON, MAXDOP=16)
- [ ] Update statistics (FULLSCAN)
- [ ] Spot check: random 1000 rows
- [ ] RECOVERY FULL mod geri al

---

## Tahmini Süre (16 Parallel Workers)

| Tablo | Satır | Batch Size | Tahmini Süre |
|-------|-------|------------|--------------|
| LS_INVOICE | 75M | 500K | 3-4 saat |
| LS_INVLINES | 350M | 2M | 6-8 saat |
| LS_DEBT_PAYTRANS | 150M | 1M | 4-5 saat |
| Diğer tablolar | ~50M | 500K | 2-3 saat |
| **TOPLAM** | | | **15-20 saat** |
| Index oluşturma | | | 4-6 saat |
| **GRAND TOTAL** | | | **20-26 saat** |

Pilot test ile bu süreleri doğrulayın (100K agreement subset).
