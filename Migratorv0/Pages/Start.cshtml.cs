using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace MigrationWeb.Pages;

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
        EnginePath = Path.GetFullPath(Path.Combine(_environment.ContentRootPath, "..", "MigrationEngine"));
        ConfigPath = Path.Combine(EnginePath, "appsettings.json");
    }
}
