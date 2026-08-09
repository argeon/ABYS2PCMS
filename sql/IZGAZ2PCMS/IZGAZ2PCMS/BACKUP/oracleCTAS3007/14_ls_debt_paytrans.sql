WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- =============================================================================
-- oracleCTAS3007 / 14 — LS_DEBT_PAYTRANS (energy 575 karsiligi — LS_005_01_PAYTRANS IOCODE=0)
-- Onkosul: 11_ls_invoice.sql
-- Kaynak: LS_INVOICE (IOCODE=0 borc faturalari)
-- LREF yok (energy IDENTITY) — bulk insert 575 kolon seti ile
-- INVOICEREF = MAIN.LREF | ABYS_INVOICE_LREF = MAIN.LREF | ABYS_ID = MAIN.ABYS_ID
-- Dump → izgazMGR; energy'de 575 yerine dogrudan INSERT…SELECT mumkun
-- =============================================================================

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
    RAISE_APPLICATION_ERROR(-20014, 'LS_INVOICE yok. Once 11_ls_invoice.sql');
  END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_DEBT_PAYTRANS PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE MIGRATION.LS_DEBT_PAYTRANS
NOLOGGING
PARALLEL 56
AS
SELECT /*+ PARALLEL(56) */
    /* LREF energy IDENTITY — staging'de NULL; isteğe bagli IDENTITY_INSERT icin:
       CAST(inv.LREF AS NUMBER(12)) AS LREF  acilabilir */
    CAST(inv.LREF AS NUMBER(12))                                  AS INVOICEREF,
    CAST(NULL AS NUMBER(12))                                      AS INVLINEREF,
    inv.DATE_,
    CAST(inv.TYPE AS NUMBER(3))                                   AS TYPE,
    CAST(inv.CLIENTREF AS NUMBER(12))                             AS CLIENTREF,
    CAST(NVL(inv.OWNERTYPE, 91) AS NUMBER(3))                     AS CLIENT_TYPE,
    CAST(0 AS NUMBER(3))                                          AS IOCODE,
    /* LS_001: TLTOTAL=KDV haric; GRANDTOTAL=KDV dahil (~TL+TAX; 109 ~TL+DV) */
    CAST(inv.TLTOTAL AS NUMBER(18,3))                             AS TLTOTAL,
    CAST(0 AS NUMBER(18,3))                                       AS PAID,
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
    /* 3007: makbuz/tarih — O33 sonrası dump'ta fatura alanlarından gelir */
    CAST(SUBSTR(inv.BANK_RECORD_REF, 1, 50) AS VARCHAR2(50))      AS BANK_RECORD_REF,
    inv.LASTPAIDDATE                                              AS LASTPAIDDATE,
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
WHERE NVL(inv.IOCODE, 0) = 0
  AND inv.LREF BETWEEN 1 AND 2147483647;

CREATE INDEX MIGRATION.IX_LS_DEBT_PT_INV ON MIGRATION.LS_DEBT_PAYTRANS (INVOICEREF) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_LS_DEBT_PT_AGR ON MIGRATION.LS_DEBT_PAYTRANS (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_LS_DEBT_PT_ABYS ON MIGRATION.LS_DEBT_PAYTRANS (ABYS_ID) PARALLEL 56 NOLOGGING;

ALTER INDEX MIGRATION.IX_LS_DEBT_PT_INV NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_DEBT_PT_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_LS_DEBT_PT_ABYS NOPARALLEL;

ALTER TABLE MIGRATION.LS_DEBT_PAYTRANS NOPARALLEL LOGGING;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_DEBT_PAYTRANS', degree => 40); END;
/

SELECT
  (SELECT COUNT(*) FROM MIGRATION.LS_INVOICE WHERE NVL(IOCODE,0)=0) AS INV_IO0,
  (SELECT COUNT(*) FROM MIGRATION.LS_DEBT_PAYTRANS) AS DEBT_PT
FROM DUAL;

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM MIGRATION.LS_DEBT_PAYTRANS;
  BEGIN
    MIGRATION.P_MIG_CTAS_LOG('O14', 'debt_paytrans', 'OK', n,
      'prefab (final=O14b after CLOSE)');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  DBMS_OUTPUT.PUT_LINE('========== O14 LS_DEBT_PAYTRANS OK | n=' || n
    || ' (O14b rebuild after O33) ==========');
END;
/