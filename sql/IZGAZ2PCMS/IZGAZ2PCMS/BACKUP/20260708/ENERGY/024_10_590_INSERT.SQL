/* ============================================================
   prodREADY_ENERGY / 10_590_INSERT  (v3 physical staging / resume)
   IADE INV/IL + KISMI IL + MAIN_UPD (CANCEL; RETURN_TARGET → WIRE)
   MAP.ENERGY_LREF doldurulur. Tek basina cutover YASAK → 19_590_ALL.

   v3:
     - #temp YOK (tempdb CP1 ≠ energy CP1254)
     - Fiziksel: MIG_590_STG_IADE_INV / _IL / _MAP_OUT + index
     - MAP MERGE skip | MERGE…OUTPUT batch | resume ENERGY_LREF
   v3b:
     - KISMI_IL: aritmetik LREF+=50k YOK → MIG_590_STG_KISMI_KEYS keyset batch
   ============================================================ */
USE energy;
GO

/* ---- fiziksel staging (energy collation) ---- */
IF OBJECT_ID('dbo.MIG_590_STG_IADE_INV', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_590_STG_IADE_INV (
        SRC_KEY              VARCHAR(80)  NOT NULL,
        LREF_HINT            INT          NULL,
        IOCODE               TINYINT      NULL,
        FICHENO              VARCHAR(45)  NULL,
        DATE_                DATETIME     NULL,
        DUEDATE              DATETIME     NULL,
        [TYPE]               TINYINT      NULL,
        CLIENTREF            INT          NULL,
        TLTOTAL              FLOAT        NULL,
        CURID                SMALLINT     NULL,
        CURTOTAL             FLOAT        NULL,
        EXPLAIN              NVARCHAR(250) NULL,
        CANCELED             BIT          NULL,
        OWNERREF             INT          NULL,
        OWNERTYPE            TINYINT      NULL,
        TAX                  FLOAT        NULL,
        DV                   FLOAT        NULL,
        GRANDTOTAL           FLOAT        NULL,
        PRINTCOUNT           INT          NULL,
        PAYABLETOTAL         FLOAT        NULL,
        CLOSED               BIT          NULL,
        RETURN_SOURCE_INVREF INT          NULL,
        FITNO                BIGINT       NULL,
        BN_TYPE              INT          NULL,
        AMOUNT               FLOAT        NULL,
        PERIOD               NVARCHAR(40) NULL,
        HAS_DISCOUNT         BIT          NULL,
        DISCOUNT_AMOUNT      FLOAT        NULL,
        ADDDATE              DATETIME     NULL,
        ADDUSER              INT          NULL,
        ABYS_ID              BIGINT       NULL,
        ABYS_ACCOUNT_ID      BIGINT       NULL,
        ABYS_ACTION_TYPE_ID  BIGINT       NULL,
        ABYS_AGREEMENT_ID    BIGINT       NULL,
        CONSTRAINT PK_MIG_590_STG_IADE_INV PRIMARY KEY CLUSTERED (SRC_KEY)
    );
END
GO

IF OBJECT_ID('dbo.MIG_590_STG_IADE_IL', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_590_STG_IADE_IL (
        SRC_KEY           VARCHAR(80)  NOT NULL,
        INVOICE_SRC_KEY   VARCHAR(80)  NOT NULL,
        CLIENTREF         INT          NULL,
        DATE_             DATETIME     NULL,
        [TYPE]            TINYINT      NULL,
        LINENR            SMALLINT     NULL,
        LINENR_SRC        SMALLINT     NULL,
        TRANSTYPE         INT          NULL,
        AMOUNT            FLOAT        NULL,
        TLTOTAL           FLOAT        NULL,
        TAX               FLOAT        NULL,
        GRANDTOTAL        FLOAT        NULL,
        LINEEXP           NVARCHAR(100) NULL,
        ABYS_INCOME_ROW_ID BIGINT      NULL,
        ABYS_INCOME_ID    BIGINT       NULL,
        ABYS_AGREEMENT_ID BIGINT       NULL,
        ABYS_SOURCE_LINE_LREF BIGINT   NULL,
        CONSTRAINT PK_MIG_590_STG_IADE_IL PRIMARY KEY CLUSTERED (SRC_KEY)
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MIG_590_STG_IADE_IL')
      AND name = 'IX_MIG_590_STG_IADE_IL_INV'
)
    CREATE NONCLUSTERED INDEX IX_MIG_590_STG_IADE_IL_INV
        ON dbo.MIG_590_STG_IADE_IL (INVOICE_SRC_KEY);
GO

IF OBJECT_ID('dbo.MIG_590_STG_MAP_OUT', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_590_STG_MAP_OUT (
        ENERGY_LREF INT         NOT NULL,
        SRC_KEY     VARCHAR(80) NOT NULL,
        CONSTRAINT PK_MIG_590_STG_MAP_OUT PRIMARY KEY CLUSTERED (SRC_KEY)
    );
END
GO

/* KISMI_IL keyset staging — boş LREF penceresi yok */
IF OBJECT_ID('dbo.MIG_590_STG_KISMI_KEYS', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_590_STG_KISMI_KEYS (
        LREF BIGINT NOT NULL,
        CONSTRAINT PK_MIG_590_STG_KISMI_KEYS PRIMARY KEY CLUSTERED (LREF)
    );
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_590_INSERT
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

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_ID_MAP', 'U') IS NULL
       OR OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_INVOICE', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR LS_OV_ID_MAP / LS_OV_IADE_INVOICE yok (prodREADY dump).', 16, 1);
        RETURN;
    END

    IF OBJECT_ID('dbo.MIG_590_STG_IADE_INV', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_590_STG_IADE_IL', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_590_STG_MAP_OUT', 'U') IS NULL
       OR OBJECT_ID('dbo.MIG_590_STG_KISMI_KEYS', 'U') IS NULL
    BEGIN
        RAISERROR('MIG_590_STG_* yok — once 10_590_INSERT.sql DDL (staging) deploy.', 16, 1);
        RETURN;
    END

    DECLARE @Msg NVARCHAR(400), @N INT, @BatchN INT, @Total BIGINT;
    DECLARE @Ts VARCHAR(30) = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    DECLARE @MgrCnt BIGINT, @EnCnt BIGINT;
    DECLARE @HasLineNrSrc BIT =
        CASE WHEN COL_LENGTH('dbo.LS_005_01_INVLINES', 'ABYS_LINENR_SRC') IS NOT NULL
             THEN 1 ELSE 0 END;

    /* ---- MAP sync (resume: count esitse atla) ---- */
    SELECT @MgrCnt = COUNT_BIG(*)
    FROM izgazMGR.dbo.LS_OV_ID_MAP WITH (NOLOCK)
    WHERE (
          @AGR_ID IS NULL
       OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
       OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
        );

    SELECT @EnCnt = COUNT_BIG(*)
    FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
    WHERE (
          @AGR_ID IS NULL
       OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
       OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
        );

    IF @MgrCnt > 0 AND @EnCnt >= @MgrCnt
    BEGIN
        SET @Msg = @Ts + N' | E590 | INFO | MAP sync SKIP (en='
                 + CAST(@EnCnt AS VARCHAR(20)) + N' mgr=' + CAST(@MgrCnt AS VARCHAR(20)) + N')';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
    ELSE
    BEGIN
        SET @Msg = @Ts + N' | E590 | INFO | MAP sync MERGE basladi (en='
                 + CAST(@EnCnt AS VARCHAR(20)) + N' mgr=' + CAST(@MgrCnt AS VARCHAR(20)) + N')';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

        MERGE dbo.MIG_OV_ID_MAP AS t
        USING (
            SELECT * FROM izgazMGR.dbo.LS_OV_ID_MAP WITH (NOLOCK)
            WHERE (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
                )
        ) s ON t.SRC_KEY = s.SRC_KEY
        WHEN NOT MATCHED THEN INSERT (
            OV_KIND, SRC_KEY, LREF_HINT, PARENT_SRC_KEY, REF_MAIN_LREF,
            ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID, ABYS_ID_BUSINESS, ENERGY_LREF
        ) VALUES (
            s.OV_KIND,
            s.SRC_KEY,
            s.LREF_HINT,
            s.PARENT_SRC_KEY,
            s.REF_MAIN_LREF,
            s.ABYS_AGREEMENT_ID, s.ABYS_ACCOUNT_ID, s.ABYS_ID_BUSINESS, NULL
        )
        OPTION (RECOMPILE, MAXDOP 24);

        SET @Ts = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
        SET @Msg = @Ts + N' | E590 | INFO | MAP sync MERGE bitti';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    SET @Ts = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    SET @Msg = @Ts + N' | E590 | INFO | INSERT basladi | AGR='
             + CASE WHEN @AGR_ID IS NULL THEN N'FULL' WHEN @AGR_ID = -1 THEN N'NO_AGR' ELSE CAST(@AGR_ID AS NVARCHAR(30)) END
             + N' Batch=' + CAST(@BatchSize AS VARCHAR(10));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* ---- IADE INVOICE staging (physical) ---- */
    TRUNCATE TABLE dbo.MIG_590_STG_IADE_INV;
    TRUNCATE TABLE dbo.MIG_590_STG_MAP_OUT;

    INSERT INTO dbo.MIG_590_STG_IADE_INV (
        SRC_KEY, LREF_HINT, IOCODE, FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF,
        TLTOTAL, CURID, CURTOTAL, EXPLAIN, CANCELED, OWNERREF, OWNERTYPE,
        TAX, DV, GRANDTOTAL, PRINTCOUNT, PAYABLETOTAL, CLOSED,
        RETURN_SOURCE_INVREF, FITNO, BN_TYPE, AMOUNT, PERIOD, HAS_DISCOUNT, DISCOUNT_AMOUNT,
        ADDDATE, ADDUSER, ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_AGREEMENT_ID
    )
    SELECT
        CAST(s.SRC_KEY AS VARCHAR(80)),
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
        CAST(0 AS BIT),
        CAST(s.OWNERREF AS INT),
        CAST(ISNULL(s.OWNERTYPE, 91) AS TINYINT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TAX)),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), ISNULL(s.DV, 0))),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.GRANDTOTAL)),
        CAST(ISNULL(s.PRINTCOUNT, 0) AS INT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
        CAST(1 AS BIT),
        CAST(s.RETURN_SOURCE_INVREF AS INT),
        TRY_CAST(s.FITNO AS BIGINT),
        TRY_CAST(s.BN_TYPE AS INT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), COALESCE(s.AMOUNT, s.PAYABLETOTAL))),
        LEFT(CONVERT(NVARCHAR(40), s.PERIOD), 40),
        CAST(ISNULL(s.HAS_DISCOUNT, 0) AS BIT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), ISNULL(s.DISCOUNT_AMOUNT, 0))),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ADDDATE AS DATETIME2)),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.ADDUSER AS INT)),
        s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_ACTION_TYPE_ID, s.ABYS_AGREEMENT_ID
    FROM izgazMGR.dbo.LS_OV_IADE_INVOICE s WITH (NOLOCK)
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

    SET @N = (SELECT COUNT(*) FROM dbo.MIG_590_STG_IADE_INV);
    SET @Msg = N'590 INSERT IADE_INV pending=' + CAST(@N AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* LREF_HINT path */
    IF EXISTS (SELECT 1 FROM dbo.MIG_590_STG_IADE_INV WHERE LREF_HINT IS NOT NULL)
    BEGIN
        SET IDENTITY_INSERT dbo.LS_005_01_INVOICE ON;
        BEGIN TRY
            INSERT INTO dbo.LS_005_01_INVOICE (
                LREF, IOCODE, FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF,
                TLTOTAL, CURID, CURTOTAL, EXPLAIN, CANCELED, OWNERREF, OWNERTYPE,
                TAX, DV, GRANDTOTAL, PRINTCOUNT, PAYABLETOTAL, CLOSED,
                RETURN_SOURCE_INVREF, RETURN_TARGET_INVREF,
                FITNO, BN_TYPE, AMOUNT, PERIOD, HAS_DISCOUNT, DISCOUNT_AMOUNT,
                ADDDATE, ADDUSER,
                ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_AGREEMENT_ID
            )
            SELECT
                s.LREF_HINT, s.IOCODE, s.FICHENO, s.DATE_, s.DUEDATE, s.[TYPE], s.CLIENTREF,
                s.TLTOTAL, s.CURID, s.CURTOTAL, s.EXPLAIN, s.CANCELED, s.OWNERREF, s.OWNERTYPE,
                s.TAX, s.DV, s.GRANDTOTAL, s.PRINTCOUNT, s.PAYABLETOTAL, s.CLOSED,
                s.RETURN_SOURCE_INVREF, NULL,
                s.FITNO, s.BN_TYPE, s.AMOUNT, s.PERIOD, s.HAS_DISCOUNT, s.DISCOUNT_AMOUNT,
                s.ADDDATE, s.ADDUSER,
                s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_ACTION_TYPE_ID, s.ABYS_AGREEMENT_ID
            FROM dbo.MIG_590_STG_IADE_INV s
            WHERE s.LREF_HINT IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1 FROM dbo.LS_005_01_INVOICE t WHERE t.LREF = s.LREF_HINT
                  )
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
        INNER JOIN dbo.MIG_590_STG_IADE_INV s ON s.SRC_KEY = m.SRC_KEY
        WHERE s.LREF_HINT IS NOT NULL AND m.ENERGY_LREF IS NULL;

        UPDATE m SET m.ENERGY_LREF = s.LREF_HINT
        FROM izgazMGR.dbo.LS_OV_ID_MAP m
        INNER JOIN dbo.MIG_590_STG_IADE_INV s ON s.SRC_KEY = m.SRC_KEY
        WHERE s.LREF_HINT IS NOT NULL AND m.ENERGY_LREF IS NULL;

        DELETE FROM dbo.MIG_590_STG_IADE_INV WHERE LREF_HINT IS NOT NULL;

        SET @Msg = N'590 INSERT IADE_INV LREF_HINT insert=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* IDENTITY — MERGE OUTPUT batch */
    SET @Total = 0;
    WHILE EXISTS (SELECT 1 FROM dbo.MIG_590_STG_IADE_INV WHERE LREF_HINT IS NULL)
    BEGIN
        TRUNCATE TABLE dbo.MIG_590_STG_MAP_OUT;

        BEGIN TRY
            BEGIN TRAN;

            MERGE dbo.LS_005_01_INVOICE WITH (HOLDLOCK) AS t
            USING (
                SELECT TOP (@BatchSize) s.*
                FROM dbo.MIG_590_STG_IADE_INV s
                WHERE s.LREF_HINT IS NULL
                ORDER BY s.SRC_KEY
            ) AS s
            ON 1 = 0
            WHEN NOT MATCHED THEN INSERT (
                IOCODE, FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF,
                TLTOTAL, CURID, CURTOTAL, EXPLAIN, CANCELED, OWNERREF, OWNERTYPE,
                TAX, DV, GRANDTOTAL, PRINTCOUNT, PAYABLETOTAL, CLOSED,
                RETURN_SOURCE_INVREF, RETURN_TARGET_INVREF,
                FITNO, BN_TYPE, AMOUNT, PERIOD, HAS_DISCOUNT, DISCOUNT_AMOUNT,
                ADDDATE, ADDUSER,
                ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_AGREEMENT_ID
            ) VALUES (
                s.IOCODE, s.FICHENO, s.DATE_, s.DUEDATE, s.[TYPE], s.CLIENTREF,
                s.TLTOTAL, s.CURID, s.CURTOTAL, s.EXPLAIN, s.CANCELED, s.OWNERREF, s.OWNERTYPE,
                s.TAX, s.DV, s.GRANDTOTAL, s.PRINTCOUNT, s.PAYABLETOTAL, s.CLOSED,
                s.RETURN_SOURCE_INVREF, NULL,
                s.FITNO, s.BN_TYPE, s.AMOUNT, s.PERIOD, s.HAS_DISCOUNT, s.DISCOUNT_AMOUNT,
                s.ADDDATE, s.ADDUSER,
                s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_ACTION_TYPE_ID, s.ABYS_AGREEMENT_ID
            )
            OUTPUT inserted.LREF, s.SRC_KEY INTO dbo.MIG_590_STG_MAP_OUT (ENERGY_LREF, SRC_KEY)
            OPTION (RECOMPILE);

            SET @BatchN = @@ROWCOUNT;

            UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
            FROM dbo.MIG_OV_ID_MAP m
            INNER JOIN dbo.MIG_590_STG_MAP_OUT o ON o.SRC_KEY = m.SRC_KEY
            WHERE m.ENERGY_LREF IS NULL;

            UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
            FROM izgazMGR.dbo.LS_OV_ID_MAP m
            INNER JOIN dbo.MIG_590_STG_MAP_OUT o ON o.SRC_KEY = m.SRC_KEY
            WHERE m.ENERGY_LREF IS NULL;

            DELETE s
            FROM dbo.MIG_590_STG_IADE_INV s
            INNER JOIN dbo.MIG_590_STG_MAP_OUT o ON o.SRC_KEY = s.SRC_KEY;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRAN;
            THROW;
        END CATCH;

        SET @Total += @BatchN;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'590 IADE_INV batch +' + CAST(@BatchN AS VARCHAR(20))
                     + N' total=' + CAST(@Total AS VARCHAR(20))
                     + N' left=' + CAST((SELECT COUNT(*) FROM dbo.MIG_590_STG_IADE_INV) AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        IF @BatchN = 0 BREAK;
    END

    SET @Ts = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    SET @Msg = @Ts + N' | E590 | INFO | IADE_INV IDENTITY insert=' + CAST(@Total AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* MAIN_UPD */
    UPDATE inv
    SET inv.CANCEL_DATE = energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(u.CANCEL_DATE AS DATETIME2)),
        inv.CANCEL_REASON_ID = CAST(u.CANCEL_REASON_ID AS INT),
        inv.CANCEL_USER_ID = energy.dbo.FN_MIG_MAP_USER_USERID(CAST(u.CANCEL_USER_ID AS INT)),
        inv.CLOSED = CAST(1 AS BIT),
        inv.CANCELED = CAST(0 AS BIT)
    FROM dbo.LS_005_01_INVOICE inv
    INNER JOIN izgazMGR.dbo.LS_OV_MAIN_UPD u WITH (NOLOCK)
        ON inv.LREF = CAST(u.LREF AS INT)
    WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND u.ABYS_AGREEMENT_ID IS NULL)
           OR (@AGR_ID > 0 AND u.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'590 INSERT MAIN_UPD(cancel)=' + CAST(@@ROWCOUNT AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* ---- IADE INVLINES staging (physical) ---- */
    TRUNCATE TABLE dbo.MIG_590_STG_IADE_IL;
    TRUNCATE TABLE dbo.MIG_590_STG_MAP_OUT;

    INSERT INTO dbo.MIG_590_STG_IADE_IL (
        SRC_KEY, INVOICE_SRC_KEY, CLIENTREF, DATE_, [TYPE], LINENR, LINENR_SRC, TRANSTYPE,
        AMOUNT, TLTOTAL, TAX, GRANDTOTAL, LINEEXP,
        ABYS_INCOME_ROW_ID, ABYS_INCOME_ID, ABYS_AGREEMENT_ID, ABYS_SOURCE_LINE_LREF
    )
    SELECT
        CAST(s.SRC_KEY AS VARCHAR(80)),
        CAST(s.INVOICE_SRC_KEY AS VARCHAR(80)),
        CAST(s.CLIENTREF AS INT),
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
        CAST(s.[TYPE] AS TINYINT),
        CAST(s.LINENR AS SMALLINT),
        CAST(s.LINENR_SRC AS SMALLINT),
        CAST(s.TRANSTYPE AS INT),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.AMOUNT)),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TLTOTAL)),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TAX)),
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.GRANDTOTAL)),
        LEFT(s.LINEEXP, 100),
        s.ABYS_INCOME_ROW_ID, s.ABYS_INCOME_ID,
        s.ABYS_AGREEMENT_ID, s.ABYS_SOURCE_LINE_LREF
    FROM izgazMGR.dbo.LS_OV_IADE_INVLINES s WITH (NOLOCK)
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

    SET @N = (SELECT COUNT(*) FROM dbo.MIG_590_STG_IADE_IL);
    SET @Msg = N'590 INSERT IADE_IL pending=' + CAST(@N AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    IF EXISTS (
        SELECT 1
        FROM dbo.MIG_590_STG_IADE_IL s
        LEFT JOIN dbo.MIG_OV_ID_MAP mi ON mi.SRC_KEY = s.INVOICE_SRC_KEY
        WHERE mi.ENERGY_LREF IS NULL
    )
    BEGIN
        DECLARE @BadParent VARCHAR(80);
        SELECT TOP (1) @BadParent = s.INVOICE_SRC_KEY
        FROM dbo.MIG_590_STG_IADE_IL s
        LEFT JOIN dbo.MIG_OV_ID_MAP mi ON mi.SRC_KEY = s.INVOICE_SRC_KEY
        WHERE mi.ENERGY_LREF IS NULL;

        SET @Msg = N'590 INSERT: parent IADE ENERGY_LREF yok ' + ISNULL(@BadParent, N'?');
        RAISERROR('%s', 16, 1, @Msg);
        RETURN;
    END

    SET @Total = 0;
    WHILE EXISTS (SELECT 1 FROM dbo.MIG_590_STG_IADE_IL)
    BEGIN
        TRUNCATE TABLE dbo.MIG_590_STG_MAP_OUT;

        BEGIN TRY
            BEGIN TRAN;

            IF @HasLineNrSrc = 1
            BEGIN
                MERGE dbo.LS_005_01_INVLINES WITH (HOLDLOCK) AS t
                USING (
                    SELECT TOP (@BatchSize)
                        s.SRC_KEY, s.CLIENTREF, s.DATE_, s.[TYPE], s.LINENR, s.LINENR_SRC,
                        s.TRANSTYPE, s.AMOUNT, s.TLTOTAL, s.TAX, s.GRANDTOTAL, s.LINEEXP,
                        s.ABYS_AGREEMENT_ID,
                        mi.ENERGY_LREF AS INVOICE_LREF
                    FROM dbo.MIG_590_STG_IADE_IL s
                    INNER JOIN dbo.MIG_OV_ID_MAP mi ON mi.SRC_KEY = s.INVOICE_SRC_KEY
                    WHERE mi.ENERGY_LREF IS NOT NULL
                    ORDER BY s.SRC_KEY
                ) AS s
                ON 1 = 0
                WHEN NOT MATCHED THEN INSERT (
                    INVOICEREF, CLIENTREF, DATE_, [TYPE], LINENR, TRANSTYPE,
                    AMOUNT, TLTOTAL, TAX, GRANDTOTAL, LINEEXP,
                    ABYS_ID, ABYS_AGREEMENT_ID, ABYS_LINENR_SRC
                ) VALUES (
                    s.INVOICE_LREF, s.CLIENTREF, s.DATE_, s.[TYPE], s.LINENR, s.TRANSTYPE,
                    s.AMOUNT, s.TLTOTAL, s.TAX, s.GRANDTOTAL, s.LINEEXP,
                    NULL, s.ABYS_AGREEMENT_ID, s.LINENR_SRC
                )
                OUTPUT inserted.LREF, s.SRC_KEY INTO dbo.MIG_590_STG_MAP_OUT (ENERGY_LREF, SRC_KEY)
                OPTION (RECOMPILE);
            END
            ELSE
            BEGIN
                MERGE dbo.LS_005_01_INVLINES WITH (HOLDLOCK) AS t
                USING (
                    SELECT TOP (@BatchSize)
                        s.SRC_KEY, s.CLIENTREF, s.DATE_, s.[TYPE], s.LINENR,
                        s.TRANSTYPE, s.AMOUNT, s.TLTOTAL, s.TAX, s.GRANDTOTAL, s.LINEEXP,
                        s.ABYS_AGREEMENT_ID,
                        mi.ENERGY_LREF AS INVOICE_LREF
                    FROM dbo.MIG_590_STG_IADE_IL s
                    INNER JOIN dbo.MIG_OV_ID_MAP mi ON mi.SRC_KEY = s.INVOICE_SRC_KEY
                    WHERE mi.ENERGY_LREF IS NOT NULL
                    ORDER BY s.SRC_KEY
                ) AS s
                ON 1 = 0
                WHEN NOT MATCHED THEN INSERT (
                    INVOICEREF, CLIENTREF, DATE_, [TYPE], LINENR, TRANSTYPE,
                    AMOUNT, TLTOTAL, TAX, GRANDTOTAL, LINEEXP,
                    ABYS_ID, ABYS_AGREEMENT_ID
                ) VALUES (
                    s.INVOICE_LREF, s.CLIENTREF, s.DATE_, s.[TYPE], s.LINENR, s.TRANSTYPE,
                    s.AMOUNT, s.TLTOTAL, s.TAX, s.GRANDTOTAL, s.LINEEXP,
                    NULL, s.ABYS_AGREEMENT_ID
                )
                OUTPUT inserted.LREF, s.SRC_KEY INTO dbo.MIG_590_STG_MAP_OUT (ENERGY_LREF, SRC_KEY)
                OPTION (RECOMPILE);
            END

            SET @BatchN = @@ROWCOUNT;

            UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
            FROM dbo.MIG_OV_ID_MAP m
            INNER JOIN dbo.MIG_590_STG_MAP_OUT o ON o.SRC_KEY = m.SRC_KEY
            WHERE m.ENERGY_LREF IS NULL;

            UPDATE m SET m.ENERGY_LREF = o.ENERGY_LREF
            FROM izgazMGR.dbo.LS_OV_ID_MAP m
            INNER JOIN dbo.MIG_590_STG_MAP_OUT o ON o.SRC_KEY = m.SRC_KEY
            WHERE m.ENERGY_LREF IS NULL;

            DELETE s
            FROM dbo.MIG_590_STG_IADE_IL s
            INNER JOIN dbo.MIG_590_STG_MAP_OUT o ON o.SRC_KEY = s.SRC_KEY;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRAN;
            THROW;
        END CATCH;

        SET @Total += @BatchN;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'590 IADE_IL batch +' + CAST(@BatchN AS VARCHAR(20))
                     + N' total=' + CAST(@Total AS VARCHAR(20))
                     + N' left=' + CAST((SELECT COUNT(*) FROM dbo.MIG_590_STG_IADE_IL) AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        IF @BatchN = 0 BREAK;
    END

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'590 INSERT IADE_IL=' + CAST(@Total AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* KISMI INVLINES — v3b keyset STG (MIG_590_STG_KISMI_KEYS); boş pencere YOK */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_KISMI_INVLINES', 'U') IS NOT NULL
    BEGIN
        DECLARE @KismiBatch INT = CASE WHEN @BatchSize < 50000 THEN 50000 ELSE @BatchSize END;
        DECLARE @KismiLast BIGINT = 0;
        DECLARE @KismiBatchTo BIGINT;
        DECLARE @KismiTotal BIGINT = 0;
        DECLARE @KismiN INT;
        DECLARE @KismiKeys INT;

        IF @DEBUG = 1
            RAISERROR('590 KISMI_IL keyset STG basladi (batch=%d)', 0, 1, @KismiBatch) WITH NOWAIT;

        WHILE 1 = 1
        BEGIN
            TRUNCATE TABLE dbo.MIG_590_STG_KISMI_KEYS;

            INSERT INTO dbo.MIG_590_STG_KISMI_KEYS (LREF)
            SELECT TOP (@KismiBatch) s.LREF
            FROM izgazMGR.dbo.LS_OV_KISMI_INVLINES s WITH (NOLOCK)
            WHERE s.LREF > @KismiLast
              AND s.LREF BETWEEN 1 AND 2147483647
              AND (
                    @AGR_ID IS NULL
                 OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL)
                 OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
                  )
            ORDER BY s.LREF ASC
            OPTION (RECOMPILE);

            SET @KismiKeys = @@ROWCOUNT;
            IF @KismiKeys = 0 BREAK;

            SELECT @KismiBatchTo = MAX(LREF) FROM dbo.MIG_590_STG_KISMI_KEYS;

            SET IDENTITY_INSERT dbo.LS_005_01_INVLINES ON;
            BEGIN TRY
                INSERT INTO dbo.LS_005_01_INVLINES (
                    LREF, INVOICEREF, CLIENTREF, DATE_, [TYPE], LINENR, TRANSTYPE,
                    AMOUNT, TLTOTAL, TAX, GRANDTOTAL, LINEEXP,
                    ABYS_ID, ABYS_AGREEMENT_ID
                )
                SELECT
                    CAST(s.LREF AS INT),
                    CAST(s.INVOICEREF AS INT),
                    CAST(s.CLIENTREF AS INT),
                    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
                    CAST(s.[TYPE] AS TINYINT),
                    CAST(s.LINENR AS SMALLINT),
                    CAST(s.TRANSTYPE AS INT),
                    CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.AMOUNT)),
                    CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TLTOTAL)),
                    CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TAX)),
                    CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.GRANDTOTAL)),
                    LEFT(REPLACE(
                        ISNULL(NULLIF(LTRIM(RTRIM(s.LINEEXP)), ''), N'Kısmi Eksilten'),
                        N'Kismi Eksilten', N'Kısmi Eksilten'), 100),
                    s.ABYS_INCOME_ROW_ID,
                    s.ABYS_AGREEMENT_ID
                FROM dbo.MIG_590_STG_KISMI_KEYS k
                INNER JOIN izgazMGR.dbo.LS_OV_KISMI_INVLINES s WITH (NOLOCK)
                    ON s.LREF = k.LREF
                WHERE NOT EXISTS (
                        SELECT 1 FROM dbo.LS_005_01_INVLINES t WHERE t.LREF = CAST(s.LREF AS INT)
                      )
                OPTION (RECOMPILE, MAXDOP 48);
                SET @KismiN = @@ROWCOUNT;
            END TRY
            BEGIN CATCH
                BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVLINES OFF; END TRY BEGIN CATCH END CATCH;
                SET @Msg = N'590 KISMI_IL keyset FAIL after LREF>' + CAST(@KismiLast AS NVARCHAR(20))
                         + N': ' + ERROR_MESSAGE();
                RAISERROR('%s', 16, 1, @Msg);
                RETURN;
            END CATCH
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVLINES OFF; END TRY BEGIN CATCH END CATCH;

            SET @KismiTotal += @KismiN;
            SET @KismiLast = @KismiBatchTo;

            IF @DEBUG = 1
            BEGIN
                SET @Msg = N'590 KISMI_IL keyset LREF<=' + CAST(@KismiLast AS NVARCHAR(20))
                         + N' keys=' + CAST(@KismiKeys AS NVARCHAR(20))
                         + N' +' + CAST(@KismiN AS NVARCHAR(20))
                         + N' total=' + CAST(@KismiTotal AS NVARCHAR(20));
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END
        END

        UPDATE m SET m.ENERGY_LREF = CAST(s.LREF AS INT)
        FROM dbo.MIG_OV_ID_MAP m
        INNER JOIN izgazMGR.dbo.LS_OV_KISMI_INVLINES s
            ON m.OV_KIND = 'KISMI_IL'
           AND m.LREF_HINT = CAST(s.LREF AS BIGINT)
        WHERE m.ENERGY_LREF IS NULL
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 48);

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'590 INSERT KISMI_IL=' + CAST(@KismiTotal AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* KISMI HDR */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_KISMI_HDR', 'U') IS NOT NULL
    BEGIN
        UPDATE inv
        SET inv.TLTOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.TLTOTAL)),
            inv.TAX = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.TAX)),
            inv.GRANDTOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.GRANDTOTAL)),
            inv.PAYABLETOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), h.PAYABLETOTAL)),
            inv.EXPLAIN = LEFT(
                CASE WHEN inv.EXPLAIN IS NULL OR LTRIM(RTRIM(inv.EXPLAIN)) = ''
                     THEN h.EXPLAIN_NOTE
                     ELSE inv.EXPLAIN + N' | ' + (h.EXPLAIN_NOTE) END, 250)
        FROM dbo.LS_005_01_INVOICE inv
        INNER JOIN izgazMGR.dbo.LS_OV_KISMI_HDR h WITH (NOLOCK)
            ON inv.LREF = CAST(h.LREF AS INT)
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND h.ABYS_AGREEMENT_ID IS NULL)
           OR (@AGR_ID > 0 AND h.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'590 INSERT KISMI_HDR=' + CAST(@@ROWCOUNT AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    SET @Ts = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    SET @Msg = @Ts + N' | E590 | INFO | INSERT bitti — sonraki WIRE zorunlu';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END
GO
