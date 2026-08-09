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
PRINT '   10_590_INSERT → 11_590_WIRE → 12_590_GATE → 19_590_ALL';
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
PRINT 'Sonra: 30_EXEC_FINANCIAL_CHAIN.sql  (@AGR_ID set)';
PRINT 'Validate: 90_afl_frk/95 → 99 → 97 @OnlyDiff=1';
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
    (N'SP_MIG_590_GATE'),
    (N'SP_MIG_590_ALL'),
    (N'SP_MIG_597_INSERT'),
    (N'SP_MIG_597_WIRE'),
    (N'SP_MIG_597_GATE'),
    (N'SP_MIG_597_ALL'),
    (N'SP_MIGRATE_LS005_INSTALLMENT_PLAN'),
    (N'SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE'),
    (N'SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR'),
    (N'SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR')
) v(name)
ORDER BY
    CASE name
        WHEN N'SP_MIGRATE_LS005_INVOICE' THEN 1
        WHEN N'SP_MIGRATE_LS005_INVLINES' THEN 2
        WHEN N'SP_MIGRATE_LS005_DEBT_PAYTRANS' THEN 3
        WHEN N'SP_MIG_590_ALL' THEN 4
        WHEN N'SP_MIG_597_ALL' THEN 5
        ELSE 9
    END, name;

SELECT name AS STG
FROM sys.tables
WHERE name LIKE 'MIG_611_STG_%' OR name LIKE 'MIG_613_STG_%' OR name LIKE 'MIG_40_STG_%'
ORDER BY 1;
GO
