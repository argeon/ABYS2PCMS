/* =============================================================================
   prodREADY_ENERGY3007 / 50e_TAKSIT_EXECS.sql
   Taksit zinciri — SADECE EXEC / sqlcmd adımları (deploy ayrı: 00e + 611/613)

   Onkosul (deploy edilmiş olmalı):
     - 00e_taksit_staging.sql
     - 00e_mgr_cs_installment_indexes.sql
     - 00e_energy_installment_plan_indexes.sql  (IX_MIG_LS005_IP_AGR — 613 P0)
     - 611 / 611b / 613 SP
     - 597 GATE_PASS
     - UX_LS005_PAYTRANS_DEBT_INVOICEREF DROP + UX_MIG_PT_DEBT_INV_INST0/INSTN CREATE
       (eski tum-borc UX 613 Msg 2601; yeni filtreli UX taksit uyumlu)

   NOT: 613 FULL ~107k AGR. ABYS_AGREEMENT_ID index yoksa her AGR
        PLAN full-scan (~24k read) → 6h+; E3 öncesi yoksa CREATE.

   @AGR_ID:
     NULL  = FULL
     >0    = tek AGR (pilot örn. 197168)

   Sıra: 611 → wire → 613 → 40 → (opsiyonel) 92 → 90 check
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

/* >>> OPERATOR <<< */
DECLARE @AGR_ID BIGINT = NULL;   -- FULL
-- DECLARE @AGR_ID BIGINT = 197168;  -- pilot

DECLARE @DEBUG BIT = 1;
PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121)
    + N' | TAKSIT EXEC START AGR='
    + CASE WHEN @AGR_ID IS NULL THEN N'FULL' ELSE CAST(@AGR_ID AS VARCHAR(20)) END;

/* ---- precheck ---- */
IF OBJECT_ID('dbo.MIG_611_STG_IP_KEYS', 'U') IS NULL
   OR OBJECT_ID('dbo.MIG_613_STG_NEW', 'U') IS NULL
   OR OBJECT_ID('dbo.MIG_40_STG_IPP', 'U') IS NULL
BEGIN
    RAISERROR('Staging yok — once 00e_taksit_staging.sql', 16, 1);
    RETURN;
END
IF OBJECT_ID('dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR', 'P') IS NULL
BEGIN
    RAISERROR('611/613 SP eksik — deploy', 16, 1);
    RETURN;
END

/* ---- UX: eski tum-borc unique DROP; INST0/INSTN unique CREATE ---- */
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
      AND name = 'UX_LS005_PAYTRANS_DEBT_INVOICEREF'
)
BEGIN
    DROP INDEX UX_LS005_PAYTRANS_DEBT_INVOICEREF ON dbo.LS_005_01_PAYTRANS;
    PRINT 'DROP UX_LS005_PAYTRANS_DEBT_INVOICEREF';
END
ELSE
    PRINT 'UX debt yok (OK)';

/* Filtered index: OR / ISNULL / IS NULL yasak. NULL ≈ 0 → normalize, sonra = 0. */
UPDATE dbo.LS_005_01_PAYTRANS SET CANCELED = 0 WHERE IOCODE = 0 AND CANCELED IS NULL;
UPDATE dbo.LS_005_01_PAYTRANS SET CANCELLATIONPAYMENT = 0 WHERE IOCODE = 0 AND CANCELLATIONPAYMENT IS NULL;

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
      AND name = N'UX_MIG_PT_DEBT_INV_INST0'
)
BEGIN
    BEGIN TRY
        CREATE UNIQUE NONCLUSTERED INDEX UX_MIG_PT_DEBT_INV_INST0
            ON dbo.LS_005_01_PAYTRANS (INVOICEREF)
            WHERE IOCODE = 0 AND INST_NR = 0 AND CANCELED = 0 AND CANCELLATIONPAYMENT = 0
            WITH (MAXDOP = 8, SORT_IN_TEMPDB = ON);
        PRINT 'CREATE UX_MIG_PT_DEBT_INV_INST0';
    END TRY
    BEGIN CATCH
        PRINT 'WARN UX_MIG_PT_DEBT_INV_INST0 — once 91_debt_pt_dup_cleanup.sql: ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
    PRINT 'UX_MIG_PT_DEBT_INV_INST0 exists';

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
      AND name = N'UX_MIG_PT_DEBT_INV_INSTN'
)
BEGIN
    BEGIN TRY
        CREATE UNIQUE NONCLUSTERED INDEX UX_MIG_PT_DEBT_INV_INSTN
            ON dbo.LS_005_01_PAYTRANS (INVOICEREF, INST_NR)
            WHERE IOCODE = 0 AND INST_NR > 0 AND CANCELED = 0 AND CANCELLATIONPAYMENT = 0
            WITH (MAXDOP = 8, SORT_IN_TEMPDB = ON);
        PRINT 'CREATE UX_MIG_PT_DEBT_INV_INSTN';
    END TRY
    BEGIN CATCH
        PRINT 'WARN UX_MIG_PT_DEBT_INV_INSTN: ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
    PRINT 'UX_MIG_PT_DEBT_INV_INSTN exists';
GO

/* =============================================================================
   E1) 611 — INSTALLMENT_PLAN INSERT
   ============================================================================= */
USE energy;
GO
DECLARE @AGR_ID BIGINT = NULL;  -- FULL | veya 197168
-- SET @AGR_ID = 197168;

PRINT '========== E1) 611 INSTALLMENT_PLAN ==========';
EXEC dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
    @BATCH_SIZE = 50000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @AGR_ID     = @AGR_ID,
    @DEBUG      = 1;
GO

/* =============================================================================
   E2) 611b — PLAN → INVOICE wire
   ============================================================================= */
USE energy;
GO
DECLARE @AGR_ID BIGINT = NULL;
-- SET @AGR_ID = 197168;

PRINT '========== E2) 611b WIRE INVOICE ==========';
EXEC dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE
    @AGR_ID = @AGR_ID,
    @DEBUG  = 1;

SELECT COUNT_BIG(*) AS EN_PLAN
FROM dbo.LS_005_01_INSTALLMENT_PLAN WITH (NOLOCK);
GO

/* =============================================================================
   E2b) 613 öncesi P0 index — LS_005_01_INSTALLMENT_PLAN(ABYS_AGREEMENT_ID)
   Yoksa CREATE ONLINE (00e_energy_installment_plan_indexes.sql ile aynı).
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

PRINT '========== E2b) IX_MIG_LS005_IP_AGR (613 P0) ==========';
IF OBJECT_ID('dbo.LS_005_01_INSTALLMENT_PLAN', 'U') IS NULL
BEGIN
    RAISERROR('LS_005_01_INSTALLMENT_PLAN yok — 611 once', 16, 1);
    RETURN;
END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.LS_005_01_INSTALLMENT_PLAN')
      AND name = N'IX_MIG_LS005_IP_AGR'
)
BEGIN
    RAISERROR('CREATE ONLINE IX_MIG_LS005_IP_AGR (613 zorunlu) ...', 0, 1) WITH NOWAIT;
    CREATE NONCLUSTERED INDEX IX_MIG_LS005_IP_AGR
        ON dbo.LS_005_01_INSTALLMENT_PLAN (ABYS_AGREEMENT_ID)
        INCLUDE (
            LREF, PLAN_ID, ABYS_ID, ABYS_INSTALLMENT_ID, ISACTIVE,
            ABYS_CANCELLATION_DATE, ABYS_CANCEL_CAUSE_ID, ABYS_CANCELLATION_USER_ID,
            TOTAL_AMOUNT, INSTALLMENT_COUNT, ABYS_ORDER_NUMBER,
            PAYTRANS_REF, INVOICE_REF, ABYS_DUE_DATE, ABYS_EXPIRY_DATE
        )
        WITH (ONLINE = ON, MAXDOP = 24, SORT_IN_TEMPDB = ON);
    RAISERROR('OK IX_MIG_LS005_IP_AGR', 0, 1) WITH NOWAIT;
END
ELSE
    RAISERROR('SKIP IX_MIG_LS005_IP_AGR (exists)', 0, 1) WITH NOWAIT;
GO

/* =============================================================================
   E3) 613 — CANCEL NORMALIZE + DEBT SPLIT
   FULL: AGR döngüsü (serial). Pilot: tek AGR.
   Resume: aktif INST_NR>0 PT olan AGR listeden çıkarılır (done_skip).
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;

DECLARE @AGR_ID BIGINT = NULL;  -- NULL=FULL loop | >0=tek AGR
-- SET @AGR_ID = 197168;
DECLARE @DEBUG BIT = 1;
DECLARE @i INT = 1, @n INT, @agr BIGINT, @try INT, @ok BIT;
DECLARE @done_skip INT = 0, @total_agr INT = 0;
DECLARE @Msg NVARCHAR(400);

PRINT '========== E3) 613 NORMALIZE + SPLIT ==========';

/* Hard gate: index yoksa 613'e girme */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.LS_005_01_INSTALLMENT_PLAN')
      AND name = N'IX_MIG_LS005_IP_AGR'
)
BEGIN
    RAISERROR('IX_MIG_LS005_IP_AGR yok — E2b / 00e_energy_installment_plan_indexes.sql', 16, 1);
    RETURN;
END

IF @AGR_ID IS NOT NULL
BEGIN
    /* ---- PILOT: tek AGR ---- */
    /* Zaten split edilmisse skip */
    IF EXISTS (
        SELECT 1 FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
        WHERE pt.ABYS_AGREEMENT_ID = @AGR_ID
          AND ISNULL(pt.IOCODE, 0) = 0
          AND ISNULL(pt.INST_NR, 0) > 0
          AND ISNULL(pt.CANCELED, 0) = 0
          AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
    )
    BEGIN
        SET @Msg = N'613 SKIP (done) AGR=' + CAST(@AGR_ID AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
    ELSE
    BEGIN
        EXEC dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR
            @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;
        EXEC dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR
            @AGR_ID = @AGR_ID, @DEBUG = @DEBUG, @DO_RESEED = 1;
    END
END
ELSE
BEGIN
    /* ---- FULL: serial AGR list — resume: INST_NR>0 olan AGR atlanır ---- */
    IF OBJECT_ID('dbo.MIG_613_STG_AGR_LIST', 'U') IS NULL
    BEGIN
        RAISERROR('MIG_613_STG_AGR_LIST yok', 16, 1);
        RETURN;
    END

    SELECT @total_agr = COUNT(DISTINCT pl.ABYS_AGREEMENT_ID)
    FROM dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
    WHERE pl.ABYS_AGREEMENT_ID IS NOT NULL;

    SELECT @done_skip = COUNT(DISTINCT pl.ABYS_AGREEMENT_ID)
    FROM dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
    WHERE pl.ABYS_AGREEMENT_ID IS NOT NULL
      AND EXISTS (
            SELECT 1
            FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
            WHERE pt.ABYS_AGREEMENT_ID = pl.ABYS_AGREEMENT_ID
              AND ISNULL(pt.IOCODE, 0) = 0
              AND ISNULL(pt.INST_NR, 0) > 0
              AND ISNULL(pt.CANCELED, 0) = 0
              AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
          );

    /* Sadece acik borcu olan AGR (INST_NR=0 unpaid).
       INST_NR>0 yok + borc yok ≈ 60k bos tur → FULL sureyi olduruyordu. */
    TRUNCATE TABLE dbo.MIG_613_STG_AGR_LIST;
    INSERT INTO dbo.MIG_613_STG_AGR_LIST (ORD, AGR_ID)
    SELECT ROW_NUMBER() OVER (ORDER BY AGR_ID), AGR_ID
    FROM (
        SELECT DISTINCT pl.ABYS_AGREEMENT_ID AS AGR_ID
        FROM dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
        WHERE pl.ABYS_AGREEMENT_ID IS NOT NULL
          AND NOT EXISTS (
                SELECT 1
                FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
                WHERE pt.ABYS_AGREEMENT_ID = pl.ABYS_AGREEMENT_ID
                  AND pt.IOCODE = 0
                  AND pt.INST_NR > 0
                  AND ISNULL(pt.CANCELED, 0) = 0
                  AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
              )
          AND EXISTS (
                SELECT 1
                FROM dbo.LS_005_01_PAYTRANS d WITH (NOLOCK)
                WHERE d.ABYS_AGREEMENT_ID = pl.ABYS_AGREEMENT_ID
                  AND d.IOCODE = 0
                  AND ISNULL(d.INST_NR, 0) = 0
                  AND ISNULL(d.CANCELED, 0) = 0
                  AND ISNULL(d.CANCELLATIONPAYMENT, 0) = 0
                  AND ISNULL(d.PAID, 0) < ISNULL(d.PAYABLETOTAL, 0) - 0.02
              )
    ) x;

    SELECT @n = COUNT(*) FROM dbo.MIG_613_STG_AGR_LIST;
    SET @Msg = N'613 RESUME total=' + CAST(@total_agr AS VARCHAR(20))
             + N' done_skip=' + CAST(@done_skip AS VARCHAR(20))
             + N' pending_open_debt=' + CAST(@n AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    IF @n = 0
    BEGIN
        RAISERROR('613: pending=0 — hepsi done', 0, 1) WITH NOWAIT;
    END
    ELSE
    WHILE @i <= @n
    BEGIN
        SELECT @agr = AGR_ID FROM dbo.MIG_613_STG_AGR_LIST WHERE ORD = @i;
        SET @try = 0; SET @ok = 0;

        WHILE @ok = 0 AND @try < 5
        BEGIN
            SET @try += 1;
            BEGIN TRY
                EXEC dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR
                    @AGR_ID = @agr, @DEBUG = 0;
                EXEC dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR
                    @AGR_ID = @agr, @DEBUG = 0, @DO_RESEED = 0;
                SET @ok = 1;
            END TRY
            BEGIN CATCH
                IF ERROR_NUMBER() = 1205
                    WAITFOR DELAY '00:00:00.200';
                ELSE
                BEGIN
                    IF OBJECT_ID('dbo.MIG_613_ERR', 'U') IS NOT NULL
                        INSERT INTO dbo.MIG_613_ERR (AGR_ID, TRY_N, ERR_NUM, ERR_MSG)
                        VALUES (@agr, @try, ERROR_NUMBER(), ERROR_MESSAGE());
                    SET @Msg = N'ERR AGR=' + CAST(@agr AS VARCHAR(20)) + N' ' + ERROR_MESSAGE();
                    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
                    SET @ok = 1;
                END
            END CATCH
        END

        IF @i = 1 OR @i = @n OR @i % 100 = 0
        BEGIN
            SET @Msg = N'613 ' + CAST(@i AS VARCHAR(10)) + N'/' + CAST(@n AS VARCHAR(20))
                     + N' (skip=' + CAST(@done_skip AS VARCHAR(20)) + N')';
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
        SET @i += 1;
    END

    /* FULL sonunda tek reseed */
    DBCC CHECKIDENT ('dbo.LS_005_01_PAYTRANS', RESEED);

    IF OBJECT_ID('dbo.MIG_613_ERR', 'U') IS NOT NULL
    BEGIN
        SELECT @n = COUNT(*) FROM dbo.MIG_613_ERR WITH (NOLOCK)
        WHERE RUN_TS >= DATEADD(HOUR, -12, SYSDATETIME());
        SET @Msg = N'613 ERR (12h)=' + CAST(@n AS VARCHAR(20)) + N' → SELECT * FROM dbo.MIG_613_ERR';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END

SELECT
  (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
    WHERE IOCODE = 0 AND INST_NR > 0) AS EN_INST_GT0;
GO

/* =============================================================================
   E4) 40 — IPP APPLY
   Script parametreli; aşağıda aynı mantık @DRY_RUN=0 ile.
   Alternatif: sqlcmd -i 40_installment_plan_pay_apply.sql  (önce dosyada DRY_RUN=0)
   ============================================================================= */
PRINT '========== E4) 40 IPP — sqlcmd ile calistir ==========';
PRINT '  Dosya: prodREADY_ENERGY3007/40_installment_plan_pay_apply.sql';
PRINT '  SET @DRY_RUN = 0;  SET @AGR_ID = NULL;  -- veya 197168';
PRINT '  sqlcmd -S 172.16.1.195 -d energy -C -I -i 40_installment_plan_pay_apply.sql';
GO

/* =============================================================================
   E5) 92 STG close (opsiyonel / sonraki)
   ============================================================================= */
PRINT '========== E5) 92 STG CLOSE ==========';
PRINT '  sqlcmd -i ../90_afl_frk/92_stg_inv_pay_close_apply.sql  (@DRY_RUN=0)';
GO

/* =============================================================================
   E6) 90 check
   ============================================================================= */
PRINT '========== E6) 90 CHECK ==========';
PRINT '  sqlcmd -i 90_check_queries.sql';
PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + N' | TAKSIT EXEC SCRIPT END (40/92/90 ayri)';
GO

/*
--- Hizli kopyala (pilot 197168) ---

USE energy;
EXEC dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
  @BATCH_SIZE=50000, @RESUME=1, @HARD_RESET=0, @AGR_ID=197168, @DEBUG=1;
EXEC dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE @AGR_ID=197168, @DEBUG=1;
EXEC dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR @AGR_ID=197168, @DEBUG=1;
EXEC dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR @AGR_ID=197168, @DEBUG=1, @DO_RESEED=1;
-- sonra 40: @DRY_RUN=0 @AGR_ID=197168

--- Hizli kopyala (FULL 611+wire; 613 döngü yukarıda) ---

EXEC dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
  @BATCH_SIZE=50000, @RESUME=1, @HARD_RESET=0, @AGR_ID=NULL, @DEBUG=1;
EXEC dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE @AGR_ID=NULL, @DEBUG=1;
*/
