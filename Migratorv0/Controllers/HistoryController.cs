using Microsoft.AspNetCore.Mvc;
using MigrationShared.Models;
using MigrationWeb.Services;

namespace MigrationWeb.Controllers;

[Route("api/[controller]")]
[ApiController]
public class HistoryController : ControllerBase
{
    private readonly HistoryDataService _history;
    private readonly ILogger<HistoryController> _logger;

    public HistoryController(HistoryDataService history, ILogger<HistoryController> logger)
    {
        _history = history;
        _logger = logger;
    }

    [HttpGet("profiles")]
    public IActionResult GetProfiles(
        [FromQuery] int limit = 100,
        [FromQuery] string? type = null,
        [FromQuery] bool includeDeleted = false)
    {
        try
        {
            var profiles = _history.GetConnectionProfiles(type, includeDeleted);
            var result = profiles
                .Take(limit)
                .Select(MapProfile);
            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load connection profiles");
            return Ok(Array.Empty<object>());
        }
    }

    [HttpGet("profiles/{id:int}")]
    public IActionResult GetProfile(int id)
    {
        try
        {
            var profile = _history.GetConnectionProfileById(id);
            if (profile == null)
                return NotFound(new { error = $"Profile {id} not found" });

            return Ok(MapProfile(profile));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load profile {ProfileId}", id);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    [HttpPut("profiles/{id:int}")]
    public IActionResult UpdateProfile(int id, [FromBody] UpdateProfileRequest request)
    {
        try
        {
            if (request == null || string.IsNullOrWhiteSpace(request.ProfileName))
                return BadRequest(new { error = "Profile name is required" });

            if (string.IsNullOrWhiteSpace(request.ConnectionType))
                return BadRequest(new { error = "Connection type is required" });

            var existing = _history.GetConnectionProfileById(id, includeDeleted: false);
            if (existing == null)
                return NotFound(new { error = $"Profile {id} not found or deleted" });

            var updated = new ConnectionProfile
            {
                Id = id,
                ProfileName = request.ProfileName.Trim(),
                ConnectionType = request.ConnectionType.Trim(),
                Host = request.Host,
                Port = request.Port,
                ServiceName = request.ServiceName,
                DatabaseName = request.DatabaseName,
                Username = request.Username,
                SchemaName = request.SchemaName,
                AuthType = request.AuthType,
                TrustCert = request.TrustCert,
                ConnectionString = request.ConnectionString,
                ConfigJson = request.ConfigJson
            };

            if (!_history.UpdateConnectionProfile(updated))
                return NotFound(new { error = $"Profile {id} could not be updated" });

            var profile = _history.GetConnectionProfileById(id);
            return Ok(new { success = true, profile = MapProfile(profile!) });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to update profile {ProfileId}", id);
            return StatusCode(500, new { success = false, error = ex.Message });
        }
    }

    [HttpDelete("profiles/{id:int}")]
    public IActionResult SoftDeleteProfile(int id)
    {
        try
        {
            if (!_history.SoftDeleteConnectionProfile(id))
                return NotFound(new { success = false, error = $"Profile {id} not found or already deleted" });

            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to soft-delete profile {ProfileId}", id);
            return StatusCode(500, new { success = false, error = ex.Message });
        }
    }

    [HttpPost("profiles/{id:int}/restore")]
    public IActionResult RestoreProfile(int id)
    {
        try
        {
            if (!_history.RestoreConnectionProfile(id))
                return NotFound(new { success = false, error = $"Profile {id} not found or not deleted" });

            var profile = _history.GetConnectionProfileById(id);
            return Ok(new { success = true, profile = MapProfile(profile!) });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to restore profile {ProfileId}", id);
            return StatusCode(500, new { success = false, error = ex.Message });
        }
    }

    // profileId is accepted for API compatibility but migration_history has no FK to connection_profiles.
    // All runs are returned; client-side filtering is not needed in current usage.
    [HttpGet("migrations")]
    public IActionResult GetMigrations([FromQuery] int? profileId, [FromQuery] int limit = 50)
    {
        try
        {
            var migrations = _history.GetMigrationHistory(limit);
            var result = migrations.Select(m => new
            {
                id = m.Id,
                runId = m.RunId,
                migrationName = m.MigrationName,
                sourceSchema = m.SourceSchema,
                tableCount = m.TableCount,
                totalRows = m.TotalRows,
                startedAt = m.StartedAt,
                completedAt = m.CompletedAt,
                durationSeconds = m.DurationSeconds,
                status = m.Status
            });
            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load migration history");
            return Ok(Array.Empty<object>());
        }
    }

    private static object MapProfile(ConnectionProfile p) => new
    {
        id = p.Id,
        name = p.ProfileName,
        connectionType = p.ConnectionType,
        host = p.Host,
        port = p.Port,
        serviceName = p.ServiceName,
        databaseName = p.DatabaseName,
        username = p.Username,
        schemaName = p.SchemaName,
        authType = p.AuthType,
        trustCert = p.TrustCert,
        connectionString = p.ConnectionString,
        configJson = p.ConfigJson,
        hasMigrationConfig = p.ConfigJson != null,
        createdAt = p.CreatedAt,
        lastUsedAt = p.LastUsedAt,
        useCount = p.UseCount,
        isDeleted = p.IsDeleted,
        deletedAt = p.DeletedAt,
        isWizard = string.Equals(p.ConnectionType, "Migration", StringComparison.OrdinalIgnoreCase)
                   || !string.IsNullOrWhiteSpace(p.ConfigJson)
    };

    public class UpdateProfileRequest
    {
        public string ProfileName { get; set; } = string.Empty;
        public string ConnectionType { get; set; } = string.Empty;
        public string? Host { get; set; }
        public string? Port { get; set; }
        public string? ServiceName { get; set; }
        public string? DatabaseName { get; set; }
        public string? Username { get; set; }
        public string? SchemaName { get; set; }
        public string? AuthType { get; set; }
        public bool TrustCert { get; set; }
        public string? ConnectionString { get; set; }
        public string? ConfigJson { get; set; }
    }
}
