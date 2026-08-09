/* ============================================================
   SCRIPT_ID : AGR_AGR_CHECK
   SCRIPT_NO : 303
   FILE      : 303_AGR_AGR__check.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LS_005_01_AGR — kontrol sorguları
-- izgazMGR.dbo.LS_AGREEMENT → energy.dbo.LS_005_01_AGR
-- ============================================================
USE energy;
GO

IF OBJECT_ID('izgazMGR.dbo.LS_AGREEMENT', 'U') IS NULL
BEGIN
    SELECT 'izgazMGR.dbo.LS_AGREEMENT tablosu yok' AS UYARI;
END
ELSE
BEGIN
    SELECT 'Kaynak toplam' AS METRIK, COUNT(*) AS DEGER
    FROM izgazMGR.dbo.LS_AGREEMENT
    UNION ALL
    SELECT 'Kaynak KUL', COUNT(*) FROM izgazMGR.dbo.LS_AGREEMENT WHERE RTRIM(TP2) = 'KUL'
    UNION ALL
    SELECT 'Kaynak ABN', COUNT(*) FROM izgazMGR.dbo.LS_AGREEMENT WHERE RTRIM(TP2) = 'ABN'
    UNION ALL
    SELECT 'Ayni ABYS_ID KUL+ABN (normal)', COUNT(*)
    FROM izgazMGR.dbo.LS_AGREEMENT k
    INNER JOIN izgazMGR.dbo.LS_AGREEMENT a
        ON a.ABYS_ID = k.ABYS_ID AND RTRIM(a.TP2) = 'ABN'
    WHERE RTRIM(k.TP2) = 'KUL';
END
GO

IF OBJECT_ID('energy.dbo.LS_005_01_AGR', 'U') IS NULL
BEGIN
    SELECT 'energy.dbo.LS_005_01_AGR tablosu yok' AS UYARI;
END
ELSE
BEGIN
    SELECT 'Hedef ABYS kayit' AS METRIK, COUNT(*) AS DEGER
    FROM energy.dbo.LS_005_01_AGR
    WHERE ABYS_MIG_ROW_ID IS NOT NULL
    UNION ALL
    SELECT 'Hedef KUL', COUNT(*)
    FROM energy.dbo.LS_005_01_AGR
    WHERE ABYS_MIG_ROW_ID IS NOT NULL AND RTRIM(TP2) = 'KUL'
    UNION ALL
    SELECT 'Hedef ABN', COUNT(*)
    FROM energy.dbo.LS_005_01_AGR
    WHERE ABYS_MIG_ROW_ID IS NOT NULL AND RTRIM(TP2) = 'ABN'
    UNION ALL
    SELECT 'LREF otomatik (ABYS_MIG_ROW_ID dolu)', COUNT(*)
    FROM energy.dbo.LS_005_01_AGR
    WHERE ABYS_MIG_ROW_ID IS NOT NULL AND LREF IS NOT NULL;

-- FLATID orphan (FK kaldirildi; veri duzeltme icin bilgilendirme)
IF OBJECT_ID('energy.dbo.LS_FLAT', 'U') IS NOT NULL
BEGIN
    SELECT 'FLATID -> LS_FLAT (FK yok, bilgi)' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR a
    WHERE a.ABYS_MIG_ROW_ID IS NOT NULL
      AND a.FLATID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_FLAT f WHERE f.LREF = a.FLATID
      );
END

-- CON orphan (FK kaldirildi; veri duzeltme icin bilgilendirme)
IF OBJECT_ID('energy.dbo.LS_005_SUBSCR', 'U') IS NOT NULL
BEGIN
    SELECT 'CON -> LS_005_SUBSCR (FK yok, bilgi)' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR a
    WHERE a.ABYS_MIG_ROW_ID IS NOT NULL
      AND a.CON IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_005_SUBSCR r WHERE r.LREF = a.CON
      );
END

    -- (TP2, ABYS_ID) tekillik
    SELECT 'TP2+ABYS_ID duplicate' AS METRIK, COUNT(*) AS DEGER
    FROM (
        SELECT TP2, ABYS_ID
        FROM energy.dbo.LS_005_01_AGR
        WHERE ABYS_ID IS NOT NULL
        GROUP BY TP2, ABYS_ID
        HAVING COUNT(*) > 1
    ) d;
END
GO

EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY @MigrationCode = 'LS_005_01_AGR';
GO

