/* ============================================================
   SCRIPT_ID : REF_TARIFF_MIGRATE
   SCRIPT_NO : 131
   FILE      : 131_REF_TARIFF__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS_TARIFF
-- Tek prosedür; sıra ile 4 tablo:
--   LS_TARIFF_TYPE_PRM        ← CS_TARIFF_TYPE_PRM + CS_TARIFF_TYPE_PRM_LNG
--   LS_TARIFF_PRM             ← CS_TARIFF
--   LS_TARIFF_INCOME_PRM      ← CS_TARIFF_INCOME
--   LS_TARIFF_INCOME_DISCOUNT_PRM ← CS_TARIFF_INCOME_DISCOUNT
-- ============================================================
USE energy;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_TARIFF_HARD_RESET
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_TARIFF* ABYS kayitlari ***', 0, 1) WITH NOWAIT;

    DECLARE @DeletedStr VARCHAR(20);

    DELETE FROM energy.dbo.LS_TARIFF_INCOME_DISCOUNT_PRM;
    IF @DEBUG = 1
    BEGIN
        SET @DeletedStr = CAST(@@ROWCOUNT AS VARCHAR(20));
        RAISERROR('  silindi LS_TARIFF_INCOME_DISCOUNT_PRM: %s', 0, 1, @DeletedStr) WITH NOWAIT;
    END

    DELETE FROM energy.dbo.LS_TARIFF_INCOME_PRM;
    IF @DEBUG = 1
    BEGIN
        SET @DeletedStr = CAST(@@ROWCOUNT AS VARCHAR(20));
        RAISERROR('  silindi LS_TARIFF_INCOME_PRM: %s', 0, 1, @DeletedStr) WITH NOWAIT;
    END

    DELETE FROM energy.dbo.LS_TARIFF_PRM;
    IF @DEBUG = 1
    BEGIN
        SET @DeletedStr = CAST(@@ROWCOUNT AS VARCHAR(20));
        RAISERROR('  silindi LS_TARIFF_PRM: %s', 0, 1, @DeletedStr) WITH NOWAIT;
    END

    DELETE FROM energy.dbo.LS_TARIFF_TYPE_PRM;
    IF @DEBUG = 1
    BEGIN
        SET @DeletedStr = CAST(@@ROWCOUNT AS VARCHAR(20));
        RAISERROR('  silindi LS_TARIFF_TYPE_PRM: %s', 0, 1, @DeletedStr) WITH NOWAIT;
    END

    DBCC CHECKIDENT('energy.dbo.LS_TARIFF_INCOME_DISCOUNT_PRM', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT('energy.dbo.LS_TARIFF_INCOME_PRM', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT('energy.dbo.LS_TARIFF_PRM', RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT('energy.dbo.LS_TARIFF_TYPE_PRM', RESEED, 0) WITH NO_INFOMSGS;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_TARIFF_MIGRATE_TABLE
    @MigrationCode  VARCHAR(50),
    @SourceTable    SYSNAME,
    @TargetTable    SYSNAME,
    @CompanyId      INT,
    @BatchSize      INT,
    @Resume         BIT,
    @HardReset      BIT,
    @MaxError       INT,
    @Debug          BIT,
    @InsertSql      NVARCHAR(MAX),
    @SourceCount    BIGINT,
    @MaxBridgeKey   BIGINT,
    @Stopped        BIT OUTPUT,
    @TotalErrors    BIGINT OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @RunID          UNIQUEIDENTIFIER,
        @TableRunID     BIGINT,
        @LastBridgeKey  BIGINT = 0,
        @BatchNo        INT = 0,
        @InsertedCount  BIGINT = 0,
        @SkippedCount   BIGINT = 0,
        @ErrorCount     BIGINT = 0,
        @BatchFrom      BIGINT,
        @BatchTo        BIGINT,
        @RowCount       INT,
        @ErrMsg         NVARCHAR(4000),
        @Msg            VARCHAR(500),
        @BatchStart     DATETIME2(3),
        @ElapsedMs      INT,
        @ExecMode       VARCHAR(20),
        @RunStatus      VARCHAR(25),
        @PhaseStatus    VARCHAR(20),
        @TargetCount    BIGINT,
        @FinishErrorMsg NVARCHAR(4000);

    IF @HardReset = 1
        SET @ExecMode = 'HARD_RESET';
    ELSE IF @Resume = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = @SourceTable,
        @TargetTable    = @TargetTable,
        @RunPhase       = 'INSERT',
        @ExecMode       = @ExecMode,
        @BatchSize      = @BatchSize,
        @Phase          = 'INSERT',
        @SourceRowCount = @SourceCount,
        @MaxBridgeKey   = @MaxBridgeKey,
        @Resume         = @Resume,
        @RunID          = @RunID          OUTPUT,
        @TableRunID     = @TableRunID     OUTPUT,
        @LastBridgeKey  = @LastBridgeKey  OUTPUT,
        @BatchNo        = @BatchNo        OUTPUT,
        @InsertedCount  = @InsertedCount  OUTPUT,
        @SkippedCount   = @SkippedCount   OUTPUT,
        @ErrorCount     = @ErrorCount     OUTPUT;

    IF @Debug = 1
    BEGIN
        SET @Msg = @MigrationCode + ' RUN ' + CAST(@RunID AS VARCHAR(36))
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

        SELECT @BatchTo = NULL;

        IF @MigrationCode = 'LS_TARIFF_TYPE_PRM'
        BEGIN
            SELECT @BatchTo = MAX(ABYS_ID)
            FROM (
                SELECT TOP (@BatchSize) s.ABYS_ID
                FROM energy.dbo.VW_MIG_TARIFF_TYPE_PRM_SOURCE s
                WHERE s.ABYS_ID > @LastBridgeKey
                ORDER BY s.ABYS_ID
            ) x;
        END
        ELSE IF @MigrationCode = 'LS_TARIFF_PRM'
        BEGIN
            SELECT @BatchTo = MAX(ABYS_ID)
            FROM (
                SELECT TOP (@BatchSize) s.ABYS_ID
                FROM energy.dbo.VW_MIG_TARIFF_PRM_SOURCE s
                WHERE s.ABYS_ID > @LastBridgeKey
                ORDER BY s.ABYS_ID
            ) x;
        END
        ELSE IF @MigrationCode = 'LS_TARIFF_INCOME_PRM'
        BEGIN
            SELECT @BatchTo = MAX(ABYS_ID)
            FROM (
                SELECT TOP (@BatchSize) s.ABYS_ID
                FROM energy.dbo.VW_MIG_TARIFF_INCOME_PRM_SOURCE s
                WHERE s.ABYS_ID > @LastBridgeKey
                ORDER BY s.ABYS_ID
            ) x;
        END
        ELSE IF @MigrationCode = 'LS_TARIFF_INCOME_DISCOUNT_PRM'
        BEGIN
            SELECT @BatchTo = MAX(ABYS_ID)
            FROM (
                SELECT TOP (@BatchSize) s.ABYS_ID
                FROM energy.dbo.VW_MIG_TARIFF_INCOME_DISCOUNT_PRM_SOURCE s
                WHERE s.ABYS_ID > @LastBridgeKey
                ORDER BY s.ABYS_ID
            ) x;
        END

        IF @BatchTo IS NULL BREAK;

        IF @Debug = 1
        BEGIN
            SET @Msg = '  ' + @MigrationCode + ' batch ' + CAST(@BatchNo AS VARCHAR(10))
                + ' | ABYS_ID ' + CAST(@BatchFrom AS VARCHAR(20))
                + '-' + CAST(@BatchTo AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            EXEC sp_executesql
                @InsertSql,
                N'@CompanyId INT, @BatchFrom BIGINT, @BatchTo BIGINT, @RowCount INT OUTPUT',
                @CompanyId = @CompanyId,
                @BatchFrom = @BatchFrom,
                @BatchTo = @BatchTo,
                @RowCount = @RowCount OUTPUT;

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

            SET @ErrorCount += 1;
            SET @TotalErrors += 1;

            IF @ErrorCount >= @MaxError
            BEGIN
                DECLARE @StopMsg VARCHAR(4000);
                SET @Stopped = 1;
                SET @StopMsg = CAST(@MigrationCode AS VARCHAR(100))
                    + ': max hata limiti (' + CAST(@MaxError AS VARCHAR(20)) + ') asildi.';
                RAISERROR('%s', 16, 1, @StopMsg);
            END
            ELSE
                SET @LastBridgeKey = @BatchTo;
        END CATCH
    END

    IF @MigrationCode = 'LS_TARIFF_TYPE_PRM'
        SELECT @TargetCount = COUNT_BIG(*) FROM energy.dbo.LS_TARIFF_TYPE_PRM WHERE ABYS_ID IS NOT NULL;
    ELSE IF @MigrationCode = 'LS_TARIFF_PRM'
        SELECT @TargetCount = COUNT_BIG(*) FROM energy.dbo.LS_TARIFF_PRM WHERE ABYS_ID IS NOT NULL;
    ELSE IF @MigrationCode = 'LS_TARIFF_INCOME_PRM'
        SELECT @TargetCount = COUNT_BIG(*) FROM energy.dbo.LS_TARIFF_INCOME_PRM WHERE ABYS_ID IS NOT NULL;
    ELSE
        SELECT @TargetCount = COUNT_BIG(*) FROM energy.dbo.LS_TARIFF_INCOME_DISCOUNT_PRM WHERE ABYS_ID IS NOT NULL;

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

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS_TARIFF
    @BATCH_SIZE   INT = 5000,
    @RESUME       BIT = 1,
    @HARD_RESET   BIT = 0,
    @MAX_ERROR    INT = 500,
    @COMPANY_ID   INT = 4102,
    @DEBUG        BIT = 0
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @Stopped     BIT = 0,
        @TotalErrors BIGINT = 0,
        @SourceCount BIGINT,
        @MaxBridgeKey BIGINT,
        @InsertSql   NVARCHAR(MAX),
        @ResumeFlag  BIT;

    EXEC dbo.SP_MIG_TARIFF_VALIDATE_ALL @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_TARIFF_HARD_RESET @DEBUG = @DEBUG;
        SET @RESUME = 0;
    END

    SET @ResumeFlag = @RESUME;

    -- ----------------------------------------------------------
    -- 1) LS_TARIFF_TYPE_PRM
    -- ----------------------------------------------------------
    SET @InsertSql = N'
DECLARE @InsertedRows INT;
SET IDENTITY_INSERT energy.dbo.LS_TARIFF_TYPE_PRM ON;
INSERT INTO energy.dbo.LS_TARIFF_TYPE_PRM (
    ID, ABYS_ID, COMPANY_ID, CODE, SUBSCRIBER_TYPE_ID, EXPIRY_DAY,
    YEARLY_CONSUMPTION, MIN_CONSUMPTION, MAX_CONSUMPTION,
    DISTRIBUTION_MIN_LIMIT, DISTRIBUTION_MAX_LIMIT, PARTICIPATION_FEE_MULTIPLIER,
    USE_MIN_INDEPENDENT_UNIT_CALC, TARIFF_TYPE, TARIFF_PRICE_TYPE,
    ACCOUNT_CODE, ACCOUNT_CODE_FINANCE, CASH_SALE_ACCOUNT_CODE, TARIFF_TYPE_NAME,
    COMM_ACCOUNT_CODE, COMM_FINANCE_CODE, AREA_ID, TARIFF_GROUP_TYPE, NEIGHBORHOOD_ID,
    IS_E_SUBSCRIPTION, TARIFF_TYPE_ID_FOR_ONLINE, ACTIVITY_TYPE_ID_FOR_ONLINE,
    IS_DONT_APPLY_FOR_CANCELLATION, IS_USABLE_PREPAID, IS_HAS_CPI, IS_HANDICAPPED, IS_MIN_ACCOUNT,
    CREATED_USER_ID, CREATED_TIMESTAMP, UPDATED_USER_ID, UPDATED_TIMESTAMP,
    DELETED_USER_ID, DELETED_TIMESTAMP, IS_DELETED, IS_ACTIVE, VERSION
)
SELECT
    s.ABYS_ID, s.ABYS_ID, @CompanyId, s.CODE, s.SUBSCRIBER_TYPE_ID, s.EXPIRY_DAY,
    s.YEARLY_CONSUMPTION, s.MIN_CONSUMPTION, s.MAX_CONSUMPTION,
    s.DISTRIBUTION_MIN_LIMIT, s.DISTRIBUTION_MAX_LIMIT, s.PARTICIPATION_FEE_MULTIPLIER,
    s.USE_MIN_INDEPENDENT_UNIT_CALC, s.TARIFF_TYPE, s.TARIFF_PRICE_TYPE,
    s.ACCOUNT_CODE, s.ACCOUNT_CODE_FINANCE, s.CASH_SALE_ACCOUNT_CODE, s.TARIFF_TYPE_NAME,
    s.COMM_ACCOUNT_CODE, s.COMM_FINANCE_CODE, s.AREA_ID, s.TARIFF_GROUP_TYPE, s.NEIGHBORHOOD_ID,
    s.IS_E_SUBSCRIPTION, s.TARIFF_TYPE_ID_FOR_ONLINE, s.ACTIVITY_TYPE_ID_FOR_ONLINE,
    s.IS_DONT_APPLY_FOR_CANCELLATION, s.IS_USABLE_PREPAID, s.IS_HAS_CPI, s.IS_HANDICAPPED, s.IS_MIN_ACCOUNT,
    s.CREATED_USER_ID, s.CREATED_TIMESTAMP, s.UPDATED_USER_ID, s.UPDATED_TIMESTAMP,
    s.DELETED_USER_ID, s.DELETED_TIMESTAMP, s.IS_DELETED, s.IS_ACTIVE, s.VERSION
FROM energy.dbo.VW_MIG_TARIFF_TYPE_PRM_SOURCE s
WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
  AND NOT EXISTS (
      SELECT 1 FROM energy.dbo.LS_TARIFF_TYPE_PRM t WHERE t.ABYS_ID = s.ABYS_ID
  );
SET @InsertedRows = @@ROWCOUNT;
SET IDENTITY_INSERT energy.dbo.LS_TARIFF_TYPE_PRM OFF;
SET @RowCount = @InsertedRows;';

    SELECT @SourceCount = COUNT_BIG(*) FROM energy.dbo.VW_MIG_TARIFF_TYPE_PRM_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_TARIFF_TYPE_PRM_SOURCE;

    EXEC dbo.SP_MIG_TARIFF_MIGRATE_TABLE
        @MigrationCode = 'LS_TARIFF_TYPE_PRM',
        @SourceTable = 'CS_TARIFF_TYPE_PRM+CS_TARIFF_TYPE_PRM_LNG',
        @TargetTable = 'LS_TARIFF_TYPE_PRM',
        @CompanyId = @COMPANY_ID,
        @BatchSize = @BATCH_SIZE,
        @Resume = @ResumeFlag,
        @HardReset = @HARD_RESET,
        @MaxError = @MAX_ERROR,
        @Debug = @DEBUG,
        @InsertSql = @InsertSql,
        @SourceCount = @SourceCount,
        @MaxBridgeKey = @MaxBridgeKey,
        @Stopped = @Stopped OUTPUT,
        @TotalErrors = @TotalErrors OUTPUT;

    IF @Stopped = 1 RETURN;

    -- ----------------------------------------------------------
    -- 2) LS_TARIFF_PRM
    -- ----------------------------------------------------------
    SET @InsertSql = N'
DECLARE @InsertedRows INT;
SET IDENTITY_INSERT energy.dbo.LS_TARIFF_PRM ON;
INSERT INTO energy.dbo.LS_TARIFF_PRM (
    ID, ABYS_ID, COMPANY_ID, TARIFF_TYPE_ID, BEGIN_DATE, END_DATE, IS_ACTIVE,
    CREATED_USER_ID, CREATED_TIMESTAMP, UPDATED_USER_ID, UPDATED_TIMESTAMP,
    DELETED_USER_ID, DELETED_TIMESTAMP, IS_DELETED, VERSION
)
SELECT
    s.ABYS_ID, s.ABYS_ID, @CompanyId, s.ABYS_TARIFF_TYPE_ID, s.BEGIN_DATE, s.END_DATE, s.IS_ACTIVE,
    s.CREATED_USER_ID, s.CREATED_TIMESTAMP, s.UPDATED_USER_ID, s.UPDATED_TIMESTAMP,
    s.DELETED_USER_ID, s.DELETED_TIMESTAMP, s.IS_DELETED, s.VERSION
FROM energy.dbo.VW_MIG_TARIFF_PRM_SOURCE s
WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
  AND NOT EXISTS (
      SELECT 1 FROM energy.dbo.LS_TARIFF_PRM t WHERE t.ABYS_ID = s.ABYS_ID
  );
SET @InsertedRows = @@ROWCOUNT;
SET IDENTITY_INSERT energy.dbo.LS_TARIFF_PRM OFF;
SET @RowCount = @InsertedRows;';

    SELECT @SourceCount = COUNT_BIG(*) FROM energy.dbo.VW_MIG_TARIFF_PRM_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_TARIFF_PRM_SOURCE;

    EXEC dbo.SP_MIG_TARIFF_MIGRATE_TABLE
        @MigrationCode = 'LS_TARIFF_PRM',
        @SourceTable = 'CS_TARIFF',
        @TargetTable = 'LS_TARIFF_PRM',
        @CompanyId = @COMPANY_ID,
        @BatchSize = @BATCH_SIZE,
        @Resume = @ResumeFlag,
        @HardReset = 0,
        @MaxError = @MAX_ERROR,
        @Debug = @DEBUG,
        @InsertSql = @InsertSql,
        @SourceCount = @SourceCount,
        @MaxBridgeKey = @MaxBridgeKey,
        @Stopped = @Stopped OUTPUT,
        @TotalErrors = @TotalErrors OUTPUT;

    IF @Stopped = 1 RETURN;

    -- ----------------------------------------------------------
    -- 3) LS_TARIFF_INCOME_PRM
    -- ----------------------------------------------------------
    SET @InsertSql = N'
DECLARE @InsertedRows INT;
SET IDENTITY_INSERT energy.dbo.LS_TARIFF_INCOME_PRM ON;
INSERT INTO energy.dbo.LS_TARIFF_INCOME_PRM (
    ID, ABYS_ID, COMPANY_ID, TARIFF_ID, LEVEL_NUMBER, INCOME_ID, CONSUMPTION, AMOUNT, VAT_RATE,
    CURRENCY_UNIT_ID, MUNICIPAL_ID, IS_CAL_DAY_DIFF, CONSUMPTION_PERCENT, REAL_COST,
    CREATED_USER_ID, CREATED_TIMESTAMP, UPDATED_USER_ID, UPDATED_TIMESTAMP,
    DELETED_USER_ID, DELETED_TIMESTAMP, IS_DELETED, VERSION
)
SELECT
    s.ABYS_ID, s.ABYS_ID, @CompanyId, s.ABYS_TARIFF_ID, s.LEVEL_NUMBER, s.INCOME_ID, s.CONSUMPTION, s.AMOUNT, s.VAT_RATE,
    s.CURRENCY_UNIT_ID, s.MUNICIPAL_ID, s.IS_CAL_DAY_DIFF, s.CONSUMPTION_PERCENT, s.REAL_COST,
    s.CREATED_USER_ID, s.CREATED_TIMESTAMP, s.UPDATED_USER_ID, s.UPDATED_TIMESTAMP,
    s.DELETED_USER_ID, s.DELETED_TIMESTAMP, s.IS_DELETED, s.VERSION
FROM energy.dbo.VW_MIG_TARIFF_INCOME_PRM_SOURCE s
WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
  AND NOT EXISTS (
      SELECT 1 FROM energy.dbo.LS_TARIFF_INCOME_PRM t WHERE t.ABYS_ID = s.ABYS_ID
  );
SET @InsertedRows = @@ROWCOUNT;
SET IDENTITY_INSERT energy.dbo.LS_TARIFF_INCOME_PRM OFF;
SET @RowCount = @InsertedRows;';

    SELECT @SourceCount = COUNT_BIG(*) FROM energy.dbo.VW_MIG_TARIFF_INCOME_PRM_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_TARIFF_INCOME_PRM_SOURCE;

    EXEC dbo.SP_MIG_TARIFF_MIGRATE_TABLE
        @MigrationCode = 'LS_TARIFF_INCOME_PRM',
        @SourceTable = 'CS_TARIFF_INCOME',
        @TargetTable = 'LS_TARIFF_INCOME_PRM',
        @CompanyId = @COMPANY_ID,
        @BatchSize = @BATCH_SIZE,
        @Resume = @ResumeFlag,
        @HardReset = 0,
        @MaxError = @MAX_ERROR,
        @Debug = @DEBUG,
        @InsertSql = @InsertSql,
        @SourceCount = @SourceCount,
        @MaxBridgeKey = @MaxBridgeKey,
        @Stopped = @Stopped OUTPUT,
        @TotalErrors = @TotalErrors OUTPUT;

    IF @Stopped = 1 RETURN;

    -- ----------------------------------------------------------
    -- 4) LS_TARIFF_INCOME_DISCOUNT_PRM
    -- ----------------------------------------------------------
    SET @InsertSql = N'
DECLARE @InsertedRows INT;
SET IDENTITY_INSERT energy.dbo.LS_TARIFF_INCOME_DISCOUNT_PRM ON;
INSERT INTO energy.dbo.LS_TARIFF_INCOME_DISCOUNT_PRM (
    ID, ABYS_ID, COMPANY_ID, TARIFF_ID, INCOME_ID, DISCOUNT_RATE, DISCOUNT_M3,
    CREATED_USER_ID, CREATED_TIMESTAMP, UPDATED_USER_ID, UPDATED_TIMESTAMP,
    DELETED_USER_ID, DELETED_TIMESTAMP, IS_DELETED, VERSION
)
SELECT
    s.ABYS_ID, s.ABYS_ID, @CompanyId, s.ABYS_TARIFF_ID, s.INCOME_ID, s.DISCOUNT_RATE, ISNULL(s.DISCOUNT_M3, 0),
    s.CREATED_USER_ID, s.CREATED_TIMESTAMP, s.UPDATED_USER_ID, s.UPDATED_TIMESTAMP,
    s.DELETED_USER_ID, s.DELETED_TIMESTAMP, s.IS_DELETED, s.VERSION
FROM energy.dbo.VW_MIG_TARIFF_INCOME_DISCOUNT_PRM_SOURCE s
WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
  AND NOT EXISTS (
      SELECT 1 FROM energy.dbo.LS_TARIFF_INCOME_DISCOUNT_PRM t WHERE t.ABYS_ID = s.ABYS_ID
  );
SET @InsertedRows = @@ROWCOUNT;
SET IDENTITY_INSERT energy.dbo.LS_TARIFF_INCOME_DISCOUNT_PRM OFF;
SET @RowCount = @InsertedRows;';

    SELECT @SourceCount = COUNT_BIG(*) FROM energy.dbo.VW_MIG_TARIFF_INCOME_DISCOUNT_PRM_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_TARIFF_INCOME_DISCOUNT_PRM_SOURCE;

    EXEC dbo.SP_MIG_TARIFF_MIGRATE_TABLE
        @MigrationCode = 'LS_TARIFF_INCOME_DISCOUNT_PRM',
        @SourceTable = 'CS_TARIFF_INCOME_DISCOUNT',
        @TargetTable = 'LS_TARIFF_INCOME_DISCOUNT_PRM',
        @CompanyId = @COMPANY_ID,
        @BatchSize = @BATCH_SIZE,
        @Resume = @ResumeFlag,
        @HardReset = 0,
        @MaxError = @MAX_ERROR,
        @Debug = @DEBUG,
        @InsertSql = @InsertSql,
        @SourceCount = @SourceCount,
        @MaxBridgeKey = @MaxBridgeKey,
        @Stopped = @Stopped OUTPUT,
        @TotalErrors = @TotalErrors OUTPUT;

    IF @DEBUG = 1
    BEGIN
        DECLARE @DoneMsg VARCHAR(100);
        SET @DoneMsg = 'SP_MIGRATE_LS_TARIFF tamamlandi. Toplam hata: ' + CAST(@TotalErrors AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @DoneMsg) WITH NOWAIT;
    END

    IF @TotalErrors > 0
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
        WHERE l.MIGRATION_CODE IN (
            'LS_TARIFF_TYPE_PRM',
            'LS_TARIFF_PRM',
            'LS_TARIFF_INCOME_PRM',
            'LS_TARIFF_INCOME_DISCOUNT_PRM'
        )
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO

 --EXEC energy.dbo.SP_MIGRATE_LS_TARIFF
 --     @HARD_RESET = 1, @COMPANY_ID = 4102, @BATCH_SIZE = 5000, @DEBUG = 1;

