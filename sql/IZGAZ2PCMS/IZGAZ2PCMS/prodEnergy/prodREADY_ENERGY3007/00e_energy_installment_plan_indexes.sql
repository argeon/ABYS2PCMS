/* =============================================================================
   prodREADY_ENERGY3007 / 00e_energy_installment_plan_indexes.sql
   energy — 613 AGR-loop seek destegi

   NOT (2026-08-05):
     613 FULL ~107k AGR × SERIAL SP. Her AGR'de
     LS_005_01_INSTALLMENT_PLAN WHERE ABYS_AGREEMENT_ID=@agr
     → ABYS_AGREEMENT_ID index YOK iken CLUSTERED FULL SCAN
       (~24k logical read / ~90ms sadece plan lookup).
     ~6 saat sonra ~14k AGR (~13%) iken kesildi.
     Bu index 613 BASLAMADAN once zorunlu (yoksa create).

   Onkosul: 611 INSERT bitmis olmali (tablo dolu → ONLINE create).
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121)
    + N' | 00e energy INSTALLMENT_PLAN indexes';

IF OBJECT_ID('dbo.LS_005_01_INSTALLMENT_PLAN', 'U') IS NULL
BEGIN
    RAISERROR('LS_005_01_INSTALLMENT_PLAN yok', 16, 1);
    RETURN;
END

/* P0: 613 normalize + split AGR seek */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.LS_005_01_INSTALLMENT_PLAN')
      AND name = N'IX_MIG_LS005_IP_AGR'
)
BEGIN
    RAISERROR('CREATE ONLINE IX_MIG_LS005_IP_AGR ...', 0, 1) WITH NOWAIT;
    CREATE NONCLUSTERED INDEX IX_MIG_LS005_IP_AGR
        ON dbo.LS_005_01_INSTALLMENT_PLAN (ABYS_AGREEMENT_ID)
        INCLUDE (
            LREF, PLAN_ID, ABYS_ID, ABYS_INSTALLMENT_ID, ISACTIVE,
            ABYS_CANCELLATION_DATE, ABYS_CANCEL_CAUSE_ID, ABYS_CANCELLATION_USER_ID,
            TOTAL_AMOUNT, INSTALLMENT_COUNT, ABYS_ORDER_NUMBER,
            PAYTRANS_REF, INVOICE_REF, ABYS_DUE_DATE, ABYS_EXPIRY_DATE
        )
        WITH (ONLINE = ON, MAXDOP = 24, SORT_IN_TEMPDB = ON);
    RAISERROR('OK IX_MIG_LS005_IP_AGR', 0, 1) WITH NOWAIT;
END
ELSE
    RAISERROR('SKIP IX_MIG_LS005_IP_AGR (exists)', 0, 1) WITH NOWAIT;

SELECT
    i.name,
    i.type_desc,
    i.has_filter
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('dbo.LS_005_01_INSTALLMENT_PLAN')
  AND i.name = N'IX_MIG_LS005_IP_AGR';

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121)
    + N' | 00e energy INSTALLMENT_PLAN indexes DONE';
GO
