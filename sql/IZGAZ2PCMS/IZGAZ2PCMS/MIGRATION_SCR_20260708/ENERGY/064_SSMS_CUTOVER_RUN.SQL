/* =============================================================================
   prodREADY_ENERGY / SSMS_CUTOVER_RUN.sql
   SSMS: energy baglan → bu dosyayi ac → F5 (veya adim adim highlight)

   SIRA:
     0) PRECHECK (SP / compat)
     1) INDEX  (izgazMGR — yoksa olustur; 350M INVLINES uzun surebilir)
     2) CLEAN  (kirli ABYS / yanlis sira artigi)
     3) MIGRATE 571 → 581 → 575
     4) OVERLAY 590 → 597
     5) LOG

   KONTROL (ustteki bayraklar): 1=calistir, 0=atla
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ========== BAYRAKLAR — ihtiyaca gore 0/1 ========== */
EXEC sys.sp_set_session_context N'cut_do_index',   1;  /* 1=index create */
EXEC sys.sp_set_session_context N'cut_do_clean',   1;  /* 1=HARD_RESET zinciri */
EXEC sys.sp_set_session_context N'cut_do_migrate', 1;  /* 1=571/581/575 */
EXEC sys.sp_set_session_context N'cut_do_overlay', 1;  /* 1=590/597 */
GO

/* =============================================================================
   0) PRECHECK
   ============================================================================= */
RAISERROR('========== 0) PRECHECK ==========', 0, 1) WITH NOWAIT;

IF (SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME()) < 110
BEGIN
    RAISERROR('energy compatibility_level < 110 — ALTER DATABASE ... SET COMPATIBILITY_LEVEL = 160', 16, 1);
    RETURN;
END

IF OBJECT_ID('dbo.SP_MIGRATE_LS005_INVOICE', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIGRATE_LS005_INVLINES', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_590_ALL', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_597_ALL', 'P') IS NULL
BEGIN
    RAISERROR('Kritik SP eksik — once 08_DEPLOY / 569-575 + 10-29 deploy et.', 16, 1);
    RETURN;
END

RAISERROR('PRECHECK OK (compat + SP)', 0, 1) WITH NOWAIT;
GO

/* =============================================================================
   1) INDEX — zorunlu (571 ACTION, 581 LREF)
   ============================================================================= */
IF CONVERT(INT, SESSION_CONTEXT(N'cut_do_index')) = 1
BEGIN
    RAISERROR('========== 1) INDEX (izgazMGR) — uzun surebilir ==========', 0, 1) WITH NOWAIT;
END
ELSE
    RAISERROR('========== 1) INDEX ATLANDI ==========', 0, 1) WITH NOWAIT;
GO

USE izgazMGR;
GO

IF CONVERT(INT, SESSION_CONTEXT(N'cut_do_index')) = 1
AND OBJECT_ID('dbo.LS_INVOICE', 'U') IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.LS_INVOICE') AND name = 'IX_MIG_LSINV_ACTION')
BEGIN
    RAISERROR('CREATE IX_MIG_LSINV_ACTION ...', 0, 1) WITH NOWAIT;
    CREATE NONCLUSTERED INDEX IX_MIG_LSINV_ACTION
        ON dbo.LS_INVOICE (ABYS_ACTION_ID)
        WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
END
GO

IF CONVERT(INT, SESSION_CONTEXT(N'cut_do_index')) = 1
AND OBJECT_ID('dbo.LS_INVOICE', 'U') IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.LS_INVOICE') AND name = 'IX_MIG_LSINV_AGR_ACTION')
BEGIN
    RAISERROR('CREATE IX_MIG_LSINV_AGR_ACTION ...', 0, 1) WITH NOWAIT;
    CREATE NONCLUSTERED INDEX IX_MIG_LSINV_AGR_ACTION
        ON dbo.LS_INVOICE (ABYS_AGREEMENT_ID, ABYS_ACTION_ID)
        INCLUDE (PAYABLETOTAL, TLTOTAL, TAX, GRANDTOTAL, IOCODE, LREF)
        WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
END
GO

IF CONVERT(INT, SESSION_CONTEXT(N'cut_do_index')) = 1
AND OBJECT_ID('dbo.LS_INVLINES', 'U') IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.LS_INVLINES') AND name = 'IX_MIG_LSINVLINES_LREF')
BEGIN
    RAISERROR('CREATE IX_MIG_LSINVLINES_LREF (350M+) — bekleyin ...', 0, 1) WITH NOWAIT;
    CREATE NONCLUSTERED INDEX IX_MIG_LSINVLINES_LREF
        ON dbo.LS_INVLINES (LREF)
        WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
END
GO

IF CONVERT(INT, SESSION_CONTEXT(N'cut_do_index')) = 1
AND OBJECT_ID('dbo.LS_INVLINES', 'U') IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.LS_INVLINES') AND name = 'IX_MIG_LSIL_INVREF')
BEGIN
    RAISERROR('CREATE IX_MIG_LSIL_INVREF ...', 0, 1) WITH NOWAIT;
    CREATE NONCLUSTERED INDEX IX_MIG_LSIL_INVREF
        ON dbo.LS_INVLINES (INVOICEREF)
        INCLUDE (LREF, GRANDTOTAL, ABYS_INCOME_ROW_ID)
        WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
END
GO

/* Index dogrulama — yoksa MIGRATE durdur */
USE energy;
GO
IF CONVERT(INT, SESSION_CONTEXT(N'cut_do_migrate')) = 1
   OR CONVERT(INT, SESSION_CONTEXT(N'cut_do_overlay')) = 1
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM izgazMGR.sys.indexes
        WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_INVOICE') AND name = 'IX_MIG_LSINV_ACTION'
    )
    BEGIN
        RAISERROR('IX_MIG_LSINV_ACTION yok — index adimini tamamla (@cut_do_index=1).', 16, 1);
        RETURN;
    END
    IF NOT EXISTS (
        SELECT 1 FROM izgazMGR.sys.indexes
        WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_INVLINES') AND name = 'IX_MIG_LSINVLINES_LREF'
    )
    BEGIN
        RAISERROR('IX_MIG_LSINVLINES_LREF yok — index adimini tamamla (@cut_do_index=1).', 16, 1);
        RETURN;
    END
    RAISERROR('INDEX OK', 0, 1) WITH NOWAIT;
END
GO

/* =============================================================================
   2) CLEAN — child → parent
   ============================================================================= */
USE energy;
GO
IF CONVERT(INT, SESSION_CONTEXT(N'cut_do_clean')) = 1
BEGIN
    RAISERROR('========== 2) CLEAN ==========', 0, 1) WITH NOWAIT;

    RAISERROR('--- PAYTRANS HARD_RESET ---', 0, 1) WITH NOWAIT;
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
        RAISERROR('PAYTRANS ABYS +%d (toplam %I64d)', 0, 1, @d, @n) WITH NOWAIT;
    END

    RAISERROR('--- INVLINES HARD_RESET ---', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_INVLINES_HARD_RESET @DELETE_BATCH = 100000, @DEBUG = 1;

    RAISERROR('--- INVOICE HARD_RESET ---', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_INVOICE_HARD_RESET @DELETE_BATCH = 50000, @DEBUG = 1;

    UPDATE dbo.MIG_OV_ID_MAP SET ENERGY_LREF = NULL WHERE ENERGY_LREF IS NOT NULL;
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_ID_MAP', 'U') IS NOT NULL
        UPDATE izgazMGR.dbo.LS_OV_ID_MAP SET ENERGY_LREF = NULL WHERE ENERGY_LREF IS NOT NULL;

    RAISERROR('CLEAN OK', 0, 1) WITH NOWAIT;
END
ELSE
    RAISERROR('========== 2) CLEAN ATLANDI ==========', 0, 1) WITH NOWAIT;
GO

/* =============================================================================
   3) ANA MIGRATE
   ============================================================================= */
USE energy;
GO
IF CONVERT(INT, SESSION_CONTEXT(N'cut_do_migrate')) = 1
BEGIN
    RAISERROR('========== 3a) 571 INVOICE ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIGRATE_LS005_INVOICE
        @BATCH_SIZE = 50000,
        @RESUME     = 1,
        @HARD_RESET = 0,
        @AGR_ID     = NULL,
        @DEBUG      = 1;
END
GO

IF CONVERT(INT, SESSION_CONTEXT(N'cut_do_migrate')) = 1
BEGIN
    RAISERROR('========== 3b) 581 INVLINES ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIGRATE_LS005_INVLINES
        @BATCH_SIZE      = 100000,
        @RESUME          = 1,
        @HARD_RESET      = 0,
        @RANGE_MODE      = 'KEYSET',
        @SKIP_PERF_CHECK = 0,
        @DEBUG           = 1;
END
GO

IF CONVERT(INT, SESSION_CONTEXT(N'cut_do_migrate')) = 1
BEGIN
    RAISERROR('========== 3c) 575 DEBT PAYTRANS ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
        @BATCH_SIZE = 50000,
        @RESUME     = 1,
        @HARD_RESET = 0,
        @AGR_ID     = NULL,
        @DEBUG      = 1;
    RAISERROR('ANA MIGRATE OK', 0, 1) WITH NOWAIT;
END
ELSE
    RAISERROR('========== 3) MIGRATE ATLANDI ==========', 0, 1) WITH NOWAIT;
GO

/* =============================================================================
   4) OVERLAY
   ============================================================================= */
USE energy;
GO
IF CONVERT(INT, SESSION_CONTEXT(N'cut_do_overlay')) = 1
BEGIN
    RAISERROR('========== 4a) 590 EKSILTEN ==========', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_590_ALL @AGR_ID = NULL, @CLEAN = 1, @DEBUG = 1;
END
GO

IF CONVERT(INT, SESSION_CONTEXT(N'cut_do_overlay')) = 1
BEGIN
    RAISERROR('========== 4b) 597 — once 20b INV+PT NCIX OFF (R17) ==========', 0, 1) WITH NOWAIT;
    RAISERROR('Dosya: 20b_INVOICE_NCIX_DISABLE + 20b_PAYTRANS_NCIX_DISABLE', 0, 1) WITH NOWAIT;
    RAISERROR('Sonra: SP_MIG_597_ALL → GATE → probe bad_map → (20e/@CLEAN=0) → 20c', 0, 1) WITH NOWAIT;
    RAISERROR('Detay: SSMS_TAHSILAT_EXECS step 9–12 | RUN_ORDER D', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_597_ALL @AGR_ID = NULL, @CLEAN = 1, @DEBUG = 1, @BatchSize = 250000;
    /* Post: GATE + probe (CUTOVER_ONE_PAGE §2). bad_map>0 → 20e + ALL @CLEAN=0 */
END
ELSE
    RAISERROR('========== 4) OVERLAY ATLANDI ==========', 0, 1) WITH NOWAIT;
GO

/* =============================================================================
   5) LOG
   ============================================================================= */
USE energy;
GO
RAISERROR('========== 5) LOG STATUS ==========', 0, 1) WITH NOWAIT;
IF OBJECT_ID('dbo.SP_MIG_LOG_STATUS', 'P') IS NOT NULL
    EXEC dbo.SP_MIG_LOG_STATUS;

SELECT 'INVOICE' AS T, COUNT(*) AS CNT, SUM(CASE WHEN ABYS_ID IS NOT NULL THEN 1 ELSE 0 END) AS ABYS_CNT
FROM dbo.LS_005_01_INVOICE
UNION ALL
SELECT 'INVLINES', COUNT(*), SUM(CASE WHEN ABYS_ID IS NOT NULL THEN 1 ELSE 0 END)
FROM dbo.LS_005_01_INVLINES
UNION ALL
SELECT 'PAYTRANS', COUNT(*), SUM(CASE WHEN ABYS_ID IS NOT NULL THEN 1 ELSE 0 END)
FROM dbo.LS_005_01_PAYTRANS;

RAISERROR('========== SSMS_CUTOVER_RUN BITTI ==========', 0, 1) WITH NOWAIT;
GO

/*
   Sadece migrate (index+clean yapildiysa):
     cut_do_index=0, cut_do_clean=0, cut_do_migrate=1, cut_do_overlay=1

   Sadece overlay:
     cut_do_index=0, cut_do_clean=0, cut_do_migrate=0, cut_do_overlay=1
*/
