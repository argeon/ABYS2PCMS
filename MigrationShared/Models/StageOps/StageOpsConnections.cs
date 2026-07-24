using System.Text.Json;
using System.Text.Json.Serialization;

namespace MigrationShared.Models.StageOps;

public class StageOpsConnectionsDocument
{
    public StageOpsOracleConnection OracleCtas { get; set; } = new();
    /// <summary>MSSQL Stage 1 — kaynak (ör. izgazMGR).</summary>
    public StageOpsMssqlConnection MssqlStage1 { get; set; } = new() { Database = "izgazMGR" };
    /// <summary>MSSQL Stage 2 — hedef / SP runtime (ör. energy).</summary>
    public StageOpsMssqlConnection MssqlStage2 { get; set; } = new() { Database = "energy" };
    /// <summary>Opsiyonel PROD hedef.</summary>
    public StageOpsMssqlConnection MssqlProd { get; set; } = new();
}

public class StageOpsOracleConnection
{
    /// <summary>sqlplus format: user/password@host:port/service</summary>
    public string SqlplusConnect { get; set; } = string.Empty;
    /// <summary>ODP.NET connection string (şema gate).</summary>
    public string OdpConnectionString { get; set; } = string.Empty;
    public int? ProfileId { get; set; }
    public string? ProfileName { get; set; }
}

public class StageOpsMssqlConnection
{
    public string Server { get; set; } = string.Empty;
    public string Database { get; set; } = string.Empty;
    public string User { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    /// <summary>Sql | Windows</summary>
    public string AuthType { get; set; } = "Sql";
    public bool TrustCert { get; set; } = true;
    public int? ProfileId { get; set; }
    public string? ProfileName { get; set; }

    [JsonIgnore]
    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(Server) &&
        !string.IsNullOrWhiteSpace(Database) &&
        (string.Equals(AuthType, "Windows", StringComparison.OrdinalIgnoreCase) ||
         !string.IsNullOrWhiteSpace(User));

    public string ToSqlConnectionString()
    {
        var trust = TrustCert ? "True" : "False";
        if (string.Equals(AuthType, "Windows", StringComparison.OrdinalIgnoreCase) || string.IsNullOrWhiteSpace(User))
            return $"Server={Server};Database={Database};Trusted_Connection=True;TrustServerCertificate={trust};";
        return $"Server={Server};Database={Database};User Id={User};Password={Password};TrustServerCertificate={trust};";
    }
}

public static class StageOpsConnectionsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public static string DefaultPath(string stageOpsRoot) =>
        Path.Combine(stageOpsRoot, "stage_ops.connections.json");

    public static StageOpsConnectionsDocument Load(string path)
    {
        if (!File.Exists(path))
            return new StageOpsConnectionsDocument();
        try
        {
            var doc = JsonSerializer.Deserialize<StageOpsConnectionsDocument>(
                File.ReadAllText(path), JsonOptions);
            return doc ?? new StageOpsConnectionsDocument();
        }
        catch
        {
            return new StageOpsConnectionsDocument();
        }
    }

    public static void Save(string path, StageOpsConnectionsDocument doc)
    {
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);
        File.WriteAllText(path, JsonSerializer.Serialize(doc, JsonOptions));
    }

    public static object StatusSummary(StageOpsConnectionsDocument doc) => new
    {
        oracleCtas = !string.IsNullOrWhiteSpace(doc.OracleCtas.SqlplusConnect),
        mssqlStage1 = doc.MssqlStage1.IsConfigured,
        mssqlStage2 = doc.MssqlStage2.IsConfigured,
        mssqlProd = doc.MssqlProd.IsConfigured,
        oracleHint = string.IsNullOrWhiteSpace(doc.OracleCtas.SqlplusConnect)
            ? "CTAS için Oracle sqlplus bağlantısı tanımlayın"
            : null,
        stage1Hint = !doc.MssqlStage1.IsConfigured ? "MSSQL Stage 1 (izgazMGR) tanımlayın" : null,
        stage2Hint = !doc.MssqlStage2.IsConfigured ? "MSSQL Stage 2 (energy) tanımlayın" : null
    };
}
