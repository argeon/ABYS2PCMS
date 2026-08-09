using System.Reflection;

namespace MigrationShared;

/// <summary>
/// Microsoft.Data.SqlClient loads geography/geometry UDTs via
/// Microsoft.SqlServer.Types Version=10.0.0.0. Modern NuGet ships 16+/17+ —
/// redirect so GetValue() on spatial columns does not FileNotFound.
/// </summary>
public static class SqlServerTypesBootstrap
{
    private static int _registered;

    public static void Ensure()
    {
        if (Interlocked.Exchange(ref _registered, 1) != 0)
            return;

        AppDomain.CurrentDomain.AssemblyResolve += Resolve;

        // Force-load the modern assembly into the default context.
        _ = typeof(Microsoft.SqlServer.Types.SqlGeography).Assembly;
    }

    private static Assembly? Resolve(object? sender, ResolveEventArgs args)
    {
        var requested = new AssemblyName(args.Name);
        if (!string.Equals(requested.Name, "Microsoft.SqlServer.Types", StringComparison.OrdinalIgnoreCase))
            return null;

        return typeof(Microsoft.SqlServer.Types.SqlGeography).Assembly;
    }
}
