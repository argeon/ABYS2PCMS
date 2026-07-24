/* ============================================================
   FILE : adim_590_597_then_613.sql
   Sira (kullanici tercihi):
     1) 590 EKSILTEN
     2) 597 TAHSILAT
     3) 613 NORMALIZE+SPLIT (taksit en sonda)
     4) CHECKIDENT PAYTRANS bir kez
   CHECKIDENT AGR dongusunde YOK (@DO_RESEED=0)
   ============================================================ */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;

DECLARE @Msg NVARCHAR(400);
DECLARE @tAll DATETIME2(3) = SYSDATETIME();
DECLARE @t0 DATETIME2(3);
DECLARE @i INT = 1, @n INT, @AGR_ID BIGINT;
DECLARE @try INT, @ok BIT;
DECLARE @MaxLref BIGINT;

SET @Msg = N'===== 590→597→613 START ' + CONVERT(VARCHAR(30), @tAll, 121) + N' =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
RAISERROR('NOTE: taksit (613) en sonda; CHECKIDENT sadece 613 sonunda', 0, 1) WITH NOWAIT;

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
      AND name = 'UX_LS005_PAYTRANS_DEBT_INVOICEREF'
)
    DROP INDEX UX_LS005_PAYTRANS_DEBT_INVOICEREF ON dbo.LS_005_01_PAYTRANS;

/* ---- 590 EKSILTEN ---- */
SET @t0 = SYSDATETIME();
SET @Msg = N'===== 590 EKSILTEN START =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

IF OBJECT_ID('energy.dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR', 'P') IS NOT NULL
   AND OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_INVOICE', 'U') IS NOT NULL
    EXEC energy.dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR
        @AGR_ID = NULL, @CLEAN = 1, @DEBUG = 1;
ELSE
    RAISERROR('590 SP/kaynak yok — atlandi', 0, 1) WITH NOWAIT;

SET @Msg = N'===== 590 DONE sec=' + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20)) + N' =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

/* ---- 597 TAHSILAT ---- */
SET @t0 = SYSDATETIME();
SET @Msg = N'===== 597 TAHSILAT START =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

IF OBJECT_ID('energy.dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR', 'P') IS NOT NULL
   AND OBJECT_ID('izgazMGR.dbo.LS_OV_PAY_PT', 'U') IS NOT NULL
    EXEC energy.dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR
        @AGR_ID = NULL, @CLEAN = 1, @DEBUG = 1;
ELSE
    RAISERROR('597 SP/kaynak yok — atlandi', 0, 1) WITH NOWAIT;

SET @Msg = N'===== 597 DONE sec=' + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20)) + N' =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

/* ---- 613 taksit (en sonda) ---- */
SET @t0 = SYSDATETIME();
SET @Msg = N'===== 613 NORMALIZE+SPLIT START =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

/* wire bir kez (set-based) */
IF OBJECT_ID('energy.dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE', 'P') IS NOT NULL
    EXEC energy.dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE @AGR_ID = NULL, @DEBUG = 1;

IF OBJECT_ID('tempdb..#Agr') IS NOT NULL DROP TABLE #Agr;
CREATE TABLE #Agr (ORD INT NOT NULL PRIMARY KEY, AGR_ID BIGINT NOT NULL);

INSERT INTO #Agr (ORD, AGR_ID)
SELECT ROW_NUMBER() OVER (ORDER BY AGR_ID), AGR_ID
FROM (
    SELECT DISTINCT pl.ABYS_AGREEMENT_ID AS AGR_ID
    FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
    WHERE pl.ABYS_ID IS NOT NULL
      AND pl.ABYS_AGREEMENT_ID IS NOT NULL
) d;

SELECT @n = COUNT(*) FROM #Agr;
SET @Msg = N'613 AGR_CNT=' + CAST(@n AS VARCHAR(20));
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

WHILE @i <= @n
BEGIN
    SELECT @AGR_ID = AGR_ID FROM #Agr WHERE ORD = @i;
    SET @ok = 0;
    SET @try = 0;

    WHILE @try < 3 AND @ok = 0
    BEGIN
        SET @try += 1;
        BEGIN TRY
            EXEC energy.dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR
                @AGR_ID = @AGR_ID, @DEBUG = 0;

            EXEC energy.dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR
                @AGR_ID = @AGR_ID, @DEBUG = 0, @DO_RESEED = 0;

            SET @ok = 1;
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() = 1205
            BEGIN
                SET @Msg = N'DEADLOCK retry ' + CAST(@try AS VARCHAR(5))
                         + N' AGR=' + CAST(@AGR_ID AS VARCHAR(20));
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
                WAITFOR DELAY '00:00:00.200';
            END
            ELSE
            BEGIN
                SET @Msg = N'ERR AGR=' + CAST(@AGR_ID AS VARCHAR(20)) + N' ' + ERROR_MESSAGE();
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
                SET @ok = 1;
            END
        END CATCH
    END

    IF @i = 1 OR @i = @n OR @i % 500 = 0
    BEGIN
        SET @Msg = N'--- 613 ' + CAST(@i AS VARCHAR(10)) + N'/' + CAST(@n AS VARCHAR(10))
                 + N' AGR=' + CAST(@AGR_ID AS VARCHAR(20))
                 + N' sec=' + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20))
                 + N' ms/agr=' + CASE WHEN @i > 1
                      THEN CAST(DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) / (@i * 1.0) AS VARCHAR(20))
                      ELSE N'?' END;
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    SET @i += 1;
END

SET @Msg = N'===== 613 LOOP DONE sec=' + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20)) + N' =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

/* ---- tek CHECKIDENT ---- */
SET @t0 = SYSDATETIME();
RAISERROR('===== PAYTRANS CHECKIDENT (once) =====', 0, 1) WITH NOWAIT;
SELECT @MaxLref = ISNULL(MAX(LREF), 0) FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK);
DBCC CHECKIDENT('energy.dbo.LS_005_01_PAYTRANS', RESEED, @MaxLref) WITH NO_INFOMSGS;
SET @Msg = N'CHECKIDENT RESEED=' + CAST(@MaxLref AS VARCHAR(20))
         + N' sec=' + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20));
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

SET @Msg = N'===== 590→597→613 ALL DONE total_sec='
         + CAST(DATEDIFF(SECOND, @tAll, SYSDATETIME()) AS VARCHAR(20)) + N' =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

SELECT 'INV' K, COUNT_BIG(*) N FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)
UNION ALL
SELECT 'DEBT', COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
 WHERE ISNULL(IOCODE,0)=0 AND ABYS_ID IS NOT NULL
UNION ALL
SELECT 'PAY', COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
 WHERE ISNULL(IOCODE,0)=1
UNION ALL
SELECT 'INST_PLAN', COUNT_BIG(*) FROM dbo.LS_005_01_INSTALLMENT_PLAN WITH (NOLOCK)
 WHERE ABYS_ID IS NOT NULL
UNION ALL
SELECT 'DEBT_INST', COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
 WHERE ISNULL(IOCODE,0)=0 AND ISNULL(INST_NR,0)>0 AND ISNULL(CANCELED,0)=0;
GO
