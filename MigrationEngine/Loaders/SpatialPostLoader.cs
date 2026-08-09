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

        if (needsTransform && sourceSrid <= 0)
        {
            var nulled = await NullOutPendingWktAsync(connection, tableName, wktColumn, targetColumn, null, null, ct);
            Log.Warning(
                "Spatial [{Table}].[{Column}]: source EPSG:{Source} invalid — {Count} WKT value(s) set to NULL (target stays NULL)",
                tableName, targetColumn, sourceSrid, nulled);
            return;
        }

        if (needsTransform)
        {
            try
            {
                WktCrsTransform.EnsureProjectionsAvailable(sourceSrid, targetSrid);
            }
            catch (Exception ex)
            {
                var nulled = await NullOutPendingWktAsync(connection, tableName, wktColumn, targetColumn, null, null, ct);
                Log.Warning(ex,
                    "Spatial [{Table}].[{Column}]: CRS EPSG:{Source}→EPSG:{Target} unavailable — {Count} WKT value(s) set to NULL",
                    tableName, targetColumn, sourceSrid, targetSrid, nulled);
                return;
            }
        }

        // Web Mercator → WGS84 geography: set-based T-SQL (millions of POINT rows).
        var useSqlWebMercator =
            needsTransform
            && sourceSrid == 3857
            && targetSrid == 4326
            && string.Equals(targetType, "geography", StringComparison.OrdinalIgnoreCase)
            && !string.IsNullOrEmpty(pkColumn);

        Log.Information(
            "Converting [{Table}].[{Wkt}] → [{Target}] {TargetType} (EPSG:{Source} → EPSG:{Target}{Transform})",
            tableName, wktColumn, targetColumn, targetType, sourceSrid, targetSrid,
            useSqlWebMercator ? ", SQL WebMercator→WGS84" : needsTransform ? ", DotSpatial reproject" : "");

        long totalConverted;
        if (useSqlWebMercator)
        {
            totalConverted = await ConvertWebMercatorPointWktToGeographyAsync(
                connection, tableName, wktColumn, targetColumn, pkColumn!, ct);
        }
        else if (needsTransform)
        {
            totalConverted = await ConvertWktWithReprojectAsync(
                connection, tableName, wktColumn, targetColumn, pkColumn,
                targetType, sourceSrid, targetSrid, ct);
        }
        else
        {
            totalConverted = await ConvertWktInBatchesAsync(
                connection, tableName, wktColumn, targetColumn, pkColumn,
                targetType, targetSrid, ct);
        }

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

    /// <summary>
    /// EPSG:3857 POINT WKT → geography 4326 via T-SQL (no DotSpatial per-row).
    /// Non-POINT / unparsable WKT is nulled (target stays NULL).
    /// </summary>
    private static async Task<long> ConvertWebMercatorPointWktToGeographyAsync(
        SqlConnection connection,
        string tableName,
        string wktColumn,
        string targetColumn,
        string pkColumn,
        CancellationToken ct)
    {
        const int batchSize = 5000;
        long total = 0;
        long nulled = 0;
        var batchNum = 0;

        // Null non-POINT staging first (cannot use this fast path).
        var nullNonPointSql = $"""
            UPDATE [{tableName}]
            SET [{wktColumn}] = NULL
            WHERE [{wktColumn}] IS NOT NULL
              AND [{targetColumn}] IS NULL
              AND [{wktColumn}] NOT LIKE N'POINT (%'
              AND [{wktColumn}] NOT LIKE N'POINT(%';
            """;
        await using (var nullCmd = new SqlCommand(nullNonPointSql, connection) { CommandTimeout = 0 })
        {
            var n = await nullCmd.ExecuteNonQueryAsync(ct);
            if (n > 0)
            {
                nulled += n;
                Log.Warning(
                    "Spatial [{Table}].[{Column}]: {Count} non-POINT WKT set to NULL (SQL 3857→4326 path)",
                    tableName, targetColumn, n);
            }
        }

        while (true)
        {
            ct.ThrowIfCancellationRequested();
            batchNum++;

            // Parse "POINT (x y)" / "POINT(x y)", convert WebMercator → WGS84, write geography.
            var sql = $"""
                ;WITH batch AS (
                    SELECT TOP ({batchSize})
                        [{pkColumn}] AS pk,
                        [{wktColumn}] AS wkt
                    FROM [{tableName}]
                    WHERE [{wktColumn}] IS NOT NULL
                      AND [{targetColumn}] IS NULL
                      AND ([{wktColumn}] LIKE N'POINT (%' OR [{wktColumn}] LIKE N'POINT(%')
                    ORDER BY [{pkColumn}]
                ),
                body AS (
                    SELECT
                        pk,
                        REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(wkt)), N'POINT (', N''), N'POINT(', N''), N')', N''), N'  ', N' ') AS xy
                    FROM batch
                ),
                xy AS (
                    SELECT
                        pk,
                        TRY_CAST(LEFT(xy, CHARINDEX(N' ', xy + N' ') - 1) AS float) AS x,
                        TRY_CAST(SUBSTRING(xy, CHARINDEX(N' ', xy + N' ') + 1, 100) AS float) AS y
                    FROM body
                    WHERE CHARINDEX(N' ', xy) > 0
                ),
                ll AS (
                    SELECT
                        pk,
                        x,
                        y,
                        x / 6378137.0 * 180.0 / PI() AS lon,
                        (ATAN(EXP(y / 6378137.0)) * 2.0 - PI() / 2.0) * 180.0 / PI() AS lat
                    FROM xy
                    WHERE x IS NOT NULL AND y IS NOT NULL
                )
                UPDATE t
                SET [{targetColumn}] = geography::Point(ll.lat, ll.lon, 4326)
                FROM [{tableName}] t
                INNER JOIN ll ON t.[{pkColumn}] = ll.pk
                WHERE ll.lat BETWEEN -90.0 AND 90.0
                  AND ll.lon BETWEEN -180.0 AND 180.0
                  AND t.[{targetColumn}] IS NULL;
                """;

            await using var cmd = new SqlCommand(sql, connection) { CommandTimeout = 0 };
            var updated = await cmd.ExecuteNonQueryAsync(ct);
            if (updated <= 0)
            {
                // Remaining pending POINT rows that failed parse / out of range → null WKT
                var nullBadSql = $"""
                    UPDATE [{tableName}]
                    SET [{wktColumn}] = NULL
                    WHERE [{wktColumn}] IS NOT NULL AND [{targetColumn}] IS NULL;
                    """;
                await using var badCmd = new SqlCommand(nullBadSql, connection) { CommandTimeout = 0 };
                var bad = await badCmd.ExecuteNonQueryAsync(ct);
                if (bad > 0)
                {
                    nulled += bad;
                    Log.Warning(
                        "Spatial [{Table}].[{Column}]: {Count} unconvertible WKT set to NULL after SQL 3857→4326",
                        tableName, targetColumn, bad);
                }
                break;
            }

            total += updated;
            if (batchNum == 1 || batchNum % 20 == 0 || updated < batchSize)
            {
                Log.Information(
                    "Spatial SQL 3857→4326 batch {Batch}: +{Rows} → [{Table}].[{Column}] ({Total} total)",
                    batchNum, updated, tableName, targetColumn, total);
            }
        }

        if (nulled > 0)
        {
            Log.Warning(
                "Spatial [{Table}].[{Column}]: SQL path finished — {Total} converted, {Nulled} WKT nulled",
                tableName, targetColumn, total, nulled);
        }

        return total;
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
        long nulled = 0;
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
                catch (InvalidOperationException ex) when (ex.Message.Contains("EPSG", StringComparison.OrdinalIgnoreCase))
                {
                    // CRS broken for whole column — null remaining WKT and stop.
                    var bulk = await NullOutPendingWktAsync(
                        connection, tableName, wktColumn, targetColumn, null, null, ct);
                    nulled += bulk;
                    Log.Warning(ex,
                        "Spatial reproject CRS failed [{Table}] — {Count} pending WKT set to NULL (EPSG:{Source}→{Target})",
                        tableName, bulk, sourceSrid, targetSrid);
                    return total;
                }
                catch (Exception ex)
                {
                    // Bad geometry / transform — accept row with NULL spatial + clear staging WKT.
                    await NullOutPendingWktAsync(
                        connection, tableName, wktColumn, targetColumn, pkColumn, pk, ct);
                    nulled++;
                    if (nulled <= 20 || nulled % 500 == 0)
                    {
                        Log.Warning(ex,
                            "Spatial reproject failed [{Table}] PK={Pk} — WKT set to NULL ({Nulled} so far)",
                            tableName, pk, nulled);
                    }
                }
            }

            if (batchNum == 1 || batchNum % 10 == 0 || rows.Count < DefaultBatchSize)
            {
                Log.Information(
                    "Spatial reproject batch {Batch}: {Rows} row(s) → [{Table}].[{Column}] ({Total} ok, {Nulled} null)",
                    batchNum, rows.Count, tableName, targetColumn, total, nulled);
            }
        }

        if (nulled > 0)
        {
            Log.Warning(
                "Spatial [{Table}].[{Column}]: {Nulled} WKT value(s) nulled after reproject failure; {Total} converted",
                tableName, targetColumn, nulled, total);
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
        long nulled = 0;
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
                await NullOutPendingWktAsync(
                    connection, tableName, wktColumn, targetColumn, null, wkt, ct);
                nulled++;
                if (nulled <= 20 || nulled % 500 == 0)
                    Log.Warning(ex, "Spatial reproject failed [{Table}] (no PK) — WKT set to NULL ({Nulled})", tableName, nulled);
            }
        }

        return total;
    }

    /// <summary>
    /// Clears staging WKT (and leaves target NULL) when reproject/CRS conversion cannot succeed.
    /// When <paramref name="pkColumn"/> + <paramref name="pkOrMatchWkt"/> are set, only that row is cleared.
    /// When both null, all pending rows (wkt NOT NULL, target NULL) are cleared.
    /// When pkColumn is null but pkOrMatchWkt is a string, match by WKT text.
    /// </summary>
    private static async Task<long> NullOutPendingWktAsync(
        SqlConnection connection,
        string tableName,
        string wktColumn,
        string targetColumn,
        string? pkColumn,
        object? pkOrMatchWkt,
        CancellationToken ct)
    {
        string sql;
        await using var cmd = new SqlCommand { Connection = connection, CommandTimeout = 0 };

        if (!string.IsNullOrEmpty(pkColumn) && pkOrMatchWkt != null)
        {
            sql = $"""
                UPDATE [{tableName}]
                SET [{wktColumn}] = NULL, [{targetColumn}] = NULL
                WHERE [{pkColumn}] = @pk;
                """;
            cmd.Parameters.AddWithValue("@pk", pkOrMatchWkt);
        }
        else if (pkOrMatchWkt is string matchWkt)
        {
            sql = $"""
                UPDATE [{tableName}]
                SET [{wktColumn}] = NULL, [{targetColumn}] = NULL
                WHERE [{wktColumn}] = @matchWkt AND [{targetColumn}] IS NULL;
                """;
            cmd.Parameters.AddWithValue("@matchWkt", matchWkt);
        }
        else
        {
            sql = $"""
                UPDATE [{tableName}]
                SET [{wktColumn}] = NULL
                WHERE [{wktColumn}] IS NOT NULL AND [{targetColumn}] IS NULL;
                """;
        }

        cmd.CommandText = sql;
        return await cmd.ExecuteNonQueryAsync(ct);
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
