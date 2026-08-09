/* ============================================================
   FILE : adim_597_resume.sql
   597 TAHSILAT resume — @CLEAN=0
   NOT EXISTS ile TAH INV / PAY PT kaldigi yerden devam eder.
   590 SKIP (bitmis varsayilir). 613 SKIP.
   Kullanim: mevcut run KILL edildikten SONRA veya run bittikten sonra.
   ============================================================ */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @Msg NVARCHAR(400);
DECLARE @tAll DATETIME2(3) = SYSDATETIME();
DECLARE @t0 DATETIME2(3);

SET @Msg = N'===== 597 RESUME (@CLEAN=0) START ' + CONVERT(VARCHAR(30), @tAll, 121) + N' =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
RAISERROR('NOTE: 590 SKIP; 613 SKIP; MAXDOP 24 hints in SP', 0, 1) WITH NOWAIT;

SET @t0 = SYSDATETIME();
EXEC energy.dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR
    @AGR_ID = NULL, @CLEAN = 0, @DEBUG = 1;

SET @Msg = N'===== 597 DONE sec=' + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20))
         + N' | total_sec=' + CAST(DATEDIFF(SECOND, @tAll, SYSDATETIME()) AS VARCHAR(20))
         + N' | 613 SKIPPED =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

SELECT 'INV' K, COUNT_BIG(*) N FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)
UNION ALL
SELECT 'PAY_IO1', COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK) WHERE ISNULL(IOCODE,0)=1
UNION ALL
SELECT 'OV_PAY_SRC', COUNT_BIG(*) FROM izgazMGR.dbo.LS_OV_PAY_PT WITH (NOLOCK)
UNION ALL
SELECT 'OV_TAH_SRC', COUNT_BIG(*) FROM izgazMGR.dbo.LS_OV_TAH_INVOICE WITH (NOLOCK);
GO
