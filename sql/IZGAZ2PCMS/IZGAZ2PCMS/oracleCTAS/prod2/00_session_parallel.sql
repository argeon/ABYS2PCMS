-- =============================================================================
-- prod2 / 00 — Session parallel (Oracle EE 11.2+)
-- Hedef: 60 core / 128 GB → DOP 52 (aggregate stage'lerde 28)
-- Not: RunTah/JDBC DEFINE kullanmaz; DOP sabit.
-- =============================================================================

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;

PROMPT ========== prod2 session OK (DOP hedef 52 / AGG 28) ==========
/