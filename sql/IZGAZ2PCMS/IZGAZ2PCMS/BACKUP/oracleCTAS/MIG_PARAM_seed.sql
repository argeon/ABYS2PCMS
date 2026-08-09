-- =============================================================================
-- MIG_PARAM_seed  |  Coklu pilot sozlesme listesi
-- Hedef : MIGRATION.MIG_PARAM
-- Kullanim:
--   - Adim1 (LS_INVOICE.sql) ile ayni set
--   - Overlay CTAS oncesi listeyi yenilemek icin bagimsiz calistirilabilir
-- Full run: DELETE + COMMIT; AGR_ID satiri birakmayin
-- =============================================================================

BEGIN
  EXECUTE IMMEDIATE 'DELETE FROM MIGRATION.MIG_PARAM';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -942 THEN
      EXECUTE IMMEDIATE
        'CREATE TABLE MIGRATION.MIG_PARAM (REG_ID NUMBER(12), AGR_ID NUMBER(12))';
    ELSE
      RAISE;
    END IF;
END;
/

-- Senaryo seti (tekrarli AGR yazilmaz)
INSERT INTO MIGRATION.MIG_PARAM (AGR_ID) VALUES (276503);   -- diger
INSERT INTO MIGRATION.MIG_PARAM (AGR_ID) VALUES (556305);   -- diger
INSERT INTO MIGRATION.MIG_PARAM (AGR_ID) VALUES (197168);   -- ana zincir (taksitsiz)
INSERT INTO MIGRATION.MIG_PARAM (AGR_ID) VALUES (5727);     -- diger
INSERT INTO MIGRATION.MIG_PARAM (AGR_ID) VALUES (2221);     -- taksit
INSERT INTO MIGRATION.MIG_PARAM (AGR_ID) VALUES (978259);   -- taksit
INSERT INTO MIGRATION.MIG_PARAM (AGR_ID) VALUES (1192595);  -- taksit
COMMIT;

SELECT AGR_ID FROM MIGRATION.MIG_PARAM WHERE AGR_ID IS NOT NULL ORDER BY AGR_ID;
/
