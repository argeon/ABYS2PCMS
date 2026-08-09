/* ============================================================
   FILE : prodREADY_ENERGY3007/SP_MIG_COMPARE_LINKED_DB.sql
   Amac : Iki SQL Server (yerel + linked) ayni yapidaki DB'lerde
          tablo / satir / alan karsilastirma
   Onkosul: linked server (varsayilan LS_196)
   Ornek:
     EXEC dbo.SP_MIG_COMPARE_LINKED_DB;
     EXEC dbo.SP_MIG_COMPARE_LINKED_DB @LocalDB=N'izgazMGR', @RemoteDB=N'izgazMGR';
     EXEC dbo.SP_MIG_COMPARE_LINKED_DB @OnlyDiff=0;  -- Ayni dahil
   ============================================================ */
USE energy;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_COMPARE_LINKED_DB
    @LocalDB      SYSNAME = N'energy',
    @RemoteDB     SYSNAME = N'energy',
    @LinkedServer SYSNAME = N'LS_196',
    @OnlyDiff     BIT     = 1          -- 1=sadece fark/tek tarafli; 0=hepsi
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF DB_ID(@LocalDB) IS NULL
    BEGIN
        RAISERROR(N'Yerel veritabani bulunamadi: %s', 16, 1, @LocalDB);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @LinkedServer AND is_linked = 1)
    BEGIN
        RAISERROR(N'Linked server yok: %s', 16, 1, @LinkedServer);
        RETURN;
    END;

    IF OBJECT_ID('tempdb..#Local')  IS NOT NULL DROP TABLE #Local;
    IF OBJECT_ID('tempdb..#Remote') IS NOT NULL DROP TABLE #Remote;
    IF OBJECT_ID('tempdb..#Cmp')    IS NOT NULL DROP TABLE #Cmp;

    CREATE TABLE #Local (
        SchemaName   SYSNAME,
        TableName    SYSNAME,
        RowCounts    BIGINT,
        TotalSpaceMB DECIMAL(18,2),
        UsedSpaceMB  DECIMAL(18,2),
        DataSpaceMB  DECIMAL(18,2),
        IndexSpaceMB DECIMAL(18,2),
        UnusedSpaceMB DECIMAL(18,2)
    );

    CREATE TABLE #Remote (
        SchemaName   SYSNAME,
        TableName    SYSNAME,
        RowCounts    BIGINT,
        TotalSpaceMB DECIMAL(18,2),
        UsedSpaceMB  DECIMAL(18,2),
        DataSpaceMB  DECIMAL(18,2),
        IndexSpaceMB DECIMAL(18,2),
        UnusedSpaceMB DECIMAL(18,2)
    );

    DECLARE @sqlLocal NVARCHAR(MAX) = N'
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    SUM(CASE WHEN i.index_id IN (0, 1) THEN p.rows ELSE 0 END) AS RowCounts,
    CAST(ROUND((SUM(a.total_pages) * 8) / 1024.0, 2) AS DECIMAL(18,2)) AS TotalSpaceMB,
    CAST(ROUND((SUM(a.used_pages) * 8) / 1024.0, 2) AS DECIMAL(18,2)) AS UsedSpaceMB,
    CAST(ROUND((SUM(CASE WHEN a.type = 1 THEN a.data_pages ELSE 0 END) * 8) / 1024.0, 2) AS DECIMAL(18,2)) AS DataSpaceMB,
    CAST(ROUND(((SUM(a.used_pages) - SUM(CASE WHEN a.type = 1 THEN a.data_pages ELSE 0 END)) * 8) / 1024.0, 2) AS DECIMAL(18,2)) AS IndexSpaceMB,
    CAST(ROUND(((SUM(a.total_pages) - SUM(a.used_pages)) * 8) / 1024.0, 2) AS DECIMAL(18,2)) AS UnusedSpaceMB
FROM ' + QUOTENAME(@LocalDB) + N'.sys.tables t
INNER JOIN ' + QUOTENAME(@LocalDB) + N'.sys.indexes i
    ON t.object_id = i.object_id
INNER JOIN ' + QUOTENAME(@LocalDB) + N'.sys.partitions p
    ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN ' + QUOTENAME(@LocalDB) + N'.sys.allocation_units a
    ON p.partition_id = a.container_id
INNER JOIN ' + QUOTENAME(@LocalDB) + N'.sys.schemas s
    ON t.schema_id = s.schema_id
WHERE t.is_ms_shipped = 0
  AND i.object_id > 255
GROUP BY s.name, t.name;';

    INSERT INTO #Local
    EXEC sys.sp_executesql @sqlLocal;

    DECLARE @remoteQuery NVARCHAR(MAX) = N'
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    SUM(CASE WHEN i.index_id IN (0, 1) THEN p.rows ELSE 0 END) AS RowCounts,
    CAST(ROUND((SUM(a.total_pages) * 8) / 1024.0, 2) AS DECIMAL(18,2)) AS TotalSpaceMB,
    CAST(ROUND((SUM(a.used_pages) * 8) / 1024.0, 2) AS DECIMAL(18,2)) AS UsedSpaceMB,
    CAST(ROUND((SUM(CASE WHEN a.type = 1 THEN a.data_pages ELSE 0 END) * 8) / 1024.0, 2) AS DECIMAL(18,2)) AS DataSpaceMB,
    CAST(ROUND(((SUM(a.used_pages) - SUM(CASE WHEN a.type = 1 THEN a.data_pages ELSE 0 END)) * 8) / 1024.0, 2) AS DECIMAL(18,2)) AS IndexSpaceMB,
    CAST(ROUND(((SUM(a.total_pages) - SUM(a.used_pages)) * 8) / 1024.0, 2) AS DECIMAL(18,2)) AS UnusedSpaceMB
FROM ' + QUOTENAME(@RemoteDB) + N'.sys.tables t
INNER JOIN ' + QUOTENAME(@RemoteDB) + N'.sys.indexes i
    ON t.object_id = i.object_id
INNER JOIN ' + QUOTENAME(@RemoteDB) + N'.sys.partitions p
    ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN ' + QUOTENAME(@RemoteDB) + N'.sys.allocation_units a
    ON p.partition_id = a.container_id
INNER JOIN ' + QUOTENAME(@RemoteDB) + N'.sys.schemas s
    ON t.schema_id = s.schema_id
WHERE t.is_ms_shipped = 0
  AND i.object_id > 255
GROUP BY s.name, t.name';

    DECLARE @openQuerySql NVARCHAR(MAX) = N'
INSERT INTO #Remote
SELECT * FROM OPENQUERY(' + QUOTENAME(@LinkedServer) + N', '''
        + REPLACE(@remoteQuery, '''', '''''') + N''');';

    EXEC sys.sp_executesql @openQuerySql;

    SELECT
        COALESCE(l.SchemaName, r.SchemaName) AS SchemaName,
        COALESCE(l.TableName, r.TableName)   AS TableName,
        l.RowCounts AS Local_RowCount,
        r.RowCounts AS Remote_RowCount,
        ISNULL(l.RowCounts, 0) - ISNULL(r.RowCounts, 0) AS RowCount_Fark,
        l.TotalSpaceMB AS Local_TotalSpaceMB,
        r.TotalSpaceMB AS Remote_TotalSpaceMB,
        ISNULL(l.TotalSpaceMB, 0) - ISNULL(r.TotalSpaceMB, 0) AS SpaceMB_Fark,
        l.UsedSpaceMB  AS Local_UsedSpaceMB,
        r.UsedSpaceMB  AS Remote_UsedSpaceMB,
        l.DataSpaceMB  AS Local_DataSpaceMB,
        r.DataSpaceMB  AS Remote_DataSpaceMB,
        l.IndexSpaceMB AS Local_IndexSpaceMB,
        r.IndexSpaceMB AS Remote_IndexSpaceMB,
        CASE
            WHEN l.TableName IS NULL THEN N'Sadece remote''da var'
            WHEN r.TableName IS NULL THEN N'Sadece local''de var'
            WHEN ISNULL(l.RowCounts, 0) <> ISNULL(r.RowCounts, 0)
              OR ISNULL(l.TotalSpaceMB, 0) <> ISNULL(r.TotalSpaceMB, 0) THEN N'FARKLI'
            ELSE N'Ayni'
        END AS Durum
    INTO #Cmp
    FROM #Local l
    FULL OUTER JOIN #Remote r
        ON l.SchemaName = r.SchemaName
       AND l.TableName = r.TableName;

    /* RS1: ozet */
    SELECT
        @@SERVERNAME AS LocalServer,
        @LinkedServer AS LinkedServer,
        @LocalDB AS LocalDB,
        @RemoteDB AS RemoteDB,
        (SELECT COUNT(*) FROM #Local) AS Local_TableCount,
        (SELECT COUNT(*) FROM #Remote) AS Remote_TableCount,
        (SELECT SUM(RowCounts) FROM #Local) AS Local_TotalRows,
        (SELECT SUM(RowCounts) FROM #Remote) AS Remote_TotalRows,
        (SELECT SUM(TotalSpaceMB) FROM #Local) AS Local_TotalMB,
        (SELECT SUM(TotalSpaceMB) FROM #Remote) AS Remote_TotalMB;

    /* RS2: durum dagilimi */
    SELECT Durum, COUNT(*) AS Adet
    FROM #Cmp
    GROUP BY Durum
    ORDER BY Adet DESC;

    /* RS3: detay */
    SELECT
        SchemaName,
        TableName,
        Local_RowCount,
        Remote_RowCount,
        RowCount_Fark,
        Local_TotalSpaceMB,
        Remote_TotalSpaceMB,
        SpaceMB_Fark,
        Local_UsedSpaceMB,
        Remote_UsedSpaceMB,
        Local_DataSpaceMB,
        Remote_DataSpaceMB,
        Local_IndexSpaceMB,
        Remote_IndexSpaceMB,
        Durum
    FROM #Cmp
    WHERE @OnlyDiff = 0
       OR Durum <> N'Ayni'
    ORDER BY
        CASE
            WHEN Durum LIKE N'Sadece%' THEN 0
            WHEN Durum = N'FARKLI' THEN 1
            ELSE 2
        END,
        ABS(RowCount_Fark) DESC,
        SchemaName,
        TableName;

    DROP TABLE #Local;
    DROP TABLE #Remote;
    DROP TABLE #Cmp;
END;
GO
