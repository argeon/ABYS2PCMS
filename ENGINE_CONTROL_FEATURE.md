# 🚀 Engine Control Feature - Manuel Tetikleme

## ✅ YENİ ÖZELLİK: Web UI'dan Engine Başlatma

Artık Migration Engine'i **Web UI'dan tek bir butona basarak** başlatabilirsiniz!

## 🎯 Özellikler

### 1. **Dashboard'dan Başlatma**

Ana sayfada (`http://localhost:5000`) yeni bir kontrol paneli:

```
┌────────────────────────────────────────────────────┐
│  🚀 Migration Engine Control                       │
│                                                     │
│  Engine status: [Running]                          │
│                                                     │
│  [Start Engine]  [Stop Engine]                     │
└────────────────────────────────────────────────────┘
```

**Özellikler:**
- ✅ Tek tıkla başlatma
- ✅ Otomatik build (gerekirse)
- ✅ Real-time status monitoring
- ✅ Stop/Start kontrol
- ✅ PID gösterimi
- ✅ Uptime tracking

### 2. **Start Page'den Başlatma**

Wizard'dan config kaydettikten sonra (`/start`):

```
Quick Actions:
[🚀 Start Engine Now]  [📊 Go to Dashboard]
```

**Flow:**
1. Wizard'da config yap
2. "Save & Continue" → `/start` sayfasına yönlendirilirsiniz
3. "Start Engine Now" butonuna bas
4. Otomatik build + start
5. Dashboard'a yönlendirilirsiniz

### 3. **Otomatik Status Monitoring**

Dashboard her 5 saniyede bir engine durumunu kontrol eder:

- ✅ **Running**: Yeşil badge, Stop butonu aktif
- ⏸️ **Stopped**: Gri badge, Start butonu aktif
- ❌ **Error**: Kırmızı badge

## 🔧 Teknik Detaylar

### API Endpoints

**EngineController** ile 4 yeni endpoint:

```
POST /api/engine/start   → Engine'i başlat
POST /api/engine/stop    → Engine'i durdur
GET  /api/engine/status  → Engine durumunu al
POST /api/engine/build   → Engine'i build et
```

### Process Management

```csharp
// Engine başlatma
ProcessStartInfo {
    FileName = "dotnet",
    Arguments = "run --no-build -c Release",
    WorkingDirectory = enginePath,
    CreateNoWindow = false  // Console penceresi göster
}
```

**Özellikler:**
- ✅ Console penceresi gösterilir (log'ları görebilirsiniz)
- ✅ Process ID tracking
- ✅ Graceful shutdown (CTRL+C simulation)
- ✅ Process tree kill (tüm child process'ler)
- ✅ Thread-safe (lock mekanizması)

## 📂 Yeni Dosyalar

### Backend
1. **`Controllers/EngineController.cs`** (YENİ)
   - `POST /api/engine/start` - Engine başlat
   - `POST /api/engine/stop` - Engine durdur
   - `GET /api/engine/status` - Status kontrol
   - `POST /api/engine/build` - Build engine

### Frontend
1. **`Pages/Index.cshtml`** (GÜNCELLENDİ)
   - Engine Control Panel eklendi
   - Start/Stop butonları
   - Status badge

2. **`Pages/Start.cshtml`** (GÜNCELLENDİ)
   - "Start Engine Now" butonu
   - Otomatik başlatma

3. **`wwwroot/js/dashboard.js`** (GÜNCELLENDİ)
   - `startMigrationEngine()` fonksiyonu
   - `stopMigrationEngine()` fonksiyonu
   - `checkEngineStatus()` fonksiyonu
   - `startEngineStatusMonitoring()` - 5 sn interval

## 🚀 Kullanım

### Yöntem 1: Dashboard'dan (Önerilen)

1. Web UI'ı başlat:
   ```bash
   cd Migratorv0
   dotnet run
   ```

2. Browser'da aç: `http://localhost:5000`

3. **"Start Engine"** butonuna bas

4. Engine otomatik:
   - ✅ Build edilir
   - ✅ Başlatılır
   - ✅ Console penceresi açılır
   - ✅ Dashboard'da monitoring başlar

### Yöntem 2: Start Page'den

1. Wizard'ı tamamla: `http://localhost:5000/wizard`

2. "Save & Continue" → `/start` sayfası

3. **"Start Engine Now"** butonuna bas

4. Otomatik dashboard'a yönlendirilirsiniz

### Yöntem 3: Manuel (Eski Yöntem)

Hala manuel de başlatabilirsiniz:

```bash
cd MigrationEngine
dotnet run
```

## 🎮 Kullanıcı Akışı

### Tam Otomatik Akış

```
1. http://localhost:5000/wizard
   ↓
2. Connection'ları gir (Step 1-2)
   ↓
3. Tabloları seç (Step 3)
   ↓
4. Options ayarla (Step 4)
   ↓
5. "Save & Continue"
   ↓
6. "Start Engine Now" butonuna bas
   ↓
7. ✅ Engine başladı!
   ↓
8. Dashboard'da real-time izle
```

**Hiç terminal'e gerek yok!** 🎉

## 📊 Engine Status States

| Status | Badge | Açıklama | Butonlar |
|--------|-------|----------|----------|
| **Running** | 🟢 Yeşil | Engine çalışıyor | Stop aktif |
| **Stopped** | ⚪ Gri | Engine durmuş | Start aktif |
| **Starting** | 🟡 Sarı | Başlatılıyor | Disabled |
| **Stopping** | 🟡 Sarı | Durduruluyor | Disabled |
| **Error** | 🔴 Kırmızı | Hata | Start aktif |

## 🔍 Monitoring

### Real-time Status Updates

Dashboard her 5 saniyede bir kontrol eder:

```javascript
setInterval(() => {
    checkEngineStatus();
}, 5000);
```

**Gösterilen Bilgiler:**
- Engine status (Running/Stopped)
- Process ID (PID)
- Start time
- Uptime (saniye)
- Configuration durumu

## ⚠️ Önemli Notlar

### 1. Configuration Kontrolü

Engine başlatılmadan önce kontrol edilir:

```
if (!appsettings.json exists) {
    Error: "Please configure via Wizard first"
    Suggestion: "Go to /wizard"
}
```

### 2. Duplicate Process Check

```
if (engine already running) {
    Error: "Migration Engine already running"
    PID: 12345
}
```

### 3. Console Window

Engine başlatıldığında:
- ✅ Ayrı console penceresi açılır
- ✅ Log'ları görebilirsiniz
- ✅ CTRL+C ile durdurul abilir (manuel)
- ✅ Web UI'dan da durdurulabilir

### 4. Graceful Shutdown

Stop butonu:
- ✅ CTRL+C simüle eder
- ✅ Checkpoint kaydedilir
- ✅ 5 saniye graceful shutdown
- ✅ Process tree temizlenir

## 🎯 Avantajlar

### Önceki Yöntem (Manuel)

```
1. Web UI başlat
2. Browser'da wizard
3. Config kaydet
4. Terminal aç
5. cd MigrationEngine
6. dotnet run
7. Dashboard'a dön
```

**7 adım** ❌

### Yeni Yöntem (Otomatik)

```
1. Web UI başlat
2. Browser'da wizard
3. Config kaydet
4. "Start Engine Now" butonu
```

**4 adım** ✅

**%43 daha az adım!** 🎉

## 🧪 Test

### Build Test

```powershell
# Manuel test
cd MigrationEngine
dotnet build -c Release
```

### Start Test

```bash
# Web UI başlat
cd Migratorv0
dotnet run

# Browser'da
http://localhost:5000

# "Start Engine" butonuna bas
# Console penceresi açılmalı
# Dashboard'da status "Running" olmalı
```

### Status Test

```bash
# API'yi test et
curl http://localhost:5000/api/engine/status

# Response:
{
  "status": "running",
  "pid": 12345,
  "startTime": "2026-04-20T23:30:00",
  "uptime": 123.45
}
```

## 📝 Örnek Senaryolar

### Senaryo 1: İlk Kullanım

1. `.\start-all.ps1` çalıştır
2. Browser otomatik açılır
3. Wizard'ı tamamla
4. "Start Engine Now" bas
5. ✅ Migration başlar!

### Senaryo 2: Tekrar Kullanım

1. Web UI zaten çalışıyor
2. Dashboard'a git
3. "Start Engine" bas
4. ✅ Engine başlar (config zaten var)

### Senaryo 3: Hata Durumu

1. Engine hata verdi ve durdu
2. Dashboard'da "Start Engine" bas
3. Engine tekrar başlar
4. Checkpoint'ten devam eder!

## 🎊 Özet

| Özellik | Durum |
|---------|-------|
| Web UI'dan başlatma | ✅ |
| Otomatik build | ✅ |
| Status monitoring | ✅ |
| Stop/Start kontrol | ✅ |
| Console window | ✅ |
| Graceful shutdown | ✅ |
| PID tracking | ✅ |
| Error handling | ✅ |

## 🔗 İlgili API'ler

### JavaScript

```javascript
// Engine başlat
await fetch('/api/engine/start', { method: 'POST' });

// Engine durdur
await fetch('/api/engine/stop', { method: 'POST' });

// Status kontrol
const status = await fetch('/api/engine/status');

// Build
await fetch('/api/engine/build', { method: 'POST' });
```

### C# Controller

```csharp
[HttpPost("start")]
public IActionResult StartEngine()
{
    // Process.Start logic
    return Ok(new { success = true, pid = process.Id });
}
```

## ✨ Kullanıcı Deneyimi

**Önceden:**
- Terminal bilgisi gerekiyordu
- Manuel komut yazılıyordu
- Hata riski yüksekti

**Şimdi:**
- ✅ Tek buton!
- ✅ Otomatik build
- ✅ Otomatik start
- ✅ Hata yönetimi
- ✅ Status monitoring

**Artık hiç terminal bilgisi olmadan migration yapabilirsiniz!** 🚀

## 🎉 SONUÇ

Engine artık **tek butona basarak** başlatılabiliyor:

1. ✅ Dashboard'dan "Start Engine" butonu
2. ✅ Start page'den "Start Engine Now" butonu
3. ✅ Otomatik build + start
4. ✅ Real-time status monitoring
5. ✅ Stop/Start kontrol
6. ✅ Hata yönetimi

**Kullanımı çok daha kolay!** 🎯
