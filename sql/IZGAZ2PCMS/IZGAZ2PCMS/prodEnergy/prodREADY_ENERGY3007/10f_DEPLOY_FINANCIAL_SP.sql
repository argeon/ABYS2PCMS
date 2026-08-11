/* =============================================================================
   prodREADY_ENERGY3007 / 10f_DEPLOY_FINANCIAL_SP.sql
   Checklist — asıl deploy: sqlcmd ile asagidaki dosyalar SIRAYLA (energy).
   Bu dosya sadece sirayi basar; SP olusturmaz.
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;

PRINT '========== 10f DEPLOY FINANCIAL SP SIRASI ==========';
PRINT 'A) Setup (prodREADY_ENERGY/)';
PRINT '   00_log_setup.sql';
PRINT '   00_map_tables.sql';
PRINT '   00_abys_columns.sql';
PRINT '   01_linenr_smallint.sql';
PRINT 'B) Ana SP (BACKUP/ProdIzgazMgr2Energy/prodENERGY/ — arsiv)';
PRINT '   569_INVOICE_CLEAN_BY_AGR.sql';
PRINT '   570_INVOICE__setup.sql';
PRINT '   571_INVOICE__migrate.sql          → SP_MIGRATE_LS005_INVOICE';
PRINT '   580_INVLINES__setup.sql';
PRINT '   581_INVLINES__migrate.sql         → SP_MIGRATE_LS005_INVLINES';
PRINT '   574_INVOICE_DEBT_PAYTRANS__setup.sql';
PRINT '   575_INVOICE_DEBT_PAYTRANS__migrate.sql → SP_MIGRATE_LS005_DEBT_PAYTRANS';
PRINT 'C) Overlay 590 (prodREADY_ENERGY/)';
PRINT '   10_590_INSERT → 11_590_WIRE → 13_590_TAM_MAIN_CLOSE → 12_590_GATE → 19_590_ALL';
PRINT 'D) Overlay 597 v5 (prodREADY_ENERGY/)';
PRINT '   28_DEPLOY_597.sql  (= 00f → 20 → 21 → 00g → 22 → 29)  NOTES_597_V5';
PRINT '   Elle: 00f → 20 → 21 → 00g → 22 → 29';
PRINT 'D2) E610 TYPE110 (O60 dump şart)';
PRINT '   60_GUVENCE_IADE_INSERT → 61_WIRE → 62_GATE → 69_ALL → 69x EXEC';
PRINT 'E) Taksit staging + SP';
PRINT '   prodREADY_ENERGY3007/00e_taksit_staging.sql  (+ MIG_613_ERR)';
PRINT '   prodREADY_ENERGY3007/00e_mgr_cs_installment_indexes.sql';
PRINT '   prodREADY_ENERGY3007/00e_energy_installment_plan_indexes.sql  -- 613 P0';
PRINT '   611_INSTALLMENT_PLAN__migrate.sql';
PRINT '   611b_INSTALLMENT_PLAN_WIRE_INVOICE__fix.sql';
PRINT '   prodREADY_ENERGY3007/613_INSTALLMENT_DEBT_SPLIT__pilot_agr.sql  (canonic v6)';
PRINT 'F) Post-613 apply SP (R12)';
PRINT '   prodREADY_ENERGY3007/40_installment_plan_pay_apply.sql  → SP_MIG_40_IPP_APPLY';
PRINT '   prodREADY_ENERGY3007/35_bankref_resolve_abys.sql        → SP_MIG_35_BANKREF_RESOLVE';
PRINT '   90_afl_frk/92_stg_inv_pay_close_apply.sql               → SP_MIG_92_STG_CLOSE';
PRINT 'G) MGR MAP clustered (R16) — dump+00b sonrasi';
PRINT '   prodREADY_ENERGY/00i_mgr_ov_id_map_clustered.sql';
PRINT 'H) IX / NCIX orch SP (R22) — dump sonrasi / 597 oncesi';
PRINT '   prodREADY_ENERGY/26_IX_PRECHECK.sql          → SP_MIG_IX_PRECHECK';
PRINT '   prodREADY_ENERGY/26a_IX_MGR_ENSURE.sql       → SP_MIG_IX_MGR_ENSURE';
PRINT '   prodREADY_ENERGY/26b_597_NCIX_DISABLE.sql    → SP_MIG_597_NCIX_DISABLE';
PRINT '   prodREADY_ENERGY/26c_597_NCIX_REBUILD.sql    → SP_MIG_597_NCIX_REBUILD';
PRINT '   prodREADY_ENERGY/26d_IX_IP_AGR.sql           → SP_MIG_IX_IP_AGR (611 sonrasi)';
PRINT 'I) Heal + FRK SP (R23)';
PRINT '   prodREADY_ENERGY/20e_597_PAY_PT_BAD_MAP_HEAL.sql → SP_MIG_20E_BAD_MAP_HEAL';
PRINT '   prodREADY_ENERGY/92_INV_DV_FROM_INCOME_HEAL.sql  → SP_MIG_INV_DV_FROM_INCOME';
PRINT '   prodREADY_ENERGY/93_AGR_FEE_COLLECTED_HEAL.sql   → SP_MIG_93_AGR_FEE_COLLECTED';
PRINT '   90_afl_frk/95_ttk_inv_afl_fatura_rapor.sql       → SP_MIG_95_TTK_AFL_RAPOR';
PRINT '   90_afl_frk/99_afl_vs_en_kalan_frk.sql            → SP_MIG_99_AFL_EN_FRK';
PRINT '   90_afl_frk/97_agr_frk_all.sql                    → SP_AGR_FRK_ALL';
PRINT 'Sonra: 30_EXEC_FINANCIAL_CHAIN.sql  (@AGR_ID set)';
PRINT 'Validate: EXEC SP_MIG_95 / 99 / SP_AGR_FRK_ALL @OnlyDiff=1';
PRINT 'Hizalama: ../PAKET_PATCH_HIZALAMA.md (patch/98_TEST zincire koyma)';
PRINT '====================================================';

SELECT
    name AS SP_NAME,
    CASE WHEN OBJECT_ID(N'dbo.' + name, N'P') IS NOT NULL THEN N'OK' ELSE N'MISSING' END AS STATUS
FROM (VALUES
    (N'SP_MIG_LOG_STEP'),
    (N'SP_MIG_CLEAN_INVOICE_CHAIN_BY_AGR'),
    (N'SP_MIGRATE_LS005_INVOICE'),
    (N'SP_MIGRATE_LS005_INVLINES'),
    (N'SP_MIGRATE_LS005_DEBT_PAYTRANS'),
    (N'SP_MIG_590_INSERT'),
    (N'SP_MIG_590_WIRE'),
    (N'SP_MIG_590_TAM_MAIN_CLOSE'),
    (N'SP_MIG_590_GATE'),
    (N'SP_MIG_590_ALL'),
    (N'SP_MIG_597_INSERT'),
    (N'SP_MIG_597_WIRE'),
    (N'SP_MIG_597_GATE'),
    (N'SP_MIG_597_ALL'),
    (N'SP_MIGRATE_LS005_INSTALLMENT_PLAN'),
    (N'SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE'),
    (N'SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR'),
    (N'SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR'),
    (N'SP_MIG_40_IPP_APPLY'),
    (N'SP_MIG_35_BANKREF_RESOLVE'),
    (N'SP_MIG_92_STG_CLOSE'),
    (N'SP_MIG_IX_PRECHECK'),
    (N'SP_MIG_IX_MGR_ENSURE'),
    (N'SP_MIG_597_NCIX_DISABLE'),
    (N'SP_MIG_597_NCIX_REBUILD'),
    (N'SP_MIG_IX_IP_AGR'),
    (N'SP_MIG_20E_BAD_MAP_HEAL'),
    (N'SP_MIG_INV_DV_FROM_INCOME'),
    (N'SP_MIG_93_AGR_FEE_COLLECTED'),
    (N'SP_MIG_95_TTK_AFL_RAPOR'),
    (N'SP_MIG_99_AFL_EN_FRK'),
    (N'SP_AGR_FRK_ALL')
) v(name)
ORDER BY
    CASE name
        WHEN N'SP_MIGRATE_LS005_INVOICE' THEN 1
        WHEN N'SP_MIGRATE_LS005_INVLINES' THEN 2
        WHEN N'SP_MIGRATE_LS005_DEBT_PAYTRANS' THEN 3
        WHEN N'SP_MIG_590_ALL' THEN 4
        WHEN N'SP_MIG_597_ALL' THEN 5
        WHEN N'SP_MIG_IX_PRECHECK' THEN 6
        WHEN N'SP_MIG_597_NCIX_DISABLE' THEN 7
        ELSE 9
    END, name;

SELECT name AS STG
FROM sys.tables
WHERE name LIKE 'MIG_611_STG_%' OR name LIKE 'MIG_613_STG_%' OR name LIKE 'MIG_40_STG_%'
ORDER BY 1;
GO
