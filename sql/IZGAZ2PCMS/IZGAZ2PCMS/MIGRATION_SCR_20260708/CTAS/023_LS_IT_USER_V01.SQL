-- 023_LS_IT_USER_V01.SQL
-- Amac: Kullanici staging
-- Uretir: LS_IT_USER
-- Gate: yok
-- Sonraki: 024_LS_AGREEMENT_V01.SQL
-- =====================================================================
-- LS_IT_USER  (Oracle staging - CTAS)
-- Kaynak : SMS.IT_USER
-- Hedef  : MIGRATION.LS_IT_USER  →  izgazMGR.dbo.LS_IT_USER
--          → energy.dbo.LS_USER  (110/111 REF_IT_USER)
-- Pattern: kaynak kolon isimleri birebir; ABYS_ID = ID bridge
--
-- Not:
--   PICTURE (BLOB) staging'e alinmaz — dump/CTAS maliyeti yuksek,
--   Energy migrate kullanmiyor (PICTURE_DOC_ID yeterli).
--   LOCATION (SDO_GEOMETRY) → LOCATION_WKT VARCHAR2(4000)
--     (SDO_UTIL.TO_WKTGEOMETRY CLOB; parallel CTAS → ORA-00932).
--   IT_USER kucuk → seri CTAS (PARALLEL yok).
--   Energy USERID = ABYS_ID + 10000 (migrate tarafinda).
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- TERMINAL DUMP: Oracle INDEX / GATHER_TABLE_STATS yok (CTAS zincirinde tuketilmiyor; IX -> izgazMGR/energy).

-- LOB/SDO + PARALLEL CTAS = ORA-00932; bu tablo icin parallel kapat
ALTER SESSION DISABLE PARALLEL QUERY;
ALTER SESSION DISABLE PARALLEL DML;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_IT_USER PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_IT_USER
NOLOGGING
AS
SELECT
    u.ID                                                    AS ID,
    u.ID                                                    AS ABYS_ID,
    u.USER_NAME                                             AS USER_NAME,
    u.PASSWORD                                              AS PASSWORD,
    u.PASSWORD_TRY_NUMBER                                   AS PASSWORD_TRY_NUMBER,
    u.PASSWORD_RECOVERY_QUESTION                            AS PASSWORD_RECOVERY_QUESTION,
    u.PASSWORD_RECOVERY_ANSWER                              AS PASSWORD_RECOVERY_ANSWER,
    u.EMAIL                                                 AS EMAIL,
    u.LAST_ENTRY_DATE                                       AS LAST_ENTRY_DATE,
    u.IS_LOCK                                               AS IS_LOCK,
    u.FORCE_PASSWORD_CHANGE                                 AS FORCE_PASSWORD_CHANGE,
    u.LANG_ID                                               AS LANG_ID,
    u.THEME_ID                                              AS THEME_ID,
    u.DATE_FORMAT                                           AS DATE_FORMAT,
    u.DEFAULT_CORPORATION_ID                                AS DEFAULT_CORPORATION_ID,
    u.WORK_PLACE_ID                                         AS WORK_PLACE_ID,
    u.REGISTER_ID                                           AS REGISTER_ID,
    CASE
        WHEN u.LOCATION IS NULL THEN CAST(NULL AS VARCHAR2(4000))
        ELSE DBMS_LOB.SUBSTR(SDO_UTIL.TO_WKTGEOMETRY(u.LOCATION), 4000, 1)
    END                                                     AS LOCATION_WKT,
    u.NOTIFICATION_SOUND                                    AS NOTIFICATION_SOUND,
    u.IS_ACTIVE                                             AS IS_ACTIVE,
    u.CREATED_USER_ID                                       AS CREATED_USER_ID,
    CAST(u.CREATED_TIMESTAMP AS TIMESTAMP)                  AS CREATED_TIMESTAMP,
    u.UPDATED_USER_ID                                       AS UPDATED_USER_ID,
    CAST(u.UPDATED_TIMESTAMP AS TIMESTAMP)                  AS UPDATED_TIMESTAMP,
    u.VERSION                                               AS VERSION,
    u.USER_LOGIN_TYPE                                       AS USER_LOGIN_TYPE,
    u.BATTERY_STATUS                                        AS BATTERY_STATUS,
    u.GPS_STATUS                                            AS GPS_STATUS,
    u.PASSWORD_CHANGE_DATE                                  AS PASSWORD_CHANGE_DATE,
    u.SESSION_KEY                                           AS SESSION_KEY,
    u.LOGOUT_MESSAGE                                        AS LOGOUT_MESSAGE,
    u.SSO_USER_NAME                                         AS SSO_USER_NAME,
    u.TWO_FACTOR_AUTHENTICATION_TYPE                        AS TWO_FACTOR_AUTHENTICATION_TYPE,
    u.TWO_FACTOR_AUTHENTICATION_KEY                         AS TWO_FACTOR_AUTHENTICATION_KEY,
    u.TWO_FACTOR_AUTH_EXPIRY_DATE                           AS TWO_FACTOR_AUTH_EXPIRY_DATE,
    u.PICTURE_DOC_ID                                        AS PICTURE_DOC_ID,
    u.VERIFICATION_TYPE_FOR_PASSWORD                        AS VERIFICATION_TYPE_FOR_PASSWORD,
    u.VERIFY_CODE                                           AS VERIFY_CODE,
    CAST(u.VERIFY_DATE AS TIMESTAMP)                        AS VERIFY_DATE
FROM SMS.IT_USER u
;

ALTER TABLE MIGRATION.LS_IT_USER LOGGING;


-- dogrulama
SELECT 'IT_USER' KAYNAK, COUNT(*) CNT FROM SMS.IT_USER
UNION ALL
SELECT 'LS_IT_USER', COUNT(*) FROM MIGRATION.LS_IT_USER
UNION ALL
SELECT 'LS_IT_USER_ACTIVE', COUNT(*) FROM MIGRATION.LS_IT_USER WHERE IS_ACTIVE = 1
UNION ALL
SELECT 'LS_IT_USER_LOCKED', COUNT(*) FROM MIGRATION.LS_IT_USER WHERE IS_LOCK = 1
UNION ALL
SELECT 'LS_IT_USER_WITH_REG', COUNT(*) FROM MIGRATION.LS_IT_USER WHERE REGISTER_ID IS NOT NULL;

-- Sonraki master'lar (AGREEMENT+) icin session parallel geri
ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

PROMPT ========== LS_IT_USER OK ==========
/

