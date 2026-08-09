-- =====================================================================
-- LS_FITMENT_FEE  (Oracle staging - CTAS)
-- Kaynak : SMS.CS_SUBSCRIBER + CS_INSTALLATION
-- Hedef  : MIGRATION.LS_FITMENT_FEE  →  izgazMGR.dbo.LS_FITMENT_FEE
--          → energy.dbo.LS_005_01_AGR_FITMENTFEE_TR
-- Pattern: hedef kolon isimleri birebir; ABYS_* bridge dahil
--
-- UYARI - F_GET_CALCULATE_BBS:
--   Scalar PL/SQL satir basina cagrilir; PARALLEL CTAS fiilen
--   serilesebilir. Fonksiyon SMS. nitelikli tutuldu.
--
-- FAN-OUT:
--   INNER JOIN CS_INSTALLATION → tesisatsizlar duser,
--   coklu tesisatli subscriber'lar coklanir.
--   Tek satir istenirse asagidaki Versiyon B'yi acin.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_FITMENT_FEE PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

-- Versiyon A: subscriber x installation (orijinal)
CREATE TABLE MIGRATION.LS_FITMENT_FEE
NOLOGGING
PARALLEL 56
AS
SELECT
    s.ID                                                    AS LREF,
    s.BUILDING_FLAT_ID                                      AS FLATID,
    s.ID                                                    AS AGRID,
    s.TOTAL_AREA                                            AS SIZE_M2,
    CAST(0 AS NUMBER(10))                                   AS FEE,
    CAST(160 AS NUMBER(10))                                 AS EXCNR,
    SMS.F_GET_CALCULATE_BBS(s.TOTAL_AREA, s.ID)             AS BBS,
    s.CREATED_USER_ID                                       AS ADDUSER,
    s.CREATED_TIMESTAMP                                     AS ADDDATE,
    s.UPDATED_TIMESTAMP                                     AS UPDDATE,
    s.UPDATED_USER_ID                                       AS UPDUSER,
    CAST(1 AS NUMBER(1))                                    AS ISACTIVE,
    s.TOTAL_AREA                                            AS TARGET_SIZE,
    ci.ID                                                   AS ABYS_INSTALLATION_ID,
    s.BUILDING_FLAT_ID                                      AS ABYS_FLAT_ID
FROM SMS.CS_SUBSCRIBER s
JOIN SMS.CS_INSTALLATION ci
    ON ci.SUBSCRIBER_ID = s.ID
;

/* ============================================================
-- Versiyon B (alternatif): subscriber basina TEK satir
CREATE TABLE MIGRATION.LS_FITMENT_FEE
NOLOGGING
PARALLEL 56
AS
SELECT
    s.ID                                                    AS LREF,
    s.BUILDING_FLAT_ID                                      AS FLATID,
    s.ID                                                    AS AGRID,
    s.TOTAL_AREA                                            AS SIZE_M2,
    CAST(0 AS NUMBER(10))                                   AS FEE,
    CAST(160 AS NUMBER(10))                                 AS EXCNR,
    SMS.F_GET_CALCULATE_BBS(s.TOTAL_AREA, s.ID)             AS BBS,
    s.CREATED_USER_ID                                       AS ADDUSER,
    s.CREATED_TIMESTAMP                                     AS ADDDATE,
    s.UPDATED_TIMESTAMP                                     AS UPDDATE,
    s.UPDATED_USER_ID                                       AS UPDUSER,
    CAST(1 AS NUMBER(1))                                    AS ISACTIVE,
    s.TOTAL_AREA                                            AS TARGET_SIZE,
    ci.ID                                                   AS ABYS_INSTALLATION_ID,
    s.BUILDING_FLAT_ID                                      AS ABYS_FLAT_ID
FROM SMS.CS_SUBSCRIBER s
JOIN (
    SELECT SUBSCRIBER_ID, ID,
           ROW_NUMBER() OVER (PARTITION BY SUBSCRIBER_ID ORDER BY ID DESC) RN
    FROM SMS.CS_INSTALLATION
) ci ON ci.SUBSCRIBER_ID = s.ID AND ci.RN = 1
;
============================================================ */

ALTER TABLE MIGRATION.LS_FITMENT_FEE NOPARALLEL LOGGING;

CREATE INDEX MIGRATION.IDX_LS_FFEE_AGRID
    ON MIGRATION.LS_FITMENT_FEE (AGRID) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IDX_LS_FFEE_FLATID
    ON MIGRATION.LS_FITMENT_FEE (FLATID) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IDX_LS_FFEE_INSID
    ON MIGRATION.LS_FITMENT_FEE (ABYS_INSTALLATION_ID) NOLOGGING PARALLEL 4;

ALTER INDEX MIGRATION.IDX_LS_FFEE_AGRID  NOPARALLEL;
ALTER INDEX MIGRATION.IDX_LS_FFEE_FLATID NOPARALLEL;
ALTER INDEX MIGRATION.IDX_LS_FFEE_INSID  NOPARALLEL;

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_FITMENT_FEE', cascade => TRUE, degree => 4);
END;
/

-- dogrulama
SELECT 'CS_SUBSCRIBER' KAYNAK, COUNT(*) CNT FROM SMS.CS_SUBSCRIBER
UNION ALL
SELECT 'LS_FITMENT_FEE', COUNT(*) FROM MIGRATION.LS_FITMENT_FEE;

SELECT AGRID, COUNT(*) AS ADET
FROM MIGRATION.LS_FITMENT_FEE
GROUP BY AGRID
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;

SELECT COUNT(*) AS TESISATSIZ_SUB
FROM SMS.CS_SUBSCRIBER s
WHERE NOT EXISTS (
    SELECT 1 FROM SMS.CS_INSTALLATION ci WHERE ci.SUBSCRIBER_ID = s.ID
);

SELECT
    SUM(CASE WHEN BBS IS NULL THEN 1 ELSE 0 END) AS BBS_NULL,
    MIN(BBS) MIN_BBS,
    MAX(BBS) MAX_BBS
FROM MIGRATION.LS_FITMENT_FEE;
