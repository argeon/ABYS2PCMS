/* ============================================================
   SCRIPT_ID : AGR_BNK_TALIMAT_MIGRATE
   SCRIPT_NO : 361
   FILE      : 361_AGR_BNK_TALIMAT__migrate.sql
   VERSION   : 4
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS_BNK_TALIMAT
-- Kaynak  : izgazMGR.dbo.CS_AGREEMENT_AUTO_PAYMENT_LOG
-- Hedef   : energy.dbo.LS_BNK_TALIMAT
-- ID      : IDENTITY (yeni)
-- ABYS_ID : kaynak ID
-- FIRMA_KODU : '005'
-- BANKA_KODU : LS_BANK.LREF (ABYS_ID = BANK_ID) — scalar UDF yok (cross-db)
-- SOZLESME_HESABI / SOZLESME_NUMARASI : AGREEMENT_ID
--
-- User: ABYS + 10000 (inline; FN_MIG_MAP_USER_USERID cagrilmaz).
-- Idempotent: NOT EXISTS (ABYS_ID = kaynak ID)
-- HARD_RESET: yalnizca ABYS_ID IS NOT NULL siler
-- Önkoşul: 121 LS_BANK bridge (ABYS_ID dolu)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_BNK_TALIMAT_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @RowCount  INT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    INSERT INTO dbo.LS_BNK_TALIMAT (
        ABYS_ID,
        BANKA_KODU,
        ACIKLAMA,
        SOZLESME_NUMARASI,
        TESISAT_NUMARASI,
        FIRMA_KODU,
        TRAN_CODE,
        IPTAL_KULLANICI_KODU,
        TALIMAT_TARIHI,
        IPTAL_TARIHI,
        IS_ACTIVE,
        UPDATED_TIMESTAMP,
        CREATED_TIMESTAMP,
        ISLEM_KANALI,
        KULLANICI_KODU,
        ABONE_NUMARASI,
        SOZLESME_HESABI,
        ABYS_AGREEMENT_ID,
        ABYS_BANK_ID,
        ABYS_CREATED_USER_ID,
        ABYS_CANCEL_USER_ID
    )
    SELECT
        CAST(s.ID AS INT),
        CAST(bk.LREF AS NVARCHAR(10)),
        LEFT(s.DESCRIPTION, 500),
        LEFT(CAST(s.AGREEMENT_ID AS NVARCHAR(20)), 12),
        LEFT(CAST(i.INSTALLATION_NUMBER AS NVARCHAR(30)), 20),
        N'005',
        NULL,
        CASE
            WHEN s.CANCEL_USER_ID IS NULL THEN NULL
            ELSE CAST(s.CANCEL_USER_ID AS INT) + 10000
        END,
        CASE
            WHEN s.INSTRUCTION_DATE IS NULL THEN NULL
            WHEN CAST(s.INSTRUCTION_DATE AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            WHEN CAST(s.INSTRUCTION_DATE AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
            ELSE CAST(s.INSTRUCTION_DATE AS DATETIME)
        END,
        CASE
            WHEN s.CANCEL_DATE IS NULL THEN NULL
            WHEN CAST(s.CANCEL_DATE AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            WHEN CAST(s.CANCEL_DATE AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
            ELSE CAST(s.CANCEL_DATE AS DATETIME)
        END,
        CASE WHEN s.CANCEL_DATE IS NULL THEN 1 ELSE 0 END,
        CASE
            WHEN s.UPDATED_TIMESTAMP IS NULL THEN NULL
            WHEN CAST(s.UPDATED_TIMESTAMP AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            WHEN CAST(s.UPDATED_TIMESTAMP AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
            ELSE CAST(s.UPDATED_TIMESTAMP AS DATETIME)
        END,
        ISNULL(
            CASE
                WHEN s.CREATED_TIMESTAMP IS NULL THEN NULL
                WHEN CAST(s.CREATED_TIMESTAMP AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
                WHEN CAST(s.CREATED_TIMESTAMP AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
                ELSE CAST(s.CREATED_TIMESTAMP AS DATETIME)
            END,
            CAST('19000101' AS DATETIME)),
        NULL,
        CAST(CAST(s.CREATED_USER_ID AS INT) + 10000 AS NVARCHAR(100)),
        LEFT(CAST(agr.BENEFITED_REGISTER_ID AS NVARCHAR(30)), 100),
        LEFT(CAST(s.AGREEMENT_ID AS NVARCHAR(30)), 20),
        CAST(s.AGREEMENT_ID AS INT),
        CAST(s.BANK_ID AS INT),
        CAST(s.CREATED_USER_ID AS INT),
        CAST(s.CANCEL_USER_ID AS INT)
    FROM izgazMGR.dbo.CS_AGREEMENT_AUTO_PAYMENT_LOG s
    LEFT JOIN izgazMGR.dbo.CS_AGREEMENT agr
        ON agr.ID = s.AGREEMENT_ID
    LEFT JOIN izgazMGR.dbo.CS_INSTALLATION i
        ON i.ID = agr.INSTALLATION_ID
    OUTER APPLY (
        SELECT TOP (1) b.LREF
        FROM dbo.LS_BANK b
        WHERE b.ABYS_ID = CAST(s.BANK_ID AS INT)
        ORDER BY b.LREF
    ) bk
    WHERE s.ID BETWEEN @BatchFrom AND @BatchTo
      AND s.ID BETWEEN 1 AND 2147483647
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.LS_BNK_TALIMAT t
          WHERE t.ABYS_ID = CAST(s.ID AS INT)
      );

    SET @RowCount = @@ROWCOUNT;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_BNK_TALIMAT_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_BNK_TALIMAT t
        WHERE t.ABYS_ID = @CurID
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_BNK_TALIMAT_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_BNK_TALIMAT_HARD_RESET
    @DELETE_BATCH INT = 10000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @TotalStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_BNK_TALIMAT ABYS kayitlari (batch=%d) ***', 0, 1, @DELETE_BATCH) WITH NOWAIT;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_BNK_TALIMAT
        WHERE ABYS_ID IS NOT NULL;

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
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s', 0, 1, @TotalStr) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS_BNK_TALIMAT
    @BATCH_SIZE  INT = 5000,
    @RESUME      BIT = 1,
    @HARD_RESET  BIT = 0,
    @MAX_ERROR   INT = 500,
    @BISECT_MIN  INT = 1,
    @DEBUG       BIT = 0
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'LS_BNK_TALIMAT',
        @RunID          UNIQUEIDENTIFIER,
        @TableRunID     BIGINT,
        @LastBridgeKey  BIGINT           = 0,
        @MaxBridgeKey   BIGINT,
        @SourceCount    BIGINT,
        @TargetCount    BIGINT,
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
        @ValidResult    INT;

    EXEC @ValidResult = dbo.SP_MIG_BNK_TALIMAT_VALIDATE_ALL @RaiseOnMissing = 1;
    IF @ValidResult <> 0
        RETURN @ValidResult;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_BNK_TALIMAT_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount = SUM(p.rows)
    FROM izgazMGR.sys.partitions p
    INNER JOIN izgazMGR.sys.tables t ON t.object_id = p.object_id
    INNER JOIN izgazMGR.sys.schemas sch ON sch.schema_id = t.schema_id
    WHERE sch.name = 'dbo'
      AND t.name = 'CS_AGREEMENT_AUTO_PAYMENT_LOG'
      AND p.index_id IN (0, 1);

    SELECT @MaxBridgeKey = MAX(s.ID)
    FROM izgazMGR.dbo.CS_AGREEMENT_AUTO_PAYMENT_LOG s
    WHERE s.ID BETWEEN 1 AND 2147483647;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'CS_AGREEMENT_AUTO_PAYMENT_LOG',
        @TargetTable    = 'LS_BNK_TALIMAT',
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
            FROM izgazMGR.dbo.CS_AGREEMENT_AUTO_PAYMENT_LOG s
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

            EXEC dbo.SP_MIG_BNK_TALIMAT_INSERT_RANGE
                @BatchFrom = @BatchFrom,
                @BatchTo   = @BatchTo,
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
                        EXEC dbo.SP_MIG_BNK_TALIMAT_INSERT_ONE
                            @CurID = @BisectFrom, @RowInserted = @RowInserted OUTPUT;

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

                    EXEC dbo.SP_MIG_BNK_TALIMAT_INSERT_RANGE
                        @BatchFrom = @BisectFrom,
                        @BatchTo   = @BisectMid,
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

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_BNK_TALIMAT
    WHERE ABYS_ID IS NOT NULL;

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

    SET @FinishErrorMsg = CASE
        WHEN @Stopped = 1 THEN N'Max hata limiti veya manuel durdurma'
        ELSE NULL
    END;

    EXEC energy.dbo.SP_MIG_LOG_FINISH_RUN
        @RunID = @RunID,
        @Status = @RunStatus,
        @TargetRowCount = @TargetCount,
        @ErrorMsg = @FinishErrorMsg;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = 'BITTI | status=' + @RunStatus
            + ' | ABYS hedef=' + CAST(ISNULL(@TargetCount, 0) AS VARCHAR(20))
            + ' | inserted~' + CAST(ISNULL(@InsertedCount, 0) AS VARCHAR(20))
            + ' | err=' + CAST(ISNULL(@ErrorCount, 0) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

PRINT '361_AGR_BNK_TALIMAT__migrate OK';
GO

/*
EXEC energy.dbo.SP_MIGRATE_LS_BNK_TALIMAT @HARD_RESET=1,
     @RESUME = 0, @BATCH_SIZE = 50000, @DEBUG = 1;
*/
