/* ============================================================
   deploy_create_all_sps.sql
   TEK GIRIS — tum SP/view/FN/setup/wire/post olusturma.
   SSMS: energy bagliyken yalnizca BU dosyayi acip calistirin.
   sqlcmd ornek:
     sqlcmd -S 172.16.1.192 -d energy -U pcms -P *** -C -I -i deploy_create_all_sps.sql

   Dahil: setup, migrate (CREATE OR ALTER), wire, post
   Haric: check, adhoc, EXEC SP_MIGRATE_* (veri aktarimi)
   ============================================================ */
USE energy;
GO
SET NOCOUNT ON;
GO
PRINT '=== 100_INFRA_MIGLOG__setup.sql ===';
:r .\100_INFRA_MIGLOG__setup.sql
GO

PRINT '=== 101_INFRA_MIGLOG__migrate.sql ===';
:r .\101_INFRA_MIGLOG__migrate.sql
GO

PRINT '=== 102_INFRA_SCRIPT_CATALOG__setup.sql ===';
:r .\102_INFRA_SCRIPT_CATALOG__setup.sql
GO

PRINT '=== 103_INFRA_SCRIPT_CATALOG__seed.sql ===';
:r .\103_INFRA_SCRIPT_CATALOG__seed.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'INFRA_SCRIPT_CATALOG_SEED', @Version = 1;
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'INFRA_SCRIPT_CATALOG', @Version = 1;
GO

PRINT '=== 110_REF_IT_USER__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'REF_IT_USER_SETUP', @ScriptNo = 110, @Version = 1;
GO
:r .\110_REF_IT_USER__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'REF_IT_USER_SETUP', @Version = 1;
GO

PRINT '=== 111_REF_IT_USER__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'REF_IT_USER_MIGRATE', @ScriptNo = 111, @Version = 1;
GO
:r .\111_REF_IT_USER__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'REF_IT_USER_MIGRATE', @Version = 1;
GO

PRINT '=== 120_REF_BANK__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'REF_BANK_SETUP', @ScriptNo = 120, @Version = 1;
GO
:r .\120_REF_BANK__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'REF_BANK_SETUP', @Version = 1;
GO

PRINT '=== 121_REF_BANK__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'REF_BANK_MIGRATE', @ScriptNo = 121, @Version = 1;
GO
:r .\121_REF_BANK__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'REF_BANK_MIGRATE', @Version = 1;
GO

PRINT '=== 122_REF_BANK__post.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'REF_BANK_POST', @ScriptNo = 122, @Version = 1;
GO
:r .\122_REF_BANK__post.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'REF_BANK_POST', @Version = 1;
GO

PRINT '=== 130_REF_TARIFF__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'REF_TARIFF_SETUP', @ScriptNo = 130, @Version = 1;
GO
:r .\130_REF_TARIFF__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'REF_TARIFF_SETUP', @Version = 1;
GO

PRINT '=== 131_REF_TARIFF__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'REF_TARIFF_MIGRATE', @ScriptNo = 131, @Version = 1;
GO
:r .\131_REF_TARIFF__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'REF_TARIFF_MIGRATE', @Version = 1;
GO

PRINT '=== 132_REF_TARIFF__wire.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'REF_TARIFF_WIRE', @ScriptNo = 132, @Version = 1;
GO
:r .\132_REF_TARIFF__wire.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'REF_TARIFF_WIRE', @Version = 1;
GO

PRINT '=== 140_REF_FUID__setup.sql [v2] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'REF_FUID_SETUP', @ScriptNo = 140, @Version = 2;
GO
:r .\140_REF_FUID__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'REF_FUID_SETUP', @Version = 2;
GO

PRINT '=== 141_REF_FUID__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'REF_FUID_MIGRATE', @ScriptNo = 141, @Version = 1;
GO
:r .\141_REF_FUID__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'REF_FUID_MIGRATE', @Version = 1;
GO

PRINT '=== 200_MASTER_SUBSCR__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'MASTER_SUBSCR_SETUP', @ScriptNo = 200, @Version = 1;
GO
:r .\200_MASTER_SUBSCR__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'MASTER_SUBSCR_SETUP', @Version = 1;
GO

PRINT '=== 201_MASTER_SUBSCR__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'MASTER_SUBSCR_MIGRATE', @ScriptNo = 201, @Version = 1;
GO
:r .\201_MASTER_SUBSCR__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'MASTER_SUBSCR_MIGRATE', @Version = 1;
GO

PRINT '=== 210_MASTER_SUBSCR_COMM__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'MASTER_SUBSCR_COMM_SETUP', @ScriptNo = 210, @Version = 1;
GO
:r .\210_MASTER_SUBSCR_COMM__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'MASTER_SUBSCR_COMM_SETUP', @Version = 1;
GO

PRINT '=== 211_MASTER_SUBSCR_COMM__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'MASTER_SUBSCR_COMM_MIGRATE', @ScriptNo = 211, @Version = 1;
GO
:r .\211_MASTER_SUBSCR_COMM__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'MASTER_SUBSCR_COMM_MIGRATE', @Version = 1;
GO

PRINT '=== 220_MASTER_GIS_FLAT__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'MASTER_GIS_FLAT_SETUP', @ScriptNo = 220, @Version = 1;
GO
:r .\220_MASTER_GIS_FLAT__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'MASTER_GIS_FLAT_SETUP', @Version = 1;
GO

PRINT '=== 221_MASTER_GIS_FLAT__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'MASTER_GIS_FLAT_MIGRATE', @ScriptNo = 221, @Version = 1;
GO
:r .\221_MASTER_GIS_FLAT__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'MASTER_GIS_FLAT_MIGRATE', @Version = 1;
GO

PRINT '=== 240_MASTER_ITEMS__setup.sql [v2] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'MASTER_ITEMS_SETUP', @ScriptNo = 240, @Version = 2;
GO
:r .\240_MASTER_ITEMS__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'MASTER_ITEMS_SETUP', @Version = 2;
GO

PRINT '=== 241_MASTER_ITEMS__migrate.sql [v2] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'MASTER_ITEMS_MIGRATE', @ScriptNo = 241, @Version = 2;
GO
:r .\241_MASTER_ITEMS__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'MASTER_ITEMS_MIGRATE', @Version = 2;
GO

PRINT '=== 242_MASTER_ITEMS__post.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'MASTER_ITEMS_POST', @ScriptNo = 242, @Version = 1;
GO
:r .\242_MASTER_ITEMS__post.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'MASTER_ITEMS_POST', @Version = 1;
GO

PRINT '=== 300_AGR_AGR__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_AGR_SETUP', @ScriptNo = 300, @Version = 1;
GO
:r .\300_AGR_AGR__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_AGR_SETUP', @Version = 1;
GO

PRINT '=== 301_AGR_AGR__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_AGR_MIGRATE', @ScriptNo = 301, @Version = 1;
GO
:r .\301_AGR_AGR__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_AGR_MIGRATE', @Version = 1;
GO

PRINT '=== 310_AGR_GUARANTY__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_GUARANTY_SETUP', @ScriptNo = 310, @Version = 1;
GO
:r .\310_AGR_GUARANTY__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_GUARANTY_SETUP', @Version = 1;
GO

PRINT '=== 311_AGR_GUARANTY__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_GUARANTY_MIGRATE', @ScriptNo = 311, @Version = 1;
GO
:r .\311_AGR_GUARANTY__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_GUARANTY_MIGRATE', @Version = 1;
GO

PRINT '=== 320_AGR_CLOSE__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_CLOSE_SETUP', @ScriptNo = 320, @Version = 1;
GO
:r .\320_AGR_CLOSE__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_CLOSE_SETUP', @Version = 1;
GO

PRINT '=== 321_AGR_CLOSE__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_CLOSE_MIGRATE', @ScriptNo = 321, @Version = 1;
GO
:r .\321_AGR_CLOSE__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_CLOSE_MIGRATE', @Version = 1;
GO

PRINT '=== 322_AGR_CLOSE__wire.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_CLOSE_WIRE', @ScriptNo = 322, @Version = 1;
GO
:r .\322_AGR_CLOSE__wire.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_CLOSE_WIRE', @Version = 1;
GO

PRINT '=== 330_AGR_DEV__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_DEV_SETUP', @ScriptNo = 330, @Version = 1;
GO
:r .\330_AGR_DEV__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_DEV_SETUP', @Version = 1;
GO

PRINT '=== 331_AGR_DEV__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_DEV_MIGRATE', @ScriptNo = 331, @Version = 1;
GO
:r .\331_AGR_DEV__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_DEV_MIGRATE', @Version = 1;
GO

PRINT '=== 340_AGR_SERVEQ__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_SERVEQ_SETUP', @ScriptNo = 340, @Version = 1;
GO
:r .\340_AGR_SERVEQ__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_SERVEQ_SETUP', @Version = 1;
GO

PRINT '=== 341_AGR_SERVEQ__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_SERVEQ_MIGRATE', @ScriptNo = 341, @Version = 1;
GO
:r .\341_AGR_SERVEQ__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_SERVEQ_MIGRATE', @Version = 1;
GO

PRINT '=== 350_AGR_FITMENTFEE__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_FITMENTFEE_SETUP', @ScriptNo = 350, @Version = 1;
GO
:r .\350_AGR_FITMENTFEE__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_FITMENTFEE_SETUP', @Version = 1;
GO

PRINT '=== 351_AGR_FITMENTFEE__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_FITMENTFEE_MIGRATE', @ScriptNo = 351, @Version = 1;
GO
:r .\351_AGR_FITMENTFEE__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_FITMENTFEE_MIGRATE', @Version = 1;
GO

PRINT '=== 360_AGR_BNK_TALIMAT__setup.sql [v3] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_BNK_TALIMAT_SETUP', @ScriptNo = 360, @Version = 3;
GO
:r .\360_AGR_BNK_TALIMAT__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_BNK_TALIMAT_SETUP', @Version = 3;
GO

PRINT '=== 361_AGR_BNK_TALIMAT__migrate.sql [v4] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'AGR_BNK_TALIMAT_MIGRATE', @ScriptNo = 361, @Version = 4;
GO
:r .\361_AGR_BNK_TALIMAT__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'AGR_BNK_TALIMAT_MIGRATE', @Version = 4;
GO

PRINT '=== 500_READ_PLAN__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'READ_PLAN_SETUP', @ScriptNo = 500, @Version = 1;
GO
:r .\500_READ_PLAN__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'READ_PLAN_SETUP', @Version = 1;
GO

PRINT '=== 501_READ_PLAN__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'READ_PLAN_MIGRATE', @ScriptNo = 501, @Version = 1;
GO
:r .\501_READ_PLAN__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'READ_PLAN_MIGRATE', @Version = 1;
GO

PRINT '=== 510_READ_INCOME__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'READ_INCOME_SETUP', @ScriptNo = 510, @Version = 1;
GO
:r .\510_READ_INCOME__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'READ_INCOME_SETUP', @Version = 1;
GO

PRINT '=== 511_READ_INCOME__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'READ_INCOME_MIGRATE', @ScriptNo = 511, @Version = 1;
GO
:r .\511_READ_INCOME__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'READ_INCOME_MIGRATE', @Version = 1;
GO

PRINT '=== 520_READ_HHD_LOC_INV_TRAN__setup.sql [v2] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'READ_HHD_LOC_INV_TRAN_SETUP', @ScriptNo = 520, @Version = 2;
GO
:r .\520_READ_HHD_LOC_INV_TRAN__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'READ_HHD_LOC_INV_TRAN_SETUP', @Version = 2;
GO

PRINT '=== 521_READ_HHD_LOC_INV_TRAN__migrate.sql [v3] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'READ_HHD_LOC_INV_TRAN_MIGRATE', @ScriptNo = 521, @Version = 3;
GO
:r .\521_READ_HHD_LOC_INV_TRAN__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'READ_HHD_LOC_INV_TRAN_MIGRATE', @Version = 3;
GO

PRINT '=== 530_WO_CS_APPOINTMENT__setup.sql [v2] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'WO_CS_APPOINTMENT_SETUP', @ScriptNo = 530, @Version = 2;
GO
:r .\530_WO_CS_APPOINTMENT__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'WO_CS_APPOINTMENT_SETUP', @Version = 2;
GO

PRINT '=== 531_WO_CS_APPOINTMENT__migrate.sql [v7] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'WO_CS_APPOINTMENT_MIGRATE', @ScriptNo = 531, @Version = 7;
GO
:r .\531_WO_CS_APPOINTMENT__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'WO_CS_APPOINTMENT_MIGRATE', @Version = 7;
GO

PRINT '=== 540_WO_WORK_RESULT__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'WO_WORK_RESULT_SETUP', @ScriptNo = 540, @Version = 1;
GO
:r .\540_WO_WORK_RESULT__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'WO_WORK_RESULT_SETUP', @Version = 1;
GO

PRINT '=== 541_WO_WORK_RESULT__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'WO_WORK_RESULT_MIGRATE', @ScriptNo = 541, @Version = 1;
GO
:r .\541_WO_WORK_RESULT__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'WO_WORK_RESULT_MIGRATE', @Version = 1;
GO

PRINT '=== 550_COMM_LOG__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'COMM_LOG_SETUP', @ScriptNo = 550, @Version = 1;
GO
:r .\550_COMM_LOG__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'COMM_LOG_SETUP', @Version = 1;
GO

PRINT '=== 551_COMM_LOG__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'COMM_LOG_MIGRATE', @ScriptNo = 551, @Version = 1;
GO
:r .\551_COMM_LOG__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'COMM_LOG_MIGRATE', @Version = 1;
GO

PRINT '=== 560_OPR_SYNC_CLIENT__setup.sql [v2] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'OPR_SYNC_CLIENT_SETUP', @ScriptNo = 560, @Version = 2;
GO
:r .\560_OPR_SYNC_CLIENT__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'OPR_SYNC_CLIENT_SETUP', @Version = 2;
GO

PRINT '=== 561_OPR_SYNC_CLIENT__migrate.sql [v3] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'OPR_SYNC_CLIENT_MIGRATE', @ScriptNo = 561, @Version = 3;
GO
:r .\561_OPR_SYNC_CLIENT__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'OPR_SYNC_CLIENT_MIGRATE', @Version = 3;
GO

PRINT '=== 570_INVOICE__setup.sql [v3] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'INVOICE_SETUP', @ScriptNo = 570, @Version = 3;
GO
:r .\570_INVOICE__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'INVOICE_SETUP', @Version = 3;
GO

PRINT '=== 571_INVOICE__migrate.sql [v4] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'INVOICE_MIGRATE', @ScriptNo = 571, @Version = 4;
GO
:r .\571_INVOICE__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'INVOICE_MIGRATE', @Version = 4;
GO

PRINT '=== 572_INVOICE__post.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'INVOICE_POST', @ScriptNo = 572, @Version = 1;
GO
:r .\572_INVOICE__post.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'INVOICE_POST', @Version = 1;
GO

PRINT '=== 600_LEGAL_LP__setup.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'LEGAL_LP_SETUP', @ScriptNo = 600, @Version = 1;
GO
:r .\600_LEGAL_LP__setup.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'LEGAL_LP_SETUP', @Version = 1;
GO

PRINT '=== 601_LEGAL_LP__migrate.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'LEGAL_LP_MIGRATE', @ScriptNo = 601, @Version = 1;
GO
:r .\601_LEGAL_LP__migrate.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'LEGAL_LP_MIGRATE', @Version = 1;
GO

PRINT '=== 602_LEGAL_LP__wire.sql [v1] ===';
EXEC energy.dbo.SP_MIG_SCRIPT_ASSERT @ScriptId = 'LEGAL_LP_WIRE', @ScriptNo = 602, @Version = 1;
GO
:r .\602_LEGAL_LP__wire.sql
GO
EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'LEGAL_LP_WIRE', @Version = 1;
GO

IF OBJECT_ID('energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED', 'P') IS NOT NULL
BEGIN
    EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'INFRA_MIGLOG_SETUP', @Version = 1;
    EXEC energy.dbo.SP_MIG_SCRIPT_MARK_DEPLOYED @ScriptId = 'INFRA_MIGLOG_PROCS', @Version = 1;
END
GO
PRINT '=== AUDIT (drift uyarisi RaiseOnDrift=0) ===';
EXEC energy.dbo.SP_MIG_SCRIPT_AUDIT @RaiseOnDrift = 0;
GO
PRINT '=== deploy_create_all_sps tamamlandi ===';
GO
