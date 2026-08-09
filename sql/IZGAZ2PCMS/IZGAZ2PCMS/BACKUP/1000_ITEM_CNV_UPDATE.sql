----SAYAÇ DÜZELTMELER


UPDATE itm set  itm.SUPLID = fr.LREF   from energy.dbo.LS_005_ITEMS itm
JOIN  energy.dbo.LS_005_FIRM fr on fr.NAME_ = itm.ABYS_MARK 


select  STATID,lps.STDEFN,count(1)   from  LS_005_01_AGR  agr
JOIN LS_PROJ_STAT lps  on lps.LREF = agr.STATID 
where TP2 = 'ABN'
group by STATID,lps.STDEFN      





INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'SCHLUMBERGER' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'ITRON' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'FABRICANT PAR DEFAUT' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'DRESSER' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'ECA' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'METRIX' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'INSTROMET' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'KALE_KALIP' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'MAGNOL' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'ACTARIS' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'RMG' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'SACOFGAZ' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'FMG' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'FIORENTİNİ' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'IMETER' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'FİORENTİNİ' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'FEDERAL' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'GWF' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'MANAR' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'GMT' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'AEM' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'NATEK' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'FMG' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'METER' ,0,1,GETDATE())
INSERT INTO energy.dbo.LS_005_FIRM ([TYPE],NAME_,STATUS ,ADDUSER,ADDDATE)VALUES (0,'RMG' ,0,1,GETDATE())
------------------------------------------------------------------------------------------------------------------------
  --select  top 100  * from LS_005_ITEMS  itm
 -- JOIN LS_STC_MODEL stc on stc.MDEFN = itm.DEFN
------------------------------------------------------------------------------------------------------------------------
  UPDATE itm SET itm.MID = stc.LREF
  from LS_005_ITEMS  itm
  JOIN LS_STC_MODEL stc on stc.MDEFN = itm.DEFN
------------------------------------------------------------------------------------------------------------------------
 
UPDATE LS_005_ITEMS set  SNNO_TEXT= TRIM(SNNO_TEXT),SNNO_NR = TRIM(SNNO_NR)
------------------------------------------------------------------------------------------------------------------------
UPDATE itm set  itm.SUPLID = fr.LREF   from energy.dbo.LS_005_ITEMS itm
JOIN  energy.dbo.LS_005_FIRM fr on fr.NAME_ = itm.ABYS_MARK 
------------------------------------------------------------------------------------------------------------------------
UPDATE itm set  itm.WAREHOUSE = fr.LREF   from energy.dbo.LS_005_ITEMS itm
JOIN  energy.dbo.LS_WAREHOUSE fr on fr.DEFN = itm.ABYS_WAREHOUSE  
where  fr.ENT_ID = 4102
------------------------------------------------------------------------------------------------------------------------

UPDATE energy.dbo.LS_005_ITEMS SET STATID = 2, ISACTIVE = 1 WHERE WAREHOUSE = 36 ; --Müşteri Ambarı
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 1, ISACTIVE = 1 WHERE WAREHOUSE = 41 ; 
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 1, ISACTIVE = 1 WHERE WAREHOUSE = 37 ;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 3, ISACTIVE = 0 WHERE WAREHOUSE = 44;

--HURDA AMBARI PASIF
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 5, ISACTIVE = 0 WHERE WAREHOUSE IN (45, 6, 33, 31, 57, 46, 52, 32, 49, 56, 34, 47, 54, 29, 28, 27,26, 50, 39, 51) ;
--HURDA AMBARI AKTIF
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 5, ISACTIVE = 1 WHERE WAREHOUSE = 38 ;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 4, ISACTIVE = 1 WHERE WAREHOUSE = 53 ;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 3, ISACTIVE = 1 WHERE WAREHOUSE = 35;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 1, ISACTIVE = 1 WHERE WAREHOUSE = 43 ;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 1, ISACTIVE = 1 WHERE WAREHOUSE = 42  ;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 1, ISACTIVE = 0 WHERE WAREHOUSE = 40 ;
UPDATE energy.dbo.LS_005_ITEMS SET STATID = 1, ISACTIVE = 0 WHERE WAREHOUSE = 48 ;

------------------------------------------------------------------------------------------------------------------------
 UPDATE LS_005_01_AGR set TP3 ='NOR' where TP3 <>'NOR' and  COUNTERID is  NULL
 -----------------------------------------------------------------------------------------------------------------------
 UPDATE  energy.dbo.LS_005_ITEMS
 SET LASTENDEX = COALESCE(
        NULLIF(ABYS_INS_LAST_INDEX, 0),
        NULLIF(ABYS_MTR_LAST_INDEX, 0),
        ABYS_INS_LAST_INDEX,
        ABYS_MTR_LAST_INDEX,
        LASTENDEX
     )
 WHERE ABYS_MIG_ROW_ID IS NOT NULL;



select * from LS_WAREHOUSE where ENT_ID = 4102 ;

select * from LS_WAREHOUSE where ENT_ID = 4102 AND LREF in (48) ;

select ABYS_WAREHOUSE ,count(1) from energy.dbo.LS_005_ITEMS  group  BY ABYS_WAREHOUSE  ORDER BY 2;

select WAREHOUSE,ABYS_WAREHOUSE ,STATID ,count(1) from energy.dbo.LS_005_ITEMS  group  BY WAREHOUSE,ABYS_WAREHOUSE  ,STATID 
