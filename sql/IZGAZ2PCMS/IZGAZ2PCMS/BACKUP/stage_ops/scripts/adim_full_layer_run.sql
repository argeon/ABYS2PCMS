/* ============================================================
   FILE : adim_full_layer_run.sql
   Full energy aktarim — KATMAN KATMAN (AGR loop YOK)

   Onkosul:
     - Oracle CTAS full + Migratorv0 → izgazMGR
     - adim3_verify_indexes.sql
     - Deploy: 571 v9+, 575 v3+, 581, 611 key-list, 590/597__full, 613

   Sira:
     1) 571 INVOICE      @AGR_ID=NULL  (key-list batch)
     2) 572 post indexes (varsa)
     3) 581 INVLINES     @AGR_ID=NULL
     4) 575 DEBT PT      @AGR_ID=NULL  (key-list; Last+1 BETWEEN YOK)
     5) 611 INSTALLMENT  @AGR_ID=NULL, HARD_RESET=0
     6) 613 normalize+split — sadece plani olan AGR (kucuk loop)
     7) 590 EKSILTEN     @AGR_ID=NULL
     8) 597 TAHSILAT     @AGR_ID=NULL

   Kesilirse: ilgili SP @RESUME=1 ile ayni katmandan devam.
   Pilot canary icin: adim_multi_agr_pilot_run.sql
   ============================================================ */
USE energy;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @DEBUG BIT = 1;
DECLARE @HARD_RESET BIT = 0;         -- resume / temiz DB
DECLARE @RESUME BIT = 1;             -- kesilince devam
DECLARE @BATCH INT = 100000;         -- tarihi hizli batch (Jul17 ~3s/100k)
DECLARE @DO_INVLINES BIT = 1;
DECLARE @DO_DEBT BIT = 1;
DECLARE @DO_INSTALLMENT BIT = 1;
DECLARE @DO_EKSILTEN BIT = 1;
DECLARE @DO_TAHSILAT BIT = 1;
DECLARE @Msg NVARCHAR(400);

SET @Msg = N'===== FULL LAYER RUN start batch=' + CAST(@BATCH AS VARCHAR(20)) + N' =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

/* ---- 1) INVOICE ---- */
SET @Msg = N'===== LAYER 1/8 INVOICE (571) =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

EXEC energy.dbo.SP_MIGRATE_LS005_INVOICE
    @AGR_ID     = NULL,
    @RESUME     = @RESUME,
    @HARD_RESET = @HARD_RESET,
    @BATCH_SIZE = @BATCH,
    @DEBUG      = @DEBUG;

IF OBJECT_ID('energy.dbo.SP_MIG_INVOICE_POST_INDEXES', 'P') IS NOT NULL
    EXEC energy.dbo.SP_MIG_INVOICE_POST_INDEXES @DEBUG = @DEBUG;

/* ---- 2) INVLINES ---- */
IF @DO_INVLINES = 1
BEGIN
    SET @Msg = N'===== LAYER 2/8 INVLINES (581) =====';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    IF OBJECT_ID('energy.dbo.SP_MIGRATE_LS005_INVLINES', 'P') IS NOT NULL
        EXEC energy.dbo.SP_MIGRATE_LS005_INVLINES
            @RESUME     = @RESUME,
            @HARD_RESET = @HARD_RESET,
            @BATCH_SIZE = @BATCH,
            @DEBUG      = @DEBUG;
    ELSE IF OBJECT_ID('energy.dbo.SP_MIGRATE_LS005_INVLINES_AGR', 'P') IS NOT NULL
        RAISERROR('581 full SP yok; INVLINES icin AGR SP veya 581 deploy edin. Atlandi.', 0, 1) WITH NOWAIT;
END

/* ---- 3) DEBT PAYTRANS ---- */
IF @DO_DEBT = 1
BEGIN
    SET @Msg = N'===== LAYER 3/8 DEBT PAYTRANS (575) =====';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    EXEC energy.dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
        @AGR_ID     = NULL,
        @RESUME     = @RESUME,
        @HARD_RESET = @HARD_RESET,
        @BATCH_SIZE = @BATCH,
        @DEBUG      = @DEBUG;
END

/* ---- 4) INSTALLMENT PLAN ---- */
IF @DO_INSTALLMENT = 1
   AND OBJECT_ID('energy.dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN', 'P') IS NOT NULL
BEGIN
    SET @Msg = N'===== LAYER 4/8 INSTALLMENT PLAN (611) =====';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    EXEC energy.dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
        @AGR_ID     = NULL,
        @HARD_RESET = @HARD_RESET,
        @RESUME     = @RESUME,
        @BATCH_SIZE = @BATCH,
        @DEBUG      = @DEBUG;
END

/* ---- 5) NORMALIZE + SPLIT (plan AGR listesi) ---- */
IF @DO_INSTALLMENT = 1
   AND OBJECT_ID('energy.dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR', 'P') IS NOT NULL
BEGIN
    SET @Msg = N'===== LAYER 5/8 INSTALLMENT NORMALIZE+SPLIT (plan AGR) =====';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    DECLARE @Agr TABLE (ORD INT IDENTITY(1,1) PRIMARY KEY, AGR_ID BIGINT NOT NULL);
    INSERT INTO @Agr (AGR_ID)
    SELECT DISTINCT pl.ABYS_AGREEMENT_ID
    FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
    WHERE pl.ABYS_ID IS NOT NULL
      AND pl.ABYS_AGREEMENT_ID IS NOT NULL
    ORDER BY pl.ABYS_AGREEMENT_ID;

    DECLARE @i INT = 1, @n INT, @AGR_ID BIGINT;
    SELECT @n = COUNT(*) FROM @Agr;
    SET @Msg = N'Plan AGR_CNT=' + CAST(@n AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    WHILE @i <= @n
    BEGIN
        SELECT @AGR_ID = AGR_ID FROM @Agr WHERE ORD = @i;
        SET @Msg = N'--- 613 AGR ' + CAST(@AGR_ID AS VARCHAR(20))
                 + N' (' + CAST(@i AS VARCHAR(10)) + N'/' + CAST(@n AS VARCHAR(10)) + N') ---';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

        EXEC energy.dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR
            @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;

        IF OBJECT_ID('energy.dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR', 'P') IS NOT NULL
            EXEC energy.dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR
                @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;

        SET @i += 1;
    END
END

/* ---- 6) EKSILTEN ---- */
IF @DO_EKSILTEN = 1
   AND OBJECT_ID('energy.dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR', 'P') IS NOT NULL
   AND OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_INVOICE', 'U') IS NOT NULL
BEGIN
    SET @Msg = N'===== LAYER 6/8 EKSILTEN (590) NULL =====';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    EXEC energy.dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR
        @AGR_ID = NULL, @CLEAN = 1, @DEBUG = @DEBUG;
END

/* ---- 7) TAHSILAT ---- */
IF @DO_TAHSILAT = 1
   AND OBJECT_ID('energy.dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR', 'P') IS NOT NULL
   AND OBJECT_ID('izgazMGR.dbo.LS_OV_PAY_PT', 'U') IS NOT NULL
BEGIN
    SET @Msg = N'===== LAYER 7/8 TAHSILAT (597) NULL =====';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    EXEC energy.dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR
        @AGR_ID = NULL, @CLEAN = 1, @DEBUG = @DEBUG;
END

SET @Msg = N'===== FULL LAYER RUN DONE =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

SELECT 'ENERGY_INV' K, COUNT_BIG(*) N FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
UNION ALL
SELECT 'ENERGY_IL', COUNT_BIG(*) FROM energy.dbo.LS_005_01_INVLINES WITH (NOLOCK)
WHERE ABYS_ID IS NOT NULL
UNION ALL
SELECT 'ENERGY_DEBT_PT', COUNT_BIG(*) FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
 WHERE ISNULL(IOCODE, 0) = 0 AND ABYS_ID IS NOT NULL
UNION ALL
SELECT 'ENERGY_PAY_PT', COUNT_BIG(*) FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
 WHERE ISNULL(IOCODE, 0) = 1
UNION ALL
SELECT 'ENERGY_INST_PLAN', COUNT_BIG(*) FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN WITH (NOLOCK)
 WHERE ABYS_ID IS NOT NULL;
GO
