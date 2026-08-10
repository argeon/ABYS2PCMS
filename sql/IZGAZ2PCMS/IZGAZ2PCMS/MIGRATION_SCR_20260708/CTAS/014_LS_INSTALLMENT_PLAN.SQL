-- =====================================================================
-- LS_INSTALLMENT_PLAN  (Oracle staging - CTAS)
-- Kaynak : SMS.CS_INSTALLMENT_PLAN
-- Hedef  : MIGRATION.LS_INSTALLMENT_PLAN  →  izgazMGR.dbo.LS_INSTALLMENT_PLAN
-- Pattern: kaynak kolon isimleri birebir; ABYS_ID = ID bridge
-- Onkosul: MIGRATION.LS_INSTALLMENT (INSTALLMENT_ID FK mantigi)
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- TERMINAL DUMP: Oracle INDEX / GATHER_TABLE_STATS yok (CTAS zincirinde tuketilmiyor; IX -> izgazMGR/energy).

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_INSTALLMENT_PLAN PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_INSTALLMENT_PLAN
NOLOGGING
PARALLEL 56
AS
SELECT
    p.ID                                                    AS ID,
    p.ID                                                    AS ABYS_ID,
    p.INSTALLMENT_ID                                        AS INSTALLMENT_ID,
    p.ORDER_NUMBER                                          AS ORDER_NUMBER,
    p.EXPIRY_DATE                                           AS EXPIRY_DATE,
    p.AMOUNT                                                AS AMOUNT,
    p.LATE_CHARGE                                           AS LATE_CHARGE,
    p.OVERDUE                                               AS OVERDUE,
    p.PAYMENT_DATE                                          AS PAYMENT_DATE,
    p.CASH_ID                                               AS CASH_ID,
    p.RECEIPT_SERIAL                                        AS RECEIPT_SERIAL,
    p.RECEIPT_NUMBER                                        AS RECEIPT_NUMBER,
    p.DUE_DATE                                              AS DUE_DATE,
    p.CREATED_USER_ID                                       AS CREATED_USER_ID,
    CAST(p.CREATED_TIMESTAMP AS TIMESTAMP)                  AS CREATED_TIMESTAMP,
    p.UPDATED_USER_ID                                       AS UPDATED_USER_ID,
    CAST(p.UPDATED_TIMESTAMP AS TIMESTAMP)                  AS UPDATED_TIMESTAMP,
    p.VERSION                                               AS VERSION,
    p.OLD_LATE_CHARGE_                                      AS OLD_LATE_CHARGE_,
    p.OLD_AMOUNT_                                           AS OLD_AMOUNT_,
    p.POOL_ID                                               AS POOL_ID,
    p.DESCRIPTION                                           AS DESCRIPTION,
    p.OLD_LATE_CHARGE                                       AS OLD_LATE_CHARGE,
    p.OLD_EXPIRY_DATE                                       AS OLD_EXPIRY_DATE
FROM SMS.CS_INSTALLMENT_PLAN p
;

ALTER TABLE MIGRATION.LS_INSTALLMENT_PLAN NOPARALLEL LOGGING;


-- dogrulama
SELECT 'CS_INSTALLMENT_PLAN' KAYNAK, COUNT(*) CNT FROM SMS.CS_INSTALLMENT_PLAN
UNION ALL
SELECT 'LS_INSTALLMENT_PLAN', COUNT(*) FROM MIGRATION.LS_INSTALLMENT_PLAN
UNION ALL
SELECT 'LS_IPLAN_PAID', COUNT(*) FROM MIGRATION.LS_INSTALLMENT_PLAN WHERE PAYMENT_DATE IS NOT NULL
UNION ALL
SELECT 'LS_IPLAN_OPEN', COUNT(*) FROM MIGRATION.LS_INSTALLMENT_PLAN WHERE PAYMENT_DATE IS NULL;
