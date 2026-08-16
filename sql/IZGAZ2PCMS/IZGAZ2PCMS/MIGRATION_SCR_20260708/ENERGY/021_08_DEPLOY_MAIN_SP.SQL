/* =============================================================================
   prodREADY_ENERGY / 08_DEPLOY_MAIN_SP
   Bu dosya CALISTIRILMAZ — sadece deploy checklist.

   Msg 2812 "Could not find stored procedure SP_MIGRATE_LS005_INVOICE"
   = asagidaki dosyalar energy DB'de henuz F5 edilmemis.

   Klasor: IZGAZ2PCMS/ProdIzgazMgr2Energy/prodENERGY/
   Her satiri SIRAYLA ac → F5 (USE energy icinde).
   =============================================================================

   Compat (TRY_CONVERT yoksa):
     SELECT name, compatibility_level FROM sys.databases WHERE name = N'energy';
     -- hedef >= 110 (onerilen 130/150). Gerekirse:
     -- ALTER DATABASE energy SET COMPATIBILITY_LEVEL = 150;

   [ ] 569_INVOICE_CLEAN_BY_AGR.sql      ★ AGR pilot / CLEAN chain
   [ ] 570_INVOICE__setup.sql
   [ ] 571_INVOICE__migrate.sql
         dogrula: SELECT OBJECT_ID('energy.dbo.SP_MIGRATE_LS005_INVOICE','P');

   [ ] 580_INVLINES__setup.sql
   [ ] 581_INVLINES__migrate.sql
         dogrula: SELECT OBJECT_ID('energy.dbo.SP_MIGRATE_LS005_INVLINES','P');

   [ ] 574_INVOICE_DEBT_PAYTRANS__setup.sql
   [ ] 575_INVOICE_DEBT_PAYTRANS__migrate.sql
         dogrula: SELECT OBJECT_ID('energy.dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS','P');

   Opsiyonel (clean/AGR):
   [ ] 569_INVOICE_CLEAN_BY_AGR.sql

   Sonra:
   [ ] 09_CLEAN_RESET_CHAIN.sql   (gerekirse)
   [ ] EXEC_ALL.sql

   Overlay SP (ayri):
   [ ] 10_590_INSERT → 11_590_WIRE → 12_590_GATE → 19_590_ALL
   [ ] 20_597_INSERT → 21_597_WIRE → 22_597_GATE → 29_597_ALL
*/
PRINT '08_DEPLOY_MAIN_SP: checklist only — ProdIzgazMgr2Energy/prodENERGY dosyalarini F5 et';
GO
