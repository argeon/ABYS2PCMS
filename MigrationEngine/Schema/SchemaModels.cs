namespace MigrationEngine.Schema;

public class TableSchema
{
    public string TableName { get; set; } = string.Empty;
    public List<ColumnSchema> Columns { get; set; } = new();
    public List<ConstraintSchema> Constraints { get; set; } = new();
    public List<IndexSchema> Indexes { get; set; } = new();
}

public class ColumnSchema
{
    public string ColumnName { get; set; } = string.Empty;
    public string DataType { get; set; } = string.Empty;
    public int? DataLength { get; set; }
    public int? DataPrecision { get; set; }
    public int? DataScale { get; set; }
    public bool Nullable { get; set; }
    public string? DefaultValue { get; set; }
    public int ColumnId { get; set; }

    /// <summary>Oracle MDSYS.SDO_GEOMETRY column — extracted as WKT and converted post-load.</summary>
    public bool IsSpatial { get; set; }

    /// <summary>EPSG SRID from ALL_SDO_GEOM_METADATA (or config override).</summary>
    public int? Srid { get; set; }

    /// <summary>MSSQL target EPSG (e.g. 4326 WGS84 geography).</summary>
    public int? SpatialTargetSrid { get; set; }

    /// <summary>Final SQL Server spatial type: geometry or geography.</summary>
    public string? SpatialTargetType { get; set; }

    /// <summary>True when column is config-driven (not on Oracle base table).</summary>
    public bool IsExtraColumn { get; set; }

    /// <summary>When set, Oracle SELECT uses this expression instead of the column name.</summary>
    public string? OracleSelectExpression { get; set; }

    /// <summary>Explicit MSSQL type for extra columns (e.g. NVARCHAR(250)).</summary>
    public string? MssqlTypeOverride { get; set; }

    /// <summary>Filled after bulk load (analytic / join expressions).</summary>
    public bool FillAfterLoad { get; set; }
}

public class ConstraintSchema
{
    public string ConstraintName { get; set; } = string.Empty;
    public string ConstraintType { get; set; } = string.Empty;
    public List<string> Columns { get; set; } = new();
    public string? ReferenceTableName { get; set; }
    public List<string>? ReferenceColumns { get; set; }
    public string? DeleteRule { get; set; }
}

public class IndexSchema
{
    public string IndexName { get; set; } = string.Empty;
    public bool IsUnique { get; set; }
    public List<IndexColumn> Columns { get; set; } = new();
}

public class IndexColumn
{
    public string ColumnName { get; set; } = string.Empty;
    public int ColumnPosition { get; set; }
    public string? DescendFlag { get; set; }
}
