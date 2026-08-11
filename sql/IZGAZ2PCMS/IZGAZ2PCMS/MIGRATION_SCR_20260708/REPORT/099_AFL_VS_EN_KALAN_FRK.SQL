/* =============================================================================
   90_afl_frk / 99_afl_vs_en_kalan_frk.sql
   CREATE OR ALTER PROCEDURE dbo.SP_MIG_99_AFL_EN_FRK  (R23 2026-08-11)
   AFL.BALANCE vs Energy EN_KALAN.
   EXEC dbo.SP_MIG_99_AFL_EN_FRK @OnlyDiff = 1;
   ============================================================================= */
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_99_AFL_EN_FRK
    @Eps      DECIMAL(18,2) = 0.02,
    @OnlyDiff BIT           = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

;WITH en_acc AS (
    SELECT
        inv.ABYS_ACCOUNT_ID AS ACCOUNT_ID,
        MAX(inv.OWNERREF) AS OWNERREF,
        MAX(inv.CLIENTREF) AS CLIENTREF,
        MAX(inv.FITNO) AS FITNO,
        COUNT(*) AS OPEN_INV_CNT,
        CONVERT(DECIMAL(18,2),
            SUM(CONVERT(DECIMAL(18,2), ISNULL(inv.PAYABLETOTAL, 0)))
        ) AS EN_PAYABLE,
        CONVERT(DECIMAL(18,2), SUM(ISNULL(pt.PT_KALAN, 0))) AS EN_KALAN
    FROM dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    LEFT JOIN (
        SELECT
            INVOICEREF,
            SUM(
                CONVERT(DECIMAL(18,2), ISNULL(PAYABLETOTAL, 0))
              - CONVERT(DECIMAL(18,2), ISNULL(PAID, 0))
            ) AS PT_KALAN
        FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
        WHERE ISNULL(IOCODE, 0) = 0
          AND ISNULL(CANCELED, 0) = 0
          AND ISNULL(CANCELLATIONPAYMENT, 0) = 0
        GROUP BY INVOICEREF
    ) pt ON pt.INVOICEREF = inv.LREF
    WHERE ISNULL(inv.CLOSED, 0) = 0
      AND ISNULL(inv.IOCODE, 0) = 0
      AND ISNULL(inv.CANCELED, 0) = 0
      AND inv.ABYS_ACCOUNT_ID IS NOT NULL
    GROUP BY inv.ABYS_ACCOUNT_ID
)
SELECT
    /* ---- SOL: AFL ---- */
    afl.FATURAID            AS AFL_FATURAID,
    afl.SOZLESME_HESABI     AS AFL_SOZLESME_HESABI,
    afl.INSTALLMENT_ID      AS AFL_TESISAT,
    afl.LEGAL_PROCEEDING_ID AS AFL_YASAL_TAKIP_NO,
    afl.SUBSCRIBER_TYPE     AS AFL_SICIL_TIP,
    CONVERT(DECIMAL(18,2), ISNULL(afl.BALANCE, 0)) AS AFL_BALANCE,

    /* ---- SAG: Energy (LEFT) ---- */
    e.ACCOUNT_ID            AS EN_ACCOUNT_ID,
    e.OWNERREF              AS EN_SOZLESMENO,
    e.CLIENTREF             AS EN_SICILNO,
    e.FITNO                 AS EN_TESISATNO,
    ISNULL(e.OPEN_INV_CNT, 0) AS EN_OPEN_INV_CNT,
    e.EN_PAYABLE            AS EN_PAYABLE,   -- odenecek (CLOSED=0 PAYABLE sum)
    e.EN_KALAN              AS EN_KALAN,     -- kalan (PT)

    CONVERT(DECIMAL(18,2),
        ISNULL(e.EN_KALAN, 0) - ISNULL(afl.BALANCE, 0)
    ) AS DELTA_KALAN,
    CASE
        WHEN e.ACCOUNT_ID IS NULL
            THEN 'AFL_ONLY'              -- AFL var, acik Energy borc INV yok
        WHEN ABS(ISNULL(e.EN_KALAN, 0) - ISNULL(afl.BALANCE, 0)) <= @Eps
            THEN 'MATCH'
        ELSE 'KALAN_FRK'
    END AS FARK_TIPI
FROM dbo.LS_AFL_OPEN_DEBT afl WITH (NOLOCK)
LEFT JOIN en_acc e
    ON e.ACCOUNT_ID = afl.FATURAID
WHERE @OnlyDiff = 0
   OR e.ACCOUNT_ID IS NULL
   OR ABS(ISNULL(e.EN_KALAN, 0) - ISNULL(afl.BALANCE, 0)) > @Eps
ORDER BY
    CASE
        WHEN e.ACCOUNT_ID IS NULL THEN 0
        WHEN ABS(ISNULL(e.EN_KALAN, 0) - ISNULL(afl.BALANCE, 0)) > @Eps THEN 1
        ELSE 2
    END,
    ABS(ISNULL(e.EN_KALAN, 0) - ISNULL(afl.BALANCE, 0)) DESC,
    afl.FATURAID;

END
GO
/* EXEC dbo.SP_MIG_99_AFL_EN_FRK @OnlyDiff = 1; */
