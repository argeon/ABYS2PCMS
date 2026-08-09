/* ============================================================
   SCRIPT_ID : AGR_SERVEQ_MIGRATE
   SCRIPT_NO : 341
   FILE      : 341_AGR_SERVEQ__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_AGR_SERVEQ
-- Kaynak  : izgazMGR.dbo.LS_AGR_SERVQ (VW_MIG_AGR_SERVEQ_TR_SOURCE)
-- Hedef   : energy.dbo.LS_005_01_AGR_SERVEQ_TR
-- Bridge  : MIG_ROW_ID → ABYS_MIG_ROW_ID (LREF = IDENTITY)
-- AGRID   : kaynak AGRID (= AGR.LREF; wire yok)
-- ISACTIVE: kaynak; aktif AGR → SP_MIG_AGR_SERVEQ_SYNC_ISACTIVE
--           (KUL ISACTIVE 910'da set edildikten sonra tekrar çağır)
-- CALCPRESS: SERVEQ sonrası AGR.CALCPRESSID ← SERVEQ
--            (AGR CTAS sadece 21→34; SERVEQ tam USED_PRESSURE lookup)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Aktif sözleşmeye bağlı pasif SERVEQ satırlarını açar (AGRID = AGR.LREF)
CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_SERVEQ_SYNC_ISACTIVE
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Updated INT = 0;

    IF OBJECT_ID('energy.dbo.LS_005_01_AGR', 'U') IS NULL
    BEGIN
        IF @DEBUG = 1
            RAISERROR('SP_MIG_AGR_SERVEQ_SYNC_ISACTIVE: LS_005_01_AGR yok, atlandi', 0, 1) WITH NOWAIT;
        RETURN;
    END

    UPDATE srv
    SET srv.ISACTIVE = 1
    FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR srv
    INNER JOIN energy.dbo.LS_005_01_AGR agr ON agr.LREF = srv.AGRID
    WHERE ISNULL(srv.ISACTIVE, 0) = 0
      AND ISNULL(agr.ISACTIVE, 0) = 1;

    SET @Updated = @@ROWCOUNT;

    IF @DEBUG = 1
    BEGIN
        DECLARE @Msg VARCHAR(200) = 'SP_MIG_AGR_SERVEQ_SYNC_ISACTIVE: ISACTIVE=1 yapilan satir='
            + CAST(@Updated AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

-- SERVEQ aktarimi sonrasi: AGR.CALCPRESSID ← SERVEQ.CALCPRESSID (COUNTERID = ITEMID)
CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_SYNC_CALCPRESS_FROM_SERVEQ
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Updated INT = 0;

    IF OBJECT_ID('energy.dbo.LS_005_01_AGR', 'U') IS NULL
       OR OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR', 'U') IS NULL
    BEGIN
        IF @DEBUG = 1
            RAISERROR('SP_MIG_AGR_SYNC_CALCPRESS_FROM_SERVEQ: AGR/SERVEQ yok, atlandi', 0, 1) WITH NOWAIT;
        RETURN;
    END

    ;WITH sq AS (
        SELECT
            ITEMID,
            CALCPRESSID,
            ROW_NUMBER() OVER (
                PARTITION BY ITEMID
                ORDER BY
                    CASE WHEN ISNULL(ISACTIVE, 0) = 1 THEN 0 ELSE 1 END,
                    CASE WHEN RTRIM(TP2) = N'KUL' THEN 0 ELSE 1 END,
                    LREF DESC
            ) AS rn
        FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR
        WHERE ITEMID IS NOT NULL
          AND CALCPRESSID IS NOT NULL
          AND CALCPRESSID > 0  -- -99 unmapped haric
    )
    UPDATE agr
    SET agr.CALCPRESSID = sq.CALCPRESSID
    FROM energy.dbo.LS_005_01_AGR agr
    INNER JOIN sq ON sq.ITEMID = agr.COUNTERID AND sq.rn = 1
    WHERE ISNULL(agr.COUNTERID, 0) <> 0
      AND ISNULL(agr.CALCPRESSID, -1) <> sq.CALCPRESSID;

    SET @Updated = @@ROWCOUNT;

    IF @DEBUG = 1
    BEGIN
        DECLARE @Msg VARCHAR(200) = 'SP_MIG_AGR_SYNC_CALCPRESS_FROM_SERVEQ: guncellenen AGR='
            + CAST(@Updated AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_SERVEQ_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR t
        WHERE t.ABYS_MIG_ROW_ID = @CurID
    )
        RETURN;

    INSERT INTO energy.dbo.LS_005_01_AGR_SERVEQ_TR (
        ABYS_MIG_ROW_ID, ABYS_AGREEMENT_ID,
        MID, TID, AGRID, CALCPRESSID, TYPE_, SNO, MIDOLD, LASTENDEX,
        PULSEVAL, ILLEGALUSE, STAMPNO, UPDDATE, UPDUSER, ISACTIVE,
        PROJECTFEE, ITEMID, LINEEXP, CAPACITY, OLREF, MOUNT_DATE, REMOVE_DATE,
        ABYS_MID, ABYS_TID, ABYS_MIDOLD, ABYS_ITEMID,
        ABYS_USED_PRESSURE, ABYS_LASTENDEX, TP2
    )
    SELECT
        s.MIG_ROW_ID, s.ABYS_AGREEMENT_ID,
        s.MID, s.TID, s.ABYS_AGREEMENT_ID, s.CALCPRESSID, s.TYPE_, s.SNO, s.MIDOLD, s.LASTENDEX,
        s.PULSEVAL, s.ILLEGALUSE, s.STAMPNO, s.UPDDATE, s.UPDUSER, s.ISACTIVE,
        s.PROJECTFEE, s.ITEMID, s.LINEEXP, s.CAPACITY, s.OLREF, s.MOUNT_DATE, s.REMOVE_DATE,
        s.ABYS_MID, s.ABYS_TID, s.ABYS_MIDOLD, s.ABYS_ITEMID,
        s.ABYS_USED_PRESSURE, s.ABYS_LASTENDEX, s.TP2
    FROM energy.dbo.VW_MIG_AGR_SERVEQ_TR_SOURCE s
    WHERE s.MIG_ROW_ID = @CurID;

    SET @RowInserted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_SERVEQ_HARD_RESET
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @MaxLref INT;

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_AGR_SERVEQ_TR ABYS kayitlari ***', 0, 1) WITH NOWAIT;

    DELETE FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR
    WHERE ABYS_MIG_ROW_ID IS NOT NULL;

    SET @Deleted = @@ROWCOUNT;

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_AGR_SERVEQ_TR', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        DECLARE @Msg VARCHAR(100) = '  silindi: ' + CAST(@Deleted AS VARCHAR(20))
            + ', CHECKIDENT=' + CAST(@MaxLref AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_AGR_SERVEQ
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
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_AGR_SERVEQ_TR',
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

    EXEC dbo.SP_MIG_AGR_SERVEQ_PREP_SOURCE;
    EXEC dbo.SP_MIG_AGR_SERVEQ_VALIDATE_SOURCE @RaiseOnMissing = 1;
    EXEC dbo.SP_MIG_AGR_SERVEQ_VALIDATE_TARGET @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_AGR_SERVEQ_HARD_RESET @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM energy.dbo.VW_MIG_AGR_SERVEQ_TR_SOURCE;
    SELECT @MaxBridgeKey = MAX(MIG_ROW_ID) FROM energy.dbo.VW_MIG_AGR_SERVEQ_TR_SOURCE;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_AGR_SERVQ',
        @TargetTable    = 'LS_005_01_AGR_SERVEQ_TR',
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
            FROM energy.dbo.VW_MIG_AGR_SERVEQ_TR_SOURCE s
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

            INSERT INTO energy.dbo.LS_005_01_AGR_SERVEQ_TR (
                ABYS_MIG_ROW_ID, ABYS_AGREEMENT_ID,
                MID, TID, AGRID, CALCPRESSID, TYPE_, SNO, MIDOLD, LASTENDEX,
                PULSEVAL, ILLEGALUSE, STAMPNO, UPDDATE, UPDUSER, ISACTIVE,
                PROJECTFEE, ITEMID, LINEEXP, CAPACITY, OLREF, MOUNT_DATE, REMOVE_DATE,
                ABYS_MID, ABYS_TID, ABYS_MIDOLD, ABYS_ITEMID,
                ABYS_USED_PRESSURE, ABYS_LASTENDEX, TP2
            )
            SELECT
                s.MIG_ROW_ID, s.ABYS_AGREEMENT_ID,
                s.MID, s.TID, s.ABYS_AGREEMENT_ID, s.CALCPRESSID, s.TYPE_, s.SNO, s.MIDOLD, s.LASTENDEX,
                s.PULSEVAL, s.ILLEGALUSE, s.STAMPNO, s.UPDDATE, s.UPDUSER, s.ISACTIVE,
                s.PROJECTFEE, s.ITEMID, s.LINEEXP, s.CAPACITY, s.OLREF, s.MOUNT_DATE, s.REMOVE_DATE,
                s.ABYS_MID, s.ABYS_TID, s.ABYS_MIDOLD, s.ABYS_ITEMID,
                s.ABYS_USED_PRESSURE, s.ABYS_LASTENDEX, s.TP2
            FROM energy.dbo.VW_MIG_AGR_SERVEQ_TR_SOURCE s
            WHERE s.MIG_ROW_ID BETWEEN @BatchFrom AND @BatchTo
              AND NOT EXISTS (
                  SELECT 1
                  FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR t
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
                        EXEC dbo.SP_MIG_AGR_SERVEQ_INSERT_ONE
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

                    INSERT INTO energy.dbo.LS_005_01_AGR_SERVEQ_TR (
                        ABYS_MIG_ROW_ID, ABYS_AGREEMENT_ID,
                        MID, TID, AGRID, CALCPRESSID, TYPE_, SNO, MIDOLD, LASTENDEX,
                        PULSEVAL, ILLEGALUSE, STAMPNO, UPDDATE, UPDUSER, ISACTIVE,
                        PROJECTFEE, ITEMID, LINEEXP, CAPACITY, OLREF, MOUNT_DATE, REMOVE_DATE,
                        ABYS_MID, ABYS_TID, ABYS_MIDOLD, ABYS_ITEMID,
                        ABYS_USED_PRESSURE, ABYS_LASTENDEX, TP2
                    )
                    SELECT
                        s.MIG_ROW_ID, s.ABYS_AGREEMENT_ID,
                        s.MID, s.TID, s.ABYS_AGREEMENT_ID, s.CALCPRESSID, s.TYPE_, s.SNO, s.MIDOLD, s.LASTENDEX,
                        s.PULSEVAL, s.ILLEGALUSE, s.STAMPNO, s.UPDDATE, s.UPDUSER, s.ISACTIVE,
                        s.PROJECTFEE, s.ITEMID, s.LINEEXP, s.CAPACITY, s.OLREF, s.MOUNT_DATE, s.REMOVE_DATE,
                        s.ABYS_MID, s.ABYS_TID, s.ABYS_MIDOLD, s.ABYS_ITEMID,
                        s.ABYS_USED_PRESSURE, s.ABYS_LASTENDEX, s.TP2
                    FROM energy.dbo.VW_MIG_AGR_SERVEQ_TR_SOURCE s
                    WHERE s.MIG_ROW_ID BETWEEN @BisectFrom AND @BisectMid
                      AND NOT EXISTS (
                          SELECT 1
                          FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR t
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
    FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_AGR_SERVEQ_TR', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR
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

    -- AGR.ISACTIVE hazirsa (KUL icin 910 sonrasi tekrar calistir)
    EXEC energy.dbo.SP_MIG_AGR_SERVEQ_SYNC_ISACTIVE @DEBUG = @DEBUG;

    -- AGR.CALCPRESSID ← SERVEQ (COUNTERID = ITEMID); 910 sonrasi da tekrar calistirilabilir
    EXEC energy.dbo.SP_MIG_AGR_SYNC_CALCPRESS_FROM_SERVEQ @DEBUG = @DEBUG;

    EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY
        @MigrationCode = @MigrationCode, @RunID = @RunID;
END
GO

-- EXEC energy.dbo.SP_MIGRATE_LS005_AGR_SERVEQ @HARD_RESET = 1, @DEBUG = 1;
-- EXEC energy.dbo.SP_MIG_AGR_SERVEQ_SYNC_ISACTIVE @DEBUG = 1;  -- 910 KUL ISACTIVE sonrasi
-- EXEC energy.dbo.SP_MIG_AGR_SYNC_CALCPRESS_FROM_SERVEQ @DEBUG = 1;  -- SERVEQ sonrasi

