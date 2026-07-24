/* ============================================================
   SCRIPT_ID : READ_INCOME_SETUP
   SCRIPT_NO : 510
   FILE      : 510_READ_INCOME__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.CS_READING_INCOME → energy.dbo.LS_005_ReadingIncome
--   LREF ← ABYS_ID (IDENTITY_INSERT)
--   READING_ID ← CS_READING_INCOME.READING_ID (LS_005_Reading migrate sonrasi)
--
-- Not: Tarife snapshot kolonlari (LIMIT_*, GAS_UNIT_PRICE_*, SKB_*) kaynakta
--      yok; view'da NULL. Is kurali netlesince genisletilebilir.
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- Hedef ABYS köprü kolonları
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_ReadingIncome') AND name = 'ABYS_ID'
)
    ALTER TABLE energy.dbo.LS_005_ReadingIncome ADD ABYS_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_ReadingIncome') AND name = 'ABYS_READING_ID'
)
    ALTER TABLE energy.dbo.LS_005_ReadingIncome ADD ABYS_READING_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_ReadingIncome') AND name = 'ABYS_INCOME_ID'
)
    ALTER TABLE energy.dbo.LS_005_ReadingIncome ADD ABYS_INCOME_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_ReadingIncome')
      AND name = 'UX_LS005_READING_INCOME_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS005_READING_INCOME_ABYS_ID
        ON energy.dbo.LS_005_ReadingIncome (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_ReadingIncome')
      AND name = 'IX_LS005_READING_INCOME_ABYS_READING'
)
    CREATE NONCLUSTERED INDEX IX_LS005_READING_INCOME_ABYS_READING
        ON energy.dbo.LS_005_ReadingIncome (ABYS_READING_ID)
        INCLUDE (LREF, READING_ID)
        WHERE ABYS_READING_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Kaynak / hedef kolon doğrulama
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_READING_INCOME_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.CS_READING_INCOME', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.CS_READING_INCOME bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('ID'), ('READING_ID'), ('INCOME_ID'),
            ('AMOUNT'), ('AMOUNT_1'), ('AMOUNT_2'), ('AMOUNT_3'), ('AMOUNT_4'), ('AMOUNT_5'),
            ('IS_DISCOUNT'), ('FIRST_DATE'), ('LAST_DATE')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'CS_READING_INCOME' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'CS_READING_INCOME eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'CS_READING_INCOME kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_READING_INCOME_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_ReadingIncome', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_ReadingIncome bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('READING_ID'), ('IS_DISCOUNT'),
            ('TARIFF_INCOME_AMOUNT'), ('TARIFF_INCOME_AMOUNT1'), ('TARIFF_INCOME_AMOUNT2'),
            ('TARIFF_INCOME_AMOUNT3'), ('TARIFF_INCOME_AMOUNT4'), ('TARIFF_INCOME_AMOUNT5'),
            ('TARIFF_INCOME_CODE'), ('ADDDATE'), ('ADDUSER'),
            ('TARIFF_BEGIN_DATE'), ('TARIFF_END_DATE'),
            ('DAY_COUNT'), ('PERIOD'),
            ('LIMIT_1'), ('LIMIT_2'), ('CALCULATE_LIMIT'), ('SKB_UNIT_PRICE'), ('TOTAT_DAY_COUNT'),
            ('GAS_UNIT_PRICE_1'), ('GAS_UNIT_PRICE_2'),
            ('DAILY_LIMIT_1'), ('MONTHLY_LIMIT_1'), ('DAILY_LIMIT_2'), ('MONTHLY_LIMIT_2'),
            ('ABYS_ID'), ('ABYS_READING_ID'), ('ABYS_INCOME_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_ReadingIncome')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_ReadingIncome eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_ReadingIncome hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_READING_INCOME_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_READING_INCOME_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_READING_INCOME_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    IF @RaiseOnMissing = 0
        SELECT N'CS_READING_INCOME kaynak + LS_005_ReadingIncome hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Kaynak view
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.VW_MIG_LS005_READING_INCOME_SOURCE
AS
SELECT
    CAST(ri.ID AS BIGINT)                                           AS ABYS_ID,
    CAST(ri.READING_ID AS BIGINT)                                   AS ABYS_READING_ID,
    CAST(ri.INCOME_ID AS BIGINT)                                    AS ABYS_INCOME_ID,
    CAST(ri.READING_ID AS BIGINT)                                   AS READING_ID,
    CAST(CASE WHEN ISNULL(ri.IS_DISCOUNT, 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS IS_DISCOUNT,
    TRY_CAST(ri.AMOUNT   AS FLOAT)                                  AS TARIFF_INCOME_AMOUNT,
    TRY_CAST(ri.AMOUNT_1 AS FLOAT)                                  AS TARIFF_INCOME_AMOUNT1,
    TRY_CAST(ri.AMOUNT_2 AS FLOAT)                                  AS TARIFF_INCOME_AMOUNT2,
    TRY_CAST(ri.AMOUNT_3 AS FLOAT)                                  AS TARIFF_INCOME_AMOUNT3,
    TRY_CAST(ri.AMOUNT_4 AS FLOAT)                                  AS TARIFF_INCOME_AMOUNT4,
    TRY_CAST(ri.AMOUNT_5 AS FLOAT)                                  AS TARIFF_INCOME_AMOUNT5,
    LEFT(COALESCE(ip.CODE, CAST(ri.INCOME_ID AS NVARCHAR(50))), 50) AS TARIFF_INCOME_CODE,
    energy.dbo.FN_SAFE_DT(CAST(ri.FIRST_DATE AS DATETIME2))         AS TARIFF_BEGIN_DATE,
    energy.dbo.FN_SAFE_DT(CAST(ri.LAST_DATE  AS DATETIME2))         AS TARIFF_END_DATE,
    CASE
        WHEN ri.FIRST_DATE IS NOT NULL AND ri.LAST_DATE IS NOT NULL
            THEN DATEDIFF(DAY, CAST(ri.FIRST_DATE AS DATE), CAST(ri.LAST_DATE AS DATE)) + 1
        ELSE NULL
    END                                                             AS DAY_COUNT,
    CAST(TRY_CAST(r.PERIOD AS BIGINT) AS INT)                       AS PERIOD,
    ISNULL(
        energy.dbo.FN_SAFE_DT(CAST(r.CREATED_TIMESTAMP AS DATETIME2)),
        GETDATE()
    )                                                               AS ADDDATE,
    ISNULL(energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(r.CREATED_USER_ID AS BIGINT) AS INT)), 1) AS ADDUSER,
    CAST(NULL AS FLOAT)                                             AS LIMIT_1,
    CAST(NULL AS FLOAT)                                             AS LIMIT_2,
    CAST(NULL AS BIT)                                               AS CALCULATE_LIMIT,
    CAST(NULL AS FLOAT)                                             AS SKB_UNIT_PRICE,
    CAST(NULL AS INT)                                               AS TOTAT_DAY_COUNT,
    CAST(NULL AS FLOAT)                                             AS GAS_UNIT_PRICE_1,
    CAST(NULL AS FLOAT)                                             AS GAS_UNIT_PRICE_2,
    CAST(NULL AS FLOAT)                                             AS DAILY_LIMIT_1,
    CAST(NULL AS FLOAT)                                             AS MONTHLY_LIMIT_1,
    CAST(NULL AS FLOAT)                                             AS DAILY_LIMIT_2,
    CAST(NULL AS FLOAT)                                             AS MONTHLY_LIMIT_2
FROM izgazMGR.dbo.CS_READING_INCOME ri
LEFT JOIN izgazMGR.dbo.CS_INCOME_PRM ip
    ON ip.ID = ri.INCOME_ID
LEFT JOIN izgazMGR.dbo.CS_READING r
    ON r.ID = ri.READING_ID;
GO

IF OBJECT_ID('dbo.SP_MIGRATE_LS005_READING_INCOME', 'P') IS NOT NULL
    EXEC sys.sp_refreshsqlmodule N'dbo.SP_MIGRATE_LS005_READING_INCOME';
GO

EXEC dbo.SP_MIG_READING_INCOME_VALIDATE_ALL @RaiseOnMissing = 0;
GO

