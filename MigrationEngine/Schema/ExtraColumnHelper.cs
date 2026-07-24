using MigrationShared.Models;

namespace MigrationEngine.Schema;

public static class ExtraColumnHelper
{
    public static void ApplyExtraColumns(IEnumerable<TableSchema> tables, MigrationConfig config)
    {
        if (config.ExtraColumns.Count == 0)
            return;

        foreach (var table in tables)
        {
            var extras = config.ExtraColumns
                .Where(e => e.TableName.Equals(table.TableName, StringComparison.OrdinalIgnoreCase))
                .ToList();
            if (extras.Count == 0)
                continue;

            var maxId = table.Columns.Count == 0 ? 0 : table.Columns.Max(c => c.ColumnId);
            foreach (var extra in extras)
            {
                if (table.Columns.Any(c =>
                        c.ColumnName.Equals(extra.ColumnName, StringComparison.OrdinalIgnoreCase)))
                    continue;

                maxId++;
                table.Columns.Add(new ColumnSchema
                {
                    ColumnName = extra.ColumnName,
                    DataType = "VARCHAR2",
                    DataLength = 250,
                    Nullable = extra.Nullable,
                    ColumnId = maxId,
                    IsExtraColumn = true,
                    OracleSelectExpression = extra.OracleSelectExpression,
                    MssqlTypeOverride = extra.MssqlType,
                    FillAfterLoad = extra.FillAfterLoad
                });
            }
        }
    }

    public static IReadOnlyList<ExtraColumnDefinition> GetFillAfterLoadColumns(
        string tableName,
        MigrationConfig config) =>
        config.ExtraColumns
            .Where(e =>
                e.FillAfterLoad
                && !string.IsNullOrWhiteSpace(e.OracleSelectExpression)
                && e.TableName.Equals(tableName, StringComparison.OrdinalIgnoreCase))
            .ToList();
}
