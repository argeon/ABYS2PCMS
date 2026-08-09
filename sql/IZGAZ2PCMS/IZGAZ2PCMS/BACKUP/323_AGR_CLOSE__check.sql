/* ============================================================
   SCRIPT_ID : AGR_CLOSE_CHECK
   SCRIPT_NO : 323
   FILE      : 323_AGR_CLOSE__check.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LS_005_01_AGR_CLOSE — kontrol sorgulari
-- ============================================================
USE energy;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_AGR_CLOSE', 'U') IS NULL
BEGIN
    SELECT 'LS_005_01_AGR_CLOSE tablosu yok' AS UYARI;
    RETURN;
END
GO

SELECT 'LS_005_01_AGR_CLOSE toplam' AS METRIK, COUNT(*) AS DEGER
FROM energy.dbo.LS_005_01_AGR_CLOSE
UNION ALL
SELECT 'ABYS migrate satirlari', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_CLOSE
WHERE ABYS_ID IS NOT NULL
UNION ALL
SELECT 'AGRID NULL (agreement var)', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_CLOSE
WHERE ABYS_AGREEMENT_ID IS NOT NULL AND AGRID IS NULL
UNION ALL
SELECT 'AGRID wired', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_CLOSE
WHERE AGRID IS NOT NULL
UNION ALL
SELECT 'LREF <> ABYS_ID', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_CLOSE
WHERE ABYS_ID IS NOT NULL AND LREF <> ABYS_ID;
GO

-- AGRID orphan (AGR tablosu varsa)
IF OBJECT_ID('energy.dbo.LS_005_01_AGR', 'U') IS NOT NULL
BEGIN
    SELECT 'AGRID -> LS_005_01_AGR' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_CLOSE c
    WHERE c.AGRID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_01_AGR a WHERE a.LREF = c.AGRID
      );

    SELECT 'ABYS agreement AGR tablosunda yok' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_CLOSE c
    WHERE c.ABYS_AGREEMENT_ID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_01_AGR a
          WHERE a.LREF = c.ABYS_AGREEMENT_ID
      );
END
GO

-- BANKREF orphan
IF OBJECT_ID('energy.dbo.LS_BANK', 'U') IS NOT NULL
BEGIN
    SELECT 'BANKREF -> LS_BANK' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_CLOSE c
    WHERE c.BANKREF IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM energy.dbo.LS_BANK b WHERE b.LREF = c.BANKREF);
END
GO

EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY @MigrationCode = 'LS_005_01_AGR_CLOSE';
GO

