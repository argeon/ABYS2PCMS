/*
  20b_PAYTRANS_NCIX_DISABLE.sql  (R22 thin wrapper)
  ---------------------------------------------------------------
  Tercih: EXEC dbo.SP_MIG_597_NCIX_DISABLE @DEBUG=1;
  INV wrapper ile ayni SP — cift kosu idempotent (zaten disabled).
*/
USE energy;
GO
EXEC dbo.SP_MIG_597_NCIX_DISABLE @DEBUG = 1;
GO
