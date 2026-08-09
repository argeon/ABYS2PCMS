-- =====================================================================
-- LS_FLAT  (Oracle staging - CTAS)
-- Kaynak : SMS.GIS_BUILDING_FLAT (+ door / subscriber / installation / box)
-- Hedef  : MIGRATION.LS_FLAT  →  izgazMGR.dbo.LS_FLAT
-- Pattern: hedef kolon isimleri birebir; ABYS_* bridge dahil
--
-- Not:
--   Flat x subscriber x installation LEFT JOIN fan-out uretebilir.
--   Energy tarafi ABYS_INSTALLATION_ID IS NOT NULL ile filtreler.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_FLAT PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_FLAT
NOLOGGING
PARALLEL 56
AS
SELECT
    ff.FLAT_NUMBER                                          AS FLATNR,
    CAST(1 AS NUMBER(10))                                   AS FLATDEFN,
    ff.FLOOR_NUMBER                                         AS FLOOR_NUMBER,
    CAST(bd.CODE AS NUMBER(10))                             AS BNA_ID,
    CAST(4102 AS NUMBER(10))                                AS ENT_ID,
    ff.TYPE                                                 AS TYPE,
    ff.ADDRESS_NUMBER                                       AS ADDRESS_NUMBER,
    ff.NATIONAL_CODE                                        AS NATIONAL_CODE,
    ff.BUILDING_DOOR_ID                                     AS BUILDING_DOOR_ID,
    bd.CODE                                                 AS ABYS_BUILDING_DOOR_CODE,
    bd.ID                                                   AS ABYS_BUILDING_DOOR_ID,
    agr.SUBSCRIBER_TYPE_ID                                  AS ABYS_SUBSCRIBER_TYPE_ID,
    i.ID                                                    AS ABYS_INSTALLATION_ID,
    i.STATUS                                                AS ABYS_INSTALLATION_GSTATUS,
    i.FIRST_STARTUP_DATE                                    AS ABYS_STARTUP_DATE_RAW,
    i.INSTALLATION_STATUS_ID                                AS ABYS_INSTALLATION_STATUS_ID,
    i.INSTALLATION_CANCEL_DATE                              AS ABYS_INSTALLATION_CANCELDATE,
    i.SERVICE_BOX_ID                                        AS ABYS_SERVICE_BOX_ID,
    sb.CODE                                                 AS ABYS_SERVICE_BOX_CODE,
    ff.CREATED_TIMESTAMP                                    AS FLAT_CREATED_TIMESTAMP,
    ff.CREATED_USER_ID                                      AS FLAT_CREATED_USER_ID,
    ff.UPDATED_TIMESTAMP                                    AS FLAT_UPDATED_TIMESTAMP,
    ff.UPDATED_USER_ID                                      AS FLAT_UPDATED_USER_ID,
    ff.ID                                                   AS ABYS_FLAT_ID,
    ff.FLAT_NUMBER                                          AS FLAT_NUMBER_RAW
FROM SMS.GIS_BUILDING_FLAT ff
INNER JOIN SMS.GIS_BUILDING_DOOR bd
    ON bd.ID = ff.BUILDING_DOOR_ID
LEFT JOIN SMS.CS_SUBSCRIBER agr
    ON ff.ID = agr.BUILDING_FLAT_ID
LEFT JOIN SMS.CS_INSTALLATION i
    ON agr.ID = i.SUBSCRIBER_ID
LEFT JOIN SMS.GIS_SERVICE_BOX sb
    ON sb.ID = i.SERVICE_BOX_ID
;

ALTER TABLE MIGRATION.LS_FLAT NOPARALLEL LOGGING;

CREATE INDEX MIGRATION.IDX_LS_FLAT_ABYS_FLAT
    ON MIGRATION.LS_FLAT (ABYS_FLAT_ID) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IDX_LS_FLAT_ABYS_INS
    ON MIGRATION.LS_FLAT (ABYS_INSTALLATION_ID) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IDX_LS_FLAT_BNA
    ON MIGRATION.LS_FLAT (BNA_ID) NOLOGGING PARALLEL 4;

ALTER INDEX MIGRATION.IDX_LS_FLAT_ABYS_FLAT NOPARALLEL;
ALTER INDEX MIGRATION.IDX_LS_FLAT_ABYS_INS  NOPARALLEL;
ALTER INDEX MIGRATION.IDX_LS_FLAT_BNA       NOPARALLEL;

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_FLAT', cascade => TRUE, degree => 4);
END;
/

-- dogrulama
SELECT 'GIS_BUILDING_FLAT' KAYNAK, COUNT(*) CNT FROM SMS.GIS_BUILDING_FLAT
UNION ALL
SELECT 'LS_FLAT', COUNT(*) FROM MIGRATION.LS_FLAT
UNION ALL
SELECT 'LS_FLAT_WITH_INS', COUNT(*) FROM MIGRATION.LS_FLAT WHERE ABYS_INSTALLATION_ID IS NOT NULL;
