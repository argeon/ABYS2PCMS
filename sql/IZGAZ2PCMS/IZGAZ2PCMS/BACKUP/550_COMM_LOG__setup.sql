/* ============================================================
   SCRIPT_ID : COMM_LOG_SETUP
   SCRIPT_NO : 550
   FILE      : 550_COMM_LOG__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.IT_COMMUNICATION_LOG
--   → energy.dbo.LS_COMMUNICATION_LOG
--
-- Hedef tabloda native veri VAR.
-- ABYS_ID = kaynak ID (LREF IDENTITY yeni numara).
-- COMPANY_ID = 5 (migrate).
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_COMMUNICATION_LOG', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_COMMUNICATION_LOG bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- ABYS_ID kopru
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_COMMUNICATION_LOG')
      AND name = 'ABYS_ID'
)
    ALTER TABLE energy.dbo.LS_COMMUNICATION_LOG ADD ABYS_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_COMMUNICATION_LOG')
      AND name = 'UX_LS_COMMUNICATION_LOG_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_COMMUNICATION_LOG_ABYS_ID
        ON energy.dbo.LS_COMMUNICATION_LOG (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Validate
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_COMM_LOG_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.IT_COMMUNICATION_LOG', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.IT_COMMUNICATION_LOG bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('ID'),('COMMUNICATION_TYPE'),('COMMUNICATION_CAUSE'),
            ('RELATIONAL_ID'),('MAIL_ID'),('PHONE_1'),('PHONE_2'),('MOBILE_PHONE'),
            ('REGISTER_ID'),('STARTING_DATE'),('UNIT_TYPE_ID'),('SUB_CODE'),
            ('AGREEMENT_ID'),('APPOINTMENT_DATE'),('TRANSACTION_CODE'),
            ('CALL_NUMBER'),('NOTE'),('CONTENT'),('RESULT'),('STATUS'),
            ('CREATED_USER_ID'),('CREATED_TIMESTAMP'),
            ('UPDATED_USER_ID'),('UPDATED_TIMESTAMP'),('VERSION'),
            ('SHIPPING_STATUS'),('DESCRIPTION'),('SUBMISSION_DATE'),('DELIVERY_DATE'),
            ('SHIPPING_FIRM'),('DUPLICATED_ID'),('PRIORITY'),
            ('IS_UNREACHABLE_CALL'),('CALL_DATE'),('EMAIL'),
            ('DEBT_TRACING_ID'),('PARENT_ID'),('SHIPPING_BARCODE_NO'),
            ('POOL_ID'),('ACCOUNT_ID'),
            ('CANCELLATION_DATE'),('CANCELLATION_USER_ID'),
            ('TOTAL_DEBT'),('DEBT_BILL_COUNT'),
            ('APPROVAL_DATE'),('APPROVAL_USER_ID'),
            ('DOC_ID'),('SMS_PROFILE_ID')
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
          AND t.name = 'IT_COMMUNICATION_LOG'
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'IT_COMMUNICATION_LOG eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        ELSE SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'IT_COMMUNICATION_LOG kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_COMM_LOG_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_COMMUNICATION_LOG', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_COMMUNICATION_LOG bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('GROUP_ID'),('DATA_DATE'),('COMPANY_ID'),
            ('AGREEMENT_ID'),('METER_STATUS_ID'),('REGISTER_ID'),
            ('READING_DATE'),('SEND_DATE'),('DELIVERY_DATE'),
            ('COMMUNICATION_CAUSE'),('COMMUNICATION_SUB_CAUSE'),('COMMUNICATION_TYPE'),
            ('COMMUNICATION_CONTENT'),('GSM_NUMBER'),('DESCRIPTION'),('EMAIL'),
            ('STATUS'),('CREATED_TIMESTAMP'),('CREATED_USER'),
            ('UPDATED_TIMESTAMP'),('UPDATED_USER'),
            ('TRANSACTION_ID'),('RESULT_STATUS_CODE'),('RESULT_STATUS'),
            ('POOL_REF'),('INVOICE_ID'),('ABYS_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_COMMUNICATION_LOG')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_COMMUNICATION_LOG eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        ELSE SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_COMMUNICATION_LOG hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_COMM_LOG_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.SP_MIG_COMM_LOG_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    EXEC dbo.SP_MIG_COMM_LOG_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
END
GO

PRINT '550_COMM_LOG__setup OK';
GO
