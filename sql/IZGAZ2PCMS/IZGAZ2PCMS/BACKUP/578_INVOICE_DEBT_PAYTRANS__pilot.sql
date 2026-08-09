/* ============================================================
   SCRIPT_ID : INVOICE_DEBT_PAYTRANS_PILOT
   SCRIPT_NO : 578
   FILE      : 578_INVOICE_DEBT_PAYTRANS__pilot.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- ADIM 3 — Borç PAYTRANS (pilot)
--
-- Oracle CTAS YOK. Borç PT, energy'de IOCODE=0 faturalardan türetilir.
-- Onkoşul: 570/571 (INVOICE) pilot AGR için yüklü olmalı.
-- INVLINES (581) borç PT için zorunlu değil; pipeline sırası: 571→581→575.
--
-- Sabitler (575 ile aynı):
--   IOCODE=0, PAID=0, PAYTYPE=174, TRANSTYPE=113, LINETYPE=103
--   1 invoice (IOCODE=0) → 1 borç PAYTRANS
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @AGR_ID BIGINT = 197168;   -- pilot
DECLARE @HARD_RESET BIT = 0;       -- 1: yalnız bu AGR borç PT sil + yeniden yaz

-- ------------------------------------------------------------
-- 0) Ön kontrol: fatura var mı?
-- ------------------------------------------------------------
SELECT
    @AGR_ID AS AGR_ID,
    COUNT_BIG(*) AS INV_IOCODE0,
    SUM(CAST(PAYABLETOTAL AS FLOAT)) AS INV_SUM
FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
WHERE ISNULL(IOCODE, 0) = 0
  AND ABYS_AGREEMENT_ID = @AGR_ID;

IF NOT EXISTS (
    SELECT 1
    FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
    WHERE ISNULL(IOCODE, 0) = 0
      AND ABYS_AGREEMENT_ID = @AGR_ID
)
BEGIN
    RAISERROR('Pilot AGR icin IOCODE=0 fatura yok. Once 571 calistirin.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- 1) Setup (idempotent) + migrate
--    Once: 574_INVOICE_DEBT_PAYTRANS__setup.sql deploy edilmis olmali
-- ------------------------------------------------------------
DECLARE @AGR_ID BIGINT = 197168;   -- = LS_005_01_AGR.AGREEMENT_NUMBER
DECLARE @HARD_RESET BIT = 0;

EXEC energy.dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
    @AGR_ID     = @AGR_ID,
    @HARD_RESET = @HARD_RESET,
    @RESUME     = 0,
    @BATCH_SIZE = 1000,
    @DEBUG      = 1;
GO

-- ------------------------------------------------------------
-- 2) Gate (Adim-3)
-- ------------------------------------------------------------
DECLARE @AGR_ID BIGINT = 197168;

-- V1: 1:1 sayim
SELECT
    (SELECT COUNT_BIG(*)
       FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
      WHERE ISNULL(IOCODE, 0) = 0
        AND ABYS_AGREEMENT_ID = @AGR_ID) AS SRC_INV,
    (SELECT COUNT_BIG(*)
       FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
      WHERE ISNULL(IOCODE, 0) = 0
        AND ABYS_ID IS NOT NULL
        AND ABYS_AGREEMENT_ID = @AGR_ID) AS TGT_DEBT_PT;

-- V2: eksik PT
SELECT COUNT_BIG(*) AS MISSING_DEBT_PT
FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
WHERE ISNULL(inv.IOCODE, 0) = 0
  AND inv.ABYS_AGREEMENT_ID = @AGR_ID
  AND NOT EXISTS (
        SELECT 1
        FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
        WHERE pt.INVOICEREF = inv.LREF
          AND ISNULL(pt.IOCODE, 0) = 0
          AND pt.ABYS_ID IS NOT NULL
      );

-- V3: cift PT (olmamali)
SELECT pt.INVOICEREF, COUNT_BIG(*) AS DEBT_PT_CNT
FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
WHERE ISNULL(pt.IOCODE, 0) = 0
  AND pt.ABYS_ID IS NOT NULL
  AND pt.ABYS_AGREEMENT_ID = @AGR_ID
GROUP BY pt.INVOICEREF
HAVING COUNT_BIG(*) > 1;

-- V4: tutar + sabitler
SELECT
    SUM(CASE WHEN pt.PAYTYPE <> 174 OR pt.TRANSTYPE <> 113 OR pt.LINETYPE <> 103
                  OR ISNULL(pt.PAID, 0) <> 0 OR ISNULL(pt.IOCODE, 0) <> 0
             THEN 1 ELSE 0 END) AS BAD_CONST,
    SUM(CASE WHEN ABS(ISNULL(pt.PAYABLETOTAL, 0) - ISNULL(inv.PAYABLETOTAL, 0)) > 0.01
             THEN 1 ELSE 0 END) AS BAD_AMT,
    SUM(CASE WHEN pt.ABYS_INVOICE_LREF <> inv.LREF OR pt.INVOICEREF <> inv.LREF
             THEN 1 ELSE 0 END) AS BAD_REF,
    SUM(CAST(pt.PAYABLETOTAL AS FLOAT)) AS PT_SUM,
    SUM(CAST(inv.PAYABLETOTAL AS FLOAT)) AS INV_SUM
FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
JOIN energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
  ON inv.LREF = pt.INVOICEREF
WHERE ISNULL(pt.IOCODE, 0) = 0
  AND pt.ABYS_ID IS NOT NULL
  AND pt.ABYS_AGREEMENT_ID = @AGR_ID;

-- V5: ornek
SELECT TOP 20
    pt.LREF, pt.INVOICEREF, pt.IOCODE, pt.[TYPE], pt.PAYTYPE, pt.TRANSTYPE,
    pt.TLTOTAL, pt.TAX, pt.GRANDTOTAL, pt.PAYABLETOTAL, pt.PAID,
    pt.ABYS_ID, pt.ABYS_ACCOUNT_ID, pt.ABYS_AGREEMENT_ID
FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
WHERE ISNULL(pt.IOCODE, 0) = 0
  AND pt.ABYS_ID IS NOT NULL
  AND pt.ABYS_AGREEMENT_ID = @AGR_ID
ORDER BY pt.INVOICEREF;

-- Gate: SRC_INV=TGT_DEBT_PT(=259 beklenen), MISSING=0, BAD_*=0, PT_SUM=INV_SUM
-- Sonraki: tahsilat / eksilten delta (Adim 4+)
GO
