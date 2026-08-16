/* =============================================================================
   prodREADY_ENERGY / CHECK_QUERIES_ENERGY — manuel dogrulama (read-only)
   Kullanim: sqlcmd -S ... -d energy -E -i CHECK_QUERIES_ENERGY.sql
            veya SSMS'te calistir.
   Gate (SP_MIG_590_GATE / 597_GATE) yerine gecmez; ara / kapanis spot check.
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;

PRINT '========== 1) MIG_STEP_LOG (son 40) ==========';
SELECT TOP 40
    LOG_ID, STEP_ID, STATUS, STEP_NAME,
    ROWCOUNT_NOTE, DURATION_SEC, NOTE,
    STARTED_AT, FINISHED_AT
FROM dbo.MIG_STEP_LOG
ORDER BY LOG_ID DESC;

PRINT '========== 2) FAIL / GATE_FAIL (0 beklenir) ==========';
SELECT STATUS, COUNT(*) CNT
FROM dbo.MIG_STEP_LOG
WHERE STATUS IN ('FAIL', 'GATE_FAIL')
GROUP BY STATUS;

PRINT '========== 3) LINENR tipi (SMALLINT beklenir) ==========';
SELECT c.name AS COL, t.name AS TYPE_NAME, c.max_length, c.precision, c.scale
FROM sys.columns c
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.LS_005_01_INVLINES')
  AND c.name IN ('LINENR', 'ABYS_LINENR_SRC');

PRINT '========== 4) MAP ozet (ENERGY_LREF fill) ==========';
SELECT OV_KIND,
       COUNT(*) AS CNT,
       SUM(CASE WHEN ENERGY_LREF IS NULL THEN 1 ELSE 0 END) AS ENERGY_NULL,
       SUM(CASE WHEN ENERGY_LREF IS NOT NULL THEN 1 ELSE 0 END) AS ENERGY_FILLED
FROM dbo.MIG_OV_ID_MAP
GROUP BY OV_KIND
ORDER BY OV_KIND
OPTION (RECOMPILE, MAXDOP 24);

PRINT '========== 5) 590 gate spot — IADE* ENERGY_LREF NULL (0 beklenir) ==========';
SELECT COUNT(*) AS IADE_ENERGY_NULL
FROM dbo.MIG_OV_ID_MAP
WHERE OV_KIND IN ('IADE_INV', 'IADE_IL', 'IADE_PT')
  AND ENERGY_LREF IS NULL
OPTION (RECOMPILE, MAXDOP 24);

PRINT '========== 6) MAIN RETURN_TARGET NULL (0 beklenir, overlay sonrasi) ==========';
SELECT COUNT(*) AS MAIN_RETURN_NULL
FROM izgazMGR.dbo.LS_OV_MAIN_UPD u WITH (NOLOCK)
INNER JOIN dbo.LS_005_01_INVOICE inv ON inv.LREF = CAST(u.LREF AS INT)
WHERE inv.RETURN_TARGET_INVREF IS NULL
OPTION (RECOMPILE, MAXDOP 24);

PRINT '========== 7) IADE_IL ABYS_ID <> LREF (0 beklenir) ==========';
SELECT COUNT(*) AS IADE_IL_ABYS_BAD
FROM dbo.MIG_OV_ID_MAP m
INNER JOIN dbo.LS_005_01_INVLINES il ON il.LREF = m.ENERGY_LREF
WHERE m.OV_KIND = 'IADE_IL'
  AND (il.ABYS_ID IS NULL OR il.ABYS_ID <> il.LREF)
OPTION (RECOMPILE, MAXDOP 24);

PRINT '========== 8) 597 gate spot — PAY_PT ENERGY_LREF NULL (0) ==========';
SELECT COUNT(*) AS PAY_ENERGY_NULL
FROM dbo.MIG_OV_ID_MAP
WHERE OV_KIND = 'PAY_PT'
  AND ENERGY_LREF IS NULL
OPTION (RECOMPILE, MAXDOP 24);

PRINT '========== 9) PAY CROSSREF NULL (PAY_PT wire sonrasi; 0 beklenir) ==========';
SELECT COUNT(*) AS PAY_CROSSREF_NULL
FROM dbo.MIG_OV_ID_MAP m
INNER JOIN dbo.LS_005_01_PAYTRANS pt ON pt.LREF = m.ENERGY_LREF
WHERE m.OV_KIND = 'PAY_PT'
  AND pt.CROSSREF IS NULL
OPTION (RECOMPILE, MAXDOP 24);

PRINT '========== 10) Spot ornek — IADE INV (5) ==========';
SELECT TOP 5
    m.SRC_KEY, m.ENERGY_LREF, inv.RETURN_TARGET_INVREF, inv.ABYS_ID
FROM dbo.MIG_OV_ID_MAP m
INNER JOIN dbo.LS_005_01_INVOICE inv ON inv.LREF = m.ENERGY_LREF
WHERE m.OV_KIND = 'IADE_INV';

PRINT '========== CHECK_QUERIES_ENERGY DONE ==========';
PRINT 'Beklenen: FAIL/GATE_FAIL yok; IADE/PAY ENERGY_NULL=0; RETURN_TARGET/CROSSREF/ABYS_ID OK';
GO
