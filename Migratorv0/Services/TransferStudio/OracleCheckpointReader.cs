using System.Text.Json;
using Microsoft.Data.Sqlite;
using MigrationEngine.Checkpoint;
using MigrationShared.Models;
using MigrationShared.Models.TransferStudio;

namespace MigrationWeb.Services.TransferStudio;

/// <summary>
/// Oracle migration checkpoint DB okuyucu — MigrationEngine'e dokunmaz.
/// </summary>
public class OracleCheckpointReader
{
    private readonly string _checkpointDbPath;

    public OracleCheckpointReader(string checkpointDbPath)
    {
        _checkpointDbPath = checkpointDbPath;
    }

    public List<OracleRunSummary> ListOracleRuns(int limit = 30)
    {
        using var conn = Open();
        using var cmd = new SqliteCommand(@"
            SELECT run_id, start_time, status, config_json
            FROM migration_runs
            ORDER BY run_id DESC LIMIT @limit", conn);
        cmd.Parameters.AddWithValue("@limit", limit);

        var list = new List<OracleRunSummary>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            var cfg = TryParseConfig(reader.GetString(3));
            list.Add(new OracleRunSummary
            {
                RunId = reader.GetInt32(0),
                StartedAt = DateTime.Parse(reader.GetString(1)),
                Status = reader.GetString(2),
                OracleSchema = cfg?.OracleSchema ?? "",
                TableCount = cfg?.Tables?.Count ?? 0
            });
        }

        return list;
    }

    public MigrationConfig? GetRunConfig(int runId)
    {
        using var conn = Open();
        using var cmd = new SqliteCommand(
            "SELECT config_json FROM migration_runs WHERE run_id = @id", conn);
        cmd.Parameters.AddWithValue("@id", runId);
        var json = cmd.ExecuteScalar() as string;
        return TryParseConfig(json);
    }

    public List<ValidationGateOutcome> GetStage1GatesFromCheckpoint(int runId, string oracleTable)
    {
        var repo = new ExtendedCheckpointRepository(_checkpointDbPath);
        var records = repo.GetValidationGatesForRun(runId)
            .Where(g => g.TableName.Equals(oracleTable, StringComparison.OrdinalIgnoreCase))
            .ToList();

        if (records.Count == 0)
            return [];

        return records.Select(g => new ValidationGateOutcome
        {
            GateType = g.GateType,
            Passed = g.Passed,
            SourceValue = g.OracleValue,
            TargetValue = g.MssqlValue,
            Detail = g.Message
        }).ToList();
    }

    public async Task<List<ValidationGateOutcome>> RunStage1LiveRowCountAsync(
        MigrationConfig config,
        string oracleTable,
        CancellationToken ct = default)
    {
        var gates = new List<ValidationGateOutcome>();

        long oracleCount = 0;
        long mssqlCount = 0;

        try
        {
            await using var oracle = new Oracle.ManagedDataAccess.Client.OracleConnection(config.OracleConnectionString);
            await oracle.OpenAsync(ct);
            var schema = config.OracleSchema?.Trim();
            if (!string.IsNullOrWhiteSpace(schema))
                schema = schema.ToUpperInvariant();
            var sql = string.IsNullOrWhiteSpace(schema)
                ? $"SELECT COUNT(*) FROM \"{oracleTable.ToUpperInvariant()}\""
                : $"SELECT COUNT(*) FROM \"{schema}\".\"{oracleTable.ToUpperInvariant()}\"";
            await using var oCmd = new Oracle.ManagedDataAccess.Client.OracleCommand(sql, oracle);
            oracleCount = Convert.ToInt64(await oCmd.ExecuteScalarAsync(ct));
        }
        catch (Exception ex)
        {
            gates.Add(new ValidationGateOutcome
            {
                GateType = "RowCount",
                Passed = false,
                Detail = "Oracle sayım hatası: " + ex.Message
            });
            return gates;
        }

        try
        {
            await using var mssql = new Microsoft.Data.SqlClient.SqlConnection(config.MssqlConnectionString);
            await mssql.OpenAsync(ct);
            await using var mCmd = new Microsoft.Data.SqlClient.SqlCommand(
                $"SELECT COUNT_BIG(*) FROM [dbo].[{oracleTable}]", mssql);
            mssqlCount = Convert.ToInt64(await mCmd.ExecuteScalarAsync(ct));
        }
        catch (Exception ex)
        {
            gates.Add(new ValidationGateOutcome
            {
                GateType = "RowCount",
                Passed = false,
                SourceValue = oracleCount.ToString(),
                Detail = "MSSQL-1 sayım hatası: " + ex.Message
            });
            return gates;
        }

        gates.Add(new ValidationGateOutcome
        {
            GateType = "RowCount",
            Passed = oracleCount == mssqlCount,
            SourceValue = oracleCount.ToString(),
            TargetValue = mssqlCount.ToString(),
            Detail = oracleCount == mssqlCount ? "Canlı sayım (checkpoint gate yok)" : $"Fark: {oracleCount - mssqlCount}"
        });

        return gates;
    }

    private SqliteConnection Open()
    {
        var conn = new SqliteConnection($"Data Source={_checkpointDbPath}");
        conn.Open();
        return conn;
    }

    private static MigrationConfig? TryParseConfig(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
            return null;
        try
        {
            return JsonSerializer.Deserialize<MigrationConfig>(json);
        }
        catch
        {
            return null;
        }
    }
}

public class OracleRunSummary
{
    public int RunId { get; set; }
    public DateTime StartedAt { get; set; }
    public string Status { get; set; } = "";
    public string OracleSchema { get; set; } = "";
    public int TableCount { get; set; }
}
