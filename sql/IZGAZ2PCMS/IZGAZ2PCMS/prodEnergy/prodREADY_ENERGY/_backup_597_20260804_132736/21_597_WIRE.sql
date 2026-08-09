/* prodREADY_ENERGY / 21_597_WIRE
   - CANCEL_PAY INVOICEREF
   - PAY_PT.CROSSREF → borç PT.LREF (kalici)
   - DEBT_PAID CLOSED/LPD
   - BANKREF SMS→LS_BANK.LREF (INV + PT)
*/
USE energy;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_WIRE
    @AGR_ID BIGINT = NULL,
    @DEBUG  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Msg NVARCHAR(400), @N INT;

    /* CANCEL_PAY.INVOICEREF ← IADE ENERGY_LREF */
    UPDATE pt
    SET pt.INVOICEREF = mi.ENERGY_LREF,
        pt.ABYS_INVOICE_LREF = mi.ENERGY_LREF
    FROM dbo.LS_005_01_PAYTRANS pt
    INNER JOIN dbo.MIG_OV_ID_MAP mp ON mp.ENERGY_LREF = pt.LREF AND mp.OV_KIND = 'CANCEL_PAY'
    INNER JOIN izgazMGR.dbo.LS_OV_CANCEL_PAY s WITH (NOLOCK)
        ON s.SRC_KEY = mp.SRC_KEY
    INNER JOIN dbo.MIG_OV_ID_MAP mi
        ON mi.SRC_KEY = s.INVOICE_SRC_KEY
    WHERE mi.ENERGY_LREF IS NOT NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
    OPTION (RECOMPILE, MAXDOP 24);
    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 WIRE CANCEL_PAY INVOICEREF=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* Cancel path: IADE CreateReverse PT sil (cift alacak) */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_CANCEL_PAY', 'U') IS NOT NULL
       AND OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_PAYTRANS', 'U') IS NOT NULL
    BEGIN
        DELETE pt
        FROM dbo.LS_005_01_PAYTRANS pt
        INNER JOIN dbo.MIG_OV_ID_MAP mpt ON mpt.ENERGY_LREF = pt.LREF AND mpt.OV_KIND = 'IADE_PT'
        INNER JOIN izgazMGR.dbo.LS_OV_IADE_PAYTRANS ip WITH (NOLOCK)
            ON ip.SRC_KEY = mpt.SRC_KEY
        INNER JOIN izgazMGR.dbo.LS_OV_CANCEL_PAY c WITH (NOLOCK)
            ON c.INVOICE_SRC_KEY
             = ip.INVOICE_SRC_KEY
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND c.ABYS_AGREEMENT_ID IS NULL AND c.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND c.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE drop IADE_PT where CANCEL=' + CAST(@@ROWCOUNT AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ============================================================
       PAY_PT.CROSSREF = borç PT.LREF (IOCODE=0, INVOICEREF=MAIN)
       Kaynak: LS_OV_PAY_PT.CROSSREF_MAIN_LREF
       ============================================================ */
    UPDATE pt
    SET pt.CROSSREF = x.DEBT_PT_LREF
    FROM dbo.LS_005_01_PAYTRANS pt
    INNER JOIN dbo.MIG_OV_ID_MAP m
        ON m.ENERGY_LREF = pt.LREF AND m.OV_KIND = 'PAY_PT'
    INNER JOIN izgazMGR.dbo.LS_OV_PAY_PT s WITH (NOLOCK)
        ON s.SRC_KEY = m.SRC_KEY
    CROSS APPLY (
        SELECT TOP (1) d.LREF AS DEBT_PT_LREF
        FROM dbo.LS_005_01_PAYTRANS d WITH (NOLOCK)
        WHERE d.INVOICEREF = CAST(s.CROSSREF_MAIN_LREF AS INT)
          AND ISNULL(d.IOCODE, 0) = 0
          AND ISNULL(d.CANCELED, 0) = 0
          AND ISNULL(d.CANCELLATIONPAYMENT, 0) = 0
        ORDER BY d.LREF
    ) x
    WHERE ISNULL(pt.IOCODE, 0) <> 0
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
      AND (pt.CROSSREF IS NULL OR pt.CROSSREF <> x.DEBT_PT_LREF)
    OPTION (RECOMPILE, MAXDOP 24);
    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 WIRE PAY_PT CROSSREF→debt PT=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* Fallback: MAP yoksa — OR join YASAK (LS_OV_PAY_PT full scan).
       ABYS_ID ve LREF_HINT ayri UPDATE; AGR varsa once kaynak filtrele. */
    IF OBJECT_ID('tempdb..#OV_PAY_PT_XREF') IS NOT NULL DROP TABLE #OV_PAY_PT_XREF;
    SELECT
        s.ABYS_ID,
        s.LREF_HINT,
        CAST(s.CROSSREF_MAIN_LREF AS INT) AS MAIN_LREF,
        s.ABYS_AGREEMENT_ID
    INTO #OV_PAY_PT_XREF
    FROM izgazMGR.dbo.LS_OV_PAY_PT s WITH (NOLOCK)
    WHERE s.CROSSREF_MAIN_LREF IS NOT NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            );

    CREATE CLUSTERED INDEX CX_OV_PAY_PT_XREF_ABYS ON #OV_PAY_PT_XREF (ABYS_ID);
    CREATE NONCLUSTERED INDEX IX_OV_PAY_PT_XREF_HINT ON #OV_PAY_PT_XREF (LREF_HINT)
        WHERE LREF_HINT IS NOT NULL;

    UPDATE pt
    SET pt.CROSSREF = x.DEBT_PT_LREF
    FROM dbo.LS_005_01_PAYTRANS pt
    INNER JOIN #OV_PAY_PT_XREF s ON s.ABYS_ID = pt.ABYS_ID
    CROSS APPLY (
        SELECT TOP (1) d.LREF AS DEBT_PT_LREF
        FROM dbo.LS_005_01_PAYTRANS d WITH (NOLOCK)
        WHERE d.INVOICEREF = s.MAIN_LREF
          AND ISNULL(d.IOCODE, 0) = 0
          AND ISNULL(d.CANCELED, 0) = 0
          AND ISNULL(d.CANCELLATIONPAYMENT, 0) = 0
        ORDER BY d.LREF
    ) x
    WHERE ISNULL(pt.IOCODE, 0) <> 0
      AND pt.ABYS_ID IS NOT NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND (pt.ABYS_AGREEMENT_ID IS NULL OR s.ABYS_AGREEMENT_ID IS NULL))
           OR (@AGR_ID > 0 AND (pt.ABYS_AGREEMENT_ID = @AGR_ID OR s.ABYS_AGREEMENT_ID = @AGR_ID))
            )
      AND (pt.CROSSREF IS NULL OR pt.CROSSREF <> x.DEBT_PT_LREF
           OR NOT EXISTS (
                SELECT 1 FROM dbo.LS_005_01_PAYTRANS d2 WITH (NOLOCK)
                WHERE d2.LREF = pt.CROSSREF AND ISNULL(d2.IOCODE, 0) = 0
              ))
    OPTION (RECOMPILE, MAXDOP 24);
    SET @N = @@ROWCOUNT;

    UPDATE pt
    SET pt.CROSSREF = x.DEBT_PT_LREF
    FROM dbo.LS_005_01_PAYTRANS pt
    INNER JOIN #OV_PAY_PT_XREF s ON s.LREF_HINT = pt.LREF
    CROSS APPLY (
        SELECT TOP (1) d.LREF AS DEBT_PT_LREF
        FROM dbo.LS_005_01_PAYTRANS d WITH (NOLOCK)
        WHERE d.INVOICEREF = s.MAIN_LREF
          AND ISNULL(d.IOCODE, 0) = 0
          AND ISNULL(d.CANCELED, 0) = 0
          AND ISNULL(d.CANCELLATIONPAYMENT, 0) = 0
        ORDER BY d.LREF
    ) x
    WHERE ISNULL(pt.IOCODE, 0) <> 0
      AND s.LREF_HINT IS NOT NULL
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND (pt.ABYS_AGREEMENT_ID IS NULL OR s.ABYS_AGREEMENT_ID IS NULL))
           OR (@AGR_ID > 0 AND (pt.ABYS_AGREEMENT_ID = @AGR_ID OR s.ABYS_AGREEMENT_ID = @AGR_ID))
            )
      AND (pt.CROSSREF IS NULL OR pt.CROSSREF <> x.DEBT_PT_LREF
           OR NOT EXISTS (
                SELECT 1 FROM dbo.LS_005_01_PAYTRANS d2 WITH (NOLOCK)
                WHERE d2.LREF = pt.CROSSREF AND ISNULL(d2.IOCODE, 0) = 0
              ))
    OPTION (RECOMPILE, MAXDOP 24);
    SET @N = @N + @@ROWCOUNT;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 WIRE PAY_PT CROSSREF fallback=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    DROP TABLE #OV_PAY_PT_XREF;

    /* DEBT_PAID → MAIN CLOSED + LASTPAIDDATE (+ BANK SMS id; resolve asagida) */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_DEBT_PAID_UPD', 'U') IS NOT NULL
    BEGIN
        IF COL_LENGTH('izgazMGR.dbo.LS_OV_DEBT_PAID_UPD', 'LASTPAIDDATE') IS NOT NULL
        BEGIN
            UPDATE inv
            SET inv.CLOSED = CASE
                    WHEN TRY_CAST(u.CLOSED AS INT) = 1 THEN CAST(1 AS BIT)
                    ELSE inv.CLOSED
                END,
                inv.LASTPAIDDATE = CASE
                    WHEN u.LASTPAIDDATE IS NOT NULL
                    THEN energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(u.LASTPAIDDATE AS DATETIME2))
                    ELSE inv.LASTPAIDDATE
                END,
                inv.BANKREF = COALESCE(CAST(u.BANKREF AS INT), inv.BANKREF)
            FROM dbo.LS_005_01_INVOICE inv
            INNER JOIN izgazMGR.dbo.LS_OV_DEBT_PAID_UPD u WITH (NOLOCK)
                ON inv.LREF = CAST(TRY_CAST(u.MAIN_LREF AS BIGINT) AS INT)
            WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) IS NULL)
           OR (@AGR_ID > 0 AND TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) = @AGR_ID)
            )
              AND (
                    (TRY_CAST(u.CLOSED AS INT) = 1 AND ISNULL(inv.CLOSED, 0) = 0)
                 OR (u.LASTPAIDDATE IS NOT NULL AND inv.LASTPAIDDATE IS NULL)
                 OR (u.BANKREF IS NOT NULL AND inv.BANKREF IS NULL)
              )
            OPTION (RECOMPILE, MAXDOP 24);
        END
        ELSE
        BEGIN
            UPDATE inv
            SET inv.CLOSED = CAST(1 AS BIT)
            FROM dbo.LS_005_01_INVOICE inv
            INNER JOIN izgazMGR.dbo.LS_OV_DEBT_PAID_UPD u WITH (NOLOCK)
                ON inv.LREF = CAST(TRY_CAST(u.MAIN_LREF AS BIGINT) AS INT)
            WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) IS NULL)
           OR (@AGR_ID > 0 AND TRY_CAST(u.ABYS_AGREEMENT_ID AS BIGINT) = @AGR_ID)
            )
              AND TRY_CAST(u.CLOSED AS INT) = 1
              AND ISNULL(inv.CLOSED, 0) = 0
            OPTION (RECOMPILE, MAXDOP 24);
        END
        SET @N = @@ROWCOUNT;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE DEBT_PAID CLOSED/LPD=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* PAYABLETOTAL=0 → CLOSED=1 */
    UPDATE inv
    SET inv.CLOSED = CAST(1 AS BIT)
    FROM dbo.LS_005_01_INVOICE inv
    WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID))
            )
      AND ISNULL(inv.IOCODE, 0) = 0
      AND ABS(ISNULL(inv.PAYABLETOTAL, 0)) <= 0.01
      AND ISNULL(inv.CLOSED, 0) = 0
    OPTION (RECOMPILE, MAXDOP 24);
    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 WIRE ZERO_PAYABLE CLOSED=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* MAHSUP EXPLAIN mark */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_MAHSUP_CLOSED', 'U') IS NOT NULL
    BEGIN
        UPDATE inv
        SET inv.EXPLAIN = LEFT(
            CASE WHEN inv.EXPLAIN IS NULL OR LTRIM(RTRIM(inv.EXPLAIN)) = ''
                 THEN m.EXPLAIN_MARK
                 ELSE inv.EXPLAIN + N' | ' + (m.EXPLAIN_MARK) END, 250),
            inv.CLOSED = CAST(1 AS BIT)
        FROM dbo.LS_005_01_INVOICE inv
        INNER JOIN izgazMGR.dbo.LS_OV_MAHSUP_CLOSED m WITH (NOLOCK)
            ON inv.LREF = CAST(m.MAIN_LREF AS INT)
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE MAHSUP_CLOSED=' + CAST(@@ROWCOUNT AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ============================================================
       BANKREF: SMS BANK_ID → LS_BANK.LREF  (perf v2)
       Oncelik: LS_PAYMENT.BANKA_ID → OV_PAY_PT / TAH_INV / LS_INVOICE
       Yedek resolve: SADECE henuz LREF olmayan (cift resolve YASAK).
       Kurallar:
         - TAH: OR join YASAK → once LREF, sonra ABYS (ayri UPDATE)
         - AGR>0: PAYMENT join SOZLESME=@AGR (SARG); EXISTS OR yok
         - BANKREF nchar → TRY_CAST int
         - MAXDOP 8 (CXSYNC azalt)
       ============================================================ */
    IF OBJECT_ID('dbo.LS_BANK', 'U') IS NOT NULL
       AND COL_LENGTH('dbo.LS_BANK', 'ABYS_ID') IS NOT NULL
       AND OBJECT_ID('izgazMGR.dbo.LS_INVOICE', 'U') IS NOT NULL
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID('dbo.LS_BANK') AND name = 'UX_LS_BANK_ABYS_ID'
        )
            CREATE UNIQUE NONCLUSTERED INDEX UX_LS_BANK_ABYS_ID
                ON dbo.LS_BANK (ABYS_ID) WHERE ABYS_ID IS NOT NULL;

        /* MAIN INV bank */
        UPDATE inv
        SET inv.BANKREF = b.LREF
        FROM dbo.LS_005_01_INVOICE inv
        INNER JOIN izgazMGR.dbo.LS_INVOICE m ON m.LREF = inv.LREF
        INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = m.BANKREF
        WHERE m.BANKREF IS NOT NULL
          AND ISNULL(inv.TYPE, 0) <> 101
          AND (inv.BANKREF IS NULL OR inv.BANKREF <> b.LREF)
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID))
            )
        OPTION (RECOMPILE, MAXDOP 8);
        SET @N = @@ROWCOUNT;

        /* debt PT bank (ABYS_ID seek) */
        IF OBJECT_ID('izgazMGR.dbo.LS_DEBT_PAYTRANS', 'U') IS NOT NULL
        BEGIN
            UPDATE pt
            SET pt.BANKREF = b.LREF
            FROM dbo.LS_005_01_PAYTRANS pt
            INNER JOIN izgazMGR.dbo.LS_DEBT_PAYTRANS m ON m.ABYS_ID = pt.ABYS_ID
            INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = m.BANKREF
            WHERE m.BANKREF IS NOT NULL
              AND pt.ABYS_ID IS NOT NULL
              AND ISNULL(pt.IOCODE, 0) = 0
              AND (pt.BANKREF IS NULL OR pt.BANKREF <> b.LREF)
              AND (
                    @AGR_ID IS NULL
                 OR (@AGR_ID = -1 AND (pt.ABYS_AGREEMENT_ID IS NULL OR m.ABYS_AGREEMENT_ID IS NULL))
                 OR (@AGR_ID > 0 AND (pt.ABYS_AGREEMENT_ID = @AGR_ID OR m.ABYS_AGREEMENT_ID = @AGR_ID))
                  )
            OPTION (RECOMPILE, MAXDOP 8);
            SET @N = @N + @@ROWCOUNT;
        END

        /* Tahsilat PT: LS_PAYMENT — AGR path SOZLESME SARG */
        IF OBJECT_ID('izgazMGR.dbo.LS_PAYMENT', 'U') IS NOT NULL
        BEGIN
            IF @AGR_ID > 0
            BEGIN
                UPDATE pt
                SET pt.BANKREF = b.LREF
                FROM dbo.LS_005_01_PAYTRANS pt
                INNER JOIN izgazMGR.dbo.LS_PAYMENT p WITH (NOLOCK)
                    ON p.PAY_LREF = pt.ABYS_ID
                   AND p.SOZLESME = @AGR_ID
                INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = p.BANKA_ID
                WHERE p.BANKA_ID IS NOT NULL
                  AND ISNULL(p.CANCELED, 0) = 0
                  AND pt.ABYS_ID IS NOT NULL
                  AND pt.ABYS_AGREEMENT_ID = @AGR_ID
                  AND (pt.BANKREF IS NULL OR pt.BANKREF <> b.LREF)
                OPTION (RECOMPILE, MAXDOP 8);
                SET @N = @N + @@ROWCOUNT;
            END
            ELSE IF @AGR_ID = -1
            BEGIN
                UPDATE pt
                SET pt.BANKREF = b.LREF
                FROM dbo.LS_005_01_PAYTRANS pt
                INNER JOIN izgazMGR.dbo.LS_PAYMENT p WITH (NOLOCK)
                    ON p.PAY_LREF = pt.ABYS_ID
                INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = p.BANKA_ID
                WHERE p.BANKA_ID IS NOT NULL
                  AND ISNULL(p.CANCELED, 0) = 0
                  AND pt.ABYS_ID IS NOT NULL
                  AND pt.ABYS_AGREEMENT_ID IS NULL
                  AND (pt.BANKREF IS NULL OR pt.BANKREF <> b.LREF)
                OPTION (RECOMPILE, MAXDOP 8);
                SET @N = @N + @@ROWCOUNT;
            END
            ELSE
            BEGIN
                UPDATE pt
                SET pt.BANKREF = b.LREF
                FROM dbo.LS_005_01_PAYTRANS pt
                INNER JOIN izgazMGR.dbo.LS_PAYMENT p WITH (NOLOCK)
                    ON p.PAY_LREF = pt.ABYS_ID
                INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = p.BANKA_ID
                WHERE p.BANKA_ID IS NOT NULL
                  AND ISNULL(p.CANCELED, 0) = 0
                  AND pt.ABYS_ID IS NOT NULL
                  AND (pt.BANKREF IS NULL OR pt.BANKREF <> b.LREF)
                OPTION (RECOMPILE, MAXDOP 8);
                SET @N = @N + @@ROWCOUNT;
            END
        END

        /* fallback: OV_PAY_PT.BANKREF */
        IF OBJECT_ID('izgazMGR.dbo.LS_OV_PAY_PT', 'U') IS NOT NULL
        BEGIN
            UPDATE pt
            SET pt.BANKREF = b.LREF
            FROM dbo.LS_005_01_PAYTRANS pt
            INNER JOIN izgazMGR.dbo.LS_OV_PAY_PT m ON m.ABYS_ID = pt.ABYS_ID
            INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = m.BANKREF
            WHERE m.BANKREF IS NOT NULL
              AND pt.ABYS_ID IS NOT NULL
              AND (pt.BANKREF IS NULL OR pt.BANKREF <> b.LREF)
              AND (
                    @AGR_ID IS NULL
                 OR (@AGR_ID = -1 AND (pt.ABYS_AGREEMENT_ID IS NULL OR m.ABYS_AGREEMENT_ID IS NULL))
                 OR (@AGR_ID > 0 AND (pt.ABYS_AGREEMENT_ID = @AGR_ID OR m.ABYS_AGREEMENT_ID = @AGR_ID))
                  )
            OPTION (RECOMPILE, MAXDOP 8);
            SET @N = @N + @@ROWCOUNT;
        END

        /* TYPE=101 TAH — OR join YASAK: 1) LREF  2) ABYS orphan */
        IF OBJECT_ID('izgazMGR.dbo.LS_OV_TAH_INVOICE', 'U') IS NOT NULL
        BEGIN
            UPDATE inv
            SET inv.BANKREF = b.LREF
            FROM dbo.LS_005_01_INVOICE inv
            INNER JOIN izgazMGR.dbo.LS_OV_TAH_INVOICE t WITH (NOLOCK)
                ON t.LREF = inv.LREF
            INNER JOIN dbo.LS_BANK b
                ON b.ABYS_ID = TRY_CAST(LTRIM(RTRIM(CONVERT(NVARCHAR(20), t.BANKREF))) AS INT)
            WHERE t.BANKREF IS NOT NULL
              AND ISNULL(inv.TYPE, 0) = 101
              AND (inv.BANKREF IS NULL OR inv.BANKREF <> b.LREF)
              AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID
                                    OR t.ABYS_AGREEMENT_ID = @AGR_ID))
                )
            OPTION (RECOMPILE, MAXDOP 8);
            SET @N = @N + @@ROWCOUNT;

            UPDATE inv
            SET inv.BANKREF = b.LREF
            FROM dbo.LS_005_01_INVOICE inv
            INNER JOIN izgazMGR.dbo.LS_OV_TAH_INVOICE t WITH (NOLOCK)
                ON t.ABYS_ID = inv.ABYS_ID
            INNER JOIN dbo.LS_BANK b
                ON b.ABYS_ID = TRY_CAST(LTRIM(RTRIM(CONVERT(NVARCHAR(20), t.BANKREF))) AS INT)
            WHERE t.ABYS_ID IS NOT NULL
              AND t.BANKREF IS NOT NULL
              AND ISNULL(inv.TYPE, 0) = 101
              AND inv.ABYS_ID IS NOT NULL
              AND (inv.BANKREF IS NULL OR inv.BANKREF <> b.LREF)
              AND (
                  @AGR_ID IS NULL
               OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
               OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID
                                    OR t.ABYS_AGREEMENT_ID = @AGR_ID))
                )
            OPTION (RECOMPILE, MAXDOP 8);
            SET @N = @N + @@ROWCOUNT;
        END

        /* Yedek: ENERGY SMS BANK_ID → LREF (cift resolve YASAK) */
        UPDATE inv
        SET inv.BANKREF = b.LREF
        FROM dbo.LS_005_01_INVOICE inv
        INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = inv.BANKREF
        WHERE inv.BANKREF IS NOT NULL
          AND inv.BANKREF <> b.LREF
          AND NOT EXISTS (SELECT 1 FROM dbo.LS_BANK x WITH (NOLOCK) WHERE x.LREF = inv.BANKREF)
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID))
            )
        OPTION (RECOMPILE, MAXDOP 8);
        SET @N = @N + @@ROWCOUNT;

        UPDATE pt
        SET pt.BANKREF = b.LREF
        FROM dbo.LS_005_01_PAYTRANS pt
        INNER JOIN dbo.LS_BANK b ON b.ABYS_ID = pt.BANKREF
        WHERE pt.BANKREF IS NOT NULL
          AND pt.BANKREF <> b.LREF
          AND NOT EXISTS (SELECT 1 FROM dbo.LS_BANK x WITH (NOLOCK) WHERE x.LREF = pt.BANKREF)
          AND (
                @AGR_ID IS NULL
             OR (@AGR_ID = -1 AND pt.ABYS_AGREEMENT_ID IS NULL)
             OR (@AGR_ID > 0 AND pt.ABYS_AGREEMENT_ID = @AGR_ID)
              )
        OPTION (RECOMPILE, MAXDOP 8);
        SET @N = @N + @@ROWCOUNT;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 WIRE BANKREF resolve INV+PT rows~' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* Borç PT PAID = PAYABLE when CLOSED (DEBT_PAID) */
    UPDATE d
    SET d.PAID = d.PAYABLETOTAL,
        d.LASTPAIDDATE = COALESCE(d.LASTPAIDDATE, inv.LASTPAIDDATE),
        d.BANKREF = COALESCE(d.BANKREF, inv.BANKREF),
        d.BANK_RECORD_REF = COALESCE(d.BANK_RECORD_REF, inv.BANK_RECORD_REF)
    FROM dbo.LS_005_01_PAYTRANS d
    INNER JOIN dbo.LS_005_01_INVOICE inv ON inv.LREF = d.INVOICEREF
    WHERE ISNULL(d.IOCODE, 0) = 0
      AND ISNULL(inv.CLOSED, 0) = 1
      AND ISNULL(d.CANCELED, 0) = 0
      AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID))
            )
      AND (
            ISNULL(d.PAID, 0) < ISNULL(d.PAYABLETOTAL, 0) - 0.01
         OR d.BANKREF IS NULL
         OR d.LASTPAIDDATE IS NULL
      )
    OPTION (RECOMPILE, MAXDOP 24);
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 WIRE debt PT PAID/BANK sync=' + CAST(@@ROWCOUNT AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    RAISERROR('SP_MIG_597_WIRE OK', 0, 1) WITH NOWAIT;
END
GO
