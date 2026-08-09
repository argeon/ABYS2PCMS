# 🔑 Foreign Key Hataları - Açıklama ve Çözüm

## ❓ Neden Bu Hatalar Oluşuyor?

Gördüğünüz foreign key hataları **NORMAL** ve **BEKLENİLEN** bir durumdur! Şu sebeplerden kaynaklanır:

### Sebep 1: Eksik Referans Tabloları

```
Foreign key 'REG_RSP_RETIRE_STATUS_FK' references invalid table 'CS_RETIRE_STATUS_PRM'.
```

**Açıklama:**
- `CS_REGISTER` tablosu `CS_RETIRE_STATUS_PRM` tablosuna foreign key ile bağlı
- Ama `CS_RETIRE_STATUS_PRM` tablosu **migration listesinde YOK**
- Bu yüzden foreign key oluşturulamıyor

**Neden listede yok?**
1. Wizard'da o tablo seçilmedi
2. Lookup/parametre tablosu olduğu için unutuldu
3. Başka bir schema'da veya veritabanında

### Sebep 2: Tablo Sıralaması

Oracle'da tablolar alfabetik veya rastgele sırada okunuyor, ancak foreign key'lerin oluşturulması için:
- Önce **parent table** (referans edilen) oluşturulmalı
- Sonra **child table** (referans eden) oluşturulmalı

Sistem bu sıralamayı otomatik yapmıyor çünkü circular dependency olabilir.

## ✅ Sistem Nasıl Davranıyor?

### 1. **Hata Yakalama**

```csharp
try {
    await loader.ExecuteDdlAsync(fkDdl, ct);
    fkSuccessCount++;
} catch (Exception ex) {
    fkFailCount++;
    Log.Warning("FK creation failed, skipping...");
    // Hata kaydediliyor ancak migration devam ediyor
}
```

### 2. **Hata Loglama**

Artık bu hatalar **Error Analysis** sistemine kaydediliyor:
- Hata tipi: `FOREIGN_KEY_CREATION_FAILED`
- Hata mesajı: Hangi tablo eksik
- DDL: Tam foreign key komutu
- `/errors` sayfasından görüntülenebilir

### 3. **Migration Devam Ediyor**

- Foreign key hataları migration'ı **DURDURMAZ**
- Data migration devam eder
- Sadece constraint'ler eksik kalır

## 🔧 ÇÖZÜMLER

### Çözüm 1: Eksik Tabloları Ekle (Önerilen)

**Adım 1:** Hangi tablolar eksik? Error Analysis'ten öğren:

```
http://localhost:5000/errors
```

Filtrele: `Error Type = FOREIGN_KEY_CREATION_FAILED`

**Adım 2:** Eksik tabloları tespit et:

Örnek hataların gösterdiği eksik tablolar:
- `CS_RETIRE_STATUS_PRM`
- `CS_NATIONAL_PRM`
- `II_FIRM_CLASS_PRM`
- `CS_EDUCATION_STATUS_PRM`
- `CS_DRV_LICENSE_CLASS_PRM`
- `DMS_DOC`
- `CS_SECRET_REGISTER`
- `CS_JOB_PRM`

**Adım 3:** Yeni migration başlat ve bu tabloları ekle:

```bash
# Wizard'da bu tabloları da seç
http://localhost:5000/wizard
```

### Çözüm 2: Foreign Key'leri Manuel Oluştur

Migration tamamlandıktan sonra:

**Adım 1:** Eksik tabloları migrate et (ayrı bir migration ile)

**Adım 2:** Foreign key DDL'lerini çalıştır:

```sql
-- Error log'dan DDL'i kopyala
ALTER TABLE [CS_REGISTER]
ADD CONSTRAINT [REG_RSP_RETIRE_STATUS_FK]
FOREIGN KEY ([RETIRE_STATUS_ID])
REFERENCES [CS_RETIRE_STATUS_PRM] ([ID]);
```

**Adım 3:** SQL Server Management Studio'da çalıştır

### Çözüm 3: Tüm Tabloları Birlikte Migrate Et (En İyisi!)

**Wizard'da tablo seçerken:**

1. **"Select All"** kullan veya
2. Tüm ilgili tabloları birlikte seç:
   - Ana tablolar (CS_REGISTER)
   - Lookup tablolar (*_PRM)
   - İlişkili tablolar (DMS_DOC, etc.)

Bu şekilde tüm foreign key'ler otomatik oluşur!

## 📊 İstatistikler

Migration sonunda şöyle bir özet göreceksiniz:

```
Foreign keys: 145 created, 28 failed (missing referenced tables)
```

**Anlamı:**
- ✅ 145 FK başarıyla oluşturuldu
- ⚠️ 28 FK oluşturulamadı (referans tabloları yok)

## 🎯 En İyi Pratikler

### 1. **Tablo Seçimi**

```
✅ DOĞRU:
- Ana tabloları seç
- Lookup/parametre tablolarını da seç (_PRM, _LKP, vs)
- İlişkili document/media tablolarını seç

❌ YANLIŞ:
- Sadece ana tabloları seç
- Lookup tabloları unutma
```

### 2. **Migration Stratejisi**

**Seçenek A: Tek Seferde**
```
1. Tüm tabloları migrate et (lookup'lar dahil)
2. Tüm FK'ler otomatik oluşur
3. Tek migration, tek seferde biter
```

**Seçenek B: Aşamalı**
```
1. İlk migration: Lookup/parametre tabloları
2. İkinci migration: Ana tablolar
3. FK'ler ikinci migration'da oluşur
```

### 3. **Hata Kontrolü**

Her migration'dan sonra:

```bash
# Error Analysis'i kontrol et
http://localhost:5000/errors

# FK hatalarını filtrele
Error Type: FOREIGN_KEY_CREATION_FAILED

# Eksik tabloları tespit et
# Bir sonraki migration'da ekle
```

## 🔍 Detaylı Örnek

### Senaryo: CS_REGISTER Tablosu

**Oracle'da:**
```sql
-- CS_REGISTER 9 FK'ye sahip:
1. REG_RSP_RETIRE_STATUS_FK → CS_RETIRE_STATUS_PRM
2. REG_NP_NATIONAL_FK → CS_NATIONAL_PRM
3. REG_FCP_FIRM_CLASS_ID_FK → II_FIRM_CLASS_PRM
4. REG_ESP_EDUCATION_STATUS_FK → CS_EDUCATION_STATUS_PRM
5. REG_DLCP_DRV_LICENSE_CLS_ID_FK → CS_DRV_LICENSE_CLASS_PRM
6. CS_REGISTER_PICTURE_DOC_ID → DMS_DOC
7. REG_SECRET_REGISTER_FK → CS_SECRET_REGISTER
8. REG_JOB_JOB_ID_FK → CS_JOB_PRM
9. ... (daha fazla)
```

**Migration sırasında:**

| Tablo | Durumu | FK Oluşturuldu? |
|-------|--------|----------------|
| CS_REGISTER | ✅ Migrate edildi | ⚠️ 8 FK başarısız |
| CS_RETIRE_STATUS_PRM | ❌ Seçilmedi | - |
| CS_NATIONAL_PRM | ❌ Seçilmedi | - |
| II_FIRM_CLASS_PRM | ❌ Seçilmedi | - |
| ... | ❌ Seçilmedi | - |

**Sonuç:**
- Data migrate edildi ✅
- Tablo oluşturuldu ✅
- Primary key oluşturuldu ✅
- Index'ler oluşturuldu ✅
- Foreign key'ler oluşturulamadı ⚠️

**Çözüm:**
```
1. Eksik 8 tabloyu da migrate et
2. Veya SQL Server'da manuel FK oluştur
3. Veya FK olmadan devam et (referential integrity risk var!)
```

## 📝 Özet

### ✅ Sistem Doğru Çalışıyor

- Hatalar yakalanıyor
- Log'lanıyor
- Error Analysis'e kaydediliyor
- Migration durmuyor

### ⚠️ Dikkat Edilmesi Gerekenler

1. **Tablo Seçimi**: Lookup tabloları unutma
2. **Referential Integrity**: FK'siz tablolar risk oluşturabilir
3. **Data Tutarlılığı**: FK'ler önemli!

### 🎯 Önerilen Aksiyon

```
1. /errors sayfasını aç
2. FK hatalarını listele
3. Eksik tabloları tespit et
4. Yeni migration ile eksik tabloları ekle
5. FK'ler otomatik oluşacak!
```

## 🚀 Sonuç

Bu hatalar **sistem hatası değil**, **eksik tablo seçimi** sonucudur. Sistem bu durumu:

1. ✅ Tespit ediyor
2. ✅ Log'luyor
3. ✅ /errors sayfasına kaydediyor
4. ✅ Migration'ı durdurmadan devam ettiriyor
5. ✅ Sonuç raporunda bildiriyor

**Aksiyonunuz:** Eksik tabloları bir sonraki migration'da ekleyin! 💪
