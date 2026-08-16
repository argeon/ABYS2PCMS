/* ============================================================
   FILE : prodREADY_ENERGY3007/00a_dump_transfer_audit.sql
   FAZ  : Dump sonrası / sırasında — aktarım + IX sağlık taraması
   Ne zaman: izgazMGR dump bitince veya kısmi dump sırasında
   Çıktı: row/IX durumu, soft/hard sapmalar, beklenen IX MISSING listesi
   Not: CREATE INDEX yapmaz — IX için 00_ix_online_safe.sql / ../00_pre_indexes.sql
   ============================================================ */
USE izgazMGR;
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + ' | 00a DUMP TRANSFER AUDIT START';

/* ---- Aktif dump / IX işleri ---- */
SELECT
    r.session_id,
    r.status,
    r.command,
    r.wait_type,
    r.percent_complete,
    r.estimated_completion_time / 60000 AS eta_min,
    SUBSTRING(COALESCE(qt.text, N''), 1, 160) AS sql_text
FROM sys.dm_exec_requests r
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) qt
WHERE r.session_id <> @@SPID
  AND DB_NAME(r.database_id) = N'izgazMGR'
  AND (
        r.command LIKE N'%INSERT%'
     OR r.command LIKE N'%BULK%'
     OR r.command LIKE N'%CREATE INDEX%'
     OR r.command LIKE N'%ALTER INDEX%'
      );

DECLARE @Need TABLE (
    TNAME SYSNAME PRIMARY KEY,
    ROLE  VARCHAR(20) NOT NULL,   -- TAH | EKS | O50 | DIAG
    MIN_ROWS BIGINT NULL          -- soft expect (NULL=sadece varlık)
);
INSERT INTO @Need (TNAME, ROLE, MIN_ROWS) VALUES
 (N'LS_INVOICE',            N'TAH',  1),
 (N'LS_INVLINES',           N'TAH',  1),
 (N'LS_DEBT_PAYTRANS',      N'TAH',  1),
 (N'LS_OV_PAY_ALLOC',       N'TAH',  1),
 (N'LS_OV_PAY_PT',          N'TAH',  1),
 (N'LS_OV_TAH_INVOICE',     N'TAH',  1),
 (N'LS_OV_DEBT_PAID_UPD',   N'TAH',  1),
 (N'LS_OV_ID_MAP',          N'TAH',  1),
 (N'LS_OV_CANCEL_PAY',      N'TAH',  NULL),
 (N'LS_OV_CANCEL_REV',      N'TAH',  NULL),
 (N'LS_OV_MAHSUP_SRC',      N'TAH',  NULL),
 (N'LS_OV_MAHSUP_CLOSED',   N'TAH',  NULL),
 (N'LS_OV_INV_PAY_GAP',     N'DIAG', NULL),
 (N'LS_OV_IADE_INVOICE',    N'EKS',  NULL),
 (N'LS_OV_IADE_INVLINES',   N'EKS',  NULL),
 (N'LS_OV_IADE_PAYTRANS',   N'EKS',  NULL),
 (N'LS_OV_KISMI_INVLINES',  N'EKS',  NULL),
 (N'LS_OV_KISMI_HDR',       N'EKS',  NULL),
 (N'LS_OV_KISMI_PAYTRANS',  N'EKS',  NULL),
 (N'LS_OV_MAIN_UPD',        N'EKS',  NULL),
 (N'LS_PAYMENT',            N'O50',  NULL),
 (N'LS_TAKSIT',             N'O50',  NULL),
 (N'LS_INSTALLMENT_PLAN_PAY', N'O50', NULL),
 (N'LS_AFL_OPEN_DEBT',      N'O50',  NULL),
 (N'LS_STG_INV_PAY_CLOSE',  N'O50',  NULL);

PRINT '=== TABLE STATUS ===';
SELECT
    n.TNAME,
    n.ROLE,
    CASE WHEN OBJECT_ID(N'dbo.' + n.TNAME, N'U') IS NULL THEN N'MISSING'
         ELSE N'OK' END AS exists_flag,
    CASE WHEN OBJECT_ID(N'dbo.' + n.TNAME, N'U') IS NULL THEN NULL
         ELSE (SELECT SUM(p.rows)
               FROM sys.partitions p
               WHERE p.object_id = OBJECT_ID(N'dbo.' + n.TNAME)
                 AND p.index_id IN (0, 1)) END AS approx_rows,
    CASE WHEN OBJECT_ID(N'dbo.' + n.TNAME, N'U') IS NULL THEN NULL
         ELSE (SELECT COUNT(*) FROM sys.indexes i
               WHERE i.object_id = OBJECT_ID(N'dbo.' + n.TNAME) AND i.index_id > 0) END AS ix_count,
    CASE
        WHEN OBJECT_ID(N'dbo.' + n.TNAME, N'U') IS NULL THEN N'HARD_MISSING'
        WHEN n.MIN_ROWS IS NOT NULL
             AND (SELECT SUM(p.rows) FROM sys.partitions p
                  WHERE p.object_id = OBJECT_ID(N'dbo.' + n.TNAME) AND p.index_id IN (0,1)) < n.MIN_ROWS
            THEN N'HARD_EMPTY'
        WHEN EXISTS (
                SELECT 1 FROM sys.dm_exec_requests r
                OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) qt
                WHERE DB_NAME(r.database_id) = N'izgazMGR'
                  AND qt.text LIKE N'%' + n.TNAME + N'%'
                  AND (r.command LIKE N'%BULK%' OR r.command LIKE N'%INSERT%')
             ) THEN N'LOADING'
        WHEN (SELECT COUNT(*) FROM sys.indexes i
              WHERE i.object_id = OBJECT_ID(N'dbo.' + n.TNAME) AND i.index_id > 0) = 0
            THEN N'HEAP_NO_IX'
        ELSE N'OK'
    END AS verdict
FROM @Need n
ORDER BY
    CASE verdict
        WHEN N'HARD_MISSING' THEN 1
        WHEN N'HARD_EMPTY' THEN 2
        WHEN N'LOADING' THEN 3
        WHEN N'HEAP_NO_IX' THEN 4
        ELSE 5
    END,
    n.ROLE, n.TNAME;

/* ---- Tahsilat tutarlılık (tablo doluysa) ---- */
PRINT '=== TAH QUALITY ===';
IF OBJECT_ID(N'dbo.LS_OV_PAY_PT', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.LS_OV_PAY_ALLOC', N'U') IS NOT NULL
BEGIN
    SELECT N'PAY_PT_vs_ALLOC' AS chk,
           (SELECT COUNT_BIG(*) FROM dbo.LS_OV_PAY_PT WITH (NOLOCK)) AS pay_pt,
           (SELECT COUNT_BIG(*) FROM dbo.LS_OV_PAY_ALLOC WITH (NOLOCK)) AS alloc,
           CASE WHEN (SELECT COUNT_BIG(*) FROM dbo.LS_OV_PAY_PT WITH (NOLOCK))
                   = (SELECT COUNT_BIG(*) FROM dbo.LS_OV_PAY_ALLOC WITH (NOLOCK))
                THEN N'OK' ELSE N'UNEXPECTED_MISMATCH' END AS verdict;

    SELECT N'PAY_PAID_GAP' AS chk, COUNT_BIG(*) AS n,
           CASE WHEN COUNT_BIG(*) = 0 THEN N'OK' ELSE N'HARD_FAIL' END AS verdict
    FROM dbo.LS_OV_PAY_PT WITH (NOLOCK)
    WHERE ISNULL(OV_KIND, N'PAY') = N'PAY' AND ISNULL(CANCELED, 0) = 0
      AND ISNULL(PAID, 0) + 0.01 < ISNULL(PAYABLETOTAL, 0)
      AND ISNULL(PAYABLETOTAL, 0) > 0.01;

    SELECT N'PAY_NO_XREF' AS chk, COUNT_BIG(*) AS n,
           CASE WHEN COUNT_BIG(*) = 0 THEN N'OK' ELSE N'HARD_FAIL' END AS verdict
    FROM dbo.LS_OV_PAY_PT WITH (NOLOCK)
    WHERE ISNULL(OV_KIND, N'PAY') = N'PAY' AND ISNULL(CANCELED, 0) = 0
      AND CROSSREF_MAIN_LREF IS NULL;
END

IF OBJECT_ID(N'dbo.LS_OV_ID_MAP', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.LS_OV_TAH_INVOICE', N'U') IS NOT NULL
BEGIN
    DECLARE @tah BIGINT, @mapTah BIGINT;
    SELECT @tah = COUNT_BIG(*) FROM dbo.LS_OV_TAH_INVOICE WITH (NOLOCK);
    SELECT @mapTah = COUNT_BIG(*) FROM dbo.LS_OV_ID_MAP WITH (NOLOCK) WHERE OV_KIND = N'TAH_INV';
    SELECT N'TAH_vs_ID_MAP' AS chk, @tah AS tah_rows, @mapTah AS map_tah_rows,
           CASE
               WHEN EXISTS (
                    SELECT 1 FROM sys.dm_exec_requests r
                    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) qt
                    WHERE DB_NAME(r.database_id) = N'izgazMGR'
                      AND qt.text LIKE N'%LS_OV_TAH_INVOICE%'
                      AND r.command LIKE N'%BULK%'
               ) THEN N'LOADING_WAIT'
               WHEN @tah = @mapTah THEN N'OK'
               WHEN @tah < @mapTah THEN N'UNEXPECTED_TAH_LT_MAP'
               ELSE N'UNEXPECTED_TAH_GT_MAP'
           END AS verdict;

    SELECT N'MAP_KIND' AS chk, OV_KIND, COUNT_BIG(*) AS n
    FROM dbo.LS_OV_ID_MAP WITH (NOLOCK)
    GROUP BY OV_KIND
    ORDER BY n DESC;
END

IF OBJECT_ID(N'dbo.LS_OV_ID_MAP', N'U') IS NOT NULL
BEGIN
    SELECT c.name AS col, ty.name AS typ,
           CASE WHEN ty.name IN (N'nvarchar', N'nchar') THEN N'NEED_00b' ELSE N'OK_VARCHAR' END AS verdict
    FROM sys.columns c
    JOIN sys.types ty ON ty.user_type_id = c.user_type_id
    WHERE c.object_id = OBJECT_ID(N'dbo.LS_OV_ID_MAP')
      AND c.name IN (N'SRC_KEY', N'OV_KIND', N'PARENT_SRC_KEY');
END

/* ---- Beklenen IX (00_pre_indexes çekirdek) ---- */
PRINT '=== EXPECTED INDEX STATUS ===';
SELECT v.tbl, v.ix_name,
    CASE
        WHEN OBJECT_ID(N'dbo.' + v.tbl, N'U') IS NULL THEN N'NO_TABLE'
        WHEN EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID(N'dbo.' + v.tbl) AND i.name = v.ix_name
        ) THEN N'PRESENT'
        ELSE N'MISSING'
    END AS status
FROM (VALUES
 (N'LS_INVOICE', N'IX_MIG_LSINV_AGR_ACTION'),
 (N'LS_INVOICE', N'IX_MIG_LSINV_ACTION'),
 (N'LS_INVOICE', N'IX_MIG_LSINV_LREF'),
 (N'LS_INVOICE', N'IX_MIG_LSINV_ACCOUNT'),
 (N'LS_INVLINES', N'IX_MIG_LSIL_AGR'),
 (N'LS_INVLINES', N'IX_MIG_LSIL_INVREF'),
 (N'LS_INVLINES', N'IX_MIG_LSINVLINES_LREF'),
 (N'LS_DEBT_PAYTRANS', N'IX_MIG_DEBT_PT_ABYS'),
 (N'LS_DEBT_PAYTRANS', N'IX_MIG_DEBT_PT_INVREF'),
 (N'LS_OV_ID_MAP', N'UX_LS_OV_ID_MAP_SRC'),
 (N'LS_OV_ID_MAP', N'IX_OV_ID_MAP_KIND'),
 (N'LS_OV_ID_MAP', N'IX_OV_ID_MAP_AGR'),
 (N'LS_OV_PAY_PT', N'IX_MIG_OV_PAY_PT_PAY'),
 (N'LS_OV_PAY_PT', N'IX_MIG_OV_PAY_PT_MAIN'),
 (N'LS_OV_PAY_PT', N'IX_MIG_OV_PAY_PT_ABYS_ID'),
 (N'LS_OV_PAY_ALLOC', N'IX_MIG_OV_PAY_ALLOC_PM'),
 (N'LS_OV_DEBT_PAID_UPD', N'IX_MIG_OV_DEBT_PAID_MAIN'),
 (N'LS_OV_TAH_INVOICE', N'IX_MIG_LS_OV_TAH_INVOICE_LREF'),
 (N'LS_OV_TAH_INVOICE', N'IX_MIG_LS_OV_TAH_INVOICE_AGR')
) v(tbl, ix_name)
ORDER BY status, tbl, ix_name;

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + ' | 00a DUMP TRANSFER AUDIT END';
PRINT 'LOADING tabloda IX oluşturma — 00_ix_online_safe.sql kullan (BULK bitince tekrar).';
GO
