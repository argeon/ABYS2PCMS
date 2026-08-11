-- 010_MIG_CTAS_LOG_V01.SQL
-- Amac: Adim log altyapisi
-- Uretir: MIG_CTAS_LOG
-- Gate: yok
-- Sonraki: 011_SESSION_PARALLEL_V01.SQL
-- =============================================================================
-- oracleCTAS3007 / 00_mig_ctas_log — adim log (cnt / MB / sure)
-- Izle: @99_log_status.sql
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
      TABLE_NAME  VARCHAR2(400),
      BYTES       NUMBER,
      SIZE_MB     NUMBER,
      START_TS    TIMESTAMP,
      END_TS      TIMESTAMP,
      ELAPSED_SEC NUMBER,
      CONSTRAINT PK_MIG_CTAS_LOG PRIMARY KEY (LOG_ID)
    )]';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -955 THEN RAISE; END IF;
END;
/

BEGIN EXECUTE IMMEDIATE 'ALTER TABLE MIGRATION.MIG_CTAS_LOG ADD (TABLE_NAME VARCHAR2(400))';
EXCEPTION WHEN OTHERS THEN IF SQLCODE NOT IN (-1430, -00957) THEN NULL; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'ALTER TABLE MIGRATION.MIG_CTAS_LOG ADD (BYTES NUMBER)';
EXCEPTION WHEN OTHERS THEN IF SQLCODE NOT IN (-1430, -00957) THEN NULL; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'ALTER TABLE MIGRATION.MIG_CTAS_LOG ADD (SIZE_MB NUMBER)';
EXCEPTION WHEN OTHERS THEN IF SQLCODE NOT IN (-1430, -00957) THEN NULL; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'ALTER TABLE MIGRATION.MIG_CTAS_LOG ADD (START_TS TIMESTAMP)';
EXCEPTION WHEN OTHERS THEN IF SQLCODE NOT IN (-1430, -00957) THEN NULL; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'ALTER TABLE MIGRATION.MIG_CTAS_LOG ADD (END_TS TIMESTAMP)';
EXCEPTION WHEN OTHERS THEN IF SQLCODE NOT IN (-1430, -00957) THEN NULL; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'ALTER TABLE MIGRATION.MIG_CTAS_LOG ADD (ELAPSED_SEC NUMBER)';
EXCEPTION WHEN OTHERS THEN IF SQLCODE NOT IN (-1430, -00957) THEN NULL; END IF; END;
/

BEGIN
  EXECUTE IMMEDIATE 'CREATE INDEX MIGRATION.IX_MIG_CTAS_LOG_STEP ON MIGRATION.MIG_CTAS_LOG (STEP_ID, LOG_TS)';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -955 THEN RAISE; END IF;
END;
/

CREATE OR REPLACE PACKAGE MIGRATION.PKG_MIG_CTAS_TIMING AS
  g_step_id   VARCHAR2(20);
  g_step_name VARCHAR2(120);
  g_start_ts  TIMESTAMP;
END PKG_MIG_CTAS_TIMING;
/
SHOW ERRORS

CREATE OR REPLACE PROCEDURE MIGRATION.P_MIG_CTAS_LOG (
  p_step_id     VARCHAR2,
  p_step_name   VARCHAR2,
  p_status      VARCHAR2,
  p_row_cnt     NUMBER    DEFAULT NULL,
  p_note        VARCHAR2  DEFAULT NULL,
  p_table_name  VARCHAR2  DEFAULT NULL,
  p_bytes       NUMBER    DEFAULT NULL,
  p_start_ts    TIMESTAMP DEFAULT NULL,
  p_end_ts      TIMESTAMP DEFAULT NULL,
  p_elapsed_sec NUMBER    DEFAULT NULL
) AS
  v_line VARCHAR2(1200);
  v_id   NUMBER;
  v_mb   NUMBER;
BEGIN
  SELECT MIGRATION.SEQ_MIG_CTAS_LOG.NEXTVAL INTO v_id FROM DUAL;
  v_mb := CASE WHEN p_bytes IS NOT NULL THEN ROUND(p_bytes / 1024 / 1024, 2) ELSE NULL END;

  INSERT INTO MIGRATION.MIG_CTAS_LOG (
    LOG_ID, STEP_ID, STEP_NAME, STATUS, ROW_CNT, NOTE, SID, USERNAME,
    TABLE_NAME, BYTES, SIZE_MB, START_TS, END_TS, ELAPSED_SEC
  ) VALUES (
    v_id,
    UPPER(TRIM(p_step_id)),
    SUBSTR(p_step_name, 1, 120),
    UPPER(TRIM(p_status)),
    p_row_cnt,
    SUBSTR(p_note, 1, 500),
    SYS_CONTEXT('USERENV', 'SID'),
    SYS_CONTEXT('USERENV', 'SESSION_USER'),
    SUBSTR(p_table_name, 1, 400),
    p_bytes,
    v_mb,
    p_start_ts,
    p_end_ts,
    p_elapsed_sec
  );
  COMMIT;

  v_line :=
    TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS')
    || ' | ' || UPPER(TRIM(p_step_id))
    || ' | ' || RPAD(UPPER(TRIM(p_status)), 10)
    || ' | ' || NVL(SUBSTR(p_step_name, 1, 36), '-')
    || CASE WHEN p_row_cnt IS NOT NULL THEN ' | cnt=' || TO_CHAR(p_row_cnt) ELSE '' END
    || CASE WHEN v_mb IS NOT NULL THEN ' | mb=' || TO_CHAR(v_mb) ELSE '' END
    || CASE WHEN p_elapsed_sec IS NOT NULL THEN ' | sec=' || TO_CHAR(p_elapsed_sec) ELSE '' END
    || CASE WHEN p_note IS NOT NULL THEN ' | ' || SUBSTR(p_note, 1, 120) ELSE '' END;

  DBMS_OUTPUT.PUT_LINE(v_line);
END;
/
SHOW ERRORS

CREATE OR REPLACE PROCEDURE MIGRATION.P_MIG_CTAS_RUN_INIT (
  p_mode VARCHAR2 DEFAULT 'FULL'
) AS
BEGIN
  MIGRATION.P_MIG_CTAS_LOG(
    p_step_id   => 'RUN',
    p_step_name => 'run_init',
    p_status    => 'INFO',
    p_note      => 'FULL | tum adimlar DROP+CREATE'
  );
  DBMS_OUTPUT.PUT_LINE('========== CTAS FULL RUN ==========');
END;
/
SHOW ERRORS

CREATE OR REPLACE PROCEDURE MIGRATION.P_MIG_CTAS_STEP_BEGIN (
  p_step_id   VARCHAR2,
  p_step_name VARCHAR2
) AS
BEGIN
  MIGRATION.PKG_MIG_CTAS_TIMING.g_step_id   := UPPER(TRIM(p_step_id));
  MIGRATION.PKG_MIG_CTAS_TIMING.g_step_name := SUBSTR(p_step_name, 1, 120);
  MIGRATION.PKG_MIG_CTAS_TIMING.g_start_ts  := SYSTIMESTAMP;

  MIGRATION.P_MIG_CTAS_LOG(
    p_step_id     => p_step_id,
    p_step_name   => p_step_name,
    p_status      => 'START',
    p_note        => 'step begin',
    p_start_ts    => MIGRATION.PKG_MIG_CTAS_TIMING.g_start_ts
  );
END;
/
SHOW ERRORS

CREATE OR REPLACE PROCEDURE MIGRATION.P_MIG_CTAS_STEP_END (
  p_step_id    VARCHAR2,
  p_step_name  VARCHAR2,
  p_owner      VARCHAR2 DEFAULT 'MIGRATION',
  p_tables_csv VARCHAR2 DEFAULT NULL
) AS
  v_start   TIMESTAMP := NVL(MIGRATION.PKG_MIG_CTAS_TIMING.g_start_ts, SYSTIMESTAMP);
  v_end     TIMESTAMP := SYSTIMESTAMP;
  v_elapsed NUMBER;
  v_owner   VARCHAR2(30) := NVL(UPPER(TRIM(p_owner)), 'MIGRATION');
  v_csv     VARCHAR2(4000) := REPLACE(NVL(p_tables_csv, ''), ' ', '');
  v_rest    VARCHAR2(4000);
  v_tok     VARCHAR2(128);
  v_pos     PLS_INTEGER;
  v_sum_cnt NUMBER := 0;
  v_sum_b   NUMBER := 0;
  v_detail  VARCHAR2(500) := '';
  v_tables  VARCHAR2(400) := '';
  v_one_c   NUMBER;
  v_one_b   NUMBER;
  v_sql     VARCHAR2(400);

  FUNCTION seg_bytes(p_own VARCHAR2, p_tab VARCHAR2) RETURN NUMBER IS
    v NUMBER;
  BEGIN
    BEGIN
      EXECUTE IMMEDIATE
        q'[SELECT NVL(SUM(bytes),0)
             FROM dba_segments
            WHERE owner = :o
              AND (
                    segment_name = :t
                 OR segment_name IN (
                      SELECT index_name FROM dba_indexes
                       WHERE table_owner = :o2 AND table_name = :t2
                    )
              )]'
        INTO v
        USING p_own, p_tab, p_own, p_tab;
      RETURN v;
    EXCEPTION
      WHEN OTHERS THEN
        BEGIN
          SELECT NVL(SUM(bytes), 0)
            INTO v
            FROM user_segments
           WHERE segment_name = p_tab
              OR segment_name IN (
                   SELECT index_name FROM user_indexes WHERE table_name = p_tab
                 );
          RETURN v;
        EXCEPTION
          WHEN OTHERS THEN
            RETURN NULL;
        END;
    END;
  END;

BEGIN
  v_elapsed := ROUND(
    EXTRACT(DAY    FROM (v_end - v_start)) * 86400
  + EXTRACT(HOUR   FROM (v_end - v_start)) * 3600
  + EXTRACT(MINUTE FROM (v_end - v_start)) * 60
  + EXTRACT(SECOND FROM (v_end - v_start))
  , 2);

  IF v_csv IS NULL THEN
    MIGRATION.P_MIG_CTAS_LOG(
      p_step_id     => p_step_id,
      p_step_name   => p_step_name,
      p_status      => 'OK',
      p_note        => 'no table metric | elapsed_sec=' || TO_CHAR(v_elapsed),
      p_start_ts    => v_start,
      p_end_ts      => v_end,
      p_elapsed_sec => v_elapsed
    );
    RETURN;
  END IF;

  v_rest := v_csv || ',';
  LOOP
    v_pos := INSTR(v_rest, ',');
    EXIT WHEN v_pos = 0 OR v_rest IS NULL;
    v_tok := UPPER(TRIM(SUBSTR(v_rest, 1, v_pos - 1)));
    v_rest := SUBSTR(v_rest, v_pos + 1);
    IF v_tok IS NOT NULL THEN
      v_one_c := NULL;
      v_one_b := NULL;
      BEGIN
        v_sql := 'SELECT COUNT(*) FROM ' || v_owner || '.' || v_tok;
        EXECUTE IMMEDIATE v_sql INTO v_one_c;
      EXCEPTION
        WHEN OTHERS THEN
          v_one_c := NULL;
          v_detail := SUBSTR(v_detail || v_tok || '=ERR:' || SQLCODE || ';', 1, 500);
      END;

      v_one_b := seg_bytes(v_owner, v_tok);

      IF v_one_c IS NOT NULL THEN
        v_sum_cnt := v_sum_cnt + v_one_c;
      END IF;
      IF v_one_b IS NOT NULL THEN
        v_sum_b := v_sum_b + v_one_b;
      END IF;

      v_tables := SUBSTR(CASE WHEN v_tables IS NULL THEN v_tok ELSE v_tables || ',' || v_tok END, 1, 400);
      v_detail := SUBSTR(
        v_detail
        || v_tok || '=' || NVL(TO_CHAR(v_one_c), '?')
        || 'r/' || CASE WHEN v_one_b IS NULL THEN '?' ELSE TO_CHAR(ROUND(v_one_b/1024/1024, 2)) || 'MB' END
        || ';',
        1, 500
      );
    END IF;
  END LOOP;

  MIGRATION.P_MIG_CTAS_LOG(
    p_step_id     => p_step_id,
    p_step_name   => p_step_name,
    p_status      => 'OK',
    p_row_cnt     => v_sum_cnt,
    p_note        => SUBSTR(v_detail, 1, 500),
    p_table_name  => v_tables,
    p_bytes       => CASE WHEN v_sum_b > 0 THEN v_sum_b ELSE NULL END,
    p_start_ts    => v_start,
    p_end_ts      => v_end,
    p_elapsed_sec => v_elapsed
  );
END;
/
SHOW ERRORS

PROMPT ========== 00 MIG_CTAS_LOG hazir | izle: @99_log_status.sql ==========
/

