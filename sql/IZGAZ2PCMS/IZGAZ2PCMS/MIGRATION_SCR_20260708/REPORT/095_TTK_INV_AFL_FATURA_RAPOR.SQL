/* =============================================================================
   90_afl_frk / 95_ttk_inv_afl_fatura_rapor.sql
   CREATE OR ALTER PROCEDURE dbo.SP_MIG_95_TTK_AFL_RAPOR  (R23 2026-08-11)
   1 fatura = 1 satir — TTK + AFL + INV + PT kalan fark raporu.
   EXEC dbo.SP_MIG_95_TTK_AFL_RAPOR;
   EXEC dbo.SP_MIG_95_TTK_AFL_RAPOR @Eps = 0.02;
   ============================================================================= */
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_95_TTK_AFL_RAPOR
    @Eps DECIMAL(18,2) = 0.02
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    inv.LREF                                              AS INV_LREF,
    inv.ABYS_ACCOUNT_ID                                   AS ACCOUNT_ID,
    inv.ABYS_AGREEMENT_ID                                 AS AGREEMENT_ID,
    inv.ABYS_ACCRUE_TYPE_ID                               AS ACCRUE_TYPE_ID,
    CAST(inv.DATE_ AS DATE)                               AS TAHAKKUK_TARIHI,
    CAST(inv.DUEDATE AS DATE)                             AS SON_ODEME,

    /* TTK master */
    CONVERT(DECIMAL(18,2), t.TOPLAM_TAHAKKUK)             AS TTK_TAH,
    CONVERT(DECIMAL(18,2), t.KALAN_TUTAR)                 AS TTK_KALAN,

    /* AFL tahsilat / acik borc */
    CONVERT(DECIMAL(18,2), afl.BALANCE)                   AS AFL_TUTAR,
    LEFT(CAST(afl.TAKSIT_DURUMU AS VARCHAR(1)), 1)        AS AFL_TAKSIT,
    LEFT(CAST(afl.YT_DURUMU AS VARCHAR(3)), 3)            AS AFL_YT,

    /* Invoice */
    CONVERT(DECIMAL(18,2), inv.PAYABLETOTAL)              AS INV_PAYABLETOTAL,
    CAST(ISNULL(inv.CLOSED, 0) AS TINYINT)                AS INV_CLOSED,

    /* Borc PAYTRANS (CANCEL_REV haric) */
    ISNULL(pt.PT_CNT, 0)                                  AS PT_CNT,
    ISNULL(pt.CP_REV_CNT, 0)                              AS CP_REV_CNT,  -- CANCEL_REV adedi (bilgi)
    CONVERT(DECIMAL(18,2), pt.PT_PAYABLE)                 AS PT_PAYABLETOTAL,
    CONVERT(DECIMAL(18,2), pt.PT_PAID)                    AS PT_PAID,
    CONVERT(DECIMAL(18,2), pt.PT_KALAN)                   AS PT_KALAN,
    CASE
        WHEN pt.INVOICEREF IS NULL                         THEN 'PT_YOK'
        WHEN ISNULL(pt.PT_KALAN, 0) <= @Eps                THEN 'KAPALI'
        WHEN ISNULL(pt.PT_PAID, 0)  <= @Eps                THEN 'ACIK'
        ELSE 'KISMI'
    END                                                   AS BORC_DURUM,

    /* AFL vs energy kalan (AFL yok = 0) */
    CONVERT(DECIMAL(18,2),
        ISNULL(pt.PT_KALAN, 0) - ISNULL(afl.BALANCE, 0)
    )                                                     AS DELTA_KALAN_AFL

FROM dbo.LS_005_01_INVOICE inv WITH (NOLOCK)

LEFT JOIN dbo.TUKETIM_TUTAR_KONTROL t WITH (NOLOCK)
    ON t.ACCOUNT_ID = inv.ABYS_ACCOUNT_ID

LEFT JOIN dbo.LS_AFL_OPEN_DEBT afl WITH (NOLOCK)
    ON afl.FATURAID = inv.ABYS_ACCOUNT_ID

LEFT JOIN (
    SELECT
        INVOICEREF,
        SUM(CASE WHEN ISNULL(CANCELLATIONPAYMENT, 0) = 0 THEN 1 ELSE 0 END) AS PT_CNT,
        SUM(CASE WHEN ISNULL(CANCELLATIONPAYMENT, 0) = 1 THEN 1 ELSE 0 END) AS CP_REV_CNT,
        SUM(CASE WHEN ISNULL(CANCELLATIONPAYMENT, 0) = 0
                 THEN CONVERT(DECIMAL(18,2), ISNULL(PAYABLETOTAL, 0)) ELSE 0 END) AS PT_PAYABLE,
        SUM(CASE WHEN ISNULL(CANCELLATIONPAYMENT, 0) = 0
                 THEN CONVERT(DECIMAL(18,2), ISNULL(PAID, 0)) ELSE 0 END) AS PT_PAID,
        SUM(CASE WHEN ISNULL(CANCELLATIONPAYMENT, 0) = 0
                 THEN CONVERT(DECIMAL(18,2), ISNULL(PAYABLETOTAL, 0)) ELSE 0 END)
      - SUM(CASE WHEN ISNULL(CANCELLATIONPAYMENT, 0) = 0
                 THEN CONVERT(DECIMAL(18,2), ISNULL(PAID, 0)) ELSE 0 END) AS PT_KALAN
    FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
    WHERE ISNULL(IOCODE, 0) = 0
      AND ISNULL(CANCELED, 0) = 0
    GROUP BY INVOICEREF
) pt ON pt.INVOICEREF = inv.LREF

WHERE inv.TYPE in (119,121,86)
  AND ISNULL(inv.CANCELED, 0) = 0
  AND inv.ABYS_ACCOUNT_ID IS NOT NULL
  /* gercek fark: tahakkuk (TTK) veya kalan (AFL) */
  AND (
        ABS(ISNULL(inv.PAYABLETOTAL, 0) - ISNULL(t.TOPLAM_TAHAKKUK, 0)) > @Eps
     OR ABS(ISNULL(pt.PT_KALAN, 0) - ISNULL(afl.BALANCE, 0)) > @Eps
  )

ORDER BY ABS(ISNULL(pt.PT_KALAN, 0) - ISNULL(afl.BALANCE, 0)) DESC;

END
GO
/* EXEC dbo.SP_MIG_95_TTK_AFL_RAPOR; */
