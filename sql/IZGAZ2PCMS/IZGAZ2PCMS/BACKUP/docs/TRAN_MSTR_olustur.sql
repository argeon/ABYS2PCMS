/* ============================================================
   HHD MSTR olusturma — GUNCEL YOL (Oracle CTAS3007)  v04

   Oracle:
     @oracleCTAS3007/09_mig_accrue_type_map.sql
     @oracleCTAS3007/LS_READING.sql
     @oracleCTAS3007/LS_READING_SYNTH.sql
     @oracleCTAS3007/LS_HHD_MSTR.sql
     @oracleCTAS3007/LS_HHD_MSTR_GATE.sql
     dump: LS_READING, LS_OV_HHD_MSTR, LS_OV_HHD_TRAN_MAP → izgazMGR
     @oracleCTAS3007/98_transfer_indexes.sql  (dump oncesi)
     Gate PASS → @99_stg_cleanup.sql

   Energy:
     521_READ_HHD_LOC_INV_TRAN__migrate.sql   (detay; ABYS_ACCRUE staging-only)
     524_READ_HHD_MSTR__apply.sql             (mstr + route_grp; ORDER BY READ_DATE, READ_NO)
     prodEnergy/00_pre_indexes.sql

   READ_NO:
     CTAS ROW_NUMBER ORDER BY READ_DATE, HAS_EOD DESC, ..., IS_SYNTH, ABYS_ACCRUE_TYPE_ID
     Gate: READ_NO artarken READ_DATE azalmamali (-20105)

   Kovalar:
     EOD     → HAS_EOD=1, grain=ENDOFDAY_ID (+region/prsnl), READING_TYPE=0
               READ_DATE = TRUNC(MIN(detay))
     ORPHAN  → HAS_EOD=0, grain=region+prsnl+TRUNC(READ_DATE); READING_TYPE=9
               sentetik: + ABYS_ACCRUE_TYPE_ID; ROUTE_GRP = ACCRUE PREFIX
     SKIP    → key kirik; gate fail (NO_MSTR_MATCH)

   O11: READ_TRANSREF ← LS_READING; TYPE/EXPLAIN ← MIG_ACCRUE_TYPE_MAP
   ============================================================ */

-- ===== ARSIV (eski energy-only yol) =====
/*
 DECLARE @MapTable TABLE (
    read_no                    INT,
    reader_region              INT,
    reader_cmp                 INT,
    read_date                  SMALLDATETIME,
    reader_prsnl               NVARCHAR(50),
    reader_prsnl_id            INT,
    ENDOFDAY_ID                INT
);

INSERT INTO energy.dbo.LS_005_01_hhd_to_hhd_mstr
    (reader_region, reader_cmp, read_date, reader_prsnl, reader_prsnl_id,
     TOTAL_COUNT, NOTREAD_COUNT, ENDOFDAY_ID, rec_status, READING_TYPE,
     ADDDATE, ADDUSER)
OUTPUT
    INSERTED.read_no,
    INSERTED.reader_region,
    INSERTED.reader_cmp,
    INSERTED.read_date,
    INSERTED.reader_prsnl,
    INSERTED.reader_prsnl_id,
    INSERTED.ENDOFDAY_ID
INTO @MapTable
    (read_no, reader_region, reader_cmp, read_date, reader_prsnl, reader_prsnl_id, ENDOFDAY_ID)
SELECT
    trn.loc_region,
    0,
    read_date,
    reader_prsnl,
    reader_prsnl_id,
    eod.LOADED_COUNT,
    eod.UNREAD_COUNT,
    trn.ABYS_READING_END_OF_DAY_ID,
    3,
    0,
    GETDATE(),
    0
FROM LS_005_01_hhd_loc_inv_tran trn
LEFT JOIN izgazMGR.dbo.CS_READING_END_OF_DAY eod
    ON eod.ID = trn.ABYS_READING_END_OF_DAY_ID
GROUP BY
    trn.loc_region, read_date, reader_prsnl, reader_prsnl_id,
    eod.LOADED_COUNT, eod.UNREAD_COUNT,
    trn.ABYS_READING_END_OF_DAY_ID;

-- DIKKAT: EOD join key yok → ayni gun/okuyucu birden fazla mstr uretirse belirsiz
UPDATE lhlit
SET lhlit.read_no = mt.read_no
FROM LS_005_01_hhd_loc_inv_tran lhlit
JOIN @MapTable mt
    ON lhlit.loc_region                 = mt.reader_region
   AND lhlit.read_date                  = mt.read_date
   AND lhlit.reader_prsnl               = mt.reader_prsnl
   AND lhlit.reader_prsnl_id            = mt.reader_prsnl_id;
*/
