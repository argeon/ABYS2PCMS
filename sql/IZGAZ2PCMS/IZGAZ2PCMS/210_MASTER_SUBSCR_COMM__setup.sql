/* ============================================================
   SCRIPT_ID : MASTER_SUBSCR_COMM_SETUP
   SCRIPT_NO : 210
   FILE      : 210_MASTER_SUBSCR_COMM__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- CS_REGISTER_COMMUNICATION → LS_005_SUBSCRIBER_COMMUNICATION
-- Kolon eşlemesi:
--   LREF          ← ID
--   SUBSCRIBER_ID ← REGISTER_ID
--   ADDUSER       ← CREATED_USER_ID
--   ADDDATE       ← CREATED_TIMESTAMP
--   UPDUSER       ← UPDATED_USER_ID
--   UPDDATE       ← UPDATED_TIMESTAMP
-- ============================================================
USE energy;
GO

-- datetimeoffset / datetime2 → datetime (1753–9999 dışı → NULL)
CREATE OR ALTER FUNCTION dbo.FN_SAFE_DT (@DT DATETIME2)
RETURNS DATETIME
AS
BEGIN
    RETURN CASE
        WHEN @DT IS NULL                     THEN NULL
        WHEN @DT < '1753-01-01 00:00:00.000' THEN NULL
        WHEN @DT > '9999-12-31 23:59:59.997' THEN NULL
        ELSE CAST(@DT AS DATETIME)
    END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_REG_COMM_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('ID'), ('REGISTER_ID'), ('COMMUNICATION_TYPE'),
            ('PHONE_AREA_CODE_ID'), ('PHONE_EXTENSION'), ('COMMUNICATION_TEXT'),
            ('DESCRIPTION'), ('IS_DEFAULT'),
            ('CREATED_USER_ID'), ('CREATED_TIMESTAMP'),
            ('UPDATED_USER_ID'), ('UPDATED_TIMESTAMP'),
            ('IS_ACTIVE'), ('IS_VERIFIED'), ('VERIFY_CODE'), ('VERIFY_DATE')
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
          AND t.name = 'CS_REGISTER_COMMUNICATION'
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'CS_REGISTER_COMMUNICATION eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1
            RAISERROR(@Msg, 16, 1);
        ELSE
            SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF NOT EXISTS (
        SELECT 1 FROM izgazMGR.sys.tables t
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'CS_REGISTER_REGISTER_TYPE'
    )
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('CS_REGISTER_REGISTER_TYPE tablosu bulunamadi.', 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'CS_REGISTER_COMMUNICATION kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

