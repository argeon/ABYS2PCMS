/* ============================================================
   FILE : 70_rapor_tahakkuk_tahsilat_gelir.sql
   DB   : energy (PCMS)
   Amac : Gelir Fatura Raporu toplamlarini SSMS'te dogrulamak
          (Tahakkuk + Tahsilat + Gelir satir kirilimi)
          Tutarlar DECIMAL(18,2) — FLOAT SUM kurus sapmasi yok

   PCMS UI "Gelir Fatura Raporu" ile karsi lastirmak icin:
     - TAHAKKUK  ≈ IOCODE=0 fatura PAYABLETOTAL / GRANDTOTAL
     - GELIR     ≈ INVLINES.GRANDTOTAL (gelir kodu kirilimi)
     - TAHSILAT  ≈ IOCODE=1 PAYTRANS.PAYABLETOTAL (TYPE=101 fisi)

   Calistir: SSMS → energy → F5
   ============================================================ */
USE energy;
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

/* ---- parametreler (UI rapor filtresi ile ayni yapin) ---- */
DECLARE @DateFrom   DATETIME = '2020-01-01';
DECLARE @DateTo     DATETIME = '2026-12-31';   -- inclusive gun: gun sonuna kadar
DECLARE @AGR_ID     BIGINT   = NULL;           -- ornek: 197168; NULL = tumu
DECLARE @InclCancel BIT      = 0;              -- 0 = iptaller haric (UI varsayilan)
DECLARE @Eps        DECIMAL(18,2) = 0.01;

DECLARE @DateToExcl DATETIME = DATEADD(DAY, 1, CAST(@DateTo AS DATE));

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121)
    + ' | rapor @DateFrom=' + CONVERT(VARCHAR(10), @DateFrom, 120)
    + ' @DateTo=' + CONVERT(VARCHAR(10), @DateTo, 120)
    + ' @AGR_ID=' + ISNULL(CAST(@AGR_ID AS VARCHAR(20)), 'ALL')
    + ' | tutarlar DECIMAL(18,2) (FLOAT SUM yok)';

/* ============================================================
   1) OZET — Tahakkuk / Tahsilat / Gelir (tek bakista)
      Tutarlar: CONVERT(DECIMAL(18,2), …) — kurus dogrulugu
   ============================================================ */
PRINT '=== 1) OZET TOPLAMLAR ===';

;WITH Inv AS (
    SELECT
        inv.LREF,
        ISNULL(inv.IOCODE, 0) AS IOCODE,
        ISNULL(inv.[TYPE], 0) AS INV_TYPE,
        ISNULL(inv.CANCELED, 0) AS CANCELED,
        CONVERT(DECIMAL(18,2), inv.TLTOTAL) AS TLTOTAL,
        CONVERT(DECIMAL(18,2), inv.TAX) AS TAX,
        CONVERT(DECIMAL(18,2), inv.GRANDTOTAL) AS GRANDTOTAL,
        CONVERT(DECIMAL(18,2), inv.PAYABLETOTAL) AS PAYABLETOTAL
    FROM dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    WHERE inv.ABYS_ID IS NOT NULL
      AND inv.DATE_ >= @DateFrom
      AND inv.DATE_ <  @DateToExcl
      AND (@AGR_ID IS NULL OR inv.ABYS_AGREEMENT_ID = @AGR_ID)
      AND (@InclCancel = 1 OR ISNULL(inv.CANCELED, 0) = 0)
),
DebtPt AS (
    SELECT
        pt.LREF,
        CONVERT(DECIMAL(18,2), pt.PAYABLETOTAL) AS PAYABLETOTAL,
        CONVERT(DECIMAL(18,2), pt.PAID) AS PAID,
        ISNULL(pt.CANCELED, 0) AS CANCELED
    FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
    WHERE pt.ABYS_ID IS NOT NULL
      AND ISNULL(pt.IOCODE, 0) = 0
      AND pt.DATE_ >= @DateFrom
      AND pt.DATE_ <  @DateToExcl
      AND (@AGR_ID IS NULL OR pt.ABYS_AGREEMENT_ID = @AGR_ID)
      AND (@InclCancel = 1 OR ISNULL(pt.CANCELED, 0) = 0)
),
PayPt AS (
    SELECT
        pt.LREF,
        CONVERT(DECIMAL(18,2), pt.PAYABLETOTAL) AS PAYABLETOTAL,
        ISNULL(pt.CANCELED, 0) AS CANCELED,
        ISNULL(pt.CANCELLATIONPAYMENT, 0) AS CANCELLATIONPAYMENT
    FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
    WHERE pt.ABYS_ID IS NOT NULL
      AND ISNULL(pt.IOCODE, 0) = 1
      AND pt.DATE_ >= @DateFrom
      AND pt.DATE_ <  @DateToExcl
      AND (@AGR_ID IS NULL OR pt.ABYS_AGREEMENT_ID = @AGR_ID)
      AND (@InclCancel = 1 OR ISNULL(pt.CANCELED, 0) = 0)
),
Lines AS (
    SELECT
        l.LREF,
        CONVERT(DECIMAL(18,2), l.TLTOTAL) AS TLTOTAL,
        CONVERT(DECIMAL(18,2), l.TAX) AS TAX,
        CONVERT(DECIMAL(18,2), l.GRANDTOTAL) AS GRANDTOTAL,
        ISNULL(l.CANCELED, 0) AS CANCELED,
        ISNULL(l.ABYS_IS_VAT_INCOME, 0) AS IS_VAT,
        ISNULL(l.ABYS_IS_DISCOUNT, 0) AS IS_DISC
    FROM dbo.LS_005_01_INVLINES l WITH (NOLOCK)
    INNER JOIN dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
        ON inv.LREF = l.INVOICEREF
    WHERE l.ABYS_ID IS NOT NULL
      AND inv.ABYS_ID IS NOT NULL
      AND ISNULL(inv.IOCODE, 0) = 0          -- gelir satirlari tahakkuk faturasina bagli
      AND inv.DATE_ >= @DateFrom
      AND inv.DATE_ <  @DateToExcl
      AND (@AGR_ID IS NULL OR inv.ABYS_AGREEMENT_ID = @AGR_ID)
      AND (@InclCancel = 1 OR ISNULL(inv.CANCELED, 0) = 0)
      AND (@InclCancel = 1 OR ISNULL(l.CANCELED, 0) = 0)
)
SELECT metric, adet, tutar
FROM (
    SELECT 1 AS ord, N'TAHAKKUK_INV (IOCODE=0)' AS metric,
           COUNT_BIG(*) AS adet,
           SUM(PAYABLETOTAL) AS tutar
    FROM Inv WHERE IOCODE = 0
    UNION ALL
    SELECT 2, N'TAHAKKUK_INV_GRANDTOTAL',
           COUNT_BIG(*), SUM(GRANDTOTAL)
    FROM Inv WHERE IOCODE = 0
    UNION ALL
    SELECT 3, N'TAHAKKUK_INV_TLTOTAL',
           COUNT_BIG(*), SUM(TLTOTAL)
    FROM Inv WHERE IOCODE = 0
    UNION ALL
    SELECT 4, N'TAHAKKUK_INV_TAX',
           COUNT_BIG(*), SUM(TAX)
    FROM Inv WHERE IOCODE = 0
    UNION ALL
    SELECT 5, N'DEBT_PT (IOCODE=0 PAYABLE)',
           COUNT_BIG(*), SUM(PAYABLETOTAL)
    FROM DebtPt
    UNION ALL
    SELECT 6, N'DEBT_PT_PAID (tahsil edilen)',
           COUNT_BIG(*), SUM(PAID)
    FROM DebtPt
    UNION ALL
    SELECT 7, N'TAHSILAT_PT (IOCODE=1)',
           COUNT_BIG(*), SUM(PAYABLETOTAL)
    FROM PayPt
      WHERE CANCELLATIONPAYMENT = 0
    UNION ALL
    SELECT 8, N'TAHSILAT_FISI (TYPE=101)',
           COUNT_BIG(*), SUM(PAYABLETOTAL)
    FROM Inv WHERE INV_TYPE = 101
    UNION ALL
    SELECT 9, N'GELIR_SATIR (INVLINES.GRANDTOTAL)',
           COUNT_BIG(*), SUM(GRANDTOTAL)
    FROM Lines
    UNION ALL
    SELECT 10, N'GELIR_SATIR_TLTOTAL',
           COUNT_BIG(*), SUM(TLTOTAL)
    FROM Lines
    UNION ALL
    SELECT 11, N'GELIR_SATIR_TAX (KDV)',
           COUNT_BIG(*), SUM(TAX)
    FROM Lines
) x
ORDER BY ord;

/* ============================================================
   2) GELIR FATURA RAPORU — gelir kodu kirilimi
      (UI "Gelir Fatura" satirlari ile karsilastirin)
   ============================================================ */
PRINT '=== 2) GELIR KIRILIMI (kod) ===';

SELECT
    l.ABYS_INCOME_ID,
    l.ABYS_INCOME_CODE,
    /* isim kolonu yoksa kod yeterli */
    CASE
        WHEN ISNULL(l.ABYS_IS_DISCOUNT, 0) = 1 THEN N'INDIRIM'
        WHEN ISNULL(l.ABYS_IS_VAT_INCOME, 0) = 1 THEN N'KDV'
        WHEN l.ABYS_INCOME_ID IN (958, 1929) THEN N'DEVIR'
        WHEN l.ABYS_INCOME_ID IN (939, 7658) THEN N'GAZ_SKB'
        ELSE N'DIGER'
    END AS GRUP,
    COUNT_BIG(*) AS ADET,
    SUM(CONVERT(DECIMAL(18,2), l.TLTOTAL)) AS TLTOTAL,
    SUM(CONVERT(DECIMAL(18,2), l.TAX)) AS TAX,
    SUM(CONVERT(DECIMAL(18,2), l.GRANDTOTAL)) AS GRANDTOTAL
FROM dbo.LS_005_01_INVLINES l WITH (NOLOCK)
INNER JOIN dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    ON inv.LREF = l.INVOICEREF
WHERE l.ABYS_ID IS NOT NULL
  AND inv.ABYS_ID IS NOT NULL
  AND ISNULL(inv.IOCODE, 0) = 0
  AND inv.DATE_ >= @DateFrom
  AND inv.DATE_ <  @DateToExcl
  AND (@AGR_ID IS NULL OR inv.ABYS_AGREEMENT_ID = @AGR_ID)
  AND (@InclCancel = 1 OR ISNULL(inv.CANCELED, 0) = 0)
  AND (@InclCancel = 1 OR ISNULL(l.CANCELED, 0) = 0)
GROUP BY
    l.ABYS_INCOME_ID,
    l.ABYS_INCOME_CODE,
    CASE
        WHEN ISNULL(l.ABYS_IS_DISCOUNT, 0) = 1 THEN N'INDIRIM'
        WHEN ISNULL(l.ABYS_IS_VAT_INCOME, 0) = 1 THEN N'KDV'
        WHEN l.ABYS_INCOME_ID IN (958, 1929) THEN N'DEVIR'
        WHEN l.ABYS_INCOME_ID IN (939, 7658) THEN N'GAZ_SKB'
        ELSE N'DIGER'
    END
ORDER BY GRANDTOTAL DESC;

/* ============================================================
   3) GRUP OZET (INDIRIM / KDV / GAZ / DEVIR)
   ============================================================ */
PRINT '=== 3) GELIR GRUP OZET ===';

SELECT
    CASE
        WHEN ISNULL(l.ABYS_IS_DISCOUNT, 0) = 1 THEN N'INDIRIM'
        WHEN ISNULL(l.ABYS_IS_VAT_INCOME, 0) = 1 THEN N'KDV'
        WHEN l.ABYS_INCOME_ID IN (958, 1929) THEN N'DEVIR'
        WHEN l.ABYS_INCOME_ID IN (939, 7658) THEN N'GAZ_SKB'
        ELSE N'DIGER'
    END AS GRUP,
    COUNT_BIG(*) AS ADET,
    SUM(CONVERT(DECIMAL(18,2), l.GRANDTOTAL)) AS GRANDTOTAL
FROM dbo.LS_005_01_INVLINES l WITH (NOLOCK)
INNER JOIN dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    ON inv.LREF = l.INVOICEREF
WHERE l.ABYS_ID IS NOT NULL
  AND inv.ABYS_ID IS NOT NULL
  AND ISNULL(inv.IOCODE, 0) = 0
  AND inv.DATE_ >= @DateFrom
  AND inv.DATE_ <  @DateToExcl
  AND (@AGR_ID IS NULL OR inv.ABYS_AGREEMENT_ID = @AGR_ID)
  AND (@InclCancel = 1 OR ISNULL(inv.CANCELED, 0) = 0)
  AND (@InclCancel = 1 OR ISNULL(l.CANCELED, 0) = 0)
GROUP BY
    CASE
        WHEN ISNULL(l.ABYS_IS_DISCOUNT, 0) = 1 THEN N'INDIRIM'
        WHEN ISNULL(l.ABYS_IS_VAT_INCOME, 0) = 1 THEN N'KDV'
        WHEN l.ABYS_INCOME_ID IN (958, 1929) THEN N'DEVIR'
        WHEN l.ABYS_INCOME_ID IN (939, 7658) THEN N'GAZ_SKB'
        ELSE N'DIGER'
    END
ORDER BY 1;

/* ============================================================
   4) TUTARLIİK — fatura basligi vs gelir satirlari
      (Gelir Fatura toplami ≈ Tahakkuk GRANDTOTAL olmali)
   ============================================================ */
PRINT '=== 4) INV vs LINES (soft gate) ===';

;WITH Inv0 AS (
    SELECT
        inv.LREF,
        CONVERT(DECIMAL(18,2), inv.PAYABLETOTAL) AS INV_PAYABLE,
        CONVERT(DECIMAL(18,2), inv.GRANDTOTAL) AS INV_GRAND
    FROM dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    WHERE inv.ABYS_ID IS NOT NULL
      AND ISNULL(inv.IOCODE, 0) = 0
      AND inv.DATE_ >= @DateFrom
      AND inv.DATE_ <  @DateToExcl
      AND (@AGR_ID IS NULL OR inv.ABYS_AGREEMENT_ID = @AGR_ID)
      AND (@InclCancel = 1 OR ISNULL(inv.CANCELED, 0) = 0)
),
LineSum AS (
    SELECT
        l.INVOICEREF,
        SUM(CONVERT(DECIMAL(18,2), l.GRANDTOTAL)) AS LINE_GRAND
    FROM dbo.LS_005_01_INVLINES l WITH (NOLOCK)
    WHERE l.ABYS_ID IS NOT NULL
      AND (@InclCancel = 1 OR ISNULL(l.CANCELED, 0) = 0)
      AND EXISTS (SELECT 1 FROM Inv0 i WHERE i.LREF = l.INVOICEREF)
    GROUP BY l.INVOICEREF
)
SELECT
    SUM(i.INV_PAYABLE) AS INV_PAYABLE_SUM,
    SUM(i.INV_GRAND)   AS INV_GRAND_SUM,
    SUM(ISNULL(ls.LINE_GRAND, 0)) AS LINE_GRAND_SUM,
    SUM(i.INV_PAYABLE) - SUM(ISNULL(ls.LINE_GRAND, 0)) AS DELTA_PAYABLE_VS_LINES,
    SUM(CASE WHEN ABS(i.INV_PAYABLE - ISNULL(ls.LINE_GRAND, 0)) > @Eps THEN 1 ELSE 0 END) AS FARKLI_FATURA_ADET,
    CASE
        WHEN ABS(SUM(i.INV_PAYABLE) - SUM(ISNULL(ls.LINE_GRAND, 0))) <= @Eps THEN 'PASS'
        ELSE 'FAIL'
    END AS GATE
FROM Inv0 i
LEFT JOIN LineSum ls ON ls.INVOICEREF = i.LREF;

/* ============================================================
   5) TAHSILAT KIRILIMI — islem tipi (ABYS_ACTION_TYPE_ID)
   ============================================================ */
PRINT '=== 5) TAHSILAT TIP KIRILIMI ===';

SELECT
    pt.ABYS_ACTION_TYPE_ID,
    tt.[VALUE] AS TIP_ADI,
    COUNT_BIG(*) AS ADET,
    SUM(CONVERT(DECIMAL(18,2), pt.PAYABLETOTAL)) AS TUTAR
FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
LEFT JOIN dbo.LS_TRANSACTION_TYPE tt WITH (NOLOCK)
    ON tt.CODE = pt.ABYS_ACTION_TYPE_ID
WHERE pt.ABYS_ID IS NOT NULL
  AND ISNULL(pt.IOCODE, 0) = 1
  AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
  AND pt.DATE_ >= @DateFrom
  AND pt.DATE_ <  @DateToExcl
  AND (@AGR_ID IS NULL OR pt.ABYS_AGREEMENT_ID = @AGR_ID)
  AND (@InclCancel = 1 OR ISNULL(pt.CANCELED, 0) = 0)
GROUP BY pt.ABYS_ACTION_TYPE_ID, tt.[VALUE]
ORDER BY TUTAR DESC;

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + ' | rapor bitti';
GO
