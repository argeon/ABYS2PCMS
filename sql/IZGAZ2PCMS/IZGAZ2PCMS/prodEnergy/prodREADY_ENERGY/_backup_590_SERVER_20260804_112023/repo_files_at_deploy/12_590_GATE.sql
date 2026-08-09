/* prodREADY_ENERGY / 12_590_GATE — hard FAIL + log */
USE energy;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_590_GATE
    @AGR_ID BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @n INT, @Msg NVARCHAR(400), @Ts VARCHAR(30) = CONVERT(VARCHAR(30), SYSDATETIME(), 121);

    SELECT @n = COUNT(*)
    FROM dbo.MIG_OV_ID_MAP m
    WHERE m.OV_KIND IN ('IADE_INV', 'IADE_IL', 'IADE_PT')
      AND m.ENERGY_LREF IS NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);
    IF @n > 0
    BEGIN
        SET @Msg = N'MAP ENERGY_LREF NULL (IADE*)=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E590G', N'gate_590', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E590G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    SELECT @n = COUNT(*)
    FROM izgazMGR.dbo.LS_OV_MAIN_UPD u WITH (NOLOCK)
    INNER JOIN dbo.LS_005_01_INVOICE inv ON inv.LREF = CAST(u.LREF AS INT)
    WHERE inv.RETURN_TARGET_INVREF IS NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND u.ABYS_AGREEMENT_ID IS NULL)
           OR (@AGR_ID > 0 AND u.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);
    IF @n > 0
    BEGIN
        SET @Msg = N'MAIN RETURN_TARGET NULL=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E590G', N'gate_590', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E590G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    SELECT @n = COUNT(*)
    FROM dbo.MIG_OV_ID_MAP m
    INNER JOIN dbo.LS_005_01_INVLINES il ON il.LREF = m.ENERGY_LREF
    WHERE m.OV_KIND = 'IADE_IL'
      AND (il.ABYS_ID IS NULL OR il.ABYS_ID <> il.LREF)
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);
    IF @n > 0
    BEGIN
        SET @Msg = N'IADE_IL ABYS_ID<>LREF=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E590G', N'gate_590', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E590G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
        EXEC dbo.SP_MIG_LOG_STEP 'E590G', N'gate_590', 'GATE_PASS',
            N'RETURN_TARGET+MAP+ABYS_ID OK', NULL;

    SET @Msg = @Ts + N' | E590G | GATE_PASS | eksilten wire dogrulandi';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END
GO
