using MigrationEngine.Checkpoint;
using MigrationEngine.Extractors;
using MigrationEngine.Loaders;
using MigrationEngine.Schema;
using MigrationEngine.Services;
using MigrationEngine.Validation;
using MigrationShared.Enums;
using MigrationEngine.Summary;
using MigrationShared.Models;
using Microsoft.Extensions.Configuration;
using Serilog;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Linq;

static string ParseReferencedTableFromFkDdl(string fkDdl)
{
    try
    {
        // REFERENCES [TABLE_NAME] pattern'ini bul
        var referencesIndex = fkDdl.IndexOf("REFERENCES", StringComparison.OrdinalIgnoreCase);
        if (referencesIndex == -1) return "UNKNOWN";
        
        var afterReferences = fkDdl.Substring(referencesIndex + 10).Trim();
        var tableName = afterReferences.Split(new[] { ' ', '\r', '\n', '(', '[' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        return tableName?.Trim(']', '[') ?? "UNKNOWN";
    }
    catch
    {
        return "UNKNOWN";
    }
}

/// <summary>
/// Migratorv0 dashboard reads checkpoint DB under the MigrationEngine project folder; relative paths in
/// appsettings would otherwise resolve next to the EXE (bin/Debug/...), so the UI never saw updates.
/// </summary>
static string ResolveCheckpointSqlitePath(string? sqliteFromConfig)
{
    var raw = string.IsNullOrWhiteSpace(sqliteFromConfig) ? "migration_checkpoint.db" : sqliteFromConfig.Trim();
    if (Path.IsPathRooted(raw))
        return Path.GetFullPath(raw);

    for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
    {
        if (File.Exists(Path.Combine(dir.FullName, "MigrationEngine.csproj")))
            return Path.GetFullPath(Path.Combine(dir.FullName, Path.GetFileName(raw)));
    }

    // Self-contained single-file: AppContext.BaseDirectory is a temp extraction dir.
    // Use the actual exe directory instead.
    var exeDir = Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory;
    return Path.GetFullPath(Path.Combine(exeDir, Path.GetFileName(raw)));
}

var config = new ConfigurationBuilder()
    .AddJsonFile("appsettings.json", optional: false)
    .Build();

var exeDir = Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory;
var logPath = Path.Combine(exeDir, "logs", "migration-.log");
Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .WriteTo.Console()
    .WriteTo.File(logPath, rollingInterval: Serilog.RollingInterval.Day)
    .CreateLogger();

int runId = 0;
int historyId = 0;
ExtendedCheckpointRepository? extendedCheckpoint = null;
CheckpointRepository? checkpoint = null;

try
{
    Log.Information("=== Oracle to MSSQL Migration Engine ===");
    Log.Information("Starting migration at {Time}", DateTime.Now);

    var migrationConfig = new MigrationConfig();
    config.GetSection("Migration").Bind(migrationConfig);
    // Anahtar yoksa veya boşsa otomatik aktarım başlamasın (dotnet run sadece motoru açar, çıkar).
    if (string.IsNullOrWhiteSpace(config["Migration:AutoStart"]))
        migrationConfig.AutoStart = false;

    var argv = Environment.GetCommandLineArgs().Skip(1).ToList();
    var forceRun = argv.Any(a => string.Equals(a, "--run", StringComparison.OrdinalIgnoreCase)
        || string.Equals(a, "-y", StringComparison.OrdinalIgnoreCase));
    var forceResume = argv.Any(a => string.Equals(a, "--resume", StringComparison.OrdinalIgnoreCase));

    if (!migrationConfig.AutoStart && !forceRun && !forceResume)
    {
        Log.Information("=== Oracle to MSSQL Migration Engine (idle) ===");
        Log.Information("Migration:AutoStart is false; migration will not run.");
        Log.Information("Run once:    dotnet run -- --run      (fresh start)");
        Log.Information("Resume:      dotnet run -- --resume   (continue interrupted migration)");
        return 0;
    }

    var checkpointPath = ResolveCheckpointSqlitePath(config["Checkpoint:SqlitePath"]);
    Log.Information("Checkpoint database path: {Path}", checkpointPath);

    checkpoint = new CheckpointRepository(checkpointPath);
    extendedCheckpoint = new ExtendedCheckpointRepository(checkpointPath);

    // --resume: son yarıda kalan run'ı bul ve devam et
    bool isResume = false;
    if (forceResume)
    {
        var incomplete = checkpoint.FindLastIncompleteRun();
        if (incomplete.HasValue)
        {
            runId = incomplete.Value.runId;
            isResume = true;
            var resetCount = checkpoint.ResetInterruptedPartitions(runId);
            Log.Information("=== RESUME MODE: Run #{RunId} (started {StartTime:g}) ===", runId, incomplete.Value.startTime);
            Log.Information("Reset {Count} interrupted partition(s) to Pending", resetCount);
            // Yarıda kalan run'ın config'ini yükle (mevcut appsettings override olabilir)
            if (incomplete.Value.config != null
                && !string.IsNullOrWhiteSpace(incomplete.Value.config.OracleConnectionString)
                && !string.IsNullOrWhiteSpace(incomplete.Value.config.MssqlConnectionString))
                migrationConfig = incomplete.Value.config;
        }
        else
        {
            Log.Warning("--resume requested but no incomplete run found in checkpoint DB. Starting fresh.");
        }
    }

    if (string.IsNullOrWhiteSpace(migrationConfig.OracleConnectionString) ||
        string.IsNullOrWhiteSpace(migrationConfig.MssqlConnectionString))
    {
        Log.Fatal("Migration configuration is missing connection strings. Run the Wizard from the web UI to generate appsettings.json.");
        return 1;
    }

    if (!isResume)
        runId = checkpoint.CreateNewRun(migrationConfig);

    var progress = new ProgressWriter(checkpoint, runId);

    // Migration history kaydı oluştur (resume'da mevcut history güncellenir)
    var migrationName = isResume
        ? $"Oracle_{migrationConfig.OracleSchema}_to_MSSQL_RESUME_{DateTime.Now:yyyyMMdd_HHmmss}"
        : $"Oracle_{migrationConfig.OracleSchema}_to_MSSQL_{DateTime.Now:yyyyMMdd_HHmmss}";
    var configJson = System.Text.Json.JsonSerializer.Serialize(migrationConfig, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
    historyId = extendedCheckpoint.CreateMigrationHistory(
        migrationName,
        migrationConfig.OracleConnectionString,
        migrationConfig.MssqlConnectionString,
        migrationConfig.OracleSchema,
        migrationConfig.Tables?.Count ?? 0,
        configJson,
        runId);

    Log.Information("Migration history created with ID: {HistoryId}", historyId);

    var migrationUnid = $"MIG-{runId:D6}-{DateTime.UtcNow:yyyyMMddHHmmss}";
    Log.Information("Migration UNID: {Unid}", migrationUnid);

    var cts = new CancellationTokenSource();
    Console.CancelKeyPress += (s, e) =>
    {
        e.Cancel = true;
        Log.Warning("Cancellation requested by user...");
        cts.Cancel();
    };

    var ct = cts.Token;
    var overallStopwatch = Stopwatch.StartNew();

    progress.WritePhaseStart("INITIALIZATION", "Migration starting");

    var schemaReader = new SchemaReader(
        migrationConfig.OracleConnectionString,
        migrationConfig.OracleSchema,
        migrationConfig.MigrateSpatial);
    var ddlGenerator = new DdlGenerator();
    var loader = new SqlBulkCopyLoader(migrationConfig.MssqlConnectionString, migrationConfig.BatchSize);
    var spatialPostLoader = migrationConfig.MigrateSpatial
        ? new SpatialPostLoader(migrationConfig.MssqlConnectionString)
        : null;
    var validator = new DataValidator(
        migrationConfig.OracleConnectionString,
        migrationConfig.MssqlConnectionString,
        migrationConfig.OracleSchema);

    Log.Information("Reading Oracle schema: {Schema}", migrationConfig.OracleSchema);
    progress.WritePhaseStart("SCHEMA", $"Reading schema {migrationConfig.OracleSchema}");

    var tables = await schemaReader.ReadSchemaAsync(
        migrationConfig.Tables,
        migrationConfig.ExcludeTables,
        ct);

    Log.Information("Found {Count} tables to migrate", tables.Count);

    if (migrationConfig.MigrateSpatial)
    {
        foreach (var table in tables)
            SpatialMetadataHelper.ApplySridOverrides(table, migrationConfig);
    }

    ExtraColumnHelper.ApplyExtraColumns(tables, migrationConfig);

    var allWarnings = new List<TypeMappingWarning>();
    var allCreateTableDdl = new List<string>();
    var allPrimaryKeyDdl = new List<string>();
    var allUniqueConstraintDdl = new List<string>();
    var allIndexDdl = new Dictionary<string, List<string>>();
    var allForeignKeyDdl = new List<string>();
    var tableCreateDdlMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    var tablePkDdlMap = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
    var tableUniqueDdlMap = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);

    progress.WritePhaseStart("DDL_GENERATION", "Generating MSSQL DDL statements");

    foreach (var table in tables)
    {
        var (createTableDdl, primaryKeyDdl, uniqueConstraintDdl, indexDdl, foreignKeyDdl, warnings) =
            ddlGenerator.GenerateDdl(table, migrationConfig.MigrateUniqueConstraints);

        allCreateTableDdl.Add(createTableDdl);
        allPrimaryKeyDdl.AddRange(primaryKeyDdl);
        allUniqueConstraintDdl.AddRange(uniqueConstraintDdl);
        tableCreateDdlMap[table.TableName] = createTableDdl;
        tablePkDdlMap[table.TableName] = primaryKeyDdl;
        tableUniqueDdlMap[table.TableName] = uniqueConstraintDdl;
        allIndexDdl[table.TableName] = indexDdl;
        allForeignKeyDdl.AddRange(foreignKeyDdl);
        allWarnings.AddRange(warnings);

        if (warnings.Any())
        {
            Log.Warning("Table {Table} has {Count} type mapping warnings", table.TableName, warnings.Count);
            foreach (var warning in warnings)
            {
                progress.WriteWarning(table.TableName,
                    $"Column {warning.ColumnName}: {warning.OracleType} → {warning.MssqlType}",
                    warning.WarningMessage);
            }
        }

        Log.Information("DDL generated for table {Table}", table.TableName);
    }

    Log.Information("Executing DDL for {Count} table(s)…", allCreateTableDdl.Count);

    var circularFks = ddlGenerator.DetectCircularForeignKeys(tables);
    if (circularFks.Any())
    {
        Log.Warning("Detected {Count} circular foreign key dependencies", circularFks.Count);
        foreach (var cycle in circularFks)
        {
            Log.Warning("Circular FK: {Cycle}", cycle);
        }
    }

    Log.Information("Generated DDL for {Count} tables, {Warnings} warnings",
        tables.Count, allWarnings.Count);

    var dbName = await loader.GetDatabaseNameAsync(ct);
    var originalRecoveryModel = "FULL";
    try
    {
        originalRecoveryModel = await loader.GetRecoveryModelAsync(ct);
        Log.Information("Database {Db} current recovery model: {Model}", dbName, originalRecoveryModel);
    }
    catch (Exception recReadEx)
    {
        Log.Warning(recReadEx, "Could not read current recovery model — will restore to FULL after migration");
    }

    if (isResume)
    {
        // Tablolar zaten mevcut; DDL_EXECUTION atlanıyor.
        progress.WritePhaseStart("DDL_EXECUTION", "Skipped (resume mode — tables already exist)");
        progress.WritePhaseComplete("DDL_EXECUTION", "Skipped");
        Log.Information("Resume mode: DDL_EXECUTION skipped, tables already exist in target");
    }
    else
    {
        progress.WritePhaseStart("DDL_EXECUTION", "Creating tables and primary keys");
        if (migrationConfig.UseBulkLoggedRecovery)
        {
            Log.Information("Setting recovery model to BULK_LOGGED (original: {Model})", originalRecoveryModel);
            await loader.SetRecoveryModelAsync(dbName, "BULK_LOGGED", ct);
        }

        Log.Information("Creating {Count} tables", allCreateTableDdl.Count);
        await loader.ExecuteDdlBatchAsync(allCreateTableDdl, ct);

        if (migrationConfig.MigratePrimaryKeys && allPrimaryKeyDdl.Count > 0)
        {
            Log.Information("Creating {Count} primary key constraint(s)", allPrimaryKeyDdl.Count);
            await loader.ExecuteDdlBatchAsync(allPrimaryKeyDdl, ct);
        }

        if (migrationConfig.MigrateUniqueConstraints && allUniqueConstraintDdl.Count > 0)
        {
            Log.Information("Creating {Count} unique constraint(s)", allUniqueConstraintDdl.Count);
            await loader.ExecuteDdlBatchAsync(allUniqueConstraintDdl, ct);
        }

        if (migrationConfig.MigratePrimaryKeys || migrationConfig.MigrateUniqueConstraints)
            progress.WritePhaseComplete("DDL_EXECUTION", "Tables and constraints created");
        else
        {
            Log.Information("Skipping primary keys and unique constraints (disabled in config)");
            progress.WritePhaseComplete("DDL_EXECUTION", "Tables created (constraints skipped)");
        }
    }

    // Per-table retry mode: Recreate / Truncate / Resume
    if (migrationConfig.TableRetryModes.Count > 0)
    {
        progress.WritePhaseStart("RETRY_SETUP", "Applying per-table retry modes");
        foreach (var table in tables)
        {
            if (!migrationConfig.TableRetryModes.TryGetValue(table.TableName, out var retryMode))
                continue;

            switch (retryMode)
            {
                case TableRetryMode.Recreate:
                    Log.Information("[RetryMode:Recreate] Dropping and recreating [{Table}]", table.TableName);
                    await loader.DropTableAsync(table.TableName, ct);
                    if (tableCreateDdlMap.TryGetValue(table.TableName, out var createDdl))
                        await loader.ExecuteDdlAsync(createDdl, ct);
                    if (migrationConfig.MigratePrimaryKeys
                        && tablePkDdlMap.TryGetValue(table.TableName, out var pkDdls))
                        await loader.ExecuteDdlBatchAsync(pkDdls, ct);
                    if (migrationConfig.MigrateUniqueConstraints
                        && tableUniqueDdlMap.TryGetValue(table.TableName, out var uniqueDdls))
                        await loader.ExecuteDdlBatchAsync(uniqueDdls, ct);
                    checkpoint.ResetTablePartitions(runId, table.TableName);
                    break;

                case TableRetryMode.Truncate:
                    Log.Information("[RetryMode:Truncate] Truncating [{Table}]", table.TableName);
                    await loader.TruncateTableAsync(table.TableName, ct);
                    checkpoint.ResetTablePartitions(runId, table.TableName);
                    break;

                case TableRetryMode.Resume:
                    Log.Information("[RetryMode:Resume] Continuing from checkpoint for [{Table}]", table.TableName);
                    // Sequentially delete rows from failed partitions that have stored PK ranges,
                    // before the parallel DATA_MIGRATION phase begins, to avoid lock contention.
                    var resumePkConstraint = table.Constraints.FirstOrDefault(c => c.ConstraintType == "P");
                    var resumePkCol = resumePkConstraint?.Columns.FirstOrDefault();
                    if (resumePkCol != null)
                    {
                        var failedRanges = checkpoint.GetFailedPartitionsWithPkRanges(runId)
                            .Where(r => r.tableName.Equals(table.TableName, StringComparison.OrdinalIgnoreCase))
                            .ToList();
                        if (failedRanges.Count > 0)
                        {
                            Log.Information("[RetryMode:Resume] Cleaning {Count} failed partition(s) for [{Table}]", failedRanges.Count, table.TableName);
                            foreach (var (_, _, startPk, endPk) in failedRanges)
                            {
                                if (startPk.HasValue && endPk.HasValue)
                                    await loader.DeletePkRangeAsync(table.TableName, resumePkCol, startPk.Value, endPk.Value, ct);
                            }
                        }
                    }
                    break;
            }
        }
        progress.WritePhaseComplete("RETRY_SETUP", "Per-table retry modes applied");
    }

    progress.WritePhaseStart("DATA_MIGRATION", $"Migrating data with {migrationConfig.DegreeOfParallelism} parallel workers");

    var extractor = new OracleParallelExtractor(
        migrationConfig.OracleConnectionString,
        migrationConfig.FetchSizeMB);

    var useStagingFlow = migrationConfig.UseStagingMerge || migrationConfig.UsePartitionSwitch;
    var stagingMergeLoader = useStagingFlow
        ? new StagingMergeLoader(migrationConfig.MssqlConnectionString)
        : null;
    var partitionSwitchLoader = migrationConfig.UsePartitionSwitch
        ? new PartitionSwitchLoader(migrationConfig.MssqlConnectionString)
        : null;

    var semaphore = new SemaphoreSlim(migrationConfig.DegreeOfParallelism);
    var tableRowCounts = new ConcurrentDictionary<string, long>(StringComparer.OrdinalIgnoreCase);
    foreach (var t in tables)
        tableRowCounts.TryAdd(t.TableName, 0L);

    using var dataMigrationCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
    var dataMigrationToken = dataMigrationCts.Token;

    await Parallel.ForEachAsync(tables, new ParallelOptions 
    { 
        MaxDegreeOfParallelism = migrationConfig.DegreeOfParallelism,
        CancellationToken = dataMigrationToken
    }, async (table, loopCt) =>
    {
        await semaphore.WaitAsync(loopCt);
        try
        {
            var tableStopwatch = Stopwatch.StartNew();
            Log.Information("Starting migration for table {Table}", table.TableName);

            var rowCount = await schemaReader.GetTableRowCountAsync(table.TableName, loopCt);
            tableRowCounts[table.TableName] = rowCount;
            if (rowCount == 0)
            {
                Log.Information("Table {Table} is empty, skipping data load", table.TableName);
                if (spatialPostLoader != null)
                {
                    var emptySpatialCols = SpatialColumnHelper.GetSpatialColumns(
                        ddlGenerator.GetMigratableColumns(table));
                    if (emptySpatialCols.Count > 0)
                        await spatialPostLoader.ConvertSpatialColumnsAsync(table, emptySpatialCols, migrationConfig, loopCt);
                }
                return;
            }

            var pkConstraint = table.Constraints.FirstOrDefault(c => c.ConstraintType == "P");
            var pkColumn = pkConstraint?.Columns.FirstOrDefault();
            var pkColSchema = pkColumn != null ? 
                table.Columns.FirstOrDefault(c => c.ColumnName.Equals(pkColumn, StringComparison.OrdinalIgnoreCase)) : 
                null;
            var isNumericPk = pkColSchema?.DataType.ToUpper() == "NUMBER";

            var partitions = new List<MigrationShared.Models.PartitionRange>();
            
            if (isNumericPk && pkColumn != null)
            {
                var pkPartitions = await extractor.CalculatePkPartitionsAsync(
                    migrationConfig.OracleSchema,
                    table.TableName,
                    pkColumn,
                    migrationConfig.DegreeOfParallelism,
                    loopCt);

                for (int i = 0; i < pkPartitions.Count; i++)
                {
                    partitions.Add(new MigrationShared.Models.PartitionRange
                    {
                        PartitionNumber = i + 1,
                        StartPkValue = pkPartitions[i].startPk,
                        EndPkValue = pkPartitions[i].endPk
                    });
                }
            }
            else
            {
                // Sayısal tek PK yok: ROWID ile yaklaşık eşit satır bölümü (önceden tek partition idi).
                var rowIdParts = await extractor.CalculateRowIdPartitionsAsync(
                    migrationConfig.OracleSchema,
                    table.TableName,
                    migrationConfig.DegreeOfParallelism,
                    loopCt);
                if (rowIdParts.Count == 0)
                {
                    partitions.Add(new MigrationShared.Models.PartitionRange { PartitionNumber = 1 });
                }
                else
                {
                    for (var i = 0; i < rowIdParts.Count; i++)
                    {
                        partitions.Add(new MigrationShared.Models.PartitionRange
                        {
                            PartitionNumber = i + 1,
                            StartRowId = rowIdParts[i].startRowId,
                            EndRowId = rowIdParts[i].endRowId,
                            // Last ROWID partition ends at MAX(ROWID); must be inclusive or that row is skipped.
                            EndRowIdInclusive = i == rowIdParts.Count - 1
                        });
                    }
                }

                Log.Information(
                    "Table {Table}: ROWID-based partitions = {Count} (no numeric single-column PK path)",
                    table.TableName, partitions.Count);
            }

            long totalRowsMigrated = 0;
            var partitionParallelism = (migrationConfig.ParallelPartitionLoad || useStagingFlow)
                ? (migrationConfig.PartitionDegreeOfParallelism > 0
                    ? migrationConfig.PartitionDegreeOfParallelism
                    : migrationConfig.DegreeOfParallelism)
                : 1;
            var partitionTargets = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
            if (partitions.Count > 0)
            {
                var baseTarget = rowCount / partitions.Count;
                var remainder = rowCount % partitions.Count;
                for (var i = 0; i < partitions.Count; i++)
                {
                    var extra = i < remainder ? 1L : 0L;
                    partitionTargets[partitions[i].PartitionKey] = baseTarget + extra;
                }
            }

            // Dashboard toplam hedef satırı baştan doğru göstersin diye tüm partition checkpoint'lerini upfront oluştur.
            foreach (var p in partitions)
            {
                var targetRows = partitionTargets.TryGetValue(p.PartitionKey, out var v) ? v : 0L;
                checkpoint.GetOrCreatePartitionCheckpoint(
                    runId, table.TableName, p.PartitionKey, targetRows,
                    p.StartPkValue, p.EndPkValue);
            }

            // Build staging table map: partition index → staging table name (only when staging flow enabled)
            var stagingTableMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            bool partitionSwitchReady = false;
            IReadOnlyList<long>? switchBoundaries = null;

            if (stagingMergeLoader != null)
            {
                for (var i = 0; i < partitions.Count; i++)
                    stagingTableMap[partitions[i].PartitionKey] = StagingMergeLoader.StagingTableName(table.TableName, i + 1);

                Log.Information("StagingFlow: creating {Count} staging table(s) for {Table}", partitions.Count, table.TableName);
                await Parallel.ForEachAsync(partitions, new ParallelOptions
                {
                    MaxDegreeOfParallelism = partitionParallelism,
                    CancellationToken = loopCt
                }, async (p, pCt) =>
                {
                    var stgName = stagingTableMap[p.PartitionKey];
                    await stagingMergeLoader.CreateStagingTableAsync(table.TableName, stgName, pCt);
                });

                // Partition switch: prepare partitioned target (drop empty target, recreate as partitioned heap)
                if (partitionSwitchLoader != null && isNumericPk && pkColumn != null && partitions.Count > 1)
                {
                    var pkPartitions = partitions.Where(p => p.StartPkValue.HasValue && p.EndPkValue.HasValue).ToList();
                    if (pkPartitions.Count == partitions.Count)
                    {
                        // RANGE RIGHT boundaries = start of each partition except the first
                        var boundaries = pkPartitions.Skip(1).Select(p => p.StartPkValue!.Value).ToList();
                        partitionSwitchReady = await partitionSwitchLoader.PreparePartitionedTargetAsync(
                            table.TableName, pkColumn, boundaries, loopCt);
                        if (partitionSwitchReady)
                            switchBoundaries = boundaries;
                    }
                    else
                    {
                        Log.Information("[PartitionSwitch] [{Table}] skipped — some partitions lack PK boundaries (ROWID-based).", table.TableName);
                    }
                }
            }

            await Parallel.ForEachAsync(partitions, new ParallelOptions
            {
                MaxDegreeOfParallelism = partitionParallelism,
                CancellationToken = loopCt
            }, async (partition, partCt) =>
            {
                var checkpointRecord = checkpoint.GetOrCreatePartitionCheckpoint(
                    runId,
                    table.TableName,
                    partition.PartitionKey,
                    partitionTargets.TryGetValue(partition.PartitionKey, out var targetRows) ? targetRows : 0L,
                    partition.StartPkValue,
                    partition.EndPkValue);

                if (checkpointRecord.Status == MigrationStatus.Done)
                {
                    Interlocked.Add(ref totalRowsMigrated, checkpointRecord.RowsProcessed);
                    Log.Information("Partition {Table}[{Partition}] already completed, skipping",
                        table.TableName, partition.PartitionKey);
                    return;
                }

                // When staging merge is enabled, load into the staging table instead of the final target.
                var loadTarget = stagingTableMap.TryGetValue(partition.PartitionKey, out var stg)
                    ? stg
                    : table.TableName;

                var partitionStopwatch = Stopwatch.StartNew();

                try
                {
                    var migratableColumns = ddlGenerator.GetMigratableColumns(table);
                    if (migratableColumns.Count == 0)
                    {
                        Log.Warning("Table {Table} has no migratable columns, skipping partition {Partition}",
                            table.TableName, partition.PartitionKey);
                        return;
                    }

                    var columnSelects = OracleSelectBuilder.BuildSelectList(
                        migratableColumns,
                        migrationConfig,
                        table.TableName,
                        migrationConfig.OracleSchema);
                    var reader = await extractor.ExtractPartitionAsync(
                        migrationConfig.OracleSchema,
                        table.TableName,
                        columnSelects,
                        partition.StartRowId,
                        partition.EndRowId,
                        partition.StartPkValue,
                        partition.EndPkValue,
                        pkColumn,
                        partCt,
                        partition.EndRowIdInclusive);

                    long lastReportedRows = 0;
                    var lastReportTime = DateTime.UtcNow;
                    const long progressRowStep = 5_000;

                    var rowsLoaded = await loader.LoadDataAsync(
                        loadTarget,
                        reader,
                        (rows) =>
                        {
                            var now = DateTime.UtcNow;
                            var shouldReport =
                                (rows - lastReportedRows >= progressRowStep) ||
                                (now - lastReportTime).TotalSeconds >= 3;
                            if (shouldReport)
                            {
                                var elapsed = (now - lastReportTime).TotalSeconds;
                                var rowsPerSecond = elapsed > 0 ? (rows - lastReportedRows) / elapsed : 0;

                                checkpoint.UpdatePartitionProgress(checkpointRecord.Id, rows);
                                progress.WriteProgress(
                                    table.TableName,
                                    partition.PartitionKey,
                                    "LOAD",
                                    MigrationStatus.Running,
                                    rows,
                                    partitionTargets.TryGetValue(partition.PartitionKey, out var tRows) ? tRows : 0L,
                                    rowsPerSecond,
                                    stagingMergeLoader != null
                                        ? $"Staging {rows:N0} rows → [{loadTarget}]"
                                        : $"Loaded {rows:N0} rows");

                                lastReportedRows = rows;
                                lastReportTime = now;
                            }
                        },
                        partCt,
                        migratableColumns);

                    reader.Dispose();

                    if (rowsLoaded > lastReportedRows)
                    {
                        var now = DateTime.UtcNow;
                        var elapsed = Math.Max(0.001, (now - lastReportTime).TotalSeconds);
                        var rowsPerSecond = (rowsLoaded - lastReportedRows) / elapsed;
                        checkpoint.UpdatePartitionProgress(checkpointRecord.Id, rowsLoaded);
                        progress.WriteProgress(
                            table.TableName,
                            partition.PartitionKey,
                            "LOAD",
                            MigrationStatus.Running,
                            rowsLoaded,
                            partitionTargets.TryGetValue(partition.PartitionKey, out var tRows) ? tRows : 0L,
                            rowsPerSecond,
                            stagingMergeLoader != null
                                ? $"Staging {rowsLoaded:N0} rows → [{loadTarget}]"
                                : $"Loaded {rowsLoaded:N0} rows");
                    }

                    // For staging merge: mark partition Done only after staging load (merge happens below)
                    checkpoint.CompletePartition(checkpointRecord.Id, rowsLoaded);
                    Interlocked.Add(ref totalRowsMigrated, rowsLoaded);

                    var partitionElapsed = partitionStopwatch.Elapsed.TotalSeconds;
                    var avgRowsPerSec = partitionElapsed > 0 ? rowsLoaded / partitionElapsed : 0;
                    Log.Information("Staged {Table}[{Partition}] → [{Target}]: {Rows:N0} rows in {Elapsed:F1}s ({RowsPerSec:N0} rows/s)",
                        table.TableName, partition.PartitionKey, loadTarget, rowsLoaded, partitionElapsed, avgRowsPerSec);
                }
                catch (OperationCanceledException)
                {
                    checkpoint.FailPartition(checkpointRecord.Id, "Cancelled");
                    throw;
                }
                catch (Exception ex)
                {
                    checkpoint.FailPartition(checkpointRecord.Id, ex.Message);
                    Log.Error(ex, "Partition {Table}[{Partition}] failed", table.TableName, partition.PartitionKey);
                    throw;
                }
            });

            // Merge phase: partition switch (instant) or INSERT/SELECT (row copy)
            if (stagingMergeLoader != null && stagingTableMap.Count > 0)
            {
                var stagingNames = stagingTableMap.Values.ToList();

                progress.WriteProgress(table.TableName, "merge", "MERGE", MigrationStatus.Running,
                    Interlocked.Read(ref totalRowsMigrated), rowCount, 0,
                    partitionSwitchReady
                        ? $"Partition SWITCH {stagingNames.Count} tables into [{table.TableName}]…"
                        : $"Merging {stagingNames.Count} staging tables into [{table.TableName}]…");

                bool mergeSucceeded = false;
                try
                {
                    if (partitionSwitchReady && partitionSwitchLoader != null && switchBoundaries != null)
                    {
                        // Add CHECK constraints to staging tables (required for SWITCH)
                        var switchConstraintArgs = partitions
                            .Where(p => p.StartPkValue.HasValue && p.EndPkValue.HasValue)
                            .Select(p => (stagingTableMap[p.PartitionKey], p.StartPkValue!.Value, p.EndPkValue!.Value))
                            .ToList();
                        await partitionSwitchLoader.AddSwitchConstraintsAsync(pkColumn!, switchConstraintArgs, loopCt);

                        // Perform partition switch (metadata-only, near-instant)
                        var switchOps = partitions
                            .Select(p => (stagingTableMap[p.PartitionKey], p.PartitionNumber))
                            .ToList();
                        await partitionSwitchLoader.SwitchAllPartitionsAsync(table.TableName, switchOps, loopCt);
                        mergeSucceeded = true;

                        Log.Information("[PartitionSwitch] All {Count} partition(s) switched into [{Table}]", stagingNames.Count, table.TableName);

                        // Cleanup partition function/scheme (merge boundaries → plain heap)
                        await partitionSwitchLoader.CleanupPartitionObjectsAsync(table.TableName, switchBoundaries, loopCt);
                    }
                    else
                    {
                        // Standard INSERT...SELECT merge (smallest-first)
                        Log.Information("Merging {Count} staging table(s) into [{Table}]...", stagingNames.Count, table.TableName);
                        var mergedRows = await stagingMergeLoader.MergeIntoTargetAsync(table.TableName, stagingNames, loopCt);
                        mergeSucceeded = true;
                        Log.Information("Merge complete: {Rows:N0} rows → [{Table}]", mergedRows, table.TableName);
                    }
                }
                finally
                {
                    if (mergeSucceeded)
                    {
                        await stagingMergeLoader.DropAllStagingTablesAsync(stagingNames, loopCt);
                        Log.Information("Staging tables dropped for [{Table}]", table.TableName);
                    }
                    else
                    {
                        Log.Warning("[PartitionSwitch] Merge failed — staging tables preserved for [{Table}]: {Tables}",
                            table.TableName, string.Join(", ", stagingNames));
                    }
                }
            }

            if (spatialPostLoader != null)
            {
                var spatialColumns = SpatialColumnHelper.GetSpatialColumns(
                    ddlGenerator.GetMigratableColumns(table));
                if (spatialColumns.Count > 0)
                {
                    progress.WriteProgress(table.TableName, "spatial", "SPATIAL", MigrationStatus.Running,
                        Interlocked.Read(ref totalRowsMigrated), rowCount, 0,
                        $"Converting {spatialColumns.Count} spatial column(s) WKT → geometry/geography…");
                    await spatialPostLoader.ConvertSpatialColumnsAsync(table, spatialColumns, migrationConfig, loopCt);
                    progress.WriteProgress(table.TableName, "spatial", "SPATIAL", MigrationStatus.Done,
                        Interlocked.Read(ref totalRowsMigrated), rowCount, 0,
                        "Spatial column conversion complete");
                }
            }

            var fillExtras = ExtraColumnHelper.GetFillAfterLoadColumns(table.TableName, migrationConfig);
            if (fillExtras.Count > 0)
            {
                progress.WriteProgress(table.TableName, "extra", "EXTRA_COLS", MigrationStatus.Running,
                    Interlocked.Read(ref totalRowsMigrated), rowCount, 0,
                    $"Filling {fillExtras.Count} extra column(s) from Oracle…");
                var extraLoader = new ExtraColumnPostLoader(
                    migrationConfig.OracleConnectionString,
                    migrationConfig.MssqlConnectionString,
                    migrationConfig.OracleSchema);
                await extraLoader.FillExtraColumnsAsync(table.TableName, fillExtras, loopCt);
                progress.WriteProgress(table.TableName, "extra", "EXTRA_COLS", MigrationStatus.Done,
                    Interlocked.Read(ref totalRowsMigrated), rowCount, 0,
                    "Extra column fill complete");
            }

            var tableElapsed = tableStopwatch.Elapsed.TotalSeconds;
            var finalRowsMigrated = Interlocked.Read(ref totalRowsMigrated);
            var tableRowsPerSec = tableElapsed > 0 ? finalRowsMigrated / tableElapsed : 0;

            Log.Information("✓ Table {Table} completed: {Rows:N0} rows in {Elapsed:F1}s ({RowsPerSec:N0} rows/s)",
                table.TableName, finalRowsMigrated, tableElapsed, tableRowsPerSec);

            if (migrationConfig.ValidatePerTableAfterLoad)
            {
                var postResult = await validator.ValidateTableWithPlanAsync(table, rowCount, migrationConfig, loopCt);
                extendedCheckpoint!.InsertValidationGateResults(runId, "PostLoad", new[] { postResult });
                if (migrationConfig.ValidationFailFast && !postResult.AllGatesPassed)
                {
                    progress.WriteWarning(table.TableName, "Post-load validation failed; stopping remaining table workers.");
                    dataMigrationCts.Cancel();
                }
            }
        }
        catch (OperationCanceledException)
        {
            Log.Warning("Data migration cancelled for table {Table}", table.TableName);
            throw;
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Failed to migrate table {Table}", table.TableName);
            progress.WriteWarning(table.TableName, $"Migration failed: {ex.Message}");
            
            // Hatayı veritabanına kaydet
            try
            {
                extendedCheckpoint.LogError(
                    runId,
                    table.TableName,
                    null,
                    ex.GetType().Name,
                    ex.Message,
                    ex.StackTrace,
                    retryAttempt: 0);
            }
            catch (Exception logEx)
            {
                Log.Warning(logEx, "Failed to log error to database");
            }
        }
        finally
        {
            semaphore.Release();
        }
    });

    if (dataMigrationCts.IsCancellationRequested && migrationConfig.ValidationFailFast && migrationConfig.ValidatePerTableAfterLoad)
    {
        progress.WriteWarning("DATA_MIGRATION", "Stopped early: post-load validation fail-fast triggered.");
    }

    progress.WritePhaseComplete("DATA_MIGRATION", "All data migrated");

    // Indexes (opsiyonel - default: false)
    if (migrationConfig.MigrateIndexes)
    {
        progress.WritePhaseStart("INDEXES", $"Creating {allIndexDdl.Sum(x => x.Value.Count)} indexes");
        
        foreach (var (tableName, indexes) in allIndexDdl)
        {
            if (indexes.Any())
            {
                Log.Information("Creating {Count} indexes for table {Table}", indexes.Count, tableName);
                await loader.ExecuteDdlBatchAsync(indexes, ct);
            }
        }

        progress.WritePhaseComplete("INDEXES", "All indexes created");
    }
    else
    {
        Log.Information("Skipping index creation (MigrateIndexes = false)");
        progress.WritePhaseComplete("INDEXES", "Index creation skipped (disabled in config)");
    }

    // Foreign Keys (opsiyonel - default: false)
    if (migrationConfig.MigrateForeignKeys)
    {
        progress.WritePhaseStart("FOREIGN_KEYS", $"Creating {allForeignKeyDdl.Count} foreign keys");
        
        int fkSuccessCount = 0;
        int fkFailCount = 0;
        
        foreach (var fkDdl in allForeignKeyDdl)
        {
            try
            {
                await loader.ExecuteDdlAsync(fkDdl, ct);
                fkSuccessCount++;
            }
            catch (Exception ex)
            {
                fkFailCount++;
                Log.Warning(ex, "Failed to create foreign key, skipping: {FK}", 
                    fkDdl.Substring(0, Math.Min(100, fkDdl.Length)));
                
                // Foreign key hatasını warning olarak kaydet (çok kritik değil)
                try
                {
                    // Referans edilen tabloyu parse et
                    var referencedTable = ParseReferencedTableFromFkDdl(fkDdl);
                    
                    extendedCheckpoint?.LogError(
                        runId,
                        null, // Birden fazla tablo ilgili olabilir
                        null,
                        "FOREIGN_KEY_CREATION_FAILED",
                        $"FK creation failed: {ex.Message}. Referenced table '{referencedTable}' may not be migrated.",
                        fkDdl, // DDL'i stack trace yerine koy
                        retryAttempt: 0);
                }
                catch (Exception logEx)
                {
                    Log.Warning(logEx, "Failed to log FK error");
                }
            }
        }

        Log.Information("Foreign keys: {Success} created, {Failed} failed (missing referenced tables)", 
            fkSuccessCount, fkFailCount);
        progress.WritePhaseComplete("FOREIGN_KEYS", $"{fkSuccessCount}/{allForeignKeyDdl.Count} foreign keys created");
        
        if (fkFailCount > 0)
        {
            progress.WriteWarning("FOREIGN_KEYS", 
                $"{fkFailCount} foreign keys failed - likely due to missing referenced tables. Check /errors page for details.");
        }
    }
    else
    {
        Log.Information("Skipping foreign key creation (MigrateForeignKeys = false)");
        progress.WritePhaseComplete("FOREIGN_KEYS", "Foreign key creation skipped (disabled in config)");
    }

    progress.WritePhaseStart("VALIDATION", $"Validating {tables.Count} tables");

    var validationResults = await validator.ValidateAllTablesAsync(tables, tableRowCounts, migrationConfig, ct);
    extendedCheckpoint!.InsertValidationGateResults(runId, "Final", validationResults);

    var passedCount = validationResults.Count(v => v.AllGatesPassed);
    var failedCount = validationResults.Count(v => !v.AllGatesPassed);

    Log.Information("Validation complete: {Passed} passed, {Failed} failed", passedCount, failedCount);

    if (failedCount > 0)
    {
        Log.Error("VALIDATION FAILURES:");
        foreach (var failure in validationResults.Where(v => !v.AllGatesPassed))
        {
            Log.Error("  {Table}: gates failed — {Gates}",
                failure.TableName,
                string.Join(", ", failure.Gates.Where(g => !g.Passed).Select(g => $"{g.GateType}")));
            if (!failure.CountMatch)
            {
                Log.Error("    Row counts: Oracle={Oracle}, MSSQL={Mssql}",
                    failure.OracleCount, failure.MssqlCount);
            }
        }
    }

    progress.WritePhaseComplete("VALIDATION", $"{passedCount}/{tables.Count} tables passed all validation gates");

    if (migrationConfig.UseBulkLoggedRecovery)
    {
        try
        {
            Log.Information("Restoring recovery model to {Model}", originalRecoveryModel);
            await loader.SetRecoveryModelAsync(dbName, originalRecoveryModel, ct);
            if (originalRecoveryModel == "FULL")
                Log.Warning("IMPORTANT: Take a FULL BACKUP of the database now!");
        }
        catch (Exception recEx)
        {
            Log.Warning(recEx, "Could not restore recovery model to {Model} — manual restore may be needed", originalRecoveryModel);
        }
    }

    overallStopwatch.Stop();

    // Hedef veritabanına aktarım özeti yaz
    try
    {
        var summaryWriter = new MigrationSummaryWriter(migrationConfig.MssqlConnectionString);
        await summaryWriter.WriteSummaryAsync(migrationUnid, migrationName, tables, tableRowCounts, loader, ct);
    }
    catch (Exception sumEx)
    {
        Log.Warning(sumEx, "Migration summary could not be written");
    }

    checkpoint.UpdateRunStatus(runId, "COMPLETED");

    Log.Information("=== Migration completed in {Elapsed} ===", overallStopwatch.Elapsed);
    Log.Information("Total tables: {Count}", tables.Count);
    Log.Information("Type mapping warnings: {Count}", allWarnings.Count);
    Log.Information("Validation: {Passed} passed, {Failed} failed", passedCount, failedCount);
    
    // Migration başarılı - history'yi tamamla
    try
    {
        var totalRows = tableRowCounts.Values.Sum();
        extendedCheckpoint!.CompleteMigrationHistory(historyId, totalRows);
        Log.Information("✓ Migration history completed successfully");
    }
    catch (Exception histEx)
    {
        Log.Warning(histEx, "Failed to complete migration history");
    }
    
    checkpoint?.Dispose();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Migration failed with fatal error");
    
    // Migration başarısız - hata kaydet ve history'yi güncelle
    try
    {
        extendedCheckpoint?.LogError(
            runId,
            null,
            null,
            "FATAL_ERROR",
            ex.Message,
            ex.StackTrace,
            retryAttempt: 0);
        
        extendedCheckpoint?.FailMigrationHistory(historyId, ex.Message);
        Log.Information("✗ Migration history marked as FAILED");
    }
    catch (Exception logEx)
    {
        Log.Warning(logEx, "Failed to log fatal error to database");
    }
    
    checkpoint?.Dispose();
    
    return 1;
}
finally
{
    Log.CloseAndFlush();
}

return 0;
