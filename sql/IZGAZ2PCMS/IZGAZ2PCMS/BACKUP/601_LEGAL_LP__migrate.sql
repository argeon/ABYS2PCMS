/* ============================================================
   SCRIPT_ID : LEGAL_LP_MIGRATE
   SCRIPT_NO : 601
   FILE      : 601_LEGAL_LP__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LP
-- Sıra:
--   1 LP_EXPENSE_CAUSE_PRM  ← LP_EXPENSE_CAUSE_PRM + LNG
--   2 LP_LEGAL_PROCEEDING
--   3 LP_STATUS
--   4 LP_INVOICE            ← LP_ACCOUNT
--   5 LP_INCOME
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_LP_HARD_RESET
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LP* ABYS + cakisan ID kayitlari ***', 0, 1) WITH NOWAIT;

    DECLARE @DeletedStr VARCHAR(20);

    DELETE t
    FROM energy.dbo.LP_INCOME t
    WHERE t.ABYS_ID IS NOT NULL
       OR EXISTS (SELECT 1 FROM izgazMGR.dbo.LP_INCOME s WHERE s.ID = t.ID);
    IF @DEBUG = 1 BEGIN SET @DeletedStr = CAST(@@ROWCOUNT AS VARCHAR(20)); RAISERROR('  silindi LP_INCOME: %s', 0, 1, @DeletedStr) WITH NOWAIT; END

    DELETE t
    FROM energy.dbo.LP_INVOICE t
    WHERE t.ABYS_ID IS NOT NULL
       OR EXISTS (SELECT 1 FROM izgazMGR.dbo.LP_ACCOUNT s WHERE s.ID = t.ID);
    IF @DEBUG = 1 BEGIN SET @DeletedStr = CAST(@@ROWCOUNT AS VARCHAR(20)); RAISERROR('  silindi LP_INVOICE: %s', 0, 1, @DeletedStr) WITH NOWAIT; END

    DELETE t
    FROM energy.dbo.LP_STATUS t
    WHERE t.ABYS_ID IS NOT NULL
       OR EXISTS (SELECT 1 FROM izgazMGR.dbo.LP_STATUS s WHERE s.ID = t.ID);
    IF @DEBUG = 1 BEGIN SET @DeletedStr = CAST(@@ROWCOUNT AS VARCHAR(20)); RAISERROR('  silindi LP_STATUS: %s', 0, 1, @DeletedStr) WITH NOWAIT; END

    DELETE t
    FROM energy.dbo.LP_LEGAL_PROCEEDING t
    WHERE t.ABYS_ID IS NOT NULL
       OR EXISTS (SELECT 1 FROM izgazMGR.dbo.LP_LEGAL_PROCEEDING s WHERE s.ID = t.ID);
    IF @DEBUG = 1 BEGIN SET @DeletedStr = CAST(@@ROWCOUNT AS VARCHAR(20)); RAISERROR('  silindi LP_LEGAL_PROCEEDING: %s', 0, 1, @DeletedStr) WITH NOWAIT; END

    DELETE t
    FROM energy.dbo.LP_EXPENSE_CAUSE_PRM t
    WHERE t.ABYS_ID IS NOT NULL
       OR EXISTS (SELECT 1 FROM izgazMGR.dbo.LP_EXPENSE_CAUSE_PRM s WHERE s.ID = t.ID);
    IF @DEBUG = 1 BEGIN SET @DeletedStr = CAST(@@ROWCOUNT AS VARCHAR(20)); RAISERROR('  silindi LP_EXPENSE_CAUSE_PRM: %s', 0, 1, @DeletedStr) WITH NOWAIT; END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_LP_MIGRATE_TABLE
    @MigrationCode  VARCHAR(50),
    @SourceTable    SYSNAME,
    @TargetTable    SYSNAME,
    @RegionId       INT,
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
        @FinishErrorMsg NVARCHAR(4000),
        @SourceView     SYSNAME;

    SET @SourceView = CASE @MigrationCode
        WHEN 'LP_EXPENSE_CAUSE_PRM' THEN 'VW_MIG_LP_EXPENSE_CAUSE_PRM_SOURCE'
        WHEN 'LP_LEGAL_PROCEEDING'  THEN 'VW_MIG_LP_LEGAL_PROCEEDING_SOURCE'
        WHEN 'LP_STATUS'            THEN 'VW_MIG_LP_STATUS_SOURCE'
        WHEN 'LP_INVOICE'           THEN 'VW_MIG_LP_INVOICE_SOURCE'
        WHEN 'LP_INCOME'            THEN 'VW_MIG_LP_INCOME_SOURCE'
    END;

    IF @HardReset = 1 SET @ExecMode = 'HARD_RESET';
    ELSE IF @Resume = 1 SET @ExecMode = 'RESUME';
    ELSE SET @ExecMode = 'FULL';

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
        SET @BatchTo    = NULL;

        DECLARE @BatchSql NVARCHAR(MAX) = N'
            SELECT @BatchToOut = MAX(ABYS_ID)
            FROM (
                SELECT TOP (@BatchSizeIn) s.ABYS_ID
                FROM energy.dbo.' + QUOTENAME(@SourceView) + N' s
                WHERE s.ABYS_ID > @LastKeyIn
                ORDER BY s.ABYS_ID
            ) x;';

        EXEC sp_executesql
            @BatchSql,
            N'@BatchSizeIn INT, @LastKeyIn BIGINT, @BatchToOut BIGINT OUTPUT',
            @BatchSizeIn = @BatchSize, @LastKeyIn = @LastBridgeKey, @BatchToOut = @BatchTo OUTPUT;

        IF @BatchTo IS NULL BREAK;

        IF @Debug = 1
        BEGIN
            SET @Msg = '  ' + @MigrationCode + ' batch ' + CAST(@BatchNo AS VARCHAR(10))
                + ' | ABYS_ID ' + CAST(@BatchFrom AS VARCHAR(20)) + '-' + CAST(@BatchTo AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            EXEC sp_executesql
                @InsertSql,
                N'@RegionId INT, @BatchFrom BIGINT, @BatchTo BIGINT, @RowCount INT OUTPUT',
                @RegionId = @RegionId,
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
                SET @Stopped = 1;
                RAISERROR('%s: max hata limiti (%d) asildi.', 16, 1, @MigrationCode, @MaxError);
            END
            ELSE
                SET @LastBridgeKey = @BatchTo;
        END CATCH
    END

    DECLARE @CountSql NVARCHAR(500) = N'
        SELECT @CntOut = COUNT_BIG(*) FROM energy.dbo.' + QUOTENAME(@TargetTable) + N' WHERE ABYS_ID IS NOT NULL;';
    EXEC sp_executesql @CountSql, N'@CntOut BIGINT OUTPUT', @CntOut = @TargetCount OUTPUT;

    IF @Stopped = 1 BEGIN SET @RunStatus = 'STOPPED'; SET @PhaseStatus = 'PAUSED'; END
    ELSE IF @ErrorCount > 0 BEGIN SET @RunStatus = 'COMPLETED_WITH_ERRORS'; SET @PhaseStatus = 'COMPLETED'; END
    ELSE BEGIN SET @RunStatus = 'COMPLETED'; SET @PhaseStatus = 'COMPLETED'; END

    EXEC energy.dbo.SP_MIG_LOG_FINISH_PHASE @TableRunID = @TableRunID, @Status = @PhaseStatus;

    SET @FinishErrorMsg = CASE WHEN @Stopped = 1 THEN N'Max hata limitine ulasildi. RESUME ile devam edin.' ELSE NULL END;

    EXEC energy.dbo.SP_MIG_LOG_FINISH_RUN
        @RunID = @RunID, @Status = @RunStatus,
        @TargetRowCount = @TargetCount, @ErrorMsg = @FinishErrorMsg;

    EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY @MigrationCode = @MigrationCode, @RunID = @RunID;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LP
    @BATCH_SIZE   INT = 5000,
    @RESUME       BIT = 1,
    @HARD_RESET   BIT = 0,
    @MAX_ERROR    INT = 500,
    @REGION_ID    INT = 4102,
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

    EXEC dbo.SP_MIG_LP_VALIDATE_ALL @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_LP_HARD_RESET @DEBUG = @DEBUG;
        SET @RESUME = 0;
    END

    SET @ResumeFlag = @RESUME;

    -- 1) LP_EXPENSE_CAUSE_PRM
    SET @InsertSql = N'
DECLARE @InsertedRows INT;
SET IDENTITY_INSERT energy.dbo.LP_EXPENSE_CAUSE_PRM ON;
INSERT INTO energy.dbo.LP_EXPENSE_CAUSE_PRM (
    ID, ABYS_ID, CODE, INCOME_ID, VALUE, EXPENSE_TYPE, IS_ACTIVE, IS_LISTED,
    CREATED_USER_ID, CREATED_TIMESTAMP, UPDATED_USER_ID, UPDATED_TIMESTAMP,
    ABYS_CORPORATION_ID, ABYS_MAIL_ID, ABYS_LIEN_TYPE_ID, ABYS_VERSION, ABYS_CODE_RAW
)
SELECT
    s.ABYS_ID, s.ABYS_ID, s.CODE, s.INCOME_ID, s.VALUE, s.EXPENSE_TYPE, s.IS_ACTIVE, s.IS_LISTED,
    s.CREATED_USER_ID, s.CREATED_TIMESTAMP, s.UPDATED_USER_ID, s.UPDATED_TIMESTAMP,
    s.ABYS_CORPORATION_ID, s.ABYS_MAIL_ID, s.ABYS_LIEN_TYPE_ID, s.ABYS_VERSION, s.ABYS_CODE_RAW
FROM energy.dbo.VW_MIG_LP_EXPENSE_CAUSE_PRM_SOURCE s
WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
  AND NOT EXISTS (SELECT 1 FROM energy.dbo.LP_EXPENSE_CAUSE_PRM t WHERE t.ABYS_ID = s.ABYS_ID);
SET @InsertedRows = @@ROWCOUNT;
SET IDENTITY_INSERT energy.dbo.LP_EXPENSE_CAUSE_PRM OFF;
SET @RowCount = @InsertedRows;';

    SELECT @SourceCount = COUNT_BIG(*) FROM energy.dbo.VW_MIG_LP_EXPENSE_CAUSE_PRM_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_LP_EXPENSE_CAUSE_PRM_SOURCE;

    EXEC dbo.SP_MIG_LP_MIGRATE_TABLE
        @MigrationCode = 'LP_EXPENSE_CAUSE_PRM', @SourceTable = 'LP_EXPENSE_CAUSE_PRM+LP_EXPENSE_CAUSE_PRM_LNG',
        @TargetTable = 'LP_EXPENSE_CAUSE_PRM', @RegionId = @REGION_ID, @BatchSize = @BATCH_SIZE,
        @Resume = @ResumeFlag, @HardReset = @HARD_RESET, @MaxError = @MAX_ERROR, @Debug = @DEBUG,
        @InsertSql = @InsertSql, @SourceCount = @SourceCount, @MaxBridgeKey = @MaxBridgeKey,
        @Stopped = @Stopped OUTPUT, @TotalErrors = @TotalErrors OUTPUT;
    IF @Stopped = 1 RETURN;

    -- 2) LP_LEGAL_PROCEEDING
    SET @InsertSql = N'
DECLARE @InsertedRows INT;
SET IDENTITY_INSERT energy.dbo.LP_LEGAL_PROCEEDING ON;
INSERT INTO energy.dbo.LP_LEGAL_PROCEEDING (
    ID, ABYS_ID, REGION, CODE, EXECUTIVE_BRANCH_ID, AGREEMENT_ID, INSTALLATION_ID, REGISTER_ID,
    PRE_PROCEEDING_DATE, LEGAL_PROCEEDING_DATE, NOTIFICATION_DATE, NOTIFICATION_RECIPIENT,
    LAST_PAYMENT_DATE, ENFORCEMENT_OFFICE_ID, DEBTOR_ATTORNEY_REG_ID,
    LAW_TRANSACTION_DATE, LAW_DOC_DATE, LAW_DOC_NUMBER, RECORD_NUMBER, CASE_NUMBER,
    DESCRIPTION, SENTENCE_DESCRIPTION, STATUS, DEBT, OVERDUE, OVERDUE_VAT,
    STANDART_EXPENSES, LEGAL_PROCEEDING_AMOUNT, CHARGE_RATE_ID,
    CANCELLATION_DATE, CANCELLATION_USER_ID, CANCELLATION_CAUSE_ID, CANCELLATION_DESCRIPTION,
    CREATED_USER_ID, CREATED_TIMESTAMP, UPDATED_USER_ID, UPDATED_TIMESTAMP,
    APPEAL_DATE, LAW_ISSUE_ID, CONFIRMATION_NUMBER, OLD_LAST_PAYMENT_DATE, IS_ACTIVE,
    ABYS_CORPORATION_ID, ABYS_TYPE, ABYS_CTV_OVERDUE, ABYS_CTV_OVERDUE_VAT,
    ABYS_POOL_ID, ABYS_POOL_DEBT, ABYS_POOL_DEBT_COUNT, ABYS_DISTRICT_ID,
    ABYS_MTS_NUMBER, ABYS_JAIL_CHARGE_AMOUNT, ABYS_VERSION, ABYS_INSTALLATION_ID
)
SELECT
    s.ABYS_ID, s.ABYS_ID, @RegionId, s.CODE, s.EXECUTIVE_BRANCH_ID, s.AGREEMENT_ID, s.INSTALLATION_ID, s.REGISTER_ID,
    s.PRE_PROCEEDING_DATE, s.LEGAL_PROCEEDING_DATE, s.NOTIFICATION_DATE, s.NOTIFICATION_RECIPIENT,
    s.LAST_PAYMENT_DATE, s.ENFORCEMENT_OFFICE_ID, s.DEBTOR_ATTORNEY_REG_ID,
    s.LAW_TRANSACTION_DATE, s.LAW_DOC_DATE, s.LAW_DOC_NUMBER, s.RECORD_NUMBER, s.CASE_NUMBER,
    s.DESCRIPTION, s.SENTENCE_DESCRIPTION, s.STATUS, s.DEBT, s.OVERDUE, s.OVERDUE_VAT,
    s.STANDART_EXPENSES, s.LEGAL_PROCEEDING_AMOUNT, s.CHARGE_RATE_ID,
    s.CANCELLATION_DATE, s.CANCELLATION_USER_ID, s.CANCELLATION_CAUSE_ID, s.CANCELLATION_DESCRIPTION,
    s.CREATED_USER_ID, s.CREATED_TIMESTAMP, s.UPDATED_USER_ID, s.UPDATED_TIMESTAMP,
    s.APPEAL_DATE, s.LAW_ISSUE_ID, s.CONFIRMATION_NUMBER, s.OLD_LAST_PAYMENT_DATE, s.IS_ACTIVE,
    s.ABYS_CORPORATION_ID, s.ABYS_TYPE, s.ABYS_CTV_OVERDUE, s.ABYS_CTV_OVERDUE_VAT,
    s.ABYS_POOL_ID, s.ABYS_POOL_DEBT, s.ABYS_POOL_DEBT_COUNT, s.ABYS_DISTRICT_ID,
    s.ABYS_MTS_NUMBER, s.ABYS_JAIL_CHARGE_AMOUNT, s.ABYS_VERSION, s.ABYS_INSTALLATION_ID
FROM energy.dbo.VW_MIG_LP_LEGAL_PROCEEDING_SOURCE s
WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
  AND NOT EXISTS (SELECT 1 FROM energy.dbo.LP_LEGAL_PROCEEDING t WHERE t.ABYS_ID = s.ABYS_ID);
SET @InsertedRows = @@ROWCOUNT;
SET IDENTITY_INSERT energy.dbo.LP_LEGAL_PROCEEDING OFF;
SET @RowCount = @InsertedRows;';

    SELECT @SourceCount = COUNT_BIG(*) FROM energy.dbo.VW_MIG_LP_LEGAL_PROCEEDING_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_LP_LEGAL_PROCEEDING_SOURCE;

    EXEC dbo.SP_MIG_LP_MIGRATE_TABLE
        @MigrationCode = 'LP_LEGAL_PROCEEDING', @SourceTable = 'LP_LEGAL_PROCEEDING',
        @TargetTable = 'LP_LEGAL_PROCEEDING', @RegionId = @REGION_ID, @BatchSize = @BATCH_SIZE,
        @Resume = @ResumeFlag, @HardReset = 0, @MaxError = @MAX_ERROR, @Debug = @DEBUG,
        @InsertSql = @InsertSql, @SourceCount = @SourceCount, @MaxBridgeKey = @MaxBridgeKey,
        @Stopped = @Stopped OUTPUT, @TotalErrors = @TotalErrors OUTPUT;
    IF @Stopped = 1 RETURN;

    -- 3) LP_STATUS
    SET @InsertSql = N'
DECLARE @InsertedRows INT;
SET IDENTITY_INSERT energy.dbo.LP_STATUS ON;
INSERT INTO energy.dbo.LP_STATUS (
    ID, ABYS_ID, LEGAL_PROCEEDING_ID, STATUS, STATUS_DATE, DESCRIPTION,
    ABYS_VERSION, ABYS_CREATED_USER_ID, ABYS_CREATED_TIMESTAMP,
    ABYS_UPDATED_USER_ID, ABYS_UPDATED_TIMESTAMP
)
SELECT
    s.ABYS_ID, s.ABYS_ID, s.LEGAL_PROCEEDING_ID, s.STATUS, s.STATUS_DATE, s.DESCRIPTION,
    s.ABYS_VERSION, s.ABYS_CREATED_USER_ID, s.ABYS_CREATED_TIMESTAMP,
    s.ABYS_UPDATED_USER_ID, s.ABYS_UPDATED_TIMESTAMP
FROM energy.dbo.VW_MIG_LP_STATUS_SOURCE s
WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
  AND NOT EXISTS (SELECT 1 FROM energy.dbo.LP_STATUS t WHERE t.ABYS_ID = s.ABYS_ID);
SET @InsertedRows = @@ROWCOUNT;
SET IDENTITY_INSERT energy.dbo.LP_STATUS OFF;
SET @RowCount = @InsertedRows;';

    SELECT @SourceCount = COUNT_BIG(*) FROM energy.dbo.VW_MIG_LP_STATUS_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_LP_STATUS_SOURCE;

    EXEC dbo.SP_MIG_LP_MIGRATE_TABLE
        @MigrationCode = 'LP_STATUS', @SourceTable = 'LP_STATUS',
        @TargetTable = 'LP_STATUS', @RegionId = @REGION_ID, @BatchSize = @BATCH_SIZE,
        @Resume = @ResumeFlag, @HardReset = 0, @MaxError = @MAX_ERROR, @Debug = @DEBUG,
        @InsertSql = @InsertSql, @SourceCount = @SourceCount, @MaxBridgeKey = @MaxBridgeKey,
        @Stopped = @Stopped OUTPUT, @TotalErrors = @TotalErrors OUTPUT;
    IF @Stopped = 1 RETURN;

    -- 4) LP_INVOICE ← LP_ACCOUNT
    SET @InsertSql = N'
DECLARE @InsertedRows INT;
SET IDENTITY_INSERT energy.dbo.LP_INVOICE ON;
INSERT INTO energy.dbo.LP_INVOICE (
    ID, ABYS_ID, REGION, LEGAL_PROCEEDING_ID, INVOICE_ID,
    AMOUNT, OVERDUE, OVERDUE_VAT, COMMISSION_DELAY_TYPE_ID, DEBT_GROUP_ID,
    EXPIRY_DATE, DUE_INSTALLMENT_ID,
    CREATED_USER_ID, CREATED_TIMESTAMP, UPDATED_USER_ID, UPDATED_TIMESTAMP,
    IS_ACTIVE, ORDER_NUMBER, DESCRIPTION,
    ABYS_VERSION, ABYS_ACCOUNT_ID
)
SELECT
    s.ABYS_ID, s.ABYS_ID, @RegionId, s.LEGAL_PROCEEDING_ID, s.INVOICE_ID,
    s.AMOUNT, s.OVERDUE, s.OVERDUE_VAT, s.COMMISSION_DELAY_TYPE_ID, s.DEBT_GROUP_ID,
    s.EXPIRY_DATE, s.DUE_INSTALLMENT_ID,
    s.CREATED_USER_ID, s.CREATED_TIMESTAMP, s.UPDATED_USER_ID, s.UPDATED_TIMESTAMP,
    s.IS_ACTIVE, s.ORDER_NUMBER, s.DESCRIPTION,
    s.ABYS_VERSION, s.ABYS_ACCOUNT_ID
FROM energy.dbo.VW_MIG_LP_INVOICE_SOURCE s
WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
  AND NOT EXISTS (SELECT 1 FROM energy.dbo.LP_INVOICE t WHERE t.ABYS_ID = s.ABYS_ID);
SET @InsertedRows = @@ROWCOUNT;
SET IDENTITY_INSERT energy.dbo.LP_INVOICE OFF;
SET @RowCount = @InsertedRows;';

    SELECT @SourceCount = COUNT_BIG(*) FROM energy.dbo.VW_MIG_LP_INVOICE_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_LP_INVOICE_SOURCE;

    EXEC dbo.SP_MIG_LP_MIGRATE_TABLE
        @MigrationCode = 'LP_INVOICE', @SourceTable = 'LP_ACCOUNT',
        @TargetTable = 'LP_INVOICE', @RegionId = @REGION_ID, @BatchSize = @BATCH_SIZE,
        @Resume = @ResumeFlag, @HardReset = 0, @MaxError = @MAX_ERROR, @Debug = @DEBUG,
        @InsertSql = @InsertSql, @SourceCount = @SourceCount, @MaxBridgeKey = @MaxBridgeKey,
        @Stopped = @Stopped OUTPUT, @TotalErrors = @TotalErrors OUTPUT;
    IF @Stopped = 1 RETURN;

    -- 5) LP_INCOME
    SET @InsertSql = N'
DECLARE @InsertedRows INT;
SET IDENTITY_INSERT energy.dbo.LP_INCOME ON;
INSERT INTO energy.dbo.LP_INCOME (
    ID, ABYS_ID, LEGAL_PROCEEDING_ID, EXPENSE_CAUSE_ID, AMOUNT, INVOICE_ID,
    STATUS, DESCRIPTION, CREATED_USER_ID, CREATED_TIMESTAMP,
    UPDATED_USER_ID, UPDATED_TIMESTAMP, IS_ACTIVE,
    ACTION_DATE, SEND_PAYED_DATE, SEND_PAYED_USER_ID,
    ABYS_VERSION, ABYS_ACCOUNT_ID
)
SELECT
    s.ABYS_ID, s.ABYS_ID, s.LEGAL_PROCEEDING_ID, s.EXPENSE_CAUSE_ID, s.AMOUNT, s.INVOICE_ID,
    s.STATUS, s.DESCRIPTION, s.CREATED_USER_ID, s.CREATED_TIMESTAMP,
    s.UPDATED_USER_ID, s.UPDATED_TIMESTAMP, s.IS_ACTIVE,
    s.ACTION_DATE, s.SEND_PAYED_DATE, s.SEND_PAYED_USER_ID,
    s.ABYS_VERSION, s.ABYS_ACCOUNT_ID
FROM energy.dbo.VW_MIG_LP_INCOME_SOURCE s
WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
  AND NOT EXISTS (SELECT 1 FROM energy.dbo.LP_INCOME t WHERE t.ABYS_ID = s.ABYS_ID);
SET @InsertedRows = @@ROWCOUNT;
SET IDENTITY_INSERT energy.dbo.LP_INCOME OFF;
SET @RowCount = @InsertedRows;';

    SELECT @SourceCount = COUNT_BIG(*) FROM energy.dbo.VW_MIG_LP_INCOME_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_LP_INCOME_SOURCE;

    EXEC dbo.SP_MIG_LP_MIGRATE_TABLE
        @MigrationCode = 'LP_INCOME', @SourceTable = 'LP_INCOME',
        @TargetTable = 'LP_INCOME', @RegionId = @REGION_ID, @BatchSize = @BATCH_SIZE,
        @Resume = @ResumeFlag, @HardReset = 0, @MaxError = @MAX_ERROR, @Debug = @DEBUG,
        @InsertSql = @InsertSql, @SourceCount = @SourceCount, @MaxBridgeKey = @MaxBridgeKey,
        @Stopped = @Stopped OUTPUT, @TotalErrors = @TotalErrors OUTPUT;

    IF @DEBUG = 1
    BEGIN
        -- RAISERROR %d only accepts INT; @TotalErrors is BIGINT
        DECLARE @DoneMsg VARCHAR(200) =
            'SP_MIGRATE_LP tamamlandi. Toplam hata: ' + CAST(@TotalErrors AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @DoneMsg) WITH NOWAIT;
    END

    IF @TotalErrors > 0
    BEGIN
        SELECT TOP 10 l.MIGRATION_CODE, l.BATCH_NO, l.BRIDGE_FROM, l.BRIDGE_TO, l.ERROR_MSG, l.LOGGED_AT
        FROM energy.dbo.MIG_BATCH_LOG l
        WHERE l.MIGRATION_CODE IN ('LP_EXPENSE_CAUSE_PRM','LP_LEGAL_PROCEEDING','LP_STATUS','LP_INVOICE','LP_INCOME')
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO

   --EXEC energy.dbo.SP_MIGRATE_LP @HARD_RESET = 1, @REGION_ID = 4102, @BATCH_SIZE = 50000, @DEBUG = 1;
 



 
 