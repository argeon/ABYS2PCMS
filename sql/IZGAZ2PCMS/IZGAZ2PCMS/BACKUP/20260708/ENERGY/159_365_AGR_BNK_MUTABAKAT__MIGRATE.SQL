/* ============================================================
   SCRIPT_ID : AGR_BNK_MUTABAKAT_MIGRATE
   SCRIPT_NO : 365
   FILE      : 365_AGR_BNK_MUTABAKAT__migrate.sql
   VERSION   : 4
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS_BNK_MUTABAKAT_DETAY
-- Kaynak  : izgazMGR.dbo.LS_BANK_CONFIRM  (= MIGRATION.LS_BANK_CONFIRM dump)
-- Hedef   : energy.dbo.LS_BNK_MUTABAKAT_DETAY
-- ID      : IDENTITY (yeni)
-- ABYS_ID : kaynak ID
-- FIRMA_ID: 5 (yalnizca bu firma; diger firmalar dokunulmaz)
-- BANK_REF: LS_BANK.LREF (ABYS_ID = BANK_ID) — zorunlu (INNER JOIN)
-- MUTABAKAT_DURUMU (PCMS):
--   ABYS APPROVAL_STATUS 2→1 Basarili, 3→0 Basarisiz, 1→3 Kayit Yok
-- AUTO_PAYMENT_COUNT/AMOUNT ← kaynak AUTO_PAYMENT_*
-- SYS_TAHSILAT_* / SYS_IPTAL_* aktarilmaz (NULL)
--
-- User: ABYS + 10000 (inline; FN_MIG_MAP_USER_USERID cagrilmaz).
-- Idempotent: NOT EXISTS (ABYS_ID = kaynak ID AND FIRMA_ID = 5)
-- HARD_RESET: yalnizca ABYS_ID IS NOT NULL AND FIRMA_ID = 5 siler
-- Gate: PRE + POST BANK LREF dogrulama (orphan → FAIL)
-- Onkosul: 121 LS_BANK bridge + 364 setup
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_BNK_MUTABAKAT_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @FirmaId   INT = 5,
    @RowCount  INT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    -- BANK_REF zorunlu: resolve edilemeyen BANK_ID satirlari yazilmaz
    -- (PRE gate zaten bunlari FAIL eder; burada ikinci savunma)
    INSERT INTO dbo.LS_BNK_MUTABAKAT_DETAY (
        FIRMA_ID,
        BANK_REF,
        MUTABAKAT_TARIHI,
        TAHSILAT_ADET,
        TAHSILAT_TUTAR,
        IPTAL_ADET,
        IPTAL_TUTAR,
        TRAN_CODE,
        MUTABAKAT_DURUMU,
        CREATED,
        CREATED_TIMESTAMP,
        UPDATED,
        UPDATED_TIMESTAMP,
        AUTO_PAYMENT_COUNT,
        AUTO_PAYMENT_AMOUNT,
        ABYS_ID,
        ABYS_BANK_ID,
        ABYS_CASH_ID,
        ABYS_TYPE,
        ABYS_APPROVAL_STATUS,
        ABYS_APPROVAL_USER_ID,
        ABYS_CREATED_USER_ID,
        ABYS_UPDATED_USER_ID
    )
    SELECT
        @FirmaId,                                               -- FIRMA_ID (Izgaz / 005)
        CAST(bk.LREF AS INT),                                   -- BANK_REF (zorunlu)
        CASE
            WHEN s.ACTION_DATE IS NULL THEN NULL
            WHEN CAST(s.ACTION_DATE AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            WHEN CAST(s.ACTION_DATE AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
            ELSE CAST(s.ACTION_DATE AS DATE)
        END,                                                    -- MUTABAKAT_TARIHI
        CAST(s.PAYMENT_COUNT AS INT),                           -- TAHSILAT_ADET
        CAST(s.PAYMENT_AMOUNT AS FLOAT),                        -- TAHSILAT_TUTAR
        CAST(s.CANCELLATION_COUNT AS INT),                      -- IPTAL_ADET
        CAST(s.CANCELLATION_AMOUNT AS FLOAT),                   -- IPTAL_TUTAR
        LEFT(s.SERVICE_RECEIPT_NUMBER, 15),                     -- TRAN_CODE
        CASE CAST(s.APPROVAL_STATUS AS INT)                     -- MUTABAKAT_DURUMU (PCMS)
            WHEN 2 THEN 1   -- APPROVED → Basarili
            WHEN 3 THEN 0   -- REJECTED → Basarisiz
            WHEN 1 THEN 3   -- NEW      → Kayit Yok (tamamlanmamis)
            ELSE NULL
        END,
        CAST(CAST(s.CREATED_USER_ID AS INT) + 10000 AS INT),    -- CREATED
        ISNULL(
            CASE
                WHEN s.CREATED_TIMESTAMP IS NULL THEN NULL
                WHEN CAST(s.CREATED_TIMESTAMP AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
                WHEN CAST(s.CREATED_TIMESTAMP AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
                ELSE CAST(s.CREATED_TIMESTAMP AS DATETIME)
            END,
            CAST('19000101' AS DATETIME)),                      -- CREATED_TIMESTAMP
        CASE
            WHEN s.UPDATED_USER_ID IS NULL THEN NULL
            ELSE CAST(CAST(s.UPDATED_USER_ID AS INT) + 10000 AS INT)
        END,                                                    -- UPDATED
        CASE
            WHEN s.UPDATED_TIMESTAMP IS NULL THEN NULL
            WHEN CAST(s.UPDATED_TIMESTAMP AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            WHEN CAST(s.UPDATED_TIMESTAMP AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
            ELSE CAST(s.UPDATED_TIMESTAMP AS DATETIME)
        END,                                                    -- UPDATED_TIMESTAMP
        CAST(s.AUTO_PAYMENT_COUNT AS INT),                      -- AUTO_PAYMENT_COUNT
        CAST(s.AUTO_PAYMENT_AMOUNT AS FLOAT),                   -- AUTO_PAYMENT_AMOUNT
        -- SYS_TAHSILAT_* / SYS_IPTAL_* bilinçli olarak INSERT'te yok → NULL
        CAST(s.ID AS INT),                                      -- ABYS_ID
        CAST(s.BANK_ID AS INT),                                 -- ABYS_BANK_ID
        CAST(s.CASH_ID AS INT),                                 -- ABYS_CASH_ID
        CAST(s.TYPE AS INT),                                    -- ABYS_TYPE
        CAST(s.APPROVAL_STATUS AS INT),                         -- ABYS_APPROVAL_STATUS
        CAST(s.APPROVAL_USER_ID AS INT),                        -- ABYS_APPROVAL_USER_ID
        CAST(s.CREATED_USER_ID AS INT),                         -- ABYS_CREATED_USER_ID
        CAST(s.UPDATED_USER_ID AS INT)                          -- ABYS_UPDATED_USER_ID
    FROM izgazMGR.dbo.LS_BANK_CONFIRM s
    CROSS APPLY (
        SELECT TOP (1) b.LREF
        FROM dbo.LS_BANK b
        WHERE b.ABYS_ID = CAST(s.BANK_ID AS INT)
        ORDER BY b.LREF
    ) bk
    WHERE s.ID BETWEEN @BatchFrom AND @BatchTo
      AND s.ID BETWEEN 1 AND 2147483647
      AND s.BANK_ID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.LS_BNK_MUTABAKAT_DETAY t
          WHERE t.ABYS_ID = CAST(s.ID AS INT)
            AND t.FIRMA_ID = @FirmaId
      );

    SET @RowCount = @@ROWCOUNT;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_BNK_MUTABAKAT_INSERT_ONE
    @CurID       BIGINT,
    @FirmaId     INT = 5,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_BNK_MUTABAKAT_DETAY t
        WHERE t.ABYS_ID = @CurID
          AND t.FIRMA_ID = @FirmaId
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_BNK_MUTABAKAT_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @FirmaId   = @FirmaId,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_BNK_MUTABAKAT_HARD_RESET
    @FirmaId      INT = 5,
    @DELETE_BATCH INT = 10000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @TotalStr VARCHAR(20);

    -- Diger firmalarin satirlari ASLA silinmez
    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_BNK_MUTABAKAT_DETAY ABYS + FIRMA_ID=%d (batch=%d) ***', 0, 1, @FirmaId, @DELETE_BATCH) WITH NOWAIT;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_BNK_MUTABAKAT_DETAY
        WHERE ABYS_ID IS NOT NULL
          AND FIRMA_ID = @FirmaId;

        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;

        SET @TotalDeleted += @Deleted;

        IF @DEBUG = 1
        BEGIN
            SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
            RAISERROR('HARD RESET silindi: +%d (toplam %s)', 0, 1, @Deleted, @TotalStr) WITH NOWAIT;
        END
    END

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s (FIRMA_ID=%d)', 0, 1, @TotalStr, @FirmaId) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS_BNK_MUTABAKAT_DETAY
    @BATCH_SIZE  INT = 5000,
    @RESUME      BIT = 1,
    @HARD_RESET  BIT = 0,
    @MAX_ERROR   INT = 500,
    @BISECT_MIN  INT = 1,
    @FirmaId     INT = 5,
    @DEBUG       BIT = 0
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'LS_BNK_MUTABAKAT_DETAY',
        @RunID          UNIQUEIDENTIFIER,
        @TableRunID     BIGINT,
        @LastBridgeKey  BIGINT           = 0,
        @MaxBridgeKey   BIGINT,
        @SourceCount    BIGINT,
        @TargetCount    BIGINT,
        @OtherFirmaCnt  BIGINT,
        @BatchNo        INT              = 0,
        @InsertedCount  BIGINT           = 0,
        @SkippedCount   BIGINT           = 0,
        @ErrorCount     BIGINT           = 0,
        @BatchFrom      BIGINT,
        @BatchTo        BIGINT,
        @RowCount       INT,
        @ErrMsg         NVARCHAR(4000),
        @SingleErrMsg   NVARCHAR(4000),
        @Msg            NVARCHAR(500),
        @BatchStart     DATETIME2(3),
        @ElapsedMs      INT,
        @ExecMode       VARCHAR(20),
        @RunStatus      VARCHAR(25),
        @PhaseStatus    VARCHAR(20),
        @Stopped        BIT              = 0,
        @FinishErrorMsg NVARCHAR(4000),
        @BisectFrom     BIGINT,
        @BisectTo       BIGINT,
        @BisectMid      BIGINT,
        @BisectSize     INT,
        @BisectRows     INT,
        @BisectLogFrom  BIGINT,
        @RowInserted    BIT,
        @ValidResult    INT,
        @PostBankRc     INT;

    EXEC @ValidResult = dbo.SP_MIG_BNK_MUTABAKAT_VALIDATE_ALL
        @RaiseOnMissing = 1,
        @FirmaId = @FirmaId;
    IF @ValidResult <> 0
        RETURN @ValidResult;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_BNK_MUTABAKAT_HARD_RESET
            @FirmaId = @FirmaId,
            @DELETE_BATCH = @BATCH_SIZE,
            @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    -- Diger firma kayit sayisi (dokunulmamali)
    SELECT @OtherFirmaCnt = COUNT_BIG(*)
    FROM energy.dbo.LS_BNK_MUTABAKAT_DETAY
    WHERE FIRMA_ID IS NULL
       OR FIRMA_ID <> @FirmaId;

    SELECT @SourceCount = SUM(p.rows)
    FROM izgazMGR.sys.partitions p
    INNER JOIN izgazMGR.sys.tables t ON t.object_id = p.object_id
    INNER JOIN izgazMGR.sys.schemas sch ON sch.schema_id = t.schema_id
    WHERE sch.name = 'dbo'
      AND t.name = 'LS_BANK_CONFIRM'
      AND p.index_id IN (0, 1);

    SELECT @MaxBridgeKey = MAX(s.ID)
    FROM izgazMGR.dbo.LS_BANK_CONFIRM s
    WHERE s.ID BETWEEN 1 AND 2147483647;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_BANK_CONFIRM',
        @TargetTable    = 'LS_BNK_MUTABAKAT_DETAY',
        @RunPhase       = 'INSERT',
        @ExecMode       = @ExecMode,
        @BatchSize      = @BATCH_SIZE,
        @Phase          = 'INSERT',
        @SourceRowCount = @SourceCount,
        @MaxBridgeKey   = @MaxBridgeKey,
        @Resume         = @RESUME,
        @RunID          = @RunID          OUTPUT,
        @TableRunID     = @TableRunID     OUTPUT,
        @LastBridgeKey  = @LastBridgeKey  OUTPUT,
        @BatchNo        = @BatchNo        OUTPUT,
        @InsertedCount  = @InsertedCount  OUTPUT,
        @SkippedCount   = @SkippedCount   OUTPUT,
        @ErrorCount     = @ErrorCount     OUTPUT;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = 'RUN ' + CAST(@RunID AS VARCHAR(36))
            + ' | FIRMA_ID=' + CAST(@FirmaId AS VARCHAR(10))
            + ' | diger_firma_korunan~' + CAST(ISNULL(@OtherFirmaCnt, 0) AS VARCHAR(20))
            + ' | Kaynak~' + CAST(ISNULL(@SourceCount, 0) AS VARCHAR(20))
            + ' | ID=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @BatchFrom  = @LastBridgeKey + 1;
        SET @RowCount   = 0;

        SELECT @BatchTo = MAX(ID)
        FROM (
            SELECT TOP (@BATCH_SIZE) s.ID
            FROM izgazMGR.dbo.LS_BANK_CONFIRM s
            WHERE s.ID > @LastBridgeKey
              AND s.ID <= 2147483647
            ORDER BY s.ID ASC
        ) x;

        IF @BatchTo IS NULL BREAK;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = 'Batch ' + CAST(@BatchNo AS VARCHAR(10))
                + ' | ' + CAST(@BatchFrom AS VARCHAR(20))
                + '-' + CAST(@BatchTo AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            EXEC dbo.SP_MIG_BNK_MUTABAKAT_INSERT_RANGE
                @BatchFrom = @BatchFrom,
                @BatchTo   = @BatchTo,
                @FirmaId   = @FirmaId,
                @RowCount  = @RowCount OUTPUT;

            COMMIT TRANSACTION;

            SET @LastBridgeKey = @BatchTo;
            SET @ElapsedMs = DATEDIFF(MILLISECOND, @BatchStart, SYSDATETIME());

            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                @RowCount = @RowCount, @ElapsedMs = @ElapsedMs;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            SET @ErrMsg = ERROR_MESSAGE();

            EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                @ErrorMsg = @ErrMsg;

            IF @DEBUG = 1
                RAISERROR('Batch %d HATA → bisect: %s', 0, 1, @BatchNo, @ErrMsg) WITH NOWAIT;

            SET @BisectFrom = @BatchFrom;
            SET @BisectTo   = @BatchTo;

            WHILE @BisectFrom <= @BisectTo AND @Stopped = 0
            BEGIN
                SET @BisectSize = @BisectTo - @BisectFrom + 1;

                IF @BisectSize <= @BISECT_MIN
                BEGIN
                    BEGIN TRY
                        SET @RowInserted = 0;
                        EXEC dbo.SP_MIG_BNK_MUTABAKAT_INSERT_ONE
                            @CurID = @BisectFrom,
                            @FirmaId = @FirmaId,
                            @RowInserted = @RowInserted OUTPUT;

                        IF @RowInserted = 1
                        BEGIN
                            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                                @RunID = @RunID, @TableRunID = @TableRunID,
                                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                                @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom,
                                @BridgeTo = @BisectFrom, @RowCount = 1;
                        END
                    END TRY
                    BEGIN CATCH
                        SET @ErrMsg = ERROR_MESSAGE();
                        SET @SingleErrMsg = LEFT(
                            N'ID=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

                        EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                            @RunID = @RunID, @TableRunID = @TableRunID,
                            @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                            @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom,
                            @BridgeTo = @BisectFrom, @SourceID = @BisectFrom,
                            @IsSingleRow = 1, @ErrorMsg = @SingleErrMsg;

                        SELECT @ErrorCount = tr.ERROR_COUNT
                        FROM energy.dbo.MIG_TABLE_RUN tr
                        WHERE tr.TABLE_RUN_ID = @TableRunID;

                        IF @ErrorCount >= @MAX_ERROR
                        BEGIN
                            SET @Stopped = 1;
                            RAISERROR('Max hata limiti (%d) asildi. Durduruldu.', 16, 1, @MAX_ERROR);
                        END
                    END CATCH

                    SET @BisectFrom += 1;
                    CONTINUE;
                END

                SET @BisectMid = @BisectFrom + (@BisectSize / 2) - 1;

                BEGIN TRY
                    BEGIN TRANSACTION;

                    EXEC dbo.SP_MIG_BNK_MUTABAKAT_INSERT_RANGE
                        @BatchFrom = @BisectFrom,
                        @BatchTo   = @BisectMid,
                        @FirmaId   = @FirmaId,
                        @RowCount  = @BisectRows OUTPUT;

                    SET @BisectLogFrom = @BisectFrom;
                    COMMIT TRANSACTION;

                    EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                        @RunID = @RunID, @TableRunID = @TableRunID,
                        @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                        @BatchNo = @BatchNo, @BridgeFrom = @BisectLogFrom,
                        @BridgeTo = @BisectMid, @RowCount = @BisectRows;

                    SET @BisectFrom = @BisectMid + 1;
                END TRY
                BEGIN CATCH
                    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
                    SET @ErrMsg = ERROR_MESSAGE();
                    SET @BisectTo = @BisectMid;
                END CATCH
            END

            IF @Stopped = 0
                SET @LastBridgeKey = @BatchTo;
        END CATCH

        SELECT
            @InsertedCount = tr.INSERTED_COUNT,
            @SkippedCount  = tr.SKIPPED_COUNT,
            @ErrorCount    = tr.ERROR_COUNT
        FROM energy.dbo.MIG_TABLE_RUN tr
        WHERE tr.TABLE_RUN_ID = @TableRunID;
    END

    -- Yalnizca bu firmanin ABYS satirlari
    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_BNK_MUTABAKAT_DETAY
    WHERE ABYS_ID IS NOT NULL
      AND FIRMA_ID = @FirmaId;

    -- POST: BANK_REF → LS_BANK.LREF hard gate
    SET @PostBankRc = 0;
    BEGIN TRY
        EXEC @PostBankRc = dbo.SP_MIG_BNK_MUTABAKAT_VALIDATE_BANK_LREF
            @FirmaId = @FirmaId,
            @RaiseOnMissing = 1,
            @Phase = 'POST';
    END TRY
    BEGIN CATCH
        SET @PostBankRc = 1;
        SET @ErrMsg = ERROR_MESSAGE();
        SET @Stopped = 1;
        SET @FinishErrorMsg = LEFT(N'POST BANK LREF gate FAIL: ' + @ErrMsg, 4000);
        IF @DEBUG = 1
            RAISERROR('%s', 0, 1, @FinishErrorMsg) WITH NOWAIT;
    END CATCH

    IF @PostBankRc <> 0 AND @FinishErrorMsg IS NULL
    BEGIN
        SET @Stopped = 1;
        SET @FinishErrorMsg = N'POST BANK LREF gate FAIL (orphan/null BANK_REF)';
    END

    IF @Stopped = 1
    BEGIN
        SET @RunStatus   = 'STOPPED';
        SET @PhaseStatus = 'PAUSED';
    END
    ELSE IF @ErrorCount > 0
    BEGIN
        SET @RunStatus   = 'COMPLETED_WITH_ERRORS';
        SET @PhaseStatus = 'DONE';
    END
    ELSE
    BEGIN
        SET @RunStatus   = 'COMPLETED';
        SET @PhaseStatus = 'DONE';
    END

    EXEC energy.dbo.SP_MIG_LOG_FINISH_PHASE
        @TableRunID = @TableRunID, @Status = @PhaseStatus;

    IF @FinishErrorMsg IS NULL AND @Stopped = 1
        SET @FinishErrorMsg = N'Max hata limiti veya manuel durdurma';

    EXEC energy.dbo.SP_MIG_LOG_FINISH_RUN
        @RunID = @RunID,
        @Status = @RunStatus,
        @TargetRowCount = @TargetCount,
        @ErrorMsg = @FinishErrorMsg;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = 'BITTI | status=' + @RunStatus
            + ' | FIRMA_ID=' + CAST(@FirmaId AS VARCHAR(10))
            + ' | ABYS hedef=' + CAST(ISNULL(@TargetCount, 0) AS VARCHAR(20))
            + ' | diger_firma_korunan~' + CAST(ISNULL(@OtherFirmaCnt, 0) AS VARCHAR(20))
            + ' | inserted~' + CAST(ISNULL(@InsertedCount, 0) AS VARCHAR(20))
            + ' | err=' + CAST(ISNULL(@ErrorCount, 0) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    IF @PostBankRc <> 0
        RETURN @PostBankRc;
END
GO

PRINT '365_AGR_BNK_MUTABAKAT__migrate OK';
GO

/*
EXEC energy.dbo.SP_MIGRATE_LS_BNK_MUTABAKAT_DETAY
     @RESUME = 1, @BATCH_SIZE = 5000, @FirmaId = 5, @DEBUG = 1;

-- Yeniden yaz (yalnizca FIRMA_ID=5 ABYS satirlari silinir):
-- EXEC energy.dbo.SP_MIGRATE_LS_BNK_MUTABAKAT_DETAY
--      @HARD_RESET = 1, @BATCH_SIZE = 5000, @FirmaId = 5, @DEBUG = 1;
*/
