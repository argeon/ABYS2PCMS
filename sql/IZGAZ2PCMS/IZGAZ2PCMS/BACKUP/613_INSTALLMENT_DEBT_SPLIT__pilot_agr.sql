/* ============================================================
   SCRIPT_ID : INSTALLMENT_DEBT_SPLIT
   SCRIPT_NO : 613
   FILE      : 613_INSTALLMENT_DEBT_SPLIT__pilot_agr.sql
   VERSION   : 4
   ============================================================ */
-- v3: INV / INV_CANCEL seek (ISNULL+OR correlated scan kaldirildi)
-- v2: Iptal taksit PAYTRANS engeli
--   CS_INSTALLMENT cancel = CANCEL_CAUSE_ID | CANCELLATION_DATE | CANCELLATION_USER_ID
--   1) SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR
--        - taksit PT (INST_NR>0) soft-cancel
--        - ana borc PT INST_NR=0: CANCELED=0, PAID=0
--        - INVOICE.INSTALLMENT_PLAN_REF = NULL
--        - plan PAYTRANS_REF temizle; tahsilat CROSSREF → ana PT
--   2) SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR
--        - yalniz ISACTIVE=1 / iptal olmayan planlar
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------------------------------------
   Iptal plan normalize (split ONCESI)
------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR
    @AGR_ID BIGINT,
    @DEBUG  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @AGR_ID IS NULL
    BEGIN
        RAISERROR('SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR: @AGR_ID zorunlu.', 16, 1);
        RETURN;
    END

    DECLARE @Msg NVARCHAR(400), @N INT;

    /* Iptal PLAN_ID seti: energy plan ABYS alanlari + izgazMGR CS_INSTALLMENT */
    IF OBJECT_ID('dbo.MIG_613_STG_CANCEL_PLAN', 'U') IS NULL BEGIN RAISERROR('MIG_613_STG_* yok — once 00e_taksit_staging.sql', 16, 1); RETURN; END
    TRUNCATE TABLE dbo.MIG_613_STG_CANCEL_PLAN;

    INSERT INTO dbo.MIG_613_STG_CANCEL_PLAN (PLAN_ID)
    SELECT DISTINCT CAST(pl.PLAN_ID AS BIGINT)
    FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
    WHERE pl.ABYS_ID IS NOT NULL
      AND pl.ABYS_AGREEMENT_ID = @AGR_ID
      AND pl.PLAN_ID IS NOT NULL
      AND (
            pl.ABYS_CANCELLATION_DATE IS NOT NULL
         OR pl.ABYS_CANCEL_CAUSE_ID IS NOT NULL
         OR pl.ABYS_CANCELLATION_USER_ID IS NOT NULL
         OR ISNULL(pl.ISACTIVE, 0) = 0
          );

    IF OBJECT_ID('izgazMGR.dbo.CS_INSTALLMENT', 'U') IS NOT NULL
    BEGIN
        INSERT INTO dbo.MIG_613_STG_CANCEL_PLAN (PLAN_ID)
        SELECT DISTINCT CAST(ins.ID AS BIGINT)
        FROM izgazMGR.dbo.CS_INSTALLMENT ins WITH (NOLOCK)
        WHERE ins.AGREEMENT_ID = @AGR_ID
          AND (
                ins.CANCELLATION_DATE IS NOT NULL
             OR ins.CANCEL_CAUSE_ID IS NOT NULL
             OR ins.CANCELLATION_USER_ID IS NOT NULL
              )
          AND NOT EXISTS (
                SELECT 1 FROM dbo.MIG_613_STG_CANCEL_PLAN c WHERE c.PLAN_ID = CAST(ins.ID AS BIGINT)
              );
    END

    SET @N = (SELECT COUNT(*) FROM dbo.MIG_613_STG_CANCEL_PLAN);
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Iptal/muaccelle PLAN_ID=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    IF @N = 0
        RETURN;

    /* Iptal planina bagli faturalar — ISNULL/CAST join YOK (iki seek + UNION) */
    TRUNCATE TABLE dbo.MIG_613_STG_INV_CANCEL;

    INSERT INTO dbo.MIG_613_STG_INV_CANCEL (INV_LREF, PLAN_ID)
    SELECT inv.LREF, CAST(inv.ABYS_INSTALLMENT_ID AS BIGINT)
    FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    INNER JOIN dbo.MIG_613_STG_CANCEL_PLAN c ON c.PLAN_ID = inv.ABYS_INSTALLMENT_ID
    WHERE inv.ABYS_AGREEMENT_ID = @AGR_ID
      AND ISNULL(inv.IOCODE, 0) = 0
      AND inv.ABYS_INSTALLMENT_ID IS NOT NULL;

    INSERT INTO dbo.MIG_613_STG_INV_CANCEL (INV_LREF, PLAN_ID)
    SELECT inv.LREF, CAST(inv.INSTALLMENT_PLAN_REF AS BIGINT)
    FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    INNER JOIN dbo.MIG_613_STG_CANCEL_PLAN c ON c.PLAN_ID = inv.INSTALLMENT_PLAN_REF
    WHERE inv.ABYS_AGREEMENT_ID = @AGR_ID
      AND ISNULL(inv.IOCODE, 0) = 0
      AND inv.INSTALLMENT_PLAN_REF IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.MIG_613_STG_INV_CANCEL x WHERE x.INV_LREF = inv.LREF);

    SET @N = (SELECT COUNT(*) FROM dbo.MIG_613_STG_INV_CANCEL);
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Iptal fatura aday=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    IF @N = 0
        RETURN;

    /* Ana borc PT (INST_NR=0) — yoksa ilk borc PT */
    TRUNCATE TABLE dbo.MIG_613_STG_MAIN_PT;
    INSERT INTO dbo.MIG_613_STG_MAIN_PT (INV_LREF, PLAN_ID, MAIN_PT_LREF)
    SELECT
        i.INV_LREF,
        i.PLAN_ID,
        pt.LREF AS MAIN_PT_LREF
    FROM dbo.MIG_613_STG_INV_CANCEL i
    CROSS APPLY (
        SELECT TOP (1) p.LREF
        FROM energy.dbo.LS_005_01_PAYTRANS p WITH (NOLOCK)
        WHERE p.INVOICEREF = i.INV_LREF
          AND ISNULL(p.IOCODE, 0) = 0
          AND ISNULL(p.CANCELLATIONPAYMENT, 0) = 0
        ORDER BY
            CASE WHEN ISNULL(p.INST_NR, 0) = 0 THEN 0 ELSE 1 END,
            CASE WHEN ISNULL(p.CANCELED, 0) = 0 THEN 0 ELSE 1 END,
            p.LREF
    ) pt;

    BEGIN TRAN;

    /* 1) Taksit borc PT soft-cancel */
    UPDATE pt
    SET pt.CANCELED = 1
    FROM energy.dbo.LS_005_01_PAYTRANS pt
    INNER JOIN dbo.MIG_613_STG_INV_CANCEL i ON i.INV_LREF = pt.INVOICEREF
    WHERE ISNULL(pt.IOCODE, 0) = 0
      AND ISNULL(pt.INST_NR, 0) > 0
      AND ISNULL(pt.CANCELED, 0) = 0;

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Taksit PT CANCELED=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 2) Ana borc PT: CANCELED=0; PAID asagida odeme toplamindan yazilir */
    UPDATE pt
    SET pt.CANCELED = 0,
        pt.PAID = 0
    FROM energy.dbo.LS_005_01_PAYTRANS pt
    INNER JOIN dbo.MIG_613_STG_MAIN_PT m ON m.MAIN_PT_LREF = pt.LREF;

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Ana PT restore CANCELED=0 n=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 3) INSTALLMENT_PLAN_REF temizle */
    UPDATE inv
    SET inv.INSTALLMENT_PLAN_REF = NULL
    FROM energy.dbo.LS_005_01_INVOICE inv
    INNER JOIN dbo.MIG_613_STG_INV_CANCEL i ON i.INV_LREF = inv.LREF
    WHERE inv.INSTALLMENT_PLAN_REF IS NOT NULL;

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'INVOICE.INSTALLMENT_PLAN_REF NULL n=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 4) Plan PAYTRANS_REF temizle */
    UPDATE pl
    SET pl.PAYTRANS_REF = NULL
    FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl
    INNER JOIN dbo.MIG_613_STG_CANCEL_PLAN c ON c.PLAN_ID = pl.PLAN_ID
    WHERE pl.ABYS_AGREEMENT_ID = @AGR_ID
      AND pl.PAYTRANS_REF IS NOT NULL;

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Plan PAYTRANS_REF clear n=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 5) Tahsilat CROSSREF: taksit PT → ana PT */
    UPDATE pay
    SET pay.CROSSREF = m.MAIN_PT_LREF,
        pay.INST_NR = 0
    FROM energy.dbo.LS_005_01_PAYTRANS pay
    INNER JOIN dbo.MIG_613_STG_MAIN_PT m ON 1 = 1
    INNER JOIN energy.dbo.LS_005_01_PAYTRANS debt
        ON debt.LREF = pay.CROSSREF
       AND debt.INVOICEREF = m.INV_LREF
       AND ISNULL(debt.INST_NR, 0) > 0
    WHERE ISNULL(pay.IOCODE, 0) = 1
      AND ISNULL(pay.CANCELED, 0) = 0
      AND pay.CROSSREF IS NOT NULL
      AND pay.CROSSREF <> m.MAIN_PT_LREF;

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Tahsilat CROSSREF → ana PT n=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 6) Ana borc PAID = bagli tahsilat toplami (597 yeniden kosmasa da ÖDENDİ) */
    UPDATE pt
    SET pt.PAID = CONVERT(FLOAT, CONVERT(DECIMAL(18,2), ISNULL(s.SUM_AMT, 0)))
    FROM energy.dbo.LS_005_01_PAYTRANS pt
    INNER JOIN dbo.MIG_613_STG_MAIN_PT m ON m.MAIN_PT_LREF = pt.LREF
    OUTER APPLY (
        SELECT SUM(CONVERT(DECIMAL(18,2), ISNULL(pay.PAYABLETOTAL, 0))) AS SUM_AMT
        FROM energy.dbo.LS_005_01_PAYTRANS pay WITH (NOLOCK)
        WHERE pay.CROSSREF = m.MAIN_PT_LREF
          AND ISNULL(pay.IOCODE, 0) = 1
          AND ISNULL(pay.CANCELED, 0) = 0
          AND ISNULL(pay.CANCELLATIONPAYMENT, 0) = 0
    ) s;

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Ana PT PAID from payments n=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 7) Tam odeme → INVOICE.CLOSED=1 */
    UPDATE inv
    SET inv.CLOSED = CAST(1 AS BIT)
    FROM energy.dbo.LS_005_01_INVOICE inv
    INNER JOIN dbo.MIG_613_STG_MAIN_PT m ON m.INV_LREF = inv.LREF
    INNER JOIN energy.dbo.LS_005_01_PAYTRANS pt
        ON pt.LREF = m.MAIN_PT_LREF
    WHERE ISNULL(inv.CANCELED, 0) = 0
      AND ISNULL(inv.CLOSED, 0) = 0
      AND CONVERT(DECIMAL(18,2), ISNULL(pt.PAID, 0)) + 0.01
          >= CONVERT(DECIMAL(18,2), ISNULL(inv.PAYABLETOTAL, 0));

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'INVOICE CLOSED from PAID n=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    COMMIT TRAN;

    IF @DEBUG = 1
        RAISERROR('SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR OK', 0, 1) WITH NOWAIT;
END
GO

/* ------------------------------------------------------------
   Aktif plan split (iptal/muaccelle HARIC)
------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR
    @AGR_ID    BIGINT,
    @DEBUG     BIT = 1,
    @DO_RESEED BIT = 0  -- 1: CHECKIDENT (yalniz pipeline sonunda bir kez)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @AGR_ID IS NULL
    BEGIN
        RAISERROR('@AGR_ID zorunlu.', 16, 1);
        RETURN;
    END

    DECLARE @Msg NVARCHAR(400), @N INT, @MaxLref INT;

    /* Plan → fatura wire (yalniz eksik varsa) */
    IF OBJECT_ID('dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE', 'P') IS NOT NULL
       AND EXISTS (
            SELECT 1
            FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
            WHERE pl.ABYS_AGREEMENT_ID = @AGR_ID
              AND pl.ABYS_ID IS NOT NULL
              AND pl.INVOICE_REF IS NULL
              AND pl.ABYS_INSTALLMENT_ID IS NOT NULL
       )
        EXEC dbo.SP_MIG_INSTALLMENT_PLAN_WIRE_INVOICE @AGR_ID = @AGR_ID, @DEBUG = @DEBUG;

    /* Aktif plan satirlari (AGR scoped) + tutar toplami — correlated OR YOK */
    IF OBJECT_ID('dbo.MIG_613_STG_CS_CANCEL', 'U') IS NULL BEGIN RAISERROR('MIG_613_STG_* yok — once 00e_taksit_staging.sql', 16, 1); RETURN; END
    TRUNCATE TABLE dbo.MIG_613_STG_CS_CANCEL;
    IF OBJECT_ID('izgazMGR.dbo.CS_INSTALLMENT', 'U') IS NOT NULL
        INSERT INTO dbo.MIG_613_STG_CS_CANCEL (ID)
        SELECT DISTINCT CAST(ins.ID AS BIGINT)
        FROM izgazMGR.dbo.CS_INSTALLMENT ins WITH (NOLOCK)
        WHERE ins.AGREEMENT_ID = @AGR_ID
          AND (
                ins.CANCELLATION_DATE IS NOT NULL
             OR ins.CANCEL_CAUSE_ID IS NOT NULL
             OR ins.CANCELLATION_USER_ID IS NOT NULL
              );

    TRUNCATE TABLE dbo.MIG_613_STG_ACTIVE_PL;
    INSERT INTO dbo.MIG_613_STG_ACTIVE_PL (PLAN_LREF, PLAN_ID, ABYS_INSTALLMENT_ID, TOTAL_AMOUNT)
    SELECT
        pl.LREF AS PLAN_LREF,
        CAST(pl.PLAN_ID AS BIGINT) AS PLAN_ID,
        CAST(pl.ABYS_INSTALLMENT_ID AS BIGINT) AS ABYS_INSTALLMENT_ID,
        CONVERT(DECIMAL(18,2), pl.TOTAL_AMOUNT) AS TOTAL_AMOUNT
    FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
    WHERE pl.ABYS_AGREEMENT_ID = @AGR_ID
      AND pl.ABYS_ID IS NOT NULL
      AND ISNULL(pl.ISACTIVE, 0) = 1
      AND pl.ABYS_CANCELLATION_DATE IS NULL
      AND pl.ABYS_CANCEL_CAUSE_ID IS NULL
      AND pl.ABYS_CANCELLATION_USER_ID IS NULL
      AND NOT EXISTS (
            SELECT 1 FROM dbo.MIG_613_STG_CS_CANCEL c
            WHERE c.ID = ISNULL(pl.ABYS_INSTALLMENT_ID, pl.PLAN_ID)
          );

    IF NOT EXISTS (SELECT 1 FROM dbo.MIG_613_STG_ACTIVE_PL)
        RETURN;

    TRUNCATE TABLE dbo.MIG_613_STG_PLAN_SUM;

    INSERT INTO dbo.MIG_613_STG_PLAN_SUM (PLAN_KEY, SUM_AMT)
    SELECT k.PLAN_KEY, SUM(k.TOTAL_AMOUNT)
    FROM (
        SELECT ABYS_INSTALLMENT_ID AS PLAN_KEY, TOTAL_AMOUNT
        FROM dbo.MIG_613_STG_ACTIVE_PL
        WHERE ABYS_INSTALLMENT_ID IS NOT NULL
        UNION ALL
        SELECT PLAN_ID, TOTAL_AMOUNT
        FROM dbo.MIG_613_STG_ACTIVE_PL
        WHERE PLAN_ID IS NOT NULL
          AND (ABYS_INSTALLMENT_ID IS NULL OR ABYS_INSTALLMENT_ID <> PLAN_ID)
    ) k
    GROUP BY k.PLAN_KEY;

    /* AGR faturalari (seek) — ISNULL join yok; iki yol UNION */
    TRUNCATE TABLE dbo.MIG_613_STG_INV;

    INSERT INTO dbo.MIG_613_STG_INV (
        INV_LREF, PLAN_ID, ABYS_AGREEMENT_ID, CLIENTREF, OWNERTYPE, INV_TYPE, CURID,
        DATE_, DUEDATE, TLTOTAL, CURTOTAL, TAX, GRANDTOTAL, CANCELED, ADDUSER, BN_TYPE, XTYPE,
        ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_ACCRUE_TYPE_ID, ABYS_REGISTER_ID
    )
    SELECT
        inv.LREF,
        CAST(inv.ABYS_INSTALLMENT_ID AS BIGINT),
        inv.ABYS_AGREEMENT_ID, inv.CLIENTREF, inv.OWNERTYPE, inv.[TYPE], inv.CURID,
        inv.DATE_, inv.DUEDATE, inv.TLTOTAL, inv.CURTOTAL, inv.TAX, inv.GRANDTOTAL,
        inv.CANCELED, inv.ADDUSER, inv.BN_TYPE, inv.XTYPE,
        inv.ABYS_ID, inv.ABYS_ACCOUNT_ID, inv.ABYS_ACTION_TYPE_ID, inv.ABYS_ACCRUE_TYPE_ID, inv.ABYS_REGISTER_ID
    FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    INNER JOIN dbo.MIG_613_STG_PLAN_SUM ps ON ps.PLAN_KEY = inv.ABYS_INSTALLMENT_ID
    WHERE inv.ABYS_AGREEMENT_ID = @AGR_ID
      AND inv.ABYS_INSTALLMENT_ID IS NOT NULL
      AND ISNULL(inv.IOCODE, 0) = 0
      AND ISNULL(inv.CANCELED, 0) = 0
      AND ISNULL(inv.PAYABLETOTAL, 0) > 0.01
      AND ABS(ISNULL(inv.PAYABLETOTAL, 0) - ps.SUM_AMT) <= 1.00
      AND NOT EXISTS (
            SELECT 1
            FROM energy.dbo.LS_005_01_PAYTRANS p WITH (NOLOCK)
            WHERE p.INVOICEREF = inv.LREF
              AND ISNULL(p.IOCODE, 0) = 0
              AND ISNULL(p.CANCELED, 0) = 0
              AND ISNULL(p.CANCELLATIONPAYMENT, 0) = 0
              AND ISNULL(p.INST_NR, 0) > 0
          );

    INSERT INTO dbo.MIG_613_STG_INV (
        INV_LREF, PLAN_ID, ABYS_AGREEMENT_ID, CLIENTREF, OWNERTYPE, INV_TYPE, CURID,
        DATE_, DUEDATE, TLTOTAL, CURTOTAL, TAX, GRANDTOTAL, CANCELED, ADDUSER, BN_TYPE, XTYPE,
        ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_ACCRUE_TYPE_ID, ABYS_REGISTER_ID
    )
    SELECT
        inv.LREF,
        CAST(inv.INSTALLMENT_PLAN_REF AS BIGINT),
        inv.ABYS_AGREEMENT_ID, inv.CLIENTREF, inv.OWNERTYPE, inv.[TYPE], inv.CURID,
        inv.DATE_, inv.DUEDATE, inv.TLTOTAL, inv.CURTOTAL, inv.TAX, inv.GRANDTOTAL,
        inv.CANCELED, inv.ADDUSER, inv.BN_TYPE, inv.XTYPE,
        inv.ABYS_ID, inv.ABYS_ACCOUNT_ID, inv.ABYS_ACTION_TYPE_ID, inv.ABYS_ACCRUE_TYPE_ID, inv.ABYS_REGISTER_ID
    FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    INNER JOIN dbo.MIG_613_STG_PLAN_SUM ps ON ps.PLAN_KEY = inv.INSTALLMENT_PLAN_REF
    WHERE inv.ABYS_AGREEMENT_ID = @AGR_ID
      AND inv.INSTALLMENT_PLAN_REF IS NOT NULL
      AND ISNULL(inv.IOCODE, 0) = 0
      AND ISNULL(inv.CANCELED, 0) = 0
      AND ISNULL(inv.PAYABLETOTAL, 0) > 0.01
      AND ABS(ISNULL(inv.PAYABLETOTAL, 0) - ps.SUM_AMT) <= 1.00
      AND NOT EXISTS (SELECT 1 FROM dbo.MIG_613_STG_INV x WHERE x.INV_LREF = inv.LREF)
      AND NOT EXISTS (
            SELECT 1
            FROM energy.dbo.LS_005_01_PAYTRANS p WITH (NOLOCK)
            WHERE p.INVOICEREF = inv.LREF
              AND ISNULL(p.IOCODE, 0) = 0
              AND ISNULL(p.CANCELED, 0) = 0
              AND ISNULL(p.CANCELLATIONPAYMENT, 0) = 0
              AND ISNULL(p.INST_NR, 0) > 0
          );

    SET @N = (SELECT COUNT(*) FROM dbo.MIG_613_STG_INV);
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Split aday fatura (aktif plan)=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    IF @N = 0
        RETURN;

    /* Orijinal tek borc PT */
    TRUNCATE TABLE dbo.MIG_613_STG_OLD_PT;
    INSERT INTO dbo.MIG_613_STG_OLD_PT (INV_LREF, PLAN_ID, OLD_PT_LREF, OLD_PAID)
    SELECT
        i.INV_LREF,
        i.PLAN_ID,
        pt.LREF AS OLD_PT_LREF,
        CONVERT(DECIMAL(18,2), ISNULL(pt.PAID, 0)) AS OLD_PAID
    FROM dbo.MIG_613_STG_INV i
    CROSS APPLY (
        SELECT TOP (1) p.*
        FROM energy.dbo.LS_005_01_PAYTRANS p WITH (NOLOCK)
        WHERE p.INVOICEREF = i.INV_LREF
          AND ISNULL(p.IOCODE, 0) = 0
          AND ISNULL(p.CANCELED, 0) = 0
          AND ISNULL(p.CANCELLATIONPAYMENT, 0) = 0
          AND ISNULL(p.INST_NR, 0) = 0
        ORDER BY p.LREF
    ) pt;

    BEGIN TRAN;

    /* 1) Orijinal PT iptal */
    UPDATE pt
    SET pt.CANCELED = 1
    FROM energy.dbo.LS_005_01_PAYTRANS pt
    INNER JOIN dbo.MIG_613_STG_OLD_PT o ON o.OLD_PT_LREF = pt.LREF;

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Orijinal borc PT CANCELED=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 2) Plan satirlari + FIFO PAID dagilimi (yalniz ISACTIVE=1) */
    TRUNCATE TABLE dbo.MIG_613_STG_NEW;
    ;WITH plan_rows AS (
        SELECT
            i.INV_LREF,
            i.PLAN_ID,
            o.OLD_PT_LREF,
            o.OLD_PAID,
            pl.LREF AS PLAN_LREF,
            CAST(ISNULL(pl.INSTALLMENT_COUNT, pl.ABYS_ORDER_NUMBER) AS INT) AS INST_NR,
            CONVERT(DECIMAL(18,2), pl.TOTAL_AMOUNT) AS INST_AMT,
            pl.ABYS_DUE_DATE,
            pl.ABYS_EXPIRY_DATE,
            i.CLIENTREF,
            i.OWNERTYPE,
            i.INV_TYPE,
            i.CURID,
            i.DATE_,
            i.DUEDATE,
            i.CANCELED,
            i.ADDUSER,
            i.BN_TYPE,
            i.XTYPE,
            i.ABYS_ID,
            i.ABYS_ACCOUNT_ID,
            i.ABYS_ACTION_TYPE_ID,
            i.ABYS_ACCRUE_TYPE_ID,
            i.ABYS_REGISTER_ID,
            i.ABYS_AGREEMENT_ID,
            ROW_NUMBER() OVER (
                PARTITION BY i.INV_LREF
                ORDER BY CAST(ISNULL(pl.INSTALLMENT_COUNT, pl.ABYS_ORDER_NUMBER) AS INT), pl.LREF
            ) AS RN
        FROM dbo.MIG_613_STG_INV i
        INNER JOIN dbo.MIG_613_STG_OLD_PT o ON o.INV_LREF = i.INV_LREF
        INNER JOIN energy.dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
            ON (pl.ABYS_INSTALLMENT_ID = i.PLAN_ID OR pl.PLAN_ID = i.PLAN_ID)
           AND pl.ABYS_ID IS NOT NULL
           AND ISNULL(pl.ISACTIVE, 0) = 1
    ),
    paid_fifo AS (
        SELECT
            p.*,
            SUM(p.INST_AMT) OVER (
                PARTITION BY p.INV_LREF
                ORDER BY p.RN
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS CUM_AMT
        FROM plan_rows p
    )
    INSERT INTO dbo.MIG_613_STG_NEW (
        INV_LREF, PLAN_ID, OLD_PT_LREF, OLD_PAID, PLAN_LREF, INST_NR, INST_AMT,
        ABYS_DUE_DATE, ABYS_EXPIRY_DATE, CLIENTREF, OWNERTYPE, INV_TYPE, CURID,
        DATE_, DUEDATE, CANCELED, ADDUSER, BN_TYPE, XTYPE,
        ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_ACCRUE_TYPE_ID,
        ABYS_REGISTER_ID, ABYS_AGREEMENT_ID, RN, CUM_AMT, NEW_PAID
    )
    SELECT
        f.INV_LREF, f.PLAN_ID, f.OLD_PT_LREF, f.OLD_PAID, f.PLAN_LREF, f.INST_NR, f.INST_AMT,
        f.ABYS_DUE_DATE, f.ABYS_EXPIRY_DATE, f.CLIENTREF, f.OWNERTYPE, f.INV_TYPE, f.CURID,
        f.DATE_, f.DUEDATE, f.CANCELED, f.ADDUSER, f.BN_TYPE, f.XTYPE,
        f.ABYS_ID, f.ABYS_ACCOUNT_ID, f.ABYS_ACTION_TYPE_ID, f.ABYS_ACCRUE_TYPE_ID,
        f.ABYS_REGISTER_ID, f.ABYS_AGREEMENT_ID, f.RN, f.CUM_AMT,
        CONVERT(DECIMAL(18,2),
            CASE
                WHEN f.OLD_PAID <= 0 THEN 0
                WHEN f.OLD_PAID >= f.CUM_AMT THEN f.INST_AMT
                WHEN f.OLD_PAID > f.CUM_AMT - f.INST_AMT
                    THEN f.OLD_PAID - (f.CUM_AMT - f.INST_AMT)
                ELSE 0
            END
        ) AS NEW_PAID
    FROM paid_fifo f;

    /* 3) N yeni borc PT */
    INSERT INTO energy.dbo.LS_005_01_PAYTRANS (
        INVOICEREF, INVLINEREF, DATE_, [TYPE], CLIENTREF, CLIENT_TYPE,
        IOCODE, TLTOTAL, PAID, DUEDATE, PAYTYPE, CURID, CURRATE, CURTOTAL,
        CROSSREF, TRANSTYPE, CANCELED, TAX, GRANDTOTAL,
        LINETYPE, INST_NR, DV, PAYABLETOTAL,
        ADDDATE, ADDUSER, CANCELLATIONPAYMENT, BN_TYPE, XTYPE, PAYCURID,
        EXPLAIN,
        ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_ACCRUE_TYPE_ID,
        ABYS_REGISTER_ID, ABYS_AGREEMENT_ID, ABYS_INVOICE_LREF
    )
    SELECT
        n.INV_LREF,
        NULL,
        n.DATE_,
        n.INV_TYPE,
        n.CLIENTREF,
        n.OWNERTYPE,
        CAST(0 AS TINYINT),
        CONVERT(FLOAT, n.INST_AMT),
        CONVERT(FLOAT, n.NEW_PAID),
        ISNULL(n.ABYS_DUE_DATE, ISNULL(n.ABYS_EXPIRY_DATE, n.DUEDATE)),
        CAST(120 AS INT),
        ISNULL(n.CURID, 160),
        CAST(1 AS FLOAT),
        CONVERT(FLOAT, n.INST_AMT),
        NULL,
        CAST(113 AS INT),
        CAST(0 AS BIT),
        CAST(0 AS FLOAT),
        CONVERT(FLOAT, n.INST_AMT),
        CAST(103 AS INT),
        n.INST_NR,
        CAST(0 AS FLOAT),
        CONVERT(FLOAT, n.INST_AMT),
        n.DATE_,
        ISNULL(n.ADDUSER, 20001),
        CAST(0 AS INT),
        n.BN_TYPE,
        ISNULL(n.XTYPE, 1),
        ISNULL(n.CURID, 160),
        CAST(n.INST_NR AS VARCHAR(10)) + N'.TAKSIT',
        n.ABYS_ID,
        n.ABYS_ACCOUNT_ID,
        n.ABYS_ACTION_TYPE_ID,
        n.ABYS_ACCRUE_TYPE_ID,
        n.ABYS_REGISTER_ID,
        n.ABYS_AGREEMENT_ID,
        n.INV_LREF
    FROM dbo.MIG_613_STG_NEW n
    ORDER BY n.INV_LREF, n.INST_NR;

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Taksit borc PT insert=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 4) Plan PAYTRANS_REF + INVOICE_REF */
    UPDATE pl
    SET pl.PAYTRANS_REF = pt.LREF,
        pl.INVOICE_REF = n.INV_LREF,
        pl.INVOICE_OLD_DUEDATE = ISNULL(pl.INVOICE_OLD_DUEDATE, n.DUEDATE)
    FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl
    INNER JOIN dbo.MIG_613_STG_NEW n ON n.PLAN_LREF = pl.LREF
    INNER JOIN energy.dbo.LS_005_01_PAYTRANS pt
        ON pt.INVOICEREF = n.INV_LREF
       AND ISNULL(pt.IOCODE, 0) = 0
       AND ISNULL(pt.CANCELED, 0) = 0
       AND ISNULL(pt.INST_NR, 0) = n.INST_NR
       AND ISNULL(pt.PAYTYPE, 0) = 120;

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Plan PAYTRANS_REF wire=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 5) Fatura INSTALLMENT_PLAN_REF */
    UPDATE inv
    SET inv.INSTALLMENT_PLAN_REF = i.PLAN_ID
    FROM energy.dbo.LS_005_01_INVOICE inv
    INNER JOIN dbo.MIG_613_STG_INV i ON i.INV_LREF = inv.LREF
    WHERE ISNULL(inv.INSTALLMENT_PLAN_REF, -1) <> i.PLAN_ID;

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'INVOICE.INSTALLMENT_PLAN_REF upd=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    /* 6) Tahsilat CROSSREF: eski tek PT → taksit PT */
    UPDATE pay
    SET pay.CROSSREF = tgt.NEW_PT_LREF,
        pay.INST_NR = tgt.INST_NR
    FROM energy.dbo.LS_005_01_PAYTRANS pay
    INNER JOIN dbo.MIG_613_STG_OLD_PT o ON o.OLD_PT_LREF = pay.CROSSREF
    CROSS APPLY (
        SELECT TOP (1) pt.LREF AS NEW_PT_LREF, pt.INST_NR
        FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
        WHERE pt.INVOICEREF = o.INV_LREF
          AND ISNULL(pt.IOCODE, 0) = 0
          AND ISNULL(pt.CANCELED, 0) = 0
          AND ISNULL(pt.PAYTYPE, 0) = 120
          AND (
                ISNULL(pay.INST_NR, 0) > 0 AND pt.INST_NR = pay.INST_NR
                OR ISNULL(pay.INST_NR, 0) = 0
              )
        ORDER BY
            CASE WHEN ISNULL(pay.INST_NR, 0) > 0 AND pt.INST_NR = pay.INST_NR THEN 0 ELSE 1 END,
            pt.INST_NR
    ) tgt
    WHERE ISNULL(pay.IOCODE, 0) = 1
      AND ISNULL(pay.CANCELED, 0) = 0;

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'Tahsilat CROSSREF retarget=' + CAST(@N AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    COMMIT TRAN;

    /* CHECKIDENT her AGR'de YAPILMAZ — pipeline sonunda @DO_RESEED=1 veya disarida bir kez */
    IF @DO_RESEED = 1
    BEGIN
        SELECT @MaxLref = ISNULL(MAX(LREF), 0) FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK);
        DBCC CHECKIDENT('energy.dbo.LS_005_01_PAYTRANS', RESEED, @MaxLref) WITH NO_INFOMSGS;
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'CHECKIDENT PAYTRANS RESEED=' + CAST(@MaxLref AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    IF @DEBUG = 1
        RAISERROR('SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR OK', 0, 1) WITH NOWAIT;
END
GO

PRINT '613_INSTALLMENT_DEBT_SPLIT OK (normalize + split v3, CHECKIDENT optional)';
GO
