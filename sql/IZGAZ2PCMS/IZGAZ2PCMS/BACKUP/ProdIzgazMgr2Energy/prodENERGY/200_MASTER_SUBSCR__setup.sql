/* ============================================================
   SCRIPT_ID : MASTER_SUBSCR_SETUP
   SCRIPT_NO : 200
   FILE      : 200_MASTER_SUBSCR__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- CS_REGISTER → LS_005_SUBSCR / LS_005_FIRM — kaynak hazırlık
-- Mirror tabloya kalıcı kolon eklenmez; FN_SAFE_SMALLDT_USR ile tarih güvenliği.
-- ============================================================
USE energy;
GO

-- datetime2 → smalldatetime (1900–2079 dışı → NULL)
-- IT_USER setup ile aynı; CS_REGISTER deploy tek başına da yeterli olsun.
CREATE OR ALTER FUNCTION dbo.FN_SAFE_SMALLDT_USR (@DT DATETIME2)
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
-- SP_MIG_CS_REGISTER_VALIDATE_SOURCE
-- Deploy / çalıştırma öncesi zorunlu kaynak kolonlarını doğrular.
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_CS_REGISTER_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('ID'), ('CODE'), ('FIRST_NAME'), ('LAST_NAME'), ('IDENTITY_NUMBER'),
            ('TAX_NUMBER'), ('TAX_OFFICE'), ('CHAMBER_CODE'),
            ('BIRTH_PLACE'), ('BIRTH_DATE'), ('FATHER_NAME'), ('MOTHER_NAME'), ('GENDER'),
            ('IDENTITY_ADDRESS'), ('IDENTITY_CHANGE_DATE'), ('IDENTITY_DISTRICT'),
            ('IDENTITY_FAMILY_ROW_NUMBER'), ('IDENTITY_ISSUE_DATE'), ('IDENTITY_PROVINCE'),
            ('IDENTITY_QUARTER'), ('IDENTITY_QUARTER_ID'), ('IDENTITY_REASON_FOR_ISSUE'),
            ('IDENTITY_REGISTRATION_NUMBER'), ('IDENTITY_ROW_NUMBER'),
            ('IDENTITY_SERIAL'), ('IDENTITY_SERIAL_NUMBER'), ('IDENTITY_VOLUME_NUMBER'),
            ('SOCIAL_SECURITY_NUMBER'), ('DESCRIPTION'),
            ('DELETED_TIMESTAMP'), ('DELETED_USER_ID'), ('IS_LOST'), ('BANKRUPTCY_RECORD'), ('DEAD_DATE'),
            ('IS_E_BILL_CUSTOMER'), ('CUSTOMER_BILL_TYPE'), ('E_BILL_CUSTOMER_DATE'),
            ('IS_COMMINICATION_PERMIT'), ('POOL_ID'),
            ('HAS_EXPRESS_CONSENT'), ('IS_MARKETING_CONSENT_GIVEN'),
            ('IS_SMS_CONTACT_ALLOWED'), ('IS_CALL_CONTACT_ALLOWED'), ('IS_EMAIL_CONTACT_ALLOWED'),
            ('CREATED_USER_ID'), ('CREATED_TIMESTAMP'), ('UPDATED_USER_ID'), ('UPDATED_TIMESTAMP')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'CS_REGISTER' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'CS_REGISTER eksik kolonlar: ' + @Missing;
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
        SELECT N'CS_REGISTER kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

