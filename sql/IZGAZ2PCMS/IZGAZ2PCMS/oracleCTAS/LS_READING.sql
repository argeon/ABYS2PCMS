-- =====================================================================================
-- LS_READING CTAS - v03  
-- Okuma Verilerinin Çıkışı için 4 alt 1 ana tablo CTAS hazılandı
--
-- Not: Stage 1 (STG_RD_SYNC_USER)
--		Stage 2 (STG_RD_USER_COMP) ve
--      Stage 3 (STG_RD_READING_INC)
--      Stage 4 (STG_RD_ACC_INC) 
--      STG_RD_ tabloları oluşturulduktan sonra sadece   MAIN bloklarini veri desenini karşılar.
-- =====================================================================================
-- =====================================================================================
-- STAGE 1: Sync Client -> Kullanici cozumu
-- =====================================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE SMS.STG_RD_SYNC_USER PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE SMS.STG_RD_SYNC_USER NOLOGGING AS
SELECT SYNC_CLIENT_ID, USER_ID, USER_NAME
FROM (
    SELECT opr.ID       AS SYNC_CLIENT_ID,
           iu.ID        AS USER_ID,
           iu.USER_NAME AS USER_NAME,
           ROW_NUMBER() OVER (PARTITION BY opr.ID ORDER BY iu.ID) AS RN
    FROM SMS.OPR_SYNC_CLIENT       opr
    JOIN SMS.CS_REGISTER_RELATION  rr ON rr.ID = opr.REGISTER_REL_ID
    JOIN SMS.IT_USER               iu ON iu.REGISTER_ID = rr.RELATIONAL_REGISTER_ID
)
WHERE RN = 1;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('SMS','STG_RD_SYNC_USER'); END;

-- =====================================================================================
-- STAGE 2: Kullanici -> Firma Register cozumu
-- =====================================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE SMS.STG_RD_USER_COMP PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE SMS.STG_RD_USER_COMP NOLOGGING AS
SELECT USER_ID, USER_NAME, COMP_REGISTER_ID
FROM (
    SELECT usr.ID          AS USER_ID,
           usr.USER_NAME   AS USER_NAME,
           crr.REGISTER_ID AS COMP_REGISTER_ID,
           ROW_NUMBER() OVER (PARTITION BY usr.ID ORDER BY crr.ID DESC) AS RN
    FROM SMS.IT_USER              usr
    JOIN SMS.CS_REGISTER_RELATION crr ON crr.RELATIONAL_REGISTER_ID = usr.REGISTER_ID
)
WHERE RN = 1;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('SMS','STG_RD_USER_COMP'); END;
/
-- =====================================================================================
-- STAGE 3: CS_READING_INCOME pivot 
-- =====================================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE SMS.STG_RD_READING_INC PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE SMS.STG_RD_READING_INC NOLOGGING PARALLEL 8 AS
SELECT /*+ FULL(ri) PARALLEL(ri 8) */
    ri.READING_ID,

    SUM(CASE WHEN ri.INCOME_ID IN (169, 60) THEN ri.AMOUNT END)   AS TOTAL_TAX,
    SUM(CASE WHEN ri.INCOME_ID = 939  THEN ri.AMOUNT END)         AS GAS_TOTAL_AMOUNT,
    SUM(CASE WHEN ri.INCOME_ID = 1929 THEN ri.AMOUNT END)         AS ROUND_AMT,
    SUM(CASE WHEN ri.INCOME_ID = 958  THEN ri.AMOUNT END)         AS TURNOVER_AMT,
    SUM(CASE WHEN ri.INCOME_ID = 7658 THEN ri.AMOUNT END)         AS SKB_TOTAL_AMOUNT,
    SUM(CASE WHEN ri.INCOME_ID = 1864 THEN ri.AMOUNT END)         AS DEFAULT_FINE,
    SUM(CASE WHEN ri.INCOME_ID = 1905 THEN ri.AMOUNT END)         AS DEFAULT_FINE_TAX,

    SUM(CASE WHEN ri.INCOME_ID = 1861 THEN ri.AMOUNT END)         AS GAS_OPEN_FEE,
    MAX(CASE WHEN ri.INCOME_ID = 1861 THEN ri.ID END)             AS GAS_OPEN_FEE_REF,

    SUM(CASE WHEN ri.INCOME_ID = 100  THEN ri.AMOUNT END)         AS DISCOUNT_ADDITION,
    MAX(CASE WHEN ri.INCOME_ID = 100  THEN ri.ID END)             AS DISCOUNT_ADDITION_REF,

    SUM(CASE WHEN ri.INCOME_ID = 1902 THEN ri.AMOUNT END)         AS ILLEGAL_USE_FEE,
    MAX(CASE WHEN ri.INCOME_ID = 1902 THEN ri.ID END)             AS ILLEGAL_USE_FEE_REF,

    SUM(CASE WHEN ri.INCOME_ID IN
            (2981, 572, 938, 23033, 573, 23034, 23031, 23032, 2982,
             576, 574, 3251, 12531, 579, 47, 578, 581, 575, 7709,
             577, 7504, 2521, 7528, 7464, 2847, 2446, 2649, 2520,
             7408, 2591, 7496, 2583, 3067)
         THEN ri.AMOUNT END)                                      AS SPEC_SERV_FEE,

    LISTAGG(
        CASE WHEN ri.INCOME_ID IN
            (2981, 572, 938, 23033, 573, 23034, 23031, 23032, 2982,
             576, 574, 3251, 12531, 579, 47, 578, 581, 575, 7709,
             577, 7504, 2521, 7528, 7464, 2847, 2446, 2649, 2520,
             7408, 2591, 7496, 2583, 3067)
            THEN TO_CHAR(ri.INCOME_ID) END,
        ','
    ) WITHIN GROUP (ORDER BY ri.INCOME_ID)                        AS SPEC_SERV_FEE_INCOME_IDS,

    SUM(CASE WHEN ri.INCOME_ID = 162 THEN ri.AMOUNT END)          AS UNMAPPED_GUVENCE_BEDELI

FROM SMS.CS_READING_INCOME ri
GROUP BY ri.READING_ID;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('SMS','STG_RD_READING_INC'); END;
/

-- =====================================================================================
-- STAGE 4: CS_ACCOUNT_INCOME aggregate (ACTION_TYPE_ID = 1)
-- =====================================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE SMS.STG_RD_ACC_INC PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE SMS.STG_RD_ACC_INC NOLOGGING PARALLEL 8 AS
SELECT /*+ FULL(aca) FULL(ai) PARALLEL(8) */
    aca.ACCOUNT_ID,
    aca.ID                                                          AS ACA_ID,
    aca.DESCRIPTION                                                 AS ACA_DESC,
    SUM(CASE WHEN ai.INCOME_ID IN (939, 7658)  THEN ai.AMOUNT END)  AS EXPEND_FEE,
    SUM(CASE WHEN ai.INCOME_ID NOT IN (169,60) THEN ai.AMOUNT END)  AS TOTAL_EXCL_TAX,
    SUM(CASE WHEN ai.INCOME_ID IN (169, 60)    THEN ai.AMOUNT END)  AS TOTAL_TAX,
    SUM(ai.AMOUNT)                                                  AS PAYABLE_TOTAL
FROM SMS.CS_ACCOUNT_ACTION aca
LEFT JOIN SMS.CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = aca.ID
WHERE aca.ACTION_TYPE_ID = 1
GROUP BY aca.ACCOUNT_ID, aca.ID, aca.DESCRIPTION;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('SMS','STG_RD_ACC_INC'); END;
/

-- =====================================================================================
-- MAIN CTAS: LS_READING (FULL LOAD - pilot filtre yorumda)
-- =====================================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE SMS.LS_READING PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE SMS.LS_READING
NOLOGGING
PARALLEL 8
AS
SELECT  
    r.ID                                                        AS LREF,

    CAST(NULL AS NUMBER(10,0))                                  AS read_no,
    4102                                                        AS loc_region,
    r.BILL_DATE                                                 AS read_date,
    CAST(r.INSTALLATION_ID AS VARCHAR2(15))                     AS loc_id,
    bd.ID                                                       AS bina_id,
    r.TERMINAL_ORDER                                            AS seq_no,

    uc.COMP_REGISTER_ID                                         AS reader_comp,
    uc.USER_NAME                                                AS reader_prsnl,
    CASE WHEN r.WORKMAN_USER_ID IS NULL
         THEN scu.USER_ID
         ELSE 10000 + r.WORKMAN_USER_ID END                     AS reader_prsnl_id,

    r.BILL_SERIAL || '' || r.BILL_ORDER_NUMBER                  AS inv_id,
    r.ACCOUNT_ID                                                AS inv_ref,

    r.BILL_DATE                                                 AS inv_date,
    r.BILL_DATE + 1                                             AS inv_first_date,
    r.EXPIRY_DATE                                               AS inv_last_date,

    COALESCE(acc.PRE_READING_DATE, r.PRE_BILL_DATE)             AS first_read_date,
    r.BILL_DATE                                                 AS last_read_date,

    r.METER_ID                                                  AS cnt_id,
    COALESCE(r.READING_METER_NUMBER, m.METER_NUMBER, r.SAYAC_NUMARASI_)
                                                                AS cnt_serial,
    CAST(NULL AS VARCHAR2(15))                                  AS cnt_mbar,
    CAST(NULL AS NUMBER(5,0))                                   AS cnt_digit,
    CAST(NULL AS NUMBER(1,0))                                   AS cnt_direction,

    rr.ID                                                       AS cust_id,
    90                                                          AS cust_suffix,
    rr.FIRST_NAME || ' ' || rr.LAST_NAME                        AS cust_name,
    CAST(NULL AS VARCHAR2(150))                                 AS cust_address,

    ri1.FIRST_INDEX                                             AS first_read_ind,
    ri1.LAST_INDEX                                              AS last_read_ind,

    (ri1.LAST_INDEX - ri1.FIRST_INDEX)                          AS expend_quantity,
    r.ADJUSTMENT_COEFFICIENT                                    AS corr_coef,
    ROUND(((r.CORRECTED_SM3 * r.HIGH_HEATING_VALUE) / 9155), 5) AS corr_volume,

    9155                                                        AS actual_top_cal_value,
    r.HIGH_HEATING_VALUE                                        AS avg_top_cal_value,
    r.KWH                                                       AS expend_energy,

    CAST(ROUND((r.UNIT_PRICE + r.SKB_UNIT_PRICE) * 10.64, 8) AS NUMBER(15,6)) AS retail_price2,
    CAST((r.UNIT_PRICE + r.SKB_UNIT_PRICE)                    AS NUMBER(15,8)) AS retail_price3,
    CAST(NULL AS NUMBER(5,0))                                   AS price_id,
    CAST(NULL AS VARCHAR2(20))                                  AS price_desc,

    CAST(COALESCE(pv.DEFAULT_FINE, 0)     AS NUMBER(15,2))      AS default_fine,
    CAST(COALESCE(pv.DEFAULT_FINE_TAX, 0) AS NUMBER(15,2))      AS default_fine_tax,
    CAST(COALESCE(pv.GAS_OPEN_FEE, 0)     AS NUMBER(15,2))      AS gas_open_fee,
    0                                                           AS detach_attach_fee,
    0                                                           AS test_fee,
    CAST(COALESCE(pv.SPEC_SERV_FEE, 0)    AS NUMBER(15,2))      AS spec_serv_fee,
    CAST(COALESCE(pv.ILLEGAL_USE_FEE, 0)  AS NUMBER(15,2))      AS illegal_use_fee,
    0                                                           AS fixed_fee,
    0                                                           AS fixed_fee_tax,

    CAST(av.EXPEND_FEE AS NUMBER(15,2))                         AS expend_fee,
    CAST(ROUND(av.EXPEND_FEE *
         CASE WHEN r.BILL_DATE < DATE '2023-07-10' THEN 0.18 ELSE 0.20 END, 2)
         AS NUMBER(15,2))                                       AS expend_fee_tax,

    COALESCE(pv.DISCOUNT_ADDITION, r.TOTAL_CREDIT, 0)           AS discount_addition,

    CAST(av.TOTAL_EXCL_TAX  AS NUMBER(15,2))                    AS total,
    CAST(av.TOTAL_TAX       AS NUMBER(15,2))                    AS total_tax,
    CAST(av.PAYABLE_TOTAL   AS NUMBER(15,2))                    AS payable_total,

    CASE WHEN r.BILL_DATE < DATE '2023-07-10' THEN 18 ELSE 20 END AS KDV,

    r.TAX_DISCOUNT_AMOUNT                                       AS OTV,
    0                                                           AS BHAB,
    0                                                           AS FATSBT,
    0                                                           AS discount_rate,
    0                                                           AS interest_rate,

    0                                                           AS min_total,
    0                                                           AS min_expend,
    r.MAX_CONSUMPTION                                           AS max_expend,

    4                                                           AS rec_status,

    CASE WHEN r.STATUS = 0  THEN 9
         WHEN r.STATUS = 1  THEN 10
         WHEN r.STATUS = 2  THEN 11
         WHEN r.STATUS = 3  THEN 12
         WHEN r.STATUS = 4  THEN 8
         WHEN r.STATUS = 5  THEN 14
         WHEN r.STATUS = 6  THEN 15
         WHEN r.STATUS = 7  THEN 16
         WHEN r.STATUS = 8  THEN 17
         WHEN r.STATUS = 9  THEN 18
         WHEN r.STATUS = 10 THEN 19
         WHEN r.STATUS = 11 THEN 20
         WHEN r.STATUS = 12 THEN 21
         WHEN r.STATUS = 13 THEN 22
    END                                                         AS read_status,
    r.METER_STATUS_ID                                           AS cnt_status,

    1                                                           AS read_count,
    91                                                          AS cust_type,

    r.CREATED_USER_ID                                           AS ADDUSER,
    r.CREATED_TIMESTAMP                                         AS ADDDATE,
    r.UPDATED_USER_ID                                           AS UPDUSER,
    r.UPDATED_TIMESTAMP                                         AS UPDDATE,

    pv.GAS_OPEN_FEE_REF                                         AS gas_open_fee_ref,
    CAST(NULL AS NUMBER(10,0))                                  AS detach_attach_fee_ref,
    CAST(NULL AS NUMBER(10,0))                                  AS test_fee_ref,
    CAST(NULL AS NUMBER(10,0))                                  AS spec_serv_fee_ref,
    pv.DISCOUNT_ADDITION_REF                                    AS discount_addition_ref,
    pv.ILLEGAL_USE_FEE_REF                                      AS illegal_use_fee_ref,

    r.AGREEMENT_ID                                              AS AGRID,
    r.TOTAL_INSTALLMENT_DEBT                                    AS INV_INSTALLMENT_TOTAL,
    0                                                           AS INV_INSTALLMENT_REF,
    r.BILL_DATE                                                 AS real_date,
    r.WORK_ID                                                   AS CS_APPREF,
    CAST(NULL AS FLOAT)                                         AS UNDERLIMIT,
    CAST(NULL AS NUMBER(10,0))                                  AS UNDERLIMITSTAT,
    CASE WHEN r.STATUS = 5 THEN 1 ELSE 0 END                    AS CANCELLED,

    CAST(COALESCE(pv.GAS_TOTAL_AMOUNT, 0) AS NUMBER(15,2))      AS GAS_TOTAL_AMOUNT,
    CAST(COALESCE(pv.SKB_TOTAL_AMOUNT, 0) AS NUMBER(15,2))      AS SKB_TOTAL_AMOUNT,
    CAST(COALESCE(pv.ROUND_AMT, 0)        AS NUMBER(15,2))      AS round_amt,
    CAST(COALESCE(pv.TURNOVER_AMT, 0)     AS NUMBER(15,2))      AS turnover_amt,

    r.PERIOD                                                    AS PERIOD,

    pv.SPEC_SERV_FEE_INCOME_IDS                                 AS STG_SPEC_SERV_FEE_SOURCE_IDS,
    pv.UNMAPPED_GUVENCE_BEDELI                                  AS STG_UNMAPPED_GUVENCE_BEDELI,

    r.CORRECTED_SM3                                             AS ABYS_CORRECTED_SM3,
    r.SM3                                                       AS ABYS_SM3,
    av.ACA_DESC                                                 AS ABYS_ACA_DESC,
    acc.DESCRIPTION                                             AS ABYS_ACC_DESC,
    r.BILL_DESCRIPTION,
    r.CALCULATED_REAL_COST,
    r.REAL_COST,

    r.LATITUDE                                                  AS latitude,
    r.LONGITUDE                                                 AS longitude,

    r.UNIT_PRICE                                                AS GAS_UNITPRICE_KWH,
    r.SKB_UNIT_PRICE                                            AS SKB_UNITPRICE_KWH,
    r.STATUS                                                    AS ABYS_STATUS,
    eb.ENUM_STR_VALUE                                           AS ABYS_STATUS_VAL,
    r.INSTALLATION_ID                                           AS ABYS_INSTALLATION_ID,
    r.SUBSCRIBER_TYPE_ID                                        AS ABYS_SUBSCRIBER_TYPE_ID,
    r.ACTIVITY_TYPE_ID                                          AS ABYS_ACTIVITY_TYPE_ID,
    r.TARIFF_TYPE_ID                                            AS ABYS_TARIFF_TYPE_ID,
    r.PRE_METER_STATUS_ID                                       AS ABYS_PRE_METER_STATUS_ID,
    r.AVG_CONSUMPTION                                           AS ABYS_AVG_CONSUMPTION,
    r.ADD_CONSUMPTION                                           AS ABYS_ADD_CONSUMPTION,
    r.CONSUMPTION                                               AS ABYS_CONSUMPTION,
    r.CONSUMPTION_1                                             AS ABYS_CONSUMPTION_1,
    r.CONSUMPTION_2                                             AS ABYS_CONSUMPTION_2,
    r.CONSUMPTION_3                                             AS ABYS_CONSUMPTION_3,
    r.CONSUMPTION_4                                             AS ABYS_CONSUMPTION_4,
    r.CONSUMPTION_5                                             AS ABYS_CONSUMPTION_5,
    r.PRE_BILL_DATE                                             AS ABYS_PRE_BILL_DATE,
    r.TOTAL_DEBT                                                AS ABYS_TOTAL_DEBT,
    r.TOTAL_INSTALLMENT_DEBT                                    AS ABYS_TOTAL_INSTALLMENT_DEBT,
    r.TOTAL_CREDIT                                              AS ABYS_TOTAL_CREDIT,
    r.DEBT_BILL_COUNT                                           AS ABYS_DEBT_BILL_COUNT,
    r.NOTE                                                      AS ABYS_NOTE,
    r.TERMINAL_SYNC_CLIENT_ID                                   AS ABYS_TERMINAL_SYNC_CLIENT_ID,
    r.TERMINAL_UPLOAD_TIME                                      AS ABYS_TERMINAL_UPLOAD_TIME,
    r.WORKMAN_USER_ID                                           AS ABYS_WORKMAN_USER_ID,
    r.INSTALLATION_STATUS_ID                                    AS ABYS_INSTALLATION_STATUS_ID,
    r.ACCOUNT_ID                                                AS ABYS_ACCOUNT_ID,
    r.RECREATE_READING_ID                                       AS ABYS_RECREATE_READING_ID,
    r.READING_DAY                                               AS ABYS_READING_DAY,
    r.HAS_BARCODE                                               AS ABYS_HAS_BARCODE,
    r.IS_BARCODE_READING                                        AS ABYS_IS_BARCODE_READING,
    r.IS_FPS                                                    AS ABYS_IS_FPS,
    r.ERR_CODE                                                  AS ABYS_ERR_CODE,
    r.ERR_TEXT                                                  AS ABYS_ERR_TEXT,
    r.READING_METER_NUMBER                                      AS ABYS_READING_METER_NUMBER,
    r.READING_END_OF_DAY_ID                                     AS ABYS_READING_END_OF_DAY_ID,
    r.OPEN_CUT_FEE                                              AS ABYS_OPEN_CUT_FEE,
    r.SKB_TARIFF_TYPE_ID                                        AS ABYS_SKB_TARIFF_TYPE_ID,
    r.SKB_UNIT_PRICE                                            AS ABYS_SKB_UNIT_PRICE,
    r.BUILDING_FLAT_ID                                          AS ABYS_BUILDING_FLAT_ID,
    r.GAS_LEVEL_DAY_COUNT                                       AS ABYS_GAS_LEVEL_DAY_COUNT,
    r.GAS_LEVEL_DAY_LIMIT                                       AS ABYS_GAS_LEVEL_DAY_LIMIT,
    r.LAST_PICTURE_DATE                                         AS ABYS_LAST_PICTURE_DATE,
    r.DESERVED_DISCOUNT_M3                                      AS ABYS_DESERVED_DISCOUNT_M3,
    r.GAS_LEVEL1_WEIGHTED_AMOUNT                                AS ABYS_GAS_LEVEL1_AMOUNT,
    r.GAS_LEVEL2_WEIGHTED_AMOUNT                                AS ABYS_GAS_LEVEL2_AMOUNT,
    r.TOLERATED_M3                                              AS ABYS_TOLERATED_M3,
    r.TOTAL_DEBT_BEN_REGISTER                                   AS ABYS_DEBT_BEN_REGISTER,
    r.BILL_DESCRIPTION                                          AS ABYS_BILL_DESCRIPTION,
    r.REAL_COST                                                 AS ABYS_REAL_COST,
    r.CALCULATED_REAL_COST                                      AS ABYS_CALCULATED_REAL_COST,
    r.PREV_CONSUMPTION                                          AS ABYS_PREV_CONSUMPTION,
    r.TAX_DISCOUNT_AMOUNT                                       AS ABYS_TAX_DISCOUNT_AMOUNT,
    r.READING_PLAN_ID                                           AS ABYS_READING_PLAN_ID,
    r.POOL_DEBT                                                 AS ABYS_POOL_DEBT,
    r.POOL_DEBT_COUNT                                           AS ABYS_POOL_DEBT_COUNT,
    r.SUBSCRIBER_PARENT_ID                                      AS ABYS_SBS_PARENT_ID,
    r.ACTIVE_HOUSEHOLDS_COUNT                                   AS ABYS_HOUSEHOLDS_COUNT,
    r.READING_END_OF_DAY_ID                                     AS ABYS_READING_END_OF_DAY

FROM SMS.CS_READING r
JOIN SMS.CS_AGREEMENT        agr ON agr.ID = r.AGREEMENT_ID
JOIN SMS.CS_REGISTER         rr  ON rr.ID  = agr.BENEFITED_REGISTER_ID
JOIN SMS.CS_INSTALLATION     ins ON ins.ID = agr.INSTALLATION_ID
JOIN SMS.CS_SUBSCRIBER       sb  ON sb.ID  = ins.SUBSCRIBER_ID
JOIN SMS.GIS_BUILDING_FLAT   bf  ON bf.ID  = sb.BUILDING_FLAT_ID
JOIN SMS.GIS_BUILDING_DOOR   bd  ON bd.ID  = bf.BUILDING_DOOR_ID
LEFT JOIN SMS.CS_METER           m   ON m.ID = r.METER_ID
LEFT JOIN SMS.CS_ACCOUNT         acc ON acc.ID = r.ACCOUNT_ID
LEFT JOIN SMS.STG_RD_ACC_INC   av  ON av.ACCOUNT_ID = acc.ID
LEFT JOIN SMS.CS_READING_INDEX   ri1 ON ri1.READING_ID = r.ID
                                    AND ri1.INDEX_TYPE_ID = 1
LEFT JOIN SMS.IT_ENUM_BUNDLE     eb  ON eb.ENUM_NAME = 'ReadingInformationTransferStatus'
                                    AND eb.ENUM_NUMBER_VALUE = r.STATUS
                                    AND eb.LANG_ID = 1
LEFT JOIN SMS.STG_RD_READING_INC pv ON pv.READING_ID = r.ID
LEFT JOIN SMS.STG_RD_SYNC_USER   scu ON scu.SYNC_CLIENT_ID = r.TERMINAL_SYNC_CLIENT_ID
LEFT JOIN SMS.STG_RD_USER_COMP   uc  ON uc.USER_ID =
                                              NVL(r.WORKMAN_USER_ID, scu.USER_ID)

-- Pilot calisma icin acin:
 WHERE r.AGREEMENT_ID IN (5727, 197168)
;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('SMS','LS_READING', degree => 8); END;
/
