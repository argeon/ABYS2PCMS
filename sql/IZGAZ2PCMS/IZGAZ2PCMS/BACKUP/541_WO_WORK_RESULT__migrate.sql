/* ============================================================
   SCRIPT_ID : WO_WORK_RESULT_MIGRATE
   SCRIPT_NO : 541
   FILE      : 541_WO_WORK_RESULT__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_WO_WORK_RESULT
-- Kaynak  : izgazMGR.dbo.WO_WORK_RESULT
-- Hedef   : energy.dbo.LS_005_01_WO_WORK_RESULT
-- LREF    : IDENTITY_INSERT = kaynak ID
-- ABYS_ID : kaynak ID
-- WORK_ID : direkt (= LS_005_01_CS_APPOINTMENT.LREF / WO_WORK.ID)
--
-- Pass 1 dump: prm/meter/appointment JOIN yok.
-- User: FN_MIG_MAP_USER_USERID (+10000, aritmetik).
-- Hedef-only kolonlar (M_METER_NUMBER vb.): NULL — proje sonu UPDATE.
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_WO_WORK_RESULT_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @RowCount  INT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    BEGIN TRY
        SET IDENTITY_INSERT dbo.LS_005_01_WO_WORK_RESULT ON;

        INSERT INTO energy.dbo.LS_005_01_WO_WORK_RESULT (
        LREF, WORK_ID, CAUSE_RESULT_ID, CAUSE_RESULT_REASON_ID,
        COMPLETED_DATE, ASSIGNEE_USER_ID, DESCRIPTION,
        C_METER_NUMBER, C_METER_MARK_ID, C_METER_MODEL_ID,
        C_INDEX, C_CORRECTED_INDEX, C_PRODUCTION_YEAR,
        C_COMMUNUCATION_MODULE_ID, C_CORRECTOR_MODULE_ID,
        C_CONSUMPTION, C_METER_TYPE_ID,
        M_METER_ID, M_INDEX, M_CORRECTED_INDEX,
        M_COMMUNUCATION_MODULE_ID, M_CORRECTOR_MODULE_ID,
        I_AGREEMENT_NUMBER, I_CUSTOMER_NAME, I_SERVICE_BOX_CODE,
        I_DOOR_NUMBER, I_FLAT_NUMBER, I_FLOOR_NUMBER, I_METER_NUMBER,
        O_CUTTING_SERIAL_NUMBER, O_CUTTING_TYPE_ID,
        O_VALVE_ARM_STATUS, O_IS_METER_INTERFERE, O_HAS_SEAL,
        PROBLEM_DESCRIPTION,
        CREATED_USER_ID, CREATED_TIMESTAMP, UPDATED_USER_ID, UPDATED_TIMESTAMP, VERSION,
        C_IS_BROKEN, I_MINUTE_NUMBER, I_MINUTE_DATE, ASSIGNEE_USER_ID_2,
        LONGITUDE, LATITUDE, CONTROL_CAUSE_ID, CONTROL_PRM_ID, CONTROL_DESCRIPTION,
        C_METER_ID, IS_PICTURE_SEND_LATER, IS_APPROVED,
        C_STAMP_YEAR, C_METER_DIAMETER_ID, C_METER_LINK_DIAMETER_ID, METER_ADDRESS,
        C_RETROKIT_INDEX, M_RETROKIT_INDEX, WAREHOUSE_SHELF_ID, SACK_NUMBER, REKOR_SEAL_NUMBER,
        C_FIRST_INDEX, C_CORRECTOR_FIRST_INDEX, C_CORRECTOR_LAST_INDEX,
        TERMINAL_CODE, SUBSCRIBER_LOCATION, LAST_INDEX, METER_STATUS_CODE, IS_BARCODE_READING,
        M_METER_NUMBER, M_PRODUCTION_YEAR, M_METER_MARK_ID, M_METER_TYPE_ID,
        ABYS_ID, ABYS_WORK_ID,
        ABYS_ASSIGNEE_USER_ID, ABYS_ASSIGNEE_USER_ID_2,
        ABYS_CREATED_USER_ID, ABYS_UPDATED_USER_ID,
        ABYS_CAUSE_RESULT_ID, ABYS_CAUSE_RESULT_REASON_ID,
        ABYS_C_METER_ID, ABYS_M_METER_ID, ABYS_WAREHOUSE_SHELF_ID
    )
    SELECT
        CAST(s.ID AS INT),
        CAST(s.WORK_ID AS INT),
        CAST(s.CAUSE_RESULT_ID AS INT),
        CAST(s.CAUSE_RESULT_REASON_ID AS INT),
        ISNULL(
            energy.dbo.FN_SAFE_DT(CAST(s.COMPLETED_DATE AS DATETIME2)),
            CAST('19000101' AS DATETIME)),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.ASSIGNEE_USER_ID AS INT)),
        s.DESCRIPTION,
        LEFT(s.C_METER_NUMBER, 25),
        CAST(s.C_METER_MARK_ID AS INT),
        CAST(s.C_METER_MODEL_ID AS INT),
        CAST(s.C_INDEX AS DECIMAL(15,3)),
        CAST(s.C_CORRECTED_INDEX AS DECIMAL(15,3)),
        CAST(s.C_PRODUCTION_YEAR AS INT),
        CAST(s.C_COMMUNUCATION_MODULE_ID AS INT),
        CAST(s.C_CORRECTOR_MODULE_ID AS INT),
        CAST(s.C_CONSUMPTION AS INT),
        CAST(s.C_METER_TYPE_ID AS INT),
        CAST(s.M_METER_ID AS INT),
        CAST(s.M_INDEX AS INT),
        CAST(s.M_CORRECTED_INDEX AS INT),
        CAST(s.M_COMMUNUCATION_MODULE_ID AS INT),
        CAST(s.M_CORRECTOR_MODULE_ID AS INT),
        CAST(s.I_AGREEMENT_NUMBER AS INT),
        LEFT(s.I_CUSTOMER_NAME, 100),
        LEFT(s.I_SERVICE_BOX_CODE, 20),
        LEFT(s.I_DOOR_NUMBER, 10),
        LEFT(s.I_FLAT_NUMBER, 10),
        LEFT(s.I_FLOOR_NUMBER, 10),
        LEFT(s.I_METER_NUMBER, 20),
        LEFT(s.O_CUTTING_SERIAL_NUMBER, 50),
        CAST(s.O_CUTTING_TYPE_ID AS INT),
        CASE WHEN s.O_VALVE_ARM_STATUS IS NULL THEN NULL
             WHEN s.O_VALVE_ARM_STATUS <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CASE WHEN s.O_IS_METER_INTERFERE IS NULL THEN NULL
             WHEN s.O_IS_METER_INTERFERE <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CASE WHEN s.O_HAS_SEAL IS NULL THEN NULL
             WHEN s.O_HAS_SEAL <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        s.PROBLEM_DESCRIPTION,
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.CREATED_USER_ID AS INT)),
        ISNULL(
            energy.dbo.FN_SAFE_DT(CAST(s.CREATED_TIMESTAMP AS DATETIME2)),
            CAST('19000101' AS DATETIME)),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.UPDATED_USER_ID AS INT)),
        energy.dbo.FN_SAFE_DT(CAST(s.UPDATED_TIMESTAMP AS DATETIME2)),
        CAST(s.VERSION AS INT),
        CASE WHEN s.C_IS_BROKEN IS NULL THEN NULL
             WHEN s.C_IS_BROKEN <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        LEFT(s.I_MINUTE_NUMBER, 10),
        energy.dbo.FN_SAFE_DT(CAST(s.I_MINUTE_DATE AS DATETIME2)),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.ASSIGNEE_USER_ID_2 AS INT)),
        CAST(s.LONGITUDE AS DECIMAL(10,8)),
        CAST(s.LATITUDE AS DECIMAL(10,8)),
        CAST(s.CONTROL_CAUSE_ID AS INT),
        CAST(s.CONTROL_PRM_ID AS INT),
        LEFT(s.CONTROL_DESCRIPTION, 500),
        CAST(s.C_METER_ID AS INT),
        CASE WHEN s.IS_PICTURE_SEND_LATER IS NULL THEN NULL
             WHEN s.IS_PICTURE_SEND_LATER <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CASE WHEN s.IS_APPROVED IS NULL THEN NULL
             WHEN s.IS_APPROVED <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CAST(s.C_STAMP_YEAR AS INT),
        CAST(s.C_METER_DIAMETER_ID AS INT),
        CAST(s.C_METER_LINK_DIAMETER_ID AS INT),
        LEFT(s.METER_ADDRESS, 255),
        CAST(s.C_RETROKIT_INDEX AS INT),
        CAST(s.M_RETROKIT_INDEX AS INT),
        CAST(s.WAREHOUSE_SHELF_ID AS INT),
        LEFT(s.SACK_NUMBER, 20),
        LEFT(s.REKOR_SEAL_NUMBER, 50),
        /* hedef-only — Pass 4 enrich */
        NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL, NULL,
        /* ABYS bridge */
        CAST(s.ID AS INT),
        CAST(s.WORK_ID AS INT),
        CAST(s.ASSIGNEE_USER_ID AS INT),
        CAST(s.ASSIGNEE_USER_ID_2 AS INT),
        CAST(s.CREATED_USER_ID AS INT),
        CAST(s.UPDATED_USER_ID AS INT),
        CAST(s.CAUSE_RESULT_ID AS INT),
        CAST(s.CAUSE_RESULT_REASON_ID AS INT),
        CAST(s.C_METER_ID AS INT),
        CAST(s.M_METER_ID AS INT),
        CAST(s.WAREHOUSE_SHELF_ID AS INT)
    FROM izgazMGR.dbo.WO_WORK_RESULT s
    WHERE s.ID BETWEEN @BatchFrom AND @BatchTo
      AND s.ID BETWEEN 1 AND 2147483647
      AND NOT EXISTS (
          SELECT 1
          FROM energy.dbo.LS_005_01_WO_WORK_RESULT t
          WHERE t.ABYS_ID = CAST(s.ID AS INT)
             OR t.LREF = CAST(s.ID AS INT)
      );

        SET @RowCount = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_WO_WORK_RESULT OFF; END TRY BEGIN CATCH END CATCH;
        THROW;
    END CATCH

    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_WO_WORK_RESULT OFF; END TRY BEGIN CATCH END CATCH;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_WO_WORK_RESULT_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_WO_WORK_RESULT t
        WHERE t.LREF = @CurID OR t.ABYS_ID = @CurID
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_WO_WORK_RESULT_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_WO_WORK_RESULT_HARD_RESET
    @DELETE_BATCH INT = 10000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @MaxLref INT, @TotalStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_WO_WORK_RESULT ABYS kayitlari (batch=%d) ***', 0, 1, @DELETE_BATCH) WITH NOWAIT;

    SET IDENTITY_INSERT dbo.LS_005_01_WO_WORK_RESULT OFF;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_005_01_WO_WORK_RESULT
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
    FROM energy.dbo.LS_005_01_WO_WORK_RESULT;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_WO_WORK_RESULT', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s, CHECKIDENT=%d', 0, 1, @TotalStr, @MaxLref) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_WO_WORK_RESULT
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
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_WO_WORK_RESULT',
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

    EXEC dbo.SP_MIG_WO_WORK_RESULT_VALIDATE_ALL @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_WO_WORK_RESULT_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
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
      AND t.name = 'WO_WORK_RESULT'
      AND p.index_id IN (0, 1);

    SELECT @MaxBridgeKey = MAX(s.ID)
    FROM izgazMGR.dbo.WO_WORK_RESULT s
    WHERE s.ID BETWEEN 1 AND 2147483647;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'WO_WORK_RESULT',
        @TargetTable    = 'LS_005_01_WO_WORK_RESULT',
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
            FROM izgazMGR.dbo.WO_WORK_RESULT s
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

            EXEC dbo.SP_MIG_WO_WORK_RESULT_INSERT_RANGE
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
            SET IDENTITY_INSERT dbo.LS_005_01_WO_WORK_RESULT OFF;
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
                        EXEC dbo.SP_MIG_WO_WORK_RESULT_INSERT_ONE
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

                    EXEC dbo.SP_MIG_WO_WORK_RESULT_INSERT_RANGE
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
                    SET IDENTITY_INSERT dbo.LS_005_01_WO_WORK_RESULT OFF;
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
    FROM energy.dbo.LS_005_01_WO_WORK_RESULT;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_WO_WORK_RESULT', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_WO_WORK_RESULT
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
        WHERE l.MIGRATION_CODE = 'LS_005_01_WO_WORK_RESULT'
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO

 --EXEC energy.dbo.SP_MIGRATE_LS005_WO_WORK_RESULT
 --     @HARD_RESET = 0, @RESUME = 1, @BATCH_SIZE = 5000, @DEBUG = 1;
