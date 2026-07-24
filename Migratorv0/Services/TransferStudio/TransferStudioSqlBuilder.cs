using System.Text;
using MigrationShared.Models.TransferStudio;

namespace MigrationWeb.Services.TransferStudio;

public static class TransferStudioSqlBuilder
{
    public static string QualifyTable(TransferEndpoints ep, string schema, string table) =>
        $"[{ep.SourceDatabase}].[{schema}].[{table}]";

    public static string QualifyTargetTable(TransferEndpoints ep) =>
        $"[{ep.TargetDatabase}].[{ep.TargetSchema}].[{ep.TargetTable}]";

    public static string Bracket(string column) => $"[{column}]";

    public static string BuildSourceFromClause(TransferRecipeDocument recipe)
    {
        var ep = recipe.Endpoints;
        var sb = new StringBuilder();
        sb.Append($"FROM {QualifyTable(ep, ep.SourceSchema, ep.SourceTable)} u");

        var insertPhase = recipe.Phases.FirstOrDefault(p =>
            p.PhaseType == TransferPhaseType.InsertSelect);

        if (insertPhase == null)
            return sb.ToString();

        foreach (var join in insertPhase.SourceJoins)
        {
            var joinTarget = join.IsSubquery
                ? join.TableOrSubquery
                : QualifyTable(ep, ep.SourceSchema, join.TableOrSubquery);
            sb.Append($" LEFT JOIN {joinTarget} {join.Alias} ON {join.JoinCondition}");
        }

        foreach (var lookup in insertPhase.Lookups)
        {
            if (lookup.Rows.Count == 0)
                continue;

            var values = string.Join(", ",
                lookup.Rows.Select(r => $"({r.Key},'{r.Value.Replace("'", "''")}')"));
            sb.Append($" LEFT JOIN (VALUES {values}) {lookup.Name}(REGISTER_TYPE_ID, REG_TYPE) ON {lookup.JoinOn}");
        }

        return sb.ToString();
    }
}
