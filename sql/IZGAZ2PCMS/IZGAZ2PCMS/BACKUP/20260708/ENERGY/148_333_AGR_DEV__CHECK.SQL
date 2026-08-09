/* ============================================================
   SCRIPT_ID : AGR_DEV_CHECK
   SCRIPT_NO : 333
   FILE      : 333_AGR_DEV__check.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LS_005_01_AGR_DEV_TR — kontrol sorgulari
-- Kaynak: izgazMGR.dbo.LS_AGR_DEVICE
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- PRE-FLIGHT (migrate oncesi — izgazMGR staging)
-- ------------------------------------------------------------
IF OBJECT_ID('izgazMGR.dbo.LS_AGR_DEVICE', 'U') IS NOT NULL
BEGIN
    SELECT 'PRE: ADDUSER ABYS orphan -> LS_USER' AS RELATION_NAME, COUNT(DISTINCT s.ADDUSER) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_AGR_DEVICE s
    WHERE s.ADDUSER IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_USER u WHERE u.ABYS_ID = s.ADDUSER
      );

    SELECT 'PRE: UPDUSER ABYS orphan -> LS_USER' AS RELATION_NAME, COUNT(DISTINCT s.UPDUSER) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_AGR_DEVICE s
    WHERE s.UPDUSER IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_USER u WHERE u.ABYS_ID = s.UPDUSER
      );

    SELECT 'PRE: DEVID=-99 (map disi)' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_AGR_DEVICE s
    WHERE TRY_CAST(s.DEVID AS INT) = -99;

    SELECT 'PRE: DEVID orphan -> LS_DEVICE' AS RELATION_NAME, COUNT(DISTINCT s.DEVID) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_AGR_DEVICE s
    WHERE s.DEVID IS NOT NULL
      AND TRY_CAST(s.DEVID AS INT) <> -99
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_DEVICE d WHERE d.LREF = TRY_CAST(s.DEVID AS INT)
      );
END
ELSE
    SELECT 'izgazMGR.dbo.LS_AGR_DEVICE yok — pre-flight atlandi' AS UYARI;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_AGR_DEV_TR', 'U') IS NULL
BEGIN
    SELECT 'LS_005_01_AGR_DEV_TR tablosu yok' AS UYARI;
    RETURN;
END
GO

-- ------------------------------------------------------------
-- POST-FLIGHT (hedef)
-- ------------------------------------------------------------
SELECT 'LS_005_01_AGR_DEV_TR toplam' AS METRIK, COUNT(*) AS DEGER
FROM energy.dbo.LS_005_01_AGR_DEV_TR
UNION ALL
SELECT 'ABYS migrate satirlari', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_DEV_TR
WHERE ABYS_MIG_ROW_ID IS NOT NULL
UNION ALL
SELECT 'AGRID NULL (agreement var)', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_DEV_TR
WHERE ABYS_AGREEMENT_ID IS NOT NULL AND AGRID IS NULL
UNION ALL
SELECT 'AGRID wired', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_DEV_TR
WHERE AGRID IS NOT NULL
UNION ALL
SELECT 'DEVID=-99', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_DEV_TR
WHERE DEVID = -99;
GO

-- AGRID orphan (AGR tablosu varsa)
IF OBJECT_ID('energy.dbo.LS_005_01_AGR', 'U') IS NOT NULL
BEGIN
    SELECT 'AGRID -> LS_005_01_AGR' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_DEV_TR d
    WHERE d.AGRID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_01_AGR a WHERE a.ABYS_ID = d.AGRID
      );

    SELECT 'ABYS agreement AGR tablosunda yok' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_DEV_TR d
    WHERE d.ABYS_AGREEMENT_ID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_01_AGR a
          WHERE a.ABYS_ID = d.ABYS_AGREEMENT_ID
             OR a.LREF = d.ABYS_AGREEMENT_ID
      );
END
GO

-- DEVID orphan
IF OBJECT_ID('energy.dbo.LS_DEVICE', 'U') IS NOT NULL
BEGIN
    SELECT 'DEVID -> LS_DEVICE' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_DEV_TR d
    WHERE d.DEVID IS NOT NULL
      AND d.DEVID <> -99
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_DEVICE ld WHERE ld.LREF = d.DEVID
      );
END
GO

-- ADDUSER/UPDUSER orphan (insert: USERID = ABYS_ID + 10000)
IF OBJECT_ID('energy.dbo.LS_USER', 'U') IS NOT NULL
BEGIN
    SELECT 'ADDUSER orphan (USERID)' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_DEV_TR d
    WHERE d.ADDUSER IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_USER u
          WHERE u.USERID = d.ADDUSER
      );

    SELECT 'UPDUSER orphan (USERID)' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_DEV_TR d
    WHERE d.UPDUSER IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_USER u
          WHERE u.USERID = d.UPDUSER
      );
END
GO

EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY @MigrationCode = 'LS_005_01_AGR_DEV_TR';
GO

