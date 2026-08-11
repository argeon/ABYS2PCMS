/* =============================================================================
   prodREADY_ENERGY / 26b_597_NCIX_DISABLE.sql
   CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_NCIX_DISABLE  (R22 2026-08-11)

   597 FULL oncesi INV+PT NCIX OFF (= eski 20b dosyalari).
   EXEC dbo.SP_MIG_597_NCIX_DISABLE @DEBUG=1;
   ============================================================================= */
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_NCIX_DISABLE
    @DEBUG BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET IMPLICIT_TRANSACTIONS OFF;

    IF EXISTS (
        SELECT 1 FROM sys.dm_exec_requests r
        CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
        WHERE r.session_id <> @@SPID AND t.text LIKE N'%SP_MIG_597%'
    )
    BEGIN
        RAISERROR('597 RUNNING — NCIX DISABLE iptal', 16, 1);
        RETURN;
    END

    RAISERROR('========== SP_MIG_597_NCIX_DISABLE INV+PT ==========', 0, 1) WITH NOWAIT;

    /* INV */
    IF OBJECT_ID(N'dbo.SP_MIG_INVOICE_PREPARE_LOAD', N'P') IS NOT NULL
        EXEC dbo.SP_MIG_INVOICE_PREPARE_LOAD @DEBUG = @DEBUG;
    ELSE
    BEGIN
        DECLARE @sqlInv NVARCHAR(MAX) = N'';
        SELECT @sqlInv = @sqlInv + N'ALTER INDEX ' + QUOTENAME(i.name)
            + N' ON dbo.LS_005_01_INVOICE DISABLE;' + CHAR(10)
        FROM sys.indexes i
        WHERE i.object_id = OBJECT_ID(N'dbo.LS_005_01_INVOICE')
          AND i.type_desc = N'NONCLUSTERED'
          AND i.is_disabled = 0
          AND i.name IS NOT NULL;
        IF @sqlInv IS NOT NULL AND @sqlInv <> N''
            EXEC sys.sp_executesql @sqlInv;
    END

    /* PT — PREPARE varsa kullan; yoksa raw DISABLE */
    IF OBJECT_ID(N'dbo.SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD', N'P') IS NOT NULL
        EXEC dbo.SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD @DEBUG = @DEBUG;
    ELSE
    BEGIN
        DECLARE @sqlPt NVARCHAR(MAX) = N'';
        SELECT @sqlPt = @sqlPt + N'ALTER INDEX ' + QUOTENAME(i.name)
            + N' ON dbo.LS_005_01_PAYTRANS DISABLE;' + CHAR(10)
        FROM sys.indexes i
        WHERE i.object_id = OBJECT_ID(N'dbo.LS_005_01_PAYTRANS')
          AND i.index_id > 1
          AND i.type > 0
          AND i.is_disabled = 0;
        IF @sqlPt IS NOT NULL AND @sqlPt <> N''
            EXEC sys.sp_executesql @sqlPt;
    END

    SELECT
        SUM(CASE WHEN object_id = OBJECT_ID(N'dbo.LS_005_01_INVOICE') AND is_disabled = 1 THEN 1 ELSE 0 END) AS inv_ncix_disabled,
        SUM(CASE WHEN object_id = OBJECT_ID(N'dbo.LS_005_01_PAYTRANS') AND is_disabled = 1 THEN 1 ELSE 0 END) AS pt_ncix_disabled
    FROM sys.indexes
    WHERE index_id > 1 AND type > 0
      AND object_id IN (OBJECT_ID(N'dbo.LS_005_01_INVOICE'), OBJECT_ID(N'dbo.LS_005_01_PAYTRANS'));

    RAISERROR('SP_MIG_597_NCIX_DISABLE DONE — simdi SP_MIG_597_ALL', 0, 1) WITH NOWAIT;
END
GO
/* EXEC dbo.SP_MIG_597_NCIX_DISABLE @DEBUG=1; */
