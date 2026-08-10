-- =============================================================================
-- prodREADY_ENERGY3007 / 05_collation_cp1254.sql
-- energy DB default → SQL_Latin1_General_CP1254_CI_AS
-- Bağımlılık drop → ALTER → recreate
-- Çalıştır: sqlcmd -S 172.16.1.195 -d master -I -i 05_collation_cp1254.sql
-- (-I = QUOTED_IDENTIFIER ON — computed/filtered index recreate için zorunlu)
-- UYARI: SINGLE_USER + ROLLBACK IMMEDIATE — aktif oturumlar kesilir
-- NOT: Bu script yalnızca DB default collation değiştirir.
--      Mevcut kolonlar CP1 kalır; kolon bazlı CP1254 ayrı adımdır.
-- =============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

USE energy;
GO

PRINT '========== E3007-05 DROP collation blockers ==========';

-- 1) Indexes that reference computed BNA_ID
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.mgg_cbs_kapi') AND name = N'IX_BNA_KP_20251011')
    DROP INDEX IX_BNA_KP_20251011 ON dbo.mgg_cbs_kapi;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.mgg_cbs_kapi') AND name = N'IX_mgg_cbs_kapi_BNA_ID')
    DROP INDEX IX_mgg_cbs_kapi_BNA_ID ON dbo.mgg_cbs_kapi;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.mgg_cbs_kapi') AND name = N'IX_mgg_cbs_kapi_COMPOSITE')
    DROP INDEX IX_mgg_cbs_kapi_COMPOSITE ON dbo.mgg_cbs_kapi;
PRINT 'Dropped BNA_ID indexes';

-- 2) Computed columns (DB collation dependent via CONVERT(varchar,...))
IF COL_LENGTH(N'dbo.mgg_cbs_kapi', N'BNA_ID') IS NOT NULL
    ALTER TABLE dbo.mgg_cbs_kapi DROP COLUMN BNA_ID;
IF COL_LENGTH(N'dbo.LS_005_01_PREPAID_MISSINGCARD', N'CUSTOMERXNO') IS NOT NULL
    ALTER TABLE dbo.LS_005_01_PREPAID_MISSINGCARD DROP COLUMN CUSTOMERXNO;
IF COL_LENGTH(N'dbo.LS_005_01_PREPAID_SALES', N'CUSTOMERXNO') IS NOT NULL
    ALTER TABLE dbo.LS_005_01_PREPAID_SALES DROP COLUMN CUSTOMERXNO;
PRINT 'Dropped computed columns';

-- 3) Filtered indexes / unique indexes reported as collation-dependent
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LS_005_01_AGR') AND name = N'UX_LS_005_01_AGR_ABYS_MIG')
    DROP INDEX UX_LS_005_01_AGR_ABYS_MIG ON dbo.LS_005_01_AGR;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LS_005_01_AGR') AND name = N'IX_LS_005_01_AGR_TP2_ABYS')
    DROP INDEX IX_LS_005_01_AGR_TP2_ABYS ON dbo.LS_005_01_AGR;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.MIG_TABLE_RUN') AND name = N'UX_MIG_TABLE_RUN_ACTIVE')
    DROP INDEX UX_MIG_TABLE_RUN_ACTIVE ON dbo.MIG_TABLE_RUN;
PRINT 'Dropped filtered indexes';

-- 4) Check constraints
DECLARE @sql nvarchar(max) = N'';
SELECT @sql += N'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id)) + N'.'
             + QUOTENAME(OBJECT_NAME(parent_object_id)) + N' DROP CONSTRAINT ' + QUOTENAME(name) + N';'
FROM sys.check_constraints
WHERE name LIKE N'CK_LS00[1-5]_SUBSCRIBER%'
   OR name LIKE N'CK_LS_ACCRUE_TYPE_PRM%'
   OR name LIKE N'CK_LS__ATP%';
IF LEN(@sql) > 0 EXEC sp_executesql @sql;
PRINT 'Dropped check constraints';
GO

USE master;
GO

PRINT '========== E3007-05 ALTER DATABASE COLLATE ==========';
ALTER DATABASE energy SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
ALTER DATABASE energy COLLATE SQL_Latin1_General_CP1254_CI_AS;
ALTER DATABASE energy SET MULTI_USER;
GO

SELECT name, collation_name, user_access_desc, state_desc
FROM sys.databases WHERE name = N'energy';
GO

USE energy;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

PRINT '========== E3007-05 RECREATE objects ==========';

-- Computed columns
IF COL_LENGTH(N'dbo.mgg_cbs_kapi', N'BNA_ID') IS NULL
    ALTER TABLE dbo.mgg_cbs_kapi ADD BNA_ID AS (TRY_CAST([AbysBinaKodu] AS int)) PERSISTED;
IF COL_LENGTH(N'dbo.LS_005_01_PREPAID_MISSINGCARD', N'CUSTOMERXNO') IS NULL
    ALTER TABLE dbo.LS_005_01_PREPAID_MISSINGCARD ADD CUSTOMERXNO AS (
        CONVERT(bigint,
            CONVERT(varchar, [CUSTOMERTYPE], 0)
          + CONVERT(varchar, RIGHT(REPLICATE('0', 8) + RTRIM(LTRIM([CUSTOMERREF])), 8), 0),
            0)
    ) PERSISTED;
IF COL_LENGTH(N'dbo.LS_005_01_PREPAID_SALES', N'CUSTOMERXNO') IS NULL
    ALTER TABLE dbo.LS_005_01_PREPAID_SALES ADD CUSTOMERXNO AS (
        CONVERT(bigint,
            CONVERT(varchar, [CUSTOMERTYPE], 0)
          + CONVERT(varchar, RIGHT(REPLICATE('0', 8) + RTRIM(LTRIM([CUSTOMERREF])), 8), 0),
            0)
    ) PERSISTED;
PRINT 'Recreated computed columns';

-- BNA_ID indexes
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.mgg_cbs_kapi') AND name = N'IX_mgg_cbs_kapi_BNA_ID')
    CREATE NONCLUSTERED INDEX IX_mgg_cbs_kapi_BNA_ID ON dbo.mgg_cbs_kapi (BNA_ID, SirketKodu)
    INCLUDE (BinaAdi, CaddeSokakKodu, DisKapiNo);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.mgg_cbs_kapi') AND name = N'IX_mgg_cbs_kapi_COMPOSITE')
    CREATE NONCLUSTERED INDEX IX_mgg_cbs_kapi_COMPOSITE ON dbo.mgg_cbs_kapi (BNA_ID, SirketKodu)
    INCLUDE (AbysBinaKodu, BinaAdi, CaddeSokakKodu, CbsKapiId, DisKapiNo);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.mgg_cbs_kapi') AND name = N'IX_BNA_KP_20251011')
    CREATE NONCLUSTERED INDEX IX_BNA_KP_20251011 ON dbo.mgg_cbs_kapi (SirketKodu)
    INCLUDE (BNA_ID, CaddeSokakKodu);
PRINT 'Recreated BNA_ID indexes';

-- Filtered indexes (STATUS filter: kolon CP1 ise once CP1254'e cevir)
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.MIG_TABLE_RUN') AND name = N'STATUS'
      AND collation_name = N'SQL_Latin1_General_CP1_CI_AS'
)
BEGIN
    DECLARE @st nvarchar(400) = N'ALTER TABLE dbo.MIG_TABLE_RUN ALTER COLUMN STATUS varchar('
        + CAST((SELECT max_length FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.MIG_TABLE_RUN') AND name = N'STATUS') AS varchar(10))
        + N') COLLATE SQL_Latin1_General_CP1254_CI_AS'
        + CASE WHEN EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.MIG_TABLE_RUN') AND name = N'STATUS' AND is_nullable = 0)
               THEN N' NOT NULL' ELSE N' NULL' END;
    EXEC sp_executesql @st;
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LS_005_01_AGR') AND name = N'UX_LS_005_01_AGR_ABYS_MIG')
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_005_01_AGR_ABYS_MIG
        ON dbo.LS_005_01_AGR (ABYS_MIG_ROW_ID) WHERE ([ABYS_MIG_ROW_ID] IS NOT NULL);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LS_005_01_AGR') AND name = N'IX_LS_005_01_AGR_TP2_ABYS')
    CREATE NONCLUSTERED INDEX IX_LS_005_01_AGR_TP2_ABYS
        ON dbo.LS_005_01_AGR (TP2, ABYS_ID) WHERE ([ABYS_ID] IS NOT NULL);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.MIG_TABLE_RUN') AND name = N'UX_MIG_TABLE_RUN_ACTIVE')
    CREATE UNIQUE NONCLUSTERED INDEX UX_MIG_TABLE_RUN_ACTIVE
        ON dbo.MIG_TABLE_RUN (MIGRATION_CODE, PHASE) WHERE ([STATUS] = 'RUNNING');
PRINT 'Recreated filtered indexes';

-- Check constraints (firm 001-005 + accrue/action)
DECLARE @ck nvarchar(max) = N'';
DECLARE @f char(3);
DECLARE @i int = 1;
WHILE @i <= 5
BEGIN
    SET @f = RIGHT('00' + CAST(@i AS varchar(2)), 3);
    IF OBJECT_ID(N'dbo.LS_' + @f + N'_SUBSCRIBER_COMMUNICATION', N'U') IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_LS' + @f + N'_SUBSCRIBER_IS_VERIFIED')
            SET @ck += N'ALTER TABLE dbo.LS_' + @f + N'_SUBSCRIBER_COMMUNICATION ADD CONSTRAINT CK_LS'
                     + @f + N'_SUBSCRIBER_IS_VERIFIED CHECK ([IS_VERIFIED]=(1) OR [IS_VERIFIED]=(0));';
        IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_LS' + @f + N'_SUBSCRIBER_RC_IS_DEFAULT')
            SET @ck += N'ALTER TABLE dbo.LS_' + @f + N'_SUBSCRIBER_COMMUNICATION ADD CONSTRAINT CK_LS'
                     + @f + N'_SUBSCRIBER_RC_IS_DEFAULT CHECK ([IS_DEFAULT]=(1) OR [IS_DEFAULT]=(0));';
        IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_LS' + @f + N'_SUBSCRIBER_RC_COMMUNICATION_TYPE')
            SET @ck += N'ALTER TABLE dbo.LS_' + @f + N'_SUBSCRIBER_COMMUNICATION ADD CONSTRAINT CK_LS'
                     + @f + N'_SUBSCRIBER_RC_COMMUNICATION_TYPE CHECK ([COMMUNICATION_TYPE] IN (1,2,3,4,5,6,7,8));';
    END
    SET @i += 1;
END
IF OBJECT_ID(N'dbo.LS_ACCRUE_TYPE_PRM', N'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_LS_ACCRUE_TYPE_PRM_LREF_CODE')
        SET @ck += N'ALTER TABLE dbo.LS_ACCRUE_TYPE_PRM ADD CONSTRAINT CK_LS_ACCRUE_TYPE_PRM_LREF_CODE CHECK ([LREF]=[CODE]);';
    IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_LS_ACCRUE_TYPE_PRM_STATUS')
        SET @ck += N'ALTER TABLE dbo.LS_ACCRUE_TYPE_PRM ADD CONSTRAINT CK_LS_ACCRUE_TYPE_PRM_STATUS CHECK ([STATUS]=(1) OR [STATUS]=(-1));';
END
IF OBJECT_ID(N'dbo.LS_ACTION_TYPE_PRM', N'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_LS__ATP_STATUS')
        SET @ck += N'ALTER TABLE dbo.LS_ACTION_TYPE_PRM ADD CONSTRAINT CK_LS__ATP_STATUS CHECK ([STATUS]=(-1) OR [STATUS]=(1));';
    IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_LS__ATP_TYPE')
        SET @ck += N'ALTER TABLE dbo.LS_ACTION_TYPE_PRM ADD CONSTRAINT CK_LS__ATP_TYPE CHECK ([TYPE]>=(1) AND [TYPE]<=(8));';
END
IF LEN(@ck) > 0 EXEC sp_executesql @ck;
PRINT 'Recreated check constraints';

SELECT DB_NAME() AS db, DATABASEPROPERTYEX(DB_NAME(), 'Collation') AS db_collation;
SELECT
    SUM(CASE WHEN collation_name = N'SQL_Latin1_General_CP1254_CI_AS' THEN 1 ELSE 0 END) AS cols_cp1254,
    SUM(CASE WHEN collation_name = N'SQL_Latin1_General_CP1_CI_AS' THEN 1 ELSE 0 END) AS cols_cp1,
    SUM(CASE WHEN collation_name IS NOT NULL THEN 1 ELSE 0 END) AS cols_string_total
FROM sys.columns;

PRINT '========== E3007-05 DONE ==========';
PRINT 'NOT: Mevcut kolon collation''lari degismez; sadece DB default CP1254 olur.';
PRINT 'Kolon bazli CP1254 donusumu ayri adim gerektirir.';
GO
