namespace MigrationShared.Enums;

public enum MigrationPhase
{
    Schema,
    Extract,
    Load,
    Index,
    ForeignKeys,
    Validate
}
