-- =====================================================================
-- LS_WORK  (Oracle staging - CTAS)
-- Kaynak : SMS.WO_WORK
-- Hedef  : MIGRATION.LS_WORK  →  izgazMGR.dbo.LS_WORK
--          → energy.dbo.LS_005_01_CS_APPOINTMENT  (530/531)
-- Pattern: hedef kolon isimleri birebir; ABYS_* bridge dahil
--
-- Pass 1 dump (migrate tarafı JOIN yapmaz):
--   LREF = WO_WORK.ID = ABYS_ID
--   ASSINGPERSON = ASSIGNEE_USER_ID (ham ID; isim wire sonra)
--   ASSINGSTATUS = WO_WORK.STATUS (Energy sozlugu birebir):
--     1=Yeni 2=Atandı 3=Terminalde 4=Red 5=Tamamlandı
--     6=İptal 7=Problemli Tamamlandı (+ABYS 8/9/10 ham)
--   WORK_ORDER_PROCESS (WO_WORK'te yok; durumdan turetilir):
--     1=İş Emri Ataması  2=Atama İptali  3=İş Emri İptal
--   ABYS_LOCATION_WKT = NULL (CTAS'ta SDO yok)
--     SDO_UTIL.TO_WKTGEOMETRY + seri CTAS → saatler surer / ORA-00932 riski.
--     Energy 531 migrate ABYS_LOCATION_WKT kolonunu zaten comment'li (kullanmiyor).
--     LOB kolonlar SUBSTR → VARCHAR2 (PARALLEL CTAS guvenli).
--
-- Proje sonu wire (910_OPS_AFTER):
--   TYPEID, BINAID, WO_TYPE_ID, AGRID→LREF remap, DAY15DEBTREF…
--   Bu alanlar burada NULL / ham birakilir.
--
-- DOP: FORCE PARALLEL 56
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_WORK PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

PROMPT ========== LS_WORK CTAS PARALLEL 56 (WKT=NULL) START ==========

CREATE TABLE MIGRATION.LS_WORK
NOLOGGING
PARALLEL 56
AS
SELECT /*+ PARALLEL(wo 56) */
    -- PK / bridge
    wo.ID                                                       AS LREF,
    wo.ID                                                       AS ABYS_ID,

    -- Energy CS_APPOINTMENT (Pass 1; TYPEID/BINAID wire sonra)
    CAST(NULL AS NUMBER(10))                                    AS TYPEID,
    wo.AGREEMENT_ID                                             AS AGRID,
    wo.FIRM_REGISTER_ID                                         AS FITNO,
    bd.CODE                                   AS BINAID,
    wo.APPOINTMENT_DATE                                         AS SDATE,
    wo.STATUS                                                   AS STATID,
    wo.ASSIGNEE_USER_ID                                         AS APPUSER,
    SUBSTR(wo.ADDRESS_DESCRIPTION, 1, 600)                      AS ADDR,

    wo.METER_ID                                                 AS CNTID,
    SUBSTR(RTRIM(LTRIM(m.METER_NUMBER)), 1, 20)                 AS CNTSN,
    SUBSTR(TO_CHAR(m.METER_MODEL_ID), 1, 10)                    AS CNTMODEL,
    TRUNC(wo.LAST_INDEX)                                        AS READENDEX,
    CAST(NULL AS NUMBER(10))                                    AS CURRENTENDEX,

    wo.UPDATED_USER_ID                                          AS PRCUSER,
    CAST(SYS_EXTRACT_UTC(wo.UPDATED_TIMESTAMP) AS DATE)         AS PRCDATE,
    CAST(SYS_EXTRACT_UTC(wo.CREATED_TIMESTAMP) AS DATE)         AS ADDDATE,
    wo.CREATED_USER_ID                                          AS ADDUSER,
    wo.UPDATED_USER_ID                                          AS UPDUSER,
    CAST(SYS_EXTRACT_UTC(wo.UPDATED_TIMESTAMP) AS DATE)         AS UPDDATE,

    CASE
        WHEN wo.STATUS = 6
          OR wo.CANCELLATION_TIME_STAMP IS NOT NULL
        THEN CAST(1 AS NUMBER(1))
        ELSE CAST(0 AS NUMBER(1))
    END                                                         AS CANCELLED,
    CAST(SYS_EXTRACT_UTC(wo.CANCELLATION_TIME_STAMP) AS DATE)   AS CANCEL_DATE,
    SUBSTR(wo.CANCELLATION_DESCRIPTION, 1, 500)                 AS CANCEL_DESCRIPTION,

    CAST(NULL AS NUMBER(10))                                    AS DAY15DEBTREF,
    CAST(NULL AS NUMBER(10))                                    AS OBJECTIONREF,
    CAST(NULL AS NUMBER(10))                                    AS CLOSEREF,

    wo.REGISTER_ID                                              AS CUSTREF,
    CAST(NULL AS NUMBER(3))                                     AS CUSTYPE,
    CAST(NULL AS NUMBER(1))                                     AS IS_INDUSTRY,
    SUBSTR(TRIM(reg.FIRST_NAME || ' ' || reg.LAST_NAME), 1, 250) AS CUSTNAME,
    CAST(NULL AS NUMBER(1))                                     AS IS_PREPAID,
    CAST(NULL AS NUMBER(1))                                     AS DELETED,

    wo.DEBT_BILL_COUNT                                          AS INVCOUNT,
    CAST(wo.TOTAL_DEBT AS BINARY_DOUBLE)                        AS INVTOTAL,
    CAST(NULL AS DATE)                                          AS PAIDDATE,
    CAST(NULL AS NUMBER(18,2))                                  AS GUVENCE_BEDELI,
    CAST(NULL AS NUMBER(10))                                    AS USULSUZINVCOUNT,
    CAST(NULL AS NUMBER(10))                                    AS LAWSTATID,

    CAST(NULL AS VARCHAR2(50 CHAR))                             AS READ_STATUS,
    -- CNT_STATUS: CS_INSTALLATION_STATUS_PRM_LNG (LANG_ID=1)
    SUBSTR(isp.VALUE, 1, 50)                                    AS CNT_STATUS,
    wo.LAST_READING_DATE                                        AS LASTREAD_DATE,
    CASE
        WHEN wo.APPOINTMENT_DATE IS NULL OR wo.LAST_READING_DATE IS NULL THEN NULL
        ELSE TRUNC(wo.APPOINTMENT_DATE) - TRUNC(wo.LAST_READING_DATE)
    END                                                         AS DATE_DIFF,

    CAST(NULL AS VARCHAR2(50 CHAR))                             AS TP1,
    CAST(NULL AS VARCHAR2(50 CHAR))                             AS AGRSTATID,

    wo.APPOINTMENT_DATE                                         AS ASSINGDATE,
    wo.STATUS                                                   AS ASSINGSTATUS,
    wo.ASSIGNEE_USER_ID                                         AS ASSINGPERSON,

    wo.WORK_ORDER_DATE                                          AS WO_DATE,
    CAST(wo.APPOINTMENT_DATE AS DATE)                           AS WO_APPOINTMENT_DATE,
    wo.PARENT_ID                                                AS PARENT_ID,
    -- 910: LS_WORK_ORDER_CAUSE.WO_TYPE_CODE ile wire
    CAST(NULL AS NUMBER(10))                                    AS WO_TYPE_ID,
    wo.CAUSE_ID                                                 AS WO_CAUSE_ID,

    -- WORK_ORDER_PROCESS: Energy 1=Atama / 2=Atama iptal / 3=İş emri iptal
    CASE
        WHEN wo.STATUS = 6
          OR wo.CANCELLATION_TIME_STAMP IS NOT NULL
        THEN CAST(3 AS NUMBER(3))
        WHEN wo.ASSIGNEE_USER_ID IS NULL
         AND wo.CHANGE_ASSIGNEE_USER_ID IS NOT NULL
        THEN CAST(2 AS NUMBER(3))
        WHEN wo.ASSIGNEE_USER_ID IS NOT NULL
        THEN CAST(1 AS NUMBER(3))
        ELSE CAST(NULL AS NUMBER(3))
    END                                                         AS WORK_ORDER_PROCESS_ID,
    CASE
        WHEN wo.STATUS = 6
          OR wo.CANCELLATION_TIME_STAMP IS NOT NULL
        THEN CAST(SYS_EXTRACT_UTC(wo.CANCELLATION_TIME_STAMP) AS DATE)
        WHEN wo.ASSIGNEE_USER_ID IS NULL
         AND wo.CHANGE_ASSIGNEE_USER_ID IS NOT NULL
        THEN CAST(SYS_EXTRACT_UTC(wo.UPDATED_TIMESTAMP) AS DATE)
        WHEN wo.ASSIGNEE_USER_ID IS NOT NULL
        THEN NVL(wo.APPOINTMENT_DATE,
                 CAST(SYS_EXTRACT_UTC(wo.UPDATED_TIMESTAMP) AS DATE))
        ELSE CAST(NULL AS DATE)
    END                                                         AS WORK_ORDER_PROCESS_TIMESTAMP,
    CASE
        WHEN wo.STATUS = 6
          OR wo.CANCELLATION_TIME_STAMP IS NOT NULL
        THEN wo.CANCELLATION_USER_ID
        WHEN wo.ASSIGNEE_USER_ID IS NULL
         AND wo.CHANGE_ASSIGNEE_USER_ID IS NOT NULL
        THEN wo.CHANGE_ASSIGNEE_USER_ID
        WHEN wo.ASSIGNEE_USER_ID IS NOT NULL
        THEN wo.ASSIGNEE_USER_ID
        ELSE CAST(NULL AS NUMBER(10))
    END                                                         AS WORK_ORDER_PROCESS_USER_ID,

    -- ABYS bridge (ham ABYS alanlari)
    wo.QUARTER_STREET_ID                                        AS ABYS_QUARTER_STREET_ID,
    wo.METER_STATUS_ID                                          AS ABYS_METER_STATUS_ID,
    wo.TARIFF_TYPE_ID                                           AS ABYS_TARIFF_TYPE_ID,
    wo.LAST_CORRECTOR_INDEX                                     AS ABYS_LAST_CORRECTOR_INDEX,
    wo.SKB_TARIFF_TYPE_ID                                       AS ABYS_SKB_TARIFF_TYPE_ID,
    wo.IS_DEBT_PAYED                                            AS ABYS_IS_DEBT_PAYED,
    wo.ILLEGAL_USE_ID                                           AS ABYS_ILLEGAL_USE_ID,
    wo.PRIORITY_ID                                              AS ABYS_PRIORITY_ID,
    wo.WORK_ORDER_NUMBER                                        AS ABYS_WORK_ORDER_NUMBER,
    wo.REGISTER_ID                                              AS ABYS_REGISTER_ID,
    wo.INSTALLATION_ID                                          AS ABYS_INSTALLATION_ID,
    wo.SUBSCRIBER_TYPE_ID                                       AS ABYS_SUBSCRIBER_TYPE_ID,
    SUBSTR(wo.UNIT_NUMBER, 1, 20)                               AS ABYS_UNIT_NUMBER,
    wo.DO_PRINT                                                 AS ABYS_DO_PRINT,
    wo.AREA_ID                                                  AS ABYS_AREA_ID,
    wo.SENDING_TYPE                                             AS ABYS_SENDING_TYPE,
    SUBSTR(wo.DESCRIPTION, 1, 4000)                             AS ABYS_DESCRIPTION,
    wo.CHANGE_ASSIGNEE_USER_ID                                  AS ABYS_CHANGE_ASSIGNEE_USER_ID,
    wo.CONTROLLED_WORK_ID                                       AS ABYS_CONTROLLED_WORK_ID,
    wo.IS_DESTRUCTION_BUILDING                                  AS ABYS_IS_DESTRUCTION_BUILDING,
    wo.LAST_CUTTING_TYPE_ID                                     AS ABYS_LAST_CUTTING_TYPE_ID,
    wo.LAST_CUTTING_DATE                                        AS ABYS_LAST_CUTTING_DATE,
    wo.INSTALLATION_STATUS_ID                                   AS ABYS_INSTALLATION_STATUS_ID,
    wo.PAYMENT_STATUS                                           AS ABYS_PAYMENT_STATUS,
    wo.POOL_ID                                                  AS ABYS_POOL_ID,
    SUBSTR(wo.INTEGRATION_CODE, 1, 20)                          AS ABYS_INTEGRATION_CODE,
    wo.CANCELLATION_USER_ID                                     AS ABYS_CANCELLATION_USER_ID,
    wo.VERSION                                                  AS ABYS_VERSION,
    wo.CONTROLLED_READING_ID                                    AS ABYS_CONTROLLED_READING_ID,
    CAST(NULL AS VARCHAR2(4000))                                AS ABYS_LOCATION_WKT,
    SUBSTR(wo.INCOME_LIST, 1, 4000)                             AS ABYS_INCOME_LIST,
    wo.WORK_REQUEST_ID                                          AS ABYS_WORK_REQUEST_ID,
    wo.LAST_RETROKIT_INDEX                                      AS ABYS_LAST_RETROKIT_INDEX,
    wo.WORK_EAM_ID                                              AS ABYS_WORK_EAM_ID,
    wo.ASSIGNEE_TEAM_ID                                         AS ABYS_ASSIGNEE_TEAM_ID,
    wo.DISCOVERY_WORK_ID                                        AS ABYS_DISCOVERY_WORK_ID,
    wo.CREDIT                                                   AS ABYS_CREDIT,
    wo.LAST_INDEX                                               AS ABYS_LAST_INDEX,
    wo.LAST_ELECTRONIC_INDEX                                    AS ABYS_LAST_ELECTRONIC_INDEX,
    SUBSTR(wo.CANCELLATION_DESCRIPTION, 1, 4000)                AS ABYS_CANCEL_DESCRIPTION_FULL,
    ss.BUILDING_FLAT_ID                                         AS ABYS_BUILDING_FLAT_ID

FROM SMS.WO_WORK wo
LEFT JOIN SMS.CS_METER m    ON m.ID = wo.METER_ID
LEFT JOIN SMS.CS_REGISTER reg    ON reg.ID = wo.REGISTER_ID
LEFT JOIN SMS.CS_INSTALLATION_STATUS_PRM_LNG isp    ON isp.PRM_ID = wo.INSTALLATION_STATUS_ID   AND isp.LANG_ID = 1
LEFT JOIN SMS.CS_INSTALLATION i on i.id = wo.INSTALLATION_ID
LEFT JOIN SMS.CS_SUBSCRIBER ss on ss.ID = i.SUBSCRIBER_ID
LEFT JOIN SMS.GIS_BUILDING_FLAT bf on bf.ID = ss.BUILDING_FLAT_ID
LEFT JOIN SMS.GIS_BUILDING_DOOR bd on bd.ID = bf.BUILDING_DOOR_ID

;

ALTER TABLE MIGRATION.LS_WORK NOPARALLEL LOGGING;

CREATE UNIQUE INDEX MIGRATION.UX_LS_WORK_LREF
    ON MIGRATION.LS_WORK (LREF) NOLOGGING PARALLEL 56;
ALTER INDEX MIGRATION.UX_LS_WORK_LREF NOPARALLEL;

CREATE INDEX MIGRATION.IDX_LS_WORK_AGRID
    ON MIGRATION.LS_WORK (AGRID) NOLOGGING PARALLEL 56;
ALTER INDEX MIGRATION.IDX_LS_WORK_AGRID NOPARALLEL;

CREATE INDEX MIGRATION.IDX_LS_WORK_CAUSE
    ON MIGRATION.LS_WORK (WO_CAUSE_ID) NOLOGGING PARALLEL 56;
ALTER INDEX MIGRATION.IDX_LS_WORK_CAUSE NOPARALLEL;

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_WORK', degree => 56);
END;
/

PROMPT ========== LS_WORK CTAS OK ==========

-- =====================================================================
-- Gate (manuel)
-- =====================================================================
-- SELECT COUNT(1) AS SRC_CNT FROM SMS.WO_WORK;
-- SELECT COUNT(1) AS TGT_CNT FROM MIGRATION.LS_WORK;
-- SELECT STATUS, COUNT(1) FROM SMS.WO_WORK GROUP BY STATUS ORDER BY 1;
-- SELECT ASSINGSTATUS, COUNT(1) FROM MIGRATION.LS_WORK GROUP BY ASSINGSTATUS ORDER BY 1;
--
-- Pipeline: CTAS → dump → izgazMGR.dbo.LS_WORK → 530/531 (LS_005_01_CS_APPOINTMENT)
/
