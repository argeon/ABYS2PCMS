-- =====================================================================================
-- ÝZGAZ MIGRATION — VALIDASYON MODÜLÜ  v0.5-val
-- Ön koþul : izgaz_pilot_ctas_v04.sql koþmuþ olmalý (STG_* tablolarý mevcut).
-- Amaç     : (1) MAHSUP/EMANET iþlemlerinin kaynaða karþý SIFIRLANMASINI kanýtlamak,
--            (2) her tahakkuk faturasýnýn (ödemesiz dahil) tam 1 borç PAYTRANS'ý olduðunu,
--            (3) emanet/mahsup çift-taraflý olduðundan kapsam kapanýþý (closure) için
--                MIG_PARAM'a eklenmesi gereken KARÞI sicilleri tespit etmek.
-- Not      : Tutarlar CS_ACCOUNT_INCOME toplamý üzerinden ölçülür (ABS). Yön STATUS'ta.
--            Bu modül YALNIZCA SELECT'tir; staging'i deðiþtirmez. Çýktýlarý yapýþtýr.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- KAPSAM KAPANIÞI (CLOSURE) — emanet/mahsup karþý taraflarý pilot dýþýnda mý?
-- V0. Pilot hesaplarýn REF_DEPOSIT_ACCOUNT_ID ile iþaret ettiði KARÞI hesaplardan
--     pilot kapsamý DIÞINDA olanlarýn register'larý. Bunlarý MIG_PARAM'a ekle ki
--     mahsup çiftleri tam görünsün (istediðin sicille baþla, closure ile tamamla).
-- -------------------------------------------------------------------------------------
SELECT DISTINCT REF.REGISTER_ID          AS EKLENECEK_REGISTER_ID,
       COUNT(*) OVER (PARTITION BY REF.REGISTER_ID) AS KARSI_HESAP_ADEDI
  FROM STG_PILOT_ACC A
  JOIN SMS.CS_ACCOUNT_ACTION X
    ON X.ACCOUNT_ID = A.ID
   AND X.ACTION_TYPE_ID IN (6, 12, 20, 48)          -- mahsup / emanet çýkýþ / giriþ
   AND X.REF_DEPOSIT_ACCOUNT_ID IS NOT NULL
  JOIN SMS.CS_ACCOUNT REF
    ON REF.ID = X.REF_DEPOSIT_ACCOUNT_ID
 WHERE NOT EXISTS (SELECT 1 FROM STG_PILOT_ACC P WHERE P.ID = REF.ID)   -- pilot dýþý
 ORDER BY KARSI_HESAP_ADEDI DESC;
-- >>> Bu liste boþ deðilse: register'larý MIG_PARAM'a ekleyip v04'ü yeniden koþ,
--     sonra bu validasyonu tekrarla. Boþsa emanet zinciri pilot içinde kapalýdýr.

-- -------------------------------------------------------------------------------------
-- BÖLÜM 1 — ACCRUAL PAYTRANS KAPSAMASI ("ödemesiz her tahakkukta da PAYTRANS")
-- -------------------------------------------------------------------------------------

-- V1. Her INVOICE'un tam 1 ACCRUE (borç) PAYTRANS'ý olmalý. (SIFIR satýr beklenir)
SELECT V.LREF, V.INV_KIND,
       (SELECT COUNT(*) FROM STG_PAYTRANS P
         WHERE P.INVOICEREF = V.LREF AND P.PT_KIND = 'ACCRUE') AS ACCRUE_PT_ADET
  FROM STG_INVOICE V
 WHERE (SELECT COUNT(*) FROM STG_PAYTRANS P
         WHERE P.INVOICEREF = V.LREF AND P.PT_KIND = 'ACCRUE') <> 1
 ORDER BY V.LREF;

-- V2. Borç PAYTRANS'ýn türetilmiþ PAID / PAYABLETOTAL / kapanýþ durumu.
--     PAID = bu faturaya CROSSREF'lenen tahsilatlarýn (IOCODE=1) toplamý.
--     ODEMESIZ tahakkuk -> PAID=0 (açýk borç, PCMS'te NEEDPAY). Bu satýrlar da listelenir.
SELECT V.LREF, V.INV_KIND, V.GRANDTOTAL AS PAYABLETOTAL,
       NVL(PAY.PAID, 0)                              AS PAID,
       CASE WHEN NVL(PAY.PAID,0) = 0                    THEN 'ODEMESIZ'
            WHEN NVL(PAY.PAID,0) >= V.GRANDTOTAL - 0.01 THEN 'KAPALI'
            ELSE 'KISMI' END                          AS DURUM
  FROM STG_INVOICE V
  LEFT JOIN (SELECT P.INVOICEREF, SUM(PI.INCOME_AMOUNT) PAID
               FROM STG_PAYTRANS P
               JOIN STG_PAYTRANS_INCOME PI ON PI.PAYTRANSREF = P.LREF
              WHERE P.PT_KIND = 'PAYMENT' AND P.IOCODE = 1
              GROUP BY P.INVOICEREF) PAY ON PAY.INVOICEREF = V.LREF
 WHERE V.CANCELED = 0
 ORDER BY DURUM, V.LREF;

-- V2b. ÖZET: durum daðýlýmý (ODEMESIZ/KISMI/KAPALI sayýlarý — beklenen tabloyla karþýlaþtýr)
SELECT DURUM, COUNT(*) ADET, SUM(PAYABLETOTAL) TOPLAM FROM (
  SELECT V.LREF, V.GRANDTOTAL AS PAYABLETOTAL,
         CASE WHEN NVL(PAY.PAID,0) = 0                    THEN 'ODEMESIZ'
              WHEN NVL(PAY.PAID,0) >= V.GRANDTOTAL - 0.01 THEN 'KAPALI'
              ELSE 'KISMI' END AS DURUM
    FROM STG_INVOICE V
    LEFT JOIN (SELECT P.INVOICEREF, SUM(PI.INCOME_AMOUNT) PAID
                 FROM STG_PAYTRANS P
                 JOIN STG_PAYTRANS_INCOME PI ON PI.PAYTRANSREF = P.LREF
                WHERE P.PT_KIND = 'PAYMENT' AND P.IOCODE = 1
                GROUP BY P.INVOICEREF) PAY ON PAY.INVOICEREF = V.LREF
   WHERE V.CANCELED = 0
) GROUP BY DURUM;

-- -------------------------------------------------------------------------------------
-- BÖLÜM 2 — EMANET SIFIRLAMA (kaynak Oracle vs staging ledger; net denge)
-- -------------------------------------------------------------------------------------

-- V3. KAYNAK vs STAGING toplamlarý (emanet, accrue=14). FARK = 0 olmalý.
--     Hiçbir emanet kuruþu taþýnýrken kaybolmamýþ/mükerrer olmamalý.
WITH ORA AS (
  SELECT SUM(CASE WHEN X.ACTION_TYPE_ID IN (20,48,36,39,44) THEN ABS(I.AMOUNT) ELSE 0 END) GIRIS,
         SUM(CASE WHEN X.ACTION_TYPE_ID IN (12,6,40,29,11)  THEN ABS(I.AMOUNT) ELSE 0 END) CIKIS
    FROM STG_PILOT_ACC A
    JOIN SMS.CS_ACCOUNT_ACTION X ON X.ACCOUNT_ID = A.ID
    JOIN SMS.CS_ACCOUNT_INCOME I ON I.ACCOUNT_ACTION_ID = X.ID
   WHERE A.ACCRUE_TYPE_ID = 14
     AND X.ACTION_TYPE_ID IN (20,48,36,39,44,12,6,40,29,11)
),
STG AS (
  SELECT SUM(CASE WHEN DIRECTION=1 THEN AMOUNT ELSE 0 END) GIRIS,
         SUM(CASE WHEN DIRECTION=2 THEN AMOUNT ELSE 0 END) CIKIS
    FROM STG_ADVANCE_LEDGER
)
SELECT 'GIRIS' KALEM, ORA.GIRIS ORACLE, STG.GIRIS STAGING, ORA.GIRIS-STG.GIRIS FARK FROM ORA,STG
UNION ALL
SELECT 'CIKIS', ORA.CIKIS, STG.CIKIS, ORA.CIKIS-STG.CIKIS FROM ORA,STG;

-- V4. HESAP BAZLI NET: giriþ-çýkýþ = kalan bakiye. NEGATÝF kalan = fazla çýkýþ = HATA.
--     (parentsýz çýkýþ da iþaretlenir — kaynaðý belirsiz çýkýþ.)
SELECT SOURCE_ORACLE_ACCOUNT_ID,
       SUM(CASE WHEN DIRECTION=1 THEN AMOUNT ELSE 0 END) GIRIS,
       SUM(CASE WHEN DIRECTION=2 THEN AMOUNT ELSE 0 END) CIKIS,
       SUM(CASE WHEN DIRECTION=1 THEN AMOUNT ELSE -AMOUNT END) KALAN,
       MAX(CASE WHEN DIRECTION=2 AND PARENT_LREF IS NULL THEN 1 ELSE 0 END) PARENTSIZ_CIKIS
  FROM STG_ADVANCE_LEDGER
 GROUP BY SOURCE_ORACLE_ACCOUNT_ID
HAVING SUM(CASE WHEN DIRECTION=1 THEN AMOUNT ELSE -AMOUNT END) < -0.01
    OR MAX(CASE WHEN DIRECTION=2 AND PARENT_LREF IS NULL THEN 1 ELSE 0 END) = 1
 ORDER BY KALAN;

-- V5. LEDGER income kýrýlýmý = ledger AMOUNT (STG_ADV_LEDGER_INCOME iç tutarlýlýk). FARK=0.
SELECT L.LREF, L.AMOUNT, NVL(GI.AMT,0) INCOME_TOPLAM, L.AMOUNT-NVL(GI.AMT,0) FARK
  FROM STG_ADVANCE_LEDGER L
  LEFT JOIN (SELECT LEDGER_LREF, SUM(AMOUNT) AMT FROM STG_ADV_LEDGER_INCOME GROUP BY LEDGER_LREF) GI
    ON GI.LEDGER_LREF = L.LREF
 WHERE ABS(L.AMOUNT - NVL(GI.AMT,0)) > 0.01;

-- -------------------------------------------------------------------------------------
-- BÖLÜM 3 — MAHSUP ÇÝFT SIFIRLAMA (makbuz bazlý; çýkýþ tutarý = mahsup tutarý)
-- -------------------------------------------------------------------------------------

-- V6. MAKBUZ (RECEIPT_NUMBER) bazýnda: EMANET ÇIKIÞI (12) tutarý = MAHSUP TAHSILATI (6) tutarý.
--     FARK<>0 olan makbuz = sýzdýran/eksik eþleþme. KAPSAM_DISI_TARAF>0 -> karþý hesap
--     pilot dýþýnda (V0 closure ile ekle). Çift tam kapalýysa çýkýþ?mahsup (net sýfýr).
WITH INC AS (
  SELECT ACCOUNT_ACTION_ID, SUM(ABS(AMOUNT)) AMT
    FROM SMS.CS_ACCOUNT_INCOME GROUP BY ACCOUNT_ACTION_ID
),
PILOT_RCPT AS (
  SELECT DISTINCT X.RECEIPT_NUMBER
    FROM STG_PILOT_ACC A
    JOIN SMS.CS_ACCOUNT_ACTION X ON X.ACCOUNT_ID = A.ID
   WHERE X.ACTION_TYPE_ID IN (6,12) AND X.RECEIPT_NUMBER IS NOT NULL
)
SELECT X.RECEIPT_NUMBER,
       SUM(CASE WHEN X.ACTION_TYPE_ID=12 THEN NVL(INC.AMT,0) ELSE 0 END) CIKIS_12,
       SUM(CASE WHEN X.ACTION_TYPE_ID=6  THEN NVL(INC.AMT,0) ELSE 0 END) MAHSUP_6,
       SUM(CASE WHEN X.ACTION_TYPE_ID=12 THEN NVL(INC.AMT,0)
                WHEN X.ACTION_TYPE_ID=6  THEN -NVL(INC.AMT,0) ELSE 0 END) FARK,
       COUNT(DISTINCT X.ACCOUNT_ID) HESAP_SAYISI,
       SUM(CASE WHEN P.ID IS NULL THEN 1 ELSE 0 END) KAPSAM_DISI_TARAF
  FROM SMS.CS_ACCOUNT_ACTION X
  JOIN PILOT_RCPT PR ON PR.RECEIPT_NUMBER = X.RECEIPT_NUMBER
  LEFT JOIN INC ON INC.ACCOUNT_ACTION_ID = X.ID
  LEFT JOIN STG_PILOT_ACC P ON P.ID = X.ACCOUNT_ID
 WHERE X.ACTION_TYPE_ID IN (6,12)
 GROUP BY X.RECEIPT_NUMBER
 ORDER BY ABS(SUM(CASE WHEN X.ACTION_TYPE_ID=12 THEN NVL(INC.AMT,0)
                       WHEN X.ACTION_TYPE_ID=6  THEN -NVL(INC.AMT,0) ELSE 0 END)) DESC;

-- V7. MAHSUP staging kapsamasý: kaynaktaki id=6/id=12 action'larýndan kaçý staging'de
--     (ledger VEYA paytrans) karþýlýk buldu? KAYIP satýr = taþýnmamýþ mahsup ayaðý.
SELECT X.ACTION_TYPE_ID,
       COUNT(*) KAYNAK_ADET,
       SUM(CASE WHEN L.LREF IS NOT NULL THEN 1 ELSE 0 END) LEDGERDA,
       SUM(CASE WHEN PT.LREF IS NOT NULL THEN 1 ELSE 0 END) PAYTRANSTA,
       SUM(CASE WHEN L.LREF IS NULL AND PT.LREF IS NULL THEN 1 ELSE 0 END) KAYIP
  FROM STG_PILOT_ACC A
  JOIN SMS.CS_ACCOUNT_ACTION X ON X.ACCOUNT_ID = A.ID AND X.ACTION_TYPE_ID IN (6,12)
  LEFT JOIN STG_ADVANCE_LEDGER L ON L.SOURCE_ORACLE_ACTION_ID = X.ID
  LEFT JOIN STG_PAYTRANS      PT ON PT.SOURCE_ORACLE_ACTION_ID = X.ID AND PT.PT_KIND='PAYMENT'
 GROUP BY X.ACTION_TYPE_ID;