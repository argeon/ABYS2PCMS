/* ============================================================
   SCRIPT_ID : INVOICE_CHECK
   SCRIPT_NO : 573
   FILE      : 573_INVOICE__check.sql
   VERSION   : 3
   ============================================================ */
-- Manuel kontrol sorgulari (deploy disi)
-- LREF = ABYS_ACTION_ID (v3)
USE energy;
GO

-- Kaynak vs ABYS hedef sayim
SELECT
    (SELECT SUM(p.rows)
     FROM izgazMGR.sys.partitions p
     INNER JOIN izgazMGR.sys.tables t ON t.object_id = p.object_id
     INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
     WHERE s.name = 'dbo' AND t.name = 'LS_INVOICE' AND p.index_id IN (0, 1)
    ) AS SRC_APPROX,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_INVOICE WHERE ABYS_ID IS NOT NULL) AS TGT_ABYS,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_INVOICE WHERE ABYS_ID IS NULL) AS TGT_NATIVE,
    (SELECT COUNT_BIG(*)
     FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
     WHERE s.ABYS_ACTION_ID IS NULL OR s.ABYS_ACTION_ID < 1 OR s.ABYS_ACTION_ID > 2147483647
    ) AS SRC_ABYS_ACTION_ID_OUT_OF_INT;

-- Duplicate ABYS_ACTION_ID (PK riski)
SELECT TOP 20 ABYS_ACTION_ID, COUNT(*) AS CNT
FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
GROUP BY ABYS_ACTION_ID
HAVING COUNT(*) > 1
ORDER BY CNT DESC;

-- Eksik kaynak ornek (ilk 100K ABYS_ACTION_ID)
SELECT COUNT_BIG(*) AS MISSING_SAMPLE_HINT
FROM (
    SELECT TOP (100000) s.ABYS_ACTION_ID
    FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
    WHERE s.ABYS_ACTION_ID BETWEEN 1 AND 2147483647
    ORDER BY s.ABYS_ACTION_ID
) s
WHERE NOT EXISTS (
    SELECT 1 FROM energy.dbo.LS_005_01_INVOICE t
    WHERE t.LREF = CAST(s.ABYS_ACTION_ID AS INT)
       OR t.ABYS_ID = s.ABYS_ACTION_ID
);

-- LREF = ABYS_ID dogrulama
SELECT COUNT_BIG(*) AS LREF_NE_ABYS_ID
FROM energy.dbo.LS_005_01_INVOICE
WHERE ABYS_ID IS NOT NULL
  AND LREF <> ABYS_ID;

-- USERID offset dogrulama (+10000)
SELECT TOP 20
    t.LREF, t.ABYS_ID, t.OLREF, t.ADDUSER, t.ABYS_ADDUSER,
    t.UPDUSER, t.ABYS_UPDUSER,
    CASE WHEN t.ABYS_ADDUSER IS NOT NULL AND t.ADDUSER = t.ABYS_ADDUSER + 10000 THEN 1 ELSE 0 END AS ADDUSER_OK,
    CASE WHEN t.ABYS_UPDUSER IS NOT NULL AND t.UPDUSER = t.ABYS_UPDUSER + 10000 THEN 1 ELSE 0 END AS UPDUSER_OK
FROM energy.dbo.LS_005_01_INVOICE t
WHERE t.ABYS_ID IS NOT NULL
ORDER BY t.LREF;

-- Index durumu (post sonrasi)
SELECT i.name, i.type_desc, i.is_unique, i.is_disabled, i.filter_definition
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
ORDER BY i.index_id;

-- Ornek satir
SELECT TOP 20
    t.LREF, t.ABYS_ID, t.OLREF, t.ABYS_ACCOUNT_ID, t.IOCODE, t.FICHENO,
    t.DATE_, t.DUEDATE, t.CLIENTREF, t.TLTOTAL, t.GRANDTOTAL, t.PAYABLETOTAL,
    t.CANCELED, t.CLOSED, t.ADDUSER, t.ABYS_ADDUSER
FROM energy.dbo.LS_005_01_INVOICE t
WHERE t.ABYS_ID IS NOT NULL
ORDER BY t.LREF;
GO
