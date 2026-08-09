/* ============================================================
   SCRIPT_ID : TAHSILAT_OVERLAY_FULL
   SCRIPT_NO : 597
   FILE      : 597_TAHSILAT_OVERLAY__full.sql
   VERSION   : 1
   ============================================================ */
-- Adim 5 — Tahsilat PAYTRANS overlay (energy)
-- Onkosul Oracle: oracleCTAS/LS_TAHSILAT_OVERLAY.sql → dump → izgazMGR:
--   LS_OV_TAH_INVOICE (TYPE=101), LS_OV_PAY_PT, LS_OV_DEBT_PAID_UPD,
--   LS_OV_CANCEL_PAY, LS_OV_CANCEL_REV, LS_OV_MAHSUP_CLOSED
-- Onkosul energy: Adim3 debt PT + Adim4a eksilten PASS
--
-- PAY.INVOICEREF = PAY.LREF (tahsilat fisi) — MAIN borca YAZILMAZ (cift satir olmasin)
-- CROSSREF → MAIN borc PT.LREF
-- Index DISABLE YOK; @AGR_ID NULL = FULL (tum izgazMGR satirlari)
-- ============================================================ */
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_TAHSILAT_OVERLAY_CLEAN_BY_AGR
    @AGR_ID       BIGINT,
    @DELETE_BATCH INT = 5000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @Msg NVARCHAR(400), @Batch INT;

    /* @AGR_ID NULL = FULL: filtre yok (tum ABYS_AGREEMENT_ID) */    IF OBJECT_ID('tempdb..#OV_PT') IS NOT NULL DROP TABLE #OV_PT;
    CREATE TABLE #OV_PT (LREF INT NOT NULL PRIMARY KEY);

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_PAY_PT', 'U') IS NOT NULL
        INSERT INTO #OV_PT (LREF)
        SELECT DISTINCT CAST(TRY_CAST(LREF AS BIGINT) AS INT)
        FROM izgazMGR.dbo.LS_OV_PAY_PT WITH (NOLOCK)
        WHERE (@AGR_ID IS NULL OR TRY_CAST(ABYS_AGREEMENT_ID AS BIGINT) = @AGR_ID)
          AND TRY_CAST(LREF AS BIGINT) BETWEEN 1 AND 2147483647;

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_CANCEL_PAY', 'U') IS NOT NULL
        INSERT INTO #OV_PT (LREF)
        SELECT DISTINCT CAST(c.LREF AS INT)
        FROM izgazMGR.dbo.LS_OV_CANCEL_PAY c WITH (NOLOCK)
        WHERE (@AGR_ID IS NULL OR c.ABYS_AGREEMENT_ID = @AGR_ID) AND c.LREF BETWEEN 1 AND 2147483647
          AND NOT EXISTS (SELECT 1 FROM #OV_PT x WHERE x.LREF = CAST(c.LREF AS INT));

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_CANCEL_REV', 'U') IS NOT NULL
        INSERT INTO #OV_PT (LREF)
        SELECT DISTINCT CAST(r.LREF AS INT)
        FROM izgazMGR.dbo.LS_OV_CANCEL_REV r WITH (NOLOCK)
        WHERE (@AGR_ID IS NULL OR r.ABYS_AGREEMENT_ID = @AGR_ID) AND r.LREF BETWEEN 1 AND 2147483647
          AND NOT EXISTS (SELECT 1 FROM #OV_PT x WHERE x.LREF = CAST(r.LREF AS INT));

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'CLEAN keys PT=' + CAST((SELECT COUNT(*) FROM #OV_PT) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    SET @Batch = 0;
    WHILE 1 = 1
    BEGIN
        SET @Batch += 1;
        DELETE TOP (@DELETE_BATCH) pt
        FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (ROWLOCK)
        INNER JOIN #OV_PT k ON k.LREF = pt.LREF
        OPTION (RECOMPILE, MAXDOP 1);
        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'CLEAN TAH PT +' + CAST(@Deleted AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_DEBT_PAID_UPD', 'U') IS NOT NULL
    BEGIN
        UPDATE pt
        SET pt.PAID = 0
        FROM energy.dbo.LS_005_01_PAYTRANS pt
        INNER JOIN izgazMGR.dbo.LS_OV_DEBT_PAID_UPD u WITH (NOLOCK)
            ON pt.INVOICEREF = CAST(u.MAIN_LREF AS INT)
           AND ISNULL(pt.IOCODE, 0) = 0
           AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
        WHERE (@AGR_ID IS NULL OR u.ABYS_AGREEMENT_ID = @AGR_ID)
        OPTION (RECOMPILE, MAXDOP 24);

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'CLEAN debt PAID reset=' + CAST(@@ROWCOUNT AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* mahsup EXPLAIN isaretini geri al (yalniz bizim markalar) */
    UPDATE inv
    SET inv.EXPLAIN = NULL
    FROM energy.dbo.LS_005_01_INVOICE inv
    WHERE (@AGR_ID IS NULL OR inv.ABYS_AGREEMENT_ID = @AGR_ID)
      AND inv.EXPLAIN IN (N'MAHSUP KAPAMA', N'MAHSUP+TAHSILAT KAPAMA')
    OPTION (RECOMPILE, MAXDOP 24);

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'CLEAN mahsup EXPLAIN reset=' + CAST(@@ROWCOUNT AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* TYPE=101 tahsilat fisleri (LREF = PAY.LREF) */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_TAH_INVOICE', 'U') IS NOT NULL
    BEGIN
        SET @Batch = 0;
        WHILE 1 = 1
        BEGIN
            SET @Batch += 1;
            DELETE TOP (@DELETE_BATCH) inv
            FROM energy.dbo.LS_005_01_INVOICE inv WITH (ROWLOCK)
            INNER JOIN izgazMGR.dbo.LS_OV_TAH_INVOICE s WITH (NOLOCK)
                ON inv.LREF = CAST(s.LREF AS INT)
            WHERE (@AGR_ID IS NULL OR s.ABYS_AGREEMENT_ID = @AGR_ID)
            OPTION (RECOMPILE, MAXDOP 1);
            SET @Deleted = @@ROWCOUNT;
            IF @Deleted = 0 BREAK;
            IF @DEBUG = 1
            BEGIN
                SET @Msg = N'CLEAN TAH INV +' + CAST(@Deleted AS VARCHAR(20));
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END
        END
    END

    DROP TABLE #OV_PT;
    IF @DEBUG = 1
        RAISERROR('TAHSILAT OVERLAY CLEAN OK', 0, 1) WITH NOWAIT;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR
    @AGR_ID BIGINT,
    @CLEAN  BIT = 1,
    @DEBUG  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Msg NVARCHAR(500), @N INT, @MaxLref INT;

    /* @AGR_ID NULL = FULL: filtre yok (tum ABYS_AGREEMENT_ID) */    IF OBJECT_ID('izgazMGR.dbo.LS_OV_PAY_PT', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR.dbo.LS_OV_PAY_PT yok. Once Oracle Adim5 dump edin.', 16, 1);
        RETURN;
    END

    IF @CLEAN = 1
        EXEC dbo.SP_MIG_TAHSILAT_OVERLAY_CLEAN_BY_AGR @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;

    /* TYPE=101 tahsilat fisi — PAY.INVOICEREF buna bakar (MAIN borca degil) */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_TAH_INVOICE', 'U') IS NOT NULL
    BEGIN
        SET IDENTITY_INSERT energy.dbo.LS_005_01_INVOICE ON;

        INSERT INTO energy.dbo.LS_005_01_INVOICE WITH (TABLOCK) (
            LREF, IOCODE, FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF,
            TLTOTAL, CURID, CURTOTAL, EXPLAIN, CANCELED, OWNERREF, OWNERTYPE,
            TAX, DV, GRANDTOTAL, PRINTCOUNT, PAYABLETOTAL, CLOSED,
            FITNO, BN_TYPE, AMOUNT, PERIOD, ADDDATE, ADDUSER,
            ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_AGREEMENT_ID
        )
        SELECT
            CAST(s.LREF AS INT),
            CAST(1 AS TINYINT),
            LEFT(ISNULL(s.FICHENO, N'TAHSILAT'), 50),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(ISNULL(s.DUEDATE, s.DATE_) AS DATETIME2)),
            CAST(101 AS TINYINT),
            CAST(s.CLIENTREF AS INT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TLTOTAL)),
            CAST(ISNULL(s.CURID, 160) AS INT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.CURTOTAL)),
            NULL,
            CAST(ISNULL(s.CANCELED, 0) AS BIT),
            TRY_CAST(s.OWNERREF AS INT),
            CAST(ISNULL(s.OWNERTYPE, 91) AS TINYINT),
            CAST(0 AS FLOAT),
            CAST(0 AS FLOAT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.GRANDTOTAL)),
            CAST(0 AS INT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            CAST(1 AS BIT),
            TRY_CAST(s.FITNO AS INT),
            TRY_CAST(s.BN_TYPE AS INT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.AMOUNT)),
            TRY_CAST(s.PERIOD AS INT),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(ISNULL(s.ADDDATE, s.DATE_) AS DATETIME2)),
            CAST(ISNULL(s.ADDUSER, 20001) AS INT),
            s.ABYS_ID,
            s.ABYS_ACCOUNT_ID,
            s.ABYS_ACTION_TYPE_ID,
            s.ABYS_AGREEMENT_ID
        FROM izgazMGR.dbo.LS_OV_TAH_INVOICE s WITH (NOLOCK)
        WHERE (@AGR_ID IS NULL OR s.ABYS_AGREEMENT_ID = @AGR_ID)
          AND s.LREF BETWEEN 1 AND 2147483647
          AND NOT EXISTS (
                SELECT 1 FROM energy.dbo.LS_005_01_INVOICE t
                WHERE t.LREF = CAST(s.LREF AS INT)
              )
        OPTION (RECOMPILE, MAXDOP 24);

        SET @N = @@ROWCOUNT;
        SET IDENTITY_INSERT energy.dbo.LS_005_01_INVOICE OFF;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'TAH INV insert=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    SET IDENTITY_INSERT energy.dbo.LS_005_01_PAYTRANS ON;

    /* INVOICEREF = PAY.LREF (101); CROSSREF = MAIN borc PT; meta MAIN faturadan */
    INSERT INTO energy.dbo.LS_005_01_PAYTRANS WITH (TABLOCK) (
        LREF, INVOICEREF, DATE_, [TYPE], CLIENTREF, CLIENT_TYPE, IOCODE,
        TLTOTAL, PAID, DUEDATE, PAYTYPE, CURID, CURRATE, CURTOTAL,
        CROSSREF, TRANSTYPE, CANCELED, TAX, GRANDTOTAL, LINETYPE, INST_NR,
        PAYABLETOTAL, ADDDATE, ADDUSER, CANCELLATIONPAYMENT, BN_TYPE, XTYPE, PAYCURID,
        ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, ABYS_ACTION_TYPE_ID, ABYS_INVOICE_LREF
    )
    SELECT
        CAST(TRY_CAST(s.LREF AS BIGINT) AS INT),
        CAST(TRY_CAST(s.INVOICEREF AS BIGINT) AS INT),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
        CAST(101 AS TINYINT),
        CAST(ISNULL(s.CLIENTREF, main.CLIENTREF) AS INT),
        CAST(ISNULL(main.OWNERTYPE, 91) AS TINYINT),
        CAST(1 AS TINYINT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
        CAST(0 AS FLOAT),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(ISNULL(main.DUEDATE, s.DATE_) AS DATETIME2)),
        CAST(s.PAYTYPE AS INT),
        CAST(ISNULL(main.CURID, 160) AS INT),
        CAST(1 AS FLOAT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
        debt.LREF,
        CAST(s.TRANSTYPE AS INT),
        CAST(ISNULL(s.CANCELED, 0) AS BIT),
        CAST(0 AS FLOAT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
        CAST(s.LINETYPE AS INT),
        CAST(ISNULL(s.INST_NR, 0) AS INT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
        CAST(ISNULL(main.ADDUSER, 20001) AS INT),
        CAST(0 AS INT),
        TRY_CAST(main.BN_TYPE AS INT),
        CAST(ISNULL(main.XTYPE, 1) AS INT),
        CAST(ISNULL(main.CURID, 160) AS INT),
        TRY_CAST(s.ABYS_ID AS BIGINT),
        TRY_CAST(s.ABYS_ACCOUNT_ID AS BIGINT),
        TRY_CAST(s.ABYS_AGREEMENT_ID AS BIGINT),
        TRY_CAST(s.ABYS_ACTION_TYPE_ID AS INT),
        TRY_CAST(s.CROSSREF_MAIN_LREF AS INT)
    FROM izgazMGR.dbo.LS_OV_PAY_PT s WITH (NOLOCK)
    LEFT JOIN energy.dbo.LS_005_01_INVOICE main WITH (NOLOCK)
        ON main.LREF = TRY_CAST(s.CROSSREF_MAIN_LREF AS INT)
    /* Taksit split: ayni MAIN'de N debt PT → TOP 1 (iptal edilmemis / INST eslesmesi) */
    OUTER APPLY (
        SELECT TOP (1) d.LREF
        FROM energy.dbo.LS_005_01_PAYTRANS d WITH (NOLOCK)
        WHERE d.INVOICEREF = TRY_CAST(s.CROSSREF_MAIN_LREF AS INT)
          AND ISNULL(d.IOCODE, 0) = 0
          AND ISNULL(d.CANCELLATIONPAYMENT, 0) = 0
        ORDER BY
          CASE WHEN ISNULL(d.CANCELED, 0) = 0 THEN 0 ELSE 1 END,
          CASE WHEN d.INST_NR = TRY_CAST(s.INST_NR AS INT) THEN 0 ELSE 1 END,
          CASE WHEN ISNULL(d.INST_NR, 0) > 0 THEN 0 ELSE 1 END,
          d.INST_NR,
          d.LREF
    ) debt
    WHERE (@AGR_ID IS NULL OR TRY_CAST(s.ABYS_AGREEMENT_ID AS BIGINT) = @AGR_ID)
      AND TRY_CAST(s.LREF AS BIGINT) BETWEEN 1 AND 2147483647
      AND NOT EXISTS (
            SELECT 1 FROM energy.dbo.LS_005_01_PAYTRANS t WITH (NOLOCK)
            WHERE t.LREF = CAST(TRY_CAST(s.LREF AS BIGINT) AS INT)
          )
    OPTION (RECOMPILE, MAXDOP 24);

    SET @N = @@ROWCOUNT;
    SET IDENTITY_INSERT energy.dbo.LS_005_01_PAYTRANS OFF;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'PAY PT insert=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_CANCEL_PAY', 'U') IS NOT NULL
    BEGIN
        /* CreateReverse IADE_PT + CancelInvoices = cift ALACAK → IADE_PT kaldir */
        DELETE pt
        FROM energy.dbo.LS_005_01_PAYTRANS pt
        INNER JOIN izgazMGR.dbo.LS_OV_CANCEL_PAY s WITH (NOLOCK)
            ON pt.LREF = TRY_CAST(s.CROSSREF_IADE_LREF AS INT)
        WHERE (@AGR_ID IS NULL OR s.ABYS_AGREEMENT_ID = @AGR_ID)
          AND ISNULL(pt.IOCODE, 0) = 1
          AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
        OPTION (RECOMPILE, MAXDOP 24);

        SET @N = @@ROWCOUNT;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'DROP IADE_PT (CancelInvoices)=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        SET IDENTITY_INSERT energy.dbo.LS_005_01_PAYTRANS ON;

        INSERT INTO energy.dbo.LS_005_01_PAYTRANS WITH (TABLOCK) (
            LREF, INVOICEREF, DATE_, [TYPE], CLIENTREF, CLIENT_TYPE, IOCODE,
            TLTOTAL, PAID, DUEDATE, PAYTYPE, CURID, CURRATE, CURTOTAL,
            CROSSREF, TRANSTYPE, CANCELED, TAX, GRANDTOTAL, LINETYPE, INST_NR,
            PAYABLETOTAL, ADDDATE, ADDUSER, CANCELLATIONPAYMENT, BN_TYPE, XTYPE, PAYCURID,
            ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF
        )
        SELECT
            CAST(s.LREF AS INT),
            CAST(s.INVOICEREF AS INT),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
            CAST(92 AS TINYINT),
            CAST(s.CLIENTREF AS INT),
            CAST(ISNULL(inv.OWNERTYPE, 91) AS TINYINT),
            CAST(1 AS TINYINT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            CAST(0 AS FLOAT),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(ISNULL(inv.DUEDATE, s.DATE_) AS DATETIME2)),
            CAST(174 AS INT),
            CAST(ISNULL(inv.CURID, 160) AS INT),
            CAST(1 AS FLOAT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            debt.LREF,
            CAST(113 AS INT),
            CAST(0 AS BIT),
            CAST(0 AS FLOAT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            CAST(103 AS INT),
            0,
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
            CAST(ISNULL(inv.ADDUSER, 20001) AS INT),
            CAST(1 AS INT),
            TRY_CAST(inv.BN_TYPE AS INT),
            CAST(ISNULL(inv.XTYPE, 1) AS INT),
            CAST(ISNULL(inv.CURID, 160) AS INT),
            s.ABYS_ID,
            s.ABYS_ACCOUNT_ID,
            s.ABYS_AGREEMENT_ID,
            TRY_CAST(s.INVOICEREF AS INT)
        FROM izgazMGR.dbo.LS_OV_CANCEL_PAY s WITH (NOLOCK)
        LEFT JOIN energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
            ON inv.LREF = TRY_CAST(COALESCE(s.CROSSREF_MAIN_LREF, s.ABYS_MAIN_LREF) AS INT)
        LEFT JOIN energy.dbo.LS_005_01_PAYTRANS debt WITH (NOLOCK)
            ON debt.INVOICEREF = TRY_CAST(
                    COALESCE(s.CROSSREF_MAIN_LREF, s.ABYS_MAIN_LREF) AS INT)
           AND ISNULL(debt.IOCODE, 0) = 0
           AND ISNULL(debt.CANCELLATIONPAYMENT, 0) = 0
        WHERE (@AGR_ID IS NULL OR s.ABYS_AGREEMENT_ID = @AGR_ID)
          AND s.LREF BETWEEN 1 AND 2147483647
          AND NOT EXISTS (
                SELECT 1 FROM energy.dbo.LS_005_01_PAYTRANS t
                WHERE t.LREF = CAST(s.LREF AS INT)
              )
        OPTION (RECOMPILE, MAXDOP 24);

        SET @N = @@ROWCOUNT;
        SET IDENTITY_INSERT energy.dbo.LS_005_01_PAYTRANS OFF;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'CANCEL_PAY insert=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_CANCEL_REV', 'U') IS NOT NULL
    BEGIN
        SET IDENTITY_INSERT energy.dbo.LS_005_01_PAYTRANS ON;

        INSERT INTO energy.dbo.LS_005_01_PAYTRANS WITH (TABLOCK) (
            LREF, INVOICEREF, DATE_, [TYPE], CLIENTREF, CLIENT_TYPE, IOCODE,
            TLTOTAL, PAID, DUEDATE, PAYTYPE, CURID, CURRATE, CURTOTAL,
            CROSSREF, TRANSTYPE, CANCELED, TAX, GRANDTOTAL, LINETYPE, INST_NR,
            PAYABLETOTAL, ADDDATE, ADDUSER, CANCELLATIONPAYMENT, BN_TYPE, XTYPE, PAYCURID,
            ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF
        )
        SELECT
            CAST(s.LREF AS INT),
            CAST(s.INVOICEREF AS INT),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
            CAST(ISNULL(s.[TYPE], ISNULL(inv.[TYPE], 119)) AS TINYINT),
            CAST(s.CLIENTREF AS INT),
            CAST(ISNULL(inv.OWNERTYPE, 91) AS TINYINT),
            CAST(0 AS TINYINT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            CAST(0 AS FLOAT),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(ISNULL(inv.DUEDATE, s.DATE_) AS DATETIME2)),
            CAST(174 AS INT),
            CAST(ISNULL(inv.CURID, 160) AS INT),
            CAST(1 AS FLOAT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            debt.LREF,
            CAST(113 AS INT),
            CAST(0 AS BIT),
            CAST(0 AS FLOAT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            CAST(103 AS INT),
            0,
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
            CAST(ISNULL(inv.ADDUSER, 20001) AS INT),
            CAST(1 AS INT),
            TRY_CAST(inv.BN_TYPE AS INT),
            CAST(ISNULL(inv.XTYPE, 1) AS INT),
            CAST(ISNULL(inv.CURID, 160) AS INT),
            s.ABYS_ID,
            s.ABYS_ACCOUNT_ID,
            s.ABYS_AGREEMENT_ID,
            TRY_CAST(s.INVOICEREF AS INT)
        FROM izgazMGR.dbo.LS_OV_CANCEL_REV s WITH (NOLOCK)
        LEFT JOIN energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
            ON inv.LREF = TRY_CAST(s.INVOICEREF AS INT)
        LEFT JOIN energy.dbo.LS_005_01_PAYTRANS debt WITH (NOLOCK)
            ON debt.INVOICEREF = TRY_CAST(s.CROSSREF_MAIN_LREF AS INT)
           AND ISNULL(debt.IOCODE, 0) = 0
           AND ISNULL(debt.CANCELLATIONPAYMENT, 0) = 0
        WHERE (@AGR_ID IS NULL OR s.ABYS_AGREEMENT_ID = @AGR_ID)
          AND s.LREF BETWEEN 1 AND 2147483647
          AND NOT EXISTS (
                SELECT 1 FROM energy.dbo.LS_005_01_PAYTRANS t
                WHERE t.LREF = CAST(s.LREF AS INT)
              )
        OPTION (RECOMPILE, MAXDOP 24);

        SET @N = @@ROWCOUNT;
        SET IDENTITY_INSERT energy.dbo.LS_005_01_PAYTRANS OFF;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'CANCEL_REV insert=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_DEBT_PAID_UPD', 'U') IS NOT NULL
    BEGIN
        /* Taksit split: ayni MAIN'de N debt PT var → PAID'i odeme CROSSREF toplamindan yaz.
           Tek debt PT: DEBT_PAID_UPD.PAID_AMT (eski davranis). */
        ;WITH debt_cnt AS (
            SELECT d.INVOICEREF, COUNT(*) AS ACTIVE_N
            FROM energy.dbo.LS_005_01_PAYTRANS d WITH (NOLOCK)
            INNER JOIN izgazMGR.dbo.LS_OV_DEBT_PAID_UPD u WITH (NOLOCK)
                ON d.INVOICEREF = CAST(TRY_CAST(u.MAIN_LREF AS BIGINT) AS INT)
            WHERE (@AGR_ID IS NULL OR TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) = @AGR_ID)
              AND ISNULL(d.IOCODE, 0) = 0
              AND ISNULL(d.CANCELLATIONPAYMENT, 0) = 0
              AND ISNULL(d.CANCELED, 0) = 0
            GROUP BY d.INVOICEREF
        ),
        pay_sum AS (
            SELECT p.CROSSREF, SUM(CONVERT(DECIMAL(18,2), p.PAYABLETOTAL)) AS SUM_AMT
            FROM energy.dbo.LS_005_01_PAYTRANS p WITH (NOLOCK)
            WHERE ISNULL(p.IOCODE, 0) = 1
              AND ISNULL(p.CANCELED, 0) = 0
              AND ISNULL(p.CANCELLATIONPAYMENT, 0) = 0
              AND p.CROSSREF IS NOT NULL
              AND (@AGR_ID IS NULL OR TRY_CAST(p.ABYS_AGREEMENT_ID AS BIGINT) = @AGR_ID)
            GROUP BY p.CROSSREF
        )
        UPDATE pt
        SET pt.PAID = CASE
              WHEN ISNULL(dc.ACTIVE_N, 0) > 1
              THEN CONVERT(FLOAT, CONVERT(DECIMAL(18,2), ISNULL(ps.SUM_AMT, 0)))
              ELSE CONVERT(FLOAT, CONVERT(DECIMAL(18,2), u.PAID_AMT))
            END
        FROM energy.dbo.LS_005_01_PAYTRANS pt
        INNER JOIN izgazMGR.dbo.LS_OV_DEBT_PAID_UPD u WITH (NOLOCK)
            ON pt.INVOICEREF = CAST(TRY_CAST(u.MAIN_LREF AS BIGINT) AS INT)
           AND ISNULL(pt.IOCODE, 0) = 0
           AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
        LEFT JOIN debt_cnt dc ON dc.INVOICEREF = pt.INVOICEREF
        LEFT JOIN pay_sum ps ON ps.CROSSREF = pt.LREF
        WHERE (@AGR_ID IS NULL OR TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) = @AGR_ID)
        OPTION (RECOMPILE, MAXDOP 24);

        SET @N = @@ROWCOUNT;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'DEBT PAID upd=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        /* CLOSED + LASTPAIDDATE (LPD kismi odemede de; kolon yoksa sadece CLOSED) */
        IF COL_LENGTH('izgazMGR.dbo.LS_OV_DEBT_PAID_UPD', 'LASTPAIDDATE') IS NOT NULL
        BEGIN
            UPDATE inv
            SET inv.CLOSED = CASE
                    WHEN TRY_CAST(u.CLOSED AS INT) = 1 THEN CAST(1 AS BIT)
                    ELSE inv.CLOSED
                END,
                inv.LASTPAIDDATE = CASE
                    WHEN u.LASTPAIDDATE IS NOT NULL
                    THEN energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(u.LASTPAIDDATE AS DATETIME2))
                    ELSE inv.LASTPAIDDATE
                END
            FROM energy.dbo.LS_005_01_INVOICE inv
            INNER JOIN izgazMGR.dbo.LS_OV_DEBT_PAID_UPD u WITH (NOLOCK)
                ON inv.LREF = CAST(TRY_CAST(u.MAIN_LREF AS BIGINT) AS INT)
            WHERE (@AGR_ID IS NULL OR TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) = @AGR_ID)
              AND (
                    (TRY_CAST(u.CLOSED AS INT) = 1 AND ISNULL(inv.CLOSED, 0) = 0)
                 OR (u.LASTPAIDDATE IS NOT NULL AND inv.LASTPAIDDATE IS NULL)
              )
            OPTION (RECOMPILE, MAXDOP 24);
        END
        ELSE
        BEGIN
            UPDATE inv
            SET inv.CLOSED = CAST(1 AS BIT)
            FROM energy.dbo.LS_005_01_INVOICE inv
            INNER JOIN izgazMGR.dbo.LS_OV_DEBT_PAID_UPD u WITH (NOLOCK)
                ON inv.LREF = CAST(TRY_CAST(u.MAIN_LREF AS BIGINT) AS INT)
            WHERE (@AGR_ID IS NULL OR TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) = @AGR_ID)
              AND TRY_CAST(u.CLOSED AS INT) = 1
              AND ISNULL(inv.CLOSED, 0) = 0
            OPTION (RECOMPILE, MAXDOP 24);
        END

        SET @N = @@ROWCOUNT;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'MAIN CLOSED/LPD upd=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* PAYABLETOTAL=0 → CLOSED=1 (odeme kaydi olmasa da) */
    UPDATE inv
    SET inv.CLOSED = CAST(1 AS BIT)
    FROM energy.dbo.LS_005_01_INVOICE inv
    WHERE (@AGR_ID IS NULL OR inv.ABYS_AGREEMENT_ID = @AGR_ID)
      AND ISNULL(inv.IOCODE, 0) = 0
      AND ABS(ISNULL(inv.PAYABLETOTAL, 0)) <= 0.01
      AND ISNULL(inv.CLOSED, 0) = 0
    OPTION (RECOMPILE, MAXDOP 24);

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'ZERO PAYABLE CLOSED=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* Mahsup ile kapanan/katkili faturalari isaretle + emanet kaynagi yaz */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_MAHSUP_CLOSED', 'U') IS NOT NULL
    BEGIN
        UPDATE inv
        SET
            inv.EXPLAIN = LEFT(c.EXPLAIN_MARK, 250),
            inv.ABYS_REF_DEPOSIT_ACCOUNT_ID = CASE
                WHEN c.DEP_ACCOUNT_ID IS NOT NULL THEN c.DEP_ACCOUNT_ID
                ELSE inv.ABYS_REF_DEPOSIT_ACCOUNT_ID
            END,
            inv.ABYS_REF_DEP_ACC_ACTION_ID = CASE
                WHEN c.DEP_ACTION_ID IS NOT NULL THEN c.DEP_ACTION_ID
                ELSE inv.ABYS_REF_DEP_ACC_ACTION_ID
            END
        FROM energy.dbo.LS_005_01_INVOICE inv
        INNER JOIN izgazMGR.dbo.LS_OV_MAHSUP_CLOSED c WITH (NOLOCK)
            ON inv.LREF = CAST(c.MAIN_LREF AS INT)
        WHERE (@AGR_ID IS NULL OR c.ABYS_AGREEMENT_ID = @AGR_ID)
          AND ISNULL(c.CLOSED, 0) = 1
        OPTION (RECOMPILE, MAXDOP 24);

        SET @N = @@ROWCOUNT;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'MAHSUP CLOSED mark=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    UPDATE pt
    SET pt.CLIENTREF = ISNULL(agr.CON, agr.FRMID)
    FROM energy.dbo.LS_005_01_PAYTRANS pt
    INNER JOIN energy.dbo.LS_005_01_AGR agr
        ON pt.ABYS_AGREEMENT_ID = agr.ABYS_ID
    WHERE (@AGR_ID IS NULL OR pt.ABYS_AGREEMENT_ID = @AGR_ID)
      AND agr.TP2 = 'KUL'
      AND pt.ABYS_ID IS NOT NULL
      AND ISNULL(pt.IOCODE, 0) = 1
      AND ISNULL(pt.CLIENTREF, -1) <> ISNULL(agr.CON, ISNULL(agr.FRMID, -1))
    OPTION (RECOMPILE, MAXDOP 24);

    SELECT @MaxLref = ISNULL(MAX(LREF), 0) FROM energy.dbo.LS_005_01_PAYTRANS;
    DBCC CHECKIDENT('energy.dbo.LS_005_01_PAYTRANS', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @MaxLref = ISNULL(MAX(LREF), 0) FROM energy.dbo.LS_005_01_INVOICE;
    DBCC CHECKIDENT('energy.dbo.LS_005_01_INVOICE', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
        RAISERROR('SP_MIGRATE_TAHSILAT_OVERLAY_AGR OK', 0, 1) WITH NOWAIT;
END
GO

PRINT '597_TAHSILAT_OVERLAY__full OK';
GO



