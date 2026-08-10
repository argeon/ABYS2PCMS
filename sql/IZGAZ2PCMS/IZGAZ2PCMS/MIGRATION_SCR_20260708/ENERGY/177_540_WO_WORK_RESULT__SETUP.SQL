/* ============================================================
   SCRIPT_ID : WO_WORK_RESULT_SETUP
   SCRIPT_NO : 540
   FILE      : 540_WO_WORK_RESULT__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.WO_WORK_RESULT
--   → energy.dbo.LS_005_01_WO_WORK_RESULT
--
-- Pass 1 dump-style:
--   - ABYS_* bridge kolonlari eklenir
--   - FK/prm/meter JOIN yok (proje sonu wire)
--   - WORK_ID = LS_005_01_CS_APPOINTMENT.LREF (WO_WORK.ID, direkt)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_WO_WORK_RESULT', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_005_01_WO_WORK_RESULT bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- ABYS bridge kolonlari (idempotent)
-- ------------------------------------------------------------
DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(200) NOT NULL);

INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 (N'ABYS_ID',                     N'INT NULL'),
 (N'ABYS_WORK_ID',                N'INT NULL'),
 (N'ABYS_ASSIGNEE_USER_ID',       N'INT NULL'),
 (N'ABYS_ASSIGNEE_USER_ID_2',     N'INT NULL'),
 (N'ABYS_CREATED_USER_ID',        N'INT NULL'),
 (N'ABYS_UPDATED_USER_ID',        N'INT NULL'),
 (N'ABYS_CAUSE_RESULT_ID',        N'INT NULL'),
 (N'ABYS_CAUSE_RESULT_REASON_ID', N'INT NULL'),
 (N'ABYS_C_METER_ID',             N'INT NULL'),
 (N'ABYS_M_METER_ID',             N'INT NULL'),
 (N'ABYS_WAREHOUSE_SHELF_ID',     N'INT NULL');

SELECT @Sql = @Sql + N'
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(''energy.dbo.LS_005_01_WO_WORK_RESULT'')
      AND name = ''' + COL_NAME + N'''
)
    ALTER TABLE energy.dbo.LS_005_01_WO_WORK_RESULT ADD ' + COL_NAME + N' ' + COL_DEF + N';'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_WO_WORK_RESULT')
      AND name = 'UX_LS005_WO_WORK_RESULT_ABYS_ID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_LS005_WO_WORK_RESULT_ABYS_ID
        ON energy.dbo.LS_005_01_WO_WORK_RESULT (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Validate
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_WO_WORK_RESULT_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.WO_WORK_RESULT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.WO_WORK_RESULT bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('ID'),('WORK_ID'),('CAUSE_RESULT_ID'),('CAUSE_RESULT_REASON_ID'),
            ('COMPLETED_DATE'),('ASSIGNEE_USER_ID'),('DESCRIPTION'),
            ('C_METER_NUMBER'),('C_METER_MARK_ID'),('C_METER_MODEL_ID'),
            ('C_INDEX'),('C_CORRECTED_INDEX'),('C_PRODUCTION_YEAR'),
            ('C_COMMUNUCATION_MODULE_ID'),('C_CORRECTOR_MODULE_ID'),
            ('C_CONSUMPTION'),('C_METER_TYPE_ID'),
            ('M_METER_ID'),('M_INDEX'),('M_CORRECTED_INDEX'),
            ('M_COMMUNUCATION_MODULE_ID'),('M_CORRECTOR_MODULE_ID'),
            ('I_AGREEMENT_NUMBER'),('I_CUSTOMER_NAME'),('I_SERVICE_BOX_CODE'),
            ('I_DOOR_NUMBER'),('I_FLAT_NUMBER'),('I_FLOOR_NUMBER'),('I_METER_NUMBER'),
            ('O_CUTTING_SERIAL_NUMBER'),('O_CUTTING_TYPE_ID'),
            ('O_VALVE_ARM_STATUS'),('O_IS_METER_INTERFERE'),('O_HAS_SEAL'),
            ('PROBLEM_DESCRIPTION'),
            ('CREATED_USER_ID'),('CREATED_TIMESTAMP'),
            ('UPDATED_USER_ID'),('UPDATED_TIMESTAMP'),('VERSION'),
            ('C_IS_BROKEN'),('I_MINUTE_NUMBER'),('I_MINUTE_DATE'),
            ('ASSIGNEE_USER_ID_2'),('LONGITUDE'),('LATITUDE'),
            ('CONTROL_CAUSE_ID'),('CONTROL_PRM_ID'),('CONTROL_DESCRIPTION'),
            ('C_METER_ID'),('IS_PICTURE_SEND_LATER'),('IS_APPROVED'),
            ('C_STAMP_YEAR'),('C_METER_DIAMETER_ID'),('C_METER_LINK_DIAMETER_ID'),
            ('METER_ADDRESS'),('C_RETROKIT_INDEX'),('M_RETROKIT_INDEX'),
            ('WAREHOUSE_SHELF_ID'),('SACK_NUMBER'),('REKOR_SEAL_NUMBER')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'WO_WORK_RESULT' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'WO_WORK_RESULT eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'WO_WORK_RESULT kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_WO_WORK_RESULT_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_WO_WORK_RESULT', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_WO_WORK_RESULT bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('WORK_ID'),('CAUSE_RESULT_ID'),('CAUSE_RESULT_REASON_ID'),
            ('COMPLETED_DATE'),('ASSIGNEE_USER_ID'),('DESCRIPTION'),
            ('C_METER_NUMBER'),('C_METER_MARK_ID'),('C_METER_MODEL_ID'),
            ('C_INDEX'),('C_CORRECTED_INDEX'),('C_PRODUCTION_YEAR'),
            ('C_COMMUNUCATION_MODULE_ID'),('C_CORRECTOR_MODULE_ID'),
            ('C_CONSUMPTION'),('C_METER_TYPE_ID'),
            ('M_METER_ID'),('M_INDEX'),('M_CORRECTED_INDEX'),
            ('M_COMMUNUCATION_MODULE_ID'),('M_CORRECTOR_MODULE_ID'),
            ('I_AGREEMENT_NUMBER'),('I_CUSTOMER_NAME'),('I_SERVICE_BOX_CODE'),
            ('I_DOOR_NUMBER'),('I_FLAT_NUMBER'),('I_FLOOR_NUMBER'),('I_METER_NUMBER'),
            ('O_CUTTING_SERIAL_NUMBER'),('O_CUTTING_TYPE_ID'),
            ('O_VALVE_ARM_STATUS'),('O_IS_METER_INTERFERE'),('O_HAS_SEAL'),
            ('PROBLEM_DESCRIPTION'),
            ('CREATED_USER_ID'),('CREATED_TIMESTAMP'),
            ('UPDATED_USER_ID'),('UPDATED_TIMESTAMP'),('VERSION'),
            ('C_IS_BROKEN'),('I_MINUTE_NUMBER'),('I_MINUTE_DATE'),
            ('ASSIGNEE_USER_ID_2'),('LONGITUDE'),('LATITUDE'),
            ('CONTROL_CAUSE_ID'),('CONTROL_PRM_ID'),('CONTROL_DESCRIPTION'),
            ('C_METER_ID'),('IS_PICTURE_SEND_LATER'),('IS_APPROVED'),
            ('C_STAMP_YEAR'),('C_METER_DIAMETER_ID'),('C_METER_LINK_DIAMETER_ID'),
            ('METER_ADDRESS'),('C_RETROKIT_INDEX'),('M_RETROKIT_INDEX'),
            ('WAREHOUSE_SHELF_ID'),('SACK_NUMBER'),('REKOR_SEAL_NUMBER'),
            ('C_FIRST_INDEX'),('C_CORRECTOR_FIRST_INDEX'),('C_CORRECTOR_LAST_INDEX'),
            ('TERMINAL_CODE'),('SUBSCRIBER_LOCATION'),('LAST_INDEX'),
            ('METER_STATUS_CODE'),('IS_BARCODE_READING'),
            ('M_METER_NUMBER'),('M_PRODUCTION_YEAR'),('M_METER_MARK_ID'),('M_METER_TYPE_ID'),
            ('ABYS_ID'),('ABYS_WORK_ID'),
            ('ABYS_ASSIGNEE_USER_ID'),('ABYS_ASSIGNEE_USER_ID_2'),
            ('ABYS_CREATED_USER_ID'),('ABYS_UPDATED_USER_ID'),
            ('ABYS_CAUSE_RESULT_ID'),('ABYS_CAUSE_RESULT_REASON_ID'),
            ('ABYS_C_METER_ID'),('ABYS_M_METER_ID'),('ABYS_WAREHOUSE_SHELF_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_WO_WORK_RESULT')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_WO_WORK_RESULT eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_WO_WORK_RESULT hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_WO_WORK_RESULT_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_WO_WORK_RESULT_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_WO_WORK_RESULT_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    RETURN @Rc;
END
GO

EXEC dbo.SP_MIG_WO_WORK_RESULT_VALIDATE_ALL @RaiseOnMissing = 0;
GO

PRINT '540_WO_WORK_RESULT__setup OK';
GO
