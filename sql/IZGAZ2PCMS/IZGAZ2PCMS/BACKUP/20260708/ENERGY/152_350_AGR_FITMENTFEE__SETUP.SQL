/* ============================================================
   SCRIPT_ID : AGR_FITMENTFEE_SETUP
   SCRIPT_NO : 350
   FILE      : 350_AGR_FITMENTFEE__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.LS_FITMENT_FEE → energy.dbo.LS_005_01_AGR_FITMENTFEE_TR
--   LREF ← IDENTITY (kaynak LREF = subscriber ID; tesisat join ile tekil olmayabilir)
--   AGRID ← ABYS_AGREEMENT_ID (Oracle/ABYS hali; wire YOK)
--   FLATID ← LS_FLAT.LREF (ABYS_INSTALLATION_ID, ENT_ID=4102)
--   ADDDATE yok hedefte → UPDDATE = ISNULL(UPDDATE, ADDDATE)
--   ADDUSER yok hedefte → UPDUSER = FN_MIG_MAP_USER_USERID(ISNULL(UPDUSER, ADDUSER))
--
-- Kaynak: Oracle CTAS LS_FITMENTFEE (CS_SUBSCRIBER + CS_INSTALLATION)
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- Aktarım öncesi FK kaldırma (orphan satırlar insert'i bozmasın)
-- ------------------------------------------------------------
IF EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_LS_005_01_AGR_FITMENTFEE_TR_LS_FLAT'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_FITMENTFEE_TR')
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_FITMENTFEE_TR
        DROP CONSTRAINT FK_LS_005_01_AGR_FITMENTFEE_TR_LS_FLAT;
GO

-- ------------------------------------------------------------
-- Hedef köprü kolonları
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_FITMENTFEE_TR') AND name = 'ABYS_MIG_ROW_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_FITMENTFEE_TR ADD ABYS_MIG_ROW_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_FITMENTFEE_TR') AND name = 'ABYS_AGREEMENT_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_FITMENTFEE_TR ADD ABYS_AGREEMENT_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_FITMENTFEE_TR') AND name = 'ABYS_FLAT_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_FITMENTFEE_TR ADD ABYS_FLAT_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_FITMENTFEE_TR') AND name = 'ABYS_INSTALLATION_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_FITMENTFEE_TR ADD ABYS_INSTALLATION_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_FITMENTFEE_TR') AND name = 'ABYS_LREF'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_FITMENTFEE_TR ADD ABYS_LREF BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_FITMENTFEE_TR')
      AND name = 'UX_LS_005_01_AGR_FITMENTFEE_TR_ABYS_MIG'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_005_01_AGR_FITMENTFEE_TR_ABYS_MIG
        ON energy.dbo.LS_005_01_AGR_FITMENTFEE_TR (ABYS_MIG_ROW_ID)
        WHERE ABYS_MIG_ROW_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_FITMENTFEE_TR')
      AND name = 'IX_LS_005_01_AGR_FITMENTFEE_TR_ABYS_AGREEMENT'
)
    CREATE NONCLUSTERED INDEX IX_LS_005_01_AGR_FITMENTFEE_TR_ABYS_AGREEMENT
        ON energy.dbo.LS_005_01_AGR_FITMENTFEE_TR (ABYS_AGREEMENT_ID)
        INCLUDE (LREF, AGRID)
        WHERE ABYS_AGREEMENT_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Kaynak: MIG_ROW_ID (LREF tesisat join ile tekil olmayabilir)
-- ------------------------------------------------------------
IF OBJECT_ID('izgazMGR.dbo.LS_FITMENT_FEE', 'U') IS NOT NULL
BEGIN
    IF COL_LENGTH('izgazMGR.dbo.LS_FITMENT_FEE', 'MIG_ROW_ID') IS NOT NULL
       AND COLUMNPROPERTY(OBJECT_ID('izgazMGR.dbo.LS_FITMENT_FEE'), 'MIG_ROW_ID', 'IsIdentity') = 1
    BEGIN
        IF EXISTS (
            SELECT 1 FROM izgazMGR.sys.indexes
            WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_FITMENT_FEE')
              AND name = 'UX_LS_FITMENT_FEE_MIG_ROW'
        )
            DROP INDEX UX_LS_FITMENT_FEE_MIG_ROW ON izgazMGR.dbo.LS_FITMENT_FEE;

        ALTER TABLE izgazMGR.dbo.LS_FITMENT_FEE DROP COLUMN MIG_ROW_ID;
    END

    IF COL_LENGTH('izgazMGR.dbo.LS_FITMENT_FEE', 'MIG_ROW_ID') IS NULL
        ALTER TABLE izgazMGR.dbo.LS_FITMENT_FEE ADD MIG_ROW_ID BIGINT NULL;

    IF COL_LENGTH('izgazMGR.dbo.LS_FITMENT_FEE', '_MIG_UID') IS NULL
        ALTER TABLE izgazMGR.dbo.LS_FITMENT_FEE ADD _MIG_UID INT IDENTITY(1, 1) NOT NULL;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_FITMENTFEE_PREP_SOURCE
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_FITMENT_FEE', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR.dbo.LS_FITMENT_FEE bulunamadi.', 16, 1);
        RETURN 1;
    END

    UPDATE s
    SET s.MIG_ROW_ID = s._MIG_UID
    FROM izgazMGR.dbo.LS_FITMENT_FEE s
    WHERE s.MIG_ROW_ID IS NULL;

    IF NOT EXISTS (
        SELECT 1 FROM izgazMGR.sys.indexes
        WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_FITMENT_FEE')
          AND name = 'UX_LS_FITMENT_FEE_MIG_ROW'
    )
        CREATE UNIQUE NONCLUSTERED INDEX UX_LS_FITMENT_FEE_MIG_ROW
            ON izgazMGR.dbo.LS_FITMENT_FEE (MIG_ROW_ID)
            WHERE MIG_ROW_ID IS NOT NULL;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Kaynak / hedef kolon doğrulama
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_FITMENTFEE_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_FITMENT_FEE', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_FITMENT_FEE bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('FLATID'), ('AGRID'),
            ('SIZE_M2'), ('FEE'), ('EXCNR'), ('BBS'),
            ('ADDUSER'), ('ADDDATE'), ('UPDDATE'), ('UPDUSER'),
            ('ISACTIVE'), ('TARGET_SIZE'),
            ('ABYS_INSTALLATION_ID'), ('ABYS_FLAT_ID'),
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
        WHERE s.name = 'dbo' AND t.name = 'LS_FITMENT_FEE' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_FITMENT_FEE eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_FITMENT_FEE kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_FITMENTFEE_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_AGR_FITMENTFEE_TR', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_AGR_FITMENTFEE_TR bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('FLATID'), ('AGRID'),
            ('SIZE_M2'), ('FEE'), ('EXCNR'), ('BBS'),
            ('UPDDATE'), ('UPDUSER'), ('ISACTIVE'), ('TARGET_SIZE'),
            ('ABYS_MIG_ROW_ID'), ('ABYS_AGREEMENT_ID'),
            ('ABYS_FLAT_ID'), ('ABYS_INSTALLATION_ID'), ('ABYS_LREF')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_FITMENTFEE_TR')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_AGR_FITMENTFEE_TR eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_AGR_FITMENTFEE_TR hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Kaynak view
-- AGRID hedefe ABYS_AGREEMENT_ID olarak yazılır (wire yok)
-- FLATID: LS_FLAT.ABYS_INSTALLATION_ID (ENT_ID=4102)
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.VW_MIG_AGR_FITMENTFEE_TR_SOURCE
AS
SELECT
    CAST(s.MIG_ROW_ID AS BIGINT)                                    AS MIG_ROW_ID,
    CAST(TRY_CAST(s.LREF AS BIGINT) AS BIGINT)                      AS ABYS_LREF,
    CAST(TRY_CAST(s.AGRID AS BIGINT) AS BIGINT)                     AS ABYS_AGREEMENT_ID,
    CAST(TRY_CAST(s.ABYS_FLAT_ID AS BIGINT) AS BIGINT)              AS ABYS_FLAT_ID,
    CAST(TRY_CAST(s.ABYS_INSTALLATION_ID AS BIGINT) AS BIGINT)      AS ABYS_INSTALLATION_ID,
    CAST(f.LREF AS INT)                                             AS FLATID,
    TRY_CAST(s.SIZE_M2 AS FLOAT)                                    AS SIZE_M2,
    TRY_CAST(s.FEE AS MONEY)                                        AS FEE,
    CAST(TRY_CAST(s.EXCNR AS BIGINT) AS INT)                        AS EXCNR,
    TRY_CAST(s.BBS AS FLOAT)                                        AS BBS,
    energy.dbo.FN_SAFE_SMALLDT_DEP(
        CAST(ISNULL(s.UPDDATE, s.ADDDATE) AS DATETIME2)
    )                                                               AS UPDDATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(ISNULL(s.UPDUSER, s.ADDUSER) AS BIGINT) AS INT)) AS UPDUSER,
    CAST(ISNULL(TRY_CAST(s.ISACTIVE AS INT), 0) AS BIT)             AS ISACTIVE,
    TRY_CAST(s.TARGET_SIZE AS FLOAT)                                AS TARGET_SIZE
FROM izgazMGR.dbo.LS_FITMENT_FEE s
LEFT JOIN energy.dbo.LS_FLAT f
    ON f.ABYS_INSTALLATION_ID = TRY_CAST(s.ABYS_INSTALLATION_ID AS BIGINT)
   AND f.ENT_ID = 4102
WHERE s.MIG_ROW_ID IS NOT NULL;
GO

EXEC dbo.SP_MIG_AGR_FITMENTFEE_PREP_SOURCE;
EXEC dbo.SP_MIG_AGR_FITMENTFEE_VALIDATE_SOURCE @RaiseOnMissing = 0;
EXEC dbo.SP_MIG_AGR_FITMENTFEE_VALIDATE_TARGET @RaiseOnMissing = 0;
GO

