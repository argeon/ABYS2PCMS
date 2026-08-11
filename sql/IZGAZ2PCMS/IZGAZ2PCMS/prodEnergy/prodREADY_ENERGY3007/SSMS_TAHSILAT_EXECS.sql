/* =============================================================================
   SSMS_TAHSILAT_EXECS.sql — yeni aktarım FULL (güncel EXEC listesi)

   Kullanim: energy + Results to Text → tah_step set → F5 (tek adim)

   @STEP:
     0   precheck + SP_MIG_IX_PRECHECK  ★ FAIL=DUR (R22)
     1   CLEAN PT→IL→INV + MAP ENERGY_LREF NULL
     2   571 INVOICE                    (icinde PREPARE → NC DISABLE)
     3   572 POST_INDEXES INVOICE       ★ load sonrasi zorunlu
     4   581 INVLINES
     5   582 POST_INDEXES INVLINES      ★
     6   575 DEBT PAYTRANS
     7   576 POST_INDEXES PAYTRANS      ★
     8   590_ALL
     9   SP_MIG_597_NCIX_DISABLE        (597 oncesi; eski 20b)
     10  597_ALL  (@CLEAN=1 ilk FULL; resume/heal sonrasi CLEAN=0)
     11  probe bad_map PAY→IOCODE=0     ★ >0 → 20e → ALL @CLEAN=0 (CLEAN=1 YASAK)
     12  SP_MIG_597_NCIX_REBUILD        (=572+20c; probe=0 sonrasi)
     13  611 INSTALLMENT_PLAN
     14  611b WIRE + SP_MIG_IX_IP_AGR   ★ 613 oncesi
     15  SP_MIG_50E_TAKSIT (UX+613)     ★ step 13–14 sonrası Do611=0
     16  ozet count

   R17+R22+R24: NCIX/PROBE/50e/20a/90 = EXEC only
   ONKOSUL: 003A+CHECK | 00c | deploy 26*+50e+20a+90 | MAP | SP deploy | AFL
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
EXEC sys.sp_set_session_context N'tah_step', 0;   -- <<< 0..16
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
        (N'SP_MIG_OV_ID_MAP_SYNC_FROM_MGR'),
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
        (N'SP_MIG_597_NCIX_DISABLE'),
        (N'SP_MIG_597_NCIX_REBUILD'),
        (N'SP_MIG_IX_PRECHECK'),
        (N'SP_MIG_IX_MGR_ENSURE'),
        (N'SP_MIG_IX_IP_AGR'),
        (N'SP_MIGRATE_LS005_INSTALLMENT_PLAN'),
        (N'SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE')
    ) v(name);

    SELECT 'MIG_OV_ID_MAP' t, COUNT_BIG(*) c FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
    UNION ALL SELECT 'INVOICE', COUNT_BIG(*) FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)
    UNION ALL SELECT 'INVLINES', COUNT_BIG(*) FROM dbo.LS_005_01_INVLINES WITH (NOLOCK)
    UNION ALL SELECT 'PAYTRANS', COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK);

    IF OBJECT_ID(N'dbo.SP_MIG_IX_MGR_ENSURE', N'P') IS NOT NULL
        EXEC dbo.SP_MIG_IX_MGR_ENSURE @DEBUG = 1;

    IF OBJECT_ID(N'dbo.SP_MIG_IX_PRECHECK', N'P') IS NOT NULL
        EXEC dbo.SP_MIG_IX_PRECHECK;  -- FAIL=DUR
    ELSE
        RAISERROR('SP_MIG_IX_PRECHECK yok — once 26_IX_PRECHECK.sql', 16, 1);

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
    /* MAP yoksa/eksikse MGR→energy kopya (doluysa SKIP) */
    IF OBJECT_ID('dbo.SP_MIG_OV_ID_MAP_SYNC_FROM_MGR', 'P') IS NOT NULL
        EXEC dbo.SP_MIG_OV_ID_MAP_SYNC_FROM_MGR @DEBUG = 1, @Force = 0;
    ELSE
        RAISERROR('WARN: SP_MIG_OV_ID_MAP_SYNC_FROM_MGR yok — 00_map_tables / 044', 0, 1) WITH NOWAIT;

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
   STEP 9 — SP_MIG_597_NCIX_DISABLE — 597 ONCESI ZORUNLU
   ============================================================================= */
USE energy;
GO
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 9
    RAISERROR('STEP 9 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 9: SP_MIG_597_NCIX_DISABLE ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_597_NCIX_DISABLE @DEBUG = 1;
    RAISERROR('STEP 9 OK → tah_step=10', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 10 — 597
   Ilk FULL temiz DB: @CLEAN=1
   Resume / 20e sonrasi / bad_map>0 iken: @CLEAN=0  (CLEAN=1 YASAK — borc siler)
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 10
    RAISERROR('STEP 10 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 10 597_ALL ==========', 0, 1) WITH NOWAIT;
    RAISERROR('Ilk FULL: CLEAN=1 | resume/20e sonrasi: CLEAN=0 (asagidaki EXEC degistir)', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_597_ALL @AGR_ID = NULL, @CLEAN = 1, @DEBUG = 1, @BatchSize = 250000;
    /* Resume ornek (yorum ac):
       EXEC dbo.SP_MIG_597_ALL @AGR_ID=NULL, @CLEAN=0, @DEBUG=1, @BatchSize=250000;
    */
    RAISERROR('STEP 10 OK → tah_step=11 PROBE (GATE otorite; E597=FAIL panik yok)', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 11 — PROBE bad_map (R15/R17) — 20c ONCESI
   >0 → DUR → 20e → ALL @CLEAN=0 → tekrar probe=0 → sonra 20c
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 11
    RAISERROR('STEP 11 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 11 PROBE bad_map PAY→IOCODE=0 ==========', 0, 1) WITH NOWAIT;

    DECLARE @bad_map BIGINT =
    (
        SELECT COUNT_BIG(*)
        FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
        JOIN dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK) ON pt.LREF = m.ENERGY_LREF
        WHERE m.OV_KIND = 'PAY_PT'
          AND m.ENERGY_LREF IS NOT NULL
          AND pt.IOCODE = 0
    );

    SELECT @bad_map AS pay_map_to_debt;

    SELECT
        SUM(CASE WHEN IOCODE <> 0 THEN 1 ELSE 0 END) AS pt_pay,
        SUM(CASE WHEN IOCODE = 0 THEN 1 ELSE 0 END) AS pt_debt
    FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
    WHERE ISNULL(CANCELED, 0) = 0;

    IF OBJECT_ID('dbo.SP_MIG_597_GATE', 'P') IS NOT NULL
        EXEC dbo.SP_MIG_597_GATE @AGR_ID = NULL;

    IF @bad_map > 0
    BEGIN
        RAISERROR('1) EXEC SP_MIG_20E_BAD_MAP_HEAL @DRY_RUN=0', 0, 1) WITH NOWAIT;
        RAISERROR('2) EXEC SP_MIG_597_ALL @CLEAN=0 @BatchSize=250000  ★ CLEAN=1 YASAK', 0, 1) WITH NOWAIT;
        RAISERROR('3) tah_step=11 tekrar (probe=0 sart) sonra tah_step=12 (20c)', 0, 1) WITH NOWAIT;
        RAISERROR('Ops: NOTES_597_OPS_HEAL.md R15', 0, 1) WITH NOWAIT;
        RAISERROR('========== BAD_MAP > 0 — DUR; 20c YASAK ==========', 16, 1);
    END
    ELSE
    BEGIN
        RAISERROR('PROBE OK bad_map=0 → tah_step=12 (20c)', 0, 1) WITH NOWAIT;
    END
END
GO

/* =============================================================================
   STEP 12 — SP_MIG_597_NCIX_REBUILD — yalniz probe=0 sonrasi
   ============================================================================= */
USE energy;
GO
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 12
    RAISERROR('STEP 12 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 12: SP_MIG_597_NCIX_REBUILD ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_597_NCIX_REBUILD @DEBUG = 1;
    RAISERROR('STEP 12 OK → tah_step=13', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 13 — 611
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 13
    RAISERROR('STEP 13 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 13 611 INSTALLMENT_PLAN ==========', 0, 1) WITH NOWAIT;
    IF OBJECT_ID('dbo.MIG_611_STG_IP_KEYS', 'U') IS NULL
    BEGIN
        RAISERROR('Staging yok — 00e_taksit_staging.sql', 16, 1);
        RETURN;
    END
    EXEC dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
        @BATCH_SIZE = 50000, @RESUME = 1, @HARD_RESET = 0, @AGR_ID = NULL, @DEBUG = 1;
    RAISERROR('STEP 13 OK → tah_step=14', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 14 — 611b
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 14
    RAISERROR('STEP 14 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 14 611b WIRE ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE @AGR_ID = NULL, @DEBUG = 1;
    SELECT COUNT_BIG(*) AS EN_PLAN FROM dbo.LS_005_01_INSTALLMENT_PLAN WITH (NOLOCK);
    RAISERROR('========== STEP 14b: SP_MIG_IX_IP_AGR (613 P0) ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_IX_IP_AGR @DEBUG = 1;
    RAISERROR('STEP 14 OK → tah_step=15 (50e/613)', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 15 — 613 / 50e
   ============================================================================= */
USE energy;
GO
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 15
    RAISERROR('STEP 15 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 15: 50e_TAKSIT_EXECS.sql ==========', 0, 1) WITH NOWAIT;
    RAISERROR('Icerik: UX DROP/CREATE + 613 NORMALIZE/SPLIT (IP_AGR step14b)', 0, 1) WITH NOWAIT;
    RAISERROR('Sonra: EXEC SP_MIG_35 / 40 / 92 @DRY_RUN=0', 0, 1) WITH NOWAIT;
    RAISERROR('Validate: 95 → 99 → 97 @OnlyDiff=1', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 16 — OZET
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
IF CONVERT(INT, SESSION_CONTEXT(N'tah_step')) <> 16
    RAISERROR('STEP 16 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 16 COUNTS ==========', 0, 1) WITH NOWAIT;
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
Guncel hizli liste (R17):

CLEAN
  SP_MIG_DEBT_PAYTRANS_HARD_RESET / INVLINES_HARD_RESET / INVOICE_HARD_RESET

ANA (+ PREPARE icinde NC DISABLE)
  SP_MIGRATE_LS005_INVOICE          → SP_MIG_INVOICE_POST_INDEXES
  SP_MIGRATE_LS005_INVLINES         → SP_MIG_INVLINES_POST_INDEXES
  SP_MIGRATE_LS005_DEBT_PAYTRANS    → SP_MIG_DEBT_PAYTRANS_POST_INDEXES

OVERLAY
  SP_MIG_590_ALL
  SP_MIG_597_NCIX_DISABLE
  SP_MIG_597_ALL (@CLEAN=1 ilk | @CLEAN=0 resume/20e)
  probe bad_map → (>0) 20e → ALL @CLEAN=0
  SP_MIG_597_NCIX_REBUILD

TAKSIT
  SP_MIGRATE_LS005_INSTALLMENT_PLAN
  SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE
  SP_MIG_IX_IP_AGR
  50e_TAKSIT_EXECS.sql (UX + 613)
  35 / 40 / 92 (@DRY_RUN=0)
*/
