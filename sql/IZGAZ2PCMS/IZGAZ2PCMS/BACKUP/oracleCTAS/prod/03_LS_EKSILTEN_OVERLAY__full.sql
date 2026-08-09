-- =============================================================================
-- ADIM 4a — EKSILTEN OVERLAY (TAM → IADE + KISMI eksi satir)
-- Ortam : Oracle 11.2 | Schema: MIGRATION | Kaynak: SMS
-- Onkosul: MIGRATION.LS_INVOICE + LS_INVLINES (Adim 1–2) mevcut
-- MOD: FULL — tum LS_INVOICE / hesaplar (MIG_PARAM zorunlulugu YOK)
--
-- Bu CTAS Adim-1 MAIN'i YENIDEN URETMEZ. Delta uretir:
--   LS_OV_EKS_CLASS     — TAM / KISMI / ASIM
--   LS_OV_IADE_INVOICE  — IADE baslik (LREF=1.6B+EKS_ACTION)
--   LS_OV_IADE_INVLINES — IADE satir  (LREF=1.7B+MAIN_LINE.LREF)
--   LS_OV_IADE_PAYTRANS — IADE alacak PT (CreateReverse; IOCODE=1)
--   LS_OV_MAIN_UPD      — MAIN RETURN_TARGET / CANCEL_* / CLOSED
--   LS_OV_KISMI_INVLINES— eksi satir (INVOICEREF=MAIN.LREF)
--   LS_OV_KISMI_HDR     — MAIN baslik net tutar (rebuild)
--
-- Hariç (sonraki Adim 4b/5): CancelInvoices iade tahsilat, normal tahsilat
--
-- Kopru: MAIN.LREF = ABYS_ACTION_ID (Adim1/571) — ACCOUNT.ID DEGIL
-- IADE TYPE=92 IOCODE=1 EXPLAIN='IADE FATURASI' CANCEL_REASON_ID=6
-- =============================================================================

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;

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

CREATE INDEX MIGRATION.IX_OV_EKS_KIND ON MIGRATION.LS_OV_EKS_CLASS (KIND);
CREATE UNIQUE INDEX MIGRATION.IX_OV_EKS_ACT ON MIGRATION.LS_OV_EKS_CLASS (EKS_ACTION_ID);

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
    1600000000 + ec.EKS_ACTION_ID                                AS LREF,
    CAST(1 AS NUMBER(3))                                         AS IOCODE,
    /* FICHENO: son 7 hane zero-pad — LPAD(LREF,7) KIRPMAZ */
    'I' || LPAD(TO_CHAR(MOD(1600000000 + ec.EKS_ACTION_ID, 10000000)), 7, '0') AS FICHENO,
    CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
         THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END AS DATE_,
    CASE WHEN EXTRACT(YEAR FROM NVL(ec.MAIN_DUEDATE, ec.EKS_DATE)) < 1753
         THEN ADD_MONTHS(NVL(ec.MAIN_DUEDATE, ec.EKS_DATE), 24000)
         ELSE NVL(ec.MAIN_DUEDATE, ec.EKS_DATE) END              AS DUEDATE,
    CAST(92 AS NUMBER(3))                                        AS TYPE,
    ec.CLIENTREF,
    ROUND(ec.MAIN_TLTOTAL, 2)                                    AS TLTOTAL,
    NVL(ec.CURID, 160)                                           AS CURID,
    ROUND(ec.MAIN_GRANDTOTAL, 2)                                 AS CURTOTAL,
    CAST('IADE FATURASI' AS VARCHAR2(250))                       AS EXPLAIN,
    CAST(0 AS NUMBER(1))                                         AS CANCELED,   -- zorunlu 0
    ec.OWNERREF,
    NVL(ec.OWNERTYPE, 91)                                        AS OWNERTYPE,
    ROUND(ec.MAIN_TAX, 2)                                        AS TAX,
    CAST(0 AS NUMBER)                                            AS DV,
    ROUND(ec.MAIN_GRANDTOTAL, 2)                                 AS GRANDTOTAL,
    CAST(0 AS NUMBER)                                            AS PRINTCOUNT,
    ROUND(ec.MAIN_PAYABLETOTAL, 2)                               AS PAYABLETOTAL,
    CAST(1 AS NUMBER(1))                                         AS CLOSED,
    ec.MAIN_LREF                                                 AS RETURN_SOURCE_INVREF,
    CAST(NULL AS NUMBER)                                         AS RETURN_TARGET_INVREF,
    ec.FITNO                                                     AS FITNO,
    ec.BN_TYPE                                                   AS BN_TYPE,
    ROUND(NVL(ec.MAIN_AMOUNT, ec.MAIN_PAYABLETOTAL), 2)          AS AMOUNT,
    ec.PERIOD                                                    AS PERIOD,
    NVL(ec.HAS_DISCOUNT, 0)                                      AS HAS_DISCOUNT,
    ROUND(NVL(ec.DISCOUNT_AMOUNT, 0), 2)                         AS DISCOUNT_AMOUNT,
    CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
         THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END AS ADDDATE,
    ec.EKS_USER_ID                                               AS ADDUSER,
    ec.EKS_ACTION_ID                                             AS ABYS_ID,
    ec.ACCOUNT_ID                                                AS ABYS_ACCOUNT_ID,
    CAST(2 AS NUMBER)                                            AS ABYS_ACTION_TYPE_ID,
    ec.AGREEMENT_ID                                              AS ABYS_AGREEMENT_ID,
    ec.MAIN_LREF                                                 AS ABYS_MAIN_LREF,
    ec.EKS_ACTION_ID                                             AS ABYS_EKS_ACTION_ID,
    CAST('IADE' AS VARCHAR2(10))                                 AS OV_KIND
FROM MIGRATION.LS_OV_EKS_CLASS ec
WHERE ec.KIND = 'TAM'
  AND ec.MAIN_LREF IS NOT NULL;

CREATE UNIQUE INDEX MIGRATION.IX_OV_IADE_INV ON MIGRATION.LS_OV_IADE_INVOICE (LREF);

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

CREATE UNIQUE INDEX MIGRATION.IX_OV_MAIN_UPD ON MIGRATION.LS_OV_MAIN_UPD (LREF);

-- =============================================================================
-- 4) TAM → IADE INVLINES (MAIN satirlarinin pozitif kopyasi)
-- LREF = 2110000000 + ROW_NUMBER  (1.7B+source_line INT tasmasi yapar)
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_IADE_INVLINES PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_IADE_INVLINES NOLOGGING AS
SELECT
    2110000000 + ROW_NUMBER() OVER (ORDER BY ec.EKS_ACTION_ID, il.LINENR, il.LREF) AS LREF,
    1600000000 + ec.EKS_ACTION_ID                                AS INVOICEREF,
    il.CLIENTREF,
    CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
         THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END AS DATE_,
    CAST(92 AS NUMBER(3))                                        AS TYPE,
    il.LINENR,
    il.TRANSTYPE,
    ROUND(ABS(il.AMOUNT), 2)                                     AS AMOUNT,
    ROUND(ABS(il.TLTOTAL), 2)                                    AS TLTOTAL,
    ROUND(ABS(il.TAX), 2)                                        AS TAX,
    ROUND(ABS(il.GRANDTOTAL), 2)                                 AS GRANDTOTAL,
    /* LINEEXP: MAIN satirdan kopya (UTF-8 dump bozulursa energy 590 MAIN'den yeniden uretir) */
    CAST('IADE ' || NVL(il.LINEEXP, TO_CHAR(il.TRANSTYPE)) AS VARCHAR2(100)) AS LINEEXP,
    il.ABYS_INCOME_ROW_ID,
    il.ABYS_INCOME_ID,
    ec.EKS_ACTION_ID                                             AS ABYS_EKS_ACTION_ID,
    ec.AGREEMENT_ID                                              AS ABYS_AGREEMENT_ID,
    il.LREF                                                      AS ABYS_SOURCE_LINE_LREF,
    CAST('IADE' AS VARCHAR2(10))                                 AS OV_KIND
FROM MIGRATION.LS_OV_EKS_CLASS ec
JOIN MIGRATION.LS_INVLINES il
  ON il.INVOICEREF = ec.MAIN_LREF
WHERE ec.KIND = 'TAM'
  AND ec.MAIN_LREF IS NOT NULL;

CREATE UNIQUE INDEX MIGRATION.IX_OV_IADE_IL ON MIGRATION.LS_OV_IADE_INVLINES (LREF);
CREATE INDEX MIGRATION.IX_OV_IADE_IL_INV ON MIGRATION.LS_OV_IADE_INVLINES (INVOICEREF);

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
    CAST(NULL AS NUMBER)                                         AS CROSSREF,
    CAST(174 AS NUMBER)                                          AS PAYTYPE,
    CAST(113 AS NUMBER)                                          AS TRANSTYPE,
    CAST(103 AS NUMBER)                                          AS LINETYPE,
    CAST(0 AS NUMBER)                                            AS INST_NR,
    i.DATE_,
    i.PAYABLETOTAL,
    CAST(0 AS NUMBER)                                            AS PAID,
    CAST(0 AS NUMBER(1))                                         AS CANCELED,
    i.CLIENTREF,
    i.ABYS_ID,
    i.ABYS_ACCOUNT_ID,
    i.ABYS_AGREEMENT_ID,
    i.ABYS_EKS_ACTION_ID,
    i.ABYS_MAIN_LREF,
    CAST('IADE' AS VARCHAR2(10))                                 AS OV_KIND
FROM MIGRATION.LS_OV_IADE_INVOICE i;

CREATE UNIQUE INDEX MIGRATION.IX_OV_IADE_PT ON MIGRATION.LS_OV_IADE_PAYTRANS (LREF);

-- =============================================================================
-- 6) KISMI → eksi INVLINES (ayni MAIN INVOICEREF)
-- LREF = CS_ACCOUNT_INCOME.ID  (Adim2'de type=2 income yok → carpisma yok)
--        NOT: 1.9B+id INT tasmasi (income_id ~248M → >2^31-1)
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_KISMI_INVLINES PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_KISMI_INVLINES NOLOGGING AS
SELECT
    ai.ID                                                        AS LREF,
    ec.MAIN_LREF                                                 AS INVOICEREF,
    ec.CLIENTREF,
    CASE WHEN EXTRACT(YEAR FROM ec.EKS_DATE) < 1753
         THEN ADD_MONTHS(ec.EKS_DATE, 24000) ELSE ec.EKS_DATE END AS DATE_,
    NVL(ec.MAIN_TYPE, 119)                                       AS TYPE,
    CAST(ROW_NUMBER() OVER (PARTITION BY ec.MAIN_LREF ORDER BY ai.ID) AS NUMBER(5)) AS LINENR,
    CASE
      WHEN NVL(ai.IS_DISCOUNT, 0) = 1 AND ai.INCOME_ID = 939 THEN 807
      WHEN NVL(ai.IS_DISCOUNT, 0) = 1 AND ai.INCOME_ID = 7658 THEN 808
      ELSE ai.INCOME_ID
    END                                                          AS TRANSTYPE,
    ROUND(-ABS(ai.AMOUNT), 2)                                    AS AMOUNT,
    ROUND(CASE WHEN NVL(ip.IS_VAT_INCOME, 0) = 1 THEN 0 ELSE -ABS(ai.AMOUNT) END, 2) AS TLTOTAL,
    ROUND(CASE WHEN NVL(ip.IS_VAT_INCOME, 0) = 1 THEN -ABS(ai.AMOUNT) ELSE 0 END, 2) AS TAX,
    ROUND(-ABS(ai.AMOUNT), 2)                                    AS GRANDTOTAL,
    /* ASCII-safe sabit - energy 590 N'Kismi Eksilten' yazar (JDBC Turkce bozulmasin) */
    CAST('Kismi Eksilten' AS VARCHAR2(100))                      AS LINEEXP,
    ai.ID                                                        AS ABYS_INCOME_ROW_ID,
    ai.INCOME_ID                                                 AS ABYS_INCOME_ID,
    ec.EKS_ACTION_ID                                             AS ABYS_EKS_ACTION_ID,
    ec.AGREEMENT_ID                                              AS ABYS_AGREEMENT_ID,
    CAST('KISMI' AS VARCHAR2(10))                                AS OV_KIND
FROM MIGRATION.LS_OV_EKS_CLASS ec
JOIN SMS.CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = ec.EKS_ACTION_ID
LEFT JOIN SMS.CS_INCOME_PRM ip ON ip.ID = ai.INCOME_ID
WHERE ec.KIND = 'KISMI'
  AND ec.MAIN_LREF IS NOT NULL;

CREATE UNIQUE INDEX MIGRATION.IX_OV_KISMI_IL ON MIGRATION.LS_OV_KISMI_INVLINES (LREF);
CREATE INDEX MIGRATION.IX_OV_KISMI_IL_INV ON MIGRATION.LS_OV_KISMI_INVLINES (INVOICEREF);

-- =============================================================================
-- 7) KISMI → MAIN baslik rebuild (mevcut MAIN + yeni eksi satirlar)
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_KISMI_HDR PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_KISMI_HDR NOLOGGING AS
SELECT
    m.LREF,
    ROUND(NVL(m.TLTOTAL, 0) + NVL(k.SUM_TL, 0), 2)               AS TLTOTAL,
    ROUND(NVL(m.TAX, 0) + NVL(k.SUM_TAX, 0), 2)                  AS TAX,
    ROUND(NVL(m.GRANDTOTAL, 0) + NVL(k.SUM_GRAND, 0), 2)         AS GRANDTOTAL,
    ROUND(NVL(m.PAYABLETOTAL, 0) + NVL(k.SUM_GRAND, 0), 2)       AS PAYABLETOTAL,
    m.ABYS_AGREEMENT_ID
FROM MIGRATION.LS_INVOICE m
JOIN (
    SELECT INVOICEREF,
           SUM(TLTOTAL) SUM_TL,
           SUM(TAX) SUM_TAX,
           SUM(GRANDTOTAL) SUM_GRAND
    FROM MIGRATION.LS_OV_KISMI_INVLINES
    GROUP BY INVOICEREF
) k ON k.INVOICEREF = m.LREF;

CREATE UNIQUE INDEX MIGRATION.IX_OV_KISMI_HDR ON MIGRATION.LS_OV_KISMI_HDR (LREF);

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
SELECT 'SKIP_ASIM', 'CNT', COUNT(*) FROM MIGRATION.LS_OV_EKS_SKIP
ORDER BY 1, 2;

-- Orphan: TAM ama MAIN yok
SELECT 'TAM_NO_MAIN' AS ISSUE, COUNT(*) AS N
FROM MIGRATION.LS_OV_EKS_CLASS
WHERE KIND = 'TAM' AND MAIN_LREF IS NULL;

-- TAM ↔ IADE 1:1
SELECT
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_EKS_CLASS WHERE KIND='TAM' AND MAIN_LREF IS NOT NULL) AS TAM,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_IADE_INVOICE) AS IADE,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_MAIN_UPD) AS MAIN_UPD,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_IADE_PAYTRANS) AS IADE_PT
FROM DUAL;

PROMPT ADIM4a EKSILTEN OVERLAY OK — sonraki: dump → izgazMGR → 590 energy apply
/
