/* ============================================================
   SCRIPT_ID : INSTALLMENT_PLAN_MIGRATE
   SCRIPT_NO : 611
   FILE      : 611_INSTALLMENT_PLAN__migrate.sql
   VERSION   : 3
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_INSTALLMENT_PLAN
-- Kaynak  : izgazMGR.dbo.CS_INSTALLMENT_PLAN
--           + izgazMGR.dbo.CS_INSTALLMENT (parent)
-- Hedef   : energy.dbo.LS_005_01_INSTALLMENT_PLAN
-- LREF    : IDENTITY (yeni)
-- ABYS_ID : CS_INSTALLMENT_PLAN.ID
-- PLAN_ID : CS_INSTALLMENT.ID (grup anahtari)
--
-- TOTAL_AMOUNT = AMOUNT + ISNULL(LATE_CHARGE,0) + ISNULL(OVERDUE,0)
-- ISACTIVE     = 1 yalniz iptal yok (CANCEL_CAUSE/DATE/USER) AND INS.DUE_DATE IS NULL
-- PAYTRANS_REF = NULL (Pass 1; taksit borc PT ayri adim)
-- INVOICE_REF / INVOICE_OLD_DUEDATE = NULL (Pass 1)
--   → sonra SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE
--
-- v3: ABYS_CANCELLATION_USER_ID + ISACTIVE uc iptal alani
-- v2: invoice OUTER APPLY kaldirildi (73M scan); tarih/user inline
-- @AGR_ID : pilot filtre (CS_INSTALLMENT.AGREEMENT_ID)
-- User    : ABYS + 10000 (inline)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_PLAN_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @AGR_ID    BIGINT = NULL,
    @RowCount  INT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    IF OBJECT_ID('tempdb..#MIG_IP_KEYS') IS NOT NULL DROP TABLE #MIG_IP_KEYS;
    CREATE TABLE #MIG_IP_KEYS (ID BIGINT NOT NULL PRIMARY KEY);

    /* AGR + batch keys → equality; full/bisect → BETWEEN */
    IF @AGR_ID IS NOT NULL
       AND OBJECT_ID('tempdb..#MIG_IP_BATCH_KEYS') IS NOT NULL
       AND EXISTS (SELECT 1 FROM #MIG_IP_BATCH_KEYS)
        INSERT INTO #MIG_IP_KEYS (ID)
        SELECT DISTINCT bk.ID FROM #MIG_IP_BATCH_KEYS bk
        WHERE bk.ID BETWEEN 1 AND 2147483647;
    ELSE
        INSERT INTO #MIG_IP_KEYS (ID)
        SELECT ip.ID
        FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN ip
        INNER JOIN izgazMGR.dbo.CS_INSTALLMENT ins ON ins.ID = ip.INSTALLMENT_ID
        WHERE ip.ID BETWEEN @BatchFrom AND @BatchTo
          AND ip.ID BETWEEN 1 AND 2147483647
          AND (@AGR_ID IS NULL OR ins.AGREEMENT_ID = @AGR_ID);

    INSERT INTO energy.dbo.LS_005_01_INSTALLMENT_PLAN (
        INSTALLMENT_TYPE_ID, OWNERREF, INVOICE_REF, PAYTRANS_REF,
        TOTAL_AMOUNT, INSTALLMENT_COUNT, COMMISSION_DELAY_RATE, ISACTIVE,
        ADDDATE, ADDUSER, UPDDATE, UPDUSER, PLAN_ID, INVOICE_OLD_DUEDATE,
        ABYS_ID, ABYS_INSTALLMENT_ID, ABYS_ORDER_NUMBER,
        ABYS_AMOUNT, ABYS_LATE_CHARGE, ABYS_OVERDUE,
        ABYS_EXPIRY_DATE, ABYS_DUE_DATE, ABYS_PAYMENT_DATE,
        ABYS_CASH_ID, ABYS_RECEIPT_SERIAL, ABYS_RECEIPT_NUMBER,
        ABYS_POOL_ID, ABYS_DESCRIPTION,
        ABYS_OLD_LATE_CHARGE, ABYS_OLD_EXPIRY_DATE, ABYS_VERSION,
        ABYS_AGREEMENT_ID, ABYS_INSTALLMENT_TYPE_ID,
        ABYS_CANCEL_CAUSE_ID, ABYS_CANCELLATION_DATE, ABYS_CANCELLATION_USER_ID,
        ABYS_INSTALLMENT_DUE_DATE, ABYS_CUSTOM_LATE_RATE,
        ABYS_CREATED_USER_ID, ABYS_UPDATED_USER_ID
    )
    SELECT
        CAST(ins.INSTALLMENT_TYPE_ID AS INT),
        CAST(ins.AGREEMENT_ID AS INT),
        NULL,  -- INVOICE_REF: Pass 1 (wire sonra)
        NULL,  -- PAYTRANS_REF: Pass 1
        CAST(
            ISNULL(ip.AMOUNT, 0)
          + ISNULL(ip.LATE_CHARGE, 0)
          + ISNULL(ip.OVERDUE, 0)
            AS DECIMAL(18,2)
        ),
        CAST(ip.ORDER_NUMBER AS INT),
        CAST(ins.CUSTOM_LATE_RATE AS DECIMAL(18,2)),
        CASE
            WHEN ins.CANCEL_CAUSE_ID IS NULL
             AND ins.CANCELLATION_DATE IS NULL
             AND ins.CANCELLATION_USER_ID IS NULL
             AND ins.DUE_DATE IS NULL THEN 1
            ELSE 0
        END,
        ISNULL(
            CASE
                WHEN ip.CREATED_TIMESTAMP IS NULL THEN NULL
                WHEN CAST(ip.CREATED_TIMESTAMP AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
                WHEN CAST(ip.CREATED_TIMESTAMP AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
                ELSE CAST(ip.CREATED_TIMESTAMP AS DATETIME)
            END,
            CAST('19000101' AS DATETIME)),
        CASE WHEN ip.CREATED_USER_ID IS NULL THEN NULL
             ELSE CAST(ip.CREATED_USER_ID AS INT) + 10000 END,
        CASE
            WHEN ip.UPDATED_TIMESTAMP IS NULL THEN NULL
            WHEN CAST(ip.UPDATED_TIMESTAMP AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            WHEN CAST(ip.UPDATED_TIMESTAMP AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
            ELSE CAST(ip.UPDATED_TIMESTAMP AS DATETIME)
        END,
        CASE WHEN ip.UPDATED_USER_ID IS NULL THEN NULL
             ELSE CAST(ip.UPDATED_USER_ID AS INT) + 10000 END,
        CAST(ins.ID AS INT),  -- PLAN_ID
        NULL,                 -- INVOICE_OLD_DUEDATE: Pass 1 (wire sonra)
        /* ABYS bridge */
        CAST(ip.ID AS BIGINT),
        CAST(ip.INSTALLMENT_ID AS BIGINT),
        CAST(ip.ORDER_NUMBER AS INT),
        CAST(ip.AMOUNT AS DECIMAL(18,2)),
        CAST(ip.LATE_CHARGE AS DECIMAL(18,2)),
        CAST(ip.OVERDUE AS DECIMAL(18,2)),
        CASE
            WHEN ip.EXPIRY_DATE IS NULL THEN NULL
            WHEN CAST(ip.EXPIRY_DATE AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            WHEN CAST(ip.EXPIRY_DATE AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
            ELSE CAST(ip.EXPIRY_DATE AS DATETIME)
        END,
        CASE
            WHEN ip.DUE_DATE IS NULL THEN NULL
            WHEN CAST(ip.DUE_DATE AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            WHEN CAST(ip.DUE_DATE AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
            ELSE CAST(ip.DUE_DATE AS DATETIME)
        END,
        CASE
            WHEN ip.PAYMENT_DATE IS NULL THEN NULL
            WHEN CAST(ip.PAYMENT_DATE AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            WHEN CAST(ip.PAYMENT_DATE AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
            ELSE CAST(ip.PAYMENT_DATE AS DATETIME)
        END,
        CAST(ip.CASH_ID AS BIGINT),
        LEFT(ip.RECEIPT_SERIAL, 6),
        CAST(ip.RECEIPT_NUMBER AS DECIMAL(25,0)),
        CAST(ip.POOL_ID AS BIGINT),
        LEFT(ip.DESCRIPTION, 500),
        CAST(ip.OLD_LATE_CHARGE AS DECIMAL(18,2)),
        CASE
            WHEN ip.OLD_EXPIRY_DATE IS NULL THEN NULL
            WHEN CAST(ip.OLD_EXPIRY_DATE AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            WHEN CAST(ip.OLD_EXPIRY_DATE AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
            ELSE CAST(ip.OLD_EXPIRY_DATE AS DATETIME)
        END,
        CAST(ip.VERSION AS BIGINT),
        CAST(ins.AGREEMENT_ID AS BIGINT),
        CAST(ins.INSTALLMENT_TYPE_ID AS BIGINT),
        CAST(ins.CANCEL_CAUSE_ID AS BIGINT),
        CASE
            WHEN ins.CANCELLATION_DATE IS NULL THEN NULL
            WHEN CAST(ins.CANCELLATION_DATE AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            WHEN CAST(ins.CANCELLATION_DATE AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
            ELSE CAST(ins.CANCELLATION_DATE AS DATETIME)
        END,
        CAST(ins.CANCELLATION_USER_ID AS BIGINT),
        CASE
            WHEN ins.DUE_DATE IS NULL THEN NULL
            WHEN CAST(ins.DUE_DATE AS DATETIME2) < CAST('17530101' AS DATETIME2) THEN NULL
            WHEN CAST(ins.DUE_DATE AS DATETIME2) > CAST('99991231 23:59:59.997' AS DATETIME2) THEN NULL
            ELSE CAST(ins.DUE_DATE AS DATETIME)
        END,
        CAST(ins.CUSTOM_LATE_RATE AS DECIMAL(18,6)),
        CAST(ip.CREATED_USER_ID AS BIGINT),
        CAST(ip.UPDATED_USER_ID AS BIGINT)
    FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN ip
    INNER JOIN #MIG_IP_KEYS kx ON kx.ID = ip.ID
    INNER JOIN izgazMGR.dbo.CS_INSTALLMENT ins
        ON ins.ID = ip.INSTALLMENT_ID
    WHERE (@AGR_ID IS NULL OR ins.AGREEMENT_ID = @AGR_ID)
      AND NOT EXISTS (
          SELECT 1
          FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN t WITH (NOLOCK)
          WHERE t.ABYS_ID = CAST(ip.ID AS BIGINT)
      );

    SET @RowCount = @@ROWCOUNT;
END
GO

-- ------------------------------------------------------------
-- Pass 2 wire: INVOICE_REF + INVOICE_OLD_DUEDATE
-- Onkosul: IX on LS_005_01_INVOICE(ABYS_INSTALLMENT_ID) onerilir
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE
    @AGR_ID BIGINT = NULL,
    @DEBUG  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes i
        JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE i.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
          AND c.name = 'ABYS_INSTALLMENT_ID'
          AND ic.key_ordinal = 1
    )
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
              AND name = 'IX_MIG_INV_ABYS_INSTALLMENT_ID'
        )
            CREATE NONCLUSTERED INDEX IX_MIG_INV_ABYS_INSTALLMENT_ID
                ON energy.dbo.LS_005_01_INVOICE (ABYS_INSTALLMENT_ID)
                INCLUDE (LREF, DUEDATE)
                WHERE ABYS_INSTALLMENT_ID IS NOT NULL
                WITH (MAXDOP = 8, ONLINE = OFF, SORT_IN_TEMPDB = ON);
    END

    UPDATE pl
    SET pl.INVOICE_REF = inv.LREF,
        pl.INVOICE_OLD_DUEDATE = inv.DUEDATE
    FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl
    CROSS APPLY (
        SELECT TOP (1) i.LREF, i.DUEDATE
        FROM energy.dbo.LS_005_01_INVOICE i WITH (NOLOCK)
        WHERE ISNULL(i.IOCODE, 0) = 0
          AND (
                i.ABYS_INSTALLMENT_ID = pl.ABYS_INSTALLMENT_ID
             OR i.INSTALLMENT_PLAN_REF = pl.PLAN_ID
              )
          AND ISNULL(i.PAYABLETOTAL, 0) > 0.01
        ORDER BY
            CASE WHEN i.ABYS_INSTALLMENT_ID = pl.ABYS_INSTALLMENT_ID THEN 0 ELSE 1 END,
            i.LREF
    ) inv
    WHERE pl.ABYS_ID IS NOT NULL
      AND pl.INVOICE_REF IS NULL
      AND pl.ABYS_INSTALLMENT_ID IS NOT NULL
      AND (@AGR_ID IS NULL OR pl.ABYS_AGREEMENT_ID = @AGR_ID);

    IF @DEBUG = 1
        SELECT
            SUM(CASE WHEN INVOICE_REF IS NOT NULL THEN 1 ELSE 0 END) AS WITH_INVOICE,
            SUM(CASE WHEN INVOICE_REF IS NULL THEN 1 ELSE 0 END) AS WITHOUT_INVOICE
        FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN WITH (NOLOCK)
        WHERE ABYS_ID IS NOT NULL
          AND (@AGR_ID IS NULL OR ABYS_AGREEMENT_ID = @AGR_ID);
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_PLAN_INSERT_ONE
    @CurID       BIGINT,
    @AGR_ID      BIGINT = NULL,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN t
        WHERE t.ABYS_ID = @CurID
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_INSTALLMENT_PLAN_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @AGR_ID    = @AGR_ID,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_PLAN_HARD_RESET
    @DELETE_BATCH INT = 10000,
    @AGR_ID       BIGINT = NULL,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @MaxLref INT, @TotalStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_INSTALLMENT_PLAN ABYS kayitlari ***', 0, 1) WITH NOWAIT;

    WHILE 1 = 1
    BEGIN
        IF @AGR_ID IS NULL
            DELETE TOP (@DELETE_BATCH)
            FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN
            WHERE ABYS_ID IS NOT NULL;
        ELSE
            DELETE TOP (@DELETE_BATCH)
            FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN
            WHERE ABYS_ID IS NOT NULL
              AND ABYS_AGREEMENT_ID = @AGR_ID;

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
    FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_INSTALLMENT_PLAN', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s, CHECKIDENT=%d', 0, 1, @TotalStr, @MaxLref) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
    @BATCH_SIZE  INT = 5000,
    @RESUME      BIT = 1,
    @HARD_RESET  BIT = 0,
    @MAX_ERROR   INT = 500,
    @BISECT_MIN  INT = 1,
    @AGR_ID      BIGINT = NULL,
    @DEBUG       BIT = 0
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_INSTALLMENT_PLAN',
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
        @MaxLref        INT,
        @CurID          BIGINT;

    EXEC dbo.SP_MIG_INSTALLMENT_PLAN_VALIDATE_ALL @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_INSTALLMENT_PLAN_HARD_RESET
            @DELETE_BATCH = @BATCH_SIZE,
            @AGR_ID = @AGR_ID,
            @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    IF @AGR_ID IS NULL
    BEGIN
        SELECT @SourceCount = SUM(p.rows)
        FROM izgazMGR.sys.partitions p
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = p.object_id
        INNER JOIN izgazMGR.sys.schemas sch ON sch.schema_id = t.schema_id
        WHERE sch.name = 'dbo'
          AND t.name = 'CS_INSTALLMENT_PLAN'
          AND p.index_id IN (0, 1);

        SELECT @MaxBridgeKey = MAX(ip.ID)
        FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN ip
        WHERE ip.ID BETWEEN 1 AND 2147483647;
    END
    ELSE
    BEGIN
        SELECT @SourceCount = COUNT_BIG(*)
        FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN ip
        INNER JOIN izgazMGR.dbo.CS_INSTALLMENT ins ON ins.ID = ip.INSTALLMENT_ID
        WHERE ip.ID BETWEEN 1 AND 2147483647
          AND ins.AGREEMENT_ID = @AGR_ID;

        SELECT @MaxBridgeKey = MAX(ip.ID)
        FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN ip
        INNER JOIN izgazMGR.dbo.CS_INSTALLMENT ins ON ins.ID = ip.INSTALLMENT_ID
        WHERE ip.ID BETWEEN 1 AND 2147483647
          AND ins.AGREEMENT_ID = @AGR_ID;
    END

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'CS_INSTALLMENT_PLAN',
        @TargetTable    = 'LS_005_01_INSTALLMENT_PLAN',
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
            + '-' + CAST(ISNULL(@MaxBridgeKey, 0) AS VARCHAR(20))
            + CASE WHEN @AGR_ID IS NULL THEN N'' ELSE N' | AGR=' + CAST(@AGR_ID AS VARCHAR(20)) END;
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* v3: AGR icin BatchFrom=Last+1 YASAK — key-list; full'da da ayni */
    IF OBJECT_ID('tempdb..#MIG_IP_BATCH_KEYS') IS NOT NULL DROP TABLE #MIG_IP_BATCH_KEYS;
    CREATE TABLE #MIG_IP_BATCH_KEYS (ID BIGINT NOT NULL PRIMARY KEY);

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @RowCount   = 0;

        TRUNCATE TABLE #MIG_IP_BATCH_KEYS;

        IF @AGR_ID IS NULL
            INSERT INTO #MIG_IP_BATCH_KEYS (ID)
            SELECT TOP (@BATCH_SIZE) ip.ID
            FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN ip
            WHERE ip.ID > @LastBridgeKey
              AND ip.ID <= 2147483647
            ORDER BY ip.ID ASC;
        ELSE
            INSERT INTO #MIG_IP_BATCH_KEYS (ID)
            SELECT TOP (@BATCH_SIZE) ip.ID
            FROM izgazMGR.dbo.CS_INSTALLMENT_PLAN ip
            INNER JOIN izgazMGR.dbo.CS_INSTALLMENT ins ON ins.ID = ip.INSTALLMENT_ID
            WHERE ip.ID > @LastBridgeKey
              AND ip.ID <= 2147483647
              AND ins.AGREEMENT_ID = @AGR_ID
            ORDER BY ip.ID ASC;

        SELECT @BatchFrom = MIN(ID), @BatchTo = MAX(ID) FROM #MIG_IP_BATCH_KEYS;

        IF @BatchTo IS NULL BREAK;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = 'Batch ' + CAST(@BatchNo AS VARCHAR(10))
                + ' | keys=' + CAST((SELECT COUNT(*) FROM #MIG_IP_BATCH_KEYS) AS VARCHAR(20))
                + ' | ' + CAST(@BatchFrom AS VARCHAR(20))
                + '-' + CAST(@BatchTo AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            EXEC dbo.SP_MIG_INSTALLMENT_PLAN_INSERT_RANGE
                @BatchFrom = @BatchFrom,
                @BatchTo   = @BatchTo,
                @AGR_ID    = @AGR_ID,
                @RowCount  = @RowCount OUTPUT;

            COMMIT TRANSACTION;

            SET @LastBridgeKey = @BatchTo;
            SET @ElapsedMs = DATEDIFF(MILLISECOND, @BatchStart, SYSDATETIME());

            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                @RowCount = @RowCount, @ElapsedMs = @ElapsedMs;

            SET @InsertedCount += @RowCount;
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

            /* Bisect BETWEEN kullanir — key-list temizle */
            IF OBJECT_ID('tempdb..#MIG_IP_BATCH_KEYS') IS NOT NULL
                TRUNCATE TABLE #MIG_IP_BATCH_KEYS;

            SET @BisectFrom = @BatchFrom;
            SET @BisectTo   = @BatchTo;

            WHILE @BisectFrom <= @BisectTo AND @Stopped = 0
            BEGIN
                SET @BisectSize = CAST(@BisectTo - @BisectFrom + 1 AS INT);

                IF @BisectSize <= @BISECT_MIN
                BEGIN
                    SET @CurID = @BisectFrom;
                    WHILE @CurID <= @BisectTo AND @Stopped = 0
                    BEGIN
                        SET @RowInserted = 0;
                        BEGIN TRY
                            BEGIN TRANSACTION;
                            EXEC dbo.SP_MIG_INSTALLMENT_PLAN_INSERT_ONE
                                @CurID = @CurID,
                                @AGR_ID = @AGR_ID,
                                @RowInserted = @RowInserted OUTPUT;
                            COMMIT TRANSACTION;

                            IF @RowInserted = 1
                                SET @InsertedCount += 1;
                            ELSE
                                SET @SkippedCount += 1;
                        END TRY
                        BEGIN CATCH
                            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
                            SET @SingleErrMsg = ERROR_MESSAGE();
                            SET @ErrorCount += 1;

                            EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                                @RunID = @RunID, @TableRunID = @TableRunID,
                                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                                @BatchNo = @BatchNo,
                                @BridgeFrom = @CurID, @BridgeTo = @CurID,
                                @SourceID = @CurID,
                                @IsSingleRow = 1,
                                @ErrorMsg = @SingleErrMsg;

                            IF @ErrorCount >= @MAX_ERROR
                                SET @Stopped = 1;
                        END CATCH

                        SET @CurID += 1;
                    END

                    SET @LastBridgeKey = @BisectTo;
                    BREAK;
                END

                SET @BisectMid = @BisectFrom + (@BisectSize / 2) - 1;
                SET @BisectRows = 0;
                SET @BisectLogFrom = @BisectFrom;

                BEGIN TRY
                    BEGIN TRANSACTION;
                    EXEC dbo.SP_MIG_INSTALLMENT_PLAN_INSERT_RANGE
                        @BatchFrom = @BisectFrom,
                        @BatchTo   = @BisectMid,
                        @AGR_ID    = @AGR_ID,
                        @RowCount  = @BisectRows OUTPUT;
                    COMMIT TRANSACTION;

                    SET @InsertedCount += @BisectRows;
                    SET @BisectFrom = @BisectMid + 1;
                END TRY
                BEGIN CATCH
                    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
                    SET @BisectTo = @BisectMid;
                END CATCH
            END

            IF @ErrorCount >= @MAX_ERROR
                SET @Stopped = 1;
        END CATCH
    END

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_INSTALLMENT_PLAN', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN
    WHERE ABYS_ID IS NOT NULL
      AND (@AGR_ID IS NULL OR ABYS_AGREEMENT_ID = @AGR_ID);

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
        WHERE l.MIGRATION_CODE = 'LS_005_01_INSTALLMENT_PLAN'
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO

-- Ornek:
-- EXEC energy.dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
--      @HARD_RESET = 0, @RESUME = 1, @BATCH_SIZE = 5000, @DEBUG = 1;
--
-- Tek AGR:
-- EXEC energy.dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
--      @AGR_ID = 2221, @HARD_RESET = 1, @RESUME = 0, @BATCH_SIZE = 5000, @DEBUG = 1;
--
-- Coklu AGR: adim_multi_agr_pilot_run.sql
--   (276503,556305,197168,5727,2221,978259,1192595)
GO
