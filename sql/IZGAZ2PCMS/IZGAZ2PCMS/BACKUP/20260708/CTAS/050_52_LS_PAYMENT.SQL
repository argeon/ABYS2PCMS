-- =============================================================================
-- oracleCTAS3007 / 52 — LS_PAYMENT (makbuz grain — senaryo diag / wizard aynı grain)
-- Ortam : Oracle 11.2 | Schema: MIGRATION
-- Onkosul: O30 LS_OV_PAY_PT
--
-- Grain : PAY_LREF = CS_ACCOUNT_ACTION.ID (makbuz)
--         Mahsup (6/24) BU TABLODA DEGIL → LS_MAHSUP (O55)
-- Dogal ID: MAP/SRC_KEY YOK (bu aile)
-- Dump → izgazMGR.dbo.LS_PAYMENT
-- =============================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- TERMINAL DUMP: Oracle INDEX / GATHER_TABLE_STATS yok (CTAS zincirinde tuketilmiyor; IX -> izgazMGR/energy).

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM ALL_TABLES
   WHERE OWNER = 'MIGRATION' AND TABLE_NAME = 'LS_OV_PAY_PT';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20052, 'MIGRATION.LS_OV_PAY_PT yok — once O30.');
  END IF;
  BEGIN
    MIGRATION.P_MIG_CTAS_LOG('O52', 'ls_payment', 'START', NULL, 'makbuz grain PAY_LREF');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
/

BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_PAYMENT PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/

CREATE TABLE MIGRATION.LS_PAYMENT NOLOGGING PARALLEL 56 AS
SELECT /*+ PARALLEL(56) */
    CAST(p.ABYS_ID AS NUMBER(12))                                AS PAY_LREF,
    CAST(p.ABYS_ACCOUNT_ID AS NUMBER(12))                        AS FATURAID,
    CAST(p.ABYS_AGREEMENT_ID AS NUMBER(12))                      AS SOZLESME,
    CAST(p.ABYS_ACTION_TYPE_ID AS NUMBER(10))                    AS ACTION_TYPE_ID,
    CAST(p.PAY_FULL_AMT AS NUMBER(15,3))                         AS PAY_AMT,
    CAST(p.PAYABLETOTAL AS NUMBER(15,3))                         AS ALLOC_FIRST_AMT,
    CAST(p.CROSSREF_MAIN_LREF AS NUMBER(12))                     AS MAIN_LREF_FIRST,
    p.DATE_                                                      AS PAY_DATE,
    CAST(NVL(p.CANCELED, 0) AS NUMBER(1))                        AS CANCELED,
    CAST(act.BANK_ID AS NUMBER(12))                              AS BANKA_ID,
    CAST(act.CASH_ID AS NUMBER(12))                              AS VEZNE_ID,
    CAST(act.RECEIPT_NUMBER AS VARCHAR2(40))                     AS TAH_MAKBUZ_NO,
    CAST(SUBSTR(act.RECEIPT_SERIAL, 1, 40) AS VARCHAR2(40))      AS TAH_MAKBUZ_SERIAL,
    /* Pilot: ENERGY BANK_RECORD_REF — banka makbuz no (RECEIPT_NUMBER fallback) */
    CAST(SUBSTR(NVL(act.BANK_RECEIPT_NUMBER, TO_CHAR(act.RECEIPT_NUMBER)), 1, 80)
         AS VARCHAR2(80))                                        AS BANK_RECORD_REF,
    CAST(act.CREATED_USER_ID AS NUMBER(12))                      AS USERID,
    CAST(act.UPDATED_USER_ID AS NUMBER(12))                      AS UPDATED_USER_ID,
    CAST(SYSDATE AS DATE)                                        AS SNAPSHOT_DATE
FROM MIGRATION.LS_OV_PAY_PT p
JOIN SMS.CS_ACCOUNT_ACTION act
  ON act.ID = p.ABYS_ID
WHERE p.OV_KIND = 'PAY'
  AND NVL(p.ALLOC_RN, 1) = 1
  AND p.ABYS_ID IS NOT NULL;

ALTER TABLE MIGRATION.LS_PAYMENT NOPARALLEL LOGGING;


DECLARE
  n NUMBER; n_c NUMBER;
BEGIN
  SELECT COUNT(*), COUNT(CASE WHEN CANCELED = 1 THEN 1 END)
    INTO n, n_c FROM MIGRATION.LS_PAYMENT;
  MIGRATION.P_MIG_CTAS_LOG('O52', 'ls_payment', 'OK', n,
    'pay=' || n || ' canceled=' || n_c || ' dump→izgazMGR');
  DBMS_OUTPUT.PUT_LINE('========== O52 LS_PAYMENT OK | n=' || n || ' ==========');
END;
/
