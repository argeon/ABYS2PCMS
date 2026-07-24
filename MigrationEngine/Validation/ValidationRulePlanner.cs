using MigrationEngine.Schema;
using MigrationShared.Models;

namespace MigrationEngine.Validation;

/// <summary>
/// Chooses validation gates from table PK/column types and row volume.
/// </summary>
public static class ValidationRulePlanner
{
    public static IReadOnlyList<ValidationGateKind> Plan(TableSchema table, long rowCount, MigrationConfig cfg)
    {
        var gates = new List<ValidationGateKind> { ValidationGateKind.RowCount };

        if (cfg.ValidationMode == ValidationMode.CountOnly)
            return gates;

        if (rowCount == 0)
            return gates;

        var skipExtended = cfg.ValidationMode == ValidationMode.Balanced
            && rowCount > cfg.ValidationMaxRowsForExtendedGates;

        if (skipExtended)
            return gates;

        var pk = table.Constraints.FirstOrDefault(c =>
            string.Equals(c.ConstraintType, "P", StringComparison.OrdinalIgnoreCase));

        if (pk == null || pk.Columns.Count != 1)
            return gates;

        var pkColName = pk.Columns[0];
        var col = table.Columns.FirstOrDefault(c =>
            c.ColumnName.Equals(pkColName, StringComparison.OrdinalIgnoreCase));

        if (col == null)
            return gates;

        var dt = col.DataType.ToUpperInvariant();

        if (dt == "NUMBER")
        {
            var scale = col.DataScale ?? 0;
            if (scale == 0)
                gates.Add(ValidationGateKind.SumIntegerPk);
            else
                gates.Add(ValidationGateKind.SumDecimalPk);
            return gates;
        }

        if (IsStringType(dt))
        {
            gates.Add(ValidationGateKind.PkMinMaxString);
            return gates;
        }

        if (IsDateTimeType(dt))
        {
            gates.Add(ValidationGateKind.PkMinMaxDateTime);
            return gates;
        }

        return gates;
    }

    private static bool IsStringType(string dt) =>
        dt is "VARCHAR2" or "CHAR" or "NVARCHAR2" or "NCHAR" or "VARCHAR" or "NVARCHAR";

    private static bool IsDateTimeType(string dt) =>
        dt == "DATE" || dt.StartsWith("TIMESTAMP", StringComparison.Ordinal);
}
