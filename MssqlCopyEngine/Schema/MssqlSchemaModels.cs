namespace MssqlCopyEngine.Schema;

public enum MssqlObjectKind
{
    Table,
    View
}

public sealed class MssqlTableSchema
{
    public string SchemaName { get; set; } = "dbo";
    public string TableName { get; set; } = string.Empty;
    public MssqlObjectKind ObjectKind { get; set; } = MssqlObjectKind.Table;

    /// <summary>For views: underlying user tables discovered via dependency analysis.</summary>
    public List<string> BaseTables { get; set; } = new();

    /// <summary>
    /// Object to SELECT FROM on source (same as TableName for tables/views).
    /// Destination CREATE/INSERT always uses TableName (view materializes as table).
    /// </summary>
    public string SourceReadName => TableName;

    public bool IsView => ObjectKind == MssqlObjectKind.View;

    public List<MssqlColumnSchema> Columns { get; set; } = new();
    public List<string> PrimaryKeyColumns { get; set; } = new();
    public List<MssqlIndexSchema> Indexes { get; set; } = new();
    public List<MssqlForeignKeySchema> ForeignKeys { get; set; } = new();
    public List<MssqlCheckConstraintSchema> CheckConstraints { get; set; } = new();
    public long EstimatedRows { get; set; }
}

public sealed class MssqlColumnSchema
{
    public string ColumnName { get; set; } = string.Empty;
    public string DataType { get; set; } = string.Empty;
    public int? MaxLength { get; set; }
    public byte? Precision { get; set; }
    public int? Scale { get; set; }
    public bool IsNullable { get; set; }
    public bool IsIdentity { get; set; }
    public int? IdentitySeed { get; set; }
    public int? IdentityIncrement { get; set; }
    public string? DefaultDefinition { get; set; }
    public string? CollationName { get; set; }
    public int Ordinal { get; set; }

    public bool IsCharacterType =>
        DataType.Equals("varchar", StringComparison.OrdinalIgnoreCase)
        || DataType.Equals("nvarchar", StringComparison.OrdinalIgnoreCase)
        || DataType.Equals("char", StringComparison.OrdinalIgnoreCase)
        || DataType.Equals("nchar", StringComparison.OrdinalIgnoreCase)
        || DataType.Equals("text", StringComparison.OrdinalIgnoreCase)
        || DataType.Equals("ntext", StringComparison.OrdinalIgnoreCase)
        || DataType.Equals("sysname", StringComparison.OrdinalIgnoreCase);
}

public sealed class MssqlIndexSchema
{
    public string IndexName { get; set; } = string.Empty;
    public bool IsUnique { get; set; }
    public bool IsPrimaryKey { get; set; }
    public List<string> Columns { get; set; } = new();
}

public sealed class MssqlForeignKeySchema
{
    public string ConstraintName { get; set; } = string.Empty;
    public List<string> Columns { get; set; } = new();
    public string ReferencedSchema { get; set; } = "dbo";
    public string ReferencedTable { get; set; } = string.Empty;
    public List<string> ReferencedColumns { get; set; } = new();
}

public sealed class MssqlCheckConstraintSchema
{
    public string ConstraintName { get; set; } = string.Empty;
    public string Definition { get; set; } = string.Empty;
}
