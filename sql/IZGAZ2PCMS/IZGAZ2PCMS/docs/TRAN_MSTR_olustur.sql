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

-- Detay satırlarını güncelle
UPDATE lhlit
SET lhlit.read_no = mt.read_no
FROM LS_005_01_hhd_loc_inv_tran lhlit
JOIN @MapTable mt
    ON lhlit.loc_region                 = mt.reader_region
   AND lhlit.read_date                  = mt.read_date
   AND lhlit.reader_prsnl               = mt.reader_prsnl
   AND lhlit.reader_prsnl_id            = mt.reader_prsnl_id






 

