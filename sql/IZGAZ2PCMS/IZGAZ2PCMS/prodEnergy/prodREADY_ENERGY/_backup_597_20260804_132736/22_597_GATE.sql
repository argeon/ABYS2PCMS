/* prodREADY_ENERGY / 22_597_GATE — hard FAIL + log */
USE energy;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_GATE
    @AGR_ID BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @n INT, @Msg NVARCHAR(400), @Ts VARCHAR(30) = CONVERT(VARCHAR(30), SYSDATETIME(), 121);

    /* ENERGY_LREF zorunlu — iptal (CANCELED=1) PAY_PT de yazilir, MAP dolu olmali */
    SELECT @n = COUNT(*)
    FROM dbo.MIG_OV_ID_MAP m
    WHERE m.OV_KIND = 'PAY_PT'
      AND m.ENERGY_LREF IS NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);
    IF @n > 0
    BEGIN
        SET @Msg = N'PAY_PT ENERGY_LREF NULL=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E597G', N'gate_597', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E597G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    SELECT @n = COUNT(*)
    FROM dbo.LS_005_01_PAYTRANS pt
    INNER JOIN dbo.MIG_OV_ID_MAP m ON m.ENERGY_LREF = pt.LREF AND m.OV_KIND = 'PAY_PT'
    WHERE pt.CROSSREF IS NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);
    IF @n > 0
    BEGIN
        SET @Msg = N'PAY_PT CROSSREF NULL=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E597G', N'gate_597', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E597G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    /* CROSSREF borç PT.LREF olmali (IOCODE=0) — iptal PAY dahil; dead/hint/INV LREF FAIL */
    SELECT @n = COUNT(*)
    FROM dbo.LS_005_01_PAYTRANS pt
    INNER JOIN dbo.MIG_OV_ID_MAP m ON m.ENERGY_LREF = pt.LREF AND m.OV_KIND = 'PAY_PT'
    WHERE pt.CROSSREF IS NOT NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
      AND NOT EXISTS (
            SELECT 1 FROM dbo.LS_005_01_PAYTRANS d
            WHERE d.LREF = pt.CROSSREF
              AND ISNULL(d.IOCODE, 0) = 0
          )
    OPTION (RECOMPILE, MAXDOP 24);
    IF @n > 0
    BEGIN
        SET @Msg = N'PAY_PT CROSSREF not debt-PT=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E597G', N'gate_597', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E597G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    SELECT @n = COUNT(*)
    FROM dbo.MIG_OV_ID_MAP m
    INNER JOIN dbo.LS_005_01_PAYTRANS pt ON pt.LREF = m.ENERGY_LREF
    WHERE m.OV_KIND = 'CANCEL_PAY'
      AND pt.INVOICEREF IS NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);
    IF @n > 0
    BEGIN
        SET @Msg = N'CANCEL_PAY INVOICEREF NULL=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E597G', N'gate_597', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E597G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
        EXEC dbo.SP_MIG_LOG_STEP 'E597G', N'gate_597', 'GATE_PASS',
            N'PAY_PT MAP+CROSSREF→debtPT+CANCEL wire OK', NULL;

    SET @Msg = @Ts + N' | E597G | GATE_PASS | tahsilat wire dogrulandi';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END
GO
