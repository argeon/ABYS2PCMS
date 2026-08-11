# AFL kalan healleri — aktarım test notu (2026-08-10)

**Kullanım:** 2026-08-11 **05:00** data aktarım testi  
**Ortamlar doğrulandı:** 195 `SQLMIG01` / energy · 196 `SQLTESTLIVE` / energy  
**AFL master:** O50 cutover `AS_OF=2026-08-08` (bayat değil — cutover referansı)

---

## 1) Ne yapıldı (patch heal zinciri)

| # | Script | Ne | 195 APPLY | 196 APPLY |
|---|--------|-----|-----------|-----------|
| 91f | `90_afl_frk/91f_en_gt_afl_kalan_heal.sql` | EN>AFL + AFL≈0 → PT PAID=PAYABLE + INV CLOSED | 3296 PT | 3296 PT |
| 91g | `90_afl_frk/91g_en_gt_afl_partial_heal.sql` | EN>AFL + AFL>0 → FIFO excess PAID (AFL tutarı açık) | 401 | 406 |
| 91h | `90_afl_frk/91h_afl_gt_en_reopen_heal.sql` | AFL>EN → PAID geri al + CLOSED=0 (AFL taban) | 2884 PT ~7.5M ₺ | 2884 PT ~7.5M ₺ |
| 91i | `90_afl_frk/91i_overpay_paid_clamp_heal.sql` | AFL≈0 + EN<0 overpay → PAID=PAYABLE (`PAYABLE>=0`) | 33 PT ~7.4k ₺ | 34 PT ~7.9k ₺ |
| 97 | `SP_AGR_FRK_ALL` | FRK tablo yenile `@OnlyDiff=1` | post-91i OK | post-91i OK |

**İş kuralı:** Cutover AFL taban — `AFL.BALANCE>eps` iken `EN_KALAN >= AFL`. Over-close → 91h reopen. EN fazla → 91f/91g close.

---

## 2) Test günü EXEC sırası (kirli DB / residual)

Önkoşul: `energy.dbo.LS_AFL_OPEN_DEBT` + güncel `MIG_AGR_FRK_ALL` (yoksa önce 97).

```text
1) 91f  @DryRun=1 → 0     -- EN_GT + AFL≈0
2) 91g  @DryRun=1 → 0     -- EN_GT + AFL>0 partial
3) 91h  @DryRun=1 → 0     -- AFL_GT reopen (öncelikli / büyük etki)
4) 91i  @DryRun=1 → 0     -- overpay clamp (MinAbs=10)
5) EXEC dbo.SP_AGR_FRK_ALL
      @Agr=NULL, @OnlyDiff=1, @WriteTable=1, @ReturnResult=0;
6) Kabul sorguları (aşağı)
```

Spot önce: `@Agr=<id>` (ör. 1028596) sonra SEED (`@Agr=NULL`).

**Testte koşma (bu heal paketinden bağımsız / saatlik):**
- `SP_MIG_597_ALL @CLEAN=1`
- Full `SP_MIG_597_WIRE` (sadece AFL için gerekmez)
- `92_stg_inv_pay_close_apply` (O51 ayrı; STG doğruysa dokunma)
- `98_TEST_*`

---

## 3) Kabul (NET) — 195/196 son ölçüm (2026-08-10)

| Metrik | ~Değer | Not |
|--------|--------|-----|
| `en_gt_afl` (eps) | **~18** | OK |
| `afl_gt_en` (eps) | ~43.6k | **çoğu gürültü** (eps–1 ₺) |
| material `DELTA_KALAN_NET <= -10` | **~517** | kabul bandı |
| material `<= -100` | **~161** | inceleme listesi |
| overpay AFL0 `<= -10` | **~19** | negatif PAYABLE — 91i bilerek dışarıda |
| AFL open + EN low `<= -10` | **~498** | PAID odası yok — otomatik reopen yok |

```sql
-- Kabul
SELECT
  SUM(CASE WHEN DELTA_KALAN_NET > 0.02 THEN 1 ELSE 0 END) AS en_gt_afl,
  SUM(CASE WHEN DELTA_KALAN_NET < -0.02 THEN 1 ELSE 0 END) AS afl_gt_en_eps,
  SUM(CASE WHEN DELTA_KALAN_NET <= -10 THEN 1 ELSE 0 END) AS afl_gt_ge10,
  SUM(CASE WHEN DELTA_KALAN_NET <= -100 THEN 1 ELSE 0 END) AS afl_gt_ge100
FROM energy.dbo.MIG_AGR_FRK_ALL WITH (NOLOCK);

DECLARE @Eps decimal(18,2)=0.02;
SELECT
  SUM(CASE WHEN DELTA_KALAN_NET<=-10 AND ISNULL(AFL_KALAN,0)<=@Eps AND ISNULL(EN_KALAN,0)<-@Eps THEN 1 ELSE 0 END) AS overpay_afl0_ge10,
  SUM(CASE WHEN DELTA_KALAN_NET<=-10 AND ISNULL(AFL_KALAN,0)>@Eps AND ISNULL(EN_KALAN,0)+@Eps<ISNULL(AFL_KALAN,0) THEN 1 ELSE 0 END) AS afl_open_en_low_ge10
FROM energy.dbo.MIG_AGR_FRK_ALL WITH (NOLOCK);
```

---

## 4) Log tabloları

| Heal | Log |
|------|-----|
| 91f | `MIG_EN_GT_AFL_KALAN_HEAL_LOG` |
| 91g | `MIG_EN_GT_AFL_PARTIAL_HEAL_LOG` |
| 91h | `MIG_AFL_GT_EN_REOPEN_LOG` |
| 91i | `MIG_OVERPAY_PAID_CLAMP_LOG` |

---

## 5) Bilinçli residual (FAIL sayma)

1. **eps gürültüsü** (`|DELTA_NET| < 10`) — material kabul kullan.  
2. **AFL open + EN=0 + PAID odası yok (~498)** — borç PT yok/iptal; otomatik PT üretme yok.  
3. **Negatif PAYABLE overpay (~19)** — 91i `PAYABLE>=0` guard.  
4. **EKSILTEN_FRK brüt TAH** — çoğu `DELTA_TAH_EKS≈IADE` beklenen TAM görüntüsü; bak `DELTA_TAH_NET` + `DELTA_KALAN_*`.  
5. **EXPECTED_EKS_ONLY** bucket — TAH_NET≈0 + KALAN≈0 → dokunma.

---

## 6) Sonraki FULL / paket (henüz kodlanmadı — hatırlatma)

Over-close’un tekrar üretilmemesi için (ayrı iş):
- `21_597_WIRE` DEBT_PAID: AFL open iken `CLOSED=1` yazma  
- `20_597_INSERT` borç PAID: AFL unpaid floor  
- `92` APPLY: canlı AFL open skip  
- `22_597_GATE`: AFL vs EN_KALAN WARN  

Bu not **patch residual** içindir; cutover EXEC zincirine 91f–91i **koyma** (`PAKET_PATCH_HIZALAMA`).

---

## 7) Dosya yolları (repo)

```
sql/IZGAZ2PCMS/IZGAZ2PCMS/prodEnergy/90_afl_frk/
  91f_en_gt_afl_kalan_heal.sql
  91g_en_gt_afl_partial_heal.sql
  91h_afl_gt_en_reopen_heal.sql
  91i_overpay_paid_clamp_heal.sql
  97_agr_frk_all.sql          → SP_AGR_FRK_ALL
  00_README.txt
```

Canlı düzenleme kökü: `prodEnergy/` (paket kopyası `MIGRATION_SCR_20260708` sync ile).
