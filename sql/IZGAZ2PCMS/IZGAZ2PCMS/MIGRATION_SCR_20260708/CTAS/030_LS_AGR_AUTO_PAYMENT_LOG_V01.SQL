-- 030_LS_AGR_AUTO_PAYMENT_LOG_V01.SQL
-- Amac: Banka talimat log
-- Uretir: LS_AGREEMENT_AUTO_PAYMENT_LOG
-- Gate: yok
-- Sonraki: 031_LS_BANK_CONFIRM_V01.SQL
-- =====================================================================
-- LS_AGREEMENT_AUTO_PAYMENT_LOG  (Oracle staging - CTAS)
-- Kaynak : SMS.CS_AGREEMENT_AUTO_PAYMENT_LOG
-- Hedef  : MIGRATION.LS_AGREEMENT_AUTO_PAYMENT_LOG
--          → izgazMGR (dump). Energy 360/361 su an
--            izgazMGR.dbo.CS_AGREEMENT_AUTO_PAYMENT_LOG bekler;
--            dump'ta CS_ adiyla alinabilir veya SP kaynak adi guncellenir.
-- Hedef Energy : energy.dbo.LS_BNK_TALIMAT
-- Pattern: kaynak kolon isimleri birebir; ABYS_ID = ID bridge
-- Aciklama: Talimatli aboneler ve talimat verilen bankalar
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- TERMINAL DUMP: Oracle INDEX / GATHER_TABLE_STATS yok (CTAS zincirinde tuketilmiyor; IX -> izgazMGR/energy).

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_AGREEMENT_AUTO_PAYMENT_LOG PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_AGREEMENT_AUTO_PAYMENT_LOG
NOLOGGING
PARALLEL 56
AS
SELECT
    a.ID                                                    AS ID,
    a.ID                                                    AS ABYS_ID,
    a.AGREEMENT_ID                                          AS AGREEMENT_ID,
    a.BANK_ID                                               AS BANK_ID,
    a.INSTRUCTION_DATE                                      AS INSTRUCTION_DATE,
    a.CANCEL_DATE                                           AS CANCEL_DATE,
    a.DESCRIPTION                                           AS DESCRIPTION,
    a.CREATED_USER_ID                                       AS CREATED_USER_ID,
    CAST(a.CREATED_TIMESTAMP AS TIMESTAMP)                  AS CREATED_TIMESTAMP,
    a.UPDATED_USER_ID                                       AS UPDATED_USER_ID,
    CAST(a.UPDATED_TIMESTAMP AS TIMESTAMP)                  AS UPDATED_TIMESTAMP,
    a.VERSION                                               AS VERSION,
    a.CANCEL_USER_ID                                        AS CANCEL_USER_ID
FROM SMS.CS_AGREEMENT_AUTO_PAYMENT_LOG a
;

ALTER TABLE MIGRATION.LS_AGREEMENT_AUTO_PAYMENT_LOG NOPARALLEL LOGGING;


-- dogrulama
SELECT 'CS_AGREEMENT_AUTO_PAYMENT_LOG' KAYNAK, COUNT(*) CNT
FROM SMS.CS_AGREEMENT_AUTO_PAYMENT_LOG
UNION ALL
SELECT 'LS_AGREEMENT_AUTO_PAYMENT_LOG', COUNT(*)
FROM MIGRATION.LS_AGREEMENT_AUTO_PAYMENT_LOG
UNION ALL
SELECT 'LS_AAPL_ACTIVE', COUNT(*)
FROM MIGRATION.LS_AGREEMENT_AUTO_PAYMENT_LOG
WHERE CANCEL_DATE IS NULL
UNION ALL
SELECT 'LS_AAPL_CANCELLED', COUNT(*)
FROM MIGRATION.LS_AGREEMENT_AUTO_PAYMENT_LOG
WHERE CANCEL_DATE IS NOT NULL;

PROMPT ========== LS_AGREEMENT_AUTO_PAYMENT_LOG OK ==========
/

