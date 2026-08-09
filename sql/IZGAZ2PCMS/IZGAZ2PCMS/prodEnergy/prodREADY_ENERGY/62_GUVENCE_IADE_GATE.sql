/* ============================================================
   prodREADY_ENERGY / 62_GUVENCE_IADE_GATE — hard FAIL
   ============================================================ */
USE energy;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_GUVENCE_IADE_GATE
    @AGR_ID BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @n INT, @Msg NVARCHAR(400);
    DECLARE @Ts VARCHAR(30) = CONVERT(VARCHAR(30), SYSDATETIME(), 121);

    SELECT @n = COUNT(*)
    FROM dbo.MIG_OV_ID_MAP m
    WHERE m.OV_KIND IN (N'GUV_IADE_INV', N'GUV_IADE_IL', N'GUV_IADE_PT')
      AND m.ENERGY_LREF IS NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);

    IF @n > 0
    BEGIN
        SET @Msg = N'MAP ENERGY_LREF NULL (GUV_IADE*)=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E610G', N'gate_guvence_iade', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E610G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    SELECT @n = COUNT(*)
    FROM dbo.MIG_OV_ID_MAP m
    INNER JOIN dbo.LS_005_01_INVOICE inv ON inv.LREF = m.ENERGY_LREF
    WHERE m.OV_KIND = N'GUV_IADE_INV'
      AND ISNULL(inv.[TYPE], 0) <> 110
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);

    IF @n > 0
    BEGIN
        SET @Msg = N'INV TYPE<>110=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E610G', N'gate_guvence_iade', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E610G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    SELECT @n = COUNT(*)
    FROM dbo.MIG_OV_ID_MAP m
    INNER JOIN dbo.LS_005_01_INVOICE inv ON inv.LREF = m.ENERGY_LREF
    WHERE m.OV_KIND = N'GUV_IADE_INV'
      AND (
            inv.EXPLAIN IS NULL
         OR (
                inv.EXPLAIN NOT LIKE N'%Mahsupla%kalan%'
            AND inv.EXPLAIN NOT LIKE N'%MAHSUPLA%KALAN%'
            )
          )
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);

    IF @n > 0
    BEGIN
        SET @Msg = N'EXPLAIN mahsup kalan eksik=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E610G', N'gate_guvence_iade', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E610G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    SELECT @n = COUNT(*)
    FROM dbo.MIG_OV_ID_MAP m
    INNER JOIN dbo.LS_005_01_INVLINES il ON il.LREF = m.ENERGY_LREF
    WHERE m.OV_KIND = N'GUV_IADE_IL'
      AND (il.ABYS_ID IS NULL OR il.ABYS_ID <> il.LREF)
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);

    IF @n > 0
    BEGIN
        SET @Msg = N'GUV_IADE_IL ABYS_ID<>LREF=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E610G', N'gate_guvence_iade', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E610G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    SELECT @n = COUNT(*)
    FROM dbo.MIG_OV_ID_MAP m
    WHERE m.OV_KIND = N'GUV_IADE_INV'
      AND m.ENERGY_LREF IS NOT NULL
      AND NOT EXISTS (
            SELECT 1 FROM dbo.LS_005_01_PAYTRANS pt
            WHERE pt.LREF = m.ENERGY_LREF
          )
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);

    IF @n > 0
    BEGIN
        SET @Msg = N'GUV_IADE_INV PAYTRANS yok=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E610G', N'gate_guvence_iade', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E610G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
        EXEC dbo.SP_MIG_LOG_STEP 'E610G', N'gate_guvence_iade', 'GATE_PASS',
            N'TYPE110+EXPLAIN+MAP+PT OK', NULL;

    SET @Msg = @Ts + N' | E610G | GATE_PASS | guvence iade TYPE110 dogrulandi';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END
GO
