-- 925_DIAG_DV_TYPE109_V01.SQL
-- Amac: Soft assert TYPE109/111 DV + damga satiri
-- Gate: yok
-- Sonraki: (son)
WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- =============================================================================
-- oracleCTAS3007 / diag — DV TYPE109/111 soft assert (RUNALL disi)
-- Onkosul: 11_ls_invoice + 12_ls_invlines
-- Paket karsiligi: MIGRATION_SCR_20260708/CTAS/925_DIAG_DV_TYPE109_V01.SQL
-- =============================================================================

PROMPT ========== DIAG DV TYPE109/111 ==========

SELECT
  COUNT(*) AS INV_109_111,
  SUM(CASE WHEN NVL(inv.DV, 0) > 0.01 THEN 1 ELSE 0 END) AS DV_GT0,
  SUM(CASE WHEN NVL(inv.DV, 0) <= 0.01 THEN 1 ELSE 0 END) AS DV_EQ0,
  SUM(CASE
        WHEN ABS(NVL(inv.TLTOTAL, 0) + NVL(inv.TAX, 0) + NVL(inv.DV, 0)
                 - NVL(inv.GRANDTOTAL, 0)) <= 0.02 THEN 1
        ELSE 0
      END) AS TL_TAX_DV_EQ_GT
FROM MIGRATION.LS_INVOICE inv
WHERE inv.TYPE IN (109, 111)
  AND NVL(inv.CANCELED, 0) = 0;

SELECT
  COUNT(*) AS HAS_DAMGA_LINE,
  SUM(CASE WHEN NVL(inv.DV, 0) <= 0.01 THEN 1 ELSE 0 END) AS BAD_DV0_WITH_DAMGA,
  SUM(CASE
        WHEN ABS(NVL(inv.DV, 0) - d.WANT_DV) <= 0.02 THEN 1
        ELSE 0
      END) AS DV_EQ_INCOME
FROM MIGRATION.LS_INVOICE inv
JOIN (
  SELECT il.INVOICEREF,
         ROUND(SUM(NVL(il.GRANDTOTAL, 0)), 3) AS WANT_DV
  FROM MIGRATION.LS_INVLINES il
  WHERE il.ABYS_INCOME_ID IN (23032, 938, 1863)
     OR il.TRANSTYPE IN (23032, 938, 1863)
  GROUP BY il.INVOICEREF
) d ON d.INVOICEREF = inv.LREF
WHERE inv.TYPE IN (109, 111)
  AND NVL(inv.CANCELED, 0) = 0
  AND d.WANT_DV > 0.01;

SELECT
  COUNT(*) AS DAMGA_LINES,
  SUM(CASE
        WHEN NVL(il.TLTOTAL, 0) <= 0.01
         AND ABS(NVL(il.DV, 0) - NVL(il.GRANDTOTAL, 0)) <= 0.02 THEN 1
        ELSE 0
      END) AS IL_DV_OK,
  SUM(CASE
        WHEN NVL(il.TLTOTAL, 0) > 0.01 AND NVL(il.DV, 0) <= 0.01 THEN 1
        ELSE 0
      END) AS IL_STILL_IN_TL
FROM MIGRATION.LS_INVLINES il
JOIN MIGRATION.LS_INVOICE inv ON inv.LREF = il.INVOICEREF
WHERE inv.TYPE IN (109, 111)
  AND (il.ABYS_INCOME_ID IN (23032, 938, 1863) OR il.TRANSTYPE IN (23032, 938, 1863));

PROMPT ========== DIAG DV OK (BAD / IL_STILL_IN_TL beklenen 0) ==========
/

