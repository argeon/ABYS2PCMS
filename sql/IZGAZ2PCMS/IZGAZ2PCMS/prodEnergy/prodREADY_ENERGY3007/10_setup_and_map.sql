-- =============================================================================
-- prodREADY_ENERGY3007 / 10_setup_and_map.sql
-- ENERGY setup notlari + MAP kopya (SP_MIG_OV_ID_MAP_SYNC_FROM_MGR)
-- Onkosul: E3007-00 GATE_PASS | 00_map_tables.sql (SP deploy)
-- =============================================================================
USE energy;
GO
SET NOCOUNT ON;

PRINT '========== E3007-10 SETUP — prodREADY_ENERGY scriptlerini calistirin ==========';
PRINT '1) ../prodREADY_ENERGY/00_log_setup.sql';
PRINT '2) ../prodREADY_ENERGY/00_map_tables.sql  (+ SP_MIG_OV_ID_MAP_SYNC_FROM_MGR)';
PRINT '3) MAP kopya → EXEC dbo.SP_MIG_OV_ID_MAP_SYNC_FROM_MGR';
PRINT '4) ../prodREADY_ENERGY/00_abys_columns.sql';
PRINT '5) ../prodREADY_ENERGY/01_linenr_smallint.sql';
PRINT '6) ../prodREADY_ENERGY/08_DEPLOY_MAIN_SP.sql  (571/581/575 + 569/611)';
PRINT '   Overlay SP sonra: 10→11→12→19 ve 20→21→22→29 (30_overlay oncesi)';
GO

/* MAP: izgazMGR.LS_OV_ID_MAP → energy.MIG_OV_ID_MAP (@Force=1: her zaman NOT EXISTS) */
EXEC dbo.SP_MIG_OV_ID_MAP_SYNC_FROM_MGR @DEBUG = 1, @Force = 1;
GO
