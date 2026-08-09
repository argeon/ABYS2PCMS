/* ============================================================
   SCRIPT_ID : OPR_SYNC_CLIENT_SETUP
   SCRIPT_NO : 560
   FILE      : 560_OPR_SYNC_CLIENT__setup.sql
   VERSION   : 2
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.OPR_SYNC_CLIENT
--   → energy.dbo.LS_OPR_SYNC_CLIENT
--
-- Hedef tabloda diger COMPANY_CODE native veri VAR.
-- LREF    : IDENTITY (yeni) — IDENTITY_INSERT kullanilmaz
-- ABYS_ID : kaynak ID
-- COMPANY_CODE ← CORPORATION_ID
-- PRINTER_TYPE ← nvarchar enum adi → smallint ordinal (0..)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_OPR_SYNC_CLIENT', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_OPR_SYNC_CLIENT bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- ABYS_ID kopru
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_OPR_SYNC_CLIENT')
      AND name = 'ABYS_ID'
)
    ALTER TABLE energy.dbo.LS_OPR_SYNC_CLIENT ADD ABYS_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_OPR_SYNC_CLIENT')
      AND name = 'UX_LS_OPR_SYNC_CLIENT_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_OPR_SYNC_CLIENT_ABYS_ID
        ON energy.dbo.LS_OPR_SYNC_CLIENT (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Validate
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_OPR_SYNC_CLIENT_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.OPR_SYNC_CLIENT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.OPR_SYNC_CLIENT bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('ID'),('CORPORATION_ID'),('CODE'),('CLIENT_TYPE'),('SERIAL'),
            ('DESCRIPTION'),('REGISTER_REL_ID'),('LAST_CONNECTION_TIME'),
            ('IS_READING'),('IS_WO_WORK'),('IS_OPR_WORK'),('GSM_NUMBER'),
            ('IS_SEND_MAIL_LOG'),('IS_COLLECT_LOG'),('IS_ACTIVE'),
            ('CREATED_USER_ID'),('CREATED_TIMESTAMP'),
            ('UPDATED_USER_ID'),('UPDATED_TIMESTAMP'),('VERSION'),
            ('PRINTER_TYPE'),('IS_SHOW_FIRST_INDEX'),('IS_DM_DISCOVERY'),
            ('IS_GPS_REQUIRED'),('IS_ADDRESS_UPDATE_REQUIRED'),('IS_ADDRESS_UPDATE'),
            ('BILL_SERIAL'),('LAST_BILL_NUMBER'),('LAST_READING_DATE'),
            ('MINUTE_NUMBER'),('MINUTE_SERIAL'),('IS_EAM'),('IS_SUBSCRIBER_UPDATE')
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
          AND t.name = 'OPR_SYNC_CLIENT'
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'OPR_SYNC_CLIENT eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        ELSE SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'OPR_SYNC_CLIENT kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_OPR_SYNC_CLIENT_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_OPR_SYNC_CLIENT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_OPR_SYNC_CLIENT bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('COMPANY_CODE'),('CODE'),('CLIENT_TYPE'),('SERIAL'),
            ('DESCRIPTION'),('REGISTER_REL_ID'),('SUBSCRIBER_ID'),
            ('LAST_CONNECTION_TIME'),('IS_READING'),('IS_WO_WORK'),('IS_OPR_WORK'),
            ('GSM_NUMBER'),('IS_SEND_MAIL_LOG'),('IS_COLLECT_LOG'),('PRINTER_TYPE'),
            ('IS_SHOW_FIRST_INDEX'),('IS_DM_DISCOVERY'),('IS_GPS_REQUIRED'),
            ('IS_ADDRESS_UPDATE_REQUIRED'),('IS_ADDRESS_UPDATE'),
            ('BILL_SERIAL'),('LAST_BILL_NUMBER'),('LAST_READING_DATE'),
            ('MINUTE_NUMBER'),('MINUTE_SERIAL'),('IS_EAM'),('IS_SUBSCRIBER_UPDATE'),
            ('REVISION_LIMIT_PER_READING'),('REVISION_LIMIT_GENERAL'),
            ('READING_TYPE'),('SYNC_PERIOD'),('SYNC_TYPE'),('SYNC_ITEM_COUNT'),
            ('ALWAYS_SEND'),('IS_ACTIVE'),
            ('CREATED_USER_ID'),('CREATED_TIMESTAMP'),
            ('UPDATED_USER_ID'),('UPDATED_TIMESTAMP'),
            ('DELETED_USER_ID'),('DELETED_TIMESTAMP'),('IS_DELETED'),('VERSION'),
            ('ABYS_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_OPR_SYNC_CLIENT')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_OPR_SYNC_CLIENT eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        ELSE SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_OPR_SYNC_CLIENT hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_OPR_SYNC_CLIENT_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.SP_MIG_OPR_SYNC_CLIENT_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    EXEC dbo.SP_MIG_OPR_SYNC_CLIENT_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
END
GO
