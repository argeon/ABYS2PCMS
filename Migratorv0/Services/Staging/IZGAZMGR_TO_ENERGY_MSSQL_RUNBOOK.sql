-- =============================================================================
-- izgazMGR → ENERGY (MSSQL → MSSQL) — Ana aktarım runbook
--
-- Kaynak : izgazMGR.dbo.LS_INVOICE / LS_INVLINES / (debt PT energy'de türetilir)
-- Hedef  : energy.dbo.LS_005_01_INVOICE / INVLINES / PAYTRANS
-- LREF   : INT (1..2147483647) = ABYS_ACTION_ID (IDENTITY_INSERT)
--
-- Onkoşul:
--   1) MIGRATOR: Oracle CTAS → izgazMGR dump tamam
--   2) ENERGY: 570/574/580 setup + 00_pre_indexes + 00_abys_columns + 01_linenr
--   3) Deploy: 571_INVOICE__migrate.sql, 581_INVLINES__migrate.sql,
--              575_INVOICE_DEBT_PAYTRANS__migrate.sql
--
-- Çalıştırma sırası (bu dosya):
--   A) Preflight (LREF INT + sayım)
--   B) Pilot (@AGR_ID dolu) — 571 → 581 → 575
--   C) Full (@AGR_ID NULL) — 571 → 581 → 575
--   D) Check (573 / 577 + satır uçları)
-- =============================================================================

USE energy;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- =============================================================================
-- A) PREFLIGHT — LREF INT + kaynak uçları
-- =============================================================================
PRINT '========== A) PREFLIGHT ==========';

-- A1. Kaynak LREF / ABYS_ACTION_ID INT dışı mı?
SELECT
    'LS_INVOICE' AS TBL,
    COUNT_BIG(*) AS SRC_ROWS,
    MIN(ABYS_ACTION_ID) AS MIN_KEY,
    MAX(ABYS_ACTION_ID) AS MAX_KEY,
    SUM(CASE WHEN ABYS_ACTION_ID IS NULL OR ABYS_ACTION_ID < 1 OR ABYS_ACTION_ID > 2147483647 THEN 1 ELSE 0 END) AS BAD_INT,
    SUM(CASE WHEN ABYS_ACTION_ID > 1500000000 THEN 1 ELSE 0 END) AS NEAR_INT_LIMIT
FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK);

SELECT
    'LS_INVLINES' AS TBL,
    COUNT_BIG(*) AS SRC_ROWS,
    MIN(LREF) AS MIN_KEY,
    MAX(LREF) AS MAX_KEY,
    SUM(CASE WHEN LREF IS NULL OR LREF < 1 OR LREF > 2147483647 THEN 1 ELSE 0 END) AS BAD_INT
FROM izgazMGR.dbo.LS_INVLINES WITH (NOLOCK);

-- BAD_INT > 0 ise DUR — INT taşması / NULL key var, aktarım başlamasın.

-- A2. Duplicate ABYS_ACTION_ID (INVOICE PK riski)
SELECT TOP 20 ABYS_ACTION_ID, COUNT(*) AS CNT
FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
GROUP BY ABYS_ACTION_ID
HAVING COUNT(*) > 1
ORDER BY CNT DESC;
-- Satır dönüyorsa DUR — 571 PK patlar.

-- A3. Kaynak index (581 KEYSET için LREF index şart)
IF OBJECT_ID('dbo.SP_MIG_INVLINES_CHECK_PERF', 'P') IS NOT NULL
    EXEC dbo.SP_MIG_INVLINES_CHECK_PERF @RangeMode = 'KEYSET', @RaiseOnBlocking = 0, @DEBUG = 1;

-- A4. Hedef boş / mevcut satır (resume bilinci)
SELECT
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)) AS EN_INV,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_INVLINES WITH (NOLOCK)) AS EN_LINES,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK) WHERE IOCODE = 0) AS EN_DEBT_PT;

PRINT 'Preflight bitti. BAD_INT=0 ve duplicate yoksa B veya C ile devam.';
GO

-- =============================================================================
-- B) PILOT — tek sözleşme (örnek: 31986)
-- =============================================================================
/*
PRINT '========== B) PILOT ==========';

DECLARE @PILOT_AGR BIGINT = 31986;  -- örnek; değiştirin

-- B1. INVOICE
EXEC dbo.SP_MIGRATE_LS005_INVOICE
    @BATCH_SIZE = 50000,
    @AGR_ID     = @PILOT_AGR,
    @RESUME     = 0,
    @HARD_RESET = 0,
    @DEBUG      = 1;

-- B2. INVLINES — SP'de @AGR_ID YOK; pilot sonrası sadece o AGR'nin faturalarına bağlı
--    satırlar anlamlı (INVOICE yoksa orphan riski). Full'de 571 bitmeden 581 başlatma.
--    Pilot için: 571 sonrası 581'i küçük batch + RESUME ile çalıştırıp AGR spot ile doğrula,
--    veya full'e geçmeden önce sadece check sorgularını kullan.
EXEC dbo.SP_MIGRATE_LS005_INVLINES
    @BATCH_SIZE      = 100000,
    @RESUME          = 0,
    @RANGE_MODE      = 'KEYSET',
    @SKIP_PERF_CHECK = 0,
    @DEBUG           = 1;

-- B3. Borç PAYTRANS (energy INVOICE'dan türetilir — Oracle CTAS değil)
EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
    @BATCH_SIZE = 50000,
    @AGR_ID     = @PILOT_AGR,
    @RESUME     = 0,
    @DEBUG      = 1;

-- B4. Pilot spot
SELECT TOP 50
    inv.LREF, inv.ABYS_ID, inv.ABYS_ACCOUNT_ID, inv.ABYS_AGREEMENT_ID,
    inv.PAYABLETOTAL, inv.CLOSED, inv.CANCELED,
    CASE WHEN inv.LREF = inv.ABYS_ID THEN 1 ELSE 0 END AS LREF_EQ_ABYS
FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
WHERE inv.ABYS_AGREEMENT_ID = @PILOT_AGR
ORDER BY inv.LREF;

SELECT
    (SELECT COUNT(*) FROM energy.dbo.LS_005_01_INVOICE WHERE ABYS_AGREEMENT_ID = @PILOT_AGR) AS INV,
    (SELECT COUNT(*) FROM energy.dbo.LS_005_01_INVLINES il
      INNER JOIN energy.dbo.LS_005_01_INVOICE inv ON inv.LREF = il.INVOICEREF
     WHERE inv.ABYS_AGREEMENT_ID = @PILOT_AGR) AS LINES,
    (SELECT COUNT(*) FROM energy.dbo.LS_005_01_PAYTRANS pt
      INNER JOIN energy.dbo.LS_005_01_INVOICE inv ON inv.LREF = pt.INVOICEREF
     WHERE inv.ABYS_AGREEMENT_ID = @PILOT_AGR AND ISNULL(pt.IOCODE,0)=0) AS DEBT_PT;
*/

-- =============================================================================
-- C) FULL LOAD — tüm veri (@AGR_ID NULL)
-- =============================================================================
/*
PRINT '========== C) FULL LOAD ==========';
PRINT 'Sıra zorunlu: 571 → 581 → 575. Araya overlay (590/597) sokma.';

-- C1. INVOICE (~75M) — batch 50K, LREF=ABYS_ACTION_ID INT
EXEC dbo.SP_MIGRATE_LS005_INVOICE
    @BATCH_SIZE  = 50000,
    @AGR_ID      = NULL,
    @RESUME      = 0,      -- kesilirse 1 yapın
    @HARD_RESET  = 0,      -- dikkat: 1 = hedef temizler
    @DEBUG       = 1;

-- C1b. Post (index rebuild vb.)
-- :r 572_INVOICE__post.sql

-- C2. INVLINES (~350M) — kaynak LREF index şart; BULK_LOGGED önerilir
EXEC dbo.SP_MIGRATE_LS005_INVLINES
    @BATCH_SIZE  = 100000,   -- index + BULK_LOGGED sonrası 250000–500000 deneyin
    @RESUME      = 0,
    @DEBUG       = 1;

-- C2b. Post
-- :r 582_INVLINES__post.sql

-- C3. Borç PAYTRANS — energy INVOICE'dan (izgazMGR LS_DEBT_PAYTRANS dump zorunlu değil)
EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
    @BATCH_SIZE  = 50000,
    @AGR_ID      = NULL,
    @RESUME      = 0,
    @DEBUG       = 1;

-- C3b. Post
-- :r 576_INVOICE_DEBT_PAYTRANS__post.sql
*/

-- =============================================================================
-- D) VALIDATION — satır uçları + mevcut check scriptleri
-- =============================================================================
PRINT '========== D) VALIDATION ==========';

-- D1. Satır uçları (izgazMGR vs ENERGY)
SELECT
    'INVOICE' AS LAYER,
    (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
      WHERE ABYS_ACTION_ID BETWEEN 1 AND 2147483647) AS SRC,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
      WHERE ABYS_ID IS NOT NULL) AS TGT,
    (SELECT MIN(ABYS_ACTION_ID) FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
      WHERE ABYS_ACTION_ID BETWEEN 1 AND 2147483647) AS SRC_MIN,
    (SELECT MAX(ABYS_ACTION_ID) FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
      WHERE ABYS_ACTION_ID BETWEEN 1 AND 2147483647) AS SRC_MAX,
    (SELECT MIN(LREF) FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK) WHERE ABYS_ID IS NOT NULL) AS TGT_MIN,
    (SELECT MAX(LREF) FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK) WHERE ABYS_ID IS NOT NULL) AS TGT_MAX;

SELECT
    'INVLINES' AS LAYER,
    (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_INVLINES WITH (NOLOCK)
      WHERE LREF BETWEEN 1 AND 2147483647) AS SRC,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_INVLINES WITH (NOLOCK)
      WHERE ABYS_ID IS NOT NULL) AS TGT,
    (SELECT MIN(LREF) FROM izgazMGR.dbo.LS_INVLINES WITH (NOLOCK)
      WHERE LREF BETWEEN 1 AND 2147483647) AS SRC_MIN,
    (SELECT MAX(LREF) FROM izgazMGR.dbo.LS_INVLINES WITH (NOLOCK)
      WHERE LREF BETWEEN 1 AND 2147483647) AS SRC_MAX;

-- D2. LREF = ABYS_ID (INVOICE kuralı)
SELECT COUNT_BIG(*) AS LREF_NE_ABYS_ID
FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
WHERE ABYS_ID IS NOT NULL AND LREF <> ABYS_ID;
-- 0 olmalı

-- D3. Orphan INVLINES
SELECT COUNT_BIG(*) AS ORPHAN_LINES
FROM energy.dbo.LS_005_01_INVLINES il WITH (NOLOCK)
WHERE NOT EXISTS (
    SELECT 1 FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    WHERE inv.LREF = il.INVOICEREF
);
-- 0 olmalı

-- D4. Orphan borç PT
SELECT COUNT_BIG(*) AS ORPHAN_DEBT_PT
FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
WHERE ISNULL(pt.IOCODE, 0) = 0
  AND NOT EXISTS (
    SELECT 1 FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    WHERE inv.LREF = pt.INVOICEREF
);
-- 0 olmalı

-- D5. Detay check scriptleri (manuel):
--   :r ProdIzgazMgr2Energy/prodENERGY/573_INVOICE__check.sql
--   :r ProdIzgazMgr2Energy/prodENERGY/577_INVOICE_DEBT_PAYTRANS__check.sql
--   EXEC SP_MIG_LOG_STATUS;

PRINT '========== RUNBOOK END ==========';
PRINT 'Sonraki: 590 eksilten overlay → 597 tahsilat overlay → AFL FRK → 613 ops';
GO
