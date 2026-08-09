/* ============================================================
   OPS: INVOICE.LREF → LS_005_01_hhd_loc_inv_tran (tum kolonlar)
   LREF = IDENTITY (INV.LREF kullanilmaz)
   ABYS_ID = NULL (migrate satiri degil)
   Sonra INV.READ_TRANSREF = yeni HHD.LREF
   ============================================================ */
USE energy;
GO

CREATE OR ALTER PROCEDURE dbo.SP_OPS_HHD_CREATE_FROM_INVOICE
    @InvLref    INT,
    @DryRun     BIT = 0,
    @Force      BIT = 0,   -- 1: READ_TRANSREF dolu olsa da yeni uret + guncelle
    @NewHhdLref INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @NewHhdLref = NULL;

    IF NOT EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_INVOICE WHERE LREF = @InvLref
    )
        THROW 50001, N'INVOICE LREF bulunamadi.', 1;

    DECLARE @ExistingRef INT =
        (SELECT READ_TRANSREF FROM energy.dbo.LS_005_01_INVOICE WHERE LREF = @InvLref);

    IF @Force = 0 AND @ExistingRef IS NOT NULL
       AND EXISTS (
           SELECT 1 FROM energy.dbo.LS_005_01_hhd_loc_inv_tran t
           WHERE t.LREF = @ExistingRef
       )
    BEGIN
        SET @NewHhdLref = @ExistingRef;
        RAISERROR('SKIP: INV=%d zaten READ_TRANSREF=%d (HHD var).', 0, 1, @InvLref, @ExistingRef) WITH NOWAIT;
        RETURN;
    END

    IF @DryRun = 1
    BEGIN
        RAISERROR('DRYRUN: INV=%d icin stub HHD olusturulacak.', 0, 1, @InvLref) WITH NOWAIT;
        RETURN;
    END

    DECLARE @Out TABLE (HhdLref INT NOT NULL);

    BEGIN TRANSACTION;

    INSERT INTO energy.dbo.LS_005_01_hhd_loc_inv_tran (
        /* LREF IDENTITY — yazilmaz */
        ABYS_ID,
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
    OUTPUT INSERTED.LREF INTO @Out (HhdLref)
    SELECT
        /* ABYS_ID */ NULL,

        /* read_no */ 0,
        /* loc_region */ 4102,
        /* read_date */
        ISNULL(
            CASE
                WHEN ISNULL(inv.ABYS_READING_DATE, inv.DATE_) IS NULL THEN NULL
                WHEN CAST(ISNULL(inv.ABYS_READING_DATE, inv.DATE_) AS DATETIME2) < '1900-01-01' THEN NULL
                WHEN CAST(ISNULL(inv.ABYS_READING_DATE, inv.DATE_) AS DATETIME2) > '2079-06-06 23:59:00' THEN NULL
                ELSE CAST(ISNULL(inv.ABYS_READING_DATE, inv.DATE_) AS SMALLDATETIME)
            END,
            CAST('19000101' AS SMALLDATETIME)
        ),
        /* loc_id */
        ISNULL(LEFT(CAST(inv.ABYS_INSTALLATION_ID AS VARCHAR(15)), 15), ''),
        /* bina_id */ CAST(NULL AS INT),
        /* seq_no */ 0,
        /* reader_comp */ 0,
        /* reader_prsnl */ CAST(NULL AS NVARCHAR(50)),
        /* reader_prsnl_id */ 0,

        /* inv_id */ LEFT(ISNULL(inv.FICHENO, ''), 16),
        /* inv_date */
        ISNULL(
            CASE
                WHEN inv.DATE_ IS NULL THEN NULL
                WHEN CAST(inv.DATE_ AS DATETIME2) < '1900-01-01' THEN NULL
                WHEN CAST(inv.DATE_ AS DATETIME2) > '2079-06-06 23:59:00' THEN NULL
                ELSE CAST(inv.DATE_ AS SMALLDATETIME)
            END,
            CAST('19000101' AS SMALLDATETIME)
        ),
        /* inv_first_date */ CAST(NULL AS SMALLDATETIME),
        /* inv_last_date */
        ISNULL(
            CASE
                WHEN inv.DUEDATE IS NULL THEN NULL
                WHEN CAST(inv.DUEDATE AS DATETIME2) < '1900-01-01' THEN NULL
                WHEN CAST(inv.DUEDATE AS DATETIME2) > '2079-06-06 23:59:00' THEN NULL
                ELSE CAST(inv.DUEDATE AS SMALLDATETIME)
            END,
            CAST('19000101' AS SMALLDATETIME)
        ),
        /* inv_ref */ CAST(inv.ABYS_ACCOUNT_ID AS BIGINT),

        /* cnt_id */ CAST(TRY_CAST(inv.ABYS_METER_ID AS BIGINT) AS INT),
        /* cnt_serial */ CAST(NULL AS NVARCHAR(20)),
        /* cnt_mbar */ CAST(NULL AS NVARCHAR(15)),
        /* cnt_digit */ CAST(NULL AS SMALLINT),
        /* cnt_direction */ CAST(0 AS BIT),

        /* cust_id */ CAST(inv.CLIENTREF AS INT),
        /* cust_suffix */ CAST(90 AS SMALLINT),
        /* cust_name */ CAST(NULL AS NVARCHAR(70)),
        /* cust_address */ CAST(NULL AS NVARCHAR(150)),

        /* first_read_date */ CAST( AS SMALLDATETIME),
        /* last_read_date */
        CASE
            WHEN ISNULL(inv.ABYS_READING_DATE, inv.DATE_) IS NULL THEN NULL
            WHEN CAST(ISNULL(inv.ABYS_READING_DATE, inv.DATE_) AS DATETIME2) < '1900-01-01' THEN NULL
            WHEN CAST(ISNULL(inv.ABYS_READING_DATE, inv.DATE_) AS DATETIME2) > '2079-06-06 23:59:00' THEN NULL
            ELSE CAST(ISNULL(inv.ABYS_READING_DATE, inv.DATE_) AS SMALLDATETIME)
        END,
        /* first_read_ind */ CAST(inv.ABYS_ AS NUMERIC(15,2)),
        /* last_read_ind */ CAST(NULL AS NUMERIC(15,2)),

        /* expend_quantity */ TRY_CAST(inv.ABYS_M3 AS NUMERIC(15,2)),
        /* corr_coef */ CAST(NULL AS NUMERIC(14,5)),
        /* corr_volume */ CAST(inv.ABYS_CONSUMPTION AS NUMERIC(15,2)),

        /* actual_top_cal_value */ CAST(0 AS NUMERIC(15,2)),
        /* avg_top_cal_value */ CAST(0 AS NUMERIC(15,2)),
        /* expend_energy */ TRY_CAST(inv.ABYS_KWH AS NUMERIC(15,2)),

        /* retail_price2 */ CAST(NULL AS NUMERIC(15,6)),
        /* retail_price3 */ CAST(NULL AS NUMERIC(15,8)),
        /* price_id */ CAST(NULL AS SMALLINT),
        /* price_desc */ CAST(NULL AS NVARCHAR(20)),

        /* default_fine */ ISNULL(TRY_CAST(inv.DEFAULT_FINE AS NUMERIC(15,2)), 0),
        /* default_fine_tax */ ISNULL(TRY_CAST(inv.DEFAULT_FINETAX AS NUMERIC(15,2)), 0),
        /* gas_open_fee */ ISNULL(TRY_CAST(inv.gas_open_fee AS NUMERIC(15,2)), 0),
        /* detach_attach_fee */ ISNULL(TRY_CAST(inv.detach_attach_fee AS NUMERIC(15,2)), 0),
        /* test_fee */ ISNULL(TRY_CAST(inv.test_fee AS NUMERIC(15,2)), 0),
        /* spec_serv_fee */ ISNULL(TRY_CAST(inv.spec_serv_fee AS NUMERIC(15,2)), 0),
        /* illegal_use_fee */ TRY_CAST(inv.illegal_use_fee AS NUMERIC(15,2)),
        /* fixed_fee */ ISNULL(TRY_CAST(inv.fixed_fee AS NUMERIC(15,2)), 0),
        /* fixed_fee_tax */ CAST(0 AS NUMERIC(15,2)),
        /* expend_fee */ TRY_CAST(inv.expend_fee AS NUMERIC(15,2)),
        /* expend_fee_tax */ CAST(NULL AS NUMERIC(15,2)),
        /* discount_addition */ ISNULL(TRY_CAST(inv.discount_addition AS NUMERIC(15,2)), 0),
        /* round_amt */ CAST(NULL AS NUMERIC(15,2)),
        /* turnover_amt */ CAST(NULL AS NUMERIC(15,2)),

        /* total */ TRY_CAST(inv.TLTOTAL AS NUMERIC(15,2)),
        /* total_tax */ TRY_CAST(inv.TAX AS NUMERIC(15,2)),
        /* payable_total */ TRY_CAST(inv.PAYABLETOTAL AS NUMERIC(15,2)),

        /* KDV */ ISNULL(TRY_CAST(inv.TAX AS NUMERIC(15,2)), 0),
        /* OTV */ CAST(NULL AS NUMERIC(15,8)),
        /* BHAB */ CAST(0 AS NUMERIC(15,2)),
        /* FATSBT */ CAST(0 AS NUMERIC(15,2)),
        /* discount_rate */ CAST(0 AS NUMERIC(14,5)),
        /* interest_rate */ ISNULL(TRY_CAST(inv.INTERESTRATE AS NUMERIC(15,2)), 0),
        /* min_total */ CAST(0 AS NUMERIC(15,2)),
        /* min_expend */ ISNULL(TRY_CAST(inv.Qmin AS NUMERIC(15,2)), 0),
        /* max_expend */ ISNULL(TRY_CAST(inv.Qmax AS NUMERIC(15,2)), 0),

        /* rec_status */ CAST(0 AS SMALLINT),
        /* read_status */ CAST(0 AS SMALLINT),
        /* cnt_status */ CAST(0 AS SMALLINT),
        /* read_count */ CAST(NULL AS SMALLINT),
        /* cust_type */ CAST(inv.OWNERTYPE AS TINYINT),

        /* ADDUSER */ inv.ADDUSER,  -- 571'de zaten +10000 mapli
        /* ADDDATE */
        CASE
            WHEN inv.ADDDATE IS NULL THEN NULL
            WHEN CAST(inv.ADDDATE AS DATETIME2) < '1900-01-01' THEN NULL
            WHEN CAST(inv.ADDDATE AS DATETIME2) > '2079-06-06 23:59:00' THEN NULL
            ELSE CAST(inv.ADDDATE AS SMALLDATETIME)
        END,

        /* fee refs */ CAST(NULL AS INT), CAST(NULL AS INT), CAST(NULL AS INT),
                       CAST(NULL AS INT), CAST(NULL AS INT), CAST(NULL AS INT),

        /* AGRID */ agr.LREF,
        /* INV_INSTALLMENT_TOTAL */ CAST(NULL AS FLOAT),
        /* INV_INSTALLMENT_REF */ CAST(inv.INSTALLMENT_PLAN_REF AS INT),

        /* real_date */ CAST(ISNULL(inv.ABYS_READING_DATE, inv.DATE_) AS DATETIME),
        /* CS_APPREF */ CAST(NULL AS INT),
        /* UNDERLIMIT */ CAST(NULL AS FLOAT),
        /* UNDERLIMITSTAT */ CAST(NULL AS INT),
        /* CANCELLED */ CAST(CASE WHEN ISNULL(inv.CANCELED, 0) <> 0 THEN 1 ELSE 0 END AS BIT),

        /* longitude */ CAST(NULL AS FLOAT),
        /* latitude */ CAST(NULL AS FLOAT),

        /* SKB_TOTAL_AMOUNT */ CAST(NULL AS DECIMAL(16,6)),
        /* GAS_TOTAL_AMOUNT */ CAST(NULL AS DECIMAL(16,8)),
        /* SKB_UNITPRICE_KWH */ CAST(NULL AS DECIMAL(16,8)),
        /* GAS_UNITPRICE_KWH */ CAST(NULL AS DECIMAL(16,8)),

        /* CalculatedRealCost */ CAST(NULL AS DECIMAL(15,2)),
        /* RealCost */ CAST(NULL AS DECIMAL(15,6)),

        /* Content */ CAST(inv.DESCRIPTION AS NVARCHAR(MAX)),
        /* DESCRIPTION */ LEFT(inv.DESCRIPTION, 500),
        /* BILLDESCRIPTION */ LEFT(ISNULL(inv.DESCRIPTION, inv.FICHENO), 500),
        /* PERIOD */ inv.PERIOD,

        /* ABYS_CORRECTED_SM3 */ CAST(NULL AS DECIMAL(16,6)),
        /* ABYS_SM3 */ TRY_CAST(inv.ABYS_M3 AS DECIMAL(13,3)),
        /* ABYS_ACA_DESC */ CAST(NULL AS NVARCHAR(4000)),
        /* ABYS_ACC_DESC */ CAST(NULL AS NVARCHAR(4000)),
        /* ABYS_STATUS */ CAST(NULL AS SMALLINT),
        /* ABYS_STATUS_VAL */ CAST(NULL AS NVARCHAR(100)),
        /* ABYS_INSTALLATION_ID */ inv.ABYS_INSTALLATION_ID,
        /* ABYS_SUBSCRIBER_TYPE_ID */ inv.ABYS_SUBSCRIBER_TYPE_ID,
        /* ABYS_ACTIVITY_TYPE_ID */ CAST(NULL AS BIGINT),
        /* ABYS_TARIFF_TYPE_ID */ inv.ABYS_TARIFF_TYPE_ID,
        /* ABYS_PRE_METER_STATUS_ID */ CAST(NULL AS BIGINT),
        /* ABYS_AVG_CONSUMPTION */ CAST(NULL AS DECIMAL(16,6)),
        /* ABYS_ADD_CONSUMPTION */ CAST(NULL AS DECIMAL(16,6)),
        /* ABYS_CONSUMPTION */ inv.ABYS_CONSUMPTION,
        /* ABYS_CONSUMPTION_1..5 */ CAST(NULL AS DECIMAL(16,6)), CAST(NULL AS DECIMAL(16,6)),
                                    CAST(NULL AS DECIMAL(16,6)), CAST(NULL AS DECIMAL(16,6)),
                                    CAST(NULL AS DECIMAL(16,6)),
        /* ABYS_PRE_BILL_DATE */ CAST(NULL AS DATETIME2(0)),
        /* ABYS_TOTAL_DEBT */ CAST(NULL AS DECIMAL(10,2)),
        /* ABYS_TOTAL_INSTALLMENT_DEBT */ CAST(NULL AS DECIMAL(10,2)),
        /* ABYS_TOTAL_CREDIT */ CAST(NULL AS DECIMAL(10,2)),
        /* ABYS_DEBT_BILL_COUNT */ CAST(NULL AS SMALLINT),
        /* ABYS_NOTE */ LEFT(N'OPS_FROM_INVOICE:' + CAST(inv.LREF AS NVARCHAR(20)), 500),
        /* ABYS_TERMINAL_SYNC_CLIENT_ID */ CAST(NULL AS BIGINT),
        /* ABYS_TERMINAL_UPLOAD_TIME */ CAST(NULL AS DATETIME2(0)),
        /* ABYS_WORKMAN_USER_ID */ CAST(NULL AS BIGINT),
        /* ABYS_INSTALLATION_STATUS_ID */ CAST(NULL AS SMALLINT),
        /* ABYS_ACCOUNT_ID */ inv.ABYS_ACCOUNT_ID,
        /* ABYS_RECREATE_READING_ID */ CAST(NULL AS BIGINT),
        /* ABYS_READING_DAY */ CAST(NULL AS SMALLINT),
        /* ABYS_HAS_BARCODE */ CAST(NULL AS SMALLINT),
        /* ABYS_IS_BARCODE_READING */ CAST(NULL AS SMALLINT),
        /* ABYS_IS_FPS */ CAST(inv.ABYS_IS_FPS AS SMALLINT),
        /* ABYS_ERR_CODE */ CAST(NULL AS NVARCHAR(10)),
        /* ABYS_ERR_TEXT */ CAST(NULL AS NVARCHAR(4000)),
        /* ABYS_READING_METER_NUMBER */ CAST(NULL AS NVARCHAR(25)),
        /* ABYS_READING_END_OF_DAY_ID */ CAST(NULL AS BIGINT),
        /* ABYS_OPEN_CUT_FEE */ CAST(NULL AS DECIMAL(10,2)),
        /* ABYS_SKB_TARIFF_TYPE_ID */ inv.ABYS_SKB_TARIFF_TYPE_ID,
        /* ABYS_SKB_UNIT_PRICE */ CAST(inv AS DECIMAL(10,9)),
        /* ABYS_BUILDING_FLAT_ID */ CAST(NULL AS BIGINT),
        /* ABYS_GAS_LEVEL_DAY_COUNT */ CAST(NULL AS SMALLINT),
        /* ABYS_GAS_LEVEL_DAY_LIMIT */ CAST(NULL AS DECIMAL(15,3)),
        /* ABYS_LAST_PICTURE_DATE */ CAST(NULL AS DATETIME2(0)),
        /* ABYS_DESERVED_DISCOUNT_M3 */ CAST(NULL AS DECIMAL(10,3)),
        /* ABYS_GAS_LEVEL1_AMOUNT */ CAST(NULL AS DECIMAL(10,8)),
        /* ABYS_GAS_LEVEL2_AMOUNT */ CAST(NULL AS DECIMAL(10,8)),
        /* ABYS_TOLERATED_M3 */ CAST(NULL AS DECIMAL(16,6)),
        /* ABYS_DEBT_BEN_REGISTER */ CAST(NULL AS DECIMAL(10,2)),
        /* ABYS_BILL_DESCRIPTION */ LEFT(inv.DESCRIPTION, 1000),
        /* ABYS_REAL_COST */ CAST(NULL AS DECIMAL(19,8)),
        /* ABYS_CALCULATED_REAL_COST */ CAST(NULL AS DECIMAL(19,8)),
        /* ABYS_PREV_CONSUMPTION */ CAST(NULL AS DECIMAL(16,6)),
        /* ABYS_TAX_DISCOUNT_AMOUNT */ TRY_CAST(inv.DISCOUNT_AMOUNT AS DECIMAL(15,2)),
        /* ABYS_READING_PLAN_ID */ CAST(NULL AS BIGINT),
        /* ABYS_POOL_DEBT */ CAST(NULL AS DECIMAL(10,2)),
        /* ABYS_POOL_DEBT_COUNT */ CAST(NULL AS SMALLINT),
        /* ABYS_SBS_PARENT_ID */ CAST(NULL AS BIGINT),
        /* ABYS_HOUSEHOLDS_COUNT */ CAST(NULL AS BIGINT)
    FROM energy.dbo.LS_005_01_INVOICE inv
    JOIN  energy.dbo.LS_005_01_INVLINES invl
    OUTER APPLY (
        SELECT TOP (1) a.LREF
        FROM energy.dbo.LS_005_01_AGR a
        WHERE a.ABYS_ID = inv.ABYS_AGREEMENT_ID
        ORDER BY a.LREF
    ) agr
    WHERE inv.LREF = @InvLref;

    SELECT @NewHhdLref = HhdLref FROM @Out;

    UPDATE energy.dbo.LS_005_01_INVOICE
    SET READ_TRANSREF = @NewHhdLref
    WHERE LREF = @InvLref;

    COMMIT TRANSACTION;

    RAISERROR('OK: INV=%d → HHD.LREF=%d (READ_TRANSREF guncellendi).', 0, 1, @InvLref, @NewHhdLref) WITH NOWAIT;
END
GO

/* ===================== EXEC ===================== */

-- 1) Dry-run
DECLARE @H INT;
EXEC energy.dbo.SP_OPS_HHD_CREATE_FROM_INVOICE
     @InvLref = 16590230,
     @DryRun  = 1,
     @NewHhdLref = @H OUTPUT;
SELECT @H AS NewHhdLref;

-- 2) Gercek olustur
DECLARE @H2 INT;
EXEC energy.dbo.SP_OPS_HHD_CREATE_FROM_INVOICE
     @InvLref = 16590230,
     @DryRun  = 0,
     @Force   = 0,
     @NewHhdLref = @H2 OUTPUT;
SELECT @H2 AS NewHhdLref;

-- 3) Dogrula
SELECT inv.LREF, inv.READ_TRANSREF, t.LREF AS HHD_LREF, t.ABYS_NOTE, t.inv_ref, t.total
FROM energy.dbo.LS_005_01_INVOICE inv
LEFT JOIN energy.dbo.LS_005_01_hhd_loc_inv_tran t ON t.LREF = inv.READ_TRANSREF
WHERE inv.LREF = 16590230;