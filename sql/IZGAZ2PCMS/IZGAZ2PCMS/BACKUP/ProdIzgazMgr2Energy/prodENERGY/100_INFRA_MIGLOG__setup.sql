/* ============================================================
   SCRIPT_ID : INFRA_MIGLOG_SETUP
   SCRIPT_NO : 100
   FILE      : 100_INFRA_MIGLOG__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- Ortak migrasyon log şeması (tüm tablo SP'leri için)
-- Veritabanı: energy
-- ============================================================
USE energy;
GO

-- Eski tabloya özel log yapıları (varsa kaldır)
IF OBJECT_ID('energy.dbo.MIG_LOG_IT_USER', 'U') IS NOT NULL
    DROP TABLE energy.dbo.MIG_LOG_IT_USER;
GO
IF OBJECT_ID('energy.dbo.MIG_CHECKPOINT_IT_USER', 'U') IS NOT NULL
    DROP TABLE energy.dbo.MIG_CHECKPOINT_IT_USER;
GO

-- ------------------------------------------------------------
-- MIG_RUN — çalıştırma özeti (başlangıç, bitiş, toplam sayılar)
-- ------------------------------------------------------------
IF OBJECT_ID('energy.dbo.MIG_RUN', 'U') IS NULL
BEGIN
    CREATE TABLE energy.dbo.MIG_RUN (
        RUN_ID           UNIQUEIDENTIFIER NOT NULL
            CONSTRAINT PK_MIG_RUN PRIMARY KEY,
        MIGRATION_CODE   VARCHAR(50)      NOT NULL,
        SOURCE_DB        SYSNAME          NOT NULL,
        SOURCE_TABLE     SYSNAME          NOT NULL,
        TARGET_TABLE     SYSNAME          NOT NULL,
        RUN_PHASE        VARCHAR(20)      NOT NULL,
        EXEC_MODE        VARCHAR(20)      NOT NULL,
        BATCH_SIZE       INT              NOT NULL,
        STATUS           VARCHAR(25)      NOT NULL,
        STARTED_AT       DATETIME2(3)     NOT NULL
            CONSTRAINT DF_MIG_RUN_STARTED DEFAULT SYSDATETIME(),
        FINISHED_AT      DATETIME2(3)     NULL,
        SOURCE_ROW_COUNT BIGINT           NULL,
        TARGET_ROW_COUNT BIGINT           NULL,
        INSERTED_COUNT   BIGINT           NOT NULL
            CONSTRAINT DF_MIG_RUN_INSERTED DEFAULT 0,
        UPDATED_COUNT    BIGINT           NOT NULL
            CONSTRAINT DF_MIG_RUN_UPDATED DEFAULT 0,
        SKIPPED_COUNT    BIGINT           NOT NULL
            CONSTRAINT DF_MIG_RUN_SKIPPED DEFAULT 0,
        ERROR_COUNT      BIGINT           NOT NULL
            CONSTRAINT DF_MIG_RUN_ERROR DEFAULT 0,
        LAST_BRIDGE_KEY  BIGINT           NULL,
        MAX_BRIDGE_KEY   BIGINT           NULL,
        ERROR_MSG        NVARCHAR(4000)   NULL,
        HOST_NAME        NVARCHAR(128)    NULL
            CONSTRAINT DF_MIG_RUN_HOST DEFAULT HOST_NAME(),
        APP_USER         NVARCHAR(128)    NULL
            CONSTRAINT DF_MIG_RUN_USER DEFAULT SUSER_SNAME()
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.MIG_RUN')
      AND name = 'IX_MIG_RUN_CODE_STARTED'
)
    CREATE INDEX IX_MIG_RUN_CODE_STARTED
        ON energy.dbo.MIG_RUN (MIGRATION_CODE, STARTED_AT DESC);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.MIG_RUN')
      AND name = 'IX_MIG_RUN_STATUS'
)
    CREATE INDEX IX_MIG_RUN_STATUS
        ON energy.dbo.MIG_RUN (STATUS, STARTED_AT DESC);
GO

-- ------------------------------------------------------------
-- MIG_TABLE_RUN — phase bazlı ilerleme + resume
-- ------------------------------------------------------------
IF OBJECT_ID('energy.dbo.MIG_TABLE_RUN', 'U') IS NULL
BEGIN
    CREATE TABLE energy.dbo.MIG_TABLE_RUN (
        TABLE_RUN_ID     BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_MIG_TABLE_RUN PRIMARY KEY,
        RUN_ID           UNIQUEIDENTIFIER NOT NULL,
        MIGRATION_CODE   VARCHAR(50)      NOT NULL,
        PHASE            VARCHAR(20)      NOT NULL,
        STATUS           VARCHAR(20)      NOT NULL,
        STARTED_AT       DATETIME2(3)     NOT NULL
            CONSTRAINT DF_MIG_TABLE_RUN_STARTED DEFAULT SYSDATETIME(),
        FINISHED_AT      DATETIME2(3)     NULL,
        LAST_BRIDGE_KEY  BIGINT           NOT NULL
            CONSTRAINT DF_MIG_TABLE_RUN_BRIDGE DEFAULT 0,
        BATCH_NO         INT              NOT NULL
            CONSTRAINT DF_MIG_TABLE_RUN_BATCH DEFAULT 0,
        SOURCE_ROW_COUNT BIGINT           NULL,
        INSERTED_COUNT   BIGINT           NOT NULL
            CONSTRAINT DF_MIG_TABLE_RUN_INSERTED DEFAULT 0,
        SKIPPED_COUNT    BIGINT           NOT NULL
            CONSTRAINT DF_MIG_TABLE_RUN_SKIPPED DEFAULT 0,
        ERROR_COUNT      BIGINT           NOT NULL
            CONSTRAINT DF_MIG_TABLE_RUN_ERROR DEFAULT 0,
        UPDATED_AT       DATETIME2(3)     NOT NULL
            CONSTRAINT DF_MIG_TABLE_RUN_UPDATED DEFAULT SYSDATETIME(),
        CONSTRAINT FK_MIG_TABLE_RUN_RUN
            FOREIGN KEY (RUN_ID) REFERENCES energy.dbo.MIG_RUN (RUN_ID)
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.MIG_TABLE_RUN')
      AND name = 'IX_MIG_TABLE_RUN_RUN'
)
    CREATE INDEX IX_MIG_TABLE_RUN_RUN
        ON energy.dbo.MIG_TABLE_RUN (RUN_ID, PHASE);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.MIG_TABLE_RUN')
      AND name = 'UX_MIG_TABLE_RUN_ACTIVE'
)
    CREATE UNIQUE INDEX UX_MIG_TABLE_RUN_ACTIVE
        ON energy.dbo.MIG_TABLE_RUN (MIGRATION_CODE, PHASE)
        WHERE STATUS = 'RUNNING';
GO

-- ------------------------------------------------------------
-- MIG_BATCH_LOG — batch / tek satır detay
-- ------------------------------------------------------------
IF OBJECT_ID('energy.dbo.MIG_BATCH_LOG', 'U') IS NULL
BEGIN
    CREATE TABLE energy.dbo.MIG_BATCH_LOG (
        LOG_ID           BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_MIG_BATCH_LOG PRIMARY KEY,
        RUN_ID           UNIQUEIDENTIFIER NOT NULL,
        MIGRATION_CODE   VARCHAR(50)      NOT NULL,
        PHASE            VARCHAR(20)      NOT NULL,
        BATCH_NO         INT              NOT NULL,
        BRIDGE_FROM      BIGINT           NULL,
        BRIDGE_TO        BIGINT           NULL,
        SOURCE_ID        BIGINT           NULL,
        STATUS           VARCHAR(15)      NOT NULL,
        ROW_COUNT        INT              NULL,
        CUM_INSERTED     BIGINT           NULL,
        CUM_SKIPPED      BIGINT           NULL,
        CUM_ERROR        BIGINT           NULL,
        ELAPSED_MS       INT              NULL,
        ERROR_MSG        NVARCHAR(4000)   NULL,
        LOGGED_AT        DATETIME2(3)     NOT NULL
            CONSTRAINT DF_MIG_BATCH_LOGGED DEFAULT SYSDATETIME(),
        CONSTRAINT FK_MIG_BATCH_LOG_RUN
            FOREIGN KEY (RUN_ID) REFERENCES energy.dbo.MIG_RUN (RUN_ID)
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.MIG_BATCH_LOG')
      AND name = 'IX_MIG_BATCH_RUN'
)
    CREATE INDEX IX_MIG_BATCH_RUN
        ON energy.dbo.MIG_BATCH_LOG (RUN_ID, BATCH_NO);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('energy.dbo.MIG_BATCH_LOG')
      AND name = 'IX_MIG_BATCH_STATUS'
)
    CREATE INDEX IX_MIG_BATCH_STATUS
        ON energy.dbo.MIG_BATCH_LOG (MIGRATION_CODE, STATUS, LOGGED_AT DESC);
GO

