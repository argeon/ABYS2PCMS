/* =============================================================================
   prodREADY_ENERGY / RUN_ORDER

   DOGRU SIRA (energy) — R22 = SSMS_TAHSILAT tek otorite:
     FAZ1 IX: SP_MIG_IX_MGR_ENSURE → SP_MIG_IX_PRECHECK (FAIL=DUR)
     FAZ2: 571→572 → 581→582 → 575→576   ★ POST atlanamaz
     FAZ3: SP_MIG_590_ALL
     FAZ4: SP_MIG_597_NCIX_DISABLE → 597_ALL → GATE → probe → SP_MIG_597_NCIX_REBUILD
     FAZ5: 35 → 611 → SP_MIG_IX_IP_AGR → 613 → 40 → 92

   590/597 = eksilten/tahsilat OVERLAY (delta). Ana tahakkuk degil.
   Ana yukleme bitmeden 590 CALISTIRMA.

   v5 (CANCEL_REV + AFL): NOTES_597_V5_AFL_CANCEL_REV.md
     — CANCEL_REV sadece AFL acik; WIRE AFL heal; GATE kontrol
     — Tam yeniden aktarim oncesi 28_DEPLOY_597.sql

   KURAL
   - Cutover gunu: yalniz EXEC SP_* (deploy hariç .sql F5 yok).
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
   2c) dump bitince: 00i_mgr_ov_id_map_clustered.sql  (MGR LS_OV_ID_MAP HEAP→PK SRC_KEY — R16)
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
   6) Deploy once R22: 26 / 26a / 26b / 26c / 26d (+ 10f STATUS)
   7) EXEC SP_MIG_IX_MGR_ENSURE; EXEC SP_MIG_IX_PRECHECK;  -- FAIL=DUR
*/

/* =============================================================================
   A1) IX GATE (R22) — dump + MAP sonrası, 571 öncesi
   ============================================================================= */
RAISERROR('========== A1) SP_MIG_IX_MGR_ENSURE ==========', 0, 1) WITH NOWAIT;
EXEC energy.dbo.SP_MIG_IX_MGR_ENSURE @DEBUG = 1;
GO
RAISERROR('========== A1b) SP_MIG_IX_PRECHECK ==========', 0, 1) WITH NOWAIT;
EXEC energy.dbo.SP_MIG_IX_PRECHECK;
GO

/* =============================================================================
   B) MAIN MIGRATE — 571→572 → 581→582 → 575→576  (POST ★)
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
RAISERROR('========== B1b) 572 POST_INDEXES INVOICE ==========', 0, 1) WITH NOWAIT;
EXEC energy.dbo.SP_MIG_INVOICE_POST_INDEXES @DEBUG = 1;
GO

RAISERROR('========== B2) 581 INVLINES (ANA YUKLEME) ==========', 0, 1) WITH NOWAIT;
EXEC energy.dbo.SP_MIGRATE_LS005_INVLINES
    @BATCH_SIZE = 100000,
    @RESUME     = 1,
    @HARD_RESET = 0,
    @RANGE_MODE = 'KEYSET',
    @DEBUG      = 1;
GO
RAISERROR('========== B2b) 582 POST_INDEXES INVLINES ==========', 0, 1) WITH NOWAIT;
EXEC energy.dbo.SP_MIG_INVLINES_POST_INDEXES @DEBUG = 1;
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
RAISERROR('========== B3b) 576 POST_INDEXES PAYTRANS ==========', 0, 1) WITH NOWAIT;
EXEC energy.dbo.SP_MIG_DEBT_PAYTRANS_POST_INDEXES @DEBUG = 1;
GO

RAISERROR('========== B OK — ana tahakkuk + POST bitti; simdi 590 overlay ==========', 0, 1) WITH NOWAIT;
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
   D) 597 TAHSILAT OVERLAY — ancak C PASS sonrasi (v5 paket)
      Deploy: 28_DEPLOY_597.sql
        (= 00f → 20 → 21 → 00g → 22 → 29)
      Elle:   00f → 20 → 21 → 00g → 22 → 29

      R17+R22 ZORUNLU SIRA:
        1) EXEC SP_MIG_597_NCIX_DISABLE   (=eski 20b)
        2) SP_MIG_597_ALL  (@CLEAN=1 ilk FULL; resume/20e sonrasi @CLEAN=0)
        3) GATE: EXEC SP_MIG_597_GATE  (otorite; E597=FAIL panik yok)
        4) PROBE bad_map (asagida) — >0 → 20e → ALL @CLEAN=0 → tekrar probe
           ★ bad_map>0 iken @CLEAN=1 YASAK (map→PT DELETE borc siler)
        5) EXEC SP_MIG_597_NCIX_REBUILD  (=572 INV + eski 20c PT)

      Resume MAP: 20a_597_TAH_MAP_FAST_FILL.sql (FULL zincire koyma)
      Kurallar: dis BEGIN TRAN YOK | calisan SP_MIG_597_* iken ALTER YOK
      Not: NOTES_597_PERF_SAFE.md · NOTES_597_OPS_HEAL.md R15
   ============================================================================= */

RAISERROR('========== D0) SP_MIG_597_NCIX_DISABLE ==========', 0, 1) WITH NOWAIT;
EXEC energy.dbo.SP_MIG_597_NCIX_DISABLE @DEBUG = 1;
GO

RAISERROR('========== D) 597 TAHSILAT OVERLAY ==========', 0, 1) WITH NOWAIT;
EXEC energy.dbo.SP_MIG_597_ALL
    @AGR_ID    = NULL,
    @CLEAN     = 1,          -- ilk FULL; resume/20e: 0
    @DEBUG     = 1,
    @BatchSize = 250000;
GO

RAISERROR('========== D1) GATE + PROBE bad_map ==========', 0, 1) WITH NOWAIT;
EXEC energy.dbo.SP_MIG_597_GATE @AGR_ID = NULL;
GO
-- Bad PAY map (0 beklenir). >0 → 20e; sonra ALL @CLEAN=0 (CLEAN=1 YASAK)
SELECT COUNT_BIG(*) AS pay_map_to_debt
FROM energy.dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
JOIN energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK) ON pt.LREF = m.ENERGY_LREF
WHERE m.OV_KIND = 'PAY_PT' AND m.ENERGY_LREF IS NOT NULL AND pt.IOCODE = 0;
GO
-- >0 ise:
--   EXEC energy.dbo.SP_MIG_20E_BAD_MAP_HEAL @DRY_RUN=0;
--   EXEC energy.dbo.SP_MIG_597_ALL @AGR_ID=NULL, @CLEAN=0, @DEBUG=1, @BatchSize=250000;
--   probe tekrar → 0
-- Resume ornek (yorum):
--   sqlcmd -I -d energy -i 20a_597_TAH_MAP_FAST_FILL.sql
--   EXEC energy.dbo.SP_MIG_597_ALL @AGR_ID=NULL, @CLEAN=0, @DEBUG=1, @BatchSize=250000;

RAISERROR('========== D1b) SP_MIG_597_NCIX_REBUILD (probe=0 sonrasi) ==========', 0, 1) WITH NOWAIT;
EXEC energy.dbo.SP_MIG_597_NCIX_REBUILD @DEBUG = 1;
GO

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
   D3) TYPE109 DV HEAL — SP_MIG_INV_DV_FROM_INCOME (R23)
   ============================================================================= */

-- RAISERROR('========== D3) SP_MIG_INV_DV_FROM_INCOME ==========', 0, 1) WITH NOWAIT;
-- EXEC energy.dbo.SP_MIG_INV_DV_FROM_INCOME @DryRun = 1, @Agr = NULL;
-- EXEC energy.dbo.SP_MIG_INV_DV_FROM_INCOME @DryRun = 0, @Agr = NULL;

/* =============================================================================
   D4) AGR FEE_COLLECTED — SP_MIG_93_AGR_FEE_COLLECTED (R23)
   ============================================================================= */

-- RAISERROR('========== D4) SP_MIG_93_AGR_FEE_COLLECTED ==========', 0, 1) WITH NOWAIT;
-- EXEC energy.dbo.SP_MIG_93_AGR_FEE_COLLECTED @DryRun = 1, @Agr = NULL;
-- EXEC energy.dbo.SP_MIG_93_AGR_FEE_COLLECTED @DryRun = 0, @Agr = NULL;

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
   [ ] A1 deploy 26* + EXEC IX_MGR_ENSURE → IX_PRECHECK (R22)
   [ ] B1 571 → 572 POST
   [ ] B2 581 → 582 POST
   [ ] B3 575 → 576 POST
   [ ] C  deploy 10→11→13→12→19  + EXEC SP_MIG_590_ALL
       (13 = TAM_MAIN_CLOSE; ALL WIRE sonrasi otomatik)
   [ ] D  28_DEPLOY_597 (00f+20+21+00g+22+29)
   [ ]    NCIX_DISABLE → ALL @BatchSize=250000 → GATE → probe → NCIX_REBUILD
   [ ]    bad_map>0 → SP_MIG_20E_BAD_MAP_HEAL → ALL @CLEAN=0 (CLEAN=1 YASAK)
   [ ]    resume (MAP): 20a + ALL @CLEAN=0
   [ ]    GATE_PASS (NOTES_597_V5 — CANCEL_REV)
   [ ] F  611 → SP_MIG_IX_IP_AGR → 613
   [ ] D2 O60 dump + deploy 60→69 + EXEC SP_MIG_GUVENCE_IADE_ALL (TYPE110)
   [ ] D3 SP_MIG_INV_DV_FROM_INCOME DryRun=1 → 0
   [ ] D4 SP_MIG_93_AGR_FEE_COLLECTED DryRun=1 → 0
   [ ] E  SP_MIG_LOG_STATUS
   [ ] V  SP_MIG_95_TTK_AFL_RAPOR → SP_MIG_99_AFL_EN_FRK → SP_AGR_FRK_ALL @OnlyDiff=1
   [ ] F  Acik kod — NOTES_CANLI (O60 TYPE110 | R21 GUAR koşu/311)
          ~~O20 ASIM | mahsup 162/1936~~ DONE 2026-08-11
          TAM MAIN close: E590 SP_MIG_590_TAM_MAIN_CLOSE (R20) — 98_TEST yalniz ad-hoc
          Spot: AGR 3 (TAM), 412056 (ASIM+emanet), INV 66081785 (CANCEL_REV)
          DV spot: OWNERREF 1200078 / INV 147401407 — TAH TOTAL=GT-DV
*/
