-- =====================================================================
-- LS_SPEFEE  (Oracle staging - CTAS)
-- Kaynak : SMS.CS_ACCOUNT_ADD
-- Hedef  : MIGRATION.LS_SPEFEE  →  energy.dbo.LS_005_01_SPEFEE
-- Pattern: hedef kolon isimleri birebir; ABYS_* bridge dahil
-- =====================================================================

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_SPEFEE PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_SPEFEE
NOLOGGING
PARALLEL 4
AS
SELECT
    aa.ID                                                       AS LREF,

    CAST(NULL AS NUMBER(3))                                     AS STYPE_OLD,

    SUBSTR(aa.DESCRIPTION, 1, 100)                              AS LINEEXP,

    -- Pass 1: ham ACCOUNT_ID; wire sonrasi LS_*_INVOICE.LREF
    aa.ACCOUNT_ID                                               AS INVOICEREF,

    SUBSTR(TRIM(reg.FIRST_NAME || ' ' || reg.LAST_NAME), 1, 50) AS CUSTNAME,

    aa.AGREEMENT_ID                                             AS CLIENTREF,
    aa.AGREEMENT_ID                                             AS OWNERREF,
    91                                                          AS CLIENTTYPE,

    CAST(aa.AMOUNT AS BINARY_DOUBLE)                            AS TLTOTAL,
    CAST(0 AS BINARY_DOUBLE)                                    AS TAX,
    CAST(aa.AMOUNT AS BINARY_DOUBLE)                            AS GRANDTOTAL,

    NVL(CAST(aa.CREATED_TIMESTAMP AS DATE), aa.ACTION_DATE)     AS ADDDATE,
    aa.CREATED_USER_ID                                          AS ADDUSER,

    -- STATUS sozlugu TBD; gecici: 0 = iptal
    CASE WHEN aa.STATUS = 0 THEN 1 ELSE 0 END                   AS CANCELLED,

    CAST(aa.UPDATED_TIMESTAMP AS DATE)                          AS UPDDATE,
    aa.UPDATED_USER_ID                                          AS UPDUSER,

    CAST(NULL AS NUMBER(10))                                    AS READ_TRANSFERREF,
    CAST(NULL AS NUMBER(10))                                    AS READ_NO,
    0                                                           AS PRINTED,

    aa.INCOME_ID                                                AS IU_TYPE,
    CAST(NULL AS NUMBER(10))                                    AS IND_DIFF,
    6                                                           AS STYPE,

    aa.READING_ID                                               AS READING_ID,
    aa.STATUS                                                   AS STATUS,
    aa.INSTALLMENT_ORDER_NUMBER                                 AS INSTALLMENT_NO,
    aa.INSTALLMENT_ORDER_NUMBER                                 AS INSTALLMENT_NR,

    -- ========== ABYS_* bridge ==========
    aa.ID                                                       AS ABYS_ID,
    aa.AGREEMENT_ID                                             AS ABYS_AGREEMENT_ID,
    aa.ACCOUNT_ID                                               AS ABYS_ACCOUNT_ID,
    aa.INCOME_ID                                                AS ABYS_INCOME_ID,
    aa.PERIOD                                                   AS ABYS_PERIOD,
    aa.ACTION_DATE                                              AS ABYS_ACTION_DATE,
    aa.WORK_ORDER_ID                                            AS ABYS_WORK_ORDER_ID,
    aa.QUANTITY                                                 AS ABYS_QUANTITY,
    aa.ACCRUE_GROUP_ID                                          AS ABYS_ACCRUE_GROUP_ID,
    aa.CASH_ID                                                  AS ABYS_CASH_ID,
    aa.RECEIPT_SERIAL                                           AS ABYS_RECEIPT_SERIAL,
    aa.RECEIPT_NUMBER                                           AS ABYS_RECEIPT_NUMBER,
    aa.ANALYSIS_ACCOUNT_ID                                      AS ABYS_ANALYSIS_ACCOUNT_ID,
    aa.VERSION                                                  AS ABYS_VERSION,
    aa.TRANSACTION_CODE                                         AS ABYS_TRANSACTION_CODE,
    aa.CREATED_USER_ID                                          AS ABYS_CREATED_USER_ID,
    aa.UPDATED_USER_ID                                          AS ABYS_UPDATED_USER_ID,
    aa.READING_ID                                               AS ABYS_READING_ID

FROM SMS.CS_ACCOUNT_ADD aa
LEFT JOIN SMS.CS_AGREEMENT agr
       ON agr.ID = aa.AGREEMENT_ID
LEFT JOIN SMS.CS_REGISTER reg
       ON reg.ID = agr.BENEFITED_REGISTER_ID
;

CREATE UNIQUE INDEX MIGRATION.UX_LS_SPEFEE_ABYS_ID
    ON MIGRATION.LS_SPEFEE (ABYS_ID) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IX_LS_SPEFEE_AGR
    ON MIGRATION.LS_SPEFEE (ABYS_AGREEMENT_ID) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IX_LS_SPEFEE_ACC
    ON MIGRATION.LS_SPEFEE (ABYS_ACCOUNT_ID) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IX_LS_SPEFEE_READ
    ON MIGRATION.LS_SPEFEE (READING_ID) NOLOGGING PARALLEL 4;

ALTER INDEX MIGRATION.UX_LS_SPEFEE_ABYS_ID NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_SPEFEE_AGR     NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_SPEFEE_ACC     NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_SPEFEE_READ    NOPARALLEL;

EXEC DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_SPEFEE');
