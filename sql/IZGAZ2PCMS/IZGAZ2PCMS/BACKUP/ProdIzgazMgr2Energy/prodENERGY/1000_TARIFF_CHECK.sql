-- ============================================================
-- 1) TARIFE LOOKUP (kalici tablo - GTT degil!
--    PARALLEL CTAS slave session'lari GTT satirlarini goremez)
-- ============================================================
CREATE TABLE TMP_TARIFF_LOOKUP (
    ABYS_TARIFF_TYPE      VARCHAR2(100),
    ABYS_SKB_TARIFF_TYPE  VARCHAR2(100),
    ABYS_SUBSCRIBER_TYPE  VARCHAR2(100),
    PCMS_TARIFF_TYPE_NAME VARCHAR2(200),
    TP1                   VARCHAR2(10),
    BN_TYPE               NUMBER(5)
);
 
INSERT ALL
    INTO TMP_TARIFF_LOOKUP VALUES('CNG 2.KADEME'       ,'4.KADEME'  ,'SANAYİ'          ,'CNG 4.Kademe'               ,'CNG', 151)
    INTO TMP_TARIFF_LOOKUP VALUES('CNG 2.KADEME'       ,'5.KADEME'  ,'SANAYİ'          ,'CNG 5.Kademe'               ,'CNG', 152)
    INTO TMP_TARIFF_LOOKUP VALUES('EKMEK ÜRETİCİSİ'   ,'1.KADEME'  ,'TİCARİ VE DİĞER' ,'Ekmek Üreticileri 1.Kademe' ,'TIC', 201)
    INTO TMP_TARIFF_LOOKUP VALUES('EKMEK ÜRETİCİSİ'   ,'2.KADEME'  ,'TİCARİ VE DİĞER' ,'Ekmek Üreticileri 2.Kademe' ,'TIC', 202)
    INTO TMP_TARIFF_LOOKUP VALUES('EKMEK ÜRETİCİSİ'   ,'3.KADEME'  ,'TİCARİ VE DİĞER' ,'Ekmek Üreticileri 3A.Kademe','TIC', 203)
    INTO TMP_TARIFF_LOOKUP VALUES('ELEKTRİK 1.KADEME' ,'1.KADEME'  ,'SANAYİ'          ,'1.Kademe'                   ,'ELK', 138)
    INTO TMP_TARIFF_LOOKUP VALUES('ELEKTRİK 2.KADEME' ,'3.KADEME'  ,'RESMI'           ,'3.Kademe B'                 ,'ELK', 141)
    INTO TMP_TARIFF_LOOKUP VALUES('ELEKTRİK 2.KADEME' ,'4.KADEME'  ,'SANAYİ'          ,'4.Kademe'                   ,'ELK', 142)
    INTO TMP_TARIFF_LOOKUP VALUES('ELEKTRİK 2.KADEME' ,'4.KADEME'  ,'RESMI'           ,'4.Kademe'                   ,'ELK', 142)
    INTO TMP_TARIFF_LOOKUP VALUES('ELEKTRİK 2.KADEME' ,'5.KADEME'  ,'SANAYİ'          ,'5.Kademe'                   ,'ELK', 143)
    INTO TMP_TARIFF_LOOKUP VALUES('GAZİ/ŞEHİT YAKINI' ,'1.KADEME'  ,'KONUT'           ,'Gazi/Şehit Konut 1'         ,'KON', 219)
    INTO TMP_TARIFF_LOOKUP VALUES('IBADETHANE'         ,'1.KADEME'  ,'RESMI'           ,'IBD 1.Kademe'               ,'TIC', 186)
    INTO TMP_TARIFF_LOOKUP VALUES('IBADETHANE'         ,'1.KADEME'  ,'KONUT'           ,'IBD 1.Kademe'               ,'TIC', 186)
    INTO TMP_TARIFF_LOOKUP VALUES('IBADETHANE'         ,'1.KADEME'  ,'TİCARİ VE DİĞER' ,'IBD 1.Kademe'               ,'TIC', 186)
    INTO TMP_TARIFF_LOOKUP VALUES('IBADETHANE'         ,'1.KADEME'  ,'MERKEZİ ISINMA'  ,'IBD 1.Kademe'               ,'TIC', 186)
    INTO TMP_TARIFF_LOOKUP VALUES('IBADETHANE'         ,'2.KADEME'  ,'TİCARİ VE DİĞER' ,'IBD 2.Kademe'               ,'TIC', 187)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'1.KADEME'  ,'TİCARİ VE DIĞER' ,'1.Kademe'                   ,'TIC', 103)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'1.KADEME'  ,'RESMI'           ,'1.Kademe'                   ,'KAM', 110)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'1.KADEME'  ,'KONUT'           ,'1.Kademe'                   ,'TIC', 103)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'1.KADEME'  ,'SANAYİ'          ,'1.Kademe'                   ,'BSA', 124)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'2.KADEME'  ,'TİCARİ VE DİĞER' ,'2.Kademe'                   ,'TIC', 104)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'2.KADEME'  ,'RESMI'           ,'2.Kademe'                   ,'KAM', 111)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'2.KADEME'  ,'SANAYİ'          ,'2.Kademe'                   ,'BSA', 125)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'2.KADEME'  ,'KONUT'           ,'2.Kademe'                   ,'TIC', 104)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'3.KADEME'  ,'TİCARİ VE DİĞER' ,'3.Kademe A'                 ,'TIC', 105)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'3.KADEME'  ,'RESMI'           ,'3.Kademe A'                 ,'KAM', 112)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KADEME'  ,'3.KADEME'  ,'SANAYİ'          ,'3.Kademe A'                 ,'BSA', 126)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KONUT'   ,'1.KADEME'  ,'KONUT'           ,'Konut 1K'                   ,'KON',  96)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KONUT'   ,'1.KADEME'  ,'RESMI'           ,'Konut 1K'                   ,'KON',  96)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KONUT'   ,'2.KADEME'  ,'MERKEZİ ISINMA'  ,'Konut 2K'                   ,'KON',  97)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KONUT'   ,'2.KADEME'  ,'TİCARİ VE DİĞER' ,'Konut 2K'                   ,'KON',  97)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 1. KONUT'   ,'3.KADEME'  ,'MERKEZİ ISINMA'  ,'Konut 3aK'                  ,'KON',  98)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'1.KADEME'  ,'SANAYİ'          ,'1.Kademe'                   ,'BSA', 124)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'3.KADEME'  ,'RESMI'           ,'3.Kademe B'                 ,'KAM', 113)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'3.KADEME'  ,'SANAYİ'          ,'3.Kademe B'                 ,'BSA', 127)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'3.KADEME'  ,'TİCARİ VE DİĞER' ,'3.Kademe B'                 ,'TIC', 106)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'4.KADEME'  ,'SANAYİ'          ,'4.Kademe'                   ,'BSA', 128)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'4.KADEME'  ,'RESMI'           ,'4.Kademe'                   ,'KAM', 114)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'4.KADEME'  ,'TİCARİ VE DİĞER' ,'4.Kademe'                   ,'TIC', 107)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 2. KADEME'  ,'5.KADEME'  ,'SANAYİ'          ,'5.Kademe'                   ,'BSA', 129)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 2. KONUT'   ,'2.KADEME'  ,'MERKEZİ ISINMA'  ,'Konut 2K'                   ,'KON',  97)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 2. KONUT'   ,'3.KADEME'  ,'MERKEZİ ISINMA'  ,'Konut 3aK'                  ,'KON',  98)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST 2. KONUT'   ,'4.KADEME'  ,'MERKEZİ ISINMA'  ,'Konut 4K'                   ,'KON', 100)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST OLMAYAN'    ,'1.KADEME'  ,'KONUT'           ,'Konut 1K'                   ,'KON',  96)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST OLMAYAN'    ,'1.KADEME'  ,'MERKEZİ ISINMA'  ,'Konut 1K'                   ,'KON',  96)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST OLMAYAN'    ,'1.KADEME'  ,'RESMI'           ,'Konut 1K'                   ,'KON',  96)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST OLMAYAN'    ,'2.KADEME'  ,'MERKEZİ ISINMA'  ,'Konut 2K'                   ,'KON',  97)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST OLMAYAN'    ,'2.KADEME'  ,'KONUT'           ,'Konut 2K'                   ,'KON',  97)
    INTO TMP_TARIFF_LOOKUP VALUES('SERBEST OLMAYAN'    ,'3.KADEME'  ,'MERKEZİ ISINMA'  ,'Konut 3aK'                  ,'KON',  98)
    INTO TMP_TARIFF_LOOKUP VALUES('TASIMA'             ,'1.KADEME'  ,'SANAYİ'          ,'1.Kademe'                   ,'BSA', 124)
    INTO TMP_TARIFF_LOOKUP VALUES('TASIMA'             ,'3.KADEME'  ,'SANAYİ'          ,'3.Kademe A'                 ,'BSA', 126)
    INTO TMP_TARIFF_LOOKUP VALUES('TASIMA'             ,'4.KADEME'  ,'SANAYİ'          ,'4.Kademe'                   ,'BSA', 128)
    INTO TMP_TARIFF_LOOKUP VALUES('TASIMA'             ,'5.KADEME'  ,'SANAYİ'          ,'5.Kademe'                   ,'BSA', 129)
SELECT 1 FROM DUAL;




    LEFT JOIN MIGRATION.TMP_TARIFF_LOOKUP lk
         ON lk.ABYS_TARIFF_TYPE     = tpl.VALUE
        AND lk.ABYS_SKB_TARIFF_TYPE = stpl.VALUE
        AND lk.ABYS_SUBSCRIBER_TYPE = spl.VALUE