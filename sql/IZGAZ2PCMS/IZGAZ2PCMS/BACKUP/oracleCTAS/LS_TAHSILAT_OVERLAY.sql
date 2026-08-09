-- =============================================================================
-- ADIM 5 — TAHSILAT OVERLAY (PAYTRANS zinciri)
-- Ortam : Oracle 11.2 | Schema: MIGRATION | Kaynak: SMS
-- Onkosul: MIGRATION.LS_INVOICE (Adim1) + LS_OV_EKS_CLASS / IADE (Adim4a)
-- Pilot : MIG_PARAM coklu AGR (seed: MIG_PARAM_seed.sql / LS_INVOICE.sql)
--
-- Prefab: TMP_MIG_ACC (MIG_PARAM hesaplari) + TMP_PAY_CANCEL (R42 iptal, tek yer)
-- Uretir:
--   LS_OV_PAY_ALLOC      — odeme INCOME kirilimina gore coklu borc allocation
--                          (pay,income_id) > tek MAIN (tip1>3>41>10, eski tarih)
--   LS_OV_TAH_INVOICE    — TYPE=101 IOCODE=1 tahsilat fisi (LREF=PAY.ID; native gibi)
--   LS_OV_PAY_PT         — ATP.TYPE=2; 1 odeme > N PT (her MAIN icin ALLOC_AMT)
--                          INVOICEREF=PAY.ID | CROSSREF_MAIN_LREF=borc
--                          LREF=PAY.ID (rn=1) | 1.35B+n (ek alloc)
--                          PAYTYPE: 4>32, 5>33, 6/24>10, else 174 | OV_KIND: PAY|MAHSUP
--   LS_OV_DEBT_PAID_UPD  — borc PT PAID + MAIN CLOSED (ALLOC SUM, tek CROSSREF degil)
--   LS_OV_CANCEL_PAY     — TAM+onceki tahsilat: CancelInvoices odeme PT (1.8B+EKS)
--   LS_OV_CANCEL_REV     — TAM+onceki tahsilat: MAIN borc ters PT (1.9B+EKS)
--   LS_OV_MAHSUP_SRC     — mahsup satir > MAIN + emanet hesabi/action (1 emanet > N fatura)
--   LS_OV_MAHSUP_CLOSED  — mahsup ile kapanan/katkili MAIN (CLOSE_KIND + EXPLAIN_MARK)
--
-- Log AYRI: oracleCTAS/LS_TAHSILAT_LOG.sql (overlay SONRASI; tip12/PAY_NO_ALLOC gozlem)
--           Ana zinciri riske sokmamak icin bilerek ayri dosya.
--
-- Hariç: alacaklandirma (36,37,39,44), emanet (ACCRUE=14),
--        TAHSILAT fatura / INVLINES (yalniz PAYTRANS)
--
-- Mahsup: her 6/24 = ayri PAYTRANS; ayni faturada N mahsup + M tahsilat > PAID=SUM
--         para girisi baska girisin cikisindan gelebilir; REF_DEPOSIT_ACCOUNT_ID ile gruplanir
-- CROSSREF: Oracle MAIN_LREF; energy'de borc PT.LREF
-- =============================================================================

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM ALL_TABLES
   WHERE OWNER='MIGRATION' AND TABLE_NAME='LS_INVOICE';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'MIGRATION.LS_INVOICE yok.');
  END IF;
  SELECT COUNT(*) INTO n FROM MIGRATION.MIG_PARAM WHERE AGR_ID IS NOT NULL;
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20003, 'MIG_PARAM.AGR_ID zorunlu.');
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
WHERE NVL(a.ACCRUE_TYPE_ID, -1) <> 14
  AND a.AGREEMENT_ID IN (
        SELECT p.AGR_ID FROM MIGRATION.MIG_PARAM p WHERE p.AGR_ID IS NOT NULL
      );

CREATE UNIQUE INDEX MIGRATION.IX_TMP_MIG_ACC ON MIGRATION.TMP_MIG_ACC (ACCOUNT_ID);
/
BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION','TMP_MIG_ACC'); END;
/

-- Iptal (R42) eslesen odeme ID'leri — YALNIZ pilot hesaplar
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

CREATE UNIQUE INDEX MIGRATION.IX_TMP_PAY_CANCEL ON MIGRATION.TMP_PAY_CANCEL (PAY_ID);
/
BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION','TMP_PAY_CANCEL'); END;
/

-- =============================================================================
-- 0) LS_OV_PAY_ALLOC — odeme gelir kirilimi > coklu MAIN
-- Her (PAY, INCOME_ID) icin tek MAIN:
--   ayni ACCOUNT, tip 1/3/10/41, ACTION_DATE<=PAY, ortak INCOME_ID
--   oncelik: tip1 > 3 > 41 > 10, sonra eski tarih, sonra min ID
-- Sonra (PAY, MAIN) bazinda SUM > ALLOC_AMT (LEAST payable)
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
        ROUND(ABS(SUM(pi.AMOUNT * pi.STATUS)), 2)                AS PAY_AMT
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
        mi.MAIN_LREF,
        mi.ACTION_TYPE_ID                                        AS MAIN_ACTION_TYPE_ID,
        ROW_NUMBER() OVER (
          PARTITION BY pi.PAY_LREF, pi.INCOME_ID
          ORDER BY
            CASE mi.ACTION_TYPE_ID
              WHEN 1  THEN 0
              WHEN 3  THEN 1
              WHEN 41 THEN 2
              WHEN 10 THEN 3
              ELSE 4
            END,
            mi.ACTION_DATE ASC,
            mi.MAIN_LREF ASC
        )                                                        AS RN
    FROM pay_inc pi
    JOIN main_inc mi
      ON mi.ACCOUNT_ID = pi.ABYS_ACCOUNT_ID
     AND mi.INCOME_ID = pi.INCOME_ID
     AND mi.ACTION_DATE <= pi.ACTION_DATE
)
SELECT
    x.PAY_LREF,
    x.MAIN_LREF,
    x.ABYS_AGREEMENT_ID,
    x.ABYS_ACCOUNT_ID,
    ROUND(
      CASE
        WHEN NVL(inv.PAYABLETOTAL, 0) > 0
         AND x.RAW_ALLOC > inv.PAYABLETOTAL
        THEN inv.PAYABLETOTAL
        ELSE x.RAW_ALLOC
      END
    , 2)                                                         AS ALLOC_AMT,
    x.RAW_ALLOC,
    NVL(inv.PAYABLETOTAL, 0)                                     AS MAIN_PAYABLE,
    NVL(inv.ABYS_ACTION_TYPE_ID, x.MAIN_ACTION_TYPE_ID)          AS MAIN_ACTION_TYPE_ID,
    CAST('PAY_ALLOC' AS VARCHAR2(12))                            AS OV_KIND
FROM (
    SELECT
        p.PAY_LREF,
        p.MAIN_LREF,
        MAX(p.ABYS_AGREEMENT_ID)                                 AS ABYS_AGREEMENT_ID,
        MAX(p.ABYS_ACCOUNT_ID)                                   AS ABYS_ACCOUNT_ID,
        MAX(p.MAIN_ACTION_TYPE_ID)                               AS MAIN_ACTION_TYPE_ID,
        ROUND(SUM(p.PAY_AMT), 2)                                 AS RAW_ALLOC
    FROM picked p
    WHERE p.RN = 1
    GROUP BY p.PAY_LREF, p.MAIN_LREF
) x
LEFT JOIN MIGRATION.LS_INVOICE inv
  ON inv.LREF = x.MAIN_LREF
WHERE x.RAW_ALLOC > 0.0001;

CREATE UNIQUE INDEX MIGRATION.IX_OV_PAY_ALLOC ON MIGRATION.LS_OV_PAY_ALLOC (PAY_LREF, MAIN_LREF);
/
CREATE INDEX MIGRATION.IX_OV_PAY_ALLOC_MAIN ON MIGRATION.LS_OV_PAY_ALLOC (MAIN_LREF);
/
CREATE INDEX MIGRATION.IX_OV_PAY_ALLOC_AGR ON MIGRATION.LS_OV_PAY_ALLOC (ABYS_AGREEMENT_ID);
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

CREATE UNIQUE INDEX MIGRATION.IX_OV_PAY_PT ON MIGRATION.LS_OV_PAY_PT (LREF);
/
CREATE INDEX MIGRATION.IX_OV_PAY_PT_MAIN ON MIGRATION.LS_OV_PAY_PT (CROSSREF_MAIN_LREF);
/
CREATE INDEX MIGRATION.IX_OV_PAY_PT_AGR ON MIGRATION.LS_OV_PAY_PT (ABYS_AGREEMENT_ID);
/
CREATE INDEX MIGRATION.IX_OV_PAY_PT_PAY ON MIGRATION.LS_OV_PAY_PT (INVOICEREF);
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

CREATE UNIQUE INDEX MIGRATION.IX_OV_TAH_INV ON MIGRATION.LS_OV_TAH_INVOICE (LREF);
/
CREATE INDEX MIGRATION.IX_OV_TAH_INV_AGR ON MIGRATION.LS_OV_TAH_INVOICE (ABYS_AGREEMENT_ID);
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

CREATE UNIQUE INDEX MIGRATION.IX_OV_DEBT_PAID ON MIGRATION.LS_OV_DEBT_PAID_UPD (MAIN_LREF);
/

-- =============================================================================
-- 3) TAM + gecerli onceki tahsilat > CancelInvoices (R31, trigger=VALID_PAY>0)
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_TAM_HAS_PAY PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_TAM_HAS_PAY NOLOGGING AS
WITH valid_pay AS (
    SELECT pay.ACCOUNT_ID, COUNT(*) AS CNT
    FROM SMS.CS_ACCOUNT_ACTION pay
    JOIN SMS.CS_ACTION_TYPE_PRM atp
      ON atp.ID = pay.ACTION_TYPE_ID AND atp.TYPE = 2
    JOIN (
        SELECT DISTINCT ec.ACCOUNT_ID
          FROM MIGRATION.LS_OV_EKS_CLASS ec
         WHERE ec.KIND = 'TAM' AND ec.MAIN_LREF IS NOT NULL
    ) t ON t.ACCOUNT_ID = pay.ACCOUNT_ID
    WHERE pay.ACTION_TYPE_ID NOT IN (36, 37, 39, 44)
      AND NOT EXISTS (
            SELECT 1 FROM MIGRATION.TMP_PAY_CANCEL c WHERE c.PAY_ID = pay.ID
          )
    GROUP BY pay.ACCOUNT_ID
)
SELECT
    ec.EKS_ACTION_ID,
    ec.ACCOUNT_ID,
    ec.MAIN_LREF,
    ec.AGREEMENT_ID                                              AS ABYS_AGREEMENT_ID,
    1600000000 + ec.EKS_ACTION_ID                                AS IADE_LREF,
    ec.MAIN_GRANDTOTAL,
    ec.MAIN_PAYABLETOTAL,
    ec.EKS_DATE,
    ec.CLIENTREF,
    NVL(ec.MAIN_TYPE, 119)                                       AS MAIN_TYPE,
    NVL(vp.CNT, 0)                                               AS VALID_PAY_CNT
FROM MIGRATION.LS_OV_EKS_CLASS ec
LEFT JOIN valid_pay vp ON vp.ACCOUNT_ID = ec.ACCOUNT_ID
WHERE ec.KIND = 'TAM'
  AND ec.MAIN_LREF IS NOT NULL;

CREATE UNIQUE INDEX MIGRATION.IX_OV_TAM_HAS_PAY ON MIGRATION.LS_OV_TAM_HAS_PAY (EKS_ACTION_ID);
/
BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION','LS_OV_TAM_HAS_PAY'); END;
/

-- 3a) Cancel pay PT — CancelInvoices (R31); LREF=1.8B+EKS
-- INVOICEREF = IADE; CROSSREF = MAIN borc (energy'de debt PT.LREF)
-- Not: CreateReverse IADE_PT bu vakada SILINIR (cift ALACAK olmasin)
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_CANCEL_PAY PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_CANCEL_PAY NOLOGGING AS
SELECT
    1800000000 + t.EKS_ACTION_ID                                 AS LREF,
    t.IADE_LREF                                                  AS INVOICEREF,
    CAST(92 AS NUMBER(3))                                        AS TYPE,
    CAST(1 AS NUMBER(3))                                         AS IOCODE,
    t.IADE_LREF                                                  AS CROSSREF_IADE_LREF,
    t.MAIN_LREF                                                  AS CROSSREF_MAIN_LREF,
    CAST(174 AS NUMBER)                                          AS PAYTYPE,
    CAST(113 AS NUMBER)                                          AS TRANSTYPE,
    CAST(103 AS NUMBER)                                          AS LINETYPE,
    CAST(0 AS NUMBER)                                            AS INST_NR,
    CASE WHEN EXTRACT(YEAR FROM t.EKS_DATE) < 1753
         THEN ADD_MONTHS(t.EKS_DATE, 24000) ELSE t.EKS_DATE END  AS DATE_,
    ROUND(NVL(t.MAIN_PAYABLETOTAL, t.MAIN_GRANDTOTAL), 2)        AS PAYABLETOTAL,
    CAST(0 AS NUMBER)                                            AS PAID,
    CAST(0 AS NUMBER(1))                                         AS CANCELED,
    CAST(1 AS NUMBER)                                            AS CANCELLATIONPAYMENT,
    t.CLIENTREF,
    t.EKS_ACTION_ID                                              AS ABYS_ID,
    t.ACCOUNT_ID                                                 AS ABYS_ACCOUNT_ID,
    t.ABYS_AGREEMENT_ID,
    t.MAIN_LREF                                                  AS ABYS_MAIN_LREF,
    t.EKS_ACTION_ID                                              AS ABYS_EKS_ACTION_ID,
    CAST('CANCEL_PAY' AS VARCHAR2(12))                           AS OV_KIND
FROM MIGRATION.LS_OV_TAM_HAS_PAY t
WHERE t.VALID_PAY_CNT > 0
  AND (1800000000 + t.EKS_ACTION_ID) <= 2147483647;

CREATE UNIQUE INDEX MIGRATION.IX_OV_CANCEL_PAY ON MIGRATION.LS_OV_CANCEL_PAY (LREF);
/

-- 3b) Cancel rev PT — CROSSREF = MAIN borc (energy'de cozulur); LREF=1.9B+EKS
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_CANCEL_REV PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_CANCEL_REV NOLOGGING AS
SELECT
    1900000000 + t.EKS_ACTION_ID                                 AS LREF,
    t.MAIN_LREF                                                  AS INVOICEREF,
    t.MAIN_TYPE                                                  AS TYPE,
    CAST(0 AS NUMBER(3))                                         AS IOCODE,
    t.MAIN_LREF                                                  AS CROSSREF_MAIN_LREF,
    CAST(174 AS NUMBER)                                          AS PAYTYPE,
    CAST(113 AS NUMBER)                                          AS TRANSTYPE,
    CAST(103 AS NUMBER)                                          AS LINETYPE,
    CAST(0 AS NUMBER)                                            AS INST_NR,
    CASE WHEN EXTRACT(YEAR FROM t.EKS_DATE) < 1753
         THEN ADD_MONTHS(t.EKS_DATE, 24000) ELSE t.EKS_DATE END  AS DATE_,
    ROUND(NVL(t.MAIN_PAYABLETOTAL, t.MAIN_GRANDTOTAL), 2)        AS PAYABLETOTAL,
    CAST(0 AS NUMBER)                                            AS PAID,
    CAST(0 AS NUMBER(1))                                         AS CANCELED,
    CAST(1 AS NUMBER)                                            AS CANCELLATIONPAYMENT,
    t.CLIENTREF,
    t.EKS_ACTION_ID                                              AS ABYS_ID,
    t.ACCOUNT_ID                                                 AS ABYS_ACCOUNT_ID,
    t.ABYS_AGREEMENT_ID,
    t.MAIN_LREF                                                  AS ABYS_MAIN_LREF,
    t.EKS_ACTION_ID                                              AS ABYS_EKS_ACTION_ID,
    CAST('CANCEL_REV' AS VARCHAR2(12))                           AS OV_KIND
FROM MIGRATION.LS_OV_TAM_HAS_PAY t
WHERE t.VALID_PAY_CNT > 0
  AND (1900000000 + t.EKS_ACTION_ID) <= 2147483647;

CREATE UNIQUE INDEX MIGRATION.IX_OV_CANCEL_REV ON MIGRATION.LS_OV_CANCEL_REV (LREF);
/

-- =============================================================================
-- 4) Mahsup kaynak + kapama isareti
-- Bir emanet hesabi (REF_DEPOSIT_ACCOUNT_ID) birden fazla fatura borcunu kapatabilir.
-- LS_OV_MAHSUP_SRC  : her mahsup PAYTRANS satiri + emanet izi
-- LS_OV_MAHSUP_CLOSED: MAIN bazinda CLOSE_KIND + EXPLAIN_MARK (energy'ye yazilir)
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_MAHSUP_SRC PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_MAHSUP_SRC NOLOGGING AS
SELECT
    p.LREF                                                       AS PAY_LREF,
    p.CROSSREF_MAIN_LREF                                         AS MAIN_LREF,
    p.ABYS_AGREEMENT_ID,
    p.ABYS_ACCOUNT_ID                                            AS ACCOUNT_ID,
    p.ABYS_ACTION_TYPE_ID                                        AS ACTION_TYPE_ID,
    ROUND(p.PAYABLETOTAL, 2)                                     AS PAYABLETOTAL,
    p.REF_DEPOSIT_ACCOUNT_ID                                     AS DEP_ACCOUNT_ID,
    p.REF_DEPOSIT_ACCOUNT_ACTION_ID                              AS DEP_ACTION_ID,
    p.CASH_ID,
    p.RECEIPT_NUMBER,
    CAST('MAHSUP_SRC' AS VARCHAR2(12))                           AS OV_KIND
FROM MIGRATION.LS_OV_PAY_PT p
WHERE p.OV_KIND = 'MAHSUP'
  AND NVL(p.CANCELED, 0) = 0
  AND p.CROSSREF_MAIN_LREF IS NOT NULL;

CREATE UNIQUE INDEX MIGRATION.IX_OV_MAHSUP_SRC ON MIGRATION.LS_OV_MAHSUP_SRC (PAY_LREF);
/
CREATE INDEX MIGRATION.IX_OV_MAHSUP_SRC_MAIN ON MIGRATION.LS_OV_MAHSUP_SRC (MAIN_LREF);
/
CREATE INDEX MIGRATION.IX_OV_MAHSUP_SRC_DEP ON MIGRATION.LS_OV_MAHSUP_SRC (DEP_ACCOUNT_ID);
/

BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_MAHSUP_CLOSED PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_MAHSUP_CLOSED NOLOGGING AS
SELECT
    m.MAIN_LREF,
    m.ABYS_AGREEMENT_ID,
    NVL(d.CLOSED, 0)                                             AS CLOSED,
    m.MAHSUP_AMT,
    NVL(b.BANK_AMT, 0)                                           AS BANK_AMT,
    m.MAHSUP_CNT,
    CASE
      WHEN NVL(b.BANK_AMT, 0) <= 0.01 THEN CAST('MAHSUP_ONLY' AS VARCHAR2(12))
      ELSE CAST('MIXED' AS VARCHAR2(12))
    END                                                          AS CLOSE_KIND,
    m.DEP_ACCOUNT_ID,
    m.DEP_ACTION_ID,
    NVL(dep.DEP_MAIN_CNT, 1)                                     AS DEP_MAIN_CNT,
    CASE
      WHEN NVL(b.BANK_AMT, 0) <= 0.01
        THEN CAST('MAHSUP KAPAMA' AS VARCHAR2(40))
      ELSE CAST('MAHSUP+TAHSILAT KAPAMA' AS VARCHAR2(40))
    END                                                          AS EXPLAIN_MARK,
    CAST(
      'Mahsup=' || TO_CHAR(m.MAHSUP_AMT) ||
      ' Bank=' || TO_CHAR(NVL(b.BANK_AMT, 0)) ||
      CASE WHEN m.DEP_ACCOUNT_ID IS NOT NULL
           THEN ' DepAcc=' || TO_CHAR(m.DEP_ACCOUNT_ID) ||
                ' (ayni emanet->' || TO_CHAR(NVL(dep.DEP_MAIN_CNT, 1)) || ' fatura)'
           ELSE ''
      END
      AS VARCHAR2(200)
    )                                                            AS DETAIL,
    CAST('MAHSUP_CLOSED' AS VARCHAR2(14))                        AS OV_KIND
FROM (
    SELECT
        s.MAIN_LREF,
        MAX(s.ABYS_AGREEMENT_ID)                                 AS ABYS_AGREEMENT_ID,
        ROUND(SUM(s.PAYABLETOTAL), 2)                            AS MAHSUP_AMT,
        COUNT(*)                                                 AS MAHSUP_CNT,
        /* once coklu fatura kapatan emanet, sonra tutar */
        MAX(s.DEP_ACCOUNT_ID) KEEP (
          DENSE_RANK FIRST ORDER BY
            NVL(dc.DEP_MAIN_CNT, 1) DESC,
            s.PAYABLETOTAL DESC,
            s.PAY_LREF DESC
        )                                                        AS DEP_ACCOUNT_ID,
        MAX(s.DEP_ACTION_ID) KEEP (
          DENSE_RANK FIRST ORDER BY
            NVL(dc.DEP_MAIN_CNT, 1) DESC,
            s.PAYABLETOTAL DESC,
            s.PAY_LREF DESC
        )                                                        AS DEP_ACTION_ID
    FROM MIGRATION.LS_OV_MAHSUP_SRC s
    LEFT JOIN (
        SELECT
            x.DEP_ACCOUNT_ID,
            COUNT(DISTINCT x.MAIN_LREF)                          AS DEP_MAIN_CNT
        FROM MIGRATION.LS_OV_MAHSUP_SRC x
        WHERE x.DEP_ACCOUNT_ID IS NOT NULL
        GROUP BY x.DEP_ACCOUNT_ID
    ) dc ON dc.DEP_ACCOUNT_ID = s.DEP_ACCOUNT_ID
    GROUP BY s.MAIN_LREF
) m
LEFT JOIN MIGRATION.LS_OV_DEBT_PAID_UPD d
  ON d.MAIN_LREF = m.MAIN_LREF
LEFT JOIN (
    SELECT
        p.CROSSREF_MAIN_LREF                                     AS MAIN_LREF,
        ROUND(SUM(p.PAYABLETOTAL), 2)                            AS BANK_AMT
    FROM MIGRATION.LS_OV_PAY_PT p
    WHERE p.OV_KIND = 'PAY'
      AND NVL(p.CANCELED, 0) = 0
      AND p.CROSSREF_MAIN_LREF IS NOT NULL
    GROUP BY p.CROSSREF_MAIN_LREF
) b ON b.MAIN_LREF = m.MAIN_LREF
LEFT JOIN (
    SELECT
        s.DEP_ACCOUNT_ID,
        COUNT(DISTINCT s.MAIN_LREF)                              AS DEP_MAIN_CNT
    FROM MIGRATION.LS_OV_MAHSUP_SRC s
    WHERE s.DEP_ACCOUNT_ID IS NOT NULL
    GROUP BY s.DEP_ACCOUNT_ID
) dep ON dep.DEP_ACCOUNT_ID = m.DEP_ACCOUNT_ID;

CREATE UNIQUE INDEX MIGRATION.IX_OV_MAHSUP_CLOSED ON MIGRATION.LS_OV_MAHSUP_CLOSED (MAIN_LREF);
/
CREATE INDEX MIGRATION.IX_OV_MAHSUP_CLOSED_DEP ON MIGRATION.LS_OV_MAHSUP_CLOSED (DEP_ACCOUNT_ID);
/
CREATE INDEX MIGRATION.IX_OV_MAHSUP_CLOSED_KIND ON MIGRATION.LS_OV_MAHSUP_CLOSED (CLOSE_KIND);
/

-- =============================================================================
-- 5) LOG — AYRI DOSYA (ana zinciri riske sokmamak icin)
--    oracleCTAS/LS_TAHSILAT_LOG.sql
--    Overlay bittikten SONRA kosulur. Tip12 / PAY_NO_ALLOC / emanet gozlem.
-- =============================================================================
-- =============================================================================
-- 6) GATE
-- =============================================================================
SELECT 'PAY_PT' AS K, 'CNT' AS V, COUNT(*) AS N FROM MIGRATION.LS_OV_PAY_PT
UNION ALL
SELECT 'PAY_ALLOC', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_PAY_ALLOC
UNION ALL
SELECT 'PAY_MULTI', 'CNT', COUNT(*) FROM (
    SELECT PAY_LREF FROM MIGRATION.LS_OV_PAY_ALLOC GROUP BY PAY_LREF HAVING COUNT(*) > 1
)
UNION ALL
SELECT 'TAH_INV', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_TAH_INVOICE
UNION ALL
SELECT 'PAY_PT_OK', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE NVL(CANCELED,0)=0
UNION ALL
SELECT 'PAY_BANK', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE OV_KIND='PAY' AND NVL(CANCELED,0)=0
UNION ALL
SELECT 'PAY_MAHSUP', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE OV_KIND='MAHSUP' AND NVL(CANCELED,0)=0
UNION ALL
SELECT 'PAY_PT_CANC', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE NVL(CANCELED,0)=1
UNION ALL
SELECT 'PAY_NO_XREF', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE CROSSREF_MAIN_LREF IS NULL
UNION ALL
SELECT 'PAY_INV_EQ_MAIN', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT
 WHERE INVOICEREF = CROSSREF_MAIN_LREF AND CROSSREF_MAIN_LREF IS NOT NULL
UNION ALL
SELECT 'DEBT_PAID', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_DEBT_PAID_UPD
UNION ALL
SELECT 'DEBT_CLOSED', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_DEBT_PAID_UPD WHERE CLOSED=1
UNION ALL
SELECT 'TAM_HAS_PAY', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_TAM_HAS_PAY WHERE VALID_PAY_CNT>0
UNION ALL
SELECT 'CANCEL_PAY', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_CANCEL_PAY
UNION ALL
SELECT 'CANCEL_REV', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_CANCEL_REV
UNION ALL
SELECT 'MAHSUP_SRC', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_MAHSUP_SRC
UNION ALL
SELECT 'MAHSUP_CLOSED', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_MAHSUP_CLOSED
UNION ALL
SELECT 'MAHSUP_ONLY', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_MAHSUP_CLOSED WHERE CLOSE_KIND='MAHSUP_ONLY'
UNION ALL
SELECT 'MAHSUP_MIXED', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_MAHSUP_CLOSED WHERE CLOSE_KIND='MIXED'
UNION ALL
SELECT 'MAHSUP_MULTI_DEP', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_MAHSUP_CLOSED WHERE DEP_MAIN_CNT > 1
;