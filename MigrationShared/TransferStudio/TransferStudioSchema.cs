namespace MigrationShared.TransferStudio;

public static class TransferStudioSchema
{
    public const string CreateRecipesTable = @"
        CREATE TABLE IF NOT EXISTS transfer_recipes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            migration_id TEXT NOT NULL,
            name TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'Draft',
            version INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0,
            config_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );";

    public const string CreateRecipesMigrationIdIndex = @"
        CREATE UNIQUE INDEX IF NOT EXISTS idx_transfer_recipes_migration_id
        ON transfer_recipes(migration_id);";

    public const string CreateRunsTable = @"
        CREATE TABLE IF NOT EXISTS transfer_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recipe_id INTEGER NOT NULL,
            run_uuid TEXT NOT NULL,
            execution_mode TEXT NOT NULL,
            phase TEXT NOT NULL DEFAULT 'ALL',
            status TEXT NOT NULL DEFAULT 'Queued',
            params_json TEXT,
            total_ok INTEGER NOT NULL DEFAULT 0,
            total_error INTEGER NOT NULL DEFAULT 0,
            last_bridge_key TEXT,
            started_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            completed_at TEXT,
            FOREIGN KEY (recipe_id) REFERENCES transfer_recipes(id)
        );";

    public const string CreateRunsIndex = @"
        CREATE INDEX IF NOT EXISTS idx_transfer_runs_recipe
        ON transfer_runs(recipe_id, started_at DESC);";

    public const string CreateCheckpointsTable = @"
        CREATE TABLE IF NOT EXISTS transfer_checkpoints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL,
            phase TEXT NOT NULL,
            last_bridge_key TEXT,
            batch_no INTEGER NOT NULL DEFAULT 0,
            total_ok INTEGER NOT NULL DEFAULT 0,
            total_error INTEGER NOT NULL DEFAULT 0,
            completed INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (run_id) REFERENCES transfer_runs(id)
        );";

    public const string CreateEventLogTable = @"
        CREATE TABLE IF NOT EXISTS transfer_event_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL,
            level TEXT NOT NULL DEFAULT 'Info',
            phase TEXT,
            batch_no INTEGER,
            bridge_from TEXT,
            bridge_to TEXT,
            bridge_key TEXT,
            message TEXT NOT NULL,
            row_count INTEGER,
            created_at TEXT NOT NULL,
            FOREIGN KEY (run_id) REFERENCES transfer_runs(id)
        );";

    public const string CreateEventLogIndex = @"
        CREATE INDEX IF NOT EXISTS idx_transfer_event_log_run
        ON transfer_event_log(run_id, id DESC);";

    public const string CreateValidationRunsTable = @"
        CREATE TABLE IF NOT EXISTS transfer_validation_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recipe_id INTEGER NOT NULL,
            transfer_run_id INTEGER,
            phase TEXT NOT NULL,
            all_passed INTEGER NOT NULL,
            evaluated_at TEXT NOT NULL,
            FOREIGN KEY (recipe_id) REFERENCES transfer_recipes(id),
            FOREIGN KEY (transfer_run_id) REFERENCES transfer_runs(id)
        );";

    public const string CreateValidationGatesTable = @"
        CREATE TABLE IF NOT EXISTS transfer_validation_gates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            validation_run_id INTEGER NOT NULL,
            gate_type TEXT NOT NULL,
            passed INTEGER NOT NULL,
            source_value TEXT,
            target_value TEXT,
            detail TEXT,
            FOREIGN KEY (validation_run_id) REFERENCES transfer_validation_runs(id)
        );";

    public const string CreateContentMismatchesTable = @"
        CREATE TABLE IF NOT EXISTS transfer_content_mismatches (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            validation_run_id INTEGER NOT NULL,
            bridge_key TEXT NOT NULL,
            column_label TEXT NOT NULL,
            source_value TEXT,
            target_value TEXT,
            compare_as TEXT NOT NULL,
            phase TEXT,
            FOREIGN KEY (validation_run_id) REFERENCES transfer_validation_runs(id)
        );";

    public const string CreatePipelineProjectsTable = @"
        CREATE TABLE IF NOT EXISTS pipeline_projects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            config_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );";

    public const string CreatePipelineValidationRunsTable = @"
        CREATE TABLE IF NOT EXISTS pipeline_validation_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL,
            all_passed INTEGER NOT NULL,
            result_json TEXT NOT NULL,
            evaluated_at TEXT NOT NULL,
            FOREIGN KEY (project_id) REFERENCES pipeline_projects(id)
        );";

    public const string CreatePipelineValidationIndex = @"
        CREATE INDEX IF NOT EXISTS idx_pipeline_validation_project
        ON pipeline_validation_runs(project_id, evaluated_at DESC);";

    public static string[] GetAllSchemaCommands() =>
    [
        CreateRecipesTable,
        CreateRecipesMigrationIdIndex,
        CreateRunsTable,
        CreateRunsIndex,
        CreateCheckpointsTable,
        CreateEventLogTable,
        CreateEventLogIndex,
        CreateValidationRunsTable,
        CreateValidationGatesTable,
        CreateContentMismatchesTable,
        CreatePipelineProjectsTable,
        CreatePipelineValidationRunsTable,
        CreatePipelineValidationIndex
    ];
}
