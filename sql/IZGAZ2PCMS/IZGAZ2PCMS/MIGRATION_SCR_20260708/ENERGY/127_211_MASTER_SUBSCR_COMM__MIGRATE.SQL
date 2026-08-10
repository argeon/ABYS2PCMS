/* ============================================================
   SCRIPT_ID : MASTER_SUBSCR_COMM_MIGRATE
   SCRIPT_NO : 211
   FILE      : 211_MASTER_SUBSCR_COMM__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_CS_REGISTER_COMMUNICATION
-- Kaynak  : izgazMGR.dbo.CS_REGISTER_COMMUNICATION
-- Hedef   : energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION
-- Kaynak ID → hedef LREF (IDENTITY_INSERT)
--
-- Kolon eşlemesi:
--   SUBSCRIBER_ID ← REGISTER_ID
--   ADDUSER       ← CREATED_USER_ID
--   ADDDATE       ← CREATED_TIMESTAMP
--   UPDUSER       ← UPDATED_USER_ID
--   UPDDATE       ← UPDATED_TIMESTAMP
-- ============================================================
USE energy;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_REG_COMM_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION ON;

    INSERT INTO energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION (
        LREF, REGISTER_TYPE, SUBSCRIBER_ID,
        COMMUNICATION_TYPE, PHONE_AREA_CODE_ID, PHONE_EXTENSION,
        COMMUNICATION_TEXT, DESCRIPTION, IS_DEFAULT,
        ADDUSER, ADDDATE, UPDUSER, UPDDATE,
        IS_ACTIVE, IS_VERIFIED, VERIFY_CODE, VERIFY_DATE,
        IS_DELETED, DELETED_TIMESTAMP, DELETED_USER_ID
    )
    SELECT
        c.ID,
        CAST(ISNULL(pt.PRIMARY_TYPE_ID, 1) AS TINYINT),
        CAST(c.REGISTER_ID AS INT),                          -- SUBSCRIBER_ID ← REGISTER_ID
        CAST(c.COMMUNICATION_TYPE AS TINYINT),
        CAST(c.PHONE_AREA_CODE_ID AS INT),
        c.PHONE_EXTENSION,
        LEFT(c.COMMUNICATION_TEXT, 500),
        LEFT(c.DESCRIPTION, 500),
        CAST(ISNULL(c.IS_DEFAULT, 0) AS BIT),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(c.CREATED_USER_ID AS INT)), -- ADDUSER ← CREATED_USER_ID + 10000
        ISNULL(
            energy.dbo.FN_SAFE_DT(CAST(c.CREATED_TIMESTAMP AS DATETIME2)),
            GETDATE()),                                        -- ADDDATE ← CREATED_TIMESTAMP
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(c.UPDATED_USER_ID AS INT)), -- UPDUSER ← UPDATED_USER_ID + 10000
        energy.dbo.FN_SAFE_DT(CAST(c.UPDATED_TIMESTAMP AS DATETIME2)), -- UPDDATE ← UPDATED_TIMESTAMP
        CAST(ISNULL(c.IS_ACTIVE, 1) AS BIT),
        CAST(ISNULL(c.IS_VERIFIED, 0) AS BIT),
        LEFT(c.VERIFY_CODE, 10),
        energy.dbo.FN_SAFE_DT(CAST(c.VERIFY_DATE AS DATETIME2)),
        CAST(0 AS BIT),
        NULL,
        NULL
    FROM izgazMGR.dbo.CS_REGISTER_COMMUNICATION c
    LEFT JOIN #RegPrimaryType pt ON pt.REGISTER_ID = c.REGISTER_ID
    WHERE c.ID = @CurID;

    SET @RowInserted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
    SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION OFF;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_CS_REGISTER_COMMUNICATION
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
        @MigrationCode  VARCHAR(50)      = 'CS_REGISTER_COMMUNICATION',
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

    EXEC dbo.SP_MIG_REG_COMM_VALIDATE_SOURCE @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        SET @ExecMode = 'HARD_RESET';
        IF @DEBUG = 1
            RAISERROR('*** HARD RESET: LS_005_SUBSCRIBER_COMMUNICATION temizleniyor ***', 0, 1) WITH NOWAIT;

        SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION OFF;
        DELETE FROM energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION;
        DBCC CHECKIDENT('energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION', RESEED, 0) WITH NO_INFOMSGS;

        SET @RESUME = 0;
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM izgazMGR.dbo.CS_REGISTER_COMMUNICATION;
    SELECT @MaxBridgeKey = MAX(ID)       FROM izgazMGR.dbo.CS_REGISTER_COMMUNICATION;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'CS_REGISTER_COMMUNICATION',
        @TargetTable    = 'LS_005_SUBSCRIBER_COMMUNICATION',
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
            + ' | ID=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    IF OBJECT_ID('tempdb..#RegPrimaryType') IS NOT NULL DROP TABLE #RegPrimaryType;
    SELECT REGISTER_ID, MIN(REGISTER_TYPE_ID) AS PRIMARY_TYPE_ID
    INTO #RegPrimaryType
    FROM izgazMGR.dbo.CS_REGISTER_REGISTER_TYPE
    GROUP BY REGISTER_ID;
    CREATE CLUSTERED INDEX CX_RegPrimaryType ON #RegPrimaryType (REGISTER_ID);

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @BatchFrom  = @LastBridgeKey + 1;
        SET @RowCount   = 0;

        SELECT @BatchTo = MAX(ID)
        FROM (
            SELECT TOP (@BATCH_SIZE) ID
            FROM izgazMGR.dbo.CS_REGISTER_COMMUNICATION
            WHERE ID > @LastBridgeKey
            ORDER BY ID ASC
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
            SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION ON;

            INSERT INTO energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION (
                LREF, REGISTER_TYPE, SUBSCRIBER_ID,
                COMMUNICATION_TYPE, PHONE_AREA_CODE_ID, PHONE_EXTENSION,
                COMMUNICATION_TEXT, DESCRIPTION, IS_DEFAULT,
                ADDUSER, ADDDATE, UPDUSER, UPDDATE,
                IS_ACTIVE, IS_VERIFIED, VERIFY_CODE, VERIFY_DATE,
                IS_DELETED, DELETED_TIMESTAMP, DELETED_USER_ID
            )
            SELECT
                c.ID,
                CAST(ISNULL(pt.PRIMARY_TYPE_ID, 1) AS TINYINT),
                CAST(c.REGISTER_ID AS INT),                          -- SUBSCRIBER_ID ← REGISTER_ID
                CAST(c.COMMUNICATION_TYPE AS TINYINT),
                CAST(c.PHONE_AREA_CODE_ID AS INT),
                c.PHONE_EXTENSION,
                LEFT(c.COMMUNICATION_TEXT, 500),
                LEFT(c.DESCRIPTION, 500),
                CAST(ISNULL(c.IS_DEFAULT, 0) AS BIT),
                energy.dbo.FN_MIG_MAP_USER_USERID(CAST(c.CREATED_USER_ID AS INT)), -- ADDUSER ← CREATED_USER_ID + 10000
                ISNULL(
                    energy.dbo.FN_SAFE_DT(CAST(c.CREATED_TIMESTAMP AS DATETIME2)),
                    GETDATE()),                                        -- ADDDATE ← CREATED_TIMESTAMP
                energy.dbo.FN_MIG_MAP_USER_USERID(CAST(c.UPDATED_USER_ID AS INT)), -- UPDUSER ← UPDATED_USER_ID + 10000
                energy.dbo.FN_SAFE_DT(CAST(c.UPDATED_TIMESTAMP AS DATETIME2)), -- UPDDATE ← UPDATED_TIMESTAMP
                CAST(ISNULL(c.IS_ACTIVE, 1) AS BIT),
                CAST(ISNULL(c.IS_VERIFIED, 0) AS BIT),
                LEFT(c.VERIFY_CODE, 10),
                energy.dbo.FN_SAFE_DT(CAST(c.VERIFY_DATE AS DATETIME2)),
                CAST(0 AS BIT),
                NULL,
                NULL
            FROM izgazMGR.dbo.CS_REGISTER_COMMUNICATION c
            LEFT JOIN #RegPrimaryType pt ON pt.REGISTER_ID = c.REGISTER_ID
            WHERE c.ID BETWEEN @BatchFrom AND @BatchTo;

            SET @RowCount = @@ROWCOUNT;
            SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION OFF;
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
            SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION OFF;
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
                        EXEC dbo.SP_MIG_REG_COMM_INSERT_ONE
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
                    SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION ON;

                    INSERT INTO energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION (
                        LREF, REGISTER_TYPE, SUBSCRIBER_ID,
                        COMMUNICATION_TYPE, PHONE_AREA_CODE_ID, PHONE_EXTENSION,
                        COMMUNICATION_TEXT, DESCRIPTION, IS_DEFAULT,
                        ADDUSER, ADDDATE, UPDUSER, UPDDATE,
                        IS_ACTIVE, IS_VERIFIED, VERIFY_CODE, VERIFY_DATE,
                        IS_DELETED, DELETED_TIMESTAMP, DELETED_USER_ID
                    )
                    SELECT
                        c.ID,
                        CAST(ISNULL(pt.PRIMARY_TYPE_ID, 1) AS TINYINT),
                        CAST(c.REGISTER_ID AS INT),                          -- SUBSCRIBER_ID ← REGISTER_ID
                        CAST(c.COMMUNICATION_TYPE AS TINYINT),
                        CAST(c.PHONE_AREA_CODE_ID AS INT),
                        c.PHONE_EXTENSION,
                        LEFT(c.COMMUNICATION_TEXT, 500),
                        LEFT(c.DESCRIPTION, 500),
                        CAST(ISNULL(c.IS_DEFAULT, 0) AS BIT),
                        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(c.CREATED_USER_ID AS INT)), -- ADDUSER ← CREATED_USER_ID + 10000
                        ISNULL(
                            energy.dbo.FN_SAFE_DT(CAST(c.CREATED_TIMESTAMP AS DATETIME2)),
                            GETDATE()),                                        -- ADDDATE ← CREATED_TIMESTAMP
                        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(c.UPDATED_USER_ID AS INT)), -- UPDUSER ← UPDATED_USER_ID + 10000
                        energy.dbo.FN_SAFE_DT(CAST(c.UPDATED_TIMESTAMP AS DATETIME2)), -- UPDDATE ← UPDATED_TIMESTAMP
                        CAST(ISNULL(c.IS_ACTIVE, 1) AS BIT),
                        CAST(ISNULL(c.IS_VERIFIED, 0) AS BIT),
                        LEFT(c.VERIFY_CODE, 10),
                        energy.dbo.FN_SAFE_DT(CAST(c.VERIFY_DATE AS DATETIME2)),
                        CAST(0 AS BIT),
                        NULL,
                        NULL
                    FROM izgazMGR.dbo.CS_REGISTER_COMMUNICATION c
                    LEFT JOIN #RegPrimaryType pt ON pt.REGISTER_ID = c.REGISTER_ID
                    WHERE c.ID BETWEEN @BisectFrom AND @BisectMid;

                    SET @BisectRows = @@ROWCOUNT;
                    SET @BisectLogFrom = @BisectFrom;
                    SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION OFF;
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
                    SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION OFF;
                    SET @ErrMsg = ERROR_MESSAGE();
                    SET @BisectTo = @BisectMid;
                END CATCH
            END -- bisect

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
                + ' LastID=' + CAST(@LastBridgeKey AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END -- WHILE

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION;

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
-- ÇALIŞTIRMA
-- ============================================================
--EXEC energy.dbo.SP_MIGRATE_CS_REGISTER_COMMUNICATION
--      @HARD_RESET = 1, @BATCH_SIZE = 10000, @DEBUG = 1;
--
-- EXEC energy.dbo.SP_MIGRATE_CS_REGISTER_COMMUNICATION
--      @RESUME = 1, @DEBUG = 1;
-- ============================================================

