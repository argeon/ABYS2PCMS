/* ============================================================
   SCRIPT_ID : INSTALLMENT_INCOME_SETUP
   SCRIPT_NO : 615
   FILE      : 615_INSTALLMENT_INCOME__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.CS_INSTALLMENT_INCOME
--   → energy.dbo.LS_005_01_INSTALLMENT_INCOME
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_INSTALLMENT_INCOME', 'U') IS NULL
BEGIN
    CREATE TABLE energy.dbo.LS_005_01_INSTALLMENT_INCOME (
        LREF                 INT IDENTITY(1,1) NOT NULL,
        INSTALLMENT_PLAN_REF INT NULL,
        ACCOUNT_REF          INT NULL,
        INCOME_ID            INT NULL,
        AMOUNT               DECIMAL(18,2) NULL,
        STATUS               SMALLINT NULL,
        PAYMENT_DATE         DATETIME NULL,
        CASH_ID              INT NULL,
        RECEIPT_SERIAL       NVARCHAR(10) NULL,
        RECEIPT_NUMBER       DECIMAL(25,0) NULL,
        ADDDATE              DATETIME NULL,
        ADDUSER              INT NULL,
        UPDDATE              DATETIME NULL,
        UPDUSER              INT NULL,
        CONSTRAINT PK_LS_005_01_INSTALLMENT_INCOME PRIMARY KEY (LREF)
    );
END
GO

DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(300) NOT NULL);

INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 (N'ABYS_ID',                  N'BIGINT NULL'),
 (N'ABYS_INSTALLMENT_PLAN_ID', N'BIGINT NULL'),
 (N'ABYS_ACCOUNT_ID',          N'BIGINT NULL'),
 (N'ABYS_INCOME_ID',           N'BIGINT NULL'),
 (N'ABYS_ABONE_NO',            N'BIGINT NULL'),
 (N'ABYS_SISTEM_KODU',         N'SMALLINT NULL'),
 (N'ABYS_DONEM',               N'BIGINT NULL'),
 (N'ABYS_SON_ODEME_TARIHI',    N'DATETIME NULL'),
 (N'ABYS_SIRA_NO',             N'BIGINT NULL'),
 (N'ABYS_SICIL_KODU',          N'BIGINT NULL');

SELECT @Sql = @Sql + N'
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(''energy.dbo.LS_005_01_INSTALLMENT_INCOME'')
      AND name = ''' + COL_NAME + N'''
)
    ALTER TABLE energy.dbo.LS_005_01_INSTALLMENT_INCOME ADD ' + COL_NAME + N' ' + COL_DEF + N';'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INSTALLMENT_INCOME')
      AND name = 'UX_LS005_INSTALLMENT_INCOME_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS005_INSTALLMENT_INCOME_ABYS_ID
        ON energy.dbo.LS_005_01_INSTALLMENT_INCOME (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INSTALLMENT_INCOME')
      AND name = 'IX_LS005_INSTALLMENT_INCOME_PLAN'
)
    CREATE NONCLUSTERED INDEX IX_LS005_INSTALLMENT_INCOME_PLAN
        ON energy.dbo.LS_005_01_INSTALLMENT_INCOME (INSTALLMENT_PLAN_REF)
        INCLUDE (STATUS, AMOUNT, ABYS_INCOME_ID);
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_INCOME_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.CS_INSTALLMENT_INCOME', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.CS_INSTALLMENT_INCOME bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('ID'),('INSTALLMENT_PLAN_ID'),('ACCOUNT_ID'),('INCOME_ID'),
            ('AMOUNT'),('STATUS'),('PAYMENT_DATE'),('CASH_ID'),
            ('RECEIPT_SERIAL'),('RECEIPT_NUMBER'),
            ('ABONE_NO_'),('SISTEM_KODU_'),('DONEM_'),
            ('SON_ODEME_TARIHI_'),('SIRA_NO_'),('SICIL_KODU_')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'CS_INSTALLMENT_INCOME' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'CS_INSTALLMENT_INCOME eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'CS_INSTALLMENT_INCOME kaynak OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_INCOME_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_INSTALLMENT_INCOME', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_INSTALLMENT_INCOME bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('INSTALLMENT_PLAN_REF'),('ACCOUNT_REF'),('INCOME_ID'),
            ('AMOUNT'),('STATUS'),('PAYMENT_DATE'),('CASH_ID'),
            ('RECEIPT_SERIAL'),('RECEIPT_NUMBER'),
            ('ABYS_ID'),('ABYS_INSTALLMENT_PLAN_ID'),('ABYS_ACCOUNT_ID'),('ABYS_INCOME_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1 FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INSTALLMENT_INCOME')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_INSTALLMENT_INCOME eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_INSTALLMENT_INCOME hedef OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_INCOME_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;
    EXEC @Rc = dbo.SP_MIG_INSTALLMENT_INCOME_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;
    EXEC @Rc = dbo.SP_MIG_INSTALLMENT_INCOME_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    RETURN @Rc;
END
GO

EXEC dbo.SP_MIG_INSTALLMENT_INCOME_VALIDATE_ALL @RaiseOnMissing = 0;
GO

PRINT '615_INSTALLMENT_INCOME__setup OK';
GO
