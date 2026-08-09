/* ============================================================
   SCRIPT_ID : AGR_GUARANTY_STAGING_SETUP
   SCRIPT_NO : 305
   FILE      : 305_AGR_GUARANTY_STAGING__setup.sql
   VERSION   : 1
   ============================================================ */
-- Oracle MIGRATION.LS_AGR_GUARANTY export hedefi.
-- Bu script veri yuklemez; izgazMGR staging semasini hazirlar.
-- Yukleme tamamlandiktan sonra 310_AGR_GUARANTY__setup.sql,
-- _MIG_UID ve MIG_ROW_ID kopru kolonlarini ekler.
--
-- Guvenlik:
--   * Dogru semadaki mevcut tablo ve veriler korunur.
--   * Hatali semadaki BOS tablo yeniden olusturulur.
--   * Hatali semadaki DOLU tablo otomatik silinmez.
-- ============================================================

USE izgazMGR;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE
    @ObjectId INT = OBJECT_ID('dbo.LS_AGR_GUARANTY', 'U'),
    @Missing  NVARCHAR(MAX),
    @RowCount BIGINT;

IF @ObjectId IS NOT NULL
BEGIN
    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('AGRID'), ('GTYPE'), ('RFNO'),
            ('SDATE'), ('EDATE'), ('TOTAL'), ('WD'), ('EXCNR'), ('MUSTTL'),
            ('ADDDATE'), ('ADDUSER'), ('UPDDATE'), ('UPDUSER'),
            ('LOGOREF'), ('BANKREF'), ('BANKACCREF'),
            ('CUSTBNK'), ('CUSTBNKACC'), ('CUSTBNKNO'),
            ('ABYS_REGISTER_ID'), ('ABYS_AGREEMENT_ID'),
            ('ABYS_GL_REF'), ('ABYS_GL_DESC'), ('ABYS_GL_BNK_DESC'),
            ('ABYS_GL_BANK_REF'), ('ABYS_GL_STATUS'),
            ('CONVERTED_TO_CASH'), ('REFUND')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, N', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM sys.columns c
        WHERE c.object_id = @ObjectId
          AND c.name = r.COL_NAME
    );

    IF NULLIF(@Missing, N'') IS NOT NULL
    BEGIN
        SELECT @RowCount = COALESCE(SUM(p.rows), 0)
        FROM sys.partitions p
        WHERE p.object_id = @ObjectId
          AND p.index_id IN (0, 1);

        IF @RowCount > 0
        BEGIN
            DECLARE @ErrorMessage NVARCHAR(2048) =
                N'LS_AGR_GUARANTY hatali semada ve '
                + CONVERT(NVARCHAR(30), @RowCount)
                + N' satir iceriyor. Veri kaybini onlemek icin tablo silinmedi. Eksik kolonlar: '
                + @Missing;
            THROW 50000, @ErrorMessage, 1;
        END;

        DROP TABLE dbo.LS_AGR_GUARANTY;
        SET @ObjectId = NULL;
        PRINT N'Bos ve hatali LS_AGR_GUARANTY tablosu yeniden olusturulacak.';
    END;
END;

IF @ObjectId IS NULL
BEGIN
    CREATE TABLE dbo.LS_AGR_GUARANTY (
        AGRID              DECIMAL(22, 0) NULL,
        GTYPE              INT NULL,
        RFNO               NVARCHAR(100) NULL,
        SDATE              DATETIME2(7) NULL,
        EDATE              DATETIME2(7) NULL,
        TOTAL              DECIMAL(28, 8) NULL,
        WD                 INT NULL,
        EXCNR              INT NULL,
        MUSTTL             DECIMAL(28, 8) NULL,
        ADDDATE            DATETIME2(7) NULL,
        ADDUSER            DECIMAL(22, 0) NULL,
        UPDDATE            DATETIME2(7) NULL,
        UPDUSER            DECIMAL(22, 0) NULL,
        LOGOREF            DECIMAL(22, 0) NULL,
        BANKREF            DECIMAL(22, 0) NULL,
        BANKACCREF         DECIMAL(22, 0) NULL,
        CUSTBNK            NVARCHAR(200) NULL,
        CUSTBNKACC         NVARCHAR(200) NULL,
        CUSTBNKNO          NVARCHAR(100) NULL,
        ABYS_REGISTER_ID   DECIMAL(22, 0) NULL,
        ABYS_AGREEMENT_ID  DECIMAL(22, 0) NULL,
        ABYS_GL_REF        DECIMAL(22, 0) NULL,
        ABYS_GL_DESC       NVARCHAR(4000) NULL,
        ABYS_GL_BNK_DESC   NVARCHAR(4000) NULL,
        ABYS_GL_BANK_REF   DECIMAL(22, 0) NULL,
        ABYS_GL_STATUS     DECIMAL(22, 0) NULL,
        CONVERTED_TO_CASH  BIT NULL,
        REFUND             BIT NULL
    );

    PRINT N'izgazMGR.dbo.LS_AGR_GUARANTY olusturuldu.';
END
ELSE
BEGIN
    PRINT N'izgazMGR.dbo.LS_AGR_GUARANTY zaten dogru semada; degisiklik yapilmadi.';
END;
GO

SELECT
    c.column_id,
    c.name AS COLUMN_NAME,
    TYPE_NAME(c.user_type_id) AS DATA_TYPE,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable
FROM sys.columns c
WHERE c.object_id = OBJECT_ID('dbo.LS_AGR_GUARANTY', 'U')
ORDER BY c.column_id;
GO
