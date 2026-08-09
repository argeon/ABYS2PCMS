-- =============================================================================
-- prod2 / 20 — EKSILTEN OVERLAY (TAM → IADE + KISMI + tahakkuk notu)
-- Ortam : Oracle 11.2 | Schema: MIGRATION | Kaynak: SMS
-- Onkosul: 11_ls_invoice + 12_ls_invlines
-- MOD: FULL — tum LS_INVOICE / hesaplar (MIG_PARAM zorunlulugu YOK)
-- DOP: session parallel; index PARALLEL 56 + AGR index (energy LOOP)
--
-- Bu CTAS Adim-1 MAIN'i YENIDEN URETMEZ. Delta uretir:
--   LS_OV_EKS_CLASS     — TAM / KISMI / ASIM
--   LS_OV_IADE_INVOICE  — IADE baslik (LREF=1.6B+EKS_ACTION)
--   LS_OV_IADE_INVLINES — IADE satir  (LREF=1.7B+MAIN_LINE.LREF)
--   LS_OV_IADE_PAYTRANS — IADE alacak PT (CreateReverse; IOCODE=1)
--   LS_OV_MAIN_UPD      — MAIN RETURN_TARGET / CANCEL_* / CLOSED
--   LS_OV_KISMI_INVLINES— bagli tahakkuka + satir (INVOICEREF=MAIN; tutar pozitif)
--   LS_OV_KISMI_HDR     — MAIN baslik net (MAIN - KISMI) + EXPLAIN_NOTE
--   LS_OV_KISMI_PAYTRANS— MAIN borc PT hedefi (R32 rebuild; IOCODE=0)
--
-- KISMI model (2026-07-24): eksi (-) satir YOK.
--   +ABS tutar MAIN uzerine yazilir; HDR dusum yapar; EXPLAIN'e not.
--   Borc PAYTRANS PAYABLE = HDR (energy 590 UPDATE / yoksa INSERT).
--
-- Hariç (sonraki Adim 4b/5): CancelInvoices iade tahsilat, normal tahsilat
--
-- Kopru: MAIN.LREF = ABYS_ACTION_ID (Adim1/571) — ACCOUNT.ID DEGIL
-- IADE TYPE=92 IOCODE=1 EXPLAIN='IADE FATURASI' CANCEL_REASON_ID=6
-- ENERGY: IADE_IL.ABYS_ID = sentetik LREF (UX; 590 ile ayni)
-- RISK: 1.6B+EKS / 2.11B+RN INT tasma; LINENR MAIN kopyasi (>255 → 590 SMALLINT OK)
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
    RAISE_APPLICATION_ERROR(-20001, 'MIGRATION.LS_INVOICE yok. Once Adim1 calistirin.');
  END IF;
  SELECT COUNT(*) INTO n FROM ALL_TABLES
   WHERE OWNER='MIGRATION' AND TABLE_NAME='LS_INVLINES';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20002, 'MIGRATION.LS_INVLINES yok. Once Adim2 calistirin.');
  END IF;
END;
/

-- =============================================================================
-- 1) EKSILTEN sinif: TAM / KISMI / ASIM
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_EKS_CLASS PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_EKS_CLASS NOLOGGING AS
SELECT
    e.ID                                                         AS EKS_ACTION_ID,
    e.ACCOUNT_ID,
    e.ACTION_DATE                                                AS EKS_DATE,
    e.CREATED_USER_ID                                            AS EKS_USER_ID,
    eks.tut                                                      AS EKS_AMT,
    NVL(tah.tut, 0)                                              AS TAH_AMT,
    CASE
      WHEN eks.tut > NVL(tah.tut, 0) + 0.01 THEN 'ASIM'
      WHEN eks.tut >= NVL(tah.tut, 0) * 0.995 THEN 'TAM'
      ELSE 'KISMI'
    END                                                          AS KIND,
    /* Adim1 MAIN: type=1 action LREF */
    main.LREF                                                    AS MAIN_LREF,
    main.ABYS_ACTION_ID                                          AS MAIN_ACTION_ID,
    main.ABYS_AGREEMENT_ID                                       AS AGREEMENT_ID,
    main.CLIENTREF,
    main.OWNERREF,
    NVL(main.OWNERTYPE, 91)                                      AS OWNERTYPE,
    main.CURID                                                   AS CURID,
    main.FITNO                                                   AS FITNO,
    main.BN_TYPE                                                 AS BN_TYPE,
    main.AMOUNT                                                  AS MAIN_AMOUNT,
    main.PERIOD                                                  AS PERIOD,
    NVL(main.HAS_DISCOUNT, 0)                                    AS HAS_DISCOUNT,
    NVL(main.DISCOUNT_AMOUNT, 0)                                 AS DISCOUNT_AMOUNT,
    main.TLTOTAL                                                 AS MAIN_TLTOTAL,
    main.TAX                                                     AS MAIN_TAX,
    main.GRANDTOTAL                                              AS MAIN_GRANDTOTAL,
    main.PAYABLETOTAL                                            AS MAIN_PAYABLETOTAL,
    main.TYPE                                                    AS MAIN_TYPE,
    main.FICHENO                                                 AS MAIN_FICHENO,
    main.DATE_                                                   AS MAIN_DATE,
    main.DUEDATE                                                 AS MAIN_DUEDATE
FROM SMS.CS_ACCOUNT_ACTION e
JOIN SMS.CS_ACCOUNT a
  ON a.ID = e.ACCOUNT_ID
 AND NVL(a.ACCRUE_TYPE_ID, -1) <> 14

JOIN (
    SELECT ai.ACCOUNT_ACTION_ID, SUM(ABS(ai.AMOUNT)) tut
    FROM SMS.CS_ACCOUNT_INCOME ai
    GROUP BY ai.ACCOUNT_ACTION_ID
) eks ON eks.ACCOUNT_ACTION_ID = e.ID
LEFT JOIN (
    SELECT x.ACCOUNT_ID, SUM(ABS(i.AMOUNT)) tut
    FROM SMS.CS_ACCOUNT_ACTION x
    JOIN SMS.CS_ACCOUNT_INCOME i ON i.ACCOUNT_ACTION_ID = x.ID
    WHERE x.ACTION_TYPE_ID = 1
    GROUP BY x.ACCOUNT_ID
) tah ON tah.ACCOUNT_ID = e.ACCOUNT_ID
LEFT JOIN MIGRATION.LS_INVOICE main
  ON main.ABYS_ACCOUNT_ID = e.ACCOUNT_ID
 AND main.ABYS_ACTION_TYPE_ID = 1
WHERE e.ACTION_TYPE_ID = 2;

CREATE INDEX MIGRATION.IX_OV_EKS_KIND ON MIGRATION.LS_OV_EKS_CLASS (KIND) PARALLEL 56 NOLOGGING;
CREATE UNIQUE INDEX MIGRATION.IX_OV_EKS_ACT ON MIGRATION.LS_OV_EKS_CLASS (EKS_ACTION_ID) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_EKS_KIND NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_EKS_ACT NOPARALLEL;

-- ASIM: skip listesi (manuel inceleme)
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_EKS_SKIP PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_EKS_SKIP NOLOGGING AS
SELECT EKS_ACTION_ID, ACCOUNT_ID, MAIN_LREF, EKS_AMT, TAH_AMT, 'EKS>TAH' AS REASON
FROM MIGRATION.LS_OV_EKS_CLASS
WHERE KIND = 'ASIM';

-- =============================================================================
-- 2) TAM → IADE INVOICE
-- LREF = 1600000000 + EKS_ACTION_ID
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_IADE_INVOICE PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_IADE_INVOICE NOLOGGING AS
SELECT
    CAST(1600000000 + ec.EKS_ACTION_ID AS NUMBER(12))            AS LREF,
    CAST(1 AS NUMBER(3))                                         AS IOCODE,
    /* FICHENO: son 7 hane zero-pad — LPAD(LREF,7) KIRPMAZ */
    'I' || LPAD(TO_CHAR(MOD(1600000000 + ec.EKS_ACTION_ID, 10000000)), 7, '0') AS FICHENO,
    CASE
      WHEN ec.EKS_DATE IS NULL THEN CAST(NULL AS DATE)
      WHEN CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
                THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END
           < DATE '1900-01-01' THEN DATE '1900-01-01'
      WHEN CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
                THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END
           > DATE '2079-06-06' THEN DATE '2079-06-06'
      ELSE CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
                THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END
    END                                                          AS DATE_,
    CASE
      WHEN NVL(ec.MAIN_DUEDATE, ec.EKS_DATE) IS NULL THEN CAST(NULL AS DATE)
      WHEN CASE WHEN EXTRACT(YEAR FROM NVL(ec.MAIN_DUEDATE, ec.EKS_DATE)) < 1753
                THEN ADD_MONTHS(NVL(ec.MAIN_DUEDATE, ec.EKS_DATE), 24000)
                ELSE NVL(ec.MAIN_DUEDATE, ec.EKS_DATE) END
           < DATE '1900-01-01' THEN DATE '1900-01-01'
      WHEN CASE WHEN EXTRACT(YEAR FROM NVL(ec.MAIN_DUEDATE, ec.EKS_DATE)) < 1753
                THEN ADD_MONTHS(NVL(ec.MAIN_DUEDATE, ec.EKS_DATE), 24000)
                ELSE NVL(ec.MAIN_DUEDATE, ec.EKS_DATE) END
           > DATE '2079-06-06' THEN DATE '2079-06-06'
      ELSE CASE WHEN EXTRACT(YEAR FROM NVL(ec.MAIN_DUEDATE, ec.EKS_DATE)) < 1753
                THEN ADD_MONTHS(NVL(ec.MAIN_DUEDATE, ec.EKS_DATE), 24000)
                ELSE NVL(ec.MAIN_DUEDATE, ec.EKS_DATE) END
    END                                                          AS DUEDATE,
    CAST(92 AS NUMBER(3))                                        AS TYPE,
    CAST(ec.CLIENTREF AS NUMBER(12))                             AS CLIENTREF,
    ROUND(ec.MAIN_TLTOTAL, 2)                                    AS TLTOTAL,
    CAST(NVL(ec.CURID, 160) AS NUMBER(5))                        AS CURID,
    ROUND(ec.MAIN_GRANDTOTAL, 2)                                 AS CURTOTAL,
    CAST('IADE FATURASI' AS VARCHAR2(250))                       AS EXPLAIN,
    CAST(0 AS NUMBER(1))                                         AS CANCELED,   -- zorunlu 0
    CAST(ec.OWNERREF AS NUMBER(12))                              AS OWNERREF,
    CAST(NVL(ec.OWNERTYPE, 91) AS NUMBER(3))                     AS OWNERTYPE,
    ROUND(ec.MAIN_TAX, 2)                                        AS TAX,
    CAST(0 AS NUMBER(18,3))                                      AS DV,
    ROUND(ec.MAIN_GRANDTOTAL, 2)                                 AS GRANDTOTAL,
    CAST(0 AS NUMBER(10))                                        AS PRINTCOUNT,
    ROUND(ec.MAIN_PAYABLETOTAL, 2)                               AS PAYABLETOTAL,
    CAST(1 AS NUMBER(1))                                         AS CLOSED,
    CAST(ec.MAIN_LREF AS NUMBER(12))                             AS RETURN_SOURCE_INVREF,
    CAST(NULL AS NUMBER(12))                                     AS RETURN_TARGET_INVREF,
    CAST(ec.FITNO AS NUMBER(19))                                 AS FITNO,
    CAST(ec.BN_TYPE AS NUMBER(10))                               AS BN_TYPE,
    ROUND(NVL(ec.MAIN_AMOUNT, ec.MAIN_PAYABLETOTAL), 2)          AS AMOUNT,
    CAST(ec.PERIOD AS NUMBER(10))                                AS PERIOD,
    CAST(NVL(ec.HAS_DISCOUNT, 0) AS NUMBER(1))                   AS HAS_DISCOUNT,
    ROUND(NVL(ec.DISCOUNT_AMOUNT, 0), 2)                         AS DISCOUNT_AMOUNT,
    CASE
      WHEN ec.EKS_DATE IS NULL THEN CAST(NULL AS DATE)
      WHEN CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
                THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END
           < DATE '1900-01-01' THEN DATE '1900-01-01'
      WHEN CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
                THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END
           > DATE '2079-06-06' THEN DATE '2079-06-06'
      ELSE CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
                THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END
    END                                                          AS ADDDATE,
    CAST(ec.EKS_USER_ID AS NUMBER(10))                           AS ADDUSER,
    CAST(ec.EKS_ACTION_ID AS NUMBER(12))                         AS ABYS_ID,
    CAST(ec.ACCOUNT_ID AS NUMBER(12))                            AS ABYS_ACCOUNT_ID,
    CAST(2 AS NUMBER(10))                                        AS ABYS_ACTION_TYPE_ID,
    CAST(ec.AGREEMENT_ID AS NUMBER(12))                          AS ABYS_AGREEMENT_ID,
    CAST(ec.MAIN_LREF AS NUMBER(12))                             AS ABYS_MAIN_LREF,
    CAST(ec.EKS_ACTION_ID AS NUMBER(12))                         AS ABYS_EKS_ACTION_ID,
    CAST('IADE' AS VARCHAR2(10))                                 AS OV_KIND
FROM MIGRATION.LS_OV_EKS_CLASS ec
WHERE ec.KIND = 'TAM'
  AND ec.MAIN_LREF IS NOT NULL
  AND (1600000000 + ec.EKS_ACTION_ID) BETWEEN 1 AND 2147483647;

CREATE UNIQUE INDEX MIGRATION.IX_OV_IADE_INV ON MIGRATION.LS_OV_IADE_INVOICE (LREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_IADE_INV NOPARALLEL;

-- =============================================================================
-- 3) TAM → MAIN UPDATE satirları
-- MAIN.RETURN_TARGET tek: ayni MAIN_LREF icin birden fazla TAM EKS varsa
-- son EKS (EKS_DATE, EKS_ACTION_ID) kazanir. IADE satirlari hepsi uretilir.
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_MAIN_UPD PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_MAIN_UPD NOLOGGING AS
SELECT
    LREF,
    RETURN_TARGET_INVREF,
    CANCEL_DATE,
    CANCEL_REASON_ID,
    CANCEL_USER_ID,
    CLOSED,
    CANCELED,
    ABYS_EKS_ACTION_ID,
    ABYS_AGREEMENT_ID
FROM (
    SELECT
        ec.MAIN_LREF                                                 AS LREF,
        1600000000 + ec.EKS_ACTION_ID                                AS RETURN_TARGET_INVREF,
        CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
             THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END AS CANCEL_DATE,
        CAST(6 AS NUMBER)                                            AS CANCEL_REASON_ID,
        ec.EKS_USER_ID                                               AS CANCEL_USER_ID,
        CAST(1 AS NUMBER(1))                                         AS CLOSED,
        CAST(0 AS NUMBER(1))                                         AS CANCELED,
        ec.EKS_ACTION_ID                                             AS ABYS_EKS_ACTION_ID,
        ec.AGREEMENT_ID                                              AS ABYS_AGREEMENT_ID,
        ROW_NUMBER() OVER (
            PARTITION BY ec.MAIN_LREF
            ORDER BY ec.EKS_DATE DESC NULLS LAST, ec.EKS_ACTION_ID DESC
        ) AS RN
    FROM MIGRATION.LS_OV_EKS_CLASS ec
    WHERE ec.KIND = 'TAM'
      AND ec.MAIN_LREF IS NOT NULL
)
WHERE RN = 1;

CREATE UNIQUE INDEX MIGRATION.IX_OV_MAIN_UPD ON MIGRATION.LS_OV_MAIN_UPD (LREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_MAIN_UPD NOPARALLEL;

-- =============================================================================
-- 4) TAM → IADE INVLINES (MAIN satirlarinin pozitif kopyasi)
-- LREF = 2110000000 + ROW_NUMBER  (1.7B+source_line INT tasmasi yapar)
-- ABYS_ID = LREF (energy UX_LS005_INVLINES_ABYS_ID — MAIN income id YAZMA)
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_IADE_INVLINES PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_IADE_INVLINES NOLOGGING AS
SELECT
    s.LREF,
    s.INVOICEREF,
    s.CLIENTREF,
    s.DATE_,
    s.TYPE,
    s.LINENR,
    s.TRANSTYPE,
    s.AMOUNT,
    s.TLTOTAL,
    s.TAX,
    s.GRANDTOTAL,
    s.LINEEXP,
    s.ABYS_INCOME_ROW_ID,
    s.ABYS_INCOME_ID,
    /* energy bridge: UX unique — ABYS_ID = sentetik LREF (590 ile ayni) */
    s.LREF                                                       AS ABYS_ID,
    s.ABYS_EKS_ACTION_ID,
    s.ABYS_AGREEMENT_ID,
    s.ABYS_SOURCE_LINE_LREF,
    s.OV_KIND
FROM (
    SELECT
        CAST(2110000000 + ROW_NUMBER() OVER (ORDER BY ec.EKS_ACTION_ID, il.LINENR, il.LREF) AS NUMBER(12)) AS LREF,
        CAST(1600000000 + ec.EKS_ACTION_ID AS NUMBER(12))        AS INVOICEREF,
        CAST(il.CLIENTREF AS NUMBER(12))                         AS CLIENTREF,
        CASE
          WHEN ec.EKS_DATE IS NULL THEN CAST(NULL AS DATE)
          WHEN CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
                    THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END
               < DATE '1900-01-01' THEN DATE '1900-01-01'
          WHEN CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
                    THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END
               > DATE '2079-06-06' THEN DATE '2079-06-06'
          ELSE CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
                    THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END
        END                                                      AS DATE_,
        CAST(92 AS NUMBER(3))                                    AS TYPE,
        CAST(il.LINENR AS NUMBER(5))                             AS LINENR,
        CAST(il.TRANSTYPE AS NUMBER(10))                         AS TRANSTYPE,
        ROUND(ABS(il.AMOUNT), 2)                                 AS AMOUNT,
        ROUND(ABS(il.TLTOTAL), 2)                                AS TLTOTAL,
        ROUND(ABS(il.TAX), 2)                                    AS TAX,
        ROUND(ABS(il.GRANDTOTAL), 2)                             AS GRANDTOTAL,
        CAST('IADE ' || NVL(il.LINEEXP, TO_CHAR(il.TRANSTYPE)) AS VARCHAR2(100)) AS LINEEXP,
        CAST(il.ABYS_INCOME_ROW_ID AS NUMBER(12))                AS ABYS_INCOME_ROW_ID,
        CAST(il.ABYS_INCOME_ID AS NUMBER(10))                    AS ABYS_INCOME_ID,
        CAST(ec.EKS_ACTION_ID AS NUMBER(12))                     AS ABYS_EKS_ACTION_ID,
        CAST(ec.AGREEMENT_ID AS NUMBER(12))                      AS ABYS_AGREEMENT_ID,
        CAST(il.LREF AS NUMBER(12))                              AS ABYS_SOURCE_LINE_LREF,
        CAST('IADE' AS VARCHAR2(10))                             AS OV_KIND
    FROM MIGRATION.LS_OV_EKS_CLASS ec
    JOIN MIGRATION.LS_INVLINES il
      ON il.INVOICEREF = ec.MAIN_LREF
    WHERE ec.KIND = 'TAM'
      AND ec.MAIN_LREF IS NOT NULL
) s
WHERE s.LREF BETWEEN 1 AND 2147483647;

CREATE UNIQUE INDEX MIGRATION.IX_OV_IADE_IL ON MIGRATION.LS_OV_IADE_INVLINES (LREF) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_OV_IADE_IL_INV ON MIGRATION.LS_OV_IADE_INVLINES (INVOICEREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_IADE_IL NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_IADE_IL_INV NOPARALLEL;

-- =============================================================================
-- 5) TAM → IADE PAYTRANS (CreateReverse — alacak PT; CancelInvoices YOK)
-- LREF = IADE.LREF; INVOICEREF = IADE.LREF; IOCODE=1
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_IADE_PAYTRANS PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_IADE_PAYTRANS NOLOGGING AS
SELECT
    i.LREF                                                       AS LREF,
    i.LREF                                                       AS INVOICEREF,
    CAST(92 AS NUMBER(3))                                        AS TYPE,
    CAST(1 AS NUMBER(3))                                         AS IOCODE,
    CAST(NULL AS NUMBER(12))                                     AS CROSSREF,
    CAST(174 AS NUMBER(10))                                      AS PAYTYPE,
    CAST(113 AS NUMBER(10))                                      AS TRANSTYPE,
    CAST(103 AS NUMBER(10))                                      AS LINETYPE,
    CAST(0 AS NUMBER(10))                                        AS INST_NR,
    i.DATE_,
    i.PAYABLETOTAL,
    CAST(0 AS NUMBER(18,3))                                      AS PAID,
    CAST(0 AS NUMBER(1))                                         AS CANCELED,
    i.CLIENTREF,
    i.ABYS_ID,
    i.ABYS_ACCOUNT_ID,
    i.ABYS_AGREEMENT_ID,
    i.ABYS_EKS_ACTION_ID,
    i.ABYS_MAIN_LREF,
    CAST('IADE' AS VARCHAR2(10))                                 AS OV_KIND
FROM MIGRATION.LS_OV_IADE_INVOICE i;

CREATE UNIQUE INDEX MIGRATION.IX_OV_IADE_PT ON MIGRATION.LS_OV_IADE_PAYTRANS (LREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_IADE_PT NOPARALLEL;

-- =============================================================================
-- 6) KISMI → bagli tahakkuka + INVLINES (ayni MAIN INVOICEREF)
-- LREF = CS_ACCOUNT_INCOME.ID  (Adim2'de type=2 income yok → carpisma yok)
-- Model: tutarlar +ABS (eksi satir YOK); dusum HDR'de; satir notu LINEEXP'te
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_KISMI_INVLINES PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_KISMI_INVLINES NOLOGGING AS
SELECT
    CAST(ai.ID AS NUMBER(12))                                    AS LREF,
    CAST(ec.MAIN_LREF AS NUMBER(12))                             AS INVOICEREF,
    CAST(ec.CLIENTREF AS NUMBER(12))                             AS CLIENTREF,
    CASE
      WHEN ec.EKS_DATE IS NULL THEN CAST(NULL AS DATE)
      WHEN CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
                THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END
           < DATE '1900-01-01' THEN DATE '1900-01-01'
      WHEN CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
                THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END
           > DATE '2079-06-06' THEN DATE '2079-06-06'
      ELSE CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
                THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END
    END                                                          AS DATE_,
    CAST(NVL(ec.MAIN_TYPE, 119) AS NUMBER(3))                    AS TYPE,
    CAST(ROW_NUMBER() OVER (PARTITION BY ec.MAIN_LREF ORDER BY ai.ID) AS NUMBER(5)) AS LINENR,
    CAST(CASE
      WHEN NVL(ai.IS_DISCOUNT, 0) = 1 AND ai.INCOME_ID = 939 THEN 807
      WHEN NVL(ai.IS_DISCOUNT, 0) = 1 AND ai.INCOME_ID = 7658 THEN 808
      ELSE ai.INCOME_ID
    END AS NUMBER(10))                                           AS TRANSTYPE,
    /* + hareket (bagli tahakkuk); net dusum HDR = MAIN - SUM(KISMI) */
    ROUND(ABS(ai.AMOUNT), 2)                                     AS AMOUNT,
    ROUND(CASE WHEN NVL(ip.IS_VAT_INCOME, 0) = 1 THEN 0 ELSE ABS(ai.AMOUNT) END, 2) AS TLTOTAL,
    ROUND(CASE WHEN NVL(ip.IS_VAT_INCOME, 0) = 1 THEN ABS(ai.AMOUNT) ELSE 0 END, 2) AS TAX,
    ROUND(ABS(ai.AMOUNT), 2)                                     AS GRANDTOTAL,
    /* ASCII-safe — energy 590 Turkce LINEEXP yazabilir */
    CAST(
      'Kismi Eksilten EKS=' || TO_CHAR(ec.EKS_ACTION_ID)
      AS VARCHAR2(100)
    )                                                            AS LINEEXP,
    CAST(ai.ID AS NUMBER(12))                                    AS ABYS_INCOME_ROW_ID,
    CAST(ai.INCOME_ID AS NUMBER(10))                             AS ABYS_INCOME_ID,
    /* energy 590: ABYS_ID = ABYS_INCOME_ROW_ID */
    CAST(ai.ID AS NUMBER(12))                                    AS ABYS_ID,
    CAST(ec.EKS_ACTION_ID AS NUMBER(12))                         AS ABYS_EKS_ACTION_ID,
    CAST(ec.AGREEMENT_ID AS NUMBER(12))                          AS ABYS_AGREEMENT_ID,
    CAST('KISMI' AS VARCHAR2(10))                                AS OV_KIND
FROM MIGRATION.LS_OV_EKS_CLASS ec
JOIN SMS.CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = ec.EKS_ACTION_ID
LEFT JOIN SMS.CS_INCOME_PRM ip ON ip.ID = ai.INCOME_ID
WHERE ec.KIND = 'KISMI'
  AND ec.MAIN_LREF IS NOT NULL
  AND ai.ID BETWEEN 1 AND 2147483647;

CREATE UNIQUE INDEX MIGRATION.IX_OV_KISMI_IL ON MIGRATION.LS_OV_KISMI_INVLINES (LREF) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_OV_KISMI_IL_INV ON MIGRATION.LS_OV_KISMI_INVLINES (INVOICEREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_KISMI_IL NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_KISMI_IL_INV NOPARALLEL;

-- =============================================================================
-- 7) KISMI → MAIN baslik rebuild + EXPLAIN not
--    Tutar: MAIN - SUM(+KISMI)   |  EXPLAIN_NOTE: Kismi Eksilten EKS=...
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_KISMI_HDR PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_KISMI_HDR NOLOGGING AS
SELECT
    m.LREF,
    ROUND(GREATEST(0, NVL(m.TLTOTAL, 0) - NVL(k.SUM_TL, 0)), 2) AS TLTOTAL,
    ROUND(GREATEST(0, NVL(m.TAX, 0) - NVL(k.SUM_TAX, 0)), 2) AS TAX,
    ROUND(GREATEST(0, NVL(m.GRANDTOTAL, 0) - NVL(k.SUM_GRAND, 0)), 2) AS GRANDTOTAL,
    ROUND(GREATEST(0, NVL(m.PAYABLETOTAL, 0) - NVL(k.SUM_GRAND, 0)), 2) AS PAYABLETOTAL,
    m.ABYS_AGREEMENT_ID,
    CAST(
      SUBSTR(
        'Kismi Eksilten ' || NVL(k.EKS_LIST, ''),
        1,
        250
      ) AS VARCHAR2(250)
    )                                                            AS EXPLAIN_NOTE
FROM MIGRATION.LS_INVOICE m
JOIN (
    SELECT
           k.INVOICEREF,
           SUM(k.TLTOTAL) SUM_TL,
           SUM(k.TAX) SUM_TAX,
           SUM(k.GRANDTOTAL) SUM_GRAND,
           MAX(e.EKS_LIST) AS EKS_LIST
    FROM MIGRATION.LS_OV_KISMI_INVLINES k
    JOIN (
        SELECT
               INVOICEREF,
               SUBSTR(
                 LISTAGG('EKS=' || TO_CHAR(ABYS_EKS_ACTION_ID), '; ')
                   WITHIN GROUP (ORDER BY ABYS_EKS_ACTION_ID),
                 1,
                 200
               ) AS EKS_LIST
        FROM (
            SELECT DISTINCT INVOICEREF, ABYS_EKS_ACTION_ID
            FROM MIGRATION.LS_OV_KISMI_INVLINES
        )
        GROUP BY INVOICEREF
    ) e ON e.INVOICEREF = k.INVOICEREF
    GROUP BY k.INVOICEREF
) k ON k.INVOICEREF = m.LREF;

CREATE UNIQUE INDEX MIGRATION.IX_OV_KISMI_HDR ON MIGRATION.LS_OV_KISMI_HDR (LREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_KISMI_HDR NOPARALLEL;

-- =============================================================================
-- 7b) KISMI → MAIN borc PAYTRANS hedefi (v09 R32 PT rebuild)
-- Energy: mevcut IOCODE=0 PT UPDATE; yoksa INSERT (LREF=IDENTITY / 575 modeli)
-- LREF burada = MAIN.LREF (esleme anahtari; energy INSERT IDENTITY kullanabilir)
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_KISMI_PAYTRANS PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_KISMI_PAYTRANS NOLOGGING AS
SELECT
    h.LREF                                                       AS LREF,
    h.LREF                                                       AS INVOICEREF,
    NVL(m.TYPE, 119)                                             AS TYPE,
    CAST(0 AS NUMBER(3))                                         AS IOCODE,
    CAST(NULL AS NUMBER)                                         AS CROSSREF,
    CAST(174 AS NUMBER)                                          AS PAYTYPE,
    CAST(113 AS NUMBER)                                          AS TRANSTYPE,
    CAST(103 AS NUMBER)                                          AS LINETYPE,
    CAST(0 AS NUMBER)                                            AS INST_NR,
    m.DATE_,
    h.TLTOTAL,
    h.TAX,
    h.GRANDTOTAL,
    h.PAYABLETOTAL,
    CAST(0 AS NUMBER)                                            AS PAID,
    CAST(0 AS NUMBER(1))                                         AS CANCELED,
    m.CLIENTREF,
    m.ABYS_ID,
    m.ABYS_ACCOUNT_ID,
    h.ABYS_AGREEMENT_ID,
    CAST('KISMI' AS VARCHAR2(10))                                AS OV_KIND
FROM MIGRATION.LS_OV_KISMI_HDR h
JOIN MIGRATION.LS_INVOICE m ON m.LREF = h.LREF;

CREATE UNIQUE INDEX MIGRATION.IX_OV_KISMI_PT ON MIGRATION.LS_OV_KISMI_PAYTRANS (LREF) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_OV_KISMI_PT_INV ON MIGRATION.LS_OV_KISMI_PAYTRANS (INVOICEREF) PARALLEL 56 NOLOGGING;
ALTER INDEX MIGRATION.IX_OV_KISMI_PT NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_KISMI_PT_INV NOPARALLEL;

-- =============================================================================
-- 7c) AGR indexes (590 energy LOOP / izgazMGR parity)
-- =============================================================================
CREATE INDEX MIGRATION.IX_OV_IADE_INV_AGR ON MIGRATION.LS_OV_IADE_INVOICE (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_OV_MAIN_UPD_AGR ON MIGRATION.LS_OV_MAIN_UPD (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_OV_IADE_IL_AGR ON MIGRATION.LS_OV_IADE_INVLINES (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_OV_IADE_PT_AGR ON MIGRATION.LS_OV_IADE_PAYTRANS (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_OV_KISMI_IL_AGR ON MIGRATION.LS_OV_KISMI_INVLINES (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_OV_KISMI_HDR_AGR ON MIGRATION.LS_OV_KISMI_HDR (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_OV_KISMI_PT_AGR ON MIGRATION.LS_OV_KISMI_PAYTRANS (ABYS_AGREEMENT_ID) PARALLEL 56 NOLOGGING;
CREATE INDEX MIGRATION.IX_OV_EKS_CLASS_AGR ON MIGRATION.LS_OV_EKS_CLASS (AGREEMENT_ID) PARALLEL 56 NOLOGGING;

ALTER INDEX MIGRATION.IX_OV_IADE_INV_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_MAIN_UPD_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_IADE_IL_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_IADE_PT_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_KISMI_IL_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_KISMI_HDR_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_KISMI_PT_AGR NOPARALLEL;
ALTER INDEX MIGRATION.IX_OV_EKS_CLASS_AGR NOPARALLEL;

-- =============================================================================
-- 8) GATE / RECON
-- =============================================================================
SELECT 'CLASS' AS K, KIND AS V, COUNT(*) AS N
FROM MIGRATION.LS_OV_EKS_CLASS
GROUP BY KIND
UNION ALL
SELECT 'IADE_INV', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_IADE_INVOICE
UNION ALL
SELECT 'IADE_IL', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_IADE_INVLINES
UNION ALL
SELECT 'IADE_PT', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_IADE_PAYTRANS
UNION ALL
SELECT 'MAIN_UPD', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_MAIN_UPD
UNION ALL
SELECT 'KISMI_IL', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_KISMI_INVLINES
UNION ALL
SELECT 'KISMI_HDR', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_KISMI_HDR
UNION ALL
SELECT 'KISMI_PT', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_KISMI_PAYTRANS
UNION ALL
SELECT 'SKIP_ASIM', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_EKS_SKIP
ORDER BY 1, 2;

-- Orphan: TAM ama MAIN yok
SELECT 'TAM_NO_MAIN' AS ISSUE, COUNT(*) AS N
FROM MIGRATION.LS_OV_EKS_CLASS
WHERE KIND = 'TAM' AND MAIN_LREF IS NULL;

-- KISMI: negatif tutar olmamali (+ model)
SELECT 'KISMI_NEG_AMT' AS ISSUE, COUNT(*) AS N
FROM MIGRATION.LS_OV_KISMI_INVLINES
WHERE NVL(AMOUNT, 0) < 0 OR NVL(GRANDTOTAL, 0) < 0;

-- KISMI HDR ↔ PT 1:1 + tutar
SELECT
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_KISMI_HDR) AS KISMI_HDR,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_KISMI_PAYTRANS) AS KISMI_PT,
    (SELECT COUNT(*)
     FROM MIGRATION.LS_OV_KISMI_HDR h
     JOIN MIGRATION.LS_OV_KISMI_PAYTRANS p ON p.LREF = h.LREF
     WHERE NVL(h.PAYABLETOTAL, 0) <> NVL(p.PAYABLETOTAL, 0)) AS HDR_PT_PAYABLE_DIFF
FROM DUAL;

-- ENERGY bridge checks
SELECT 'IADE_IL_ABYS_NE_LREF' AS ISSUE, COUNT(*) AS N
FROM MIGRATION.LS_OV_IADE_INVLINES WHERE NVL(ABYS_ID, -1) <> NVL(LREF, -2);
SELECT 'IADE_INV_LREF_GT_INT' AS ISSUE, COUNT(*) AS N
FROM MIGRATION.LS_OV_IADE_INVOICE WHERE LREF > 2147483647 OR LREF < 1;
SELECT 'IADE_IL_LREF_GT_INT' AS ISSUE, COUNT(*) AS N
FROM MIGRATION.LS_OV_IADE_INVLINES WHERE LREF > 2147483647 OR LREF < 1;

-- TAM ↔ IADE 1:1
SELECT
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_EKS_CLASS WHERE KIND='TAM' AND MAIN_LREF IS NOT NULL) AS TAM,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_IADE_INVOICE) AS IADE,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_MAIN_UPD) AS MAIN_UPD,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_IADE_PAYTRANS) AS IADE_PT
FROM DUAL;

PROMPT ========== 20 EKSILTEN OVERLAY OK — sonraki: 27_gate veya 30 tahsilat ==========
/
