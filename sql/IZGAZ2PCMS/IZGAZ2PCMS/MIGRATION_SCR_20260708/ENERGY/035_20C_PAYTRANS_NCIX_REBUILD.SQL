/*
  20c_PAYTRANS_NCIX_REBUILD.sql  (R22 thin wrapper)
  ---------------------------------------------------------------
  Tercih: EXEC dbo.SP_MIG_597_NCIX_REBUILD @DEBUG=1;
  (= 572 INV POST + PT NCIX REBUILD)
*/
USE energy;
GO
EXEC dbo.SP_MIG_597_NCIX_REBUILD @DEBUG = 1;
GO
