using System.Diagnostics;

namespace MigrationWeb.Services;

internal static class EngineLauncher
{
    public static string GetEngineDirectory(string contentRootPath) =>
        Path.GetFullPath(Path.Combine(contentRootPath, "..", "MigrationEngine"));

    public static (bool success, string output, string? error) Build(string engineDir)
    {
        var existingExe = FindBuiltExecutable(engineDir);
        var csproj = Path.Combine(engineDir, "MigrationEngine.csproj");

        // Published deployments ship MigrationEngine.exe without source — skip build.
        if (!File.Exists(csproj))
        {
            if (existingExe != null)
                return (true, $"Using existing executable (no project file): {existingExe}", null);

            return (false, string.Empty,
                $"MigrationEngine.csproj not found at: {csproj}. " +
                "Deploy the published MigrationEngine folder (with MigrationEngine.exe) next to the web app.");
        }

        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = $"build \"{csproj}\" -c Release",
            WorkingDirectory = engineDir,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        });

        if (process == null)
            return (false, string.Empty, "Failed to start dotnet build process.");

        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            // Build failed but a previously published exe may still be usable.
            var fallbackExe = existingExe ?? FindBuiltExecutable(engineDir);
            if (fallbackExe != null)
                return (true, stdout + Environment.NewLine + $"Build failed; using existing executable: {fallbackExe}", null);

            return (false, stdout, string.IsNullOrWhiteSpace(stderr) ? $"dotnet build exited with code {process.ExitCode}" : stderr);
        }

        return (true, stdout, null);
    }

    public static ProcessStartInfo CreateStartInfo(string engineDir, string engineArgument)
    {
        var configPath = Path.Combine(engineDir, "appsettings.json");
        if (!File.Exists(configPath))
            throw new FileNotFoundException("Configuration file not found. Configure migration via Wizard first.", configPath);

        var exePath = FindBuiltExecutable(engineDir);
        if (exePath != null)
        {
            var workingDir = Path.GetDirectoryName(exePath)!;
            SyncAppSettings(engineDir, workingDir);

            return new ProcessStartInfo
            {
                FileName = exePath,
                Arguments = engineArgument,
                WorkingDirectory = workingDir,
                UseShellExecute = false,
                CreateNoWindow = false
            };
        }

        var csproj = Path.Combine(engineDir, "MigrationEngine.csproj");
        if (!File.Exists(csproj))
            throw new FileNotFoundException("MigrationEngine executable or project file not found.", csproj);

        return new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = $"run --project \"{csproj}\" -c Release -- {engineArgument}",
            WorkingDirectory = engineDir,
            UseShellExecute = false,
            CreateNoWindow = false
        };
    }

    public static string? FindBuiltExecutable(string engineDir)
    {
        string? newest = null;
        DateTime newestTime = DateTime.MinValue;

        foreach (var candidate in GetExeCandidates(engineDir))
        {
            if (!File.Exists(candidate))
                continue;

            var writeTime = File.GetLastWriteTimeUtc(candidate);
            if (writeTime > newestTime)
            {
                newestTime = writeTime;
                newest = candidate;
            }
        }

        return newest;
    }

    private static IEnumerable<string> GetExeCandidates(string engineDir)
    {
        yield return Path.Combine(engineDir, "MigrationEngine.exe");

        foreach (var config in new[] { "Release", "Debug" })
        {
            yield return Path.Combine(engineDir, "bin", config, "net8.0", "MigrationEngine.exe");
            yield return Path.Combine(engineDir, "bin", config, "net8.0", "win-x64", "MigrationEngine.exe");
            yield return Path.Combine(engineDir, "bin", config, "net8.0", "publish", "win-x64", "MigrationEngine.exe");
        }
    }

    private static void SyncAppSettings(string engineDir, string outputDir)
    {
        if (string.Equals(Path.GetFullPath(engineDir), Path.GetFullPath(outputDir), StringComparison.OrdinalIgnoreCase))
            return;

        var source = Path.Combine(engineDir, "appsettings.json");
        if (!File.Exists(source))
            return;

        File.Copy(source, Path.Combine(outputDir, "appsettings.json"), overwrite: true);
    }
}
