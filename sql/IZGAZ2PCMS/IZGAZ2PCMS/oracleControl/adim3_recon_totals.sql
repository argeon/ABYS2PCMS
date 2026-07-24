-- =============================================================================
-- ADIM3 RECON TOTALS — Oracle (MIGRATION)
-- energy / izgazMGR ile AYNI kolon seti (yan yana kıyas)
-- Pilot: AGR_ID = 197168
-- Not: ORA-00937 önlemek için INV ve LINE aggregate'leri ayrı blok
-- =============================================================================

SELECT
  'ORACLE'              AS SRC,
  inv.AGR_ID,
  inv.INV_CNT,
  inv.INV_IOCODE0,
  inv.INV_SUM,
  inv.INV_TL,
  inv.INV_TAX,
  inv.INV_GRAND,
  lin.LINE_CNT,
  lin.LINE_SUM,
  inv.EXPECTED_DEBT_PT,
  inv.EXPECTED_PT_SUM
FROM (
  SELECT
    197168                                              AS AGR_ID,
    COUNT(*)                                            AS INV_CNT,
    SUM(CASE WHEN NVL(IOCODE, 0) = 0 THEN 1 ELSE 0 END) AS INV_IOCODE0,
    ROUND(SUM(NVL(PAYABLETOTAL, 0)), 2)                 AS INV_SUM,
    ROUND(SUM(NVL(TLTOTAL, 0)), 2)                      AS INV_TL,
    ROUND(SUM(NVL(TAX, 0)), 2)                          AS INV_TAX,
    ROUND(SUM(NVL(GRANDTOTAL, 0)), 2)                   AS INV_GRAND,
    SUM(CASE WHEN NVL(IOCODE, 0) = 0 THEN 1 ELSE 0 END) AS EXPECTED_DEBT_PT,
    ROUND(SUM(CASE WHEN NVL(IOCODE, 0) = 0
                   THEN NVL(PAYABLETOTAL, 0) ELSE 0 END), 2) AS EXPECTED_PT_SUM
  FROM MIGRATION.LS_INVOICE
  WHERE ABYS_AGREEMENT_ID = 197168
) inv
CROSS JOIN (
  SELECT
    COUNT(*)                              AS LINE_CNT,
    ROUND(SUM(NVL(l.GRANDTOTAL, 0)), 2)   AS LINE_SUM
  FROM MIGRATION.LS_INVLINES l
  WHERE l.ABYS_AGREEMENT_ID = 197168
     OR l.INVOICEREF IN (
          SELECT i.LREF
          FROM MIGRATION.LS_INVOICE i
          WHERE i.ABYS_AGREEMENT_ID = 197168
        )
) lin;

-- Tip kirilimi (opsiyonel)
SELECT
  'ORACLE' AS SRC,
  TYPE,
  ABYS_ACTION_TYPE_ID,
  COUNT(*) ADET,
  ROUND(SUM(NVL(PAYABLETOTAL, 0)), 2) TOPLAM
FROM MIGRATION.LS_INVOICE
WHERE ABYS_AGREEMENT_ID = 197168
GROUP BY TYPE, ABYS_ACTION_TYPE_ID
ORDER BY ABYS_ACTION_TYPE_ID, TYPE;
/
