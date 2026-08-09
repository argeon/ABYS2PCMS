/* ============================================================
   SCRIPT_ID : AGR_BNK_MUTABAKAT_SETUP
   SCRIPT_NO : 364
   FILE      : 364_AGR_BNK_MUTABAKAT__setup.sql
   VERSION   : 4
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.LS_BANK_CONFIRM
--   → energy.dbo.LS_BNK_MUTABAKAT_DETAY
--
-- Guvenlik:
--   Yalnizca FIRMA_ID = 5 (Izgaz) yazilir / silinir.
--   Diger firmalarin native satirlari dokunulmaz.
--   BANK_REF mutlaka LS_BANK.LREF olmali (pre + post gate).
--
-- Kolon eslemesi:
--   ID                  : IDENTITY (yeni) — native satir olabilir
--   ABYS_ID             : kaynak ID (kopru)
--   FIRMA_ID            : 5 (Izgaz / 005)
--   BANK_REF            : LS_BANK.LREF WHERE ABYS_ID = BANK_ID
--   MUTABAKAT_TARIHI    : ACTION_DATE
--   TAHSILAT_ADET       : PAYMENT_COUNT
--   TAHSILAT_TUTAR      : PAYMENT_AMOUNT
--   IPTAL_ADET          : CANCELLATION_COUNT
--   IPTAL_TUTAR         : CANCELLATION_AMOUNT
--   TRAN_CODE           : SERVICE_RECEIPT_NUMBER (LEFT 15)
--   MUTABAKAT_DURUMU    : PCMS sozluk (ABYS APPROVAL_STATUS map)
--                         ABYS 2=APPROVED → 1 Basarili
--                         ABYS 3=REJECTED → 0 Basarisiz
--                         ABYS 1=NEW      → 3 Kayit Yok (tamamlanmamis)
--   ABYS_APPROVAL_STATUS: kaynak APPROVAL_STATUS (1=NEW;2=APPROVED;3=REJECTED)
--   CREATED             : CREATED_USER_ID + 10000
--   CREATED_TIMESTAMP   : CREATED_TIMESTAMP
--   UPDATED             : UPDATED_USER_ID + 10000
--   UPDATED_TIMESTAMP   : UPDATED_TIMESTAMP
--   AUTO_PAYMENT_COUNT  : AUTO_PAYMENT_COUNT (yeni kolon)
--   AUTO_PAYMENT_AMOUNT : AUTO_PAYMENT_AMOUNT (yeni kolon)
--   SYS_TAHSILAT_TUTAR  : aktarilmaz (NULL)
--   SYS_TAHSILAT_ADET   : aktarilmaz (NULL)
--   SYS_IPTAL_ADET      : aktarilmaz (NULL)
--   SYS_IPTAL_TUTAR     : aktarilmaz (NULL)
--
-- Onkosul : 121_REF_BANK__migrate.sql (LS_BANK.ABYS_ID dolu)
-- Oracle  : oracleCTAS3007/LS_BANK_CONFIRM.sql → dump LS_BANK_CONFIRM
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_BNK_MUTABAKAT_DETAY bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- Kaynak AUTO_PAYMENT kolonlari (SYS_* aktarilmaz)
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY')
      AND name = 'AUTO_PAYMENT_COUNT'
)
    ALTER TABLE energy.dbo.LS_BNK_MUTABAKAT_DETAY ADD AUTO_PAYMENT_COUNT INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY')
      AND name = 'AUTO_PAYMENT_AMOUNT'
)
    ALTER TABLE energy.dbo.LS_BNK_MUTABAKAT_DETAY ADD AUTO_PAYMENT_AMOUNT FLOAT NULL;
GO

-- ------------------------------------------------------------
-- ABYS_ kopru kolonlari
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY')
      AND name = 'ABYS_ID'
)
    ALTER TABLE energy.dbo.LS_BNK_MUTABAKAT_DETAY ADD ABYS_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY')
      AND name = 'ABYS_BANK_ID'
)
    ALTER TABLE energy.dbo.LS_BNK_MUTABAKAT_DETAY ADD ABYS_BANK_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY')
      AND name = 'ABYS_CASH_ID'
)
    ALTER TABLE energy.dbo.LS_BNK_MUTABAKAT_DETAY ADD ABYS_CASH_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY')
      AND name = 'ABYS_TYPE'
)
    ALTER TABLE energy.dbo.LS_BNK_MUTABAKAT_DETAY ADD ABYS_TYPE INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY')
      AND name = 'ABYS_APPROVAL_STATUS'
)
    ALTER TABLE energy.dbo.LS_BNK_MUTABAKAT_DETAY ADD ABYS_APPROVAL_STATUS INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY')
      AND name = 'ABYS_APPROVAL_USER_ID'
)
    ALTER TABLE energy.dbo.LS_BNK_MUTABAKAT_DETAY ADD ABYS_APPROVAL_USER_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY')
      AND name = 'ABYS_CREATED_USER_ID'
)
    ALTER TABLE energy.dbo.LS_BNK_MUTABAKAT_DETAY ADD ABYS_CREATED_USER_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY')
      AND name = 'ABYS_UPDATED_USER_ID'
)
    ALTER TABLE energy.dbo.LS_BNK_MUTABAKAT_DETAY ADD ABYS_UPDATED_USER_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY')
      AND name = 'UX_LS_BNK_MUTABAKAT_DETAY_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_BNK_MUTABAKAT_DETAY_ABYS_ID
        ON energy.dbo.LS_BNK_MUTABAKAT_DETAY (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Validate
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_BNK_MUTABAKAT_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_BANK_CONFIRM', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_BANK_CONFIRM bulunamadi. Once Oracle CTAS + dump calistirin.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('ID'),('BANK_ID'),('CASH_ID'),('ACTION_DATE'),
            ('PAYMENT_COUNT'),('PAYMENT_AMOUNT'),
            ('CANCELLATION_COUNT'),('CANCELLATION_AMOUNT'),
            ('APPROVAL_STATUS'),('APPROVAL_USER_ID'),
            ('CREATED_USER_ID'),('CREATED_TIMESTAMP'),
            ('UPDATED_USER_ID'),('UPDATED_TIMESTAMP'),
            ('AUTO_PAYMENT_COUNT'),('AUTO_PAYMENT_AMOUNT'),
            ('TYPE'),('SERVICE_RECEIPT_NUMBER')
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
          AND t.name = 'LS_BANK_CONFIRM'
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_BANK_CONFIRM eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        ELSE SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_BANK_CONFIRM kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_BNK_MUTABAKAT_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_BNK_MUTABAKAT_DETAY bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('ID'),('FIRMA_ID'),('BANK_REF'),('MUTABAKAT_TARIHI'),
            ('TAHSILAT_ADET'),('TAHSILAT_TUTAR'),
            ('IPTAL_ADET'),('IPTAL_TUTAR'),
            ('TRAN_CODE'),('MUTABAKAT_DURUMU'),
            ('CREATED'),('CREATED_TIMESTAMP'),
            ('UPDATED'),('UPDATED_TIMESTAMP'),
            ('AUTO_PAYMENT_COUNT'),('AUTO_PAYMENT_AMOUNT'),
            ('SYS_TAHSILAT_TUTAR'),('SYS_TAHSILAT_ADET'),
            ('SYS_IPTAL_ADET'),('SYS_IPTAL_TUTAR'),
            ('ABYS_ID'),('ABYS_BANK_ID'),('ABYS_CASH_ID'),
            ('ABYS_TYPE'),('ABYS_APPROVAL_STATUS'),('ABYS_APPROVAL_USER_ID'),
            ('ABYS_CREATED_USER_ID'),('ABYS_UPDATED_USER_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_BNK_MUTABAKAT_DETAY')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_BNK_MUTABAKAT_DETAY eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        ELSE SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF OBJECT_ID('dbo.LS_BANK', 'U') IS NULL
       OR COL_LENGTH('dbo.LS_BANK', 'ABYS_ID') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('LS_BANK.ABYS_ID yok. Once 121_REF_BANK__migrate.sql calistirin.', 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_BNK_MUTABAKAT_DETAY hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Banka LREF dogrulama (kaynak BANK_ID → LS_BANK.LREF)
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_BNK_MUTABAKAT_VALIDATE_BANK_LREF
    @FirmaId        INT = 5,
    @RaiseOnMissing BIT = 1,
    @Phase          VARCHAR(20) = 'PRE'  -- PRE | POST
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @NullBankSrc   BIGINT = 0,
        @OrphanBankSrc BIGINT = 0,
        @NullBankTgt   BIGINT = 0,
        @OrphanBankTgt BIGINT = 0,
        @Msg           NVARCHAR(4000);

    IF @Phase IN ('PRE', 'BOTH')
    BEGIN
        IF OBJECT_ID('izgazMGR.dbo.LS_BANK_CONFIRM', 'U') IS NOT NULL
        BEGIN
            SELECT @NullBankSrc = COUNT_BIG(*)
            FROM izgazMGR.dbo.LS_BANK_CONFIRM s
            WHERE s.ID BETWEEN 1 AND 2147483647
              AND s.BANK_ID IS NULL;

            SELECT @OrphanBankSrc = COUNT_BIG(*)
            FROM izgazMGR.dbo.LS_BANK_CONFIRM s
            WHERE s.ID BETWEEN 1 AND 2147483647
              AND s.BANK_ID IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM energy.dbo.LS_BANK b
                  WHERE b.ABYS_ID = CAST(s.BANK_ID AS INT)
              );
        END
    END

    IF @Phase IN ('POST', 'BOTH')
    BEGIN
        SELECT @NullBankTgt = COUNT_BIG(*)
        FROM energy.dbo.LS_BNK_MUTABAKAT_DETAY t
        WHERE t.ABYS_ID IS NOT NULL
          AND t.FIRMA_ID = @FirmaId
          AND t.BANK_REF IS NULL;

        SELECT @OrphanBankTgt = COUNT_BIG(*)
        FROM energy.dbo.LS_BNK_MUTABAKAT_DETAY t
        WHERE t.ABYS_ID IS NOT NULL
          AND t.FIRMA_ID = @FirmaId
          AND t.BANK_REF IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM energy.dbo.LS_BANK b
              WHERE b.LREF = t.BANK_REF
          );
    END

    IF @NullBankSrc > 0 OR @OrphanBankSrc > 0 OR @NullBankTgt > 0 OR @OrphanBankTgt > 0
    BEGIN
        SET @Msg = N'BANK LREF dogrulama FAIL'
            + N' | PRE null_BANK_ID=' + CAST(@NullBankSrc AS NVARCHAR(20))
            + N' orphan_BANK_ID=' + CAST(@OrphanBankSrc AS NVARCHAR(20))
            + N' | POST null_BANK_REF=' + CAST(@NullBankTgt AS NVARCHAR(20))
            + N' orphan_BANK_REF=' + CAST(@OrphanBankTgt AS NVARCHAR(20))
            + N' | Once 121_REF_BANK__migrate tamamlayin / map eksik bankalari ekleyin.';

        IF @RaiseOnMissing = 1
            RAISERROR(@Msg, 16, 1);
        ELSE
            SELECT @Msg AS VALIDATION_MESSAGE,
                   @NullBankSrc AS PRE_NULL_BANK_ID,
                   @OrphanBankSrc AS PRE_ORPHAN_BANK_ID,
                   @NullBankTgt AS POST_NULL_BANK_REF,
                   @OrphanBankTgt AS POST_ORPHAN_BANK_REF;

        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'BANK LREF dogrulama OK (' + @Phase + N')' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_BNK_MUTABAKAT_VALIDATE_ALL
    @RaiseOnMissing BIT = 1,
    @FirmaId        INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Rc INT;

    EXEC @Rc = dbo.SP_MIG_BNK_MUTABAKAT_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_BNK_MUTABAKAT_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_BNK_MUTABAKAT_VALIDATE_BANK_LREF
        @FirmaId = @FirmaId,
        @RaiseOnMissing = @RaiseOnMissing,
        @Phase = 'PRE';
    IF @Rc <> 0 RETURN @Rc;

    RETURN 0;
END
GO

PRINT '364_AGR_BNK_MUTABAKAT__setup OK';
GO
