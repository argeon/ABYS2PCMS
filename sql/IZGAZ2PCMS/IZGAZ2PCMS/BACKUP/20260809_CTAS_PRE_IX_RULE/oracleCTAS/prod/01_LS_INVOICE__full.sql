-- =============================================================================
-- LS_INVOICE CTAS  |  ADIM 1 — Borc faturasi kokü
-- Kaynak : SMS | Hedef schema: MIGRATION | Oracle 11.2
-- Pipeline: MIGRATION.LS_INVOICE → izgazMGR.dbo.LS_INVOICE → energy (571)
--
-- LREF / ABYS_ACTION_ID = CS_ACCOUNT_ACTION.ID  (571 IDENTITY_INSERT ile ayni)
-- ABYS_ACCOUNT_ID       = CS_ACCOUNT.ID
-- Grain : ACTION_TYPE_ID IN (1,3,10,41), ACCRUE_TYPE_ID <> 14
-- Tutar : CS_ACCOUNT_INCOME.AMOUNT (stage aggregate)
--
-- MOD  : FULL (tum sozlesmeler, ACCRUE_TYPE_ID <> 14)
-- Pilot: oracleCTAS/LS_INVOICE.sql + MIG_PARAM_seed.sql (DOKUNMA)
--
-- Sonraki adimlar (bu dosyada YOK):
--   2) LS_INVLINES CTAS
--   3) energy: dump → 571 → 581/588 → 575 borç PAYTRANS
--   4a) oracleCTAS/LS_EKSILTEN_OVERLAY.sql + 590 energy apply (TAM IADE + KISMI)
--   5) tahsilat overlay (IOCODE=1 PAYTRANS + CROSSREF + PAID/CLOSED)
-- =============================================================================

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;

-- =============================================================================
-- 00. MIG_PARAM — FULL: bos tablo (AGR filtresi YOK)
-- =============================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.MIG_PARAM PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE MIGRATION.MIG_PARAM (
  REG_ID NUMBER(12),
  AGR_ID NUMBER(12)
);
-- Bos birak: AGREEMENT_ID IN (MIG_PARAM) filtreleri asagida KALDIRILDI.
COMMIT;

-- =============================================================================
-- STAGE 1: CS_ACCOUNT_INCOME aggregate + fee pivot
-- =============================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.STG_INV_ACC_INC PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE MIGRATION.STG_INV_ACC_INC NOLOGGING PARALLEL 8 AS
SELECT /*+ FULL(aca) FULL(ai) PARALLEL(8) */
    aca.ACCOUNT_ID,
    aca.ID                                                              AS ACA_ID,

    SUM(CASE WHEN ai.INCOME_ID IN (939, 7658)  THEN ai.AMOUNT END)      AS EXPEND_FEE,
    SUM(CASE WHEN ai.INCOME_ID NOT IN (169, 60) THEN ai.AMOUNT END)     AS TOTAL_EXCL_TAX,
    SUM(CASE WHEN ai.INCOME_ID IN (169, 60)    THEN ai.AMOUNT END)      AS TOTAL_TAX,
    SUM(ai.AMOUNT)                                                      AS PAYABLE_TOTAL,

    SUM(CASE WHEN ai.INCOME_ID = 1861 THEN ai.AMOUNT END)               AS GAS_OPEN_FEE,
    SUM(CASE WHEN ai.INCOME_ID = 1864 THEN ai.AMOUNT END)               AS DEFAULT_FINE,
    SUM(CASE WHEN ai.INCOME_ID = 1905 THEN ai.AMOUNT END)               AS DEFAULT_FINE_TAX,
    SUM(CASE WHEN ai.INCOME_ID = 1902 THEN ai.AMOUNT END)               AS ILLEGAL_USE_FEE,
    SUM(CASE WHEN ai.INCOME_ID = 100  THEN ai.AMOUNT END)               AS DISCOUNT_ADDITION,
    SUM(CASE WHEN ai.INCOME_ID IN
            (2981, 572, 938, 23033, 573, 23034, 23031, 23032, 2982,
             576, 574, 3251, 12531, 579, 47, 578, 581, 575, 7709,
             577, 7504, 2521, 7528, 7464, 2847, 2446, 2649, 2520,
             7408, 2591, 7496, 2583, 3067)
         THEN ai.AMOUNT END)                                            AS SPEC_SERV_FEE,

    SUM(CASE WHEN ai.INCOME_ID IN (939, 7658) THEN 1 ELSE 0 END)        AS HAS_GAZ,
    SUM(CASE WHEN ai.INCOME_ID IN
            (162, 163, 164, 165, 1936, 3198, 3199,
             7649, 7650, 7651, 7652, 12531, 23032)
         THEN 1 ELSE 0 END)                                             AS HAS_GUV,
    MAX(CASE WHEN NVL(ai.IS_DISCOUNT, 0) = 1 THEN 1 ELSE 0 END)         AS HAS_DISCOUNT,
    SUM(CASE WHEN NVL(ai.IS_DISCOUNT, 0) = 1 THEN ABS(ai.AMOUNT) ELSE 0 END) AS DISCOUNT_AMOUNT

FROM SMS.CS_ACCOUNT_ACTION aca
JOIN SMS.CS_ACCOUNT a ON a.ID = aca.ACCOUNT_ID
LEFT JOIN SMS.CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = aca.ID
WHERE aca.ACTION_TYPE_ID IN (1, 3, 10, 41)
  AND NVL(a.ACCRUE_TYPE_ID, -1) <> 14
GROUP BY aca.ACCOUNT_ID, aca.ID;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'STG_INV_ACC_INC', degree => 8); END;
/

CREATE UNIQUE INDEX MIGRATION.IX_STG_INV_ACC_INC ON MIGRATION.STG_INV_ACC_INC (ACA_ID);

-- =============================================================================
-- MAIN: LS_INVOICE
-- LREF = aa.ID (= ABYS_ACTION_ID) — 571 ile birebir
-- =============================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_INVOICE PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE MIGRATION.LS_INVOICE
NOLOGGING
PARALLEL 8
AS
SELECT /*+ PARALLEL(8) FULL(aa) FULL(acc) FULL(av) */

    /* --- kimlik: 571 LREF = ABYS_ACTION_ID --- */
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
    acc.IS_E_BILL                                                 AS ABYS_IS_E_BILL,
    acc.IS_FPS                                                    AS ABYS_IS_FPS,
    acc.DO_DISCHARGE                                              AS ABYS_DO_DISCHARGE,
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

    aa.BILL_SERIAL || TO_CHAR(aa.BILL_ORDER_NUMBER)               AS FICHENO,

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

    acc.REGISTER_ID                                               AS CLIENTREF,

    CAST(COALESCE(av.TOTAL_EXCL_TAX, 0) AS NUMBER(18,3))          AS TLTOTAL,
    CAST(160 AS NUMBER(10))                                       AS CURID,
    CAST(COALESCE(av.TOTAL_EXCL_TAX, 0) AS NUMBER(18,3))          AS CURTOTAL,

    acc.ACCRUE_TYPE_ID,

    CAST(0 AS NUMBER(1))                                          AS CANCELED,
    acc.AGREEMENT_ID                                              AS OWNERREF,
    CAST(91 AS NUMBER(3))                                         AS OWNERTYPE,
    CAST(NULL AS NUMBER(10))                                      AS LOGOREF,

    CAST(COALESCE(av.TOTAL_TAX, 0)      AS NUMBER(18,3))          AS TAX,
    CAST(0 AS NUMBER(18,3))                                       AS DV,
    CAST(COALESCE(av.PAYABLE_TOTAL, 0)  AS NUMBER(18,3))          AS GRANDTOTAL,
    CAST(NVL(aa.BILL_PRINT_NUMBER, 0)   AS NUMBER(18,3))          AS PRINTCOUNT,
    CAST(COALESCE(av.PAYABLE_TOTAL, 0)  AS NUMBER(18,3))          AS PAYABLETOTAL,

    r.READING_ID                                                  AS READ_TRANSREF,
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

    aa.LEGAL_PROCEEDING_ID                                        AS LAWDETAILREF,
    aa.BANK_ID                                                    AS BANKREF,
    CAST(NULL AS VARCHAR2(4000))                                  AS CUSTBNK_ACC,
    CAST(NULL AS NUMBER(10))                                      AS BANK_STAT,
    CAST(0 AS NUMBER(1))                                          AS BANK_CANCELLED,
    aa.BANK_RECEIPT_NUMBER                                        AS BANK_RECORD_REF,

    CAST(COALESCE(av.ILLEGAL_USE_FEE, 0) AS NUMBER(18,3))         AS illegal_use_fee,

    CAST(NULL AS NUMBER(10))                                      AS LOGO_FIRMNR,
    CAST(NULL AS NUMBER(10))                                      AS LOGO_FICHEREF,
    CAST(NULL AS VARCHAR2(4000))                                  AS LOGO_FICHENO,
    CAST(COALESCE(av.DISCOUNT_ADDITION, 0) AS NUMBER(18,3))       AS discount_addition,

    CAST(NULL AS NUMBER(10))                                      AS RETURN_SOURCE_INVREF,
    CAST(NULL AS NUMBER(10))                                      AS RETURN_TARGET_INVREF,
    CAST(0 AS NUMBER(1))                                          AS CLOSED,
    CAST(NULL AS VARCHAR2(4000))                                  AS CCCONFIRMCODE,
    CAST(NULL AS NUMBER(10))                                      AS BANKACCREF,
    CAST(NULL AS NUMBER(10))                                      AS XTYPE,
    CAST(acc.TARIFF_TYPE_ID AS NUMBER(10))                        AS BN_TYPE,
    acc.INSTALLATION_ID                                           AS OLOC_ID,
    acc.ID                                                        AS OLREF,
    CAST(NULL AS DATE)                                            AS LASTPAIDDATE,
    CAST(0 AS NUMBER(1))                                          AS IS_DUPLICATE_PAYMENT,
    CAST(NULL AS NUMBER(10))                                      AS PRJ_INV_REF,
    CAST(CASE WHEN aa.LEGAL_PROCEEDING_ID IS NOT NULL
              THEN 1 ELSE 0 END AS NUMBER(1))                     AS IS_LAW,
    CAST(0 AS NUMBER(1))                                          AS IsSendInvoice,
    CAST(0 AS NUMBER(1))                                          AS IsApproveInvoice,
    aa.ARCHIVE_NUMBER                                             AS SuccessCode,
    aa.ARCHIVE_NUMBER                                             AS ETTN,
    CAST(NULL AS NUMBER(10))                                      AS ArchiveNo,
    aa.BILL_SERIAL                                                AS InvPreName,
    CAST(0 AS NUMBER(1))                                          AS IsBuyukSanayiFatura,
    CAST(NULL AS VARCHAR2(4000))                                  AS InvoiceReturnMessage,
    CAST(0 AS NUMBER(1))                                          AS CancelEArchiveInvoiceIsSend,

    CAST(COALESCE(av.PAYABLE_TOTAL, 0) AS NUMBER(18,3))           AS AMOUNT,

    aa.ARCHIVE_SEND_STATUS,
    aa.ARCHIVE_MAIL_SEND_STATUS,
    aa.ARCHIVE_SEND_DATE,
    aa.ARCHIVE_MAIL_SEND_DATE,
    acc.PERIOD,

    CAST(NVL(av.HAS_DISCOUNT, 0) AS NUMBER(1))                    AS HAS_DISCOUNT,
    CAST(COALESCE(av.DISCOUNT_AMOUNT, 0) AS NUMBER(18,3))         AS DISCOUNT_AMOUNT,
    CAST(NULL AS NUMBER(18,3))                                    AS DISCOUNT_REMAIN_AMOUNT,
    CAST(NULL AS NUMBER(18,3))                                    AS DISCOUNT_USED_AMOUNT,

    CAST(NULL AS DATE)                                            AS CANCEL_DATE,
    CAST(NULL AS NUMBER(10))                                      AS CANCEL_REASON_ID,
    CAST(NULL AS NUMBER(10))                                      AS CANCEL_USER_ID,

    NVL(aa.DESCRIPTION, acc.DESCRIPTION)                          AS DESCRIPTION,
    aa.INSTALLMENT_ID                                             AS INSTALLMENT_PLAN_REF,

    CAST(NULL AS NUMBER(18,3))                                    AS TAX_TEVKIFAT,
    CAST(NULL AS NUMBER(18,6))                                    AS Qmin,
    CAST(NULL AS NUMBER(18,6))                                    AS Qmax,
    CAST(NULL AS DATE)                                            AS ARCHIVE_CANCEL_DATE,
    CAST(NULL AS DATE)                                            AS ARCHIVE_LAST_PROCESS_DATE

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

CREATE UNIQUE INDEX MIGRATION.IX_LS_INV_LREF ON MIGRATION.LS_INVOICE (LREF);
CREATE UNIQUE INDEX MIGRATION.IX_LS_INV_ABYS_ACT ON MIGRATION.LS_INVOICE (ABYS_ACTION_ID);
CREATE INDEX MIGRATION.IX_LS_INV_ABYS_ACC ON MIGRATION.LS_INVOICE (ABYS_ACCOUNT_ID);
CREATE INDEX MIGRATION.IX_LS_INV_AGR ON MIGRATION.LS_INVOICE (ABYS_AGREEMENT_ID);
CREATE INDEX MIGRATION.IX_LS_INV_DATE ON MIGRATION.LS_INVOICE (DATE_);
CREATE INDEX MIGRATION.IX_LS_INV_ATYPE ON MIGRATION.LS_INVOICE (ABYS_ACTION_TYPE_ID);

ALTER TABLE MIGRATION.LS_INVOICE NOPARALLEL LOGGING;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_INVOICE', degree => 8); END;
/

-- =============================================================================
-- DOGRULAMA (Adim-1 gate)
-- =============================================================================

-- V0: parametre / kapsam
SELECT CASE
         WHEN EXISTS (SELECT 1 FROM MIGRATION.MIG_PARAM WHERE AGR_ID IS NOT NULL)
         THEN 'PILOT_AGR'
         WHEN EXISTS (SELECT 1 FROM MIGRATION.MIG_PARAM WHERE REG_ID IS NOT NULL)
         THEN 'PILOT_REG'
         ELSE 'FULL'
       END AS KAPSAM,
       (SELECT AGR_ID FROM MIGRATION.MIG_PARAM WHERE ROWNUM = 1) AS AGR_ID
FROM DUAL;

-- V1: kaynak action vs hedef (ayni filtre)
SELECT
  (SELECT COUNT(*)
     FROM SMS.CS_ACCOUNT_ACTION aa
     JOIN SMS.CS_ACCOUNT a ON a.ID = aa.ACCOUNT_ID
    WHERE aa.ACTION_TYPE_ID IN (1, 3, 10, 41)
      AND NVL(a.ACCRUE_TYPE_ID, -1) <> 14
      ) AS SRC_CNT,
  (SELECT COUNT(*) FROM MIGRATION.LS_INVOICE) AS TGT_CNT
FROM DUAL;

-- V1b: LREF = ABYS_ACTION_ID (571 uyumu) — BAD_LREF = 0 olmali
SELECT
  COUNT(*) AS SATIR,
  COUNT(DISTINCT LREF) AS DISTINCT_LREF,
  COUNT(DISTINCT ABYS_ACTION_ID) AS DISTINCT_ACTION,
  SUM(CASE WHEN LREF <> ABYS_ACTION_ID THEN 1 ELSE 0 END) AS BAD_LREF
FROM MIGRATION.LS_INVOICE;

-- V2: tutar mutabakati
SELECT
  (SELECT SUM(av.PAYABLE_TOTAL) FROM MIGRATION.STG_INV_ACC_INC av
    WHERE EXISTS (SELECT 1 FROM MIGRATION.LS_INVOICE i WHERE i.ABYS_ACTION_ID = av.ACA_ID)) AS STG_SUM,
  (SELECT SUM(PAYABLETOTAL) FROM MIGRATION.LS_INVOICE) AS INV_SUM
FROM DUAL;

-- V3: TYPE dagilimi
SELECT TYPE, ABYS_ACTION_TYPE_ID, COUNT(*) AS ADET, SUM(GRANDTOTAL) AS TOPLAM
FROM MIGRATION.LS_INVOICE
GROUP BY TYPE, ABYS_ACTION_TYPE_ID
ORDER BY ABYS_ACTION_TYPE_ID, TYPE;

-- V4: income yok (sifir tutar)
SELECT COUNT(*) AS INCOME_YOK
FROM MIGRATION.LS_INVOICE
WHERE GRANDTOTAL = 0 AND TLTOTAL = 0 AND TAX = 0;

-- V5: action tip ozeti
SELECT ABYS_ACTION_TYPE_ID,
       COUNT(*) ADET,
       SUM(GRANDTOTAL) TOPLAM
FROM MIGRATION.LS_INVOICE
GROUP BY ABYS_ACTION_TYPE_ID
ORDER BY ABYS_ACTION_TYPE_ID;

-- Gate ozeti (manuel): SRC_CNT=TGT_CNT, BAD_LREF=0, STG_SUM~INV_SUM
-- Sonraki: LS_INVLINES CTAS → dump → 571/581/575 (578 pilot)
/
