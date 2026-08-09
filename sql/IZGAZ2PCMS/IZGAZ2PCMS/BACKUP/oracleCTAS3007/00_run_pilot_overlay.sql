-- oracleCTAS3007 / 00_run_pilot_overlay.sql
-- Ornek AGR tahsilat overlay (full CTAS DEGIL — dakikalar)
-- Onkosul: LS_INVOICE (+ INVLINES/DEBT) zaten var VEYA once O10-O14 pilot kosuldu
--
-- Kullanim:
--   @@00_session_parallel.sql
--   @@00_mig_ctas_log.sql
--   @@00_mig_param_pilot.sql          -- AGR listesi
--   @@00_run_pilot_overlay.sql        -- bu dosya
--
-- UYARI: O30 DROP+CREATE → LS_OV_* yalniz MIG_PARAM AGR kapsami.
--        Prod full dump icin @@00_mig_param_full.sql + @@00_run_all.sql
WHENEVER SQLERROR EXIT FAILURE
SET ECHO ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET TIMING ON
SET DEFINE OFF

PROMPT ========== oracleCTAS3007 PILOT OVERLAY START ==========

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM MIGRATION.MIG_PARAM WHERE AGR_ID IS NOT NULL;
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20000,
      'MIG_PARAM.AGR_ID bos — once @@00_mig_param_pilot.sql');
  END IF;
  DBMS_OUTPUT.PUT_LINE('PILOT AGR_CNT=' || n);
END;
/

-- INV yoksa kisa zincir (pilot scope)
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM ALL_TABLES
   WHERE OWNER='MIGRATION' AND TABLE_NAME='LS_INVOICE';
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20001,
      'LS_INVOICE yok — @@10 + @@11 + @@12 + @@14 (MIG_PARAM pilot) kosun.');
  END IF;
END;
/

@@30_ls_tahsilat_overlay.sql
@@32_ls_ov_debt_paid_lastpaid.sql
@@34_ls_ov_pay_pt_bank_enrich.sql
@@33_ls_invoice_close_bank_patch.sql
@@14b_ls_debt_paytrans_rebuild.sql
@@35_ls_ov_id_map.sql
@@41_gate_tahsilat.sql
@@60_ls_ov_guvence_iade.sql

PROMPT ========== PILOT OVERLAY DONE ==========
PROMPT Sonraki: dump (PAY_PT TAH_INV DEBT_PAID INV MAP + GUVENCE_IADE) → izgazMGR
PROMPT         veya wizard pilotDumpMgr APPLY
PROMPT         sonra Energy SP_MIG_597_ALL @AGR_ID=...
/
