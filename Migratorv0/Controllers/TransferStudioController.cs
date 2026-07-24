using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using MigrationShared.Models;
using MigrationShared.Models.TransferStudio;
using MigrationWeb.Services;
using MigrationWeb.Services.TransferStudio;

namespace MigrationWeb.Controllers;

/// <summary>
/// MSSQL Transfer Studio API — Oracle migration motoruna dokunmaz.
/// </summary>
[Route("api/transfer-studio")]
[ApiController]
public class TransferStudioController : ControllerBase
{
    private readonly TransferStudioDataService _transferData;
    private readonly HistoryDataService _history;
    private readonly ILogger<TransferStudioController> _logger;

    public TransferStudioController(
        TransferStudioDataService transferData,
        HistoryDataService history,
        ILogger<TransferStudioController> logger)
    {
        _transferData = transferData;
        _history = history;
        _logger = logger;
    }

    [HttpGet("recipes")]
    public IActionResult ListRecipes() =>
        Ok(_transferData.ListRecipes());

    [HttpGet("recipes/{id:int}")]
    public IActionResult GetRecipe(int id)
    {
        var recipe = _transferData.GetRecipe(id);
        if (recipe == null)
            return NotFound();
        return Ok(new { id = recipe.Value.id, document = recipe.Value.doc });
    }

    [HttpPost("recipes")]
    public IActionResult CreateRecipe([FromBody] SaveRecipeRequest request)
    {
        if (request.Document == null || string.IsNullOrWhiteSpace(request.Document.MigrationId))
            return BadRequest(new { error = "Geçersiz recipe." });

        ApplyConnectionProfiles(request.Document);
        var id = _transferData.SaveRecipe(request.Document, request.Status ?? TransferRecipeStatus.Draft);
        return Ok(new { id });
    }

    [HttpPut("recipes/{id:int}")]
    public IActionResult UpdateRecipe(int id, [FromBody] SaveRecipeRequest request)
    {
        if (request.Document == null)
            return BadRequest(new { error = "Geçersiz recipe." });

        ApplyConnectionProfiles(request.Document);
        var savedId = _transferData.SaveRecipe(request.Document, request.Status ?? TransferRecipeStatus.Draft, id);
        return Ok(new { id = savedId });
    }

    [HttpDelete("recipes/{id:int}")]
    public IActionResult DeleteRecipe(int id)
    {
        if (!_transferData.DeleteRecipe(id))
            return NotFound();
        return Ok(new { success = true });
    }

    [HttpPost("recipes/sample-it-user")]
    public IActionResult CreateItUserSample()
    {
        var existing = _transferData.ListRecipes()
            .FirstOrDefault(r => r.MigrationId.Equals("IT_USER", StringComparison.OrdinalIgnoreCase));
        if (existing != null)
        {
            var doc = _transferData.GetRecipe(existing.Id);
            return Ok(new { id = existing.Id, document = doc?.doc, existing = true });
        }

        var sample = TransferRecipeSamples.CreateItUserSample();
        var id = _transferData.SaveRecipe(sample, TransferRecipeStatus.Draft);
        return Ok(new { id, document = sample, existing = false });
    }

    [HttpGet("mssql-profiles")]
    public IActionResult ListMssqlProfiles()
    {
        var profiles = _history.GetConnectionProfiles("MSSQL")
            .Select(p => new
            {
                p.Id,
                p.ProfileName,
                p.DatabaseName,
                p.Host,
                hasConnectionString = !string.IsNullOrWhiteSpace(p.ConnectionString)
            });
        return Ok(profiles);
    }

    [HttpPost("test-connection")]
    public async Task<IActionResult> TestConnection([FromBody] MssqlTestRequest request)
    {
        try
        {
            var cs = ResolveConnectionString(request);
            await using var conn = new SqlConnection(cs);
            await conn.OpenAsync();
            await using var cmd = new SqlCommand("SELECT DB_NAME()", conn);
            var db = (string?)await cmd.ExecuteScalarAsync();
            return Ok(new { success = true, database = db });
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "MSSQL bağlantı testi başarısız");
            return Ok(new { success = false, error = ex.Message });
        }
    }

    [HttpPost("schema/tables")]
    public async Task<IActionResult> ListTables([FromBody] MssqlSchemaRequest request)
    {
        try
        {
            var cs = ResolveConnectionString(request);
            await using var conn = new SqlConnection(cs);
            await conn.OpenAsync();
            var schema = string.IsNullOrWhiteSpace(request.Schema) ? "dbo" : request.Schema;
            const string sql = @"
                SELECT TABLE_SCHEMA, TABLE_NAME
                FROM INFORMATION_SCHEMA.TABLES
                WHERE TABLE_TYPE = 'BASE TABLE' AND TABLE_SCHEMA = @schema
                ORDER BY TABLE_NAME";
            await using var cmd = new SqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@schema", schema);
            var tables = new List<object>();
            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
                tables.Add(new { schema = reader.GetString(0), name = reader.GetString(1) });
            return Ok(tables);
        }
        catch (Exception ex)
        {
            return Ok(new { error = ex.Message, tables = Array.Empty<object>() });
        }
    }

    [HttpPost("schema/columns")]
    public async Task<IActionResult> ListColumns([FromBody] MssqlTableRequest request)
    {
        try
        {
            var cs = ResolveConnectionString(request);
            await using var conn = new SqlConnection(cs);
            await conn.OpenAsync();
            var schema = string.IsNullOrWhiteSpace(request.Schema) ? "dbo" : request.Schema;
            const string sql = @"
                SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = @schema AND TABLE_NAME = @table
                ORDER BY ORDINAL_POSITION";
            await using var cmd = new SqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@schema", schema);
            cmd.Parameters.AddWithValue("@table", request.Table);
            var cols = new List<object>();
            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                cols.Add(new
                {
                    name = reader.GetString(0),
                    dataType = reader.GetString(1),
                    isNullable = reader.GetString(2),
                    maxLength = reader.IsDBNull(3) ? (int?)null : reader.GetInt32(3)
                });
            }
            return Ok(cols);
        }
        catch (Exception ex)
        {
            return Ok(new { error = ex.Message, columns = Array.Empty<object>() });
        }
    }

    [HttpPost("validate")]
    public async Task<IActionResult> RunValidation([FromBody] RunValidationRequest request, CancellationToken ct)
    {
        var recipe = _transferData.GetRecipe(request.RecipeId);
        if (recipe == null)
            return NotFound();

        var doc = recipe.Value.doc;
        ApplyConnectionProfiles(doc);

        try
        {
            var result = await TransferStudioValidator.ValidateAsync(
                doc, request.RecipeId, request.Phase ?? "INSERT", request.IncludeContent, ct);
            _transferData.SaveValidationResult(result, request.TransferRunId);
            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Validasyon hatası recipe {Id}", request.RecipeId);
            return Ok(new { error = ex.Message });
        }
    }

    [HttpGet("recipes/{id:int}/validation/latest")]
    public IActionResult GetLatestValidation(int id)
    {
        var result = _transferData.GetLatestValidation(id);
        return result == null ? NotFound() : Ok(result);
    }

    [HttpGet("runs")]
    public IActionResult ListRuns([FromQuery] int? recipeId, [FromQuery] int limit = 50) =>
        Ok(_transferData.ListRuns(recipeId, limit));

    [HttpGet("runs/{id:int}/events")]
    public IActionResult GetRunEvents(int id, [FromQuery] int limit = 200) =>
        Ok(_transferData.GetEvents(id, limit));

    [HttpPost("runs")]
    public IActionResult StartRun([FromBody] StartRunRequest request)
    {
        var recipe = _transferData.GetRecipe(request.RecipeId);
        if (recipe == null)
            return NotFound();

        var doc = recipe.Value.doc;
        var runUuid = Guid.NewGuid().ToString();
        var phase = request.Phase ?? doc.Execution.DefaultRunPhase;
        var runId = _transferData.CreateRun(
            request.RecipeId,
            runUuid,
            doc.Execution.Mode.ToString(),
            phase,
            null);

        _transferData.LogEvent(new TransferEventLogEntry
        {
            RunId = runId,
            Level = "Info",
            Phase = phase,
            Message = $"Aktarım run başlatıldı (Transfer Studio — engine entegrasyonu bekliyor). RUN_ID={runUuid}",
            CreatedAt = DateTime.UtcNow
        });

        _transferData.UpdateRun(runId, "Queued", 0, 0, null);

        return Ok(new
        {
            runId,
            runUuid,
            message = "Run kaydı oluşturuldu. Tam aktarım motoru sonraki aşamada bağlanacak."
        });
    }

    private void ApplyConnectionProfiles(TransferRecipeDocument doc)
    {
        if (doc.Endpoints.SourceProfileId is > 0)
        {
            var p = _history.GetConnectionProfiles("MSSQL")
                .FirstOrDefault(x => x.Id == doc.Endpoints.SourceProfileId);
            if (p?.ConnectionString != null)
            {
                doc.Endpoints.SourceConnectionString = p.ConnectionString;
                if (string.IsNullOrWhiteSpace(doc.Endpoints.SourceDatabase) && !string.IsNullOrWhiteSpace(p.DatabaseName))
                    doc.Endpoints.SourceDatabase = p.DatabaseName;
            }
        }

        if (doc.Endpoints.TargetProfileId is > 0)
        {
            var p = _history.GetConnectionProfiles("MSSQL")
                .FirstOrDefault(x => x.Id == doc.Endpoints.TargetProfileId);
            if (p?.ConnectionString != null)
            {
                doc.Endpoints.TargetConnectionString = p.ConnectionString;
                if (string.IsNullOrWhiteSpace(doc.Endpoints.TargetDatabase) && !string.IsNullOrWhiteSpace(p.DatabaseName))
                    doc.Endpoints.TargetDatabase = p.DatabaseName;
            }
        }
    }

    private string ResolveConnectionString(MssqlTestRequest request)
    {
        if (!string.IsNullOrWhiteSpace(request.ConnectionString))
            return request.ConnectionString;

        if (request.ProfileId is > 0)
        {
            var p = _history.GetConnectionProfiles("MSSQL").FirstOrDefault(x => x.Id == request.ProfileId);
            if (!string.IsNullOrWhiteSpace(p?.ConnectionString))
                return p.ConnectionString;
        }

        if (string.IsNullOrWhiteSpace(request.Server) || string.IsNullOrWhiteSpace(request.Database))
            throw new InvalidOperationException("Sunucu veya profil gerekli.");

        var builder = new SqlConnectionStringBuilder
        {
            DataSource = request.Server,
            InitialCatalog = request.Database,
            TrustServerCertificate = request.TrustCert
        };

        if (request.UseWindowsAuth)
            builder.IntegratedSecurity = true;
        else
        {
            builder.UserID = request.Username ?? "";
            builder.Password = request.Password ?? "";
        }

        return builder.ConnectionString;
    }
}

public class SaveRecipeRequest
{
    public TransferRecipeDocument? Document { get; set; }
    public TransferRecipeStatus? Status { get; set; }
}

public class MssqlTestRequest
{
    public int? ProfileId { get; set; }
    public string? ConnectionString { get; set; }
    public string? Server { get; set; }
    public string? Database { get; set; }
    public string? Username { get; set; }
    public string? Password { get; set; }
    public bool UseWindowsAuth { get; set; }
    public bool TrustCert { get; set; } = true;
}

public class MssqlSchemaRequest : MssqlTestRequest
{
    public string? Schema { get; set; }
}

public class MssqlTableRequest : MssqlSchemaRequest
{
    public string Table { get; set; } = string.Empty;
}

public class RunValidationRequest
{
    public int RecipeId { get; set; }
    public string? Phase { get; set; }
    public bool IncludeContent { get; set; } = true;
    public int? TransferRunId { get; set; }
}

public class StartRunRequest
{
    public int RecipeId { get; set; }
    public string? Phase { get; set; }
}
