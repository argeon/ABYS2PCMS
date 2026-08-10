/* ============================================================
   SCRIPT_ID : II_APPOINTMENT_MIGRATE
   SCRIPT_NO : 533
   FILE      : 533_II_APPOINTMENT__migrate.sql
   VERSION   : 3
   ============================================================ */
-- v3: INSERT dogrudan II_APPOINTMENT; scalar UDF yok (inline +10000 / tarih)
--     PROJECT_ID TRY_CAST; batch key II_APPOINTMENT.ID
-- v2: Hedefte olmayan kaynak kolonlar ABYS_* olarak aktarilir
-- ============================================================
-- SP_MIGRATE_LS005_II_APPOINTMENT
-- Kaynak  : izgazMGR.dbo.II_APPOINTMENT
-- Hedef   : energy.dbo.LS_005_01_APPOINTMENT
-- LREF    : IDENTITY_INSERT = kaynak ID
-- ABYS_ID : kaynak ID
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @RowCount  INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    BEGIN TRY
        SET IDENTITY_INSERT dbo.LS_005_01_APPOINTMENT ON;

        INSERT INTO energy.dbo.LS_005_01_APPOINTMENT (
            LREF, APPOINTMENT_TYPE_ID, APPOINTMENT_POOL_REF,
            REQUEST_DATE, APPOINTMENT_ASSIGNDATE, APPOINTMENT_DATE,
            STATUS, PROJECT_ID, FITNO, FIRM_ID, TEAM_ID,
            AGREEMENT_LREF, APPOINTMENT_GOING_NUMBER,
            CAMPAIGN_ID, CAMPAIGN_PERIOD, RECORD_TYPE, DESCRIPTION,
            METER_ID, ACCOUNT_ID,
            IS_SUSPEND, SUSPEND_DATE, SUSPEND_USER_ID, SUSPEND_DESCRIPTION,
            APPROVAL_DESCRIPTION,
            RSLT_METER_NUMBER, RSLT_LAST_INDEX, RSLT_DATE,
            RSLT_INSTALLATION_CONTROL, RSLT_OPEN, RSLT_RELEASE, RSLT_CONTROL,
            GAS_CUTTING_STATUS, NEXT_CONTROL_DATE, WHERE_REMOVING_METER,
            SEAL_SERIAL_NUMBER, REGULATOR_TYPE_ID, REGULATOR_MARK_ID,
            REGULATOR_SERIAL_NUMBER, EARTHQUAKE_VALVE_MARK_ID,
            WORKORDER_REF,
            CANCEL_DATE, CANCEL_USER_ID, CANCEL_DESCRIPTION,
            CANCEL_BILL_NUMBER, CANCEL_BILL_DATE,
            WHERE_REMOVING_REGULATOR, COMEBACK_DATE,
            CREATED_USER_ID, CREATED_DATE, UPDATED_USER_ID, UPDATED_DATE,
            IS_ADJUSTABLE,
            FATURA_TARIHI, FATURA_BEDELI, FATURA_BEDELI_KDV, FATURA_NUMARASI,
            STARTTIME, ENDTIME,
            OLDPROJECT_ID, PROJECTLINE_ID, OLD_PROJECT_CODE, OLD_PROJECT_YEAR,
            ENGINEERID, ENGINEERLREF,
            ABYS_ID, ABYS_PROJECT_ID, ABYS_PROJECT_INSTALLATION_ID,
            ABYS_FIRM_ID, ABYS_AGREEMENT_ID, ABYS_METER_ID, ABYS_CAMPAIGN_ID,
            ABYS_APPOINTMENT_TYPE_ID,
            ABYS_CREATED_USER_ID, ABYS_UPDATED_USER_ID,
            ABYS_SUSPEND_USER_ID, ABYS_CANCEL_USER_ID,
            ABYS_REGULATOR_TYPE_ID, ABYS_REGULATOR_MARK_ID,
            ABYS_EARTHQUAKE_VALVE_MARK_ID,
            ABYS_OLD_VALUES, ABYS_INTEGRATION_CODE, ABYS_VERSION,
            ABYS_CREATED_TIMESTAMP, ABYS_UPDATED_TIMESTAMP,
            ABYS_FATURA_TARIHI_, ABYS_FATURA_BEDELI_,
            ABYS_FATURA_BEDELI_KDV_, ABYS_FATURA_NUMARASI_,
            ABYS_INSTALLATION_ID_, ABYS_AGR_INSTALLATION_ID_,
            ABYS_RANDEVU_GIRIS_TAR_
        )
        SELECT
            CAST(s.ID AS INT),
            CAST(s.APPOINTMENT_TYPE_ID AS INT),
            CAST(0 AS INT),
            CASE WHEN s.REQUEST_DATE IS NULL THEN NULL
                 WHEN CAST(s.REQUEST_DATE AS DATETIME2) < '17530101' THEN NULL
                 WHEN CAST(s.REQUEST_DATE AS DATETIME2) > '99991231 23:59:59.997' THEN NULL
                 ELSE CAST(s.REQUEST_DATE AS DATETIME) END,
            CAST(NULL AS DATETIME),
            CAST(NULL AS DATETIME), -- RANDEVU_GIRIS_TAR_ 196 dump'ta yok
            CAST(s.STATUS AS TINYINT),
            ISNULL(TRY_CAST(s.PROJECT_ID AS INT), 0),
            CAST(NULL AS BIGINT),   -- INSTALLATION_ID_ 196 dump'ta yok
            CAST(NULL AS INT),
            CAST(NULL AS INT),
            CAST(NULL AS INT),
            CAST(s.APPOINTMENT_GOING_NUMBER AS TINYINT),
            CAST(NULL AS INT),
            CAST(s.CAMPAIGN_PERIOD AS SMALLINT),
            CAST(s.RECORD_TYPE AS TINYINT),
            LEFT(s.DESCRIPTION, 500),
            CAST(NULL AS INT),
            s.ACCOUNT_ID,
            CAST(ISNULL(s.IS_SUSPEND, 0) AS TINYINT),
            CASE WHEN s.SUSPEND_DATE IS NULL THEN NULL
                 WHEN CAST(s.SUSPEND_DATE AS DATETIME2) < '17530101' THEN NULL
                 WHEN CAST(s.SUSPEND_DATE AS DATETIME2) > '99991231 23:59:59.997' THEN NULL
                 ELSE CAST(s.SUSPEND_DATE AS DATETIME) END,
            CASE WHEN s.SUSPEND_USER_ID IS NULL THEN NULL
                 ELSE CAST(s.SUSPEND_USER_ID AS INT) + 10000 END,
            LEFT(s.SUSPEND_DESCRIPTION, 500),
            LEFT(s.APPROVAL_DESCRIPTION, 500),
            LEFT(s.RSLT_METER_NUMBER, 25),
            CAST(s.RSLT_LAST_INDEX AS DECIMAL(15, 3)),
            CASE WHEN s.RSLT_DATE IS NULL THEN NULL
                 WHEN CAST(s.RSLT_DATE AS DATETIME2) < '17530101' THEN NULL
                 WHEN CAST(s.RSLT_DATE AS DATETIME2) > '99991231 23:59:59.997' THEN NULL
                 ELSE CAST(s.RSLT_DATE AS DATETIME) END,
            CAST(s.RSLT_INSTALLATION_CONTROL AS TINYINT),
            CAST(s.RSLT_OPEN AS TINYINT),
            CAST(s.RSLT_RELEASE AS TINYINT),
            CAST(s.RSLT_CONTROL AS TINYINT),
            CAST(s.GAS_CUTTING_STATUS AS TINYINT),
            CASE WHEN s.NEXT_CONTROL_DATE IS NULL THEN NULL
                 WHEN CAST(s.NEXT_CONTROL_DATE AS DATETIME2) < '17530101' THEN NULL
                 WHEN CAST(s.NEXT_CONTROL_DATE AS DATETIME2) > '99991231 23:59:59.997' THEN NULL
                 ELSE CAST(s.NEXT_CONTROL_DATE AS DATETIME) END,
            CAST(s.WHERE_REMOVING_METER AS TINYINT),
            LEFT(s.SEAL_SERIAL_NUMBER, 15),
            CAST(NULL AS INT),
            CAST(NULL AS INT),
            LEFT(s.REGULATOR_SERIAL_NUMBER, 20),
            CAST(NULL AS INT),
            CAST(NULL AS INT),
            CASE WHEN s.CANCEL_DATE IS NULL THEN NULL
                 WHEN CAST(s.CANCEL_DATE AS DATETIME2) < '17530101' THEN NULL
                 WHEN CAST(s.CANCEL_DATE AS DATETIME2) > '99991231 23:59:59.997' THEN NULL
                 ELSE CAST(s.CANCEL_DATE AS DATETIME) END,
            CASE WHEN s.CANCEL_USER_ID IS NULL THEN NULL
                 ELSE CAST(s.CANCEL_USER_ID AS INT) + 10000 END,
            LEFT(s.CANCEL_DESCRIPTION, 200),
            LEFT(s.CANCEL_BILL_NUMBER, 20),
            CASE WHEN s.CANCEL_BILL_DATE IS NULL THEN NULL
                 WHEN CAST(s.CANCEL_BILL_DATE AS DATETIME2) < '17530101' THEN NULL
                 WHEN CAST(s.CANCEL_BILL_DATE AS DATETIME2) > '99991231 23:59:59.997' THEN NULL
                 ELSE CAST(s.CANCEL_BILL_DATE AS DATETIME) END,
            CAST(s.WHERE_REMOVING_REGULATOR AS TINYINT),
            CASE WHEN s.COMEBACK_DATE IS NULL THEN NULL
                 WHEN CAST(s.COMEBACK_DATE AS DATETIME2) < '17530101' THEN NULL
                 WHEN CAST(s.COMEBACK_DATE AS DATETIME2) > '99991231 23:59:59.997' THEN NULL
                 ELSE CAST(s.COMEBACK_DATE AS DATETIME) END,
            CASE WHEN s.CREATED_USER_ID IS NULL THEN NULL
                 ELSE CAST(s.CREATED_USER_ID AS INT) + 10000 END,
            ISNULL(
                CASE WHEN s.CREATED_TIMESTAMP IS NULL THEN NULL
                     WHEN CAST(s.CREATED_TIMESTAMP AS DATETIME2) < '17530101' THEN NULL
                     WHEN CAST(s.CREATED_TIMESTAMP AS DATETIME2) > '99991231 23:59:59.997' THEN NULL
                     ELSE CAST(s.CREATED_TIMESTAMP AS DATETIME) END,
                CAST('19000101' AS DATETIME)),
            CASE WHEN s.UPDATED_USER_ID IS NULL THEN NULL
                 ELSE CAST(s.UPDATED_USER_ID AS INT) + 10000 END,
            CASE WHEN s.UPDATED_TIMESTAMP IS NULL THEN NULL
                 WHEN CAST(s.UPDATED_TIMESTAMP AS DATETIME2) < '17530101' THEN NULL
                 WHEN CAST(s.UPDATED_TIMESTAMP AS DATETIME2) > '99991231 23:59:59.997' THEN NULL
                 ELSE CAST(s.UPDATED_TIMESTAMP AS DATETIME) END,
            CAST(s.IS_ADJUSTABLE AS TINYINT),
            CAST(NULL AS DATETIME),           -- FATURA_*_ 196 dump'ta yok
            CAST(NULL AS DECIMAL(18, 0)),
            CAST(NULL AS DECIMAL(18, 0)),
            CAST(NULL AS DECIMAL(18, 0)),
            CAST(NULL AS DATETIME),
            CAST(NULL AS DATETIME),
            CAST(NULL AS INT),
            CAST(NULL AS INT),
            CAST(NULL AS NVARCHAR(100)),
            CAST(NULL AS INT),
            CAST(NULL AS INT),
            CAST(NULL AS INT),
            CAST(s.ID AS BIGINT),
            CAST(s.PROJECT_ID AS BIGINT),
            CAST(s.PROJECT_INSTALLATION_ID AS BIGINT),
            CAST(s.FIRM_ID AS BIGINT),
            CAST(s.AGREEMENT_ID AS BIGINT),
            CAST(s.METER_ID AS BIGINT),
            CAST(s.CAMPAIGN_ID AS BIGINT),
            CAST(s.APPOINTMENT_TYPE_ID AS BIGINT),
            CAST(s.CREATED_USER_ID AS BIGINT),
            CAST(s.UPDATED_USER_ID AS BIGINT),
            CAST(s.SUSPEND_USER_ID AS BIGINT),
            CAST(s.CANCEL_USER_ID AS BIGINT),
            CAST(s.REGULATOR_TYPE_ID AS BIGINT),
            CAST(s.REGULATOR_MARK_ID AS BIGINT),
            CAST(s.EARTHQUAKE_VALVE_MARK_ID AS BIGINT),
            s.OLD_VALUES,
            LEFT(s.INTEGRATION_CODE, 20),
            CAST(s.VERSION AS BIGINT),
            s.CREATED_TIMESTAMP,
            s.UPDATED_TIMESTAMP,
            CAST(NULL AS DATETIME2(0)),
            CAST(NULL AS DECIMAL(22, 0)),
            CAST(NULL AS DECIMAL(22, 0)),
            CAST(NULL AS DECIMAL(22, 0)),
            CAST(NULL AS DECIMAL(22, 0)),
            CAST(NULL AS DECIMAL(22, 0)),
            CAST(NULL AS DATETIME2(0))
        FROM (
            -- 196: II_APPOINTMENT audit/log (coklu satir / ID) → son VERSION
            SELECT
                s.*,
                ROW_NUMBER() OVER (
                    PARTITION BY s.ID
                    ORDER BY ISNULL(s.VERSION, 0) DESC, s.UPDATED_TIMESTAMP DESC, s.LOG_DATE DESC
                ) AS rn
            FROM izgazMGR.dbo.II_APPOINTMENT s
            WHERE s.ID BETWEEN @BatchFrom AND @BatchTo
              AND s.ID BETWEEN 1 AND 2147483647
        ) s
        WHERE s.rn = 1
          AND NOT EXISTS (
              SELECT 1
              FROM energy.dbo.LS_005_01_APPOINTMENT t WITH (INDEX(UX_LS005_APPOINTMENT_ABYS_ID))
              WHERE t.ABYS_ID = s.ID
          );

        SET @RowCount = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_APPOINTMENT OFF; END TRY BEGIN CATCH END CATCH;
        THROW;
    END CATCH

    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_APPOINTMENT OFF; END TRY BEGIN CATCH END CATCH;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_APPOINTMENT t
        WHERE t.ABYS_ID = @CurID
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_II_APPOINTMENT_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_HARD_RESET
    @DELETE_BATCH INT = 10000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @MaxLref INT, @TotalStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_APPOINTMENT ABYS kayitlari (batch=%d) ***', 0, 1, @DELETE_BATCH) WITH NOWAIT;

    SET IDENTITY_INSERT dbo.LS_005_01_APPOINTMENT OFF;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_005_01_APPOINTMENT
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
    FROM energy.dbo.LS_005_01_APPOINTMENT;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_APPOINTMENT', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s, CHECKIDENT=%d', 0, 1, @TotalStr, @MaxLref) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_II_APPOINTMENT
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
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_APPOINTMENT',
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

    EXEC dbo.SP_MIG_II_APPOINTMENT_VALIDATE_ALL @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_II_APPOINTMENT_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    -- Audit/log dump: satir sayisi degil, tekil ID (latest VERSION)
    SELECT @SourceCount = COUNT(DISTINCT s.ID)
    FROM izgazMGR.dbo.II_APPOINTMENT s
    WHERE s.ID BETWEEN 1 AND 2147483647;

    SELECT @MaxBridgeKey = MAX(s.ID)
    FROM izgazMGR.dbo.II_APPOINTMENT s
    WHERE s.ID BETWEEN 1 AND 2147483647;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'II_APPOINTMENT',
        @TargetTable    = 'LS_005_01_APPOINTMENT',
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

        SELECT @BatchTo = MAX(ID)
        FROM (
            SELECT TOP (@BATCH_SIZE) d.ID
            FROM (
                SELECT DISTINCT s.ID
                FROM izgazMGR.dbo.II_APPOINTMENT s
                WHERE s.ID > @LastBridgeKey
                  AND s.ID <= 2147483647
            ) d
            ORDER BY d.ID ASC
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

            EXEC dbo.SP_MIG_II_APPOINTMENT_INSERT_RANGE
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
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_APPOINTMENT OFF; END TRY BEGIN CATCH END CATCH;
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
                        EXEC dbo.SP_MIG_II_APPOINTMENT_INSERT_ONE
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

                    EXEC dbo.SP_MIG_II_APPOINTMENT_INSERT_RANGE
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
                    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_APPOINTMENT OFF; END TRY BEGIN CATCH END CATCH;
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
    FROM energy.dbo.LS_005_01_APPOINTMENT;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_APPOINTMENT', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_APPOINTMENT
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
        WHERE l.MIGRATION_CODE = 'LS_005_01_APPOINTMENT'
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO

-- EXEC energy.dbo.SP_MIGRATE_LS005_II_APPOINTMENT
--      @HARD_RESET = 1, @RESUME = 1, @BATCH_SIZE = 5000, @DEBUG = 1;
-- Wire sonrasi: EXEC energy.dbo.SP_MIG_II_APPOINTMENT_RESTORE_KEYS @DEBUG = 1;
