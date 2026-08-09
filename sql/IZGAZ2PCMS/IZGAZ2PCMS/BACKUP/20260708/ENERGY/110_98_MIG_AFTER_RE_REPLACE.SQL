 

select  * from LS_USER
------

UPDATE agr SET
agr.FLATID = fl.LREF
from LS_005_01_AGR agr
JOIN  LS_FLAT fl on agr.FITNO  = fl.ABYS_INSTALLATION_ID 
where fl.ENT_ID =4102 --and agr.FITNO =136283  and AGR.TP2  = 'KUL'

   ------
   select  usr.USERID, usr.ABYS_ID from  LS_USER usr 
   JOIN  LS_005_01_AGR agr on usr.ABYS_ID = agr.ADDUSER
   ------
        
   UPDATE agr set  agr.ADDUSER = usr.USERID
   from  LS_USER usr 
   JOIN  LS_005_01_AGR agr on usr.ABYS_ID = agr.ADDUSER

   UPDATE agr set  agr.UPDUSER = usr.USERID
   from  LS_USER usr 
   JOIN  LS_005_01_AGR agr on usr.ABYS_ID = agr.UPDUSER

   ------

   UPDATE agr set  agr.ADDUSER = usr.USERID
   from  LS_USER usr 
   JOIN  LS_005_01_AGR_GUARANTY agr on usr.ABYS_ID = agr.ADDUSER

   UPDATE agr set  agr.UPDUSER = usr.USERID
   from  LS_USER usr 
   JOIN  LS_005_01_AGR_GUARANTY agr on usr.ABYS_ID = agr.UPDUSER

-----

   UPDATE agrGua set  agrGua.AGRID = agr.LREF
   from  LS_005_01_AGR agr 
   JOIN  LS_005_01_AGR_GUARANTY agrGua on agr.ABYS_ID = agrGua.ABYS_AGRID 
---------------------------

  
   UPDATE agt set  agt.AGRID = agr.LREF
   from  LS_005_01_AGR agr 
   JOIN  LS_005_01_AGR_DEV_TR agt on agr.ABYS_ID = agt.ABYS_AGREEMENT_ID 

   select top 100  * from LS_005_01_AGR_DEV_TR

 
   UPDATE agt set  agt.AGRID = agr.LREF
   from  LS_005_01_AGR agr 
   JOIN  LS_005_01_AGR_SERVEQ_TR agt on agr.ABYS_ID = agt.ABYS_AGREEMENT_ID 


    UPDATE agt set  agt.AGRID = agr.LREF
   from  LS_005_01_AGR agr 
   JOIN  LS_005_01_AGR_FITMENTFEE_TR agt on agr.FITNO = agt.ABYS_INSTALLATION_ID and agr.TP2 = 'ABN'




      select top 100  agt.AGRID, agr.LREF   from  LS_005_01_AGR agr 
   JOIN  LS_005_01_AGR_SERVEQ_TR agt on agr.ABYS_ID = agt.ABYS_AGREEMENT_ID 



   select top 100   *from LS_005_01_AGR_CLOSE

select  *from LS_005_01_AGR_GUARANTY where ABYS_AGRID= 1197101

   select * from LS_005_01_AGR where LREF =    3102752 
------

   select fr.LREF, * from LS_005_01_AGR agr
    LEFT JOIN LS_005_SUBSCR sb on sb.LREF = agr.con
   LEFT JOIN LS_005_FIRM fr on fr.LREF = agr.con
   where sb.LREF is null


   --UPDATE agr set agr.CON = null , agr.FRMID = fr.LREF from LS_005_01_AGR agr
   --LEFT JOIN LS_005_SUBSCR sb on sb.LREF = agr.con
   --LEFT JOIN LS_005_FIRM fr on fr.LREF = agr.con
   --where sb.LREF is null  

   --select  * from LS_005_01_AGR agr
   --LEFT JOIN LS_005_SUBSCR sb on sb.LREF = agr.con
   --LEFT JOIN LS_005_FIRM fr on fr.LREF = agr.con
   --where fr.LREF is null


   --UPDATE agr set agr.CON = null , agr.FRMID = fr.LREF from LS_005_01_AGR agr
   --LEFT JOIN LS_005_SUBSCR sb on sb.LREF = agr.con
   --LEFT JOIN LS_005_FIRM fr on fr.LREF = agr.con
   --where fr.LREF is null


UPDATE agr
SET agr.FRMID = fr.LREF,
agr.CON   = CASE WHEN fr.LREF IS NOT NULL THEN NULL ELSE agr.CON END
FROM LS_005_01_AGR agr
LEFT JOIN LS_005_SUBSCR sb ON sb.LREF = agr.con
LEFT JOIN LS_005_FIRM   fr ON fr.LREF = agr.con
WHERE fr.LREF IS NOT NULL; 

   ------
        
   UPDATE fr set  fr.ADDUSER = usr.USERID
   from  LS_USER usr 
   JOIN  LS_005_FIRM fr on usr.ABYS_ID = fr.ADDUSER

   UPDATE sb set  sb.UPDUSER = usr.USERID
   from  LS_USER usr 
   JOIN  LS_005_SUBSCR sb on usr.ABYS_ID = sb.UPDUSER
--------------
  select  top 100  * from LS_005_ITEMS  itm
  JOIN LS_STC_MODEL stc on stc.MDEFN = itm.DEFN

  UPDATE itm SET itm.MID = stc.LREF
  from LS_005_ITEMS  itm
  JOIN LS_STC_MODEL stc on stc.MDEFN = itm.DEFN
-----------------------


UPDATE agr SET 
COUNTERSN = itm.SNNO_TEXT, COUNTERMODEL=itm.MID,COUNTERMBAR = itm.METER_PRESSURE_REF
  from LS_005_01_AGR   agr 
  JOIN LS_005_ITEMS itm on itm.LREF = agr.COUNTERID
  where agr.FITNO= 813400
  -----------------------
  UPDATE  LS_005_01_AGR set  IS_GS  =0


 UPDATE LS_005_01_AGR SET TP3 ='NOR' where ISNULL(COUNTERID,0)=0

 /*
 16	Büyük Sanayi
 4	İşyeri
 13	Kamu 
 */

  select agr.COUNTERID,* 
    from LS_005_01_AGR   agr 
  LEFT JOIN LS_005_ITEMS itm on itm.LREF = agr.COUNTERID
  where agr.FITNO= 813400

select * from LS_005_ITEMS where LREF = 645346




select * from izgazMGR.dbo.LS_005_ITEMS   where METER_ID = 645346

 
UPDATE LS_FLAT  SET FLATDEFN = 4 where LREF in (
select FLATID  from LS_005_01_AGR  where TP1 = 'TIC'  and TP2 ='KUL'
)


UPDATE LS_FLAT  SET FLATDEFN = 13 where LREF in (
select FLATID  from LS_005_01_AGR  where TP1 = 'KAM'  and TP2 ='KUL'
)

UPDATE LS_FLAT  SET FLATDEFN = 16 where LREF in (
select FLATID  from LS_005_01_AGR  where TP1 = 'BSA'  and TP2 ='KUL'
)


  select * from LS_STC_MODEL


  select  top 100  * from LS_005_ITEMS  itm
  JOIN LS_STC_MODEL stc on stc.MDEFN = itm.DEFN

  UPDATE itm SET itm.MID = stc.LREF
  from LS_005_ITEMS  itm
  JOIN LS_STC_MODEL stc on stc.MDEFN = itm.DEFN





  select  * from LS_005_01_AGR_GUARANTY
  
  select  * from LS_005_01_AGR_DEV_TR

  select  * from LS_005_01_AGR_CLOSE



  select * from LS_005_01_AGR 
  group by FLATID 
  order by ADDDATE


  -----------------------------------------

     UPDATE  LS_005_01_AGR set STATID = 2 where TP2 = 'ABN'  and ABYS_PROJECT_STATUS in (200,300,400);
      
     UPDATE  LS_005_01_AGR set STATID = 1 where TP2 = 'ABN'  and ABYS_PROJECT_STATUS in (100);

     UPDATE  LS_005_01_AGR set STATID = 4 where TP2 = 'ABN'  and ABYS_PROJECT_STATUS in (888,999);

     UPDATE  LS_005_01_AGR set STATID = 1 where TP2 = 'ABN'  and ABYS_PROJECT_STATUS is NULL ;
     
        
 select ABYS_PROJECT_STATUS, 
 CASE   WHEN    ABYS_PROJECT_STATUS is null THEN 1 
        WHEN    ABYS_PROJECT_STATUS =0 THEN 1   
        WHEN    ABYS_PROJECT_STATUS = 100 THEN 1    
        WHEN    ABYS_PROJECT_STATUS = 200 THEN 2    
        WHEN    ABYS_PROJECT_STATUS = 200 THEN 2    
        WHEN    ABYS_PROJECT_STATUS = 300 THEN 2  
        WHEN    ABYS_PROJECT_STATUS = 400 THEN 2             
        WHEN    ABYS_PROJECT_STATUS = 888 THEN 4 
        WHEN    ABYS_PROJECT_STATUS = 999 THEN 4 
            END   ABYS_PROJECT_STATUS ,count(1) from  LS_005_01_AGR 
where TP2 = 'ABN'
group by ABYS_PROJECT_STATUS       


UPDATE itm set  itm.SUPLID = fr.LREF   from energy.dbo.LS_005_ITEMS itm
JOIN  energy.dbo.LS_005_FIRM fr on fr.NAME_ = itm.ABYS_MARK 




select  STATID,lps.STDEFN,count(1)   from  LS_005_01_AGR  agr
JOIN LS_PROJ_STAT lps  on lps.LREF = agr.STATID 
where TP2 = 'ABN'
group by STATID,lps.STDEFN        


CREATE TABLE izgazMGR.dbo.LS_ITEMS (
	METER_ID bigint NOT NULL,
	MID decimal(22,0) NULL,
	DEFN nvarchar(5) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	ACCCODE nvarchar(50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	STOCKCODE nvarchar(50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	LASTENDEX decimal(25,3) NULL,
	SNNO_TEXT nvarchar(25) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	SNNO_NR nvarchar(25) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	WAREHOUSE bigint NULL,
	SUPLID decimal(22,0) NULL,
	STATID decimal(22,0) NULL,
	ISACTIVE smallint NOT NULL,
	ADDDATE datetimeoffset NOT NULL,
	ADDUSER bigint NOT NULL,
	UPDUSER datetimeoffset NULL,
	UPDDATE bigint NULL,
	CNT_DIGIT bigint NULL,
	CNT_DIRECTION decimal(22,0) NULL,
	INV_DATE datetime2(0) NULL,
	INV_NO nvarchar(50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	OLREF bigint NOT NULL,
	PRODDATE datetime2(0) NULL,
	CALIBRATIONDATE datetime2(0) NULL,
	CALIBRATIONCOUNT decimal(22,0) NULL,
	CALIBRATIONFIRM bigint NULL,
	DESCRIPTION nvarchar(2000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	HAS_CORRECTOR_MODULE decimal(22,0) NULL,
	MARK_REF bigint NOT NULL,
	METER_CLASS_REF bigint NULL,
	METER_DIAMETER_REF bigint NULL,
	METER_PRESSURE_REF int NULL,
	ABYS_WAREHOUSE nvarchar(1000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	ABYS_INSTALLATION_ID bigint NULL,
	ABYS_INS_LAST_INDEX decimal(25,3) NULL,
	ABYS_KORR_LAST_INDEX decimal(25,3) NULL,
	ABYS_READING_DATE datetime2(0) NULL,
	ABYS_KORR_READING_DATE datetime2(0) NULL,
	ABYS_METER_MODEL nvarchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	ABYS_METER_TYPE_ID bigint NULL,
	ABYS_MARK nvarchar(50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	ABYS_METER_KIND smallint NULL,
	ABYS_DESCRIPTION nvarchar(2000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	CAP nvarchar(50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	TIP nvarchar(50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	ABYS_LENGTH nvarchar(10) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	ABYS_GEAR_DECIMAL bigint NULL
);

--

select * from LS_WAREHOUSE

UPDATE energy.dbo.LS_005_ITEMS SET STATID = 2, ISACTIVE = 1 WHERE WAREHOUSE = 2  AND ABYS_MIG_ROW_ID IS NOT NULL;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 1, ISACTIVE = 1 WHERE WAREHOUSE = 1  AND ABYS_MIG_ROW_ID IS NOT NULL;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 1, ISACTIVE = 1 WHERE WAREHOUSE = 5  AND ABYS_MIG_ROW_ID IS NOT NULL;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 3, ISACTIVE = 0 WHERE WAREHOUSE = 44 AND ABYS_MIG_ROW_ID IS NOT NULL;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 3, ISACTIVE = 1 WHERE WAREHOUSE = 35 AND ABYS_MIG_ROW_ID IS NOT NULL;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 1, ISACTIVE = 1 WHERE WAREHOUSE = 43 AND ABYS_MIG_ROW_ID IS NOT NULL;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 5, ISACTIVE = 1 WHERE WAREHOUSE = 7  AND ABYS_MIG_ROW_ID IS NOT NULL;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 5, ISACTIVE = 1 WHERE WAREHOUSE = 38  AND ABYS_MIG_ROW_ID IS NOT NULL;

UPDATE energy.dbo.LS_005_ITEMS SET STATID = 1, ISACTIVE = 1 WHERE WAREHOUSE = 42  AND ABYS_MIG_ROW_ID IS NOT NULL;

UPDATE energy.dbo.LS_005_ITEMS SET STATID = 4, ISACTIVE = 1 WHERE WAREHOUSE = 53 AND ABYS_MIG_ROW_ID IS NOT NULL;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 1, ISACTIVE = 0 WHERE WAREHOUSE = 40 AND ABYS_MIG_ROW_ID IS NOT NULL;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 1, ISACTIVE = 0 WHERE WAREHOUSE = 48 AND ABYS_MIG_ROW_ID IS NOT NULL;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 5, ISACTIVE = 0 WHERE WAREHOUSE IN (45, 6, 33, 31, 57, 46, 52, 32, 49, 56, 34, 47, 54, 29, 28, 27,26, 50, 39, 51)   AND ABYS_MIG_ROW_ID IS NOT NULL;

UPDATE LS_005_ITEMS set  SNNO_TEXT= TRIM(SNNO_TEXT),SNNO_NR = TRIM(SNNO_NR)



select WAREHOUSE,ABYS_WAREHOUSE ,STATID ,count(1) from energy.dbo.LS_005_ITEMS  group  BY WAREHOUSE,ABYS_WAREHOUSE  ,STATID 







UPDATE itm set  itm.SUPLID = fr.LREF   from energy.dbo.LS_005_ITEMS itm
JOIN  energy.dbo.LS_005_FIRM fr on fr.NAME_ = itm.ABYS_MARK 

UPDATE itm set  itm.WAREHOUSE = fr.LREF   from energy.dbo.LS_005_ITEMS itm
JOIN  energy.dbo.LS_WAREHOUSE fr on fr.DEFN = itm.ABYS_WAREHOUSE  
where  fr.ENT_ID = 4102


select STATID,COUNT(1) from energy.dbo.LS_005_ITEMS itm
group by STATID


UPDATE energy.dbo.LS_005_ITEMS
 SET LASTENDEX = COALESCE(
        NULLIF(ABYS_INS_LAST_INDEX, 0),
        NULLIF(ABYS_MTR_LAST_INDEX, 0),
        ABYS_INS_LAST_INDEX,
        ABYS_MTR_LAST_INDEX,
        LASTENDEX
     )
 WHERE ABYS_MIG_ROW_ID IS NOT NULL
-- was: SET LASTENDEX = ABYS_INS_LAST_INDEX

--UPDATE itm set  itm.WAREHOUSE = fr.LREF   from energy.dbo.LS_005_ITEMS itm
--JOIN  energy.dbo.LS_WAREHOUSE fr on fr.DEFN = itm.ABYS_WAREHOUSE  
--where itm.WAREHOUSE is null 




-- İZGAZ 7 HANE Tel değişikliği

update prm
SET prm.COMMUNICATION_TEXT='( ' + CAST(prm.PHONE_AREA_CODE_ID AS VARCHAR(10)) + ' ) ' 
        + SUBSTRING(prm.COMMUNICATION_TEXT, 1, 3) + ' ' 
        + SUBSTRING(prm.COMMUNICATION_TEXT, 4, 2) + ' ' 
        + SUBSTRING(prm.COMMUNICATION_TEXT, 6, 2),
    prm.PHONE_AREA_CODE_ID=null,
    prm.PHONE_EXTENSION=null
 from LS_005_SUBSCRIBER_COMMUNICATION prm (NOLOCK) 
 WHERE prm.PHONE_AREA_CODE_ID is not null and LEN(prm.COMMUNICATION_TEXT)=7
 
 
-- İZGAZ 9 Hane Tel Değişikliği ve '-' kaldırma

update prm
SET prm.COMMUNICATION_TEXT='( ' + CAST(prm.PHONE_AREA_CODE_ID AS VARCHAR(10)) + ' ) ' 
        + SUBSTRING(REPLACE(prm.COMMUNICATION_TEXT, '-', ''), 1, 3) + ' ' 
        + SUBSTRING(REPLACE(prm.COMMUNICATION_TEXT, '-', ''), 4, 2) + ' ' 
        + SUBSTRING(REPLACE(prm.COMMUNICATION_TEXT, '-', ''), 6, 2),
    prm.PHONE_AREA_CODE_ID=null,
    prm.PHONE_EXTENSION=null
 from LS_005_SUBSCRIBER_COMMUNICATION prm (NOLOCK) 
 WHERE prm.PHONE_AREA_CODE_ID is not null and LEN(prm.COMMUNICATION_TEXT)=9
 

-- İZGAZ Kalan Tel Değiştirme

update prm
SET prm.COMMUNICATION_TEXT='( ' + CAST(prm.PHONE_AREA_CODE_ID AS VARCHAR(10)) + ' ) ' 
        + SUBSTRING(REPLACE(prm.COMMUNICATION_TEXT, '-', ''), 1, 3) + ' ' 
        + SUBSTRING(REPLACE(prm.COMMUNICATION_TEXT, '-', ''), 4, 2) + ' ' 
        + SUBSTRING(REPLACE(prm.COMMUNICATION_TEXT, '-', ''), 6, 2),
    prm.PHONE_AREA_CODE_ID=null,
    prm.PHONE_EXTENSION=null
 from LS_005_SUBSCRIBER_COMMUNICATION prm (NOLOCK) 
WHERE prm.PHONE_AREA_CODE_ID is not null and prm.COMMUNICATION_TYPE in(2,3,4,5)





UPDATE agr2
SET agr2.PARID = agr1.LREF
FROM LS_005_01_AGR agr1
JOIN LS_005_01_AGR agr2 
    ON agr1.FITNO = agr2.FITNO   
WHERE agr1.TP2 = 'ABN'           
  AND agr2.TP2 = 'KUL'           
 
  


    WITH CTE_KUL AS (
    SELECT 
        KUL.LREF AS KUL_LREF,
        KUL.FITNO AS FITNO,
        KUL.TP1 AS KUL_TP1,      KUL.TP3 AS KUL_TP3,      KUL.BN_TYPE AS KUL_BN_TYPE,
        ROW_NUMBER() OVER (PARTITION BY KUL.FITNO ORDER BY KUL.LREF) AS RN
    FROM LS_003_01_AGR KUL
    WHERE KUL.TP2 = 'KUL'
)
 


 WITH CTE_KUL AS (
    SELECT 
        KUL.LREF AS KUL_LREF,
        KUL.FITNO AS FITNO,
        KUL.TP1 AS KUL_TP1,      KUL.TP3 AS KUL_TP3,      KUL.BN_TYPE AS KUL_BN_TYPE,
        ROW_NUMBER() OVER (PARTITION BY KUL.FITNO ORDER BY KUL.LREF DESC) AS RN
    FROM LS_005_01_AGR KUL 
    WHERE KUL.TP2 = 'KUL' --and KUL.FITNO = '695760' 
)
--UPDATE KUL_SON SET ISACTIVE=1
select * 
FROM LS_005_01_AGR KUL_SON
JOIN CTE_KUL KUL    ON KUL_SON.LREF = KUL.KUL_LREF    AND KUL.RN = 1  
WHERE KUL_SON.TP2 = 'KUL'  

