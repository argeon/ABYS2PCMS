/* ============================================================
   SCRIPT_ID : READ_HHD_LOC_INV_TRAN_MIGRATE
   SCRIPT_NO : 521
   FILE      : 521_READ_HHD_LOC_INV_TRAN__migrate.sql
   VERSION   : 5
   ============================================================ */
-- v5: NOT EXISTS OR → iki ayri anti-join (ABYS_ID + LREF index seek; hedef buyudukce yavaslama)
-- v4: Enterprise 128-core: TABLOCK + OPTION(RECOMPILE,MAXDOP) + BATCH 250K
-- v3: IDENTITY_INSERT TRY/CATCH (hata sonrasi OFF)
-- ============================================================
-- SP_MIGRATE_LS005_HHD_LOC_INV_TRAN (v5)
-- Kaynak  : izgazMGR.dbo.LS_READING  (dogrudan, view yok)
-- Hedef   : energy.dbo.LS_005_01_hhd_loc_inv_tran
-- LREF    : IDENTITY_INSERT = kaynak LREF
-- ABYS_ID : kaynak LREF
-- AGRID   : LS_005_01_AGR.LREF (ABYS_ID = kaynak AGRID)
-- Bulk    : IDENTITY_INSERT + TABLOCK + LREF aralik batch (~250K)
-- MAXDOP  : varsayilan 64 (ust sinir 128, Enterprise 128-core)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_HHD_LOC_INV_TRAN_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @MAXDOP    INT = 64,
    @RowCount  INT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    /* Enterprise 128-core: varsayilan 64, ust sinir 128 */
    IF @MAXDOP IS NULL OR @MAXDOP < 1 SET @MAXDOP = 1;
    IF @MAXDOP > 128 SET @MAXDOP = 128;

    DECLARE @sql NVARCHAR(MAX);

    BEGIN TRY
        SET IDENTITY_INSERT dbo.LS_005_01_hhd_loc_inv_tran ON;

        /* MAXDOP literal zorunlu → dinamik SQL (302_AGR_BULK deseni) */
        SET @sql = N'
        INSERT INTO energy.dbo.LS_005_01_hhd_loc_inv_tran WITH (TABLOCK) (
        LREF, ABYS_ID,
        read_no, loc_region, read_date, loc_id, bina_id, seq_no,
        reader_comp, reader_prsnl, reader_prsnl_id,
        inv_id, inv_date, inv_first_date, inv_last_date, inv_ref,
        cnt_id, cnt_serial, cnt_mbar, cnt_digit, cnt_direction,
        cust_id, cust_suffix, cust_name, cust_address,
        first_read_date, last_read_date, first_read_ind, last_read_ind,
        expend_quantity, corr_coef, corr_volume,
        actual_top_cal_value, avg_top_cal_value, expend_energy,
        retail_price2, retail_price3, price_id, price_desc,
        default_fine, default_fine_tax,
        gas_open_fee, detach_attach_fee, test_fee, spec_serv_fee,
        illegal_use_fee, fixed_fee, fixed_fee_tax,
        expend_fee, expend_fee_tax, discount_addition,
        round_amt, turnover_amt,
        total, total_tax, payable_total,
        KDV, OTV, BHAB, FATSBT,
        discount_rate, interest_rate,
        min_total, min_expend, max_expend,
        rec_status, read_status, cnt_status, read_count,
        cust_type, ADDUSER, ADDDATE,
        gas_open_fee_ref, detach_attach_fee_ref, test_fee_ref,
        spec_serv_fee_ref, discount_addition_ref, illegal_use_fee_ref,
        AGRID, INV_INSTALLMENT_TOTAL, INV_INSTALLMENT_REF,
        real_date, CS_APPREF, UNDERLIMIT, UNDERLIMITSTAT, CANCELLED,
        longitude, latitude,
        SKB_TOTAL_AMOUNT, GAS_TOTAL_AMOUNT,
        SKB_UNITPRICE_KWH, GAS_UNITPRICE_KWH,
        CalculatedRealCost, RealCost,
        Content, DESCRIPTION, BILLDESCRIPTION, PERIOD,
        ABYS_CORRECTED_SM3, ABYS_SM3, ABYS_ACA_DESC, ABYS_ACC_DESC,
        ABYS_STATUS, ABYS_STATUS_VAL, ABYS_INSTALLATION_ID,
        ABYS_SUBSCRIBER_TYPE_ID, ABYS_ACTIVITY_TYPE_ID, ABYS_TARIFF_TYPE_ID,
        ABYS_PRE_METER_STATUS_ID,
        ABYS_AVG_CONSUMPTION, ABYS_ADD_CONSUMPTION, ABYS_CONSUMPTION,
        ABYS_CONSUMPTION_1, ABYS_CONSUMPTION_2, ABYS_CONSUMPTION_3,
        ABYS_CONSUMPTION_4, ABYS_CONSUMPTION_5,
        ABYS_PRE_BILL_DATE, ABYS_TOTAL_DEBT, ABYS_TOTAL_INSTALLMENT_DEBT,
        ABYS_TOTAL_CREDIT, ABYS_DEBT_BILL_COUNT, ABYS_NOTE,
        ABYS_TERMINAL_SYNC_CLIENT_ID, ABYS_TERMINAL_UPLOAD_TIME,
        ABYS_WORKMAN_USER_ID, ABYS_INSTALLATION_STATUS_ID,
        ABYS_ACCOUNT_ID, ABYS_RECREATE_READING_ID, ABYS_READING_DAY,
        ABYS_HAS_BARCODE, ABYS_IS_BARCODE_READING, ABYS_IS_FPS,
        ABYS_ERR_CODE, ABYS_ERR_TEXT, ABYS_READING_METER_NUMBER,
        ABYS_READING_END_OF_DAY_ID, ABYS_OPEN_CUT_FEE,
        ABYS_SKB_TARIFF_TYPE_ID, ABYS_SKB_UNIT_PRICE,
        ABYS_BUILDING_FLAT_ID, ABYS_GAS_LEVEL_DAY_COUNT,
        ABYS_GAS_LEVEL_DAY_LIMIT, ABYS_LAST_PICTURE_DATE,
        ABYS_DESERVED_DISCOUNT_M3, ABYS_GAS_LEVEL1_AMOUNT,
        ABYS_GAS_LEVEL2_AMOUNT, ABYS_TOLERATED_M3,
        ABYS_DEBT_BEN_REGISTER, ABYS_BILL_DESCRIPTION,
        ABYS_REAL_COST, ABYS_CALCULATED_REAL_COST,
        ABYS_PREV_CONSUMPTION, ABYS_TAX_DISCOUNT_AMOUNT,
        ABYS_READING_PLAN_ID, ABYS_POOL_DEBT, ABYS_POOL_DEBT_COUNT,
        ABYS_SBS_PARENT_ID, ABYS_HOUSEHOLDS_COUNT
    )
    SELECT
        CAST(s.LREF AS INT),
        CAST(s.LREF AS BIGINT),

        ISNULL(CAST(TRY_CAST(s.READ_NO AS BIGINT) AS INT), 0),
        ISNULL(CAST(TRY_CAST(s.LOC_REGION AS BIGINT) AS INT), 0),
        ISNULL(
            CASE
                WHEN s.READ_DATE IS NULL THEN NULL
                WHEN CAST(s.READ_DATE AS DATETIME2) < ''1900-01-01'' THEN NULL
                WHEN CAST(s.READ_DATE AS DATETIME2) > ''2079-06-06 23:59:00'' THEN NULL
                ELSE CAST(s.READ_DATE AS SMALLDATETIME)
            END,
            CAST(''19000101'' AS SMALLDATETIME)
        ),
        ISNULL(LEFT(s.LOC_ID, 15), ''''),
        CAST(s.BINA_ID AS INT),
        ISNULL(CAST(s.SEQ_NO AS INT), 0),
        ISNULL(TRY_CAST(s.READER_COMP AS INT), 0),
        LEFT(s.READER_PRSNL, 50),
        ISNULL(CAST(TRY_CAST(s.READER_PRSNL_ID AS BIGINT) AS INT), 0),

        LEFT(s.INV_ID, 16),
        ISNULL(
            CASE
                WHEN s.INV_DATE IS NULL THEN NULL
                WHEN CAST(s.INV_DATE AS DATETIME2) < ''1900-01-01'' THEN NULL
                WHEN CAST(s.INV_DATE AS DATETIME2) > ''2079-06-06 23:59:00'' THEN NULL
                ELSE CAST(s.INV_DATE AS SMALLDATETIME)
            END,
            CAST(''19000101'' AS SMALLDATETIME)
        ),
        CASE
            WHEN s.INV_FIRST_DATE IS NULL THEN NULL
            WHEN CAST(s.INV_FIRST_DATE AS DATETIME2) < ''1900-01-01'' THEN NULL
            WHEN CAST(s.INV_FIRST_DATE AS DATETIME2) > ''2079-06-06 23:59:00'' THEN NULL
            ELSE CAST(s.INV_FIRST_DATE AS SMALLDATETIME)
        END,
        ISNULL(
            CASE
                WHEN s.INV_LAST_DATE IS NULL THEN NULL
                WHEN CAST(s.INV_LAST_DATE AS DATETIME2) < ''1900-01-01'' THEN NULL
                WHEN CAST(s.INV_LAST_DATE AS DATETIME2) > ''2079-06-06 23:59:00'' THEN NULL
                ELSE CAST(s.INV_LAST_DATE AS SMALLDATETIME)
            END,
            CAST(''19000101'' AS SMALLDATETIME)
        ),
        CAST(s.INV_REF AS BIGINT),

        CAST(TRY_CAST(s.CNT_ID AS BIGINT) AS INT),
        LEFT(s.CNT_SERIAL, 20),
        LEFT(s.CNT_MBAR, 15),
        CAST(TRY_CAST(s.CNT_DIGIT AS INT) AS SMALLINT),
        CAST(CASE WHEN ISNULL(s.CNT_DIRECTION, 0) <> 0 THEN 1 ELSE 0 END AS BIT),

        CAST(TRY_CAST(s.CUST_ID AS BIGINT) AS INT),
        CAST(TRY_CAST(s.CUST_SUFFIX AS BIGINT) AS SMALLINT),
        LEFT(s.CUST_NAME, 70),
        LEFT(s.CUST_ADDRESS, 150),

        CASE
            WHEN s.FIRST_READ_DATE IS NULL THEN NULL
            WHEN CAST(s.FIRST_READ_DATE AS DATETIME2) < ''1900-01-01'' THEN NULL
            WHEN CAST(s.FIRST_READ_DATE AS DATETIME2) > ''2079-06-06 23:59:00'' THEN NULL
            ELSE CAST(s.FIRST_READ_DATE AS SMALLDATETIME)
        END,
        CASE
            WHEN s.LAST_READ_DATE IS NULL THEN NULL
            WHEN CAST(s.LAST_READ_DATE AS DATETIME2) < ''1900-01-01'' THEN NULL
            WHEN CAST(s.LAST_READ_DATE AS DATETIME2) > ''2079-06-06 23:59:00'' THEN NULL
            ELSE CAST(s.LAST_READ_DATE AS SMALLDATETIME)
        END,
        TRY_CAST(s.FIRST_READ_IND AS NUMERIC(15,2)),
        TRY_CAST(s.LAST_READ_IND AS NUMERIC(15,2)),
        TRY_CAST(s.EXPEND_QUANTITY AS NUMERIC(15,2)),
        TRY_CAST(s.CORR_COEF AS NUMERIC(14,5)),
        TRY_CAST(s.CORR_VOLUME AS NUMERIC(15,2)),

        ISNULL(TRY_CAST(s.ACTUAL_TOP_CAL_VALUE AS NUMERIC(15,2)), 0),
        ISNULL(TRY_CAST(s.AVG_TOP_CAL_VALUE AS NUMERIC(15,2)), 0),
        TRY_CAST(s.EXPEND_ENERGY AS NUMERIC(15,2)),

        TRY_CAST(s.RETAIL_PRICE2 AS NUMERIC(15,6)),
        TRY_CAST(s.RETAIL_PRICE3 AS NUMERIC(15,8)),
        CAST(TRY_CAST(s.PRICE_ID AS INT) AS SMALLINT),
        LEFT(s.PRICE_DESC, 20),

        ISNULL(TRY_CAST(s.DEFAULT_FINE AS NUMERIC(15,2)), 0),
        ISNULL(TRY_CAST(s.DEFAULT_FINE_TAX AS NUMERIC(15,2)), 0),
        ISNULL(TRY_CAST(s.GAS_OPEN_FEE AS NUMERIC(15,2)), 0),
        ISNULL(TRY_CAST(s.DETACH_ATTACH_FEE AS NUMERIC(15,2)), 0),
        ISNULL(TRY_CAST(s.TEST_FEE AS NUMERIC(15,2)), 0),
        ISNULL(TRY_CAST(s.SPEC_SERV_FEE AS NUMERIC(15,2)), 0),
        TRY_CAST(s.ILLEGAL_USE_FEE AS NUMERIC(15,2)),
        ISNULL(TRY_CAST(s.FIXED_FEE AS NUMERIC(15,2)), 0),
        ISNULL(TRY_CAST(s.FIXED_FEE_TAX AS NUMERIC(15,2)), 0),
        TRY_CAST(s.EXPEND_FEE AS NUMERIC(15,2)),
        TRY_CAST(s.EXPEND_FEE_TAX AS NUMERIC(15,2)),
        ISNULL(TRY_CAST(s.DISCOUNT_ADDITION AS NUMERIC(15,2)), 0),
        TRY_CAST(s.ROUND_AMT AS NUMERIC(15,2)),
        TRY_CAST(s.TURNOVER_AMT AS NUMERIC(15,2)),
        TRY_CAST(s.TOTAL AS NUMERIC(15,2)),
        TRY_CAST(s.TOTAL_TAX AS NUMERIC(15,2)),
        TRY_CAST(s.PAYABLE_TOTAL AS NUMERIC(15,2)),

        ISNULL(TRY_CAST(s.KDV AS NUMERIC(15,2)), 0),
        TRY_CAST(s.OTV AS NUMERIC(15,8)),
        ISNULL(TRY_CAST(s.BHAB AS NUMERIC(15,2)), 0),
        ISNULL(TRY_CAST(s.FATSBT AS NUMERIC(15,2)), 0),
        ISNULL(TRY_CAST(s.DISCOUNT_RATE AS NUMERIC(14,5)), 0),
        ISNULL(TRY_CAST(s.INTEREST_RATE AS NUMERIC(15,2)), 0),
        ISNULL(TRY_CAST(s.MIN_TOTAL AS NUMERIC(15,2)), 0),
        ISNULL(TRY_CAST(s.MIN_EXPEND AS NUMERIC(15,2)), 0),
        ISNULL(TRY_CAST(s.MAX_EXPEND AS NUMERIC(15,2)), 0),

        ISNULL(CAST(TRY_CAST(s.REC_STATUS AS BIGINT) AS SMALLINT), 0),
        ISNULL(CAST(TRY_CAST(s.READ_STATUS AS BIGINT) AS SMALLINT), 0),
        ISNULL(CAST(TRY_CAST(s.CNT_STATUS AS BIGINT) AS SMALLINT), 0),
        CAST(TRY_CAST(s.READ_COUNT AS BIGINT) AS SMALLINT),
        CAST(TRY_CAST(s.CUST_TYPE AS BIGINT) AS TINYINT),

        CASE
            WHEN TRY_CAST(s.ADDUSER AS INT) IS NULL THEN NULL
            ELSE TRY_CAST(s.ADDUSER AS INT) + 10000
        END,
        CASE
            WHEN CAST(s.ADDDATE AS DATETIME2) < ''1900-01-01'' THEN NULL
            WHEN CAST(s.ADDDATE AS DATETIME2) > ''2079-06-06 23:59:00'' THEN NULL
            ELSE CAST(CAST(s.ADDDATE AS DATETIME2) AS SMALLDATETIME)
        END,

        CAST(TRY_CAST(s.GAS_OPEN_FEE_REF AS BIGINT) AS INT),
        CAST(TRY_CAST(s.DETACH_ATTACH_FEE_REF AS BIGINT) AS INT),
        CAST(TRY_CAST(s.TEST_FEE_REF AS BIGINT) AS INT),
        CAST(TRY_CAST(s.SPEC_SERV_FEE_REF AS BIGINT) AS INT),
        CAST(TRY_CAST(s.DISCOUNT_ADDITION_REF AS BIGINT) AS INT),
        CAST(TRY_CAST(s.ILLEGAL_USE_FEE_REF AS BIGINT) AS INT),

        a.LREF,
        TRY_CAST(s.INV_INSTALLMENT_TOTAL AS FLOAT),
        CAST(TRY_CAST(s.INV_INSTALLMENT_REF AS BIGINT) AS INT),
        CAST(s.REAL_DATE AS DATETIME),
        CAST(TRY_CAST(s.CS_APPREF AS BIGINT) AS INT),
        s.UNDERLIMIT,
        CAST(TRY_CAST(s.UNDERLIMITSTAT AS BIGINT) AS INT),
        CAST(CASE WHEN ISNULL(TRY_CAST(s.CANCELLED AS BIGINT), 0) <> 0 THEN 1 ELSE 0 END AS BIT),

        s.LONGITUDE,
        s.LATITUDE,

        TRY_CAST(s.SKB_TOTAL_AMOUNT AS DECIMAL(16,6)),
        TRY_CAST(s.GAS_TOTAL_AMOUNT AS DECIMAL(16,8)),
        TRY_CAST(s.SKB_UNITPRICE_KWH AS DECIMAL(16,8)),
        TRY_CAST(s.GAS_UNITPRICE_KWH AS DECIMAL(16,8)),

        TRY_CAST(s.CALCULATED_REAL_COST AS DECIMAL(15,2)),
        TRY_CAST(s.REAL_COST AS DECIMAL(15,6)),

        CAST(s.BILL_DESCRIPTION AS NVARCHAR(MAX)),
        LEFT(s.BILL_DESCRIPTION, 500),
        LEFT(s.BILL_DESCRIPTION, 500),
        s.PERIOD,

        s.ABYS_CORRECTED_SM3,
        s.ABYS_SM3,
        s.ABYS_ACA_DESC,
        s.ABYS_ACC_DESC,
        s.ABYS_STATUS,
        s.ABYS_STATUS_VAL,
        s.ABYS_INSTALLATION_ID,
        s.ABYS_SUBSCRIBER_TYPE_ID,
        s.ABYS_ACTIVITY_TYPE_ID,
        s.ABYS_TARIFF_TYPE_ID,
        s.ABYS_PRE_METER_STATUS_ID,
        s.ABYS_AVG_CONSUMPTION,
        s.ABYS_ADD_CONSUMPTION,
        s.ABYS_CONSUMPTION,
        s.ABYS_CONSUMPTION_1,
        s.ABYS_CONSUMPTION_2,
        s.ABYS_CONSUMPTION_3,
        s.ABYS_CONSUMPTION_4,
        s.ABYS_CONSUMPTION_5,
        s.ABYS_PRE_BILL_DATE,
        s.ABYS_TOTAL_DEBT,
        s.ABYS_TOTAL_INSTALLMENT_DEBT,
        s.ABYS_TOTAL_CREDIT,
        s.ABYS_DEBT_BILL_COUNT,
        s.ABYS_NOTE,
        s.ABYS_TERMINAL_SYNC_CLIENT_ID,
        s.ABYS_TERMINAL_UPLOAD_TIME,
        s.ABYS_WORKMAN_USER_ID,
        s.ABYS_INSTALLATION_STATUS_ID,
        s.ABYS_ACCOUNT_ID,
        s.ABYS_RECREATE_READING_ID,
        s.ABYS_READING_DAY,
        s.ABYS_HAS_BARCODE,
        s.ABYS_IS_BARCODE_READING,
        s.ABYS_IS_FPS,
        s.ABYS_ERR_CODE,
        s.ABYS_ERR_TEXT,
        s.ABYS_READING_METER_NUMBER,
        s.ABYS_READING_END_OF_DAY_ID,
        s.ABYS_OPEN_CUT_FEE,
        s.ABYS_SKB_TARIFF_TYPE_ID,
        s.ABYS_SKB_UNIT_PRICE,
        s.ABYS_BUILDING_FLAT_ID,
        s.ABYS_GAS_LEVEL_DAY_COUNT,
        s.ABYS_GAS_LEVEL_DAY_LIMIT,
        s.ABYS_LAST_PICTURE_DATE,
        s.ABYS_DESERVED_DISCOUNT_M3,
        s.ABYS_GAS_LEVEL1_AMOUNT,
        s.ABYS_GAS_LEVEL2_AMOUNT,
        s.ABYS_TOLERATED_M3,
        s.ABYS_DEBT_BEN_REGISTER,
        s.ABYS_BILL_DESCRIPTION,
        s.ABYS_REAL_COST,
        s.ABYS_CALCULATED_REAL_COST,
        s.ABYS_PREV_CONSUMPTION,
        s.ABYS_TAX_DISCOUNT_AMOUNT,
        s.ABYS_READING_PLAN_ID,
        s.ABYS_POOL_DEBT,
        s.ABYS_POOL_DEBT_COUNT,
        s.ABYS_SBS_PARENT_ID,
        s.ABYS_HOUSEHOLDS_COUNT
    FROM izgazMGR.dbo.LS_READING s
    OUTER APPLY (
        SELECT TOP (1) agr.LREF
        FROM energy.dbo.LS_005_01_AGR agr
        WHERE agr.ABYS_ID = s.AGRID
        ORDER BY agr.LREF
    ) a
    WHERE s.LREF BETWEEN @BatchFrom AND @BatchTo
      AND s.LREF BETWEEN 1 AND 2147483647
      AND s.BINA_ID BETWEEN -2147483648 AND 2147483647
      AND NOT EXISTS (
          SELECT 1
          FROM energy.dbo.LS_005_01_hhd_loc_inv_tran t WITH (NOLOCK)
          WHERE t.ABYS_ID = s.LREF
      )
      AND NOT EXISTS (
          SELECT 1
          FROM energy.dbo.LS_005_01_hhd_loc_inv_tran t WITH (NOLOCK)
          WHERE t.LREF = CAST(s.LREF AS INT)
      )
        OPTION (RECOMPILE, MAXDOP ' + CAST(@MAXDOP AS NVARCHAR(3)) + N', USE HINT(''ENABLE_PARALLEL_PLAN_PREFERENCE''));';

        EXEC sys.sp_executesql
            @sql,
            N'@BatchFrom BIGINT, @BatchTo BIGINT',
            @BatchFrom = @BatchFrom,
            @BatchTo   = @BatchTo;

        SET @RowCount = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_hhd_loc_inv_tran OFF; END TRY BEGIN CATCH END CATCH;
        THROW;
    END CATCH

    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_hhd_loc_inv_tran OFF; END TRY BEGIN CATCH END CATCH;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_HHD_LOC_INV_TRAN_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_hhd_loc_inv_tran t WITH (NOLOCK)
        WHERE t.ABYS_ID = @CurID
    )
    OR EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_hhd_loc_inv_tran t WITH (NOLOCK)
        WHERE t.LREF = CAST(@CurID AS INT)
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @MAXDOP    = 1,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_HHD_LOC_INV_TRAN_HARD_RESET
    @DELETE_BATCH INT = 100000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @MaxLref INT, @TotalStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_hhd_loc_inv_tran ABYS kayitlari (batch=%d) ***', 0, 1, @DELETE_BATCH) WITH NOWAIT;

    SET IDENTITY_INSERT dbo.LS_005_01_hhd_loc_inv_tran OFF;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_005_01_hhd_loc_inv_tran WITH (TABLOCK)
        WHERE ABYS_ID IS NOT NULL
        OPTION (RECOMPILE, MAXDOP 8);

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
    FROM energy.dbo.LS_005_01_hhd_loc_inv_tran;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_hhd_loc_inv_tran', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s, CHECKIDENT=%d', 0, 1, @TotalStr, @MaxLref) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_HHD_LOC_INV_TRAN
    @BATCH_SIZE  INT = 250000,
    @RESUME      BIT = 1,
    @HARD_RESET  BIT = 0,
    @MAX_ERROR   INT = 500,
    @BISECT_MIN  INT = 1,
    @MAXDOP      INT = 64,
    @DEBUG       BIT = 0
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    /* Enterprise 128-core: varsayilan MAXDOP 64, ust sinir 128 */
    IF @MAXDOP IS NULL OR @MAXDOP < 1 SET @MAXDOP = 1;
    IF @MAXDOP > 128 SET @MAXDOP = 128;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_HHD_LOC_INV_TRAN',
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

    EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_VALIDATE_ALL @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    -- Full COUNT_BIG 95M'de pahali: partitions.rows approx + MAX(LREF)
    SELECT @SourceCount = SUM(p.rows)
    FROM izgazMGR.sys.partitions p
    INNER JOIN izgazMGR.sys.tables t ON t.object_id = p.object_id
    INNER JOIN izgazMGR.sys.schemas sch ON sch.schema_id = t.schema_id
    WHERE sch.name = 'dbo'
      AND t.name = 'LS_READING'
      AND p.index_id IN (0, 1);

    SELECT @MaxBridgeKey = MAX(s.LREF)
    FROM izgazMGR.dbo.LS_READING s WITH (NOLOCK)
    WHERE s.LREF BETWEEN 1 AND 2147483647
    OPTION (RECOMPILE, MAXDOP 8);

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_READING',
        @TargetTable    = 'LS_005_01_hhd_loc_inv_tran',
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
            + ' | Kaynak~' + CAST(ISNULL(@SourceCount, 0) AS VARCHAR(20))
            + ' | LREF=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20))
            + ' | BATCH=' + CAST(@BATCH_SIZE AS VARCHAR(10))
            + ' | MAXDOP=' + CAST(@MAXDOP AS VARCHAR(3));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @BatchFrom  = @LastBridgeKey + 1;
        SET @RowCount   = 0;

        -- Sonraki N gercek LREF (bos araliklarda hizli ilerler)
        SELECT @BatchTo = MAX(LREF)
        FROM (
            SELECT TOP (@BATCH_SIZE) s.LREF
            FROM izgazMGR.dbo.LS_READING s WITH (NOLOCK)
            WHERE s.LREF > @LastBridgeKey
              AND s.LREF <= 2147483647
            ORDER BY s.LREF ASC
        ) x
        OPTION (RECOMPILE, MAXDOP 8);

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

            EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_INSERT_RANGE
                @BatchFrom = @BatchFrom,
                @BatchTo   = @BatchTo,
                @MAXDOP    = @MAXDOP,
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
            SET IDENTITY_INSERT dbo.LS_005_01_hhd_loc_inv_tran OFF;
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
                        EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_INSERT_ONE
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
                            N'LREF=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

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

                    EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_INSERT_RANGE
                        @BatchFrom = @BisectFrom,
                        @BatchTo   = @BisectMid,
                        @MAXDOP    = @MAXDOP,
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
                    SET IDENTITY_INSERT dbo.LS_005_01_hhd_loc_inv_tran OFF;
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
    FROM energy.dbo.LS_005_01_hhd_loc_inv_tran;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_hhd_loc_inv_tran', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
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
        WHERE l.MIGRATION_CODE = 'LS_005_01_HHD_LOC_INV_TRAN'
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO


 
   --EXEC energy.dbo.SP_MIGRATE_LS005_HHD_LOC_INV_TRAN
   --    @RESUME = 1, @HARD_RESET = 0,
   --    @BATCH_SIZE = 250000, @MAXDOP = 64, @DEBUG = 1;
   -- 128-core Enterprise: @BATCH_SIZE 100000..500000, @MAXDOP 32..128
 