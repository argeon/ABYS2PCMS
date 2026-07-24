using Microsoft.Data.SqlClient;
using MigrationShared.Models;
using Oracle.ManagedDataAccess.Client;
using Serilog;
using System.Data;
using System.Globalization;
using System.Text;

namespace MigrationEngine.Loaders;

/// <summary>
/// Fills extra MSSQL columns from a full-table Oracle SELECT (joins + analytic functions).
/// </summary>
public class ExtraColumnPostLoader
{
    private const int BatchSize = 500;

    private readonly string _oracleConnectionString;
    private readonly string _mssqlConnectionString;
    private readonly string _oracleSchema;

    public ExtraColumnPostLoader(
        string oracleConnectionString,
        string mssqlConnectionString,
        string oracleSchema)
    {
        _oracleConnectionString = oracleConnectionString;
        _mssqlConnectionString = mssqlConnectionString;
        _oracleSchema = oracleSchema;
    }

    public async Task FillExtraColumnsAsync(
        string tableName,
        IReadOnlyList<ExtraColumnDefinition> columns,
        CancellationToken ct)
    {
        foreach (var column in columns)
            await FillOneAsync(tableName, column, ct);
    }

    private async Task FillOneAsync(string tableName, ExtraColumnDefinition column, CancellationToken ct)
    {
        var keyCol = string.IsNullOrWhiteSpace(column.KeyColumn) ? "ID" : column.KeyColumn;
        var schema = QuoteOracleIdentifier(_oracleSchema);
        var table = QuoteOracleIdentifier(tableName);
        var keyQuoted = QuoteOracleIdentifier(keyCol);

        var joins = column.OracleFromJoins.Count == 0
            ? string.Empty
            : Environment.NewLine + string.Join(Environment.NewLine, column.OracleFromJoins);
        var where = string.IsNullOrWhiteSpace(column.OracleWhere)
            ? string.Empty
            : Environment.NewLine + "WHERE " + column.OracleWhere;

        var sql = $@"
SELECT t.{keyQuoted} AS KEY_VAL, ({column.OracleSelectExpression}) AS EXTRA_VAL
FROM {schema}.{table} t{joins}{where}";

        Log.Information(
            "Filling extra column [{Table}].[{Column}] from Oracle (joins={JoinCount})",
            tableName, column.ColumnName, column.OracleFromJoins.Count);

        await using var oracle = new OracleConnection(_oracleConnectionString);
        await oracle.OpenAsync(ct);
        await using var cmd = oracle.CreateCommand();
        cmd.CommandText = sql;
        cmd.CommandTimeout = 0;
        cmd.FetchSize = 50 * 1024 * 1024;

        await using var reader = await cmd.ExecuteReaderAsync(CommandBehavior.SequentialAccess, ct);
        await using var mssql = new SqlConnection(_mssqlConnectionString);
        await mssql.OpenAsync(ct);

        var batch = new List<(object Key, string? Value)>(BatchSize);
        long total = 0;

        while (await reader.ReadAsync(ct))
        {
            var key = reader.GetValue(0);
            var value = reader.IsDBNull(1) ? null : Convert.ToString(reader.GetValue(1), CultureInfo.InvariantCulture);
            batch.Add((key, value));

            if (batch.Count >= BatchSize)
            {
                total += await FlushBatchAsync(mssql, tableName, column.ColumnName, keyCol, batch, ct);
                batch.Clear();
            }
        }

        if (batch.Count > 0)
            total += await FlushBatchAsync(mssql, tableName, column.ColumnName, keyCol, batch, ct);

        Log.Information(
            "Filled {Rows:N0} row(s) for [{Table}].[{Column}]",
            total, tableName, column.ColumnName);
    }

    private static async Task<long> FlushBatchAsync(
        SqlConnection mssql,
        string tableName,
        string columnName,
        string keyColumn,
        List<(object Key, string? Value)> batch,
        CancellationToken ct)
    {
        var sb = new StringBuilder();
        sb.AppendLine("CREATE TABLE #upd (KeyVal BIGINT NOT NULL, ExtraVal NVARCHAR(250) NULL);");
        sb.AppendLine("INSERT INTO #upd (KeyVal, ExtraVal) VALUES");

        for (var i = 0; i < batch.Count; i++)
        {
            if (i > 0) sb.Append(',');
            var keyLiteral = Convert.ToInt64(batch[i].Key, CultureInfo.InvariantCulture)
                .ToString(CultureInfo.InvariantCulture);
            var val = batch[i].Value;
            var valLiteral = val == null
                ? "NULL"
                : "N'" + val.Replace("'", "''", StringComparison.Ordinal) + "'";
            sb.AppendLine($"({keyLiteral},{valLiteral})");
        }

        sb.AppendLine(";");
        sb.AppendLine($@"
UPDATE t
SET t.[{columnName}] = u.ExtraVal
FROM [{tableName}] t
INNER JOIN #upd u ON t.[{keyColumn}] = u.KeyVal;
DROP TABLE #upd;");

        await using var cmd = new SqlCommand(sb.ToString(), mssql) { CommandTimeout = 0 };
        await cmd.ExecuteNonQueryAsync(ct);
        return batch.Count;
    }

    private static string QuoteOracleIdentifier(string name)
    {
        if (string.IsNullOrEmpty(name))
            return name;

        if (name.All(c => char.IsLetterOrDigit(c) || c == '_' || c == '$' || c == '#'))
            return name.ToUpperInvariant();

        return $"\"{name.Replace("\"", "\"\"", StringComparison.Ordinal)}\"";
    }
}
