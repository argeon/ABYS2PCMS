/* ============================================================
   prodREADY_ENERGY / 60_GUVENCE_IADE_INSERT
   O60 dump → TYPE 110 (GÜVENCE BEDELİ İADE) INV + INVLINES
   Kaynak: izgazMGR.LS_OV_GUVENCE_IADE_*  (Oracle CTAS O60)
   Kural : GUVENCE_IADE_110_RULE.md
   - #temp YOK (fiziksel MIG_610_STG_*)
   - Index staging icinde; gereksiz FK dokunma
   - WHILE: DELETE processed + @BatchN=0 BREAK (bos dongu yok)
   Tek basina cutover YASAK → 69_GUVENCE_IADE_ALL
   ============================================================ */
USE energy;
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---- fiziksel staging (energy collation) ---- */
IF OBJECT_ID('dbo.MIG_610_STG_INV', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_610_STG_INV (
        SRC_KEY              VARCHAR(80)   NOT NULL,
        LREF_HINT            INT           NULL,
        IOCODE               TINYINT       NULL,
        FICHENO              VARCHAR(45)   NULL,
        DATE_                DATETIME      NULL,
        DUEDATE              DATETIME      NULL,
        [TYPE]               TINYINT       NULL,
        CLIENTREF            INT           NULL,
        TLTOTAL              FLOAT         NULL,
        CURID                SMALLINT      NULL,
        CURTOTAL             FLOAT         NULL,
        EXPLAIN              NVARCHAR(250) NULL,
        CANCELED             BIT           NULL,
        OWNERREF             INT           NULL,
        OWNERTYPE            TINYINT       NULL,
        TAX                  FLOAT         NULL,
        DV                   FLOAT         NULL,
        GRANDTOTAL           FLOAT         NULL,
        PRINTCOUNT           INT           NULL,
        PAYABLETOTAL         FLOAT         NULL,
        CLOSED               BIT           NULL,
        FITNO                BIGINT        NULL,
        BN_TYPE              INT           NULL,
        AMOUNT               FLOAT         NULL,
        PERIOD               INT           NULL,
        HAS_DISCOUNT         BIT           NULL,
        DISCOUNT_AMOUNT      FLOAT         NULL,
        ADDDATE              DATETIME      NULL,
        ADDUSER              INT           NULL,
        ABYS_ID              BIGINT        NULL,
        ABYS_ACCOUNT_ID      BIGINT        NULL,
        ABYS_ACTION_TYPE_ID  BIGINT        NULL,
        ABYS_AGREEMENT_ID    BIGINT        NULL,
        CONSTRAINT PK_MIG_610_STG_INV PRIMARY KEY CLUSTERED (SRC_KEY)
    );
END
GO

IF OBJECT_ID('dbo.MIG_610_STG_IL', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_610_STG_IL (
        SRC_KEY           VARCHAR(80)   NOT NULL,
        INVOICE_SRC_KEY   VARCHAR(80)   NOT NULL,
        CLIENTREF         INT           NULL,
        DATE_             DATETIME      NULL,
        [TYPE]            TINYINT       NULL,
        LINENR            SMALLINT      NULL,
        TRANSTYPE         INT           NULL,
        AMOUNT            FLOAT         NULL,
        TLTOTAL           FLOAT         NULL,
        TAX               FLOAT         NULL,
        GRANDTOTAL        FLOAT         NULL,
        LINEEXP           NVARCHAR(100) NULL,
        ABYS_INCOME_ID    BIGINT        NULL,
        PCMS_INCOME_CODE  INT           NULL,
        ABYS_AGREEMENT_ID BIGINT        NULL,
        ABYS_ACCOUNT_ID   BIGINT        NULL,
        CONSTRAINT PK_MIG_610_STG_IL PRIMARY KEY CLUSTERED (SRC_KEY)
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MIG_610_STG_IL')
      AND name = 'IX_MIG_610_STG_IL_INV'
)
    CREATE NONCLUSTERED INDEX IX_MIG_610_STG_IL_INV
        ON dbo.MIG_610_STG_IL (INVOICE_SRC_KEY);
GO

IF OBJECT_ID('dbo.MIG_610_STG_MAP_OUT', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_610_STG_MAP_OUT (
        ENERGY_LREF INT         NOT NULL,
        SRC_KEY     VARCHAR(80) NOT NULL,
        CONSTRAINT PK_MIG_610_STG_MAP_OUT PRIMARY KEY CLUSTERED (SRC_KEY)
    );
END
GO

/* ---- izgazMGR OV join IX (yoksa olustur; FK yok) ---- */
IF OBJECT_ID('izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVOICE', 'U') IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM izgazMGR.sys.indexes
    WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVOICE')
      AND name = 'IX_MIG_OV_GUV_IADE_INV_AGR'
)
AND COL_LENGTH('izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVOICE', 'ABYS_AGREEMENT_ID') IS NOT NULL
    CREATE NONCLUSTERED INDEX IX_MIG_OV_GUV_IADE_INV_AGR
        ON izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVOICE (ABYS_AGREEMENT_ID)
        INCLUDE (SRC_KEY, [TYPE], TLTOTAL);
GO

IF OBJECT_ID('izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVOICE', 'U') IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM izgazMGR.sys.indexes
    WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVOICE')
      AND name = 'UX_MIG_OV_GUV_IADE_INV_SRC'
)
AND COL_LENGTH('izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVOICE', 'SRC_KEY') IS NOT NULL
    CREATE UNIQUE NONCLUSTERED INDEX UX_MIG_OV_GUV_IADE_INV_SRC
        ON izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVOICE (SRC_KEY);
GO

IF OBJECT_ID('izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVLINES', 'U') IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM izgazMGR.sys.indexes
    WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVLINES')
      AND name = 'IX_MIG_OV_GUV_IADE_IL_INV'
)
AND COL_LENGTH('izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVLINES', 'INVOICE_SRC_KEY') IS NOT NULL
    CREATE NONCLUSTERED INDEX IX_MIG_OV_GUV_IADE_IL_INV
        ON izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVLINES (INVOICE_SRC_KEY)
        INCLUDE (SRC_KEY, TLTOTAL, ABYS_INCOME_ID);
GO

IF OBJECT_ID('izgazMGR.dbo.LS_OV_GUVENCE_IADE_PAYTRANS', 'U') IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM izgazMGR.sys.indexes
    WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_OV_GUVENCE_IADE_PAYTRANS')
      AND name = 'IX_MIG_OV_GUV_IADE_PT_INV'
)
AND COL_LENGTH('izgazMGR.dbo.LS_OV_GUVENCE_IADE_PAYTRANS', 'INVOICE_SRC_KEY') IS NOT NULL
    CREATE NONCLUSTERED INDEX IX_MIG_OV_GUV_IADE_PT_INV
        ON izgazMGR.dbo.LS_OV_GUVENCE_IADE_PAYTRANS (INVOICE_SRC_KEY)
        INCLUDE (SRC_KEY, PAYABLETOTAL, TRANSTYPE);
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_GUVENCE_IADE_INSERT
    @AGR_ID    BIGINT = NULL,
    @CLEAN     BIT = 1,
    @DEBUG     BIT = 1,
    @BatchSize INT = 20000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET QUOTED_IDENTIFIER ON;

    IF @BatchSize IS NULL OR @BatchSize < 1000 SET @BatchSize = 20000;
    IF @BatchSize > 100000 SET @BatchSize = 100000;

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_ID_MAP', 'U') IS NULL
       OR OBJECT_ID('izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVOICE', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR LS_OV_ID_MAP / LS_OV_GUVENCE_IADE_INVOICE yok (O60 dump).', 16, 1);
        RETURN;
    END

    IF OBJECT_ID('dbo.MIG_610_STG_INV', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_610_STG_IL', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_610_STG_MAP_OUT', 'U') IS NULL
    BEGIN
        RAISERROR('MIG_610_STG_* yok — once 60_GUVENCE_IADE_INSERT.sql DDL deploy.', 16, 1);
        RETURN;
    END

    IF OBJECT_ID('dbo.MIG_OV_ID_MAP', 'U') IS NULL
    BEGIN
        RAISERROR('dbo.MIG_OV_ID_MAP yok — once 590/MAP sync altyapisi.', 16, 1);
        RETURN;
    END

    DECLARE @Msg NVARCHAR(400), @N INT, @BatchN INT, @Total BIGINT;
    DECLARE @Ts VARCHAR(30) = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    DECLARE @MgrCnt BIGINT, @EnCnt BIGINT;
    DECLARE @HasLineNrSrc BIT =
        CASE WHEN COL_LENGTH('dbo.LS_005_01_INVLINES', 'ABYS_LINENR_SRC') IS NOT NULL
             THEN 1 ELSE 0 END;

    /* ---- MAP sync (GUV_IADE*) ---- */
    SELECT @MgrCnt = COUNT_BIG(*)
    FROM izgazMGR.dbo.LS_OV_ID_MAP WITH (NOLOCK)
    WHERE OV_KIND IN (N'GUV_IADE_INV', N'GUV_IADE_IL', N'GUV_IADE_PT')
      AND (
          @AGR_ID IS NULL
       OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
       OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
        );

    IF @MgrCnt = 0
    BEGIN
        SET @Msg = @Ts + N' | E610 | INFO | MAP GUV_IADE* yok — O60 dump / ID_MAP append kontrol';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        /* bos kosu: FAIL degil — GATE ayri bakar */
    END

    SELECT @EnCnt = COUNT_BIG(*)
    FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
    WHERE OV_KIND IN (N'GUV_IADE_INV', N'GUV_IADE_IL', N'GUV_IADE_PT')
      AND (
          @AGR_ID IS NULL
       OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
       OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
        );

    IF @MgrCnt > 0 AND @EnCnt >= @MgrCnt
    BEGIN
        SET @Msg = @Ts + N' | E610 | INFO | MAP sync SKIP (en='
                 + CAST(@EnCnt AS VARCHAR(20)) + N' mgr=' + CAST(@MgrCnt AS VARCHAR(20)) + N')';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
    ELSE IF @MgrCnt > 0
    BEGIN
        MERGE dbo.MIG_OV_ID_MAP AS t
        USING (
            SELECT * FROM izgazMGR.dbo.LS_OV_ID_MAP WITH (NOLOCK)
            WHERE OV_KIND IN (N'GUV_IADE_INV', N'GUV_IADE_IL', N'GUV_IADE_PT')
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

        SET @Msg = CONVERT(VARCHAR(30), SYSDATETIME(), 121)
                 + N' | E610 | INFO | MAP sync MERGE bitti';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* OV → MAP seed (ID_MAP append eksikse) — set-based, loop yok */
    INSERT INTO dbo.MIG_OV_ID_MAP (
        OV_KIND, SRC_KEY, LREF_HINT, PARENT_SRC_KEY, REF_MAIN_LREF,
        ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID, ABYS_ID_BUSINESS, ENERGY_LREF
    )
    SELECT N'GUV_IADE_INV', CAST(s.SRC_KEY AS VARCHAR(80)), CAST(s.LREF_HINT AS INT),
           CAST(NULL AS VARCHAR(80)), CAST(s.ABYS_MAIN_LREF AS INT),
           s.ABYS_AGREEMENT_ID, s.ABYS_ACCOUNT_ID, s.ABYS_ID, NULL
    FROM izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVOICE s WITH (NOLOCK)
    WHERE (
          @AGR_ID IS NULL
       OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL)
       OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
        )
      AND NOT EXISTS (SELECT 1 FROM dbo.MIG_OV_ID_MAP m WHERE m.SRC_KEY = s.SRC_KEY)
    OPTION (RECOMPILE, MAXDOP 24);

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVLINES', 'U') IS NOT NULL
    INSERT INTO dbo.MIG_OV_ID_MAP (
        OV_KIND, SRC_KEY, LREF_HINT, PARENT_SRC_KEY, REF_MAIN_LREF,
        ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID, ABYS_ID_BUSINESS, ENERGY_LREF
    )
    SELECT N'GUV_IADE_IL', CAST(s.SRC_KEY AS VARCHAR(80)), NULL,
           CAST(s.INVOICE_SRC_KEY AS VARCHAR(80)), NULL,
           s.ABYS_AGREEMENT_ID, s.ABYS_ACCOUNT_ID, NULL, NULL
    FROM izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVLINES s WITH (NOLOCK)
    WHERE (
          @AGR_ID IS NULL
       OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL)
       OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
        )
      AND NOT EXISTS (SELECT 1 FROM dbo.MIG_OV_ID_MAP m WHERE m.SRC_KEY = s.SRC_KEY)
    OPTION (RECOMPILE, MAXDOP 24);

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_GUVENCE_IADE_PAYTRANS', 'U') IS NOT NULL
    INSERT INTO dbo.MIG_OV_ID_MAP (
        OV_KIND, SRC_KEY, LREF_HINT, PARENT_SRC_KEY, REF_MAIN_LREF,
        ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID, ABYS_ID_BUSINESS, ENERGY_LREF
    )
    SELECT N'GUV_IADE_PT', CAST(s.SRC_KEY AS VARCHAR(80)), NULL,
           CAST(s.INVOICE_SRC_KEY AS VARCHAR(80)), CAST(s.ABYS_MAIN_LREF AS INT),
           s.ABYS_AGREEMENT_ID, s.ABYS_ACCOUNT_ID, s.ABYS_ID, NULL
    FROM izgazMGR.dbo.LS_OV_GUVENCE_IADE_PAYTRANS s WITH (NOLOCK)
    WHERE (
          @AGR_ID IS NULL
       OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL)
       OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
        )
      AND NOT EXISTS (SELECT 1 FROM dbo.MIG_OV_ID_MAP m WHERE m.SRC_KEY = s.SRC_KEY)
    OPTION (RECOMPILE, MAXDOP 24);

    /* ---- CLEAN: sadece migrasyon TYPE=110 (MAP bagli) ---- */
    IF @CLEAN = 1
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
            WHERE m.OV_KIND IN (N'GUV_IADE_INV', N'GUV_IADE_IL', N'GUV_IADE_PT')
              AND m.ENERGY_LREF IS NOT NULL
              AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
                )
        )
        BEGIN
        /* PT (LREF = INV LREF ailesi) */
        DELETE pt
        FROM dbo.LS_005_01_PAYTRANS pt
        INNER JOIN dbo.MIG_OV_ID_MAP m
            ON m.ENERGY_LREF = pt.LREF
           AND m.OV_KIND IN (N'GUV_IADE_PT', N'GUV_IADE_INV')
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);
        SET @N = @@ROWCOUNT;

        DELETE il
        FROM dbo.LS_005_01_INVLINES il
        INNER JOIN dbo.MIG_OV_ID_MAP m
            ON m.ENERGY_LREF = il.LREF AND m.OV_KIND = N'GUV_IADE_IL'
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);
        SET @N += @@ROWCOUNT;

        DELETE inv
        FROM dbo.LS_005_01_INVOICE inv
        INNER JOIN dbo.MIG_OV_ID_MAP m
            ON m.ENERGY_LREF = inv.LREF AND m.OV_KIND = N'GUV_IADE_INV'
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);
        SET @N += @@ROWCOUNT;

        UPDATE m SET m.ENERGY_LREF = NULL
        FROM dbo.MIG_OV_ID_MAP m
        WHERE m.OV_KIND IN (N'GUV_IADE_INV', N'GUV_IADE_IL', N'GUV_IADE_PT')
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            );

        IF OBJECT_ID('izgazMGR.dbo.LS_OV_ID_MAP', 'U') IS NOT NULL
        UPDATE m SET m.ENERGY_LREF = NULL
        FROM izgazMGR.dbo.LS_OV_ID_MAP m
        WHERE m.OV_KIND IN (N'GUV_IADE_INV', N'GUV_IADE_IL', N'GUV_IADE_PT')
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            );

        SET @Msg = N'E610 CLEAN silinen~=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    SET @Ts = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    SET @Msg = @Ts + N' | E610 | INFO | INSERT basladi | AGR='
             + CASE WHEN @AGR_ID IS NULL THEN N'FULL' WHEN @AGR_ID = -1 THEN N'NO_AGR' ELSE CAST(@AGR_ID AS NVARCHAR(30)) END
             + N' Batch=' + CAST(@BatchSize AS VARCHAR(10));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* ---- INV staging ---- */
    TRUNCATE TABLE dbo.MIG_610_STG_INV;
    TRUNCATE TABLE dbo.MIG_610_STG_MAP_OUT;

    INSERT INTO dbo.MIG_610_STG_INV (
        SRC_KEY, LREF_HINT, IOCODE, FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF,
        TLTOTAL, CURID, CURTOTAL, EXPLAIN, CANCELED, OWNERREF, OWNERTYPE,
        TAX, DV, GRANDTOTAL, PRINTCOUNT, PAYABLETOTAL, CLOSED,
        FITNO, BN_TYPE, AMOUNT, PERIOD, HAS_DISCOUNT, DISCOUNT_AMOUNT,
        ADDDATE, ADDUSER, ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_AGREEMENT_ID
    )
    SELECT
        CAST(s.SRC_KEY AS VARCHAR(80)),
        CAST(s.LREF_HINT AS INT),
        CAST(s.IOCODE AS TINYINT),
        LEFT(s.FICHENO, 45),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DUEDATE AS DATETIME2)),
        CAST(110 AS TINYINT),
        CAST(s.CLIENTREF AS INT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TLTOTAL)),
        CAST(160 AS SMALLINT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.CURTOTAL)),
        LEFT(s.EXPLAIN, 250),
        CAST(ISNULL(s.CANCELED, 0) AS BIT),
        CAST(s.OWNERREF AS INT),
        CAST(ISNULL(s.OWNERTYPE, 91) AS TINYINT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), ISNULL(s.TAX, 0))),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), ISNULL(s.DV, 0))),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.GRANDTOTAL)),
        CAST(ISNULL(s.PRINTCOUNT, 0) AS INT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
        CAST(ISNULL(s.CLOSED, 1) AS BIT),
        CAST(s.FITNO AS BIGINT),
        CAST(s.BN_TYPE AS INT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.AMOUNT)),
        CAST(s.PERIOD AS INT),
        CAST(ISNULL(s.HAS_DISCOUNT, 0) AS BIT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), ISNULL(s.DISCOUNT_AMOUNT, 0))),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ADDDATE AS DATETIME2)),
        CAST(s.ADDUSER AS INT),
        s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_ACTION_TYPE_ID, s.ABYS_AGREEMENT_ID
    FROM izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVOICE s WITH (NOLOCK)
    WHERE s.[TYPE] = 110
      AND (
          @AGR_ID IS NULL
       OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL)
       OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
        )
      AND NOT EXISTS (
            SELECT 1 FROM dbo.MIG_OV_ID_MAP m
            WHERE m.SRC_KEY = s.SRC_KEY
              AND m.ENERGY_LREF IS NOT NULL
          )
    OPTION (RECOMPILE, MAXDOP 24);

    SET @N = (SELECT COUNT(*) FROM dbo.MIG_610_STG_INV);
    SET @Msg = N'E610 INV pending=' + CAST(@N AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* LREF_HINT yolu (varsa) */
    IF EXISTS (SELECT 1 FROM dbo.MIG_610_STG_INV WHERE LREF_HINT IS NOT NULL)
    BEGIN
        BEGIN TRY
            SET IDENTITY_INSERT dbo.LS_005_01_INVOICE ON;
            INSERT INTO dbo.LS_005_01_INVOICE (
                LREF, IOCODE, FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF,
                TLTOTAL, CURID, CURTOTAL, EXPLAIN, CANCELED, OWNERREF, OWNERTYPE,
                TAX, DV, GRANDTOTAL, PRINTCOUNT, PAYABLETOTAL, CLOSED,
                FITNO, BN_TYPE, AMOUNT, PERIOD, HAS_DISCOUNT, DISCOUNT_AMOUNT,
                ADDDATE, ADDUSER,
                ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_AGREEMENT_ID
            )
            SELECT
                s.LREF_HINT, s.IOCODE, s.FICHENO, s.DATE_, s.DUEDATE, s.[TYPE], s.CLIENTREF,
                s.TLTOTAL, s.CURID, s.CURTOTAL, s.EXPLAIN, s.CANCELED, s.OWNERREF, s.OWNERTYPE,
                s.TAX, s.DV, s.GRANDTOTAL, s.PRINTCOUNT, s.PAYABLETOTAL, s.CLOSED,
                s.FITNO, s.BN_TYPE, s.AMOUNT, s.PERIOD, s.HAS_DISCOUNT, s.DISCOUNT_AMOUNT,
                s.ADDDATE, s.ADDUSER,
                s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_ACTION_TYPE_ID, s.ABYS_AGREEMENT_ID
            FROM dbo.MIG_610_STG_INV s
            WHERE s.LREF_HINT IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM dbo.LS_005_01_INVOICE t WHERE t.LREF = s.LREF_HINT)
            OPTION (RECOMPILE, MAXDOP 24);
            SET @N = @@ROWCOUNT;
        END TRY
        BEGIN CATCH
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;
            THROW;
        END CATCH
        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;

        UPDATE m SET m.ENERGY_LREF = s.LREF_HINT
        FROM dbo.MIG_OV_ID_MAP m
        INNER JOIN dbo.MIG_610_STG_INV s ON s.SRC_KEY = m.SRC_KEY
        WHERE s.LREF_HINT IS NOT NULL AND m.ENERGY_LREF IS NULL;

        UPDATE m SET m.ENERGY_LREF = s.LREF_HINT
        FROM izgazMGR.dbo.LS_OV_ID_MAP m
        INNER JOIN dbo.MIG_610_STG_INV s ON s.SRC_KEY = m.SRC_KEY
        WHERE s.LREF_HINT IS NOT NULL AND m.ENERGY_LREF IS NULL;

        DELETE FROM dbo.MIG_610_STG_INV WHERE LREF_HINT IS NOT NULL;
        SET @Msg = N'E610 INV LREF_HINT insert=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* IDENTITY batch */
    SET @Total = 0;
    WHILE EXISTS (SELECT 1 FROM dbo.MIG_610_STG_INV WHERE LREF_HINT IS NULL)
    BEGIN
        TRUNCATE TABLE dbo.MIG_610_STG_MAP_OUT;

        BEGIN TRY
            BEGIN TRAN;

            MERGE dbo.LS_005_01_INVOICE WITH (HOLDLOCK) AS t
            USING (
                SELECT TOP (@BatchSize) s.*
                FROM dbo.MIG_610_STG_INV s
                WHERE s.LREF_HINT IS NULL
                ORDER BY s.SRC_KEY
            ) AS s
            ON 1 = 0
            WHEN NOT MATCHED THEN INSERT (
                IOCODE, FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF,
                TLTOTAL, CURID, CURTOTAL, EXPLAIN, CANCELED, OWNERREF, OWNERTYPE,
                TAX, DV, GRANDTOTAL, PRINTCOUNT, PAYABLETOTAL, CLOSED,
                FITNO, BN_TYPE, AMOUNT, PERIOD, HAS_DISCOUNT, DISCOUNT_AMOUNT,
                ADDDATE, ADDUSER,
                ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_AGREEMENT_ID
            ) VALUES (
                s.IOCODE, s.FICHENO, s.DATE_, s.DUEDATE, s.[TYPE], s.CLIENTREF,
                s.TLTOTAL, s.CURID, s.CURTOTAL, s.EXPLAIN, s.CANCELED, s.OWNERREF, s.OWNERTYPE,
                s.TAX, s.DV, s.GRANDTOTAL, s.PRINTCOUNT, s.PAYABLETOTAL, s.CLOSED,
                s.FITNO, s.BN_TYPE, s.AMOUNT, s.PERIOD, s.HAS_DISCOUNT, s.DISCOUNT_AMOUNT,
                s.ADDDATE, s.ADDUSER,
                s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_ACTION_TYPE_ID, s.ABYS_AGREEMENT_ID
            )
            OUTPUT inserted.LREF, s.SRC_KEY INTO dbo.MIG_610_STG_MAP_OUT (ENERGY_LREF, SRC_KEY)
            OPTION (RECOMPILE);

            SET @BatchN = @@ROWCOUNT;

            UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
            FROM dbo.MIG_OV_ID_MAP m
            INNER JOIN dbo.MIG_610_STG_MAP_OUT o ON o.SRC_KEY = m.SRC_KEY
            WHERE m.ENERGY_LREF IS NULL;

            UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
            FROM izgazMGR.dbo.LS_OV_ID_MAP m
            INNER JOIN dbo.MIG_610_STG_MAP_OUT o ON o.SRC_KEY = m.SRC_KEY
            WHERE m.ENERGY_LREF IS NULL;

            DELETE s
            FROM dbo.MIG_610_STG_INV s
            INNER JOIN dbo.MIG_610_STG_MAP_OUT o ON o.SRC_KEY = s.SRC_KEY;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRAN;
            THROW;
        END CATCH;

        SET @Total += @BatchN;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'E610 INV batch +' + CAST(@BatchN AS VARCHAR(20))
                     + N' total=' + CAST(@Total AS VARCHAR(20))
                     + N' left=' + CAST((SELECT COUNT(*) FROM dbo.MIG_610_STG_INV) AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        IF @BatchN = 0 BREAK;
    END

    SET @Msg = CONVERT(VARCHAR(30), SYSDATETIME(), 121)
             + N' | E610 | INFO | INV IDENTITY insert=' + CAST(@Total AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* ---- INVLINES ---- */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVLINES', 'U') IS NULL
    BEGIN
        RAISERROR('E610 | WARN | LS_OV_GUVENCE_IADE_INVLINES yok — IL atlandi', 0, 1) WITH NOWAIT;
        RETURN;
    END

    TRUNCATE TABLE dbo.MIG_610_STG_IL;
    TRUNCATE TABLE dbo.MIG_610_STG_MAP_OUT;

    INSERT INTO dbo.MIG_610_STG_IL (
        SRC_KEY, INVOICE_SRC_KEY, CLIENTREF, DATE_, [TYPE], LINENR, TRANSTYPE,
        AMOUNT, TLTOTAL, TAX, GRANDTOTAL, LINEEXP,
        ABYS_INCOME_ID, PCMS_INCOME_CODE, ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID
    )
    SELECT
        CAST(s.SRC_KEY AS VARCHAR(80)),
        CAST(s.INVOICE_SRC_KEY AS VARCHAR(80)),
        CAST(s.CLIENTREF AS INT),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
        CAST(110 AS TINYINT),
        CAST(s.LINENR AS SMALLINT),
        CAST(ISNULL(s.PCMS_INCOME_CODE, s.ABYS_INCOME_ID) AS INT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.AMOUNT)),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TLTOTAL)),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), ISNULL(s.TAX, 0))),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.GRANDTOTAL)),
        LEFT(s.LINEEXP, 100),
        s.ABYS_INCOME_ID,
        CAST(ISNULL(s.PCMS_INCOME_CODE, 823) AS INT),
        s.ABYS_AGREEMENT_ID,
        s.ABYS_ACCOUNT_ID
    FROM izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVLINES s WITH (NOLOCK)
    WHERE (
          @AGR_ID IS NULL
       OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL)
       OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
        )
      AND NOT EXISTS (
            SELECT 1 FROM dbo.MIG_OV_ID_MAP m
            WHERE m.SRC_KEY = s.SRC_KEY
              AND m.ENERGY_LREF IS NOT NULL
          )
    OPTION (RECOMPILE, MAXDOP 24);

    SET @N = (SELECT COUNT(*) FROM dbo.MIG_610_STG_IL);
    SET @Msg = N'E610 IL pending=' + CAST(@N AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    IF @N > 0 AND EXISTS (
        SELECT 1
        FROM dbo.MIG_610_STG_IL s
        LEFT JOIN dbo.MIG_OV_ID_MAP mi ON mi.SRC_KEY = s.INVOICE_SRC_KEY
        WHERE mi.ENERGY_LREF IS NULL
    )
    BEGIN
        DECLARE @BadParent VARCHAR(80);
        SELECT TOP (1) @BadParent = s.INVOICE_SRC_KEY
        FROM dbo.MIG_610_STG_IL s
        LEFT JOIN dbo.MIG_OV_ID_MAP mi ON mi.SRC_KEY = s.INVOICE_SRC_KEY
        WHERE mi.ENERGY_LREF IS NULL;
        SET @Msg = N'E610 INSERT: parent GUV_IADE ENERGY_LREF yok ' + ISNULL(@BadParent, N'?');
        RAISERROR('%s', 16, 1, @Msg);
        RETURN;
    END

    SET @Total = 0;
    WHILE EXISTS (SELECT 1 FROM dbo.MIG_610_STG_IL)
    BEGIN
        TRUNCATE TABLE dbo.MIG_610_STG_MAP_OUT;

        BEGIN TRY
            BEGIN TRAN;

            IF @HasLineNrSrc = 1
            BEGIN
                MERGE dbo.LS_005_01_INVLINES WITH (HOLDLOCK) AS t
                USING (
                    SELECT TOP (@BatchSize)
                        s.*,
                        mi.ENERGY_LREF AS INVOICEREF
                    FROM dbo.MIG_610_STG_IL s
                    INNER JOIN dbo.MIG_OV_ID_MAP mi ON mi.SRC_KEY = s.INVOICE_SRC_KEY
                    ORDER BY s.SRC_KEY
                ) AS s
                ON 1 = 0
                WHEN NOT MATCHED THEN INSERT (
                    INVOICEREF, CLIENTREF, DATE_, [TYPE], LINENR, TLTOTAL, TRANSTYPE,
                    TAX, GRANDTOTAL, LINEEXP, ABYS_INCOME_ID, ABYS_LINENR_SRC
                ) VALUES (
                    s.INVOICEREF, s.CLIENTREF, s.DATE_, s.[TYPE], s.LINENR, s.TLTOTAL, s.TRANSTYPE,
                    s.TAX, s.GRANDTOTAL, s.LINEEXP, s.ABYS_INCOME_ID, s.LINENR
                )
                OUTPUT inserted.LREF, s.SRC_KEY INTO dbo.MIG_610_STG_MAP_OUT (ENERGY_LREF, SRC_KEY)
                OPTION (RECOMPILE);
            END
            ELSE
            BEGIN
                MERGE dbo.LS_005_01_INVLINES WITH (HOLDLOCK) AS t
                USING (
                    SELECT TOP (@BatchSize)
                        s.*,
                        mi.ENERGY_LREF AS INVOICEREF
                    FROM dbo.MIG_610_STG_IL s
                    INNER JOIN dbo.MIG_OV_ID_MAP mi ON mi.SRC_KEY = s.INVOICE_SRC_KEY
                    ORDER BY s.SRC_KEY
                ) AS s
                ON 1 = 0
                WHEN NOT MATCHED THEN INSERT (
                    INVOICEREF, CLIENTREF, DATE_, [TYPE], LINENR, TLTOTAL, TRANSTYPE,
                    TAX, GRANDTOTAL, LINEEXP, ABYS_INCOME_ID
                ) VALUES (
                    s.INVOICEREF, s.CLIENTREF, s.DATE_, s.[TYPE], s.LINENR, s.TLTOTAL, s.TRANSTYPE,
                    s.TAX, s.GRANDTOTAL, s.LINEEXP, s.ABYS_INCOME_ID
                )
                OUTPUT inserted.LREF, s.SRC_KEY INTO dbo.MIG_610_STG_MAP_OUT (ENERGY_LREF, SRC_KEY)
                OPTION (RECOMPILE);
            END

            SET @BatchN = @@ROWCOUNT;

            UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
            FROM dbo.MIG_OV_ID_MAP m
            INNER JOIN dbo.MIG_610_STG_MAP_OUT o ON o.SRC_KEY = m.SRC_KEY
            WHERE m.ENERGY_LREF IS NULL;

            UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
            FROM izgazMGR.dbo.LS_OV_ID_MAP m
            INNER JOIN dbo.MIG_610_STG_MAP_OUT o ON o.SRC_KEY = m.SRC_KEY
            WHERE m.ENERGY_LREF IS NULL;

            DELETE s
            FROM dbo.MIG_610_STG_IL s
            INNER JOIN dbo.MIG_610_STG_MAP_OUT o ON o.SRC_KEY = s.SRC_KEY;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRAN;
            THROW;
        END CATCH;

        SET @Total += @BatchN;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'E610 IL batch +' + CAST(@BatchN AS VARCHAR(20))
                     + N' total=' + CAST(@Total AS VARCHAR(20))
                     + N' left=' + CAST((SELECT COUNT(*) FROM dbo.MIG_610_STG_IL) AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        IF @BatchN = 0 BREAK;
    END

    SET @Msg = CONVERT(VARCHAR(30), SYSDATETIME(), 121)
             + N' | E610 | INFO | IL insert=' + CAST(@Total AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END
GO
