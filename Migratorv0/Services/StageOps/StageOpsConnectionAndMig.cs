using System.Text.Json;
using Microsoft.Data.SqlClient;
using MigrationShared.Models.StageOps;
using Oracle.ManagedDataAccess.Client;

namespace MigrationWeb.Services.StageOps;

public class StageOpsConnectionConfig
{
    public string? OracleSqlplus { get; set; }
    public string? OracleOdp { get; set; }
    public string? MssqlStage1ConnectionString { get; set; }
    public string? MssqlConnectionString { get; set; }
    public string? ProdConnectionString { get; set; }

    public static StageOpsConnectionConfig FromEnvAndFile(string configPath)
    {
        var cfg = new StageOpsConnectionConfig();
        var stageOpsRoot = Path.GetDirectoryName(configPath) ?? ".";
        var connectionsPath = StageOpsConnectionsStore.DefaultPath(stageOpsRoot);
        var saved = StageOpsConnectionsStore.Load(connectionsPath);

        if (!string.IsNullOrWhiteSpace(saved.OracleCtas.SqlplusConnect))
            cfg.OracleSqlplus = saved.OracleCtas.SqlplusConnect;
        if (!string.IsNullOrWhiteSpace(saved.OracleCtas.OdpConnectionString))
            cfg.OracleOdp = saved.OracleCtas.OdpConnectionString;
        if (saved.MssqlStage1.IsConfigured)
            cfg.MssqlStage1ConnectionString = saved.MssqlStage1.ToSqlConnectionString();
        if (saved.MssqlStage2.IsConfigured)
            cfg.MssqlConnectionString = saved.MssqlStage2.ToSqlConnectionString();
        if (saved.MssqlProd.IsConfigured)
            cfg.ProdConnectionString = saved.MssqlProd.ToSqlConnectionString();

        cfg.OracleSqlplus ??= Environment.GetEnvironmentVariable("STAGEOPS_ORACLE_CONN");
        cfg.OracleOdp ??= Environment.GetEnvironmentVariable("STAGEOPS_ORACLE_ODP")
                         ?? Environment.GetEnvironmentVariable("STAGEOPS_ORACLE_CONN_ODP");

        if (File.Exists(configPath))
        {
            try
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(configPath));
                var root = doc.RootElement;
                if (root.TryGetProperty("oracle", out var ora))
                {
                    if (ora.TryGetProperty("connectString", out var cs) && !string.IsNullOrWhiteSpace(cs.GetString()))
                        cfg.OracleSqlplus ??= cs.GetString();
                    if (ora.TryGetProperty("odpConnectionString", out var odp) && !string.IsNullOrWhiteSpace(odp.GetString()))
                        cfg.OracleOdp ??= odp.GetString();
                }

                cfg.MssqlConnectionString ??= BuildSql(root, "mssql", "STAGEOPS_MSSQL");
                cfg.ProdConnectionString ??= BuildSql(root, "prod", "STAGEOPS_PROD");
            }
            catch
            {
                // keep saved/env
            }
        }

        cfg.MssqlConnectionString ??= BuildSqlFromEnv("STAGEOPS_MSSQL");
        cfg.ProdConnectionString ??= BuildSqlFromEnv("STAGEOPS_PROD");
        cfg.MssqlStage1ConnectionString ??= BuildSqlFromEnv("STAGEOPS_MSSQL_STAGE1");
        return cfg;
    }

    private static string? BuildSql(JsonElement root, string section, string envPrefix)
    {
        if (!root.TryGetProperty(section, out var sec)) return BuildSqlFromEnv(envPrefix);
        var server = EnvOr(sec, "server", $"{envPrefix}_SERVER");
        var database = EnvOr(sec, "database", $"{envPrefix}_DATABASE") ?? "energy";
        var user = EnvOr(sec, "user", $"{envPrefix}_USER");
        var password = EnvOr(sec, "password", $"{envPrefix}_PASSWORD");
        if (string.IsNullOrWhiteSpace(server)) return null;
        if (string.IsNullOrWhiteSpace(user))
            return $"Server={server};Database={database};Trusted_Connection=True;TrustServerCertificate=True;";
        return $"Server={server};Database={database};User Id={user};Password={password};TrustServerCertificate=True;";
    }

    private static string? BuildSqlFromEnv(string envPrefix)
    {
        var server = Environment.GetEnvironmentVariable($"{envPrefix}_SERVER");
        if (string.IsNullOrWhiteSpace(server)) return null;
        var database = Environment.GetEnvironmentVariable($"{envPrefix}_DATABASE") ?? "energy";
        var user = Environment.GetEnvironmentVariable($"{envPrefix}_USER");
        var password = Environment.GetEnvironmentVariable($"{envPrefix}_PASSWORD");
        if (string.IsNullOrWhiteSpace(user))
            return $"Server={server};Database={database};Trusted_Connection=True;TrustServerCertificate=True;";
        return $"Server={server};Database={database};User Id={user};Password={password};TrustServerCertificate=True;";
    }

    private static string? EnvOr(JsonElement sec, string prop, string envName)
    {
        var env = Environment.GetEnvironmentVariable(envName);
        if (!string.IsNullOrWhiteSpace(env)) return env;
        if (sec.TryGetProperty(prop, out var p) && !string.IsNullOrWhiteSpace(p.GetString()))
            return p.GetString();
        if (sec.TryGetProperty(prop + "Env", out var e) && e.GetString() is { } en)
        {
            var v = Environment.GetEnvironmentVariable(en);
            if (!string.IsNullOrWhiteSpace(v)) return v;
        }
        return null;
    }
}

public class StageOpsMigLogService
{
    private readonly StageOpsPaths _paths;

    public StageOpsMigLogService(StageOpsPaths paths) => _paths = paths;

    public async Task<object> GetSummaryAsync(string? migrationCode = null, CancellationToken ct = default)
    {
        var cfg = StageOpsConnectionConfig.FromEnvAndFile(Path.Combine(_paths.StageOpsRoot, "stage_ops.config.json"));
        if (string.IsNullOrWhiteSpace(cfg.MssqlConnectionString))
            return new { available = false, message = "STAGEOPS_MSSQL_* bağlantısı yok" };

        await using var conn = new SqlConnection(cfg.MssqlConnectionString);
        await conn.OpenAsync(ct);

        var running = new List<object>();
        await using (var cmd = new SqlCommand(@"
            SELECT TOP 30 MIGRATION_CODE, STATUS, INSERTED_COUNT, SOURCE_ROW_COUNT, SKIPPED_COUNT, ERROR_COUNT,
                   LAST_BRIDGE_KEY, STARTED_AT,
                   CASE WHEN SOURCE_ROW_COUNT > 0 THEN CAST(100.0 * INSERTED_COUNT / SOURCE_ROW_COUNT AS DECIMAL(6,2)) END AS PCT
            FROM energy.dbo.MIG_RUN
            WHERE (@code IS NULL OR MIGRATION_CODE = @code)
            ORDER BY STARTED_AT DESC", conn))
        {
            cmd.Parameters.AddWithValue("@code", (object?)migrationCode ?? DBNull.Value);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                running.Add(new
                {
                    migrationCode = r.IsDBNull(0) ? null : r.GetString(0),
                    status = r.IsDBNull(1) ? null : r.GetString(1),
                    inserted = r.IsDBNull(2) ? 0L : Convert.ToInt64(r.GetValue(2)),
                    sourceRows = r.IsDBNull(3) ? (long?)null : Convert.ToInt64(r.GetValue(3)),
                    skipped = r.IsDBNull(4) ? 0L : Convert.ToInt64(r.GetValue(4)),
                    errors = r.IsDBNull(5) ? 0L : Convert.ToInt64(r.GetValue(5)),
                    lastBridgeKey = r.IsDBNull(6) ? null : r.GetValue(6)?.ToString(),
                    startedAt = r.IsDBNull(7) ? (DateTime?)null : r.GetDateTime(7),
                    pct = r.IsDBNull(8) ? (decimal?)null : r.GetDecimal(8)
                });
            }
        }

        var errors = new List<object>();
        await using (var cmd = new SqlCommand(@"
            SELECT TOP 50 MIGRATION_CODE, PHASE, BATCH_NO, ERROR_MSG, LOGGED_AT
            FROM energy.dbo.MIG_BATCH_LOG
            WHERE STATUS = 'ERROR' AND (@code IS NULL OR MIGRATION_CODE = @code)
            ORDER BY LOGGED_AT DESC", conn))
        {
            cmd.Parameters.AddWithValue("@code", (object?)migrationCode ?? DBNull.Value);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                errors.Add(new
                {
                    migrationCode = r.IsDBNull(0) ? null : r.GetString(0),
                    phase = r.IsDBNull(1) ? null : r.GetString(1),
                    batchNo = r.IsDBNull(2) ? (int?)null : Convert.ToInt32(r.GetValue(2)),
                    error = r.IsDBNull(3) ? null : r.GetString(3),
                    loggedAt = r.IsDBNull(4) ? (DateTime?)null : r.GetDateTime(4)
                });
            }
        }

        return new { available = true, runs = running, batchErrors = errors };
    }
}
