/* ============================================================
   FILE : adim_multi_agr_pilot_run.sql
   Coklu pilot sozlesme aktarimi (energy)

   AGR seti (Oracle MIG_PARAM ile ayni):
     276503, 556305, 197168, 5727, 2221, 978259, 1192595

   Onkosul:
     - Oracle CTAS + dump → izgazMGR (LS_INVOICE / INVLINES / OV_* / CS_INSTALLMENT*)
     - energy: 569/570/571, 574/575, 588, 590, 597, 610/611/613 deploy edilmis
     - LS_005_01_AGR ilgili AGREEMENT_NUMBER kayitlari mevcut

   Not:
     - Her AGR ayri CLEAN + INSERT (tek @AGR_ID SP'ler bozulmaz)
     - Overlay adimlari (4a/5) dump yoksa atlanir (OBJECT_ID kontrol)
     - Taksit: 611 → CANCEL_NORMALIZE → SPLIT → 590/597
   ============================================================ */
USE energy;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @DEBUG BIT = 1;
DECLARE @BATCH INT = 1000;
DECLARE @CLEAN BIT = 1;
DECLARE @HARD_RESET BIT = 1;
DECLARE @DO_INVLINES BIT = 1;
DECLARE @DO_INSTALLMENT BIT = 1;
DECLARE @DO_EKSILTEN BIT = 1;
DECLARE @DO_TAHSILAT BIT = 1;

DECLARE @Agr TABLE (
    ORD INT IDENTITY(1,1) PRIMARY KEY,
    AGR_ID BIGINT NOT NULL
);

INSERT INTO @Agr (AGR_ID) VALUES
    (276503),
    (556305),
    (197168),
    (5727),
    (2221),
    (978259),
    (1192595);

DECLARE @i INT = 1, @n INT, @AGR_ID BIGINT, @Msg NVARCHAR(400);

SELECT @n = COUNT(*) FROM @Agr;

WHILE @i <= @n
BEGIN
    SELECT @AGR_ID = AGR_ID FROM @Agr WHERE ORD = @i;

    SET @Msg = N'===== AGR ' + CAST(@AGR_ID AS VARCHAR(20))
             + N' (' + CAST(@i AS VARCHAR(10)) + N'/' + CAST(@n AS VARCHAR(10)) + N') =====';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* 1) INVOICE */
    EXEC energy.dbo.SP_MIGRATE_LS005_INVOICE
        @AGR_ID     = @AGR_ID,
        @RESUME     = 0,
        @HARD_RESET = 0,
        @BATCH_SIZE = @BATCH,
        @DEBUG      = @DEBUG;

    /* 2) INVLINES (opsiyonel) */
    IF @DO_INVLINES = 1 AND OBJECT_ID('energy.dbo.SP_MIGRATE_LS005_INVLINES_AGR', 'P') IS NOT NULL
    BEGIN
        EXEC energy.dbo.SP_MIGRATE_LS005_INVLINES_AGR
            @AGR_ID     = @AGR_ID,
            @CLEAN      = @CLEAN,
            @BATCH_SIZE = @BATCH,
            @DEBUG      = @DEBUG;
    END

    /* 3) BORC PAYTRANS */
    EXEC energy.dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
        @AGR_ID     = @AGR_ID,
        @RESUME     = 0,
        @HARD_RESET = 0,
        @BATCH_SIZE = @BATCH,
        @DEBUG      = @DEBUG;

    /* 4) INSTALLMENT_PLAN */
    IF @DO_INSTALLMENT = 1
       AND OBJECT_ID('energy.dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN', 'P') IS NOT NULL
    BEGIN
        EXEC energy.dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
            @AGR_ID     = @AGR_ID,
            @HARD_RESET = @HARD_RESET,
            @RESUME     = 0,
            @BATCH_SIZE = 5000,
            @DEBUG      = @DEBUG;
    END

    /* 4b) Iptal taksit normalize + aktif split (613) */
    IF @DO_INSTALLMENT = 1
       AND OBJECT_ID('energy.dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR', 'P') IS NOT NULL
        EXEC energy.dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR
            @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;

    IF @DO_INSTALLMENT = 1
       AND OBJECT_ID('energy.dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR', 'P') IS NOT NULL
        EXEC energy.dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR
            @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;

    /* 5) Eksilten overlay (Adim 4a) */
    IF @DO_EKSILTEN = 1
       AND OBJECT_ID('energy.dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR', 'P') IS NOT NULL
       AND OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_INVOICE', 'U') IS NOT NULL
    BEGIN
        EXEC energy.dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR
            @AGR_ID = @AGR_ID,
            @CLEAN  = @CLEAN,
            @DEBUG  = @DEBUG;
    END

    /* 6) Tahsilat overlay (Adim 5) */
    IF @DO_TAHSILAT = 1
       AND OBJECT_ID('energy.dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR', 'P') IS NOT NULL
       AND OBJECT_ID('izgazMGR.dbo.LS_OV_PAY_PT', 'U') IS NOT NULL
    BEGIN
        EXEC energy.dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR
            @AGR_ID = @AGR_ID,
            @CLEAN  = @CLEAN,
            @DEBUG  = @DEBUG;
    END

    SET @i += 1;
END

/* ---- Ozet ---- */
SELECT
    a.AGR_ID,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_INVOICE i WITH (NOLOCK)
      WHERE i.ABYS_AGREEMENT_ID = a.AGR_ID) AS INV_CNT,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_PAYTRANS p WITH (NOLOCK)
      WHERE p.ABYS_AGREEMENT_ID = a.AGR_ID AND ISNULL(p.IOCODE, 0) = 0) AS DEBT_PT,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_PAYTRANS p WITH (NOLOCK)
      WHERE p.ABYS_AGREEMENT_ID = a.AGR_ID AND ISNULL(p.IOCODE, 0) = 1) AS PAY_PT,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
      WHERE pl.ABYS_AGREEMENT_ID = a.AGR_ID AND pl.ABYS_ID IS NOT NULL) AS INST_PLAN
FROM @Agr a
ORDER BY a.ORD;
GO
