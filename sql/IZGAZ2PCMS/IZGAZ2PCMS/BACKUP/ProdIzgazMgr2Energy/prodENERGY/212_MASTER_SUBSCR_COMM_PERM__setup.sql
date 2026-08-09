/* ============================================================
   SCRIPT_ID : MASTER_SUBSCR_COMM_PERM_SETUP
   SCRIPT_NO : 212
   FILE      : 212_MASTER_SUBSCR_COMM_PERM__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.CS_REGISTER_COMM_PERMISSION
--   → energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION
--
-- Kolon eşlemesi:
--   ID                           ← ID                 (IDENTITY_INSERT)
--   SUBSCRIBER_COMMUNICATION_ID  ← REGISTER_COMMUNICATION_ID
--   PERMISSION_SOURCE_ID         ← PERMISSION_SOURCE_ID
--   PERMISSION_TYPE              ← PERMISSION_TYPE
--                                  (1=SMS; 2=IVR; 3=MAIL; 4=ADDRESS)
--   IP_ADDRESS                   ← IP_ADDRESS
--   CREATED_USER_ID              ← FN_MIG_MAP_USER_USERID(CREATED_USER_ID)
--   CREATED_TIMESTAMP            ← CREATED_TIMESTAMP
--   UPDATED_USER_ID              ← FN_MIG_MAP_USER_USERID(UPDATED_USER_ID)
--   UPDATED_TIMESTAMP            ← UPDATED_TIMESTAMP
--   DELETED_*                    ← NULL
--   IS_ACTIVE                    ← ISNULL(IS_COMMUNICATION_PERMIT,
--                                         ISNULL(IS_COMMINICATION_PERMIT, 1))
--   VERSION                      ← VERSION
--   INTEGRATION_CODE             ← LEFT(INTEGRATION_CODE, 100)
--   INTEGRATION_DATE             ← INTEGRATION_DATE
--   IS_INTEGRATION_PERMISSION    ← IS_COMMINICATION_PERMIT (legacy typo kolon)
--   PCMS_IS_PERMISSION           ← IS_COMMUNICATION_PERMIT
--   PCMS_PERMISSION_DATE         ← NULL
--
-- Önkoşul : 210/211 (LS_005_SUBSCRIBER_COMMUNICATION, LREF = kaynak ID)
-- FK      : PERMISSION_SOURCE_ID → LS_SUBSCRIBER_PERMISSION_SOURCE_PRM.ID
--           (CS_REG_PERM_SOURCE_PRM ID'leri birebir varsayılır)
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_REG_COMM_PERM_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.CS_REGISTER_COMM_PERMISSION', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.CS_REGISTER_COMM_PERMISSION bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME
        FROM (VALUES
            ('ID'), ('REGISTER_COMMUNICATION_ID'),
            ('PERMISSION_TYPE'), ('PERMISSION_SOURCE_ID'),
            ('IP_ADDRESS'),
            ('CREATED_USER_ID'), ('CREATED_TIMESTAMP'),
            ('UPDATED_USER_ID'), ('UPDATED_TIMESTAMP'),
            ('VERSION'),
            ('IS_COMMINICATION_PERMIT'),
            ('INTEGRATION_CODE'), ('INTEGRATION_DATE'),
            ('IS_COMMUNICATION_PERMIT')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo'
          AND t.name = 'CS_REGISTER_COMM_PERMISSION'
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'CS_REGISTER_COMM_PERMISSION eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1
            RAISERROR(@Msg, 16, 1);
        ELSE
            SELECT @Msg AS VALIDATION_MESSAGE;
        RETURN 1;
    END

    IF OBJECT_ID('energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION bulunamadi. Once 210/211 calistirin.', 16, 1);
        RETURN 1;
    END

    IF OBJECT_ID('energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION bulunamadi.', 16, 1);
        RETURN 1;
    END

    IF OBJECT_ID('energy.dbo.LS_SUBSCRIBER_PERMISSION_SOURCE_PRM', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_SUBSCRIBER_PERMISSION_SOURCE_PRM bulunamadi.', 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'CS_REGISTER_COMM_PERMISSION kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER VIEW dbo.VW_MIG_REG_COMM_PERM_SOURCE
AS
SELECT
    CAST(s.ID AS INT)                                                       AS ABYS_ID,
    CAST(s.REGISTER_COMMUNICATION_ID AS INT)                                AS SUBSCRIBER_COMMUNICATION_ID,
    CAST(s.PERMISSION_SOURCE_ID AS INT)                                     AS PERMISSION_SOURCE_ID,
    CAST(s.PERMISSION_TYPE AS INT)                                          AS PERMISSION_TYPE,
    LEFT(s.IP_ADDRESS, 50)                                                  AS IP_ADDRESS,
    energy.dbo.FN_MIG_MAP_USER_USERID(
        CAST(TRY_CAST(s.CREATED_USER_ID AS BIGINT) AS INT)
    )                                                                       AS CREATED_USER_ID,
    ISNULL(
        energy.dbo.FN_SAFE_DT(CAST(s.CREATED_TIMESTAMP AS DATETIME2)),
        GETDATE()
    )                                                                       AS CREATED_TIMESTAMP,
    energy.dbo.FN_MIG_MAP_USER_USERID(
        CAST(TRY_CAST(s.UPDATED_USER_ID AS BIGINT) AS INT)
    )                                                                       AS UPDATED_USER_ID,
    energy.dbo.FN_SAFE_DT(CAST(s.UPDATED_TIMESTAMP AS DATETIME2))           AS UPDATED_TIMESTAMP,
    CAST(NULL AS INT)                                                       AS DELETED_USER_ID,
    CAST(NULL AS DATETIME)                                                  AS DELETED_TIMESTAMP,
    CAST(
        ISNULL(
            TRY_CAST(s.IS_COMMUNICATION_PERMIT AS INT),
            ISNULL(TRY_CAST(s.IS_COMMINICATION_PERMIT AS INT), 1)
        ) AS BIT
    )                                                                       AS IS_ACTIVE,
    CAST(s.VERSION AS INT)                                                  AS VERSION,
    LEFT(s.INTEGRATION_CODE, 100)                                           AS INTEGRATION_CODE,
    energy.dbo.FN_SAFE_DT(CAST(s.INTEGRATION_DATE AS DATETIME2))            AS INTEGRATION_DATE,
    CAST(TRY_CAST(s.IS_COMMINICATION_PERMIT AS INT) AS BIT)                 AS IS_INTEGRATION_PERMISSION,
    CAST(TRY_CAST(s.IS_COMMUNICATION_PERMIT AS INT) AS BIT)                 AS PCMS_IS_PERMISSION,
    CAST(NULL AS DATETIME)                                                  AS PCMS_PERMISSION_DATE
FROM izgazMGR.dbo.CS_REGISTER_COMM_PERMISSION s
INNER JOIN energy.dbo.LS_005_SUBSCRIBER_COMMUNICATION p
    ON p.LREF = CAST(s.REGISTER_COMMUNICATION_ID AS INT)
INNER JOIN energy.dbo.LS_SUBSCRIBER_PERMISSION_SOURCE_PRM src
    ON src.ID = CAST(s.PERMISSION_SOURCE_ID AS INT)
WHERE s.PERMISSION_TYPE IS NOT NULL
  AND s.PERMISSION_SOURCE_ID IS NOT NULL;
GO

IF OBJECT_ID('dbo.SP_MIGRATE_CS_REGISTER_COMM_PERMISSION', 'P') IS NOT NULL
    EXEC sys.sp_refreshsqlmodule N'dbo.SP_MIGRATE_CS_REGISTER_COMM_PERMISSION';
GO

EXEC dbo.SP_MIG_REG_COMM_PERM_VALIDATE_SOURCE @RaiseOnMissing = 0;
GO

PRINT '212_MASTER_SUBSCR_COMM_PERM__setup OK';
GO
