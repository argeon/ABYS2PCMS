/* =============================================================================
   SSMS_TAHSILAT_EXECS.sql — yeni aktarım FULL (güncel EXEC listesi)

   Kullanim: energy + Results to Text → tah_step set → F5 (tek adim)

   @STEP:
     0   precheck
     1   CLEAN PT→IL→INV + MAP ENERGY_LREF NULL
     2   571 INVOICE                    (icinde PREPARE → NC DISABLE)
     3   572 POST_INDEXES INVOICE       ★ load sonrasi zorunlu
     4   581 INVLINES
     5   582 POST_INDEXES INVLINES      ★
     6   575 DEBT PAYTRANS
     7   576 POST_INDEXES PAYTRANS      ★
     8   590_ALL
     9   20b PAYTRANS NCIX DISABLE      (597 oncesi; dosya calistir)
     10  597_ALL
     11  20c PAYTRANS NCIX REBUILD      (597 sonrasi; dosya calistir)
     12  611 INSTALLMENT_PLAN
     13  611b WIRE
     14  50e / 613 pointer (+ UX DROP/CREATE 50e icinde)
     15  ozet count

   ONKOSUL: 003A+CHECK | 00c | 00d | MGR INV/IL IX | MAP | SP deploy | AFL
   195: C:\www\MIGRATION_SCR_20260708\ENERGY
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ========== TEK SATIR ========== */
EXEC sys.sp_set_session_context N'tah_step', 0;   -- <<< 0..15
GO

/* =============================================================================
   STEP 0 — PRECHECK
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 0
    RAISERROR('STEP 0 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 0 PRECHECK ==========', 0, 1) WITH NOWAIT;
    SELECT name AS SP,
           CASE WHEN OBJECT_ID(N'dbo.' + name, N'P') IS NOT NULL THEN N'OK' ELSE N'MISS' END AS st
    FROM (VALUES
        (N'SP_MIG_DEBT_PAYTRANS_HARD_RESET'),
        (N'SP_MIG_INVLINES_HARD_RESET'),
        (N'SP_MIG_INVOICE_HARD_RESET'),
        (N'SP_MIGRATE_LS005_INVOICE'),
        (N'SP_MIG_INVOICE_POST_INDEXES'),
        (N'SP_MIGRATE_LS005_INVLINES'),
        (N'SP_MIG_INVLINES_ENSURE_MGR_INDEXES'),
        (N'SP_MIG_INVLINES_POST_INDEXES'),
        (N'SP_MIGRATE_LS005_DEBT_PAYTRANS'),
        (N'SP_MIG_DEBT_PAYTRANS_POST_INDEXES'),
        (N'SP_MIG_590_ALL'),
        (N'SP_MIG_597_ALL'),
        (N'SP_MIGRATE_LS005_INSTALLMENT_PLAN'),
        (N'SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE')
    ) v(name);

    SELECT 'MIG_OV_ID_MAP' t, COUNT_BIG(*) c FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
    UNION ALL SELECT 'INVOICE', COUNT_BIG(*) FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)
    UNION ALL SELECT 'INVLINES', COUNT_BIG(*) FROM dbo.LS_005_01_INVLINES WITH (NOLOCK)
    UNION ALL SELECT 'PAYTRANS', COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK);

    IF NOT EXISTS (SELECT 1 FROM izgazMGR.sys.indexes WHERE object_id=OBJECT_ID('izgazMGR.dbo.LS_INVOICE') AND name='IX_MIG_LSINV_ACTION')
        RAISERROR('WARN: IX_MIG_LSINV_ACTION yok', 0, 1) WITH NOWAIT;
    IF NOT EXISTS (SELECT 1 FROM izgazMGR.sys.indexes WHERE object_id=OBJECT_ID('izgazMGR.dbo.LS_INVLINES') AND name='IX_MIG_LSINVLINES_LREF')
        RAISERROR('WARN: IX_MIG_LSINVLINES_LREF yok — 581 icinde SP_MIG_INVLINES_ENSURE_MGR_INDEXES kuracak', 0, 1) WITH NOWAIT;
    IF NOT EXISTS (SELECT 1 FROM izgazMGR.sys.indexes WHERE object_id=OBJECT_ID('izgazMGR.dbo.LS_INVLINES') AND name='IX_MIG_LSIL_INVREF')
        RAISERROR('WARN: IX_MIG_LSIL_INVREF yok — ENSURE_MGR_INDEXES kuracak', 0, 1) WITH NOWAIT;
    IF NOT EXISTS (SELECT 1 FROM izgazMGR.sys.indexes WHERE object_id=OBJECT_ID('izgazMGR.dbo.LS_PAYMENT') AND name='UX_MIG_LS_PAYMENT_PAY_LREF')
        RAISERROR('WARN: UX_MIG_LS_PAYMENT_PAY_LREF yok — 00d', 0, 1) WITH NOWAIT;

    RAISERROR('Sonraki: tah_step=1 CLEAN', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 1 — CLEAN
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 1
    RAISERROR('STEP 1 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 1 CLEAN ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_DEBT_PAYTRANS_HARD_RESET @DELETE_BATCH = 50000, @AGR_ID = NULL, @DEBUG = 1;
    IF OBJECT_ID('dbo.SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD', 'P') IS NOT NULL
        EXEC dbo.SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD @DEBUG = 1;

    DECLARE @d INT, @n BIGINT = 0;
    WHILE 1 = 1
    BEGIN
        DELETE TOP (50000) FROM dbo.LS_005_01_PAYTRANS WHERE ABYS_ID IS NOT NULL;
        SET @d = @@ROWCOUNT;
        IF @d = 0 BREAK;
        SET @n += @d;
        RAISERROR('PAYTRANS ABYS del +%d (toplam %I64d)', 0, 1, @d, @n) WITH NOWAIT;
    END

    EXEC dbo.SP_MIG_INVLINES_HARD_RESET @DELETE_BATCH = 100000, @DEBUG = 1;
    EXEC dbo.SP_MIG_INVOICE_HARD_RESET @DELETE_BATCH = 50000, @DEBUG = 1;

    IF OBJECT_ID('dbo.MIG_OV_ID_MAP', 'U') IS NOT NULL
        UPDATE dbo.MIG_OV_ID_MAP SET ENERGY_LREF = NULL WHERE ENERGY_LREF IS NOT NULL;
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_ID_MAP', 'U') IS NOT NULL
        UPDATE izgazMGR.dbo.LS_OV_ID_MAP SET ENERGY_LREF = NULL WHERE ENERGY_LREF IS NOT NULL;

    SELECT 'AFTER_CLEAN_INV' t, COUNT_BIG(*) c FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)
    UNION ALL SELECT 'AFTER_CLEAN_IL', COUNT_BIG(*) FROM dbo.LS_005_01_INVLINES WITH (NOLOCK)
    UNION ALL SELECT 'AFTER_CLEAN_PT', COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK);
    RAISERROR('STEP 1 OK → tah_step=2', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 2 — 571 (PREPARE/NC DISABLE SP icinde)
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 2
    RAISERROR('STEP 2 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 2 571 INVOICE ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIGRATE_LS005_INVOICE
        @BATCH_SIZE = 50000, @RESUME = 1, @HARD_RESET = 0, @AGR_ID = NULL, @DEBUG = 1;
    RAISERROR('STEP 2 OK → tah_step=3 (572 POST)', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 3 — 572 POST_INDEXES INVOICE
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 3
    RAISERROR('STEP 3 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 3 572 POST_INDEXES INVOICE ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_INVOICE_POST_INDEXES @DEBUG = 1;
    RAISERROR('STEP 3 OK → tah_step=4', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 4 — 581
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 4
    RAISERROR('STEP 4 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 4 581 INVLINES (once ENSURE MGR IX) ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIGRATE_LS005_INVLINES
        @BATCH_SIZE = 100000, @RESUME = 1, @HARD_RESET = 0,
        @RANGE_MODE = 'KEYSET', @SKIP_PERF_CHECK = 0, @DEBUG = 1;
    RAISERROR('STEP 4 OK → tah_step=5 (582 POST)', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 5 — 582 POST_INDEXES INVLINES
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 5
    RAISERROR('STEP 5 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 5 582 POST_INDEXES INVLINES ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_INVLINES_POST_INDEXES @DEBUG = 1;
    RAISERROR('STEP 5 OK → tah_step=6', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 6 — 575
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 6
    RAISERROR('STEP 6 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 6 575 DEBT PAYTRANS ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
        @BATCH_SIZE = 50000, @RESUME = 1, @HARD_RESET = 0, @AGR_ID = NULL, @DEBUG = 1;
    RAISERROR('STEP 6 OK → tah_step=7 (576 POST)', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 7 — 576 POST_INDEXES PAYTRANS
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 7
    RAISERROR('STEP 7 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 7 576 POST_INDEXES PAYTRANS ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_DEBT_PAYTRANS_POST_INDEXES @DEBUG = 1;
    RAISERROR('STEP 7 OK → tah_step=8', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 8 — 590
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 8
    RAISERROR('STEP 8 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 8 590_ALL ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_590_ALL @AGR_ID = NULL, @CLEAN = 1, @DEBUG = 1;
    RAISERROR('STEP 8 OK (GATE_FAIL→DUR) → tah_step=9 (20b)', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 9 — 20b NCIX DISABLE (dosya; SP degil)
   ============================================================================= */
USE energy;
GO
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 9
    RAISERROR('STEP 9 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 9: 20b_PAYTRANS_NCIX_DISABLE.sql CALISTIR ==========', 0, 1) WITH NOWAIT;
    RAISERROR('Dosya: prodREADY_ENERGY/20b_PAYTRANS_NCIX_DISABLE.sql', 0, 1) WITH NOWAIT;
    RAISERROR('Snapshot: 034_20B_PAYTRANS_NCIX_DISABLE.SQL', 0, 1) WITH NOWAIT;
    RAISERROR('Bitince tah_step=10', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 10 — 597
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 10
    RAISERROR('STEP 10 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 10 597_ALL ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_597_ALL @AGR_ID = NULL, @CLEAN = 1, @DEBUG = 1, @BatchSize = 250000;
    RAISERROR('STEP 10 OK (GATE_PASS sart) → tah_step=11 (20c)', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 11 — 20c NCIX REBUILD (dosya)
   ============================================================================= */
USE energy;
GO
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 11
    RAISERROR('STEP 11 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 11: 20c_PAYTRANS_NCIX_REBUILD.sql CALISTIR ==========', 0, 1) WITH NOWAIT;
    RAISERROR('Dosya: prodREADY_ENERGY/20c_PAYTRANS_NCIX_REBUILD.sql', 0, 1) WITH NOWAIT;
    RAISERROR('Snapshot: 035_20C_PAYTRANS_NCIX_REBUILD.SQL', 0, 1) WITH NOWAIT;
    RAISERROR('Bitince tah_step=12', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 12 — 611
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 12
    RAISERROR('STEP 12 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 12 611 INSTALLMENT_PLAN ==========', 0, 1) WITH NOWAIT;
    IF OBJECT_ID('dbo.MIG_611_STG_IP_KEYS', 'U') IS NULL
    BEGIN
        RAISERROR('Staging yok — 00e_taksit_staging.sql', 16, 1);
        RETURN;
    END
    EXEC dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
        @BATCH_SIZE = 50000, @RESUME = 1, @HARD_RESET = 0, @AGR_ID = NULL, @DEBUG = 1;
    RAISERROR('STEP 12 OK → tah_step=13', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 13 — 611b
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 13
    RAISERROR('STEP 13 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 13 611b WIRE ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE @AGR_ID = NULL, @DEBUG = 1;
    SELECT COUNT_BIG(*) AS EN_PLAN FROM dbo.LS_005_01_INSTALLMENT_PLAN WITH (NOLOCK);
    RAISERROR('STEP 13 OK → tah_step=14 (50e)', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 14 — 613 / 50e
   ============================================================================= */
USE energy;
GO
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 14
    RAISERROR('STEP 14 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 14: 50e_TAKSIT_EXECS.sql ==========', 0, 1) WITH NOWAIT;
    RAISERROR('Icerik: UX DROP/CREATE + IX_MIG_LS005_IP_AGR + 613 NORMALIZE/SPLIT', 0, 1) WITH NOWAIT;
    RAISERROR('Sonra: 35_bankref @DRY_RUN=0 | 40_ipp @DRY_RUN=0 | 92_stg @DRY_RUN=0', 0, 1) WITH NOWAIT;
    RAISERROR('Validate: 95 → 99 → 97 @OnlyDiff=1', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 15 — OZET
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 15
    RAISERROR('STEP 15 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 15 COUNTS ==========', 0, 1) WITH NOWAIT;
    SELECT t, c FROM (
        SELECT 1 o, 'INVOICE' t, COUNT_BIG(*) c FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)
        UNION ALL SELECT 2, 'INVLINES', COUNT_BIG(*) FROM dbo.LS_005_01_INVLINES WITH (NOLOCK)
        UNION ALL SELECT 3, 'PAYTRANS', COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
        UNION ALL SELECT 4, 'INSTALLMENT_PLAN', COUNT_BIG(*) FROM dbo.LS_005_01_INSTALLMENT_PLAN WITH (NOLOCK)
        UNION ALL SELECT 5, 'MIG_OV_ID_MAP', COUNT_BIG(*) FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
    ) x ORDER BY o;
    IF OBJECT_ID('dbo.SP_MIG_LOG_STATUS', 'P') IS NOT NULL
        EXEC dbo.SP_MIG_LOG_STATUS;
END
GO

/*
Guncel hizli liste:

CLEAN
  SP_MIG_DEBT_PAYTRANS_HARD_RESET / INVLINES_HARD_RESET / INVOICE_HARD_RESET

ANA (+ PREPARE icinde NC DISABLE)
  SP_MIGRATE_LS005_INVOICE          → SP_MIG_INVOICE_POST_INDEXES
  SP_MIGRATE_LS005_INVLINES         → SP_MIG_INVLINES_POST_INDEXES
  SP_MIGRATE_LS005_DEBT_PAYTRANS    → SP_MIG_DEBT_PAYTRANS_POST_INDEXES

OVERLAY
  SP_MIG_590_ALL
  20b_PAYTRANS_NCIX_DISABLE.sql
  SP_MIG_597_ALL
  20c_PAYTRANS_NCIX_REBUILD.sql

TAKSIT
  SP_MIGRATE_LS005_INSTALLMENT_PLAN
  SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE
  50e_TAKSIT_EXECS.sql (UX + 613)
  35 / 40 / 92 (@DRY_RUN=0)
*/
