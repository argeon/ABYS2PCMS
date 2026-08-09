/* ============================================================
   SCRIPT_ID : INVOICE_DEBT_PAYTRANS_CHECK
   SCRIPT_NO : 577
   FILE      : 577_INVOICE_DEBT_PAYTRANS__check.sql
   VERSION   : 1
   ============================================================ */
-- Manuel kontrol sorgulari (deploy disi)
USE energy;
GO

-- Kaynak (IOCODE=0 invoice) vs hedef borç PT sayim
SELECT
    (SELECT COUNT_BIG(*)
     FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
     WHERE ISNULL(IOCODE, 0) = 0
       AND LREF BETWEEN 1 AND 2147483647
    ) AS SRC_INVOICE_IOCODE0,
    (SELECT COUNT_BIG(*)
     FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
     WHERE ISNULL(IOCODE, 0) = 0
       AND ABYS_ID IS NOT NULL
    ) AS TGT_DEBT_PT_ABYS,
    (SELECT COUNT_BIG(*)
     FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
     WHERE ISNULL(IOCODE, 0) = 0
       AND ABYS_ID IS NULL
    ) AS TGT_DEBT_PT_NATIVE;

-- Eksik borç PT (ornek TOP — 74M'de pahali)
SELECT COUNT_BIG(*) AS MISSING_DEBT_PT_SAMPLE
FROM (
    SELECT TOP (100000) inv.LREF, inv.ABYS_ID
    FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    WHERE ISNULL(inv.IOCODE, 0) = 0
      AND inv.LREF BETWEEN 1 AND 2147483647
    ORDER BY inv.LREF
) s
WHERE NOT EXISTS (
    SELECT 1
    FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
    WHERE pt.INVOICEREF = s.LREF
      AND ISNULL(pt.IOCODE, 0) = 0
      AND pt.ABYS_ID IS NOT NULL
);

-- Cift borç PT (olmamali)
SELECT TOP 50
    pt.INVOICEREF,
    COUNT_BIG(*) AS DEBT_PT_CNT
FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
WHERE ISNULL(pt.IOCODE, 0) = 0
  AND pt.ABYS_ID IS NOT NULL
GROUP BY pt.INVOICEREF
HAVING COUNT_BIG(*) > 1
ORDER BY DEBT_PT_CNT DESC;

-- Index durumu (post sonrasi)
SELECT i.name, i.type_desc, i.is_unique, i.is_disabled, i.filter_definition
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS')
ORDER BY i.index_id;

-- Ornek satir
SELECT TOP 20
    pt.LREF, pt.INVOICEREF, pt.IOCODE, pt.[TYPE], pt.CLIENTREF, pt.CLIENT_TYPE,
    pt.TLTOTAL, pt.PAYABLETOTAL, pt.PAID, pt.PAYTYPE, pt.TRANSTYPE, pt.LINETYPE,
    pt.CANCELED, pt.ABYS_ID, pt.ABYS_INVOICE_LREF, pt.ABYS_ACCOUNT_ID
FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
WHERE pt.ABYS_ID IS NOT NULL
  AND ISNULL(pt.IOCODE, 0) = 0
ORDER BY pt.LREF;
GO

-- ------------------------------------------------------------
-- Pilot AGR (197168) — Adim 3 gate ozeti
-- ------------------------------------------------------------
DECLARE @AGR_ID BIGINT = 197168;

SELECT
    (SELECT COUNT_BIG(*)
       FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
      WHERE ISNULL(IOCODE, 0) = 0 AND ABYS_AGREEMENT_ID = @AGR_ID) AS SRC_INV,
    (SELECT COUNT_BIG(*)
       FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
      WHERE ISNULL(IOCODE, 0) = 0 AND ABYS_ID IS NOT NULL
        AND ABYS_AGREEMENT_ID = @AGR_ID) AS TGT_DEBT_PT;

SELECT COUNT_BIG(*) AS MISSING_DEBT_PT
FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
WHERE ISNULL(inv.IOCODE, 0) = 0
  AND inv.ABYS_AGREEMENT_ID = @AGR_ID
  AND NOT EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
        WHERE pt.INVOICEREF = inv.LREF
          AND ISNULL(pt.IOCODE, 0) = 0 AND pt.ABYS_ID IS NOT NULL
      );
GO
