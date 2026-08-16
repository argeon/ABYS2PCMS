/*
  20b_INVOICE_NCIX_DISABLE.sql  (R22 thin wrapper)
  ---------------------------------------------------------------
  Tercih: EXEC dbo.SP_MIG_597_NCIX_DISABLE @DEBUG=1;
  Bu dosya geriye uyumluluk — INV+PT NCIX OFF (tek SP).
*/
USE energy;
GO
EXEC dbo.SP_MIG_597_NCIX_DISABLE @DEBUG = 1;
GO
