-- =====================================================================
-- LS_PROJECT  (Oracle staging - CTAS)
-- Kaynak : SMS.II_PROJECT (+ FIRM_CERTIFICATE / PROJECT_BUILDING / DOOR)
-- Hedef  : MIGRATION.LS_PROJECT  →  izgazMGR.dbo.LS_PROJECT
--          → energy.dbo.LS_005_01_PROJECT  (590/591)
-- Lokasyon: oracleCTAS/ (master; oracleCTAS3007 degil)
-- Pattern: hedef kolon isimleri birebir; ORACLE_PROJECT_ID + STG_* bridge
--
-- Notlar:
--   LREF = SEQ.NEXTVAL ust SELECT'te (alt sorguda ORA-02287)
--   CODE = ayni satirda SEQ.CURRVAL (NEXTVAL ile ayni deger)
--   ORACLE_PROJECT_ID / ABYS_PROJECT_ID = II_PROJECT.ID (591 bridge)
--   BNA: BD.CODE x PROJECT_ID (coklu kapi → fan-out; LREF seq ile ayri satir)
--   Seq CTAS: PARALLEL kapali (NEXTVAL + PX riski)
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_PROJECT PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

-- Seq: MIGRATION (eski SMS_AUDIT.SEQ_LS_PROJECT yerine)
BEGIN
  EXECUTE IMMEDIATE 'CREATE SEQUENCE MIGRATION.SEQ_LS_PROJECT START WITH 1 INCREMENT BY 1 NOCACHE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -955 THEN RAISE; END IF;  -- already exists
END;
/

-- Seq CTAS: PX kapali
ALTER SESSION DISABLE PARALLEL QUERY;
ALTER SESSION DISABLE PARALLEL DML;

CREATE TABLE MIGRATION.LS_PROJECT
NOLOGGING
AS
SELECT
    MIGRATION.SEQ_LS_PROJECT.NEXTVAL                            AS LREF,

    SUBSTR(
        CASE
            WHEN p.PROJECT_TYPE_ID IN (
                5, 8, 13, 17, 20, 22, 24, 26,
                59, 60, 64, 65, 66, 67, 68, 69, 70
            )
            THEN 'T-'
            ELSE ''
        END
        || TO_CHAR(NVL(fc.FIRM_ID, 0))
        || '-'
        || NVL(TO_CHAR(bna.CODE), '0')
        || '-'
        || TO_CHAR(MIGRATION.SEQ_LS_PROJECT.CURRVAL)
    , 1, 50)                                                    AS CODE,

    CAST(0 AS NUMBER(19,4))                                     AS TOTALFEE,
    CAST(0 AS NUMBER(19,4))                                     AS TAX,
    CAST(0 AS NUMBER(19,4))                                     AS GRANDTOTAL,
    CAST(NULL AS VARCHAR2(20 CHAR))                             AS OCODE,
    CAST(NULL AS NUMBER(10))                                    AS XTYPE,

    p.PROJECT_TYPE_ID                                           AS PROJECT_TYPE_ID,
    fc.FIRM_ID                                                  AS FIRM_ID,
    p.ACCOUNT_ID                                                AS INVOICE_ID,

    CASE
        WHEN p.PROJECT_STATUS = 0 THEN 5
        WHEN p.PROJECT_STATUS = 50 THEN 1
        WHEN p.PROJECT_STATUS IN (100, 200, 300, 400, 500, 800) THEN 2
        WHEN p.PROJECT_STATUS IN (888, 999) THEN 4
        ELSE 2
    END                                                         AS STATID,

    -- 590/591 bridge
    p.ID                                                        AS ORACLE_PROJECT_ID,

    CAST(p.PROJECT_YEAR AS NUMBER(5))                           AS ABYS_PROJECT_YEAR,
    CAST(p.PROJECT_NUMBER AS NUMBER(19))                        AS ABYS_PROJECT_NUMBER,
 

    -- ABYS ham
    p.ID                                                        AS ABYS_PROJECT_ID,
    p.PROJECT_STATUS                                            AS ABYS_PROJECT_STATUS,
    p.FIRM_CERTIFICATE_ID                                       AS ABYS_FIRM_CERTIFICATE_ID,
    p.ACCOUNT_ID                                                AS ABYS_ACCOUNT_ID,
    bna.CODE                                                    AS ABYS_BUILDING_DOOR_CODE

FROM SMS.II_PROJECT p
LEFT JOIN SMS.II_FIRM_CERTIFICATE fc
    ON fc.ID = p.FIRM_CERTIFICATE_ID
LEFT JOIN (
    SELECT
        bd.CODE,
        ipb.PROJECT_ID
    FROM SMS.II_PROJECT_BUILDING ipb
    INNER JOIN SMS.GIS_BUILDING_DOOR bd
        ON bd.ID = ipb.BUILDING_DOOR_ID
    GROUP BY
        bd.CODE,
        ipb.PROJECT_ID
) bna
    ON bna.PROJECT_ID = p.ID
;

ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

ALTER TABLE MIGRATION.LS_PROJECT NOPARALLEL LOGGING;

CREATE UNIQUE INDEX MIGRATION.UX_LS_PROJECT_LREF
    ON MIGRATION.LS_PROJECT (LREF) NOLOGGING PARALLEL 8;
ALTER INDEX MIGRATION.UX_LS_PROJECT_LREF NOPARALLEL;

-- fan-out mumkun (coklu BNA.CODE) → UNIQUE degil
CREATE INDEX MIGRATION.IDX_LS_PROJECT_ORACLE_ID
    ON MIGRATION.LS_PROJECT (ORACLE_PROJECT_ID) NOLOGGING PARALLEL 8;
ALTER INDEX MIGRATION.IDX_LS_PROJECT_ORACLE_ID NOPARALLEL;

CREATE INDEX MIGRATION.IDX_LS_PROJECT_FIRM
    ON MIGRATION.LS_PROJECT (FIRM_ID) NOLOGGING PARALLEL 8;
ALTER INDEX MIGRATION.IDX_LS_PROJECT_FIRM NOPARALLEL;

CREATE INDEX MIGRATION.IDX_LS_PROJECT_TYPE
    ON MIGRATION.LS_PROJECT (PROJECT_TYPE_ID) NOLOGGING PARALLEL 8;
ALTER INDEX MIGRATION.IDX_LS_PROJECT_TYPE NOPARALLEL;

CREATE INDEX MIGRATION.IDX_LS_PROJECT_STAT
    ON MIGRATION.LS_PROJECT (STATID) NOLOGGING PARALLEL 8;
ALTER INDEX MIGRATION.IDX_LS_PROJECT_STAT NOPARALLEL;

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS('MIGRATION', 'LS_PROJECT', degree => 56);
END;
/

-- =====================================================================
-- Gate (manuel)
-- =====================================================================
-- SELECT COUNT(1) AS SRC_CNT FROM SMS.II_PROJECT;
-- SELECT COUNT(1) AS TGT_CNT FROM MIGRATION.LS_PROJECT;
-- SELECT STATID, COUNT(1) FROM MIGRATION.LS_PROJECT GROUP BY STATID ORDER BY 1;
-- SELECT PROJECT_TYPE_ID, COUNT(1) FROM MIGRATION.LS_PROJECT GROUP BY PROJECT_TYPE_ID ORDER BY 1;
--
-- Pipeline: CTAS → dump → izgazMGR.dbo.LS_PROJECT → 590/591 (LS_005_01_PROJECT)
/

