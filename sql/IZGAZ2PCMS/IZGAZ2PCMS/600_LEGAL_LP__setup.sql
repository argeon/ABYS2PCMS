/* ============================================================
   SCRIPT_ID : LEGAL_LP_SETUP
   SCRIPT_NO : 600
   FILE      : 600_LEGAL_LP__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LP (Legal Proceeding) izgazMGR → energy
--   LP_EXPENSE_CAUSE_PRM     ← LP_EXPENSE_CAUSE_PRM + LP_EXPENSE_CAUSE_PRM_LNG
--   LP_LEGAL_PROCEEDING      ← LP_LEGAL_PROCEEDING
--   LP_STATUS                ← LP_STATUS
--   LP_INVOICE               ← LP_ACCOUNT
--   LP_INCOME                ← LP_INCOME
--
-- REGION sabit 4102; ID = ABYS_ID (IDENTITY_INSERT)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ------------------------------------------------------------
-- Hedef ABYS köprü + kaynakta olup hedefte olmayan kolonlar
-- ------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_EXPENSE_CAUSE_PRM') AND name = 'ABYS_ID')
    ALTER TABLE energy.dbo.LP_EXPENSE_CAUSE_PRM ADD ABYS_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_EXPENSE_CAUSE_PRM') AND name = 'ABYS_CORPORATION_ID')
    ALTER TABLE energy.dbo.LP_EXPENSE_CAUSE_PRM ADD ABYS_CORPORATION_ID INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_EXPENSE_CAUSE_PRM') AND name = 'ABYS_MAIL_ID')
    ALTER TABLE energy.dbo.LP_EXPENSE_CAUSE_PRM ADD ABYS_MAIL_ID INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_EXPENSE_CAUSE_PRM') AND name = 'ABYS_LIEN_TYPE_ID')
    ALTER TABLE energy.dbo.LP_EXPENSE_CAUSE_PRM ADD ABYS_LIEN_TYPE_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_EXPENSE_CAUSE_PRM') AND name = 'ABYS_VERSION')
    ALTER TABLE energy.dbo.LP_EXPENSE_CAUSE_PRM ADD ABYS_VERSION BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_EXPENSE_CAUSE_PRM') AND name = 'ABYS_CODE_RAW')
    ALTER TABLE energy.dbo.LP_EXPENSE_CAUSE_PRM ADD ABYS_CODE_RAW NVARCHAR(10) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'ABYS_ID')
    ALTER TABLE energy.dbo.LP_LEGAL_PROCEEDING ADD ABYS_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'ABYS_CORPORATION_ID')
    ALTER TABLE energy.dbo.LP_LEGAL_PROCEEDING ADD ABYS_CORPORATION_ID INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'ABYS_TYPE')
    ALTER TABLE energy.dbo.LP_LEGAL_PROCEEDING ADD ABYS_TYPE SMALLINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'ABYS_CTV_OVERDUE')
    ALTER TABLE energy.dbo.LP_LEGAL_PROCEEDING ADD ABYS_CTV_OVERDUE DECIMAL(10, 2) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'ABYS_CTV_OVERDUE_VAT')
    ALTER TABLE energy.dbo.LP_LEGAL_PROCEEDING ADD ABYS_CTV_OVERDUE_VAT DECIMAL(10, 2) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'ABYS_POOL_ID')
    ALTER TABLE energy.dbo.LP_LEGAL_PROCEEDING ADD ABYS_POOL_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'ABYS_POOL_DEBT')
    ALTER TABLE energy.dbo.LP_LEGAL_PROCEEDING ADD ABYS_POOL_DEBT DECIMAL(10, 2) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'ABYS_POOL_DEBT_COUNT')
    ALTER TABLE energy.dbo.LP_LEGAL_PROCEEDING ADD ABYS_POOL_DEBT_COUNT SMALLINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'ABYS_DISTRICT_ID')
    ALTER TABLE energy.dbo.LP_LEGAL_PROCEEDING ADD ABYS_DISTRICT_ID INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'ABYS_MTS_NUMBER')
    ALTER TABLE energy.dbo.LP_LEGAL_PROCEEDING ADD ABYS_MTS_NUMBER NVARCHAR(20) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'ABYS_JAIL_CHARGE_AMOUNT')
    ALTER TABLE energy.dbo.LP_LEGAL_PROCEEDING ADD ABYS_JAIL_CHARGE_AMOUNT DECIMAL(10, 2) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'ABYS_VERSION')
    ALTER TABLE energy.dbo.LP_LEGAL_PROCEEDING ADD ABYS_VERSION BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'ABYS_INSTALLATION_ID')
    ALTER TABLE energy.dbo.LP_LEGAL_PROCEEDING ADD ABYS_INSTALLATION_ID BIGINT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_STATUS') AND name = 'ABYS_ID')
    ALTER TABLE energy.dbo.LP_STATUS ADD ABYS_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_STATUS') AND name = 'ABYS_VERSION')
    ALTER TABLE energy.dbo.LP_STATUS ADD ABYS_VERSION BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_STATUS') AND name = 'ABYS_CREATED_USER_ID')
    ALTER TABLE energy.dbo.LP_STATUS ADD ABYS_CREATED_USER_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_STATUS') AND name = 'ABYS_CREATED_TIMESTAMP')
    ALTER TABLE energy.dbo.LP_STATUS ADD ABYS_CREATED_TIMESTAMP DATETIMEOFFSET(7) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_STATUS') AND name = 'ABYS_UPDATED_USER_ID')
    ALTER TABLE energy.dbo.LP_STATUS ADD ABYS_UPDATED_USER_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_STATUS') AND name = 'ABYS_UPDATED_TIMESTAMP')
    ALTER TABLE energy.dbo.LP_STATUS ADD ABYS_UPDATED_TIMESTAMP DATETIMEOFFSET(7) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_INVOICE') AND name = 'ABYS_ID')
    ALTER TABLE energy.dbo.LP_INVOICE ADD ABYS_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_INVOICE') AND name = 'ABYS_VERSION')
    ALTER TABLE energy.dbo.LP_INVOICE ADD ABYS_VERSION BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_INVOICE') AND name = 'ABYS_ACCOUNT_ID')
    ALTER TABLE energy.dbo.LP_INVOICE ADD ABYS_ACCOUNT_ID BIGINT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_INCOME') AND name = 'ABYS_ID')
    ALTER TABLE energy.dbo.LP_INCOME ADD ABYS_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_INCOME') AND name = 'ABYS_VERSION')
    ALTER TABLE energy.dbo.LP_INCOME ADD ABYS_VERSION BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LP_INCOME') AND name = 'ABYS_ACCOUNT_ID')
    ALTER TABLE energy.dbo.LP_INCOME ADD ABYS_ACCOUNT_ID BIGINT NULL;
GO

-- ABYS_ID unique filtered index (resume / idempotency)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LP_EXPENSE_CAUSE_PRM') AND name = 'UX_LP_EXPENSE_CAUSE_PRM_ABYS_ID')
    CREATE UNIQUE NONCLUSTERED INDEX UX_LP_EXPENSE_CAUSE_PRM_ABYS_ID
        ON energy.dbo.LP_EXPENSE_CAUSE_PRM (ABYS_ID) WHERE ABYS_ID IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING') AND name = 'UX_LP_LEGAL_PROCEEDING_ABYS_ID')
    CREATE UNIQUE NONCLUSTERED INDEX UX_LP_LEGAL_PROCEEDING_ABYS_ID
        ON energy.dbo.LP_LEGAL_PROCEEDING (ABYS_ID) WHERE ABYS_ID IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LP_STATUS') AND name = 'UX_LP_STATUS_ABYS_ID')
    CREATE UNIQUE NONCLUSTERED INDEX UX_LP_STATUS_ABYS_ID
        ON energy.dbo.LP_STATUS (ABYS_ID) WHERE ABYS_ID IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LP_INVOICE') AND name = 'UX_LP_INVOICE_ABYS_ID')
    CREATE UNIQUE NONCLUSTERED INDEX UX_LP_INVOICE_ABYS_ID
        ON energy.dbo.LP_INVOICE (ABYS_ID) WHERE ABYS_ID IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LP_INCOME') AND name = 'UX_LP_INCOME_ABYS_ID')
    CREATE UNIQUE NONCLUSTERED INDEX UX_LP_INCOME_ABYS_ID
        ON energy.dbo.LP_INCOME (ABYS_ID) WHERE ABYS_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Aktarım öncesi FK gevşetme (varsa)
-- ------------------------------------------------------------
DECLARE @DropFkSql NVARCHAR(MAX) = N'';

SELECT @DropFkSql = @DropFkSql
    + N'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id)) + N'.' + QUOTENAME(OBJECT_NAME(fk.parent_object_id))
    + N' DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';' + CHAR(13) + CHAR(10)
FROM sys.foreign_keys fk
WHERE OBJECT_NAME(fk.parent_object_id) IN (
    'LP_EXPENSE_CAUSE_PRM', 'LP_LEGAL_PROCEEDING', 'LP_STATUS', 'LP_INVOICE', 'LP_INCOME'
);

IF @DropFkSql <> N''
    EXEC sys.sp_executesql @DropFkSql;
GO

-- ------------------------------------------------------------
-- Kolon doğrulama
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_LP_VALIDATE_TABLE_COLUMNS
    @DbName       SYSNAME,
    @SchemaName   SYSNAME,
    @TableName    SYSNAME,
    @RequiredCols NVARCHAR(MAX),
    @Label        NVARCHAR(200),
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Missing NVARCHAR(MAX) = N'';
    DECLARE @FullName NVARCHAR(300) = QUOTENAME(@DbName) + N'.' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName);
    DECLARE @Xml XML;

    IF OBJECT_ID(@FullName, 'U') IS NULL
    BEGIN
        DECLARE @NotFound NVARCHAR(4000) = @Label + N': tablo bulunamadi (' + @FullName + N').';
        IF @RaiseOnMissing = 1 RAISERROR(@NotFound, 16, 1);
        RETURN 1;
    END

    SET @Xml = CAST(N'<r><c>'
        + REPLACE(REPLACE(REPLACE(ISNULL(@RequiredCols, N''), N'&', N'&amp;'), N'<', N'&lt;'), N',', N'</c><c>')
        + N'</c></r>' AS XML);

    DECLARE @Sql NVARCHAR(MAX) = N'
;WITH Required (COL_NAME) AS (
    SELECT LTRIM(RTRIM(T.C.value(''.'', ''nvarchar(255)'')))
    FROM @ColsXml.nodes(''/r/c'') AS T(C)
    WHERE LTRIM(RTRIM(T.C.value(''.'', ''nvarchar(255)''))) <> N''''
)
SELECT @MissingOut = STUFF((
    SELECT N'', '' + r.COL_NAME
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM ' + QUOTENAME(@DbName) + N'.sys.columns c
        INNER JOIN ' + QUOTENAME(@DbName) + N'.sys.tables t ON t.object_id = c.object_id
        INNER JOIN ' + QUOTENAME(@DbName) + N'.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = @SchemaName AND t.name = @TableName AND c.name = r.COL_NAME
    )
    FOR XML PATH(''''), TYPE
).value(''.'', ''nvarchar(max)''), 1, 2, N'''');';

    EXEC sp_executesql
        @Sql,
        N'@ColsXml XML, @SchemaName SYSNAME, @TableName SYSNAME, @MissingOut NVARCHAR(MAX) OUTPUT',
        @ColsXml = @Xml, @SchemaName = @SchemaName, @TableName = @TableName, @MissingOut = @Missing OUTPUT;

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = @Label + N' eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_LP_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_LP_VALIDATE_TABLE_COLUMNS
        @DbName = 'izgazMGR', @SchemaName = 'dbo', @TableName = 'LP_EXPENSE_CAUSE_PRM',
        @RequiredCols = N'ID,CORPORATION_ID,CODE,INCOME_ID,MAIL_ID,IS_ACTIVE,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,VERSION,LIEN_TYPE_ID',
        @Label = N'LP_EXPENSE_CAUSE_PRM', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_LP_VALIDATE_TABLE_COLUMNS
        @DbName = 'izgazMGR', @SchemaName = 'dbo', @TableName = 'LP_EXPENSE_CAUSE_PRM_LNG',
        @RequiredCols = N'ID,PRM_ID,LANG_ID,VALUE',
        @Label = N'LP_EXPENSE_CAUSE_PRM_LNG', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_LP_VALIDATE_TABLE_COLUMNS
        @DbName = 'izgazMGR', @SchemaName = 'dbo', @TableName = 'LP_LEGAL_PROCEEDING',
        @RequiredCols = N'ID,CORPORATION_ID,CODE,EXECUTIVE_BRANCH_ID,AGREEMENT_ID,INSTALLATION_ID,REGISTER_ID,PRE_PROCEEDING_DATE,LEGAL_PROCEEDING_DATE,NOTIFICATION_DATE,NOTIFICATION_RECIPIENT,LAST_PAYMENT_DATE,ENFORCEMENT_OFFICE_ID,DEBTOR_ATTORNEY_REG_ID,LAW_TRANSACTION_DATE,LAW_DOC_DATE,LAW_DOC_NUMBER,RECORD_NUMBER,CASE_NUMBER,DESCRIPTION,SENTENCE_DESCRIPTION,STATUS,TYPE,DEBT,OVERDUE,OVERDUE_VAT,CTV_OVERDUE,CTV_OVERDUE_VAT,STANDART_EXPENSES,LEGAL_PROCEEDING_AMOUNT,CHARGE_RATE_ID,CANCELLATION_DATE,CANCELLATION_USER_ID,CANCELLATION_CAUSE_ID,CANCELLATION_DESCRIPTION,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,VERSION,APPEAL_DATE,POOL_ID,LAW_ISSUE_ID,POOL_DEBT,POOL_DEBT_COUNT,CONFIRMATION_NUMBER,OLD_LAST_PAYMENT_DATE,DISTRICT_ID,MTS_NUMBER,JAIL_CHARGE_AMOUNT',
        @Label = N'LP_LEGAL_PROCEEDING', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_LP_VALIDATE_TABLE_COLUMNS
        @DbName = 'izgazMGR', @SchemaName = 'dbo', @TableName = 'LP_STATUS',
        @RequiredCols = N'ID,LEGAL_PROCEEDING_ID,STATUS,STATUS_DATE,DESCRIPTION,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,VERSION',
        @Label = N'LP_STATUS', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_LP_VALIDATE_TABLE_COLUMNS
        @DbName = 'izgazMGR', @SchemaName = 'dbo', @TableName = 'LP_ACCOUNT',
        @RequiredCols = N'ID,LEGAL_PROCEEDING_ID,ACCOUNT_ID,AMOUNT,OVERDUE,OVERDUE_VAT,COMMISSION_DELAY_TYPE_ID,DEBT_GROUP_ID,EXPIRY_DATE,DUE_INSTALLMENT_ID,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,VERSION,ORDER_NUMBER,DESCRIPTION',
        @Label = N'LP_ACCOUNT', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_LP_VALIDATE_TABLE_COLUMNS
        @DbName = 'izgazMGR', @SchemaName = 'dbo', @TableName = 'LP_INCOME',
        @RequiredCols = N'ID,LEGAL_PROCEEDING_ID,EXPENSE_CAUSE_ID,AMOUNT,ACCOUNT_ID,STATUS,DESCRIPTION,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,VERSION,ACTION_DATE,SEND_PAYED_DATE,SEND_PAYED_USER_ID',
        @Label = N'LP_INCOME', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    IF @RaiseOnMissing = 0
        SELECT N'LP kaynak tablolari kolon dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_LP_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_LP_VALIDATE_TABLE_COLUMNS
        @DbName = 'energy', @SchemaName = 'dbo', @TableName = 'LP_EXPENSE_CAUSE_PRM',
        @RequiredCols = N'ABYS_ID,CODE,INCOME_ID,VALUE,EXPENSE_TYPE,IS_ACTIVE,IS_LISTED,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP',
        @Label = N'LP_EXPENSE_CAUSE_PRM', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_LP_VALIDATE_TABLE_COLUMNS
        @DbName = 'energy', @SchemaName = 'dbo', @TableName = 'LP_LEGAL_PROCEEDING',
        @RequiredCols = N'ABYS_ID,REGION,CODE,EXECUTIVE_BRANCH_ID,AGREEMENT_ID,INSTALLATION_ID,REGISTER_ID,PRE_PROCEEDING_DATE,LEGAL_PROCEEDING_DATE,NOTIFICATION_DATE,NOTIFICATION_RECIPIENT,LAST_PAYMENT_DATE,ENFORCEMENT_OFFICE_ID,DEBTOR_ATTORNEY_REG_ID,LAW_TRANSACTION_DATE,LAW_DOC_DATE,LAW_DOC_NUMBER,RECORD_NUMBER,CASE_NUMBER,DESCRIPTION,SENTENCE_DESCRIPTION,STATUS,DEBT,OVERDUE,OVERDUE_VAT,STANDART_EXPENSES,LEGAL_PROCEEDING_AMOUNT,CHARGE_RATE_ID,CANCELLATION_DATE,CANCELLATION_USER_ID,CANCELLATION_CAUSE_ID,CANCELLATION_DESCRIPTION,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,APPEAL_DATE,LAW_ISSUE_ID,CONFIRMATION_NUMBER,OLD_LAST_PAYMENT_DATE,IS_ACTIVE',
        @Label = N'LP_LEGAL_PROCEEDING', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_LP_VALIDATE_TABLE_COLUMNS
        @DbName = 'energy', @SchemaName = 'dbo', @TableName = 'LP_STATUS',
        @RequiredCols = N'ABYS_ID,LEGAL_PROCEEDING_ID,STATUS,STATUS_DATE,DESCRIPTION',
        @Label = N'LP_STATUS', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_LP_VALIDATE_TABLE_COLUMNS
        @DbName = 'energy', @SchemaName = 'dbo', @TableName = 'LP_INVOICE',
        @RequiredCols = N'ABYS_ID,REGION,LEGAL_PROCEEDING_ID,INVOICE_ID,AMOUNT,OVERDUE,OVERDUE_VAT,COMMISSION_DELAY_TYPE_ID,DEBT_GROUP_ID,EXPIRY_DATE,DUE_INSTALLMENT_ID,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,IS_ACTIVE,ORDER_NUMBER,DESCRIPTION',
        @Label = N'LP_INVOICE', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_LP_VALIDATE_TABLE_COLUMNS
        @DbName = 'energy', @SchemaName = 'dbo', @TableName = 'LP_INCOME',
        @RequiredCols = N'ABYS_ID,LEGAL_PROCEEDING_ID,EXPENSE_CAUSE_ID,AMOUNT,INVOICE_ID,STATUS,DESCRIPTION,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,IS_ACTIVE,ACTION_DATE,SEND_PAYED_DATE,SEND_PAYED_USER_ID',
        @Label = N'LP_INCOME', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    IF @RaiseOnMissing = 0
        SELECT N'LP hedef tablolari kolon dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_LP_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_LP_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_LP_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    IF @RaiseOnMissing = 0
        SELECT N'LP kaynak + hedef kolon dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Kaynak view'lar
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.VW_MIG_LP_EXPENSE_CAUSE_PRM_SOURCE
AS
SELECT
    p.ID                                                            AS ABYS_ID,
    TRY_CAST(p.CODE AS INT)                                         AS CODE,
    CAST(TRY_CAST(p.INCOME_ID AS BIGINT) AS INT)                    AS INCOME_ID,
    LEFT(lng.VALUE, 100)                                            AS VALUE,
    CAST(NULL AS INT)                                               AS EXPENSE_TYPE,
    CAST(CASE WHEN ISNULL(p.IS_ACTIVE, 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS IS_ACTIVE,
    CAST(NULL AS BIT)                                               AS IS_LISTED,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(p.CREATED_USER_ID AS BIGINT) AS INT)) AS CREATED_USER_ID,
    ISNULL(energy.dbo.FN_SAFE_DT(CAST(p.CREATED_TIMESTAMP AS DATETIME2)), GETDATE()) AS CREATED_TIMESTAMP,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(p.UPDATED_USER_ID AS BIGINT) AS INT)) AS UPDATED_USER_ID,
    energy.dbo.FN_SAFE_DT(CAST(p.UPDATED_TIMESTAMP AS DATETIME2))   AS UPDATED_TIMESTAMP,
    p.CORPORATION_ID                                                AS ABYS_CORPORATION_ID,
    p.MAIL_ID                                                       AS ABYS_MAIL_ID,
    p.LIEN_TYPE_ID                                                  AS ABYS_LIEN_TYPE_ID,
    p.VERSION                                                       AS ABYS_VERSION,
    LEFT(p.CODE, 10)                                                AS ABYS_CODE_RAW
FROM izgazMGR.dbo.LP_EXPENSE_CAUSE_PRM p
LEFT JOIN izgazMGR.dbo.LP_EXPENSE_CAUSE_PRM_LNG lng
    ON lng.PRM_ID = p.ID AND lng.LANG_ID = 1;
GO

CREATE OR ALTER VIEW dbo.VW_MIG_LP_LEGAL_PROCEEDING_SOURCE
AS
SELECT
    s.ID                                                            AS ABYS_ID,
    CAST(4102 AS INT)                                               AS REGION,
    LEFT(s.CODE, 10)                                                AS CODE,
    CAST(TRY_CAST(s.EXECUTIVE_BRANCH_ID AS BIGINT) AS INT)          AS EXECUTIVE_BRANCH_ID,
    CAST(ISNULL(s.AGREEMENT_ID, 0) AS INT)                          AS AGREEMENT_ID,
    ISNULL(LEFT(CAST(s.INSTALLATION_ID AS NVARCHAR(20)), 20), N'0') AS INSTALLATION_ID,
    CAST(TRY_CAST(s.REGISTER_ID AS BIGINT) AS INT)                  AS REGISTER_ID,
    energy.dbo.FN_SAFE_DT(CAST(s.PRE_PROCEEDING_DATE AS DATETIME2)) AS PRE_PROCEEDING_DATE,
    energy.dbo.FN_SAFE_DT(CAST(s.LEGAL_PROCEEDING_DATE AS DATETIME2)) AS LEGAL_PROCEEDING_DATE,
    energy.dbo.FN_SAFE_DT(CAST(s.NOTIFICATION_DATE AS DATETIME2)) AS NOTIFICATION_DATE,
    LEFT(s.NOTIFICATION_RECIPIENT, 50)                             AS NOTIFICATION_RECIPIENT,
    energy.dbo.FN_SAFE_DT(CAST(s.LAST_PAYMENT_DATE AS DATETIME2))   AS LAST_PAYMENT_DATE,
    CAST(TRY_CAST(s.ENFORCEMENT_OFFICE_ID AS BIGINT) AS INT)        AS ENFORCEMENT_OFFICE_ID,
    CAST(TRY_CAST(s.DEBTOR_ATTORNEY_REG_ID AS BIGINT) AS INT)       AS DEBTOR_ATTORNEY_REG_ID,
    energy.dbo.FN_SAFE_DT(CAST(s.LAW_TRANSACTION_DATE AS DATETIME2)) AS LAW_TRANSACTION_DATE,
    energy.dbo.FN_SAFE_DT(CAST(s.LAW_DOC_DATE AS DATETIME2))        AS LAW_DOC_DATE,
    LEFT(s.LAW_DOC_NUMBER, 50)                                      AS LAW_DOC_NUMBER,
    LEFT(s.RECORD_NUMBER, 50)                                       AS RECORD_NUMBER,
    LEFT(s.CASE_NUMBER, 30)                                         AS CASE_NUMBER,
    CAST(s.DESCRIPTION AS NVARCHAR(MAX))                            AS DESCRIPTION,
    CAST(s.SENTENCE_DESCRIPTION AS NVARCHAR(MAX))                   AS SENTENCE_DESCRIPTION,
    CAST(s.STATUS AS INT)                                           AS STATUS,
    s.DEBT, s.OVERDUE, s.OVERDUE_VAT,
    s.STANDART_EXPENSES, s.LEGAL_PROCEEDING_AMOUNT,
    CAST(TRY_CAST(s.CHARGE_RATE_ID AS BIGINT) AS INT)               AS CHARGE_RATE_ID,
    energy.dbo.FN_SAFE_DT(CAST(s.CANCELLATION_DATE AS DATETIME2))   AS CANCELLATION_DATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.CANCELLATION_USER_ID AS BIGINT) AS INT)) AS CANCELLATION_USER_ID,
    CAST(TRY_CAST(s.CANCELLATION_CAUSE_ID AS BIGINT) AS INT)        AS CANCELLATION_CAUSE_ID,
    CAST(s.CANCELLATION_DESCRIPTION AS NVARCHAR(MAX))               AS CANCELLATION_DESCRIPTION,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.CREATED_USER_ID AS BIGINT) AS INT)) AS CREATED_USER_ID,
    ISNULL(energy.dbo.FN_SAFE_DT(CAST(s.CREATED_TIMESTAMP AS DATETIME2)), GETDATE()) AS CREATED_TIMESTAMP,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.UPDATED_USER_ID AS BIGINT) AS INT)) AS UPDATED_USER_ID,
    energy.dbo.FN_SAFE_DT(CAST(s.UPDATED_TIMESTAMP AS DATETIME2))   AS UPDATED_TIMESTAMP,
    energy.dbo.FN_SAFE_DT(CAST(s.APPEAL_DATE AS DATETIME2))         AS APPEAL_DATE,
    CAST(TRY_CAST(s.LAW_ISSUE_ID AS BIGINT) AS INT)                 AS LAW_ISSUE_ID,
    LEFT(s.CONFIRMATION_NUMBER, 30)                                 AS CONFIRMATION_NUMBER,
    energy.dbo.FN_SAFE_DT(CAST(s.OLD_LAST_PAYMENT_DATE AS DATETIME2)) AS OLD_LAST_PAYMENT_DATE,
    CAST(1 AS BIT)                                                  AS IS_ACTIVE,
    s.CORPORATION_ID                                                AS ABYS_CORPORATION_ID,
    s.TYPE                                                          AS ABYS_TYPE,
    s.CTV_OVERDUE                                                   AS ABYS_CTV_OVERDUE,
    s.CTV_OVERDUE_VAT                                               AS ABYS_CTV_OVERDUE_VAT,
    s.POOL_ID                                                       AS ABYS_POOL_ID,
    s.POOL_DEBT                                                     AS ABYS_POOL_DEBT,
    s.POOL_DEBT_COUNT                                               AS ABYS_POOL_DEBT_COUNT,
    s.DISTRICT_ID                                                   AS ABYS_DISTRICT_ID,
    s.MTS_NUMBER                                                    AS ABYS_MTS_NUMBER,
    s.JAIL_CHARGE_AMOUNT                                            AS ABYS_JAIL_CHARGE_AMOUNT,
    s.VERSION                                                       AS ABYS_VERSION,
    s.INSTALLATION_ID                                               AS ABYS_INSTALLATION_ID
FROM izgazMGR.dbo.LP_LEGAL_PROCEEDING s;
GO

CREATE OR ALTER VIEW dbo.VW_MIG_LP_STATUS_SOURCE
AS
SELECT
    s.ID                                                            AS ABYS_ID,
    CAST(TRY_CAST(s.LEGAL_PROCEEDING_ID AS BIGINT) AS INT)          AS LEGAL_PROCEEDING_ID,
    CAST(s.STATUS AS INT)                                           AS STATUS,
    energy.dbo.FN_SAFE_DT(CAST(s.STATUS_DATE AS DATETIME2))       AS STATUS_DATE,
    s.DESCRIPTION,
    s.VERSION                                                       AS ABYS_VERSION,
    s.CREATED_USER_ID                                               AS ABYS_CREATED_USER_ID,
    s.CREATED_TIMESTAMP                                             AS ABYS_CREATED_TIMESTAMP,
    s.UPDATED_USER_ID                                               AS ABYS_UPDATED_USER_ID,
    s.UPDATED_TIMESTAMP                                             AS ABYS_UPDATED_TIMESTAMP
FROM izgazMGR.dbo.LP_STATUS s;
GO

CREATE OR ALTER VIEW dbo.VW_MIG_LP_INVOICE_SOURCE
AS
SELECT
    a.ID                                                            AS ABYS_ID,
    CAST(4102 AS INT)                                               AS REGION,
    CAST(TRY_CAST(a.LEGAL_PROCEEDING_ID AS BIGINT) AS INT)          AS LEGAL_PROCEEDING_ID,
    CAST(TRY_CAST(a.ACCOUNT_ID AS BIGINT) AS INT)                   AS INVOICE_ID,
    a.AMOUNT, a.OVERDUE, a.OVERDUE_VAT,
    CAST(TRY_CAST(a.COMMISSION_DELAY_TYPE_ID AS BIGINT) AS INT)     AS COMMISSION_DELAY_TYPE_ID,
    CAST(TRY_CAST(a.DEBT_GROUP_ID AS BIGINT) AS INT)                AS DEBT_GROUP_ID,
    energy.dbo.FN_SAFE_DT(CAST(a.EXPIRY_DATE AS DATETIME2))         AS EXPIRY_DATE,
    CAST(TRY_CAST(a.DUE_INSTALLMENT_ID AS BIGINT) AS INT)           AS DUE_INSTALLMENT_ID,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(a.CREATED_USER_ID AS BIGINT) AS INT)) AS CREATED_USER_ID,
    ISNULL(energy.dbo.FN_SAFE_DT(CAST(a.CREATED_TIMESTAMP AS DATETIME2)), GETDATE()) AS CREATED_TIMESTAMP,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(a.UPDATED_USER_ID AS BIGINT) AS INT)) AS UPDATED_USER_ID,
    energy.dbo.FN_SAFE_DT(CAST(a.UPDATED_TIMESTAMP AS DATETIME2))   AS UPDATED_TIMESTAMP,
    CAST(1 AS BIT)                                                  AS IS_ACTIVE,
    CAST(a.ORDER_NUMBER AS INT)                                     AS ORDER_NUMBER,
    LEFT(a.DESCRIPTION, 250)                                        AS DESCRIPTION,
    a.VERSION                                                       AS ABYS_VERSION,
    a.ACCOUNT_ID                                                    AS ABYS_ACCOUNT_ID
FROM izgazMGR.dbo.LP_ACCOUNT a;
GO

CREATE OR ALTER VIEW dbo.VW_MIG_LP_INCOME_SOURCE
AS
SELECT
    s.ID                                                            AS ABYS_ID,
    CAST(TRY_CAST(s.LEGAL_PROCEEDING_ID AS BIGINT) AS INT)          AS LEGAL_PROCEEDING_ID,
    CAST(TRY_CAST(s.EXPENSE_CAUSE_ID AS BIGINT) AS INT)             AS EXPENSE_CAUSE_ID,
    s.AMOUNT,
    CAST(TRY_CAST(s.ACCOUNT_ID AS BIGINT) AS INT)                   AS INVOICE_ID,
    CAST(s.STATUS AS TINYINT)                                       AS STATUS,
    s.DESCRIPTION,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.CREATED_USER_ID AS BIGINT) AS INT)) AS CREATED_USER_ID,
    CAST(s.CREATED_TIMESTAMP AS DATETIMEOFFSET(6))                  AS CREATED_TIMESTAMP,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.UPDATED_USER_ID AS BIGINT) AS INT)) AS UPDATED_USER_ID,
    CAST(s.UPDATED_TIMESTAMP AS DATETIMEOFFSET(6))                  AS UPDATED_TIMESTAMP,
    CAST(1 AS BIT)                                                  AS IS_ACTIVE,
    CAST(energy.dbo.FN_SAFE_DT(CAST(s.ACTION_DATE AS DATETIME2)) AS DATE) AS ACTION_DATE,
    CAST(s.SEND_PAYED_DATE AS DATETIME2(0))                         AS SEND_PAYED_DATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.SEND_PAYED_USER_ID AS BIGINT) AS INT)) AS SEND_PAYED_USER_ID,
    s.VERSION                                                       AS ABYS_VERSION,
    s.ACCOUNT_ID                                                    AS ABYS_ACCOUNT_ID
FROM izgazMGR.dbo.LP_INCOME s;
GO

IF OBJECT_ID('dbo.SP_MIGRATE_LP', 'P') IS NOT NULL
    EXEC sys.sp_refreshsqlmodule N'dbo.SP_MIGRATE_LP';
GO

EXEC dbo.SP_MIG_LP_VALIDATE_ALL @RaiseOnMissing = 0;
GO

