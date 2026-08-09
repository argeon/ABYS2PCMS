# Taksit Yönetimi - Kapalı ve İptal Dahil (Güncellenmiş)

## Amaç
SMS'teki **TÜM taksitleri** (açık, kapalı, iptal) ENERGY'ye aktarmak ve durumlarına göre işlem yapmak:
- **İptal ise** → CANCELED=1 olarak işaretlenmeli
- **Tahsil edilmiş ise** → PAID, CLOSED bilgileri yazılmalı
- **Açık ise** → Mevcut haliyle aktarılmalı

## Güncelleme (Yeni Mantık)

### Önceki Davranış (ESKİ)
- ❌ Sadece **açık taksitleri** getiriyordu (`BALANCE > 0.01` filtresi)
- ❌ **Kapalı/iptal taksitler eksikti**
- ❌ Durum tespiti yapılmıyordu

### Yeni Davranış (GÜNCELLEME)
- ✅ **TÜM taksitleri** getiriyor (açık, kapalı, iptal, fazla ödeme)
- ✅ Her taksit için **durum tespiti** yapıyor:
  - `ACIK`: Bakiye > 0.01
  - `KAPALI`: Bakiye ≈ 0 ve iptal yok
  - `IPTAL`: ACTION_TYPE_ID=9 var
  - `FAZLA_ODEME`: Bakiye < -0.01
- ✅ **Tahsilat bilgileri** dahil (tutar, adet, tarih)
- ✅ **İptal bilgileri** dahil (tutar, adet, tarih)
- ✅ **Taksit detayları** dahil (taksit no, toplam taksit, tutar)

## SMS Tarafı Tespit (LoadTaksitAsync)

### Yeni SQL Yapısı

```sql
WITH taksit_base AS (
  -- Tüm taksitli hesaplar + CS_INSTALLMENT detayı
  SELECT 
    a.ID AS FATURAID,
    a.INSTALLMENT_ID,
    inst.SEQUENCE_NUMBER AS TAKSIT_NO,
    inst.TOTAL_INSTALLMENTS AS TOPLAM_TAKSIT,
    inst.AMOUNT AS TAKSIT_TUTARI
  FROM CS_ACCOUNT a
  JOIN CS_INSTALLMENT inst ON inst.ID = a.INSTALLMENT_ID
  WHERE a.AGREEMENT_ID = :agrId
),
bal AS (
  -- Gerçek bakiye (AMOUNT×STATUS)
  SELECT 
    aa.ACCOUNT_ID,
    SUM(ai.STATUS * ai.AMOUNT) AS BALANCE,
    SUM(CASE WHEN ai.STATUS > 0 THEN ai.AMOUNT * ai.STATUS ELSE 0 END) AS TOTAL_DEBT,
    SUM(CASE WHEN ai.STATUS < 0 THEN ABS(ai.AMOUNT * ai.STATUS) ELSE 0 END) AS TOTAL_CREDIT
  FROM CS_ACCOUNT_ACTION aa
  JOIN CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = aa.ID
  GROUP BY aa.ACCOUNT_ID
),
pay_info AS (
  -- Tahsilat bilgileri (tip3)
  SELECT 
    aa.ACCOUNT_ID,
    COUNT(DISTINCT aa.ID) AS TAHSILAT_ADET,
    SUM(ABS(ai.AMOUNT * ai.STATUS)) AS TAHSILAT_TUTAR,
    MAX(aa.ACTION_DATE) AS SON_TAHSILAT_TARIH
  FROM CS_ACCOUNT_ACTION aa
  JOIN CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = aa.ID
  WHERE aa.ACTION_TYPE_ID = 3  -- Tahsilat
  GROUP BY aa.ACCOUNT_ID
),
iptal_info AS (
  -- İptal bilgileri (tip9)
  SELECT 
    aa.ACCOUNT_ID,
    COUNT(DISTINCT aa.ID) AS IPTAL_ADET,
    SUM(ABS(ai.AMOUNT * ai.STATUS)) AS IPTAL_TUTAR,
    MAX(aa.ACTION_DATE) AS SON_IPTAL_TARIH
  FROM CS_ACCOUNT_ACTION aa
  JOIN CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = aa.ID
  WHERE aa.ACTION_TYPE_ID = 9  -- İptal
  GROUP BY aa.ACCOUNT_ID
)
SELECT 
  t.*,
  b.BALANCE,
  b.TOTAL_DEBT,
  b.TOTAL_CREDIT,
  p.TAHSILAT_TUTAR,
  p.TAHSILAT_ADET,
  p.SON_TAHSILAT_TARIH,
  i.IPTAL_TUTAR,
  i.IPTAL_ADET,
  i.SON_IPTAL_TARIH,
  -- DURUM TESPİTİ
  CASE
    WHEN i.IPTAL_ADET > 0 THEN 'IPTAL'
    WHEN ABS(b.BALANCE) <= 0.01 THEN 'KAPALI'
    WHEN b.BALANCE > 0.01 THEN 'ACIK'
    WHEN b.BALANCE < -0.01 THEN 'FAZLA_ODEME'
    ELSE 'BILINMIYOR'
  END AS TAKSIT_DURUMU
FROM taksit_base t
LEFT JOIN bal b ON b.ACCOUNT_ID = t.FATURAID
LEFT JOIN pay_info p ON p.ACCOUNT_ID = t.FATURAID
LEFT JOIN iptal_info i ON i.ACCOUNT_ID = t.FATURAID
ORDER BY t.TAKSIT_NO
```

### Çıktı Kolonları

| Kolon | Tip | Açıklama |
|-------|-----|----------|
| `FATURAID` | NUMBER | CS_ACCOUNT.ID |
| `INSTALLMENT_ID` | NUMBER | Taksit grubu ID |
| `TAKSIT_NO` | NUMBER | Kaçıncı taksit (1,2,3...) |
| `TOPLAM_TAKSIT` | NUMBER | Toplam taksit sayısı |
| `TAKSIT_TUTARI` | NUMBER(15,3) | Taksit tutarı |
| `BALANCE` | NUMBER(15,3) | Güncel bakiye (AMOUNT×STATUS) |
| `TOTAL_DEBT` | NUMBER(15,3) | Toplam borç |
| `TOTAL_CREDIT` | NUMBER(15,3) | Toplam alacak |
| `TAHSILAT_TUTAR` | NUMBER(15,3) | Tahsil edilen toplam |
| `TAHSILAT_ADET` | NUMBER | Tahsilat adedi |
| `SON_TAHSILAT_TARIH` | DATE | Son tahsilat tarihi |
| `IPTAL_TUTAR` | NUMBER(15,3) | İptal edilen tutar |
| `IPTAL_ADET` | NUMBER | İptal adedi |
| `SON_IPTAL_TARIH` | DATE | Son iptal tarihi |
| **`TAKSIT_DURUMU`** | VARCHAR | `ACIK`, `KAPALI`, `IPTAL`, `FAZLA_ODEME` |

### Özet İstatistikler

SMS adımı şu özet gap'i üretir:

```
TAKSIT_SUMMARY:
  ACIK=5 KAPALI=12 IPTAL=2 FAZLA_ODEME=0 (Toplam=19)
```

## ENERGY Tarafı Tespit (LoadScenarioSpotAsync - taksit)

### Yeni SQL Yapısı

```sql
SELECT TOP 500 
    inv.LREF,
    inv.ABYS_ACCOUNT_ID AS FATURAID,
    inv.FICHENO,
    inv.EXPLAIN,
    inv.CLOSED,
    inv.CANCELED,
    inv.PAYABLETOTAL,
    pt.INST_NR AS TAKSIT_NO,
    pt.PAYABLETOTAL AS PT_PAYABLE,
    pt.PAID AS PT_PAID,
    pt.CANCELED AS PT_CANCELED,
    pt.CANCELLATIONPAYMENT,  -- Dinamik (yoksa NULL)
    pt.PAYMENTDATE AS SON_ODEME_TARIH,
    -- DURUM TESPİTİ
    CASE
        WHEN inv.CANCELED=1 OR pt.CANCELED=1 THEN 'IPTAL'
        WHEN inv.CLOSED=1 AND pt.PAID >= pt.PAYABLETOTAL THEN 'KAPALI'
        WHEN pt.PAID > 0 AND pt.PAID < pt.PAYABLETOTAL THEN 'KISMI_ODEME'
        WHEN pt.PAID = 0 THEN 'ACIK'
        ELSE 'DIGER'
    END AS EN_TAKSIT_DURUMU,
    -- TESPİT TİPİ
    CASE 
        WHEN inv.EXPLAIN LIKE '%TAKSIT%' THEN 'EXPLAIN'
        WHEN pt.INST_NR > 0 THEN 'INST_NR'
        ELSE 'MANUAL'
    END AS TESPIT_TIPI
FROM LS_XXX_XXXX_INVOICE inv
LEFT JOIN LS_XXX_XXXX_PAYTRANS pt 
    ON pt.INVOICEREF = inv.LREF
WHERE inv.OWNERREF = @agrId
  AND (
    inv.EXPLAIN LIKE '%TAKSIT%'
    OR pt.INST_NR > 0
  )
ORDER BY pt.INST_NR
```

**ÖNEMLİ:** `CANCELLATIONPAYMENT` kolonu dinamik kontrol edilir:
- Varsa → SELECT'e dahil edilir
- Yoksa → `CAST(NULL AS INT)` eklenir

### Çıktı Kolonları

| Kolon | Tip | Açıklama |
|-------|-----|----------|
| `LREF` | BIGINT | ENERGY fatura ID |
| `FATURAID` | BIGINT | ABYS_ACCOUNT_ID (SMS ACCOUNT_ID) |
| `FICHENO` | VARCHAR | Fiş numarası |
| `EXPLAIN` | VARCHAR(100) | Açıklama |
| `CLOSED` | BIT | Kapalı mı? |
| `CANCELED` | BIT | İptal mi? |
| `TAKSIT_NO` | INT | Taksit numarası (INST_NR) |
| `PT_PAID` | DECIMAL | Ödenen tutar |
| `PT_CANCELED` | BIT | PAYTRANS iptal mi? |
| `CANCELLATIONPAYMENT` | INT | İptal ödeme tipi |
| `SON_ODEME_TARIH` | DATETIME | Son ödeme tarihi |
| **`EN_TAKSIT_DURUMU`** | VARCHAR | `ACIK`, `KAPALI`, `IPTAL`, `KISMI_ODEME` |
| **`TESPIT_TIPI`** | VARCHAR | `EXPLAIN`, `INST_NR`, `MANUAL` |

## Wizard Adım 10 Özeti

### Karşılaştırma ve Raporlama

Orchestrator (`ScenarioCompareAsync`) şu özeti üretir:

```
TAKSIT_DURUM_SUMMARY (INFO):
  SMS: ACIK=5 KAPALI=12 IPTAL=2 FAZLA=0 
  ENERGY: ACIK=4 KAPALI=11 IPTAL=2 KISMI=1
```

### Gap Tespitleri

| Gap Code | Severity | Koşul | Açıklama |
|----------|----------|-------|----------|
| `TAKSIT_ACIK_MISMATCH` | WARN | SMS ACIK>0, EN ACIK=0 | ENERGY'de açık taksit bulunamadı (INST_NR/EXPLAIN eksik) |
| `TAKSIT_IPTAL_MISMATCH` | WARN | SMS IPTAL>0, EN IPTAL=0 | ENERGY'de iptal bilgisi yok (CANCELED=1 set edilmeli) |
| `TAKSIT_KAPALI_MISMATCH` | INFO | SMS KAPALI>0, EN KAPALI=0 | ENERGY'de CLOSED=1 eksik |

## Migrasyon İşlemleri

### 1. İptal Taksitler (SMS TAKSIT_DURUMU='IPTAL')

**SMS'te:**
```sql
-- İptal tespiti
ACTION_TYPE_ID = 9  -- Tahsilat İptal
```

**ENERGY'ye aktarım:**
```sql
-- INVOICE seviyesinde
UPDATE LS_XXX_XXXX_INVOICE
SET CANCELED = 1,
    EXPLAIN = CONCAT(EXPLAIN, ' [İPTAL]')
WHERE ABYS_ACCOUNT_ID IN (iptal_account_ids);

-- PAYTRANS seviyesinde
UPDATE LS_XXX_XXXX_PAYTRANS pt
SET pt.CANCELED = 1,
    pt.CANCELLATIONPAYMENT = 1
WHERE pt.INVOICEREF IN (iptal_invoice_lrefs);
```

### 2. Kapalı Taksitler (SMS TAKSIT_DURUMU='KAPALI')

**SMS'te:**
```sql
-- Kapalı tespiti
BALANCE <= 0.01 AND IPTAL_ADET IS NULL
-- Tahsilat var: TAHSILAT_TUTAR ≈ TAKSIT_TUTARI
```

**ENERGY'ye aktarım:**
```sql
-- PAYTRANS seviyesinde
UPDATE LS_XXX_XXXX_PAYTRANS pt
SET pt.PAID = pt.PAYABLETOTAL,
    pt.PAYMENTDATE = :son_tahsilat_tarih
WHERE pt.ABYS_ACCOUNT_ID IN (kapali_account_ids);

-- INVOICE seviyesinde
UPDATE LS_XXX_XXXX_INVOICE inv
SET inv.CLOSED = 1,
    inv.LASTPAIDDATE = :son_tahsilat_tarih
WHERE inv.ABYS_ACCOUNT_ID IN (kapali_account_ids)
  AND NOT EXISTS (
    SELECT 1 FROM LS_XXX_XXXX_PAYTRANS pt2
    WHERE pt2.INVOICEREF = inv.LREF
      AND pt2.PAID < pt2.PAYABLETOTAL
  );
```

### 3. Açık Taksitler (SMS TAKSIT_DURUMU='ACIK')

**SMS'te:**
```sql
-- Açık tespiti
BALANCE > 0.01
-- Kısmi ödeme olabilir: 0 < TAHSILAT_TUTAR < TAKSIT_TUTARI
```

**ENERGY'ye aktarım:**
```sql
-- PAYTRANS seviyesinde
UPDATE LS_XXX_XXXX_PAYTRANS pt
SET pt.PAID = :tahsilat_tutar,
    pt.PAYMENTDATE = :son_tahsilat_tarih
WHERE pt.ABYS_ACCOUNT_ID IN (acik_account_ids);

-- INVOICE kapalı OLMASIN
UPDATE LS_XXX_XXXX_INVOICE inv
SET inv.CLOSED = 0
WHERE inv.ABYS_ACCOUNT_ID IN (acik_account_ids);
```

## Migrasyon Scripti Örneği

```sql
-- ========================================
-- TAKSİT MİGRASYONU (Açık+Kapalı+İptal)
-- ========================================

-- ADIM 1: SMS'ten taksit durumları (Wizard Adım 10 çıktısı)
-- Bu veriyi wizard'dan JSON olarak al veya staging table'a yaz

CREATE TABLE #SMS_TAKSIT_STAGING (
    FATURAID BIGINT,
    TAKSIT_NO INT,
    TAKSIT_DURUMU VARCHAR(20),  -- ACIK, KAPALI, IPTAL
    TAHSILAT_TUTAR DECIMAL(15,3),
    SON_TAHSILAT_TARIH DATE,
    IPTAL_ADET INT,
    SON_IPTAL_TARIH DATE
);

-- Wizard çıktısını buraya yükle
INSERT INTO #SMS_TAKSIT_STAGING (...)
SELECT ... FROM wizard_output;

-- ADIM 2: İptal taksitleri işaretle
UPDATE inv
SET inv.CANCELED = 1,
    inv.EXPLAIN = CONCAT(COALESCE(inv.EXPLAIN,''), ' [İPTAL]')
FROM LS_XXX_XXXX_INVOICE inv
JOIN #SMS_TAKSIT_STAGING s ON s.FATURAID = inv.ABYS_ACCOUNT_ID
WHERE s.TAKSIT_DURUMU = 'IPTAL';

UPDATE pt
SET pt.CANCELED = 1,
    pt.CANCELLATIONPAYMENT = 1
FROM LS_XXX_XXXX_PAYTRANS pt
JOIN LS_XXX_XXXX_INVOICE inv ON inv.LREF = pt.INVOICEREF
JOIN #SMS_TAKSIT_STAGING s ON s.FATURAID = inv.ABYS_ACCOUNT_ID
WHERE s.TAKSIT_DURUMU = 'IPTAL';

-- ADIM 3: Kapalı taksitlere tahsilat bilgisi yaz
UPDATE pt
SET pt.PAID = pt.PAYABLETOTAL,
    pt.PAYMENTDATE = COALESCE(s.SON_TAHSILAT_TARIH, GETDATE())
FROM LS_XXX_XXXX_PAYTRANS pt
JOIN LS_XXX_XXXX_INVOICE inv ON inv.LREF = pt.INVOICEREF
JOIN #SMS_TAKSIT_STAGING s ON s.FATURAID = inv.ABYS_ACCOUNT_ID
WHERE s.TAKSIT_DURUMU = 'KAPALI'
  AND pt.PAID < pt.PAYABLETOTAL;

UPDATE inv
SET inv.CLOSED = 1,
    inv.LASTPAIDDATE = COALESCE(s.SON_TAHSILAT_TARIH, GETDATE())
FROM LS_XXX_XXXX_INVOICE inv
JOIN #SMS_TAKSIT_STAGING s ON s.FATURAID = inv.ABYS_ACCOUNT_ID
WHERE s.TAKSIT_DURUMU = 'KAPALI'
  AND inv.CLOSED = 0
  AND NOT EXISTS (
    SELECT 1 FROM LS_XXX_XXXX_PAYTRANS pt2
    WHERE pt2.INVOICEREF = inv.LREF
      AND pt2.PAID < pt2.PAYABLETOTAL
  );

-- ADIM 4: Açık taksitlere kısmi ödeme yaz (varsa)
UPDATE pt
SET pt.PAID = COALESCE(s.TAHSILAT_TUTAR, 0),
    pt.PAYMENTDATE = s.SON_TAHSILAT_TARIH
FROM LS_XXX_XXXX_PAYTRANS pt
JOIN LS_XXX_XXXX_INVOICE inv ON inv.LREF = pt.INVOICEREF
JOIN #SMS_TAKSIT_STAGING s ON s.FATURAID = inv.ABYS_ACCOUNT_ID
WHERE s.TAKSIT_DURUMU = 'ACIK'
  AND s.TAHSILAT_TUTAR > 0;

-- ADIM 5: Doğrulama
SELECT 
    s.TAKSIT_DURUMU AS SMS_DURUM,
    COUNT(*) AS ADET,
    SUM(CASE WHEN inv.CLOSED = 1 THEN 1 ELSE 0 END) AS EN_CLOSED,
    SUM(CASE WHEN inv.CANCELED = 1 THEN 1 ELSE 0 END) AS EN_CANCELED,
    SUM(CASE WHEN pt.PAID >= pt.PAYABLETOTAL THEN 1 ELSE 0 END) AS EN_PAID_FULL
FROM #SMS_TAKSIT_STAGING s
JOIN LS_XXX_XXXX_INVOICE inv ON inv.ABYS_ACCOUNT_ID = s.FATURAID
LEFT JOIN LS_XXX_XXXX_PAYTRANS pt ON pt.INVOICEREF = inv.LREF
GROUP BY s.TAKSIT_DURUMU;

-- Beklenen:
-- SMS_DURUM='IPTAL' → EN_CANCELED>0
-- SMS_DURUM='KAPALI' → EN_CLOSED>0, EN_PAID_FULL>0
-- SMS_DURUM='ACIK' → EN_CLOSED=0
```

## Kontrol Listesi

### SMS Tarafı
- [x] Tüm taksitleri getir (açık+kapalı+iptal)
- [x] CS_INSTALLMENT ile join (taksit no, toplam taksit)
- [x] BALANCE hesapla (AMOUNT×STATUS)
- [x] Tahsilat bilgilerini topla (tip3)
- [x] İptal bilgilerini topla (tip9)
- [x] TAKSIT_DURUMU tespit et (ACIK/KAPALI/IPTAL/FAZLA_ODEME)

### ENERGY Tarafı
- [x] INST_NR ve EXPLAIN ile taksitleri bul
- [x] CANCELED kontrol (invoice + paytrans)
- [x] CLOSED kontrol
- [x] PAID vs PAYABLETOTAL karşılaştır
- [x] EN_TAKSIT_DURUMU tespit et (ACIK/KAPALI/IPTAL/KISMI_ODEME)
- [x] CANCELLATIONPAYMENT kolonu dinamik kontrol

### Migrasyon
- [ ] İptal taksitler: CANCELED=1 set et
- [ ] Kapalı taksitler: PAID=PAYABLETOTAL, CLOSED=1 set et
- [ ] Açık taksitler: PAID kısmi ödemeleri yaz
- [ ] Tahsilat tarihleri yaz (PAYMENTDATE, LASTPAIDDATE)
- [ ] Doğrulama: SMS durum vs ENERGY durum karşılaştır

## Beklenen Sonuçlar

| Sözleşme | SMS ACIK | SMS KAPALI | SMS IPTAL | EN ACIK | EN KAPALI | EN IPTAL | Durum |
|----------|----------|------------|-----------|---------|-----------|----------|--------|
| 31986 | 0 | 15 | 1 | 0 | 15 | 1 | ✅ Eşleşti |
| 33228 | 3 | 8 | 0 | 3 | 8 | 0 | ✅ Eşleşti |
| 33229 | 5 | 2 | 1 | 4 | 2 | 0 | ⚠️ İptal eksik |
| 33230 | 0 | 0 | 0 | 0 | 0 | 0 | ✅ Taksit yok |

## Notlar

1. **BALANCE filtresi kaldırıldı:** Artık tüm taksitler geliyor (eski `> 0.01` koşulu yok)
2. **Durum önceliği:** İPTAL > KAPALI > ACIK > FAZLA_ODEME (SQL CASE sırası)
3. **Tahsilat tarih:** `SON_TAHSILAT_TARIH` ENERGY'ye `PAYMENTDATE` ve `LASTPAIDDATE` olarak yazılır
4. **İptal tespit:** Sadece `ACTION_TYPE_ID=9` varlığına bakıyor (tutar 0 olsa bile)
5. **CANCELLATIONPAYMENT:** Dinamik - yoksa NULL döner, migrasyon hata vermez
