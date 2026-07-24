/* ============================================================
   SCRIPT_ID : REF_IT_USER_SETUP
   SCRIPT_NO : 110
   FILE      : 110_REF_IT_USER__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- IT_USER → LS_USER hedef hazırlığı
-- ============================================================
USE energy;
GO

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_USER')
      AND name = 'IX_LS_USER_ABYS_USER_ID'
)
    DROP INDEX IX_LS_USER_ABYS_USER_ID ON energy.dbo.LS_USER;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_USER') AND name = 'ABYS_USER_ID'
)
    ALTER TABLE energy.dbo.LS_USER DROP COLUMN ABYS_USER_ID;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_USER') AND name = 'ABYS_ID'
)
    ALTER TABLE energy.dbo.LS_USER ADD ABYS_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_USER') AND name = 'REGISTER_ID'
)
    ALTER TABLE energy.dbo.LS_USER ADD REGISTER_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_USER') AND name = 'REGISTER_TABLE'
)
    ALTER TABLE energy.dbo.LS_USER ADD REGISTER_TABLE VARCHAR(10) NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_USER') AND name = 'USER_TYPE'
)
    ALTER TABLE energy.dbo.LS_USER ADD USER_TYPE TINYINT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('energy.dbo.LS_USER') AND name = 'WORK_PLACE_ID'
)
    ALTER TABLE energy.dbo.LS_USER ADD WORK_PLACE_ID INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_USER')
      AND name = 'IX_LS_USER_ABYS_ID'
)
    CREATE NONCLUSTERED INDEX IX_LS_USER_ABYS_ID
        ON energy.dbo.LS_USER (ABYS_ID) INCLUDE (USERID);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_USER')
      AND name = 'UX_LS_USER_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_USER_ABYS_ID
        ON energy.dbo.LS_USER (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

CREATE OR ALTER FUNCTION dbo.FN_SAFE_SMALLDT_USR (@DT DATETIME2)
RETURNS SMALLDATETIME
AS
BEGIN
    RETURN CASE
        WHEN @DT IS NULL                 THEN NULL
        WHEN @DT < '1900-01-01 00:00:00' THEN NULL
        WHEN @DT > '2079-06-06 23:59:00' THEN NULL
        ELSE CAST(@DT AS SMALLDATETIME)
    END;
END
GO

-- ------------------------------------------------------------
-- ABYS user ID → PCMS LS_USER.USERID
-- Kural: PCMS_USERID = ABYS_USER_ID + 10000
-- Native PCMS bandi: USERID 1..10000 (offset uygulanmaz; seed ADDUSER=1 vb.)
-- ABYS_* audit kolonlarina offset uygulanmaz.
-- ------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.FN_MIG_MAP_USER_USERID (@AbysUserId INT)
RETURNS INT
AS
BEGIN
    IF @AbysUserId IS NULL
        RETURN NULL;

    RETURN @AbysUserId + 10000;
END
GO

-- Eski isim: deterministik offset'e yonlendirir (JOIN yok).
CREATE OR ALTER FUNCTION dbo.FN_MIG_RESOLVE_USER_USERID (@AbysUserId INT)
RETURNS INT
AS
BEGIN
    RETURN energy.dbo.FN_MIG_MAP_USER_USERID(@AbysUserId);
END
GO

