/* =============================================================================
   prodREADY_ENERGY / 99z_MIG_DROP_ARTIFACTS.sql
   CREATE OR ALTER PROCEDURE dbo.SP_MIG_DROP_ARTIFACTS  (R24 2026-08-11)

   Aktarım bitince energy’de MIG altyapısını temizler.
   DOKUNMAZ: LS_005_01_* iş tabloları, LS_AFL_*, LS_BANK, master.

   Düşürür:
     - PROCEDURE: SP_MIG_% | SP_MIGRATE_% | SP_AGR_FRK_ALL | FN_MIG_% (scalar/TVF)
     - VIEW: MIG_% | V_MIG_% | VW_MIG_%
     - TABLE: dbo.MIG_%

   SP_MIG_DROP_ARTIFACTS kendisi en sonda kalır (tekrar çalıştırılabilir).

   EXEC dbo.SP_MIG_DROP_ARTIFACTS @DryRun = 1;   -- liste
   EXEC dbo.SP_MIG_DROP_ARTIFACTS @DryRun = 0;   -- APPLY
   ============================================================================= */
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_DROP_ARTIFACTS
    @DryRun BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET IMPLICIT_TRANSACTIONS OFF;

    DECLARE @DryRunInt INT = CAST(@DryRun AS INT);
    DECLARE @name SYSNAME;
    DECLARE @schema SYSNAME;
    DECLARE @sql NVARCHAR(500);
    DECLARE @Msg NVARCHAR(400);
    DECLARE @n INT = 0;

    RAISERROR('========== SP_MIG_DROP_ARTIFACTS DryRun=%d ==========', 0, 1, @DryRunInt) WITH NOWAIT;
    RAISERROR('YASAK: LS_005_01_* / is verisi SILINMEZ — sadece MIG_* + SP_MIG*', 0, 1) WITH NOWAIT;

    IF OBJECT_ID('tempdb..#drop_list') IS NOT NULL DROP TABLE #drop_list;
    CREATE TABLE #drop_list (
        ORD INT IDENTITY(1,1) NOT NULL,
        OBJ_TYPE VARCHAR(20) NOT NULL,
        SCHEMA_NAME SYSNAME NOT NULL,
        OBJ_NAME SYSNAME NOT NULL,
        DROP_SQL NVARCHAR(500) NOT NULL
    );

    /* ---- functions ---- */
    INSERT INTO #drop_list (OBJ_TYPE, SCHEMA_NAME, OBJ_NAME, DROP_SQL)
    SELECT 'FUNCTION', s.name, o.name,
           N'DROP FUNCTION ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name) + N';'
    FROM sys.objects o
    JOIN sys.schemas s ON s.schema_id = o.schema_id
    WHERE o.type IN ('FN', 'IF', 'TF', 'FS', 'FT')
      AND (o.name LIKE N'FN_MIG[_]%' OR o.name LIKE N'FN_MIG%')
      AND s.name = N'dbo';

    /* ---- views ---- */
    INSERT INTO #drop_list (OBJ_TYPE, SCHEMA_NAME, OBJ_NAME, DROP_SQL)
    SELECT 'VIEW', s.name, o.name,
           N'DROP VIEW ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name) + N';'
    FROM sys.views o
    JOIN sys.schemas s ON s.schema_id = o.schema_id
    WHERE s.name = N'dbo'
      AND (o.name LIKE N'MIG[_]%' OR o.name LIKE N'V_MIG[_]%' OR o.name LIKE N'VW_MIG[_]%');

    /* ---- procedures (DROP SP itself last — exclude for now) ---- */
    INSERT INTO #drop_list (OBJ_TYPE, SCHEMA_NAME, OBJ_NAME, DROP_SQL)
    SELECT 'PROCEDURE', s.name, o.name,
           N'DROP PROCEDURE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name) + N';'
    FROM sys.procedures o
    JOIN sys.schemas s ON s.schema_id = o.schema_id
    WHERE s.name = N'dbo'
      AND o.name <> N'SP_MIG_DROP_ARTIFACTS'
      AND (
            o.name LIKE N'SP_MIG[_]%'
         OR o.name LIKE N'SP_MIGRATE[_]%'
         OR o.name = N'SP_AGR_FRK_ALL'
          );

    /* ---- tables MIG_% (no LS_) ---- */
    INSERT INTO #drop_list (OBJ_TYPE, SCHEMA_NAME, OBJ_NAME, DROP_SQL)
    SELECT 'TABLE', s.name, t.name,
           N'DROP TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N';'
    FROM sys.tables t
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name = N'dbo'
      AND t.name LIKE N'MIG[_]%'
      AND t.name NOT LIKE N'LS[_]%';

    SELECT OBJ_TYPE, SCHEMA_NAME, OBJ_NAME, DROP_SQL
    FROM #drop_list
    ORDER BY
        CASE OBJ_TYPE WHEN 'PROCEDURE' THEN 1 WHEN 'FUNCTION' THEN 2 WHEN 'VIEW' THEN 3 WHEN 'TABLE' THEN 4 ELSE 9 END,
        OBJ_NAME;

    SELECT @n = COUNT(*) FROM #drop_list;
    SET @Msg = N'Aday obje n=' + CAST(@n AS NVARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    IF @DryRun = 1
    BEGIN
        RAISERROR('DRY_RUN — DROP yok. APPLY: EXEC SP_MIG_DROP_ARTIFACTS @DryRun=0', 0, 1) WITH NOWAIT;
        RETURN;
    END

    /* drop order: proc → fn → view → table */
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT DROP_SQL, OBJ_TYPE, OBJ_NAME
        FROM #drop_list
        ORDER BY
            CASE OBJ_TYPE WHEN 'PROCEDURE' THEN 1 WHEN 'FUNCTION' THEN 2 WHEN 'VIEW' THEN 3 WHEN 'TABLE' THEN 4 ELSE 9 END,
            OBJ_NAME;

    OPEN c;
    FETCH NEXT FROM c INTO @sql, @schema, @name;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC sys.sp_executesql @sql;
            SET @Msg = N'OK ' + @schema + N' ' + @name;
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END TRY
        BEGIN CATCH
            SET @Msg = N'SKIP ' + @name + N': ' + ERROR_MESSAGE();
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END CATCH
        FETCH NEXT FROM c INTO @sql, @schema, @name;
    END
    CLOSE c;
    DEALLOCATE c;

    /* remaining MIG tables retry (FK order) */
    DECLARE @round INT = 0;
    WHILE @round < 3
    BEGIN
        SET @round += 1;
        SET @n = 0;
        DECLARE c2 CURSOR LOCAL FAST_FORWARD FOR
            SELECT N'DROP TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name), t.name
            FROM sys.tables t
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            WHERE s.name = N'dbo' AND t.name LIKE N'MIG[_]%';
        OPEN c2;
        FETCH NEXT FROM c2 INTO @sql, @name;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                EXEC sys.sp_executesql @sql;
                SET @n += 1;
                SET @Msg = N'OK TABLE ' + @name;
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END TRY
            BEGIN CATCH
                SET @Msg = N'SKIP TABLE ' + @name + N': ' + ERROR_MESSAGE();
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END CATCH
            FETCH NEXT FROM c2 INTO @sql, @name;
        END
        CLOSE c2;
        DEALLOCATE c2;
        IF @n = 0 BREAK;
    END

    SELECT
        (SELECT COUNT(*) FROM sys.procedures WHERE name LIKE N'SP_MIG[_]%' AND name <> N'SP_MIG_DROP_ARTIFACTS') AS left_sp_mig,
        (SELECT COUNT(*) FROM sys.tables WHERE name LIKE N'MIG[_]%') AS left_mig_tables,
        (SELECT COUNT(*) FROM sys.views WHERE name LIKE N'MIG[_]%' OR name LIKE N'V_MIG[_]%') AS left_mig_views;

    RAISERROR('========== SP_MIG_DROP_ARTIFACTS APPLY DONE (bu SP kaldi) ==========', 0, 1) WITH NOWAIT;
END
GO
/* EXEC dbo.SP_MIG_DROP_ARTIFACTS @DryRun = 1; */
/* EXEC dbo.SP_MIG_DROP_ARTIFACTS @DryRun = 0; */
