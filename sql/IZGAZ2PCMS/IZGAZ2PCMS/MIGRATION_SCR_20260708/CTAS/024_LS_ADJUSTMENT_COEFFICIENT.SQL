-- =====================================================================
-- LS_ADJUSTMENT_COEFFICIENT  (Oracle staging - CTAS)
-- Kaynak : SMS.ME_ADJUSTMENT_COEFFICIENT
-- Hedef  : MIGRATION.LS_ADJUSTMENT_COEFFICIENT
--          → izgazMGR.dbo.LS_ADJUSTMENT_COEFFICIENT
-- Pattern: kaynak kolon isimleri birebir; ABYS_ID / LREF = ID bridge
--
-- Sozluk:
--   TYPE  : 1=PRESSURE, 2=TEMPERATURE
--   MONTH : 1..12
--   DEBTH : 50 | 100  (kaynak yazim; DEPTH degil)
--
-- UK: (TYPE, YEAR, MONTH, DEBTH)
-- DOP: FORCE PARALLEL 8 (kucuk referans tablo)
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- TERMINAL DUMP: Oracle INDEX / GATHER_TABLE_STATS yok (CTAS zincirinde tuketilmiyor; IX -> izgazMGR/energy).

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 8;
ALTER SESSION FORCE PARALLEL DML PARALLEL 8;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_ADJUSTMENT_COEFFICIENT PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_ADJUSTMENT_COEFFICIENT
NOLOGGING
PARALLEL 8
AS
SELECT /*+ FULL(ac) PARALLEL(ac 8) */
    ac.ID                                                       AS LREF,
    ac.ID                                                       AS ID,
    ac.ID                                                       AS ABYS_ID,

    ac."TYPE"                                                   AS TYPE,
    ac."YEAR"                                                   AS YEAR,
    ac."MONTH"                                                  AS MONTH,
    ac.DEBTH                                                    AS DEBTH,
    ac."VALUE"                                                  AS VALUE,

    ac.CREATED_USER_ID                                          AS CREATED_USER_ID,
    CAST(SYS_EXTRACT_UTC(ac.CREATED_TIMESTAMP) AS TIMESTAMP)    AS CREATED_TIMESTAMP,
    ac.UPDATED_USER_ID                                          AS UPDATED_USER_ID,
    CAST(SYS_EXTRACT_UTC(ac.UPDATED_TIMESTAMP) AS TIMESTAMP)    AS UPDATED_TIMESTAMP,
    ac.VERSION                                                  AS VERSION

FROM SMS.ME_ADJUSTMENT_COEFFICIENT ac
;

ALTER TABLE MIGRATION.LS_ADJUSTMENT_COEFFICIENT NOPARALLEL LOGGING;


-- =====================================================================
-- Gate (manuel)
-- =====================================================================
-- SELECT COUNT(1) AS SRC_CNT FROM SMS.ME_ADJUSTMENT_COEFFICIENT;
-- SELECT COUNT(1) AS TGT_CNT FROM MIGRATION.LS_ADJUSTMENT_COEFFICIENT;
-- SELECT TYPE, YEAR, MONTH, DEBTH, VALUE
--   FROM MIGRATION.LS_ADJUSTMENT_COEFFICIENT
--  ORDER BY TYPE, YEAR, MONTH, DEBTH;
--
-- Pipeline: CTAS → dump → izgazMGR.dbo.LS_ADJUSTMENT_COEFFICIENT
/
