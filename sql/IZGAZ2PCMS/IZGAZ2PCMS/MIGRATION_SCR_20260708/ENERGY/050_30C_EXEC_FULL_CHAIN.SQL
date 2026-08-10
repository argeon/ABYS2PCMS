/* =============================================================================
   prodREADY_ENERGY3007 / 30c_EXEC_FULL_CHAIN.sql
   PROD TAM AKTARIM — @AGR_ID = NULL (FULL)

   Kapsar: sozlesmeli + NO_AGR (NULL AGR) fatura/tahsilat.
   30b (-1) AYRI kosmaya gerek yok; FULL zaten NULL AGR'yi alir.

   ONKOSUL (sirayla, bir kez):
     0) EXIT_MAP §1–2 master/HHD
     1) 00b/00c dump prep
     2) 00d_perf_bank_indexes.sql   ← PAY_LREF + TAH ABYS (zorunlu hiz)
     3) 00 gate PASS
     4) 05/05b/05c collation
     5) 10 setup + MAP + 10f SP deploy (571/581/575 + 10→19 + 20→29 + 611)

   YASAK:
     - GATE_FAIL sonrasi devam
     - 575 + Oracle O14 ayni anda
     - Tek basina 590/597 INSERT (yalniz *_ALL)

   Calistir:
     sqlcmd -S 172.16.1.195 -d energy -C -I -i 30c_EXEC_FULL_CHAIN.sql
       -o logs/energy3007/30c_full_yyyymmdd_hhmm.log

   Sure: saatler–gun (73M INV / 66M PAY_PT). SSMS yerine sqlcmd + log.
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;

DECLARE @AGR_ID BIGINT = NULL;  -- FULL — degistirme
DECLARE @t0 DATETIME2 = SYSDATETIME();

PRINT CONVERT(VARCHAR(30), @t0, 121) + ' | FULL CHAIN START (@AGR_ID=NULL)';

/* ---- precheck ---- */
IF OBJECT_ID('dbo.SP_MIGRATE_LS005_INVOICE', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIGRATE_LS005_INVLINES', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_590_ALL', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_597_ALL', 'P') IS NULL
BEGIN
    RAISERROR('Kritik SP eksik — 10f + overlay deploy', 16, 1);
    RETURN;
END

IF NOT EXISTS (
    SELECT 1 FROM izgazMGR.sys.indexes
    WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_PAYMENT')
      AND name = 'UX_MIG_LS_PAYMENT_PAY_LREF'
)
BEGIN
    RAISERROR('UX_MIG_LS_PAYMENT_PAY_LREF yok — once 00d_perf_bank_indexes.sql', 16, 1);
    RETURN;
END

IF NOT EXISTS (
    SELECT 1 FROM izgazMGR.sys.indexes
    WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_OV_TAH_INVOICE')
      AND name = 'IX_MIG_LS_OV_TAH_INVOICE_ABYS'
)
BEGIN
    RAISERROR('IX_MIG_LS_OV_TAH_INVOICE_ABYS yok — once 00d_perf_bank_indexes.sql', 16, 1);
    RETURN;
END

SELECT
    (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)) AS mgr_inv,
    (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)) AS en_inv_before,
    (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
     WHERE ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL) AS mgr_no_agr;

/* =============================================================================
   E1) 571 INVOICE FULL
   Ilk temiz baslangic: @RESUME=0 (pilot artigi uzerine devam icin 1)
   HARD_RESET=1 sadece bilinçli tam silme — burada KAPALI
   ============================================================================= */
PRINT '========== E1) 571 INVOICE FULL ==========';
EXEC dbo.SP_MIGRATE_LS005_INVOICE
    @BATCH_SIZE = 50000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @AGR_ID     = NULL,
    @DEBUG      = 1;

/* =============================================================================
   E2) 581 INVLINES
   ============================================================================= */
PRINT '========== E2) 581 INVLINES ==========';
EXEC dbo.SP_MIGRATE_LS005_INVLINES
    @BATCH_SIZE = 100000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @RANGE_MODE = 'KEYSET',
    @DEBUG      = 1;

/* =============================================================================
   E3) 575 DEBT PAYTRANS FULL
   O14 bulk kullandiysan bu adimi ATLA
   NOT (v3c): INSERT_RANGE FULL'da #MIG_DEBT_BATCH_KEYS kullanmali — cift INVOICE
   tarama olmasin. Load sirasinda NC index KAPALI; bitince 576 POST_INDEXES.
   ============================================================================= */
PRINT '========== E3) 575 DEBT PAYTRANS FULL ==========';
EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
    @BATCH_SIZE = 50000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @AGR_ID     = NULL,
    @DEBUG      = 1;

/* =============================================================================
   E4) 590 EKSILTEN FULL
   ============================================================================= */
PRINT '========== E4) 590_ALL FULL ==========';
EXEC dbo.SP_MIG_590_ALL
    @AGR_ID = NULL,
    @CLEAN  = 1,
    @DEBUG  = 1;
-- GATE_FAIL → DUR

/* =============================================================================
   E5) 597 TAHSILAT FULL
   ============================================================================= */
PRINT '========== E5) 597_ALL FULL ==========';
EXEC dbo.SP_MIG_597_ALL
    @AGR_ID = NULL,
    @CLEAN  = 1,
    @DEBUG  = 1;
-- GATE_FAIL → DUR

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121)
    + ' | FULL CORE DONE (571→597) elapsed_min='
    + CAST(DATEDIFF(MINUTE, @t0, SYSDATETIME()) AS VARCHAR(20));

SELECT
    (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)) AS en_inv_after,
    (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)) AS en_pt_after,
    (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)
     WHERE ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL) AS en_no_agr;

PRINT '========== SONRAKI (ayri) ==========';
PRINT 'E6) 35_bankref_resolve_abys.sql  — SET @AGR_ID=NULL; SET @DRY_RUN=0;';
PRINT 'E7) 50_post_taksit_close_afl.sql — SET @AGR_ID=NULL;';
PRINT 'E8) 40_installment_plan_pay_apply.sql @DRY_RUN=0 @AGR_ID=NULL';
PRINT 'E9) ../90_afl_frk/92_stg_inv_pay_close_apply.sql @DRY_RUN=0';
PRINT 'E10) 90_check_queries.sql';
PRINT 'NOT: 30b NO_AGR (-1) FULL sonrasi gerekmez.';
GO
