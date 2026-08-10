-- =============================================================================
-- prodREADY_ENERGY3007 / RUN_ORDER.sql
-- CTAS3007 → izgazMGR dump SONRASI ENERGY cutover
-- GATE_FAIL → DUR
-- Envanter: EXIT_MAP.md
-- =============================================================================

/*
  SIRA:
    ÖNKOŞUL  master/HHD (111…365, 521/524, 585) — EXIT_MAP §1–2; bu paket EXEC etmez
    00b  dump prep OV varchar     ../prodREADY_ENERGY/00b_align_mgr_varchar.sql
    00c  KISMI LINEEXP            ../prodREADY_ENERGY/00c_enrich_mgr_kismi_lineexp.sql
    00d  PAY_LREF / TAH ABYS indexes  00d_perf_bank_indexes.sql
    00e  taksit physical staging     00e_taksit_staging.sql + 00e_mgr_cs_installment_indexes.sql
                                     + 00e_energy_installment_plan_indexes.sql (613 P0 AGR IX)
    00   izgazMGR gate + checkpoint          (ENERGY'ye DOKUNMA)
    01   Pilot spot wizard (01_PILOT_SPOT.md)
    05   energy COLLATE CP1254 (05_collation_cp1254.sql) — bir kez, master + sqlcmd -I
    05b  column COLLATE CP1254 (05b_columns_cp1254.sql) — sqlcmd -I -d energy
    05c  izgazMGR COLLATE CP1254 (05c_izgazmgr_collation_cp1254.sql) — sqlcmd -I -d master
    10   ENERGY setup + MAP copy
         + ../prodREADY_ENERGY/00_log,00_map,00_abys,01_linenr + SP deploy
    28   597 v5 deploy  ../prodREADY_ENERGY/28_DEPLOY_597.sql  (CANCEL_REV)
    20   571 → 581 → 575
    30   590_ALL → 597_ALL  (@AGR_ID: NULL=FULL | >0 | -1)  GATE_PASS
    D2   E610 TYPE110  60→69 + EXEC (O60 dump şart) — NOTES_CANLI §4
    30b  NO_AGR zincir (@AGR_ID=-1): 571→575→590→597 — 36 backfill YOK
    35   BANKREF (@AGR_ID: NULL=FULL | >0 | -1)
    50   611/613 + AFL checklist
    40   IPP apply (40_installment_plan_pay_apply.sql)
    92   STG close (../90_afl_frk/92_stg_inv_pay_close_apply.sql)
    V    FRK gate: 95 → 99 → 97 @OnlyDiff=1 (96 = spot, paket kapısı değil)
    90   check queries
  Hizalama: ../PAKET_PATCH_HIZALAMA.md
  PATCH/TEST zincire koyma: hotfix/03-04, 91* residual, 98_TEST_*
  AÇIK KOD (heal yok): NOTES_CANLI O20 ASIM | TAM MAIN | mahsup IL
  NOT: FULL (@AGR_ID=NULL) serbest; NO_AGR ayrica 30b (-1) ile de kosulabilir.
*/

USE energy;
GO

PRINT '========== prodREADY_ENERGY3007 RUN_ORDER ==========';
PRINT '0) ÖNKOŞUL: master/HHD yüklü mü? EXIT_MAP.md §1–2 (221/302/521/524/…)';
PRINT '0b) ../prodREADY_ENERGY/00b_align_mgr_varchar.sql  (dump sonrası)';
PRINT '0c) ../prodREADY_ENERGY/00c_enrich_mgr_kismi_lineexp.sql';
PRINT '0d) 00d_perf_bank_indexes.sql (PAY_LREF + TAH ABYS + MAP) — 597 bank hiz';
PRINT '0e) 00e_taksit_staging.sql + 00e_mgr_cs_installment_indexes.sql + 00e_energy_installment_plan_indexes.sql — STG + 613 P0 AGR IX';
PRINT '1) sqlcmd -d izgazMGR -i 00_izgazmgr_gate_checkpoint.sql';
PRINT '2) Pilot: 01_PILOT_SPOT.md';
PRINT '3) 05_collation_cp1254.sql (sqlcmd -I -d master) — energy DB default CP1254';
PRINT '3b) 05b_columns_cp1254.sql (sqlcmd -I -d energy) — energy kolon CP1254';
PRINT '3c) 05c_izgazmgr_collation_cp1254.sql (sqlcmd -I -d master) — izgazMGR DB+kolon CP1254';
PRINT '4) ../prodREADY_ENERGY/00_log_setup.sql';
PRINT '5) ../prodREADY_ENERGY/00_map_tables.sql';
PRINT '6) 10_setup_and_map.sql  (MAP copy)';
PRINT '7) ../prodREADY_ENERGY/00_abys_columns.sql';
PRINT '8) ../prodREADY_ENERGY/01_linenr_smallint.sql';
PRINT '8f) 10f_DEPLOY_FINANCIAL_SP.sql (SP varlık) + sqlcmd deploy 571/590/597/611';
PRINT '8g) ../prodREADY_ENERGY/28_DEPLOY_597.sql  (597 v5 CANCEL_REV — NOTES_597_V5)';
PRINT '8h) E610 deploy 60→61→62→69 (O60 dump şart) — NOTES_CANLI §4 / RUN_ORDER D2';
PRINT '9) 30c_EXEC_FULL_CHAIN.sql  (@AGR_ID=NULL PROD TAM) — veya 30_EXEC / 20+30';
PRINT '9b) 30b_EXEC_NO_AGR_CHAIN (@AGR_ID=-1) — FULL sonrasi GEREKMEZ';
PRINT '9c) E610 EXEC SP_MIG_GUVENCE_IADE_ALL (69x) — O60 yoksa ATLA';
PRINT '10) 35_bankref_resolve_abys.sql @DRY_RUN=0 + @AGR_ID (NULL=FULL | >0 | -1)';
PRINT '11) 40_installment_plan_pay_apply.sql @DRY_RUN=0 + @AGR_ID';
PRINT '12) ../90_afl_frk/92_stg_inv_pay_close_apply.sql @DRY_RUN=0';
PRINT '13) VALIDATE: 95_ttk_inv_afl_fatura_rapor → 99_afl_vs_en_kalan → 97 SP_AGR_FRK_ALL @OnlyDiff=1';
PRINT '14) 90_check_queries.sql';
PRINT 'PATCH: hotfix/03-04 ve 98_TEST_* cutover zincirine KOYMA — PAKET_PATCH_HIZALAMA.md';
PRINT 'AÇIK KOD: NOTES_CANLI (O20 ASIM | TAM MAIN close | mahsup 162/1936) — heal ile kapatma';
PRINT 'YASAK kaldirildi: @AGR_ID=NULL FULL cutover 3007de serbest (NO_AGR: -1 veya FULL)';
PRINT 'Envanter: EXIT_MAP.md | Checklist: MANUAL_CHECKLIST.txt | Hizalama: ../PAKET_PATCH_HIZALAMA.md';
PRINT '====================================================';
GO
