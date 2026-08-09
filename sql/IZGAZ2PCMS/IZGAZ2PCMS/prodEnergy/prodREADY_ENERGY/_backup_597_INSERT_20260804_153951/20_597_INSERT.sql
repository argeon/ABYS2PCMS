/* ============================================================
   prodREADY_ENERGY / 20_597_INSERT  (v3 physical staging)
   PAY_PT + TAH_INV + CANCEL_* insert; MAP.ENERGY_LREF doldur
   Tek basina YASAK → 29_597_ALL

   v3:
     - #temp / cursor YOK (tempdb CP1 ≠ energy CP1254)
     - Fiziksel: MIG_597_STG_PAY / _CANCEL / _MAP_OUT + index
     - IDENTITY: MERGE…OUTPUT batch
     - @CLEAN=1 gercek overlay siler (eski davranis)
   Backup: _backup_597_yyyyMMdd_HHmmss/
   ============================================================ */
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---- fiziksel staging ---- */
IF OBJECT_ID('dbo.MIG_597_STG_PAY', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_PAY (
        SRC_KEY              VARCHAR(80)  NOT NULL,
        LREF_HINT            INT          NULL,
        INVOICEREF           INT          NULL,
        CROSSREF_MAIN_LREF   INT          NULL,
        [TYPE]               TINYINT      NULL,
        IOCODE               TINYINT      NULL,
        PAYTYPE              INT          NULL,
        TRANSTYPE            INT          NULL,
        LINETYPE             INT          NULL,
        INST_NR              INT          NULL,
        DATE_                DATETIME     NULL,
        PAYABLETOTAL         FLOAT        NULL,
        CANCELED             BIT          NULL,
        CLIENTREF            INT          NULL,
        ABYS_ID              BIGINT       NULL,
        ABYS_ACCOUNT_ID      BIGINT       NULL,
        ABYS_AGREEMENT_ID    BIGINT       NULL,
        USE_HINT             BIT          NOT NULL CONSTRAINT DF_MIG_597_STG_PAY_UH DEFAULT (0),
        CROSSREF_PT          INT          NULL,
        BANKREF_SMS          INT          NULL,
        BANK_RECORD_REF      NVARCHAR(50) NULL,
        PAID_AMT             FLOAT        NULL,
        CONSTRAINT PK_MIG_597_STG_PAY PRIMARY KEY CLUSTERED (SRC_KEY)
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MIG_597_STG_PAY') AND name = 'IX_MIG_597_STG_PAY_HINT'
)
    CREATE NONCLUSTERED INDEX IX_MIG_597_STG_PAY_HINT
        ON dbo.MIG_597_STG_PAY (USE_HINT)
        INCLUDE (LREF_HINT);
GO

IF OBJECT_ID('dbo.MIG_597_STG_CANCEL', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_CANCEL (
        SRC_KEY              VARCHAR(80)  NOT NULL,
        OV_KIND              VARCHAR(20)  NOT NULL,  /* CANCEL_PAY | CANCEL_REV */
        INVOICEREF           INT          NULL,
        CROSSREF_MAIN_LREF   INT          NULL,
        [TYPE]               TINYINT      NULL,
        IOCODE               TINYINT      NULL,
        PAYTYPE              INT          NULL,
        TRANSTYPE            INT          NULL,
        LINETYPE             INT          NULL,
        DATE_                DATETIME     NULL,
        PAYABLETOTAL         FLOAT        NULL,
        CLIENTREF            INT          NULL,
        ABYS_ID              BIGINT       NULL,
        ABYS_ACCOUNT_ID      BIGINT       NULL,
        ABYS_AGREEMENT_ID    BIGINT       NULL,
        CONSTRAINT PK_MIG_597_STG_CANCEL PRIMARY KEY CLUSTERED (SRC_KEY)
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MIG_597_STG_CANCEL') AND name = 'IX_MIG_597_STG_CANCEL_KIND'
)
    CREATE NONCLUSTERED INDEX IX_MIG_597_STG_CANCEL_KIND
        ON dbo.MIG_597_STG_CANCEL (OV_KIND);
GO

IF OBJECT_ID('dbo.MIG_597_STG_MAP_OUT', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_MAP_OUT (
        ENERGY_LREF INT         NOT NULL,
        SRC_KEY     VARCHAR(80) NOT NULL,
        CONSTRAINT PK_MIG_597_STG_MAP_OUT PRIMARY KEY CLUSTERED (SRC_KEY)
    );
END
GO

/* WIRE fallback xref (21_597_WIRE) */
IF OBJECT_ID('dbo.MIG_597_STG_PAY_XREF', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_PAY_XREF (
        ABYS_ID           BIGINT       NULL,
        LREF_HINT         BIGINT       NULL,
        MAIN_LREF         INT          NULL,
        ABYS_AGREEMENT_ID BIGINT       NULL
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

CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_INSERT
    @AGR_ID    BIGINT = NULL,
    @CLEAN     BIT = 1,
    @DEBUG     BIT = 1,
    @BatchSize INT = 20000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @BatchSize IS NULL OR @BatchSize < 1000 SET @BatchSize = 20000;
    IF @BatchSize > 100000 SET @BatchSize = 100000;

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_PAY_PT', 'U') IS NULL
       OR OBJECT_ID('izgazMGR.dbo.LS_OV_ID_MAP', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR LS_OV_PAY_PT / LS_OV_ID_MAP yok.', 16, 1);
        RETURN;
    END

    IF OBJECT_ID('dbo.MIG_597_STG_PAY', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_597_STG_CANCEL', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_597_STG_MAP_OUT', 'U') IS NULL
    BEGIN
        RAISERROR('MIG_597_STG_* yok — once 20_597_INSERT.sql DDL deploy.', 16, 1);
        RETURN;
    END

    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;
    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;

    DECLARE @Msg NVARCHAR(400), @N INT, @BatchN INT, @Total BIGINT;
    DECLARE @Ts VARCHAR(30) = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    DECLARE @MgrCnt BIGINT, @EnCnt BIGINT;

    /* MAP sync — sadece 597 kind; resume skip */
    SELECT @MgrCnt = COUNT_BIG(*)
    FROM izgazMGR.dbo.LS_OV_ID_MAP WITH (NOLOCK)
    WHERE OV_KIND IN ('PAY_PT','TAH_INV','CANCEL_PAY','CANCEL_REV')
      AND (
          @AGR_ID IS NULL
       OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
       OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
        );

    SELECT @EnCnt = COUNT_BIG(*)
    FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
    WHERE OV_KIND IN ('PAY_PT','TAH_INV','CANCEL_PAY','CANCEL_REV')
      AND (
          @AGR_ID IS NULL
       OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
       OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
        );

    IF @MgrCnt > 0 AND @EnCnt >= @MgrCnt
    BEGIN
        SET @Msg = @Ts + N' | E597 | INFO | MAP sync SKIP (en='
                 + CAST(@EnCnt AS VARCHAR(20)) + N' mgr=' + CAST(@MgrCnt AS VARCHAR(20)) + N')';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
    ELSE
    BEGIN
        MERGE dbo.MIG_OV_ID_MAP AS t
        USING (
            SELECT * FROM izgazMGR.dbo.LS_OV_ID_MAP WITH (NOLOCK)
            WHERE OV_KIND IN ('PAY_PT','TAH_INV','CANCEL_PAY','CANCEL_REV')
              AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
                )
        ) s ON t.SRC_KEY = s.SRC_KEY
        WHEN NOT MATCHED THEN INSERT (
            OV_KIND, SRC_KEY, LREF_HINT, PARENT_SRC_KEY, REF_MAIN_LREF,
            ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID, ABYS_ID_BUSINESS, ENERGY_LREF
        ) VALUES (
            s.OV_KIND, s.SRC_KEY, s.LREF_HINT, s.PARENT_SRC_KEY, s.REF_MAIN_LREF,
            s.ABYS_AGREEMENT_ID, s.ABYS_ACCOUNT_ID, s.ABYS_ID_BUSINESS, NULL
        )
        OPTION (RECOMPILE, MAXDOP 24);

        SET @Ts = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
        SET @Msg = @Ts + N' | E597 | INFO | MAP sync MERGE bitti';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    SET @Ts = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    SET @Msg = @Ts + N' | E597 | INFO | INSERT basladi | AGR='
             + CASE WHEN @AGR_ID IS NULL THEN N'FULL' WHEN @AGR_ID = -1 THEN N'NO_AGR' ELSE CAST(@AGR_ID AS NVARCHAR(30)) END
             + N' Batch=' + CAST(@BatchSize AS VARCHAR(10));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* ---- CLEAN ---- */
    IF @CLEAN = 1
    BEGIN
        DELETE pt
        FROM dbo.LS_005_01_PAYTRANS pt
        INNER JOIN dbo.MIG_OV_ID_MAP m
            ON m.ENERGY_LREF = pt.LREF
           AND m.OV_KIND IN ('PAY_PT', 'CANCEL_PAY', 'CANCEL_REV')
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);
        SET @N = @@ROWCOUNT;

        DELETE pt
        FROM dbo.LS_005_01_PAYTRANS pt
        WHERE ISNULL(pt.IOCODE, 0) <> 0
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND pt.ABYS_AGREEMENT_ID IS NULL AND pt.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND pt.ABYS_AGREEMENT_ID = @AGR_ID)
            )
          AND NOT EXISTS (
                SELECT 1 FROM dbo.MIG_OV_ID_MAP m
                WHERE m.ENERGY_LREF = pt.LREF
                  AND m.OV_KIND IN ('IADE_PT', 'KISMI_PT')
              )
        OPTION (RECOMPILE, MAXDOP 24);
        SET @N = @N + @@ROWCOUNT;

        IF OBJECT_ID('dbo.LS_005_01_INVLINES', 'U') IS NOT NULL
        BEGIN
            DELETE il
            FROM dbo.LS_005_01_INVLINES il
            INNER JOIN dbo.LS_005_01_INVOICE inv ON inv.LREF = il.INVOICEREF
            WHERE ISNULL(inv.IOCODE, 0) = 1
              AND ISNULL(inv.[TYPE], 0) = 101
              AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID))
            )
            OPTION (RECOMPILE, MAXDOP 24);
        END

        DELETE inv
        FROM dbo.LS_005_01_INVOICE inv
        WHERE ISNULL(inv.IOCODE, 0) = 1
          AND ISNULL(inv.[TYPE], 0) = 101
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID))
            )
        OPTION (RECOMPILE, MAXDOP 24);

        UPDATE dbo.MIG_OV_ID_MAP
        SET ENERGY_LREF = NULL
        WHERE OV_KIND IN ('PAY_PT', 'TAH_INV', 'CANCEL_PAY', 'CANCEL_REV')
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);

        UPDATE izgazMGR.dbo.LS_OV_ID_MAP
        SET ENERGY_LREF = NULL
        WHERE OV_KIND IN ('PAY_PT', 'TAH_INV', 'CANCEL_PAY', 'CANCEL_REV')
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 CLEAN PAY/TAH overlay silindi (PT+INV TYPE=101) + MAP sifir';
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ---- TAH_INV — LREF_HINT = PAY.ID (set-based, degismedi) ---- */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_TAH_INVOICE', 'U') IS NOT NULL
    BEGIN
        BEGIN TRY
            SET IDENTITY_INSERT dbo.LS_005_01_INVOICE ON;
            INSERT INTO dbo.LS_005_01_INVOICE (
                LREF, IOCODE, FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF,
                TLTOTAL, CURID, CURTOTAL, EXPLAIN, CANCELED, OWNERREF, OWNERTYPE,
                TAX, DV, GRANDTOTAL, PRINTCOUNT, PAYABLETOTAL, CLOSED,
                FITNO, BN_TYPE, AMOUNT, PERIOD,
                BANKREF, BANK_RECORD_REF, LASTPAIDDATE,
                ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID
            )
            SELECT
                CAST(s.LREF_HINT AS INT),
                CAST(s.IOCODE AS TINYINT),
                LEFT(s.FICHENO, 45),
                energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
                energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DUEDATE AS DATETIME2)),
                CAST(s.[TYPE] AS TINYINT),
                CAST(s.CLIENTREF AS INT),
                CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TLTOTAL)),
                CAST(160 AS SMALLINT),
                CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.CURTOTAL)),
                LEFT(s.EXPLAIN, 250),
                CAST(ISNULL(s.CANCELED, 0) AS BIT),
                CAST(s.OWNERREF AS INT),
                CAST(ISNULL(s.OWNERTYPE, 91) AS TINYINT),
                0, 0,
                CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.GRANDTOTAL)),
                0,
                CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
                CAST(1 AS BIT),
                TRY_CAST(s.FITNO AS BIGINT),
                TRY_CAST(s.BN_TYPE AS INT),
                CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.AMOUNT)),
                s.PERIOD,
                CAST(s.BANKREF AS INT),
                LEFT(s.BANK_RECORD_REF, 50),
                CASE WHEN s.LASTPAIDDATE IS NOT NULL
                     THEN energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.LASTPAIDDATE AS DATETIME2))
                     WHEN ISNULL(s.CANCELED, 0) = 0
                     THEN energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2))
                     ELSE NULL END,
                s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID
            FROM izgazMGR.dbo.LS_OV_TAH_INVOICE s WITH (NOLOCK)
            WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
              AND s.LREF_HINT BETWEEN 1 AND 2147483647
              AND NOT EXISTS (
                    SELECT 1 FROM dbo.LS_005_01_INVOICE t WHERE t.LREF = CAST(s.LREF_HINT AS INT)
                  )
            OPTION (RECOMPILE, MAXDOP 24);
            SET @N = @@ROWCOUNT;
        END TRY
        BEGIN CATCH
            SET @N = 0;
            SET @Msg = N'597 TAH_INV INSERT FAIL: ' + ERROR_MESSAGE();
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;
            RAISERROR('%s', 16, 1, @Msg);
            RETURN;
        END CATCH

        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;

        UPDATE m SET m.ENERGY_LREF = CAST(s.LREF_HINT AS INT)
        FROM dbo.MIG_OV_ID_MAP m
        INNER JOIN izgazMGR.dbo.LS_OV_TAH_INVOICE s ON s.SRC_KEY = m.SRC_KEY
        INNER JOIN dbo.LS_005_01_INVOICE inv
            ON inv.LREF = CAST(s.LREF_HINT AS INT)
           AND ISNULL(inv.[TYPE], 0) = 101
        WHERE m.OV_KIND = 'TAH_INV' AND m.ENERGY_LREF IS NULL
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);

        UPDATE mgr
        SET mgr.ENERGY_LREF = m.ENERGY_LREF
        FROM izgazMGR.dbo.LS_OV_ID_MAP mgr
        INNER JOIN dbo.MIG_OV_ID_MAP m ON m.SRC_KEY = mgr.SRC_KEY
        WHERE m.OV_KIND = 'TAH_INV' AND m.ENERGY_LREF IS NOT NULL
          AND mgr.ENERGY_LREF IS NULL
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 INSERT TAH_INV=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ---- PAY_PT staging (physical) ---- */
    TRUNCATE TABLE dbo.MIG_597_STG_PAY;
    TRUNCATE TABLE dbo.MIG_597_STG_MAP_OUT;

    INSERT INTO dbo.MIG_597_STG_PAY (
        SRC_KEY, LREF_HINT, INVOICEREF, CROSSREF_MAIN_LREF, [TYPE], IOCODE,
        PAYTYPE, TRANSTYPE, LINETYPE, INST_NR, DATE_, PAYABLETOTAL, CANCELED, CLIENTREF,
        ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, USE_HINT, CROSSREF_PT,
        BANKREF_SMS, BANK_RECORD_REF, PAID_AMT
    )
    SELECT
        CAST(s.SRC_KEY AS VARCHAR(80)),
        CAST(s.LREF_HINT AS INT),
        CAST(s.INVOICEREF AS INT),
        CAST(s.CROSSREF_MAIN_LREF AS INT),
        CAST(s.[TYPE] AS TINYINT),
        CAST(s.IOCODE AS TINYINT),
        CAST(s.PAYTYPE AS INT),
        CAST(s.TRANSTYPE AS INT),
        CAST(s.LINETYPE AS INT),
        CAST(ISNULL(s.INST_NR, 0) AS INT),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
        CAST(ISNULL(s.CANCELED, 0) AS BIT),
        CAST(s.CLIENTREF AS INT),
        s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID,
        CAST(CASE
            WHEN s.LREF_HINT BETWEEN 1 AND 2147483647
             AND NOT EXISTS (
                    SELECT 1 FROM dbo.LS_005_01_PAYTRANS t
                    WHERE t.LREF = CAST(s.LREF_HINT AS INT)
                  )
            THEN 1 ELSE 0 END AS BIT),
        CAST((
            SELECT TOP (1) d.LREF
            FROM dbo.LS_005_01_PAYTRANS d WITH (NOLOCK)
            WHERE d.INVOICEREF = CAST(s.CROSSREF_MAIN_LREF AS INT)
              AND ISNULL(d.IOCODE, 0) = 0
              AND ISNULL(d.CANCELED, 0) = 0
              AND ISNULL(d.CANCELLATIONPAYMENT, 0) = 0
            ORDER BY d.LREF
        ) AS INT),
        CAST(s.BANKREF AS INT),
        CAST(s.BANK_RECORD_REF AS NVARCHAR(50)),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), ISNULL(s.PAID, 0)))
    FROM izgazMGR.dbo.LS_OV_PAY_PT s WITH (NOLOCK)
    WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
      AND NOT EXISTS (
            SELECT 1 FROM dbo.MIG_OV_ID_MAP m
            WHERE m.SRC_KEY = s.SRC_KEY
              AND m.ENERGY_LREF IS NOT NULL
          )
    OPTION (RECOMPILE, MAXDOP 24);

    SET @N = (SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY);
    SET @Msg = N'597 INSERT PAY_PT pending=' + CAST(@N AS VARCHAR(20))
             + N' hint=' + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY WHERE USE_HINT=1) AS VARCHAR(20))
             + N' identity=' + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY WHERE USE_HINT=0) AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* hint path */
    BEGIN TRY
        SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS ON;
        INSERT INTO dbo.LS_005_01_PAYTRANS (
            LREF, INVOICEREF, [TYPE], IOCODE, CROSSREF, PAYTYPE, TRANSTYPE, LINETYPE, INST_NR,
            DATE_, PAYABLETOTAL, PAID, CANCELED, CLIENTREF, CLIENT_TYPE,
            ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF,
            BANKREF, BANK_RECORD_REF, LASTPAIDDATE
        )
        SELECT
            p.LREF_HINT, p.INVOICEREF, p.[TYPE], p.IOCODE,
            COALESCE(p.CROSSREF_PT, p.CROSSREF_MAIN_LREF),
            p.PAYTYPE, p.TRANSTYPE, p.LINETYPE, p.INST_NR,
            p.DATE_, p.PAYABLETOTAL,
            CASE WHEN ISNULL(p.CANCELED, 0) = 0 THEN p.PAID_AMT ELSE 0 END,
            p.CANCELED, p.CLIENTREF, CAST(91 AS TINYINT),
            p.ABYS_ID, p.ABYS_ACCOUNT_ID, p.ABYS_AGREEMENT_ID, p.INVOICEREF,
            p.BANKREF_SMS, p.BANK_RECORD_REF,
            CASE WHEN ISNULL(p.CANCELED, 0) = 0 THEN p.DATE_ ELSE NULL END
        FROM dbo.MIG_597_STG_PAY p
        WHERE p.USE_HINT = 1
        OPTION (RECOMPILE, MAXDOP 24);
        SET @N = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        SET @N = 0;
        SET @Msg = N'597 PAY hint INSERT FAIL: ' + ERROR_MESSAGE();
        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;
        RAISERROR('%s', 16, 1, @Msg);
        RETURN;
    END CATCH
    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;

    UPDATE m SET m.ENERGY_LREF = p.LREF_HINT
    FROM dbo.MIG_OV_ID_MAP m
    INNER JOIN dbo.MIG_597_STG_PAY p ON p.SRC_KEY = m.SRC_KEY
    INNER JOIN dbo.LS_005_01_PAYTRANS pt
        ON pt.LREF = p.LREF_HINT
       AND ISNULL(pt.IOCODE, 0) <> 0
    WHERE p.USE_HINT = 1 AND m.ENERGY_LREF IS NULL
    OPTION (RECOMPILE, MAXDOP 24);

    UPDATE mgr
    SET mgr.ENERGY_LREF = m.ENERGY_LREF
    FROM izgazMGR.dbo.LS_OV_ID_MAP mgr
    INNER JOIN dbo.MIG_OV_ID_MAP m ON m.SRC_KEY = mgr.SRC_KEY
    INNER JOIN dbo.MIG_597_STG_PAY p ON p.SRC_KEY = m.SRC_KEY AND p.USE_HINT = 1
    WHERE m.OV_KIND = 'PAY_PT' AND m.ENERGY_LREF IS NOT NULL AND mgr.ENERGY_LREF IS NULL
    OPTION (RECOMPILE, MAXDOP 24);

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 INSERT PAY_PT(hint)=' + CAST(@N AS VARCHAR(20))
                 + N' collide→identity=' + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY WHERE USE_HINT=0 AND LREF_HINT IS NOT NULL) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    DELETE FROM dbo.MIG_597_STG_PAY WHERE USE_HINT = 1;

    /* identity path — MERGE OUTPUT batch */
    SET @Total = 0;
    WHILE EXISTS (SELECT 1 FROM dbo.MIG_597_STG_PAY WHERE USE_HINT = 0)
    BEGIN
        TRUNCATE TABLE dbo.MIG_597_STG_MAP_OUT;

        BEGIN TRY
            BEGIN TRAN;
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;

            MERGE dbo.LS_005_01_PAYTRANS WITH (HOLDLOCK) AS t
            USING (
                SELECT TOP (@BatchSize) p.*
                FROM dbo.MIG_597_STG_PAY p
                WHERE p.USE_HINT = 0
                  AND NOT EXISTS (
                        SELECT 1 FROM dbo.MIG_OV_ID_MAP m
                        WHERE m.SRC_KEY = p.SRC_KEY AND m.ENERGY_LREF IS NOT NULL
                      )
                ORDER BY p.SRC_KEY
            ) AS s
            ON 1 = 0
            WHEN NOT MATCHED THEN INSERT (
                INVOICEREF, [TYPE], IOCODE, CROSSREF, PAYTYPE, TRANSTYPE, LINETYPE, INST_NR,
                DATE_, PAYABLETOTAL, PAID, CANCELED, CLIENTREF, CLIENT_TYPE,
                ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF,
                BANKREF, BANK_RECORD_REF, LASTPAIDDATE
            ) VALUES (
                s.INVOICEREF, s.[TYPE], s.IOCODE,
                COALESCE(s.CROSSREF_PT, s.CROSSREF_MAIN_LREF),
                s.PAYTYPE, s.TRANSTYPE, s.LINETYPE, s.INST_NR,
                s.DATE_, s.PAYABLETOTAL,
                CASE WHEN ISNULL(s.CANCELED, 0) = 0 THEN s.PAID_AMT ELSE 0 END,
                s.CANCELED, s.CLIENTREF, CAST(91 AS TINYINT),
                s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID, s.INVOICEREF,
                s.BANKREF_SMS, s.BANK_RECORD_REF,
                CASE WHEN ISNULL(s.CANCELED, 0) = 0 THEN s.DATE_ ELSE NULL END
            )
            OUTPUT inserted.LREF, s.SRC_KEY INTO dbo.MIG_597_STG_MAP_OUT (ENERGY_LREF, SRC_KEY)
            OPTION (RECOMPILE);

            SET @BatchN = @@ROWCOUNT;

            UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
            FROM dbo.MIG_OV_ID_MAP m
            INNER JOIN dbo.MIG_597_STG_MAP_OUT o ON o.SRC_KEY = m.SRC_KEY
            WHERE m.ENERGY_LREF IS NULL;

            UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
            FROM izgazMGR.dbo.LS_OV_ID_MAP m
            INNER JOIN dbo.MIG_597_STG_MAP_OUT o ON o.SRC_KEY = m.SRC_KEY
            WHERE m.ENERGY_LREF IS NULL;

            DELETE p
            FROM dbo.MIG_597_STG_PAY p
            INNER JOIN dbo.MIG_597_STG_MAP_OUT o ON o.SRC_KEY = p.SRC_KEY;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRAN;
            THROW;
        END CATCH;

        SET @Total += @BatchN;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 PAY_PT identity batch +' + CAST(@BatchN AS VARCHAR(20))
                     + N' total=' + CAST(@Total AS VARCHAR(20))
                     + N' left=' + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY) AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
        IF @BatchN = 0 BREAK;
    END

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 INSERT PAY_PT(identity)=' + CAST(@Total AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* ---- CANCEL staging + MERGE OUTPUT ---- */
    TRUNCATE TABLE dbo.MIG_597_STG_CANCEL;
    TRUNCATE TABLE dbo.MIG_597_STG_MAP_OUT;

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_CANCEL_PAY', 'U') IS NOT NULL
    BEGIN
        INSERT INTO dbo.MIG_597_STG_CANCEL (
            SRC_KEY, OV_KIND, INVOICEREF, CROSSREF_MAIN_LREF, [TYPE], IOCODE,
            PAYTYPE, TRANSTYPE, LINETYPE, DATE_, PAYABLETOTAL, CLIENTREF,
            ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID
        )
        SELECT
            CAST(s.SRC_KEY AS VARCHAR(80)), 'CANCEL_PAY', NULL,
            CAST(s.CROSSREF_MAIN_LREF AS INT),
            CAST(s.[TYPE] AS TINYINT), CAST(s.IOCODE AS TINYINT),
            CAST(s.PAYTYPE AS INT), CAST(s.TRANSTYPE AS INT), CAST(s.LINETYPE AS INT),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            CAST(s.CLIENTREF AS INT),
            s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID
        FROM izgazMGR.dbo.LS_OV_CANCEL_PAY s WITH (NOLOCK)
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
          AND NOT EXISTS (
                SELECT 1 FROM dbo.MIG_OV_ID_MAP m
                WHERE m.SRC_KEY = s.SRC_KEY AND m.ENERGY_LREF IS NOT NULL
              );
    END

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_CANCEL_REV', 'U') IS NOT NULL
    BEGIN
        INSERT INTO dbo.MIG_597_STG_CANCEL (
            SRC_KEY, OV_KIND, INVOICEREF, CROSSREF_MAIN_LREF, [TYPE], IOCODE,
            PAYTYPE, TRANSTYPE, LINETYPE, DATE_, PAYABLETOTAL, CLIENTREF,
            ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID
        )
        SELECT
            CAST(s.SRC_KEY AS VARCHAR(80)), 'CANCEL_REV',
            CAST(s.INVOICEREF AS INT),
            CAST(s.CROSSREF_MAIN_LREF AS INT),
            CAST(s.[TYPE] AS TINYINT), CAST(s.IOCODE AS TINYINT),
            CAST(s.PAYTYPE AS INT), CAST(s.TRANSTYPE AS INT), CAST(s.LINETYPE AS INT),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            CAST(s.CLIENTREF AS INT),
            s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID
        FROM izgazMGR.dbo.LS_OV_CANCEL_REV s WITH (NOLOCK)
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
          AND NOT EXISTS (
                SELECT 1 FROM dbo.MIG_OV_ID_MAP m
                WHERE m.SRC_KEY = s.SRC_KEY AND m.ENERGY_LREF IS NOT NULL
              );
    END

    SET @Total = 0;
    WHILE EXISTS (SELECT 1 FROM dbo.MIG_597_STG_CANCEL)
    BEGIN
        TRUNCATE TABLE dbo.MIG_597_STG_MAP_OUT;

        BEGIN TRY
            BEGIN TRAN;
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;

            MERGE dbo.LS_005_01_PAYTRANS WITH (HOLDLOCK) AS t
            USING (
                SELECT TOP (@BatchSize) c.*
                FROM dbo.MIG_597_STG_CANCEL c
                ORDER BY c.SRC_KEY
            ) AS s
            ON 1 = 0
            WHEN NOT MATCHED THEN INSERT (
                INVOICEREF, [TYPE], IOCODE, CROSSREF, PAYTYPE, TRANSTYPE, LINETYPE, INST_NR,
                DATE_, PAYABLETOTAL, PAID, CANCELED, CANCELLATIONPAYMENT, CLIENTREF, CLIENT_TYPE,
                ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID
            ) VALUES (
                s.INVOICEREF, s.[TYPE], s.IOCODE, s.CROSSREF_MAIN_LREF,
                s.PAYTYPE, s.TRANSTYPE, s.LINETYPE, 0,
                s.DATE_, s.PAYABLETOTAL, 0, CAST(0 AS BIT), CAST(1 AS INT),
                s.CLIENTREF, CAST(91 AS TINYINT),
                s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID
            )
            OUTPUT inserted.LREF, s.SRC_KEY INTO dbo.MIG_597_STG_MAP_OUT (ENERGY_LREF, SRC_KEY)
            OPTION (RECOMPILE);

            SET @BatchN = @@ROWCOUNT;

            UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
            FROM dbo.MIG_OV_ID_MAP m
            INNER JOIN dbo.MIG_597_STG_MAP_OUT o ON o.SRC_KEY = m.SRC_KEY
            WHERE m.ENERGY_LREF IS NULL;

            UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
            FROM izgazMGR.dbo.LS_OV_ID_MAP m
            INNER JOIN dbo.MIG_597_STG_MAP_OUT o ON o.SRC_KEY = m.SRC_KEY
            WHERE m.ENERGY_LREF IS NULL;

            DELETE c
            FROM dbo.MIG_597_STG_CANCEL c
            INNER JOIN dbo.MIG_597_STG_MAP_OUT o ON o.SRC_KEY = c.SRC_KEY;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRAN;
            THROW;
        END CATCH;

        SET @Total += @BatchN;
        IF @DEBUG = 1 AND @BatchN > 0
        BEGIN
            SET @Msg = N'597 CANCEL identity batch +' + CAST(@BatchN AS VARCHAR(20))
                     + N' total=' + CAST(@Total AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
        IF @BatchN = 0 BREAK;
    END

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 INSERT CANCEL_* identity=' + CAST(@Total AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* DEBT_PAID_UPD */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_DEBT_PAID_UPD', 'U') IS NOT NULL
    BEGIN
        UPDATE pt
        SET pt.PAID = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), d.PAID_AMT))
        FROM dbo.LS_005_01_PAYTRANS pt
        INNER JOIN izgazMGR.dbo.LS_OV_DEBT_PAID_UPD d WITH (NOLOCK)
            ON pt.INVOICEREF = CAST(d.MAIN_LREF AS INT)
           AND ISNULL(pt.IOCODE, 0) = 0
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND d.ABYS_AGREEMENT_ID IS NULL)
           OR (@AGR_ID > 0 AND d.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 INSERT DEBT_PAID_UPD=' + CAST(@@ROWCOUNT AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;
    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;

    SET @Ts = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    SET @Msg = @Ts + N' | E597 | INFO | INSERT bitti — sonraki WIRE zorunlu';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END
GO
