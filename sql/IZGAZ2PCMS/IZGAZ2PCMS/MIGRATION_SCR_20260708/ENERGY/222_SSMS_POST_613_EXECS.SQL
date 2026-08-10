/* =============================================================================
   SSMS_POST_613_EXECS.sql — 613 sonrasi kalan EXEC / dosya adimlari
   energy baglan | Results to Text | asagida @STEP set et | F5

   Onkosul: 597 GATE_PASS | 20c PT NCIX | 611+611b | 50e E3 (613) BITMIS

   @STEP:
     0  status (613 progress + index)
     1  613 resume pointer → 50e_TAKSIT_EXECS.sql (E3)
     2  40 IPP DRY_RUN=1 (sayim)
     3  40 IPP APPLY pointer (@DRY_RUN=0 dosyada)
     4  35 BANKREF DRY pointer
     5  35 BANKREF APPLY pointer
     6  92 STG CLOSE DRY pointer
     7  92 STG CLOSE APPLY pointer
     8  validate EXECs (97 FRK)
     9  20a TAH MAP (opsiyonel)
    10  ozet counts
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET IMPLICIT_TRANSACTIONS OFF;
GO

DECLARE @STEP INT = 0;   -- <<< BURAYA ADIM
EXEC sys.sp_set_session_context @key = N'post613_step', @value = @STEP;
RAISERROR('post613_step=%d', 0, 1, @STEP) WITH NOWAIT;
GO

/* =============================================================================
   STEP 0 — STATUS
   ============================================================================= */
IF CONVERT(INT, SESSION_CONTEXT(N'post613_step')) <> 0
    RAISERROR('STEP 0 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 0 STATUS ==========', 0, 1) WITH NOWAIT;

    SELECT
        (SELECT COUNT(DISTINCT ABYS_AGREEMENT_ID)
         FROM dbo.LS_005_01_INSTALLMENT_PLAN WITH (NOLOCK)
         WHERE ABYS_AGREEMENT_ID IS NOT NULL) AS agr_total,
        (SELECT COUNT(DISTINCT pl.ABYS_AGREEMENT_ID)
         FROM dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
         WHERE pl.ABYS_AGREEMENT_ID IS NOT NULL
           AND EXISTS (
                SELECT 1 FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
                WHERE pt.ABYS_AGREEMENT_ID = pl.ABYS_AGREEMENT_ID
                  AND pt.IOCODE = 0 AND pt.INST_NR > 0
                  AND ISNULL(pt.CANCELED, 0) = 0
                  AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
           )) AS agr_613_done,
        (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
         WHERE IOCODE = 0 AND INST_NR > 0
           AND ISNULL(CANCELED, 0) = 0
           AND ISNULL(CANCELLATIONPAYMENT, 0) = 0) AS pt_inst_gt0,
        (SELECT COUNT(*) FROM sys.indexes
         WHERE object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
           AND type = 2 AND is_disabled = 1) AS pt_ncix_disabled;

    SELECT r.session_id, r.status, r.command, ISNULL(r.wait_type, '-') wt,
           LEFT(REPLACE(REPLACE(t.text, CHAR(13), ' '), CHAR(10), ' '), 100) txt
    FROM sys.dm_exec_requests r
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.session_id <> @@SPID
      AND r.database_id = DB_ID(N'energy')
      AND r.session_id > 50;
END
GO

/* =============================================================================
   STEP 1 — 613 resume
   ============================================================================= */
IF CONVERT(INT, SESSION_CONTEXT(N'post613_step')) <> 1
    RAISERROR('STEP 1 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 1: 50e_TAKSIT_EXECS.sql ==========', 0, 1) WITH NOWAIT;
    RAISERROR('Dosya: prodREADY_ENERGY3007/50e_TAKSIT_EXECS.sql', 0, 1) WITH NOWAIT;
    RAISERROR('613 resume: done_skip artar, pending azalir. Bitmeden 40/35 YASAK.', 0, 1) WITH NOWAIT;
    RAISERROR('Snapshot: 20260708/ENERGY/*50E*', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 2 — 40 IPP DRY
   ============================================================================= */
IF CONVERT(INT, SESSION_CONTEXT(N'post613_step')) <> 2
    RAISERROR('STEP 2 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 2: 40 IPP DRY_RUN=1 ==========', 0, 1) WITH NOWAIT;
    RAISERROR('Dosya: prodREADY_ENERGY3007/40_installment_plan_pay_apply.sql', 0, 1) WITH NOWAIT;
    RAISERROR('Icinde: DECLARE @DRY_RUN BIT = 1;  @AGR_ID = NULL;', 0, 1) WITH NOWAIT;
    RAISERROR('sqlcmd: -i 40_installment_plan_pay_apply.sql', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 3 — 40 IPP APPLY
   ============================================================================= */
IF CONVERT(INT, SESSION_CONTEXT(N'post613_step')) <> 3
    RAISERROR('STEP 3 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 3: 40 IPP APPLY ==========', 0, 1) WITH NOWAIT;
    RAISERROR('40_installment_plan_pay_apply.sql → @DRY_RUN = 0; @AGR_ID = NULL;', 0, 1) WITH NOWAIT;
    RAISERROR('Onkosul: 613 pending=0 + MIG_40_STG_IPP var', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 4 — 35 BANKREF DRY
   ============================================================================= */
IF CONVERT(INT, SESSION_CONTEXT(N'post613_step')) <> 4
    RAISERROR('STEP 4 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 4: 35 BANKREF DRY ==========', 0, 1) WITH NOWAIT;
    RAISERROR('Dosya: prodREADY_ENERGY3007/35_bankref_resolve_abys.sql', 0, 1) WITH NOWAIT;
    RAISERROR('Icinde: @DRY_RUN = 1; @AGR_ID = NULL;', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 5 — 35 BANKREF APPLY
   ============================================================================= */
IF CONVERT(INT, SESSION_CONTEXT(N'post613_step')) <> 5
    RAISERROR('STEP 5 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 5: 35 BANKREF APPLY ==========', 0, 1) WITH NOWAIT;
    RAISERROR('35_bankref_resolve_abys.sql → @DRY_RUN = 0; @AGR_ID = NULL;', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 6 — 92 STG CLOSE DRY
   ============================================================================= */
IF CONVERT(INT, SESSION_CONTEXT(N'post613_step')) <> 6
    RAISERROR('STEP 6 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 6: 92 STG CLOSE DRY ==========', 0, 1) WITH NOWAIT;
    RAISERROR('Dosya: prodEnergy/90_afl_frk/92_stg_inv_pay_close_apply.sql', 0, 1) WITH NOWAIT;
    RAISERROR('Icinde: @DRY_RUN = 1; @AGR_ID = NULL;', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 7 — 92 STG CLOSE APPLY
   ============================================================================= */
IF CONVERT(INT, SESSION_CONTEXT(N'post613_step')) <> 7
    RAISERROR('STEP 7 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 7: 92 STG CLOSE APPLY ==========', 0, 1) WITH NOWAIT;
    RAISERROR('92_stg_inv_pay_close_apply.sql → @DRY_RUN = 0;', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 8 — VALIDATE EXECs
   ============================================================================= */
IF CONVERT(INT, SESSION_CONTEXT(N'post613_step')) <> 8
    RAISERROR('STEP 8 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 8 VALIDATE ==========', 0, 1) WITH NOWAIT;

    /* GATE tekrar (opsiyonel guvence) */
    EXEC dbo.SP_MIG_597_GATE @AGR_ID = NULL;

    /* Sozlesme FRK — sadece farklar */
    IF OBJECT_ID('dbo.SP_AGR_FRK_ALL', 'P') IS NOT NULL
        EXEC dbo.SP_AGR_FRK_ALL @Agr = NULL, @OnlyDiff = 1, @WriteTable = 1, @ReturnResult = 0;
    ELSE
        RAISERROR('SP_AGR_FRK_ALL yok — once 97_agr_frk_all.sql deploy', 16, 1);

    RAISERROR('Dosya check: 90_check_queries.sql | 95_ttk... | 99_afl_vs_en...', 0, 1) WITH NOWAIT;
    RAISERROR('  prodREADY_ENERGY3007/90_check_queries.sql', 0, 1) WITH NOWAIT;
    RAISERROR('  90_afl_frk/95_ttk_inv_afl_fatura_rapor.sql', 0, 1) WITH NOWAIT;
    RAISERROR('  90_afl_frk/99_afl_vs_en_kalan_frk.sql', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 9 — 20a (opsiyonel)
   ============================================================================= */
IF CONVERT(INT, SESSION_CONTEXT(N'post613_step')) <> 9
    RAISERROR('STEP 9 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 9: 20a MGR TAH MAP (opsiyonel) ==========', 0, 1) WITH NOWAIT;
    RAISERROR('Dosya: prodREADY_ENERGY/20a_597_TAH_MAP_FAST_FILL.sql', 0, 1) WITH NOWAIT;
    RAISERROR('Cutover bloklamaz — baska pencerede OK', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   STEP 10 — OZET
   ============================================================================= */
IF CONVERT(INT, SESSION_CONTEXT(N'post613_step')) <> 10
    RAISERROR('STEP 10 atlandi', 0, 1) WITH NOWAIT;
ELSE
BEGIN
    RAISERROR('========== STEP 10 OZET ==========', 0, 1) WITH NOWAIT;
    SELECT 'EN_PLAN' k, COUNT_BIG(*) n FROM dbo.LS_005_01_INSTALLMENT_PLAN WITH (NOLOCK)
    UNION ALL SELECT 'PT_INST_GT0', COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
        WHERE IOCODE = 0 AND INST_NR > 0 AND ISNULL(CANCELED,0)=0 AND ISNULL(CANCELLATIONPAYMENT,0)=0
    UNION ALL SELECT 'MAP_PAY', COUNT_BIG(*) FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
        WHERE OV_KIND = 'PAY_PT' AND ENERGY_LREF IS NOT NULL
    UNION ALL SELECT 'MAP_TAH', COUNT_BIG(*) FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
        WHERE OV_KIND = 'TAH_INV' AND ENERGY_LREF IS NOT NULL;
END
GO

/*
--- Hizli kopyala (613 BITTIKTEN SONRA, sira) ---

-- 40 APPLY: dosyada @DRY_RUN=0 sonra:
--   sqlcmd -S 172.16.1.195 -d energy -C -I -f 65001 -i 40_installment_plan_pay_apply.sql

-- 35 APPLY: dosyada @DRY_RUN=0
--   sqlcmd ... -i 35_bankref_resolve_abys.sql

-- 92 APPLY: dosyada @DRY_RUN=0
--   sqlcmd ... -i ..\90_afl_frk\92_stg_inv_pay_close_apply.sql

-- Validate:
EXEC dbo.SP_MIG_597_GATE @AGR_ID = NULL;
EXEC dbo.SP_AGR_FRK_ALL @Agr = NULL, @OnlyDiff = 1, @WriteTable = 1;

--- 613 hâlâ kosuyorsa sadece ---
-- 50e_TAKSIT_EXECS.sql tekrar (RESUME)
*/
GO
