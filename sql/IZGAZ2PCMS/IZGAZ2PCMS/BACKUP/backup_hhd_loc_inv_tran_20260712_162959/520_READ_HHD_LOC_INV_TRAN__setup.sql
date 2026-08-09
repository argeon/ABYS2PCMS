/* ============================================================
   SCRIPT_ID : READ_HHD_LOC_INV_TRAN_SETUP
   SCRIPT_NO : 520
   FILE      : 520_READ_HHD_LOC_INV_TRAN__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.LS_READING
--   → energy.dbo.LS_005_01_hhd_loc_inv_tran
--
-- LREF    ← kaynak LREF (IDENTITY_INSERT; int araliginda olmali)
-- ABYS_ID ← kaynak LREF (kopru)
--
-- Kaynak-only (aktarilmaz):
--   STG_SPEC_SERV_FEE_SOURCE_IDS, STG_UNMAPPED_GUVENCE_BEDELI,
--   ABYS_CORRECTED_SM3, ABYS_SM3, ABYS_ACA_DESC, ABYS_ACC_DESC
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- smalldatetime guvenli cast (garanti setup ile ayni)
-- ------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.FN_SAFE_SMALLDT_DEP (@DT DATETIME2)
RETURNS SMALLDATETIME
AS
BEGIN
    RETURN CASE
        WHEN @DT IS NULL                 THEN NULL
        WHEN @DT < '1900-01-01 00:00:00' THEN NULL
        WHEN @DT > '2079-06-06 23:59:00' THEN NULL
        ELSE CAST(@DT AS SMALLDATETIME)
    END;
END
GO

-- ------------------------------------------------------------
-- Hedef ABYS kopru kolonu
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_hhd_loc_inv_tran')
      AND name = 'ABYS_ID'
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

-- ------------------------------------------------------------
-- Kaynak dogrulama
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
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('READ_NO'), ('LOC_REGION'), ('READ_DATE'), ('LOC_ID'),
            ('BINA_ID'), ('SEQ_NO'), ('READER_COMP'), ('READER_PRSNL'), ('READER_PRSNL_ID'),
            ('INV_ID'), ('INV_REF'), ('INV_DATE'), ('INV_FIRST_DATE'), ('INV_LAST_DATE'),
            ('CNT_ID'), ('CNT_SERIAL'), ('CNT_MBAR'), ('CNT_DIGIT'), ('CNT_DIRECTION'),
            ('CUST_ID'), ('CUST_SUFFIX'), ('CUST_NAME'), ('CUST_ADDRESS'),
            ('FIRST_READ_DATE'), ('LAST_READ_DATE'), ('FIRST_READ_IND'), ('LAST_READ_IND'),
            ('EXPEND_QUANTITY'), ('CORR_COEF'), ('CORR_VOLUME'),
            ('ACTUAL_TOP_CAL_VALUE'), ('AVG_TOP_CAL_VALUE'), ('EXPEND_ENERGY'),
            ('RETAIL_PRICE2'), ('RETAIL_PRICE3'), ('PRICE_ID'), ('PRICE_DESC'),
            ('DEFAULT_FINE'), ('DEFAULT_FINE_TAX'),
            ('GAS_OPEN_FEE'), ('DETACH_ATTACH_FEE'), ('TEST_FEE'), ('SPEC_SERV_FEE'),
            ('ILLEGAL_USE_FEE'), ('FIXED_FEE'), ('FIXED_FEE_TAX'),
            ('EXPEND_FEE'), ('EXPEND_FEE_TAX'), ('DISCOUNT_ADDITION'),
            ('TOTAL'), ('TOTAL_TAX'), ('PAYABLE_TOTAL'),
            ('KDV'), ('OTV'), ('BHAB'), ('FATSBT'),
            ('DISCOUNT_RATE'), ('INTEREST_RATE'),
            ('MIN_TOTAL'), ('MIN_EXPEND'), ('MAX_EXPEND'),
            ('REC_STATUS'), ('READ_STATUS'), ('CNT_STATUS'), ('READ_COUNT'),
            ('CUST_TYPE'), ('ADDUSER'), ('ADDDATE'),
            ('GAS_OPEN_FEE_REF'), ('DETACH_ATTACH_FEE_REF'), ('TEST_FEE_REF'),
            ('SPEC_SERV_FEE_REF'), ('DISCOUNT_ADDITION_REF'), ('ILLEGAL_USE_FEE_REF'),
            ('AGRID'), ('INV_INSTALLMENT_TOTAL'), ('INV_INSTALLMENT_REF'),
            ('REAL_DATE'), ('CS_APPREF'), ('UNDERLIMIT'), ('UNDERLIMITSTAT'),
            ('CANCELLED'), ('GAS_TOTAL_AMOUNT'), ('SKB_TOTAL_AMOUNT'),
            ('ROUND_AMT'), ('TURNOVER_AMT'), ('PERIOD'),
            ('BILL_DESCRIPTION'), ('CALCULATED_REAL_COST'), ('REAL_COST'),
            ('LATITUDE'), ('LONGITUDE'),
            ('GAS_UNITPRICE_KWH'), ('SKB_UNITPRICE_KWH')
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

-- ------------------------------------------------------------
-- Hedef dogrulama
-- ------------------------------------------------------------
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
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('read_no'), ('loc_region'), ('read_date'), ('loc_id'),
            ('bina_id'), ('seq_no'), ('reader_comp'), ('reader_prsnl'), ('reader_prsnl_id'),
            ('inv_id'), ('inv_date'), ('inv_first_date'), ('inv_last_date'),
            ('cnt_id'), ('cnt_serial'), ('cnt_mbar'), ('cnt_digit'), ('cnt_direction'),
            ('cust_id'), ('cust_suffix'), ('cust_name'), ('cust_address'),
            ('first_read_date'), ('last_read_date'), ('first_read_ind'), ('last_read_ind'),
            ('expend_quantity'), ('corr_coef'), ('corr_volume'),
            ('actual_top_cal_value'), ('avg_top_cal_value'), ('expend_energy'),
            ('retail_price2'), ('retail_price3'), ('price_id'), ('price_desc'),
            ('default_fine'), ('default_fine_tax'),
            ('gas_open_fee'), ('detach_attach_fee'), ('test_fee'), ('spec_serv_fee'),
            ('illegal_use_fee'), ('fixed_fee'), ('fixed_fee_tax'),
            ('expend_fee'), ('expend_fee_tax'), ('discount_addition'),
            ('round_amt'), ('turnover_amt'),
            ('total'), ('total_tax'), ('payable_total'),
            ('KDV'), ('OTV'), ('BHAB'), ('FATSBT'),
            ('discount_rate'), ('interest_rate'),
            ('min_total'), ('min_expend'), ('max_expend'),
            ('rec_status'), ('read_status'), ('cnt_status'), ('read_count'),
            ('cust_type'), ('ADDUSER'), ('ADDDATE'),
            ('gas_open_fee_ref'), ('detach_attach_fee_ref'), ('test_fee_ref'),
            ('spec_serv_fee_ref'), ('discount_addition_ref'), ('illegal_use_fee_ref'),
            ('AGRID'), ('INV_INSTALLMENT_TOTAL'), ('INV_INSTALLMENT_REF'),
            ('real_date'), ('CS_APPREF'), ('UNDERLIMIT'), ('UNDERLIMITSTAT'),
            ('CANCELLED'), ('longitude'), ('latitude'),
            ('GAS_TOTAL_AMOUNT'), ('SKB_TOTAL_AMOUNT'),
            ('GAS_UNITPRICE_KWH'), ('SKB_UNITPRICE_KWH'),
            ('CalculatedRealCost'), ('RealCost'), ('BILLDESCRIPTION'),
            ('inv_ref'), ('PERIOD'), ('ABYS_ID')
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
        SELECT N'LS_READING kaynak + LS_005_01_hhd_loc_inv_tran hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Kaynak view
-- NOT NULL hedef kolonlar icin ISNULL / varsayilan
-- LREF int araligi disindakiler view disinda kalir
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.VW_MIG_LS005_HHD_LOC_INV_TRAN_SOURCE
AS
SELECT
    CAST(s.LREF AS BIGINT)                                                      AS ABYS_ID,
    CAST(s.LREF AS INT)                                                         AS LREF,

    ISNULL(CAST(TRY_CAST(s.READ_NO AS BIGINT) AS INT), 0)                       AS read_no,
    ISNULL(CAST(TRY_CAST(s.LOC_REGION AS BIGINT) AS INT), 0)                    AS loc_region,
    ISNULL(
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.READ_DATE AS DATETIME2)),
        CAST('19000101' AS SMALLDATETIME)
    )                                                                           AS read_date,
    ISNULL(LEFT(s.LOC_ID, 15), '')                                              AS loc_id,
    CAST(s.BINA_ID AS INT)                                                      AS bina_id,
    ISNULL(CAST(TRY_CAST(s.SEQ_NO AS BIGINT) AS INT), 0)                        AS seq_no,
    ISNULL(CAST(TRY_CAST(s.READER_COMP AS BIGINT) AS INT), 0)                   AS reader_comp,
    LEFT(s.READER_PRSNL, 50)                                                    AS reader_prsnl,
    ISNULL(CAST(TRY_CAST(s.READER_PRSNL_ID AS BIGINT) AS INT), 0)               AS reader_prsnl_id,

    LEFT(s.INV_ID, 16)                                                          AS inv_id,
    ISNULL(
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.INV_DATE AS DATETIME2)),
        CAST('19000101' AS SMALLDATETIME)
    )                                                                           AS inv_date,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.INV_FIRST_DATE AS DATETIME2))         AS inv_first_date,
    ISNULL(
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.INV_LAST_DATE AS DATETIME2)),
        CAST('19000101' AS SMALLDATETIME)
    )                                                                           AS inv_last_date,
    CAST(s.INV_REF AS BIGINT)                                                   AS inv_ref,

    CAST(TRY_CAST(s.CNT_ID AS BIGINT) AS INT)                                   AS cnt_id,
    LEFT(s.CNT_SERIAL, 20)                                                      AS cnt_serial,
    LEFT(s.CNT_MBAR, 15)                                                        AS cnt_mbar,
    CAST(TRY_CAST(s.CNT_DIGIT AS INT) AS SMALLINT)                              AS cnt_digit,
    CAST(CASE WHEN ISNULL(s.CNT_DIRECTION, 0) <> 0 THEN 1 ELSE 0 END AS BIT)    AS cnt_direction,

    CAST(TRY_CAST(s.CUST_ID AS BIGINT) AS INT)                                  AS cust_id,
    CAST(TRY_CAST(s.CUST_SUFFIX AS BIGINT) AS SMALLINT)                         AS cust_suffix,
    LEFT(s.CUST_NAME, 70)                                                       AS cust_name,
    LEFT(s.CUST_ADDRESS, 150)                                                   AS cust_address,

    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.FIRST_READ_DATE AS DATETIME2))        AS first_read_date,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.LAST_READ_DATE AS DATETIME2))         AS last_read_date,
    TRY_CAST(s.FIRST_READ_IND AS NUMERIC(15,2))                                 AS first_read_ind,
    TRY_CAST(s.LAST_READ_IND AS NUMERIC(15,2))                                  AS last_read_ind,
    TRY_CAST(s.EXPEND_QUANTITY AS NUMERIC(15,2))                                AS expend_quantity,
    TRY_CAST(s.CORR_COEF AS NUMERIC(14,5))                                      AS corr_coef,
    TRY_CAST(s.CORR_VOLUME AS NUMERIC(15,2))                                    AS corr_volume,

    ISNULL(TRY_CAST(s.ACTUAL_TOP_CAL_VALUE AS NUMERIC(15,2)), 0)                AS actual_top_cal_value,
    ISNULL(TRY_CAST(s.AVG_TOP_CAL_VALUE AS NUMERIC(15,2)), 0)                   AS avg_top_cal_value,
    TRY_CAST(s.EXPEND_ENERGY AS NUMERIC(15,2))                                  AS expend_energy,

    TRY_CAST(s.RETAIL_PRICE2 AS NUMERIC(15,6))                                  AS retail_price2,
    TRY_CAST(s.RETAIL_PRICE3 AS NUMERIC(15,8))                                  AS retail_price3,
    CAST(TRY_CAST(s.PRICE_ID AS INT) AS SMALLINT)                               AS price_id,
    LEFT(s.PRICE_DESC, 20)                                                      AS price_desc,

    ISNULL(TRY_CAST(s.DEFAULT_FINE AS NUMERIC(15,2)), 0)                        AS default_fine,
    ISNULL(TRY_CAST(s.DEFAULT_FINE_TAX AS NUMERIC(15,2)), 0)                    AS default_fine_tax,
    ISNULL(TRY_CAST(s.GAS_OPEN_FEE AS NUMERIC(15,2)), 0)                        AS gas_open_fee,
    ISNULL(TRY_CAST(s.DETACH_ATTACH_FEE AS NUMERIC(15,2)), 0)                   AS detach_attach_fee,
    ISNULL(TRY_CAST(s.TEST_FEE AS NUMERIC(15,2)), 0)                            AS test_fee,
    ISNULL(TRY_CAST(s.SPEC_SERV_FEE AS NUMERIC(15,2)), 0)                       AS spec_serv_fee,
    TRY_CAST(s.ILLEGAL_USE_FEE AS NUMERIC(15,2))                                AS illegal_use_fee,
    ISNULL(TRY_CAST(s.FIXED_FEE AS NUMERIC(15,2)), 0)                           AS fixed_fee,
    ISNULL(TRY_CAST(s.FIXED_FEE_TAX AS NUMERIC(15,2)), 0)                       AS fixed_fee_tax,
    TRY_CAST(s.EXPEND_FEE AS NUMERIC(15,2))                                     AS expend_fee,
    TRY_CAST(s.EXPEND_FEE_TAX AS NUMERIC(15,2))                                 AS expend_fee_tax,
    ISNULL(TRY_CAST(s.DISCOUNT_ADDITION AS NUMERIC(15,2)), 0)                   AS discount_addition,
    TRY_CAST(s.ROUND_AMT AS NUMERIC(15,2))                                      AS round_amt,
    TRY_CAST(s.TURNOVER_AMT AS NUMERIC(15,2))                                   AS turnover_amt,
    TRY_CAST(s.TOTAL AS NUMERIC(15,2))                                          AS total,
    TRY_CAST(s.TOTAL_TAX AS NUMERIC(15,2))                                      AS total_tax,
    TRY_CAST(s.PAYABLE_TOTAL AS NUMERIC(15,2))                                  AS payable_total,

    ISNULL(TRY_CAST(s.KDV AS NUMERIC(15,2)), 0)                                 AS KDV,
    TRY_CAST(s.OTV AS NUMERIC(15,8))                                            AS OTV,
    ISNULL(TRY_CAST(s.BHAB AS NUMERIC(15,2)), 0)                                AS BHAB,
    ISNULL(TRY_CAST(s.FATSBT AS NUMERIC(15,2)), 0)                              AS FATSBT,
    ISNULL(TRY_CAST(s.DISCOUNT_RATE AS NUMERIC(14,5)), 0)                       AS discount_rate,
    ISNULL(TRY_CAST(s.INTEREST_RATE AS NUMERIC(15,2)), 0)                       AS interest_rate,
    ISNULL(TRY_CAST(s.MIN_TOTAL AS NUMERIC(15,2)), 0)                           AS min_total,
    ISNULL(TRY_CAST(s.MIN_EXPEND AS NUMERIC(15,2)), 0)                          AS min_expend,
    ISNULL(TRY_CAST(s.MAX_EXPEND AS NUMERIC(15,2)), 0)                          AS max_expend,

    ISNULL(CAST(TRY_CAST(s.REC_STATUS AS BIGINT) AS SMALLINT), 0)               AS rec_status,
    ISNULL(CAST(s.READ_STATUS AS SMALLINT), 0)                                  AS read_status,
    ISNULL(CAST(TRY_CAST(s.CNT_STATUS AS BIGINT) AS SMALLINT), 0)               AS cnt_status,
    CAST(TRY_CAST(s.READ_COUNT AS BIGINT) AS SMALLINT)                          AS read_count,
    CAST(TRY_CAST(s.CUST_TYPE AS BIGINT) AS TINYINT)                            AS cust_type,

    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.ADDUSER AS BIGINT) AS INT)) AS ADDUSER,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ADDDATE AS DATETIME2))                AS ADDDATE,

    CAST(TRY_CAST(s.GAS_OPEN_FEE_REF AS BIGINT) AS INT)                         AS gas_open_fee_ref,
    CAST(TRY_CAST(s.DETACH_ATTACH_FEE_REF AS BIGINT) AS INT)                    AS detach_attach_fee_ref,
    CAST(TRY_CAST(s.TEST_FEE_REF AS BIGINT) AS INT)                             AS test_fee_ref,
    CAST(TRY_CAST(s.SPEC_SERV_FEE_REF AS BIGINT) AS INT)                        AS spec_serv_fee_ref,
    CAST(TRY_CAST(s.DISCOUNT_ADDITION_REF AS BIGINT) AS INT)                    AS discount_addition_ref,
    CAST(TRY_CAST(s.ILLEGAL_USE_FEE_REF AS BIGINT) AS INT)                      AS illegal_use_fee_ref,

    CAST(TRY_CAST(s.AGRID AS BIGINT) AS INT)                                    AS AGRID,
    s.INV_INSTALLMENT_TOTAL                                                     AS INV_INSTALLMENT_TOTAL,
    CAST(TRY_CAST(s.INV_INSTALLMENT_REF AS BIGINT) AS INT)                      AS INV_INSTALLMENT_REF,
    CAST(s.REAL_DATE AS DATETIME)                                               AS real_date,
    CAST(TRY_CAST(s.CS_APPREF AS BIGINT) AS INT)                                AS CS_APPREF,
    s.UNDERLIMIT                                                                AS UNDERLIMIT,
    CAST(TRY_CAST(s.UNDERLIMITSTAT AS BIGINT) AS INT)                           AS UNDERLIMITSTAT,
    CAST(CASE WHEN ISNULL(TRY_CAST(s.CANCELLED AS BIGINT), 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS CANCELLED,

    s.LONGITUDE                                                                 AS longitude,
    s.LATITUDE                                                                  AS latitude,

    TRY_CAST(s.SKB_TOTAL_AMOUNT AS DECIMAL(16,6))                               AS SKB_TOTAL_AMOUNT,
    TRY_CAST(s.GAS_TOTAL_AMOUNT AS DECIMAL(16,8))                               AS GAS_TOTAL_AMOUNT,
    TRY_CAST(s.SKB_UNITPRICE_KWH AS DECIMAL(16,8))                              AS SKB_UNITPRICE_KWH,
    TRY_CAST(s.GAS_UNITPRICE_KWH AS DECIMAL(16,8))                              AS GAS_UNITPRICE_KWH,

    TRY_CAST(s.CALCULATED_REAL_COST AS DECIMAL(15,2))                           AS CalculatedRealCost,
    TRY_CAST(s.REAL_COST AS DECIMAL(15,6))                                      AS RealCost,
    LEFT(s.BILL_DESCRIPTION, 500)                                               AS BILLDESCRIPTION,
    s.PERIOD                                                                    AS PERIOD
FROM izgazMGR.dbo.LS_READING s
WHERE s.LREF IS NOT NULL
  AND s.LREF BETWEEN 1 AND 2147483647
  AND s.BINA_ID BETWEEN -2147483648 AND 2147483647;
GO

IF OBJECT_ID('dbo.SP_MIGRATE_LS005_HHD_LOC_INV_TRAN', 'P') IS NOT NULL
    EXEC sys.sp_refreshsqlmodule N'dbo.SP_MIGRATE_LS005_HHD_LOC_INV_TRAN';
GO

EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_VALIDATE_ALL @RaiseOnMissing = 0;
GO
