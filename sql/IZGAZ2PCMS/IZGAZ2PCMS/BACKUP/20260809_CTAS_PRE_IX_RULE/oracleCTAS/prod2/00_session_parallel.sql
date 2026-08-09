-- =============================================================================
-- prod2 / 00 — Session parallel (Oracle EE 11.2+)
-- Hedef: 60 core / 128 GB → FORCE DOP 56 (CTAS + index build)
-- Not: RunTah/JDBC DEFINE kullanmaz; DOP sabit.
-- RISK: FORCE 56 PGA/TEMP baskisi — ORA-12801/12805 / temp bitmesi olursa
--       DOP dusur (48) veya tek buyuk CTAS'i ayri session'da calistir.
-- =============================================================================

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;
ALTER SESSION FORCE PARALLEL QUERY PARALLEL 56;
ALTER SESSION FORCE PARALLEL DML PARALLEL 56;

PROMPT ========== prod2 session OK (FORCE PARALLEL 56) ==========
/
