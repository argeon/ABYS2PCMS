-- =====================================================================
-- LS_REGISTER  (Oracle staging - CTAS)
-- Kaynak : SMS.CS_REGISTER
-- Hedef  : MIGRATION.LS_REGISTER  →  izgazMGR.dbo.LS_REGISTER
--          (Energy: LS_005_SUBSCR / LS_005_FIRM)
-- Pattern: kaynak kolon isimleri birebir; ABYS_ID = ID bridge
--
-- Not:
--   LOGO (BLOB) staging'e alinmaz — dump/CTAS maliyeti yuksek,
--   Energy migrate kullanmiyor.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_REGISTER PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_REGISTER
NOLOGGING
PARALLEL 56
AS
SELECT
    r.ID                                                    AS ID,
    r.ID                                                    AS ABYS_ID,
    r.CODE                                                  AS CODE,
    r.FIRST_NAME                                            AS FIRST_NAME,
    r.LAST_NAME                                             AS LAST_NAME,
    r.MAIDEN_NAME                                           AS MAIDEN_NAME,
    r.IDENTITY_NUMBER                                       AS IDENTITY_NUMBER,
    r.IDENTITY_SERIAL                                       AS IDENTITY_SERIAL,
    r.IDENTITY_PROVINCE                                     AS IDENTITY_PROVINCE,
    r.IDENTITY_DISTRICT                                     AS IDENTITY_DISTRICT,
    r.IDENTITY_QUARTER                                      AS IDENTITY_QUARTER,
    r.IDENTITY_QUARTER_ID                                   AS IDENTITY_QUARTER_ID,
    r.IDENTITY_VOLUME_NUMBER                                AS IDENTITY_VOLUME_NUMBER,
    r.IDENTITY_FAMILY_ROW_NUMBER                            AS IDENTITY_FAMILY_ROW_NUMBER,
    r.IDENTITY_ROW_NUMBER                                   AS IDENTITY_ROW_NUMBER,
    r.IDENTITY_REASON_FOR_ISSUE                             AS IDENTITY_REASON_FOR_ISSUE,
    r.IDENTITY_REGISTRATION_NUMBER                          AS IDENTITY_REGISTRATION_NUMBER,
    r.IDENTITY_ISSUE_DATE                                   AS IDENTITY_ISSUE_DATE,
    r.BIRTH_PLACE                                           AS BIRTH_PLACE,
    r.BIRTH_DATE                                            AS BIRTH_DATE,
    r.MOTHER_NAME                                           AS MOTHER_NAME,
    r.FATHER_NAME                                           AS FATHER_NAME,
    r.GENDER                                                AS GENDER,
    r.DRV_LICENSE_NUMBER                                    AS DRV_LICENSE_NUMBER,
    r.DRV_LICENSE_CLASS_ID                                  AS DRV_LICENSE_CLASS_ID,
    r.DRV_LICENSE_DATE                                      AS DRV_LICENSE_DATE,
    r.TAX_NUMBER                                            AS TAX_NUMBER,
    r.TAX_OFFICE                                            AS TAX_OFFICE,
    r.DESCRIPTION                                           AS DESCRIPTION,
    r.JOB_ID                                                AS JOB_ID,
    r.CHAMBER_CODE                                          AS CHAMBER_CODE,
    r.CHAMBER_NAME                                          AS CHAMBER_NAME,
    r.SOCIAL_SECURITY_NUMBER                                AS SOCIAL_SECURITY_NUMBER,
    r.DEAD_DATE                                             AS DEAD_DATE,
    r.IS_COMMINICATION_PERMIT                               AS IS_COMMINICATION_PERMIT,
    r.ACCOUNT_CODE                                          AS ACCOUNT_CODE,
    r.FIRM_CLASS_ID                                         AS FIRM_CLASS_ID,
    r.HR_REGISTER_NUMBER                                    AS HR_REGISTER_NUMBER,
    r.ATTORNEY_BAR_NUMBER                                   AS ATTORNEY_BAR_NUMBER,
    r.ATTORNEY_BAR_ASSOCIATION_NUM                          AS ATTORNEY_BAR_ASSOCIATION_NUM,
    r.ATTORNEY_OFFICE_NAME                                  AS ATTORNEY_OFFICE_NAME,
    r.NATIONAL_ID                                           AS NATIONAL_ID,
    r.CREATED_USER_ID                                       AS CREATED_USER_ID,
    r.IBAN                                                  AS IBAN,
    r.IS_LOST                                               AS IS_LOST,
    r.IS_E_BILL_CUSTOMER                                    AS IS_E_BILL_CUSTOMER,
    r.VERSION                                               AS VERSION,
    CAST(r.CREATED_TIMESTAMP AS TIMESTAMP)                  AS CREATED_TIMESTAMP,
    r.UPDATED_USER_ID                                       AS UPDATED_USER_ID,
    CAST(r.UPDATED_TIMESTAMP AS TIMESTAMP)                  AS UPDATED_TIMESTAMP,
    r.DELETED_USER_ID                                       AS DELETED_USER_ID,
    CAST(r.DELETED_TIMESTAMP AS TIMESTAMP)                  AS DELETED_TIMESTAMP,
    r.EDUCATION_STATUS_ID                                   AS EDUCATION_STATUS_ID,
    r.RETIRE_STATUS_ID                                      AS RETIRE_STATUS_ID,
    r.IDENTITY_ADDRESS                                      AS IDENTITY_ADDRESS,
    r.LOST_DESCRIPTION                                      AS LOST_DESCRIPTION,
    r.LOST_USER_ID                                          AS LOST_USER_ID,
    r.LOST_DATE                                             AS LOST_DATE,
    r.E_BILL_CUSTOMER_DATE                                  AS E_BILL_CUSTOMER_DATE,
    r.POOL_ID                                               AS POOL_ID,
    r.IDENTITY_SERIAL_NUMBER                                AS IDENTITY_SERIAL_NUMBER,
    r.IDENTITY_CHANGE_DATE                                  AS IDENTITY_CHANGE_DATE,
    r.CUSTOMER_BILL_TYPE                                    AS CUSTOMER_BILL_TYPE,
    r.PASSPORT_NUMBER                                       AS PASSPORT_NUMBER,
    r.PASSPORT_VALIDITY_DATE                                AS PASSPORT_VALIDITY_DATE,
    r.COUNTRY_ENTRY_DATE                                    AS COUNTRY_ENTRY_DATE,
    r.COUNTRY_LEAVE_DATE                                    AS COUNTRY_LEAVE_DATE,
    r.PICTURE_DOC_ID                                        AS PICTURE_DOC_ID,
    r.IS_SANITARY_INSTALLATION_ENG                          AS IS_SANITARY_INSTALLATION_ENG,
    r.SECRET_REGISTER_ID                                    AS SECRET_REGISTER_ID,
    r.PERMIT_START_DATE                                     AS PERMIT_START_DATE,
    r.PERMIT_EXPIRE_DATE                                    AS PERMIT_EXPIRE_DATE,
    r.POOL_DEBT                                             AS POOL_DEBT,
    r.POOL_DEBT_COUNT                                       AS POOL_DEBT_COUNT,
    r.BANKRUPTCY_RECORD                                     AS BANKRUPTCY_RECORD,
    r.HAS_EXPRESS_CONSENT                                   AS HAS_EXPRESS_CONSENT,
    r.IS_SMS_CONTACT_ALLOWED                                AS IS_SMS_CONTACT_ALLOWED,
    r.IS_CALL_CONTACT_ALLOWED                               AS IS_CALL_CONTACT_ALLOWED,
    r.IS_EMAIL_CONTACT_ALLOWED                              AS IS_EMAIL_CONTACT_ALLOWED,
    r.IS_MARKETING_CONSENT_GIVEN                            AS IS_MARKETING_CONSENT_GIVEN
FROM SMS.CS_REGISTER r
;

ALTER TABLE MIGRATION.LS_REGISTER NOPARALLEL LOGGING;

CREATE UNIQUE INDEX MIGRATION.UX_LS_REGISTER_ID
    ON MIGRATION.LS_REGISTER (ID) NOLOGGING PARALLEL 4;

CREATE UNIQUE INDEX MIGRATION.UX_LS_REGISTER_ABYS_ID
    ON MIGRATION.LS_REGISTER (ABYS_ID) NOLOGGING PARALLEL 4;

CREATE UNIQUE INDEX MIGRATION.UX_LS_REGISTER_CODE
    ON MIGRATION.LS_REGISTER (CODE) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IDX_LS_REGISTER_TC
    ON MIGRATION.LS_REGISTER (IDENTITY_NUMBER) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IDX_LS_REGISTER_TAX
    ON MIGRATION.LS_REGISTER (TAX_NUMBER) NOLOGGING PARALLEL 4;

ALTER INDEX MIGRATION.UX_LS_REGISTER_ID      NOPARALLEL;
ALTER INDEX MIGRATION.UX_LS_REGISTER_ABYS_ID NOPARALLEL;
ALTER INDEX MIGRATION.UX_LS_REGISTER_CODE    NOPARALLEL;
ALTER INDEX MIGRATION.IDX_LS_REGISTER_TC     NOPARALLEL;
ALTER INDEX MIGRATION.IDX_LS_REGISTER_TAX    NOPARALLEL;

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_REGISTER', cascade => TRUE, degree => 4);
END;
/

-- dogrulama
SELECT 'CS_REGISTER' KAYNAK, COUNT(*) CNT FROM SMS.CS_REGISTER
UNION ALL
SELECT 'LS_REGISTER', COUNT(*) FROM MIGRATION.LS_REGISTER
UNION ALL
SELECT 'LS_REGISTER_DELETED', COUNT(*) FROM MIGRATION.LS_REGISTER WHERE DELETED_TIMESTAMP IS NOT NULL
UNION ALL
SELECT 'LS_REGISTER_LOST', COUNT(*) FROM MIGRATION.LS_REGISTER WHERE IS_LOST = 1;
