# 🚀 Oracle → MSSQL Migration Tool - BAŞLANGIÇ REHBERİ

## ✅ EVET! TEK SOLUTION, 3 PROJE

```
OracleMssqlMigration.sln
├── MigrationShared     (Ortak kütüphane)
├── MigrationEngine     (Console - Migration motoru)
└── Migratorv0          (Web UI - Monitoring)
```

## 🎯 3 KOLAY YÖNTEM

### Yöntem 1: PowerShell Script (EN KOLAY!)

```powershell
# Her şeyi otomatik başlatır
.\start-all.ps1
```

**Bu tek komut:**
- ✅ Solution'ı build eder
- ✅ Web UI'ı başlatır (http://localhost:5000)
- ✅ Migration Engine'i başlatır
- ✅ Browser'ı açar
- ✅ HER ŞEY TEK KOMUTTA ÇALIŞIR!

### Yöntem 2: Visual Studio (F5)

1. `OracleMssqlMigration.sln` dosyasını aç
2. Solution'a sağ tık → "Set Startup Projects..."
3. "Multiple startup projects" seç
4. **MigrationEngine** → Start
5. **Migratorv0** → Start
6. **F5'e bas!**

📖 Detaylı anlatım: [VISUAL_STUDIO_SETUP.md](VISUAL_STUDIO_SETUP.md)

### Yöntem 3: VS Code (F5)

1. VS Code'da klasörü aç
2. **F5'e bas**
3. "Web UI + Engine" seç
4. Her ikisi de debug modunda başlar!

## 📖 DOKÜMANTASYON

| Ne Arıyorsunuz? | Hangi Dosya? |
|-----------------|--------------|
| ⭐ "Tek solution mı?" | [TEK_SOLUTION_BILGI.md](TEK_SOLUTION_BILGI.md) |
| ⭐ Visual Studio F5 kurulumu | [VISUAL_STUDIO_SETUP.md](VISUAL_STUDIO_SETUP.md) |
| Solution detayları | [SOLUTION_INFO.md](SOLUTION_INFO.md) |
| Hızlı başlangıç | [QUICK_START.md](QUICK_START.md) |
| Tam dokümantasyon | [README.md](README.md) |
| Tüm dosya listesi | [INDEX.md](INDEX.md) |

## 🔨 TEK KOMUTLA BUILD

```powershell
# Solution'ın tümünü build et
dotnet build OracleMssqlMigration.sln -c Release
```

## 🎮 İLK KULLANIMDA NE YAPMALI?

### Adım 1: Projeleri Başlat

```powershell
# İlk kurulum için
.\start-migration.ps1
```

Veya F5 (Visual Studio / VS Code)

### Adım 2: Wizard'ı Kullan

Browser otomatik açılır: `http://localhost:5000/wizard`

1. **Oracle Connection** gir ve test et
2. **MSSQL Connection** gir ve test et
3. **Tabloları seç** (row count ile)
4. **Save & Continue**

### Adım 3: Migration'ı İzle

Dashboard'da real-time:
- ✅ Phase progress
- ✅ Table status
- ✅ Active threads
- ✅ Performance metrics
- ✅ Log stream

## 🎉 ÖNEMLİ NOKTALAR

### ✅ Tüm Projeler Tek Solution'da!

```powershell
# Kanıt:
dotnet sln OracleMssqlMigration.sln list

# Çıktı:
# MigrationEngine\MigrationEngine.csproj
# MigrationShared\MigrationShared.csproj
# Migratorv0\Migratorv0.csproj
```

### ✅ Tek Komutla Her Şey Çalışır!

- **PowerShell**: `.\start-all.ps1`
- **Visual Studio**: F5 (Multiple Startup Projects)
- **VS Code**: F5 (launch.json)

### ✅ İnter-process Communication

- **SQLite**: Checkpoint database
- **Web UI**: Real-time monitoring
- **Engine**: Background processing

## 🔗 HIZLI LİNKLER

| Konu | Link |
|------|------|
| ⭐⭐⭐ Tek solution mı? | [TEK_SOLUTION_BILGI.md](TEK_SOLUTION_BILGI.md) |
| ⭐⭐ VS F5 kurulumu | [VISUAL_STUDIO_SETUP.md](VISUAL_STUDIO_SETUP.md) |
| ⭐ Solution yapısı | [SOLUTION_INFO.md](SOLUTION_INFO.md) |
| Hızlı başlat | [QUICK_START.md](QUICK_START.md) |
| Wizard kullanımı | [USAGE_GUIDE.md](USAGE_GUIDE.md) |
| Yeni özellikler | [NEW_FEATURES.md](NEW_FEATURES.md) |
| Tüm index | [INDEX.md](INDEX.md) |

## 💡 SORUN GİDERME

### "Projeler ayrı solution'da mı?"

❌ HAYIR! Hepsi `OracleMssqlMigration.sln` içinde!

### "Tek komutla çalışır mı?"

✅ EVET! 3 yöntemle:
1. `.\start-all.ps1`
2. Visual Studio F5
3. VS Code F5

### "Build hatası alıyorum"

```powershell
# Her projeyi ayrı build et
dotnet build MigrationShared/MigrationShared.csproj -maxcpucount:1
dotnet build MigrationEngine/MigrationEngine.csproj -maxcpucount:1
dotnet build Migratorv0/Migratorv0.csproj -maxcpucount:1
```

### "Engine başlamıyor"

1. İlk olarak Web UI wizard'ını çalıştır
2. Connection'ları test et
3. Config'i kaydet
4. Sonra Engine'i başlat

## 📊 PROJE DURUMU

```
┌────────────────────────────────────┐
│                                    │
│  ✅ SOLUTION: HAZIR               │
│  ✅ PROJELER: 3 TANE              │
│  ✅ BUILD: BAŞARILI               │
│  ✅ SCRIPTS: HAZIR                │
│  ✅ DOKÜMANTASYON: TAM            │
│                                    │
│  STATUS: KULLANIMA HAZIR! 🚀      │
│                                    │
└────────────────────────────────────┘
```

## 🎊 HEMEN BAŞLA!

```powershell
# ADIM 1: Script ile başlat
.\start-all.ps1

# ADIM 2: Browser açılır (http://localhost:5000)

# ADIM 3: Wizard'ı kullan veya Dashboard'a git

# ADIM 4: Migration'ı başlat ve izle!
```

---

**Tüm projeler tek solution'da ve tek komutla çalışıyor!** 🚀

Daha fazla bilgi: [INDEX.md](INDEX.md) - Tüm dokümantasyon listesi
