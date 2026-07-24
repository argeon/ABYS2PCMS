using Microsoft.Data.Sqlite;

namespace MigrationEngine.Checkpoint;

public static class ConnectionProfileSchemaMigrator
{
    public static void EnsureColumns(SqliteConnection connection)
    {
        if (!TableExists(connection, "connection_profiles"))
            return;

        AddColumnIfMissing(connection, "connection_profiles", "connection_string", "TEXT");
        AddColumnIfMissing(connection, "connection_profiles", "config_json", "TEXT");
        AddColumnIfMissing(connection, "connection_profiles", "is_deleted", "INTEGER NOT NULL DEFAULT 0");
        AddColumnIfMissing(connection, "connection_profiles", "deleted_at", "TEXT");
    }

    private static bool TableExists(SqliteConnection connection, string table)
    {
        using var cmd = new SqliteCommand(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = @name LIMIT 1",
            connection);
        cmd.Parameters.AddWithValue("@name", table);
        return cmd.ExecuteScalar() != null;
    }

    private static void AddColumnIfMissing(SqliteConnection connection, string table, string column, string type)
    {
        if (ColumnExists(connection, table, column))
            return;

        using var cmd = new SqliteCommand($"ALTER TABLE {table} ADD COLUMN {column} {type}", connection);
        cmd.ExecuteNonQuery();
    }

    private static bool ColumnExists(SqliteConnection connection, string table, string column)
    {
        using var cmd = new SqliteCommand($"PRAGMA table_info({table})", connection);
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            if (string.Equals(reader.GetString(1), column, StringComparison.OrdinalIgnoreCase))
                return true;
        }

        return false;
    }
}
