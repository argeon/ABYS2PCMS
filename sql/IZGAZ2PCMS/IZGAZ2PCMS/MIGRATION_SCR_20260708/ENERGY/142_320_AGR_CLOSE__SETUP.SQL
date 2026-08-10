/* ============================================================
   SCRIPT_ID : AGR_CLOSE_SETUP
   SCRIPT_NO : 320
   FILE      : 320_AGR_CLOSE__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.LS_AGR_CLOSE → energy.dbo.LS_005_01_AGR_CLOSE
--   LREF ← ABYS_ID (IDENTITY_INSERT)
--   AGRID ← ABYS_AGREEMENT_ID (Oracle/ABYS hali; wire YOK)
--
-- Kaynak: Oracle CTAS (CS_AGREEMENT_CLOSING_APP + köprü kolonları)
-- ============================================================
USE energy;
GO
ALTER TABLE energy.dbo.LS_005_01_AGR_CLOSE ALTER COLUMN CUSTNAME nvarchar(500) COLLATE SQL_Latin1_General_CP1254_CI_AS NULL;

-- ------------------------------------------------------------
-- Hedef köprü kolonları
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_CLOSE') AND name = 'ABYS_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_CLOSE ADD ABYS_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_CLOSE') AND name = 'ABYS_AGREEMENT_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_CLOSE ADD ABYS_AGREEMENT_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_CLOSE') AND name = 'ABYS_PAYABLE_BANK_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_CLOSE ADD ABYS_PAYABLE_BANK_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_CLOSE')
      AND name = 'UX_LS_005_01_AGR_CLOSE_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_005_01_AGR_CLOSE_ABYS_ID
        ON energy.dbo.LS_005_01_AGR_CLOSE (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_CLOSE')
      AND name = 'IX_LS_005_01_AGR_CLOSE_ABYS_AGREEMENT'
)
    CREATE NONCLUSTERED INDEX IX_LS_005_01_AGR_CLOSE_ABYS_AGREEMENT
        ON energy.dbo.LS_005_01_AGR_CLOSE (ABYS_AGREEMENT_ID)
        INCLUDE (LREF, AGRID)
        WHERE ABYS_AGREEMENT_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Kaynak kolon doğrulama
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_CLOSE_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_AGR_CLOSE', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_AGR_CLOSE bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('ABYS_ID'),
            ('CUSTTYPE'), ('CUSTNAME'), ('CUSTNO'),
            ('CURRENT_TLTOTAL'), ('CURRENT_CURTOTAL'), ('CURRENT_CURID'), ('CURRENT_RATE'),
            ('DESC_'), ('STATID'),
            ('ADDUSER'), ('ADDDATE'), ('UPDUSER'), ('UPDDATE'),
            ('CANCELLED'),
            ('BNK_NAME'), ('BNK_NO'), ('BNK_ACCNO'), ('BNK_IBAN'), ('BNK_DESC'),
            ('ALTERNATE_NAME'), ('ALTERNATE_NO'),
            ('PAYTYPE'), ('TYPE_'),
            ('INVOICESTOTAL'), ('COMPLETEDDATE'),
            ('LOGO_FIRMNR_RETURN'), ('LOGO_FICHEREF_RETURN'), ('LOGO_FICHENO_RETURN'),
            ('LOGO_FIRMNR_REV'), ('LOGO_FICHEREF_REV'), ('LOGO_FICHENO_REV'),
            ('DEMAND'),
            ('ABYS_PAYABLE_BANK_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'LS_AGR_CLOSE' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_AGR_CLOSE eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF COL_LENGTH('izgazMGR.dbo.LS_AGR_CLOSE', 'ABYS_AGREEMENT_ID') IS NULL
       AND COL_LENGTH('izgazMGR.dbo.LS_AGR_CLOSE', 'AGRID') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('LS_AGR_CLOSE: ABYS_AGREEMENT_ID veya AGRID kolonu gerekli.', 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_AGR_CLOSE kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_CLOSE_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_AGR_CLOSE', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_AGR_CLOSE bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('AGRID'), ('FITNO'), ('BNA_ID'),
            ('CUSTTYPE'), ('CUSTNAME'), ('CUSTNO'), ('CUSTREF'),
            ('DESC_'), ('STATID'),
            ('ADDUSER'), ('ADDDATE'), ('UPDUSER'), ('UPDDATE'),
            ('CANCELLED'),
            ('BNK_NAME'), ('BNK_NO'), ('BNK_ACCNO'), ('BNK_IBAN'),
            ('TYPE_'), ('BANKREF'),
            ('ABYS_ID'), ('ABYS_AGREEMENT_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_CLOSE')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_AGR_CLOSE eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_AGR_CLOSE hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Kaynak view (kolon eşlemesi tek nokta)
-- AGRID hedefe ABYS_AGREEMENT_ID olarak yazılır (wire yok)
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.VW_MIG_AGR_CLOSE_SOURCE
AS
SELECT
    CAST(s.ABYS_ID AS BIGINT)                                       AS ABYS_ID,
    CAST(COALESCE(
        TRY_CAST(s.ABYS_AGREEMENT_ID AS BIGINT),
        TRY_CAST(s.AGRID AS BIGINT)
    ) AS BIGINT)                                                    AS ABYS_AGREEMENT_ID,
    CAST(NULL AS BIGINT)                                            AS FITNO,
    CAST(NULL AS INT)                                               AS BNA_ID,
    CAST(TRY_CAST(s.CUSTTYPE AS BIGINT) AS TINYINT)                 AS CUSTTYPE,
    LEFT(s.CUSTNAME, 250)                                           AS CUSTNAME,
    LEFT(s.CUSTNO, 20)                                              AS CUSTNO,
    CAST(NULL AS INT)                                               AS CUSTREF,
    TRY_CAST(s.CURRENT_TLTOTAL AS FLOAT)                            AS CURRENT_TLTOTAL,
    TRY_CAST(s.CURRENT_CURTOTAL AS FLOAT)                           AS CURRENT_CURTOTAL,
    CAST(TRY_CAST(s.CURRENT_CURID AS BIGINT) AS INT)                AS CURRENT_CURID,
    TRY_CAST(s.CURRENT_RATE AS FLOAT)                               AS CURRENT_RATE,
    LEFT(s.DESC_, 4000)                                             AS DESC_,
    CAST(TRY_CAST(s.STATID AS BIGINT) AS INT)                       AS STATID,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.ADDUSER AS BIGINT) AS INT)) AS ADDUSER,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ADDDATE AS DATETIME2))    AS ADDDATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.UPDUSER AS BIGINT) AS INT)) AS UPDUSER,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.UPDDATE AS DATETIME2))    AS UPDDATE,
    CAST(ISNULL(TRY_CAST(s.CANCELLED AS INT), 0) AS BIT)            AS CANCELLED,
    LEFT(s.BNK_NAME, 50)                                            AS BNK_NAME,
    LEFT(s.BNK_NO, 5)                                               AS BNK_NO,
    LEFT(s.BNK_ACCNO, 20)                                           AS BNK_ACCNO,
    LEFT(s.BNK_IBAN, 50)                                            AS BNK_IBAN,
    LEFT(s.BNK_DESC, 50)                                            AS BNK_DESC,
    LEFT(s.ALTERNATE_NAME, 50)                                      AS ALTERNATE_NAME,
    LEFT(s.ALTERNATE_NO, 50)                                        AS ALTERNATE_NO,
    CAST(TRY_CAST(s.PAYTYPE AS BIGINT) AS INT)                      AS PAYTYPE,
    CAST(TRY_CAST(s.TYPE_ AS BIGINT) AS TINYINT)                    AS TYPE_,
    energy.dbo.FN_MIG_RESOLVE_BANK_LREF(
        CAST(TRY_CAST(s.ABYS_PAYABLE_BANK_ID AS BIGINT) AS INT)
    )                                                               AS BANKREF,
    TRY_CAST(s.INVOICESTOTAL AS FLOAT)                              AS INVOICESTOTAL,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.COMPLETEDDATE AS DATETIME2)) AS COMPLETEDDATE,
    CAST(TRY_CAST(s.LOGO_FIRMNR_RETURN AS BIGINT) AS INT)           AS LOGO_FIRMNR_RETURN,
    CAST(TRY_CAST(s.LOGO_FICHEREF_RETURN AS BIGINT) AS INT)         AS LOGO_FICHEREF_RETURN,
    LEFT(s.LOGO_FICHENO_RETURN, 50)                                 AS LOGO_FICHENO_RETURN,
    CAST(TRY_CAST(s.LOGO_FIRMNR_REV AS BIGINT) AS INT)              AS LOGO_FIRMNR_REV,
    CAST(TRY_CAST(s.LOGO_FICHEREF_REV AS BIGINT) AS INT)            AS LOGO_FICHEREF_REV,
    LEFT(s.LOGO_FICHENO_REV, 50)                                    AS LOGO_FICHENO_REV,
    CAST(TRY_CAST(s.DEMAND AS BIGINT) AS INT)                       AS DEMAND,
    CAST(TRY_CAST(s.ABYS_PAYABLE_BANK_ID AS BIGINT) AS INT)         AS ABYS_PAYABLE_BANK_ID
FROM izgazMGR.dbo.LS_AGR_CLOSE s;
GO

IF OBJECT_ID('dbo.SP_MIGRATE_LS_AGR_CLOSE', 'P') IS NOT NULL
    EXEC sys.sp_refreshsqlmodule N'dbo.SP_MIGRATE_LS_AGR_CLOSE';
GO

EXEC dbo.SP_MIG_AGR_CLOSE_VALIDATE_SOURCE @RaiseOnMissing = 0;
EXEC dbo.SP_MIG_AGR_CLOSE_VALIDATE_TARGET @RaiseOnMissing = 0;
GO

