/* ============================================================
   SCRIPT_ID : OPS_LS001_HESAP
   SCRIPT_NO : 920
   FILE      : 920_OPS_LS001_HESAP__adhoc.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LS_001 Hesap Kartı — PCMS (energy) karşılığı
-- Kaynak referans: e:\SqlScripts\hesapKartı.sql (Oracle ABYS)
--
-- Oracle hesapKartı 4 dal (type):
--   1 = normal açık hesap/fatura
--   2 = vadesi gelen taksit (due_installment) — henüz LS_001 migrate yok
--   3 = taksit planı — izgazMGR blok (bölüm 6)
--   4 = icra — LP_LEGAL_PROCEEDING (bölüm 2)
--
-- PCMS: LS_001_01_INVOICE + LS_001_01_PAYTRANS (+ PAYTRANS_INCOME)
--   Borç PT: IOCODE=0 | Tahsilat: IOCODE=1, CROSSREF → borç PT.LREF
--
-- @AgreementLref = energy.dbo.LS_005_01_AGR.LREF
-- (pilot: LREF = ABYS agreement id ise aynı değer)
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- 0) Şema doğrulama
-- ------------------------------------------------------------
IF OBJECT_ID('energy.dbo.LS_001_01_INVOICE', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_001_01_INVOICE bulunamadi.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('energy.dbo.LS_001_01_PAYTRANS', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_001_01_PAYTRANS bulunamadi.', 16, 1);
    RETURN;
END;

SELECT N'Sema OK' AS VALIDATION,
       N'LS_001_01_INVOICE' AS INVOICE_TBL,
       N'LS_001_01_PAYTRANS' AS PAYTRANS_TBL;
GO

-- ------------------------------------------------------------
-- 1) Hesap kartı — type=1 (açık tahakkuk faturaları)
-- ------------------------------------------------------------
DECLARE @AgreementLref      BIGINT = 197168;
DECLARE @Tolerance          DECIMAL(19,4) = 0.01;

;WITH DebtPT AS (
    SELECT PT.LREF, PT.INVOICEREF, PT.PAYABLETOTAL, PT.PAID, PT.DATE_
    FROM energy.dbo.LS_001_01_PAYTRANS PT
    WHERE ISNULL(PT.CANCELED, 0) = 0 AND PT.IOCODE = 0
),
GecikmeByAcct AS (
    SELECT
        COALESCE(G.FITNO, G.LREF) AS AccountKey,
        SUM(ISNULL(G.PAYABLETOTAL, G.GRANDTOTAL)) AS Commission,
        SUM(ISNULL(G.TAX, 0)) AS CommissionVat
    FROM energy.dbo.LS_001_01_INVOICE G
    WHERE G.OWNERREF = @AgreementLref
      AND ISNULL(G.CANCELED, 0) = 0
      AND ISNULL(G.CLOSED, 0) = 0
      AND G.IOCODE = 0
      AND (
            G.EXPLAIN LIKE N'%GECİKME%'
         OR G.EXPLAIN LIKE N'%GECIKME%'
         OR G.FICHENO LIKE N'%GEC%'
      )
    GROUP BY COALESCE(G.FITNO, G.LREF)
),
LastPay AS (
    SELECT D.LREF AS DebtPTLref, MAX(P.DATE_) AS PayedDate
    FROM DebtPT D
    JOIN energy.dbo.LS_001_01_PAYTRANS P
      ON P.CROSSREF = D.LREF AND P.IOCODE = 1 AND ISNULL(P.CANCELED, 0) = 0
    GROUP BY D.LREF
)
SELECT
    I.TYPE                              AS accrue_type_id,
    ISNULL(I.EXPLAIN, N'Tahakkuk')      AS accrue_type,
    COALESCE(I.FITNO, I.LREF)           AS id,
    CAST(1 AS INT)                      AS order_number,
    CAST(NULL AS INT)                   AS municipal_id,
    CAST(NULL AS INT)                   AS area_id,
    CAST(NULL AS NVARCHAR(50))          AS installation_number,
    CAST(NULL AS NVARCHAR(50))          AS register_number,
    CAST(CAST(@AgreementLref AS NVARCHAR(30)) AS NVARCHAR(50)) AS agreement_number,
    CAST(NULL AS INT)                   AS period,
    I.DATE_                             AS action_date,
    ISNULL(I.PAYABLETOTAL, I.GRANDTOTAL) AS accrue_amount,
    ISNULL(I.PAYABLETOTAL, I.GRANDTOTAL) - ISNULL(D.PAID, 0) AS balance,
    ISNULL(GA.Commission, 0)            AS commission,
    ISNULL(GA.CommissionVat, 0)         AS commission_vat,
    ISNULL(I.PAYABLETOTAL, I.GRANDTOTAL) - ISNULL(D.PAID, 0)
      + ISNULL(GA.Commission, 0) + ISNULL(GA.CommissionVat, 0) AS total_debt,
    I.DUEDATE                           AS expiry_date,
    ISNULL(D.PAID, 0)                   AS payed,
    LP.PayedDate                        AS payed_date,
    CAST(NULL AS NVARCHAR(50))          AS legal_proceeding,
    CAST(NULL AS BIGINT)                AS installment_id,
    CAST(NULL AS BIGINT)                AS due_installment_id,
    CAST(NULL AS NVARCHAR(50))          AS meter_number,
    CAST(1 AS INT)                      AS type,
    CAST(0 AS DECIMAL(19,4))            AS old_commission,
    CAST(0 AS BIT)                      AS do_discharge,
    CAST(0 AS BIT)                      AS is_edit,
    CAST(0 AS DECIMAL(19,4))            AS tax_discount_amount,
    CAST(NULL AS BIT)                   AS is_fps,
    CAST(NULL AS BIGINT)                AS work_order_id,
    I.EXPLAIN                           AS description,
    CAST(NULL AS SMALLINT)              AS lp_type,
    CAST(NULL AS DATETIME)              AS commitment_date,
    CAST(NULL AS NVARCHAR(200))         AS commitment_cause,
    CAST(0 AS INT)                      AS doc_count
FROM energy.dbo.LS_001_01_INVOICE I
LEFT JOIN DebtPT D ON D.INVOICEREF = I.LREF
LEFT JOIN GecikmeByAcct GA ON GA.AccountKey = COALESCE(I.FITNO, I.LREF)
LEFT JOIN LastPay LP ON LP.DebtPTLref = D.LREF
WHERE I.OWNERREF = @AgreementLref
  AND ISNULL(I.CANCELED, 0) = 0
  AND ISNULL(I.CLOSED, 0) = 0
  AND I.IOCODE = 0
  AND NOT (
        I.EXPLAIN LIKE N'%GECİKME%'
     OR I.EXPLAIN LIKE N'%GECIKME%'
     OR I.FICHENO LIKE N'%GEC%'
  )
  AND ISNULL(I.PAYABLETOTAL, I.GRANDTOTAL) - ISNULL(D.PAID, 0) > @Tolerance
ORDER BY I.DATE_, I.LREF;
GO

-- ------------------------------------------------------------
-- 2) Hesap kartı — type=4 (icra / LP_LEGAL_PROCEEDING)
-- ------------------------------------------------------------
DECLARE @AgreementLref BIGINT = 197168;

IF OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING', 'U') IS NOT NULL
BEGIN
    SELECT
        CAST(NULL AS INT)                   AS accrue_type_id,
        N'İcra'                             AS accrue_type,
        LP.ID                               AS id,
        CAST(1 AS INT)                      AS order_number,
        CAST(NULL AS INT)                   AS municipal_id,
        CAST(NULL AS INT)                   AS area_id,
        LP.INSTALLATION_ID                  AS installation_number,
        CAST(LP.REGISTER_ID AS NVARCHAR(50)) AS register_number,
        CAST(CAST(@AgreementLref AS NVARCHAR(30)) AS NVARCHAR(50)) AS agreement_number,
        CAST(NULL AS INT)                   AS period,
        LP.LEGAL_PROCEEDING_DATE            AS action_date,
        LP.DEBT                             AS accrue_amount,
        LP.LEGAL_PROCEEDING_AMOUNT          AS balance,
        LP.OVERDUE                          AS commission,
        LP.OVERDUE_VAT                      AS commission_vat,
        LP.LEGAL_PROCEEDING_AMOUNT          AS total_debt,
        LP.LAST_PAYMENT_DATE                AS expiry_date,
        LP.DEBT + LP.OVERDUE + LP.OVERDUE_VAT - LP.LEGAL_PROCEEDING_AMOUNT AS payed,
        LP.LAST_PAYMENT_DATE                AS payed_date,
        LP.CODE                             AS legal_proceeding,
        CAST(NULL AS BIGINT)                AS installment_id,
        CAST(NULL AS BIGINT)                AS due_installment_id,
        CAST(NULL AS NVARCHAR(50))          AS meter_number,
        CAST(4 AS INT)                      AS type,
        CAST(NULL AS DECIMAL(19,4))         AS old_commission,
        CAST(0 AS BIT)                      AS do_discharge,
        CAST(0 AS BIT)                      AS is_edit,
        CAST(NULL AS DECIMAL(19,4))         AS tax_discount_amount,
        CAST(NULL AS BIT)                   AS is_fps,
        CAST(NULL AS BIGINT)                AS work_order_id,
        LP.DESCRIPTION                      AS description,
        LP.ABYS_TYPE                        AS lp_type,
        CAST(NULL AS DATETIME)              AS commitment_date,
        CAST(NULL AS NVARCHAR(200))         AS commitment_cause,
        CAST(0 AS INT)                      AS doc_count
    FROM energy.dbo.LP_LEGAL_PROCEEDING LP
    WHERE LP.AGREEMENT_ID = @AgreementLref
      AND LP.CANCELLATION_DATE IS NULL
      AND ISNULL(LP.IS_ACTIVE, 1) = 1
      AND LP.LEGAL_PROCEEDING_AMOUNT > 0.01;
END
ELSE
    SELECT N'LP_LEGAL_PROCEEDING yok — type=4 atlandi' AS UYARI;
GO

-- ------------------------------------------------------------
-- 3) Birleşik hesap kartı (type 1 + type 4)
-- ------------------------------------------------------------
DECLARE @AgreementLref      BIGINT = 197168;
DECLARE @Tolerance          DECIMAL(19,4) = 0.01;

IF OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING', 'U') IS NOT NULL
BEGIN
    ;WITH DebtPT AS (
        SELECT PT.INVOICEREF, PT.PAID
        FROM energy.dbo.LS_001_01_PAYTRANS PT
        WHERE ISNULL(PT.CANCELED, 0) = 0 AND PT.IOCODE = 0
    ),
    OpenInv AS (
        SELECT
            I.TYPE AS accrue_type_id,
            ISNULL(I.EXPLAIN, N'Tahakkuk') AS accrue_type,
            COALESCE(I.FITNO, I.LREF) AS id,
            CAST(1 AS INT) AS order_number,
            I.DATE_ AS action_date,
            ISNULL(I.PAYABLETOTAL, I.GRANDTOTAL) AS accrue_amount,
            ISNULL(I.PAYABLETOTAL, I.GRANDTOTAL) - ISNULL(D.PAID, 0) AS balance,
            CAST(0 AS DECIMAL(19,4)) AS commission,
            CAST(0 AS DECIMAL(19,4)) AS commission_vat,
            ISNULL(I.PAYABLETOTAL, I.GRANDTOTAL) - ISNULL(D.PAID, 0) AS total_debt,
            I.DUEDATE AS expiry_date,
            ISNULL(D.PAID, 0) AS payed,
            CAST(1 AS INT) AS type,
            I.EXPLAIN AS description
        FROM energy.dbo.LS_001_01_INVOICE I
        LEFT JOIN DebtPT D ON D.INVOICEREF = I.LREF
        WHERE I.OWNERREF = @AgreementLref
          AND ISNULL(I.CANCELED, 0) = 0
          AND ISNULL(I.CLOSED, 0) = 0
          AND I.IOCODE = 0
          AND NOT (I.EXPLAIN LIKE N'%GECİKME%' OR I.EXPLAIN LIKE N'%GECIKME%')
          AND ISNULL(I.PAYABLETOTAL, I.GRANDTOTAL) - ISNULL(D.PAID, 0) > @Tolerance
    )
    SELECT * FROM OpenInv
    UNION ALL
    SELECT
        CAST(NULL AS INT),
        N'İcra ' + ISNULL(LP.CODE, N''),
        LP.ID,
        CAST(1 AS INT),
        LP.LEGAL_PROCEEDING_DATE,
        LP.DEBT,
        LP.LEGAL_PROCEEDING_AMOUNT,
        LP.OVERDUE,
        LP.OVERDUE_VAT,
        LP.LEGAL_PROCEEDING_AMOUNT,
        LP.LAST_PAYMENT_DATE,
        LP.DEBT + LP.OVERDUE + LP.OVERDUE_VAT - LP.LEGAL_PROCEEDING_AMOUNT,
        CAST(4 AS INT),
        LP.DESCRIPTION
    FROM energy.dbo.LP_LEGAL_PROCEEDING LP
    WHERE LP.AGREEMENT_ID = @AgreementLref
      AND LP.CANCELLATION_DATE IS NULL
      AND ISNULL(LP.IS_ACTIVE, 1) = 1
      AND LP.LEGAL_PROCEEDING_AMOUNT > @Tolerance
    ORDER BY type, action_date, id;
END
ELSE
BEGIN
    ;WITH DebtPT AS (
        SELECT PT.INVOICEREF, PT.PAID
        FROM energy.dbo.LS_001_01_PAYTRANS PT
        WHERE ISNULL(PT.CANCELED, 0) = 0 AND PT.IOCODE = 0
    )
    SELECT
        I.TYPE AS accrue_type_id,
        ISNULL(I.EXPLAIN, N'Tahakkuk') AS accrue_type,
        COALESCE(I.FITNO, I.LREF) AS id,
        CAST(1 AS INT) AS order_number,
        I.DATE_ AS action_date,
        ISNULL(I.PAYABLETOTAL, I.GRANDTOTAL) AS accrue_amount,
        ISNULL(I.PAYABLETOTAL, I.GRANDTOTAL) - ISNULL(D.PAID, 0) AS balance,
        CAST(0 AS DECIMAL(19,4)) AS commission,
        CAST(0 AS DECIMAL(19,4)) AS commission_vat,
        ISNULL(I.PAYABLETOTAL, I.GRANDTOTAL) - ISNULL(D.PAID, 0) AS total_debt,
        I.DUEDATE AS expiry_date,
        ISNULL(D.PAID, 0) AS payed,
        CAST(1 AS INT) AS type,
        I.EXPLAIN AS description
    FROM energy.dbo.LS_001_01_INVOICE I
    LEFT JOIN DebtPT D ON D.INVOICEREF = I.LREF
    WHERE I.OWNERREF = @AgreementLref
      AND ISNULL(I.CANCELED, 0) = 0
      AND ISNULL(I.CLOSED, 0) = 0
      AND I.IOCODE = 0
      AND NOT (I.EXPLAIN LIKE N'%GECİKME%' OR I.EXPLAIN LIKE N'%GECIKME%')
      AND ISNULL(I.PAYABLETOTAL, I.GRANDTOTAL) - ISNULL(D.PAID, 0) > @Tolerance
    ORDER BY I.DATE_, I.LREF;
END
GO

-- ------------------------------------------------------------
-- 4) Gelir kırılımı — PAYTRANS_INCOME allocation vs PT.PAID
-- ------------------------------------------------------------
DECLARE @AgreementLref BIGINT = 197168;
DECLARE @Tolerance     DECIMAL(19,4) = 0.01;

IF OBJECT_ID('energy.dbo.LS_001_01_PAYTRANS_INCOME', 'U') IS NOT NULL
   AND OBJECT_ID('energy.dbo.LS_001_01_INVLINES', 'U') IS NOT NULL
BEGIN
    SELECT
        I.LREF AS invoice_lref,
        COALESCE(I.FITNO, I.LREF) AS account_key,
        SUM(IL.TLTOTAL) AS line_net,
        ISNULL(D.PAID, 0) AS paid_on_debt_pt,
        ISNULL(PI_SUM.AllocPaid, 0) AS paid_via_allocation,
        SUM(IL.TLTOTAL) - ISNULL(D.PAID, 0) AS balance_pt,
        SUM(IL.TLTOTAL) - ISNULL(PI_SUM.AllocPaid, 0) AS balance_alloc
    FROM energy.dbo.LS_001_01_INVOICE I
    JOIN energy.dbo.LS_001_01_INVLINES IL ON IL.INVOICEREF = I.LREF
    LEFT JOIN energy.dbo.LS_001_01_PAYTRANS D
           ON D.INVOICEREF = I.LREF AND D.IOCODE = 0 AND ISNULL(D.CANCELED, 0) = 0
    OUTER APPLY (
        SELECT SUM(PI.INCOME_AMOUNT) AS AllocPaid
        FROM energy.dbo.LS_001_01_PAYTRANS_INCOME PI
        JOIN energy.dbo.LS_001_01_PAYTRANS P ON P.LREF = PI.PAYTRANSREF
        WHERE PI.DEBT_INVOICEREF = I.LREF AND ISNULL(P.CANCELED, 0) = 0
    ) PI_SUM
    WHERE I.OWNERREF = @AgreementLref
      AND ISNULL(I.CANCELED, 0) = 0
      AND ISNULL(IL.CANCELED, 0) = 0
    GROUP BY I.LREF, I.FITNO, D.PAID, PI_SUM.AllocPaid
    HAVING ABS(SUM(IL.TLTOTAL) - ISNULL(D.PAID, 0)) > @Tolerance
        OR ABS(SUM(IL.TLTOTAL) - ISNULL(PI_SUM.AllocPaid, 0)) > @Tolerance
    ORDER BY I.LREF;
END
GO

-- ------------------------------------------------------------
-- 5) Özet metrikler
-- ------------------------------------------------------------
DECLARE @AgreementLref BIGINT = 197168;
DECLARE @Tolerance     DECIMAL(19,4) = 0.01;

;WITH DebtPT AS (
    SELECT PT.INVOICEREF, PT.PAID
    FROM energy.dbo.LS_001_01_PAYTRANS PT
    WHERE ISNULL(PT.CANCELED, 0) = 0 AND PT.IOCODE = 0
),
OpenRows AS (
    SELECT I.LREF,
           ISNULL(I.PAYABLETOTAL, I.GRANDTOTAL) - ISNULL(D.PAID, 0) AS Remaining
    FROM energy.dbo.LS_001_01_INVOICE I
    LEFT JOIN DebtPT D ON D.INVOICEREF = I.LREF
    WHERE I.OWNERREF = @AgreementLref
      AND ISNULL(I.CANCELED, 0) = 0
      AND ISNULL(I.CLOSED, 0) = 0
      AND I.IOCODE = 0
)
SELECT N'Açık fatura adedi' AS METRIK, COUNT(*) AS DEGER
FROM OpenRows WHERE Remaining > @Tolerance
UNION ALL
SELECT N'Toplam açık borç (LS_001)', SUM(Remaining)
FROM OpenRows WHERE Remaining > @Tolerance
UNION ALL
SELECT N'Kapalı fatura adedi', COUNT(*)
FROM energy.dbo.LS_001_01_INVOICE I
WHERE I.OWNERREF = @AgreementLref
  AND ISNULL(I.CANCELED, 0) = 0
  AND ISNULL(I.CLOSED, 0) = 1
  AND I.IOCODE = 0;

IF OBJECT_ID('energy.dbo.LP_LEGAL_PROCEEDING', 'U') IS NOT NULL
BEGIN
    SELECT N'İcra dosyası (LP)' AS METRIK, COUNT(*) AS DEGER
    FROM energy.dbo.LP_LEGAL_PROCEEDING LP
    WHERE LP.AGREEMENT_ID = @AgreementLref
      AND LP.CANCELLATION_DATE IS NULL
      AND LP.LEGAL_PROCEEDING_AMOUNT > @Tolerance;
END
GO

-- ------------------------------------------------------------
-- 6) [İsteğe bağlı] type=3 taksit — izgazMGR (migrate öncesi)
-- ------------------------------------------------------------
DECLARE @AgreementLref BIGINT = 197168;

IF OBJECT_ID('izgazMGR.dbo.CS_INSTALLMENT', 'U') IS NOT NULL
   AND OBJECT_ID('izgazMGR.dbo.CS_INSTALLMENT_PLAN', 'U') IS NOT NULL
BEGIN
    SELECT
        CAST(NULL AS INT)                   AS accrue_type_id,
        N'Taksit'                           AS accrue_type,
        IP.ID                               AS id,
        IP.ORDER_NUMBER                     AS order_number,
        CAST(NULL AS INT)                   AS municipal_id,
        INS.AREA_ID                         AS area_id,
        CAST(NULL AS NVARCHAR(50))          AS installation_number,
        CAST(NULL AS NVARCHAR(50))          AS register_number,
        CAST(CAST(@AgreementLref AS NVARCHAR(30)) AS NVARCHAR(50)) AS agreement_number,
        INS.PERIOD                          AS period,
        INS.INSTALLMENT_DATE                AS action_date,
        IP.AMOUNT                           AS accrue_amount,
        CASE WHEN IP.PAYMENT_DATE IS NULL
             THEN IP.AMOUNT + ISNULL(IP.LATE_CHARGE, 0) ELSE 0 END AS balance,
        ISNULL(IP.LATE_CHARGE, 0)           AS commission,
        CAST(0 AS DECIMAL(19,4))            AS commission_vat,
        CASE WHEN IP.PAYMENT_DATE IS NULL
             THEN IP.AMOUNT + ISNULL(IP.LATE_CHARGE, 0) ELSE 0 END AS total_debt,
        IP.EXPIRY_DATE                      AS expiry_date,
        CASE WHEN IP.PAYMENT_DATE IS NULL THEN 0 ELSE IP.AMOUNT END AS payed,
        IP.PAYMENT_DATE                     AS payed_date,
        CAST(NULL AS NVARCHAR(50))          AS legal_proceeding,
        INS.ID                              AS installment_id,
        CAST(NULL AS BIGINT)                AS due_installment_id,
        CAST(NULL AS NVARCHAR(50))          AS meter_number,
        CAST(3 AS INT)                      AS type,
        CAST(NULL AS DECIMAL(19,4))         AS old_commission,
        CAST(0 AS BIT)                      AS do_discharge,
        CAST(0 AS BIT)                      AS is_edit,
        CAST(NULL AS DECIMAL(19,4))         AS tax_discount_amount,
        CAST(NULL AS BIT)                   AS is_fps,
        CAST(NULL AS BIGINT)                AS work_order_id,
        CAST(NULL AS NVARCHAR(250))         AS description,
        CAST(NULL AS SMALLINT)              AS lp_type,
        CAST(NULL AS DATETIME)              AS commitment_date,
        CAST(NULL AS NVARCHAR(200))         AS commitment_cause,
        CAST(0 AS INT)                      AS doc_count
    FROM izgazMGR.dbo.CS_INSTALLMENT INS
    JOIN izgazMGR.dbo.CS_INSTALLMENT_PLAN IP ON IP.INSTALLMENT_ID = INS.ID
    WHERE INS.AGREEMENT_ID = @AgreementLref
      AND INS.CANCELLATION_DATE IS NULL
      AND INS.DUE_DATE IS NULL
      AND IP.PAYMENT_DATE IS NULL
    ORDER BY INS.ID, IP.ORDER_NUMBER;
END
ELSE
    SELECT N'izgazMGR taksit tablolari yok — type=3 atlandi' AS UYARI;
GO

