using Oracle.ManagedDataAccess.Client;
using Serilog;

namespace MigrationEngine.Schema;

public class SchemaReader
{
    private readonly string _connectionString;
    private readonly string _schemaName;
    private readonly bool _migrateSpatial;

    public SchemaReader(string connectionString, string schemaName, bool migrateSpatial = true)
    {
        _connectionString = connectionString;
        _schemaName = schemaName.ToUpper();
        _migrateSpatial = migrateSpatial;
    }

    public async Task<List<TableSchema>> ReadSchemaAsync(List<string> includeTables, List<string> excludePatterns, CancellationToken ct)
    {
        var tables = new List<TableSchema>();

        using var connection = new OracleConnection(_connectionString);
        await connection.OpenAsync(ct);

        var tableNames = await GetTableNamesAsync(connection, includeTables, excludePatterns, ct);
        Log.Information("Found {Count} tables in schema {Schema}", tableNames.Count, _schemaName);

        foreach (var tableName in tableNames)
        {
            var table = new TableSchema { TableName = tableName };
            table.Columns = await GetColumnsAsync(connection, tableName, ct);
            SpatialColumnHelper.MarkSpatialColumns(table);

            if (_migrateSpatial)
            {
                var spatialMetadata = await GetSpatialMetadataAsync(connection, tableName, ct);
                EnsureSpatialColumnsFromMetadata(table, spatialMetadata);

                foreach (var column in table.Columns.Where(SpatialColumnHelper.IsSpatialColumn))
                {
                    if (spatialMetadata.TryGetValue(column.ColumnName, out var srid))
                        column.Srid = srid;

                    if (!column.Srid.HasValue || column.Srid == 0)
                    {
                        var sridFromGeom = await TryGetDominantSdoSridFromDataAsync(
                            connection, tableName, column.ColumnName, ct);
                        if (sridFromGeom.HasValue)
                        {
                            column.Srid = sridFromGeom;
                            Log.Information(
                                "Table {Table}: [{Column}] SRID={Srid} from SDO_GEOMETRY.SDO_SRID (ALL_SDO_GEOM_METADATA empty)",
                                tableName, column.ColumnName, sridFromGeom);
                        }
                        else
                        {
                            Log.Warning(
                                "Table {Table}: [{Column}] has no SRID in metadata or geometry — config override will apply",
                                tableName, column.ColumnName);
                        }
                    }

                    column.SpatialTargetType = column.Srid == 4326 ? "geography" : "geometry";
                }

                var spatialCount = table.Columns.Count(SpatialColumnHelper.IsSpatialColumn);
                if (spatialCount > 0)
                {
                    Log.Information(
                        "Table {Table}: {Count} SDO_GEOMETRY column(s) — WKT bridge → {Target}",
                        tableName,
                        spatialCount,
                        string.Join(", ", table.Columns.Where(SpatialColumnHelper.IsSpatialColumn)
                            .Select(c => $"{c.ColumnName}({c.SpatialTargetType}, SRID={c.Srid?.ToString() ?? "?"})")));
                }
            }

            var skippedUdt = await GetUdtColumnCountAsync(connection, tableName, ct);
            if (skippedUdt > 0)
                Log.Warning("Table {Table}: skipped {Count} user-defined type column(s) — not mappable to SQL Server", tableName, skippedUdt);

            table.Constraints = await GetConstraintsAsync(connection, tableName, ct);
            table.Indexes = await GetIndexesAsync(connection, tableName, ct);
            tables.Add(table);
        }

        return tables;
    }

    private async Task<List<string>> GetTableNamesAsync(OracleConnection conn, List<string> includeTables, List<string> excludePatterns, CancellationToken ct)
    {
        const string sql = @"
            SELECT table_name 
            FROM all_tables 
            WHERE owner = :schema
            ORDER BY table_name";

        var allTables = new List<string>();
        using var cmd = new OracleCommand(sql, conn);
        cmd.Parameters.Add("schema", OracleDbType.Varchar2).Value = _schemaName;

        using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            allTables.Add(reader.GetString(0));
        }

        if (includeTables.Any())
        {
            allTables = allTables.Where(t => includeTables.Contains(t, StringComparer.OrdinalIgnoreCase)).ToList();
        }

        if (excludePatterns.Any())
        {
            allTables = allTables.Where(t => !excludePatterns.Any(pattern => 
                MatchesPattern(t, pattern))).ToList();
        }

        return allTables;
    }

    private bool MatchesPattern(string tableName, string pattern)
    {
        if (pattern.Contains('*'))
        {
            var regexPattern = "^" + System.Text.RegularExpressions.Regex.Escape(pattern)
                .Replace("\\*", ".*") + "$";
            return System.Text.RegularExpressions.Regex.IsMatch(tableName, regexPattern, 
                System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        }
        return tableName.Equals(pattern, StringComparison.OrdinalIgnoreCase);
    }

    private async Task<List<ColumnSchema>> GetColumnsAsync(OracleConnection conn, string tableName, CancellationToken ct)
    {
        // Scalar columns + optional SDO_GEOMETRY (MDSYS UDT). Other UDTs are excluded — they trigger
        // ORA-06550 PLS-00306 (GET_TYPE_SHAPE) and can't map to SQL Server without custom handling.
        var sql = _migrateSpatial
            ? @"
            SELECT
                column_name,
                data_type,
                data_length,
                data_precision,
                data_scale,
                nullable,
                data_default,
                column_id,
                data_type_owner
            FROM all_tab_columns
            WHERE owner = :schema AND table_name = :tableName
              AND (
                    data_type_owner IS NULL
                    OR UPPER(data_type) = 'SDO_GEOMETRY'
                  )
            ORDER BY column_id"
            : @"
            SELECT
                column_name,
                data_type,
                data_length,
                data_precision,
                data_scale,
                nullable,
                data_default,
                column_id,
                data_type_owner
            FROM all_tab_columns
            WHERE owner = :schema AND table_name = :tableName
              AND data_type_owner IS NULL
            ORDER BY column_id";

        var columns = new List<ColumnSchema>();
        using var cmd = new OracleCommand(sql, conn);
        cmd.Parameters.Add("schema", OracleDbType.Varchar2).Value = _schemaName;
        cmd.Parameters.Add("tableName", OracleDbType.Varchar2).Value = tableName;

        using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var dataTypeOwner = reader.IsDBNull(8) ? null : reader.GetString(8);
            var dataType = reader.GetString(1);
            var isSpatial = _migrateSpatial
                && string.Equals(dataType, "SDO_GEOMETRY", StringComparison.OrdinalIgnoreCase);

            columns.Add(new ColumnSchema
            {
                ColumnName = reader.GetString(0),
                DataType = dataType,
                DataLength = reader.IsDBNull(2) ? null : reader.GetInt32(2),
                DataPrecision = reader.IsDBNull(3) ? null : reader.GetInt32(3),
                DataScale = reader.IsDBNull(4) ? null : reader.GetInt32(4),
                Nullable = reader.GetString(5) == "Y",
                DefaultValue = reader.IsDBNull(6) ? null : reader.GetString(6)?.Trim(),
                ColumnId = reader.GetInt32(7),
                IsSpatial = isSpatial,
                SpatialTargetType = isSpatial ? "geometry" : null
            });
        }

        return columns;
    }

    private async Task<Dictionary<string, int>> GetSpatialMetadataAsync(
        OracleConnection conn, string tableName, CancellationToken ct)
    {
        const string sql = @"
            SELECT column_name, srid
            FROM all_sdo_geom_metadata
            WHERE owner = :schema AND table_name = :tableName";

        var metadata = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var cmd = new OracleCommand(sql, conn);
            cmd.Parameters.Add("schema", OracleDbType.Varchar2).Value = _schemaName;
            cmd.Parameters.Add("tableName", OracleDbType.Varchar2).Value = tableName;

            using var reader = await cmd.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                var columnName = reader.GetString(0);
                if (reader.IsDBNull(1))
                {
                    Log.Debug(
                        "ALL_SDO_GEOM_METADATA: {Table}.{Column} has NULL SRID",
                        tableName, columnName);
                    continue;
                }

                metadata[columnName] = Convert.ToInt32(reader.GetValue(1));
            }
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "Could not read ALL_SDO_GEOM_METADATA for table {Table}", tableName);
        }

        return metadata;
    }

    /// <summary>
    /// When ALL_SDO_GEOM_METADATA.SRID is NULL, infer from the most common SDO_GEOMETRY.SDO_SRID in sample rows.
    /// </summary>
    private async Task<int?> TryGetDominantSdoSridFromDataAsync(
        OracleConnection conn,
        string tableName,
        string columnName,
        CancellationToken ct)
    {
        if (!IsSafeOracleIdentifier(columnName))
            return null;

        var sql = $@"
            SELECT sdo_srid FROM (
                SELECT g.sdo_srid, COUNT(*) AS cnt
                FROM (
                    SELECT t.{columnName}.SDO_SRID AS sdo_srid
                    FROM {_schemaName}.{tableName} t
                    WHERE t.{columnName} IS NOT NULL
                ) g
                WHERE g.sdo_srid IS NOT NULL
                GROUP BY g.sdo_srid
                ORDER BY COUNT(*) DESC
            )
            WHERE ROWNUM = 1";

        try
        {
            using var cmd = new OracleCommand(sql, conn) { CommandTimeout = 60 };
            var result = await cmd.ExecuteScalarAsync(ct);
            if (result is null or DBNull)
                return null;

            return Convert.ToInt32(result);
        }
        catch (Exception ex)
        {
            Log.Warning(ex,
                "Could not read SDO_SRID from {Table}.{Column} sample data",
                tableName, columnName);
            return null;
        }
    }

    private static bool IsSafeOracleIdentifier(string name) =>
        !string.IsNullOrEmpty(name)
        && name.All(c => char.IsLetterOrDigit(c) || c == '_' || c == '$' || c == '#');

    /// <summary>
    /// ALL_TAB_COLUMNS bazen SDO_GEOMETRY kolonunu UDT olarak filtreler; metadata'dan ekler.
    /// </summary>
    private static void EnsureSpatialColumnsFromMetadata(TableSchema table, Dictionary<string, int> spatialMetadata)
    {
        if (spatialMetadata.Count == 0)
            return;

        var maxColumnId = table.Columns.Count > 0 ? table.Columns.Max(c => c.ColumnId) : 0;

        foreach (var (columnName, srid) in spatialMetadata)
        {
            if (table.Columns.Any(c => c.ColumnName.Equals(columnName, StringComparison.OrdinalIgnoreCase)))
                continue;

            maxColumnId++;
            Log.Warning(
                "Table {Table}: spatial column [{Column}] found in ALL_SDO_GEOM_METADATA but missing from column list — adding",
                table.TableName, columnName);

            table.Columns.Add(new ColumnSchema
            {
                ColumnName = columnName,
                DataType = "SDO_GEOMETRY",
                Nullable = true,
                ColumnId = maxColumnId,
                IsSpatial = true,
                Srid = srid,
                SpatialTargetType = srid == 4326 ? "geography" : "geometry"
            });
        }

        SpatialColumnHelper.MarkSpatialColumns(table);
    }

    private async Task<List<ConstraintSchema>> GetConstraintsAsync(OracleConnection conn, string tableName, CancellationToken ct)
    {
        const string sql = @"
            SELECT 
                c.constraint_name,
                c.constraint_type,
                c.r_constraint_name,
                c.delete_rule
            FROM all_constraints c
            WHERE c.owner = :schema AND c.table_name = :tableName
            AND c.constraint_type IN ('P', 'U', 'R')
            ORDER BY 
                CASE c.constraint_type 
                    WHEN 'P' THEN 1 
                    WHEN 'U' THEN 2 
                    WHEN 'R' THEN 3 
                END";

        var constraints = new List<ConstraintSchema>();
        using var cmd = new OracleCommand(sql, conn);
        cmd.Parameters.Add("schema", OracleDbType.Varchar2).Value = _schemaName;
        cmd.Parameters.Add("tableName", OracleDbType.Varchar2).Value = tableName;

        using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var constraint = new ConstraintSchema
            {
                ConstraintName = reader.GetString(0),
                ConstraintType = reader.GetString(1),
                DeleteRule = reader.IsDBNull(3) ? null : reader.GetString(3)
            };

            constraint.Columns = await GetConstraintColumnsAsync(conn, constraint.ConstraintName, ct);

            if (constraint.ConstraintType == "R" && !reader.IsDBNull(2))
            {
                var refInfo = await GetReferenceInfoAsync(conn, reader.GetString(2), ct);
                constraint.ReferenceTableName = refInfo.tableName;
                constraint.ReferenceColumns = refInfo.columns;
            }

            constraints.Add(constraint);
        }

        return constraints;
    }

    private async Task<List<string>> GetConstraintColumnsAsync(OracleConnection conn, string constraintName, CancellationToken ct)
    {
        const string sql = @"
            SELECT column_name
            FROM all_cons_columns
            WHERE owner = :schema AND constraint_name = :constraintName
            ORDER BY position";

        var columns = new List<string>();
        using var cmd = new OracleCommand(sql, conn);
        cmd.Parameters.Add("schema", OracleDbType.Varchar2).Value = _schemaName;
        cmd.Parameters.Add("constraintName", OracleDbType.Varchar2).Value = constraintName;

        using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            columns.Add(reader.GetString(0));
        }

        return columns;
    }

    private async Task<(string tableName, List<string> columns)> GetReferenceInfoAsync(OracleConnection conn, string refConstraintName, CancellationToken ct)
    {
        const string sql = @"
            SELECT c.table_name
            FROM all_constraints c
            WHERE c.owner = :schema AND c.constraint_name = :constraintName";

        string? tableName = null;
        using (var cmd = new OracleCommand(sql, conn))
        {
            cmd.Parameters.Add("schema", OracleDbType.Varchar2).Value = _schemaName;
            cmd.Parameters.Add("constraintName", OracleDbType.Varchar2).Value = refConstraintName;

            using var reader = await cmd.ExecuteReaderAsync(ct);
            if (await reader.ReadAsync(ct))
            {
                tableName = reader.GetString(0);
            }
        }

        var columns = await GetConstraintColumnsAsync(conn, refConstraintName, ct);
        return (tableName ?? string.Empty, columns);
    }

    private async Task<List<IndexSchema>> GetIndexesAsync(OracleConnection conn, string tableName, CancellationToken ct)
    {
        const string sql = @"
            SELECT 
                i.index_name,
                i.uniqueness
            FROM all_indexes i
            WHERE i.owner = :schema 
            AND i.table_name = :tableName
            AND NOT EXISTS (
                SELECT 1 FROM all_constraints c
                WHERE c.owner = i.owner 
                AND c.table_name = i.table_name
                AND c.index_name = i.index_name
            )
            ORDER BY i.index_name";

        var indexes = new List<IndexSchema>();
        using var cmd = new OracleCommand(sql, conn);
        cmd.Parameters.Add("schema", OracleDbType.Varchar2).Value = _schemaName;
        cmd.Parameters.Add("tableName", OracleDbType.Varchar2).Value = tableName;

        using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var index = new IndexSchema
            {
                IndexName = reader.GetString(0),
                IsUnique = reader.GetString(1) == "UNIQUE"
            };

            index.Columns = await GetIndexColumnsAsync(conn, index.IndexName, ct);
            indexes.Add(index);
        }

        return indexes;
    }

    private async Task<List<IndexColumn>> GetIndexColumnsAsync(OracleConnection conn, string indexName, CancellationToken ct)
    {
        const string sql = @"
            SELECT column_name, column_position, descend
            FROM all_ind_columns
            WHERE index_owner = :schema AND index_name = :indexName
            ORDER BY column_position";

        var columns = new List<IndexColumn>();
        using var cmd = new OracleCommand(sql, conn);
        cmd.Parameters.Add("schema", OracleDbType.Varchar2).Value = _schemaName;
        cmd.Parameters.Add("indexName", OracleDbType.Varchar2).Value = indexName;

        using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            columns.Add(new IndexColumn
            {
                ColumnName = reader.GetString(0),
                ColumnPosition = reader.GetInt32(1),
                DescendFlag = reader.IsDBNull(2) ? null : reader.GetString(2)
            });
        }

        return columns;
    }

    private async Task<int> GetUdtColumnCountAsync(OracleConnection conn, string tableName, CancellationToken ct)
    {
        try
        {
            var sql = _migrateSpatial
                ? @"
                SELECT COUNT(*) FROM all_tab_columns
                WHERE owner = :schema AND table_name = :tableName
                  AND data_type_owner IS NOT NULL
                  AND UPPER(data_type) <> 'SDO_GEOMETRY'"
                : @"
                SELECT COUNT(*) FROM all_tab_columns
                WHERE owner = :schema AND table_name = :tableName
                  AND data_type_owner IS NOT NULL";

            using var cmd = new OracleCommand(sql, conn);
            cmd.Parameters.Add("schema", OracleDbType.Varchar2).Value = _schemaName;
            cmd.Parameters.Add("tableName", OracleDbType.Varchar2).Value = tableName;
            var result = await cmd.ExecuteScalarAsync(ct);
            return Convert.ToInt32(result);
        }
        catch
        {
            return 0;
        }
    }

    public async Task<long> GetTableRowCountAsync(string tableName, CancellationToken ct)
    {
        using var connection = new OracleConnection(_connectionString);
        await connection.OpenAsync(ct);

        var sql = $"SELECT COUNT(*) FROM {_schemaName}.{tableName}";
        using var cmd = new OracleCommand(sql, connection);
        
        var result = await cmd.ExecuteScalarAsync(ct);
        return Convert.ToInt64(result);
    }
}
