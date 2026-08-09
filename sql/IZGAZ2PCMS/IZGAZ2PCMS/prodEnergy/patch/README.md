# patch/ — ayrı patch pointer (dosyalar taşınmadı)

Cutover **PAKET** EXEC zincirine girmeyen scriptler burada listelenir.
Tam ayrım: `../PAKET_PATCH_HIZALAMA.md` · envanter: `../HOTFIX_ANLIK_ENVANTER.md`

## Legacy (prodEnergy/hotfix/) — eski DB / PG-098

| Script | Tip | Full reload sonrası |
|--------|-----|---------------------|
| `../hotfix/03_backfill_iade_invlines.sql` | PATCH | Gerekmez (yeni 590) |
| `../hotfix/04_patch_kismi_debt_pt.sql` | PATCH | Gerekmez (yeni 590) |
| `../hotfix/02_patch_resync_amounts_from_ov.sql` | PATCH ops | Nadir |
| `../hotfix/01_diag_kurus_src_en.sql` | DIAG | OK |
| `../hotfix/05_diag_linenr_gt_255.sql` | DIAG | OK |
| `../hotfix/00_HOTFIX_ORDER.txt` | Sıra | — |

## Residual (kapı sonrası opsiyonel)

| Script | Ne |
|--------|-----|
| `../prodREADY_ENERGY3007/91_debt_pt_dup_cleanup.sql` | DUP_2X |
| `../prodREADY_ENERGY3007/91b_false_installment_plan_ref_cleanup.sql` | FALSE_REF |
| `../prodREADY_ENERGY3007/91c_tah_crossref_paid_detect.sql` | DIAG |
| `../prodREADY_ENERGY3007/91d_debt_paid_sync_from_tah.sql` | PAID heal |
| `../prodREADY_ENERGY/22b_597_DEBT_PT_BACKFILL.sql` | Debt PT eksik |
| `../prodREADY_ENERGY3007/36_backfill_null_agr_owner.sql` | Primary değil |

## TEST — canlıda YASAK

| Script |
|--------|
| `../90_afl_frk/98_TEST_tam_iade_main_close.sql` |
| `../90_afl_frk/98_TEST_asim_main_close.sql` |
| `../90_afl_frk/98_tam_iade_main_pt_close_temp.sql` |

Kalıcı çözüm: `NOTES_CANLI_AKTARIM_REV_20260807.md` (O20 / 590–597 / mahsup) — heal ile paket şişirme.

## Spot rapor (paket kapısı değil)

| Script |
|--------|
| `../90_afl_frk/96_agr5727_ttk_vs_inv.sql` |
