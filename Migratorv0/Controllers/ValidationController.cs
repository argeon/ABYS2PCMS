using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;
using Microsoft.Data.SqlClient;
using Oracle.ManagedDataAccess.Client;

namespace MigrationWeb.Controllers;

[Route("api/[controller]")]
[ApiController]
public class ValidationController : ControllerBase
{
    private readonly ILogger<ValidationController> _logger;
    private readonly IConfiguration _configuration;

    public ValidationController(ILogger<ValidationController> logger, IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
    }

    /// <summary>
    /// Get table checkpoints for a specific run
    /// </summary>
    [HttpGet("run/{runId}/tables")]
    public async Task<IActionResult> GetRunTables(int runId)
    {
        try
        {
            var checkpointPath = GetCheckpointPath();
            var connectionString = $"Data Source={checkpointPath};Mode=ReadOnly";

            using var connection = new SqliteConnection(connectionString);
            await connection.OpenAsync();

            const string sql = @"
                SELECT 
                    table_name,
                    status,
                    total_rows,
                    rows_processed
                FROM table_checkpoints
                WHERE run_id = @runId
                ORDER BY table_name";

            using var cmd = new SqliteCommand(sql, connection);
            cmd.Parameters.AddWithValue("@runId", runId);

            var tables = new List<object>();
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                tables.Add(new
                {
                    tableName = reader.GetString(0),
                    status = reader.GetString(1),
                    sourceRows = reader.GetInt64(2),
                    totalRows = reader.GetInt64(2),
                    destinationRows = reader.GetInt64(3),
                    rowsProcessed = reader.GetInt64(3)
                });
            }

            return Ok(tables);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get run tables for run {RunId}", runId);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Validate all tables for a run
    /// </summary>
    [HttpPost("run/{runId}/validate-all")]
    public async Task<IActionResult> ValidateAll(int runId)
    {
        try
        {
            var tables = await GetRunTablesInternal(runId);
            int validated = 0;

            foreach (var table in tables)
            {
                // TODO: Implement actual validation
                validated++;
            }

            return Ok(new { success = true, validated });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to validate all tables for run {RunId}", runId);
            return Ok(new { success = false, error = ex.Message });
        }
    }

    /// <summary>
    /// Validate a specific table
    /// </summary>
    [HttpPost("run/{runId}/validate/{tableName}")]
    public async Task<IActionResult> ValidateTable(int runId, string tableName)
    {
        try
        {
            // Get connection strings from checkpoint
            var (oracleCs, mssqlCs) = await GetConnectionStringsFromRun(runId);

            // Count Oracle rows
            long sourceRows = 0;
            using (var oracleConn = new OracleConnection(oracleCs))
            {
                await oracleConn.OpenAsync();
                using var cmd = new OracleCommand($"SELECT COUNT(*) FROM {tableName}", oracleConn);
                sourceRows = Convert.ToInt64(await cmd.ExecuteScalarAsync());
            }

            // Count MSSQL rows
            long destinationRows = 0;
            using (var mssqlConn = new SqlConnection(mssqlCs))
            {
                await mssqlConn.OpenAsync();
                using var cmd = new SqlCommand($"SELECT COUNT(*) FROM [{tableName}]", mssqlConn);
                destinationRows = Convert.ToInt64(await cmd.ExecuteScalarAsync());
            }

            // Update checkpoint
            await UpdateTableValidation(runId, tableName, sourceRows, destinationRows);

            return Ok(new
            {
                success = true,
                tableName,
                sourceRows,
                destinationRows,
                difference = sourceRows - destinationRows,
                matchPercent = sourceRows > 0 ? (destinationRows * 100.0 / sourceRows) : 0
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to validate table {TableName} for run {RunId}", tableName, runId);
            return Ok(new { success = false, error = ex.Message });
        }
    }

    /// <summary>
    /// Drop selected tables from MSSQL
    /// </summary>
    [HttpPost("drop-tables")]
    public async Task<IActionResult> DropTables([FromBody] DropTablesRequest request)
    {
        try
        {
            if (request.Tables == null || request.Tables.Length == 0)
            {
                return Ok(new { success = false, error = "No tables specified" });
            }

            int dropped = 0;
            using var connection = new SqlConnection(request.ConnectionString);
            await connection.OpenAsync();

            foreach (var tableName in request.Tables)
            {
                try
                {
                    using var cmd = new SqlCommand($"DROP TABLE IF EXISTS [{tableName}]", connection);
                    await cmd.ExecuteNonQueryAsync();
                    dropped++;
                    _logger.LogInformation("Dropped table {TableName}", tableName);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to drop table {TableName}", tableName);
                }
            }

            return Ok(new { success = true, dropped });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to drop tables");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    // Helper methods
    private string GetCheckpointPath()
    {
        var sqlitePath = _configuration.GetValue<string>("Checkpoint:SqlitePath") 
            ?? "migration_checkpoint.db";
        return Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "..", "MigrationEngine", sqlitePath));
    }

    private async Task<List<TableInfo>> GetRunTablesInternal(int runId)
    {
        var checkpointPath = GetCheckpointPath();
        var connectionString = $"Data Source={checkpointPath};Mode=ReadOnly";

        using var connection = new SqliteConnection(connectionString);
        await connection.OpenAsync();

        const string sql = @"
            SELECT table_name, total_rows, rows_processed
            FROM table_checkpoints
            WHERE run_id = @runId";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);

        var tables = new List<TableInfo>();
        using var reader = await cmd.ExecuteReaderAsync();

        while (await reader.ReadAsync())
        {
            tables.Add(new TableInfo
            {
                TableName = reader.GetString(0),
                TotalRows = reader.GetInt64(1),
                RowsProcessed = reader.GetInt64(2)
            });
        }

        return tables;
    }

    private async Task<(string OracleCs, string MssqlCs)> GetConnectionStringsFromRun(int runId)
    {
        var checkpointPath = GetCheckpointPath();
        var connectionString = $"Data Source={checkpointPath};Mode=ReadOnly";

        using var connection = new SqliteConnection(connectionString);
        await connection.OpenAsync();

        const string sql = @"
            SELECT oracle_connection_string, mssql_connection_string
            FROM migration_runs
            WHERE run_id = @runId";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);

        using var reader = await cmd.ExecuteReaderAsync();
        if (await reader.ReadAsync())
        {
            return (reader.GetString(0), reader.GetString(1));
        }

        throw new Exception($"Run {runId} not found");
    }

    private async Task UpdateTableValidation(int runId, string tableName, long sourceRows, long destRows)
    {
        var checkpointPath = GetCheckpointPath();
        var connectionString = $"Data Source={checkpointPath}";

        using var connection = new SqliteConnection(connectionString);
        await connection.OpenAsync();

        const string sql = @"
            UPDATE table_checkpoints
            SET total_rows = @sourceRows,
                rows_processed = @destRows,
                last_validated = datetime('now')
            WHERE run_id = @runId AND table_name = @tableName";

        using var cmd = new SqliteCommand(sql, connection);
        cmd.Parameters.AddWithValue("@runId", runId);
        cmd.Parameters.AddWithValue("@tableName", tableName);
        cmd.Parameters.AddWithValue("@sourceRows", sourceRows);
        cmd.Parameters.AddWithValue("@destRows", destRows);

        await cmd.ExecuteNonQueryAsync();
    }

    private class TableInfo
    {
        public string TableName { get; set; } = "";
        public long TotalRows { get; set; }
        public long RowsProcessed { get; set; }
    }

    public class DropTablesRequest
    {
        public string[]? Tables { get; set; }
        public string ConnectionString { get; set; } = "";
    }
}
