using Microsoft.Data.SqlClient;
using MigrationShared.Models;
using MigrationShared.Models.TransferStudio;
using Oracle.ManagedDataAccess.Client;

namespace MigrationWeb.Services.TransferStudio;

public class PipelineValidationOrchestrator
{
    private readonly TransferStudioDataService _transferData;
    private readonly OracleCheckpointReader _oracleReader;
    private readonly HistoryDataService _history;

    public PipelineValidationOrchestrator(
        TransferStudioDataService transferData,
        OracleCheckpointReader oracleReader,
        HistoryDataService history)
    {
        _transferData = transferData;
        _oracleReader = oracleReader;
        _history = history;
    }

    public async Task<PipelineValidationRunResult> ValidateProjectAsync(
        int projectId,
        bool includeContent,
        bool includeE2e,
        CancellationToken ct = default)
    {
        var doc = _transferData.GetPipelineDocument(projectId);
        if (doc == null)
            throw new InvalidOperationException("Pipeline projesi bulunamadı.");

        var result = new PipelineValidationRunResult
        {
            ProjectId = projectId,
            EvaluatedAt = DateTime.UtcNow,
            AllPassed = true
        };

        MigrationConfig? oracleConfig = null;
        if (doc.OracleRunId is > 0)
            oracleConfig = _oracleReader.GetRunConfig(doc.OracleRunId.Value);

        foreach (var step in doc.Steps.OrderBy(s => s.SortOrder))
        {
            var recipePair = _transferData.GetRecipe(step.RecipeId);
            if (recipePair == null)
            {
                AddFailedStep(result, step, PipelineStageKind.Stage2_Mssql1ToMssql2_Insert,
                    $"Recipe #{step.RecipeId} bulunamadı.");
                if (doc.FailFast) break;
                continue;
            }

            var recipe = recipePair.Value.doc;
            ApplyConnectionProfiles(recipe);

            // --- Aşama 1: Oracle → MSSQL-1 ---
            if (doc.OracleRunId is > 0 && !string.IsNullOrWhiteSpace(step.OracleTable))
            {
                var stage1 = await ValidateStage1Async(
                    doc.OracleRunId.Value, step, oracleConfig, ct);
                result.Steps.Add(stage1);
                if (!stage1.Passed)
                {
                    result.AllPassed = false;
                    if (doc.FailFast) break;
                }
            }

            // --- Aşama 2: MSSQL-1 → MSSQL-2 INSERT ---
            try
            {
                var stage2 = await ValidateStage2Async(
                    recipe, step, "INSERT", includeContent, ct);
                result.Steps.Add(stage2);
                if (!stage2.Passed)
                {
                    result.AllPassed = false;
                    if (doc.FailFast) break;
                }
            }
            catch (Exception ex)
            {
                AddFailedStep(result, step, PipelineStageKind.Stage2_Mssql1ToMssql2_Insert, ex.Message);
                if (doc.FailFast) break;
            }

            // --- Aşama 3: UPDATE / FK fazı ---
            var hasUpdatePhase = recipe.Phases.Any(p =>
                p.PhaseType == TransferPhaseType.FkResolve && p.FkResolves.Count > 0);

            if (hasUpdatePhase)
            {
                try
                {
                    var stage3 = await ValidateStage2Async(
                        recipe, step, "UPDATE", includeContent, ct);
                    stage3.Stage = PipelineStageKind.Stage3_Mssql1ToMssql2_Update;
                    result.Steps.Add(stage3);
                    if (!stage3.Passed)
                    {
                        result.AllPassed = false;
                        if (doc.FailFast) break;
                    }
                }
                catch (Exception ex)
                {
                    AddFailedStep(result, step, PipelineStageKind.Stage3_Mssql1ToMssql2_Update, ex.Message);
                    if (doc.FailFast) break;
                }
            }

            // --- E2E zincir ---
            if (includeE2e && oracleConfig != null)
            {
                var keys = doc.E2eFixedKeys.Count > 0
                    ? doc.E2eFixedKeys
                    : recipe.Validation.Content.FixedKeys.Select(k => (long)k).ToList();

                if (keys.Count > 0)
                {
                    var e2e = await ValidateE2eAsync(oracleConfig, recipe, step, keys, ct);
                    result.Steps.Add(e2e);
                    if (!e2e.Passed)
                    {
                        result.AllPassed = false;
                        if (doc.FailFast) break;
                    }
                }
            }
        }

        _transferData.SavePipelineValidationRun(result);
        return result;
    }

    private async Task<PipelineStepValidationResult> ValidateStage1Async(
        int oracleRunId,
        PipelineStepDefinition step,
        MigrationConfig? config,
        CancellationToken ct)
    {
        var gates = _oracleReader.GetStage1GatesFromCheckpoint(oracleRunId, step.OracleTable);

        if (gates.Count == 0 && config != null)
            gates = await _oracleReader.RunStage1LiveRowCountAsync(config, step.OracleTable, ct);

        if (gates.Count == 0)
        {
            gates.Add(new ValidationGateOutcome
            {
                GateType = "RowCount",
                Passed = false,
                Detail = "Aşama 1 gate yok ve Oracle run config okunamadı."
            });
        }

        return new PipelineStepValidationResult
        {
            RecipeId = step.RecipeId,
            Label = step.Label ?? step.OracleTable,
            OracleTable = step.OracleTable,
            Stage = PipelineStageKind.Stage1_OracleToMssql1,
            Passed = gates.All(g => g.Passed),
            Gates = gates
        };
    }

    private static async Task<PipelineStepValidationResult> ValidateStage2Async(
        TransferRecipeDocument recipe,
        PipelineStepDefinition step,
        string phase,
        bool includeContent,
        CancellationToken ct)
    {
        var validation = await TransferStudioValidator.ValidateAsync(
            recipe, step.RecipeId, phase, includeContent, ct);

        return new PipelineStepValidationResult
        {
            RecipeId = step.RecipeId,
            Label = step.Label ?? recipe.Name,
            OracleTable = step.OracleTable,
            Stage = phase == "UPDATE"
                ? PipelineStageKind.Stage3_Mssql1ToMssql2_Update
                : PipelineStageKind.Stage2_Mssql1ToMssql2_Insert,
            Passed = validation.AllPassed,
            Gates = validation.Metrics,
            ContentMismatches = validation.ContentMismatches
        };
    }

    private static async Task<PipelineStepValidationResult> ValidateE2eAsync(
        MigrationConfig oracleConfig,
        TransferRecipeDocument recipe,
        PipelineStepDefinition step,
        List<long> keys,
        CancellationToken ct)
    {
        var checks = new List<E2eKeyCheckResult>();
        var schema = oracleConfig.OracleSchema?.ToUpperInvariant() ?? "";
        var oracleTable = step.OracleTable.ToUpperInvariant();
        var pkCol = recipe.Bridge.SourceKeyColumn;
        var srcTable = TransferStudioSqlBuilder.QualifyTable(
            recipe.Endpoints, recipe.Endpoints.SourceSchema, recipe.Endpoints.SourceTable);
        var tgtTable = TransferStudioSqlBuilder.QualifyTargetTable(recipe.Endpoints);
        var tgtBridge = TransferStudioSqlBuilder.Bracket(recipe.Bridge.TargetBridgeColumn);
        var srcKey = TransferStudioSqlBuilder.Bracket(pkCol);

        foreach (var key in keys)
        {
            var check = new E2eKeyCheckResult { Key = key };

            try
            {
                await using var oc = new OracleConnection(oracleConfig.OracleConnectionString);
                await oc.OpenAsync(ct);
                var oSql = string.IsNullOrWhiteSpace(schema)
                    ? $"SELECT COUNT(*) FROM \"{oracleTable}\" WHERE \"{pkCol.ToUpperInvariant()}\" = :k"
                    : $"SELECT COUNT(*) FROM \"{schema}\".\"{oracleTable}\" WHERE \"{pkCol.ToUpperInvariant()}\" = :k";
                await using var oCmd = new OracleCommand(oSql, oc);
                oCmd.Parameters.Add("k", Oracle.ManagedDataAccess.Client.OracleDbType.Int64).Value = key;
                check.OraclePresent = Convert.ToInt64(await oCmd.ExecuteScalarAsync(ct)) > 0;
            }
            catch (Exception ex)
            {
                check.Detail = "Oracle: " + ex.Message;
            }

            if (!string.IsNullOrWhiteSpace(recipe.Endpoints.SourceConnectionString))
            {
                check.Stage1Present = await ExistsAsync(
                    recipe.Endpoints.SourceConnectionString,
                    $"SELECT COUNT_BIG(*) FROM {srcTable} WHERE {srcKey} = @k", key, ct);
            }

            if (!string.IsNullOrWhiteSpace(recipe.Endpoints.TargetConnectionString))
            {
                check.Stage2Present = await ExistsAsync(
                    recipe.Endpoints.TargetConnectionString,
                    $"SELECT COUNT_BIG(*) FROM {tgtTable} WHERE {tgtBridge} = @k", key, ct);
            }

            check.Passed = check.OraclePresent && check.Stage1Present && check.Stage2Present;
            if (!check.Passed && check.Detail == null)
                check.Detail = $"O={check.OraclePresent} M1={check.Stage1Present} M2={check.Stage2Present}";

            checks.Add(check);
        }

        return new PipelineStepValidationResult
        {
            RecipeId = step.RecipeId,
            Label = step.Label ?? recipe.Name,
            OracleTable = step.OracleTable,
            Stage = PipelineStageKind.E2E_Chain,
            Passed = checks.All(c => c.Passed),
            E2eChecks = checks
        };
    }

    private static async Task<bool> ExistsAsync(string cs, string sql, long key, CancellationToken ct)
    {
        await using var conn = new SqlConnection(cs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@k", key);
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct)) > 0;
    }

    private void ApplyConnectionProfiles(TransferRecipeDocument doc)
    {
        if (doc.Endpoints.SourceProfileId is > 0)
        {
            var p = _history.GetConnectionProfiles("MSSQL")
                .FirstOrDefault(x => x.Id == doc.Endpoints.SourceProfileId);
            if (p?.ConnectionString != null)
                doc.Endpoints.SourceConnectionString = p.ConnectionString;
        }

        if (doc.Endpoints.TargetProfileId is > 0)
        {
            var p = _history.GetConnectionProfiles("MSSQL")
                .FirstOrDefault(x => x.Id == doc.Endpoints.TargetProfileId);
            if (p?.ConnectionString != null)
                doc.Endpoints.TargetConnectionString = p.ConnectionString;
        }
    }

    private static void AddFailedStep(
        PipelineValidationRunResult result,
        PipelineStepDefinition step,
        PipelineStageKind stage,
        string error)
    {
        result.AllPassed = false;
        result.Steps.Add(new PipelineStepValidationResult
        {
            RecipeId = step.RecipeId,
            Label = step.Label,
            OracleTable = step.OracleTable,
            Stage = stage,
            Passed = false,
            Error = error
        });
    }
}
