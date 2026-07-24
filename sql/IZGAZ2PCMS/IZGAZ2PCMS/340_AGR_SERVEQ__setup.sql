/* ============================================================
   SCRIPT_ID : AGR_SERVEQ_SETUP
   SCRIPT_NO : 340
   FILE      : 340_AGR_SERVEQ__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.LS_AGR_SERVQ → energy.dbo.LS_005_01_AGR_SERVEQ_TR
--   LREF ← IDENTITY (kaynakta tekil ABYS satır PK yok)
--   AGRID ← NULL (1. geçiş); AGR migrate sonrası SP_MIG_WIRE_AGR_SERVEQ_AGRID
--   MID/MIDOLD ← ABYS meter id (ITEMS LREF = METER_ID ise doğrudan)
--   VALUE → LINEEXP, CODE → STAMPNO
--   ADDDATE → UPDDATE (hedeften ADDDATE yok)
--   LASTENDEX decimal(25,3) → int (ROUND)
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- Hedef köprü kolonları
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR') AND name = 'ABYS_MIG_ROW_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_SERVEQ_TR ADD ABYS_MIG_ROW_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR') AND name = 'ABYS_AGREEMENT_ID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_SERVEQ_TR ADD ABYS_AGREEMENT_ID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR') AND name = 'ABYS_MID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_SERVEQ_TR ADD ABYS_MID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR') AND name = 'ABYS_TID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_SERVEQ_TR ADD ABYS_TID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR') AND name = 'ABYS_MIDOLD'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_SERVEQ_TR ADD ABYS_MIDOLD BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR') AND name = 'ABYS_ITEMID'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_SERVEQ_TR ADD ABYS_ITEMID BIGINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR') AND name = 'ABYS_USED_PRESSURE'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_SERVEQ_TR ADD ABYS_USED_PRESSURE INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR') AND name = 'ABYS_LASTENDEX'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_SERVEQ_TR ADD ABYS_LASTENDEX DECIMAL(25, 3) NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR') AND name = 'TP2'
)
    ALTER TABLE energy.dbo.LS_005_01_AGR_SERVEQ_TR ADD TP2 NCHAR(3) NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR')
      AND name = 'UX_LS_005_01_AGR_SERVEQ_TR_ABYS_MIG'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_005_01_AGR_SERVEQ_TR_ABYS_MIG
        ON energy.dbo.LS_005_01_AGR_SERVEQ_TR (ABYS_MIG_ROW_ID)
        WHERE ABYS_MIG_ROW_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR')
      AND name = 'IX_LS_005_01_AGR_SERVEQ_TR_ABYS_AGREEMENT'
)
    CREATE NONCLUSTERED INDEX IX_LS_005_01_AGR_SERVEQ_TR_ABYS_AGREEMENT
        ON energy.dbo.LS_005_01_AGR_SERVEQ_TR (ABYS_AGREEMENT_ID)
        INCLUDE (LREF, AGRID)
        WHERE ABYS_AGREEMENT_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Kaynak: MIG_ROW_ID (tekil ABYS PK yok)
-- ------------------------------------------------------------
IF OBJECT_ID('izgazMGR.dbo.LS_AGR_SERVQ', 'U') IS NOT NULL
BEGIN
    IF COL_LENGTH('izgazMGR.dbo.LS_AGR_SERVQ', 'MIG_ROW_ID') IS NOT NULL
       AND COLUMNPROPERTY(OBJECT_ID('izgazMGR.dbo.LS_AGR_SERVQ'), 'MIG_ROW_ID', 'IsIdentity') = 1
    BEGIN
        IF EXISTS (
            SELECT 1 FROM izgazMGR.sys.indexes
            WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_AGR_SERVQ')
              AND name = 'UX_LS_AGR_SERVQ_MIG_ROW'
        )
            DROP INDEX UX_LS_AGR_SERVQ_MIG_ROW ON izgazMGR.dbo.LS_AGR_SERVQ;

        ALTER TABLE izgazMGR.dbo.LS_AGR_SERVQ DROP COLUMN MIG_ROW_ID;
    END

    IF COL_LENGTH('izgazMGR.dbo.LS_AGR_SERVQ', 'MIG_ROW_ID') IS NULL
        ALTER TABLE izgazMGR.dbo.LS_AGR_SERVQ ADD MIG_ROW_ID BIGINT NULL;

    IF COL_LENGTH('izgazMGR.dbo.LS_AGR_SERVQ', '_MIG_UID') IS NULL
        ALTER TABLE izgazMGR.dbo.LS_AGR_SERVQ ADD _MIG_UID INT IDENTITY(1, 1) NOT NULL;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_SERVEQ_PREP_SOURCE
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_AGR_SERVQ', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR.dbo.LS_AGR_SERVQ bulunamadi.', 16, 1);
        RETURN 1;
    END

    UPDATE s
    SET s.MIG_ROW_ID = s._MIG_UID
    FROM izgazMGR.dbo.LS_AGR_SERVQ s
    WHERE s.MIG_ROW_ID IS NULL;

    IF NOT EXISTS (
        SELECT 1 FROM izgazMGR.sys.indexes
        WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_AGR_SERVQ')
          AND name = 'UX_LS_AGR_SERVQ_MIG_ROW'
    )
        CREATE UNIQUE NONCLUSTERED INDEX UX_LS_AGR_SERVQ_MIG_ROW
            ON izgazMGR.dbo.LS_AGR_SERVQ (MIG_ROW_ID)
            WHERE MIG_ROW_ID IS NOT NULL;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Kaynak / hedef kolon doğrulama
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_SERVEQ_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_AGR_SERVQ', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_AGR_SERVQ bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('MID'), ('TID'), ('AGRID'), ('TYPE_'), ('SNO'),
            ('MIDOLD'), ('LASTENDEX'), ('VALUE'), ('CODE'),
            ('ITEMID'), ('USED_PRESSURE'), ('CALCPRESSID'),
            ('ADDDATE'), ('ISACTIVE'), ('TP2'),
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
        WHERE s.name = 'dbo' AND t.name = 'LS_AGR_SERVQ' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_AGR_SERVQ eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_AGR_SERVQ kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_SERVEQ_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_AGR_SERVEQ_TR bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('MID'), ('TID'), ('AGRID'), ('CALCPRESSID'),
            ('TYPE_'), ('SNO'), ('MIDOLD'), ('LASTENDEX'),
            ('PULSEVAL'), ('ILLEGALUSE'), ('STAMPNO'),
            ('UPDDATE'), ('UPDUSER'), ('ISACTIVE'),
            ('PROJECTFEE'), ('ITEMID'), ('LINEEXP'),
            ('CAPACITY'), ('OLREF'), ('MOUNT_DATE'), ('REMOVE_DATE'),
            ('ABYS_MIG_ROW_ID'), ('ABYS_AGREEMENT_ID'),
            ('ABYS_MID'), ('ABYS_TID'), ('ABYS_MIDOLD'),
            ('ABYS_ITEMID'), ('ABYS_USED_PRESSURE'), ('ABYS_LASTENDEX'),
            ('TP2')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_AGR_SERVEQ_TR eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_AGR_SERVEQ_TR hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Kaynak view
-- AGRID hedefe 1. geçişte yazılmaz; ABYS_AGREEMENT_ID wiring için saklanır
-- MID/MIDOLD: ITEMS LREF = METER_ID varsayımı (doğrudan cast); ham değer ABYS_*
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.VW_MIG_AGR_SERVEQ_TR_SOURCE
AS
SELECT
    CAST(s.MIG_ROW_ID AS BIGINT)                                    AS MIG_ROW_ID,
    CAST(TRY_CAST(s.AGRID AS BIGINT) AS BIGINT)                     AS ABYS_AGREEMENT_ID,
    CAST(TRY_CAST(s.MID AS BIGINT) AS BIGINT)                       AS ABYS_MID,
    CAST(TRY_CAST(s.TID AS BIGINT) AS BIGINT)                       AS ABYS_TID,
    CAST(TRY_CAST(s.MIDOLD AS BIGINT) AS BIGINT)                    AS ABYS_MIDOLD,
    CAST(TRY_CAST(s.ITEMID AS BIGINT) AS BIGINT)                    AS ABYS_ITEMID,
    s.USED_PRESSURE                                                 AS ABYS_USED_PRESSURE,
    s.LASTENDEX                                                     AS ABYS_LASTENDEX,
    CAST(TRY_CAST(s.MID AS BIGINT) AS INT)                          AS MID,
    CAST(TRY_CAST(s.TID AS BIGINT) AS INT)                          AS TID,
    CAST(TRY_CAST(s.CALCPRESSID AS BIGINT) AS INT)                  AS CALCPRESSID,
    CAST(TRY_CAST(s.TYPE_ AS BIGINT) AS INT)                        AS TYPE_,
    LEFT(s.SNO, 50)                                                 AS SNO,
    CAST(TRY_CAST(s.MIDOLD AS BIGINT) AS INT)                       AS MIDOLD,
    CAST(ROUND(TRY_CAST(s.LASTENDEX AS FLOAT), 0) AS INT)           AS LASTENDEX,
    CAST(NULL AS FLOAT)                                             AS PULSEVAL,
    CAST(0 AS BIT)                                                  AS ILLEGALUSE,
    LEFT(s.CODE, 50)                                                AS STAMPNO,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ADDDATE AS DATETIME2))    AS UPDDATE,
    CAST(NULL AS INT)                                               AS UPDUSER,
    CAST(ISNULL(TRY_CAST(s.ISACTIVE AS INT), 0) AS BIT)             AS ISACTIVE,
    CAST(NULL AS FLOAT)                                             AS PROJECTFEE,
    CAST(TRY_CAST(s.ITEMID AS BIGINT) AS INT)                       AS ITEMID,
    LEFT(s.VALUE, 300)                                              AS LINEEXP,
    CAST(NULL AS FLOAT)                                             AS CAPACITY,
    CAST(NULL AS INT)                                               AS OLREF,
    CAST(NULL AS SMALLDATETIME)                                     AS MOUNT_DATE,
    CAST(NULL AS SMALLDATETIME)                                     AS REMOVE_DATE,
    CAST(s.TP2 AS NCHAR(3))                                         AS TP2
FROM izgazMGR.dbo.LS_AGR_SERVQ s
WHERE s.MIG_ROW_ID IS NOT NULL;
GO

EXEC dbo.SP_MIG_AGR_SERVEQ_PREP_SOURCE;
EXEC dbo.SP_MIG_AGR_SERVEQ_VALIDATE_SOURCE @RaiseOnMissing = 0;
EXEC dbo.SP_MIG_AGR_SERVEQ_VALIDATE_TARGET @RaiseOnMissing = 0;
GO

