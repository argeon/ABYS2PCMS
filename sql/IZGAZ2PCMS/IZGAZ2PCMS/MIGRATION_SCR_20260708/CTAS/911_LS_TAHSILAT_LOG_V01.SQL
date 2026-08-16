-- 911_LS_TAHSILAT_LOG_V01.SQL
-- Amac: Tahsilat log
-- Gate: yok
-- Sonraki: 912_CHECK_QUERIES_ORACLE_V01.SQL
-- =============================================================================
-- prod2 / 40 — TAHSILAT LOG FULL (DIAGNOSTIC)
-- Onkosul: 30_ls_tahsilat_overlay.sql
-- Soft: fail etmez; sayim raporu
-- =============================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_TAH_LOG PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_OV_TAH_LOG NOLOGGING AS
SELECT
    ROW_NUMBER() OVER (ORDER BY x.REASON, x.PAY_LREF, x.MAIN_LREF) AS LOG_ID,
    x.REASON,
    x.SEVERITY,
    x.PAY_LREF,
    x.MAIN_LREF,
    x.ACCOUNT_ID,
    x.AGREEMENT_ID,
    x.ACTION_TYPE_ID,
    x.PAYABLETOTAL,
    x.PAID_AMT,
    x.DETAIL,
    CAST('TAH_LOG' AS VARCHAR2(10)) AS OV_KIND
FROM (
    /* ortak gelir yok */
    SELECT
        CAST('NO_XREF' AS VARCHAR2(20))                          AS REASON,
        CAST('WARN' AS VARCHAR2(10))                             AS SEVERITY,
        p.LREF                                                   AS PAY_LREF,
        CAST(NULL AS NUMBER)                                     AS MAIN_LREF,
        p.ABYS_ACCOUNT_ID                                        AS ACCOUNT_ID,
        p.ABYS_AGREEMENT_ID                                      AS AGREEMENT_ID,
        p.ABYS_ACTION_TYPE_ID                                    AS ACTION_TYPE_ID,
        p.PAYABLETOTAL,
        CAST(NULL AS NUMBER)                                     AS PAID_AMT,
        CAST('Ortak INCOME_ID yok - CROSSREF/PAID uygulanmadi (' || NVL(p.OV_KIND,'PAY') || ')' AS VARCHAR2(200)) AS DETAIL
    FROM MIGRATION.LS_OV_PAY_PT p
    WHERE p.CROSSREF_MAIN_LREF IS NULL

    UNION ALL

    /* R42 iptal */
    SELECT
        CAST('PAY_CANCELED' AS VARCHAR2(20)),
        CAST('INFO' AS VARCHAR2(10)),
        p.LREF,
        p.CROSSREF_MAIN_LREF,
        p.ABYS_ACCOUNT_ID,
        p.ABYS_AGREEMENT_ID,
        p.ABYS_ACTION_TYPE_ID,
        p.PAYABLETOTAL,
        CAST(NULL AS NUMBER),
        CAST('ACTION_TYPE=9 makbuz eslesmesi - CANCELED=1' AS VARCHAR2(200))
    FROM MIGRATION.LS_OV_PAY_PT p
    WHERE NVL(p.CANCELED, 0) = 1

    UNION ALL

    /* xref var, Adim1 MAIN yok */
    SELECT
        CAST('MAIN_MISSING' AS VARCHAR2(20)),
        CAST('WARN' AS VARCHAR2(10)),
        p.LREF,
        p.CROSSREF_MAIN_LREF,
        p.ABYS_ACCOUNT_ID,
        p.ABYS_AGREEMENT_ID,
        p.ABYS_ACTION_TYPE_ID,
        p.PAYABLETOTAL,
        CAST(NULL AS NUMBER),
        CAST('CROSSREF_MAIN_LREF LS_INVOICE da yok' AS VARCHAR2(200))
    FROM MIGRATION.LS_OV_PAY_PT p
    WHERE p.CROSSREF_MAIN_LREF IS NOT NULL
      AND NOT EXISTS (
            SELECT 1 FROM MIGRATION.LS_INVOICE inv
             WHERE inv.LREF = p.CROSSREF_MAIN_LREF
          )

    UNION ALL

    /* kismi odeme — borc kapanmadi */
    SELECT
        CAST('DEBT_PARTIAL' AS VARCHAR2(20)),
        CAST('INFO' AS VARCHAR2(10)),
        CAST(NULL AS NUMBER),
        d.MAIN_LREF,
        CAST(NULL AS NUMBER),
        d.ABYS_AGREEMENT_ID,
        CAST(NULL AS NUMBER),
        NVL(inv.PAYABLETOTAL, 0),
        d.PAID_AMT,
        CAST('PAID < PAYABLE - CLOSED=0' AS VARCHAR2(200))
    FROM MIGRATION.LS_OV_DEBT_PAID_UPD d
    LEFT JOIN MIGRATION.LS_INVOICE inv ON inv.LREF = d.MAIN_LREF
    WHERE NVL(d.CLOSED, 0) = 0
      AND NVL(inv.PAYABLETOTAL, 0) > 0.01

    UNION ALL

    /* tip2 odeme ALLOC'a dusmedi (PT uretilmedi) — mahsup/bank dahil */
    SELECT
        CAST('PAY_NO_ALLOC' AS VARCHAR2(20)),
        CAST('WARN' AS VARCHAR2(10)),
        pay.ID,
        CAST(NULL AS NUMBER),
        pay.ACCOUNT_ID,
        m.AGREEMENT_ID,
        pay.ACTION_TYPE_ID,
        (
          SELECT ROUND(ABS(SUM(ai.AMOUNT * ai.STATUS)), 2)
          FROM SMS.CS_ACCOUNT_INCOME ai
          WHERE ai.ACCOUNT_ACTION_ID = pay.ID
        ),
        CAST(NULL AS NUMBER),
        CAST(
          'Tip2 odeme ALLOC yok - PT/PAID yazilmadi' ||
          CASE WHEN pay.ACTION_TYPE_ID IN (6, 24) THEN ' (MAHSUP)' ELSE '' END ||
          CASE WHEN pay.REF_DEPOSIT_ACCOUNT_ID IS NOT NULL
               THEN ' DepAcc=' || TO_CHAR(pay.REF_DEPOSIT_ACCOUNT_ID) ELSE '' END
          AS VARCHAR2(200)
        )
    FROM SMS.CS_ACCOUNT_ACTION pay
    JOIN MIGRATION.TMP_MIG_ACC m
      ON m.ACCOUNT_ID = pay.ACCOUNT_ID
    JOIN SMS.CS_ACTION_TYPE_PRM atp
      ON atp.ID = pay.ACTION_TYPE_ID AND atp.TYPE = 2
    WHERE pay.ACTION_TYPE_ID NOT IN (36, 37, 39, 44)
      AND NOT EXISTS (
            SELECT 1 FROM MIGRATION.TMP_PAY_CANCEL c WHERE c.PAY_ID = pay.ID
          )
      AND NOT EXISTS (
            SELECT 1 FROM MIGRATION.LS_OV_PAY_ALLOC a WHERE a.PAY_LREF = pay.ID
          )

    UNION ALL

    /* tip12 emanet cikisi — overlay kapsami disinda (ATP.TYPE=7) */
    SELECT
        CAST('EMANET_CIKIS_SKIP' AS VARCHAR2(20)),
        CAST('WARN' AS VARCHAR2(10)),
        pay.ID,
        CAST(NULL AS NUMBER),
        pay.ACCOUNT_ID,
        m.AGREEMENT_ID,
        pay.ACTION_TYPE_ID,
        (
          SELECT ROUND(ABS(SUM(ai.AMOUNT * ai.STATUS)), 2)
          FROM SMS.CS_ACCOUNT_INCOME ai
          WHERE ai.ACCOUNT_ACTION_ID = pay.ID
        ),
        CAST(NULL AS NUMBER),
        CAST(
          'Tip12 emanet cikisi overlay disi' ||
          CASE WHEN pay.REF_DEPOSIT_ACCOUNT_ID IS NOT NULL
               THEN ' DepAcc=' || TO_CHAR(pay.REF_DEPOSIT_ACCOUNT_ID) ELSE '' END ||
          CASE WHEN pay.REF_DEPOSIT_ACCOUNT_ACTION_ID IS NOT NULL
               THEN ' DepAct=' || TO_CHAR(pay.REF_DEPOSIT_ACCOUNT_ACTION_ID) ELSE '' END
          AS VARCHAR2(200)
        )
    FROM SMS.CS_ACCOUNT_ACTION pay
    JOIN MIGRATION.TMP_MIG_ACC m
      ON m.ACCOUNT_ID = pay.ACCOUNT_ID
    WHERE pay.ACTION_TYPE_ID = 12

    UNION ALL

    /* tip12 + borc INCOME eslesmesi — dahil edilse ALLOC uretebilirdi */
    SELECT
        CAST('EMANET_CIKIS_MATCH' AS VARCHAR2(20)),
        CAST('WARN' AS VARCHAR2(10)),
        pay.ID,
        CAST(NULL AS NUMBER),
        pay.ACCOUNT_ID,
        m.AGREEMENT_ID,
        pay.ACTION_TYPE_ID,
        (
          SELECT ROUND(ABS(SUM(ai.AMOUNT * ai.STATUS)), 2)
          FROM SMS.CS_ACCOUNT_INCOME ai
          WHERE ai.ACCOUNT_ACTION_ID = pay.ID
        ),
        CAST(NULL AS NUMBER),
        CAST(
          'Tip12 borc INCOME eslesmesi var - overlay dahil edilmedi' ||
          CASE WHEN pay.REF_DEPOSIT_ACCOUNT_ID IS NOT NULL
               THEN ' DepAcc=' || TO_CHAR(pay.REF_DEPOSIT_ACCOUNT_ID) ELSE '' END
          AS VARCHAR2(200)
        )
    FROM SMS.CS_ACCOUNT_ACTION pay
    JOIN MIGRATION.TMP_MIG_ACC m
      ON m.ACCOUNT_ID = pay.ACCOUNT_ID
    WHERE pay.ACTION_TYPE_ID = 12
      AND EXISTS (
            SELECT 1
            FROM SMS.CS_ACCOUNT_INCOME pi
            JOIN SMS.CS_ACCOUNT_ACTION g
              ON g.ACTION_TYPE_ID IN (1, 3, 10, 41)
            JOIN SMS.CS_ACCOUNT_INCOME gi
              ON gi.ACCOUNT_ACTION_ID = g.ID
             AND gi.INCOME_ID = pi.INCOME_ID
            WHERE pi.ACCOUNT_ACTION_ID = pay.ID
              AND g.ACCOUNT_ID = pay.ACCOUNT_ID
          )

    UNION ALL

    /* mahsup ama emanet hesabi yok */
    SELECT
        CAST('MAHSUP_NO_DEP' AS VARCHAR2(20)),
        CAST('WARN' AS VARCHAR2(10)),
        p.INVOICEREF,
        p.CROSSREF_MAIN_LREF,
        p.ABYS_ACCOUNT_ID,
        p.ABYS_AGREEMENT_ID,
        p.ABYS_ACTION_TYPE_ID,
        p.PAYABLETOTAL,
        CAST(NULL AS NUMBER),
        CAST('Mahsup PT REF_DEPOSIT_ACCOUNT_ID bos (alloc_rn=' || TO_CHAR(p.ALLOC_RN) || ')' AS VARCHAR2(200))
    FROM MIGRATION.LS_OV_PAY_PT p
    WHERE p.OV_KIND = 'MAHSUP'
      AND p.REF_DEPOSIT_ACCOUNT_ID IS NULL
      AND p.ALLOC_RN = 1

    UNION ALL

    /* ayni emanet > birden fazla fatura */
    SELECT
        CAST('EMANET_MULTI_MAIN' AS VARCHAR2(20)),
        CAST('INFO' AS VARCHAR2(10)),
        CAST(NULL AS NUMBER),
        c.MAIN_LREF,
        CAST(NULL AS NUMBER),
        c.ABYS_AGREEMENT_ID,
        CAST(NULL AS NUMBER),
        c.MAHSUP_AMT,
        c.BANK_AMT,
        CAST(
          'Ayni emanet DepAcc=' || TO_CHAR(c.DEP_ACCOUNT_ID) ||
          ' > ' || TO_CHAR(c.DEP_MAIN_CNT) || ' fatura - Close=' || c.CLOSE_KIND
          AS VARCHAR2(200)
        )
    FROM MIGRATION.LS_OV_MAHSUP_CLOSED c
    WHERE NVL(c.DEP_MAIN_CNT, 1) > 1
      AND c.DEP_ACCOUNT_ID IS NOT NULL

    UNION ALL

    /* mahsup DepAcc beklenen emanet (14) degil */
    SELECT
        CAST('DEP_ACCRUE_ODD' AS VARCHAR2(20)),
        CAST('INFO' AS VARCHAR2(10)),
        p.INVOICEREF,
        p.CROSSREF_MAIN_LREF,
        p.ABYS_ACCOUNT_ID,
        p.ABYS_AGREEMENT_ID,
        p.ABYS_ACTION_TYPE_ID,
        p.PAYABLETOTAL,
        CAST(NULL AS NUMBER),
        CAST(
          'Mahsup DepAcc=' || TO_CHAR(p.REF_DEPOSIT_ACCOUNT_ID) ||
          ' ACCRUE=' || TO_CHAR(NVL(a.ACCRUE_TYPE_ID, -1)) || ' (beklenen 14)'
          AS VARCHAR2(200)
        )
    FROM MIGRATION.LS_OV_PAY_PT p
    JOIN SMS.CS_ACCOUNT a
      ON a.ID = p.REF_DEPOSIT_ACCOUNT_ID
    WHERE p.OV_KIND = 'MAHSUP'
      AND p.ALLOC_RN = 1
      AND p.REF_DEPOSIT_ACCOUNT_ID IS NOT NULL
      AND NVL(a.ACCRUE_TYPE_ID, -1) <> 14
) x;

CREATE UNIQUE INDEX MIGRATION.IX_OV_TAH_LOG ON MIGRATION.LS_OV_TAH_LOG (LOG_ID);
/
CREATE INDEX MIGRATION.IX_OV_TAH_LOG_RSN ON MIGRATION.LS_OV_TAH_LOG (REASON);
/
CREATE INDEX MIGRATION.IX_OV_TAH_LOG_AGR ON MIGRATION.LS_OV_TAH_LOG (AGREEMENT_ID);
/

-- =============================================================================
-- LOG GATE (sadece sayim — fail etmez)
-- =============================================================================
SELECT 'TAH_LOG' AS K, 'CNT' AS V, COUNT(*) AS N FROM MIGRATION.LS_OV_TAH_LOG
UNION ALL
SELECT 'LOG_' || REASON, 'CNT', COUNT(*) FROM MIGRATION.LS_OV_TAH_LOG GROUP BY REASON;

PROMPT ========== 40 TAHSILAT LOG OK ==========
/
