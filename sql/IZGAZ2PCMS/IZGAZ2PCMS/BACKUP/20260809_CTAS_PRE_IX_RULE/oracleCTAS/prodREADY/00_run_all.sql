-- prodREADY / 00_run_all.sql — yedek otomasyon (tercih: tek tek + tee log)
-- Her adim MIG_CTAS_LOG yazar; GATE_FAIL → EXIT
WHENEVER SQLERROR EXIT FAILURE
SET ECHO ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET TIMING ON
SET DEFINE OFF

PROMPT ========== prodREADY FULL RUN START ==========
@@00_session_parallel.sql
@@00_mig_param_full.sql
@@10_stg_inv_acc_inc.sql
@@11_ls_invoice.sql
@@12_ls_invlines.sql
@@13_ls_mig_agr_list.sql
@@14_ls_debt_paytrans.sql
@@20_ls_eksilten_overlay.sql
@@27_gate_eksilten.sql
@@30_ls_tahsilat_overlay.sql
@@30_HOTFIX_ls_ov_tah_log_pay_before.sql
@@32_ls_ov_debt_paid_lastpaid.sql
@@35_ls_ov_id_map.sql
-- @@40_ls_tahsilat_log.sql   -- SKIP: O30h HOTFIX TAH_LOG (PAY_BEFORE_*)
@@41_gate_tahsilat.sql
@@50_ls_afl_open_debt.sql
@@51_ls_stg_inv_pay_close.sql
@@52_ls_payment.sql
@@53_ls_eksilten_family.sql
@@54_ls_artiran_emanet.sql
@@55_ls_mahsup.sql
@@56_ls_taksit.sql
@@99_log_status.sql

PROMPT ========== prodREADY FULL RUN DONE — FAIL yoksa dump ==========
/
