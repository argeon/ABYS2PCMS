/* ============================================================
   SCRIPT_ID : INVLINES_SETUP
   SCRIPT_NO : 580
   FILE      : 580_INVLINES__setup.sql
   VERSION   : 2
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.LS_INVLINES
--   → energy.dbo.LS_005_01_INVLINES
--
-- Pass 1 dump-style:
--   - Eksik PCMS kolonlari (FIRST_DATE, LAST_DATE, DAY) + ABYS_* TABLO SONUNA
--   - FK / wire YOK (INVOICEREF dump; post/wire ayri)
--   - Unique / NC index YOK (582_INVLINES__post sonrasi)
--   - LREF = kaynak LREF (IDENTITY_INSERT)
--   - ABYS_ID = ABYS_INCOME_ROW_ID
--   - ~800M satir: PREPARE_LOAD FK dus + NC index disable
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_INVLINES', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_005_01_INVLINES bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- Kaynak uzunluklari > hedef: truncation onleme (idempotent)
-- ------------------------------------------------------------
IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVLINES')
      AND c.name = 'LINEEXP'
      AND (TYPE_NAME(c.user_type_id) <> 'nvarchar' OR (c.max_length > 0 AND c.max_length < 600))
)
    ALTER TABLE energy.dbo.LS_005_01_INVLINES ALTER COLUMN LINEEXP NVARCHAR(300) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVLINES')
      AND c.name = 'FITNO'
      AND (TYPE_NAME(c.user_type_id) <> 'nvarchar' OR (c.max_length > 0 AND c.max_length < 200))
)
    ALTER TABLE energy.dbo.LS_005_01_INVLINES ALTER COLUMN FITNO NVARCHAR(100) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVLINES')
      AND c.name = 'LOGO_FICHENO'
      AND (TYPE_NAME(c.user_type_id) <> 'nvarchar' OR (c.max_length > 0 AND c.max_length < 200))
)
    ALTER TABLE energy.dbo.LS_005_01_INVLINES ALTER COLUMN LOGO_FICHENO NVARCHAR(100) NULL;
GO

-- ------------------------------------------------------------
-- Eksik PCMS + ABYS bridge kolonlari — TABLO SONUNA (idempotent)
-- Index / FK burada OLUSTURULMAZ.
-- ------------------------------------------------------------
DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(300) NOT NULL);

INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 -- kaynakta yeni PCMS kolonlari
 (N'FIRST_DATE',               N'DATETIME2(0) NULL'),
 (N'LAST_DATE',                N'DATETIME2(0) NULL'),
 (N'DAY',                      N'SMALLINT NULL'),
 -- ABYS bridge
 (N'ABYS_ID',                  N'BIGINT NULL'),
 (N'ABYS_INCOME_ROW_ID',       N'BIGINT NULL'),
 (N'ABYS_INCOME_ID',           N'BIGINT NULL'),
 (N'ABYS_ACTION_ID',           N'BIGINT NULL'),
 (N'ABYS_ACCOUNT_ID',          N'BIGINT NULL'),
 (N'ABYS_REGISTER_ID',         N'BIGINT NULL'),
 (N'ABYS_AGREEMENT_ID',        N'BIGINT NULL'),
 (N'ABYS_ACTION_TYPE_ID',      N'BIGINT NULL'),
 (N'ABYS_ACCRUE_TYPE_ID',      N'SMALLINT NULL'),
 (N'ABYS_IS_DISCOUNT',         N'DECIMAL(22,0) NULL'),
 (N'ABYS_IS_VAT_INCOME',       N'DECIMAL(22,0) NULL'),
 (N'ABYS_IS_DEPOSIT',          N'DECIMAL(22,0) NULL'),
 (N'ABYS_IS_OVERDUE_INCOME',   N'DECIMAL(22,0) NULL'),
 (N'ABYS_IS_LEGAL_FEE',        N'DECIMAL(22,0) NULL'),
 (N'ABYS_INCOME_CODE',         N'NVARCHAR(10) NULL'),
 (N'ABYS_AMOUNT_RAW',          N'DECIMAL(15,2) NULL'),
 (N'ABYS_STATUS',              N'SMALLINT NULL'),
 (N'ABYS_QUANTITY',            N'DECIMAL(15,3) NULL'),
 (N'ABYS_UNIT_PRICE',          N'DECIMAL(19,8) NULL'),
 (N'ABYS_AMOUNT1',             N'DECIMAL(15,2) NULL'),
 (N'ABYS_AMOUNT2',             N'DECIMAL(15,2) NULL'),
 (N'ABYS_AMOUNT3',             N'DECIMAL(15,2) NULL'),
 (N'ABYS_AMOUNT4',             N'DECIMAL(15,2) NULL'),
 (N'ABYS_AMOUNT5',             N'DECIMAL(15,2) NULL');

SELECT @Sql = @Sql + N'
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(''energy.dbo.LS_005_01_INVLINES'')
      AND name = ''' + COL_NAME + N'''
)
    ALTER TABLE energy.dbo.LS_005_01_INVLINES ADD ' + QUOTENAME(COL_NAME) + N' ' + COL_DEF + N';'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;
GO

-- ------------------------------------------------------------
-- Yukleme oncesi: outbound FK + NC index kaldir/disable
-- (PK clustered kalir. Index/FK 582 post'ta kurulur.)
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVLINES_PREPARE_LOAD
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Sql NVARCHAR(MAX) = N'';
    DECLARE @Msg NVARCHAR(500);

    -- 1) Bu tablodan cikan FK'leri dus (FK → INVOICE vb.)
    SELECT @Sql = @Sql + N'
ALTER TABLE energy.dbo.LS_005_01_INVLINES DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
    FROM sys.foreign_keys fk
    WHERE fk.parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_INVLINES');

    IF LEN(@Sql) > 0
    BEGIN
        IF @DEBUG = 1
            RAISERROR('INVLINES outbound FK drop...', 0, 1) WITH NOWAIT;
        EXEC sp_executesql @Sql;
    END

    -- 2) Bu tabloya gelen FK'leri dus (child → INVLINES)
    SET @Sql = N'';
    SELECT @Sql = @Sql + N'
ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id))
        + N'.' + QUOTENAME(OBJECT_NAME(fk.parent_object_id))
        + N' DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
    FROM sys.foreign_keys fk
    WHERE fk.referenced_object_id = OBJECT_ID('energy.dbo.LS_005_01_INVLINES');

    IF LEN(@Sql) > 0
    BEGIN
        IF @DEBUG = 1
            RAISERROR('INVLINES inbound FK drop...', 0, 1) WITH NOWAIT;
        EXEC sp_executesql @Sql;
    END

    -- 3) NC index disable (clustered PK haric)
    SET @Sql = N'';
    SELECT @Sql = @Sql + N'
ALTER INDEX ' + QUOTENAME(i.name) + N' ON energy.dbo.LS_005_01_INVLINES DISABLE;'
    FROM sys.indexes i
    WHERE i.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVLINES')
      AND i.type_desc = 'NONCLUSTERED'
      AND i.is_disabled = 0
      AND i.name IS NOT NULL;

    IF LEN(@Sql) > 0
    BEGIN
        IF @DEBUG = 1
            RAISERROR('INVLINES NC index DISABLE...', 0, 1) WITH NOWAIT;
        EXEC sp_executesql @Sql;
    END

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'SP_MIG_INVLINES_PREPARE_LOAD OK (FK yok, NC index disabled)';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

-- ------------------------------------------------------------
-- Validate
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVLINES_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_INVLINES', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_INVLINES bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('INVOICEREF'),('CLIENTREF'),('DATE_'),('TYPE'),('LINENR'),
            ('TLTOTAL'),('CURID'),('CURRATE'),('CURTOTAL'),('FIRSTREAD'),('LASTREAD'),
            ('TRANSTYPE'),('CANCELED'),('TAX'),('GRANDTOTAL'),('LINEEXP'),('LINETYPE'),
            ('DV'),('FITNO'),('CNTREF'),('LOGO_FIRMNR'),('LOGO_FICHEREF'),('LOGO_FICHENO'),
            ('XTYPE'),('UNITPRICE'),('SPEREF'),('AMOUNT'),
            ('FIRST_DATE'),('LAST_DATE'),('DAY'),
            ('ABYS_INCOME_ROW_ID'),('ABYS_INCOME_ID'),('ABYS_ACTION_ID'),('ABYS_ACCOUNT_ID'),
            ('ABYS_REGISTER_ID'),('ABYS_AGREEMENT_ID'),('ABYS_ACTION_TYPE_ID'),('ABYS_ACCRUE_TYPE_ID'),
            ('ABYS_IS_DISCOUNT'),('ABYS_IS_VAT_INCOME'),('ABYS_IS_DEPOSIT'),
            ('ABYS_IS_OVERDUE_INCOME'),('ABYS_IS_LEGAL_FEE'),('ABYS_INCOME_CODE'),
            ('ABYS_AMOUNT_RAW'),('ABYS_STATUS'),('ABYS_QUANTITY'),('ABYS_UNIT_PRICE'),
            ('ABYS_AMOUNT1'),('ABYS_AMOUNT2'),('ABYS_AMOUNT3'),('ABYS_AMOUNT4'),('ABYS_AMOUNT5')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'LS_INVLINES' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_INVLINES eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_INVLINES kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVLINES_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_INVLINES', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_INVLINES bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('INVOICEREF'),('CLIENTREF'),('DATE_'),('TYPE'),('LINENR'),
            ('TLTOTAL'),('CURID'),('CURRATE'),('CURTOTAL'),('FIRSTREAD'),('LASTREAD'),
            ('TRANSTYPE'),('CANCELED'),('TAX'),('GRANDTOTAL'),('LINEEXP'),('LINETYPE'),
            ('DV'),('FITNO'),('CNTREF'),('LOGO_FIRMNR'),('LOGO_FICHEREF'),('LOGO_FICHENO'),
            ('XTYPE'),('UNITPRICE'),('SPEREF'),('AMOUNT'),
            ('FIRST_DATE'),('LAST_DATE'),('DAY'),
            ('ABYS_ID'),('ABYS_INCOME_ROW_ID'),('ABYS_INCOME_ID'),('ABYS_ACTION_ID'),('ABYS_ACCOUNT_ID'),
            ('ABYS_REGISTER_ID'),('ABYS_AGREEMENT_ID'),('ABYS_ACTION_TYPE_ID'),('ABYS_ACCRUE_TYPE_ID'),
            ('ABYS_IS_DISCOUNT'),('ABYS_IS_VAT_INCOME'),('ABYS_IS_DEPOSIT'),
            ('ABYS_IS_OVERDUE_INCOME'),('ABYS_IS_LEGAL_FEE'),('ABYS_INCOME_CODE'),
            ('ABYS_AMOUNT_RAW'),('ABYS_STATUS'),('ABYS_QUANTITY'),('ABYS_UNIT_PRICE'),
            ('ABYS_AMOUNT1'),('ABYS_AMOUNT2'),('ABYS_AMOUNT3'),('ABYS_AMOUNT4'),('ABYS_AMOUNT5')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVLINES')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_INVLINES eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_INVLINES hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVLINES_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_INVLINES_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_INVLINES_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    RETURN @Rc;
END
GO

EXEC dbo.SP_MIG_INVLINES_VALIDATE_ALL @RaiseOnMissing = 0;
GO

PRINT '580_INVLINES__setup OK (FK/index yok — post: 582)';
GO
