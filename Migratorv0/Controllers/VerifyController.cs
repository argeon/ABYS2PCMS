using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Oracle.ManagedDataAccess.Client;

namespace MigrationWeb.Controllers;

[Route("api/[controller]")]
[ApiController]
public class VerifyController : ControllerBase
{
    private readonly ILogger<VerifyController> _logger;

    public VerifyController(ILogger<VerifyController> logger)
    {
        _logger = logger;
    }

    [HttpGet("compare")]
    public async Task<IActionResult> CompareTable(
        [FromQuery] string table,
        [FromQuery] string oracleConn,
        [FromQuery] string mssqlConn,
        [FromQuery] string schema)
    {
        try
        {
            long oracleRows = await GetOracleRowCount(oracleConn, schema, table);
            long mssqlRows = await GetMssqlRowCount(mssqlConn, table);

            return Ok(new
            {
                tableName = table,
                oracleRows = oracleRows,
                mssqlRows = mssqlRows,
                difference = oracleRows - mssqlRows,
                matchPercent = oracleRows > 0 ? ((double)mssqlRows / oracleRows) * 100 : 0,
                checkedAt = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to compare table {Table}", table);
            return Ok(new
            {
                tableName = table,
                oracleRows = -1,
                mssqlRows = -1,
                error = ex.Message
            });
        }
    }

    [HttpPost("drop")]
    public async Task<IActionResult> DropTables([FromBody] DropTablesRequest request)
    {
        try
        {
            if (request == null || request.Tables == null || request.Tables.Length == 0)
            {
                return BadRequest(new { error = "No tables specified" });
            }

            int droppedCount = 0;
            var errors = new List<string>();

            using var connection = new SqlConnection(request.ConnectionString);
            await connection.OpenAsync();

            foreach (var table in request.Tables)
            {
                try
                {
                    var sql = $"DROP TABLE IF EXISTS [{table}]";
                    using var cmd = new SqlCommand(sql, connection);
                    await cmd.ExecuteNonQueryAsync();
                    droppedCount++;
                    _logger.LogInformation("Dropped table {Table}", table);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to drop table {Table}", table);
                    errors.Add($"{table}: {ex.Message}");
                }
            }

            return Ok(new
            {
                success = true,
                droppedCount = droppedCount,
                totalRequested = request.Tables.Length,
                errors = errors
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to drop tables");
            return Ok(new
            {
                success = false,
                error = ex.Message
            });
        }
    }

    [HttpPost("verify-bulk")]
    public async Task<IActionResult> VerifyBulk([FromBody] VerifyBulkRequest request)
    {
        try
        {
            var results = new List<object>();

            foreach (var table in request.Tables)
            {
                try
                {
                    long oracleRows = await GetOracleRowCount(request.OracleConnectionString, request.Schema, table);
                    long mssqlRows = await GetMssqlRowCount(request.MssqlConnectionString, table);

                    results.Add(new
                    {
                        tableName = table,
                        oracleRows = oracleRows,
                        mssqlRows = mssqlRows,
                        difference = oracleRows - mssqlRows,
                        matchPercent = oracleRows > 0 ? ((double)mssqlRows / oracleRows) * 100 : 0,
                        status = oracleRows == mssqlRows ? "matched" : "mismatch"
                    });
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to verify table {Table}", table);
                    results.Add(new
                    {
                        tableName = table,
                        error = ex.Message
                    });
                }
            }

            return Ok(results);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to verify tables");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    private async Task<long> GetOracleRowCount(string connectionString, string schema, string tableName)
    {
        using var connection = new OracleConnection(connectionString);
        await connection.OpenAsync();

        var sql = $"SELECT COUNT(*) FROM {schema}.{tableName}";
        using var cmd = new OracleCommand(sql, connection);
        cmd.CommandTimeout = 300; // 5 minutes

        var result = await cmd.ExecuteScalarAsync();
        return Convert.ToInt64(result);
    }

    private async Task<long> GetMssqlRowCount(string connectionString, string tableName)
    {
        using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();

        // Check if table exists
        var checkSql = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = @tableName";
        using var checkCmd = new SqlCommand(checkSql, connection);
        checkCmd.Parameters.AddWithValue("@tableName", tableName);
        var exists = Convert.ToInt32(await checkCmd.ExecuteScalarAsync()) > 0;

        if (!exists)
        {
            return -1; // Table doesn't exist
        }

        var sql = $"SELECT COUNT(*) FROM [{tableName}]";
        using var cmd = new SqlCommand(sql, connection);
        cmd.CommandTimeout = 300; // 5 minutes

        var result = await cmd.ExecuteScalarAsync();
        return Convert.ToInt64(result);
    }
}

public class DropTablesRequest
{
    public string ConnectionString { get; set; } = string.Empty;
    public string[] Tables { get; set; } = Array.Empty<string>();
}

public class VerifyBulkRequest
{
    public string OracleConnectionString { get; set; } = string.Empty;
    public string MssqlConnectionString { get; set; } = string.Empty;
    public string Schema { get; set; } = string.Empty;
    public string[] Tables { get; set; } = Array.Empty<string>();
}
