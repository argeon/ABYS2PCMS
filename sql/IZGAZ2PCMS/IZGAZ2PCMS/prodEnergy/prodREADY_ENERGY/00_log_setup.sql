/* ============================================================
   prodREADY_ENERGY / 00_log_setup
   MIG_STEP_LOG + SP_MIG_LOG_STEP (anlasilir, kalici)
   Format (Messages):
     2026-07-24 20:40:01.123 | E590 | START | eksilten_ALL | ...
     2026-07-24 20:45:10.456 | E590 | OK    | eksilten_ALL | cnt=... | 312s
   Izle: EXEC SP_MIG_LOG_STATUS;  veya  @99_log_status.sql
   ============================================================ */
USE energy;
GO
SET NOCOUNT ON;

IF OBJECT_ID('dbo.MIG_STEP_LOG', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_STEP_LOG (
        LOG_ID        BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        STEP_ID       VARCHAR(16)   NOT NULL,
        STEP_NAME     NVARCHAR(200) NOT NULL,
        HOST          NVARCHAR(64)  NULL,
        STARTED_AT    DATETIME2(3)  NULL,
        FINISHED_AT   DATETIME2(3)  NULL,
        STATUS        VARCHAR(16)   NOT NULL,  -- START|OK|FAIL|INFO|GATE_PASS|GATE_FAIL
        ROWCOUNT_NOTE NVARCHAR(400) NULL,
        DURATION_SEC  INT NULL,
        NOTE          NVARCHAR(500) NULL,
        OPERATOR      NVARCHAR(64)  NULL
    );
    CREATE NONCLUSTERED INDEX IX_MIG_STEP_LOG_STEP
        ON dbo.MIG_STEP_LOG (STEP_ID, LOG_ID DESC);
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_LOG_STEP
    @STEP_ID       VARCHAR(16),
    @STEP_NAME     NVARCHAR(200),
    @STATUS        VARCHAR(16),          -- START | OK | FAIL | INFO | GATE_PASS | GATE_FAIL
    @ROWCOUNT_NOTE NVARCHAR(400) = NULL,
    @NOTE          NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @Host NVARCHAR(64) = HOST_NAME(),
        @Op   NVARCHAR(64) = SUSER_SNAME(),
        @Msg  NVARCHAR(800),
        @Dur  INT = NULL,
        @Ts   VARCHAR(30) = CONVERT(VARCHAR(30), SYSDATETIME(), 121);

    IF OBJECT_ID('dbo.MIG_STEP_LOG', 'U') IS NULL
    BEGIN
        RAISERROR('MIG_STEP_LOG yok — once 00_log_setup.sql', 16, 1);
        RETURN;
    END

    IF UPPER(@STATUS) = 'START'
    BEGIN
        INSERT INTO dbo.MIG_STEP_LOG (
            STEP_ID, STEP_NAME, HOST, STARTED_AT, STATUS, OPERATOR, NOTE, ROWCOUNT_NOTE
        )
        VALUES (
            UPPER(@STEP_ID), @STEP_NAME, @Host, SYSDATETIME(), 'START', @Op, @NOTE, @ROWCOUNT_NOTE
        );

        SET @Msg = @Ts + N' | ' + UPPER(@STEP_ID) + N' | START     | ' + @STEP_NAME
                 + ISNULL(N' | ' + @NOTE, N'');
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        RETURN;
    END

    /* Son START kaydini kapat */
    UPDATE TOP (1) s
    SET s.FINISHED_AT   = SYSDATETIME(),
        s.STATUS        = UPPER(@STATUS),
        s.ROWCOUNT_NOTE = COALESCE(@ROWCOUNT_NOTE, s.ROWCOUNT_NOTE),
        s.NOTE          = COALESCE(@NOTE, s.NOTE),
        s.DURATION_SEC  = DATEDIFF(SECOND, s.STARTED_AT, SYSDATETIME()),
        @Dur            = DATEDIFF(SECOND, s.STARTED_AT, SYSDATETIME())
    FROM dbo.MIG_STEP_LOG s
    WHERE s.LOG_ID = (
        SELECT MAX(LOG_ID) FROM dbo.MIG_STEP_LOG
        WHERE STEP_ID = UPPER(@STEP_ID) AND STATUS = 'START'
    );

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.MIG_STEP_LOG (
            STEP_ID, STEP_NAME, HOST, STARTED_AT, FINISHED_AT, STATUS,
            ROWCOUNT_NOTE, DURATION_SEC, OPERATOR, NOTE
        )
        VALUES (
            UPPER(@STEP_ID), @STEP_NAME, @Host, SYSDATETIME(), SYSDATETIME(), UPPER(@STATUS),
            @ROWCOUNT_NOTE, 0, @Op, @NOTE
        );
        SET @Dur = 0;
    END

    SET @Msg = @Ts + N' | ' + UPPER(@STEP_ID)
             + N' | ' + LEFT(UPPER(@STATUS) + N'          ', 10)
             + N' | ' + @STEP_NAME
             + ISNULL(N' | ' + @ROWCOUNT_NOTE, N'')
             + CASE WHEN @Dur IS NOT NULL THEN N' | ' + CAST(@Dur AS NVARCHAR(20)) + N's' ELSE N'' END
             + ISNULL(N' | ' + @NOTE, N'');
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_LOG_STATUS
    @TOP INT = 40
AS
BEGIN
    SET NOCOUNT ON;
    PRINT '========== MIG_STEP_LOG son kayitlar ==========';
    SELECT TOP (@TOP)
        LOG_ID, STEP_ID, STATUS, STEP_NAME,
        ROWCOUNT_NOTE, DURATION_SEC,
        STARTED_AT, FINISHED_AT, NOTE, OPERATOR, HOST
    FROM dbo.MIG_STEP_LOG WITH (NOLOCK)
    ORDER BY LOG_ID DESC;

    PRINT '========== Son durum (STEP bazinda) ==========';
    ;WITH x AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY STEP_ID ORDER BY LOG_ID DESC) AS rn
        FROM dbo.MIG_STEP_LOG WITH (NOLOCK)
    )
    SELECT STEP_ID, STATUS, STEP_NAME, ROWCOUNT_NOTE, DURATION_SEC, FINISHED_AT, NOTE
    FROM x WHERE rn = 1
    ORDER BY STEP_ID;

    PRINT '========== FAIL / GATE_FAIL ==========';
    SELECT LOG_ID, STEP_ID, STATUS, STEP_NAME, ROWCOUNT_NOTE, NOTE, FINISHED_AT
    FROM dbo.MIG_STEP_LOG WITH (NOLOCK)
    WHERE STATUS IN ('FAIL', 'GATE_FAIL')
    ORDER BY LOG_ID DESC;
END
GO

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + ' | LOG | OK | 00_log_setup | SP_MIG_LOG_STEP + SP_MIG_LOG_STATUS';
GO
