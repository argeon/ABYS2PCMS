/* ============================================================
   SCRIPT_ID : INFRA_SCRIPT_CATALOG_SEED
   SCRIPT_NO : 103
   FILE      : 103_INFRA_SCRIPT_CATALOG__seed.sql
   VERSION   : 1
   ============================================================ */
USE energy;
GO

IF OBJECT_ID('energy.dbo.MIG_SCRIPT_CATALOG', 'U') IS NULL
BEGIN
    RAISERROR('Once 102_INFRA_SCRIPT_CATALOG__setup.sql calistirin.', 16, 1);
    RETURN;
END
GO

MERGE energy.dbo.MIG_SCRIPT_CATALOG AS t
USING (VALUES
  ('INFRA_MIGLOG_SETUP', 100, 'INFRA', 'MIGLOG', 'setup', N'100_INFRA_MIGLOG__setup.sql', 1),
  ('INFRA_MIGLOG_PROCS', 101, 'INFRA', 'MIGLOG', 'migrate', N'101_INFRA_MIGLOG__migrate.sql', 1),
  ('INFRA_SCRIPT_CATALOG', 102, 'INFRA', 'SCRIPT_CATALOG', 'setup', N'102_INFRA_SCRIPT_CATALOG__setup.sql', 1),
  ('INFRA_SCRIPT_CATALOG_SEED', 103, 'INFRA', 'SCRIPT_CATALOG', 'setup', N'103_INFRA_SCRIPT_CATALOG__seed.sql', 1),
  ('REF_IT_USER_SETUP', 110, 'REF', 'IT_USER', 'setup', N'110_REF_IT_USER__setup.sql', 1),
  ('REF_IT_USER_MIGRATE', 111, 'REF', 'IT_USER', 'migrate', N'111_REF_IT_USER__migrate.sql', 1),
  ('REF_BANK_MIGRATE', 121, 'REF', 'BANK', 'migrate', N'121_REF_BANK__migrate.sql', 2),
  ('REF_TARIFF_SETUP', 130, 'REF', 'TARIFF', 'setup', N'130_REF_TARIFF__setup.sql', 1),
  ('REF_TARIFF_MIGRATE', 131, 'REF', 'TARIFF', 'migrate', N'131_REF_TARIFF__migrate.sql', 1),
  ('REF_TARIFF_WIRE', 132, 'REF', 'TARIFF', 'wire', N'132_REF_TARIFF__wire.sql', 1),
  ('REF_TARIFF_CHECK', 133, 'REF', 'TARIFF', 'check', N'133_REF_TARIFF__check.sql', 1),
  ('REF_FUID_SETUP', 140, 'REF', 'FUID', 'setup', N'140_REF_FUID__setup.sql', 4),
  ('REF_FUID_MIGRATE', 141, 'REF', 'FUID', 'migrate', N'141_REF_FUID__migrate.sql', 2),
  ('MASTER_SUBSCR_SETUP', 200, 'MASTER', 'SUBSCR', 'setup', N'200_MASTER_SUBSCR__setup.sql', 1),
  ('MASTER_SUBSCR_MIGRATE', 201, 'MASTER', 'SUBSCR', 'migrate', N'201_MASTER_SUBSCR__migrate.sql', 1),
  ('MASTER_SUBSCR_COMM_SETUP', 210, 'MASTER', 'SUBSCR_COMM', 'setup', N'210_MASTER_SUBSCR_COMM__setup.sql', 1),
  ('MASTER_SUBSCR_COMM_MIGRATE', 211, 'MASTER', 'SUBSCR_COMM', 'migrate', N'211_MASTER_SUBSCR_COMM__migrate.sql', 1),
  ('MASTER_SUBSCR_COMM_PERM_SETUP', 212, 'MASTER', 'SUBSCR_COMM_PERM', 'setup', N'212_MASTER_SUBSCR_COMM_PERM__setup.sql', 1),
  ('MASTER_SUBSCR_COMM_PERM_MIGRATE', 213, 'MASTER', 'SUBSCR_COMM_PERM', 'migrate', N'213_MASTER_SUBSCR_COMM_PERM__migrate.sql', 1),
  ('MASTER_GIS_FLAT_SETUP', 220, 'MASTER', 'GIS_FLAT', 'setup', N'220_MASTER_GIS_FLAT__setup.sql', 1),
  ('MASTER_GIS_FLAT_MIGRATE', 221, 'MASTER', 'GIS_FLAT', 'migrate', N'221_MASTER_GIS_FLAT__migrate.sql', 1),
  ('MASTER_ITEMS_SETUP', 240, 'MASTER', 'ITEMS', 'setup', N'240_MASTER_ITEMS__setup.sql', 4),
  ('MASTER_ITEMS_MIGRATE', 241, 'MASTER', 'ITEMS', 'migrate', N'241_MASTER_ITEMS__migrate.sql', 4),
  ('MASTER_ITEMS_POST', 242, 'MASTER', 'ITEMS', 'post', N'242_MASTER_ITEMS__post.sql', 1),
  ('AGR_AGR_SETUP', 300, 'AGR', 'AGR', 'setup', N'300_AGR_AGR__setup.sql', 1),
  ('AGR_AGR_MIGRATE', 301, 'AGR', 'AGR', 'migrate', N'301_AGR_AGR__migrate.sql', 1),
  ('AGR_AGR_CHECK', 303, 'AGR', 'AGR', 'check', N'303_AGR_AGR__check.sql', 1),
  ('AGR_GUARANTY_STAGING_SETUP', 305, 'AGR', 'GUARANTY', 'setup', N'305_AGR_GUARANTY_STAGING__setup.sql', 1),
  ('AGR_GUARANTY_SETUP', 310, 'AGR', 'GUARANTY', 'setup', N'310_AGR_GUARANTY__setup.sql', 1),
  ('AGR_GUARANTY_MIGRATE', 311, 'AGR', 'GUARANTY', 'migrate', N'311_AGR_GUARANTY__migrate.sql', 1),
  ('AGR_CLOSE_SETUP', 320, 'AGR', 'CLOSE', 'setup', N'320_AGR_CLOSE__setup.sql', 1),
  ('AGR_CLOSE_MIGRATE', 321, 'AGR', 'CLOSE', 'migrate', N'321_AGR_CLOSE__migrate.sql', 1),
  ('AGR_CLOSE_WIRE', 322, 'AGR', 'CLOSE', 'wire', N'322_AGR_CLOSE__wire.sql', 1),
  ('AGR_CLOSE_CHECK', 323, 'AGR', 'CLOSE', 'check', N'323_AGR_CLOSE__check.sql', 1),
  ('AGR_DEV_SETUP', 330, 'AGR', 'DEV', 'setup', N'330_AGR_DEV__setup.sql', 1),
  ('AGR_DEV_MIGRATE', 331, 'AGR', 'DEV', 'migrate', N'331_AGR_DEV__migrate.sql', 1),
  ('AGR_DEV_CHECK', 333, 'AGR', 'DEV', 'check', N'333_AGR_DEV__check.sql', 1),
  ('AGR_SERVEQ_SETUP', 340, 'AGR', 'SERVEQ', 'setup', N'340_AGR_SERVEQ__setup.sql', 1),
  ('AGR_SERVEQ_MIGRATE', 341, 'AGR', 'SERVEQ', 'migrate', N'341_AGR_SERVEQ__migrate.sql', 1),
  ('AGR_SERVEQ_CHECK', 343, 'AGR', 'SERVEQ', 'check', N'343_AGR_SERVEQ__check.sql', 1),
  ('AGR_FITMENTFEE_SETUP', 350, 'AGR', 'FITMENTFEE', 'setup', N'350_AGR_FITMENTFEE__setup.sql', 1),
  ('AGR_FITMENTFEE_MIGRATE', 351, 'AGR', 'FITMENTFEE', 'migrate', N'351_AGR_FITMENTFEE__migrate.sql', 1),
  ('AGR_FITMENTFEE_CHECK', 353, 'AGR', 'FITMENTFEE', 'check', N'353_AGR_FITMENTFEE__check.sql', 1),
  ('AGR_BNK_TALIMAT_SETUP', 360, 'AGR', 'BNK_TALIMAT', 'setup', N'360_AGR_BNK_TALIMAT__setup.sql', 3),
  ('AGR_BNK_TALIMAT_MIGRATE', 361, 'AGR', 'BNK_TALIMAT', 'migrate', N'361_AGR_BNK_TALIMAT__migrate.sql', 4),
  ('AGR_BNK_TALIMAT_CHECK', 363, 'AGR', 'BNK_TALIMAT', 'check', N'363_AGR_BNK_TALIMAT__check.sql', 1),
  ('AGR_BNK_MUTABAKAT_SETUP', 364, 'AGR', 'BNK_MUTABAKAT', 'setup', N'364_AGR_BNK_MUTABAKAT__setup.sql', 4),
  ('AGR_BNK_MUTABAKAT_MIGRATE', 365, 'AGR', 'BNK_MUTABAKAT', 'migrate', N'365_AGR_BNK_MUTABAKAT__migrate.sql', 4),
  ('AGR_BNK_MUTABAKAT_CHECK', 367, 'AGR', 'BNK_MUTABAKAT', 'check', N'367_AGR_BNK_MUTABAKAT__check.sql', 4),
  ('READ_PLAN_SETUP', 500, 'READ', 'PLAN', 'setup', N'500_READ_PLAN__setup.sql', 1),
  ('READ_PLAN_MIGRATE', 501, 'READ', 'PLAN', 'migrate', N'501_READ_PLAN__migrate.sql', 1),
  ('READ_INCOME_SETUP', 510, 'READ', 'INCOME', 'setup', N'510_READ_INCOME__setup.sql', 1),
  ('READ_INCOME_MIGRATE', 511, 'READ', 'INCOME', 'migrate', N'511_READ_INCOME__migrate.sql', 1),
  ('READ_INCOME_CHECK', 513, 'READ', 'INCOME', 'check', N'513_READ_INCOME__check.sql', 1),
  ('READ_HHD_LOC_INV_TRAN_SETUP', 520, 'READ', 'HHD_LOC_INV_TRAN', 'setup', N'520_READ_HHD_LOC_INV_TRAN__setup.sql', 2),
  ('READ_HHD_LOC_INV_TRAN_MIGRATE', 521, 'READ', 'HHD_LOC_INV_TRAN', 'migrate', N'521_READ_HHD_LOC_INV_TRAN__migrate.sql', 5),
  ('READ_HHD_LOC_INV_TRAN_CHECK', 523, 'READ', 'HHD_LOC_INV_TRAN', 'check', N'523_READ_HHD_LOC_INV_TRAN__check.sql', 2),
  ('WO_CS_APPOINTMENT_SETUP', 530, 'WO', 'CS_APPOINTMENT', 'setup', N'530_WO_CS_APPOINTMENT__setup.sql', 4),
  ('WO_CS_APPOINTMENT_MIGRATE', 531, 'WO', 'CS_APPOINTMENT', 'migrate', N'531_WO_CS_APPOINTMENT__migrate.sql', 7),
  ('II_APPOINTMENT_SETUP', 532, 'II', 'APPOINTMENT', 'setup', N'532_II_APPOINTMENT__setup.sql', 2),
  ('II_APPOINTMENT_MIGRATE', 533, 'II', 'APPOINTMENT', 'migrate', N'533_II_APPOINTMENT__migrate.sql', 3),
  ('II_APPOINTMENT_DEVICE_SETUP', 534, 'II', 'APPOINTMENT_DEVICE', 'setup', N'534_II_APPOINTMENT_DEVICE__setup.sql', 1),
  ('II_APPOINTMENT_DEVICE_MIGRATE', 535, 'II', 'APPOINTMENT_DEVICE', 'migrate', N'535_II_APPOINTMENT_DEVICE__migrate.sql', 1),
  ('WO_WORK_RESULT_SETUP', 540, 'WO', 'WORK_RESULT', 'setup', N'540_WO_WORK_RESULT__setup.sql', 1),
  ('WO_WORK_RESULT_MIGRATE', 541, 'WO', 'WORK_RESULT', 'migrate', N'541_WO_WORK_RESULT__migrate.sql', 1),
  ('COMM_LOG_SETUP', 550, 'COMM', 'COMM_LOG', 'setup', N'550_COMM_LOG__setup.sql', 1),
  ('COMM_LOG_MIGRATE', 551, 'COMM', 'COMM_LOG', 'migrate', N'551_COMM_LOG__migrate.sql', 1),
  ('COMM_LOG_CHECK', 553, 'COMM', 'COMM_LOG', 'check', N'553_COMM_LOG__check.sql', 1),
  ('OPR_SYNC_CLIENT_SETUP', 560, 'OPR', 'SYNC_CLIENT', 'setup', N'560_OPR_SYNC_CLIENT__setup.sql', 2),
  ('OPR_SYNC_CLIENT_MIGRATE', 561, 'OPR', 'SYNC_CLIENT', 'migrate', N'561_OPR_SYNC_CLIENT__migrate.sql', 3),
  ('INVOICE_SETUP', 570, 'INV', 'INVOICE', 'setup', N'570_INVOICE__setup.sql', 3),
  ('INVOICE_MIGRATE', 571, 'INV', 'INVOICE', 'migrate', N'571_INVOICE__migrate.sql', 4),
  ('INVOICE_POST', 572, 'INV', 'INVOICE', 'post', N'572_INVOICE__post.sql', 1),
  ('INVOICE_CHECK', 573, 'INV', 'INVOICE', 'check', N'573_INVOICE__check.sql', 3),
  ('INVOICE_DEBT_PAYTRANS_SETUP', 574, 'INV', 'DEBT_PAYTRANS', 'setup', N'574_INVOICE_DEBT_PAYTRANS__setup.sql', 1),
  ('INVOICE_DEBT_PAYTRANS_MIGRATE', 575, 'INV', 'DEBT_PAYTRANS', 'migrate', N'575_INVOICE_DEBT_PAYTRANS__migrate.sql', 1),
  ('INVOICE_DEBT_PAYTRANS_POST', 576, 'INV', 'DEBT_PAYTRANS', 'post', N'576_INVOICE_DEBT_PAYTRANS__post.sql', 1),
  ('INVOICE_DEBT_PAYTRANS_CHECK', 577, 'INV', 'DEBT_PAYTRANS', 'check', N'577_INVOICE_DEBT_PAYTRANS__check.sql', 1),
  ('INVLINES_SETUP', 580, 'INV', 'INVLINES', 'setup', N'580_INVLINES__setup.sql', 2),
  ('INVLINES_MIGRATE', 581, 'INV', 'INVLINES', 'migrate', N'581_INVLINES__migrate.sql', 4),
  ('INVLINES_POST', 582, 'INV', 'INVLINES', 'post', N'582_INVLINES__post.sql', 1),
  ('INVLINES_CHECK', 583, 'INV', 'INVLINES', 'check', N'583_INVLINES__check.sql', 2),
  ('SPEFEE_SETUP', 584, 'INV', 'SPEFEE', 'setup', N'584_SPEFEE__setup.sql', 1),
  ('SPEFEE_MIGRATE', 585, 'INV', 'SPEFEE', 'migrate', N'585_SPEFEE__migrate.sql', 1),
  ('SPEFEE_CHECK', 586, 'INV', 'SPEFEE', 'check', N'586_SPEFEE__check.sql', 1),
  ('PROJECT_SETUP', 590, 'PRJ', 'PROJECT', 'setup', N'590_PROJECT__setup.sql', 1),
  ('PROJECT_MIGRATE', 591, 'PRJ', 'PROJECT', 'migrate', N'591_PROJECT__migrate.sql', 1),
  ('PROJECT_CHECK', 593, 'PRJ', 'PROJECT', 'check', N'593_PROJECT__check.sql', 1),
  ('PROJECTLINE_SETUP', 594, 'PRJ', 'PROJECTLINE', 'setup', N'594_PROJECTLINE__setup.sql', 1),
  ('PROJECTLINE_MIGRATE', 595, 'PRJ', 'PROJECTLINE', 'migrate', N'595_PROJECTLINE__migrate.sql', 1),
  ('PROJECTLINE_CHECK', 596, 'PRJ', 'PROJECTLINE', 'check', N'596_PROJECTLINE__check.sql', 1),
  ('LEGAL_LP_SETUP', 600, 'LEGAL', 'LP', 'setup', N'600_LEGAL_LP__setup.sql', 1),
  ('LEGAL_LP_MIGRATE', 601, 'LEGAL', 'LP', 'migrate', N'601_LEGAL_LP__migrate.sql', 1),
  ('LEGAL_LP_WIRE', 602, 'LEGAL', 'LP', 'wire', N'602_LEGAL_LP__wire.sql', 1),
  ('LEGAL_LP_CHECK', 603, 'LEGAL', 'LP', 'check', N'603_LEGAL_LP__check.sql', 1),
  ('INSTALLMENT_PLAN_SETUP', 610, 'INV', 'INSTALLMENT_PLAN', 'setup', N'610_INSTALLMENT_PLAN__setup.sql', 1),
  ('INSTALLMENT_PLAN_MIGRATE', 611, 'INV', 'INSTALLMENT_PLAN', 'migrate', N'611_INSTALLMENT_PLAN__migrate.sql', 2),
  ('INSTALLMENT_PLAN_CHECK', 612, 'INV', 'INSTALLMENT_PLAN', 'check', N'612_INSTALLMENT_PLAN__check.sql', 1),
  ('INSTALLMENT_TYPE_SETUP', 613, 'INV', 'INSTALLMENT_TYPE', 'setup', N'613_INSTALLMENT_TYPE__setup.sql', 1),
  ('INSTALLMENT_TYPE_MIGRATE', 614, 'INV', 'INSTALLMENT_TYPE', 'migrate', N'614_INSTALLMENT_TYPE__migrate.sql', 1),
  ('INSTALLMENT_INCOME_SETUP', 615, 'INV', 'INSTALLMENT_INCOME', 'setup', N'615_INSTALLMENT_INCOME__setup.sql', 1),
  ('INSTALLMENT_INCOME_MIGRATE', 616, 'INV', 'INSTALLMENT_INCOME', 'migrate', N'616_INSTALLMENT_INCOME__migrate.sql', 1),
  ('OPS_MIGLOG_CHECK', 900, 'OPS', 'MIGLOG', 'check', N'900_OPS_MIGLOG__check.sql', 1),
  ('OPS_AFTER_ADHOC', 910, 'OPS', 'AFTER', 'adhoc', N'910_OPS_AFTER__adhoc.sql', 1),
  ('OPS_LS001_HESAP', 920, 'OPS', 'LS001_HESAP', 'adhoc', N'920_OPS_LS001_HESAP__adhoc.sql', 1)
) AS s (SCRIPT_ID, SCRIPT_NO, DOMAIN, ENTITY, ROLE, FILE_NAME, EXPECTED_VERSION)
ON t.SCRIPT_ID = s.SCRIPT_ID
WHEN MATCHED THEN UPDATE SET
    SCRIPT_NO = s.SCRIPT_NO,
    DOMAIN = s.DOMAIN,
    ENTITY = s.ENTITY,
    ROLE = s.ROLE,
    FILE_NAME = s.FILE_NAME,
    EXPECTED_VERSION = s.EXPECTED_VERSION,
    IS_ACTIVE = 1
WHEN NOT MATCHED THEN INSERT (SCRIPT_ID, SCRIPT_NO, DOMAIN, ENTITY, ROLE, FILE_NAME, EXPECTED_VERSION, IS_ACTIVE)
VALUES (s.SCRIPT_ID, s.SCRIPT_NO, s.DOMAIN, s.ENTITY, s.ROLE, s.FILE_NAME, s.EXPECTED_VERSION, 1);
GO

PRINT 'MIG_SCRIPT_CATALOG seed OK';
GO
