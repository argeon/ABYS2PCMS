# prodREADY_ENERGY3007 — izgazMGR → ENERGY (CTAS3007 sonrası)

Oracle paket: `oracleCTAS3007` · Dump: izgazMGR birebir · Bu paket: ENERGY cutover.

**Tüm çıkışlar:** [EXIT_MAP.md](EXIT_MAP.md)

## Sıra

```text
ÖNKOŞUL master/HHD (EXIT_MAP §1–2)
→ 00b/00c dump prep → 00 gate → 01 pilot → 05/05b/05c collation
→ 10 setup+MAP → 20 571/581/575 → 30 590/597 → 35 bankref
→ 50 611/613 → 40 IPP → 92 close → 90 check
(@AGR_ID: NULL=FULL | >0=AGR | -1=NO_AGR; 30b ayrica)
```

Detay: [RUN_ORDER.sql](RUN_ORDER.sql) · Pilot: [01_PILOT_SPOT.md](01_PILOT_SPOT.md) · [INDEX.md](INDEX.md) · [EXIT_MAP.md](EXIT_MAP.md)

## Dosyalar

| Dosya | Ne |
|-------|-----|
| `EXIT_MAP.md` | izgazMGR→energy tam envanter (EVET/ÖNKOŞUL/YOK/DIAG) |
| `00_izgazmgr_gate_checkpoint.sql` | Manifest + kolon + LREF + PAY_PAID_GAP + checkpoint |
| `01_PILOT_SPOT.md` | Wizard tek-AGR |
| `05` / `05b` / `05c` | CP1254 collation (energy + izgazMGR) |
| `10_setup_and_map.sql` | MAP copy + setup hatırlatma |
| `20_main_load_571_581_575.sql` | Ana yükleme (`NULL`/`>0`/`-1`) |
| `30_EXEC_FINANCIAL_CHAIN.sql` | Açık EXEC 571→597→611→613 |
| `30_overlay_590_597.sql` | 590→597 |
| `10f_DEPLOY_FINANCIAL_SP.sql` | SP deploy checklist + varlık |
| `35_bankref_resolve_abys.sql` | BANKREF → LS_BANK.LREF |
| `40_installment_plan_pay_apply.sql` | O57 → INST_NR PAID/banka/CLOSED |
| `50_post_taksit_close_afl.sql` | 611/613/92/AFL checklist |
| `90_check_queries.sql` | Delta + taksit + FRK soft |
| `MANUAL_CHECKLIST.txt` | Operatör checkbox |

Dump prep (komşu paket): `../prodREADY_ENERGY/00b_align_mgr_varchar.sql`, `00c_enrich_mgr_kismi_lineexp.sql`

Setup/overlay SP gövdeleri: [../prodREADY_ENERGY/](../prodREADY_ENERGY/) · Migrate SP: [../../ProdIzgazMgr2Energy/prodENERGY/](../../ProdIzgazMgr2Energy/prodENERGY/)

## Kurallar

- Gate FAIL → ENERGY yok
- Pilot FAIL → full cutover yok
- `@AGR_ID`: NULL=FULL | >0=AGR | -1=NO_AGR (30b); FULL yasağı kalkmıştır
- 575 ile Oracle O14 çift yazma yok
- Overlay yalnızca `*_ALL`
- Dump sonrası `00b` — bare string join; query-time COLLATE/CAST yasak
- Master + 521/524 önkoşul (EXIT_MAP)
