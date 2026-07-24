# ✅ TEK SOLUTION - TÜM PROJELER BİRLİKTE!

## 🎯 CEVAP: EVET!

**Solution'da 3 proje var ve hepsi birlikte çalışıyor!**

```
OracleMssqlMigration.sln
├── MigrationShared     ← Ortak modeller
├── MigrationEngine     ← Migration motoru (Console)
└── Migratorv0          ← Web UI (ASP.NET Core)
```

## 🚀 3 FARKLI YÖNTEMLE TEK KOMUTTA BAŞLAT

### Yöntem 1: PowerShell Script (EN KOLAY!)

```powershell
# Her iki projeyi de otomatik başlatır
.\start-all.ps1
```

**Ne yapar:**
- ✅ Solution'ı build eder (3 proje birden)
- ✅ Web UI'ı başlatır (localhost:5000)
- ✅ Migration Engine'i başlatır
- ✅ Browser'ı açar
- ✅ HER ŞEY TEK KOMUTTA!

### Yöntem 2: Visual Studio (F5)

1. `OracleMssqlMigration.sln` dosyasını aç
2. Solution'a sağ tık → **"Set Startup Projects..."**
3. **"Multiple startup projects"** seç
4. Her iki proje için **"Start"** seç:
   - ✅ MigrationEngine → Start
   - ✅ Migratorv0 → Start
5. **F5'e bas** → Her ikisi de başlar!

📖 Detaylı anlatım: `VISUAL_STUDIO_SETUP.md`

### Yöntem 3: VS Code (F5)

1. VS Code'da klasörü aç
2. **F5'e bas**
3. "Web UI + Engine" seç
4. Her ikisi de debug modunda başlar!

## 🔨 TEK KOMUTLA BUILD

```powershell
# Tüm solution'ı build et
dotnet build OracleMssqlMigration.sln -c Release

# Başarılı çıktı:
# Build succeeded.
#     0 Warning(s)
#     0 Error(s)
```

## 📊 PROJE İLİŞKİLERİ

```
MigrationShared (Base)
    ↓
    ├─→ MigrationEngine (Console)
    └─→ Migratorv0 (Web UI)
```

**Shared Library:**
- Ortak modeller (MigrationConfig, TableInfo, etc.)
- Enums (MigrationPhase, PartitionStatus)
- Her iki proje de bunu kullanır

**MigrationEngine:**
- Console uygulaması
- Gerçek migration işini yapar
- SQLite checkpoint DB'ye yazar
- `appsettings.json` okur

**Migratorv0 (Web UI):**
- ASP.NET Core web app
- Real-time monitoring (SignalR)
- Configuration wizard
- SQLite checkpoint DB'yi okur
- Dashboard, History, Analytics

## 🔄 NASIL ÇALIŞIYORLAR?

```
1. Web UI (Wizard)
   ↓
2. appsettings.json oluşturur
   ↓
3. Migration Engine başlar
   ↓
4. SQLite checkpoint DB kullanır
   ↓
5. Web UI real-time okur
```

**İletişim:**
- Inter-process: SQLite database
- Real-time: SQLite polling + SignalR
- Config: JSON dosyalar

## ✅ DOĞRULAMA

```powershell
# Solution'daki projeleri listele
dotnet sln OracleMssqlMigration.sln list

# Çıktı:
# MigrationEngine\MigrationEngine.csproj
# MigrationShared\MigrationShared.csproj
# Migratorv0\Migratorv0.csproj

# 3 PROJE ✓
```

## 🎮 KULLANIM SENARYOLARI

### Senaryo 1: İlk Kullanım

```powershell
# 1. Script ile başlat
.\start-migration.ps1

# 2. Browser açılır → Wizard
# 3. Connection'ları gir
# 4. Tabloları seç
# 5. "Save & Continue"
# 6. Engine'i başlat (komut verilir)
```

### Senaryo 2: Tekrar Kullanım

```powershell
# Tek komut - her şey başlar!
.\start-all.ps1
```

### Senaryo 3: Visual Studio

```
1. OracleMssqlMigration.sln aç
2. F5'e bas
3. Her iki proje de başlar!
```

### Senaryo 4: VS Code

```
1. Klasörü aç
2. F5'e bas
3. Debug mode!
```

## 📁 DOSYA YAPISI

```
Migratorv0/                          ← Root klasör
├── OracleMssqlMigration.sln        ← ANA SOLUTION
├── MigrationShared/                 ← Proje 1
│   ├── Models/
│   └── MigrationShared.csproj
├── MigrationEngine/                 ← Proje 2
│   ├── Checkpoint/
│   ├── Orchestration/
│   ├── appsettings.json
│   └── MigrationEngine.csproj
├── Migratorv0/                      ← Proje 3 (Web UI)
│   ├── Pages/
│   ├── Services/
│   ├── Controllers/
│   ├── wwwroot/
│   └── Migratorv0.csproj
├── start-all.ps1                    ← Otomatik başlatma
├── start-migration.ps1              ← İlk kurulum
└── .vscode/
    └── launch.json                  ← VS Code config
```

## 🎯 ÖZET

| Soru | Cevap |
|------|-------|
| Tek solution mı? | ✅ EVET - `OracleMssqlMigration.sln` |
| Kaç proje var? | **3 proje** (Shared, Engine, Web) |
| Tek komutla build olur mu? | ✅ EVET - `dotnet build OracleMssqlMigration.sln` |
| F5'te her ikisi başlar mı? | ✅ EVET - Multiple Startup Projects ayarlı |
| PowerShell script var mı? | ✅ EVET - `start-all.ps1` |
| VS Code config var mı? | ✅ EVET - `.vscode/launch.json` |

## 🔗 İLGİLİ DOSYALAR

- `SOLUTION_INFO.md` - Detaylı solution bilgisi
- `VISUAL_STUDIO_SETUP.md` - VS ile F5 kurulumu
- `README.md` - Ana dokümantasyon
- `QUICK_START.md` - Hızlı başlangıç

## 💡 ÖNEMLİ NOTLAR

1. **Solution dosyası 2 formatta var:**
   - `OracleMssqlMigration.sln` (klasik, VS için)
   - `OracleMssqlMigration.slnx` (yeni XML format)

2. **Her iki proje de bağımsız çalışabilir:**
   - Web UI → Sadece monitoring
   - Engine → Sadece migration

3. **Ama birlikte çalışınca:**
   - Real-time monitoring ✓
   - Wizard ile kolay config ✓
   - History ve analytics ✓

4. **Inter-process communication:**
   - SQLite checkpoint database
   - Her iki proje de aynı DB'yi kullanır
   - Engine yazar, Web UI okur

## 🎉 SONUÇ

**EVET, TEK SOLUTION! Tek komutla her şey çalışır!** 🚀

```powershell
# Kanıtı:
dotnet sln OracleMssqlMigration.sln list

# Çıktı:
# 3 proje ✓ Tek solution ✓ Hepsi birlikte ✓
```

---

**Artık tek bir F5 veya tek bir PowerShell komutuyla tüm sistem çalışır!** 🎯
