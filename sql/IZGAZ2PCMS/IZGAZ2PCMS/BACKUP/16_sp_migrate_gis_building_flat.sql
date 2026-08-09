-- ============================================================
-- SP_MIGRATE_GIS_BUILDING_FLAT  (LS_FLAT doldurma)
-- Kaynak  : izgazMGR.dbo.LS_FLAT → VW_MIG_LS_FLAT_SOURCE
-- Hedef   : energy.dbo.LS_FLAT  (ENT_ID = 4102)
-- Köprü   : MIG_ROW_ID (FLAT_CREATED_TIMESTAMP sırası)
-- Not     : Once 15_gis_building_flat_setup.sql deploy edilmeli
-- ============================================================
USE energy;
GO

 
 


CREATE OR ALTER PROCEDURE dbo.SP_MIG_FLAT_INSERT_ONE
    @MigRowID    BIGINT,
    @ENT_ID      INT,
    @RowInserted BIT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1
        FROM energy.dbo.LS_FLAT t
        INNER JOIN energy.dbo.VW_MIG_LS_FLAT_SOURCE s
            ON s.ABYS_INSTALLATION_ID = t.ABYS_INSTALLATION_ID
        WHERE s.MIG_ROW_ID = @MigRowID
          AND t.ENT_ID = @ENT_ID
    )
        RETURN;

    INSERT INTO energy.dbo.LS_FLAT (
        ABYS_FLAT_ID, ABYS_SUBSCRIBER_TYPE_ID, ABYS_INSTALLATION_ID,
        ABYS_INSTALLATION_GSTATUS, ABYS_STARTUP_DATE,
        ABYS_INSTALLATION_STATUS_ID, ABYS_INSTALLATION_CANCEL_DATE,
        FLATNR, FLATDEFN, FLOOR_NUMBER, BNA_ID, ENT_ID,
        TYPE, ADDRESS_NUMBER, NATIONAL_CODE, BUILDING_DOOR_ID,
        CREATED_TIMESTAMP, CREATED_USER_ID, UPDATED_TIMESTAMP, UPDATED_USER_ID
    )
    SELECT
        s.ABYS_FLAT_ID,
        s.ABYS_SUBSCRIBER_TYPE_ID,
        s.ABYS_INSTALLATION_ID,
        s.ABYS_INSTALLATION_GSTATUS,
        energy.dbo.FN_SAFE_DT(CAST(s.ABYS_STARTUP_DATE_RAW AS DATETIME2)),
        s.ABYS_INSTALLATION_STATUS_ID,
        energy.dbo.FN_SAFE_DT(CAST(s.ABYS_INSTALLATION_CANCEL_DATE_RAW AS DATETIME2)),
        energy.dbo.FN_SAFE_FLATNR(s.FLAT_NUMBER_RAW),
        s.FLATDEFN,
        s.FLOOR_NUMBER,
        s.BNA_ID,
        @ENT_ID,
        s.TYPE,
        LEFT(CAST(s.ADDRESS_NUMBER AS NVARCHAR(50)), 50),
        s.NATIONAL_CODE,
        s.BUILDING_DOOR_ID,
        energy.dbo.FN_SAFE_DT(CAST(s.FLAT_CREATED_TIMESTAMP AS DATETIME2)),
        s.FLAT_CREATED_USER_ID,
        energy.dbo.FN_SAFE_DT(CAST(s.FLAT_UPDATED_TIMESTAMP AS DATETIME2)),
        s.FLAT_UPDATED_USER_ID
    FROM energy.dbo.VW_MIG_LS_FLAT_SOURCE s
    WHERE s.MIG_ROW_ID = @MigRowID;

    SET @RowInserted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_FLAT_HARD_RESET
    @ENT_ID       INT = 4102,
    @DELETE_BATCH INT = 5000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @TotalDeletedStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_FLAT ENT_ID=%d ABYS tesisat kayitlari (batch=%d) ***',
            0, 1, @ENT_ID, @DELETE_BATCH) WITH NOWAIT;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_FLAT
        WHERE ENT_ID = @ENT_ID
          AND ABYS_INSTALLATION_ID IS NOT NULL;

        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;

        SET @TotalDeleted += @Deleted;
        SET @TotalDeletedStr = CAST(@TotalDeleted AS VARCHAR(20));

        RAISERROR('HARD RESET silindi: +%d (toplam %s)', 0, 1, @Deleted, @TotalDeletedStr) WITH NOWAIT;
    END

    IF @DEBUG = 1
    BEGIN
        SET @TotalDeletedStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s', 0, 1, @TotalDeletedStr) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_GIS_BUILDING_FLAT
    @BATCH_SIZE  INT = 5000,
    @RESUME      BIT = 1,
    @HARD_RESET  BIT = 0,
    @MAX_ERROR   INT = 500,
    @BISECT_MIN  INT = 1,
    @ENT_ID      INT = 4102,
    @DEBUG       BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'LS_FLAT',
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

    EXEC dbo.SP_MIG_FLAT_VALIDATE_SOURCE @RaiseOnMissing = 1;
    EXEC dbo.SP_MIG_FLAT_PREP_SOURCE;

    IF @HARD_RESET = 1
    BEGIN
        SET @ExecMode = 'HARD_RESET';

        EXEC dbo.SP_MIG_FLAT_HARD_RESET
            @ENT_ID = @ENT_ID, @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;

        SET @RESUME = 0;
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*)
    FROM energy.dbo.VW_MIG_LS_FLAT_SOURCE;

    SELECT @MaxBridgeKey = MAX(s.MIG_ROW_ID)
    FROM energy.dbo.VW_MIG_LS_FLAT_SOURCE s;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_FLAT',
        @TargetTable    = 'LS_FLAT',
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
            + ' | ENT_ID=' + CAST(@ENT_ID AS VARCHAR(10))
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
            FROM energy.dbo.VW_MIG_LS_FLAT_SOURCE s
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

            INSERT INTO energy.dbo.LS_FLAT (
                ABYS_FLAT_ID, ABYS_SUBSCRIBER_TYPE_ID, ABYS_INSTALLATION_ID,
                ABYS_INSTALLATION_GSTATUS, ABYS_STARTUP_DATE,
                ABYS_INSTALLATION_STATUS_ID, ABYS_INSTALLATION_CANCEL_DATE,
                FLATNR, FLATDEFN, FLOOR_NUMBER, BNA_ID, ENT_ID,
                TYPE, ADDRESS_NUMBER, NATIONAL_CODE, BUILDING_DOOR_ID,
                CREATED_TIMESTAMP, CREATED_USER_ID, UPDATED_TIMESTAMP, UPDATED_USER_ID
            )
            SELECT
                s.ABYS_FLAT_ID,
                s.ABYS_SUBSCRIBER_TYPE_ID,
                s.ABYS_INSTALLATION_ID,
                s.ABYS_INSTALLATION_GSTATUS,
                energy.dbo.FN_SAFE_DT(CAST(s.ABYS_STARTUP_DATE_RAW AS DATETIME2)),
                s.ABYS_INSTALLATION_STATUS_ID,
                energy.dbo.FN_SAFE_DT(CAST(s.ABYS_INSTALLATION_CANCEL_DATE_RAW AS DATETIME2)),
                energy.dbo.FN_SAFE_FLATNR(s.FLAT_NUMBER_RAW),
                s.FLATDEFN,
                s.FLOOR_NUMBER,
                s.BNA_ID,
                4102,
                s.TYPE,
                LEFT(CAST(s.ADDRESS_NUMBER AS NVARCHAR(50)), 50),
                s.NATIONAL_CODE,
                s.BUILDING_DOOR_ID,
                energy.dbo.FN_SAFE_DT(CAST(s.FLAT_CREATED_TIMESTAMP AS DATETIME2)),
                s.FLAT_CREATED_USER_ID,
                energy.dbo.FN_SAFE_DT(CAST(s.FLAT_UPDATED_TIMESTAMP AS DATETIME2)),
                s.FLAT_UPDATED_USER_ID
            FROM energy.dbo.VW_MIG_LS_FLAT_SOURCE s
            WHERE s.MIG_ROW_ID BETWEEN @BatchFrom AND @BatchTo
              AND NOT EXISTS (
                  SELECT 1
                  FROM energy.dbo.LS_FLAT t
                  WHERE t.ABYS_INSTALLATION_ID = s.ABYS_INSTALLATION_ID
                    AND t.ENT_ID = @ENT_ID
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
                        EXEC dbo.SP_MIG_FLAT_INSERT_ONE
                            @MigRowID = @BisectFrom, @ENT_ID = @ENT_ID,
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

                    INSERT INTO energy.dbo.LS_FLAT (
                        ABYS_FLAT_ID, ABYS_SUBSCRIBER_TYPE_ID, ABYS_INSTALLATION_ID,
                        ABYS_INSTALLATION_GSTATUS, ABYS_STARTUP_DATE,
                        ABYS_INSTALLATION_STATUS_ID, ABYS_INSTALLATION_CANCEL_DATE,
                        FLATNR, FLATDEFN, FLOOR_NUMBER, BNA_ID, ENT_ID,
                        TYPE, ADDRESS_NUMBER, NATIONAL_CODE, BUILDING_DOOR_ID,
                        CREATED_TIMESTAMP, CREATED_USER_ID, UPDATED_TIMESTAMP, UPDATED_USER_ID
                    )
                    SELECT
                        s.ABYS_FLAT_ID,
                        s.ABYS_SUBSCRIBER_TYPE_ID,
                        s.ABYS_INSTALLATION_ID,
                        s.ABYS_INSTALLATION_GSTATUS,
                        energy.dbo.FN_SAFE_DT(CAST(s.ABYS_STARTUP_DATE_RAW AS DATETIME2)),
                        s.ABYS_INSTALLATION_STATUS_ID,
                        energy.dbo.FN_SAFE_DT(CAST(s.ABYS_INSTALLATION_CANCEL_DATE_RAW AS DATETIME2)),
                        energy.dbo.FN_SAFE_FLATNR(s.FLAT_NUMBER_RAW),
                        s.FLATDEFN,
                        s.FLOOR_NUMBER,
                        s.BNA_ID,
                        @ENT_ID,
                        s.TYPE,
                        LEFT(CAST(s.ADDRESS_NUMBER AS NVARCHAR(50)), 50),
                        s.NATIONAL_CODE,
                        s.BUILDING_DOOR_ID,
                        energy.dbo.FN_SAFE_DT(CAST(s.FLAT_CREATED_TIMESTAMP AS DATETIME2)),
                        s.FLAT_CREATED_USER_ID,
                        energy.dbo.FN_SAFE_DT(CAST(s.FLAT_UPDATED_TIMESTAMP AS DATETIME2)),
                        s.FLAT_UPDATED_USER_ID
                    FROM energy.dbo.VW_MIG_LS_FLAT_SOURCE s
                    WHERE s.MIG_ROW_ID BETWEEN @BisectFrom AND @BisectMid
                      AND NOT EXISTS (
                          SELECT 1
                          FROM energy.dbo.LS_FLAT t
                          WHERE t.ABYS_INSTALLATION_ID = s.ABYS_INSTALLATION_ID
                            AND t.ENT_ID = @ENT_ID
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
                + ' LastMigRow=' + CAST(@LastBridgeKey AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_FLAT
    WHERE ENT_ID = @ENT_ID AND ABYS_INSTALLATION_ID IS NOT NULL;

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

--delete   from LS_FLAT where ENT_ID = 4102

--exec  dbo.SP_MIG_FLAT_INSERT_ONE @MigRowID =1,    @ENT_ID    =4102 

----select * from izgazMGR.dbo.LS_FLAT

--SELECT 1
--        FROM energy.dbo.LS_FLAT t
--        INNER JOIN energy.dbo.VW_MIG_LS_FLAT_SOURCE s
--            ON s.ABYS_INSTALLATION_ID = t.ABYS_INSTALLATION_ID
--        WHERE s.MIG_ROW_ID = 1
--          AND t.ENT_ID = 4102
   

 