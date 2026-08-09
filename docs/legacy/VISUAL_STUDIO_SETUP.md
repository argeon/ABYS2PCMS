# Visual Studio ile Tek F5'te Her İki Projeyi Başlatma

## 🎯 Hedef

F5'e basınca hem **Web UI** hem de **Migration Engine** başlasın.

## 📋 Adım Adım Kurulum

### Adım 1: Solution'ı Aç

1. Visual Studio'yu başlat
2. **File** → **Open** → **Project/Solution**
3. `OracleMssqlMigration.sln` dosyasını seç
4. Solution açıldığında 3 proje göreceksiniz:
   - MigrationShared
   - MigrationEngine
   - Migratorv0

### Adım 2: Multiple Startup Projects Ayarla

1. **Solution Explorer**'da solution'a (en üstteki öğe) **sağ tıklayın**
2. **"Set Startup Projects..."** seçin
3. Açılan pencerede:

   **"Multiple startup projects"** radio button'ını seçin

4. Proje listesinde:

   | Project | Action | Ayarlama |
   |---------|--------|----------|
   | MigrationShared | None | Değiştirme (Class library başlatılmaz) |
   | MigrationEngine | **Start** | ✅ Burası önemli! |
   | Migratorv0 | **Start** | ✅ Burası önemli! |

5. **OK**'e tıklayın

### Adım 3: Test Et

1. **F5**'e basın veya **Debug → Start Debugging**
2. Ne olacak:
   - ✅ Bir konsol penceresi açılacak (MigrationEngine)
   - ✅ Browser açılacak (Web UI - http://localhost:5000)
   - ✅ Her ikisi de debug modunda çalışacak
   - ✅ Breakpoint'ler her iki projede de çalışacak

## 🖼️ Görsel Referans

### Solution Explorer Görünümü

```
Solution 'OracleMssqlMigration' (3 of 3 projects)
├─ MigrationShared
├─ MigrationEngine     ← Startup project (🚀)
└─ Migratorv0          ← Startup project (🚀)
```

### Properties Penceresi (Multiple Startup Projects)

```
⚪ Single startup project:  [dropdown]
⦿ Multiple startup projects:

Projects                 Action
─────────────────────── ──────────
MigrationShared          None
MigrationEngine          Start    ← ✅
Migratorv0               Start    ← ✅
```

## 🔍 Sorun Giderme

### Problem: "Start" seçeneği yok

**Çözüm:** Projeye sağ tıklayın → **"Set as Startup Project"** seçin, sonra tekrar Multiple Startup Projects'e dönün.

### Problem: Sadece bir proje başlıyor

**Çözüm:** 
1. Solution'a sağ tık → Properties
2. "Multiple startup projects" seçili mi kontrol edin
3. Her iki projenin de Action = "Start" olduğundan emin olun

### Problem: Engine hata veriyor

**Çözüm:** 
1. İlk olarak Web UI wizard'ını çalıştırın (`.\start-migration.ps1`)
2. Wizard'da connectionları test edin ve kaydedin
3. Sonra "Save & Continue" ile config oluşturun
4. Artık Engine çalışabilir (appsettings.json var)

### Problem: Port çakışması

**Çözüm:** 
- Web UI portu: `Migratorv0/Properties/launchSettings.json` → `applicationUrl` değiştirin
- Engine portu yok (konsol uygulaması)

## 💡 İpuçları

### Debug Modu

F5 ile başlatınca:
- Breakpoint'ler çalışır
- Exception'lar yakalanır
- Output window'da log'lar görünür

### Release Modu

**Ctrl+F5** ile başlatınca:
- Debug olmadan çalışır
- Daha hızlı
- Production gibi davranır

### Sadece Birini Başlat

Geçici olarak sadece birini başlatmak için:
1. O projeye sağ tıklayın
2. **Debug → Start New Instance**

## 🚀 Hızlı Başlangıç Komutları

```powershell
# Build solution
dotnet build OracleMssqlMigration.sln -c Debug

# Visual Studio'dan başlat
# F5 tuşuna bas!

# Veya komut satırından
start devenv OracleMssqlMigration.sln
```

## 📝 Proje Başlangıç Sırası

Visual Studio otomatik olarak şu sırada başlatır:
1. **Migratorv0** (Web UI) - 2-3 saniye
2. **MigrationEngine** (Console) - 1 saniye

Bu sıra önemli değil çünkü:
- Engine appsettings.json okuyor (Web UI wizard'la oluşturulmuş)
- Her ikisi de aynı SQLite checkpoint DB'yi kullanıyor
- Inter-process communication SQLite üzerinden

## ✅ Başarı Göstergeleri

F5'ten sonra görmeniz gerekenler:

1. ✅ **Konsol Penceresi** (MigrationEngine):
   ```
   Oracle → MSSQL Migration Engine Starting...
   Loading configuration...
   ```

2. ✅ **Browser** (Web UI):
   ```
   http://localhost:5000
   Dashboard sayfası açılır
   ```

3. ✅ **Output Window** (Visual Studio):
   ```
   2 project(s) started
   ```

## 🎉 Tamamlandı!

Artık tek bir **F5** ile her iki proje de çalışıyor!

- Web UI → Configuration ve Monitoring
- Engine → Gerçek migration işlemi
- Her ikisi de aynı checkpoint DB'yi paylaşıyor
- Real-time iletişim SignalR ve SQLite polling ile

## 🔗 Diğer Başlatma Yöntemleri

- PowerShell: `.\start-all.ps1`
- VS Code: F5 (.vscode/launch.json)
- Manuel: Her projeyi ayrı terminalde `dotnet run`

---

**Sonuç:** Solution'daki her iki proje de tek bir F5'le başlıyor! 🚀
