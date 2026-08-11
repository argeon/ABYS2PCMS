/* ============================================================
   prodREADY_ENERGY / 19_590_ALL  ★ CUTOVER GIRIS
   INSERT → WIRE → TAM_MAIN_CLOSE → GATE | log: MIG_STEP_LOG (E590)
   Ornek: EXEC energy.dbo.SP_MIG_590_ALL @AGR_ID=NULL, @CLEAN=1, @DEBUG=1;
   Resume FULL (MAP dolu, INV bitmis, IL yarim): ayni EXEC — MAP SKIP + IL batch.
   Backup: _backup_590_yyyyMMdd_HHmmss/
   R20: TAM+TYPE92 → MAIN PT/INV close (13_590_TAM_MAIN_CLOSE)
   ============================================================ */
USE energy;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_590_ALL
    @AGR_ID    BIGINT = NULL,
    @CLEAN     BIT = 1,
    @DEBUG     BIT = 1,
    @BatchSize INT = 20000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Note NVARCHAR(200) =
        N'AGR=' + CASE WHEN @AGR_ID IS NULL THEN N'FULL' WHEN @AGR_ID = -1 THEN N'NO_AGR' ELSE CAST(@AGR_ID AS NVARCHAR(30)) END
        + N' CLEAN=' + CAST(@CLEAN AS NVARCHAR(2))
        + N' Batch=' + CAST(ISNULL(@BatchSize, 20000) AS NVARCHAR(10));

    IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NULL
        RAISERROR('Uyari: SP_MIG_LOG_STEP yok — once 00_log_setup.sql', 10, 1) WITH NOWAIT;
    ELSE
        EXEC dbo.SP_MIG_LOG_STEP
            @STEP_ID = 'E590', @STEP_NAME = N'eksilten_ALL',
            @STATUS = 'START', @NOTE = @Note;

    BEGIN TRY
        IF OBJECT_ID('dbo.SP_MIG_590_INSERT', 'P') IS NULL
           OR OBJECT_ID('dbo.SP_MIG_590_WIRE', 'P') IS NULL
           OR OBJECT_ID('dbo.SP_MIG_590_GATE', 'P') IS NULL
            RAISERROR('590 INSERT/WIRE/GATE deploy eksik (10/11/12).', 16, 1);

        IF OBJECT_ID('dbo.SP_MIG_590_TAM_MAIN_CLOSE', 'P') IS NULL
            RAISERROR('590 TAM_MAIN_CLOSE deploy eksik (13_590_TAM_MAIN_CLOSE.sql).', 16, 1);

        RAISERROR('---------- E590 faz1 INSERT ----------', 0, 1) WITH NOWAIT;
        EXEC dbo.SP_MIG_590_INSERT
            @AGR_ID=@AGR_ID, @CLEAN=@CLEAN, @DEBUG=@DEBUG, @BatchSize=@BatchSize;

        RAISERROR('---------- E590 faz2 WIRE ----------', 0, 1) WITH NOWAIT;
        EXEC dbo.SP_MIG_590_WIRE   @AGR_ID=@AGR_ID, @DEBUG=@DEBUG;

        RAISERROR('---------- E590 faz2b TAM_MAIN_CLOSE ----------', 0, 1) WITH NOWAIT;
        EXEC dbo.SP_MIG_590_TAM_MAIN_CLOSE
            @AGR_ID=@AGR_ID, @DEBUG=@DEBUG, @DryRun=0;

        RAISERROR('---------- E590 faz3 GATE ----------', 0, 1) WITH NOWAIT;
        EXEC dbo.SP_MIG_590_GATE   @AGR_ID=@AGR_ID;

        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP
                @STEP_ID = 'E590', @STEP_NAME = N'eksilten_ALL',
                @STATUS = 'OK',
                @ROWCOUNT_NOTE = N'INSERT+WIRE+TAM_CLOSE+GATE PASS',
                @NOTE = @Note;

        RAISERROR('========== E590 ALL PASS | sonraki E597_ALL ==========', 0, 1) WITH NOWAIT;
    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;  /* doom 3930 onemli */
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP
                @STEP_ID = 'E590', @STEP_NAME = N'eksilten_ALL',
                @STATUS = 'FAIL', @NOTE = @Err;
        RAISERROR('========== E590 ALL FAIL | %s ==========', 16, 1, @Err);
    END CATCH
END
GO
