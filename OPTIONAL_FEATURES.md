# 🎛️ Opsiyonel Migration Özellikleri

## ✅ YENİ: Schema Migration Seçenekleri

Artık index, trigger, foreign key ve diğer constraint'leri **opsiyonel** olarak migrate edebilirsiniz!

## 📋 Kullanılabilir Seçenekler

| Özellik | Default | Açıklama | Öneri |
|---------|---------|----------|-------|
| **MigratePrimaryKeys** | ✅ `true` | Primary key constraint'leri | ✅ Açık bırakın |
| **MigrateIndexes** | ❌ `false` | Index'ler | ⚠️ Yavaşlatır, sonradan ekleyin |
| **MigrateForeignKeys** | ❌ `false` | Foreign key constraint'leri | ⚠️ Referans tabloları gerekli |
| **MigrateUniqueConstraints** | ❌ `false` | Unique constraint'ler | ⏸️ İsteğe bağlı |
| **MigrateCheckConstraints** | ❌ `false` | Check constraint'ler | ⏸️ İsteğe bağlı |
| **MigrateTriggers** | ❌ `false` | Trigger'lar | ❌ Henüz implement edilmedi |

## 🎯 Kullanım Senaryoları

### Senaryo 1: Hızlı Data Migration (Önerilen)

**Hedef:** En hızlı migration, sonra manuel index oluşturma

**Ayarlar:**
```json
{
  "MigratePrimaryKeys": true,
  "MigrateIndexes": false,
  "MigrateForeignKeys": false,
  "MigrateUniqueConstraints": false,
  "MigrateCheckConstraints": false,
  "MigrateTriggers": false
}
```

**Avantajlar:**
- ✅ En hızlı migration
- ✅ Index overhead yok
- ✅ FK failure riski yok
- ✅ Sonradan optimize ederek index oluşturabilirsiniz

**Ne Zaman:** Büyük data setleri, ilk migration, test ortamları

### Senaryo 2: Tam Schema Migration

**Hedef:** Tüm schema ile birlikte migrate et

**Ayarlar:**
```json
{
  "MigratePrimaryKeys": true,
  "MigrateIndexes": true,
  "MigrateForeignKeys": true,
  "MigrateUniqueConstraints": true,
  "MigrateCheckConstraints": true,
  "MigrateTriggers": false
}
```

**Avantajlar:**
- ✅ Tam schema kopyası
- ✅ Tüm constraint'ler yerinde
- ✅ Referential integrity korunur

**Dezavantajlar:**
- ⚠️ Daha yavaş
- ⚠️ FK'ler fail olabilir (eksik referans tabloları)

**Ne Zaman:** Küçük data setleri, tüm tabloları birlikte migrate ediyorsanız

### Senaryo 3: Sadece Data + PK

**Hedef:** Data + Primary Key, diğer her şey sonra

**Ayarlar:**
```json
{
  "MigratePrimaryKeys": true,
  "MigrateIndexes": false,
  "MigrateForeignKeys": false,
  "MigrateUniqueConstraints": false,
  "MigrateCheckConstraints": false,
  "MigrateTriggers": false
}
```

**Avantajlar:**
- ✅ Hızlı
- ✅ PK ile data bütünlüğü var
- ✅ Sonra ihtiyaca göre index eklersiniz

**Ne Zaman:** En yaygın senaryo, production migration'lar

### Senaryo 4: Data Only (Test Amaçlı)

**Hedef:** Sadece data, hiç constraint yok

**Ayarlar:**
```json
{
  "MigratePrimaryKeys": false,
  "MigrateIndexes": false,
  "MigrateForeignKeys": false,
  "MigrateUniqueConstraints": false,
  "MigrateCheckConstraints": false,
  "MigrateTriggers": false
}
```

**Avantajlar:**
- ✅ Maksimum hız
- ✅ Hiç constraint overhead yok

**Dezavantajlar:**
- ⚠️ Duplicate data riski
- ⚠️ Data integrity korunmaz

**Ne Zaman:** Sadece test data yüklemesi, geliştirme ortamları

## 🎨 Wizard'dan Kullanım

### Web UI (Wizard) - Step 4

Wizard'ın 4. adımında "Schema Migration Options" bölümünü göreceksiniz:

```
┌─────────────────────────────────────────────────┐
│  Schema Migration Options                       │
├─────────────────────────────────────────────────┤
│  ☑ Primary Keys (Recommended)                   │
│  ☐ Indexes (Default: Disabled)                  │
│  ☐ Foreign Keys (Default: Disabled)             │
│  ☐ Unique Constraints (Default: Disabled)       │
│  ☐ Check Constraints (Default: Disabled)        │
│  ☐ Triggers (Not implemented)                   │
└─────────────────────────────────────────────────┘

💡 Tip: For fastest migration, keep only Primary Keys
   enabled. Create indexes manually after data load.
```

**Kullanım:**
1. Wizard'ı başlat: `http://localhost:5000/wizard`
2. Step 4'e kadar ilerle
3. İstediğiniz seçenekleri işaretle/kaldır
4. "Save & Continue" tıkla

Ayarlar otomatik `appsettings.json`'a yazılır!

## 📝 appsettings.json ile Kullanım

### Manuel Konfigürasyon

`MigrationEngine/appsettings.json`:

```json
{
  "Migration": {
    "OracleConnectionString": "...",
    "MssqlConnectionString": "...",
    "OracleSchema": "MYSCHEMA",
    
    "MigrateIndexes": false,
    "MigrateTriggers": false,
    "MigrateForeignKeys": false,
    "MigratePrimaryKeys": true,
    "MigrateUniqueConstraints": false,
    "MigrateCheckConstraints": false
  }
}
```

## ⚡ Performans Etkileri

### Migration Süresi (Örnek: 1M satır, 10 tablo)

| Ayar | Süre | Açıklama |
|------|------|----------|
| Sadece Data + PK | **5 dakika** | ✅ En hızlı |
| + Indexes | **15 dakika** | Index creation overhead |
| + FK + Constraints | **20 dakika** | Validation overhead |
| Tüm options aktif | **25 dakika** | Full schema migration |

### Index Oluşturma Zamanı

- **Migration sırasında**: Index'ler data load edilirken oluşturulur → YAVAŞ
- **Migration sonrasında**: Tüm data yüklü, parallel index creation → HIZLI

**Öneri:** Index'leri sonra oluşturun!

```sql
-- Migration sonrası, parallel index creation
CREATE INDEX idx_customer_name ON CUSTOMERS(NAME) WITH (ONLINE = ON, MAXDOP = 8);
CREATE INDEX idx_order_date ON ORDERS(ORDER_DATE) WITH (ONLINE = ON, MAXDOP = 8);
-- ... paralel olarak
```

## 🔍 Foreign Key Hataları

### Problem

Foreign key migration sırasında hatalar görebilirsiniz:

```
Foreign key 'FK_NAME' references invalid table 'REFERENCED_TABLE'.
```

### Sebep

Referans edilen tablo migration listesinde yok!

### Çözüm 1: FK'leri Devre Dışı Bırak (Önerilen)

```json
{
  "MigrateForeignKeys": false
}
```

Sonra manuel oluştur:

```sql
ALTER TABLE CHILD_TABLE
ADD CONSTRAINT FK_NAME
FOREIGN KEY (COLUMN_ID)
REFERENCES PARENT_TABLE (ID);
```

### Çözüm 2: Tüm Tabloları Migrate Et

Wizard'da **tüm referans tablolarını** da seç!

## 📊 Constraint'lerin Etkileri

### Primary Keys

**Etki:** ✅ Düşük (genelde gerekli)
- Duplicate satır engeller
- Unique identifier
- Index otomatik oluşur (clustered)

**Öneri:** ✅ Her zaman aktif

### Indexes

**Etki:** ⚠️ Yüksek
- Data insert sırasında index güncellenmeli
- Memory ve disk I/O artar

**Öneri:** ❌ Migration sırasında devre dışı, sonra oluştur

### Foreign Keys

**Etki:** ⚠️ Orta-Yüksek
- Her insert'te referans kontrolü
- Eksik referans tabloları fail olur

**Öneri:** ❌ Migration sırasında devre dışı, sonra oluştur

### Unique Constraints

**Etki:** ⚠️ Orta
- Duplicate kontrolü
- Index otomatik oluşur

**Öneri:** ⏸️ İhtiyaca göre

### Check Constraints

**Etki:** ⚠️ Düşük-Orta
- Her insert'te validation
- Genelde hızlı

**Öneri:** ⏸️ İhtiyaca göre

## 🎯 Best Practices

### 1. **İlk Migration: Hızlı ve Basit**

```
✅ MigratePrimaryKeys: true
❌ Diğer her şey: false
```

**Sonra:**
1. Index'leri analiz et ve gerekenleri oluştur
2. FK'leri kontrol et ve oluştur
3. Performance test yap

### 2. **Constraint'leri Sonra Ekle**

```sql
-- Migration tamamlandıktan sonra
-- 1. Index'ler (paralel)
CREATE INDEX idx1 ON TABLE1(COL1) WITH (ONLINE = ON, MAXDOP = 8);
CREATE INDEX idx2 ON TABLE2(COL2) WITH (ONLINE = ON, MAXDOP = 8);

-- 2. Foreign Keys
ALTER TABLE CHILD ADD CONSTRAINT FK_NAME FOREIGN KEY ...;

-- 3. Diğer constraints
ALTER TABLE TABLE1 ADD CONSTRAINT UQ_NAME UNIQUE (COL);
```

### 3. **Test Migration Sonuçlarını Karşılaştır**

Error Analysis sayfasından:

```
http://localhost:5000/errors
```

- FK hatalarını gör
- Eksik tabloları tespit et
- Bir sonraki migration'da düzelt

### 4. **Performance Monitoring**

History sayfasından karşılaştır:

```
http://localhost:5000/history
```

- İndex'siz migration: 5 dakika
- Index'li migration: 15 dakika
- **Fark:** 10 dakika → Index'leri sonra eklemek daha hızlı!

## 📈 Örnek Senaryo: Production Migration

### Planlama

**Tablo Sayısı:** 150 tablo  
**Data Boyutu:** 50 GB  
**Downtime Penceresi:** 2 saat

### Strateji

**Phase 1: Hızlı Data Load (30 dakika)**
```json
{
  "MigratePrimaryKeys": true,
  "MigrateIndexes": false,
  "MigrateForeignKeys": false
}
```

**Phase 2: Kritik Index'ler (20 dakika)**
```sql
-- Sadece WHERE clause'da kullanılan index'ler
CREATE INDEX idx_critical1 ... WITH (ONLINE = ON);
CREATE INDEX idx_critical2 ... WITH (ONLINE = ON);
```

**Phase 3: FK ve Diğerleri (30 dakika)**
```sql
-- Foreign keys
-- Check constraints
-- Diğer index'ler
```

**Phase 4: Validation (30 dakika)**
```sql
-- Row count check
-- Data integrity check
-- Performance test
```

**Toplam:** 1 saat 50 dakika < 2 saat downtime ✅

## 🎊 Özet

| Ne İstiyorsunuz? | Ayarlar |
|------------------|---------|
| En hızlı migration | PK: ✅, Diğerleri: ❌ |
| Balanced | PK + Unique: ✅, Index + FK: ❌ |
| Tam schema | Hepsi: ✅ (FK riskli) |
| Test data | Hepsi: ❌ |

**Altın Kural:** 
> Migration sırasında minimum constraint, sonra optimize ederek ekle!

## 🔗 İlgili Dosyalar

- `FOREIGN_KEY_ERRORS_EXPLAINED.md` - FK hataları detayı
- `ERROR_ANALYSIS_FEATURE.md` - Hata analiz sistemi
- `README.md` - Ana dokümantasyon

---

**Artık migration'ınızı tam kontrol altına aldınız!** 🚀
