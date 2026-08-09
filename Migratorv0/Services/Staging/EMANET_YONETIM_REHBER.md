# Emanet Hesap Yönetim Rehberi

## Özet
Emanet hesaplar (ACCRUE_TYPE_ID=14) **normal faturalardan farklı** yönetilmelidir.
- **HARICI_ACIK** olarak sınıflandırılır (INFO seviyesi)
- AFL'de görünebilir ama **ENERGY ile 1:1 eşleşmesi beklenmez**
- Mahsup zinciri takip edilmelidir

## Emanet Tespit SQL

```sql
-- 1. Tüm emanet hesapları listele
SELECT 
    CA.ACCOUNT_ID,
    CA.AGREEMENT_ID,
    CA.ACCRUE_TYPE_ID,
    SUM(AI.AMOUNT * AI.STATUS) AS EMANET_BAKIYE,
    COUNT(DISTINCT AA.ACCOUNT_ACTION_ID) AS ISLEM_SAYISI
FROM CS_ACCOUNT CA
JOIN CS_ACCOUNT_ACTION AA ON AA.ACCOUNT_ID = CA.ACCOUNT_ID
LEFT JOIN CS_ACCOUNT_INCOME AI ON AI.ACCOUNT_ACTION_ID = AA.ACCOUNT_ACTION_ID
WHERE CA.ACCRUE_TYPE_ID = 14
GROUP BY CA.ACCOUNT_ID, CA.AGREEMENT_ID, CA.ACCRUE_TYPE_ID
HAVING ABS(SUM(AI.AMOUNT * AI.STATUS)) > 0.02
ORDER BY CA.ACCOUNT_ID;

-- 2. Emanet giriş (güvence) kayıtları
SELECT 
    AA.ACCOUNT_ID,
    AA.ACTION_TYPE_ID,
    AA.AMOUNT,
    AA.STATUS,
    AA.ACTION_DATE,
    AA.EXPLAIN,
    AI.INCOME_TYPE_ID,
    IT.INCOME_TYPE_NAME
FROM CS_ACCOUNT_ACTION AA
JOIN CS_ACCOUNT CA ON CA.ACCOUNT_ID = AA.ACCOUNT_ID
LEFT JOIN CS_ACCOUNT_INCOME AI ON AI.ACCOUNT_ACTION_ID = AA.ACCOUNT_ACTION_ID
LEFT JOIN CS_INCOME_TYPE IT ON IT.INCOME_TYPE_ID = AI.INCOME_TYPE_ID
WHERE CA.ACCRUE_TYPE_ID = 14
  AND AA.ACTION_TYPE_ID = 20  -- EMANET GİRİŞİ
ORDER BY AA.ACTION_DATE DESC;

-- 3. Mahsup zinciri (emanetten borçlu faturaya)
WITH emanet_cikis AS (
    SELECT 
        AA.ACCOUNT_ID AS EMANET_ACCT,
        AA.ACCOUNT_ACTION_ID AS EMANET_ACTION_ID,
        AA.REF_DEPOSIT_ACCOUNT_ID AS HEDEF_ACCT,
        AA.AMOUNT AS CIKIS_TUTAR,
        AA.ACTION_DATE
    FROM CS_ACCOUNT_ACTION AA
    WHERE AA.ACTION_TYPE_ID = 12  -- EMANET ÇIKIŞI
      AND AA.REF_DEPOSIT_ACCOUNT_ID IS NOT NULL
),
mahsup_islem AS (
    SELECT 
        AA.ACCOUNT_ID AS BORCLU_ACCT,
        AA.REF_DEPOSIT_ACCOUNT_ID AS KAYNAK_EMANET,
        AA.REF_DEPOSIT_ACCOUNT_ACTION_ID AS EMANET_ACTION_REF,
        AA.AMOUNT AS MAHSUP_TUTAR,
        AA.ACTION_DATE
    FROM CS_ACCOUNT_ACTION AA
    WHERE AA.ACTION_TYPE_ID IN (6, 24)  -- MAHSUP
      AND AA.REF_DEPOSIT_ACCOUNT_ID IS NOT NULL
)
SELECT 
    ec.EMANET_ACCT,
    ec.HEDEF_ACCT,
    ec.CIKIS_TUTAR,
    mi.MAHSUP_TUTAR,
    ec.ACTION_DATE AS CIKIS_TARIH,
    mi.ACTION_DATE AS MAHSUP_TARIH,
    CASE 
        WHEN ABS(ec.CIKIS_TUTAR + mi.MAHSUP_TUTAR) < 0.02 THEN 'OK'
        ELSE 'TUTAR_UYUMSUZ'
    END AS DURUM
FROM emanet_cikis ec
LEFT JOIN mahsup_islem mi 
    ON mi.KAYNAK_EMANET = ec.EMANET_ACCT
   AND mi.EMANET_ACTION_REF = ec.EMANET_ACTION_ID
ORDER BY ec.ACTION_DATE DESC;

-- 4. Kullanılmamış emanet bakiyesi (iade bekleyen)
SELECT 
    CA.ACCOUNT_ID,
    CA.AGREEMENT_ID,
    SUM(AI.AMOUNT * AI.STATUS) AS KALAN_EMANET,
    MAX(AA.ACTION_DATE) AS SON_ISLEM_TARIH
FROM CS_ACCOUNT CA
JOIN CS_ACCOUNT_ACTION AA ON AA.ACCOUNT_ID = CA.ACCOUNT_ID
LEFT JOIN CS_ACCOUNT_INCOME AI ON AI.ACCOUNT_ACTION_ID = AA.ACCOUNT_ACTION_ID
WHERE CA.ACCRUE_TYPE_ID = 14
GROUP BY CA.ACCOUNT_ID, CA.AGREEMENT_ID
HAVING SUM(AI.AMOUNT * AI.STATUS) < -0.50  -- Negatif = müşteri lehine bakiye
ORDER BY ABS(SUM(AI.AMOUNT * AI.STATUS)) DESC;
```

## Wizard Adımları (Emanet İçin)

### Adım 15: İptal/Emanet Tespit
```csharp
// C# Service call
var (rows, gaps, log) = await _sms.LoadIptalEmanetAsync(req, runId, ct);

// Beklenen çıktı KIND dağılımı:
// - EMANET_GIRIS: tip20 işlemleri
// - CANCEL_EMANET: tip12 işlemleri (emanet → borçlu)
// - EMANET_MAHSUP: tip6/24 işlemleri (borçlu hesapta mahsup)
// - PAY_CANCEL: tip9 işlemleri (iptal)
```

### Adım 14: FRK Karşılaştırma (Emanet Filtresi)
```csharp
// Emanet hesaplar HARICI_ACIK olarak ayrılır
if (aflRow["ACCRUE_TYPE_ID"] == 14 || aflRow["MIG_IN_SCOPE"] == 0)
{
    kind = "HARICI_ACIK";
    severity = "INFO";  // CRITICAL değil!
}
```

**Önemli:** FRK adımında HARICI_ACIK kategorisi:
- ✅ **Normal durum** - hata değil
- ℹ️ **Bilgilendirme amaçlı** - takip için
- ❌ **CRITICAL yapma** - migrasyon bloklamaz

## Migrasyon Kontrol Listesi

### ✅ Emanet Hesaplar İçin Yapılacaklar

1. **Tespit (Adım 15)**
   ```
   - EMANET_GIRIS sayısı ve toplamı
   - EMANET_MAHSUP zincirleri tamamlanmış mı?
   - Kullanılmamış emanet bakiyesi ne kadar?
   ```

2. **Sınıflandırma (Adım 14)**
   ```
   - ACCRUE_TYPE_ID=14 → HARICI_ACIK ✓
   - MIG_IN_SCOPE=0 → HARICI_ACIK ✓
   - Severity = INFO (CRITICAL değil) ✓
   ```

3. **Doğrulama**
   ```sql
   -- Mahsup tutarları eşleşiyor mu?
   SELECT 
       EMANET_ACCT,
       SUM(CIKIS) AS TOPLAM_CIKIS,
       SUM(MAHSUP) AS TOPLAM_MAHSUP,
       ABS(SUM(CIKIS) - SUM(MAHSUP)) AS FARK
   FROM (mahsup_zinciri_view)
   GROUP BY EMANET_ACCT
   HAVING ABS(SUM(CIKIS) - SUM(MAHSUP)) > 0.02;
   ```

4. **Raporlama**
   ```
   Emanet Hesap Özeti:
   ├─ Toplam Emanet Hesap: X
   ├─ Güvence Girişi (tip20): Y hesap, Σ=ZZZ TL
   ├─ Mahsup Kullanılan: A hesap, Σ=BBB TL
   ├─ Kalan Emanet: CCC TL
   └─ İade Bekleyen: D hesap
   ```

### ❌ Yapılmaması Gerekenler

1. **Emaneti normal fatura gibi ONLY_EN yapma**
   ```
   ❌ YANLIŞ: "ENERGY'de açık ama AFL'de yok → CRITICAL"
   ✅ DOĞRU: "Emanet hesap → HARICI_ACIK (INFO)"
   ```

2. **MIG_IN_SCOPE=0 kontrolü atlama**
   ```
   ❌ YANLIŞ: Tüm AFL kayıtlarını aynı şekilde işle
   ✅ DOĞRU: MIG_IN_SCOPE=0 → ayrı kategori
   ```

3. **Mahsup zincirini takip etmeme**
   ```
   ❌ YANLIŞ: Sadece emanet bakiyesine bak
   ✅ DOĞRU: tip12 → tip6 zincirini doğrula
   ```

## Örnek Vaka: 30667167 + 30667165

```
Durum: Güvence bedeli ile fesih borcu kapatma

Hesap 30667167 (EMANET):
├─ tip20: −504.51 TL (GÜVENCE GİRİŞ)
├─ tip12: +7.25 TL (ÇIKIŞ → 30667165)
└─ tip40: +497.26 TL (İADE)
Bakiye: 0 TL ✓

Hesap 30667165 (İŞ EMRİ):
├─ Borç: +7.25 TL
└─ tip6 MAHSUP: −7.25 TL (← emanet 30667167)
Bakiye: 0 TL ✓

Wizard Çıktısı:
├─ Adım 15: EMANET_GIRIS=1, EMANET_MAHSUP=1
└─ Adım 14: 30667167 → HARICI_ACIK (INFO)
```

## Gelir Kodları (İncome Types)

| INCOME_TYPE_ID | İsim | Kullanım |
|----------------|------|----------|
| **162** | GÜVENCE BEDELİ | Ana güvence tutarı |
| **1936** | GÜVENCE FARK BEDELİ | Fark/ek güvence |

Bu kodlar emanet girişinde (tip20) kullanılır.

## Troubleshooting

### Sorun 1: "Emanet hesap ONLY_EN olarak CRITICAL gösteriliyor"
**Çözüm:**
```csharp
// FrkAsync metodunda kontrol ekle
if (aflRow["ACCRUE_TYPE_ID"]?.ToString() == "14")
{
    kind = "HARICI_ACIK";
    severity = "INFO";
}
```

### Sorun 2: "Mahsup tutarları eşleşmiyor"
**Çözüm:**
```sql
-- tip12 (çıkış) ve tip6 (mahsup) tutarlarını kontrol et
-- AMOUNT * STATUS net değeri eşit olmalı
```

### Sorun 3: "Emanet bakiye yanlış hesaplanıyor"
**Çözüm:**
```sql
-- TOTAL_DEBT/CREDIT değil, SUM(AMOUNT*STATUS) kullan!
SELECT 
    ACCOUNT_ID,
    SUM(AMOUNT * STATUS) AS DOGRU_BAKIYE
FROM CS_ACCOUNT_INCOME
WHERE ACCOUNT_ID IN (emanet_accounts)
GROUP BY ACCOUNT_ID;
```

## Sonuç

Emanet hesaplar **özel kategori** olup:
- ✅ HARICI_ACIK (INFO) olarak sınıflandırılmalı
- ✅ Mahsup zinciri doğrulanmalı
- ✅ Ayrı raporlanmalı
- ❌ Normal fatura gibi CRITICAL yapılmamalı
- ❌ AFL/ENERGY 1:1 eşleşmesi beklenmemeli
