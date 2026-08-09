# Solution Yapısı ve Çalıştırma Rehberi

## ✅ SOLUTION DURUMU

**Durum:** ✅ TÜM PROJELER TEK SOLUTION'DA!

```
OracleMssqlMigration.sln
├── MigrationShared     (Class Library)
├── MigrationEngine     (Console App)
└── Migratorv0          (Web App - MigrationWeb)
```

## 🎯 TEK KOMUTLA ÇALIŞTIRMA

### Seçenek 1: PowerShell (Otomatik)

```powershell
# İlk kurulum için (Web UI başlatır, wizard açar)
.\start-migration.ps1

# Her şeyi başlatmak için (Web UI + Engine)
.\start-all.ps1
```

### Seçenek 2: Visual Studio

1. `OracleMssqlMigration.sln` dosyasını açın
2. Solution Explorer'da Solution'a sağ tıklayın
3. **"Set Startup Projects..."** seçin
4. **"Multiple startup projects"** seçin
5. Her iki proje için "Action" → **"Start"** seçin:
   - ✅ `MigrationEngine` → Start
   - ✅ `Migratorv0` → Start
6. **F5**'e basın veya Debug → Start Debugging

Artık F5'e her bastığınızda:
- ✅ Web UI (http://localhost:5000) başlar
- ✅ Migration Engine konsol penceresi açılır
- ✅ Her ikisi de aynı SQLite checkpoint DB'yi kullanır

### Seçenek 3: VS Code

1. VS Code'da solution klasörünü açın
2. **F5**'e basın
3. "Web UI + Engine" konfigürasyonunu seçin
4. Her ikisi de debug modunda başlar!

### Seçenek 4: Komut Satırı (Manuel)

```powershell
# Solution'ın tümünü build et
dotnet build OracleMssqlMigration.sln -c Release

# Terminal 1: Web UI
cd Migratorv0
dotnet run --no-build -c Release

# Terminal 2: Migration Engine
cd MigrationEngine
dotnet run --no-build -c Release
```

## 📦 Solution Build

```powershell
# Tüm projeleri birlikte build et
dotnet build OracleMssqlMigration.sln -c Release

# Tüm projeleri temizle
dotnet clean OracleMssqlMigration.sln

# NuGet paketlerini restore et
dotnet restore OracleMssqlMigration.sln
```

## 🔍 Proje Referansları

**MigrationEngine** → Referanslar:
- `MigrationShared` (Project Reference)

**Migratorv0 (Web)** → Referanslar:
- `MigrationShared` (Project Reference)

**MigrationShared** → Referanslar:
- Yok (base class library)

## 🎨 Visual Studio Solution Yapılandırması

Solution Explorer'da görünüm:

```
Solution 'OracleMssqlMigration' (3 of 3 projects)
├─ 📦 MigrationShared
│  ├─ Dependencies
│  ├─ Models/
│  └─ ...
├─ 🖥️ MigrationEngine
│  ├─ Dependencies
│  │  └─ Projects
│  │     └─ MigrationShared
│  ├─ Checkpoint/
│  ├─ Orchestration/
│  └─ Program.cs
└─ 🌐 Migratorv0 (Web)
   ├─ Dependencies
   │  └─ Projects
   │     └─ MigrationShared
   ├─ Pages/
   ├─ Services/
   └─ Program.cs
```

## ✅ Doğrulama

```powershell
# Solution'daki projeleri listele
dotnet sln OracleMssqlMigration.sln list

# Çıktı:
# Project(s)
# ----------
# MigrationEngine\MigrationEngine.csproj
# MigrationShared\MigrationShared.csproj
# Migratorv0\Migratorv0.csproj
```

## 🚀 Hızlı Test

```powershell
# Build testi
dotnet build OracleMssqlMigration.sln

# Başarılı olursa:
# Build succeeded.
#     0 Warning(s)
#     0 Error(s)
```

## 💡 İpuçları

1. **Visual Studio'da F5** = Her iki proje de başlar (Multiple Startup Projects ayarlıysa)
2. **VS Code'da F5** = Hazır launch.json konfigürasyonu ile başlar
3. **PowerShell Script** = Tek komutla her şey otomatik
4. **Tüm projeler aynı solution'da**, ayrı solution değil!

## 🔗 İlgili Dosyalar

- `OracleMssqlMigration.sln` - Ana solution dosyası
- `OracleMssqlMigration.slnx` - Alternatif XML format
- `start-all.ps1` - Her şeyi başlatma scripti
- `start-migration.ps1` - İlk kurulum scripti
- `.vscode/launch.json` - VS Code debug config
- `README.md` - Ana dokümantasyon
