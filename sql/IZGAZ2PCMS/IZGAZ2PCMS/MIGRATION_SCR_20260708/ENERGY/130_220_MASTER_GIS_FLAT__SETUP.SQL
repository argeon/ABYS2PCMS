/* ============================================================
   SCRIPT_ID : MASTER_GIS_FLAT_SETUP
   SCRIPT_NO : 220
   FILE      : 220_MASTER_GIS_FLAT__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LS_FLAT — ABYS kolonları + kaynak view (izgazMGR.dbo.LS_FLAT staging)
-- ============================================================
USE energy;
GO

-- '100(KAPICI DAİRESİ)' gibi değerlerden FLATNR için sayısal önek (100)
CREATE OR ALTER FUNCTION dbo.FN_SAFE_FLATNR (@Val SQL_VARIANT)
RETURNS INT
AS
BEGIN
    DECLARE @s NVARCHAR(100) = LTRIM(RTRIM(CAST(@Val AS NVARCHAR(100))));
    IF @s IS NULL OR @s = N'' RETURN NULL;
    IF CHARINDEX(N'(', @s) > 0
        SET @s = LTRIM(RTRIM(LEFT(@s, CHARINDEX(N'(', @s) - 1)));
    RETURN TRY_CAST(@s AS INT);
END
GO

-- ------------------------------------------------------------
-- Hedef kolonlar (ABYS_* + map alanları)
-- ------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'ABYS_FLAT_ID')
    ALTER TABLE energy.dbo.LS_FLAT ADD ABYS_FLAT_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'ABYS_SUBSCRIBER_TYPE_ID')
    ALTER TABLE energy.dbo.LS_FLAT ADD ABYS_SUBSCRIBER_TYPE_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'ABYS_INSTALLATION_ID')
    ALTER TABLE energy.dbo.LS_FLAT ADD ABYS_INSTALLATION_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'ABYS_INSTALLATION_GSTATUS')
    ALTER TABLE energy.dbo.LS_FLAT ADD ABYS_INSTALLATION_GSTATUS SMALLINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'ABYS_STARTUP_DATE')
    ALTER TABLE energy.dbo.LS_FLAT ADD ABYS_STARTUP_DATE DATETIME NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'ABYS_INSTALLATION_STATUS_ID')
    ALTER TABLE energy.dbo.LS_FLAT ADD ABYS_INSTALLATION_STATUS_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'ABYS_INSTALLATION_CANCEL_DATE')
    ALTER TABLE energy.dbo.LS_FLAT ADD ABYS_INSTALLATION_CANCEL_DATE DATETIME NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'FLOOR_NUMBER')
    ALTER TABLE energy.dbo.LS_FLAT ADD FLOOR_NUMBER VARCHAR(20) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns c
    INNER JOIN sys.types t ON t.user_type_id = c.user_type_id
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_FLAT')
      AND c.name = 'FLOOR_NUMBER'
      AND t.name IN ('int', 'bigint', 'smallint', 'tinyint')
)
    ALTER TABLE energy.dbo.LS_FLAT ALTER COLUMN FLOOR_NUMBER VARCHAR(20) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'TYPE')
    ALTER TABLE energy.dbo.LS_FLAT ADD TYPE SMALLINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'ADDRESS_NUMBER')
    ALTER TABLE energy.dbo.LS_FLAT ADD ADDRESS_NUMBER NVARCHAR(50) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'NATIONAL_CODE')
    ALTER TABLE energy.dbo.LS_FLAT ADD NATIONAL_CODE BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'BUILDING_DOOR_ID')
    ALTER TABLE energy.dbo.LS_FLAT ADD BUILDING_DOOR_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'CREATED_TIMESTAMP')
    ALTER TABLE energy.dbo.LS_FLAT ADD CREATED_TIMESTAMP DATETIME NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'CREATED_USER_ID')
    ALTER TABLE energy.dbo.LS_FLAT ADD CREATED_USER_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'UPDATED_TIMESTAMP')
    ALTER TABLE energy.dbo.LS_FLAT ADD UPDATED_TIMESTAMP DATETIME NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'UPDATED_USER_ID')
    ALTER TABLE energy.dbo.LS_FLAT ADD UPDATED_USER_ID BIGINT NULL;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'UX_LS_FLAT_ENT_ABYS_FLAT')
    DROP INDEX UX_LS_FLAT_ENT_ABYS_FLAT ON energy.dbo.LS_FLAT;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'IX_LS_FLAT_ABYS_INSTALLATION')
    CREATE NONCLUSTERED INDEX IX_LS_FLAT_ABYS_INSTALLATION
        ON energy.dbo.LS_FLAT (ABYS_INSTALLATION_ID, ENT_ID)
        INCLUDE (LREF)
        WHERE ABYS_INSTALLATION_ID IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LS_FLAT') AND name = 'UX_LS_FLAT_ENT_ABYS_INSTALLATION')
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_FLAT_ENT_ABYS_INSTALLATION
        ON energy.dbo.LS_FLAT (ENT_ID, ABYS_INSTALLATION_ID)
        WHERE ABYS_INSTALLATION_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Kaynak staging kolonlari (SP/view derlemesinden ONCE)
-- ------------------------------------------------------------
IF OBJECT_ID('izgazMGR.dbo.LS_FLAT', 'U') IS NOT NULL
BEGIN
    IF COL_LENGTH('izgazMGR.dbo.LS_FLAT', 'MIG_ROW_ID') IS NOT NULL
       AND COLUMNPROPERTY(OBJECT_ID('izgazMGR.dbo.LS_FLAT'), 'MIG_ROW_ID', 'IsIdentity') = 1
    BEGIN
        IF EXISTS (
            SELECT 1 FROM izgazMGR.sys.indexes
            WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_FLAT')
              AND name = 'UX_LS_FLAT_STAGING_MIG_ROW'
        )
            DROP INDEX UX_LS_FLAT_STAGING_MIG_ROW ON izgazMGR.dbo.LS_FLAT;

        ALTER TABLE izgazMGR.dbo.LS_FLAT DROP COLUMN MIG_ROW_ID;
    END

    IF COL_LENGTH('izgazMGR.dbo.LS_FLAT', 'MIG_ROW_ID') IS NULL
        ALTER TABLE izgazMGR.dbo.LS_FLAT ADD MIG_ROW_ID BIGINT NULL;

    IF COL_LENGTH('izgazMGR.dbo.LS_FLAT', '_MIG_UID') IS NULL
        ALTER TABLE izgazMGR.dbo.LS_FLAT ADD _MIG_UID INT IDENTITY(1, 1) NOT NULL;
END
GO

-- ------------------------------------------------------------
-- Kaynak: MIG_ROW_ID atama (FLAT_CREATED_TIMESTAMP sirasi)
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_FLAT_PREP_SOURCE
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_FLAT', 'U') IS NULL
        RETURN;

    IF COL_LENGTH('izgazMGR.dbo.LS_FLAT', 'MIG_ROW_ID') IS NULL
       OR COL_LENGTH('izgazMGR.dbo.LS_FLAT', '_MIG_UID') IS NULL
    BEGIN
        RAISERROR('LS_FLAT staging: MIG_ROW_ID veya _MIG_UID kolonu yok. Once 220_MASTER_GIS_FLAT__setup.sql calistirin.', 16, 1);
        RETURN;
    END

    ;WITH Ordered AS (
        SELECT
            s._MIG_UID,
            ROW_NUMBER() OVER (
                ORDER BY
                    CAST(s.FLAT_CREATED_TIMESTAMP AS DATETIME2),
                    s.ABYS_INSTALLATION_ID,
                    s._MIG_UID
            ) AS NewMigRowId
        FROM izgazMGR.dbo.LS_FLAT s
        WHERE s.ABYS_INSTALLATION_ID IS NOT NULL
    )
    UPDATE s
    SET s.MIG_ROW_ID = o.NewMigRowId
    FROM izgazMGR.dbo.LS_FLAT s
    INNER JOIN Ordered o ON o._MIG_UID = s._MIG_UID;

    IF EXISTS (
        SELECT 1
        FROM izgazMGR.dbo.LS_FLAT
        WHERE ABYS_INSTALLATION_ID IS NOT NULL AND MIG_ROW_ID IS NULL
    )
        RAISERROR('LS_FLAT: MIG_ROW_ID atamasi tamamlanamadi.', 16, 1);

    IF EXISTS (
        SELECT 1 FROM izgazMGR.sys.indexes
        WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_FLAT')
          AND name = 'UX_LS_FLAT_STAGING_MIG_ROW'
    )
        DROP INDEX UX_LS_FLAT_STAGING_MIG_ROW ON izgazMGR.dbo.LS_FLAT;

    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_FLAT_STAGING_MIG_ROW
        ON izgazMGR.dbo.LS_FLAT (MIG_ROW_ID)
        WHERE MIG_ROW_ID IS NOT NULL;
END
GO

EXEC dbo.SP_MIG_FLAT_PREP_SOURCE;
GO

-- ------------------------------------------------------------
-- Kaynak view — PREP sonrasi (MIG_ROW_ID kolonu staging'de mevcut)
-- ------------------------------------------------------------
IF OBJECT_ID('izgazMGR.dbo.LS_FLAT', 'U') IS NOT NULL
   AND COL_LENGTH('izgazMGR.dbo.LS_FLAT', 'MIG_ROW_ID') IS NOT NULL
BEGIN
    DECLARE @EntIdExpr NVARCHAR(200) = CASE
        WHEN COL_LENGTH('izgazMGR.dbo.LS_FLAT', 'ENT_ID') IS NOT NULL
            THEN N'CAST(TRY_CAST(s.ENT_ID AS BIGINT) AS INT)'
        ELSE N'CAST(4102 AS INT)'
    END;

    DECLARE @AbysDoorCodeExpr NVARCHAR(200) = CASE
        WHEN COL_LENGTH('izgazMGR.dbo.LS_FLAT', 'ABYS_BUILDING_DOOR_CODE') IS NOT NULL
            THEN N's.ABYS_BUILDING_DOOR_CODE'
        ELSE N'CAST(NULL AS NVARCHAR(10))'
    END;

    DECLARE @AbysDoorIdExpr NVARCHAR(200) = CASE
        WHEN COL_LENGTH('izgazMGR.dbo.LS_FLAT', 'ABYS_BUILDING_DOOR_ID') IS NOT NULL
            THEN N'CAST(TRY_CAST(s.ABYS_BUILDING_DOOR_ID AS BIGINT) AS DECIMAL(22,0))'
        ELSE N'CAST(NULL AS DECIMAL(22,0))'
    END;

    DECLARE @ViewSql NVARCHAR(MAX);
    SET @ViewSql = N'
CREATE OR ALTER VIEW dbo.VW_MIG_LS_FLAT_SOURCE
AS
SELECT
    s.MIG_ROW_ID,
    CAST(TRY_CAST(s.FLATDEFN AS BIGINT) AS INT)              AS FLATDEFN,
    LEFT(CAST(s.FLOOR_NUMBER AS VARCHAR(20)), 20)            AS FLOOR_NUMBER,
    CAST(TRY_CAST(s.BNA_ID AS BIGINT) AS INT)                 AS BNA_ID,
    ' + @EntIdExpr + N'                                       AS ENT_ID,
    s.TYPE,
    s.ADDRESS_NUMBER,
    s.NATIONAL_CODE,
    s.BUILDING_DOOR_ID,
    ' + @AbysDoorCodeExpr + N'                                AS ABYS_BUILDING_DOOR_CODE,
    ' + @AbysDoorIdExpr + N'                                  AS ABYS_BUILDING_DOOR_ID,
    s.ABYS_SUBSCRIBER_TYPE_ID,
    s.ABYS_INSTALLATION_ID,
    s.ABYS_INSTALLATION_GSTATUS,
    s.ABYS_STARTUP_DATE_RAW,
    s.ABYS_INSTALLATION_STATUS_ID,
    s.ABYS_INSTALLATION_CANCELDATE                          AS ABYS_INSTALLATION_CANCEL_DATE_RAW,
    s.FLAT_CREATED_TIMESTAMP,
    s.FLAT_CREATED_USER_ID,
    s.FLAT_UPDATED_TIMESTAMP,
    s.FLAT_UPDATED_USER_ID,
    s.ABYS_FLAT_ID,
    COALESCE(s.FLAT_NUMBER_RAW, s.FLATNR)                     AS FLAT_NUMBER_RAW
FROM izgazMGR.dbo.LS_FLAT s
WHERE s.ABYS_INSTALLATION_ID IS NOT NULL
  AND s.MIG_ROW_ID IS NOT NULL';

    EXEC sys.sp_executesql @ViewSql;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_FLAT_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_FLAT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_FLAT bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('FLATNR'), ('FLATDEFN'), ('FLOOR_NUMBER'), ('BNA_ID'), ('ENT_ID'),
            ('TYPE'), ('ADDRESS_NUMBER'), ('NATIONAL_CODE'), ('BUILDING_DOOR_ID'),
            ('ABYS_BUILDING_DOOR_CODE'), ('ABYS_BUILDING_DOOR_ID'),
            ('ABYS_SUBSCRIBER_TYPE_ID'), ('ABYS_INSTALLATION_ID'),
            ('ABYS_INSTALLATION_GSTATUS'), ('ABYS_STARTUP_DATE_RAW'),
            ('ABYS_INSTALLATION_STATUS_ID'), ('ABYS_INSTALLATION_CANCELDATE'),
            ('FLAT_CREATED_TIMESTAMP'), ('FLAT_CREATED_USER_ID'),
            ('FLAT_UPDATED_TIMESTAMP'), ('FLAT_UPDATED_USER_ID'),
            ('ABYS_FLAT_ID'), ('FLAT_NUMBER_RAW')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas sch ON sch.schema_id = t.schema_id
        WHERE sch.name = 'dbo' AND t.name = 'LS_FLAT' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'izgazMGR.dbo.LS_FLAT eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'izgazMGR.dbo.LS_FLAT kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

