-- =====================================================================
-- LS_AGR_GUARANTY  (Oracle staging - CTAS)
-- Kaynak : SMS.CS_ACCOUNT / CS_GUARANTEE_LETTER
-- Hedef  : MIGRATION.LS_AGR_GUARANTY  →  izgazMGR.dbo.LS_AGR_GUARANTY
-- Pattern: hedef kolon isimleri birebir; ABYS_* bridge dahil
--
-- Notlar:
--   1) UNION ALL kolon tipleri ilk dalda CAST ile sabitlenir (ORA-01790).
--   2) Dal 1 REGISTER_ID ile gruplanir → ayni AGRID icin birden fazla
--      GTYPE=39 satiri olusabilir (dogrulama asagida).
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- TERMINAL DUMP: Oracle INDEX / GATHER_TABLE_STATS yok (CTAS zincirinde tuketilmiyor; IX -> izgazMGR/energy).

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_AGR_GUARANTY PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_AGR_GUARANTY
NOLOGGING
PARALLEL 56
AS
-- Dal 1: GTYPE=39 - Nakit depozito (CS_ACCOUNT)
SELECT
    a.AGREEMENT_ID                                          AS AGRID,
    CAST(39 AS NUMBER(10))                                  AS GTYPE,
    CAST(NULL AS VARCHAR2(100))                             AS RFNO,
    MAX(CASE WHEN atp.TYPE = 2 AND a.ACCRUE_TYPE_ID IN (5, 6)
             THEN aa.ACTION_DATE END)                       AS SDATE,
    ag.REFUND_DATE                                          AS EDATE,
    SUM(CASE WHEN atp.TYPE = 1 AND a.ACCRUE_TYPE_ID IN (5, 6)
             THEN ai.AMOUNT * ai.STATUS END)                AS TOTAL,
    CAST(0 AS NUMBER(10))                                   AS WD,
    CAST(160 AS NUMBER(10))                                 AS EXCNR,
    SUM(CASE WHEN atp.TYPE = 2 AND a.ACCRUE_TYPE_ID IN (5, 6)
             THEN ai.AMOUNT * ai.STATUS END)                AS MUSTTL,
    MAX(a.CREATED_TIMESTAMP)                                AS ADDDATE,
    MAX(a.CREATED_USER_ID)                                  AS ADDUSER,
    CAST(NULL AS DATE)                                      AS UPDDATE,
    CAST(NULL AS NUMBER)                                    AS UPDUSER,
    CAST(NULL AS NUMBER)                                    AS LOGOREF,
    CAST(NULL AS NUMBER)                                    AS BANKREF,
    CAST(NULL AS NUMBER)                                    AS BANKACCREF,
    CAST(NULL AS VARCHAR2(200))                             AS CUSTBNK,
    CAST(NULL AS VARCHAR2(200))                             AS CUSTBNKACC,
    CAST(NULL AS VARCHAR2(100))                             AS CUSTBNKNO,
    a.REGISTER_ID                                           AS ABYS_REGISTER_ID,
    a.AGREEMENT_ID                                          AS ABYS_AGREEMENT_ID,
    CAST(NULL AS NUMBER)                                    AS ABYS_GL_REF,
    CAST(NULL AS VARCHAR2(4000))                            AS ABYS_GL_DESC,
    CAST(NULL AS VARCHAR2(4000))                            AS ABYS_GL_BNK_DESC,
    CAST(NULL AS NUMBER)                                    AS ABYS_GL_BANK_REF,
    CAST(NULL AS NUMBER)                                    AS ABYS_GL_STATUS,
    CAST(0 AS NUMBER(1))                                    AS CONVERTED_TO_CASH,
    CASE WHEN ag.REFUND_NUMBER > 0 THEN 1 ELSE 0 END        AS REFUND
FROM SMS.CS_ACCOUNT a
JOIN SMS.CS_ACCOUNT_ACTION aa   ON aa.ACCOUNT_ID        = a.ID
JOIN SMS.CS_ACCOUNT_INCOME ai   ON ai.ACCOUNT_ACTION_ID = aa.ID
JOIN SMS.CS_ACTION_TYPE_PRM atp ON aa.ACTION_TYPE_ID    = atp.ID
JOIN SMS.CS_AGREEMENT ag        ON a.AGREEMENT_ID       = ag.ID
WHERE ai.INCOME_ID IN (23032, 163, 164, 165, 1936, 162, 3199, 3198, 7649, 7650, 7651, 7652, 12531)
  -- 45 = TEMİNAT MEKTUBU İLE TAHSİLAT → nakit (GTYPE=39) degil; mektup Dal 2'de
  AND aa.ACTION_TYPE_ID <> 45
  AND NOT EXISTS (
        SELECT 1
        FROM SMS.CS_ACCOUNT_ACTION aa2
        WHERE aa2.ACCOUNT_ID     = aa.ACCOUNT_ID
          AND aa2.CASH_ID        = aa.CASH_ID
          AND aa2.RECEIPT_NUMBER = aa.RECEIPT_NUMBER
          AND aa2.ACTION_TYPE_ID = 9
  )
GROUP BY
    a.AGREEMENT_ID,
    a.REGISTER_ID,
    ag.REFUND_DATE,
    ag.REFUND_NUMBER

UNION ALL

-- Dal 2: GTYPE=40/41 - Teminat mektubu
SELECT
    gl.AGREEMENT_ID                                         AS AGRID,
    CASE WHEN gl.FINISH_DATE IS NULL THEN 41 ELSE 40 END    AS GTYPE,
    gl.REF_NUMBER                                           AS RFNO,
    gl.START_DATE                                           AS SDATE,
    gl.FINISH_DATE                                          AS EDATE,
    gl.AMOUNT                                               AS TOTAL,
    CAST(0 AS NUMBER(10))                                   AS WD,
    CAST(160 AS NUMBER(10))                                 AS EXCNR,
    gl.AMOUNT                                               AS MUSTTL,
    gl.CREATED_TIMESTAMP                                    AS ADDDATE,
    gl.CREATED_USER_ID                                      AS ADDUSER,
    gl.UPDATED_TIMESTAMP                                    AS UPDDATE,
    gl.UPDATED_USER_ID                                      AS UPDUSER,
    CAST(NULL AS NUMBER)                                    AS LOGOREF,
    CAST(NULL AS NUMBER)                                    AS BANKREF,
    CAST(NULL AS NUMBER)                                    AS BANKACCREF,
    CAST(NULL AS VARCHAR2(200))                             AS CUSTBNK,
    CAST(NULL AS VARCHAR2(200))                             AS CUSTBNKACC,
    CAST(NULL AS VARCHAR2(100))                             AS CUSTBNKNO,
    gl.REGISTER_ID                                          AS ABYS_REGISTER_ID,
    gl.AGREEMENT_ID                                         AS ABYS_AGREEMENT_ID,
    gl.ID                                                   AS ABYS_GL_REF,
    gl.STATUS_DESCRIPTION                                   AS ABYS_GL_DESC,
    gl.BANK_DESCRIPTION                                     AS ABYS_GL_BNK_DESC,
    gl.BANK_ID                                              AS ABYS_GL_BANK_REF,
    gl.STATUS                                               AS ABYS_GL_STATUS,
    CASE WHEN gl.STATUS = 4 THEN 1 ELSE 0 END               AS CONVERTED_TO_CASH,
    CASE WHEN gl.STATUS IN (2, 3) THEN 1 ELSE 0 END         AS REFUND
FROM SMS.CS_GUARANTEE_LETTER gl
;

ALTER TABLE MIGRATION.LS_AGR_GUARANTY NOPARALLEL LOGGING;


-- dogrulama
SELECT 'LS_AGR_GUARANTY' KAYNAK, COUNT(*) CNT FROM MIGRATION.LS_AGR_GUARANTY
UNION ALL
SELECT 'GTYPE_' || TO_CHAR(GTYPE), COUNT(*) FROM MIGRATION.LS_AGR_GUARANTY GROUP BY GTYPE;

SELECT GTYPE, COUNT(*) AS ADET, SUM(TOTAL) AS TOPLAM_TUTAR
FROM MIGRATION.LS_AGR_GUARANTY
GROUP BY GTYPE
ORDER BY GTYPE;

-- REGISTER_ID kaynakli AGRID coklamasi (GTYPE=39)
SELECT AGRID, COUNT(*) AS ADET
FROM MIGRATION.LS_AGR_GUARANTY
WHERE GTYPE = 39
GROUP BY AGRID
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;

SELECT
    SUM(CASE WHEN GTYPE = 39 AND SDATE IS NULL THEN 1 ELSE 0 END) AS ODEMESIZ_DEPOZITO,
    SUM(CASE WHEN GTYPE = 39 AND NVL(MUSTTL, 0) > NVL(TOTAL, 0) THEN 1 ELSE 0 END) AS ODEME_TAHAKKUKU_ASIYOR,
    SUM(CASE WHEN GTYPE = 39 AND TOTAL IS NULL THEN 1 ELSE 0 END) AS TAHAKKUKSUZ
FROM MIGRATION.LS_AGR_GUARANTY;
