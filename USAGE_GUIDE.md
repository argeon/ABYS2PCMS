# Oracle → MSSQL Migration Tool - Kullanım Kılavuzu

## 🚀 Hızlı Başlangıç

### Adım 1: Web UI'yi Başlatın

```bash
cd C:\Users\HW5536\source\repos\Migratorv0\Migratorv0
dotnet run
```

Tarayıcınızda açılacak: `http://localhost:5000`

### Adım 2: Wizard'ı Kullanın

Tarayıcıda `http://localhost:5000/wizard` adresine gidin veya üst menüden **"New Migration"** linkine tıklayın.

#### 🔹 Step 1: Oracle Connection
1. Oracle bilgilerinizi girin:
   - **Host**: `localhost` (veya Oracle server adresi)
   - **Port**: `1521`
   - **Service Name**: `ORCL` (veya SID)
   - **Username**: `SYSTEM` (veya schema owner)
   - **Password**: Şifreniz
   - **Schema Name**: `YOUR_SCHEMA` (büyük harf)

2. **"Test Connection"** butonuna tıklayın
3. ✅ Başarılı olursa: "Connected successfully! Found X tables" mesajı
4. ❌ Hata alırsanız: Connection string'i kontrol edin
5. **"Next"** butonuna tıklayın

#### 🔹 Step 2: MSSQL Connection
1. SQL Server bilgilerinizi girin:
   - **Server**: `localhost` (veya SQL Server adresi)
   - **Authentication**: `SQL Server Authentication` veya `Windows Authentication`
   - **Username**: `sa` (SQL Auth seçildiyse)
   - **Password**: Şifreniz (SQL Auth seçildiyse)
   - **Database**: `TargetDB` (hedef database)
   - **Trust Certificate**: ✅ (geliştirme ortamı için)

2. **"Test Connection"** butonuna tıklayın
3. ✅ Başarılı olursa: "Connected successfully! Database: TargetDB" mesajı
4. **"Next"** butonuna tıklayın

#### 🔹 Step 3: Select Tables
1. Oracle'dan tablolar otomatik yüklenecek (loading spinner görünür)
2. Her tablo için tahmin edilen satır sayısı gösterilir
3. **Arama**: Tablo ismi ile filtreleyin
4. **Seçim**: 
   - Tek tek checkbox ile seçin
   - **"Select All"** ile hepsini seçin
   - **"Deselect All"** ile seçimi temizleyin
5. Alt kısımda: **"Selected: X tables"** sayacı
6. En az 1 tablo seçin
7. **"Next"** butonuna tıklayın

#### 🔹 Step 4: Configure & Start
1. **Migration Summary** görüntülenir:
   - Source: Oracle host/schema
   - Target: MSSQL server/database
   - Seçili tablolar listesi

2. **Performance ayarları**:
   - **Degree of Parallelism**: `8` (önerilen, 1-32 arası)
   - **Batch Size**: `50000` (önerilen, 1K-100K arası)
   - **Fetch Size MB**: `50` (önerilen, 10-200 arası)

3. **"Save & Continue"** butonuna tıklayın

### Adım 3: Migration Engine'i Başlatın

Configuration kaydedildikten sonra **Start** sayfası açılacak. Bu sayfada:

#### Yöntem 1: Manuel (Önerilen)
1. **Yeni bir terminal açın** (PowerShell veya CMD)
2. Klasöre gidin:
   ```bash
   cd C:\Users\HW5536\source\repos\Migratorv0\MigrationEngine
   ```
3. Engine'i başlatın:
   ```bash
   dotnet run
   ```
4. Terminal penceresini açık bırakın
5. Tarayıcıya dönün ve **"Go to Dashboard"** butonuna tıklayın

#### Yöntem 2: PowerShell ile Otomatik
Start sayfasındaki alternatif komutu kopyalayın ve PowerShell'de çalıştırın:
```powershell
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd 'C:\Users\HW5536\source\repos\Migratorv0\MigrationEngine'; dotnet run"
```

### Adım 4: Dashboard'da İzleyin

Dashboard otomatik olarak açılacak ve şunları göreceksiniz:

#### 📊 Overall Progress
- **Total Tables**: Toplam tablo sayısı
- **Completed**: Tamamlanan tablolar (yeşil)
- **Running**: Şu anda işlenen tablolar (mavi)
- **Pending**: Bekleyenler (gri)
- **Failed**: Hata alanlar (kırmızı)
- **Progress Bar**: Genel ilerleme %
- **Elapsed Time**: Geçen süre
- **Throughput**: Saniyede işlenen satır sayısı

#### 📋 Table Status Grid
Her tablo için:
- **Table Name**: Tablo adı
- **Status**: Durum badge'i (renk kodlu)
- **Progress**: İlerleme çubuğu
- **Rows**: Yüklenen/Toplam satır
- **Speed**: rows/sec

Status renkleri:
- 🟢 **Green (Done)**: Tamamlandı
- 🔵 **Blue Pulse (Running)**: Şu anda işleniyor (animasyon)
- 🟡 **Yellow (Pending)**: Bekliyor
- 🔴 **Red (Failed)**: Hata

#### 📝 Log Stream
- Son 100 log eventi
- **Filtreler**: All / Info / Warning / Error
- **Auto-scroll**: Toggle ile açıp kapatın
- Yeni loglar en üste eklenir
- Timestamp ile birlikte gösterilir

#### 🎛️ Controls
- **Export Report**: JSON formatında rapor indir

## 🔄 Migration Süreci

### Phase 1: Schema Discovery
- Oracle metadata okunur (tables, columns, constraints, indexes)
- Tablo filtreleri uygulanır
- Schema model oluşturulur

### Phase 2: DDL Generation
- Type mapping (Oracle → MSSQL)
- CREATE TABLE statements
- ALTER TABLE (PK, UNIQUE)
- CREATE INDEX statements
- ALTER TABLE (FK) statements
- Circular FK detection

### Phase 3: DDL Execution
- MSSQL database BULK_LOGGED mode'a alınır
- CREATE TABLE tüm tablolar için
- Primary Key ve Unique constraint'ler eklenir
- Checkpoint kaydedilir

### Phase 4: Parallel Data Migration ⚡
- Her tablo için:
  - Satır sayısı tahmin edilir
  - Partition'lar hesaplanır (ROWID veya PK bazlı)
  - Parallel.ForEachAsync ile işlenir
  - OracleParallelExtractor: FetchSize=50MB ile stream
  - SqlBulkCopyLoader: EnableStreaming=true ile yükle
  - Her 50K satırda progress update
  - Partition tamamlandığında checkpoint

### Phase 5: Post-Load DDL
- Tüm index'ler oluşturulur:
  - WITH (SORT_IN_TEMPDB = ON)
  - MAXDOP = 8
  - DATA_COMPRESSION = PAGE
- Foreign Key constraint'ler eklenir:
  - WITH CHECK
  - Circular FK'ler skip edilir

### Phase 6: Validation
- Her tablo için:
  - Oracle: `SELECT COUNT(*)`
  - MSSQL: `SELECT COUNT(*)`
  - Karşılaştır
  - Numeric PK varsa: `SUM(pk)` checksum
  - Sonuç: PASS / FAIL

### Cleanup
- MSSQL database FULL recovery mode'a döner
- Completion statistics loglanır
- Run status: COMPLETED

## 🛠️ Troubleshooting

### ❌ Oracle connection test başarısız
**Sorun**: "ORA-12154: TNS:could not resolve the connect identifier"
**Çözüm**: 
- Host ve Port'u kontrol edin
- Service Name yerine SID kullanmayı deneyin
- TNS Names yapılandırmasını kontrol edin

**Sorun**: "ORA-01017: invalid username/password"
**Çözüm**:
- Kullanıcı adı ve şifre doğru mu?
- Schema name büyük harfle yazıldı mı?

### ❌ MSSQL connection test başarısız
**Sorun**: "A connection was successfully established with the server, but then an error occurred"
**Çözüm**:
- "Trust Server Certificate" işaretleyin
- SQL Server TCP/IP enabled mi?
- Port 1433 açık mı?

**Sorun**: "Cannot open database requested by the login"
**Çözüm**:
- Database adı doğru mu?
- Database mevcut mu? (CREATE DATABASE TargetDB)
- Kullanıcı database'e erişim yetkisi var mı?

### ❌ Migration Engine başlamıyor
**Sorun**: Terminal'de hata görmüyorum
**Çözüm**:
1. MigrationEngine klasöründe `appsettings.json` var mı kontrol edin
2. Manuel olarak test edin:
   ```bash
   cd MigrationEngine
   dotnet build
   dotnet run
   ```
3. Console'da hata mesajlarını okuyun

### ❌ Dashboard'da data güncellenmiyor
**Sorun**: Tablolar "Pending" durumunda kalıyor
**Çözüm**:
- Migration Engine çalışıyor mu? Terminal penceresini kontrol edin
- `migration_checkpoint.db` dosyası var mı?
- SignalR bağlantısı koptu mu? Sayfayı yenileyin (F5)

### ❌ Partition failed
**Sorun**: Bazı partition'lar "FAILED" durumunda
**Çözüm**:
- Log stream'de hata mesajını bulun
- Engine'i yeniden başlatın (otomatik retry yapacak)
- Checkpoint sistemi başarılı partition'ları skip eder

### ❌ Validation FAIL
**Sorun**: Row count eşleşmiyor
**Çözüm**:
- Oracle ve MSSQL'de manuel COUNT(*) çalıştırın
- Transaction commit edildi mi?
- Data truncate edilmiş olabilir mi?

## 📊 Performance Tuning

### Yavaş Migration
**Optimizasyonlar**:
1. **Degree of Parallelism artırın**: 8 → 16 (CPU'ya göre)
2. **Batch Size artırın**: 50K → 100K
3. **Fetch Size artırın**: 50MB → 100MB
4. **MSSQL Recovery Model**: BULK_LOGGED (otomatik yapılır)
5. **Network**: Oracle ve MSSQL aynı network'te mi?

### Çok Fazla Memory Kullanımı
**Optimizasyonlar**:
1. **Degree of Parallelism azaltın**: 16 → 4
2. **Batch Size azaltın**: 100K → 25K
3. **Fetch Size azaltın**: 100MB → 25MB

## 🔒 Security Best Practices

1. **Connection Strings**: 
   - Production'da environment variables kullanın
   - appsettings.json'ı .gitignore'a ekleyin

2. **Passwords**:
   - Kesinlikle commit etmeyin
   - Azure Key Vault veya HashiCorp Vault kullanın

3. **Database Permissions**:
   - Oracle: Sadece READ permission yeterli
   - MSSQL: CREATE TABLE, INSERT, CREATE INDEX gerekli

## 📦 Migration Sonrası

### ✅ Checklist
- [ ] Validation tüm tablolar için PASS
- [ ] Dashboard'da tüm tablolar "Done" (yeşil)
- [ ] Log stream'de ERROR yok
- [ ] Row count'lar eşleşiyor
- [ ] **MSSQL FULL BACKUP alın**
- [ ] Recovery mode FULL'a döndü mü kontrol edin
- [ ] Test queries çalıştırın
- [ ] Application bağlantısını test edin

### 🗄️ Backup Command
```sql
BACKUP DATABASE [TargetDB] 
TO DISK = 'C:\Backups\TargetDB_FULL.bak'
WITH FORMAT, INIT, COMPRESSION, STATS = 10;
```

## 📞 Support

Sorularınız için:
- Architecture sayfasını inceleyin: `http://localhost:5000/architecture`
- README.md'yi okuyun
- PROJECT_SUMMARY.md'yi kontrol edin
- WIZARD_FLOW.md'de detaylı flow

## 🎉 Başarılı Migration!

Migration tamamlandığında:
- ✅ Dashboard: Tüm tablolar yeşil
- ✅ Overall progress: %100
- ✅ Validation: All PASS
- ✅ No errors in log stream
- ✅ Export Report ile JSON rapor indirin
- ✅ FULL BACKUP alın
- ✅ Production'a deploy!

Tebrikler! 🚀
