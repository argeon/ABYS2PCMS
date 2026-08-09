-- =============================================================================
-- LS_WORK / WO_WORK / CREATE TABLE MIGRATION.LS_WORK session kill
-- sqlplus gbayer/...@izgaz @00_kill_ls_work_sessions.sql
-- =============================================================================
SET PAGESIZE 200
SET LINESIZE 220
SET SERVEROUTPUT ON SIZE UNLIMITED
COLUMN sid_serial FORMAT A20
COLUMN username   FORMAT A20
COLUMN program    FORMAT A30
COLUMN event      FORMAT A40
COLUMN sql_text   FORMAT A60

PROMPT ========== ACTIVE sessions (LS_WORK / WO_WORK) ==========
SELECT
    s.sid || ',' || s.serial# AS sid_serial,
    s.username,
    s.status,
    ROUND(s.last_call_et/60) AS mins,
    s.event,
    SUBSTR(s.program,1,30) AS program,
    SUBSTR(REPLACE(REPLACE(q.sql_text,CHR(10),' '),CHR(13),' '),1,60) AS sql_text
FROM v$session s
LEFT JOIN v$sql q
  ON q.sql_id = s.sql_id
 AND q.child_number = s.sql_child_number
WHERE s.username IS NOT NULL
  AND s.status = 'ACTIVE'
  AND (
       UPPER(NVL(q.sql_text,' ')) LIKE '%LS_WORK%'
    OR UPPER(NVL(q.sql_text,' ')) LIKE '%WO_WORK%'
    OR UPPER(NVL(q.sql_text,' ')) LIKE '%CREATE TABLE MIGRATION.LS_WORK%'
  )
ORDER BY s.last_call_et DESC;

PROMPT ========== KILL ==========
DECLARE
  n PLS_INTEGER := 0;
BEGIN
  FOR r IN (
    SELECT s.sid, s.serial#, s.inst_id
    FROM gv$session s
    LEFT JOIN gv$sql q
      ON q.sql_id = s.sql_id
     AND q.child_number = s.sql_child_number
     AND q.inst_id = s.inst_id
    WHERE s.username IS NOT NULL
      AND s.status = 'ACTIVE'
      AND (
           UPPER(NVL(q.sql_text,' ')) LIKE '%LS_WORK%'
        OR UPPER(NVL(q.sql_text,' ')) LIKE '%WO_WORK%'
        OR UPPER(NVL(q.sql_text,' ')) LIKE '%CREATE TABLE MIGRATION.LS_WORK%'
      )
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE
        'ALTER SYSTEM KILL SESSION ''' || r.sid || ',' || r.serial# || ''' IMMEDIATE';
      DBMS_OUTPUT.PUT_LINE('KILLED ' || r.sid || ',' || r.serial#);
      n := n + 1;
    EXCEPTION WHEN OTHERS THEN
      -- RAC: try @inst
      BEGIN
        EXECUTE IMMEDIATE
          'ALTER SYSTEM KILL SESSION ''' || r.sid || ',' || r.serial# || ',@' || r.inst_id || ''' IMMEDIATE';
        DBMS_OUTPUT.PUT_LINE('KILLED ' || r.sid || ',' || r.serial# || ',@' || r.inst_id);
        n := n + 1;
      EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('FAIL ' || r.sid || ',' || r.serial# || ' ' || SQLERRM);
      END;
    END;
  END LOOP;
  IF n = 0 THEN
    DBMS_OUTPUT.PUT_LINE('No matching ACTIVE session.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Total killed: ' || n);
  END IF;
END;
/

PROMPT ========== AFTER ==========
SELECT COUNT(*) AS still_active
FROM v$session s
LEFT JOIN v$sql q ON q.sql_id=s.sql_id AND q.child_number=s.sql_child_number
WHERE s.username IS NOT NULL AND s.status='ACTIVE'
  AND (UPPER(NVL(q.sql_text,' ')) LIKE '%LS_WORK%'
    OR UPPER(NVL(q.sql_text,' ')) LIKE '%WO_WORK%');

PROMPT Sonra: @015_LS_WORK.SQL  (PARALLEL 56, WKT=NULL)
/
