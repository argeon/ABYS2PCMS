/* ============================================================
   SCRIPT_ID : MASTER_ITEMS_MIGRATE
   SCRIPT_NO : 241
   FILE      : 241_MASTER_ITEMS__migrate.sql
   VERSION   : 4
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_ITEMS
-- Kaynak  : izgazMGR.dbo.LS_ITEMS (MIG_ROW_ID köprü)
-- Hedef   : energy.dbo.LS_005_ITEMS
-- LREF    ← METER_ID (IDENTITY_INSERT ON → insert → OFF)
--
-- Endeks: ABYS_MTR_LAST_INDEX (sayaç) + ABYS_INS/KORR; LASTENDEX view'da COALESCE
--
-- PK hatasi (ornegin LREF=430):
--   1) Kaynakta ayni METER_ID birden fazla MIG_ROW_ID (CTAS join fan-out)
--   2) Hedefte native LREF zaten var (HARD_RESET yalniz ABYS satirlarini siler)
-- Batch INSERT: PARTITION BY METER_ID (ilk MIG_ROW_ID) + LREF/ABYS skip
-- ============================================================
USE energy;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_ITEMS_HARD_RESET
    @DELETE_BATCH INT = 5000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @TotalStr VARCHAR(20), @MaxLref INT;

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_ITEMS ABYS kayitlari (batch=%d) ***', 0, 1, @DELETE_BATCH) WITH NOWAIT;

    SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS OFF;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_005_ITEMS
        WHERE ABYS_MIG_ROW_ID IS NOT NULL;

        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;

        SET @TotalDeleted += @Deleted;
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET silindi: +%d (toplam %s)', 0, 1, @Deleted, @TotalStr) WITH NOWAIT;
    END

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_ITEMS;

    DBCC CHECKIDENT('energy.dbo.LS_005_ITEMS', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s, CHECKIDENT=%d', 0, 1, @TotalStr, @MaxLref) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_ITEMS_INSERT_ONE
    @MigRowID    BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_ITEMS t
        WHERE t.ABYS_MIG_ROW_ID = @MigRowID
    )
        RETURN;

    IF EXISTS (
        SELECT 1
        FROM energy.dbo.LS_005_ITEMS t
        INNER JOIN energy.dbo.VW_MIG_LS005_ITEMS_SOURCE s ON s.MIG_ROW_ID = @MigRowID
        WHERE t.LREF = CAST(s.METER_ID AS INT)
           OR t.ABYS_METER_ID = s.METER_ID
    )
        RETURN;

    SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS OFF;
    SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS ON;

    BEGIN TRY
        INSERT INTO energy.dbo.LS_005_ITEMS (
            LREF,
            ABYS_MIG_ROW_ID, ABYS_METER_ID, ABYS_OLREF, ABYS_INSTALLATION_ID,
            ABYS_WAREHOUSE, ABYS_MTR_LAST_INDEX, ABYS_INS_LAST_INDEX, ABYS_KORR_LAST_INDEX,
            ABYS_READING_DATE, ABYS_KORR_READING_DATE,
            ABYS_METER_MODEL, ABYS_METER_TYPE_ID, ABYS_MARK, ABYS_METER_KIND,
            MID, DEFN, ACCCODE, STOCKCODE, SPECODE, LASTENDEX,
            SNNO_TEXT, SNNO_NR, WAREHOUSE, SUPLID, STATID, ISACTIVE,
            ADDUSER, ADDDATE, UPDUSER, UPDDATE,
            CNT_DIGIT, CNT_DIRECTION, INV_DATE, INV_NO, OLREF,
            PRODDATE, CALIBRATIONDATE, CALIBRATIONCOUNT, CALIBRATIONFIRM,
            Cap, Basinc, Tip, HAS_CORRECTOR_MODULE,
            MARK_REF, METER_CLASS_REF, METER_DIAMETER_REF, METER_PRESSURE_REF,
            DESCRIPTION
        )
        SELECT
            CAST(s.METER_ID AS INT),
            s.MIG_ROW_ID, s.METER_ID, s.ABYS_OLREF_RAW, s.ABYS_INSTALLATION_ID,
            s.ABYS_WAREHOUSE, s.ABYS_MTR_LAST_INDEX, s.ABYS_INS_LAST_INDEX, s.ABYS_KORR_LAST_INDEX,
            s.ABYS_READING_DATE, s.ABYS_KORR_READING_DATE,
            s.ABYS_METER_MODEL, s.ABYS_METER_TYPE_ID, s.ABYS_MARK, s.ABYS_METER_KIND,
            s.RESOLVED_MID, s.DEFN, s.ACCCODE, s.STOCKCODE, NULL, s.LASTENDEX,
            s.SNNO_TEXT, s.SNNO_NR, s.RESOLVED_WH, s.SUPLID, s.STATID, s.ISACTIVE,
            s.ADDUSER, s.ADDDATE, s.UPDUSER, s.UPDDATE,
            s.CNT_DIGIT, s.CNT_DIRECTION, s.INV_DATE, s.INV_NO, s.OLREF,
            s.PRODDATE, s.CALIBRATIONDATE, s.CALIBRATIONCOUNT, s.CALIBRATIONFIRM,
            s.Cap, s.Basinc, s.Tip, s.HAS_CORRECTOR_MODULE,
            s.MARK_REF, s.METER_CLASS_REF, s.METER_DIAMETER_REF, s.METER_PRESSURE_REF,
            s.DESCRIPTION
        FROM energy.dbo.VW_MIG_LS005_ITEMS_SOURCE s
        WHERE s.MIG_ROW_ID = @MigRowID;

        SET @RowInserted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
    END TRY
    BEGIN CATCH
        SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS OFF;
        THROW;
    END CATCH

    SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS OFF;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_ITEMS
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
        @MigrationCode  VARCHAR(50)      = 'LS_005_ITEMS',
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

    EXEC dbo.SP_MIG_ITEMS_VALIDATE_SOURCE @RaiseOnMissing = 1;
    EXEC dbo.SP_MIG_ITEMS_PREP_SOURCE;

    IF @HARD_RESET = 1
    BEGIN
        SET @ExecMode = 'HARD_RESET';
        EXEC dbo.SP_MIG_ITEMS_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
        SET @RESUME = 0;
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM energy.dbo.VW_MIG_LS005_ITEMS_SOURCE;
    SELECT @MaxBridgeKey = MAX(MIG_ROW_ID) FROM energy.dbo.VW_MIG_LS005_ITEMS_SOURCE;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_ITEMS',
        @TargetTable    = 'LS_005_ITEMS',
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
            FROM energy.dbo.VW_MIG_LS005_ITEMS_SOURCE s
            WHERE s.MIG_ROW_ID > @LastBridgeKey
            ORDER BY s.MIG_ROW_ID ASC
        ) t;

        IF @BatchTo IS NULL BREAK;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = 'Batch ' + CAST(@BatchNo AS VARCHAR(10))
                + ' | MIG_ROW_ID ' + CAST(@BatchFrom AS VARCHAR(20))
                + '-' + CAST(@BatchTo AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        BEGIN TRY
            BEGIN TRANSACTION;
            SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS OFF;
            SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS ON;

            INSERT INTO energy.dbo.LS_005_ITEMS (
                LREF,
                ABYS_MIG_ROW_ID, ABYS_METER_ID, ABYS_OLREF, ABYS_INSTALLATION_ID,
                ABYS_WAREHOUSE, ABYS_MTR_LAST_INDEX, ABYS_INS_LAST_INDEX, ABYS_KORR_LAST_INDEX,
                ABYS_READING_DATE, ABYS_KORR_READING_DATE,
                ABYS_METER_MODEL, ABYS_METER_TYPE_ID, ABYS_MARK, ABYS_METER_KIND,
                MID, DEFN, ACCCODE, STOCKCODE, SPECODE, LASTENDEX,
                SNNO_TEXT, SNNO_NR, WAREHOUSE, SUPLID, STATID, ISACTIVE,
                ADDUSER, ADDDATE, UPDUSER, UPDDATE,
                CNT_DIGIT, CNT_DIRECTION, INV_DATE, INV_NO, OLREF,
                PRODDATE, CALIBRATIONDATE, CALIBRATIONCOUNT, CALIBRATIONFIRM,
                Cap, Basinc, Tip, HAS_CORRECTOR_MODULE,
                MARK_REF, METER_CLASS_REF, METER_DIAMETER_REF, METER_PRESSURE_REF,
                DESCRIPTION
            )
            SELECT
                CAST(s.METER_ID AS INT),
                s.MIG_ROW_ID, s.METER_ID, s.ABYS_OLREF_RAW, s.ABYS_INSTALLATION_ID,
                s.ABYS_WAREHOUSE, s.ABYS_MTR_LAST_INDEX, s.ABYS_INS_LAST_INDEX, s.ABYS_KORR_LAST_INDEX,
                s.ABYS_READING_DATE, s.ABYS_KORR_READING_DATE,
                s.ABYS_METER_MODEL, s.ABYS_METER_TYPE_ID, s.ABYS_MARK, s.ABYS_METER_KIND,
                s.RESOLVED_MID, s.DEFN, s.ACCCODE, s.STOCKCODE, NULL, s.LASTENDEX,
                s.SNNO_TEXT, s.SNNO_NR, s.RESOLVED_WH, s.SUPLID, s.STATID, s.ISACTIVE,
                s.ADDUSER, s.ADDDATE, s.UPDUSER, s.UPDDATE,
                s.CNT_DIGIT, s.CNT_DIRECTION, s.INV_DATE, s.INV_NO, s.OLREF,
                s.PRODDATE, s.CALIBRATIONDATE, s.CALIBRATIONCOUNT, s.CALIBRATIONFIRM,
                s.Cap, s.Basinc, s.Tip, s.HAS_CORRECTOR_MODULE,
                s.MARK_REF, s.METER_CLASS_REF, s.METER_DIAMETER_REF, s.METER_PRESSURE_REF,
                s.DESCRIPTION
            FROM (
                SELECT
                    src.*,
                    ROW_NUMBER() OVER (
                        PARTITION BY CAST(src.METER_ID AS INT)
                        ORDER BY src.MIG_ROW_ID
                    ) AS rn_meter
                FROM energy.dbo.VW_MIG_LS005_ITEMS_SOURCE src
                WHERE src.MIG_ROW_ID BETWEEN @BatchFrom AND @BatchTo
            ) s
            WHERE s.rn_meter = 1
              AND NOT EXISTS (
                  SELECT 1 FROM energy.dbo.LS_005_ITEMS t
                  WHERE t.ABYS_MIG_ROW_ID = s.MIG_ROW_ID
                     OR t.LREF = CAST(s.METER_ID AS INT)
                     OR t.ABYS_METER_ID = s.METER_ID
              );

            SET @RowCount = @@ROWCOUNT;
            SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS OFF;
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
            SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS OFF;
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
                        EXEC dbo.SP_MIG_ITEMS_INSERT_ONE
                            @MigRowID = @BisectFrom, @RowInserted = @RowInserted OUTPUT;

                        IF @RowInserted = 1
                            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                                @RunID = @RunID, @TableRunID = @TableRunID,
                                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                                @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom,
                                @BridgeTo = @BisectFrom, @RowCount = 1;
                    END TRY
                    BEGIN CATCH
                        SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS OFF;
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
                    SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS OFF;
                    SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS ON;

                    INSERT INTO energy.dbo.LS_005_ITEMS (
                        LREF,
                        ABYS_MIG_ROW_ID, ABYS_METER_ID, ABYS_OLREF, ABYS_INSTALLATION_ID,
                        ABYS_WAREHOUSE, ABYS_MTR_LAST_INDEX, ABYS_INS_LAST_INDEX, ABYS_KORR_LAST_INDEX,
                        ABYS_READING_DATE, ABYS_KORR_READING_DATE,
                        ABYS_METER_MODEL, ABYS_METER_TYPE_ID, ABYS_MARK, ABYS_METER_KIND,
                        MID, DEFN, ACCCODE, STOCKCODE, SPECODE, LASTENDEX,
                        SNNO_TEXT, SNNO_NR, WAREHOUSE, SUPLID, STATID, ISACTIVE,
                        ADDUSER, ADDDATE, UPDUSER, UPDDATE,
                        CNT_DIGIT, CNT_DIRECTION, INV_DATE, INV_NO, OLREF,
                        PRODDATE, CALIBRATIONDATE, CALIBRATIONCOUNT, CALIBRATIONFIRM,
                        Cap, Basinc, Tip, HAS_CORRECTOR_MODULE,
                        MARK_REF, METER_CLASS_REF, METER_DIAMETER_REF, METER_PRESSURE_REF,
                        DESCRIPTION
                    )
                    SELECT
                        CAST(s.METER_ID AS INT),
                        s.MIG_ROW_ID, s.METER_ID, s.ABYS_OLREF_RAW, s.ABYS_INSTALLATION_ID,
                        s.ABYS_WAREHOUSE, s.ABYS_MTR_LAST_INDEX, s.ABYS_INS_LAST_INDEX, s.ABYS_KORR_LAST_INDEX,
                        s.ABYS_READING_DATE, s.ABYS_KORR_READING_DATE,
                        s.ABYS_METER_MODEL, s.ABYS_METER_TYPE_ID, s.ABYS_MARK, s.ABYS_METER_KIND,
                        s.RESOLVED_MID, s.DEFN, s.ACCCODE, s.STOCKCODE, NULL, s.LASTENDEX,
                        s.SNNO_TEXT, s.SNNO_NR, s.RESOLVED_WH, s.SUPLID, s.STATID, s.ISACTIVE,
                        s.ADDUSER, s.ADDDATE, s.UPDUSER, s.UPDDATE,
                        s.CNT_DIGIT, s.CNT_DIRECTION, s.INV_DATE, s.INV_NO, s.OLREF,
                        s.PRODDATE, s.CALIBRATIONDATE, s.CALIBRATIONCOUNT, s.CALIBRATIONFIRM,
                        s.Cap, s.Basinc, s.Tip, s.HAS_CORRECTOR_MODULE,
                        s.MARK_REF, s.METER_CLASS_REF, s.METER_DIAMETER_REF, s.METER_PRESSURE_REF,
                        s.DESCRIPTION
                    FROM (
                        SELECT
                            src.*,
                            ROW_NUMBER() OVER (
                                PARTITION BY CAST(src.METER_ID AS INT)
                                ORDER BY src.MIG_ROW_ID
                            ) AS rn_meter
                        FROM energy.dbo.VW_MIG_LS005_ITEMS_SOURCE src
                        WHERE src.MIG_ROW_ID BETWEEN @BisectFrom AND @BisectMid
                    ) s
                    WHERE s.rn_meter = 1
                      AND NOT EXISTS (
                          SELECT 1 FROM energy.dbo.LS_005_ITEMS t
                          WHERE t.ABYS_MIG_ROW_ID = s.MIG_ROW_ID
                             OR t.LREF = CAST(s.METER_ID AS INT)
                             OR t.ABYS_METER_ID = s.METER_ID
                      );

                    SET @BisectRows = @@ROWCOUNT;
                    SET @BisectLogFrom = @BisectFrom;
                    SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS OFF;
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
                    SET IDENTITY_INSERT energy.dbo.LS_005_ITEMS OFF;
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

        IF @DEBUG = 1
        BEGIN
            SET @Msg = '  → OK=' + CAST(@InsertedCount AS VARCHAR(20))
                + ' ERR=' + CAST(@ErrorCount AS VARCHAR(20))
                + ' LastMigRow=' + CAST(@LastBridgeKey AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_ITEMS;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_ITEMS', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_ITEMS
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

   --EXEC energy.dbo.SP_MIGRATE_LS005_ITEMS
   --     @HARD_RESET = 1, @BATCH_SIZE = 5000, @DEBUG = 1;

