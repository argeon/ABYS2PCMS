/* ============================================================
   FILE : prodEnergy/00_mig_step_log__setup.sql
   MANUEL adim takibi — otomatik runner YOK
   Her adim sonrasi: 00_mig_step_log__mark.sql ile isaretle
   ============================================================ */
USE energy;
GO

IF OBJECT_ID('energy.dbo.MIG_STEP_LOG', 'U') IS NULL
BEGIN
    CREATE TABLE energy.dbo.MIG_STEP_LOG (
        LOG_ID        BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        STEP_ID       VARCHAR(16)  NOT NULL,   -- B0, C20, E590, ...
        STEP_NAME     NVARCHAR(200) NOT NULL,
        HOST          NVARCHAR(64)  NULL,
        STARTED_AT    DATETIME2(3)  NULL,
        FINISHED_AT   DATETIME2(3)  NULL,
        STATUS        VARCHAR(16)   NOT NULL,  -- START|OK|FAIL|SKIP
        ROWCOUNT_NOTE NVARCHAR(200) NULL,
        DURATION_SEC  INT NULL,
        NOTE          NVARCHAR(500) NULL,
        OPERATOR      NVARCHAR(64)  NULL
    );
    CREATE NONCLUSTERED INDEX IX_MIG_STEP_LOG_STEP
        ON energy.dbo.MIG_STEP_LOG (STEP_ID, FINISHED_AT DESC);
END
GO

PRINT 'MIG_STEP_LOG hazir — takip: SELECT * FROM energy.dbo.MIG_STEP_LOG ORDER BY LOG_ID';
GO
