/* ============================================================
   FILE : prodEnergy/80_613_taksit__STANDALONE.sql
   FAZ  : B8 — TAKSIT (613) TEK BASINA
   Zorunlu B1-B7 zincirini BLOKE ETMEZ; maliyet yuksek — istege bagli

   Onkosul:
     - 590 + 597 bitmis
     - UX_LS005_PAYTRANS_DEBT_INVOICEREF DROP (invoice basina 1 borc UX
       split ile Msg 2601 verir — asagida drop)

   Bu dosya: guvenli UX hazirlik + mevcut 613 runner'a yonlendirme.
   FULL AGR dongusu BURADA OTOMATIK BASLATILMAZ (@RUN_FULL=0 default).

   @RUN_FULL = 1 → adim_590_597_then_613 icindeki 613 bolumu mantigi
                   (AGRs over INSTALLMENT_PLAN) — uzun surer
   ============================================================ */
USE energy;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;

DECLARE @RUN_FULL BIT = 0;   -- 1 yapmadan once timing/disk kontrol
DECLARE @DEBUG    BIT = 1;
DECLARE @Msg NVARCHAR(400);

SET @Msg = N'===== 613 STANDALONE ' + CONVERT(VARCHAR(30), SYSDATETIME(), 121) + N' =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

/* 1) UX — taksit split ile uyumsuz (Known Issues §3) */
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
      AND name = 'UX_LS005_PAYTRANS_DEBT_INVOICEREF'
)
BEGIN
    DROP INDEX UX_LS005_PAYTRANS_DEBT_INVOICEREF ON dbo.LS_005_01_PAYTRANS;
    RAISERROR('DROP UX_LS005_PAYTRANS_DEBT_INVOICEREF OK', 0, 1) WITH NOWAIT;
END
ELSE
    RAISERROR('UX_LS005_PAYTRANS_DEBT_INVOICEREF yok (OK)', 0, 1) WITH NOWAIT;

/* TODO (sonra): filtered unique (INVOICEREF, INST_NR) WHERE CANCELED=0 IOCODE=0 */

/* 2) Wire (hafif) — plan→invoice */
IF OBJECT_ID('energy.dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE', 'P') IS NOT NULL
BEGIN
    EXEC energy.dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE @AGR_ID = NULL, @DEBUG = @DEBUG;
    RAISERROR('WIRE INSTALLMENT_PLAN OK', 0, 1) WITH NOWAIT;
END
ELSE
    RAISERROR('SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE yok — setup 613 gerekli', 0, 1) WITH NOWAIT;

IF @RUN_FULL = 0
BEGIN
    RAISERROR('RUN_FULL=0 — NORMALIZE+SPLIT BASLATILMADI.', 0, 1) WITH NOWAIT;
    RAISERROR('Tam kosu: repo kokunde adim_590_597_then_613.sql (sadece 613 bolumu)', 0, 1) WITH NOWAIT;
    RAISERROR('veya adim_613_serial_fast.sql / adim_613_parallel_worker.sql', 0, 1) WITH NOWAIT;
    RAISERROR('Bu dosyada @RUN_FULL=1 ile asagidaki dongu acilir.', 0, 1) WITH NOWAIT;
    RETURN;
END

/* ---- @RUN_FULL=1: AGR bazli normalize+split (mevcut SP — adim_590_597_then_613 ile ayni) ---- */
IF OBJECT_ID('energy.dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR', 'P') IS NULL
   OR OBJECT_ID('energy.dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR', 'P') IS NULL
BEGIN
    RAISERROR('613 SP eksik. 613_INSTALLMENT_DEBT_SPLIT__pilot_agr.sql deploy edin.', 16, 1);
    RETURN;
END

DECLARE @i INT = 1, @n INT, @AGR_ID BIGINT;
DECLARE @try INT, @ok BIT;
DECLARE @t0 DATETIME2(3) = SYSDATETIME();

IF OBJECT_ID('tempdb..#Agr613') IS NOT NULL DROP TABLE #Agr613;
CREATE TABLE #Agr613 (ORD INT NOT NULL PRIMARY KEY, AGR_ID BIGINT NOT NULL);

INSERT INTO #Agr613 (ORD, AGR_ID)
SELECT ROW_NUMBER() OVER (ORDER BY AGR_ID), AGR_ID
FROM (
    SELECT DISTINCT pl.ABYS_AGREEMENT_ID AS AGR_ID
    FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
    WHERE pl.ABYS_AGREEMENT_ID IS NOT NULL
) x;

SELECT @n = COUNT(*) FROM #Agr613;
SET @Msg = N'613 AGR_CNT=' + CAST(@n AS VARCHAR(20));
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

WHILE @i <= @n
BEGIN
    SELECT @AGR_ID = AGR_ID FROM #Agr613 WHERE ORD = @i;
    SET @try = 0;
    SET @ok = 0;

    WHILE @ok = 0 AND @try < 5
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

    IF @DEBUG = 1 AND (@i % 100 = 0 OR @i = @n OR @i = 1)
    BEGIN
        SET @Msg = N'613 ' + CAST(@i AS VARCHAR(10)) + N'/' + CAST(@n AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
    SET @i += 1;
END

DECLARE @MaxLref BIGINT;
SELECT @MaxLref = ISNULL(MAX(LREF), 0) FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK);
DBCC CHECKIDENT('energy.dbo.LS_005_01_PAYTRANS', RESEED, @MaxLref) WITH NO_INFOMSGS;

SET @Msg = N'===== 613 STANDALONE DONE sec='
    + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20)) + N' =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
GO
