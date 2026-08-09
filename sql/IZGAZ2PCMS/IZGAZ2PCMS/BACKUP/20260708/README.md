# 20260708 — CTAS + ENERGY + REPORT snapshot (COPY)

Kaynaklar yerinde kaldi; bu klasor **kopya** arsivdir (cut degil).
Son yenileme: 2026-08-09.
**Guncel paket:** 2. bir tarihli klasor acilana kadar burasi.

## CTAS/
Omurga: `oracleCTAS3007` · ayni ad varsa daha yeni: `oracleCTAS/prodREADY`  
Ad: `NNN_ORIJINAL_AD.SQL` (**BUYUK HARF**).

| NNN | Anlam |
|-----|--------|
| `000_*` | Dokuman — `000_RUN_ORDER.MD` sira kaynagi |
| `001–027` | Faz A — Master CTAS (+ LS_PROJECT / LS_PROJECTLINE) |
| `030–060` | Faz B — Full tahsilat / O60 GUVENCE |
| `070+` | prodREADY / 3007 extra (HOTFIX/diag/checklist) |
| `090–091` | Orkestrator |

## ENERGY/
| Kaynak | Icerik |
|--------|--------|
| `prodREADY_ENERGY` | 570 zinciri setup, 590/597 overlay, **610 GUVENCE_IADE**, RUN_ORDER, NOTES, hotfix |
| `ProdIzgazMgr2Energy/prodENERGY` | **tam master zincir** (04–920) + 57x + **590–596 PROJECT/PROJECTLINE** + SPEFEE/LEGAL/INSTALLMENT |
| `prodREADY_ENERGY3007` | financial chain, bankref, taksit, 91/91b/91c/**91d** |
| `90_afl_frk` | 91–99 FRK/TTK (+ 98_TEST_*) |

Index: `ENERGY/000_ENERGY_INDEX.MD`

## REPORT/
Kontrol / FRK / checklist kopyalari (akis disi calistirma paketi).

Manifest: `MANIFEST_CTAS.txt` · `MANIFEST_ENERGY.txt` · `MANIFEST_REPORT.txt`  
Yenile: `_sync_snapshot.ps1`
