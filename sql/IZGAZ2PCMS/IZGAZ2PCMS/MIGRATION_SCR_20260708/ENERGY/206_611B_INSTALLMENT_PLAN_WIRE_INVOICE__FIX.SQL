/* ============================================================
   FILE : 611b_INSTALLMENT_PLAN_WIRE_INVOICE__fix.sql
   Fast set-based wire — OR/CROSS APPLY kaldırıldı
   ============================================================ */
USE energy;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE
    @AGR_ID BIGINT = NULL,
    @DEBUG  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Msg NVARCHAR(400);
    DECLARE @N INT;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME();

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
          AND name = 'IX_MIG_INV_ABYS_INSTALLMENT_ID'
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE IX_MIG_INV_ABYS_INSTALLMENT_ID...', 0, 1) WITH NOWAIT;
        CREATE NONCLUSTERED INDEX IX_MIG_INV_ABYS_INSTALLMENT_ID
            ON energy.dbo.LS_005_01_INVOICE (ABYS_INSTALLMENT_ID)
            INCLUDE (LREF, DUEDATE, PAYABLETOTAL, IOCODE)
            WHERE ABYS_INSTALLMENT_ID IS NOT NULL
            WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
    END

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
          AND name = 'IX_MIG_INV_INSTALLMENT_PLAN_REF'
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE IX_MIG_INV_INSTALLMENT_PLAN_REF...', 0, 1) WITH NOWAIT;
        CREATE NONCLUSTERED INDEX IX_MIG_INV_INSTALLMENT_PLAN_REF
            ON energy.dbo.LS_005_01_INVOICE (INSTALLMENT_PLAN_REF)
            INCLUDE (LREF, DUEDATE, PAYABLETOTAL, IOCODE)
            WHERE INSTALLMENT_PLAN_REF IS NOT NULL
            WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
    END

    /* Pass 1: ABYS_INSTALLMENT_ID — ayrı dallar (OR residual YOK) */
    IF @AGR_ID IS NULL
    BEGIN
        ;WITH inv_best AS (
            SELECT
                i.ABYS_INSTALLMENT_ID,
                i.LREF,
                i.DUEDATE,
                ROW_NUMBER() OVER (PARTITION BY i.ABYS_INSTALLMENT_ID ORDER BY i.LREF) AS rn
            FROM energy.dbo.LS_005_01_INVOICE i WITH (NOLOCK)
            WHERE i.ABYS_INSTALLMENT_ID IS NOT NULL
              AND ISNULL(i.IOCODE, 0) = 0
              AND ISNULL(i.PAYABLETOTAL, 0) > 0.01
        )
        UPDATE pl
        SET pl.INVOICE_REF = b.LREF,
            pl.INVOICE_OLD_DUEDATE = ISNULL(pl.INVOICE_OLD_DUEDATE, b.DUEDATE)
        FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl
        INNER JOIN inv_best b
            ON b.ABYS_INSTALLMENT_ID = pl.ABYS_INSTALLMENT_ID AND b.rn = 1
        WHERE pl.ABYS_ID IS NOT NULL
          AND pl.INVOICE_REF IS NULL
          AND pl.ABYS_INSTALLMENT_ID IS NOT NULL;
    END
    ELSE
    BEGIN
        ;WITH inv_best AS (
            SELECT
                i.ABYS_INSTALLMENT_ID,
                i.LREF,
                i.DUEDATE,
                ROW_NUMBER() OVER (PARTITION BY i.ABYS_INSTALLMENT_ID ORDER BY i.LREF) AS rn
            FROM energy.dbo.LS_005_01_INVOICE i WITH (NOLOCK)
            WHERE i.ABYS_AGREEMENT_ID = @AGR_ID
              AND i.ABYS_INSTALLMENT_ID IS NOT NULL
              AND ISNULL(i.IOCODE, 0) = 0
              AND ISNULL(i.PAYABLETOTAL, 0) > 0.01
        )
        UPDATE pl
        SET pl.INVOICE_REF = b.LREF,
            pl.INVOICE_OLD_DUEDATE = ISNULL(pl.INVOICE_OLD_DUEDATE, b.DUEDATE)
        FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl
        INNER JOIN inv_best b
            ON b.ABYS_INSTALLMENT_ID = pl.ABYS_INSTALLMENT_ID AND b.rn = 1
        WHERE pl.ABYS_AGREEMENT_ID = @AGR_ID
          AND pl.ABYS_ID IS NOT NULL
          AND pl.INVOICE_REF IS NULL
          AND pl.ABYS_INSTALLMENT_ID IS NOT NULL;
    END

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Wire pass1 ABYS_INSTALLMENT_ID n=' + CAST(@N AS VARCHAR(20))
                 + N' sec=' + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* Pass 2: INSTALLMENT_PLAN_REF = PLAN_ID */
    SET @t0 = SYSDATETIME();
    IF @AGR_ID IS NULL
    BEGIN
        ;WITH inv_best AS (
            SELECT
                i.INSTALLMENT_PLAN_REF AS PLAN_ID,
                i.LREF,
                i.DUEDATE,
                ROW_NUMBER() OVER (PARTITION BY i.INSTALLMENT_PLAN_REF ORDER BY i.LREF) AS rn
            FROM energy.dbo.LS_005_01_INVOICE i WITH (NOLOCK)
            WHERE i.INSTALLMENT_PLAN_REF IS NOT NULL
              AND ISNULL(i.IOCODE, 0) = 0
              AND ISNULL(i.PAYABLETOTAL, 0) > 0.01
        )
        UPDATE pl
        SET pl.INVOICE_REF = b.LREF,
            pl.INVOICE_OLD_DUEDATE = ISNULL(pl.INVOICE_OLD_DUEDATE, b.DUEDATE)
        FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl
        INNER JOIN inv_best b ON b.PLAN_ID = pl.PLAN_ID AND b.rn = 1
        WHERE pl.ABYS_ID IS NOT NULL
          AND pl.INVOICE_REF IS NULL
          AND pl.PLAN_ID IS NOT NULL;
    END
    ELSE
    BEGIN
        ;WITH inv_best AS (
            SELECT
                i.INSTALLMENT_PLAN_REF AS PLAN_ID,
                i.LREF,
                i.DUEDATE,
                ROW_NUMBER() OVER (PARTITION BY i.INSTALLMENT_PLAN_REF ORDER BY i.LREF) AS rn
            FROM energy.dbo.LS_005_01_INVOICE i WITH (NOLOCK)
            WHERE i.ABYS_AGREEMENT_ID = @AGR_ID
              AND i.INSTALLMENT_PLAN_REF IS NOT NULL
              AND ISNULL(i.IOCODE, 0) = 0
              AND ISNULL(i.PAYABLETOTAL, 0) > 0.01
        )
        UPDATE pl
        SET pl.INVOICE_REF = b.LREF,
            pl.INVOICE_OLD_DUEDATE = ISNULL(pl.INVOICE_OLD_DUEDATE, b.DUEDATE)
        FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl
        INNER JOIN inv_best b ON b.PLAN_ID = pl.PLAN_ID AND b.rn = 1
        WHERE pl.ABYS_AGREEMENT_ID = @AGR_ID
          AND pl.ABYS_ID IS NOT NULL
          AND pl.INVOICE_REF IS NULL
          AND pl.PLAN_ID IS NOT NULL;
    END

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Wire pass2 INSTALLMENT_PLAN_REF n=' + CAST(@N AS VARCHAR(20))
                 + N' sec=' + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

        SELECT
            SUM(CASE WHEN INVOICE_REF IS NOT NULL THEN 1 ELSE 0 END) AS WITH_INVOICE,
            SUM(CASE WHEN INVOICE_REF IS NULL THEN 1 ELSE 0 END) AS WITHOUT_INVOICE
        FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN WITH (NOLOCK)
        WHERE ABYS_ID IS NOT NULL
          AND (@AGR_ID IS NULL OR ABYS_AGREEMENT_ID = @AGR_ID);
    END
END
GO

PRINT '611b_WIRE_INVOICE fix OK';
GO
