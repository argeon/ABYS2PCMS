/* ============================================================
   SCRIPT_ID : SPEFEE_SETUP
   SCRIPT_NO : 584
   FILE      : 584_SPEFEE__setup.sql
   VERSION   : 2
   ============================================================ */
-- v2: VW_MIG_SPEFEE_SOURCE ABYS_ID dedupe (kaynak 2x yukleme)
-- ============================================================
-- izgazMGR.dbo.LS_SPEFEE → energy.dbo.LS_005_01_SPEFEE
--   LREF ← ABYS_ID (IDENTITY_INSERT)
--   ABYS_* bridge kolonlari hedefe eklenir
--
-- Kaynak: Oracle CTAS (SMS.CS_ACCOUNT_ADD → MIGRATION.LS_SPEFEE)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_SPEFEE', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_005_01_SPEFEE bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- ABYS_* bridge kolonlari (idempotent)
-- ------------------------------------------------------------
DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(200) NOT NULL);

INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 (N'ABYS_ID',                   N'BIGINT NULL'),
 (N'ABYS_AGREEMENT_ID',         N'BIGINT NULL'),
 (N'ABYS_ACCOUNT_ID',           N'BIGINT NULL'),
 (N'ABYS_INCOME_ID',            N'BIGINT NULL'),
 (N'ABYS_PERIOD',               N'INT NULL'),
 (N'ABYS_ACTION_DATE',          N'DATETIME2(0) NULL'),
 (N'ABYS_WORK_ORDER_ID',        N'BIGINT NULL'),
 (N'ABYS_QUANTITY',             N'DECIMAL(7,2) NULL'),
 (N'ABYS_ACCRUE_GROUP_ID',      N'BIGINT NULL'),
 (N'ABYS_CASH_ID',              N'BIGINT NULL'),
 (N'ABYS_RECEIPT_SERIAL',       N'NVARCHAR(2) NULL'),
 (N'ABYS_RECEIPT_NUMBER',       N'DECIMAL(25,0) NULL'),
 (N'ABYS_ANALYSIS_ACCOUNT_ID',  N'BIGINT NULL'),
 (N'ABYS_VERSION',              N'BIGINT NULL'),
 (N'ABYS_TRANSACTION_CODE',     N'NVARCHAR(20) NULL'),
 (N'ABYS_CREATED_USER_ID',      N'BIGINT NULL'),
 (N'ABYS_UPDATED_USER_ID',      N'BIGINT NULL'),
 (N'ABYS_READING_ID',           N'BIGINT NULL');

SELECT @Sql = @Sql + N'
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(''energy.dbo.LS_005_01_SPEFEE'')
      AND name = ''' + COL_NAME + N'''
)
    ALTER TABLE energy.dbo.LS_005_01_SPEFEE ADD ' + COL_NAME + N' ' + COL_DEF + N';'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_SPEFEE')
      AND name = 'UX_LS_005_01_SPEFEE_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS_005_01_SPEFEE_ABYS_ID
        ON energy.dbo.LS_005_01_SPEFEE (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_SPEFEE')
      AND name = 'IX_LS_005_01_SPEFEE_ABYS_AGR'
)
    CREATE NONCLUSTERED INDEX IX_LS_005_01_SPEFEE_ABYS_AGR
        ON energy.dbo.LS_005_01_SPEFEE (ABYS_AGREEMENT_ID)
        INCLUDE (LREF, CLIENTREF, OWNERREF)
        WHERE ABYS_AGREEMENT_ID IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_SPEFEE')
      AND name = 'IX_LS_005_01_SPEFEE_ABYS_ACC'
)
    CREATE NONCLUSTERED INDEX IX_LS_005_01_SPEFEE_ABYS_ACC
        ON energy.dbo.LS_005_01_SPEFEE (ABYS_ACCOUNT_ID)
        WHERE ABYS_ACCOUNT_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Kaynak kolon dogrulama
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_SPEFEE_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_SPEFEE', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_SPEFEE bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('LINEEXP'), ('INVOICEREF'), ('CUSTNAME'),
            ('CLIENTREF'), ('OWNERREF'), ('CLIENTTYPE'),
            ('TLTOTAL'), ('TAX'), ('GRANDTOTAL'),
            ('ADDDATE'), ('ADDUSER'), ('CANCELLED'), ('UPDDATE'), ('UPDUSER'),
            ('PRINTED'), ('IU_TYPE'), ('STYPE'), ('READING_ID'), ('STATUS'),
            ('INSTALLMENT_NO'), ('INSTALLMENT_NR'),
            ('ABYS_ID'), ('ABYS_AGREEMENT_ID'), ('ABYS_ACCOUNT_ID'),
            ('ABYS_INCOME_ID'), ('ABYS_PERIOD'), ('ABYS_ACTION_DATE'),
            ('ABYS_WORK_ORDER_ID'), ('ABYS_QUANTITY'), ('ABYS_ACCRUE_GROUP_ID'),
            ('ABYS_CASH_ID'), ('ABYS_RECEIPT_SERIAL'), ('ABYS_RECEIPT_NUMBER'),
            ('ABYS_ANALYSIS_ACCOUNT_ID'), ('ABYS_VERSION'),
            ('ABYS_TRANSACTION_CODE'), ('ABYS_CREATED_USER_ID'),
            ('ABYS_UPDATED_USER_ID'), ('ABYS_READING_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'LS_SPEFEE' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_SPEFEE eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_SPEFEE kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_SPEFEE_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_SPEFEE', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_SPEFEE bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('LREF'), ('STYPE_OLD'), ('LINEEXP'), ('INVOICEREF'), ('CUSTNAME'),
            ('CLIENTREF'), ('OWNERREF'), ('CLIENTTYPE'),
            ('TLTOTAL'), ('TAX'), ('GRANDTOTAL'),
            ('ADDDATE'), ('ADDUSER'), ('CANCELLED'), ('UPDDATE'), ('UPDUSER'),
            ('READ_TRANSFERREF'), ('READ_NO'), ('PRINTED'),
            ('IU_TYPE'), ('IND_DIFF'), ('STYPE'), ('READING_ID'), ('STATUS'),
            ('INSTALLMENT_NO'), ('INSTALLMENT_NR'),
            ('ABYS_ID'), ('ABYS_AGREEMENT_ID'), ('ABYS_ACCOUNT_ID'),
            ('ABYS_INCOME_ID'), ('ABYS_PERIOD'), ('ABYS_ACTION_DATE'),
            ('ABYS_WORK_ORDER_ID'), ('ABYS_QUANTITY'), ('ABYS_ACCRUE_GROUP_ID'),
            ('ABYS_CASH_ID'), ('ABYS_RECEIPT_SERIAL'), ('ABYS_RECEIPT_NUMBER'),
            ('ABYS_ANALYSIS_ACCOUNT_ID'), ('ABYS_VERSION'),
            ('ABYS_TRANSACTION_CODE'), ('ABYS_CREATED_USER_ID'),
            ('ABYS_UPDATED_USER_ID'), ('ABYS_READING_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_SPEFEE')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_SPEFEE eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_SPEFEE hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

-- ------------------------------------------------------------
-- Kaynak view (kolon eslemesi tek nokta)
-- LREF <- ABYS_ID (IDENTITY_INSERT)
-- Not: izgazMGR.LS_SPEFEE ~2x duplicate satır (ayni ABYS_ID/LREF);
--      PARTITION BY ABYS_ID ile tek satir alinir → PK ihlali onlenir.
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.VW_MIG_SPEFEE_SOURCE
AS
SELECT
    CAST(s.ABYS_ID AS BIGINT)                                                   AS ABYS_ID,
    CAST(TRY_CAST(s.STYPE_OLD AS INT) AS TINYINT)                               AS STYPE_OLD,
    LEFT(s.LINEEXP, 100)                                                        AS LINEEXP,
    CAST(TRY_CAST(s.INVOICEREF AS BIGINT) AS INT)                               AS INVOICEREF,
    LEFT(s.CUSTNAME, 50)                                                        AS CUSTNAME,
    CAST(TRY_CAST(s.CLIENTREF AS BIGINT) AS INT)                                AS CLIENTREF,
    CAST(TRY_CAST(s.OWNERREF AS BIGINT) AS INT)                                 AS OWNERREF,
    CAST(ISNULL(TRY_CAST(s.CLIENTTYPE AS BIGINT), 91) AS TINYINT)               AS CLIENTTYPE,
    TRY_CAST(s.TLTOTAL AS FLOAT)                                                AS TLTOTAL,
    TRY_CAST(s.TAX AS FLOAT)                                                    AS TAX,
    TRY_CAST(s.GRANDTOTAL AS FLOAT)                                             AS GRANDTOTAL,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ADDDATE AS DATETIME2))                AS ADDDATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.ADDUSER AS BIGINT) AS INT)) AS ADDUSER,
    CAST(ISNULL(TRY_CAST(s.CANCELLED AS INT), 0) AS BIT)                        AS CANCELLED,
    energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.UPDDATE AS DATETIME2))                AS UPDDATE,
    energy.dbo.FN_MIG_MAP_USER_USERID(CAST(TRY_CAST(s.UPDUSER AS BIGINT) AS INT)) AS UPDUSER,
    CAST(TRY_CAST(s.READ_TRANSFERREF AS BIGINT) AS INT)                         AS READ_TRANSFERREF,
    CAST(TRY_CAST(s.READ_NO AS BIGINT) AS INT)                                  AS READ_NO,
    CAST(ISNULL(TRY_CAST(s.PRINTED AS INT), 0) AS BIT)                          AS PRINTED,
    CAST(ISNULL(TRY_CAST(s.IU_TYPE AS BIGINT), 0) AS INT)                       AS IU_TYPE,
    CAST(TRY_CAST(s.IND_DIFF AS BIGINT) AS INT)                                 AS IND_DIFF,
    CAST(ISNULL(TRY_CAST(s.STYPE AS BIGINT), 6) AS INT)                         AS STYPE,
    CAST(TRY_CAST(s.READING_ID AS BIGINT) AS INT)                               AS READING_ID,
    CAST(TRY_CAST(s.STATUS AS INT) AS INT)                                      AS STATUS,
    CAST(TRY_CAST(s.INSTALLMENT_NO AS INT) AS INT)                              AS INSTALLMENT_NO,
    CAST(TRY_CAST(s.INSTALLMENT_NR AS INT) AS INT)                              AS INSTALLMENT_NR,
    CAST(s.ABYS_AGREEMENT_ID AS BIGINT)                                         AS ABYS_AGREEMENT_ID,
    CAST(s.ABYS_ACCOUNT_ID AS BIGINT)                                           AS ABYS_ACCOUNT_ID,
    CAST(s.ABYS_INCOME_ID AS BIGINT)                                            AS ABYS_INCOME_ID,
    CAST(s.ABYS_PERIOD AS INT)                                                  AS ABYS_PERIOD,
    CAST(s.ABYS_ACTION_DATE AS DATETIME2(0))                                    AS ABYS_ACTION_DATE,
    CAST(s.ABYS_WORK_ORDER_ID AS BIGINT)                                        AS ABYS_WORK_ORDER_ID,
    CAST(s.ABYS_QUANTITY AS DECIMAL(7,2))                                       AS ABYS_QUANTITY,
    CAST(s.ABYS_ACCRUE_GROUP_ID AS BIGINT)                                      AS ABYS_ACCRUE_GROUP_ID,
    CAST(s.ABYS_CASH_ID AS BIGINT)                                              AS ABYS_CASH_ID,
    LEFT(s.ABYS_RECEIPT_SERIAL, 2)                                              AS ABYS_RECEIPT_SERIAL,
    CAST(s.ABYS_RECEIPT_NUMBER AS DECIMAL(25,0))                                AS ABYS_RECEIPT_NUMBER,
    CAST(s.ABYS_ANALYSIS_ACCOUNT_ID AS BIGINT)                                  AS ABYS_ANALYSIS_ACCOUNT_ID,
    CAST(s.ABYS_VERSION AS BIGINT)                                              AS ABYS_VERSION,
    LEFT(s.ABYS_TRANSACTION_CODE, 20)                                           AS ABYS_TRANSACTION_CODE,
    CAST(s.ABYS_CREATED_USER_ID AS BIGINT)                                      AS ABYS_CREATED_USER_ID,
    CAST(s.ABYS_UPDATED_USER_ID AS BIGINT)                                      AS ABYS_UPDATED_USER_ID,
    CAST(s.ABYS_READING_ID AS BIGINT)                                           AS ABYS_READING_ID
FROM (
    SELECT
        raw.*,
        ROW_NUMBER() OVER (
            PARTITION BY raw.ABYS_ID
            ORDER BY raw.LREF ASC
        ) AS rn
    FROM izgazMGR.dbo.LS_SPEFEE raw
    WHERE raw.ABYS_ID IS NOT NULL
      AND raw.ABYS_ID BETWEEN 1 AND 2147483647
) s
WHERE s.rn = 1;
GO

IF OBJECT_ID('dbo.SP_MIGRATE_LS_SPEFEE', 'P') IS NOT NULL
    EXEC sys.sp_refreshsqlmodule N'dbo.SP_MIGRATE_LS_SPEFEE';
GO

EXEC dbo.SP_MIG_SPEFEE_VALIDATE_SOURCE @RaiseOnMissing = 0;
EXEC dbo.SP_MIG_SPEFEE_VALIDATE_TARGET @RaiseOnMissing = 0;
GO
