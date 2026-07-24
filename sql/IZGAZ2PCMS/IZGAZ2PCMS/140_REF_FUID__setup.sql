/* ============================================================
   SCRIPT_ID : REF_FUID_SETUP
   SCRIPT_NO : 140
   FILE      : 140_REF_FUID__setup.sql
   VERSION   : 2
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.me_factor_value → energy.dbo.LS_005_FUID
--   LREF    ← ID
--   VAL     ← HIGHER_HEATING_VALUE
--   DATE_   ← ACTION_DATE
--   RMSID   ← LS_005_RMS.LREF (SERVICE_BOX_ID = DEFN)
--   ADDUSER ← CREATED_USER_ID
--   ADDDATE ← CREATED_TIMESTAMP
-- ============================================================


 

USE energy;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_LS005_FUID_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('ID'), ('HIGHER_HEATING_VALUE'), ('ACTION_DATE'),
            ('SERVICE_BOX_ID'), ('CREATED_USER_ID'), ('CREATED_TIMESTAMP')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo'
          AND t.name = 'me_factor_value'
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'me_factor_value eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1
            RAISERROR(@Msg, 16, 1);
        ELSE
            SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF OBJECT_ID('energy.dbo.LS_005_RMS', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_RMS bulunamadi. Once 04_STATION.sql calistirin.', 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'me_factor_value kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER VIEW dbo.VW_MIG_LS005_FUID_SOURCE
AS
SELECT
    s.ID                                                            AS ABYS_ID,
    s.HIGHER_HEATING_VALUE                                          AS VAL,
    energy.dbo.FN_SAFE_DT(CAST(s.ACTION_DATE AS DATETIME2))         AS DATE_,
    r.LREF                                                          AS RMSID,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.CREATED_USER_ID AS BIGINT) AS INT)) AS ADDUSER,
    ISNULL(
        energy.dbo.FN_SAFE_DT(CAST(s.CREATED_TIMESTAMP AS DATETIME2)),
        GETDATE()
    )                                                               AS ADDDATE
FROM izgazMGR.dbo.me_factor_value s
LEFT JOIN energy.dbo.LS_005_RMS r
    ON r.DEFN = CONVERT(NVARCHAR(50), s.SERVICE_BOX_ID);
GO

IF OBJECT_ID('dbo.SP_MIGRATE_LS005_FUID', 'P') IS NOT NULL
    EXEC sys.sp_refreshsqlmodule N'dbo.SP_MIGRATE_LS005_FUID';
GO

EXEC dbo.SP_MIG_LS005_FUID_VALIDATE_SOURCE @RaiseOnMissing = 0;
GO

