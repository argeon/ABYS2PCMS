/* ============================================================
   SCRIPT_ID : AGR_DEV_SETUP
   SCRIPT_NO : 330
   FILE      : 330_AGR_DEV__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.LS_AGR_DEVICE → energy.dbo.LS_005_01_AGR_DEV_TR
--   LREF ← IDENTITY (kaynakta tekil ABYS satır PK yok)
--   AGRID ← NULL (1. geçiş); AGR migrate sonrası SP_MIG_WIRE_AGR_DEV_AGRID
--   DEVID ← staging DEVID (Oracle CASE ile PCMS LREF; 42_ls_device_setup yok)
--   ADDUSER/UPDUSER ← ABYS user id + 10000 (FN_MIG_MAP_USER_USERID)
--
-- Kaynak: Oracle CTAS LS_AGR_DEVICE (CS_AGREEMENT + project device)
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- Hedef köprü kolonları
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR') AND name = 'ABYS_MIG_ROW_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_DEV_TR ADD ABYS_MIG_ROW_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR') AND name = 'ABYS_AGREEMENT_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_DEV_TR ADD ABYS_AGREEMENT_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR') AND name = 'ABYS_DEV_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_DEV_TR ADD ABYS_DEV_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR') AND name = 'ABYS_DEVICE_KIND'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_DEV_TR ADD ABYS_DEVICE_KIND NVARCHAR(200) NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR') AND name = 'ABYS_PROJECT_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_DEV_TR ADD ABYS_PROJECT_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR') AND name = 'ABYS_INSTALLATION_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_DEV_TR ADD ABYS_INSTALLATION_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR') AND name = 'ABYS_MARK_CODE'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_DEV_TR ADD ABYS_MARK_CODE NVARCHAR(10) NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR') AND name = 'ABYS_MARK_VALUE'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_DEV_TR ADD ABYS_MARK_VALUE NVARCHAR(100) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR')
      AND name = 'UX_LS_005_01_AGR_DEV_TR_ABYS_ID'
)
    DROP INDEX UX_LS_005_01_AGR_DEV_TR_ABYS_ID ON energy.dbo.LS_005_01_AGR_DEV_TR;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR')
      AND name = 'UX_LS_005_01_AGR_DEV_TR_ABYS_MIG'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_005_01_AGR_DEV_TR_ABYS_MIG
        ON energy.dbo.LS_005_01_AGR_DEV_TR (ABYS_MIG_ROW_ID)
        WHERE ABYS_MIG_ROW_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR')
      AND name = 'IX_LS_005_01_AGR_DEV_TR_ABYS_AGREEMENT'
)
    CREATE NONCLUSTERED INDEX IX_LS_005_01_AGR_DEV_TR_ABYS_AGREEMENT
        ON energy.dbo.LS_005_01_AGR_DEV_TR (ABYS_AGREEMENT_ID)
        INCLUDE (LREF, AGRID)
        WHERE ABYS_AGREEMENT_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Kaynak: MIG_ROW_ID (ABYS_DEV_ID tekil değil)
-- ------------------------------------------------------------
IF OBJECT_ID('izgazMGR.dbo.LS_AGR_DEVICE', 'U') IS NOT NULL
BEGIN
    IF COL_LENGTH('izgazMGR.dbo.LS_AGR_DEVICE', 'MIG_ROW_ID') IS NOT NULL
       AND COLUMNPROPERTY(OBJECT_ID('izgazMGR.dbo.LS_AGR_DEVICE'), 'MIG_ROW_ID', 'IsIdentity') = 1
    BEGIN
        IF EXISTS (
            SELECT 1 FROM izgazMGR.sys.indexes
            WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_AGR_DEVICE')
              AND name = 'UX_LS_AGR_DEVICE_MIG_ROW'
        )
            DROP INDEX UX_LS_AGR_DEVICE_MIG_ROW ON izgazMGR.dbo.LS_AGR_DEVICE;

        ALTER TABLE izgazMGR.dbo.LS_AGR_DEVICE DROP COLUMN MIG_ROW_ID;
    END

    IF COL_LENGTH('izgazMGR.dbo.LS_AGR_DEVICE', 'MIG_ROW_ID') IS NULL
        ALTER TABLE izgazMGR.dbo.LS_AGR_DEVICE ADD MIG_ROW_ID BIGINT NULL;

    IF COL_LENGTH('izgazMGR.dbo.LS_AGR_DEVICE', '_MIG_UID') IS NULL
        ALTER TABLE izgazMGR.dbo.LS_AGR_DEVICE ADD _MIG_UID INT IDENTITY(1, 1) NOT NULL;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_DEV_PREP_SOURCE
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_AGR_DEVICE', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR.dbo.LS_AGR_DEVICE bulunamadi.', 16, 1);
        RETURN 1;
    END

    UPDATE s
    SET s.MIG_ROW_ID = s._MIG_UID
    FROM izgazMGR.dbo.LS_AGR_DEVICE s
    WHERE s.MIG_ROW_ID IS NULL;

    IF NOT EXISTS (
        SELECT 1 FROM izgazMGR.sys.indexes
        WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_AGR_DEVICE')
          AND name = 'UX_LS_AGR_DEVICE_MIG_ROW'
    )
        CREATE UNIQUE NONCLUSTERED INDEX UX_LS_AGR_DEVICE_MIG_ROW
            ON izgazMGR.dbo.LS_AGR_DEVICE (MIG_ROW_ID)
            WHERE MIG_ROW_ID IS NOT NULL;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Kaynak / hedef kolon doğrulama
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_DEV_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_AGR_DEVICE', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_AGR_DEVICE bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('DEVID'), ('AGRID'),
            ('MIN_DEBIT'), ('WORKDAY'), ('WORKHOUR'), ('FEE'), ('EXCNR'),
            ('BLIND_PLUG'), ('ISACTIVE'),
            ('ADDUSER'), ('ADDDATE'), ('UPDUSER'), ('UPDDATE'),
            ('ABYS_DEV_ID'), ('ABYS_DEVICE_KIND'),
            ('ABYS_PROJECT_ID'), ('ABYS_INSTALLATION_ID'),
            ('ABYS_MARK_CODE'), ('ABYS_MARK_VALUE'),
            ('MIG_ROW_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'LS_AGR_DEVICE' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_AGR_DEVICE eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_AGR_DEVICE kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO
 
CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_DEV_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_AGR_DEV_TR bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('DEVID'), ('AGRID'),
            ('CAPACITY'), ('WORKDAY'), ('WORKHOUR'), ('FEE'), ('EXCNR'),
            ('BLIND_PLUG'), ('ISACTIVE'), ('DEMANDTYPE'),
            ('ADDUSER'), ('ADDDATE'), ('UPDUSER'), ('UPDDATE'),
            ('ABYS_MIG_ROW_ID'), ('ABYS_AGREEMENT_ID'),
            ('ABYS_DEV_ID'), ('ABYS_DEVICE_KIND'),
            ('ABYS_PROJECT_ID'), ('ABYS_INSTALLATION_ID'),
            ('ABYS_MARK_CODE'), ('ABYS_MARK_VALUE')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_AGR_DEV_TR eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_AGR_DEV_TR hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Kaynak view — sadece izgazMGR.dbo.LS_AGR_DEVICE
-- AGRID hedefe 1. geçişte yazılmaz; ABYS_AGREEMENT_ID wiring için saklanır
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.VW_MIG_AGR_DEV_TR_SOURCE', 'V') IS NOT NULL
    DROP VIEW dbo.VW_MIG_AGR_DEV_TR_SOURCE;
GO

CREATE OR ALTER VIEW dbo.VW_MIG_AGR_DEVICE_SOURCE
AS
SELECT
    CAST(s.MIG_ROW_ID AS BIGINT)                                    AS MIG_ROW_ID,
    CAST(TRY_CAST(s.AGRID AS BIGINT) AS BIGINT)                     AS ABYS_AGREEMENT_ID,
    CAST(TRY_CAST(s.DEVID AS BIGINT) AS INT)                        AS DEVID,
    TRY_CAST(s.MIN_DEBIT AS FLOAT)                                   AS CAPACITY,
    CAST(TRY_CAST(s.WORKDAY AS BIGINT) AS INT)                      AS WORKDAY,
    CAST(TRY_CAST(s.WORKHOUR AS BIGINT) AS INT)                     AS WORKHOUR,
    TRY_CAST(s.FEE AS MONEY)                                        AS FEE,
    CAST(TRY_CAST(s.EXCNR AS BIGINT) AS INT)                        AS EXCNR,
    CAST(ISNULL(TRY_CAST(s.BLIND_PLUG AS INT), 0) AS BIT)           AS BLIND_PLUG,
    CAST(ISNULL(TRY_CAST(s.ISACTIVE AS INT), 0) AS BIT)             AS ISACTIVE,
    CAST(NULL AS TINYINT)                                           AS DEMANDTYPE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.ADDUSER AS BIGINT) AS INT)) AS ADDUSER,
    energy.dbo.FN_SAFE_SMALLDT_DEP(
        TRY_CONVERT(DATETIME2, s.ADDDATE)
    )                                                               AS ADDDATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.UPDUSER AS BIGINT) AS INT)) AS UPDUSER,
    energy.dbo.FN_SAFE_SMALLDT_DEP(
        TRY_CONVERT(DATETIME2, s.UPDDATE)
    )                                                               AS UPDDATE,
    CAST(TRY_CAST(s.ABYS_DEV_ID AS BIGINT) AS BIGINT)               AS ABYS_DEV_ID,
    LEFT(s.ABYS_DEVICE_KIND, 200)                                   AS ABYS_DEVICE_KIND,
    CAST(TRY_CAST(s.ABYS_PROJECT_ID AS BIGINT) AS BIGINT)           AS ABYS_PROJECT_ID,
    CAST(TRY_CAST(s.ABYS_INSTALLATION_ID AS BIGINT) AS BIGINT)      AS ABYS_INSTALLATION_ID,
    LEFT(s.ABYS_MARK_CODE, 10)                                      AS ABYS_MARK_CODE,
    LEFT(s.ABYS_MARK_VALUE, 100)                                    AS ABYS_MARK_VALUE
FROM izgazMGR.dbo.LS_AGR_DEVICE s
WHERE s.MIG_ROW_ID IS NOT NULL;
GO

EXEC dbo.SP_MIG_AGR_DEV_PREP_SOURCE;
EXEC dbo.SP_MIG_AGR_DEV_VALIDATE_SOURCE @RaiseOnMissing = 0;
EXEC dbo.SP_MIG_AGR_DEV_VALIDATE_TARGET @RaiseOnMissing = 0;
GO

 



