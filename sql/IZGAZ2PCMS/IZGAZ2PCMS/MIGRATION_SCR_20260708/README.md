# MIGRATION_SCR_20260708 — CTAS + ENERGY + REPORT

Repo yolu = 195 yolu (ayni klasor yapisi):
- Repo: `sql/IZGAZ2PCMS/IZGAZ2PCMS/MIGRATION_SCR_20260708/`
- 195:  `C:\www\MIGRATION_SCR_20260708\`

Kaynaklar yerinde kaldi; bu klasor **kopya** paket yuzeyidir (cut degil).
Son yenileme: 2026-08-11.

## CTAS/
Omurga: `oracleCTAS3007` · ayni ad varsa daha yeni: `oracleCTAS/prodREADY`  
Ad: `NNN_NAME_Vnn.SQL` (**BUYUK HARF**) · tek orch: `00_RUN_ALL.SQL`  
Map: `_ctas_nnn_map.ps1`

| NNN | Anlam |
|-----|--------|
| `001–009` | DOC (INDEX/SCHEMA/DUMP) |
| `010–019` | SETUP (LOG/SESSION/PARAM) — RUNALL |
| `020–099` | MASTER — RUNALL |
| `100–129` | OKUMA/HHD — RUNALL |
| `130–199` | FATURA/OVERLAY/GATE — RUNALL |
| `200–259` | POST + IX + LOG — RUNALL |
| `900+` | PILOT/EXTRA/DIAG — RUNALL disi |

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
195 mirror: `_deploy_195.ps1`  
**Yasak:** `SRC_*` / yan paket — tek yuzey bu uc klasor.
