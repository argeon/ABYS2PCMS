/* ============================================================
   FILE : adim_full_fatura_run.sql
   Full fatura zinciri — varsayilan: KATMAN (AGR loop YOK)

   Onkosul:
     - Oracle CTAS full + Migratorv0 → izgazMGR
     - adim3_verify_indexes.sql
     - Deploy: 571 v9+, 575 v3+, 581, 611 key-list, 590/597__full, 613

   Modlar:
     @MODE = 'LAYER' → adim_full_layer_run.sql mantigi (onerilen full)
     @MODE = 'NULL'  → ayni LAYER (alias)
     @MODE = 'LOOP'  → DISTINCT AGR (yalniz canary / kucuk; full'de YAVAS)

   Performans:
     Pilot AGR loop yavasliginin kok nedeni: BETWEEN min-max seyrek ID.
     571/575/611 artik #MIG_*_BATCH_KEYS equality join kullanir.
     Full icin LAYER + @BATCH=50000 tercih edin.
   ============================================================ */
USE energy;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @DEBUG BIT = 1;
DECLARE @BATCH INT = 50000;
DECLARE @CLEAN BIT = 1;
DECLARE @HARD_RESET BIT = 0;
DECLARE @RESUME BIT = 0;
DECLARE @DO_INVLINES BIT = 1;
DECLARE @DO_DEBT BIT = 1;
DECLARE @DO_INSTALLMENT BIT = 1;
DECLARE @DO_EKSILTEN BIT = 1;
DECLARE @DO_TAHSILAT BIT = 1;
/* 'LAYER' | 'NULL' | 'LOOP' — full icin LAYER */
DECLARE @MODE VARCHAR(10) = 'LAYER';

DECLARE @Msg NVARCHAR(400);
DECLARE @AGR_ID BIGINT = NULL;

IF @MODE IN ('LAYER', 'NULL')
BEGIN
    SET @Msg = N'===== FULL MODE LAYER (katman; AGR loop yok) batch='
             + CAST(@BATCH AS VARCHAR(20)) + N' =====';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* 1) INVOICE */
    SET @Msg = N'===== LAYER 1/8 INVOICE (571) =====';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    EXEC energy.dbo.SP_MIGRATE_LS005_INVOICE
        @AGR_ID = NULL, @RESUME = @RESUME, @HARD_RESET = @HARD_RESET,
        @BATCH_SIZE = @BATCH, @DEBUG = @DEBUG;

    IF OBJECT_ID('energy.dbo.SP_MIG_INVOICE_POST_INDEXES', 'P') IS NOT NULL
        EXEC energy.dbo.SP_MIG_INVOICE_POST_INDEXES @DEBUG = @DEBUG;

    /* 2) INVLINES — full KEYSET (588 AGR degil) */
    IF @DO_INVLINES = 1
       AND OBJECT_ID('energy.dbo.SP_MIGRATE_LS005_INVLINES', 'P') IS NOT NULL
    BEGIN
        SET @Msg = N'===== LAYER 2/8 INVLINES (581) =====';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

        EXEC energy.dbo.SP_MIGRATE_LS005_INVLINES
            @RESUME = @RESUME, @HARD_RESET = @HARD_RESET,
            @BATCH_SIZE = @BATCH, @RANGE_MODE = 'KEYSET', @DEBUG = @DEBUG;
    END

    /* 3) DEBT */
    IF @DO_DEBT = 1
    BEGIN
        SET @Msg = N'===== LAYER 3/8 DEBT PAYTRANS (575) =====';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

        EXEC energy.dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
            @AGR_ID = NULL, @RESUME = @RESUME, @HARD_RESET = @HARD_RESET,
            @BATCH_SIZE = @BATCH, @DEBUG = @DEBUG;
    END

    /* 4) INSTALLMENT PLAN */
    IF @DO_INSTALLMENT = 1
       AND OBJECT_ID('energy.dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN', 'P') IS NOT NULL
    BEGIN
        SET @Msg = N'===== LAYER 4/8 INSTALLMENT PLAN (611) =====';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

        EXEC energy.dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
            @AGR_ID = NULL, @HARD_RESET = @HARD_RESET, @RESUME = @RESUME,
            @BATCH_SIZE = @BATCH, @DEBUG = @DEBUG;
    END

    /* 5) normalize+split — sadece plani olan AGR */
    IF @DO_INSTALLMENT = 1
       AND OBJECT_ID('energy.dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR', 'P') IS NOT NULL
    BEGIN
        SET @Msg = N'===== LAYER 5/8 INSTALLMENT NORMALIZE+SPLIT =====';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

        DECLARE @AgrLayer TABLE (ORD INT IDENTITY(1,1) PRIMARY KEY, AGR_ID BIGINT NOT NULL);
        INSERT INTO @AgrLayer (AGR_ID)
        SELECT DISTINCT pl.ABYS_AGREEMENT_ID
        FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
        WHERE pl.ABYS_ID IS NOT NULL
          AND pl.ABYS_AGREEMENT_ID IS NOT NULL
        ORDER BY pl.ABYS_AGREEMENT_ID;

        DECLARE @iL INT = 1, @nL INT;
        SELECT @nL = COUNT(*) FROM @AgrLayer;
        SET @Msg = N'Plan AGR_CNT=' + CAST(@nL AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

        WHILE @iL <= @nL
        BEGIN
            SELECT @AGR_ID = AGR_ID FROM @AgrLayer WHERE ORD = @iL;
            SET @Msg = N'--- 613 AGR ' + CAST(@AGR_ID AS VARCHAR(20))
                     + N' (' + CAST(@iL AS VARCHAR(10)) + N'/' + CAST(@nL AS VARCHAR(10)) + N') ---';
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

            EXEC energy.dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR
                @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;

            IF OBJECT_ID('energy.dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR', 'P') IS NOT NULL
                EXEC energy.dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR
                    @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;

            SET @iL += 1;
        END
    END

    /* 6) EKSILTEN */
    IF @DO_EKSILTEN = 1
       AND OBJECT_ID('energy.dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR', 'P') IS NOT NULL
       AND OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_INVOICE', 'U') IS NOT NULL
    BEGIN
        SET @Msg = N'===== LAYER 6/8 EKSILTEN (590) NULL =====';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

        EXEC energy.dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR
            @AGR_ID = NULL, @CLEAN = @CLEAN, @DEBUG = @DEBUG;
    END

    /* 7) TAHSILAT */
    IF @DO_TAHSILAT = 1
       AND OBJECT_ID('energy.dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR', 'P') IS NOT NULL
       AND OBJECT_ID('izgazMGR.dbo.LS_OV_PAY_PT', 'U') IS NOT NULL
    BEGIN
        SET @Msg = N'===== LAYER 7/8 TAHSILAT (597) NULL =====';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

        EXEC energy.dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR
            @AGR_ID = NULL, @CLEAN = @CLEAN, @DEBUG = @DEBUG;
    END

    SET @Msg = N'===== FULL LAYER DONE =====';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END
ELSE
BEGIN
    /* LOOP: canary / kucuk set — full production icin kullanmayin */
    DECLARE @Agr TABLE (
        ORD INT IDENTITY(1,1) PRIMARY KEY,
        AGR_ID BIGINT NOT NULL
    );

    INSERT INTO @Agr (AGR_ID)
    SELECT AGR_ID
    FROM (
        SELECT DISTINCT TRY_CAST(ABYS_AGREEMENT_ID AS BIGINT) AS AGR_ID
        FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
        WHERE TRY_CAST(ABYS_AGREEMENT_ID AS BIGINT) IS NOT NULL
    ) d
    ORDER BY AGR_ID;

    DECLARE @i INT = 1, @n INT;
    SELECT @n = COUNT(*) FROM @Agr;
    SET @Msg = N'===== FULL MODE LOOP AGR_CNT=' + CAST(@n AS VARCHAR(20))
             + N' (UYARI: full icin YAVAS; LAYER kullanin) =====';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    WHILE @i <= @n
    BEGIN
        SELECT @AGR_ID = AGR_ID FROM @Agr WHERE ORD = @i;
        SET @Msg = N'===== AGR ' + CAST(@AGR_ID AS VARCHAR(20))
                 + N' (' + CAST(@i AS VARCHAR(10)) + N'/' + CAST(@n AS VARCHAR(10)) + N') =====';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

        EXEC energy.dbo.SP_MIGRATE_LS005_INVOICE
            @AGR_ID = @AGR_ID, @RESUME = 0, @HARD_RESET = 0,
            @BATCH_SIZE = @BATCH, @DEBUG = @DEBUG;

        IF @DO_INVLINES = 1 AND OBJECT_ID('energy.dbo.SP_MIGRATE_LS005_INVLINES_AGR', 'P') IS NOT NULL
            EXEC energy.dbo.SP_MIGRATE_LS005_INVLINES_AGR
                @AGR_ID = @AGR_ID, @CLEAN = @CLEAN, @BATCH_SIZE = @BATCH, @DEBUG = @DEBUG;

        IF @DO_DEBT = 1
            EXEC energy.dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
                @AGR_ID = @AGR_ID, @RESUME = 0, @HARD_RESET = 0,
                @BATCH_SIZE = @BATCH, @DEBUG = @DEBUG;

        IF @DO_INSTALLMENT = 1
           AND OBJECT_ID('energy.dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN', 'P') IS NOT NULL
            EXEC energy.dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
                @AGR_ID = @AGR_ID, @HARD_RESET = @HARD_RESET, @RESUME = 0,
                @BATCH_SIZE = @BATCH, @DEBUG = @DEBUG;

        IF @DO_INSTALLMENT = 1
           AND OBJECT_ID('energy.dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR', 'P') IS NOT NULL
            EXEC energy.dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR
                @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;

        IF @DO_INSTALLMENT = 1
           AND OBJECT_ID('energy.dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR', 'P') IS NOT NULL
            EXEC energy.dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR
                @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;

        IF @DO_EKSILTEN = 1
           AND OBJECT_ID('energy.dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR', 'P') IS NOT NULL
           AND OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_INVOICE', 'U') IS NOT NULL
            EXEC energy.dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR
                @AGR_ID = @AGR_ID, @CLEAN = @CLEAN, @DEBUG = @DEBUG;

        IF @DO_TAHSILAT = 1
           AND OBJECT_ID('energy.dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR', 'P') IS NOT NULL
           AND OBJECT_ID('izgazMGR.dbo.LS_OV_PAY_PT', 'U') IS NOT NULL
            EXEC energy.dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR
                @AGR_ID = @AGR_ID, @CLEAN = @CLEAN, @DEBUG = @DEBUG;

        SET @i += 1;
    END
END

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
