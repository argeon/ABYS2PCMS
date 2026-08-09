/* ============================================================
   SCRIPT_ID : INSTALLMENT_INCOME_MIGRATE
   SCRIPT_NO : 616
   FILE      : 616_INSTALLMENT_INCOME__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_INSTALLMENT_INCOME
-- Kaynak  : izgazMGR.dbo.CS_INSTALLMENT_INCOME
-- Hedef   : energy.dbo.LS_005_01_INSTALLMENT_INCOME
-- ABYS_ID : kaynak ID
-- INSTALLMENT_PLAN_REF ← LS_005_01_INSTALLMENT_PLAN.ABYS_ID
--   (= CS_INSTALLMENT_INCOME.INSTALLMENT_PLAN_ID)  [indexed]
-- INCOME_ID Pass1 = ABYS income id (wire sonra)
-- ACCOUNT_REF = NULL (Pass1); ABYS_ACCOUNT_ID saklanir
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_INCOME_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @RowCount  INT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    INSERT INTO energy.dbo.LS_005_01_INSTALLMENT_INCOME (
        INSTALLMENT_PLAN_REF, ACCOUNT_REF, INCOME_ID, AMOUNT, STATUS,
        PAYMENT_DATE, CASH_ID, RECEIPT_SERIAL, RECEIPT_NUMBER,
        ADDDATE, ADDUSER, UPDDATE, UPDUSER,
        ABYS_ID, ABYS_INSTALLMENT_PLAN_ID, ABYS_ACCOUNT_ID, ABYS_INCOME_ID,
        ABYS_ABONE_NO, ABYS_SISTEM_KODU, ABYS_DONEM,
        ABYS_SON_ODEME_TARIHI, ABYS_SIRA_NO, ABYS_SICIL_KODU
    )
    SELECT
        pl.LREF,
        NULL,
        CAST(s.INCOME_ID AS INT),
        CAST(s.AMOUNT AS DECIMAL(18,2)),
        CAST(s.STATUS AS SMALLINT),
        CASE
            WHEN s.PAYMENT_DATE IS NULL THEN NULL
            WHEN CAST(s.PAYMENT_DATE AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            WHEN CAST(s.PAYMENT_DATE AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
            ELSE CAST(s.PAYMENT_DATE AS DATETIME)
        END,
        CAST(s.CASH_ID AS INT),
        LEFT(s.RECEIPT_SERIAL, 10),
        CAST(s.RECEIPT_NUMBER AS DECIMAL(25,0)),
        GETDATE(),
        NULL,
        NULL,
        NULL,
        CAST(s.ID AS BIGINT),
        CAST(s.INSTALLMENT_PLAN_ID AS BIGINT),
        CAST(s.ACCOUNT_ID AS BIGINT),
        CAST(s.INCOME_ID AS BIGINT),
        CAST(s.ABONE_NO_ AS BIGINT),
        CAST(s.SISTEM_KODU_ AS SMALLINT),
        CAST(s.DONEM_ AS BIGINT),
        CASE
            WHEN s.SON_ODEME_TARIHI_ IS NULL THEN NULL
            WHEN CAST(s.SON_ODEME_TARIHI_ AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            ELSE CAST(s.SON_ODEME_TARIHI_ AS DATETIME)
        END,
        CAST(s.SIRA_NO_ AS BIGINT),
        CAST(s.SICIL_KODU_ AS BIGINT)
    FROM izgazMGR.dbo.CS_INSTALLMENT_INCOME s
    LEFT JOIN energy.dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
        ON pl.ABYS_ID = CAST(s.INSTALLMENT_PLAN_ID AS BIGINT)
    WHERE s.ID BETWEEN @BatchFrom AND @BatchTo
      AND s.ID BETWEEN 1 AND 2147483647
      AND NOT EXISTS (
          SELECT 1
          FROM energy.dbo.LS_005_01_INSTALLMENT_INCOME t WITH (NOLOCK)
          WHERE t.ABYS_ID = CAST(s.ID AS BIGINT)
      );

    SET @RowCount = @@ROWCOUNT;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_INCOME_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_INSTALLMENT_INCOME t
        WHERE t.ABYS_ID = @CurID
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_INSTALLMENT_INCOME_INSERT_RANGE
        @BatchFrom = @CurID, @BatchTo = @CurID, @RowCount = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_INCOME_HARD_RESET
    @DELETE_BATCH INT = 20000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @MaxLref INT, @TotalStr VARCHAR(20);

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_005_01_INSTALLMENT_INCOME
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

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_INSTALLMENT_INCOME;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_INSTALLMENT_INCOME', RESEED, @MaxLref) WITH NO_INFOMSGS;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_INSTALLMENT_INCOME
    @BATCH_SIZE  INT = 20000,
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
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_INSTALLMENT_INCOME',
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
        @RowInserted    BIT,
        @MaxLref        INT,
        @CurID          BIGINT;

    EXEC dbo.SP_MIG_INSTALLMENT_INCOME_VALIDATE_ALL @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_INSTALLMENT_INCOME_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
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
    WHERE sch.name = 'dbo' AND t.name = 'CS_INSTALLMENT_INCOME' AND p.index_id IN (0, 1);

    SELECT @MaxBridgeKey = MAX(s.ID)
    FROM izgazMGR.dbo.CS_INSTALLMENT_INCOME s
    WHERE s.ID BETWEEN 1 AND 2147483647;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'CS_INSTALLMENT_INCOME',
        @TargetTable    = 'LS_005_01_INSTALLMENT_INCOME',
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
            + '-' + CAST(ISNULL(@MaxBridgeKey, 0) AS VARCHAR(20));
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
            FROM izgazMGR.dbo.CS_INSTALLMENT_INCOME s
            WHERE s.ID > @LastBridgeKey AND s.ID <= 2147483647
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

            EXEC dbo.SP_MIG_INSTALLMENT_INCOME_INSERT_RANGE
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

            SET @InsertedCount += @RowCount;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            SET @ErrMsg = ERROR_MESSAGE();

            EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                @ErrorMsg = @ErrMsg;

            SET @ErrorCount += 1;

            SET @BisectFrom = @BatchFrom;
            SET @BisectTo   = @BatchTo;

            WHILE @BisectFrom <= @BisectTo AND @Stopped = 0
            BEGIN
                SET @BisectSize = CAST(@BisectTo - @BisectFrom + 1 AS INT);

                IF @BisectSize <= @BISECT_MIN
                BEGIN
                    SET @CurID = @BisectFrom;
                    WHILE @CurID <= @BisectTo AND @Stopped = 0
                    BEGIN
                        SET @RowInserted = 0;
                        BEGIN TRY
                            BEGIN TRANSACTION;
                            EXEC dbo.SP_MIG_INSTALLMENT_INCOME_INSERT_ONE
                                @CurID = @CurID, @RowInserted = @RowInserted OUTPUT;
                            COMMIT TRANSACTION;

                            IF @RowInserted = 1
                                SET @InsertedCount += 1;
                            ELSE
                                SET @SkippedCount += 1;
                        END TRY
                        BEGIN CATCH
                            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
                            SET @SingleErrMsg = ERROR_MESSAGE();
                            SET @ErrorCount += 1;

                            EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                                @RunID = @RunID, @TableRunID = @TableRunID,
                                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                                @BatchNo = @BatchNo,
                                @BridgeFrom = @CurID, @BridgeTo = @CurID,
                                @SourceID = @CurID, @IsSingleRow = 1,
                                @ErrorMsg = @SingleErrMsg;

                            IF @ErrorCount >= @MAX_ERROR
                                SET @Stopped = 1;
                        END CATCH

                        SET @CurID += 1;
                    END

                    SET @LastBridgeKey = @BisectTo;
                    BREAK;
                END

                SET @BisectMid = @BisectFrom + (@BisectSize / 2) - 1;
                SET @BisectRows = 0;

                BEGIN TRY
                    BEGIN TRANSACTION;
                    EXEC dbo.SP_MIG_INSTALLMENT_INCOME_INSERT_RANGE
                        @BatchFrom = @BisectFrom,
                        @BatchTo   = @BisectMid,
                        @RowCount  = @BisectRows OUTPUT;
                    COMMIT TRANSACTION;

                    SET @InsertedCount += @BisectRows;
                    SET @BisectFrom = @BisectMid + 1;
                END TRY
                BEGIN CATCH
                    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
                    SET @BisectTo = @BisectMid;
                END CATCH
            END

            IF @ErrorCount >= @MAX_ERROR
                SET @Stopped = 1;
        END CATCH
    END

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_INSTALLMENT_INCOME;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_INSTALLMENT_INCOME', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_INSTALLMENT_INCOME
    WHERE ABYS_ID IS NOT NULL;

    IF @Stopped = 1
    BEGIN
        SET @RunStatus = 'STOPPED'; SET @PhaseStatus = 'PAUSED';
    END
    ELSE IF @ErrorCount > 0
    BEGIN
        SET @RunStatus = 'COMPLETED_WITH_ERRORS'; SET @PhaseStatus = 'COMPLETED';
    END
    ELSE
    BEGIN
        SET @RunStatus = 'COMPLETED'; SET @PhaseStatus = 'COMPLETED';
    END

    EXEC energy.dbo.SP_MIG_LOG_FINISH_PHASE @TableRunID = @TableRunID, @Status = @PhaseStatus;

    SET @FinishErrorMsg = CASE
        WHEN @Stopped = 1 THEN N'Max hata limitine ulasildi. RESUME ile devam edin.'
        ELSE NULL
    END;

    EXEC energy.dbo.SP_MIG_LOG_FINISH_RUN
        @RunID = @RunID, @Status = @RunStatus,
        @TargetRowCount = @TargetCount,
        @ErrorMsg = @FinishErrorMsg;

    EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY
        @MigrationCode = @MigrationCode, @RunID = @RunID;
END
GO

-- EXEC energy.dbo.SP_MIGRATE_LS005_INSTALLMENT_INCOME
--      @HARD_RESET = 0, @RESUME = 1, @BATCH_SIZE = 20000, @DEBUG = 1;
GO
