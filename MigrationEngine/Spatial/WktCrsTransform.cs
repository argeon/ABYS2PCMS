using System.Collections.Concurrent;
using DotSpatial.Projections;
using NetTopologySuite.Geometries;
using NetTopologySuite.IO;

namespace MigrationEngine.Spatial;

/// <summary>
/// Reprojects WKT between EPSG codes using DotSpatial.Projections (NuGet).
/// </summary>
public static class WktCrsTransform
{
    private static readonly ConcurrentDictionary<(int From, int To), ProjectionInfo[]> ProjectionCache = new();
    private static readonly WKTReader WktReader = new();
    private static readonly WKTWriter WktWriter = new();

    /// <summary>Proj4 definitions for EPSG codes missing/broken in DotSpatial authority DB.</summary>
    private static readonly Dictionary<int, string> Proj4Fallbacks = new()
    {
        // Web Mercator (Google/OSM) — also covers unofficial 900913
        [3857] = "+proj=merc +a=6378137 +b=6378137 +lat_ts=0 +lon_0=0 +x_0=0 +y_0=0 +k=1 +units=m +nadgrids=@null +wktext +no_defs",
        [900913] = "+proj=merc +a=6378137 +b=6378137 +lat_ts=0 +lon_0=0 +x_0=0 +y_0=0 +k=1 +units=m +nadgrids=@null +wktext +no_defs",
        [4326] = "+proj=longlat +datum=WGS84 +no_defs",
    };

    public static string Transform(string wkt, int sourceEpsg, int targetEpsg)
    {
        if (string.IsNullOrWhiteSpace(wkt))
            return wkt;

        if (sourceEpsg == targetEpsg)
            return wkt;

        var projections = ProjectionCache.GetOrAdd((sourceEpsg, targetEpsg), key =>
        {
            var from = ResolveProjection(key.From);
            var to = ResolveProjection(key.To);
            return [from, to];
        });

        var geometry = WktReader.Read(wkt);
        ReprojectGeometry(geometry, projections[0], projections[1]);
        return WktWriter.Write(geometry);
    }

    /// <summary>Eagerly validate that both EPSG codes resolve (fail once before row loop).</summary>
    public static void EnsureProjectionsAvailable(int sourceEpsg, int targetEpsg)
    {
        if (sourceEpsg == targetEpsg)
            return;
        _ = ProjectionCache.GetOrAdd((sourceEpsg, targetEpsg), key =>
        {
            var from = ResolveProjection(key.From);
            var to = ResolveProjection(key.To);
            return [from, to];
        });
    }

    private static ProjectionInfo ResolveProjection(int epsg)
    {
        if (epsg <= 0)
        {
            throw new InvalidOperationException(
                $"Invalid EPSG:{epsg}. Oracle SRID is missing — set Migration:SpatialSridOverrides " +
                "(\"TABLE.COLUMN\": 3857) or Migration:DefaultSpatialSourceSridWhenMissing.");
        }

        try
        {
            var fromEpsg = ProjectionInfo.FromEpsgCode(epsg);
            if (fromEpsg != null)
                return fromEpsg;
        }
        catch (ArgumentOutOfRangeException)
        {
            // fall through to Proj4
        }

        if (Proj4Fallbacks.TryGetValue(epsg, out var proj4))
            return ProjectionInfo.FromProj4String(proj4);

        throw new InvalidOperationException(
            $"EPSG:{epsg} is not supported by DotSpatial.Projections. " +
            "Add a SpatialSridOverrides entry or a Proj4 fallback in WktCrsTransform.");
    }

    private static void ReprojectGeometry(Geometry geometry, ProjectionInfo source, ProjectionInfo target)
    {
        var coords = geometry.Coordinates;
        if (coords.Length == 0)
            return;

        var xy = new double[coords.Length * 2];
        var z = new double[coords.Length];
        for (var i = 0; i < coords.Length; i++)
        {
            xy[i * 2] = coords[i].X;
            xy[i * 2 + 1] = coords[i].Y;
            z[i] = double.IsNaN(coords[i].Z) ? 0 : coords[i].Z;
        }

        Reproject.ReprojectPoints(xy, z, source, target, 0, coords.Length);

        for (var i = 0; i < coords.Length; i++)
        {
            coords[i].X = xy[i * 2];
            coords[i].Y = xy[i * 2 + 1];
        }

        geometry.GeometryChanged();
    }
}
