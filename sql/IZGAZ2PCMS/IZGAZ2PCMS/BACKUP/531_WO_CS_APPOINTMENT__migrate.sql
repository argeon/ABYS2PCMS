/* ============================================================
   SCRIPT_ID : WO_CS_APPOINTMENT_MIGRATE
   SCRIPT_NO : 531
   FILE      : 531_WO_CS_APPOINTMENT__migrate.sql
   VERSION   : 7
   ============================================================ */
-- v7: CUSTNAME LEFT 250 (setup ALTER NVARCHAR(250) ile)
-- ============================================================
-- SP_MIGRATE_LS005_CS_APPOINTMENT
-- Kaynak  : izgazMGR.dbo.LS_WORK
-- Hedef   : energy.dbo.LS_005_01_CS_APPOINTMENT
-- LREF    : IDENTITY_INSERT = kaynak LREF (= WO_WORK.ID)
-- ABYS_ID : kaynak ABYS_ID
--
-- Pass 1 dump: prm/meter/AGR JOIN yok.
-- User: FN_MIG_MAP_USER_USERID (+10000).
-- ASSINGPERSON: staging'de ID (decimal) → NVARCHAR string; isim wire sonra.
-- ABYS_LOCATION_WKT: geography → STAsText().
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.SP_MIG_FORCE_IDENTITY_INSERT_OFF', 'P') IS NOT NULL
    DROP PROCEDURE dbo.SP_MIG_FORCE_IDENTITY_INSERT_OFF;
GO
IF OBJECT_ID('dbo.SP_MIG_CLEAR_PEER_IDENTITY_INSERT', 'P') IS NOT NULL
    DROP PROCEDURE dbo.SP_MIG_CLEAR_PEER_IDENTITY_INSERT;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_CS_APPOINTMENT_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @RowCount  INT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    BEGIN TRY
        SET IDENTITY_INSERT dbo.LS_005_01_CS_APPOINTMENT ON;

        INSERT INTO dbo.LS_005_01_CS_APPOINTMENT (
        LREF, TYPEID, AGRID, FITNO, BINAID, SDATE, STATID, APPUSER, ADDR,
        CNTID, CNTSN, CNTMODEL, READENDEX, CURRENTENDEX,
        PRCUSER, PRCDATE, ADDDATE, ADDUSER, UPDUSER, UPDDATE,
        CANCELLED, CANCEL_DATE, CANCEL_DESCRIPTION,
        DAY15DEBTREF, OBJECTIONREF, CLOSEREF,
        CUSTREF, CUSTYPE, IS_INDUSTRY, CUSTNAME, IS_PREPAID, DELETED,
        INVCOUNT, INVTOTAL, PAIDDATE, GUVENCE_BEDELI, USULSUZINVCOUNT,
        LAWSTATID, READ_STATUS, CNT_STATUS, LASTREAD_DATE, DATE_DIFF,
        TP1, AGRSTATID, ASSINGDATE, ASSINGSTATUS, ASSINGPERSON,
        WO_DATE, WO_APPOINTMENT_DATE, PARENT_ID, WO_TYPE_ID, WO_CAUSE_ID,
        WORK_ORDER_PROCESS_ID, WORK_ORDER_PROCESS_TIMESTAMP, WORK_ORDER_PROCESS_USER_ID,
        ABYS_ID,   ABYS_QUARTER_STREET_ID, ABYS_METER_STATUS_ID,
        ABYS_TARIFF_TYPE_ID, ABYS_LAST_CORRECTOR_INDEX, ABYS_SKB_TARIFF_TYPE_ID,
        ABYS_IS_DEBT_PAYED, ABYS_ILLEGAL_USE_ID, ABYS_PRIORITY_ID,
        ABYS_WORK_ORDER_NUMBER, ABYS_REGISTER_ID, ABYS_INSTALLATION_ID,
        ABYS_SUBSCRIBER_TYPE_ID, ABYS_UNIT_NUMBER, ABYS_DO_PRINT, ABYS_AREA_ID,
        ABYS_SENDING_TYPE, ABYS_DESCRIPTION, ABYS_CHANGE_ASSIGNEE_USER_ID,
        ABYS_CONTROLLED_WORK_ID, ABYS_IS_DESTRUCTION_BUILDING,
        ABYS_LAST_CUTTING_TYPE_ID, ABYS_LAST_CUTTING_DATE,
        ABYS_INSTALLATION_STATUS_ID, ABYS_PAYMENT_STATUS, ABYS_POOL_ID,
        ABYS_INTEGRATION_CODE, ABYS_CANCELLATION_USER_ID, ABYS_VERSION,
        ABYS_CONTROLLED_READING_ID, ABYS_LOCATION_WKT, ABYS_INCOME_LIST,
        ABYS_WORK_REQUEST_ID, ABYS_LAST_RETROKIT_INDEX, ABYS_WORK_EAM_ID,
        ABYS_ASSIGNEE_TEAM_ID, ABYS_DISCOVERY_WORK_ID, ABYS_CREDIT,
        ABYS_LAST_INDEX, ABYS_LAST_ELECTRONIC_INDEX, ABYS_CANCEL_DESCRIPTION_FULL,
        ABYS_APPUSER, ABYS_ADDUSER, ABYS_UPDUSER, ABYS_PRCUSER,
        ABYS_WORK_ORDER_PROCESS_USER_ID
    )
    SELECT
        CAST(s.LREF AS INT),
        CAST(s.TYPEID AS INT),
        CAST(s.AGRID AS INT),
        s.FITNO,
        CAST(s.BINAID AS INT),
        ISNULL(
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.SDATE AS DATETIME2)),
            CAST('19000101' AS SMALLDATETIME)),
        CAST(s.STATID AS INT),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.APPUSER AS INT)),
        LEFT(s.ADDR, 600),
        CAST(s.CNTID AS INT),
        LEFT(s.CNTSN, 20),
        LEFT(s.CNTMODEL, 10),
        CAST(s.READENDEX AS INT),
        CAST(s.CURRENTENDEX AS INT),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.PRCUSER AS INT)),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.PRCDATE AS DATETIME2)),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ADDDATE AS DATETIME2)),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.ADDUSER AS INT)),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.UPDUSER AS INT)),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.UPDDATE AS DATETIME2)),
        CAST(CASE WHEN ISNULL(s.CANCELLED, 0) <> 0 THEN 1 ELSE 0 END AS BIT),
        energy.dbo.FN_SAFE_DT(CAST(s.CANCEL_DATE AS DATETIME2)),
        LEFT(s.CANCEL_DESCRIPTION, 500),
        CAST(s.DAY15DEBTREF AS INT),
        CAST(s.OBJECTIONREF AS INT),
        CAST(s.CLOSEREF AS INT),
        CAST(s.CUSTREF AS INT),
        CAST(s.CUSTYPE AS TINYINT),
        CASE WHEN s.IS_INDUSTRY IS NULL THEN NULL
             WHEN s.IS_INDUSTRY <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        LEFT(s.CUSTNAME, 250),
        CAST(CASE WHEN ISNULL(s.IS_PREPAID, 0) <> 0 THEN 1 ELSE 0 END AS BIT),
        CASE WHEN s.DELETED IS NULL THEN NULL
             WHEN s.DELETED <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CAST(s.INVCOUNT AS INT),
        CAST(s.INVTOTAL AS FLOAT),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.PAIDDATE AS DATETIME2)),
        s.GUVENCE_BEDELI,
        CAST(s.USULSUZINVCOUNT AS INT),
        CAST(s.LAWSTATID AS INT),
        LEFT(s.READ_STATUS, 50),
        LEFT(s.CNT_STATUS, 50),
        energy.dbo.FN_SAFE_DT(CAST(s.LASTREAD_DATE AS DATETIME2)),
        CAST(s.DATE_DIFF AS INT),
        LEFT(s.TP1, 50),
        LEFT(s.AGRSTATID, 50),
        ISNULL(
            energy.dbo.FN_SAFE_DT(CAST(s.ASSINGDATE AS DATETIME2)),
            CAST('19000101' AS DATETIME)),
        CAST(s.ASSINGSTATUS AS SMALLINT),
        LEFT(CAST(s.ASSINGPERSON AS NVARCHAR(50)), 50),
        energy.dbo.FN_SAFE_DT(CAST(s.WO_DATE AS DATETIME2)),
        CAST(s.WO_APPOINTMENT_DATE AS DATE),
        CAST(s.PARENT_ID AS INT),
        CAST(s.WO_TYPE_ID AS INT),
        CAST(s.WO_CAUSE_ID AS INT),
        CAST(s.WORK_ORDER_PROCESS_ID AS TINYINT),
        energy.dbo.FN_SAFE_DT(CAST(s.WORK_ORDER_PROCESS_TIMESTAMP AS DATETIME2)),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.WORK_ORDER_PROCESS_USER_ID AS INT)),

        CAST(s.ABYS_ID AS INT), 
        CAST(s.ABYS_QUARTER_STREET_ID AS INT),
        CAST(s.ABYS_METER_STATUS_ID AS INT),
        CAST(s.ABYS_TARIFF_TYPE_ID AS INT),
        s.ABYS_LAST_CORRECTOR_INDEX,
        CAST(s.ABYS_SKB_TARIFF_TYPE_ID AS INT),
        CASE WHEN s.ABYS_IS_DEBT_PAYED IS NULL THEN NULL
             WHEN s.ABYS_IS_DEBT_PAYED <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CAST(s.ABYS_ILLEGAL_USE_ID AS INT),
        CAST(s.ABYS_PRIORITY_ID AS INT),
        CAST(s.ABYS_WORK_ORDER_NUMBER AS INT),
        s.ABYS_REGISTER_ID,
        CAST(s.ABYS_INSTALLATION_ID AS INT),
        CAST(s.ABYS_SUBSCRIBER_TYPE_ID AS INT),
        LEFT(s.ABYS_UNIT_NUMBER, 20),
        CASE WHEN s.ABYS_DO_PRINT IS NULL THEN NULL
             WHEN s.ABYS_DO_PRINT <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CAST(s.ABYS_AREA_ID AS INT),
        CAST(s.ABYS_SENDING_TYPE AS TINYINT),
        s.ABYS_DESCRIPTION,
        CAST(s.ABYS_CHANGE_ASSIGNEE_USER_ID AS INT),
        CAST(s.ABYS_CONTROLLED_WORK_ID AS INT),
        CASE WHEN s.ABYS_IS_DESTRUCTION_BUILDING IS NULL THEN NULL
             WHEN s.ABYS_IS_DESTRUCTION_BUILDING <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CAST(s.ABYS_LAST_CUTTING_TYPE_ID AS INT),
        CAST(s.ABYS_LAST_CUTTING_DATE AS DATETIME2),
        CAST(s.ABYS_INSTALLATION_STATUS_ID AS SMALLINT),
        CAST(s.ABYS_PAYMENT_STATUS AS TINYINT),
        CAST(s.ABYS_POOL_ID AS INT),
        LEFT(s.ABYS_INTEGRATION_CODE, 20),
        CAST(s.ABYS_CANCELLATION_USER_ID AS INT),
        CAST(s.ABYS_VERSION AS INT),
        s.ABYS_CONTROLLED_READING_ID,
        CASE WHEN s.ABYS_LOCATION_WKT IS NULL THEN NULL
             ELSE s.ABYS_LOCATION_WKT.STAsText() END,
        s.ABYS_INCOME_LIST,
        TRY_CAST(s.ABYS_WORK_REQUEST_ID AS BIGINT),
        CAST(s.ABYS_LAST_RETROKIT_INDEX AS INT),
        CAST(s.ABYS_WORK_EAM_ID AS INT),
        CAST(s.ABYS_ASSIGNEE_TEAM_ID AS INT),
        CAST(s.ABYS_DISCOVERY_WORK_ID AS INT),
        s.ABYS_CREDIT,
        s.ABYS_LAST_INDEX,
        s.ABYS_LAST_ELECTRONIC_INDEX,
        s.ABYS_CANCEL_DESCRIPTION_FULL,
        CAST(s.APPUSER AS INT),
        CAST(s.ADDUSER AS INT),
        CAST(s.UPDUSER AS INT),
        CAST(s.PRCUSER AS INT),
        CAST(s.WORK_ORDER_PROCESS_USER_ID AS INT)
    FROM izgazMGR.dbo.LS_WORK s
    WHERE s.LREF BETWEEN @BatchFrom AND @BatchTo
      AND s.LREF BETWEEN 1 AND 2147483647
      AND NOT EXISTS (
          SELECT 1
          FROM energy.dbo.LS_005_01_CS_APPOINTMENT t
          WHERE t.ABYS_ID = CAST(s.ABYS_ID AS INT)
             OR t.LREF = CAST(s.LREF AS INT)
      );

        SET @RowCount = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_CS_APPOINTMENT OFF; END TRY BEGIN CATCH END CATCH;
        THROW;
    END CATCH

    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_CS_APPOINTMENT OFF; END TRY BEGIN CATCH END CATCH;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_CS_APPOINTMENT_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_CS_APPOINTMENT t
        WHERE t.LREF = @CurID OR t.ABYS_ID = @CurID
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_CS_APPOINTMENT_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_CS_APPOINTMENT_HARD_RESET
    @DELETE_BATCH INT = 10000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @MaxLref INT, @TotalStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_CS_APPOINTMENT ABYS kayitlari (batch=%d) ***', 0, 1, @DELETE_BATCH) WITH NOWAIT;

    SET IDENTITY_INSERT dbo.LS_005_01_CS_APPOINTMENT OFF;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_005_01_CS_APPOINTMENT
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
    FROM energy.dbo.LS_005_01_CS_APPOINTMENT;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_CS_APPOINTMENT', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s, CHECKIDENT=%d', 0, 1, @TotalStr, @MaxLref) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_CS_APPOINTMENT
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
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_CS_APPOINTMENT',
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

    EXEC dbo.SP_MIG_CS_APPOINTMENT_VALIDATE_ALL @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_CS_APPOINTMENT_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
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
      AND t.name = 'LS_WORK'
      AND p.index_id IN (0, 1);

    SELECT @MaxBridgeKey = MAX(s.LREF)
    FROM izgazMGR.dbo.LS_WORK s
    WHERE s.LREF BETWEEN 1 AND 2147483647;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_WORK',
        @TargetTable    = 'LS_005_01_CS_APPOINTMENT',
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
            + ' | LREF=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @BatchFrom  = @LastBridgeKey + 1;
        SET @RowCount   = 0;

        SELECT @BatchTo = MAX(LREF)
        FROM (
            SELECT TOP (@BATCH_SIZE) s.LREF
            FROM izgazMGR.dbo.LS_WORK s
            WHERE s.LREF > @LastBridgeKey
              AND s.LREF <= 2147483647
            ORDER BY s.LREF ASC
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

            EXEC dbo.SP_MIG_CS_APPOINTMENT_INSERT_RANGE
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
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_CS_APPOINTMENT OFF; END TRY BEGIN CATCH END CATCH;
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
                        EXEC dbo.SP_MIG_CS_APPOINTMENT_INSERT_ONE
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
                            N'LREF=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

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

                    EXEC dbo.SP_MIG_CS_APPOINTMENT_INSERT_RANGE
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
                    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_CS_APPOINTMENT OFF; END TRY BEGIN CATCH END CATCH;
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
    FROM energy.dbo.LS_005_01_CS_APPOINTMENT;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_CS_APPOINTMENT', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_CS_APPOINTMENT
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
        WHERE l.MIGRATION_CODE = 'LS_005_01_CS_APPOINTMENT'
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO

 --EXEC energy.dbo.SP_MIGRATE_LS005_CS_APPOINTMENT
 --     @HARD_RESET = 1, @RESUME = 1, @BATCH_SIZE = 15000, @DEBUG = 1;
