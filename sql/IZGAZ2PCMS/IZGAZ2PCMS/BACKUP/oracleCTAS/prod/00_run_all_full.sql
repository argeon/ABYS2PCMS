-- =============================================================================
-- 00_run_all_full.sql — FULL CTAS zinciri (01..05) + gate (06)
-- Calistir: sqlplus veya SQL Developer "Run Script" (F5), bu klasorden.
-- Hata olursa WHENEVER SQLERROR ile durur (gate RAISE dahil).
-- RunTah kullanacaksan: 00_run_all_full.ps1
-- =============================================================================

WHENEVER SQLERROR EXIT FAILURE
SET ECHO ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET TIMING ON
SET DEFINE OFF

PROMPT ========== 01 LS_INVOICE ==========
@@01_LS_INVOICE__full.sql

PROMPT ========== 02 LS_INVLINES ==========
@@02_LS_INVLINES__full.sql

PROMPT ========== 03 LS_EKSILTEN_OVERLAY ==========
@@03_LS_EKSILTEN_OVERLAY__full.sql

PROMPT ========== 04 LS_TAHSILAT_OVERLAY ==========
@@04_LS_TAHSILAT_OVERLAY__full.sql

PROMPT ========== 05 LS_TAHSILAT_LOG ==========
@@05_LS_TAHSILAT_LOG__full.sql

PROMPT ========== 06 ADIM5 HARD GATE ==========
@@06_adim5_tahsilat_gate_full.sql

PROMPT ========== 00_run_all_full DONE ==========
