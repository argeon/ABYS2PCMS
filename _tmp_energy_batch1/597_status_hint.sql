SET NOCOUNT ON;
SELECT r.session_id, r.status, r.command, ISNULL(r.wait_type,'-') wait_type,
       r.wait_time/1000 wait_s, r.blocking_session_id blk,
       r.cpu_time/1000 cpu_s, r.logical_reads, r.writes,
       LEFT(REPLACE(REPLACE(t.text,CHAR(13),' '),CHAR(10),' '),160) txt
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID AND r.database_id = DB_ID(N'energy')
ORDER BY r.logical_reads DESC;

SELECT
  SUM(CASE WHEN USE_HINT=1 AND LOADED=0 THEN 1 ELSE 0 END) hint_left,
  SUM(CASE WHEN USE_HINT=0 AND LOADED=0 THEN 1 ELSE 0 END) id_left,
  SUM(CASE WHEN LOADED=1 THEN 1 ELSE 0 END) loaded,
  COUNT(*) total
FROM dbo.MIG_597_STG_PAY WITH (NOLOCK);

SELECT name, size*8/1024 size_mb, FILEPROPERTY(name,'SpaceUsed')*8/1024 used_mb,
       CAST(100.0*FILEPROPERTY(name,'SpaceUsed')/NULLIF(size,0) AS decimal(5,1)) pct
FROM sys.database_files WHERE type_desc=N'LOG';

SELECT COUNT(*) pt_ncix_enabled
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID(N'dbo.LS_005_01_PAYTRANS') AND i.type=2 AND i.is_disabled=0;
