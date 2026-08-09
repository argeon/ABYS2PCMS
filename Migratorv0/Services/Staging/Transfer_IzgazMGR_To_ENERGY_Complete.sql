-- =============================================================================
-- Transfer_IzgazMGR_To_ENERGY_Complete.sql
-- izgazMGR (CTAS staging) → ENERGY complete transfer pipeline
-- 
-- PREREQUISITES:
-- 1. MIGRATOR uygulaması Oracle CTAS'ları izgazMGR'ye aktardı ✓
-- 2. ENERGY hedef tabloları oluşturuldu
-- 3. LREF INT kontrolü yapıldı (max < 2.1B)
--
-- EXECUTION ORDER:
-- Step 1: Create validation checkpoints (izgazMGR)
-- Step 2: Execute parallel transfer (16 workers)
-- Step 3: Validate transfer results
-- Step 4: Create indexes
-- =============================================================================

USE izgazMGR;
GO

SET NOCOUNT ON;
GO

-- =============================================================================
-- STEP 1: VALIDATION CHECKPOINTS (Pre-Transfer Snapshot)
-- =============================================================================

PRINT '========== STEP 1: Creating Validation Checkpoints =========='
PRINT ''

-- Checkpoint table
IF OBJECT_ID('dbo.CTAS_VALIDATION_CHECKPOINT', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CTAS_VALIDATION_CHECKPOINT (
        CHECKPOINT_ID INT IDENTITY(1,1) PRIMARY KEY,
        TABLE_NAME VARCHAR(100) NOT NULL,
        CHECKPOINT_TIME DATETIME DEFAULT GETDATE(),
        ROW_COUNT BIGINT,
        MIN_LREF INT,
        MAX_LREF INT,
        LREF_RANGE_SIZE BIGINT,
        SUM_PAYABLETOTAL DECIMAL(22,2),
        SUM_AMOUNT DECIMAL(22,2),
        SAMPLE_FIRST_10_LREF VARCHAR(500),
        SAMPLE_LAST_10_LREF VARCHAR(500),
        CHECKSUM_SAMPLE BIGINT,
        LREF_INT_OVERFLOW_CHECK VARCHAR(20)  -- SAFE / WARNING / OVERFLOW
    );
    
    CREATE NONCLUSTERED INDEX IX_CHECKPOINT_TABLE 
        ON dbo.CTAS_VALIDATION_CHECKPOINT(TABLE_NAME, CHECKPOINT_TIME DESC);
    
    PRINT 'Created CTAS_VALIDATION_CHECKPOINT table'
END
GO

-- Checkpoint creation procedure
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
    DECLARE @SumPayable DECIMAL(22,2) = 0;
    DECLARE @SumAmount DECIMAL(22,2) = 0;
    DECLARE @First10 VARCHAR(500);
    DECLARE @Last10 VARCHAR(500);
    DECLARE @Checksum BIGINT;
    DECLARE @IntOverflowCheck VARCHAR(20);
    
    PRINT 'Creating checkpoint for ' + @TableName + '...'
    
    BEGIN TRY
        -- Row count
        SET @Sql = N'SELECT @cnt = COUNT_BIG(*) FROM dbo.' + QUOTENAME(@TableName);
        EXEC sp_executesql @Sql, N'@cnt BIGINT OUTPUT', @cnt = @RowCount OUTPUT;
        
        -- LREF range
        SET @Sql = N'SELECT @min = MIN(LREF), @max = MAX(LREF) FROM dbo.' + QUOTENAME(@TableName);
        EXEC sp_executesql @Sql, 
            N'@min INT OUTPUT, @max INT OUTPUT', 
            @min = @MinLref OUTPUT, 
            @max = @MaxLref OUTPUT;
        
        SET @RangeSize = CAST(@MaxLref AS BIGINT) - CAST(@MinLref AS BIGINT) + 1;
        
        -- INT overflow check
        IF @MaxLref > 2147483647
            SET @IntOverflowCheck = 'OVERFLOW';
        ELSE IF @MaxLref > 1500000000
            SET @IntOverflowCheck = 'WARNING';
        ELSE
            SET @IntOverflowCheck = 'SAFE';
        
        -- Sum amounts (table-specific)
        IF @TableName = 'LS_INVOICE'
        BEGIN
            SET @Sql = N'SELECT @sum = SUM(CAST(PAYABLETOTAL AS DECIMAL(22,2))) FROM dbo.' + QUOTENAME(@TableName);
            EXEC sp_executesql @Sql, N'@sum DECIMAL(22,2) OUTPUT', @sum = @SumPayable OUTPUT;
        END
        ELSE IF @AmountColumn IS NOT NULL
        BEGIN
            SET @Sql = N'SELECT @sum = SUM(CAST(' + @AmountColumn + ' AS DECIMAL(22,2))) FROM dbo.' + QUOTENAME(@TableName);
            EXEC sp_executesql @Sql, N'@sum DECIMAL(22,2) OUTPUT', @sum = @SumAmount OUTPUT;
        END
        
        -- First 10 LREFs (comma-separated)
        SET @Sql = N'SELECT @first = STRING_AGG(CAST(LREF AS VARCHAR), '','') 
                     FROM (SELECT TOP 10 LREF FROM dbo.' + QUOTENAME(@TableName) + ' ORDER BY LREF) t';
        EXEC sp_executesql @Sql, N'@first VARCHAR(500) OUTPUT', @first = @First10 OUTPUT;
        
        -- Last 10 LREFs
        SET @Sql = N'SELECT @last = STRING_AGG(CAST(LREF AS VARCHAR), '','') 
                     FROM (SELECT TOP 10 LREF FROM dbo.' + QUOTENAME(@TableName) + ' ORDER BY LREF DESC) t';
        EXEC sp_executesql @Sql, N'@last VARCHAR(500) OUTPUT', @last = @Last10 OUTPUT;
        
        -- Checksum (sample 100K rows for performance)
        SET @Sql = N'SELECT @chk = CHECKSUM_AGG(CHECKSUM(*)) 
                     FROM (SELECT TOP 100000 * FROM dbo.' + QUOTENAME(@TableName) + ' ORDER BY LREF) t';
        EXEC sp_executesql @Sql, N'@chk BIGINT OUTPUT', @chk = @Checksum OUTPUT;
        
        -- Insert checkpoint
        INSERT INTO dbo.CTAS_VALIDATION_CHECKPOINT (
            TABLE_NAME, ROW_COUNT, MIN_LREF, MAX_LREF, LREF_RANGE_SIZE,
            SUM_PAYABLETOTAL, SUM_AMOUNT, SAMPLE_FIRST_10_LREF, SAMPLE_LAST_10_LREF,
            CHECKSUM_SAMPLE, LREF_INT_OVERFLOW_CHECK
        ) VALUES (
            @TableName, @RowCount, @MinLref, @MaxLref, @RangeSize,
            @SumPayable, @SumAmount, @First10, @Last10, @Checksum, @IntOverflowCheck
        );
        
        -- Display result
        PRINT 'Checkpoint created: ' + @TableName + ' (' + CAST(@RowCount AS VARCHAR) + ' rows, LREF range ' 
            + CAST(@MinLref AS VARCHAR) + '-' + CAST(@MaxLref AS VARCHAR) + ', Status: ' + @IntOverflowCheck + ')'
        
        IF @IntOverflowCheck = 'OVERFLOW'
            RAISERROR('WARNING: LREF exceeds INT max (2,147,483,647) for table %s', 16, 1, @TableName);
        ELSE IF @IntOverflowCheck = 'WARNING'
            RAISERROR('WARNING: LREF approaching INT limit for table %s', 10, 1, @TableName);
            
    END TRY
    BEGIN CATCH
        PRINT 'ERROR creating checkpoint for ' + @TableName + ': ' + ERROR_MESSAGE()
        RETURN -1;
    END CATCH
    
    RETURN 0;
END
GO

-- Create checkpoints for all CTAS tables
PRINT 'Creating validation checkpoints...'
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
GO

-- View checkpoints
SELECT * FROM dbo.CTAS_VALIDATION_CHECKPOINT ORDER BY CHECKPOINT_TIME DESC;
GO

PRINT ''
PRINT '========== STEP 1 Completed =========='
PRINT ''
GO

-- =============================================================================
-- STEP 2: PARALLEL TRANSFER PROCEDURE
-- =============================================================================

PRINT '========== STEP 2: Transfer Procedure Setup =========='
PRINT ''

-- Transfer log table
IF OBJECT_ID('dbo.ENERGY_TRANSFER_LOG', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ENERGY_TRANSFER_LOG (
        LOG_ID INT IDENTITY(1,1) PRIMARY KEY,
        TABLE_NAME VARCHAR(100),
        WORKER_ID INT,
        BATCH_ID INT,
        START_TIME DATETIME,
        END_TIME DATETIME,
        ROW_COUNT BIGINT,
        STATUS VARCHAR(20),  -- RUNNING, SUCCESS, FAILED
        ERROR_MESSAGE VARCHAR(MAX),
        DURATION_SECONDS AS DATEDIFF(SECOND, START_TIME, END_TIME),
        ROWS_PER_SECOND AS CASE 
            WHEN DATEDIFF(SECOND, START_TIME, END_TIME) > 0 
            THEN ROW_COUNT / DATEDIFF(SECOND, START_TIME, END_TIME) 
            ELSE 0 
        END
    );
    
    CREATE NONCLUSTERED INDEX IX_TRANSFER_LOG 
        ON dbo.ENERGY_TRANSFER_LOG(TABLE_NAME, WORKER_ID, STATUS);
    
    PRINT 'Created ENERGY_TRANSFER_LOG table'
END
GO

-- Main transfer procedure
CREATE OR ALTER PROCEDURE dbo.sp_Transfer_To_ENERGY_Parallel
    @SourceTable VARCHAR(100),
    @TargetDatabase VARCHAR(100) = 'IZGAZ',
    @TargetTablePrefix VARCHAR(50) = 'LS_315_0126',
    @WorkerId INT = 0,
    @TotalWorkers INT = 16,
    @BatchSize INT = 500000,
    @PreserveIdentity BIT = 1  -- For LS_INVOICE (LREF preservation)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TargetTable VARCHAR(200) = @TargetDatabase + '.dbo.' + @TargetTablePrefix + '_' + 
        REPLACE(REPLACE(@SourceTable, 'LS_', ''), 'DEBT_PAYTRANS', 'PAYTRANS');
    DECLARE @Sql NVARCHAR(MAX);
    DECLARE @MinLref INT;
    DECLARE @MaxLref INT;
    DECLARE @CurrentLref INT;
    DECLARE @BatchId INT = 0;
    DECLARE @TotalRows BIGINT = 0;
    DECLARE @StartTime DATETIME = GETDATE();
    DECLARE @RowsInserted INT;
    
    PRINT 'Worker ' + CAST(@WorkerId AS VARCHAR) + ': Starting transfer of ' + @SourceTable + ' to ' + @TargetTable
    
    BEGIN TRY
        -- Get LREF range for this worker (partition by OWNERREF)
        SET @Sql = N'SELECT 
            @min = MIN(LREF),
            @max = MAX(LREF)
        FROM dbo.' + QUOTENAME(@SourceTable) + '
        WHERE OWNERREF % @workers = @worker';
        
        EXEC sp_executesql @Sql, 
            N'@workers INT, @worker INT, @min INT OUTPUT, @max INT OUTPUT',
            @workers = @TotalWorkers,
            @worker = @WorkerId,
            @min = @MinLref OUTPUT,
            @max = @MaxLref OUTPUT;
        
        IF @MinLref IS NULL OR @MaxLref IS NULL
        BEGIN
            PRINT 'Worker ' + CAST(@WorkerId AS VARCHAR) + ': No data in partition'
            RETURN 0;
        END
        
        PRINT 'Worker ' + CAST(@WorkerId AS VARCHAR) + ': LREF range ' + CAST(@MinLref AS VARCHAR) + ' - ' + CAST(@MaxLref AS VARCHAR)
        
        SET @CurrentLref = @MinLref;
        
        -- Batch loop
        WHILE @CurrentLref <= @MaxLref
        BEGIN
            SET @BatchId = @BatchId + 1;
            
            -- Log batch start
            INSERT INTO dbo.ENERGY_TRANSFER_LOG (TABLE_NAME, WORKER_ID, BATCH_ID, START_TIME, STATUS, ROW_COUNT)
            VALUES (@SourceTable, @WorkerId, @BatchId, GETDATE(), 'RUNNING', 0);
            
            DECLARE @LogId INT = SCOPE_IDENTITY();
            
            BEGIN TRY
                -- IDENTITY_INSERT control
                IF @PreserveIdentity = 1
                    EXEC('SET IDENTITY_INSERT ' + @TargetTable + ' ON');
                
                -- Batch insert
                SET @Sql = N'
                    INSERT INTO ' + @TargetTable + ' WITH (TABLOCK)
                    SELECT TOP (@batchSize) *
                    FROM izgazMGR.dbo.' + QUOTENAME(@SourceTable) + '
                    WHERE OWNERREF % @workers = @worker
                      AND LREF >= @current
                      AND LREF <= @max
                    ORDER BY LREF';
                
                EXEC sp_executesql @Sql,
                    N'@batchSize INT, @workers INT, @worker INT, @current INT, @max INT',
                    @batchSize = @BatchSize,
                    @workers = @TotalWorkers,
                    @worker = @WorkerId,
                    @current = @CurrentLref,
                    @max = @MaxLref;
                
                SET @RowsInserted = @@ROWCOUNT;
                SET @TotalRows = @TotalRows + @RowsInserted;
                
                IF @PreserveIdentity = 1
                    EXEC('SET IDENTITY_INSERT ' + @TargetTable + ' OFF');
                
                -- Update log
                UPDATE dbo.ENERGY_TRANSFER_LOG
                SET END_TIME = GETDATE(),
                    ROW_COUNT = @RowsInserted,
                    STATUS = 'SUCCESS'
                WHERE LOG_ID = @LogId;
                
                -- Progress reporting
                IF @BatchId % 10 = 0
                BEGIN
                    DECLARE @ElapsedMin DECIMAL(10,2) = DATEDIFF(SECOND, @StartTime, GETDATE()) / 60.0;
                    DECLARE @Rate DECIMAL(15,2) = @TotalRows / NULLIF(@ElapsedMin, 0);
                    
                    RAISERROR('Worker %d: Batch %d, Rows %d, Elapsed %.2f min, Rate %.0f rows/min', 
                        0, 1, @WorkerId, @BatchId, @TotalRows, @ElapsedMin, @Rate) WITH NOWAIT;
                    
                    CHECKPOINT;  -- Optional: reduce log growth
                END
                
                -- Exit if no more rows
                IF @RowsInserted = 0 
                    BREAK;
                
                -- Advance cursor
                SET @CurrentLref = @CurrentLref + @BatchSize;
                
            END TRY
            BEGIN CATCH
                IF @PreserveIdentity = 1
                    EXEC('SET IDENTITY_INSERT ' + @TargetTable + ' OFF');
                
                DECLARE @ErrMsg NVARCHAR(MAX) = ERROR_MESSAGE();
                
                UPDATE dbo.ENERGY_TRANSFER_LOG
                SET END_TIME = GETDATE(),
                    STATUS = 'FAILED',
                    ERROR_MESSAGE = @ErrMsg
                WHERE LOG_ID = @LogId;
                
                RAISERROR('Worker %d Batch %d failed: %s', 16, 1, @WorkerId, @BatchId, @ErrMsg);
                RETURN -1;
            END CATCH
        END
        
        PRINT 'Worker ' + CAST(@WorkerId AS VARCHAR) + ' completed: ' + CAST(@BatchId AS VARCHAR) + ' batches, ' + CAST(@TotalRows AS VARCHAR) + ' rows'
        RETURN 0;
        
    END TRY
    BEGIN CATCH
        PRINT 'Worker ' + CAST(@WorkerId AS VARCHAR) + ' error: ' + ERROR_MESSAGE()
        RETURN -1;
    END CATCH
END
GO

PRINT 'Transfer procedure created'
PRINT ''
PRINT '========== STEP 2 Completed =========='
PRINT ''
PRINT '========== READY FOR EXECUTION =========='
PRINT ''
PRINT 'To execute transfer, run workers in separate SSMS windows:'
PRINT ''
PRINT '-- Worker 0 (Window 1)'
PRINT 'EXEC izgazMGR.dbo.sp_Transfer_To_ENERGY_Parallel @SourceTable=''LS_INVOICE'', @WorkerId=0, @TotalWorkers=16;'
PRINT ''
PRINT '-- Worker 1 (Window 2)'
PRINT 'EXEC izgazMGR.dbo.sp_Transfer_To_ENERGY_Parallel @SourceTable=''LS_INVOICE'', @WorkerId=1, @TotalWorkers=16;'
PRINT ''
PRINT '-- ... Workers 2-15 (Windows 3-16)'
PRINT ''
GO

-- =============================================================================
-- STEP 3: VALIDATION PROCEDURE
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.sp_Validate_Transfer_Against_Checkpoint
    @SourceTable VARCHAR(100),
    @TargetDatabase VARCHAR(100) = 'IZGAZ',
    @TargetTablePrefix VARCHAR(50) = 'LS_315_0126'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TargetTable VARCHAR(200) = @TargetDatabase + '.dbo.' + @TargetTablePrefix + '_' + 
        REPLACE(REPLACE(@SourceTable, 'LS_', ''), 'DEBT_PAYTRANS', 'PAYTRANS');
    
    PRINT 'Validating ' + @SourceTable + ' → ' + @TargetTable
    
    -- Get original checkpoint
    DECLARE @OrigRowCount BIGINT, @OrigMinLref INT, @OrigMaxLref INT, @OrigSum DECIMAL(22,2), @OrigChecksum BIGINT;
    
    SELECT TOP 1
        @OrigRowCount = ROW_COUNT,
        @OrigMinLref = MIN_LREF,
        @OrigMaxLref = MAX_LREF,
        @OrigSum = COALESCE(SUM_PAYABLETOTAL, SUM_AMOUNT),
        @OrigChecksum = CHECKSUM_SAMPLE
    FROM dbo.CTAS_VALIDATION_CHECKPOINT
    WHERE TABLE_NAME = @SourceTable
    ORDER BY CHECKPOINT_TIME DESC;
    
    -- Get target stats
    DECLARE @Sql NVARCHAR(MAX);
    DECLARE @TgtRowCount BIGINT, @TgtMinLref INT, @TgtMaxLref INT, @TgtSum DECIMAL(22,2), @TgtChecksum BIGINT;
    
    SET @Sql = N'SELECT 
        @cnt = COUNT_BIG(*),
        @min = MIN(LREF),
        @max = MAX(LREF)
    FROM ' + @TargetTable;
    EXEC sp_executesql @Sql, 
        N'@cnt BIGINT OUTPUT, @min INT OUTPUT, @max INT OUTPUT',
        @cnt = @TgtRowCount OUTPUT,
        @min = @TgtMinLref OUTPUT,
        @max = @TgtMaxLref OUTPUT;
    
    -- Sum validation
    IF @SourceTable = 'LS_INVOICE'
        SET @Sql = N'SELECT @sum = SUM(CAST(PAYABLETOTAL AS DECIMAL(22,2))) FROM ' + @TargetTable;
    ELSE IF @SourceTable LIKE '%INVLINES%'
        SET @Sql = N'SELECT @sum = SUM(CAST(AMOUNT AS DECIMAL(22,2))) FROM ' + @TargetTable;
    ELSE
        SET @Sql = N'SELECT @sum = 0';
    
    EXEC sp_executesql @Sql, N'@sum DECIMAL(22,2) OUTPUT', @sum = @TgtSum OUTPUT;
    
    -- Display results
    SELECT 
        @SourceTable AS SOURCE_TABLE,
        @TargetTable AS TARGET_TABLE,
        @OrigRowCount AS ORIGINAL_COUNT,
        @TgtRowCount AS TARGET_COUNT,
        @OrigRowCount - @TgtRowCount AS DIFF_COUNT,
        @OrigMinLref AS ORIG_MIN_LREF,
        @TgtMinLref AS TGT_MIN_LREF,
        @OrigMaxLref AS ORIG_MAX_LREF,
        @TgtMaxLref AS TGT_MAX_LREF,
        @OrigSum AS ORIG_SUM,
        @TgtSum AS TGT_SUM,
        @OrigSum - @TgtSum AS DIFF_SUM,
        CASE 
            WHEN @OrigRowCount = @TgtRowCount 
                AND @OrigMinLref = @TgtMinLref
                AND @OrigMaxLref = @TgtMaxLref
                AND ABS(@OrigSum - @TgtSum) < 0.01
            THEN '✅ PASS'
            WHEN ABS(@OrigRowCount - @TgtRowCount) < 100
            THEN '⚠️ WARN'
            ELSE '❌ FAIL'
        END AS STATUS;
END
GO

PRINT 'Validation procedure created'
PRINT ''
GO
