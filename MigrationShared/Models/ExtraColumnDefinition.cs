namespace MigrationShared.Models;

/// <summary>
/// Extra target column not present on the Oracle base table (computed expression / joins).
/// </summary>
public class ExtraColumnDefinition
{
    /// <summary>Target / source table name (e.g. CS_READING_PLAN).</summary>
    public string TableName { get; set; } = string.Empty;

    public string ColumnName { get; set; } = string.Empty;

    /// <summary>MSSQL type, e.g. NVARCHAR(250).</summary>
    public string MssqlType { get; set; } = "NVARCHAR(250)";

    public bool Nullable { get; set; } = true;

    /// <summary>
    /// When true, column is created empty during bulk load and filled after all partitions complete
    /// (required for analytic functions such as ROW_NUMBER that need the full table).
    /// </summary>
    public bool FillAfterLoad { get; set; } = true;

    /// <summary>Oracle expression for the value (no AS alias).</summary>
    public string OracleSelectExpression { get; set; } = string.Empty;

    /// <summary>JOIN clauses; main table alias is always <c>t</c>.</summary>
    public List<string> OracleFromJoins { get; set; } = new();

    /// <summary>Optional WHERE clause (without WHERE keyword).</summary>
    public string? OracleWhere { get; set; }

    /// <summary>Key column used to UPDATE MSSQL rows (default ID).</summary>
    public string KeyColumn { get; set; } = "ID";
}
