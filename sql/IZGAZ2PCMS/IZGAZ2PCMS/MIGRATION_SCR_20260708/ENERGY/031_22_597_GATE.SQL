/* prodREADY_ENERGY / 22_597_GATE — hard FAIL + log
   + CROSSREF vs OV MAIN→debt PT mismatch (MAP path dogrulama)
   + v5: CANCEL_REV aktif iken AFL kapali ise FAIL (WIRE heal sonrasi 0 olmali)
*/
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_GATE
    @AGR_ID BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @n INT, @Msg NVARCHAR(400), @Ts VARCHAR(30) = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    DECLARE @Eps DECIMAL(18,2) = 0.02;

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
    OPTION (RECOMPILE, MAXDOP 8);
    IF @n > 0
    BEGIN
        SET @Msg = N'PAY_PT ENERGY_LREF NULL=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E597G', N'gate_597', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E597G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    /* WIRE ile ayni kapsam: sadece tahsilat (IOCODE<>0). Debt IOCODE=0 CROSSREF beklenmez. */
    SELECT @n = COUNT(*)
    FROM dbo.LS_005_01_PAYTRANS pt
    INNER JOIN dbo.MIG_OV_ID_MAP m ON m.ENERGY_LREF = pt.LREF AND m.OV_KIND = 'PAY_PT'
    WHERE pt.CROSSREF IS NULL
      AND pt.IOCODE <> 0
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 8);
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
    OPTION (RECOMPILE, MAXDOP 8);
    IF @n > 0
    BEGIN
        SET @Msg = N'PAY_PT CROSSREF not debt-PT=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E597G', N'gate_597', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E597G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    /* CROSSREF = OV MAIN'in debt PT'si olmali — sadece tahsilat (IOCODE<>0) */
    SELECT @n = COUNT(*)
    FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
    INNER JOIN izgazMGR.dbo.LS_OV_PAY_PT s WITH (NOLOCK)
        ON s.SRC_KEY = m.SRC_KEY
    INNER JOIN dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
        ON pt.LREF = m.ENERGY_LREF
    WHERE m.OV_KIND = 'PAY_PT'
      AND m.ENERGY_LREF IS NOT NULL
      AND pt.IOCODE <> 0
      AND s.CROSSREF_MAIN_LREF IS NOT NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
      AND NOT EXISTS (
            SELECT 1
            FROM dbo.LS_005_01_PAYTRANS d WITH (NOLOCK)
            WHERE d.LREF = pt.CROSSREF
              AND d.INVOICEREF = CAST(s.CROSSREF_MAIN_LREF AS INT)
              AND d.IOCODE = 0
          )
    OPTION (RECOMPILE, MAXDOP 8);
    IF @n > 0
    BEGIN
        SET @Msg = N'PAY_PT CROSSREF mismatch vs OV MAIN debt=' + CAST(@n AS VARCHAR(20));
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
    OPTION (RECOMPILE, MAXDOP 8);
    IF @n > 0
    BEGIN
        SET @Msg = N'CANCEL_PAY INVOICEREF NULL=' + CAST(@n AS VARCHAR(20));
        IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_LOG_STEP 'E597G', N'gate_597', 'GATE_FAIL', @Msg, NULL;
        RAISERROR('%s | E597G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
        RETURN;
    END

    /* v5: aktif CANCEL_REV + AFL kapali → WIRE heal eksik */
    IF OBJECT_ID('dbo.LS_AFL_OPEN_DEBT', 'U') IS NOT NULL
    BEGIN
        SELECT @n = COUNT(*)
        FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
        INNER JOIN dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
            ON inv.LREF = pt.INVOICEREF
        WHERE ISNULL(pt.IOCODE, 0) = 0
          AND ISNULL(pt.CANCELED, 0) = 0
          AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 1
          AND ISNULL(inv.IOCODE, 0) = 0
          AND ISNULL(inv.CANCELED, 0) = 0
          AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND inv.ABYS_AGREEMENT_ID = @AGR_ID)
              )
          AND NOT EXISTS (
                SELECT 1
                FROM dbo.LS_AFL_OPEN_DEBT a WITH (NOLOCK)
                WHERE a.FATURAID = inv.ABYS_ACCOUNT_ID
                  AND CONVERT(DECIMAL(18,2), ISNULL(a.BALANCE, 0)) > @Eps
              )
        OPTION (RECOMPILE, MAXDOP 8);

        IF @n > 0
        BEGIN
            SET @Msg = N'CANCEL_REV active but AFL closed=' + CAST(@n AS VARCHAR(20))
                     + N' — rerun SP_MIG_597_WIRE';
            IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
                EXEC dbo.SP_MIG_LOG_STEP 'E597G', N'gate_597', 'GATE_FAIL', @Msg, NULL;
            RAISERROR('%s | E597G | GATE_FAIL | %s', 16, 1, @Ts, @Msg);
            RETURN;
        END
    END

    IF OBJECT_ID('dbo.SP_MIG_LOG_STEP', 'P') IS NOT NULL
        EXEC dbo.SP_MIG_LOG_STEP 'E597G', N'gate_597', 'GATE_PASS',
            N'PAY_PT MAP+CROSSREF→debtPT+CANCEL+AFL heal OK', NULL;

    SET @Msg = @Ts + N' | E597G | GATE_PASS | tahsilat wire dogrulandi';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END
GO
