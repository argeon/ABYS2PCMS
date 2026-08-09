# 🔍 Hata Analizi Özelliği

## ✅ ÖZELLİK TAMAMLANDI!

Tüm migration hatalarını (başarılı/başarısız) kaydeden ve analiz eden kapsamlı bir hata yönetim sistemi eklendi.

## 📦 Eklenen Özellikler

### 1. **Otomatik Hata Kaydı (MigrationEngine)**

Migration Engine artık tüm hataları otomatik olarak SQLite veritabanına kaydediyor:

```csharp
// Program.cs içinde otomatik hata kaydı
try {
    // Migration işlemleri...
} catch (Exception ex) {
    extendedCheckpoint.LogError(
        runId,
        tableName,
        partitionId,
        ex.GetType().Name,
        ex.Message,
        ex.StackTrace,
        retryAttempt: 0);
}
```

**Kaydedilen Bilgiler:**
- ✅ Hata tipi (Exception adı)
- ✅ Hata mesajı
- ✅ Stack trace (full)
- ✅ Oluşma zamanı
- ✅ Run ID
- ✅ Tablo adı
- ✅ Partition ID
- ✅ Retry sayısı
- ✅ Çözüldü mü? (boolean)

### 2. **Migration History Tracking**

Her migration'ın durumu (RUNNING/COMPLETED/FAILED) otomatik kaydediliyor:

```csharp
// Başlangıçta
historyId = extendedCheckpoint.CreateMigrationHistory(...);

// Başarılı tamamlandığında
extendedCheckpoint.CompleteMigrationHistory(historyId, totalRows);

// Hata durumunda
extendedCheckpoint.FailMigrationHistory(historyId, errorReason);
```

### 3. **Web UI - Hata Analiz Sayfası**

Yeni sayfa: `http://localhost:5000/errors`

**Özellikler:**
- 📊 **Dashboard Widget'ları**:
  - Toplam hata sayısı
  - Çözülmemiş hatalar
  - Çözülmüş hatalar
  - Etkilenen tablo sayısı

- 🔍 **Filtreleme**:
  - Run ID'ye göre
  - Tabloya göre
  - Hata tipine göre
  - Durum'a göre (Çözülmüş/Çözülmemiş)

- 📈 **Grafikler** (Chart.js):
  - Hata tipi dağılımı (Pie chart)
  - Tabloya göre hatalar (Bar chart - Top 5)

- 📋 **Hata Listesi**:
  - Detaylı hata bilgileri
  - Çözüldü işaretleme (tek veya toplu)
  - Hata detay modal (Stack trace ile)
  - CSV export

### 4. **API Endpoints**

**ErrorsController** ile 8 yeni endpoint:

```
GET  /api/errors                     → Tüm hataları getir
GET  /api/errors/run/{runId}         → Belirli run'daki hatalar
GET  /api/errors/run/{runId}/table/{tableName}  → Tablo bazında hatalar
GET  /api/errors/run/{runId}/stats   → Hata istatistikleri
GET  /api/errors/unresolved          → Çözülmemiş hatalar
GET  /api/errors/summary             → Özet istatistikler
POST /api/errors/{errorId}/resolve   → Hatayı çözüldü işaretle
```

## 🗃️ Veritabanı Şeması

**`error_log` Tablosu** (Zaten mevcuttu, şimdi aktif kullanılıyor):

```sql
CREATE TABLE error_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL,
    table_name TEXT,
    partition_id INTEGER,
    error_type TEXT NOT NULL,
    error_message TEXT NOT NULL,
    stack_trace TEXT,
    occurred_at TEXT NOT NULL,
    retry_attempt INTEGER DEFAULT 0,
    resolved INTEGER DEFAULT 0,
    FOREIGN KEY (run_id) REFERENCES migration_runs(run_id)
);
```

## 📂 Yeni Dosyalar

### Backend (MigrationEngine)
1. **`ExtendedCheckpointRepository.cs`** (Güncellendi)
   - `LogError()` - Hata kaydet
   - `MarkErrorResolved()` - Çözüldü işaretle
   - `GetErrorsByRunId()` - Run bazında hatalar
   - `GetErrorsByTable()` - Tablo bazında hatalar
   - `GetErrorStatsByType()` - Tip bazında istatistik
   - `FailMigrationHistory()` - Migration'ı başarısız işaretle

2. **`Program.cs`** (Güncellendi)
   - Otomatik hata kaydı eklendi
   - Migration history tracking eklendi
   - Fatal error handling iyileştirildi

### Frontend (Web UI)
1. **`Pages/Errors.cshtml`**
   - Hata analiz sayfası
   - Dashboard widget'ları
   - Filtreler
   - Grafikler
   - Hata listesi
   - Detay modal

2. **`Pages/Errors.cshtml.cs`**
   - PageModel

3. **`wwwroot/js/errors.js`**
   - Client-side JavaScript
   - API çağrıları
   - Chart.js entegrasyonu
   - Filtreleme logic'i
   - CSV export

4. **`Controllers/ErrorsController.cs`**
   - 8 yeni API endpoint
   - ExtendedCheckpointRepository entegrasyonu

5. **`Pages/_Layout.cshtml`** (Güncellendi)
   - Navbar'a "Errors" linki eklendi

## 🚀 Kullanım

### 1. Migration Engine

Hata kaydı tamamen otomatik! Engine çalıştırın, hatalar otomatik kaydedilir.

```bash
cd MigrationEngine
dotnet run
```

### 2. Hataları Görüntüleme

Web UI'da:

```
http://localhost:5000/errors
```

### 3. Hata Analizi

**Örnekler:**

```javascript
// Tüm hataları getir
fetch('/api/errors')

// Belirli run'daki hatalar
fetch('/api/errors/run/123')

// Tablo bazında hatalar
fetch('/api/errors/run/123/table/EMPLOYEES')

// Hata istatistikleri
fetch('/api/errors/run/123/stats')

// Özet
fetch('/api/errors/summary')

// Çözüldü işaretle
fetch('/api/errors/456/resolve', { method: 'POST' })
```

## 📊 Örnek Kullanım Senaryoları

### Senaryo 1: Migration Sonrası Hata Kontrolü

1. Migration tamamlandı
2. `/errors` sayfasını aç
3. Filtreyi son run ID'ye ayarla
4. Çözülmemiş hataları görüntüle
5. Hatalar üzerine tıklayarak detay gör (stack trace dahil)

### Senaryo 2: Belirli Tablo Hatalarını İnceleme

1. Table filter'da tablo seç (örn: `ORDERS`)
2. Tüm run'lardaki bu tabloya ait hatalar gösterilir
3. Pattern'leri tespit et
4. Çözüm üret

### Senaryo 3: Hata Tipi Analizi

1. Pie chart'ta en çok görülen hata tipini gör
2. Error Type filter'da o tipi seç
3. Tüm bu tipteki hataları listele
4. Ortak neden araştır

### Senaryo 4: Toplu Çözüm İşaretleme

1. Filtrele (örn: ConnectionTimeout hataları)
2. Select All checkbox'ı işaretle
3. "Seçilenleri Çözüldü İşaretle" butonuna tıkla
4. Tüm seçililer çözüldü olarak işaretlenir

### Senaryo 5: CSV Export

1. Filtrele (istediğin kriterlere göre)
2. "Export CSV" butonuna tıkla
3. CSV dosyası indir
4. Excel/BI tool'larında analiz et

## 📈 İstatistikler ve Metrikler

### Dashboard Widget'ları

```
┌─────────────────┬─────────────────┬─────────────────┬─────────────────┐
│ Toplam Hata     │ Çözülmemiş      │ Çözülmüş        │ Etkilenen Tablo │
│      245        │       89        │      156        │       12        │
└─────────────────┴─────────────────┴─────────────────┴─────────────────┘
```

### Hata Tipi Dağılımı (Örnek)

- SqlException: 85 (35%)
- TimeoutException: 62 (25%)
- OracleException: 48 (20%)
- NullReferenceException: 30 (12%)
- Other: 20 (8%)

### Tabloya Göre Hatalar (Top 5)

1. ORDERS: 45 hata
2. CUSTOMERS: 38 hata
3. PRODUCTS: 32 hata
4. INVOICES: 28 hata
5. SHIPMENTS: 22 hata

## 🔧 Yapılandırma

Özel yapılandırma gerekmez! Mevcut SQLite checkpoint database kullanılır.

```json
// appsettings.json (zaten var)
{
  "Checkpoint": {
    "SqlitePath": "migration_checkpoint.db"
  }
}
```

## 🎨 UI Özellikleri

- ✅ Bootstrap 5 Dark Theme
- ✅ Font Awesome Icons
- ✅ Chart.js grafikleri
- ✅ Responsive tasarım
- ✅ Modal detay gösterimi
- ✅ Renk kodlu status badges
- ✅ CSV export özelliği

## 🧪 Test

```powershell
# 1. Build
dotnet build OracleMssqlMigration.sln -c Release

# 2. Web UI başlat
cd Migratorv0
dotnet run

# 3. Browser'da aç
http://localhost:5000/errors
```

## 📝 Örnek Hata Detayı

```
Hata Tipi: OracleException
Oluşma Zamanı: 2026-04-20 23:15:42
Run ID: 15
Tablo: EMPLOYEES
Partition ID: 3

Hata Mesajı:
ORA-00942: table or view does not exist

Stack Trace:
   at Oracle.ManagedDataAccess.Client.OracleException.HandleErrorHelper(...)
   at Oracle.ManagedDataAccess.Client.OracleCommand.ExecuteReader(...)
   at MigrationEngine.Extractors.OracleParallelExtractor.ExtractPartitionAsync(...)
   at MigrationEngine.Program.<>c__DisplayClass0_0.<<Main>b__3>d.MoveNext()
```

## ✅ Faydalar

1. **Sorun Tespiti**: Hangi tablolarda sorun var?
2. **Pattern Tanıma**: Aynı tip hatalar tekrar ediyor mu?
3. **Performans**: Hangi hatalar en sık görülüyor?
4. **İzlenebilirlik**: Tüm hatalar kayıt altında
5. **Raporlama**: CSV export ile üst yönetime rapor
6. **Çözüm Takibi**: Hangi hatalar çözüldü, hangisi bekliyor?

## 🎉 ÖZET

Artık **TÜM** migration hataları:
- ✅ Otomatik kaydediliyor
- ✅ Analiz edilebiliyor
- ✅ Filtrelenebiliyor
- ✅ Grafiklerle görselleştiriliyor
- ✅ Export edilebiliyor
- ✅ Çözüm takibi yapılabiliyor

**Hata analizi artık çok kolay!** 🚀
