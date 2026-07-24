/* ============================================================
   deploy_all.sql — GERİYE UYUMLULUK
   Tum SP olusturma icin tek giris:
     deploy_create_all_sps.sql
   ============================================================ */
USE energy;
GO

PRINT '>>> Yonlendiriliyor: deploy_create_all_sps.sql';
:r .\deploy_create_all_sps.sql
GO
