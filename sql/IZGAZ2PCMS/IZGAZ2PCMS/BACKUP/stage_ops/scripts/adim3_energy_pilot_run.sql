/* ============================================================
   FILE : adim3_energy_pilot_run.sql
   Tek AGR ornek (197168). Coklu set icin: adim_multi_agr_pilot_run.sql
   Onkosul : izgazMGR dump + energy LS_005_01_AGR yuklu
   ============================================================ */
USE energy;
GO

/* 0) CLEAN helper + setup deploy (bir kez) */
-- :r 569_INVOICE_CLEAN_BY_AGR.sql
-- :r 570_INVOICE__setup.sql
-- :r 571_INVOICE__migrate.sql
-- :r 574_INVOICE_DEBT_PAYTRANS__setup.sql
-- :r 575_INVOICE_DEBT_PAYTRANS__migrate.sql

/* 1) INVOICE — once sozlesme fatura zinciri temizlenir (AGREEMENT_NUMBER) */
EXEC energy.dbo.SP_MIGRATE_LS005_INVOICE
     @AGR_ID     = 197168,
     @RESUME     = 0,
     @HARD_RESET = 0,
     @BATCH_SIZE = 1000,
     @DEBUG      = 1;
GO

SELECT COUNT_BIG(*) AS INV_PILOT
FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
WHERE ABYS_AGREEMENT_ID = 197168
   OR OWNERREF = (
        SELECT TOP 1 LREF FROM energy.dbo.LS_005_01_AGR WITH (NOLOCK)
        WHERE AGREEMENT_NUMBER = '197168'
      );
-- beklenen: 259
GO

/* 2) BORC PAYTRANS — AGR resolve + onceki borc PT temiz + insert */
EXEC energy.dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
     @AGR_ID     = 197168,
     @RESUME     = 0,
     @HARD_RESET = 0,
     @BATCH_SIZE = 1000,
     @DEBUG      = 1;
GO

DECLARE @AGR_ID BIGINT = 197168;
SELECT
    (SELECT COUNT_BIG(*)
       FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
      WHERE ISNULL(IOCODE, 0) = 0
        AND ABYS_AGREEMENT_ID = @AGR_ID) AS SRC_INV,
    (SELECT COUNT_BIG(*)
       FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
      WHERE ISNULL(IOCODE, 0) = 0
        AND ABYS_ID IS NOT NULL
        AND ABYS_AGREEMENT_ID = @AGR_ID) AS TGT_DEBT_PT;
GO
