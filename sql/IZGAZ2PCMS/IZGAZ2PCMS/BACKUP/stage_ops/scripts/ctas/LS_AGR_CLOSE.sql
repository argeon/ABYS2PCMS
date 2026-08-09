-- =====================================================================
-- LS_AGR_CLOSE  (Oracle staging - CTAS)
-- Hedef MSSQL kolon isimleriyle birebir, tip olarak Oracle karsiligi
-- 2. gecis gerektiren kolonlar CAST(NULL AS <tip>) ile placeholder
-- =====================================================================
DROP TABLE MIGRATION.LS_AGR_CLOSE PURGE;


 CREATE TABLE MIGRATION.LS_AGR_CLOSE AS
SELECT
    -- LREF: MSSQL tarafinda IDENTITY, staging'de tutulmuyor
    aca.ID AS LREF,
    aca.AGREEMENT_ID                        AS AGRID,                       -- bridge lookup MSSQL tarafinda cozulecek (henuz ham deger)
    CAST(NULL AS NUMBER(19))                AS FITNO,                       -- 2. gecis
    CAST(NULL AS NUMBER(10))                AS BNA_ID,                      -- 2. gecis
    90                                      AS CUSTTYPE,                  
    reg.FIRST_NAME ||' '||   reg.LAST_NAME  AS CUSTNAME,                    -- CS_REGISTER
    reg.IDENTITY_NUMBER                     AS CUSTNO,                      -- CS_REGISTER
    reg.ID                                  AS CUSTREF,                     -- 2. gecis
 
    CAST(NULL AS BINARY_DOUBLE)             AS CURRENT_TLTOTAL,
    CAST(NULL AS BINARY_DOUBLE)             AS CURRENT_CURTOTAL,
    CAST(NULL AS NUMBER(10))                AS CURRENT_CURID,
    CAST(NULL AS BINARY_DOUBLE)             AS CURRENT_RATE,

    aca.DESCRIPTION                         AS DESC_,

CASE
    WHEN agr.REFUND_NUMBER > 0         THEN 5   -- Tamamland�
    WHEN aca.WORK_ORDER_ID IS NULL     THEN 2   -- Mahsupla�ma Bekliyor
    WHEN aca.WORK_ORDER_ID > 0         THEN 4   -- Gaz Kesme Bekliyor
    ELSE 1                                      
END AS STATID,
    --CAST(NULL AS NUMBER(10))                AS STATID,                      -- karar bekliyor

    aca.CREATED_USER_ID                     AS ADDUSER,
    aca.CREATED_TIMESTAMP                   AS ADDDATE,                     -- MSSQL: FN_SAFE_SMALLDT ile cast edilecek
    aca.UPDATED_USER_ID                     AS UPDUSER,
    aca.UPDATED_TIMESTAMP                   AS UPDDATE,                     -- MSSQL: FN_SAFE_SMALLDT ile cast edilecek

    CASE WHEN aca.CANCELLATION_DATE IS NOT NULL THEN 1 ELSE 0 END AS CANCELLED,

    --CAST(NULL AS VARCHAR2(50 CHAR))         AS BNK_NAME,                    -- IBAN parse / lookup MSSQL tarafinda

CASE SUBSTR(REPLACE(aca.PAYABLE_IBAN , ' ', ''), 6, 5)
    WHEN '00001' THEN 'T.C. Merkez Bankas�'
    WHEN '00004' THEN '�ller Bankas�'
    WHEN '00010' THEN 'T.C. Ziraat Bankas�'
    WHEN '00012' THEN 'T�rkiye Halk Bankas�'
    WHEN '00014' THEN 'T�rkiye S�nai Kalk�nma Bankas� (TSKB)'
    WHEN '00015' THEN 'T�rkiye Vak�flar Bankas�'
    WHEN '00016' THEN 'T�rk Eximbank'
    WHEN '00017' THEN 'T�rkiye Kalk�nma Bankas�'
    WHEN '00029' THEN 'Birle�ik Fon Bankas�'
    WHEN '00032' THEN 'T�rk Ekonomi Bankas� (TEB)'
    WHEN '00046' THEN 'Akbank'
    WHEN '00059' THEN '�ekerbank'
    WHEN '00062' THEN 'Garanti BBVA'
    WHEN '00064' THEN 'T�rkiye �� Bankas�'
    WHEN '00067' THEN 'Yap� ve Kredi Bankas�'
    WHEN '00092' THEN 'Citibank'
    WHEN '00099' THEN 'ING Bank'
    WHEN '00111' THEN 'QNB Bank'
    WHEN '00121' THEN 'Standard Chartered Yat�r�m Bankas�'
    WHEN '00122' THEN 'Societe Generale'
    WHEN '00123' THEN 'HSBC Bank'
    WHEN '00124' THEN 'Alternatif Bank'
    WHEN '00125' THEN 'Burgan Bank'
    WHEN '00129' THEN 'Merrill Lynch Yat�r�m Bank'
    WHEN '00132' THEN 'Takasbank'
    WHEN '00134' THEN 'DenizBank'
    WHEN '00135' THEN 'Anadolubank'
    WHEN '00137' THEN 'Rabobank'
    WHEN '00138' THEN 'Dilerbank'
    WHEN '00139' THEN 'GSD Yat�r�m Bankas�'
    WHEN '00141' THEN 'Nurol Yat�r�m Bankas�'
    WHEN '00142' THEN 'Bankpozitif Kredi ve Kalk�nma Bankas�'
    WHEN '00143' THEN 'Aktif Yat�r�m Bankas� (Aktifbank)'
    WHEN '00146' THEN 'Odeabank'
    WHEN '00147' THEN 'MUFG Bank Turkey'
    WHEN '00148' THEN 'Intesa Sanpaolo S.p.A.'
    WHEN '00203' THEN 'Albaraka T�rk Kat�l�m Bankas�'
    WHEN '00205' THEN 'Kuveyt T�rk Kat�l�m Bankas�'
    WHEN '00206' THEN 'T�rkiye Finans Kat�l�m Bankas�'
    WHEN '00209' THEN 'Ziraat Kat�l�m Bankas�'
    WHEN '00210' THEN 'Vak�f Kat�l�m Bankas�'
    WHEN '00211' THEN 'Emlak Kat�l�m Bankas�'
    ELSE 'Di�er / Tan�mlanmayan Banka'
END AS BNK_NAME,
SUBSTR(REPLACE(aca.PAYABLE_IBAN , ' ', ''), 6, 5) AS  BNK_NO,                      -- IBAN parse MSSQL tarafinda
    
    aca.PAYABLE_ACCOUNT_NUMBER              AS BNK_ACCNO,
    aca.PAYABLE_IBAN                        AS BNK_IBAN,
    CAST(NULL AS VARCHAR2(50 CHAR))         AS BNK_DESC,                    -- acik

    CAST(NULL AS VARCHAR2(50 CHAR))         AS ALTERNATE_NAME,              -- acik
    CAST(NULL AS VARCHAR2(50 CHAR))         AS ALTERNATE_NO,                -- acik

    CAST(NULL AS NUMBER(10))                AS PAYTYPE,                     -- ABYS_PAYMENT_TYPE'tan mi turetilecek karar bekliyor
    1                                       AS TYPE_,                       -- default
    CAST(NULL AS NUMBER(10))                AS BANKREF,                     -- ABYS_PAYABLE_BANK_ID'den mi karar bekliyor

    0                                       AS INVOICESTOTAL,               -- acik
    CAST(NULL AS DATE)                      AS COMPLETEDDATE,               -- STATID'e bagimli

    CAST(NULL AS NUMBER(10))                AS LOGO_FIRMNR_RETURN,
    CAST(NULL AS NUMBER(10))                AS LOGO_FICHEREF_RETURN,
    CAST(NULL AS VARCHAR2(50 CHAR))         AS LOGO_FICHENO_RETURN,
    CAST(NULL AS NUMBER(10))                AS LOGO_FIRMNR_REV,
    CAST(NULL AS NUMBER(10))                AS LOGO_FICHEREF_REV,
    CAST(NULL AS VARCHAR2(50 CHAR))         AS LOGO_FICHENO_REV,

    CAST(NULL AS NUMBER(10))                AS DEMAND,

    -- ABYS_* bridge kolonlari
    aca.ID                                   AS ABYS_ID,                    -- oncelikli oneri: eski PK bridge icin eklendi
    aca.AGREEMENT_ID                         AS ABYS_AGREEMENT_ID,
    aca.CANCELLATION_OUT                     AS ABYS_CANCELLATION_OUT,
    aca.PAYABLE_BANK_ID                      AS ABYS_PAYABLE_BANK_ID,
    aca.PAYMENT_TYPE                         AS ABYS_PAYMENT_TYPE,
    aca.PAYEE_NAME                           AS ABYS_PAYEE_NAME,
    aca.PAYEE_IDENTIFICATION_NUMBER          AS ABYS_PAYEE_TCKN,
    aca.PAYABLE_KARD_NUMBER                  AS ABYS_PAYABLE_KARD_NUMBER,
    aca.WORK_ORDER_CAUSE_ID                  AS ABYS_WORK_ORDER_CAUSE_ID,
    aca.WORK_ORDER_ID                        AS ABYS_WORK_ORDER_ID,
    aca.APPOINTMENT_ID                       AS ABYS_APPOINTMENT_ID,
    aca.IS_RUINED_BUILDING                   AS ABYS_IS_RUINED_BUILDING,
    aca.LAST_INDEKS                          AS ABYS_LAST_INDEKS,
    aca.CORRECTOR_LAST_INDEKS                AS ABYS_CORRECTOR_LAST_INDEKS

FROM SMS.CS_AGREEMENT_CLOSING_APP aca
LEFT JOIN SMS.CS_AGREEMENT agr       ON agr.ID = aca.AGREEMENT_ID
LEFT JOIN SMS.CS_REGISTER reg        ON reg.ID = agr.benefited_reg�ster_id        
--LEFT JOIN LS_005_AGR_GUARANTY ag ON ag.AGREEMENT_ID = agr.ID

