/* ============================================================
   SCRIPT_ID : REF_TARIFF_SETUP
   SCRIPT_NO : 130
   FILE      : 130_REF_TARIFF__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- Tarife parametreleri: CS_TARIFF* → LS_TARIFF*_PRM
--   LS_TARIFF_TYPE_PRM        ← CS_TARIFF_TYPE_PRM + CS_TARIFF_TYPE_PRM_LNG (LANG_ID=1)
--   LS_TARIFF_PRM             ← CS_TARIFF
--   LS_TARIFF_INCOME_PRM      ← CS_TARIFF_INCOME
--   LS_TARIFF_INCOME_DISCOUNT_PRM ← CS_TARIFF_INCOME_DISCOUNT
--
-- Hedef tablolar energy DB'de mevcut; bu script ABYS köprü kolonları,
-- kaynak/hedef kolon doğrulaması ve aktarım view'larını hazırlar.
-- ============================================================
USE energy;
GO
 
-- ------------------------------------------------------------
-- Ortak: hedef ABYS_ID köprüsü
-- ------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_TARIFF_TYPE_PRM') AND name = 'ABYS_ID')
    ALTER TABLE energy.dbo.LS_TARIFF_TYPE_PRM ADD ABYS_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_TARIFF_PRM') AND name = 'ABYS_ID')
    ALTER TABLE energy.dbo.LS_TARIFF_PRM ADD ABYS_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_TARIFF_INCOME_PRM') AND name = 'ABYS_ID')
    ALTER TABLE energy.dbo.LS_TARIFF_INCOME_PRM ADD ABYS_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_TARIFF_INCOME_DISCOUNT_PRM') AND name = 'ABYS_ID')
    ALTER TABLE energy.dbo.LS_TARIFF_INCOME_DISCOUNT_PRM ADD ABYS_ID BIGINT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LS_TARIFF_TYPE_PRM') AND name = 'UX_LS_TARIFF_TYPE_PRM_ABYS_ID')
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_TARIFF_TYPE_PRM_ABYS_ID
        ON energy.dbo.LS_TARIFF_TYPE_PRM (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LS_TARIFF_PRM') AND name = 'UX_LS_TARIFF_PRM_ABYS_ID')
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_TARIFF_PRM_ABYS_ID
        ON energy.dbo.LS_TARIFF_PRM (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LS_TARIFF_INCOME_PRM') AND name = 'UX_LS_TARIFF_INCOME_PRM_ABYS_ID')
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_TARIFF_INCOME_PRM_ABYS_ID
        ON energy.dbo.LS_TARIFF_INCOME_PRM (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LS_TARIFF_INCOME_DISCOUNT_PRM') AND name = 'UX_LS_TARIFF_INCOME_DISCOUNT_PRM_ABYS_ID')
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_TARIFF_INCOME_DISCOUNT_PRM_ABYS_ID
        ON energy.dbo.LS_TARIFF_INCOME_DISCOUNT_PRM (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Tarife aktarımı için ilişki gevşetme
-- ------------------------------------------------------------
IF EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_LS_TARIFF_INCOME_PRM_LS_TARIFF_PRM'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_TARIFF_INCOME_PRM')
)
    ALTER TABLE energy.dbo.LS_TARIFF_INCOME_PRM
    DROP CONSTRAINT FK_LS_TARIFF_INCOME_PRM_LS_TARIFF_PRM;
GO

IF EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_LS_TARIFF_TYPE_PRM_LS_AGR_TYPE1'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_TARIFF_TYPE_PRM')
)
    ALTER TABLE energy.dbo.LS_TARIFF_TYPE_PRM
    DROP CONSTRAINT FK_LS_TARIFF_TYPE_PRM_LS_AGR_TYPE1;
GO

IF EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_LS_TARIFF_INCOME_PRM_LS_INCOME_PRM'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_TARIFF_INCOME_PRM')
)
    ALTER TABLE energy.dbo.LS_TARIFF_INCOME_PRM
    DROP CONSTRAINT FK_LS_TARIFF_INCOME_PRM_LS_INCOME_PRM;
GO

IF EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_LS_TARIFF_INCOME_DISCOUNT_PRM_LS_INCOME_PRM'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_TARIFF_INCOME_DISCOUNT_PRM')
)
    ALTER TABLE energy.dbo.LS_TARIFF_INCOME_DISCOUNT_PRM
    DROP CONSTRAINT FK_LS_TARIFF_INCOME_DISCOUNT_PRM_LS_INCOME_PRM;
GO

-- ------------------------------------------------------------
-- Hedef numeric precision/scale'a göre güvenli değer üret
-- ------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.FN_MIG_FIT_NUMERIC
(
    @Value      DECIMAL(38, 10),
    @TableName  SYSNAME,
    @ColumnName SYSNAME
)
RETURNS DECIMAL(38, 10)
AS
BEGIN
    DECLARE @Precision INT;
    DECLARE @Scale INT;
    DECLARE @Rounded DECIMAL(38, 10);
    DECLARE @AbsMax DECIMAL(38, 10);

    IF @Value IS NULL
        RETURN NULL;

    SELECT
        @Precision = c.precision,
        @Scale = c.scale
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(N'energy.dbo.' + @TableName)
      AND c.name = @ColumnName;

    IF @Precision IS NULL OR @Scale IS NULL
        RETURN @Value;

    SET @Rounded = ROUND(@Value, @Scale);

    IF @Precision - @Scale <= 0
        SET @AbsMax = CAST(1 AS DECIMAL(38, 10)) - POWER(CAST(10 AS DECIMAL(38, 10)), -@Scale);
    ELSE
        SET @AbsMax = POWER(CAST(10 AS DECIMAL(38, 10)), @Precision - @Scale)
                    - POWER(CAST(10 AS DECIMAL(38, 10)), -@Scale);

    IF ABS(@Rounded) > @AbsMax
        RETURN 0;

    RETURN @Rounded;
END
GO

-- ------------------------------------------------------------
-- Kolon doğrulama yardımcıları
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_TARIFF_VALIDATE_TABLE_COLUMNS
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
        + REPLACE(
            REPLACE(
                REPLACE(ISNULL(@RequiredCols, N''), N'&', N'&amp;'),
                N'<', N'&lt;'
            ),
            N',', N'</c><c>'
        )
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
        WHERE s.name = @SchemaName
          AND t.name = @TableName
          AND c.name = r.COL_NAME
    )
    FOR XML PATH(''''), TYPE
).value(''.'', ''nvarchar(max)''), 1, 2, N'''');';

    EXEC sp_executesql
        @Sql,
        N'@ColsXml XML, @SchemaName SYSNAME, @TableName SYSNAME, @MissingOut NVARCHAR(MAX) OUTPUT',
        @ColsXml = @Xml,
        @SchemaName = @SchemaName,
        @TableName = @TableName,
        @MissingOut = @Missing OUTPUT;

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = @Label + N' eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_TARIFF_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_TARIFF_VALIDATE_TABLE_COLUMNS
        @DbName = 'izgazMGR', @SchemaName = 'dbo', @TableName = 'CS_TARIFF_TYPE_PRM',
        @RequiredCols = N'ID,CODE,SUBSCRIBER_TYPE_ID,YEARLY_CONSUMPTION,MAX_CONSUMPTION,MIN_CONSUMPTION,HAS_CPI,TYPE,ACCOUNT_CODE,CASH_SALE_ACCOUNT_CODE,IS_ACTIVE,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,VERSION,AREA_ID,EXPIRY_DAY,IS_HANDICAPPED,COMM_ACCOUNT_CODE,COMM_FINANCE_CODE,ACCOUNT_CODE_FINANCE,DISTRIBUTION_MIN_LIMIT,DISTRIBUTION_MAX_LIMIT,IS_E_SUBSCRIPTION,USE_MIN_INDEPENDENT_UNIT_CALC,PRICE_TYPE,IS_USABLE_PREPAID,PARTICIPATION_FEE_MULTIPLIER,TARIFF_TYPE_ID_FOR_ONLINE,ACTIVITY_TYPE_ID_FOR_ONLINE,TARIFF_GROUP_TYPE,DONT_APPLY_FOR_CANCELLATION',
        @Label = N'CS_TARIFF_TYPE_PRM', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_TARIFF_VALIDATE_TABLE_COLUMNS
        @DbName = 'izgazMGR', @SchemaName = 'dbo', @TableName = 'CS_TARIFF_TYPE_PRM_LNG',
        @RequiredCols = N'ID,PRM_ID,LANG_ID,VALUE',
        @Label = N'CS_TARIFF_TYPE_PRM_LNG', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_TARIFF_VALIDATE_TABLE_COLUMNS
        @DbName = 'izgazMGR', @SchemaName = 'dbo', @TableName = 'CS_TARIFF',
        @RequiredCols = N'ID,TARIFF_TYPE_ID,BEGIN_DATE,END_DATE,IS_ACTIVE,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,VERSION,LEVEL_TYPE',
        @Label = N'CS_TARIFF', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_TARIFF_VALIDATE_TABLE_COLUMNS
        @DbName = 'izgazMGR', @SchemaName = 'dbo', @TableName = 'CS_TARIFF_INCOME',
        @RequiredCols = N'ID,TARIFF_ID,LEVEL_NUMBER,INCOME_ID,CONSUMPTION,AMOUNT,VAT_RATE,CURRENCY_UNIT_ID,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,VERSION,MUNICIPAL_ID,IS_CAL_DAY_DIFF,CONSUMPTION_PERCENT,REAL_COST',
        @Label = N'CS_TARIFF_INCOME', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_TARIFF_VALIDATE_TABLE_COLUMNS
        @DbName = 'izgazMGR', @SchemaName = 'dbo', @TableName = 'CS_TARIFF_INCOME_DISCOUNT',
        @RequiredCols = N'ID,TARIFF_ID,INCOME_ID,DISCOUNT_RATE,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,VERSION,DISCOUNT_M3',
        @Label = N'CS_TARIFF_INCOME_DISCOUNT', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    IF @RaiseOnMissing = 0
        SELECT N'Tarife kaynak tablolari kolon dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_TARIFF_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_TARIFF_VALIDATE_TABLE_COLUMNS
        @DbName = 'energy', @SchemaName = 'dbo', @TableName = 'LS_TARIFF_TYPE_PRM',
        @RequiredCols = N'ABYS_ID,COMPANY_ID,CODE,SUBSCRIBER_TYPE_ID,EXPIRY_DAY,YEARLY_CONSUMPTION,MIN_CONSUMPTION,MAX_CONSUMPTION,DISTRIBUTION_MIN_LIMIT,DISTRIBUTION_MAX_LIMIT,PARTICIPATION_FEE_MULTIPLIER,USE_MIN_INDEPENDENT_UNIT_CALC,TARIFF_TYPE,TARIFF_PRICE_TYPE,ACCOUNT_CODE,ACCOUNT_CODE_FINANCE,CASH_SALE_ACCOUNT_CODE,TARIFF_TYPE_NAME,COMM_ACCOUNT_CODE,COMM_FINANCE_CODE,AREA_ID,TARIFF_GROUP_TYPE,NEIGHBORHOOD_ID,IS_E_SUBSCRIPTION,TARIFF_TYPE_ID_FOR_ONLINE,ACTIVITY_TYPE_ID_FOR_ONLINE,IS_DONT_APPLY_FOR_CANCELLATION,IS_USABLE_PREPAID,IS_HAS_CPI,IS_HANDICAPPED,IS_MIN_ACCOUNT,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,DELETED_USER_ID,DELETED_TIMESTAMP,IS_DELETED,IS_ACTIVE,VERSION',
        @Label = N'LS_TARIFF_TYPE_PRM', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_TARIFF_VALIDATE_TABLE_COLUMNS
        @DbName = 'energy', @SchemaName = 'dbo', @TableName = 'LS_TARIFF_PRM',
        @RequiredCols = N'ABYS_ID,COMPANY_ID,TARIFF_TYPE_ID,BEGIN_DATE,END_DATE,IS_ACTIVE,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,DELETED_USER_ID,DELETED_TIMESTAMP,IS_DELETED,VERSION',
        @Label = N'LS_TARIFF_PRM', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_TARIFF_VALIDATE_TABLE_COLUMNS
        @DbName = 'energy', @SchemaName = 'dbo', @TableName = 'LS_TARIFF_INCOME_PRM',
        @RequiredCols = N'ABYS_ID,COMPANY_ID,TARIFF_ID,LEVEL_NUMBER,INCOME_ID,CONSUMPTION,AMOUNT,VAT_RATE,CURRENCY_UNIT_ID,MUNICIPAL_ID,IS_CAL_DAY_DIFF,CONSUMPTION_PERCENT,REAL_COST,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,DELETED_USER_ID,DELETED_TIMESTAMP,IS_DELETED,VERSION',
        @Label = N'LS_TARIFF_INCOME_PRM', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_TARIFF_VALIDATE_TABLE_COLUMNS
        @DbName = 'energy', @SchemaName = 'dbo', @TableName = 'LS_TARIFF_INCOME_DISCOUNT_PRM',
        @RequiredCols = N'ABYS_ID,COMPANY_ID,TARIFF_ID,INCOME_ID,DISCOUNT_RATE,DISCOUNT_M3,CREATED_USER_ID,CREATED_TIMESTAMP,UPDATED_USER_ID,UPDATED_TIMESTAMP,DELETED_USER_ID,DELETED_TIMESTAMP,IS_DELETED,VERSION',
        @Label = N'LS_TARIFF_INCOME_DISCOUNT_PRM', @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    IF @RaiseOnMissing = 0
        SELECT N'Tarife hedef tablolari kolon dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_TARIFF_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_TARIFF_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_TARIFF_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    IF @RaiseOnMissing = 0
        SELECT N'Tarife kaynak + hedef kolon dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Kaynak view'lar (alan alan dönüşüm)
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.VW_MIG_TARIFF_TYPE_PRM_SOURCE
AS
SELECT
    tt.ID                                                           AS ABYS_ID,
    LEFT(tt.CODE, 10)                                               AS CODE,
    CAST(TRY_CAST(tt.SUBSCRIBER_TYPE_ID AS BIGINT) AS INT)          AS SUBSCRIBER_TYPE_ID,
    CAST(tt.EXPIRY_DAY AS TINYINT)                                  AS EXPIRY_DAY,
    CAST(tt.YEARLY_CONSUMPTION AS DECIMAL(18, 2))                   AS YEARLY_CONSUMPTION,
    CAST(tt.MIN_CONSUMPTION AS DECIMAL(18, 2))                      AS MIN_CONSUMPTION,
    CAST(tt.MAX_CONSUMPTION AS DECIMAL(18, 2))                      AS MAX_CONSUMPTION,
    CAST(tt.DISTRIBUTION_MIN_LIMIT AS DECIMAL(18, 0))               AS DISTRIBUTION_MIN_LIMIT,
    CAST(tt.DISTRIBUTION_MAX_LIMIT AS DECIMAL(18, 0))               AS DISTRIBUTION_MAX_LIMIT,
    CAST(tt.PARTICIPATION_FEE_MULTIPLIER AS DECIMAL(10, 2))         AS PARTICIPATION_FEE_MULTIPLIER,
    CAST(tt.USE_MIN_INDEPENDENT_UNIT_CALC AS TINYINT)               AS USE_MIN_INDEPENDENT_UNIT_CALC,
    CAST(tt.TYPE AS INT)                                            AS TARIFF_TYPE,
    CAST(tt.PRICE_TYPE AS INT)                                      AS TARIFF_PRICE_TYPE,
    LEFT(tt.ACCOUNT_CODE, 20)                                       AS ACCOUNT_CODE,
    LEFT(tt.ACCOUNT_CODE_FINANCE, 20)                               AS ACCOUNT_CODE_FINANCE,
    LEFT(tt.CASH_SALE_ACCOUNT_CODE, 10)                             AS CASH_SALE_ACCOUNT_CODE,
    tpl.VALUE                                                       AS TARIFF_TYPE_NAME,
    LEFT(tt.COMM_ACCOUNT_CODE, 20)                                  AS COMM_ACCOUNT_CODE,
    LEFT(tt.COMM_FINANCE_CODE, 20)                                  AS COMM_FINANCE_CODE,
    CAST(TRY_CAST(tt.AREA_ID AS BIGINT) AS INT)                     AS AREA_ID,
    tt.TARIFF_GROUP_TYPE                                            AS TARIFF_GROUP_TYPE,
    CAST(NULL AS INT)                                               AS NEIGHBORHOOD_ID,
    CAST(CASE WHEN ISNULL(tt.IS_E_SUBSCRIPTION, 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS IS_E_SUBSCRIPTION,
    CAST(TRY_CAST(tt.TARIFF_TYPE_ID_FOR_ONLINE AS BIGINT) AS INT)   AS TARIFF_TYPE_ID_FOR_ONLINE,
    CAST(TRY_CAST(tt.ACTIVITY_TYPE_ID_FOR_ONLINE AS BIGINT) AS INT) AS ACTIVITY_TYPE_ID_FOR_ONLINE,
    CAST(CASE WHEN ISNULL(tt.DONT_APPLY_FOR_CANCELLATION, 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS IS_DONT_APPLY_FOR_CANCELLATION,
    CAST(CASE WHEN ISNULL(tt.IS_USABLE_PREPAID, 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS IS_USABLE_PREPAID,
    CAST(CASE WHEN ISNULL(tt.HAS_CPI, 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS IS_HAS_CPI,
    CAST(CASE WHEN ISNULL(tt.IS_HANDICAPPED, 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS IS_HANDICAPPED,
    CAST(NULL AS BIT)                                               AS IS_MIN_ACCOUNT,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(tt.CREATED_USER_ID AS BIGINT) AS INT)) AS CREATED_USER_ID,
    ISNULL(energy.dbo.FN_SAFE_DT(CAST(tt.CREATED_TIMESTAMP AS DATETIME2)), GETDATE()) AS CREATED_TIMESTAMP,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(tt.UPDATED_USER_ID AS BIGINT) AS INT)) AS UPDATED_USER_ID,
    energy.dbo.FN_SAFE_DT(CAST(tt.UPDATED_TIMESTAMP AS DATETIME2))  AS UPDATED_TIMESTAMP,
    CAST(NULL AS INT)                                               AS DELETED_USER_ID,
    CAST(NULL AS DATETIME)                                          AS DELETED_TIMESTAMP,
    CAST(0 AS BIT)                                                  AS IS_DELETED,
    CAST(CASE WHEN ISNULL(tt.IS_ACTIVE, 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS IS_ACTIVE,
    CAST(TRY_CAST(tt.VERSION AS BIGINT) AS INT)                     AS VERSION
FROM izgazMGR.dbo.CS_TARIFF_TYPE_PRM tt
LEFT JOIN izgazMGR.dbo.CS_TARIFF_TYPE_PRM_LNG tpl
    ON tpl.PRM_ID = tt.ID
   AND tpl.LANG_ID = 1;
GO

CREATE OR ALTER VIEW dbo.VW_MIG_TARIFF_PRM_SOURCE
AS
SELECT
    s.ID                                                            AS ABYS_ID,
    s.TARIFF_TYPE_ID                                                AS ABYS_TARIFF_TYPE_ID,
  (
        SELECT TOP (1) t.ID
        FROM energy.dbo.LS_TARIFF_TYPE_PRM t
        WHERE t.ABYS_ID = s.TARIFF_TYPE_ID
        ORDER BY t.ID
    )                                                               AS RESOLVED_TARIFF_TYPE_ID,
    energy.dbo.FN_SAFE_DT(CAST(s.BEGIN_DATE AS DATETIME2))          AS BEGIN_DATE,
    energy.dbo.FN_SAFE_DT(CAST(s.END_DATE AS DATETIME2))            AS END_DATE,
    CAST(s.LEVEL_TYPE AS INT)                                       AS LEVEL_TYPE,
    CAST(CASE WHEN ISNULL(s.IS_ACTIVE, 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS IS_ACTIVE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.CREATED_USER_ID AS BIGINT) AS INT)) AS CREATED_USER_ID,
    ISNULL(energy.dbo.FN_SAFE_DT(CAST(s.CREATED_TIMESTAMP AS DATETIME2)), GETDATE()) AS CREATED_TIMESTAMP,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.UPDATED_USER_ID AS BIGINT) AS INT)) AS UPDATED_USER_ID,
    energy.dbo.FN_SAFE_DT(CAST(s.UPDATED_TIMESTAMP AS DATETIME2))   AS UPDATED_TIMESTAMP,
    CAST(NULL AS INT)                                               AS DELETED_USER_ID,
    CAST(NULL AS DATETIME)                                          AS DELETED_TIMESTAMP,
    CAST(0 AS BIT)                                                  AS IS_DELETED,
    CAST(TRY_CAST(s.VERSION AS BIGINT) AS INT)                        AS VERSION
FROM izgazMGR.dbo.CS_TARIFF s;
GO

CREATE OR ALTER VIEW dbo.VW_MIG_TARIFF_INCOME_PRM_SOURCE
AS
SELECT
    s.ID                                                            AS ABYS_ID,
    s.TARIFF_ID                                                     AS ABYS_TARIFF_ID,
  (
        SELECT TOP (1) t.ID
        FROM energy.dbo.LS_TARIFF_PRM t
        WHERE t.ABYS_ID = s.TARIFF_ID
        ORDER BY t.ID
    )                                                               AS RESOLVED_TARIFF_ID,
    CAST(s.LEVEL_NUMBER AS SMALLINT)                                AS LEVEL_NUMBER,
    CAST(TRY_CAST(s.INCOME_ID AS BIGINT) AS INT)                     AS INCOME_ID,
    dbo.FN_MIG_FIT_NUMERIC(TRY_CAST(s.CONSUMPTION AS DECIMAL(38, 10)), N'LS_TARIFF_INCOME_PRM', N'CONSUMPTION') AS CONSUMPTION,
    dbo.FN_MIG_FIT_NUMERIC(TRY_CAST(s.AMOUNT AS DECIMAL(38, 10)), N'LS_TARIFF_INCOME_PRM', N'AMOUNT')           AS AMOUNT,
    dbo.FN_MIG_FIT_NUMERIC(TRY_CAST(s.VAT_RATE AS DECIMAL(38, 10)), N'LS_TARIFF_INCOME_PRM', N'VAT_RATE')       AS VAT_RATE,
    CAST(TRY_CAST(s.CURRENCY_UNIT_ID AS BIGINT) AS INT)              AS CURRENCY_UNIT_ID,
    CAST(TRY_CAST(s.MUNICIPAL_ID AS BIGINT) AS INT)                 AS MUNICIPAL_ID,
    CAST(ISNULL(s.IS_CAL_DAY_DIFF, 0) AS SMALLINT)                  AS IS_CAL_DAY_DIFF,
    dbo.FN_MIG_FIT_NUMERIC(
        CASE
            WHEN s.CONSUMPTION_PERCENT IS NULL THEN NULL
            WHEN ABS(TRY_CAST(s.CONSUMPTION_PERCENT AS DECIMAL(18, 6))) <= 0.99
                THEN TRY_CAST(s.CONSUMPTION_PERCENT AS DECIMAL(18, 6))
            WHEN ABS(TRY_CAST(s.CONSUMPTION_PERCENT AS DECIMAL(18, 6))) <= 99.00
                THEN TRY_CAST(s.CONSUMPTION_PERCENT AS DECIMAL(18, 6)) / 100.0
            ELSE 0
        END,
        N'LS_TARIFF_INCOME_PRM',
        N'CONSUMPTION_PERCENT'
    )                                                               AS CONSUMPTION_PERCENT,
    dbo.FN_MIG_FIT_NUMERIC(TRY_CAST(s.REAL_COST AS DECIMAL(38, 10)), N'LS_TARIFF_INCOME_PRM', N'REAL_COST')     AS REAL_COST,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.CREATED_USER_ID AS BIGINT) AS INT)) AS CREATED_USER_ID,
    ISNULL(energy.dbo.FN_SAFE_DT(CAST(s.CREATED_TIMESTAMP AS DATETIME2)), GETDATE()) AS CREATED_TIMESTAMP,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.UPDATED_USER_ID AS BIGINT) AS INT)) AS UPDATED_USER_ID,
    energy.dbo.FN_SAFE_DT(CAST(s.UPDATED_TIMESTAMP AS DATETIME2))   AS UPDATED_TIMESTAMP,
    CAST(NULL AS INT)                                               AS DELETED_USER_ID,
    CAST(NULL AS DATETIME)                                          AS DELETED_TIMESTAMP,
    CAST(0 AS BIT)                                                  AS IS_DELETED,
    CAST(TRY_CAST(s.VERSION AS BIGINT) AS INT)                        AS VERSION
FROM izgazMGR.dbo.CS_TARIFF_INCOME s;
GO

CREATE OR ALTER VIEW dbo.VW_MIG_TARIFF_INCOME_DISCOUNT_PRM_SOURCE
AS
SELECT
    s.ID                                                            AS ABYS_ID,
    s.TARIFF_ID                                                     AS ABYS_TARIFF_ID,
  (
        SELECT TOP (1) t.ID
        FROM energy.dbo.LS_TARIFF_PRM t
        WHERE t.ABYS_ID = s.TARIFF_ID
        ORDER BY t.ID
    )                                                               AS RESOLVED_TARIFF_ID,
    CAST(TRY_CAST(s.INCOME_ID AS BIGINT) AS INT)                     AS INCOME_ID,
    CAST(s.DISCOUNT_RATE AS DECIMAL(4, 3))                          AS DISCOUNT_RATE,
    CAST(s.DISCOUNT_M3 AS DECIMAL(10, 3))                           AS DISCOUNT_M3,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.CREATED_USER_ID AS BIGINT) AS INT)) AS CREATED_USER_ID,
    ISNULL(energy.dbo.FN_SAFE_DT(CAST(s.CREATED_TIMESTAMP AS DATETIME2)), GETDATE()) AS CREATED_TIMESTAMP,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.UPDATED_USER_ID AS BIGINT) AS INT)) AS UPDATED_USER_ID,
    energy.dbo.FN_SAFE_DT(CAST(s.UPDATED_TIMESTAMP AS DATETIME2))   AS UPDATED_TIMESTAMP,
    CAST(NULL AS INT)                                               AS DELETED_USER_ID,
    CAST(NULL AS DATETIME)                                          AS DELETED_TIMESTAMP,
    CAST(0 AS BIT)                                                  AS IS_DELETED,
    CAST(TRY_CAST(s.VERSION AS BIGINT) AS INT)                        AS VERSION
FROM izgazMGR.dbo.CS_TARIFF_INCOME_DISCOUNT s;
GO

IF OBJECT_ID('dbo.SP_MIGRATE_LS_TARIFF', 'P') IS NOT NULL
    EXEC sys.sp_refreshsqlmodule N'dbo.SP_MIGRATE_LS_TARIFF';
GO

EXEC dbo.SP_MIG_TARIFF_VALIDATE_ALL @RaiseOnMissing = 0;
GO

