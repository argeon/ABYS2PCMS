-- 208_GATE_PILOT_PARITY_V01.SQL
-- Amac: Parity / dump kapisi
-- Gate: PASS zorunlu
-- Sonraki: 209_TUKETIM_TUTAR_KONTROL_V01.SQL
-- =============================================================================
-- oracleCTAS3007 / 58 — GATE pilot parity (hard stop)
-- Onkosul: O30–O57 zinciri
-- Pilot gap'lerinin Oracle tarafında kapanmış olduğunu doğrular.
-- =============================================================================

WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
  v_fail NUMBER := 0;
  v_msg  VARCHAR2(4000) := '';
  n      NUMBER;
  n2     NUMBER;

  PROCEDURE need_table(p_name VARCHAR2) IS
  BEGIN
    SELECT COUNT(*) INTO n FROM ALL_TABLES
     WHERE OWNER='MIGRATION' AND TABLE_NAME=p_name;
    IF n = 0 THEN
      v_fail := v_fail + 1;
      v_msg := v_msg || ' MISSING:' || p_name;
    END IF;
  END;

  PROCEDURE need_col(p_tab VARCHAR2, p_col VARCHAR2) IS
  BEGIN
    SELECT COUNT(*) INTO n FROM ALL_TAB_COLUMNS
     WHERE OWNER='MIGRATION' AND TABLE_NAME=p_tab AND COLUMN_NAME=p_col;
    IF n = 0 THEN
      v_fail := v_fail + 1;
      v_msg := v_msg || ' COL:' || p_tab || '.' || p_col;
    END IF;
  END;
BEGIN
  BEGIN
    MIGRATION.P_MIG_CTAS_LOG('O58', 'gate_pilot_parity', 'START', NULL, 'hard gate');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  need_table('LS_DEBT_PAYTRANS');
  need_table('LS_INVOICE');
  need_table('LS_OV_PAY_PT');
  need_table('LS_OV_PAY_ALLOC');
  need_table('LS_OV_DEBT_PAID_UPD');
  need_table('LS_AFL_OPEN_DEBT');
  need_table('LS_STG_INV_PAY_CLOSE');
  need_table('LS_PAYMENT');
  need_table('LS_TAKSIT');
  need_table('LS_INSTALLMENT_PLAN_PAY');
  need_table('LS_EKSILTEN');
  need_table('LS_PARTIAL_EKSILTEN');
  need_table('LS_MAHSUP');
  need_table('LS_OV_ID_MAP');

  need_col('LS_INVOICE', 'ABYS_INSTALLMENT_ID');
  need_col('LS_INVOICE', 'INSTALLMENT_PLAN_REF');
  need_col('LS_INVOICE', 'BANKREF');
  need_col('LS_INVOICE', 'BANK_RECORD_REF');
  need_col('LS_INVOICE', 'LASTPAIDDATE');
  need_col('LS_OV_PAY_PT', 'BANKREF');
  need_col('LS_OV_PAY_PT', 'BANK_RECORD_REF');
  need_col('LS_OV_PAY_PT', 'PAID');
  need_col('LS_OV_PAY_PT', 'XTYPE');
  need_table('LS_OV_TAH_INVOICE');
  need_col('LS_OV_TAH_INVOICE', 'BANKREF');
  need_col('LS_OV_TAH_INVOICE', 'BANK_RECORD_REF');
  need_col('LS_OV_TAH_INVOICE', 'LASTPAIDDATE');
  need_col('LS_OV_TAH_INVOICE', 'EXPLAIN');
  need_col('LS_DEBT_PAYTRANS', 'PAID');
  need_col('LS_DEBT_PAYTRANS', 'BANKREF');
  need_col('LS_INSTALLMENT_PLAN_PAY', 'PAYMENT_DATE');
  need_col('LS_INSTALLMENT_PLAN_PAY', 'ORDER_NUMBER');

  -- PT vs ALLOC sayım (O41 ile aynı ruh)
  SELECT COUNT(*) INTO n FROM MIGRATION.LS_OV_PAY_PT
   WHERE OV_KIND='PAY' AND NVL(CANCELED,0)=0;
  SELECT COUNT(*) INTO n2 FROM MIGRATION.LS_OV_PAY_ALLOC;
  IF n = 0 OR n2 = 0 THEN
    v_fail := v_fail + 1;
    v_msg := v_msg || ' EMPTY_PAY_OR_ALLOC';
  END IF;

  -- PAY uncanceled ama PAID≈0 (O34 kaçırdıysa)
  SELECT COUNT(*) INTO n FROM MIGRATION.LS_OV_PAY_PT
   WHERE OV_KIND='PAY' AND NVL(CANCELED,0)=0
     AND NVL(PAID,0) + 0.01 < NVL(PAYABLETOTAL,0)
     AND NVL(PAYABLETOTAL,0) > 0.01;
  IF n > 0 THEN
    v_fail := v_fail + 1;
    v_msg := v_msg || ' PAY_PAID_GAP=' || n;
  END IF;

  -- CROSSREF null PAY
  SELECT COUNT(*) INTO n FROM MIGRATION.LS_OV_PAY_PT
   WHERE OV_KIND='PAY' AND NVL(CANCELED,0)=0 AND CROSSREF_MAIN_LREF IS NULL;
  IF n > 0 THEN
    v_fail := v_fail + 1;
    v_msg := v_msg || ' PAY_NO_XREF=' || n;
  END IF;

  -- Taksit plan satırı var mı
  SELECT COUNT(*) INTO n FROM MIGRATION.LS_INSTALLMENT_PLAN_PAY;
  IF n = 0 THEN
    -- soft: ortamda hiç taksit yoksa INFO; FAIL etme
    DBMS_OUTPUT.PUT_LINE('O58 INFO: LS_INSTALLMENT_PLAN_PAY empty (no installment data?)');
  END IF;

  IF v_fail > 0 THEN
    BEGIN
      MIGRATION.P_MIG_CTAS_LOG('O58', 'gate_pilot_parity', 'GATE_FAIL', v_fail, SUBSTR(v_msg,1,500));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    RAISE_APPLICATION_ERROR(-20058, 'O58 GATE_FAIL:' || SUBSTR(v_msg,1,500));
  END IF;

  BEGIN
    MIGRATION.P_MIG_CTAS_LOG('O58', 'gate_pilot_parity', 'GATE_PASS', 0, 'pilot parity OK');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  DBMS_OUTPUT.PUT_LINE('========== O58 GATE_PASS — dump serbest ==========');
END;
/

