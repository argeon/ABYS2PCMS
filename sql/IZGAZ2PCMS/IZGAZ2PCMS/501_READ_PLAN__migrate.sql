/* ============================================================
   SCRIPT_ID : READ_PLAN_MIGRATE
   SCRIPT_NO : 501
   FILE      : 501_READ_PLAN__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- 



-- Kaynak  : izgazMGR.dbo.CS_READING_PLAN
-- Hedef   : energy.dbo.mgg_cbs_okuma_bolge
-- ============================================================
USE energy;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_READING_PLAN_HARD_RESET
    @DELETE_BATCH INT = 5000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @TotalStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: mgg_cbs_okuma_bolge ABYS kayitlari (batch=%d) ***', 0, 1, @DELETE_BATCH) WITH NOWAIT;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.mgg_cbs_okuma_bolge
        WHERE ABYS_MIG_ROW_ID IS NOT NULL;

        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;

        SET @TotalDeleted += @Deleted;
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET silindi: +%d (toplam %s)', 0, 1, @Deleted, @TotalStr) WITH NOWAIT;
    END

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s', 0, 1, @TotalStr) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_READING_PLAN_UPDATE_ABYS
    @MigRowFrom   BIGINT = NULL,
    @MigRowTo     BIGINT = NULL,
    @SirketKodu   INT    = NULL,
    @UpdatedRows  INT    = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @UpdatedRows = 0;

    UPDATE t
    SET
        t.OkumaBolgeAdi                   = s.OkumaBolgeAdi,
        t.KonumWkt                        = s.KonumWkt,
        t.ent_datetime                    = s.ent_datetime,
        t.ABYS_MIG_ROW_ID                 = s.MIG_ROW_ID,
        t.ABYS_ID                         = s.ABYS_ID,
        t.ABYS_READING_LAYER_ID           = s.ABYS_READING_LAYER_ID,
        t.ABYS_BOOK_ID                    = s.ABYS_BOOK_ID,
        t.ABYS_CODE                       = s.ABYS_CODE,
        t.ABYS_READING_DAY                = s.ABYS_READING_DAY,
        t.ABYS_TERMINAL_SYNC_CLIENT_ID    = s.ABYS_TERMINAL_SYNC_CLIENT_ID,
        t.ABYS_LOCATION_WKT               = s.ABYS_LOCATION_WKT,
        t.ABYS_MAX_SUBSCRIBER_COUNT       = s.ABYS_MAX_SUBSCRIBER_COUNT,
        t.ABYS_CREATED_USER_ID            = s.ABYS_CREATED_USER_ID,
        t.ABYS_CREATED_TIMESTAMP          = s.ABYS_CREATED_TIMESTAMP,
        t.ABYS_UPDATED_USER_ID            = s.ABYS_UPDATED_USER_ID,
        t.ABYS_UPDATED_TIMESTAMP          = s.ABYS_UPDATED_TIMESTAMP,
        t.ABYS_VERSION                    = s.ABYS_VERSION,
        t.ABYS_FIRST_READING_ORDER_NUMBER = s.ABYS_FIRST_READING_ORDER_NUMBER,
        t.ABYS_LAST_READING_ORDER_NUMBER  = s.ABYS_LAST_READING_ORDER_NUMBER,
        t.ABYS_TERMINAL_ORDER             = s.ABYS_TERMINAL_ORDER,
        t.ABYS_IS_ACTIVE                  = s.ABYS_IS_ACTIVE
    FROM energy.dbo.mgg_cbs_okuma_bolge t
    INNER JOIN energy.dbo.VW_MIG_READING_PLAN_SOURCE s
        ON t.ABYS_ID = s.ABYS_ID
        OR t.ABYS_MIG_ROW_ID = s.MIG_ROW_ID
        OR (
            @SirketKodu IS NOT NULL
            AND t.SirketKodu = @SirketKodu
            AND t.ABYS_ID IS NULL
            AND t.ABYS_MIG_ROW_ID IS NULL
            AND t.OkumaBolgeAdi COLLATE DATABASE_DEFAULT = s.OkumaBolgeAdi COLLATE DATABASE_DEFAULT
        )
    WHERE (@MigRowFrom IS NULL OR s.MIG_ROW_ID >= @MigRowFrom)
      AND (@MigRowTo   IS NULL OR s.MIG_ROW_ID <= @MigRowTo);

    SET @UpdatedRows = @@ROWCOUNT;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_READING_PLAN_INSERT_ONE
    @MigRowID     BIGINT,
    @SirketKodu   INT,
    @RowInserted  BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    DECLARE @UpdatedRows INT = 0;

    IF EXISTS (
        SELECT 1
        FROM energy.dbo.mgg_cbs_okuma_bolge t
        WHERE t.ABYS_MIG_ROW_ID = @MigRowID
    )
    BEGIN
        EXEC dbo.SP_MIG_READING_PLAN_UPDATE_ABYS
            @MigRowFrom = @MigRowID, @MigRowTo = @MigRowID,
            @SirketKodu = @SirketKodu, @UpdatedRows = @UpdatedRows OUTPUT;
        SET @RowInserted = CASE WHEN @UpdatedRows > 0 THEN 1 ELSE 0 END;
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM energy.dbo.mgg_cbs_okuma_bolge t
        INNER JOIN energy.dbo.VW_MIG_READING_PLAN_SOURCE s
            ON s.MIG_ROW_ID = @MigRowID
        WHERE t.ABYS_ID = s.ABYS_ID
    )
    BEGIN
        EXEC dbo.SP_MIG_READING_PLAN_UPDATE_ABYS
            @MigRowFrom = @MigRowID, @MigRowTo = @MigRowID,
            @SirketKodu = @SirketKodu, @UpdatedRows = @UpdatedRows OUTPUT;
        SET @RowInserted = CASE WHEN @UpdatedRows > 0 THEN 1 ELSE 0 END;
        RETURN;
    END

    INSERT INTO energy.dbo.mgg_cbs_okuma_bolge (
        OkumaBolgeAdi, KonumWkt, SirketKodu, ent_datetime,
        ABYS_MIG_ROW_ID, ABYS_ID, ABYS_READING_LAYER_ID, ABYS_BOOK_ID, ABYS_CODE,
        ABYS_READING_DAY, ABYS_TERMINAL_SYNC_CLIENT_ID, ABYS_LOCATION_WKT,
        ABYS_MAX_SUBSCRIBER_COUNT, ABYS_CREATED_USER_ID, ABYS_CREATED_TIMESTAMP,
        ABYS_UPDATED_USER_ID, ABYS_UPDATED_TIMESTAMP, ABYS_VERSION,
        ABYS_FIRST_READING_ORDER_NUMBER, ABYS_LAST_READING_ORDER_NUMBER,
        ABYS_TERMINAL_ORDER, ABYS_IS_ACTIVE
    )
    SELECT
        s.OkumaBolgeAdi, s.KonumWkt, @SirketKodu, s.ent_datetime,
        s.MIG_ROW_ID, s.ABYS_ID, s.ABYS_READING_LAYER_ID, s.ABYS_BOOK_ID, s.ABYS_CODE,
        s.ABYS_READING_DAY, s.ABYS_TERMINAL_SYNC_CLIENT_ID, s.ABYS_LOCATION_WKT,
        s.ABYS_MAX_SUBSCRIBER_COUNT, s.ABYS_CREATED_USER_ID, s.ABYS_CREATED_TIMESTAMP,
        s.ABYS_UPDATED_USER_ID, s.ABYS_UPDATED_TIMESTAMP, s.ABYS_VERSION,
        s.ABYS_FIRST_READING_ORDER_NUMBER, s.ABYS_LAST_READING_ORDER_NUMBER,
        s.ABYS_TERMINAL_ORDER, s.ABYS_IS_ACTIVE
    FROM energy.dbo.VW_MIG_READING_PLAN_SOURCE s
    WHERE s.MIG_ROW_ID = @MigRowID;

    SET @RowInserted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_CS_READING_PLAN_OKUMA_BOLGE
    @BATCH_SIZE   INT = 5000,
    @RESUME       BIT = 1,
    @HARD_RESET   BIT = 0,
    @MAX_ERROR    INT = 500,
    @BISECT_MIN   INT = 1,
    @SIRKET_KODU  INT = 4102,
    @DEBUG        BIT = 0
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'MGG_CBS_OKUMA_BOLGE',
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
        @UpdatedRows    INT              = 0;

    EXEC dbo.SP_MIG_READING_PLAN_VALIDATE_SOURCE @RaiseOnMissing = 1;
    EXEC dbo.SP_MIG_READING_PLAN_PREP_SOURCE;

    IF EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge')
          AND name = 'UX_MGG_OKUMA_BOLGE_ABYS_ID'
    )
        DROP INDEX UX_MGG_OKUMA_BOLGE_ABYS_ID ON energy.dbo.mgg_cbs_okuma_bolge;

    IF @HARD_RESET = 1
    BEGIN
        SET @ExecMode = 'HARD_RESET';
        EXEC dbo.SP_MIG_READING_PLAN_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
        SET @RESUME = 0;
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM energy.dbo.VW_MIG_READING_PLAN_SOURCE;
    SELECT @MaxBridgeKey = MAX(MIG_ROW_ID) FROM energy.dbo.VW_MIG_READING_PLAN_SOURCE;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'CS_READING_PLAN',
        @TargetTable    = 'mgg_cbs_okuma_bolge',
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
            + ' | SirketKodu=' + CAST(@SIRKET_KODU AS VARCHAR(10))
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
            FROM energy.dbo.VW_MIG_READING_PLAN_SOURCE s
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

            INSERT INTO energy.dbo.mgg_cbs_okuma_bolge (
                OkumaBolgeAdi, KonumWkt, SirketKodu, ent_datetime,
                ABYS_MIG_ROW_ID, ABYS_ID, ABYS_READING_LAYER_ID, ABYS_BOOK_ID, ABYS_CODE,
                ABYS_READING_DAY, ABYS_TERMINAL_SYNC_CLIENT_ID, ABYS_LOCATION_WKT,
                ABYS_MAX_SUBSCRIBER_COUNT, ABYS_CREATED_USER_ID, ABYS_CREATED_TIMESTAMP,
                ABYS_UPDATED_USER_ID, ABYS_UPDATED_TIMESTAMP, ABYS_VERSION,
                ABYS_FIRST_READING_ORDER_NUMBER, ABYS_LAST_READING_ORDER_NUMBER,
                ABYS_TERMINAL_ORDER, ABYS_IS_ACTIVE
            )
            SELECT
                s.OkumaBolgeAdi, s.KonumWkt, @SIRKET_KODU, s.ent_datetime,
                s.MIG_ROW_ID, s.ABYS_ID, s.ABYS_READING_LAYER_ID, s.ABYS_BOOK_ID, s.ABYS_CODE,
                s.ABYS_READING_DAY, s.ABYS_TERMINAL_SYNC_CLIENT_ID, s.ABYS_LOCATION_WKT,
                s.ABYS_MAX_SUBSCRIBER_COUNT, s.ABYS_CREATED_USER_ID, s.ABYS_CREATED_TIMESTAMP,
                s.ABYS_UPDATED_USER_ID, s.ABYS_UPDATED_TIMESTAMP, s.ABYS_VERSION,
                s.ABYS_FIRST_READING_ORDER_NUMBER, s.ABYS_LAST_READING_ORDER_NUMBER,
                s.ABYS_TERMINAL_ORDER, s.ABYS_IS_ACTIVE
            FROM energy.dbo.VW_MIG_READING_PLAN_SOURCE s
            WHERE s.MIG_ROW_ID BETWEEN @BatchFrom AND @BatchTo
              AND NOT EXISTS (
                  SELECT 1 FROM energy.dbo.mgg_cbs_okuma_bolge t
                  WHERE t.ABYS_MIG_ROW_ID = s.MIG_ROW_ID
                     OR t.ABYS_ID = s.ABYS_ID
              );

            SET @RowCount = @@ROWCOUNT;
            COMMIT TRANSACTION;

            EXEC dbo.SP_MIG_READING_PLAN_UPDATE_ABYS
                @MigRowFrom = @BatchFrom, @MigRowTo = @BatchTo,
                @SirketKodu = @SIRKET_KODU, @UpdatedRows = @UpdatedRows OUTPUT;

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
                        EXEC dbo.SP_MIG_READING_PLAN_INSERT_ONE
                            @MigRowID = @BisectFrom, @SirketKodu = @SIRKET_KODU,
                            @RowInserted = @RowInserted OUTPUT;

                        IF @RowInserted = 1
                            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                                @RunID = @RunID, @TableRunID = @TableRunID,
                                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                                @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom,
                                @BridgeTo = @BisectFrom, @RowCount = 1;
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

                    INSERT INTO energy.dbo.mgg_cbs_okuma_bolge (
                        OkumaBolgeAdi, KonumWkt, SirketKodu, ent_datetime,
                        ABYS_MIG_ROW_ID, ABYS_ID, ABYS_READING_LAYER_ID, ABYS_BOOK_ID, ABYS_CODE,
                        ABYS_READING_DAY, ABYS_TERMINAL_SYNC_CLIENT_ID, ABYS_LOCATION_WKT,
                        ABYS_MAX_SUBSCRIBER_COUNT, ABYS_CREATED_USER_ID, ABYS_CREATED_TIMESTAMP,
                        ABYS_UPDATED_USER_ID, ABYS_UPDATED_TIMESTAMP, ABYS_VERSION,
                        ABYS_FIRST_READING_ORDER_NUMBER, ABYS_LAST_READING_ORDER_NUMBER,
                        ABYS_TERMINAL_ORDER, ABYS_IS_ACTIVE
                    )
                    SELECT
                        s.OkumaBolgeAdi, s.KonumWkt, @SIRKET_KODU, s.ent_datetime,
                        s.MIG_ROW_ID, s.ABYS_ID, s.ABYS_READING_LAYER_ID, s.ABYS_BOOK_ID, s.ABYS_CODE,
                        s.ABYS_READING_DAY, s.ABYS_TERMINAL_SYNC_CLIENT_ID, s.ABYS_LOCATION_WKT,
                        s.ABYS_MAX_SUBSCRIBER_COUNT, s.ABYS_CREATED_USER_ID, s.ABYS_CREATED_TIMESTAMP,
                        s.ABYS_UPDATED_USER_ID, s.ABYS_UPDATED_TIMESTAMP, s.ABYS_VERSION,
                        s.ABYS_FIRST_READING_ORDER_NUMBER, s.ABYS_LAST_READING_ORDER_NUMBER,
                        s.ABYS_TERMINAL_ORDER, s.ABYS_IS_ACTIVE
                    FROM energy.dbo.VW_MIG_READING_PLAN_SOURCE s
                    WHERE s.MIG_ROW_ID BETWEEN @BisectFrom AND @BisectMid
                      AND NOT EXISTS (
                          SELECT 1 FROM energy.dbo.mgg_cbs_okuma_bolge t
                          WHERE t.ABYS_MIG_ROW_ID = s.MIG_ROW_ID
                             OR t.ABYS_ID = s.ABYS_ID
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

        IF @DEBUG = 1
        BEGIN
            SET @Msg = '  → OK=' + CAST(@InsertedCount AS VARCHAR(20))
                + ' ERR=' + CAST(@ErrorCount AS VARCHAR(20))
                + ' UPD=' + CAST(@UpdatedRows AS VARCHAR(20))
                + ' LastMigRow=' + CAST(@LastBridgeKey AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    EXEC dbo.SP_MIG_READING_PLAN_UPDATE_ABYS
        @SirketKodu = @SIRKET_KODU, @UpdatedRows = @UpdatedRows OUTPUT;

    IF @DEBUG = 1 AND @UpdatedRows > 0
        RAISERROR('ABYS kolonlari guncellendi (toplam): %d', 0, 1, @UpdatedRows) WITH NOWAIT;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.mgg_cbs_okuma_bolge
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



--SELECT TOP 5
--    src.CODE,
--    src.LOCATION.STAsText() AS GeogWkt,
--    s.KonumWkt.STAsText() AS GeomWkt,
--    s.KonumWkt.STCentroid().STX AS Lon,
--    s.KonumWkt.STCentroid().STY AS Lat,
--    LEFT(CONVERT(VARCHAR(MAX), s.KonumWkt.STAsBinary(), 2), 8) AS Hex_OnEk
--FROM energy.dbo.VW_MIG_READING_PLAN_SOURCE s
--INNER JOIN izgazMGR.dbo.CS_READING_PLAN src ON src.MIG_ROW_ID = s.MIG_ROW_ID
--WHERE s.KonumWkt IS NOT NULL;


EXEC dbo.SP_MIGRATE_CS_READING_PLAN_OKUMA_BOLGE
    @BATCH_SIZE  = 5000, 
    @BISECT_MIN    = 1,
    @SIRKET_KODU   = 4102,
    @DEBUG         = 1


--  delete from mgg_cbs_okuma_bolge  where SirketKodu = 4102 and ABYS_READING_LAYER_ID <>1135

--    UPDATE
--    mgg_cbs_kapi
--SET
--    mgg_cbs_kapi.OkumaBolgeKodu = RAN.Id
--FROM
--    mgg_cbs_kapi SI
--INNER JOIN
--    mgg_cbs_okuma_bolge RAN
--ON 
--    RAN.KonumWkt.STIntersects(SI.KonumWkt)=1 
--    where SI.SirketKodu=4102



select RAN.OkumaBolgeAdi  , COUNT(1) 
FROM    mgg_cbs_kapi SI
INNER JOIN   mgg_cbs_okuma_bolge RAN
ON 
    RAN.KonumWkt.STIntersects(SI.KonumWkt)=1 
    where SI.SirketKodu=4102
    group by RAN.OkumaBolgeAdi 