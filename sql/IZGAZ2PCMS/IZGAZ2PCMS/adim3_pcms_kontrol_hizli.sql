/* ============================================================
   FILE : adim3_pcms_kontrol_hizli.sql
   PCMS (energy) hizli kontrol — TARAMA YOK
   Mantik: izgazMGR'den 259 LREF al → energy'de yalniz PK / INVOICEREF seek
   ============================================================ */
USE energy;
GO

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @AGR_ID BIGINT = 197168;
DECLARE @Eps    FLOAT  = 0.01;
DECLARE @t0     DATETIME2(3) = SYSDATETIME();

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + ' | basladi AGR=' + CAST(@AGR_ID AS VARCHAR(20));

/* ---- 0) Index durumu (PT icin kritik) ---- */
SELECT
    i.name AS index_name,
    i.is_disabled,
    OBJECT_NAME(i.object_id) AS table_name
FROM sys.indexes i
WHERE i.object_id IN (
        OBJECT_ID('dbo.LS_005_01_INVOICE'),
        OBJECT_ID('dbo.LS_005_01_PAYTRANS')
      )
  AND i.name IN (
        'IX_MIG_INV_ABYS_AGR',
        'IX_MIG_PT_INVREF_IO',
        'IX_LS005_PAYTRANS_INVOICEREF',
        'UX_LS005_PAYTRANS_ABYS_ID'
      );

DECLARE @HasPtInvrefIndex BIT = 0;
IF EXISTS (
    SELECT 1
    FROM sys.indexes i
    INNER JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.key_ordinal = 1
    INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE i.object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
      AND i.type > 0
      AND i.is_disabled = 0
      AND c.name = 'INVOICEREF'
)
    SET @HasPtInvrefIndex = 1;

IF @HasPtInvrefIndex = 0
BEGIN
    PRINT 'UYARI: PAYTRANS uzerinde aktif INVOICEREF index YOK.';
    IF EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('dbo.LS_005_01_PAYTRANS')
          AND name = 'IX_MIG_PT_INVREF_IO'
          AND is_disabled = 1
    )
    BEGIN
        PRINT 'IX_MIG_PT_INVREF_IO DISABLED — enable edin:';
        PRINT 'ALTER INDEX IX_MIG_PT_INVREF_IO ON dbo.LS_005_01_PAYTRANS REBUILD WITH (SORT_IN_TEMPDB = ON, MAXDOP = 4);';
    END
    ELSE
    BEGIN
        PRINT 'Once su indexi kurun (bir kez; uzun surebilir ama sonraki kontroller saniyelik olur):';
        PRINT 'CREATE NONCLUSTERED INDEX IX_MIG_PT_INVREF_IO ON dbo.LS_005_01_PAYTRANS (INVOICEREF, IOCODE) INCLUDE (LREF, ABYS_ID, PAYABLETOTAL, ABYS_AGREEMENT_ID) WHERE ABYS_ID IS NOT NULL;';
    END
END

/* ---- 1) Kaynak anahtarlar (kucuk) ---- */
IF OBJECT_ID('tempdb..#K') IS NOT NULL DROP TABLE #K;
CREATE TABLE #K (
    LREF INT NOT NULL PRIMARY KEY,
    PAYABLETOTAL FLOAT NULL,
    IOCODE INT NULL
);

INSERT INTO #K (LREF, PAYABLETOTAL, IOCODE)
SELECT
    CAST(s.ABYS_ACTION_ID AS INT),
    CAST(s.PAYABLETOTAL AS FLOAT),
    ISNULL(CAST(s.IOCODE AS INT), 0)
FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
WHERE s.ABYS_AGREEMENT_ID = @AGR_ID
  AND s.ABYS_ACTION_ID BETWEEN 1 AND 2147483647;

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121)
    + ' | #K=' + CAST(@@ROWCOUNT AS VARCHAR(20))
    + ' ms=' + CAST(DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS VARCHAR(20));

/* ---- 2) INVOICE: PK seek (LREF) ---- */
SELECT
    'IZGAZMGR' AS SRC,
    COUNT(*) AS INV_CNT,
    ROUND(SUM(PAYABLETOTAL), 2) AS INV_SUM
FROM #K
UNION ALL
SELECT
    'ENERGY_INV',
    COUNT(*),
    ROUND(SUM(CAST(t.PAYABLETOTAL AS FLOAT)), 2)
FROM #K k
INNER LOOP JOIN energy.dbo.LS_005_01_INVOICE t WITH (NOLOCK, FORCESEEK)
    ON t.LREF = k.LREF
OPTION (MAXDOP 1);

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121)
    + ' | invoice OK ms=' + CAST(DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS VARCHAR(20));

/* ---- 3) Eksik fatura (PK) ---- */
SELECT COUNT(*) AS INV_MISSING
FROM #K k
WHERE NOT EXISTS (
    SELECT 1
    FROM energy.dbo.LS_005_01_INVOICE t WITH (NOLOCK, FORCESEEK)
    WHERE t.LREF = k.LREF
);

/* ---- 4) BORC PT — sadece index varsa ---- */
IF @HasPtInvrefIndex = 1
BEGIN
    SELECT
        'ENERGY_DEBT_PT' AS SRC,
        COUNT(*) AS PT_CNT,
        ROUND(SUM(CAST(pt.PAYABLETOTAL AS FLOAT)), 2) AS PT_SUM
    FROM #K k
    INNER LOOP JOIN energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK, FORCESEEK)
        ON pt.INVOICEREF = k.LREF
    WHERE ISNULL(pt.IOCODE, 0) = 0
      AND pt.ABYS_ID IS NOT NULL
    OPTION (MAXDOP 1);

    SELECT COUNT(*) AS MISSING_DEBT_PT
    FROM #K k
    WHERE k.IOCODE = 0
      AND NOT EXISTS (
            SELECT 1
            FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK, FORCESEEK)
            WHERE pt.INVOICEREF = k.LREF
              AND ISNULL(pt.IOCODE, 0) = 0
              AND pt.ABYS_ID IS NOT NULL
          )
    OPTION (MAXDOP 1);

    ;WITH
    mgr AS (SELECT COUNT(*) CNT, SUM(PAYABLETOTAL) AMT FROM #K),
    en  AS (
        SELECT COUNT(*) CNT, SUM(CAST(t.PAYABLETOTAL AS FLOAT)) AMT
        FROM #K k
        INNER LOOP JOIN energy.dbo.LS_005_01_INVOICE t WITH (NOLOCK, FORCESEEK) ON t.LREF = k.LREF
    ),
    pt  AS (
        SELECT COUNT(*) CNT, SUM(CAST(pt.PAYABLETOTAL AS FLOAT)) AMT
        FROM #K k
        INNER LOOP JOIN energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK, FORCESEEK)
            ON pt.INVOICEREF = k.LREF
        WHERE ISNULL(pt.IOCODE, 0) = 0 AND pt.ABYS_ID IS NOT NULL
    ),
    miss AS (
        SELECT COUNT(*) CNT
        FROM #K k
        WHERE k.IOCODE = 0
          AND NOT EXISTS (
                SELECT 1 FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK, FORCESEEK)
                WHERE pt.INVOICEREF = k.LREF AND ISNULL(pt.IOCODE, 0) = 0 AND pt.ABYS_ID IS NOT NULL
              )
    )
    SELECT
        mgr.CNT AS MGR_INV, en.CNT AS EN_INV, pt.CNT AS EN_DEBT_PT,
        ROUND(mgr.AMT, 2) AS MGR_SUM, ROUND(en.AMT, 2) AS EN_SUM, ROUND(pt.AMT, 2) AS EN_PT_SUM,
        miss.CNT AS MISSING_DEBT_PT,
        CASE WHEN mgr.CNT = en.CNT AND en.CNT = pt.CNT
              AND ABS(mgr.AMT - en.AMT) <= @Eps AND ABS(en.AMT - pt.AMT) <= @Eps
              AND miss.CNT = 0
             THEN 'PASS' ELSE 'FAIL' END AS OVERALL
    FROM mgr, en, pt, miss
    OPTION (MAXDOP 1);
END
ELSE
BEGIN
    SELECT
        'PT_ATLANDI' AS SRC,
        'INVOICEREF index yok — asagidaki CREATE calistirin' AS MSG;

    -- Sadece fatura PASS/FAIL
    ;WITH
    mgr AS (SELECT COUNT(*) CNT, SUM(PAYABLETOTAL) AMT FROM #K),
    en  AS (
        SELECT COUNT(*) CNT, SUM(CAST(t.PAYABLETOTAL AS FLOAT)) AMT
        FROM #K k
        INNER LOOP JOIN energy.dbo.LS_005_01_INVOICE t WITH (NOLOCK, FORCESEEK) ON t.LREF = k.LREF
    )
    SELECT
        mgr.CNT AS MGR_INV, en.CNT AS EN_INV,
        ROUND(mgr.AMT, 2) AS MGR_SUM, ROUND(en.AMT, 2) AS EN_SUM,
        CASE WHEN mgr.CNT = en.CNT AND ABS(mgr.AMT - en.AMT) <= @Eps
             THEN 'PASS_INV_ONLY' ELSE 'FAIL' END AS OVERALL
    FROM mgr, en
    OPTION (MAXDOP 1);
END

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121)
    + ' | bitti toplam_ms=' + CAST(DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS VARCHAR(20));

/* ---- 5) INVLINES (PK via invoice keys) ---- */
SELECT
    'IZGAZMGR_LINES' AS SRC,
    COUNT(*) AS LINE_CNT,
    ROUND(SUM(CAST(l.GRANDTOTAL AS FLOAT)), 2) AS LINE_SUM
FROM izgazMGR.dbo.LS_INVLINES l WITH (NOLOCK)
WHERE EXISTS (SELECT 1 FROM #K k WHERE k.LREF = l.INVOICEREF);

IF OBJECT_ID('energy.dbo.LS_005_01_INVLINES', 'U') IS NOT NULL
    SELECT
        'ENERGY_LINES' AS SRC,
        COUNT(*) AS LINE_CNT,
        ROUND(SUM(CAST(l.GRANDTOTAL AS FLOAT)), 2) AS LINE_SUM
    FROM energy.dbo.LS_005_01_INVLINES l WITH (NOLOCK)
    WHERE l.ABYS_ID IS NOT NULL
      AND EXISTS (SELECT 1 FROM #K k WHERE k.LREF = l.INVOICEREF);

DROP TABLE #K;
GO

/*
Oracle ile kiyas (adim3_recon_totals.sql):
  INV_CNT=259  INV_SUM=109843.94  EXPECTED_DEBT_PT=259
  LINE_CNT=1277 LINE_SUM=109843.94

INVLINES pilot:
  :r 588_INVLINES__pilot_agr.sql

Index yoksa (PT icin — bir kez):
CREATE NONCLUSTERED INDEX IX_MIG_PT_INVREF_IO
ON energy.dbo.LS_005_01_PAYTRANS (INVOICEREF, IOCODE)
INCLUDE (LREF, ABYS_ID, PAYABLETOTAL, ABYS_AGREEMENT_ID)
WHERE ABYS_ID IS NOT NULL
WITH (SORT_IN_TEMPDB = ON, MAXDOP = 4, ONLINE = OFF);
*/
