/* ============================================================
   SCRIPT_ID : AGR_FITMENTFEE_CHECK
   SCRIPT_NO : 353
   FILE      : 353_AGR_FITMENTFEE__check.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LS_005_01_AGR_FITMENTFEE_TR — kontrol sorgulari
-- Kaynak: izgazMGR.dbo.LS_FITMENT_FEE
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- PRE-FLIGHT (migrate oncesi — izgazMGR staging)
-- ------------------------------------------------------------
IF OBJECT_ID('izgazMGR.dbo.LS_FITMENT_FEE', 'U') IS NOT NULL
BEGIN
    SELECT 'PRE: kaynak toplam' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_FITMENT_FEE;

    SELECT 'PRE: AGRID NULL' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_FITMENT_FEE
    WHERE AGRID IS NULL;

    SELECT 'PRE: ABYS_INSTALLATION_ID NULL' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_FITMENT_FEE
    WHERE ABYS_INSTALLATION_ID IS NULL;

    SELECT 'PRE: installation orphan -> LS_FLAT' AS RELATION_NAME,
           COUNT(DISTINCT s.ABYS_INSTALLATION_ID) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_FITMENT_FEE s
    WHERE s.ABYS_INSTALLATION_ID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_FLAT f
          WHERE f.ABYS_INSTALLATION_ID = TRY_CAST(s.ABYS_INSTALLATION_ID AS BIGINT)
            AND f.ENT_ID = 4102
      );
END
ELSE
    SELECT 'izgazMGR.dbo.LS_FITMENT_FEE yok — pre-flight atlandi' AS UYARI;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_AGR_FITMENTFEE_TR', 'U') IS NULL
BEGIN
    SELECT 'LS_005_01_AGR_FITMENTFEE_TR tablosu yok' AS UYARI;
    RETURN;
END
GO

-- ------------------------------------------------------------
-- POST-FLIGHT (hedef)
-- ------------------------------------------------------------
SELECT 'LS_005_01_AGR_FITMENTFEE_TR toplam' AS METRIK, COUNT(*) AS DEGER
FROM energy.dbo.LS_005_01_AGR_FITMENTFEE_TR
UNION ALL
SELECT 'ABYS migrate satirlari', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_FITMENTFEE_TR
WHERE ABYS_MIG_ROW_ID IS NOT NULL
UNION ALL
SELECT 'AGRID NULL (agreement var)', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_FITMENTFEE_TR
WHERE ABYS_AGREEMENT_ID IS NOT NULL AND AGRID IS NULL
UNION ALL
SELECT 'AGRID wired', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_FITMENTFEE_TR
WHERE AGRID IS NOT NULL
UNION ALL
SELECT 'FLATID NULL', COUNT(*)
FROM energy.dbo.LS_005_01_AGR_FITMENTFEE_TR
WHERE ABYS_MIG_ROW_ID IS NOT NULL AND FLATID IS NULL;
GO

-- AGRID orphan (AGR tablosu varsa)
IF OBJECT_ID('energy.dbo.LS_005_01_AGR', 'U') IS NOT NULL
BEGIN
    SELECT 'AGRID -> LS_005_01_AGR' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_FITMENTFEE_TR d
    WHERE d.AGRID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_01_AGR a WHERE a.ABYS_ID = d.AGRID
      );

    SELECT 'ABYS agreement AGR tablosunda yok' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_FITMENTFEE_TR d
    WHERE d.ABYS_AGREEMENT_ID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_01_AGR a
          WHERE a.ABYS_ID = d.ABYS_AGREEMENT_ID
             OR a.LREF = d.ABYS_AGREEMENT_ID
      );
END
GO

-- FLATID orphan
IF OBJECT_ID('energy.dbo.LS_FLAT', 'U') IS NOT NULL
BEGIN
    SELECT 'FLATID -> LS_FLAT' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_FITMENTFEE_TR d
    WHERE d.FLATID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_FLAT f WHERE f.LREF = d.FLATID
      );

    SELECT 'ABYS installation LS_FLAT yok' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_FITMENTFEE_TR d
    WHERE d.ABYS_INSTALLATION_ID IS NOT NULL
      AND d.FLATID IS NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_FLAT f
          WHERE f.ABYS_INSTALLATION_ID = d.ABYS_INSTALLATION_ID
            AND f.ENT_ID = 4102
      );
END
GO

EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY @MigrationCode = 'LS_005_01_AGR_FITMENTFEE_TR';
GO

