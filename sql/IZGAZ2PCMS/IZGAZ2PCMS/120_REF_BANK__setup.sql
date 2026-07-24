/* ============================================================
   SCRIPT_ID : REF_BANK_SETUP
   SCRIPT_NO : 120
   FILE      : 120_REF_BANK__setup.sql
   VERSION   : 1
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================
-- LS_BANK — ABYS köprüsü ve eşleme master tablosu
--
-- Kaynak: MIG_LS_BANK_MAP (Excel / iş birimi eşleme listesi)
--   ACTION_TYPE = 'MAP'    → mevcut LS_BANK.LREF satırına ABYS_ID yaz
--   ACTION_TYPE = 'INSERT' → yeni LS_BANK satırı (IDENTITY LREF)
--
-- Downstream: FN_MIG_RESOLVE_BANK_LREF / VW_MIG_LS_BANK_RESOLVED
-- Orphan FK kontrolleri proje sonunda (35_ls_bank_check_queries.sql)
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- Hedef köprü kolonları
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BANK') AND name = 'ABYS_ID'
)
    ALTER TABLE energy.dbo.LS_BANK ADD ABYS_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BANK') AND name = 'ABYS_CODE'
)
    ALTER TABLE energy.dbo.LS_BANK ADD ABYS_CODE NVARCHAR(20) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BANK') AND name = 'IX_LS_BANK_ABYS_ID'
)
    DROP INDEX IX_LS_BANK_ABYS_ID ON energy.dbo.LS_BANK;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BANK') AND name = 'UX_LS_BANK_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_BANK_ABYS_ID
        ON energy.dbo.LS_BANK (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_BANK') AND name = 'IX_LS_BANK_ABYS_ID'
)
    CREATE NONCLUSTERED INDEX IX_LS_BANK_ABYS_ID
        ON energy.dbo.LS_BANK (ABYS_ID) INCLUDE (LREF, DEFN, ISACTIVE);
GO

-- ------------------------------------------------------------
-- Eşleme master (Excel: ABYS_BANK_ID, ABYS_BANK_CODE, DEFN,
-- ABYS_DESCRIPTION, IS_ACTIVE, DURUM, PCMS MAP)
-- ------------------------------------------------------------
IF OBJECT_ID('energy.dbo.MIG_LS_BANK_MAP', 'U') IS NULL
BEGIN
    CREATE TABLE energy.dbo.MIG_LS_BANK_MAP
    (
        ABYS_BANK_ID     INT            NOT NULL,
        ABYS_BANK_CODE   NVARCHAR(20)   NULL,
        DEFN             NVARCHAR(100)  NOT NULL,
        ABYS_DESCRIPTION NVARCHAR(500)  NULL,
        IS_ACTIVE        BIT            NOT NULL CONSTRAINT DF_MIG_LS_BANK_MAP_IS_ACTIVE DEFAULT ((1)),
        ACTION_TYPE      CHAR(6)        NOT NULL,
        PCMS_LREF        INT            NULL,
        CONSTRAINT PK_MIG_LS_BANK_MAP PRIMARY KEY (ABYS_BANK_ID),
        CONSTRAINT CK_MIG_LS_BANK_MAP_ACTION
            CHECK (ACTION_TYPE IN ('MAP', 'INSERT')),
        CONSTRAINT CK_MIG_LS_BANK_MAP_PCMS
            CHECK (
                (ACTION_TYPE = 'MAP'    AND PCMS_LREF IS NOT NULL)
             OR (ACTION_TYPE = 'INSERT' AND PCMS_LREF IS NULL)
            )
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.MIG_LS_BANK_MAP')
      AND name = 'UX_MIG_LS_BANK_MAP_PCMS_LREF'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_MIG_LS_BANK_MAP_PCMS_LREF
        ON energy.dbo.MIG_LS_BANK_MAP (PCMS_LREF)
        WHERE ACTION_TYPE = 'MAP' AND PCMS_LREF IS NOT NULL;
GO

-- ------------------------------------------------------------
-- ABYS banka ID → PCMS LS_BANK.LREF
-- ------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.FN_MIG_RESOLVE_BANK_LREF (@AbysBankId INT)
RETURNS INT
AS
BEGIN
    IF @AbysBankId IS NULL
        RETURN NULL;

    RETURN (
        SELECT TOP (1) b.LREF
        FROM energy.dbo.LS_BANK b
        WHERE b.ABYS_ID = @AbysBankId
        ORDER BY b.LREF
    );
END
GO

-- ------------------------------------------------------------
-- Eşleme + çözümlenmiş LREF (insert / wiring view'ları için)
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.VW_MIG_LS_BANK_RESOLVED
AS
SELECT
    m.ABYS_BANK_ID,
    m.ABYS_BANK_CODE,
    m.DEFN,
    m.ABYS_DESCRIPTION,
    m.IS_ACTIVE,
    m.ACTION_TYPE,
    m.PCMS_LREF                                                     AS MAP_PCMS_LREF,
    CASE
        WHEN m.ACTION_TYPE = 'MAP'    THEN m.PCMS_LREF
        WHEN m.ACTION_TYPE = 'INSERT'   THEN b_ins.LREF
    END                                                             AS RESOLVED_LREF,
    b_map.LREF                                                      AS MAP_TARGET_EXISTS,
    b_ins.LREF                                                      AS INSERT_TARGET_EXISTS,
    CASE
        WHEN m.ACTION_TYPE = 'MAP' AND b_map.LREF IS NULL THEN 'MAP_PCMS_LREF_MISSING'
        WHEN m.ACTION_TYPE = 'MAP' AND b_map.ABYS_ID IS NOT NULL
             AND b_map.ABYS_ID <> m.ABYS_BANK_ID              THEN 'MAP_PCMS_ALREADY_BRIDGED'
        WHEN m.ACTION_TYPE = 'INSERT' AND b_ins.LREF IS NOT NULL THEN 'INSERT_ALREADY_DONE'
        ELSE 'OK'
    END                                                             AS MAP_STATUS
FROM energy.dbo.MIG_LS_BANK_MAP m
LEFT JOIN energy.dbo.LS_BANK b_map
    ON b_map.LREF = m.PCMS_LREF
   AND m.ACTION_TYPE = 'MAP'
LEFT JOIN energy.dbo.LS_BANK b_ins
    ON b_ins.ABYS_ID = m.ABYS_BANK_ID
   AND m.ACTION_TYPE = 'INSERT';
GO

-- ------------------------------------------------------------
-- Aktarım öncesi doğrulama (bloklayıcı — orphan FK değil)
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_LS_BANK_VALIDATE_MAP
    @RaiseOnError BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Errors NVARCHAR(MAX) = N'';

    IF NOT EXISTS (SELECT 1 FROM energy.dbo.MIG_LS_BANK_MAP)
    BEGIN
        SET @Errors = @Errors + N'MIG_LS_BANK_MAP bos; once Excel verisini yukleyin.' + CHAR(13) + CHAR(10);
    END

    IF EXISTS (
        SELECT 1 FROM energy.dbo.MIG_LS_BANK_MAP
        GROUP BY ABYS_BANK_ID HAVING COUNT(*) > 1
    )
        SET @Errors = @Errors + N'MIG_LS_BANK_MAP icinde cift ABYS_BANK_ID var.' + CHAR(13) + CHAR(10);

    IF EXISTS (
        SELECT 1 FROM energy.dbo.MIG_LS_BANK_MAP
        WHERE ACTION_TYPE = 'MAP'
        GROUP BY PCMS_LREF HAVING COUNT(*) > 1
    )
        SET @Errors = @Errors + N'MIG_LS_BANK_MAP icinde cift PCMS_LREF (MAP) var.' + CHAR(13) + CHAR(10);

    DECLARE
        @MissingLref NVARCHAR(MAX),
        @Conflict    NVARCHAR(MAX);

    SELECT @MissingLref = STRING_AGG(
        N'MAP hedefi yok LREF=' + CAST(m.PCMS_LREF AS NVARCHAR(20))
        + N' ABYS=' + CAST(m.ABYS_BANK_ID AS NVARCHAR(20)),
        CHAR(13) + CHAR(10)
    )
    FROM energy.dbo.MIG_LS_BANK_MAP m
    LEFT JOIN energy.dbo.LS_BANK b ON b.LREF = m.PCMS_LREF
    WHERE m.ACTION_TYPE = 'MAP'
      AND b.LREF IS NULL;

    IF @MissingLref IS NOT NULL
        SET @Errors = @Errors + @MissingLref + CHAR(13) + CHAR(10);

    SELECT @Conflict = STRING_AGG(
        N'MAP kopru cakismasi LREF=' + CAST(b.LREF AS NVARCHAR(20))
        + N' mevcut ABYS=' + CAST(b.ABYS_ID AS NVARCHAR(20))
        + N' yeni ABYS=' + CAST(m.ABYS_BANK_ID AS NVARCHAR(20)),
        CHAR(13) + CHAR(10)
    )
    FROM energy.dbo.MIG_LS_BANK_MAP m
    INNER JOIN energy.dbo.LS_BANK b ON b.LREF = m.PCMS_LREF
    WHERE m.ACTION_TYPE = 'MAP'
      AND b.ABYS_ID IS NOT NULL
      AND b.ABYS_ID <> m.ABYS_BANK_ID;

    IF @Conflict IS NOT NULL
        SET @Errors = @Errors + @Conflict + CHAR(13) + CHAR(10);

    IF @Errors <> N''
    BEGIN
        IF @RaiseOnError = 1
            RAISERROR(@Errors, 16, 1);
        ELSE
            SELECT @Errors AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF @RaiseOnError = 0
        SELECT N'LS_BANK map dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Excel kolonları → MIG_LS_BANK_MAP upsert (tek satir)
-- DURUM: 'Map' | 'Yeni Eklenecek'
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_LS_BANK_MAP_UPSERT
    @AbysBankId      INT,
    @AbysBankCode    NVARCHAR(20)  = NULL,
    @Defn            NVARCHAR(100),
    @AbysDescription NVARCHAR(500) = NULL,
    @IsActive        BIT,
    @Durum           NVARCHAR(20),
    @PcmsLref        INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ActionType CHAR(6);

    SET @Durum = UPPER(LTRIM(RTRIM(@Durum)));

    SET @ActionType = CASE
        WHEN @Durum IN (N'MAP', N'M') THEN 'MAP'
        WHEN @Durum IN (N'YENI EKLENECEK', N'YENİ EKLENECEK', N'INSERT', N'YENI') THEN 'INSERT'
        ELSE NULL
    END;

    IF @ActionType IS NULL
    BEGIN
        RAISERROR('Gecersiz DURUM: %s (Map veya Yeni Eklenecek bekleniyor)', 16, 1, @Durum);
        RETURN 1;
    END

    IF @ActionType = 'MAP' AND @PcmsLref IS NULL
    BEGIN
        RAISERROR('MAP satiri icin PCMS_LREF zorunlu. ABYS_BANK_ID=%d', 16, 1, @AbysBankId);
        RETURN 1;
    END

    IF @ActionType = 'INSERT'
        SET @PcmsLref = NULL;

    MERGE energy.dbo.MIG_LS_BANK_MAP AS t
    USING (
        SELECT
            @AbysBankId      AS ABYS_BANK_ID,
            @AbysBankCode    AS ABYS_BANK_CODE,
            @Defn            AS DEFN,
            @AbysDescription AS ABYS_DESCRIPTION,
            @IsActive        AS IS_ACTIVE,
            @ActionType      AS ACTION_TYPE,
            @PcmsLref        AS PCMS_LREF
    ) AS s
    ON t.ABYS_BANK_ID = s.ABYS_BANK_ID
    WHEN MATCHED THEN
        UPDATE SET
            ABYS_BANK_CODE   = s.ABYS_BANK_CODE,
            DEFN             = s.DEFN,
            ABYS_DESCRIPTION = s.ABYS_DESCRIPTION,
            IS_ACTIVE        = s.IS_ACTIVE,
            ACTION_TYPE      = s.ACTION_TYPE,
            PCMS_LREF        = s.PCMS_LREF
    WHEN NOT MATCHED THEN
        INSERT (ABYS_BANK_ID, ABYS_BANK_CODE, DEFN, ABYS_DESCRIPTION, IS_ACTIVE, ACTION_TYPE, PCMS_LREF)
        VALUES (s.ABYS_BANK_ID, s.ABYS_BANK_CODE, s.DEFN, s.ABYS_DESCRIPTION, s.IS_ACTIVE, s.ACTION_TYPE, s.PCMS_LREF);
END
GO

-- ------------------------------------------------------------
-- izgazMGR IT_BANK_PRM → MIG_LS_BANK_MAP (MAP kurallari sabit)
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_LS_BANK_LOAD_FROM_ABYS
    @TruncateExisting BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.IT_BANK_PRM', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR.dbo.IT_BANK_PRM bulunamadi.', 16, 1);
        RETURN 1;
    END

    IF @TruncateExisting = 1
        TRUNCATE TABLE energy.dbo.MIG_LS_BANK_MAP;

    ;WITH Source AS (
        SELECT
            p.ID                                            AS ABYS_BANK_ID,
            p.CODE                                          AS ABYS_BANK_CODE,
            LEFT(COALESCE(l.VALUE, p.CODE), 100)            AS DEFN,
            CAST(ISNULL(p.IS_ACTIVE, 0) AS BIT)             AS IS_ACTIVE
        FROM izgazMGR.dbo.IT_BANK_PRM p
        LEFT JOIN izgazMGR.dbo.IT_BANK_PRM_LNG l
            ON l.PRM_ID = p.ID
           AND l.LANG_ID = 1
    ),
    MapRule AS (
        SELECT v.ABYS_BANK_ID, v.PCMS_LREF
        FROM (VALUES
            (9,   4), (11,  12), (13,  35), (14,  16), (17,  13),
            (19,  11), (21,  5),  (25,  1),  (30,  2),  (31,  6),
            (33,  3),  (35,  14), (37,  29), (38,  10), (39,  9),
            (40,  8),  (41,  27), (43,  31), (44,  17), (47,  7),
            (90,  28), (91,  19), (92,  25), (96,  30), (97,  32),
            (298, 36)
        ) v(ABYS_BANK_ID, PCMS_LREF)
    )
    INSERT INTO energy.dbo.MIG_LS_BANK_MAP
    (
        ABYS_BANK_ID, ABYS_BANK_CODE, DEFN, ABYS_DESCRIPTION,
        IS_ACTIVE, ACTION_TYPE, PCMS_LREF
    )
    SELECT
        s.ABYS_BANK_ID,
        s.ABYS_BANK_CODE,
        s.DEFN,
        NULL,
        s.IS_ACTIVE,
        CASE WHEN m.ABYS_BANK_ID IS NOT NULL THEN 'MAP' ELSE 'INSERT' END,
        m.PCMS_LREF
    FROM Source s
    LEFT JOIN MapRule m ON m.ABYS_BANK_ID = s.ABYS_BANK_ID
    WHERE NOT EXISTS (
        SELECT 1 FROM energy.dbo.MIG_LS_BANK_MAP x
        WHERE x.ABYS_BANK_ID = s.ABYS_BANK_ID
    );
END
GO

/*
-- Ornek: Excel satiri yukleme
EXEC dbo.SP_MIG_LS_BANK_MAP_UPSERT
    @AbysBankId = 9, @AbysBankCode = N'11-9', @Defn = N'AKBANK',
    @IsActive = 1, @Durum = N'Map', @PcmsLref = 9;

EXEC dbo.SP_MIG_LS_BANK_MAP_UPSERT
    @AbysBankId = 1, @AbysBankCode = N'25-1',
    @Defn = N'VAKIFBANK IZMIT MRK. ANA HES',
    @AbysDescription = N'KREDI KARTI TRANSFER HESABI',
    @IsActive = 1, @Durum = N'Yeni Eklenecek';

-- Aktarim
EXEC dbo.SP_MIG_LS_BANK_VALIDATE_MAP @RaiseOnError = 0;
EXEC dbo.SP_MIGRATE_LS_BANK @DEBUG = 1;

-- Bagimli tablo wiring (proje ilerledikce)
-- EXEC dbo.SP_MIG_LS_BANK_WIRE_FK @TargetTable = N'LS_001_01_PAYTRANS',
--     @AbysColumn = N'ABYS_BANK_ID', @FkColumn = N'BANKREF', @Debug = 1;
*/

