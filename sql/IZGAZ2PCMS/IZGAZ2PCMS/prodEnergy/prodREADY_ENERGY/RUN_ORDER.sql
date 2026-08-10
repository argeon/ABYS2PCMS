/* =============================================================================
   prodREADY_ENERGY / RUN_ORDER

   DOGRU SIRA (energy):
     SETUP → 571 INVOICE → 581 INVLINES → 575 DEBT PT
       → sonra overlay SP_MIG_590_ALL → SP_MIG_597_ALL

   590/597 = eksilten/tahsilat OVERLAY (delta). Ana tahakkuk degil.
   Ana yukleme bitmeden 590 CALISTIRMA.

   v5 (CANCEL_REV + AFL): NOTES_597_V5_AFL_CANCEL_REV.md
     — CANCEL_REV sadece AFL acik; WIRE AFL heal; GATE kontrol
     — Tam yeniden aktarim oncesi 28_DEPLOY_597.sql

   KURAL
   - Overlay icin SADECE *_ALL EXEC (tek INSERT yasak).
   - GATE_FAIL / FAIL → DUR.
   ============================================================================= */

USE energy;
GO

/* =============================================================================
   A) SETUP — dosyalari SIRAYLA F5 (prodREADY_ENERGY/)
   =============================================================================
   1) 00_log_setup.sql
   2) 00_map_tables.sql
   2b) dump bitince: 00b_align_mgr_varchar.sql  (nvarchar→varchar — CAST/COLLATE kalkar)
   3) MAP kopyala:

        INSERT INTO energy.dbo.MIG_OV_ID_MAP (
            OV_KIND, SRC_KEY, LREF_HINT, PARENT_SRC_KEY, REF_MAIN_LREF,
            ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID, ABYS_ID_BUSINESS, ENERGY_LREF
        )
        SELECT
            OV_KIND, SRC_KEY, LREF_HINT, PARENT_SRC_KEY, REF_MAIN_LREF,
            ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID, ABYS_ID_BUSINESS, ENERGY_LREF
        FROM izgazMGR.dbo.LS_OV_ID_MAP s WITH (NOLOCK)
        WHERE NOT EXISTS (
            SELECT 1 FROM energy.dbo.MIG_OV_ID_MAP t
            WHERE t.SRC_KEY = s.SRC_KEY
        );

   4) 00_abys_columns.sql
   5) 01_linenr_smallint.sql
*/

/* =============================================================================
   B) MAIN MIGRATE — ONCE BUNLAR (ProdIzgazMgr2Energy/prodENERGY/)
      Deploy: 570+571, 580+581, 574+575  sonra EXEC
   ============================================================================= */

RAISERROR('========== B1) 571 INVOICE (ANA YUKLEME) ==========', 0, 1) WITH NOWAIT;
EXEC energy.dbo.SP_MIGRATE_LS005_INVOICE
    @BATCH_SIZE = 50000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @AGR_ID     = NULL,   -- FULL; pilot: @AGR_ID = 2221
    @DEBUG      = 1;
GO

RAISERROR('========== B2) 581 INVLINES (ANA YUKLEME) ==========', 0, 1) WITH NOWAIT;
EXEC energy.dbo.SP_MIGRATE_LS005_INVLINES
    @BATCH_SIZE = 100000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @RANGE_MODE = 'KEYSET',
    @DEBUG      = 1;
GO

RAISERROR('========== B3) 575 DEBT PAYTRANS (ANA YUKLEME) ==========', 0, 1) WITH NOWAIT;
-- Alternatif: Oracle O14 bulk — 575 ile BIRLIKTE YAPMA
EXEC energy.dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
    @BATCH_SIZE = 50000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @AGR_ID     = NULL,
    @DEBUG      = 1;
GO

RAISERROR('========== B OK — ana tahakkuk bitti; simdi 590 overlay ==========', 0, 1) WITH NOWAIT;
GO

/* =============================================================================
   C) 590 EKSILTEN OVERLAY — ancak B bittikten sonra
      Deploy SIRAYLA: 10 → 11 → 13_TAM_MAIN_CLOSE → 12 → 19_590_ALL
      ALL: INSERT → WIRE → TAM_MAIN_CLOSE → GATE
   ============================================================================= */

RAISERROR('========== C) 590 EKSILTEN OVERLAY ==========', 0, 1) WITH NOWAIT;
/* Deploy SIRAYLA: 10 → 11 → 13_TAM_MAIN_CLOSE → 12 → 19_590_ALL
   ALL icinde: INSERT → WIRE → TAM_MAIN_CLOSE → GATE */
EXEC energy.dbo.SP_MIG_590_ALL
    @AGR_ID = NULL,
    @CLEAN  = 1,
    @DEBUG  = 1;
GO
-- Pilot: EXEC energy.dbo.SP_MIG_590_ALL @AGR_ID=2221, @CLEAN=1, @DEBUG=1;

/* GATE_PASS / E590 OK olmadan 597'ye GECME */

/* =============================================================================
   D) 597 TAHSILAT OVERLAY — ancak C PASS sonrasi (v4 paket)
      Deploy: 28_DEPLOY_597.sql
        (= 00f → 20 → 21 → 00g → 22 → 29)
      Elle:   00f → 20 → 21 → 00g → 22 → 29
      Ops:    20b NCIX off → ALL → 20c rebuild
      Resume: 20a_597_TAH_MAP_FAST_FILL.sql (MAP null + INV dolu; FULL'a koyma)
      Kurallar: dis BEGIN TRAN YOK | calisan SP_MIG_597_* iken ALTER YOK
      Not: NOTES_597_PERF_SAFE.md
   ============================================================================= */

RAISERROR('========== D) 597 TAHSILAT OVERLAY ==========', 0, 1) WITH NOWAIT;
EXEC energy.dbo.SP_MIG_597_ALL
    @AGR_ID    = NULL,
    @CLEAN     = 1,
    @DEBUG     = 1,
    @BatchSize = 100000;
GO
-- Resume ornek:
--   sqlcmd -I -d energy -i 20a_597_TAH_MAP_FAST_FILL.sql
--   EXEC energy.dbo.SP_MIG_597_ALL @AGR_ID=NULL, @CLEAN=0, @DEBUG=1, @BatchSize=100000;

/* =============================================================================
   D2) E610 GÜVENCE BEDELİ İADE (TYPE 110) — O60 dump sonrasi
       Deploy: 60_GUVENCE_IADE_INSERT → 61_WIRE → 62_GATE → 69_ALL
       EXEC:   69x_GUVENCE_IADE_EXEC.sql (EXEC satirlari kapali — acinca calisir)
       Kurallar: #temp YOK | fiziki MIG_610_STG_* | dis TRAN YOK
   ============================================================================= */

-- RAISERROR('========== D2) E610 GUVENCE IADE TYPE110 ==========', 0, 1) WITH NOWAIT;
-- EXEC energy.dbo.SP_MIG_GUVENCE_IADE_ALL
--     @AGR_ID = NULL, @CLEAN = 1, @DEBUG = 1, @BatchSize = 20000;
-- GO

/* =============================================================================
   D3) TYPE109 DV HEAL — LS_001 düzeni (gelirden DV + CROSSREF tahsilat)
       Not: NOTES_CANLI §2b · 05:00 aktarım testi checklist
       Dosya: 92_INV_DV_FROM_INCOME_HEAL.sql  (@DryRun=1 önce; APPLY @DryRun=0)
       CTAS O10–O12 TOTAL_DV deploy + dump yapıldıysa Faz A hafif; Faz B yine kontrol
   ============================================================================= */

-- RAISERROR('========== D3) 92 INV DV FROM INCOME HEAL ==========', 0, 1) WITH NOWAIT;
-- :r prodREADY_ENERGY/92_INV_DV_FROM_INCOME_HEAL.sql
-- (veya sqlcmd -i …92_INV_DV_FROM_INCOME_HEAL.sql — önce DryRun=1)

/* =============================================================================
   D4) AGR FEE_COLLECTED — 109 Güvence + 86 Bağlantı tahsil
       Not: NOTES_CANLI §2c
       Dosya: 93_AGR_FEE_COLLECTED_HEAL.sql  (@DryRun=1 önce; APPLY @DryRun=0)
   ============================================================================= */

-- RAISERROR('========== D4) 93 AGR FEE_COLLECTED HEAL ==========', 0, 1) WITH NOWAIT;
-- :r prodREADY_ENERGY/93_AGR_FEE_COLLECTED_HEAL.sql

/* =============================================================================
   E) DOGRULAMA
   ============================================================================= */

EXEC energy.dbo.SP_MIG_LOG_STATUS;
GO
-- + CHECK_QUERIES_ENERGY.sql

/*
   Operatör: CUTOVER_ONE_PAGE.md · Gün: NOTES_CUTOVER_DAY_20260811.md
   Ozet:

   [ ] A setup (00_log, 00_map, MAP copy, 00_abys, 01_linenr)
   [ ] B1 EXEC SP_MIGRATE_LS005_INVOICE
   [ ] B2 EXEC SP_MIGRATE_LS005_INVLINES
   [ ] B3 EXEC SP_MIGRATE_LS005_DEBT_PAYTRANS
   [ ] C  deploy 10→11→13→12→19  + EXEC SP_MIG_590_ALL
       (13 = TAM_MAIN_CLOSE; ALL WIRE sonrasi otomatik)
   [ ] D  28_DEPLOY_597 (00f+20+21+00g+22+29) + 20b → ALL @BatchSize=250000 → 20c
   [ ]    resume: 20a + ALL @CLEAN=0
   [ ]    GATE_PASS (NOTES_597_V5 — CANCEL_REV)
   [ ] D2 O60 dump + deploy 60→69 + EXEC SP_MIG_GUVENCE_IADE_ALL (TYPE110)
   [ ] D3 92_INV_DV_FROM_INCOME_HEAL DryRun=1 → APPLY (NOTES §2b — 05:00 test)
   [ ] D4 93_AGR_FEE_COLLECTED_HEAL DryRun=1 → APPLY (NOTES §2c)
   [ ] E  SP_MIG_LOG_STATUS
   [ ] V  95 → 99 → 97 @OnlyDiff=1 (FRK okuma: NOTES_CANLI §okuma kurali)
   [ ] F  Acik kod — NOTES_CANLI (O20 ASIM | mahsup 162/1936)
          TAM MAIN close: E590 SP_MIG_590_TAM_MAIN_CLOSE (R20) — 98_TEST yalniz ad-hoc
          Spot: AGR 3 (TAM), 412056 (ASIM+emanet), INV 66081785 (CANCEL_REV)
          DV spot: OWNERREF 1200078 / INV 147401407 — TAH TOTAL=GT-DV
*/
