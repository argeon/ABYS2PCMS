namespace MigrationEngine.Checkpoint;

public static class CheckpointSchema
{
    public const string CreateMigrationRunsTable = @"
        CREATE TABLE IF NOT EXISTS migration_runs (
            run_id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time TEXT NOT NULL,
            config_json TEXT NOT NULL,
            status TEXT NOT NULL
        );";

    public const string CreateTableCheckpointsTable = @"
        CREATE TABLE IF NOT EXISTS table_checkpoints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL,
            table_name TEXT NOT NULL,
            partition_key TEXT NOT NULL,
            status TEXT NOT NULL,
            rows_processed INTEGER DEFAULT 0,
            total_rows INTEGER DEFAULT 0,
            start_time TEXT,
            end_time TEXT,
            error_message TEXT,
            start_pk INTEGER,
            end_pk INTEGER,
            UNIQUE(run_id, table_name, partition_key)
        );";

    // Mevcut DB'lere kolon eklemek için migration SQL'leri
    public const string MigrateAddStartPk = "ALTER TABLE table_checkpoints ADD COLUMN start_pk INTEGER;";
    public const string MigrateAddEndPk   = "ALTER TABLE table_checkpoints ADD COLUMN end_pk INTEGER;";

    public const string CreateProgressEventsTable = @"
        CREATE TABLE IF NOT EXISTS progress_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL,
            timestamp TEXT NOT NULL,
            table_name TEXT,
            partition_key TEXT,
            phase TEXT,
            status TEXT,
            rows_processed INTEGER,
            total_rows INTEGER,
            rows_per_second REAL,
            message TEXT,
            warning TEXT
        );";

    public const string CreateIndexes = @"
        CREATE INDEX IF NOT EXISTS idx_progress_timestamp ON progress_events(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_table_status ON table_checkpoints(run_id, table_name, status);";

    public static string[] GetSchemaCommands() => new[]
    {
        CreateMigrationRunsTable,
        CreateTableCheckpointsTable,
        CreateProgressEventsTable,
        CreateIndexes
    };
}
