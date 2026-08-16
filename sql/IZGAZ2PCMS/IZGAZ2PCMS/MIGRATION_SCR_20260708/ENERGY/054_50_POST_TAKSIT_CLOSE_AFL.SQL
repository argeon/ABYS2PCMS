-- =============================================================================
-- prodREADY_ENERGY3007 / 50_post_taksit_close_afl.sql
-- 611/613 taksit + 92 STG close + AFL soft check
-- Onkosul: 597 OK; CS_INSTALLMENT(_PLAN) izgazMGR'de
--          00e_taksit_staging.sql + 00e_mgr_cs_installment_indexes.sql
--          + 00e_energy_installment_plan_indexes.sql (IX_MIG_LS005_IP_AGR — 613 P0)
--          Asil EXEC: 50e_TAKSIT_EXECS.sql (E2b index gate + 613)
-- =============================================================================
USE energy;
GO
SET NOCOUNT ON;

DECLARE @AGR_ID BIGINT = NULL;  -- ornek: 197168
-- SET @AGR_ID = 197168;

IF OBJECT_ID('dbo.MIG_611_STG_IP_KEYS', 'U') IS NULL
   OR OBJECT_ID('dbo.MIG_613_STG_NEW', 'U') IS NULL
BEGIN
    RAISERROR('Taksit staging yok — once 00e_taksit_staging.sql', 16, 1);
    RETURN;
END

RAISERROR('========== E3007-50a) 611 WIRE (varsa) ==========', 0, 1) WITH NOWAIT;
PRINT 'AGR=' + CASE WHEN @AGR_ID IS NULL THEN 'FULL' ELSE CAST(@AGR_ID AS VARCHAR(20)) END;
IF OBJECT_ID('dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN', 'P') IS NOT NULL
    EXEC dbo.SP_MIGRATE_LS005_INSTALLMENT_PLAN @BATCH_SIZE=50000, @RESUME=1, @DEBUG=1;
ELSE IF OBJECT_ID('dbo.SP_MIG_INSTALLMENT_PLAN_INSERT_RANGE', 'P') IS NOT NULL
    RAISERROR('611 range SP var — tam migrate scriptini calistirin', 0, 1) WITH NOWAIT;
ELSE
    RAISERROR('611 SP yok — ProdIzgazMgr2Energy 611 deploy veya wizard pilot', 0, 1) WITH NOWAIT;

IF OBJECT_ID('dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE', 'P') IS NOT NULL
    EXEC dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE @AGR_ID = @AGR_ID, @DEBUG = 1;
GO

RAISERROR('========== E3007-50b) 613 SPLIT (varsa) ==========', 0, 1) WITH NOWAIT;
IF OBJECT_ID('dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR', 'P') IS NOT NULL
   AND OBJECT_ID('dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR', 'P') IS NOT NULL
BEGIN
    RAISERROR('613 SP mevcut — full split: ../../prodEnergy/80_613_taksit__STANDALONE.sql', 0, 1) WITH NOWAIT;
END
ELSE
    RAISERROR('613 SP eksik — installment debt split atlanabilir (pilot direct)', 0, 1) WITH NOWAIT;
GO

RAISERROR('========== E3007-50c) O57 PLAN_PAY APPLY ==========', 0, 1) WITH NOWAIT;
PRINT 'Calistir: 40_installment_plan_pay_apply.sql  (@DRY_RUN=0)';
GO

RAISERROR('========== E3007-50d) 92 STG CLOSE ==========', 0, 1) WITH NOWAIT;
PRINT 'Calistir: ../90_afl_frk/92_stg_inv_pay_close_apply.sql  (@DRY_RUN=0)';
IF OBJECT_ID('izgazMGR.dbo.LS_STG_INV_PAY_CLOSE', 'U') IS NOT NULL
    SELECT FIX_KIND, COUNT(*) CNT
      FROM izgazMGR.dbo.LS_STG_INV_PAY_CLOSE WITH (NOLOCK)
     GROUP BY FIX_KIND ORDER BY 1;
GO

RAISERROR('========== E3007-50e) AFL soft ==========', 0, 1) WITH NOWAIT;
IF OBJECT_ID('izgazMGR.dbo.LS_AFL_OPEN_DEBT', 'U') IS NOT NULL
    SELECT COUNT(*) AFL_CNT,
           COUNT(CASE WHEN MIG_IN_SCOPE=1 THEN 1 END) MIG_SCOPE,
           COUNT(CASE WHEN TAKSIT_DURUMU='T' THEN 1 END) TAKSIT_T
      FROM izgazMGR.dbo.LS_AFL_OPEN_DEBT WITH (NOLOCK);

PRINT '========== E3007-50 POST CHECKLIST DONE ==========';
GO
