/* ============================================================
   SCRIPT_ID : AGR_GUARANTY_MIGRATE
   SCRIPT_NO : 311
   FILE      : 311_AGR_GUARANTY__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_DEPOSIT_GUARANTY
-- Kaynak  : izgazMGR.dbo.LS_AGR_GUARANTY (MIG_ROW_ID köprü)
-- Hedef   : energy.dbo.LS_005_01_AGR_GUARANTY
-- ============================================================
USE energy;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_DEPOSIT_GUAR_INSERT_ONE
    @MigRowID    BIGINT,
    @RowInserted BIT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_AGR_GUARANTY t
        WHERE t.ABYS_MIG_ROW_ID = @MigRowID
    )
        RETURN;

    INSERT INTO energy.dbo.LS_005_01_AGR_GUARANTY (
        ABYS_MIG_ROW_ID, ABYS_LREF, ABYS_AGRID,
        AGRID, GTYPE, RFNO, SDATE, EDATE, WD, TOTAL, EXCNR, MUSTTL,
        ADDDATE, ADDUSER, UPDDATE, UPDUSER,
        LOGOREF, BANKREF, BANKACCREF,
        CUSTBNK, CUSTBNKACC, CUSTBNKNO,
        LOGO_FIRMNR, LOGO_FICHEREF, LOGO_FICHENO,
        REFUND, CONVERTED_CASH
    )
    SELECT
        s.MIG_ROW_ID,
        s.SRC_LREF,
        s.AGRID,
        s.AGRID, s.GTYPE, LEFT(s.RFNO, 50),
        s.SDATE, s.EDATE, s.WD, s.TOTAL, s.EXCNR, s.MUSTTL,
        s.ADDDATE, s.ADDUSER, s.UPDDATE, s.UPDUSER,
        s.LOGOREF, s.BANKREF, s.BANKACCREF,
        LEFT(s.CUSTBNK, 50), LEFT(s.CUSTBNKACC, 50), LEFT(s.CUSTBNKNO, 50),
        s.LOGO_FIRMNR, s.LOGO_FICHEREF, LEFT(s.LOGO_FICHENO, 50),
        s.REFUND, s.CONVERTED_CASH
    FROM energy.dbo.VW_MIG_DEPOSIT_GUARANTY_SOURCE s
    WHERE s.MIG_ROW_ID = @MigRowID;

    SET @RowInserted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_DEPOSIT_GUARANTY
    @BATCH_SIZE  INT = 5000,
    @RESUME      BIT = 1,
    @HARD_RESET  BIT = 0,
    @MAX_ERROR   INT = 500,
    @BISECT_MIN  INT = 1,
    @DEBUG       BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_AGR_GUARANTY',
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
        @ValidationResult INT;

    EXEC @ValidationResult =
        dbo.SP_MIG_DEPOSIT_GUAR_VALIDATE_SOURCE @RaiseOnMissing = 1;

    IF @ValidationResult <> 0
        THROW 50000, 'LS_AGR_GUARANTY kaynak dogrulamasi basarisiz; migrasyon ve HARD RESET durduruldu.', 1;

    EXEC dbo.SP_MIG_DEPOSIT_GUAR_PREP_SOURCE;

    IF @HARD_RESET = 1
    BEGIN
        SET @ExecMode = 'HARD_RESET';
        IF @DEBUG = 1
            RAISERROR('*** HARD RESET: LS_005_01_AGR_GUARANTY ABYS kayitlari ***', 0, 1) WITH NOWAIT;

        DELETE FROM energy.dbo.LS_005_01_AGR_GUARANTY
        WHERE ABYS_MIG_ROW_ID IS NOT NULL;

        SET @RESUME = 0;
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM energy.dbo.VW_MIG_DEPOSIT_GUARANTY_SOURCE;
    SELECT @MaxBridgeKey = MAX(MIG_ROW_ID) FROM energy.dbo.VW_MIG_DEPOSIT_GUARANTY_SOURCE;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_AGR_GUARANTY',
        @TargetTable    = 'LS_005_01_AGR_GUARANTY',
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
            + ' | MIG_ROW_ID=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @BatchFrom  = @LastBridgeKey + 1;
        SET @RowCount   = 0;

        SELECT @BatchTo = MAX(MIG_ROW_ID)
        FROM (
            SELECT TOP (@BATCH_SIZE) s.MIG_ROW_ID
            FROM energy.dbo.VW_MIG_DEPOSIT_GUARANTY_SOURCE s
            WHERE s.MIG_ROW_ID > @LastBridgeKey
            ORDER BY s.MIG_ROW_ID ASC
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

            INSERT INTO energy.dbo.LS_005_01_AGR_GUARANTY (
                ABYS_MIG_ROW_ID, ABYS_LREF, ABYS_AGRID,
                AGRID, GTYPE, RFNO, SDATE, EDATE, WD, TOTAL, EXCNR, MUSTTL,
                ADDDATE, ADDUSER, UPDDATE, UPDUSER,
                LOGOREF, BANKREF, BANKACCREF,
                CUSTBNK, CUSTBNKACC, CUSTBNKNO,
                LOGO_FIRMNR, LOGO_FICHEREF, LOGO_FICHENO,
                REFUND, CONVERTED_CASH
            )
            SELECT
                s.MIG_ROW_ID,
                s.SRC_LREF,
                s.AGRID,
                s.AGRID, s.GTYPE, LEFT(s.RFNO, 50),
                s.SDATE, s.EDATE, s.WD, s.TOTAL, s.EXCNR, s.MUSTTL,
                s.ADDDATE, s.ADDUSER, s.UPDDATE, s.UPDUSER,
                s.LOGOREF, s.BANKREF, s.BANKACCREF,
                LEFT(s.CUSTBNK, 50), LEFT(s.CUSTBNKACC, 50), LEFT(s.CUSTBNKNO, 50),
                s.LOGO_FIRMNR, s.LOGO_FICHEREF, LEFT(s.LOGO_FICHENO, 50),
                s.REFUND, s.CONVERTED_CASH
            FROM energy.dbo.VW_MIG_DEPOSIT_GUARANTY_SOURCE s
            WHERE s.MIG_ROW_ID BETWEEN @BatchFrom AND @BatchTo
              AND NOT EXISTS (
                  SELECT 1
                  FROM energy.dbo.LS_005_01_AGR_GUARANTY t
                  WHERE t.ABYS_MIG_ROW_ID = s.MIG_ROW_ID
              );

            SET @RowCount = @@ROWCOUNT;
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
                        EXEC dbo.SP_MIG_DEPOSIT_GUAR_INSERT_ONE
                            @MigRowID = @BisectFrom, @RowInserted = @RowInserted OUTPUT;

                        IF @RowInserted = 1
                            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                                @RunID = @RunID, @TableRunID = @TableRunID,
                                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                                @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom,
                                @BridgeTo = @BisectFrom, @RowCount = 1;
                    END TRY
                    BEGIN CATCH
                        SET @ErrMsg = ERROR_MESSAGE();
                        SET @SingleErrMsg = LEFT(
                            N'MIG_ROW_ID=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

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

                    INSERT INTO energy.dbo.LS_005_01_AGR_GUARANTY (
                        ABYS_MIG_ROW_ID, ABYS_LREF, ABYS_AGRID,
                        AGRID, GTYPE, RFNO, SDATE, EDATE, WD, TOTAL, EXCNR, MUSTTL,
                        ADDDATE, ADDUSER, UPDDATE, UPDUSER,
                        LOGOREF, BANKREF, BANKACCREF,
                        CUSTBNK, CUSTBNKACC, CUSTBNKNO,
                        LOGO_FIRMNR, LOGO_FICHEREF, LOGO_FICHENO,
                        REFUND, CONVERTED_CASH
                    )
                    SELECT
                        s.MIG_ROW_ID, s.SRC_LREF, s.AGRID,
                        s.AGRID, s.GTYPE, LEFT(s.RFNO, 50),
                        s.SDATE, s.EDATE, s.WD, s.TOTAL, s.EXCNR, s.MUSTTL,
                        s.ADDDATE, s.ADDUSER, s.UPDDATE, s.UPDUSER,
                        s.LOGOREF, s.BANKREF, s.BANKACCREF,
                        LEFT(s.CUSTBNK, 50), LEFT(s.CUSTBNKACC, 50), LEFT(s.CUSTBNKNO, 50),
                        s.LOGO_FIRMNR, s.LOGO_FICHEREF, LEFT(s.LOGO_FICHENO, 50),
                        s.REFUND, s.CONVERTED_CASH
                    FROM energy.dbo.VW_MIG_DEPOSIT_GUARANTY_SOURCE s
                    WHERE s.MIG_ROW_ID BETWEEN @BisectFrom AND @BisectMid
                      AND NOT EXISTS (
                          SELECT 1 FROM energy.dbo.LS_005_01_AGR_GUARANTY t
                          WHERE t.ABYS_MIG_ROW_ID = s.MIG_ROW_ID
                      );

                    SET @BisectRows = @@ROWCOUNT;
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

        IF @DEBUG = 1
        BEGIN
            SET @Msg = '  → OK=' + CAST(@InsertedCount AS VARCHAR(20))
                + ' ERR=' + CAST(@ErrorCount AS VARCHAR(20))
                + ' LastMigRow=' + CAST(@LastBridgeKey AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_AGR_GUARANTY
    WHERE ABYS_MIG_ROW_ID IS NOT NULL;

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
 
-- ============================================================
 --EXEC energy.dbo.SP_MIGRATE_LS005_DEPOSIT_GUARANTY
 --     @HARD_RESET = 1, @BATCH_SIZE = 5000, @DEBUG = 1;
-- ============================================================



 
