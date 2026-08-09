/* ============================================================
   FILE      : adim3_energy_verify.sql
   SCRIPT_ID : ADIM3_ENERGY_VERIFY
   FAZ       : Dogrulama / karsilastirma (energy vs izgazMGR)
   Pilot     : @AGR_ID = 197168 (= AGREEMENT_NUMBER / ABYS_AGREEMENT_ID)
   Onkosul   : 571 (+ istege 581) + 575/578 tamam
   ============================================================
   YAVAS / DONMUYORSA:
     1) adim3_verify_indexes.sql
     2) adim3_recon_totals.sql  (hizli, PK join)
     3) Oracle: oracleControl/adim3_recon_totals.sql (ayni kolonlar)
   ============================================================
   Beklenen (pilot):
     MGR_INV = EN_INV = EN_DEBT_PT = 259
     SUM     = 109843.94
     MISSING / EXTRA / BAD_* = 0
   ============================================================ */
USE energy;
GO

DECLARE @AGR_ID BIGINT = 197168;
DECLARE @AgrLref INT = NULL;
DECLARE @Eps FLOAT = 0.01;

-- AGR resolve (varsa)
IF OBJECT_ID('energy.dbo.SP_MIG_RESOLVE_AGR_BY_NUMBER', 'P') IS NOT NULL
BEGIN
    DECLARE @AbysAgrId BIGINT, @AgrNumber VARCHAR(50);
    EXEC dbo.SP_MIG_RESOLVE_AGR_BY_NUMBER
        @AGRID     = @AGR_ID,
        @AgrLref   = @AgrLref OUTPUT,
        @AbysAgrId = @AbysAgrId OUTPUT,
        @AgrNumber = @AgrNumber OUTPUT;

    SELECT
        @AGR_ID AS AGR_ID,
        @AgrNumber AS AGREEMENT_NUMBER,
        @AgrLref AS AGR_LREF,
        @AbysAgrId AS AGR_ABYS_ID,
        CASE WHEN @AgrLref IS NULL THEN 'AGR_YOK' ELSE 'AGR_OK' END AS AGR_STATUS;
END
ELSE
    SELECT @AGR_ID AS AGR_ID, CAST(NULL AS INT) AS AGR_LREF, 'RESOLVE_SP_YOK' AS AGR_STATUS;
GO

DECLARE @AGR_ID BIGINT = 197168;
DECLARE @AgrLref INT;
DECLARE @Eps FLOAT = 0.01;

SELECT TOP 1 @AgrLref = a.LREF
FROM energy.dbo.LS_005_01_AGR a WITH (NOLOCK)
WHERE a.AGREEMENT_NUMBER = CAST(@AGR_ID AS VARCHAR(50))
   OR TRY_CAST(a.AGREEMENT_NUMBER AS BIGINT) = @AGR_ID
   OR TRY_CAST(a.ABYS_ID AS BIGINT) = @AGR_ID
ORDER BY a.LREF;

PRINT '=== A) INVOICE: izgazMGR vs energy ===';
SELECT
    (SELECT COUNT_BIG(*)
       FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
      WHERE ABYS_AGREEMENT_ID = @AGR_ID) AS MGR_INV,
    (SELECT COUNT_BIG(*)
       FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
      WHERE ABYS_ID IS NOT NULL
        AND (
              ABYS_AGREEMENT_ID = @AGR_ID
           OR (@AgrLref IS NOT NULL AND OWNERREF = @AgrLref)
            )) AS EN_INV,
    (SELECT SUM(CAST(PAYABLETOTAL AS FLOAT))
       FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
      WHERE ABYS_AGREEMENT_ID = @AGR_ID) AS MGR_SUM,
    (SELECT SUM(CAST(PAYABLETOTAL AS FLOAT))
       FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
      WHERE ABYS_ID IS NOT NULL
        AND (
              ABYS_AGREEMENT_ID = @AGR_ID
           OR (@AgrLref IS NOT NULL AND OWNERREF = @AgrLref)
            )) AS EN_SUM;

-- Eksik / fazla fatura
SELECT COUNT_BIG(*) AS INV_MISSING_IN_ENERGY
FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
WHERE s.ABYS_AGREEMENT_ID = @AGR_ID
  AND s.ABYS_ACTION_ID BETWEEN 1 AND 2147483647
  AND NOT EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_INVOICE t WITH (NOLOCK)
        WHERE t.LREF = CAST(s.ABYS_ACTION_ID AS INT)
           OR t.ABYS_ID = s.ABYS_ACTION_ID
      );

SELECT COUNT_BIG(*) AS INV_EXTRA_IN_ENERGY
FROM energy.dbo.LS_005_01_INVOICE t WITH (NOLOCK)
WHERE t.ABYS_ID IS NOT NULL
  AND (
        t.ABYS_AGREEMENT_ID = @AGR_ID
     OR (@AgrLref IS NOT NULL AND t.OWNERREF = @AgrLref)
      )
  AND NOT EXISTS (
        SELECT 1 FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
        WHERE s.ABYS_ACTION_ID = t.ABYS_ID
           OR s.ABYS_ACTION_ID = t.LREF
      );

-- LREF = ABYS_ID
SELECT COUNT_BIG(*) AS INV_LREF_NE_ABYS_ID
FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
WHERE ABYS_ID IS NOT NULL
  AND (
        ABYS_AGREEMENT_ID = @AGR_ID
     OR (@AgrLref IS NOT NULL AND OWNERREF = @AgrLref)
      )
  AND LREF <> ABYS_ID;

-- Tutar farki (eski vs yeni, action bazinda)
SELECT COUNT_BIG(*) AS INV_AMT_MISMATCH
FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
INNER JOIN energy.dbo.LS_005_01_INVOICE t WITH (NOLOCK)
    ON t.LREF = CAST(s.ABYS_ACTION_ID AS INT)
WHERE s.ABYS_AGREEMENT_ID = @AGR_ID
  AND ABS(ISNULL(CAST(s.PAYABLETOTAL AS FLOAT), 0) - ISNULL(CAST(t.PAYABLETOTAL AS FLOAT), 0)) > @Eps;

-- Ornek farklar
SELECT TOP 20
    s.ABYS_ACTION_ID,
    CAST(s.PAYABLETOTAL AS FLOAT) AS MGR_AMT,
    CAST(t.PAYABLETOTAL AS FLOAT) AS EN_AMT,
    CAST(s.PAYABLETOTAL AS FLOAT) - CAST(t.PAYABLETOTAL AS FLOAT) AS DELTA,
    t.LREF, t.IOCODE, t.[TYPE]
FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
INNER JOIN energy.dbo.LS_005_01_INVOICE t WITH (NOLOCK)
    ON t.LREF = CAST(s.ABYS_ACTION_ID AS INT)
WHERE s.ABYS_AGREEMENT_ID = @AGR_ID
  AND ABS(ISNULL(CAST(s.PAYABLETOTAL AS FLOAT), 0) - ISNULL(CAST(t.PAYABLETOTAL AS FLOAT), 0)) > @Eps
ORDER BY ABS(CAST(s.PAYABLETOTAL AS FLOAT) - CAST(t.PAYABLETOTAL AS FLOAT)) DESC;
GO

DECLARE @AGR_ID BIGINT = 197168;
DECLARE @AgrLref INT;
DECLARE @Eps FLOAT = 0.01;

SELECT TOP 1 @AgrLref = a.LREF
FROM energy.dbo.LS_005_01_AGR a WITH (NOLOCK)
WHERE a.AGREEMENT_NUMBER = CAST(@AGR_ID AS VARCHAR(50))
   OR TRY_CAST(a.AGREEMENT_NUMBER AS BIGINT) = @AGR_ID
ORDER BY a.LREF;

PRINT '=== B) INVLINES (varsa): izgazMGR vs energy ===';
IF OBJECT_ID('izgazMGR.dbo.LS_INVLINES', 'U') IS NULL
   OR OBJECT_ID('energy.dbo.LS_005_01_INVLINES', 'U') IS NULL
BEGIN
    SELECT 'INVLINES atlandi (kaynak veya hedef yok)' AS INVLINES_STATUS;
END
ELSE
BEGIN
    SELECT
        (SELECT COUNT_BIG(*)
           FROM izgazMGR.dbo.LS_INVLINES l WITH (NOLOCK)
          WHERE l.ABYS_AGREEMENT_ID = @AGR_ID
             OR l.INVOICEREF IN (
                    SELECT CAST(ABYS_ACTION_ID AS INT)
                    FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
                    WHERE ABYS_AGREEMENT_ID = @AGR_ID
                )) AS MGR_LINES,
        (SELECT COUNT_BIG(*)
           FROM energy.dbo.LS_005_01_INVLINES l WITH (NOLOCK)
          WHERE l.ABYS_ID IS NOT NULL
            AND (
                  l.ABYS_AGREEMENT_ID = @AGR_ID
               OR l.INVOICEREF IN (
                      SELECT inv.LREF
                      FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
                      WHERE inv.ABYS_ID IS NOT NULL
                        AND (
                              inv.ABYS_AGREEMENT_ID = @AGR_ID
                           OR (@AgrLref IS NOT NULL AND inv.OWNERREF = @AgrLref)
                            )
                  )
                )) AS EN_LINES,
        (SELECT SUM(CAST(GRANDTOTAL AS FLOAT))
           FROM izgazMGR.dbo.LS_INVLINES l WITH (NOLOCK)
          WHERE l.ABYS_AGREEMENT_ID = @AGR_ID
             OR l.INVOICEREF IN (
                    SELECT CAST(ABYS_ACTION_ID AS INT)
                    FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
                    WHERE ABYS_AGREEMENT_ID = @AGR_ID
                )) AS MGR_LINE_SUM,
        (SELECT SUM(CAST(GRANDTOTAL AS FLOAT))
           FROM energy.dbo.LS_005_01_INVLINES l WITH (NOLOCK)
          WHERE l.ABYS_ID IS NOT NULL
            AND (
                  l.ABYS_AGREEMENT_ID = @AGR_ID
               OR l.INVOICEREF IN (
                      SELECT inv.LREF
                      FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
                      WHERE inv.ABYS_AGREEMENT_ID = @AGR_ID
                         OR (@AgrLref IS NOT NULL AND inv.OWNERREF = @AgrLref)
                  )
                )) AS EN_LINE_SUM;

    SELECT COUNT_BIG(*) AS LINE_MISSING_IN_ENERGY
    FROM izgazMGR.dbo.LS_INVLINES s WITH (NOLOCK)
    WHERE (
            s.ABYS_AGREEMENT_ID = @AGR_ID
         OR s.INVOICEREF IN (
                SELECT CAST(ABYS_ACTION_ID AS INT)
                FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
                WHERE ABYS_AGREEMENT_ID = @AGR_ID
            )
          )
      AND s.LREF BETWEEN 1 AND 2147483647
      AND NOT EXISTS (
            SELECT 1 FROM energy.dbo.LS_005_01_INVLINES t WITH (NOLOCK)
            WHERE t.LREF = CAST(s.LREF AS INT)
               OR t.ABYS_ID = s.ABYS_INCOME_ROW_ID
          );
END
GO

DECLARE @AGR_ID BIGINT = 197168;
DECLARE @AgrLref INT;
DECLARE @Eps FLOAT = 0.01;

SELECT TOP 1 @AgrLref = a.LREF
FROM energy.dbo.LS_005_01_AGR a WITH (NOLOCK)
WHERE a.AGREEMENT_NUMBER = CAST(@AGR_ID AS VARCHAR(50))
   OR TRY_CAST(a.AGREEMENT_NUMBER AS BIGINT) = @AGR_ID
ORDER BY a.LREF;

PRINT '=== C) BORC PAYTRANS (575) ===';
SELECT
    (SELECT COUNT_BIG(*)
       FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
      WHERE ISNULL(IOCODE, 0) = 0
        AND ABYS_ID IS NOT NULL
        AND (
              ABYS_AGREEMENT_ID = @AGR_ID
           OR (@AgrLref IS NOT NULL AND OWNERREF = @AgrLref)
            )) AS EN_INV_IOCODE0,
    (SELECT COUNT_BIG(*)
       FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
      WHERE ISNULL(IOCODE, 0) = 0
        AND ABYS_ID IS NOT NULL
        AND (
              ABYS_AGREEMENT_ID = @AGR_ID
           OR INVOICEREF IN (
                  SELECT LREF FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
                  WHERE ABYS_AGREEMENT_ID = @AGR_ID
                     OR (@AgrLref IS NOT NULL AND OWNERREF = @AgrLref)
              )
            )) AS EN_DEBT_PT,
    (SELECT SUM(CAST(PAYABLETOTAL AS FLOAT))
       FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
      WHERE ISNULL(IOCODE, 0) = 0
        AND ABYS_ID IS NOT NULL
        AND (
              ABYS_AGREEMENT_ID = @AGR_ID
           OR (@AgrLref IS NOT NULL AND OWNERREF = @AgrLref)
            )) AS EN_INV_SUM,
    (SELECT SUM(CAST(PAYABLETOTAL AS FLOAT))
       FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
      WHERE ISNULL(IOCODE, 0) = 0
        AND ABYS_ID IS NOT NULL
        AND (
              ABYS_AGREEMENT_ID = @AGR_ID
           OR INVOICEREF IN (
                  SELECT LREF FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
                  WHERE ABYS_AGREEMENT_ID = @AGR_ID
                     OR (@AgrLref IS NOT NULL AND OWNERREF = @AgrLref)
              )
            )) AS EN_PT_SUM;

SELECT COUNT_BIG(*) AS MISSING_DEBT_PT
FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
WHERE ISNULL(inv.IOCODE, 0) = 0
  AND inv.ABYS_ID IS NOT NULL
  AND (
        inv.ABYS_AGREEMENT_ID = @AGR_ID
     OR (@AgrLref IS NOT NULL AND inv.OWNERREF = @AgrLref)
      )
  AND NOT EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
        WHERE pt.INVOICEREF = inv.LREF
          AND ISNULL(pt.IOCODE, 0) = 0
          AND pt.ABYS_ID IS NOT NULL
      );

SELECT pt.INVOICEREF, COUNT_BIG(*) AS DEBT_PT_CNT
FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
WHERE ISNULL(pt.IOCODE, 0) = 0
  AND pt.ABYS_ID IS NOT NULL
  AND (
        pt.ABYS_AGREEMENT_ID = @AGR_ID
     OR pt.INVOICEREF IN (
            SELECT LREF FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
            WHERE ABYS_AGREEMENT_ID = @AGR_ID
               OR (@AgrLref IS NOT NULL AND OWNERREF = @AgrLref)
        )
      )
GROUP BY pt.INVOICEREF
HAVING COUNT_BIG(*) > 1;

SELECT
    SUM(CASE WHEN pt.PAYTYPE <> 174 OR pt.TRANSTYPE <> 113 OR pt.LINETYPE <> 103
                  OR ISNULL(pt.PAID, 0) <> 0 OR ISNULL(pt.IOCODE, 0) <> 0
             THEN 1 ELSE 0 END) AS BAD_CONST,
    SUM(CASE WHEN ABS(ISNULL(CAST(pt.PAYABLETOTAL AS FLOAT), 0)
                    - ISNULL(CAST(inv.PAYABLETOTAL AS FLOAT), 0)) > @Eps
             THEN 1 ELSE 0 END) AS BAD_AMT,
    SUM(CASE WHEN pt.INVOICEREF <> inv.LREF
                  OR ISNULL(pt.ABYS_INVOICE_LREF, 0) <> inv.LREF
             THEN 1 ELSE 0 END) AS BAD_REF
FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
INNER JOIN energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    ON inv.LREF = pt.INVOICEREF
WHERE ISNULL(pt.IOCODE, 0) = 0
  AND pt.ABYS_ID IS NOT NULL
  AND (
        pt.ABYS_AGREEMENT_ID = @AGR_ID
     OR inv.ABYS_AGREEMENT_ID = @AGR_ID
     OR (@AgrLref IS NOT NULL AND inv.OWNERREF = @AgrLref)
      );
GO

DECLARE @AGR_ID BIGINT = 197168;
DECLARE @AgrLref INT;
DECLARE @Eps FLOAT = 0.01;

SELECT TOP 1 @AgrLref = a.LREF
FROM energy.dbo.LS_005_01_AGR a WITH (NOLOCK)
WHERE a.AGREEMENT_NUMBER = CAST(@AGR_ID AS VARCHAR(50))
   OR TRY_CAST(a.AGREEMENT_NUMBER AS BIGINT) = @AGR_ID
ORDER BY a.LREF;

PRINT '=== D) GATE OZET (PASS/FAIL) ===';
;WITH
mgr AS (
    SELECT
        COUNT_BIG(*) AS CNT,
        SUM(CAST(PAYABLETOTAL AS FLOAT)) AS AMT
    FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
    WHERE ABYS_AGREEMENT_ID = @AGR_ID
),
en AS (
    SELECT
        COUNT_BIG(*) AS CNT,
        SUM(CAST(PAYABLETOTAL AS FLOAT)) AS AMT
    FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
    WHERE ABYS_ID IS NOT NULL
      AND (
            ABYS_AGREEMENT_ID = @AGR_ID
         OR (@AgrLref IS NOT NULL AND OWNERREF = @AgrLref)
          )
),
pt AS (
    SELECT
        COUNT_BIG(*) AS CNT,
        SUM(CAST(PAYABLETOTAL AS FLOAT)) AS AMT
    FROM energy.dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
    WHERE ISNULL(IOCODE, 0) = 0
      AND ABYS_ID IS NOT NULL
      AND (
            ABYS_AGREEMENT_ID = @AGR_ID
         OR INVOICEREF IN (
                SELECT LREF FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
                WHERE ABYS_AGREEMENT_ID = @AGR_ID
                   OR (@AgrLref IS NOT NULL AND OWNERREF = @AgrLref)
            )
          )
),
miss AS (
    SELECT COUNT_BIG(*) AS CNT
    FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
    WHERE ISNULL(inv.IOCODE, 0) = 0
      AND inv.ABYS_ID IS NOT NULL
      AND (
            inv.ABYS_AGREEMENT_ID = @AGR_ID
         OR (@AgrLref IS NOT NULL AND inv.OWNERREF = @AgrLref)
          )
      AND NOT EXISTS (
            SELECT 1 FROM energy.dbo.LS_005_01_PAYTRANS p WITH (NOLOCK)
            WHERE p.INVOICEREF = inv.LREF
              AND ISNULL(p.IOCODE, 0) = 0
              AND p.ABYS_ID IS NOT NULL
          )
),
dup AS (
    SELECT COUNT_BIG(*) AS CNT
    FROM (
        SELECT pt.INVOICEREF
        FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
        WHERE ISNULL(pt.IOCODE, 0) = 0
          AND pt.ABYS_ID IS NOT NULL
          AND (
                pt.ABYS_AGREEMENT_ID = @AGR_ID
             OR pt.INVOICEREF IN (
                    SELECT LREF FROM energy.dbo.LS_005_01_INVOICE WITH (NOLOCK)
                    WHERE ABYS_AGREEMENT_ID = @AGR_ID
                       OR (@AgrLref IS NOT NULL AND OWNERREF = @AgrLref)
                )
              )
        GROUP BY pt.INVOICEREF
        HAVING COUNT_BIG(*) > 1
    ) x
)
SELECT
    @AGR_ID AS AGR_ID,
    mgr.CNT AS MGR_INV,
    en.CNT  AS EN_INV,
    pt.CNT  AS EN_DEBT_PT,
    mgr.AMT AS MGR_SUM,
    en.AMT  AS EN_SUM,
    pt.AMT  AS EN_PT_SUM,
    miss.CNT AS MISSING_DEBT_PT,
    dup.CNT  AS DUP_DEBT_PT,
    CASE WHEN mgr.CNT = en.CNT THEN 'PASS' ELSE 'FAIL' END AS G_INV_CNT,
    CASE WHEN ABS(ISNULL(mgr.AMT,0) - ISNULL(en.AMT,0)) <= @Eps THEN 'PASS' ELSE 'FAIL' END AS G_INV_AMT,
    CASE WHEN en.CNT = pt.CNT THEN 'PASS' ELSE 'FAIL' END AS G_PT_CNT,
    CASE WHEN ABS(ISNULL(en.AMT,0) - ISNULL(pt.AMT,0)) <= @Eps THEN 'PASS' ELSE 'FAIL' END AS G_PT_AMT,
    CASE WHEN miss.CNT = 0 THEN 'PASS' ELSE 'FAIL' END AS G_PT_MISS,
    CASE WHEN dup.CNT = 0 THEN 'PASS' ELSE 'FAIL' END AS G_PT_DUP,
    CASE
        WHEN mgr.CNT = en.CNT
         AND en.CNT = pt.CNT
         AND ABS(ISNULL(mgr.AMT,0) - ISNULL(en.AMT,0)) <= @Eps
         AND ABS(ISNULL(en.AMT,0) - ISNULL(pt.AMT,0)) <= @Eps
         AND miss.CNT = 0
         AND dup.CNT = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS OVERALL
FROM mgr, en, pt, miss, dup;
GO

PRINT 'OVERALL=PASS ise Adim3 dogrulama tamam. Sonraki: tahsilat/eksilten.';
GO
