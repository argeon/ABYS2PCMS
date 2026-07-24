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

    public static string Transform(string wkt, int sourceEpsg, int targetEpsg)
    {
        if (string.IsNullOrWhiteSpace(wkt))
            return wkt;

        if (sourceEpsg == targetEpsg)
            return wkt;

        var projections = ProjectionCache.GetOrAdd((sourceEpsg, targetEpsg), key =>
        {
            var from = ProjectionInfo.FromEpsgCode(key.From)
                       ?? throw new InvalidOperationException($"EPSG:{key.From} is not supported by DotSpatial.Projections.");
            var to = ProjectionInfo.FromEpsgCode(key.To)
                     ?? throw new InvalidOperationException($"EPSG:{key.To} is not supported by DotSpatial.Projections.");
            return [from, to];
        });

        var geometry = WktReader.Read(wkt);
        ReprojectGeometry(geometry, projections[0], projections[1]);
        return WktWriter.Write(geometry);
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
