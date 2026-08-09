 select * from PROBLEMATIC_CUSTODY_202607 


--EMANET
-- create table PROBLEMATIC_CUSTODY_202607 as  
SELECT   MAX(ACTION_DATE) ACTION_DATE, MAX(agreement_id) agreement_id,   register_id, firm_name,SUM(DEBT_BALANCE) DEBT_BALANCE,
SUM(CASE WHEN CUSTODY <0 THEN CUSTODY ELSE 0 END) CUSTODY,
SUM(CASE WHEN CUSTODY >0 THEN CUSTODY ELSE 0 END) PROBLEMATIC_CUSTODY
FROM (
SELECT   MAX(ACTION_DATE)ACTION_DATE, MAX(a.agreement_id) agreement_id,  r.id register_id,r.first_name|| ' '|| r.last_name firm_name,
NVL(sum(case when a.accrue_type_id= 14 then ai.amount * ai.status end),0) CUSTODY,
NVL(sum(case when a.accrue_type_id != 14 then ai.amount * ai.status end),0) DEBT_BALANCE,
atpl.value,a.id
FROM CS_REGISTER R
JOIN CS_ACCOUNT A ON (A.REGISTER_ID=R.ID)
join cs_account_action aa on (aa.account_id=a.id)
join cs_account_income ai on (ai.account_action_id=aa.id)
join cs_accrue_type_prm atp on (atp.id=a.accrue_type_id)
join cs_accrue_type_prm_lng atpl on (atpl.prm_id=atp.id and atpl.lang_id=1)
WHERE 1=1 --  AND R.ID=1400109 
 --AND A.AGREEMENT_ID = 432332
group by   r.id,r.first_name,r.last_name,atpl.value,a.id)
WHERE (CUSTODY != 0 OR DEBT_BALANCE!=0)
GROUP BY   register_id,firm_name;