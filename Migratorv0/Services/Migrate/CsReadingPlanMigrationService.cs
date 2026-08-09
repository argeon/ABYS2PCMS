using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Data.SqlClient;
using MigrationEngine.Schema;
using MigrationShared.Enums;
using MigrationShared.Models;
using MigrationWeb.Services;
using Oracle.ManagedDataAccess.Client;

namespace MigrationWeb.Services.Migrate;

public class CsReadingPlanMigrationService
{
    /// <summary>Oracle SMS.CS_READING_PLAN beklenen kolonlar (kaynak DDL).</summary>
    private static readonly string[] ExpectedColumns =
    [
        "ID", "READING_LAYER_ID", "BOOK_ID", "CODE", "READING_DAY",
        "TERMINAL_SYNC_CLIENT_ID", "LOCATION", "MAX_SUBSCRIBER_COUNT",
        "CREATED_USER_ID", "CREATED_TIMESTAMP", "UPDATED_USER_ID", "UPDATED_TIMESTAMP",
        "VERSION", "FIRST_READING_ORDER_NUMBER", "LAST_READING_ORDER_NUMBER",
        "TERMINAL_ORDER", "IS_ACTIVE"
    ];

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    private readonly IWebHostEnvironment _environment;
    private readonly ILogger<CsReadingPlanMigrationService> _logger;

    public CsReadingPlanMigrationService(
        IWebHostEnvironment environment,
        ILogger<CsReadingPlanMigrationService> logger)
    {
        _environment = environment;
        _logger = logger;
    }

    public string EngineDirectory => EngineLauncher.GetEngineDirectory(_environment.ContentRootPath);

    public string DefinitionPath => Path.Combine(EngineDirectory, "migrations", "cs_reading_plan.json");

    public string CheckpointDbPath => Path.GetFullPath(Path.Combine(EngineDirectory, "migration_checkpoint.db"));

    public CsReadingPlanMigrationDefinition LoadDefinition()
    {
        if (!File.Exists(DefinitionPath))
            return new CsReadingPlanMigrationDefinition();

        try
        {
            var json = File.ReadAllText(DefinitionPath);
            return JsonSerializer.Deserialize<CsReadingPlanMigrationDefinition>(json, JsonOptions)
                   ?? new CsReadingPlanMigrationDefinition();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to load CS_READING_PLAN definition — using defaults");
            return new CsReadingPlanMigrationDefinition();
        }
    }

    public async Task SaveDefinitionAsync(CsReadingPlanMigrationDefinition definition, CancellationToken ct = default)
    {
        definition.UpdatedAtUtc = DateTime.UtcNow;
        NormalizeDefinition(definition);
        definition.MssqlConnectionString = EnsureMssqlTrustCert(definition.MssqlConnectionString);

        var dir = Path.GetDirectoryName(DefinitionPath)!;
        Directory.CreateDirectory(dir);

        await File.WriteAllTextAsync(DefinitionPath, JsonSerializer.Serialize(definition, JsonOptions), ct);
        _logger.LogInformation("CS_READING_PLAN definition saved to {Path}", DefinitionPath);
    }

    public MigrationConfig BuildMigrationConfig(CsReadingPlanMigrationDefinition definition)
    {
        NormalizeDefinition(definition);

        var tableName = definition.TargetTableName;
        var locationKey = $"{tableName}.{CsReadingPlanMigrationDefinition.LocationColumn}";
        var sourceSrid = CsReadingPlanMigrationDefinition.DefaultSourceSrid;
        var config = new MigrationConfig
        {
            OracleConnectionString = definition.OracleConnectionString,
            MssqlConnectionString = EnsureMssqlTrustCert(definition.MssqlConnectionString),
            OracleSchema = definition.OracleSchema,
            DegreeOfParallelism = definition.DegreeOfParallelism,
            BatchSize = definition.BatchSize,
            FetchSizeMB = definition.FetchSizeMB,
            Tables = [tableName],
            ExcludeTables = [],
            MigratePrimaryKeys = definition.MigratePrimaryKeys,
            MigrateForeignKeys = definition.MigrateForeignKeys,
            MigrateIndexes = definition.MigrateIndexes,
            MigrateUniqueConstraints = definition.MigrateUniqueConstraints,
            MigrateCheckConstraints = definition.MigrateCheckConstraints,
            MigrateSpatial = true,
            TransformSpatialInOracle = false,
            AutoStart = false,
            SpatialSridOverrides = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
            {
                [locationKey] = sourceSrid
            },
            SpatialTargetSridOverrides = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
            {
                [locationKey] = CsReadingPlanMigrationDefinition.Wgs84Srid
            },
            SpatialReconstructAndTransformInOracle = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                locationKey
            },
            KeepSpatialWktStagingColumns = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                locationKey
            },
            ExtraColumns =
            [
                BuildOkumaBolgeAdiExtraColumn(definition)
            ]
        };

        if (definition.HardReset)
        {
            config.TableRetryModes[tableName] = TableRetryMode.Recreate;
        }

        return config;
    }

    private static ExtraColumnDefinition BuildOkumaBolgeAdiExtraColumn(CsReadingPlanMigrationDefinition definition)
    {
        var schema = string.IsNullOrWhiteSpace(definition.OracleSchema)
            ? CsReadingPlanMigrationDefinition.DefaultOracleSchema
            : definition.OracleSchema.Trim().ToUpperInvariant();
        var period = string.IsNullOrWhiteSpace(definition.ReadingPeriod)
            ? CsReadingPlanMigrationDefinition.DefaultReadingPeriod
            : definition.ReadingPeriod.Trim();
        var periodLiteral = period.Replace("'", "''", StringComparison.Ordinal);

        return new ExtraColumnDefinition
        {
            TableName = CsReadingPlanMigrationDefinition.SourceTable,
            ColumnName = CsReadingPlanMigrationDefinition.OkumaBolgeAdiColumn,
            MssqlType = "NVARCHAR(250)",
            Nullable = true,
            FillAfterLoad = true,
            KeyColumn = "ID",
            OracleSelectExpression =
                "op.CODE || '_' || LPAD(TO_CHAR(t.READING_DAY), 2, '0') || '_' || " +
                "LPAD(TO_CHAR(ROW_NUMBER() OVER (PARTITION BY op.CODE, t.READING_DAY ORDER BY t.ID)), 2, '0')",
            OracleFromJoins =
            [
                $"JOIN {schema}.OPR_SYNC_CLIENT op ON op.ID = t.TERMINAL_SYNC_CLIENT_ID",
                $"JOIN {schema}.CS_READING_LAYER_PRM crlp ON crlp.ID = t.READING_LAYER_ID",
                $"JOIN {schema}.CS_READING_PERIOD rp ON t.READING_DAY = rp.READING_DAY AND rp.PERIOD = '{periodLiteral}'"
            ],
            OracleWhere = "t.IS_ACTIVE = 1 AND crlp.IS_ACTIVE = 1"
        };
    }

    public async Task WriteEngineAppSettingsAsync(MigrationConfig config, CancellationToken ct = default)
    {
        var enginePath = EngineDirectory;
        if (!Directory.Exists(enginePath))
            throw new DirectoryNotFoundException($"MigrationEngine directory not found: {enginePath}");

        var payload = new
        {
            Migration = new
            {
                config.OracleConnectionString,
                config.MssqlConnectionString,
                config.OracleSchema,
                config.DegreeOfParallelism,
                config.BatchSize,
                config.FetchSizeMB,
                config.Tables,
                ExcludeTables = Array.Empty<string>(),
                config.MigrateIndexes,
                MigrateTriggers = false,
                config.MigrateForeignKeys,
                config.MigratePrimaryKeys,
                config.MigrateUniqueConstraints,
                config.MigrateCheckConstraints,
                ValidationMode = ValidationMode.Balanced,
                ValidationMaxRowsForExtendedGates = 5_000_000L,
                ValidatePerTableAfterLoad = false,
                ValidationFailFast = false,
                EnableCompositePkHash = false,
                config.AutoStart,
                ParallelPartitionLoad = false,
                PartitionDegreeOfParallelism = 4,
                UseStagingMerge = false,
                UsePartitionSwitch = false,
                UseBulkLoggedRecovery = true,
                config.TableRetryModes,
                config.MigrateSpatial,
                config.TransformSpatialInOracle,
                config.SpatialSridOverrides,
                config.SpatialTargetSridOverrides,
                config.SpatialReconstructAndTransformInOracle,
                config.KeepSpatialWktStagingColumns,
                config.ExtraColumns
            },
            Checkpoint = new { SqlitePath = "migration_checkpoint.db" },
            Serilog = new
            {
                MinimumLevel = new { Default = "Information" },
                WriteTo = new object[]
                {
                    new { Name = "Console" },
                    new { Name = "File", Args = new { path = "logs/migration-.log", rollingInterval = "Day" } }
                }
            }
        };

        var configPath = Path.Combine(enginePath, "appsettings.json");
        await File.WriteAllTextAsync(configPath, JsonSerializer.Serialize(payload, JsonOptions), ct);
        _logger.LogInformation("Engine appsettings written for CS_READING_PLAN → {Path}", configPath);
    }

    public async Task<object> GetPreviewAsync(CsReadingPlanMigrationDefinition definition, CancellationToken ct = default)
    {
        NormalizeDefinition(definition);

        if (string.IsNullOrWhiteSpace(definition.OracleConnectionString))
            throw new InvalidOperationException("Oracle bağlantı dizesi gerekli.");

        var config = BuildMigrationConfig(definition);
        var schemaReader = new SchemaReader(
            definition.OracleConnectionString,
            definition.OracleSchema,
            migrateSpatial: true);

        var tables = await schemaReader.ReadSchemaAsync(
            [definition.TargetTableName],
            [],
            ct);

        var table = tables.FirstOrDefault()
            ?? throw new InvalidOperationException(
                $"Oracle şemasında {definition.OracleSchema}.{definition.TargetTableName} bulunamadı.");

        var locationCol = table.Columns.FirstOrDefault(c =>
            c.ColumnName.Equals(CsReadingPlanMigrationDefinition.LocationColumn, StringComparison.OrdinalIgnoreCase));

        SpatialMetadataHelper.ApplySridOverrides(table, config);

        var resolvedSourceSrid = locationCol?.Srid 
            ?? CsReadingPlanMigrationDefinition.DefaultSourceSrid;

        var rowCount = await schemaReader.GetTableRowCountAsync(table.TableName, ct);
        var typeMapper = new TypeMapper();
        var foundNames = table.Columns.Select(c => c.ColumnName.ToUpperInvariant()).ToHashSet();
        var missingColumns = ExpectedColumns
            .Where(c => !foundNames.Contains(c))
            .ToList();

        long? targetRowCount = null;
        if (!string.IsNullOrWhiteSpace(definition.MssqlConnectionString))
        {
            try
            {
                var mssqlConn = EnsureMssqlTrustCert(definition.MssqlConnectionString);
                await using var conn = new SqlConnection(mssqlConn);
                await conn.OpenAsync(ct);
                await using var cmd = new SqlCommand(
                    $"SELECT COUNT_BIG(*) FROM [{definition.TargetTableName}]", conn);
                targetRowCount = Convert.ToInt64(await cmd.ExecuteScalarAsync(ct));
            }
            catch
            {
                targetRowCount = null;
            }
        }

        return new
        {
            sourceTable = $"{definition.OracleSchema}.{table.TableName}",
            targetTable = definition.TargetTableName,
            rowCount,
            targetRowCount,
            expectedColumnCount = ExpectedColumns.Length,
            foundColumnCount = table.Columns.Count,
            missingColumns,
            locationFound = locationCol != null,
            locationIsSpatial = locationCol != null && SpatialColumnHelper.IsSpatialColumn(locationCol),
            columns = table.Columns
                .OrderBy(c => c.ColumnId)
                .Select(c =>
                {
                    var mapPrecision = TypeMapper.ResolvePrecisionArgument(
                        c.DataType, c.DataPrecision, c.DataLength);
                    var mapping = typeMapper.MapType(
                        c.DataType, mapPrecision, c.DataScale, c.ColumnName,
                        SpatialColumnHelper.IsSpatialColumn(c), c.Srid);
                    var mssqlTargetType = SpatialColumnHelper.IsSpatialColumn(c)
                        ? (c.SpatialTargetType ?? "geography")
                        : mapping.SqlType;

                    return new
                    {
                        c.ColumnName,
                        oracleType = FormatOracleType(c),
                        c.Nullable,
                        c.IsSpatial,
                        mssqlTargetType,
                        srid = c.Srid,
                        targetSrid = c.SpatialTargetSrid,
                        spatialTargetType = c.SpatialTargetType,
                        isWgs84Location = SpatialColumnHelper.IsSpatialColumn(c)
                            && c.ColumnName.Equals(CsReadingPlanMigrationDefinition.LocationColumn, StringComparison.OrdinalIgnoreCase)
                    };
                }),
            locationMigration = new
            {
                column = CsReadingPlanMigrationDefinition.LocationColumn,
                oracleType = "SDO_GEOMETRY",
                targetType = "geography",
                sourceSrid = resolvedSourceSrid,
                sridResolution = "forced_3857_oracle_reconstruct",
                targetSrid = CsReadingPlanMigrationDefinition.Wgs84Srid,
                oracleExtractSql =
                    "GIS_TO_WKTGEOMETRY(SDO_CS.TRANSFORM(SDO_GEOMETRY(t.LOCATION.SDO_GTYPE, 3857, t.LOCATION.SDO_POINT, t.LOCATION.SDO_ELEM_INFO, t.LOCATION.SDO_ORDINATES), 4326))",
                note = "Oracle: SDO_GEOMETRY(3857) → SDO_CS.TRANSFORM(4326) → GIS_TO_WKTGEOMETRY (t alias); LOCATION__wkt korunur"
            },
            okumaBolgeAdi = new
            {
                column = CsReadingPlanMigrationDefinition.OkumaBolgeAdiColumn,
                readingPeriod = definition.ReadingPeriod,
                formula = "op.CODE || '_' || LPAD(READING_DAY,2,'0') || '_' || LPAD(ROW_NUMBER()...,2,'0')",
                note = "Post-load fill from OPR_SYNC_CLIENT + CS_READING_LAYER_PRM + CS_READING_PERIOD"
            },
            constraints = table.Constraints.Select(c => new
            {
                c.ConstraintName,
                c.ConstraintType,
                columns = c.Columns
            })
        };
    }

    public (bool success, int? pid, string? error) StartEngine(string argument = "--run")
    {
        try
        {
            var startInfo = EngineLauncher.CreateStartInfo(EngineDirectory, argument);
            var process = Process.Start(startInfo);
            if (process == null)
                return (false, null, "Migration Engine process başlatılamadı.");

            _logger.LogInformation(
                "CS_READING_PLAN migration engine started PID={Pid} ({File} {Args})",
                process.Id, startInfo.FileName, startInfo.Arguments);

            return (true, process.Id, null);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to start migration engine for CS_READING_PLAN");
            return (false, null, ex.Message);
        }
    }

    public async Task<long?> GetOracleRowCountAsync(string connectionString, string schema, CancellationToken ct = default)
    {
        await using var conn = new OracleConnection(connectionString);
        await conn.OpenAsync(ct);
        await using var cmd = new OracleCommand(
            "SELECT NVL(NUM_ROWS, 0) FROM ALL_TABLES WHERE OWNER = :owner AND TABLE_NAME = :table", conn);
        cmd.Parameters.Add("owner", OracleDbType.Varchar2).Value = schema.ToUpperInvariant();
        cmd.Parameters.Add("table", OracleDbType.Varchar2).Value = CsReadingPlanMigrationDefinition.SourceTable;
        var result = await cmd.ExecuteScalarAsync(ct);
        return result == null || result == DBNull.Value ? 0 : Convert.ToInt64(result);
    }

    private static void NormalizeDefinition(CsReadingPlanMigrationDefinition definition)
    {
        if (string.IsNullOrWhiteSpace(definition.OracleSchema))
            definition.OracleSchema = CsReadingPlanMigrationDefinition.DefaultOracleSchema;

        definition.TargetTableName = CsReadingPlanMigrationDefinition.SourceTable;

        if (string.IsNullOrWhiteSpace(definition.ReadingPeriod))
            definition.ReadingPeriod = CsReadingPlanMigrationDefinition.DefaultReadingPeriod;

        definition.DegreeOfParallelism = Math.Clamp(definition.DegreeOfParallelism, 1, 32);
        definition.BatchSize = Math.Max(1000, definition.BatchSize);
        definition.FetchSizeMB = Math.Max(1, definition.FetchSizeMB);
    }

    /// <summary>Self-signed / kurumsal CA sertifikalarında SSL login hatasını önler.</summary>
    internal static string EnsureMssqlTrustCert(string connectionString)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            return connectionString;

        var builder = new SqlConnectionStringBuilder(connectionString)
        {
            TrustServerCertificate = true
        };
        return builder.ConnectionString;
    }

    private static string FormatOracleType(ColumnSchema c)
    {
        if (SpatialColumnHelper.IsSpatialColumn(c))
            return "SDO_GEOMETRY";

        if (string.Equals(c.DataType, "NUMBER", StringComparison.OrdinalIgnoreCase)
            && c.DataPrecision.HasValue)
        {
            return c.DataScale.HasValue && c.DataScale > 0
                ? $"NUMBER({c.DataPrecision},{c.DataScale})"
                : $"NUMBER({c.DataPrecision},0)";
        }

        if ((c.DataType.StartsWith("VARCHAR2", StringComparison.OrdinalIgnoreCase)
             || c.DataType.StartsWith("NVARCHAR2", StringComparison.OrdinalIgnoreCase))
            && c.DataLength.HasValue)
            return $"{c.DataType.ToUpperInvariant()}({c.DataLength})";

        if (c.DataType.StartsWith("TIMESTAMP", StringComparison.OrdinalIgnoreCase))
            return c.DataType.ToUpperInvariant();

        return c.DataType.ToUpperInvariant();
    }
}
