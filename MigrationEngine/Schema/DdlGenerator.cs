using MigrationShared.Models;
using Serilog;
using System.Text;

namespace MigrationEngine.Schema;

public class DdlGenerator
{
    private readonly TypeMapper _typeMapper;

    public DdlGenerator()
    {
        _typeMapper = new TypeMapper();
    }

    /// <summary>
    /// Columns that are created on SQL Server (excludes SKIP mappings such as ROWID and UDT columns
    /// already filtered out at schema read time).
    /// </summary>
    public IReadOnlyList<ColumnSchema> GetMigratableColumns(TableSchema table)
    {
        var columns = new List<ColumnSchema>();
        foreach (var column in table.Columns)
        {
            var mapPrecision = TypeMapper.ResolvePrecisionArgument(
                column.DataType, column.DataPrecision, column.DataLength);
            var mapping = _typeMapper.MapType(
                column.DataType, mapPrecision, column.DataScale, column.ColumnName,
                column.IsSpatial, column.Srid);
            if (mapping.SqlType != "SKIP")
                columns.Add(column);
        }

        return columns.OrderBy(c => c.ColumnId).ToList();
    }

    public (string createTableDdl, List<string> primaryKeyDdl, List<string> uniqueConstraintDdl, List<string> indexDdl, List<string> foreignKeyDdl, List<TypeMappingWarning> warnings) 
        GenerateDdl(TableSchema table, bool migrateUniqueConstraints = true)
    {
        var warnings = new List<TypeMappingWarning>();
        var createTableBuilder = new StringBuilder();
        var primaryKeyDdl = new List<string>();
        var uniqueConstraintDdl = new List<string>();
        var indexDdl = new List<string>();
        var foreignKeyDdl = new List<string>();

        createTableBuilder.AppendLine($"CREATE TABLE [{table.TableName}] (");

        var columnDefs = new List<string>();
        foreach (var column in table.Columns)
        {
            var mapPrecision = TypeMapper.ResolvePrecisionArgument(column.DataType, column.DataPrecision, column.DataLength);

            if (SpatialColumnHelper.IsSpatialColumn(column))
            {
                var targetType = string.Equals(column.SpatialTargetType, "geography", StringComparison.OrdinalIgnoreCase)
                    ? "geography"
                    : "geometry";
                var wktCol = SpatialColumnHelper.GetWktStagingColumnName(column);

                warnings.Add(new TypeMappingWarning
                {
                    TableName = table.TableName,
                    ColumnName = column.ColumnName,
                    OracleType = column.DataType,
                    MssqlType = targetType,
                    WarningMessage =
                        $"Oracle SDO_GEOMETRY → {targetType} (WKT bulk-staged in [{wktCol}], DotSpatial reproject at post-load)"
                });

                columnDefs.Add($"    [{column.ColumnName}] {targetType} NULL");
                columnDefs.Add($"    [{wktCol}] NVARCHAR(MAX) NULL");
                continue;
            }

            if (!string.IsNullOrWhiteSpace(column.MssqlTypeOverride))
            {
                var nullability = column.Nullable ? "NULL" : "NOT NULL";
                columnDefs.Add($"    [{column.ColumnName}] {column.MssqlTypeOverride} {nullability}");
                if (column.IsExtraColumn)
                {
                    warnings.Add(new TypeMappingWarning
                    {
                        TableName = table.TableName,
                        ColumnName = column.ColumnName,
                        OracleType = "EXTRA",
                        MssqlType = column.MssqlTypeOverride,
                        WarningMessage = column.FillAfterLoad
                            ? "Extra column — filled after load from Oracle expression"
                            : "Extra column — selected from Oracle expression during extract"
                    });
                }

                continue;
            }

            var mapping = _typeMapper.MapType(column.DataType, mapPrecision,
                column.DataScale, column.ColumnName, column.IsSpatial, column.Srid);

            if (mapping.SqlType == "SKIP")
            {
                warnings.Add(new TypeMappingWarning
                {
                    TableName = table.TableName,
                    ColumnName = column.ColumnName,
                    OracleType = column.DataType,
                    MssqlType = "SKIPPED",
                    WarningMessage = mapping.WarningMessage ?? "Column skipped"
                });
                continue;
            }

            if (mapping.HasWarning && !string.IsNullOrEmpty(mapping.WarningMessage))
            {
                warnings.Add(new TypeMappingWarning
                {
                    TableName = table.TableName,
                    ColumnName = column.ColumnName,
                    OracleType = column.DataType,
                    MssqlType = mapping.SqlType,
                    WarningMessage = mapping.WarningMessage
                });
            }

            var columnDef = $"    [{column.ColumnName}] {mapping.SqlType}";

            if (!column.Nullable)
            {
                columnDef += " NOT NULL";
            }

            if (!string.IsNullOrWhiteSpace(column.DefaultValue))
            {
                var mappedDefault = _typeMapper.MapDefaultValue(column.DefaultValue);
                columnDef += $" DEFAULT {mappedDefault}";
            }

            columnDefs.Add(columnDef);
        }

        createTableBuilder.AppendLine(string.Join(",\n", columnDefs));
        createTableBuilder.AppendLine(");");

        var pkConstraint = table.Constraints.FirstOrDefault(c => c.ConstraintType == "P");
        if (pkConstraint != null)
        {
            var pkColumns = string.Join(", ", pkConstraint.Columns.Select(c => $"[{c}]"));
            primaryKeyDdl.Add($"ALTER TABLE [{table.TableName}] ADD CONSTRAINT [PK_{table.TableName}] PRIMARY KEY ({pkColumns});");
        }

        var uniqueConstraints = table.Constraints.Where(c => c.ConstraintType == "U");
        foreach (var unique in uniqueConstraints)
        {
            var uniqueColumns = string.Join(", ", unique.Columns.Select(c => $"[{c}]"));
            var ddl = $"ALTER TABLE [{table.TableName}] ADD CONSTRAINT [{unique.ConstraintName}] UNIQUE ({uniqueColumns});";
            if (migrateUniqueConstraints)
                uniqueConstraintDdl.Add(ddl);
        }

        foreach (var index in table.Indexes)
        {
            var uniqueKeyword = index.IsUnique ? "UNIQUE " : "";
            var indexColumns = string.Join(", ", index.Columns.OrderBy(c => c.ColumnPosition)
                .Select(c => $"[{c.ColumnName}]" + (c.DescendFlag == "DESC" ? " DESC" : "")));
            
            indexDdl.Add($@"CREATE {uniqueKeyword}NONCLUSTERED INDEX [{index.IndexName}] 
ON [{table.TableName}] ({indexColumns})
WITH (SORT_IN_TEMPDB = ON, MAXDOP = 8, DATA_COMPRESSION = PAGE);");
        }

        var fkConstraints = table.Constraints.Where(c => c.ConstraintType == "R");
        foreach (var fk in fkConstraints)
        {
            if (string.IsNullOrEmpty(fk.ReferenceTableName) || fk.ReferenceColumns == null || !fk.ReferenceColumns.Any())
            {
                Log.Warning("Foreign key {Constraint} on table {Table} has invalid reference", 
                    fk.ConstraintName, table.TableName);
                continue;
            }

            var fkColumns = string.Join(", ", fk.Columns.Select(c => $"[{c}]"));
            var refColumns = string.Join(", ", fk.ReferenceColumns.Select(c => $"[{c}]"));

            var deleteAction = fk.DeleteRule switch
            {
                "CASCADE" => " ON DELETE CASCADE",
                "SET NULL" => " ON DELETE SET NULL",
                _ => ""
            };

            foreignKeyDdl.Add($@"ALTER TABLE [{table.TableName}] 
ADD CONSTRAINT [{fk.ConstraintName}] 
FOREIGN KEY ({fkColumns}) 
REFERENCES [{fk.ReferenceTableName}] ({refColumns}){deleteAction};");
        }

        return (createTableBuilder.ToString(), primaryKeyDdl, uniqueConstraintDdl, indexDdl, foreignKeyDdl, warnings);
    }

    public List<string> DetectCircularForeignKeys(List<TableSchema> tables)
    {
        var circularReferences = new List<string>();
        var graph = BuildDependencyGraph(tables);

        foreach (var table in tables)
        {
            var visited = new HashSet<string>();
            var recursionStack = new HashSet<string>();

            if (HasCycle(table.TableName, graph, visited, recursionStack, new List<string>(), circularReferences))
            {
                Log.Warning("Circular foreign key dependency detected involving table {Table}", table.TableName);
            }
        }

        return circularReferences.Distinct().ToList();
    }

    private Dictionary<string, List<string>> BuildDependencyGraph(List<TableSchema> tables)
    {
        var graph = new Dictionary<string, List<string>>();

        foreach (var table in tables)
        {
            if (!graph.ContainsKey(table.TableName))
            {
                graph[table.TableName] = new List<string>();
            }

            var fkConstraints = table.Constraints.Where(c => c.ConstraintType == "R");
            foreach (var fk in fkConstraints)
            {
                if (!string.IsNullOrEmpty(fk.ReferenceTableName))
                {
                    graph[table.TableName].Add(fk.ReferenceTableName);
                }
            }
        }

        return graph;
    }

    private bool HasCycle(string node, Dictionary<string, List<string>> graph, 
        HashSet<string> visited, HashSet<string> recursionStack, 
        List<string> path, List<string> circularReferences)
    {
        if (recursionStack.Contains(node))
        {
            var cycle = string.Join(" -> ", path.SkipWhile(n => n != node).Append(node));
            circularReferences.Add(cycle);
            return true;
        }

        if (visited.Contains(node))
            return false;

        visited.Add(node);
        recursionStack.Add(node);
        path.Add(node);

        if (graph.ContainsKey(node))
        {
            foreach (var neighbor in graph[node])
            {
                if (HasCycle(neighbor, graph, visited, recursionStack, new List<string>(path), circularReferences))
                {
                    return true;
                }
            }
        }

        recursionStack.Remove(node);
        return false;
    }
}
