-- =============================================================================
-- prod2 / 12 — LS_INVLINES (energy LS_005_01_INVLINES yakin)
-- Onkosul: 11_ls_invoice.sql
-- LREF = CS_ACCOUNT_INCOME.ID | INVOICEREF = LS_INVOICE.LREF
-- DOP: 52 | Sonraki: 13_ls_mig_agr_list.sql
-- =============================================================================

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM ALL_TABLES
   WHERE OWNER = 'MIGRATION' AND TABLE_NAME = 'LS_INVOICE';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20012, 'LS_INVOICE yok. Once 11_ls_invoice.sql');
  END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_INVLINES PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE MIGRATION.LS_INVLINES
NOLOGGING
PARALLEL 52
AS
SELECT /*+ PARALLEL(52) */

    CAST(ai.ID AS NUMBER(12))                                     AS LREF,
    CAST(inv.LREF AS NUMBER(12))                                  AS INVOICEREF,
    CAST(inv.CLIENTREF AS NUMBER(12))                             AS CLIENTREF,

    CASE
      WHEN EXTRACT(YEAR FROM NVL(aa.ACTION_DATE, inv.DATE_)) < 1753
      THEN ADD_MONTHS(NVL(aa.ACTION_DATE, inv.DATE_), 24000)
      ELSE NVL(aa.ACTION_DATE, inv.DATE_)
    END                                                           AS DATE_,

    CAST(
      CASE
        WHEN NVL(ai.IS_DISCOUNT, 0) = 1 THEN 103
        ELSE NVL(inv.TYPE, 119)
      END AS NUMBER(3)
    )                                                             AS TYPE,

    CAST(
      ROW_NUMBER() OVER (
        PARTITION BY ai.ACCOUNT_ACTION_ID
        ORDER BY NVL(ip.ACCRUE_GROUP_ID, 0), ai.ID
      ) AS NUMBER(5)
    )                                                             AS LINENR,

    CAST(
      CASE WHEN NVL(ip.IS_VAT_INCOME, 0) = 1 THEN 0
           ELSE NVL(ai.AMOUNT, 0)
      END AS NUMBER(18,3)
    )                                                             AS TLTOTAL,

    CAST(160 AS NUMBER(10))                                       AS CURID,
    CAST(1 AS NUMBER(18,6))                                       AS CURRATE,
    CAST(
      CASE WHEN NVL(ip.IS_VAT_INCOME, 0) = 1 THEN 0
           ELSE NVL(ai.AMOUNT, 0)
      END AS NUMBER(18,3)
    )                                                             AS CURTOTAL,

    CAST(aa.M3 AS NUMBER(18,6))                                   AS FIRSTREAD,
    CAST(aa.KWH AS NUMBER(18,6))                                  AS LASTREAD,

    CAST(
      CASE
        WHEN NVL(ai.IS_DISCOUNT, 0) = 1 AND ai.INCOME_ID = 939  THEN 807
        WHEN NVL(ai.IS_DISCOUNT, 0) = 1 AND ai.INCOME_ID = 7658 THEN 808
        ELSE NVL(ai.INCOME_ID, 0)
      END AS NUMBER(10)
    )                                                             AS TRANSTYPE,

    CAST(0 AS NUMBER(1))                                          AS CANCELED,

    CAST(
      CASE WHEN NVL(ip.IS_VAT_INCOME, 0) = 1 THEN NVL(ai.AMOUNT, 0)
           ELSE 0
      END AS NUMBER(18,3)
    )                                                             AS TAX,

    CAST(NVL(ai.AMOUNT, 0) AS NUMBER(18,3))                       AS GRANDTOTAL,

    CAST(
      CASE
        WHEN ai.INCOME_ID = 958  THEN 'SONRAKI AYA DEVIR'
        WHEN ai.INCOME_ID = 1929 THEN 'ONCEKI AYDAN DEVIR'
        WHEN NVL(ai.IS_DISCOUNT, 0) = 1 AND ai.INCOME_ID = 939  THEN 'Gaz Bedeli Indirim'
        WHEN NVL(ai.IS_DISCOUNT, 0) = 1 AND ai.INCOME_ID = 7658 THEN 'SKB Bedeli Indirim'
        ELSE SUBSTR(NVL(ipl.VALUE, ip.CODE), 1, 300)
      END AS VARCHAR2(300)
    )                                                             AS LINEEXP,

    CAST(NVL(ip.INCOME_TYPE, 0) AS NUMBER(10))                    AS LINETYPE,
    CAST(0 AS NUMBER(18,3))                                       AS DV,
    CAST(TO_CHAR(inv.FITNO) AS VARCHAR2(100))                     AS FITNO,
    CAST(NULL AS NUMBER(10))                                      AS CNTREF,
    CAST(NULL AS NUMBER(10))                                      AS LOGO_FIRMNR,
    CAST(NULL AS NUMBER(10))                                      AS LOGO_FICHEREF,
    CAST(NULL AS VARCHAR2(100))                                   AS LOGO_FICHENO,
    CAST(NULL AS NUMBER(10))                                      AS XTYPE,

    CAST(ai.UNIT_PRICE AS NUMBER(19,8))                           AS UNITPRICE,
    CAST(NULL AS NUMBER(10))                                      AS SPEREF,
    CAST(ai.QUANTITY AS NUMBER(18,6))                             AS AMOUNT,

    CAST(NULL AS DATE)                                            AS FIRST_DATE,
    CAST(NULL AS DATE)                                            AS LAST_DATE,
    CAST(NULL AS NUMBER(5))                                       AS "DAY",

    CAST(ai.ID AS NUMBER(12))                                     AS ABYS_INCOME_ROW_ID,
    CAST(ai.INCOME_ID AS NUMBER(10))                              AS ABYS_INCOME_ID,
    CAST(ai.ACCOUNT_ACTION_ID AS NUMBER(12))                      AS ABYS_ACTION_ID,
    CAST(inv.ABYS_ACCOUNT_ID AS NUMBER(12))                       AS ABYS_ACCOUNT_ID,
    CAST(inv.ABYS_REGISTER_ID AS NUMBER(12))                      AS ABYS_REGISTER_ID,
    CAST(inv.ABYS_AGREEMENT_ID AS NUMBER(12))                     AS ABYS_AGREEMENT_ID,
    CAST(inv.ABYS_ACTION_TYPE_ID AS NUMBER(10))                   AS ABYS_ACTION_TYPE_ID,
    CAST(inv.ABYS_ACCRUE_TYPE_ID AS NUMBER(10))                   AS ABYS_ACCRUE_TYPE_ID,
    CAST(NVL(ai.IS_DISCOUNT, 0) AS NUMBER(1))                     AS ABYS_IS_DISCOUNT,
    CAST(NVL(ip.IS_VAT_INCOME, 0) AS NUMBER(1))                   AS ABYS_IS_VAT_INCOME,
    CAST(NVL(ip.IS_DEPOSIT, 0) AS NUMBER(1))                      AS ABYS_IS_DEPOSIT,
    CAST(NVL(ip.IS_OVERDUE_INCOME, 0) AS NUMBER(1))               AS ABYS_IS_OVERDUE_INCOME,
    CAST(NVL(ip.IS_LEGAL_FEE, 0) AS NUMBER(1))                    AS ABYS_IS_LEGAL_FEE,
    CAST(SUBSTR(ip.CODE, 1, 10) AS VARCHAR2(10))                  AS ABYS_INCOME_CODE,
    CAST(ai.AMOUNT AS NUMBER(18,3))                               AS ABYS_AMOUNT_RAW,
    CAST(ai.STATUS AS NUMBER(5))                                  AS ABYS_STATUS,
    CAST(ai.QUANTITY AS NUMBER(18,6))                             AS ABYS_QUANTITY,
    CAST(ai.UNIT_PRICE AS NUMBER(19,8))                           AS ABYS_UNIT_PRICE,
    CAST(ai.AMOUNT1 AS NUMBER(18,3))                              AS ABYS_AMOUNT1,
    CAST(ai.AMOUNT2 AS NUMBER(18,3))                              AS ABYS_AMOUNT2,
    CAST(ai.AMOUNT3 AS NUMBER(18,3))                              AS ABYS_AMOUNT3,
    CAST(ai.AMOUNT4 AS NUMBER(18,3))                              AS ABYS_AMOUNT4,
    CAST(ai.AMOUNT5 AS NUMBER(18,3))                              AS ABYS_AMOUNT5,

    CAST(NVL(ip.ACCRUE_GROUP_ID, 0) AS NUMBER(10))                AS ABYS_ACCRUE_GROUP_ID,
    CAST(SUBSTR(NVL(ipl.VALUE, ip.CODE), 1, 200) AS VARCHAR2(200)) AS ABYS_INCOME_NAME,

    CAST(ai.ID AS NUMBER(12))                                     AS ABYS_ID

FROM SMS.CS_ACCOUNT_INCOME ai
JOIN MIGRATION.LS_INVOICE inv
  ON inv.ABYS_ACTION_ID = ai.ACCOUNT_ACTION_ID
LEFT JOIN SMS.CS_ACCOUNT_ACTION aa
  ON aa.ID = ai.ACCOUNT_ACTION_ID
LEFT JOIN SMS.CS_INCOME_PRM ip
  ON ip.ID = ai.INCOME_ID
LEFT JOIN SMS.CS_INCOME_PRM_LNG ipl
  ON ipl.PRM_ID = ip.ID
 AND ipl.LANG_ID = 1;

CREATE UNIQUE INDEX MIGRATION.IX_LS_IL_LREF ON MIGRATION.LS_INVLINES (LREF) PARALLEL 52 NOLOGGING;
CREATE INDEX MIGRATION.IX_LS_IL_INVREF ON MIGRATION.LS_INVLINES (INVOICEREF) PARALLEL 52 NOLOGGING;
CREATE INDEX MIGRATION.IX_LS_IL_AGR ON MIGRATION.LS_INVLINES (ABYS_AGREEMENT_ID) PARALLEL 52 NOLOGGING;
CREATE INDEX MIGRATION.IX_LS_IL_AGR_INV ON MIGRATION.LS_INVLINES (ABYS_AGREEMENT_ID, INVOICEREF) PARALLEL 52 NOLOGGING;

ALTER INDEX MIGRATION.IX_LS_IL_LREF NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_IL_INVREF NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_IL_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_IL_AGR_INV NOPARALLEL;

ALTER TABLE MIGRATION.LS_INVLINES NOPARALLEL LOGGING;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_INVLINES', degree => 32); END;
/

SELECT
  (SELECT COUNT(*) FROM MIGRATION.LS_INVOICE) AS INV_CNT,
  (SELECT COUNT(*) FROM MIGRATION.LS_INVLINES) AS LINE_CNT,
  (SELECT SUM(CASE WHEN LREF <> ABYS_INCOME_ROW_ID THEN 1 ELSE 0 END) FROM MIGRATION.LS_INVLINES) AS BAD_LREF
FROM DUAL;

PROMPT ========== 12 LS_INVLINES OK ==========
/