# 🚀 Quick Start Guide

## Tek Komutla Başlatma

### Seçenek 1: Wizard ile Başlatma (İlk Kullanım)

```powershell
# PowerShell'de çalıştır:
.\start-migration.ps1
```

**Ne Yapar:**
1. ✅ Solution'ı build eder
2. ✅ Web UI'yi başlatır
3. ✅ Browser'ı açar → Wizard
4. ✅ Adım adım konfigürasyon

**Adımlar:**
1. Script çalıştır
2. Browser açılınca wizard'ı takip et:
   - Oracle connection → Test
   - MSSQL connection → Test
   - Tabloları seç
   - Save & Continue
3. Start sayfasındaki talimatları takip et
4. Yeni terminal'de: `cd MigrationEngine; dotnet run`
5. Dashboard'da izle!

---

### Seçenek 2: Her Şeyi Otomatik Başlat (Config Hazırsa)

```powershell
# PowerShell'de çalıştır:
.\start-all.ps1
```

**Ne Yapar:**
1. ✅ Solution'ı build eder
2. ✅ Web UI'yi başlatır (ayrı pencere)
3. ✅ Engine'i başlatır (ayrı pencere)
4. ✅ Dashboard'u açar

**Adımlar:**
1. Script çalıştır
2. İki pencere açılır (Web + Engine)
3. Browser otomatik açılır
4. Dashboard'da real-time monitoring!

---

### Seçenek 3: Batch File ile (Basit)

```cmd
# Command Prompt'ta çalıştır:
start-migration.cmd
```

Aynı şekilde çalışır, sadece .bat format.

---

## Hangi Seçeneği Kullanmalıyım?

### İlk Kez Kullanıyorsanız:
→ **`start-migration.ps1`** (Wizard ile)

### Daha önce config oluşturduysanız:
→ **`start-all.ps1`** (Otomatik her şey)

### Script kullanmak istemiyorsanız:
→ Manuel başlatma (aşağıda)

---

## Manuel Başlatma

### Adım 1: Web UI
```bash
cd Migratorv0
dotnet run
```

### Adım 2: Wizard'da Konfigüre Et
```
http://localhost:5000/wizard
```

### Adım 3: Engine Başlat
```bash
cd MigrationEngine
dotnet run
```

### Adım 4: Monitor
```
http://localhost:5000
```

---

## Script Detayları

### start-migration.ps1
- Web UI'yi başlatır
- Wizard'a yönlendirir
- Engine'i sen başlat

### start-all.ps1
- Her şeyi otomatik başlatır
- İki ayrı terminal penceresi
- Dashboard otomatik açılır

### start-migration.cmd
- Windows Batch versiyonu
- Basit, batch file kullanıcıları için

---

## Troubleshooting

### "dotnet bulunamadı" Hatası
```bash
# .NET 8 SDK yükleyin:
https://dotnet.microsoft.com/download/dotnet/8.0
```

### "Build failed" Hatası
```bash
# Solution'ı manuel build edin:
dotnet build OracleMssqlMigration.slnx
```

### Port 5000 Kullanımda
```bash
# appsettings.json'da portu değiştirin
# Veya çalışan uygulamayı durdurun
```

### Script Çalışmıyor
```bash
# PowerShell execution policy:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Sonraki Adımlar

1. ✅ Script ile başlat
2. ✅ Wizard'da konfigüre et
3. ✅ Migration'ı başlat
4. ✅ Dashboard'da izle
5. ✅ History'de analiz et

**Kolay gelsin! 🎉**
