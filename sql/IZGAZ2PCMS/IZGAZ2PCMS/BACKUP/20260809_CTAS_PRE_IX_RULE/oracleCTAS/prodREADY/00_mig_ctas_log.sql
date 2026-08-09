-- =============================================================================
-- prodREADY / 00_mig_ctas_log — Oracle adim log (11.2 uyumlu)
-- Format: YYYY-MM-DD HH24:MI:SS | STEP | STATUS | name | cnt= | note
-- Izle: @99_log_status.sql  veya  SELECT * FROM MIGRATION.MIG_CTAS_LOG ORDER BY LOG_ID;
-- =============================================================================

BEGIN
  EXECUTE IMMEDIATE 'CREATE SEQUENCE MIGRATION.SEQ_MIG_CTAS_LOG START WITH 1 INCREMENT BY 1 NOCACHE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -955 THEN RAISE; END IF;
END;
/
BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE TABLE MIGRATION.MIG_CTAS_LOG (
      LOG_ID      NUMBER        NOT NULL,
      LOG_TS      TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
      STEP_ID     VARCHAR2(20)  NOT NULL,
      STEP_NAME   VARCHAR2(120) NOT NULL,
      STATUS      VARCHAR2(16)  NOT NULL,
      ROW_CNT     NUMBER,
      NOTE        VARCHAR2(500),
      SID         NUMBER,
      USERNAME    VARCHAR2(30),
      CONSTRAINT PK_MIG_CTAS_LOG PRIMARY KEY (LOG_ID)
    )]';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -955 THEN RAISE; END IF;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'CREATE INDEX MIGRATION.IX_MIG_CTAS_LOG_STEP ON MIGRATION.MIG_CTAS_LOG (STEP_ID, LOG_TS)';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -955 THEN RAISE; END IF;
END;
/

CREATE OR REPLACE PROCEDURE MIGRATION.P_MIG_CTAS_LOG (
  p_step_id   VARCHAR2,
  p_step_name VARCHAR2,
  p_status    VARCHAR2,
  p_row_cnt   NUMBER   DEFAULT NULL,
  p_note      VARCHAR2 DEFAULT NULL
) AS
  v_line VARCHAR2(1000);
  v_id   NUMBER;
BEGIN
  SELECT MIGRATION.SEQ_MIG_CTAS_LOG.NEXTVAL INTO v_id FROM DUAL;

  INSERT INTO MIGRATION.MIG_CTAS_LOG (
    LOG_ID, STEP_ID, STEP_NAME, STATUS, ROW_CNT, NOTE, SID, USERNAME
  ) VALUES (
    v_id,
    UPPER(TRIM(p_step_id)),
    SUBSTR(p_step_name, 1, 120),
    UPPER(TRIM(p_status)),
    p_row_cnt,
    SUBSTR(p_note, 1, 500),
    SYS_CONTEXT('USERENV', 'SID'),
    SYS_CONTEXT('USERENV', 'SESSION_USER')
  );
  COMMIT;

  v_line :=
    TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS')
    || ' | ' || UPPER(TRIM(p_step_id))
    || ' | ' || RPAD(UPPER(TRIM(p_status)), 10)
    || ' | ' || NVL(SUBSTR(p_step_name, 1, 40), '-')
    || CASE WHEN p_row_cnt IS NOT NULL THEN ' | cnt=' || TO_CHAR(p_row_cnt) ELSE '' END
    || CASE WHEN p_note IS NOT NULL THEN ' | ' || SUBSTR(p_note, 1, 180) ELSE '' END;

  DBMS_OUTPUT.PUT_LINE(v_line);
END;
/
SHOW ERRORS

PROMPT ========== 00 MIG_CTAS_LOG hazir | izle: @99_log_status.sql ==========
/
