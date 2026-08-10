-- =============================================================================
-- prodREADY_ENERGY3007 / 05b_columns_cp1254.sql
-- energy: tüm string kolonlar → SQL_Latin1_General_CP1254_CI_AS
-- Önkoşul: 05_collation_cp1254.sql (DB default zaten CP1254)
-- sqlcmd -S 172.16.1.195 -d energy -I -i 05b_columns_cp1254.sql
-- =============================================================================
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

USE energy;
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

PRINT '========== E3007-05b COLUMN COLLATE → CP1254 ==========';
PRINT CONVERT(varchar(30), SYSDATETIME(), 121);

DECLARE
    @sch sysname, @tbl sysname, @col sysname,
    @typ sysname, @maxlen int, @nullable bit, @userTypeId int,
    @typeSql nvarchar(200), @sql nvarchar(max),
    @ok int = 0, @fail int = 0, @skip int = 0;

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
SELECT
    s.name, t.name, c.name,
    ty.name, c.max_length, c.is_nullable, c.user_type_id
FROM sys.columns c
JOIN sys.tables t ON t.object_id = c.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE c.collation_name = N'SQL_Latin1_General_CP1_CI_AS'
  AND c.is_computed = 0
  AND t.is_ms_shipped = 0
ORDER BY s.name, t.name, c.column_id;

OPEN c;
FETCH NEXT FROM c INTO @sch, @tbl, @col, @typ, @maxlen, @nullable, @userTypeId;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- type clause
    IF @typ IN (N'text', N'ntext')
        SET @typeSql = @typ;
    ELSE IF @typ = N'sysname'
        SET @typeSql = N'sysname';
    ELSE IF @maxlen = -1
        SET @typeSql = @typ + N'(max)';
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
        VALUES (@sch, @tbl, @col, N'ALTER', 1, NULL);
    END TRY
    BEGIN CATCH
        SET @fail += 1;
        INSERT INTO dbo._MIG_COLLATION_LOG(schema_name, table_name, column_name, step, ok, msg)
        VALUES (@sch, @tbl, @col, N'ALTER', 0, ERROR_MESSAGE());
    END CATCH;

    FETCH NEXT FROM c INTO @sch, @tbl, @col, @typ, @maxlen, @nullable, @userTypeId;
END

CLOSE c;
DEALLOCATE c;

PRINT 'Pass1 OK=' + CAST(@ok AS varchar(20)) + ' FAIL=' + CAST(@fail AS varchar(20));

-- Pass2: drop nonclustered indexes that reference failed columns, retry ALTER, recreate later via pass3
-- Collect distinct indexes on failed columns
IF OBJECT_ID(N'tempdb..#failed') IS NOT NULL DROP TABLE #failed;
SELECT schema_name, table_name, column_name
INTO #failed
FROM dbo._MIG_COLLATION_LOG
WHERE step = N'ALTER' AND ok = 0;

IF OBJECT_ID(N'tempdb..#idx') IS NOT NULL DROP TABLE #idx;
SELECT DISTINCT
    s.name AS schema_name,
    t.name AS table_name,
    i.name AS index_name,
    i.is_unique,
    i.has_filter,
    i.filter_definition,
    i.type_desc,
    CAST(NULL AS nvarchar(max)) AS create_sql
INTO #idx
FROM #failed f
JOIN sys.schemas s ON s.name = f.schema_name
JOIN sys.tables t ON t.name = f.table_name AND t.schema_id = s.schema_id
JOIN sys.columns c ON c.object_id = t.object_id AND c.name = f.column_name
JOIN sys.index_columns ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id
JOIN sys.indexes i ON i.object_id = ic.object_id AND i.index_id = ic.index_id
WHERE i.type > 0          -- skip heap
  AND i.is_primary_key = 0
  AND i.is_unique_constraint = 0
  AND i.name IS NOT NULL;

-- Build CREATE scripts before drop (keys + includes)
DECLARE @isysname sysname, @itbl sysname, @iidx sysname;
DECLARE @keys nvarchar(max), @incl nvarchar(max), @uniq nvarchar(20), @filter nvarchar(max), @create nvarchar(max);

DECLARE ix CURSOR LOCAL FAST_FORWARD FOR
SELECT schema_name, table_name, index_name FROM #idx;
OPEN ix;
FETCH NEXT FROM ix INTO @isysname, @itbl, @iidx;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT
        @keys = STUFF((
            SELECT N', ' + QUOTENAME(c2.name) + CASE WHEN ic2.is_descending_key = 1 THEN N' DESC' ELSE N'' END
            FROM sys.indexes i2
            JOIN sys.tables t2 ON t2.object_id = i2.object_id
            JOIN sys.schemas s2 ON s2.schema_id = t2.schema_id
            JOIN sys.index_columns ic2 ON ic2.object_id = i2.object_id AND ic2.index_id = i2.index_id
            JOIN sys.columns c2 ON c2.object_id = ic2.object_id AND c2.column_id = ic2.column_id
            WHERE s2.name = @isysname AND t2.name = @itbl AND i2.name = @iidx AND ic2.is_included_column = 0
            ORDER BY ic2.key_ordinal
            FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'');

    SELECT
        @incl = STUFF((
            SELECT N', ' + QUOTENAME(c2.name)
            FROM sys.indexes i2
            JOIN sys.tables t2 ON t2.object_id = i2.object_id
            JOIN sys.schemas s2 ON s2.schema_id = t2.schema_id
            JOIN sys.index_columns ic2 ON ic2.object_id = i2.object_id AND ic2.index_id = i2.index_id
            JOIN sys.columns c2 ON c2.object_id = ic2.object_id AND c2.column_id = ic2.column_id
            WHERE s2.name = @isysname AND t2.name = @itbl AND i2.name = @iidx AND ic2.is_included_column = 1
            ORDER BY ic2.index_column_id
            FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'');

    SELECT
        @uniq = CASE WHEN i.is_unique = 1 THEN N'UNIQUE ' ELSE N'' END,
        @filter = i.filter_definition
    FROM sys.indexes i
    JOIN sys.tables t ON t.object_id = i.object_id
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name = @isysname AND t.name = @itbl AND i.name = @iidx;

    SET @create = N'CREATE ' + @uniq + N'NONCLUSTERED INDEX ' + QUOTENAME(@iidx)
                + N' ON ' + QUOTENAME(@isysname) + N'.' + QUOTENAME(@itbl)
                + N' (' + ISNULL(@keys, N'') + N')'
                + CASE WHEN @incl IS NOT NULL THEN N' INCLUDE (' + @incl + N')' ELSE N'' END
                + CASE WHEN @filter IS NOT NULL THEN N' WHERE ' + @filter ELSE N'' END + N';';

    UPDATE #idx SET create_sql = @create
    WHERE schema_name = @isysname AND table_name = @itbl AND index_name = @iidx;

    -- drop
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

-- Also drop CHECK / DEFAULT on failed cols if present, and unique/PK constraints separately
-- Retry ALTER for remaining CP1 columns (same list)
SET @ok = 0; SET @fail = 0;

DECLARE c2 CURSOR LOCAL FAST_FORWARD FOR
SELECT
    s.name, t.name, c.name,
    ty.name, c.max_length, c.is_nullable
FROM sys.columns c
JOIN sys.tables t ON t.object_id = c.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE c.collation_name = N'SQL_Latin1_General_CP1_CI_AS'
  AND c.is_computed = 0
  AND t.is_ms_shipped = 0
ORDER BY s.name, t.name, c.column_id;

OPEN c2;
FETCH NEXT FROM c2 INTO @sch, @tbl, @col, @typ, @maxlen, @nullable;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @typ IN (N'text', N'ntext')
        SET @typeSql = @typ;
    ELSE IF @typ = N'sysname'
        SET @typeSql = N'sysname';
    ELSE IF @maxlen = -1
        SET @typeSql = @typ + N'(max)';
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

-- Recreate dropped indexes
SET @ok = 0; SET @fail = 0;
DECLARE ix2 CURSOR LOCAL FAST_FORWARD FOR
SELECT schema_name, table_name, index_name, create_sql FROM #idx WHERE create_sql IS NOT NULL;
OPEN ix2;
FETCH NEXT FROM ix2 INTO @sch, @tbl, @col, @sql; -- reuse: @col=index_name
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

-- Pass3: PK/UQ blockers (known leftovers) — drop, alter, recreate
PRINT '========== Pass3 PK/UQ leftovers ==========';
BEGIN TRY
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.LS_005_01_hhd_loc_old_inv') AND name=N'loc_id' AND collation_name=N'SQL_Latin1_General_CP1_CI_AS')
    BEGIN
        ALTER TABLE dbo.LS_005_01_hhd_loc_old_inv DROP CONSTRAINT PK_LS_005_01_hhd_loc_old_inv;
        ALTER TABLE dbo.LS_005_01_hhd_loc_old_inv ALTER COLUMN loc_id varchar(20) COLLATE SQL_Latin1_General_CP1254_CI_AS NOT NULL;
        ALTER TABLE dbo.LS_005_01_hhd_loc_old_inv ALTER COLUMN inv_id varchar(16) COLLATE SQL_Latin1_General_CP1254_CI_AS NOT NULL;
        ALTER TABLE dbo.LS_005_01_hhd_loc_old_inv ADD CONSTRAINT PK_LS_005_01_hhd_loc_old_inv PRIMARY KEY CLUSTERED (loc_region, read_date, loc_id, inv_id);
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.LS_005_01_hhd_params') AND name=N'param_type' AND collation_name=N'SQL_Latin1_General_CP1_CI_AS')
    BEGIN
        ALTER TABLE dbo.LS_005_01_hhd_params DROP CONSTRAINT PK_LS_005_01_hhd_params;
        ALTER TABLE dbo.LS_005_01_hhd_params ALTER COLUMN param_type varchar(20) COLLATE SQL_Latin1_General_CP1254_CI_AS NOT NULL;
        ALTER TABLE dbo.LS_005_01_hhd_params ADD CONSTRAINT PK_LS_005_01_hhd_params PRIMARY KEY CLUSTERED (param_type, param_id);
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.LS_005_01_PAYPLAN') AND name=N'CODE' AND collation_name=N'SQL_Latin1_General_CP1_CI_AS')
    BEGIN
        ALTER TABLE dbo.LS_005_01_PAYPLAN DROP CONSTRAINT IX_LS_005_01_PAYPLAN;
        ALTER TABLE dbo.LS_005_01_PAYPLAN ALTER COLUMN CODE nvarchar(50) COLLATE SQL_Latin1_General_CP1254_CI_AS NULL;
        ALTER TABLE dbo.LS_005_01_PAYPLAN ADD CONSTRAINT IX_LS_005_01_PAYPLAN UNIQUE NONCLUSTERED (CODE);
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.LS_005_RMS') AND name=N'CODE' AND collation_name=N'SQL_Latin1_General_CP1_CI_AS')
    BEGIN
        DECLARE @uq_rms sysname = (SELECT name FROM sys.key_constraints WHERE parent_object_id=OBJECT_ID(N'dbo.LS_005_RMS') AND type=N'UQ' AND name LIKE N'UQ__LS_005_R%');
        IF @uq_rms IS NOT NULL EXEC(N'ALTER TABLE dbo.LS_005_RMS DROP CONSTRAINT ' + QUOTENAME(@uq_rms));
        ALTER TABLE dbo.LS_005_RMS ALTER COLUMN CODE nvarchar(20) COLLATE SQL_Latin1_General_CP1254_CI_AS NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE parent_object_id=OBJECT_ID(N'dbo.LS_005_RMS') AND type=N'UQ')
            ALTER TABLE dbo.LS_005_RMS ADD CONSTRAINT UQ_LS_005_RMS_CODE UNIQUE NONCLUSTERED (CODE);
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.LS_005_SUBROUTE') AND name=N'NAME_' AND collation_name=N'SQL_Latin1_General_CP1_CI_AS')
    BEGIN
        ALTER TABLE dbo.LS_005_SUBROUTE DROP CONSTRAINT IX_LS_005_SUBROUTE;
        ALTER TABLE dbo.LS_005_SUBROUTE ALTER COLUMN NAME_ nvarchar(50) COLLATE SQL_Latin1_General_CP1254_CI_AS NULL;
        ALTER TABLE dbo.LS_005_SUBROUTE ADD CONSTRAINT IX_LS_005_SUBROUTE UNIQUE NONCLUSTERED (NAME_);
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.LS_LANGS') AND name=N'LANGCODE' AND collation_name=N'SQL_Latin1_General_CP1_CI_AS')
    BEGIN
        ALTER TABLE dbo.LS_LANGS DROP CONSTRAINT PK_LS_LANGS;
        ALTER TABLE dbo.LS_LANGS ALTER COLUMN LANGCODE char(3) COLLATE SQL_Latin1_General_CP1254_CI_AS NOT NULL;
        ALTER TABLE dbo.LS_LANGS ADD CONSTRAINT PK_LS_LANGS PRIMARY KEY CLUSTERED (LANGCODE);
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.LS_PROJ_STAT') AND name=N'STYPE' AND collation_name=N'SQL_Latin1_General_CP1_CI_AS')
    BEGIN
        ALTER TABLE dbo.LS_PROJ_STAT DROP CONSTRAINT PK_LS_PROJ_STAT;
        ALTER TABLE dbo.LS_PROJ_STAT ALTER COLUMN STYPE nvarchar(50) COLLATE SQL_Latin1_General_CP1254_CI_AS NOT NULL;
        ALTER TABLE dbo.LS_PROJ_STAT ADD CONSTRAINT PK_LS_PROJ_STAT PRIMARY KEY CLUSTERED (LREF, STYPE);
    END
    PRINT 'Pass3 OK';
END TRY
BEGIN CATCH
    PRINT 'Pass3 ERROR: ' + ERROR_MESSAGE();
END CATCH;

-- Refresh views that still advertise CP1
DECLARE @vs sysname, @vv sysname, @vsql nvarchar(400);
DECLARE cv CURSOR LOCAL FAST_FORWARD FOR
SELECT DISTINCT s.name, v.name
FROM sys.columns c
JOIN sys.views v ON v.object_id = c.object_id
JOIN sys.schemas s ON s.schema_id = v.schema_id
WHERE c.collation_name = N'SQL_Latin1_General_CP1_CI_AS';
OPEN cv;
FETCH NEXT FROM cv INTO @vs, @vv;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SET @vsql = N'EXEC sp_refreshview N''' + @vs + N'.' + @vv + N'''';
        EXEC sp_executesql @vsql;
    END TRY
    BEGIN CATCH
        PRINT 'sp_refreshview skip ' + @vs + N'.' + @vv + N': ' + ERROR_MESSAGE();
    END CATCH;
    FETCH NEXT FROM cv INTO @vs, @vv;
END
CLOSE cv;
DEALLOCATE cv;

SELECT
    SUM(CASE WHEN c.collation_name = N'SQL_Latin1_General_CP1254_CI_AS' THEN 1 ELSE 0 END) AS cols_cp1254_usertable,
    SUM(CASE WHEN c.collation_name = N'SQL_Latin1_General_CP1_CI_AS' THEN 1 ELSE 0 END) AS cols_cp1_usertable
FROM sys.columns c
JOIN sys.tables t ON t.object_id = c.object_id
WHERE c.collation_name IS NOT NULL;

PRINT '--- Remaining failures / leftover CP1 (non user-table OK: INTERNAL) ---';
SELECT schema_name, table_name, column_name, step, LEFT(msg, 200) AS msg
FROM dbo._MIG_COLLATION_LOG
WHERE ok = 0 AND step IN (N'ALTER2', N'CREATE_INDEX', N'DROP_INDEX')
ORDER BY id;

SELECT o.type_desc, COUNT(*) AS cp1_left
FROM sys.columns c
JOIN sys.objects o ON o.object_id = c.object_id
WHERE c.collation_name = N'SQL_Latin1_General_CP1_CI_AS'
GROUP BY o.type_desc;

PRINT '========== E3007-05b DONE ==========';
GO
