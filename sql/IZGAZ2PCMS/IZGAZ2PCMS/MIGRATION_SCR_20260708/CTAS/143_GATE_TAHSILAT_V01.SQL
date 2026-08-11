-- 143_GATE_TAHSILAT_V01.SQL
-- Amac: Tahsilat hard gate
-- Gate: PASS zorunlu
-- Sonraki: 200_LS_AFL_OPEN_DEBT_V01.SQL
WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- =============================================================================
-- oracleCTAS3007 / 41 — GATE tahsilat
-- HARD PASS: PAY_PT = PAY_ALLOC; CROSSREF_MAIN NULL = 0
-- SOFT (kabul): EARLY_PAY — tahsilat once, fatura sonra; O30 uzerine islenir
--   early_ok    = ALLOC yazilmis erken odeme (beklenen)
--   early_ghost = ALLOC yok kalan sayim — WARN, FAIL etmez
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

BEGIN
  MIGRATION.P_MIG_CTAS_LOG('O41', 'gate_tahsilat', 'START', NULL, 'hard: pt=alloc xref; soft: early_pay');
END;
/

SELECT 'PAY_PT' K, COUNT(*) N FROM MIGRATION.LS_OV_PAY_PT
UNION ALL SELECT 'PAY_OK', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE NVL(CANCELED,0)=0
UNION ALL SELECT 'PAY_CANC', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE NVL(CANCELED,0)=1
UNION ALL SELECT 'PAY_BANK', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE OV_KIND='PAY' AND NVL(CANCELED,0)=0
UNION ALL SELECT 'PAY_MAHSUP', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE OV_KIND='MAHSUP' AND NVL(CANCELED,0)=0
UNION ALL SELECT 'PAY_NO_XREF', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE CROSSREF_MAIN_LREF IS NULL
UNION ALL SELECT 'PAY_ALLOC', COUNT(*) FROM MIGRATION.LS_OV_PAY_ALLOC
UNION ALL SELECT 'CANCEL_PAY', COUNT(*) FROM MIGRATION.LS_OV_CANCEL_PAY
UNION ALL SELECT 'CANCEL_REV', COUNT(*) FROM MIGRATION.LS_OV_CANCEL_REV
UNION ALL SELECT 'MAP_ROWS', COUNT(*) FROM MIGRATION.LS_OV_ID_MAP;

DECLARE
  n_pt NUMBER; n_al NUMBER; n_xr NUMBER; n_multi NUMBER; n_map NUMBER;
  n_tmp NUMBER; n_col NUMBER; n_early_ghost NUMBER := -1; n_early_ok NUMBER := -1;
  v_note VARCHAR2(400);
BEGIN
  SELECT COUNT(*) INTO n_pt FROM MIGRATION.LS_OV_PAY_PT;
  SELECT COUNT(*) INTO n_al FROM MIGRATION.LS_OV_PAY_ALLOC;
  SELECT COUNT(*) INTO n_xr FROM MIGRATION.LS_OV_PAY_PT WHERE CROSSREF_MAIN_LREF IS NULL;
  SELECT COUNT(*) INTO n_multi FROM (
    SELECT PAY_LREF FROM MIGRATION.LS_OV_PAY_ALLOC GROUP BY PAY_LREF HAVING COUNT(*) > 1
  );
  SELECT COUNT(*) INTO n_map FROM MIGRATION.LS_OV_ID_MAP;

  IF n_pt <> n_al THEN
    v_note := 'PAY_PT(' || n_pt || ') <> PAY_ALLOC(' || n_al || ')';
    MIGRATION.P_MIG_CTAS_LOG('O41', 'gate_tahsilat', 'GATE_FAIL', n_pt, v_note);
    RAISE_APPLICATION_ERROR(-20051, 'GATE FAIL: ' || v_note);
  END IF;
  IF n_xr > 0 THEN
    v_note := 'PAY_NO_XREF=' || n_xr;
    MIGRATION.P_MIG_CTAS_LOG('O41', 'gate_tahsilat', 'GATE_FAIL', n_xr, v_note);
    RAISE_APPLICATION_ERROR(-20052, 'GATE FAIL: ' || v_note);
  END IF;

  /* Soft: tahsilat once / fatura sonra — ALLOC yazilmis (kabul, beklenen) */
  SELECT COUNT(DISTINCT a.PAY_LREF)
    INTO n_early_ok
  FROM MIGRATION.LS_OV_PAY_ALLOC a
  JOIN MIGRATION.LS_OV_PAY_PT pt
    ON pt.INVOICEREF = a.PAY_LREF
   AND pt.CROSSREF_MAIN_LREF = a.MAIN_LREF
  JOIN MIGRATION.LS_INVOICE inv
    ON inv.LREF = a.MAIN_LREF
  WHERE inv.DATE_ IS NOT NULL
    AND pt.DATE_ IS NOT NULL
    AND inv.DATE_ > pt.DATE_;

  /* Soft: ayni senaryo, ALLOC kalmamis — sayim/WARN, FAIL yok (is kurali kabul) */
  SELECT COUNT(*) INTO n_tmp FROM ALL_TABLES
   WHERE OWNER = 'MIGRATION' AND TABLE_NAME = 'TMP_MIG_ACC';
  SELECT COUNT(*) INTO n_col FROM ALL_TAB_COLUMNS
   WHERE OWNER = 'SMS' AND TABLE_NAME = 'CS_ACCOUNT_ACTION' AND COLUMN_NAME = 'ACTION_DATE';

  IF n_tmp = 0 THEN
    MIGRATION.P_MIG_CTAS_LOG('O41', 'early_pay', 'INFO', n_early_ok,
      'TMP_MIG_ACC yok — early_ghost skip; early_ok=' || n_early_ok);
    DBMS_OUTPUT.PUT_LINE('O41 EARLY_PAY: TMP_MIG_ACC yok — ghost SKIP; early_ok=' || n_early_ok);
  ELSIF n_col = 0 THEN
    MIGRATION.P_MIG_CTAS_LOG('O41', 'early_pay', 'INFO', n_early_ok,
      'ACTION_DATE yok — early_ghost skip; early_ok=' || n_early_ok);
    DBMS_OUTPUT.PUT_LINE('O41 EARLY_PAY: ACTION_DATE yok — ghost SKIP; early_ok=' || n_early_ok);
  ELSE
    /* Nested inline-view icinde pay.ID → ORA-00904; korelasyon tek seviye */
    SELECT COUNT(DISTINCT pay.ID)
      INTO n_early_ghost
    FROM SMS.CS_ACCOUNT_ACTION pay
    JOIN MIGRATION.TMP_MIG_ACC m
      ON m.ACCOUNT_ID = pay.ACCOUNT_ID
    JOIN SMS.CS_ACTION_TYPE_PRM atp
      ON atp.ID = pay.ACTION_TYPE_ID AND atp.TYPE = 2
    WHERE pay.ACTION_TYPE_ID NOT IN (36, 37, 39, 44, 6, 24)
      AND NOT EXISTS (
            SELECT 1 FROM MIGRATION.TMP_PAY_CANCEL c WHERE c.PAY_ID = pay.ID
          )
      AND NOT EXISTS (
            SELECT 1 FROM MIGRATION.LS_OV_PAY_ALLOC a WHERE a.PAY_LREF = pay.ID
          )
      AND EXISTS (
            SELECT 1
            FROM SMS.CS_ACCOUNT_INCOME pi
            JOIN SMS.CS_ACCOUNT_INCOME gi
              ON gi.INCOME_ID = pi.INCOME_ID
            JOIN SMS.CS_ACCOUNT_ACTION g
              ON g.ID = gi.ACCOUNT_ACTION_ID
            WHERE pi.ACCOUNT_ACTION_ID = pay.ID
              AND g.ACCOUNT_ID = pay.ACCOUNT_ID
              AND g.ACTION_TYPE_ID IN (1, 3, 10, 41)
              AND g.ACTION_DATE > pay.ACTION_DATE
              AND (
                    SELECT ABS(SUM(pi2.AMOUNT * pi2.STATUS))
                    FROM SMS.CS_ACCOUNT_INCOME pi2
                    WHERE pi2.ACCOUNT_ACTION_ID = pay.ID
                      AND pi2.INCOME_ID = pi.INCOME_ID
                  ) > 0.0001
          );

    DBMS_OUTPUT.PUT_LINE('O41 EARLY_PAY (SOFT/KABUL): ok=' || n_early_ok
      || ' ghost_warn=' || n_early_ghost);
    MIGRATION.P_MIG_CTAS_LOG('O41', 'early_pay', 'INFO', n_early_ok,
      'SOFT ok=' || n_early_ok || ' ghost_warn=' || n_early_ghost);
    IF n_early_ghost > 0 THEN
      MIGRATION.P_MIG_CTAS_LOG('O41', 'early_pay', 'WARN', n_early_ghost,
        'EARLY_PAY_GHOST=' || n_early_ghost
        || ' — hard PASS; residual (diag 41_diag_early_pay_ghost; sonraki O30)');
    END IF;
  END IF;

  v_note := 'pt=' || n_pt || ' alloc=' || n_al || ' multi=' || n_multi
         || ' map=' || n_map
         || ' early_ok=' || CASE WHEN n_early_ok < 0 THEN 'SKIP' ELSE TO_CHAR(n_early_ok) END
         || ' early_ghost=' || CASE WHEN n_early_ghost < 0 THEN 'SKIP' ELSE TO_CHAR(n_early_ghost) END
         || ' (early=SOFT)';
  MIGRATION.P_MIG_CTAS_LOG('O41', 'gate_tahsilat', 'GATE_PASS', n_pt, v_note);
  DBMS_OUTPUT.PUT_LINE('========== O41 GATE TAHSILAT PASS | ' || v_note || ' ==========');
END;
/

