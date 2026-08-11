-- =============================================================================
-- prodREADY_ENERGY3007 / 40_installment_plan_pay_apply.sql
-- CREATE OR ALTER PROCEDURE dbo.SP_MIG_40_IPP_APPLY  (R12 2026-08-11)
-- CTAS O57 LS_INSTALLMENT_PLAN_PAY → ENERGY:
--   1) borç PT (INST_NR) PAID + banka/makbuz/tarih/XTYPE
--   2) mevcut TYPE=101 tahsilat (CROSSREF) PAID + banka (yoksa skip insert)
--   3) hepsi ödendiyse INVOICE CLOSED + LPD/BANKREF
-- Onkosul: 575 (veya 613 split) sonrası INST_NR>0 borç PT mevcut
--           00e_taksit_staging.sql → dbo.MIG_40_STG_IPP (physical)
-- @DRY_RUN=1 sayım; 0=apply
-- EXEC ornek:
--   EXEC dbo.SP_MIG_40_IPP_APPLY @DRY_RUN = 1, @AGR_ID = NULL;
--   EXEC dbo.SP_MIG_40_IPP_APPLY @DRY_RUN = 0, @AGR_ID = NULL;
-- =============================================================================
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_40_IPP_APPLY
    @DRY_RUN BIT = 1,
    @AGR_ID  BIGINT = NULL   -- NULL=FULL | >0=AGR (taksit; -1 genelde yok)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Prefix  SYSNAME = N'LS_005_01';
    DECLARE @N INT;
    DECLARE @DryRunInt INT;
    DECLARE @sql NVARCHAR(MAX);

    IF OBJECT_ID('izgazMGR.dbo.LS_INSTALLMENT_PLAN_PAY', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR.LS_INSTALLMENT_PLAN_PAY yok — CTAS O57 dump', 16, 1);
        RETURN;
    END

    DECLARE @Inv SYSNAME = @Prefix + N'_INVOICE';
    DECLARE @Pt  SYSNAME = @Prefix + N'_PAYTRANS';

    IF OBJECT_ID(N'dbo.' + @Inv, N'U') IS NULL OR OBJECT_ID(N'dbo.' + @Pt, N'U') IS NULL
    BEGIN
        RAISERROR('ENERGY invoice/paytrans yok', 16, 1);
        RETURN;
    END

    IF OBJECT_ID('dbo.MIG_40_STG_IPP', 'U') IS NULL
    BEGIN
        RAISERROR('MIG_40_STG_IPP yok — once 00e_taksit_staging.sql', 16, 1);
        RETURN;
    END

    TRUNCATE TABLE dbo.MIG_40_STG_IPP;
    INSERT INTO dbo.MIG_40_STG_IPP (
        INSTALLMENT_ID, INST_NR, AGREEMENT_ID, MAIN_LREF, ACCOUNT_ID,
        PAYMENT_DATE, BANKREF, BANK_RECORD_REF, PAYTYPE, XTYPE, AMOUNT
    )
    SELECT
        CAST(ipp.INSTALLMENT_ID AS BIGINT),
        CAST(ipp.ORDER_NUMBER AS INT),
        CAST(ipp.AGREEMENT_ID AS BIGINT),
        CAST(ipp.MAIN_LREF AS INT),
        CAST(ipp.ACCOUNT_ID AS BIGINT),
        ipp.PAYMENT_DATE,
        ipp.BANKREF,
        CAST(ipp.BANK_RECORD_REF AS NVARCHAR(50)),
        CAST(ISNULL(ipp.PAYTYPE, 174) AS INT),
        CAST(ISNULL(ipp.XTYPE, 1) AS INT),
        CONVERT(DECIMAL(18,2), ISNULL(ipp.AMOUNT,0))
    FROM izgazMGR.dbo.LS_INSTALLMENT_PLAN_PAY ipp WITH (NOLOCK)
    WHERE ISNULL(ipp.IS_PAID, 0) = 1
      AND ipp.PAYMENT_DATE IS NOT NULL
      AND ISNULL(ipp.ORDER_NUMBER, 0) > 0
      AND (@AGR_ID IS NULL OR ipp.AGREEMENT_ID = @AGR_ID);

    SELECT @N = COUNT(*) FROM dbo.MIG_40_STG_IPP;
    SET @DryRunInt = CAST(@DRY_RUN AS INT);
    RAISERROR('IPP paid candidates=%d DRY_RUN=%d', 0, 1, @N, @DryRunInt) WITH NOWAIT;

    IF @DRY_RUN = 1
    BEGIN
        SELECT TOP 50 * FROM dbo.MIG_40_STG_IPP ORDER BY AGREEMENT_ID, INSTALLMENT_ID, INST_NR;
        RETURN;
    END

    DECLARE @HasBankRec BIT = CASE WHEN COL_LENGTH('dbo.' + @Pt, 'BANK_RECORD_REF') IS NOT NULL THEN 1 ELSE 0 END;
    DECLARE @HasXtype   BIT = CASE WHEN COL_LENGTH('dbo.' + @Pt, 'XTYPE') IS NOT NULL THEN 1 ELSE 0 END;
    DECLARE @HasLpd     BIT = CASE WHEN COL_LENGTH('dbo.' + @Pt, 'LASTPAIDDATE') IS NOT NULL THEN 1 ELSE 0 END;

    /* ---- 1) Borç PT PAID + banka ---- */
    SET @sql = N'
UPDATE pt SET
  pt.PAID = pt.PAYABLETOTAL,
  pt.PAYTYPE = COALESCE(NULLIF(pt.PAYTYPE,0), 120),
  pt.BANKREF = COALESCE(ipp.BANKREF, pt.BANKREF)'
  + CASE WHEN @HasLpd = 1 THEN N',
  pt.LASTPAIDDATE = COALESCE(ipp.PAYMENT_DATE, pt.LASTPAIDDATE)' ELSE N'' END
  + CASE WHEN @HasBankRec = 1 THEN N',
  pt.BANK_RECORD_REF = COALESCE(ipp.BANK_RECORD_REF, pt.BANK_RECORD_REF)' ELSE N'' END
  + CASE WHEN @HasXtype = 1 THEN N',
  pt.XTYPE = COALESCE(pt.XTYPE, ipp.XTYPE, 1)' ELSE N'' END
  + N'
FROM dbo.' + QUOTENAME(@Pt) + N' pt
INNER JOIN dbo.' + QUOTENAME(@Inv) + N' inv ON inv.LREF = pt.INVOICEREF
INNER JOIN dbo.MIG_40_STG_IPP ipp
  ON ipp.INST_NR = pt.INST_NR
 AND (
      (ipp.MAIN_LREF IS NOT NULL AND inv.LREF = ipp.MAIN_LREF)
   OR (ipp.ACCOUNT_ID IS NOT NULL AND inv.ABYS_ACCOUNT_ID = ipp.ACCOUNT_ID)
   OR (inv.ABYS_INSTALLMENT_ID = ipp.INSTALLMENT_ID)
   OR (inv.INSTALLMENT_PLAN_REF = ipp.INSTALLMENT_ID)
 )
WHERE pt.IOCODE = 0 AND ISNULL(pt.CANCELED,0)=0
  AND pt.INST_NR > 0
  AND (@agr IS NULL OR inv.OWNERREF = @agr OR inv.ABYS_AGREEMENT_ID = @agr)
OPTION (RECOMPILE, MAXDOP 8);';

    EXEC sp_executesql @sql, N'@agr BIGINT', @agr = @AGR_ID;
    SET @N = @@ROWCOUNT;
    RAISERROR('debt PT paid/bank updated=%d', 0, 1, @N) WITH NOWAIT;

    /* ---- 2) Mevcut tahsilat (CROSSREF) PAID + banka — TYPE=101 grain ---- */
    SET @sql = N'
UPDATE pay SET
  pay.PAID = pay.PAYABLETOTAL,
  pay.PAYTYPE = COALESCE(NULLIF(pay.PAYTYPE,0), 174),
  pay.BANKREF = COALESCE(ipp.BANKREF, pay.BANKREF)'
  + CASE WHEN @HasLpd = 1 THEN N',
  pay.LASTPAIDDATE = COALESCE(ipp.PAYMENT_DATE, pay.LASTPAIDDATE),
  pay.DATE_ = COALESCE(pay.DATE_, ipp.PAYMENT_DATE)' ELSE N'' END
  + CASE WHEN @HasBankRec = 1 THEN N',
  pay.BANK_RECORD_REF = COALESCE(ipp.BANK_RECORD_REF, pay.BANK_RECORD_REF)' ELSE N'' END
  + CASE WHEN @HasXtype = 1 THEN N',
  pay.XTYPE = COALESCE(pay.XTYPE, ipp.XTYPE, 1)' ELSE N'' END
  + N'
FROM dbo.' + QUOTENAME(@Pt) + N' debt
INNER JOIN dbo.' + QUOTENAME(@Inv) + N' inv ON inv.LREF = debt.INVOICEREF
INNER JOIN dbo.MIG_40_STG_IPP ipp
  ON ipp.INST_NR = debt.INST_NR
 AND (
      (ipp.MAIN_LREF IS NOT NULL AND inv.LREF = ipp.MAIN_LREF)
   OR (ipp.ACCOUNT_ID IS NOT NULL AND inv.ABYS_ACCOUNT_ID = ipp.ACCOUNT_ID)
   OR (inv.ABYS_INSTALLMENT_ID = ipp.INSTALLMENT_ID)
   OR (inv.INSTALLMENT_PLAN_REF = ipp.INSTALLMENT_ID)
 )
INNER JOIN dbo.' + QUOTENAME(@Pt) + N' pay
  ON pay.CROSSREF = debt.LREF AND pay.IOCODE = 1 AND ISNULL(pay.CANCELED,0)=0
WHERE debt.IOCODE = 0 AND ISNULL(debt.CANCELED,0)=0
  AND debt.INST_NR > 0
  AND (@agr IS NULL OR inv.OWNERREF = @agr OR inv.ABYS_AGREEMENT_ID = @agr)
OPTION (RECOMPILE, MAXDOP 8);';

    EXEC sp_executesql @sql, N'@agr BIGINT', @agr = @AGR_ID;
    SET @N = @@ROWCOUNT;
    RAISERROR('tahsilat PT (CROSSREF) paid/bank updated=%d', 0, 1, @N) WITH NOWAIT;

    /* ---- 3) Hepsi ödenen faturayı kapat ---- */
    SET @sql = N'
;WITH debt AS (
  SELECT inv.LREF AS INV_LREF, pt.INST_NR, pt.PAID, pt.PAYABLETOTAL,
         pt.LASTPAIDDATE AS LPD, pt.BANKREF
    FROM dbo.' + QUOTENAME(@Inv) + N' inv
   INNER JOIN dbo.' + QUOTENAME(@Pt) + N' pt
      ON pt.INVOICEREF = inv.LREF AND pt.IOCODE = 0 AND ISNULL(pt.CANCELED,0)=0
     AND pt.INST_NR > 0
   WHERE (@agr IS NULL OR inv.OWNERREF = @agr OR inv.ABYS_AGREEMENT_ID = @agr)
),
agg AS (
  SELECT INV_LREF, COUNT(*) N,
         SUM(CASE WHEN ISNULL(PAID,0)+0.01>=ISNULL(PAYABLETOTAL,0) THEN 1 ELSE 0 END) PAID_N
    FROM debt GROUP BY INV_LREF
),
lastPay AS (
  SELECT d.INV_LREF, d.BANKREF, d.LPD,
         ROW_NUMBER() OVER (PARTITION BY d.INV_LREF ORDER BY ISNULL(d.LPD,''19000101'') DESC, d.INST_NR DESC) rn
    FROM debt d
   WHERE ISNULL(d.PAID,0)+0.01>=ISNULL(d.PAYABLETOTAL,0)
)
UPDATE inv SET
  inv.CLOSED = 1,
  inv.LASTPAIDDATE = COALESCE(lp.LPD, inv.LASTPAIDDATE),
  inv.BANKREF = COALESCE(lp.BANKREF, inv.BANKREF)
FROM dbo.' + QUOTENAME(@Inv) + N' inv
INNER JOIN agg a ON a.INV_LREF = inv.LREF AND a.N>0 AND a.N=a.PAID_N
LEFT JOIN lastPay lp ON lp.INV_LREF = inv.LREF AND lp.rn=1
WHERE ISNULL(inv.CLOSED,0)=0
OPTION (RECOMPILE, MAXDOP 8);';
    EXEC sp_executesql @sql, N'@agr BIGINT', @agr = @AGR_ID;
    SET @N = @@ROWCOUNT;
    RAISERROR('invoices closed (all installments paid)=%d', 0, 1, @N) WITH NOWAIT;

    PRINT '========== E3007-40 IPP APPLY DONE ==========';
    PRINT 'Not: CROSSREF tahsilat yoksa wizard pilot veya 597 insert gerekir (bu script INSERT yapmaz).';
END
GO
/* Driver (SSMS / sqlcmd):
EXEC dbo.SP_MIG_40_IPP_APPLY @DRY_RUN = 1, @AGR_ID = NULL;
EXEC dbo.SP_MIG_40_IPP_APPLY @DRY_RUN = 0, @AGR_ID = NULL;
*/
