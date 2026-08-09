/* ============================================================
   SCRIPT_ID : SPEFEE_MIGRATE
   SCRIPT_NO : 585
   FILE      : 585_SPEFEE__migrate.sql
   VERSION   : 2
   ============================================================ */
-- v2: Enterprise 128-core: TABLOCK + OPTION(RECOMPILE,MAXDOP) + BATCH 500K
-- Not   : Kaynak 2x duplicate → VW_MIG_SPEFEE_SOURCE ABYS_ID dedupe (584 v2)
-- ============================================================
-- SP_MIGRATE_LS_SPEFEE
-- Kaynak  : izgazMGR.dbo.LS_SPEFEE (VW_MIG_SPEFEE_SOURCE, ABYS_ID unique)
-- Hedef   : energy.dbo.LS_005_01_SPEFEE
-- Kaynak ABYS_ID → hedef LREF (IDENTITY_INSERT)
-- Bulk    : IDENTITY_INSERT + TABLOCK + ABYS_ID aralik batch (~500K)
-- MAXDOP  : varsayilan 64 (ust sinir 128, Enterprise 128-core)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_SPEFEE_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_SPEFEE t
        WHERE t.LREF = @CurID
    )
        RETURN;

    SET IDENTITY_INSERT energy.dbo.LS_005_01_SPEFEE ON;

    INSERT INTO energy.dbo.LS_005_01_SPEFEE (
        LREF,
        STYPE_OLD, LINEEXP, INVOICEREF, CUSTNAME,
        CLIENTREF, OWNERREF, CLIENTTYPE,
        TLTOTAL, TAX, GRANDTOTAL,
        ADDDATE, ADDUSER, CANCELLED, UPDDATE, UPDUSER,
        READ_TRANSFERREF, READ_NO, PRINTED,
        IU_TYPE, IND_DIFF, STYPE, READING_ID, STATUS,
        INSTALLMENT_NO, INSTALLMENT_NR,
        ABYS_ID, ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID, ABYS_INCOME_ID,
        ABYS_PERIOD, ABYS_ACTION_DATE, ABYS_WORK_ORDER_ID, ABYS_QUANTITY,
        ABYS_ACCRUE_GROUP_ID, ABYS_CASH_ID, ABYS_RECEIPT_SERIAL, ABYS_RECEIPT_NUMBER,
        ABYS_ANALYSIS_ACCOUNT_ID, ABYS_VERSION, ABYS_TRANSACTION_CODE,
        ABYS_CREATED_USER_ID, ABYS_UPDATED_USER_ID, ABYS_READING_ID
    )
    SELECT
        s.ABYS_ID,
        s.STYPE_OLD, s.LINEEXP, s.INVOICEREF, s.CUSTNAME,
        s.CLIENTREF, s.OWNERREF, s.CLIENTTYPE,
        s.TLTOTAL, s.TAX, s.GRANDTOTAL,
        s.ADDDATE, s.ADDUSER, s.CANCELLED, s.UPDDATE, s.UPDUSER,
        s.READ_TRANSFERREF, s.READ_NO, s.PRINTED,
        s.IU_TYPE, s.IND_DIFF, s.STYPE, s.READING_ID, s.STATUS,
        s.INSTALLMENT_NO, s.INSTALLMENT_NR,
        s.ABYS_ID, s.ABYS_AGREEMENT_ID, s.ABYS_ACCOUNT_ID, s.ABYS_INCOME_ID,
        s.ABYS_PERIOD, s.ABYS_ACTION_DATE, s.ABYS_WORK_ORDER_ID, s.ABYS_QUANTITY,
        s.ABYS_ACCRUE_GROUP_ID, s.ABYS_CASH_ID, s.ABYS_RECEIPT_SERIAL, s.ABYS_RECEIPT_NUMBER,
        s.ABYS_ANALYSIS_ACCOUNT_ID, s.ABYS_VERSION, s.ABYS_TRANSACTION_CODE,
        s.ABYS_CREATED_USER_ID, s.ABYS_UPDATED_USER_ID, s.ABYS_READING_ID
    FROM energy.dbo.VW_MIG_SPEFEE_SOURCE s
    WHERE s.ABYS_ID = @CurID
    OPTION (RECOMPILE, MAXDOP 1);

    SET @RowInserted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
    SET IDENTITY_INSERT energy.dbo.LS_005_01_SPEFEE OFF;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_SPEFEE_HARD_RESET
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @MaxLref INT;

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_SPEFEE ABYS kayitlari ***', 0, 1) WITH NOWAIT;

    SET IDENTITY_INSERT energy.dbo.LS_005_01_SPEFEE OFF;

    DELETE FROM energy.dbo.LS_005_01_SPEFEE
    WHERE ABYS_ID IS NOT NULL;

    SET @Deleted = @@ROWCOUNT;

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_SPEFEE;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_SPEFEE', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        DECLARE @Msg VARCHAR(100) = '  silindi: ' + CAST(@Deleted AS VARCHAR(20))
            + ', CHECKIDENT=' + CAST(@MaxLref AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS_SPEFEE
    @BATCH_SIZE  INT = 500000,
    @RESUME      BIT = 1,
    @HARD_RESET  BIT = 0,
    @MAX_ERROR   INT = 500,
    @BISECT_MIN  INT = 1,
    @MAXDOP      INT = 64,
    @DEBUG       BIT = 0
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    /* Enterprise 128-core: varsayilan MAXDOP 64, ust sinir 128 */
    IF @MAXDOP IS NULL OR @MAXDOP < 1 SET @MAXDOP = 1;
    IF @MAXDOP > 128 SET @MAXDOP = 128;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_SPEFEE',
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
        @MaxLref        INT,
        @sql            NVARCHAR(MAX);

    EXEC dbo.SP_MIG_SPEFEE_VALIDATE_SOURCE @RaiseOnMissing = 1;
    EXEC dbo.SP_MIG_SPEFEE_VALIDATE_TARGET @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_SPEFEE_HARD_RESET @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*)
    FROM energy.dbo.VW_MIG_SPEFEE_SOURCE
    OPTION (RECOMPILE, MAXDOP 8);

    SELECT @MaxBridgeKey = MAX(ABYS_ID)
    FROM energy.dbo.VW_MIG_SPEFEE_SOURCE
    OPTION (RECOMPILE, MAXDOP 8);

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_SPEFEE',
        @TargetTable    = 'LS_005_01_SPEFEE',
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
            + ' | Kaynak=' + CAST(@SourceCount AS VARCHAR(20))
            + ' | ABYS_ID=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20))
            + ' | BATCH=' + CAST(@BATCH_SIZE AS VARCHAR(10))
            + ' | MAXDOP=' + CAST(@MAXDOP AS VARCHAR(3));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @BatchFrom  = @LastBridgeKey + 1;
        SET @RowCount   = 0;

        SELECT @BatchTo = MAX(ABYS_ID)
        FROM (
            SELECT TOP (@BATCH_SIZE) s.ABYS_ID
            FROM energy.dbo.VW_MIG_SPEFEE_SOURCE s
            WHERE s.ABYS_ID > @LastBridgeKey
            ORDER BY s.ABYS_ID ASC
        ) t
        OPTION (RECOMPILE, MAXDOP 8);

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
            SET IDENTITY_INSERT energy.dbo.LS_005_01_SPEFEE ON;

            SET @sql = N'
            INSERT INTO energy.dbo.LS_005_01_SPEFEE WITH (TABLOCK) (
                LREF,
                STYPE_OLD, LINEEXP, INVOICEREF, CUSTNAME,
                CLIENTREF, OWNERREF, CLIENTTYPE,
                TLTOTAL, TAX, GRANDTOTAL,
                ADDDATE, ADDUSER, CANCELLED, UPDDATE, UPDUSER,
                READ_TRANSFERREF, READ_NO, PRINTED,
                IU_TYPE, IND_DIFF, STYPE, READING_ID, STATUS,
                INSTALLMENT_NO, INSTALLMENT_NR,
                ABYS_ID, ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID, ABYS_INCOME_ID,
                ABYS_PERIOD, ABYS_ACTION_DATE, ABYS_WORK_ORDER_ID, ABYS_QUANTITY,
                ABYS_ACCRUE_GROUP_ID, ABYS_CASH_ID, ABYS_RECEIPT_SERIAL, ABYS_RECEIPT_NUMBER,
                ABYS_ANALYSIS_ACCOUNT_ID, ABYS_VERSION, ABYS_TRANSACTION_CODE,
                ABYS_CREATED_USER_ID, ABYS_UPDATED_USER_ID, ABYS_READING_ID
            )
            SELECT
                s.ABYS_ID,
                s.STYPE_OLD, s.LINEEXP, s.INVOICEREF, s.CUSTNAME,
                s.CLIENTREF, s.OWNERREF, s.CLIENTTYPE,
                s.TLTOTAL, s.TAX, s.GRANDTOTAL,
                s.ADDDATE, s.ADDUSER, s.CANCELLED, s.UPDDATE, s.UPDUSER,
                s.READ_TRANSFERREF, s.READ_NO, s.PRINTED,
                s.IU_TYPE, s.IND_DIFF, s.STYPE, s.READING_ID, s.STATUS,
                s.INSTALLMENT_NO, s.INSTALLMENT_NR,
                s.ABYS_ID, s.ABYS_AGREEMENT_ID, s.ABYS_ACCOUNT_ID, s.ABYS_INCOME_ID,
                s.ABYS_PERIOD, s.ABYS_ACTION_DATE, s.ABYS_WORK_ORDER_ID, s.ABYS_QUANTITY,
                s.ABYS_ACCRUE_GROUP_ID, s.ABYS_CASH_ID, s.ABYS_RECEIPT_SERIAL, s.ABYS_RECEIPT_NUMBER,
                s.ABYS_ANALYSIS_ACCOUNT_ID, s.ABYS_VERSION, s.ABYS_TRANSACTION_CODE,
                s.ABYS_CREATED_USER_ID, s.ABYS_UPDATED_USER_ID, s.ABYS_READING_ID
            FROM energy.dbo.VW_MIG_SPEFEE_SOURCE s
            WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
              AND NOT EXISTS (
                  SELECT 1
                  FROM energy.dbo.LS_005_01_SPEFEE t WITH (NOLOCK)
                  WHERE t.LREF = s.ABYS_ID
              )
            OPTION (RECOMPILE, MAXDOP ' + CAST(@MAXDOP AS NVARCHAR(3)) + N', USE HINT(''ENABLE_PARALLEL_PLAN_PREFERENCE''));';

            EXEC sys.sp_executesql
                @sql,
                N'@BatchFrom BIGINT, @BatchTo BIGINT',
                @BatchFrom = @BatchFrom,
                @BatchTo   = @BatchTo;

            SET @RowCount = @@ROWCOUNT;
            SET IDENTITY_INSERT energy.dbo.LS_005_01_SPEFEE OFF;
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
            SET IDENTITY_INSERT energy.dbo.LS_005_01_SPEFEE OFF;
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
                        EXEC dbo.SP_MIG_SPEFEE_INSERT_ONE
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
                            N'ABYS_ID=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

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
                    SET IDENTITY_INSERT energy.dbo.LS_005_01_SPEFEE ON;

                    SET @sql = N'
                    INSERT INTO energy.dbo.LS_005_01_SPEFEE WITH (TABLOCK) (
                        LREF,
                        STYPE_OLD, LINEEXP, INVOICEREF, CUSTNAME,
                        CLIENTREF, OWNERREF, CLIENTTYPE,
                        TLTOTAL, TAX, GRANDTOTAL,
                        ADDDATE, ADDUSER, CANCELLED, UPDDATE, UPDUSER,
                        READ_TRANSFERREF, READ_NO, PRINTED,
                        IU_TYPE, IND_DIFF, STYPE, READING_ID, STATUS,
                        INSTALLMENT_NO, INSTALLMENT_NR,
                        ABYS_ID, ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID, ABYS_INCOME_ID,
                        ABYS_PERIOD, ABYS_ACTION_DATE, ABYS_WORK_ORDER_ID, ABYS_QUANTITY,
                        ABYS_ACCRUE_GROUP_ID, ABYS_CASH_ID, ABYS_RECEIPT_SERIAL, ABYS_RECEIPT_NUMBER,
                        ABYS_ANALYSIS_ACCOUNT_ID, ABYS_VERSION, ABYS_TRANSACTION_CODE,
                        ABYS_CREATED_USER_ID, ABYS_UPDATED_USER_ID, ABYS_READING_ID
                    )
                    SELECT
                        s.ABYS_ID,
                        s.STYPE_OLD, s.LINEEXP, s.INVOICEREF, s.CUSTNAME,
                        s.CLIENTREF, s.OWNERREF, s.CLIENTTYPE,
                        s.TLTOTAL, s.TAX, s.GRANDTOTAL,
                        s.ADDDATE, s.ADDUSER, s.CANCELLED, s.UPDDATE, s.UPDUSER,
                        s.READ_TRANSFERREF, s.READ_NO, s.PRINTED,
                        s.IU_TYPE, s.IND_DIFF, s.STYPE, s.READING_ID, s.STATUS,
                        s.INSTALLMENT_NO, s.INSTALLMENT_NR,
                        s.ABYS_ID, s.ABYS_AGREEMENT_ID, s.ABYS_ACCOUNT_ID, s.ABYS_INCOME_ID,
                        s.ABYS_PERIOD, s.ABYS_ACTION_DATE, s.ABYS_WORK_ORDER_ID, s.ABYS_QUANTITY,
                        s.ABYS_ACCRUE_GROUP_ID, s.ABYS_CASH_ID, s.ABYS_RECEIPT_SERIAL, s.ABYS_RECEIPT_NUMBER,
                        s.ABYS_ANALYSIS_ACCOUNT_ID, s.ABYS_VERSION, s.ABYS_TRANSACTION_CODE,
                        s.ABYS_CREATED_USER_ID, s.ABYS_UPDATED_USER_ID, s.ABYS_READING_ID
                    FROM energy.dbo.VW_MIG_SPEFEE_SOURCE s
                    WHERE s.ABYS_ID BETWEEN @BisectFrom AND @BisectMid
                      AND NOT EXISTS (
                          SELECT 1
                          FROM energy.dbo.LS_005_01_SPEFEE t WITH (NOLOCK)
                          WHERE t.LREF = s.ABYS_ID
                      )
                    OPTION (RECOMPILE, MAXDOP ' + CAST(@MAXDOP AS NVARCHAR(3)) + N', USE HINT(''ENABLE_PARALLEL_PLAN_PREFERENCE''));';

                    EXEC sys.sp_executesql
                        @sql,
                        N'@BisectFrom BIGINT, @BisectMid BIGINT',
                        @BisectFrom = @BisectFrom,
                        @BisectMid  = @BisectMid;

                    SET @BisectRows = @@ROWCOUNT;
                    SET @BisectLogFrom = @BisectFrom;
                    SET IDENTITY_INSERT energy.dbo.LS_005_01_SPEFEE OFF;
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
                    SET IDENTITY_INSERT energy.dbo.LS_005_01_SPEFEE OFF;
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

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_SPEFEE;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_SPEFEE', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_SPEFEE
    WHERE ABYS_ID IS NOT NULL;

    IF @Stopped = 1
    BEGIN
        SET @RunStatus   = 'STOPPED';
        SET @PhaseStatus = 'PAUSED';
    END
    ELSE IF @ErrorCount > 0
    BEGIN
        SET @RunStatus   = 'COMPLETED_WITH_ERRORS';
        SET @PhaseStatus = 'COMPLETED';
    END
    ELSE
    BEGIN
        SET @RunStatus   = 'COMPLETED';
        SET @PhaseStatus = 'COMPLETED';
    END

    EXEC energy.dbo.SP_MIG_LOG_FINISH_PHASE
        @TableRunID = @TableRunID, @Status = @PhaseStatus;

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

-- EXEC energy.dbo.SP_MIGRATE_LS_SPEFEE
--     @RESUME = 1, @BATCH_SIZE = 500000, @MAXDOP = 64, @DEBUG = 1;
-- 128-core Enterprise: @BATCH_SIZE 250000..1000000, @MAXDOP 32..128
