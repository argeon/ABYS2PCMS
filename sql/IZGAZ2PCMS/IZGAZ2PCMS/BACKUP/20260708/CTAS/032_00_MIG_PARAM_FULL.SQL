-- =============================================================================
-- oracleCTAS3007 / O0b — MIG_PARAM FULL (AGR filtresi YOK)
-- Pilot ornek AGR: @@033_00_MIG_PARAM_PILOT.SQL  (bu dosya DEGIL)
-- Filtre: O10 / O11 / O30 TMP_MIG_ACC — AGR_ID doluysa pilot scope
-- =============================================================================

BEGIN
  MIGRATION.P_MIG_CTAS_LOG('O0b', 'mig_param_full', 'START', NULL, 'DROP+CREATE MIG_PARAM empty');
EXCEPTION WHEN OTHERS THEN NULL; -- log proc henuz yoksa (tek basina kosu)
END;
/

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

BEGIN
  MIGRATION.P_MIG_CTAS_LOG('O0b', 'mig_param_full', 'OK', 0, 'FULL mode — AGR filter YOK');
END;
/

PROMPT ========== O0b MIG_PARAM FULL (bos) OK ==========
/

