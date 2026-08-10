# prodREADY_ENERGY3007 — izgazMGR → Energy EXIT MAP

CTAS3007 dump → izgazMGR → energy çıkış envanteri.

**3007 durumu:** `EVET` = bu paket RUN_ORDER’ında · `ÖNKOŞUL` = cutover öncesi yüklenmiş olmalı (bu pakette EXEC yok) · `YOK` = Energy INSERT SP yok · `DIAG` = doğrulama/FRK, domain tablo yüklemez

SP gövdeleri: [`../ProdIzgazMgr2Energy/prodENERGY/`](../../ProdIzgazMgr2Energy/prodENERGY/) · Overlay: [`../prodREADY_ENERGY/`](../prodREADY_ENERGY/) · Dump: [`../../oracleCTAS3007/DUMP_MANIFEST.txt`](../../oracleCTAS3007/DUMP_MANIFEST.txt)

```text
CTAS dump → 00b/00c/IX → gate/collation
  → master/REF/AGR (ÖNKOŞUL)
  → READING/HHD 521/524 (ÖNKOŞUL)
  → MAP → 571 → 581 → 575 → 590 → 597(v5) → E610 → 35 → 611/613 → 40 → 92
  → VALIDATE 95/99/97 → 90
```
Hizalama: [`../PAKET_PATCH_HIZALAMA.md`](../PAKET_PATCH_HIZALAMA.md)

---

## 0) Dump sonrası prep

| Adım | SP / script | izgazMGR kaynak | energy hedef | 3007 |
|------|-------------|-----------------|--------------|------|
| 00a | `00a_dump_transfer_audit.sql` | Manifest + IX + TAH kalite | — (audit) | EVET |
| 00ix | `00_ix_online_safe.sql` | ONLINE IX (BULK tablo atla) | — (IX) | EVET |
| IX | `prodEnergy/00_pre_indexes.sql` (+520 setup) | OV / READING join kolonları | — (IX) | ÖNKOŞUL |
| 00b | `prodREADY_ENERGY/00b_align_mgr_varchar.sql` | `LS_OV_*` nvarchar join kolonları | — (ALTER mgr) | EVET |
| 00c | `prodREADY_ENERGY/00c_enrich_mgr_kismi_lineexp.sql` | `LS_OV_KISMI_INVLINES` + `LS_INCOME_PRM` | UPDATE mgr KISMI LINEEXP | EVET |
| 00 | `00_izgazmgr_gate_checkpoint.sql` | Manifest tablolar | — (gate) | EVET |
| 01 | `01_PILOT_SPOT.md` | Pilot AGR | Wizard spot | EVET |
| 05 | `05_collation_cp1254.sql` | — | energy DB CP1254 | EVET |
| 05b | `05b_columns_cp1254.sql` | — | energy kolon CP1254 | EVET |
| 05c | `05c_izgazmgr_collation_cp1254.sql` | izgazMGR | mgr DB/kolon CP1254 | EVET |

---

## 1) Önkoşul — REF / MASTER / AGR

Path: `ProdIzgazMgr2Energy/prodENERGY/`. 3007 cutover’dan **önce** dolu olmalı.

| Adım | SP / script | izgazMGR kaynak | energy hedef | 3007 |
|------|-------------|-----------------|--------------|------|
| 111 | `SP_MIGRATE_IT_USER` · `111_REF_IT_USER__migrate.sql` | `IT_USER` / `LS_IT_USER` | `LS_USER` | ÖNKOŞUL |
| 121 | `121_REF_BANK__migrate.sql` (+ `FN_MIG_RESOLVE_BANK_LREF`) | SMS bank eşlemesi | `LS_BANK.ABYS_ID` | ÖNKOŞUL |
| 131 | `SP_MIGRATE_LS_TARIFF` · `131_REF_TARIFF__migrate.sql` | tariff PRM | `LS_TARIFF_*_PRM` | ÖNKOŞUL |
| 141 | `SP_MIGRATE_LS005_FUID` · `141_REF_FUID__migrate.sql` | `LS_KFACTOR_VALUE` | `LS_005_FUID` | ÖNKOŞUL |
| 201 | `SP_MIGRATE_CS_REGISTER` · `201_MASTER_SUBSCR__migrate.sql` | `CS_REGISTER` / `LS_REGISTER` | `LS_005_SUBSCR`, `LS_005_FIRM` | ÖNKOŞUL |
| 211 | `SP_MIGRATE_CS_REGISTER_COMMUNICATION` | `CS_REGISTER_COMMUNICATION` | `LS_005_SUBSCRIBER_COMMUNICATION` | ÖNKOŞUL |
| 213 | `SP_MIGRATE_CS_REGISTER_COMM_PERMISSION` | `CS_REGISTER_COMM_PERMISSION` | `LS_005_SUBSCRIBER_COMMUNICATION_PERMISSION` | ÖNKOŞUL |
| 221 | `SP_MIGRATE_GIS_BUILDING_FLAT` · `221_MASTER_GIS_FLAT__migrate.sql` | `LS_FLAT` | `LS_FLAT` | ÖNKOŞUL |
| 241 | `SP_MIGRATE_LS005_ITEMS` · `241_MASTER_ITEMS__migrate.sql` | `LS_ITEMS` | `LS_005_ITEMS` | ÖNKOŞUL |
| 301/302 | `SP_MIGRATE_LS005_AGR` / `_BULK` | `LS_AGREEMENT` | `LS_005_01_AGR` | ÖNKOŞUL |
| 311 | `SP_MIGRATE_LS005_DEPOSIT_GUARANTY` | `LS_AGR_GUARANTY` | `LS_005_01_AGR_GUARANTY` | ÖNKOŞUL |
| 321 | `SP_MIGRATE_LS_AGR_CLOSE` | `LS_AGR_CLOSE` | `LS_005_01_AGR_CLOSE` | ÖNKOŞUL |
| 331 | `SP_MIGRATE_LS005_AGR_DEV` | `LS_AGR_DEVICE` | `LS_005_01_AGR_DEV_TR` | ÖNKOŞUL |
| 341 | `SP_MIGRATE_LS005_AGR_SERVEQ` | `LS_AGR_SERVQ` | `LS_005_01_AGR_SERVEQ_TR` | ÖNKOŞUL |
| 351 | `SP_MIGRATE_LS005_AGR_FITMENTFEE` | `LS_FITMENT_FEE` | `LS_005_01_AGR_FITMENTFEE_TR` | ÖNKOŞUL |
| 361 | `SP_MIGRATE_LS_BNK_TALIMAT` | `CS_AGREEMENT_AUTO_PAYMENT_LOG` / `LS_AGREEMENT_AUTO_PAYMENT_LOG` | `LS_BNK_TALIMAT` | ÖNKOŞUL |
| 365 | `SP_MIGRATE_LS_BNK_MUTABAKAT_DETAY` | `LS_BANK_CONFIRM` | `LS_BNK_MUTABAKAT_DETAY` | ÖNKOŞUL |
| 585 | `SP_MIGRATE_LS_SPEFEE` · `585_SPEFEE__migrate.sql` | `LS_SPEFEE` (+ `LS_SPEFEE_ADD`) | `LS_005_01_SPEFEE` | ÖNKOŞUL |

---

## 2) Önkoşul — Okuma / HHD / WO / COMM

Dump manifest 521/524 çağırır; 3007 RUN_ORDER bunları EXEC etmez.

| Adım | SP / script | izgazMGR kaynak | energy hedef | 3007 |
|------|-------------|-----------------|--------------|------|
| 501 | `SP_MIGRATE_CS_READING_PLAN_OKUMA_BOLGE` | `CS_READING_PLAN` | `mgg_cbs_okuma_bolge` | ÖNKOŞUL |
| 511 | `SP_MIGRATE_LS005_READING_INCOME` | `CS_READING_INCOME` | `LS_005_ReadingIncome` | ÖNKOŞUL |
| 521 | `SP_MIGRATE_LS005_HHD_LOC_INV_TRAN` · `521_READ_HHD_LOC_INV_TRAN__migrate.sql` | `LS_READING` | `LS_005_01_hhd_loc_inv_tran` | ÖNKOŞUL |
| 524 | `SP_MIGRATE_LS005_HHD_MSTR` · `524_READ_HHD_MSTR__apply.sql` | `LS_OV_HHD_MSTR`, `LS_OV_HHD_TRAN_MAP` | `LS_005_01_hhd_to_hhd_mstr` + TRAN `read_no` | ÖNKOŞUL |
| 530 | `SP_MIGRATE_LS005_READINGDATA` | `LS_READING` | reading-data | ÖNKOŞUL |
| 531 | `SP_MIGRATE_LS005_CS_APPOINTMENT` | `LS_WORK` | `LS_005_01_CS_APPOINTMENT` | ÖNKOŞUL |
| 533 | `SP_MIGRATE_LS005_II_APPOINTMENT` | `II_APPOINTMENT` | `LS_005_01_APPOINTMENT` | ÖNKOŞUL |
| 535 | `SP_MIGRATE_LS005_II_APPOINTMENT_DEVICE` | `II_APPOINTMENT_DEVICE` | `LS_005_01_APPOINTMENT_DEVICE` | ÖNKOŞUL |
| 541 | `SP_MIGRATE_LS005_WO_WORK_RESULT` | `WO_WORK_RESULT` / `LS_WORK_RESULT` | `LS_005_01_WO_WORK_RESULT` | ÖNKOŞUL |
| 551 | `SP_MIGRATE_LS_COMMUNICATION_LOG` | `IT_COMMUNICATION_LOG` | `LS_COMMUNICATION_LOG` | ÖNKOŞUL |
| 561 | `SP_MIGRATE_LS_OPR_SYNC_CLIENT` | `OPR_SYNC_CLIENT` | `LS_OPR_SYNC_CLIENT` | ÖNKOŞUL |

---

## 3) 3007 cutover — MAP / ana yükleme / overlay / post

| Adım | SP / script | izgazMGR kaynak | energy hedef | 3007 |
|------|-------------|-----------------|--------------|------|
| 10a | `prodREADY_ENERGY/00_log_setup.sql` | — | `MIG_STEP_LOG` | EVET |
| 10b | `prodREADY_ENERGY/00_map_tables.sql` | — | `MIG_OV_ID_MAP` mirror | EVET |
| 10c | `10_setup_and_map.sql` | `LS_OV_ID_MAP` | `MIG_OV_ID_MAP` | EVET |
| 10d | `prodREADY_ENERGY/00_abys_columns.sql` | — | energy ABYS kolonları | EVET |
| 10e | `prodREADY_ENERGY/01_linenr_smallint.sql` | — | INVLINES LINENR | EVET |
| 571 | `SP_MIGRATE_LS005_INVOICE` · `20_main_load…` | `LS_INVOICE` | `LS_005_01_INVOICE` | EVET |
| 581 | `SP_MIGRATE_LS005_INVLINES` | `LS_INVLINES` | `LS_005_01_INVLINES` | EVET |
| 575 | `SP_MIGRATE_LS005_DEBT_PAYTRANS` | energy INV IOCODE=0 (mgr `LS_DEBT_PAYTRANS` enrich) | `LS_005_01_PAYTRANS` (borç) | EVET |
| 590 | `SP_MIG_590_ALL` · `30_overlay…` (deploy 10→19) | `LS_OV_IADE_*`, `LS_OV_KISMI_*`, `LS_OV_MAIN_UPD`, MAP | INSERT INV/IL; UPDATE MAIN; PT | EVET |
| 610 | `SP_MIG_GUVENCE_IADE_ALL` · deploy 60→69 | `LS_OV_GUVENCE_IADE_*` (O60), MAP GUV_IADE* | TYPE110 INV/IL/PT | EVET |
| 597 | `SP_MIG_597_ALL` · `30_overlay…` (**28_DEPLOY_597 v5**) | `LS_OV_TAH_INVOICE`, `LS_OV_PAY_PT`, `LS_OV_CANCEL_*`, `LS_OV_DEBT_PAID_UPD`, `LS_OV_MAHSUP_CLOSED` | TAH INV + pay PT; CLOSED/LPD/CROSSREF; CANCEL_REV AFL-gate | EVET |
| 35 | `35_bankref_resolve_abys.sql` | INV / DEBT_PT / PAY_PT BANKREF | UPDATE energy `BANKREF` → `LS_BANK.LREF` | EVET |
| 611 | `SP_MIGRATE_LS005_INSTALLMENT_PLAN` (+ wire) · `50_…` | `CS_INSTALLMENT_PLAN`, `CS_INSTALLMENT` | `LS_005_01_INSTALLMENT_PLAN` | EVET |
| 613 | installment split SP’ler · `50_…` / `80_613…` | `CS_INSTALLMENT` + energy plan/PT | debt PT split | EVET (partial) |
| 40 | `40_installment_plan_pay_apply.sql` | `LS_INSTALLMENT_PLAN_PAY` | UPDATE PT/INV PAID/banka/CLOSED | EVET |
| 92 | `90_afl_frk/92_stg_inv_pay_close_apply.sql` | `LS_STG_INV_PAY_CLOSE` | UPDATE INV/PT | EVET |
| V95 | `90_afl_frk/95_ttk_inv_afl_fatura_rapor.sql` | INV/PT/AFL | — (validate) | EVET |
| V97 | `90_afl_frk/97_agr_frk_all.sql` | FRK özet SP | `MIG_AGR_FRK_ALL` | EVET |
| V99 | `90_afl_frk/99_afl_vs_en_kalan_frk.sql` | AFL vs PT kalan | — (validate) | EVET |
| 90 | `90_check_queries.sql` | çeşitli | — (read) | EVET |

**Hizalama:** [`../PAKET_PATCH_HIZALAMA.md`](../PAKET_PATCH_HIZALAMA.md) — PAKET vs PATCH vs AÇIK KOD.  
**Patch (3007 EXEC yok):** `hotfix/03–04`, `91*`, `22b`, `98_TEST_*` — `patch/README.md`.  
**Açık kod (heal yok):** `NOTES_CANLI_AKTARIM_REV_20260807` O20 ASIM · TAM MAIN · mahsup IL.

### Diğer INV / LEGAL / INSTALLMENT (paket dışı)

| Adım | SP / script | izgazMGR kaynak | energy hedef | 3007 |
|------|-------------|-----------------|--------------|------|
| 591 | `SP_MIGRATE_LS005_PROJECT` | `LS_PROJECT` | `LS_005_01_PROJECT` | ÖNKOŞUL |
| 595 | `SP_MIGRATE_LS005_PROJECTLINE` | `LS_PROJECTLINE` | `LS_005_01_PROJECTLINE` | ÖNKOŞUL |
| 601 | `SP_MIGRATE_LP` | `LP_*` | LP expense/status/invoice | ÖNKOŞUL |
| 614 | `SP_MIGRATE_LS_INSTALLMENT_TYPE` | `CS_INSTALLMENT_TYPE_PRM` | `LS_INSTALLMENT_TYPE` | ÖNKOŞUL |
| 616 | `SP_MIGRATE_LS005_INSTALLMENT_INCOME` | `CS_INSTALLMENT_INCOME` | `LS_005_01_INSTALLMENT_INCOME` | ÖNKOŞUL |
| 96 | `90_afl_frk/96_agr5727_ttk_vs_inv.sql` | spot AGR | — (diag) | DIAG |

---

## 4) Dump var / Energy INSERT yok (bilinçli)

| Tablo | Tüketici | Gerekçe | 3007 |
|-------|----------|---------|------|
| `LS_DEBT_PAYTRANS` | 575 alternatif / 597+35 enrich | Canlı INSERT yolu energy INV’den 575; O14 ile çift yazma yasak | DIAG |
| `LS_PAYMENT` | senaryo / wizard / IX | Domain `LS_005_*` INSERT SP yok | YOK |
| `LS_EKSILTEN` / `LS_PARTIAL_EKSILTEN` | O53 family | Energy yolu **590 OV** | YOK |
| `LS_ARTIRAN` / `LS_EMANET` | O54 | Energy INSERT SP yok | YOK |
| `LS_MAHSUP` | O55 | Kapama **597** `LS_OV_MAHSUP_CLOSED` | YOK |
| `LS_TAKSIT` | O56 / FRK | Energy INSERT SP yok | DIAG |
| `LS_OV_PAY_ALLOC` | O30 / gate | Overlay ara; Energy tablo yükü yok | DIAG |
| `LS_OV_EKS_CLASS` / `LS_OV_EKS_SKIP` | O20 | 590 sınıflama staging | DIAG |
| `LS_OV_INV_PAY_GAP` / `LS_OV_TAH_LOG` | diag | Energy yüklemez | DIAG |
| `LS_AFL_OPEN_DEBT` | FRK (`91_*` / 50 soft) | Soft check; Energy INSERT yok | DIAG |
| `LS_MIG_AGR_LIST` | Energy LOOP | Helper liste | DIAG |
| `STG_INV_ACC_INC` | Oracle O10–O14 | Dump opsiyonel | YOK |
| `LS_KFACTOR_VALUE` | CTAS master | `SP_MIGRATE*` yok (seed `04_KFACTOR`) | YOK |
| `LS_ADJUSTMENT_COEFFICIENT` | CTAS | Energy migrate yok | YOK |
| `LS_OV_HHD_MSTR_SKIP` | GATE diag | Opsiyonel | DIAG |

---

## Kurallar

1. Gate FAIL / Pilot FAIL → ENERGY yok.
2. Overlay yalnız `SP_MIG_590_ALL` / `SP_MIG_597_ALL` — tek INSERT yasak.
3. **575 + Oracle O14** aynı anda yazılmaz.
4. String join: dump sonrası `00b` → bare join; `COLLATE` / query-time CAST yasak (workspace kuralı).
5. Master + 521/524 dolmadan 571 full cutover başlatma.
6. `@AGR_ID`: NULL=FULL | >0=AGR | -1=NO_AGR — FULL yasağı kalkmıştır (NO_AGR ayrica 30b).

Operatör sırası: [RUN_ORDER.sql](RUN_ORDER.sql) · Checkbox: [MANUAL_CHECKLIST.txt](MANUAL_CHECKLIST.txt) · Index: [INDEX.md](INDEX.md)
