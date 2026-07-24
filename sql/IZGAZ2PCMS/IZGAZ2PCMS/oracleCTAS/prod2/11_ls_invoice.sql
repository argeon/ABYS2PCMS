-- =============================================================================
-- prod2 / 11 — LS_INVOICE (energy LS_005_01_INVOICE kolon/tip yakin)
-- Onkosul: 10_stg_inv_acc_inc.sql
-- LREF = ABYS_ACTION_ID = CS_ACCOUNT_ACTION.ID (571 IDENTITY_INSERT)
-- Anahtarlar NUMBER(12)/NUMBER(3)/NUMBER(1) — izgazMGR TRY_CAST azaltma
-- DOP: 52 | Sonraki: 12_ls_invlines.sql
-- =============================================================================

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM ALL_TABLES
   WHERE OWNER = 'MIGRATION' AND TABLE_NAME = 'STG_INV_ACC_INC';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20010, 'STG_INV_ACC_INC yok. Once 10_stg_inv_acc_inc.sql');
  END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_INVOICE PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE MIGRATION.LS_INVOICE
NOLOGGING
PARALLEL 52
AS
SELECT /*+ PARALLEL(52) FULL(aa) FULL(acc) FULL(av) */

    CAST(aa.ID AS NUMBER(12))                                     AS LREF,
    CAST(aa.ID AS NUMBER(12))                                     AS ABYS_ACTION_ID,
    CAST(acc.ID AS NUMBER(12))                                    AS ABYS_ACCOUNT_ID,
    CAST(aa.ACTION_TYPE_ID AS NUMBER(10))                         AS ABYS_ACTION_TYPE_ID,
    CAST(acc.ACCRUE_TYPE_ID AS NUMBER(10))                        AS ABYS_ACCRUE_TYPE_ID,
    CAST(acc.REGISTER_ID AS NUMBER(12))                           AS ABYS_REGISTER_ID,
    CAST(acc.AGREEMENT_ID AS NUMBER(12))                          AS ABYS_AGREEMENT_ID,
    CAST(acc.INSTALLATION_ID AS NUMBER(12))                       AS ABYS_INSTALLATION_ID,
    CAST(acc.METER_ID AS NUMBER(12))                              AS ABYS_METER_ID,
    CAST(acc.AREA_ID AS NUMBER(12))                               AS ABYS_AREA_ID,
    CAST(acc.PROJECT_ID AS NUMBER(12))                            AS ABYS_PROJECT_ID,
    CAST(acc.TARIFF_TYPE_ID AS NUMBER(10))                        AS ABYS_TARIFF_TYPE_ID,
    CAST(acc.SKB_TARIFF_TYPE_ID AS NUMBER(10))                    AS ABYS_SKB_TARIFF_TYPE_ID,
    CAST(acc.SUBSCRIBER_TYPE_ID AS NUMBER(10))                    AS ABYS_SUBSCRIBER_TYPE_ID,
    acc.READING_DATE                                              AS ABYS_READING_DATE,
    CAST(acc.IS_E_BILL AS NUMBER(1))                              AS ABYS_IS_E_BILL,
    CAST(acc.IS_FPS AS NUMBER(1))                                 AS ABYS_IS_FPS,
    CAST(acc.DO_DISCHARGE AS NUMBER(1))                           AS ABYS_DO_DISCHARGE,
    CAST(acc.INSTALLMENT_ID AS NUMBER(12))                        AS ABYS_INSTALLMENT_ID,
    CAST(acc.GROUP_ACCOUNT_ID AS NUMBER(12))                      AS ABYS_GROUP_ACCOUNT_ID,
    CAST(aa.BILL_TYPE_ID AS NUMBER(10))                           AS ABYS_BILL_TYPE_ID,
    aa.BILL_SERIAL                                                AS ABYS_BILL_SERIAL,
    CAST(aa.BILL_ORDER_NUMBER AS NUMBER(12))                      AS ABYS_BILL_ORDER_NUMBER,
    aa.BILL_NUMBER                                                AS ABYS_BILL_NUMBER,
    CAST(aa.CONSUMPTION AS NUMBER(18,6))                          AS ABYS_CONSUMPTION,
    CAST(aa.M3 AS NUMBER(18,6))                                   AS ABYS_M3,
    CAST(aa.KWH AS NUMBER(18,6))                                  AS ABYS_KWH,
    CAST(aa.CUSTOMER_BILL_TYPE AS NUMBER(10))                     AS ABYS_CUSTOMER_BILL_TYPE,
    CAST(aa.REF_DEPOSIT_ACCOUNT_ID AS NUMBER(12))                 AS ABYS_REF_DEPOSIT_ACCOUNT_ID,
    CAST(aa.REF_DEPOSIT_ACCOUNT_ACTION_ID AS NUMBER(12))          AS ABYS_REF_DEP_ACC_ACTION_ID,
    CAST(aa.POOL_ID AS NUMBER(12))                                AS ABYS_POOL_ID,
    CAST(aa.CREATED_USER_ID AS NUMBER(12))                        AS ABYS_CREATED_USER_ID,
    CAST(aa.UPDATED_USER_ID AS NUMBER(12))                        AS ABYS_UPDATED_USER_ID,
    CAST(aa.VERSION AS NUMBER(10))                                AS ABYS_VERSION,
    CAST(acc.ACCRUE_TYPE_ID AS NUMBER(10))                        AS TRNSACTION_TYPE_ID,

    CAST(0 AS NUMBER(3))                                          AS IOCODE,

    CAST(SUBSTR(aa.BILL_SERIAL || TO_CHAR(aa.BILL_ORDER_NUMBER), 1, 45) AS VARCHAR2(45)) AS FICHENO,

    CASE
      WHEN EXTRACT(YEAR FROM aa.ACTION_DATE) < 1753
      THEN ADD_MONTHS(aa.ACTION_DATE, 24000)
      ELSE aa.ACTION_DATE
    END                                                           AS DATE_,

    acc.EXPIRY_DATE                                               AS DUEDATE,

    CAST(
      CASE
        WHEN NVL(av.HAS_GAZ, 0) = 0 AND NVL(av.HAS_GUV, 0) > 0 THEN 109
        WHEN acc.ACCRUE_TYPE_ID = 443 THEN 121
        WHEN aa.ACTION_TYPE_ID IN (3, 10, 41) THEN 93
        ELSE 119
      END AS NUMBER(3)
    )                                                             AS TYPE,

    CAST(acc.REGISTER_ID AS NUMBER(12))                           AS CLIENTREF,

    CAST(COALESCE(av.TOTAL_EXCL_TAX, 0) AS NUMBER(18,3))          AS TLTOTAL,
    CAST(160 AS NUMBER(10))                                       AS CURID,
    CAST(COALESCE(av.TOTAL_EXCL_TAX, 0) AS NUMBER(18,3))          AS CURTOTAL,

    CAST(acc.ACCRUE_TYPE_ID AS NUMBER(10))                        AS ACCRUE_TYPE_ID,

    CAST(0 AS NUMBER(1))                                          AS CANCELED,
    CAST(acc.AGREEMENT_ID AS NUMBER(12))                          AS OWNERREF,
    CAST(91 AS NUMBER(3))                                         AS OWNERTYPE,
    CAST(NULL AS NUMBER(10))                                      AS LOGOREF,

    CAST(COALESCE(av.TOTAL_TAX, 0)      AS NUMBER(18,3))          AS TAX,
    CAST(0 AS NUMBER(18,3))                                       AS DV,
    CAST(COALESCE(av.PAYABLE_TOTAL, 0)  AS NUMBER(18,3))          AS GRANDTOTAL,
    CAST(NVL(aa.BILL_PRINT_NUMBER, 0)   AS NUMBER(10))            AS PRINTCOUNT,
    CAST(COALESCE(av.PAYABLE_TOTAL, 0)  AS NUMBER(18,3))          AS PAYABLETOTAL,

    CAST(r.READING_ID AS NUMBER(12))                              AS READ_TRANSREF,
    CAST(NULL AS NUMBER(18,6))                                    AS INTERESTRATE,

    CAST(COALESCE(av.GAS_OPEN_FEE, 0)     AS NUMBER(18,3))        AS gas_open_fee,
    CAST(0 AS NUMBER(18,3))                                       AS detach_attach_fee,
    CAST(0 AS NUMBER(18,3))                                       AS test_fee,
    CAST(COALESCE(av.SPEC_SERV_FEE, 0)    AS NUMBER(18,3))        AS spec_serv_fee,
    CAST(0 AS NUMBER(18,3))                                       AS fixed_fee,
    CAST(COALESCE(av.EXPEND_FEE, 0)       AS NUMBER(18,3))        AS expend_fee,
    CAST(COALESCE(av.DEFAULT_FINE, 0)     AS NUMBER(18,3))        AS DEFAULT_FINE,
    CAST(COALESCE(av.DEFAULT_FINE_TAX, 0) AS NUMBER(18,3))        AS DEFAULT_FINETAX,

    CAST(acc.INSTALLATION_ID AS NUMBER(19))                       AS FITNO,
    CAST(NULL AS NUMBER(10))                                      AS CHEQUEREF,

    CAST(aa.CREATED_TIMESTAMP AS DATE)                            AS ADDDATE,
    CAST(CASE WHEN aa.CREATED_USER_ID IS NULL THEN NULL
              ELSE aa.CREATED_USER_ID + 10000 END AS NUMBER(10))  AS ADDUSER,
    CAST(aa.UPDATED_TIMESTAMP AS DATE)                            AS UPDDATE,
    CAST(CASE WHEN aa.UPDATED_USER_ID IS NULL THEN NULL
              ELSE aa.UPDATED_USER_ID + 10000 END AS NUMBER(10))  AS UPDUSER,

    CAST(aa.LEGAL_PROCEEDING_ID AS NUMBER(12))                    AS LAWDETAILREF,
    CAST(aa.BANK_ID AS NUMBER(12))                                AS BANKREF,
    CAST(NULL AS VARCHAR2(20))                                    AS CUSTBNK_ACC,
    CAST(NULL AS NUMBER(10))                                      AS BANK_STAT,
    CAST(0 AS NUMBER(1))                                          AS BANK_CANCELLED,
    CAST(SUBSTR(aa.BANK_RECEIPT_NUMBER, 1, 50) AS VARCHAR2(50))   AS BANK_RECORD_REF,

    CAST(COALESCE(av.ILLEGAL_USE_FEE, 0) AS NUMBER(18,3))         AS illegal_use_fee,

    CAST(NULL AS NUMBER(10))                                      AS LOGO_FIRMNR,
    CAST(NULL AS NUMBER(10))                                      AS LOGO_FICHEREF,
    CAST(NULL AS VARCHAR2(100))                                   AS LOGO_FICHENO,
    CAST(COALESCE(av.DISCOUNT_ADDITION, 0) AS NUMBER(18,3))       AS discount_addition,

    CAST(NULL AS NUMBER(12))                                      AS RETURN_SOURCE_INVREF,
    CAST(NULL AS NUMBER(12))                                      AS RETURN_TARGET_INVREF,
    CAST(0 AS NUMBER(1))                                          AS CLOSED,
    CAST(NULL AS VARCHAR2(50))                                    AS CCCONFIRMCODE,
    CAST(NULL AS NUMBER(10))                                      AS BANKACCREF,
    CAST(NULL AS NUMBER(10))                                      AS XTYPE,
    CAST(acc.TARIFF_TYPE_ID AS NUMBER(10))                        AS BN_TYPE,
    CAST(acc.INSTALLATION_ID AS NUMBER(12))                       AS OLOC_ID,
    CAST(acc.ID AS NUMBER(12))                                    AS OLREF,
    CAST(NULL AS DATE)                                            AS LASTPAIDDATE,
    CAST(0 AS NUMBER(1))                                          AS IS_DUPLICATE_PAYMENT,
    CAST(NULL AS NUMBER(10))                                      AS PRJ_INV_REF,
    CAST(CASE WHEN aa.LEGAL_PROCEEDING_ID IS NOT NULL
              THEN 1 ELSE 0 END AS NUMBER(1))                     AS IS_LAW,
    CAST(0 AS NUMBER(1))                                          AS IsSendInvoice,
    CAST(0 AS NUMBER(1))                                          AS IsApproveInvoice,
    CAST(SUBSTR(aa.ARCHIVE_NUMBER, 1, 100) AS VARCHAR2(100))      AS SuccessCode,
    CAST(SUBSTR(aa.ARCHIVE_NUMBER, 1, 100) AS VARCHAR2(100))      AS ETTN,
    CAST(NULL AS NUMBER(10))                                      AS ArchiveNo,
    CAST(SUBSTR(aa.BILL_SERIAL, 1, 5) AS VARCHAR2(5))             AS InvPreName,
    CAST(0 AS NUMBER(1))                                          AS IsBuyukSanayiFatura,
    CAST(NULL AS VARCHAR2(400))                                   AS InvoiceReturnMessage,
    CAST(0 AS NUMBER(1))                                          AS CancelEArchiveInvoiceIsSend,

    CAST(COALESCE(av.PAYABLE_TOTAL, 0) AS NUMBER(18,3))           AS AMOUNT,

    CAST(aa.ARCHIVE_SEND_STATUS AS NUMBER(10))                    AS ARCHIVE_SEND_STATUS,
    CAST(aa.ARCHIVE_MAIL_SEND_STATUS AS NUMBER(10))               AS ARCHIVE_MAIL_SEND_STATUS,
    aa.ARCHIVE_SEND_DATE,
    aa.ARCHIVE_MAIL_SEND_DATE,
    CAST(acc.PERIOD AS NUMBER(10))                                AS PERIOD,

    CAST(NVL(av.HAS_DISCOUNT, 0) AS NUMBER(1))                    AS HAS_DISCOUNT,
    CAST(COALESCE(av.DISCOUNT_AMOUNT, 0) AS NUMBER(18,3))         AS DISCOUNT_AMOUNT,
    CAST(NULL AS NUMBER(18,3))                                    AS DISCOUNT_REMAIN_AMOUNT,
    CAST(NULL AS NUMBER(18,3))                                    AS DISCOUNT_USED_AMOUNT,

    CAST(NULL AS DATE)                                            AS CANCEL_DATE,
    CAST(NULL AS NUMBER(10))                                      AS CANCEL_REASON_ID,
    CAST(NULL AS NUMBER(10))                                      AS CANCEL_USER_ID,

    CAST(SUBSTR(NVL(aa.DESCRIPTION, acc.DESCRIPTION), 1, 400) AS VARCHAR2(400)) AS DESCRIPTION,
    CAST(aa.INSTALLMENT_ID AS NUMBER(12))                         AS INSTALLMENT_PLAN_REF,

    CAST(NULL AS NUMBER(18,3))                                    AS TAX_TEVKIFAT,
    CAST(NULL AS NUMBER(18,6))                                    AS Qmin,
    CAST(NULL AS NUMBER(18,6))                                    AS Qmax,
    CAST(NULL AS DATE)                                            AS ARCHIVE_CANCEL_DATE,
    CAST(NULL AS DATE)                                            AS ARCHIVE_LAST_PROCESS_DATE,

    /* energy bridge: 571 ABYS_ID = ABYS_ACTION_ID */
    CAST(aa.ID AS NUMBER(12))                                     AS ABYS_ID

FROM SMS.CS_ACCOUNT_ACTION aa
JOIN SMS.CS_ACCOUNT acc
  ON acc.ID = aa.ACCOUNT_ID
LEFT JOIN (
    SELECT ACCOUNT_ID, MAX(ID) AS READING_ID
    FROM SMS.CS_READING
    GROUP BY ACCOUNT_ID
) r ON r.ACCOUNT_ID = acc.ID
LEFT JOIN MIGRATION.STG_INV_ACC_INC av
  ON av.ACA_ID = aa.ID
WHERE aa.ACTION_TYPE_ID IN (1, 3, 10, 41)
  AND NVL(acc.ACCRUE_TYPE_ID, -1) <> 14
;

CREATE UNIQUE INDEX MIGRATION.IX_LS_INV_LREF ON MIGRATION.LS_INVOICE (LREF) PARALLEL 52 NOLOGGING;
CREATE UNIQUE INDEX MIGRATION.IX_LS_INV_ABYS_ACT ON MIGRATION.LS_INVOICE (ABYS_ACTION_ID) PARALLEL 52 NOLOGGING;
CREATE INDEX MIGRATION.IX_LS_INV_AGR ON MIGRATION.LS_INVOICE (ABYS_AGREEMENT_ID) PARALLEL 52 NOLOGGING;
CREATE INDEX MIGRATION.IX_LS_INV_AGR_ACT ON MIGRATION.LS_INVOICE (ABYS_AGREEMENT_ID, ABYS_ACTION_ID) PARALLEL 52 NOLOGGING;
CREATE INDEX MIGRATION.IX_LS_INV_ABYS_ACC ON MIGRATION.LS_INVOICE (ABYS_ACCOUNT_ID) PARALLEL 52 NOLOGGING;

ALTER INDEX MIGRATION.IX_LS_INV_LREF NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_INV_ABYS_ACT NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_INV_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_INV_AGR_ACT NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_INV_ABYS_ACC NOPARALLEL;

ALTER TABLE MIGRATION.LS_INVOICE NOPARALLEL LOGGING;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_INVOICE', degree => 32); END;
/

-- Soft gate
SELECT
  (SELECT COUNT(*) FROM SMS.CS_ACCOUNT_ACTION aa
     JOIN SMS.CS_ACCOUNT a ON a.ID = aa.ACCOUNT_ID
    WHERE aa.ACTION_TYPE_ID IN (1, 3, 10, 41) AND NVL(a.ACCRUE_TYPE_ID, -1) <> 14) AS SRC_CNT,
  (SELECT COUNT(*) FROM MIGRATION.LS_INVOICE) AS TGT_CNT,
  (SELECT SUM(CASE WHEN LREF <> ABYS_ACTION_ID THEN 1 ELSE 0 END) FROM MIGRATION.LS_INVOICE) AS BAD_LREF
FROM DUAL;

PROMPT ========== 11 LS_INVOICE OK ==========
/