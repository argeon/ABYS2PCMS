SET NOCOUNT ON;
DECLARE @i INT = 0;
WHILE @i < 120
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.dm_exec_requests WHERE command = N'BACKUP LOG')
        BREAK;
    WAITFOR DELAY '00:00:05';
    SET @i += 1;
END

SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.dm_exec_requests WHERE command = N'BACKUP LOG')
           THEN 'BACKUP_STILL' ELSE 'BACKUP_DONE' END AS st;

SELECT df.name, df.size*8/1024 size_mb,
       FILEPROPERTY(df.name,'SpaceUsed')*8/1024 used_mb,
       CAST(100.0*FILEPROPERTY(df.name,'SpaceUsed')/NULLIF(df.size,0) AS decimal(5,1)) pct,
       d.log_reuse_wait_desc
FROM sys.database_files df
JOIN sys.databases d ON d.name = DB_NAME()
WHERE df.type_desc = N'LOG';

-- grow if still >85% used or reuse wait
DECLARE @pct decimal(5,1) = (
    SELECT CAST(100.0*FILEPROPERTY(name,'SpaceUsed')/NULLIF(size,0) AS decimal(5,1))
    FROM sys.database_files WHERE type_desc=N'LOG'
);
IF @pct > 85
BEGIN
    RAISERROR('Growing energy_log to 280GB (was tight after backup)', 0, 1) WITH NOWAIT;
    ALTER DATABASE energy MODIFY FILE (NAME = energy_log, SIZE = 280000MB);
END

SELECT df.name, df.size*8/1024 size_mb,
       FILEPROPERTY(df.name,'SpaceUsed')*8/1024 used_mb,
       CAST(100.0*FILEPROPERTY(df.name,'SpaceUsed')/NULLIF(df.size,0) AS decimal(5,1)) pct,
       d.log_reuse_wait_desc
FROM sys.database_files df
JOIN sys.databases d ON d.name = DB_NAME()
WHERE df.type_desc = N'LOG';
