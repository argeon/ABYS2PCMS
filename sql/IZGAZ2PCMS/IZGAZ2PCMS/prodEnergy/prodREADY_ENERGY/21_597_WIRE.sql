/* ============================================================
   prodREADY_ENERGY / 21_597_WIRE  (v5)
   - CANCEL_PAY INVOICEREF + IADE_PT drop
   - PAY_PT.CROSSREF → borç PT (staging debt lookup, APPLY YOK)
   - Fallback xref sadece CROSSREF eksik/hatali
   - DEBT_PAID CLOSED/LPD (typed staging)
   - ZERO_PAYABLE / PAID / BANKREF batch'li
   - MAIN/DEBT/PAY BANKREF: MGR→staging + batch
   - TAH BANKREF: BANK_LREF stage + keyset
   - v5 AFL heal:
       * aktif CANCEL_REV (IOCODE=0,CP=1) → AFL yok/BALANCE<=0.02 ise CANCELED=1
       * ayni faturalarda ana borc PAID=PAYABLE + INV CLOSED=1
   - #temp YOK | BEGIN TRAN YOK (dis tran ile CAGIRMA)
   Backup: _backup_597_WIRE_yyyyMMdd_HHmmss/
   ============================================================ */
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---- fiziksel staging (energy CP1254) ---- */
IF OBJECT_ID('dbo.MIG_597_STG_PAY_XREF', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_PAY_XREF (
        ABYS_ID           BIGINT NULL,
        LREF_HINT         BIGINT NULL,
        MAIN_LREF         INT    NULL,
        ABYS_AGREEMENT_ID BIGINT NULL
    );
END
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MIG_597_STG_PAY_XREF') AND name = 'CX_MIG_597_STG_PAY_XREF_ABYS'
)
    CREATE CLUSTERED INDEX CX_MIG_597_STG_PAY_XREF_ABYS
        ON dbo.MIG_597_STG_PAY_XREF (ABYS_ID);
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MIG_597_STG_PAY_XREF') AND name = 'IX_MIG_597_STG_PAY_XREF_HINT'
)
    CREATE NONCLUSTERED INDEX IX_MIG_597_STG_PAY_XREF_HINT
        ON dbo.MIG_597_STG_PAY_XREF (LREF_HINT)
        WHERE LREF_HINT IS NOT NULL;
GO

IF OBJECT_ID('dbo.MIG_597_STG_KEYS', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_KEYS (
        MAIN_LREF INT NOT NULL,
        CONSTRAINT PK_MIG_597_STG_KEYS PRIMARY KEY CLUSTERED (MAIN_LREF)
    );
END
GO

IF OBJECT_ID('dbo.MIG_597_STG_DEBT_LOOKUP', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_DEBT_LOOKUP (
        MAIN_LREF    INT NOT NULL,
        DEBT_PT_LREF INT NOT NULL,
        CONSTRAINT PK_MIG_597_STG_DEBT_LOOKUP PRIMARY KEY CLUSTERED (MAIN_LREF)
    );
END
GO

IF OBJECT_ID('dbo.MIG_597_STG_DEBT_PAID', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_DEBT_PAID (
        MAIN_LREF         INT      NOT NULL,
        CLOSED            BIT      NULL,
        LASTPAIDDATE      DATETIME NULL,
        BANKREF           INT      NULL,
        ABYS_AGREEMENT_ID BIGINT   NULL,
        CONSTRAINT PK_MIG_597_STG_DEBT_PAID PRIMARY KEY CLUSTERED (MAIN_LREF)
    );
END
GO

IF OBJECT_ID('dbo.MIG_597_STG_TAH_BANK', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_TAH_BANK (
        INV_LREF          INT    NOT NULL,
        ABYS_ID           BIGINT NULL,
        BANK_SMS          INT    NOT NULL,
        BANK_LREF         INT    NULL,  /* LS_BANK.LREF — stage fill sonrasi cozulur */
        ABYS_AGREEMENT_ID BIGINT NULL,
        CONSTRAINT PK_MIG_597_STG_TAH_BANK PRIMARY KEY CLUSTERED (INV_LREF)
    );
END
GO
IF COL_LENGTH('dbo.MIG_597_STG_TAH_BANK', 'BANK_LREF') IS NULL
    ALTER TABLE dbo.MIG_597_STG_TAH_BANK ADD BANK_LREF INT NULL;
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MIG_597_STG_TAH_BANK') AND name = 'IX_MIG_597_STG_TAH_BANK_ABYS'
)
    CREATE NONCLUSTERED INDEX IX_MIG_597_STG_TAH_BANK_ABYS
        ON dbo.MIG_597_STG_TAH_BANK (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

IF OBJECT_ID('dbo.MIG_597_STG_BATCH', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_BATCH (
        LREF INT NOT NULL,
        CONSTRAINT PK_MIG_597_STG_BATCH PRIMARY KEY CLUSTERED (LREF)
    );
END
GO

/* MAIN INV BANKREF staging (MGR LS_INVOICE.BANKREF = SMS id) */
IF OBJECT_ID('dbo.MIG_597_STG_MAIN_BANK', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_MAIN_BANK (
        INV_LREF  INT NOT NULL,
        BANK_SMS  INT NOT NULL,
        BANK_LREF INT NULL,
        CONSTRAINT PK_MIG_597_STG_MAIN_BANK PRIMARY KEY CLUSTERED (INV_LREF)
    );
END
GO
IF COL_LENGTH('dbo.MIG_597_STG_MAIN_BANK', 'BANK_LREF') IS NULL
    ALTER TABLE dbo.MIG_597_STG_MAIN_BANK ADD BANK_LREF INT NULL;
GO

/* Debt PT BANKREF staging */
IF OBJECT_ID('dbo.MIG_597_STG_DEBT_PT_BANK', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_DEBT_PT_BANK (
        ABYS_ID           BIGINT NOT NULL,
        BANK_SMS          INT    NOT NULL,
        BANK_LREF         INT    NULL,
        ABYS_AGREEMENT_ID BIGINT NULL,
        CONSTRAINT PK_MIG_597_STG_DEBT_PT_BANK PRIMARY KEY CLUSTERED (ABYS_ID)
    );
END
GO
IF COL_LENGTH('dbo.MIG_597_STG_DEBT_PT_BANK', 'BANK_LREF') IS NULL
    ALTER TABLE dbo.MIG_597_STG_DEBT_PT_BANK ADD BANK_LREF INT NULL;
GO

/* Tahsilat / OV_PAY_PT BANKREF staging (ABYS_ID = PAY_LREF) */
IF OBJECT_ID('dbo.MIG_597_STG_PAY_BANK', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_PAY_BANK (
        ABYS_ID   BIGINT NOT NULL,
        BANK_SMS  INT    NOT NULL,
        BANK_LREF INT    NULL,
        SOZLESME  BIGINT NULL,
        CONSTRAINT PK_MIG_597_STG_PAY_BANK PRIMARY KEY CLUSTERED (ABYS_ID)
    );
END
GO
IF COL_LENGTH('dbo.MIG_597_STG_PAY_BANK', 'BANK_LREF') IS NULL
    ALTER TABLE dbo.MIG_597_STG_PAY_BANK ADD BANK_LREF INT NULL;
GO

IF OBJECT_ID('dbo.MIG_597_STG_BATCH_ABYS', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_BATCH_ABYS (
        ABYS_ID BIGINT NOT NULL,
        CONSTRAINT PK_MIG_597_STG_BATCH_ABYS PRIMARY KEY CLUSTERED (ABYS_ID)
    );
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_WIRE
    @AGR_ID    BIGINT = NULL,
    @DEBUG     BIT = 1,
    @BatchSize INT = 50000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET IMPLICIT_TRANSACTIONS OFF;
    /* DIS BEGIN TRAN ILE CAGIRMA — her statement kendi commit'i */

    IF @BatchSize IS NULL OR @BatchSize < 1000 SET @BatchSize = 50000;
    IF @BatchSize > 200000 SET @BatchSize = 200000;

    DECLARE @Msg NVARCHAR(400), @N INT, @BatchN INT, @Total BIGINT, @AbysFb INT;
    DECLARE @LastLref INT, @LastAbys BIGINT;
    DECLARE @EpsAfl DECIMAL(18,2) = 0.02;

    IF OBJECT_ID('dbo.MIG_597_STG_DEBT_LOOKUP', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_597_STG_KEYS', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_597_STG_PAY_XREF', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_597_STG_BATCH', 'U') IS NULL
    BEGIN
        RAISERROR('MIG_597_STG_* yok — once 21_597_WIRE.sql DDL deploy.', 16, 1);
        RETURN;
    END

    /* ============================================================
       1) CANCEL_PAY.INVOICEREF ← IADE ENERGY_LREF
       ============================================================ */
    UPDATE pt
    SET pt.INVOICEREF = mi.ENERGY_LREF,
        pt.ABYS_INVOICE_LREF = mi.ENERGY_LREF
    FROM dbo.LS_005_01_PAYTRANS pt
    INNER JOIN dbo.MIG_OV_ID_MAP mp
        ON mp.ENERGY_LREF = pt.LREF AND mp.OV_KIND = 'CANCEL_PAY'
    INNER JOIN izgazMGR.dbo.LS_OV_CANCEL_PAY s WITH (NOLOCK)
        ON s.SRC_KEY = mp.SRC_KEY
    INNER JOIN dbo.MIG_OV_ID_MAP mi
        ON mi.SRC_KEY = s.INVOICE_SRC_KEY
    WHERE mi.ENERGY_LREF IS NOT NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);
    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 WIRE CANCEL_PAY INVOICEREF=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* Cancel path: IADE CreateReverse PT sil (cift alacak) */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_CANCEL_PAY', 'U') IS NOT NULL
       AND OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_PAYTRANS', 'U') IS NOT NULL
    BEGIN
        DELETE pt
        FROM dbo.LS_005_01_PAYTRANS pt
        INNER JOIN dbo.MIG_OV_ID_MAP mpt
            ON mpt.ENERGY_LREF = pt.LREF AND mpt.OV_KIND = 'IADE_PT'
        INNER JOIN izgazMGR.dbo.LS_OV_IADE_PAYTRANS ip WITH (NOLOCK)
            ON ip.SRC_KEY = mpt.SRC_KEY
        INNER JOIN izgazMGR.dbo.LS_OV_CANCEL_PAY c WITH (NOLOCK)
            ON c.INVOICE_SRC_KEY = ip.INVOICE_SRC_KEY
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND c.ABYS_AGREEMENT_ID IS NULL AND c.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND c.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE drop IADE_PT where CANCEL=' + CAST(@@ROWCOUNT AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ============================================================
       2) DEBT LOOKUP — MAIN_LREF → debt PT.LREF (tek sefer, APPLY yok)
       ============================================================ */
    TRUNCATE TABLE dbo.MIG_597_STG_KEYS;
    TRUNCATE TABLE dbo.MIG_597_STG_DEBT_LOOKUP;

    INSERT INTO dbo.MIG_597_STG_KEYS (MAIN_LREF)
    SELECT DISTINCT CAST(s.CROSSREF_MAIN_LREF AS INT)
    FROM izgazMGR.dbo.LS_OV_PAY_PT s WITH (NOLOCK)
    WHERE s.CROSSREF_MAIN_LREF IS NOT NULL
      AND CAST(s.CROSSREF_MAIN_LREF AS INT) BETWEEN 1 AND 2147483647
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);

    INSERT INTO dbo.MIG_597_STG_DEBT_LOOKUP (MAIN_LREF, DEBT_PT_LREF)
    SELECT k.MAIN_LREF, MIN(d.LREF)
    FROM dbo.MIG_597_STG_KEYS k
    INNER JOIN dbo.LS_005_01_PAYTRANS d WITH (NOLOCK)
        ON d.INVOICEREF = k.MAIN_LREF
    WHERE d.IOCODE = 0
      AND ISNULL(d.CANCELED, 0) = 0
      AND ISNULL(d.CANCELLATIONPAYMENT, 0) = 0
    GROUP BY k.MAIN_LREF
    OPTION (RECOMPILE, MAXDOP 24);

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 WIRE debt_lookup mains='
                 + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_KEYS) AS VARCHAR(20))
                 + N' resolved='
                 + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_DEBT_LOOKUP) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 2a) MAP path CROSSREF — batch */
    SET @Total = 0;
    WHILE 1 = 1
    BEGIN
        TRUNCATE TABLE dbo.MIG_597_STG_BATCH;

        INSERT INTO dbo.MIG_597_STG_BATCH (LREF)
        SELECT TOP (@BatchSize) pt.LREF
        FROM dbo.LS_005_01_PAYTRANS pt
        INNER JOIN dbo.MIG_OV_ID_MAP m
            ON m.ENERGY_LREF = pt.LREF AND m.OV_KIND = 'PAY_PT'
        INNER JOIN izgazMGR.dbo.LS_OV_PAY_PT s WITH (NOLOCK)
            ON s.SRC_KEY = m.SRC_KEY
        INNER JOIN dbo.MIG_597_STG_DEBT_LOOKUP l
            ON l.MAIN_LREF = CAST(s.CROSSREF_MAIN_LREF AS INT)
        WHERE pt.IOCODE <> 0
          AND s.CROSSREF_MAIN_LREF IS NOT NULL
          AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
                )
          AND (pt.CROSSREF IS NULL OR pt.CROSSREF <> l.DEBT_PT_LREF)
        OPTION (RECOMPILE, MAXDOP 24);

        SET @BatchN = @@ROWCOUNT;
        IF @BatchN = 0 BREAK;

        UPDATE pt
        SET pt.CROSSREF = l.DEBT_PT_LREF
        FROM dbo.LS_005_01_PAYTRANS pt
        INNER JOIN dbo.MIG_597_STG_BATCH b ON b.LREF = pt.LREF
        INNER JOIN dbo.MIG_OV_ID_MAP m
            ON m.ENERGY_LREF = pt.LREF AND m.OV_KIND = 'PAY_PT'
        INNER JOIN izgazMGR.dbo.LS_OV_PAY_PT s WITH (NOLOCK)
            ON s.SRC_KEY = m.SRC_KEY
        INNER JOIN dbo.MIG_597_STG_DEBT_LOOKUP l
            ON l.MAIN_LREF = CAST(s.CROSSREF_MAIN_LREF AS INT)
        OPTION (RECOMPILE, MAXDOP 24);

        SET @Total = @Total + @BatchN;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE CROSSREF MAP batch=' + CAST(@BatchN AS VARCHAR(20))
                     + N' total=' + CAST(@Total AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 WIRE PAY_PT CROSSREF→debt PT(MAP)=' + CAST(@Total AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 2b) Fallback CROSSREF
       - LREF_HINT: guvenli (hint→multi MAIN = 0 olculdu)
       - ABYS_ID: SADECE tek-MAIN ABYS (multi-MAIN ~434k FANOUT YASAK)
       Asil yol MAP/SRC_KEY (2a). */
    SET @N = 0;

    /* --- HINT fallback --- */
    TRUNCATE TABLE dbo.MIG_597_STG_PAY_XREF;
    INSERT INTO dbo.MIG_597_STG_PAY_XREF (ABYS_ID, LREF_HINT, MAIN_LREF, ABYS_AGREEMENT_ID)
    SELECT
        s.ABYS_ID,
        s.LREF_HINT,
        CAST(s.CROSSREF_MAIN_LREF AS INT),
        s.ABYS_AGREEMENT_ID
    FROM izgazMGR.dbo.LS_OV_PAY_PT s WITH (NOLOCK)
    INNER JOIN dbo.MIG_597_STG_DEBT_LOOKUP l
        ON l.MAIN_LREF = CAST(s.CROSSREF_MAIN_LREF AS INT)
    WHERE s.CROSSREF_MAIN_LREF IS NOT NULL
      AND s.LREF_HINT IS NOT NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
      AND EXISTS (
            SELECT 1
            FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
            WHERE pt.LREF = s.LREF_HINT
              AND pt.IOCODE <> 0
              AND (
                    pt.CROSSREF IS NULL
                 OR pt.CROSSREF <> l.DEBT_PT_LREF
                 OR NOT EXISTS (
                        SELECT 1 FROM dbo.LS_005_01_PAYTRANS d2 WITH (NOLOCK)
                        WHERE d2.LREF = pt.CROSSREF AND d2.IOCODE = 0
                    )
                  )
        )
    OPTION (RECOMPILE, MAXDOP 24);

    UPDATE pt
    SET pt.CROSSREF = l.DEBT_PT_LREF
    FROM dbo.LS_005_01_PAYTRANS pt
    INNER JOIN dbo.MIG_597_STG_PAY_XREF s ON s.LREF_HINT = pt.LREF
    INNER JOIN dbo.MIG_597_STG_DEBT_LOOKUP l ON l.MAIN_LREF = s.MAIN_LREF
    WHERE pt.IOCODE <> 0
      AND s.LREF_HINT IS NOT NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND (pt.ABYS_AGREEMENT_ID IS NULL OR s.ABYS_AGREEMENT_ID IS NULL))
           OR (@AGR_ID > 0 AND (pt.ABYS_AGREEMENT_ID = @AGR_ID OR s.ABYS_AGREEMENT_ID = @AGR_ID))
            )
      AND (pt.CROSSREF IS NULL OR pt.CROSSREF <> l.DEBT_PT_LREF
           OR NOT EXISTS (
                SELECT 1 FROM dbo.LS_005_01_PAYTRANS d2 WITH (NOLOCK)
                WHERE d2.LREF = pt.CROSSREF AND d2.IOCODE = 0
              ))
    OPTION (RECOMPILE, MAXDOP 24);
    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 WIRE CROSSREF fallback HINT=' + CAST(@N AS VARCHAR(20))
                 + N' rows=' + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY_XREF) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* --- ABYS fallback: sadece tek-MAIN ABYS_ID --- */
    TRUNCATE TABLE dbo.MIG_597_STG_PAY_XREF;
    INSERT INTO dbo.MIG_597_STG_PAY_XREF (ABYS_ID, LREF_HINT, MAIN_LREF, ABYS_AGREEMENT_ID)
    SELECT
        s.ABYS_ID,
        s.LREF_HINT,
        CAST(s.CROSSREF_MAIN_LREF AS INT),
        s.ABYS_AGREEMENT_ID
    FROM izgazMGR.dbo.LS_OV_PAY_PT s WITH (NOLOCK)
    INNER JOIN dbo.MIG_597_STG_DEBT_LOOKUP l
        ON l.MAIN_LREF = CAST(s.CROSSREF_MAIN_LREF AS INT)
    WHERE s.CROSSREF_MAIN_LREF IS NOT NULL
      AND s.ABYS_ID IS NOT NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
      /* P0: multi-MAIN ABYS fanout YASAK (~434k key) */
      AND NOT EXISTS (
            SELECT 1
            FROM izgazMGR.dbo.LS_OV_PAY_PT s2 WITH (NOLOCK)
            WHERE s2.ABYS_ID = s.ABYS_ID
              AND s2.CROSSREF_MAIN_LREF IS NOT NULL
              AND CAST(s2.CROSSREF_MAIN_LREF AS INT) <> CAST(s.CROSSREF_MAIN_LREF AS INT)
        )
      AND EXISTS (
            SELECT 1
            FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
            WHERE pt.ABYS_ID = s.ABYS_ID
              AND pt.IOCODE <> 0
              AND (
                    pt.CROSSREF IS NULL
                 OR pt.CROSSREF <> l.DEBT_PT_LREF
                 OR NOT EXISTS (
                        SELECT 1 FROM dbo.LS_005_01_PAYTRANS d2 WITH (NOLOCK)
                        WHERE d2.LREF = pt.CROSSREF AND d2.IOCODE = 0
                    )
                  )
        )
    OPTION (RECOMPILE, MAXDOP 24);

    SET @AbysFb = 0;
    UPDATE pt
    SET pt.CROSSREF = l.DEBT_PT_LREF
    FROM dbo.LS_005_01_PAYTRANS pt
    INNER JOIN dbo.MIG_597_STG_PAY_XREF s ON s.ABYS_ID = pt.ABYS_ID
    INNER JOIN dbo.MIG_597_STG_DEBT_LOOKUP l ON l.MAIN_LREF = s.MAIN_LREF
    WHERE pt.IOCODE <> 0
      AND pt.ABYS_ID IS NOT NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND (pt.ABYS_AGREEMENT_ID IS NULL OR s.ABYS_AGREEMENT_ID IS NULL))
           OR (@AGR_ID > 0 AND (pt.ABYS_AGREEMENT_ID = @AGR_ID OR s.ABYS_AGREEMENT_ID = @AGR_ID))
            )
      AND (pt.CROSSREF IS NULL OR pt.CROSSREF <> l.DEBT_PT_LREF
           OR NOT EXISTS (
                SELECT 1 FROM dbo.LS_005_01_PAYTRANS d2 WITH (NOLOCK)
                WHERE d2.LREF = pt.CROSSREF AND d2.IOCODE = 0
              ))
    OPTION (RECOMPILE, MAXDOP 24);
    SET @AbysFb = @@ROWCOUNT;
    SET @N = @N + @AbysFb;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 WIRE CROSSREF fallback ABYS(single-MAIN)=' + CAST(@AbysFb AS VARCHAR(20))
                 + N' rows=' + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY_XREF) AS VARCHAR(20))
                 + N' total_fb=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* ============================================================
       3) DEBT_PAID → MAIN CLOSED + LASTPAIDDATE (+ BANK SMS id)
       ============================================================ */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_DEBT_PAID_UPD', 'U') IS NOT NULL
       AND OBJECT_ID('dbo.MIG_597_STG_DEBT_PAID', 'U') IS NOT NULL
    BEGIN
        TRUNCATE TABLE dbo.MIG_597_STG_DEBT_PAID;

        IF COL_LENGTH('izgazMGR.dbo.LS_OV_DEBT_PAID_UPD', 'LASTPAIDDATE') IS NOT NULL
        BEGIN
            INSERT INTO dbo.MIG_597_STG_DEBT_PAID (
                MAIN_LREF, CLOSED, LASTPAIDDATE, BANKREF, ABYS_AGREEMENT_ID
            )
            SELECT MAIN_LREF, CLOSED, LASTPAIDDATE, BANKREF, ABYS_AGREEMENT_ID
            FROM (
                SELECT
                    CAST(TRY_CAST(u.MAIN_LREF AS BIGINT) AS INT) AS MAIN_LREF,
                    CASE WHEN TRY_CAST(u.CLOSED AS INT) = 1 THEN CAST(1 AS BIT) ELSE NULL END AS CLOSED,
                    CASE WHEN u.LASTPAIDDATE IS NOT NULL
                              AND CAST(u.LASTPAIDDATE AS DATETIME2) >= CAST('1900-01-01' AS DATETIME2)
                              AND CAST(u.LASTPAIDDATE AS DATETIME2) <= CAST('2079-06-06 23:59:00' AS DATETIME2)
                         THEN CAST(CAST(u.LASTPAIDDATE AS DATETIME2) AS SMALLDATETIME)
                         ELSE NULL END AS LASTPAIDDATE,
                    TRY_CAST(u.BANKREF AS INT) AS BANKREF,
                    TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) AS ABYS_AGREEMENT_ID,
                    ROW_NUMBER() OVER (
                        PARTITION BY CAST(TRY_CAST(u.MAIN_LREF AS BIGINT) AS INT)
                        ORDER BY CASE WHEN TRY_CAST(u.CLOSED AS INT) = 1 THEN 0 ELSE 1 END
                    ) AS rn
                FROM izgazMGR.dbo.LS_OV_DEBT_PAID_UPD u WITH (NOLOCK)
                WHERE TRY_CAST(u.MAIN_LREF AS BIGINT) BETWEEN 1 AND 2147483647
                  AND (
                      @AGR_ID IS NULL
                   OR (@AGR_ID = -1 AND TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) IS NULL)
                   OR (@AGR_ID > 0 AND TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) = @AGR_ID)
                    )
            ) x
            WHERE x.rn = 1
            OPTION (RECOMPILE, MAXDOP 24);
        END
        ELSE
        BEGIN
            INSERT INTO dbo.MIG_597_STG_DEBT_PAID (
                MAIN_LREF, CLOSED, LASTPAIDDATE, BANKREF, ABYS_AGREEMENT_ID
            )
            SELECT MAIN_LREF, CLOSED, LASTPAIDDATE, BANKREF, ABYS_AGREEMENT_ID
            FROM (
                SELECT
                    CAST(TRY_CAST(u.MAIN_LREF AS BIGINT) AS INT) AS MAIN_LREF,
                    CASE WHEN TRY_CAST(u.CLOSED AS INT) = 1 THEN CAST(1 AS BIT) ELSE NULL END AS CLOSED,
                    CAST(NULL AS DATETIME) AS LASTPAIDDATE,
                    CAST(NULL AS INT) AS BANKREF,
                    TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) AS ABYS_AGREEMENT_ID,
                    ROW_NUMBER() OVER (
                        PARTITION BY CAST(TRY_CAST(u.MAIN_LREF AS BIGINT) AS INT)
                        ORDER BY (SELECT 0)
                    ) AS rn
                FROM izgazMGR.dbo.LS_OV_DEBT_PAID_UPD u WITH (NOLOCK)
                WHERE TRY_CAST(u.MAIN_LREF AS BIGINT) BETWEEN 1 AND 2147483647
                  AND TRY_CAST(u.CLOSED AS INT) = 1
                  AND (
                      @AGR_ID IS NULL
                   OR (@AGR_ID = -1 AND TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) IS NULL)
                   OR (@AGR_ID > 0 AND TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) = @AGR_ID)
                    )
            ) x
            WHERE x.rn = 1
            OPTION (RECOMPILE, MAXDOP 24);
        END

        SET @Total = 0;
        WHILE 1 = 1
        BEGIN
            TRUNCATE TABLE dbo.MIG_597_STG_BATCH;

            INSERT INTO dbo.MIG_597_STG_BATCH (LREF)
            SELECT TOP (@BatchSize) inv.LREF
            FROM dbo.LS_005_01_INVOICE inv
            INNER JOIN dbo.MIG_597_STG_DEBT_PAID u ON u.MAIN_LREF = inv.LREF
            WHERE (
                    (u.CLOSED = 1 AND ISNULL(inv.CLOSED, 0) = 0)
                 OR (u.LASTPAIDDATE IS NOT NULL AND inv.LASTPAIDDATE IS NULL)
                 OR (u.BANKREF IS NOT NULL AND inv.BANKREF IS NULL)
              )
            OPTION (RECOMPILE, MAXDOP 24);

            SET @BatchN = @@ROWCOUNT;
            IF @BatchN = 0 BREAK;

            UPDATE inv
            SET inv.CLOSED = CASE WHEN u.CLOSED = 1 THEN CAST(1 AS BIT) ELSE inv.CLOSED END,
                inv.LASTPAIDDATE = CASE
                    WHEN u.LASTPAIDDATE IS NOT NULL AND inv.LASTPAIDDATE IS NULL
                    THEN u.LASTPAIDDATE ELSE inv.LASTPAIDDATE END,
                inv.BANKREF = COALESCE(u.BANKREF, inv.BANKREF)
            FROM dbo.LS_005_01_INVOICE inv
            INNER JOIN dbo.MIG_597_STG_BATCH b ON b.LREF = inv.LREF
            INNER JOIN dbo.MIG_597_STG_DEBT_PAID u ON u.MAIN_LREF = inv.LREF
            OPTION (RECOMPILE, MAXDOP 24);

            SET @Total = @Total + @BatchN;
            IF @DEBUG = 1
            BEGIN
                SET @Msg = N'597 WIRE DEBT_PAID batch=' + CAST(@BatchN AS VARCHAR(20))
                         + N' total=' + CAST(@Total AS VARCHAR(20));
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END
        END

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE DEBT_PAID CLOSED/LPD=' + CAST(@Total AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ============================================================
       4) PAYABLETOTAL=0 → CLOSED=1 (batch; IOCODE=0 debt)
       ============================================================ */
    SET @Total = 0;
    WHILE 1 = 1
    BEGIN
        UPDATE TOP (@BatchSize) inv
        SET inv.CLOSED = CAST(1 AS BIT)
        FROM dbo.LS_005_01_INVOICE inv
        WHERE (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID))
                )
          AND inv.IOCODE = 0
          AND ISNULL(inv.[TYPE], 0) <> 101
          AND ABS(ISNULL(inv.PAYABLETOTAL, 0)) <= 0.01
          AND ISNULL(inv.CLOSED, 0) = 0
        OPTION (RECOMPILE, MAXDOP 24);

        SET @BatchN = @@ROWCOUNT;
        SET @Total = @Total + @BatchN;
        IF @BatchN = 0 BREAK;

        IF @DEBUG = 1 AND (@Total % (@BatchSize * 5) < @BatchSize OR @BatchN < @BatchSize)
        BEGIN
            SET @Msg = N'597 WIRE ZERO_PAYABLE batch cumulative=' + CAST(@Total AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 WIRE ZERO_PAYABLE CLOSED=' + CAST(@Total AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* MAHSUP EXPLAIN mark — CLOSED sadece overlay CLOSED=1 (tam odeme) */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_MAHSUP_CLOSED', 'U') IS NOT NULL
    BEGIN
        UPDATE inv
        SET inv.EXPLAIN = LEFT(
            CASE WHEN inv.EXPLAIN IS NULL OR LTRIM(RTRIM(inv.EXPLAIN)) = ''
                 THEN m.EXPLAIN_MARK
                 ELSE inv.EXPLAIN + N' | ' + (m.EXPLAIN_MARK) END, 250),
            inv.CLOSED = CASE
                WHEN ISNULL(m.CLOSED, 0) = 1 THEN CAST(1 AS BIT)
                WHEN ISNULL(m.CLOSED, 0) = 0 THEN CAST(0 AS BIT) /* kismi mahsup: acik birak / yeniden ac */
                ELSE inv.CLOSED
            END
        FROM dbo.LS_005_01_INVOICE inv
        INNER JOIN izgazMGR.dbo.LS_OV_MAHSUP_CLOSED m WITH (NOLOCK)
            ON inv.LREF = CAST(m.MAIN_LREF AS INT)
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE MAHSUP_CLOSED=' + CAST(@@ROWCOUNT AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ============================================================
       4b) CANCEL_REV + AFL heal (v5)
       AFL yok / BALANCE<=0.02 → CANCEL_REV soft-cancel;
       ilgili MAIN: PAID=PAYABLE + CLOSED=1 (AFL master kapali)
       ============================================================ */
    IF OBJECT_ID('dbo.LS_AFL_OPEN_DEBT', 'U') IS NOT NULL
    BEGIN
        /* INV adaylari: aktif CANCEL_REV var, AFL acik degil */
        TRUNCATE TABLE dbo.MIG_597_STG_KEYS;
        INSERT INTO dbo.MIG_597_STG_KEYS (MAIN_LREF)
        SELECT DISTINCT pt.INVOICEREF
        FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
        INNER JOIN dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
            ON inv.LREF = pt.INVOICEREF
        WHERE pt.IOCODE = 0
          AND ISNULL(pt.CANCELED, 0) = 0
          AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 1
          AND inv.IOCODE = 0
          AND ISNULL(inv.CANCELED, 0) = 0
          AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID))
              )
          AND NOT EXISTS (
                SELECT 1
                FROM dbo.LS_AFL_OPEN_DEBT a WITH (NOLOCK)
                WHERE a.FATURAID = inv.ABYS_ACCOUNT_ID
                  AND CONVERT(DECIMAL(18,2), ISNULL(a.BALANCE, 0)) > @EpsAfl
              )
        OPTION (RECOMPILE, MAXDOP 24);

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE AFL-heal INV candidates='
                     + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_KEYS) AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        /* CANCEL_REV soft-cancel */
        UPDATE pt
        SET pt.CANCELED = CAST(1 AS BIT)
        FROM dbo.LS_005_01_PAYTRANS pt
        INNER JOIN dbo.MIG_597_STG_KEYS k ON k.MAIN_LREF = pt.INVOICEREF
        WHERE pt.IOCODE = 0
          AND ISNULL(pt.CANCELED, 0) = 0
          AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 1
        OPTION (RECOMPILE, MAXDOP 24);

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE CANCEL_REV soft-cancel=' + CAST(@@ROWCOUNT AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        /* Ana borc PT PAID = PAYABLE */
        UPDATE d
        SET d.PAID = d.PAYABLETOTAL
        FROM dbo.LS_005_01_PAYTRANS d
        INNER JOIN dbo.MIG_597_STG_KEYS k ON k.MAIN_LREF = d.INVOICEREF
        WHERE d.IOCODE = 0
          AND ISNULL(d.CANCELED, 0) = 0
          AND ISNULL(d.CANCELLATIONPAYMENT, 0) = 0
          AND ISNULL(d.INST_NR, 0) = 0
          AND CONVERT(DECIMAL(18,2), ISNULL(d.PAID, 0))
            < CONVERT(DECIMAL(18,2), ISNULL(d.PAYABLETOTAL, 0)) - @EpsAfl
        OPTION (RECOMPILE, MAXDOP 24);

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE AFL-heal debt PAID sync=' + CAST(@@ROWCOUNT AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        /* INV CLOSED=1 */
        UPDATE inv
        SET inv.CLOSED = CAST(1 AS BIT)
        FROM dbo.LS_005_01_INVOICE inv
        INNER JOIN dbo.MIG_597_STG_KEYS k ON k.MAIN_LREF = inv.LREF
        WHERE ISNULL(inv.CLOSED, 0) = 0
        OPTION (RECOMPILE, MAXDOP 24);

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE AFL-heal INV CLOSED=' + CAST(@@ROWCOUNT AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END
    ELSE IF @DEBUG = 1
        RAISERROR('597 WIRE AFL-heal SKIP — LS_AFL_OPEN_DEBT yok', 0, 1) WITH NOWAIT;

    /* ============================================================
       5) BANKREF: SMS BANK_ID → LS_BANK.LREF
       ============================================================ */
    SET @N = 0;
    IF OBJECT_ID('dbo.LS_BANK', 'U') IS NOT NULL
       AND COL_LENGTH('dbo.LS_BANK', 'ABYS_ID') IS NOT NULL
       AND OBJECT_ID('izgazMGR.dbo.LS_INVOICE', 'U') IS NOT NULL
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID('dbo.LS_BANK') AND name = 'UX_LS_BANK_ABYS_ID'
        )
            CREATE UNIQUE NONCLUSTERED INDEX UX_LS_BANK_ABYS_ID
                ON dbo.LS_BANK (ABYS_ID) WHERE ABYS_ID IS NOT NULL;

        /* ---- MAIN INV bank: stage + BANK_LREF + keyset ---- */
        TRUNCATE TABLE dbo.MIG_597_STG_MAIN_BANK;
        INSERT INTO dbo.MIG_597_STG_MAIN_BANK (INV_LREF, BANK_SMS)
        SELECT INV_LREF, BANK_SMS
        FROM (
            SELECT
                CAST(m.LREF AS INT) AS INV_LREF,
                TRY_CAST(m.BANKREF AS INT) AS BANK_SMS,
                ROW_NUMBER() OVER (
                    PARTITION BY CAST(m.LREF AS INT)
                    ORDER BY TRY_CAST(m.BANKREF AS INT)
                ) AS rn
            FROM izgazMGR.dbo.LS_INVOICE m WITH (NOLOCK)
            WHERE m.BANKREF IS NOT NULL
              AND m.LREF BETWEEN 1 AND 2147483647
              AND TRY_CAST(m.BANKREF AS INT) IS NOT NULL
        ) x
        WHERE x.rn = 1
        OPTION (RECOMPILE, MAXDOP 8);

        UPDATE t
        SET t.BANK_LREF = b.LREF
        FROM dbo.MIG_597_STG_MAIN_BANK t
        INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = t.BANK_SMS
        WHERE t.BANK_LREF IS NULL OR t.BANK_LREF <> b.LREF
        OPTION (RECOMPILE, MAXDOP 8);

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE MAIN_BANK staged=' + CAST((
                SELECT COUNT_BIG(*) FROM dbo.MIG_597_STG_MAIN_BANK WITH (NOLOCK)
            ) AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        SET @Total = 0;
        SET @LastLref = 0;
        WHILE 1 = 1
        BEGIN
            TRUNCATE TABLE dbo.MIG_597_STG_BATCH;

            INSERT INTO dbo.MIG_597_STG_BATCH (LREF)
            SELECT TOP (@BatchSize) t.INV_LREF
            FROM dbo.MIG_597_STG_MAIN_BANK t
            WHERE t.INV_LREF > @LastLref
              AND t.BANK_LREF IS NOT NULL
            ORDER BY t.INV_LREF
            OPTION (RECOMPILE);

            SET @BatchN = @@ROWCOUNT;
            IF @BatchN = 0 BREAK;

            SELECT @LastLref = MAX(x.LREF) FROM dbo.MIG_597_STG_BATCH x;

            UPDATE inv
            SET inv.BANKREF = t.BANK_LREF
            FROM dbo.LS_005_01_INVOICE inv
            INNER JOIN dbo.MIG_597_STG_BATCH x ON x.LREF = inv.LREF
            INNER JOIN dbo.MIG_597_STG_MAIN_BANK t ON t.INV_LREF = inv.LREF
            WHERE ISNULL(inv.[TYPE], 0) <> 101
              AND t.BANK_LREF IS NOT NULL
              AND (inv.BANKREF IS NULL OR inv.BANKREF <> t.BANK_LREF)
              AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID))
                )
            OPTION (RECOMPILE, MAXDOP 8);

            SET @Total = @Total + @BatchN;
            IF @DEBUG = 1
            BEGIN
                SET @Msg = N'597 WIRE MAIN BANKREF keyset batch=' + CAST(@BatchN AS VARCHAR(20))
                         + N' total=' + CAST(@Total AS VARCHAR(20))
                         + N' last=' + CAST(@LastLref AS VARCHAR(20));
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END
        END
        SET @N = @N + @Total;

        /* ---- debt PT bank: stage + BANK_LREF + keyset ---- */
        IF OBJECT_ID('izgazMGR.dbo.LS_DEBT_PAYTRANS', 'U') IS NOT NULL
           AND OBJECT_ID('dbo.MIG_597_STG_DEBT_PT_BANK', 'U') IS NOT NULL
        BEGIN
            TRUNCATE TABLE dbo.MIG_597_STG_DEBT_PT_BANK;
            INSERT INTO dbo.MIG_597_STG_DEBT_PT_BANK (ABYS_ID, BANK_SMS, ABYS_AGREEMENT_ID)
            SELECT ABYS_ID, BANK_SMS, ABYS_AGREEMENT_ID
            FROM (
                SELECT
                    TRY_CAST(m.ABYS_ID AS BIGINT) AS ABYS_ID,
                    TRY_CAST(m.BANKREF AS INT) AS BANK_SMS,
                    TRY_CAST(m.ABYS_AGREEMENT_ID AS BIGINT) AS ABYS_AGREEMENT_ID,
                    ROW_NUMBER() OVER (
                        PARTITION BY TRY_CAST(m.ABYS_ID AS BIGINT)
                        ORDER BY TRY_CAST(m.BANKREF AS INT)
                    ) AS rn
                FROM izgazMGR.dbo.LS_DEBT_PAYTRANS m WITH (NOLOCK)
                WHERE m.BANKREF IS NOT NULL
                  AND TRY_CAST(m.ABYS_ID AS BIGINT) IS NOT NULL
                  AND TRY_CAST(m.BANKREF AS INT) IS NOT NULL
                  AND (
                        @AGR_ID IS NULL
                     OR (@AGR_ID = -1 AND TRY_CAST(m.ABYS_AGREEMENT_ID AS BIGINT) IS NULL)
                     OR (@AGR_ID > 0 AND TRY_CAST(m.ABYS_AGREEMENT_ID AS BIGINT) = @AGR_ID)
                      )
            ) x
            WHERE x.rn = 1
            OPTION (RECOMPILE, MAXDOP 8);

            UPDATE t
            SET t.BANK_LREF = b.LREF
            FROM dbo.MIG_597_STG_DEBT_PT_BANK t
            INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = t.BANK_SMS
            WHERE t.BANK_LREF IS NULL OR t.BANK_LREF <> b.LREF
            OPTION (RECOMPILE, MAXDOP 8);

            SET @Total = 0;
            SET @LastAbys = 0;
            WHILE 1 = 1
            BEGIN
                TRUNCATE TABLE dbo.MIG_597_STG_BATCH_ABYS;

                INSERT INTO dbo.MIG_597_STG_BATCH_ABYS (ABYS_ID)
                SELECT TOP (@BatchSize) t.ABYS_ID
                FROM dbo.MIG_597_STG_DEBT_PT_BANK t
                WHERE t.ABYS_ID > @LastAbys
                  AND t.BANK_LREF IS NOT NULL
                ORDER BY t.ABYS_ID
                OPTION (RECOMPILE);

                SET @BatchN = @@ROWCOUNT;
                IF @BatchN = 0 BREAK;

                SELECT @LastAbys = MAX(x.ABYS_ID) FROM dbo.MIG_597_STG_BATCH_ABYS x;

                UPDATE pt
                SET pt.BANKREF = t.BANK_LREF
                FROM dbo.LS_005_01_PAYTRANS pt
                INNER JOIN dbo.MIG_597_STG_BATCH_ABYS x ON x.ABYS_ID = pt.ABYS_ID
                INNER JOIN dbo.MIG_597_STG_DEBT_PT_BANK t ON t.ABYS_ID = pt.ABYS_ID
                WHERE pt.IOCODE = 0
                  AND t.BANK_LREF IS NOT NULL
                  AND (pt.BANKREF IS NULL OR pt.BANKREF <> t.BANK_LREF)
                  AND (
                        @AGR_ID IS NULL
                     OR (@AGR_ID = -1 AND (pt.ABYS_AGREEMENT_ID IS NULL OR t.ABYS_AGREEMENT_ID IS NULL))
                     OR (@AGR_ID > 0 AND (pt.ABYS_AGREEMENT_ID = @AGR_ID OR t.ABYS_AGREEMENT_ID = @AGR_ID))
                      )
                OPTION (RECOMPILE, MAXDOP 8);

                SET @Total = @Total + @BatchN;
                IF @DEBUG = 1
                BEGIN
                    SET @Msg = N'597 WIRE DEBT_PT BANKREF keyset batch=' + CAST(@BatchN AS VARCHAR(20))
                             + N' total=' + CAST(@Total AS VARCHAR(20));
                    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
                END
            END
            SET @N = @N + @Total;
        END

        /* ---- Tahsilat PT: LS_PAYMENT stage + BANK_LREF + keyset ---- */
        IF OBJECT_ID('izgazMGR.dbo.LS_PAYMENT', 'U') IS NOT NULL
           AND OBJECT_ID('dbo.MIG_597_STG_PAY_BANK', 'U') IS NOT NULL
        BEGIN
            TRUNCATE TABLE dbo.MIG_597_STG_PAY_BANK;
            INSERT INTO dbo.MIG_597_STG_PAY_BANK (ABYS_ID, BANK_SMS, SOZLESME)
            SELECT ABYS_ID, BANK_SMS, SOZLESME
            FROM (
                SELECT
                    TRY_CAST(p.PAY_LREF AS BIGINT) AS ABYS_ID,
                    TRY_CAST(p.BANKA_ID AS INT) AS BANK_SMS,
                    TRY_CAST(p.SOZLESME AS BIGINT) AS SOZLESME,
                    ROW_NUMBER() OVER (
                        PARTITION BY TRY_CAST(p.PAY_LREF AS BIGINT)
                        ORDER BY TRY_CAST(p.BANKA_ID AS INT)
                    ) AS rn
                FROM izgazMGR.dbo.LS_PAYMENT p WITH (NOLOCK)
                WHERE p.BANKA_ID IS NOT NULL
                  AND ISNULL(p.CANCELED, 0) = 0
                  AND TRY_CAST(p.PAY_LREF AS BIGINT) IS NOT NULL
                  AND TRY_CAST(p.BANKA_ID AS INT) IS NOT NULL
                  AND (
                        @AGR_ID IS NULL
                     OR (@AGR_ID = -1 AND TRY_CAST(p.SOZLESME AS BIGINT) IS NULL)
                     OR (@AGR_ID > 0 AND TRY_CAST(p.SOZLESME AS BIGINT) = @AGR_ID)
                      )
            ) x
            WHERE x.rn = 1
            OPTION (RECOMPILE, MAXDOP 8);

            UPDATE t
            SET t.BANK_LREF = b.LREF
            FROM dbo.MIG_597_STG_PAY_BANK t
            INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = t.BANK_SMS
            WHERE t.BANK_LREF IS NULL OR t.BANK_LREF <> b.LREF
            OPTION (RECOMPILE, MAXDOP 8);

            SET @Total = 0;
            SET @LastAbys = 0;
            WHILE 1 = 1
            BEGIN
                TRUNCATE TABLE dbo.MIG_597_STG_BATCH_ABYS;

                INSERT INTO dbo.MIG_597_STG_BATCH_ABYS (ABYS_ID)
                SELECT TOP (@BatchSize) t.ABYS_ID
                FROM dbo.MIG_597_STG_PAY_BANK t
                WHERE t.ABYS_ID > @LastAbys
                  AND t.BANK_LREF IS NOT NULL
                ORDER BY t.ABYS_ID
                OPTION (RECOMPILE);

                SET @BatchN = @@ROWCOUNT;
                IF @BatchN = 0 BREAK;

                SELECT @LastAbys = MAX(x.ABYS_ID) FROM dbo.MIG_597_STG_BATCH_ABYS x;

                UPDATE pt
                SET pt.BANKREF = t.BANK_LREF
                FROM dbo.LS_005_01_PAYTRANS pt
                INNER JOIN dbo.MIG_597_STG_BATCH_ABYS x ON x.ABYS_ID = pt.ABYS_ID
                INNER JOIN dbo.MIG_597_STG_PAY_BANK t ON t.ABYS_ID = pt.ABYS_ID
                WHERE t.BANK_LREF IS NOT NULL
                  AND (
                        (@AGR_ID > 0 AND pt.ABYS_AGREEMENT_ID = @AGR_ID
                            AND (pt.BANKREF IS NULL OR pt.BANKREF <> t.BANK_LREF))
                     OR (@AGR_ID = -1 AND pt.ABYS_AGREEMENT_ID IS NULL
                            AND (pt.BANKREF IS NULL OR pt.BANKREF <> t.BANK_LREF))
                     OR (@AGR_ID IS NULL AND pt.IOCODE <> 0 AND pt.BANKREF IS NULL)
                      )
                OPTION (RECOMPILE, MAXDOP 8);

                SET @Total = @Total + @BatchN;
                IF @DEBUG = 1
                BEGIN
                    SET @Msg = N'597 WIRE PAY BANKREF keyset batch=' + CAST(@BatchN AS VARCHAR(20))
                             + N' total=' + CAST(@Total AS VARCHAR(20));
                    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
                END
            END
            SET @N = @N + @Total;
        END

        /* ---- fallback OV_PAY_PT: BANKREF bos — stage + BANK_LREF + keyset ---- */
        IF OBJECT_ID('izgazMGR.dbo.LS_OV_PAY_PT', 'U') IS NOT NULL
           AND OBJECT_ID('dbo.MIG_597_STG_PAY_BANK', 'U') IS NOT NULL
        BEGIN
            TRUNCATE TABLE dbo.MIG_597_STG_PAY_BANK;
            INSERT INTO dbo.MIG_597_STG_PAY_BANK (ABYS_ID, BANK_SMS, SOZLESME)
            SELECT ABYS_ID, BANK_SMS, ABYS_AGREEMENT_ID
            FROM (
                SELECT
                    TRY_CAST(m.ABYS_ID AS BIGINT) AS ABYS_ID,
                    TRY_CAST(m.BANKREF AS INT) AS BANK_SMS,
                    TRY_CAST(m.ABYS_AGREEMENT_ID AS BIGINT) AS ABYS_AGREEMENT_ID,
                    ROW_NUMBER() OVER (
                        PARTITION BY TRY_CAST(m.ABYS_ID AS BIGINT)
                        ORDER BY TRY_CAST(m.BANKREF AS INT)
                    ) AS rn
                FROM izgazMGR.dbo.LS_OV_PAY_PT m WITH (NOLOCK)
                WHERE m.BANKREF IS NOT NULL
                  AND TRY_CAST(m.ABYS_ID AS BIGINT) IS NOT NULL
                  AND TRY_CAST(m.BANKREF AS INT) IS NOT NULL
                  AND (
                        @AGR_ID IS NULL
                     OR (@AGR_ID = -1 AND TRY_CAST(m.ABYS_AGREEMENT_ID AS BIGINT) IS NULL)
                     OR (@AGR_ID > 0 AND TRY_CAST(m.ABYS_AGREEMENT_ID AS BIGINT) = @AGR_ID)
                      )
            ) x
            WHERE x.rn = 1
            OPTION (RECOMPILE, MAXDOP 8);

            UPDATE t
            SET t.BANK_LREF = b.LREF
            FROM dbo.MIG_597_STG_PAY_BANK t
            INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = t.BANK_SMS
            WHERE t.BANK_LREF IS NULL OR t.BANK_LREF <> b.LREF
            OPTION (RECOMPILE, MAXDOP 8);

            SET @Total = 0;
            SET @LastAbys = 0;
            WHILE 1 = 1
            BEGIN
                TRUNCATE TABLE dbo.MIG_597_STG_BATCH_ABYS;

                INSERT INTO dbo.MIG_597_STG_BATCH_ABYS (ABYS_ID)
                SELECT TOP (@BatchSize) t.ABYS_ID
                FROM dbo.MIG_597_STG_PAY_BANK t
                WHERE t.ABYS_ID > @LastAbys
                  AND t.BANK_LREF IS NOT NULL
                ORDER BY t.ABYS_ID
                OPTION (RECOMPILE);

                SET @BatchN = @@ROWCOUNT;
                IF @BatchN = 0 BREAK;

                SELECT @LastAbys = MAX(x.ABYS_ID) FROM dbo.MIG_597_STG_BATCH_ABYS x;

                UPDATE pt
                SET pt.BANKREF = t.BANK_LREF
                FROM dbo.LS_005_01_PAYTRANS pt
                INNER JOIN dbo.MIG_597_STG_BATCH_ABYS x ON x.ABYS_ID = pt.ABYS_ID
                INNER JOIN dbo.MIG_597_STG_PAY_BANK t ON t.ABYS_ID = pt.ABYS_ID
                WHERE pt.BANKREF IS NULL
                  AND t.BANK_LREF IS NOT NULL
                  AND (
                        @AGR_ID IS NULL
                     OR (@AGR_ID = -1 AND (pt.ABYS_AGREEMENT_ID IS NULL OR t.SOZLESME IS NULL))
                     OR (@AGR_ID > 0 AND (pt.ABYS_AGREEMENT_ID = @AGR_ID OR t.SOZLESME = @AGR_ID))
                      )
                OPTION (RECOMPILE, MAXDOP 8);

                SET @Total = @Total + @BatchN;
                IF @DEBUG = 1
                BEGIN
                    SET @Msg = N'597 WIRE OV_PAY BANKREF keyset batch=' + CAST(@BatchN AS VARCHAR(20))
                             + N' total=' + CAST(@Total AS VARCHAR(20));
                    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
                END
            END
            SET @N = @N + @Total;
        END

        /* TYPE=101 TAH — staging BANK_SMS (ifadesiz join) */
        IF OBJECT_ID('izgazMGR.dbo.LS_OV_TAH_INVOICE', 'U') IS NOT NULL
           AND OBJECT_ID('dbo.MIG_597_STG_TAH_BANK', 'U') IS NOT NULL
        BEGIN
            TRUNCATE TABLE dbo.MIG_597_STG_TAH_BANK;

            INSERT INTO dbo.MIG_597_STG_TAH_BANK (INV_LREF, ABYS_ID, BANK_SMS, ABYS_AGREEMENT_ID)
            SELECT INV_LREF, ABYS_ID, BANK_SMS, ABYS_AGREEMENT_ID
            FROM (
                SELECT
                    CAST(t.LREF AS INT) AS INV_LREF,
                    t.ABYS_ID,
                    TRY_CAST(LTRIM(RTRIM(CONVERT(NVARCHAR(20), t.BANKREF))) AS INT) AS BANK_SMS,
                    t.ABYS_AGREEMENT_ID,
                    ROW_NUMBER() OVER (
                        PARTITION BY CAST(t.LREF AS INT)
                        ORDER BY TRY_CAST(LTRIM(RTRIM(CONVERT(NVARCHAR(20), t.BANKREF))) AS INT)
                    ) AS rn
                FROM izgazMGR.dbo.LS_OV_TAH_INVOICE t WITH (NOLOCK)
                WHERE t.BANKREF IS NOT NULL
                  AND t.LREF BETWEEN 1 AND 2147483647
                  AND TRY_CAST(LTRIM(RTRIM(CONVERT(NVARCHAR(20), t.BANKREF))) AS INT) IS NOT NULL
                  AND (
                      @AGR_ID IS NULL
                   OR (@AGR_ID = -1 AND t.ABYS_AGREEMENT_ID IS NULL AND t.ABYS_ACCOUNT_ID IS NOT NULL)
                   OR (@AGR_ID > 0 AND t.ABYS_AGREEMENT_ID = @AGR_ID)
                    )
            ) x
            WHERE x.rn = 1
            OPTION (RECOMPILE, MAXDOP 8);

            /* LS_BANK bir kez — her batch'te tekrar join yok */
            UPDATE t
            SET t.BANK_LREF = b.LREF
            FROM dbo.MIG_597_STG_TAH_BANK t
            INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = t.BANK_SMS
            WHERE t.BANK_LREF IS NULL OR t.BANK_LREF <> b.LREF
            OPTION (RECOMPILE, MAXDOP 8);

            IF @DEBUG = 1
            BEGIN
                SET @Msg = N'597 WIRE TAH_BANK staged=' + CAST((
                        SELECT COUNT_BIG(*) FROM dbo.MIG_597_STG_TAH_BANK WITH (NOLOCK)
                    ) AS VARCHAR(20))
                         + N' bank_lref=' + CAST((
                        SELECT COUNT_BIG(*) FROM dbo.MIG_597_STG_TAH_BANK WITH (NOLOCK)
                        WHERE BANK_LREF IS NOT NULL
                    ) AS VARCHAR(20));
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END

            /* keyset: staging PK gez — mismatch SELECT TOP YOK */
            SET @Total = 0;
            SET @LastLref = 0;
            WHILE 1 = 1
            BEGIN
                TRUNCATE TABLE dbo.MIG_597_STG_BATCH;

                INSERT INTO dbo.MIG_597_STG_BATCH (LREF)
                SELECT TOP (@BatchSize) t.INV_LREF
                FROM dbo.MIG_597_STG_TAH_BANK t
                WHERE t.INV_LREF > @LastLref
                  AND t.BANK_LREF IS NOT NULL
                ORDER BY t.INV_LREF
                OPTION (RECOMPILE);

                SET @BatchN = @@ROWCOUNT;
                IF @BatchN = 0 BREAK;

                SELECT @LastLref = MAX(x.LREF) FROM dbo.MIG_597_STG_BATCH x;

                UPDATE inv
                SET inv.BANKREF = t.BANK_LREF
                FROM dbo.LS_005_01_INVOICE inv
                INNER JOIN dbo.MIG_597_STG_BATCH x ON x.LREF = inv.LREF
                INNER JOIN dbo.MIG_597_STG_TAH_BANK t ON t.INV_LREF = inv.LREF
                WHERE ISNULL(inv.[TYPE], 0) = 101
                  AND t.BANK_LREF IS NOT NULL
                  AND (inv.BANKREF IS NULL OR inv.BANKREF <> t.BANK_LREF)
                OPTION (RECOMPILE, MAXDOP 8);

                SET @Total = @Total + @BatchN;
                IF @DEBUG = 1
                BEGIN
                    SET @Msg = N'597 WIRE TAH BANKREF keyset batch=' + CAST(@BatchN AS VARCHAR(20))
                             + N' total=' + CAST(@Total AS VARCHAR(20))
                             + N' last=' + CAST(@LastLref AS VARCHAR(20));
                    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
                END
            END
            SET @N = @N + @Total;

            /* orphan ABYS (LREF eslesmedi) — dar */
            UPDATE inv
            SET inv.BANKREF = t.BANK_LREF
            FROM dbo.LS_005_01_INVOICE inv
            INNER JOIN dbo.MIG_597_STG_TAH_BANK t ON t.ABYS_ID = inv.ABYS_ID
            WHERE t.ABYS_ID IS NOT NULL
              AND t.BANK_LREF IS NOT NULL
              AND ISNULL(inv.[TYPE], 0) = 101
              AND inv.ABYS_ID IS NOT NULL
              AND inv.BANKREF IS NULL
            OPTION (RECOMPILE, MAXDOP 8);
            SET @N = @N + @@ROWCOUNT;
        END

        /* Yedek: ENERGY SMS BANK_ID → LREF (sadece henuz LREF olmayan) */
        UPDATE inv
        SET inv.BANKREF = b.LREF
        FROM dbo.LS_005_01_INVOICE inv
        INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = inv.BANKREF
        WHERE inv.BANKREF IS NOT NULL
          AND inv.BANKREF <> b.LREF
          AND NOT EXISTS (SELECT 1 FROM dbo.LS_BANK x WITH (NOLOCK) WHERE x.LREF = inv.BANKREF)
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID))
            )
        OPTION (RECOMPILE, MAXDOP 8);
        SET @N = @N + @@ROWCOUNT;

        UPDATE pt
        SET pt.BANKREF = b.LREF
        FROM dbo.LS_005_01_PAYTRANS pt
        INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = pt.BANKREF
        WHERE pt.BANKREF IS NOT NULL
          AND pt.BANKREF <> b.LREF
          AND NOT EXISTS (SELECT 1 FROM dbo.LS_BANK x WITH (NOLOCK) WHERE x.LREF = pt.BANKREF)
          AND (
                @AGR_ID IS NULL
             OR (@AGR_ID = -1 AND pt.ABYS_AGREEMENT_ID IS NULL)
             OR (@AGR_ID > 0 AND pt.ABYS_AGREEMENT_ID = @AGR_ID)
              )
        OPTION (RECOMPILE, MAXDOP 8);
        SET @N = @N + @@ROWCOUNT;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE BANKREF resolve INV+PT rows~' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ============================================================
       6) Borç PT PAID = PAYABLE when CLOSED (batch)
       Picker: PAID eksik VEYA inv'de dolu BANKREF/LPD kopyalanabilir.
       Duz BANKREF/LPD NULL (inv de NULL) → sonsuz dongu (82M+ goruldu) YASAK.
       ============================================================ */
    SET @Total = 0;
    WHILE 1 = 1
    BEGIN
        TRUNCATE TABLE dbo.MIG_597_STG_BATCH;

        INSERT INTO dbo.MIG_597_STG_BATCH (LREF)
        SELECT TOP (@BatchSize) d.LREF
        FROM dbo.LS_005_01_PAYTRANS d
        INNER JOIN dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
            ON inv.LREF = d.INVOICEREF
        WHERE d.IOCODE = 0
          AND ISNULL(inv.CLOSED, 0) = 1
          AND ISNULL(d.CANCELED, 0) = 0
          AND ISNULL(d.CANCELLATIONPAYMENT, 0) = 0
          AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID))
                )
          AND (
                ISNULL(d.PAID, 0) < ISNULL(d.PAYABLETOTAL, 0) - 0.01
             OR (d.BANKREF IS NULL AND inv.BANKREF IS NOT NULL)
             OR (d.LASTPAIDDATE IS NULL AND inv.LASTPAIDDATE IS NOT NULL)
          )
        OPTION (RECOMPILE, MAXDOP 24);

        SET @BatchN = @@ROWCOUNT;
        IF @BatchN = 0 BREAK;

        UPDATE d
        SET d.PAID = d.PAYABLETOTAL,
            d.LASTPAIDDATE = COALESCE(d.LASTPAIDDATE, inv.LASTPAIDDATE),
            d.BANKREF = COALESCE(d.BANKREF, inv.BANKREF),
            d.BANK_RECORD_REF = COALESCE(d.BANK_RECORD_REF, inv.BANK_RECORD_REF)
        FROM dbo.LS_005_01_PAYTRANS d
        INNER JOIN dbo.MIG_597_STG_BATCH b ON b.LREF = d.LREF
        INNER JOIN dbo.LS_005_01_INVOICE inv ON inv.LREF = d.INVOICEREF
        OPTION (RECOMPILE, MAXDOP 24);

        SET @Total = @Total + @BatchN;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE debt PT PAID sync batch=' + CAST(@BatchN AS VARCHAR(20))
                     + N' total=' + CAST(@Total AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 WIRE debt PT PAID/BANK sync=' + CAST(@Total AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    RAISERROR('SP_MIG_597_WIRE OK (v5)', 0, 1) WITH NOWAIT;
END
GO
