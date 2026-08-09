-- TAKSİT TESPİT DİAGNOSTİK SORGUSU
-- Kullanım: Aşağıdaki sorgular sırayla çalıştırılmalı

-- =============================================================================
-- SMS TARAFINDA TAKSİT TESPİTİ
-- =============================================================================

-- SORGU 1: LS_AFL_OPEN_DEBT varsa (öncelikli)
-- -------------------------
SELECT 
    A.FATURAID,
    A.SOZLESME_HESABI AS SOZLESME,
    A.BALANCE,
    A.TAKSIT_DURUMU,
    A.INSTALLMENT_ID,
    A.YT_DURUMU,
    A.ACCRUE_TYPE_ID
FROM MIG_IZGAZPR.LS_AFL_OPEN_DEBT A
WHERE A.SOZLESME_HESABI IN (31986, 33228, 33229, 33230)
  AND A.TAKSIT_DURUMU = 'T'
ORDER BY A.SOZLESME_HESABI, A.FATURAID;

-- BEKLENEN: TAKSIT_DURUMU='T' olan kayıtlar
-- YOKSA → SORGU 2'ye geç


-- SORGU 2: CS_ACCOUNT fallback (LS_AFL yok veya boşsa)
-- -------------------------
SELECT 
    a.ID AS FATURAID,
    a.AGREEMENT_ID AS SOZLESME,
    a.INSTALLMENT_ID,
    ROUND(NVL(bal.TUT, 0), 2) AS BALANCE,
    a.ACCRUE_TYPE_ID,
    a.CREATE_DATE,
    a.TOTAL_DEBT,
    a.TOTAL_CREDIT
FROM IZGAZSMS.CS_ACCOUNT a
LEFT JOIN (
    SELECT 
        aa.ACCOUNT_ID, 
        SUM(ai.STATUS * ai.AMOUNT) AS TUT
    FROM IZGAZSMS.CS_ACCOUNT_ACTION aa
    JOIN IZGAZSMS.CS_ACCOUNT_INCOME ai 
      ON ai.ACCOUNT_ACTION_ID = aa.ID
    GROUP BY aa.ACCOUNT_ID
) bal ON bal.ACCOUNT_ID = a.ID
WHERE a.AGREEMENT_ID IN (31986, 33228, 33229, 33230)
  AND a.INSTALLMENT_ID IS NOT NULL
  AND NVL(bal.TUT, 0) > 0.01
ORDER BY a.AGREEMENT_ID, a.ID;

-- BEKLENEN: INSTALLMENT_ID dolu ve BALANCE>0 olan hesaplar
-- YOKSA → Bu sözleşmelerde taksitli hesap yok veya kapalı


-- SORGU 3: Tüm hesapları göster (taksit durumuna bakmaksızın)
-- -------------------------
SELECT 
    a.ID AS FATURAID,
    a.AGREEMENT_ID AS SOZLESME,
    a.INSTALLMENT_ID,
    ROUND(NVL(bal.TUT, 0), 2) AS BALANCE,
    a.ACCRUE_TYPE_ID,
    a.CREATE_DATE,
    CASE 
        WHEN a.INSTALLMENT_ID IS NULL THEN 'TEK_CEKIMLI'
        ELSE 'TAKSITLI'
    END AS TAKSIT_TIPI,
    CASE 
        WHEN NVL(bal.TUT, 0) > 0.01 THEN 'ACIK'
        WHEN NVL(bal.TUT, 0) < -0.01 THEN 'FAZLA_ÖDEME'
        ELSE 'KAPALI'
    END AS DURUM
FROM IZGAZSMS.CS_ACCOUNT a
LEFT JOIN (
    SELECT 
        aa.ACCOUNT_ID, 
        SUM(ai.STATUS * ai.AMOUNT) AS TUT
    FROM IZGAZSMS.CS_ACCOUNT_ACTION aa
    JOIN IZGAZSMS.CS_ACCOUNT_INCOME ai 
      ON ai.ACCOUNT_ACTION_ID = aa.ID
    GROUP BY aa.ACCOUNT_ID
) bal ON bal.ACCOUNT_ID = a.ID
WHERE a.AGREEMENT_ID IN (31986, 33228, 33229, 33230)
ORDER BY a.AGREEMENT_ID, a.INSTALLMENT_ID NULLS FIRST, a.ID;

-- BEKLENEN: Tüm hesapların listesi
-- TAKSIT_TIPI ve DURUM bazında sayım yapılabilir


-- SORGU 4: Sözleşme bazında taksit özeti
-- -------------------------
SELECT 
    a.AGREEMENT_ID AS SOZLESME,
    COUNT(*) AS TOPLAM_HESAP,
    SUM(CASE WHEN a.INSTALLMENT_ID IS NOT NULL THEN 1 ELSE 0 END) AS TAKSITLI_HESAP,
    SUM(CASE WHEN a.INSTALLMENT_ID IS NOT NULL AND NVL(bal.TUT, 0) > 0.01 THEN 1 ELSE 0 END) AS ACIK_TAKSIT,
    SUM(CASE WHEN a.INSTALLMENT_ID IS NOT NULL AND ABS(NVL(bal.TUT, 0)) <= 0.01 THEN 1 ELSE 0 END) AS KAPALI_TAKSIT,
    SUM(CASE WHEN a.INSTALLMENT_ID IS NULL THEN 1 ELSE 0 END) AS TEK_CEKIMLI_HESAP
FROM IZGAZSMS.CS_ACCOUNT a
LEFT JOIN (
    SELECT 
        aa.ACCOUNT_ID, 
        SUM(ai.STATUS * ai.AMOUNT) AS TUT
    FROM IZGAZSMS.CS_ACCOUNT_ACTION aa
    JOIN IZGAZSMS.CS_ACCOUNT_INCOME ai 
      ON ai.ACCOUNT_ACTION_ID = aa.ID
    GROUP BY aa.ACCOUNT_ID
) bal ON bal.ACCOUNT_ID = a.ID
WHERE a.AGREEMENT_ID IN (31986, 33228, 33229, 33230)
GROUP BY a.AGREEMENT_ID
ORDER BY a.AGREEMENT_ID;

-- BEKLENEN: Sözleşme başına özet
-- ACIK_TAKSIT=0 ise → Tüm taksitler kapalı veya taksit yok


-- =============================================================================
-- ENERGY TARAFINDA TAKSİT TESPİTİ
-- =============================================================================

-- SORGU 5: ENERGY'de taksit tespit (LS_315_0126 örnek prefix)
-- -------------------------
-- NOT: Table prefix'i ortamınıza göre değiştirin (LS_XXX_XXXX)
-- DECLARE @prefix VARCHAR(20) = 'LS_315_0126';  -- MSSQL için

SELECT TOP 300 
    inv.LREF,
    inv.OWNERREF,
    inv.ABYS_ACCOUNT_ID,
    inv.FICHENO,
    LEFT(inv.EXPLAIN, 50) AS EXPLAIN_KISIT,
    inv.CLOSED,
    inv.PAYABLETOTAL,
    pt.LREF AS PT_LREF,
    pt.INST_NR,
    pt.PAYABLETOTAL AS PT_PAYABLE,
    pt.PAID,
    CASE 
        WHEN UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%TAKSIT%' THEN 'EXPLAIN_TAKSIT'
        WHEN ISNULL(pt.INST_NR,0) > 0 THEN 'INST_NR>0'
        ELSE 'TESPITT_YOK'
    END AS TESPIT_TIPI
FROM dbo.LS_315_0126_INVOICE inv WITH (NOLOCK)
LEFT JOIN dbo.LS_315_0126_PAYTRANS pt WITH (NOLOCK)
    ON pt.INVOICEREF = inv.LREF 
   AND ISNULL(pt.CANCELED,0) = 0
WHERE inv.OWNERREF IN (31986, 33228, 33229, 33230)
  AND ISNULL(inv.CANCELED,0) = 0
  AND (
    UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%TAKSIT%'
    OR ISNULL(pt.INST_NR,0) > 0
  )
ORDER BY inv.OWNERREF, inv.LREF DESC;

-- BEKLENEN: Taksit ifadesi veya INST_NR>0 olan faturalar
-- YOKSA → SORGU 6'ya geç


-- SORGU 6: Tüm faturaları göster (taksit filtresi olmadan)
-- -------------------------
SELECT TOP 500
    inv.LREF,
    inv.OWNERREF,
    inv.ABYS_ACCOUNT_ID,
    inv.FICHENO,
    LEFT(inv.EXPLAIN, 50) AS EXPLAIN_KISIT,
    inv.CLOSED,
    inv.PAYABLETOTAL,
    pt.INST_NR,
    CASE 
        WHEN UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%TAKSIT%' THEN 1
        WHEN ISNULL(pt.INST_NR,0) > 0 THEN 1
        ELSE 0
    END AS TAKSIT_VAR_MI
FROM dbo.LS_315_0126_INVOICE inv WITH (NOLOCK)
LEFT JOIN dbo.LS_315_0126_PAYTRANS pt WITH (NOLOCK)
    ON pt.INVOICEREF = inv.LREF 
   AND ISNULL(pt.CANCELED,0) = 0
WHERE inv.OWNERREF IN (31986, 33228, 33229, 33230)
  AND ISNULL(inv.CANCELED,0) = 0
ORDER BY inv.OWNERREF, inv.LREF DESC;

-- BEKLENEN: Tüm faturalar
-- TAKSIT_VAR_MI sütununda 1 olanlar taksit


-- SORGU 7: ENERGY sözleşme bazında özet
-- -------------------------
SELECT 
    inv.OWNERREF AS SOZLESME,
    COUNT(DISTINCT inv.LREF) AS TOPLAM_FATURA,
    SUM(CASE 
        WHEN UPPER(ISNULL(inv.EXPLAIN,'')) LIKE '%TAKSIT%' 
          OR ISNULL(pt.INST_NR,0) > 0 
        THEN 1 ELSE 0 
    END) AS TAKSIT_TESPIT,
    SUM(CASE WHEN inv.CLOSED = 1 THEN 1 ELSE 0 END) AS KAPALI_FATURA,
    SUM(CASE WHEN inv.CLOSED = 0 THEN 1 ELSE 0 END) AS ACIK_FATURA
FROM dbo.LS_315_0126_INVOICE inv WITH (NOLOCK)
LEFT JOIN dbo.LS_315_0126_PAYTRANS pt WITH (NOLOCK)
    ON pt.INVOICEREF = inv.LREF 
   AND ISNULL(pt.CANCELED,0) = 0
WHERE inv.OWNERREF IN (31986, 33228, 33229, 33230)
  AND ISNULL(inv.CANCELED,0) = 0
GROUP BY inv.OWNERREF
ORDER BY inv.OWNERREF;

-- BEKLENEN: TAKSIT_TESPIT=0 ise → ENERGY'de taksit tespit edilemiyor


-- =============================================================================
-- KARŞILAŞTIRMA VE KÖK NEDEN ANALİZİ
-- =============================================================================

-- SORGU 8: SMS ABYS_ACCOUNT_ID ile ENERGY ABYS_ACCOUNT_ID eşleşmesi
-- -------------------------
SELECT 
    a.ID AS SMS_FATURAID,
    a.AGREEMENT_ID AS SOZLESME,
    a.INSTALLMENT_ID AS SMS_INSTALLMENT_ID,
    ROUND(NVL(bal.TUT, 0), 2) AS SMS_BALANCE,
    inv.LREF AS ENERGY_LREF,
    inv.ABYS_ACCOUNT_ID AS ENERGY_ACCOUNT_ID,
    pt.INST_NR AS ENERGY_INST_NR,
    LEFT(inv.EXPLAIN, 50) AS ENERGY_EXPLAIN,
    CASE 
        WHEN a.INSTALLMENT_ID IS NOT NULL AND inv.LREF IS NULL THEN 'SMS_TAKSIT_ENERGY_YOK'
        WHEN a.INSTALLMENT_ID IS NOT NULL AND inv.LREF IS NOT NULL AND ISNULL(pt.INST_NR,0) = 0 
             AND UPPER(ISNULL(inv.EXPLAIN,'')) NOT LIKE '%TAKSIT%' THEN 'ENERGY_TAKSIT_BILGISI_EKSIK'
        WHEN a.INSTALLMENT_ID IS NOT NULL AND inv.LREF IS NOT NULL THEN 'ESLESME_OK'
        ELSE 'DIGER'
    END AS DURUM
FROM IZGAZSMS.CS_ACCOUNT a
LEFT JOIN (
    SELECT 
        aa.ACCOUNT_ID, 
        SUM(ai.STATUS * ai.AMOUNT) AS TUT
    FROM IZGAZSMS.CS_ACCOUNT_ACTION aa
    JOIN IZGAZSMS.CS_ACCOUNT_INCOME ai 
      ON ai.ACCOUNT_ACTION_ID = aa.ID
    GROUP BY aa.ACCOUNT_ID
) bal ON bal.ACCOUNT_ID = a.ID
LEFT JOIN IZGAZ.LS_315_0126_INVOICE inv 
    ON inv.ABYS_ACCOUNT_ID = a.ID 
   AND ISNULL(inv.CANCELED,0) = 0
LEFT JOIN IZGAZ.LS_315_0126_PAYTRANS pt 
    ON pt.INVOICEREF = inv.LREF 
   AND ISNULL(pt.CANCELED,0) = 0
WHERE a.AGREEMENT_ID IN (31986, 33228, 33229, 33230)
  AND a.INSTALLMENT_ID IS NOT NULL
  AND NVL(bal.TUT, 0) > 0.01
ORDER BY a.AGREEMENT_ID, a.ID;

-- BEKLENEN: DURUM analizi
-- - SMS_TAKSIT_ENERGY_YOK: SMS'te taksit var ama ENERGY'ye migre olmamış
-- - ENERGY_TAKSIT_BILGISI_EKSIK: ENERGY'de fatura var ama INST_NR yok ve EXPLAIN'de taksit yok
-- - ESLESME_OK: Her iki tarafta da tespit ediliyor


-- =============================================================================
-- SORUN GİDERME ÖNERİLERİ
-- =============================================================================

/*
KÖK NEDEN ANALİZİ:

1. SMS'te taksit yok veya kapalı
   └─ SORGU 3 ve 4'ü kontrol et
   └─ ACIK_TAKSIT=0 ise tüm taksitler ödenmiş
   └─ ÇÖ

ZÜM: Taksitler zaten kapalı, tespit normal davranış

2. SMS'te taksit var ama LS_AFL_OPEN_DEBT'te TAKSIT_DURUMU='T' değil
   └─ SORGU 1'de kayıt yok ama SORGU 2'de var
   └─ ÇÖZÜM: AFL CTAS'ı güncellenmeliAFL TAKSIT_DURUMU alanı yanlış
   └─ SQL: UPDATE LS_AFL_OPEN_DEBT SET TAKSIT_DURUMU='T' WHERE INSTALLMENT_ID IS NOT NULL

3. ENERGY'de fatura var ama INST_NR=0 ve EXPLAIN'de taksit ifadesi yok
   └─ SORGU 8'de ENERGY_TAKSIT_BILGISI_EKSIK durumu
   └─ ÇÖZÜM: ENERGY'de PAYTRANS.INST_NR veya INVOICE.EXPLAIN güncellenmeli
   └─ Bu migrasyon sonrası düzeltme gerektirir

4. SMS'te taksit var ama ENERGY'ye hiç migre olmamış
   └─ SORGU 8'de SMS_TAKSIT_ENERGY_YOK durumu
   └─ ÇÖZÜM: Migrasyon tamamlanmamış, bu faturalar migre edilmeli

5. LS_AFL_OPEN_DEBT CTAS tablosu yoksa
   └─ Wizard fallback kullanır (CS_ACCOUNT.INSTALLMENT_ID)
   └─ WARN gap üretir: "NO_LS_AFL_FOR_TAKSIT"
   └─ ÇÖZÜM: LS_AFL_OPEN_DEBT CTAS'ını oluştur

AKSIYONLAR:
- Önce SORGU 4 ve 7'yi çalıştır → Sözleşme başına özet
- ACIK_TAKSIT > 0 ve TAKSIT_TESPIT = 0 ise → SORGU 8'i çalıştır
- DURUM analizine göre uygun çözümü uygula
*/
