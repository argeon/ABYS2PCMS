-- =============================================================================
-- CTAS yavaslik / parallel diag — 172.16.1.201 (veya izgaz)
-- sqlplus ... @00_diag_ctas_slow.sql
-- =============================================================================
SET PAGESIZE 200 LINESIZE 220
SET SERVEROUTPUT ON SIZE UNLIMITED
COLUMN event FORMAT A40
COLUMN username FORMAT A20
COLUMN sql_text FORMAT A60
COLUMN tablespace_name FORMAT A20

PROMPT ========== 1) Aktif CTAS / PX session ==========
SELECT s.sid, s.serial#, s.username, s.status,
       ROUND(s.last_call_et/60) mins,
       s.event,
       s.blocking_session,
       px.qcsid,
       px.server_set,
       SUBSTR(REPLACE(REPLACE(q.sql_text,CHR(10),' '),CHR(13),' '),1,60) sql_text
FROM v$session s
LEFT JOIN v$px_session px ON px.sid = s.sid AND px.serial# = s.serial#
LEFT JOIN v$sql q ON q.sql_id = s.sql_id AND q.child_number = s.sql_child_number
WHERE s.username IS NOT NULL
  AND s.status = 'ACTIVE'
  AND (
       UPPER(NVL(q.sql_text,'x')) LIKE '%MIGRATION.%'
    OR UPPER(NVL(q.sql_text,'x')) LIKE '%CREATE TABLE%'
    OR px.qcsid IS NOT NULL
    OR s.program LIKE '%sqlplus%'
  )
ORDER BY s.last_call_et DESC;

PROMPT ========== 2) Parallel downgrade (bu instance) ==========
SELECT name, value FROM v$sysstat
WHERE name IN (
  'Parallel operations not downgraded',
  'Parallel operations downgraded to serial',
  'Parallel operations downgraded 75 to 99 pct',
  'Parallel operations downgraded 50 to 75 pct',
  'Parallel operations downgraded 25 to 50 pct',
  'Parallel operations downgraded 1 to 25 pct'
);

PROMPT ========== 3) TEMP / undo baskisi ==========
SELECT tablespace_name,
       ROUND(SUM(bytes)/1024/1024) free_mb
FROM dba_free_space
WHERE tablespace_name IN ('TEMP','UNDOTBS1','UNDO','USERS')
GROUP BY tablespace_name
ORDER BY 1;

SELECT tablespace_name, ROUND(bytes_used/1024/1024) used_mb,
       ROUND(bytes_free/1024/1024) free_mb
FROM v$temp_space_header;

PROMPT ========== 4) MIG_CTAS_LOG — yavas / acik adimlar ==========
SELECT STEP_ID, STATUS, STEP_NAME, ROW_CNT, SIZE_MB, ELAPSED_SEC,
       TO_CHAR(START_TS,'MM-DD HH24:MI') ST,
       TO_CHAR(END_TS,'MM-DD HH24:MI') EN,
       TABLE_NAME
FROM (
  SELECT STEP_ID, STATUS, STEP_NAME, ROW_CNT, SIZE_MB, ELAPSED_SEC,
         START_TS, END_TS, TABLE_NAME, LOG_ID,
         ROW_NUMBER() OVER (PARTITION BY STEP_ID ORDER BY LOG_ID DESC) RN
  FROM MIGRATION.MIG_CTAS_LOG
  WHERE STATUS IN ('OK','START','FAIL','GATE_FAIL','GATE_PASS')
)
WHERE RN = 1
ORDER BY LOG_ID;

PROMPT ========== 5) Bitmemis START ==========
SELECT s.STEP_ID, s.STEP_NAME,
       TO_CHAR(s.LOG_TS,'YYYY-MM-DD HH24:MI:SS') START_TS,
       ROUND((SYSDATE - CAST(s.LOG_TS AS DATE))*24*60) MINS
FROM MIGRATION.MIG_CTAS_LOG s
WHERE s.STATUS = 'START'
  AND NOT EXISTS (
    SELECT 1 FROM MIGRATION.MIG_CTAS_LOG e
     WHERE e.STEP_ID = s.STEP_ID AND e.LOG_ID > s.LOG_ID
       AND e.STATUS IN ('OK','FAIL','GATE_FAIL','GATE_PASS')
  )
ORDER BY s.LOG_ID;

PROMPT ========== 6) Session parallel parametre (bu oturum) ==========
SELECT * FROM (
  SELECT 'parallel_degree_policy' n, value FROM v$parameter WHERE name='parallel_degree_policy'
  UNION ALL SELECT 'parallel_max_servers', value FROM v$parameter WHERE name='parallel_max_servers'
  UNION ALL SELECT 'parallel_servers_target', value FROM v$parameter WHERE name='parallel_servers_target'
  UNION ALL SELECT 'cpu_count', value FROM v$parameter WHERE name='cpu_count'
  UNION ALL SELECT 'resource_manager_plan', value FROM v$parameter WHERE name='resource_manager_plan'
);

PROMPT ========== Yorum ==========
PROMPT - PX session yok + CREATE TABLE uzun → seri / downgrade
PROMPT - TEMP free dusuk → PX spill yavas
PROMPT - blocking_session dolu → kilit
PROMPT - Bu hafta FULL A01-A19+O10-O60; gecen hafta genelde daha kisa paket
/
