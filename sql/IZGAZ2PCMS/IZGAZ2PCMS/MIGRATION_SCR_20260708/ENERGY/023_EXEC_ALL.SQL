/* =============================================================================
   prodREADY_ENERGY / EXEC_ALL
   Sadece EXEC — once deploy/setup bitmis olmali.

   Yanlis sira / FK truncate hatasi → once:
     09_CLEAN_RESET_CHAIN.sql
   (PAYTRANS → INVLINES → INVOICE; TRUNCATE kullanma)

   Oncesinde (SSMS: her dosyayi energy DB'de F5 — SP yoksa Msg 2812):

     A) prodREADY_ENERGY/
        00_log_setup.sql
        00_map_tables.sql + MAP kopya
        00_abys_columns.sql
        01_linenr_smallint.sql

     B) ProdIzgazMgr2Energy/prodENERGY/  ★ EXEC oncesi zorunlu deploy
        570_INVOICE__setup.sql
        571_INVOICE__migrate.sql          → SP_MIGRATE_LS005_INVOICE
        580_INVLINES__setup.sql
        581_INVLINES__migrate.sql         → SP_MIGRATE_LS005_INVLINES
        574_INVOICE_DEBT_PAYTRANS__setup.sql
        575_INVOICE_DEBT_PAYTRANS__migrate.sql → SP_MIGRATE_LS005_DEBT_PAYTRANS
        (clean icin: 569_INVOICE_CLEAN_BY_AGR.sql opsiyonel)

     C) prodREADY_ENERGY/ overlay deploy (590 ONCESI)
        10→11→12→19
     D) 20→21→22→29 (597; 590 PASS sonrasi)

   Calistir: her GO blogunu ayri / veya hepsini sirayla.
   FAIL → DUR. 590 PASS olmadan 597 calistirma.
   ============================================================================= */
USE energy;
GO

/* ----- B1) ANA — INVOICE ----- */
EXEC dbo.SP_MIGRATE_LS005_INVOICE
    @BATCH_SIZE = 50000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @AGR_ID     = NULL,
    @DEBUG      = 1;
GO

/* ----- B2) ANA — INVLINES ----- */
EXEC dbo.SP_MIGRATE_LS005_INVLINES
    @BATCH_SIZE      = 100000,
    @RESUME          = 1,
    @HARD_RESET      = 0,
    @RANGE_MODE      = 'KEYSET',
    @SKIP_PERF_CHECK = 0,
    @DEBUG           = 1;
GO

/* ----- B3) ANA — DEBT PAYTRANS (O14 bulk kullandiysan bu blogu ATLA) ----- */
EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
    @BATCH_SIZE = 50000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @AGR_ID     = NULL,
    @DEBUG      = 1;
GO

/* ----- C) OVERLAY 590 EKSILTEN (deploy 19 sonrasi) ----- */
EXEC dbo.SP_MIG_590_ALL
    @AGR_ID = NULL,
    @CLEAN  = 1,
    @DEBUG  = 1;
GO

/* ----- D) OVERLAY 597 TAHSILAT (C GATE_PASS + deploy 29 sonrasi) ----- */
EXEC dbo.SP_MIG_597_ALL
    @AGR_ID = NULL,
    @CLEAN  = 1,
    @DEBUG  = 1;
GO

/* ----- E) LOG ----- */
EXEC dbo.SP_MIG_LOG_STATUS;
GO

/* =============================================================================
   PILOT (FULL yerine tek AGR — usttekileri yorumlayip bunlari kullan)

EXEC dbo.SP_MIGRATE_LS005_INVOICE        @BATCH_SIZE=50000, @RESUME=1, @AGR_ID=2221, @DEBUG=1;
EXEC dbo.SP_MIGRATE_LS005_INVLINES       @BATCH_SIZE=100000, @RESUME=1, @RANGE_MODE='KEYSET', @DEBUG=1;
EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS  @BATCH_SIZE=50000, @RESUME=1, @AGR_ID=2221, @DEBUG=1;
EXEC dbo.SP_MIG_590_ALL                  @AGR_ID=2221, @CLEAN=1, @DEBUG=1;
EXEC dbo.SP_MIG_597_ALL                  @AGR_ID=2221, @CLEAN=1, @DEBUG=1;
EXEC dbo.SP_MIG_LOG_STATUS;

   POST INDEX (istege bagli, ana migrate sonrasi / overlay oncesi veya sonrasi)
EXEC dbo.SP_MIG_INVOICE_POST_INDEXES;
EXEC dbo.SP_MIG_INVLINES_POST_INDEXES;
EXEC dbo.SP_MIG_DEBT_PAYTRANS_POST_INDEXES;
   ============================================================================= */
