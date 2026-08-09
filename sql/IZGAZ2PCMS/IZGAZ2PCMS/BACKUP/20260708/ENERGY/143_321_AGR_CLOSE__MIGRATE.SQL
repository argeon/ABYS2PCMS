/* ============================================================
   SCRIPT_ID : AGR_CLOSE_MIGRATE
   SCRIPT_NO : 321
   FILE      : 321_AGR_CLOSE__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS_AGR_CLOSE
-- Kaynak  : izgazMGR.dbo.LS_AGR_CLOSE
-- Hedef   : energy.dbo.LS_005_01_AGR_CLOSE
-- Kaynak ABYS_ID → hedef LREF (IDENTITY_INSERT)
-- AGRID   : kaynak ABYS_AGREEMENT_ID (Oracle/ABYS hali; wire YOK)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_CLOSE_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_AGR_CLOSE t
        WHERE t.LREF = @CurID
    )
        RETURN;

    SET IDENTITY_INSERT energy.dbo.LS_005_01_AGR_CLOSE ON;

    INSERT INTO energy.dbo.LS_005_01_AGR_CLOSE (
        LREF, ABYS_ID, ABYS_AGREEMENT_ID, ABYS_PAYABLE_BANK_ID,
        AGRID, FITNO, BNA_ID,
        CUSTTYPE, CUSTNAME, CUSTNO, CUSTREF,
        CURRENT_TLTOTAL, CURRENT_CURTOTAL, CURRENT_CURID, CURRENT_RATE,
        DESC_, STATID,
        ADDUSER, ADDDATE, UPDUSER, UPDDATE, CANCELLED,
        BNK_NAME, BNK_NO, BNK_ACCNO, BNK_IBAN, BNK_DESC,
        ALTERNATE_NAME, ALTERNATE_NO,
        PAYTYPE, TYPE_, BANKREF,
        INVOICESTOTAL, COMPLETEDDATE,
        LOGO_FIRMNR_RETURN, LOGO_FICHEREF_RETURN, LOGO_FICHENO_RETURN,
        LOGO_FIRMNR_REV, LOGO_FICHEREF_REV, LOGO_FICHENO_REV,
        DEMAND
    )
    SELECT
        s.ABYS_ID, s.ABYS_ID, s.ABYS_AGREEMENT_ID, s.ABYS_PAYABLE_BANK_ID,
        s.ABYS_AGREEMENT_ID, s.FITNO, s.BNA_ID,
        s.CUSTTYPE, s.CUSTNAME, s.CUSTNO, s.CUSTREF,
        s.CURRENT_TLTOTAL, s.CURRENT_CURTOTAL, s.CURRENT_CURID, s.CURRENT_RATE,
        s.DESC_, s.STATID,
        s.ADDUSER, s.ADDDATE, s.UPDUSER, s.UPDDATE, s.CANCELLED,
        s.BNK_NAME, s.BNK_NO, s.BNK_ACCNO, s.BNK_IBAN, s.BNK_DESC,
        s.ALTERNATE_NAME, s.ALTERNATE_NO,
        s.PAYTYPE, s.TYPE_, s.BANKREF,
        s.INVOICESTOTAL, s.COMPLETEDDATE,
        s.LOGO_FIRMNR_RETURN, s.LOGO_FICHEREF_RETURN, s.LOGO_FICHENO_RETURN,
        s.LOGO_FIRMNR_REV, s.LOGO_FICHEREF_REV, s.LOGO_FICHENO_REV,
        s.DEMAND
    FROM energy.dbo.VW_MIG_AGR_CLOSE_SOURCE s
    WHERE s.ABYS_ID = @CurID;

    SET @RowInserted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
    SET IDENTITY_INSERT energy.dbo.LS_005_01_AGR_CLOSE OFF;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_CLOSE_HARD_RESET
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @MaxLref INT;

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_AGR_CLOSE ABYS kayitlari ***', 0, 1) WITH NOWAIT;

    SET IDENTITY_INSERT energy.dbo.LS_005_01_AGR_CLOSE OFF;

    DELETE FROM energy.dbo.LS_005_01_AGR_CLOSE
    WHERE ABYS_ID IS NOT NULL;

    SET @Deleted = @@ROWCOUNT;

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_AGR_CLOSE;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_AGR_CLOSE', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        DECLARE @Msg VARCHAR(100) = '  silindi: ' + CAST(@Deleted AS VARCHAR(20))
            + ', CHECKIDENT=' + CAST(@MaxLref AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS_AGR_CLOSE
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
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_AGR_CLOSE',
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
        @MaxLref        INT;

    EXEC dbo.SP_MIG_AGR_CLOSE_VALIDATE_SOURCE @RaiseOnMissing = 1;
    EXEC dbo.SP_MIG_AGR_CLOSE_VALIDATE_TARGET @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_AGR_CLOSE_HARD_RESET @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM energy.dbo.VW_MIG_AGR_CLOSE_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_AGR_CLOSE_SOURCE;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_AGR_CLOSE',
        @TargetTable    = 'LS_005_01_AGR_CLOSE',
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
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20));
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
            FROM energy.dbo.VW_MIG_AGR_CLOSE_SOURCE s
            WHERE s.ABYS_ID > @LastBridgeKey
            ORDER BY s.ABYS_ID ASC
        ) t;

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
            SET IDENTITY_INSERT energy.dbo.LS_005_01_AGR_CLOSE ON;

            INSERT INTO energy.dbo.LS_005_01_AGR_CLOSE (
                LREF, ABYS_ID, ABYS_AGREEMENT_ID, ABYS_PAYABLE_BANK_ID,
                AGRID, FITNO, BNA_ID,
                CUSTTYPE, CUSTNAME, CUSTNO, CUSTREF,
                CURRENT_TLTOTAL, CURRENT_CURTOTAL, CURRENT_CURID, CURRENT_RATE,
                DESC_, STATID,
                ADDUSER, ADDDATE, UPDUSER, UPDDATE, CANCELLED,
                BNK_NAME, BNK_NO, BNK_ACCNO, BNK_IBAN, BNK_DESC,
                ALTERNATE_NAME, ALTERNATE_NO,
                PAYTYPE, TYPE_, BANKREF,
                INVOICESTOTAL, COMPLETEDDATE,
                LOGO_FIRMNR_RETURN, LOGO_FICHEREF_RETURN, LOGO_FICHENO_RETURN,
                LOGO_FIRMNR_REV, LOGO_FICHEREF_REV, LOGO_FICHENO_REV,
                DEMAND
            )
            SELECT
                s.ABYS_ID, s.ABYS_ID, s.ABYS_AGREEMENT_ID, s.ABYS_PAYABLE_BANK_ID,
                s.ABYS_AGREEMENT_ID, s.FITNO, s.BNA_ID,
                s.CUSTTYPE, s.CUSTNAME, s.CUSTNO, s.CUSTREF,
                s.CURRENT_TLTOTAL, s.CURRENT_CURTOTAL, s.CURRENT_CURID, s.CURRENT_RATE,
                s.DESC_, s.STATID,
                s.ADDUSER, s.ADDDATE, s.UPDUSER, s.UPDDATE, s.CANCELLED,
                s.BNK_NAME, s.BNK_NO, s.BNK_ACCNO, s.BNK_IBAN, s.BNK_DESC,
                s.ALTERNATE_NAME, s.ALTERNATE_NO,
                s.PAYTYPE, s.TYPE_, s.BANKREF,
                s.INVOICESTOTAL, s.COMPLETEDDATE,
                s.LOGO_FIRMNR_RETURN, s.LOGO_FICHEREF_RETURN, s.LOGO_FICHENO_RETURN,
                s.LOGO_FIRMNR_REV, s.LOGO_FICHEREF_REV, s.LOGO_FICHENO_REV,
                s.DEMAND
            FROM energy.dbo.VW_MIG_AGR_CLOSE_SOURCE s
            WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
              AND NOT EXISTS (
                  SELECT 1
                  FROM energy.dbo.LS_005_01_AGR_CLOSE t
                  WHERE t.LREF = s.ABYS_ID
              );

            SET @RowCount = @@ROWCOUNT;
            SET IDENTITY_INSERT energy.dbo.LS_005_01_AGR_CLOSE OFF;
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
            SET IDENTITY_INSERT energy.dbo.LS_005_01_AGR_CLOSE OFF;
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
                        EXEC dbo.SP_MIG_AGR_CLOSE_INSERT_ONE
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
                    SET IDENTITY_INSERT energy.dbo.LS_005_01_AGR_CLOSE ON;

                    INSERT INTO energy.dbo.LS_005_01_AGR_CLOSE (
                        LREF, ABYS_ID, ABYS_AGREEMENT_ID, ABYS_PAYABLE_BANK_ID,
                        AGRID, FITNO, BNA_ID,
                        CUSTTYPE, CUSTNAME, CUSTNO, CUSTREF,
                        CURRENT_TLTOTAL, CURRENT_CURTOTAL, CURRENT_CURID, CURRENT_RATE,
                        DESC_, STATID,
                        ADDUSER, ADDDATE, UPDUSER, UPDDATE, CANCELLED,
                        BNK_NAME, BNK_NO, BNK_ACCNO, BNK_IBAN, BNK_DESC,
                        ALTERNATE_NAME, ALTERNATE_NO,
                        PAYTYPE, TYPE_, BANKREF,
                        INVOICESTOTAL, COMPLETEDDATE,
                        LOGO_FIRMNR_RETURN, LOGO_FICHEREF_RETURN, LOGO_FICHENO_RETURN,
                        LOGO_FIRMNR_REV, LOGO_FICHEREF_REV, LOGO_FICHENO_REV,
                        DEMAND
                    )
                    SELECT
                        s.ABYS_ID, s.ABYS_ID, s.ABYS_AGREEMENT_ID, s.ABYS_PAYABLE_BANK_ID,
                        s.ABYS_AGREEMENT_ID, s.FITNO, s.BNA_ID,
                        s.CUSTTYPE, s.CUSTNAME, s.CUSTNO, s.CUSTREF,
                        s.CURRENT_TLTOTAL, s.CURRENT_CURTOTAL, s.CURRENT_CURID, s.CURRENT_RATE,
                        s.DESC_, s.STATID,
                        s.ADDUSER, s.ADDDATE, s.UPDUSER, s.UPDDATE, s.CANCELLED,
                        s.BNK_NAME, s.BNK_NO, s.BNK_ACCNO, s.BNK_IBAN, s.BNK_DESC,
                        s.ALTERNATE_NAME, s.ALTERNATE_NO,
                        s.PAYTYPE, s.TYPE_, s.BANKREF,
                        s.INVOICESTOTAL, s.COMPLETEDDATE,
                        s.LOGO_FIRMNR_RETURN, s.LOGO_FICHEREF_RETURN, s.LOGO_FICHENO_RETURN,
                        s.LOGO_FIRMNR_REV, s.LOGO_FICHEREF_REV, s.LOGO_FICHENO_REV,
                        s.DEMAND
                    FROM energy.dbo.VW_MIG_AGR_CLOSE_SOURCE s
                    WHERE s.ABYS_ID BETWEEN @BisectFrom AND @BisectMid
                      AND NOT EXISTS (
                          SELECT 1
                          FROM energy.dbo.LS_005_01_AGR_CLOSE t
                          WHERE t.LREF = s.ABYS_ID
                      );

                    SET @BisectRows = @@ROWCOUNT;
                    SET @BisectLogFrom = @BisectFrom;
                    SET IDENTITY_INSERT energy.dbo.LS_005_01_AGR_CLOSE OFF;
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
                    SET IDENTITY_INSERT energy.dbo.LS_005_01_AGR_CLOSE OFF;
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
    FROM energy.dbo.LS_005_01_AGR_CLOSE;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_AGR_CLOSE', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_AGR_CLOSE
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

 --EXEC energy.dbo.SP_MIGRATE_LS_AGR_CLOSE @HARD_RESET = 1, @DEBUG = 1;
 -- AGRID = ABYS_AGREEMENT_ID (wire yok)

