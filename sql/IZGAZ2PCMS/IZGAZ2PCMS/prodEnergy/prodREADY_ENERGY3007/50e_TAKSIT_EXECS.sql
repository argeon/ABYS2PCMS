/* =============================================================================
   prodREADY_ENERGY3007 / 50e_TAKSIT_EXECS.sql
   CREATE OR ALTER PROCEDURE dbo.SP_MIG_50E_TAKSIT  (R24 2026-08-11)

   UX prep + (opsiyonel 611/wire/IP) + 613 open-debt loop.
   SSMS_TAHSILAT step 13–14 sonrası: @Do611=0 @DoWire=0 @DoIpAgr=0 @Do613=1
   Standalone FULL taksit:
     EXEC dbo.SP_MIG_50E_TAKSIT @AGR_ID=NULL, @Do611=1, @DoWire=1, @DoIpAgr=1, @Do613=1;
   ============================================================================= */
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_50E_TAKSIT
    @AGR_ID   BIGINT = NULL,   -- NULL=FULL | >0=pilot
    @DEBUG    BIT    = 1,
    @DoUxPrep BIT    = 1,
    @Do611    BIT    = 0,
    @DoWire   BIT    = 0,
    @DoIpAgr  BIT    = 0,
    @Do613    BIT    = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET IMPLICIT_TRANSACTIONS OFF;

    DECLARE @Msg NVARCHAR(400);
    DECLARE @i INT = 1, @n INT, @agr BIGINT, @try INT, @ok BIT;
    DECLARE @done_skip INT = 0, @total_agr INT = 0;

    SET @Msg = N'SP_MIG_50E_TAKSIT AGR='
             + CASE WHEN @AGR_ID IS NULL THEN N'FULL' ELSE CAST(@AGR_ID AS NVARCHAR(20)) END
             + N' Ux=' + CAST(@DoUxPrep AS NVARCHAR(1))
             + N' 611=' + CAST(@Do611 AS NVARCHAR(1))
             + N' Wire=' + CAST(@DoWire AS NVARCHAR(1))
             + N' Ip=' + CAST(@DoIpAgr AS NVARCHAR(1))
             + N' 613=' + CAST(@Do613 AS NVARCHAR(1));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

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

    /* ---- UX prep ---- */
    IF @DoUxPrep = 1
    BEGIN
        IF EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
              AND name = 'UX_LS005_PAYTRANS_DEBT_INVOICEREF'
        )
        BEGIN
            DROP INDEX UX_LS005_PAYTRANS_DEBT_INVOICEREF ON dbo.LS_005_01_PAYTRANS;
            RAISERROR('DROP UX_LS005_PAYTRANS_DEBT_INVOICEREF', 0, 1) WITH NOWAIT;
        END

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
                RAISERROR('CREATE UX_MIG_PT_DEBT_INV_INST0', 0, 1) WITH NOWAIT;
            END TRY
            BEGIN CATCH
                SET @Msg = N'WARN UX_MIG_PT_DEBT_INV_INST0: ' + ERROR_MESSAGE();
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END CATCH
        END

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
                RAISERROR('CREATE UX_MIG_PT_DEBT_INV_INSTN', 0, 1) WITH NOWAIT;
            END TRY
            BEGIN CATCH
                SET @Msg = N'WARN UX_MIG_PT_DEBT_INV_INSTN: ' + ERROR_MESSAGE();
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END CATCH
        END
    END

    IF @Do611 = 1
    BEGIN
        RAISERROR('========== 50E 611 INSTALLMENT_PLAN ==========', 0, 1) WITH NOWAIT;
        EXEC dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN
            @BATCH_SIZE = 50000, @RESUME = 1, @HARD_RESET = 0,
            @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;
    END

    IF @DoWire = 1
    BEGIN
        RAISERROR('========== 50E 611b WIRE ==========', 0, 1) WITH NOWAIT;
        EXEC dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;
    END

    IF @DoIpAgr = 1
    BEGIN
        IF OBJECT_ID('dbo.SP_MIG_IX_IP_AGR', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_IX_IP_AGR @DEBUG = @DEBUG;
        ELSE
            RAISERROR('SP_MIG_IX_IP_AGR yok — once 26d deploy', 16, 1);
    END

    IF @Do613 = 0
    BEGIN
        RAISERROR('SP_MIG_50E_TAKSIT DONE (613 atlandi)', 0, 1) WITH NOWAIT;
        RETURN;
    END

    /* ---- 613 ---- */
    RAISERROR('========== 50E 613 NORMALIZE + SPLIT ==========', 0, 1) WITH NOWAIT;

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('dbo.LS_005_01_INSTALLMENT_PLAN')
          AND name = N'IX_MIG_LS005_IP_AGR'
    )
    BEGIN
        RAISERROR('IX_MIG_LS005_IP_AGR yok — once SP_MIG_IX_IP_AGR', 16, 1);
        RETURN;
    END

    IF @AGR_ID IS NOT NULL
    BEGIN
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
                SELECT 1 FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
                WHERE pt.ABYS_AGREEMENT_ID = pl.ABYS_AGREEMENT_ID
                  AND ISNULL(pt.IOCODE, 0) = 0
                  AND ISNULL(pt.INST_NR, 0) > 0
                  AND ISNULL(pt.CANCELED, 0) = 0
                  AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
              );

        TRUNCATE TABLE dbo.MIG_613_STG_AGR_LIST;
        INSERT INTO dbo.MIG_613_STG_AGR_LIST (ORD, AGR_ID)
        SELECT ROW_NUMBER() OVER (ORDER BY AGR_ID), AGR_ID
        FROM (
            SELECT DISTINCT pl.ABYS_AGREEMENT_ID AS AGR_ID
            FROM dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
            WHERE pl.ABYS_AGREEMENT_ID IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1 FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
                    WHERE pt.ABYS_AGREEMENT_ID = pl.ABYS_AGREEMENT_ID
                      AND pt.IOCODE = 0 AND pt.INST_NR > 0
                      AND ISNULL(pt.CANCELED, 0) = 0
                      AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
                  )
              AND EXISTS (
                    SELECT 1 FROM dbo.LS_005_01_PAYTRANS d WITH (NOLOCK)
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
            RAISERROR('613: pending=0 — hepsi done', 0, 1) WITH NOWAIT;
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

        DBCC CHECKIDENT ('dbo.LS_005_01_PAYTRANS', RESEED);

        IF OBJECT_ID('dbo.MIG_613_ERR', 'U') IS NOT NULL
        BEGIN
            SELECT @n = COUNT(*) FROM dbo.MIG_613_ERR WITH (NOLOCK)
            WHERE RUN_TS >= DATEADD(HOUR, -12, SYSDATETIME());
            SET @Msg = N'613 ERR (12h)=' + CAST(@n AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    SELECT
        (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
         WHERE IOCODE = 0 AND INST_NR > 0) AS EN_INST_GT0;

    RAISERROR('SP_MIG_50E_TAKSIT DONE — sonra 40/35/92 EXEC', 0, 1) WITH NOWAIT;
END
GO
/* EXEC dbo.SP_MIG_50E_TAKSIT @AGR_ID=NULL, @Do611=0, @DoWire=0, @DoIpAgr=0, @Do613=1; */
