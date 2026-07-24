--DROP TABLE  LS_ITEMS

 
;
 


 ;

 CREATE TABLE LS_ITEMS AS
SELECT 
    m.id                                                        METER_ID,
    CAST(0 AS NUMBER)                                           MID,
    mtp.CODE                                                    DEFN,
    CAST(NULL AS VARCHAR2(50))                                  ACCCODE, 
    CAST(NULL AS VARCHAR2(50))                                  STOCKCODE,
    ix.LAST_INDEX                                               LASTENDEX,  -- Tesisatın Son Endeksi
     RTRIM(LTRIM(m.METER_NUMBER))                               SNNO_TEXT,
    RTRIM(LTRIM(m.METER_NUMBER))                                SNNO_NR,
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
    cm.calCD                                                    CALIBRATIONDATE,
    cm.calCNT                                                   CALIBRATIONCOUNT,
    m.CALIBRATION_FIRM_REGISTER_ID                              CALIBRATIONFIRM,
    m.DESCRIPTION                                                               ,
    CASE WHEN COALESCE(m.CORRECTOR_MODULE_ID, 0) > 0 
         THEN 1 ELSE 0 END                                      HAS_CORRECTOR_MODULE,
    mmp.METER_MARK_ID                                           MARK_REF,
    mmp.METER_CLASS_ID                                          METER_CLASS_REF,
    mmp.METER_DIAMETER_ID                                      METER_DIAMETER_REF,
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
    mmp.METER_KIND                                              ABYS_METER_KIND , 
       m.DESCRIPTION                                            ABYS_DESCRIPTION      ,
    mdp.VALUE   Cap,
    mcp.VALUE   Tip ,
    mlp.code    ABYS_LENGTH,
    mmp.GEAR_NUMBER_DECIMAL                                             ABYS_GEAR_DECIMAL  

FROM cs_meter m
JOIN cs_meter_model_prm mmp ON (mmp.id = m.METER_MODEL_ID) 
JOIN cs_meter_model_prm_lng mmpl ON (mmp.id = mmpl.prm_id AND mmpl.lang_id = 1) 
JOIN cs_meter_type_prm mtp ON (mtp.id = mmp.METER_TYPE_ID)
JOIN cs_meter_mark_prm mm ON (mm.id = mmp.METER_MARK_ID)
LEFT JOIN CS_METER_DIAMETER_PRM  mdp ON (mdp.id = mmp.METER_DIAMETER_ID)
--LEFT JOIN CS_METER_DIAMETER_PRM  mdp ON (mdp.id = mmp.METER_DIAMETER_ID)
LEFT JOIN CS_METER_CLASS_PRM_LNG mcp ON (mcp.prm_id = mmp.METER_CLASS_ID and mcp.lang_id = 1)
LEFT JOIN CS_METER_LENGTH_PRM  mlp  ON (mlp.id = mmp.METER_LENGTH_ID)
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
LEFT JOIN 
(
select wo.METER_ID,COUNT(1) calCNT,MAX(wr.COMPLETED_DATE)calCD from WO_WORK wo
JOIN WO_WORK_RESULT wr on WO.ID = wr.WORK_ID
where wo.STATUS =5 AND wo.cause_id=18  AND  wr.cause_result_id=79
GROUP BY wo.METER_ID 
)   cm on cm.METER_ID = m.id 


;

  


;;;
--654107
;;
select ABYS_WAREHOUSE,count(1)  from  SMS_AUDIT.LS_METER_WAREHOUSE  where ABYS_INSTALLATION_ID is not null
group by ABYS_WAREHOUSE;

;

select *  from  CS_READING_PLAN
 


/*
select count(1), METER_ID from CS_INSTALLATION 
group by METER_ID
having count(1)>1
*/