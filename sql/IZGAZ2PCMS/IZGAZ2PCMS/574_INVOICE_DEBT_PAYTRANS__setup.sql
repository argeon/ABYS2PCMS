/* ============================================================
   SCRIPT_ID : INVOICE_DEBT_PAYTRANS_SETUP
   SCRIPT_NO : 574
   FILE      : 574_INVOICE_DEBT_PAYTRANS__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- energy.dbo.LS_005_01_INVOICE  (IOCODE=0 tahakkuk)
--   → energy.dbo.LS_005_01_PAYTRANS  (borç PT, IOCODE=0)
--
-- Pass 1 dump-style:
--   - 1 invoice → 1 borç PAYTRANS (wire / FK / JOIN yok)
--   - ABYS_* bridge kolonlari TABLO SONUNA eklenir
--   - Unique / NC index YOK (576 post sonrasi)
--   - LREF = IDENTITY (auto); INVOICEREF = invoice.LREF
--   - ABYS_ID = invoice.ABYS_ID (migrasyon isareti)
--   - ~74M satir: PREPARE_LOAD FK dus + NC index disable
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_005_01_PAYTRANS bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

IF OBJECT_ID('energy.dbo.LS_005_01_INVOICE', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_005_01_INVOICE bulunamadi. Once 570/571 INVOICE aktarimini tamamlayin.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- ABYS bridge kolonlari — TABLO SONUNA (idempotent)
-- Index / FK burada OLUSTURULMAZ.
-- ------------------------------------------------------------
DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(300) NOT NULL);

INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 (N'ABYS_ID',                 N'BIGINT NULL'),
 (N'ABYS_ACCOUNT_ID',         N'BIGINT NULL'),
 (N'ABYS_ACTION_TYPE_ID',     N'BIGINT NULL'),
 (N'ABYS_ACCRUE_TYPE_ID',     N'SMALLINT NULL'),
 (N'ABYS_REGISTER_ID',        N'BIGINT NULL'),
 (N'ABYS_AGREEMENT_ID',       N'BIGINT NULL'),
 (N'ABYS_INVOICE_LREF',       N'INT NULL'),
 (N'ABYS_ADDUSER',            N'BIGINT NULL'),
 (N'ABYS_UPDUSER',            N'BIGINT NULL');

SELECT @Sql = @Sql + N'
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(''energy.dbo.LS_005_01_PAYTRANS'')
      AND name = ''' + COL_NAME + N'''
)
    ALTER TABLE energy.dbo.LS_005_01_PAYTRANS ADD ' + COL_NAME + N' ' + COL_DEF + N';'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;
GO

-- ------------------------------------------------------------
-- Yukleme oncesi: outbound FK + NC index kaldir/disable
-- (PK clustered kalir. Index/FK 576 post'ta kurulur.)
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Sql NVARCHAR(MAX) = N'';
    DECLARE @Msg NVARCHAR(500);

    SELECT @Sql = @Sql + N'
ALTER TABLE energy.dbo.LS_005_01_PAYTRANS DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
    FROM sys.foreign_keys fk
    WHERE fk.parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS');

    IF LEN(@Sql) > 0
    BEGIN
        IF @DEBUG = 1
            RAISERROR('DEBT_PAYTRANS outbound FK drop...', 0, 1) WITH NOWAIT;
        EXEC sp_executesql @Sql;
    END

    SET @Sql = N'';
    SELECT @Sql = @Sql + N'
ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id))
        + N'.' + QUOTENAME(OBJECT_NAME(fk.parent_object_id))
        + N' DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
    FROM sys.foreign_keys fk
    WHERE fk.referenced_object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS');

    IF LEN(@Sql) > 0
    BEGIN
        IF @DEBUG = 1
            RAISERROR('DEBT_PAYTRANS inbound FK drop...', 0, 1) WITH NOWAIT;
        EXEC sp_executesql @Sql;
    END

    SET @Sql = N'';
    SELECT @Sql = @Sql + N'
ALTER INDEX ' + QUOTENAME(i.name) + N' ON energy.dbo.LS_005_01_PAYTRANS DISABLE;'
    FROM sys.indexes i
    WHERE i.object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
      AND i.type_desc = 'NONCLUSTERED'
      AND i.is_disabled = 0
      AND i.name IS NOT NULL;

    IF LEN(@Sql) > 0
    BEGIN
        IF @DEBUG = 1
            RAISERROR('DEBT_PAYTRANS NC index DISABLE...', 0, 1) WITH NOWAIT;
        EXEC sp_executesql @Sql;
    END

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD OK (FK yok, NC index disabled)';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

-- ------------------------------------------------------------
-- Validate
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_DEBT_PAYTRANS_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_INVOICE', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_INVOICE bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('IOCODE'),('DATE_'),('DUEDATE'),('TYPE'),('CLIENTREF'),('OWNERTYPE'),
            ('TLTOTAL'),('CURID'),('CURTOTAL'),('CANCELED'),('TAX'),('DV'),('GRANDTOTAL'),
            ('PAYABLETOTAL'),('ADDDATE'),('ADDUSER'),('BN_TYPE'),('XTYPE'),('IS_LAW'),
            ('ABYS_ID'),('ABYS_ACCOUNT_ID'),('ABYS_ACTION_TYPE_ID'),('ABYS_ACCRUE_TYPE_ID'),
            ('ABYS_REGISTER_ID'),('ABYS_AGREEMENT_ID'),('ABYS_ADDUSER'),('ABYS_UPDUSER')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_INVOICE eksik kolonlar (debt PT kaynak): ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_INVOICE kaynak dogrulama OK (debt PT)' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_DEBT_PAYTRANS_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_PAYTRANS bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('INVOICEREF'),('INVLINEREF'),('DATE_'),('TYPE'),('CLIENTREF'),('CLIENT_TYPE'),
            ('IOCODE'),('TLTOTAL'),('PAID'),('DUEDATE'),('PAYTYPE'),('CURID'),('CURRATE'),('CURTOTAL'),
            ('CROSSREF'),('TRANSTYPE'),('CANCELED'),('AGRPAYLINEREF'),('LOGOREF'),('TAX'),('GRANDTOTAL'),
            ('LINETYPE'),('INST_NR'),('DV'),('PAYABLETOTAL'),('EXPENDINVREF'),('CALC_FINE'),('CERTLINKREF'),
            ('ADDDATE'),('ADDUSER'),('CANCELLATIONPAYMENT'),('BANKREF'),('BANKACCREF'),('BN_TYPE'),
            ('PROJECTLINEREF'),('ISDVFREE'),('XTYPE'),('IS_LAW'),('PAYCURID'),
            ('ABYS_ID'),('ABYS_ACCOUNT_ID'),('ABYS_ACTION_TYPE_ID'),('ABYS_ACCRUE_TYPE_ID'),
            ('ABYS_REGISTER_ID'),('ABYS_AGREEMENT_ID'),('ABYS_INVOICE_LREF'),
            ('ABYS_ADDUSER'),('ABYS_UPDUSER')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_PAYTRANS eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_PAYTRANS hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_DEBT_PAYTRANS_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_DEBT_PAYTRANS_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_DEBT_PAYTRANS_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    RETURN @Rc;
END
GO

EXEC dbo.SP_MIG_DEBT_PAYTRANS_VALIDATE_ALL @RaiseOnMissing = 0;
GO

PRINT '574_INVOICE_DEBT_PAYTRANS__setup OK (FK/index yok — post: 576)';
GO
