-- =====================================================================
-- LS_AGR_CLOSE  (Oracle staging - CTAS)
-- Kaynak : SMS.CS_AGREEMENT_CLOSING_APP (+ agreement / register)
-- Hedef  : MIGRATION.LS_AGR_CLOSE  →  izgazMGR.dbo.LS_AGR_CLOSE
--          → energy.dbo.LS_005_01_AGR_CLOSE
-- Pattern: hedef kolon isimleri birebir; ABYS_* bridge dahil
-- 2. gecis gerektiren kolonlar CAST(NULL AS <tip>) ile placeholder
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_AGR_CLOSE PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_AGR_CLOSE
NOLOGGING
PARALLEL 56
AS
SELECT
    -- LREF: MSSQL tarafinda IDENTITY; staging'de ABYS PK olarak tutuluyor
    aca.ID                                                  AS LREF,
    aca.AGREEMENT_ID                                        AS AGRID,          -- wire: ABYS_AGREEMENT_ID
    CAST(NULL AS NUMBER(19))                                AS FITNO,          -- 2. gecis
    CAST(NULL AS NUMBER(10))                                AS BNA_ID,         -- 2. gecis
    CAST(90 AS NUMBER(10))                                  AS CUSTTYPE,
    reg.FIRST_NAME || ' ' || reg.LAST_NAME                  AS CUSTNAME,
    reg.IDENTITY_NUMBER                                     AS CUSTNO,
    reg.ID                                                  AS CUSTREF,        -- 2. gecis (Energy view NULL yazar)

    CAST(NULL AS BINARY_DOUBLE)                             AS CURRENT_TLTOTAL,
    CAST(NULL AS BINARY_DOUBLE)                             AS CURRENT_CURTOTAL,
    CAST(NULL AS NUMBER(10))                                AS CURRENT_CURID,
    CAST(NULL AS BINARY_DOUBLE)                             AS CURRENT_RATE,

    aca.DESCRIPTION                                         AS DESC_,

    CASE
        WHEN agr.REFUND_NUMBER > 0     THEN 5   -- Tamamlandi
        WHEN aca.WORK_ORDER_ID IS NULL THEN 2   -- Mahsuplasma Bekliyor
        WHEN aca.WORK_ORDER_ID > 0     THEN 4   -- Gaz Kesme Bekliyor
        ELSE 1
    END                                                     AS STATID,

    aca.CREATED_USER_ID                                     AS ADDUSER,
    aca.CREATED_TIMESTAMP                                   AS ADDDATE,
    aca.UPDATED_USER_ID                                     AS UPDUSER,
    aca.UPDATED_TIMESTAMP                                   AS UPDDATE,

    CASE WHEN aca.CANCELLATION_DATE IS NOT NULL THEN 1 ELSE 0 END AS CANCELLED,

    CASE SUBSTR(REPLACE(aca.PAYABLE_IBAN, ' ', ''), 6, 5)
        WHEN '00001' THEN 'T.C. Merkez Bankası'
        WHEN '00004' THEN 'İller Bankası'
        WHEN '00010' THEN 'T.C. Ziraat Bankası'
        WHEN '00012' THEN 'Türkiye Halk Bankası'
        WHEN '00014' THEN 'Türkiye Sınai Kalkınma Bankası (TSKB)'
        WHEN '00015' THEN 'Türkiye Vakıflar Bankası'
        WHEN '00016' THEN 'Türk Eximbank'
        WHEN '00017' THEN 'Türkiye Kalkınma Bankası'
        WHEN '00029' THEN 'Birleşik Fon Bankası'
        WHEN '00032' THEN 'Türk Ekonomi Bankası (TEB)'
        WHEN '00046' THEN 'Akbank'
        WHEN '00059' THEN 'Şekerbank'
        WHEN '00062' THEN 'Garanti BBVA'
        WHEN '00064' THEN 'Türkiye İş Bankası'
        WHEN '00067' THEN 'Yapı ve Kredi Bankası'
        WHEN '00092' THEN 'Citibank'
        WHEN '00099' THEN 'ING Bank'
        WHEN '00111' THEN 'QNB Bank'
        WHEN '00121' THEN 'Standard Chartered Yatırım Bankası'
        WHEN '00122' THEN 'Societe Generale'
        WHEN '00123' THEN 'HSBC Bank'
        WHEN '00124' THEN 'Alternatif Bank'
        WHEN '00125' THEN 'Burgan Bank'
        WHEN '00129' THEN 'Merrill Lynch Yatırım Bank'
        WHEN '00132' THEN 'Takasbank'
        WHEN '00134' THEN 'DenizBank'
        WHEN '00135' THEN 'Anadolubank'
        WHEN '00137' THEN 'Rabobank'
        WHEN '00138' THEN 'Dilerbank'
        WHEN '00139' THEN 'GSD Yatırım Bankası'
        WHEN '00141' THEN 'Nurol Yatırım Bankası'
        WHEN '00142' THEN 'Bankpozitif Kredi ve Kalkınma Bankası'
        WHEN '00143' THEN 'Aktif Yatırım Bankası (Aktifbank)'
        WHEN '00146' THEN 'Odeabank'
        WHEN '00147' THEN 'MUFG Bank Turkey'
        WHEN '00148' THEN 'Intesa Sanpaolo S.p.A.'
        WHEN '00203' THEN 'Albaraka Türk Katılım Bankası'
        WHEN '00205' THEN 'Kuveyt Türk Katılım Bankası'
        WHEN '00206' THEN 'Türkiye Finans Katılım Bankası'
        WHEN '00209' THEN 'Ziraat Katılım Bankası'
        WHEN '00210' THEN 'Vakıf Katılım Bankası'
        WHEN '00211' THEN 'Emlak Katılım Bankası'
        ELSE 'Diğer / Tanımlanmayan Banka'
    END                                                     AS BNK_NAME,
    SUBSTR(REPLACE(aca.PAYABLE_IBAN, ' ', ''), 6, 5)        AS BNK_NO,

    aca.PAYABLE_ACCOUNT_NUMBER                              AS BNK_ACCNO,
    aca.PAYABLE_IBAN                                        AS BNK_IBAN,
    CAST(NULL AS VARCHAR2(50 CHAR))                         AS BNK_DESC,

    CAST(NULL AS VARCHAR2(50 CHAR))                         AS ALTERNATE_NAME,
    CAST(NULL AS VARCHAR2(50 CHAR))                         AS ALTERNATE_NO,

    CAST(NULL AS NUMBER(10))                                AS PAYTYPE,        -- ABYS_PAYMENT_TYPE karar bekliyor
    CAST(1 AS NUMBER(10))                                   AS TYPE_,
    CAST(NULL AS NUMBER(10))                                AS BANKREF,        -- wire: ABYS_PAYABLE_BANK_ID

    CAST(0 AS BINARY_DOUBLE)                                AS INVOICESTOTAL,
    CAST(NULL AS DATE)                                      AS COMPLETEDDATE,  -- STATID'e bagimli

    CAST(NULL AS NUMBER(10))                                AS LOGO_FIRMNR_RETURN,
    CAST(NULL AS NUMBER(10))                                AS LOGO_FICHEREF_RETURN,
    CAST(NULL AS VARCHAR2(50 CHAR))                         AS LOGO_FICHENO_RETURN,
    CAST(NULL AS NUMBER(10))                                AS LOGO_FIRMNR_REV,
    CAST(NULL AS NUMBER(10))                                AS LOGO_FICHEREF_REV,
    CAST(NULL AS VARCHAR2(50 CHAR))                         AS LOGO_FICHENO_REV,

    CAST(NULL AS NUMBER(10))                                AS DEMAND,

    -- ABYS_* bridge
    aca.ID                                                  AS ABYS_ID,
    aca.AGREEMENT_ID                                        AS ABYS_AGREEMENT_ID,
    aca.CANCELLATION_OUT                                    AS ABYS_CANCELLATION_OUT,
    aca.PAYABLE_BANK_ID                                     AS ABYS_PAYABLE_BANK_ID,
    aca.PAYMENT_TYPE                                        AS ABYS_PAYMENT_TYPE,
    aca.PAYEE_NAME                                          AS ABYS_PAYEE_NAME,
    aca.PAYEE_IDENTIFICATION_NUMBER                         AS ABYS_PAYEE_TCKN,
    aca.PAYABLE_KARD_NUMBER                                 AS ABYS_PAYABLE_KARD_NUMBER,
    aca.WORK_ORDER_CAUSE_ID                                 AS ABYS_WORK_ORDER_CAUSE_ID,
    aca.WORK_ORDER_ID                                       AS ABYS_WORK_ORDER_ID,
    aca.APPOINTMENT_ID                                      AS ABYS_APPOINTMENT_ID,
    aca.IS_RUINED_BUILDING                                  AS ABYS_IS_RUINED_BUILDING,
    aca.LAST_INDEKS                                         AS ABYS_LAST_INDEKS,
    aca.CORRECTOR_LAST_INDEKS                               AS ABYS_CORRECTOR_LAST_INDEKS
FROM SMS.CS_AGREEMENT_CLOSING_APP aca
LEFT JOIN SMS.CS_AGREEMENT agr
    ON agr.ID = aca.AGREEMENT_ID
LEFT JOIN SMS.CS_REGISTER reg
    ON reg.ID = agr.BENEFITED_REGISTER_ID
;

ALTER TABLE MIGRATION.LS_AGR_CLOSE NOPARALLEL LOGGING;

CREATE UNIQUE INDEX MIGRATION.UX_LS_AGR_CLOSE_ABYS_ID
    ON MIGRATION.LS_AGR_CLOSE (ABYS_ID) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IDX_LS_AGR_CLOSE_AGRID
    ON MIGRATION.LS_AGR_CLOSE (AGRID) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IDX_LS_AGR_CLOSE_ABYS_AGR
    ON MIGRATION.LS_AGR_CLOSE (ABYS_AGREEMENT_ID) NOLOGGING PARALLEL 4;

ALTER INDEX MIGRATION.UX_LS_AGR_CLOSE_ABYS_ID   NOPARALLEL;
ALTER INDEX MIGRATION.IDX_LS_AGR_CLOSE_AGRID    NOPARALLEL;
ALTER INDEX MIGRATION.IDX_LS_AGR_CLOSE_ABYS_AGR NOPARALLEL;

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_AGR_CLOSE', cascade => TRUE, degree => 56);
END;
/

-- dogrulama
SELECT 'CS_AGREEMENT_CLOSING_APP' KAYNAK, COUNT(*) CNT FROM SMS.CS_AGREEMENT_CLOSING_APP
UNION ALL
SELECT 'LS_AGR_CLOSE', COUNT(*) FROM MIGRATION.LS_AGR_CLOSE
UNION ALL
SELECT 'LS_AGR_CLOSE_STATID_5', COUNT(*) FROM MIGRATION.LS_AGR_CLOSE WHERE STATID = 5;
