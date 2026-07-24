using Microsoft.Data.SqlClient;
using MigrationEngine.Schema;
using MigrationEngine.Spatial;
using MigrationShared.Models;
using Serilog;

namespace MigrationEngine.Loaders;

/// <summary>
/// Converts WKT from staging column ({name}__wkt) into geography/geometry on {name}.
/// Supports legacy tables where {name} was NVARCHAR(MAX) from older migrations.
/// </summary>
public class SpatialPostLoader
{
    private const int DefaultBatchSize = 250;

    private readonly string _connectionString;

    public SpatialPostLoader(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task ConvertSpatialColumnsAsync(
        TableSchema table,
        IReadOnlyList<ColumnSchema> spatialColumns,
        MigrationConfig config,
        CancellationToken ct)
    {
        if (spatialColumns.Count == 0)
            return;

        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);

        var pkColumn = table.Constraints
            .FirstOrDefault(c => c.ConstraintType == "P")
            ?.Columns.FirstOrDefault();

        foreach (var column in spatialColumns)
        {
            await DropColumnIfExistsAsync(connection, table.TableName, $"{column.ColumnName}__geom", ct);

            var targetType = string.Equals(column.SpatialTargetType, "geography", StringComparison.OrdinalIgnoreCase)
                ? "geography"
                : "geometry";
            var wktColumn = SpatialColumnHelper.GetWktStagingColumnName(column);
            var targetColumn = column.ColumnName;

            var targetSqlType = await GetColumnSqlTypeAsync(connection, table.TableName, targetColumn, ct);
            if (targetSqlType == null)
            {
                Log.Warning("Spatial column [{Table}].[{Column}] not found — skipping conversion",
                    table.TableName, targetColumn);
                continue;
            }

            if (IsSpatialSqlType(targetSqlType))
            {
                var wktType = await GetColumnSqlTypeAsync(connection, table.TableName, wktColumn, ct);
                if (wktType == null || !SpatialColumnHelper.IsStringSqlType(wktType))
                {
                    Log.Information(
                        "Spatial column [{Table}].[{Column}] already {Type} — no WKT staging to convert",
                        table.TableName, targetColumn, targetSqlType);
                    continue;
                }

                await ConvertStagingToTargetAsync(
                    connection, table, wktColumn, targetColumn, pkColumn,
                    column, config, targetType, ct);

                if (!ShouldKeepWktStaging(table.TableName, column, config))
                    await DropColumnIfExistsAsync(connection, table.TableName, wktColumn, ct);

                await ApplyNotNullIfNeededAsync(connection, table, column, targetType, ct);
                continue;
            }

            if (SpatialColumnHelper.IsStringSqlType(targetSqlType))
            {
                Log.Information(
                    "Spatial column [{Table}].[{Column}] is legacy NVARCHAR staging — converting in-place",
                    table.TableName, targetColumn);
                await ConvertLegacyNvarcharColumnAsync(
                    connection, table, targetColumn, pkColumn, column, config, targetType, ct);
                continue;
            }

            Log.Warning(
                "Spatial column [{Table}].[{Column}] has unexpected type {Type} — skipping",
                table.TableName, targetColumn, targetSqlType);
        }
    }

    private async Task ConvertStagingToTargetAsync(
        SqlConnection connection,
        TableSchema table,
        string wktColumn,
        string targetColumn,
        string? pkColumn,
        ColumnSchema column,
        MigrationConfig config,
        string targetType,
        CancellationToken ct)
    {
        var sourceSrid = SpatialMetadataHelper.ResolveWktSrid(table, column, config);
        var targetSrid = SpatialMetadataHelper.ResolveTargetSrid(table, column, config);
        var needsTransform = sourceSrid != targetSrid;
        var tableName = table.TableName;

        Log.Information(
            "Converting [{Table}].[{Wkt}] → [{Target}] {TargetType} (EPSG:{Source} → EPSG:{Target}{Transform})",
            tableName, wktColumn, targetColumn, targetType, sourceSrid, targetSrid,
            needsTransform ? ", DotSpatial reproject" : "");

        var totalConverted = needsTransform
            ? await ConvertWktWithReprojectAsync(
                connection, tableName, wktColumn, targetColumn, pkColumn,
                targetType, sourceSrid, targetSrid, ct)
            : await ConvertWktInBatchesAsync(
                connection, tableName, wktColumn, targetColumn, pkColumn,
                targetType, targetSrid, ct);

        Log.Information(
            "Converted {Rows} spatial value(s) [{Table}].[{Wkt}] → [{Target}]",
            totalConverted, tableName, wktColumn, targetColumn);
    }

    private async Task ConvertLegacyNvarcharColumnAsync(
        SqlConnection connection,
        TableSchema table,
        string wktColumn,
        string? pkColumn,
        ColumnSchema column,
        MigrationConfig config,
        string targetType,
        CancellationToken ct)
    {
        var tableName = table.TableName;
        var sourceSrid = SpatialMetadataHelper.ResolveWktSrid(table, column, config);
        var targetSrid = SpatialMetadataHelper.ResolveTargetSrid(table, column, config);
        var tempColumn = $"{column.ColumnName}__geom";
        var needsTransform = sourceSrid != targetSrid;

        await DropColumnIfExistsAsync(connection, tableName, tempColumn, ct);
        await ExecuteDdlAsync(connection,
            $"ALTER TABLE [{tableName}] ADD [{tempColumn}] {targetType} NULL;", ct);

        var totalConverted = needsTransform
            ? await ConvertWktWithReprojectAsync(
                connection, tableName, wktColumn, tempColumn, pkColumn,
                targetType, sourceSrid, targetSrid, ct)
            : await ConvertWktInBatchesAsync(
                connection, tableName, wktColumn, tempColumn, pkColumn,
                targetType, targetSrid, ct);

        Log.Information(
            "Converted {Rows} legacy spatial value(s) in [{Table}].[{Column}]",
            totalConverted, tableName, wktColumn);

        await ExecuteDdlAsync(connection, $"ALTER TABLE [{tableName}] DROP COLUMN [{wktColumn}];", ct);
        await ExecuteDdlAsync(connection,
            $"EXEC sp_rename N'[{tableName}].[{tempColumn}]', N'{column.ColumnName}', 'COLUMN';", ct);

        if (!column.Nullable)
        {
            await ExecuteDdlAsync(connection,
                $"ALTER TABLE [{tableName}] ALTER COLUMN [{column.ColumnName}] {targetType} NOT NULL;", ct);
        }
    }

    private static async Task ApplyNotNullIfNeededAsync(
        SqlConnection connection,
        TableSchema table,
        ColumnSchema column,
        string targetType,
        CancellationToken ct)
    {
        if (column.Nullable)
            return;

        await ExecuteDdlAsync(connection,
            $"ALTER TABLE [{table.TableName}] ALTER COLUMN [{column.ColumnName}] {targetType} NOT NULL;", ct);
    }

    private static async Task DropColumnIfExistsAsync(
        SqlConnection connection,
        string tableName,
        string columnName,
        CancellationToken ct)
    {
        var ddl = $@"
            IF COL_LENGTH(@qualifiedTable, @column) IS NOT NULL
                ALTER TABLE [{tableName}] DROP COLUMN [{columnName}];";

        await using var cmd = new SqlCommand(ddl, connection) { CommandTimeout = 0 };
        cmd.Parameters.AddWithValue("@qualifiedTable", $"dbo.{tableName}");
        cmd.Parameters.AddWithValue("@column", columnName);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task<long> ConvertWktWithReprojectAsync(
        SqlConnection connection,
        string tableName,
        string wktColumn,
        string targetColumn,
        string? pkColumn,
        string targetType,
        int sourceSrid,
        int targetSrid,
        CancellationToken ct)
    {
        if (string.IsNullOrEmpty(pkColumn))
        {
            return await ConvertWktWithReprojectNoPkAsync(
                connection, tableName, wktColumn, targetColumn, targetType, sourceSrid, targetSrid, ct);
        }

        long total = 0;
        long failed = 0;
        var batchNum = 0;

        while (true)
        {
            ct.ThrowIfCancellationRequested();
            batchNum++;

            var selectSql = $@"
                SELECT TOP ({DefaultBatchSize}) [{pkColumn}], [{wktColumn}]
                FROM [{tableName}]
                WHERE [{wktColumn}] IS NOT NULL AND [{targetColumn}] IS NULL
                ORDER BY [{pkColumn}]";

            var rows = new List<(object Pk, string Wkt)>();
            await using (var selectCmd = new SqlCommand(selectSql, connection) { CommandTimeout = 0 })
            await using (var reader = await selectCmd.ExecuteReaderAsync(ct))
            {
                while (await reader.ReadAsync(ct))
                {
                    rows.Add((reader.GetValue(0), reader.GetString(1)));
                }
            }

            if (rows.Count == 0)
                break;

            foreach (var (pk, wkt) in rows)
            {
                try
                {
                    var transformed = WktCrsTransform.Transform(wkt, sourceSrid, targetSrid);
                    await UpdateSpatialRowAsync(
                        connection, tableName, wktColumn, targetColumn, pkColumn, pk,
                        transformed, targetType, targetSrid, ct);
                    total++;
                }
                catch (Exception ex)
                {
                    failed++;
                    Log.Warning(ex, "Spatial reproject failed [{Table}] PK={Pk}", tableName, pk);
                }
            }

            if (batchNum == 1 || batchNum % 10 == 0 || rows.Count < DefaultBatchSize)
            {
                Log.Information(
                    "Spatial reproject batch {Batch}: {Rows} row(s) → [{Table}].[{Column}] ({Total} ok, {Failed} failed)",
                    batchNum, rows.Count, tableName, targetColumn, total, failed);
            }
        }

        return total;
    }

    private static async Task<long> ConvertWktWithReprojectNoPkAsync(
        SqlConnection connection,
        string tableName,
        string wktColumn,
        string targetColumn,
        string targetType,
        int sourceSrid,
        int targetSrid,
        CancellationToken ct)
    {
        Log.Warning(
            "Spatial [{Table}].[{Column}]: no PK — row-by-row reproject (slow on large tables)",
            tableName, wktColumn);

        var sql = $"SELECT [{wktColumn}] FROM [{tableName}] WHERE [{wktColumn}] IS NOT NULL AND [{targetColumn}] IS NULL";

        long total = 0;
        await using var selectCmd = new SqlCommand(sql, connection) { CommandTimeout = 0 };
        await using var reader = await selectCmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var wkt = reader.GetString(0);
            try
            {
                var transformed = WktCrsTransform.Transform(wkt, sourceSrid, targetSrid);
                var updateSql = BuildSpatialUpdateSql(tableName, wktColumn, targetColumn, null, targetType);
                await using var updateCmd = new SqlCommand(updateSql, connection) { CommandTimeout = 0 };
                updateCmd.Parameters.AddWithValue("@wkt", transformed);
                updateCmd.Parameters.AddWithValue("@srid", targetSrid);
                updateCmd.Parameters.AddWithValue("@matchWkt", wkt);
                total += await updateCmd.ExecuteNonQueryAsync(ct);
            }
            catch (Exception ex)
            {
                Log.Warning(ex, "Spatial reproject failed [{Table}] (no PK)", tableName);
            }
        }

        return total;
    }

    private static async Task UpdateSpatialRowAsync(
        SqlConnection connection,
        string tableName,
        string wktColumn,
        string targetColumn,
        string pkColumn,
        object pk,
        string wkt,
        string targetType,
        int targetSrid,
        CancellationToken ct)
    {
        var updateSql = BuildSpatialUpdateSql(tableName, wktColumn, targetColumn, pkColumn, targetType);
        await using var cmd = new SqlCommand(updateSql, connection) { CommandTimeout = 0 };
        cmd.Parameters.AddWithValue("@wkt", wkt);
        cmd.Parameters.AddWithValue("@srid", targetSrid);
        cmd.Parameters.AddWithValue("@pk", pk);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static string BuildSpatialUpdateSql(
        string tableName,
        string wktColumn,
        string targetColumn,
        string? pkColumn,
        string targetType)
    {
        var geomExpr = targetType == "geography"
            ? "geography::STGeomFromText(@wkt, @srid)"
            : "geometry::STGeomFromText(@wkt, @srid).MakeValid()";

        if (!string.IsNullOrEmpty(pkColumn))
        {
            return $"""
                    UPDATE [{tableName}]
                    SET [{targetColumn}] = {geomExpr}
                    WHERE [{pkColumn}] = @pk;
                    """;
        }

        return $"""
                UPDATE [{tableName}]
                SET [{targetColumn}] = {geomExpr}
                WHERE [{wktColumn}] = @matchWkt AND [{targetColumn}] IS NULL;
                """;
    }

    private static async Task<long> ConvertWktInBatchesAsync(
        SqlConnection connection,
        string tableName,
        string wktColumn,
        string targetColumn,
        string? pkColumn,
        string targetType,
        int srid,
        CancellationToken ct)
    {
        if (string.IsNullOrEmpty(pkColumn))
        {
            return await ConvertWktSingleUpdateAsync(
                connection, tableName, wktColumn, targetColumn, targetType, srid, ct);
        }

        long total = 0;
        var batchNum = 0;
        while (true)
        {
            ct.ThrowIfCancellationRequested();
            batchNum++;

            var convertExpr = targetType == "geography"
                ? $"geography::STGeomFromText(t.[{wktColumn}], @srid)"
                : $"geometry::STGeomFromText(t.[{wktColumn}], @srid).MakeValid()";

            var sql = $@"
                ;WITH batch AS (
                    SELECT TOP ({DefaultBatchSize}) [{pkColumn}]
                    FROM [{tableName}]
                    WHERE [{wktColumn}] IS NOT NULL AND [{targetColumn}] IS NULL
                    ORDER BY [{pkColumn}]
                )
                UPDATE t
                SET [{targetColumn}] = {convertExpr}
                FROM [{tableName}] t
                INNER JOIN batch b ON t.[{pkColumn}] = b.[{pkColumn}]";

            await using var cmd = new SqlCommand(sql, connection) { CommandTimeout = 0 };
            cmd.Parameters.AddWithValue("@srid", srid);
            var updated = await cmd.ExecuteNonQueryAsync(ct);
            if (updated <= 0)
                break;

            total += updated;
            if (batchNum == 1 || batchNum % 10 == 0 || updated < DefaultBatchSize)
            {
                Log.Information(
                    "Spatial batch {Batch}: +{Rows} rows → [{Table}].[{Column}] ({Total} total)",
                    batchNum, updated, tableName, targetColumn, total);
            }
        }

        return total;
    }

    private static async Task<long> ConvertWktSingleUpdateAsync(
        SqlConnection connection,
        string tableName,
        string wktColumn,
        string targetColumn,
        string targetType,
        int srid,
        CancellationToken ct)
    {
        Log.Information(
            "Spatial [{Table}].[{Column}]: no PK — single UPDATE (may be slow on large tables)",
            tableName, wktColumn);

        var convertSql = targetType == "geography"
            ? $"""
               UPDATE [{tableName}]
               SET [{targetColumn}] = geography::STGeomFromText([{wktColumn}], @srid)
               WHERE [{wktColumn}] IS NOT NULL AND [{targetColumn}] IS NULL;
               """
            : $"""
               UPDATE [{tableName}]
               SET [{targetColumn}] = geometry::STGeomFromText([{wktColumn}], @srid).MakeValid()
               WHERE [{wktColumn}] IS NOT NULL AND [{targetColumn}] IS NULL;
               """;

        await using var cmd = new SqlCommand(convertSql, connection) { CommandTimeout = 0 };
        cmd.Parameters.AddWithValue("@srid", srid);
        return await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task<string?> GetColumnSqlTypeAsync(
        SqlConnection connection, string tableName, string columnName, CancellationToken ct)
    {
        const string sql = @"
            SELECT tp.name
            FROM sys.columns c
            JOIN sys.types tp ON c.user_type_id = tp.user_type_id
            WHERE c.object_id = OBJECT_ID(@table, 'U')
              AND c.name = @column";

        await using var cmd = new SqlCommand(sql, connection);
        cmd.Parameters.AddWithValue("@table", $"dbo.{tableName}");
        cmd.Parameters.AddWithValue("@column", columnName);
        var result = await cmd.ExecuteScalarAsync(ct);
        return result?.ToString();
    }

    private static bool IsSpatialSqlType(string typeName) =>
        string.Equals(typeName, "geometry", StringComparison.OrdinalIgnoreCase)
        || string.Equals(typeName, "geography", StringComparison.OrdinalIgnoreCase);

    private static bool ShouldKeepWktStaging(string tableName, ColumnSchema column, MigrationConfig config) =>
        config.KeepSpatialWktStagingColumns.Contains($"{tableName}.{column.ColumnName}");

    private static async Task ExecuteDdlAsync(SqlConnection connection, string ddl, CancellationToken ct)
    {
        await using var cmd = new SqlCommand(ddl, connection) { CommandTimeout = 0 };
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
