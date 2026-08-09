/* ============================================================
   SCRIPT_ID : INSTALLMENT_PLAN_SETUP
   SCRIPT_NO : 610
   FILE      : 610_INSTALLMENT_PLAN__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.CS_INSTALLMENT_PLAN (+ CS_INSTALLMENT)
--   → energy.dbo.LS_005_01_INSTALLMENT_PLAN
--
-- Pass 1 dump-style:
--   - Hedef tablo yoksa olusturulur
--   - ABYS_* bridge kolonlari TABLO SONUNA (idempotent)
--   - PAYTRANS / tahsilat bu scriptte YOK
--   - Unique index: ABYS_ID
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ------------------------------------------------------------
-- Hedef tablo (yoksa create)
-- ------------------------------------------------------------
IF OBJECT_ID('energy.dbo.LS_005_01_INSTALLMENT_PLAN', 'U') IS NULL
BEGIN
    CREATE TABLE energy.dbo.LS_005_01_INSTALLMENT_PLAN (
        LREF                  INT IDENTITY(1,1) NOT NULL,
        INSTALLMENT_TYPE_ID   INT NULL,
        OWNERREF              INT NULL,
        INVOICE_REF           INT NULL,
        PAYTRANS_REF          INT NULL,
        TOTAL_AMOUNT         DECIMAL(18,2) NULL,
        INSTALLMENT_COUNT     INT NULL,
        COMMISSION_DELAY_RATE DECIMAL(18,2) NULL,
        ISACTIVE              INT NULL,
        ADDDATE               DATETIME NULL,
        ADDUSER               INT NULL,
        UPDDATE               DATETIME NULL,
        UPDUSER               INT NULL,
        PLAN_ID               INT NULL,
        INVOICE_OLD_DUEDATE   DATETIME NULL,
        CONSTRAINT PK_LS_005_01_INSTALLMENT_PLAN PRIMARY KEY (LREF)
    );
END
GO

-- ------------------------------------------------------------
-- ABYS bridge kolonlari (idempotent)
-- ------------------------------------------------------------
DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(300) NOT NULL);

INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 (N'ABYS_ID',                     N'BIGINT NULL'),
 (N'ABYS_INSTALLMENT_ID',         N'BIGINT NULL'),
 (N'ABYS_ORDER_NUMBER',           N'INT NULL'),
 (N'ABYS_AMOUNT',                 N'DECIMAL(18,2) NULL'),
 (N'ABYS_LATE_CHARGE',            N'DECIMAL(18,2) NULL'),
 (N'ABYS_OVERDUE',                N'DECIMAL(18,2) NULL'),
 (N'ABYS_EXPIRY_DATE',            N'DATETIME NULL'),
 (N'ABYS_DUE_DATE',               N'DATETIME NULL'),
 (N'ABYS_PAYMENT_DATE',           N'DATETIME NULL'),
 (N'ABYS_CASH_ID',                N'BIGINT NULL'),
 (N'ABYS_RECEIPT_SERIAL',         N'NVARCHAR(6) NULL'),
 (N'ABYS_RECEIPT_NUMBER',         N'DECIMAL(25,0) NULL'),
 (N'ABYS_POOL_ID',                N'BIGINT NULL'),
 (N'ABYS_DESCRIPTION',            N'NVARCHAR(500) NULL'),
 (N'ABYS_OLD_LATE_CHARGE',        N'DECIMAL(18,2) NULL'),
 (N'ABYS_OLD_EXPIRY_DATE',        N'DATETIME NULL'),
 (N'ABYS_VERSION',                N'BIGINT NULL'),
 (N'ABYS_AGREEMENT_ID',           N'BIGINT NULL'),
 (N'ABYS_INSTALLMENT_TYPE_ID',    N'BIGINT NULL'),
 (N'ABYS_CANCEL_CAUSE_ID',        N'BIGINT NULL'),
 (N'ABYS_CANCELLATION_DATE',      N'DATETIME NULL'),
 (N'ABYS_CANCELLATION_USER_ID',   N'BIGINT NULL'),
 (N'ABYS_INSTALLMENT_DUE_DATE',   N'DATETIME NULL'),
 (N'ABYS_CUSTOM_LATE_RATE',       N'DECIMAL(18,6) NULL'),
 (N'ABYS_CREATED_USER_ID',        N'BIGINT NULL'),
 (N'ABYS_UPDATED_USER_ID',        N'BIGINT NULL');

SELECT @Sql = @Sql + N'
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(''energy.dbo.LS_005_01_INSTALLMENT_PLAN'')
      AND name = ''' + COL_NAME + N'''
)
    ALTER TABLE energy.dbo.LS_005_01_INSTALLMENT_PLAN ADD ' + COL_NAME + N' ' + COL_DEF + N';'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INSTALLMENT_PLAN')
      AND name = 'UX_LS005_INSTALLMENT_PLAN_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS005_INSTALLMENT_PLAN_ABYS_ID
        ON energy.dbo.LS_005_01_INSTALLMENT_PLAN (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INSTALLMENT_PLAN')
      AND name = 'IX_LS005_INSTALLMENT_PLAN_PLAN_ID'
)
    CREATE NONCLUSTERED INDEX IX_LS005_INSTALLMENT_PLAN_PLAN_ID
        ON energy.dbo.LS_005_01_INSTALLMENT_PLAN (PLAN_ID)
        INCLUDE (INSTALLMENT_COUNT, INVOICE_REF, ISACTIVE);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INSTALLMENT_PLAN')
      AND name = 'IX_LS005_INSTALLMENT_PLAN_ABYS_INS'
)
    CREATE NONCLUSTERED INDEX IX_LS005_INSTALLMENT_PLAN_ABYS_INS
        ON energy.dbo.LS_005_01_INSTALLMENT_PLAN (ABYS_INSTALLMENT_ID, ABYS_ORDER_NUMBER);
GO

-- ------------------------------------------------------------
-- Validate kaynak
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_PLAN_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.CS_INSTALLMENT_PLAN', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.CS_INSTALLMENT_PLAN bulunamadi.', 16, 1);
        RETURN 1;
    END

    IF OBJECT_ID('izgazMGR.dbo.CS_INSTALLMENT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.CS_INSTALLMENT bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('ID'),('INSTALLMENT_ID'),('ORDER_NUMBER'),('EXPIRY_DATE'),
            ('AMOUNT'),('LATE_CHARGE'),('OVERDUE'),('PAYMENT_DATE'),
            ('CASH_ID'),('RECEIPT_SERIAL'),('RECEIPT_NUMBER'),('DUE_DATE'),
            ('CREATED_USER_ID'),('CREATED_TIMESTAMP'),
            ('UPDATED_USER_ID'),('UPDATED_TIMESTAMP'),('VERSION'),
            ('POOL_ID'),('DESCRIPTION'),('OLD_LATE_CHARGE'),('OLD_EXPIRY_DATE')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'CS_INSTALLMENT_PLAN' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'CS_INSTALLMENT_PLAN eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    SET @Missing = N'';

    ;WITH RequiredIns (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('ID'),('INSTALLMENT_TYPE_ID'),('AGREEMENT_ID'),
            ('CANCEL_CAUSE_ID'),('CANCELLATION_DATE'),('CANCELLATION_USER_ID'),
            ('DUE_DATE'),('CUSTOM_LATE_RATE')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM RequiredIns r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'CS_INSTALLMENT' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg2 NVARCHAR(4000) = N'CS_INSTALLMENT eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg2, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'CS_INSTALLMENT_PLAN / CS_INSTALLMENT kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_PLAN_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_INSTALLMENT_PLAN', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_INSTALLMENT_PLAN bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('INSTALLMENT_TYPE_ID'),('OWNERREF'),('INVOICE_REF'),
            ('PAYTRANS_REF'),('TOTAL_AMOUNT'),('INSTALLMENT_COUNT'),
            ('COMMISSION_DELAY_RATE'),('ISACTIVE'),
            ('ADDDATE'),('ADDUSER'),('UPDDATE'),('UPDUSER'),
            ('PLAN_ID'),('INVOICE_OLD_DUEDATE'),
            ('ABYS_ID'),('ABYS_INSTALLMENT_ID'),('ABYS_ORDER_NUMBER'),
            ('ABYS_AMOUNT'),('ABYS_LATE_CHARGE'),('ABYS_OVERDUE'),
            ('ABYS_EXPIRY_DATE'),('ABYS_DUE_DATE'),('ABYS_PAYMENT_DATE'),
            ('ABYS_CASH_ID'),('ABYS_RECEIPT_SERIAL'),('ABYS_RECEIPT_NUMBER'),
            ('ABYS_POOL_ID'),('ABYS_DESCRIPTION'),
            ('ABYS_OLD_LATE_CHARGE'),('ABYS_OLD_EXPIRY_DATE'),('ABYS_VERSION'),
            ('ABYS_AGREEMENT_ID'),('ABYS_INSTALLMENT_TYPE_ID'),
            ('ABYS_CANCEL_CAUSE_ID'),('ABYS_CANCELLATION_DATE'),
            ('ABYS_CANCELLATION_USER_ID'),
            ('ABYS_INSTALLMENT_DUE_DATE'),('ABYS_CUSTOM_LATE_RATE'),
            ('ABYS_CREATED_USER_ID'),('ABYS_UPDATED_USER_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INSTALLMENT_PLAN')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_INSTALLMENT_PLAN eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_INSTALLMENT_PLAN hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_PLAN_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_INSTALLMENT_PLAN_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_INSTALLMENT_PLAN_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    RETURN @Rc;
END
GO

EXEC dbo.SP_MIG_INSTALLMENT_PLAN_VALIDATE_ALL @RaiseOnMissing = 0;
GO

PRINT '610_INSTALLMENT_PLAN__setup OK';
GO
