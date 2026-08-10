-- =====================================================================
-- LS_BANK_ACC  (Oracle staging - CTAS)
-- Kaynak : SMS.IT_CASH  JOIN  SMS.IT_BANK_PRM  (bnk.ID = ic.BANK_ID)
-- Hedef  : MIGRATION.LS_BANK_ACC  →  izgazMGR.dbo.LS_BANK_ACC
--          → energy.dbo.LS_BANK_ACC  (125/126 REF_BANK_ACC)
-- Pattern: kaynak kolon isimleri birebir; ABYS_ID = ID bridge
-- Aciklama: Banka kasa / tahsilat hesabi (IT_CASH) staging
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- TERMINAL DUMP: Oracle INDEX / GATHER_TABLE_STATS yok (CTAS zincirinde tuketilmiyor; IX -> izgazMGR/energy).

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_BANK_ACC PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_BANK_ACC
NOLOGGING
PARALLEL 56
AS
SELECT /*+ FULL(ic) FULL(bnk) PARALLEL(ic 56) PARALLEL(bnk 56) */
    ic.ID                                                   AS ID,
    ic.ID                                                   AS ABYS_ID,
    ic.CORPORATION_ID                                       AS CORPORATION_ID,
    ic.CODE                                                 AS CODE,
    ic.CASH_NAME                                            AS CASH_NAME,
    ic.RECEIPT_SERIAL                                       AS RECEIPT_SERIAL,
    ic.RECEIPT_NUMBER                                       AS RECEIPT_NUMBER,
    ic.RECEIPT_TYPE                                         AS RECEIPT_TYPE,
    ic.ACCOUNT_CODE                                         AS ACCOUNT_CODE,
    ic.ACCOUNT_CODE_FINANCE                                 AS ACCOUNT_CODE_FINANCE,
    ic.BANK_ID                                              AS BANK_ID,
    ic.BANK_ACCOUNT_NUMBER                                  AS BANK_ACCOUNT_NUMBER,
    ic.OPENING_TIME                                         AS OPENING_TIME,
    ic.CLOSING_TIME                                         AS CLOSING_TIME,
    ic.BANK_INTEGRATION_CODE                                AS BANK_INTEGRATION_CODE,
    ic.RECONCILIATION_DATE                                  AS RECONCILIATION_DATE,
    ic.PAYMENT_RETURN_DAY                                   AS PAYMENT_RETURN_DAY,
    ic.IS_ONLINE_DISCHARGE                                  AS IS_ONLINE_DISCHARGE,
    ic.IS_ACTIVE                                            AS IS_ACTIVE,
    ic.CREATED_USER_ID                                      AS CREATED_USER_ID,
    CAST(ic.CREATED_TIMESTAMP AS TIMESTAMP)                 AS CREATED_TIMESTAMP,
    ic.UPDATED_USER_ID                                      AS UPDATED_USER_ID,
    CAST(ic.UPDATED_TIMESTAMP AS TIMESTAMP)                 AS UPDATED_TIMESTAMP,
    ic.VERSION                                              AS VERSION,
    ic.CASH_TYPE_ID                                         AS CASH_TYPE_ID,
    ic.WORK_PLACE_ID                                        AS WORK_PLACE_ID,
    ic.ACCOUNT_CODE_CREDIT                                  AS ACCOUNT_CODE_CREDIT
FROM SMS.IT_CASH ic
INNER JOIN SMS.IT_BANK_PRM bnk
    ON bnk.ID = ic.BANK_ID
;

ALTER TABLE MIGRATION.LS_BANK_ACC NOPARALLEL LOGGING;


-- dogrulama
SELECT 'IT_CASH_JOIN_BANK' KAYNAK, COUNT(*) CNT
FROM SMS.IT_CASH ic
INNER JOIN SMS.IT_BANK_PRM bnk ON bnk.ID = ic.BANK_ID
UNION ALL
SELECT 'LS_BANK_ACC', COUNT(*)
FROM MIGRATION.LS_BANK_ACC
UNION ALL
SELECT 'LS_BANK_ACC_ACTIVE', COUNT(*)
FROM MIGRATION.LS_BANK_ACC WHERE IS_ACTIVE = 1
UNION ALL
SELECT 'LS_BANK_ACC_HAS_INTEG', COUNT(*)
FROM MIGRATION.LS_BANK_ACC WHERE BANK_INTEGRATION_CODE IS NOT NULL
UNION ALL
SELECT 'LS_BANK_ACC_BANK_ID_NULL', COUNT(*)
FROM MIGRATION.LS_BANK_ACC WHERE BANK_ID IS NULL;

PROMPT ========== LS_BANK_ACC OK ==========
/
