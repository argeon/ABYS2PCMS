-- 011_SESSION_PARALLEL_V01.SQL
-- Amac: Session DOP 56 (TEMP → 48)
-- Gate: yok
-- Sonraki: 012_MIG_PARAM_FULL_V01.SQL
-- =============================================================================
-- oracleCTAS3007 / 00 — Session parallel + log hazir
-- FORCE PARALLEL 56 | RISK: TEMP/PGA → DOP 48
-- =============================================================================

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

SET SERVEROUTPUT ON SIZE UNLIMITED
SET TIMING ON

-- Log: once @00_mig_ctas_log.sql (00_run_all bunu SESSION'dan ONCE cagirir)
BEGIN
  MIGRATION.P_MIG_CTAS_LOG(
    'O0', 'session_parallel', 'START', NULL,
    'FORCE PARALLEL QUERY/DML 56'
  );
  MIGRATION.P_MIG_CTAS_LOG(
    'O0', 'session_parallel', 'OK', NULL,
    'session ready — sonraki: O0b MIG_PARAM'
  );
END;
/

PROMPT ========== O0 SESSION OK | FORCE PARALLEL 56 | log=MIG_CTAS_LOG ==========
/

