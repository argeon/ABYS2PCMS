using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MigrationShared.Models.StageOps;

namespace MigrationWeb.Pages.StageOps;

public class BoardModel : PageModel
{
    [FromRoute]
    public string Surface { get; set; } = StageOpsSurfaces.Ctas;

    public string Title { get; private set; } = "Stage Ops";
    public string Subtitle { get; private set; } = "";
    public string Badge { get; private set; } = "";
    public string Hint { get; private set; } = "";
    public int DefaultParallel { get; private set; } = 1;

    public IActionResult OnGet()
    {
        Surface = (Surface ?? "").Trim().ToLowerInvariant();
        if (!StageOpsSurfaces.IsValid(Surface))
            return Redirect("/stage-ops");

        switch (Surface)
        {
            case StageOpsSurfaces.Ctas:
                Title = "CTAS";
                Badge = "Oracle · paralel üretim";
                Subtitle = "Mevcut oracleCTAS scriptleri. Seçin, MaxParallel ile eşzamanlı sqlplus çalıştırın. Canlı satır sayımı yok — performans korunur.";
                Hint = "Öneri: ağır tablolar (300M) için MaxParallel 2; script içi PARALLEL aynen kalır.";
                DefaultParallel = 2;
                break;
            case StageOpsSurfaces.TransferSql:
                Title = "TRANSFER SQL";
                Badge = "izgazMGR → energy";
                Subtitle = "Mevcut SP_MIGRATE_* prosedürleri. Resume destekli; hatalar MIG_BATCH_LOG’da. Transfer Studio’dan bağımsız.";
                Hint = "Sıralı çalıştırma (MaxParallel=1). Bağımlı stage’leri sırayla seçin.";
                DefaultParallel = 1;
                break;
            default:
                Title = "PROD SQL";
                Badge = "PROD · şema gate";
                Subtitle = "PROD’a gidecek scriptleri yükleyin veya seçin. Kaynak–hedef şema uyumu run öncesi kontrol edilir.";
                Hint = "Önce .sql yükleyin; Invalid syntax’lı stage çalıştırılamaz.";
                DefaultParallel = 1;
                break;
        }

        return Page();
    }
}
