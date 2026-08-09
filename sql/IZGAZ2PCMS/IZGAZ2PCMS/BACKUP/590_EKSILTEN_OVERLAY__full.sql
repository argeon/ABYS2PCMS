/* ============================================================
   SCRIPT_ID : EKSILTEN_OVERLAY_FULL
   SCRIPT_NO : 590
   FILE      : 590_EKSILTEN_OVERLAY__full.sql
   VERSION   : 1
   ============================================================ */
-- Adim 4a — Eksilten overlay (energy)
-- Onkosul Oracle: oracleCTAS/prod2/20_ls_eksilten_overlay.sql → dump → izgazMGR:
--   LS_OV_IADE_INVOICE, LS_OV_IADE_INVLINES, LS_OV_IADE_PAYTRANS,
--   LS_OV_MAIN_UPD, LS_OV_KISMI_INVLINES, LS_OV_KISMI_HDR (+EXPLAIN_NOTE),
--   LS_OV_KISMI_PAYTRANS (MAIN borc PT hedefi; yoksa HDR'den sync)
-- Onkosul energy: Adim3 PASS (INVOICE+INVLINES+debt PT) AGR yuklu
-- KISMI: + satir MAIN; HDR = MAIN - SUM(KISMI); EXPLAIN not; borc PT rebuild
--
-- Yapmaz: CancelInvoices iade tahsilat, normal tahsilat (Adim 5)
-- Index DISABLE YOK; @AGR_ID NULL = FULL (tum izgazMGR satirlari)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_EKSILTEN_OVERLAY_CLEAN_BY_AGR
    @AGR_ID       BIGINT,
    @DELETE_BATCH INT = 5000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @Msg NVARCHAR(400), @Batch INT = 0, @N INT;

    /* @AGR_ID NULL = FULL: filtre yok (tum ABYS_AGREEMENT_ID) */    /* Anahtarlar izgazMGR'den (kucuk) — energy AGR/LINEEXP tarama YOK */
    IF OBJECT_ID('tempdb..#OV_PT') IS NOT NULL DROP TABLE #OV_PT;
    IF OBJECT_ID('tempdb..#OV_IL') IS NOT NULL DROP TABLE #OV_IL;
    IF OBJECT_ID('tempdb..#OV_INV') IS NOT NULL DROP TABLE #OV_INV;
    IF OBJECT_ID('tempdb..#OV_MAIN') IS NOT NULL DROP TABLE #OV_MAIN;
    CREATE TABLE #OV_PT   (LREF INT NOT NULL PRIMARY KEY);
    CREATE TABLE #OV_IL   (LREF INT NOT NULL PRIMARY KEY);
    CREATE TABLE #OV_INV  (LREF INT NOT NULL PRIMARY KEY);
    CREATE TABLE #OV_MAIN (LREF INT NOT NULL PRIMARY KEY);

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_PAYTRANS', 'U') IS NOT NULL
        INSERT INTO #OV_PT (LREF)
        SELECT DISTINCT CAST(LREF AS INT)
        FROM izgazMGR.dbo.LS_OV_IADE_PAYTRANS WITH (NOLOCK)
        WHERE (@AGR_ID IS NULL OR ABYS_AGREEMENT_ID = @AGR_ID) AND LREF BETWEEN 1 AND 2147483647;

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_INVLINES', 'U') IS NOT NULL
        INSERT INTO #OV_IL (LREF)
        SELECT DISTINCT CAST(LREF AS INT)
        FROM izgazMGR.dbo.LS_OV_IADE_INVLINES WITH (NOLOCK)
        WHERE (@AGR_ID IS NULL OR ABYS_AGREEMENT_ID = @AGR_ID) AND LREF BETWEEN 1 AND 2147483647;

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_KISMI_INVLINES', 'U') IS NOT NULL
        INSERT INTO #OV_IL (LREF)
        SELECT DISTINCT CAST(k.LREF AS INT)
        FROM izgazMGR.dbo.LS_OV_KISMI_INVLINES k WITH (NOLOCK)
        WHERE (@AGR_ID IS NULL OR k.ABYS_AGREEMENT_ID = @AGR_ID) AND k.LREF BETWEEN 1 AND 2147483647
          AND NOT EXISTS (SELECT 1 FROM #OV_IL x WHERE x.LREF = CAST(k.LREF AS INT));

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_INVOICE', 'U') IS NOT NULL
        INSERT INTO #OV_INV (LREF)
        SELECT DISTINCT CAST(LREF AS INT)
        FROM izgazMGR.dbo.LS_OV_IADE_INVOICE WITH (NOLOCK)
        WHERE (@AGR_ID IS NULL OR ABYS_AGREEMENT_ID = @AGR_ID) AND LREF BETWEEN 1 AND 2147483647;

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_MAIN_UPD', 'U') IS NOT NULL
        INSERT INTO #OV_MAIN (LREF)
        SELECT DISTINCT CAST(LREF AS INT)
        FROM izgazMGR.dbo.LS_OV_MAIN_UPD WITH (NOLOCK)
        WHERE (@AGR_ID IS NULL OR ABYS_AGREEMENT_ID = @AGR_ID) AND LREF BETWEEN 1 AND 2147483647;

    SELECT @N = COUNT(*) FROM #OV_PT;
    IF @DEBUG = 1 BEGIN SET @Msg = N'CLEAN keys PT=' + CAST(@N AS VARCHAR(20)); RAISERROR('%s',0,1,@Msg) WITH NOWAIT; END

    /* 1) IADE PAYTRANS — PK */
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
        IF @DEBUG = 1 BEGIN SET @Msg = N'CLEAN IADE PT +' + CAST(@Deleted AS VARCHAR(20)); RAISERROR('%s',0,1,@Msg) WITH NOWAIT; END
    END

    /* 2a) IADE INVLINES — tum satirlar (INVOICEREF = IADE LREF; eski 1.7B yetim dahil) */
    SET @Batch = 0;
    WHILE 1 = 1
    BEGIN
        SET @Batch += 1;
        DELETE TOP (@DELETE_BATCH) il
        FROM energy.dbo.LS_005_01_INVLINES il WITH (ROWLOCK)
        INNER JOIN #OV_INV k ON k.LREF = il.INVOICEREF
        OPTION (RECOMPILE, MAXDOP 1);
        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;
        IF @DEBUG = 1 BEGIN SET @Msg = N'CLEAN IADE IL(by INV) +' + CAST(@Deleted AS VARCHAR(20)); RAISERROR('%s',0,1,@Msg) WITH NOWAIT; END
    END

    /* 2b) KISMI (+ kalan OV) INVLINES — PK */
    SET @Batch = 0;
    WHILE 1 = 1
    BEGIN
        SET @Batch += 1;
        DELETE TOP (@DELETE_BATCH) il
        FROM energy.dbo.LS_005_01_INVLINES il WITH (ROWLOCK)
        INNER JOIN #OV_IL k ON k.LREF = il.LREF
        OPTION (RECOMPILE, MAXDOP 1);
        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;
        IF @DEBUG = 1 BEGIN SET @Msg = N'CLEAN OV IL +' + CAST(@Deleted AS VARCHAR(20)); RAISERROR('%s',0,1,@Msg) WITH NOWAIT; END
    END

    /* 3) IADE INVOICE — PK */
    SET @Batch = 0;
    WHILE 1 = 1
    BEGIN
        SET @Batch += 1;
        DELETE TOP (@DELETE_BATCH) inv
        FROM energy.dbo.LS_005_01_INVOICE inv WITH (ROWLOCK)
        INNER JOIN #OV_INV k ON k.LREF = inv.LREF
        OPTION (RECOMPILE, MAXDOP 1);
        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;
        IF @DEBUG = 1 BEGIN SET @Msg = N'CLEAN IADE INV +' + CAST(@Deleted AS VARCHAR(20)); RAISERROR('%s',0,1,@Msg) WITH NOWAIT; END
    END

    /* 4) MAIN overlay alanlari — PK (#OV_MAIN) */
    UPDATE inv
    SET inv.RETURN_TARGET_INVREF = NULL,
        inv.CANCEL_DATE = NULL,
        inv.CANCEL_REASON_ID = NULL,
        inv.CANCEL_USER_ID = NULL
    FROM energy.dbo.LS_005_01_INVOICE inv
    INNER JOIN #OV_MAIN k ON k.LREF = inv.LREF;

    SET @Deleted = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'CLEAN MAIN UPD reset=' + CAST(@Deleted AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        RAISERROR('EKSILTEN OVERLAY CLEAN OK (PK)', 0, 1) WITH NOWAIT;
    END

    DROP TABLE #OV_PT; DROP TABLE #OV_IL; DROP TABLE #OV_INV; DROP TABLE #OV_MAIN;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR
    @AGR_ID BIGINT,
    @CLEAN  BIT = 1,
    @DEBUG  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @Msg NVARCHAR(500),
        @N INT,
        @MaxLref INT;

    /* @AGR_ID NULL = FULL: filtre yok (tum ABYS_AGREEMENT_ID) */    IF OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_INVOICE', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR.dbo.LS_OV_IADE_INVOICE yok. Once Oracle Adim4a dump edin.', 16, 1);
        RETURN;
    END

    IF @CLEAN = 1
        EXEC dbo.SP_MIG_EKSILTEN_OVERLAY_CLEAN_BY_AGR
            @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;

    /* ---- IADE INVOICE ---- */
    SET IDENTITY_INSERT energy.dbo.LS_005_01_INVOICE ON;

    INSERT INTO energy.dbo.LS_005_01_INVOICE WITH (TABLOCK) (
        LREF, IOCODE, FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF,
        TLTOTAL, CURID, CURTOTAL, EXPLAIN, CANCELED, OWNERREF, OWNERTYPE,
        TAX, DV, GRANDTOTAL, PRINTCOUNT, PAYABLETOTAL, CLOSED,
        RETURN_SOURCE_INVREF, RETURN_TARGET_INVREF,
        FITNO, BN_TYPE, AMOUNT, PERIOD, HAS_DISCOUNT, DISCOUNT_AMOUNT,
        ADDDATE, ADDUSER,
        ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_AGREEMENT_ID
    )
    SELECT
        CAST(s.LREF AS INT),
        CAST(s.IOCODE AS TINYINT),
        LEFT(s.FICHENO, 45),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DUEDATE AS DATETIME2)),
        CAST(s.[TYPE] AS TINYINT),
        CAST(s.CLIENTREF AS INT),
        ROUND(CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TLTOTAL)), 2),
        TRY_CAST(ISNULL(s.CURID, 160) AS SMALLINT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.CURTOTAL)),
        LEFT(s.EXPLAIN, 250),
        CAST(0 AS BIT),                                          -- CANCELED=0
        CAST(s.OWNERREF AS INT),
        CAST(ISNULL(s.OWNERTYPE, 91) AS TINYINT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TAX)),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), ISNULL(s.DV, 0))),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.GRANDTOTAL)),
        CAST(ISNULL(s.PRINTCOUNT, 0) AS INT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
        CAST(1 AS BIT),
        CAST(s.RETURN_SOURCE_INVREF AS INT),
        NULL,
        TRY_CAST(s.FITNO AS BIGINT),
        TRY_CAST(s.BN_TYPE AS INT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), COALESCE(s.AMOUNT, s.PAYABLETOTAL))),
        s.PERIOD,
        CAST(ISNULL(s.HAS_DISCOUNT, 0) AS BIT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), ISNULL(s.DISCOUNT_AMOUNT, 0))),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ADDDATE AS DATETIME2)),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.ADDUSER AS INT)),
        s.ABYS_ID,
        s.ABYS_ACCOUNT_ID,
        s.ABYS_ACTION_TYPE_ID,
        s.ABYS_AGREEMENT_ID
    FROM izgazMGR.dbo.LS_OV_IADE_INVOICE s WITH (NOLOCK)
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
        SET @Msg = N'IADE INVOICE insert=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* ---- MAIN UPDATE ---- */
    UPDATE inv
    SET inv.RETURN_TARGET_INVREF = CAST(u.RETURN_TARGET_INVREF AS INT),
        inv.CANCEL_DATE = energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(u.CANCEL_DATE AS DATETIME2)),
        inv.CANCEL_REASON_ID = CAST(u.CANCEL_REASON_ID AS INT),
        inv.CANCEL_USER_ID = energy.dbo.FN_MIG_MAP_USER_USERID(CAST(u.CANCEL_USER_ID AS INT)),
        inv.CLOSED = CAST(1 AS BIT),
        inv.CANCELED = CAST(0 AS BIT)
    FROM energy.dbo.LS_005_01_INVOICE inv
    INNER JOIN izgazMGR.dbo.LS_OV_MAIN_UPD u WITH (NOLOCK)
        ON inv.LREF = CAST(u.LREF AS INT)
    WHERE (@AGR_ID IS NULL OR u.ABYS_AGREEMENT_ID = @AGR_ID)
    OPTION (RECOMPILE, MAXDOP 24);

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'MAIN UPD=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* ---- IADE INVLINES (stage RECOMPILE+MAXDOP 24, sonra IDENTITY insert) ---- */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_INVLINES', 'U') IS NOT NULL
       AND OBJECT_ID('energy.dbo.LS_005_01_INVLINES', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('tempdb..#IADE_IL') IS NOT NULL DROP TABLE #IADE_IL;

        SELECT
            CAST(s.LREF AS INT) AS LREF,
            CAST(s.INVOICEREF AS INT) AS INVOICEREF,
            CAST(s.CLIENTREF AS INT) AS CLIENTREF,
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)) AS DATE_,
            CAST(s.[TYPE] AS TINYINT) AS [TYPE],
            CAST(s.LINENR AS SMALLINT) AS LINENR,
            CAST(s.TRANSTYPE AS INT) AS TRANSTYPE,
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.AMOUNT)) AS AMOUNT,
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TLTOTAL)) AS TLTOTAL,
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TAX)) AS TAX,
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.GRANDTOTAL)) AS GRANDTOTAL,
            LEFT(N'IADE ' + ISNULL(ml.LINEEXP, ISNULL(s.LINEEXP, CAST(s.TRANSTYPE AS NVARCHAR(20)))), 100) AS LINEEXP,
            /* UX_LS005_INVLINES_ABYS_ID: MAIN ile ayni ABYS_INCOME_ROW_ID yazma — LREF unique */
            CAST(s.LREF AS BIGINT) AS ABYS_ID,
            s.ABYS_AGREEMENT_ID
        INTO #IADE_IL
        FROM izgazMGR.dbo.LS_OV_IADE_INVLINES s WITH (NOLOCK)
        LEFT JOIN energy.dbo.LS_005_01_INVLINES ml WITH (NOLOCK)
            ON ml.LREF = TRY_CAST(COALESCE(s.ABYS_SOURCE_LINE_LREF, s.ABYS_INCOME_ROW_ID) AS INT)
        WHERE (@AGR_ID IS NULL OR s.ABYS_AGREEMENT_ID = @AGR_ID)
          AND s.LREF BETWEEN 1 AND 2147483647
          AND NOT EXISTS (
                SELECT 1 FROM energy.dbo.LS_005_01_INVLINES t WITH (NOLOCK)
                WHERE t.LREF = CAST(s.LREF AS INT)
              )
        OPTION (RECOMPILE, MAXDOP 24);

        CREATE CLUSTERED INDEX CX_IADE_IL ON #IADE_IL (LREF);

        SET @N = (SELECT COUNT(*) FROM #IADE_IL);
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'IADE INVLINES staged=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        SET IDENTITY_INSERT energy.dbo.LS_005_01_INVLINES ON;
        INSERT INTO energy.dbo.LS_005_01_INVLINES WITH (TABLOCK) (
            LREF, INVOICEREF, CLIENTREF, DATE_, [TYPE], LINENR, TRANSTYPE,
            AMOUNT, TLTOTAL, TAX, GRANDTOTAL, LINEEXP,
            ABYS_ID, ABYS_AGREEMENT_ID
        )
        SELECT LREF, INVOICEREF, CLIENTREF, DATE_, [TYPE], LINENR, TRANSTYPE,
               AMOUNT, TLTOTAL, TAX, GRANDTOTAL, LINEEXP, ABYS_ID, ABYS_AGREEMENT_ID
        FROM #IADE_IL
        OPTION (RECOMPILE, MAXDOP 24);
        SET @N = @@ROWCOUNT;
        SET IDENTITY_INSERT energy.dbo.LS_005_01_INVLINES OFF;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'IADE INVLINES insert=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ---- IADE PAYTRANS ---- */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_PAYTRANS', 'U') IS NOT NULL
    BEGIN
        SET IDENTITY_INSERT energy.dbo.LS_005_01_PAYTRANS ON;

        INSERT INTO energy.dbo.LS_005_01_PAYTRANS WITH (TABLOCK) (
            LREF, INVOICEREF, DATE_, [TYPE], CLIENTREF, CLIENT_TYPE, IOCODE,
            TLTOTAL, PAID, DUEDATE, PAYTYPE, CURID, CURRATE, CURTOTAL,
            CROSSREF, TRANSTYPE, CANCELED, TAX, GRANDTOTAL, LINETYPE, INST_NR,
            PAYABLETOTAL, ADDDATE, ADDUSER, CANCELLATIONPAYMENT, BN_TYPE, XTYPE, PAYCURID,
            ABYS_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF
        )
        SELECT
            CAST(s.LREF AS INT),
            CAST(s.INVOICEREF AS INT),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
            CAST(s.[TYPE] AS TINYINT),
            CAST(s.CLIENTREF AS INT),
            CAST(ISNULL(iade.OWNERTYPE, ISNULL(main.OWNERTYPE, 91)) AS TINYINT),
            CAST(s.IOCODE AS TINYINT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            CAST(0 AS FLOAT),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(ISNULL(iade.DUEDATE, s.DATE_) AS DATETIME2)),
            CAST(s.PAYTYPE AS INT),
            CAST(ISNULL(iade.CURID, ISNULL(main.CURID, 160)) AS INT),
            CAST(1 AS FLOAT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            /* CreateReverse: CROSSREF = MAIN borc PT */
            debt.LREF,
            CAST(s.TRANSTYPE AS INT),
            CAST(0 AS BIT),
            CAST(0 AS FLOAT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            CAST(s.LINETYPE AS INT),
            CAST(ISNULL(s.INST_NR, 0) AS INT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
            CAST(ISNULL(iade.ADDUSER, 20001) AS INT),
            CAST(0 AS INT),
            TRY_CAST(ISNULL(iade.BN_TYPE, main.BN_TYPE) AS INT),
            CAST(ISNULL(iade.XTYPE, ISNULL(main.XTYPE, 1)) AS INT),
            CAST(ISNULL(iade.CURID, ISNULL(main.CURID, 160)) AS INT),
            s.ABYS_ID,
            s.ABYS_AGREEMENT_ID,
            TRY_CAST(s.INVOICEREF AS INT)
        FROM izgazMGR.dbo.LS_OV_IADE_PAYTRANS s WITH (NOLOCK)
        LEFT JOIN energy.dbo.LS_005_01_INVOICE iade WITH (NOLOCK)
            ON iade.LREF = TRY_CAST(s.INVOICEREF AS INT)
        LEFT JOIN energy.dbo.LS_005_01_INVOICE main WITH (NOLOCK)
            ON main.LREF = TRY_CAST(s.ABYS_MAIN_LREF AS INT)
        LEFT JOIN energy.dbo.LS_005_01_PAYTRANS debt WITH (NOLOCK)
            ON debt.INVOICEREF = TRY_CAST(s.ABYS_MAIN_LREF AS INT)
           AND ISNULL(debt.IOCODE, 0) = 0
           AND ISNULL(debt.CANCELLATIONPAYMENT, 0) = 0
        WHERE (@AGR_ID IS NULL OR s.ABYS_AGREEMENT_ID = @AGR_ID)
          AND s.LREF BETWEEN 1 AND 2147483647
          /* CancelInvoices (Adim5) gelecekse IADE_PT yazma — cift ALACAK */
          AND NOT EXISTS (
                SELECT 1
                FROM izgazMGR.dbo.LS_OV_CANCEL_PAY cp WITH (NOLOCK)
                WHERE TRY_CAST(cp.CROSSREF_IADE_LREF AS INT) = TRY_CAST(s.LREF AS INT)
                   OR TRY_CAST(cp.INVOICEREF AS INT) = TRY_CAST(s.LREF AS INT)
              )
          AND NOT EXISTS (
                SELECT 1 FROM energy.dbo.LS_005_01_PAYTRANS t WITH (NOLOCK)
                WHERE t.LREF = CAST(s.LREF AS INT)
              )
        OPTION (RECOMPILE, MAXDOP 24);

        SET @N = @@ROWCOUNT;
        SET IDENTITY_INSERT energy.dbo.LS_005_01_PAYTRANS OFF;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'IADE PAYTRANS insert=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ---- KISMI INVLINES (stage RECOMPILE+MAXDOP 24) ---- */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_KISMI_INVLINES', 'U') IS NOT NULL
       AND OBJECT_ID('energy.dbo.LS_005_01_INVLINES', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('tempdb..#KISMI_IL') IS NOT NULL DROP TABLE #KISMI_IL;

        SELECT
            CAST(s.LREF AS INT) AS LREF,
            CAST(s.INVOICEREF AS INT) AS INVOICEREF,
            CAST(s.CLIENTREF AS INT) AS CLIENTREF,
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)) AS DATE_,
            CAST(s.[TYPE] AS TINYINT) AS [TYPE],
            CAST(s.LINENR AS SMALLINT) AS LINENR,
            CAST(s.TRANSTYPE AS INT) AS TRANSTYPE,
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.AMOUNT)) AS AMOUNT,
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TLTOTAL)) AS TLTOTAL,
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TAX)) AS TAX,
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.GRANDTOTAL)) AS GRANDTOTAL,
            LEFT(ISNULL(NULLIF(LTRIM(RTRIM(s.LINEEXP)), N''), N'Kısmi Eksilten'), 100) AS LINEEXP,
            s.ABYS_INCOME_ROW_ID AS ABYS_ID,
            s.ABYS_AGREEMENT_ID
        INTO #KISMI_IL
        FROM izgazMGR.dbo.LS_OV_KISMI_INVLINES s WITH (NOLOCK)
        WHERE (@AGR_ID IS NULL OR s.ABYS_AGREEMENT_ID = @AGR_ID)
          AND s.LREF BETWEEN 1 AND 2147483647
          AND NOT EXISTS (
                SELECT 1 FROM energy.dbo.LS_005_01_INVLINES t WITH (NOLOCK)
                WHERE t.LREF = CAST(s.LREF AS INT)
              )
          AND (
                s.ABYS_INCOME_ROW_ID IS NULL
             OR NOT EXISTS (
                    SELECT 1 FROM energy.dbo.LS_005_01_INVLINES t WITH (NOLOCK)
                    WHERE t.ABYS_ID = s.ABYS_INCOME_ROW_ID
                  )
              )
        OPTION (RECOMPILE, MAXDOP 24);

        CREATE CLUSTERED INDEX CX_KISMI_IL ON #KISMI_IL (LREF);

        SET @N = (SELECT COUNT(*) FROM #KISMI_IL);
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'KISMI INVLINES staged=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        SET IDENTITY_INSERT energy.dbo.LS_005_01_INVLINES ON;
        INSERT INTO energy.dbo.LS_005_01_INVLINES WITH (TABLOCK) (
            LREF, INVOICEREF, CLIENTREF, DATE_, [TYPE], LINENR, TRANSTYPE,
            AMOUNT, TLTOTAL, TAX, GRANDTOTAL, LINEEXP,
            ABYS_ID, ABYS_AGREEMENT_ID
        )
        SELECT LREF, INVOICEREF, CLIENTREF, DATE_, [TYPE], LINENR, TRANSTYPE,
               AMOUNT, TLTOTAL, TAX, GRANDTOTAL, LINEEXP, ABYS_ID, ABYS_AGREEMENT_ID
        FROM #KISMI_IL
        OPTION (RECOMPILE, MAXDOP 24);
        SET @N = @@ROWCOUNT;
        SET IDENTITY_INSERT energy.dbo.LS_005_01_INVLINES OFF;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'KISMI INVLINES insert=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ---- KISMI header rebuild (+ EXPLAIN not, OV EXPLAIN_NOTE varsa) ---- */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_KISMI_HDR', 'U') IS NOT NULL
    BEGIN
        IF COL_LENGTH('izgazMGR.dbo.LS_OV_KISMI_HDR', 'EXPLAIN_NOTE') IS NOT NULL
        BEGIN
            UPDATE inv
            SET inv.TLTOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.TLTOTAL)),
                inv.TAX = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.TAX)),
                inv.GRANDTOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.GRANDTOTAL)),
                inv.PAYABLETOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.PAYABLETOTAL)),
                inv.EXPLAIN = LEFT(
                    CASE
                        WHEN NULLIF(LTRIM(RTRIM(CAST(h.EXPLAIN_NOTE AS NVARCHAR(250)))), N'') IS NULL
                            THEN inv.EXPLAIN
                        WHEN NULLIF(LTRIM(RTRIM(inv.EXPLAIN)), N'') IS NULL
                            THEN CAST(h.EXPLAIN_NOTE AS NVARCHAR(250))
                        WHEN CHARINDEX(CAST(h.EXPLAIN_NOTE AS NVARCHAR(250)), inv.EXPLAIN) > 0
                            THEN inv.EXPLAIN
                        ELSE LEFT(inv.EXPLAIN + N' | ' + CAST(h.EXPLAIN_NOTE AS NVARCHAR(250)), 250)
                    END,
                    250
                )
            FROM energy.dbo.LS_005_01_INVOICE inv
            INNER JOIN izgazMGR.dbo.LS_OV_KISMI_HDR h WITH (NOLOCK)
                ON inv.LREF = CAST(h.LREF AS INT)
            WHERE (@AGR_ID IS NULL OR h.ABYS_AGREEMENT_ID = @AGR_ID)
            OPTION (RECOMPILE, MAXDOP 24);
        END
        ELSE
        BEGIN
            UPDATE inv
            SET inv.TLTOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.TLTOTAL)),
                inv.TAX = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.TAX)),
                inv.GRANDTOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.GRANDTOTAL)),
                inv.PAYABLETOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.PAYABLETOTAL)),
                inv.EXPLAIN = LEFT(
                    CASE
                        WHEN NULLIF(LTRIM(RTRIM(inv.EXPLAIN)), N'') IS NULL
                            THEN N'Kısmi Eksilten'
                        WHEN CHARINDEX(N'Kısmi Eksilten', inv.EXPLAIN) > 0
                            THEN inv.EXPLAIN
                        ELSE LEFT(inv.EXPLAIN + N' | Kısmi Eksilten', 250)
                    END,
                    250
                )
            FROM energy.dbo.LS_005_01_INVOICE inv
            INNER JOIN izgazMGR.dbo.LS_OV_KISMI_HDR h WITH (NOLOCK)
                ON inv.LREF = CAST(h.LREF AS INT)
            WHERE (@AGR_ID IS NULL OR h.ABYS_AGREEMENT_ID = @AGR_ID)
            OPTION (RECOMPILE, MAXDOP 24);
        END

        SET @N = @@ROWCOUNT;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'KISMI HDR upd=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ---- KISMI borc PAYTRANS (v09 R32): UPDATE mevcut; yoksa INSERT ---- */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_KISMI_HDR', 'U') IS NOT NULL
    BEGIN
        UPDATE pt
        SET pt.TLTOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.TLTOTAL)),
            pt.TAX = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.TAX)),
            pt.GRANDTOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.GRANDTOTAL)),
            pt.PAYABLETOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.PAYABLETOTAL)),
            pt.CURTOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.GRANDTOTAL))
        FROM energy.dbo.LS_005_01_PAYTRANS pt
        INNER JOIN izgazMGR.dbo.LS_OV_KISMI_HDR h WITH (NOLOCK)
            ON pt.INVOICEREF = CAST(h.LREF AS INT)
        WHERE (@AGR_ID IS NULL OR h.ABYS_AGREEMENT_ID = @AGR_ID)
          AND ISNULL(pt.IOCODE, 0) = 0
          AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
          AND ISNULL(pt.CANCELED, 0) = 0
        OPTION (RECOMPILE, MAXDOP 24);

        SET @N = @@ROWCOUNT;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'KISMI PT upd=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        /* Eksik borc PT — 575 modeli (IDENTITY LREF; INVOICEREF=MAIN) */
        INSERT INTO energy.dbo.LS_005_01_PAYTRANS WITH (TABLOCK) (
            INVOICEREF, INVLINEREF, DATE_, [TYPE], CLIENTREF, CLIENT_TYPE,
            IOCODE, TLTOTAL, PAID, DUEDATE, PAYTYPE, CURID, CURRATE, CURTOTAL,
            CROSSREF, TRANSTYPE, CANCELED, TAX, GRANDTOTAL, LINETYPE, INST_NR,
            PAYABLETOTAL, ADDDATE, ADDUSER, CANCELLATIONPAYMENT, BN_TYPE, XTYPE, PAYCURID,
            ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF
        )
        SELECT
            inv.LREF,
            NULL,
            inv.DATE_,
            inv.[TYPE],
            inv.CLIENTREF,
            inv.OWNERTYPE,
            CAST(0 AS TINYINT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.TLTOTAL)),
            CAST(0 AS FLOAT),
            inv.DUEDATE,
            CAST(174 AS INT),
            ISNULL(inv.CURID, 160),
            CAST(1 AS FLOAT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.GRANDTOTAL)),
            NULL,
            CAST(113 AS INT),
            CAST(0 AS BIT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.TAX)),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.GRANDTOTAL)),
            CAST(103 AS INT),
            CAST(0 AS INT),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.PAYABLETOTAL)),
            inv.ADDDATE,
            ISNULL(inv.ADDUSER, 20001),
            CAST(0 AS INT),
            TRY_CAST(inv.BN_TYPE AS INT),
            ISNULL(inv.XTYPE, 1),
            ISNULL(inv.CURID, 160),
            inv.ABYS_ID,
            inv.ABYS_ACCOUNT_ID,
            inv.ABYS_AGREEMENT_ID,
            inv.LREF
        FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
        INNER JOIN izgazMGR.dbo.LS_OV_KISMI_HDR h WITH (NOLOCK)
            ON inv.LREF = CAST(h.LREF AS INT)
        WHERE (@AGR_ID IS NULL OR h.ABYS_AGREEMENT_ID = @AGR_ID)
          AND ISNULL(inv.IOCODE, 0) = 0
          AND NOT EXISTS (
                SELECT 1
                FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
                WHERE pt.INVOICEREF = inv.LREF
                  AND ISNULL(pt.IOCODE, 0) = 0
                  AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
                  AND ISNULL(pt.CANCELED, 0) = 0
              )
        OPTION (RECOMPILE, MAXDOP 24);

        SET @N = @@ROWCOUNT;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'KISMI PT insert=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ---- AGR wiring (KUL) — energy AGR.LREF / CON / FRMID ---- */
    UPDATE inv
    SET inv.CLIENTREF = ISNULL(agr.CON, agr.FRMID),
        inv.OWNERTYPE = CASE WHEN ISNULL(agr.CON, 0) > 0 THEN 91 ELSE 90 END,
        inv.OWNERREF  = agr.LREF
    FROM energy.dbo.LS_005_01_INVOICE inv
    INNER JOIN energy.dbo.LS_005_01_AGR agr
        ON inv.ABYS_AGREEMENT_ID = agr.ABYS_ID
    WHERE (@AGR_ID IS NULL OR inv.ABYS_AGREEMENT_ID = @AGR_ID)
      AND agr.TP2 = 'KUL'
    OPTION (RECOMPILE, MAXDOP 24);

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'AGR wiring INV=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* INVLINES / PAYTRANS CLIENTREF = fatura CLIENTREF */
    UPDATE il
    SET il.CLIENTREF = inv.CLIENTREF
    FROM energy.dbo.LS_005_01_INVLINES il
    INNER JOIN energy.dbo.LS_005_01_INVOICE inv
        ON inv.LREF = il.INVOICEREF
    WHERE (@AGR_ID IS NULL OR inv.ABYS_AGREEMENT_ID = @AGR_ID)
      AND il.ABYS_ID IS NOT NULL
      AND ISNULL(il.CLIENTREF, -1) <> ISNULL(inv.CLIENTREF, -1)
    OPTION (RECOMPILE, MAXDOP 24);

    UPDATE pt
    SET pt.CLIENTREF = inv.CLIENTREF
    FROM energy.dbo.LS_005_01_PAYTRANS pt
    INNER JOIN energy.dbo.LS_005_01_INVOICE inv
        ON inv.LREF = pt.INVOICEREF
    WHERE (@AGR_ID IS NULL OR inv.ABYS_AGREEMENT_ID = @AGR_ID)
      AND pt.ABYS_ID IS NOT NULL
      AND ISNULL(pt.CLIENTREF, -1) <> ISNULL(inv.CLIENTREF, -1)
    OPTION (RECOMPILE, MAXDOP 24);

    SELECT @MaxLref = ISNULL(MAX(LREF), 0) FROM energy.dbo.LS_005_01_INVOICE;
    DBCC CHECKIDENT('energy.dbo.LS_005_01_INVOICE', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF OBJECT_ID('energy.dbo.LS_005_01_INVLINES', 'U') IS NOT NULL
    BEGIN
        SELECT @MaxLref = ISNULL(MAX(LREF), 0) FROM energy.dbo.LS_005_01_INVLINES;
        DBCC CHECKIDENT('energy.dbo.LS_005_01_INVLINES', RESEED, @MaxLref) WITH NO_INFOMSGS;
    END

    SELECT @MaxLref = ISNULL(MAX(LREF), 0) FROM energy.dbo.LS_005_01_PAYTRANS;
    DBCC CHECKIDENT('energy.dbo.LS_005_01_PAYTRANS', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
        RAISERROR('SP_MIGRATE_EKSILTEN_OVERLAY_AGR OK', 0, 1) WITH NOWAIT;
END
GO

PRINT '590_EKSILTEN_OVERLAY__full OK';
GO

-- Calistirma:
-- EXEC energy.dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR @AGR_ID=NULL, @CLEAN=1, @DEBUG=1;
GO



