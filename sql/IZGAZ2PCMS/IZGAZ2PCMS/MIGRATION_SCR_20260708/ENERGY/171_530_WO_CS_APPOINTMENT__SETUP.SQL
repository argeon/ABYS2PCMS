/* ============================================================
   SCRIPT_ID : WO_CS_APPOINTMENT_SETUP
   SCRIPT_NO : 530
   FILE      : 530_WO_CS_APPOINTMENT__setup.sql
   VERSION   : 4
   ============================================================ */
-- v4: IX_LS005_CS_APPOINTMENT_AGRID (wire JOIN / AGRID remap)
-- v3: ABYS_UNIT_TYPE_ID aktarımdan cikarildi (kaynakta yok)
-- v2: CUSTNAME NVARCHAR(250) ALTER
-- ============================================================
-- izgazMGR.dbo.LS_WORK
--   → energy.dbo.LS_005_01_CS_APPOINTMENT
--
-- Pass 1 dump-style:
--   - ABYS_* bridge kolonlari eklenir
--   - FK/prm/meter/AGR JOIN yok (proje sonu wire)
--   - LREF = LS_WORK.LREF (= WO_WORK.ID)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_CS_APPOINTMENT', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_005_01_CS_APPOINTMENT bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- CUSTNAME: canli kisa (orn. 50) → NVARCHAR(250)
-- ------------------------------------------------------------
IF EXISTS (
    SELECT 1
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_CS_APPOINTMENT')
      AND c.name = 'CUSTNAME'
      AND (
            TYPE_NAME(c.user_type_id) <> 'nvarchar'
         OR (c.max_length > 0 AND c.max_length < 500)  -- 250 char = 500 bytes; MAX=-1 dokunma
      )
)
BEGIN
    ALTER TABLE energy.dbo.LS_005_01_CS_APPOINTMENT
        ALTER COLUMN CUSTNAME NVARCHAR(250) NULL;
END
GO

-- ------------------------------------------------------------
-- ABYS bridge kolonlari (idempotent)
-- ------------------------------------------------------------
DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(200) NOT NULL);

INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 (N'ABYS_ID',                         N'INT NULL'),
 (N'ABYS_QUARTER_STREET_ID',          N'INT NULL'),
 (N'ABYS_METER_STATUS_ID',            N'INT NULL'),
 (N'ABYS_TARIFF_TYPE_ID',             N'INT NULL'),
 (N'ABYS_LAST_CORRECTOR_INDEX',       N'NUMERIC(15,3) NULL'),
 (N'ABYS_SKB_TARIFF_TYPE_ID',         N'INT NULL'),
 (N'ABYS_IS_DEBT_PAYED',              N'BIT NULL'),
 (N'ABYS_ILLEGAL_USE_ID',             N'INT NULL'),
 (N'ABYS_PRIORITY_ID',                N'INT NULL'),
 (N'ABYS_WORK_ORDER_NUMBER',          N'INT NULL'),
 (N'ABYS_REGISTER_ID',                N'BIGINT NULL'),
 (N'ABYS_INSTALLATION_ID',            N'INT NULL'),
 (N'ABYS_SUBSCRIBER_TYPE_ID',         N'INT NULL'),
 (N'ABYS_UNIT_NUMBER',                N'NVARCHAR(20) NULL'),
 (N'ABYS_DO_PRINT',                   N'BIT NULL'),
 (N'ABYS_AREA_ID',                    N'INT NULL'),
 (N'ABYS_SENDING_TYPE',               N'TINYINT NULL'),
 (N'ABYS_DESCRIPTION',                N'NVARCHAR(MAX) NULL'),
 (N'ABYS_CHANGE_ASSIGNEE_USER_ID',    N'INT NULL'),
 (N'ABYS_CONTROLLED_WORK_ID',         N'INT NULL'),
 (N'ABYS_IS_DESTRUCTION_BUILDING',    N'BIT NULL'),
 (N'ABYS_LAST_CUTTING_TYPE_ID',       N'INT NULL'),
 (N'ABYS_LAST_CUTTING_DATE',          N'DATETIME2 NULL'),
 (N'ABYS_INSTALLATION_STATUS_ID',     N'SMALLINT NULL'),
 (N'ABYS_PAYMENT_STATUS',             N'TINYINT NULL'),
 (N'ABYS_POOL_ID',                    N'INT NULL'),
 (N'ABYS_INTEGRATION_CODE',           N'NVARCHAR(20) NULL'),
 (N'ABYS_CANCELLATION_USER_ID',       N'INT NULL'),
 (N'ABYS_VERSION',                    N'INT NULL'),
 (N'ABYS_CONTROLLED_READING_ID',      N'BIGINT NULL'),
 (N'ABYS_LOCATION_WKT',               N'NVARCHAR(MAX) NULL'),
 (N'ABYS_INCOME_LIST',                N'NVARCHAR(MAX) NULL'),
 (N'ABYS_WORK_REQUEST_ID',            N'BIGINT NULL'),
 (N'ABYS_LAST_RETROKIT_INDEX',        N'INT NULL'),
 (N'ABYS_WORK_EAM_ID',                N'INT NULL'),
 (N'ABYS_ASSIGNEE_TEAM_ID',           N'INT NULL'),
 (N'ABYS_DISCOVERY_WORK_ID',          N'INT NULL'),
 (N'ABYS_CREDIT',                     N'DECIMAL(16,6) NULL'),
 (N'ABYS_LAST_INDEX',                 N'NUMERIC(15,3) NULL'),
 (N'ABYS_LAST_ELECTRONIC_INDEX',      N'NUMERIC(15,3) NULL'),
 (N'ABYS_CANCEL_DESCRIPTION_FULL',    N'NVARCHAR(MAX) NULL'),
 (N'ABYS_APPUSER',                    N'INT NULL'),
 (N'ABYS_ADDUSER',                    N'INT NULL'),
 (N'ABYS_UPDUSER',                    N'INT NULL'),
 (N'ABYS_PRCUSER',                    N'INT NULL'),
 (N'ABYS_WORK_ORDER_PROCESS_USER_ID', N'INT NULL');

SELECT @Sql = @Sql + N'
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(''energy.dbo.LS_005_01_CS_APPOINTMENT'')
      AND name = ''' + COL_NAME + N'''
)
    ALTER TABLE energy.dbo.LS_005_01_CS_APPOINTMENT ADD ' + COL_NAME + N' ' + COL_DEF + N';'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_CS_APPOINTMENT')
      AND name = 'UX_LS005_CS_APPOINTMENT_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS005_CS_APPOINTMENT_ABYS_ID
        ON energy.dbo.LS_005_01_CS_APPOINTMENT (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

-- Wire: agr.ABYS_ID = agt.AGRID → AGRID remap; sonra agt.AGRID = agr.LREF
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_CS_APPOINTMENT')
      AND name = 'IX_LS005_CS_APPOINTMENT_AGRID'
)
    CREATE NONCLUSTERED INDEX IX_LS005_CS_APPOINTMENT_AGRID
        ON energy.dbo.LS_005_01_CS_APPOINTMENT (AGRID)
        WHERE AGRID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Validate
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_CS_APPOINTMENT_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_WORK', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_WORK bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('ABYS_ID'),('TYPEID'),('AGRID'),('FITNO'),('BINAID'),
            ('SDATE'),('STATID'),('APPUSER'),('ADDR'),
            ('CNTID'),('CNTSN'),('CNTMODEL'),('READENDEX'),('CURRENTENDEX'),
            ('PRCUSER'),('PRCDATE'),('ADDDATE'),('ADDUSER'),('UPDUSER'),('UPDDATE'),
            ('CANCELLED'),('CANCEL_DATE'),('CANCEL_DESCRIPTION'),
            ('DAY15DEBTREF'),('OBJECTIONREF'),('CLOSEREF'),
            ('CUSTREF'),('CUSTYPE'),('IS_INDUSTRY'),('CUSTNAME'),('IS_PREPAID'),('DELETED'),
            ('INVCOUNT'),('INVTOTAL'),('PAIDDATE'),('GUVENCE_BEDELI'),('USULSUZINVCOUNT'),
            ('LAWSTATID'),('READ_STATUS'),('CNT_STATUS'),('LASTREAD_DATE'),('DATE_DIFF'),
            ('TP1'),('AGRSTATID'),('ASSINGDATE'),('ASSINGSTATUS'),('ASSINGPERSON'),
            ('WO_DATE'),('WO_APPOINTMENT_DATE'),('PARENT_ID'),('WO_TYPE_ID'),('WO_CAUSE_ID'),
            ('WORK_ORDER_PROCESS_ID'),('WORK_ORDER_PROCESS_TIMESTAMP'),('WORK_ORDER_PROCESS_USER_ID'),
            ('ABYS_QUARTER_STREET_ID'),('ABYS_METER_STATUS_ID'),
            ('ABYS_TARIFF_TYPE_ID'),('ABYS_LAST_CORRECTOR_INDEX'),('ABYS_SKB_TARIFF_TYPE_ID'),
            ('ABYS_IS_DEBT_PAYED'),('ABYS_ILLEGAL_USE_ID'),('ABYS_PRIORITY_ID'),
            ('ABYS_WORK_ORDER_NUMBER'),('ABYS_REGISTER_ID'),('ABYS_INSTALLATION_ID'),
            ('ABYS_SUBSCRIBER_TYPE_ID'),('ABYS_UNIT_NUMBER'),('ABYS_DO_PRINT'),('ABYS_AREA_ID'),
            ('ABYS_SENDING_TYPE'),('ABYS_DESCRIPTION'),('ABYS_CHANGE_ASSIGNEE_USER_ID'),
            ('ABYS_CONTROLLED_WORK_ID'),('ABYS_IS_DESTRUCTION_BUILDING'),
            ('ABYS_LAST_CUTTING_TYPE_ID'),('ABYS_LAST_CUTTING_DATE'),
            ('ABYS_INSTALLATION_STATUS_ID'),('ABYS_PAYMENT_STATUS'),('ABYS_POOL_ID'),
            ('ABYS_INTEGRATION_CODE'),('ABYS_CANCELLATION_USER_ID'),('ABYS_VERSION'),
            ('ABYS_CONTROLLED_READING_ID'),('ABYS_LOCATION_WKT'),('ABYS_INCOME_LIST'),
            ('ABYS_WORK_REQUEST_ID'),('ABYS_LAST_RETROKIT_INDEX'),('ABYS_WORK_EAM_ID'),
            ('ABYS_ASSIGNEE_TEAM_ID'),('ABYS_DISCOVERY_WORK_ID'),('ABYS_CREDIT'),
            ('ABYS_LAST_INDEX'),('ABYS_LAST_ELECTRONIC_INDEX'),('ABYS_CANCEL_DESCRIPTION_FULL')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'LS_WORK' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_WORK eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_WORK kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_CS_APPOINTMENT_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_CS_APPOINTMENT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_CS_APPOINTMENT bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('TYPEID'),('AGRID'),('FITNO'),('BINAID'),
            ('SDATE'),('STATID'),('APPUSER'),('ADDR'),
            ('CNTID'),('CNTSN'),('CNTMODEL'),('READENDEX'),('CURRENTENDEX'),
            ('PRCUSER'),('PRCDATE'),('ADDDATE'),('ADDUSER'),('UPDUSER'),('UPDDATE'),
            ('CANCELLED'),('CANCEL_DATE'),('CANCEL_DESCRIPTION'),
            ('DAY15DEBTREF'),('OBJECTIONREF'),('CLOSEREF'),
            ('CUSTREF'),('CUSTYPE'),('IS_INDUSTRY'),('CUSTNAME'),('IS_PREPAID'),('DELETED'),
            ('INVCOUNT'),('INVTOTAL'),('PAIDDATE'),('GUVENCE_BEDELI'),('USULSUZINVCOUNT'),
            ('LAWSTATID'),('READ_STATUS'),('CNT_STATUS'),('LASTREAD_DATE'),('DATE_DIFF'),
            ('TP1'),('AGRSTATID'),('ASSINGDATE'),('ASSINGSTATUS'),('ASSINGPERSON'),
            ('WO_DATE'),('WO_APPOINTMENT_DATE'),('PARENT_ID'),('WO_TYPE_ID'),('WO_CAUSE_ID'),
            ('WORK_ORDER_PROCESS_ID'),('WORK_ORDER_PROCESS_TIMESTAMP'),('WORK_ORDER_PROCESS_USER_ID'),
            ('ABYS_ID'),('ABYS_QUARTER_STREET_ID'),('ABYS_METER_STATUS_ID'),
            ('ABYS_TARIFF_TYPE_ID'),('ABYS_LAST_CORRECTOR_INDEX'),('ABYS_SKB_TARIFF_TYPE_ID'),
            ('ABYS_IS_DEBT_PAYED'),('ABYS_ILLEGAL_USE_ID'),('ABYS_PRIORITY_ID'),
            ('ABYS_WORK_ORDER_NUMBER'),('ABYS_REGISTER_ID'),('ABYS_INSTALLATION_ID'),
            ('ABYS_SUBSCRIBER_TYPE_ID'),('ABYS_UNIT_NUMBER'),('ABYS_DO_PRINT'),('ABYS_AREA_ID'),
            ('ABYS_SENDING_TYPE'),('ABYS_DESCRIPTION'),('ABYS_CHANGE_ASSIGNEE_USER_ID'),
            ('ABYS_CONTROLLED_WORK_ID'),('ABYS_IS_DESTRUCTION_BUILDING'),
            ('ABYS_LAST_CUTTING_TYPE_ID'),('ABYS_LAST_CUTTING_DATE'),
            ('ABYS_INSTALLATION_STATUS_ID'),('ABYS_PAYMENT_STATUS'),('ABYS_POOL_ID'),
            ('ABYS_INTEGRATION_CODE'),('ABYS_CANCELLATION_USER_ID'),('ABYS_VERSION'),
            ('ABYS_CONTROLLED_READING_ID'),('ABYS_LOCATION_WKT'),('ABYS_INCOME_LIST'),
            ('ABYS_WORK_REQUEST_ID'),('ABYS_LAST_RETROKIT_INDEX'),('ABYS_WORK_EAM_ID'),
            ('ABYS_ASSIGNEE_TEAM_ID'),('ABYS_DISCOVERY_WORK_ID'),('ABYS_CREDIT'),
            ('ABYS_LAST_INDEX'),('ABYS_LAST_ELECTRONIC_INDEX'),('ABYS_CANCEL_DESCRIPTION_FULL'),
            ('ABYS_APPUSER'),('ABYS_ADDUSER'),('ABYS_UPDUSER'),('ABYS_PRCUSER'),
            ('ABYS_WORK_ORDER_PROCESS_USER_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_CS_APPOINTMENT')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_CS_APPOINTMENT eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_CS_APPOINTMENT hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_CS_APPOINTMENT_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_CS_APPOINTMENT_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_CS_APPOINTMENT_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    RETURN @Rc;
END
GO

EXEC dbo.SP_MIG_CS_APPOINTMENT_VALIDATE_ALL @RaiseOnMissing = 0;
GO

PRINT '530_WO_CS_APPOINTMENT__setup OK';
GO
