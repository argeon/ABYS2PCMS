using Oracle.ManagedDataAccess.Client;

var cs = "User Id=SMS;Password=RepSmS26!IzGx;Data Source=172.16.1.201:1521/izgaz;Connection Timeout=90;";
Console.WriteLine("Connecting 172.16.1.201 / SMS → MIGRATION checks...");
await using var conn = new OracleConnection(cs);
await conn.OpenAsync();
Console.WriteLine($"OK connected. Server={conn.ServerVersion}");

async Task Run(string title, string sql)
{
    Console.WriteLine();
    Console.WriteLine($"========== {title} ==========");
    await using var cmd = conn.CreateCommand();
    cmd.CommandText = sql;
    cmd.CommandTimeout = 600;
    try
    {
        await using var r = await cmd.ExecuteReaderAsync();
        var cols = r.FieldCount;
        var header = string.Join(" | ", Enumerable.Range(0, cols).Select(i => r.GetName(i)));
        Console.WriteLine(header);
        var n = 0;
        while (await r.ReadAsync())
        {
            var cells = new string[cols];
            for (var i = 0; i < cols; i++)
                cells[i] = r.IsDBNull(i) ? "" : Convert.ToString(r.GetValue(i)) ?? "";
            Console.WriteLine(string.Join(" | ", cells));
            n++;
        }
        if (n == 0) Console.WriteLine("(no rows)");
    }
    catch (Exception ex)
    {
        Console.WriteLine("ERROR: " + ex.Message);
    }
}

await Run("WHOAMI", @"
SELECT USER, SYS_CONTEXT('USERENV','DB_NAME') DB_NAME,
       SYS_CONTEXT('USERENV','SERVER_HOST') HOST,
       SYS_CONTEXT('USERENV','SERVICE_NAME') SVC
FROM DUAL");

await Run("MIGRATION privilege", @"
SELECT privilege FROM (
  SELECT privilege FROM session_privs WHERE privilege IN ('CREATE TABLE','DROP ANY TABLE','SELECT ANY TABLE')
  UNION ALL
  SELECT 'SELECT_'||table_name FROM all_tab_privs
   WHERE owner='MIGRATION' AND grantee=USER AND ROWNUM<=5
)
");

await Run("Key tables exist", @"
SELECT table_name,
       CASE WHEN num_rows IS NULL THEN -1 ELSE num_rows END AS num_rows_stats
FROM all_tables
WHERE owner='MIGRATION'
  AND table_name IN (
    'MIG_CTAS_LOG','LS_AGREEMENT','LS_READING','LS_INVOICE','LS_INVLINES',
    'LS_OV_PAY_PT','LS_OV_PAY_ALLOC','LS_OV_ID_MAP',
    'LS_OV_GUVENCE_IADE_INVOICE','LS_WORK','LS_FLAT'
  )
ORDER BY table_name");

await Run("Live counts (key)", @"
SELECT 'LS_AGREEMENT' t, COUNT(*) n FROM MIGRATION.LS_AGREEMENT UNION ALL
SELECT 'LS_READING', COUNT(*) FROM MIGRATION.LS_READING UNION ALL
SELECT 'LS_INVOICE', COUNT(*) FROM MIGRATION.LS_INVOICE UNION ALL
SELECT 'LS_OV_PAY_PT', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT UNION ALL
SELECT 'LS_OV_PAY_ALLOC', COUNT(*) FROM MIGRATION.LS_OV_PAY_ALLOC UNION ALL
SELECT 'LS_OV_ID_MAP', COUNT(*) FROM MIGRATION.LS_OV_ID_MAP UNION ALL
SELECT 'LS_WORK', COUNT(*) FROM MIGRATION.LS_WORK UNION ALL
SELECT 'GUV_IADE_INV', COUNT(*) FROM MIGRATION.LS_OV_GUVENCE_IADE_INVOICE");

await Run("O41/PT gate snapshot", @"
SELECT 'PAY_PT' k, COUNT(*) n FROM MIGRATION.LS_OV_PAY_PT UNION ALL
SELECT 'PAY_ALLOC', COUNT(*) FROM MIGRATION.LS_OV_PAY_ALLOC UNION ALL
SELECT 'PAY_NO_XREF', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE CROSSREF_MAIN_LREF IS NULL UNION ALL
SELECT 'PT_EQ_ALLOC', CASE WHEN
  (SELECT COUNT(*) FROM MIGRATION.LS_OV_PAY_PT)=(SELECT COUNT(*) FROM MIGRATION.LS_OV_PAY_ALLOC)
  THEN 1 ELSE 0 END FROM DUAL");

await Run("Open START (unfinished)", @"
SELECT s.STEP_ID, s.STEP_NAME,
       TO_CHAR(s.LOG_TS,'YYYY-MM-DD HH24:MI:SS') START_TS,
       ROUND((SYSDATE - CAST(s.LOG_TS AS DATE))*24*60) MINS
FROM MIGRATION.MIG_CTAS_LOG s
WHERE s.STATUS = 'START'
  AND NOT EXISTS (
    SELECT 1 FROM MIGRATION.MIG_CTAS_LOG e
     WHERE e.STEP_ID = s.STEP_ID AND e.LOG_ID > s.LOG_ID
       AND e.STATUS IN ('OK','GATE_PASS','GATE_FAIL','FAIL','WARN')
  )
ORDER BY s.LOG_ID");

await Run("Latest status per step", @"
SELECT STEP_ID, STATUS, STEP_NAME,
       TO_CHAR(LOG_TS,'YYYY-MM-DD HH24:MI:SS') TS,
       SUBSTR(NOTE,1,80) NOTE
FROM (
  SELECT STEP_ID, STATUS, STEP_NAME, LOG_TS, NOTE, LOG_ID,
         ROW_NUMBER() OVER (PARTITION BY STEP_ID ORDER BY LOG_ID DESC) RN
  FROM MIGRATION.MIG_CTAS_LOG
  WHERE STATUS IN ('OK','GATE_PASS','GATE_FAIL','FAIL','START','WARN')
)
WHERE RN = 1
ORDER BY LOG_ID");

await Run("Recent FAIL/GATE_FAIL (last 15)", @"
SELECT STEP_ID, STATUS, TO_CHAR(LOG_TS,'YYYY-MM-DD HH24:MI:SS') TS, SUBSTR(NOTE,1,90) NOTE
FROM (
  SELECT STEP_ID, STATUS, LOG_TS, NOTE, LOG_ID
  FROM MIGRATION.MIG_CTAS_LOG
  WHERE STATUS IN ('FAIL','GATE_FAIL')
  ORDER BY LOG_ID DESC
)
WHERE ROWNUM <= 15");

await Run("Active PX / long SQL", @"
SELECT s.sid, s.serial#, s.status, ROUND(s.last_call_et/60) mins, s.event,
       CASE WHEN px.qcsid IS NOT NULL THEN 'PX' ELSE 'NO_PX' END px,
       SUBSTR(REPLACE(REPLACE(q.sql_text,CHR(10),' '),CHR(13),' '),1,70) sql_text
FROM v$session s
LEFT JOIN v$px_session px ON px.sid=s.sid AND px.serial#=s.serial#
LEFT JOIN v$sql q ON q.sql_id=s.sql_id AND q.child_number=s.sql_child_number
WHERE s.username IS NOT NULL AND s.status='ACTIVE'
  AND (UPPER(NVL(q.sql_text,'x')) LIKE '%MIGRATION%'
       OR px.qcsid IS NOT NULL
       OR s.program LIKE '%sqlplus%')
  AND ROWNUM <= 25
ORDER BY s.last_call_et DESC");

Console.WriteLine();
Console.WriteLine("DONE");
