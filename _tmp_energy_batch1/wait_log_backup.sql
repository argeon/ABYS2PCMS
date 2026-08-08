SET NOCOUNT ON;
DECLARE @i INT = 0;
WHILE @i < 60
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.dm_exec_requests
        WHERE session_id = 77 OR command = N'BACKUP LOG'
    )
        BREAK;
    WAITFOR DELAY '00:00:05';
    SET @i += 1;
END

SELECT CASE WHEN EXISTS (
    SELECT 1 FROM sys.dm_exec_requests WHERE command = N'BACKUP LOG'
) THEN 'BACKUP_STILL_RUNNING' ELSE 'BACKUP_DONE' END AS backup_status;

SELECT name, size*8/1024 size_mb, FILEPROPERTY(name,'SpaceUsed')*8/1024 used_mb,
       CAST(100.0*FILEPROPERTY(name,'SpaceUsed')/NULLIF(size,0) AS decimal(5,1)) pct,
       log_reuse_wait_desc
FROM sys.database_files CROSS JOIN sys.databases d
WHERE database_files.type_desc=N'LOG' AND d.name=N'energy';
