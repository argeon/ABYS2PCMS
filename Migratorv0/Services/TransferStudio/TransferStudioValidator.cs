using System.Globalization;
using Microsoft.Data.SqlClient;
using MigrationShared.Models.TransferStudio;

namespace MigrationWeb.Services.TransferStudio;

/// <summary>
/// MSSQL-only validation — Oracle kod yollarına dokunmaz.
/// </summary>
public static class TransferStudioValidator
{
    public static async Task<TransferValidationRunResult> ValidateAsync(
        TransferRecipeDocument recipe,
        int recipeId,
        string phase,
        bool includeContent,
        CancellationToken ct = default)
    {
        var result = new TransferValidationRunResult
        {
            RecipeId = recipeId,
            Phase = phase,
            EvaluatedAt = DateTime.UtcNow,
            AllPassed = true
        };

        var srcCs = recipe.Endpoints.SourceConnectionString;
        var tgtCs = recipe.Endpoints.TargetConnectionString;
        if (string.IsNullOrWhiteSpace(srcCs) || string.IsNullOrWhiteSpace(tgtCs))
            throw new InvalidOperationException("Kaynak ve hedef bağlantı dizgileri tanımlı olmalı.");

        var srcKey = TransferStudioSqlBuilder.Bracket(recipe.Bridge.SourceKeyColumn);
        var tgtBridge = TransferStudioSqlBuilder.Bracket(recipe.Bridge.TargetBridgeColumn);
        var srcTable = TransferStudioSqlBuilder.QualifyTable(recipe.Endpoints, recipe.Endpoints.SourceSchema, recipe.Endpoints.SourceTable);
        var tgtTable = TransferStudioSqlBuilder.QualifyTargetTable(recipe.Endpoints);
        var srcFilter = string.IsNullOrWhiteSpace(recipe.Bridge.SourceFilter) ? "" : $" WHERE {recipe.Bridge.SourceFilter}";

        foreach (var metric in recipe.Validation.Metrics.Where(m => m.Enabled))
        {
            var gate = metric.GateType switch
            {
                MetricGateType.RowCount => await RunRowCountAsync(srcCs, tgtCs, srcTable, tgtTable, srcFilter, ct),
                MetricGateType.MissingByBridge => await RunMissingByBridgeAsync(
                    srcCs, tgtCs, srcTable, tgtTable, srcKey, tgtBridge, srcFilter, ct),
                MetricGateType.BridgeNotNull => await RunBridgeNotNullAsync(tgtCs, tgtTable, tgtBridge, ct),
                MetricGateType.SumBridgeKey => await RunSumBridgeAsync(
                    srcCs, tgtCs, srcTable, tgtTable, srcKey, tgtBridge, srcFilter, ct),
                MetricGateType.CustomSql => await RunCustomSqlAsync(metric, srcCs, tgtCs, ct),
                _ => new ValidationGateOutcome { GateType = metric.GateType.ToString(), Passed = true }
            };

            result.Metrics.Add(gate);
            if (!gate.Passed)
                result.AllPassed = false;
        }

        if (includeContent && recipe.Validation.Content.Enabled && recipe.Validation.Content.Rules.Count > 0)
        {
            var mismatches = await RunContentSampleAsync(recipe, srcTable, tgtTable, phase, ct);
            result.ContentMismatches.AddRange(mismatches);
            if (mismatches.Count > 0)
                result.AllPassed = false;
        }

        return result;
    }

    private static async Task<ValidationGateOutcome> RunRowCountAsync(
        string srcCs, string tgtCs, string srcTable, string tgtTable, string srcFilter, CancellationToken ct)
    {
        var srcCount = await ScalarLongAsync(srcCs, $"SELECT COUNT_BIG(*) FROM {srcTable}{srcFilter}", ct);
        var tgtCount = await ScalarLongAsync(tgtCs, $"SELECT COUNT_BIG(*) FROM {tgtTable}", ct);
        return new ValidationGateOutcome
        {
            GateType = nameof(MetricGateType.RowCount),
            Passed = srcCount == tgtCount,
            SourceValue = srcCount.ToString(CultureInfo.InvariantCulture),
            TargetValue = tgtCount.ToString(CultureInfo.InvariantCulture),
            Detail = srcCount == tgtCount ? null : $"Fark: {srcCount - tgtCount}"
        };
    }

    private static async Task<ValidationGateOutcome> RunMissingByBridgeAsync(
        string srcCs, string tgtCs, string srcTable, string tgtTable,
        string srcKey, string tgtBridge, string srcFilter, CancellationToken ct)
    {
        var filterExpr = srcFilter.Trim();
        if (filterExpr.StartsWith("WHERE", StringComparison.OrdinalIgnoreCase))
            filterExpr = filterExpr[5..].Trim();

        var whereCore = string.IsNullOrWhiteSpace(filterExpr)
            ? $"NOT EXISTS (SELECT 1 FROM {tgtTable} t WHERE t.{tgtBridge} = s.{srcKey})"
            : $"({filterExpr}) AND NOT EXISTS (SELECT 1 FROM {tgtTable} t WHERE t.{tgtBridge} = s.{srcKey})";

        var sql = $@"
            SELECT COUNT_BIG(*)
            FROM {srcTable} s
            WHERE {whereCore}";

        long missing;
        try
        {
            missing = await ScalarLongAsync(srcCs, sql, ct);
        }
        catch
        {
            // Farklı sunucular: kaynak key'leri hedefte tek tek kontrol (örneklem üst sınırı)
            missing = await CountMissingBridgeAppSideAsync(srcCs, tgtCs, srcTable, tgtTable, srcKey, tgtBridge, filterExpr, ct);
        }

        return new ValidationGateOutcome
        {
            GateType = nameof(MetricGateType.MissingByBridge),
            Passed = missing == 0,
            SourceValue = missing.ToString(CultureInfo.InvariantCulture),
            TargetValue = "0",
            Detail = missing == 0 ? null : $"{missing} kaynak satırı hedefte yok"
        };
    }

    private static async Task<long> CountMissingBridgeAppSideAsync(
        string srcCs, string tgtCs, string srcTable, string tgtTable,
        string srcKey, string tgtBridge, string filterExpr, CancellationToken ct)
    {
        var where = string.IsNullOrWhiteSpace(filterExpr) ? "" : $"WHERE {filterExpr}";
        var keys = await QueryLongListAsync(srcCs, $"SELECT TOP (10000) {srcKey} FROM {srcTable} {where}", ct);
        long missing = 0;
        foreach (var key in keys)
        {
            var count = await ScalarLongParamAsync(tgtCs,
                $"SELECT COUNT_BIG(*) FROM {tgtTable} WHERE {tgtBridge} = @key", key, ct);
            if (count == 0)
                missing++;
        }

        return missing;
    }

    private static async Task<ValidationGateOutcome> RunBridgeNotNullAsync(
        string tgtCs, string tgtTable, string tgtBridge, CancellationToken ct)
    {
        var total = await ScalarLongAsync(tgtCs, $"SELECT COUNT_BIG(*) FROM {tgtTable}", ct);
        var filled = await ScalarLongAsync(tgtCs,
            $"SELECT COUNT_BIG(*) FROM {tgtTable} WHERE {tgtBridge} IS NOT NULL", ct);
        return new ValidationGateOutcome
        {
            GateType = nameof(MetricGateType.BridgeNotNull),
            Passed = total == filled,
            SourceValue = total.ToString(CultureInfo.InvariantCulture),
            TargetValue = filled.ToString(CultureInfo.InvariantCulture),
            Detail = total == filled ? null : $"{total - filled} satırda bridge boş"
        };
    }

    private static async Task<ValidationGateOutcome> RunSumBridgeAsync(
        string srcCs, string tgtCs, string srcTable, string tgtTable,
        string srcKey, string tgtBridge, string srcFilter, CancellationToken ct)
    {
        var srcSql = $"SELECT ISNULL(SUM(CAST({srcKey} AS BIGINT)), 0) FROM {srcTable}{srcFilter}";
        var tgtSql = $"SELECT ISNULL(SUM(CAST({tgtBridge} AS BIGINT)), 0) FROM {tgtTable}";
        var srcSum = await ScalarLongAsync(srcCs, srcSql, ct);
        var tgtSum = await ScalarLongAsync(tgtCs, tgtSql, ct);
        return new ValidationGateOutcome
        {
            GateType = nameof(MetricGateType.SumBridgeKey),
            Passed = srcSum == tgtSum,
            SourceValue = srcSum.ToString(CultureInfo.InvariantCulture),
            TargetValue = tgtSum.ToString(CultureInfo.InvariantCulture)
        };
    }

    private static async Task<ValidationGateOutcome> RunCustomSqlAsync(
        MetricValidationRule metric, string srcCs, string tgtCs, CancellationToken ct)
    {
        var srcVal = string.IsNullOrWhiteSpace(metric.SourceSql)
            ? null
            : (await ScalarObjectAsync(srcCs, metric.SourceSql!, ct))?.ToString();
        var tgtVal = string.IsNullOrWhiteSpace(metric.TargetSql)
            ? null
            : (await ScalarObjectAsync(tgtCs, metric.TargetSql!, ct))?.ToString();
        var passed = string.Equals(srcVal, tgtVal, StringComparison.Ordinal);
        return new ValidationGateOutcome
        {
            GateType = nameof(MetricGateType.CustomSql),
            Passed = passed,
            SourceValue = srcVal,
            TargetValue = tgtVal
        };
    }

    private static async Task<List<ContentMismatchRow>> RunContentSampleAsync(
        TransferRecipeDocument recipe, string srcTable, string tgtTable, string phase, CancellationToken ct)
    {
        var content = recipe.Validation.Content;
        var rules = content.Rules
            .Where(r => string.IsNullOrWhiteSpace(r.ValidateAfterPhase)
                        || r.ValidateAfterPhase.Equals(phase, StringComparison.OrdinalIgnoreCase)
                        || phase.Equals("ALL", StringComparison.OrdinalIgnoreCase))
            .ToList();
        if (rules.Count == 0)
            return [];

        var srcKey = TransferStudioSqlBuilder.Bracket(recipe.Bridge.SourceKeyColumn);
        var tgtBridge = TransferStudioSqlBuilder.Bracket(recipe.Bridge.TargetBridgeColumn);
        var max = content.MaxReportedMismatches;
        var mismatches = new List<ContentMismatchRow>();

        List<long> sampleKeys;
        if (content.Strategy == ContentCompareStrategy.FixedKeys && content.FixedKeys.Count > 0)
            sampleKeys = content.FixedKeys.Select(k => (long)k).ToList();
        else
        {
            var top = Math.Max(1, Math.Min(content.SampleSize, 500));
            var keySql = $@"
                SELECT TOP ({top}) {srcKey}
                FROM {srcTable}
                ORDER BY NEWID()";
            sampleKeys = await QueryLongListAsync(recipe.Endpoints.SourceConnectionString, keySql, ct);
        }

        foreach (var key in sampleKeys)
        {
            var fromClause = TransferStudioSqlBuilder.BuildSourceFromClause(recipe);
            foreach (var rule in rules)
            {
                var srcSql = $"SELECT CAST(({rule.SourceExpression}) AS NVARCHAR(4000)) {fromClause} WHERE u.{srcKey} = @key";
                var tgtSql = $"SELECT CAST(({rule.TargetExpression}) AS NVARCHAR(4000)) FROM {tgtTable} t WHERE t.{tgtBridge} = @key";

                var srcVal = await ScalarStringParamAsync(recipe.Endpoints.SourceConnectionString, srcSql, key, ct);
                var tgtVal = await ScalarStringParamAsync(recipe.Endpoints.TargetConnectionString, tgtSql, key, ct);

                if (!ValuesMatch(srcVal, tgtVal, rule))
                {
                    mismatches.Add(new ContentMismatchRow
                    {
                        BridgeKey = key.ToString(CultureInfo.InvariantCulture),
                        ColumnLabel = rule.Label,
                        SourceValue = srcVal,
                        TargetValue = tgtVal,
                        CompareAs = rule.CompareAs.ToString(),
                        Phase = phase
                    });

                    if (mismatches.Count >= max)
                        return mismatches;
                }
            }
        }

        return mismatches;
    }

    private static bool ValuesMatch(string? src, string? tgt, ContentCompareRule rule) =>
        rule.CompareAs switch
        {
            ContentCompareKind.StringTrimIgnoreCase =>
                string.Equals(Normalize(src), Normalize(tgt), StringComparison.OrdinalIgnoreCase),
            ContentCompareKind.Decimal when decimal.TryParse(src, NumberStyles.Any, CultureInfo.InvariantCulture, out var s)
                                           && decimal.TryParse(tgt, NumberStyles.Any, CultureInfo.InvariantCulture, out var t) =>
                Math.Abs(s - t) <= (rule.Tolerance ?? 0m),
            ContentCompareKind.DateOnly =>
                string.Equals(ParseDate(src)?.ToString("yyyy-MM-dd"), ParseDate(tgt)?.ToString("yyyy-MM-dd"), StringComparison.Ordinal),
            ContentCompareKind.NullEquivalent =>
                string.IsNullOrWhiteSpace(src) && string.IsNullOrWhiteSpace(tgt),
            _ => string.Equals(src ?? "", tgt ?? "", StringComparison.Ordinal)
        };

    private static string? Normalize(string? v) => v?.Trim();

    private static DateTime? ParseDate(string? v) =>
        DateTime.TryParse(v, CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out var d) ? d : null;

    private static string Qualify(string database, string schema, string table) =>
        $"[{database}].[{schema}].[{table}]";

    private static async Task<long> ScalarLongParamAsync(string cs, string sql, long key, CancellationToken ct)
    {
        await using var conn = new SqlConnection(cs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 120 };
        cmd.Parameters.AddWithValue("@key", key);
        var o = await cmd.ExecuteScalarAsync(ct);
        return o == null || o == DBNull.Value ? 0L : Convert.ToInt64(o, CultureInfo.InvariantCulture);
    }

    private static async Task<long> ScalarLongAsync(string cs, string sql, CancellationToken ct)
    {
        var o = await ScalarObjectAsync(cs, sql, ct);
        return o == null || o == DBNull.Value ? 0L : Convert.ToInt64(o, CultureInfo.InvariantCulture);
    }

    private static async Task<object?> ScalarObjectAsync(string cs, string sql, CancellationToken ct)
    {
        await using var conn = new SqlConnection(cs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 120 };
        return await cmd.ExecuteScalarAsync(ct);
    }

    private static async Task<string?> ScalarStringParamAsync(string cs, string sql, long key, CancellationToken ct)
    {
        await using var conn = new SqlConnection(cs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 120 };
        cmd.Parameters.AddWithValue("@key", key);
        var o = await cmd.ExecuteScalarAsync(ct);
        return o == null || o == DBNull.Value ? null : Convert.ToString(o, CultureInfo.InvariantCulture);
    }

    private static async Task<List<long>> QueryLongListAsync(string cs, string sql, CancellationToken ct)
    {
        var list = new List<long>();
        await using var conn = new SqlConnection(cs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 120 };
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
            list.Add(reader.GetInt64(0));
        return list;
    }
}
