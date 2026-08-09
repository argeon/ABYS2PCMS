/*
  20c_PAYTRANS_NCIX_REBUILD.sql
  ---------------------------------------------------------------
  597 PAY INSERT + WIRE/GATE bittikten sonra NCIX REBUILD.
  597 çalışırken çalıştırma.
*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET IMPLICIT_TRANSACTIONS OFF;

USE energy;
GO

IF EXISTS (
    SELECT 1 FROM sys.dm_exec_requests r
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.session_id <> @@SPID AND t.text LIKE N'%SP_MIG_597%'
)
BEGIN
    RAISERROR('597 RUNNING — NCIX REBUILD iptal', 16, 1);
    RETURN;
END
GO

RAISERROR('========== 20c PAYTRANS NCIX REBUILD ==========', 0, 1) WITH NOWAIT;

/* UX_LS005_PAYTRANS_ABYS_ID: ABYS_ID duplicate (~444k grup) → REBUILD imkansiz.
   Non-unique IX_MIG_PT_ABYS_ID zaten var. Unique'i DROP et (disable birakma). */
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
      AND name = N'UX_LS005_PAYTRANS_ABYS_ID'
)
BEGIN
    RAISERROR('DROP UX_LS005_PAYTRANS_ABYS_ID (ABYS_ID not unique after mig)', 0, 1) WITH NOWAIT;
    DROP INDEX UX_LS005_PAYTRANS_ABYS_ID ON dbo.LS_005_01_PAYTRANS;
END

DECLARE @name sysname, @sql nvarchar(400), @msg nvarchar(400);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT i.name
    FROM sys.indexes i
    WHERE i.object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
      AND i.index_id > 1
      AND i.is_disabled = 1
    ORDER BY i.name;

OPEN c;
FETCH NEXT FROM c INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'ALTER INDEX ' + QUOTENAME(@name)
             + N' ON dbo.LS_005_01_PAYTRANS REBUILD WITH (MAXDOP = 8, SORT_IN_TEMPDB = ON);';
    RAISERROR('REBUILD %s ...', 0, 1, @name) WITH NOWAIT;
    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        SET @msg = N'SKIP ' + @name + N': ' + ERROR_MESSAGE();
        RAISERROR('%s', 0, 1, @msg) WITH NOWAIT;
    END CATCH
    FETCH NEXT FROM c INTO @name;
END
CLOSE c;
DEALLOCATE c;

SELECT i.name, i.is_disabled
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS') AND i.index_id > 0
ORDER BY i.index_id;

RAISERROR('========== 20c DONE ==========', 0, 1) WITH NOWAIT;
GO
