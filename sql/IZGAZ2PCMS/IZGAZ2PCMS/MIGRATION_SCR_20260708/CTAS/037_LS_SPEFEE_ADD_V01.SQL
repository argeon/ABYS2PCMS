-- 037_LS_SPEFEE_ADD_V01.SQL
-- Amac: SPEFEE devir
-- Uretir: LS_SPEFEE_ADD
-- Gate: yok
-- Sonraki: 038_LS_PROJECT_V01.SQL
-- =====================================================================
-- LS_SPEFEE_ADD  (Oracle staging - CTAS)
-- Kaynak : SMS.CS_AGREEMENT  (ROUND_VALUE != 0 → onceki aydan devir)
--          + CS_INSTALLATION_INDEX (READING_DATE → ADDATE)
--          + CS_READING (son okuma; AGREEMENT_ID baglantisi)
-- Hedef  : MIGRATION.LS_SPEFEE_ADD  →  izgazMGR.dbo.LS_SPEFEE_ADD
--          → energy.dbo.LS_005_01_SPEFEE  (SPEFEE migrate ile ayni hedef)
-- Pattern: LS_SPEFEE kolon deseni birebir; ABYS_* bridge dahil
--
-- Kaynak ozet:
--   CS_AGREEMENT.ID                 → OWNERREF / CLIENTREF / LREF / ABYS_ID
--   CS_AGREEMENT.INSTALLATION_ID    → FITNO
--   CS_AGREEMENT.ROUND_VALUE        → TLTOTAL / GRANDTOTAL  (ONCEKI_AYDAN_DEVIR)
--   CS_INSTALLATION_INDEX.READING_DATE → ADDATE  (INDEX_TYPE_ID=1, IS_ACTIVE=1)
--   CS_READING (AGR basina son)     → READING_ID / INVOICEREF / ADDUSER / ABYS_*
-- Filtre: ROUND_VALUE IS NOT NULL AND ROUND_VALUE <> 0
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- TERMINAL DUMP: Oracle INDEX / GATHER_TABLE_STATS yok (CTAS zincirinde tuketilmiyor; IX -> izgazMGR/energy).

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_SPEFEE_ADD PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_SPEFEE_ADD
NOLOGGING
PARALLEL 56
AS
SELECT
    agr.ID                                                      AS LREF,

    CAST(NULL AS NUMBER(3))                                     AS STYPE_OLD,

    CAST('ONCEKI AYDAN DEVIR' AS VARCHAR2(100))                 AS LINEEXP,

    -- Pass 1: ham ACCOUNT_ID (okuma uzerinden); wire sonrasi LS_*_INVOICE.LREF
    rd.ACCOUNT_ID                                               AS INVOICEREF,

    SUBSTR(TRIM(reg.FIRST_NAME || ' ' || reg.LAST_NAME), 1, 50) AS CUSTNAME,

    agr.ID                                                      AS CLIENTREF,
    agr.ID                                                      AS OWNERREF,
    91                                                          AS CLIENTTYPE,

    CAST(agr.ROUND_VALUE AS NUMBER(15,3))                       AS TLTOTAL,
    CAST(0 AS NUMBER(15,3))                                     AS TAX,
    CAST(agr.ROUND_VALUE AS NUMBER(15,3))                       AS GRANDTOTAL,

    -- ADDATE = tesisat son endeks okuma tarihi
    CAST(ix.READING_DATE AS DATE)                               AS ADDDATE,
    NVL(rd.CREATED_USER_ID, agr.CREATED_USER_ID)                AS ADDUSER,

    CAST(0 AS NUMBER(1))                                        AS CANCELLED,

    CAST(NVL(rd.UPDATED_TIMESTAMP, agr.UPDATED_TIMESTAMP) AS DATE) AS UPDDATE,
    NVL(rd.UPDATED_USER_ID, agr.UPDATED_USER_ID)                AS UPDUSER,

    CAST(NULL AS NUMBER(10))                                    AS READ_TRANSFERREF,
    CAST(NULL AS NUMBER(10))                                    AS READ_NO,
    0                                                           AS PRINTED,

    -- 1929 = ONCEKI AYDAN DEVIR (STG_SPEFEE / R23)
    1929                                                        AS IU_TYPE,
    CAST(ix.LAST_INDEX AS NUMBER(10))                           AS IND_DIFF,
    6                                                           AS STYPE,

    rd.ID                                                       AS READING_ID,
    CAST(2 AS NUMBER(10))                                       AS STATUS,
    CAST(NULL AS NUMBER(10))                                    AS INSTALLMENT_NO,
    CAST(NULL AS NUMBER(10))                                    AS INSTALLMENT_NR,

    -- Tesisat no (kaynak: CS_AGREEMENT.INSTALLATION_ID)
    agr.INSTALLATION_ID                                         AS FITNO,

    -- ========== ABYS_* bridge ==========
    agr.ID                                                      AS ABYS_ID,
    agr.ID                                                      AS ABYS_AGREEMENT_ID,
    rd.ACCOUNT_ID                                               AS ABYS_ACCOUNT_ID,
    CAST(1929 AS NUMBER(19))                                    AS ABYS_INCOME_ID,
    CAST(NULL AS NUMBER(10))                                    AS ABYS_PERIOD,
    CAST(rd.BILL_DATE AS DATE)                                  AS ABYS_ACTION_DATE,
    CAST(NULL AS NUMBER(19))                                    AS ABYS_WORK_ORDER_ID,
    CAST(NULL AS NUMBER(18,6))                                  AS ABYS_QUANTITY,
    CAST(NULL AS NUMBER(19))                                    AS ABYS_ACCRUE_GROUP_ID,
    CAST(NULL AS NUMBER(19))                                    AS ABYS_CASH_ID,
    CAST(NULL AS VARCHAR2(2))                                   AS ABYS_RECEIPT_SERIAL,
    CAST(NULL AS NUMBER(25,0))                                  AS ABYS_RECEIPT_NUMBER,
    CAST(NULL AS NUMBER(19))                                    AS ABYS_ANALYSIS_ACCOUNT_ID,
    agr.VERSION                                                 AS ABYS_VERSION,
    CAST(NULL AS VARCHAR2(20))                                  AS ABYS_TRANSACTION_CODE,
    NVL(rd.CREATED_USER_ID, agr.CREATED_USER_ID)                AS ABYS_CREATED_USER_ID,
    NVL(rd.UPDATED_USER_ID, agr.UPDATED_USER_ID)                AS ABYS_UPDATED_USER_ID,
    rd.ID                                                       AS ABYS_READING_ID,
    agr.INSTALLATION_ID                                         AS ABYS_INSTALLATION_ID,
    agr.ROUND_VALUE                                             AS ABYS_ROUND_VALUE,
    ix.ID                                                       AS ABYS_INSTALLATION_INDEX_ID,
    CAST(ix.READING_DATE AS DATE)                               AS ABYS_READING_DATE,
    ix.LAST_INDEX                                               AS ABYS_LAST_INDEX,
    rd.METER_ID                                                 AS ABYS_METER_ID,
    rd.STATUS                                                   AS ABYS_READING_STATUS,
    CAST(rd.BILL_DATE AS DATE)                                  AS ABYS_BILL_DATE

FROM SMS.CS_AGREEMENT agr
LEFT JOIN SMS.CS_REGISTER reg
       ON reg.ID = agr.BENEFITED_REGISTER_ID
LEFT JOIN SMS.CS_INSTALLATION_INDEX ix
       ON ix.INSTALLATION_ID = agr.INSTALLATION_ID
      AND ix.INDEX_TYPE_ID = 1
      AND ix.IS_ACTIVE = 1
LEFT JOIN (
    SELECT *
    FROM (
        SELECT
            r.*,
            ROW_NUMBER() OVER (
                PARTITION BY r.AGREEMENT_ID
                ORDER BY r.BILL_DATE DESC NULLS LAST, r.ID DESC
            ) AS RN
        FROM SMS.CS_READING r
    ) t
    WHERE RN = 1
) rd
       ON rd.AGREEMENT_ID = agr.ID
WHERE agr.ROUND_VALUE IS NOT NULL
  AND agr.ROUND_VALUE <> 0
;

ALTER TABLE MIGRATION.LS_SPEFEE_ADD NOPARALLEL LOGGING;


-- dogrulama
SELECT 'CS_AGREEMENT_ROUND' KAYNAK, COUNT(*) CNT
FROM SMS.CS_AGREEMENT
WHERE ROUND_VALUE IS NOT NULL
  AND ROUND_VALUE <> 0
UNION ALL
SELECT 'LS_SPEFEE_ADD', COUNT(*)
FROM MIGRATION.LS_SPEFEE_ADD
UNION ALL
SELECT 'LS_SPEFEE_ADD_WITH_IX', COUNT(*)
FROM MIGRATION.LS_SPEFEE_ADD
WHERE ABYS_INSTALLATION_INDEX_ID IS NOT NULL
UNION ALL
SELECT 'LS_SPEFEE_ADD_WITH_RD', COUNT(*)
FROM MIGRATION.LS_SPEFEE_ADD
WHERE READING_ID IS NOT NULL;

SELECT
    OWNERREF,
    FITNO,
    GRANDTOTAL AS ONCEKI_AYDAN_DEVIR,
    ADDDATE,
    READING_ID,
    INVOICEREF
FROM MIGRATION.LS_SPEFEE_ADD
WHERE ROWNUM <= 20
ORDER BY OWNERREF;

PROMPT ========== LS_SPEFEE_ADD OK ==========
/

