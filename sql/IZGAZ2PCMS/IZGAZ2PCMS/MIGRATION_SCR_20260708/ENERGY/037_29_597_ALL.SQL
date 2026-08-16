/* ============================================================
   prodREADY_ENERGY / 29_597_ALL  ★ CUTOVER GIRIS
   INSERT → WIRE → GATE | log: MIG_STEP_LOG (E597)
   Ornek: EXEC energy.dbo.SP_MIG_597_ALL @AGR_ID=NULL, @CLEAN=1, @DEBUG=1, @BatchSize=20000;
   ============================================================ */
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_ALL
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
            @STEP_ID = 'E597', @STEP_NAME = N'tahsilat_ALL',
            @STATUS = 'START', @NOTE = @Note;

    BEGIN TRY
        IF OBJECT_ID('dbo.SP_MIG_597_INSERT', 'P') IS NULL
           OR OBJECT_ID('dbo.SP_MIG_597_WIRE', 'P') IS NULL
           OR OBJECT_ID('dbo.SP_MIG_597_GATE', 'P') IS NULL
            RAISERROR('597 INSERT/WIRE/GATE deploy eksik (20/21/22).', 16, 1);

        RAISERROR('---------- E597 faz1 INSERT ----------', 0, 1) WITH NOWAIT;
        EXEC dbo.SP_MIG_597_INSERT
            @AGR_ID=@AGR_ID, @CLEAN=@CLEAN, @DEBUG=@DEBUG, @BatchSize=@BatchSize;

        RAISERROR('---------- E597 faz2 WIRE ----------', 0, 1) WITH NOWAIT;
        EXEC dbo.SP_MIG_597_WIRE
            @AGR_ID=@AGR_ID, @DEBUG=@DEBUG, @BatchSize=@BatchSize;

        RAISERROR('---------- E597 faz3 GATE ----------', 0, 1) WITH NOWAIT;
        EXEC dbo.SP_MIG_597_GATE   @AGR_ID=@AGR_ID;

        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP
                @STEP_ID = 'E597', @STEP_NAME = N'tahsilat_ALL',
                @STATUS = 'OK',
                @ROWCOUNT_NOTE = N'INSERT+WIRE+GATE PASS',
                @NOTE = @Note;

        RAISERROR('========== E597 ALL PASS | overlay zinciri tamam ==========', 0, 1) WITH NOWAIT;
    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        BEGIN TRY
            IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
                EXEC dbo.SP_MIG_LOG_STEP
                    @STEP_ID = 'E597', @STEP_NAME = N'tahsilat_ALL',
                    @STATUS = 'FAIL', @NOTE = @Err;
        END TRY
        BEGIN CATCH
            RAISERROR('E597 FAIL log yazilamadi: %s', 10, 1, @Err) WITH NOWAIT;
        END CATCH
        RAISERROR('========== E597 ALL FAIL | %s ==========', 16, 1, @Err);
    END CATCH
END
GO
