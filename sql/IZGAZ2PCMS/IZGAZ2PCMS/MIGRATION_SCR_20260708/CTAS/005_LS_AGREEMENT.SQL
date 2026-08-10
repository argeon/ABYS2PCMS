-- ============================================================
-- ABYS -> PCMS : LS_AGREEMENT staging (MIGRATION semasi)
-- Kaynak: SMS  |  Hedef: MIGRATION
-- Oracle 11.2 uyumlu. sqlplus'ta calistirin (GO yok, / var).
--
-- LREF:
--   KUL (CS_AGREEMENT)            -> LREF = CS_AGREEMENT.ID
--   ABN (CS_AGREEMENT_SUBSCRIBER) -> LREF = MAX(CS_AGREEMENT.ID) + 1..N
--                                    (AGR sonrasi sirali IDENTITY)
--
-- CTAS icinde (Energy 910 wire karsiligi):
--   ISACTIVE(KUL) = 1  → FITNO basina LREF DESC son sozlesme
--   PARID(KUL)         → ayni FLATID'deki ABN.LREF
--   IS_GS              = 0
--
-- Energy tarafinda kalan wire (LS_FLAT / LS_ITEMS migrate sonrasi):
--   FLATID = LS_FLAT.LREF  WHERE FITNO = ABYS_INSTALLATION_ID AND ENT_ID=4102
--   BNA_ID = LS_FLAT.BNA_ID (ayni join)
--   COUNTERSN/MODEL/MBAR = LS_005_ITEMS (COUNTERID = ITEMS.LREF)
--
-- Tarife:
--   MIGRATION.STG_TARIFF_MAP fiziksel stage tablo
--   Join: normalize edilmis NK_* anahtarlar (TRIM/UPPER/I-İ)
-- ============================================================
-- TERMINAL DUMP: Oracle INDEX / GATHER_TABLE_STATS yok (CTAS zincirinde tuketilmiyor; IX -> izgazMGR/energy).

-- ============================================================
-- 0) IDEMPOTENT DROP
-- ============================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_AGREEMENT PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.STG_TARIFF_MAP PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

-- Eski ad (gecis)
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.TMP_TARIFF_LOOKUP PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

-- ============================================================
-- 1) TARIFE MAP — fiziksel stage (GTT DEGIL)
--    PARALLEL CTAS slave session'lari GTT satirlarini goremez.
--    NK_* : TRIM + I/İ normalize + UPPER — join guvenilirligi icin.
-- ============================================================
CREATE TABLE MIGRATION.STG_TARIFF_MAP (
    ABYS_TARIFF_TYPE      VARCHAR2(100)  NOT NULL,
    ABYS_SKB_TARIFF_TYPE  VARCHAR2(100)  NOT NULL,
    ABYS_SUBSCRIBER_TYPE  VARCHAR2(100)  NOT NULL,
    PCMS_TARIFF_TYPE_NAME VARCHAR2(200),
    TP1                   VARCHAR2(10),
    BN_TYPE               NUMBER(5)      NOT NULL,
    NK_TARIFF             VARCHAR2(100)  NOT NULL,
    NK_SKB                VARCHAR2(100)  NOT NULL,
    NK_SUBSCRIBER         VARCHAR2(100)  NOT NULL
);

-- Normalize: TRIM, I/İ/ı tekillestir, UPPER
-- (Turkce karakter farklari join'i bozmasin)
INSERT INTO MIGRATION.STG_TARIFF_MAP (
    ABYS_TARIFF_TYPE, ABYS_SKB_TARIFF_TYPE, ABYS_SUBSCRIBER_TYPE,
    PCMS_TARIFF_TYPE_NAME, TP1, BN_TYPE,
    NK_TARIFF, NK_SKB, NK_SUBSCRIBER
)
SELECT
    t.ABYS_TARIFF_TYPE,
    t.ABYS_SKB_TARIFF_TYPE,
    t.ABYS_SUBSCRIBER_TYPE,
    t.PCMS_TARIFF_TYPE_NAME,
    t.TP1,
    t.BN_TYPE,
    UPPER(REPLACE(REPLACE(TRIM(t.ABYS_TARIFF_TYPE),     'İ','I'), 'ı','I')) AS NK_TARIFF,
    UPPER(REPLACE(REPLACE(TRIM(t.ABYS_SKB_TARIFF_TYPE), 'İ','I'), 'ı','I')) AS NK_SKB,
    UPPER(REPLACE(REPLACE(TRIM(t.ABYS_SUBSCRIBER_TYPE), 'İ','I'), 'ı','I')) AS NK_SUBSCRIBER
FROM (
    SELECT 'CNG 2.KADEME'       AS ABYS_TARIFF_TYPE, '4.KADEME' AS ABYS_SKB_TARIFF_TYPE, 'SANAYİ'          AS ABYS_SUBSCRIBER_TYPE, 'CNG 4.Kademe'               AS PCMS_TARIFF_TYPE_NAME, 'CNG' AS TP1, 151 AS BN_TYPE FROM DUAL UNION ALL
    SELECT 'CNG 2.KADEME',       '5.KADEME',  'SANAYİ',          'CNG 5.Kademe',               'CNG', 152 FROM DUAL UNION ALL
    SELECT 'EKMEK ÜRETİCİSİ',   '1.KADEME',  'TİCARİ VE DİĞER', 'Ekmek Üreticileri 1.Kademe', 'TIC', 201 FROM DUAL UNION ALL
    SELECT 'EKMEK ÜRETİCİSİ',   '2.KADEME',  'TİCARİ VE DİĞER', 'Ekmek Üreticileri 2.Kademe', 'TIC', 202 FROM DUAL UNION ALL
    SELECT 'EKMEK ÜRETİCİSİ',   '3.KADEME',  'TİCARİ VE DİĞER', 'Ekmek Üreticileri 3A.Kademe','TIC', 203 FROM DUAL UNION ALL
    SELECT 'ELEKTRİK 1.KADEME', '1.KADEME',  'SANAYİ',          '1.Kademe',                   'ELK', 138 FROM DUAL UNION ALL
    SELECT 'ELEKTRİK 2.KADEME', '3.KADEME',  'RESMI',           '3.Kademe B',                 'ELK', 141 FROM DUAL UNION ALL
    SELECT 'ELEKTRİK 2.KADEME', '4.KADEME',  'SANAYİ',          '4.Kademe',                   'ELK', 142 FROM DUAL UNION ALL
    SELECT 'ELEKTRİK 2.KADEME', '4.KADEME',  'RESMI',           '4.Kademe',                   'ELK', 142 FROM DUAL UNION ALL
    SELECT 'ELEKTRİK 2.KADEME', '5.KADEME',  'SANAYİ',          '5.Kademe',                   'ELK', 143 FROM DUAL UNION ALL
    SELECT 'GAZİ/ŞEHİT YAKINI', '1.KADEME',  'KONUT',           'Gazi/Şehit Konut 1',         'KON', 219 FROM DUAL UNION ALL
    SELECT 'IBADETHANE',         '1.KADEME',  'RESMI',           'IBD 1.Kademe',               'TIC', 186 FROM DUAL UNION ALL
    SELECT 'IBADETHANE',         '1.KADEME',  'KONUT',           'IBD 1.Kademe',               'TIC', 186 FROM DUAL UNION ALL
    SELECT 'IBADETHANE',         '1.KADEME',  'TİCARİ VE DİĞER', 'IBD 1.Kademe',               'TIC', 186 FROM DUAL UNION ALL
    SELECT 'IBADETHANE',         '1.KADEME',  'MERKEZİ ISINMA',  'IBD 1.Kademe',               'TIC', 186 FROM DUAL UNION ALL
    SELECT 'IBADETHANE',         '2.KADEME',  'TİCARİ VE DİĞER', 'IBD 2.Kademe',               'TIC', 187 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KADEME',  '1.KADEME',  'TİCARİ VE DİĞER', '1.Kademe',                   'TIC', 103 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KADEME',  '1.KADEME',  'RESMI',           '1.Kademe',                   'KAM', 110 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KADEME',  '1.KADEME',  'KONUT',           '1.Kademe',                   'TIC', 103 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KADEME',  '1.KADEME',  'SANAYİ',          '1.Kademe',                   'BSA', 124 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KADEME',  '2.KADEME',  'TİCARİ VE DİĞER', '2.Kademe',                   'TIC', 104 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KADEME',  '2.KADEME',  'RESMI',           '2.Kademe',                   'KAM', 111 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KADEME',  '2.KADEME',  'SANAYİ',          '2.Kademe',                   'BSA', 125 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KADEME',  '2.KADEME',  'KONUT',           '2.Kademe',                   'TIC', 104 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KADEME',  '3.KADEME',  'TİCARİ VE DİĞER', '3.Kademe A',                 'TIC', 105 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KADEME',  '3.KADEME',  'RESMI',           '3.Kademe A',                 'KAM', 112 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KADEME',  '3.KADEME',  'SANAYİ',          '3.Kademe A',                 'BSA', 126 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KONUT',   '1.KADEME',  'KONUT',           'Konut 1K',                   'KON',  96 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KONUT',   '1.KADEME',  'RESMI',           'Konut 1K',                   'KON',  96 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KONUT',   '2.KADEME',  'MERKEZİ ISINMA',  'Konut 2K',                   'KON',  97 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KONUT',   '2.KADEME',  'TİCARİ VE DİĞER', 'Konut 2K',                   'KON',  97 FROM DUAL UNION ALL
    SELECT 'SERBEST 1. KONUT',   '3.KADEME',  'MERKEZİ ISINMA',  'Konut 3aK',                  'KON',  98 FROM DUAL UNION ALL
    SELECT 'SERBEST 2. KADEME',  '1.KADEME',  'SANAYİ',          '1.Kademe',                   'BSA', 124 FROM DUAL UNION ALL
    SELECT 'SERBEST 2. KADEME',  '3.KADEME',  'RESMI',           '3.Kademe B',                 'KAM', 113 FROM DUAL UNION ALL
    SELECT 'SERBEST 2. KADEME',  '3.KADEME',  'SANAYİ',          '3.Kademe B',                 'BSA', 127 FROM DUAL UNION ALL
    SELECT 'SERBEST 2. KADEME',  '3.KADEME',  'TİCARİ VE DİĞER', '3.Kademe B',                 'TIC', 106 FROM DUAL UNION ALL
    SELECT 'SERBEST 2. KADEME',  '4.KADEME',  'SANAYİ',          '4.Kademe',                   'BSA', 128 FROM DUAL UNION ALL
    SELECT 'SERBEST 2. KADEME',  '4.KADEME',  'RESMI',           '4.Kademe',                   'KAM', 114 FROM DUAL UNION ALL
    SELECT 'SERBEST 2. KADEME',  '4.KADEME',  'TİCARİ VE DİĞER', '4.Kademe',                   'TIC', 107 FROM DUAL UNION ALL
    SELECT 'SERBEST 2. KADEME',  '5.KADEME',  'SANAYİ',          '5.Kademe',                   'BSA', 129 FROM DUAL UNION ALL
    SELECT 'SERBEST 2. KONUT',   '2.KADEME',  'MERKEZİ ISINMA',  'Konut 2K',                   'KON',  97 FROM DUAL UNION ALL
    SELECT 'SERBEST 2. KONUT',   '3.KADEME',  'MERKEZİ ISINMA',  'Konut 3aK',                  'KON',  98 FROM DUAL UNION ALL
    SELECT 'SERBEST 2. KONUT',   '4.KADEME',  'MERKEZİ ISINMA',  'Konut 4K',                   'KON', 100 FROM DUAL UNION ALL
    SELECT 'SERBEST OLMAYAN',    '1.KADEME',  'KONUT',           'Konut 1K',                   'KON',  96 FROM DUAL UNION ALL
    SELECT 'SERBEST OLMAYAN',    '1.KADEME',  'MERKEZİ ISINMA',  'Konut 1K',                   'KON',  96 FROM DUAL UNION ALL
    SELECT 'SERBEST OLMAYAN',    '1.KADEME',  'RESMI',           'Konut 1K',                   'KON',  96 FROM DUAL UNION ALL
    SELECT 'SERBEST OLMAYAN',    '2.KADEME',  'MERKEZİ ISINMA',  'Konut 2K',                   'KON',  97 FROM DUAL UNION ALL
    SELECT 'SERBEST OLMAYAN',    '2.KADEME',  'KONUT',           'Konut 2K',                   'KON',  97 FROM DUAL UNION ALL
    SELECT 'SERBEST OLMAYAN',    '3.KADEME',  'MERKEZİ ISINMA',  'Konut 3aK',                  'KON',  98 FROM DUAL UNION ALL
    SELECT 'TASIMA',             '1.KADEME',  'SANAYİ',          '1.Kademe',                   'BSA', 124 FROM DUAL UNION ALL
    SELECT 'TASIMA',             '3.KADEME',  'SANAYİ',          '3.Kademe A',                 'BSA', 126 FROM DUAL UNION ALL
    SELECT 'TASIMA',             '4.KADEME',  'SANAYİ',          '4.Kademe',                   'BSA', 128 FROM DUAL UNION ALL
    SELECT 'TASIMA',             '5.KADEME',  'SANAYİ',          '5.Kademe',                   'BSA', 129 FROM DUAL
) t;

COMMIT;

-- Cift anahtar kontrolu (normalize sonrasi)
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n
  FROM (
    SELECT NK_TARIFF, NK_SKB, NK_SUBSCRIBER
    FROM MIGRATION.STG_TARIFF_MAP
    GROUP BY NK_TARIFF, NK_SKB, NK_SUBSCRIBER
    HAVING COUNT(*) > 1
  );
  IF n > 0 THEN
    RAISE_APPLICATION_ERROR(-20001,
      'STG_TARIFF_MAP: ' || n || ' cift NK anahtar — map seed duzeltilmeli');
  END IF;
END;
/

CREATE UNIQUE INDEX MIGRATION.UX_STG_TARIFF_MAP_NK
    ON MIGRATION.STG_TARIFF_MAP (NK_TARIFF, NK_SKB, NK_SUBSCRIBER);

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'STG_TARIFF_MAP', cascade => TRUE);
END;
/

PROMPT ========== STG_TARIFF_MAP seed OK ==========
SELECT COUNT(*) AS MAP_SATIR FROM MIGRATION.STG_TARIFF_MAP;

-- ============================================================
-- 2) CTAS : MIGRATION.LS_AGREEMENT
--    LREF dis katmanda atanir (KUL=ID, ABN=MAX_KUL+RN)
--    Sonra: ISACTIVE(KUL son FITNO) + PARID(KUL→ABN FLATID)
-- ============================================================
CREATE TABLE MIGRATION.LS_AGREEMENT
NOLOGGING
PARALLEL 4
AS
SELECT
    w.LREF,
    w.TP2,
    w.ABYS_ID,
    -- KUL.PARID = ayni FLATID'deki ABN.LREF (910 wire)
    CASE
        WHEN w.TP2 = 'KUL' THEN
            MAX(CASE WHEN w.TP2 = 'ABN' THEN w.LREF END)
                OVER (PARTITION BY w.FLATID)
        ELSE w.PARID
    END                                                         AS PARID,
    w.FLATID,
    w.BNA_ID,
    w.AGR_SDATE,
    w.AGR_EDATE,
    w.PAY_SDATE,
    w.OPEN_DATE,
    w.ABYS_REFUND_DATE,
    w.BN_TYPE,
    w.SKB_TARIFF_TYPE_ID,
    w.TARIFF_TYPE_ID,
    w.FRMID,
    w.CON,
    w.TP1,
    w.TP3,
    w.FMETHOD,
    w.FPARID,
    w.FMANUAL,
    w.STATID,
    -- KUL.ISACTIVE = 1 sadece FITNO basina son LREF (910 wire)
    CASE
        WHEN w.TP2 = 'KUL' THEN
            CASE
                WHEN ROW_NUMBER() OVER (
                         PARTITION BY w.TP2, w.FITNO
                         ORDER BY w.LREF DESC
                     ) = 1
                THEN 1
                ELSE 0
            END
        ELSE w.ISACTIVE
    END                                                         AS ISACTIVE,
    w.ADDUSER,
    w.ADDDATE,
    w.UPDUSER,
    w.UPDDATE,
    w.NEEDPAY,
    w.CURTYPE,
    w.PAY_BANKREF,
    w.PAYTYPE,
    w.TAX,
    w.PAY_TOTAL,
    w.TLTOTAL,
    w.CURTOTAL,
    w.GRANDTOTAL,
    w.DV,
    w.Basinc,
    w.COUNTERMBAR,
    w.CALCPRESSID,
    w.SON_ODEME_GUNU,
    w.AGREEMENT_NUMBER,
    w.ISTAXFREE,
    w.ISDVFREE,
    w.ISOTVFREE,
    w.ISNOTCALCDV,
    w.NOTE,
    w.FITNO,
    w.INSTALLATION_STATUS_ID,
    w.TUKETIM_NOKTASI,
    w.COUNTER_STAT,
    w.Tip,
    w.COUNTERID,
    w.SERVICE_BOX_ID,
    w.HOUSEHOLDS_COUNT,
    w.FIRST_STARTUP_DATE,
    w.COUNTERSN,
    w.COUNTERMODEL,
    w.Cap,
    w.OPENED,
    w.IS_GS,
    w.IS_FIRST_USE,
    w.TRANS,
    w.OLREF,
    w.OLOC_ID,
    w.CLOSESTATID,
    w.FEE_COLLECTED,
    w.REFUND,
    w.HAS_USING_AGR,
    w.INV_PRINT_DATE,
    w.LASTREAD_DATE,
    w.EXPIRE_DEBTTIME,
    w.APP_ID,
    w.ABYS_SUBSCRIBER_TYPE,
    w.ABYS_SKB_TARIFF_TYPE,
    w.ABYS_TARIFF_TYPE,
    w.ABYS_INSTALLATION_STATUS,
    w.PCMS_TARIFF_TYPE_NAME,
    w.ABYS_DESC_NOTE,
    w.ABYS_PROJECT_STATUS
FROM (
SELECT
    CASE
        WHEN t.TP2 = 'KUL' THEN CAST(t.ABYS_ID AS NUMBER(12))
        ELSE CAST(
            m.MAX_KUL_ID
            + ROW_NUMBER() OVER (
                PARTITION BY t.TP2
                ORDER BY t.ADDDATE ASC NULLS LAST, t.ABYS_ID, t.TUKETIM_NOKTASI
              )
            AS NUMBER(12)
        )
    END                                                         AS LREF,
    t.TP2,
    t.ABYS_ID,
    t.PARID,
    t.FLATID,
    t.BNA_ID,
    t.AGR_SDATE,
    t.AGR_EDATE,
    t.PAY_SDATE,
    t.OPEN_DATE,
    t.ABYS_REFUND_DATE,
    t.BN_TYPE,
    t.SKB_TARIFF_TYPE_ID,
    t.TARIFF_TYPE_ID,
    t.FRMID,
    t.CON,
    t.TP1,
    t.TP3,
    t.FMETHOD,
    t.FPARID,
    t.FMANUAL,
    t.STATID,
    t.ISACTIVE,
    t.ADDUSER,
    t.ADDDATE,
    t.UPDUSER,
    t.UPDDATE,
    t.NEEDPAY,
    t.CURTYPE,
    t.PAY_BANKREF,
    t.PAYTYPE,
    t.TAX,
    t.PAY_TOTAL,
    t.TLTOTAL,
    t.CURTOTAL,
    t.GRANDTOTAL,
    t.DV,
    t.Basinc,
    t.COUNTERMBAR,
    t.CALCPRESSID,
    t.SON_ODEME_GUNU,
    t.AGREEMENT_NUMBER,
    t.ISTAXFREE,
    t.ISDVFREE,
    t.ISOTVFREE,
    t.ISNOTCALCDV,
    t.NOTE,
    t.FITNO,
    t.INSTALLATION_STATUS_ID,
    t.TUKETIM_NOKTASI,
    t.COUNTER_STAT,
    t.Tip,
    t.COUNTERID,
    t.SERVICE_BOX_ID,
    t.HOUSEHOLDS_COUNT,
    t.FIRST_STARTUP_DATE,
    t.COUNTERSN,
    t.COUNTERMODEL,
    t.Cap,
    t.OPENED,
    t.IS_GS,
    t.IS_FIRST_USE,
    t.TRANS,
    t.OLREF,
    t.OLOC_ID,
    t.CLOSESTATID,
    t.FEE_COLLECTED,
    t.REFUND,
    t.HAS_USING_AGR,
    t.INV_PRINT_DATE,
    t.LASTREAD_DATE,
    t.EXPIRE_DEBTTIME,
    t.APP_ID,
    t.ABYS_SUBSCRIBER_TYPE,
    t.ABYS_SKB_TARIFF_TYPE,
    t.ABYS_TARIFF_TYPE,
    t.ABYS_INSTALLATION_STATUS,
    t.PCMS_TARIFF_TYPE_NAME,
    t.ABYS_DESC_NOTE,
    t.ABYS_PROJECT_STATUS
FROM (

    -- ============================================================
    -- KUL: CS_AGREEMENT
    -- ============================================================
    SELECT
        'KUL'                                                   AS TP2,
        a.ID                                                    AS ABYS_ID,
        CAST(NULL AS NUMBER(10))                                AS PARID,

        -- Flat / Bina (BNA_ID = GIS_BUILDING_DOOR.CODE — LS_FLAT ile ayni)
        sub.BUILDING_FLAT_ID                                    AS FLATID,
        CAST(bd.CODE AS NUMBER(10))                             AS BNA_ID,

        -- Tarihler
        a.AGREEMENT_DATE                                        AS AGR_SDATE,
        a.CANCELLATION_DATE                                     AS AGR_EDATE,
        a.STARTING_DATE                                         AS PAY_SDATE,
        a.STARTUP_DATE                                          AS OPEN_DATE,
        a.REFUND_DATE                                           AS ABYS_REFUND_DATE,

        -- Tarife / BN_TYPE  (STG_TARIFF_MAP NK join)
        NVL(lk.BN_TYPE, -99)                                    AS BN_TYPE,
        a.SKB_TARIFF_TYPE_ID                                    AS SKB_TARIFF_TYPE_ID,
        a.TARIFF_TYPE_ID                                        AS TARIFF_TYPE_ID,
        CAST(NULL AS NUMBER(11))                                AS FRMID,
        a.BENEFITED_REGISTER_ID                                 AS CON,

        -- TP1
        NVL(
            lk.TP1,
            CASE a.SUBSCRIBER_TYPE_ID
                WHEN 1 THEN 'KON'
                WHEN 2 THEN 'KAM'
                WHEN 3 THEN 'TIC'
                WHEN 4 THEN 'BSA'
                WHEN 5 THEN 'KON'
                WHEN 6 THEN 'BSA'
                WHEN 7 THEN 'KAM'
                WHEN 8 THEN 'BSA'
                WHEN 9 THEN 'ELK'  ELSE       '99'
            END
        )                                                       AS TP1,

        -- TP3
        CASE mm.METER_KIND WHEN 0 THEN 'ONO' ELSE 'NOR' END    AS TP3,

        -- FMETHOD / FPARID / FMANUAL
        CASE
            WHEN a.HEATING_TYPE_ID IN (
                SELECT ht.PRM_ID FROM SMS.CS_HEATING_TYPE_PRM_LNG ht
                WHERE ht.LANG_ID = 1 AND UPPER(ht.VALUE) LIKE '%MERKEZ%'
            ) THEN 1
            ELSE 0
        END                                                     AS FMETHOD,
        sub.PARENT_ID                                           AS FPARID, --- Bu kisim incelenmeli
        CASE a.SUBSCRIBER_TYPE_ID
            WHEN 1 THEN 0  WHEN 5 THEN 0  ELSE 1
        END                                                     AS FMANUAL,

        -- STATID / ISACTIVE
        CASE a.STATUS
            WHEN 0 THEN 1  WHEN 1 THEN 9
            WHEN 2 THEN 11 WHEN 3 THEN 9
            ELSE NULL
        END                                                     AS STATID,
        0                                                       AS ISACTIVE,  -- dis katmanda FITNO son = 1

        -- Kullanici
        a.CREATED_USER_ID                                       AS ADDUSER,
        a.CREATED_TIMESTAMP                                     AS ADDDATE,
        a.UPDATED_USER_ID                                       AS UPDUSER,
        a.UPDATED_TIMESTAMP                                     AS UPDDATE,

        -- Finansal
        a.CREATE_DEPOSIT_DIFF                                   AS NEEDPAY,
        160                                                     AS CURTYPE,
        a.AUTO_PAYMENT_BANK_ID                                  AS PAY_BANKREF,
        CASE WHEN a.AUTO_PAYMENT_BANK_ID IS NOT NULL THEN 1 ELSE 0 END AS PAYTYPE,
        a.IS_VAT_DISCOUNT                                       AS TAX,
        CAST(NULL AS NUMBER(15,2))                              AS PAY_TOTAL,
        CAST(NULL AS NUMBER(15,2))                              AS TLTOTAL,
        CAST(NULL AS NUMBER(15,2))                              AS CURTOTAL,
        CAST(NULL AS NUMBER(15,2))                              AS GRANDTOTAL,
        CAST(NULL AS NUMBER(15,2))                              AS DV,

        -- Basinc
        a.PRESSURE                                              AS Basinc,
        a.PRESSURE                                              AS COUNTERMBAR,
        CASE WHEN a.PRESSURE = 21 THEN 34 ELSE a.PRESSURE END  AS CALCPRESSID,

        -- Sozlesme
        a.EXPIRY_DAY                                            AS SON_ODEME_GUNU,
        TO_CHAR(a.ID)                                           AS AGREEMENT_NUMBER,
        a.IS_TAX_DISCOUNT                                       AS ISTAXFREE,
        a.IS_VAT_DISCOUNT                                       AS ISDVFREE,
        a.IS_TAX_DISCOUNT                                       AS ISOTVFREE,
        CASE WHEN a.VAT_EXEMPTION_REASON_CODE IS NOT NULL THEN 1 ELSE 0 END AS ISNOTCALCDV,
        a.DESCRIPTION                                           AS NOTE,

        -- Tesisat
        i.INSTALLATION_NUMBER                                   AS FITNO,
        i.INSTALLATION_STATUS_ID                                AS INSTALLATION_STATUS_ID,
        i.ID                                                    AS TUKETIM_NOKTASI,
        i.METER_STATUS_ID                                       AS COUNTER_STAT,
        i.METER_TYPE_ID                                         AS Tip,
        i.METER_ID                                              AS COUNTERID,
        i.SERVICE_BOX_ID                                        AS SERVICE_BOX_ID,
        i.HOUSEHOLDS_COUNT                                      AS HOUSEHOLDS_COUNT,
        i.FIRST_STARTUP_DATE                                    AS FIRST_STARTUP_DATE,

        -- Sayac
        m.METER_NUMBER                                          AS COUNTERSN,
        CASE
            WHEN m.METER_MODEL_ID = 16 THEN 109
            WHEN m.METER_MODEL_ID = 17 THEN 9
            WHEN m.METER_MODEL_ID = 18 THEN 11   -- DIKKAT: 18 icin ikinci dal (10) olusuydu, ilki gecerli
            WHEN m.METER_MODEL_ID = 20 THEN 13
            WHEN m.METER_MODEL_ID = 21 THEN 105
            WHEN m.METER_MODEL_ID = 22 THEN 3
            WHEN m.METER_MODEL_ID = 23 THEN 4
            WHEN m.METER_MODEL_ID = 24 THEN 5
            WHEN m.METER_MODEL_ID = 25 THEN 1
            WHEN m.METER_MODEL_ID = 26 THEN 6
            WHEN m.METER_MODEL_ID = 27 THEN 2
            WHEN m.METER_MODEL_ID = 29 THEN 7
            WHEN m.METER_MODEL_ID = 30 THEN 8
            WHEN m.METER_MODEL_ID = 31 THEN 14
            WHEN m.METER_MODEL_ID = 32 THEN 101
            ELSE -99
        END                                                     AS COUNTERMODEL,
        mm.METER_DIAMETER_ID                                    AS Cap,

        -- Gaz
        CASE WHEN a.STARTUP_DATE IS NOT NULL THEN 1 ELSE 0 END AS OPENED,
        0                                                       AS IS_GS,
        CASE
            WHEN a.STARTUP_DATE IS NOT NULL
             AND a.STARTUP_DATE = a.AGREEMENT_DATE THEN 1
            ELSE 0
        END                                                     AS IS_FIRST_USE,

        -- Devir / Referans
        CASE a.STATUS WHEN 3 THEN 1 ELSE 0 END                 AS TRANS,
        a.ID                                                    AS OLREF,
        i.INSTALLATION_NUMBER                                   AS OLOC_ID,
        cls.STATUS                                              AS CLOSESTATID,  -- DIKKAT: aslinda CANCELLATION_DATE (DATE). Kaynak kolon adi dogrulanmali.

        -- Tahsilat / Iade
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM SMS.CS_ACCOUNT        acc
                JOIN SMS.CS_ACCOUNT_ACTION aa ON aa.ACCOUNT_ID = acc.ID
                WHERE acc.AGREEMENT_ID   = a.ID
                  AND acc.ACCRUE_TYPE_ID IN (5, 6)
                  AND aa.ACTION_TYPE_ID   = 2
            ) THEN 1
            ELSE 0
        END                                                     AS FEE_COLLECTED,
        CASE WHEN a.REFUND_DATE IS NOT NULL THEN 1 ELSE 0 END  AS REFUND,

        -- Diger
        1                                                       AS HAS_USING_AGR,
        CAST(NULL AS DATE)                                      AS INV_PRINT_DATE,
        CAST(NULL AS DATE)                                      AS LASTREAD_DATE,
        0                                                       AS EXPIRE_DEBTTIME,
        CAST(NULL AS NUMBER(10))                                AS APP_ID,

        -- Debug
        spl.VALUE                                               AS ABYS_SUBSCRIBER_TYPE,
        stpl.VALUE                                              AS ABYS_SKB_TARIFF_TYPE,
        tpl.VALUE                                               AS ABYS_TARIFF_TYPE,
        ispl.VALUE                                              AS ABYS_INSTALLATION_STATUS,
        lk.PCMS_TARIFF_TYPE_NAME                                AS PCMS_TARIFF_TYPE_NAME,
        CASE WHEN (a.DESCRIPTION IS NOT NULL AND LTRIM(RTRIM(a.DESCRIPTION)) != '' )
             THEN 'SID : ' || i.SUBSCRIBER_ID || ' SBOX : ' || i.SERVICE_BOX_ID || ' DESC : ' || a.DESCRIPTION
             ELSE NULL END                                      AS ABYS_DESC_NOTE,

        (
            SELECT MAX(p.PROJECT_STATUS)
            KEEP (DENSE_RANK LAST ORDER BY p.ID)
            FROM SMS.II_PROJECT p
            JOIN SMS.II_PROJECT_BUILDING     pb ON p.ID  = pb.PROJECT_ID
            JOIN SMS.II_PROJECT_INSTALLATION pi ON pb.ID = pi.PROJECT_BUILDING_ID
            WHERE pi.INSTALLATION_ID = i.ID
        )                                                       AS ABYS_PROJECT_STATUS

    FROM SMS.CS_AGREEMENT a
    JOIN SMS.CS_INSTALLATION i
         ON i.ID = a.INSTALLATION_ID
    JOIN SMS.CS_INSTALLATION_STATUS_PRM_LNG ispl
         ON ispl.PRM_ID = i.INSTALLATION_STATUS_ID AND ispl.LANG_ID = 1
    JOIN SMS.CS_SUBSCRIBER sub
         ON sub.ID = i.SUBSCRIBER_ID
    JOIN SMS.GIS_BUILDING_FLAT bf
         ON bf.ID = sub.BUILDING_FLAT_ID
    JOIN SMS.GIS_BUILDING_DOOR bd
         ON bd.ID = bf.BUILDING_DOOR_ID
    LEFT JOIN SMS.CS_METER m
         ON m.ID = i.METER_ID
    LEFT JOIN SMS.CS_METER_MODEL_PRM mm
         ON mm.ID = m.METER_MODEL_ID
    LEFT JOIN SMS.CS_SUBSCRIBER_TYPE_PRM_LNG spl
         ON spl.PRM_ID = a.SUBSCRIBER_TYPE_ID AND spl.LANG_ID = 1
    LEFT JOIN SMS.CS_TARIFF_TYPE_PRM_LNG tpl
         ON tpl.PRM_ID = a.TARIFF_TYPE_ID AND tpl.LANG_ID = 1
    LEFT JOIN SMS.CS_TARIFF_TYPE_PRM_LNG stpl
         ON stpl.PRM_ID = a.SKB_TARIFF_TYPE_ID AND stpl.LANG_ID = 1
    LEFT JOIN MIGRATION.STG_TARIFF_MAP lk
         ON lk.NK_TARIFF     = UPPER(REPLACE(REPLACE(TRIM(tpl.VALUE),  'İ','I'), 'ı','I'))
        AND lk.NK_SKB        = UPPER(REPLACE(REPLACE(TRIM(stpl.VALUE), 'İ','I'), 'ı','I'))
        AND lk.NK_SUBSCRIBER = UPPER(REPLACE(REPLACE(TRIM(spl.VALUE),  'İ','I'), 'ı','I'))
    LEFT JOIN (
        SELECT
            aca.AGREEMENT_ID,
            aca.CANCELLATION_DATE AS STATUS,
            ROW_NUMBER() OVER (
                PARTITION BY aca.AGREEMENT_ID
                ORDER BY aca.CREATED_TIMESTAMP DESC
            ) AS RN
        FROM SMS.CS_AGREEMENT_CLOSING_APP aca
    ) cls ON cls.AGREEMENT_ID = a.ID AND cls.RN = 1
    WHERE a.STATUS IN (0, 1, 2, 3)

    UNION ALL

    -- ============================================================
    -- ABN: CS_AGREEMENT_SUBSCRIBER
    -- ============================================================
    SELECT
        'ABN'                                                   AS TP2,
        as_.ID                                                  AS ABYS_ID,
        CAST(NULL AS NUMBER(10))                                AS PARID,

        -- Flat / Bina (BNA_ID = GIS_BUILDING_DOOR.CODE — LS_FLAT ile ayni)
        sub.BUILDING_FLAT_ID                                    AS FLATID,
        CAST(bd.CODE AS NUMBER(10))                             AS BNA_ID,

        -- Tarihler
        as_.AGREEMENT_DATE                                      AS AGR_SDATE,
        as_.CANCELLATION_DATE                                   AS AGR_EDATE,
        CAST(NULL AS DATE)                                      AS PAY_SDATE,
        i.FIRST_STARTUP_DATE                                    AS OPEN_DATE,
        CAST(NULL AS DATE)                                      AS ABYS_REFUND_DATE,

        -- Tarife
        CAST(NULL AS NUMBER(5))                                 AS BN_TYPE,
        CAST(NULL AS NUMBER(10))                                AS SKB_TARIFF_TYPE_ID,
        CAST(NULL AS NUMBER(10))                                AS TARIFF_TYPE_ID,
        CAST(NULL AS NUMBER(11))                                AS FRMID,
        as_.REGISTER_ID                                         AS CON,

        -- TP1
        CASE i.SUBSCRIBER_TYPE_ID
            WHEN 1 THEN 'KON'  WHEN 2 THEN 'KAM'
            WHEN 3 THEN 'TIC'  WHEN 4 THEN 'BSA'
            WHEN 5 THEN 'KON'  WHEN 6 THEN 'BSA'
            WHEN 7 THEN 'KAM'  WHEN 8 THEN 'BSA'
            WHEN 9 THEN 'ELK'  ELSE       '99'
        END                                                     AS TP1,

        -- TP3
        CASE mm.METER_KIND WHEN 1 THEN 'NOR' ELSE 'ONO' END    AS TP3,

        -- FMETHOD / FPARID / FMANUAL
        CASE WHEN sub.PARENT_ID IS NOT NULL THEN 1 ELSE 0 END  AS FMETHOD,
        sub.PARENT_ID                                           AS FPARID,
        CASE i.SUBSCRIBER_TYPE_ID
            WHEN 1 THEN 0  WHEN 5 THEN 0  ELSE 1
        END                                                     AS FMANUAL,

        -- STATID / ISACTIVE
        CASE
            WHEN as_.CANCELLATION_DATE IS NULL THEN 9
            ELSE 11
        END                                                     AS STATID,
        CASE
            WHEN as_.CANCELLATION_DATE IS NULL THEN 1
            ELSE 0
        END                                                     AS ISACTIVE,

        -- Kullanici
        as_.CREATED_USER_ID                                     AS ADDUSER,
        as_.CREATED_TIMESTAMP                                   AS ADDDATE,
        as_.UPDATED_USER_ID                                     AS UPDUSER,
        as_.UPDATED_TIMESTAMP                                   AS UPDDATE,

        -- Finansal
        0                                                       AS NEEDPAY,
        160                                                     AS CURTYPE,
        CAST(NULL AS NUMBER(5))                                 AS PAY_BANKREF,
        CAST(NULL AS NUMBER(1))                                 AS PAYTYPE,
        CAST(NULL AS NUMBER(1))                                 AS TAX,
        CAST(NULL AS NUMBER(15,2))                              AS PAY_TOTAL,
        CAST(NULL AS NUMBER(15,2))                              AS TLTOTAL,
        CAST(NULL AS NUMBER(15,2))                              AS CURTOTAL,
        CAST(NULL AS NUMBER(15,2))                              AS GRANDTOTAL,
        CAST(NULL AS NUMBER(15,2))                              AS DV,

        -- Basinc
        CAST(NULL AS NUMBER(10,2))                              AS Basinc,
        CAST(NULL AS NUMBER(10,2))                              AS COUNTERMBAR,
        CAST(NULL AS NUMBER(10,2))                              AS CALCPRESSID,

        -- Sozlesme
        CAST(NULL AS NUMBER(2))                                 AS SON_ODEME_GUNU,
        CAST(NULL AS VARCHAR2(50))                              AS AGREEMENT_NUMBER,
        CAST(NULL AS NUMBER(1))                                 AS ISTAXFREE,
        CAST(NULL AS NUMBER(1))                                 AS ISDVFREE,
        CAST(NULL AS NUMBER(1))                                 AS ISOTVFREE,
        CAST(NULL AS NUMBER(1))                                 AS ISNOTCALCDV,
        as_.DESCRIPTION                                         AS NOTE,

        -- Tesisat
        i.INSTALLATION_NUMBER                                   AS FITNO,
        i.INSTALLATION_STATUS_ID                                AS INSTALLATION_STATUS_ID,
        i.ID                                                    AS TUKETIM_NOKTASI,
        i.METER_STATUS_ID                                       AS COUNTER_STAT,
        i.METER_TYPE_ID                                         AS Tip,
        i.METER_ID                                              AS COUNTERID,
        i.SERVICE_BOX_ID                                        AS SERVICE_BOX_ID,
        i.HOUSEHOLDS_COUNT                                      AS HOUSEHOLDS_COUNT,
        i.FIRST_STARTUP_DATE                                    AS FIRST_STARTUP_DATE,

        -- Sayac
        m.METER_NUMBER                                          AS COUNTERSN,
        CASE
            WHEN m.METER_MODEL_ID = 16 THEN 109
            WHEN m.METER_MODEL_ID = 17 THEN 9
            WHEN m.METER_MODEL_ID = 18 THEN 11
            WHEN m.METER_MODEL_ID = 20 THEN 13
            WHEN m.METER_MODEL_ID = 21 THEN 105
            WHEN m.METER_MODEL_ID = 22 THEN 3
            WHEN m.METER_MODEL_ID = 23 THEN 4
            WHEN m.METER_MODEL_ID = 24 THEN 5
            WHEN m.METER_MODEL_ID = 25 THEN 1
            WHEN m.METER_MODEL_ID = 26 THEN 6
            WHEN m.METER_MODEL_ID = 27 THEN 2
            WHEN m.METER_MODEL_ID = 29 THEN 7
            WHEN m.METER_MODEL_ID = 30 THEN 8
            WHEN m.METER_MODEL_ID = 31 THEN 14
            WHEN m.METER_MODEL_ID = 32 THEN 101
            ELSE -99
        END                                                     AS COUNTERMODEL,
        mm.METER_DIAMETER_ID                                    AS Cap,

        -- Gaz
        CASE WHEN i.FIRST_STARTUP_DATE IS NOT NULL THEN 1 ELSE 0 END AS OPENED,
        0                                                       AS IS_GS,
        CASE
            WHEN NOT EXISTS (
                SELECT 1 FROM SMS.CS_AGREEMENT agr
                WHERE agr.INSTALLATION_ID = i.ID
            ) THEN 1
            ELSE 0
        END                                                     AS IS_FIRST_USE,

        -- Devir / Referans
        CASE as_.CLOSING_TYPE WHEN 1 THEN 1 ELSE 0 END         AS TRANS,
        as_.ID                                                  AS OLREF,
        i.INSTALLATION_NUMBER                                   AS OLOC_ID,
        CAST(NULL AS DATE)                                      AS CLOSESTATID,  -- KUL tarafiyla ayni tip (DATE); semantik dogrulama gerekli

        -- Tahsilat / Iade
        CAST(NULL AS NUMBER(1))                                 AS FEE_COLLECTED,
        CAST(NULL AS NUMBER(1))                                 AS REFUND,

        -- Diger
        CASE
            WHEN EXISTS (
                SELECT 1 FROM SMS.CS_AGREEMENT agr
                WHERE agr.INSTALLATION_ID = i.ID
            ) THEN 1
            ELSE 0
        END                                                     AS HAS_USING_AGR,
        CAST(NULL AS DATE)                                      AS INV_PRINT_DATE,
        CAST(NULL AS DATE)                                      AS LASTREAD_DATE,
        0                                                       AS EXPIRE_DEBTTIME,
        CAST(NULL AS NUMBER(10))                                AS APP_ID,

        -- Debug
        CASE i.SUBSCRIBER_TYPE_ID
            WHEN 1 THEN 'KONUT'            WHEN 2 THEN 'RESMI'
            WHEN 3 THEN 'TİCARİ VE DİĞER' WHEN 4 THEN 'SANAYİ'
            WHEN 5 THEN 'MERKEZİ ISINMA'  WHEN 6 THEN 'SANAYİ KESİNTİLİ'
            WHEN 7 THEN 'RESMİ MERKEZİ'   WHEN 8 THEN 'OSB'
            WHEN 9 THEN 'ELEKTRİK ÜRETİM' ELSE 'BİLİNMEYEN'
        END                                                     AS ABYS_SUBSCRIBER_TYPE,
        CAST(NULL AS VARCHAR2(200))                             AS ABYS_SKB_TARIFF_TYPE,
        CAST(NULL AS VARCHAR2(200))                             AS ABYS_TARIFF_TYPE,
        ispl.VALUE                                              AS ABYS_INSTALLATION_STATUS,
        CAST(NULL AS VARCHAR2(200))                             AS PCMS_TARIFF_TYPE_NAME,

        CASE WHEN (as_.DESCRIPTION IS NOT NULL AND LTRIM(RTRIM(as_.DESCRIPTION)) != '' )
             THEN 'SID : ' || as_.SUBSCRIBER_ID || ' SBOX : ' || as_.SERVICE_BOX_ID || ' DESC : ' || as_.DESCRIPTION
             ELSE NULL END                                      AS ABYS_DESC_NOTE,

        (
            SELECT MAX(p.PROJECT_STATUS)
            KEEP (DENSE_RANK LAST ORDER BY p.ID)
            FROM SMS.II_PROJECT p
            JOIN SMS.II_PROJECT_BUILDING     pb ON p.ID  = pb.PROJECT_ID
            JOIN SMS.II_PROJECT_INSTALLATION pi ON pb.ID = pi.PROJECT_BUILDING_ID
            WHERE pi.INSTALLATION_ID = i.ID
        )                                                       AS ABYS_PROJECT_STATUS

    FROM SMS.CS_AGREEMENT_SUBSCRIBER as_
    JOIN SMS.CS_SUBSCRIBER sub
         ON sub.ID = as_.SUBSCRIBER_ID
    JOIN SMS.CS_INSTALLATION i
         ON i.SUBSCRIBER_ID = sub.ID
    JOIN SMS.GIS_BUILDING_FLAT bf
         ON bf.ID = sub.BUILDING_FLAT_ID
    JOIN SMS.GIS_BUILDING_DOOR bd
         ON bd.ID = bf.BUILDING_DOOR_ID
    JOIN SMS.GIS_SERVICE_BOX sb
         ON sb.ID = i.SERVICE_BOX_ID
    LEFT JOIN SMS.CS_INSTALLATION_STATUS_PRM_LNG ispl
         ON ispl.PRM_ID = i.INSTALLATION_STATUS_ID AND ispl.LANG_ID = 1
    LEFT JOIN SMS.CS_METER m
         ON m.ID = i.METER_ID
    LEFT JOIN SMS.CS_METER_MODEL_PRM mm
         ON mm.ID = m.METER_MODEL_ID
    WHERE 1=1

) t
CROSS JOIN (
    -- ABN LREF baslangici: tum CS_AGREEMENT.ID ust siniri (filtreli degil)
    SELECT NVL(MAX(ID), 0) AS MAX_KUL_ID FROM SMS.CS_AGREEMENT
) m
) w
;

-- ============================================================
-- 3) INDEX
-- ============================================================


-- Parallel/nologging kapat (sonraki DML'lerde surpriz olmasin)
ALTER TABLE MIGRATION.LS_AGREEMENT NOPARALLEL LOGGING;

-- Istatistik

-- ============================================================
-- 4) DOGRULAMA
-- ============================================================
SELECT TP2, COUNT(*) AS ADET,
       MIN(LREF) AS MIN_LREF, MAX(LREF) AS MAX_LREF
FROM MIGRATION.LS_AGREEMENT
GROUP BY TP2
ORDER BY TP2;

-- KUL LREF = CS_AGREEMENT.ID olmali
SELECT COUNT(*) AS KUL_LREF_MISMATCH
FROM MIGRATION.LS_AGREEMENT
WHERE TP2 = 'KUL' AND LREF <> ABYS_ID;

-- ABN LREF, MAX(CS_AGREEMENT.ID) sonrasinda olmali
SELECT
    m.MAX_CS_AGR_ID,
    a.ABN_MIN_LREF,
    a.ABN_MAX_LREF,
    a.ABN_ADET
FROM (SELECT NVL(MAX(ID), 0) AS MAX_CS_AGR_ID FROM SMS.CS_AGREEMENT) m
CROSS JOIN (
    SELECT
        MIN(LREF) AS ABN_MIN_LREF,
        MAX(LREF) AS ABN_MAX_LREF,
        COUNT(*)  AS ABN_ADET
    FROM MIGRATION.LS_AGREEMENT
    WHERE TP2 = 'ABN'
) a;

SELECT 'CS_AGREEMENT (0-3)'     , COUNT(*) FROM SMS.CS_AGREEMENT            WHERE STATUS IN (0,1,2,3) UNION ALL
SELECT 'CS_AGREEMENT_SUBSCRIBER', COUNT(*) FROM SMS.CS_AGREEMENT_SUBSCRIBER UNION ALL
SELECT 'LS_AGREEMENT KUL'       , COUNT(*) FROM MIGRATION.LS_AGREEMENT WHERE TP2 = 'KUL' UNION ALL
SELECT 'LS_AGREEMENT ABN'       , COUNT(*) FROM MIGRATION.LS_AGREEMENT WHERE TP2 = 'ABN';

-- BN_TYPE eslesmeyenler
SELECT ABYS_TARIFF_TYPE, ABYS_SKB_TARIFF_TYPE, ABYS_SUBSCRIBER_TYPE, COUNT(*) AS ADET
FROM MIGRATION.LS_AGREEMENT
WHERE TP2 = 'KUL' AND BN_TYPE = -99
GROUP BY ABYS_TARIFF_TYPE, ABYS_SKB_TARIFF_TYPE, ABYS_SUBSCRIBER_TYPE
ORDER BY COUNT(*) DESC;

-- ISACTIVE: FITNO basina tek aktif KUL
SELECT
    COUNT(*) AS KUL_FITNO,
    SUM(CASE WHEN CNT <> 1 THEN 1 ELSE 0 END) AS FITNO_AKTIF_SAYISI_HATALI
FROM (
    SELECT FITNO, SUM(CASE WHEN ISACTIVE = 1 THEN 1 ELSE 0 END) AS CNT
    FROM MIGRATION.LS_AGREEMENT
    WHERE TP2 = 'KUL' AND FITNO IS NOT NULL
    GROUP BY FITNO
);

-- PARID: KUL → ABN (FLATID dolu olanlar)
SELECT
    COUNT(*) AS KUL_FLAT_DOLU,
    SUM(CASE WHEN PARID IS NULL THEN 1 ELSE 0 END) AS KUL_PARID_NULL
FROM MIGRATION.LS_AGREEMENT
WHERE TP2 = 'KUL' AND FLATID IS NOT NULL;

-- Lookup eslesme ozeti
SELECT
    COUNT(*) AS KUL_TOPLAM,
    SUM(CASE WHEN BN_TYPE = -99 THEN 1 ELSE 0 END) AS BN_TYPE_YOK,
    SUM(CASE WHEN BN_TYPE <> -99 THEN 1 ELSE 0 END) AS BN_TYPE_OK,
    ROUND(100 * SUM(CASE WHEN BN_TYPE <> -99 THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0), 2) AS PCT_OK
FROM MIGRATION.LS_AGREEMENT
WHERE TP2 = 'KUL';

SELECT COUNT(*) AS MAP_SATIR FROM MIGRATION.STG_TARIFF_MAP;

PROMPT ========== LS_AGREEMENT OK ==========
/
