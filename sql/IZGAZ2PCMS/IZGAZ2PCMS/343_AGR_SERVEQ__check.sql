/* ============================================================
   SCRIPT_ID : AGR_SERVEQ_CHECK
   SCRIPT_NO : 343
   FILE      : 343_AGR_SERVEQ__check.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LS_005_01_AGR_SERVEQ_TR — kontrol sorgulari
-- Kaynak: izgazMGR.dbo.LS_AGR_SERVQ
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- PRE-FLIGHT (migrate oncesi — izgazMGR staging)
-- ------------------------------------------------------------
IF OBJECT_ID('izgazMGR.dbo.LS_AGR_SERVQ', 'U') IS NOT NULL
BEGIN
    SELECT 'PRE: kaynak toplam' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_AGR_SERVQ;

    SELECT 'PRE: AGRID NULL' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_AGR_SERVQ
    WHERE AGRID IS NULL;

    SELECT 'PRE: MID orphan -> LS_005_ITEMS' AS RELATION_NAME, COUNT(DISTINCT s.MID) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_AGR_SERVQ s
    WHERE s.MID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_ITEMS i
          WHERE i.ABYS_METER_ID = TRY_CAST(s.MID AS BIGINT)
             OR i.LREF = TRY_CAST(s.MID AS INT)
      );

    SELECT 'PRE: MIDOLD orphan -> LS_005_ITEMS' AS RELATION_NAME, COUNT(DISTINCT s.MIDOLD) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_AGR_SERVQ s
    WHERE s.MIDOLD IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_ITEMS i
          WHERE i.ABYS_METER_ID = TRY_CAST(s.MIDOLD AS BIGINT)
             OR i.LREF = TRY_CAST(s.MIDOLD AS INT)
      );

    SELECT 'PRE: LASTENDEX > INT max (ROUND sonrasi)' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_AGR_SERVQ s
    WHERE s.LASTENDEX IS NOT NULL
      AND (
          ROUND(TRY_CAST(s.LASTENDEX AS FLOAT), 0) > 2147483647
          OR ROUND(TRY_CAST(s.LASTENDEX AS FLOAT), 0) < -2147483648
      );
END
ELSE
    SELECT 'izgazMGR.dbo.LS_AGR_SERVQ yok — pre-flight atlandi' AS UYARI;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_AGR_SERVEQ_TR', 'U') IS NULL
BEGIN
    SELECT 'LS_005_01_AGR_SERVEQ_TR tablosu yok' AS UYARI;
    RETURN;
END
GO

-- ------------------------------------------------------------
-- POST-FLIGHT (hedef)
-- ------------------------------------------------------------
SELECT 'LS_005_01_AGR_SERVEQ_TR toplam' AS METRIK, COUNT(*) AS DEGER
FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR
UNION ALL
SELECT 'ABYS migrate satirlari', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR
WHERE ABYS_MIG_ROW_ID IS NOT NULL
UNION ALL
SELECT 'AGRID NULL (agreement var)', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR
WHERE ABYS_AGREEMENT_ID IS NOT NULL AND AGRID IS NULL
UNION ALL
SELECT 'AGRID wired', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR
WHERE AGRID IS NOT NULL
UNION ALL
SELECT 'MID NULL', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR
WHERE ABYS_MIG_ROW_ID IS NOT NULL AND MID IS NULL;
GO

-- AGRID orphan (AGR tablosu varsa)
IF OBJECT_ID('energy.dbo.LS_005_01_AGR', 'U') IS NOT NULL
BEGIN
    SELECT 'AGRID -> LS_005_01_AGR' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR d
    WHERE d.AGRID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_01_AGR a WHERE a.LREF = d.AGRID
      );

    SELECT 'ABYS agreement AGR tablosunda yok' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR d
    WHERE d.ABYS_AGREEMENT_ID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_01_AGR a
          WHERE a.ABYS_ID = d.ABYS_AGREEMENT_ID
             OR a.LREF = d.ABYS_AGREEMENT_ID
      );
END
GO

-- MID orphan
IF OBJECT_ID('energy.dbo.LS_005_ITEMS', 'U') IS NOT NULL
BEGIN
    SELECT 'MID -> LS_005_ITEMS' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR d
    WHERE d.MID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_ITEMS i WHERE i.LREF = d.MID
      );

    SELECT 'MIDOLD -> LS_005_ITEMS' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_SERVEQ_TR d
    WHERE d.MIDOLD IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_ITEMS i WHERE i.LREF = d.MIDOLD
      );
END
GO

EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY @MigrationCode = 'LS_005_01_AGR_SERVEQ_TR';
GO

