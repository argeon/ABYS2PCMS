/* ============================================================
   SCRIPT_ID : AGR_DEV_MIGRATE
   SCRIPT_NO : 331
   FILE      : 331_AGR_DEV__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_AGR_DEV
-- Kaynak  : izgazMGR.dbo.LS_AGR_DEVICE (VW_MIG_AGR_DEVICE_SOURCE)
-- Hedef   : energy.dbo.LS_005_01_AGR_DEV_TR
-- Bridge  : MIG_ROW_ID → ABYS_MIG_ROW_ID (LREF = IDENTITY)
-- AGRID   : kaynak ABYS_AGREEMENT_ID (Oracle/ABYS hali; wire YOK)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_DEV_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_AGR_DEV_TR t
        WHERE t.ABYS_MIG_ROW_ID = @CurID
    )
        RETURN;

    INSERT INTO energy.dbo.LS_005_01_AGR_DEV_TR (
        ABYS_MIG_ROW_ID, ABYS_AGREEMENT_ID,
        DEVID, AGRID,
        CAPACITY, WORKDAY, WORKHOUR, FEE, EXCNR, BLIND_PLUG,
        ISACTIVE, DEMANDTYPE,
        ADDUSER, ADDDATE, UPDUSER, UPDDATE,
        ABYS_DEV_ID, ABYS_DEVICE_KIND,
        ABYS_PROJECT_ID, ABYS_INSTALLATION_ID,
        ABYS_MARK_CODE, ABYS_MARK_VALUE
    )
    SELECT
        s.MIG_ROW_ID, s.ABYS_AGREEMENT_ID,
        s.DEVID, s.ABYS_AGREEMENT_ID,
        s.CAPACITY, s.WORKDAY, s.WORKHOUR, s.FEE, s.EXCNR, s.BLIND_PLUG,
        s.ISACTIVE, s.DEMANDTYPE,
        s.ADDUSER, s.ADDDATE, s.UPDUSER, s.UPDDATE,
        s.ABYS_DEV_ID, s.ABYS_DEVICE_KIND,
        s.ABYS_PROJECT_ID, s.ABYS_INSTALLATION_ID,
        s.ABYS_MARK_CODE, s.ABYS_MARK_VALUE
    FROM energy.dbo.VW_MIG_AGR_DEVICE_SOURCE s
    WHERE s.MIG_ROW_ID = @CurID;

    SET @RowInserted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_DEV_HARD_RESET
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @MaxLref INT;

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_AGR_DEV_TR ABYS kayitlari ***', 0, 1) WITH NOWAIT;

    DELETE FROM energy.dbo.LS_005_01_AGR_DEV_TR
    WHERE ABYS_MIG_ROW_ID IS NOT NULL;

    SET @Deleted = @@ROWCOUNT;

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_AGR_DEV_TR;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_AGR_DEV_TR', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        DECLARE @Msg VARCHAR(100) = '  silindi: ' + CAST(@Deleted AS VARCHAR(20))
            + ', CHECKIDENT=' + CAST(@MaxLref AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_AGR_DEV
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
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_AGR_DEV_TR',
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

    EXEC dbo.SP_MIG_AGR_DEV_PREP_SOURCE;
    EXEC dbo.SP_MIG_AGR_DEV_VALIDATE_SOURCE @RaiseOnMissing = 1;
    EXEC dbo.SP_MIG_AGR_DEV_VALIDATE_TARGET @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_AGR_DEV_HARD_RESET @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM energy.dbo.VW_MIG_AGR_DEVICE_SOURCE;
    SELECT @MaxBridgeKey = MAX(MIG_ROW_ID) FROM energy.dbo.VW_MIG_AGR_DEVICE_SOURCE;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_AGR_DEVICE',
        @TargetTable    = 'LS_005_01_AGR_DEV_TR',
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
        @SkippedCount   = @SkippedCount  OUTPUT,
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
            FROM energy.dbo.VW_MIG_AGR_DEVICE_SOURCE s
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

            INSERT INTO energy.dbo.LS_005_01_AGR_DEV_TR (
                ABYS_MIG_ROW_ID, ABYS_AGREEMENT_ID,
                DEVID, AGRID,
                CAPACITY, WORKDAY, WORKHOUR, FEE, EXCNR, BLIND_PLUG,
                ISACTIVE, DEMANDTYPE,
                ADDUSER, ADDDATE, UPDUSER, UPDDATE,
                ABYS_DEV_ID, ABYS_DEVICE_KIND,
                ABYS_PROJECT_ID, ABYS_INSTALLATION_ID,
                ABYS_MARK_CODE, ABYS_MARK_VALUE
            )
            SELECT
                s.MIG_ROW_ID, s.ABYS_AGREEMENT_ID,
                s.DEVID, s.ABYS_AGREEMENT_ID,
                s.CAPACITY, s.WORKDAY, s.WORKHOUR, s.FEE, s.EXCNR, s.BLIND_PLUG,
                s.ISACTIVE, s.DEMANDTYPE,
                s.ADDUSER, s.ADDDATE, s.UPDUSER, s.UPDDATE,
                s.ABYS_DEV_ID, s.ABYS_DEVICE_KIND,
                s.ABYS_PROJECT_ID, s.ABYS_INSTALLATION_ID,
                s.ABYS_MARK_CODE, s.ABYS_MARK_VALUE
            FROM energy.dbo.VW_MIG_AGR_DEVICE_SOURCE s
            WHERE s.MIG_ROW_ID BETWEEN @BatchFrom AND @BatchTo
              AND NOT EXISTS (
                  SELECT 1
                  FROM energy.dbo.LS_005_01_AGR_DEV_TR t
                  WHERE t.ABYS_MIG_ROW_ID = s.MIG_ROW_ID
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
                        EXEC dbo.SP_MIG_AGR_DEV_INSERT_ONE
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

                    INSERT INTO energy.dbo.LS_005_01_AGR_DEV_TR (
                        ABYS_MIG_ROW_ID, ABYS_AGREEMENT_ID,
                        DEVID, AGRID,
                        CAPACITY, WORKDAY, WORKHOUR, FEE, EXCNR, BLIND_PLUG,
                        ISACTIVE, DEMANDTYPE,
                        ADDUSER, ADDDATE, UPDUSER, UPDDATE,
                        ABYS_DEV_ID, ABYS_DEVICE_KIND,
                        ABYS_PROJECT_ID, ABYS_INSTALLATION_ID,
                        ABYS_MARK_CODE, ABYS_MARK_VALUE
                    )
                    SELECT
                        s.MIG_ROW_ID, s.ABYS_AGREEMENT_ID,
                        s.DEVID, s.ABYS_AGREEMENT_ID,
                        s.CAPACITY, s.WORKDAY, s.WORKHOUR, s.FEE, s.EXCNR, s.BLIND_PLUG,
                        s.ISACTIVE, s.DEMANDTYPE,
                        s.ADDUSER, s.ADDDATE, s.UPDUSER, s.UPDDATE,
                        s.ABYS_DEV_ID, s.ABYS_DEVICE_KIND,
                        s.ABYS_PROJECT_ID, s.ABYS_INSTALLATION_ID,
                        s.ABYS_MARK_CODE, s.ABYS_MARK_VALUE
                    FROM energy.dbo.VW_MIG_AGR_DEVICE_SOURCE s
                    WHERE s.MIG_ROW_ID BETWEEN @BisectFrom AND @BisectMid
                      AND NOT EXISTS (
                          SELECT 1
                          FROM energy.dbo.LS_005_01_AGR_DEV_TR t
                          WHERE t.ABYS_MIG_ROW_ID = s.MIG_ROW_ID
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
    FROM energy.dbo.LS_005_01_AGR_DEV_TR;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_AGR_DEV_TR', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_AGR_DEV_TR
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


--truncate table LS_005_01_AGR_DEV_TR

  --EXEC energy.dbo.SP_MIGRATE_LS005_AGR_DEV @HARD_RESET = 1, @DEBUG = 1 , @BATCH_SIZE =50000;



-- 1) Setup + SP deploy (veya deploy_all)
-- 2) Migrate
--EXEC energy.dbo.SP_MIGRATE_LS005_AGR_FITMENTFEE @HARD_RESET = 1, @DEBUG = 1;
---- 3) AGR migrate sonrası
--EXEC energy.dbo.SP_MIG_WIRE_AGR_FITMENTFEE_AGRID @Debug = 1;

-- EXEC energy.dbo.SP_MIGRATE_LS005_AGR_DEV @HARD_RESET = 1, @DEBUG = 1;
-- EXEC energy.dbo.SP_MIG_WIRE_AGR_DEV_AGRID @Debug = 1;  -- AGR migrate sonrasi
--EXEC energy.dbo.SP_MIGRATE_LS005_AGR_DEV @HARD_RESET = 1,@DEBUG = 1;
--EXEC energy.dbo.SP_MIG_WIRE_AGR_DEV_AGRID @Debug = 1; 


--EXEC energy.dbo.SP_MIGRATE_LS005_AGR_SERVEQ @HARD_RESET = 1, @DEBUG = 1;
---- 3) AGR migrate sonrası AGRID wiring
--EXEC energy.dbo.SP_MIG_WIRE_AGR_SERVEQ_AGRID @Debug = 1;

 

--CREATE TABLE energy.dbo.LS_005_01_AGR_SERVEQ_TR (
--	LREF int IDENTITY(1,1) NOT NULL,
--	MID int NULL,
--	TID int NULL,
--	AGRID int NULL,
--	CALCPRESSID int NULL,
--	TYPE_ int NULL,
--	SNO nvarchar(50) COLLATE SQL_Latin1_General_CP1254_CI_AS NULL,
--	MIDOLD int NULL,
--	LASTENDEX int NULL,
--	PULSEVAL float NULL,
--	ILLEGALUSE bit DEFAULT 0 NULL,
--	STAMPNO nvarchar(50) COLLATE SQL_Latin1_General_CP1254_CI_AS NULL,
--	UPDDATE smalldatetime NULL,
--	UPDUSER int NULL,
--	ISACTIVE bit DEFAULT 0 NULL,
--	PROJECTFEE float NULL,
--	ITEMID int NULL,
--	LINEEXP nvarchar(300) COLLATE SQL_Latin1_General_CP1254_CI_AS NULL,
--	CAPACITY float NULL,
--	OLREF int NULL,
--	MOUNT_DATE smalldatetime NULL,
--	REMOVE_DATE smalldatetime NULL,
--	CONSTRAINT PK_LS_005_01_AGR_SERVEQ_TR PRIMARY KEY (LREF),
--	CONSTRAINT FK_LS_005_01_AGR_SERVEQ_TR_LS_005_ITEMS FOREIGN KEY (ITEMID) REFERENCES energy.dbo.LS_005_ITEMS(LREF),
--	CONSTRAINT FK_LS_005_01_AGR_SERVEQ_TR_LS_LOOKUP FOREIGN KEY (CALCPRESSID) REFERENCES energy.dbo.LS_LOOKUP_12022024(LREF),
--	CONSTRAINT FK_LS_005_01_AGR_SERVEQ_TR_LS_STC_MODEL FOREIGN KEY (MID) REFERENCES energy.dbo.LS_STC_MODEL(LREF)
--);
-- CREATE NONCLUSTERED INDEX IX_LS_005_01_AGR_SERVEQ_TR_AGRID ON energy.dbo.LS_005_01_AGR_SERVEQ_TR (  AGRID ASC  )  
--	 WITH (  PAD_INDEX = OFF ,FILLFACTOR = 50   ,SORT_IN_TEMPDB = OFF , IGNORE_DUP_KEY = OFF , STATISTICS_NORECOMPUTE = OFF , ONLINE = OFF , ALLOW_ROW_LOCKS = ON , ALLOW_PAGE_LOCKS = ON  )
--	 ON [PRIMARY ] ;
-- CREATE NONCLUSTERED INDEX IX_LS_005_01_AGR_SERVEQ_TR_SNO ON energy.dbo.LS_005_01_AGR_SERVEQ_TR (  SNO ASC  )  
--	 WITH (  PAD_INDEX = OFF ,FILLFACTOR = 50   ,SORT_IN_TEMPDB = OFF , IGNORE_DUP_KEY = OFF , STATISTICS_NORECOMPUTE = OFF , ONLINE = OFF , ALLOW_ROW_LOCKS = ON , ALLOW_PAGE_LOCKS = ON  )
--	 ON [PRIMARY ] ;
-- CREATE NONCLUSTERED INDEX IX_WO ON energy.dbo.LS_005_01_AGR_SERVEQ_TR (  ITEMID ASC  )  
--	 WITH (  PAD_INDEX = OFF ,FILLFACTOR = 100  ,SORT_IN_TEMPDB = OFF , IGNORE_DUP_KEY = OFF , STATISTICS_NORECOMPUTE = OFF , ONLINE = OFF , ALLOW_ROW_LOCKS = ON , ALLOW_PAGE_LOCKS = ON  )
--	 ON [PRIMARY ] ;
-- CREATE NONCLUSTERED INDEX energy_LS_005_01_AGR_SERVEQ_TR_STAMPNO_ISACTIVE_ITEMID ON energy.dbo.LS_005_01_AGR_SERVEQ_TR (  STAMPNO ASC  , ISACTIVE ASC  , ITEMID ASC  )  
--	 WITH (  PAD_INDEX = OFF ,FILLFACTOR = 100  ,SORT_IN_TEMPDB = OFF , IGNORE_DUP_KEY = OFF , STATISTICS_NORECOMPUTE = OFF , ONLINE = OFF , ALLOW_ROW_LOCKS = ON , ALLOW_PAGE_LOCKS = ON  )
--	 ON [PRIMARY ] ;
-- CREATE NONCLUSTERED INDEX idx_serveq_itemid ON energy.dbo.LS_005_01_AGR_SERVEQ_TR (  ITEMID ASC  , LREF DESC  )  
--	 INCLUDE ( STAMPNO ) 
--	 WITH (  PAD_INDEX = OFF ,FILLFACTOR = 100  ,SORT_IN_TEMPDB = OFF , IGNORE_DUP_KEY = OFF , STATISTICS_NORECOMPUTE = OFF , ONLINE = OFF , ALLOW_ROW_LOCKS = ON , ALLOW_PAGE_LOCKS = ON  )
--	 ON [PRIMARY ] ;

