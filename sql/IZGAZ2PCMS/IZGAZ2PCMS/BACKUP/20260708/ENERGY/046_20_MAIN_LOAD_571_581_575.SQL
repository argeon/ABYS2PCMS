-- =============================================================================
-- prodREADY_ENERGY3007 / 20_main_load_571_581_575.sql
-- Ana yukleme — overlay ONCESI. GATE_FAIL yoksa calistir.
-- O14 LS_DEBT_PAYTRANS ile 575'i AYNI ANDA cift yazma.
--
-- @AGR_ID: NULL=FULL | >0=tek AGR | -1=NO_AGR (NULL AGR + ACCOUNT)
-- =============================================================================
USE energy;
GO
SET NOCOUNT ON;

/* >>> OPERATOR: NULL=FULL, >0=AGR, -1=NO_AGR <<< */
DECLARE @AGR_ID BIGINT = NULL;  -- ornek: 197168 / 1034469 / -1
-- SET @AGR_ID = 197168;

RAISERROR('========== E3007-B1) 571 INVOICE ==========', 0, 1) WITH NOWAIT;
PRINT 'AGR=' + CASE WHEN @AGR_ID IS NULL THEN 'FULL' WHEN @AGR_ID = -1 THEN 'NO_AGR' ELSE CAST(@AGR_ID AS VARCHAR(20)) END;
IF OBJECT_ID('dbo.SP_MIGRATE_LS005_INVOICE', 'P') IS NULL
    RAISERROR('SP_MIGRATE_LS005_INVOICE yok — 571 deploy', 16, 1);
ELSE
    EXEC dbo.SP_MIGRATE_LS005_INVOICE
        @BATCH_SIZE = 50000,
        @RESUME     = 1,
        @HARD_RESET = 0,
        @AGR_ID     = @AGR_ID,
        @DEBUG      = 1;

RAISERROR('========== E3007-B2) 581 INVLINES ==========', 0, 1) WITH NOWAIT;
IF OBJECT_ID('dbo.SP_MIGRATE_LS005_INVLINES', 'P') IS NULL
    RAISERROR('SP_MIGRATE_LS005_INVLINES yok — 581 deploy', 16, 1);
ELSE
    EXEC dbo.SP_MIGRATE_LS005_INVLINES
        @BATCH_SIZE = 100000,
        @RESUME     = 1,
        @HARD_RESET = 0,
        @RANGE_MODE = 'KEYSET',
        @DEBUG      = 1;

RAISERROR('========== E3007-B3) 575 DEBT PAYTRANS ==========', 0, 1) WITH NOWAIT;
PRINT 'AGR=' + CASE WHEN @AGR_ID IS NULL THEN 'FULL' WHEN @AGR_ID = -1 THEN 'NO_AGR' ELSE CAST(@AGR_ID AS VARCHAR(20)) END;
IF OBJECT_ID('dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS', 'P') IS NULL
    RAISERROR('SP_MIGRATE_LS005_DEBT_PAYTRANS yok — 575 deploy', 16, 1);
ELSE
    EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
        @BATCH_SIZE = 50000,
        @RESUME     = 1,
        @HARD_RESET = 0,
        @AGR_ID     = @AGR_ID,
        @DEBUG      = 1;

PRINT '========== E3007-B OK AGR=' + CAST(@AGR_ID AS VARCHAR(20)) + ' — simdi 30_overlay ==========';
GO
