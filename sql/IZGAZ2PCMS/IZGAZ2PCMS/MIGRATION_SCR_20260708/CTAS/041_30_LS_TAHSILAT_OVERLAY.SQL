WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- TERMINAL DUMP final: LS_OV_MAHSUP_CLOSED INDEX/STATS yok (diger OV/TMP zincir IX kalir).

-- =============================================================================
-- oracleCTAS3007 / 30 — TAHSILAT OVERLAY (MAP / SRC_KEY)
-- Onkosul: 11 + 20 | DOP: FORCE 56
-- PAY_PT: SRC_KEY=PAY_PT|{PAY}|{MAIN}; LREF_HINT=PAY_ID sadece ALLOC_RN=1
-- CANCEL_*: SRC_KEY; LREF_HINT NULL (energy IDENTITY)
-- Sentetik 1.35B/1.8B/1.9B YOK
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
  /* MIG_PARAM yoksa FULL (bos) olustur — @@00_mig_param_full / pilot oncesi guvenlik */
  SELECT COUNT(*) INTO n FROM ALL_TABLES
   WHERE OWNER='MIGRATION' AND TABLE_NAME='MIG_PARAM';
  IF n = 0 THEN
    EXECUTE IMMEDIATE
      'CREATE TABLE MIGRATION.MIG_PARAM (REG_ID NUMBER(12), AGR_ID NUMBER(12))';
  END IF;
END;
/

-- =============================================================================
-- 0-PRE) Driver tablolar — pilot hesaplar + gecerli iptal seti (tek sefer)
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.TMP_MIG_ACC PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
/* MIG_PARAM.AGR_ID doluysa yalniz o sozlesmeler; bos/FULL = tum hesaplar */
CREATE TABLE MIGRATION.TMP_MIG_ACC NOLOGGING AS
SELECT a.ID AS ACCOUNT_ID, a.AGREEMENT_ID
FROM SMS.CS_ACCOUNT a
WHERE NVL(a.ACCRUE_TYPE_ID, -1) <> 14
  AND (
        NOT EXISTS (SELECT 1 FROM MIGRATION.MIG_PARAM p WHERE p.AGR_ID IS NOT NULL)
     OR a.AGREEMENT_ID IN (SELECT p.AGR_ID FROM MIGRATION.MIG_PARAM p WHERE p.AGR_ID IS NOT NULL)
      );

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
--   ayni ACCOUNT, tip 1/3/10/41, ortak INCOME_ID
--   oncelik: tip1 > 3 > 41 > 10, sonra eski tarih, sonra min ID
-- (PAY, MAIN) RAW_ALLOC = SUM(PAY_AMT)
--
-- FIX (2026-08-02) — ACTION_DATE<=PAY kaldirildi (ESLESME / canli heuristic ile ayni):
--   tahsilat cogu 00:00:00, tahakkuk gun ici → yanlis NO_PAY / ONLY_EN (or. ACC 21407069).
--   Soft diag: @_skip/30_HOTFIX_ls_ov_tah_log_pay_before.sql (PAY_BEFORE_* log, ALLOC degil).
--
-- FIX (2026-08-02b/c) — iptal odeme (TMP_PAY_CANCEL):
--   Ornek ACC 51407277 / MAIN 109425605:
--     1) PAY 109510236 (gişe) iptal → PAY_PT CANCELED=1 yazilmali; borc PAID'e sayilmaz
--     2) PAY 109577625 (otomatik) gecerli → MAIN kapasitesini o alir
--   Yanlis (02b): iptali pay_inc'den tamamen atmak → CANCELED=1 PAYTRANS hic yok
--   Dogru: iptal ALLOC+PAY_PT'ye girer (CANCELED=1); MAIN waterfill yalniz CANCELED=0 tuketir
--          DEBT_PAID / borc PAID yalniz gecerli odeme (CANCELED=0) SUM
--
-- FIX (2026-07-24) — ornek MAIN 63984619 (kaynak 6.54+8.46=15):
--   Eski: her odeme bagimsiz LEAST(RAW, MAIN_PAYABLE) → 7+10=17, PAID_AMT=16
--         banka ALLOC=10 > PAY_FULL=8
--   Yeni waterfill:
--     1) PAY icinde: SUM(ALLOC) <= PAY_FULL_AMT (aksiyon gelir toplami)
--     2) MAIN icinde (tarih sirasi): SUM(ALLOC) <= MAIN_PAYABLE
--   Arttiran/coklu MAIN: MAIN_PRI + ACTION_DATE waterfill (tip1→3→41→10)
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
        /* iptal PAY de PAY_PT'ye girer (CANCELED=1); kapasite asagida ayrilir */
        CASE WHEN can.PAY_ID IS NOT NULL THEN 1 ELSE 0 END        AS IS_CANCELED,
        CAST(ROUND(ABS(SUM(pi.AMOUNT * pi.STATUS)), 2) AS NUMBER(15,3)) AS PAY_AMT
    FROM SMS.CS_ACCOUNT_ACTION pay
    JOIN MIGRATION.TMP_MIG_ACC m
      ON m.ACCOUNT_ID = pay.ACCOUNT_ID
    JOIN SMS.CS_ACTION_TYPE_PRM atp
      ON atp.ID = pay.ACTION_TYPE_ID
     AND atp.TYPE = 2
    JOIN SMS.CS_ACCOUNT_INCOME pi
      ON pi.ACCOUNT_ACTION_ID = pay.ID
    LEFT JOIN MIGRATION.TMP_PAY_CANCEL can
      ON can.PAY_ID = pay.ID
    WHERE pay.ACTION_TYPE_ID NOT IN (36, 37, 39, 44)
    GROUP BY pay.ID, pay.ACCOUNT_ID, m.AGREEMENT_ID, pay.ACTION_DATE, pi.INCOME_ID,
             CASE WHEN can.PAY_ID IS NOT NULL THEN 1 ELSE 0 END
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
        pi.IS_CANCELED,
        pi.ABYS_AGREEMENT_ID,
        pi.ABYS_ACCOUNT_ID,
        pi.ACTION_DATE                                           AS PAY_ACTION_DATE,
        mi.MAIN_LREF,
        mi.ACTION_DATE                                           AS MAIN_ACTION_DATE,
        mi.ACTION_TYPE_ID                                        AS MAIN_ACTION_TYPE_ID
        /* FIX 2026-08-07: tip basina tek MAIN (RN=1) kaldirildi.
           Ayni tipte birden fazla MAIN (erken tarihli dolu / sonraki acik) varken
           yalniz en eski MAIN seciliyordu → ALLOC=0 + O41 EARLY_PAY_GHOST.
           Tum eslesen MAIN'ler aday; waterfill PAY_FULL + MAIN_PAYABLE tuketir.
           MAIN_PRI: tip1 dolunca tip3/41/10 (cift sayim yok). */
    FROM pay_inc pi
    JOIN main_inc mi
      ON mi.ACCOUNT_ID = pi.ABYS_ACCOUNT_ID
     AND mi.INCOME_ID = pi.INCOME_ID
     /* ACTION_DATE<=PAY YOK — 2026-08-02 temizlendi (tarih/saat yaniltici) */
),
raw_by_pm AS (
    SELECT
        p.PAY_LREF,
        p.MAIN_LREF,
        MAX(p.IS_CANCELED)                                      AS IS_CANCELED,
        MAX(p.ABYS_AGREEMENT_ID)                                 AS ABYS_AGREEMENT_ID,
        MAX(p.ABYS_ACCOUNT_ID)                                   AS ABYS_ACCOUNT_ID,
        MAX(p.MAIN_ACTION_TYPE_ID)                               AS MAIN_ACTION_TYPE_ID,
        MAX(p.PAY_ACTION_DATE)                                   AS PAY_ACTION_DATE,
        MAX(p.MAIN_ACTION_DATE)                                  AS MAIN_ACTION_DATE,
        CAST(ROUND(SUM(p.PAY_AMT), 2) AS NUMBER(15,3))           AS RAW_ALLOC
    FROM picked p
    GROUP BY p.PAY_LREF, p.MAIN_LREF
),
pay_full AS (
    /* Aksiyon net tutari — PAY_PT.PAY_FULL_AMT ile ayni (ABS(SUM), SUM(ABS) degil) */
    SELECT
        ai.ACCOUNT_ACTION_ID                                     AS PAY_LREF,
        CAST(ROUND(ABS(SUM(ai.AMOUNT * ai.STATUS)), 2) AS NUMBER(15,3)) AS PAY_FULL_AMT
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
        r.IS_CANCELED,
        r.ABYS_AGREEMENT_ID,
        r.ABYS_ACCOUNT_ID,
        r.MAIN_ACTION_TYPE_ID,
        r.PAY_ACTION_DATE,
        r.RAW_ALLOC,
        CAST(NVL(inv.PAYABLETOTAL, 0) AS NUMBER(15,3))           AS MAIN_PAYABLE,
        NVL(inv.ABYS_ACTION_TYPE_ID, r.MAIN_ACTION_TYPE_ID)      AS MAIN_ACTION_TYPE_ID_OUT,
        CAST(NVL(pf.PAY_FULL_AMT, r.RAW_ALLOC) AS NUMBER(15,3))  AS PAY_FULL_AMT,
        r.MAIN_ACTION_DATE,
        CASE NVL(r.MAIN_ACTION_TYPE_ID, 99)
          WHEN 1  THEN 0
          WHEN 3  THEN 1
          WHEN 41 THEN 2
          WHEN 10 THEN 3
          ELSE 4
        END                                                      AS MAIN_PRI,
        /* Tek satirlik once MAIN payable tavan (eski davranis) */
        CAST(ROUND(
          CASE
            WHEN NVL(inv.PAYABLETOTAL, 0) > 0
             AND r.RAW_ALLOC > inv.PAYABLETOTAL
            THEN inv.PAYABLETOTAL
            ELSE r.RAW_ALLOC
          END
        , 2) AS NUMBER(15,3))                                    AS RAW_MAIN_CAP
    FROM raw_by_pm r
    LEFT JOIN MIGRATION.LS_INVOICE inv
      ON inv.LREF = r.MAIN_LREF
    LEFT JOIN pay_full pf
      ON pf.PAY_LREF = r.PAY_LREF
    WHERE r.RAW_ALLOC > 0.0001
),
/* 1) Ayni PAY > birden fazla MAIN: odeme bakiyesi (PAY_FULL) bitene kadar
   Sira: tip onceligi, sonra MAIN.ACTION_DATE, sonra LREF */
pay_wf AS (
    SELECT
        j.*,
        CAST(ROUND(
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
                      ORDER BY j.MAIN_PRI, j.MAIN_ACTION_DATE NULLS LAST, j.MAIN_LREF
                      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                    ),
                    0
                  )
              )
            )
          )
        , 2) AS NUMBER(15,3))                                    AS ALLOC_PAY_CAP
    FROM joined j
),
/* 2) Ayni MAIN > birden fazla PAY: fatura bakiyesi (tarih sirasi) bitene kadar
   Iptal (IS_CANCELED=1) ALLOC gosterilir ama MAIN kapasitesini tuketmez */
main_wf AS (
    SELECT
        p.*,
        CAST(ROUND(
          GREATEST(
            0,
            LEAST(
              p.ALLOC_PAY_CAP,
              CASE
                WHEN NVL(p.IS_CANCELED, 0) = 1 THEN p.ALLOC_PAY_CAP
                WHEN p.MAIN_PAYABLE > 0 THEN
                  GREATEST(
                    0,
                    p.MAIN_PAYABLE
                    - NVL(
                        SUM(CASE WHEN NVL(p.IS_CANCELED, 0) = 0
                                 THEN p.ALLOC_PAY_CAP ELSE 0 END) OVER (
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
        , 2) AS NUMBER(15,3))                                    AS ALLOC_AMT
    FROM pay_wf p
)
SELECT
    w.PAY_LREF,
    w.MAIN_LREF,
    w.ABYS_AGREEMENT_ID,
    w.ABYS_ACCOUNT_ID,
    CAST(w.ALLOC_AMT AS NUMBER(15,3))                            AS ALLOC_AMT,
    CAST(w.RAW_ALLOC AS NUMBER(15,3))                            AS RAW_ALLOC,
    CAST(w.MAIN_PAYABLE AS NUMBER(15,3))                         AS MAIN_PAYABLE,
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
-- SRC_KEY her ALLOC satiri; LREF_HINT sadece RN=1 (PAY.ID)
-- CROSSREF_MAIN_LREF = gercek MAIN.LREF (571 INT)
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_PAY_PT PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_PAY_PT NOLOGGING AS
SELECT
    CAST('PAY_PT|' || TO_CHAR(z.PAY_LREF) || '|' || TO_CHAR(z.MAIN_LREF) AS VARCHAR2(80)) AS SRC_KEY,
    CASE WHEN z.ALLOC_RN = 1 THEN z.PAY_LREF ELSE CAST(NULL AS NUMBER(12)) END AS LREF_HINT,
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
    CAST(113 AS NUMBER(10))                                      AS TRANSTYPE,
    CAST(103 AS NUMBER(10))                                      AS LINETYPE,
    NVL(z.INSTALLMENT_ORDER_NUMBER, 0)                           AS INST_NR,
    z.DATE_,
    CAST(z.ALLOC_AMT AS NUMBER(15,3))                            AS PAYABLETOTAL,
    CAST(0 AS NUMBER(15,3))                                      AS PAID,
    z.CANCELED,
    CAST(0 AS NUMBER(15,3))                                      AS CANCELLATIONPAYMENT,
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
    CAST(z.PAY_FULL_AMT AS NUMBER(15,3))                         AS PAY_FULL_AMT,
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
        CAST(ROUND(ABS(NVL(amt.TUT, 0)), 2) AS NUMBER(15,3))     AS PAY_FULL_AMT,
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

CREATE UNIQUE INDEX MIGRATION.IX_OV_PAY_PT ON MIGRATION.LS_OV_PAY_PT (SRC_KEY) PARALLEL 56 NOLOGGING;
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
    CAST('TAH_INV|' || TO_CHAR(p.INVOICEREF) AS VARCHAR2(80))    AS SRC_KEY,
    CAST(p.INVOICEREF AS NUMBER(12))                             AS LREF_HINT,
    p.INVOICEREF                                                 AS LREF,
    CAST(1 AS NUMBER(3))                                         AS IOCODE,
    CAST('TAHSILAT' AS VARCHAR2(50))                             AS FICHENO,
    p.DATE_,
    p.DATE_                                                      AS DUEDATE,
    CAST(101 AS NUMBER(3))                                       AS TYPE,
    p.CLIENTREF,
    CAST(p.PAY_FULL_AMT AS NUMBER(15,3))                         AS TLTOTAL,
    NVL(inv.CURID, 160)                                          AS CURID,
    CAST(p.PAY_FULL_AMT AS NUMBER(15,3))                         AS CURTOTAL,
    /* TYPE=101 EXPLAIN: gecerli=TAHSILAT, iptal=TAHSILAT IPTAL */
    CAST(CASE WHEN NVL(p.CANCELED, 0) = 1
              THEN 'TAHSILAT IPTAL'
              ELSE 'TAHSILAT'
         END AS VARCHAR2(250))                                   AS EXPLAIN,
    NVL(p.CANCELED, 0)                                           AS CANCELED,
    p.ABYS_AGREEMENT_ID                                          AS OWNERREF,
    NVL(inv.OWNERTYPE, 91)                                       AS OWNERTYPE,
    CAST(0 AS NUMBER(15,3))                                      AS TAX,
    CAST(0 AS NUMBER(15,3))                                      AS DV,
    CAST(p.PAY_FULL_AMT AS NUMBER(15,3))                         AS GRANDTOTAL,
    CAST(0 AS NUMBER(10))                                        AS PRINTCOUNT,
    CAST(p.PAY_FULL_AMT AS NUMBER(15,3))                         AS PAYABLETOTAL,
    CAST(1 AS NUMBER(1))                                         AS CLOSED,
    /* bank/makbuz/LPD — O34 PAY_PT enrich ile ayni formul; 597 TAH_INV INSERT */
    CAST(act.BANK_ID AS NUMBER(12))                              AS BANKREF,
    CAST(SUBSTR(NVL(act.BANK_RECEIPT_NUMBER, TO_CHAR(act.RECEIPT_NUMBER)), 1, 50)
         AS VARCHAR2(50))                                        AS BANK_RECORD_REF,
    CASE WHEN NVL(p.CANCELED, 0) = 0 THEN p.DATE_ ELSE CAST(NULL AS DATE) END AS LASTPAIDDATE,
    inv.FITNO,
    inv.BN_TYPE,
    CAST(p.PAY_FULL_AMT AS NUMBER(15,3))                         AS AMOUNT,
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
    /* Iptal tahsilat da TYPE=101 TAH_INV (CANCELED=1) — PAYTRANS ile ayni fis */
    SELECT x.*,
           ROW_NUMBER() OVER (
             PARTITION BY x.INVOICEREF
             ORDER BY x.ALLOC_RN, x.SRC_KEY
           ) AS RN
    FROM MIGRATION.LS_OV_PAY_PT x
) p
LEFT JOIN MIGRATION.LS_INVOICE inv ON inv.LREF = p.CROSSREF_MAIN_LREF
LEFT JOIN SMS.CS_ACCOUNT_ACTION act ON act.ID = p.ABYS_ID
WHERE p.RN = 1;

CREATE UNIQUE INDEX MIGRATION.IX_OV_TAH_INV ON MIGRATION.LS_OV_TAH_INVOICE (LREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_TAH_INV NOPARALLEL;
/
CREATE INDEX MIGRATION.IX_OV_TAH_INV_AGR ON MIGRATION.LS_OV_TAH_INVOICE (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_TAH_INV_AGR NOPARALLEL;
/

-- =============================================================================
-- 2) Borc PT PAID / MAIN CLOSED / LASTPAIDDATE — ALLOC/PT SUM (coklu CROSSREF)
-- LASTPAIDDATE = gecerli (CANCELED=0) odeme DATE_ MAX — kismi odemede de dolar
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_DEBT_PAID_UPD PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_DEBT_PAID_UPD NOLOGGING AS
SELECT
    x.MAIN_LREF,
    CAST(x.PAID_AMT AS NUMBER(15,3))                             AS PAID_AMT,
    x.ABYS_AGREEMENT_ID,
    CASE
      WHEN NVL(x.PAYABLE_AMT, 0) <= 0.01 THEN 1
      WHEN x.PAID_AMT >= x.PAYABLE_AMT - 0.01 THEN 1
      ELSE 0
    END                                                          AS CLOSED,
    x.LASTPAIDDATE
FROM (
    SELECT
        p.CROSSREF_MAIN_LREF                                     AS MAIN_LREF,
        CAST(ROUND(SUM(CASE WHEN NVL(p.CANCELED, 0) = 0 THEN p.PAYABLETOTAL ELSE 0 END), 2) AS NUMBER(15,3)) AS PAID_AMT,
        MAX(p.ABYS_AGREEMENT_ID)                                 AS ABYS_AGREEMENT_ID,
        CAST(ROUND(NVL(MAX(inv.PAYABLETOTAL), 0), 2) AS NUMBER(15,3)) AS PAYABLE_AMT,
        MAX(CASE WHEN NVL(p.CANCELED, 0) = 0 THEN p.DATE_ END)   AS LASTPAIDDATE
    FROM MIGRATION.LS_OV_PAY_PT p
    LEFT JOIN MIGRATION.LS_INVOICE inv ON inv.LREF = p.CROSSREF_MAIN_LREF
    WHERE p.CROSSREF_MAIN_LREF IS NOT NULL
    GROUP BY p.CROSSREF_MAIN_LREF

    UNION ALL

    /* PAYABLETOTAL=0 > CLOSED=1 (odeme olmasa da) */
    SELECT
        inv.LREF                                                 AS MAIN_LREF,
        CAST(0 AS NUMBER(15,3))                                  AS PAID_AMT,
        inv.ABYS_AGREEMENT_ID                                    AS ABYS_AGREEMENT_ID,
        CAST(ROUND(NVL(inv.PAYABLETOTAL, 0), 2) AS NUMBER(15,3)) AS PAYABLE_AMT,
        CAST(NULL AS DATE)                                       AS LASTPAIDDATE
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
    CAST('IADE_INV|' || TO_CHAR(ec.EKS_ACTION_ID) AS VARCHAR2(80)) AS IADE_SRC_KEY,
    CAST(ec.MAIN_GRANDTOTAL AS NUMBER(15,3))                     AS MAIN_GRANDTOTAL,
    CAST(ec.MAIN_PAYABLETOTAL AS NUMBER(15,3))                   AS MAIN_PAYABLETOTAL,
    ec.EKS_DATE,
    ec.CLIENTREF,
    NVL(ec.MAIN_TYPE, 119)                                       AS MAIN_TYPE,
    NVL(vp.CNT, 0)                                               AS VALID_PAY_CNT
FROM MIGRATION.LS_OV_EKS_CLASS ec
LEFT JOIN valid_pay vp ON vp.ACCOUNT_ID = ec.ACCOUNT_ID
WHERE ec.KIND = 'TAM'
  AND ec.MAIN_LREF IS NOT NULL;

CREATE UNIQUE INDEX MIGRATION.IX_OV_TAM_HAS_PAY ON MIGRATION.LS_OV_TAM_HAS_PAY (EKS_ACTION_ID) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_TAM_HAS_PAY NOPARALLEL;
/
BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION','LS_OV_TAM_HAS_PAY'); END;
/

-- 3a) Cancel pay PT — SRC_KEY; INVOICE_SRC_KEY=IADE; CROSSREF_MAIN=MAIN LREF
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_CANCEL_PAY PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_CANCEL_PAY NOLOGGING AS
SELECT
    CAST('CANCEL_PAY|' || TO_CHAR(t.EKS_ACTION_ID) AS VARCHAR2(80)) AS SRC_KEY,
    CAST(NULL AS NUMBER(12))                                     AS LREF_HINT,
    t.IADE_SRC_KEY                                               AS INVOICE_SRC_KEY,
    CAST(92 AS NUMBER(3))                                        AS TYPE,
    CAST(1 AS NUMBER(3))                                         AS IOCODE,
    t.IADE_SRC_KEY                                               AS CROSSREF_IADE_SRC_KEY,
    CAST(t.MAIN_LREF AS NUMBER(12))                              AS CROSSREF_MAIN_LREF,
    CAST(174 AS NUMBER(10))                                      AS PAYTYPE,
    CAST(113 AS NUMBER(10))                                      AS TRANSTYPE,
    CAST(103 AS NUMBER(10))                                      AS LINETYPE,
    CAST(0 AS NUMBER(10))                                        AS INST_NR,
    CASE WHEN EXTRACT(YEAR FROM t.EKS_DATE) < 1753
         THEN ADD_MONTHS(t.EKS_DATE, 24000) ELSE t.EKS_DATE END  AS DATE_,
    CAST(ROUND(NVL(t.MAIN_PAYABLETOTAL, t.MAIN_GRANDTOTAL), 2) AS NUMBER(15,3)) AS PAYABLETOTAL,
    CAST(0 AS NUMBER(15,3))                                      AS PAID,
    CAST(0 AS NUMBER(1))                                         AS CANCELED,
    CAST(1 AS NUMBER(10))                                        AS CANCELLATIONPAYMENT,
    t.CLIENTREF,
    CAST(t.EKS_ACTION_ID AS NUMBER(12))                          AS ABYS_ID,
    CAST(t.ACCOUNT_ID AS NUMBER(12))                             AS ABYS_ACCOUNT_ID,
    t.ABYS_AGREEMENT_ID,
    CAST(t.MAIN_LREF AS NUMBER(12))                              AS ABYS_MAIN_LREF,
    CAST(t.EKS_ACTION_ID AS NUMBER(12))                          AS ABYS_EKS_ACTION_ID,
    CAST('CANCEL_PAY' AS VARCHAR2(12))                           AS OV_KIND
FROM MIGRATION.LS_OV_TAM_HAS_PAY t
WHERE t.VALID_PAY_CNT > 0;

CREATE UNIQUE INDEX MIGRATION.IX_OV_CANCEL_PAY ON MIGRATION.LS_OV_CANCEL_PAY (SRC_KEY) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_CANCEL_PAY NOPARALLEL;
/

-- 3b) Cancel rev PT — SRC_KEY; INVOICEREF=MAIN (gercek LREF)
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_CANCEL_REV PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_CANCEL_REV NOLOGGING AS
SELECT
    CAST('CANCEL_REV|' || TO_CHAR(t.EKS_ACTION_ID) AS VARCHAR2(80)) AS SRC_KEY,
    CAST(NULL AS NUMBER(12))                                     AS LREF_HINT,
    CAST(t.MAIN_LREF AS NUMBER(12))                              AS INVOICEREF,
    t.MAIN_TYPE                                                  AS TYPE,
    CAST(0 AS NUMBER(3))                                         AS IOCODE,
    CAST(t.MAIN_LREF AS NUMBER(12))                              AS CROSSREF_MAIN_LREF,
    CAST(174 AS NUMBER(10))                                      AS PAYTYPE,
    CAST(113 AS NUMBER(10))                                      AS TRANSTYPE,
    CAST(103 AS NUMBER(10))                                      AS LINETYPE,
    CAST(0 AS NUMBER(10))                                        AS INST_NR,
    CASE WHEN EXTRACT(YEAR FROM t.EKS_DATE) < 1753
         THEN ADD_MONTHS(t.EKS_DATE, 24000) ELSE t.EKS_DATE END  AS DATE_,
    CAST(ROUND(NVL(t.MAIN_PAYABLETOTAL, t.MAIN_GRANDTOTAL), 2) AS NUMBER(15,3)) AS PAYABLETOTAL,
    CAST(0 AS NUMBER(15,3))                                      AS PAID,
    CAST(0 AS NUMBER(1))                                         AS CANCELED,
    CAST(1 AS NUMBER(10))                                        AS CANCELLATIONPAYMENT,
    t.CLIENTREF,
    CAST(t.EKS_ACTION_ID AS NUMBER(12))                          AS ABYS_ID,
    CAST(t.ACCOUNT_ID AS NUMBER(12))                             AS ABYS_ACCOUNT_ID,
    t.ABYS_AGREEMENT_ID,
    CAST(t.MAIN_LREF AS NUMBER(12))                              AS ABYS_MAIN_LREF,
    CAST(t.EKS_ACTION_ID AS NUMBER(12))                          AS ABYS_EKS_ACTION_ID,
    CAST('CANCEL_REV' AS VARCHAR2(12))                           AS OV_KIND
FROM MIGRATION.LS_OV_TAM_HAS_PAY t
WHERE t.VALID_PAY_CNT > 0;

CREATE UNIQUE INDEX MIGRATION.IX_OV_CANCEL_REV ON MIGRATION.LS_OV_CANCEL_REV (SRC_KEY) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_CANCEL_REV NOPARALLEL;
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
    p.SRC_KEY                                                    AS PAY_SRC_KEY,
    p.INVOICEREF                                                 AS PAY_LREF,
    p.CROSSREF_MAIN_LREF                                         AS MAIN_LREF,
    p.ABYS_AGREEMENT_ID,
    p.ABYS_ACCOUNT_ID                                            AS ACCOUNT_ID,
    p.ABYS_ACTION_TYPE_ID                                        AS ACTION_TYPE_ID,
    CAST(ROUND(p.PAYABLETOTAL, 2) AS NUMBER(15,3))               AS PAYABLETOTAL,
    p.REF_DEPOSIT_ACCOUNT_ID                                     AS DEP_ACCOUNT_ID,
    p.REF_DEPOSIT_ACCOUNT_ACTION_ID                              AS DEP_ACTION_ID,
    p.CASH_ID,
    p.RECEIPT_NUMBER,
    CAST('MAHSUP_SRC' AS VARCHAR2(12))                           AS OV_KIND
FROM MIGRATION.LS_OV_PAY_PT p
WHERE p.OV_KIND = 'MAHSUP'
  AND NVL(p.CANCELED, 0) = 0
  AND p.CROSSREF_MAIN_LREF IS NOT NULL;

CREATE UNIQUE INDEX MIGRATION.IX_OV_MAHSUP_SRC ON MIGRATION.LS_OV_MAHSUP_SRC (PAY_SRC_KEY) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_MAHSUP_SRC NOPARALLEL;
/
CREATE INDEX MIGRATION.IX_OV_MAHSUP_SRC_MAIN ON MIGRATION.LS_OV_MAHSUP_SRC (MAIN_LREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_MAHSUP_SRC_MAIN NOPARALLEL;
/
CREATE INDEX MIGRATION.IX_OV_MAHSUP_SRC_DEP ON MIGRATION.LS_OV_MAHSUP_SRC (DEP_ACCOUNT_ID) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_MAHSUP_SRC_DEP NOPARALLEL;
/

BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_MAHSUP_CLOSED PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_MAHSUP_CLOSED NOLOGGING AS
SELECT
    m.MAIN_LREF,
    m.ABYS_AGREEMENT_ID,
    NVL(d.CLOSED, 0)                                             AS CLOSED,
    CAST(m.MAHSUP_AMT AS NUMBER(15,3))                           AS MAHSUP_AMT,
    CAST(NVL(b.BANK_AMT, 0) AS NUMBER(15,3))                     AS BANK_AMT,
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
        CAST(ROUND(SUM(s.PAYABLETOTAL), 2) AS NUMBER(15,3))      AS MAHSUP_AMT,
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
        CAST(ROUND(SUM(p.PAYABLETOTAL), 2) AS NUMBER(15,3))      AS BANK_AMT
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

/
/
/

-- =============================================================================
-- 4b) AGR indexes (597 energy LOOP — cancel / debt_paid)
-- =============================================================================
CREATE INDEX MIGRATION.IX_OV_DEBT_PAID_AGR ON MIGRATION.LS_OV_DEBT_PAID_UPD (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_OV_CANCEL_PAY_AGR ON MIGRATION.LS_OV_CANCEL_PAY (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_OV_CANCEL_REV_AGR ON MIGRATION.LS_OV_CANCEL_REV (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_OV_MAHSUP_SRC_AGR ON MIGRATION.LS_OV_MAHSUP_SRC (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;

ALTER INDEX MIGRATION.IX_OV_DEBT_PAID_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_CANCEL_PAY_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_CANCEL_REV_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_MAHSUP_SRC_AGR NOPARALLEL;

-- =============================================================================
-- 5) LOG — AYRI DOSYA: 40_ls_tahsilat_log.sql
-- 6) HARD GATE — AYRI DOSYA: 41_gate_tahsilat.sql
-- =============================================================================
DECLARE
  n_pt NUMBER; n_al NUMBER; n_can NUMBER;
BEGIN
  SELECT COUNT(*) INTO n_pt FROM MIGRATION.LS_OV_PAY_PT;
  SELECT COUNT(*) INTO n_al FROM MIGRATION.LS_OV_PAY_ALLOC;
  SELECT COUNT(*) INTO n_can FROM MIGRATION.LS_OV_CANCEL_PAY;
  MIGRATION.P_MIG_CTAS_LOG('O30', 'tahsilat_overlay', 'OK', n_pt,
    'pay_pt=' || n_pt || ' alloc=' || n_al || ' cancel_pay=' || n_can || ' SRC_KEY model');
  DBMS_OUTPUT.PUT_LINE('========== O30 TAHSILAT OK | pay_pt=' || n_pt
    || ' alloc=' || n_al || ' | sonraki O35 MAP → O41 ==========');
END;
/
/
