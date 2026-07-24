namespace MigrationEngine.Checkpoint;

public static class ExtendedCheckpointSchema
{
    // Migration History - Geçmiş migration'ları saklar
    public const string CreateMigrationHistoryTable = @"
        CREATE TABLE IF NOT EXISTS migration_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL,
            migration_name TEXT NOT NULL,
            source_connection TEXT NOT NULL,
            target_connection TEXT NOT NULL,
            source_schema TEXT NOT NULL,
            table_count INTEGER NOT NULL,
            total_rows BIGINT DEFAULT 0,
            started_at TEXT NOT NULL,
            completed_at TEXT,
            duration_seconds INTEGER,
            status TEXT NOT NULL,
            config_json TEXT NOT NULL,
            FOREIGN KEY (run_id) REFERENCES migration_runs(run_id)
        );";

    public const string CreateHistoryIndex = @"
        CREATE INDEX IF NOT EXISTS idx_history_started 
        ON migration_history(started_at DESC);";

    // Connection Profiles - Bağlantı bilgilerini saklar
    public const string CreateConnectionProfilesTable = @"
        CREATE TABLE IF NOT EXISTS connection_profiles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            profile_name TEXT NOT NULL UNIQUE,
            connection_type TEXT NOT NULL,
            host TEXT,
            port TEXT,
            service_name TEXT,
            database_name TEXT,
            username TEXT,
            schema_name TEXT,
            auth_type TEXT,
            trust_cert INTEGER DEFAULT 0,
            connection_string TEXT,
            config_json TEXT,
            created_at TEXT NOT NULL,
            last_used_at TEXT,
            use_count INTEGER DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            deleted_at TEXT
        );";

    // Metrics - Detaylı performans metrikleri
    public const string CreateMetricsTable = @"
        CREATE TABLE IF NOT EXISTS migration_metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL,
            table_name TEXT NOT NULL,
            metric_type TEXT NOT NULL,
            metric_value REAL NOT NULL,
            recorded_at TEXT NOT NULL,
            FOREIGN KEY (run_id) REFERENCES migration_runs(run_id)
        );";

    public const string CreateMetricsIndex = @"
        CREATE INDEX IF NOT EXISTS idx_metrics_run_table 
        ON migration_metrics(run_id, table_name);";

    // Thread/Partition Monitoring - Aktif thread'leri izler
    public const string CreateThreadMonitoringTable = @"
        CREATE TABLE IF NOT EXISTS thread_monitoring (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL,
            partition_id INTEGER NOT NULL,
            table_name TEXT NOT NULL,
            thread_id INTEGER NOT NULL,
            status TEXT NOT NULL,
            started_at TEXT NOT NULL,
            last_heartbeat TEXT NOT NULL,
            rows_processed BIGINT DEFAULT 0,
            total_rows BIGINT DEFAULT 0,
            current_speed REAL DEFAULT 0,
            estimated_completion TEXT,
            FOREIGN KEY (run_id) REFERENCES migration_runs(run_id),
            FOREIGN KEY (partition_id) REFERENCES table_checkpoints(id)
        );";

    public const string CreateThreadIndex = @"
        CREATE INDEX IF NOT EXISTS idx_thread_run_status 
        ON thread_monitoring(run_id, status);";

    // Performance Summary - Run bazında özet metrikler
    public const string CreatePerformanceSummaryTable = @"
        CREATE TABLE IF NOT EXISTS performance_summary (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL UNIQUE,
            total_duration_seconds INTEGER,
            avg_rows_per_second REAL,
            peak_rows_per_second REAL,
            total_bytes_transferred BIGINT,
            total_errors INTEGER,
            total_warnings INTEGER,
            parallel_efficiency REAL,
            schema_phase_duration INTEGER,
            load_phase_duration INTEGER,
            index_phase_duration INTEGER,
            validation_phase_duration INTEGER,
            FOREIGN KEY (run_id) REFERENCES migration_runs(run_id)
        );";

    // Table Statistics - Tablo bazında istatistikler
    public const string CreateTableStatisticsTable = @"
        CREATE TABLE IF NOT EXISTS table_statistics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL,
            table_name TEXT NOT NULL,
            oracle_row_count BIGINT,
            mssql_row_count BIGINT,
            oracle_size_mb REAL,
            mssql_size_mb REAL,
            load_duration_seconds INTEGER,
            avg_rows_per_second REAL,
            partition_count INTEGER,
            retry_count INTEGER,
            validation_status TEXT,
            FOREIGN KEY (run_id) REFERENCES migration_runs(run_id)
        );";

    public const string CreateTableStatsIndex = @"
        CREATE INDEX IF NOT EXISTS idx_table_stats_run 
        ON table_statistics(run_id, table_name);";

    // Error Log - Detaylı hata kayıtları
    public const string CreateErrorLogTable = @"
        CREATE TABLE IF NOT EXISTS error_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL,
            table_name TEXT,
            partition_id INTEGER,
            error_type TEXT NOT NULL,
            error_message TEXT NOT NULL,
            stack_trace TEXT,
            occurred_at TEXT NOT NULL,
            retry_attempt INTEGER DEFAULT 0,
            resolved INTEGER DEFAULT 0,
            FOREIGN KEY (run_id) REFERENCES migration_runs(run_id)
        );";

    public const string CreateErrorLogIndex = @"
        CREATE INDEX IF NOT EXISTS idx_error_run_table 
        ON error_log(run_id, table_name, occurred_at DESC);";

    // Comparison Snapshots - Run'lar arası karşılaştırma için
    public const string CreateComparisonSnapshotsTable = @"
        CREATE TABLE IF NOT EXISTS comparison_snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id_1 INTEGER NOT NULL,
            run_id_2 INTEGER NOT NULL,
            comparison_metric TEXT NOT NULL,
            run_1_value REAL,
            run_2_value REAL,
            improvement_percent REAL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (run_id_1) REFERENCES migration_runs(run_id),
            FOREIGN KEY (run_id_2) REFERENCES migration_runs(run_id)
        );";

    public const string CreateValidationGatesTable = @"
        CREATE TABLE IF NOT EXISTS validation_gates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL,
            table_name TEXT NOT NULL,
            gate_type TEXT NOT NULL,
            phase TEXT NOT NULL DEFAULT 'Final',
            passed INTEGER NOT NULL,
            oracle_value TEXT,
            mssql_value TEXT,
            message TEXT,
            evaluated_at TEXT NOT NULL,
            FOREIGN KEY (run_id) REFERENCES migration_runs(run_id)
        );";

    public const string CreateValidationGatesIndex = @"
        CREATE INDEX IF NOT EXISTS idx_validation_gates_run_table 
        ON validation_gates(run_id, table_name);";

    public static string[] GetAllExtendedSchemas()
    {
        return new[]
        {
            CreateMigrationHistoryTable,
            CreateHistoryIndex,
            CreateConnectionProfilesTable,
            CreateMetricsTable,
            CreateMetricsIndex,
            CreateThreadMonitoringTable,
            CreateThreadIndex,
            CreatePerformanceSummaryTable,
            CreateTableStatisticsTable,
            CreateTableStatsIndex,
            CreateErrorLogTable,
            CreateErrorLogIndex,
            CreateComparisonSnapshotsTable,
            CreateValidationGatesTable,
            CreateValidationGatesIndex
        };
    }
}
