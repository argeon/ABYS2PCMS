/* ============================================================
   SCRIPT_ID : II_APPOINTMENT_DEVICE_MIGRATE
   SCRIPT_NO : 535
   FILE      : 535_II_APPOINTMENT_DEVICE__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_II_APPOINTMENT_DEVICE
-- Kaynak  : izgazMGR.dbo.II_APPOINTMENT_DEVICE (VW_MIG_II_APPOINTMENT_DEVICE_SOURCE)
-- Hedef   : energy.dbo.LS_005_01_APPOINTMENT_DEVICE
-- LREF    : IDENTITY_INSERT = kaynak ID
-- ABYS_ID : kaynak ID
--
-- Pass 1 dump: DEVICE_TYPE/FLUE/CAPACITY/REGULATOR/BRAND JOIN yok.
-- User: FN_MIG_MAP_USER_USERID (+10000).
-- APPOINTMENT_REF ← APPOINTMENT_ID (parent LREF)
-- PROJECT_DEVICE_REF ← PROJECT_INSTALLATION_DEVICE_ID
-- BRAND_CODE ← MARK_CODE
-- Parent: 533 II_APPOINTMENT migrate sonrasi calistir.
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_DEVICE_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @RowCount  INT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    BEGIN TRY
        SET IDENTITY_INSERT dbo.LS_005_01_APPOINTMENT_DEVICE ON;

        INSERT INTO energy.dbo.LS_005_01_APPOINTMENT_DEVICE (
            LREF, UNIT_LREF,
            DEVICE_TYPE_CODE, DEVICE_TYPE,
            FLUE_TYPE_CODE, FLUE_TYPE,
            IS_CONDENSED, DEVICE_CAPACITY, DEVICE_FLOW_RATE,
            EFFICIENCY, WORKING_PRESSURE, DEVICE_LOCATION,
            DEVICE_STATUS, STARTUP_DATE, SHOULD_UPDATED,
            APPOINTMENT_REF,
            ADDUSER, ADDDATE, UPDUSER, UPDDATE,
            CREATED_USER, CREATED_DATE, UPDATED_USER, UPDATED_DATE,
            PROJECTLINE_ID, BRAND_CODE, BRAND, PROJECT_DEVICE_REF,
            REGULATOR_BRAND, REGULATOR_TYPE, REGULATOR_SERIAL, REGULATOR_YEAR,
            ABYS_ID, ABYS_APPOINTMENT_ID, ABYS_PROJECT_INSTALLATION_DEVICE_ID,
            ABYS_DEVICE_MARK_ID, ABYS_MARK_CODE, ABYS_DEVICE_MODEL_ID,
            ABYS_DEVICE_STATUS, ABYS_STARTUP_DATE, ABYS_SHOULD_UPDATED,
            ABYS_CREATED_USER_ID, ABYS_CREATED_TIMESTAMP,
            ABYS_UPDATED_USER_ID, ABYS_UPDATED_TIMESTAMP,
            ABYS_VERSION, ABYS_CIHAZ_ID_
        )
        SELECT
            s.LREF, s.UNIT_LREF,
            s.DEVICE_TYPE_CODE, s.DEVICE_TYPE,
            s.FLUE_TYPE_CODE, s.FLUE_TYPE,
            s.IS_CONDENSED, s.DEVICE_CAPACITY, s.DEVICE_FLOW_RATE,
            s.EFFICIENCY, s.WORKING_PRESSURE, s.DEVICE_LOCATION,
            s.DEVICE_STATUS, s.STARTUP_DATE, s.SHOULD_UPDATED,
            s.APPOINTMENT_REF,
            s.ADDUSER, s.ADDDATE, s.UPDUSER, s.UPDDATE,
            s.CREATED_USER, s.CREATED_DATE, s.UPDATED_USER, s.UPDATED_DATE,
            s.PROJECTLINE_ID, s.BRAND_CODE, s.BRAND, s.PROJECT_DEVICE_REF,
            s.REGULATOR_BRAND, s.REGULATOR_TYPE, s.REGULATOR_SERIAL, s.REGULATOR_YEAR,
            s.ABYS_ID, s.ABYS_APPOINTMENT_ID, s.ABYS_PROJECT_INSTALLATION_DEVICE_ID,
            s.ABYS_DEVICE_MARK_ID, s.ABYS_MARK_CODE, s.ABYS_DEVICE_MODEL_ID,
            s.ABYS_DEVICE_STATUS, s.ABYS_STARTUP_DATE, s.ABYS_SHOULD_UPDATED,
            s.ABYS_CREATED_USER_ID, s.ABYS_CREATED_TIMESTAMP,
            s.ABYS_UPDATED_USER_ID, s.ABYS_UPDATED_TIMESTAMP,
            s.ABYS_VERSION, s.ABYS_CIHAZ_ID_
        FROM energy.dbo.VW_MIG_II_APPOINTMENT_DEVICE_SOURCE s
        WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
          AND NOT EXISTS (
              SELECT 1
              FROM energy.dbo.LS_005_01_APPOINTMENT_DEVICE t
              WHERE t.ABYS_ID = s.ABYS_ID
                 OR t.LREF = s.LREF
          );

        SET @RowCount = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_APPOINTMENT_DEVICE OFF; END TRY BEGIN CATCH END CATCH;
        THROW;
    END CATCH

    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_APPOINTMENT_DEVICE OFF; END TRY BEGIN CATCH END CATCH;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_DEVICE_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_APPOINTMENT_DEVICE t
        WHERE t.LREF = @CurID OR t.ABYS_ID = @CurID
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_II_APPOINTMENT_DEVICE_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_DEVICE_HARD_RESET
    @DELETE_BATCH INT = 10000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @MaxLref BIGINT;
    DECLARE @TotalStr VARCHAR(20), @MaxLrefStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_APPOINTMENT_DEVICE ABYS kayitlari (batch=%d) ***', 0, 1, @DELETE_BATCH) WITH NOWAIT;

    SET IDENTITY_INSERT dbo.LS_005_01_APPOINTMENT_DEVICE OFF;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_005_01_APPOINTMENT_DEVICE
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
    FROM energy.dbo.LS_005_01_APPOINTMENT_DEVICE;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_APPOINTMENT_DEVICE', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        SET @MaxLrefStr = CAST(@MaxLref AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s, CHECKIDENT=%s', 0, 1, @TotalStr, @MaxLrefStr) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_II_APPOINTMENT_DEVICE
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
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_APPOINTMENT_DEVICE',
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
        @MaxLref        BIGINT;

    EXEC dbo.SP_MIG_II_APPOINTMENT_DEVICE_VALIDATE_ALL @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_II_APPOINTMENT_DEVICE_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount = COUNT_BIG(*) FROM energy.dbo.VW_MIG_II_APPOINTMENT_DEVICE_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_II_APPOINTMENT_DEVICE_SOURCE;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'II_APPOINTMENT_DEVICE',
        @TargetTable    = 'LS_005_01_APPOINTMENT_DEVICE',
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
            + ' | Kaynak=' + CAST(ISNULL(@SourceCount, 0) AS VARCHAR(20))
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
            FROM energy.dbo.VW_MIG_II_APPOINTMENT_DEVICE_SOURCE s
            WHERE s.ABYS_ID > @LastBridgeKey
            ORDER BY s.ABYS_ID ASC
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

            EXEC dbo.SP_MIG_II_APPOINTMENT_DEVICE_INSERT_RANGE
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
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_APPOINTMENT_DEVICE OFF; END TRY BEGIN CATCH END CATCH;
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
                        EXEC dbo.SP_MIG_II_APPOINTMENT_DEVICE_INSERT_ONE
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

                    EXEC dbo.SP_MIG_II_APPOINTMENT_DEVICE_INSERT_RANGE
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
                    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_APPOINTMENT_DEVICE OFF; END TRY BEGIN CATCH END CATCH;
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
    FROM energy.dbo.LS_005_01_APPOINTMENT_DEVICE;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_APPOINTMENT_DEVICE', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_APPOINTMENT_DEVICE
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

    IF @ErrorCount > 0
    BEGIN
        SELECT TOP 10
            l.MIGRATION_CODE,
            l.BATCH_NO,
            l.BRIDGE_FROM,
            l.BRIDGE_TO,
            l.SOURCE_ID,
            l.ERROR_MSG,
            l.LOGGED_AT
        FROM energy.dbo.MIG_BATCH_LOG l
        WHERE l.MIGRATION_CODE = 'LS_005_01_APPOINTMENT_DEVICE'
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO

-- EXEC energy.dbo.SP_MIGRATE_LS005_II_APPOINTMENT_DEVICE
--      @HARD_RESET = 1, @RESUME = 1, @BATCH_SIZE = 5000, @DEBUG = 1;
-- Wire sonrasi: EXEC energy.dbo.SP_MIG_II_APPOINTMENT_DEVICE_RESTORE_KEYS @DEBUG = 1;
