/* =============================================================================
   prodREADY_ENERGY / 26c_597_NCIX_REBUILD.sql
   CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_NCIX_REBUILD  (R22 2026-08-11)

   597 GATE + bad_map=0 sonrasi: INV POST (572) + PT NCIX REBUILD (=20c).
   EXEC dbo.SP_MIG_597_NCIX_REBUILD @DEBUG=1;
   ============================================================================= */
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_NCIX_REBUILD
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
        RAISERROR('597 RUNNING — NCIX REBUILD iptal', 16, 1);
        RETURN;
    END

    RAISERROR('========== SP_MIG_597_NCIX_REBUILD INV+PT ==========', 0, 1) WITH NOWAIT;

    /* INV — 572 */
    IF OBJECT_ID(N'dbo.SP_MIG_INVOICE_POST_INDEXES', N'P') IS NOT NULL
        EXEC dbo.SP_MIG_INVOICE_POST_INDEXES @DEBUG = @DEBUG;
    ELSE
        RAISERROR('WARN: SP_MIG_INVOICE_POST_INDEXES yok — INV NCIX elle rebuild', 0, 1) WITH NOWAIT;

    /* PT — drop bad UX + REBUILD disabled */
    IF EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.LS_005_01_PAYTRANS')
          AND name = N'UX_LS005_PAYTRANS_ABYS_ID'
    )
    BEGIN
        RAISERROR('DROP UX_LS005_PAYTRANS_ABYS_ID (not unique after mig)', 0, 1) WITH NOWAIT;
        DROP INDEX UX_LS005_PAYTRANS_ABYS_ID ON dbo.LS_005_01_PAYTRANS;
    END

    DECLARE @name SYSNAME, @sql NVARCHAR(400), @msg NVARCHAR(400);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT i.name
        FROM sys.indexes i
        WHERE i.object_id = OBJECT_ID(N'dbo.LS_005_01_PAYTRANS')
          AND i.index_id > 1
          AND i.is_disabled = 1
        ORDER BY i.name;

    OPEN c;
    FETCH NEXT FROM c INTO @name;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = N'ALTER INDEX ' + QUOTENAME(@name)
                 + N' ON dbo.LS_005_01_PAYTRANS REBUILD WITH (MAXDOP = 8, SORT_IN_TEMPDB = ON);';
        IF @DEBUG = 1
            RAISERROR('REBUILD %s ...', 0, 1, @name) WITH NOWAIT;
        BEGIN TRY
            EXEC sys.sp_executesql @sql;
        END TRY
        BEGIN CATCH
            SET @msg = N'SKIP ' + @name + N': ' + ERROR_MESSAGE();
            RAISERROR('%s', 0, 1, @msg) WITH NOWAIT;
        END CATCH
        FETCH NEXT FROM c INTO @name;
    END
    CLOSE c;
    DEALLOCATE c;

    SELECT
        SUM(CASE WHEN object_id = OBJECT_ID(N'dbo.LS_005_01_INVOICE') AND is_disabled = 1 THEN 1 ELSE 0 END) AS inv_ncix_disabled,
        SUM(CASE WHEN object_id = OBJECT_ID(N'dbo.LS_005_01_PAYTRANS') AND is_disabled = 1 THEN 1 ELSE 0 END) AS pt_ncix_disabled
    FROM sys.indexes
    WHERE index_id > 1 AND type > 0
      AND object_id IN (OBJECT_ID(N'dbo.LS_005_01_INVOICE'), OBJECT_ID(N'dbo.LS_005_01_PAYTRANS'));

    RAISERROR('SP_MIG_597_NCIX_REBUILD DONE', 0, 1) WITH NOWAIT;
END
GO
/* EXEC dbo.SP_MIG_597_NCIX_REBUILD @DEBUG=1; */
