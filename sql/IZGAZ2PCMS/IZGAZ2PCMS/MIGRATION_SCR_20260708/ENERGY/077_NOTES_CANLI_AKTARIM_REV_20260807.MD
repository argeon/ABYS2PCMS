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
| **Test** | `90_afl_frk/98_TEST_tam_iade_main_close.sql` → `MIG_TAM_IADE_CLOSE_LOG` |
| **Canlı revizyon** | IADE / 590–597 zincirinde (veya STG close): TAM hesapta AFL≈0 iken MAIN PT `PAID=PAYABLE` + `CLOSED=1` |
| **Dosya adayları** | `oracleCTAS3007/20_ls_eksilten_overlay.sql` (TAM→IADE) · energy 590/597 WIRE · O51 `LS_STG_INV_PAY_CLOSE` apply |

---

## 2) ASIM (EKS>TAH) — sahte ASIM + açık PT

| | |
|--|--|
| **Belirti** | `KIND=ASIM`, TYPE92 yok, `DELTA_TAH_NET` büyük, `DELTA_KALAN` açık PT, AFL=0 / ABYS TTK=0 |
| **Örnek** | AGR `412056` / ACC `42153632` — EKS=5377.69 = tahakkuk 5368 + **gecikme 9.69** |
| **Kök** | O20 `tah.tut` çoğunlukla ACTION_TYPE=1; gecikme tah dışında → `eks > tah` → ASIM → `LS_OV_EKS_SKIP` (otomatik IADE yok) |
| **Test** | `90_afl_frk/98_TEST_asim_main_close.sql` → `MIG_ASIM_CLOSE_LOG` (PROD değil) |
| **Canlı revizyon** | (a) `tah.tut` tanımına gecikme / ilgili borç action’ları dahil et **veya** (b) `eks ≈ tah+gecikme` ise TAM say; ASIM gerçek EKS>>TAH kalsın. Skip listesi + manuel inceleme ayrı kalsın. |
| **Dosya** | `oracleCTAS3007/20_ls_eksilten_overlay.sql` (KIND CASE + tah subquery) · `53_ls_eksilten_family.sql` |

---

## 3) Emanet mahsup ↔ güvence gelir (162 / 1936)

| | |
|--|--|
| **Belirti** | ABYS’de EMANET çıkış + mahsup; Energy’de TYPE101 TAHSILAT var, **INVLINES yok** |
| **Örnek** | AGR `412056`: EMANET `42491917` → 778.90; Energy `92340286`/`92340288` TYPE101, IL count=0 |
| **Kural** | Mahsup için **Güvence Bedeli (162)** + **Güvence Fark / güncelleme (1936)** — `EMANET_MAHSUP_RULE.md` |
| **Canlı revizyon** | Mahsup/TAHSILAT fisinde gelir kırılımı (IL) 162/1936 yazılsın; O30 `LS_OV_MAHSUP_*` + 597 kapama ile borç PT doğru PAID. `LS_EMANET` Energy INSERT hâlâ YOK (`EXIT_MAP`) — bilinçli gap veya ayrı SP. |
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
[ ] O20 eksilten KIND: gecikme dahil TAM/ASIM düzeltmesi deploy
[ ] TAM+IADE → MAIN PT close (590/597/STG) — 98_TEST_tam semptomu gelmesin
[ ] O30/597 mahsup: TYPE101 + IL 162/1936 (spot 412056 tipi)
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
