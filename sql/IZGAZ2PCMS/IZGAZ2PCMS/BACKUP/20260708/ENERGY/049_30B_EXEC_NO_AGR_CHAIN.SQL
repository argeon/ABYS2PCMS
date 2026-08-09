/* =============================================================================
   prodREADY_ENERGY3007 / 30b_EXEC_NO_AGR_CHAIN.sql
   Sozlesmesiz tahakkuk + ACCOUNT tahsilat zinciri.

   @AGR_ID = -1  → ABYS_AGREEMENT_ID IS NULL (+ ABYS_ACCOUNT_ID IS NOT NULL)

   Sira: 571 → 581 → 575 → 590_ALL → 597_ALL → (sonra 35 @AGR_ID=-1)

   NOT:
     - 36_backfill_null_agr_owner.sql PRIMARY DEGIL (opsiyonel diag).
     - OWNERREF NULL kalir; kopru ABYS_ACCOUNT_ID.
     - 611/613 taksit NO_AGR disinda (AGREEMENT zorunlu).
     - NO_AGR yolu: 30b (@AGR_ID=-1). FULL (@AGR_ID=NULL) de NO_AGR satirlari alir.
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @AGR_ID BIGINT = -1;  -- NO_AGR sentinel (degistirme)

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + ' | NO_AGR CHAIN START (@AGR_ID=-1)';

IF OBJECT_ID('dbo.SP_MIGRATE_LS005_INVOICE', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_590_ALL', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_597_ALL', 'P') IS NULL
BEGIN
    RAISERROR('571/575/590/597 SP yok — 10f + overlay deploy', 16, 1);
    RETURN;
END

/* kalan NULL AGR (ACCOUNT dolu) */
SELECT
    COUNT_BIG(*) AS mgr_null_agr_with_account
FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
WHERE ABYS_AGREEMENT_ID IS NULL
  AND ABYS_ACCOUNT_ID IS NOT NULL;

PRINT '========== E1) 571 INVOICE NO_AGR ==========';
EXEC dbo.SP_MIGRATE_LS005_INVOICE
    @BATCH_SIZE = 50000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @AGR_ID     = @AGR_ID,
    @DEBUG      = 1;

PRINT '========== E2) 581 INVLINES ==========';
EXEC dbo.SP_MIGRATE_LS005_INVLINES
    @BATCH_SIZE = 100000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @RANGE_MODE = 'KEYSET',
    @DEBUG      = 1;

PRINT '========== E3) 575 DEBT PAYTRANS NO_AGR ==========';
EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
    @BATCH_SIZE = 50000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @AGR_ID     = @AGR_ID,
    @DEBUG      = 1;

PRINT '========== E4) 590_ALL NO_AGR (IADE/KISMI) ==========';
EXEC dbo.SP_MIG_590_ALL
    @AGR_ID = @AGR_ID,
    @CLEAN  = 1,
    @DEBUG  = 1;

PRINT '========== E5) 597_ALL NO_AGR (tahsilat ACCOUNT) ==========';
EXEC dbo.SP_MIG_597_ALL
    @AGR_ID = @AGR_ID,
    @CLEAN  = 1,
    @DEBUG  = 1;

SELECT
    SUM(CASE WHEN OWNERREF IS NULL THEN 1 ELSE 0 END) AS en_null_owner,
    COUNT(*) AS en_null_agr_inv,
    COUNT(DISTINCT ABYS_ACCOUNT_ID) AS en_distinct_account
FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)
WHERE ABYS_AGREEMENT_ID IS NULL
  AND ABYS_ACCOUNT_ID IS NOT NULL;

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + ' | NO_AGR CHAIN DONE';
PRINT 'Sonraki: 35_bankref_resolve_abys.sql @AGR_ID=-1 @DRY_RUN=0';
PRINT 'Not: 36 backfill PRIMARY DEGIL — dogrudan NO_AGR yolu kullanildi.';
GO
