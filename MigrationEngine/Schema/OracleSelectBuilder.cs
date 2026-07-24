using MigrationShared.Models;

namespace MigrationEngine.Schema;

public record OracleColumnSelect(string Alias, string SelectExpression);

public static class OracleSelectBuilder
{
    public static IReadOnlyList<OracleColumnSelect> BuildSelectList(
        IReadOnlyList<ColumnSchema> columns,
        MigrationConfig? config = null,
        string? tableName = null,
        string? oracleSchema = null,
        string tableAlias = "t")
    {
        var transformInOracle = config?.TransformSpatialInOracle ?? false;
        var useAlias = !string.IsNullOrWhiteSpace(tableAlias);

        return columns
            .OrderBy(c => c.ColumnId)
            .Select(c =>
            {
                // Extra columns filled after load are omitted from partition SELECT (NULL on insert).
                if (c.IsExtraColumn && c.FillAfterLoad)
                    return (OracleColumnSelect?)null;

                var quoted = QuoteOracleIdentifier(c.ColumnName);
                var qualified = QualifyColumn(tableAlias, quoted, useAlias);

                if (c.IsExtraColumn && !string.IsNullOrWhiteSpace(c.OracleSelectExpression))
                    return new OracleColumnSelect(c.ColumnName, c.OracleSelectExpression);

                if (SpatialColumnHelper.IsSpatialColumn(c))
                {
                    var key = tableName != null
                        ? $"{tableName}.{c.ColumnName}"
                        : c.ColumnName;
                    var targetSrid = c.SpatialTargetSrid ?? c.Srid ?? 4326;
                    var sourceSrid = c.Srid ?? 4326;

                    if (config != null
                        && tableName != null
                        && config.SpatialReconstructAndTransformInOracle.Contains(key))
                    {
                        if (config.SpatialSridOverrides.TryGetValue(key, out var forcedSourceSrid))
                            sourceSrid = forcedSourceSrid;

                        if (config.SpatialTargetSridOverrides.TryGetValue(key, out var forcedTargetSrid))
                            targetSrid = forcedTargetSrid;

                        var wktExpr = BuildReconstructTransformWktExpression(
                            qualified, sourceSrid, targetSrid, oracleSchema);
                        return new OracleColumnSelect(c.ColumnName, wktExpr);
                    }

                    var defaultWktExpr = BuildSpatialWktExpression(qualified, targetSrid, transformInOracle);
                    return new OracleColumnSelect(c.ColumnName, defaultWktExpr);
                }

                if (string.Equals(c.DataType, "XMLTYPE", StringComparison.OrdinalIgnoreCase))
                {
                    var xmlExpr = $"CASE WHEN {qualified} IS NULL THEN NULL ELSE {qualified}.GETCLOBVAL() END";
                    return new OracleColumnSelect(c.ColumnName, xmlExpr);
                }

                return new OracleColumnSelect(c.ColumnName, qualified);
            })
            .Where(c => c is not null)
            .Select(c => c!)
            .ToList();
    }

    private static string QualifyColumn(string tableAlias, string quotedColumn, bool useAlias) =>
        useAlias ? $"{tableAlias}.{quotedColumn}" : quotedColumn;

    /// <summary>
    /// SMS.CS_READING_PLAN LOCATION: SDO_GEOMETRY(3857) → SDO_CS.TRANSFORM(4326) → GIS_TO_WKTGEOMETRY.
    /// Table alias (t.LOCATION) required — bare LOCATION.SDO_ORDINATES raises ORA-00904 in Oracle SQL.
    /// </summary>
    private static string BuildReconstructTransformWktExpression(
        string qualifiedColumn,
        int forcedSourceSrid,
        int targetSrid,
        string? oracleSchema)
    {
        var locFixed =
            $"SDO_GEOMETRY({qualifiedColumn}.SDO_GTYPE, {forcedSourceSrid}, {qualifiedColumn}.SDO_POINT, " +
            $"{qualifiedColumn}.SDO_ELEM_INFO, {qualifiedColumn}.SDO_ORDINATES)";
        var schemaPrefix = string.IsNullOrWhiteSpace(oracleSchema)
            ? string.Empty
            : $"{QuoteOracleIdentifier(oracleSchema)}.";
        return
            $"CASE WHEN {qualifiedColumn} IS NULL THEN NULL " +
            $"ELSE {schemaPrefix}GIS_TO_WKTGEOMETRY(SDO_CS.TRANSFORM({locFixed}, {targetSrid})) END";
    }

    private static string BuildSpatialWktExpression(string quoted, int targetSrid, bool transformInOracle)
    {
        // Return raw WKT (VARCHAR2 or CLOB). SafeDataReaderWrapper + InitialLOBFetchSize read large CLOBs in C#.
        // Avoid TO_CHAR / SUBSTR in SQL — ORA-22835 when WKT exceeds 4000 chars.
        var wktFromGeom = (string geom) => $"SDO_UTIL.TO_WKTGEOMETRY({geom})";

        if (!transformInOracle)
        {
            return $"CASE WHEN {quoted} IS NULL THEN NULL ELSE {wktFromGeom(quoted)} END";
        }

        var geomExpr =
            $"CASE WHEN {quoted} IS NULL THEN NULL " +
            $"WHEN {quoted}.SDO_SRID IS NOT NULL AND {quoted}.SDO_SRID <> {targetSrid} " +
            $"THEN SDO_CS.TRANSFORM({quoted}, {targetSrid}) ELSE {quoted} END";

        return $"CASE WHEN {quoted} IS NULL THEN NULL ELSE {wktFromGeom(geomExpr)} END";
    }

    private static string QuoteOracleIdentifier(string name)
    {
        if (string.IsNullOrEmpty(name))
            return name;

        if (name.All(c => char.IsLetterOrDigit(c) || c == '_' || c == '$' || c == '#'))
            return name.ToUpperInvariant();

        return $"\"{name.Replace("\"", "\"\"", StringComparison.Ordinal)}\"";
    }
}
