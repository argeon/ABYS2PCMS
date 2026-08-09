# Taksit Tespit Kuralları (Adım 10)

## Amaç
SMS'teki taksitli hesapların ENERGY'de doğru şekilde tespit edilmesi ve karşılaştırılması.

## SMS Tarafı Tespit Mantığı

### Öncelik 1: LS_AFL_OPEN_DEBT (O50 CTAS)
```sql
SELECT 
    FATURAID, 
    SOZLESME_HESABI, 
    BALANCE, 
    TAKSIT_DURUMU, 
    INSTALLMENT_ID
FROM MIG_XXX.LS_AFL_OPEN_DEBT
WHERE SOZLESME_HESABI = :agrId 
  AND TAKSIT_DURUMU = 'T'
```

**Koşul:** `TAKSIT_DURUMU = 'T'`

### Öncelik 2: CS_ACCOUNT Fallback (LS_AFL yoksa)
```sql
SELECT 
    a.ID AS FATURAID,
    a.AGREEMENT_ID AS SOZLESME,
    a.INSTALLMENT_ID,
    SUM(ai.AMOUNT * ai.STATUS) AS BALANCE
FROM SMS.CS_ACCOUNT a
JOIN CS_ACCOUNT_ACTION aa ON aa.ACCOUNT_ID = a.ID
JOIN CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = aa.ID
WHERE a.AGREEMENT_ID = :agrId
  AND a.INSTALLMENT_ID IS NOT NULL
  AND BALANCE > 0.01
GROUP BY a.ID, a.AGREEMENT_ID, a.INSTALLMENT_ID
```

**Koşul:** `INSTALLMENT_ID IS NOT NULL` ve `BALANCE > 0.01`

## ENERGY Tarafı Tespit Mantığı

```sql
SELECT 
    inv.LREF,
    inv.OWNERREF,
    inv.ABYS_ACCOUNT_ID,
    inv.EXPLAIN,
    pt.INST_NR
FROM LS_XXX_XXXX_INVOICE inv
LEFT JOIN LS_XXX_XXXX_PAYTRANS pt 
    ON pt.INVOICEREF = inv.LREF 
   AND pt.CANCELED = 0
WHERE inv.OWNERREF = :agrId
  AND inv.CANCELED = 0
  AND (
    UPPER(inv.EXPLAIN) LIKE '%TAKSIT%'
    OR pt.INST_NR > 0
  )
```

**Koşullar (OR):**
1. `INVOICE.EXPLAIN` içinde "TAKSIT" kelimesi
2. `PAYTRANS.INST_NR > 0`

## Yaygın Sorunlar ve Çözümleri

### Sorun 1: LS_AFL_OPEN_DEBT'te TAKSIT_DURUMU Yanlış

**Belirti:**
```
SMS SORGU 2 (fallback): 5 taksitli hesap
SMS SORGU 1 (AFL): 0 kayıt
```

**Kök Neden:**
- `LS_AFL_OPEN_DEBT.TAKSIT_DURUMU` alanı doğru set edilmemiş
- CTAS oluşturulurken `CS_ACCOUNT.INSTALLMENT_ID` kontrolü yapılmamış

**Çözüm:**
```sql
-- LS_AFL_OPEN_DEBT CTAS'ında TAKSIT_DURUMU set mantığı
UPDATE MIG_XXX.LS_AFL_OPEN_DEBT o
SET o.TAKSIT_DURUMU = 'T'
WHERE o.INSTALLMENT_ID IS NOT NULL;

-- Veya CTAS'ı yeniden oluştur:
CREATE TABLE LS_AFL_OPEN_DEBT AS
SELECT 
    a.ID AS FATURAID,
    a.AGREEMENT_ID AS SOZLESME_HESABI,
    SUM(ai.AMOUNT * ai.STATUS) AS BALANCE,
    CASE 
        WHEN a.INSTALLMENT_ID IS NOT NULL THEN 'T'
        ELSE 'N'
    END AS TAKSIT_DURUMU,
    a.INSTALLMENT_ID
FROM CS_ACCOUNT a
JOIN CS_ACCOUNT_ACTION aa ON aa.ACCOUNT_ID = a.ID
JOIN CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = aa.ID
GROUP BY a.ID, a.AGREEMENT_ID, a.INSTALLMENT_ID
HAVING SUM(ai.AMOUNT * ai.STATUS) > 0.02;
```

### Sorun 2: ENERGY'de INST_NR Boş veya EXPLAIN'de Taksit Yok

**Belirti:**
```
ENERGY SORGU 5: 0 kayıt
SMS'te 5 taksitli hesap var
```

**Kök Neden:**
- Migrasyon sırasında `PAYTRANS.INST_NR` set edilmemiş
- `INVOICE.EXPLAIN` alanında "taksit" ifadesi yok

**Çözüm A: INST_NR Güncelle**
```sql
-- SMS INSTALLMENT_ID'den ENERGY INST_NR'a mapping
UPDATE ENERGY.LS_XXX_XXXX_PAYTRANS pt
SET pt.INST_NR = (
    SELECT inst.SEQUENCE_NUMBER
    FROM SMS.CS_INSTALLMENT inst
    WHERE inst.ID = sms_acct.INSTALLMENT_ID
      AND inst.AGREEMENT_ID = pt.OWNERREF
)
FROM ENERGY.LS_XXX_XXXX_INVOICE inv
JOIN SMS.CS_ACCOUNT sms_acct 
    ON sms_acct.ID = inv.ABYS_ACCOUNT_ID
WHERE pt.INVOICEREF = inv.LREF
  AND sms_acct.INSTALLMENT_ID IS NOT NULL
  AND pt.INST_NR IS NULL;
```

**Çözüm B: EXPLAIN Güncelle**
```sql
-- INVOICE.EXPLAIN'e taksit bilgisi ekle
UPDATE ENERGY.LS_XXX_XXXX_INVOICE inv
SET inv.EXPLAIN = CONCAT(
    COALESCE(inv.EXPLAIN, ''), 
    ' [TAKSIT ', inst.SEQUENCE_NUMBER, '/', inst.TOTAL_INSTALLMENTS, ']'
)
FROM SMS.CS_ACCOUNT sms_acct
JOIN SMS.CS_INSTALLMENT inst 
    ON inst.ID = sms_acct.INSTALLMENT_ID
WHERE inv.ABYS_ACCOUNT_ID = sms_acct.ID
  AND sms_acct.INSTALLMENT_ID IS NOT NULL
  AND (
    UPPER(ISNULL(inv.EXPLAIN,'')) NOT LIKE '%TAKSIT%'
  );
```

### Sorun 3: SMS'te Taksit Var Ama ENERGY'ye Migre Olmamış

**Belirti:**
```
SORGU 8 DURUM: SMS_TAKSIT_ENERGY_YOK
SMS'te INSTALLMENT_ID dolu
ENERGY'de ABYS_ACCOUNT_ID ile eşleşen fatura yok
```

**Kök Neden:**
- Bu hesaplar henüz ENERGY'ye migre edilmemiş
- Migrasyon kapsamı dışında bırakılmış olabilir (MIG_IN_SCOPE=0)

**Çözüm:**
```sql
-- Migre edilmemiş taksitli hesapları listele
SELECT 
    a.ID AS ACCOUNT_ID,
    a.AGREEMENT_ID,
    a.INSTALLMENT_ID,
    inst.SEQUENCE_NUMBER,
    inst.TOTAL_INSTALLMENTS,
    SUM(ai.AMOUNT * ai.STATUS) AS BALANCE
FROM SMS.CS_ACCOUNT a
JOIN SMS.CS_INSTALLMENT inst 
    ON inst.ID = a.INSTALLMENT_ID
JOIN CS_ACCOUNT_ACTION aa ON aa.ACCOUNT_ID = a.ID
JOIN CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = aa.ID
WHERE a.AGREEMENT_ID IN (31986, 33228, 33229, 33230)
  AND a.INSTALLMENT_ID IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 
    FROM ENERGY.LS_XXX_XXXX_INVOICE inv
    WHERE inv.ABYS_ACCOUNT_ID = a.ID
  )
GROUP BY a.ID, a.AGREEMENT_ID, a.INSTALLMENT_ID, 
         inst.SEQUENCE_NUMBER, inst.TOTAL_INSTALLMENTS
HAVING SUM(ai.AMOUNT * ai.STATUS) > 0.01
ORDER BY a.AGREEMENT_ID, inst.SEQUENCE_NUMBER;

-- Bu hesapları migre et veya neden migre edilmediğini araştır
```

### Sorun 4: Taksitler Kapalı (Balance = 0)

**Belirti:**
```
SORGU 4: TAKSITLI_HESAP=5, ACIK_TAKSIT=0, KAPALI_TAKSIT=5
```

**Kök Neden:**
- Taksitler ödenmiş, bakiye sıfır
- Bu **normal bir durumdur**, hata değil

**Aksiyon:**
```
✓ Wizard'ın taksit tespiti boş dönecek
✓ Bu beklenen davranış
✓ Kapalı taksitleri tespit etmeye gerek yok
```

**İsteğe Bağlı: Kapalı Taksitleri de Göster**
```sql
-- LoadTaksitAsync'te BALANCE kontrolünü kaldır
-- VEYA kapalı taksitler için ayrı query

SELECT 
    a.ID AS FATURAID,
    a.AGREEMENT_ID AS SOZLESME,
    a.INSTALLMENT_ID,
    ROUND(NVL(bal.TUT, 0), 2) AS BALANCE,
    inst.SEQUENCE_NUMBER,
    inst.TOTAL_INSTALLMENTS,
    CASE 
        WHEN NVL(bal.TUT, 0) > 0.01 THEN 'ACIK'
        ELSE 'KAPALI'
    END AS DURUM
FROM SMS.CS_ACCOUNT a
JOIN SMS.CS_INSTALLMENT inst ON inst.ID = a.INSTALLMENT_ID
LEFT JOIN (
    SELECT aa.ACCOUNT_ID, SUM(ai.STATUS * ai.AMOUNT) AS TUT
    FROM CS_ACCOUNT_ACTION aa
    JOIN CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = aa.ID
    GROUP BY aa.ACCOUNT_ID
) bal ON bal.ACCOUNT_ID = a.ID
WHERE a.AGREEMENT_ID = :agrId
  AND a.INSTALLMENT_ID IS NOT NULL
ORDER BY inst.SEQUENCE_NUMBER;
```

## Gelişmiş Tespit: CS_INSTALLMENT Detayı

Faz2'de `LS_TAKSIT` CTAS'ı oluşturulabilir:

```sql
CREATE TABLE MIG_XXX.LS_TAKSIT AS
SELECT 
    inst.ID AS INSTALLMENT_ID,
    inst.AGREEMENT_ID,
    inst.SEQUENCE_NUMBER AS TAKSIT_NO,
    inst.TOTAL_INSTALLMENTS AS TOPLAM_TAKSIT,
    inst.AMOUNT AS TAKSIT_TUTARI,
    inst.CREATE_DATE AS TAKSIT_TARIHI,
    COUNT(a.ID) AS HESAP_SAYISI,
    SUM(CASE 
        WHEN bal.TUT > 0.01 THEN 1 
        ELSE 0 
    END) AS ACIK_HESAP_SAYISI,
    SUM(COALESCE(bal.TUT, 0)) AS TOPLAM_BAKIYE
FROM SMS.CS_INSTALLMENT inst
LEFT JOIN SMS.CS_ACCOUNT a 
    ON a.INSTALLMENT_ID = inst.ID
LEFT JOIN (
    SELECT aa.ACCOUNT_ID, SUM(ai.STATUS * ai.AMOUNT) AS TUT
    FROM CS_ACCOUNT_ACTION aa
    JOIN CS_ACCOUNT_INCOME ai ON ai.ACCOUNT_ACTION_ID = aa.ID
    GROUP BY aa.ACCOUNT_ID
) bal ON bal.ACCOUNT_ID = a.ID
GROUP BY 
    inst.ID, inst.AGREEMENT_ID, inst.SEQUENCE_NUMBER, 
    inst.TOTAL_INSTALLMENTS, inst.AMOUNT, inst.CREATE_DATE;
```

## Wizard Enhancements (Öneriler)

### 1. Detaylı Gap Raporlama

```csharp
// AgreementSmsReadService.LoadTaksitAsync() içinde
if (rows.Count == 0)
{
    // Neden taksit yok diye araştır
    var allAccounts = await QueryAsync(conn, $@"
        SELECT COUNT(*) AS CNT
        FROM {sms}.CS_ACCOUNT
        WHERE AGREEMENT_ID = :agrId
          AND INSTALLMENT_ID IS NOT NULL", agrId, ct);
    
    var closedCount = Scalar<int>(allAccounts.FirstOrDefault(), "CNT");
    
    if (closedCount > 0)
    {
        gaps.Add(new TahsilatGapItem
        {
            Code = "TAKSIT_ALL_CLOSED",
            Severity = "INFO",
            Side = "SMS",
            Message = $"{closedCount} taksitli hesap var ama tümü kapalı (BALANCE≈0)."
        });
    }
    else
    {
        gaps.Add(new TahsilatGapItem
        {
            Code = "NO_TAKSIT",
            Severity = "INFO",
            Side = "SMS",
            Message = "Sözleşmede taksitli hesap yok."
        });
    }
}
```

### 2. ENERGY Karşılaştırma

```csharp
// AgreementTahsilatOrchestrator.ScenarioAsync() içinde
// SMS ve ENERGY satırlarını karşılaştır

var smsIds = smsRows.Select(r => Scalar<long>(r, "FATURAID")).ToHashSet();
var energyIds = enRows.Select(r => Scalar<long>(r, "ABYS_ACCOUNT_ID")).ToHashSet();

var onlySms = smsIds.Except(energyIds).Count();
var onlyEnergy = energyIds.Except(smsIds).Count();

if (onlySms > 0)
    result.Gaps.Add(new TahsilatGapItem
    {
        Code = "TAKSIT_ONLY_SMS",
        Severity = "WARN",
        Side = "BOTH",
        Message = $"{onlySms} taksit SMS'te var ama ENERGY'de tespit edilmedi (INST_NR/EXPLAIN eksik olabilir)."
    });

if (onlyEnergy > 0)
    result.Gaps.Add(new TahsilatGapItem
    {
        Code = "TAKSIT_ONLY_ENERGY",
        Severity = "INFO",
        Side = "BOTH",
        Message = $"{onlyEnergy} ENERGY'de taksit tespit edildi ama SMS AFL'de yok (kapalı olabilir)."
    });
```

## Kontrol Listesi

### Migrasyon Öncesi
- [ ] LS_AFL_OPEN_DEBT CTAS var mı?
- [ ] LS_AFL_OPEN_DEBT.TAKSIT_DURUMU doğru set edilmiş mi?
- [ ] SMS'te INSTALLMENT_ID dolu hesaplar tespit ediliyor mu?
- [ ] Wizard adım 10 SMS tarafı boş dönüyor mu? → Neden?

### Migrasyon Sonrası
- [ ] ENERGY PAYTRANS.INST_NR set edilmiş mi?
- [ ] ENERGY INVOICE.EXPLAIN'de "TAKSIT" ifadesi var mı?
- [ ] Wizard adım 10 ENERGY tarafı boş dönüyor mu? → Neden?
- [ ] SMS ve ENERGY sayıları eşleşiyor mu?

### Sorun Giderme
1. `TAKSIT_DIAGNOSTIC.sql` SORGU 4 ve 7'yi çalıştır
2. ACIK_TAKSIT ve TAKSIT_TESPIT sayılarını karşılaştır
3. Uyuşmazlık varsa SORGU 8'i çalıştır
4. DURUM analizine göre Sorun 1-4'ten birini uygula

## Özet

| Taraf | Tespit Kaynağı | Kritik Alan |
|-------|----------------|-------------|
| SMS | LS_AFL_OPEN_DEBT | `TAKSIT_DURUMU='T'` |
| SMS Fallback | CS_ACCOUNT | `INSTALLMENT_ID IS NOT NULL` |
| ENERGY | INVOICE+PAYTRANS | `EXPLAIN LIKE '%TAKSIT%'` OR `INST_NR>0` |

**En Yaygın Sorun:** ENERGY'de INST_NR=NULL ve EXPLAIN'de "TAKSIT" yok
**Çözüm:** Migrasyon sırasında INST_NR ve EXPLAIN'i doğru set et
