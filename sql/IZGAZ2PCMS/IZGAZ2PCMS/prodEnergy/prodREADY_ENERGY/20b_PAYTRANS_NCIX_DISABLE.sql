/*
  20b_PAYTRANS_NCIX_DISABLE.sql
  ---------------------------------------------------------------
  597 PAY hint INSERT öncesi: LS_005_01_PAYTRANS NCIX DISABLE (PK kalır).
  Sonra: SP_MIG_597_ALL ... @BatchSize=250000
  Bitince: 20c_PAYTRANS_NCIX_REBUILD.sql

  Dış TRAN YASAK. 597 çalışırken çalıştırma.
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
    RAISERROR('597 RUNNING — NCIX DISABLE iptal', 16, 1);
    RETURN;
END
GO

RAISERROR('========== 20b PAYTRANS NCIX DISABLE ==========', 0, 1) WITH NOWAIT;

DECLARE @sql nvarchar(max) = N'';
SELECT @sql = @sql + N'ALTER INDEX ' + QUOTENAME(i.name)
    + N' ON dbo.LS_005_01_PAYTRANS DISABLE;' + CHAR(10)
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
  AND i.index_id > 1          /* PK/clustered degil */
  AND i.type > 0
  AND i.is_disabled = 0;

IF @sql IS NULL OR @sql = N''
    RAISERROR('Disable edilecek NCIX yok (hepsi zaten disabled?)', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    PRINT @sql;
    EXEC sp_executesql @sql;
END

SELECT i.name, i.is_disabled
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS') AND i.index_id > 0
ORDER BY i.index_id;

RAISERROR('========== 20b DONE — simdi SP_MIG_597_ALL @CLEAN=0 @BatchSize=250000 ==========', 0, 1) WITH NOWAIT;
GO
