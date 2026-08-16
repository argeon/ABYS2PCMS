-- 902_STG_CLEANUP_V01.SQL
-- Amac: STG/TMP drop (opsiyonel)
-- Gate: yok
-- Sonraki: 910_HOTFIX_LS_OV_TAH_LOG_V01.SQL
-- =============================================================================
-- oracleCTAS3007 / 99_stg_cleanup.sql
-- Tek kullanimlik STG/TMP DROP (Gate PASS sonrasi).
-- Gate FAIL ise CALISTIRMA.
-- =============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
  PROCEDURE drop_if(p_owner VARCHAR2, p_table VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE ' || p_owner || '.' || p_table || ' PURGE';
    DBMS_OUTPUT.PUT_LINE('DROPPED ' || p_owner || '.' || p_table);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -942 THEN
        DBMS_OUTPUT.PUT_LINE('MISS  ' || p_owner || '.' || p_table);
      ELSE
        RAISE;
      END IF;
  END;
BEGIN
  -- Reading stages
  drop_if('MIGRATION', 'STG_RD_SYNC_USER');
  drop_if('MIGRATION', 'STG_RD_USER_COMP');
  drop_if('MIGRATION', 'STG_RD_READING_INC');
  drop_if('MIGRATION', 'STG_RD_ACC_INC');
  drop_if('MIGRATION', 'STG_RD_SYNTH_GAP');

  -- HHD ara (normalde LS_HHD_MSTR sonu zaten DROP)
  drop_if('MIGRATION', 'TMP_HHD_TRAN_KEY');
  drop_if('MIGRATION', 'LS_OV_HHD_MSTR_EOD');
  drop_if('MIGRATION', 'LS_OV_HHD_MSTR_ORPHAN');

  -- O30 / O33 / O51 TMP
  drop_if('MIGRATION', 'TMP_MIG_ACC');
  drop_if('MIGRATION', 'TMP_PAY_CANCEL');
  drop_if('MIGRATION', 'TMP_O33_LAST_PAY');
  drop_if('MIGRATION', 'TMP_O33_OPEN_ACC');
  drop_if('MIGRATION', 'TMP_O33_BAL');
  drop_if('MIGRATION', 'TMP_STG_PAY_AGG');
  drop_if('MIGRATION', 'TMP_STG_BANK_NM');

  -- O60 ara pivot (OV_GUVENCE_IADE_* kalir — dump)
  drop_if('MIGRATION', 'STG_GUV_IADE_PIVOT');

  -- Opsiyonel: tarife / invoice income (yeniden kosu yoksa)
  -- drop_if('MIGRATION', 'STG_TARIFF_MAP');
  -- drop_if('MIGRATION', 'STG_INV_ACC_INC');

  DBMS_OUTPUT.PUT_LINE('========== 99_stg_cleanup OK ==========');
END;
/

