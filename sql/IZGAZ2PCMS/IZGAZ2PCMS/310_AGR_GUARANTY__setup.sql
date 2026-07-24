/* ============================================================
   SCRIPT_ID : AGR_GUARANTY_SETUP
   SCRIPT_NO : 310
   FILE      : 310_AGR_GUARANTY__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================

-- LS_AGR_GUARANTY → LS_005_01_AGR_GUARANTY

-- izgazMGR staging → energy hedef (ABYS köprü kolonları)

-- ADDDATE/UPDDATE: datetimeoffset (+0300) → FN_SAFE_SMALLDT_DEP

--

-- Kaynak (MigrationEngine mirror):

--   AGRID, GTYPE, RFNO, SDATE, EDATE, TOTAL, WD, EXCNR, MUSTTL,

--   ADDDATE, ADDUSER, UPDDATE, UPDUSER, LOGOREF, BANKREF, BANKACCREF,

--   CUSTBNK, CUSTBNKACC, CUSTBNKNO,

--   ABYS_REGISTER_ID, ABYS_AGREEMENT_ID,

--   ABYS_GL_REF, ABYS_GL_DESC, ABYS_GL_BNK_DESC, ABYS_GL_BANK_REF,

--   REFUND

--

-- MIG_ROW_ID: aktarım öncesi ADDDATE (oluşturma zamanı) sırasına göre atanır

-- ============================================================

USE energy;

GO

--select * from LS_005_01_AGR_GUARANTY


-- ------------------------------------------------------------

-- Hedef ABYS kolonları

-- ------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_GUARANTY') AND name = 'ABYS_MIG_ROW_ID')

    ALTER TABLE energy.dbo.LS_005_01_AGR_GUARANTY ADD ABYS_MIG_ROW_ID BIGINT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_GUARANTY') AND name = 'ABYS_LREF')

    ALTER TABLE energy.dbo.LS_005_01_AGR_GUARANTY ADD ABYS_LREF INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_GUARANTY') AND name = 'ABYS_AGRID')

    ALTER TABLE energy.dbo.LS_005_01_AGR_GUARANTY ADD ABYS_AGRID INT NULL;

GO



IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_GUARANTY') AND name = 'UX_LS005_AGR_GUAR_ABYS_MIG')

    DROP INDEX UX_LS005_AGR_GUAR_ABYS_MIG ON energy.dbo.LS_005_01_AGR_GUARANTY;

GO



IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_GUARANTY') AND name = 'UX_LS005_AGR_GUAR_ABYS_MIG')

    CREATE UNIQUE NONCLUSTERED INDEX UX_LS005_AGR_GUAR_ABYS_MIG

        ON energy.dbo.LS_005_01_AGR_GUARANTY (ABYS_MIG_ROW_ID)

        WHERE ABYS_MIG_ROW_ID IS NOT NULL;

GO



IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR_GUARANTY') AND name = 'IX_LS005_AGR_GUAR_ABYS_LREF')

    CREATE NONCLUSTERED INDEX IX_LS005_AGR_GUAR_ABYS_LREF

        ON energy.dbo.LS_005_01_AGR_GUARANTY (ABYS_LREF)

        INCLUDE (LREF)

        WHERE ABYS_LREF IS NOT NULL;

GO



-- ------------------------------------------------------------
-- Kaynak staging kolonlari (SP/view derlemesinden ONCE)
-- ------------------------------------------------------------
IF OBJECT_ID('izgazMGR.dbo.LS_AGR_GUARANTY', 'U') IS NOT NULL
BEGIN
    IF COL_LENGTH('izgazMGR.dbo.LS_AGR_GUARANTY', 'MIG_ROW_ID') IS NOT NULL
       AND COLUMNPROPERTY(
            OBJECT_ID('izgazMGR.dbo.LS_AGR_GUARANTY'),
            'MIG_ROW_ID', 'IsIdentity') = 1
    BEGIN
        IF EXISTS (
            SELECT 1 FROM izgazMGR.sys.indexes
            WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_AGR_GUARANTY')
              AND name = 'UX_LS_AGR_GUARANTY_MIG_ROW'
        )
            DROP INDEX UX_LS_AGR_GUARANTY_MIG_ROW
                ON izgazMGR.dbo.LS_AGR_GUARANTY;

        ALTER TABLE izgazMGR.dbo.LS_AGR_GUARANTY DROP COLUMN MIG_ROW_ID;
    END

    IF COL_LENGTH('izgazMGR.dbo.LS_AGR_GUARANTY', 'MIG_ROW_ID') IS NULL
        ALTER TABLE izgazMGR.dbo.LS_AGR_GUARANTY ADD MIG_ROW_ID BIGINT NULL;

    IF COL_LENGTH('izgazMGR.dbo.LS_AGR_GUARANTY', '_MIG_UID') IS NULL
        ALTER TABLE izgazMGR.dbo.LS_AGR_GUARANTY
            ADD _MIG_UID INT IDENTITY(1, 1) NOT NULL;
END
GO

-- ------------------------------------------------------------
-- Kaynak: MIG_ROW_ID atama (ADDDATE sirasi)
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_DEPOSIT_GUAR_PREP_SOURCE
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_AGR_GUARANTY', 'U') IS NULL
        RETURN;

    IF COL_LENGTH('izgazMGR.dbo.LS_AGR_GUARANTY', 'MIG_ROW_ID') IS NULL
       OR COL_LENGTH('izgazMGR.dbo.LS_AGR_GUARANTY', '_MIG_UID') IS NULL
    BEGIN
        RAISERROR('LS_AGR_GUARANTY: MIG_ROW_ID veya _MIG_UID kolonu yok. Once 305_AGR_GUARANTY_STAGING__setup.sql calistirin.', 16, 1);
        RETURN;
    END

    ;WITH Ordered AS (
        SELECT
            s._MIG_UID,
            ROW_NUMBER() OVER (
                ORDER BY
                    CAST(s.ADDDATE AS DATETIME2),
                    s.AGRID,
                    s.ABYS_AGREEMENT_ID,
                    s.RFNO,
                    s._MIG_UID
            ) AS NewMigRowId
        FROM izgazMGR.dbo.LS_AGR_GUARANTY s
    )
    UPDATE s
    SET s.MIG_ROW_ID = o.NewMigRowId
    FROM izgazMGR.dbo.LS_AGR_GUARANTY s
    INNER JOIN Ordered o ON o._MIG_UID = s._MIG_UID;

    IF EXISTS (
        SELECT 1
        FROM izgazMGR.dbo.LS_AGR_GUARANTY
        WHERE MIG_ROW_ID IS NULL
    )
        RAISERROR('LS_AGR_GUARANTY: MIG_ROW_ID atamasi tamamlanamadi.', 16, 1);

    IF EXISTS (
        SELECT 1 FROM izgazMGR.sys.indexes
        WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_AGR_GUARANTY')
          AND name = 'UX_LS_AGR_GUARANTY_MIG_ROW'
    )
        DROP INDEX UX_LS_AGR_GUARANTY_MIG_ROW
            ON izgazMGR.dbo.LS_AGR_GUARANTY;

    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_AGR_GUARANTY_MIG_ROW
        ON izgazMGR.dbo.LS_AGR_GUARANTY (MIG_ROW_ID);
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_DEPOSIT_GUAR_VALIDATE_SOURCE

    @RaiseOnMissing BIT = 1

AS

BEGIN

    SET NOCOUNT ON;



    IF OBJECT_ID('izgazMGR.dbo.LS_AGR_GUARANTY', 'U') IS NULL

    BEGIN

        IF @RaiseOnMissing = 1

            RAISERROR('izgazMGR.dbo.LS_AGR_GUARANTY bulunamadi.', 16, 1);

        RETURN 1;

    END



    DECLARE @Missing NVARCHAR(MAX) = N'';



    ;WITH Required (COL_NAME) AS (

        SELECT v.COL_NAME FROM (VALUES

            ('AGRID'), ('GTYPE'), ('RFNO'),

            ('SDATE'), ('EDATE'), ('WD'), ('TOTAL'), ('EXCNR'), ('MUSTTL'),

            ('ADDDATE'), ('ADDUSER'), ('UPDDATE'), ('UPDUSER'),

            ('LOGOREF'), ('BANKREF'), ('BANKACCREF'),

            ('CUSTBNK'), ('CUSTBNKACC'), ('CUSTBNKNO'),

            ('ABYS_REGISTER_ID'), ('ABYS_AGREEMENT_ID'),

            ('ABYS_GL_REF'), ('ABYS_GL_DESC'), ('ABYS_GL_BNK_DESC'), ('ABYS_GL_BANK_REF'),

            ('REFUND')

        ) v(COL_NAME)

    )

    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')

    FROM Required r

    WHERE NOT EXISTS (

        SELECT 1

        FROM izgazMGR.sys.columns c

        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id

        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id

        WHERE s.name = 'dbo' AND t.name = 'LS_AGR_GUARANTY' AND c.name = r.COL_NAME

    );



    IF @Missing IS NOT NULL AND @Missing <> N''

    BEGIN

        DECLARE @Msg NVARCHAR(4000) = N'LS_AGR_GUARANTY eksik kolonlar: ' + @Missing;

        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);

        RETURN 1;

    END



    IF @RaiseOnMissing = 0

        SELECT N'LS_AGR_GUARANTY kaynak dogrulama OK' AS VALIDATION_MESSAGE;



    RETURN 0;

END

GO



-- datetimeoffset / datetime2 → smalldatetime (ADDDATE, UPDDATE, SDATE, EDATE)

CREATE OR ALTER FUNCTION dbo.FN_SAFE_SMALLDT_DEP (@DT DATETIME2)

RETURNS SMALLDATETIME

AS

BEGIN

    RETURN CASE

        WHEN @DT IS NULL                 THEN NULL

        WHEN @DT < '1900-01-01 00:00:00' THEN NULL

        WHEN @DT > '2079-06-06 23:59:00' THEN NULL

        ELSE CAST(@DT AS SMALLDATETIME)

    END;

END

GO



-- ------------------------------------------------------------

-- Kaynak view (kolon eşlemesi tek nokta)

-- MIG_ROW_ID sırası = ADDDATE (oluşturma zamanı) — SP_MIG_DEPOSIT_GUAR_PREP_SOURCE

-- ------------------------------------------------------------

CREATE OR ALTER VIEW dbo.VW_MIG_DEPOSIT_GUARANTY_SOURCE

AS

SELECT

    s.MIG_ROW_ID,

    CAST(s.ABYS_AGREEMENT_ID AS INT)                              AS SRC_LREF,

    CAST(s.AGRID AS INT)                                          AS AGRID,

    s.GTYPE,

    s.RFNO,

    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.SDATE AS DATETIME2))    AS SDATE,

    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.EDATE AS DATETIME2))    AS EDATE,

    s.WD,

    s.TOTAL,

    s.EXCNR,

    s.MUSTTL,

    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ADDDATE AS DATETIME2))  AS ADDDATE,

    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.ADDUSER AS BIGINT) AS INT)) AS ADDUSER,

    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.UPDDATE AS DATETIME2))  AS UPDDATE,

    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.UPDUSER AS BIGINT) AS INT)) AS UPDUSER,

    s.LOGOREF,

    s.BANKREF,

    s.BANKACCREF,

    s.CUSTBNK,

    s.CUSTBNKACC,

    s.CUSTBNKNO,

    CAST(TRY_CAST(s.ABYS_GL_BANK_REF AS DECIMAL(22, 0)) AS INT)   AS LOGO_FIRMNR,

    CAST(COALESCE(

        TRY_CAST(s.ABYS_GL_REF AS DECIMAL(22, 0)),

        TRY_CAST(s.LOGOREF AS DECIMAL(22, 0))

    ) AS INT)                                                     AS LOGO_FICHEREF,

    LEFT(COALESCE(s.ABYS_GL_DESC, s.ABYS_GL_BNK_DESC), 50)        AS LOGO_FICHENO,

    CAST(ISNULL(s.REFUND, 0) AS BIT)                              AS REFUND,

    CAST(0 AS BIT)                                                AS CONVERTED_CASH

FROM izgazMGR.dbo.LS_AGR_GUARANTY s;

GO



EXEC dbo.SP_MIG_DEPOSIT_GUAR_PREP_SOURCE;

GO


