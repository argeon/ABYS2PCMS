-- ============================================================
-- ABYS -> PCMS : LS_FITMENT_FEE staging (MIGRATION semasi)
-- Kaynak: SMS | Hedef: MIGRATION | Oracle 11.2
--
-- UYARI - F_GET_CALCULATE_BBS:
--   Scalar PL/SQL fonksiyonu satir basina cagrilir; PARALLEL
--   CTAS'i fiilen serilestirir ve CS_SUBSCRIBER buyukse yavas
--   olur. Fonksiyon PARALLEL_ENABLE + DETERMINISTIC degilse
--   PARALLEL hint'i zaten devreye girmez.
--   Kaynagini dokup mantigi CASE ile inline edebilirim:
--     SELECT text FROM all_source
--     WHERE owner='SMS' AND name='F_GET_CALCULATE_BBS'
--     ORDER BY line;
--   Simdilik fonksiyon SMS. nitelikli olarak korundu.
--
-- FAN-OUT UYARISI:
--   INNER JOIN CS_INSTALLATION nedeniyle:
--   - Tesisatsiz subscriber'lar DUSER
--   - Coklu tesisatli subscriber'lar COKLANIR
--   Fee tablosu subscriber basina tek satir olmali ise
--   asagidaki ROW_NUMBER'li B versiyonunu kullanin.
-- ============================================================

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_FITMENT_FEE PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

-- ============================================================
-- VERSIYON A: Orijinal mantik (subscriber x installation)
-- ============================================================
CREATE TABLE MIGRATION.LS_FITMENT_FEE
NOLOGGING
PARALLEL 4
AS
SELECT
    s.ID                                    AS LREF,
    s.BUILDING_FLAT_ID                      AS FLATID,
    s.ID                                    AS AGRID,
    s.TOTAL_AREA                            AS SIZE_M2,
    0                                       AS FEE,
    160                                     AS EXCNR,
    SMS.F_GET_CALCULATE_BBS(s.TOTAL_AREA, s.ID) AS BBS,
    s.CREATED_USER_ID                       AS ADDUSER,
    s.CREATED_TIMESTAMP                     AS ADDDATE,
    s.UPDATED_TIMESTAMP                     AS UPDDATE,
    s.UPDATED_USER_ID                       AS UPDUSER,
    1                                       AS ISACTIVE,
    s.TOTAL_AREA                            AS TARGET_SIZE,
    ci.ID                                   AS ABYS_INSTALLATION_ID,
    s.BUILDING_FLAT_ID                      AS ABYS_FLAT_ID
FROM SMS.CS_SUBSCRIBER s
JOIN SMS.CS_INSTALLATION ci
     ON ci.SUBSCRIBER_ID = s.ID
;

/* ============================================================
-- VERSIYON B (alternatif): subscriber basina TEK satir
-- (son installation ID'si alinir; tesisatsizlar yine duser,
--  onlar da gelsin isteniyorsa JOIN -> LEFT JOIN yapin)
-- ============================================================
CREATE TABLE MIGRATION.LS_FITMENT_FEE
NOLOGGING
PARALLEL 4
AS
SELECT
    s.ID                                    AS LREF,
    s.BUILDING_FLAT_ID                      AS FLATID,
    s.ID                                    AS AGRID,
    s.TOTAL_AREA                            AS SIZE_M2,
    0                                       AS FEE,
    160                                     AS EXCNR,
    SMS.F_GET_CALCULATE_BBS(s.TOTAL_AREA, s.ID) AS BBS,
    s.CREATED_USER_ID                       AS ADDUSER,
    s.CREATED_TIMESTAMP                     AS ADDDATE,
    s.UPDATED_TIMESTAMP                     AS UPDDATE,
    s.UPDATED_USER_ID                       AS UPDUSER,
    1                                       AS ISACTIVE,
    s.TOTAL_AREA                            AS TARGET_SIZE,
    ci.ID                                   AS ABYS_INSTALLATION_ID,
    s.BUILDING_FLAT_ID                      AS ABYS_FLAT_ID
FROM SMS.CS_SUBSCRIBER s
JOIN (
    SELECT SUBSCRIBER_ID, ID,
           ROW_NUMBER() OVER (PARTITION BY SUBSCRIBER_ID ORDER BY ID DESC) RN
    FROM SMS.CS_INSTALLATION
) ci ON ci.SUBSCRIBER_ID = s.ID AND ci.RN = 1
;
============================================================ */

-- ============================================================
-- INDEX + FINALIZE
-- ============================================================
CREATE INDEX MIGRATION.IDX_LS_FFEE_AGRID
    ON MIGRATION.LS_FITMENT_FEE (AGRID) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IDX_LS_FFEE_FLATID
    ON MIGRATION.LS_FITMENT_FEE (FLATID) NOLOGGING PARALLEL 4;

CREATE INDEX MIGRATION.IDX_LS_FFEE_INSID
    ON MIGRATION.LS_FITMENT_FEE (ABYS_INSTALLATION_ID) NOLOGGING PARALLEL 4;

ALTER TABLE MIGRATION.LS_FITMENT_FEE NOPARALLEL LOGGING;
ALTER INDEX MIGRATION.IDX_LS_FFEE_AGRID  NOPARALLEL;
ALTER INDEX MIGRATION.IDX_LS_FFEE_FLATID NOPARALLEL;
ALTER INDEX MIGRATION.IDX_LS_FFEE_INSID  NOPARALLEL;

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS('MIGRATION','LS_FITMENT_FEE', cascade => TRUE, degree => 4);
END;
/

-- ============================================================
-- DOGRULAMA
-- ============================================================
SELECT 'CS_SUBSCRIBER'   KAYNAK, COUNT(*) FROM SMS.CS_SUBSCRIBER UNION ALL
SELECT 'LS_FITMENT_FEE'        , COUNT(*) FROM MIGRATION.LS_FITMENT_FEE;

-- Coklama (Versiyon A fan-out olcumu)
SELECT AGRID, COUNT(*) AS ADET
FROM MIGRATION.LS_FITMENT_FEE
GROUP BY AGRID
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;

-- INNER JOIN'in dusurdugu tesisatsiz subscriber sayisi
SELECT COUNT(*) AS TESISATSIZ_SUB
FROM SMS.CS_SUBSCRIBER s
WHERE NOT EXISTS (SELECT 1 FROM SMS.CS_INSTALLATION ci
                  WHERE ci.SUBSCRIBER_ID = s.ID);

-- BBS NULL / anomali kontrolu
SELECT
    SUM(CASE WHEN BBS IS NULL THEN 1 ELSE 0 END) AS BBS_NULL,
    MIN(BBS) MIN_BBS, MAX(BBS) MAX_BBS
FROM MIGRATION.LS_FITMENT_FEE;