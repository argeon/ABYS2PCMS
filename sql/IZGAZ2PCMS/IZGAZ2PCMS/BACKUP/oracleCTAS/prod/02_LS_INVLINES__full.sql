-- MOD: FULL — LS_INVOICE driver (AGR filtresi yok; 01_LS_INVOICE__full onkosul)
-- =============================================================================
-- LS_INVLINES CTAS  |  ADIM 2 — Borc faturasi gelir satirlari
-- Kaynak : SMS.CS_ACCOUNT_INCOME (+ CS_INCOME_PRM)
-- Hedef  : MIGRATION.LS_INVLINES  → izgazMGR.dbo.LS_INVLINES → energy (581)
-- Oracle 11.2
--
-- Onkosul : MIGRATION.LS_INVOICE (Adim 1) mevcut olmali
-- Grain   : Adim-1 faturalarina bagli income satirlari
--
-- Anahtarlar (581 uyumu):
--   LREF              = CS_ACCOUNT_INCOME.ID          (IDENTITY_INSERT)
--   INVOICEREF        = LS_INVOICE.LREF               (= ABYS_ACTION_ID)
--   ABYS_INCOME_ROW_ID= CS_ACCOUNT_INCOME.ID          (= ABYS_ID hedefte)
--   TRANSTYPE         = INCOME_ID (indirim: 807/808)
--
-- Tutar (Adim 1 ile ayni): ai.AMOUNT  (STATUS carpimi YOK; ABYS_STATUS saklanir)
--   KDV satiri (IS_VAT_INCOME=1): TAX=AMOUNT, TLTOTAL=0, GRANDTOTAL=AMOUNT
--   Diger:                         TLTOTAL=AMOUNT, TAX=0, GRANDTOTAL=AMOUNT
--
-- 581 turetim:
--   UNITPRICE ← ABYS_UNIT_PRICE | AMOUNT ← ABYS_QUANTITY | CURID=160 CURRATE=1
--
-- Bu dosyada YOK: eksilten / tahsilat / SPEFEE dual-write (958/1929 satir yine yazilir)
-- =============================================================================

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;

-- Onkosul kontrol
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM ALL_TABLES
   WHERE OWNER = 'MIGRATION' AND TABLE_NAME = 'LS_INVOICE';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20001,
      'MIGRATION.LS_INVOICE yok. Once Adim 1 (LS_INVOICE.sql) calistirin.');
  END IF;
END;
/

-- =============================================================================
-- MAIN: LS_INVLINES  (hedef kolon sirasi ≈ 580/581 + ABYS_* bridge)
-- =============================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_INVLINES PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE MIGRATION.LS_INVLINES
NOLOGGING
PARALLEL 8
AS
SELECT /*+ PARALLEL(8) */

    /* --- PCMS hedef kolonlar --- */
    ai.ID                                                         AS LREF,
    inv.LREF                                                      AS INVOICEREF,
    inv.CLIENTREF                                                 AS CLIENTREF,

    CASE
      WHEN EXTRACT(YEAR FROM NVL(aa.ACTION_DATE, inv.DATE_)) < 1753
      THEN ADD_MONTHS(NVL(aa.ACTION_DATE, inv.DATE_), 24000)
      ELSE NVL(aa.ACTION_DATE, inv.DATE_)
    END                                                           AS DATE_,

    CAST(
      CASE
        WHEN NVL(ai.IS_DISCOUNT, 0) = 1 THEN 103
        ELSE NVL(inv.TYPE, 119)
      END AS NUMBER(3)
    )                                                             AS TYPE,

    CAST(
      ROW_NUMBER() OVER (
        PARTITION BY ai.ACCOUNT_ACTION_ID
        ORDER BY NVL(ip.ACCRUE_GROUP_ID, 0), ai.ID
      ) AS NUMBER(5)
    )                                                             AS LINENR,

    /* tutar kirilimi */
    CAST(
      CASE WHEN NVL(ip.IS_VAT_INCOME, 0) = 1 THEN 0
           ELSE NVL(ai.AMOUNT, 0)
      END AS NUMBER(18,3)
    )                                                             AS TLTOTAL,

    CAST(160 AS NUMBER(10))                                       AS CURID,
    CAST(1 AS NUMBER(18,6))                                       AS CURRATE,
    CAST(
      CASE WHEN NVL(ip.IS_VAT_INCOME, 0) = 1 THEN 0
           ELSE NVL(ai.AMOUNT, 0)
      END AS NUMBER(18,3)
    )                                                             AS CURTOTAL,

    CAST(aa.M3 AS NUMBER(18,6))                                   AS FIRSTREAD,
    CAST(aa.KWH AS NUMBER(18,6))                                  AS LASTREAD,

    CAST(
      CASE
        WHEN NVL(ai.IS_DISCOUNT, 0) = 1 AND ai.INCOME_ID = 939  THEN 807
        WHEN NVL(ai.IS_DISCOUNT, 0) = 1 AND ai.INCOME_ID = 7658 THEN 808
        ELSE NVL(ai.INCOME_ID, 0)
      END AS NUMBER(10)
    )                                                             AS TRANSTYPE,

    CAST(0 AS NUMBER(1))                                          AS CANCELED,

    CAST(
      CASE WHEN NVL(ip.IS_VAT_INCOME, 0) = 1 THEN NVL(ai.AMOUNT, 0)
           ELSE 0
      END AS NUMBER(18,3)
    )                                                             AS TAX,

    CAST(NVL(ai.AMOUNT, 0) AS NUMBER(18,3))                       AS GRANDTOTAL,

    CAST(
      CASE
        WHEN ai.INCOME_ID = 958  THEN 'SONRAKI AYA DEVIR'
        WHEN ai.INCOME_ID = 1929 THEN 'ONCEKI AYDAN DEVIR'
        WHEN NVL(ai.IS_DISCOUNT, 0) = 1 AND ai.INCOME_ID = 939  THEN 'Gaz Bedeli Indirim'
        WHEN NVL(ai.IS_DISCOUNT, 0) = 1 AND ai.INCOME_ID = 7658 THEN 'SKB Bedeli Indirim'
        ELSE SUBSTR(NVL(ipl.VALUE, ip.CODE), 1, 300)
      END AS VARCHAR2(300)
    )                                                             AS LINEEXP,

    CAST(NVL(ip.INCOME_TYPE, 0) AS NUMBER(10))                    AS LINETYPE,
    CAST(0 AS NUMBER(18,3))                                       AS DV,
    CAST(TO_CHAR(inv.FITNO) AS VARCHAR2(100))                     AS FITNO,
    CAST(NULL AS NUMBER(10))                                      AS CNTREF,
    CAST(NULL AS NUMBER(10))                                      AS LOGO_FIRMNR,
    CAST(NULL AS NUMBER(10))                                      AS LOGO_FICHEREF,
    CAST(NULL AS VARCHAR2(100))                                   AS LOGO_FICHENO,
    CAST(NULL AS NUMBER(10))                                      AS XTYPE,

    /* 581: UNITPRICE<-ABYS_UNIT_PRICE - staging ayni deger */
    CAST(ai.UNIT_PRICE AS NUMBER(19,8))                           AS UNITPRICE,
    CAST(NULL AS NUMBER(10))                                      AS SPEREF,
    /* 581: AMOUNT<-ABYS_QUANTITY */
    CAST(ai.QUANTITY AS NUMBER(18,6))                             AS AMOUNT,

    CAST(NULL AS DATE)                                            AS FIRST_DATE,
    CAST(NULL AS DATE)                                            AS LAST_DATE,
    CAST(NULL AS NUMBER(5))                                       AS "DAY",

    /* --- ABYS bridge (580/581) --- */
    ai.ID                                                         AS ABYS_INCOME_ROW_ID,
    ai.INCOME_ID                                                  AS ABYS_INCOME_ID,
    ai.ACCOUNT_ACTION_ID                                          AS ABYS_ACTION_ID,
    inv.ABYS_ACCOUNT_ID                                           AS ABYS_ACCOUNT_ID,
    inv.ABYS_REGISTER_ID                                          AS ABYS_REGISTER_ID,
    inv.ABYS_AGREEMENT_ID                                         AS ABYS_AGREEMENT_ID,
    inv.ABYS_ACTION_TYPE_ID                                       AS ABYS_ACTION_TYPE_ID,
    inv.ABYS_ACCRUE_TYPE_ID                                       AS ABYS_ACCRUE_TYPE_ID,
    CAST(NVL(ai.IS_DISCOUNT, 0) AS NUMBER(1))                     AS ABYS_IS_DISCOUNT,
    CAST(NVL(ip.IS_VAT_INCOME, 0) AS NUMBER(1))                   AS ABYS_IS_VAT_INCOME,
    CAST(NVL(ip.IS_DEPOSIT, 0) AS NUMBER(1))                      AS ABYS_IS_DEPOSIT,
    CAST(NVL(ip.IS_OVERDUE_INCOME, 0) AS NUMBER(1))               AS ABYS_IS_OVERDUE_INCOME,
    CAST(NVL(ip.IS_LEGAL_FEE, 0) AS NUMBER(1))                    AS ABYS_IS_LEGAL_FEE,
    CAST(SUBSTR(ip.CODE, 1, 10) AS VARCHAR2(10))                  AS ABYS_INCOME_CODE,
    CAST(ai.AMOUNT AS NUMBER(18,3))                               AS ABYS_AMOUNT_RAW,
    CAST(ai.STATUS AS NUMBER(5))                                  AS ABYS_STATUS,
    CAST(ai.QUANTITY AS NUMBER(18,6))                             AS ABYS_QUANTITY,
    CAST(ai.UNIT_PRICE AS NUMBER(19,8))                           AS ABYS_UNIT_PRICE,
    CAST(ai.AMOUNT1 AS NUMBER(18,3))                              AS ABYS_AMOUNT1,
    CAST(ai.AMOUNT2 AS NUMBER(18,3))                              AS ABYS_AMOUNT2,
    CAST(ai.AMOUNT3 AS NUMBER(18,3))                              AS ABYS_AMOUNT3,
    CAST(ai.AMOUNT4 AS NUMBER(18,3))                              AS ABYS_AMOUNT4,
    CAST(ai.AMOUNT5 AS NUMBER(18,3))                              AS ABYS_AMOUNT5,

    /* --- ek kontrol / operasyon (dump kalabilir - 581 SELECT etmez) --- */
    CAST(NVL(ip.ACCRUE_GROUP_ID, 0) AS NUMBER(10))                AS ABYS_ACCRUE_GROUP_ID,
    CAST(SUBSTR(NVL(ipl.VALUE, ip.CODE), 1, 200) AS VARCHAR2(200)) AS ABYS_INCOME_NAME

FROM SMS.CS_ACCOUNT_INCOME ai
JOIN MIGRATION.LS_INVOICE inv
  ON inv.ABYS_ACTION_ID = ai.ACCOUNT_ACTION_ID
LEFT JOIN SMS.CS_ACCOUNT_ACTION aa
  ON aa.ID = ai.ACCOUNT_ACTION_ID
LEFT JOIN SMS.CS_INCOME_PRM ip
  ON ip.ID = ai.INCOME_ID
LEFT JOIN SMS.CS_INCOME_PRM_LNG ipl
  ON ipl.PRM_ID = ip.ID
 AND ipl.LANG_ID = 1;

CREATE UNIQUE INDEX MIGRATION.IX_LS_IL_LREF ON MIGRATION.LS_INVLINES (LREF);
CREATE INDEX MIGRATION.IX_LS_IL_INVREF ON MIGRATION.LS_INVLINES (INVOICEREF);
CREATE INDEX MIGRATION.IX_LS_IL_ABYS_ACT ON MIGRATION.LS_INVLINES (ABYS_ACTION_ID);
CREATE INDEX MIGRATION.IX_LS_IL_ABYS_INC ON MIGRATION.LS_INVLINES (ABYS_INCOME_ID);
CREATE INDEX MIGRATION.IX_LS_IL_AGR ON MIGRATION.LS_INVLINES (ABYS_AGREEMENT_ID);

ALTER TABLE MIGRATION.LS_INVLINES NOPARALLEL LOGGING;

BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_INVLINES', degree => 8); END;
/

-- =============================================================================
-- DOGRULAMA (Adim-2 gate)
-- =============================================================================

-- V0: kapsam (Adim-1 faturalari)
SELECT
  (SELECT COUNT(*) FROM MIGRATION.LS_INVOICE) AS INV_CNT,
  (SELECT COUNT(*) FROM MIGRATION.LS_INVLINES) AS LINE_CNT,
  (SELECT COUNT(DISTINCT INVOICEREF) FROM MIGRATION.LS_INVLINES) AS INV_WITH_LINES
FROM DUAL;

-- V1: kaynak income vs hedef (ayni grain)
SELECT
  (SELECT COUNT(*)
     FROM SMS.CS_ACCOUNT_INCOME ai
     JOIN MIGRATION.LS_INVOICE inv ON inv.ABYS_ACTION_ID = ai.ACCOUNT_ACTION_ID
  ) AS SRC_CNT,
  (SELECT COUNT(*) FROM MIGRATION.LS_INVLINES) AS TGT_CNT
FROM DUAL;

-- V1b: LREF = ABYS_INCOME_ROW_ID; INVOICEREF = ABYS_ACTION_ID
SELECT
  SUM(CASE WHEN LREF <> ABYS_INCOME_ROW_ID THEN 1 ELSE 0 END) AS BAD_LREF,
  SUM(CASE WHEN INVOICEREF <> ABYS_ACTION_ID THEN 1 ELSE 0 END) AS BAD_INVREF,
  SUM(CASE WHEN INVOICEREF NOT IN (SELECT LREF FROM MIGRATION.LS_INVOICE) THEN 1 ELSE 0 END) AS ORPHAN_LINE
FROM MIGRATION.LS_INVLINES;

-- V2: baslik ↔ satir tutar mutabakati (fatura bazinda fark)
SELECT COUNT(*) AS INV_TUTAR_FARK
FROM (
  SELECT i.LREF,
         i.PAYABLETOTAL AS INV_AMT,
         NVL(l.SUM_G, 0) AS LINE_AMT
    FROM MIGRATION.LS_INVOICE i
    LEFT JOIN (
      SELECT INVOICEREF, SUM(GRANDTOTAL) AS SUM_G
        FROM MIGRATION.LS_INVLINES
       GROUP BY INVOICEREF
    ) l ON l.INVOICEREF = i.LREF
   WHERE ABS(NVL(i.PAYABLETOTAL, 0) - NVL(l.SUM_G, 0)) > 0.01
);

-- V2b: toplam
SELECT
  (SELECT SUM(PAYABLETOTAL) FROM MIGRATION.LS_INVOICE) AS INV_SUM,
  (SELECT SUM(GRANDTOTAL) FROM MIGRATION.LS_INVLINES) AS LINE_SUM,
  (SELECT SUM(TLTOTAL) FROM MIGRATION.LS_INVLINES) AS LINE_TL,
  (SELECT SUM(TAX) FROM MIGRATION.LS_INVLINES) AS LINE_TAX
FROM DUAL;

-- V3: income yok faturalar (Adim-1 INCOME_YOK ile uyum)
SELECT COUNT(*) AS INV_NO_LINES
FROM MIGRATION.LS_INVOICE i
WHERE NOT EXISTS (
  SELECT 1 FROM MIGRATION.LS_INVLINES l WHERE l.INVOICEREF = i.LREF
);

-- V4: TRANSTYPE / KDV / indirim ozeti
SELECT
  CASE
    WHEN ABYS_IS_DISCOUNT = 1 THEN 'INDIRIM'
    WHEN ABYS_IS_VAT_INCOME = 1 THEN 'KDV'
    WHEN ABYS_INCOME_ID IN (958, 1929) THEN 'DEVIR'
    WHEN ABYS_INCOME_ID IN (939, 7658) THEN 'GAZ_SKB'
    ELSE 'DIGER'
  END AS GRUP,
  COUNT(*) ADET,
  SUM(GRANDTOTAL) TOPLAM
FROM MIGRATION.LS_INVLINES
GROUP BY
  CASE
    WHEN ABYS_IS_DISCOUNT = 1 THEN 'INDIRIM'
    WHEN ABYS_IS_VAT_INCOME = 1 THEN 'KDV'
    WHEN ABYS_INCOME_ID IN (958, 1929) THEN 'DEVIR'
    WHEN ABYS_INCOME_ID IN (939, 7658) THEN 'GAZ_SKB'
    ELSE 'DIGER'
  END
ORDER BY 1;

-- V5: top income
SELECT ABYS_INCOME_ID, ABYS_INCOME_CODE, ABYS_INCOME_NAME,
       COUNT(*) ADET, SUM(GRANDTOTAL) TOPLAM
FROM MIGRATION.LS_INVLINES
GROUP BY ABYS_INCOME_ID, ABYS_INCOME_CODE, ABYS_INCOME_NAME
ORDER BY SUM(GRANDTOTAL) DESC;

-- Gate: SRC=TGT, BAD_*=0, INV_TUTAR_FARK=0, INV_SUM≈LINE_SUM
-- Sonraki: dump → izgazMGR → 571 → 581 → 575 (borç PT; 578 pilot)
/
