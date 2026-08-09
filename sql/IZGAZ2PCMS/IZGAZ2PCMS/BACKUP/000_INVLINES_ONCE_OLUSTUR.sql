USE izgazMGR;
GO

-- ============================================================
-- 0) ONCE DURUMU GOR: LREF'te zaten index var mi?
-- ============================================================
SELECT
    i.index_id, i.name, i.type_desc, i.is_disabled,
    c.name AS col_name, ic.key_ordinal, ic.is_included_column
FROM sys.indexes i
LEFT JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
LEFT JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID('dbo.LS_INVLINES')
ORDER BY i.index_id, ic.key_ordinal;

-- Tablo boyutu / heap mi? (index build suresi ve disk tahmini icin)
SELECT
    i.index_id, i.type_desc,
    SUM(p.rows)                                   AS row_count,
    CAST(SUM(a.total_pages) * 8 / 1024.0 / 1024 AS DECIMAL(10,2)) AS size_gb
FROM sys.indexes i
JOIN sys.partitions p ON p.object_id = i.object_id AND p.index_id = i.index_id
JOIN sys.allocation_units a ON a.container_id = p.partition_id
WHERE i.object_id = OBJECT_ID('dbo.LS_INVLINES')
GROUP BY i.index_id, i.type_desc;
GO

-- ============================================================
-- 1) INDEX (idempotent)
-- ============================================================
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE i.object_id = OBJECT_ID('dbo.LS_INVLINES')
      AND i.type > 0
      AND ic.key_ordinal = 1
      AND ic.is_included_column = 0
      AND c.name = 'LREF'
)
BEGIN
    RAISERROR('IX_MIG_LSINVLINES_LREF olusturuluyor...', 0, 1) WITH NOWAIT;

    CREATE NONCLUSTERED INDEX IX_MIG_LSINVLINES_LREF
    ON dbo.LS_INVLINES (LREF)
    WITH (
        MAXDOP           = 8,
        ONLINE           = ON,
        SORT_IN_TEMPDB   = ON,
        DATA_COMPRESSION = PAGE
    );

    RAISERROR('IX_MIG_LSINVLINES_LREF tamam.', 0, 1) WITH NOWAIT;
END
ELSE
    RAISERROR('LREF onde index zaten var, atlaniyor.', 0, 1) WITH NOWAIT;
GO