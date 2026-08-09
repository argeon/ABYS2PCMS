-- =====================================================================
-- LS_KFACTOR_VALUE  (Oracle staging - CTAS)
-- Kaynak : SMS.ME_FACTOR_VALUE
-- Hedef  : MIGRATION.LS_KFACTOR_VALUE
--          → izgazMGR.dbo.LS_KFACTOR_VALUE
-- Pattern: kaynak kolon isimleri birebir; ABYS_ID / LREF = ID bridge
--
-- Gunluk isil deger + gaz kromatograf verileri (RMS / service box).
-- UK: (ACTION_DATE, SERVICE_BOX_ID, IS_MONTHLY)
--   IS_MONTHLY: 0=gunluk, 1=aylik
--
-- DOP: FORCE PARALLEL 16
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- TERMINAL DUMP: Oracle INDEX / GATHER_TABLE_STATS yok (CTAS zincirinde tuketilmiyor; IX -> izgazMGR/energy).

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 16;
ALTER SESSION FORCE PARALLEL DML PARALLEL 16;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_KFACTOR_VALUE PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_KFACTOR_VALUE
NOLOGGING
PARALLEL 16
AS
SELECT /*+ FULL(fv) PARALLEL(fv 16) */
    fv.ID                                                       AS LREF,
    fv.ID                                                       AS ID,
    fv.ID                                                       AS ABYS_ID,

    fv.ACTION_DATE                                              AS ACTION_DATE,
    fv.SERVICE_BOX_ID                                           AS SERVICE_BOX_ID,
    fv.SERVICE_BOX_ID                                           AS ABYS_SERVICE_BOX_ID,

    fv.HIGHER_HEATING_VALUE                                     AS HIGHER_HEATING_VALUE,
    fv.METAN                                                    AS METAN,
    fv.NITROGEN                                                 AS NITROGEN,
    fv.CARBONDIOXIDE                                            AS CARBONDIOXIDE,
    fv.ETAN                                                     AS ETAN,
    fv.PROPAN                                                   AS PROPAN,
    fv.IBUTAN                                                   AS IBUTAN,
    fv.NBUTAN                                                   AS NBUTAN,
    fv.IPENTAN                                                  AS IPENTAN,
    fv.NPENTAN                                                  AS NPENTAN,
    fv.HEXANE                                                   AS HEXANE,

    fv.SP_GRAVITY                                               AS SP_GRAVITY,
    fv.SP_GRAVITY_CALCULATED                                    AS SP_GRAVITY_CALCULATED,
    fv.HIGHER_HEATING_VALUE_CALC                                AS HIGHER_HEATING_VALUE_CALC,
    fv.DENSITY                                                  AS DENSITY,
    fv.DENSITY_CALCULATED                                       AS DENSITY_CALCULATED,
    fv.ONE_DIVIDE_Z                                             AS ONE_DIVIDE_Z,

    fv.DESCRIPTION                                              AS DESCRIPTION,
    fv.IS_MONTHLY                                               AS IS_MONTHLY,
    fv.FLOW_WEIGHTED_AVG_ENERGY                                 AS FLOW_WEIGHTED_AVG_ENERGY,

    fv.CREATED_USER_ID                                          AS CREATED_USER_ID,
    CAST(SYS_EXTRACT_UTC(fv.CREATED_TIMESTAMP) AS TIMESTAMP)    AS CREATED_TIMESTAMP,
    fv.UPDATED_USER_ID                                          AS UPDATED_USER_ID,
    CAST(SYS_EXTRACT_UTC(fv.UPDATED_TIMESTAMP) AS TIMESTAMP)    AS UPDATED_TIMESTAMP,
    fv.VERSION                                                  AS VERSION

FROM SMS.ME_FACTOR_VALUE fv
;

ALTER TABLE MIGRATION.LS_KFACTOR_VALUE NOPARALLEL LOGGING;


-- =====================================================================
-- Gate (manuel)
-- =====================================================================
-- SELECT COUNT(1) AS SRC_CNT FROM SMS.ME_FACTOR_VALUE;
-- SELECT COUNT(1) AS TGT_CNT FROM MIGRATION.LS_KFACTOR_VALUE;
-- SELECT IS_MONTHLY, COUNT(1)
--   FROM MIGRATION.LS_KFACTOR_VALUE
--  GROUP BY IS_MONTHLY;
--
-- Pipeline: CTAS → dump → izgazMGR.dbo.LS_KFACTOR_VALUE
-- Not: Energy LS_005_KFACTOR farkli/basit tablo; bu staging ME_FACTOR_VALUE mirror.
/
