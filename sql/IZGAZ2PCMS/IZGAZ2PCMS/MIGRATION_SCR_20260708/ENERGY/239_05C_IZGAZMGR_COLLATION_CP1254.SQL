-- =============================================================================
-- prodREADY_ENERGY3007 / 05c_izgazmgr_collation_cp1254.sql
-- izgazMGR: DB default + tüm user string kolonlar → CP1254
-- sqlcmd -S 172.16.1.195 -d master -I -i 05c_izgazmgr_collation_cp1254.sql
-- =============================================================================
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

USE master;
GO

PRINT '========== E3007-05c izgazMGR DB COLLATE ==========';
IF EXISTS (
    SELECT 1 FROM sys.databases
    WHERE name = N'izgazMGR' AND collation_name <> N'SQL_Latin1_General_CP1254_CI_AS'
)
BEGIN
    ALTER DATABASE izgazMGR SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    ALTER DATABASE izgazMGR COLLATE SQL_Latin1_General_CP1254_CI_AS;
    ALTER DATABASE izgazMGR SET MULTI_USER;
    PRINT 'DB COLLATE applied';
END
ELSE
    PRINT 'DB COLLATE already CP1254';

SELECT name, collation_name, user_access_desc FROM sys.databases WHERE name = N'izgazMGR';
GO

USE izgazMGR;
GO

IF OBJECT_ID(N'dbo._MIG_COLLATION_LOG', N'U') IS NULL
BEGIN
    CREATE TABLE dbo._MIG_COLLATION_LOG (
        id int IDENTITY(1,1) PRIMARY KEY,
        schema_name sysname NOT NULL,
        table_name sysname NOT NULL,
        column_name sysname NOT NULL,
        step sysname NOT NULL,
        ok bit NOT NULL,
        msg nvarchar(4000) NULL,
        logged_at datetime2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END
ELSE
    TRUNCATE TABLE dbo._MIG_COLLATION_LOG;
GO

PRINT '========== E3007-05c COLUMN COLLATE → CP1254 ==========';
PRINT CONVERT(varchar(30), SYSDATETIME(), 121);

DECLARE
    @sch sysname, @tbl sysname, @col sysname,
    @typ sysname, @maxlen int, @nullable bit,
    @typeSql nvarchar(200), @sql nvarchar(max),
    @ok int = 0, @fail int = 0;

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
SELECT s.name, t.name, c.name, ty.name, c.max_length, c.is_nullable
FROM sys.columns c
JOIN sys.tables t ON t.object_id = c.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE c.collation_name = N'SQL_Latin1_General_CP1_CI_AS'
  AND c.is_computed = 0
  AND t.is_ms_shipped = 0
ORDER BY s.name, t.name, c.column_id;

OPEN c;
FETCH NEXT FROM c INTO @sch, @tbl, @col, @typ, @maxlen, @nullable;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @typ IN (N'text', N'ntext') SET @typeSql = @typ;
    ELSE IF @typ = N'sysname' SET @typeSql = N'sysname';
    ELSE IF @maxlen = -1 SET @typeSql = @typ + N'(max)';
    ELSE IF @typ IN (N'nvarchar', N'nchar')
        SET @typeSql = @typ + N'(' + CAST(@maxlen / 2 AS nvarchar(20)) + N')';
    ELSE
        SET @typeSql = @typ + N'(' + CAST(@maxlen AS nvarchar(20)) + N')';

    SET @sql = N'ALTER TABLE ' + QUOTENAME(@sch) + N'.' + QUOTENAME(@tbl)
             + N' ALTER COLUMN ' + QUOTENAME(@col) + N' ' + @typeSql
             + N' COLLATE SQL_Latin1_General_CP1254_CI_AS'
             + CASE WHEN @nullable = 1 THEN N' NULL' ELSE N' NOT NULL' END + N';';

    BEGIN TRY
        PRINT 'ALTER ' + @sch + N'.' + @tbl + N'.' + @col;
        EXEC sp_executesql @sql;
        SET @ok += 1;
        INSERT INTO dbo._MIG_COLLATION_LOG(schema_name, table_name, column_name, step, ok, msg)
        VALUES (@sch, @tbl, @col, N'ALTER', 1, NULL);
    END TRY
    BEGIN CATCH
        SET @fail += 1;
        INSERT INTO dbo._MIG_COLLATION_LOG(schema_name, table_name, column_name, step, ok, msg)
        VALUES (@sch, @tbl, @col, N'ALTER', 0, ERROR_MESSAGE());
        PRINT 'FAIL ' + @sch + N'.' + @tbl + N'.' + @col + N': ' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM c INTO @sch, @tbl, @col, @typ, @maxlen, @nullable;
END
CLOSE c;
DEALLOCATE c;
PRINT 'Pass1 OK=' + CAST(@ok AS varchar(20)) + ' FAIL=' + CAST(@fail AS varchar(20));

-- Pass2: drop nonclustered indexes on failed cols, retry, recreate
IF OBJECT_ID(N'tempdb..#failed') IS NOT NULL DROP TABLE #failed;
SELECT schema_name, table_name, column_name
INTO #failed
FROM dbo._MIG_COLLATION_LOG WHERE step = N'ALTER' AND ok = 0;

IF OBJECT_ID(N'tempdb..#idx') IS NOT NULL DROP TABLE #idx;
SELECT DISTINCT
    s.name AS schema_name, t.name AS table_name, i.name AS index_name,
    CAST(NULL AS nvarchar(max)) AS create_sql
INTO #idx
FROM #failed f
JOIN sys.schemas s ON s.name = f.schema_name
JOIN sys.tables t ON t.name = f.table_name AND t.schema_id = s.schema_id
JOIN sys.columns c ON c.object_id = t.object_id AND c.name = f.column_name
JOIN sys.index_columns ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id
JOIN sys.indexes i ON i.object_id = ic.object_id AND i.index_id = ic.index_id
WHERE i.type > 0 AND i.is_primary_key = 0 AND i.is_unique_constraint = 0 AND i.name IS NOT NULL;

DECLARE @isysname sysname, @itbl sysname, @iidx sysname;
DECLARE @keys nvarchar(max), @incl nvarchar(max), @uniq nvarchar(20), @filter nvarchar(max), @create nvarchar(max);

DECLARE ix CURSOR LOCAL FAST_FORWARD FOR SELECT schema_name, table_name, index_name FROM #idx;
OPEN ix;
FETCH NEXT FROM ix INTO @isysname, @itbl, @iidx;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @keys = STUFF((
        SELECT N', ' + QUOTENAME(c2.name) + CASE WHEN ic2.is_descending_key = 1 THEN N' DESC' ELSE N'' END
        FROM sys.indexes i2
        JOIN sys.tables t2 ON t2.object_id = i2.object_id
        JOIN sys.schemas s2 ON s2.schema_id = t2.schema_id
        JOIN sys.index_columns ic2 ON ic2.object_id = i2.object_id AND ic2.index_id = i2.index_id
        JOIN sys.columns c2 ON c2.object_id = ic2.object_id AND c2.column_id = ic2.column_id
        WHERE s2.name = @isysname AND t2.name = @itbl AND i2.name = @iidx AND ic2.is_included_column = 0
        ORDER BY ic2.key_ordinal
        FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'');

    SELECT @incl = STUFF((
        SELECT N', ' + QUOTENAME(c2.name)
        FROM sys.indexes i2
        JOIN sys.tables t2 ON t2.object_id = i2.object_id
        JOIN sys.schemas s2 ON s2.schema_id = t2.schema_id
        JOIN sys.index_columns ic2 ON ic2.object_id = i2.object_id AND ic2.index_id = i2.index_id
        JOIN sys.columns c2 ON c2.object_id = ic2.object_id AND c2.column_id = ic2.column_id
        WHERE s2.name = @isysname AND t2.name = @itbl AND i2.name = @iidx AND ic2.is_included_column = 1
        ORDER BY ic2.index_column_id
        FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'');

    SELECT @uniq = CASE WHEN i.is_unique = 1 THEN N'UNIQUE ' ELSE N'' END, @filter = i.filter_definition
    FROM sys.indexes i
    JOIN sys.tables t ON t.object_id = i.object_id
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name = @isysname AND t.name = @itbl AND i.name = @iidx;

    SET @create = N'CREATE ' + @uniq + N'NONCLUSTERED INDEX ' + QUOTENAME(@iidx)
                + N' ON ' + QUOTENAME(@isysname) + N'.' + QUOTENAME(@itbl)
                + N' (' + ISNULL(@keys, N'') + N')'
                + CASE WHEN @incl IS NOT NULL THEN N' INCLUDE (' + @incl + N')' ELSE N'' END
                + CASE WHEN @filter IS NOT NULL THEN N' WHERE ' + @filter ELSE N'' END + N';';

    UPDATE #idx SET create_sql = @create WHERE schema_name = @isysname AND table_name = @itbl AND index_name = @iidx;

    BEGIN TRY
        SET @sql = N'DROP INDEX ' + QUOTENAME(@iidx) + N' ON ' + QUOTENAME(@isysname) + N'.' + QUOTENAME(@itbl) + N';';
        EXEC sp_executesql @sql;
        INSERT INTO dbo._MIG_COLLATION_LOG(schema_name, table_name, column_name, step, ok, msg)
        VALUES (@isysname, @itbl, @iidx, N'DROP_INDEX', 1, @create);
    END TRY
    BEGIN CATCH
        INSERT INTO dbo._MIG_COLLATION_LOG(schema_name, table_name, column_name, step, ok, msg)
        VALUES (@isysname, @itbl, @iidx, N'DROP_INDEX', 0, ERROR_MESSAGE());
    END CATCH;

    FETCH NEXT FROM ix INTO @isysname, @itbl, @iidx;
END
CLOSE ix;
DEALLOCATE ix;

SET @ok = 0; SET @fail = 0;
DECLARE c2 CURSOR LOCAL FAST_FORWARD FOR
SELECT s.name, t.name, c.name, ty.name, c.max_length, c.is_nullable
FROM sys.columns c
JOIN sys.tables t ON t.object_id = c.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE c.collation_name = N'SQL_Latin1_General_CP1_CI_AS'
  AND c.is_computed = 0 AND t.is_ms_shipped = 0
ORDER BY s.name, t.name, c.column_id;

OPEN c2;
FETCH NEXT FROM c2 INTO @sch, @tbl, @col, @typ, @maxlen, @nullable;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @typ IN (N'text', N'ntext') SET @typeSql = @typ;
    ELSE IF @typ = N'sysname' SET @typeSql = N'sysname';
    ELSE IF @maxlen = -1 SET @typeSql = @typ + N'(max)';
    ELSE IF @typ IN (N'nvarchar', N'nchar')
        SET @typeSql = @typ + N'(' + CAST(@maxlen / 2 AS nvarchar(20)) + N')';
    ELSE
        SET @typeSql = @typ + N'(' + CAST(@maxlen AS nvarchar(20)) + N')';

    SET @sql = N'ALTER TABLE ' + QUOTENAME(@sch) + N'.' + QUOTENAME(@tbl)
             + N' ALTER COLUMN ' + QUOTENAME(@col) + N' ' + @typeSql
             + N' COLLATE SQL_Latin1_General_CP1254_CI_AS'
             + CASE WHEN @nullable = 1 THEN N' NULL' ELSE N' NOT NULL' END + N';';
    BEGIN TRY
        EXEC sp_executesql @sql;
        SET @ok += 1;
        INSERT INTO dbo._MIG_COLLATION_LOG(schema_name, table_name, column_name, step, ok, msg)
        VALUES (@sch, @tbl, @col, N'ALTER2', 1, NULL);
    END TRY
    BEGIN CATCH
        SET @fail += 1;
        INSERT INTO dbo._MIG_COLLATION_LOG(schema_name, table_name, column_name, step, ok, msg)
        VALUES (@sch, @tbl, @col, N'ALTER2', 0, ERROR_MESSAGE());
    END CATCH;
    FETCH NEXT FROM c2 INTO @sch, @tbl, @col, @typ, @maxlen, @nullable;
END
CLOSE c2;
DEALLOCATE c2;
PRINT 'Pass2 OK=' + CAST(@ok AS varchar(20)) + ' FAIL=' + CAST(@fail AS varchar(20));

SET @ok = 0; SET @fail = 0;
DECLARE ix2 CURSOR LOCAL FAST_FORWARD FOR
SELECT schema_name, table_name, index_name, create_sql FROM #idx WHERE create_sql IS NOT NULL;
OPEN ix2;
FETCH NEXT FROM ix2 INTO @sch, @tbl, @col, @sql;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            JOIN sys.tables t ON t.object_id = i.object_id
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            WHERE s.name = @sch AND t.name = @tbl AND i.name = @col
        )
            EXEC sp_executesql @sql;
        SET @ok += 1;
        INSERT INTO dbo._MIG_COLLATION_LOG(schema_name, table_name, column_name, step, ok, msg)
        VALUES (@sch, @tbl, @col, N'CREATE_INDEX', 1, NULL);
    END TRY
    BEGIN CATCH
        SET @fail += 1;
        INSERT INTO dbo._MIG_COLLATION_LOG(schema_name, table_name, column_name, step, ok, msg)
        VALUES (@sch, @tbl, @col, N'CREATE_INDEX', 0, ERROR_MESSAGE());
    END CATCH;
    FETCH NEXT FROM ix2 INTO @sch, @tbl, @col, @sql;
END
CLOSE ix2;
DEALLOCATE ix2;
PRINT 'Index recreate OK=' + CAST(@ok AS varchar(20)) + ' FAIL=' + CAST(@fail AS varchar(20));

SELECT
    SUM(CASE WHEN c.collation_name = N'SQL_Latin1_General_CP1254_CI_AS' THEN 1 ELSE 0 END) AS cols_cp1254,
    SUM(CASE WHEN c.collation_name = N'SQL_Latin1_General_CP1_CI_AS' THEN 1 ELSE 0 END) AS cols_cp1
FROM sys.columns c
JOIN sys.tables t ON t.object_id = c.object_id
WHERE c.collation_name IS NOT NULL;

PRINT '--- Failures ---';
SELECT schema_name, table_name, column_name, step, LEFT(msg, 200) msg
FROM dbo._MIG_COLLATION_LOG WHERE ok = 0 ORDER BY id;

PRINT '========== E3007-05c DONE ==========';
GO
