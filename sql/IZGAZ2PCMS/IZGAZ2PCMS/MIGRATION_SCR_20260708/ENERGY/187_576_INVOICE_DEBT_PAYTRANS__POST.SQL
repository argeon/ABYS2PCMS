/* ============================================================
   SCRIPT_ID : INVOICE_DEBT_PAYTRANS_POST
   SCRIPT_NO : 576
   FILE      : 576_INVOICE_DEBT_PAYTRANS__post.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LS_005_01_PAYTRANS (borç PT) aktarim SONRASI index kurulumu
-- Wire / FK remap YOK — sadece NC index CREATE + REBUILD
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_DEBT_PAYTRANS_POST_INDEXES
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS', 'U') IS NULL
    BEGIN
        RAISERROR('energy.dbo.LS_005_01_PAYTRANS bulunamadi.', 16, 1);
        RETURN;
    END

    DECLARE @Sql NVARCHAR(MAX) = N'';
    DECLARE @Msg NVARCHAR(500);
    DECLARE @RowCnt BIGINT;

    IF @DEBUG = 1
    BEGIN
        SELECT @RowCnt = SUM(p.rows)
        FROM sys.partitions p
        WHERE p.object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND p.index_id IN (0, 1);
        SET @Msg = N'DEBT_PAYTRANS post indexes | ~' + CAST(ISNULL(@RowCnt, 0) AS VARCHAR(20)) + N' satir';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    -- 1) Disabled NC indexleri rebuild
    SET @Sql = N'';
    SELECT @Sql = @Sql + N'
ALTER INDEX ' + QUOTENAME(i.name) + N' ON energy.dbo.LS_005_01_PAYTRANS REBUILD WITH (MAXDOP = 24, SORT_IN_TEMPDB = ON);'
    FROM sys.indexes i
    WHERE i.object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
      AND i.type_desc = 'NONCLUSTERED'
      AND i.is_disabled = 1
      AND i.name IS NOT NULL;

    IF LEN(@Sql) > 0
    BEGIN
        IF @DEBUG = 1
            RAISERROR('Disabled NC index REBUILD...', 0, 1) WITH NOWAIT;
        EXEC sp_executesql @Sql;
    END

    -- 2) ABYS_ID unique (filtered) — borç + tahsilat ABYS aksiyon id'leri ayri
    --    Duplicate ABYS_ID varsa UX atlanir (PIPELINE_KNOWN_ISSUES); non-unique IX kurulur.
    --    TODO: dup temizlenince UX yeniden CREATE edilmeli.
    DECLARE @DupAbys INT = 0;
    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND name = 'UX_LS005_PAYTRANS_ABYS_ID'
    )
    BEGIN
        ;WITH d AS (
            SELECT ABYS_ID
            FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
            WHERE ABYS_ID IS NOT NULL
            GROUP BY ABYS_ID
            HAVING COUNT(*) > 1
        )
        SELECT @DupAbys = COUNT(*) FROM d;

        IF @DupAbys > 0
        BEGIN
            SET @Msg = N'WARN SKIP UX_LS005_PAYTRANS_ABYS_ID: ' + CAST(@DupAbys AS VARCHAR(20))
                     + N' duplicate ABYS_ID (see PIPELINE_KNOWN_ISSUES.txt)';
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
        ELSE
        BEGIN
            IF @DEBUG = 1
                RAISERROR('CREATE UX_LS005_PAYTRANS_ABYS_ID...', 0, 1) WITH NOWAIT;

            CREATE UNIQUE NONCLUSTERED INDEX UX_LS005_PAYTRANS_ABYS_ID
                ON energy.dbo.LS_005_01_PAYTRANS (ABYS_ID)
                WHERE ABYS_ID IS NOT NULL
                WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
        END
    END
    ELSE IF EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND name = 'UX_LS005_PAYTRANS_ABYS_ID'
          AND is_disabled = 1
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('REBUILD UX_LS005_PAYTRANS_ABYS_ID...', 0, 1) WITH NOWAIT;
        ALTER INDEX UX_LS005_PAYTRANS_ABYS_ID ON energy.dbo.LS_005_01_PAYTRANS
            REBUILD WITH (MAXDOP = 24, SORT_IN_TEMPDB = ON);
    END

    -- Non-unique ABYS seek (UX yoksa veya her zaman kullanisli)
    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND name IN ('UX_LS005_PAYTRANS_ABYS_ID', 'IX_LS005_PAYTRANS_ABYS_ID')
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE IX_LS005_PAYTRANS_ABYS_ID (non-unique)...', 0, 1) WITH NOWAIT;
        CREATE NONCLUSTERED INDEX IX_LS005_PAYTRANS_ABYS_ID
            ON energy.dbo.LS_005_01_PAYTRANS (ABYS_ID)
            WHERE ABYS_ID IS NOT NULL
            WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
    END

    -- 3) Borç PT unique (taksit uyumlu):
    --    INST_NR=0 → invoice basina 1 ana borc
    --    INST_NR>0 → (INVOICEREF, INST_NR) unique
    -- Eski UX_LS005_PAYTRANS_DEBT_INVOICEREF (tum borc) 613 split ile Msg 2601 verir — kullanma.
    IF EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND name = 'UX_LS005_PAYTRANS_DEBT_INVOICEREF'
    )
    BEGIN
        DROP INDEX UX_LS005_PAYTRANS_DEBT_INVOICEREF ON energy.dbo.LS_005_01_PAYTRANS;
        RAISERROR('DROP UX_LS005_PAYTRANS_DEBT_INVOICEREF (replaced by INST0/INSTN)', 0, 1) WITH NOWAIT;
    END

    /* Filtered index: OR / ISNULL / IS NULL yasak. NULL ≈ 0 → önce normalize, sonra = 0. */
    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND name = 'UX_MIG_PT_DEBT_INV_INST0'
    )
       OR NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND name = 'UX_MIG_PT_DEBT_INV_INSTN'
    )
    BEGIN
        UPDATE energy.dbo.LS_005_01_PAYTRANS
           SET CANCELED = 0
         WHERE IOCODE = 0 AND CANCELED IS NULL;

        UPDATE energy.dbo.LS_005_01_PAYTRANS
           SET CANCELLATIONPAYMENT = 0
         WHERE IOCODE = 0 AND CANCELLATIONPAYMENT IS NULL;
    END

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND name = 'UX_MIG_PT_DEBT_INV_INST0'
    )
    BEGIN
        BEGIN TRY
            IF @DEBUG = 1
                RAISERROR('CREATE UX_MIG_PT_DEBT_INV_INST0...', 0, 1) WITH NOWAIT;
            CREATE UNIQUE NONCLUSTERED INDEX UX_MIG_PT_DEBT_INV_INST0
                ON energy.dbo.LS_005_01_PAYTRANS (INVOICEREF)
                WHERE IOCODE = 0 AND INST_NR = 0 AND CANCELED = 0 AND CANCELLATIONPAYMENT = 0
                WITH (MAXDOP = 24, SORT_IN_TEMPDB = ON);
        END TRY
        BEGIN CATCH
            RAISERROR('WARN UX_MIG_PT_DEBT_INV_INST0 create fail — once 91_debt_pt_dup_cleanup.sql', 0, 1) WITH NOWAIT;
        END CATCH
    END

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND name = 'UX_MIG_PT_DEBT_INV_INSTN'
    )
    BEGIN
        BEGIN TRY
            IF @DEBUG = 1
                RAISERROR('CREATE UX_MIG_PT_DEBT_INV_INSTN...', 0, 1) WITH NOWAIT;
            CREATE UNIQUE NONCLUSTERED INDEX UX_MIG_PT_DEBT_INV_INSTN
                ON energy.dbo.LS_005_01_PAYTRANS (INVOICEREF, INST_NR)
                WHERE IOCODE = 0 AND INST_NR > 0 AND CANCELED = 0 AND CANCELLATIONPAYMENT = 0
                WITH (MAXDOP = 24, SORT_IN_TEMPDB = ON);
        END TRY
        BEGIN CATCH
            RAISERROR('WARN UX_MIG_PT_DEBT_INV_INSTN create fail — INST_NR duplicate var', 0, 1) WITH NOWAIT;
        END CATCH
    END

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND name = 'IX_LS005_PAYTRANS_INVOICEREF'
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE IX_LS005_PAYTRANS_INVOICEREF...', 0, 1) WITH NOWAIT;

        CREATE NONCLUSTERED INDEX IX_LS005_PAYTRANS_INVOICEREF
            ON energy.dbo.LS_005_01_PAYTRANS (INVOICEREF)
            WHERE INVOICEREF IS NOT NULL
            WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
    END

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND name = 'IX_LS005_PAYTRANS_IOCODE'
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE IX_LS005_PAYTRANS_IOCODE...', 0, 1) WITH NOWAIT;

        CREATE NONCLUSTERED INDEX IX_LS005_PAYTRANS_IOCODE
            ON energy.dbo.LS_005_01_PAYTRANS (IOCODE, INVOICEREF)
            INCLUDE (PAID, PAYABLETOTAL, CANCELED)
            WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
    END

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND name = 'IX_LS005_PAYTRANS_CLIENTREF'
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE IX_LS005_PAYTRANS_CLIENTREF...', 0, 1) WITH NOWAIT;

        CREATE NONCLUSTERED INDEX IX_LS005_PAYTRANS_CLIENTREF
            ON energy.dbo.LS_005_01_PAYTRANS (CLIENTREF)
            WHERE CLIENTREF IS NOT NULL
            WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
    END

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND name = 'IX_LS005_PAYTRANS_ABYS_ACCOUNT_ID'
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE IX_LS005_PAYTRANS_ABYS_ACCOUNT_ID...', 0, 1) WITH NOWAIT;

        CREATE NONCLUSTERED INDEX IX_LS005_PAYTRANS_ABYS_ACCOUNT_ID
            ON energy.dbo.LS_005_01_PAYTRANS (ABYS_ACCOUNT_ID)
            WHERE ABYS_ACCOUNT_ID IS NOT NULL
            WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
    END

    UPDATE STATISTICS energy.dbo.LS_005_01_PAYTRANS WITH SAMPLE 10 PERCENT;

    IF @DEBUG = 1
        RAISERROR('SP_MIG_DEBT_PAYTRANS_POST_INDEXES OK', 0, 1) WITH NOWAIT;
END
GO

-- Deploy aninda SP olusturulur; 74M index build manuel:
-- EXEC energy.dbo.SP_MIG_DEBT_PAYTRANS_POST_INDEXES @DEBUG = 1;
PRINT '576_INVOICE_DEBT_PAYTRANS__post OK (SP_MIG_DEBT_PAYTRANS_POST_INDEXES)';
GO
