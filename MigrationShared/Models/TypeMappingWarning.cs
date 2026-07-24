namespace MigrationShared.Models;

public class TypeMappingWarning
{
    public string TableName { get; set; } = string.Empty;
    public string ColumnName { get; set; } = string.Empty;
    public string OracleType { get; set; } = string.Empty;
    public string MssqlType { get; set; } = string.Empty;
    public string WarningMessage { get; set; } = string.Empty;
}
