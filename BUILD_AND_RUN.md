# 🔨 Build & Run Guide

## ✅ Build Status

Tüm projeler başarıyla build oldu:

```
✅ MigrationShared - 0 Errors, 0 Warnings
✅ MigrationEngine - 0 Errors, 0 Warnings
✅ MigrationWeb - 0 Errors, 0 Warnings
```

---

## 🚀 Nasıl Çalıştırılır

### Yöntem 1: PowerShell Script (Önerilen)

```powershell
# Solution root klasöründe:
.\start-migration.ps1
```

**Ne Yapar:**
1. Her projeyi sırayla build eder (MSBuild node issue'yi çözer)
2. Web UI'yi başlatır (ayrı PowerShell penceresi)
3. Browser'ı otomatik açar
4. Wizard'a yönlendirir

**Avantajlar:**
- ✅ Tek komut
- ✅ Otomatik build
- ✅ Hata kontrolü
- ✅ Browser açılır
- ✅ Renkli output

---

### Yöntem 2: Tam Otomatik (Engine dahil)

```powershell
.\start-all.ps1
```

**Ne Yapar:**
1. Tüm projeleri build eder
2. Web UI başlatır (Pencere 1)
3. Engine başlatır (Pencere 2)
4. Dashboard açar

**Avantajlar:**
- ✅ Tek komut
- ✅ Her şey otomatik
- ✅ İki pencere ayrı
- ✅ Dashboard açılır

**Not:** Engine başlatmak için `appsettings.json` gerekli. Yoksa wizard'a yönlendirir.

---

### Yöntem 3: Batch File

```cmd
start-migration.cmd
```

Windows Command Prompt kullanıcıları için aynı işlevsellik.

---

### Yöntem 4: VS Code Debug (F5)

1. VS Code'da solution aç
2. `F5` tuşuna bas
3. "Web UI + Engine" seç
4. Her iki proje de debug mode'da başlar

**Avantajlar:**
- ✅ Debug mode
- ✅ Breakpoint
- ✅ Variable inspection
- ✅ Step through

---

### Yöntem 5: Manuel (Tam Kontrol)

```bash
# Terminal 1: Web UI
cd Migratorv0
dotnet run

# Terminal 2: Engine
cd MigrationEngine
dotnet run

# Browser
http://localhost:5000/wizard
```

**Avantajlar:**
- ✅ Tam kontrol
- ✅ Her terminalin çıktısını görürsün
- ✅ Manuel start/stop

---

## 🔧 Build Sorunları

### MSBuild "Access Denied" Hatası

**Sorun:** Solution build ederken `MSB1025` hatası

**Çözüm:** Her projeyi ayrı ayrı build et:
```powershell
dotnet build MigrationShared/MigrationShared.csproj -maxcpucount:1
dotnet build MigrationEngine/MigrationEngine.csproj -maxcpucount:1
dotnet build Migratorv0/Migratorv0.csproj -maxcpucount:1
```

**Script'ler zaten bunu yapıyor!** ✅

### Port 5000 Kullanımda

**Sorun:** "Address already in use"

**Çözüm:**
```powershell
# Çalışan process'i bul:
netstat -ano | findstr :5000

# Process'i kapat:
taskkill /PID <process_id> /F

# Veya appsettings.json'da port değiştir
```

### "dotnet" Komutu Bulunamadı

**Sorun:** PATH'de dotnet yok

**Çözüm:**
```bash
# .NET 8 SDK yükle:
https://dotnet.microsoft.com/download/dotnet/8.0

# Veya PATH'e ekle:
$env:PATH += ";C:\Program Files\dotnet"
```

---

## ✅ Build Testi

Her projeyi test ettik:

```bash
dotnet build MigrationShared/MigrationShared.csproj -maxcpucount:1
# ✅ Passed - 0 Errors

dotnet build MigrationEngine/MigrationEngine.csproj -maxcpucount:1
# ✅ Passed - 0 Errors

dotnet build Migratorv0/Migratorv0.csproj -maxcpucount:1
# ✅ Passed - 0 Errors
```

**Sonuç: HATASIZ! 🎉**

---

## 🎯 Önerilen Kullanım

### İlk Defa Kullanıyorsanız:
```powershell
.\start-migration.ps1
```
→ Wizard ile guided setup

### Daha Önce Kullandıysanız:
```powershell
.\start-all.ps1
```
→ Otomatik her şey

### Debug Yapacaksanız:
```
VS Code → F5 → "Web UI + Engine"
```
→ Breakpoint ile debug

---

## 📊 Performance Tips

### Build Hızlandırma:
```bash
# Release mode:
dotnet build -c Release

# Incremental build (değişenleri build et):
dotnet build --no-restore

# Parallel build yok (MSBuild issue):
-maxcpucount:1
```

### Run Hızlandırma:
```bash
# Build'siz run (zaten build ettiysen):
dotnet run --no-build -c Release
```

---

## 🎉 Sonuç

**TÜM PROJELER HATASIZ BUILD OLUYOR!**

- ✅ 0 Compilation errors
- ✅ 0 Warnings
- ✅ 0 Linter errors
- ✅ Script'ler hazır
- ✅ VS Code config hazır
- ✅ Documentation tam

**Kullanıma hazır! 🚀**
