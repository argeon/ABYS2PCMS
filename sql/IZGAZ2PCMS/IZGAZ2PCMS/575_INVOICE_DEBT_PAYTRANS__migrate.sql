/* ============================================================
   SCRIPT_ID : INVOICE_DEBT_PAYTRANS_MIGRATE
   SCRIPT_NO : 575
   FILE      : 575_INVOICE_DEBT_PAYTRANS__migrate.sql
   VERSION   : 3
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_DEBT_PAYTRANS
-- Kaynak  : energy.dbo.LS_005_01_INVOICE (IOCODE=0)
-- Hedef   : energy.dbo.LS_005_01_PAYTRANS (borç PT, IOCODE=0)
-- Bridge  : INVOICE.LREF → PAYTRANS.INVOICEREF / ABYS_INVOICE_LREF
-- ABYS_ID : invoice.ABYS_ID
--
-- Sabitler (borç PT):
--   IOCODE=0, PAID=0, PAYTYPE=174, CURRATE=1
--   TRANSTYPE=113, LINETYPE=103, INST_NR=0
--   BANKREF/BANKACCREF/CROSSREF = NULL (wire yok)
--
-- v3: key-list batch — #MIG_DEBT_BATCH_KEYS (Last+1..MAX BETWEEN kaldirildi)
-- v2: @AGR_ID — LS_005_01_AGR.AGREEMENT_NUMBER ile cozum; pilot filtre
--     Oracle CTAS YOK: borc PT energy'de INVOICE'dan turetilir (Adim 3)
--     Fatura zinciri temizligi 571'de (569); burada yalniz borc PT silinir
-- v2b: @AGR_ID doluysa PREPARE_LOAD / index DISABLE YOK
--
-- Pass 1 dump: FK/wire/JOIN yok.
-- Full load (@AGR_ID NULL): PREPARE_LOAD; sonra 576 post.
-- ~74M satir: @BATCH_SIZE varsayilan 50000.
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_DEBT_PAYTRANS_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @AGR_ID    BIGINT = NULL,
    @AgrLref   INT    = NULL,
    @RowCount  INT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    /* v3b: AGR + batch keys → equality; full/bisect → BETWEEN (hizli) */
    IF OBJECT_ID('tempdb..#MIG_DEBT_KEYS') IS NOT NULL DROP TABLE #MIG_DEBT_KEYS;
    CREATE TABLE #MIG_DEBT_KEYS (LREF BIGINT NOT NULL PRIMARY KEY);

    IF @AGR_ID IS NOT NULL
       AND OBJECT_ID('tempdb..#MIG_DEBT_BATCH_KEYS') IS NOT NULL
       AND EXISTS (SELECT 1 FROM #MIG_DEBT_BATCH_KEYS)
        INSERT INTO #MIG_DEBT_KEYS (LREF)
        SELECT DISTINCT k.LREF
        FROM #MIG_DEBT_BATCH_KEYS k
        WHERE k.LREF BETWEEN 1 AND 2147483647;
    ELSE
        INSERT INTO #MIG_DEBT_KEYS (LREF)
        SELECT inv.LREF
        FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
        WHERE inv.LREF BETWEEN @BatchFrom AND @BatchTo
          AND inv.LREF BETWEEN 1 AND 2147483647
          AND ISNULL(inv.IOCODE, 0) = 0
          AND (
                @AGR_ID IS NULL
             OR inv.ABYS_AGREEMENT_ID = @AGR_ID
             OR (@AgrLref IS NOT NULL AND inv.OWNERREF = @AgrLref)
              );

    INSERT INTO energy.dbo.LS_005_01_PAYTRANS WITH (TABLOCK) (
        INVOICEREF, INVLINEREF, DATE_, [TYPE], CLIENTREF, CLIENT_TYPE,
        IOCODE, TLTOTAL, PAID, DUEDATE, PAYTYPE, CURID, CURRATE, CURTOTAL,
        CROSSREF, TRANSTYPE, CANCELED, AGRPAYLINEREF, LOGOREF, TAX, GRANDTOTAL,
        LINETYPE, INST_NR, DV, PAYABLETOTAL, EXPENDINVREF, CALC_FINE, CERTLINKREF,
        ADDDATE, ADDUSER, CANCELLATIONPAYMENT, BANKREF, BANKACCREF, BN_TYPE,
        PROJECTLINEREF, ISDVFREE, XTYPE, IS_LAW, PAYCURID,
        ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_ACCRUE_TYPE_ID,
        ABYS_REGISTER_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF,
        ABYS_ADDUSER, ABYS_UPDUSER
    )
    SELECT
        inv.LREF,
        NULL,
        inv.DATE_,
        inv.[TYPE],
        inv.CLIENTREF,
        inv.OWNERTYPE,
        CAST(0 AS TINYINT),
        inv.TLTOTAL,
        CAST(0 AS FLOAT),
        inv.DUEDATE,
        CAST(174 AS INT),
        inv.CURID,
        CAST(1 AS FLOAT),
        inv.CURTOTAL,
        NULL,
        CAST(113 AS INT),
        inv.CANCELED,
        NULL,
        NULL,
        inv.TAX,
        inv.GRANDTOTAL,
        CAST(103 AS INT),
        CAST(0 AS INT),
        inv.DV,
        inv.PAYABLETOTAL,
        CAST(0 AS INT),
        CAST(0 AS INT),
        NULL,
        inv.ADDDATE,
        inv.ADDUSER,
        CAST(0 AS INT),
        NULL,
        NULL,
        inv.BN_TYPE,
        NULL,
        0,
        ISNULL(inv.XTYPE, 1),
        inv.IS_LAW,
        ISNULL(inv.CURID, 160),
        inv.ABYS_ID,
        inv.ABYS_ACCOUNT_ID,
        inv.ABYS_ACTION_TYPE_ID,
        inv.ABYS_ACCRUE_TYPE_ID,
        inv.ABYS_REGISTER_ID,
        inv.ABYS_AGREEMENT_ID,
        inv.LREF,
        inv.ABYS_ADDUSER,
        inv.ABYS_UPDUSER
    FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    INNER JOIN #MIG_DEBT_KEYS k ON k.LREF = inv.LREF
    WHERE ISNULL(inv.IOCODE, 0) = 0
      AND (
            @AGR_ID IS NULL
         OR inv.ABYS_AGREEMENT_ID = @AGR_ID
         OR (@AgrLref IS NOT NULL AND inv.OWNERREF = @AgrLref)
          )
      AND NOT EXISTS (
          SELECT 1
          FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
          WHERE pt.INVOICEREF = inv.LREF
            AND ISNULL(pt.IOCODE, 0) = 0
            AND pt.ABYS_ID IS NOT NULL
      );

    SET @RowCount = @@ROWCOUNT;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_DEBT_PAYTRANS_INSERT_ONE
    @CurID       BIGINT,
    @AGR_ID      BIGINT = NULL,
    @AgrLref     INT    = NULL,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1
        FROM energy.dbo.LS_005_01_PAYTRANS pt
        WHERE pt.INVOICEREF = @CurID
          AND ISNULL(pt.IOCODE, 0) = 0
          AND pt.ABYS_ID IS NOT NULL
    )
        RETURN;

    IF NOT EXISTS (
        SELECT 1
        FROM energy.dbo.LS_005_01_INVOICE inv
        WHERE inv.LREF = @CurID
          AND ISNULL(inv.IOCODE, 0) = 0
          AND (
                @AGR_ID IS NULL
             OR inv.ABYS_AGREEMENT_ID = @AGR_ID
             OR (@AgrLref IS NOT NULL AND inv.OWNERREF = @AgrLref)
              )
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_DEBT_PAYTRANS_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @AGR_ID    = @AGR_ID,
        @AgrLref   = @AgrLref,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_DEBT_PAYTRANS_HARD_RESET
    @DELETE_BATCH INT = 10000,
    @AGR_ID       BIGINT = NULL,
    @AgrLref      INT    = NULL,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @Deleted      INT,
        @TotalDeleted BIGINT = 0,
        @MaxLref      INT,
        @TotalStr     VARCHAR(20),
        @AgrIdStr     VARCHAR(20),
        @AgrLrefStr   VARCHAR(20);

    SET @AgrIdStr   = ISNULL(CAST(@AGR_ID AS VARCHAR(20)), 'ALL');
    SET @AgrLrefStr = ISNULL(CAST(@AgrLref AS VARCHAR(20)), 'NULL');

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_PAYTRANS borc PT ABYS (AGR_ID=%s AgrLref=%s, batch=%d) ***',
            0, 1, @AgrIdStr, @AgrLrefStr, @DELETE_BATCH) WITH NOWAIT;

    -- Pilot / AGR scoped: index DISABLE etme
    IF @AGR_ID IS NULL AND @AgrLref IS NULL
        EXEC dbo.SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD @DEBUG = @DEBUG;
    ELSE IF @DEBUG = 1
        RAISERROR('AGR HARD RESET: PREPARE_LOAD atlandi (index DISABLE yok).', 0, 1) WITH NOWAIT;

    WHILE 1 = 1
    BEGIN
        IF @AGR_ID IS NULL AND @AgrLref IS NULL
        BEGIN
            DELETE TOP (@DELETE_BATCH)
            FROM energy.dbo.LS_005_01_PAYTRANS
            WHERE ABYS_ID IS NOT NULL
              AND ISNULL(IOCODE, 0) = 0;
        END
        ELSE
        BEGIN
            DELETE TOP (@DELETE_BATCH) pt
            FROM energy.dbo.LS_005_01_PAYTRANS pt
            INNER JOIN energy.dbo.LS_005_01_INVOICE inv
                ON inv.LREF = pt.INVOICEREF
            WHERE pt.ABYS_ID IS NOT NULL
              AND ISNULL(pt.IOCODE, 0) = 0
              AND (
                    inv.ABYS_AGREEMENT_ID = @AGR_ID
                 OR (@AgrLref IS NOT NULL AND inv.OWNERREF = @AgrLref)
                 OR pt.ABYS_AGREEMENT_ID = @AGR_ID
                  );
        END

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
    FROM energy.dbo.LS_005_01_PAYTRANS;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_PAYTRANS', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s, CHECKIDENT=%d', 0, 1, @TotalStr, @MaxLref) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
    @BATCH_SIZE  INT = 50000,
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
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_PAYTRANS_DEBT',
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
        @AgrLref        INT              = NULL,
        @AbysAgrId      BIGINT           = NULL,
        @AgrNumber      VARCHAR(50);

    EXEC dbo.SP_MIG_DEBT_PAYTRANS_VALIDATE_ALL @RaiseOnMissing = 1;

    IF @AGR_ID IS NOT NULL
    BEGIN
        IF OBJECT_ID('energy.dbo.SP_MIG_RESOLVE_AGR_BY_NUMBER', 'P') IS NULL
        BEGIN
            RAISERROR('SP_MIG_RESOLVE_AGR_BY_NUMBER yok. Once 569_INVOICE_CLEAN_BY_AGR.sql deploy edin.', 16, 1);
            RETURN;
        END

        EXEC dbo.SP_MIG_RESOLVE_AGR_BY_NUMBER
            @AGRID     = @AGR_ID,
            @AgrLref   = @AgrLref   OUTPUT,
            @AbysAgrId = @AbysAgrId OUTPUT,
            @AgrNumber = @AgrNumber OUTPUT;

        IF @AgrLref IS NULL
        BEGIN
            SET @Msg = N'LS_005_01_AGR bulunamadi. AGREEMENT_NUMBER=' + ISNULL(CAST(@AGR_ID AS VARCHAR(20)), '?');
            RAISERROR('%s', 16, 1, @Msg);
            RETURN;
        END

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'AGR resolve | AGREEMENT_NUMBER=' + ISNULL(@AgrNumber, '?')
                + N' LREF=' + CAST(@AgrLref AS VARCHAR(20))
                + N' ABYS_ID=' + ISNULL(CAST(@AbysAgrId AS VARCHAR(20)), 'NULL');
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    IF @HARD_RESET = 1 OR (@AGR_ID IS NOT NULL AND @RESUME = 0)
    BEGIN
        EXEC dbo.SP_MIG_DEBT_PAYTRANS_HARD_RESET
            @DELETE_BATCH = @BATCH_SIZE,
            @AGR_ID       = @AGR_ID,
            @AgrLref      = @AgrLref,
            @DEBUG        = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = CASE WHEN @HARD_RESET = 1 THEN 'HARD_RESET' ELSE 'AGR_CLEAN_PT' END;
    END
    ELSE IF @AGR_ID IS NOT NULL
    BEGIN
        -- Pilot resume: index DISABLE yok
        SET @ExecMode = 'AGR_RESUME';
        IF @DEBUG = 1
            RAISERROR('AGR pilot: PREPARE_LOAD atlandi (index DISABLE yok).', 0, 1) WITH NOWAIT;
    END
    ELSE
    BEGIN
        EXEC dbo.SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD @DEBUG = @DEBUG;
        IF @RESUME = 1
            SET @ExecMode = 'RESUME';
        ELSE
            SET @ExecMode = 'FULL';
    END

    SELECT @SourceCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
    WHERE ISNULL(IOCODE, 0) = 0
      AND LREF BETWEEN 1 AND 2147483647
      AND (
            @AGR_ID IS NULL
         OR ABYS_AGREEMENT_ID = @AGR_ID
         OR (@AgrLref IS NOT NULL AND OWNERREF = @AgrLref)
          );

    SELECT @MaxBridgeKey = MAX(inv.LREF)
    FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    WHERE ISNULL(inv.IOCODE, 0) = 0
      AND inv.LREF BETWEEN 1 AND 2147483647
      AND (
            @AGR_ID IS NULL
         OR inv.ABYS_AGREEMENT_ID = @AGR_ID
         OR (@AgrLref IS NOT NULL AND inv.OWNERREF = @AgrLref)
          );

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'energy',
        @SourceTable    = 'LS_005_01_INVOICE',
        @TargetTable    = 'LS_005_01_PAYTRANS',
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
            + ' | AGR=' + ISNULL(CAST(@AGR_ID AS VARCHAR(20)), 'ALL')
            + ' | Kaynak~' + CAST(ISNULL(@SourceCount, 0) AS VARCHAR(20))
            + ' | INVOICE.LREF=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20))
            + ' | key-list';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    IF OBJECT_ID('tempdb..#MIG_DEBT_BATCH_KEYS') IS NOT NULL DROP TABLE #MIG_DEBT_BATCH_KEYS;
    CREATE TABLE #MIG_DEBT_BATCH_KEYS (LREF BIGINT NOT NULL PRIMARY KEY);

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @RowCount   = 0;

        TRUNCATE TABLE #MIG_DEBT_BATCH_KEYS;

        INSERT INTO #MIG_DEBT_BATCH_KEYS (LREF)
        SELECT TOP (@BATCH_SIZE) inv.LREF
        FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
        WHERE inv.LREF > @LastBridgeKey
          AND inv.LREF <= 2147483647
          AND ISNULL(inv.IOCODE, 0) = 0
          AND (
                @AGR_ID IS NULL
             OR inv.ABYS_AGREEMENT_ID = @AGR_ID
             OR (@AgrLref IS NOT NULL AND inv.OWNERREF = @AgrLref)
              )
        ORDER BY inv.LREF ASC;

        SELECT @BatchFrom = MIN(LREF),
               @BatchTo   = MAX(LREF)
        FROM #MIG_DEBT_BATCH_KEYS;

        IF @BatchTo IS NULL BREAK;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = 'Batch ' + CAST(@BatchNo AS VARCHAR(10))
                + ' | keys=' + CAST((SELECT COUNT(*) FROM #MIG_DEBT_BATCH_KEYS) AS VARCHAR(20))
                + ' | ' + CAST(@BatchFrom AS VARCHAR(20))
                + '-' + CAST(@BatchTo AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            EXEC dbo.SP_MIG_DEBT_PAYTRANS_INSERT_RANGE
                @BatchFrom = @BatchFrom,
                @BatchTo   = @BatchTo,
                @AGR_ID    = @AGR_ID,
                @AgrLref   = @AgrLref,
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

            IF OBJECT_ID('tempdb..#MIG_DEBT_BATCH_KEYS') IS NOT NULL
                TRUNCATE TABLE #MIG_DEBT_BATCH_KEYS;

            SET @BisectFrom = @BatchFrom;
            SET @BisectTo   = @BatchTo;

            WHILE @BisectFrom <= @BisectTo AND @Stopped = 0
            BEGIN
                SET @BisectSize = @BisectTo - @BisectFrom + 1;

                IF @BisectSize <= @BISECT_MIN
                BEGIN
                    BEGIN TRY
                        SET @RowInserted = 0;
                        EXEC dbo.SP_MIG_DEBT_PAYTRANS_INSERT_ONE
                            @CurID = @BisectFrom,
                            @AGR_ID = @AGR_ID,
                            @AgrLref = @AgrLref,
                            @RowInserted = @RowInserted OUTPUT;

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
                            N'INVOICE.LREF=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

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

                    EXEC dbo.SP_MIG_DEBT_PAYTRANS_INSERT_RANGE
                        @BatchFrom = @BisectFrom,
                        @BatchTo   = @BisectMid,
                        @AGR_ID    = @AGR_ID,
                        @AgrLref   = @AgrLref,
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

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_PAYTRANS;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_PAYTRANS', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_PAYTRANS pt
    WHERE pt.ABYS_ID IS NOT NULL
      AND ISNULL(pt.IOCODE, 0) = 0
      AND (
            @AGR_ID IS NULL
         OR pt.ABYS_AGREEMENT_ID = @AGR_ID
         OR EXISTS (
                SELECT 1 FROM energy.dbo.LS_005_01_INVOICE inv
                WHERE inv.LREF = pt.INVOICEREF
                  AND (
                        inv.ABYS_AGREEMENT_ID = @AGR_ID
                     OR (@AgrLref IS NOT NULL AND inv.OWNERREF = @AgrLref)
                      )
            )
          );

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
        WHEN @Stopped = 1 THEN N'Max hata limitine ulasildi. RESUME ile devam edin. Index icin 576_INVOICE_DEBT_PAYTRANS__post calistirin.'
        ELSE N'Aktarim bitti. Index icin: EXEC energy.dbo.SP_MIG_DEBT_PAYTRANS_POST_INDEXES @DEBUG=1;'
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
        WHERE l.MIGRATION_CODE = 'LS_005_01_PAYTRANS_DEBT'
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO

-- Pilot AGR:
-- EXEC energy.dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
--      @AGR_ID = 197168, @HARD_RESET = 0, @RESUME = 0, @BATCH_SIZE = 1000, @DEBUG = 1;
-- Full:
-- EXEC energy.dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
--      @HARD_RESET = 1, @RESUME = 1, @BATCH_SIZE = 50000, @DEBUG = 1;
-- EXEC energy.dbo.SP_MIG_DEBT_PAYTRANS_POST_INDEXES @DEBUG = 1;
