-- =====================================================================
-- LS_ITEMS  (Oracle staging - CTAS)
-- Kaynak : SMS.CS_METER (+ model/marka/ambar/tesisat/kalibrasyon)
-- Hedef  : MIGRATION.LS_ITEMS  →  izgazMGR.dbo.LS_ITEMS  →  energy.dbo.LS_005_ITEMS (240/241)
-- Oracle 11.2 | sqlplus (GO yok, / var)
--
-- Notlar:
--   METER_ID  = LREF (IDENTITY_INSERT ile hedefe ayni anahtar)
--   PRODDATE  = PRODUCTION_YEAR → 01/01/YYYY
--   LASTENDEX = tesisat son endeks (INDEX_TYPE_ID=1)
--   UPDUSER / UPDDATE staging'de tip olarak yer degismis (240 notu); CTAS ayni semayi korur
-- =====================================================================

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_ITEMS PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_ITEMS
NOLOGGING
PARALLEL 4
AS
SELECT
    m.ID                                                        AS METER_ID,
    CAST(0 AS NUMBER)                                           AS MID,
    mtp.CODE                                                    AS DEFN,
    CAST(NULL AS VARCHAR2(50))                                  AS ACCCODE,
    CAST(NULL AS VARCHAR2(50))                                  AS STOCKCODE,
    ix.LAST_INDEX                                               AS LASTENDEX,
    RTRIM(LTRIM(m.METER_NUMBER))                                AS SNNO_TEXT,
    RTRIM(LTRIM(m.METER_NUMBER))                                AS SNNO_NR,
    wm2.WAREHOUSE_ID                                            AS WAREHOUSE,
    CAST(0 AS NUMBER)                                           AS SUPLID,
    CAST(0 AS NUMBER)                                           AS STATID,
    m.IS_ACTIVE                                                 AS ISACTIVE,
    m.CREATED_TIMESTAMP                                         AS ADDDATE,
    m.CREATED_USER_ID                                           AS ADDUSER,
    m.UPDATED_TIMESTAMP                                         AS UPDUSER,
    m.UPDATED_USER_ID                                           AS UPDDATE,
    mmp.GEAR_NUMBER                                             AS CNT_DIGIT,
    CAST(1 AS NUMBER)                                           AS CNT_DIRECTION,
    CAST(NULL AS DATE)                                          AS INV_DATE,
    CAST(NULL AS VARCHAR2(50))                                  AS INV_NO,
    m.ID                                                        AS OLREF,
    CASE
        WHEN m.PRODUCTION_YEAR IS NULL THEN NULL
        ELSE TO_DATE('01/01/' || TO_CHAR(m.PRODUCTION_YEAR), 'DD/MM/YYYY')
    END                                                         AS PRODDATE,
    cm.CAL_CD                                                   AS CALIBRATIONDATE,
    cm.CAL_CNT                                                  AS CALIBRATIONCOUNT,
    m.CALIBRATION_FIRM_REGISTER_ID                              AS CALIBRATIONFIRM,
    m.DESCRIPTION                                               AS DESCRIPTION,
    CASE
        WHEN COALESCE(m.CORRECTOR_MODULE_ID, 0) > 0 THEN 1
        ELSE 0
    END                                                         AS HAS_CORRECTOR_MODULE,
    mmp.METER_MARK_ID                                           AS MARK_REF,
    mmp.METER_CLASS_ID                                          AS METER_CLASS_REF,
    mmp.METER_DIAMETER_ID                                       AS METER_DIAMETER_REF,
    iip.USED_PRESSURE                                           AS METER_PRESSURE_REF,
    w2.NAME                                                     AS ABYS_WAREHOUSE,
    ii.ID                                                       AS ABYS_INSTALLATION_ID,
    ix.LAST_INDEX                                               AS ABYS_INS_LAST_INDEX,
    ixk.LAST_INDEX                                              AS ABYS_KORR_LAST_INDEX,
    ix.READING_DATE                                             AS ABYS_READING_DATE,
    ixk.READING_DATE                                            AS ABYS_KORR_READING_DATE,
    mmpl.VALUE                                                  AS ABYS_METER_MODEL,
    mmp.METER_TYPE_ID                                           AS ABYS_METER_TYPE_ID,
    mm.VALUE                                                    AS ABYS_MARK,
    mmp.METER_KIND                                              AS ABYS_METER_KIND,
    m.DESCRIPTION                                               AS ABYS_DESCRIPTION,
    mdp.VALUE                                                   AS CAP,
    mcp.VALUE                                                   AS TIP,
    mlp.CODE                                                    AS ABYS_LENGTH,
    mmp.GEAR_NUMBER_DECIMAL                                     AS ABYS_GEAR_DECIMAL
FROM SMS.CS_METER m
JOIN SMS.CS_METER_MODEL_PRM mmp
     ON mmp.ID = m.METER_MODEL_ID
JOIN SMS.CS_METER_MODEL_PRM_LNG mmpl
     ON mmp.ID = mmpl.PRM_ID
    AND mmpl.LANG_ID = 1
JOIN SMS.CS_METER_TYPE_PRM mtp
     ON mtp.ID = mmp.METER_TYPE_ID
JOIN SMS.CS_METER_MARK_PRM mm
     ON mm.ID = mmp.METER_MARK_ID
LEFT JOIN SMS.CS_METER_DIAMETER_PRM mdp
     ON mdp.ID = mmp.METER_DIAMETER_ID
LEFT JOIN SMS.CS_METER_CLASS_PRM_LNG mcp
     ON mcp.PRM_ID = mmp.METER_CLASS_ID
    AND mcp.LANG_ID = 1
LEFT JOIN SMS.CS_METER_LENGTH_PRM mlp
     ON mlp.ID = mmp.METER_LENGTH_ID
LEFT JOIN (
    SELECT
        MAX(CASE WHEN wm.IO = 1 THEN wm.ID END) AS WAREHOUSE_METER,
        wm.METER_ID,
        SUM(wm.IO) AS NET_STOCK
    FROM SMS.CS_WAREHOUSE_METER wm
    GROUP BY wm.METER_ID
) gb2
     ON m.ID = gb2.METER_ID
LEFT JOIN SMS.CS_WAREHOUSE_METER wm2
     ON wm2.ID = gb2.WAREHOUSE_METER
LEFT JOIN SMS.CS_WAREHOUSE w2
     ON wm2.WAREHOUSE_ID = w2.ID
LEFT JOIN (
    SELECT *
    FROM (
        SELECT
            ii.*,
            ROW_NUMBER() OVER (PARTITION BY ii.METER_ID ORDER BY ii.ID DESC) AS RN
        FROM SMS.CS_INSTALLATION ii
    )
    WHERE RN = 1
) ii
     ON ii.METER_ID = m.ID
LEFT JOIN (
    SELECT *
    FROM (
        SELECT
            ix.*,
            ROW_NUMBER() OVER (
                PARTITION BY ix.INSTALLATION_ID
                ORDER BY ix.ID DESC
            ) AS RN
        FROM SMS.CS_INSTALLATION_INDEX ix
        WHERE ix.INDEX_TYPE_ID = 1
          AND ix.IS_ACTIVE = 1
    )
    WHERE RN = 1
) ix
     ON ix.INSTALLATION_ID = ii.ID
LEFT JOIN (
    SELECT *
    FROM (
        SELECT
            ixk.*,
            ROW_NUMBER() OVER (
                PARTITION BY ixk.INSTALLATION_ID
                ORDER BY ixk.ID DESC
            ) AS RN
        FROM SMS.CS_INSTALLATION_INDEX ixk
        WHERE ixk.INDEX_TYPE_ID = 2
          AND ixk.IS_ACTIVE = 1
    )
    WHERE RN = 1
) ixk
     ON ixk.INSTALLATION_ID = ii.ID
LEFT JOIN (
    SELECT USED_PRESSURE, INSTALLATION_ID
    FROM (
        SELECT
            USED_PRESSURE,
            INSTALLATION_ID,
            ROW_NUMBER() OVER (PARTITION BY INSTALLATION_ID ORDER BY ID DESC) AS RN
        FROM SMS.II_PROJECT_INSTALLATION
    )
    WHERE RN = 1
) iip
     ON iip.INSTALLATION_ID = ii.ID
LEFT JOIN (
    SELECT
        wo.METER_ID,
        COUNT(1)                 AS CAL_CNT,
        MAX(wr.COMPLETED_DATE)   AS CAL_CD
    FROM SMS.WO_WORK wo
    JOIN SMS.WO_WORK_RESULT wr
         ON wo.ID = wr.WORK_ID
    WHERE wo.STATUS = 5
      AND wo.CAUSE_ID = 18
      AND wr.CAUSE_RESULT_ID = 79
    GROUP BY wo.METER_ID
) cm
     ON cm.METER_ID = m.ID
;

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_ITEMS');
END;
/

-- =====================================================================
-- Gate (manuel)
-- =====================================================================
-- SELECT COUNT(1) AS SRC_CNT FROM SMS.CS_METER;
-- SELECT COUNT(1) AS TGT_CNT FROM MIGRATION.LS_ITEMS;
-- SELECT ABYS_WAREHOUSE, COUNT(1)
-- FROM MIGRATION.LS_ITEMS
-- WHERE ABYS_INSTALLATION_ID IS NOT NULL
-- GROUP BY ABYS_WAREHOUSE;
--
-- Pipeline: dump → izgazMGR.dbo.LS_ITEMS → 240/241 (LS_005_ITEMS)
/
