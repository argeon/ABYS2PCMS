# CTAS — CALISTIRMA SIRASI (2026-08-11)

Tek giris: `00_RUN_ALL.SQL`
Ad: `NNN_NAME_Vnn.SQL` (BUYUK HARF)
FAIL → o NNN'den devam — bashtan RUNALL YASAK

| NNN | AD | V | RUN | Amac |
|-----|----|---|-----|------|
| 001 | DUMP_MANIFEST | V01 | - | Dump tablo listesi |
| 002 | INDEX | V01 | - | CTAS index |
| 003 | SCHEMA_CTAS_ORDER | V01 | - | Sema / sira aciklamasi |
| 004 | TABLE_CATALOG | V01 | - | Tablo katalogu |
| 010 | MIG_CTAS_LOG | V01 | Y | Adim log altyapisi |
| 011 | SESSION_PARALLEL | V01 | Y | Session DOP 56 (TEMP → 48) |
| 012 | MIG_PARAM_FULL | V01 | Y | FULL mod — AGR filtre kapali |
| 020 | LS_FLAT | V01 | Y | Bina/daire FLAT staging |
| 021 | LS_ITEMS | V01 | Y | Sayac envanteri |
| 022 | LS_REGISTER | V01 | Y | Abone/firma sicil |
| 023 | LS_IT_USER | V01 | Y | Kullanici staging |
| 024 | LS_AGREEMENT | V01 | Y | Sozlesme staging |
| 025 | LS_AGR_CLOSE | V01 | Y | Sozlesme kapatma |
| 026 | LS_AGR_GUARANTY | V01 | Y | Teminat/garanti (GTYPE39 TOTAL damgasiz) |
| 027 | LS_AGR_DEVICE | V01 | Y | Sozlesme cihaz |
| 028 | LS_AGR_SERVQ | V01 | Y | Servis ekipmani |
| 029 | LS_FITMENT_FEE | V01 | Y | Baglanti ucreti |
| 030 | LS_AGR_AUTO_PAYMENT_LOG | V01 | Y | Banka talimat log |
| 031 | LS_BANK_CONFIRM | V01 | Y | Banka mutabakat |
| 032 | LS_BANK_ACC | V01 | Y | Banka hesap |
| 033 | LS_INSTALLMENT | V01 | Y | Taksit baslik |
| 034 | LS_INSTALLMENT_PLAN | V01 | Y | Taksit satirlari |
| 035 | LS_WORK | V01 | Y | Is emri / randevu |
| 036 | LS_WORK_RESULT | V01 | Y | Is emri sonuc |
| 037 | LS_SPEFEE_ADD | V01 | Y | SPEFEE devir |
| 038 | LS_PROJECT | V01 | Y | Proje baslik (MIGRATION) |
| 039 | LS_PROJECTLINE | V01 | Y | Proje satirlari (MIGRATION) |
| 100 | MIG_ACCRUE_TYPE_MAP | V01 | Y | ACCRUE→TYPE map |
| 101 | LS_READING | V01 | Y | Sayac okuma |
| 102 | LS_READING_SYNTH | V01 | Y | Sentetik okuma gap |
| 103 | LS_HHD_MSTR | V01 | Y | HHD master + MAP |
| 104 | GATE_HHD_MSTR | V01 | Y | HHD gate |
| 105 | LS_KFACTOR_VALUE | V01 | Y | Isil deger / kromatograf |
| 106 | LS_ADJUSTMENT_COEFFICIENT | V01 | Y | Duzeltme katsayisi |
| 107 | LS_SPEFEE | V01 | Y | Ozel ucret |
| 130 | STG_INV_ACC_INC | V01 | Y | Fatura fee pivot (+TOTAL_DV; ACCRUE 5/6/21/341) |
| 131 | LS_INVOICE | V01 | Y | Ana fatura (DV=TOTAL_DV) |
| 132 | LS_INVLINES | V01 | Y | Fatura kalemleri (109/111 damga TL=0/DV) |
| 133 | LS_MIG_AGR_LIST | V01 | Y | Migrate AGR listesi |
| 134 | LS_DEBT_PAYTRANS | V01 | Y | Borc PT prefab |
| 135 | LS_EKSILTEN_OVERLAY | V01 | Y | Eksilten / iade overlay |
| 136 | GATE_EKSILTEN | V01 | Y | Eksilten hard gate |
| 137 | LS_TAHSILAT_OVERLAY | V01 | Y | Tahsilat overlay |
| 138 | LS_OV_DEBT_PAID_LASTPAID | V01 | Y | DEBT_PAID / LPD set |
| 139 | LS_OV_PAY_PT_BANK_ENRICH | V01 | Y | PAY_PT bank / PAID enrich |
| 140 | LS_INVOICE_CLOSE_BANK | V01 | Y | INV CLOSED/LPD/BANK patch |
| 141 | LS_DEBT_PAYTRANS_REBUILD | V01 | Y | Borc PT final rebuild |
| 142 | LS_OV_ID_MAP | V01 | Y | Overlay SRC_KEY map |
| 143 | GATE_TAHSILAT | V01 | Y | Tahsilat hard gate |
| 200 | LS_AFL_OPEN_DEBT | V01 | Y | AFL acik borc snapshot |
| 201 | LS_STG_INV_PAY_CLOSE | V01 | Y | STG kapama aday |
| 202 | LS_PAYMENT | V01 | Y | Makbuz grain tahsilat |
| 203 | LS_EKSILTEN_FAMILY | V01 | Y | Eksilten family tablolar |
| 204 | LS_ARTIRAN_EMANET | V01 | Y | Artiran + emanet |
| 205 | LS_MAHSUP | V01 | Y | Mahsup staging |
| 206 | LS_TAKSIT | V01 | Y | Taksit durum tablosu |
| 207 | LS_INSTALLMENT_PLAN_PAY | V01 | Y | Taksit plan odeme |
| 208 | GATE_PILOT_PARITY | V01 | Y | Parity / dump kapisi |
| 209 | TUKETIM_TUTAR_KONTROL | V01 | Y | TTK master (O59) |
| 210 | LS_OV_GUVENCE_IADE | V01 | Y | TYPE110 guvence iade overlay |
| 211 | LS_CUSTODY | V01 | Y | Custody staging |
| 250 | TRANSFER_INDEXES | V01 | Y | Dump oncesi join IX |
| 251 | LOG_STATUS | V01 | Y | MIG_CTAS_LOG ozet |
| 900 | MIG_PARAM_PILOT | V01 | - | Pilot AGR listesi |
| 901 | RUN_PILOT_OVERLAY | V01 | - | Pilot overlay orch |
| 902 | STG_CLEANUP | V01 | - | STG/TMP drop (opsiyonel) |
| 910 | HOTFIX_LS_OV_TAH_LOG | V01 | - | TAH log hotfix |
| 911 | LS_TAHSILAT_LOG | V01 | - | Tahsilat log |
| 912 | CHECK_QUERIES_ORACLE | V01 | - | Oracle check sorgulari |
| 913 | DESIGN_MAP | V01 | - | Tasarim map |
| 914 | MANUAL_CHECKLIST_ORACLE | V01 | - | Oracle checklist |
| 915 | README_PRODREADY | V01 | - | prodREADY README |
| 916 | SCENARIO_MAP | V01 | - | Senaryo map |
| 917 | DIAG_LINENR_GT_255 | V01 | - | LINENR>255 diag |
| 918 | DIAG_O11_CTAS_SMOKE | V01 | - | O11 smoke diag |
| 919 | DIAG_O11_PRECISION | V01 | - | O11 precision diag |
| 920 | LS_HHD_MSTR_DIAG | V01 | - | HHD diag |
| 921 | VERIFY_SYNTH_GAP | V01 | - | Synth gap verify |
| 922 | PILOT_FINDINGS | V01 | - | Pilot bulgulari |
| 923 | README_3007 | V01 | - | 3007 README |
| 924 | NOTES_CTAS_NO_RESTART | V01 | - | FAIL→resume; RUNALL bashtan YASAK |
| 925 | DIAG_DV_TYPE109 | V01 | - | Soft assert TYPE109/111 DV + damga satiri |

```text
cd ...\MIGRATION_SCR_20260708\CTAS
sqlplus user/pass@db @00_RUN_ALL.SQL
```

