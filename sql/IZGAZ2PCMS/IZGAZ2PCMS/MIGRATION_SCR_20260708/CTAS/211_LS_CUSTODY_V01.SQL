-- 211_LS_CUSTODY_V01.SQL
-- Amac: Custody staging
-- Uretir: LS_CUSTODY
-- Gate: yok
-- Sonraki: 250_TRANSFER_INDEXES_V01.SQL
WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- TERMINAL DUMP: Oracle INDEX / GATHER_TABLE_STATS yok (CTAS zincirinde tuketilmiyor; IX -> izgazMGR/energy).

-- =============================================================================
-- oracleCTAS3007 / 61 — LS_CUSTODY (register emanet / borc snapshot)
-- Ortam : Oracle 11.2 | Schema: MIGRATION | Kaynak: SMS
-- Tek basina calisir; B zorunlu zinciri BLOKE ETMEZ
--
-- Grain : CS_REGISTER.ID  (hesap netleri → register rollup)
-- Mantik : oracleControl/CUSTODY.sql  (II_FIRM_PRM YOK — tum register)
--   ACCRUE_TYPE_ID = 14 → CUSTODY (amount*status)
--   ACCRUE_TYPE_ID <> 14 → DEBT_BALANCE
--   CUSTODY < 0  → normal emanet (alacak)
--   CUSTODY > 0  → PROBLEMATIC_CUSTODY (emanet net borc — anomali)
--
-- Dump → izgazMGR.dbo.LS_CUSTODY (ENERGY zorunlu yuk degil; recon)
-- DOP: FORCE 56
-- =============================================================================

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

DECLARE
  n NUMBER;
BEGIN
  BEGIN
    MIGRATION.P_MIG_CTAS_LOG('O61', 'ls_custody', 'START', NULL,
      'register grain CUSTODY / DEBT / PROBLEMATIC (no II_FIRM_PRM)');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
/

BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_CUSTODY PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_CUSTODY
NOLOGGING
PARALLEL 56
AS
SELECT /*+ PARALLEL(56) */
    CAST(MAX(x.ACTION_DATE) AS DATE)                             AS ACTION_DATE,
    CAST(MAX(x.AGREEMENT_ID) AS NUMBER(12))                      AS AGREEMENT_ID,
    CAST(x.REGISTER_ID AS NUMBER(12))                            AS REGISTER_ID,
    CAST(x.FIRM_NAME AS VARCHAR2(400))                           AS FIRM_NAME,
    CAST(ROUND(SUM(x.DEBT_BALANCE), 2) AS NUMBER(18,2))          AS DEBT_BALANCE,
    CAST(ROUND(SUM(CASE WHEN x.CUSTODY < 0 THEN x.CUSTODY ELSE 0 END), 2)
         AS NUMBER(18,2))                                        AS CUSTODY,
    CAST(ROUND(SUM(CASE WHEN x.CUSTODY > 0 THEN x.CUSTODY ELSE 0 END), 2)
         AS NUMBER(18,2))                                        AS PROBLEMATIC_CUSTODY,
    CAST(TRUNC(SYSDATE) AS DATE)                                 AS AS_OF_DATE,
    CAST(SYSDATE AS DATE)                                        AS SNAPSHOT_DATE
FROM (
    SELECT
        MAX(aa.ACTION_DATE)                                      AS ACTION_DATE,
        MAX(a.AGREEMENT_ID)                                      AS AGREEMENT_ID,
        r.ID                                                     AS REGISTER_ID,
        r.FIRST_NAME || ' ' || r.LAST_NAME                       AS FIRM_NAME,
        NVL(SUM(CASE WHEN a.ACCRUE_TYPE_ID = 14
                     THEN ai.AMOUNT * ai.STATUS END), 0)         AS CUSTODY,
        NVL(SUM(CASE WHEN a.ACCRUE_TYPE_ID <> 14
                     THEN ai.AMOUNT * ai.STATUS END), 0)         AS DEBT_BALANCE
    FROM SMS.CS_REGISTER r
    JOIN SMS.CS_ACCOUNT a
      ON a.REGISTER_ID = r.ID
    JOIN SMS.CS_ACCOUNT_ACTION aa
      ON aa.ACCOUNT_ID = a.ID
    JOIN SMS.CS_ACCOUNT_INCOME ai
      ON ai.ACCOUNT_ACTION_ID = aa.ID
    GROUP BY
        r.ID,
        r.FIRST_NAME,
        r.LAST_NAME,
        a.ID
) x
WHERE x.CUSTODY <> 0
   OR x.DEBT_BALANCE <> 0
GROUP BY
    x.REGISTER_ID,
    x.FIRM_NAME;

ALTER TABLE MIGRATION.LS_CUSTODY NOPARALLEL LOGGING;


-- RECON
SELECT
    COUNT(*) AS CUSTODY_CNT,
    COUNT(CASE WHEN PROBLEMATIC_CUSTODY <> 0 THEN 1 END) AS PROB_CNT,
    COUNT(CASE WHEN CUSTODY <> 0 THEN 1 END) AS NORM_CUST_CNT,
    COUNT(CASE WHEN DEBT_BALANCE <> 0 THEN 1 END) AS DEBT_NZ_CNT,
    ROUND(SUM(DEBT_BALANCE), 2) AS DEBT_SUM,
    ROUND(SUM(CUSTODY), 2) AS CUSTODY_SUM,
    ROUND(SUM(PROBLEMATIC_CUSTODY), 2) AS PROB_SUM
FROM MIGRATION.LS_CUSTODY;

DECLARE
  n_all NUMBER; n_prob NUMBER;
BEGIN
  SELECT COUNT(*), COUNT(CASE WHEN PROBLEMATIC_CUSTODY <> 0 THEN 1 END)
    INTO n_all, n_prob FROM MIGRATION.LS_CUSTODY;
  MIGRATION.P_MIG_CTAS_LOG('O61', 'ls_custody', 'OK', n_all,
    'reg=' || n_all || ' problematic=' || n_prob);
  DBMS_OUTPUT.PUT_LINE('========== O61 LS_CUSTODY OK | reg=' || n_all
    || ' problematic=' || n_prob || ' | CTAS BITTI ==========');
END;
/

