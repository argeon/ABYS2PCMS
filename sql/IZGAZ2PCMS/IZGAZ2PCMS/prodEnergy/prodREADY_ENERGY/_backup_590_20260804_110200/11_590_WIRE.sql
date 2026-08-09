/* ============================================================
   prodREADY_ENERGY / 11_590_WIRE
   INSERT sonrasi baglantilar. Atlanirsa sessiz bozulma → GATE FAIL.
   ============================================================ */
USE energy;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_590_WIRE
    @AGR_ID BIGINT = NULL,
    @DEBUG  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Msg NVARCHAR(400), @N INT;

    /* 1) MAIN.RETURN_TARGET_INVREF ← MAP(IADE_INV) */
    UPDATE inv
    SET inv.RETURN_TARGET_INVREF = m.ENERGY_LREF
    FROM dbo.LS_005_01_INVOICE inv
    INNER JOIN izgazMGR.dbo.LS_OV_MAIN_UPD u WITH (NOLOCK)
        ON inv.LREF = CAST(u.LREF AS INT)
    INNER JOIN dbo.MIG_OV_ID_MAP m
        ON m.SRC_KEY = u.RETURN_TARGET_SRC_KEY
    WHERE m.ENERGY_LREF IS NOT NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND u.ABYS_AGREEMENT_ID IS NULL)
           OR (@AGR_ID > 0 AND u.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);
    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'590 WIRE RETURN_TARGET=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 2) IADE INVLINES.ABYS_ID = LREF (UX) */
    UPDATE il
    SET il.ABYS_ID = il.LREF
    FROM dbo.LS_005_01_INVLINES il
    INNER JOIN dbo.MIG_OV_ID_MAP m ON m.ENERGY_LREF = il.LREF AND m.OV_KIND = 'IADE_IL'
    WHERE il.ABYS_ID IS NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);
    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'590 WIRE IADE_IL ABYS_ID=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 3) IADE PAYTRANS — LREF=INVOICEREF=IADE ENERGY_LREF (IDENTITY_INSERT) */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_PAYTRANS', 'U') IS NOT NULL
    BEGIN
        SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS ON;
        INSERT INTO dbo.LS_005_01_PAYTRANS (
            LREF, INVOICEREF, [TYPE], IOCODE, PAYTYPE, TRANSTYPE, LINETYPE, INST_NR,
            DATE_, PAYABLETOTAL, PAID, CANCELED, CLIENTREF, CLIENT_TYPE,
            ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF
        )
        SELECT
            mi.ENERGY_LREF,
            mi.ENERGY_LREF,
            CAST(s.[TYPE] AS TINYINT),
            CAST(s.IOCODE AS TINYINT),
            CAST(s.PAYTYPE AS INT),
            CAST(s.TRANSTYPE AS INT),
            CAST(s.LINETYPE AS INT),
            CAST(s.INST_NR AS INT),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
            CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            0, CAST(0 AS BIT),
            CAST(s.CLIENTREF AS INT),
            CAST(91 AS TINYINT),
            s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID,
            mi.ENERGY_LREF
        FROM izgazMGR.dbo.LS_OV_IADE_PAYTRANS s WITH (NOLOCK)
        INNER JOIN dbo.MIG_OV_ID_MAP mi
            ON mi.SRC_KEY = s.INVOICE_SRC_KEY
        WHERE mi.ENERGY_LREF IS NOT NULL
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
          AND NOT EXISTS (
                SELECT 1 FROM dbo.LS_005_01_PAYTRANS t WHERE t.LREF = mi.ENERGY_LREF
              )
        OPTION (RECOMPILE, MAXDOP 24);
        SET @N = @@ROWCOUNT;
        SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF;

        UPDATE mp SET mp.ENERGY_LREF = mi.ENERGY_LREF
        FROM dbo.MIG_OV_ID_MAP mp
        INNER JOIN izgazMGR.dbo.LS_OV_IADE_PAYTRANS s
            ON s.SRC_KEY = mp.SRC_KEY
        INNER JOIN dbo.MIG_OV_ID_MAP mi
            ON mi.SRC_KEY = s.INVOICE_SRC_KEY
        WHERE mp.OV_KIND = 'IADE_PT' AND mp.ENERGY_LREF IS NULL
        OPTION (RECOMPILE, MAXDOP 24);

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'590 WIRE IADE_PT=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* 4) KISMI debt PT — UPDATE by INVOICEREF=MAIN */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_KISMI_PAYTRANS', 'U') IS NOT NULL
    BEGIN
        UPDATE pt
        SET pt.TLTOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TLTOTAL)),
            pt.TAX = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TAX)),
            pt.GRANDTOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.GRANDTOTAL)),
            pt.PAYABLETOTAL = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
            pt.CANCELED = CAST(0 AS BIT)
        FROM dbo.LS_005_01_PAYTRANS pt
        INNER JOIN izgazMGR.dbo.LS_OV_KISMI_PAYTRANS s WITH (NOLOCK)
            ON pt.INVOICEREF = CAST(s.INVOICEREF AS INT)
           AND ISNULL(pt.IOCODE, 0) = 0
           AND ISNULL(pt.CANCELED, 0) = 0
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'590 WIRE KISMI_PT UPD=' + CAST(@@ROWCOUNT AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* 5) KISMI INVLINES LINEEXP — gelir adi senkron (O20 dump sonrasi) */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_KISMI_INVLINES', 'U') IS NOT NULL
       AND COL_LENGTH('dbo.LS_005_01_INVLINES', 'LINEEXP') IS NOT NULL
    BEGIN
        UPDATE il
        SET il.LINEEXP = LEFT(
                ISNULL(NULLIF(LTRIM(RTRIM(s.LINEEXP)), ''), N'Kısmi Eksilten'), 100)
        FROM dbo.LS_005_01_INVLINES il
        INNER JOIN izgazMGR.dbo.LS_OV_KISMI_INVLINES s WITH (NOLOCK)
            ON il.LREF = CAST(s.LREF AS INT)
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
          AND (
                il.LINEEXP IS NULL
             OR LTRIM(RTRIM(il.LINEEXP)) = N''
             OR il.LINEEXP = N'Kısmi Eksilten'
             OR (il.LINEEXP LIKE N'Kismi Eksilten EKS=%'
                 AND CHARINDEX(N'|', il.LINEEXP) = 0)
              )
        OPTION (RECOMPILE, MAXDOP 24);
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'590 WIRE KISMI_IL LINEEXP=' + CAST(@@ROWCOUNT AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    RAISERROR('SP_MIG_590_WIRE OK', 0, 1) WITH NOWAIT;
END
GO
