-- ============================================================
-- �NCE TEMP TABLOYU DOLDUR (session ba��nda bir kez �al��t�r)
-- ============================================================
CREATE GLOBAL TEMPORARY TABLE TEMP_TARIFF_LOOKUP (
    ABYS_TARIFF_TYPE      VARCHAR2(100),
    ABYS_SKB_TARIFF_TYPE  VARCHAR2(100),
    ABYS_SUBSCRIBER_TYPE  VARCHAR2(100),
    PCMS_TARIFF_TYPE_NAME VARCHAR2(200),
    TP1                   VARCHAR2(10),
    BN_TYPE               NUMBER(5)
)
ON COMMIT PRESERVE ROWS;
GO
 

INSERT ALL
    INTO TEMP_TARIFF_LOOKUP VALUES('CNG 2.KADEME'       ,'4.KADEME'  ,'SANAY�'          ,'CNG 4.Kademe'               ,'CNG', 151)
    INTO TEMP_TARIFF_LOOKUP VALUES('CNG 2.KADEME'       ,'5.KADEME'  ,'SANAY�'          ,'CNG 5.Kademe'               ,'CNG', 152)
    INTO TEMP_TARIFF_LOOKUP VALUES('EKMEK �RET�C�S�'   ,'1.KADEME'  ,'T�CAR� VE D��ER' ,'Ekmek �reticileri 1.Kademe' ,'TIC', 201)
    INTO TEMP_TARIFF_LOOKUP VALUES('EKMEK �RET�C�S�'   ,'2.KADEME'  ,'T�CAR� VE D��ER' ,'Ekmek �reticileri 2.Kademe' ,'TIC', 202)
    INTO TEMP_TARIFF_LOOKUP VALUES('EKMEK �RET�C�S�'   ,'3.KADEME'  ,'T�CAR� VE D��ER' ,'Ekmek �reticileri 3A.Kademe','TIC', 203)
    INTO TEMP_TARIFF_LOOKUP VALUES('ELEKTR�K 1.KADEME' ,'1.KADEME'  ,'SANAY�'          ,'1.Kademe'                   ,'ELK', 138)
    INTO TEMP_TARIFF_LOOKUP VALUES('ELEKTR�K 2.KADEME' ,'3.KADEME'  ,'RESMI'           ,'3.Kademe B'                 ,'ELK', 141)
    INTO TEMP_TARIFF_LOOKUP VALUES('ELEKTR�K 2.KADEME' ,'4.KADEME'  ,'SANAY�'          ,'4.Kademe'                   ,'ELK', 142)
    INTO TEMP_TARIFF_LOOKUP VALUES('ELEKTR�K 2.KADEME' ,'4.KADEME'  ,'RESMI'           ,'4.Kademe'                   ,'ELK', 142)
    INTO TEMP_TARIFF_LOOKUP VALUES('ELEKTR�K 2.KADEME' ,'5.KADEME'  ,'SANAY�'          ,'5.Kademe'                   ,'ELK', 143)
    INTO TEMP_TARIFF_LOOKUP VALUES('GAZ�/�EH�T YAKINI' ,'1.KADEME'  ,'KONUT'           ,'Gazi/�ehit Konut 1'         ,'KON', -99)
    INTO TEMP_TARIFF_LOOKUP VALUES('IBADETHANE'         ,'1.KADEME'  ,'RESMI'           ,'IBD 1.Kademe'               ,'TIC', 186)
    INTO TEMP_TARIFF_LOOKUP VALUES('IBADETHANE'         ,'1.KADEME'  ,'KONUT'           ,'IBD 1.Kademe'               ,'TIC', 186)
    INTO TEMP_TARIFF_LOOKUP VALUES('IBADETHANE'         ,'1.KADEME'  ,'T�CAR� VE D��ER' ,'IBD 1.Kademe'               ,'TIC', 186)
    INTO TEMP_TARIFF_LOOKUP VALUES('IBADETHANE'         ,'1.KADEME'  ,'MERKEZ� ISINMA'  ,'IBD 1.Kademe'               ,'TIC', 186)
    INTO TEMP_TARIFF_LOOKUP VALUES('IBADETHANE'         ,'2.KADEME'  ,'T�CAR� VE D��ER' ,'IBD 2.Kademe'               ,'TIC', 187)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'1.KADEME'  ,'T�CAR� VE D��ER' ,'1.Kademe'                   ,'TIC', 103)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'1.KADEME'  ,'RESMI'           ,'1.Kademe'                   ,'KAM', 110)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'1.KADEME'  ,'KONUT'           ,'1.Kademe'                   ,'TIC', 103)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'1.KADEME'  ,'SANAY�'          ,'1.Kademe'                   ,'BSA', 124)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'2.KADEME'  ,'T�CAR� VE D��ER' ,'2.Kademe'                   ,'TIC', 104)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'2.KADEME'  ,'RESMI'           ,'2.Kademe'                   ,'KAM', 111)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'2.KADEME'  ,'SANAY�'          ,'2.Kademe'                   ,'BSA', 125)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'2.KADEME'  ,'KONUT'           ,'2.Kademe'                   ,'TIC', 104)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'3.KADEME'  ,'T�CAR� VE D��ER' ,'3.Kademe A'                 ,'TIC', 105)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'3.KADEME'  ,'RESMI'           ,'3.Kademe A'                 ,'KAM', 112)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'3.KADEME'  ,'SANAY�'          ,'3.Kademe A'                 ,'BSA', 126)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KONUT'   ,'1.KADEME'  ,'KONUT'           ,'Konut 1K'                   ,'KON',  96)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KONUT'   ,'1.KADEME'  ,'RESMI'           ,'Konut 1K'                   ,'KON',  96)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KONUT'   ,'2.KADEME'  ,'MERKEZ� ISINMA'  ,'Konut 2K'                   ,'KON',  97)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KONUT'   ,'2.KADEME'  ,'T�CAR� VE D��ER' ,'Konut 2K'                   ,'KON',  97)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 1. KONUT'   ,'3.KADEME'  ,'MERKEZ� ISINMA'  ,'Konut 3aK'                  ,'KON',  98)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'1.KADEME'  ,'SANAY�'          ,'1.Kademe'                   ,'BSA', 124)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'3.KADEME'  ,'RESMI'           ,'3.Kademe B'                 ,'KAM', 113)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'3.KADEME'  ,'SANAY�'          ,'3.Kademe B'                 ,'BSA', 127)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'3.KADEME'  ,'T�CAR� VE D��ER' ,'3.Kademe B'                 ,'TIC', 106)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'4.KADEME'  ,'SANAY�'          ,'4.Kademe'                   ,'BSA', 128)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'4.KADEME'  ,'RESMI'           ,'4.Kademe'                   ,'KAM', 114)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'4.KADEME'  ,'T�CAR� VE D��ER' ,'4.Kademe'                   ,'TIC', 107)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'5.KADEME'  ,'SANAY�'          ,'5.Kademe'                   ,'BSA', 129)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 2. KONUT'   ,'2.KADEME'  ,'MERKEZ� ISINMA'  ,'Konut 2K'                   ,'KON',  97)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 2. KONUT'   ,'3.KADEME'  ,'MERKEZ� ISINMA'  ,'Konut 3aK'                  ,'KON',  98)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST 2. KONUT'   ,'4.KADEME'  ,'MERKEZ� ISINMA'  ,'Konut 4K'                   ,'KON', 100)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST OLMAYAN'    ,'1.KADEME'  ,'KONUT'           ,'Konut 1K'                   ,'KON',  96)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST OLMAYAN'    ,'1.KADEME'  ,'MERKEZ� ISINMA'  ,'Konut 1K'                   ,'KON',  96)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST OLMAYAN'    ,'1.KADEME'  ,'RESMI'           ,'Konut 1K'                   ,'KON',  96)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST OLMAYAN'    ,'2.KADEME'  ,'MERKEZ� ISINMA'  ,'Konut 2K'                   ,'KON',  97)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST OLMAYAN'    ,'2.KADEME'  ,'KONUT'           ,'Konut 2K'                   ,'KON',  97)
    INTO TEMP_TARIFF_LOOKUP VALUES('SERBEST OLMAYAN'    ,'3.KADEME'  ,'MERKEZ� ISINMA'  ,'Konut 3aK'                  ,'KON',  98)
    INTO TEMP_TARIFF_LOOKUP VALUES('TASIMA'             ,'1.KADEME'  ,'SANAY�'          ,'1.Kademe'                   ,'BSA', 124)
    INTO TEMP_TARIFF_LOOKUP VALUES('TASIMA'             ,'3.KADEME'  ,'SANAY�'          ,'3.Kademe A'                 ,'BSA', 126)
    INTO TEMP_TARIFF_LOOKUP VALUES('TASIMA'             ,'4.KADEME'  ,'SANAY�'          ,'4.Kademe'                   ,'BSA', 128)
    INTO TEMP_TARIFF_LOOKUP VALUES('TASIMA'             ,'5.KADEME'  ,'SANAY�'          ,'5.Kademe'                   ,'BSA', 129)
SELECT 1 FROM DUAL;

COMMIT;





 
 

-- ============================================================
-- STAGING: LS_AGREEMENT � KUL + ABN UNION ALL
-- ORA-01723 fix: t�m NULL kolonlar CAST ile tiplendirildi
-- ============================================================

CREATE TABLE SMS.LS_AGREEMENT
NOLOGGING
PARALLEL 4
AS
SELECT * FROM (

    -- ============================================================
    -- KUL: CS_AGREEMENT
    -- ============================================================
    SELECT
        'KUL'                                                   AS TP2,
        a.ID                                                    AS ABYS_ID,
        CAST(NULL AS NUMBER(10))                                AS PARID,

        -- Flat / Bina
        sub.BUILDING_FLAT_ID                                    AS FLATID,
        bf.BUILDING_DOOR_ID                                     AS BNA_ID,

        -- Tarihler
        a.AGREEMENT_DATE                                        AS AGR_SDATE,
        a.CANCELLATION_DATE                                     AS AGR_EDATE,
        a.STARTING_DATE                                         AS PAY_SDATE,
        a.STARTUP_DATE                                          AS OPEN_DATE,
        a.REFUND_DATE                                           AS ABYS_REFUND_DATE,

        -- Tarife / BN_TYPE
        NVL(lk.BN_TYPE, -99)                                   AS BN_TYPE,
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
        CASE mm.METER_KIND WHEN 1 THEN 'NOR' ELSE 'ONO' END    AS TP3,

        -- FMETHOD / FPARID / FMANUAL
        CASE
            WHEN a.HEATING_TYPE_ID IN (
                SELECT ht.PRM_ID FROM SMS.CS_HEATING_TYPE_PRM_LNG ht
                WHERE ht.LANG_ID = 1 AND UPPER(ht.VALUE) LIKE '%MERKEZ%'
            ) THEN 1
            ELSE 0
        END                                                     AS FMETHOD,
        sub.PARENT_ID                                           AS FPARID, --- Bu k�s�m �ncelenmeli
        CASE a.SUBSCRIBER_TYPE_ID
            WHEN 1 THEN 0  WHEN 5 THEN 0  ELSE 1
        END                                                     AS FMANUAL,
 

        -- STATID / ISACTIVE
        CASE a.STATUS
            WHEN 0 THEN 1  --Pasif - 
            WHEN 1 THEN 9
            WHEN 2 THEN 11 
            WHEN 3 THEN 9
            ELSE NULL
        END                                                     AS STATID,
        0                                                       AS ISACTIVE,

        -- Kullan�c�
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

        -- Bas�n�
        a.PRESSURE                                              AS Basinc,
        a.PRESSURE                                              AS COUNTERMBAR,
        CASE WHEN a.PRESSURE = 21 THEN 34 ELSE a.PRESSURE END  AS CALCPRESSID,

        -- S�zle�me
        a.EXPIRY_DAY                                            AS SON_ODEME_GUNU,
        a.AGREEMENT_NUMBER                                      AS AGREEMENT_NUMBER,
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

        -- Saya�
        m.METER_NUMBER                                          AS COUNTERSN,
        m.METER_MODEL_ID                                        AS COUNTERMODEL,
        mm.METER_DIAMETER_ID                                    AS Cap,

        -- Gaz
        CASE WHEN a.STARTUP_DATE IS NOT NULL THEN 1 ELSE 0 END AS OPENED,
        0  AS IS_GS,  -- GAZ SA�LAYICI 
        CASE
            WHEN a.STARTUP_DATE IS NOT NULL
             AND a.STARTUP_DATE = a.AGREEMENT_DATE THEN 1
            ELSE 0
        END                                                     AS IS_FIRST_USE,

        -- Devir / Referans
        CASE a.STATUS WHEN 3 THEN 1 ELSE 0 END                 AS TRANS,
        a.ID                                                    AS OLREF,
        i.INSTALLATION_NUMBER                                   AS OLOC_ID,
        cls.STATUS                                              AS CLOSESTATID,

        -- Tahsilat / �ade
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM SMS.CS_ACCOUNT     acc
                JOIN SMS.CS_ACCOUNT_ACTION aa ON aa.ACCOUNT_ID = acc.ID
                WHERE acc.AGREEMENT_ID   = a.ID
                  AND acc.ACCRUE_TYPE_ID IN (5, 6)
                  AND aa.ACTION_TYPE_ID   = 2
            ) THEN 1
            ELSE 0
        END                                                     AS FEE_COLLECTED,
        CASE WHEN a.REFUND_DATE IS NOT NULL THEN 1 ELSE 0 END   AS REFUND,

        -- Di�er
        1                                                       AS HAS_USING_AGR,
        CAST(NULL AS DATE)                                      AS INV_PRINT_DATE,
        CAST(NULL AS DATE)                                      AS LASTREAD_DATE,---  SON TAHAKKUK TARIHI
        0                                                       AS EXPIRE_DEBTTIME,
        CAST(NULL AS NUMBER(10))                                AS APP_ID,

        -- Debug
        spl.VALUE                                               AS ABYS_SUBSCRIBER_TYPE,
        stpl.VALUE                                              AS ABYS_SKB_TARIFF_TYPE,
        tpl.VALUE                                               AS ABYS_TARIFF_TYPE,
        ispl.VALUE                                              AS ABYS_INSTALLATION_STATUS,
        lk.PCMS_TARIFF_TYPE_NAME                                AS PCMS_TARIFF_TYPE_NAME,
        (
            SELECT MAX(p.PROJECT_STATUS)
            KEEP (DENSE_RANK LAST ORDER BY p.ID)
            FROM ii_project p
            JOIN ii_project_building    pb ON p.ID  = pb.PROJECT_ID
            JOIN ii_project_installation pi ON pb.ID = pi.PROJECT_BUILDING_ID
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
    LEFT JOIN TEMP_TARIFF_LOOKUP lk
         ON lk.ABYS_TARIFF_TYPE     = tpl.VALUE
        AND lk.ABYS_SKB_TARIFF_TYPE = stpl.VALUE
        AND lk.ABYS_SUBSCRIBER_TYPE = spl.VALUE
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

        -- Flat / Bina
        sub.BUILDING_FLAT_ID                                    AS FLATID,
        bf.BUILDING_DOOR_ID                                     AS BNA_ID,

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

        -- Kullan�c�
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

        -- Bas�n�
        CAST(NULL AS NUMBER(10,2))                              AS Basinc,
        CAST(NULL AS NUMBER(10,2))                              AS COUNTERMBAR,
        CAST(NULL AS NUMBER(10,2))                              AS CALCPRESSID,

        -- S�zle�me
        CAST(NULL AS NUMBER(2))                                 AS SON_ODEME_GUNU,
        TO_CHAR(as_.ID)                                         AS AGREEMENT_NUMBER,
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

        -- Saya�
        m.METER_NUMBER                                          AS COUNTERSN,
        m.METER_MODEL_ID                                        AS COUNTERMODEL,
        mm.METER_DIAMETER_ID                                    AS Cap,

        -- Gaz
        CASE WHEN i.FIRST_STARTUP_DATE IS NOT NULL THEN 1 ELSE 0 END AS OPENED,
        0  IS_GS,
        CASE
            WHEN NOT EXISTS (
                SELECT 1 FROM SMS.CS_AGREEMENT agr
                WHERE agr.INSTALLATION_ID = i.ID
            ) THEN 1
            ELSE 0
        END                                                     AS IS_FIRST_USE,

        -- Devir / Referans
        CASE as_.CLOSING_TYPE WHEN 1 THEN 1 ELSE 0 END         AS TRANS,
        CAST(NULL AS NUMBER(10))                                AS OLREF,
        i.INSTALLATION_NUMBER                                   AS OLOC_ID,
        CAST(NULL AS DATE)                                      AS CLOSESTATID,

        -- Tahsilat / �ade
        CAST(NULL AS NUMBER(1))                                 AS FEE_COLLECTED,
        CAST(NULL AS NUMBER(1))                                 AS REFUND,

        -- Di�er
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
            WHEN 1 THEN 'KONUT'           WHEN 2 THEN 'RESMI'
            WHEN 3 THEN 'T�CAR� VE D��ER' WHEN 4 THEN 'SANAY�'
            WHEN 5 THEN 'MERKEZ� ISINMA'  WHEN 6 THEN 'SANAY� KES�NT�L�'
            WHEN 7 THEN 'RESM� MERKEZ�'   WHEN 8 THEN 'OSB'
            WHEN 9 THEN 'ELEKTR�K �RET�M' ELSE 'B�L�NMEYEN'
        END                                                     AS ABYS_SUBSCRIBER_TYPE,
        CAST(NULL AS VARCHAR2(200))                             AS ABYS_SKB_TARIFF_TYPE,
        CAST(NULL AS VARCHAR2(200))                             AS ABYS_TARIFF_TYPE,
        ispl.VALUE                                              AS ABYS_INSTALLATION_STATUS,
        CAST(NULL AS VARCHAR2(200))                             AS PCMS_TARIFF_TYPE_NAME,
        (
            SELECT MAX(p.PROJECT_STATUS)
            KEEP (DENSE_RANK LAST ORDER BY p.ID)
            FROM ii_project p
            JOIN ii_project_building    pb ON p.ID  = pb.PROJECT_ID
            JOIN ii_project_installation pi ON pb.ID = pi.PROJECT_BUILDING_ID
            WHERE pi.INSTALLATION_ID = i.ID
        )                                                       AS ABYS_PROJECT_STATUS

    FROM SMS.CS_AGREEMENT_SUBSCRIBER as_
    JOIN SMS.CS_SUBSCRIBER sub
         ON sub.ID = as_.SUBSCRIBER_ID
    JOIN SMS.CS_INSTALLATION i
         ON i.SUBSCRIBER_ID = sub.ID
    JOIN SMS.GIS_BUILDING_FLAT bf
         ON bf.ID = sub.BUILDING_FLAT_ID
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
ORDER BY ADDDATE ASC, TP2 ASC, ABYS_ID ASC
;

-- ============================================================
-- INDEX
-- ============================================================
CREATE INDEX IDX_LS_AGR_TP2_ABYSID
    ON SMS.LS_AGREEMENT (TP2, ABYS_ID) NOLOGGING PARALLEL 4;

CREATE INDEX IDX_LS_AGR_ADDDATE
    ON SMS.LS_AGREEMENT (ADDDATE) NOLOGGING PARALLEL 4;

CREATE INDEX IDX_LS_AGR_FLATID
    ON SMS.LS_AGREEMENT (FLATID) NOLOGGING PARALLEL 4;

CREATE INDEX IDX_LS_AGR_CON
    ON SMS.LS_AGREEMENT (CON) NOLOGGING PARALLEL 4;

-- ============================================================
-- DO�RULAMA
-- ============================================================
--SELECT TP2, COUNT(*) AS ADET
--FROM SMS.LS_AGREEMENT
--GROUP BY TP2
--ORDER BY TP2;

--SELECT 'CS_AGREEMENT (0-3)'    , COUNT(*) FROM SMS.CS_AGREEMENT          WHERE STATUS IN (0,1,2,3) UNION ALL
--SELECT 'CS_AGREEMENT_SUBSCRIBER', COUNT(*) FROM SMS.CS_AGREEMENT_SUBSCRIBER UNION ALL
--SELECT 'LS_AGREEMENT KUL'       , COUNT(*) FROM SMS.LS_AGREEMENT WHERE TP2 = 'KUL' UNION ALL
--SELECT 'LS_AGREEMENT ABN'       , COUNT(*) FROM SMS.LS_AGREEMENT WHERE TP2 = 'ABN';

---- BN_TYPE e�le�meyenler
--SELECT ABYS_TARIFF_TYPE, ABYS_SKB_TARIFF_TYPE, ABYS_SUBSCRIBER_TYPE, COUNT(*) AS ADET
--FROM SMS.LS_AGREEMENT
--WHERE TP2 = 'KUL' AND BN_TYPE = -99
--GROUP BY ABYS_TARIFF_TYPE, ABYS_SKB_TARIFF_TYPE, ABYS_SUBSCRIBER_TYPE
--ORDER BY COUNT(*) DESC;