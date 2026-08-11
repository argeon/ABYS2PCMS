# Paket vs Patch hizalama (aktarım öncesi)

**Tarih:** 2026-08-07  
**İlke:** Canlı notlarla (`NOTES_CANLI_AKTARIM_REV_20260807`, `NOTES_597_V5`) çelişen **test heal / anlık yama** cutover paketinin EXEC zincirine **girmez**. Kalıcı kök çözüm CTAS/overlay’de ayrı iş; residual patch kapı sonrası opsiyonel.

Kaynaklar: `EXIT_MAP.md` · `HOTFIX_ANLIK_ENVANTER.md` · `prodREADY_ENERGY/RUN_ORDER.sql` · `prodREADY_ENERGY3007/RUN_ORDER.sql`

---

## 1) PAKET İÇİ (full reload EXEC / deploy)

Bunlar cutover runbook’unda; yeni dump + SP ile gelir. Eski DB yaması değil.

| Blok | Dosya / yol | Not |
|------|-------------|-----|
| 597 v5 CANCEL_REV | `prodREADY_ENERGY/28_DEPLOY_597.sql` (20→21→00g→22→29) | AFL kapalı → REV yazma; GATE_PASS şart |
| 575/576 CP=0 UX | `ProdIzgazMgr2Energy/…/575*`, `576*` | v5 ile birlikte |
| E610 TYPE110 | `60→61→62→69` + `69x_GUVENCE_IADE_EXEC` | **O60 dump zorunlu**; RUN_ORDER D2 |
| 590/597 ALL | yalnız `*_ALL` EXEC | tek INSERT yasak |
| STG close | `90_afl_frk/92_stg_inv_pay_close_apply.sql` | AFL_OPEN dokunma |
| CTAS O30h | `30_HOTFIX_ls_ov_tah_log_pay_before.sql` | dump sırası O30→O30h; O40 SKIP |
| FRK gate (salt) | `95_ttk_inv_afl_fatura_rapor.sql` | CP=0; post-cutover |
| FRK özet SP | `97_agr_frk_all.sql` → `SP_AGR_FRK_ALL` | `@OnlyDiff=1` |
| AFL kalan | `99_afl_vs_en_kalan_frk.sql` | BALANCE vs PT kalan |
| Envanter | `EXIT_MAP.md` · `INDEX.md` · checklist | — |

**Post doğrulama sırası (paket, yazmaz / salt veya log):**  
`95` → `99` → `97 @OnlyDiff=1` → spot AGR 3 / 412056 / INV 66081785

---

## 2) AYRI PATCH (cutover EXEC zincirine KOYMA)

`prodEnergy/hotfix/` + residual 91* — mevcut kirli DB veya kapı sonrası. Full reload + güncel SP sonrası **çoğu gerekmez**.

| Grup | Script | Ne zaman |
|------|--------|----------|
| Legacy HF | `hotfix/03`, `04` | Eski 590 dump öncesi; **yeni paket sonrası YOK** |
| Legacy ops | `hotfix/02` | DEC2 fark varsa |
| Legacy diag | `hotfix/01`, `05` | Salt okuma — her zaman OK |
| Residual | `91_debt_pt_dup_cleanup` | GATE sonrası hâlâ DUP_2X |
| Residual | `91b_false_installment_plan_ref` | Yanlış PLAN_REF |
| Residual | `91c` → `91d` | Tah CROSSREF PAID gap |
| Residual | `22b_597_DEBT_PT_BACKFILL` | GATE: debt PT eksik; 597 idle |
| Spot rapor | `96_agr5727_ttk_vs_inv` | Tek AGR örnek; paket kapısı değil |
| **TEST YASAK** | `98_TEST_*`, `98_tam_iade_*_temp` | Test DB heal — **canlıda ÇALIŞTIRMA** |

Ayrı klasör notu: `patch/README.md` (bu ayrımı sabitleyen pointer; dosyalar taşınmadı — path kırılmasın).

---

## 3) AÇIK KOD İŞİ (pakete heal olarak YAZILMAZ)

`NOTES_CANLI_AKTARIM_REV_20260807` maddeleri. Bunları `98_TEST` veya residual patch ile “çözülmüş” saymak **risk**: full reload’da aynı FRK geri gelir.

| # | Konu | Doğru yer | Durum |
|---|------|-----------|--------|
| 1 | TAM+TYPE92 → MAIN PT/CLOSED | E590 `13_TAM_MAIN_CLOSE` (R20) | **DONE** |
| 2 | Sahte ASIM (gecikme tah dışı) | `20_ls_eksilten` `tah.tut` ∈(1,3,10,41) | **DONE** CTAS 2026-08-11 |
| 3 | Emanet mahsup IL 162+1936 | O30 `LS_OV_TAH_INVLINES` + 597 TAH_IL | **DONE** CTAS+597 2026-08-11 |
| 4 | TYPE110 zinciri | O60 dump + E610 — **paket D2** | AÇIK (dump yoksa ATLA) |
| 5 | FRK KIND/ACIKLAMA | `97` SP (NET öncelik) — rapor kalitesi | rapor kalitesi |
| 6 | AGR_GUARANTY TOTAL−damga | CTAS `026` 23032 hariç | **PARTIAL R21** (kod DONE; koşu/311 açık) |

**CTAS paket+195 (2026-08-11 ~07:57):** O20/O30/DV/GUAR/FEE kod sync. Heal/`98_TEST` ile “çözüldü” sayma YASAK.

---

## 4) FRK okuma kuralı (operatör)

| Kolon | Anlam | Aksiyon |
|-------|--------|---------|
| `DELTA_TAH_EKS` | Overlay/IADE/ASIM bacağı | O20/590 |
| `DELTA_TAH_NET` | Gerçek tah / ONLY_EN–ABYS | TTK / ana yük |
| `DELTA_KALAN` / `_EKS` / `_NET` | Açık PT vs AFL | STG/597 veya açık kod #1–2 |
| `EN_IADE` / TYPE92 | TAM path | #1 |
| OV `KIND` | TAM / KISMI / **ASIM** | ASIM ≠ güvence mahsup (#3) |

Spot: AGR **3** (TAM) · **412056** (ASIM+mahsup) · INV **66081785** (CANCEL_REV)

---

## 5) Aktarım günü kısa sıra

```
ÖNKOŞUL  EXIT_MAP §1–2 + AFL dump + O60 dump (TYPE110 için)
DEPLOY   10f + 28_DEPLOY_597 (v5) + E610 60→69
EXEC     571→581→575→576 → 590_ALL → 597_ALL → GATE_PASS
         → E610 ALL (D2) → 35 bank → 611/613/40 → 92 STG
VALIDATE 95 → 99 → 97 @OnlyDiff=1 → spotlar
PATCH    yalnız residual gerekirse (91/91b/91c→91d) — 98_TEST YOK
AÇIK     #4 TYPE110 (O60) + R21 koşu/311 bitmeden “FRK bitti” deme
         (#1–3 + DV/FEE CTAS kod DONE 2026-08-11)
```
