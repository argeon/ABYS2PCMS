WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED

-- =============================================================================
-- oracleCTAS3007 / 27 — GATE eksilten (SRC_KEY) HARD
-- PASS: TAM=IADE=IADE_PT; KISMI_HDR=KISMI_PT; SRC_KEY dolu
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

BEGIN
  MIGRATION.P_MIG_CTAS_LOG('O27', 'gate_eksilten', 'START', NULL, 'hard gate');
END;
/

SELECT KIND, COUNT(*) CNT
FROM MIGRATION.LS_OV_EKS_CLASS
GROUP BY KIND
ORDER BY 1;

SELECT
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_EKS_CLASS WHERE KIND='TAM' AND MAIN_LREF IS NOT NULL) TAM,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_IADE_INVOICE) IADE,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_MAIN_UPD) MAIN_UPD,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_IADE_INVLINES) IADE_IL,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_IADE_PAYTRANS) IADE_PT,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_KISMI_INVLINES) KISMI_IL,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_KISMI_HDR) KISMI_HDR,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_KISMI_PAYTRANS) KISMI_PT,
    (SELECT COUNT(*) FROM MIGRATION.LS_OV_EKS_SKIP) ASIM_SKIP
FROM DUAL;

DECLARE
  n_tam NUMBER; n_iade NUMBER; n_upd NUMBER; n_pt NUMBER;
  n_kh NUMBER; n_kpt NUMBER; n_src NUMBER; n_tgt NUMBER;
  v_note VARCHAR2(400);
BEGIN
  SELECT COUNT(*) INTO n_tam FROM MIGRATION.LS_OV_EKS_CLASS WHERE KIND='TAM' AND MAIN_LREF IS NOT NULL;
  SELECT COUNT(*) INTO n_iade FROM MIGRATION.LS_OV_IADE_INVOICE;
  SELECT COUNT(*) INTO n_upd FROM MIGRATION.LS_OV_MAIN_UPD;
  SELECT COUNT(*) INTO n_pt FROM MIGRATION.LS_OV_IADE_PAYTRANS;
  SELECT COUNT(*) INTO n_kh FROM MIGRATION.LS_OV_KISMI_HDR;
  SELECT COUNT(*) INTO n_kpt FROM MIGRATION.LS_OV_KISMI_PAYTRANS;
  SELECT COUNT(*) INTO n_src FROM MIGRATION.LS_OV_IADE_INVOICE WHERE SRC_KEY IS NULL;
  SELECT COUNT(*) INTO n_tgt FROM MIGRATION.LS_OV_MAIN_UPD WHERE RETURN_TARGET_SRC_KEY IS NULL;

  IF n_tam <> n_iade THEN
    v_note := 'TAM(' || n_tam || ') <> IADE(' || n_iade || ')';
    MIGRATION.P_MIG_CTAS_LOG('O27', 'gate_eksilten', 'GATE_FAIL', n_tam, v_note);
    RAISE_APPLICATION_ERROR(-20027, 'GATE FAIL: ' || v_note);
  END IF;
  IF n_tam <> n_pt THEN
    v_note := 'TAM(' || n_tam || ') <> IADE_PT(' || n_pt || ')';
    MIGRATION.P_MIG_CTAS_LOG('O27', 'gate_eksilten', 'GATE_FAIL', n_tam, v_note);
    RAISE_APPLICATION_ERROR(-20028, 'GATE FAIL: ' || v_note);
  END IF;
  IF n_upd > n_tam THEN
    v_note := 'MAIN_UPD(' || n_upd || ') > TAM(' || n_tam || ')';
    MIGRATION.P_MIG_CTAS_LOG('O27', 'gate_eksilten', 'GATE_FAIL', n_upd, v_note);
    RAISE_APPLICATION_ERROR(-20029, 'GATE FAIL: ' || v_note);
  END IF;
  IF n_kh <> n_kpt THEN
    v_note := 'KISMI_HDR(' || n_kh || ') <> KISMI_PT(' || n_kpt || ')';
    MIGRATION.P_MIG_CTAS_LOG('O27', 'gate_eksilten', 'GATE_FAIL', n_kh, v_note);
    RAISE_APPLICATION_ERROR(-20030, 'GATE FAIL: ' || v_note);
  END IF;
  IF n_src > 0 THEN
    v_note := 'IADE SRC_KEY NULL=' || n_src;
    MIGRATION.P_MIG_CTAS_LOG('O27', 'gate_eksilten', 'GATE_FAIL', n_src, v_note);
    RAISE_APPLICATION_ERROR(-20031, 'GATE FAIL: ' || v_note);
  END IF;
  IF n_tgt > 0 THEN
    v_note := 'MAIN_UPD RETURN_TARGET_SRC_KEY NULL=' || n_tgt;
    MIGRATION.P_MIG_CTAS_LOG('O27', 'gate_eksilten', 'GATE_FAIL', n_tgt, v_note);
    RAISE_APPLICATION_ERROR(-20032, 'GATE FAIL: ' || v_note);
  END IF;

  v_note := 'tam=' || n_tam || ' iade=' || n_iade || ' main_upd=' || n_upd
         || ' kismi_hdr=' || n_kh || ' kismi_pt=' || n_kpt;
  MIGRATION.P_MIG_CTAS_LOG('O27', 'gate_eksilten', 'GATE_PASS', n_tam, v_note);
  DBMS_OUTPUT.PUT_LINE('========== O27 GATE EKSILTEN PASS | ' || v_note || ' ==========');
END;
/
