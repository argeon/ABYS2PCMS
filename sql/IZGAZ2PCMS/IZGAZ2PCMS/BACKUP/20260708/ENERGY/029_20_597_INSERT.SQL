/* ============================================================
   prodREADY_ENERGY / 20_597_INSERT  (v5)
   PAY_PT + TAH_INV + CANCEL_* insert; MAP.ENERGY_LREF doldur
   Tek basina YASAK → 29_597_ALL

   v5c (perf hard rules — geri donus YASAK):
     - Hot loop'ta MGR LS_OV_ID_MAP UPDATE YOK (TAH/PAY/CANCEL); 20a offline
     - FULL: INV + PAYTRANS NCIX DISABLE zorunlu (PREPARE); acikken INSERT yok
     - Scalar FN_SAFE_SMALLDT_DEP hot path YOK (inline CASE)
     - #temp YOK | IMPLICIT_TRANSACTIONS OFF | dis BEGIN TRAN sadece MERGE OUTPUT
     - Filtered IX: IOCODE = 0 (ISNULL(IOCODE,0) YASAK debt lookup)
     - PAY hint: MERGE OUTPUT → STG_MAP_OUT (20260804 identity kalibi; PT JOIN YOK)
   v5b:
     - TAH_INV: mega MIG_597_STG_TAH_KEYS YOK → keyset SRC_KEY
     - TAH INSERT inline tarih; EN MAP only
   v5:
     - CANCEL_REV: sadece AFL acik borc varsa (FATURAID=ABYS_ACCOUNT_ID,
       BALANCE>0.02). AFL yok/kapali → REV insert YOK (sahte 2x + OPEN engeli)
   v4:
     - CLEAN MAP / TAH_INV / PAY DEBT_LOOKUP / IDENTITY MERGE
     - #temp YOK | dis BEGIN TRAN YASAK
   Backup: _backup_597_INSERT_yyyyMMdd_HHmmss/
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
        XTYPE                INT          NULL,
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
        LOADED               BIT          NOT NULL CONSTRAINT DF_MIG_597_STG_PAY_LD DEFAULT (0),
        CROSSREF_PT          INT          NULL,
        BANKREF_SMS          INT          NULL,
        BANK_RECORD_REF      NVARCHAR(50) NULL,
        PAID_AMT             FLOAT        NULL,
        CONSTRAINT PK_MIG_597_STG_PAY PRIMARY KEY CLUSTERED (SRC_KEY)
    );
END
GO

IF COL_LENGTH('dbo.MIG_597_STG_PAY', 'LOADED') IS NULL
BEGIN
    ALTER TABLE dbo.MIG_597_STG_PAY ADD LOADED BIT NOT NULL
        CONSTRAINT DF_MIG_597_STG_PAY_LD DEFAULT (0);
END
GO

IF COL_LENGTH('dbo.MIG_597_STG_PAY', 'XTYPE') IS NULL
    ALTER TABLE dbo.MIG_597_STG_PAY ADD XTYPE INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MIG_597_STG_PAY') AND name = 'IX_MIG_597_STG_PAY_HINT'
)
    CREATE NONCLUSTERED INDEX IX_MIG_597_STG_PAY_HINT
        ON dbo.MIG_597_STG_PAY (USE_HINT, LOADED)
        INCLUDE (LREF_HINT, SRC_KEY);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MIG_597_STG_PAY') AND name = 'IX_MIG_597_STG_PAY_LOAD'
)
    CREATE NONCLUSTERED INDEX IX_MIG_597_STG_PAY_LOAD
        ON dbo.MIG_597_STG_PAY (LOADED, USE_HINT, SRC_KEY);
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

/* TAH batch keys */
IF OBJECT_ID('dbo.MIG_597_STG_TAH_KEYS', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_TAH_KEYS (
        LREF    INT         NOT NULL,
        SRC_KEY VARCHAR(80) NOT NULL,
        CONSTRAINT PK_MIG_597_STG_TAH_KEYS PRIMARY KEY CLUSTERED (LREF)
    );
END
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MIG_597_STG_TAH_KEYS') AND name = 'IX_MIG_597_STG_TAH_KEYS_SRC'
)
    CREATE NONCLUSTERED INDEX IX_MIG_597_STG_TAH_KEYS_SRC
        ON dbo.MIG_597_STG_TAH_KEYS (SRC_KEY);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MIG_597_STG_PAY') AND name = 'IX_MIG_597_STG_PAY_HINT_SRC'
)
    CREATE NONCLUSTERED INDEX IX_MIG_597_STG_PAY_HINT_SRC
        ON dbo.MIG_597_STG_PAY (USE_HINT, SRC_KEY)
        INCLUDE (LREF_HINT);
GO

/* PAY/TAH hint batch SRC_KEY set */
IF OBJECT_ID('dbo.MIG_597_STG_SRC_BATCH', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_597_STG_SRC_BATCH (
        SRC_KEY VARCHAR(80) NOT NULL,
        CONSTRAINT PK_MIG_597_STG_SRC_BATCH PRIMARY KEY CLUSTERED (SRC_KEY)
    );
END
GO

/* DEBT_LOOKUP — WIRE ile paylasilir; INSERT staging join */
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

CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_INSERT
    @AGR_ID    BIGINT = NULL,
    @CLEAN     BIT = 1,
    @DEBUG     BIT = 1,
    @BatchSize INT = 20000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET IMPLICIT_TRANSACTIONS OFF;

    IF @BatchSize IS NULL OR @BatchSize < 1000 SET @BatchSize = 20000;
    IF @BatchSize > 250000 SET @BatchSize = 250000;

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_PAY_PT', 'U') IS NULL
       OR OBJECT_ID('izgazMGR.dbo.LS_OV_ID_MAP', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR LS_OV_PAY_PT / LS_OV_ID_MAP yok.', 16, 1);
        RETURN;
    END

    IF OBJECT_ID('dbo.MIG_597_STG_PAY', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_597_STG_CANCEL', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_597_STG_MAP_OUT', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_597_STG_TAH_KEYS', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_597_STG_SRC_BATCH', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_597_STG_DEBT_LOOKUP', 'U') IS NULL
    BEGIN
        RAISERROR('MIG_597_STG_* yok — once 20_597_INSERT.sql DDL deploy.', 16, 1);
        RETURN;
    END

    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;
    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;

    DECLARE @Msg NVARCHAR(400), @N INT, @BatchN INT, @Total BIGINT;
    DECLARE @Ts VARCHAR(30) = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    DECLARE @MgrCnt BIGINT, @EnCnt BIGINT;
    DECLARE @PayLastKey VARCHAR(80);
    DECLARE @TahLastKey VARCHAR(80);
    DECLARE @StgResume BIT;

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

        /* MAP null — sadece dolu satir + batch (NULL→NULL YOK) */
        SET @Total = 0;
        SELECT @EnCnt = COUNT_BIG(*)
        FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
        WHERE OV_KIND IN ('PAY_PT', 'TAH_INV', 'CANCEL_PAY', 'CANCEL_REV')
          AND ENERGY_LREF IS NOT NULL
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
            );
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 CLEAN EN MAP filled→null target=' + CAST(@EnCnt AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        WHILE 1 = 1
        BEGIN
            UPDATE TOP (@BatchSize) m
            SET m.ENERGY_LREF = NULL
            FROM dbo.MIG_OV_ID_MAP m
            WHERE m.OV_KIND IN ('PAY_PT', 'TAH_INV', 'CANCEL_PAY', 'CANCEL_REV')
              AND m.ENERGY_LREF IS NOT NULL
              AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
                )
            OPTION (RECOMPILE, MAXDOP 24);
            SET @BatchN = @@ROWCOUNT;
            SET @Total = @Total + @BatchN;
            IF @BatchN = 0 BREAK;
            IF @DEBUG = 1
            BEGIN
                SET @Msg = N'597 CLEAN EN MAP null batch=' + CAST(@BatchN AS VARCHAR(20))
                         + N' total=' + CAST(@Total AS VARCHAR(20));
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END
        END

        /* MGR MAP null SKIP — cross-DB CLEAN yavas; 20a / offline sonra */
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 CLEAN PAY/TAH overlay silindi + EN MAP sifir | MGR MAP SKIP';
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ---- TAH_INV — keyset SRC_KEY + IDENTITY_INSERT (mega STG_TAH_KEYS YOK) ----
       Skip: MAP TAH_INV ENERGY_LREF dolu VEYA INV LREF=hint var.
       Onkosul: izgazMGR.UX_MIG_LS_OV_TAH_INVOICE_SRC (00f).
       FULL: INVOICE NCIX disable (15 index acik = 66M INSERT olum) → sonra 572 POST. */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_TAH_INVOICE', 'U') IS NOT NULL
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM izgazMGR.sys.indexes
            WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_OV_TAH_INVOICE')
              AND name = N'UX_MIG_LS_OV_TAH_INVOICE_SRC'
        )
        BEGIN
            RAISERROR('UX_MIG_LS_OV_TAH_INVOICE_SRC yok — once 00f_597_v4_indexes.sql (MGR)', 16, 1);
            RETURN;
        END

        IF @AGR_ID IS NULL
           AND OBJECT_ID('dbo.SP_MIG_INVOICE_PREPARE_LOAD', 'P') IS NOT NULL
           AND EXISTS (
                SELECT 1 FROM sys.indexes i
                WHERE i.object_id = OBJECT_ID('dbo.LS_005_01_INVOICE')
                  AND i.type_desc = N'NONCLUSTERED'
                  AND i.is_disabled = 0
           )
        BEGIN
            IF @DEBUG = 1
                RAISERROR('597 TAH: SP_MIG_INVOICE_PREPARE_LOAD (NCIX DISABLE)', 0, 1) WITH NOWAIT;
            EXEC dbo.SP_MIG_INVOICE_PREPARE_LOAD @DEBUG = @DEBUG;
            IF EXISTS (
                SELECT 1 FROM sys.indexes i
                WHERE i.object_id = OBJECT_ID('dbo.LS_005_01_INVOICE')
                  AND i.type_desc = N'NONCLUSTERED'
                  AND i.is_disabled = 0
            )
            BEGIN
                RAISERROR('597 TAH: INVOICE NCIX hala acik — 20b_INVOICE_NCIX_DISABLE.sql', 16, 1);
                RETURN;
            END
        END

        SET @TahLastKey = N'';
        SET @Total = 0;

        IF @DEBUG = 1
            RAISERROR('597 TAH_INV keyset START (no STG_TAH_KEYS mega fill)', 0, 1) WITH NOWAIT;

        BEGIN TRY
            WHILE 1 = 1
            BEGIN
                TRUNCATE TABLE dbo.MIG_597_STG_SRC_BATCH;

                /* KEYSET: TOP N SRC_KEY > last — INV anti-join sadece adaylarda (66M staging YOK) */
                INSERT INTO dbo.MIG_597_STG_SRC_BATCH (SRC_KEY)
                SELECT TOP (@BatchSize) s.SRC_KEY
                FROM izgazMGR.dbo.LS_OV_TAH_INVOICE s WITH (NOLOCK)
                WHERE s.SRC_KEY > @TahLastKey
                  AND s.LREF_HINT BETWEEN 1 AND 2147483647
                  AND (
                      @AGR_ID IS NULL
                   OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
                   OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
                    )
                  AND NOT EXISTS (
                        SELECT 1 FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
                        WHERE m.SRC_KEY = s.SRC_KEY
                          AND m.OV_KIND = 'TAH_INV'
                          AND m.ENERGY_LREF IS NOT NULL
                      )
                  AND NOT EXISTS (
                        SELECT 1 FROM dbo.LS_005_01_INVOICE t WITH (NOLOCK)
                        WHERE t.LREF = CAST(s.LREF_HINT AS INT)
                      )
                ORDER BY s.SRC_KEY
                OPTION (RECOMPILE, MAXDOP 8);

                SET @BatchN = @@ROWCOUNT;
                IF @BatchN = 0 BREAK;

                SELECT @TahLastKey = MAX(SRC_KEY) FROM dbo.MIG_597_STG_SRC_BATCH;

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
                    /* DATE_ zaten datetime2 — CROSS APPLY/JOIN yok; FN ile ayni aralik */
                    CASE WHEN s.DATE_ < CAST('1900-01-01' AS DATETIME2)
                              OR s.DATE_ > CAST('2079-06-06 23:59:00' AS DATETIME2)
                         THEN CAST(NULL AS SMALLDATETIME) ELSE CAST(s.DATE_ AS SMALLDATETIME) END,
                    CASE WHEN s.DUEDATE < CAST('1900-01-01' AS DATETIME2)
                              OR s.DUEDATE > CAST('2079-06-06 23:59:00' AS DATETIME2)
                         THEN CAST(NULL AS SMALLDATETIME) ELSE CAST(s.DUEDATE AS SMALLDATETIME) END,
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
                    CASE
                        WHEN s.LASTPAIDDATE IS NOT NULL
                             AND s.LASTPAIDDATE >= CAST('1900-01-01' AS DATETIME2)
                             AND s.LASTPAIDDATE <= CAST('2079-06-06 23:59:00' AS DATETIME2)
                            THEN CAST(s.LASTPAIDDATE AS SMALLDATETIME)
                        WHEN (s.CANCELED IS NULL OR s.CANCELED = 0)
                             AND s.DATE_ >= CAST('1900-01-01' AS DATETIME2)
                             AND s.DATE_ <= CAST('2079-06-06 23:59:00' AS DATETIME2)
                            THEN CAST(s.DATE_ AS SMALLDATETIME)
                        ELSE NULL
                    END,
                    s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID
                FROM izgazMGR.dbo.LS_OV_TAH_INVOICE s WITH (NOLOCK)
                INNER JOIN dbo.MIG_597_STG_SRC_BATCH b ON b.SRC_KEY = s.SRC_KEY
                OPTION (RECOMPILE, MAXDOP 8);

                SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF;

                /* EN MAP only — MGR cross-DB UPDATE batch'te YASAK (20a offline).
                   SRC_KEY = TAH_INV|<LREF_HINT> → SUBSTRING; TAH join yok. */
                UPDATE m
                SET m.ENERGY_LREF = TRY_CAST(SUBSTRING(m.SRC_KEY, CHARINDEX('|', m.SRC_KEY) + 1, 20) AS INT)
                FROM dbo.MIG_OV_ID_MAP m
                INNER JOIN dbo.MIG_597_STG_SRC_BATCH b ON b.SRC_KEY = m.SRC_KEY
                WHERE m.OV_KIND = 'TAH_INV'
                  AND m.ENERGY_LREF IS NULL
                OPTION (RECOMPILE, MAXDOP 8);

                SET @Total = @Total + @BatchN;
                IF @DEBUG = 1
                BEGIN
                    SET @Msg = N'597 TAH_INV keyset +' + CAST(@BatchN AS VARCHAR(20))
                             + N' total=' + CAST(@Total AS VARCHAR(20))
                             + N' lastKey=' + @TahLastKey;
                    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
                END
            END
        END TRY
        BEGIN CATCH
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;
            SET @Msg = N'597 TAH_INV INSERT FAIL: ' + ERROR_MESSAGE();
            RAISERROR('%s', 16, 1, @Msg);
            RETURN;
        END CATCH

        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 INSERT TAH_INV=' + CAST(@Total AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        /* Resume: INV zaten var, MAP null → hızlı fill (INV join YOK; 500k; MGR sync sonda) */
        SET @Total = 0;
        WHILE 1 = 1
        BEGIN
            UPDATE TOP (500000) m
            SET m.ENERGY_LREF = CAST(s.LREF_HINT AS INT)
            FROM dbo.MIG_OV_ID_MAP m
            INNER JOIN izgazMGR.dbo.LS_OV_TAH_INVOICE s WITH (NOLOCK)
                ON s.SRC_KEY = m.SRC_KEY
            WHERE m.OV_KIND = 'TAH_INV'
              AND m.ENERGY_LREF IS NULL
              AND s.LREF_HINT BETWEEN 1 AND 2147483647
              AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
                )
            OPTION (RECOMPILE, MAXDOP 24);

            SET @BatchN = @@ROWCOUNT;
            IF @BatchN = 0 BREAK;

            SET @Total = @Total + @BatchN;
            IF @DEBUG = 1
            BEGIN
                SET @Msg = N'597 TAH MAP resume backfill +' + CAST(@BatchN AS VARCHAR(20))
                         + N' total=' + CAST(@Total AS VARCHAR(20));
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END
        END
        IF @DEBUG = 1 AND @Total > 0
        BEGIN
            SET @Msg = N'597 TAH MAP resume backfill EN done=' + CAST(@Total AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        /* MGR MAP sync: resume kritik path degil — 20a ile sonraya birak.
           EN MAP doluysa PAY/WIRE icin yeterli; saatlik cross-DB sync'i atla. */
        IF @DEBUG = 1
            RAISERROR('597 TAH MAP resume MGR sync SKIP (use 20a offline)', 0, 1) WITH NOWAIT;
    END
    /* ---- PAY_PT: DEBT_LOOKUP + staging ----
       STG resume: STG_PAY+DEBT doluysa TRUNCATE yok; keyset MAX(SRC_KEY)'den devam */
    SET @StgResume = CASE
        WHEN EXISTS (SELECT 1 FROM dbo.MIG_597_STG_PAY WITH (NOLOCK))
         AND EXISTS (SELECT 1 FROM dbo.MIG_597_STG_DEBT_LOOKUP WITH (NOLOCK))
        THEN 1 ELSE 0 END;

    TRUNCATE TABLE dbo.MIG_597_STG_MAP_OUT;

    IF @StgResume = 1
    BEGIN
        SELECT @PayLastKey = ISNULL(MAX(SRC_KEY), N'') FROM dbo.MIG_597_STG_PAY WITH (NOLOCK);
        SET @N = (SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY WITH (NOLOCK));
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 STG resume KEEP pay=' + CAST(@N AS VARCHAR(20))
                     + N' debt=' + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_DEBT_LOOKUP WITH (NOLOCK)) AS VARCHAR(20))
                     + N' lastKey=' + @PayLastKey;
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END
    ELSE
    BEGIN
        TRUNCATE TABLE dbo.MIG_597_STG_KEYS;
        TRUNCATE TABLE dbo.MIG_597_STG_DEBT_LOOKUP;
        TRUNCATE TABLE dbo.MIG_597_STG_PAY;

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
          AND NOT EXISTS (
                SELECT 1 FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
                WHERE m.SRC_KEY = s.SRC_KEY AND m.ENERGY_LREF IS NOT NULL
              )
        OPTION (RECOMPILE, MAXDOP 24);

        INSERT INTO dbo.MIG_597_STG_DEBT_LOOKUP (MAIN_LREF, DEBT_PT_LREF)
        SELECT k.MAIN_LREF, MIN(d.LREF)
        FROM dbo.MIG_597_STG_KEYS k
        INNER JOIN dbo.LS_005_01_PAYTRANS d WITH (NOLOCK)
            ON d.INVOICEREF = k.MAIN_LREF
        WHERE d.IOCODE = 0
          AND d.CANCELED = 0
          AND (d.CANCELLATIONPAYMENT = 0 OR d.CANCELLATIONPAYMENT IS NULL)
        GROUP BY k.MAIN_LREF
        OPTION (RECOMPILE, MAXDOP 24);

        SET @PayLastKey = N'';
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 PAY debt_lookup mains='
                     + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_KEYS) AS VARCHAR(20))
                     + N' resolved='
                     + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_DEBT_LOOKUP) AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END
    /* STG_PAY fill — keyset batch (MAXDOP 8); USE_HINT collide fill sonrasi */
    SET @Total = 0;
    WHILE 1 = 1
    BEGIN
        TRUNCATE TABLE dbo.MIG_597_STG_SRC_BATCH;

        INSERT INTO dbo.MIG_597_STG_SRC_BATCH (SRC_KEY)
        SELECT TOP (@BatchSize) s.SRC_KEY
        FROM izgazMGR.dbo.LS_OV_PAY_PT s WITH (NOLOCK)
        WHERE s.SRC_KEY > @PayLastKey
          AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
                )
          AND NOT EXISTS (
                SELECT 1 FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
                WHERE m.SRC_KEY = s.SRC_KEY
                  AND m.ENERGY_LREF IS NOT NULL
              )
        ORDER BY s.SRC_KEY
        OPTION (RECOMPILE, MAXDOP 8);

        SET @BatchN = @@ROWCOUNT;
        IF @BatchN = 0 BREAK;

        SELECT @PayLastKey = MAX(SRC_KEY) FROM dbo.MIG_597_STG_SRC_BATCH;

        INSERT INTO dbo.MIG_597_STG_PAY (
            SRC_KEY, LREF_HINT, INVOICEREF, CROSSREF_MAIN_LREF, [TYPE], IOCODE,
            PAYTYPE, XTYPE, TRANSTYPE, LINETYPE, INST_NR, DATE_, PAYABLETOTAL, CANCELED, CLIENTREF,
            ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, USE_HINT, CROSSREF_PT,
            BANKREF_SMS, BANK_RECORD_REF, PAID_AMT
        )
        SELECT
            s.SRC_KEY,
            CAST(s.LREF_HINT AS INT),
            CAST(s.INVOICEREF AS INT),
            CAST(s.CROSSREF_MAIN_LREF AS INT),
            CAST(s.[TYPE] AS TINYINT),
            CAST(s.IOCODE AS TINYINT),
            CAST(s.PAYTYPE AS INT),
            CAST(COALESCE(TRY_CAST(s.XTYPE AS INT), 1) AS INT),
            CAST(s.TRANSTYPE AS INT),
            CAST(s.LINETYPE AS INT),
            CAST(ISNULL(s.INST_NR, 0) AS INT),
            CASE WHEN s.DATE_ IS NULL
                      OR CAST(s.DATE_ AS DATETIME2) < CAST('1900-01-01' AS DATETIME2)
                      OR CAST(s.DATE_ AS DATETIME2) > CAST('2079-06-06 23:59:00' AS DATETIME2)
                 THEN CAST(NULL AS SMALLDATETIME)
                 ELSE CAST(CAST(s.DATE_ AS DATETIME2) AS SMALLDATETIME) END,
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            CAST(ISNULL(s.CANCELED, 0) AS BIT),
            CAST(s.CLIENTREF AS INT),
            s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID,
            CAST(CASE WHEN s.LREF_HINT BETWEEN 1 AND 2147483647 THEN 1 ELSE 0 END AS BIT),
            l.DEBT_PT_LREF,
            CAST(s.BANKREF AS INT),
            CAST(s.BANK_RECORD_REF AS NVARCHAR(50)),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), ISNULL(s.PAID, 0)))
        FROM izgazMGR.dbo.LS_OV_PAY_PT s WITH (NOLOCK)
        INNER JOIN dbo.MIG_597_STG_SRC_BATCH b
            ON b.SRC_KEY = s.SRC_KEY
        LEFT JOIN dbo.MIG_597_STG_DEBT_LOOKUP l
            ON l.MAIN_LREF = CAST(s.CROSSREF_MAIN_LREF AS INT)
        OPTION (RECOMPILE, MAXDOP 8);

        SET @Total = @Total + @BatchN;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 STG_PAY fill +' + CAST(@BatchN AS VARCHAR(20))
                     + N' total=' + CAST(@Total AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* hint collide pre-pass YOK — 60M×PAYTRANS tarama/JOIN cutover'da olum.
       Hint INSERT: NOT EXISTS (LREF); cakisanlar LOADED=0 kalir → leftover→identity. */
    IF @DEBUG = 1
        RAISERROR('597 STG_PAY hint collide SKIP (filter at INSERT + leftover→identity)', 0, 1) WITH NOWAIT;

    SET @N = (SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY WITH (NOLOCK));
    SET @Msg = N'597 INSERT PAY_PT pending=' + CAST(@N AS VARCHAR(20))
             + N' hint=' + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY WITH (NOLOCK) WHERE USE_HINT=1) AS VARCHAR(20))
             + N' identity=' + CAST((SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY WITH (NOLOCK) WHERE USE_HINT=0) AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* hint path — IDENTITY_INSERT; FULL'da PAYTRANS NCIX zorunlu DISABLE */
    IF @AGR_ID IS NULL
       AND EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
              AND i.type_desc = N'NONCLUSTERED'
              AND i.is_disabled = 0
       )
    BEGIN
        IF OBJECT_ID('dbo.SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD', 'P') IS NOT NULL
        BEGIN
            IF @DEBUG = 1
                RAISERROR('597 PAY: SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD (NCIX DISABLE)', 0, 1) WITH NOWAIT;
            EXEC dbo.SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD @DEBUG = @DEBUG;
        END
        IF EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
              AND i.type_desc = N'NONCLUSTERED'
              AND i.is_disabled = 0
        )
        BEGIN
            RAISERROR('597 PAY: PAYTRANS NCIX hala acik — 20b_PAYTRANS_NCIX_DISABLE.sql', 16, 1);
            RETURN;
        END
    END

    /* hint INSERT — identity kalibi (20260804): MERGE OUTPUT → STG_MAP_OUT → MAP/LOADED
       PAYTRANS JOIN dogrulama YOK. Cakisan (OUTPUT'a dustmeyen) → USE_HINT=0. */
    SET @Total = 0;
    SET @PayLastKey = N'';
    IF @DEBUG = 1
        RAISERROR('597 PAY hint MERGE OUTPUT (same as identity path; no PT join)', 0, 1) WITH NOWAIT;
    BEGIN TRY
        WHILE 1 = 1
        BEGIN
            TRUNCATE TABLE dbo.MIG_597_STG_SRC_BATCH;
            TRUNCATE TABLE dbo.MIG_597_STG_MAP_OUT;

            INSERT INTO dbo.MIG_597_STG_SRC_BATCH (SRC_KEY)
            SELECT TOP (@BatchSize) p.SRC_KEY
            FROM dbo.MIG_597_STG_PAY p
            WHERE p.USE_HINT = 1
              AND p.LOADED = 0
              AND p.LREF_HINT IS NOT NULL
              AND p.SRC_KEY > @PayLastKey
            ORDER BY p.SRC_KEY
            OPTION (RECOMPILE);

            SET @BatchN = @@ROWCOUNT;
            IF @BatchN = 0 BREAK;

            SELECT @PayLastKey = MAX(SRC_KEY) FROM dbo.MIG_597_STG_SRC_BATCH;

            BEGIN TRY
                /* TRAN sadece MERGE+MAP_OUT LOADED — collide/adopt disarida (uzun UPDATE open_tran YASAK) */
                BEGIN TRAN;
                SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS ON;

                MERGE dbo.LS_005_01_PAYTRANS WITH (HOLDLOCK) AS t
                USING (
                    SELECT p.*
                    FROM dbo.MIG_597_STG_SRC_BATCH b
                    INNER JOIN dbo.MIG_597_STG_PAY p ON p.SRC_KEY = b.SRC_KEY
                    WHERE p.USE_HINT = 1
                      AND p.LOADED = 0
                      AND p.LREF_HINT IS NOT NULL
                      AND NOT EXISTS (
                            SELECT 1 FROM dbo.LS_005_01_PAYTRANS x WITH (NOLOCK)
                            WHERE x.LREF = p.LREF_HINT
                          )
                ) AS s
                ON 1 = 0
                WHEN NOT MATCHED THEN INSERT (
                    LREF, INVOICEREF, [TYPE], IOCODE, CROSSREF, PAYTYPE, TRANSTYPE, LINETYPE, INST_NR,
                    DATE_, TLTOTAL, CURTOTAL, TAX, GRANDTOTAL, PAYABLETOTAL, DV, PAID, CANCELED, CLIENTREF, CLIENT_TYPE,
                    ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF,
                    BANKREF, BANK_RECORD_REF, LASTPAIDDATE, XTYPE
                ) VALUES (
                    s.LREF_HINT, s.INVOICEREF, s.[TYPE], s.IOCODE,
                    COALESCE(s.CROSSREF_PT, s.CROSSREF_MAIN_LREF),
                    s.PAYTYPE, s.TRANSTYPE, s.LINETYPE, s.INST_NR,
                    s.DATE_,
                    s.PAYABLETOTAL, s.PAYABLETOTAL, CAST(0 AS FLOAT),
                    s.PAYABLETOTAL, s.PAYABLETOTAL, CAST(0 AS FLOAT),
                    CASE WHEN ISNULL(s.CANCELED, 0) = 0 THEN s.PAID_AMT ELSE 0 END,
                    s.CANCELED, s.CLIENTREF, CAST(91 AS TINYINT),
                    s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID, s.INVOICEREF,
                    s.BANKREF_SMS, s.BANK_RECORD_REF,
                    CASE WHEN ISNULL(s.CANCELED, 0) = 0 THEN s.DATE_ ELSE NULL END,
                    ISNULL(s.XTYPE, 1)
                )
                OUTPUT inserted.LREF, s.SRC_KEY INTO dbo.MIG_597_STG_MAP_OUT (ENERGY_LREF, SRC_KEY)
                OPTION (RECOMPILE);

                SET @N = @@ROWCOUNT;
                SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF;

                /* MAP_OUT surer — STG hint scan YASAK */
                UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
                FROM dbo.MIG_597_STG_MAP_OUT o
                INNER JOIN dbo.MIG_OV_ID_MAP m ON m.SRC_KEY = o.SRC_KEY
                WHERE m.ENERGY_LREF IS NULL
                OPTION (RECOMPILE, FORCE ORDER);

                UPDATE p SET p.LOADED = 1
                FROM dbo.MIG_597_STG_MAP_OUT o
                INNER JOIN dbo.MIG_597_STG_PAY p ON p.SRC_KEY = o.SRC_KEY
                OPTION (RECOMPILE, FORCE ORDER);

                COMMIT TRAN;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK TRAN;
                BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;
                THROW;
            END CATCH

            /* adopt: batch→PT LREF (onceki kismi yazim) — FORCE ORDER batch-first */
            UPDATE m SET m.ENERGY_LREF = p.LREF_HINT
            FROM dbo.MIG_597_STG_SRC_BATCH b
            INNER JOIN dbo.MIG_597_STG_PAY p ON p.SRC_KEY = b.SRC_KEY
            INNER JOIN dbo.MIG_OV_ID_MAP m ON m.SRC_KEY = b.SRC_KEY
            INNER JOIN dbo.LS_005_01_PAYTRANS t WITH (NOLOCK) ON t.LREF = p.LREF_HINT
            WHERE p.USE_HINT = 1
              AND p.LOADED = 0
              AND p.LREF_HINT IS NOT NULL
              AND m.ENERGY_LREF IS NULL
            OPTION (RECOMPILE, FORCE ORDER);

            UPDATE p SET p.LOADED = 1
            FROM dbo.MIG_597_STG_SRC_BATCH b
            INNER JOIN dbo.MIG_597_STG_PAY p ON p.SRC_KEY = b.SRC_KEY
            INNER JOIN dbo.LS_005_01_PAYTRANS t WITH (NOLOCK) ON t.LREF = p.LREF_HINT
            WHERE p.USE_HINT = 1
              AND p.LOADED = 0
              AND p.LREF_HINT IS NOT NULL
            OPTION (RECOMPILE, FORCE ORDER);

            /* cakisma → identity: sadece batch, MAP_OUT'ta yok */
            UPDATE p SET p.USE_HINT = 0
            FROM dbo.MIG_597_STG_SRC_BATCH b
            INNER JOIN dbo.MIG_597_STG_PAY p ON p.SRC_KEY = b.SRC_KEY
            WHERE p.USE_HINT = 1
              AND p.LOADED = 0
              AND NOT EXISTS (
                    SELECT 1 FROM dbo.MIG_597_STG_MAP_OUT o WHERE o.SRC_KEY = b.SRC_KEY
                  )
            OPTION (RECOMPILE, FORCE ORDER);

            SET @Total = @Total + @N;
            IF @DEBUG = 1
            BEGIN
                SET @Msg = N'597 PAY_PT hint OUTPUT +' + CAST(@N AS VARCHAR(20))
                         + N' batch=' + CAST(@BatchN AS VARCHAR(20))
                         + N' total=' + CAST(@Total AS VARCHAR(20))
                         + N' lastKey=' + @PayLastKey;
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END
        END
    END TRY
    BEGIN CATCH
        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;
        SET @Msg = N'597 PAY hint INSERT FAIL: ' + ERROR_MESSAGE();
        RAISERROR('%s', 16, 1, @Msg);
        RETURN;
    END CATCH
    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 INSERT PAY_PT(hint)=' + CAST(@Total AS VARCHAR(20))
                 + N' collide→identity=' + CAST((
                        SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY WITH (NOLOCK)
                        WHERE USE_HINT = 0 AND LOADED = 0
                   ) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* hint artigi → identity */
    IF EXISTS (SELECT 1 FROM dbo.MIG_597_STG_PAY WITH (NOLOCK) WHERE USE_HINT = 1 AND LOADED = 0)
    BEGIN
        SET @N = (SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY WITH (NOLOCK) WHERE USE_HINT = 1 AND LOADED = 0);
        UPDATE dbo.MIG_597_STG_PAY SET USE_HINT = 0 WHERE USE_HINT = 1 AND LOADED = 0;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 PAY hint leftover→identity=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* identity path — MERGE OUTPUT batch; LOADED=1; MGR SKIP */
    SET @Total = 0;
    WHILE EXISTS (
        SELECT 1 FROM dbo.MIG_597_STG_PAY WITH (NOLOCK)
        WHERE USE_HINT = 0 AND LOADED = 0
    )
    BEGIN
        TRUNCATE TABLE dbo.MIG_597_STG_MAP_OUT;

        BEGIN TRY
            BEGIN TRAN;
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;

            MERGE dbo.LS_005_01_PAYTRANS WITH (HOLDLOCK) AS t
            USING (
                SELECT TOP (@BatchSize) p.*
                FROM dbo.MIG_597_STG_PAY p
                WHERE p.USE_HINT = 0 AND p.LOADED = 0
                  AND NOT EXISTS (
                        SELECT 1 FROM dbo.MIG_OV_ID_MAP m
                        WHERE m.SRC_KEY = p.SRC_KEY AND m.ENERGY_LREF IS NOT NULL
                      )
                ORDER BY p.SRC_KEY
            ) AS s
            ON 1 = 0
            WHEN NOT MATCHED THEN INSERT (
                INVOICEREF, [TYPE], IOCODE, CROSSREF, PAYTYPE, TRANSTYPE, LINETYPE, INST_NR,
                DATE_, TLTOTAL, CURTOTAL, TAX, GRANDTOTAL, PAYABLETOTAL, DV, PAID, CANCELED, CLIENTREF, CLIENT_TYPE,
                ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF,
                BANKREF, BANK_RECORD_REF, LASTPAIDDATE, XTYPE
            ) VALUES (
                s.INVOICEREF, s.[TYPE], s.IOCODE,
                COALESCE(s.CROSSREF_PT, s.CROSSREF_MAIN_LREF),
                s.PAYTYPE, s.TRANSTYPE, s.LINETYPE, s.INST_NR,
                s.DATE_,
                s.PAYABLETOTAL, s.PAYABLETOTAL, CAST(0 AS FLOAT),
                s.PAYABLETOTAL, s.PAYABLETOTAL, CAST(0 AS FLOAT),
                CASE WHEN ISNULL(s.CANCELED, 0) = 0 THEN s.PAID_AMT ELSE 0 END,
                s.CANCELED, s.CLIENTREF, CAST(91 AS TINYINT),
                s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID, s.INVOICEREF,
                s.BANKREF_SMS, s.BANK_RECORD_REF,
                CASE WHEN ISNULL(s.CANCELED, 0) = 0 THEN s.DATE_ ELSE NULL END,
                ISNULL(s.XTYPE, 1)
            )
            OUTPUT inserted.LREF, s.SRC_KEY INTO dbo.MIG_597_STG_MAP_OUT (ENERGY_LREF, SRC_KEY)
            OPTION (RECOMPILE);

            SET @BatchN = @@ROWCOUNT;

            UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
            FROM dbo.MIG_OV_ID_MAP m
            INNER JOIN dbo.MIG_597_STG_MAP_OUT o ON o.SRC_KEY = m.SRC_KEY
            WHERE m.ENERGY_LREF IS NULL;

            UPDATE p SET p.LOADED = 1
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
                     + N' left=' + CAST((
                            SELECT COUNT(*) FROM dbo.MIG_597_STG_PAY WITH (NOLOCK)
                            WHERE USE_HINT = 0 AND LOADED = 0
                       ) AS VARCHAR(20));
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
            CASE WHEN s.DATE_ IS NULL
                      OR CAST(s.DATE_ AS DATETIME2) < CAST('1900-01-01' AS DATETIME2)
                      OR CAST(s.DATE_ AS DATETIME2) > CAST('2079-06-06 23:59:00' AS DATETIME2)
                 THEN CAST(NULL AS SMALLDATETIME)
                 ELSE CAST(CAST(s.DATE_ AS DATETIME2) AS SMALLDATETIME) END,
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
        /* AFL-gate: acik borc yoksa CANCEL_REV yazma (AFL master).
           AFL tablosu yoksa guvenli taraf: REV insert YOK. */
        IF OBJECT_ID('dbo.LS_AFL_OPEN_DEBT', 'U') IS NULL
        BEGIN
            IF @DEBUG = 1
                RAISERROR('597 INSERT CANCEL_REV SKIP — LS_AFL_OPEN_DEBT yok', 0, 1) WITH NOWAIT;
        END
        ELSE
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
                CASE WHEN s.DATE_ IS NULL
                          OR CAST(s.DATE_ AS DATETIME2) < CAST('1900-01-01' AS DATETIME2)
                          OR CAST(s.DATE_ AS DATETIME2) > CAST('2079-06-06 23:59:00' AS DATETIME2)
                     THEN CAST(NULL AS SMALLDATETIME)
                     ELSE CAST(CAST(s.DATE_ AS DATETIME2) AS SMALLDATETIME) END,
                CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
                CAST(s.CLIENTREF AS INT),
                s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID
            FROM izgazMGR.dbo.LS_OV_CANCEL_REV s WITH (NOLOCK)
            WHERE (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
                )
              AND s.ABYS_ACCOUNT_ID IS NOT NULL
              AND EXISTS (
                    SELECT 1
                    FROM dbo.LS_AFL_OPEN_DEBT a WITH (NOLOCK)
                    WHERE a.FATURAID = s.ABYS_ACCOUNT_ID
                      AND CONVERT(DECIMAL(18,2), ISNULL(a.BALANCE, 0)) > 0.02
                  )
              AND NOT EXISTS (
                    SELECT 1 FROM dbo.MIG_OV_ID_MAP m
                    WHERE m.SRC_KEY = s.SRC_KEY AND m.ENERGY_LREF IS NOT NULL
                  );

            IF @DEBUG = 1
            BEGIN
                SET @Msg = N'597 INSERT CANCEL_REV staged(AFL-open)='
                         + CAST(@@ROWCOUNT AS VARCHAR(20));
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END
        END
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
            /* MGR MAP SKIP — 20a offline */

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
           AND pt.IOCODE = 0
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

    /* LS_001: 109 borca bagli tahsilat tutar NULL → BORC/INV alan-alan (GT=KDV dahil, TL=haric) */
    UPDATE TAH
    SET
        TAH.TLTOTAL      = ISNULL(BORC.TLTOTAL, INV.TLTOTAL),
        TAH.CURTOTAL     = ISNULL(BORC.CURTOTAL, INV.CURTOTAL),
        TAH.TAX          = ISNULL(BORC.TAX, ISNULL(INV.TAX, 0)),
        TAH.GRANDTOTAL   = ISNULL(BORC.GRANDTOTAL, INV.GRANDTOTAL),
        TAH.PAYABLETOTAL = ISNULL(TAH.PAYABLETOTAL, ISNULL(BORC.PAYABLETOTAL, INV.PAYABLETOTAL)),
        TAH.DV           = ISNULL(BORC.DV, ISNULL(INV.DV, 0))
    FROM dbo.LS_005_01_PAYTRANS AS TAH
    INNER JOIN dbo.LS_005_01_PAYTRANS AS BORC ON TAH.CROSSREF = BORC.LREF
    INNER JOIN dbo.LS_005_01_INVOICE AS INV ON INV.LREF = BORC.INVOICEREF
    WHERE BORC.[TYPE] = 109
      AND ISNULL(BORC.IOCODE, 0) = 0
      AND ISNULL(TAH.IOCODE, 0) = 1
      AND TAH.TLTOTAL IS NULL
      AND TAH.DV IS NULL
      AND ISNULL(BORC.TLTOTAL, INV.TLTOTAL) IS NOT NULL
      AND (
            @AGR_ID IS NULL
         OR (@AGR_ID = -1 AND INV.ABYS_AGREEMENT_ID IS NULL)
         OR (@AGR_ID > 0 AND (INV.ABYS_AGREEMENT_ID = @AGR_ID OR BORC.ABYS_AGREEMENT_ID = @AGR_ID))
          )
    OPTION (RECOMPILE, MAXDOP 8);

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 INSERT TYPE109 TAH tutar heal=' + CAST(@@ROWCOUNT AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;
    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;

    SET @Ts = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    SET @Msg = @Ts + N' | E597 | INFO | INSERT bitti — sonraki WIRE zorunlu';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END
GO
