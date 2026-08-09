-- =============================================================================
-- oracleCTAS3007 / 14b — LS_DEBT_PAYTRANS yeniden (O33 sonrası)
-- Onkosul: O11 + O32 + O33 (+ O34 tercih)
-- Amac: CLOSED faturalarda PAID=PAYABLETOTAL; BANKREF/LPD/XTYPE fatura ile hizalı
-- Dump → izgazMGR LS_DEBT_PAYTRANS (Energy 575)
-- =============================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM ALL_TABLES
   WHERE OWNER = 'MIGRATION' AND TABLE_NAME = 'LS_INVOICE';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20014, 'LS_INVOICE yok.');
  END IF;
  BEGIN
    MIGRATION.P_MIG_CTAS_LOG('O14b', 'debt_paytrans_rebuild', 'START', NULL,
      'after O33 CLOSE/BANK');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
/

BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_DEBT_PAYTRANS PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/

CREATE TABLE MIGRATION.LS_DEBT_PAYTRANS
NOLOGGING
PARALLEL 56
AS
SELECT /*+ PARALLEL(56) */
    CAST(inv.LREF AS NUMBER(12))                                  AS INVOICEREF,
    CAST(NULL AS NUMBER(12))                                      AS INVLINEREF,
    inv.DATE_,
    CAST(inv.TYPE AS NUMBER(3))                                   AS TYPE,
    CAST(inv.CLIENTREF AS NUMBER(12))                             AS CLIENTREF,
    CAST(NVL(inv.OWNERTYPE, 91) AS NUMBER(3))                     AS CLIENT_TYPE,
    CAST(0 AS NUMBER(3))                                          AS IOCODE,
    /* LS_001: TLTOTAL=KDV haric; GRANDTOTAL=KDV dahil (~TL+TAX; 109 ~TL+DV) */
    CAST(inv.TLTOTAL AS NUMBER(18,3))                             AS TLTOTAL,
    /* Pilot: kapalı → PAID dolu */
    CAST(CASE
           WHEN NVL(inv.CLOSED, 0) = 1 THEN inv.PAYABLETOTAL
           WHEN NVL(d.CLOSED, 0) = 1 THEN inv.PAYABLETOTAL
           WHEN NVL(d.PAID_AMT, 0) > 0.01
                AND NVL(d.PAID_AMT, 0) + 0.01 >= NVL(inv.PAYABLETOTAL, 0)
             THEN inv.PAYABLETOTAL
           WHEN NVL(d.PAID_AMT, 0) > 0.01 THEN d.PAID_AMT
           ELSE 0
         END AS NUMBER(18,3))                                     AS PAID,
    inv.DUEDATE,
    CAST(174 AS NUMBER(10))                                       AS PAYTYPE,
    CAST(NVL(inv.CURID, 160) AS NUMBER(5))                        AS CURID,
    CAST(1 AS NUMBER(18,6))                                       AS CURRATE,
    CAST(inv.CURTOTAL AS NUMBER(18,3))                            AS CURTOTAL,
    CAST(NULL AS NUMBER(12))                                      AS CROSSREF,
    CAST(113 AS NUMBER(10))                                       AS TRANSTYPE,
    CAST(NVL(inv.CANCELED, 0) AS NUMBER(1))                       AS CANCELED,
    CAST(NULL AS NUMBER(12))                                      AS AGRPAYLINEREF,
    CAST(NULL AS NUMBER(10))                                      AS LOGOREF,
    CAST(NVL(inv.TAX, 0) AS NUMBER(18,3))                         AS TAX,
    CAST(inv.GRANDTOTAL AS NUMBER(18,3))                          AS GRANDTOTAL,
    CAST(103 AS NUMBER(10))                                       AS LINETYPE,
    CAST(0 AS NUMBER(10))                                         AS INST_NR,
    CAST(NVL(inv.DV, 0) AS NUMBER(18,3))                          AS DV,
    CAST(inv.PAYABLETOTAL AS NUMBER(18,3))                        AS PAYABLETOTAL,
    CAST(0 AS NUMBER(12))                                         AS EXPENDINVREF,
    CAST(0 AS NUMBER(10))                                         AS CALC_FINE,
    CAST(NULL AS NUMBER(12))                                      AS CERTLINKREF,
    inv.ADDDATE,
    CAST(inv.ADDUSER AS NUMBER(10))                               AS ADDUSER,
    CAST(0 AS NUMBER(10))                                         AS CANCELLATIONPAYMENT,
    CAST(inv.BANKREF AS NUMBER(12))                               AS BANKREF,
    CAST(NULL AS NUMBER(12))                                      AS BANKACCREF,
    CAST(inv.BN_TYPE AS NUMBER(10))                               AS BN_TYPE,
    CAST(NULL AS NUMBER(12))                                      AS PROJECTLINEREF,
    CAST(0 AS NUMBER(1))                                          AS ISDVFREE,
    CAST(NVL(inv.XTYPE, 1) AS NUMBER(10))                         AS XTYPE,
    CAST(SUBSTR(inv.BANK_RECORD_REF, 1, 50) AS VARCHAR2(50))      AS BANK_RECORD_REF,
    COALESCE(d.LASTPAIDDATE, inv.LASTPAIDDATE)                    AS LASTPAIDDATE,
    CAST(NVL(inv.IS_LAW, 0) AS NUMBER(1))                         AS IS_LAW,
    CAST(NVL(inv.CURID, 160) AS NUMBER(5))                        AS PAYCURID,
    CAST(NVL(inv.ABYS_ID, inv.ABYS_ACTION_ID) AS NUMBER(12))      AS ABYS_ID,
    CAST(inv.ABYS_ACCOUNT_ID AS NUMBER(12))                       AS ABYS_ACCOUNT_ID,
    CAST(inv.ABYS_ACTION_TYPE_ID AS NUMBER(10))                   AS ABYS_ACTION_TYPE_ID,
    CAST(inv.ABYS_ACCRUE_TYPE_ID AS NUMBER(10))                   AS ABYS_ACCRUE_TYPE_ID,
    CAST(inv.ABYS_REGISTER_ID AS NUMBER(12))                      AS ABYS_REGISTER_ID,
    CAST(inv.ABYS_AGREEMENT_ID AS NUMBER(12))                     AS ABYS_AGREEMENT_ID,
    CAST(inv.LREF AS NUMBER(12))                                  AS ABYS_INVOICE_LREF,
    CAST(inv.ADDUSER AS NUMBER(10))                               AS ABYS_ADDUSER,
    CAST(inv.UPDUSER AS NUMBER(10))                               AS ABYS_UPDUSER
FROM MIGRATION.LS_INVOICE inv
LEFT JOIN MIGRATION.LS_OV_DEBT_PAID_UPD d ON d.MAIN_LREF = inv.LREF
WHERE NVL(inv.IOCODE, 0) = 0;

CREATE INDEX MIGRATION.IX_LS_DEBT_PT_INV ON MIGRATION.LS_DEBT_PAYTRANS (INVOICEREF) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_LS_DEBT_PT_AGR ON MIGRATION.LS_DEBT_PAYTRANS (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_LS_DEBT_PT_ABYS ON MIGRATION.LS_DEBT_PAYTRANS (ABYS_ID) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_LS_DEBT_PT_INV NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_DEBT_PT_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_DEBT_PT_ABYS NOPARALLEL;
ALTER TABLE MIGRATION.LS_DEBT_PAYTRANS NOPARALLEL LOGGING;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_DEBT_PAYTRANS', degree => 40); END;
/

DECLARE
  n NUMBER; n_paid NUMBER;
BEGIN
  SELECT COUNT(*), COUNT(CASE WHEN NVL(PAID,0) > 0.01 THEN 1 END)
    INTO n, n_paid FROM MIGRATION.LS_DEBT_PAYTRANS;
  MIGRATION.P_MIG_CTAS_LOG('O14b', 'debt_paytrans_rebuild', 'OK', n,
    'debt_pt=' || n || ' paid_gt0=' || n_paid);
  DBMS_OUTPUT.PUT_LINE('========== O14b LS_DEBT_PAYTRANS REBUILD OK | n='
    || n || ' paid=' || n_paid || ' ==========');
END;
/
