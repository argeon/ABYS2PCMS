-- 036_LS_WORK_RESULT_V01.SQL
-- Amac: Is emri sonuc
-- Uretir: LS_WORK_RESULT
-- Gate: yok
-- Sonraki: 037_LS_SPEFEE_ADD_V01.SQL
-- =====================================================================
-- LS_WORK_RESULT  (Oracle staging - CTAS)
-- Kaynak : SMS.WO_WORK_RESULT
-- Hedef  : MIGRATION.LS_WORK_RESULT  →  izgazMGR.dbo.WO_WORK_RESULT
--          (veya LS_WORK_RESULT) → energy.dbo.LS_005_01_WO_WORK_RESULT
--          (540/541)
-- Pattern: kaynak kolon isimleri birebir; ABYS_* bridge dahil
--
-- Pass 1 dump (541 migrate JOIN yapmaz):
--   LREF / ABYS_ID = ID
--   WORK_ID = WO_WORK.ID = LS_005_01_CS_APPOINTMENT.LREF
--   User/prm/meter/shelf ham; +10000 ve wire migrate / proje sonu
--
-- Hedef-only (Pass 4 enrich): C_FIRST_INDEX, M_METER_NUMBER, …
--   burada NULL birakilir.
--
-- DOP: FORCE PARALLEL 56
-- Parent: once LS_WORK / WO_WORK CTAS
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- TERMINAL DUMP: Oracle INDEX / GATHER_TABLE_STATS yok (CTAS zincirinde tuketilmiyor; IX -> izgazMGR/energy).

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_WORK_RESULT PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_WORK_RESULT
NOLOGGING
PARALLEL 56
AS
SELECT /*+ FULL(wr) PARALLEL(wr 56) */
    -- PK / bridge
    wr.ID                                                       AS LREF,
    wr.ID                                                       AS ID,
    wr.ID                                                       AS ABYS_ID,

    wr.WORK_ID                                                  AS WORK_ID,
    wr.WORK_ID                                                  AS ABYS_WORK_ID,

    wr.CAUSE_RESULT_ID                                          AS CAUSE_RESULT_ID,
    wr.CAUSE_RESULT_ID                                          AS ABYS_CAUSE_RESULT_ID,
    wr.CAUSE_RESULT_REASON_ID                                   AS CAUSE_RESULT_REASON_ID,
    wr.CAUSE_RESULT_REASON_ID                                   AS ABYS_CAUSE_RESULT_REASON_ID,

    wr.COMPLETED_DATE                                           AS COMPLETED_DATE,
    wr.ASSIGNEE_USER_ID                                         AS ASSIGNEE_USER_ID,
    wr.ASSIGNEE_USER_ID                                         AS ABYS_ASSIGNEE_USER_ID,
    wr.DESCRIPTION                                              AS DESCRIPTION,

    -- Current meter (C_*)
    wr.C_METER_NUMBER                                           AS C_METER_NUMBER,
    wr.C_METER_MARK_ID                                          AS C_METER_MARK_ID,
    wr.C_METER_MODEL_ID                                         AS C_METER_MODEL_ID,
    wr.C_INDEX                                                  AS C_INDEX,
    wr.C_CORRECTED_INDEX                                        AS C_CORRECTED_INDEX,
    wr.C_PRODUCTION_YEAR                                        AS C_PRODUCTION_YEAR,
    wr.C_COMMUNUCATION_MODULE_ID                                AS C_COMMUNUCATION_MODULE_ID,
    wr.C_CORRECTOR_MODULE_ID                                    AS C_CORRECTOR_MODULE_ID,
    wr.C_CONSUMPTION                                            AS C_CONSUMPTION,
    wr.C_METER_TYPE_ID                                          AS C_METER_TYPE_ID,
    wr.C_METER_ID                                               AS C_METER_ID,
    wr.C_METER_ID                                               AS ABYS_C_METER_ID,
    wr.C_IS_BROKEN                                              AS C_IS_BROKEN,
    wr.C_STAMP_YEAR                                             AS C_STAMP_YEAR,
    wr.C_METER_DIAMETER_ID                                      AS C_METER_DIAMETER_ID,
    wr.C_METER_LINK_DIAMETER_ID                                 AS C_METER_LINK_DIAMETER_ID,
    wr.C_RETROKIT_INDEX                                         AS C_RETROKIT_INDEX,

    -- Mounted meter (M_*)
    wr.M_METER_ID                                               AS M_METER_ID,
    wr.M_METER_ID                                               AS ABYS_M_METER_ID,
    wr.M_INDEX                                                  AS M_INDEX,
    wr.M_CORRECTED_INDEX                                        AS M_CORRECTED_INDEX,
    wr.M_COMMUNUCATION_MODULE_ID                                AS M_COMMUNUCATION_MODULE_ID,
    wr.M_CORRECTOR_MODULE_ID                                    AS M_CORRECTOR_MODULE_ID,
    wr.M_RETROKIT_INDEX                                         AS M_RETROKIT_INDEX,

    -- Info (I_*)
    wr.I_AGREEMENT_NUMBER                                       AS I_AGREEMENT_NUMBER,
    wr.I_CUSTOMER_NAME                                          AS I_CUSTOMER_NAME,
    wr.I_SERVICE_BOX_CODE                                       AS I_SERVICE_BOX_CODE,
    wr.I_DOOR_NUMBER                                            AS I_DOOR_NUMBER,
    wr.I_FLAT_NUMBER                                            AS I_FLAT_NUMBER,
    wr.I_FLOOR_NUMBER                                           AS I_FLOOR_NUMBER,
    wr.I_METER_NUMBER                                           AS I_METER_NUMBER,
    wr.I_MINUTE_NUMBER                                          AS I_MINUTE_NUMBER,
    wr.I_MINUTE_DATE                                            AS I_MINUTE_DATE,

    -- Other / cutting (O_*)
    wr.O_CUTTING_SERIAL_NUMBER                                  AS O_CUTTING_SERIAL_NUMBER,
    wr.O_CUTTING_TYPE_ID                                        AS O_CUTTING_TYPE_ID,
    wr.O_VALVE_ARM_STATUS                                       AS O_VALVE_ARM_STATUS,
    wr.O_IS_METER_INTERFERE                                     AS O_IS_METER_INTERFERE,
    wr.O_HAS_SEAL                                               AS O_HAS_SEAL,

    wr.PROBLEM_DESCRIPTION                                      AS PROBLEM_DESCRIPTION,

    wr.CREATED_USER_ID                                          AS CREATED_USER_ID,
    wr.CREATED_USER_ID                                          AS ABYS_CREATED_USER_ID,
    CAST(SYS_EXTRACT_UTC(wr.CREATED_TIMESTAMP) AS TIMESTAMP)    AS CREATED_TIMESTAMP,
    wr.UPDATED_USER_ID                                          AS UPDATED_USER_ID,
    wr.UPDATED_USER_ID                                          AS ABYS_UPDATED_USER_ID,
    CAST(SYS_EXTRACT_UTC(wr.UPDATED_TIMESTAMP) AS TIMESTAMP)    AS UPDATED_TIMESTAMP,
    wr.VERSION                                                  AS VERSION,

    wr.ASSIGNEE_USER_ID_2                                       AS ASSIGNEE_USER_ID_2,
    wr.ASSIGNEE_USER_ID_2                                       AS ABYS_ASSIGNEE_USER_ID_2,
    wr.LONGITUDE                                                AS LONGITUDE,
    wr.LATITUDE                                                 AS LATITUDE,

    wr.CONTROL_CAUSE_ID                                         AS CONTROL_CAUSE_ID,
    wr.CONTROL_PRM_ID                                           AS CONTROL_PRM_ID,
    wr.CONTROL_DESCRIPTION                                      AS CONTROL_DESCRIPTION,

    wr.IS_PICTURE_SEND_LATER                                    AS IS_PICTURE_SEND_LATER,
    wr.IS_APPROVED                                              AS IS_APPROVED,
    wr.METER_ADDRESS                                            AS METER_ADDRESS,

    wr.WAREHOUSE_SHELF_ID                                       AS WAREHOUSE_SHELF_ID,
    wr.WAREHOUSE_SHELF_ID                                       AS ABYS_WAREHOUSE_SHELF_ID,
    wr.SACK_NUMBER                                              AS SACK_NUMBER,
    wr.REKOR_SEAL_NUMBER                                        AS REKOR_SEAL_NUMBER,

    -- Hedef-only (energy var, kaynak DDL yok) — Pass 4
    CAST(NULL AS NUMBER(15,3))                                  AS C_FIRST_INDEX,
    CAST(NULL AS NUMBER(15,3))                                  AS C_CORRECTOR_FIRST_INDEX,
    CAST(NULL AS NUMBER(15,3))                                  AS C_CORRECTOR_LAST_INDEX,
    CAST(NULL AS VARCHAR2(50 CHAR))                             AS TERMINAL_CODE,
    CAST(NULL AS VARCHAR2(4000 CHAR))                           AS SUBSCRIBER_LOCATION,
    CAST(NULL AS NUMBER(15,3))                                  AS LAST_INDEX,
    CAST(NULL AS VARCHAR2(50 CHAR))                             AS METER_STATUS_CODE,
    CAST(NULL AS NUMBER(1))                                     AS IS_BARCODE_READING,
    CAST(NULL AS VARCHAR2(25 CHAR))                             AS M_METER_NUMBER,
    CAST(NULL AS NUMBER(4))                                     AS M_PRODUCTION_YEAR,
    CAST(NULL AS NUMBER(10))                                    AS M_METER_MARK_ID,
    CAST(NULL AS NUMBER(10))                                    AS M_METER_TYPE_ID

FROM SMS.WO_WORK_RESULT wr
;

ALTER TABLE MIGRATION.LS_WORK_RESULT NOPARALLEL LOGGING;


-- =====================================================================
-- Gate (manuel)
-- =====================================================================
-- SELECT COUNT(1) AS SRC_CNT FROM SMS.WO_WORK_RESULT;
-- SELECT COUNT(1) AS TGT_CNT FROM MIGRATION.LS_WORK_RESULT;
-- SELECT COUNT(1) AS ORPHAN
--   FROM MIGRATION.LS_WORK_RESULT r
--   WHERE NOT EXISTS (SELECT 1 FROM MIGRATION.LS_WORK w WHERE w.LREF = r.WORK_ID);
--
-- Pipeline: CTAS → dump → izgazMGR.dbo.WO_WORK_RESULT → 540/541
-- Not: 541 kaynak adi WO_WORK_RESULT; dump tablosunu o isimle al veya
--      migrate FROM'u LS_WORK_RESULT yap.
/

