-- 039_LS_PROJECTLINE_V01.SQL
-- Amac: Proje satirlari (MIGRATION)
-- Uretir: LS_PROJECTLINE
-- Gate: yok
-- Sonraki: 100_MIG_ACCRUE_TYPE_MAP_V01.SQL
-- =====================================================================
-- LS_PROJECTLINE  (Oracle staging - CTAS)
-- Kaynak : SMS.II_PROJECT + BUILDING (+ INSTALLATION / daire)
-- Hedef  : MIGRATION.LS_PROJECTLINE → izgazMGR.dbo.LS_PROJECTLINE
--          → energy.dbo.LS_005_01_PROJECTLINE (594/595)
-- Onkosul: MIGRATION.LS_PROJECT (oracleCTAS/LS_PROJECT.sql)
-- Lokasyon: oracleCTAS/ (master; oracleCTAS3007 degil)
--
-- Pattern:
--   KOLON (HAS_COLON / HAS_IND_COLON)  ∪  DAIRE (PROJECT_INSTALLATION)
--   LREF = ROW_NUMBER (SEQUENCE yok)
--   PROJECTID = LS_PROJECT.LREF (ABYS_PROJECT_ID basina tek satir)
--   Ek / bridge kolonlar ABYS_* (STG dahil)
--
-- Oracle:
--   UNION ALL kolon tipleri her dalda CAST ile sabit (ORA-01790)
--   WORKERID = SUBSTR(TO_CHAR(...),1,10) — CAST VARCHAR2(10) ORA-12899 riski
--   BNA_ID = sayisal CODE; non-numeric → 0 (ORA-01722 yok)
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
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_PROJECTLINE PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE MIGRATION.LS_PROJECTLINE
NOLOGGING
PARALLEL 56
AS
SELECT
    ROW_NUMBER() OVER (
        ORDER BY u.ABYS_LINE_KIND, u.ORACLE_LINE_ID, u.ORACLE_PROJECT_ID
    )                                                           AS LREF,

    u.PROJECTID,
    u.BNA_ID,
    u.ENT_ID,
    u.FLATID,
    u.AGRID,
    u.ISACTIVE,
    u.STATID,
    u.PROJECTUSER,
    u.FLOWRATE,
    u.REGMODEL,
    u.REGSNO,
    u.ACPT_APP_DATE,
    u.APPSDATE,
    u.APPEDATE,
    u.APPCENG,
    u.PARID,
    u.REVISION_TYPE,
    u.DESCRIPTION_,
    u.FRMID2,
    u.ENGID2,
    u.WORKERID2,
    u.FRMID,
    u.ENGID,
    u.WORKERID,
    u.REASON,
    u.REFID,
    u.REFUSEISACTIVE,
    u.COMPLETIONID,
    u.UPDUSER,
    u.UPDDATE,
    u.ADDUSER,
    u.ADDDATE,
    u.TLTOTAL,
    u.ISGASON,
    u.FMETHOD,
    u.CONFIRMDATE,
    u.REG_CALCPRESS,
    u.XTYPE,
    u.OLOC_ID,
    u.PROJ_ACPT_DATE,
    u.PROJ_ENTER_DATE,
    u.CONFIRMDATE_REAL,
    u.INSURANCENO,
    u.INSURANCE_EDATE,
    u.INSURANCE_SDATE,
    u.AREA,
    u.FLAT_NUMBER,
    u.INSURANCE_FIRM_ID,
    u.PROJECT_TYPE_ID,
    u.SAP_TUKETIM_NOKTASI,
    u.SAP_PROJECT_NUMBER,
    u.SAP_TESISAT_NO,

    u.ORACLE_PROJECT_ID,
    u.ORACLE_LINE_ID,

    -- ABYS bridge / STG
    u.ABYS_LINE_KIND,
    u.ABYS_PROJECT_ID,
    u.ABYS_PROJECT_BUILDING_ID,
    u.ABYS_PROJECT_INSTALLATION_ID,
    u.ABYS_INSTALLATION_ID,
    u.ABYS_STG_TRC_ENG_ID,
    u.ABYS_STG_CTRL_ENG_ID,
    u.ABYS_STG_OLD_PROJECT_STATUS,
    u.ABYS_STG_TESISAT_NO,
    u.ABYS_STG_PROJE_SATIR,
    u.ABYS_STG_SERVIS_KUTU_NO,
    u.ABYS_STG_WORKERID2,
    u.ABYS_STG_PI_TYPE_SET

FROM (
    /* ============================================================
       Dal 1 — KOLON (proje tipi HAS_COLON / HAS_IND_COLON)
       grain : II_PROJECT_BUILDING
       ============================================================ */
    SELECT /*+ PARALLEL(56) */
        CAST(1 AS NUMBER(1))                                    AS ABYS_LINE_KIND,
        CAST(mp.LREF AS NUMBER(19))                             AS PROJECTID,
        CAST(
            NVL(
                TO_NUMBER(REGEXP_SUBSTR(TRIM(TO_CHAR(bna.CODE)), '^[0-9]+$')),
                0
            ) AS NUMBER(10)
        )                                                       AS BNA_ID,
        CAST(4102 AS NUMBER(10))                                AS ENT_ID,
        CAST(NULL AS NUMBER(19))                                AS FLATID,
        CAST(NULL AS NUMBER(19))                                AS AGRID,

        CASE
            WHEN p.CANCEL_DATE IS NULL
             AND p.PROJECT_STATUS <> 0
             AND NOT EXISTS (
                 SELECT 1 FROM SMS.II_PROJECT r WHERE r.PARENT_ID = p.ID
             )
            THEN CAST(1 AS NUMBER(1))
            ELSE CAST(0 AS NUMBER(1))
        END                                                     AS ISACTIVE,

        CAST(
            CASE
                WHEN p.PROJECT_STATUS = 0 THEN 5
                WHEN p.PROJECT_STATUS = 50 THEN 1
                WHEN p.PROJECT_STATUS IN (100, 200, 300, 400, 500, 800) THEN 2
                WHEN p.PROJECT_STATUS IN (888, 999) THEN 4
                ELSE 2
            END AS NUMBER(10)
        )                                                       AS STATID,

        CAST(p.CREATED_USER_ID AS NUMBER(19))                   AS PROJECTUSER,
        CAST(p.COLON_DEBIT AS BINARY_DOUBLE)                    AS FLOWRATE,
        CAST(p.REGULATOR_TYPE_ID AS NUMBER(19))                 AS REGMODEL,

        CAST(NULL AS VARCHAR2(50 CHAR))                         AS REGSNO,
        CAST(NULL AS DATE)                                      AS ACPT_APP_DATE,
        CAST(NULL AS DATE)                                      AS APPSDATE,
        CAST(NULL AS DATE)                                      AS APPEDATE,
        CAST(NULL AS NUMBER(10))                                AS APPCENG,
        CAST(NULL AS NUMBER(10))                                AS PARID,
        CAST(NULL AS NUMBER(10))                                AS REVISION_TYPE,

        CAST(SUBSTR(p.DESCRIPTION, 1, 1500) AS VARCHAR2(1500 CHAR)) AS DESCRIPTION_,

        CAST(fc.FIRM_ID AS NUMBER(19))                          AS FRMID2,
        CAST(rr_eng.RELATIONAL_REGISTER_ID AS NUMBER(19))       AS ENGID2,
        CAST(rr_col.RELATIONAL_REGISTER_ID AS NUMBER(19))       AS WORKERID2,

        CAST(fc.FIRM_ID AS NUMBER(19))                          AS FRMID,
        CAST(rr_eng.RELATIONAL_REGISTER_ID AS NUMBER(19))       AS ENGID,
        CAST(SUBSTR(TO_CHAR(rr_col.RELATIONAL_REGISTER_ID), 1, 10) AS VARCHAR2(10 CHAR)) AS WORKERID,

        CAST(SUBSTR(p.CANCEL_DESCRIPTION, 1, 1500) AS VARCHAR2(1500 CHAR)) AS REASON,

        CAST(NULL AS NUMBER(10))                                AS REFID,
        CAST(NULL AS NUMBER(1))                                 AS REFUSEISACTIVE,
        CAST(NULL AS NUMBER(10))                                AS COMPLETIONID,

        CAST(p.UPDATED_USER_ID AS NUMBER(19))                   AS UPDUSER,
        CAST(p.UPDATED_TIMESTAMP AS DATE)                       AS UPDDATE,
        CAST(p.CREATED_USER_ID AS NUMBER(19))                   AS ADDUSER,
        CAST(p.CREATED_TIMESTAMP AS DATE)                       AS ADDDATE,

        CAST(NULL AS BINARY_DOUBLE)                             AS TLTOTAL,
        CAST(NULL AS NUMBER(1))                                 AS ISGASON,
        CAST(NULL AS NUMBER(10))                                AS FMETHOD,

        CAST(p.APPROVAL_DATE AS DATE)                           AS CONFIRMDATE,
        CAST(p.COLON_PRESSURE AS NUMBER(10))                    AS REG_CALCPRESS,
        CAST(NULL AS NUMBER(10))                                AS XTYPE,
        CAST(NULL AS NUMBER(10))                                AS OLOC_ID,
        CAST(NULL AS DATE)                                      AS PROJ_ACPT_DATE,
        CAST(p.ARRIVAL_DATE AS DATE)                            AS PROJ_ENTER_DATE,
        CAST(p.APPROVAL_DATE AS DATE)                           AS CONFIRMDATE_REAL,

        CAST(SUBSTR(TRIM(polp.POLICY_NUMBER), 1, 50) AS VARCHAR2(50 CHAR)) AS INSURANCENO,
        CAST(polp.POLICY_END_DATE AS DATE)                      AS INSURANCE_EDATE,
        CAST(polp.POLICY_START_DATE AS DATE)                    AS INSURANCE_SDATE,

        CAST(NULL AS NUMBER(12,2))                              AS AREA,
        CAST(NULL AS VARCHAR2(50 CHAR))                         AS FLAT_NUMBER,
        CAST(polp.INSURANCE_COMPANY_ID AS NUMBER(19))           AS INSURANCE_FIRM_ID,

        CAST(
            CASE
                WHEN p.PROJECT_TYPE_ID = 15 AND s.PI_TYPE_SET IN ('2', '1,2') THEN 5
                WHEN p.PROJECT_TYPE_ID = 8  AND s.PI_TYPE_SET = '2'          THEN 69
                WHEN p.PROJECT_TYPE_ID = 8  AND s.PI_TYPE_SET = '1,2'        THEN 68
                WHEN p.PROJECT_TYPE_ID = 17
                 AND INSTR(',' || s.PI_TYPE_SET || ',', ',4,') > 0           THEN 67
                WHEN p.PROJECT_TYPE_ID = 18 AND s.PI_TYPE_SET = '4'          THEN 70
                WHEN p.PROJECT_TYPE_ID = 20 AND s.PI_TYPE_SET = '2,4'        THEN 66
                WHEN p.PROJECT_TYPE_ID = 20 AND s.PI_TYPE_SET = '1,4'        THEN 65
                ELSE p.PROJECT_TYPE_ID
            END AS NUMBER(10)
        )                                                       AS PROJECT_TYPE_ID,

        CAST(NULL AS NUMBER(10))                                AS SAP_TUKETIM_NOKTASI,
        CAST(NULL AS VARCHAR2(100 CHAR))                        AS SAP_PROJECT_NUMBER,
        CAST(NULL AS NUMBER(10))                                AS SAP_TESISAT_NO,

        CAST(p.ID AS NUMBER(19))                                AS ORACLE_PROJECT_ID,
        CAST(pb.ID AS NUMBER(19))                               AS ORACLE_LINE_ID,

        CAST(p.ID AS NUMBER(19))                                AS ABYS_PROJECT_ID,
        CAST(pb.ID AS NUMBER(19))                               AS ABYS_PROJECT_BUILDING_ID,
        CAST(NULL AS NUMBER(19))                                AS ABYS_PROJECT_INSTALLATION_ID,
        CAST(NULL AS NUMBER(19))                                AS ABYS_INSTALLATION_ID,
        CAST(rr_trc.RELATIONAL_REGISTER_ID AS NUMBER(19))       AS ABYS_STG_TRC_ENG_ID,
        CAST(rr_ctrl.RELATIONAL_REGISTER_ID AS NUMBER(19))      AS ABYS_STG_CTRL_ENG_ID,
        CAST(p.PROJECT_STATUS AS NUMBER(5))                     AS ABYS_STG_OLD_PROJECT_STATUS,
        CAST(NULL AS NUMBER(22,0))                              AS ABYS_STG_TESISAT_NO,
        CAST(p.PROJECT_NUMBER AS NUMBER(19))                    AS ABYS_STG_PROJE_SATIR,
        CAST(p.SERVICE_BOX_ID AS NUMBER(19))                    AS ABYS_STG_SERVIS_KUTU_NO,
        CAST(SUBSTR(TO_CHAR(rr_col.RELATIONAL_REGISTER_ID), 1, 40) AS VARCHAR2(40 CHAR)) AS ABYS_STG_WORKERID2,
        CAST(SUBSTR(s.PI_TYPE_SET, 1, 4000) AS VARCHAR2(4000 CHAR)) AS ABYS_STG_PI_TYPE_SET

    FROM SMS.II_PROJECT p
    INNER JOIN (
        SELECT
            x.LREF,
            x.ABYS_PROJECT_ID
        FROM (
            SELECT
                lp.LREF,
                lp.ABYS_PROJECT_ID,
                ROW_NUMBER() OVER (
                    PARTITION BY lp.ABYS_PROJECT_ID
                    ORDER BY lp.LREF
                ) AS RN
            FROM MIGRATION.LS_PROJECT lp
        ) x
        WHERE x.RN = 1
    ) mp
        ON mp.ABYS_PROJECT_ID = p.ID
    INNER JOIN SMS.II_PROJECT_TYPE_PRM t
        ON t.ID = p.PROJECT_TYPE_ID
       AND (t.HAS_COLON = 1 OR t.HAS_IND_COLON = 1)
    INNER JOIN SMS.II_PROJECT_BUILDING pb
        ON pb.PROJECT_ID = p.ID
    LEFT JOIN (
        SELECT
            ipb.ID AS PROJECT_BUILDING_ID,
            bd.CODE
        FROM SMS.II_PROJECT_BUILDING ipb
        INNER JOIN SMS.GIS_BUILDING_DOOR bd
            ON bd.ID = ipb.BUILDING_DOOR_ID
    ) bna
        ON bna.PROJECT_BUILDING_ID = pb.ID
    LEFT JOIN (
        SELECT
            project_id,
            LISTAGG(TO_CHAR(type_no), ',') WITHIN GROUP (ORDER BY type_no) AS PI_TYPE_SET
        FROM (
            SELECT DISTINCT
                pb2.PROJECT_ID AS project_id,
                pi2.TYPE       AS type_no
            FROM SMS.II_PROJECT_BUILDING pb2
            INNER JOIN SMS.II_PROJECT_INSTALLATION pi2
                ON pi2.PROJECT_BUILDING_ID = pb2.ID
            WHERE pi2.TYPE IS NOT NULL
        )
        GROUP BY project_id
    ) s
        ON s.project_id = p.ID
    LEFT JOIN SMS.II_FIRM_CERTIFICATE fc
        ON fc.ID = p.FIRM_CERTIFICATE_ID
    LEFT JOIN SMS.CS_REGISTER_RELATION rr_eng
        ON rr_eng.ID = p.ENGINEER_REG_REL_ID
    LEFT JOIN SMS.CS_REGISTER_RELATION rr_col
        ON rr_col.ID = p.COLON_MASTER_REG_REL_ID
    LEFT JOIN SMS.CS_REGISTER_RELATION rr_trc
        ON rr_trc.ID = p.TRACING_ENGINEER_REG_REL_ID
    LEFT JOIN SMS.CS_REGISTER_RELATION rr_ctrl
        ON rr_ctrl.ID = p.CONTROL_ENGINEER_REG_REL_ID
    LEFT JOIN (
        SELECT
            project_id,
            policy_number,
            policy_start_date,
            policy_end_date,
            insurance_company_id
        FROM (
            SELECT
                ip.PROJECT_ID           AS project_id,
                ip.POLICY_NUMBER        AS policy_number,
                ip.POLICY_START_DATE    AS policy_start_date,
                ip.POLICY_END_DATE      AS policy_end_date,
                ip.INSURANCE_COMPANY_ID AS insurance_company_id,
                ROW_NUMBER() OVER (
                    PARTITION BY ip.PROJECT_ID
                    ORDER BY ip.POLICY_END_DATE DESC, ip.ID DESC
                ) AS RN
            FROM SMS.II_PROJECT_INSURANCE_POLICY ip
            WHERE ip.PROJECT_INSTALLATION_ID IS NULL
        )
        WHERE RN = 1
    ) polp
        ON polp.project_id = p.ID

    UNION ALL

    /* ============================================================
       Dal 2 — DAIRE (PROJECT_INSTALLATION)
       grain : II_PROJECT_INSTALLATION
       ============================================================ */
    SELECT /*+ PARALLEL(56) */
        CAST(2 AS NUMBER(1))                                    AS ABYS_LINE_KIND,
        CAST(mp.LREF AS NUMBER(19))                             AS PROJECTID,
        CAST(
            NVL(
                TO_NUMBER(REGEXP_SUBSTR(TRIM(TO_CHAR(bna.CODE)), '^[0-9]+$')),
                0
            ) AS NUMBER(10)
        )                                                       AS BNA_ID,
        CAST(4102 AS NUMBER(10))                                AS ENT_ID,
        CAST(cs.BUILDING_FLAT_ID AS NUMBER(19))                 AS FLATID,
        CAST(agr.ID AS NUMBER(19))                              AS AGRID,

        CASE
            WHEN p.CANCEL_DATE IS NULL
             AND p.PROJECT_STATUS <> 0
             AND NOT EXISTS (
                 SELECT 1 FROM SMS.II_PROJECT r WHERE r.PARENT_ID = p.ID
             )
            THEN CAST(1 AS NUMBER(1))
            ELSE CAST(0 AS NUMBER(1))
        END                                                     AS ISACTIVE,

        CAST(
            CASE
                WHEN p.PROJECT_STATUS = 0 THEN 5
                WHEN p.PROJECT_STATUS = 50 THEN 1
                WHEN p.PROJECT_STATUS IN (100, 200, 300, 400, 500, 800) THEN 2
                WHEN p.PROJECT_STATUS IN (888, 999) THEN
                    CASE
                        WHEN agr.STATUS IN (1, 3) AND agr.STARTUP_DATE IS NOT NULL THEN 9
                        WHEN agr.STATUS = 2 AND agr.STARTUP_DATE IS NOT NULL THEN 15
                        WHEN agr.STATUS = 0 AND agr.STARTUP_DATE IS NOT NULL THEN 11
                        ELSE 4
                    END
                ELSE 2
            END AS NUMBER(10)
        )                                                       AS STATID,

        CAST(p.CREATED_USER_ID AS NUMBER(19))                   AS PROJECTUSER,
        CAST(pi.USED_DEBIT AS BINARY_DOUBLE)                    AS FLOWRATE,
        CAST(p.REGULATOR_TYPE_ID AS NUMBER(19))                 AS REGMODEL,

        CAST(NULL AS VARCHAR2(50 CHAR))                         AS REGSNO,
        CAST(NULL AS DATE)                                      AS ACPT_APP_DATE,
        CAST(NULL AS DATE)                                      AS APPSDATE,
        CAST(NULL AS DATE)                                      AS APPEDATE,
        CAST(NULL AS NUMBER(10))                                AS APPCENG,
        CAST(NULL AS NUMBER(10))                                AS PARID,
        CAST(NULL AS NUMBER(10))                                AS REVISION_TYPE,

        CAST(SUBSTR(p.DESCRIPTION, 1, 1500) AS VARCHAR2(1500 CHAR)) AS DESCRIPTION_,

        CAST(fc.FIRM_ID AS NUMBER(19))                          AS FRMID2,
        CAST(rr_eng.RELATIONAL_REGISTER_ID AS NUMBER(19))       AS ENGID2,
        CAST(
            NVL(rr_col.RELATIONAL_REGISTER_ID, rr_mst.RELATIONAL_REGISTER_ID)
            AS NUMBER(19)
        )                                                       AS WORKERID2,

        CAST(fc.FIRM_ID AS NUMBER(19))                          AS FRMID,
        CAST(rr_eng.RELATIONAL_REGISTER_ID AS NUMBER(19))       AS ENGID,
        CAST(SUBSTR(TO_CHAR(
            NVL(rr_col.RELATIONAL_REGISTER_ID, rr_mst.RELATIONAL_REGISTER_ID)
        ), 1, 10) AS VARCHAR2(10 CHAR))                         AS WORKERID,

        CAST(SUBSTR(p.CANCEL_DESCRIPTION, 1, 1500) AS VARCHAR2(1500 CHAR)) AS REASON,

        CAST(NULL AS NUMBER(10))                                AS REFID,
        CAST(NULL AS NUMBER(1))                                 AS REFUSEISACTIVE,
        CAST(NULL AS NUMBER(10))                                AS COMPLETIONID,

        CAST(p.UPDATED_USER_ID AS NUMBER(19))                   AS UPDUSER,
        CAST(pi.UPDATED_TIMESTAMP AS DATE)                      AS UPDDATE,
        CAST(p.CREATED_USER_ID AS NUMBER(19))                   AS ADDUSER,
        CAST(pi.CREATED_TIMESTAMP AS DATE)                      AS ADDDATE,

        CAST(NULL AS BINARY_DOUBLE)                             AS TLTOTAL,

        CASE
            WHEN agr.STATUS IN (1, 3) AND agr.STARTUP_DATE IS NOT NULL
            THEN CAST(1 AS NUMBER(1))
            ELSE CAST(0 AS NUMBER(1))
        END                                                     AS ISGASON,

        CASE
            WHEN pi.TYPE IN (1, 2) THEN CAST(0 AS NUMBER(10))
            WHEN pi.TYPE IN (3, 4) THEN CAST(1 AS NUMBER(10))
            ELSE CAST(NULL AS NUMBER(10))
        END                                                     AS FMETHOD,

        CAST(p.APPROVAL_DATE AS DATE)                           AS CONFIRMDATE,
        CAST(pi.USED_PRESSURE AS NUMBER(10))                    AS REG_CALCPRESS,
        CAST(pi.TYPE AS NUMBER(10))                             AS XTYPE,
        CAST(NULL AS NUMBER(10))                                AS OLOC_ID,
        CAST(NULL AS DATE)                                      AS PROJ_ACPT_DATE,
        CAST(p.ARRIVAL_DATE AS DATE)                            AS PROJ_ENTER_DATE,
        CAST(p.APPROVAL_DATE AS DATE)                           AS CONFIRMDATE_REAL,

        CAST(SUBSTR(
            COALESCE(TRIM(poli.POLICY_NUMBER), TRIM(polp.POLICY_NUMBER)),
            1, 50
        ) AS VARCHAR2(50 CHAR))                                 AS INSURANCENO,
        CAST(COALESCE(poli.POLICY_END_DATE, polp.POLICY_END_DATE) AS DATE) AS INSURANCE_EDATE,
        CAST(COALESCE(poli.POLICY_START_DATE, polp.POLICY_START_DATE) AS DATE) AS INSURANCE_SDATE,

        CAST(pi.USED_AREA AS NUMBER(12,2))                      AS AREA,
        CAST(SUBSTR(pi.FLAT_NUMBER, 1, 50) AS VARCHAR2(50 CHAR)) AS FLAT_NUMBER,
        CAST(
            COALESCE(poli.INSURANCE_COMPANY_ID, polp.INSURANCE_COMPANY_ID)
            AS NUMBER(19)
        )                                                       AS INSURANCE_FIRM_ID,

        CAST(
            CASE
                WHEN p.PROJECT_TYPE_ID = 15 AND s.PI_TYPE_SET IN ('2', '1,2') THEN 5
                WHEN p.PROJECT_TYPE_ID = 8  AND s.PI_TYPE_SET = '2'          THEN 69
                WHEN p.PROJECT_TYPE_ID = 8  AND s.PI_TYPE_SET = '1,2'        THEN 68
                WHEN p.PROJECT_TYPE_ID = 17
                 AND INSTR(',' || s.PI_TYPE_SET || ',', ',4,') > 0           THEN 67
                WHEN p.PROJECT_TYPE_ID = 18 AND s.PI_TYPE_SET = '4'          THEN 70
                WHEN p.PROJECT_TYPE_ID = 20 AND s.PI_TYPE_SET = '2,4'        THEN 66
                WHEN p.PROJECT_TYPE_ID = 20 AND s.PI_TYPE_SET = '1,4'        THEN 65
                ELSE p.PROJECT_TYPE_ID
            END AS NUMBER(10)
        )                                                       AS PROJECT_TYPE_ID,

        CAST(NULL AS NUMBER(10))                                AS SAP_TUKETIM_NOKTASI,
        CAST(NULL AS VARCHAR2(100 CHAR))                        AS SAP_PROJECT_NUMBER,
        CAST(NULL AS NUMBER(10))                                AS SAP_TESISAT_NO,

        CAST(p.ID AS NUMBER(19))                                AS ORACLE_PROJECT_ID,
        CAST(pi.ID AS NUMBER(19))                               AS ORACLE_LINE_ID,

        CAST(p.ID AS NUMBER(19))                                AS ABYS_PROJECT_ID,
        CAST(pb.ID AS NUMBER(19))                               AS ABYS_PROJECT_BUILDING_ID,
        CAST(pi.ID AS NUMBER(19))                               AS ABYS_PROJECT_INSTALLATION_ID,
        CAST(pi.INSTALLATION_ID AS NUMBER(19))                  AS ABYS_INSTALLATION_ID,
        CAST(rr_trc.RELATIONAL_REGISTER_ID AS NUMBER(19))       AS ABYS_STG_TRC_ENG_ID,
        CAST(rr_ctrl.RELATIONAL_REGISTER_ID AS NUMBER(19))      AS ABYS_STG_CTRL_ENG_ID,
        CAST(p.PROJECT_STATUS AS NUMBER(5))                     AS ABYS_STG_OLD_PROJECT_STATUS,
        CAST(pi.INSTALLATION_ID AS NUMBER(22,0))                AS ABYS_STG_TESISAT_NO,
        CAST(p.PROJECT_NUMBER AS NUMBER(19))                    AS ABYS_STG_PROJE_SATIR,
        CAST(p.SERVICE_BOX_ID AS NUMBER(19))                    AS ABYS_STG_SERVIS_KUTU_NO,
        CAST(SUBSTR(TO_CHAR(
            NVL(rr_col.RELATIONAL_REGISTER_ID, rr_mst.RELATIONAL_REGISTER_ID)
        ), 1, 40) AS VARCHAR2(40 CHAR))                         AS ABYS_STG_WORKERID2,
        CAST(SUBSTR(s.PI_TYPE_SET, 1, 4000) AS VARCHAR2(4000 CHAR)) AS ABYS_STG_PI_TYPE_SET

    FROM SMS.II_PROJECT p
    INNER JOIN (
        SELECT
            x.LREF,
            x.ABYS_PROJECT_ID
        FROM (
            SELECT
                lp.LREF,
                lp.ABYS_PROJECT_ID,
                ROW_NUMBER() OVER (
                    PARTITION BY lp.ABYS_PROJECT_ID
                    ORDER BY lp.LREF
                ) AS RN
            FROM MIGRATION.LS_PROJECT lp
        ) x
        WHERE x.RN = 1
    ) mp
        ON mp.ABYS_PROJECT_ID = p.ID
    INNER JOIN SMS.II_PROJECT_BUILDING pb
        ON pb.PROJECT_ID = p.ID
    INNER JOIN SMS.II_PROJECT_INSTALLATION pi
        ON pi.PROJECT_BUILDING_ID = pb.ID
    LEFT JOIN (
        SELECT
            ipb.ID AS PROJECT_BUILDING_ID,
            bd.CODE
        FROM SMS.II_PROJECT_BUILDING ipb
        INNER JOIN SMS.GIS_BUILDING_DOOR bd
            ON bd.ID = ipb.BUILDING_DOOR_ID
    ) bna
        ON bna.PROJECT_BUILDING_ID = pb.ID
    LEFT JOIN SMS.CS_INSTALLATION ci
        ON ci.ID = pi.INSTALLATION_ID
    LEFT JOIN SMS.CS_SUBSCRIBER cs
        ON cs.ID = ci.SUBSCRIBER_ID
    LEFT JOIN SMS.II_FIRM_CERTIFICATE fc
        ON fc.ID = p.FIRM_CERTIFICATE_ID
    LEFT JOIN (
        SELECT
            project_id,
            LISTAGG(TO_CHAR(type_no), ',') WITHIN GROUP (ORDER BY type_no) AS PI_TYPE_SET
        FROM (
            SELECT DISTINCT
                pb2.PROJECT_ID AS project_id,
                pi2.TYPE       AS type_no
            FROM SMS.II_PROJECT_BUILDING pb2
            INNER JOIN SMS.II_PROJECT_INSTALLATION pi2
                ON pi2.PROJECT_BUILDING_ID = pb2.ID
            WHERE pi2.TYPE IS NOT NULL
        )
        GROUP BY project_id
    ) s
        ON s.project_id = p.ID
    LEFT JOIN SMS.CS_REGISTER_RELATION rr_eng
        ON rr_eng.ID = p.ENGINEER_REG_REL_ID
    LEFT JOIN SMS.CS_REGISTER_RELATION rr_col
        ON rr_col.ID = p.COLON_MASTER_REG_REL_ID
    LEFT JOIN SMS.CS_REGISTER_RELATION rr_trc
        ON rr_trc.ID = p.TRACING_ENGINEER_REG_REL_ID
    LEFT JOIN SMS.CS_REGISTER_RELATION rr_mst
        ON rr_mst.ID = pi.MASTER_REGISTER_RELATION_ID
    LEFT JOIN SMS.CS_REGISTER_RELATION rr_ctrl
        ON rr_ctrl.ID = p.CONTROL_ENGINEER_REG_REL_ID
    LEFT JOIN (
        SELECT
            id,
            installation_id,
            status,
            startup_date
        FROM (
            SELECT
                a.ID               AS id,
                a.INSTALLATION_ID  AS installation_id,
                a.STATUS           AS status,
                a.STARTUP_DATE     AS startup_date,
                ROW_NUMBER() OVER (
                    PARTITION BY a.INSTALLATION_ID
                    ORDER BY
                        CASE WHEN a.STATUS IN (1, 3) THEN 0 ELSE 1 END,
                        a.AGREEMENT_DATE DESC,
                        a.ID DESC
                ) AS RN
            FROM SMS.CS_AGREEMENT a
        )
        WHERE RN = 1
    ) agr
        ON agr.installation_id = pi.INSTALLATION_ID
    LEFT JOIN (
        SELECT
            project_installation_id,
            policy_number,
            policy_start_date,
            policy_end_date,
            insurance_company_id
        FROM (
            SELECT
                ip.PROJECT_INSTALLATION_ID AS project_installation_id,
                ip.POLICY_NUMBER           AS policy_number,
                ip.POLICY_START_DATE       AS policy_start_date,
                ip.POLICY_END_DATE         AS policy_end_date,
                ip.INSURANCE_COMPANY_ID    AS insurance_company_id,
                ROW_NUMBER() OVER (
                    PARTITION BY ip.PROJECT_INSTALLATION_ID
                    ORDER BY ip.POLICY_END_DATE DESC, ip.ID DESC
                ) AS RN
            FROM SMS.II_PROJECT_INSURANCE_POLICY ip
            WHERE ip.PROJECT_INSTALLATION_ID IS NOT NULL
        )
        WHERE RN = 1
    ) poli
        ON poli.project_installation_id = pi.ID
    LEFT JOIN (
        SELECT
            project_id,
            policy_number,
            policy_start_date,
            policy_end_date,
            insurance_company_id
        FROM (
            SELECT
                ip.PROJECT_ID           AS project_id,
                ip.POLICY_NUMBER        AS policy_number,
                ip.POLICY_START_DATE    AS policy_start_date,
                ip.POLICY_END_DATE      AS policy_end_date,
                ip.INSURANCE_COMPANY_ID AS insurance_company_id,
                ROW_NUMBER() OVER (
                    PARTITION BY ip.PROJECT_ID
                    ORDER BY ip.POLICY_END_DATE DESC, ip.ID DESC
                ) AS RN
            FROM SMS.II_PROJECT_INSURANCE_POLICY ip
            WHERE ip.PROJECT_INSTALLATION_ID IS NULL
        )
        WHERE RN = 1
    ) polp
        ON polp.project_id = p.ID
) u
;

ALTER TABLE MIGRATION.LS_PROJECTLINE NOPARALLEL LOGGING;

CREATE UNIQUE INDEX MIGRATION.UX_LS_PROJECTLINE_LREF
    ON MIGRATION.LS_PROJECTLINE (LREF) NOLOGGING PARALLEL 8;
ALTER INDEX MIGRATION.UX_LS_PROJECTLINE_LREF NOPARALLEL;

CREATE INDEX MIGRATION.IDX_LS_PL_PROJECTID
    ON MIGRATION.LS_PROJECTLINE (PROJECTID) NOLOGGING PARALLEL 8;
ALTER INDEX MIGRATION.IDX_LS_PL_PROJECTID NOPARALLEL;

CREATE INDEX MIGRATION.IDX_LS_PL_ORA_PROJ
    ON MIGRATION.LS_PROJECTLINE (ORACLE_PROJECT_ID) NOLOGGING PARALLEL 8;
ALTER INDEX MIGRATION.IDX_LS_PL_ORA_PROJ NOPARALLEL;

CREATE INDEX MIGRATION.IDX_LS_PL_ORA_LINE
    ON MIGRATION.LS_PROJECTLINE (ORACLE_LINE_ID) NOLOGGING PARALLEL 8;
ALTER INDEX MIGRATION.IDX_LS_PL_ORA_LINE NOPARALLEL;

CREATE INDEX MIGRATION.IDX_LS_PL_KIND
    ON MIGRATION.LS_PROJECTLINE (ABYS_LINE_KIND) NOLOGGING PARALLEL 8;
ALTER INDEX MIGRATION.IDX_LS_PL_KIND NOPARALLEL;

CREATE INDEX MIGRATION.IDX_LS_PL_AGR
    ON MIGRATION.LS_PROJECTLINE (AGRID) NOLOGGING PARALLEL 8;
ALTER INDEX MIGRATION.IDX_LS_PL_AGR NOPARALLEL;

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_PROJECTLINE', degree => 56);
END;
/

-- =====================================================================
-- Gate (manuel)
-- =====================================================================
-- SELECT ABYS_LINE_KIND, COUNT(1) FROM MIGRATION.LS_PROJECTLINE GROUP BY ABYS_LINE_KIND;
-- SELECT COUNT(1) FROM MIGRATION.LS_PROJECTLINE;  -- = kolon + daire
-- SELECT COUNT(1) FROM MIGRATION.LS_PROJECTLINE pl
--  WHERE NOT EXISTS (
--    SELECT 1 FROM MIGRATION.LS_PROJECT p WHERE p.LREF = pl.PROJECTID
--  );
--
-- Pipeline: LS_PROJECT → LS_PROJECTLINE → dump → 594/595
/


