use energy
 


;WITH TabloListesi AS (
    SELECT t.object_id, t.name AS TabloAdi, s.name AS SemaAdi
    FROM sys.tables t
    INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE t.name IN ( 
    'LS_AGREEMENT'

    )
),
PKKolon AS (
    SELECT ic.object_id, ic.column_id, kc.name AS PKAdi
    FROM sys.key_constraints kc
    INNER JOIN sys.index_columns ic
        ON ic.object_id = kc.parent_object_id
       AND ic.index_id  = kc.unique_index_id
    WHERE kc.type = 'PK'
),
FKKolon AS (
    SELECT
        fkc.parent_object_id      AS object_id,
        fkc.parent_column_id      AS column_id,
        fk.name                   AS FKAdi,
        OBJECT_SCHEMA_NAME(fkc.referenced_object_id) + '.' +
        OBJECT_NAME(fkc.referenced_object_id) + '(' +
        COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id) + ')' AS ReferansHedef
    FROM sys.foreign_key_columns fkc
    INNER JOIN sys.foreign_keys fk ON fk.object_id = fkc.constraint_object_id
)
SELECT
    DB_NAME()                                   AS [DB],
    tl.SemaAdi + '.' + tl.TabloAdi              AS [Tablo],
    c.column_id                                 AS [Sira],
    c.name                                      AS [Kolon],
    -- Tip: uzunluk/precision dahil okunur format
    ty.name +
        CASE
            WHEN ty.name IN ('varchar','char','varbinary')
                THEN '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length AS varchar(10)) END + ')'
            WHEN ty.name IN ('nvarchar','nchar')
                THEN '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length/2 AS varchar(10)) END + ')'
            WHEN ty.name IN ('decimal','numeric')
                THEN '(' + CAST(c.precision AS varchar(5)) + ',' + CAST(c.scale AS varchar(5)) + ')'
            WHEN ty.name IN ('datetime2','time','datetimeoffset')
                THEN '(' + CAST(c.scale AS varchar(5)) + ')'
            ELSE ''
        END                                     AS [Tip],
    CASE WHEN c.is_nullable = 1 THEN 'NULL' ELSE 'NOT NULL' END AS [Nullable],
    CASE WHEN c.is_identity = 1 THEN 'IDENTITY' ELSE '' END     AS [Identity],
    ISNULL(pk.PKAdi, '')                        AS [PK],
    ISNULL(fk.FKAdi, '')                        AS [FK],
    ISNULL(fk.ReferansHedef, '')                AS [FK_Referans],
    ISNULL(dc.name + ' = ' + dc.definition, '') AS [Default_Constraint],
    ISNULL(cc.CheckList, '')                    AS [Check_Constraint]
FROM TabloListesi tl
INNER JOIN sys.columns c  ON c.object_id = tl.object_id
INNER JOIN sys.types  ty  ON ty.user_type_id = c.user_type_id
LEFT JOIN PKKolon pk      ON pk.object_id = c.object_id AND pk.column_id = c.column_id
LEFT JOIN FKKolon fk      ON fk.object_id = c.object_id AND fk.column_id = c.column_id
LEFT JOIN sys.default_constraints dc
       ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
OUTER APPLY (
    -- Aynı kolona birden fazla CHECK bağlıysa birleştir
    SELECT STRING_AGG(chk.name + ': ' + chk.definition, ' | ')
    FROM sys.check_constraints chk
    WHERE chk.parent_object_id = c.object_id
      AND chk.parent_column_id = c.column_id
) cc(CheckList)
ORDER BY tl.TabloAdi, c.column_id;



Use izgazMGR

;WITH TabloListesi AS (
    SELECT t.object_id, t.name AS TabloAdi, s.name AS SemaAdi
    FROM sys.tables t
    INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE t.name IN (
        'LS_AGREEMENT' 
    )
),
PKKolon AS (
    SELECT ic.object_id, ic.column_id, kc.name AS PKAdi
    FROM sys.key_constraints kc
    INNER JOIN sys.index_columns ic
        ON ic.object_id = kc.parent_object_id
       AND ic.index_id  = kc.unique_index_id
    WHERE kc.type = 'PK'
),
FKKolon AS (
    SELECT
        fkc.parent_object_id      AS object_id,
        fkc.parent_column_id      AS column_id,
        fk.name                   AS FKAdi,
        OBJECT_SCHEMA_NAME(fkc.referenced_object_id) + '.' +
        OBJECT_NAME(fkc.referenced_object_id) + '(' +
        COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id) + ')' AS ReferansHedef
    FROM sys.foreign_key_columns fkc
    INNER JOIN sys.foreign_keys fk ON fk.object_id = fkc.constraint_object_id
)
SELECT
    DB_NAME()                                   AS [DB],
    tl.SemaAdi + '.' + tl.TabloAdi              AS [Tablo],
    c.column_id                                 AS [Sira],
    c.name                                      AS [Kolon],
    -- Tip: uzunluk/precision dahil okunur format
    ty.name +
        CASE
            WHEN ty.name IN ('varchar','char','varbinary')
                THEN '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length AS varchar(10)) END + ')'
            WHEN ty.name IN ('nvarchar','nchar')
                THEN '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length/2 AS varchar(10)) END + ')'
            WHEN ty.name IN ('decimal','numeric')
                THEN '(' + CAST(c.precision AS varchar(5)) + ',' + CAST(c.scale AS varchar(5)) + ')'
            WHEN ty.name IN ('datetime2','time','datetimeoffset')
                THEN '(' + CAST(c.scale AS varchar(5)) + ')'
            ELSE ''
        END                                     AS [Tip],
    CASE WHEN c.is_nullable = 1 THEN 'NULL' ELSE 'NOT NULL' END AS [Nullable],
    CASE WHEN c.is_identity = 1 THEN 'IDENTITY' ELSE '' END     AS [Identity],
    ISNULL(pk.PKAdi, '')                        AS [PK],
    ISNULL(fk.FKAdi, '')                        AS [FK],
    ISNULL(fk.ReferansHedef, '')                AS [FK_Referans],
    ISNULL(dc.name + ' = ' + dc.definition, '') AS [Default_Constraint],
    ISNULL(cc.CheckList, '')                    AS [Check_Constraint]
FROM TabloListesi tl
INNER JOIN sys.columns c  ON c.object_id = tl.object_id
INNER JOIN sys.types  ty  ON ty.user_type_id = c.user_type_id
LEFT JOIN PKKolon pk      ON pk.object_id = c.object_id AND pk.column_id = c.column_id
LEFT JOIN FKKolon fk      ON fk.object_id = c.object_id AND fk.column_id = c.column_id
LEFT JOIN sys.default_constraints dc
       ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
OUTER APPLY (
    -- Aynı kolona birden fazla CHECK bağlıysa birleştir
    SELECT STRING_AGG(chk.name + ': ' + chk.definition, ' | ')
    FROM sys.check_constraints chk
    WHERE chk.parent_object_id = c.object_id
      AND chk.parent_column_id = c.column_id
) cc(CheckList)
ORDER BY tl.TabloAdi, c.column_id;

