/* ============================================================
   SCRIPT_ID : REF_BANK_POST
   SCRIPT_NO : 122
   FILE      : 122_REF_BANK__post.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- IT_BANK_PRM → MIG_LS_BANK_MAP yukleme (SP 33_ls_bank_setup icinde)
-- ============================================================
USE energy;
GO

EXEC dbo.SP_MIG_LS_BANK_LOAD_FROM_ABYS @TruncateExisting = 1;
GO

SELECT ACTION_TYPE, COUNT(*) AS SATIR
FROM energy.dbo.MIG_LS_BANK_MAP
GROUP BY ACTION_TYPE;
GO

