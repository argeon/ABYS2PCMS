using System.Text.Json;
using System.Text.Json.Serialization;
using MigrationEngine.Checkpoint;
using MigrationWeb.Hubs;
using MigrationWeb.Services;

var builder = WebApplication.CreateBuilder(args);

var sqliteFileName = builder.Configuration.GetValue<string>("Checkpoint:SqlitePath") ?? "migration_checkpoint.db";
var checkpointDbPath = Path.GetFullPath(
    Path.Combine(builder.Environment.ContentRootPath, "..", "MigrationEngine", sqliteFileName));
var checkpointDir = Path.GetDirectoryName(checkpointDbPath);
if (!string.IsNullOrEmpty(checkpointDir))
    Directory.CreateDirectory(checkpointDir);

var transferSqliteFileName = builder.Configuration.GetValue<string>("TransferStudio:SqlitePath") ?? "transfer_studio.db";
var transferStudioDbPath = Path.GetFullPath(
    Path.Combine(builder.Environment.ContentRootPath, "..", "MigrationEngine", transferSqliteFileName));
var transferStudioDir = Path.GetDirectoryName(transferStudioDbPath);
if (!string.IsNullOrEmpty(transferStudioDir))
    Directory.CreateDirectory(transferStudioDir);

var stageOpsSqliteFileName = builder.Configuration.GetValue<string>("StageOps:SqlitePath") ?? "stage_ops.db";
var stageOpsDbPath = Path.GetFullPath(
    Path.Combine(builder.Environment.ContentRootPath, "..", "MigrationEngine", stageOpsSqliteFileName));
var stageOpsRoot = Path.GetFullPath(
    Path.Combine(builder.Environment.ContentRootPath, "..", "sql", "IZGAZ2PCMS", "IZGAZ2PCMS", "stage_ops"));
var sqlRoot = Path.GetFullPath(
    Path.Combine(builder.Environment.ContentRootPath, "..", "sql", "IZGAZ2PCMS", "IZGAZ2PCMS"));
var stageOpsUploadRoot = Path.Combine(stageOpsRoot, "scripts");
Directory.CreateDirectory(stageOpsUploadRoot);

builder.Services.AddRazorPages();
builder.Services.AddControllers()
    .ConfigureApplicationPartManager(apm =>
    {
        // MigrationEngine is a console EXE referenced for checkpoint/schema APIs — not an MVC assembly.
        var enginePart = apm.ApplicationParts
            .FirstOrDefault(p => string.Equals(p.Name, "MigrationEngine", StringComparison.OrdinalIgnoreCase));
        if (enginePart != null)
            apm.ApplicationParts.Remove(enginePart);
    })
    .AddJsonOptions(o =>
{
    o.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    // Wizard sends enum names as PascalCase (e.g. "Balanced"); accept integers too.
    o.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter(allowIntegerValues: true));
});
builder.Services.AddSignalR().AddJsonProtocol(o =>
{
    o.PayloadSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    o.PayloadSerializerOptions.Converters.Add(new JsonStringEnumConverter(allowIntegerValues: true));
});
builder.Services.AddSingleton<DashboardDataService>();
builder.Services.Configure<CheckpointOptions>(builder.Configuration.GetSection("Checkpoint"));
builder.Services.PostConfigure<CheckpointOptions>(o => o.SqlitePath = checkpointDbPath);
builder.Services.AddSingleton<HistoryDataService>(_ => new HistoryDataService(checkpointDbPath));
builder.Services.AddSingleton<MigrationWeb.Services.TransferStudio.TransferStudioDataService>(
    _ => new MigrationWeb.Services.TransferStudio.TransferStudioDataService(transferStudioDbPath));
builder.Services.AddSingleton<MigrationWeb.Services.TransferStudio.OracleCheckpointReader>(
    _ => new MigrationWeb.Services.TransferStudio.OracleCheckpointReader(checkpointDbPath));
builder.Services.AddSingleton<MigrationWeb.Services.TransferStudio.PipelineValidationOrchestrator>();
builder.Services.AddSingleton<MigrationWeb.Services.Migrate.CsReadingPlanMigrationService>();
builder.Services.AddSingleton<MigrationWeb.Services.Staging.AgreementStagingService>();
builder.Services.AddSingleton(new MigrationWeb.Services.StageOps.StageOpsPaths
{
    SqlitePath = stageOpsDbPath,
    StageOpsRoot = stageOpsRoot,
    SqlRoot = sqlRoot,
    ScriptsUploadRoot = stageOpsUploadRoot
});
builder.Services.AddSingleton<MigrationWeb.Services.StageOps.StageOpsDataService>();
builder.Services.AddSingleton<MigrationWeb.Services.StageOps.StageOpsScriptAnalyzer>();
builder.Services.AddSingleton<MigrationWeb.Services.StageOps.StageOpsSchemaGateService>();
builder.Services.AddSingleton<MigrationWeb.Services.StageOps.StageOpsMigLogService>();
builder.Services.AddSingleton<MigrationWeb.Services.StageOps.StageOpsOrchestrator>();
builder.Services.AddHostedService<CheckpointPollingService>();

var app = builder.Build();

using (new CheckpointRepository(checkpointDbPath))
{
}

using (new MigrationShared.TransferStudio.TransferStudioRepository(transferStudioDbPath))
{
}

// Seed once — do NOT dispose the singleton (that closes the SQLite connection).
app.Services.GetRequiredService<MigrationWeb.Services.StageOps.StageOpsDataService>().EnsureSeeded();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
}

app.UseStaticFiles();
app.UseRouting();
app.MapRazorPages();
app.MapControllers();
app.MapHub<MigrationHub>("/migrationHub");

app.Run();
