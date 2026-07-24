

# IZGAZ ABYS → PCMS Tahsilat Mapping Dokumani

> **Amac:** `LS_001_01_INVOICE`, `LS_001_01_INVLINES`, `LS_001_01_PAYTRANS`, `LS_001_01_PAYTRANS_INCOME` tablolarinin uc katmanli migrasyon pipeline'inda kolon mapping'ini tanimlamak.
>
> **Durum:** Taslak — energy hedef sema dump'i tamamlandiginda Katman 3 kolonlari kesinlestirilecek.
>
> **Referans:** Oracle pilot script (REVIZE 3), mimari kararlar K1–K13, repodaki `23_ls_tariff_setup.sql` / `17_ls005_deposit_guaranty_setup.sql` pattern'leri.

---

## 1. Migrasyon Pipeline (Uc Katman)

```
SMS (Oracle kaynak — ham veri, read-only)
    |
    v  Siniflandirma, mahsup eslestirme, istisna kuyrugu, 4.1–4.6 kontroller
SMS_AUDIT (Oracle staging)          ← ONCE BURADA HAZIRLANIR
    |
    v  BCP / SSIS / linked server (yontem secilecek)
izgazMGR (MSSQL ara staging)         ← Transform edilmis veri (ham mirror degil)
    |
    v  VW_MIG_* + SP (repo pattern)
energy (PCMS hedef)
```

### Katman sorumluluklari

| Katman | Rol | Yapilir | Yapilmaz |
|---|---|---|---|
| **SMS** | Ham kaynak | Okuma | Transform |
| **SMS_AUDIT** | Oracle transform | Routing, mahsup FK/RECEIPT_GUNLUK, stage uretimi, kontroller | PCMS kolonlarina tam map |
| **izgazMGR** | MSSQL kopru | Oracle stage → MSSQL tip donusumu, batch yukleme, kopru key | Is mantigi tekrari |
| **energy** | PCMS hedef | Identity resolution, FK wiring, PAID/CLOSED (Faz 6) | Allocation yeniden hesaplama (FIFO yok — K2) |

> **User ID kurali:** Canli user FK kolonlari (`ADDUSER` / `UPDUSER` / `CREATED_USER_ID` / `UPDATED_USER_ID` vb.) insert aninda `FN_MIG_MAP_USER_USERID` ile yazilir: `PCMS_USERID = ABYS_USER_ID + 10000`. `LS_USER.USERID` ayni offset ile uretilir. Post-UPDATE user remap yok. `ABYS_*_USER_ID` audit kolonlari ham ABYS id kalir.

---

## 2. Kaynak Tablolar (Oracle SMS)

| Tablo | Rol |
|---|---|
| `CS_REGISTER` | Sicil (musteri) |
| `CS_ACCOUNT` | Hesap karti (donem/fatura; `EXPIRY_DATE` = son odeme tarihi) |
| `CS_ACCOUNT_ACTION` | Hareket (tahakkuk, tahsilat, emanet giris/cikis…) |
| `CS_ACCOUNT_INCOME` | Hareket gelir kirilimi (1 action → N income) |
| `CS_ACTION_TYPE_PRM` (+ `_LNG`) | Islem tipi katalogu (`TYPE`, `STATUS` kritik) |
| `CS_INCOME_PRM` (+ `_LNG`) | Gelir kodu katalogu |

---

## 3. Hedef Tablolar (MSSQL energy)

| Tablo | Rol |
|---|---|
| `LS_001_01_INVOICE` | Fatura baslik |
| `LS_001_01_INVLINES` | Fatura satir (gelir kirilimi) |
| `LS_001_01_PAYTRANS` | Tahsilat baslik |
| `LS_001_01_PAYTRANS_INCOME` | Tahsilat–fatura eslesme koprusu (allocation) |

> **Not:** `LS_001_01` = bolge kodu (IZGAZ region 001 — dogrulanacak).

---

## 4. Staging Tablo Eslemesi (Katman 1 → Katman 2)

| Oracle `SMS_AUDIT` | izgazMGR staging (onerilen) | energy hedef |
|---|---|---|
| `MIG_INVOICE_STAGE` | `LS_001_INVOICE_STAGING` | `LS_001_01_INVOICE` |
| `MIG_INVLINES_STAGE` | `LS_001_INVLINES_STAGING` | `LS_001_01_INVLINES` |
| `MIG_PAYTRANS_STAGE` + `MIG_MAHSUP_TARGET_STAGE` | `LS_001_PAYTRANS_STAGING` | `LS_001_01_PAYTRANS` |
| *(henuz Oracle'da yok)* | `LS_001_PAYTRANS_INCOME_STAGING` | `LS_001_01_PAYTRANS_INCOME` |
| `MIG_EXCEPTION_QUEUE` | `LS_001_MIG_EXCEPTION` | — (is birimi kuyrugu) |

**Birlestirme notu:** `MIG_PAYTRANS_STAGE` ve `MIG_MAHSUP_TARGET_STAGE`, izgazMGR'de tek `LS_001_PAYTRANS_STAGING` tablosunda birlestirilebilir; `PAYTYPE_HEDEF = 'MAHSUP'` ile ayrilir.

### SMS_AUDIT pilot tablolari (referans)

| Tablo | Aciklama |
|---|---|
| `PILOT_REGISTER`, `PILOT_ACCOUNT`, `PILOT_ACCOUNT_ACTION`, `PILOT_ACCOUNT_INCOME` | Sicil kapsami extraction |
| `PILOT_EXT_*` | Sicil disi FK referanslari |
| `REF_ACTION_TYPE`, `REF_INCOME` | Lookup kopyalari |
| `MIG_ACTION_CLASSIFICATION` | Routing + mahsup eslestirme sonucu |
| `MIG_INVOICE_STAGE`, `MIG_INVLINES_STAGE`, `MIG_PAYTRANS_STAGE`, `MIG_MAHSUP_TARGET_STAGE`, `MIG_ADVANCE_LEDGER_STAGE` | Hedef satir staging |
| `MIG_EXCEPTION_QUEUE` | Otomatik migrate edilmeyen kayitlar |

---

## 5. Routing Kurallari (Degistirilemez — K3, K4)

Routing **yalnizca** `CS_ACTION_TYPE_PRM.TYPE` + spesifik `ACTION_TYPE_ID` listelerine gore yapilir. `IS_DEPOSIT` routing'de **kullanilmaz**.

| ATP.TYPE | Anlam | ACTION_TYPE_ID ornekleri | Hedef yapi |
|---|---|---|---|
| 1 | ACCRUE (tahakkuk) | 1, 10 | `INVOICE` |
| 2 | PAYMENT (tahsilat) | 4, 5, … | `PAYTRANS_ONLY` |
| 2 (istisna) | ALACAKLANDIRMA | **36, 37, 39, 44** | `ADVANCE_LEDGER` CREDIT — **PAYTRANS degil** |
| 3 | DISCHARGE | 29 | `ADVANCE_LEDGER` DEBIT |
| 4 | CANCEL_PAYMENT | 9 | `CANCEL_MARK` (henuz tasarlanmadi) |
| 5 | DELAYED_FROZEN | gecikme | `INVOICE` |
| 6 | CUSTODY | 20, 48, 49 | `ADVANCE_LEDGER` |
| 7 | CANCEL_CUSTODY | 12 | `ADVANCE_LEDGER` |
| 8 | CANCEL_DISCHARGE | 25 | `ADVANCE_LEDGER` |
| — | MAHSUP/MAHSUBEN | **6, 24** | `PAYTRANS_INCOME_TARGET` |

### Bu dort tabloya giren routing filtreleri

| Hedef tablo | Filtre |
|---|---|
| `INVOICE` | `HEDEF_YAPI = 'INVOICE'` → `ATP.TYPE IN (1, 5)` |
| `INVLINES` | Parent action → INVOICE olan `CS_ACCOUNT_INCOME` satirlari |
| `PAYTRANS` | `HEDEF_YAPI = 'PAYTRANS_ONLY'` → `ATP.TYPE = 2` **ve** `ACTION_TYPE_ID NOT IN (36,37,39,44,6,24)` |
| `PAYTRANS_INCOME` | Turetilmis allocation — Oracle'da dogrudan 1:1 tablo yok |

---

## 6. Kopru Anahtarlari (Tum Katmanlarda Sabit)

| Anahtar | Kaynak | Kullanim |
|---|---|---|
| `ABYS_ACTION_ID` / `OLD_REF` | `CS_ACCOUNT_ACTION.ID` | INVOICE ve PAYTRANS kok anahtari |
| `ABYS_ACCOUNT_ID` | `CS_ACCOUNT.ID` | Hesap karti |
| `ABYS_REGISTER_ID` | `CS_REGISTER.ID` | Sicil / batch filtreleme |
| `OLD_INVOICE_REF` | Parent action ID | INVLINES → INVOICE FK wiring |
| `OLD_TARGET_ACTION_ID` | Mahsup hedef action ID | PAYTRANS_INCOME allocation |
| `MIG_BATCH_ID` / `MIGRASYON_ETIKETI` | Batch etiketi | Izlenebilirlik |

### energy tarafi identity stratejisi (K10)

- `LREF` = MSSQL IDENTITY — Oracle'da uretilmez
- `ABYS_ID = ABYS_ACTION_ID` — repodaki `23_ls_tariff`, `27_lp_*` standardi
- FK wiring insert sonrasi `OUTPUT` clause + kopru esleme tablosu ile yapilir
- `smalldatetime` hassasiyet kaybina karsi Oracle ID tie-break olarak bridge'de saklanir

---

## 7. Kolon Mapping — LS_001_01_INVOICE

### Katman 1: Oracle `MIG_INVOICE_STAGE`

| Stage kolonu | Kaynak | Donusum |
|---|---|---|
| `OLD_REF` | `aa.ID` | `CS_ACCOUNT_ACTION.ID` |
| `IOCODE` | sabit `0` | Tahakkuk fisi |
| `FICHENO` | `NULL` | Pilot NULL — PCMS zorunlulugu kontrol edilecek |
| `DATE_` | `aa.ACTION_DATE` | |
| `DUEDATE` | `acc.EXPIRY_DATE` | `CS_ACCOUNT` join |
| `TYPE_REF` | `atp.BILL_TYPE_ID` | `CS_ACTION_TYPE_PRM` |
| `OLD_ACCOUNT_ID` | `aa.ACCOUNT_ID` | |
| `GRANDTOTAL` | `cls.ACTION_TOPLAM` | `SUM(ai.AMOUNT * ai.STATUS)` — isaretli |
| `MIGRASYON_ETIKETI` | `'PILOT-{sicil}'` | Batch etiketi |

### Katman 2 → 3: izgazMGR → energy (taslak)

| energy kolonu (beklenen) | izgazMGR staging | Not |
|---|---|---|
| `LREF` | — | IDENTITY; insert sonrasi |
| `ABYS_ID` | `OLD_REF` | Unique filtered index |
| `IOCODE` | `IOCODE` | |
| `DATE_` | `DATE_` | `FN_SAFE_SMALLDT_*` |
| `DUEDATE` | `DUEDATE` | |
| `TYPE` / `TYPE_REF` | `TYPE_REF` | Lookup dogrulama |
| `GRANDTOTAL` | `GRANDTOTAL` | `FN_MIG_FIT_NUMERIC` |
| `FICHENO` | `FICHENO` | |
| `CLOSED` / `PAID` | — | **Faz 6 — hesaplanir**, Oracle'dan kopyalanmaz (K13) |
| Agreement / sicil FK | `OLD_ACCOUNT_ID` → lookup | Hedef semaya bagli — **TBD** |

---

## 8. Kolon Mapping — LS_001_01_INVLINES

### Katman 1: Oracle `MIG_INVLINES_STAGE`

| Stage kolonu | Kaynak | Donusum |
|---|---|---|
| `OLD_INVOICE_REF` | `ai.ACCOUNT_ACTION_ID` | Parent INVOICE action |
| `LINENR` | `ROW_NUMBER()` | `PARTITION BY action ORDER BY ACCRUE_GROUP_ID, ai.ID` |
| `GELIR_KODU` | `ip.CODE` | `CS_INCOME_PRM` |
| `OLD_INCOME_ID` | `ip.ID` | |
| `TLTOTAL` | `ai.AMOUNT * ai.STATUS` | Isaretli tutar |
| `IS_DEPOSIT` | `ip.IS_DEPOSIT` | Bilgi amacli — routing'de kullanilmaz (K3) |
| `INCOME_EXPENSE` | `ip.INCOME_EXPENSE` | |
| `GELIR_ADI` | lookup | |

### Katman 2 → 3: izgazMGR → energy (taslak)

| energy kolonu (beklenen) | izgazMGR staging | Not |
|---|---|---|
| `LREF` | — | IDENTITY |
| `INVOICEREF` | `OLD_INVOICE_REF` | 2. faz FK wiring → INVOICE.LREF |
| `LINENR` | `LINENR` | |
| Gelir tipi ref | `OLD_INCOME_ID` / `GELIR_KODU` | `LS_INCOME_PRM` ABYS koprusu |
| Tutar | `TLTOTAL` | |

---

## 9. Kolon Mapping — LS_001_01_PAYTRANS

### Katman 1: Oracle `MIG_PAYTRANS_STAGE` + `MIG_MAHSUP_TARGET_STAGE`

| Stage kolonu | Kaynak | Donusum |
|---|---|---|
| `OLD_REF` | `aa.ID` | |
| `IOCODE` | sabit `1` | Odeme fisi |
| `OLD_ACCOUNT_ID` | `aa.ACCOUNT_ID` | |
| `OLD_ACTION_TYPE_ID` | `aa.ACTION_TYPE_ID` | |
| `ORACLE_KANAL_KODU` | `atp.CODE` | |
| `DATE_` | `aa.ACTION_DATE` | |
| `TLTOTAL` | `ABS(ACTION_TOPLAM)` | D4: gosterim pozitif |
| `TLTOTAL_ISARETLI` | `ACTION_TOPLAM` | D4: isaretli deger ayri |
| `RECEIPT_SERIAL` | `aa.RECEIPT_SERIAL` | |
| `RECEIPT_NUMBER` | `aa.RECEIPT_NUMBER` | |
| `BANK_RECEIPT_NUMBER` | `aa.BANK_RECEIPT_NUMBER` | |
| `BANK_ID` | `aa.BANK_ID` | |
| `PAYTYPE_HEDEF` | `'MAHSUP'` | Sadece `MIG_MAHSUP_TARGET_STAGE` |

### Katman 2 → 3: izgazMGR → energy (taslak)

| energy kolonu (beklenen) | izgazMGR staging | Not |
|---|---|---|
| `LREF` | — | IDENTITY |
| `ABYS_ID` | `OLD_REF` | |
| `IOCODE` | `IOCODE` | |
| `DATE_` | `DATE_` | |
| `TLTOTAL` / `PAYED` | `TLTOTAL` | D4 mantigi |
| `PAYTYPE` | `ORACLE_KANAL_KODU` / lookup | Tip 6,24 → `MAHSUP` lookup'a eklenmeli |
| Receipt / bank kolonlari | staging'den 1:1 | |
| Iptal bayragi | — | Tip 9 zinciri — henuz tasarlanmadi |

### PAYTRANS'a gitmeyenler

- ALACAKLANDIRMA (36, 37, 39, 44) → `ADVANCE_LEDGER`
- MAHSUP (6, 24) → allocation tarafinda `PAYTRANS_INCOME` ile birlikte ele alinir

---

## 10. Kolon Mapping — LS_001_01_PAYTRANS_INCOME

> **Kritik:** Oracle cari modelinde allocation acik satir olarak yok; PCMS'de kopru tablosu. **Henuz Oracle stage tablosu tasarlanmadi.**

### Allocation kaynak tipleri

| Tip | Mantik | Pilot durumu |
|---|---|---|
| Dogrudan tahsilat → fatura | Ayni `CS_ACCOUNT` uzerinde odeme–tahakkuk eslesmesi | Pilot cogu 1:1; cok-faturali hesap acik |
| Mahsup zinciri | EMANET CIKISI (12,25,49) → MAHSUP (6,24) | `MIG_MAHSUP_TARGET_STAGE` + FK/RECEIPT_GUNLUK |
| As-is reconstruction | Uretim hesap karti sorgusu | FIFO **yok** (K2) |

### Onerilen staging kolonlari (Katman 1 + 2)

| Kolon | Kaynak | Not |
|---|---|---|
| `OLD_PAY_ACTION_ID` | Tahsilat/mahsup kaynak action | PAYTRANS koprusu |
| `OLD_INVOICE_ACTION_ID` | Hedef fatura action | INVOICE koprusu |
| `OLD_TARGET_ACTION_ID` | Mahsup hedef action | Emanet cikisi eslesmesi |
| `TLTOTAL` | Income satir tutari | Gelir bazli allocation mumkun |
| `OLD_INCOME_ID` | `CS_INCOME_PRM.ID` | Opsiyonel gelir kirilimi |
| `ESLESME_KATMANI` | FK / RECEIPT_GUNLUK / MANUEL | Mahsup eslestirme katmani |

### Katman 3: energy (taslak)

| energy kolonu (beklenen) | Wiring | Not |
|---|---|---|
| `PAYTRANSREF` | PAYTRANS.LREF | Identity resolution sonrasi |
| `INVOICEREF` | INVOICE.LREF | |
| Tutar kolonu | staging'den | |
| `ABYS_ID` | composite / satir ID | TBD |

---

## 11. Mahsup Eslestirme (PAYTRANS_INCOME ile iliskili — K7)

```
Kademe 1 — FK: REF_DEPOSIT_ACCOUNT_ACTION_ID dolu → dogrudan hedef
Kademe 2 — RECEIPT_GUNLUK: CASH_ID + RECEIPT_NUMBER + AYNI GUN (TRUNC)
           + ACTION_TYPE_ID IN (6,24) + TEK ADAY
Kademe 3 — Cozulemeyen → MIG_EXCEPTION_QUEUE (otomatik migrate edilmez)
```

**Terk edilen yontemler (K8):** ID±1/2/3 fallback, zaman+tutar penceresi.

---

## 12. Katman Bazinda Kontroller

| Kontrol | Oracle SMS_AUDIT | izgazMGR | energy |
|---|---|---|---|
| Satir sayisi | 4.1 | stage vs Oracle export count | hedef vs staging count |
| Kapsam (kayip action yok) | 4.2, 4.3 | `COUNT(*)` esitligi | orphan FK check |
| Mahsup tutar eslesmesi | 4.4 | ayni sorgu MSSQL'de | allocation sum check |
| ENTRY_TYPE dogrulama | 4.5 | — | — |
| Ledger denge | 4.6 | — | `V_ADVANCE_BALANCE` (ADVANCE_LEDGER ayri hat) |
| PAID / CLOSED | — | — | Faz 6 hesaplanir (tolerans 0.005) |

**Kural:** Oracle 4.1–4.6 FARK≠0 kapatilmadan izgazMGR'ye yukleme yapilmaz.

---

## 13. izgazMGR Staging Tasarim Notlari

Repodaki referans: `LS_005_DEPOSIT_STAGING` (`17_ls005_deposit_guaranty_setup.sql`)

Onerilen ortak kolonlar:

| Kolon | Aciklama |
|---|---|
| `_MIG_UID` | `INT IDENTITY` — yukleme sirasi |
| `MIG_ROW_ID` | Batch ici sira (gerekirse) |
| `MIG_BATCH_ID` / `MIGRASYON_ETIKETI` | Batch etiketi |
| `ABYS_ACTION_ID` | Oracle action koprusu |
| `ABYS_ACCOUNT_ID` | Hesap karti koprusu |
| `ABYS_REGISTER_ID` | Sicil koprusu |

Tip donusumleri:

| Oracle | MSSQL |
|---|---|
| `NUMBER(19,4)` | `DECIMAL(19,4)` |
| `DATE` / `TIMESTAMP` | `DATETIME2` → `FN_SAFE_SMALLDT_*` |
| `VARCHAR2` | `NVARCHAR` (uygun uzunluk) |

---

## 14. energy Repo Pattern (Katman 3)

Mevcut migrasyonlardaki sira (`23_ls_tariff`, `27_lp_*`, `17_ls005_*`):

1. **Setup** (`31_ls001_invoice_setup.sql`): `ABYS_ID` kopru kolonu, filtered unique index, kolon dogrulama SP
2. **Kaynak view** (`VW_MIG_LS001_INVOICE_SOURCE`): izgazMGR staging → energy donusum
3. **Migrate SP** (`32_sp_migrate_ls001_invoice.sql`): batch + `MIG_LOG` + bisect
4. **Restore FK** + **check queries**

---

## 15. Acik Isler / TBD

| # | Konu | Durum |
|---|---|---|
| 1 | energy hedef 4 tablo sema dump'i | **Bekleniyor** |
| 2 | `PAYTRANS_INCOME` Oracle stage tasarimi | Uretim hesap karti sorgusu gerekli |
| 3 | Oracle → izgazMGR aktarim yontemi | BCP / SSIS / linked server — secilecek |
| 4 | `PAYTYPE` lookup'a `MAHSUP` degeri | Faz 0 sema degisikligi |
| 5 | `CANCEL_MARK` (tip 9) uretimi | Iptalli sicil testi sonrasi |
| 6 | Cok-faturali hesap allocation | Acik tasarim |
| 7 | Agreement / sicil FK mapping | Hedef semaya bagli |
| 8 | Bolge kodu `LS_001_01` dogrulama | IZGAZ = 001? |

---

## 16. Calisma Sirasi (Mapping)

1. Oracle `MIG_*_STAGE` kolon listesini Katman 1 spec olarak kilitle
2. izgazMGR staging DDL taslagi (`LS_005_DEPOSIT_STAGING` pattern)
3. energy 4 tablo kolon envanteri (NOT NULL, FK, default)
4. **INVOICE + INVLINES** mapping kesinlestir
5. **PAYTRANS** + PAYTYPE lookup map
6. **PAYTRANS_INCOME** — uretim sorgusu ile allocation kurallari
7. Kopru stratejisi + identity resolution tablosu
8. Faz 6 hesaplanan kolonlari mapping disi birak, ayri bolumde dokumante et

---

## 17. Mimari Kararlar Ozeti (Bu Mapping Icin Gecerli)

| Karar | Kural |
|---|---|
| K2 | FIFO migrasyonda kosuturulmaz — as-is allocation |
| K3 | Routing yalnizca ACTION_TYPE — IS_DEPOSIT kullanilmaz |
| K10 | Bridge key: `OLD_REF = CS_ACCOUNT_ACTION.ID` |
| K12 | GRANDTOTAL=0 faturalar otomatik CLOSED isaretlenebilir |
| K13 | PAID/CLOSED Oracle'dan kopyalanmaz, hesaplanir |
| D4 | PAYTRANS TLTOTAL pozitif, isaretli deger ayri kolonda |

---

*Son guncelleme: 2026-07-05*
