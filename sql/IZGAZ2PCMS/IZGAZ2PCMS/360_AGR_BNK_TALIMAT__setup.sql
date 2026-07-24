/* ============================================================
   SCRIPT_ID : AGR_BNK_TALIMAT_SETUP
   SCRIPT_NO : 360
   FILE      : 360_AGR_BNK_TALIMAT__setup.sql
   VERSION   : 3
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.CS_AGREEMENT_AUTO_PAYMENT_LOG
--   → energy.dbo.LS_BNK_TALIMAT
--
-- ID      : IDENTITY (yeni) — native satır olabilir
-- ABYS_ID : kaynak ID (köprü)
-- FIRMA_KODU : '005' (migrate)
-- BANKA_KODU : FN_MIG_RESOLVE_BANK_LREF(BANK_ID) → LS_BANK.LREF
-- Önkoşul : 120/121 bank bridge
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_BNK_TALIMAT', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_BNK_TALIMAT bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- ABYS_ kopru kolonlari
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_TALIMAT')
      AND name = 'ABYS_ID'
)
    ALTER TABLE energy.dbo.LS_BNK_TALIMAT ADD ABYS_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_TALIMAT')
      AND name = 'ABYS_AGREEMENT_ID'
)
    ALTER TABLE energy.dbo.LS_BNK_TALIMAT ADD ABYS_AGREEMENT_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_TALIMAT')
      AND name = 'ABYS_BANK_ID'
)
    ALTER TABLE energy.dbo.LS_BNK_TALIMAT ADD ABYS_BANK_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_TALIMAT')
      AND name = 'ABYS_CREATED_USER_ID'
)
    ALTER TABLE energy.dbo.LS_BNK_TALIMAT ADD ABYS_CREATED_USER_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_TALIMAT')
      AND name = 'ABYS_CANCEL_USER_ID'
)
    ALTER TABLE energy.dbo.LS_BNK_TALIMAT ADD ABYS_CANCEL_USER_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_TALIMAT')
      AND name = 'UX_LS_BNK_TALIMAT_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_BNK_TALIMAT_ABYS_ID
        ON energy.dbo.LS_BNK_TALIMAT (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_TALIMAT')
      AND name = 'IX_LS_BNK_TALIMAT_SOZLESME_HESABI'
)
    CREATE NONCLUSTERED INDEX IX_LS_BNK_TALIMAT_SOZLESME_HESABI
        ON energy.dbo.LS_BNK_TALIMAT (SOZLESME_HESABI, FIRMA_KODU)
        INCLUDE (IS_ACTIVE, BANKA_KODU, TALIMAT_TARIHI, IPTAL_TARIHI);
GO

-- ------------------------------------------------------------
-- Validate
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_BNK_TALIMAT_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.CS_AGREEMENT_AUTO_PAYMENT_LOG', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.CS_AGREEMENT_AUTO_PAYMENT_LOG bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('ID'),('AGREEMENT_ID'),('BANK_ID'),
            ('INSTRUCTION_DATE'),('CANCEL_DATE'),('DESCRIPTION'),
            ('CREATED_USER_ID'),('CREATED_TIMESTAMP'),
            ('UPDATED_USER_ID'),('UPDATED_TIMESTAMP'),
            ('VERSION'),('CANCEL_USER_ID')
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
          AND t.name = 'CS_AGREEMENT_AUTO_PAYMENT_LOG'
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'CS_AGREEMENT_AUTO_PAYMENT_LOG eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        ELSE SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF OBJECT_ID('izgazMGR.dbo.CS_AGREEMENT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.CS_AGREEMENT bulunamadi (TESISAT/ABONE icin gerekli).', 16, 1);
        RETURN 1;
    END

    IF COL_LENGTH('izgazMGR.dbo.CS_AGREEMENT', 'BENEFITED_REGISTER_ID') IS NULL
       OR COL_LENGTH('izgazMGR.dbo.CS_AGREEMENT', 'INSTALLATION_ID') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('CS_AGREEMENT: BENEFITED_REGISTER_ID / INSTALLATION_ID eksik.', 16, 1);
        RETURN 1;
    END

    IF OBJECT_ID('izgazMGR.dbo.CS_INSTALLATION', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.CS_INSTALLATION bulunamadi (TESISAT_NUMARASI icin gerekli).', 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'CS_AGREEMENT_AUTO_PAYMENT_LOG kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_BNK_TALIMAT_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_BNK_TALIMAT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_BNK_TALIMAT bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('ID'),('BANKA_KODU'),('ACIKLAMA'),
            ('SOZLESME_NUMARASI'),('TESISAT_NUMARASI'),('FIRMA_KODU'),
            ('TRAN_CODE'),('IPTAL_KULLANICI_KODU'),
            ('TALIMAT_TARIHI'),('IPTAL_TARIHI'),('IS_ACTIVE'),
            ('UPDATED_TIMESTAMP'),('CREATED_TIMESTAMP'),
            ('ISLEM_KANALI'),('KULLANICI_KODU'),
            ('ABONE_NUMARASI'),('SOZLESME_HESABI'),
            ('ABYS_ID'),('ABYS_AGREEMENT_ID'),('ABYS_BANK_ID'),
            ('ABYS_CREATED_USER_ID'),('ABYS_CANCEL_USER_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_BNK_TALIMAT')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_BNK_TALIMAT eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        ELSE SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF OBJECT_ID('dbo.LS_BANK', 'U') IS NULL
       OR COL_LENGTH('dbo.LS_BANK', 'ABYS_ID') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('LS_BANK.ABYS_ID yok. Once 120/121 bank bridge calistirin.', 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_BNK_TALIMAT hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_BNK_TALIMAT_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Rc INT;

    EXEC @Rc = dbo.SP_MIG_BNK_TALIMAT_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_BNK_TALIMAT_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    RETURN 0;
END
GO

PRINT '360_AGR_BNK_TALIMAT__setup OK';
GO
