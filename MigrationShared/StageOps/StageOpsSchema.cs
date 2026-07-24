namespace MigrationShared.StageOps;

public static class StageOpsSchema
{
    public const string CreateScripts = @"
        CREATE TABLE IF NOT EXISTS stage_scripts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            stage_id TEXT NOT NULL UNIQUE,
            surface TEXT NOT NULL,
            name TEXT NOT NULL,
            domain TEXT NOT NULL DEFAULT '',
            kind TEXT NOT NULL,
            path TEXT,
            procedure_name TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            estimated_rows INTEGER,
            depends_on_json TEXT NOT NULL DEFAULT '[]',
            writes_json TEXT NOT NULL DEFAULT '[]',
            reads_json TEXT NOT NULL DEFAULT '[]',
            parallel_safe INTEGER NOT NULL DEFAULT 1,
            slot_cost INTEGER NOT NULL DEFAULT 1,
            recreate_on_retry INTEGER NOT NULL DEFAULT 1,
            status TEXT NOT NULL DEFAULT 'Ready',
            syntax_status TEXT,
            analysis_json TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );";

    public const string CreateScriptsSurfaceIndex = @"
        CREATE INDEX IF NOT EXISTS idx_stage_scripts_surface
        ON stage_scripts(surface, sort_order, name);";

    public const string CreateRuns = @"
        CREATE TABLE IF NOT EXISTS stage_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_uuid TEXT NOT NULL UNIQUE,
            surface TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'Queued',
            max_parallel INTEGER NOT NULL DEFAULT 1,
            total_stages INTEGER NOT NULL DEFAULT 0,
            done_count INTEGER NOT NULL DEFAULT 0,
            failed_count INTEGER NOT NULL DEFAULT 0,
            running_count INTEGER NOT NULL DEFAULT 0,
            total_rows INTEGER NOT NULL DEFAULT 0,
            params_json TEXT,
            started_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            completed_at TEXT
        );";

    public const string CreateRunsSurfaceIndex = @"
        CREATE INDEX IF NOT EXISTS idx_stage_runs_surface
        ON stage_runs(surface, started_at DESC);";

    public const string CreateRunItems = @"
        CREATE TABLE IF NOT EXISTS stage_run_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL,
            stage_id TEXT NOT NULL,
            stage_name TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'Queued',
            exit_code INTEGER,
            elapsed_ms INTEGER NOT NULL DEFAULT 0,
            row_count INTEGER,
            rows_per_sec REAL,
            log_path TEXT,
            detail_json TEXT,
            started_at TEXT,
            completed_at TEXT,
            FOREIGN KEY (run_id) REFERENCES stage_runs(id)
        );";

    public const string CreateRunItemsIndex = @"
        CREATE INDEX IF NOT EXISTS idx_stage_run_items_run
        ON stage_run_items(run_id, id);";

    public const string CreateEvents = @"
        CREATE TABLE IF NOT EXISTS stage_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL,
            stage_id TEXT,
            level TEXT NOT NULL DEFAULT 'Info',
            message TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (run_id) REFERENCES stage_runs(id)
        );";

    public const string CreateEventsIndex = @"
        CREATE INDEX IF NOT EXISTS idx_stage_events_run
        ON stage_events(run_id, id DESC);";

    public const string CreateSchemaChecks = @"
        CREATE TABLE IF NOT EXISTS stage_schema_checks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            surface TEXT NOT NULL,
            stage_id TEXT NOT NULL,
            run_id INTEGER,
            compatible INTEGER NOT NULL,
            result_json TEXT NOT NULL,
            checked_at TEXT NOT NULL
        );";

    public const string CreateAnalyses = @"
        CREATE TABLE IF NOT EXISTS script_analyses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            stage_id TEXT NOT NULL,
            surface TEXT NOT NULL,
            file_name TEXT NOT NULL,
            syntax_ok INTEGER NOT NULL,
            result_json TEXT NOT NULL,
            analyzed_at TEXT NOT NULL
        );";

    public static string[] GetAllSchemaCommands() =>
    [
        CreateScripts,
        CreateScriptsSurfaceIndex,
        CreateRuns,
        CreateRunsSurfaceIndex,
        CreateRunItems,
        CreateRunItemsIndex,
        CreateEvents,
        CreateEventsIndex,
        CreateSchemaChecks,
        CreateAnalyses
    ];
}
