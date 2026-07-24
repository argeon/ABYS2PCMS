/* ============================================================
   SCRIPT_ID : AGR_AGR_SETUP
   SCRIPT_NO : 300
   FILE      : 300_AGR_AGR__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.LS_AGREEMENT → energy.dbo.LS_005_01_AGR
--   LREF    : IDENTITY (otomatik)
--   ABYS_ID : kaynak değeri aynen (KUL+ABN birleşimi; TP2 ile ayırt)
--   Köprü   : MIG_ROW_ID (ADDDATE, TP2, ABYS_ID sırası)
--   FK      : aktarım öncesi kaldırılır; veri düzeltme sonra yapılacak
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- Yardımcı fonksiyonlar
-- ------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.FN_MIG_DEC_TO_BIT (@Val DECIMAL(22,0))
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN ISNULL(TRY_CAST(@Val AS INT), 0) <> 0 THEN 1 ELSE 0 END;
END
GO

-- ------------------------------------------------------------
-- Aktarım öncesi FK kaldırma (veri düzeltme sonra yapılacak)
-- ------------------------------------------------------------
IF EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_LS_005_01_AGR_LS_005_SUBSCR'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR')
)
    ALTER TABLE energy.dbo.LS_005_01_AGR DROP CONSTRAINT FK_LS_005_01_AGR_LS_005_SUBSCR;
GO

IF EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_LS_005_01_AGR_LS_FLAT'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR')
)
    ALTER TABLE energy.dbo.LS_005_01_AGR DROP CONSTRAINT FK_LS_005_01_AGR_LS_FLAT;
GO

IF EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_LS_005_01_AGR_LS_LOOKUP'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR')
)
    ALTER TABLE energy.dbo.LS_005_01_AGR DROP CONSTRAINT FK_LS_005_01_AGR_LS_LOOKUP;
GO

IF EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_LS_005_01_AGR_LS_LOOKUP1'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR')
)
    ALTER TABLE energy.dbo.LS_005_01_AGR DROP CONSTRAINT FK_LS_005_01_AGR_LS_LOOKUP1;
GO

-- ------------------------------------------------------------
-- Hedef ABYS / köprü kolonları
-- ------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_MIG_ROW_ID')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_MIG_ROW_ID BIGINT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_ID')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_ID BIGINT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_REFUND_DATE')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_REFUND_DATE DATETIME2(0) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_SKB_TARIFF_TYPE_ID')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_SKB_TARIFF_TYPE_ID BIGINT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_TARIFF_TYPE_ID')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_TARIFF_TYPE_ID BIGINT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_INSTALLATION_STATUS_ID')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_INSTALLATION_STATUS_ID SMALLINT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_SERVICE_BOX_ID')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_SERVICE_BOX_ID BIGINT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_HOUSEHOLDS_COUNT')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_HOUSEHOLDS_COUNT BIGINT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_FIRST_STARTUP_DATE')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_FIRST_STARTUP_DATE DATETIME2(0) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_SUBSCRIBER_TYPE')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_SUBSCRIBER_TYPE NVARCHAR(50) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_SKB_TARIFF_TYPE')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_SKB_TARIFF_TYPE NVARCHAR(200) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_TARIFF_TYPE')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_TARIFF_TYPE NVARCHAR(200) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_INSTALLATION_STATUS')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_INSTALLATION_STATUS NVARCHAR(50) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_PCMS_TARIFF_TYPE_NAME')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_PCMS_TARIFF_TYPE_NAME NVARCHAR(200) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_PROJECT_STATUS')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_PROJECT_STATUS DECIMAL(22,0) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR') AND name = 'ABYS_CLOSESTAT_DATE')
    ALTER TABLE energy.dbo.LS_005_01_AGR ADD ABYS_CLOSESTAT_DATE DATETIME2(0) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR')
      AND name = 'UX_LS_005_01_AGR_ABYS_MIG'
)
    DROP INDEX UX_LS_005_01_AGR_ABYS_MIG ON energy.dbo.LS_005_01_AGR;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR')
      AND name = 'UX_LS_005_01_AGR_ABYS_MIG'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_005_01_AGR_ABYS_MIG
        ON energy.dbo.LS_005_01_AGR (ABYS_MIG_ROW_ID)
        WHERE ABYS_MIG_ROW_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR')
      AND name = 'UX_LS_005_01_AGR_TP2_ABYS'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_005_01_AGR_TP2_ABYS
        ON energy.dbo.LS_005_01_AGR (TP2, ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Kaynak staging: MIG_ROW_ID
-- ------------------------------------------------------------
IF OBJECT_ID('izgazMGR.dbo.LS_AGREEMENT', 'U') IS NOT NULL
BEGIN
    IF COL_LENGTH('izgazMGR.dbo.LS_AGREEMENT', 'MIG_ROW_ID') IS NOT NULL
       AND COLUMNPROPERTY(
            OBJECT_ID('izgazMGR.dbo.LS_AGREEMENT'),
            'MIG_ROW_ID', 'IsIdentity') = 1
    BEGIN
        IF EXISTS (
            SELECT 1 FROM izgazMGR.sys.indexes
            WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_AGREEMENT')
              AND name = 'UX_LS_AGREEMENT_MIG_ROW'
        )
            DROP INDEX UX_LS_AGREEMENT_MIG_ROW ON izgazMGR.dbo.LS_AGREEMENT;

        ALTER TABLE izgazMGR.dbo.LS_AGREEMENT DROP COLUMN MIG_ROW_ID;
    END

    IF COL_LENGTH('izgazMGR.dbo.LS_AGREEMENT', 'MIG_ROW_ID') IS NULL
        ALTER TABLE izgazMGR.dbo.LS_AGREEMENT ADD MIG_ROW_ID BIGINT NULL;

    IF COL_LENGTH('izgazMGR.dbo.LS_AGREEMENT', '_MIG_UID') IS NULL
        ALTER TABLE izgazMGR.dbo.LS_AGREEMENT
            ADD _MIG_UID INT IDENTITY(1, 1) NOT NULL;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_PREP_SOURCE
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_AGREEMENT', 'U') IS NULL
        RETURN;

    IF COL_LENGTH('izgazMGR.dbo.LS_AGREEMENT', 'MIG_ROW_ID') IS NULL
       OR COL_LENGTH('izgazMGR.dbo.LS_AGREEMENT', '_MIG_UID') IS NULL
    BEGIN
        RAISERROR('LS_AGREEMENT: MIG_ROW_ID veya _MIG_UID yok. Once 46_ls005_agr_setup.sql calistirin.', 16, 1);
        RETURN;
    END

    ;WITH Ordered AS (
        SELECT
            s._MIG_UID,
            ROW_NUMBER() OVER (
                ORDER BY
                    CAST(s.ADDDATE AS DATETIME2),
                    RTRIM(s.TP2),
                    s.ABYS_ID,
                    s._MIG_UID
            ) AS NewMigRowId
        FROM izgazMGR.dbo.LS_AGREEMENT s
    )
    UPDATE s
    SET s.MIG_ROW_ID = o.NewMigRowId
    FROM izgazMGR.dbo.LS_AGREEMENT s
    INNER JOIN Ordered o ON o._MIG_UID = s._MIG_UID;

    IF EXISTS (
        SELECT 1 FROM izgazMGR.dbo.LS_AGREEMENT WHERE MIG_ROW_ID IS NULL
    )
        RAISERROR('LS_AGREEMENT: MIG_ROW_ID atamasi tamamlanamadi.', 16, 1);

    IF EXISTS (
        SELECT 1 FROM izgazMGR.sys.indexes
        WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_AGREEMENT')
          AND name = 'UX_LS_AGREEMENT_MIG_ROW'
    )
        DROP INDEX UX_LS_AGREEMENT_MIG_ROW ON izgazMGR.dbo.LS_AGREEMENT;

    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_AGREEMENT_MIG_ROW
        ON izgazMGR.dbo.LS_AGREEMENT (MIG_ROW_ID);
END
GO

-- ------------------------------------------------------------
-- Kaynak / hedef doğrulama
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_AGREEMENT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_AGREEMENT bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('MIG_ROW_ID'), ('TP2'), ('ABYS_ID'), ('FLATID'), ('CON'),
            ('AGR_SDATE'), ('STATID'), ('ISACTIVE'),
            ('ADDDATE'), ('ADDUSER')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'LS_AGREEMENT' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @MsgSrc NVARCHAR(4000) = N'LS_AGREEMENT eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@MsgSrc, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_AGREEMENT kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_AGR', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_AGR bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'), ('TP2'), ('FLATID'), ('CON'), ('STATID'),
            ('ABYS_MIG_ROW_ID'), ('ABYS_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_AGR')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @MsgTgt NVARCHAR(4000) = N'LS_005_01_AGR eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@MsgTgt, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_AGR hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Kaynak view (kolon eşlemesi tek nokta)
-- FK yok: FLATID / CON / BN_TYPE / PAYTYPE kaynak değerleri aynen
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.VW_MIG_AGR_SOURCE
AS
SELECT
    s.MIG_ROW_ID,
    CAST(s.ABYS_ID AS BIGINT)                                           AS ABYS_ID,
    LEFT(RTRIM(s.TP2), 5)                                               AS TP2,
    CAST(TRY_CAST(s.FLATID AS BIGINT) AS INT)                           AS FLATID,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.AGR_SDATE AS DATETIME2))      AS AGR_SDATE,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.AGR_EDATE AS DATETIME2))      AS AGR_EDATE,
    CAST(TRY_CAST(s.BN_TYPE AS BIGINT) AS INT)                          AS BN_TYPE,
    CAST(TRY_CAST(s.FRMID AS BIGINT) AS INT)                            AS FRMID,
    CAST(TRY_CAST(s.CON AS BIGINT) AS INT)                              AS CON,
    LEFT(s.TP1, 5)                                                      AS TP1,
    LEFT(RTRIM(s.TP3), 5)                                               AS TP3,
    CAST(TRY_CAST(s.FMETHOD AS BIGINT) AS INT)                          AS FMETHOD,
    CAST(TRY_CAST(s.FPARID AS BIGINT) AS INT)                            AS FPARID,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.FMANUAL)                             AS FMANUAL,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.PAY_SDATE AS DATETIME2))      AS PAY_SDATE,
    TRY_CAST(s.PAY_TOTAL AS FLOAT)                                      AS PAY_TOTAL,
    CAST(TRY_CAST(s.STATID AS BIGINT) AS INT)                           AS STATID,
    CAST(TRY_CAST(s.PARID AS BIGINT) AS INT)                            AS PARID,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.ISACTIVE)                            AS ISACTIVE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.ADDUSER AS BIGINT) AS INT)) AS ADDUSER,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ADDDATE AS DATETIME2))        AS ADDDATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.UPDUSER AS BIGINT) AS INT)) AS UPDUSER,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.UPDDATE AS DATETIME2))        AS UPDDATE,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.NEEDPAY)                             AS NEEDPAY,
    TRY_CAST(s.TLTOTAL AS FLOAT)                                        AS TLTOTAL,
    TRY_CAST(s.CURTOTAL AS FLOAT)                                       AS CURTOTAL,
    CAST(TRY_CAST(s.CURTYPE AS BIGINT) AS INT)                          AS CURTYPE,
    CAST(TRY_CAST(s.PAYTYPE AS BIGINT) AS INT)                          AS PAYTYPE,
    TRY_CAST(s.FITNO AS BIGINT)                                         AS FITNO,
    energy.dbo.FN_MIG_FIT_NUMERIC(s.GRANDTOTAL, 'LS_005_01_AGR', 'GRANDTOTAL') AS GRANDTOTAL,
    energy.dbo.FN_MIG_FIT_NUMERIC(s.TAX, 'LS_005_01_AGR', 'TAX')        AS TAX,
    energy.dbo.FN_MIG_FIT_NUMERIC(s.DV, 'LS_005_01_AGR', 'DV')          AS DV,
    CAST(TRY_CAST(s.COUNTERMODEL AS BIGINT) AS INT)                     AS COUNTERMODEL,
    LEFT(s.COUNTERSN, 50)                                               AS COUNTERSN,
    CAST(TRY_CAST(s.COUNTERID AS BIGINT) AS INT)                        AS COUNTERID,
    LEFT(CAST(s.COUNTERMBAR AS NVARCHAR(20)), 10)                       AS COUNTERMBAR,
    CAST(TRY_CAST(s.CALCPRESSID AS BIGINT) AS INT)                      AS CALCPRESSID,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.OPENED)                              AS OPENED,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.OPEN_DATE AS DATETIME2))      AS OPEN_DATE,
    CAST(TRY_CAST(s.BNA_ID AS BIGINT) AS INT)                           AS BNA_ID,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.INV_PRINT_DATE AS DATETIME2)) AS INV_PRINT_DATE,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.REFUND)                              AS REFUND,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.FEE_COLLECTED)                       AS FEE_COLLECTED,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.LASTREAD_DATE AS DATETIME2))  AS LASTREAD_DATE,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.EXPIRE_DEBTTIME)                     AS EXPIRE_DEBTTIME,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.HAS_USING_AGR)                       AS HAS_USING_AGR,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.IS_GS)                               AS IS_GS,
    TRY_CAST(s.OLOC_ID AS BIGINT)                                       AS OLOC_ID,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.IS_FIRST_USE)                        AS IS_FIRST_USE,
    CAST(NULL AS INT)                                                   AS CLOSESTATID,
    CAST(TRY_CAST(s.PAY_BANKREF AS BIGINT) AS INT)                      AS PAY_BANKREF,
    LEFT(s.NOTE, 4000)                                                  AS NOTE,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.TRANS)                               AS TRANS,
    CAST(TRY_CAST(s.OLREF AS BIGINT) AS INT)                            AS OLREF,
    CAST(TRY_CAST(s.COUNTER_STAT AS BIGINT) AS INT)                     AS COUNTER_STAT,
    CAST(TRY_CAST(s.SON_ODEME_GUNU AS BIGINT) AS INT)                     AS SON_ODEME_GUNU,
    CAST(TRY_CAST(s.CAP AS BIGINT) AS INT)                              AS Cap,
    CAST(TRY_CAST(s.BASINC AS BIGINT) AS INT)                            AS Basinc,
    CAST(TRY_CAST(s.TIP AS BIGINT) AS INT)                              AS Tip,
    CAST(TRY_CAST(s.APP_ID AS BIGINT) AS INT)                           AS APP_ID,
    LEFT(s.AGREEMENT_NUMBER, 100)                                       AS AGREEMENT_NUMBER,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.ISTAXFREE)                           AS ISTAXFREE,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.ISDVFREE)                            AS ISDVFREE,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.ISOTVFREE)                           AS ISOTVFREE,
    energy.dbo.FN_MIG_DEC_TO_BIT(s.ISNOTCALCDV)                         AS ISNOTCALCDV,
    CAST(TRY_CAST(s.TUKETIM_NOKTASI AS BIGINT) AS INT)                  AS TUKETIM_NOKTASI,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ABYS_REFUND_DATE AS DATETIME2)) AS ABYS_REFUND_DATE,
    s.SKB_TARIFF_TYPE_ID                                                AS ABYS_SKB_TARIFF_TYPE_ID,
    s.TARIFF_TYPE_ID                                                    AS ABYS_TARIFF_TYPE_ID,
    CAST(TRY_CAST(s.INSTALLATION_STATUS_ID AS BIGINT) AS SMALLINT)      AS ABYS_INSTALLATION_STATUS_ID,
    s.SERVICE_BOX_ID                                                    AS ABYS_SERVICE_BOX_ID,
    s.HOUSEHOLDS_COUNT                                                  AS ABYS_HOUSEHOLDS_COUNT,
    CAST(s.FIRST_STARTUP_DATE AS DATETIME2)                             AS ABYS_FIRST_STARTUP_DATE,
    LEFT(s.ABYS_SUBSCRIBER_TYPE, 50)                                    AS ABYS_SUBSCRIBER_TYPE,
    LEFT(s.ABYS_SKB_TARIFF_TYPE, 200)                                   AS ABYS_SKB_TARIFF_TYPE,
    LEFT(s.ABYS_TARIFF_TYPE, 200)                                       AS ABYS_TARIFF_TYPE,
    LEFT(s.ABYS_INSTALLATION_STATUS, 50)                                AS ABYS_INSTALLATION_STATUS,
    LEFT(s.PCMS_TARIFF_TYPE_NAME, 200)                                  AS ABYS_PCMS_TARIFF_TYPE_NAME,
    s.ABYS_PROJECT_STATUS                                               AS ABYS_PROJECT_STATUS,
    CAST(s.CLOSESTATID AS DATETIME2)                                    AS ABYS_CLOSESTAT_DATE,
    ROW_NUMBER() OVER (
        PARTITION BY LEFT(RTRIM(s.TP2), 5), CAST(s.ABYS_ID AS BIGINT)
        ORDER BY s.MIG_ROW_ID
    )                                                                   AS ABYS_DUP_RN
FROM izgazMGR.dbo.LS_AGREEMENT s
WHERE s.MIG_ROW_ID IS NOT NULL;
GO

EXEC dbo.SP_MIG_AGR_PREP_SOURCE;
GO

IF OBJECT_ID('dbo.SP_MIGRATE_LS005_AGR', 'P') IS NOT NULL
    EXEC sys.sp_refreshsqlmodule N'dbo.SP_MIGRATE_LS005_AGR';
GO

EXEC dbo.SP_MIG_AGR_VALIDATE_SOURCE @RaiseOnMissing = 0;
EXEC dbo.SP_MIG_AGR_VALIDATE_TARGET @RaiseOnMissing = 0;
GO

