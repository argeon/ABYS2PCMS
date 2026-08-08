/* =============================================================================
   597_AFTER_ALL_IMMEDIATE.sql — GATE PASS sonrasi HEMEN
   energy | Implicit Transactions OFF | Results to Text

   Sira (zaman kritik):
     A) Bu dosya adim 0–1 (GATE dogrula)
     B) EXEC SP_MIG_INVOICE_POST_INDEXES          -- 572
     C) sqlcmd/SSMS: 20c_PAYTRANS_NCIX_REBUILD.sql
     D) (opsiyonel baska pencere) 20a_597_TAH_MAP_FAST_FILL.sql
     E) taksit: 611 → 611b → 50e
   ============================================================================= */
USE energy;
SET NOCOUNT ON;
SET IMPLICIT_TRANSACTIONS OFF;
GO

IF EXISTS (
    SELECT 1 FROM sys.dm_exec_requests r
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.session_id <> @@SPID AND t.text LIKE N'%SP_MIG_597%'
)
BEGIN
    RAISERROR('597 hala kosuyor — bitmesini bekle', 16, 1);
    RETURN;
END
GO

RAISERROR('========== GATE / MAP ozet ==========', 0, 1) WITH NOWAIT;
SELECT
    (SELECT COUNT_BIG(*) FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
     WHERE OV_KIND = 'TAH_INV' AND ENERGY_LREF IS NOT NULL) AS en_tah_map,
    (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_OV_TAH_INVOICE WITH (NOLOCK)) AS mgr_tah,
    (SELECT COUNT_BIG(*) FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
     WHERE OV_KIND = 'PAY_PT' AND ENERGY_LREF IS NOT NULL) AS en_pay_map,
    (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_OV_PAY_PT WITH (NOLOCK)) AS mgr_pay;

EXEC dbo.SP_MIG_597_GATE @AGR_ID = NULL;
GO

RAISERROR('========== 572 INVOICE POST_INDEXES ==========', 0, 1) WITH NOWAIT;
EXEC dbo.SP_MIG_INVOICE_POST_INDEXES;
GO

RAISERROR('========== SIMDI 20c CALISTIR ==========', 0, 1) WITH NOWAIT;
RAISERROR('prodREADY_ENERGY/20c_PAYTRANS_NCIX_REBUILD.sql', 0, 1) WITH NOWAIT;
RAISERROR('Snapshot: 20260708/ENERGY/*20C*PAYTRANS*', 0, 1) WITH NOWAIT;
GO

RAISERROR('========== SONRA (opsiyonel) 20a MGR MAP — cutover bloklamaz ==========', 0, 1) WITH NOWAIT;
RAISERROR('========== TAKSIT: 611 → 611b → 50e (STG 611/613 hazir) ==========', 0, 1) WITH NOWAIT;
GO
