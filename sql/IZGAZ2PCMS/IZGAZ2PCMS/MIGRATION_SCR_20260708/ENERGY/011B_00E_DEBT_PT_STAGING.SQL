/* =============================================================================
   prodREADY_ENERGY3007 / 00e_debt_pt_staging.sql
   575 — fiziksel staging (#temp YOK; paket kurali)
   Neden: 610/597/611 fiziksel MIG_*_STG_*; 575 v3c key-list hâlâ #MIG_DEBT_*
          kalmisti (tempdb collation / kural geri kalmis).
   Kullanim: SP basinda TRUNCATE; SERIAL (paralel worker paylasmasin)
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + ' | 00e DEBT_PT STAGING START';

IF OBJECT_ID('dbo.MIG_575_STG_BATCH_KEYS', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_575_STG_BATCH_KEYS (
        LREF BIGINT NOT NULL,
        CONSTRAINT PK_MIG_575_STG_BATCH_KEYS PRIMARY KEY CLUSTERED (LREF)
    );
    PRINT 'CREATE MIG_575_STG_BATCH_KEYS';
END
ELSE
    PRINT 'SKIP MIG_575_STG_BATCH_KEYS (exists)';

IF OBJECT_ID('dbo.MIG_575_STG_KEYS', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_575_STG_KEYS (
        LREF BIGINT NOT NULL,
        CONSTRAINT PK_MIG_575_STG_KEYS PRIMARY KEY CLUSTERED (LREF)
    );
    PRINT 'CREATE MIG_575_STG_KEYS';
END
ELSE
    PRINT 'SKIP MIG_575_STG_KEYS (exists)';

/* PK zaten LREF seek; ekstra covering IX (join / EXISTS) */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MIG_575_STG_BATCH_KEYS')
      AND name = N'IX_MIG_575_STG_BATCH_KEYS_LREF'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_MIG_575_STG_BATCH_KEYS_LREF
        ON dbo.MIG_575_STG_BATCH_KEYS (LREF);
    PRINT 'CREATE IX_MIG_575_STG_BATCH_KEYS_LREF';
END

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.MIG_575_STG_KEYS')
      AND name = N'IX_MIG_575_STG_KEYS_LREF'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_MIG_575_STG_KEYS_LREF
        ON dbo.MIG_575_STG_KEYS (LREF);
    PRINT 'CREATE IX_MIG_575_STG_KEYS_LREF';
END

TRUNCATE TABLE dbo.MIG_575_STG_BATCH_KEYS;
TRUNCATE TABLE dbo.MIG_575_STG_KEYS;

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + ' | 00e DEBT_PT STAGING OK';
GO
