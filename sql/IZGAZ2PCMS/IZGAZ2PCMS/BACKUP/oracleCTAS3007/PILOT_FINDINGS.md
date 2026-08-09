# Pilot bulguları → oracleCTAS3007

Kaynak: Migratorv0 `/staging/tahsilat` pilot (2026-07), ENERGY zinciri + gap export.

## Kanıtlanmış kurallar

1. **Bakiye** = `SUM(AMOUNT × STATUS)` (SMS income).
2. **Kapama** = AFL açık değil + OV ödeme ≥ payable (−0.01 / EPS 0.50).
3. **Eşleşme** = O30 waterfill (`Σ ALLOC ≤ PAY_FULL` ve `≤ MAIN_PAYABLE`); canlı INCOME_ID yalnızca yaklaşık.
4. **Taksit**:
   - `CS_ACCOUNT.INSTALLMENT_ID` (action boş olabilir) → `ABYS_INSTALLMENT_ID` / `INSTALLMENT_PLAN_REF`.
   - ENERGY: ana borç PT iptal → `INST_NR>0`, `PAYTYPE=120`.
   - Ödenen satır: `CS_INSTALLMENT_PLAN.PAYMENT_DATE` + makbuz → borç PT `PAID` + TYPE=101 tahsilat.
   - Hepsi ödendiyse: `INVOICE.CLOSED=1`, `LASTPAIDDATE`/`BANKREF` = **son** ödenen taksit.
5. **Veri dengesi (debt + tahsilat PT):** `BANKREF`, `BANK_RECORD_REF`, `LASTPAIDDATE`, `PAYTYPE`, `XTYPE`, `PAID`.

## Pilot gap → CTAS zorunluluğu

| Code | Severity | CTAS |
|------|----------|------|
| `NO_LS_OV_PAY_PT` | WARN | O30 |
| `NO_ALLOC_SOURCE` | WARN | O30 |
| `NO_LS_OV_PAY_ALLOC_ESLESME` | WARN | O30 |
| `NO_LS_STG_INV_PAY_CLOSE` | WARN | O51 |
| `NO_LS_AFL_OPEN_DEBT` | WARN | O50 |
| `NO_LS_OV_EKS_CLASS` | WARN | O20 |
| `NO_LS_OV_MAHSUP` | WARN | O30/O55 |
| `TAKSIT_SMS_ONLY` / `ACIK_MISMATCH` | WARN | O56+O57 + Energy 611/613 |
| `FRK_ONLY_EN` | CRITICAL | O50 + O51 sync |
| `PILOT_LIVE_FALLBACK` | INFO | Prod’da CTAS tercih |

## Bilinen tuzaklar (3007’de adres)

| Tuzak | Önlem |
|-------|--------|
| O11 `CLOSED=0` / `LASTPAIDDATE=NULL` ham | O33 patch + O32 DEBT_PAID |
| O52 `BANK_RECORD_REF` NULL | O52 fix (`BANK_RECEIPT_NUMBER`) |
| O56 yalnızca AFL açık | O56 tüm `INSTALLMENT_ID` hesapları |
| Plan satırı yok → ENERGY PAID boş | O57 `LS_INSTALLMENT_PLAN_PAY` |
| PAY PT `PAID=0` (597 legacy) | O34 enrich `PAID=PAYABLETOTAL` |
| `aa.INSTALLMENT_ID` NULL | O11 `NVL(acc, aa)` |
| `ACTION_DATE<=PAY` → hayalet NO_PAY / ONLY_EN | O30 filtre **kaldirildi** (2026-08-02); soft log `_skip/30_HOTFIX…`; **O41 EARLY_PAY_GHOST=0 hard** (2026-08-07) |
| İptal PAY waterfill’i tüketir → 2. tahsilat yok | O30: iptal ALLOC+`CANCELED=1`; kapasite yalnız geçerli (2026-08-02c); örn. ACC 51407277 |
| TAH_INV `EXPLAIN` boş | O30: `TAHSILAT` / `TAHSILAT IPTAL` |
| MGR `BANKREF` / `BANK_RECORD_REF` hep NULL | O33+O34 atlanmış dump; yeniden CTAS+dump şart |
| Energy INV `BANKREF` hâlâ SMS id (örn. 21) | O33 bank + 597 WIRE `ABYS_ID→LREF` (debt PT bazen mapli, INV değil) |

## Plan — AGR 197168 retest (2026-08-03)

Kod tamam (O30 iptal/EXPLAIN/TAH bank; O34 TAH; 597 INSERT+WIRE yedek; MIG_PARAM pilot). **Ops: Oracle→MGR aktarım.**

| # | Adım | Beklenen spot |
|---|------|----------------|
| 1a | Hızlı: `@00_mig_param_pilot` → `@00_run_pilot_overlay` | Overlay yalnız örnek AGR; PAY_PT/TAH bank>0 |
| 1b | veya FULL: `@00_run_all` (O30→O34→O33 dahil) | Aynı kolonlar global |
| 2 | Dump → izgazMGR (+ `00b_align_mgr_varchar`) | MGR 197168: bank+makbuz dolu; TAH_INV bank kolonları |
| 3 | Energy deploy 20/21/22/29 (QI ON) + `SP_MIG_597_ALL @AGR_ID=197168` | GATE_PASS |
| 4 | Spot ACC **51407277** / MAIN **109425605** | 1. tahsilat PT `CANCELED=1`; 2. PT `109577625` `CANCELED=0`; `BANKREF` Energy LREF; makbuz dolu |
| 5 | Spot MAIN **126748999** | `inv.BANKREF=5` (SMS 21 değil); `BANK_RECORD_REF=45334326234` |
| 6 | TYPE=101 | EXPLAIN + BANKREF/BANK_RECORD_REF/LASTPAIDDATE dolu |

**Pass (197168):** iptal geçmişi; 2. tahsilat; INV/PT/TAH bank+makbuz; CLOSED/LPD tutarlı.

## Pilot vs aktarım gap (5727 / 31894 / 33290 / 39264) — 2026-08-02

Karşılaştırma: wizard `pilotEnergyChain` + master (201/301) vs şu an koşulan MAP→571→575→590→597.

| # | Konu | Pilot / beklenen | Şu anki aktarım | Kök neden | Aksiyon |
|---|------|------------------|-----------------|-----------|---------|
| 1 | **Banka adı** | UI: `INV/PT.BANKREF` = `LS_BANK.LREF` → `LS_BANK.DEFN` / `SHORTNAME` | Eski dump: SMS id / NULL | O33/O34 atlanmış dump; 571 SMS id | **Kod OK (2026-08-03):** O34+O33; 597 WIRE MGR + ENERGY SMS→LREF yedek. **Ops:** pilot overlay veya FULL O30–O34 → dump → 597 |
| 2 | **Müşteri Ad/Soyad** | `LS_005_01_AGR.CON` → `LS_005_SUBSCR…` | AGR/SUBSCR yok | 201/301 çalıştırılmadı | Energy master 201+301 (CTAS dışı) |
| 3 | **INVOICE tahsilat alanları** | MAIN + TYPE=101: EXPLAIN + bank/makbuz/LPD | Eski dump eksik | O30 TAH bank yoktu; 597 yazmıyordu | **Kod OK:** O30 TAH_INV BANK/LPD; O34 TAH MERGE; 597 INSERT bank/LPD. **Ops:** `@00_mig_param_pilot` + `@00_run_pilot_overlay` → dump → 597 |

**Pilot zincir farkı (eksik adımlar):** master **201/301** (müşteri+sözleşme açılış) bu AGR aktarımında yoktu.

Spot (energy, ağ açılınca):
```sql
-- 1 banka adı
SELECT inv.OWNERREF, inv.LREF, inv.BANKREF, b.SHORTNAME, b.DEFN, inv.BANK_RECORD_REF
FROM LS_005_01_INVOICE inv
LEFT JOIN LS_BANK b ON b.LREF = inv.BANKREF
WHERE inv.OWNERREF IN (5727,31894,33290,39264) AND ISNULL(inv.TYPE,0)<>101 AND inv.CLOSED=1;

-- 2 ad soyad
SELECT a.LREF, a.CON, s.FIRSTNAME, s.SURNAME, s.NAME_
FROM LS_005_01_AGR a
LEFT JOIN LS_005_SUBSCR s ON s.LREF=a.CON
WHERE a.LREF IN (5727,31894,33290,39264);

-- 3 tahsilat INV
SELECT TYPE, COUNT(*), SUM(CASE WHEN BANKREF IS NOT NULL THEN 1 END) bank,
       SUM(CASE WHEN BANK_RECORD_REF IS NOT NULL THEN 1 END) rec,
       SUM(CASE WHEN EXPLAIN IS NOT NULL THEN 1 END) expl
FROM LS_005_01_INVOICE
WHERE OWNERREF IN (5727,31894,33290,39264) OR ABYS_AGREEMENT_ID IN (5727,31894,33290,39264)
GROUP BY TYPE;
```

## Doğrulama AGR (ör. 943373)

```sql
-- AFL vs live balance
SELECT COUNT(*), ROUND(SUM(BALANCE),2) FROM MIGRATION.LS_AFL_OPEN_DEBT
 WHERE SOZLESME_HESABI = 943373 AND MIG_IN_SCOPE = 1;

-- Taksit plan ödemeleri
SELECT INSTALLMENT_ID, ORDER_NUMBER, AMOUNT, PAYMENT_DATE, BANKREF, RECEIPT_NUMBER
  FROM MIGRATION.LS_INSTALLMENT_PLAN_PAY
 WHERE AGREEMENT_ID = 943373
 ORDER BY INSTALLMENT_ID, ORDER_NUMBER;

-- Kapama adayı
SELECT FIX_KIND, COUNT(*) FROM MIGRATION.LS_STG_INV_PAY_CLOSE
 WHERE SOZLESME = 943373 GROUP BY FIX_KIND;
```
