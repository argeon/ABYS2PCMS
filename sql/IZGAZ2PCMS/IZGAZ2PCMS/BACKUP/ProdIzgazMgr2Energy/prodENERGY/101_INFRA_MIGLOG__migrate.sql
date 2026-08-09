/* ============================================================
   SCRIPT_ID : INFRA_MIGLOG_PROCS
   SCRIPT_NO : 101
   FILE      : 101_INFRA_MIGLOG__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- Ortak migrasyon log yardımcı prosedürleri
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- SP_MIG_LOG_START_RUN
-- Yeni run açar veya RESUME ile mevcut RUNNING run'ı devam ettirir.
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE SP_MIG_LOG_START_RUN
    @MigrationCode   VARCHAR(50),
    @SourceDb        SYSNAME,
    @SourceTable     SYSNAME,
    @TargetTable     SYSNAME,
    @RunPhase        VARCHAR(20),
    @ExecMode        VARCHAR(20),
    @BatchSize       INT,
    @Phase           VARCHAR(20)       = 'INSERT',
    @SourceRowCount  BIGINT            = NULL,
    @MaxBridgeKey    BIGINT            = NULL,
    @Resume          BIT               = 0,
    @RunID           UNIQUEIDENTIFIER  OUTPUT,
    @TableRunID      BIGINT            OUTPUT,
    @LastBridgeKey   BIGINT            OUTPUT,
    @BatchNo         INT               OUTPUT,
    @InsertedCount   BIGINT            OUTPUT,
    @SkippedCount    BIGINT            OUTPUT,
    @ErrorCount      BIGINT            OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @LastBridgeKey  = 0;
    SET @BatchNo        = 0;
    SET @InsertedCount  = 0;
    SET @SkippedCount   = 0;
    SET @ErrorCount     = 0;
    SET @TableRunID     = NULL;

    IF @Resume = 1 AND @ExecMode <> 'HARD_RESET'
    BEGIN
        SELECT TOP 1
            @RunID          = tr.RUN_ID,
            @TableRunID     = tr.TABLE_RUN_ID,
            @LastBridgeKey  = tr.LAST_BRIDGE_KEY,
            @BatchNo        = tr.BATCH_NO,
            @InsertedCount  = tr.INSERTED_COUNT,
            @SkippedCount   = tr.SKIPPED_COUNT,
            @ErrorCount     = tr.ERROR_COUNT
        FROM energy.dbo.MIG_TABLE_RUN tr
        INNER JOIN energy.dbo.MIG_RUN r ON r.RUN_ID = tr.RUN_ID
        WHERE tr.MIGRATION_CODE = @MigrationCode
          AND tr.PHASE          = @Phase
          AND tr.STATUS         = 'RUNNING'
          AND r.STATUS          = 'RUNNING'
        ORDER BY tr.TABLE_RUN_ID DESC;

        IF @RunID IS NOT NULL
            RETURN 0;
    END

    UPDATE tr
    SET tr.STATUS      = 'SUPERSEDED',
        tr.FINISHED_AT = SYSDATETIME(),
        tr.UPDATED_AT  = SYSDATETIME()
    FROM energy.dbo.MIG_TABLE_RUN tr
    WHERE tr.MIGRATION_CODE = @MigrationCode
      AND tr.PHASE          = @Phase
      AND tr.STATUS         = 'RUNNING';

    UPDATE r
    SET r.STATUS      = 'SUPERSEDED',
        r.FINISHED_AT = SYSDATETIME()
    FROM energy.dbo.MIG_RUN r
    INNER JOIN energy.dbo.MIG_TABLE_RUN tr ON tr.RUN_ID = r.RUN_ID
    WHERE tr.MIGRATION_CODE = @MigrationCode
      AND tr.PHASE          = @Phase
      AND tr.STATUS         = 'SUPERSEDED'
      AND r.STATUS          = 'RUNNING'
      AND r.FINISHED_AT IS NULL;

    SET @RunID = NEWID();

    INSERT INTO energy.dbo.MIG_RUN (
        RUN_ID, MIGRATION_CODE, SOURCE_DB, SOURCE_TABLE, TARGET_TABLE,
        RUN_PHASE, EXEC_MODE, BATCH_SIZE, STATUS,
        SOURCE_ROW_COUNT, MAX_BRIDGE_KEY
    )
    VALUES (
        @RunID, @MigrationCode, @SourceDb, @SourceTable, @TargetTable,
        @RunPhase, @ExecMode, @BatchSize, 'RUNNING',
        @SourceRowCount, @MaxBridgeKey
    );

    INSERT INTO energy.dbo.MIG_TABLE_RUN (
        RUN_ID, MIGRATION_CODE, PHASE, STATUS,
        LAST_BRIDGE_KEY, BATCH_NO, SOURCE_ROW_COUNT
    )
    VALUES (
        @RunID, @MigrationCode, @Phase, 'RUNNING',
        @LastBridgeKey, @BatchNo, @SourceRowCount
    );

    SET @TableRunID = SCOPE_IDENTITY();
END
GO

-- ------------------------------------------------------------
-- SP_MIG_LOG_BATCH_OK
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE SP_MIG_LOG_BATCH_OK
    @RunID           UNIQUEIDENTIFIER,
    @TableRunID      BIGINT,
    @MigrationCode   VARCHAR(50),
    @Phase           VARCHAR(20),
    @BatchNo         INT,
    @BridgeFrom      BIGINT           = NULL,
    @BridgeTo        BIGINT           = NULL,
    @RowCount        INT,
    @SkippedCount    INT              = 0,
    @ElapsedMs       INT              = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE energy.dbo.MIG_TABLE_RUN
    SET BATCH_NO        = @BatchNo,
        LAST_BRIDGE_KEY = ISNULL(@BridgeTo, LAST_BRIDGE_KEY),
        INSERTED_COUNT  = INSERTED_COUNT + @RowCount,
        SKIPPED_COUNT   = SKIPPED_COUNT + @SkippedCount,
        UPDATED_AT      = SYSDATETIME()
    WHERE TABLE_RUN_ID = @TableRunID;

    UPDATE energy.dbo.MIG_RUN
    SET INSERTED_COUNT  = INSERTED_COUNT + @RowCount,
        SKIPPED_COUNT   = SKIPPED_COUNT + @SkippedCount,
        LAST_BRIDGE_KEY = ISNULL(@BridgeTo, LAST_BRIDGE_KEY)
    WHERE RUN_ID = @RunID;

    INSERT INTO energy.dbo.MIG_BATCH_LOG (
        RUN_ID, MIGRATION_CODE, PHASE, BATCH_NO,
        BRIDGE_FROM, BRIDGE_TO, STATUS, ROW_COUNT,
        CUM_INSERTED, CUM_SKIPPED, CUM_ERROR, ELAPSED_MS
    )
    SELECT
        @RunID, @MigrationCode, @Phase, @BatchNo,
        @BridgeFrom, @BridgeTo, 'OK', @RowCount,
        r.INSERTED_COUNT, r.SKIPPED_COUNT, r.ERROR_COUNT, @ElapsedMs
    FROM energy.dbo.MIG_RUN r
    WHERE r.RUN_ID = @RunID;
END
GO

-- ------------------------------------------------------------
-- SP_MIG_LOG_BATCH_ERROR
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE SP_MIG_LOG_BATCH_ERROR
    @RunID           UNIQUEIDENTIFIER,
    @TableRunID      BIGINT,
    @MigrationCode   VARCHAR(50),
    @Phase           VARCHAR(20),
    @BatchNo         INT,
    @BridgeFrom      BIGINT           = NULL,
    @BridgeTo        BIGINT           = NULL,
    @SourceID        BIGINT           = NULL,
    @IsSingleRow     BIT              = 0,
    @ErrorMsg        NVARCHAR(4000)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE energy.dbo.MIG_TABLE_RUN
    SET ERROR_COUNT = ERROR_COUNT + 1,
        UPDATED_AT  = SYSDATETIME()
    WHERE TABLE_RUN_ID = @TableRunID;

    UPDATE energy.dbo.MIG_RUN
    SET ERROR_COUNT = ERROR_COUNT + 1
    WHERE RUN_ID = @RunID;

    INSERT INTO energy.dbo.MIG_BATCH_LOG (
        RUN_ID, MIGRATION_CODE, PHASE, BATCH_NO,
        BRIDGE_FROM, BRIDGE_TO, SOURCE_ID, STATUS, ROW_COUNT,
        CUM_INSERTED, CUM_SKIPPED, CUM_ERROR, ERROR_MSG
    )
    SELECT
        @RunID, @MigrationCode,
        CASE WHEN @IsSingleRow = 1 THEN @Phase + '_SINGLE' ELSE @Phase END,
        @BatchNo, @BridgeFrom, @BridgeTo, @SourceID, 'ERROR', 0,
        r.INSERTED_COUNT, r.SKIPPED_COUNT, r.ERROR_COUNT,
        LEFT(@ErrorMsg, 4000)
    FROM energy.dbo.MIG_RUN r
    WHERE r.RUN_ID = @RunID;
END
GO

-- ------------------------------------------------------------
-- SP_MIG_LOG_FINISH_PHASE
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE SP_MIG_LOG_FINISH_PHASE
    @TableRunID      BIGINT,
    @Status          VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE energy.dbo.MIG_TABLE_RUN
    SET STATUS      = @Status,
        FINISHED_AT = SYSDATETIME(),
        UPDATED_AT  = SYSDATETIME()
    WHERE TABLE_RUN_ID = @TableRunID;
END
GO

-- ------------------------------------------------------------
-- SP_MIG_LOG_FINISH_RUN
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE SP_MIG_LOG_FINISH_RUN
    @RunID           UNIQUEIDENTIFIER,
    @Status          VARCHAR(25),
    @TargetRowCount  BIGINT           = NULL,
    @ErrorMsg        NVARCHAR(4000)   = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE energy.dbo.MIG_RUN
    SET STATUS           = @Status,
        FINISHED_AT      = SYSDATETIME(),
        TARGET_ROW_COUNT = ISNULL(@TargetRowCount, TARGET_ROW_COUNT),
        ERROR_MSG        = @ErrorMsg
    WHERE RUN_ID = @RunID;
END
GO

-- ------------------------------------------------------------
-- SP_MIG_LOG_GET_SUMMARY — operatör özeti
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE SP_MIG_LOG_GET_SUMMARY
    @MigrationCode VARCHAR(50) = NULL,
    @RunID        UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.RUN_ID,
        r.MIGRATION_CODE,
        r.SOURCE_DB + '.' + r.SOURCE_TABLE AS KAYNAK,
        r.TARGET_TABLE AS HEDEF,
        r.RUN_PHASE,
        r.EXEC_MODE,
        r.STATUS,
        r.BATCH_SIZE,
        r.SOURCE_ROW_COUNT AS TOPLAM_KAYNAK,
        r.INSERTED_COUNT   AS AKTARILAN,
        r.SKIPPED_COUNT    AS ATLANAN,
        r.ERROR_COUNT      AS HATA,
        r.TARGET_ROW_COUNT AS HEDEF_SATIR,
        r.LAST_BRIDGE_KEY,
        r.MAX_BRIDGE_KEY,
        CASE
            WHEN r.SOURCE_ROW_COUNT IS NULL OR r.SOURCE_ROW_COUNT = 0 THEN NULL
            ELSE CAST(100.0 * r.INSERTED_COUNT / r.SOURCE_ROW_COUNT AS DECIMAL(6,2))
        END AS ILERLEME_YUZDE,
        r.STARTED_AT AS BASLADI,
        r.FINISHED_AT AS BITTI,
        DATEDIFF(SECOND, r.STARTED_AT,
            ISNULL(r.FINISHED_AT, SYSDATETIME())) AS SURE_SN,
        CASE
            WHEN DATEDIFF(SECOND, r.STARTED_AT,
                 ISNULL(r.FINISHED_AT, SYSDATETIME())) > 0
            THEN CAST(
                r.INSERTED_COUNT * 1.0 /
                DATEDIFF(SECOND, r.STARTED_AT,
                    ISNULL(r.FINISHED_AT, SYSDATETIME()))
                AS DECIMAL(12,2))
            ELSE NULL
        END AS SATIR_SN,
        r.ERROR_MSG,
        r.HOST_NAME,
        r.APP_USER
    FROM energy.dbo.MIG_RUN r
    WHERE (@MigrationCode IS NULL OR r.MIGRATION_CODE = @MigrationCode)
      AND (@RunID IS NULL OR r.RUN_ID = @RunID)
    ORDER BY r.STARTED_AT DESC;
END
GO

