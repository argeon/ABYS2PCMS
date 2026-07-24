/* ============================================================
   SCRIPT_ID : OPR_SYNC_CLIENT_MIGRATE
   SCRIPT_NO : 561
   FILE      : 561_OPR_SYNC_CLIENT__migrate.sql
   VERSION   : 3
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS_OPR_SYNC_CLIENT
-- Kaynak  : izgazMGR.dbo.OPR_SYNC_CLIENT
-- Hedef   : energy.dbo.LS_OPR_SYNC_CLIENT
-- LREF    : IDENTITY (yeni) — IDENTITY_INSERT YOK (diger COMPANY_CODE veri var)
-- ABYS_ID : kaynak ID
--
-- Mapping ozeti:
--   COMPANY_CODE ← CORPORATION_ID
--   PRINTER_TYPE ← TRY_CAST veya enum adi → ordinal (0=BIXOLON..)
--   bit/smallint ← CASE <> 0
--   User: FN_MIG_MAP_USER_USERID (+10000)
--   Hedef-only: SUBSCRIBER_ID, REVISION_*, SYNC_*, ALWAYS_SEND,
--               DELETED_* = NULL; IS_DELETED = 0
-- Idempotent: NOT EXISTS (ABYS_ID = kaynak ID OR CODE = CODE)
-- HARD_RESET: yalnizca ABYS_ID IS NOT NULL siler (native COMPANY_CODE korunur)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_OPR_SYNC_CLIENT_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @RowCount  INT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    INSERT INTO energy.dbo.LS_OPR_SYNC_CLIENT (
        ABYS_ID,
        COMPANY_CODE,
        CODE,
        CLIENT_TYPE,
        SERIAL,
        DESCRIPTION,
        REGISTER_REL_ID,
        SUBSCRIBER_ID,
        LAST_CONNECTION_TIME,
        IS_READING,
        IS_WO_WORK,
        IS_OPR_WORK,
        GSM_NUMBER,
        IS_SEND_MAIL_LOG,
        IS_COLLECT_LOG,
        PRINTER_TYPE,
        IS_SHOW_FIRST_INDEX,
        IS_DM_DISCOVERY,
        IS_GPS_REQUIRED,
        IS_ADDRESS_UPDATE_REQUIRED,
        IS_ADDRESS_UPDATE,
        BILL_SERIAL,
        LAST_BILL_NUMBER,
        LAST_READING_DATE,
        MINUTE_NUMBER,
        MINUTE_SERIAL,
        IS_EAM,
        IS_SUBSCRIBER_UPDATE,
        REVISION_LIMIT_PER_READING,
        REVISION_LIMIT_GENERAL,
        READING_TYPE,
        SYNC_PERIOD,
        SYNC_TYPE,
        SYNC_ITEM_COUNT,
        ALWAYS_SEND,
        IS_ACTIVE,
        CREATED_USER_ID,
        CREATED_TIMESTAMP,
        UPDATED_USER_ID,
        UPDATED_TIMESTAMP,
        DELETED_USER_ID,
        DELETED_TIMESTAMP,
        IS_DELETED,
        VERSION
    )
    SELECT
        CAST(s.ID AS INT),
        CAST(s.CORPORATION_ID AS INT),
        LEFT(s.CODE, 10),
        CAST(s.CLIENT_TYPE AS NUMERIC(1, 0)),
        LEFT(s.SERIAL, 64),
        LEFT(s.DESCRIPTION, 255),
        CAST(s.REGISTER_REL_ID AS INT),
        NULL, -- SUBSCRIBER_ID (hedef-only)
        energy.dbo.FN_SAFE_DT(CAST(s.LAST_CONNECTION_TIME AS DATETIME2)),
        CAST(s.IS_READING AS INT),
        CASE WHEN s.IS_WO_WORK IS NULL THEN NULL
             WHEN s.IS_WO_WORK <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CASE WHEN s.IS_OPR_WORK IS NULL THEN NULL
             WHEN s.IS_OPR_WORK <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        LEFT(s.GSM_NUMBER, 20),
        CASE WHEN s.IS_SEND_MAIL_LOG IS NULL THEN NULL
             WHEN s.IS_SEND_MAIL_LOG <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CASE WHEN s.IS_COLLECT_LOG IS NULL THEN NULL
             WHEN s.IS_COLLECT_LOG <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        COALESCE(
            TRY_CAST(s.PRINTER_TYPE AS SMALLINT),
            CASE UPPER(LTRIM(RTRIM(s.PRINTER_TYPE)))
                WHEN N'BIXOLON'            THEN CAST(0 AS SMALLINT)
                WHEN N'INTERMEC'           THEN CAST(1 AS SMALLINT)
                WHEN N'ZEBRA'              THEN CAST(2 AS SMALLINT)
                WHEN N'SEWOO'              THEN CAST(3 AS SMALLINT)
                WHEN N'BIXOLON_CPCL'       THEN CAST(4 AS SMALLINT)
                WHEN N'IBM_PROPRINTER_II'  THEN CAST(5 AS SMALLINT)
                WHEN N'UNITECH'            THEN CAST(6 AS SMALLINT)
                WHEN N'UROVO'              THEN CAST(7 AS SMALLINT)
                WHEN N'TSC'                THEN CAST(8 AS SMALLINT)
                WHEN N'WP'                 THEN CAST(9 AS SMALLINT)
                ELSE NULL
            END
        ),
        CASE WHEN s.IS_SHOW_FIRST_INDEX IS NULL THEN NULL
             WHEN s.IS_SHOW_FIRST_INDEX <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CASE WHEN s.IS_DM_DISCOVERY IS NULL THEN NULL
             WHEN s.IS_DM_DISCOVERY <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CASE WHEN s.IS_GPS_REQUIRED IS NULL THEN NULL
             WHEN s.IS_GPS_REQUIRED <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CASE WHEN s.IS_ADDRESS_UPDATE_REQUIRED IS NULL THEN NULL
             WHEN s.IS_ADDRESS_UPDATE_REQUIRED <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CASE WHEN s.IS_ADDRESS_UPDATE IS NULL THEN NULL
             WHEN s.IS_ADDRESS_UPDATE <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        LEFT(s.BILL_SERIAL, 5),
        CAST(s.LAST_BILL_NUMBER AS NUMERIC(20, 0)),
        energy.dbo.FN_SAFE_DT(CAST(s.LAST_READING_DATE AS DATETIME2)),
        LEFT(s.MINUTE_NUMBER, 10),
        LEFT(s.MINUTE_SERIAL, 6),
        CASE WHEN s.IS_EAM IS NULL THEN CAST(0 AS BIT)
             WHEN s.IS_EAM <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        CASE WHEN s.IS_SUBSCRIBER_UPDATE IS NULL THEN CAST(0 AS BIT)
             WHEN s.IS_SUBSCRIBER_UPDATE <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        NULL, -- REVISION_LIMIT_PER_READING
        NULL, -- REVISION_LIMIT_GENERAL
        NULL, -- READING_TYPE
        NULL, -- SYNC_PERIOD
        NULL, -- SYNC_TYPE
        NULL, -- SYNC_ITEM_COUNT
        NULL, -- ALWAYS_SEND
        CASE WHEN s.IS_ACTIVE <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.CREATED_USER_ID AS INT)),
        ISNULL(
            energy.dbo.FN_SAFE_DT(CAST(s.CREATED_TIMESTAMP AS DATETIME2)),
            CAST('19000101' AS DATETIME)),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.UPDATED_USER_ID AS INT)),
        energy.dbo.FN_SAFE_DT(CAST(s.UPDATED_TIMESTAMP AS DATETIME2)),
        NULL, -- DELETED_USER_ID
        NULL, -- DELETED_TIMESTAMP
        CAST(0 AS BIT), -- IS_DELETED
        CAST(ISNULL(s.VERSION, 0) AS NUMERIC(10, 0))
    FROM izgazMGR.dbo.OPR_SYNC_CLIENT s
    WHERE s.ID BETWEEN @BatchFrom AND @BatchTo
      AND s.ID BETWEEN 1 AND 2147483647
      AND NOT EXISTS (
          SELECT 1
          FROM energy.dbo.LS_OPR_SYNC_CLIENT t
          WHERE t.ABYS_ID = CAST(s.ID AS INT)
             OR t.CODE COLLATE DATABASE_DEFAULT = s.CODE COLLATE DATABASE_DEFAULT
      );

    SET @RowCount = @@ROWCOUNT;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_OPR_SYNC_CLIENT_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_OPR_SYNC_CLIENT t
        WHERE t.ABYS_ID = @CurID
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_OPR_SYNC_CLIENT_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_OPR_SYNC_CLIENT_HARD_RESET
    @DELETE_BATCH INT = 10000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @TotalStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_OPR_SYNC_CLIENT ABYS kayitlari (batch=%d) ***', 0, 1, @DELETE_BATCH) WITH NOWAIT;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_OPR_SYNC_CLIENT
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

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS_OPR_SYNC_CLIENT
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
        @MigrationCode  VARCHAR(50)      = 'LS_OPR_SYNC_CLIENT',
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
        @RowInserted    BIT;

    EXEC dbo.SP_MIG_OPR_SYNC_CLIENT_VALIDATE_ALL @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_OPR_SYNC_CLIENT_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
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
      AND t.name = 'OPR_SYNC_CLIENT'
      AND p.index_id IN (0, 1);

    SELECT @MaxBridgeKey = MAX(s.ID)
    FROM izgazMGR.dbo.OPR_SYNC_CLIENT s
    WHERE s.ID BETWEEN 1 AND 2147483647;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'OPR_SYNC_CLIENT',
        @TargetTable    = 'LS_OPR_SYNC_CLIENT',
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
            FROM izgazMGR.dbo.OPR_SYNC_CLIENT s
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

            EXEC dbo.SP_MIG_OPR_SYNC_CLIENT_INSERT_RANGE
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
                        EXEC dbo.SP_MIG_OPR_SYNC_CLIENT_INSERT_ONE
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

                    EXEC dbo.SP_MIG_OPR_SYNC_CLIENT_INSERT_RANGE
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
    FROM energy.dbo.LS_OPR_SYNC_CLIENT
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
        WHERE l.MIGRATION_CODE = 'LS_OPR_SYNC_CLIENT'
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO

  --EXEC energy.dbo.SP_MIGRATE_LS_OPR_SYNC_CLIENT
  --     @HARD_RESET = 0, @RESUME = 1, @BATCH_SIZE = 5000, @DEBUG = 1;
