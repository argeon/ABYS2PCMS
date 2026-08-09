90_afl_frk — AFL master vs energy FRK + STG kontrollu kapanis
             + TUKETIM_TUTAR_KONTROL (O59) vs energy FRK

Grain: ACCOUNT_ID / FATURAID = CS_ACCOUNT.ID = INVOICE.ABYS_ACCOUNT_ID
Master AFL : izgazMGR.LS_AFL_OPEN_DEBT (Oracle O50)
Master TTK : izgazMGR.TUKETIM_TUTAR_KONTROL (Oracle O59)
Energy TTK : energy.dbo.TUKETIM_TUTAR_KONTROL (93)
STG        : izgazMGR.LS_STG_INV_PAY_CLOSE (Oracle O51)

Sira — AFL / STG
----
1) Oracle: @50_ls_afl_open_debt.sql + @51_ls_stg_inv_pay_close.sql
2) Dump → izgazMGR.LS_AFL_OPEN_DEBT + LS_STG_INV_PAY_CLOSE
3) prodEnergy/00_pre_indexes.sql
4) 92_stg_inv_pay_close_apply.sql  (@DRY_RUN=1 sonra 0)
     CLOSE_FULL/EPS → PAYTRANS.PAID=PAYABLE + INVOICE.CLOSED/LPD
     AFL_OPEN / KEEP_OPEN / NO_PAY → dokunulmaz
5) 91_afl_frk_compare_log.sql
6) Incele: MIG_AFL_FRK_LOG + MIG_STG_CLOSE_LOG

KIND AFL: MATCH | AMT_DIFF | ONLY_AFL | ONLY_EN
@OnlyMig=1 → ACCRUE<>14 (MIG_IN_SCOPE)

Sira — TUKETIM_TUTAR (TTK)
----
Hizli SSMS (kalici tablo YOK):
  93b_tuketim_tutar_ssms.sql
  Kaynak: energy INV/INVLINES/PAYTRANS + energy.LS_AFL_OPEN_DEBT
  Cikti : #TTK + AFL_CHECK ozet

Kalici tablo yolu (opsiyonel):
1) Oracle: @59_tuketim_tutar_kontrol.sql
2) Dump → izgazMGR.TUKETIM_TUTAR_KONTROL
3) Energy 571/581/575 yuklu + LS_AFL_OPEN_DEBT energy'de
4) 93_tuketim_tutar_kontrol.sql  → energy.dbo.TUKETIM_TUTAR_KONTROL
5) 94_tuketim_tutar_frk.sql      → MIG_TTK_FRK_LOG


KIND TTK: MATCH | AMT_DIFF | ONLY_ORA | ONLY_EN
  birincil: KALAN (+ M3 eps)
@ExcludeEmanet=1 → ACCRUE_TYPE_ID <> 14

Sozlesme FRK ozeti (Energy INV vs TTK vs AFL)
----
6) 97_agr_frk_all.sql → energy.dbo.SP_AGR_FRK_ALL → MIG_AGR_FRK_ALL
     Seed: TYPE IN (119,121,86) GROUP BY OWNERREF (~977k)
     EXEC dbo.SP_AGR_FRK_ALL @Agr = NULL, @OnlyDiff = 0;  -- TRUNCATE+INSERT tablo
     EXEC dbo.SP_AGR_FRK_ALL @Agr = NULL, @OnlyDiff = 1;  -- sadece FRK
     EXEC dbo.SP_AGR_FRK_ALL @Agr = 197168, @ReturnResult = 1;  -- grid icin ReturnResult=1
     SELECT KIND_FRK, COUNT(*) FROM energy.dbo.MIG_AGR_FRK_ALL GROUP BY KIND_FRK;
     *_EKS = eksilten/IADE/ASIM hesap farki | *_NET = diger
     EN_IADE_SM3/KWH/CONSUMPTION = IADE fis tuketimi (borc EN_SM3 degil)
     ASIM_CNT / OV_ASIM_TUTAR | DELTA_KALAN_EKS/NET | DELTA_CONSUMPTION_*

CANLI AKTARIM REVIZYON NOTU (2026-08-07)
----
Tek liste (kod + checklist):
  prodREADY_ENERGY/NOTES_CANLI_AKTARIM_REV_20260807.md
  (+ CANCEL_REV: NOTES_597_V5_AFL_CANCEL_REV.md)
  Staging: EMANET_MAHSUP_RULE.md · GUVENCE_IADE_110_RULE.md
  Paket/patch ayrimi: ../PAKET_PATCH_HIZALAMA.md
  Hotfix envanter: ../HOTFIX_ANLIK_ENVANTER.md · ../patch/README.md

PAKET (cutover): 597 v5 · E610 60-69 · 92 STG · validate 95/97/99
PATCH (zincire koyma): hotfix/03-04 · 91* residual · 96 spot
TEST YASAK: 98_TEST_*
ACIK KOD (heal ile kapatma): asagidaki 1-3

Ozet — canlida yapilacak:
  1) TAM+TYPE92 → MAIN PT PAID=PAYABLE + CLOSED (590/597/STG; test: 98_TEST_tam)
  2) O20 ASIM: tah.tut'a gecikme dahil / EKS≈tah+gecikme → TAM (ornek 412056)
  3) Emanet mahsup: TYPE101 + INVLINES 162+1936 (guvence / fark)
  4) O60 dump + E610 EXEC TYPE110 (RUN_ORDER D2) — PAKET
  5) SP_AGR_FRK_ALL: KIND once NET; DELTA_KALAN_EKS/NET; ASIM ayri ACIKLAMA

FRK okuma (hizli):
  DELTA_TAH_EKS = overlay/IADE | DELTA_TAH_NET = gercek tah
  DELTA_KALAN(_EKS/_NET) = acik PT | EN_IADE/TYPE92 = TAM | OV KIND ASIM ≠ mahsup

DEV BACKLOG / test heal (2026-08-06..07)
----
Durum: SP_AGR_FRK_ALL *_NET ile tahakkuk/tuketim eksilten farkini ayirir;
       DELTA_KALAN canlida zincirle kapanmali — testte 98_TEST_*.

Belirti (TAM):
  - KIND_FRK=EKSILTEN_FRK, DELTA_TAH≈EN_IADE, DELTA_*_NET=0
  - DELTA_KALAN > 0: MAIN CLOSED=0; TYPE92 var; AFL=0
  Ornek: AGR=3 / ACC=28077306

Belirti (ASIM + emanet mahsup):
  - OV ASIM, TYPE92 yok, DELTA_TAH_NET≈EKS; mahsup 778.90 guvence 162/1936
  Ornek: AGR=412056 / ACC=42153632 (+ EMANET 42491917)

TEST ortam heal (manuel — canlida CALISTIRMA):
  98_TEST_tam_iade_main_close.sql  → MIG_TAM_IADE_CLOSE_LOG
  98_TEST_asim_main_close.sql      → MIG_ASIM_CLOSE_LOG
  98_tam_iade_main_pt_close_temp.sql — eski dar OV-only varyant

AFL vs Energy kalan FRK (SSMS):
  99_afl_vs_en_kalan_frk.sql
    AFL.BALANCE vs SUM(PT kalan) — PAYABLETOTAL kiyasi YANLIS (kismi tahsilat)

Energy esleme (93):
  M3/KWH/CONSUMPTION ← INV.ABYS_*
  GAZ/SKB/KDV/TOPLAM ← INVLINES ABYS_AMOUNT_RAW*ABYS_STATUS (939/7658/169)
  ODENEN             ← -SUM(borc PT.PAID)
  KALAN              ← TOPLAM + ODENEN
  NULL kolonlar     ← ACCRUE_TYPE_NAME, FIRST/LAST_INDEX,
                       CORRECTED_M3, CONSUMPTION_1/2/3
  AFL LEFT           ← AFL_HIT, AFL_BALANCE, AFL_TAKSIT, AFL_YT,
                       AFL_MIG_IN_SCOPE, DELTA_AFL_KALAN, AFL_CHECK
                       (MATCH|AMT_DIFF|NO_AFL; eps 0.02)
