-- =============================================================================
-- ADIM 3 — Borç PAYTRANS beklenen gate (Oracle preview)
-- Kaynak : MIGRATION.LS_INVOICE (Adim 1)
-- Not    : Borç PT Oracle'da üretilmez; energy 575 INVOICE→PAYTRANS türetir.
--          Bu script yalnızca beklenen sayım/tutar (pilot doğrulama).
-- =============================================================================

-- Beklenen: 1 IOCODE=0 fatura → 1 borç PT
SELECT
  COUNT(*)                         AS EXPECTED_DEBT_PT,
  SUM(PAYABLETOTAL)                AS EXPECTED_PT_SUM,
  SUM(TLTOTAL)                     AS EXPECTED_TL,
  SUM(TAX)                         AS EXPECTED_TAX,
  SUM(GRANDTOTAL)                  AS EXPECTED_GRAND,
  COUNT(DISTINCT ABYS_AGREEMENT_ID) AS AGR_CNT,
  MIN(ABYS_AGREEMENT_ID)           AS AGR_ID
FROM MIGRATION.LS_INVOICE
WHERE NVL(IOCODE, 0) = 0;

-- Tip dağılımı (PT.TYPE = INV.TYPE)
SELECT TYPE, COUNT(*) ADET, SUM(PAYABLETOTAL) TOPLAM
FROM MIGRATION.LS_INVOICE
WHERE NVL(IOCODE, 0) = 0
GROUP BY TYPE
ORDER BY TYPE;

-- Energy gate ile karşılaştır:
--   EXPECTED_DEBT_PT ≈ 259 (pilot 197168)
--   EXPECTED_PT_SUM  ≈ 109843.94
-- Energy: 578_INVOICE_DEBT_PAYTRANS__pilot.sql
/
