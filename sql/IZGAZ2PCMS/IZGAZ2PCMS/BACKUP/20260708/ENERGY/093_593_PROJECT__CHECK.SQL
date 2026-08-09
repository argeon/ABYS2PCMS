/* ============================================================
   SCRIPT_ID : PROJECT_CHECK
   SCRIPT_NO : 593
   FILE      : 593_PROJECT__check.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LS_005_01_PROJECT — kontrol sorgulari
-- Kaynak: izgazMGR.dbo.LS_PROJECT
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- PRE-FLIGHT (migrate oncesi — izgazMGR staging)
-- ------------------------------------------------------------
IF OBJECT_ID('izgazMGR.dbo.LS_PROJECT', 'U') IS NOT NULL
BEGIN
    SELECT 'PRE: kaynak toplam' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_PROJECT;

    SELECT 'PRE: ORACLE_PROJECT_ID NULL' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_PROJECT
    WHERE ORACLE_PROJECT_ID IS NULL;

    SELECT 'PRE: ORACLE_PROJECT_ID duplicate' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM (
        SELECT ORACLE_PROJECT_ID
        FROM izgazMGR.dbo.LS_PROJECT
        WHERE ORACLE_PROJECT_ID IS NOT NULL
        GROUP BY ORACLE_PROJECT_ID
        HAVING COUNT(*) > 1
    ) d;

    SELECT 'PRE: CODE > 50 char (truncation)' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_PROJECT
    WHERE LEN(CODE) > 50;

    SELECT 'PRE: OCODE > 20 char (truncation)' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_PROJECT
    WHERE LEN(OCODE) > 20;

    SELECT 'PRE: XTYPE > INT max' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM izgazMGR.dbo.LS_PROJECT
    WHERE XTYPE IS NOT NULL
      AND (XTYPE > 2147483647 OR XTYPE < -2147483648);
END
ELSE
    SELECT 'izgazMGR.dbo.LS_PROJECT yok — pre-flight atlandi' AS UYARI;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_PROJECT', 'U') IS NULL
BEGIN
    SELECT 'LS_005_01_PROJECT tablosu yok' AS UYARI;
    RETURN;
END
GO

-- ------------------------------------------------------------
-- POST-FLIGHT (hedef)
-- ------------------------------------------------------------
SELECT 'LS_005_01_PROJECT toplam' AS METRIK, COUNT(*) AS DEGER
FROM energy.dbo.LS_005_01_PROJECT
UNION ALL
SELECT 'ABYS migrate satirlari', COUNT(*)
FROM energy.dbo.LS_005_01_PROJECT
WHERE ABYS_ID IS NOT NULL
UNION ALL
SELECT 'CODE NULL/bos', COUNT(*)
FROM energy.dbo.LS_005_01_PROJECT
WHERE ABYS_ID IS NOT NULL AND (CODE IS NULL OR LTRIM(RTRIM(CODE)) = N'')
UNION ALL
SELECT 'STATID NULL', COUNT(*)
FROM energy.dbo.LS_005_01_PROJECT
WHERE ABYS_ID IS NOT NULL AND STATID IS NULL
UNION ALL
SELECT 'FIRM_ID NULL', COUNT(*)
FROM energy.dbo.LS_005_01_PROJECT
WHERE ABYS_ID IS NOT NULL AND FIRM_ID IS NULL
UNION ALL
SELECT 'INVOICE_ID NULL', COUNT(*)
FROM energy.dbo.LS_005_01_PROJECT
WHERE ABYS_ID IS NOT NULL AND INVOICE_ID IS NULL;
GO

-- Kaynak vs hedef adet
IF OBJECT_ID('izgazMGR.dbo.LS_PROJECT', 'U') IS NOT NULL
BEGIN
    SELECT
        (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_PROJECT WHERE ORACLE_PROJECT_ID IS NOT NULL) AS SRC_CNT,
        (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_PROJECT WHERE ABYS_ID IS NOT NULL) AS TGT_CNT,
        (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_PROJECT WHERE ORACLE_PROJECT_ID IS NOT NULL) -
        (SELECT COUNT_BIG(*) FROM energy.dbo.LS_005_01_PROJECT WHERE ABYS_ID IS NOT NULL) AS DIFF;
END
GO

-- Tutar rekonsil
IF OBJECT_ID('izgazMGR.dbo.LS_PROJECT', 'U') IS NOT NULL
BEGIN
    SELECT
        (SELECT SUM(TRY_CAST(TOTALFEE AS MONEY)) FROM izgazMGR.dbo.LS_PROJECT) AS SRC_TOTALFEE,
        (SELECT SUM(TOTALFEE) FROM energy.dbo.LS_005_01_PROJECT WHERE ABYS_ID IS NOT NULL) AS TGT_TOTALFEE,
        (SELECT SUM(TRY_CAST(TAX AS MONEY)) FROM izgazMGR.dbo.LS_PROJECT) AS SRC_TAX,
        (SELECT SUM(TAX) FROM energy.dbo.LS_005_01_PROJECT WHERE ABYS_ID IS NOT NULL) AS TGT_TAX,
        (SELECT SUM(TRY_CAST(GRANDTOTAL AS MONEY)) FROM izgazMGR.dbo.LS_PROJECT) AS SRC_GRANDTOTAL,
        (SELECT SUM(GRANDTOTAL) FROM energy.dbo.LS_005_01_PROJECT WHERE ABYS_ID IS NOT NULL) AS TGT_GRANDTOTAL;
END
GO

-- Orphan: kaynakta var, hedefte yok
IF OBJECT_ID('izgazMGR.dbo.LS_PROJECT', 'U') IS NOT NULL
BEGIN
    SELECT TOP (50)
        s.ORACLE_PROJECT_ID AS ABYS_ID,
        s.LREF AS ABYS_LREF,
        s.CODE
    FROM izgazMGR.dbo.LS_PROJECT s
    WHERE s.ORACLE_PROJECT_ID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_01_PROJECT t
          WHERE t.ABYS_ID = s.ORACLE_PROJECT_ID
      )
    ORDER BY s.ORACLE_PROJECT_ID;
END
GO

EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY @MigrationCode = 'LS_005_01_PROJECT';
GO
