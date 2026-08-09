# 🚀 Quick Engine Start Guide

## TL;DR - En Hızlı Yöntem

```
1. Web UI başlat: .\start-all.ps1
2. Wizard'ı tamamla: http://localhost:5000/wizard
3. "Start Engine Now" butonuna bas
4. ✅ TAMAM!
```

**Hiç terminal komutu yazmanıza gerek yok!**

---

## 🎯 3 Yöntem - Engine Başlatma

### Yöntem 1: 🚀 Web UI'dan (EN KOLAY - YENİ!)

**Adımlar:**

1. **Web UI'ı başlat:**
   ```powershell
   .\start-all.ps1
   ```
   veya manuel:
   ```powershell
   cd Migratorv0
   dotnet run
   ```

2. **Dashboard'a git:**
   ```
   http://localhost:5000
   ```

3. **"Start Engine" butonuna bas:**
   - Dashboard sayfasının üstünde "Migration Engine Control" paneli
   - Yeşil "Start Engine" butonu
   - Tek tıkla başlar!

**Ne Olur:**
- ✅ Otomatik build
- ✅ Engine başlatılır
- ✅ Console penceresi açılır (log'ları görebilirsiniz)
- ✅ Dashboard'da real-time monitoring başlar
- ✅ Status badge "Running" olur

### Yöntem 2: 🎨 Wizard Sonrası (ÖNERILEN)

**Adımlar:**

1. **Wizard'ı tamamla:**
   ```
   http://localhost:5000/wizard
   ```

2. **Config kaydet:**
   - 4 adımı tamamla
   - "Save & Continue" butonuna bas
   - Start page'e yönlendirilirsiniz

3. **"Start Engine Now" butonuna bas:**
   - Otomatik build + start
   - Dashboard'a yönlendirilirsiniz

**Avantajları:**
- Configuration + Start tek akışta
- Hızlı ve kolay
- Hata riski düşük

### Yöntem 3: 💻 Manuel Terminal (ESKİ YÖNTEM)

**Adımlar:**

1. **Yeni terminal aç**

2. **Engine klasörüne git:**
   ```powershell
   cd MigrationEngine
   ```

3. **Engine'i başlat:**
   ```powershell
   dotnet run
   ```

**Dezavantajları:**
- ❌ Terminal bilgisi gerekli
- ❌ Manuel komut yazma
- ❌ Hata riski yüksek
- ❌ Yavaş

---

## 🎮 Kullanıcı Akışları

### Akış 1: İlk Kullanım (Wizard + Auto Start)

```
START
  ↓
1. .\start-all.ps1              (PowerShell çalıştır)
  ↓
2. Browser açılır               (http://localhost:5000)
  ↓
3. Wizard'a git                 (Sağ üstte "Wizard")
  ↓
4. Oracle connection gir        (Step 1)
  ↓
5. MSSQL connection gir         (Step 2)
  ↓
6. Tabloları seç               (Step 3)
  ↓
7. Options ayarla              (Step 4)
  ↓
8. "Save & Continue"
  ↓
9. "Start Engine Now" butonuna bas  🚀
  ↓
10. Dashboard açılır
  ↓
11. ✅ Migration başladı!
  ↓
END
```

**Toplam Süre: ~3 dakika**

### Akış 2: Hızlı Restart (Sadece Buton)

```
START
  ↓
1. Web UI zaten çalışıyor
  ↓
2. Dashboard'a git              (http://localhost:5000)
  ↓
3. "Start Engine" butonuna bas  🚀
  ↓
4. ✅ Engine başladı!
  ↓
END
```

**Toplam Süre: ~5 saniye**

### Akış 3: Engine Durdu - Yeniden Başlat

```
START (Engine durmuş)
  ↓
1. Dashboard'da status: "Stopped"
  ↓
2. "Start Engine" butonuna bas
  ↓
3. Engine başlar
  ↓
4. Checkpoint'ten devam eder
  ↓
5. ✅ Migration devam ediyor!
  ↓
END
```

---

## 🎛️ Engine Kontrol Paneli

Dashboard'da göreceğiniz panel:

```
┌──────────────────────────────────────────────┐
│  🚀 Migration Engine Control                 │
│                                               │
│  Engine status: [🟢 Running (PID: 12345)]    │
│                                               │
│  [Start Engine]  [Stop Engine]               │
└──────────────────────────────────────────────┘
```

**Status Durumları:**

| Status | Badge | Açıklama | Buton |
|--------|-------|----------|-------|
| 🟢 Running | Yeşil | Engine çalışıyor | Stop aktif |
| ⚪ Stopped | Gri | Engine durmuş | Start aktif |
| 🟡 Starting | Sarı | Başlatılıyor | Disabled |
| 🟡 Stopping | Sarı | Durduruluyor | Disabled |
| 🔴 Error | Kırmızı | Hata | Start aktif |

---

## 🔍 Status Monitoring

Dashboard **her 5 saniyede bir** otomatik kontrol eder:

```javascript
// Otomatik monitoring
setInterval(() => {
    checkEngineStatus();  // API çağrısı
}, 5000);
```

**Gösterilen Bilgiler:**
- Engine durumu (Running/Stopped/Error)
- Process ID (PID)
- Başlama zamanı
- Uptime (kaç saniye çalışıyor)
- Configuration durumu

---

## 🛑 Engine Durdurma

**Dashboard'dan:**

1. "Stop Engine" butonuna bas
2. Onay penceresi: "Are you sure?"
3. ✅ Engine gracefully durdurulur

**Ne Olur:**
- ✅ Checkpoint kaydedilir
- ✅ CTRL+C simüle edilir
- ✅ 5 saniye graceful shutdown
- ✅ Process tree temizlenir
- ✅ Restart yapılabilir

**Console'dan (Manuel):**
- CTRL+C tuşuna bas
- Gracefully durdurulur
- Dashboard'da status "Stopped" olur

---

## 📊 API Endpoints

Web UI'ın kullandığı API'ler:

```
POST /api/engine/start    → Engine'i başlat
POST /api/engine/stop     → Engine'i durdur
GET  /api/engine/status   → Durumu kontrol et
POST /api/engine/build    → Build yap (otomatik)
```

**Örnek Response:**

```json
// Status
{
  "status": "running",
  "pid": 12345,
  "startTime": "2026-04-20T23:30:00",
  "uptime": 123.45
}

// Start
{
  "success": true,
  "message": "Migration Engine started successfully",
  "pid": 12345,
  "path": "C:\\...\\MigrationEngine"
}
```

---

## 💡 Pro Tips

### Tip 1: Hızlı Test İçin

```powershell
# Terminal 1: Web UI
cd Migratorv0
dotnet run

# Browser'da Dashboard
# "Start Engine" bas
# ✅ TAMAM!
```

### Tip 2: Wizard Flow

```
Wizard → Save → Start Page → "Start Engine Now" → Dashboard
```

En hızlı ve güvenli yöntem!

### Tip 3: Console Log'larını İzle

Engine başladığında ayrı bir console penceresi açılır:

```
┌─────────────────────────────────────┐
│ MigrationEngine Console             │
│                                     │
│ [INFO] Migration started...        │
│ [INFO] Phase 1: Schema Discovery   │
│ [INFO] Found 10 tables...          │
│ ...                                 │
└─────────────────────────────────────┘
```

Bu pencereyi kapatmayın! (Migration durur)

### Tip 4: Dashboard vs Console

- **Dashboard**: Real-time progress, grafik, istatistikler
- **Console**: Detaylı log mesajları, debug bilgisi

İkisini birden kullanın!

---

## ❓ Troubleshooting

### Problem 1: "Start Engine" butonu çalışmıyor

**Çözüm:**
1. Console'da hata var mı kontrol et (F12 → Console)
2. `appsettings.json` var mı kontrol et:
   ```powershell
   Test-Path MigrationEngine/appsettings.json
   ```
3. Wizard'ı tekrar çalıştır

### Problem 2: Engine başlamıyor

**Çözüm:**
1. Manuel build dene:
   ```powershell
   cd MigrationEngine
   dotnet build -c Release
   ```
2. Hata mesajını oku
3. Missing dependencies varsa:
   ```powershell
   dotnet restore
   ```

### Problem 3: Status "Error" gösteriyor

**Çözüm:**
1. Console log'larını kontrol et
2. Manual başlatma dene:
   ```powershell
   cd MigrationEngine
   dotnet run
   ```
3. Hata mesajını dokümante et

### Problem 4: "Already running" mesajı

**Çözüm:**
1. Gerçekten çalışıyor mu kontrol et:
   - Console penceresi açık mı?
   - Task Manager'da process var mı?
2. Stop butonu ile durdur
3. Tekrar Start

---

## 🎉 Özet

| Özellik | Durum |
|---------|-------|
| Web UI'dan başlatma | ✅ |
| Tek butona basarak | ✅ |
| Otomatik build | ✅ |
| Real-time status | ✅ |
| Start/Stop kontrol | ✅ |
| Console log monitoring | ✅ |
| Graceful shutdown | ✅ |
| Checkpoint recovery | ✅ |

## 🚀 Sonuç

**Artık Migration Engine'i başlatmak için sadece:**

1. Web UI'ı aç
2. Butona bas
3. ✅ TAMAM!

**Terminal bilgisi gereksiz!** 🎉

---

**İlgili Dokümantasyon:**
- [ENGINE_CONTROL_FEATURE.md](ENGINE_CONTROL_FEATURE.md) - Teknik detaylar
- [BASLANGIC.md](BASLANGIC.md) - Hızlı başlangıç
- [INDEX.md](INDEX.md) - Tüm dokümantasyon
