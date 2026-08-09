/* ============================================================
   SCRIPT_ID : INVLINES_CHECK
   SCRIPT_NO : 583
   FILE      : 583_INVLINES__check.sql
   VERSION   : 2
   ============================================================ */
-- Manuel kontrol sorgulari (deploy disi)
USE energy;
GO

-- Kaynak vs ABYS hedef sayim
SELECT
    (SELECT SUM(p.rows)
     FROM izgazMGR.sys.partitions p
     INNER JOIN izgazMGR.sys.tables t ON t.object_id = p.object_id
     INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
     WHERE s.name = 'dbo' AND t.name = 'LS_INVLINES' AND p.index_id IN (0, 1)
    ) AS SRC_APPROX,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_INVLINES WHERE ABYS_ID IS NOT NULL) AS TGT_ABYS,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_INVLINES WHERE ABYS_ID IS NULL) AS TGT_NATIVE,
    (SELECT COUNT_BIG(*)
     FROM izgazMGR.dbo.LS_INVLINES s WITH (NOLOCK)
     WHERE s.LREF IS NULL OR s.LREF < 1 OR s.LREF > 2147483647
    ) AS SRC_LREF_OUT_OF_INT;

-- Eksik kaynak (henuz gelmemis) — buyuk tabloda pahali; ornek TOP
SELECT COUNT_BIG(*) AS MISSING_SAMPLE_HINT
FROM (
    SELECT TOP (100000) s.LREF, s.ABYS_INCOME_ROW_ID
    FROM izgazMGR.dbo.LS_INVLINES s WITH (NOLOCK)
    WHERE s.LREF BETWEEN 1 AND 2147483647
    ORDER BY s.LREF
) s
WHERE NOT EXISTS (
    SELECT 1 FROM energy.dbo.LS_005_01_INVLINES t
    WHERE t.LREF = CAST(s.LREF AS INT)
);

-- Sabit / turetilmis mapping ornek
SELECT TOP 20
    t.LREF, t.CURID, t.CURRATE, t.TLTOTAL, t.CURTOTAL,
    t.UNITPRICE, t.ABYS_UNIT_PRICE, t.AMOUNT, t.ABYS_QUANTITY,
    CASE WHEN t.CURID = 160 AND t.CURRATE = 1
              AND (t.CURTOTAL = t.TLTOTAL OR (t.CURTOTAL IS NULL AND t.TLTOTAL IS NULL))
         THEN 1 ELSE 0 END AS CUR_OK,
    CASE WHEN (t.UNITPRICE = CAST(t.ABYS_UNIT_PRICE AS FLOAT)
               OR (t.UNITPRICE IS NULL AND t.ABYS_UNIT_PRICE IS NULL))
         THEN 1 ELSE 0 END AS UNITPRICE_OK,
    CASE WHEN (t.AMOUNT = CAST(t.ABYS_QUANTITY AS FLOAT)
               OR (t.AMOUNT IS NULL AND t.ABYS_QUANTITY IS NULL))
         THEN 1 ELSE 0 END AS AMOUNT_OK
FROM energy.dbo.LS_005_01_INVLINES t
WHERE t.ABYS_ID IS NOT NULL
ORDER BY t.LREF;

-- Index durumu (post sonrasi)
SELECT i.name, i.type_desc, i.is_unique, i.is_disabled, i.filter_definition
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVLINES')
ORDER BY i.index_id;

-- Ornek satir
SELECT TOP 20
    t.LREF, t.ABYS_ID, t.ABYS_INCOME_ROW_ID, t.ABYS_INCOME_ID, t.ABYS_ACTION_ID,
    t.INVOICEREF, t.CLIENTREF, t.DATE_, t.FIRST_DATE, t.LAST_DATE, t.[DAY],
    t.LINENR, t.TLTOTAL, t.AMOUNT, t.UNITPRICE, t.CURID, t.CURRATE, t.CURTOTAL,
    t.TRANSTYPE, t.CANCELED, t.ABYS_INCOME_CODE, t.ABYS_STATUS
FROM energy.dbo.LS_005_01_INVLINES t
WHERE t.ABYS_ID IS NOT NULL
ORDER BY t.LREF;
GO
