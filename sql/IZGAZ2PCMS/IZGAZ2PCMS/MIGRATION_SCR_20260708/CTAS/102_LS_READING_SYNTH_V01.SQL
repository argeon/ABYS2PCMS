-- 102_LS_READING_SYNTH_V01.SQL
-- Amac: Sentetik okuma gap
-- Uretir: LS_READING
-- Gate: yok
-- Sonraki: 103_LS_HHD_MSTR_V01.SQL
-- =============================================================================
-- oracleCTAS3007 / LS_READING_SYNTH
-- Onkosul: LS_READING.sql, 09_mig_accrue_type_map.sql
-- NEEDS_READING=1 hesaplarda organik okuma yoksa sentetik TRAN ekler.
-- LREF = GREATEST(MAX(organik), 1500000000) + RN  (INT-safe)
-- Personel = fatura creator (CREATED_USER_ID), okuyucu değil.
-- Gelirler = CS_ACCOUNT_INCOME (organik STG_RD_READING_INC + STG_RD_ACC_INC hizasi)
--   birim: 939 gaz / 7658 SKB UNIT_PRICE
--   tutar pivot: 939/7658/1929/958/1864/1905/1861/100/1902/SPEC/162 + vergi
-- SMS.CS_READING'e yazilmaz.
-- Sonraki: LS_HHD_MSTR.sql
-- =============================================================================
WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM ALL_TABLES
   WHERE OWNER = 'MIGRATION' AND TABLE_NAME = 'LS_READING';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20041, 'LS_READING yok — once LS_READING.sql');
  END IF;
  SELECT COUNT(*) INTO n FROM ALL_TABLES
   WHERE OWNER = 'MIGRATION' AND TABLE_NAME = 'MIG_ACCRUE_TYPE_MAP';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20042, 'MIG_ACCRUE_TYPE_MAP yok — once 09_mig_accrue_type_map.sql');
  END IF;
  SELECT COUNT(*) INTO n FROM ALL_TAB_COLUMNS
   WHERE OWNER = 'MIGRATION' AND TABLE_NAME = 'LS_READING'
     AND COLUMN_NAME = 'ABYS_ACCRUE_TYPE_ID';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20043, 'LS_READING.ABYS_ACCRUE_TYPE_ID yok — LS_READING.sql guncelle');
  END IF;
END;
/

-- Idempotent: onceki sentetikleri temizle (yeniden kosu)
DELETE FROM MIGRATION.LS_READING
 WHERE ABYS_NOTE LIKE 'MIG_SYNTH%'
    OR LREF >= 1500000000;
COMMIT;

PROMPT ========== SYNTH GAP CANDIDATES ==========

BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.STG_RD_SYNTH_GAP PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/

CREATE TABLE MIGRATION.STG_RD_SYNTH_GAP NOLOGGING PARALLEL 56 AS
SELECT /*+ PARALLEL(56) */
    acc.ID                                                    AS ACCOUNT_ID,
    acc.AGREEMENT_ID,
    acc.REGISTER_ID,
    acc.INSTALLATION_ID,
    acc.METER_ID,
    acc.ACCRUE_TYPE_ID,
    map.ABYS_NAME,
    map.EXPLAIN_PREFIX,
    aa.ID                                                     AS ACTION_ID,
    aa.ACTION_DATE,
    aa.CREATED_TIMESTAMP,
    aa.CREATED_USER_ID,
    aa.M3,
    aa.CONSUMPTION,
    aa.KWH,
    NVL(acc.READING_DATE, aa.ACTION_DATE)                        AS READ_DATE,
    iu.USER_NAME                                              AS CREATOR_NAME,
    /* bina / abone — organik LS_READING JOIN hizasi (BINA_ID NOT NULL) */
    NVL(bd.ID, 0)                                             AS BINA_ID,
    NVL(rr.ID, 0)                                             AS CUST_ID,
    SUBSTR(TRIM(NVL(rr.FIRST_NAME, '') || ' ' || NVL(rr.LAST_NAME, '')), 1, 100) AS CUST_NAME,
    NVL(acc.SUBSCRIBER_TYPE_ID, 0)                            AS SUBSCRIBER_TYPE_ID,
    NVL(acc.TARIFF_TYPE_ID, 0)                                AS TARIFF_TYPE_ID,
    NVL(acc.PERIOD, 0)                                        AS PERIOD,
    NVL(bf.ID, 0)                                             AS BUILDING_FLAT_ID,
    /* birim fiyat (indirimsiz) */
    ai.GAS_UNIT_PRICE,
    ai.SKB_UNIT_PRICE,
    /* tutar pivot — STG_RD_READING_INC hizasi */
    ai.GAS_TOTAL_AMOUNT,
    ai.SKB_TOTAL_AMOUNT,
    ai.ROUND_AMT,
    ai.TURNOVER_AMT,
    ai.DEFAULT_FINE,
    ai.DEFAULT_FINE_TAX,
    ai.GAS_OPEN_FEE,
    ai.GAS_OPEN_FEE_REF,
    ai.DISCOUNT_ADDITION,
    ai.DISCOUNT_ADDITION_REF,
    ai.ILLEGAL_USE_FEE,
    ai.ILLEGAL_USE_FEE_REF,
    ai.SPEC_SERV_FEE,
    ai.SPEC_SERV_FEE_INCOME_IDS,
    ai.UNMAPPED_GUVENCE_BEDELI,
    /* STG_RD_ACC_INC hizasi */
    ai.EXPEND_FEE,
    ai.TOTAL_EXCL_TAX,
    ai.TOTAL_TAX,
    ai.PAYABLE_TOTAL
FROM SMS.CS_ACCOUNT acc
JOIN MIGRATION.MIG_ACCRUE_TYPE_MAP map
  ON map.ABYS_ACCRUE_TYPE_ID = acc.ACCRUE_TYPE_ID
 AND map.NEEDS_READING = 1
JOIN SMS.CS_ACCOUNT_ACTION aa
  ON aa.ACCOUNT_ID = acc.ID
 AND aa.ACTION_TYPE_ID IN (1, 3, 10, 41)
 AND aa.ID = (
      SELECT MAX(aa2.ID)
        FROM SMS.CS_ACCOUNT_ACTION aa2
       WHERE aa2.ACCOUNT_ID = acc.ID
         AND aa2.ACTION_TYPE_ID IN (1, 3, 10, 41)
 )
LEFT JOIN (
    SELECT /*+ PARALLEL(56) */
           ACCOUNT_ACTION_ID,
           MAX(CASE WHEN NVL(IS_DISCOUNT, 0) = 0 AND INCOME_ID = 939
                    THEN UNIT_PRICE END)                         AS GAS_UNIT_PRICE,
           MAX(CASE WHEN NVL(IS_DISCOUNT, 0) = 0 AND INCOME_ID = 7658
                    THEN UNIT_PRICE END)                         AS SKB_UNIT_PRICE,

           SUM(CASE WHEN INCOME_ID = 939  THEN AMOUNT END)       AS GAS_TOTAL_AMOUNT,
           SUM(CASE WHEN INCOME_ID = 7658 THEN AMOUNT END)       AS SKB_TOTAL_AMOUNT,
           SUM(CASE WHEN INCOME_ID = 1929 THEN AMOUNT END)       AS ROUND_AMT,
           SUM(CASE WHEN INCOME_ID = 958  THEN AMOUNT END)       AS TURNOVER_AMT,
           SUM(CASE WHEN INCOME_ID = 1864 THEN AMOUNT END)       AS DEFAULT_FINE,
           SUM(CASE WHEN INCOME_ID = 1905 THEN AMOUNT END)       AS DEFAULT_FINE_TAX,

           SUM(CASE WHEN INCOME_ID = 1861 THEN AMOUNT END)       AS GAS_OPEN_FEE,
           MAX(CASE WHEN INCOME_ID = 1861 THEN ID END)           AS GAS_OPEN_FEE_REF,

           SUM(CASE WHEN INCOME_ID = 100  THEN AMOUNT END)       AS DISCOUNT_ADDITION,
           MAX(CASE WHEN INCOME_ID = 100  THEN ID END)           AS DISCOUNT_ADDITION_REF,

           SUM(CASE WHEN INCOME_ID = 1902 THEN AMOUNT END)       AS ILLEGAL_USE_FEE,
           MAX(CASE WHEN INCOME_ID = 1902 THEN ID END)           AS ILLEGAL_USE_FEE_REF,

           SUM(CASE WHEN INCOME_ID IN
                    (2981, 572, 938, 23033, 573, 23034, 23031, 23032, 2982,
                     576, 574, 3251, 12531, 579, 47, 578, 581, 575, 7709,
                     577, 7504, 2521, 7528, 7464, 2847, 2446, 2649, 2520,
                     7408, 2591, 7496, 2583, 3067)
                THEN AMOUNT END)                                 AS SPEC_SERV_FEE,
           LISTAGG(
             CASE WHEN INCOME_ID IN
                    (2981, 572, 938, 23033, 573, 23034, 23031, 23032, 2982,
                     576, 574, 3251, 12531, 579, 47, 578, 581, 575, 7709,
                     577, 7504, 2521, 7528, 7464, 2847, 2446, 2649, 2520,
                     7408, 2591, 7496, 2583, 3067)
                  THEN TO_CHAR(INCOME_ID) END,
             ','
           ) WITHIN GROUP (ORDER BY INCOME_ID)                   AS SPEC_SERV_FEE_INCOME_IDS,

           SUM(CASE WHEN INCOME_ID = 162 THEN AMOUNT END)        AS UNMAPPED_GUVENCE_BEDELI,

           SUM(CASE WHEN INCOME_ID IN (939, 7658) THEN AMOUNT END) AS EXPEND_FEE,
           SUM(CASE WHEN INCOME_ID NOT IN (169, 60) THEN AMOUNT END) AS TOTAL_EXCL_TAX,
           SUM(CASE WHEN INCOME_ID IN (169, 60) THEN AMOUNT END) AS TOTAL_TAX,
           SUM(AMOUNT)                                           AS PAYABLE_TOTAL
      FROM SMS.CS_ACCOUNT_INCOME
     GROUP BY ACCOUNT_ACTION_ID
) ai ON ai.ACCOUNT_ACTION_ID = aa.ID
LEFT JOIN SMS.IT_USER iu ON iu.ID = aa.CREATED_USER_ID
LEFT JOIN SMS.CS_AGREEMENT agr
  ON agr.ID = acc.AGREEMENT_ID
LEFT JOIN SMS.CS_REGISTER rr
  ON rr.ID = agr.BENEFITED_REGISTER_ID
LEFT JOIN SMS.CS_INSTALLATION ins
  ON ins.ID = NVL(acc.INSTALLATION_ID, agr.INSTALLATION_ID)
LEFT JOIN SMS.CS_SUBSCRIBER sb
  ON sb.ID = ins.SUBSCRIBER_ID
LEFT JOIN SMS.GIS_BUILDING_FLAT bf
  ON bf.ID = sb.BUILDING_FLAT_ID
LEFT JOIN SMS.GIS_BUILDING_DOOR bd
  ON bd.ID = bf.BUILDING_DOOR_ID
WHERE NVL(acc.ACCRUE_TYPE_ID, -1) <> 14
  AND NOT EXISTS (
        SELECT 1 FROM MIGRATION.LS_READING r
         WHERE r.ABYS_ACCOUNT_ID = acc.ID
           AND NVL(r.ABYS_NOTE, 'x') NOT LIKE 'MIG_SYNTH%'
      )
  AND NOT EXISTS (
        SELECT 1 FROM SMS.CS_READING cr
         WHERE cr.ACCOUNT_ID = acc.ID
      );

CREATE INDEX MIGRATION.IX_STG_RD_SYNTH_GAP ON MIGRATION.STG_RD_SYNTH_GAP (ACCOUNT_ID)
  PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_STG_RD_SYNTH_GAP NOPARALLEL;
BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'STG_RD_SYNTH_GAP', degree => 40); END;
/

SELECT COUNT(*) AS SYNTH_GAP_CNT FROM MIGRATION.STG_RD_SYNTH_GAP;

PROMPT ========== INSERT SYNTH INTO LS_READING ==========

INSERT /*+ APPEND PARALLEL(56) */ INTO MIGRATION.LS_READING (
    LREF,
    READ_NO,
    LOC_REGION,
    READ_DATE,
    LOC_ID,
    BINA_ID,
    SEQ_NO,
    READER_COMP,
    READER_PRSNL,
    READER_PRSNL_ID,
    INV_ID,
    INV_REF,
    INV_DATE,
    INV_FIRST_DATE,
    INV_LAST_DATE,
    FIRST_READ_DATE,
    LAST_READ_DATE,
    CNT_ID,
    CNT_SERIAL,
    CUST_ID,
    CUST_SUFFIX,
    CUST_NAME,
    FIRST_READ_IND,
    LAST_READ_IND,
    EXPEND_QUANTITY,
    CORR_COEF,
    CORR_VOLUME,
    ACTUAL_TOP_CAL_VALUE,
    AVG_TOP_CAL_VALUE,
    EXPEND_ENERGY,
    RETAIL_PRICE2,
    RETAIL_PRICE3,
    GAS_UNITPRICE_KWH,
    SKB_UNITPRICE_KWH,
    DEFAULT_FINE,
    DEFAULT_FINE_TAX,
    GAS_OPEN_FEE,
    DETACH_ATTACH_FEE,
    TEST_FEE,
    SPEC_SERV_FEE,
    ILLEGAL_USE_FEE,
    FIXED_FEE,
    FIXED_FEE_TAX,
    EXPEND_FEE,
    EXPEND_FEE_TAX,
    DISCOUNT_ADDITION,
    TOTAL,
    TOTAL_TAX,
    PAYABLE_TOTAL,
    KDV,
    OTV,
    BHAB,
    FATSBT,
    DISCOUNT_RATE,
    INTEREST_RATE,
    MIN_TOTAL,
    MIN_EXPEND,
    MAX_EXPEND,
    REC_STATUS,
    READ_STATUS,
    READ_COUNT,
    CUST_TYPE,
    ADDUSER,
    ADDDATE,
    GAS_OPEN_FEE_REF,
    DETACH_ATTACH_FEE_REF,
    TEST_FEE_REF,
    SPEC_SERV_FEE_REF,
    DISCOUNT_ADDITION_REF,
    ILLEGAL_USE_FEE_REF,
    AGRID,
    INV_INSTALLMENT_TOTAL,
    INV_INSTALLMENT_REF,
    REAL_DATE,
    UNDERLIMIT,
    UNDERLIMITSTAT,
    CANCELLED,
    GAS_TOTAL_AMOUNT,
    SKB_TOTAL_AMOUNT,
    ROUND_AMT,
    TURNOVER_AMT,
    STG_SPEC_SERV_FEE_SOURCE_IDS,
    STG_UNMAPPED_GUVENCE_BEDELI,
    ABYS_ACCOUNT_ID,
    ABYS_ACCRUE_TYPE_ID,
    ABYS_NOTE,
    ABYS_SM3,
    ABYS_CORRECTED_SM3,
    ABYS_CONSUMPTION,
    ABYS_INSTALLATION_ID,
    ABYS_READING_END_OF_DAY_ID,
    ABYS_READING_END_OF_DAY,
    ABYS_SKB_UNIT_PRICE,
    ABYS_STATUS,
    ABYS_SUBSCRIBER_TYPE_ID,
    ABYS_ACTIVITY_TYPE_ID,
    ABYS_TARIFF_TYPE_ID,
    ABYS_PRE_METER_STATUS_ID,
    ABYS_TOTAL_DEBT,
    ABYS_TOTAL_INSTALLMENT_DEBT,
    ABYS_TOTAL_CREDIT,
    ABYS_DEBT_BILL_COUNT,
    ABYS_OPEN_CUT_FEE,
    ABYS_REAL_COST,
    ABYS_CALCULATED_REAL_COST,
    ABYS_PREV_CONSUMPTION,
    ABYS_TAX_DISCOUNT_AMOUNT,
    ABYS_POOL_DEBT,
    ABYS_POOL_DEBT_COUNT,
    ABYS_AVG_CONSUMPTION,
    ABYS_ADD_CONSUMPTION,
    ABYS_CONSUMPTION_1,
    ABYS_CONSUMPTION_2,
    ABYS_CONSUMPTION_3,
    ABYS_CONSUMPTION_4,
    ABYS_CONSUMPTION_5,
    ABYS_READING_DAY,
    ABYS_HAS_BARCODE,
    ABYS_IS_BARCODE_READING,
    ABYS_IS_FPS,
    ABYS_INSTALLATION_STATUS_ID,
    ABYS_SKB_TARIFF_TYPE_ID,
    ABYS_BUILDING_FLAT_ID,
    ABYS_GAS_LEVEL_DAY_COUNT,
    ABYS_GAS_LEVEL_DAY_LIMIT,
    ABYS_DESERVED_DISCOUNT_M3,
    ABYS_GAS_LEVEL1_AMOUNT,
    ABYS_GAS_LEVEL2_AMOUNT,
    ABYS_TOLERATED_M3,
    ABYS_DEBT_BEN_REGISTER,
    ABYS_SBS_PARENT_ID,
    ABYS_HOUSEHOLDS_COUNT,
    ABYS_TERMINAL_SYNC_CLIENT_ID,
    ABYS_WORKMAN_USER_ID,
    ABYS_RECREATE_READING_ID,
    ABYS_READING_PLAN_ID,
    CNT_STATUS,
    PERIOD
)
SELECT /*+ PARALLEL(56) */
    GREATEST(
      NVL((SELECT MAX(LREF) FROM MIGRATION.LS_READING WHERE LREF < 1500000000), 0),
      1500000000
    ) + ROW_NUMBER() OVER (ORDER BY g.ACCOUNT_ID)                 AS LREF,
    CAST(0 AS NUMBER(10,0))                                       AS READ_NO,
    4102                                                          AS LOC_REGION,
    CASE
      WHEN g.READ_DATE IS NULL THEN SYSDATE
      WHEN EXTRACT(YEAR FROM g.READ_DATE) < 1753
        THEN ADD_MONTHS(g.READ_DATE, 24000)
      ELSE g.READ_DATE
    END                                                           AS READ_DATE,
    CAST(g.INSTALLATION_ID AS VARCHAR2(15))                       AS LOC_ID,
    NVL(g.BINA_ID, 0)                                             AS BINA_ID,
    CAST(0 AS NUMBER)                                             AS SEQ_NO,
    CAST(0 AS NUMBER)                                             AS READER_COMP,
    SUBSTR(NVL(g.CREATOR_NAME, 'MIG_SYNTH'), 1, 50)               AS READER_PRSNL,
    CASE WHEN g.CREATED_USER_ID IS NULL THEN 10000
         ELSE 10000 + g.CREATED_USER_ID END                       AS READER_PRSNL_ID,
    CAST(NULL AS VARCHAR2(50))                                    AS INV_ID,
    NVL(g.ACCOUNT_ID, 0)                                          AS INV_REF,
    NVL(g.READ_DATE, SYSDATE)                                     AS INV_DATE,
    NVL(g.READ_DATE, SYSDATE)                                     AS INV_FIRST_DATE,
    NVL(g.READ_DATE, SYSDATE)                                     AS INV_LAST_DATE,
    NVL(g.READ_DATE, SYSDATE)                                     AS FIRST_READ_DATE,
    NVL(g.READ_DATE, SYSDATE)                                     AS LAST_READ_DATE,
    NVL(g.METER_ID, 0)                                            AS CNT_ID,
    CAST(NULL AS VARCHAR2(50))                                    AS CNT_SERIAL,
    NVL(g.CUST_ID, 0)                                             AS CUST_ID,
    90                                                            AS CUST_SUFFIX,
    NVL(NULLIF(TRIM(g.CUST_NAME), ''), 'MIG_SYNTH')              AS CUST_NAME,
    CAST(0 AS NUMBER)                                             AS FIRST_READ_IND,
    CAST(0 AS NUMBER)                                             AS LAST_READ_IND,
    CAST(NVL(NVL(g.CONSUMPTION, g.M3), 0) AS NUMBER(15,2))        AS EXPEND_QUANTITY,
    CAST(1 AS NUMBER)                                             AS CORR_COEF,
    CAST(NVL(NVL(g.M3, g.CONSUMPTION), 0) AS NUMBER(15,2))        AS CORR_VOLUME,
    9155                                                          AS ACTUAL_TOP_CAL_VALUE,
    CAST(0 AS NUMBER)                                             AS AVG_TOP_CAL_VALUE,
    CAST(NVL(g.KWH, 0) AS NUMBER)                                 AS EXPEND_ENERGY,
    CAST(ROUND((NVL(g.GAS_UNIT_PRICE, 0) + NVL(g.SKB_UNIT_PRICE, 0)) * 10.64, 8)
         AS NUMBER(15,6))                                         AS RETAIL_PRICE2,
    CAST((NVL(g.GAS_UNIT_PRICE, 0) + NVL(g.SKB_UNIT_PRICE, 0))
         AS NUMBER(15,8))                                         AS RETAIL_PRICE3,
    CAST(NVL(g.GAS_UNIT_PRICE, 0) AS NUMBER)                      AS GAS_UNITPRICE_KWH,
    CAST(NVL(g.SKB_UNIT_PRICE, 0) AS NUMBER)                      AS SKB_UNITPRICE_KWH,
    CAST(NVL(g.DEFAULT_FINE, 0) AS NUMBER(15,2))                  AS DEFAULT_FINE,
    CAST(NVL(g.DEFAULT_FINE_TAX, 0) AS NUMBER(15,2))              AS DEFAULT_FINE_TAX,
    CAST(NVL(g.GAS_OPEN_FEE, 0) AS NUMBER(15,2))                  AS GAS_OPEN_FEE,
    0                                                             AS DETACH_ATTACH_FEE,
    0                                                             AS TEST_FEE,
    CAST(NVL(g.SPEC_SERV_FEE, 0) AS NUMBER(15,2))                 AS SPEC_SERV_FEE,
    CAST(NVL(g.ILLEGAL_USE_FEE, 0) AS NUMBER(15,2))               AS ILLEGAL_USE_FEE,
    0                                                             AS FIXED_FEE,
    0                                                             AS FIXED_FEE_TAX,
    CAST(NVL(g.EXPEND_FEE, 0) AS NUMBER(15,2))                    AS EXPEND_FEE,
    CAST(ROUND(NVL(g.EXPEND_FEE, 0) *
         CASE WHEN NVL(g.READ_DATE, DATE '2099-01-01') < DATE '2023-07-10'
              THEN 0.18 ELSE 0.20 END, 2) AS NUMBER(15,2))        AS EXPEND_FEE_TAX,
    CAST(NVL(g.DISCOUNT_ADDITION, 0) AS NUMBER(15,2))             AS DISCOUNT_ADDITION,
    CAST(NVL(g.TOTAL_EXCL_TAX, 0) AS NUMBER(15,2))                AS TOTAL,
    CAST(NVL(g.TOTAL_TAX, 0) AS NUMBER(15,2))                     AS TOTAL_TAX,
    CAST(NVL(g.PAYABLE_TOTAL, 0) AS NUMBER(15,2))                 AS PAYABLE_TOTAL,
    CASE WHEN NVL(g.READ_DATE, DATE '2099-01-01') < DATE '2023-07-10'
         THEN 18 ELSE 20 END                                      AS KDV,
    CAST(0 AS NUMBER)                                             AS OTV,
    0                                                             AS BHAB,
    0                                                             AS FATSBT,
    0                                                             AS DISCOUNT_RATE,
    0                                                             AS INTEREST_RATE,
    0                                                             AS MIN_TOTAL,
    0                                                             AS MIN_EXPEND,
    0                                                             AS MAX_EXPEND,
    4                                                             AS REC_STATUS,
    10                                                            AS READ_STATUS,
    1                                                             AS READ_COUNT,
    91                                                            AS CUST_TYPE,
    CASE WHEN g.CREATED_USER_ID IS NULL THEN 0
         ELSE g.CREATED_USER_ID + 10000 END                       AS ADDUSER,
    NVL(g.CREATED_TIMESTAMP, SYSDATE)                             AS ADDDATE,
    NVL(g.GAS_OPEN_FEE_REF, 0)                                    AS GAS_OPEN_FEE_REF,
    CAST(0 AS NUMBER(10,0))                                       AS DETACH_ATTACH_FEE_REF,
    CAST(0 AS NUMBER(10,0))                                       AS TEST_FEE_REF,
    CAST(0 AS NUMBER(10,0))                                       AS SPEC_SERV_FEE_REF,
    NVL(g.DISCOUNT_ADDITION_REF, 0)                               AS DISCOUNT_ADDITION_REF,
    NVL(g.ILLEGAL_USE_FEE_REF, 0)                                 AS ILLEGAL_USE_FEE_REF,
    NVL(g.AGREEMENT_ID, 0)                                        AS AGRID,
    CAST(0 AS NUMBER)                                             AS INV_INSTALLMENT_TOTAL,
    0                                                             AS INV_INSTALLMENT_REF,
    NVL(g.READ_DATE, SYSDATE)                                     AS REAL_DATE,
    CAST(0 AS NUMBER)                                             AS UNDERLIMIT,
    CAST(0 AS NUMBER(10,0))                                       AS UNDERLIMITSTAT,
    0                                                             AS CANCELLED,
    CAST(NVL(g.GAS_TOTAL_AMOUNT, 0) AS NUMBER(15,2))              AS GAS_TOTAL_AMOUNT,
    CAST(NVL(g.SKB_TOTAL_AMOUNT, 0) AS NUMBER(15,2))              AS SKB_TOTAL_AMOUNT,
    CAST(NVL(g.ROUND_AMT, 0) AS NUMBER(15,2))                     AS ROUND_AMT,
    CAST(NVL(g.TURNOVER_AMT, 0) AS NUMBER(15,2))                  AS TURNOVER_AMT,
    g.SPEC_SERV_FEE_INCOME_IDS                                    AS STG_SPEC_SERV_FEE_SOURCE_IDS,
    CAST(NVL(g.UNMAPPED_GUVENCE_BEDELI, 0) AS NUMBER)             AS STG_UNMAPPED_GUVENCE_BEDELI,
    NVL(g.ACCOUNT_ID, 0)                                          AS ABYS_ACCOUNT_ID,
    NVL(g.ACCRUE_TYPE_ID, 0)                                      AS ABYS_ACCRUE_TYPE_ID,
    'MIG_SYNTH ACCRUE=' || TO_CHAR(g.ACCRUE_TYPE_ID)
      || ' ' || NVL(g.EXPLAIN_PREFIX, g.ABYS_NAME)                AS ABYS_NOTE,
    CAST(NVL(NVL(g.M3, g.CONSUMPTION), 0) AS NUMBER)              AS ABYS_SM3,
    CAST(NVL(NVL(g.M3, g.CONSUMPTION), 0) AS NUMBER)              AS ABYS_CORRECTED_SM3,
    CAST(NVL(NVL(g.CONSUMPTION, g.M3), 0) AS NUMBER)              AS ABYS_CONSUMPTION,
    NVL(g.INSTALLATION_ID, 0)                                     AS ABYS_INSTALLATION_ID,
    CAST(0 AS NUMBER)                                             AS ABYS_READING_END_OF_DAY_ID,
    CAST(0 AS NUMBER)                                             AS ABYS_READING_END_OF_DAY,
    CAST(NVL(g.SKB_UNIT_PRICE, 0) AS NUMBER)                      AS ABYS_SKB_UNIT_PRICE,
    CAST(0 AS NUMBER)                                             AS ABYS_STATUS,
    NVL(g.SUBSCRIBER_TYPE_ID, 0)                                  AS ABYS_SUBSCRIBER_TYPE_ID,
    CAST(0 AS NUMBER)                                             AS ABYS_ACTIVITY_TYPE_ID,
    NVL(g.TARIFF_TYPE_ID, 0)                                      AS ABYS_TARIFF_TYPE_ID,
    CAST(0 AS NUMBER)                                             AS ABYS_PRE_METER_STATUS_ID,
    CAST(0 AS NUMBER)                                             AS ABYS_TOTAL_DEBT,
    CAST(0 AS NUMBER)                                             AS ABYS_TOTAL_INSTALLMENT_DEBT,
    CAST(0 AS NUMBER)                                             AS ABYS_TOTAL_CREDIT,
    CAST(0 AS NUMBER)                                             AS ABYS_DEBT_BILL_COUNT,
    CAST(0 AS NUMBER)                                             AS ABYS_OPEN_CUT_FEE,
    CAST(0 AS NUMBER)                                             AS ABYS_REAL_COST,
    CAST(0 AS NUMBER)                                             AS ABYS_CALCULATED_REAL_COST,
    CAST(0 AS NUMBER)                                             AS ABYS_PREV_CONSUMPTION,
    CAST(0 AS NUMBER)                                             AS ABYS_TAX_DISCOUNT_AMOUNT,
    CAST(0 AS NUMBER)                                             AS ABYS_POOL_DEBT,
    CAST(0 AS NUMBER)                                             AS ABYS_POOL_DEBT_COUNT,
    CAST(0 AS NUMBER)                                             AS ABYS_AVG_CONSUMPTION,
    CAST(0 AS NUMBER)                                             AS ABYS_ADD_CONSUMPTION,
    CAST(0 AS NUMBER)                                             AS ABYS_CONSUMPTION_1,
    CAST(0 AS NUMBER)                                             AS ABYS_CONSUMPTION_2,
    CAST(0 AS NUMBER)                                             AS ABYS_CONSUMPTION_3,
    CAST(0 AS NUMBER)                                             AS ABYS_CONSUMPTION_4,
    CAST(0 AS NUMBER)                                             AS ABYS_CONSUMPTION_5,
    CAST(0 AS NUMBER)                                             AS ABYS_READING_DAY,
    CAST(0 AS NUMBER)                                             AS ABYS_HAS_BARCODE,
    CAST(0 AS NUMBER)                                             AS ABYS_IS_BARCODE_READING,
    CAST(0 AS NUMBER)                                             AS ABYS_IS_FPS,
    CAST(0 AS NUMBER)                                             AS ABYS_INSTALLATION_STATUS_ID,
    CAST(0 AS NUMBER)                                             AS ABYS_SKB_TARIFF_TYPE_ID,
    NVL(g.BUILDING_FLAT_ID, 0)                                    AS ABYS_BUILDING_FLAT_ID,
    CAST(0 AS NUMBER)                                             AS ABYS_GAS_LEVEL_DAY_COUNT,
    CAST(0 AS NUMBER)                                             AS ABYS_GAS_LEVEL_DAY_LIMIT,
    CAST(0 AS NUMBER)                                             AS ABYS_DESERVED_DISCOUNT_M3,
    CAST(0 AS NUMBER)                                             AS ABYS_GAS_LEVEL1_AMOUNT,
    CAST(0 AS NUMBER)                                             AS ABYS_GAS_LEVEL2_AMOUNT,
    CAST(0 AS NUMBER)                                             AS ABYS_TOLERATED_M3,
    CAST(0 AS NUMBER)                                             AS ABYS_DEBT_BEN_REGISTER,
    CAST(0 AS NUMBER)                                             AS ABYS_SBS_PARENT_ID,
    CAST(0 AS NUMBER)                                             AS ABYS_HOUSEHOLDS_COUNT,
    CAST(0 AS NUMBER)                                             AS ABYS_TERMINAL_SYNC_CLIENT_ID,
    CAST(0 AS NUMBER)                                             AS ABYS_WORKMAN_USER_ID,
    CAST(0 AS NUMBER)                                             AS ABYS_RECREATE_READING_ID,
    CAST(0 AS NUMBER)                                             AS ABYS_READING_PLAN_ID,
    CAST(0 AS NUMBER)                                             AS CNT_STATUS,
    NVL(g.PERIOD, 0)                                              AS PERIOD
FROM MIGRATION.STG_RD_SYNTH_GAP g;

COMMIT;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_READING', degree => 40); END;
/

-- STG_DROP gap
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.STG_RD_SYNTH_GAP PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/

SELECT
  (SELECT COUNT(*) FROM MIGRATION.LS_READING WHERE ABYS_NOTE LIKE 'MIG_SYNTH%') AS SYNTH_N,
  (SELECT COUNT(*) FROM MIGRATION.LS_READING) AS ALL_N
FROM DUAL;

PROMPT ========== LS_READING_SYNTH OK ==========
/

