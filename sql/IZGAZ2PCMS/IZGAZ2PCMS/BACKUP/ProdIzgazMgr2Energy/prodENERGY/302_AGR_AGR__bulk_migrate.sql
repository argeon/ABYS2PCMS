/* ============================================================
   SCRIPT_ID : AGR_AGR_BULK_MIGRATE
   SCRIPT_NO : 302
   FILE      : 302_AGR_AGR__bulk_migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_AGR_BULK
-- Kaynak  : izgazMGR.dbo.LS_AGREEMENT
-- Hedef   : energy.dbo.LS_005_01_AGR
-- LREF    : IDENTITY_INSERT = kaynak LREF
--           KUL = CS_AGREEMENT.ID
--           ABN = MAX(CS_AGREEMENT.ID) + seq (Oracle CTAS)
--
-- Onkosul : 300_AGR_AGR__setup.sql (LREF + VW_MIG_AGR_SOURCE)
-- Bulk    : IDENTITY_INSERT + TABLOCK + LREF aralik batch
-- MAXDOP  : varsayilan 24 (ust sinir 24)
--
-- Ornek:
--   EXEC energy.dbo.SP_MIGRATE_LS005_AGR_BULK @HARD_RESET = 1, @DEBUG = 1;
--   EXEC energy.dbo.SP_MIGRATE_LS005_AGR_BULK @RESUME = 1, @MAXDOP = 24, @DEBUG = 1;
--   EXEC energy.dbo.SP_MIGRATE_LS005_AGR_BULK @AGR_ID = 123456, @DEBUG = 1;
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_BULK_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @AGR_ID    BIGINT = NULL,
    @MAXDOP    INT    = 24,
    @RowCount  INT    = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    /* Ust sinir 24 */
    IF @MAXDOP IS NULL OR @MAXDOP < 1 SET @MAXDOP = 1;
    IF @MAXDOP > 24 SET @MAXDOP = 24;

    DECLARE @sql NVARCHAR(MAX);

    BEGIN TRY
        SET IDENTITY_INSERT energy.dbo.LS_005_01_AGR ON;

        SET @sql = N'
        INSERT INTO energy.dbo.LS_005_01_AGR WITH (TABLOCK) (
            LREF, ABYS_MIG_ROW_ID, ABYS_ID,
            FLATID, AGR_SDATE, AGR_EDATE, BN_TYPE, FRMID, CON,
            TP1, TP2, TP3, FMETHOD, FPARID, FMANUAL,
            PAY_SDATE, PAY_TOTAL, STATID, PARID, ISACTIVE,
            ADDUSER, ADDDATE, UPDUSER, UPDDATE,
            NEEDPAY, TLTOTAL, CURTOTAL, CURTYPE, PAYTYPE,
            FITNO, GRANDTOTAL, TAX, DV,
            COUNTERMODEL, COUNTERSN, COUNTERID, COUNTERMBAR, CALCPRESSID,
            OPENED, OPEN_DATE, BNA_ID, INV_PRINT_DATE,
            REFUND, FEE_COLLECTED, LASTREAD_DATE, EXPIRE_DEBTTIME, HAS_USING_AGR,
            IS_GS, OLOC_ID, IS_FIRST_USE, CLOSESTATID, PAY_BANKREF, NOTE,
            TRANS, OLREF, COUNTER_STAT, SON_ODEME_GUNU, Cap, Basinc, Tip, APP_ID,
            AGREEMENT_NUMBER, ISTAXFREE, ISDVFREE, ISOTVFREE, ISNOTCALCDV, TUKETIM_NOKTASI,
            ABYS_REFUND_DATE, ABYS_SKB_TARIFF_TYPE_ID, ABYS_TARIFF_TYPE_ID,
            ABYS_INSTALLATION_STATUS_ID, ABYS_SERVICE_BOX_ID, ABYS_HOUSEHOLDS_COUNT,
            ABYS_FIRST_STARTUP_DATE, ABYS_SUBSCRIBER_TYPE, ABYS_SKB_TARIFF_TYPE,
            ABYS_TARIFF_TYPE, ABYS_INSTALLATION_STATUS, ABYS_PCMS_TARIFF_TYPE_NAME,
            ABYS_PROJECT_STATUS, ABYS_CLOSESTAT_DATE
        )
        SELECT
            s.LREF, s.MIG_ROW_ID, s.ABYS_ID,
            s.FLATID, s.AGR_SDATE, s.AGR_EDATE, s.BN_TYPE, s.FRMID, s.CON,
            s.TP1, s.TP2, s.TP3, s.FMETHOD, s.FPARID, s.FMANUAL,
            s.PAY_SDATE, s.PAY_TOTAL, s.STATID, s.PARID, s.ISACTIVE,
            s.ADDUSER, s.ADDDATE, s.UPDUSER, s.UPDDATE,
            s.NEEDPAY, s.TLTOTAL, s.CURTOTAL, s.CURTYPE, s.PAYTYPE,
            s.FITNO, s.GRANDTOTAL, s.TAX, s.DV,
            s.COUNTERMODEL, s.COUNTERSN, s.COUNTERID, s.COUNTERMBAR, s.CALCPRESSID,
            s.OPENED, s.OPEN_DATE, s.BNA_ID, s.INV_PRINT_DATE,
            s.REFUND, s.FEE_COLLECTED, s.LASTREAD_DATE, s.EXPIRE_DEBTTIME, s.HAS_USING_AGR,
            s.IS_GS, s.OLOC_ID, s.IS_FIRST_USE, s.CLOSESTATID, s.PAY_BANKREF, s.NOTE,
            s.TRANS, s.OLREF, s.COUNTER_STAT, s.SON_ODEME_GUNU, s.Cap, s.Basinc, s.Tip, s.APP_ID,
            s.AGREEMENT_NUMBER, s.ISTAXFREE, s.ISDVFREE, s.ISOTVFREE, s.ISNOTCALCDV, s.TUKETIM_NOKTASI,
            s.ABYS_REFUND_DATE, s.ABYS_SKB_TARIFF_TYPE_ID, s.ABYS_TARIFF_TYPE_ID,
            s.ABYS_INSTALLATION_STATUS_ID, s.ABYS_SERVICE_BOX_ID, s.ABYS_HOUSEHOLDS_COUNT,
            s.ABYS_FIRST_STARTUP_DATE, s.ABYS_SUBSCRIBER_TYPE, s.ABYS_SKB_TARIFF_TYPE,
            s.ABYS_TARIFF_TYPE, s.ABYS_INSTALLATION_STATUS, s.ABYS_PCMS_TARIFF_TYPE_NAME,
            s.ABYS_PROJECT_STATUS, s.ABYS_CLOSESTAT_DATE
        FROM energy.dbo.VW_MIG_AGR_SOURCE s
        WHERE s.LREF BETWEEN @BatchFrom AND @BatchTo
          AND (@AGR_ID IS NULL OR s.ABYS_ID = @AGR_ID)
          AND NOT EXISTS (
              SELECT 1 FROM energy.dbo.LS_005_01_AGR t WITH (NOLOCK)
              WHERE t.LREF = s.LREF
          )
        OPTION (RECOMPILE, MAXDOP ' + CAST(@MAXDOP AS NVARCHAR(2)) + N');';

        EXEC sys.sp_executesql
            @sql,
            N'@BatchFrom BIGINT, @BatchTo BIGINT, @AGR_ID BIGINT',
            @BatchFrom = @BatchFrom,
            @BatchTo   = @BatchTo,
            @AGR_ID    = @AGR_ID;

        SET @RowCount = @@ROWCOUNT;

        SET IDENTITY_INSERT energy.dbo.LS_005_01_AGR OFF;
    END TRY
    BEGIN CATCH
        BEGIN TRY SET IDENTITY_INSERT energy.dbo.LS_005_01_AGR OFF; END TRY BEGIN CATCH END CATCH;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_BULK_HARD_RESET
    @DELETE_BATCH INT = 50000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @Deleted      INT,
        @TotalDeleted BIGINT = 0,
        @MaxLref      INT,
        @Msg          NVARCHAR(200),
        @TotalStr     VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET BULK: LS_005_01_AGR ABYS kayitlari ***', 0, 1) WITH NOWAIT;

    BEGIN TRY SET IDENTITY_INSERT energy.dbo.LS_005_01_AGR OFF; END TRY BEGIN CATCH END CATCH;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_005_01_AGR
        WHERE ABYS_MIG_ROW_ID IS NOT NULL
           OR ABYS_ID IS NOT NULL;

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
    FROM energy.dbo.LS_005_01_AGR;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_AGR', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        SET @Msg = N'HARD RESET bitti. silinen=' + @TotalStr
                 + N', CHECKIDENT=' + CAST(@MaxLref AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_AGR_BULK
    @BATCH_SIZE  INT    = 50000,
    @RESUME      BIT    = 1,
    @HARD_RESET  BIT    = 0,
    @MAX_ERROR   INT    = 50,
    @AGR_ID      BIGINT = NULL,
    @MAXDOP      INT    = 24,
    @DEBUG       BIT    = 0
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    /* Ust sinir 24 */
    IF @MAXDOP IS NULL OR @MAXDOP < 1 SET @MAXDOP = 1;
    IF @MAXDOP > 24 SET @MAXDOP = 24;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_AGR_BULK',
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
        @Msg            NVARCHAR(500),
        @BatchStart     DATETIME2(3),
        @ElapsedMs      INT,
        @ExecMode       VARCHAR(20),
        @RunStatus      VARCHAR(25),
        @PhaseStatus    VARCHAR(20),
        @Stopped        BIT              = 0,
        @FinishErrorMsg NVARCHAR(4000),
        @MaxLref        INT,
        @BisectFrom     BIGINT,
        @BisectTo       BIGINT,
        @BisectMid      BIGINT,
        @BisectSize     INT,
        @BisectRows     INT;

    EXEC dbo.SP_MIG_AGR_VALIDATE_SOURCE @RaiseOnMissing = 1;
    EXEC dbo.SP_MIG_AGR_VALIDATE_TARGET @RaiseOnMissing = 1;
    EXEC dbo.SP_MIG_AGR_PREP_SOURCE;

    IF @HARD_RESET = 1 AND @AGR_ID IS NULL
    BEGIN
        EXEC dbo.SP_MIG_AGR_BULK_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @AGR_ID IS NOT NULL AND (@RESUME = 0 OR @HARD_RESET = 1)
    BEGIN
        DELETE FROM energy.dbo.LS_005_01_AGR
        WHERE ABYS_ID = @AGR_ID;

        SET @RESUME = 0;
        SET @ExecMode = 'AGR_CLEAN';
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'AGR pilot: ABYS_ID=' + CAST(@AGR_ID AS VARCHAR(20)) + N' hedef temizlendi.';
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    IF @AGR_ID IS NOT NULL
    BEGIN
        SELECT @SourceCount = COUNT_BIG(*), @MaxBridgeKey = MAX(CAST(s.LREF AS BIGINT))
        FROM izgazMGR.dbo.LS_AGREEMENT s WITH (NOLOCK)
        WHERE s.ABYS_ID = @AGR_ID
          AND s.LREF BETWEEN 1 AND 2147483647
        OPTION (MAXDOP 24);
    END
    ELSE
    BEGIN
        SELECT @SourceCount = COUNT_BIG(*), @MaxBridgeKey = MAX(CAST(s.LREF AS BIGINT))
        FROM izgazMGR.dbo.LS_AGREEMENT s WITH (NOLOCK)
        WHERE s.LREF BETWEEN 1 AND 2147483647
        OPTION (MAXDOP 24);
    END

    IF @MaxBridgeKey IS NULL
    BEGIN
        RAISERROR('Kaynakta LREF bulunamadi (LS_AGREEMENT bos veya LREF yok).', 16, 1);
        RETURN;
    END

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_AGREEMENT',
        @TargetTable    = 'LS_005_01_AGR',
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

    /* Resume: hedefte mevcut max ABYS LREF ile senkron */
    IF @RESUME = 1 AND @AGR_ID IS NULL
    BEGIN
        SELECT @LastBridgeKey = ISNULL(MAX(CAST(t.LREF AS BIGINT)), @LastBridgeKey)
        FROM energy.dbo.LS_005_01_AGR t WITH (NOLOCK)
        WHERE t.ABYS_ID IS NOT NULL
          AND t.LREF BETWEEN 1 AND 2147483647
          AND t.LREF > @LastBridgeKey;
    END
    ELSE IF @RESUME = 1 AND @AGR_ID IS NOT NULL
    BEGIN
        SELECT @LastBridgeKey = ISNULL(MAX(CAST(t.LREF AS BIGINT)), @LastBridgeKey)
        FROM energy.dbo.LS_005_01_AGR t WITH (NOLOCK)
        WHERE t.ABYS_ID = @AGR_ID
          AND t.LREF BETWEEN 1 AND 2147483647
          AND t.LREF > @LastBridgeKey;
    END

    IF @DEBUG = 1
    BEGIN
        SET @Msg = 'RUN ' + CAST(@RunID AS VARCHAR(36))
            + ' | mode=' + @ExecMode
            + ' | AGR=' + ISNULL(CAST(@AGR_ID AS VARCHAR(20)), 'ALL')
            + ' | MAXDOP=' + CAST(@MAXDOP AS VARCHAR(2))
            + ' | kaynak=' + CAST(ISNULL(@SourceCount, 0) AS VARCHAR(20))
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

        /* Sonraki @BATCH_SIZE kadar LREF ust siniri */
        SELECT @BatchTo = MAX(LREF)
        FROM (
            SELECT TOP (@BATCH_SIZE) CAST(s.LREF AS BIGINT) AS LREF
            FROM izgazMGR.dbo.LS_AGREEMENT s WITH (NOLOCK)
            WHERE CAST(s.LREF AS BIGINT) > @LastBridgeKey
              AND s.LREF BETWEEN 1 AND 2147483647
              AND (@AGR_ID IS NULL OR s.ABYS_ID = @AGR_ID)
            ORDER BY CAST(s.LREF AS BIGINT) ASC
        ) x;

        IF @BatchTo IS NULL BREAK;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = 'Batch ' + CAST(@BatchNo AS VARCHAR(10))
                + ' | LREF ' + CAST(@BatchFrom AS VARCHAR(20))
                + '-' + CAST(@BatchTo AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        BEGIN TRY
            EXEC dbo.SP_MIG_AGR_BULK_INSERT_RANGE
                @BatchFrom = @BatchFrom,
                @BatchTo   = @BatchTo,
                @AGR_ID    = @AGR_ID,
                @MAXDOP    = @MAXDOP,
                @RowCount  = @RowCount OUTPUT;

            SET @LastBridgeKey = @BatchTo;
            SET @ElapsedMs = DATEDIFF(MILLISECOND, @BatchStart, SYSDATETIME());

            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                @RowCount = @RowCount, @ElapsedMs = @ElapsedMs;
        END TRY
        BEGIN CATCH
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
                SET @BisectSize = CAST(@BisectTo - @BisectFrom + 1 AS INT);

                IF @BisectSize <= 1
                BEGIN
                    BEGIN TRY
                        EXEC dbo.SP_MIG_AGR_BULK_INSERT_RANGE
                            @BatchFrom = @BisectFrom,
                            @BatchTo   = @BisectFrom,
                            @AGR_ID    = @AGR_ID,
                            @MAXDOP    = @MAXDOP,
                            @RowCount  = @BisectRows OUTPUT;

                        EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                            @RunID = @RunID, @TableRunID = @TableRunID,
                            @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                            @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom,
                            @BridgeTo = @BisectFrom, @RowCount = @BisectRows;
                    END TRY
                    BEGIN CATCH
                        SET @ErrMsg = ERROR_MESSAGE();

                        EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                            @RunID = @RunID, @TableRunID = @TableRunID,
                            @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                            @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom,
                            @BridgeTo = @BisectFrom, @SourceID = @BisectFrom,
                            @IsSingleRow = 1,
                            @ErrorMsg = @ErrMsg;

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
                    EXEC dbo.SP_MIG_AGR_BULK_INSERT_RANGE
                        @BatchFrom = @BisectFrom,
                        @BatchTo   = @BisectMid,
                        @AGR_ID    = @AGR_ID,
                        @MAXDOP    = @MAXDOP,
                        @RowCount  = @BisectRows OUTPUT;

                    EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                        @RunID = @RunID, @TableRunID = @TableRunID,
                        @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                        @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom,
                        @BridgeTo = @BisectMid, @RowCount = @BisectRows;

                    SET @BisectFrom = @BisectMid + 1;
                END TRY
                BEGIN CATCH
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

    /* IDENTITY seed — sonraki native insert'ler max sonrasi */
    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_AGR;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_AGR', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_AGR WITH (NOLOCK)
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

    /* Hizli dogrulama */
    SELECT
        (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_AGREEMENT WITH (NOLOCK)
         WHERE LREF BETWEEN 1 AND 2147483647
           AND (@AGR_ID IS NULL OR ABYS_ID = @AGR_ID)) AS SRC_CNT,
        (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_AGR WITH (NOLOCK)
         WHERE ABYS_ID IS NOT NULL
           AND (@AGR_ID IS NULL OR ABYS_ID = @AGR_ID)) AS TGT_CNT,
        (SELECT COUNT_BIG(*) FROM energy.dbo.VW_MIG_AGR_SOURCE s
         WHERE (@AGR_ID IS NULL OR s.ABYS_ID = @AGR_ID)
           AND NOT EXISTS (
               SELECT 1 FROM energy.dbo.LS_005_01_AGR t WHERE t.LREF = s.LREF
           )) AS MISSING_BY_LREF,
        @MaxLref AS CHECKIDENT_LREF;
END
GO

PRINT '302_AGR_AGR__bulk_migrate deployed.';
PRINT 'Kullanim:';
PRINT '  EXEC energy.dbo.SP_MIGRATE_LS005_AGR_BULK @HARD_RESET = 1, @MAXDOP = 24, @DEBUG = 1;';
PRINT '  EXEC energy.dbo.SP_MIGRATE_LS005_AGR_BULK @RESUME = 1, @MAXDOP = 24, @DEBUG = 1;';
PRINT '  EXEC energy.dbo.SP_MIGRATE_LS005_AGR_BULK @AGR_ID = <abys_id>, @MAXDOP = 24, @DEBUG = 1;';
GO
