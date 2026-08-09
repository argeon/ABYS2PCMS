using System.Text;

namespace MssqlCopyEngine.Schema;

public sealed class MssqlDdlGenerator
{
    public string GenerateCreateTable(MssqlTableSchema table, bool includePrimaryKey)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"IF OBJECT_ID(N'{Quote(table.SchemaName)}.{Quote(table.TableName)}', N'U') IS NULL");
        sb.AppendLine("BEGIN");
        sb.AppendLine($"CREATE TABLE {Quote(table.SchemaName)}.{Quote(table.TableName)} (");

        var parts = new List<string>();
        foreach (var col in table.Columns.OrderBy(c => c.Ordinal))
            parts.Add("    " + FormatColumn(col));

        if (includePrimaryKey && table.PrimaryKeyColumns.Count > 0)
        {
            var pkCols = string.Join(", ", table.PrimaryKeyColumns.Select(Quote));
            parts.Add($"    CONSTRAINT {Quote("PK_" + table.TableName)} PRIMARY KEY ({pkCols})");
        }

        sb.AppendLine(string.Join(",\n", parts));
        sb.AppendLine(");");
        sb.AppendLine("END");
        return sb.ToString();
    }

    public string GenerateDropTable(MssqlTableSchema table) =>
        $"IF OBJECT_ID(N'{Quote(table.SchemaName)}.{Quote(table.TableName)}', N'U') IS NOT NULL DROP TABLE {Quote(table.SchemaName)}.{Quote(table.TableName)};";

    public IEnumerable<string> GenerateIndexes(MssqlTableSchema table, bool uniqueOnly)
    {
        foreach (var idx in table.Indexes.Where(i => !i.IsPrimaryKey))
        {
            if (uniqueOnly && !idx.IsUnique)
                continue;
            if (!uniqueOnly && idx.IsUnique)
                continue; // unique handled separately via MigrateUniqueConstraints

            var unique = idx.IsUnique ? "UNIQUE " : "";
            var cols = string.Join(", ", idx.Columns.Select(Quote));
            yield return
                $"IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'{Escape(idx.IndexName)}' AND object_id = OBJECT_ID(N'{Quote(table.SchemaName)}.{Quote(table.TableName)}'))\n" +
                $"CREATE {unique}INDEX {Quote(idx.IndexName)} ON {Quote(table.SchemaName)}.{Quote(table.TableName)} ({cols});";
        }
    }

    public IEnumerable<string> GenerateUniqueConstraints(MssqlTableSchema table)
    {
        foreach (var idx in table.Indexes.Where(i => i.IsUnique && !i.IsPrimaryKey))
        {
            var cols = string.Join(", ", idx.Columns.Select(Quote));
            yield return
                $"IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'{Escape(idx.IndexName)}' AND object_id = OBJECT_ID(N'{Quote(table.SchemaName)}.{Quote(table.TableName)}'))\n" +
                $"CREATE UNIQUE INDEX {Quote(idx.IndexName)} ON {Quote(table.SchemaName)}.{Quote(table.TableName)} ({cols});";
        }
    }

    public IEnumerable<string> GenerateForeignKeys(MssqlTableSchema table)
    {
        foreach (var fk in table.ForeignKeys)
        {
            var cols = string.Join(", ", fk.Columns.Select(Quote));
            var refCols = string.Join(", ", fk.ReferencedColumns.Select(Quote));
            yield return
                $"IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'{Escape(fk.ConstraintName)}')\n" +
                $"ALTER TABLE {Quote(table.SchemaName)}.{Quote(table.TableName)} ADD CONSTRAINT {Quote(fk.ConstraintName)} " +
                $"FOREIGN KEY ({cols}) REFERENCES {Quote(fk.ReferencedSchema)}.{Quote(fk.ReferencedTable)} ({refCols});";
        }
    }

    public IEnumerable<string> GenerateCheckConstraints(MssqlTableSchema table)
    {
        foreach (var ck in table.CheckConstraints)
        {
            yield return
                $"IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'{Escape(ck.ConstraintName)}')\n" +
                $"ALTER TABLE {Quote(table.SchemaName)}.{Quote(table.TableName)} ADD CONSTRAINT {Quote(ck.ConstraintName)} CHECK {ck.Definition};";
        }
    }

    private static string FormatColumn(MssqlColumnSchema col)
    {
        var type = FormatType(col);
        // Preserve source collation so SqlBulkCopy LocaleId matches (e.g. 1055 vs 1033)
        var collation = col.IsCharacterType && !string.IsNullOrWhiteSpace(col.CollationName)
            ? $" COLLATE {col.CollationName}"
            : "";
        var nullability = col.IsNullable ? "NULL" : "NOT NULL";
        var identity = col.IsIdentity
            ? $" IDENTITY({col.IdentitySeed ?? 1},{col.IdentityIncrement ?? 1})"
            : "";
        var def = !string.IsNullOrWhiteSpace(col.DefaultDefinition) && !col.IsIdentity
            ? $" DEFAULT {col.DefaultDefinition}"
            : "";
        return $"{Quote(col.ColumnName)} {type}{collation}{identity} {nullability}{def}";
    }

    private static string FormatType(MssqlColumnSchema col)
    {
        var t = col.DataType.ToLowerInvariant();

        // These types never take a length/precision width. sys.columns.max_length is often -1
        // for geometry/geography — do NOT emit geometry(max) (SQL error: cannot specify column width).
        switch (t)
        {
            case "geometry":
            case "geography":
            case "hierarchyid":
            case "xml":
            case "sql_variant":
            case "uniqueidentifier":
            case "bit":
            case "int":
            case "bigint":
            case "smallint":
            case "tinyint":
            case "money":
            case "smallmoney":
            case "real":
            case "date":
            case "datetime":
            case "smalldatetime":
            case "image":
            case "ntext":
            case "text":
            case "timestamp":
            case "rowversion":
                return t;
            case "sysname":
                return "nvarchar(128)";
        }

        var len = col.MaxLength;
        if (len is -1)
            return $"{t}(max)";

        return t switch
        {
            "nvarchar" or "nchar" => len is null or <= 0 or > 4000 ? "nvarchar(max)" : $"{t}({len})",
            "varchar" or "char" => len is null or <= 0 or > 8000 ? $"{t}(max)" : $"{t}({len})",
            "varbinary" or "binary" => len is null or <= 0 or > 8000 ? "varbinary(max)" : $"{t}({len})",
            "decimal" or "numeric" => $"{t}({col.Precision ?? 18},{col.Scale ?? 0})",
            "datetime2" or "datetimeoffset" or "time" => col.Scale is > 0 ? $"{t}({col.Scale})" : t,
            "float" => col.Precision is > 0 and < 53 ? $"{t}({col.Precision})" : t,
            _ => t
        };
    }

    private static string Quote(string name) => $"[{name.Replace("]", "]]")}]";
    private static string Escape(string name) => name.Replace("'", "''");
}
