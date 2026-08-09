-- =============================================================================
-- prod2 / 00_run_all.sql — FULL CTAS zinciri (energy-yakin staged)
-- Calistir: sqlplus / SQL Developer F5 (bu klasorden)
-- RunTah: 00_run_all.ps1
-- Hata olursa WHENEVER SQLERROR ile durur (gate RAISE dahil).
-- =============================================================================

WHENEVER SQLERROR EXIT FAILURE
SET ECHO ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET TIMING ON
SET DEFINE OFF

PROMPT ========== 00 SESSION ==========
@@00_session_parallel.sql

PROMPT ========== 00 MIG_PARAM ==========
@@00_mig_param_full.sql

PROMPT ========== 10 STG_INV_ACC_INC ==========
@@10_stg_inv_acc_inc.sql

PROMPT ========== 11 LS_INVOICE ==========
@@11_ls_invoice.sql

PROMPT ========== 12 LS_INVLINES ==========
@@12_ls_invlines.sql

PROMPT ========== 13 LS_MIG_AGR_LIST ==========
@@13_ls_mig_agr_list.sql

PROMPT ========== 14 LS_DEBT_PAYTRANS ==========
@@14_ls_debt_paytrans.sql

PROMPT ========== 20 EKSILTEN ==========
@@20_ls_eksilten_overlay.sql

PROMPT ========== 27 GATE EKSILTEN ==========
@@27_gate_eksilten.sql

PROMPT ========== 30 TAHSILAT ==========
@@30_ls_tahsilat_overlay.sql

PROMPT ========== 40 TAHSILAT LOG ==========
@@40_ls_tahsilat_log.sql

PROMPT ========== 41 GATE TAHSILAT ==========
@@41_gate_tahsilat.sql

PROMPT ========== 50 AFL OPEN DEBT ==========
@@50_ls_afl_open_debt.sql

PROMPT ========== 51 STG INV PAY CLOSE ==========
@@51_ls_stg_inv_pay_close.sql

PROMPT ========== 52 LS_PAYMENT ==========
@@52_ls_payment.sql

PROMPT ========== 53 EKSILTEN FAMILY ==========
@@53_ls_eksilten_family.sql

PROMPT ========== 54 ARTIRAN / EMANET ==========
@@54_ls_artiran_emanet.sql

PROMPT ========== 55 MAHSUP ==========
@@55_ls_mahsup.sql

PROMPT ========== 56 TAKSIT ==========
@@56_ls_taksit.sql

PROMPT ========== prod2 00_run_all DONE (manuel tercih: tek tek; bu dosya otomasyon) ==========
/
-- NOT: Greenfield ana yol MANUEL — prodEnergy/MANUAL_RUN_PLAN_GREENFIELD.txt
--      00_run_all sadece acil/toplu yedek; O50 AFL + O51 STG.