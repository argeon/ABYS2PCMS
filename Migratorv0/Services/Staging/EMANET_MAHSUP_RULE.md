# Emanet ↔ mahsup (güvence / iptal bakiyesi)

## Tipik zincir (güvence bedeli → fesih borcu)
Örnek AGR `437611`:

| Hesap | ACCRUE | Rol |
|-------|--------|-----|
| **30667167** | **14 EMANET** | Güvence havuzu |
| **30667165** | 26 (iş emri) | Fesih borcu 7,25 |

```text
1) tip20 EMANET GİRİŞİ  @30667167  −504,51   (162 GÜVENCE + 1936 GÜVENCE FARK)
2) tip12 EMANET ÇIKIŞI  @30667167  +7,25     REF→30667165  (güvenceden çıkış)
3) tip6  MAHSUP         @30667165  −7,25     REF_DEP→30667167, DEP_ACT→tip12
4) tip40 PTT TEDİYE     @30667167  +497,26   (kalan güvence iadesi)
→ 30667165 bakiyesi = 0 (mahsup ile kapandı)
```

Gelir kodları: **162 = GÜVENCE BEDELİ**, **1936 = GÜVENCE FARK BEDELİ**.

PCMS TYPE **110** (GÜVENCE BEDELİ İADE) için CTAS: `oracleCTAS3007/60_ls_ov_guvence_iade.sql` — bkz. `GUVENCE_IADE_110_RULE.md`.

## Diğer kaynak
Tahsilat **iptal** (tip **9**) da emanet üretebilir; aynı `tip12 → tip6/24` mahsup modeli geçerli.

## Grain (SMS)
| Alan | Nerede | Anlam |
|------|--------|--------|
| `ACCRUE_TYPE_ID=14` | CS_ACCOUNT | Emanet hesabı |
| tip **20** | EMANET GİRİŞİ | Güvence/iptal bakiyesi girişi |
| tip **12** | EMANET ÇIKIŞI | `REF_DEPOSIT_ACCOUNT_ID` = borçlu fatura |
| tip **6/24** | MAHSUP | `REF_DEPOSIT_ACCOUNT_ID` = emanet; `REF_DEPOSIT_ACCOUNT_ACTION_ID` = tip12 |
| Aynı emanet | — | Birden fazla faturaya mahsup (`DEP_MAIN_CNT`) |

## Wizard KIND
| KIND | Kaynak |
|------|--------|
| `EMANET_GIRIS` | tip20 (ACCRUE14) |
| `CANCEL_EMANET` | tip12 (+ hedef borç REF) |
| `EMANET_MAHSUP` | tip6/24 + REF_DEPOSIT |
| `PAY_CANCEL` | tip9 |

Overlay: `LS_OV_MAHSUP_SRC` / `LS_OV_MAHSUP_CLOSED` (O30).

## Örnek AGR `412056` (tesisat 352) — mahsup ≠ eksilten

ABYS hesapları:

| ACCOUNT | Tür | Rol |
|---------|-----|-----|
| **42491917** | EMANET | Çıkış / mahsup kaynağı **778,90** (makbuz 1110225) |
| **42489985 / 42489984** | EMANET | Yan emanet (0 bakiye) |
| **42153632** | EL TERMİNALİ TÜKETİM | Borç: tahakkuk 5368 + gecikme 9,69 |

Zincir:

```text
1) tip20/emanet havuzu          → gelir 162 GÜVENCE + 1936 GÜVENCE FARK (güncelleme)
2) tip12 EMANET ÇIKIŞI @42491917 → 778,90  REF→42153632
3) tip6  MAHSUP         @42153632 → Energy TYPE101 LREF 92340286/92340288 (778,75+0,15)
4) tip2  EKSİLTEN       @42153632 → −5377,69 (5368+9,69; güvence değil)
```

Ayırım:

| Bacak | Tutar | Kapsayan not / pipeline | Test heal |
|-------|-------|-------------------------|-----------|
| Mahsup (güvence) | 778,90 | Bu dosya + O30 `LS_OV_MAHSUP_*` / `LS_OV_TAH_INVLINES` / 597 TAH_IL | Energy TYPE101 + **INVLINES 162/1936** |
| Mahsup sonrası kalan iade | (varsa) | `GUVENCE_IADE_110_RULE.md` · O60 → E610 TYPE110 | 196’da `LS_OV_GUVENCE_IADE_*` yok → TYPE110=0 |
| Eksilten sonrası açık PT | ~4590 | Overlay ASIM (EKS>TAH; **O20 tah=1,3,10,41**) | `98_TEST_asim_main_close.sql` — sadece PT close; güvence yerine geçmez |

`98_TEST_asim_*` DELTA_KALAN semptomunu temizler; mahsup/güvence gelir modeli bu not + E610 ile gelir.

## Canlı aktarım revizyon (2026-08-07)

Kod / dump tarafında yapılacaklar (test heal yerine):

1. **Mahsup fis gelir kırılımı** — Energy TYPE101 yanında INVLINES **162 + 1936** → O30 `LS_OV_TAH_INVLINES` + 597 TAH_IL (**DONE 2026-08-11**).
2. **O30 / 597** — `LS_OV_MAHSUP_CLOSED` ile borç PT doğru `PAID`; mahsup over-close ile CANCEL_REV karıştırma (`NOTES_597_V5…`).
3. **O60 + E610** — kalan güvence iade TYPE110 (`GUVENCE_IADE_110_RULE.md`); dump atlanırsa TYPE110=0.
4. **O20 ASIM** — gecikmeli eksilten sahte ASIM → `tah.tut` IN (1,3,10,41) (**DONE 2026-08-11**).
5. `LS_EMANET` Energy INSERT hâlâ yok (`EXIT_MAP`) — bilinçli gap; mahsup borcu TYPE101/597 ile kapanır.

Tek checklist: `prodEnergy/prodREADY_ENERGY/NOTES_CANLI_AKTARIM_REV_20260807.md`
