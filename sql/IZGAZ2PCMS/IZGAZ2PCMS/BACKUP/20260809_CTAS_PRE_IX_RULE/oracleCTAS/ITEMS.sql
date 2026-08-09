/*

"LREF","MID","DEFN","ACCCODE","STOCKCODE","SPECODE","LASTENDEX","SNNO_TEXT","SNNO_NR","WAREHOUSE","SUPLID","STATID","ISACTIVE","ADDUSER","ADDDATE","UPDUSER","UPDDATE","CNT_DIGIT","CNT_DIRECTION","INV_DATE","INV_NO","OLREF","PRODDATE","CALIBRATIONDATE","CALIBRATIONCOUNT","CALIBRATIONFIRM",
"Cap","Basinc","Tip","DESCRIPTION","HAS_CORRECTOR_MODULE","MARK_REF","METER_CLASS_REF","METER_DIAMETER_REF","METER_PRESSURE_REF","SCRAP_DATE","SCRAP_FIRM"
1800001540,5,G25,,"18154",,169960.0,,"000000000005146507",21,1910000868,3,1,,2007-09-04 00:00:00.000,720,2025-10-09 17:07:00.000,6,0,,,,2006-01-01 00:00:00.000,2015-01-01,,,,,,İş Emri No : 2332805 Kalibrasyon,,9,,,,,


*/ 

--METER_ID  LREF olarak kullnılacak IDENTITY alanıdır.
--PRODDATE DATETIME olması gerekiyor ama sadece year var elimizde hedefe aktarırken "01/01/"  eklenmeli
--

CREATE TABLE LS_005_ITEMS AS
SELECT 
    m.id                                                        METER_ID,
    CAST(0 AS NUMBER)                                           MID,
    mtp.CODE                                                    DEFN,
    CAST(NULL AS VARCHAR2(50))                                  ACCCODE, 
    CAST(NULL AS VARCHAR2(50))                                  STOCKCODE,
    m.LAST_INDEX                                                LASTENDEX, 
    m.METER_NUMBER                                              SNNO_TEXT,
    m.METER_NUMBER                                              SNNO_NR,
    wm2.warehouse_id                                            WAREHOUSE,
    CAST(0 AS NUMBER)                                           SUPLID,
    CAST(0 AS NUMBER)                                           STATID,
    m.IS_ACTIVE                                                 ISACTIVE,
    m.CREATED_TIMESTAMP                                         ADDDATE,
    m.CREATED_USER_ID                                           ADDUSER,
    m.UPDATED_TIMESTAMP                                         UPDUSER,
    m.UPDATED_USER_ID                                           UPDDATE,
    mmp.GEAR_NUMBER                                             CNT_DIGIT,
    CAST(1 AS NUMBER)                                           CNT_DIRECTION,
    CAST(NULL AS DATE)                                          INV_DATE,
    CAST(NULL AS VARCHAR2(50))                                  INV_NO,
    m.id                                                        OLREF,
    CASE 
        WHEN m.PRODUCTION_YEAR IS NULL THEN NULL
        ELSE TO_DATE('01/01/' || TO_CHAR(m.PRODUCTION_YEAR), 'DD/MM/YYYY')
    END                                                         PRODDATE,
    m.CALIBRATION_DATE                                          CALIBRATIONDATE,
    CAST(0 AS NUMBER)                                           CALIBRATIONCOUNT,
    m.CALIBRATION_FIRM_REGISTER_ID                              CALIBRATIONFIRM,
    m.DESCRIPTION,
    CASE WHEN COALESCE(m.CORRECTOR_MODULE_ID, 0) > 0 
         THEN 1 ELSE 0 END                                      HAS_CORRECTOR_MODULE,
    mmp.METER_MARK_ID                                           MARK_REF,
    mmp.METER_CLASS_ID                                          METER_CLASS_REF,
    iip.USED_PRESSURE                                           METER_PRESSURE_REF, 
    w2.name                                                     ABYS_WAREHOUSE,
    ii.id                                                       ABYS_INSTALLATION_ID, 
    ix.LAST_INDEX                                               ABYS_INS_LAST_INDEX,
    ixK.LAST_INDEX                                              ABYS_KORR_LAST_INDEX,
    ix.READING_DATE                                             ABYS_READING_DATE,
    ixK.READING_DATE                                            ABYS_KORR_READING_DATE, 
    mmpl.value                                                  ABYS_METER_MODEL,
    mmp.METER_TYPE_ID                                           ABYS_METER_TYPE_ID,
    mm.VALUE                                                    ABYS_MARK,
    mmp.METER_KIND                                              ABYS_METER_KIND
FROM cs_meter m
JOIN cs_meter_model_prm mmp ON (mmp.id = m.METER_MODEL_ID) 
JOIN cs_meter_model_prm_lng mmpl ON (mmp.id = mmpl.prm_id AND mmpl.lang_id = 1) 
JOIN cs_meter_type_prm mtp ON (mtp.id = mmp.METER_TYPE_ID)
JOIN cs_meter_mark_prm mm ON (mm.id = mmp.METER_MARK_ID)
LEFT JOIN (
    SELECT 
        MAX(CASE WHEN wm.io = 1 THEN wm.id END) AS warehouse_meter,
        wm.meter_id,
        SUM(wm.io) AS net_stock
    FROM cs_warehouse_meter wm
    GROUP BY wm.meter_id
) gb2 ON (m.id = gb2.meter_id)
LEFT JOIN cs_warehouse_meter wm2 ON (wm2.id = gb2.warehouse_meter)
LEFT JOIN cs_warehouse w2 ON (wm2.warehouse_id = w2.id) 
LEFT JOIN (
    SELECT *
    FROM (
        SELECT 
            ii.*,
            ROW_NUMBER() OVER (PARTITION BY ii.METER_ID ORDER BY ii.ID DESC) AS rn
        FROM cs_INSTALLATION ii
    )
    WHERE rn = 1
) ii ON (ii.METER_ID = m.id)
LEFT JOIN cs_INSTALLATION_INDEX ix ON (
    ix.INSTALLATION_ID = ii.id AND ix.INDEX_TYPE_ID = 1 AND ix.IS_ACTIVE = 1
)
LEFT JOIN cs_INSTALLATION_INDEX ixK ON (
    ixK.INSTALLATION_ID = ii.id AND ixK.INDEX_TYPE_ID = 2 AND ixK.IS_ACTIVE = 1
)
LEFT JOIN (
    SELECT USED_PRESSURE, INSTALLATION_ID
    FROM (
        SELECT 
            USED_PRESSURE, 
            INSTALLATION_ID,
            ROW_NUMBER() OVER (PARTITION BY INSTALLATION_ID ORDER BY ID DESC) AS rn
        FROM II_PROJECT_INSTALLATION
    )
    WHERE rn = 1
) iip ON (iip.INSTALLATION_ID = ii.id)



;
SELECT meter_id, COUNT(1) cnt
FROM cs_warehouse_meter
GROUP BY meter_id
HAVING COUNT(1) > 1
ORDER BY cnt DESC
;
SELECT COUNT(1) 
FROM cs_meter m
 ;

SELECT COUNT(1)
FROM cs_meter m
LEFT JOIN (
    SELECT 
        MAX(CASE WHEN wm.io = 1 THEN wm.id END) AS warehouse_meter,
        wm.meter_id,
        SUM(wm.io) AS net_stock
    FROM cs_warehouse_meter wm
    GROUP BY wm.meter_id
) gb2 ON (m.id = gb2.meter_id)
LEFT JOIN cs_warehouse_meter wm2 ON (wm2.id = gb2.warehouse_meter)
LEFT JOIN cs_warehouse w2 ON (wm2.warehouse_id = w2.id)

--select * from cs_meter_type_prm
--select * from cs_meter_model_prm  where IS_ACTIVE = 1
;
select *  from  II_PROJECT_INSTALLATION
;
SELECT COUNT(1)
FROM cs_meter m
JOIN (
    SELECT MAX(wm.id) AS warehouse_meter, wm.meter_id
    FROM cs_warehouse_meter wm 
    GROUP BY wm.meter_id
    HAVING SUM(wm.io) > 0
) gb2 ON (m.id = gb2.meter_id) 
JOIN cs_warehouse_meter wm2 ON (wm2.id = gb2.warehouse_meter)
LEFT JOIN cs_warehouse w2 ON (wm2.warehouse_id = w2.id)
;
--644854  660210
--select count(1) from cs_meter

/*
select mm.ID, 
mm.VALUE,count(1)
from  cs_meter m
join cs_meter_model_prm mmp on (mmp.id = m.METER_MODEL_ID) 
join cs_meter_model_prm_lng mmpl on (mmp.id = mmpl.prm_id and mmpl.lang_id = 1) 
join cs_meter_type_prm mtp on (mtp.id = mmp.METER_TYPE_ID)
join cs_meter_mark_prm mm on (mm.id = mmp.METER_MARK_ID)
group by mm.ID, mm.VALUE

--660692

--Ambar Sayaç Sayıları

select 
count(1),
wm2.warehouse_id, 
w2.name   
from  cs_meter m 

join (
select max(wm.id) warehouse_meter ,wm.meter_id
from cs_warehouse_meter wm 
join cs_warehouse w on
 (wm.warehouse_id = w.id)
group by w.name, wm.meter_id
having sum(wm.io) > 0) gb2 on (m.id = gb2.meter_id) 
join cs_warehouse_meter wm2 on (wm2.id = gb2.warehouse_meter)
join cs_warehouse w2 on (wm2.warehouse_id = w2.id)
group by  wm2.warehouse_id,w2.name 

*/
