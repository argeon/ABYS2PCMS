/* =============================================================================
   prodREADY_ENERGY3007 / 30c_EXEC_FULL_CHAIN.sql
   PROD TAM AKTARIM — @AGR_ID = NULL (FULL)
   R22: SSMS_TAHSILAT sırası = tek doğru (POST ★ + NCIX SP + IX gate)

   Kapsar: sozlesmeli + NO_AGR (NULL AGR) fatura/tahsilat.
   30b (-1) AYRI kosmaya gerek yok; FULL zaten NULL AGR'yi alir.

   ONKOSUL (sirayla, bir kez):
     0) EXIT_MAP §1–2 master/HHD
     1) 00b/00c dump prep + 00i MAP clustered
     2) Deploy 26/26a/26b/26c/26d + 00d/00f (veya SP_MIG_IX_MGR_ENSURE)
     3) EXEC SP_MIG_IX_PRECHECK  ← FAIL=DUR
     4) 05/05b/05c collation
     5) 10 setup + MAP + 10f SP deploy (571/581/575 + 10→19 + 20→29 + 611)

   YASAK:
     - GATE_FAIL sonrasi devam
     - 575 + Oracle O14 ayni anda
     - Tek basina 590/597 INSERT (yalniz *_ALL)
     - POST atlayip 590/597

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
DECLARE @bad_map BIGINT;

PRINT CONVERT(VARCHAR(30), @t0, 121) + ' | FULL CHAIN START (@AGR_ID=NULL) R22';

/* ---- precheck SP varlık ---- */
IF OBJECT_ID('dbo.SP_MIGRATE_LS005_INVOICE', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIGRATE_LS005_INVLINES', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_590_ALL', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_597_ALL', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_INVOICE_POST_INDEXES', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_INVLINES_POST_INDEXES', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_DEBT_PAYTRANS_POST_INDEXES', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_597_NCIX_DISABLE', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_597_NCIX_REBUILD', 'P') IS NULL
BEGIN
    RAISERROR('Kritik SP eksik — 10f + 26* + overlay deploy', 16, 1);
    RETURN;
END

/* ---- IX hard gate (R22) ---- */
IF OBJECT_ID('dbo.SP_MIG_IX_MGR_ENSURE', 'P') IS NOT NULL
    EXEC dbo.SP_MIG_IX_MGR_ENSURE @DEBUG = 1;

IF OBJECT_ID('dbo.SP_MIG_IX_PRECHECK', 'P') IS NOT NULL
    EXEC dbo.SP_MIG_IX_PRECHECK;
ELSE
BEGIN
    RAISERROR('SP_MIG_IX_PRECHECK yok — once 26_IX_PRECHECK.sql deploy', 16, 1);
    RETURN;
END

SELECT
    (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)) AS mgr_inv,
    (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)) AS en_inv_before,
    (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
     WHERE ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL) AS mgr_no_agr;

/* =============================================================================
   E1) 571 → 572
   ============================================================================= */
PRINT '========== E1) 571 INVOICE FULL ==========';
EXEC dbo.SP_MIGRATE_LS005_INVOICE
    @BATCH_SIZE = 50000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @AGR_ID     = NULL,
    @DEBUG      = 1;
PRINT '========== E1b) 572 POST_INDEXES INVOICE ==========';
EXEC dbo.SP_MIG_INVOICE_POST_INDEXES @DEBUG = 1;

/* =============================================================================
   E2) 581 → 582
   ============================================================================= */
PRINT '========== E2) 581 INVLINES ==========';
EXEC dbo.SP_MIGRATE_LS005_INVLINES
    @BATCH_SIZE = 100000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @RANGE_MODE = 'KEYSET',
    @DEBUG      = 1;
PRINT '========== E2b) 582 POST_INDEXES INVLINES ==========';
EXEC dbo.SP_MIG_INVLINES_POST_INDEXES @DEBUG = 1;

/* =============================================================================
   E3) 575 → 576
   O14 bulk kullandiysan bu adimi ATLA
   ============================================================================= */
PRINT '========== E3) 575 DEBT PAYTRANS FULL ==========';
EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
    @BATCH_SIZE = 50000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @AGR_ID     = NULL,
    @DEBUG      = 1;
PRINT '========== E3b) 576 POST_INDEXES PAYTRANS ==========';
EXEC dbo.SP_MIG_DEBT_PAYTRANS_POST_INDEXES @DEBUG = 1;

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
   E5) 597 — NCIX OFF → ALL → GATE → probe → NCIX ON
   ============================================================================= */
PRINT '========== E5a) SP_MIG_597_NCIX_DISABLE ==========';
EXEC dbo.SP_MIG_597_NCIX_DISABLE @DEBUG = 1;

PRINT '========== E5b) 597_ALL FULL ==========';
EXEC dbo.SP_MIG_597_ALL
    @AGR_ID    = NULL,
    @CLEAN     = 1,
    @DEBUG     = 1,
    @BatchSize = 250000;

PRINT '========== E5c) GATE + PROBE bad_map ==========';
EXEC dbo.SP_MIG_597_GATE @AGR_ID = NULL;

SELECT @bad_map = COUNT_BIG(*)
FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
JOIN dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK) ON pt.LREF = m.ENERGY_LREF
WHERE m.OV_KIND = 'PAY_PT' AND m.ENERGY_LREF IS NOT NULL AND pt.IOCODE = 0;

SELECT @bad_map AS pay_map_to_debt;

IF @bad_map > 0
BEGIN
    RAISERROR('BAD_MAP > 0 — 20e sonra ALL @CLEAN=0; NCIX_REBUILD YASAK', 16, 1);
    RETURN;
END

PRINT '========== E5d) SP_MIG_597_NCIX_REBUILD ==========';
EXEC dbo.SP_MIG_597_NCIX_REBUILD @DEBUG = 1;

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121)
    + ' | FULL CORE DONE (571→572→…→597→NCIX) elapsed_min='
    + CAST(DATEDIFF(MINUTE, @t0, SYSDATETIME()) AS VARCHAR(20));

SELECT
    (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)) AS en_inv_after,
    (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)) AS en_pt_after,
    (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)
     WHERE ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL) AS en_no_agr;

PRINT '========== SONRAKI (ayri EXEC) ==========';
PRINT 'E6) EXEC SP_MIG_35_BANKREF_RESOLVE @DRY_RUN=0 @AGR_ID=NULL';
PRINT 'E7) 611 + 611b → EXEC SP_MIG_IX_IP_AGR → 613/50e';
PRINT 'E8) EXEC SP_MIG_40_IPP_APPLY @DRY_RUN=0';
PRINT 'E9) EXEC SP_MIG_92_STG_CLOSE @DRY_RUN=0';
PRINT 'E10) 90_check_queries.sql';
PRINT 'NOT: 30b NO_AGR (-1) FULL sonrasi gerekmez.';
GO
