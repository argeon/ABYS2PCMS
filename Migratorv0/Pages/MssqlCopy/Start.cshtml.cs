using Microsoft.AspNetCore.Mvc.RazorPages;
using MigrationWeb.Services.MssqlCopy;

namespace MigrationWeb.Pages.MssqlCopy;

public class StartModel : PageModel
{
    private readonly IWebHostEnvironment _environment;

    public StartModel(IWebHostEnvironment environment)
    {
        _environment = environment;
    }

    public string? ConfigPath { get; set; }
    public string? EnginePath { get; set; }

    public void OnGet()
    {
        EnginePath = MssqlCopyEngineLauncher.GetEngineDirectory(_environment.ContentRootPath);
        ConfigPath = Path.Combine(EnginePath, "appsettings.json");
    }
}
