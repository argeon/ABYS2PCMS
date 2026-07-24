using System.Globalization;
using Microsoft.Data.SqlClient;
using MigrationEngine.Schema;
using MigrationShared.Models;
using Oracle.ManagedDataAccess.Client;
using Serilog;

namespace MigrationEngine.Validation;

public class DataValidator
{
    private readonly string _oracleConnectionString;
    private readonly string _mssqlConnectionString;
    private readonly string _oracleSchema;

    public DataValidator(string oracleConnectionString, string mssqlConnectionString, string oracleSchema)
    {
        _oracleConnectionString = oracleConnectionString;
        _mssqlConnectionString = mssqlConnectionString;
        _oracleSchema = oracleSchema;
    }

    public async Task<ValidationResult> ValidateTableWithPlanAsync(
        TableSchema table,
        long plannerRowCount,
        MigrationConfig migrationConfig,
        CancellationToken ct)
    {
        var result = new ValidationResult { TableName = table.TableName };
        var plan = ValidationRulePlanner.Plan(table, plannerRowCount, migrationConfig);

        try
        {
            foreach (var gate in plan)
            {
                switch (gate)
                {
                    case ValidationGateKind.RowCount:
                        await RunRowCountGateAsync(table.TableName, result, ct);
                        break;
                    case ValidationGateKind.SumIntegerPk:
                        await RunSumIntegerPkGateAsync(table, result, ct);
                        break;
                    case ValidationGateKind.SumDecimalPk:
                        await RunSumDecimalPkGateAsync(table, result, ct);
                        break;
                    case ValidationGateKind.PkMinMaxString:
                        await RunPkMinMaxStringGateAsync(table, result, ct);
                        break;
                    case ValidationGateKind.PkMinMaxDateTime:
                        await RunPkMinMaxDateTimeGateAsync(table, result, ct);
                        break;
                }
            }

            SyncLegacyChecksumFields(result);
            LogTableOutcome(result);
        }
        catch (Exception ex)
        {
            result.ErrorMessage = ex.Message;
            Log.Error(ex, "Validation error for table {Table}", table.TableName);
        }

        return result;
    }

    public async Task<List<ValidationResult>> ValidateAllTablesAsync(
        IReadOnlyList<TableSchema> tables,
        IReadOnlyDictionary<string, long> rowCountsByTable,
        MigrationConfig migrationConfig,
        CancellationToken ct)
    {
        var results = new List<ValidationResult>();
        foreach (var table in tables)
        {
            var rowHint = rowCountsByTable.TryGetValue(table.TableName, out var rc) ? rc : 0L;
            var r = await ValidateTableWithPlanAsync(table, rowHint, migrationConfig, ct);
            results.Add(r);
        }

        return results;
    }

    private static void SyncLegacyChecksumFields(ValidationResult result)
    {
        var sumGate = result.Gates.FirstOrDefault(g => g.GateType == nameof(ValidationGateKind.SumIntegerPk));
        if (sumGate?.OracleValue != null && long.TryParse(sumGate.OracleValue, NumberStyles.Integer, CultureInfo.InvariantCulture, out var oSum))
            result.OracleChecksum = oSum;
        if (sumGate?.MssqlValue != null && long.TryParse(sumGate.MssqlValue, NumberStyles.Integer, CultureInfo.InvariantCulture, out var mSum))
            result.MssqlChecksum = mSum;
    }

    private static void LogTableOutcome(ValidationResult result)
    {
        if (!result.Gates.Any())
            return;

        var rowGate = result.Gates.FirstOrDefault(g => g.GateType == nameof(ValidationGateKind.RowCount));
        if (rowGate?.Passed == true)
            Log.Information("✓ Table {Table} RowCount gate PASSED: {Count}", result.TableName, result.OracleCount);
        else if (rowGate != null)
            Log.Error("✗ Table {Table} RowCount gate FAILED: Oracle={Oracle}, MSSQL={Mssql}",
                result.TableName, rowGate.OracleValue, rowGate.MssqlValue);

        foreach (var g in result.Gates.Where(x => x.GateType != nameof(ValidationGateKind.RowCount)))
        {
            if (g.Passed)
                Log.Information("✓ Table {Table} gate {Gate} PASSED", result.TableName, g.GateType);
            else
                Log.Warning("✗ Table {Table} gate {Gate} FAILED: Oracle={Ov} MSSQL={Mv} {Detail}",
                    result.TableName, g.GateType, g.OracleValue, g.MssqlValue, g.Detail);
        }
    }

    private async Task RunRowCountGateAsync(string tableName, ValidationResult result, CancellationToken ct)
    {
        var oracleCount = await GetOracleCountAsync(tableName, ct);
        var mssqlCount = await GetMssqlCountAsync(tableName, ct);
        result.OracleCount = oracleCount;
        result.MssqlCount = mssqlCount;

        result.Gates.Add(new ValidationGateResult
        {
            GateType = nameof(ValidationGateKind.RowCount),
            Passed = oracleCount == mssqlCount,
            OracleValue = oracleCount.ToString(CultureInfo.InvariantCulture),
            MssqlValue = mssqlCount.ToString(CultureInfo.InvariantCulture)
        });
    }

    private async Task RunSumIntegerPkGateAsync(TableSchema table, ValidationResult result, CancellationToken ct)
    {
        var pkCol = GetSinglePkColumn(table);
        if (pkCol == null || !IsSafeIdentifier(table.TableName) || !IsSafeIdentifier(pkCol))
        {
            result.Gates.Add(new ValidationGateResult
            {
                GateType = nameof(ValidationGateKind.SumIntegerPk),
                Passed = false,
                Detail = "Invalid or missing PK column for SumIntegerPk"
            });
            return;
        }

        long? o = null, m = null;
        try
        {
            o = await GetOracleSumIntAsync(table.TableName, pkCol, ct);
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "Oracle SUM(PK) failed for {Table}", table.TableName);
        }

        try
        {
            m = await GetMssqlSumIntAsync(table.TableName, pkCol, ct);
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "MSSQL SUM(PK) failed for {Table}", table.TableName);
        }

        var passed = o.HasValue && m.HasValue && o.Value == m.Value;
        result.Gates.Add(new ValidationGateResult
        {
            GateType = nameof(ValidationGateKind.SumIntegerPk),
            Passed = passed,
            OracleValue = o?.ToString(CultureInfo.InvariantCulture),
            MssqlValue = m?.ToString(CultureInfo.InvariantCulture),
            Detail = !passed ? "SUM(PK) mismatch or query error" : null
        });
    }

    private async Task RunSumDecimalPkGateAsync(TableSchema table, ValidationResult result, CancellationToken ct)
    {
        var pkCol = GetSinglePkColumn(table);
        if (pkCol == null || !IsSafeIdentifier(table.TableName) || !IsSafeIdentifier(pkCol))
        {
            result.Gates.Add(new ValidationGateResult
            {
                GateType = nameof(ValidationGateKind.SumDecimalPk),
                Passed = false,
                Detail = "Invalid or missing PK column for SumDecimalPk"
            });
            return;
        }

        decimal? o = null, m = null;
        try
        {
            o = await GetOracleSumDecimalAsync(table.TableName, pkCol, ct);
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "Oracle SUM(PK decimal) failed for {Table}", table.TableName);
        }

        try
        {
            m = await GetMssqlSumDecimalAsync(table.TableName, pkCol, ct);
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "MSSQL SUM(PK decimal) failed for {Table}", table.TableName);
        }

        var passed = o.HasValue && m.HasValue && decimal.Round(o.Value, 10) == decimal.Round(m.Value, 10);
        result.Gates.Add(new ValidationGateResult
        {
            GateType = nameof(ValidationGateKind.SumDecimalPk),
            Passed = passed,
            OracleValue = o?.ToString(CultureInfo.InvariantCulture),
            MssqlValue = m?.ToString(CultureInfo.InvariantCulture),
            Detail = !passed ? "SUM(PK decimal) mismatch or query error" : null
        });
    }

    private async Task RunPkMinMaxStringGateAsync(TableSchema table, ValidationResult result, CancellationToken ct)
    {
        var pkCol = GetSinglePkColumn(table);
        if (pkCol == null || !IsSafeIdentifier(table.TableName) || !IsSafeIdentifier(pkCol))
        {
            result.Gates.Add(new ValidationGateResult
            {
                GateType = nameof(ValidationGateKind.PkMinMaxString),
                Passed = false,
                Detail = "Invalid or missing PK column for PkMinMaxString"
            });
            return;
        }

        string? o = null, m = null;
        try
        {
            o = await GetOracleMinMaxStringAsync(table.TableName, pkCol, ct);
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "Oracle MIN/MAX string PK failed for {Table}", table.TableName);
        }

        try
        {
            m = await GetMssqlMinMaxStringAsync(table.TableName, pkCol, ct);
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "MSSQL MIN/MAX string PK failed for {Table}", table.TableName);
        }

        var passed = o != null && m != null && string.Equals(o, m, StringComparison.Ordinal);
        result.Gates.Add(new ValidationGateResult
        {
            GateType = nameof(ValidationGateKind.PkMinMaxString),
            Passed = passed,
            OracleValue = o,
            MssqlValue = m,
            Detail = !passed ? "MIN|MAX PK string fingerprint mismatch" : null
        });
    }

    private async Task RunPkMinMaxDateTimeGateAsync(TableSchema table, ValidationResult result, CancellationToken ct)
    {
        var pkCol = GetSinglePkColumn(table);
        if (pkCol == null || !IsSafeIdentifier(table.TableName) || !IsSafeIdentifier(pkCol))
        {
            result.Gates.Add(new ValidationGateResult
            {
                GateType = nameof(ValidationGateKind.PkMinMaxDateTime),
                Passed = false,
                Detail = "Invalid or missing PK column for PkMinMaxDateTime"
            });
            return;
        }

        string? o = null, m = null;
        try
        {
            o = await GetOracleMinMaxDateAsync(table.TableName, pkCol, ct);
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "Oracle MIN/MAX date PK failed for {Table}", table.TableName);
        }

        try
        {
            m = await GetMssqlMinMaxDateAsync(table.TableName, pkCol, ct);
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "MSSQL MIN/MAX date PK failed for {Table}", table.TableName);
        }

        var passed = o != null && m != null && string.Equals(o, m, StringComparison.Ordinal);
        result.Gates.Add(new ValidationGateResult
        {
            GateType = nameof(ValidationGateKind.PkMinMaxDateTime),
            Passed = passed,
            OracleValue = o,
            MssqlValue = m,
            Detail = !passed ? "MIN|MAX PK date fingerprint mismatch" : null
        });
    }

    private static string? GetSinglePkColumn(TableSchema table)
    {
        var pk = table.Constraints.FirstOrDefault(c =>
            string.Equals(c.ConstraintType, "P", StringComparison.OrdinalIgnoreCase));
        return pk?.Columns.Count == 1 ? pk.Columns[0] : null;
    }

    private static bool IsSafeIdentifier(string name) =>
        !string.IsNullOrEmpty(name) && name.All(c => char.IsLetterOrDigit(c) || c == '_');

    private static string Bracket(string name) => $"[{name.Replace("]", "]]", StringComparison.Ordinal)}]";

    private async Task<long> GetOracleCountAsync(string tableName, CancellationToken ct)
    {
        using var connection = new OracleConnection(_oracleConnectionString);
        await connection.OpenAsync(ct);
        var sql = $"SELECT COUNT(*) FROM {_oracleSchema}.{tableName}";
        using var cmd = new OracleCommand(sql, connection);
        var scalar = await cmd.ExecuteScalarAsync(ct);
        return Convert.ToInt64(scalar);
    }

    private async Task<long> GetMssqlCountAsync(string tableName, CancellationToken ct)
    {
        using var connection = new SqlConnection(_mssqlConnectionString);
        await connection.OpenAsync(ct);
        var sql = $"SELECT COUNT(*) FROM {Bracket(tableName)}";
        using var cmd = new SqlCommand(sql, connection);
        var scalar = await cmd.ExecuteScalarAsync(ct);
        return Convert.ToInt64(scalar);
    }

    private async Task<long?> GetOracleSumIntAsync(string tableName, string pkColumn, CancellationToken ct)
    {
        using var connection = new OracleConnection(_oracleConnectionString);
        await connection.OpenAsync(ct);
        var sql = $"SELECT SUM({pkColumn}) FROM {_oracleSchema}.{tableName}";
        using var cmd = new OracleCommand(sql, connection);
        var result = await cmd.ExecuteScalarAsync(ct);
        if (result == null || result == DBNull.Value)
            return null;
        return Convert.ToInt64(result);
    }

    private async Task<long?> GetMssqlSumIntAsync(string tableName, string pkColumn, CancellationToken ct)
    {
        using var connection = new SqlConnection(_mssqlConnectionString);
        await connection.OpenAsync(ct);
        var sql = $"SELECT SUM(CAST({Bracket(pkColumn)} AS BIGINT)) FROM {Bracket(tableName)}";
        using var cmd = new SqlCommand(sql, connection);
        var result = await cmd.ExecuteScalarAsync(ct);
        if (result == null || result == DBNull.Value)
            return null;
        return Convert.ToInt64(result);
    }

    private async Task<decimal?> GetOracleSumDecimalAsync(string tableName, string pkColumn, CancellationToken ct)
    {
        using var connection = new OracleConnection(_oracleConnectionString);
        await connection.OpenAsync(ct);
        var sql = $"SELECT SUM({pkColumn}) FROM {_oracleSchema}.{tableName}";
        using var cmd = new OracleCommand(sql, connection);
        var result = await cmd.ExecuteScalarAsync(ct);
        if (result == null || result == DBNull.Value)
            return null;
        return Convert.ToDecimal(result, CultureInfo.InvariantCulture);
    }

    private async Task<decimal?> GetMssqlSumDecimalAsync(string tableName, string pkColumn, CancellationToken ct)
    {
        using var connection = new SqlConnection(_mssqlConnectionString);
        await connection.OpenAsync(ct);
        var sql = $"SELECT SUM(CAST({Bracket(pkColumn)} AS decimal(38, 18))) FROM {Bracket(tableName)}";
        using var cmd = new SqlCommand(sql, connection);
        var result = await cmd.ExecuteScalarAsync(ct);
        if (result == null || result == DBNull.Value)
            return null;
        return Convert.ToDecimal(result, CultureInfo.InvariantCulture);
    }

    private async Task<string?> GetOracleMinMaxStringAsync(string tableName, string pkColumn, CancellationToken ct)
    {
        using var connection = new OracleConnection(_oracleConnectionString);
        await connection.OpenAsync(ct);
        var sql = $@"
            SELECT NVL(MIN(TO_CHAR({pkColumn})), '') || '|' || NVL(MAX(TO_CHAR({pkColumn})), '')
            FROM {_oracleSchema}.{tableName}";
        using var cmd = new OracleCommand(sql, connection);
        var result = await cmd.ExecuteScalarAsync(ct);
        return result?.ToString();
    }

    private async Task<string?> GetMssqlMinMaxStringAsync(string tableName, string pkColumn, CancellationToken ct)
    {
        using var connection = new SqlConnection(_mssqlConnectionString);
        await connection.OpenAsync(ct);
        var c = Bracket(pkColumn);
        var t = Bracket(tableName);
        var sql = $@"
            SELECT ISNULL(CONVERT(varchar(max), MIN({c})), '') + '|' + ISNULL(CONVERT(varchar(max), MAX({c})), '')
            FROM {t}";
        using var cmd = new SqlCommand(sql, connection);
        var result = await cmd.ExecuteScalarAsync(ct);
        return result?.ToString();
    }

    private async Task<string?> GetOracleMinMaxDateAsync(string tableName, string pkColumn, CancellationToken ct)
    {
        using var connection = new OracleConnection(_oracleConnectionString);
        await connection.OpenAsync(ct);
        var sql = $@"
            SELECT NVL(TO_CHAR(MIN({pkColumn}), 'YYYY-MM-DD HH24:MI:SS'), '') || '|' ||
                   NVL(TO_CHAR(MAX({pkColumn}), 'YYYY-MM-DD HH24:MI:SS'), '')
            FROM {_oracleSchema}.{tableName}";
        using var cmd = new OracleCommand(sql, connection);
        var result = await cmd.ExecuteScalarAsync(ct);
        return result?.ToString();
    }

    private async Task<string?> GetMssqlMinMaxDateAsync(string tableName, string pkColumn, CancellationToken ct)
    {
        using var connection = new SqlConnection(_mssqlConnectionString);
        await connection.OpenAsync(ct);
        var c = Bracket(pkColumn);
        var t = Bracket(tableName);
        var sql = $@"
            SELECT ISNULL(CONVERT(varchar(30), MIN({c}), 120), '') + '|' + ISNULL(CONVERT(varchar(30), MAX({c}), 120), '')
            FROM {t}";
        using var cmd = new SqlCommand(sql, connection);
        var result = await cmd.ExecuteScalarAsync(ct);
        return result?.ToString();
    }
}
