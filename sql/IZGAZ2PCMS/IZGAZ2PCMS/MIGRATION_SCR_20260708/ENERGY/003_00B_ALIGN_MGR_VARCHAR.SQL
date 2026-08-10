/* ============================================================
   prodREADY_ENERGY / 00b_align_mgr_varchar  — CHECK ONLY
   REV 2026-08-08

   Aktarım sırasında ALTER YOK.
   Dump (MigrationEngine) Oracle VARCHAR2 → MSSQL VARCHAR üretmeli.
   Bu script yalnızca join-key kolonlarının VARCHAR olduğunu doğrular.

   Eski dump (NVARCHAR kaldıysa) acil APPLY:
     00b_align_mgr_varchar__APPLY.sql
   ============================================================ */
USE izgazMGR;
GO
SET NOCOUNT ON;

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + ' | 00b_align_mgr_varchar CHECK START';

;WITH expected AS (
    SELECT * FROM (VALUES
        ('LS_OV_ID_MAP',        'OV_KIND',              'varchar'),
        ('LS_OV_ID_MAP',        'SRC_KEY',              'varchar'),
        ('LS_OV_ID_MAP',        'PARENT_SRC_KEY',       'varchar'),
        ('LS_OV_PAY_PT',        'OV_KIND',              'varchar'),
        ('LS_OV_PAY_PT',        'SRC_KEY',              'varchar'),
        ('LS_OV_TAH_INVOICE',   'OV_KIND',              'varchar'),
        ('LS_OV_TAH_INVOICE',   'SRC_KEY',              'varchar'),
        ('LS_OV_TAH_INVOICE',   'FICHENO',              'varchar'),
        ('LS_OV_TAH_INVOICE',   'EXPLAIN',              'varchar'),
        ('LS_OV_CANCEL_PAY',    'OV_KIND',              'varchar'),
        ('LS_OV_CANCEL_PAY',    'SRC_KEY',              'varchar'),
        ('LS_OV_CANCEL_PAY',    'INVOICE_SRC_KEY',      'varchar'),
        ('LS_OV_CANCEL_REV',    'OV_KIND',              'varchar'),
        ('LS_OV_CANCEL_REV',    'SRC_KEY',              'varchar'),
        ('LS_OV_IADE_INVOICE',  'OV_KIND',              'varchar'),
        ('LS_OV_IADE_INVOICE',  'SRC_KEY',              'varchar'),
        ('LS_OV_IADE_INVLINES', 'OV_KIND',              'varchar'),
        ('LS_OV_IADE_INVLINES', 'SRC_KEY',              'varchar'),
        ('LS_OV_IADE_PAYTRANS', 'OV_KIND',              'varchar'),
        ('LS_OV_IADE_PAYTRANS', 'SRC_KEY',              'varchar'),
        ('LS_OV_KISMI_INVLINES','OV_KIND',              'varchar'),
        ('LS_OV_KISMI_INVLINES','SRC_KEY',              'varchar'),
        ('LS_OV_KISMI_PAYTRANS','OV_KIND',              'varchar'),
        ('LS_OV_KISMI_PAYTRANS','SRC_KEY',              'varchar'),
        ('LS_OV_MAIN_UPD',      'RETURN_TARGET_SRC_KEY','varchar'),
        ('LS_OV_PAY_ALLOC',     'OV_KIND',              'varchar')
    ) v(tbl, col, want_typ)
),
actual AS (
    SELECT
        t.name AS tbl,
        c.name AS col,
        ty.name AS typ
    FROM sys.tables t
    JOIN sys.columns c ON c.object_id = t.object_id
    JOIN sys.types ty ON c.user_type_id = ty.user_type_id
    WHERE t.is_ms_shipped = 0
)
SELECT
    e.tbl,
    e.col,
    e.want_typ,
    ISNULL(a.typ, '(missing)') AS actual_typ,
    CASE
        WHEN a.typ IS NULL THEN 'MISSING'
        WHEN a.typ = e.want_typ THEN 'OK'
        ELSE 'FAIL'
    END AS status
INTO #align_check
FROM expected e
LEFT JOIN actual a ON a.tbl = e.tbl AND a.col = e.col
WHERE OBJECT_ID('dbo.' + e.tbl, 'U') IS NOT NULL;

SELECT * FROM #align_check ORDER BY status DESC, tbl, col;

DECLARE @fail INT = (SELECT COUNT(*) FROM #align_check WHERE status = 'FAIL');
DECLARE @ok   INT = (SELECT COUNT(*) FROM #align_check WHERE status = 'OK');

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121)
    + ' | 00b CHECK ok=' + CAST(@ok AS VARCHAR(10))
    + ' fail=' + CAST(@fail AS VARCHAR(10));

IF @fail > 0
BEGIN
    RAISERROR('00b_align CHECK FAIL: %d join-key column(s) still NVARCHAR (or wrong type). Dump should use MigrationEngine VARCHAR mapping; emergency: 00b_align_mgr_varchar__APPLY.sql', 16, 1, @fail);
END
ELSE
    PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + ' | 00b_align_mgr_varchar CHECK PASS (no ALTER)';

DROP TABLE #align_check;
GO
