/* ============================================================
   SCRIPT_ID : II_APPOINTMENT_SETUP
   SCRIPT_NO : 532
   FILE      : 532_II_APPOINTMENT__setup.sql
   VERSION   : 2
   ============================================================ */
-- v2: Kaynakta var / hedefte yok kolonlar → ABYS_* ALTER + aktarim
--     Nullable FK canlı kolonlar Pass 1 NULL; ham → ABYS_*
-- ============================================================
-- izgazMGR.dbo.II_APPOINTMENT
--   → energy.dbo.LS_005_01_APPOINTMENT
--
-- Pass 1 dump-style:
--   - PK + FK aktarim oncesi kaldirilir (RESTORE_KEYS sonra)
--   - Hedefte olmayan kaynak kolonlar ABYS_* olarak eklenir ve aktarilir
--   - PROJECT / AGR / meter / pool JOIN yok (proje sonu wire)
--   - LREF = II_APPOINTMENT.ID (IDENTITY_INSERT)
--   - ABYS_ID = II_APPOINTMENT.ID
--
-- NOT NULL placeholder:
--   APPOINTMENT_POOL_REF = 0 (kaynakta yok; wire sonra)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_005_01_APPOINTMENT bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- Aktarim oncesi: outbound/inbound FK + PK kaldir (idempotent)
-- Recreate → SP_MIG_II_APPOINTMENT_RESTORE_KEYS
-- ------------------------------------------------------------
DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @PkName SYSNAME;

-- 1) Bu tablodan cikan FK
SELECT @Sql = @Sql + N'
ALTER TABLE energy.dbo.LS_005_01_APPOINTMENT DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
FROM sys.foreign_keys fk
WHERE fk.parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT');

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;

-- 2) Bu tabloya gelen FK (child → APPOINTMENT)
SET @Sql = N'';
SELECT @Sql = @Sql + N'
ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id))
    + N'.' + QUOTENAME(OBJECT_NAME(fk.parent_object_id))
    + N' DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
FROM sys.foreign_keys fk
WHERE fk.referenced_object_id = OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT');

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;

-- 3) PK (auto-name olabilir: PK__LS_005_0__...)
SELECT @PkName = kc.name
FROM sys.key_constraints kc
WHERE kc.parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT')
  AND kc.type = 'PK';

IF @PkName IS NOT NULL
BEGIN
    SET @Sql = N'ALTER TABLE energy.dbo.LS_005_01_APPOINTMENT DROP CONSTRAINT '
        + QUOTENAME(@PkName) + N';';
    EXEC sp_executesql @Sql;
END
GO

-- ------------------------------------------------------------
-- ABYS bridge kolonlari (idempotent)
-- ------------------------------------------------------------
DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(200) NOT NULL);

INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 -- kopru / wire
 (N'ABYS_ID',                         N'BIGINT NULL'),
 (N'ABYS_PROJECT_ID',                 N'BIGINT NULL'),
 (N'ABYS_FIRM_ID',                    N'BIGINT NULL'),
 (N'ABYS_AGREEMENT_ID',               N'BIGINT NULL'),
 (N'ABYS_METER_ID',                   N'BIGINT NULL'),
 (N'ABYS_CAMPAIGN_ID',                N'BIGINT NULL'),
 (N'ABYS_APPOINTMENT_TYPE_ID',        N'BIGINT NULL'),
 (N'ABYS_CREATED_USER_ID',            N'BIGINT NULL'),
 (N'ABYS_UPDATED_USER_ID',            N'BIGINT NULL'),
 (N'ABYS_SUSPEND_USER_ID',            N'BIGINT NULL'),
 (N'ABYS_CANCEL_USER_ID',             N'BIGINT NULL'),
 (N'ABYS_REGULATOR_TYPE_ID',          N'BIGINT NULL'),
 (N'ABYS_REGULATOR_MARK_ID',          N'BIGINT NULL'),
 (N'ABYS_EARTHQUAKE_VALVE_MARK_ID',   N'BIGINT NULL'),
 -- kaynakta var, hedefte yok → ABYS_* olarak olustur + aktar
 (N'ABYS_PROJECT_INSTALLATION_ID',    N'BIGINT NULL'),
 (N'ABYS_OLD_VALUES',                 N'NVARCHAR(MAX) NULL'),
 (N'ABYS_INTEGRATION_CODE',           N'NVARCHAR(20) NULL'),
 (N'ABYS_VERSION',                    N'BIGINT NULL'),
 (N'ABYS_CREATED_TIMESTAMP',          N'DATETIMEOFFSET(7) NULL'),
 (N'ABYS_UPDATED_TIMESTAMP',          N'DATETIMEOFFSET(7) NULL'),
 (N'ABYS_FATURA_TARIHI_',             N'DATETIME2(0) NULL'),
 (N'ABYS_FATURA_BEDELI_',             N'DECIMAL(22,0) NULL'),
 (N'ABYS_FATURA_BEDELI_KDV_',         N'DECIMAL(22,0) NULL'),
 (N'ABYS_FATURA_NUMARASI_',           N'DECIMAL(22,0) NULL'),
 (N'ABYS_INSTALLATION_ID_',           N'DECIMAL(22,0) NULL'),
 (N'ABYS_AGR_INSTALLATION_ID_',       N'DECIMAL(22,0) NULL'),
 (N'ABYS_RANDEVU_GIRIS_TAR_',         N'DATETIME2(0) NULL');

SELECT @Sql = @Sql + N'
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(''energy.dbo.LS_005_01_APPOINTMENT'')
      AND name = ''' + COL_NAME + N'''
)
    ALTER TABLE energy.dbo.LS_005_01_APPOINTMENT ADD ' + COL_NAME + N' ' + COL_DEF + N';'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT')
      AND name = 'UX_LS005_APPOINTMENT_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS005_APPOINTMENT_ABYS_ID
        ON energy.dbo.LS_005_01_APPOINTMENT (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Validate
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.II_APPOINTMENT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.II_APPOINTMENT bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('ID'),('APPOINTMENT_TYPE_ID'),('REQUEST_DATE'),('STATUS'),
            ('PROJECT_ID'),('PROJECT_INSTALLATION_ID'),('FIRM_ID'),('AGREEMENT_ID'),
            ('APPOINTMENT_GOING_NUMBER'),('CAMPAIGN_ID'),('CAMPAIGN_PERIOD'),
            ('RECORD_TYPE'),('DESCRIPTION'),('METER_ID'),('ACCOUNT_ID'),
            ('IS_SUSPEND'),('SUSPEND_DATE'),('SUSPEND_USER_ID'),('SUSPEND_DESCRIPTION'),
            ('APPROVAL_DESCRIPTION'),
            ('RSLT_METER_NUMBER'),('RSLT_LAST_INDEX'),('RSLT_DATE'),
            ('RSLT_INSTALLATION_CONTROL'),('RSLT_OPEN'),('RSLT_RELEASE'),('RSLT_CONTROL'),
            ('GAS_CUTTING_STATUS'),('NEXT_CONTROL_DATE'),('WHERE_REMOVING_METER'),
            ('SEAL_SERIAL_NUMBER'),('REGULATOR_TYPE_ID'),('REGULATOR_MARK_ID'),
            ('REGULATOR_SERIAL_NUMBER'),('EARTHQUAKE_VALVE_MARK_ID'),
            ('OLD_VALUES'),('INTEGRATION_CODE'),
            ('CANCEL_DATE'),('CANCEL_USER_ID'),('CANCEL_DESCRIPTION'),
            ('CANCEL_BILL_NUMBER'),('CANCEL_BILL_DATE'),
            ('WHERE_REMOVING_REGULATOR'),('COMEBACK_DATE'),
            ('CREATED_USER_ID'),('CREATED_TIMESTAMP'),
            ('UPDATED_USER_ID'),('UPDATED_TIMESTAMP'),('VERSION'),
            ('IS_ADJUSTABLE'),
            ('FATURA_TARIHI_'),('FATURA_BEDELI_'),('FATURA_BEDELI_KDV_'),('FATURA_NUMARASI_'),
            ('INSTALLATION_ID_'),('AGR_INSTALLATION_ID_'),('RANDEVU_GIRIS_TAR_')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'II_APPOINTMENT' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'II_APPOINTMENT eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'II_APPOINTMENT kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_APPOINTMENT bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('APPOINTMENT_TYPE_ID'),('APPOINTMENT_POOL_REF'),
            ('REQUEST_DATE'),('APPOINTMENT_ASSIGNDATE'),('APPOINTMENT_DATE'),
            ('STATUS'),('PROJECT_ID'),('FITNO'),('FIRM_ID'),('TEAM_ID'),
            ('AGREEMENT_LREF'),('APPOINTMENT_GOING_NUMBER'),
            ('CAMPAIGN_ID'),('CAMPAIGN_PERIOD'),('RECORD_TYPE'),('DESCRIPTION'),
            ('METER_ID'),('ACCOUNT_ID'),
            ('IS_SUSPEND'),('SUSPEND_DATE'),('SUSPEND_USER_ID'),('SUSPEND_DESCRIPTION'),
            ('APPROVAL_DESCRIPTION'),
            ('RSLT_METER_NUMBER'),('RSLT_LAST_INDEX'),('RSLT_DATE'),
            ('RSLT_INSTALLATION_CONTROL'),('RSLT_OPEN'),('RSLT_RELEASE'),('RSLT_CONTROL'),
            ('GAS_CUTTING_STATUS'),('NEXT_CONTROL_DATE'),('WHERE_REMOVING_METER'),
            ('SEAL_SERIAL_NUMBER'),('REGULATOR_TYPE_ID'),('REGULATOR_MARK_ID'),
            ('REGULATOR_SERIAL_NUMBER'),('EARTHQUAKE_VALVE_MARK_ID'),
            ('WORKORDER_REF'),
            ('CANCEL_DATE'),('CANCEL_USER_ID'),('CANCEL_DESCRIPTION'),
            ('CANCEL_BILL_NUMBER'),('CANCEL_BILL_DATE'),
            ('WHERE_REMOVING_REGULATOR'),('COMEBACK_DATE'),
            ('CREATED_USER_ID'),('CREATED_DATE'),('UPDATED_USER_ID'),('UPDATED_DATE'),
            ('IS_ADJUSTABLE'),
            ('FATURA_TARIHI'),('FATURA_BEDELI'),('FATURA_BEDELI_KDV'),('FATURA_NUMARASI'),
            ('STARTTIME'),('ENDTIME'),
            ('OLDPROJECT_ID'),('PROJECTLINE_ID'),('OLD_PROJECT_CODE'),('OLD_PROJECT_YEAR'),
            ('ENGINEERID'),('ENGINEERLREF'),
            ('ABYS_ID'),('ABYS_PROJECT_ID'),('ABYS_PROJECT_INSTALLATION_ID'),
            ('ABYS_FIRM_ID'),('ABYS_AGREEMENT_ID'),('ABYS_METER_ID'),('ABYS_CAMPAIGN_ID'),
            ('ABYS_APPOINTMENT_TYPE_ID'),
            ('ABYS_CREATED_USER_ID'),('ABYS_UPDATED_USER_ID'),
            ('ABYS_SUSPEND_USER_ID'),('ABYS_CANCEL_USER_ID'),
            ('ABYS_REGULATOR_TYPE_ID'),('ABYS_REGULATOR_MARK_ID'),
            ('ABYS_EARTHQUAKE_VALVE_MARK_ID'),
            ('ABYS_OLD_VALUES'),('ABYS_INTEGRATION_CODE'),('ABYS_VERSION'),
            ('ABYS_CREATED_TIMESTAMP'),('ABYS_UPDATED_TIMESTAMP'),
            ('ABYS_FATURA_TARIHI_'),('ABYS_FATURA_BEDELI_'),
            ('ABYS_FATURA_BEDELI_KDV_'),('ABYS_FATURA_NUMARASI_'),
            ('ABYS_INSTALLATION_ID_'),('ABYS_AGR_INSTALLATION_ID_'),
            ('ABYS_RANDEVU_GIRIS_TAR_')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_APPOINTMENT eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_APPOINTMENT hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_II_APPOINTMENT_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_II_APPOINTMENT_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    RETURN @Rc;
END
GO

-- ------------------------------------------------------------
-- PK restore (wire / aktarim SONRASI)
-- FK recreate: canli DDL isimleri netlestiginde eklenir
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_II_APPOINTMENT_RESTORE_KEYS
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT', 'U') IS NULL
    BEGIN
        RAISERROR('energy.dbo.LS_005_01_APPOINTMENT bulunamadi.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1 FROM sys.key_constraints
        WHERE parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_APPOINTMENT')
          AND type = 'PK'
    )
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CREATE PK_LS_005_01_APPOINTMENT...', 0, 1) WITH NOWAIT;

        ALTER TABLE energy.dbo.LS_005_01_APPOINTMENT
            ADD CONSTRAINT PK_LS_005_01_APPOINTMENT PRIMARY KEY CLUSTERED (LREF ASC)
            WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF,
                  ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON,
                  OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF);
    END

    IF @DEBUG = 1
        RAISERROR('SP_MIG_II_APPOINTMENT_RESTORE_KEYS OK (FK manuel / wire sonrasi)', 0, 1) WITH NOWAIT;
END
GO

/*
-- SAKLANAN RECREATE DDL (manuel referans)
ALTER TABLE [dbo].[LS_005_01_APPOINTMENT]
    ADD CONSTRAINT [PK_LS_005_01_APPOINTMENT] PRIMARY KEY CLUSTERED ([LREF] ASC)
    WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF,
          ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON,
          OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF);
-- FK'ler canli semadan netlestirilince buraya eklenecek.
*/

-- ------------------------------------------------------------
-- Kaynak view (kolon eslemesi tek nokta)
-- LREF = ID (IDENTITY_INSERT)
-- Hedefte olmayan kaynak kolonlar → ABYS_* (aktarilir)
-- Nullable FK canli kolonlar → NULL (wire sonra); ham → ABYS_*
-- ============================================================
CREATE OR ALTER VIEW dbo.VW_MIG_II_APPOINTMENT_SOURCE
AS
SELECT
    CAST(s.ID AS INT)                                                       AS LREF,
    CAST(s.ID AS BIGINT)                                                    AS ABYS_ID,

    -- ABYS kopru (ham FK / user)
    CAST(s.PROJECT_ID AS BIGINT)                                            AS ABYS_PROJECT_ID,
    CAST(s.FIRM_ID AS BIGINT)                                               AS ABYS_FIRM_ID,
    CAST(s.AGREEMENT_ID AS BIGINT)                                          AS ABYS_AGREEMENT_ID,
    CAST(s.METER_ID AS BIGINT)                                              AS ABYS_METER_ID,
    CAST(s.CAMPAIGN_ID AS BIGINT)                                           AS ABYS_CAMPAIGN_ID,
    CAST(s.APPOINTMENT_TYPE_ID AS BIGINT)                                   AS ABYS_APPOINTMENT_TYPE_ID,
    CAST(s.CREATED_USER_ID AS BIGINT)                                       AS ABYS_CREATED_USER_ID,
    CAST(s.UPDATED_USER_ID AS BIGINT)                                       AS ABYS_UPDATED_USER_ID,
    CAST(s.SUSPEND_USER_ID AS BIGINT)                                       AS ABYS_SUSPEND_USER_ID,
    CAST(s.CANCEL_USER_ID AS BIGINT)                                        AS ABYS_CANCEL_USER_ID,
    CAST(s.REGULATOR_TYPE_ID AS BIGINT)                                     AS ABYS_REGULATOR_TYPE_ID,
    CAST(s.REGULATOR_MARK_ID AS BIGINT)                                     AS ABYS_REGULATOR_MARK_ID,
    CAST(s.EARTHQUAKE_VALVE_MARK_ID AS BIGINT)                              AS ABYS_EARTHQUAKE_VALVE_MARK_ID,

    -- Kaynakta var, hedefte yok → ABYS_* aktar
    CAST(s.PROJECT_INSTALLATION_ID AS BIGINT)                               AS ABYS_PROJECT_INSTALLATION_ID,
    s.OLD_VALUES                                                            AS ABYS_OLD_VALUES,
    LEFT(s.INTEGRATION_CODE, 20)                                            AS ABYS_INTEGRATION_CODE,
    CAST(s.VERSION AS BIGINT)                                               AS ABYS_VERSION,
    s.CREATED_TIMESTAMP                                                     AS ABYS_CREATED_TIMESTAMP,
    s.UPDATED_TIMESTAMP                                                     AS ABYS_UPDATED_TIMESTAMP,
    CAST(s.FATURA_TARIHI_ AS DATETIME2(0))                                  AS ABYS_FATURA_TARIHI_,
    s.FATURA_BEDELI_                                                        AS ABYS_FATURA_BEDELI_,
    s.FATURA_BEDELI_KDV_                                                    AS ABYS_FATURA_BEDELI_KDV_,
    s.FATURA_NUMARASI_                                                      AS ABYS_FATURA_NUMARASI_,
    s.INSTALLATION_ID_                                                      AS ABYS_INSTALLATION_ID_,
    s.AGR_INSTALLATION_ID_                                                  AS ABYS_AGR_INSTALLATION_ID_,
    CAST(s.RANDEVU_GIRIS_TAR_ AS DATETIME2(0))                              AS ABYS_RANDEVU_GIRIS_TAR_,

    -- Canli hedef kolonlar
    CAST(s.APPOINTMENT_TYPE_ID AS INT)                                      AS APPOINTMENT_TYPE_ID,
    CAST(0 AS INT)                                                          AS APPOINTMENT_POOL_REF,  -- kaynakta yok
    energy.dbo.FN_SAFE_DT(CAST(s.REQUEST_DATE AS DATETIME2))                AS REQUEST_DATE,
    CAST(NULL AS DATETIME)                                                  AS APPOINTMENT_ASSIGNDATE,
    energy.dbo.FN_SAFE_DT(CAST(s.RANDEVU_GIRIS_TAR_ AS DATETIME2))          AS APPOINTMENT_DATE,
    CAST(s.STATUS AS TINYINT)                                               AS STATUS,
    -- PROJECT_ID NOT NULL INT; bigint tasarsa 0 + ABYS_PROJECT_ID'de ham
    ISNULL(TRY_CAST(s.PROJECT_ID AS INT), 0)                                AS PROJECT_ID,
    TRY_CAST(s.INSTALLATION_ID_ AS BIGINT)                                  AS FITNO,
    CAST(NULL AS INT)                                                       AS FIRM_ID,               -- wire: ABYS_FIRM_ID
    CAST(NULL AS INT)                                                       AS TEAM_ID,
    CAST(NULL AS INT)                                                       AS AGREEMENT_LREF,        -- wire: ABYS_AGREEMENT_ID
    CAST(s.APPOINTMENT_GOING_NUMBER AS TINYINT)                             AS APPOINTMENT_GOING_NUMBER,
    CAST(NULL AS INT)                                                       AS CAMPAIGN_ID,           -- wire: ABYS_CAMPAIGN_ID
    CAST(s.CAMPAIGN_PERIOD AS SMALLINT)                                     AS CAMPAIGN_PERIOD,
    CAST(s.RECORD_TYPE AS TINYINT)                                          AS RECORD_TYPE,
    LEFT(s.DESCRIPTION, 500)                                                AS DESCRIPTION,
    CAST(NULL AS INT)                                                       AS METER_ID,              -- wire: ABYS_METER_ID
    s.ACCOUNT_ID                                                            AS ACCOUNT_ID,
    CAST(ISNULL(s.IS_SUSPEND, 0) AS TINYINT)                                AS IS_SUSPEND,
    energy.dbo.FN_SAFE_DT(CAST(s.SUSPEND_DATE AS DATETIME2))                AS SUSPEND_DATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.SUSPEND_USER_ID AS INT))       AS SUSPEND_USER_ID,
    LEFT(s.SUSPEND_DESCRIPTION, 500)                                        AS SUSPEND_DESCRIPTION,
    LEFT(s.APPROVAL_DESCRIPTION, 500)                                       AS APPROVAL_DESCRIPTION,
    LEFT(s.RSLT_METER_NUMBER, 25)                                           AS RSLT_METER_NUMBER,
    CAST(s.RSLT_LAST_INDEX AS DECIMAL(15, 3))                               AS RSLT_LAST_INDEX,
    energy.dbo.FN_SAFE_DT(CAST(s.RSLT_DATE AS DATETIME2))                   AS RSLT_DATE,
    CAST(s.RSLT_INSTALLATION_CONTROL AS TINYINT)                            AS RSLT_INSTALLATION_CONTROL,
    CAST(s.RSLT_OPEN AS TINYINT)                                            AS RSLT_OPEN,
    CAST(s.RSLT_RELEASE AS TINYINT)                                         AS RSLT_RELEASE,
    CAST(s.RSLT_CONTROL AS TINYINT)                                         AS RSLT_CONTROL,
    CAST(s.GAS_CUTTING_STATUS AS TINYINT)                                   AS GAS_CUTTING_STATUS,
    energy.dbo.FN_SAFE_DT(CAST(s.NEXT_CONTROL_DATE AS DATETIME2))           AS NEXT_CONTROL_DATE,
    CAST(s.WHERE_REMOVING_METER AS TINYINT)                                 AS WHERE_REMOVING_METER,
    LEFT(s.SEAL_SERIAL_NUMBER, 15)                                          AS SEAL_SERIAL_NUMBER,
    CAST(NULL AS INT)                                                       AS REGULATOR_TYPE_ID,     -- wire: ABYS_*
    CAST(NULL AS INT)                                                       AS REGULATOR_MARK_ID,
    LEFT(s.REGULATOR_SERIAL_NUMBER, 20)                                     AS REGULATOR_SERIAL_NUMBER,
    CAST(NULL AS INT)                                                       AS EARTHQUAKE_VALVE_MARK_ID,
    CAST(NULL AS INT)                                                       AS WORKORDER_REF,
    energy.dbo.FN_SAFE_DT(CAST(s.CANCEL_DATE AS DATETIME2))                 AS CANCEL_DATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.CANCEL_USER_ID AS INT))        AS CANCEL_USER_ID,
    LEFT(s.CANCEL_DESCRIPTION, 200)                                         AS CANCEL_DESCRIPTION,
    LEFT(s.CANCEL_BILL_NUMBER, 20)                                          AS CANCEL_BILL_NUMBER,
    energy.dbo.FN_SAFE_DT(CAST(s.CANCEL_BILL_DATE AS DATETIME2))            AS CANCEL_BILL_DATE,
    CAST(s.WHERE_REMOVING_REGULATOR AS TINYINT)                             AS WHERE_REMOVING_REGULATOR,
    energy.dbo.FN_SAFE_DT(CAST(s.COMEBACK_DATE AS DATETIME2))               AS COMEBACK_DATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.CREATED_USER_ID AS INT))       AS CREATED_USER_ID,
    ISNULL(
        energy.dbo.FN_SAFE_DT(CAST(s.CREATED_TIMESTAMP AS DATETIME2)),
        CAST('19000101' AS DATETIME))                                       AS CREATED_DATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.UPDATED_USER_ID AS INT))       AS UPDATED_USER_ID,
    energy.dbo.FN_SAFE_DT(CAST(s.UPDATED_TIMESTAMP AS DATETIME2))           AS UPDATED_DATE,
    CAST(s.IS_ADJUSTABLE AS TINYINT)                                        AS IS_ADJUSTABLE,
    energy.dbo.FN_SAFE_DT(CAST(s.FATURA_TARIHI_ AS DATETIME2))              AS FATURA_TARIHI,
    TRY_CAST(s.FATURA_BEDELI_ AS DECIMAL(18, 0))                            AS FATURA_BEDELI,
    TRY_CAST(s.FATURA_BEDELI_KDV_ AS DECIMAL(18, 0))                        AS FATURA_BEDELI_KDV,
    TRY_CAST(s.FATURA_NUMARASI_ AS DECIMAL(18, 0))                          AS FATURA_NUMARASI,
    CAST(NULL AS DATETIME)                                                  AS STARTTIME,
    CAST(NULL AS DATETIME)                                                  AS ENDTIME,
    CAST(NULL AS INT)                                                       AS OLDPROJECT_ID,
    CAST(NULL AS INT)                                                       AS PROJECTLINE_ID,
    CAST(NULL AS NVARCHAR(100))                                             AS OLD_PROJECT_CODE,
    CAST(NULL AS INT)                                                       AS OLD_PROJECT_YEAR,
    CAST(NULL AS INT)                                                       AS ENGINEERID,
    CAST(NULL AS INT)                                                       AS ENGINEERLREF
FROM izgazMGR.dbo.II_APPOINTMENT s
WHERE s.ID BETWEEN 1 AND 2147483647;
GO

EXEC dbo.SP_MIG_II_APPOINTMENT_VALIDATE_ALL @RaiseOnMissing = 0;
GO

PRINT '532_II_APPOINTMENT__setup OK';
GO
