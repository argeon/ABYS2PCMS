/* ============================================================
   FILE      : 530_READ_READINGDATA.sql
   VERSION   : 1
   ============================================================
   izgazMGR.dbo.LS_READING
     → energy.dbo.LS_005_ReadingData

   Onayli map:
     LREF                 ← LREF
     READING_ID           ← LREF (INT; overflow → NULL)
     SM3                  ← ABYS_SM3
     CONSUMPTION          ← EXPEND_ENERGY (kWh)
     CONTENT              ← BILL_DESCRIPTION
     PRE_ROUNDING_VALUE   ← ROUND_AMT
     CONTINUING_ROUND     ← TURNOVER_AMT

   Diger semantik map:
     CORRECTED_SM3        ← ABYS_CORRECTED_SM3
     M3                   ← CORR_VOLUME
     FIRST/LAST_INDEX     ← FIRST/LAST_READ_IND
     ADJUSTMENT_COEFFICIENT ← CORR_COEF
     HIGH_HEATING_VALUE   ← AVG_TOP_CAL_VALUE
     READING_METER_NUMBER ← CNT_SERIAL
     UNIT_PRICE           ← GAS_UNITPRICE_KWH
     SKB_UNIT_PRICE       ← SKB_UNITPRICE_KWH
     CONSUMPTION_FEE(_VAT)← EXPEND_FEE(_TAX)
     TOTAL_BILL_AMOUNT    ← PAYABLE_TOTAL
     DELAY_FEE(_VAT)      ← DEFAULT_FINE(_TAX)
     OPEN_CUT_FEE         ← GAS_OPEN_FEE
     PENALTY_FEE          ← ILLEGAL_USE_FEE
     STAMP_FEE            ← FATSBT
     SKB_CONSUMPTION_FEE  ← SKB_TOTAL_AMOUNT
     SUBSCRIBER_LOCATION  ← CUST_ADDRESS
     BILL_DATE            ← INV_DATE (nvarchar)
     BILL_SEQUENCE_NUMBER ← INV_ID
     AGREEMENT_NUMBER     ← AGRID
     METER_STATUS_CODE    ← CNT_STATUS
     ACCOUNT_DATE         ← INV_DATE
     FICHE                ← INV_REF
     STATUS               ← REC_STATUS
     PERIOD / ADDDATE / ADDUSER / RealCost / CalculatedRealCost

   Hedef LREF IDENTITY degil — dogrudan insert.
   ABYS_ID kopru kolonu eklenir.
   ============================================================ */
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ------------------------------------------------------------
-- ABYS kopru
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_ReadingData')
      AND name = 'ABYS_ID'
)
    ALTER TABLE energy.dbo.LS_005_ReadingData ADD ABYS_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_ReadingData')
      AND name = 'UX_LS005_READINGDATA_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS005_READINGDATA_ABYS_ID
        ON energy.dbo.LS_005_ReadingData (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Kaynak view
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.VW_MIG_LS005_READINGDATA_SOURCE
AS
SELECT
    CAST(s.LREF AS BIGINT)                                                      AS ABYS_ID,
    CAST(s.LREF AS BIGINT)                                                      AS LREF,
    TRY_CAST(s.LREF AS INT)                                                     AS READING_ID,

    CAST(TRY_CAST(s.AGRID AS BIGINT) AS NVARCHAR(50))                           AS AGREEMENT_NUMBER,
    CONVERT(NVARCHAR(20), s.INV_DATE, 120)                                      AS BILL_DATE,
    LEFT(s.INV_ID, 20)                                                          AS BILL_SEQUENCE_NUMBER,

    TRY_CAST(s.FIRST_READ_IND AS INT)                                           AS FIRST_INDEX,
    TRY_CAST(s.LAST_READ_IND AS INT)                                            AS LAST_INDEX,

    TRY_CAST(s.ABYS_SM3 AS FLOAT)                                               AS SM3,
    TRY_CAST(s.ABYS_CORRECTED_SM3 AS FLOAT)                                     AS CORRECTED_SM3,
    TRY_CAST(s.EXPEND_ENERGY AS FLOAT)                                          AS CONSUMPTION,
    TRY_CAST(s.CORR_VOLUME AS FLOAT)                                            AS M3,
    TRY_CAST(s.TURNOVER_AMT AS FLOAT)                                           AS CONTINUING_ROUND,
    TRY_CAST(s.ROUND_AMT AS FLOAT)                                              AS PRE_ROUNDING_VALUE,

    LEFT(CAST(TRY_CAST(s.CNT_STATUS AS BIGINT) AS NVARCHAR(20)), 10)            AS METER_STATUS_CODE,
    LEFT(s.CNT_SERIAL, 50)                                                      AS READING_METER_NUMBER,

    TRY_CAST(s.PAYABLE_TOTAL AS FLOAT)                                          AS TOTAL_BILL_AMOUNT,
    TRY_CAST(s.EXPEND_FEE AS FLOAT)                                             AS CONSUMPTION_FEE,
    TRY_CAST(s.EXPEND_FEE_TAX AS FLOAT)                                         AS CONSUMPTION_FEE_VAT,
    TRY_CAST(s.GAS_UNITPRICE_KWH AS FLOAT)                                      AS UNIT_PRICE,
    TRY_CAST(s.CORR_COEF AS FLOAT)                                              AS ADJUSTMENT_COEFFICIENT,
    TRY_CAST(s.AVG_TOP_CAL_VALUE AS FLOAT)                                      AS HIGH_HEATING_VALUE,

    TRY_CAST(s.DEFAULT_FINE AS FLOAT)                                           AS DELAY_FEE,
    TRY_CAST(s.DEFAULT_FINE_TAX AS FLOAT)                                       AS DELAY_FEE_VAT,
    TRY_CAST(s.FATSBT AS FLOAT)                                                 AS STAMP_FEE,
    TRY_CAST(s.ILLEGAL_USE_FEE AS FLOAT)                                        AS PENALTY_FEE,
    TRY_CAST(s.GAS_OPEN_FEE AS FLOAT)                                           AS OPEN_CUT_FEE,

    TRY_CAST(s.SKB_UNITPRICE_KWH AS FLOAT)                                      AS SKB_UNIT_PRICE,
    TRY_CAST(s.SKB_TOTAL_AMOUNT AS FLOAT)                                       AS SKB_CONSUMPTION_FEE,

    CAST(s.BILL_DESCRIPTION AS NVARCHAR(MAX))                                   AS CONTENT,
    CAST(s.CUST_ADDRESS AS NVARCHAR(MAX))                                       AS SUBSCRIBER_LOCATION,

    CAST(s.ADDDATE AS DATETIME)                                                 AS ADDDATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.ADDUSER AS BIGINT) AS INT)) AS ADDUSER,
    CAST(s.INV_DATE AS DATETIME)                                                AS ACCOUNT_DATE,
    CAST(s.INV_REF AS BIGINT)                                                   AS FICHE,
    CAST(TRY_CAST(s.REC_STATUS AS BIGINT) AS INT)                               AS STATUS,
    s.PERIOD                                                                    AS PERIOD,

    TRY_CAST(s.REAL_COST AS DECIMAL(15,6))                                      AS RealCost,
    TRY_CAST(s.CALCULATED_REAL_COST AS DECIMAL(15,2))                           AS CalculatedRealCost
FROM izgazMGR.dbo.LS_READING s
WHERE s.LREF IS NOT NULL;
GO

-- ------------------------------------------------------------
-- INSERT range
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_READINGDATA_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @RowCount  INT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    INSERT INTO energy.dbo.LS_005_ReadingData (
        LREF, ABYS_ID, READING_ID,
        AGREEMENT_NUMBER, BILL_DATE, BILL_SEQUENCE_NUMBER,
        FIRST_INDEX, LAST_INDEX,
        SM3, CORRECTED_SM3, CONSUMPTION, M3,
        CONTINUING_ROUND, PRE_ROUNDING_VALUE,
        METER_STATUS_CODE, READING_METER_NUMBER,
        TOTAL_BILL_AMOUNT, CONSUMPTION_FEE, CONSUMPTION_FEE_VAT,
        UNIT_PRICE, ADJUSTMENT_COEFFICIENT, HIGH_HEATING_VALUE,
        DELAY_FEE, DELAY_FEE_VAT, STAMP_FEE, PENALTY_FEE, OPEN_CUT_FEE,
        SKB_UNIT_PRICE, SKB_CONSUMPTION_FEE,
        CONTENT, SUBSCRIBER_LOCATION,
        ADDDATE, ADDUSER, ACCOUNT_DATE, FICHE, STATUS, PERIOD,
        RealCost, CalculatedRealCost
    )
    SELECT
        s.LREF, s.ABYS_ID, s.READING_ID,
        s.AGREEMENT_NUMBER, s.BILL_DATE, s.BILL_SEQUENCE_NUMBER,
        s.FIRST_INDEX, s.LAST_INDEX,
        s.SM3, s.CORRECTED_SM3, s.CONSUMPTION, s.M3,
        s.CONTINUING_ROUND, s.PRE_ROUNDING_VALUE,
        s.METER_STATUS_CODE, s.READING_METER_NUMBER,
        s.TOTAL_BILL_AMOUNT, s.CONSUMPTION_FEE, s.CONSUMPTION_FEE_VAT,
        s.UNIT_PRICE, s.ADJUSTMENT_COEFFICIENT, s.HIGH_HEATING_VALUE,
        s.DELAY_FEE, s.DELAY_FEE_VAT, s.STAMP_FEE, s.PENALTY_FEE, s.OPEN_CUT_FEE,
        s.SKB_UNIT_PRICE, s.SKB_CONSUMPTION_FEE,
        s.CONTENT, s.SUBSCRIBER_LOCATION,
        s.ADDDATE, s.ADDUSER, s.ACCOUNT_DATE, s.FICHE, s.STATUS, s.PERIOD,
        s.RealCost, s.CalculatedRealCost
    FROM energy.dbo.VW_MIG_LS005_READINGDATA_SOURCE s
    WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
      AND NOT EXISTS (
          SELECT 1
          FROM energy.dbo.LS_005_ReadingData t
          WHERE t.LREF = s.LREF
             OR t.ABYS_ID = s.ABYS_ID
      );

    SET @RowCount = @@ROWCOUNT;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_READINGDATA_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_ReadingData t
        WHERE t.LREF = @CurID OR t.ABYS_ID = @CurID
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_READINGDATA_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_READINGDATA_HARD_RESET
    @DELETE_BATCH INT = 10000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @TotalStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_ReadingData ABYS kayitlari (batch=%d) ***', 0, 1, @DELETE_BATCH) WITH NOWAIT;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_005_ReadingData
        WHERE ABYS_ID IS NOT NULL;

        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;

        SET @TotalDeleted += @Deleted;

        IF @DEBUG = 1
        BEGIN
            SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
            RAISERROR('HARD RESET silindi: +%d (toplam %s)', 0, 1, @Deleted, @TotalStr) WITH NOWAIT;
        END
    END

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s', 0, 1, @TotalStr) WITH NOWAIT;
    END
END
GO

-- ------------------------------------------------------------
-- Ana migrate
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_READINGDATA
    @BATCH_SIZE  INT = 10000,
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
        @MigrationCode  VARCHAR(50)      = 'LS_005_READINGDATA',
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

    IF OBJECT_ID('izgazMGR.dbo.LS_READING', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR.dbo.LS_READING bulunamadi.', 16, 1);
        RETURN;
    END

    IF OBJECT_ID('energy.dbo.LS_005_ReadingData', 'U') IS NULL
    BEGIN
        RAISERROR('energy.dbo.LS_005_ReadingData bulunamadi.', 16, 1);
        RETURN;
    END

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_READINGDATA_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM energy.dbo.VW_MIG_LS005_READINGDATA_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_LS005_READINGDATA_SOURCE;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_READING',
        @TargetTable    = 'LS_005_ReadingData',
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
            FROM energy.dbo.VW_MIG_LS005_READINGDATA_SOURCE s
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

            EXEC dbo.SP_MIG_READINGDATA_INSERT_RANGE
                @BatchFrom = @BatchFrom,
                @BatchTo   = @BatchTo,
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

            SET @BisectFrom = @BatchFrom;
            SET @BisectTo   = @BatchTo;

            WHILE @BisectFrom <= @BisectTo AND @Stopped = 0
            BEGIN
                SET @BisectSize = @BisectTo - @BisectFrom + 1;

                IF @BisectSize <= @BISECT_MIN
                BEGIN
                    BEGIN TRY
                        SET @RowInserted = 0;
                        EXEC dbo.SP_MIG_READINGDATA_INSERT_ONE
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

                    EXEC dbo.SP_MIG_READINGDATA_INSERT_RANGE
                        @BatchFrom = @BisectFrom,
                        @BatchTo   = @BisectMid,
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

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_ReadingData
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
        WHERE l.MIGRATION_CODE = 'LS_005_READINGDATA'
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO

/*
-- Deploy + calistir:
--   530_READ_READINGDATA.sql

EXEC energy.dbo.SP_MIGRATE_LS005_READINGDATA
     @HARD_RESET =1, @BATCH_SIZE = 10000, @DEBUG = 1;
*/


--EXEC energy.dbo.SP_MIGRATE_LS005_READINGDATA
--     @HARD_RESET =1, @BATCH_SIZE = 10000, @DEBUG = 1;


