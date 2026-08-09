/* ============================================================
   SCRIPT_ID : PROJECTLINE_SETUP
   SCRIPT_NO : 594
   FILE      : 594_PROJECTLINE__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.LS_PROJECTLINE
--   → energy.dbo.LS_005_01_PROJECTLINE
--
-- LREF    : IDENTITY (yeni) — kaynak LREF TASINMAZ
-- ABYS_ID : kaynak LREF (kopru; ORACLE_LINE_ID tekil DEGIL)
-- ABYS_ORACLE_LINE_ID : ORACLE_LINE_ID (bilgi)
-- ABYS_LREF : kaynak LREF (ABYS_ID ile ayni)
-- ABYS_PROJECT_ID : kaynak ABYS_PROJECT_ID / ORACLE_PROJECT_ID → PROJECT wire
-- Kaynak CTAS: oracleCTAS/LS_PROJECTLINE.sql (KOLON + DAIRE; ABYS_* bridge)
-- PROJECTID / FLATID / AGRID / PARID / REFID : 1. geciste NULL (wire sonra)
--
-- PK + FK aktarim oncesi kaldirilir; recreate DDL asagida sakli.
-- Truncation:
--   REGSNO       nvarchar(100) → nvarchar(50)
--   DESCRIPTION_ nvarchar(500) → nvarchar(1500)  (genis)
--   REASON       nvarchar(500) → nvarchar(1500)  (genis)
--   WORKERID     nvarchar(40)  → nchar(10)
--   FLAT_NUMBER  nvarchar(100) → nvarchar(50)
--   WORKERID2    nvarchar(40)  → int (TRY_CAST; ham ABYS_STG_WORKERID2)
--   SAP_*_NO     nvarchar     → int (TRY_CAST)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_005_01_PROJECTLINE bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- Aktarim oncesi FK + PK kaldir (idempotent)
-- Recreate DDL → dosya sonu / SP_MIG_PROJECTLINE_RESTORE_KEYS
-- ------------------------------------------------------------
IF EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_LS_005_01_PROJECTLINE_LS_005_01_PROJECT'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE')
)
    ALTER TABLE energy.dbo.LS_005_01_PROJECTLINE
        DROP CONSTRAINT FK_LS_005_01_PROJECTLINE_LS_005_01_PROJECT;
GO

IF EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_LS_005_01_PROJECTLINE_LS_FLAT'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE')
)
    ALTER TABLE energy.dbo.LS_005_01_PROJECTLINE
        DROP CONSTRAINT FK_LS_005_01_PROJECTLINE_LS_FLAT;
GO

IF EXISTS (
    SELECT 1 FROM sys.key_constraints
    WHERE name = 'PK_LS_005_01_COLPROJECT'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE')
      AND type = 'PK'
)
    ALTER TABLE energy.dbo.LS_005_01_PROJECTLINE
        DROP CONSTRAINT PK_LS_005_01_COLPROJECT;
GO

-- ------------------------------------------------------------
-- Truncation onleme (idempotent) — hedef dar kolonlar
-- ------------------------------------------------------------
IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE')
      AND c.name = 'REGSNO'
      AND (TYPE_NAME(c.user_type_id) <> 'nvarchar' OR (c.max_length > 0 AND c.max_length < 100))
)
    ALTER TABLE energy.dbo.LS_005_01_PROJECTLINE ALTER COLUMN REGSNO NVARCHAR(50) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE')
      AND c.name = 'WORKERID'
      AND TYPE_NAME(c.user_type_id) = 'nchar'
      AND c.max_length < 20
)
    ALTER TABLE energy.dbo.LS_005_01_PROJECTLINE ALTER COLUMN WORKERID NCHAR(10) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE')
      AND c.name = 'FLAT_NUMBER'
      AND (TYPE_NAME(c.user_type_id) <> 'nvarchar' OR (c.max_length > 0 AND c.max_length < 100))
)
    ALTER TABLE energy.dbo.LS_005_01_PROJECTLINE ALTER COLUMN FLAT_NUMBER NVARCHAR(50) NULL;
GO

-- ------------------------------------------------------------
-- ABYS bridge kolonlari — TABLO SONUNA (idempotent)
-- ------------------------------------------------------------
DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(200) NOT NULL);

INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 (N'ABYS_ID',                  N'BIGINT NULL'),
 (N'ABYS_LREF',                N'BIGINT NULL'),
 (N'ABYS_ORACLE_LINE_ID',      N'BIGINT NULL'),
 (N'ABYS_PROJECT_ID',          N'BIGINT NULL'),
 (N'ABYS_PROJECT_LREF',        N'BIGINT NULL'),
 (N'ABYS_FLAT_ID',             N'BIGINT NULL'),
 (N'ABYS_AGR_ID',              N'BIGINT NULL'),
 (N'ABYS_BNA_ID',              N'BIGINT NULL'),
 (N'ABYS_ENT_ID',              N'BIGINT NULL'),
 (N'ABYS_PAR_ID',              N'BIGINT NULL'),
 (N'ABYS_REF_ID',              N'BIGINT NULL'),
 (N'ABYS_LINE_KIND',           N'SMALLINT NULL'),          -- 1=KOLON 2=DAIRE
 (N'ABYS_PROJECT_BUILDING_ID', N'BIGINT NULL'),
 (N'ABYS_PROJECT_INSTALLATION_ID', N'BIGINT NULL'),
 (N'ABYS_INSTALLATION_ID',     N'BIGINT NULL'),
 (N'ABYS_STG_WORKERID2',       N'NVARCHAR(40) NULL'),
 (N'ABYS_STG_TRC_ENG_ID',      N'BIGINT NULL'),
 (N'ABYS_STG_CTRL_ENG_ID',     N'BIGINT NULL'),
 (N'ABYS_STG_OLD_PROJECT_STATUS', N'SMALLINT NULL'),
 (N'ABYS_STG_TESISAT_NO',      N'DECIMAL(22,0) NULL'),
 (N'ABYS_STG_PROJE_SATIR',     N'BIGINT NULL'),
 (N'ABYS_STG_SERVIS_KUTU_NO',  N'BIGINT NULL'),
 (N'ABYS_STG_PI_TYPE_SET',     N'NVARCHAR(4000) NULL'),
 (N'ABYS_STG_SAP_TUKETIM_NOKTASI', N'NVARCHAR(100) NULL'),
 (N'ABYS_STG_SAP_TESISAT_NO',  N'NVARCHAR(100) NULL');

SELECT @Sql = @Sql + N'
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(''energy.dbo.LS_005_01_PROJECTLINE'')
      AND name = ''' + COL_NAME + N'''
)
    ALTER TABLE energy.dbo.LS_005_01_PROJECTLINE ADD ' + COL_NAME + N' ' + COL_DEF + N';'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE')
      AND name = 'UX_LS_005_01_PROJECTLINE_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_005_01_PROJECTLINE_ABYS_ID
        ON energy.dbo.LS_005_01_PROJECTLINE (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE')
      AND name = 'IX_LS_005_01_PROJECTLINE_ABYS_LREF'
)
    CREATE NONCLUSTERED INDEX IX_LS_005_01_PROJECTLINE_ABYS_LREF
        ON energy.dbo.LS_005_01_PROJECTLINE (ABYS_LREF)
        INCLUDE (LREF)
        WHERE ABYS_LREF IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE')
      AND name = 'IX_LS_005_01_PROJECTLINE_ABYS_PROJECT_ID'
)
    CREATE NONCLUSTERED INDEX IX_LS_005_01_PROJECTLINE_ABYS_PROJECT_ID
        ON energy.dbo.LS_005_01_PROJECTLINE (ABYS_PROJECT_ID)
        INCLUDE (LREF)
        WHERE ABYS_PROJECT_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Kaynak / hedef kolon dogrulama
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_PROJECTLINE_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_PROJECTLINE', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_PROJECTLINE bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('ORACLE_PROJECT_ID'), ('ORACLE_LINE_ID'),
            ('PROJECTID'), ('BNA_ID'), ('ENT_ID'), ('FLATID'), ('AGRID'),
            ('ISACTIVE'), ('STATID'), ('PROJECTUSER'), ('FLOWRATE'),
            ('REGMODEL'), ('REGSNO'),
            ('ACPT_APP_DATE'), ('APPSDATE'), ('APPEDATE'), ('APPCENG'),
            ('PARID'), ('REVISION_TYPE'), ('DESCRIPTION_'),
            ('FRMID2'), ('ENGID2'), ('WORKERID2'),
            ('FRMID'), ('ENGID'), ('WORKERID'),
            ('REASON'), ('REFID'), ('REFUSEISACTIVE'), ('COMPLETIONID'),
            ('UPDUSER'), ('UPDDATE'), ('ADDUSER'), ('ADDDATE'),
            ('TLTOTAL'), ('ISGASON'), ('FMETHOD'), ('CONFIRMDATE'),
            ('REG_CALCPRESS'), ('XTYPE'), ('OLOC_ID'),
            ('PROJ_ACPT_DATE'), ('PROJ_ENTER_DATE'), ('CONFIRMDATE_REAL'),
            ('INSURANCENO'), ('INSURANCE_EDATE'), ('INSURANCE_SDATE'),
            ('AREA'), ('FLAT_NUMBER'), ('INSURANCE_FIRM_ID'),
            ('PROJECT_TYPE_ID'),
            ('SAP_TUKETIM_NOKTASI'), ('SAP_PROJECT_NUMBER'), ('SAP_TESISAT_NO'),
            -- CTAS ABYS_* bridge (oracleCTAS/LS_PROJECTLINE.sql)
            ('ABYS_LINE_KIND'),
            ('ABYS_PROJECT_ID'),
            ('ABYS_PROJECT_BUILDING_ID'),
            ('ABYS_PROJECT_INSTALLATION_ID'),
            ('ABYS_INSTALLATION_ID'),
            ('ABYS_STG_TRC_ENG_ID'),
            ('ABYS_STG_CTRL_ENG_ID'),
            ('ABYS_STG_OLD_PROJECT_STATUS'),
            ('ABYS_STG_TESISAT_NO'),
            ('ABYS_STG_PROJE_SATIR'),
            ('ABYS_STG_SERVIS_KUTU_NO'),
            ('ABYS_STG_WORKERID2'),
            ('ABYS_STG_PI_TYPE_SET')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'LS_PROJECTLINE' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_PROJECTLINE eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        ELSE SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_PROJECTLINE kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_PROJECTLINE_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_PROJECTLINE bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('PROJECTID'), ('BNA_ID'), ('ENT_ID'), ('FLATID'), ('AGRID'),
            ('ISACTIVE'), ('STATID'), ('PROJECTUSER'), ('FLOWRATE'),
            ('REGMODEL'), ('REGSNO'),
            ('ACPT_APP_DATE'), ('APPSDATE'), ('APPEDATE'), ('APPCENG'),
            ('PARID'), ('REVISION_TYPE'), ('DESCRIPTION_'),
            ('FRMID2'), ('ENGID2'), ('WORKERID2'),
            ('FRMID'), ('ENGID'), ('WORKERID'),
            ('REASON'), ('REFID'), ('REFUSEISACTIVE'), ('COMPLETIONID'),
            ('UPDUSER'), ('UPDDATE'), ('ADDUSER'), ('ADDDATE'),
            ('TLTOTAL'), ('ISGASON'), ('FMETHOD'), ('CONFIRMDATE'),
            ('REG_CALCPRESS'), ('XTYPE'), ('OLOC_ID'),
            ('PROJ_ACPT_DATE'), ('PROJ_ENTER_DATE'), ('CONFIRMDATE_REAL'),
            ('INSURANCENO'), ('INSURANCE_EDATE'), ('INSURANCE_SDATE'),
            ('AREA'), ('FLAT_NUMBER'), ('INSURANCE_FIRM_ID'),
            ('PROJECT_TYPE_ID'),
            ('SAP_TUKETIM_NOKTASI'), ('SAP_PROJECT_NUMBER'), ('SAP_TESISAT_NO'),
            ('ABYS_ID'), ('ABYS_LREF'), ('ABYS_ORACLE_LINE_ID'),
            ('ABYS_PROJECT_ID'), ('ABYS_PROJECT_LREF'),
            ('ABYS_FLAT_ID'), ('ABYS_AGR_ID'),
            ('ABYS_BNA_ID'), ('ABYS_ENT_ID'), ('ABYS_PAR_ID'), ('ABYS_REF_ID'),
            ('ABYS_LINE_KIND'),
            ('ABYS_PROJECT_BUILDING_ID'),
            ('ABYS_PROJECT_INSTALLATION_ID'),
            ('ABYS_INSTALLATION_ID'),
            ('ABYS_STG_WORKERID2'), ('ABYS_STG_TRC_ENG_ID'), ('ABYS_STG_CTRL_ENG_ID'),
            ('ABYS_STG_OLD_PROJECT_STATUS'), ('ABYS_STG_TESISAT_NO'),
            ('ABYS_STG_PROJE_SATIR'), ('ABYS_STG_SERVIS_KUTU_NO'),
            ('ABYS_STG_PI_TYPE_SET'),
            ('ABYS_STG_SAP_TUKETIM_NOKTASI'), ('ABYS_STG_SAP_TESISAT_NO')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_PROJECTLINE eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        ELSE SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_PROJECTLINE hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_PROJECTLINE_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.SP_MIG_PROJECTLINE_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    EXEC dbo.SP_MIG_PROJECTLINE_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
END
GO

-- ------------------------------------------------------------
-- PK + FK restore (wire SONRASI calistir)
-- Saklanan recreate DDL
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_PROJECTLINE_RESTORE_KEYS
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE', 'U') IS NULL
    BEGIN
        RAISERROR('energy.dbo.LS_005_01_PROJECTLINE bulunamadi.', 16, 1);
        RETURN;
    END

    -- PK
    IF NOT EXISTS (
        SELECT 1 FROM sys.key_constraints
        WHERE name = 'PK_LS_005_01_COLPROJECT'
          AND parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE')
          AND type = 'PK'
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE PK_LS_005_01_COLPROJECT...', 0, 1) WITH NOWAIT;

        ALTER TABLE energy.dbo.LS_005_01_PROJECTLINE
            ADD CONSTRAINT PK_LS_005_01_COLPROJECT PRIMARY KEY CLUSTERED (LREF ASC)
            WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF,
                  ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 50);
    END

    -- FK → PROJECT
    IF NOT EXISTS (
        SELECT 1 FROM sys.foreign_keys
        WHERE name = 'FK_LS_005_01_PROJECTLINE_LS_005_01_PROJECT'
          AND parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE')
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE FK_LS_005_01_PROJECTLINE_LS_005_01_PROJECT...', 0, 1) WITH NOWAIT;

        ALTER TABLE energy.dbo.LS_005_01_PROJECTLINE WITH CHECK
            ADD CONSTRAINT FK_LS_005_01_PROJECTLINE_LS_005_01_PROJECT
            FOREIGN KEY (PROJECTID) REFERENCES energy.dbo.LS_005_01_PROJECT (LREF);

        ALTER TABLE energy.dbo.LS_005_01_PROJECTLINE
            CHECK CONSTRAINT FK_LS_005_01_PROJECTLINE_LS_005_01_PROJECT;
    END

    -- FK → FLAT
    IF NOT EXISTS (
        SELECT 1 FROM sys.foreign_keys
        WHERE name = 'FK_LS_005_01_PROJECTLINE_LS_FLAT'
          AND parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_PROJECTLINE')
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE FK_LS_005_01_PROJECTLINE_LS_FLAT...', 0, 1) WITH NOWAIT;

        ALTER TABLE energy.dbo.LS_005_01_PROJECTLINE WITH NOCHECK
            ADD CONSTRAINT FK_LS_005_01_PROJECTLINE_LS_FLAT
            FOREIGN KEY (FLATID) REFERENCES energy.dbo.LS_FLAT (LREF);

        ALTER TABLE energy.dbo.LS_005_01_PROJECTLINE
            CHECK CONSTRAINT FK_LS_005_01_PROJECTLINE_LS_FLAT;
    END

    IF @DEBUG = 1
        RAISERROR('SP_MIG_PROJECTLINE_RESTORE_KEYS OK', 0, 1) WITH NOWAIT;
END
GO

/*
-- SAKLANAN RECREATE DDL (manuel referans)
ALTER TABLE [dbo].[LS_005_01_PROJECTLINE] ADD CONSTRAINT [PK_LS_005_01_COLPROJECT]
    PRIMARY KEY CLUSTERED ([LREF] ASC)
    WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF,
          ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 50);

ALTER TABLE [dbo].[LS_005_01_PROJECTLINE] WITH CHECK
    ADD CONSTRAINT [FK_LS_005_01_PROJECTLINE_LS_005_01_PROJECT]
    FOREIGN KEY([PROJECTID]) REFERENCES [dbo].[LS_005_01_PROJECT] ([LREF]);
ALTER TABLE [dbo].[LS_005_01_PROJECTLINE]
    CHECK CONSTRAINT [FK_LS_005_01_PROJECTLINE_LS_005_01_PROJECT];

ALTER TABLE [dbo].[LS_005_01_PROJECTLINE] WITH NOCHECK
    ADD CONSTRAINT [FK_LS_005_01_PROJECTLINE_LS_FLAT]
    FOREIGN KEY([FLATID]) REFERENCES [dbo].[LS_FLAT] ([LREF]);
ALTER TABLE [dbo].[LS_005_01_PROJECTLINE]
    CHECK CONSTRAINT [FK_LS_005_01_PROJECTLINE_LS_FLAT];
*/

-- ------------------------------------------------------------
-- Kaynak view (kolon eslemesi tek nokta)
-- LREF IDENTITY — view'da yok / INSERT'te yazilmaz
-- PROJECTID / FLATID / AGRID = NULL (wire sonra)
-- Bridge: ABYS_ID = LREF (ORACLE_LINE_ID tekil degil)
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.VW_MIG_PROJECTLINE_SOURCE
AS
SELECT
    CAST(s.LREF AS BIGINT)                                                  AS ABYS_ID,
    CAST(s.LREF AS BIGINT)                                                  AS ABYS_LREF,
    CAST(s.ORACLE_LINE_ID AS BIGINT)                                        AS ABYS_ORACLE_LINE_ID,
    CAST(COALESCE(s.ABYS_PROJECT_ID, s.ORACLE_PROJECT_ID) AS BIGINT)        AS ABYS_PROJECT_ID,
    CAST(TRY_CAST(s.PROJECTID AS BIGINT) AS BIGINT)                         AS ABYS_PROJECT_LREF,
    CAST(TRY_CAST(s.FLATID AS DECIMAL(22, 0)) AS BIGINT)                     AS ABYS_FLAT_ID,
    CAST(TRY_CAST(s.AGRID AS DECIMAL(22, 0)) AS BIGINT)                      AS ABYS_AGR_ID,
    CAST(TRY_CAST(s.BNA_ID AS BIGINT) AS BIGINT)                             AS ABYS_BNA_ID,
    CAST(TRY_CAST(s.ENT_ID AS DECIMAL(22, 0)) AS BIGINT)                     AS ABYS_ENT_ID,
    CAST(TRY_CAST(s.PARID AS DECIMAL(22, 0)) AS BIGINT)                      AS ABYS_PAR_ID,
    CAST(TRY_CAST(s.REFID AS DECIMAL(22, 0)) AS BIGINT)                      AS ABYS_REF_ID,
    CAST(TRY_CAST(s.ABYS_LINE_KIND AS SMALLINT) AS SMALLINT)                AS ABYS_LINE_KIND,
    CAST(s.ABYS_PROJECT_BUILDING_ID AS BIGINT)                               AS ABYS_PROJECT_BUILDING_ID,
    CAST(s.ABYS_PROJECT_INSTALLATION_ID AS BIGINT)                           AS ABYS_PROJECT_INSTALLATION_ID,
    CAST(s.ABYS_INSTALLATION_ID AS BIGINT)                                   AS ABYS_INSTALLATION_ID,
    LEFT(COALESCE(s.ABYS_STG_WORKERID2, CAST(s.WORKERID2 AS NVARCHAR(40))), 40)
                                                                            AS ABYS_STG_WORKERID2,
    CAST(s.ABYS_STG_TRC_ENG_ID AS BIGINT)                                    AS ABYS_STG_TRC_ENG_ID,
    CAST(s.ABYS_STG_CTRL_ENG_ID AS BIGINT)                                   AS ABYS_STG_CTRL_ENG_ID,
    CAST(s.ABYS_STG_OLD_PROJECT_STATUS AS SMALLINT)                          AS ABYS_STG_OLD_PROJECT_STATUS,
    TRY_CAST(s.ABYS_STG_TESISAT_NO AS DECIMAL(22, 0))                        AS ABYS_STG_TESISAT_NO,
    CAST(s.ABYS_STG_PROJE_SATIR AS BIGINT)                                   AS ABYS_STG_PROJE_SATIR,
    CAST(s.ABYS_STG_SERVIS_KUTU_NO AS BIGINT)                                AS ABYS_STG_SERVIS_KUTU_NO,
    LEFT(s.ABYS_STG_PI_TYPE_SET, 4000)                                      AS ABYS_STG_PI_TYPE_SET,
    LEFT(CAST(s.SAP_TUKETIM_NOKTASI AS NVARCHAR(100)), 100)                 AS ABYS_STG_SAP_TUKETIM_NOKTASI,
    LEFT(CAST(s.SAP_TESISAT_NO AS NVARCHAR(100)), 100)                      AS ABYS_STG_SAP_TESISAT_NO,

    -- Hedef FK / self-ref kolonlari: 1. geciste NULL (wire sonra)
    CAST(NULL AS INT)                                                       AS PROJECTID,
    CAST(TRY_CAST(s.BNA_ID AS BIGINT) AS INT)                               AS BNA_ID,
    CAST(TRY_CAST(s.ENT_ID AS DECIMAL(22, 0)) AS INT)                       AS ENT_ID,
    CAST(NULL AS INT)                                                       AS FLATID,
    CAST(NULL AS INT)                                                       AS AGRID,
    CAST(CASE WHEN ISNULL(TRY_CAST(s.ISACTIVE AS INT), 1) <> 0 THEN 1 ELSE 0 END AS BIT) AS ISACTIVE,
    CAST(TRY_CAST(s.STATID AS DECIMAL(22, 0)) AS INT)                       AS STATID,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.PROJECTUSER AS BIGINT) AS INT)) AS PROJECTUSER,
    TRY_CAST(s.FLOWRATE AS FLOAT)                                           AS FLOWRATE,
    CAST(TRY_CAST(s.REGMODEL AS BIGINT) AS INT)                             AS REGMODEL,
    LEFT(s.REGSNO, 50)                                                      AS REGSNO,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ACPT_APP_DATE AS DATETIME2))      AS ACPT_APP_DATE,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.APPSDATE AS DATETIME2))           AS APPSDATE,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.APPEDATE AS DATETIME2))           AS APPEDATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.APPCENG AS DECIMAL(22, 0)) AS INT)) AS APPCENG,
    CAST(NULL AS INT)                                                       AS PARID,  -- ABYS_PAR_ID → wire
    CAST(TRY_CAST(s.REVISION_TYPE AS DECIMAL(22, 0)) AS INT)                AS REVISION_TYPE,
    LEFT(s.DESCRIPTION_, 1500)                                              AS DESCRIPTION_,
    CAST(TRY_CAST(s.FRMID2 AS BIGINT) AS INT)                               AS FRMID2,
    CAST(TRY_CAST(s.ENGID2 AS BIGINT) AS INT)                               AS ENGID2,
    CAST(TRY_CAST(s.WORKERID2 AS INT) AS INT)                               AS WORKERID2,
    CAST(TRY_CAST(s.FRMID AS BIGINT) AS INT)                                AS FRMID,
    CAST(TRY_CAST(s.ENGID AS BIGINT) AS INT)                                AS ENGID,
    CAST(LEFT(s.WORKERID, 10) AS NCHAR(10))                                 AS WORKERID,
    LEFT(s.REASON, 1500)                                                    AS REASON,
    CAST(NULL AS INT)                                                       AS REFID,  -- ABYS_REF_ID → wire
    CAST(CASE WHEN ISNULL(TRY_CAST(s.REFUSEISACTIVE AS INT), 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS REFUSEISACTIVE,
    CAST(TRY_CAST(s.COMPLETIONID AS DECIMAL(22, 0)) AS INT)                 AS COMPLETIONID,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.UPDUSER AS BIGINT) AS INT)) AS UPDUSER,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.UPDDATE AS DATETIME2))            AS UPDDATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.ADDUSER AS BIGINT) AS INT)) AS ADDUSER,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ADDDATE AS DATETIME2))            AS ADDDATE,
    TRY_CAST(s.TLTOTAL AS FLOAT)                                            AS TLTOTAL,
    CAST(CASE WHEN ISNULL(TRY_CAST(s.ISGASON AS INT), 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS ISGASON,
    CAST(TRY_CAST(s.FMETHOD AS DECIMAL(22, 0)) AS INT)                      AS FMETHOD,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.CONFIRMDATE AS DATETIME2))        AS CONFIRMDATE,
    CAST(s.REG_CALCPRESS AS INT)                                            AS REG_CALCPRESS,
    CAST(TRY_CAST(s.XTYPE AS DECIMAL(22, 0)) AS INT)                        AS XTYPE,
    CAST(TRY_CAST(s.OLOC_ID AS DECIMAL(22, 0)) AS INT)                      AS OLOC_ID,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.PROJ_ACPT_DATE AS DATETIME2))     AS PROJ_ACPT_DATE,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.PROJ_ENTER_DATE AS DATETIME2))    AS PROJ_ENTER_DATE,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.CONFIRMDATE_REAL AS DATETIME2))   AS CONFIRMDATE_REAL,
    LEFT(s.INSURANCENO, 50)                                                 AS INSURANCENO,
    CAST(s.INSURANCE_EDATE AS DATETIME)                                     AS INSURANCE_EDATE,
    CAST(s.INSURANCE_SDATE AS DATETIME)                                     AS INSURANCE_SDATE,
    CAST(TRY_CAST(s.AREA AS DECIMAL(12, 2)) AS DECIMAL(12, 2))              AS AREA,
    LEFT(s.FLAT_NUMBER, 50)                                                 AS FLAT_NUMBER,
    CAST(TRY_CAST(s.INSURANCE_FIRM_ID AS DECIMAL(22, 0)) AS INT)            AS INSURANCE_FIRM_ID,
    CAST(TRY_CAST(s.PROJECT_TYPE_ID AS DECIMAL(22, 0)) AS INT)              AS PROJECT_TYPE_ID,
    CAST(TRY_CAST(s.SAP_TUKETIM_NOKTASI AS INT) AS INT)                     AS SAP_TUKETIM_NOKTASI,
    LEFT(s.SAP_PROJECT_NUMBER, 100)                                         AS SAP_PROJECT_NUMBER,
    CAST(TRY_CAST(s.SAP_TESISAT_NO AS INT) AS INT)                          AS SAP_TESISAT_NO
FROM izgazMGR.dbo.LS_PROJECTLINE s
WHERE s.LREF IS NOT NULL;
GO

EXEC dbo.SP_MIG_PROJECTLINE_VALIDATE_SOURCE @RaiseOnMissing = 0;
EXEC dbo.SP_MIG_PROJECTLINE_VALIDATE_TARGET @RaiseOnMissing = 0;
GO
