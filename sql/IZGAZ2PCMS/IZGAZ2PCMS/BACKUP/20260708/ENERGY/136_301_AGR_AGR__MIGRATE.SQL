/* ============================================================
   SCRIPT_ID : AGR_AGR_MIGRATE
   SCRIPT_NO : 301
   FILE      : 301_AGR_AGR__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_AGR  (LEGACY — yavas; MIG_ROW_ID + auto IDENTITY)
-- Kaynak  : izgazMGR.dbo.LS_AGREEMENT (MIG_ROW_ID köprü)
-- Hedef   : energy.dbo.LS_005_01_AGR
-- LREF    : IDENTITY (otomatik) — kaynak LREF KORUNMAZ
--
-- Tercih edilen yol (LREF korunur, TABLOCK bulk):
--   302_AGR_AGR__bulk_migrate.sql → SP_MIGRATE_LS005_AGR_BULK
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_INSERT_ONE
    @MigRowID    BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_AGR t
        WHERE t.ABYS_MIG_ROW_ID = @MigRowID
    )
        RETURN;

    IF EXISTS (
        SELECT 1
        FROM energy.dbo.VW_MIG_AGR_SOURCE s
        INNER JOIN energy.dbo.LS_005_01_AGR t
            ON t.TP2 COLLATE DATABASE_DEFAULT = s.TP2 COLLATE DATABASE_DEFAULT
           AND t.ABYS_ID = s.ABYS_ID
        WHERE s.MIG_ROW_ID = @MigRowID
    )
        RETURN;

    INSERT INTO energy.dbo.LS_005_01_AGR (
        ABYS_MIG_ROW_ID, ABYS_ID,
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
        s.MIG_ROW_ID, s.ABYS_ID,
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
    WHERE s.MIG_ROW_ID = @MigRowID
      AND s.ABYS_DUP_RN = 1;

    SET @RowInserted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_HARD_RESET
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @MaxLref INT;

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_AGR ABYS kayitlari ***', 0, 1) WITH NOWAIT;

    DELETE FROM energy.dbo.LS_005_01_AGR
    WHERE ABYS_MIG_ROW_ID IS NOT NULL;

    SET @Deleted = @@ROWCOUNT;

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_AGR;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_AGR', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        DECLARE @Msg VARCHAR(100) = '  silindi: ' + CAST(@Deleted AS VARCHAR(20))
            + ', CHECKIDENT=' + CAST(@MaxLref AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_AGR
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
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_AGR',
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

    EXEC dbo.SP_MIG_AGR_VALIDATE_SOURCE @RaiseOnMissing = 1;
    EXEC dbo.SP_MIG_AGR_VALIDATE_TARGET @RaiseOnMissing = 1;
    EXEC dbo.SP_MIG_AGR_PREP_SOURCE;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_AGR_HARD_RESET @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM energy.dbo.VW_MIG_AGR_SOURCE;
    SELECT @MaxBridgeKey = MAX(MIG_ROW_ID) FROM energy.dbo.VW_MIG_AGR_SOURCE;

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

    IF @DEBUG = 1
    BEGIN
        SET @Msg = 'RUN ' + CAST(@RunID AS VARCHAR(36))
            + ' | Kaynak=' + CAST(@SourceCount AS VARCHAR(20))
            + ' | MIG_ROW_ID=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @BatchFrom  = @LastBridgeKey + 1;
        SET @RowCount   = 0;

        SELECT @BatchTo = MAX(MIG_ROW_ID)
        FROM (
            SELECT TOP (@BATCH_SIZE) s.MIG_ROW_ID
            FROM energy.dbo.VW_MIG_AGR_SOURCE s
            WHERE s.MIG_ROW_ID > @LastBridgeKey
            ORDER BY s.MIG_ROW_ID ASC
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

            INSERT INTO energy.dbo.LS_005_01_AGR (
                ABYS_MIG_ROW_ID, ABYS_ID,
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
                s.MIG_ROW_ID, s.ABYS_ID,
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
            WHERE s.MIG_ROW_ID BETWEEN @BatchFrom AND @BatchTo
              AND s.ABYS_DUP_RN = 1
              AND NOT EXISTS (
                  SELECT 1
                  FROM energy.dbo.LS_005_01_AGR t
                  WHERE t.ABYS_MIG_ROW_ID = s.MIG_ROW_ID
              )
              AND NOT EXISTS (
                  SELECT 1
                  FROM energy.dbo.LS_005_01_AGR t
                  WHERE t.TP2 COLLATE DATABASE_DEFAULT = s.TP2 COLLATE DATABASE_DEFAULT
                    AND t.ABYS_ID = s.ABYS_ID
              );

            SET @RowCount = @@ROWCOUNT;
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
                        EXEC dbo.SP_MIG_AGR_INSERT_ONE
                            @MigRowID = @BisectFrom, @RowInserted = @RowInserted OUTPUT;

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
                            N'MIG_ROW_ID=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

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

                    INSERT INTO energy.dbo.LS_005_01_AGR (
                        ABYS_MIG_ROW_ID, ABYS_ID,
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
                        s.MIG_ROW_ID, s.ABYS_ID,
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
                    WHERE s.MIG_ROW_ID BETWEEN @BisectFrom AND @BisectMid
                      AND s.ABYS_DUP_RN = 1
                      AND NOT EXISTS (
                          SELECT 1
                          FROM energy.dbo.LS_005_01_AGR t
                          WHERE t.ABYS_MIG_ROW_ID = s.MIG_ROW_ID
                      )
                      AND NOT EXISTS (
                          SELECT 1
                          FROM energy.dbo.LS_005_01_AGR t
                          WHERE t.TP2 COLLATE DATABASE_DEFAULT = s.TP2 COLLATE DATABASE_DEFAULT
                            AND t.ABYS_ID = s.ABYS_ID
                      );

                    SET @BisectRows = @@ROWCOUNT;
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
    FROM energy.dbo.LS_005_01_AGR
    WHERE ABYS_MIG_ROW_ID IS NOT NULL;

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

-- EXEC energy.dbo.SP_MIGRATE_LS005_AGR @HARD_RESET = 1, @DEBUG = 1;
-- EXEC energy.dbo.SP_MIG_WIRE_AGR_CLOSE_AGRID @Debug = 1;

