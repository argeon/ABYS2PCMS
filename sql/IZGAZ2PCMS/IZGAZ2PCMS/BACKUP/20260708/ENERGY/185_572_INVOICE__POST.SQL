/* ============================================================
   SCRIPT_ID : INVOICE_POST
   SCRIPT_NO : 572
   FILE      : 572_INVOICE__post.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LS_005_01_INVOICE aktarim SONRASI index kurulumu
-- Wire / FK remap YOK — sadece NC index CREATE + REBUILD
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVOICE_POST_INDEXES
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_INVOICE', 'U') IS NULL
    BEGIN
        RAISERROR('energy.dbo.LS_005_01_INVOICE bulunamadi.', 16, 1);
        RETURN;
    END

    DECLARE @Sql NVARCHAR(MAX) = N'';
    DECLARE @Msg NVARCHAR(500);
    DECLARE @RowCnt BIGINT;

    IF @DEBUG = 1
    BEGIN
        SELECT @RowCnt = SUM(p.rows)
        FROM sys.partitions p
        WHERE p.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
          AND p.index_id IN (0, 1);
        SET @Msg = N'INVOICE post indexes | ~' + CAST(ISNULL(@RowCnt, 0) AS VARCHAR(20)) + N' satir';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    -- 1) Disabled NC indexleri rebuild
    SET @Sql = N'';
    SELECT @Sql = @Sql + N'
ALTER INDEX ' + QUOTENAME(i.name) + N' ON energy.dbo.LS_005_01_INVOICE REBUILD WITH (MAXDOP = 24, SORT_IN_TEMPDB = ON);'
    FROM sys.indexes i
    WHERE i.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
      AND i.type_desc = 'NONCLUSTERED'
      AND i.is_disabled = 1
      AND i.name IS NOT NULL;

    IF LEN(@Sql) > 0
    BEGIN
        IF @DEBUG = 1
            RAISERROR('Disabled NC index REBUILD...', 0, 1) WITH NOWAIT;
        EXEC sp_executesql @Sql;
    END

    -- 2) ABYS_ID unique (filtered)
    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
          AND name = 'UX_LS005_INVOICE_ABYS_ID'
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE UX_LS005_INVOICE_ABYS_ID...', 0, 1) WITH NOWAIT;

        CREATE UNIQUE NONCLUSTERED INDEX UX_LS005_INVOICE_ABYS_ID
            ON energy.dbo.LS_005_01_INVOICE (ABYS_ID)
            WHERE ABYS_ID IS NOT NULL
            WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
    END
    ELSE IF EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
          AND name = 'UX_LS005_INVOICE_ABYS_ID'
          AND is_disabled = 1
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('REBUILD UX_LS005_INVOICE_ABYS_ID...', 0, 1) WITH NOWAIT;
        ALTER INDEX UX_LS005_INVOICE_ABYS_ID ON energy.dbo.LS_005_01_INVOICE
            REBUILD WITH (MAXDOP = 24, SORT_IN_TEMPDB = ON);
    END

    -- 3) Sik kullanilan destek indexleri (idempotent)
    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
          AND name = 'IX_LS005_INVOICE_ABYS_ACCOUNT_ID'
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE IX_LS005_INVOICE_ABYS_ACCOUNT_ID...', 0, 1) WITH NOWAIT;

        CREATE NONCLUSTERED INDEX IX_LS005_INVOICE_ABYS_ACCOUNT_ID
            ON energy.dbo.LS_005_01_INVOICE (ABYS_ACCOUNT_ID)
            WHERE ABYS_ACCOUNT_ID IS NOT NULL
            WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
    END

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
          AND name = 'IX_LS005_INVOICE_CLIENTREF'
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE IX_LS005_INVOICE_CLIENTREF...', 0, 1) WITH NOWAIT;

        CREATE NONCLUSTERED INDEX IX_LS005_INVOICE_CLIENTREF
            ON energy.dbo.LS_005_01_INVOICE (CLIENTREF)
            WHERE CLIENTREF IS NOT NULL
            WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
    END

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
          AND name = 'IX_LS005_INVOICE_DATE_'
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE IX_LS005_INVOICE_DATE_...', 0, 1) WITH NOWAIT;

        CREATE NONCLUSTERED INDEX IX_LS005_INVOICE_DATE_
            ON energy.dbo.LS_005_01_INVOICE (DATE_)
            WHERE DATE_ IS NOT NULL
            WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
    END

    UPDATE STATISTICS energy.dbo.LS_005_01_INVOICE WITH FULLSCAN;

    IF @DEBUG = 1
        RAISERROR('SP_MIG_INVOICE_POST_INDEXES OK', 0, 1) WITH NOWAIT;
END
GO

-- Deploy aninda SP olusturulur; 80M index build manuel:
-- EXEC energy.dbo.SP_MIG_INVOICE_POST_INDEXES @DEBUG = 1;
PRINT '572_INVOICE__post OK (SP_MIG_INVOICE_POST_INDEXES)';
GO
