-- =====================================================================
-- LS_AGR_SERVQ  (Oracle staging - CTAS)
-- Kaynak : SMS.CS_AGREEMENT / CS_AGREEMENT_SUBSCRIBER + meter / index
-- Hedef  : MIGRATION.LS_AGR_SERVQ  →  izgazMGR.dbo.LS_AGR_SERVQ
--          → energy.dbo.LS_005_01_AGR_SERVEQ_TR
-- Pattern: hedef kolon isimleri birebir
--
-- Dal 1 TP2='KUL'  : agreement (CS_INSTALLATION) bazli
-- Dal 2 TP2='ABN'  : agreement_subscriber bazli
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- TERMINAL DUMP: Oracle INDEX / GATHER_TABLE_STATS yok (CTAS zincirinde tuketilmiyor; IX -> izgazMGR/energy).

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_AGR_SERVQ PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_AGR_SERVQ
NOLOGGING
PARALLEL 56
AS
-- Dal 1: CS_INSTALLATION uzerinden (agreement / KUL)
SELECT
    CASE mtp.ID
        WHEN 16 THEN 109
        WHEN 17 THEN 9
        WHEN 20 THEN 13
        WHEN 21 THEN 105
        WHEN 22 THEN 3
        WHEN 23 THEN 4
        WHEN 18 THEN 10
        WHEN 24 THEN 5
        WHEN 25 THEN 1
        WHEN 26 THEN 6
        WHEN 27 THEN 2
        WHEN 29 THEN 7
        WHEN 30 THEN 8
        WHEN 31 THEN 14
        WHEN 32 THEN 101
        ELSE -99
    END                                                     AS MID,
    CAST(1 AS NUMBER(10))                                   AS TID,
    agr.ID                                                  AS AGRID,
    CAST(0 AS NUMBER(10))                                   AS TYPE_,
    m.METER_NUMBER                                          AS SNO,
    CAST(0 AS NUMBER(10))                                   AS MIDOLD,
    ix.LAST_INDEX                                           AS LASTENDEX,
    mmpl.VALUE                                              AS VALUE,
    mtp.CODE                                                AS CODE,
    m.ID                                                    AS ITEMID,
    iip.USED_PRESSURE                                       AS USED_PRESSURE,
    CASE iip.USED_PRESSURE
        WHEN 21    THEN 34
        WHEN 300   THEN 35
        WHEN 120   THEN 48
        WHEN 1000  THEN 609
        WHEN 4000  THEN 610
        WHEN 500   THEN 618
        WHEN 2000  THEN 637
        WHEN 3000  THEN 638
        WHEN 15000 THEN 639
        WHEN 2200  THEN 641
        WHEN 30000 THEN 642
        WHEN 2500  THEN 645
        WHEN 5000  THEN 666
        WHEN 50    THEN 667
        WHEN 19000 THEN 670
        WHEN 1400  THEN 705
        WHEN 0     THEN 844
        WHEN 6000  THEN 845
        WHEN 100   THEN 846
        WHEN 16000 THEN 847
        WHEN 12000 THEN 920
        ELSE -99
    END                                                     AS CALCPRESSID,
    agr.CREATED_TIMESTAMP                                   AS ADDDATE,
    CAST(1 AS NUMBER(1))                                    AS ISACTIVE,
    CAST('KUL' AS VARCHAR2(3 CHAR))                         AS TP2
FROM SMS.CS_INSTALLATION i
JOIN SMS.CS_AGREEMENT agr
    ON agr.INSTALLATION_ID = i.ID
JOIN SMS.CS_METER m
    ON i.METER_ID = m.ID
JOIN SMS.CS_METER_MODEL_PRM mmp
    ON mmp.ID = m.METER_MODEL_ID
JOIN SMS.CS_METER_MODEL_PRM_LNG mmpl
    ON mmpl.PRM_ID = mmp.ID
   AND mmpl.LANG_ID = 1
JOIN SMS.CS_METER_TYPE_PRM mtp
    ON mtp.ID = mmp.METER_TYPE_ID
LEFT JOIN SMS.CS_INSTALLATION_INDEX ix
    ON ix.INSTALLATION_ID = i.ID
   AND ix.INDEX_TYPE_ID = 1
   AND ix.IS_ACTIVE = 1
LEFT JOIN (
    SELECT USED_PRESSURE, INSTALLATION_ID
    FROM (
        SELECT
            USED_PRESSURE,
            INSTALLATION_ID,
            ROW_NUMBER() OVER (PARTITION BY INSTALLATION_ID ORDER BY ID DESC) AS RN
        FROM SMS.II_PROJECT_INSTALLATION
    ) t
    WHERE RN = 1
) iip
    ON iip.INSTALLATION_ID = i.ID

UNION ALL

-- Dal 2: CS_AGREEMENT_SUBSCRIBER uzerinden (ABN)
SELECT
    CASE mtp.ID
        WHEN 16 THEN 109
        WHEN 17 THEN 9
        WHEN 18 THEN 11
        WHEN 20 THEN 13
        WHEN 21 THEN 105
        WHEN 22 THEN 3
        WHEN 23 THEN 4
        WHEN 24 THEN 5
        WHEN 25 THEN 1
        WHEN 26 THEN 6
        WHEN 27 THEN 2
        WHEN 29 THEN 7
        WHEN 30 THEN 8
        WHEN 31 THEN 14
        WHEN 32 THEN 101
        ELSE -99
    END                                                     AS MID,
    CAST(1 AS NUMBER(10))                                   AS TID,
    asub.ID                                                 AS AGRID,
    CAST(0 AS NUMBER(10))                                   AS TYPE_,
    m.METER_NUMBER                                          AS SNO,
    CAST(0 AS NUMBER(10))                                   AS MIDOLD,
    ix.LAST_INDEX                                           AS LASTENDEX,
    mmpl.VALUE                                              AS VALUE,
    mtp.CODE                                                AS CODE,
    m.ID                                                    AS ITEMID,
    iip.USED_PRESSURE                                       AS USED_PRESSURE,
    CASE iip.USED_PRESSURE
        WHEN 21    THEN 34
        WHEN 300   THEN 35
        WHEN 120   THEN 48
        WHEN 1000  THEN 609
        WHEN 4000  THEN 610
        WHEN 500   THEN 618
        WHEN 2000  THEN 637
        WHEN 3000  THEN 638
        WHEN 15000 THEN 639
        WHEN 2200  THEN 641
        WHEN 30000 THEN 642
        WHEN 2500  THEN 645
        WHEN 5000  THEN 666
        WHEN 50    THEN 667
        WHEN 19000 THEN 670
        WHEN 1400  THEN 705
        WHEN 0     THEN 844
        WHEN 6000  THEN 845
        WHEN 100   THEN 846
        WHEN 16000 THEN 847
        WHEN 12000 THEN 920
        ELSE -99
    END                                                     AS CALCPRESSID,
    asub.CREATED_TIMESTAMP                                  AS ADDDATE,
    CAST(1 AS NUMBER(1))                                    AS ISACTIVE,
    CAST('ABN' AS VARCHAR2(3 CHAR))                         AS TP2
FROM SMS.CS_AGREEMENT_SUBSCRIBER asub
JOIN SMS.CS_SUBSCRIBER sub
    ON sub.ID = asub.SUBSCRIBER_ID
JOIN SMS.CS_INSTALLATION i
    ON i.SUBSCRIBER_ID = sub.ID
JOIN SMS.CS_AGREEMENT agr
    ON agr.INSTALLATION_ID = i.ID
JOIN SMS.CS_METER m
    ON i.METER_ID = m.ID
JOIN SMS.CS_METER_MODEL_PRM mmp
    ON mmp.ID = m.METER_MODEL_ID
JOIN SMS.CS_METER_MODEL_PRM_LNG mmpl
    ON mmpl.PRM_ID = mmp.ID
   AND mmpl.LANG_ID = 1
JOIN SMS.CS_METER_TYPE_PRM mtp
    ON mtp.ID = mmp.METER_TYPE_ID
LEFT JOIN SMS.CS_INSTALLATION_INDEX ix
    ON ix.INSTALLATION_ID = i.ID
   AND ix.INDEX_TYPE_ID = 1
   AND ix.IS_ACTIVE = 1
LEFT JOIN (
    SELECT USED_PRESSURE, INSTALLATION_ID
    FROM (
        SELECT
            USED_PRESSURE,
            INSTALLATION_ID,
            ROW_NUMBER() OVER (PARTITION BY INSTALLATION_ID ORDER BY ID DESC) AS RN
        FROM SMS.II_PROJECT_INSTALLATION
    ) t
    WHERE RN = 1
) iip
    ON iip.INSTALLATION_ID = i.ID
;

ALTER TABLE MIGRATION.LS_AGR_SERVQ NOPARALLEL LOGGING;


-- dogrulama
SELECT 'LS_AGR_SERVQ' KAYNAK, COUNT(*) CNT FROM MIGRATION.LS_AGR_SERVQ
UNION ALL
SELECT 'TP2_' || TP2, COUNT(*) FROM MIGRATION.LS_AGR_SERVQ GROUP BY TP2
UNION ALL
SELECT 'MID_UNMAPPED', COUNT(*) FROM MIGRATION.LS_AGR_SERVQ WHERE MID = -99
UNION ALL
SELECT 'CALCPRESS_UNMAPPED', COUNT(*) FROM MIGRATION.LS_AGR_SERVQ WHERE CALCPRESSID = -99;
