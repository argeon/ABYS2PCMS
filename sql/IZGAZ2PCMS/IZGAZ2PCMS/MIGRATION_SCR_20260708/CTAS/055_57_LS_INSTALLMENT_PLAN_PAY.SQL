-- =============================================================================
-- oracleCTAS3007 / 57 — LS_INSTALLMENT_PLAN_PAY (taksit satır ödemeleri)
-- Onkosul: SMS.CS_INSTALLMENT_PLAN (+ optional CS_INSTALLMENT)
--
-- Pilot: ödenen taksit INST_NR için PAID + banka/makbuz/tarih kaynağı.
-- Grain : INSTALLMENT_ID + ORDER_NUMBER (= ENERGY PAYTRANS.INST_NR)
-- Dump → izgazMGR → Energy ApplyInstallmentTahsilat / 613 wire
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
   WHERE OWNER = 'SMS' AND TABLE_NAME = 'CS_INSTALLMENT_PLAN';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20057, 'SMS.CS_INSTALLMENT_PLAN yok.');
  END IF;
  BEGIN
    MIGRATION.P_MIG_CTAS_LOG('O57', 'ls_installment_plan_pay', 'START', NULL,
      'plan lines + PAYMENT_DATE + receipt/bank');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
/

BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_INSTALLMENT_PLAN_PAY PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/

CREATE TABLE MIGRATION.LS_INSTALLMENT_PLAN_PAY NOLOGGING PARALLEL 56 AS
SELECT /*+ PARALLEL(56) */
    CAST(ip.ID AS NUMBER(12))                                    AS PLAN_ROW_ID,
    CAST(ip.INSTALLMENT_ID AS NUMBER(12))                        AS INSTALLMENT_ID,
    CAST(ins.AGREEMENT_ID AS NUMBER(12))                         AS AGREEMENT_ID,
    CAST(ip.ORDER_NUMBER AS NUMBER(10))                          AS ORDER_NUMBER,
    CAST(ROUND(NVL(ip.AMOUNT, 0)
         + NVL(ip.LATE_CHARGE, 0)
         + NVL(ip.OVERDUE, 0), 2) AS NUMBER(15,3))               AS AMOUNT,
    ip.DUE_DATE                                                  AS DUE_DATE,
    ip.EXPIRY_DATE                                               AS EXPIRY_DATE,
    ip.PAYMENT_DATE                                              AS PAYMENT_DATE,
    CAST(CASE WHEN ip.PAYMENT_DATE IS NOT NULL THEN 1 ELSE 0 END
         AS NUMBER(1))                                           AS IS_PAID,
    CAST(ip.CASH_ID AS NUMBER(12))                               AS CASH_ID,
    CAST(SUBSTR(ip.RECEIPT_SERIAL, 1, 40) AS VARCHAR2(40))       AS RECEIPT_SERIAL,
    CAST(SUBSTR(TO_CHAR(ip.RECEIPT_NUMBER), 1, 40) AS VARCHAR2(40)) AS RECEIPT_NUMBER,
    /* CASH_ID SMS'te ödeme action ref olabilir → BANK_ID */
    CAST(act.BANK_ID AS NUMBER(12))                              AS BANKREF,
    CAST(SUBSTR(NVL(act.BANK_RECEIPT_NUMBER, TO_CHAR(ip.RECEIPT_NUMBER)), 1, 50)
         AS VARCHAR2(50))                                        AS BANK_RECORD_REF,
    CAST(NVL(act.ACTION_TYPE_ID, 3) AS NUMBER(10))               AS PAY_ACTION_TYPE_ID,
    CAST(174 AS NUMBER(10))                                      AS PAYTYPE,
    CAST(1 AS NUMBER(10))                                        AS XTYPE,
    CAST(acc.ID AS NUMBER(12))                                   AS ACCOUNT_ID,
    CAST(INV.LREF AS NUMBER(12))                                 AS MAIN_LREF,
    CAST(SYSDATE AS DATE)                                        AS SNAPSHOT_DATE
FROM SMS.CS_INSTALLMENT_PLAN ip
JOIN SMS.CS_INSTALLMENT ins ON ins.ID = ip.INSTALLMENT_ID
LEFT JOIN SMS.CS_ACCOUNT_ACTION act
  ON act.ID = ip.CASH_ID
LEFT JOIN SMS.CS_ACCOUNT acc
  ON acc.INSTALLMENT_ID = ip.INSTALLMENT_ID
 AND acc.AGREEMENT_ID = ins.AGREEMENT_ID
LEFT JOIN MIGRATION.LS_INVOICE INV
  ON INV.ABYS_ACCOUNT_ID = acc.ID
 AND INV.ABYS_ACTION_TYPE_ID = 1
 AND NVL(INV.CANCELED, 0) = 0
WHERE NVL(ip.ORDER_NUMBER, 0) > 0;

ALTER TABLE MIGRATION.LS_INSTALLMENT_PLAN_PAY NOPARALLEL LOGGING;


DECLARE
  n NUMBER; n_paid NUMBER;
BEGIN
  SELECT COUNT(*), COUNT(CASE WHEN IS_PAID = 1 THEN 1 END)
    INTO n, n_paid FROM MIGRATION.LS_INSTALLMENT_PLAN_PAY;
  MIGRATION.P_MIG_CTAS_LOG('O57', 'ls_installment_plan_pay', 'OK', n,
    'rows=' || n || ' paid=' || n_paid);
  DBMS_OUTPUT.PUT_LINE('========== O57 LS_INSTALLMENT_PLAN_PAY OK | n='
    || n || ' paid=' || n_paid || ' ==========');
END;
/
