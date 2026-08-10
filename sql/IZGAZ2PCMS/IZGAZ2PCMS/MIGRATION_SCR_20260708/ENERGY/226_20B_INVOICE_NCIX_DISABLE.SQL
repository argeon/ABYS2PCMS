/*
  20b_INVOICE_NCIX_DISABLE.sql
  ---------------------------------------------------------------
  597 TAH_INV INSERT öncesi: LS_005_01_INVOICE NCIX DISABLE (PK kalır).
  15 NC index açıkken 66M IDENTITY_INSERT çok yavaş.

  Tercihen: EXEC dbo.SP_MIG_INVOICE_PREPARE_LOAD @DEBUG=1
  (FK drop + NC disable — 572 POST ile geri)

  Sonra: SP_MIG_597_ALL @CLEAN=0 @BatchSize=250000
  TAH bitince / ALL bitince: EXEC dbo.SP_MIG_INVOICE_POST_INDEXES (572)
  PAY için ayrıca 20b_PAYTRANS_NCIX_DISABLE.sql

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
    RAISERROR('597 RUNNING — INVOICE NCIX DISABLE iptal (once KILL)', 16, 1);
    RETURN;
END
GO

RAISERROR('========== 20b INVOICE NCIX DISABLE ==========', 0, 1) WITH NOWAIT;

IF OBJECT_ID('dbo.SP_MIG_INVOICE_PREPARE_LOAD', 'P') IS NOT NULL
BEGIN
    EXEC dbo.SP_MIG_INVOICE_PREPARE_LOAD @DEBUG = 1;
END
ELSE
BEGIN
    DECLARE @sql nvarchar(max) = N'';
    SELECT @sql = @sql + N'ALTER INDEX ' + QUOTENAME(i.name)
        + N' ON dbo.LS_005_01_INVOICE DISABLE;' + CHAR(10)
    FROM sys.indexes i
    WHERE i.object_id = OBJECT_ID('dbo.LS_005_01_INVOICE')
      AND i.type_desc = N'NONCLUSTERED'
      AND i.is_disabled = 0
      AND i.name IS NOT NULL;

    IF @sql IS NULL OR @sql = N''
        RAISERROR('Disable edilecek NCIX yok', 0, 1) WITH NOWAIT;
    ELSE
    BEGIN
        PRINT @sql;
        EXEC sp_executesql @sql;
    END
END

SELECT i.name, i.is_disabled
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('dbo.LS_005_01_INVOICE') AND i.index_id > 0
ORDER BY i.index_id;

RAISERROR('========== 20b INVOICE DONE — 597 ALL @CLEAN=0; sonra 572 POST ==========', 0, 1) WITH NOWAIT;
GO
