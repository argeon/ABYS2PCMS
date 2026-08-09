/* ============================================================
   SCRIPT_ID : PROJECT_SETUP
   SCRIPT_NO : 590
   FILE      : 590_PROJECT__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.LS_PROJECT
--   → energy.dbo.LS_005_01_PROJECT
--
-- LREF    : IDENTITY (yeni) — kaynak LREF TASINMAZ
-- ABYS_ID : ORACLE_PROJECT_ID (kopru)
-- ABYS_LREF : kaynak LREF (izlenebilirlik)
-- STG_*   : ABYS_STG_* bridge kolonlari
--
-- Truncation:
--   CODE  nvarchar(124) → nvarchar(50)
--   OCODE nvarchar(50)  → nvarchar(20)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_PROJECT', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_005_01_PROJECT bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- Kaynak uzunluklari > hedef: truncation onleme (idempotent)
-- ------------------------------------------------------------
IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECT')
      AND c.name = 'CODE'
      AND (TYPE_NAME(c.user_type_id) <> 'nvarchar' OR (c.max_length > 0 AND c.max_length < 100))
)
    ALTER TABLE energy.dbo.LS_005_01_PROJECT ALTER COLUMN CODE NVARCHAR(50) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECT')
      AND c.name = 'OCODE'
      AND (TYPE_NAME(c.user_type_id) <> 'nvarchar' OR (c.max_length > 0 AND c.max_length < 40))
)
    ALTER TABLE energy.dbo.LS_005_01_PROJECT ALTER COLUMN OCODE NVARCHAR(20) NULL;
GO

-- ------------------------------------------------------------
-- ABYS bridge kolonlari — TABLO SONUNA (idempotent)
-- ------------------------------------------------------------
DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(200) NOT NULL);

INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 (N'ABYS_ID',                N'BIGINT NULL'),
 (N'ABYS_LREF',              N'BIGINT NULL'),
 (N'ABYS_FIRM_ID',           N'BIGINT NULL'),
 (N'ABYS_INVOICE_ID',        N'DECIMAL(22,0) NULL'),
 (N'ABYS_STG_PROJECT_YEAR',  N'SMALLINT NULL'),
 (N'ABYS_STG_PROJECT_NUMBER',N'BIGINT NULL'),
 (N'ABYS_STG_ORA_TYPE_ID',   N'BIGINT NULL'),
 (N'ABYS_STG_PI_TYPE_SET',   N'NVARCHAR(4000) NULL'),
 (N'ABYS_STG_HASMOD',        N'DECIMAL(22,0) NULL'),
 (N'ABYS_STG_ORA_STATUS',    N'SMALLINT NULL');

SELECT @Sql = @Sql + N'
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(''energy.dbo.LS_005_01_PROJECT'')
      AND name = ''' + COL_NAME + N'''
)
    ALTER TABLE energy.dbo.LS_005_01_PROJECT ADD ' + COL_NAME + N' ' + COL_DEF + N';'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECT')
      AND name = 'UX_LS_005_01_PROJECT_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_005_01_PROJECT_ABYS_ID
        ON energy.dbo.LS_005_01_PROJECT (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECT')
      AND name = 'IX_LS_005_01_PROJECT_ABYS_LREF'
)
    CREATE NONCLUSTERED INDEX IX_LS_005_01_PROJECT_ABYS_LREF
        ON energy.dbo.LS_005_01_PROJECT (ABYS_LREF)
        INCLUDE (LREF)
        WHERE ABYS_LREF IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Kaynak / hedef kolon dogrulama
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_PROJECT_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_PROJECT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_PROJECT bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    -- CTAS (oracleCTAS/LS_PROJECT): ABYS_PROJECT_* + ORACLE_PROJECT_ID
    -- Eski STG_* adlari dump'ta yok; view asagida map eder.
    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('ORACLE_PROJECT_ID'), ('CODE'),
            ('TOTALFEE'), ('TAX'), ('GRANDTOTAL'), ('OCODE'),
            ('XTYPE'), ('PROJECT_TYPE_ID'), ('FIRM_ID'),
            ('INVOICE_ID'), ('STATID'),
            ('ABYS_PROJECT_YEAR'), ('ABYS_PROJECT_NUMBER'),
            ('ABYS_PROJECT_STATUS')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'LS_PROJECT' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_PROJECT eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        ELSE SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_PROJECT kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_PROJECT_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_PROJECT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_PROJECT bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('CODE'), ('TOTALFEE'), ('TAX'), ('GRANDTOTAL'),
            ('OCODE'), ('XTYPE'), ('PROJECT_TYPE_ID'), ('FIRM_ID'),
            ('INVOICE_ID'), ('STATID'),
            ('ABYS_ID'), ('ABYS_LREF'), ('ABYS_FIRM_ID'), ('ABYS_INVOICE_ID'),
            ('ABYS_STG_PROJECT_YEAR'), ('ABYS_STG_PROJECT_NUMBER'),
            ('ABYS_STG_ORA_TYPE_ID'), ('ABYS_STG_PI_TYPE_SET'),
            ('ABYS_STG_HASMOD'), ('ABYS_STG_ORA_STATUS')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECT')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_PROJECT eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        ELSE SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_PROJECT hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_PROJECT_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.SP_MIG_PROJECT_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    EXEC dbo.SP_MIG_PROJECT_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
END
GO

-- ------------------------------------------------------------
-- Kaynak view (kolon eslemesi tek nokta)
-- LREF IDENTITY — view'da yok / INSERT'te yazilmaz
-- Bridge key: ABYS_ID = ORACLE_PROJECT_ID
-- CTAS BNA fan-out: ayni ORACLE_PROJECT_ID birden fazla LREF → MIN(LREF) tek satir
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.VW_MIG_PROJECT_SOURCE
AS
SELECT
    CAST(s.ORACLE_PROJECT_ID AS BIGINT)                                     AS ABYS_ID,
    CAST(s.LREF AS BIGINT)                                                  AS ABYS_LREF,
    CAST(TRY_CAST(s.FIRM_ID AS BIGINT) AS BIGINT)                           AS ABYS_FIRM_ID,
    TRY_CAST(s.INVOICE_ID AS DECIMAL(22, 0))                                AS ABYS_INVOICE_ID,
    CAST(s.ABYS_PROJECT_YEAR AS SMALLINT)                                   AS ABYS_STG_PROJECT_YEAR,
    CAST(s.ABYS_PROJECT_NUMBER AS BIGINT)                                   AS ABYS_STG_PROJECT_NUMBER,
    CAST(TRY_CAST(s.PROJECT_TYPE_ID AS BIGINT) AS BIGINT)                   AS ABYS_STG_ORA_TYPE_ID,
    CAST(NULL AS NVARCHAR(4000))                                            AS ABYS_STG_PI_TYPE_SET,
    CAST(NULL AS DECIMAL(22, 0))                                            AS ABYS_STG_HASMOD,
    CAST(s.ABYS_PROJECT_STATUS AS SMALLINT)                                 AS ABYS_STG_ORA_STATUS,
    LEFT(s.CODE, 50)                                                        AS CODE,
    TRY_CAST(s.TOTALFEE AS MONEY)                                           AS TOTALFEE,
    TRY_CAST(s.TAX AS MONEY)                                                AS TAX,
    TRY_CAST(s.GRANDTOTAL AS MONEY)                                         AS GRANDTOTAL,
    LEFT(s.OCODE, 20)                                                       AS OCODE,
    CAST(TRY_CAST(s.XTYPE AS BIGINT) AS INT)                                AS XTYPE,
    CAST(TRY_CAST(s.PROJECT_TYPE_ID AS DECIMAL(22, 0)) AS INT)              AS PROJECT_TYPE_ID,
    CAST(TRY_CAST(s.FIRM_ID AS BIGINT) AS INT)                              AS FIRM_ID,
    CAST(TRY_CAST(s.INVOICE_ID AS DECIMAL(22, 0)) AS INT)                   AS INVOICE_ID,
    CAST(TRY_CAST(s.STATID AS DECIMAL(22, 0)) AS INT)                       AS STATID
FROM izgazMGR.dbo.LS_PROJECT s
INNER JOIN (
    SELECT ORACLE_PROJECT_ID, MIN(LREF) AS LREF
    FROM izgazMGR.dbo.LS_PROJECT
    WHERE ORACLE_PROJECT_ID IS NOT NULL
    GROUP BY ORACLE_PROJECT_ID
) d
    ON d.ORACLE_PROJECT_ID = s.ORACLE_PROJECT_ID
   AND d.LREF = s.LREF;
GO

EXEC dbo.SP_MIG_PROJECT_VALIDATE_SOURCE @RaiseOnMissing = 0;
EXEC dbo.SP_MIG_PROJECT_VALIDATE_TARGET @RaiseOnMissing = 0;
GO
