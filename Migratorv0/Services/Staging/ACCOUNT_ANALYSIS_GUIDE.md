# Account Discrepancy Analysis Guide

## Quick Diagnosis Checklist

### For ONLY_EN (CRITICAL - AFL'de olmalı)
1. **Run SMS live balance query:**
   ```sql
   SELECT ACCOUNT_ID, SUM(AMOUNT * STATUS) AS REAL_BAL
   FROM CS_ACCOUNT_INCOME
   WHERE ACCOUNT_ID IN (...)
   GROUP BY ACCOUNT_ID
   HAVING ABS(SUM(AMOUNT * STATUS)) > 0.02
   ```
2. **Check if invoice is partially paid:**
   - May have payments but balance still > 0
   - AFL O50 query may have filtered it incorrectly
3. **Verify AFL CTAS vs live:**
   - Compare `LS_AFL_OPEN_DEBT.BALANCE` vs live SUM(AMOUNT×STATUS)
4. **Check ACCRUE_TYPE and MIG_IN_SCOPE:**
   - Should be MIG_IN_SCOPE=1, not emanet (ACCRUE_TYPE≠14)

### For AMT_DIFF (Balance Mismatch)
1. **Compare detailed balance:**
   ```
   SMS:    SUM(CS_ACCOUNT_INCOME.AMOUNT × STATUS)
   ENERGY: SUM(FINANCIALLIABILITIES.PAYABLE - PAID)
           grouped by ABYS_ACCOUNT_ID = FATURAID
   ```
2. **Check allocation discrepancies:**
   - Run step 4 (Alloc) for this agreement
   - Look for RAW_ALLOC vs ALLOC_AMT differences
   - Check waterfill capping: ALLOC ≤ MIN(PAY_FULL_AMT, MAIN_PAYABLE)
3. **Inspect devir entries:**
   - Mixed positive/negative STATUS on same ACCOUNT_ID
   - May cause incorrect SUM if ABS applied too early
4. **Rounding tolerance:**
   - If |DELTA| < 0.02, this is acceptable
   - If |DELTA| ≥ 0.50, investigate immediately

### For ONLY_AFL (Energy'de Kapalı)
1. **Check ENERGY CLOSED status:**
   ```sql
   SELECT CLOSED, PAYABLE, PAID, (PAYABLE-PAID) AS BALANCE
   FROM FINANCIALLIABILITIES
   WHERE ABYS_ACCOUNT_ID IN (...)
   ```
2. **Review close scenarios:**
   - Step 6 (Close Candidates): Was this marked for closing?
   - Step 11 (Tam Eksilten): Full deduction applied?
   - Step 15 (Mahsup): Offset from emanet account?
3. **Check payment history:**
   - Full payment may have been allocated in ENERGY
   - Compare step 4 allocations vs ENERGY PAYMENTS table

### For HARICI_ACIK (Expected Differences)
1. **Verify out-of-scope classification:**
   ```sql
   SELECT ACCRUE_TYPE_ID, MIG_IN_SCOPE
   FROM CS_ACCOUNT
   WHERE ACCOUNT_ID IN (...)
   ```
2. **Common out-of-scope types:**
   - ACCRUE_TYPE_ID = 14 (EMANET - deposit/trust accounts)
   - MIG_IN_SCOPE = 0 (explicitly excluded from migration)
3. **Track separately:**
   - These are expected to differ
   - Monitor total amount for business validation
   - Should be handled by special emanet/mahsup logic (step 15)

## Common Patterns

### Pattern 1: Stale TOTAL_DEBT/TOTAL_CREDIT
**Symptom:** ONLY_EN or AMT_DIFF  
**Root Cause:** Code using CS_ACCOUNT.TOTAL_DEBT instead of SUM(AMOUNT×STATUS)  
**Fix:** Apply SMS_BALANCE_RULE.md - always use CS_ACCOUNT_INCOME aggregation

### Pattern 2: Waterfill Not Applied
**Symptom:** AMT_DIFF, especially where RAW_ALLOC > MAIN_PAYABLE  
**Root Cause:** Allocation exceeded invoice payable limit  
**Fix:** Ensure step 4 logic caps: `ALLOC_AMT = LEAST(RAW_ALLOC, MAIN_PAYABLE, remaining_from_PAY_FULL_AMT)`

### Pattern 3: Emanet Confusion
**Symptom:** HARICI_ACIK showing CRITICAL  
**Root Cause:** Emanet accounts (ACCRUE=14) treated as regular invoices  
**Fix:** Filter MIG_IN_SCOPE=0 and ACCRUE_TYPE_ID=14 to HARICI_ACIK category

### Pattern 4: Cancelled Payment Impact
**Symptom:** ONLY_AFL or AMT_DIFF after cancellation  
**Root Cause:** tip9 cancellation not reflected in ENERGY  
**Fix:** Check step 15 (iptalEmanet) - PAY_CANCEL scenario

### Pattern 5: Eksilten Closed But AFL Shows Open
**Symptom:** ONLY_AFL where invoice was fully deducted  
**Root Cause:** Tam eksilten (step 11) closed it in ENERGY, but AFL still lists it  
**Fix:** Verify LS_OV_EKS_CLASS.EKS_KIND='TAM' and ENERGY INVOICECROSSREF or RETURN_* columns

## Investigation SQL Templates

### Template 1: Deep Dive on Specific Account
```sql
-- SMS side
SELECT 
    AA.ACCOUNT_ID,
    AA.AGREEMENT_ID,
    AA.ACTION_TYPE_ID,
    AA.AMOUNT,
    AA.STATUS,
    AA.ACTION_DATE,
    AA.EXPLAIN,
    AA.REF_DEPOSIT_ACCOUNT_ID,
    AI.INCOME_TYPE_ID,
    AI.AMOUNT AS INC_AMT,
    AI.STATUS AS INC_STATUS
FROM CS_ACCOUNT_ACTION AA
LEFT JOIN CS_ACCOUNT_INCOME AI ON AI.ACCOUNT_ACTION_ID = AA.ACCOUNT_ACTION_ID
WHERE AA.ACCOUNT_ID = :account_id
ORDER BY AA.ACTION_DATE, AA.ACCOUNT_ACTION_ID;

-- SMS balance
SELECT 
    ACCOUNT_ID,
    SUM(AMOUNT * STATUS) AS REAL_BALANCE,
    SUM(CASE WHEN AMOUNT * STATUS > 0 THEN AMOUNT * STATUS ELSE 0 END) AS DEBT,
    SUM(CASE WHEN AMOUNT * STATUS < 0 THEN ABS(AMOUNT * STATUS) ELSE 0 END) AS CREDIT
FROM CS_ACCOUNT_INCOME
WHERE ACCOUNT_ID = :account_id
GROUP BY ACCOUNT_ID;

-- ENERGY side
SELECT 
    FL.ABYS_ACCOUNT_ID,
    FL.ABYS_FINANCIALLIABILITY_ID,
    FL.PAYABLE,
    FL.PAID,
    (FL.PAYABLE - FL.PAID) AS BALANCE,
    FL.CLOSED,
    FL.INVOICECROSSREF,
    FL.EXPLAIN
FROM FINANCIALLIABILITIES FL
WHERE FL.ABYS_ACCOUNT_ID = :account_id
ORDER BY FL.ABYS_FINANCIALLIABILITY_ID;
```

### Template 2: Bulk Classification Summary
```sql
-- Run FRK step to get automated classification
-- Then query gaps table:
SELECT 
    KIND,
    COUNT(*) AS CNT,
    SUM(ABS(DELTA)) AS TOTAL_DIFF,
    AVG(ABS(DELTA)) AS AVG_DIFF
FROM <frk_result_rows>
WHERE KIND != 'MATCH'
GROUP BY KIND
ORDER BY 
    CASE KIND 
        WHEN 'ONLY_EN' THEN 1 
        WHEN 'AMT_DIFF' THEN 2 
        WHEN 'ONLY_AFL' THEN 3 
        WHEN 'HARICI_ACIK' THEN 4 
    END;
```

## Prioritization Matrix

| Severity | Count Threshold | Action Required |
|----------|----------------|-----------------|
| ONLY_EN with balance > 0 | ANY | **BLOCK MIGRATION** - Must resolve |
| AMT_DIFF with \|Δ\| > 1.00 | > 5 accounts | Investigate before migration |
| AMT_DIFF with \|Δ\| ≤ 0.02 | Any | Acceptable tolerance |
| ONLY_AFL | > 10% of total | Review close logic |
| HARICI_ACIK | Any | Track for business validation |

## Quick Wins

1. **Run full FRK step (14):** Automatic classification + summary stats
2. **Filter CRITICAL gaps:** Focus on ONLY_EN first
3. **Sample deep-dive:** Pick 2-3 flagged accounts, run Template 1 SQL
4. **Pattern recognition:** If same root cause for multiple accounts, fix globally
5. **Re-run wizard:** Verify fixes reduced gap counts

## Notes
- Always use `SUM(AMOUNT×STATUS)` for SMS balances (SMS_BALANCE_RULE.md)
- Waterfill tolerance ±0.02 is acceptable for FRK comparisons
- Emanet accounts (ACCRUE_TYPE=14) are expected to be HARICI_ACIK
- Check all 15 wizard steps in sequence - earlier step errors cascade
