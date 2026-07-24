namespace MigrationEngine.Schema;

public static class SpatialColumnHelper
{
    public const string WktStagingSuffix = "__wkt";

    public static bool IsSpatialColumn(ColumnSchema column) =>
        column.IsSpatial
        || string.Equals(column.DataType, "SDO_GEOMETRY", StringComparison.OrdinalIgnoreCase);

    /// <summary>NVARCHAR(MAX) column that receives Oracle WKT during bulk load.</summary>
    public static string GetWktStagingColumnName(string columnName) =>
        $"{columnName}{WktStagingSuffix}";

    public static string GetWktStagingColumnName(ColumnSchema column) =>
        GetWktStagingColumnName(column.ColumnName);

    public static bool IsStringSqlType(string? typeName) =>
        string.Equals(typeName, "nvarchar", StringComparison.OrdinalIgnoreCase)
        || string.Equals(typeName, "varchar", StringComparison.OrdinalIgnoreCase);

    public static void MarkSpatialColumns(TableSchema table)
    {
        foreach (var column in table.Columns.Where(IsSpatialColumn))
        {
            column.IsSpatial = true;
            column.SpatialTargetType ??= "geometry";
        }
    }

    public static IReadOnlyList<ColumnSchema> GetSpatialColumns(IEnumerable<ColumnSchema> columns) =>
        columns.Where(IsSpatialColumn).ToList();
}
