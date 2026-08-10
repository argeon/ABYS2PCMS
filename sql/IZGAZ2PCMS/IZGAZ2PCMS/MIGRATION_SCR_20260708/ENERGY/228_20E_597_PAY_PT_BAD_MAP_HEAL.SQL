/* =============================================================================
   prodREADY_ENERGY / 20e_597_PAY_PT_BAD_MAP_HEAL.sql
   R15: PAY_PT ENERGY_LREF → borç PT (IOCODE=0) adopt kirlenmesi
   ---------------------------------------------------------------
   Belirti (195 SQLMIG01):
     PAY_PT map ~66.8M dolu ama IOCODE=1 PT ~37M;
     ~30M map borç LREF'ine basılmış → tahsilat satırı yok.
   Kök: 597 hint adopt, LREF doluysa IOCODE bakmadan MAP+LOADED=1.

   Bu script:
     1) DRY sayım
     2) APPLY: EN (+opsiyonel MGR) PAY_PT/CANCEL_* map null (sadece IOCODE=0 hedef)
     3) STG_PAY/DEBT truncate (resume KEEP kötü LOADED'ı taşımasın)
     Borç PAYTRANS SİLMEZ.

   YASAK: bu heal öncesi @CLEAN=1 FULL — CLEAN map→PT DELETE borç satırını yer!

   Sonra (ayrı session):
     - 28_DEPLOY_597 (adopt fix'li 20) veya en az 20_597_INSERT redeploy
     - 20b_PAYTRANS_NCIX_DISABLE.sql
     - EXEC SP_MIG_597_ALL @AGR_ID=NULL, @CLEAN=0, @DEBUG=1, @BatchSize=250000
     - SP_MIG_597_GATE
     - 20c_PAYTRANS_NCIX_REBUILD.sql

   @DRY_RUN=1 sayim; 0=apply
   sqlcmd -S 172.16.1.195 -d energy -C -I -f 65001 -i 20e_597_PAY_PT_BAD_MAP_HEAL.sql
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET IMPLICIT_TRANSACTIONS OFF;

DECLARE @DRY_RUN BIT = 1;
DECLARE @NULL_MGR BIT = 1;          /* offline MGR map null — hot path degil */
DECLARE @Batch INT = 500000;
DECLARE @DryRunInt INT = CAST(@DRY_RUN AS INT);
DECLARE @NullMgrInt INT = CAST(@NULL_MGR AS INT);
DECLARE @N BIGINT;
DECLARE @Upd INT;
DECLARE @Total BIGINT = 0;
DECLARE @Msg NVARCHAR(400);
DECLARE @t0 DATETIME2 = SYSDATETIME();

RAISERROR('========== 20e PAY_PT BAD MAP HEAL DRY_RUN=%d NULL_MGR=%d ==========', 0, 1, @DryRunInt, @NullMgrInt) WITH NOWAIT;

IF OBJECT_ID('dbo.MIG_OV_ID_MAP', 'U') IS NULL
   OR OBJECT_ID('dbo.LS_005_01_PAYTRANS', 'U') IS NULL
BEGIN
    RAISERROR('MIG_OV_ID_MAP / PAYTRANS yok', 16, 1);
    RETURN;
END

/* ---- 1) Probe ---- */
SELECT @N = COUNT_BIG(*)
FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
INNER JOIN dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK) ON pt.LREF = m.ENERGY_LREF
WHERE m.OV_KIND IN (N'PAY_PT', N'CANCEL_PAY', N'CANCEL_REV')
  AND m.ENERGY_LREF IS NOT NULL
  AND pt.IOCODE = 0
OPTION (RECOMPILE, MAXDOP 8);
SET @Msg = N'EN bad map (PAY*→IOCODE=0)=' + CAST(@N AS VARCHAR(20));
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

SELECT
    pt.IOCODE,
    pt.PAYTYPE,
    COUNT_BIG(*) AS cnt
FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
INNER JOIN dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK) ON pt.LREF = m.ENERGY_LREF
WHERE m.OV_KIND = N'PAY_PT'
  AND m.ENERGY_LREF IS NOT NULL
GROUP BY pt.IOCODE, pt.PAYTYPE
ORDER BY cnt DESC
OPTION (RECOMPILE, MAXDOP 8);

IF @DRY_RUN = 1
BEGIN
    RAISERROR('DRY_RUN=1 — APPLY icin dosyada @DRY_RUN=0', 0, 1) WITH NOWAIT;
    RETURN;
END

IF @N = 0
BEGIN
    RAISERROR('Bad map=0 — EN null skip; STG truncate yine yapilacak', 0, 1) WITH NOWAIT;
END
ELSE
BEGIN
    /* ---- 2) EN MAP null (keyset batch via temp physical stg) ---- */
    IF OBJECT_ID('dbo.MIG_20E_STG_BAD_KEYS', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.MIG_20E_STG_BAD_KEYS (
            SRC_KEY VARCHAR(80) NOT NULL,
            CONSTRAINT PK_MIG_20E_STG_BAD_KEYS PRIMARY KEY CLUSTERED (SRC_KEY)
        );
    END

    SET @Total = 0;
    WHILE 1 = 1
    BEGIN
        TRUNCATE TABLE dbo.MIG_20E_STG_BAD_KEYS;

        INSERT INTO dbo.MIG_20E_STG_BAD_KEYS (SRC_KEY)
        SELECT TOP (@Batch) m.SRC_KEY
        FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
        INNER JOIN dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK) ON pt.LREF = m.ENERGY_LREF
        WHERE m.OV_KIND IN (N'PAY_PT', N'CANCEL_PAY', N'CANCEL_REV')
          AND m.ENERGY_LREF IS NOT NULL
          AND pt.IOCODE = 0
        ORDER BY m.SRC_KEY
        OPTION (RECOMPILE, MAXDOP 8);

        SET @Upd = @@ROWCOUNT;
        IF @Upd = 0 BREAK;

        UPDATE m
        SET m.ENERGY_LREF = NULL
        FROM dbo.MIG_OV_ID_MAP m
        INNER JOIN dbo.MIG_20E_STG_BAD_KEYS b ON b.SRC_KEY = m.SRC_KEY
        WHERE m.OV_KIND IN (N'PAY_PT', N'CANCEL_PAY', N'CANCEL_REV')
          AND m.ENERGY_LREF IS NOT NULL
        OPTION (RECOMPILE, MAXDOP 8, FORCE ORDER);

        SET @Total = @Total + @@ROWCOUNT;
        SET @Msg = N'EN MAP null +' + CAST(@Upd AS VARCHAR(20))
                 + N' total=' + CAST(@Total AS VARCHAR(20))
                 + N' elapsed_s=' + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    SET @Msg = N'EN MAP null done total=' + CAST(@Total AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END

/* ---- 3) MGR MAP null (ayni SRC_KEY set — offline) ---- */
IF @NULL_MGR = 1
   AND OBJECT_ID('izgazMGR.dbo.LS_OV_ID_MAP', 'U') IS NOT NULL
BEGIN
    SET @Total = 0;
    WHILE 1 = 1
    BEGIN
        IF OBJECT_ID('dbo.MIG_20E_STG_BAD_KEYS', 'U') IS NULL
        BEGIN
            CREATE TABLE dbo.MIG_20E_STG_BAD_KEYS (
                SRC_KEY VARCHAR(80) NOT NULL,
                CONSTRAINT PK_MIG_20E_STG_BAD_KEYS PRIMARY KEY CLUSTERED (SRC_KEY)
            );
        END
        TRUNCATE TABLE dbo.MIG_20E_STG_BAD_KEYS;

        INSERT INTO dbo.MIG_20E_STG_BAD_KEYS (SRC_KEY)
        SELECT TOP (@Batch) mgr.SRC_KEY
        FROM izgazMGR.dbo.LS_OV_ID_MAP mgr WITH (NOLOCK)
        INNER JOIN dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK) ON pt.LREF = mgr.ENERGY_LREF
        WHERE mgr.OV_KIND IN (N'PAY_PT', N'CANCEL_PAY', N'CANCEL_REV')
          AND mgr.ENERGY_LREF IS NOT NULL
          AND pt.IOCODE = 0
        ORDER BY mgr.SRC_KEY
        OPTION (RECOMPILE, MAXDOP 8);

        SET @Upd = @@ROWCOUNT;
        IF @Upd = 0 BREAK;

        UPDATE mgr
        SET mgr.ENERGY_LREF = NULL
        FROM izgazMGR.dbo.LS_OV_ID_MAP mgr
        INNER JOIN dbo.MIG_20E_STG_BAD_KEYS b ON b.SRC_KEY = mgr.SRC_KEY
        WHERE mgr.OV_KIND IN (N'PAY_PT', N'CANCEL_PAY', N'CANCEL_REV')
          AND mgr.ENERGY_LREF IS NOT NULL
        OPTION (RECOMPILE, MAXDOP 8, FORCE ORDER);

        SET @Total = @Total + @@ROWCOUNT;
        SET @Msg = N'MGR MAP null +' + CAST(@Upd AS VARCHAR(20))
                 + N' total=' + CAST(@Total AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
    SET @Msg = N'MGR MAP null done total=' + CAST(@Total AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END

/* ---- 4) STG wipe — LOADED=1 bad resume engeli ---- */
IF OBJECT_ID('dbo.MIG_597_STG_PAY', 'U') IS NOT NULL
BEGIN
    TRUNCATE TABLE dbo.MIG_597_STG_PAY;
    RAISERROR('TRUNCATE MIG_597_STG_PAY', 0, 1) WITH NOWAIT;
END
IF OBJECT_ID('dbo.MIG_597_STG_DEBT_LOOKUP', 'U') IS NOT NULL
BEGIN
    TRUNCATE TABLE dbo.MIG_597_STG_DEBT_LOOKUP;
    RAISERROR('TRUNCATE MIG_597_STG_DEBT_LOOKUP', 0, 1) WITH NOWAIT;
END
IF OBJECT_ID('dbo.MIG_597_STG_KEYS', 'U') IS NOT NULL
BEGIN
    TRUNCATE TABLE dbo.MIG_597_STG_KEYS;
    RAISERROR('TRUNCATE MIG_597_STG_KEYS', 0, 1) WITH NOWAIT;
END
IF OBJECT_ID('dbo.MIG_597_STG_MAP_OUT', 'U') IS NOT NULL
    TRUNCATE TABLE dbo.MIG_597_STG_MAP_OUT;

/* ---- 5) Post count ---- */
SELECT @N = COUNT_BIG(*)
FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
INNER JOIN dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK) ON pt.LREF = m.ENERGY_LREF
WHERE m.OV_KIND IN (N'PAY_PT', N'CANCEL_PAY', N'CANCEL_REV')
  AND m.ENERGY_LREF IS NOT NULL
  AND pt.IOCODE = 0
OPTION (RECOMPILE, MAXDOP 8);
SET @Msg = N'POST bad map left=' + CAST(@N AS VARCHAR(20)) + N' (0 beklenir)';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

SELECT
    (SELECT COUNT_BIG(*) FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
     WHERE OV_KIND = N'PAY_PT' AND ENERGY_LREF IS NULL) AS en_pay_null,
    (SELECT COUNT_BIG(*) FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
     WHERE OV_KIND = N'PAY_PT' AND ENERGY_LREF IS NOT NULL) AS en_pay_filled;

RAISERROR('========== 20e DONE — sonra: deploy 20 (adopt fix) → 20b → ALL @CLEAN=0 → GATE → 20c ==========', 0, 1) WITH NOWAIT;
GO
