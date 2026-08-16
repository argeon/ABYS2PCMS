/* ============================================================
   SCRIPT_ID : READ_HHD_LOC_INV_TRAN_SETUP
   SCRIPT_NO : 520
   FILE      : 520_READ_HHD_LOC_INV_TRAN__setup.sql
   VERSION   : 3
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.LS_READING
--   → energy.dbo.LS_005_01_hhd_loc_inv_tran
--
-- v3:
--   - Kaynak IX_LS_READING_LREF (heap → LREF seek; 521 batch)
--   - Kaynak IX_LS_READING_ABYS_ACCOUNT_ID (O11 READ_TRANSREF / invoice join)
--   - AGR IX_LS_005_01_AGR_ABYS_ID (OUTER APPLY AGRID resolve)
--   - ABYS_ACCRUE_TYPE_ID: dump/staging bridge (ENERGY TRAN'a yazilmaz)
-- v2:
--   - View YOK (95M satir; dogrudan batch INSERT)
--   - ABYS_* kolonlar hedefe eklenir, 1:1 insert
--   - AGRID ← LS_005_01_AGR.LREF (ABYS_ID resolve)
--   - READER_COMP TRY_CAST → int, degilse 0
--   - DESCRIPTION/Content/BILLDESCRIPTION ← BILL_DESCRIPTION
--   - Scalar UDF yok (inline CASE; ADDUSER = +10000)
--   - STG_* aktarilmaz
-- ============================================================
USE energy;
GO

-- Eski view kaldir
IF OBJECT_ID('dbo.VW_MIG_LS005_HHD_LOC_INV_TRAN_SOURCE', 'V') IS NOT NULL
    DROP VIEW dbo.VW_MIG_LS005_HHD_LOC_INV_TRAN_SOURCE;
GO

-- ------------------------------------------------------------
-- Performans index (521 migrate / 524 TRAN yama)
-- Enterprise: ONLINE + MAXDOP; migrate sirasinda da guvenli
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1
    FROM izgazMGR.sys.indexes i
    INNER JOIN izgazMGR.sys.tables t ON t.object_id = i.object_id
    INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name = 'dbo' AND t.name = 'LS_READING' AND i.name = 'IX_LS_READING_LREF'
)
BEGIN
    RAISERROR('CREATE IX_LS_READING_LREF (ONLINE)...', 0, 1) WITH NOWAIT;
    CREATE NONCLUSTERED INDEX IX_LS_READING_LREF
        ON izgazMGR.dbo.LS_READING (LREF)
        WITH (ONLINE = ON, MAXDOP = 64, SORT_IN_TEMPDB = ON);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM izgazMGR.sys.indexes i
    INNER JOIN izgazMGR.sys.tables t ON t.object_id = i.object_id
    INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name = 'dbo' AND t.name = 'LS_READING' AND i.name = 'IX_LS_READING_ABYS_ACCOUNT_ID'
)
AND COL_LENGTH('izgazMGR.dbo.LS_READING', 'ABYS_ACCOUNT_ID') IS NOT NULL
BEGIN
    RAISERROR('CREATE IX_LS_READING_ABYS_ACCOUNT_ID (ONLINE)...', 0, 1) WITH NOWAIT;
    CREATE NONCLUSTERED INDEX IX_LS_READING_ABYS_ACCOUNT_ID
        ON izgazMGR.dbo.LS_READING (ABYS_ACCOUNT_ID)
        INCLUDE (LREF)
        WITH (ONLINE = ON, MAXDOP = 64, SORT_IN_TEMPDB = ON);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR')
      AND name = 'IX_LS_005_01_AGR_ABYS_ID'
)
BEGIN
    RAISERROR('CREATE IX_LS_005_01_AGR_ABYS_ID (ONLINE)...', 0, 1) WITH NOWAIT;
    CREATE NONCLUSTERED INDEX IX_LS_005_01_AGR_ABYS_ID
        ON energy.dbo.LS_005_01_AGR (ABYS_ID)
        INCLUDE (LREF)
        WITH (ONLINE = ON, MAXDOP = 64, SORT_IN_TEMPDB = ON);
END
GO

-- ------------------------------------------------------------
-- ABYS kopru + ABYS_* mirror kolonlar
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_hhd_loc_inv_tran') AND name = 'ABYS_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_hhd_loc_inv_tran ADD ABYS_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_hhd_loc_inv_tran')
      AND name = 'UX_LS005_HHD_LOC_INV_TRAN_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS005_HHD_LOC_INV_TRAN_ABYS_ID
        ON energy.dbo.LS_005_01_hhd_loc_inv_tran (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(200) NOT NULL);

INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 (N'ABYS_CORRECTED_SM3',            N'decimal(16,6) NULL'),
 (N'ABYS_SM3',                      N'decimal(13,3) NULL'),
 (N'ABYS_ACA_DESC',                 N'nvarchar(4000) NULL'),
 (N'ABYS_ACC_DESC',                 N'nvarchar(4000) NULL'),
 (N'ABYS_STATUS',                   N'smallint NULL'),
 (N'ABYS_STATUS_VAL',               N'nvarchar(100) NULL'),
 (N'ABYS_INSTALLATION_ID',          N'bigint NULL'),
 (N'ABYS_SUBSCRIBER_TYPE_ID',       N'bigint NULL'),
 (N'ABYS_ACTIVITY_TYPE_ID',         N'bigint NULL'),
 (N'ABYS_TARIFF_TYPE_ID',           N'bigint NULL'),
 (N'ABYS_PRE_METER_STATUS_ID',      N'bigint NULL'),
 (N'ABYS_AVG_CONSUMPTION',          N'decimal(16,6) NULL'),
 (N'ABYS_ADD_CONSUMPTION',          N'decimal(16,6) NULL'),
 (N'ABYS_CONSUMPTION',              N'decimal(16,6) NULL'),
 (N'ABYS_CONSUMPTION_1',            N'decimal(16,6) NULL'),
 (N'ABYS_CONSUMPTION_2',            N'decimal(16,6) NULL'),
 (N'ABYS_CONSUMPTION_3',            N'decimal(16,6) NULL'),
 (N'ABYS_CONSUMPTION_4',            N'decimal(16,6) NULL'),
 (N'ABYS_CONSUMPTION_5',            N'decimal(16,6) NULL'),
 (N'ABYS_PRE_BILL_DATE',            N'datetime2(0) NULL'),
 (N'ABYS_TOTAL_DEBT',               N'decimal(10,2) NULL'),
 (N'ABYS_TOTAL_INSTALLMENT_DEBT',   N'decimal(10,2) NULL'),
 (N'ABYS_TOTAL_CREDIT',             N'decimal(10,2) NULL'),
 (N'ABYS_DEBT_BILL_COUNT',          N'smallint NULL'),
 (N'ABYS_NOTE',                     N'nvarchar(500) NULL'),
 (N'ABYS_TERMINAL_SYNC_CLIENT_ID',  N'bigint NULL'),
 (N'ABYS_TERMINAL_UPLOAD_TIME',     N'datetime2(0) NULL'),
 (N'ABYS_WORKMAN_USER_ID',          N'bigint NULL'),
 (N'ABYS_INSTALLATION_STATUS_ID',   N'smallint NULL'),
 (N'ABYS_ACCOUNT_ID',               N'bigint NULL'),
 (N'ABYS_RECREATE_READING_ID',      N'bigint NULL'),
 (N'ABYS_READING_DAY',              N'smallint NULL'),
 (N'ABYS_HAS_BARCODE',              N'smallint NULL'),
 (N'ABYS_IS_BARCODE_READING',       N'smallint NULL'),
 (N'ABYS_IS_FPS',                   N'smallint NULL'),
 (N'ABYS_ERR_CODE',                 N'nvarchar(10) NULL'),
 (N'ABYS_ERR_TEXT',                 N'nvarchar(4000) NULL'),
 (N'ABYS_READING_METER_NUMBER',     N'nvarchar(25) NULL'),
 (N'ABYS_READING_END_OF_DAY_ID',    N'bigint NULL'),
 (N'ABYS_OPEN_CUT_FEE',             N'decimal(10,2) NULL'),
 (N'ABYS_SKB_TARIFF_TYPE_ID',       N'bigint NULL'),
 (N'ABYS_SKB_UNIT_PRICE',           N'decimal(10,9) NULL'),
 (N'ABYS_BUILDING_FLAT_ID',         N'bigint NULL'),
 (N'ABYS_GAS_LEVEL_DAY_COUNT',      N'smallint NULL'),
 (N'ABYS_GAS_LEVEL_DAY_LIMIT',      N'decimal(15,3) NULL'),
 (N'ABYS_LAST_PICTURE_DATE',        N'datetime2(0) NULL'),
 (N'ABYS_DESERVED_DISCOUNT_M3',     N'decimal(10,3) NULL'),
 (N'ABYS_GAS_LEVEL1_AMOUNT',        N'decimal(10,8) NULL'),
 (N'ABYS_GAS_LEVEL2_AMOUNT',        N'decimal(10,8) NULL'),
 (N'ABYS_TOLERATED_M3',             N'decimal(16,6) NULL'),
 (N'ABYS_DEBT_BEN_REGISTER',        N'decimal(10,2) NULL'),
 (N'ABYS_BILL_DESCRIPTION',         N'nvarchar(1000) NULL'),
 (N'ABYS_REAL_COST',                N'decimal(19,8) NULL'),
 (N'ABYS_CALCULATED_REAL_COST',     N'decimal(19,8) NULL'),
 (N'ABYS_PREV_CONSUMPTION',         N'decimal(16,6) NULL'),
 (N'ABYS_TAX_DISCOUNT_AMOUNT',      N'decimal(15,2) NULL'),
 (N'ABYS_READING_PLAN_ID',          N'bigint NULL'),
 (N'ABYS_POOL_DEBT',                N'decimal(10,2) NULL'),
 (N'ABYS_POOL_DEBT_COUNT',          N'smallint NULL'),
 (N'ABYS_SBS_PARENT_ID',            N'bigint NULL'),
 (N'ABYS_HOUSEHOLDS_COUNT',         N'bigint NULL');

SELECT @Sql = @Sql + N'ALTER TABLE energy.dbo.LS_005_01_hhd_loc_inv_tran ADD '
    + QUOTENAME(c.COL_NAME) + N' ' + c.COL_DEF + N';'
FROM @Cols c
WHERE NOT EXISTS (
    SELECT 1 FROM sys.columns sc
    WHERE sc.object_id = OBJECT_ID('energy.dbo.LS_005_01_hhd_loc_inv_tran')
      AND sc.name = c.COL_NAME
);

IF @Sql <> N''
    EXEC sys.sp_executesql @Sql;
GO

-- ------------------------------------------------------------
-- Validate
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_HHD_LOC_INV_TRAN_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_READING', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_READING bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('READ_NO'),('LOC_REGION'),('READ_DATE'),('LOC_ID'),
            ('BINA_ID'),('SEQ_NO'),('READER_COMP'),('READER_PRSNL'),('READER_PRSNL_ID'),
            ('INV_ID'),('INV_REF'),('INV_DATE'),('INV_FIRST_DATE'),('INV_LAST_DATE'),
            ('CNT_ID'),('CNT_SERIAL'),('CNT_MBAR'),('CNT_DIGIT'),('CNT_DIRECTION'),
            ('CUST_ID'),('CUST_SUFFIX'),('CUST_NAME'),('CUST_ADDRESS'),
            ('FIRST_READ_DATE'),('LAST_READ_DATE'),('FIRST_READ_IND'),('LAST_READ_IND'),
            ('EXPEND_QUANTITY'),('CORR_COEF'),('CORR_VOLUME'),
            ('ACTUAL_TOP_CAL_VALUE'),('AVG_TOP_CAL_VALUE'),('EXPEND_ENERGY'),
            ('RETAIL_PRICE2'),('RETAIL_PRICE3'),('PRICE_ID'),('PRICE_DESC'),
            ('DEFAULT_FINE'),('DEFAULT_FINE_TAX'),
            ('GAS_OPEN_FEE'),('DETACH_ATTACH_FEE'),('TEST_FEE'),('SPEC_SERV_FEE'),
            ('ILLEGAL_USE_FEE'),('FIXED_FEE'),('FIXED_FEE_TAX'),
            ('EXPEND_FEE'),('EXPEND_FEE_TAX'),('DISCOUNT_ADDITION'),
            ('TOTAL'),('TOTAL_TAX'),('PAYABLE_TOTAL'),
            ('KDV'),('OTV'),('BHAB'),('FATSBT'),
            ('DISCOUNT_RATE'),('INTEREST_RATE'),
            ('MIN_TOTAL'),('MIN_EXPEND'),('MAX_EXPEND'),
            ('REC_STATUS'),('READ_STATUS'),('CNT_STATUS'),('READ_COUNT'),
            ('CUST_TYPE'),('ADDUSER'),('ADDDATE'),
            ('GAS_OPEN_FEE_REF'),('DETACH_ATTACH_FEE_REF'),('TEST_FEE_REF'),
            ('SPEC_SERV_FEE_REF'),('DISCOUNT_ADDITION_REF'),('ILLEGAL_USE_FEE_REF'),
            ('AGRID'),('INV_INSTALLMENT_TOTAL'),('INV_INSTALLMENT_REF'),
            ('REAL_DATE'),('CS_APPREF'),('UNDERLIMIT'),('UNDERLIMITSTAT'),
            ('CANCELLED'),('GAS_TOTAL_AMOUNT'),('SKB_TOTAL_AMOUNT'),
            ('ROUND_AMT'),('TURNOVER_AMT'),('PERIOD'),
            ('BILL_DESCRIPTION'),('CALCULATED_REAL_COST'),('REAL_COST'),
            ('LATITUDE'),('LONGITUDE'),
            ('GAS_UNITPRICE_KWH'),('SKB_UNITPRICE_KWH'),
            ('ABYS_CORRECTED_SM3'),('ABYS_SM3'),('ABYS_ACA_DESC'),('ABYS_ACC_DESC'),
            ('ABYS_STATUS'),('ABYS_STATUS_VAL'),('ABYS_INSTALLATION_ID'),
            ('ABYS_SUBSCRIBER_TYPE_ID'),('ABYS_ACTIVITY_TYPE_ID'),('ABYS_TARIFF_TYPE_ID'),
            ('ABYS_PRE_METER_STATUS_ID'),
            ('ABYS_AVG_CONSUMPTION'),('ABYS_ADD_CONSUMPTION'),('ABYS_CONSUMPTION'),
            ('ABYS_CONSUMPTION_1'),('ABYS_CONSUMPTION_2'),('ABYS_CONSUMPTION_3'),
            ('ABYS_CONSUMPTION_4'),('ABYS_CONSUMPTION_5'),
            ('ABYS_PRE_BILL_DATE'),('ABYS_TOTAL_DEBT'),('ABYS_TOTAL_INSTALLMENT_DEBT'),
            ('ABYS_TOTAL_CREDIT'),('ABYS_DEBT_BILL_COUNT'),('ABYS_NOTE'),
            ('ABYS_TERMINAL_SYNC_CLIENT_ID'),('ABYS_TERMINAL_UPLOAD_TIME'),
            ('ABYS_WORKMAN_USER_ID'),('ABYS_INSTALLATION_STATUS_ID'),
            ('ABYS_ACCOUNT_ID'),('ABYS_RECREATE_READING_ID'),('ABYS_READING_DAY'),
            ('ABYS_HAS_BARCODE'),('ABYS_IS_BARCODE_READING'),('ABYS_IS_FPS'),
            ('ABYS_ERR_CODE'),('ABYS_ERR_TEXT'),('ABYS_READING_METER_NUMBER'),
            ('ABYS_READING_END_OF_DAY_ID'),('ABYS_OPEN_CUT_FEE'),
            ('ABYS_SKB_TARIFF_TYPE_ID'),('ABYS_SKB_UNIT_PRICE'),
            ('ABYS_BUILDING_FLAT_ID'),('ABYS_GAS_LEVEL_DAY_COUNT'),
            ('ABYS_GAS_LEVEL_DAY_LIMIT'),('ABYS_LAST_PICTURE_DATE'),
            ('ABYS_DESERVED_DISCOUNT_M3'),('ABYS_GAS_LEVEL1_AMOUNT'),
            ('ABYS_GAS_LEVEL2_AMOUNT'),('ABYS_TOLERATED_M3'),
            ('ABYS_DEBT_BEN_REGISTER'),('ABYS_BILL_DESCRIPTION'),
            ('ABYS_REAL_COST'),('ABYS_CALCULATED_REAL_COST'),
            ('ABYS_PREV_CONSUMPTION'),('ABYS_TAX_DISCOUNT_AMOUNT'),
            ('ABYS_READING_PLAN_ID'),('ABYS_POOL_DEBT'),('ABYS_POOL_DEBT_COUNT'),
            ('ABYS_SBS_PARENT_ID'),('ABYS_HOUSEHOLDS_COUNT'),
            ('ABYS_ACCRUE_TYPE_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'LS_READING' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_READING eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_READING kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_HHD_LOC_INV_TRAN_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_hhd_loc_inv_tran', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_hhd_loc_inv_tran bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('read_no'),('loc_region'),('read_date'),('loc_id'),
            ('bina_id'),('seq_no'),('reader_comp'),('reader_prsnl'),('reader_prsnl_id'),
            ('inv_id'),('inv_date'),('inv_first_date'),('inv_last_date'),('inv_ref'),
            ('cnt_id'),('cnt_serial'),('cnt_mbar'),('cnt_digit'),('cnt_direction'),
            ('cust_id'),('cust_suffix'),('cust_name'),('cust_address'),
            ('first_read_date'),('last_read_date'),('first_read_ind'),('last_read_ind'),
            ('expend_quantity'),('corr_coef'),('corr_volume'),
            ('actual_top_cal_value'),('avg_top_cal_value'),('expend_energy'),
            ('retail_price2'),('retail_price3'),('price_id'),('price_desc'),
            ('default_fine'),('default_fine_tax'),
            ('gas_open_fee'),('detach_attach_fee'),('test_fee'),('spec_serv_fee'),
            ('illegal_use_fee'),('fixed_fee'),('fixed_fee_tax'),
            ('expend_fee'),('expend_fee_tax'),('discount_addition'),
            ('round_amt'),('turnover_amt'),
            ('total'),('total_tax'),('payable_total'),
            ('KDV'),('OTV'),('BHAB'),('FATSBT'),
            ('discount_rate'),('interest_rate'),
            ('min_total'),('min_expend'),('max_expend'),
            ('rec_status'),('read_status'),('cnt_status'),('read_count'),
            ('cust_type'),('ADDUSER'),('ADDDATE'),
            ('gas_open_fee_ref'),('detach_attach_fee_ref'),('test_fee_ref'),
            ('spec_serv_fee_ref'),('discount_addition_ref'),('illegal_use_fee_ref'),
            ('AGRID'),('INV_INSTALLMENT_TOTAL'),('INV_INSTALLMENT_REF'),
            ('real_date'),('CS_APPREF'),('UNDERLIMIT'),('UNDERLIMITSTAT'),
            ('CANCELLED'),('longitude'),('latitude'),
            ('GAS_TOTAL_AMOUNT'),('SKB_TOTAL_AMOUNT'),
            ('GAS_UNITPRICE_KWH'),('SKB_UNITPRICE_KWH'),
            ('CalculatedRealCost'),('RealCost'),
            ('Content'),('DESCRIPTION'),('BILLDESCRIPTION'),
            ('PERIOD'),('ABYS_ID'),
            ('ABYS_CORRECTED_SM3'),('ABYS_SM3'),('ABYS_ACA_DESC'),('ABYS_ACC_DESC'),
            ('ABYS_STATUS'),('ABYS_STATUS_VAL'),('ABYS_INSTALLATION_ID'),
            ('ABYS_SUBSCRIBER_TYPE_ID'),('ABYS_ACTIVITY_TYPE_ID'),('ABYS_TARIFF_TYPE_ID'),
            ('ABYS_PRE_METER_STATUS_ID'),
            ('ABYS_AVG_CONSUMPTION'),('ABYS_ADD_CONSUMPTION'),('ABYS_CONSUMPTION'),
            ('ABYS_CONSUMPTION_1'),('ABYS_CONSUMPTION_2'),('ABYS_CONSUMPTION_3'),
            ('ABYS_CONSUMPTION_4'),('ABYS_CONSUMPTION_5'),
            ('ABYS_PRE_BILL_DATE'),('ABYS_TOTAL_DEBT'),('ABYS_TOTAL_INSTALLMENT_DEBT'),
            ('ABYS_TOTAL_CREDIT'),('ABYS_DEBT_BILL_COUNT'),('ABYS_NOTE'),
            ('ABYS_TERMINAL_SYNC_CLIENT_ID'),('ABYS_TERMINAL_UPLOAD_TIME'),
            ('ABYS_WORKMAN_USER_ID'),('ABYS_INSTALLATION_STATUS_ID'),
            ('ABYS_ACCOUNT_ID'),('ABYS_RECREATE_READING_ID'),('ABYS_READING_DAY'),
            ('ABYS_HAS_BARCODE'),('ABYS_IS_BARCODE_READING'),('ABYS_IS_FPS'),
            ('ABYS_ERR_CODE'),('ABYS_ERR_TEXT'),('ABYS_READING_METER_NUMBER'),
            ('ABYS_READING_END_OF_DAY_ID'),('ABYS_OPEN_CUT_FEE'),
            ('ABYS_SKB_TARIFF_TYPE_ID'),('ABYS_SKB_UNIT_PRICE'),
            ('ABYS_BUILDING_FLAT_ID'),('ABYS_GAS_LEVEL_DAY_COUNT'),
            ('ABYS_GAS_LEVEL_DAY_LIMIT'),('ABYS_LAST_PICTURE_DATE'),
            ('ABYS_DESERVED_DISCOUNT_M3'),('ABYS_GAS_LEVEL1_AMOUNT'),
            ('ABYS_GAS_LEVEL2_AMOUNT'),('ABYS_TOLERATED_M3'),
            ('ABYS_DEBT_BEN_REGISTER'),('ABYS_BILL_DESCRIPTION'),
            ('ABYS_REAL_COST'),('ABYS_CALCULATED_REAL_COST'),
            ('ABYS_PREV_CONSUMPTION'),('ABYS_TAX_DISCOUNT_AMOUNT'),
            ('ABYS_READING_PLAN_ID'),('ABYS_POOL_DEBT'),('ABYS_POOL_DEBT_COUNT'),
            ('ABYS_SBS_PARENT_ID'),('ABYS_HOUSEHOLDS_COUNT')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_hhd_loc_inv_tran')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_hhd_loc_inv_tran eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_hhd_loc_inv_tran hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_HHD_LOC_INV_TRAN_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_HHD_LOC_INV_TRAN_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_HHD_LOC_INV_TRAN_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    IF @RaiseOnMissing = 0
        SELECT N'LS_READING + LS_005_01_hhd_loc_inv_tran dogrulama OK (v2, view yok)' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_VALIDATE_ALL @RaiseOnMissing = 0;
GO
