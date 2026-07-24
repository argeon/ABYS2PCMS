/* ============================================================
   SCRIPT_ID : READ_HHD_LOC_INV_TRAN_CHECK
   SCRIPT_NO : 523
   FILE      : 523_READ_HHD_LOC_INV_TRAN__check.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LS_005_01_hhd_loc_inv_tran — kontrol sorgulari
-- ============================================================
USE energy;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_hhd_loc_inv_tran', 'U') IS NULL
BEGIN
    SELECT 'LS_005_01_hhd_loc_inv_tran tablosu yok' AS UYARI;
    RETURN;
END
GO

SELECT 'LS_005_01_hhd_loc_inv_tran toplam' AS METRIK, COUNT(*) AS DEGER
FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
UNION ALL
SELECT 'ABYS migrate satirlari', COUNT(*)
FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
WHERE ABYS_ID IS NOT NULL
UNION ALL
SELECT 'LREF <> ABYS_ID', COUNT(*)
FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
WHERE ABYS_ID IS NOT NULL AND LREF <> ABYS_ID
UNION ALL
SELECT 'Kaynak LS_READING_197168', COUNT_BIG(*)
FROM izgazMGR.dbo.LS_READING_197168
UNION ALL
SELECT 'View (int LREF filtresi)', COUNT_BIG(*)
FROM energy.dbo.VW_MIG_LS005_HHD_LOC_INV_TRAN_SOURCE
UNION ALL
SELECT 'Kaynak LREF > INT_MAX (atlanan)', COUNT_BIG(*)
FROM izgazMGR.dbo.LS_READING_197168
WHERE LREF IS NULL OR LREF < 1 OR LREF > 2147483647;
GO

SELECT
    'payable_total kaynak' AS METRIK,
    SUM(TRY_CAST(PAYABLE_TOTAL AS DECIMAL(18, 2))) AS DEGER
FROM izgazMGR.dbo.LS_READING_197168
UNION ALL
SELECT
    'payable_total hedef (ABYS)',
    SUM(payable_total)
FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
WHERE ABYS_ID IS NOT NULL
UNION ALL
SELECT
    'expend_energy kaynak',
    SUM(TRY_CAST(EXPEND_ENERGY AS DECIMAL(18, 2)))
FROM izgazMGR.dbo.LS_READING_197168
UNION ALL
SELECT
    'expend_energy hedef (ABYS)',
    SUM(expend_energy)
FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
WHERE ABYS_ID IS NOT NULL;
GO

-- Kaynakta olup hedefte olmayan ABYS_ID (view kapsaminda)
SELECT TOP 20 s.ABYS_ID AS EKSIK_ABYS_ID
FROM energy.dbo.VW_MIG_LS005_HHD_LOC_INV_TRAN_SOURCE s
WHERE NOT EXISTS (
    SELECT 1
    FROM energy.dbo.LS_005_01_hhd_loc_inv_tran t
    WHERE t.ABYS_ID = s.ABYS_ID
)
ORDER BY s.ABYS_ID;
GO

EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY @MigrationCode = 'LS_005_01_HHD_LOC_INV_TRAN';
GO
