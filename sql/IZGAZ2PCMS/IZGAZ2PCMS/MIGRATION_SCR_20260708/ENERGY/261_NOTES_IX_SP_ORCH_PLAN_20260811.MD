# Plan — İndeks sırası + SP-only aktarım (izgazMGR → Energy)

**Tarih:** 2026-08-11  
**Durum:** **P0+P1 DONE** (kod + sürücü). P2 `SP_MIG_CUTOVER_ALL` opsiyonel açık.  
**Amaç:** “İndeksli adımlar hızlı / indekssiz adımlar saatlerce” çelişkisini kapatmak; cutover’da **yalnız `EXEC SP_*`** (sql dosyası koşmama).

İlgili: `CUTOVER_ONE_PAGE.md` · `SSMS_TAHSILAT_EXECS.sql` · `RUN_ORDER.sql` · `NOTES_597_PERF_SAFE.md` · `EXIT_MAP.md`

---

## 1) Teşhis — neden çelişki? (tarihsel)

İndeks işi **parçalı** ve sürücüler **uyumsuzdu** (P0 öncesi):

| Yüzey | Ne yapıyordu | IX / POST |
|-------|------------|-----------|
| `SSMS_TAHSILAT_EXECS` | 571→**572**→…→20b→597→20c | Tam zincir |
| `RUN_ORDER` / `30c` | 571→581→575→590→597 | POST/NCIX eksik |
| `20b`/`20c` | NCIX off/on | dosya |

**Şimdi (P0+P1):** hepsi `571→572→581→582→575→576` + `SP_MIG_597_NCIX_*` + `SP_MIG_IX_*`.

**Kasıtlı disable (ölümden kaçış):** FULL 571/581/575 ve 597 öncesi NCIX OFF.  
**Zorunlu reopen:** her load sonrası POST; 597 sonrası **`SP_MIG_597_NCIX_REBUILD`**. Unutulursa sonraki tüm adımlar yavaş.

---

## 2) Hedef mimari (tek sıra)

```text
FAZ 0  SETUP SP          00_log / 00_map / 00_abys / 01_linenr  (deploy bir kez)
FAZ 1  MGR IX GATE       SP_MIG_IX_PRECHECK (hard FAIL) + SP_MIG_IX_MGR_ENSURE
                         (= 00b/00i/00d/00_pre/00f özü — yoksa CREATE)
FAZ 2  LOAD + POST       571→572 → 581→582 → 575→576   ★ POST atlanamaz
FAZ 3  OVERLAY           590_ALL
FAZ 4  597 NCIX          SP_MIG_597_NCIX_DISABLE (=20b)
                         → 597_ALL → GATE → probe
                         → (bad_map→20e SP) → SP_MIG_597_NCIX_REBUILD (=572+20c)
FAZ 5  POST              35 → 611 → SP_MIG_IX_IP_AGR (=00e energy) → 613
                         → 40 → 92 → (92 DV / 93 FEE) → validate
```

**Kural:** Operatör günü = yalnız `EXEC …`. `.sql` yalnız **deploy** (CREATE OR ALTER / ilk kurulum).

---

## 3) SP envanteri (yapılacak)

### 3a) Yeni / sarmalanacak

| SP | Kaynak dosya / davranış | Ne zaman |
|----|-------------------------|----------|
| `SP_MIG_IX_PRECHECK` | 00a + 30c gate birleşik | FAZ 1 başı — **FAIL = DUR** |
| `SP_MIG_IX_MGR_ENSURE` | 00_pre + 00d + 00i + 00f MGR kısmı | FAZ 1 — idempotent CREATE |
| `SP_MIG_597_NCIX_DISABLE` | 20b INV+PT → PREPARE_LOAD | FAZ 4 başı |
| `SP_MIG_597_NCIX_REBUILD` | 572 INV POST + 20c PT REBUILD | FAZ 4 sonu (probe=0) |
| `SP_MIG_IX_IP_AGR` | 00e_energy_installment_plan_indexes | **611 sonrası**, 613 öncesi |
| `SP_MIG_CUTOVER_ALL` (opsiyonel) | Tek orch `@Phase` / `@FromStep` | Canlıda adım adım veya FULL |

### 3b) Zaten SP (deploy bir kez, sonra EXEC)

| SP | Not |
|----|-----|
| 571 / 581 / 575 (+ PREPARE) | FULL’da NCIX disable içeride |
| 572 / 582 / 576 POST | **Zincire zorunlu** (şimdi RUN_ORDER’da eksik) |
| 590_ALL / 597_ALL / GATE | R17 probe ayrı veya ALL sonrası |
| `SP_MIG_35_BANKREF_RESOLVE` | R12 DONE |
| `SP_MIG_40_IPP_APPLY` | R12 DONE |
| `SP_MIG_92_STG_CLOSE` | R12 DONE |
| 611 / 613 | 50e orchestrator → SP veya `SP_MIG_613_RESUME` |

### 3c) Hard FAIL listesi (`SP_MIG_IX_PRECHECK`)

MGR (yoksa 571/581/597 ölür):

- `IX_MIG_LSINV_ACTION` (+ tercihen AGR_ACTION)
- `IX_MIG_LSINVLINES_LREF`, `IX_MIG_LSIL_INVREF`
- `UX_MIG_LS_OV_TAH_INVOICE_SRC` (00f — 597 hard)
- `UX_MIG_LS_PAYMENT_PAY_LREF`, TAH ABYS IX (00d)
- `LS_OV_ID_MAP` clustered/PK `SRC_KEY` (00i)

Energy (POST sonrası / 613 öncesi ayrı gate):

- INV/IL/PT NCIX **disabled = 0** (597 sonrası rebuild gate)
- `IX_MIG_LS005_IP_AGR` (613 P0)

---

## 4) Uygulama fazları

### P0 — Bugün / sonraki FULL öncesi (doküman + gate, az kod)

1. `RUN_ORDER` + `30c` + `CUTOVER_ONE_PAGE` + `EXIT_MAP` **hizala** → SSMS_TAHSILAT sırası = tek doğru.
2. B zincirine açık yaz: `571→572→581→582→575→576` (POST ★).
3. `00_pre_indexes` + `00ix` + `00i` + `00d` + `00f` → FAZ 1 checklist (PRINT + hard gate SQL bloğu).
4. 597 sonrası: **572 + 20c** zorunlu; “20c_INVOICE” pointer’ı kaldır → 572.
5. `00e` IP IX’i prep’ten çıkar; yalnız 611→613 arası.

**Kabul:** Yanlış sürücüyle koşulsa bile checklist’te POST/IX atlanamaz görünür.

### P1 — SP sarmalama (kod)

1. `SP_MIG_IX_PRECHECK` + `SP_MIG_IX_MGR_ENSURE` (00_pre/00d/00i/00f).
2. `SP_MIG_597_NCIX_DISABLE` / `SP_MIG_597_NCIX_REBUILD` (20b/20c+572).
3. `SP_MIG_IX_IP_AGR`.
4. `SSMS_TAHSILAT` / `SSMS_POST` / `SSMS_CUTOVER` → yalnız `EXEC` (dosya pointer yok).
5. `10f` STATUS listesine yeni SP’ler.

**Kabul:** Cutover günü sqlcmd `-i *.sql` yok (deploy hariç).

### P2 — Tek orch (opsiyonel)

`SP_MIG_CUTOVER_ALL @FromPhase=@ToPhase @CLEAN=@DryRun`  
Resume = `@FromPhase` (CTAS’taki NNN resume gibi). Log → `MIG_STEP_LOG`.

---

## 5) Operatör kısa kural (yeni disiplin)

```text
1) Deploy (bir kez / drift): 10f + 28 + 35/40/92 sql + yeni IX SP sql
2) Dump sonrası: EXEC SP_MIG_IX_MGR_ENSURE; EXEC SP_MIG_IX_PRECHECK  → FAIL ise DUR
3) Aktarım: yalnız EXEC zinciri (yukarı FAZ 2–5)
4) Her FULL load sonrası POST_INDEXES şart
5) 597: NCIX OFF → ALL → GATE → probe → NCIX ON (INV+PT)
6) 613: IP_AGR IX yoksa başlama
```

**Yasak:** `30c` / eski `SSMS_CUTOVER` ile “kısayol”; POST atlayıp 590/597’ye geçmek; IX’siz “bir deneriz”.

---

## 6) Bilinçli istisna

| Adım | Neden dosya kalabilir (geçici) |
|------|--------------------------------|
| 00b nvarchar→varchar | ALTER TABLE DDL; SP içine alınabilir (P1) |
| 92 DV / 93 FEE heal | Hâlâ script; sonra SP (R12 kalıbı) |
| 91f–i residual | PATCH — FULL zincir dışı |
| CTAS Oracle | Ayrı dünya; bu plan MSSQL Energy |

---

## 7) Başarı ölçütü

- Aynı FULL’da 571/581/575/597 süreleri “IX’li band”da (scan paniği yok).
- `SP_MIG_IX_PRECHECK` = 0 missing.
- Post-597: `pt_ncix_disabled=0`, `inv_ncix_disabled=0`.
- Operatör runbook’ta `-i` satırı yok (yalnız EXEC).
- Tek sürücü: `SSMS_TAHSILAT` / `SP_MIG_CUTOVER_ALL` = `RUN_ORDER` = `ONE_PAGE`.

---

## 8) Uygulama sırası — durum

1. ~~**P0 doküman hizalama**~~ **DONE** — RUN_ORDER / 30c / ONE_PAGE / SSMS / 10f  
2. ~~**P1 PRECHECK + NCIX SP**~~ **DONE** — `26` `26b` `26c`  
3. ~~**P1 MGR ENSURE + IP_AGR**~~ **DONE** — `26a` `26d`  
4. **P2 orch** — `SP_MIG_CUTOVER_ALL` (opsiyonel, açık)

Backlog: **R22 DONE** (P2 hariç).

**Deploy once (sunucu):**
```text
sqlcmd … -i 26_IX_PRECHECK.sql
sqlcmd … -i 26a_IX_MGR_ENSURE.sql
sqlcmd … -i 26b_597_NCIX_DISABLE.sql
sqlcmd … -i 26c_597_NCIX_REBUILD.sql
sqlcmd … -i 26d_IX_IP_AGR.sql
-- sonra 10f STATUS: SP_MIG_IX_* / SP_MIG_597_NCIX_* = OK
```
