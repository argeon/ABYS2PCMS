-- ============================================================
-- ABYS -> PCMS : LS_AGR_GUARANTY staging (MIGRATION semasi)
-- Kaynak: SMS | Hedef: MIGRATION | Oracle 11.2
--
-- DUZELTMELER / NOTLAR:
--   1) Ilk dalda tipsiz NULL literalleri CAST'lendi.
--      UNION ALL'da kolon tipini ILK dal belirler; tipsiz NULL +
--      ikinci dalda VARCHAR2/NUMBER/DATE karisimi ORA-01790
--      riskidir (bu projede daha once yasandi).
--   2) atpl (CS_ACTION_TYPE_PRM_LNG) join'i SELECT'te
--      kullanilmiyordu, kaldirildi.
--   3) GROUP BY'daki ag.CREATED_USER_ID SELECT'te yok;
--      agreement basina sabit oldugu icin grup bolmez ama
--      gereksizdi, kaldirildi.
--   4) DIKKAT: Ilk dal a.REGISTER_ID ile gruplaniyor.
--      Ayni sozlesmede farkli REGISTER_ID'li hesaplar varsa
--      AGRID basina BIRDEN FAZLA GTYPE=39 satiri olusur.
--      Dogrulama sorgusu bunu olcuyor.
-- ============================================================

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_AGR_GUARANTY PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_AGR_GUARANTY
NOLOGGING
PARALLEL 4
AS
-- ============================================
-- Dal 1: GTYPE=39 - Nakit depozito (CS_ACCOUNT)
-- ============================================
SELECT
    a.AGREEMENT_ID                                          AS AGRID,
    39                                                      AS GTYPE,
    CAST(NULL AS VARCHAR2(100))                             AS RFNO,
    MAX(CASE WHEN atp.TYPE = 2 AND a.ACCRUE_TYPE_ID IN (5,6)
             THEN aa.ACTION_DATE END)                       AS SDATE,  -- DEPOSIT_PAYMENT_DATE
    ag.REFUND_DATE                                          AS EDATE,
    SUM(CASE WHEN atp.TYPE = 1 AND a.ACCRUE_TYPE_ID IN (5,6)
             THEN ai.AMOUNT * ai.STATUS END)                AS TOTAL,  -- DEPOSIT_ACCRUE_AMOUNT
    0                                                       AS WD,
    160                                                     AS EXCNR,
    SUM(CASE WHEN atp.TYPE = 2 AND a.ACCRUE_TYPE_ID IN (5,6)
             THEN ai.AMOUNT * ai.STATUS END)                AS MUSTTL, -- DEPOSIT_PAYMENT_AMOUNT
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
    CAST(NULL AS NUMBER)                                    AS ABYS_GL_STATUS,  -- GuaranteeLetterStatus(1=ACTIVE;2=RETURN;3=CANCEL;4=CONVERTED_TO_CASH)
    0                                                       AS CONVERTED_TO_CASH,
    CASE WHEN ag.REFUND_NUMBER > 0 THEN 1 ELSE 0 END        AS REFUND
FROM SMS.CS_ACCOUNT a
JOIN SMS.CS_ACCOUNT_ACTION aa   ON aa.ACCOUNT_ID        = a.ID
JOIN SMS.CS_ACCOUNT_INCOME ai   ON ai.ACCOUNT_ACTION_ID = aa.ID
JOIN SMS.CS_ACTION_TYPE_PRM atp ON aa.ACTION_TYPE_ID    = atp.ID
JOIN SMS.CS_AGREEMENT ag        ON a.AGREEMENT_ID       = ag.ID
WHERE ai.INCOME_ID IN (23032,163,164,165,1936,162,3199,3198,7649,7650,7651,7652,12531)
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

-- ============================================
-- Dal 2: GTYPE=40/41 - Teminat mektubu
-- ============================================
SELECT
    gl.AGREEMENT_ID                                         AS AGRID,
    CASE WHEN gl.FINISH_DATE IS NULL THEN 41 ELSE 40 END    AS GTYPE,
    gl.REF_NUMBER                                           AS RFNO,
    gl.START_DATE                                           AS SDATE,
    gl.FINISH_DATE                                          AS EDATE,
    gl.AMOUNT                                               AS TOTAL,
    0                                                       AS WD,
    160                                                     AS EXCNR,
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
    CASE WHEN gl.STATUS IN (2,3) THEN 1 ELSE 0 END          AS REFUND
FROM SMS.CS_GUARANTEE_LETTER gl
;

-- ============================================================
-- INDEX + FINALIZE
-- ============================================================
CREATE INDEX MIGRATION.IDX_LS_GRNT_AGRID
    ON MIGRATION.LS_AGR_GUARANTY (AGRID) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IDX_LS_GRNT_GTYPE
    ON MIGRATION.LS_AGR_GUARANTY (GTYPE) NOLOGGING PARALLEL 4;

ALTER TABLE MIGRATION.LS_AGR_GUARANTY NOPARALLEL LOGGING;
ALTER INDEX MIGRATION.IDX_LS_GRNT_AGRID NOPARALLEL;
ALTER INDEX MIGRATION.IDX_LS_GRNT_GTYPE NOPARALLEL;

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS('MIGRATION','LS_AGR_GUARANTY', cascade => TRUE, degree => 4);
END;
/

-- ============================================================
-- DOGRULAMA
-- ============================================================
SELECT GTYPE, COUNT(*) AS ADET, SUM(TOTAL) AS TOPLAM_TUTAR
FROM MIGRATION.LS_AGR_GUARANTY
GROUP BY GTYPE ORDER BY GTYPE;

-- REGISTER_ID kaynakli AGRID coklamasi (GTYPE=39)
SELECT AGRID, COUNT(*) AS ADET
FROM MIGRATION.LS_AGR_GUARANTY
WHERE GTYPE = 39
GROUP BY AGRID
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;

-- Tahakkuk var / tahsilat yok (SDATE NULL) veya tutarsiz tutarlar
SELECT
    SUM(CASE WHEN GTYPE = 39 AND SDATE IS NULL THEN 1 ELSE 0 END) AS ODEMESIZ_DEPOZITO,
    SUM(CASE WHEN GTYPE = 39 AND NVL(MUSTTL,0) > NVL(TOTAL,0) THEN 1 ELSE 0 END) AS ODEME_TAHAKKUKU_ASIYOR,
    SUM(CASE WHEN GTYPE = 39 AND TOTAL IS NULL THEN 1 ELSE 0 END) AS TAHAKKUKSUZ
FROM MIGRATION.LS_AGR_GUARANTY;

-- LS_AGREEMENT ile FEE_COLLECTED tutarliligi
SELECT la.ABYS_ID, la.FEE_COLLECTED
FROM MIGRATION.LS_AGREEMENT la
JOIN MIGRATION.LS_AGR_GUARANTY g
     ON g.AGRID = la.ABYS_ID AND g.GTYPE = 39
WHERE la.TP2 = 'KUL'
  AND la.FEE_COLLECTED = 0
  AND g.MUSTTL > 0
  AND ROWNUM <= 100;