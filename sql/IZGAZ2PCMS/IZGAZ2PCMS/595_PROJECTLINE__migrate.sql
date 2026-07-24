/* ============================================================
   SCRIPT_ID : PROJECTLINE_MIGRATE
   SCRIPT_NO : 595
   FILE      : 595_PROJECTLINE__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_PROJECTLINE
-- Kaynak  : izgazMGR.dbo.LS_PROJECTLINE (VW_MIG_PROJECTLINE_SOURCE)
-- Hedef   : energy.dbo.LS_005_01_PROJECTLINE
-- Bridge  : ABYS_ID = LREF (ORACLE_LINE_ID tekil degil)
-- LREF    : IDENTITY (yeni) — IDENTITY_INSERT YOK, kaynak LREF tasinmaz
-- PROJECTID / FLATID / AGRID : NULL (wire sonra)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_PROJECTLINE_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_PROJECTLINE t
        WHERE t.ABYS_ID = @CurID
    )
        RETURN;

    INSERT INTO energy.dbo.LS_005_01_PROJECTLINE (
        PROJECTID, BNA_ID, ENT_ID, FLATID, AGRID,
        ISACTIVE, STATID, PROJECTUSER, FLOWRATE, REGMODEL, REGSNO,
        ACPT_APP_DATE, APPSDATE, APPEDATE, APPCENG,
        PARID, REVISION_TYPE, DESCRIPTION_,
        FRMID2, ENGID2, WORKERID2, FRMID, ENGID, WORKERID,
        REASON, REFID, REFUSEISACTIVE, COMPLETIONID,
        UPDUSER, UPDDATE, ADDUSER, ADDDATE,
        TLTOTAL, ISGASON, FMETHOD, CONFIRMDATE,
        REG_CALCPRESS, XTYPE, OLOC_ID,
        PROJ_ACPT_DATE, PROJ_ENTER_DATE, CONFIRMDATE_REAL,
        INSURANCENO, INSURANCE_EDATE, INSURANCE_SDATE,
        AREA, FLAT_NUMBER, INSURANCE_FIRM_ID, PROJECT_TYPE_ID,
        SAP_TUKETIM_NOKTASI, SAP_PROJECT_NUMBER, SAP_TESISAT_NO,
        ABYS_ID, ABYS_LREF, ABYS_ORACLE_LINE_ID, ABYS_PROJECT_ID, ABYS_PROJECT_LREF,
        ABYS_FLAT_ID, ABYS_AGR_ID, ABYS_BNA_ID, ABYS_ENT_ID,
        ABYS_PAR_ID, ABYS_REF_ID, ABYS_STG_WORKERID2,
        ABYS_STG_TRC_ENG_ID, ABYS_STG_CTRL_ENG_ID,
        ABYS_STG_OLD_PROJECT_STATUS, ABYS_STG_TESISAT_NO,
        ABYS_STG_PROJE_SATIR, ABYS_STG_SERVIS_KUTU_NO,
        ABYS_STG_SAP_TUKETIM_NOKTASI, ABYS_STG_SAP_TESISAT_NO
    )
    SELECT
        s.PROJECTID, s.BNA_ID, s.ENT_ID, s.FLATID, s.AGRID,
        s.ISACTIVE, s.STATID, s.PROJECTUSER, s.FLOWRATE, s.REGMODEL, s.REGSNO,
        s.ACPT_APP_DATE, s.APPSDATE, s.APPEDATE, s.APPCENG,
        s.PARID, s.REVISION_TYPE, s.DESCRIPTION_,
        s.FRMID2, s.ENGID2, s.WORKERID2, s.FRMID, s.ENGID, s.WORKERID,
        s.REASON, s.REFID, s.REFUSEISACTIVE, s.COMPLETIONID,
        s.UPDUSER, s.UPDDATE, s.ADDUSER, s.ADDDATE,
        s.TLTOTAL, s.ISGASON, s.FMETHOD, s.CONFIRMDATE,
        s.REG_CALCPRESS, s.XTYPE, s.OLOC_ID,
        s.PROJ_ACPT_DATE, s.PROJ_ENTER_DATE, s.CONFIRMDATE_REAL,
        s.INSURANCENO, s.INSURANCE_EDATE, s.INSURANCE_SDATE,
        s.AREA, s.FLAT_NUMBER, s.INSURANCE_FIRM_ID, s.PROJECT_TYPE_ID,
        s.SAP_TUKETIM_NOKTASI, s.SAP_PROJECT_NUMBER, s.SAP_TESISAT_NO,
        s.ABYS_ID, s.ABYS_LREF, s.ABYS_ORACLE_LINE_ID, s.ABYS_PROJECT_ID, s.ABYS_PROJECT_LREF,
        s.ABYS_FLAT_ID, s.ABYS_AGR_ID, s.ABYS_BNA_ID, s.ABYS_ENT_ID,
        s.ABYS_PAR_ID, s.ABYS_REF_ID, s.ABYS_STG_WORKERID2,
        s.ABYS_STG_TRC_ENG_ID, s.ABYS_STG_CTRL_ENG_ID,
        s.ABYS_STG_OLD_PROJECT_STATUS, s.ABYS_STG_TESISAT_NO,
        s.ABYS_STG_PROJE_SATIR, s.ABYS_STG_SERVIS_KUTU_NO,
        s.ABYS_STG_SAP_TUKETIM_NOKTASI, s.ABYS_STG_SAP_TESISAT_NO
    FROM energy.dbo.VW_MIG_PROJECTLINE_SOURCE s
    WHERE s.ABYS_ID = @CurID;

    SET @RowInserted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_PROJECTLINE_HARD_RESET
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @MaxLref INT;

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_PROJECTLINE ABYS kayitlari ***', 0, 1) WITH NOWAIT;

    DELETE FROM energy.dbo.LS_005_01_PROJECTLINE
    WHERE ABYS_ID IS NOT NULL;

    SET @Deleted = @@ROWCOUNT;

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_PROJECTLINE;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_PROJECTLINE', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        DECLARE @Msg VARCHAR(100) = '  silindi: ' + CAST(@Deleted AS VARCHAR(20))
            + ', CHECKIDENT=' + CAST(@MaxLref AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_PROJECTLINE
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
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_PROJECTLINE',
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
        @MaxLref        INT;

    EXEC dbo.SP_MIG_PROJECTLINE_VALIDATE_SOURCE @RaiseOnMissing = 1;
    EXEC dbo.SP_MIG_PROJECTLINE_VALIDATE_TARGET @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_PROJECTLINE_HARD_RESET @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM energy.dbo.VW_MIG_PROJECTLINE_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_PROJECTLINE_SOURCE;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_PROJECTLINE',
        @TargetTable    = 'LS_005_01_PROJECTLINE',
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

        SELECT @BatchTo = MAX(ABYS_ID)
        FROM (
            SELECT TOP (@BATCH_SIZE) s.ABYS_ID
            FROM energy.dbo.VW_MIG_PROJECTLINE_SOURCE s
            WHERE s.ABYS_ID > @LastBridgeKey
            ORDER BY s.ABYS_ID ASC
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

            INSERT INTO energy.dbo.LS_005_01_PROJECTLINE (
                PROJECTID, BNA_ID, ENT_ID, FLATID, AGRID,
                ISACTIVE, STATID, PROJECTUSER, FLOWRATE, REGMODEL, REGSNO,
                ACPT_APP_DATE, APPSDATE, APPEDATE, APPCENG,
                PARID, REVISION_TYPE, DESCRIPTION_,
                FRMID2, ENGID2, WORKERID2, FRMID, ENGID, WORKERID,
                REASON, REFID, REFUSEISACTIVE, COMPLETIONID,
                UPDUSER, UPDDATE, ADDUSER, ADDDATE,
                TLTOTAL, ISGASON, FMETHOD, CONFIRMDATE,
                REG_CALCPRESS, XTYPE, OLOC_ID,
                PROJ_ACPT_DATE, PROJ_ENTER_DATE, CONFIRMDATE_REAL,
                INSURANCENO, INSURANCE_EDATE, INSURANCE_SDATE,
                AREA, FLAT_NUMBER, INSURANCE_FIRM_ID, PROJECT_TYPE_ID,
                SAP_TUKETIM_NOKTASI, SAP_PROJECT_NUMBER, SAP_TESISAT_NO,
                ABYS_ID, ABYS_LREF, ABYS_ORACLE_LINE_ID, ABYS_PROJECT_ID, ABYS_PROJECT_LREF,
                ABYS_FLAT_ID, ABYS_AGR_ID, ABYS_BNA_ID, ABYS_ENT_ID,
                ABYS_PAR_ID, ABYS_REF_ID, ABYS_STG_WORKERID2,
                ABYS_STG_TRC_ENG_ID, ABYS_STG_CTRL_ENG_ID,
                ABYS_STG_OLD_PROJECT_STATUS, ABYS_STG_TESISAT_NO,
                ABYS_STG_PROJE_SATIR, ABYS_STG_SERVIS_KUTU_NO,
                ABYS_STG_SAP_TUKETIM_NOKTASI, ABYS_STG_SAP_TESISAT_NO
            )
            SELECT
                s.PROJECTID, s.BNA_ID, s.ENT_ID, s.FLATID, s.AGRID,
                s.ISACTIVE, s.STATID, s.PROJECTUSER, s.FLOWRATE, s.REGMODEL, s.REGSNO,
                s.ACPT_APP_DATE, s.APPSDATE, s.APPEDATE, s.APPCENG,
                s.PARID, s.REVISION_TYPE, s.DESCRIPTION_,
                s.FRMID2, s.ENGID2, s.WORKERID2, s.FRMID, s.ENGID, s.WORKERID,
                s.REASON, s.REFID, s.REFUSEISACTIVE, s.COMPLETIONID,
                s.UPDUSER, s.UPDDATE, s.ADDUSER, s.ADDDATE,
                s.TLTOTAL, s.ISGASON, s.FMETHOD, s.CONFIRMDATE,
                s.REG_CALCPRESS, s.XTYPE, s.OLOC_ID,
                s.PROJ_ACPT_DATE, s.PROJ_ENTER_DATE, s.CONFIRMDATE_REAL,
                s.INSURANCENO, s.INSURANCE_EDATE, s.INSURANCE_SDATE,
                s.AREA, s.FLAT_NUMBER, s.INSURANCE_FIRM_ID, s.PROJECT_TYPE_ID,
                s.SAP_TUKETIM_NOKTASI, s.SAP_PROJECT_NUMBER, s.SAP_TESISAT_NO,
                s.ABYS_ID, s.ABYS_LREF, s.ABYS_ORACLE_LINE_ID, s.ABYS_PROJECT_ID, s.ABYS_PROJECT_LREF,
                s.ABYS_FLAT_ID, s.ABYS_AGR_ID, s.ABYS_BNA_ID, s.ABYS_ENT_ID,
                s.ABYS_PAR_ID, s.ABYS_REF_ID, s.ABYS_STG_WORKERID2,
                s.ABYS_STG_TRC_ENG_ID, s.ABYS_STG_CTRL_ENG_ID,
                s.ABYS_STG_OLD_PROJECT_STATUS, s.ABYS_STG_TESISAT_NO,
                s.ABYS_STG_PROJE_SATIR, s.ABYS_STG_SERVIS_KUTU_NO,
                s.ABYS_STG_SAP_TUKETIM_NOKTASI, s.ABYS_STG_SAP_TESISAT_NO
            FROM energy.dbo.VW_MIG_PROJECTLINE_SOURCE s
            WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
              AND NOT EXISTS (
                  SELECT 1
                  FROM energy.dbo.LS_005_01_PROJECTLINE t
                  WHERE t.ABYS_ID = s.ABYS_ID
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
                        EXEC dbo.SP_MIG_PROJECTLINE_INSERT_ONE
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
                            N'ABYS_ID=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

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

                    INSERT INTO energy.dbo.LS_005_01_PROJECTLINE (
                        PROJECTID, BNA_ID, ENT_ID, FLATID, AGRID,
                        ISACTIVE, STATID, PROJECTUSER, FLOWRATE, REGMODEL, REGSNO,
                        ACPT_APP_DATE, APPSDATE, APPEDATE, APPCENG,
                        PARID, REVISION_TYPE, DESCRIPTION_,
                        FRMID2, ENGID2, WORKERID2, FRMID, ENGID, WORKERID,
                        REASON, REFID, REFUSEISACTIVE, COMPLETIONID,
                        UPDUSER, UPDDATE, ADDUSER, ADDDATE,
                        TLTOTAL, ISGASON, FMETHOD, CONFIRMDATE,
                        REG_CALCPRESS, XTYPE, OLOC_ID,
                        PROJ_ACPT_DATE, PROJ_ENTER_DATE, CONFIRMDATE_REAL,
                        INSURANCENO, INSURANCE_EDATE, INSURANCE_SDATE,
                        AREA, FLAT_NUMBER, INSURANCE_FIRM_ID, PROJECT_TYPE_ID,
                        SAP_TUKETIM_NOKTASI, SAP_PROJECT_NUMBER, SAP_TESISAT_NO,
                        ABYS_ID, ABYS_LREF, ABYS_ORACLE_LINE_ID, ABYS_PROJECT_ID, ABYS_PROJECT_LREF,
                        ABYS_FLAT_ID, ABYS_AGR_ID, ABYS_BNA_ID, ABYS_ENT_ID,
                        ABYS_PAR_ID, ABYS_REF_ID, ABYS_STG_WORKERID2,
                        ABYS_STG_TRC_ENG_ID, ABYS_STG_CTRL_ENG_ID,
                        ABYS_STG_OLD_PROJECT_STATUS, ABYS_STG_TESISAT_NO,
                        ABYS_STG_PROJE_SATIR, ABYS_STG_SERVIS_KUTU_NO,
                        ABYS_STG_SAP_TUKETIM_NOKTASI, ABYS_STG_SAP_TESISAT_NO
                    )
                    SELECT
                        s.PROJECTID, s.BNA_ID, s.ENT_ID, s.FLATID, s.AGRID,
                        s.ISACTIVE, s.STATID, s.PROJECTUSER, s.FLOWRATE, s.REGMODEL, s.REGSNO,
                        s.ACPT_APP_DATE, s.APPSDATE, s.APPEDATE, s.APPCENG,
                        s.PARID, s.REVISION_TYPE, s.DESCRIPTION_,
                        s.FRMID2, s.ENGID2, s.WORKERID2, s.FRMID, s.ENGID, s.WORKERID,
                        s.REASON, s.REFID, s.REFUSEISACTIVE, s.COMPLETIONID,
                        s.UPDUSER, s.UPDDATE, s.ADDUSER, s.ADDDATE,
                        s.TLTOTAL, s.ISGASON, s.FMETHOD, s.CONFIRMDATE,
                        s.REG_CALCPRESS, s.XTYPE, s.OLOC_ID,
                        s.PROJ_ACPT_DATE, s.PROJ_ENTER_DATE, s.CONFIRMDATE_REAL,
                        s.INSURANCENO, s.INSURANCE_EDATE, s.INSURANCE_SDATE,
                        s.AREA, s.FLAT_NUMBER, s.INSURANCE_FIRM_ID, s.PROJECT_TYPE_ID,
                        s.SAP_TUKETIM_NOKTASI, s.SAP_PROJECT_NUMBER, s.SAP_TESISAT_NO,
                        s.ABYS_ID, s.ABYS_LREF, s.ABYS_ORACLE_LINE_ID, s.ABYS_PROJECT_ID, s.ABYS_PROJECT_LREF,
                        s.ABYS_FLAT_ID, s.ABYS_AGR_ID, s.ABYS_BNA_ID, s.ABYS_ENT_ID,
                        s.ABYS_PAR_ID, s.ABYS_REF_ID, s.ABYS_STG_WORKERID2,
                        s.ABYS_STG_TRC_ENG_ID, s.ABYS_STG_CTRL_ENG_ID,
                        s.ABYS_STG_OLD_PROJECT_STATUS, s.ABYS_STG_TESISAT_NO,
                        s.ABYS_STG_PROJE_SATIR, s.ABYS_STG_SERVIS_KUTU_NO,
                        s.ABYS_STG_SAP_TUKETIM_NOKTASI, s.ABYS_STG_SAP_TESISAT_NO
                    FROM energy.dbo.VW_MIG_PROJECTLINE_SOURCE s
                    WHERE s.ABYS_ID BETWEEN @BisectFrom AND @BisectMid
                      AND NOT EXISTS (
                          SELECT 1
                          FROM energy.dbo.LS_005_01_PROJECTLINE t
                          WHERE t.ABYS_ID = s.ABYS_ID
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

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_PROJECTLINE;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_PROJECTLINE', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_PROJECTLINE
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
END
GO

-- EXEC energy.dbo.SP_MIGRATE_LS005_PROJECTLINE @HARD_RESET = 1, @DEBUG = 1;
-- EXEC energy.dbo.SP_MIGRATE_LS005_PROJECTLINE @RESUME = 1, @DEBUG = 1;
-- Wire sonrasi: EXEC energy.dbo.SP_MIG_PROJECTLINE_RESTORE_KEYS @DEBUG = 1;
