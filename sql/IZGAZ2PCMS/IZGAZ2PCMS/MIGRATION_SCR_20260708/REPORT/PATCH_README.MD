# patch/ — cutover dışı yama envanteri

Bu klasör **script deposu değil**; paket EXEC zincirine girmeyen yamaların **tek pointer’ı**.

Dosyalar yerinde kaldı (`hotfix/`, `prodREADY_*`, `90_afl_frk/`) — path kırılmasın diye taşınmadı.

| Belge | Ne için |
|-------|---------|
| [`../PAKET_PATCH_HIZALAMA.md`](../PAKET_PATCH_HIZALAMA.md) | Paket / patch / açık kod ayrımı |
| [`../HOTFIX_ANLIK_ENVANTER.md`](../HOTFIX_ANLIK_ENVANTER.md) | Tam envanter + sınıflar |
| [`../prodREADY_ENERGY3007/EXIT_MAP.md`](../prodREADY_ENERGY3007/EXIT_MAP.md) | 3007 çıkış haritası |
| [`../hotfix/00_HOTFIX_ORDER.txt`](../hotfix/00_HOTFIX_ORDER.txt) | Legacy hotfix koşu sırası |

---

## İlke

```text
PAKET  →  full reload EXEC / deploy  (RUN_ORDER)
PATCH  →  kirli DB veya kapı sonrası opsiyonel  (bu liste)
TEST   →  canlıda YASAK
AÇIK   →  CTAS/overlay kod işi — heal ile “çözülmüş” sayma
```

**Full reload + güncel 590/597 sonrası** legacy `hotfix/03–04` ve çoğu residual **gerekmez**.  
Kalıcı FRK kökü: CTAS / overlay — paket şişirme veya `98_TEST_*` heal yok.

---

## Ne zaman bakılır?

| Durum | Aksiyon |
|-------|---------|
| Temiz cutover (yeni dump + SP) | Bu listeyi **atlama** — `RUN_ORDER` + FRK `95→99→97` |
| Eski / kirli energy (PG-098 tipi) | Legacy `hotfix/` + sıra dosyası |
| GATE sonrası residual semptom | `91*` / `22b` (sadece semptom varsa) |
| Test DB’de TAM/ASIM denemesi | `98_TEST_*` — **canlıda asla** |
| NOTES_CANLI #1–3 (MAIN close, ASIM, mahsup) | Patch değil → CTAS/overlay PR |

---

## 1) Legacy — `../hotfix/`

Eski 590 dump / full 597 CLEAN yokken. **Yeni paket sonrası 03/04 → N/A.**

| Script | Tip | Full reload sonrası |
|--------|-----|---------------------|
| [`03_backfill_iade_invlines.sql`](../hotfix/03_backfill_iade_invlines.sql) | PATCH | Gerekmez (yeni 590) |
| [`04_patch_kismi_debt_pt.sql`](../hotfix/04_patch_kismi_debt_pt.sql) | PATCH | Gerekmez (yeni 590) |
| [`02_patch_resync_amounts_from_ov.sql`](../hotfix/02_patch_resync_amounts_from_ov.sql) | PATCH ops | Nadir — DEC2 fark varsa |
| [`01_diag_kurus_src_en.sql`](../hotfix/01_diag_kurus_src_en.sql) | DIAG | OK (salt okuma) |
| [`05_diag_linenr_gt_255.sql`](../hotfix/05_diag_linenr_gt_255.sql) | DIAG | OK (salt okuma) |
| [`00_HOTFIX_ORDER.txt`](../hotfix/00_HOTFIX_ORDER.txt) | Sıra | — |

Koşu: `@DRY_RUN=1` → kontrol → `@DRY_RUN=0`.

---

## 2) Residual — kapı sonrası (opsiyonel)

| Script | Ne |
|--------|-----|
| [`../prodREADY_ENERGY3007/91_debt_pt_dup_cleanup.sql`](../prodREADY_ENERGY3007/91_debt_pt_dup_cleanup.sql) | DUP_2X (CP=1 asla KEEP) |
| [`../prodREADY_ENERGY3007/91b_false_installment_plan_ref_cleanup.sql`](../prodREADY_ENERGY3007/91b_false_installment_plan_ref_cleanup.sql) | FALSE_REF |
| [`../prodREADY_ENERGY3007/91c_tah_crossref_paid_detect.sql`](../prodREADY_ENERGY3007/91c_tah_crossref_paid_detect.sql) | DIAG — PAID gap |
| [`../prodREADY_ENERGY3007/91d_debt_paid_sync_from_tah.sql`](../prodREADY_ENERGY3007/91d_debt_paid_sync_from_tah.sql) | HEAL — PAID ← tah |
| [`../prodREADY_ENERGY/22b_597_DEBT_PT_BACKFILL.sql`](../prodREADY_ENERGY/22b_597_DEBT_PT_BACKFILL.sql) | Debt PT eksik (597 idle) |
| [`../prodREADY_ENERGY3007/36_backfill_null_agr_owner.sql`](../prodREADY_ENERGY3007/36_backfill_null_agr_owner.sql) | Ops — primary değil |

> `92_stg_inv_pay_close_apply.sql` → **PAKET** (cutover sırası); patch değil.

---

## 3) TEST — canlıda YASAK

| Script | Not |
|--------|-----|
| [`../90_afl_frk/98_TEST_tam_iade_main_close.sql`](../90_afl_frk/98_TEST_tam_iade_main_close.sql) | Test heal — MAIN close |
| [`../90_afl_frk/98_TEST_asim_main_close.sql`](../90_afl_frk/98_TEST_asim_main_close.sql) | Test heal — ASIM |
| [`../90_afl_frk/98_tam_iade_main_pt_close_temp.sql`](../90_afl_frk/98_tam_iade_main_pt_close_temp.sql) | Eski varyant |

Kalıcı kök: [`NOTES_CANLI_AKTARIM_REV_20260807.md`](../prodREADY_ENERGY/NOTES_CANLI_AKTARIM_REV_20260807.md) (O20 / 590–597 / mahsup).

---

## 4) Spot rapor (paket kapısı değil)

| Script | Rol |
|--------|-----|
| [`../90_afl_frk/96_agr5727_ttk_vs_inv.sql`](../90_afl_frk/96_agr5727_ttk_vs_inv.sql) | Tek AGR örnek karşılaştırma |

Paket FRK kapısı: `95` → `99` → `97 @OnlyDiff=1` (`90_afl_frk/`).

---

## Full reload beklenti (özet)

```text
PAKET:      O30h · 597 v5 · E610 · 92 · 95/97/99
PATCH YOK:  hotfix/03, 04
OPS:        91 / 91b / 91c→91d / 22b  — yalnız residual semptom
YASAK:      98_TEST_*
AÇIK KOD:   NOTES_CANLI #1–3  — ayrı CTAS/overlay işi
```

Spot doğrulama AGR: **3** (TAM) · **412056** (ASIM+mahsup) · INV **66081785** (CANCEL_REV)
