/* ============================================================
   SCRIPT_ID : READ_INCOME_CHECK
   SCRIPT_NO : 513
   FILE      : 513_READ_INCOME__check.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LS_005_ReadingIncome — kontrol sorgulari
-- ============================================================
USE energy;
GO

IF OBJECT_ID('energy.dbo.LS_005_ReadingIncome', 'U') IS NULL
BEGIN
    SELECT 'LS_005_ReadingIncome tablosu yok' AS UYARI;
    RETURN;
END
GO

SELECT 'LS_005_ReadingIncome toplam' AS METRIK, COUNT(*) AS DEGER
FROM energy.dbo.LS_005_ReadingIncome
UNION ALL
SELECT 'ABYS migrate satirlari', COUNT(*)
FROM energy.dbo.LS_005_ReadingIncome
WHERE ABYS_ID IS NOT NULL
UNION ALL
SELECT 'LREF <> ABYS_ID', COUNT(*)
FROM energy.dbo.LS_005_ReadingIncome
WHERE ABYS_ID IS NOT NULL AND LREF <> ABYS_ID
UNION ALL
SELECT 'Kaynak CS_READING_INCOME', COUNT_BIG(*)
FROM izgazMGR.dbo.CS_READING_INCOME;
GO

SELECT
    'Tutar toplami (kaynak AMOUNT)' AS METRIK,
    SUM(TRY_CAST(AMOUNT AS DECIMAL(18, 2))) AS DEGER
FROM izgazMGR.dbo.CS_READING_INCOME
UNION ALL
SELECT
    'Tutar toplami (hedef TARIFF_INCOME_AMOUNT)',
    SUM(TARIFF_INCOME_AMOUNT)
FROM energy.dbo.LS_005_ReadingIncome
WHERE ABYS_ID IS NOT NULL;
GO

-- READING_ID orphan (LS_005_Reading varsa)
IF OBJECT_ID('energy.dbo.LS_005_Reading', 'U') IS NOT NULL
BEGIN
    SELECT 'READING_ID -> LS_005_Reading' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_ReadingIncome ri
    WHERE ri.READING_ID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_Reading r WHERE r.LREF = ri.READING_ID
      );
END
ELSE
BEGIN
    SELECT 'LS_005_Reading tablosu yok — READING_ID FK kontrolu atlandi' AS UYARI;
END
GO

-- Kaynakta olup hedefte olmayan ABYS_ID
SELECT TOP 20 s.ID AS EKSIK_ABYS_ID
FROM izgazMGR.dbo.CS_READING_INCOME s
WHERE NOT EXISTS (
    SELECT 1 FROM energy.dbo.LS_005_ReadingIncome t WHERE t.ABYS_ID = s.ID
)
ORDER BY s.ID;
GO

EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY @MigrationCode = 'LS_005_READING_INCOME';
GO

