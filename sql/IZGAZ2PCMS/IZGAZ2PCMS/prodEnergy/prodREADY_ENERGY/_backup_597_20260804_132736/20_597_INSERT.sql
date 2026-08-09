/* ============================================================
   prodREADY_ENERGY / 20_597_INSERT  (v2 — LREF carpismasi fix)
   PAY_PT + TAH_INV + CANCEL_* insert; MAP.ENERGY_LREF doldur
   Tek basina YASAK → 29_597_ALL

   Fix:
     - LREF_HINT dolu ama PAYTRANS'ta mevcut → IDENTITY path (carpismayi atla)
     - MAP ENERGY_LREF yalniz gercek insert sonrasi
     - CROSSREF = borc PT LREF (IOCODE=0, INVOICEREF=MAIN); yoksa MAIN
     - IDENTITY_INSERT OFF her zaman (TRY/CATCH)
     - TAH_INV MAP yalniz TYPE=101 satirinda
     - PAY_PT iptal: CANCELED=1 yazilir; PAID=0 (borc PAID'e sayilmaz — DEBT_PAID yalniz gecerli)
   ============================================================ */
USE energy;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_INSERT
    @AGR_ID BIGINT = NULL,
    @CLEAN  BIT = 1,
    @DEBUG  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_PAY_PT', 'U') IS NULL
       OR OBJECT_ID('izgazMGR.dbo.LS_OV_ID_MAP', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR LS_OV_PAY_PT / LS_OV_ID_MAP yok.', 16, 1);
        RETURN;
    END

    /* kirli session temizligi */
    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;
    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;

    MERGE dbo.MIG_OV_ID_MAP AS t
    USING (
        SELECT * FROM izgazMGR.dbo.LS_OV_ID_MAP WITH (NOLOCK)
        WHERE OV_KIND IN ('PAY_PT','TAH_INV','CANCEL_PAY','CANCEL_REV')
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
            )
    ) s ON t.SRC_KEY = s.SRC_KEY
    WHEN NOT MATCHED THEN INSERT (
        OV_KIND, SRC_KEY, LREF_HINT, PARENT_SRC_KEY, REF_MAIN_LREF,
        ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID, ABYS_ID_BUSINESS, ENERGY_LREF
    ) VALUES (
        s.OV_KIND,
        s.SRC_KEY,
        s.LREF_HINT,
        s.PARENT_SRC_KEY,
        s.REF_MAIN_LREF,
        s.ABYS_AGREEMENT_ID, s.ABYS_ACCOUNT_ID, s.ABYS_ID_BUSINESS, NULL
    )
    OPTION (RECOMPILE, MAXDOP 24);

    DECLARE @Msg NVARCHAR(400), @N INT, @SRC VARCHAR(80), @NewLref INT;
    DECLARE @Ts VARCHAR(30) = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    SET @Msg = @Ts + N' | E597 | INFO | INSERT basladi | AGR='
             + CASE WHEN @AGR_ID IS NULL THEN N'FULL' WHEN @AGR_ID = -1 THEN N'NO_AGR' ELSE CAST(@AGR_ID AS NVARCHAR(30)) END;
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* ---- CLEAN: onceki PAY/TAH overlay sil + MAP ENERGY_LREF sifirla ---- */
    IF @CLEAN = 1
    BEGIN
        DELETE pt
        FROM dbo.LS_005_01_PAYTRANS pt
        INNER JOIN dbo.MIG_OV_ID_MAP m
            ON m.ENERGY_LREF = pt.LREF
           AND m.OV_KIND IN ('PAY_PT', 'CANCEL_PAY', 'CANCEL_REV')
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);
        SET @N = @@ROWCOUNT;

        DELETE pt
        FROM dbo.LS_005_01_PAYTRANS pt
        WHERE ISNULL(pt.IOCODE, 0) <> 0
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND pt.ABYS_AGREEMENT_ID IS NULL AND pt.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND pt.ABYS_AGREEMENT_ID = @AGR_ID)
            )
          AND NOT EXISTS (
                SELECT 1 FROM dbo.MIG_OV_ID_MAP m
                WHERE m.ENERGY_LREF = pt.LREF
                  AND m.OV_KIND IN ('IADE_PT', 'KISMI_PT')
              )
        OPTION (RECOMPILE, MAXDOP 24);
        SET @N = @N + @@ROWCOUNT;

        IF OBJECT_ID('dbo.LS_005_01_INVLINES', 'U') IS NOT NULL
        BEGIN
            DELETE il
            FROM dbo.LS_005_01_INVLINES il
            INNER JOIN dbo.LS_005_01_INVOICE inv ON inv.LREF = il.INVOICEREF
            WHERE ISNULL(inv.IOCODE, 0) = 1
              AND ISNULL(inv.[TYPE], 0) = 101
              AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID))
            )
            OPTION (RECOMPILE, MAXDOP 24);
        END

        DELETE inv
        FROM dbo.LS_005_01_INVOICE inv
        WHERE ISNULL(inv.IOCODE, 0) = 1
          AND ISNULL(inv.[TYPE], 0) = 101
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND inv.ABYS_AGREEMENT_ID IS NULL AND inv.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND (inv.ABYS_AGREEMENT_ID = @AGR_ID OR inv.OWNERREF = @AGR_ID))
            )
        OPTION (RECOMPILE, MAXDOP 24);

        UPDATE dbo.MIG_OV_ID_MAP
        SET ENERGY_LREF = NULL
        WHERE OV_KIND IN ('PAY_PT', 'TAH_INV', 'CANCEL_PAY', 'CANCEL_REV')
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);

        UPDATE izgazMGR.dbo.LS_OV_ID_MAP
        SET ENERGY_LREF = NULL
        WHERE OV_KIND IN ('PAY_PT', 'TAH_INV', 'CANCEL_PAY', 'CANCEL_REV')
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL AND ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 CLEAN PAY/TAH overlay silindi (PT+INV TYPE=101) + MAP sifir';
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ---- TAH_INV — LREF_HINT = PAY.ID ---- */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_TAH_INVOICE', 'U') IS NOT NULL
    BEGIN
        BEGIN TRY
            SET IDENTITY_INSERT dbo.LS_005_01_INVOICE ON;
            INSERT INTO dbo.LS_005_01_INVOICE (
                LREF, IOCODE, FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF,
                TLTOTAL, CURID, CURTOTAL, EXPLAIN, CANCELED, OWNERREF, OWNERTYPE,
                TAX, DV, GRANDTOTAL, PRINTCOUNT, PAYABLETOTAL, CLOSED,
                FITNO, BN_TYPE, AMOUNT, PERIOD,
                BANKREF, BANK_RECORD_REF, LASTPAIDDATE,
                ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID
            )
            SELECT
                CAST(s.LREF_HINT AS INT),
                CAST(s.IOCODE AS TINYINT),
                LEFT(s.FICHENO, 45),
                energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
                energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DUEDATE AS DATETIME2)),
                CAST(s.[TYPE] AS TINYINT),
                CAST(s.CLIENTREF AS INT),
                CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.TLTOTAL)),
                CAST(160 AS SMALLINT),
                CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.CURTOTAL)),
                LEFT(s.EXPLAIN, 250),
                CAST(ISNULL(s.CANCELED, 0) AS BIT),
                CAST(s.OWNERREF AS INT),
                CAST(ISNULL(s.OWNERTYPE, 91) AS TINYINT),
                0, 0,
                CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.GRANDTOTAL)),
                0,
                CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
                CAST(1 AS BIT),
                TRY_CAST(s.FITNO AS BIGINT),
                TRY_CAST(s.BN_TYPE AS INT),
                CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.AMOUNT)),
                s.PERIOD,
                /* SMS BANK_ID — WIRE ABYS_ID→LS_BANK.LREF (O30/O34 TAH_INV) */
                CAST(s.BANKREF AS INT),
                LEFT(s.BANK_RECORD_REF, 50),
                CASE WHEN s.LASTPAIDDATE IS NOT NULL
                     THEN energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.LASTPAIDDATE AS DATETIME2))
                     WHEN ISNULL(s.CANCELED, 0) = 0
                     THEN energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2))
                     ELSE NULL END,
                s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID
            FROM izgazMGR.dbo.LS_OV_TAH_INVOICE s WITH (NOLOCK)
            WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
              AND s.LREF_HINT BETWEEN 1 AND 2147483647
              AND NOT EXISTS (
                    SELECT 1 FROM dbo.LS_005_01_INVOICE t WHERE t.LREF = CAST(s.LREF_HINT AS INT)
                  )
            OPTION (RECOMPILE, MAXDOP 24);
            SET @N = @@ROWCOUNT;
        END TRY
        BEGIN CATCH
            SET @N = 0;
            SET @Msg = N'597 TAH_INV INSERT FAIL: ' + ERROR_MESSAGE();
            RAISERROR('%s', 16, 1, @Msg);
        END CATCH

        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;

        /* MAP: yalniz gercek TYPE=101 (yeni veya zaten var) */
        UPDATE m SET m.ENERGY_LREF = CAST(s.LREF_HINT AS INT)
        FROM dbo.MIG_OV_ID_MAP m
        INNER JOIN izgazMGR.dbo.LS_OV_TAH_INVOICE s
            ON s.SRC_KEY = m.SRC_KEY
        INNER JOIN dbo.LS_005_01_INVOICE inv
            ON inv.LREF = CAST(s.LREF_HINT AS INT)
           AND ISNULL(inv.[TYPE], 0) = 101
        WHERE m.OV_KIND = 'TAH_INV' AND m.ENERGY_LREF IS NULL
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);

        UPDATE mgr
        SET mgr.ENERGY_LREF = m.ENERGY_LREF
        FROM izgazMGR.dbo.LS_OV_ID_MAP mgr
        INNER JOIN dbo.MIG_OV_ID_MAP m
            ON m.SRC_KEY = mgr.SRC_KEY
        WHERE m.OV_KIND = 'TAH_INV' AND m.ENERGY_LREF IS NOT NULL
          AND mgr.ENERGY_LREF IS NULL
          AND (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND m.ABYS_AGREEMENT_ID IS NULL AND m.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND m.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 INSERT TAH_INV=' + CAST(@N AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ---- PAY_PT ---- */
    IF OBJECT_ID('tempdb..#PAY') IS NOT NULL DROP TABLE #PAY;
    SELECT
        s.SRC_KEY AS SRC_KEY,
        CAST(s.LREF_HINT AS INT) AS LREF_HINT,
        CAST(s.INVOICEREF AS INT) AS INVOICEREF,
        CAST(s.CROSSREF_MAIN_LREF AS INT) AS CROSSREF_MAIN_LREF,
        CAST(s.[TYPE] AS TINYINT) AS [TYPE],
        CAST(s.IOCODE AS TINYINT) AS IOCODE,
        CAST(s.PAYTYPE AS INT) AS PAYTYPE,
        CAST(s.TRANSTYPE AS INT) AS TRANSTYPE,
        CAST(s.LINETYPE AS INT) AS LINETYPE,
        CAST(ISNULL(s.INST_NR, 0) AS INT) AS INST_NR,
        energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)) AS DATE_,
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)) AS PAYABLETOTAL,
        CAST(ISNULL(s.CANCELED, 0) AS BIT) AS CANCELED,
        CAST(s.CLIENTREF AS INT) AS CLIENTREF,
        s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID,
        /* hint kullanilabilir mi? */
        CAST(CASE
            WHEN s.LREF_HINT BETWEEN 1 AND 2147483647
             AND NOT EXISTS (
                    SELECT 1 FROM dbo.LS_005_01_PAYTRANS t
                    WHERE t.LREF = CAST(s.LREF_HINT AS INT)
                  )
            THEN 1 ELSE 0 END AS BIT) AS USE_HINT,
        /* CROSSREF: borc PT (IOCODE=0) — WIRE da yeniden yazar */
        CAST((
            SELECT TOP (1) d.LREF
            FROM dbo.LS_005_01_PAYTRANS d WITH (NOLOCK)
            WHERE d.INVOICEREF = CAST(s.CROSSREF_MAIN_LREF AS INT)
              AND ISNULL(d.IOCODE, 0) = 0
              AND ISNULL(d.CANCELED, 0) = 0
              AND ISNULL(d.CANCELLATIONPAYMENT, 0) = 0
            ORDER BY d.LREF
        ) AS INT) AS CROSSREF_PT,
        CAST(s.BANKREF AS INT) AS BANKREF_SMS,
        CAST(s.BANK_RECORD_REF AS NVARCHAR(50)) AS BANK_RECORD_REF,
        CONVERT(FLOAT, CONVERT(DECIMAL(18,2), ISNULL(s.PAID, 0))) AS PAID_AMT
    INTO #PAY
    FROM izgazMGR.dbo.LS_OV_PAY_PT s WITH (NOLOCK)
    WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
      /* iptal tahsilat da yazilir: CANCELED=1, PAID=0; borc PAID DEBT_PAID ile (yalniz gecerli) */
      AND NOT EXISTS (
            SELECT 1 FROM dbo.MIG_OV_ID_MAP m
            WHERE m.SRC_KEY = s.SRC_KEY
              AND m.ENERGY_LREF IS NOT NULL
          )
    OPTION (RECOMPILE, MAXDOP 24);

    /* hint path — sadece bos LREF */
    BEGIN TRY
        SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS ON;
        INSERT INTO dbo.LS_005_01_PAYTRANS (
            LREF, INVOICEREF, [TYPE], IOCODE, CROSSREF, PAYTYPE, TRANSTYPE, LINETYPE, INST_NR,
            DATE_, PAYABLETOTAL, PAID, CANCELED, CLIENTREF, CLIENT_TYPE,
            ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF,
            BANKREF, BANK_RECORD_REF, LASTPAIDDATE
        )
        SELECT
            p.LREF_HINT, p.INVOICEREF, p.[TYPE], p.IOCODE,
            /* borc PT yoksa MAIN — WIRE sonra PT.LREF'e cevirir */
            COALESCE(p.CROSSREF_PT, p.CROSSREF_MAIN_LREF),
            p.PAYTYPE, p.TRANSTYPE, p.LINETYPE, p.INST_NR,
            p.DATE_, p.PAYABLETOTAL,
            CASE WHEN ISNULL(p.CANCELED, 0) = 0 THEN p.PAID_AMT ELSE 0 END,
            p.CANCELED, p.CLIENTREF, CAST(91 AS TINYINT),
            p.ABYS_ID, p.ABYS_ACCOUNT_ID, p.ABYS_AGREEMENT_ID, p.INVOICEREF,
            p.BANKREF_SMS, p.BANK_RECORD_REF,
            CASE WHEN ISNULL(p.CANCELED, 0) = 0 THEN p.DATE_ ELSE NULL END
        FROM #PAY p
        WHERE p.USE_HINT = 1
        OPTION (RECOMPILE, MAXDOP 24);
        SET @N = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        SET @N = 0;
        SET @Msg = N'597 PAY hint INSERT FAIL: ' + ERROR_MESSAGE();
        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;
        RAISERROR('%s', 16, 1, @Msg);
        RETURN;
    END CATCH
    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;

    /* MAP: yalniz insert edilen hint (PT IOCODE<>0 + LREF=HINT) */
    UPDATE m SET m.ENERGY_LREF = p.LREF_HINT
    FROM dbo.MIG_OV_ID_MAP m
    INNER JOIN #PAY p ON p.SRC_KEY = m.SRC_KEY
    INNER JOIN dbo.LS_005_01_PAYTRANS pt
        ON pt.LREF = p.LREF_HINT
       AND ISNULL(pt.IOCODE, 0) <> 0
    WHERE p.USE_HINT = 1 AND m.ENERGY_LREF IS NULL
    OPTION (RECOMPILE, MAXDOP 24);

    UPDATE mgr
    SET mgr.ENERGY_LREF = m.ENERGY_LREF
    FROM izgazMGR.dbo.LS_OV_ID_MAP mgr
    INNER JOIN dbo.MIG_OV_ID_MAP m
        ON m.SRC_KEY = mgr.SRC_KEY
    INNER JOIN #PAY p ON p.SRC_KEY = m.SRC_KEY AND p.USE_HINT = 1
    WHERE m.OV_KIND = 'PAY_PT' AND m.ENERGY_LREF IS NOT NULL AND mgr.ENERGY_LREF IS NULL
    OPTION (RECOMPILE, MAXDOP 24);

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 INSERT PAY_PT(hint)=' + CAST(@N AS VARCHAR(20))
                 + N' collide→identity=' + CAST((SELECT COUNT(*) FROM #PAY WHERE USE_HINT=0 AND LREF_HINT IS NOT NULL) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* identity path: multi-alloc + collide */
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT SRC_KEY FROM #PAY
        WHERE USE_HINT = 0
          AND NOT EXISTS (
                SELECT 1 FROM dbo.MIG_OV_ID_MAP m
                WHERE m.SRC_KEY = #PAY.SRC_KEY AND m.ENERGY_LREF IS NOT NULL
              );
    OPEN c;
    FETCH NEXT FROM c INTO @SRC;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;

        INSERT INTO dbo.LS_005_01_PAYTRANS (
            INVOICEREF, [TYPE], IOCODE, CROSSREF, PAYTYPE, TRANSTYPE, LINETYPE, INST_NR,
            DATE_, PAYABLETOTAL, PAID, CANCELED, CLIENTREF, CLIENT_TYPE,
            ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF,
            BANKREF, BANK_RECORD_REF, LASTPAIDDATE
        )
        SELECT
            INVOICEREF, [TYPE], IOCODE,
            COALESCE(CROSSREF_PT, CROSSREF_MAIN_LREF),
            PAYTYPE, TRANSTYPE, LINETYPE, INST_NR,
            DATE_, PAYABLETOTAL,
            CASE WHEN ISNULL(CANCELED, 0) = 0 THEN PAID_AMT ELSE 0 END,
            CANCELED, CLIENTREF, CAST(91 AS TINYINT),
            ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID, INVOICEREF,
            BANKREF_SMS, BANK_RECORD_REF,
            CASE WHEN ISNULL(CANCELED, 0) = 0 THEN DATE_ ELSE NULL END
        FROM #PAY WHERE SRC_KEY = @SRC;

        SET @NewLref = SCOPE_IDENTITY();
        IF @NewLref IS NULL
        BEGIN
            SET @Msg = N'597 PAY identity SCOPE_IDENTITY NULL SRC=' + @SRC;
            RAISERROR('%s', 16, 1, @Msg);
            CLOSE c; DEALLOCATE c;
            RETURN;
        END

        UPDATE dbo.MIG_OV_ID_MAP SET ENERGY_LREF = @NewLref WHERE SRC_KEY = @SRC;
        UPDATE izgazMGR.dbo.LS_OV_ID_MAP
        SET ENERGY_LREF = @NewLref
        WHERE SRC_KEY = @SRC;

        FETCH NEXT FROM c INTO @SRC;
    END
    CLOSE c; DEALLOCATE c;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'597 INSERT PAY_PT(identity)=' + CAST((SELECT COUNT(*) FROM #PAY WHERE USE_HINT=0) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* CANCEL_PAY / CANCEL_REV — IDENTITY */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_CANCEL_PAY', 'U') IS NOT NULL
    BEGIN
        DECLARE c2 CURSOR LOCAL FAST_FORWARD FOR
            SELECT s.SRC_KEY
            FROM izgazMGR.dbo.LS_OV_CANCEL_PAY s WITH (NOLOCK)
            WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
              AND NOT EXISTS (
                    SELECT 1 FROM dbo.MIG_OV_ID_MAP m
                    WHERE m.SRC_KEY = s.SRC_KEY
                      AND m.ENERGY_LREF IS NOT NULL
                  );
        OPEN c2;
        FETCH NEXT FROM c2 INTO @SRC;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;
            INSERT INTO dbo.LS_005_01_PAYTRANS (
                INVOICEREF, [TYPE], IOCODE, CROSSREF, PAYTYPE, TRANSTYPE, LINETYPE, INST_NR,
                DATE_, PAYABLETOTAL, PAID, CANCELED, CANCELLATIONPAYMENT, CLIENTREF, CLIENT_TYPE,
                ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID
            )
            SELECT
                NULL,
                CAST(s.[TYPE] AS TINYINT), CAST(s.IOCODE AS TINYINT),
                CAST(s.CROSSREF_MAIN_LREF AS INT),
                CAST(s.PAYTYPE AS INT), CAST(s.TRANSTYPE AS INT), CAST(s.LINETYPE AS INT), 0,
                energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
                CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
                0, CAST(0 AS BIT), CAST(1 AS INT),
                CAST(s.CLIENTREF AS INT), CAST(91 AS TINYINT),
                s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID
            FROM izgazMGR.dbo.LS_OV_CANCEL_PAY s WITH (NOLOCK)
            WHERE s.SRC_KEY = @SRC;

            SET @NewLref = SCOPE_IDENTITY();
            UPDATE dbo.MIG_OV_ID_MAP SET ENERGY_LREF = @NewLref WHERE SRC_KEY = @SRC;
            UPDATE izgazMGR.dbo.LS_OV_ID_MAP
            SET ENERGY_LREF = @NewLref
            WHERE SRC_KEY = @SRC;
            FETCH NEXT FROM c2 INTO @SRC;
        END
        CLOSE c2; DEALLOCATE c2;
    END

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_CANCEL_REV', 'U') IS NOT NULL
    BEGIN
        DECLARE c3 CURSOR LOCAL FAST_FORWARD FOR
            SELECT s.SRC_KEY
            FROM izgazMGR.dbo.LS_OV_CANCEL_REV s WITH (NOLOCK)
            WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
           OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
            )
              AND NOT EXISTS (
                    SELECT 1 FROM dbo.MIG_OV_ID_MAP m
                    WHERE m.SRC_KEY = s.SRC_KEY
                      AND m.ENERGY_LREF IS NOT NULL
                  );
        OPEN c3;
        FETCH NEXT FROM c3 INTO @SRC;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;
            INSERT INTO dbo.LS_005_01_PAYTRANS (
                INVOICEREF, [TYPE], IOCODE, CROSSREF, PAYTYPE, TRANSTYPE, LINETYPE, INST_NR,
                DATE_, PAYABLETOTAL, PAID, CANCELED, CANCELLATIONPAYMENT, CLIENTREF, CLIENT_TYPE,
                ABYS_ID, ABYS_ACCOUNT_ID, ABYS_AGREEMENT_ID
            )
            SELECT
                CAST(s.INVOICEREF AS INT),
                CAST(s.[TYPE] AS TINYINT), CAST(s.IOCODE AS TINYINT),
                CAST(s.CROSSREF_MAIN_LREF AS INT),
                CAST(s.PAYTYPE AS INT), CAST(s.TRANSTYPE AS INT), CAST(s.LINETYPE AS INT), 0,
                energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
                CONVERT(FLOAT, CONVERT(DECIMAL(18,2), s.PAYABLETOTAL)),
                0, CAST(0 AS BIT), CAST(1 AS INT),
                CAST(s.CLIENTREF AS INT), CAST(91 AS TINYINT),
                s.ABYS_ID, s.ABYS_ACCOUNT_ID, s.ABYS_AGREEMENT_ID
            FROM izgazMGR.dbo.LS_OV_CANCEL_REV s WITH (NOLOCK)
            WHERE s.SRC_KEY = @SRC;

            SET @NewLref = SCOPE_IDENTITY();
            UPDATE dbo.MIG_OV_ID_MAP SET ENERGY_LREF = @NewLref WHERE SRC_KEY = @SRC;
            UPDATE izgazMGR.dbo.LS_OV_ID_MAP
            SET ENERGY_LREF = @NewLref
            WHERE SRC_KEY = @SRC;
            FETCH NEXT FROM c3 INTO @SRC;
        END
        CLOSE c3; DEALLOCATE c3;
    END

    /* DEBT_PAID_UPD */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_DEBT_PAID_UPD', 'U') IS NOT NULL
    BEGIN
        UPDATE pt
        SET pt.PAID = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), d.PAID_AMT))
        FROM dbo.LS_005_01_PAYTRANS pt
        INNER JOIN izgazMGR.dbo.LS_OV_DEBT_PAID_UPD d WITH (NOLOCK)
            ON pt.INVOICEREF = CAST(d.MAIN_LREF AS INT)
           AND ISNULL(pt.IOCODE, 0) = 0
        WHERE (
              @AGR_ID IS NULL
           OR (@AGR_ID = -1 AND d.ABYS_AGREEMENT_ID IS NULL)
           OR (@AGR_ID > 0 AND d.ABYS_AGREEMENT_ID = @AGR_ID)
            )
        OPTION (RECOMPILE, MAXDOP 24);
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'597 INSERT DEBT_PAID_UPD=' + CAST(@@ROWCOUNT AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_PAYTRANS OFF; END TRY BEGIN CATCH END CATCH;
    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;

    SET @Ts = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    SET @Msg = @Ts + N' | E597 | INFO | INSERT bitti — sonraki WIRE zorunlu';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END
GO
