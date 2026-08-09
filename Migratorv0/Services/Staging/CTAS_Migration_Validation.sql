-- =============================================================================
-- CTAS_Migration_Validation.sql
-- Comprehensive validation for Oracle → izgazMGR → ENERGY migration
-- =============================================================================

USE izgazMGR;
GO

-- =============================================================================
-- 1. ROW COUNT VALIDATION
-- =============================================================================

PRINT '========== Row Count Validation =========='
PRINT ''

-- Create temp table for results
IF OBJECT_ID('tempdb..#ValidationResults') IS NOT NULL DROP TABLE #ValidationResults;
CREATE TABLE #ValidationResults (
    TABLE_NAME VARCHAR(100),
    ORACLE_COUNT BIGINT,
    IZGAZMGR_COUNT BIGINT,
    ENERGY_COUNT BIGINT,
    DIFF_ORA_MGR BIGINT,
    DIFF_MGR_EN BIGINT,
    DIFF_ORA_EN BIGINT,
    STATUS VARCHAR(20)
);

-- LS_INVOICE
DECLARE @OraInv BIGINT, @MgrInv BIGINT, @EnInv BIGINT;

-- Oracle count (via linked server or manual input)
-- SET @OraInv = (SELECT COUNT(*) FROM [ORACLE_SMS]...LS_INVOICE);
SET @OraInv = 75000000;  -- Manual input for now

SET @MgrInv = (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_INVOICE);
SET @EnInv = (SELECT COUNT_BIG(*) FROM IZGAZ.dbo.LS_315_0126_INVOICE);

INSERT INTO #ValidationResults VALUES (
    'LS_INVOICE', 
    @OraInv, 
    @MgrInv, 
    @EnInv,
    @OraInv - @MgrInv,
    @MgrInv - @EnInv,
    @OraInv - @EnInv,
    CASE 
        WHEN ABS(@OraInv - @EnInv) = 0 THEN 'PASS'
        WHEN ABS(@OraInv - @EnInv) < 100 THEN 'WARN'
        ELSE 'FAIL'
    END
);

-- LS_INVLINES
DECLARE @OraLines BIGINT, @MgrLines BIGINT, @EnLines BIGINT;
SET @OraLines = 350000000;
SET @MgrLines = (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_INVLINES);
SET @EnLines = (SELECT COUNT_BIG(*) FROM IZGAZ.dbo.LS_315_0126_INVLINES);

INSERT INTO #ValidationResults VALUES (
    'LS_INVLINES', 
    @OraLines, 
    @MgrLines, 
    @EnLines,
    @OraLines - @MgrLines,
    @MgrLines - @EnLines,
    @OraLines - @EnLines,
    CASE 
        WHEN ABS(@OraLines - @EnLines) = 0 THEN 'PASS'
        WHEN ABS(@OraLines - @EnLines) < 1000 THEN 'WARN'
        ELSE 'FAIL'
    END
);

-- LS_DEBT_PAYTRANS
DECLARE @OraDebt BIGINT, @MgrDebt BIGINT, @EnDebt BIGINT;
SET @OraDebt = 150000000;
SET @MgrDebt = (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_DEBT_PAYTRANS);
SET @EnDebt = (SELECT COUNT_BIG(*) FROM IZGAZ.dbo.LS_315_0126_PAYTRANS);

INSERT INTO #ValidationResults VALUES (
    'LS_DEBT_PAYTRANS', 
    @OraDebt, 
    @MgrDebt, 
    @EnDebt,
    @OraDebt - @MgrDebt,
    @MgrDebt - @EnDebt,
    @OraDebt - @EnDebt,
    CASE 
        WHEN ABS(@OraDebt - @EnDebt) = 0 THEN 'PASS'
        WHEN ABS(@OraDebt - @EnDebt) < 500 THEN 'WARN'
        ELSE 'FAIL'
    END
);

-- Display results
SELECT * FROM #ValidationResults ORDER BY TABLE_NAME;

DECLARE @FailCount INT = (SELECT COUNT(*) FROM #ValidationResults WHERE STATUS = 'FAIL');
IF @FailCount > 0
BEGIN
    RAISERROR('VALIDATION FAILED: %d tables have significant row count differences', 16, 1, @FailCount);
END
ELSE
BEGIN
    PRINT 'Row count validation: PASSED'
END
PRINT ''

-- =============================================================================
-- 2. DATA QUALITY VALIDATION
-- =============================================================================

PRINT '========== Data Quality Validation =========='
PRINT ''

-- NULL checks
SELECT 
    'LS_INVOICE' AS TABLE_NAME,
    'LREF_NULL' AS CHECK_TYPE,
    COUNT(*) AS NULL_COUNT
FROM izgazMGR.dbo.LS_INVOICE
WHERE LREF IS NULL
HAVING COUNT(*) > 0

UNION ALL

SELECT 
    'LS_INVOICE',
    'OWNERREF_NULL',
    COUNT(*)
FROM izgazMGR.dbo.LS_INVOICE
WHERE OWNERREF IS NULL
HAVING COUNT(*) > 0

UNION ALL

SELECT 
    'LS_INVLINES',
    'INVOICE_LREF_NULL',
    COUNT(*)
FROM izgazMGR.dbo.LS_INVLINES
WHERE INVOICE_LREF IS NULL
HAVING COUNT(*) > 0

UNION ALL

SELECT 
    'LS_INVLINES',
    'AMOUNT_NULL',
    COUNT(*)
FROM izgazMGR.dbo.LS_INVLINES
WHERE AMOUNT IS NULL
HAVING COUNT(*) > 0;

-- Orphaned records check
PRINT 'Checking for orphaned INVLINES...'
SELECT 
    COUNT(*) AS ORPHANED_INVLINES_COUNT
FROM izgazMGR.dbo.LS_INVLINES lines
WHERE NOT EXISTS (
    SELECT 1 
    FROM izgazMGR.dbo.LS_INVOICE inv
    WHERE inv.LREF = lines.INVOICE_LREF
);

-- Duplicate LREF check
PRINT 'Checking for duplicate LREFs in LS_INVOICE...'
SELECT 
    LREF,
    COUNT(*) AS DUPLICATE_COUNT
FROM izgazMGR.dbo.LS_INVOICE
GROUP BY LREF
HAVING COUNT(*) > 1;

PRINT ''

-- =============================================================================
-- 3. SAMPLE DATA COMPARISON (izgazMGR vs ENERGY)
-- =============================================================================

PRINT '========== Sample Data Comparison (izgazMGR vs ENERGY) =========='
PRINT ''

-- Random 1000 invoices comparison
WITH SampleInvoices AS (
    SELECT TOP 1000 LREF
    FROM izgazMGR.dbo.LS_INVOICE
    WHERE OWNERREF % 1000 = 0
    ORDER BY NEWID()
)
SELECT 
    CASE 
        WHEN mgr.LREF IS NULL THEN 'MISSING_IN_MGR'
        WHEN en.LREF IS NULL THEN 'MISSING_IN_ENERGY'
        WHEN mgr.PAYABLETOTAL <> en.PAYABLETOTAL THEN 'AMOUNT_MISMATCH'
        WHEN mgr.CLOSED <> en.CLOSED THEN 'STATUS_MISMATCH'
        ELSE 'OK'
    END AS STATUS,
    COUNT(*) AS COUNT
FROM SampleInvoices s
LEFT JOIN izgazMGR.dbo.LS_INVOICE mgr ON mgr.LREF = s.LREF
LEFT JOIN IZGAZ.dbo.LS_315_0126_INVOICE en ON en.LREF = s.LREF
GROUP BY CASE 
        WHEN mgr.LREF IS NULL THEN 'MISSING_IN_MGR'
        WHEN en.LREF IS NULL THEN 'MISSING_IN_ENERGY'
        WHEN mgr.PAYABLETOTAL <> en.PAYABLETOTAL THEN 'AMOUNT_MISMATCH'
        WHEN mgr.CLOSED <> en.CLOSED THEN 'STATUS_MISMATCH'
        ELSE 'OK'
    END;

PRINT ''

-- =============================================================================
-- 4. REFERENTIAL INTEGRITY CHECK
-- =============================================================================

PRINT '========== Referential Integrity Check =========='
PRINT ''

-- INVLINES → INVOICE integrity
PRINT 'Checking INVLINES → INVOICE references...'
SELECT 
    'izgazMGR' AS SYSTEM,
    COUNT(*) AS ORPHANED_LINES
FROM izgazMGR.dbo.LS_INVLINES lines
WHERE NOT EXISTS (
    SELECT 1 FROM izgazMGR.dbo.LS_INVOICE inv
    WHERE inv.LREF = lines.INVOICE_LREF
)

UNION ALL

SELECT 
    'ENERGY',
    COUNT(*)
FROM IZGAZ.dbo.LS_315_0126_INVLINES lines
WHERE NOT EXISTS (
    SELECT 1 FROM IZGAZ.dbo.LS_315_0126_INVOICE inv
    WHERE inv.LREF = lines.INVOICE_LREF
);

-- PAYTRANS → INVOICE integrity
PRINT 'Checking PAYTRANS → INVOICE references...'
SELECT 
    'izgazMGR' AS SYSTEM,
    COUNT(*) AS ORPHANED_PAYTRANS
FROM izgazMGR.dbo.LS_DEBT_PAYTRANS pt
WHERE NOT EXISTS (
    SELECT 1 FROM izgazMGR.dbo.LS_INVOICE inv
    WHERE inv.LREF = pt.INVOICEREF
)

UNION ALL

SELECT 
    'ENERGY',
    COUNT(*)
FROM IZGAZ.dbo.LS_315_0126_PAYTRANS pt
WHERE NOT EXISTS (
    SELECT 1 FROM IZGAZ.dbo.LS_315_0126_INVOICE inv
    WHERE inv.LREF = pt.INVOICEREF
);

PRINT ''

-- =============================================================================
-- 5. BUSINESS RULE VALIDATION
-- =============================================================================

PRINT '========== Business Rule Validation =========='
PRINT ''

-- Rule 1: CLOSED invoices should have PAYABLETOTAL = PAID
PRINT 'Checking closed invoice payment consistency...'
SELECT 
    'ENERGY' AS SYSTEM,
    COUNT(*) AS CLOSED_BUT_UNPAID_COUNT
FROM IZGAZ.dbo.LS_315_0126_INVOICE inv
LEFT JOIN (
    SELECT INVOICEREF, SUM(PAID) AS TOTAL_PAID
    FROM IZGAZ.dbo.LS_315_0126_PAYTRANS
    WHERE CANCELED = 0
    GROUP BY INVOICEREF
) pt ON pt.INVOICEREF = inv.LREF
WHERE inv.CLOSED = 1
  AND (pt.TOTAL_PAID IS NULL OR ABS(inv.PAYABLETOTAL - pt.TOTAL_PAID) > 0.01);

-- Rule 2: Open invoices should have BALANCE > 0
PRINT 'Checking open invoice balance consistency...'
SELECT 
    'ENERGY' AS SYSTEM,
    COUNT(*) AS OPEN_BUT_ZERO_BALANCE_COUNT
FROM IZGAZ.dbo.LS_315_0126_INVOICE inv
LEFT JOIN (
    SELECT INVOICEREF, 
           SUM(PAYABLETOTAL - PAID) AS BALANCE
    FROM IZGAZ.dbo.LS_315_0126_PAYTRANS
    WHERE CANCELED = 0
    GROUP BY INVOICEREF
) pt ON pt.INVOICEREF = inv.LREF
WHERE inv.CLOSED = 0
  AND (pt.BALANCE IS NULL OR pt.BALANCE <= 0.01);

-- Rule 3: CANCELED invoices should not be CLOSED
PRINT 'Checking canceled vs closed consistency...'
SELECT 
    'ENERGY' AS SYSTEM,
    COUNT(*) AS CANCELED_AND_CLOSED_COUNT
FROM IZGAZ.dbo.LS_315_0126_INVOICE
WHERE CANCELED = 1 AND CLOSED = 1;

PRINT ''

-- =============================================================================
-- 6. AGGREGATE VALIDATION
-- =============================================================================

PRINT '========== Aggregate Validation =========='
PRINT ''

-- Total PAYABLETOTAL comparison
SELECT 
    'LS_INVOICE' AS TABLE_NAME,
    (SELECT SUM(PAYABLETOTAL) FROM izgazMGR.dbo.LS_INVOICE) AS IZGAZMGR_TOTAL,
    (SELECT SUM(PAYABLETOTAL) FROM IZGAZ.dbo.LS_315_0126_INVOICE) AS ENERGY_TOTAL,
    (SELECT SUM(PAYABLETOTAL) FROM izgazMGR.dbo.LS_INVOICE) - 
    (SELECT SUM(PAYABLETOTAL) FROM IZGAZ.dbo.LS_315_0126_INVOICE) AS DIFFERENCE;

-- Total INVLINES AMOUNT comparison
SELECT 
    'LS_INVLINES' AS TABLE_NAME,
    (SELECT SUM(AMOUNT) FROM izgazMGR.dbo.LS_INVLINES) AS IZGAZMGR_TOTAL,
    (SELECT SUM(AMOUNT) FROM IZGAZ.dbo.LS_315_0126_INVLINES) AS ENERGY_TOTAL,
    (SELECT SUM(AMOUNT) FROM izgazMGR.dbo.LS_INVLINES) - 
    (SELECT SUM(AMOUNT) FROM IZGAZ.dbo.LS_315_0126_INVLINES) AS DIFFERENCE;

PRINT ''

-- =============================================================================
-- 7. PERFORMANCE METRICS
-- =============================================================================

PRINT '========== Performance Metrics =========='
PRINT ''

-- Table sizes
SELECT 
    t.name AS TABLE_NAME,
    p.rows AS ROW_COUNT,
    CAST((SUM(a.total_pages) * 8.0 / 1024 / 1024) AS DECIMAL(10,2)) AS SIZE_GB,
    i.name AS INDEX_NAME,
    CASE WHEN i.index_id = 1 THEN 'CLUSTERED' ELSE 'NONCLUSTERED' END AS INDEX_TYPE
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.name LIKE 'LS_%'
  AND t.schema_id = SCHEMA_ID('dbo')
GROUP BY t.name, p.rows, i.name, i.index_id
ORDER BY t.name, i.index_id;

-- Index fragmentation
SELECT 
    OBJECT_NAME(ips.object_id) AS TABLE_NAME,
    i.name AS INDEX_NAME,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE OBJECT_NAME(ips.object_id) LIKE 'LS_%'
  AND ips.avg_fragmentation_in_percent > 30
ORDER BY ips.avg_fragmentation_in_percent DESC;

PRINT ''

-- =============================================================================
-- 8. FINAL SUMMARY
-- =============================================================================

PRINT '========== Validation Summary =========='
PRINT ''

DECLARE @PassCount INT, @WarnCount INT, @FailCount2 INT;

SELECT 
    @PassCount = SUM(CASE WHEN STATUS = 'PASS' THEN 1 ELSE 0 END),
    @WarnCount = SUM(CASE WHEN STATUS = 'WARN' THEN 1 ELSE 0 END),
    @FailCount2 = SUM(CASE WHEN STATUS = 'FAIL' THEN 1 ELSE 0 END)
FROM #ValidationResults;

PRINT 'Row Count Validation:'
PRINT '  PASS: ' + CAST(@PassCount AS VARCHAR)
PRINT '  WARN: ' + CAST(@WarnCount AS VARCHAR)
PRINT '  FAIL: ' + CAST(@FailCount2 AS VARCHAR)
PRINT ''

IF @FailCount2 = 0 AND @WarnCount = 0
BEGIN
    PRINT '=========================================='
    PRINT '  ✅ ALL VALIDATIONS PASSED'
    PRINT '=========================================='
END
ELSE IF @FailCount2 > 0
BEGIN
    PRINT '=========================================='
    PRINT '  ❌ VALIDATION FAILED'
    PRINT '  Review differences above'
    PRINT '=========================================='
    RAISERROR('Validation failed', 16, 1);
END
ELSE
BEGIN
    PRINT '=========================================='
    PRINT '  ⚠️  VALIDATION WARNING'
    PRINT '  Minor differences detected'
    PRINT '=========================================='
END

-- Cleanup
DROP TABLE #ValidationResults;

GO
