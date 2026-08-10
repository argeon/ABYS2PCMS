# Hotfix / anlık düzeltme envanteri

**Tarih:** 2026-08-07  
**Üst belge:** [`PAKET_PATCH_HIZALAMA.md`](PAKET_PATCH_HIZALAMA.md) — paket / patch / açık kod ayrımı (çelişki yasak).  
**Pointer:** [`patch/README.md`](patch/README.md)

İlgili: `hotfix/00_HOTFIX_ORDER.txt` · `NOTES_CANLI_AKTARIM_REV_20260807.md` · `NOTES_597_V5_AFL_CANCEL_REV.md`

---

## Sınıflar (özet)

| Sınıf | Cutover | Örnek |
|-------|---------|--------|
| **PAKET** | EXEC/deploy zincirinde | 597 v5, E610, 92, O30h, 95/97/99 |
| **PATCH ayrı** | Zincire koyma | hotfix/03–04, 91*, 22b |
| **TEST** | Canlıda yasak | 98_TEST_* |
| **AÇIK KOD** | Heal ile kapatma | O20 ASIM, TAM MAIN close, mahsup IL |
| **DIAG** | Salt okuma | 01, 05, 91c, 96 spot |

---

## A) PAKET — CTAS hotfix

| Script | Ne |
|--------|-----|
| `oracleCTAS/prodREADY/30_HOTFIX_ls_ov_tah_log_pay_before.sql` | `LS_OV_TAH_LOG` PAY_BEFORE_TAH*; O30→O30h; O40 SKIP |

---

## B) AYRI PATCH — `hotfix/` (2026-07-24 / eski DB)

Full 597 CLEAN yokken. **Yeni 590/597 + dump sonrası 03/04 gerekmez.**

| # | Script | Tip |
|---|--------|-----|
| 03 | `03_backfill_iade_invlines.sql` | PATCH — TYPE92 IL |
| 04 | `04_patch_kismi_debt_pt.sql` | PATCH — KISMI PT=HDR |
| 02 | `02_patch_resync_amounts_from_ov.sql` | PATCH ops |
| 01 | `01_diag_kurus_src_en.sql` | DIAG |
| 05 | `05_diag_linenr_gt_255.sql` | DIAG |

---

## C) AYRI PATCH — residual (kapı sonrası)

| Script | Tip | Ne |
|--------|-----|-----|
| `91_debt_pt_dup_cleanup.sql` | HEAL | DUP_2X; CP=1 asla KEEP |
| `91b_false_installment_plan_ref_cleanup.sql` | HEAL | FALSE_REF NULL |
| `91c_tah_crossref_paid_detect.sql` | DIAG | PAID gap |
| `91d_debt_paid_sync_from_tah.sql` | HEAL | PAID ← tah |
| `22b_597_DEBT_PT_BACKFILL.sql` | HEAL | Debt PT eksik |
| `36_backfill_null_agr_owner.sql` | ops | Primary değil |
| `92_stg_inv_pay_close_apply.sql` | **PAKET** APPLY | Cutover sırası (patch değil) |

---

## D) TEST — canlıda YASAK

| Script | Log |
|--------|-----|
| `98_TEST_tam_iade_main_close.sql` | `MIG_TAM_IADE_CLOSE_LOG` |
| `98_TEST_asim_main_close.sql` | `MIG_ASIM_CLOSE_LOG` |
| `98_tam_iade_main_pt_close_temp.sql` | eski varyant |

Kalıcı: `NOTES_CANLI…` → O20/590/597/STG — **pakete gömme**.

---

## E) PAKET — FRK / diag (salt)

| Script | Rol |
|--------|-----|
| `95_ttk_inv_afl_fatura_rapor.sql` | Gate (CP=0) |
| `97_agr_frk_all.sql` | `SP_AGR_FRK_ALL` |
| `99_afl_vs_en_kalan_frk.sql` | AFL vs PT kalan |
| `96_agr5727_…` | Spot — paket kapısı değil |
| `91_afl_frk_compare_log` / `93*` / `94` | AFL/TTK |

---

## Full reload beklenti

```
PAKET:     O30h · 597 v5 · E610 · 92 · 95/97/99
PATCH YOK: hotfix/03,04 (yeni SP+dump)
OPS:       91/91b/91c→91d/22b yalnız residual
YASAK:     98_TEST_*
AÇIK:      NOTES_CANLI #1–3 (O20 / MAIN close / mahsup IL) — ayrı kod işi
```
