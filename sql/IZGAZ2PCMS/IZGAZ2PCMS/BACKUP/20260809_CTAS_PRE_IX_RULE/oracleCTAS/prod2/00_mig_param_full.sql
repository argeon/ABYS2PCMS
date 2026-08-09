-- =============================================================================
-- prod2 / 00b — MIG_PARAM FULL (AGR filtresi YOK)
-- Pilot icin: oracleCTAS/MIG_PARAM_seed.sql (DOKUNMA)
-- =============================================================================

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.MIG_PARAM PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE MIGRATION.MIG_PARAM (
  REG_ID NUMBER(12),
  AGR_ID NUMBER(12)
);
COMMIT;

PROMPT ========== MIG_PARAM FULL (bos) OK ==========
/