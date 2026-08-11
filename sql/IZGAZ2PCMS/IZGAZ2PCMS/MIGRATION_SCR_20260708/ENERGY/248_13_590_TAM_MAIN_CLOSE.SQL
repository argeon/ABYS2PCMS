/* =============================================================================
   FILE : prodREADY_ENERGY / 13_590_TAM_MAIN_CLOSE.sql
   R20  : TAM + TYPE92 IADE sonrasi MAIN debt PT/INV kapatma (kalici E590 fazi)

   Onceki residual: 90_afl_frk/98_TEST_tam_iade_main_close.sql (test)
                    90_afl_frk/98_tam_iade_main_pt_close_temp.sql

   KURAL:
     OV_EKS KIND=TAM + TYPE92 (ayni ABYS_ACCOUNT_ID) + AFL≈0
     + MAIN debt PT acik (PAYABLE-PAID > eps)
   APPLY:
     PT.PAID = PAYABLETOTAL ; INV.CLOSED = 1

   Cagri: SP_MIG_590_ALL (WIRE sonrasi, GATE oncesi)
     EXEC dbo.SP_MIG_590_TAM_MAIN_CLOSE @AGR_ID=NULL, @DEBUG=1, @DryRun=0;
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_590_TAM_MAIN_CLOSE
    @AGR_ID  BIGINT        = NULL,   /* NULL=FULL | -1=NO_AGR | >0=tek AGR */
    @DEBUG   BIT           = 1,
    @DryRun  BIT           = 0,      /* ALL'dan 0; ad-hoc tespit icin 1 */
    @Eps     DECIMAL(18,2) = 0.02
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @DryRunInt INT = CAST(@DryRun AS INT);
    DECLARE @DebugInt  INT = CAST(@DEBUG AS INT);
    DECLARE @Msg       NVARCHAR(400);
    DECLARE @N         INT;
    DECLARE @RunId     UNIQUEIDENTIFIER = NEWID();
    DECLARE @Ts        DATETIME2(3) = SYSDATETIME();
    DECLARE @AflFrom   SYSNAME;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'590 TAM_MAIN_CLOSE start DryRun=' + CAST(@DryRunInt AS VARCHAR(1))
                 + N' AGR=' + CASE WHEN @AGR_ID IS NULL THEN N'FULL'
                                  WHEN @AGR_ID = -1 THEN N'NO_AGR'
                                  ELSE CAST(@AGR_ID AS NVARCHAR(30)) END;
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_EKS_CLASS', 'U') IS NULL
    BEGIN
        RAISERROR('590 TAM_MAIN_CLOSE SKIP: izgazMGR.dbo.LS_OV_EKS_CLASS yok', 10, 1) WITH NOWAIT;
        RETURN;
    END

    IF OBJECT_ID('energy.dbo.LS_AFL_OPEN_DEBT', 'U') IS NOT NULL
        SET @AflFrom = N'energy';
    ELSE IF OBJECT_ID('izgazMGR.dbo.LS_AFL_OPEN_DEBT', 'U') IS NOT NULL
        SET @AflFrom = N'izgazMGR';
    ELSE
    BEGIN
        RAISERROR('590 TAM_MAIN_CLOSE SKIP: LS_AFL_OPEN_DEBT yok', 10, 1) WITH NOWAIT;
        RETURN;
    END

    /* ---- Log tablo ---- */
    IF OBJECT_ID('energy.dbo.MIG_TAM_IADE_CLOSE_LOG', 'U') IS NULL
    BEGIN
        CREATE TABLE energy.dbo.MIG_TAM_IADE_CLOSE_LOG (
            LOG_ID         BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
            RUN_ID         UNIQUEIDENTIFIER NOT NULL,
            SNAPSHOT_TS    DATETIME2(3) NOT NULL
                CONSTRAINT DF_MIG_TAM_IADE_CLOSE_TS DEFAULT (SYSDATETIME()),
            DRY_RUN        BIT NOT NULL,
            AGREEMENT_ID   BIGINT NULL,
            ACCOUNT_ID     BIGINT NOT NULL,
            MAIN_LREF      INT NOT NULL,
            PT_LREF        INT NOT NULL,
            IADE_LREF      INT NULL,
            EKS_AMT        DECIMAL(18,2) NULL,
            IADE_AMT       DECIMAL(18,2) NULL,
            PT_PAID_OLD    DECIMAL(18,2) NULL,
            PT_PAYABLE     DECIMAL(18,2) NULL,
            PT_KALAN       DECIMAL(18,2) NULL,
            AFL_BALANCE    DECIMAL(18,2) NULL,
            SOURCE_KIND    VARCHAR(20) NOT NULL,
            NOTE           NVARCHAR(200) NULL
        );
        CREATE NONCLUSTERED INDEX IX_MIG_TAM_IADE_CLOSE_RUN
            ON energy.dbo.MIG_TAM_IADE_CLOSE_LOG (RUN_ID, ACCOUNT_ID);
    END

    IF OBJECT_ID('tempdb..#CAND') IS NOT NULL DROP TABLE #CAND;
    IF OBJECT_ID('tempdb..#AFL') IS NOT NULL DROP TABLE #AFL;

    CREATE TABLE #AFL (
        ACCOUNT_ID BIGINT NOT NULL PRIMARY KEY,
        BALANCE    DECIMAL(18,2) NOT NULL
    );

    IF @AflFrom = N'energy'
    BEGIN
        INSERT INTO #AFL (ACCOUNT_ID, BALANCE)
        SELECT CAST(a.FATURAID AS BIGINT),
               CONVERT(DECIMAL(18,2), SUM(CONVERT(DECIMAL(18,2), ISNULL(a.BALANCE, 0))))
        FROM energy.dbo.LS_AFL_OPEN_DEBT a WITH (NOLOCK)
        WHERE ISNULL(a.MIG_IN_SCOPE, 1) = 1
        GROUP BY CAST(a.FATURAID AS BIGINT)
        OPTION (RECOMPILE, MAXDOP 8);
    END
    ELSE
    BEGIN
        INSERT INTO #AFL (ACCOUNT_ID, BALANCE)
        SELECT CAST(a.FATURAID AS BIGINT),
               CONVERT(DECIMAL(18,2), SUM(CONVERT(DECIMAL(18,2), ISNULL(a.BALANCE, 0))))
        FROM izgazMGR.dbo.LS_AFL_OPEN_DEBT a WITH (NOLOCK)
        WHERE ISNULL(a.MIG_IN_SCOPE, 1) = 1
        GROUP BY CAST(a.FATURAID AS BIGINT)
        OPTION (RECOMPILE, MAXDOP 8);
    END

    ;WITH tam AS (
        SELECT
            CAST(e.AGREEMENT_ID AS BIGINT) AS AGREEMENT_ID,
            CAST(e.ACCOUNT_ID AS BIGINT) AS ACCOUNT_ID,
            CAST(e.MAIN_LREF AS INT) AS MAIN_LREF,
            CONVERT(DECIMAL(18,2), ISNULL(e.EKS_AMT, 0)) AS EKS_AMT
        FROM izgazMGR.dbo.LS_OV_EKS_CLASS e WITH (NOLOCK)
        WHERE e.KIND = 'TAM'
          AND e.MAIN_LREF IS NOT NULL
          AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND e.AGREEMENT_ID IS NULL)
               OR (@AGR_ID > 0 AND e.AGREEMENT_ID = @AGR_ID)
                )
    ),
    iade AS (
        SELECT
            inv.ABYS_ACCOUNT_ID AS ACCOUNT_ID,
            MAX(inv.LREF) AS IADE_LREF,
            CONVERT(DECIMAL(18,2), SUM(CONVERT(DECIMAL(18,2), ISNULL(inv.PAYABLETOTAL, 0)))) AS IADE_AMT
        FROM dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
        WHERE inv.TYPE = 92
          AND inv.CANCELED = 0
          AND inv.ABYS_ACCOUNT_ID IS NOT NULL
          AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL)
               OR (@AGR_ID > 0 AND (
                        inv.ABYS_AGREEMENT_ID = @AGR_ID
                     OR inv.OWNERREF = CONVERT(INT, @AGR_ID)
                   ))
                )
        GROUP BY inv.ABYS_ACCOUNT_ID
    )
    SELECT
        t.AGREEMENT_ID,
        t.ACCOUNT_ID,
        t.MAIN_LREF,
        t.EKS_AMT,
        i.IADE_LREF,
        i.IADE_AMT,
        CAST(N'OV_TAM' AS VARCHAR(20)) AS SOURCE_KIND,
        inv.TYPE AS MAIN_TYPE,
        ISNULL(inv.CLOSED, 0) AS MAIN_CLOSED,
        CONVERT(DECIMAL(18,2), ISNULL(inv.PAYABLETOTAL, 0)) AS INV_PAYABLE,
        pt.LREF AS PT_LREF,
        CONVERT(DECIMAL(18,2), ISNULL(pt.PAYABLETOTAL, 0)) AS PT_PAYABLE,
        CONVERT(DECIMAL(18,2), ISNULL(pt.PAID, 0)) AS PT_PAID_OLD,
        CONVERT(DECIMAL(18,2), ISNULL(pt.PAYABLETOTAL, 0)) AS PT_PAID_NEW,
        CONVERT(DECIMAL(18,2),
            ISNULL(pt.PAYABLETOTAL, 0) - ISNULL(pt.PAID, 0)) AS PT_KALAN,
        CONVERT(DECIMAL(18,2), ISNULL(a.BALANCE, 0)) AS AFL_BALANCE
    INTO #CAND
    FROM tam t
    INNER JOIN iade i ON i.ACCOUNT_ID = t.ACCOUNT_ID
    INNER JOIN dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
        ON inv.LREF = t.MAIN_LREF
       AND inv.IOCODE = 0
       AND inv.CANCELED = 0
    INNER JOIN dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
        ON pt.INVOICEREF = inv.LREF
       AND pt.IOCODE = 0
       AND pt.CANCELED = 0
       AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
    LEFT JOIN #AFL a ON a.ACCOUNT_ID = t.ACCOUNT_ID
    WHERE CONVERT(DECIMAL(18,2), ISNULL(pt.PAYABLETOTAL, 0) - ISNULL(pt.PAID, 0)) > @Eps
      AND CONVERT(DECIMAL(18,2), ISNULL(a.BALANCE, 0)) <= @Eps
    OPTION (RECOMPILE, MAXDOP 8);

    CREATE CLUSTERED INDEX CX_CAND ON #CAND (PT_LREF);

    SET @N = (SELECT COUNT(*) FROM #CAND);
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'590 TAM_MAIN_CLOSE aday PT=' + CAST(@N AS VARCHAR(20))
                 + N' ACC=' + CAST((SELECT COUNT(DISTINCT ACCOUNT_ID) FROM #CAND) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    INSERT INTO energy.dbo.MIG_TAM_IADE_CLOSE_LOG (
        RUN_ID, SNAPSHOT_TS, DRY_RUN, AGREEMENT_ID, ACCOUNT_ID,
        MAIN_LREF, PT_LREF, IADE_LREF, EKS_AMT, IADE_AMT,
        PT_PAID_OLD, PT_PAYABLE, PT_KALAN, AFL_BALANCE, SOURCE_KIND, NOTE
    )
    SELECT
        @RunId, @Ts, @DryRun, AGREEMENT_ID, ACCOUNT_ID,
        MAIN_LREF, PT_LREF, IADE_LREF, EKS_AMT, IADE_AMT,
        PT_PAID_OLD, PT_PAYABLE, PT_KALAN, AFL_BALANCE, SOURCE_KIND,
        CASE WHEN @DryRun = 1 THEN N'DRY_RUN' ELSE N'APPLY_E590' END
    FROM #CAND;

    IF @N = 0
    BEGIN
        IF @DEBUG = 1
            RAISERROR('590 TAM_MAIN_CLOSE: aday yok', 0, 1) WITH NOWAIT;
        RETURN;
    END

    IF @DryRun = 1
    BEGIN
        IF @DEBUG = 1
            RAISERROR('590 TAM_MAIN_CLOSE DRY_RUN=1 — UPDATE yok', 0, 1) WITH NOWAIT;
        RETURN;
    END

    BEGIN TRAN;

    UPDATE pt
    SET pt.PAID = CONVERT(FLOAT, c.PT_PAID_NEW)
    FROM dbo.LS_005_01_PAYTRANS pt
    INNER JOIN #CAND c ON c.PT_LREF = pt.LREF
    WHERE pt.IOCODE = 0
      AND pt.CANCELED = 0
      AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0;

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'590 TAM_MAIN_CLOSE PT PAID=PAYABLE n=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    UPDATE inv
    SET inv.CLOSED = CAST(1 AS BIT)
    FROM dbo.LS_005_01_INVOICE inv
    INNER JOIN (SELECT DISTINCT MAIN_LREF FROM #CAND) c ON c.MAIN_LREF = inv.LREF
    WHERE inv.IOCODE = 0
      AND inv.CANCELED = 0
      AND ISNULL(inv.CLOSED, 0) = 0;

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'590 TAM_MAIN_CLOSE INV CLOSED=1 n=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    COMMIT TRAN;

    IF @DEBUG = 1
    BEGIN
        SELECT @N = COUNT(*)
        FROM #CAND c
        INNER JOIN dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK) ON pt.LREF = c.PT_LREF
        WHERE CONVERT(DECIMAL(18,2), ISNULL(pt.PAYABLETOTAL, 0) - ISNULL(pt.PAID, 0)) > @Eps;
        SET @Msg = N'590 TAM_MAIN_CLOSE POST still_open=' + CAST(@N AS VARCHAR(20))
                 + N' RUN=' + CONVERT(NVARCHAR(36), @RunId);
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

PRINT 'SP_MIG_590_TAM_MAIN_CLOSE OK (R20)';
GO
