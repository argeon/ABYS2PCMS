using MigrationShared.Models;

namespace MigrationEngine.Schema;

public static class SpatialMetadataHelper
{
    public static void ApplySridOverrides(TableSchema table, MigrationConfig config)
    {
        foreach (var column in table.Columns.Where(SpatialColumnHelper.IsSpatialColumn))
        {
            column.IsSpatial = true;
            var key = $"{table.TableName}.{column.ColumnName}";

            if (!column.Srid.HasValue || column.Srid == 0)
            {
                if (config.SpatialSridOverrides.TryGetValue(key, out var sourceOverride) && sourceOverride > 0)
                    column.Srid = sourceOverride;
                else if (config.DefaultSpatialSourceSridWhenMissing.HasValue
                         && config.DefaultSpatialSourceSridWhenMissing.Value > 0)
                    column.Srid = config.DefaultSpatialSourceSridWhenMissing.Value;
            }

            column.SpatialTargetSrid = config.SpatialTargetSridOverrides.TryGetValue(key, out var targetOverride)
                ? targetOverride
                : 4326;
            column.SpatialTargetType = column.SpatialTargetSrid == 4326 ? "geography" : "geometry";
        }
    }

    public static bool UsesReconstructTransformInOracle(
        TableSchema table,
        ColumnSchema column,
        MigrationConfig config) =>
        config.SpatialReconstructAndTransformInOracle.Contains($"{table.TableName}.{column.ColumnName}");

    public static int ResolveSourceSrid(TableSchema table, ColumnSchema column, MigrationConfig config)
    {
        var key = $"{table.TableName}.{column.ColumnName}";
        if ((!column.Srid.HasValue || column.Srid == 0)
            && config.SpatialSridOverrides.TryGetValue(key, out var overrideSrid)
            && overrideSrid > 0)
        {
            return overrideSrid;
        }

        if (column.Srid.HasValue && column.Srid.Value > 0)
            return column.Srid.Value;

        if (config.DefaultSpatialSourceSridWhenMissing.HasValue
            && config.DefaultSpatialSourceSridWhenMissing.Value > 0)
            return config.DefaultSpatialSourceSridWhenMissing.Value;

        return 0;
    }

    /// <summary>WKT staging EPSG — after Oracle reconstruct+transform, WKT is already at target CRS.</summary>
    public static int ResolveWktSrid(TableSchema table, ColumnSchema column, MigrationConfig config)
    {
        if (UsesReconstructTransformInOracle(table, column, config))
            return ResolveTargetSrid(table, column, config);

        return ResolveSourceSrid(table, column, config);
    }

    public static int ResolveTargetSrid(TableSchema table, ColumnSchema column, MigrationConfig config)
    {
        if (column.SpatialTargetSrid.HasValue)
            return column.SpatialTargetSrid.Value;

        var key = $"{table.TableName}.{column.ColumnName}";
        if (config.SpatialTargetSridOverrides.TryGetValue(key, out var overrideSrid))
            return overrideSrid;

        return 4326;
    }

    [Obsolete("Use ResolveSourceSrid or ResolveTargetSrid")]
    public static int ResolveSrid(TableSchema table, ColumnSchema column, MigrationConfig config) =>
        ResolveSourceSrid(table, column, config);
}
