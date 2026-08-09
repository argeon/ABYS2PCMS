/* ============================================================
   SCRIPT_ID : II_APPOINTMENT_DEVICE_SETUP
   SCRIPT_NO : 534
   FILE      : 534_II_APPOINTMENT_DEVICE__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.II_APPOINTMENT_DEVICE
--   → energy.dbo.LS_005_01_APPOINTMENT_DEVICE
--
-- Pass 1 dump-style:
--   - PK + FK aktarim oncesi kaldirilir (RESTORE_KEYS sonra)
--   - Kaynakta olup hedefte OLMAYAN kolonlar ABYS_* olarak eklenir VE aktarilir
--   - DEVICE_TYPE / FLUE / CAPACITY / REGULATOR JOIN yok (proje sonu wire)
--   - LREF = II_APPOINTMENT_DEVICE.ID (IDENTITY_INSERT)
--   - ABYS_ID = II_APPOINTMENT_DEVICE.ID
--   - APPOINTMENT_REF = APPOINTMENT_ID (ham; parent LREF = ayni ID)
--   - PROJECT_DEVICE_REF = PROJECT_INSTALLATION_DEVICE_ID (ham)
--   - BRAND_CODE = MARK_CODE (ham)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT_DEVICE', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_005_01_APPOINTMENT_DEVICE bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- Aktarim oncesi: outbound/inbound FK + PK kaldir (idempotent)
-- Recreate → SP_MIG_II_APPOINTMENT_DEVICE_RESTORE_KEYS
-- ------------------------------------------------------------
DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @PkName SYSNAME;

-- 1) Bu tablodan cikan FK
SELECT @Sql = @Sql + N'
ALTER TABLE energy.dbo.LS_005_01_APPOINTMENT_DEVICE DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
FROM sys.foreign_keys fk
WHERE fk.parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT_DEVICE');

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;

-- 2) Bu tabloya gelen FK (child → APPOINTMENT_DEVICE)
SET @Sql = N'';
SELECT @Sql = @Sql + N'
ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id))
    + N'.' + QUOTENAME(OBJECT_NAME(fk.parent_object_id))
    + N' DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
FROM sys.foreign_keys fk
WHERE fk.referenced_object_id = OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT_DEVICE');

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;

-- 3) PK (auto-name olabilir: PK__LS_005_0__...)
SELECT @PkName = kc.name
FROM sys.key_constraints kc
WHERE kc.parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT_DEVICE')
  AND kc.type = 'PK';

IF @PkName IS NOT NULL
BEGIN
    SET @Sql = N'ALTER TABLE energy.dbo.LS_005_01_APPOINTMENT_DEVICE DROP CONSTRAINT '
        + QUOTENAME(@PkName) + N';';
    EXEC sp_executesql @Sql;
END
GO

-- ------------------------------------------------------------
-- Canli audit kolonlari: ADDUSER / ADDDATE / UPDUSER / UPDDATE
-- (CREATED_* hedef DDL varsa da ayni deger dual-write)
-- ------------------------------------------------------------
DECLARE @SqlAudit NVARCHAR(MAX) = N'';
DECLARE @AuditCols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(200) NOT NULL);

INSERT INTO @AuditCols (COL_NAME, COL_DEF) VALUES
 (N'ADDUSER',  N'INT NULL'),
 (N'ADDDATE',  N'DATETIME NULL'),
 (N'UPDUSER',  N'INT NULL'),
 (N'UPDDATE',  N'DATETIME NULL');

SELECT @SqlAudit = @SqlAudit + N'
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(''energy.dbo.LS_005_01_APPOINTMENT_DEVICE'')
      AND name = ''' + COL_NAME + N'''
)
    ALTER TABLE energy.dbo.LS_005_01_APPOINTMENT_DEVICE ADD ' + COL_NAME + N' ' + COL_DEF + N';'
FROM @AuditCols;

IF LEN(@SqlAudit) > 0
    EXEC sp_executesql @SqlAudit;
GO

-- ------------------------------------------------------------
-- ABYS bridge kolonlari (idempotent)
-- Kaynakta olup hedef DDL'de olmayan her kolon → ABYS_* (ham aktarim)
-- ------------------------------------------------------------
DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(200) NOT NULL);

-- Kaynakta olup hedef DDL'de olmayan her kolon → ABYS_* (ham aktarim)
INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 (N'ABYS_ID',                                 N'BIGINT NULL'),
 (N'ABYS_APPOINTMENT_ID',                     N'BIGINT NULL'),
 (N'ABYS_PROJECT_INSTALLATION_DEVICE_ID',     N'BIGINT NULL'),
 (N'ABYS_DEVICE_MARK_ID',                     N'BIGINT NULL'),
 (N'ABYS_MARK_CODE',                          N'BIGINT NULL'),
 (N'ABYS_DEVICE_MODEL_ID',                    N'BIGINT NULL'),
 (N'ABYS_DEVICE_STATUS',                      N'SMALLINT NULL'),
 (N'ABYS_STARTUP_DATE',                       N'DATETIME2(0) NULL'),
 (N'ABYS_SHOULD_UPDATED',                     N'SMALLINT NULL'),
 (N'ABYS_CREATED_USER_ID',                    N'BIGINT NULL'),
 (N'ABYS_CREATED_TIMESTAMP',                  N'DATETIMEOFFSET(7) NULL'),
 (N'ABYS_UPDATED_USER_ID',                    N'BIGINT NULL'),
 (N'ABYS_UPDATED_TIMESTAMP',                  N'DATETIMEOFFSET(7) NULL'),
 (N'ABYS_VERSION',                            N'BIGINT NULL'),
 (N'ABYS_CIHAZ_ID_',                          N'NVARCHAR(50) NULL');

SELECT @Sql = @Sql + N'
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(''energy.dbo.LS_005_01_APPOINTMENT_DEVICE'')
      AND name = ''' + COL_NAME + N'''
)
    ALTER TABLE energy.dbo.LS_005_01_APPOINTMENT_DEVICE ADD ' + COL_NAME + N' ' + COL_DEF + N';'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT_DEVICE')
      AND name = 'UX_LS005_APPOINTMENT_DEVICE_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS005_APPOINTMENT_DEVICE_ABYS_ID
        ON energy.dbo.LS_005_01_APPOINTMENT_DEVICE (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Validate
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_DEVICE_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.II_APPOINTMENT_DEVICE', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.II_APPOINTMENT_DEVICE bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('ID'),('APPOINTMENT_ID'),('PROJECT_INSTALLATION_DEVICE_ID'),
            ('DEVICE_MARK_ID'),('MARK_CODE'),('DEVICE_MODEL_ID'),
            ('DEVICE_STATUS'),('STARTUP_DATE'),('SHOULD_UPDATED'),
            ('CREATED_USER_ID'),('CREATED_TIMESTAMP'),
            ('UPDATED_USER_ID'),('UPDATED_TIMESTAMP'),('VERSION'),
            ('CIHAZ_ID_')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'II_APPOINTMENT_DEVICE' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'II_APPOINTMENT_DEVICE eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'II_APPOINTMENT_DEVICE kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_DEVICE_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT_DEVICE', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_APPOINTMENT_DEVICE bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('UNIT_LREF'),
            ('DEVICE_TYPE_CODE'),('DEVICE_TYPE'),
            ('FLUE_TYPE_CODE'),('FLUE_TYPE'),
            ('IS_CONDENSED'),('DEVICE_CAPACITY'),('DEVICE_FLOW_RATE'),
            ('EFFICIENCY'),('WORKING_PRESSURE'),('DEVICE_LOCATION'),
            ('DEVICE_STATUS'),('STARTUP_DATE'),('SHOULD_UPDATED'),
            ('APPOINTMENT_REF'),
            ('ADDUSER'),('ADDDATE'),('UPDUSER'),('UPDDATE'),
            ('CREATED_USER'),('CREATED_DATE'),('UPDATED_USER'),('UPDATED_DATE'),
            ('PROJECTLINE_ID'),('BRAND_CODE'),('BRAND'),('PROJECT_DEVICE_REF'),
            ('REGULATOR_BRAND'),('REGULATOR_TYPE'),('REGULATOR_SERIAL'),('REGULATOR_YEAR'),
            ('ABYS_ID'),('ABYS_APPOINTMENT_ID'),('ABYS_PROJECT_INSTALLATION_DEVICE_ID'),
            ('ABYS_DEVICE_MARK_ID'),('ABYS_MARK_CODE'),('ABYS_DEVICE_MODEL_ID'),
            ('ABYS_DEVICE_STATUS'),('ABYS_STARTUP_DATE'),('ABYS_SHOULD_UPDATED'),
            ('ABYS_CREATED_USER_ID'),('ABYS_CREATED_TIMESTAMP'),
            ('ABYS_UPDATED_USER_ID'),('ABYS_UPDATED_TIMESTAMP'),
            ('ABYS_VERSION'),('ABYS_CIHAZ_ID_')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT_DEVICE')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_APPOINTMENT_DEVICE eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_APPOINTMENT_DEVICE hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_DEVICE_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_II_APPOINTMENT_DEVICE_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_II_APPOINTMENT_DEVICE_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    RETURN @Rc;
END
GO

-- ------------------------------------------------------------
-- PK restore (wire / aktarim SONRASI)
-- FK recreate: canli DDL isimleri netlestiginde eklenir
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_DEVICE_RESTORE_KEYS
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT_DEVICE', 'U') IS NULL
    BEGIN
        RAISERROR('energy.dbo.LS_005_01_APPOINTMENT_DEVICE bulunamadi.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1 FROM sys.key_constraints
        WHERE parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT_DEVICE')
          AND type = 'PK'
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE PK_LS_005_01_APPOINTMENT_DEVICE...', 0, 1) WITH NOWAIT;

        ALTER TABLE energy.dbo.LS_005_01_APPOINTMENT_DEVICE
            ADD CONSTRAINT PK_LS_005_01_APPOINTMENT_DEVICE PRIMARY KEY CLUSTERED (LREF ASC)
            WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF,
                  ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON,
                  OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF);
    END

    IF @DEBUG = 1
        RAISERROR('SP_MIG_II_APPOINTMENT_DEVICE_RESTORE_KEYS OK (FK manuel / wire sonrasi)', 0, 1) WITH NOWAIT;
END
GO

/*
-- SAKLANAN RECREATE DDL (manuel referans)
ALTER TABLE [dbo].[LS_005_01_APPOINTMENT_DEVICE]
    ADD CONSTRAINT [PK_LS_005_01_APPOINTMENT_DEVICE] PRIMARY KEY CLUSTERED ([LREF] ASC)
    WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF,
          ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON,
          OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF);
-- FK'ler canli semadan netlestirilince buraya eklenecek.
*/

-- ------------------------------------------------------------
-- Kaynak view (kolon eslemesi tek nokta)
-- LREF = ID (IDENTITY_INSERT, BIGINT)
-- ============================================================
CREATE OR ALTER VIEW dbo.VW_MIG_II_APPOINTMENT_DEVICE_SOURCE
AS
SELECT
    CAST(s.ID AS BIGINT)                                                    AS LREF,
    CAST(s.ID AS BIGINT)                                                    AS ABYS_ID,

    -- ABYS_* : kaynak ham degerler (hedefte olmayan / audit)
    CAST(s.APPOINTMENT_ID AS BIGINT)                                        AS ABYS_APPOINTMENT_ID,
    CAST(s.PROJECT_INSTALLATION_DEVICE_ID AS BIGINT)                        AS ABYS_PROJECT_INSTALLATION_DEVICE_ID,
    CAST(s.DEVICE_MARK_ID AS BIGINT)                                        AS ABYS_DEVICE_MARK_ID,
    CAST(s.MARK_CODE AS BIGINT)                                             AS ABYS_MARK_CODE,
    CAST(s.DEVICE_MODEL_ID AS BIGINT)                                       AS ABYS_DEVICE_MODEL_ID,
    CAST(s.DEVICE_STATUS AS SMALLINT)                                       AS ABYS_DEVICE_STATUS,
    CAST(s.STARTUP_DATE AS DATETIME2(0))                                    AS ABYS_STARTUP_DATE,
    CAST(s.SHOULD_UPDATED AS SMALLINT)                                      AS ABYS_SHOULD_UPDATED,
    CAST(s.CREATED_USER_ID AS BIGINT)                                       AS ABYS_CREATED_USER_ID,
    s.CREATED_TIMESTAMP                                                     AS ABYS_CREATED_TIMESTAMP,
    CAST(s.UPDATED_USER_ID AS BIGINT)                                       AS ABYS_UPDATED_USER_ID,
    s.UPDATED_TIMESTAMP                                                     AS ABYS_UPDATED_TIMESTAMP,
    CAST(s.VERSION AS BIGINT)                                               AS ABYS_VERSION,
    LEFT(s.CIHAZ_ID_, 50)                                                   AS ABYS_CIHAZ_ID_,

    -- Hedef canli kolonlar (eslesen / donusen)
    CAST(NULL AS BIGINT)                                                    AS UNIT_LREF,
    CAST(NULL AS INT)                                                       AS DEVICE_TYPE_CODE,
    CAST(NULL AS NVARCHAR(50))                                              AS DEVICE_TYPE,
    CAST(NULL AS INT)                                                       AS FLUE_TYPE_CODE,
    CAST(NULL AS NVARCHAR(50))                                              AS FLUE_TYPE,
    CAST(NULL AS BIT)                                                       AS IS_CONDENSED,
    CAST(NULL AS DECIMAL(10, 2))                                            AS DEVICE_CAPACITY,
    CAST(NULL AS INT)                                                       AS DEVICE_FLOW_RATE,
    CAST(NULL AS INT)                                                       AS EFFICIENCY,
    CAST(NULL AS INT)                                                       AS WORKING_PRESSURE,
    CAST(NULL AS NVARCHAR(100))                                             AS DEVICE_LOCATION,

    CAST(CASE WHEN ISNULL(s.DEVICE_STATUS, 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS DEVICE_STATUS,
    energy.dbo.FN_SAFE_DT(CAST(s.STARTUP_DATE AS DATETIME2))                AS STARTUP_DATE,
    CAST(CASE WHEN ISNULL(s.SHOULD_UPDATED, 0) <> 0 THEN 1 ELSE 0 END AS BIT) AS SHOULD_UPDATED,

    CAST(s.APPOINTMENT_ID AS INT)                                           AS APPOINTMENT_REF,
    -- CREATED_* → ADDUSER/ADDDATE ; UPDATED_* → UPDUSER/UPDDATE
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.CREATED_USER_ID AS INT))       AS ADDUSER,
    ISNULL(
        energy.dbo.FN_SAFE_DT(CAST(s.CREATED_TIMESTAMP AS DATETIME2)),
        CAST('19000101' AS DATETIME))                                       AS ADDDATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.UPDATED_USER_ID AS INT))       AS UPDUSER,
    energy.dbo.FN_SAFE_DT(CAST(s.UPDATED_TIMESTAMP AS DATETIME2))           AS UPDDATE,
    -- Canli DDL CREATED_*/UPDATED_* varsa ayni deger
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.CREATED_USER_ID AS INT))       AS CREATED_USER,
    ISNULL(
        energy.dbo.FN_SAFE_DT(CAST(s.CREATED_TIMESTAMP AS DATETIME2)),
        CAST('19000101' AS DATETIME))                                       AS CREATED_DATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.UPDATED_USER_ID AS INT))       AS UPDATED_USER,
    energy.dbo.FN_SAFE_DT(CAST(s.UPDATED_TIMESTAMP AS DATETIME2))           AS UPDATED_DATE,

    CAST(NULL AS INT)                                                       AS PROJECTLINE_ID,
    CAST(s.MARK_CODE AS INT)                                                AS BRAND_CODE,
    CAST(NULL AS NVARCHAR(100))                                             AS BRAND,
    CAST(s.PROJECT_INSTALLATION_DEVICE_ID AS INT)                           AS PROJECT_DEVICE_REF,

    CAST(NULL AS NVARCHAR(100))                                             AS REGULATOR_BRAND,
    CAST(NULL AS NVARCHAR(100))                                             AS REGULATOR_TYPE,
    CAST(NULL AS NVARCHAR(100))                                             AS REGULATOR_SERIAL,
    CAST(NULL AS INT)                                                       AS REGULATOR_YEAR
FROM izgazMGR.dbo.II_APPOINTMENT_DEVICE s
WHERE s.ID IS NOT NULL
  AND s.APPOINTMENT_ID BETWEEN 1 AND 2147483647;  -- APPOINTMENT_REF INT
GO

EXEC dbo.SP_MIG_II_APPOINTMENT_DEVICE_VALIDATE_ALL @RaiseOnMissing = 0;
GO

PRINT '534_II_APPOINTMENT_DEVICE__setup OK';
GO
