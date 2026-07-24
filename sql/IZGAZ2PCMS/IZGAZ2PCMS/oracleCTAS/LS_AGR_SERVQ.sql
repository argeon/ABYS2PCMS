 
CREATE TABLE LS_AGR_SERVQ AS
select * from 
(
-- ============================================
-- Query 1: CS_INSTALLATION üzerinden (agreement bazlı)
-- ============================================
SELECT
    CASE mtp.ID
        WHEN 16 THEN 109
        WHEN 17 THEN 9       
        WHEN 20 THEN 13
        WHEN 21 THEN 105
        WHEN 22 THEN 3
        WHEN 23 THEN 4
        WHEN 18 THEN 10   
        WHEN 24 THEN 5
        WHEN 25 THEN 1
        WHEN 26 THEN 6
        WHEN 27 THEN 2
        WHEN 29 THEN 7
        WHEN 30 THEN 8
        WHEN 31 THEN 14
        WHEN 32 THEN 101
        ELSE -99
    END                       AS MID,
    1                         AS TID,
    agr.id                    AS AGRID,
    0                         AS TYPE_,
    m.METER_NUMBER            AS SNO,
    0                         AS MIDOLD,
    ix.LAST_INDEX             AS LASTENDEX,
    mmpl.VALUE,
    mtp.CODE,
    m.id                      AS ITEMID,
    iip.USED_PRESSURE,
    CASE iip.USED_PRESSURE
        WHEN 21    THEN 34
        WHEN 300   THEN 35
        WHEN 120   THEN 48
        WHEN 1000  THEN 609
        WHEN 4000  THEN 610
        WHEN 500   THEN 618
        WHEN 2000  THEN 637
        WHEN 3000  THEN 638
        WHEN 15000 THEN 639
        WHEN 2200  THEN 641
        WHEN 30000 THEN 642
        WHEN 2500  THEN 645
        WHEN 5000  THEN 666
        WHEN 50    THEN 667
        WHEN 19000 THEN 670
        WHEN 1400  THEN 705
        WHEN 0     THEN 844
        WHEN 6000  THEN 845
        WHEN 100   THEN 846
        WHEN 16000 THEN 847
        WHEN 12000 THEN 920
        ELSE -99
    END                       AS CALCPRESSID, 
    agr.created_tımestamp  ADDDATE,1 ISACTIVE,  'KUL' as TP2
    
FROM CS_INSTALLATION i
JOIN CS_AGREEMENT agr
    ON agr.INSTALLATION_ID = i.id
--JOIN CS_INSTALLATION_INDEX ii
--    ON ii.INSTALLATION_ID = i.id AND ii.INDEX_TYPE_ID = 1
JOIN CS_METER m
    ON i.METER_ID = m.id
JOIN cs_meter_model_prm mmp
    ON mmp.id = m.METER_MODEL_ID
JOIN cs_meter_model_prm_lng mmpl
    ON mmpl.prm_id = mmp.id AND mmpl.lang_id = 1
JOIN cs_meter_type_prm mtp
    ON mtp.id = mmp.METER_TYPE_ID
LEFT JOIN cs_INSTALLATION_INDEX ix
    ON ix.INSTALLATION_ID = i.id
   AND ix.INDEX_TYPE_ID = 1
   AND ix.IS_ACTIVE = 1
LEFT JOIN cs_INSTALLATION_INDEX ixK
    ON ixK.INSTALLATION_ID = i.id
   AND ixK.INDEX_TYPE_ID = 2
   AND ixK.IS_ACTIVE = 1
LEFT JOIN (
    SELECT USED_PRESSURE, INSTALLATION_ID
    FROM (
        SELECT
            USED_PRESSURE,
            INSTALLATION_ID,
            ROW_NUMBER() OVER (PARTITION BY INSTALLATION_ID ORDER BY ID DESC) AS rn
        FROM II_PROJECT_INSTALLATION
    ) t
    WHERE rn = 1
) iip
    ON iip.INSTALLATION_ID = i.id
--WHERE agr.id = 197168

UNION ALL

-- ============================================
-- Query 2: CS_AGREEMENT_SUBSCRIBER üzerinden (subscriber bazlı)
-- ============================================
SELECT
    CASE mtp.ID
        WHEN 16 THEN 109
        WHEN 17 THEN 9
        WHEN 18 THEN 11   -- ⚠️ aynı çakışma burada da mevcut
        WHEN 20 THEN 13
        WHEN 21 THEN 105
        WHEN 22 THEN 3
        WHEN 23 THEN 4
        -- WHEN 18 THEN 10   -- ⚠️ dead code
        WHEN 24 THEN 5
        WHEN 25 THEN 1
        WHEN 26 THEN 6
        WHEN 27 THEN 2
        WHEN 29 THEN 7
        WHEN 30 THEN 8
        WHEN 31 THEN 14
        WHEN 32 THEN 101
        ELSE -99
    END                       AS MID,
    1                         AS TID,
    as_.id                    AS AGRID,
    0                         AS TYPE_,
    m.METER_NUMBER            AS SNO,
    0                         AS MIDOLD,
    ix.LAST_INDEX             AS LASTENDEX,
    mmpl.VALUE,
    mtp.CODE,
    m.id                      AS ITEMID,
    iip.USED_PRESSURE,
    CASE iip.USED_PRESSURE
        WHEN 21    THEN 34
        WHEN 300   THEN 35
        WHEN 120   THEN 48
        WHEN 1000  THEN 609
        WHEN 4000  THEN 610
        WHEN 500   THEN 618
        WHEN 2000  THEN 637
        WHEN 3000  THEN 638
        WHEN 15000 THEN 639
        WHEN 2200  THEN 641
        WHEN 30000 THEN 642
        WHEN 2500  THEN 645
        WHEN 5000  THEN 666
        WHEN 50    THEN 667
        WHEN 19000 THEN 670
        WHEN 1400  THEN 705
        WHEN 0     THEN 844
        WHEN 6000  THEN 845
        WHEN 100   THEN 846
        WHEN 16000 THEN 847
        WHEN 12000 THEN 920
        ELSE -99
    END                       AS CALCPRESSID,
        as_.created_tımestamp  ADDDATE,1 ISACTIVE,'ABN' as TP2

FROM CS_AGREEMENT_SUBSCRIBER as_
JOIN SMS.CS_SUBSCRIBER sub
    ON sub.ID = as_.SUBSCRIBER_ID
JOIN SMS.CS_INSTALLATION i
    ON i.SUBSCRIBER_ID = sub.ID
JOIN CS_AGREEMENT agr
    ON agr.INSTALLATION_ID = i.id
--JOIN CS_INSTALLATION_INDEX ii
--    ON ii.INSTALLATION_ID = i.id AND ii.INDEX_TYPE_ID = 1
JOIN CS_METER m
    ON i.METER_ID = m.id
JOIN cs_meter_model_prm mmp
    ON mmp.id = m.METER_MODEL_ID
JOIN cs_meter_model_prm_lng mmpl
    ON mmpl.prm_id = mmp.id AND mmpl.lang_id = 1
JOIN cs_meter_type_prm mtp
    ON mtp.id = mmp.METER_TYPE_ID
LEFT JOIN cs_INSTALLATION_INDEX ix
    ON ix.INSTALLATION_ID = i.id
   AND ix.INDEX_TYPE_ID = 1
   AND ix.IS_ACTIVE = 1
LEFT JOIN cs_INSTALLATION_INDEX ixK
    ON ixK.INSTALLATION_ID = i.id
   AND ixK.INDEX_TYPE_ID = 2
   AND ixK.IS_ACTIVE = 1
LEFT JOIN (
    SELECT USED_PRESSURE, INSTALLATION_ID
    FROM (
        SELECT
            USED_PRESSURE,
            INSTALLATION_ID,
            ROW_NUMBER() OVER (PARTITION BY INSTALLATION_ID ORDER BY ID DESC) AS rn
        FROM II_PROJECT_INSTALLATION
    ) t
    WHERE rn = 1
) iip
    ON iip.INSTALLATION_ID = i.id
--WHERE agr.id = 197168 
) order by ADDDATE asc