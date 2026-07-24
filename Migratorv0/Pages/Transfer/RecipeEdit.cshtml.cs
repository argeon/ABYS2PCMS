using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace MigrationWeb.Pages.Transfer;

public class RecipeEditModel : PageModel
{
    [FromQuery]
    public int? Id { get; set; }

    public void OnGet() { }
}
