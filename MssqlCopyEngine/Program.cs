using MigrationEngine.Checkpoint;
using MigrationShared;
using MigrationShared.Enums;
using MigrationShared.Models;
using Microsoft.Extensions.Configuration;
using MssqlCopyEngine.Loaders;
using MssqlCopyEngine.Schema;
using Serilog;
using System.Collections.Concurrent;
using System.Diagnostics;

SqlServerTypesBootstrap.Ensure();

static string ResolveCheckpointSqlitePath(string? sqliteFromConfig)
{
    var raw = string.IsNullOrWhiteSpace(sqliteFromConfig) ? "mssql_copy_checkpoint.db" : sqliteFromConfig.Trim();
    if (Path.IsPathRooted(raw))
        return Path.GetFullPath(raw);

    for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
    {
        if (File.Exists(Path.Combine(dir.FullName, "MssqlCopyEngine.csproj")))
            return Path.GetFullPath(Path.Combine(dir.FullName, Path.GetFileName(raw)));
    }

    var exeDir = Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory;
    return Path.GetFullPath(Path.Combine(exeDir, Path.GetFileName(raw)));
}

static string ResolveAppSettingsPath()
{
    // Prefer project-folder appsettings (wizard writes here), then cwd, then exe dir
    for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
    {
        var candidate = Path.Combine(dir.FullName, "appsettings.json");
        if (File.Exists(Path.Combine(dir.FullName, "MssqlCopyEngine.csproj")) && File.Exists(candidate))
            return candidate;
    }

    var cwd = Path.Combine(Directory.GetCurrentDirectory(), "appsettings.json");
    if (File.Exists(cwd))
        return cwd;

    return Path.Combine(AppContext.BaseDirectory, "appsettings.json");
}

var appsettingsPath = ResolveAppSettingsPath();
var config = new ConfigurationBuilder()
    .SetBasePath(Path.GetDirectoryName(appsettingsPath)!)
    .AddJsonFile(Path.GetFileName(appsettingsPath), optional: false)
    .Build();

var exeDirForLog = Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory;
var logPath = Path.Combine(exeDirForLog, "logs", "mssql-copy-.log");
Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .WriteTo.Console()
    .WriteTo.File(logPath, rollingInterval: Serilog.RollingInterval.Day)
    .CreateLogger();

CheckpointRepository? checkpoint = null;
var runId = 0;

try
{
    Log.Information("=== MSSQL → MSSQL Copy Engine ===");
    Log.Information("Using appsettings: {Path}", appsettingsPath);

    var migrationConfig = new MigrationConfig();
    config.GetSection("Migration").Bind(migrationConfig);
    if (string.IsNullOrWhiteSpace(config["Migration:AutoStart"]))
        migrationConfig.AutoStart = false;

    var sourceCs = migrationConfig.OracleConnectionString;
    var targetCs = migrationConfig.MssqlConnectionString;
    var schema = string.IsNullOrWhiteSpace(migrationConfig.OracleSchema) ? "dbo" : migrationConfig.OracleSchema.Trim();

    var argv = Environment.GetCommandLineArgs().Skip(1).ToList();
    var forceRun = argv.Any(a => string.Equals(a, "--run", StringComparison.OrdinalIgnoreCase)
        || string.Equals(a, "-y", StringComparison.OrdinalIgnoreCase));
    var forceResume = argv.Any(a => string.Equals(a, "--resume", StringComparison.OrdinalIgnoreCase));

    if (!migrationConfig.AutoStart && !forceRun && !forceResume)
    {
        Log.Information("AutoStart is false; idle. Use: dotnet run -- --run | --resume");
        return 0;
    }

    var checkpointPath = ResolveCheckpointSqlitePath(config["Checkpoint:SqlitePath"]);
    Log.Information("Checkpoint path: {Path}", checkpointPath);

    checkpoint = new CheckpointRepository(checkpointPath);

    var isResume = false;
    if (forceResume)
    {
        var incomplete = checkpoint.FindLastIncompleteRun();
        if (incomplete.HasValue)
        {
            runId = incomplete.Value.runId;
            isResume = true;
            checkpoint.ResetInterruptedPartitions(runId);
            if (incomplete.Value.config != null
                && !string.IsNullOrWhiteSpace(incomplete.Value.config.OracleConnectionString)
                && !string.IsNullOrWhiteSpace(incomplete.Value.config.MssqlConnectionString))
            {
                migrationConfig = incomplete.Value.config;
                sourceCs = migrationConfig.OracleConnectionString;
                targetCs = migrationConfig.MssqlConnectionString;
                schema = string.IsNullOrWhiteSpace(migrationConfig.OracleSchema) ? "dbo" : migrationConfig.OracleSchema.Trim();
            }
            Log.Information("RESUME mode: Run #{RunId}", runId);
        }
        else
        {
            Log.Warning("--resume requested but no incomplete run found. Starting fresh.");
        }
    }

    if (string.IsNullOrWhiteSpace(sourceCs) || string.IsNullOrWhiteSpace(targetCs))
    {
        Log.Fatal("Missing source/target connection strings. Configure via MSSQL Copy Wizard.");
        return 1;
    }

    if (migrationConfig.Tables == null || migrationConfig.Tables.Count == 0)
    {
        Log.Fatal("No tables selected.");
        return 1;
    }

    if (!isResume)
        runId = checkpoint.CreateNewRun(migrationConfig);

    var cts = new CancellationTokenSource();
    Console.CancelKeyPress += (_, e) =>
    {
        e.Cancel = true;
        cts.Cancel();
    };
    var ct = cts.Token;

    var reader = new MssqlSchemaReader(sourceCs, schema);
    var ddlGen = new MssqlDdlGenerator();
    var loader = new MssqlBulkCopyLoader(targetCs, migrationConfig.BatchSize);

    Log.Information("Reading source schema {Schema} for {Count} tables", schema, migrationConfig.Tables.Count);
    var tables = await reader.ReadTablesAsync(migrationConfig.Tables, ct);
    if (tables.Count == 0)
    {
        Log.Fatal("No source tables resolved.");
        checkpoint.UpdateRunStatus(runId, "FAILED");
        return 1;
    }

    await MssqlBulkCopyLoader.EnsureSchemaAsync(targetCs, schema, ct);

    var dop = migrationConfig.DegreeOfParallelism <= 0
        ? 8
        : Math.Clamp(migrationConfig.DegreeOfParallelism, 1, 64);
    var viewCount = tables.Count(t => t.IsView);
    Log.Information(
        "DegreeOfParallelism={Dop}, BatchSize={Batch}, Objects={Count} (views={Views})",
        dop, migrationConfig.BatchSize, tables.Count, viewCount);
    foreach (var v in tables.Where(t => t.IsView))
    {
        Log.Information(
            "Will MATERIALIZE view {Schema}.{View} → target TABLE (base: {Bases})",
            v.SchemaName, v.TableName,
            v.BaseTables.Count == 0 ? "?" : string.Join(", ", v.BaseTables));
    }

    // Pre-create all partition checkpoints so UI shows every table immediately
    foreach (var table in tables)
        checkpoint.GetOrCreatePartitionCheckpoint(runId, table.TableName, "FULL", table.EstimatedRows);

    var errors = new ConcurrentBag<string>();
    var sw = Stopwatch.StartNew();

    await Parallel.ForEachAsync(
        tables,
        new ParallelOptions { MaxDegreeOfParallelism = dop, CancellationToken = ct },
        async (table, token) =>
        {
            try
            {
                await CopyOneTableAsync(
                    table, migrationConfig, sourceCs, targetCs, schema,
                    ddlGen, loader, checkpoint, runId, isResume, token);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex)
            {
                errors.Add($"{table.TableName}: {ex.Message}");
                Log.Error(ex, "Failed copying {Table}", table.TableName);
            }
        });

    sw.Stop();

    if (errors.Count > 0)
    {
        checkpoint.UpdateRunStatus(runId, "FAILED");
        Log.Error("Completed with {Count} errors in {Elapsed}", errors.Count, sw.Elapsed);
        foreach (var err in errors)
            Log.Error("  {Error}", err);
        return 1;
    }

    checkpoint.UpdateRunStatus(runId, "COMPLETED");
    Log.Information("All tables copied successfully in {Elapsed}", sw.Elapsed);
    return 0;
}
catch (Exception ex)
{
    Log.Fatal(ex, "Unhandled engine failure");
    try
    {
        if (checkpoint != null && runId > 0)
            checkpoint.UpdateRunStatus(runId, "FAILED");
    }
    catch { /* ignore */ }
    return 1;
}
finally
{
    checkpoint?.Dispose();
    await Log.CloseAndFlushAsync();
}

static async Task CopyOneTableAsync(
    MssqlTableSchema table,
    MigrationConfig cfg,
    string sourceCs,
    string targetCs,
    string schema,
    MssqlDdlGenerator ddlGen,
    MssqlBulkCopyLoader loader,
    CheckpointRepository checkpoint,
    int runId,
    bool isResumeRun,
    CancellationToken ct)
{
    var partitionKey = "FULL";
    var cp = checkpoint.GetOrCreatePartitionCheckpoint(runId, table.TableName, partitionKey, table.EstimatedRows);
    if (cp.Status == MigrationStatus.Done)
    {
        Log.Information("Skipping completed table {Table}", table.TableName);
        return;
    }

    // Mark running immediately so progress UI updates
    checkpoint.UpdatePartitionProgress(cp.Id, cp.RowsProcessed);

    var hasExplicitRetry = cfg.TableRetryModes.TryGetValue(table.TableName, out var retryMode);
    var exists = await MssqlBulkCopyLoader.TableExistsAsync(targetCs, schema, table.TableName, ct);

    try
    {
        if (hasExplicitRetry && retryMode == TableRetryMode.Recreate && exists)
        {
            Log.Information("Recreate: dropping {Table}", table.TableName);
            await MssqlBulkCopyLoader.ExecuteDdlAsync(targetCs, ddlGen.GenerateDropTable(table), ct);
            exists = false;
            checkpoint.ResetTablePartitions(runId, table.TableName);
            cp = checkpoint.GetOrCreatePartitionCheckpoint(runId, table.TableName, partitionKey, table.EstimatedRows);
            checkpoint.UpdatePartitionProgress(cp.Id, 0);
        }

        // CREATE TABLE only (PK optional). Views are materialized as tables with the view name.
        // Indexes/unique/FK AFTER data load (tables only).
        if (!exists)
        {
            var withPk = cfg.MigratePrimaryKeys && !table.IsView
                || (table.IsView && cfg.MigratePrimaryKeys && table.PrimaryKeyColumns.Count > 0
                    && table.PrimaryKeyColumns.All(pk =>
                        table.Columns.Any(c => c.ColumnName.Equals(pk, StringComparison.OrdinalIgnoreCase))));
            Log.Information(
                "Creating target table {Schema}.{Table}{ViewNote}",
                schema, table.TableName,
                table.IsView ? " (materialized from VIEW)" : "");
            await MssqlBulkCopyLoader.ExecuteDdlAsync(
                targetCs,
                ddlGen.GenerateCreateTable(table, withPk),
                ct);
        }
        else
        {
            var targetCount = await MssqlBulkCopyLoader.CountRowsAsync(targetCs, schema, table.TableName, ct);

            // Explicit Resume with rows already loaded → skip
            if (hasExplicitRetry && retryMode == TableRetryMode.Resume && targetCount > 0 && isResumeRun
                && cp.Status != MigrationStatus.Failed)
            {
                Log.Information("Resume skip {Table} (target has {Rows} rows)", table.TableName, targetCount);
                checkpoint.CompletePartition(cp.Id, targetCount);
                return;
            }

            // Fresh run or Truncate / Failed: clear target before reload to avoid PK duplicates
            if (targetCount > 0)
            {
                Log.Information("Clearing target {Table} ({Rows} rows) before copy", table.TableName, targetCount);
                await MssqlBulkCopyLoader.TruncateAsync(targetCs, schema, table.TableName, ct);
            }
        }

        var insertCols = table.Columns
            .Where(c => !c.IsIdentity || true) // identity kept via KeepIdentity
            .Select(c => c.ColumnName)
            .ToList();

        // Prefer live insertable column list (skips computed/rowversion)
        var liveCols = await MssqlBulkCopyLoader.GetInsertableColumnsAsync(sourceCs, schema, table.TableName, ct);
        if (liveCols.Count > 0)
            insertCols = liveCols;

        // Views: read through view (data may live in base tables); no KeepIdentity
        var hasIdentity = !table.IsView
            && table.Columns.Any(c => c.IsIdentity && insertCols.Contains(c.ColumnName, StringComparer.OrdinalIgnoreCase));
        if (table.IsView)
            Log.Information("Reading VIEW {View} (bases: {Bases})", table.TableName,
                table.BaseTables.Count == 0 ? "?" : string.Join(", ", table.BaseTables));

        var rows = await loader.CopyTableAsync(
            sourceCs,
            schema,
            table.TableName,
            keepIdentity: hasIdentity,
            columnNames: insertCols,
            progressCallback: r =>
            {
                try { checkpoint.UpdatePartitionProgress(cp.Id, r); }
                catch (Exception ex) { Log.Warning(ex, "Checkpoint progress update failed for {Table}", table.TableName); }
            },
            ct);

        // Post-load schema objects (never before data; skip for pure view materialize extras if empty)
        if (!table.IsView && cfg.MigrateIndexes)
        {
            foreach (var ddl in ddlGen.GenerateIndexes(table, uniqueOnly: false))
                await TryDdlAsync(targetCs, ddl, ct);
        }

        if (!table.IsView && cfg.MigrateUniqueConstraints)
        {
            foreach (var ddl in ddlGen.GenerateUniqueConstraints(table))
                await TryDdlAsync(targetCs, ddl, ct);
        }

        if (!table.IsView && cfg.MigrateCheckConstraints)
        {
            foreach (var ddl in ddlGen.GenerateCheckConstraints(table))
                await TryDdlAsync(targetCs, ddl, ct);
        }

        if (!table.IsView && cfg.MigrateForeignKeys)
        {
            foreach (var ddl in ddlGen.GenerateForeignKeys(table))
                await TryDdlAsync(targetCs, ddl, ct);
        }

        var shouldValidate = cfg.ValidatePerTableAfterLoad
            || cfg.ValidationMode is ValidationMode.CountOnly or ValidationMode.Balanced or ValidationMode.Strict;

        if (shouldValidate)
        {
            var sourceCount = await MssqlBulkCopyLoader.CountRowsAsync(sourceCs, schema, table.TableName, ct);
            var targetCount = await MssqlBulkCopyLoader.CountRowsAsync(targetCs, schema, table.TableName, ct);
            if (sourceCount != targetCount)
            {
                var msg = $"Row count mismatch {table.TableName}: source={sourceCount}, target={targetCount}";
                Log.Error(msg);
                checkpoint.FailPartition(cp.Id, msg);
                throw new InvalidOperationException(msg);
            }

            Log.Information("Validated {Table}: {Count} rows", table.TableName, sourceCount);
            checkpoint.CompletePartition(cp.Id, sourceCount);
        }
        else
        {
            checkpoint.CompletePartition(cp.Id, rows);
        }

        Log.Information("Done {Table}: {Rows} rows", table.TableName, rows);
    }
    catch (Exception ex)
    {
        try { checkpoint.FailPartition(cp.Id, ex.Message); }
        catch { /* ignore */ }
        throw;
    }
}

static async Task TryDdlAsync(string targetCs, string ddl, CancellationToken ct)
{
    try
    {
        await MssqlBulkCopyLoader.ExecuteDdlAsync(targetCs, ddl, ct);
    }
    catch (Exception ex)
    {
        Log.Warning(ex, "DDL skipped/failed: {Ddl}", ddl.Split('\n')[0]);
    }
}
