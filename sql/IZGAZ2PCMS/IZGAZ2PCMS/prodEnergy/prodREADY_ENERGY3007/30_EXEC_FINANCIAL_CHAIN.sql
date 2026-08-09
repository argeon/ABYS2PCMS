/* =============================================================================
   prodREADY_ENERGY3007 / 30_EXEC_FINANCIAL_CHAIN.sql
   Energy cutover — finansal zincir EXEC (acik parametreler).

   Onkosul:
     - 10f SP deploy OK (571/581/575 + 590/597 + 611/613)
     - 10_setup_and_map (MAP copy) yapildi
     - 00 gate PASS
     - @AGR_ID: NULL=FULL | >0=tek AGR | -1=NO_AGR (30b tercih)

   SIRA:
     E1  571 INVOICE
     E2  581 INVLINES
     E3  575 DEBT PAYTRANS
     E4  590_ALL (eksilten)  → GATE_PASS
     E5  597_ALL (tahsilat)  → GATE_PASS
     E6  35 bankref          (ayri dosya: 35_bankref_resolve_abys.sql)
     E7  611 installment plan + wire
     E8  613 split (varsa)
     E9  40 IPP              (ayri: 40_installment_plan_pay_apply.sql @DRY_RUN=0)
     E10 92 STG close        (ayri: ../90_afl_frk/92_stg_inv_pay_close_apply.sql)
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

/* >>> OPERATOR: NULL=FULL | >0=AGR | -1=NO_AGR <<< */
DECLARE @AGR_ID BIGINT = NULL;
-- SET @AGR_ID = 197168;
-- SET @AGR_ID = 1034469;
-- SET @AGR_ID = -1;

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121)
    + ' | FINANCIAL CHAIN START AGR='
    + CASE WHEN @AGR_ID IS NULL THEN 'FULL' WHEN @AGR_ID = -1 THEN 'NO_AGR' ELSE CAST(@AGR_ID AS VARCHAR(20)) END;

/* ---- SP varlık kontrol ---- */
IF OBJECT_ID('dbo.SP_MIGRATE_LS005_INVOICE', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIGRATE_LS005_INVLINES', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_590_ALL', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_597_ALL', 'P') IS NULL
BEGIN
    RAISERROR('Kritik SP eksik — once 10f deploy (571/581/575 + 10→19 + 20→29).', 16, 1);
    RETURN;
END

/* =============================================================================
   E1) 571 — ANA INVOICE
   ============================================================================= */
PRINT '========== E1) 571 INVOICE ==========';
EXEC dbo.SP_MIGRATE_LS005_INVOICE
    @BATCH_SIZE = 50000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @AGR_ID     = @AGR_ID,
    @DEBUG      = 1;

/* =============================================================================
   E2) 581 — INVLINES
   ============================================================================= */
PRINT '========== E2) 581 INVLINES ==========';
EXEC dbo.SP_MIGRATE_LS005_INVLINES
    @BATCH_SIZE = 100000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @RANGE_MODE = 'KEYSET',
    @DEBUG      = 1;

/* =============================================================================
   E3) 575 — DEBT PAYTRANS
   Not: Oracle O14 ile AYNI ANDA cift yazma YASAK.
   ============================================================================= */
PRINT '========== E3) 575 DEBT PAYTRANS ==========';
EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
    @BATCH_SIZE = 50000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @AGR_ID     = @AGR_ID,
    @DEBUG      = 1;

/* =============================================================================
   E4) 590 — EKSILTEN OVERLAY (INSERT→WIRE→GATE)
   ============================================================================= */
PRINT '========== E4) 590_ALL EKSILTEN ==========';
EXEC dbo.SP_MIG_590_ALL
    @AGR_ID = @AGR_ID,
    @CLEAN  = 1,
    @DEBUG  = 1;
-- GATE_FAIL → buradan sonra devam ETME

/* =============================================================================
   E5) 597 — TAHSILAT OVERLAY (INSERT→WIRE→GATE)
   ============================================================================= */
PRINT '========== E5) 597_ALL TAHSILAT ==========';
EXEC dbo.SP_MIG_597_ALL
    @AGR_ID = @AGR_ID,
    @CLEAN  = 1,
    @DEBUG  = 1;
-- GATE_FAIL → bank/taksit calistirma

/* =============================================================================
   E6) BANK — ayri script (35)
   ============================================================================= */
PRINT '========== E6) BANKREF — calistir: 35_bankref_resolve_abys.sql ==========';
PRINT '   SET @AGR_ID = ' + CAST(@AGR_ID AS VARCHAR(20)) + '; SET @DRY_RUN = 0;';

/* =============================================================================
   E7) 611 — INSTALLMENT PLAN + WIRE
   ============================================================================= */
PRINT '========== E7) 611 INSTALLMENT PLAN ==========';
IF OBJECT_ID('dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN', 'P') IS NOT NULL
    EXEC dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
        @BATCH_SIZE = 5000,
        @RESUME     = 1,
        @HARD_RESET = 0,
        @AGR_ID     = @AGR_ID,
        @DEBUG      = 1;
ELSE
    PRINT 'SKIP: SP_MIGRATE_LS005_INSTALLMENT_PLAN yok';

IF OBJECT_ID('dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE', 'P') IS NOT NULL
    EXEC dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE
        @AGR_ID = @AGR_ID,
        @DEBUG  = 1;
ELSE
    PRINT 'SKIP: SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE yok';

/* =============================================================================
   E8) 613 — DEBT SPLIT (AGR)
   ============================================================================= */
PRINT '========== E8) 613 SPLIT ==========';
IF OBJECT_ID('dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR', 'P') IS NOT NULL
    EXEC dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR
        @AGR_ID = @AGR_ID,
        @DEBUG  = 1;
ELSE
    PRINT 'SKIP: SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR yok';

IF OBJECT_ID('dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR', 'P') IS NOT NULL
    EXEC dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR
        @AGR_ID = @AGR_ID,
        @DEBUG  = 1;
ELSE
    PRINT 'SKIP: SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR yok — 80_613_taksit__STANDALONE.sql';

/* =============================================================================
   E9–E10) IPP + 92 — ayri dosyalar
   ============================================================================= */
PRINT '========== E9) IPP — 40_installment_plan_pay_apply.sql @DRY_RUN=0 @AGR_ID ==========';
PRINT '========== E10) 92 — ../90_afl_frk/92_stg_inv_pay_close_apply.sql @DRY_RUN=0 ==========';
PRINT '========== E11) 90_check_queries.sql ==========';

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121)
    + ' | FINANCIAL CHAIN CORE DONE AGR='
    + CASE WHEN @AGR_ID IS NULL THEN 'FULL' WHEN @AGR_ID = -1 THEN 'NO_AGR' ELSE CAST(@AGR_ID AS VARCHAR(20)) END;
PRINT 'Sonraki: 35 bank → 40 IPP → 92 close → 90 check';
PRINT 'FULL icin tercih: 30c_EXEC_FULL_CHAIN.sql (@AGR_ID=NULL + 00d index guard)';
GO
