/* ============================================================
   SCRIPT_ID : READ_HHD_LOC_INV_TRAN_CHECK
   SCRIPT_NO : 523
   FILE      : 523_READ_HHD_LOC_INV_TRAN__check.sql
   VERSION   : 2
   ============================================================ */
USE energy;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_hhd_loc_inv_tran', 'U') IS NULL
BEGIN
    SELECT 'LS_005_01_hhd_loc_inv_tran tablosu yok' AS UYARI;
    RETURN;
END
GO

SELECT 'hedef toplam' AS METRIK, COUNT(*) AS DEGER
FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
UNION ALL
SELECT 'ABYS migrate', COUNT(*)
FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
WHERE ABYS_ID IS NOT NULL
UNION ALL
SELECT 'LREF <> ABYS_ID', COUNT(*)
FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
WHERE ABYS_ID IS NOT NULL AND LREF <> ABYS_ID
UNION ALL
SELECT 'kaynak approx (partition)', SUM(p.rows)
FROM izgazMGR.sys.partitions p
INNER JOIN izgazMGR.sys.tables t ON t.object_id = p.object_id
INNER JOIN izgazMGR.sys.schemas sch ON sch.schema_id = t.schema_id
WHERE sch.name = 'dbo' AND t.name = 'LS_READING' AND p.index_id IN (0, 1)
UNION ALL
SELECT 'AGRID NULL (ABYS satirlari)', COUNT(*)
FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
WHERE ABYS_ID IS NOT NULL AND AGRID IS NULL
UNION ALL
SELECT 'reader_comp=0 (TRY_CAST fail/NULL)', COUNT(*)
FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
WHERE ABYS_ID IS NOT NULL AND reader_comp = 0
UNION ALL
SELECT 'ABYS_SM3 dolu', COUNT(*)
FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
WHERE ABYS_ID IS NOT NULL AND ABYS_SM3 IS NOT NULL;
GO

-- unresolved AGRID ornekleri (kaynakta AGRID var, hedefte NULL)
SELECT TOP 20
    t.ABYS_ID,
    t.AGRID AS HEDEF_AGRID
FROM energy.dbo.LS_005_01_hhd_loc_inv_tran t
WHERE t.ABYS_ID IS NOT NULL
  AND t.AGRID IS NULL
ORDER BY t.ABYS_ID;
GO

EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY @MigrationCode = 'LS_005_01_HHD_LOC_INV_TRAN';
GO
