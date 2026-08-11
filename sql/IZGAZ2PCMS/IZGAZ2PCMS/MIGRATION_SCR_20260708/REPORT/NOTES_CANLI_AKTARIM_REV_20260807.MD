# NOTES — Canlı aktarım kod revizyonları (FRK / eksilten / güvence)

**Tarih:** 2026-08-07  
**Kaynak:** test FRK (`SP_AGR_FRK_ALL` / `90_afl_frk`) + AGR örnekleri `3`, `174042`, `412056`  
**Durum:** Test heal scriptleri var (`98_TEST_*`). **Canlı/full reload öncesi** aşağıdaki kod/CTAS revizyonları yapılmalı; aksi halde aynı FRK yeniden gelir.

İlgili: `NOTES_597_V5_AFL_CANCEL_REV.md` (CANCEL_REV) · `EMANET_MAHSUP_RULE.md` · `GUVENCE_IADE_110_RULE.md` · `90_afl_frk/00_README.txt` · `../HOTFIX_ANLIK_ENVANTER.md` · **`../PAKET_PATCH_HIZALAMA.md`** (paket vs patch vs açık kod — çelişki yasak)

**Uyarı:** `98_TEST_*` ve residual `91*` / `hotfix/03–04` bu maddeleri **çözmez**. Full reload’da aynı FRK geri gelir. Kalıcı iş CTAS/overlay’de; paket heal bloğu ekleme.

---

## 1) TAM + TYPE92 IADE → MAIN PT kapanışı (kalıcı)

| | |
|--|--|
| **Belirti** | `DELTA_TAH≈IADE≈DELTA_TAH_EKS`, `DELTA_*_NET≈0`, `DELTA_KALAN>0`, AFL=0 |
| **Örnek** | AGR `3` / ACC `28077306` — MAIN açık, TYPE92 var |
| **Kök** | Overlay IADE yazıyor; MAIN `PAYTRANS.PAID` / `INVOICE.CLOSED` tam kapanmıyor |
| **Test** | `90_afl_frk/98_TEST_tam_iade_main_close.sql` → `MIG_TAM_IADE_CLOSE_LOG` (ad-hoc) |
| **Canlı revizyon** | **DONE R20:** `prodREADY_ENERGY/13_590_TAM_MAIN_CLOSE.sql` → `SP_MIG_590_TAM_MAIN_CLOSE`; `19_590_ALL` WIRE→TAM_CLOSE→GATE |
| **Dosya adayları** | `13_590_TAM_MAIN_CLOSE.sql` · `19_590_ALL.sql` · (eski: O51 STG / 98_TEST) |

---

## 2) ASIM (EKS>TAH) — sahte ASIM + açık PT

| | |
|--|--|
| **Belirti** | `KIND=ASIM`, TYPE92 yok, `DELTA_TAH_NET` büyük, `DELTA_KALAN` açık PT, AFL=0 / ABYS TTK=0 |
| **Örnek** | AGR `412056` / ACC `42153632` — EKS=5377.69 = tahakkuk 5368 + **gecikme 9.69** |
| **Kök** | O20 `tah.tut` çoğunlukla ACTION_TYPE=1; gecikme tah dışında → `eks > tah` → ASIM → `LS_OV_EKS_SKIP` (otomatik IADE yok) |
| **Test** | `90_afl_frk/98_TEST_asim_main_close.sql` → `MIG_ASIM_CLOSE_LOG` (PROD değil) |
| **Canlı revizyon** | (a) `tah.tut` tanımına gecikme / ilgili borç action’ları dahil et **veya** (b) `eks ≈ tah+gecikme` ise TAM say; ASIM gerçek EKS>>TAH kalsın. Skip listesi + manuel inceleme ayrı kalsın. |
| **Durum 2026-08-11** | **DONE** — O20 `tah.tut` = `ACTION_TYPE_ID IN (1,3,10,41)` (O11 ile aynı) |
| **Dosya** | `oracleCTAS3007/20_ls_eksilten_overlay.sql` (KIND CASE + tah subquery) · `53_ls_eksilten_family.sql` |

---

## 2b0) AGR_GUARANTY TOTAL — damga gömülü (GTYPE 39)

| | |
|--|--|
| **Belirti** | `LS_005_01_AGR_GUARANTY.TOTAL` = güvence+damga (örn. 4387.20); PCMS `TOTAL = tahsilat−DV` ile uyumsuz |
| **Spot** | AGR `1200078`: GUAR TOTAL **4387.20** · INV109 TL **4346** / DV **41.20** |
| **Kök** | CTAS `LS_AGR_GUARANTY` Dal1 `INCOME_ID` listesinde **23032** |
| **Yapılan (2026-08-11)** | `026` / `LS_AGR_GUARANTY.sql` — 23032 **hariç**; TOTAL/MUSTTL yalnız depozito gelirleri · 195 sync (~07:57) |
| **Koşu** | 026 geçmişse dump öncesi `@@026_LS_AGR_GUARANTY_V01` tekrar |
| **Durum** | **PARTIAL (R21)** — CTAS kod DONE; Oracle re-run + Energy 311 + PCMS spot AÇIK |

### R21 — AGR_GUARANTY devam (PARTIAL)

```text
[x] CTAS 026 kod: 23032 hariç — paket + _deploy_195 (2026-08-11 ~07:57)
[ ] Dump öncesi @@026 re-run + spot TOTAL=4346 (AGR 1200078)
[ ] Energy 311 / LS_005_01_AGR_GUARANTY parity (TOTAL vs INV TL; MUSTTL işareti)
[ ] Gerekirse Energy heal (eski dump / mid-test) — grain: REGISTER_ID satırları
[ ] PCMS sorgu zinciri (tahsilat−DV → GUAR TOTAL) uçtan uca spot
[ ] O60 / GUVENCE_IADE income set’te 23032 ile ilişki netleştir (çakışma yok mu)
```

Backlog: `NOTES_REVIZYON_BACKLOG` **R21**.

---

## 2b) TYPE109 DV — LS_001 header / gelirden DV (LS_005)

| | |
|--|--|
| **Belirti** | Güvence (TYPE109) `TLTOTAL=GRANDTOTAL`, `DV=0`; satırda 23032 var |
| **Referans** | 102 `LS_001`: `TL` damgasız + `DV` dolu + `GT=TL+DV` |
| **Kök** | O10 `TOTAL_EXCL_TAX` damgayı TL’ye gömüyor; O11 `DV=0`; TYPE101 tahsilat `CROSSREF` ile ayrı PT |
| **Kalıcı (CTAS)** | O10: DV ayırımı **yalnız ACCRUE 5/6 (→109) + 21/341 (→111)**; diğer tahakkukta damga TL’de kalır. O11 `DV=TOTAL_DV`. O12 damga satırı yalnız `TYPE IN (109,111)` |
| **Patch** | `92_…HEAL` — TYPE **109+111**; Faz B CROSSREF tahsilat |
| | **Faz A:** TYPE109 INV + IL + borc PT |
| | **Faz B:** CROSSREF tahsilat PT (+ TYPE101 INV) — PCMS `TOTAL = TAH.GT − TAH.DV` |
| **196** | APPLY yapıldı (A ~228k INV; B ~222k TAH xref) — yeniden DryRun aday=0 |
| **Dosya** | `BACKUP/oracleCTAS3007/10…12` · `diag_dv_type109.sql` · `prodREADY_ENERGY/92_INV_DV_FROM_INCOME_HEAL.sql` · paket `251_92_…` / `925_DIAG_DV…` |

### 05:00 data aktarım testi — DV checklist (2026-08-11)

**Önkoşul (Oracle CTAS, dump öncesi):** `10_stg_inv_acc_inc` / `11_ls_invoice` / `12_ls_invlines` güncel TOTAL_DV düzeni diskte olsun.  
Koşu **130’dan önce** ise dosya değişince otomatik alınır. **130–132 (veya 134) eski kodla OK** ise baştan RUNALL yok → `NOTES_CTAS_NO_RESTART` DV bölümü: `@@130…@@132` (+ gerekirse `@@134`) + `@925_DIAG…`. O14 `inv.DV` kopyalar.

**Energy (571→581→575→590→597 sonrası):**

```text
1) sqlcmd … -i prodREADY_ENERGY/92_INV_DV_FROM_INCOME_HEAL.sql   (@DryRun=1, @Agr=NULL)
2) Aday > 0 ise: @DryRun=0 APPLY (FULL)
3) Spot: OWNERREF=1200078 / LREF=147401407
   INV: TL=4346, DV=41.20, GT=4387.20
   TAH (CROSSREF): DV=41.20 → TOTAL=GT-DV=4346
4) Gate: TYPE109+23032’de DV=0 kalan ≈ 0; TAH xref borc.DV≠tah.DV ≈ 0
```

CTAS yeni dump ile gelirse Faz A çoğu kayıtta boş kalır; Faz B yine gerekebilir (101 tahsilat ayrı LREF). Eski dump / heal’siz yüklemede A+B birlikte.

---

## 2c) AGR.FEE_COLLECTED — 109 Güvence + 86 Bağlantı tahsil

| | |
|--|--|
| **Belirti** | `LS_005_01_AGR.FEE_COLLECTED` çoğunlukla 0; CTAS yalnız ACCRUE 5/6 action |
| **Kural** | TYPE **109** + TYPE **86 Bağlantı** (ACCRUE **4/27/28/544**) hepsi `CLOSED=1` → `FEE_COLLECTED=1` |
| **Bağlantı AGR** | INV `OWNERREF`/`ABYS_AGREEMENT_ID` çoğu NULL → EXPLAIN `Abn No:` / `Tes.No:` → `AGR.ABYS_ID` / `FITNO` |
| **Kalıcı (CTAS)** | `LS_AGREEMENT` FEE_COLLECTED: güvence action **ve** bağlanti action (`AGREEMENT_ID` veya `INSTALLATION_ID`) |
| **Patch** | `93_AGR_FEE_COLLECTED_HEAL.sql` — `@RequireBag=1` default; `@DryRun=1` |
| **196** | **APPLY 2026-08-10** — SET_1=**280.987**; KUL `FEE_COLLECTED=1` ≈ **307.890**; log `MIG_AGR_FEE_COLLECTED_LOG` |
| **Residual** | ONLY_GUV ~709k (bağlantı yok/çözülemedi); GUV_OK_BAG_OPEN ~1k; unresolved BAG INV ~7.6k |
| **Dosya** | `prodREADY_ENERGY/93_…` · paket `252_93_…` · `BACKUP/oracleCTAS3007/LS_AGREEMENT.sql` |

---

## 3) Emanet mahsup ↔ güvence gelir (162 / 1936)

| | |
|--|--|
| **Belirti** | ABYS’de EMANET çıkış + mahsup; Energy’de TYPE101 TAHSILAT var, **INVLINES yok** |
| **Örnek** | AGR `412056`: EMANET `42491917` → 778.90; Energy `92340286`/`92340288` TYPE101, IL count=0 |
| **Kural** | Mahsup için **Güvence Bedeli (162)** + **Güvence Fark / güncelleme (1936)** — `EMANET_MAHSUP_RULE.md` |
| **Canlı revizyon** | Mahsup/TAHSILAT fisinde gelir kırılımı (IL) 162/1936 yazılsın; O30 `LS_OV_MAHSUP_*` + 597 kapama ile borç PT doğru PAID. `LS_EMANET` Energy INSERT hâlâ YOK (`EXIT_MAP`) — bilinçli gap veya ayrı SP. |
| **Durum 2026-08-11** | **DONE** — O30 `LS_OV_TAH_INVLINES` (tip12→tip20 162/1936) + O35 `TAH_IL` + 597 INSERT; dump `LS_OV_TAH_INVLINES` |
| **Dosya adayları** | O30 tahsilat/mahsup overlay · `575`/`597` · gelir satırı üretimi (INVLINES) |

---

## 4) TYPE110 — mahsuplaşma sonrası kalan güvence iade (E610)

| | |
|--|--|
| **Belirti** | ABYS’de tediye / kalan güvence iade; Energy TYPE110=0 |
| **Kural** | O60 → dump → `SP_MIG_GUVENCE_IADE_ALL` — `GUVENCE_IADE_110_RULE.md` |
| **Canlı revizyon** | Full aktarım checklist: **O60 dump zorunlu** + deploy `60→69` + `EXEC SP_MIG_GUVENCE_IADE_ALL` (`RUN_ORDER` D2). Test 196’da OV tablo yoktu → zincir çalışmamış. |
| **Dosya** | `oracleCTAS3007/60_ls_ov_guvence_iade.sql` · `prodREADY_ENERGY/60…69x_GUVENCE_IADE_*.sql` |

---

## 5) FRK sınıflandırma (rapor / SP) — kod kalitesi

| | |
|--|--|
| **Belirti** | Küçük `KISMI`/`EKSILTEN_CNT` varken büyük `DELTA_TAH_NET` → `KIND_FRK=EKSILTEN_FRK` + yanıltıcı ACIKLAMA |
| **Canlı revizyon** | `SP_AGR_FRK_ALL`: KIND önce NET; `DELTA_KALAN_EKS` / `DELTA_KALAN_NET`; ACIKLAMA’da ASIM ayrı |
| **Dosya** | `90_afl_frk/97_agr_frk_all.sql` |

---

## Aktarım günü kontrol listesi (bu notlara özel)

```
[x] O20 eksilten KIND: gecikme dahil TAM/ASIM düzeltmesi deploy
[x] TAM+IADE → MAIN PT close — E590 `SP_MIG_590_TAM_MAIN_CLOSE` (R20); 98_TEST yalnızca ad-hoc
[x] O30/597 mahsup: TYPE101 + IL 162/1936 (spot 412056 tipi) — `LS_OV_TAH_INVLINES` + 597 TAH_IL
[ ] O60 dump + E610 EXEC TYPE110 (RUN_ORDER D2)
[ ] 597 v5 CANCEL_REV (NOTES_597_V5…) GATE_PASS
[ ] Post: SP_AGR_FRK_ALL @OnlyDiff=1 — TAM kalan / ASIM kalan / NET only ayır
[ ] Spot: AGR 3 (TAM), 412056 (ASIM+emanet mahsup)
```

Test-only (canlıda çalıştırma): `98_TEST_tam_iade_main_close.sql`, `98_TEST_asim_main_close.sql`.

---

## Okuma kuralı (FRK satırı)

| Kolon | Canlıda bak |
|-------|-------------|
| `DELTA_TAH_EKS` | Overlay/IADE bacağı |
| `DELTA_TAH_NET` | Gerçek tah / ONLY_EN–ABYS / ASIM hesabı |
| `DELTA_KALAN` | Açık PT vs AFL — TAM/ASIM close veya STG |
| `EN_IADE` / TYPE92 | TAM path |
| OV `KIND` | TAM / KISMI / **ASIM** (ASIM≠güvence mahsup) |
