using Microsoft.Data.SqlClient;
using Serilog;

namespace MssqlCopyEngine.Schema;

public sealed class MssqlSchemaReader
{
    private readonly string _connectionString;
    private readonly string _schema;

    public MssqlSchemaReader(string connectionString, string schema)
    {
        _connectionString = connectionString;
        _schema = string.IsNullOrWhiteSpace(schema) ? "dbo" : schema.Trim();
    }

    public async Task<List<MssqlTableSchema>> ReadTablesAsync(
        IReadOnlyList<string> tableNames,
        CancellationToken ct)
    {
        var result = new List<MssqlTableSchema>();
        await using var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);

        foreach (var rawName in tableNames.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var table = await ReadOneObjectAsync(conn, rawName, ct);
            if (table != null)
                result.Add(table);
            else
                Log.Warning("Source table/view not found: {Schema}.{Table}", _schema, rawName);
        }

        return result;
    }

    private async Task<MssqlTableSchema?> ReadOneObjectAsync(SqlConnection conn, string objectName, CancellationToken ct)
    {
        const string kindSql = @"
SELECT o.type
FROM sys.objects o
INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name = @schema AND o.name = @name
  AND o.is_ms_shipped = 0
  AND o.type IN ('U', 'V')";

        string? typeCode;
        await using (var kindCmd = new SqlCommand(kindSql, conn))
        {
            kindCmd.Parameters.AddWithValue("@schema", _schema);
            kindCmd.Parameters.AddWithValue("@name", objectName);
            typeCode = (string?)await kindCmd.ExecuteScalarAsync(ct);
        }

        if (string.IsNullOrEmpty(typeCode))
            return null;

        var kind = typeCode.Trim() == "V" ? MssqlObjectKind.View : MssqlObjectKind.Table;
        var table = new MssqlTableSchema
        {
            SchemaName = _schema,
            TableName = objectName,
            ObjectKind = kind
        };

        table.Columns = await ReadColumnsAsync(conn, objectName, ct);
        if (table.Columns.Count == 0)
        {
            Log.Warning("No columns resolved for {Kind} {Schema}.{Name}", kind, _schema, objectName);
            return null;
        }

        if (kind == MssqlObjectKind.Table)
        {
            table.PrimaryKeyColumns = await ReadPrimaryKeyAsync(conn, objectName, ct);
            table.Indexes = await ReadIndexesAsync(conn, objectName, ct);
            table.ForeignKeys = await ReadForeignKeysAsync(conn, objectName, ct);
            table.CheckConstraints = await ReadCheckConstraintsAsync(conn, objectName, ct);
            table.EstimatedRows = await ReadRowEstimateAsync(conn, objectName, ct);
        }
        else
        {
            table.BaseTables = await ResolveViewBaseTablesAsync(conn, objectName, ct);
            table.EstimatedRows = await EstimateViewRowsAsync(conn, table.BaseTables, ct);
            Log.Information(
                "VIEW {Schema}.{View} → base tables: {Bases} (est.rows~{Rows})",
                _schema, objectName,
                table.BaseTables.Count == 0 ? "(none/ unresolved)" : string.Join(", ", table.BaseTables),
                table.EstimatedRows);

            // Prefer PK from single base table when view is a simple projection
            if (table.BaseTables.Count == 1)
            {
                var baseName = table.BaseTables[0].Contains('.')
                    ? table.BaseTables[0].Split('.').Last().Trim('[', ']')
                    : table.BaseTables[0];
                try
                {
                    table.PrimaryKeyColumns = await ReadPrimaryKeyAsync(conn, baseName, ct);
                }
                catch
                {
                    table.PrimaryKeyColumns = new List<string>();
                }
            }
        }

        return table;
    }

    private async Task<List<string>> ResolveViewBaseTablesAsync(SqlConnection conn, string viewName, CancellationToken ct)
    {
        // sql_expression_dependencies: referenced user tables (and views, filtered to U)
        const string sql = @"
SELECT DISTINCT
    ISNULL(rs.name, @schema) AS ref_schema,
    ro.name AS ref_name
FROM sys.sql_expression_dependencies d
INNER JOIN sys.objects o ON o.object_id = d.referencing_id
INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
LEFT JOIN sys.objects ro ON ro.object_id = d.referenced_id
LEFT JOIN sys.schemas rs ON rs.schema_id = ro.schema_id
WHERE s.name = @schema AND o.name = @view AND o.type = 'V'
  AND d.referenced_id IS NOT NULL
  AND ro.type = 'U'
  AND ISNULL(ro.is_ms_shipped, 0) = 0
ORDER BY 1, 2";

        var list = new List<string>();
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@schema", _schema);
        cmd.Parameters.AddWithValue("@view", viewName);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var sch = reader.GetString(0);
            var name = reader.GetString(1);
            list.Add($"{sch}.{name}");
        }

        // Fallback: parse sp_depends-style via referenced_entity_name when object_id null (cross-db)
        if (list.Count == 0)
        {
            const string sql2 = @"
SELECT DISTINCT d.referenced_schema_name, d.referenced_entity_name
FROM sys.sql_expression_dependencies d
INNER JOIN sys.objects o ON o.object_id = d.referencing_id
INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name = @schema AND o.name = @view AND o.type = 'V'
  AND d.referenced_entity_name IS NOT NULL
ORDER BY 1, 2";
            await using var cmd2 = new SqlCommand(sql2, conn);
            cmd2.Parameters.AddWithValue("@schema", _schema);
            cmd2.Parameters.AddWithValue("@view", viewName);
            await using var reader2 = await cmd2.ExecuteReaderAsync(ct);
            while (await reader2.ReadAsync(ct))
            {
                var sch = reader2.IsDBNull(0) ? _schema : reader2.GetString(0);
                var name = reader2.GetString(1);
                list.Add($"{sch}.{name}");
            }
        }

        return list.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    private async Task<long> EstimateViewRowsAsync(SqlConnection conn, List<string> baseTables, CancellationToken ct)
    {
        if (baseTables.Count == 0)
            return 0;

        // Use largest base table row estimate as proxy
        long max = 0;
        foreach (var fq in baseTables)
        {
            var parts = fq.Split('.');
            var sch = parts.Length > 1 ? parts[0] : _schema;
            var name = parts.Length > 1 ? parts[1] : parts[0];
            const string sql = @"
SELECT ISNULL(SUM(p.rows), 0)
FROM sys.partitions p
INNER JOIN sys.tables t ON t.object_id = p.object_id
INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = @schema AND t.name = @table AND p.index_id IN (0, 1)";
            await using var cmd = new SqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@schema", sch);
            cmd.Parameters.AddWithValue("@table", name);
            var val = await cmd.ExecuteScalarAsync(ct);
            var n = val == null || val == DBNull.Value ? 0L : Convert.ToInt64(val);
            if (n > max) max = n;
        }

        return max;
    }

    private async Task<List<MssqlColumnSchema>> ReadColumnsAsync(SqlConnection conn, string objectName, CancellationToken ct)
    {
        // Works for both tables and views (sys.columns → sys.objects)
        const string sql = @"
SELECT
    c.name AS ColumnName,
    ty.name AS DataType,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    c.is_identity,
    ISNULL(ic.seed_value, 1) AS seed_value,
    ISNULL(ic.increment_value, 1) AS increment_value,
    dc.definition AS DefaultDefinition,
    c.column_id,
    c.collation_name
FROM sys.columns c
INNER JOIN sys.objects o ON o.object_id = c.object_id
INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
INNER JOIN sys.types ty ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.identity_columns ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id
LEFT JOIN sys.default_constraints dc ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
WHERE s.name = @schema AND o.name = @table
  AND o.type IN ('U', 'V')
  AND c.is_computed = 0
  AND ty.name NOT IN ('timestamp', 'rowversion')
ORDER BY c.column_id";

        var cols = new List<MssqlColumnSchema>();
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@schema", _schema);
        cmd.Parameters.AddWithValue("@table", objectName);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var dataType = reader.GetString(1);
            int? maxLength = reader.IsDBNull(2) ? null : Convert.ToInt32(reader.GetValue(2));
            if (maxLength is > 0 && dataType is "nvarchar" or "nchar" or "sysname")
                maxLength /= 2;

            cols.Add(new MssqlColumnSchema
            {
                ColumnName = reader.GetString(0),
                DataType = dataType,
                MaxLength = maxLength,
                Precision = reader.IsDBNull(3) ? null : reader.GetByte(3),
                Scale = reader.IsDBNull(4) ? null : Convert.ToInt32(reader.GetValue(4)),
                IsNullable = reader.GetBoolean(5),
                IsIdentity = reader.GetBoolean(6),
                IdentitySeed = reader.IsDBNull(7) ? null : Convert.ToInt32(reader.GetValue(7)),
                IdentityIncrement = reader.IsDBNull(8) ? null : Convert.ToInt32(reader.GetValue(8)),
                DefaultDefinition = reader.IsDBNull(9) ? null : reader.GetString(9),
                Ordinal = Convert.ToInt32(reader.GetValue(10)),
                CollationName = reader.IsDBNull(11) ? null : reader.GetString(11)
            });
        }

        return cols;
    }

    private async Task<List<string>> ReadPrimaryKeyAsync(SqlConnection conn, string tableName, CancellationToken ct)
    {
        const string sql = @"
SELECT c.name
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
INNER JOIN sys.tables t ON t.object_id = i.object_id
INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = @schema AND t.name = @table AND i.is_primary_key = 1
ORDER BY ic.key_ordinal";

        var cols = new List<string>();
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@schema", _schema);
        cmd.Parameters.AddWithValue("@table", tableName);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
            cols.Add(reader.GetString(0));
        return cols;
    }

    private async Task<List<MssqlIndexSchema>> ReadIndexesAsync(SqlConnection conn, string tableName, CancellationToken ct)
    {
        const string sql = @"
SELECT i.name, i.is_unique, i.is_primary_key, c.name, ic.key_ordinal
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
INNER JOIN sys.tables t ON t.object_id = i.object_id
INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = @schema AND t.name = @table
  AND i.type > 0
  AND ic.is_included_column = 0
ORDER BY i.name, ic.key_ordinal";

        var map = new Dictionary<string, MssqlIndexSchema>(StringComparer.OrdinalIgnoreCase);
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@schema", _schema);
        cmd.Parameters.AddWithValue("@table", tableName);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var name = reader.GetString(0);
            if (!map.TryGetValue(name, out var idx))
            {
                idx = new MssqlIndexSchema
                {
                    IndexName = name,
                    IsUnique = reader.GetBoolean(1),
                    IsPrimaryKey = reader.GetBoolean(2)
                };
                map[name] = idx;
            }
            idx.Columns.Add(reader.GetString(3));
        }

        return map.Values.ToList();
    }

    private async Task<List<MssqlForeignKeySchema>> ReadForeignKeysAsync(SqlConnection conn, string tableName, CancellationToken ct)
    {
        const string sql = @"
SELECT
    fk.name,
    pc.name AS ParentCol,
    rs.name AS RefSchema,
    rt.name AS RefTable,
    rc.name AS RefCol,
    fkc.constraint_column_id
FROM sys.foreign_keys fk
INNER JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
INNER JOIN sys.tables pt ON pt.object_id = fk.parent_object_id
INNER JOIN sys.schemas ps ON ps.schema_id = pt.schema_id
INNER JOIN sys.columns pc ON pc.object_id = fkc.parent_object_id AND pc.column_id = fkc.parent_column_id
INNER JOIN sys.tables rt ON rt.object_id = fk.referenced_object_id
INNER JOIN sys.schemas rs ON rs.schema_id = rt.schema_id
INNER JOIN sys.columns rc ON rc.object_id = fkc.referenced_object_id AND rc.column_id = fkc.referenced_column_id
WHERE ps.name = @schema AND pt.name = @table
ORDER BY fk.name, fkc.constraint_column_id";

        var map = new Dictionary<string, MssqlForeignKeySchema>(StringComparer.OrdinalIgnoreCase);
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@schema", _schema);
        cmd.Parameters.AddWithValue("@table", tableName);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var name = reader.GetString(0);
            if (!map.TryGetValue(name, out var fk))
            {
                fk = new MssqlForeignKeySchema
                {
                    ConstraintName = name,
                    ReferencedSchema = reader.GetString(2),
                    ReferencedTable = reader.GetString(3)
                };
                map[name] = fk;
            }
            fk.Columns.Add(reader.GetString(1));
            fk.ReferencedColumns.Add(reader.GetString(4));
        }

        return map.Values.ToList();
    }

    private async Task<List<MssqlCheckConstraintSchema>> ReadCheckConstraintsAsync(SqlConnection conn, string tableName, CancellationToken ct)
    {
        const string sql = @"
SELECT cc.name, cc.definition
FROM sys.check_constraints cc
INNER JOIN sys.tables t ON t.object_id = cc.parent_object_id
INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = @schema AND t.name = @table AND cc.is_disabled = 0";

        var list = new List<MssqlCheckConstraintSchema>();
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@schema", _schema);
        cmd.Parameters.AddWithValue("@table", tableName);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            list.Add(new MssqlCheckConstraintSchema
            {
                ConstraintName = reader.GetString(0),
                Definition = reader.GetString(1)
            });
        }

        return list;
    }

    private async Task<long> ReadRowEstimateAsync(SqlConnection conn, string tableName, CancellationToken ct)
    {
        const string sql = @"
SELECT SUM(p.rows)
FROM sys.partitions p
INNER JOIN sys.tables t ON t.object_id = p.object_id
INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = @schema AND t.name = @table AND p.index_id IN (0, 1)";

        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@schema", _schema);
        cmd.Parameters.AddWithValue("@table", tableName);
        var val = await cmd.ExecuteScalarAsync(ct);
        return val == null || val == DBNull.Value ? 0 : Convert.ToInt64(val);
    }
}
