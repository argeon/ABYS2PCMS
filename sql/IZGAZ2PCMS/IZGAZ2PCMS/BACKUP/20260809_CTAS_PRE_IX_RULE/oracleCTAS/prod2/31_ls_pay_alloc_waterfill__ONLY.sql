-- =============================================================================
-- prod2 / 31 — PAY ALLOC WATERFILL ONLY (yuvarlama / over-alloc fix)
-- Ortam : Oracle 11.2 | Schema: MIGRATION | Kaynak: SMS
-- Onkosul: MIGRATION.LS_INVOICE (11) hazir
-- Calistir: sqlplus ... @31_ls_pay_alloc_waterfill__ONLY.sql
--
-- Yeniden uretir:
--   TMP_MIG_ACC, TMP_PAY_CANCEL
--   LS_OV_PAY_ALLOC   (waterfill: PAY_FULL + MAIN_PAYABLE)
--   LS_OV_PAY_PT
--   LS_OV_TAH_INVOICE
--   LS_OV_DEBT_PAID_UPD
--
-- YAPMAZ: CancelInvoices / MAHSUP / 40 log / tam 30 zinciri
-- Sonra: dump bu 4 LS_OV_* → izgazMGR → energy 597 @CLEAN=0 (PAID/PT resync)
-- =============================================================================

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM ALL_TABLES
   WHERE OWNER='MIGRATION' AND TABLE_NAME='LS_INVOICE';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'MIGRATION.LS_INVOICE yok.');
  END IF;
END;
/

-- =============================================================================
-- 0-PRE) Driver tablolar — pilot hesaplar + gecerli iptal seti (tek sefer)
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.TMP_MIG_ACC PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.TMP_MIG_ACC NOLOGGING AS
SELECT a.ID AS ACCOUNT_ID, a.AGREEMENT_ID
FROM SMS.CS_ACCOUNT a
WHERE NVL(a.ACCRUE_TYPE_ID, -1) <> 14;

CREATE UNIQUE INDEX MIGRATION.IX_TMP_MIG_ACC ON MIGRATION.TMP_MIG_ACC (ACCOUNT_ID) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_TMP_MIG_ACC NOPARALLEL;
/
BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION','TMP_MIG_ACC'); END;
/

-- Iptal (R42) eslesen odeme ID'leri — TMP_MIG_ACC kapsamindaki tum hesaplar
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.TMP_PAY_CANCEL PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.TMP_PAY_CANCEL NOLOGGING AS
SELECT DISTINCT pay.ID AS PAY_ID
FROM SMS.CS_ACCOUNT_ACTION pay
JOIN MIGRATION.TMP_MIG_ACC m
  ON m.ACCOUNT_ID = pay.ACCOUNT_ID
JOIN SMS.CS_ACTION_TYPE_PRM atp
  ON atp.ID = pay.ACTION_TYPE_ID AND atp.TYPE = 2
JOIN SMS.CS_ACCOUNT_ACTION can
  ON can.ACCOUNT_ID = pay.ACCOUNT_ID
 AND can.ACTION_TYPE_ID = 9
 AND can.CASH_ID = pay.CASH_ID
 AND can.RECEIPT_NUMBER = pay.RECEIPT_NUMBER
 AND NVL(can.BANK_PAYMENT_DATE, DATE '1900-01-01')
   = NVL(pay.BANK_PAYMENT_DATE, DATE '1900-01-01');

CREATE UNIQUE INDEX MIGRATION.IX_TMP_PAY_CANCEL ON MIGRATION.TMP_PAY_CANCEL (PAY_ID) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_TMP_PAY_CANCEL NOPARALLEL;
/
BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION','TMP_PAY_CANCEL'); END;
/

-- =============================================================================
-- 0) LS_OV_PAY_ALLOC — odeme gelir kirilimi > coklu MAIN
-- Her (PAY, INCOME_ID) icin tek MAIN:
--   ayni ACCOUNT, tip 1/3/10/41, ACTION_DATE<=PAY, ortak INCOME_ID
--   oncelik: tip1 > 3 > 41 > 10, sonra eski tarih, sonra min ID
-- (PAY, MAIN) RAW_ALLOC = SUM(PAY_AMT)
--
-- FIX (2026-07-24) — ornek MAIN 63984619 (kaynak 6.54+8.46=15):
--   Eski: her odeme bagimsiz LEAST(RAW, MAIN_PAYABLE) → 7+10=17, PAID_AMT=16
--         banka ALLOC=10 > PAY_FULL=8
--   Yeni waterfill:
--     1) PAY icinde: SUM(ALLOC) <= PAY_FULL_AMT (aksiyon gelir toplami)
--     2) MAIN icinde (tarih sirasi): SUM(ALLOC) <= MAIN_PAYABLE
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_PAY_ALLOC PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_PAY_ALLOC NOLOGGING AS
WITH pay_inc AS (
    SELECT
        pay.ID                                                   AS PAY_LREF,
        pay.ACCOUNT_ID                                           AS ABYS_ACCOUNT_ID,
        m.AGREEMENT_ID                                           AS ABYS_AGREEMENT_ID,
        pay.ACTION_DATE,
        pi.INCOME_ID,
        /* Income ABS yok — devir (+/-) satırları RAW'ı şişirirdi; pozitifleştirme RAW_ALLOC'ta */
        ROUND(SUM(pi.AMOUNT * pi.STATUS), 2)                     AS PAY_AMT
    FROM SMS.CS_ACCOUNT_ACTION pay
    JOIN MIGRATION.TMP_MIG_ACC m
      ON m.ACCOUNT_ID = pay.ACCOUNT_ID
    JOIN SMS.CS_ACTION_TYPE_PRM atp
      ON atp.ID = pay.ACTION_TYPE_ID
     AND atp.TYPE = 2
    JOIN SMS.CS_ACCOUNT_INCOME pi
      ON pi.ACCOUNT_ACTION_ID = pay.ID
    WHERE pay.ACTION_TYPE_ID NOT IN (36, 37, 39, 44)
    GROUP BY pay.ID, pay.ACCOUNT_ID, m.AGREEMENT_ID, pay.ACTION_DATE, pi.INCOME_ID
    HAVING ABS(SUM(pi.AMOUNT * pi.STATUS)) > 0.0001
),
main_inc AS (
    SELECT
        g.ID                                                     AS MAIN_LREF,
        g.ACCOUNT_ID,
        g.ACTION_DATE,
        g.ACTION_TYPE_ID,
        ai.INCOME_ID
    FROM SMS.CS_ACCOUNT_ACTION g
    JOIN MIGRATION.TMP_MIG_ACC m
      ON m.ACCOUNT_ID = g.ACCOUNT_ID
    JOIN SMS.CS_ACCOUNT_INCOME ai
      ON ai.ACCOUNT_ACTION_ID = g.ID
    WHERE g.ACTION_TYPE_ID IN (1, 3, 10, 41)
),
picked AS (
    SELECT
        pi.PAY_LREF,
        pi.PAY_AMT,
        pi.ABYS_AGREEMENT_ID,
        pi.ABYS_ACCOUNT_ID,
        pi.ACTION_DATE                                           AS PAY_ACTION_DATE,
        mi.MAIN_LREF,
        mi.ACTION_TYPE_ID                                        AS MAIN_ACTION_TYPE_ID,
        /* Tip basina 1 MAIN — arttiran cascade (waterfill MAIN_PRI) */
        ROW_NUMBER() OVER (
          PARTITION BY pi.PAY_LREF, pi.INCOME_ID, mi.ACTION_TYPE_ID
          ORDER BY
            mi.ACTION_DATE ASC,
            mi.MAIN_LREF ASC
        )                                                        AS RN_TYPE
    FROM pay_inc pi
    JOIN main_inc mi
      ON mi.ACCOUNT_ID = pi.ABYS_ACCOUNT_ID
     AND mi.INCOME_ID = pi.INCOME_ID
     AND mi.ACTION_DATE <= pi.ACTION_DATE
),
raw_by_pm AS (
    SELECT
        p.PAY_LREF,
        p.MAIN_LREF,
        MAX(p.ABYS_AGREEMENT_ID)                                 AS ABYS_AGREEMENT_ID,
        MAX(p.ABYS_ACCOUNT_ID)                                   AS ABYS_ACCOUNT_ID,
        MAX(p.MAIN_ACTION_TYPE_ID)                               AS MAIN_ACTION_TYPE_ID,
        MAX(p.PAY_ACTION_DATE)                                   AS PAY_ACTION_DATE,
        ROUND(ABS(SUM(p.PAY_AMT)), 2)                            AS RAW_ALLOC
    FROM picked p
    WHERE p.RN_TYPE = 1
    GROUP BY p.PAY_LREF, p.MAIN_LREF
    HAVING ABS(SUM(p.PAY_AMT)) > 0.0001
),
pay_full AS (
    /* Aksiyon net tutari — PAY_PT.PAY_FULL_AMT ile ayni (ABS(SUM), SUM(ABS) degil) */
    SELECT
        ai.ACCOUNT_ACTION_ID                                     AS PAY_LREF,
        ROUND(ABS(SUM(ai.AMOUNT * ai.STATUS)), 2)                AS PAY_FULL_AMT
    FROM SMS.CS_ACCOUNT_INCOME ai
    WHERE EXISTS (
            SELECT 1 FROM raw_by_pm r WHERE r.PAY_LREF = ai.ACCOUNT_ACTION_ID
          )
    GROUP BY ai.ACCOUNT_ACTION_ID
),
joined AS (
    SELECT
        r.PAY_LREF,
        r.MAIN_LREF,
        r.ABYS_AGREEMENT_ID,
        r.ABYS_ACCOUNT_ID,
        r.MAIN_ACTION_TYPE_ID,
        r.PAY_ACTION_DATE,
        r.RAW_ALLOC,
        NVL(inv.PAYABLETOTAL, 0)                                 AS MAIN_PAYABLE,
        NVL(inv.ABYS_ACTION_TYPE_ID, r.MAIN_ACTION_TYPE_ID)      AS MAIN_ACTION_TYPE_ID_OUT,
        NVL(pf.PAY_FULL_AMT, r.RAW_ALLOC)                        AS PAY_FULL_AMT,
        CASE NVL(r.MAIN_ACTION_TYPE_ID, 99)
          WHEN 1  THEN 0
          WHEN 3  THEN 1
          WHEN 41 THEN 2
          WHEN 10 THEN 3
          ELSE 4
        END                                                      AS MAIN_PRI,
        /* Tek satirlik once MAIN payable tavan (eski davranis) */
        ROUND(
          CASE
            WHEN NVL(inv.PAYABLETOTAL, 0) > 0
             AND r.RAW_ALLOC > inv.PAYABLETOTAL
            THEN inv.PAYABLETOTAL
            ELSE r.RAW_ALLOC
          END
        , 2)                                                     AS RAW_MAIN_CAP
    FROM raw_by_pm r
    LEFT JOIN MIGRATION.LS_INVOICE inv
      ON inv.LREF = r.MAIN_LREF
    LEFT JOIN pay_full pf
      ON pf.PAY_LREF = r.PAY_LREF
    WHERE r.RAW_ALLOC > 0.0001
),
/* 1) Ayni PAY > birden fazla MAIN: odeme bakiyesi (PAY_FULL) bitene kadar */
pay_wf AS (
    SELECT
        j.*,
        ROUND(
          GREATEST(
            0,
            LEAST(
              j.RAW_MAIN_CAP,
              GREATEST(
                0,
                j.PAY_FULL_AMT
                - NVL(
                    SUM(j.RAW_MAIN_CAP) OVER (
                      PARTITION BY j.PAY_LREF
                      ORDER BY j.MAIN_PRI, j.MAIN_LREF
                      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                    ),
                    0
                  )
              )
            )
          )
        , 2)                                                     AS ALLOC_PAY_CAP
    FROM joined j
),
/* 2) Ayni MAIN > birden fazla PAY: fatura bakiyesi (tarih sirasi) bitene kadar */
main_wf AS (
    SELECT
        p.*,
        ROUND(
          GREATEST(
            0,
            LEAST(
              p.ALLOC_PAY_CAP,
              CASE
                WHEN p.MAIN_PAYABLE > 0 THEN
                  GREATEST(
                    0,
                    p.MAIN_PAYABLE
                    - NVL(
                        SUM(p.ALLOC_PAY_CAP) OVER (
                          PARTITION BY p.MAIN_LREF
                          ORDER BY p.PAY_ACTION_DATE, p.PAY_LREF
                          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                        ),
                        0
                      )
                  )
                ELSE p.ALLOC_PAY_CAP
              END
            )
          )
        , 2)                                                     AS ALLOC_AMT
    FROM pay_wf p
)
SELECT
    w.PAY_LREF,
    w.MAIN_LREF,
    w.ABYS_AGREEMENT_ID,
    w.ABYS_ACCOUNT_ID,
    w.ALLOC_AMT,
    w.RAW_ALLOC,
    w.MAIN_PAYABLE,
    w.MAIN_ACTION_TYPE_ID_OUT                                    AS MAIN_ACTION_TYPE_ID,
    CAST('PAY_ALLOC' AS VARCHAR2(12))                            AS OV_KIND
FROM main_wf w
WHERE w.ALLOC_AMT > 0.0001;

CREATE UNIQUE INDEX MIGRATION.IX_OV_PAY_ALLOC ON MIGRATION.LS_OV_PAY_ALLOC (PAY_LREF, MAIN_LREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_PAY_ALLOC NOPARALLEL;
/
CREATE INDEX MIGRATION.IX_OV_PAY_ALLOC_MAIN ON MIGRATION.LS_OV_PAY_ALLOC (MAIN_LREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_PAY_ALLOC_MAIN NOPARALLEL;
/
CREATE INDEX MIGRATION.IX_OV_PAY_ALLOC_AGR ON MIGRATION.LS_OV_PAY_ALLOC (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_PAY_ALLOC_AGR NOPARALLEL;
/
BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION','LS_OV_PAY_ALLOC'); END;
/

-- =============================================================================
-- 1) Tahsilat + Mahsup PAYTRANS (ALLOC patlatma)
-- INVOICEREF = PAY.ID (tek tahsilat fisi)
-- LREF = PAY.ID (birincil MAIN) | 1350000000+n (ek MAIN)
-- CROSSREF_MAIN_LREF = ALLOC.MAIN | PAYABLETOTAL = ALLOC_AMT
-- Alloc yoksa: eski tek-xref fallback (NO_XREF log'a dusmesin diye)
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_PAY_PT PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_PAY_PT NOLOGGING AS
SELECT
    CASE
      WHEN z.ALLOC_RN = 1 THEN z.PAY_LREF
      ELSE 1350000000 + z.SEC_RN
    END                                                          AS LREF,
    z.PAY_LREF                                                   AS INVOICEREF,
    CAST(101 AS NUMBER(3))                                       AS TYPE,
    CAST(1 AS NUMBER(3))                                         AS IOCODE,
    z.MAIN_LREF                                                  AS CROSSREF_MAIN_LREF,
    /* ABYS_PAYTYPE = Oracle ham ACTION_TYPE_ID */
    CAST(z.ACTION_TYPE_ID AS NUMBER(10))                         AS ABYS_PAYTYPE,
    /* PAYTYPE + XTYPE = PayType enum (tahsilat kanali) */
    CASE z.ACTION_TYPE_ID
      WHEN 4  THEN 32   -- Nakit
      WHEN 5  THEN 33   -- KrediKarti
      WHEN 6  THEN 10   -- Mahsup (eski PCMS)
      WHEN 24 THEN 10
      WHEN 45 THEN 178  -- TeminatMektubu
      ELSE 174          -- Banka
    END                                                          AS PAYTYPE,
    CASE z.ACTION_TYPE_ID
      WHEN 4  THEN 32
      WHEN 5  THEN 33
      WHEN 6  THEN 10
      WHEN 24 THEN 10
      WHEN 45 THEN 178
      ELSE 174
    END                                                          AS XTYPE,
    CAST(113 AS NUMBER)                                          AS TRANSTYPE,
    CAST(103 AS NUMBER)                                          AS LINETYPE,
    NVL(z.INSTALLMENT_ORDER_NUMBER, 0)                           AS INST_NR,
    z.DATE_,
    z.ALLOC_AMT                                                  AS PAYABLETOTAL,
    CAST(0 AS NUMBER)                                            AS PAID,
    z.CANCELED,
    CAST(0 AS NUMBER)                                            AS CANCELLATIONPAYMENT,
    NVL(z.CLIENTREF, 0)                                          AS CLIENTREF,
    z.PAY_LREF                                                   AS ABYS_ID,
    z.ABYS_ACCOUNT_ID,
    z.ABYS_AGREEMENT_ID,
    z.MAIN_LREF                                                  AS ABYS_MAIN_LREF,
    z.ACTION_TYPE_ID                                             AS ABYS_ACTION_TYPE_ID,
    CASE
      WHEN z.ACTION_TYPE_ID IN (6, 24) THEN CAST('MAHSUP' AS VARCHAR2(10))
      ELSE CAST('PAY' AS VARCHAR2(10))
    END                                                          AS OV_KIND,
    z.REF_DEPOSIT_ACCOUNT_ID,
    z.REF_DEPOSIT_ACCOUNT_ACTION_ID,
    z.CASH_ID,
    z.RECEIPT_NUMBER,
    z.ALLOC_RN,
    z.PAY_FULL_AMT                                               AS PAY_FULL_AMT,
    CAST(z.ALLOC_SRC AS VARCHAR2(12))                            AS ALLOC_SRC
FROM (
    /* A) Income-based multi alloc */
    SELECT
        al.PAY_LREF,
        al.MAIN_LREF,
        al.ALLOC_AMT,
        al.ABYS_AGREEMENT_ID,
        al.ABYS_ACCOUNT_ID,
        pay.ACTION_TYPE_ID,
        pay.INSTALLMENT_ORDER_NUMBER,
        CASE WHEN EXTRACT(YEAR FROM pay.ACTION_DATE) < 1753
             THEN ADD_MONTHS(pay.ACTION_DATE, 24000) ELSE pay.ACTION_DATE END AS DATE_,
        CASE WHEN can.PAY_ID IS NOT NULL THEN 1 ELSE 0 END        AS CANCELED,
        NVL(inv.CLIENTREF, 0)                                    AS CLIENTREF,
        pay.REF_DEPOSIT_ACCOUNT_ID,
        pay.REF_DEPOSIT_ACCOUNT_ACTION_ID,
        pay.CASH_ID,
        pay.RECEIPT_NUMBER,
        ROUND(ABS(NVL(amt.TUT, 0)), 2)                           AS PAY_FULL_AMT,
        CAST('INCOME' AS VARCHAR2(12))                           AS ALLOC_SRC,
        ROW_NUMBER() OVER (
          PARTITION BY al.PAY_LREF
          ORDER BY
            CASE NVL(al.MAIN_ACTION_TYPE_ID, 99)
              WHEN 1  THEN 0
              WHEN 3  THEN 1
              WHEN 41 THEN 2
              WHEN 10 THEN 3
              ELSE 4
            END,
            al.MAIN_LREF
        )                                                        AS ALLOC_RN,
        ROW_NUMBER() OVER (ORDER BY al.PAY_LREF, al.MAIN_LREF)   AS SEC_RN
    FROM MIGRATION.LS_OV_PAY_ALLOC al
    JOIN SMS.CS_ACCOUNT_ACTION pay ON pay.ID = al.PAY_LREF
    LEFT JOIN MIGRATION.LS_INVOICE inv ON inv.LREF = al.MAIN_LREF
    /* ALLOC driver - index lookup (IN-subquery full-scan riski) */
    LEFT JOIN (
        SELECT ai.ACCOUNT_ACTION_ID, SUM(ai.AMOUNT * ai.STATUS) TUT
        FROM (SELECT DISTINCT PAY_LREF FROM MIGRATION.LS_OV_PAY_ALLOC) a2
        JOIN SMS.CS_ACCOUNT_INCOME ai
          ON ai.ACCOUNT_ACTION_ID = a2.PAY_LREF
        GROUP BY ai.ACCOUNT_ACTION_ID
    ) amt ON amt.ACCOUNT_ACTION_ID = pay.ID
    LEFT JOIN MIGRATION.TMP_PAY_CANCEL can ON can.PAY_ID = pay.ID
    /* Fallback correlated CROSSREF kaldirildi - PAY_PT yalniz ALLOC */
) z
WHERE z.ALLOC_AMT > 0.0001
  AND z.MAIN_LREF IS NOT NULL;

CREATE UNIQUE INDEX MIGRATION.IX_OV_PAY_PT ON MIGRATION.LS_OV_PAY_PT (LREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_PAY_PT NOPARALLEL;
/
CREATE INDEX MIGRATION.IX_OV_PAY_PT_MAIN ON MIGRATION.LS_OV_PAY_PT (CROSSREF_MAIN_LREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_PAY_PT_MAIN NOPARALLEL;
/
CREATE INDEX MIGRATION.IX_OV_PAY_PT_AGR ON MIGRATION.LS_OV_PAY_PT (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_PAY_PT_AGR NOPARALLEL;
/
CREATE INDEX MIGRATION.IX_OV_PAY_PT_PAY ON MIGRATION.LS_OV_PAY_PT (INVOICEREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_PAY_PT_PAY NOPARALLEL;
/
BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION','LS_OV_PAY_PT'); END;
/

-- =============================================================================
-- 1b) Tahsilat faturasi (TYPE=101) — native PCMS modeli; LREF = PAY.ID
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_TAH_INVOICE PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_TAH_INVOICE NOLOGGING AS
SELECT
    p.INVOICEREF                                                 AS LREF,
    CAST(1 AS NUMBER(3))                                         AS IOCODE,
    CAST('TAHSILAT' AS VARCHAR2(50))                             AS FICHENO,
    p.DATE_,
    p.DATE_                                                      AS DUEDATE,
    CAST(101 AS NUMBER(3))                                       AS TYPE,
    p.CLIENTREF,
    p.PAY_FULL_AMT                                               AS TLTOTAL,
    NVL(inv.CURID, 160)                                          AS CURID,
    p.PAY_FULL_AMT                                               AS CURTOTAL,
    CAST(NULL AS VARCHAR2(250))                                  AS EXPLAIN,
    NVL(p.CANCELED, 0)                                           AS CANCELED,
    p.ABYS_AGREEMENT_ID                                          AS OWNERREF,
    NVL(inv.OWNERTYPE, 91)                                       AS OWNERTYPE,
    CAST(0 AS NUMBER)                                            AS TAX,
    CAST(0 AS NUMBER)                                            AS DV,
    p.PAY_FULL_AMT                                               AS GRANDTOTAL,
    CAST(0 AS NUMBER)                                            AS PRINTCOUNT,
    p.PAY_FULL_AMT                                               AS PAYABLETOTAL,
    CAST(1 AS NUMBER(1))                                         AS CLOSED,
    inv.FITNO,
    inv.BN_TYPE,
    p.PAY_FULL_AMT                                               AS AMOUNT,
    inv.PERIOD,
    p.DATE_                                                      AS ADDDATE,
    NVL(inv.ADDUSER, 211)                                        AS ADDUSER,
    p.ABYS_ID,
    p.ABYS_ACCOUNT_ID,
    p.ABYS_ACTION_TYPE_ID,
    p.ABYS_AGREEMENT_ID,
    p.CROSSREF_MAIN_LREF                                         AS ABYS_MAIN_LREF,
    CAST('TAH_INV' AS VARCHAR2(10))                              AS OV_KIND
FROM (
    SELECT x.*,
           ROW_NUMBER() OVER (
             PARTITION BY x.INVOICEREF
             ORDER BY x.ALLOC_RN, x.LREF
           ) AS RN
    FROM MIGRATION.LS_OV_PAY_PT x
    WHERE NVL(x.CANCELED, 0) = 0
) p
LEFT JOIN MIGRATION.LS_INVOICE inv ON inv.LREF = p.CROSSREF_MAIN_LREF
WHERE p.RN = 1;

CREATE UNIQUE INDEX MIGRATION.IX_OV_TAH_INV ON MIGRATION.LS_OV_TAH_INVOICE (LREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_TAH_INV NOPARALLEL;
/
CREATE INDEX MIGRATION.IX_OV_TAH_INV_AGR ON MIGRATION.LS_OV_TAH_INVOICE (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_TAH_INV_AGR NOPARALLEL;
/

-- =============================================================================
-- 2) Borc PT PAID / MAIN CLOSED — ALLOC/PT SUM (coklu CROSSREF destekli)
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_DEBT_PAID_UPD PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_DEBT_PAID_UPD NOLOGGING AS
SELECT
    x.MAIN_LREF,
    x.PAID_AMT,
    x.ABYS_AGREEMENT_ID,
    CASE
      WHEN NVL(x.PAYABLE_AMT, 0) <= 0.01 THEN 1
      WHEN x.PAID_AMT >= x.PAYABLE_AMT - 0.01 THEN 1
      ELSE 0
    END                                                          AS CLOSED
FROM (
    SELECT
        p.CROSSREF_MAIN_LREF                                     AS MAIN_LREF,
        ROUND(SUM(CASE WHEN NVL(p.CANCELED, 0) = 0 THEN p.PAYABLETOTAL ELSE 0 END), 2) AS PAID_AMT,
        MAX(p.ABYS_AGREEMENT_ID)                                 AS ABYS_AGREEMENT_ID,
        ROUND(NVL(MAX(inv.PAYABLETOTAL), 0), 2)                  AS PAYABLE_AMT
    FROM MIGRATION.LS_OV_PAY_PT p
    LEFT JOIN MIGRATION.LS_INVOICE inv ON inv.LREF = p.CROSSREF_MAIN_LREF
    WHERE p.CROSSREF_MAIN_LREF IS NOT NULL
    GROUP BY p.CROSSREF_MAIN_LREF

    UNION ALL

    /* PAYABLETOTAL=0 > CLOSED=1 (odeme olmasa da) */
    SELECT
        inv.LREF                                                 AS MAIN_LREF,
        CAST(0 AS NUMBER)                                        AS PAID_AMT,
        inv.ABYS_AGREEMENT_ID                                    AS ABYS_AGREEMENT_ID,
        ROUND(NVL(inv.PAYABLETOTAL, 0), 2)                       AS PAYABLE_AMT
    FROM MIGRATION.LS_INVOICE inv
    WHERE ABS(NVL(inv.PAYABLETOTAL, 0)) <= 0.01
      AND NVL(inv.IOCODE, 0) = 0
      AND NOT EXISTS (
            SELECT 1 FROM MIGRATION.LS_OV_PAY_PT p
             WHERE p.CROSSREF_MAIN_LREF = inv.LREF
          )
) x;

CREATE UNIQUE INDEX MIGRATION.IX_OV_DEBT_PAID ON MIGRATION.LS_OV_DEBT_PAID_UPD (MAIN_LREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_DEBT_PAID NOPARALLEL;
/
BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION','LS_OV_DEBT_PAID_UPD'); END;
/

-- =============================================================================
-- RECON — over-alloc 0 olmali (kurus tolerans 0.02)
-- =============================================================================
PROMPT ========== 31 RECON: PAY SUM(ALLOC) > PAY_FULL ==========
SELECT COUNT(*) AS PAY_OVER_FULL
FROM (
    SELECT a.PAY_LREF,
           ROUND(SUM(a.ALLOC_AMT), 2) AS SUM_ALLOC,
           NVL(pf.PAY_FULL, 0) AS PAY_FULL
    FROM MIGRATION.LS_OV_PAY_ALLOC a
    LEFT JOIN (
        SELECT ai.ACCOUNT_ACTION_ID AS PAY_LREF,
               ROUND(ABS(SUM(ai.AMOUNT * ai.STATUS)), 2) AS PAY_FULL
        FROM SMS.CS_ACCOUNT_INCOME ai
        GROUP BY ai.ACCOUNT_ACTION_ID
    ) pf ON pf.PAY_LREF = a.PAY_LREF
    GROUP BY a.PAY_LREF, pf.PAY_FULL
    HAVING ROUND(SUM(a.ALLOC_AMT), 2) > NVL(pf.PAY_FULL, 0) + 0.02
);

PROMPT ========== 31 RECON: MAIN SUM(ALLOC) > MAIN_PAYABLE ==========
SELECT COUNT(*) AS MAIN_OVER_PAYABLE
FROM (
    SELECT a.MAIN_LREF,
           ROUND(SUM(a.ALLOC_AMT), 2) AS SUM_ALLOC,
           ROUND(MAX(a.MAIN_PAYABLE), 2) AS MAIN_PAYABLE
    FROM MIGRATION.LS_OV_PAY_ALLOC a
    WHERE NVL(a.MAIN_PAYABLE, 0) > 0
    GROUP BY a.MAIN_LREF
    HAVING ROUND(SUM(a.ALLOC_AMT), 2) > ROUND(MAX(a.MAIN_PAYABLE), 2) + 0.02
);

PROMPT ========== 31 RECON: spot MAIN 63984619 ==========
SELECT PAY_LREF, MAIN_LREF, ALLOC_AMT, RAW_ALLOC, MAIN_PAYABLE
FROM MIGRATION.LS_OV_PAY_ALLOC
WHERE MAIN_LREF = 63984619
ORDER BY PAY_LREF;

SELECT
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_PAY_ALLOC) AS ALLOC_CNT,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_PAY_PT) AS PAY_PT_CNT,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_TAH_INVOICE) AS TAH_INV_CNT,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_DEBT_PAID_UPD) AS DEBT_PAID_CNT
FROM DUAL;

PROMPT ========== 31 WATERFILL ONLY OK — dump LS_OV_PAY_ALLOC/PAY_PT/TAH_INVOICE/DEBT_PAID_UPD ==========
/
