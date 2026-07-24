-- =============================================================================
-- prod2 / 50 — AFL OPEN DEBT (FRK master snapshot)
-- Ortam : Oracle 11.2 | Schema: MIGRATION | Kaynak: SMS
-- Tek basina calisir; B zorunlu zinciri BLOKE ETMEZ
--
-- Grain : CS_ACCOUNT.ID = FATURAID  (energy FRK: ABYS_ACCOUNT_ID)
-- Master: tahsile acik borclar SUM(status*amount) > 0
--
-- Duzeltmeler (kaynak AFL sorgusuna gore):
--   installment_id / legal_proceeding_id → IS NOT NULL ( != null yanlis)
--   GECIKME_BEDELI: CTAS'ta NULL (fonksiyon bagimliligi yok; FRK balance odaklı)
--   MIG_IN_SCOPE: ACCRUE_TYPE_ID <> 14 (migrasyon kapsami; AFL ham satirda kalir)
--
-- Dump → izgazMGR.dbo.LS_AFL_OPEN_DEBT → energy 90_afl_frk
-- =============================================================================

ALTER SESSION ENABLE PARALLEL DML;
ALTER SESSION ENABLE PARALLEL QUERY;

BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_AFL_OPEN_DEBT PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
CREATE TABLE MIGRATION.LS_AFL_OPEN_DEBT NOLOGGING AS
SELECT
    a.ID                                                         AS FATURAID,
    a.AGREEMENT_ID                                               AS SOZLESME_HESABI,
    a.EXPIRY_DATE                                                AS EXPIRY_DATE,
    ROUND(SUM(ai.STATUS * ai.AMOUNT), 2)                         AS BALANCE,
    CAST(NULL AS NUMBER(18,2))                                   AS GECIKME_BEDELI,
    stpl.VALUE                                                   AS SUBSCRIBER_TYPE,
    ttpl.VALUE                                                   AS TARIFF_TYPE,
    ttpl2.VALUE                                                  AS SKB_TARIFF_TYPE,
    CASE WHEN a.INSTALLMENT_ID IS NOT NULL THEN 'T' ELSE 'N' END AS TAKSIT_DURUMU,
    CASE WHEN a.LEGAL_PROCEEDING_ID IS NOT NULL THEN 'VAR' ELSE 'YOK' END AS YT_DURUMU,
    a.INSTALLMENT_ID,
    a.LEGAL_PROCEEDING_ID,
    a.ACCRUE_TYPE_ID,
    CASE WHEN NVL(a.ACCRUE_TYPE_ID, -1) <> 14 THEN 1 ELSE 0 END  AS MIG_IN_SCOPE,
    CAST(DATE '2026-07-24' AS DATE)                              AS AS_OF_DATE,
    CAST(SYSDATE AS DATE)                                        AS SNAPSHOT_DATE
FROM SMS.CS_ACCOUNT a
JOIN SMS.CS_ACCOUNT_ACTION aa
  ON aa.ACCOUNT_ID = a.ID
JOIN SMS.CS_ACCOUNT_INCOME ai
  ON ai.ACCOUNT_ACTION_ID = aa.ID
JOIN SMS.CS_INCOME_PRM ip
  ON ip.ID = ai.INCOME_ID
LEFT JOIN SMS.CS_SUBSCRIBER_TYPE_PRM_LNG stpl
  ON stpl.PRM_ID = a.SUBSCRIBER_TYPE_ID AND stpl.LANG_ID = 1
LEFT JOIN SMS.CS_TARIFF_TYPE_PRM_LNG ttpl
  ON ttpl.PRM_ID = a.TARIFF_TYPE_ID AND ttpl.LANG_ID = 1
LEFT JOIN SMS.CS_TARIFF_TYPE_PRM_LNG ttpl2
  ON ttpl2.PRM_ID = a.SKB_TARIFF_TYPE_ID AND ttpl2.LANG_ID = 1
GROUP BY
    a.ID, a.AGREEMENT_ID, a.EXPIRY_DATE,
    stpl.VALUE, ttpl.VALUE, ttpl2.VALUE,
    a.LEGAL_PROCEEDING_ID, a.INSTALLMENT_ID, a.ACCRUE_TYPE_ID
HAVING SUM(ai.STATUS * ai.AMOUNT) > 0;

CREATE UNIQUE INDEX MIGRATION.IX_AFL_FATURA ON MIGRATION.LS_AFL_OPEN_DEBT (FATURAID);
CREATE INDEX MIGRATION.IX_AFL_AGR ON MIGRATION.LS_AFL_OPEN_DEBT (SOZLESME_HESABI);
CREATE INDEX MIGRATION.IX_AFL_MIG ON MIGRATION.LS_AFL_OPEN_DEBT (MIG_IN_SCOPE);

BEGIN DBMS_STATS.GATHER_TABLE_STATS('MIGRATION','LS_AFL_OPEN_DEBT'); END;
/

-- RECON
SELECT
    COUNT(*) AS AFL_CNT,
    COUNT(CASE WHEN MIG_IN_SCOPE = 1 THEN 1 END) AS MIG_SCOPE_CNT,
    COUNT(CASE WHEN TAKSIT_DURUMU = 'T' THEN 1 END) AS TAKSIT_CNT,
    ROUND(SUM(BALANCE), 2) AS AFL_BAL_SUM,
    ROUND(SUM(CASE WHEN MIG_IN_SCOPE = 1 THEN BALANCE ELSE 0 END), 2) AS MIG_BAL_SUM
FROM MIGRATION.LS_AFL_OPEN_DEBT;

PROMPT ========== 50 AFL OPEN DEBT OK — dump LS_AFL_OPEN_DEBT → izgazMGR ==========
/
