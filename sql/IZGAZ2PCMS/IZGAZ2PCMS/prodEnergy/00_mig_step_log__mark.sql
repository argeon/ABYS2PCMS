/* ============================================================
   FILE : prodEnergy/00_mig_step_log__mark.sql
   Manuel adim isaretle (SSMS'de STEP_ID / STATUS degistirip F5)

   Ornek:
     @STEP_ID='B0'  @STATUS='START'  → baslamadan
     @STEP_ID='B0'  @STATUS='OK'     @ROWCOUNT_NOTE=N'ix ok' → bitince
   ============================================================ */
USE energy;
GO

SET NOCOUNT ON;

DECLARE @STEP_ID       VARCHAR(16)   = N'B0';      -- <<< degistir
DECLARE @STEP_NAME     NVARCHAR(200) = N'pre_indexes';
DECLARE @STATUS        VARCHAR(16)   = N'START';    -- START | OK | FAIL | SKIP
DECLARE @ROWCOUNT_NOTE NVARCHAR(200) = NULL;
DECLARE @NOTE          NVARCHAR(500) = NULL;
DECLARE @OPERATOR      NVARCHAR(64)  = SUSER_SNAME();
DECLARE @HOST          NVARCHAR(64)  = HOST_NAME();

IF OBJECT_ID('energy.dbo.MIG_STEP_LOG', 'U') IS NULL
BEGIN
    RAISERROR('Once 00_mig_step_log__setup.sql calistir.', 16, 1);
    RETURN;
END

IF @STATUS = 'START'
BEGIN
    INSERT INTO energy.dbo.MIG_STEP_LOG (
        STEP_ID, STEP_NAME, HOST, STARTED_AT, STATUS, OPERATOR, NOTE
    )
    VALUES (
        @STEP_ID, @STEP_NAME, @HOST, SYSDATETIME(), 'START', @OPERATOR, @NOTE
    );
END
ELSE
BEGIN
    /* Son START kaydini kapat */
    UPDATE TOP (1) s
    SET s.FINISHED_AT = SYSDATETIME(),
        s.STATUS = @STATUS,
        s.ROWCOUNT_NOTE = @ROWCOUNT_NOTE,
        s.NOTE = COALESCE(@NOTE, s.NOTE),
        s.DURATION_SEC = DATEDIFF(SECOND, s.STARTED_AT, SYSDATETIME())
    FROM energy.dbo.MIG_STEP_LOG s
    WHERE s.LOG_ID = (
        SELECT MAX(LOG_ID)
        FROM energy.dbo.MIG_STEP_LOG
        WHERE STEP_ID = @STEP_ID AND STATUS = 'START'
    );

    IF @@ROWCOUNT = 0
        INSERT INTO energy.dbo.MIG_STEP_LOG (
            STEP_ID, STEP_NAME, HOST, STARTED_AT, FINISHED_AT, STATUS,
            ROWCOUNT_NOTE, DURATION_SEC, OPERATOR, NOTE
        )
        VALUES (
            @STEP_ID, @STEP_NAME, @HOST, SYSDATETIME(), SYSDATETIME(), @STATUS,
            @ROWCOUNT_NOTE, 0, @OPERATOR, @NOTE
        );
END

SELECT TOP (20) *
FROM energy.dbo.MIG_STEP_LOG WITH (NOLOCK)
ORDER BY LOG_ID DESC;
GO
