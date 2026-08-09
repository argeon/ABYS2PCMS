/* ============================================================
   SCRIPT_ID : MASTER_SUBSCR_COMM_PERM_MIGRATE
   SCRIPT_NO : 213
   FILE      : 213_MASTER_SUBSCR_COMM_PERM__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_CS_REGISTER_COMM_PERMISSION
-- Kaynak  : izgazMGR.dbo.CS_REGISTER_COMM_PERMISSION
-- Hedef   : energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION
-- Kaynak ID → hedef ID (IDENTITY_INSERT)
-- View    : VW_MIG_REG_COMM_PERM_SOURCE
-- Önkoşul : 211 (parent communication), 212 (setup)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_REG_COMM_PERM_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION ON;

    INSERT INTO energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION (
        ID,
        SUBSCRIBER_COMMUNICATION_ID,
        PERMISSION_SOURCE_ID,
        PERMISSION_TYPE,
        IP_ADDRESS,
        CREATED_USER_ID,
        CREATED_TIMESTAMP,
        UPDATED_USER_ID,
        UPDATED_TIMESTAMP,
        DELETED_USER_ID,
        DELETED_TIMESTAMP,
        IS_ACTIVE,
        VERSION,
        INTEGRATION_CODE,
        INTEGRATION_DATE,
        IS_INTEGRATION_PERMISSION,
        PCMS_IS_PERMISSION,
        PCMS_PERMISSION_DATE
    )
    SELECT
        s.ABYS_ID,
        s.SUBSCRIBER_COMMUNICATION_ID,
        s.PERMISSION_SOURCE_ID,
        s.PERMISSION_TYPE,
        s.IP_ADDRESS,
        s.CREATED_USER_ID,
        s.CREATED_TIMESTAMP,
        s.UPDATED_USER_ID,
        s.UPDATED_TIMESTAMP,
        s.DELETED_USER_ID,
        s.DELETED_TIMESTAMP,
        s.IS_ACTIVE,
        s.VERSION,
        s.INTEGRATION_CODE,
        s.INTEGRATION_DATE,
        s.IS_INTEGRATION_PERMISSION,
        s.PCMS_IS_PERMISSION,
        s.PCMS_PERMISSION_DATE
    FROM energy.dbo.VW_MIG_REG_COMM_PERM_SOURCE s
    WHERE s.ABYS_ID = @CurID;

    SET @RowInserted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
    SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION OFF;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_CS_REGISTER_COMM_PERMISSION
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
        @MigrationCode  VARCHAR(50)      = 'CS_REGISTER_COMM_PERMISSION',
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

    EXEC dbo.SP_MIG_REG_COMM_PERM_VALIDATE_SOURCE @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        SET @ExecMode = 'HARD_RESET';
        IF @DEBUG = 1
            RAISERROR('*** HARD RESET: LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION temizleniyor ***', 0, 1) WITH NOWAIT;

        SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION OFF;
        DELETE FROM energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION;
        DBCC CHECKIDENT('energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION', RESEED, 0) WITH NO_INFOMSGS;

        SET @RESUME = 0;
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM izgazMGR.dbo.CS_REGISTER_COMM_PERMISSION;
    SELECT @MaxBridgeKey = MAX(ID)       FROM izgazMGR.dbo.CS_REGISTER_COMM_PERMISSION;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'CS_REGISTER_COMM_PERMISSION',
        @TargetTable    = 'LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION',
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

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @BatchFrom  = @LastBridgeKey + 1;
        SET @RowCount   = 0;

        SELECT @BatchTo = MAX(ID)
        FROM (
            SELECT TOP (@BATCH_SIZE) ID
            FROM izgazMGR.dbo.CS_REGISTER_COMM_PERMISSION
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
            SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION ON;

            INSERT INTO energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION (
                ID,
                SUBSCRIBER_COMMUNICATION_ID,
                PERMISSION_SOURCE_ID,
                PERMISSION_TYPE,
                IP_ADDRESS,
                CREATED_USER_ID,
                CREATED_TIMESTAMP,
                UPDATED_USER_ID,
                UPDATED_TIMESTAMP,
                DELETED_USER_ID,
                DELETED_TIMESTAMP,
                IS_ACTIVE,
                VERSION,
                INTEGRATION_CODE,
                INTEGRATION_DATE,
                IS_INTEGRATION_PERMISSION,
                PCMS_IS_PERMISSION,
                PCMS_PERMISSION_DATE
            )
            SELECT
                s.ABYS_ID,
                s.SUBSCRIBER_COMMUNICATION_ID,
                s.PERMISSION_SOURCE_ID,
                s.PERMISSION_TYPE,
                s.IP_ADDRESS,
                s.CREATED_USER_ID,
                s.CREATED_TIMESTAMP,
                s.UPDATED_USER_ID,
                s.UPDATED_TIMESTAMP,
                s.DELETED_USER_ID,
                s.DELETED_TIMESTAMP,
                s.IS_ACTIVE,
                s.VERSION,
                s.INTEGRATION_CODE,
                s.INTEGRATION_DATE,
                s.IS_INTEGRATION_PERMISSION,
                s.PCMS_IS_PERMISSION,
                s.PCMS_PERMISSION_DATE
            FROM energy.dbo.VW_MIG_REG_COMM_PERM_SOURCE s
            WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo;

            SET @RowCount = @@ROWCOUNT;
            SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION OFF;
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
            SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION OFF;
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
                        EXEC dbo.SP_MIG_REG_COMM_PERM_INSERT_ONE
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
                    SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION ON;

                    INSERT INTO energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION (
                        ID,
                        SUBSCRIBER_COMMUNICATION_ID,
                        PERMISSION_SOURCE_ID,
                        PERMISSION_TYPE,
                        IP_ADDRESS,
                        CREATED_USER_ID,
                        CREATED_TIMESTAMP,
                        UPDATED_USER_ID,
                        UPDATED_TIMESTAMP,
                        DELETED_USER_ID,
                        DELETED_TIMESTAMP,
                        IS_ACTIVE,
                        VERSION,
                        INTEGRATION_CODE,
                        INTEGRATION_DATE,
                        IS_INTEGRATION_PERMISSION,
                        PCMS_IS_PERMISSION,
                        PCMS_PERMISSION_DATE
                    )
                    SELECT
                        s.ABYS_ID,
                        s.SUBSCRIBER_COMMUNICATION_ID,
                        s.PERMISSION_SOURCE_ID,
                        s.PERMISSION_TYPE,
                        s.IP_ADDRESS,
                        s.CREATED_USER_ID,
                        s.CREATED_TIMESTAMP,
                        s.UPDATED_USER_ID,
                        s.UPDATED_TIMESTAMP,
                        s.DELETED_USER_ID,
                        s.DELETED_TIMESTAMP,
                        s.IS_ACTIVE,
                        s.VERSION,
                        s.INTEGRATION_CODE,
                        s.INTEGRATION_DATE,
                        s.IS_INTEGRATION_PERMISSION,
                        s.PCMS_IS_PERMISSION,
                        s.PCMS_PERMISSION_DATE
                    FROM energy.dbo.VW_MIG_REG_COMM_PERM_SOURCE s
                    WHERE s.ABYS_ID BETWEEN @BisectFrom AND @BisectMid;

                    SET @BisectRows = @@ROWCOUNT;
                    SET @BisectLogFrom = @BisectFrom;
                    SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION OFF;
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
                    SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION OFF;
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
    FROM energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION;

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
-- EXEC energy.dbo.SP_MIGRATE_CS_REGISTER_COMM_PERMISSION
--      @HARD_RESET = 1, @BATCH_SIZE = 10000, @DEBUG = 1;
--
-- EXEC energy.dbo.SP_MIGRATE_CS_REGISTER_COMM_PERMISSION
--      @RESUME = 1, @DEBUG = 1;
-- ============================================================
