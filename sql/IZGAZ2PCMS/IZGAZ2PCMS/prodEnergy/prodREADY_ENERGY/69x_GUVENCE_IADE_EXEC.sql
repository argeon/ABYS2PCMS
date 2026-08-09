/* ============================================================
   prodREADY_ENERGY / 69x_GUVENCE_IADE_EXEC
   Deploy + (sonra) EXEC hazirligi.
   Onkosul:
     1) Oracle O60 CTAS + dump → izgazMGR.LS_OV_GUVENCE_IADE_*
     2) energy.dbo.MIG_OV_ID_MAP (590 sonrasi)
   Dis BEGIN TRAN YASAK. Calisirken ALTER YASAK.
   #temp YOK. Staging: MIG_610_STG_*

   sqlcmd ornek (deploy):
     sqlcmd -S ... -d energy -U ... -P ... -C -I ^
       -i 60_GUVENCE_IADE_INSERT.sql ^
       -i 61_GUVENCE_IADE_WIRE.sql ^
       -i 62_GUVENCE_IADE_GATE.sql ^
       -i 69_GUVENCE_IADE_ALL.sql
   ============================================================ */
USE energy;
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET IMPLICIT_TRANSACTIONS OFF;
GO

RAISERROR('========== E610 — once 60/61/62/69 deploy et ==========', 0, 1) WITH NOWAIT;
GO

/* ---- ON-KOSUL SPOT ---- */
IF OBJECT_ID('dbo.SP_MIG_GUVENCE_IADE_ALL', 'P') IS NULL
BEGIN
    RAISERROR('SP_MIG_GUVENCE_IADE_ALL yok — 60→61→62→69 deploy et', 16, 1);
    RETURN;
END
GO

IF OBJECT_ID('izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVOICE', 'U') IS NULL
    RAISERROR('UYARI: izgazMGR.LS_OV_GUVENCE_IADE_INVOICE yok — O60 dump yok; EXEC etme', 10, 1) WITH NOWAIT;
ELSE
BEGIN
    DECLARE @c INT =
        (SELECT COUNT(*) FROM izgazMGR.dbo.LS_OV_GUVENCE_IADE_INVOICE WITH (NOLOCK));
    DECLARE @Msg NVARCHAR(200) = N'OV GUVENCE_IADE_INVOICE cnt=' + CAST(@c AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END
GO

/* ---- EXEC (hazir — simdilik KAPALI; satirlari acinca calisir) ----

FULL:
  EXEC energy.dbo.SP_MIG_GUVENCE_IADE_ALL
      @AGR_ID = NULL, @CLEAN = 1, @DEBUG = 1, @BatchSize = 20000;

Pilot:
  EXEC energy.dbo.SP_MIG_GUVENCE_IADE_ALL
      @AGR_ID = 2221, @CLEAN = 1, @DEBUG = 1, @BatchSize = 5000;

Resume:
  EXEC energy.dbo.SP_MIG_GUVENCE_IADE_ALL
      @AGR_ID = NULL, @CLEAN = 0, @DEBUG = 1, @BatchSize = 20000;
*/

-- EXEC energy.dbo.SP_MIG_GUVENCE_IADE_ALL
--     @AGR_ID = NULL,
--     @CLEAN  = 1,
--     @DEBUG  = 1,
--     @BatchSize = 20000;
-- GO
