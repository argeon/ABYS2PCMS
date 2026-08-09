-- =============================================================================
-- prodREADY / 11 — LS_INVOICE
-- Onkosul: 10_stg_inv_acc_inc.sql
-- LREF = ABYS_ACTION_ID = CS_ACCOUNT_ACTION.ID (571 IDENTITY_INSERT)
-- Tip modeli: kaynak kolonlara SIKI NUMBER(p) CAST YOK (ORA-01438)
--   — orijinal LS_INVOICE.sql ile ayni; energy hizalama: SMALLDT + CURID=160
--   + EXPLAIN + ABYS_ID + INT filtre
-- DOP: FORCE 56 | Sonraki: 12_ls_invlines.sql
-- =============================================================================

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

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
PARALLEL 56
AS
SELECT /*+ PARALLEL(56) FULL(aa) FULL(acc) FULL(av) */

    /* kimlik — CAST yok (kaynak NUMBER); INT filtre asagida */
    aa.ID                                                         AS LREF,
    aa.ID                                                         AS ABYS_ACTION_ID,
    acc.ID                                                        AS ABYS_ACCOUNT_ID,
    aa.ACTION_TYPE_ID                                             AS ABYS_ACTION_TYPE_ID,
    acc.ACCRUE_TYPE_ID                                            AS ABYS_ACCRUE_TYPE_ID,
    acc.REGISTER_ID                                               AS ABYS_REGISTER_ID,
    acc.AGREEMENT_ID                                              AS ABYS_AGREEMENT_ID,
    acc.INSTALLATION_ID                                           AS ABYS_INSTALLATION_ID,
    acc.METER_ID                                                  AS ABYS_METER_ID,
    acc.AREA_ID                                                   AS ABYS_AREA_ID,
    acc.PROJECT_ID                                                AS ABYS_PROJECT_ID,
    acc.TARIFF_TYPE_ID                                            AS ABYS_TARIFF_TYPE_ID,
    acc.SKB_TARIFF_TYPE_ID                                        AS ABYS_SKB_TARIFF_TYPE_ID,
    acc.SUBSCRIBER_TYPE_ID                                        AS ABYS_SUBSCRIBER_TYPE_ID,
    acc.READING_DATE                                              AS ABYS_READING_DATE,
    CASE WHEN NVL(acc.IS_E_BILL, 0) = 0 THEN 0 ELSE 1 END         AS ABYS_IS_E_BILL,
    CASE WHEN NVL(acc.IS_FPS, 0) = 0 THEN 0 ELSE 1 END            AS ABYS_IS_FPS,
    CASE WHEN NVL(acc.DO_DISCHARGE, 0) = 0 THEN 0 ELSE 1 END      AS ABYS_DO_DISCHARGE,
    acc.INSTALLMENT_ID                                            AS ABYS_INSTALLMENT_ID,
    acc.GROUP_ACCOUNT_ID                                          AS ABYS_GROUP_ACCOUNT_ID,
    aa.BILL_TYPE_ID                                               AS ABYS_BILL_TYPE_ID,
    aa.BILL_SERIAL                                                AS ABYS_BILL_SERIAL,
    aa.BILL_ORDER_NUMBER                                          AS ABYS_BILL_ORDER_NUMBER,
    aa.BILL_NUMBER                                                AS ABYS_BILL_NUMBER,
    aa.CONSUMPTION                                                AS ABYS_CONSUMPTION,
    aa.M3                                                         AS ABYS_M3,
    aa.KWH                                                        AS ABYS_KWH,
    aa.CUSTOMER_BILL_TYPE                                         AS ABYS_CUSTOMER_BILL_TYPE,
    aa.REF_DEPOSIT_ACCOUNT_ID                                     AS ABYS_REF_DEPOSIT_ACCOUNT_ID,
    aa.REF_DEPOSIT_ACCOUNT_ACTION_ID                              AS ABYS_REF_DEP_ACC_ACTION_ID,
    aa.POOL_ID                                                    AS ABYS_POOL_ID,
    aa.CREATED_USER_ID                                            AS ABYS_CREATED_USER_ID,
    aa.UPDATED_USER_ID                                            AS ABYS_UPDATED_USER_ID,
    aa.VERSION                                                    AS ABYS_VERSION,
    acc.ACCRUE_TYPE_ID                                            AS TRNSACTION_TYPE_ID,

    CAST(0 AS NUMBER(3))                                          AS IOCODE,

    CAST(SUBSTR(aa.BILL_SERIAL || TO_CHAR(aa.BILL_ORDER_NUMBER), 1, 45) AS VARCHAR2(45)) AS FICHENO,

    /* SMALLDATETIME: 1900-01-01 .. 2079-06-06 (energy FN_SAFE_SMALLDT) */
    CASE
      WHEN aa.ACTION_DATE IS NULL THEN CAST(NULL AS DATE)
      WHEN CASE WHEN EXTRACT(YEAR FROM aa.ACTION_DATE) < 1753
                THEN ADD_MONTHS(aa.ACTION_DATE, 24000) ELSE aa.ACTION_DATE END
           < DATE '1900-01-01' THEN DATE '1900-01-01'
      WHEN CASE WHEN EXTRACT(YEAR FROM aa.ACTION_DATE) < 1753
                THEN ADD_MONTHS(aa.ACTION_DATE, 24000) ELSE aa.ACTION_DATE END
           > DATE '2079-06-06' THEN DATE '2079-06-06'
      ELSE CASE WHEN EXTRACT(YEAR FROM aa.ACTION_DATE) < 1753
                THEN ADD_MONTHS(aa.ACTION_DATE, 24000) ELSE aa.ACTION_DATE END
    END                                                           AS DATE_,

    CASE
      WHEN acc.EXPIRY_DATE IS NULL THEN CAST(NULL AS DATE)
      WHEN CASE WHEN EXTRACT(YEAR FROM acc.EXPIRY_DATE) < 1753
                THEN ADD_MONTHS(acc.EXPIRY_DATE, 24000) ELSE acc.EXPIRY_DATE END
           < DATE '1900-01-01' THEN DATE '1900-01-01'
      WHEN CASE WHEN EXTRACT(YEAR FROM acc.EXPIRY_DATE) < 1753
                THEN ADD_MONTHS(acc.EXPIRY_DATE, 24000) ELSE acc.EXPIRY_DATE END
           > DATE '2079-06-06' THEN DATE '2079-06-06'
      ELSE CASE WHEN EXTRACT(YEAR FROM acc.EXPIRY_DATE) < 1753
                THEN ADD_MONTHS(acc.EXPIRY_DATE, 24000) ELSE acc.EXPIRY_DATE END
    END                                                           AS DUEDATE,

    CAST(
      CASE
        WHEN NVL(av.HAS_GAZ, 0) = 0 AND NVL(av.HAS_GUV, 0) > 0 THEN 109
        WHEN acc.ACCRUE_TYPE_ID = 443 THEN 121
        WHEN aa.ACTION_TYPE_ID IN (3, 10, 41) THEN 93
        ELSE 119
      END AS NUMBER(3)
    )                                                             AS TYPE,

    acc.REGISTER_ID                                               AS CLIENTREF,

    /* tutar: precision CAST yok — ROUND yeter; ORA-01438 riski kaldirildi */
    ROUND(COALESCE(av.TOTAL_EXCL_TAX, 0), 3)                      AS TLTOTAL,
    CAST(160 AS NUMBER(10))                                       AS CURID,
    ROUND(COALESCE(av.TOTAL_EXCL_TAX, 0), 3)                      AS CURTOTAL,

    acc.ACCRUE_TYPE_ID                                            AS ACCRUE_TYPE_ID,

    CAST(NULL AS VARCHAR2(250))                                   AS EXPLAIN,
    CAST(0 AS NUMBER(1))                                          AS CANCELED,
    acc.AGREEMENT_ID                                              AS OWNERREF,
    CAST(91 AS NUMBER(3))                                         AS OWNERTYPE,
    CAST(NULL AS NUMBER(10))                                      AS LOGOREF,

    ROUND(COALESCE(av.TOTAL_TAX, 0), 3)                           AS TAX,
    CAST(0 AS NUMBER(18,3))                                       AS DV,
    ROUND(COALESCE(av.PAYABLE_TOTAL, 0), 3)                       AS GRANDTOTAL,
    NVL(aa.BILL_PRINT_NUMBER, 0)                                  AS PRINTCOUNT,
    ROUND(COALESCE(av.PAYABLE_TOTAL, 0), 3)                       AS PAYABLETOTAL,

    r.READING_ID                                                  AS READ_TRANSREF,
    CAST(NULL AS NUMBER(18,6))                                    AS INTERESTRATE,

    ROUND(COALESCE(av.GAS_OPEN_FEE, 0), 3)                        AS gas_open_fee,
    CAST(0 AS NUMBER(18,3))                                       AS detach_attach_fee,
    CAST(0 AS NUMBER(18,3))                                       AS test_fee,
    ROUND(COALESCE(av.SPEC_SERV_FEE, 0), 3)                       AS spec_serv_fee,
    CAST(0 AS NUMBER(18,3))                                       AS fixed_fee,
    ROUND(COALESCE(av.EXPEND_FEE, 0), 3)                          AS expend_fee,
    ROUND(COALESCE(av.DEFAULT_FINE, 0), 3)                        AS DEFAULT_FINE,
    ROUND(COALESCE(av.DEFAULT_FINE_TAX, 0), 3)                    AS DEFAULT_FINETAX,

    acc.INSTALLATION_ID                                           AS FITNO,
    CAST(NULL AS NUMBER(10))                                      AS CHEQUEREF,

    CASE
      WHEN aa.CREATED_TIMESTAMP IS NULL THEN CAST(NULL AS DATE)
      WHEN CASE WHEN EXTRACT(YEAR FROM aa.CREATED_TIMESTAMP) < 1753
                THEN ADD_MONTHS(aa.CREATED_TIMESTAMP, 24000) ELSE CAST(aa.CREATED_TIMESTAMP AS DATE) END
           < DATE '1900-01-01' THEN DATE '1900-01-01'
      WHEN CASE WHEN EXTRACT(YEAR FROM aa.CREATED_TIMESTAMP) < 1753
                THEN ADD_MONTHS(aa.CREATED_TIMESTAMP, 24000) ELSE CAST(aa.CREATED_TIMESTAMP AS DATE) END
           > DATE '2079-06-06' THEN DATE '2079-06-06'
      ELSE CASE WHEN EXTRACT(YEAR FROM aa.CREATED_TIMESTAMP) < 1753
                THEN ADD_MONTHS(aa.CREATED_TIMESTAMP, 24000) ELSE CAST(aa.CREATED_TIMESTAMP AS DATE) END
    END                                                           AS ADDDATE,
    CASE WHEN aa.CREATED_USER_ID IS NULL THEN NULL
         ELSE aa.CREATED_USER_ID + 10000 END                      AS ADDUSER,
    CASE
      WHEN aa.UPDATED_TIMESTAMP IS NULL THEN CAST(NULL AS DATE)
      WHEN CASE WHEN EXTRACT(YEAR FROM aa.UPDATED_TIMESTAMP) < 1753
                THEN ADD_MONTHS(aa.UPDATED_TIMESTAMP, 24000) ELSE CAST(aa.UPDATED_TIMESTAMP AS DATE) END
           < DATE '1900-01-01' THEN DATE '1900-01-01'
      WHEN CASE WHEN EXTRACT(YEAR FROM aa.UPDATED_TIMESTAMP) < 1753
                THEN ADD_MONTHS(aa.UPDATED_TIMESTAMP, 24000) ELSE CAST(aa.UPDATED_TIMESTAMP AS DATE) END
           > DATE '2079-06-06' THEN DATE '2079-06-06'
      ELSE CASE WHEN EXTRACT(YEAR FROM aa.UPDATED_TIMESTAMP) < 1753
                THEN ADD_MONTHS(aa.UPDATED_TIMESTAMP, 24000) ELSE CAST(aa.UPDATED_TIMESTAMP AS DATE) END
    END                                                           AS UPDDATE,
    CASE WHEN aa.UPDATED_USER_ID IS NULL THEN NULL
         ELSE aa.UPDATED_USER_ID + 10000 END                      AS UPDUSER,

    aa.LEGAL_PROCEEDING_ID                                        AS LAWDETAILREF,
    aa.BANK_ID                                                    AS BANKREF,
    CAST(NULL AS VARCHAR2(20))                                    AS CUSTBNK_ACC,
    CAST(NULL AS NUMBER(10))                                      AS BANK_STAT,
    CAST(0 AS NUMBER(1))                                          AS BANK_CANCELLED,
    CAST(SUBSTR(aa.BANK_RECEIPT_NUMBER, 1, 50) AS VARCHAR2(50))   AS BANK_RECORD_REF,

    ROUND(COALESCE(av.ILLEGAL_USE_FEE, 0), 3)                     AS illegal_use_fee,

    CAST(NULL AS NUMBER(10))                                      AS LOGO_FIRMNR,
    CAST(NULL AS NUMBER(10))                                      AS LOGO_FICHEREF,
    CAST(NULL AS VARCHAR2(100))                                   AS LOGO_FICHENO,
    ROUND(COALESCE(av.DISCOUNT_ADDITION, 0), 3)                   AS discount_addition,

    CAST(NULL AS NUMBER(12))                                      AS RETURN_SOURCE_INVREF,
    CAST(NULL AS NUMBER(12))                                      AS RETURN_TARGET_INVREF,
    CAST(0 AS NUMBER(1))                                          AS CLOSED,
    CAST(NULL AS VARCHAR2(50))                                    AS CCCONFIRMCODE,
    CAST(NULL AS NUMBER(10))                                      AS BANKACCREF,
    CAST(NULL AS NUMBER(10))                                      AS XTYPE,
    acc.TARIFF_TYPE_ID                                            AS BN_TYPE,
    acc.INSTALLATION_ID                                           AS OLOC_ID,
    acc.ID                                                        AS OLREF,
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

    ROUND(COALESCE(av.PAYABLE_TOTAL, 0), 3)                       AS AMOUNT,

    aa.ARCHIVE_SEND_STATUS,
    aa.ARCHIVE_MAIL_SEND_STATUS,
    aa.ARCHIVE_SEND_DATE,
    aa.ARCHIVE_MAIL_SEND_DATE,
    acc.PERIOD,

    CASE WHEN NVL(av.HAS_DISCOUNT, 0) = 0 THEN 0 ELSE 1 END       AS HAS_DISCOUNT,
    ROUND(COALESCE(av.DISCOUNT_AMOUNT, 0), 3)                     AS DISCOUNT_AMOUNT,
    CAST(NULL AS NUMBER(18,3))                                    AS DISCOUNT_REMAIN_AMOUNT,
    CAST(NULL AS NUMBER(18,3))                                    AS DISCOUNT_USED_AMOUNT,

    CAST(NULL AS DATE)                                            AS CANCEL_DATE,
    CAST(NULL AS NUMBER(10))                                      AS CANCEL_REASON_ID,
    CAST(NULL AS NUMBER(10))                                      AS CANCEL_USER_ID,

    CAST(SUBSTR(NVL(aa.DESCRIPTION, acc.DESCRIPTION), 1, 400) AS VARCHAR2(400)) AS DESCRIPTION,
    aa.INSTALLMENT_ID                                             AS INSTALLMENT_PLAN_REF,

    CAST(NULL AS NUMBER(18,3))                                    AS TAX_TEVKIFAT,
    CAST(NULL AS NUMBER(18,6))                                    AS Qmin,
    CAST(NULL AS NUMBER(18,6))                                    AS Qmax,
    CAST(NULL AS DATE)                                            AS ARCHIVE_CANCEL_DATE,
    CAST(NULL AS DATE)                                            AS ARCHIVE_LAST_PROCESS_DATE,

    /* energy bridge: 571 ABYS_ID = ABYS_ACTION_ID */
    aa.ID                                                         AS ABYS_ID

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
  /* RISK: INT tasma — energy IDENTITY_INSERT INT */
  AND aa.ID BETWEEN 1 AND 2147483647
;

CREATE UNIQUE INDEX MIGRATION.IX_LS_INV_LREF ON MIGRATION.LS_INVOICE (LREF) PARALLEL 56 NOLOGGING;
CREATE UNIQUE INDEX MIGRATION.IX_LS_INV_ABYS_ACT ON MIGRATION.LS_INVOICE (ABYS_ACTION_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_LS_INV_AGR ON MIGRATION.LS_INVOICE (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_LS_INV_AGR_ACT ON MIGRATION.LS_INVOICE (ABYS_AGREEMENT_ID, ABYS_ACTION_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_LS_INV_ABYS_ACC ON MIGRATION.LS_INVOICE (ABYS_ACCOUNT_ID) PARALLEL 56 NOLOGGING;

ALTER INDEX MIGRATION.IX_LS_INV_LREF NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_INV_ABYS_ACT NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_INV_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_INV_AGR_ACT NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_INV_ABYS_ACC NOPARALLEL;

ALTER TABLE MIGRATION.LS_INVOICE NOPARALLEL LOGGING;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_INVOICE', degree => 40); END;
/

-- Soft gate + log (src de INT filtre — CTAS ile ayni)
SELECT
  (SELECT COUNT(*) FROM SMS.CS_ACCOUNT_ACTION aa
     JOIN SMS.CS_ACCOUNT a ON a.ID = aa.ACCOUNT_ID
    WHERE aa.ACTION_TYPE_ID IN (1, 3, 10, 41)
      AND NVL(a.ACCRUE_TYPE_ID, -1) <> 14
      AND aa.ID BETWEEN 1 AND 2147483647) AS SRC_CNT,
  (SELECT COUNT(*) FROM MIGRATION.LS_INVOICE) AS TGT_CNT,
  (SELECT SUM(CASE WHEN LREF <> ABYS_ACTION_ID THEN 1 ELSE 0 END) FROM MIGRATION.LS_INVOICE) AS BAD_LREF
FROM DUAL;

DECLARE
  n_tgt NUMBER; n_bad NUMBER; n_src NUMBER;
BEGIN
  SELECT COUNT(*) INTO n_tgt FROM MIGRATION.LS_INVOICE;
  SELECT NVL(SUM(CASE WHEN LREF <> ABYS_ACTION_ID THEN 1 ELSE 0 END),0) INTO n_bad FROM MIGRATION.LS_INVOICE;
  SELECT COUNT(*) INTO n_src FROM SMS.CS_ACCOUNT_ACTION aa
    JOIN SMS.CS_ACCOUNT a ON a.ID = aa.ACCOUNT_ID
   WHERE aa.ACTION_TYPE_ID IN (1, 3, 10, 41)
     AND NVL(a.ACCRUE_TYPE_ID, -1) <> 14
     AND aa.ID BETWEEN 1 AND 2147483647;
  IF n_bad > 0 OR n_src <> n_tgt THEN
    MIGRATION.P_MIG_CTAS_LOG('O11', 'ls_invoice', 'FAIL', n_tgt,
      'src=' || n_src || ' tgt=' || n_tgt || ' bad_lref=' || n_bad);
    RAISE_APPLICATION_ERROR(-20011, 'O11 FAIL src/tgt/bad_lref');
  END IF;
  MIGRATION.P_MIG_CTAS_LOG('O11', 'ls_invoice', 'OK', n_tgt,
    'src=tgt=' || n_tgt || ' bad_lref=0 CURID=160 loose_types');
  DBMS_OUTPUT.PUT_LINE('========== O11 LS_INVOICE OK | cnt=' || n_tgt || ' ==========');
END;
/
