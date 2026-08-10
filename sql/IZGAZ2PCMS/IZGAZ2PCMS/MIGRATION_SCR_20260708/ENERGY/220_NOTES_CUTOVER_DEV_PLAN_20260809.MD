# Cutover geliştirme planı — sorunsuz / eksiksiz aktarım (2026-08-09)

Kaynak: canlı cutover notları (597 v5c, WIRE/GATE, 20c, 611/613, paket/snapshot sapması)  
+ `NOTES_597_PERF_SAFE.md` + `EXIT_MAP.md` + `20260708/ENERGY`.

**Tek doğru paket yolu:** `prodREADY_ENERGY` + `prodREADY_ENERGY3007`  
**Arşiv kopya:** `20260708/ENERGY` (`_sync_snapshot.ps1`)  
**Yasak referans:** `_tmp_*` (ops scratch; paket sayılmaz)

---

## 0a) Revizyon disiplini (zorunlu)

Canlıda öğrenilen her fix **aynı gün** ana koda alınır — `_tmp` / “sonra” yok.  
Takip: [`NOTES_REVIZYON_BACKLOG.md`](NOTES_REVIZYON_BACKLOG.md) (R01…).  
Kapanış: backlog DONE/PARTIAL + `_sync_snapshot` + `_deploy_195` (CTAS/ENERGY/REPORT).

**Sonraki FULL hazırlık:** aynı dosyada bölüm **「SONRAKI AKTARIM — hazırlık」** (R15 probe, 20b, CLEAN=0, R12/R16–R18).  
Ops: [`NOTES_597_OPS_HEAL.md`](NOTES_597_OPS_HEAL.md) R08/R09/R15.

## 0) Bugünkü gerçek durum (planın zemini)

| Alan | Durum |
|------|--------|
| 571/581/575 + 590 | Bu cutover’da büyük ölçüde tamam |
| 597 INSERT+WIRE | Tamam (STG/MAP = MGR) |
| 597 GATE | PASS (IOCODE≠0 kapsamı) — ALL log’unda eski FAIL kalabilir |
| INV NCIX | Açık |
| PT NCIX | 20c DONE |
| 611 + 611b | DONE (645 840) |
| 613 | **Eksik** — `INST_NR>0` ~26k AGR; açık borçlu ~20k hâlâ split bekliyor |
| 35 / 40 / 92 / 97 | Henüz APPLY yok (613 sonrası) |
| Paket senkronu | 597/GATE/50e filtre snapshot’a alındı; yeni resume script sync-map’te eksik |

---

## 1) Hedef mimari (bir sonraki FULL için)

```text
CTAS dump → prep/IX/collation
  → REF/MASTER/AGR/READING (önkoşul)
  → MAP → 571 → 581 → 575(+576)
  → 590_ALL → [20b INV+PT NCIX OFF]
  → 597_ALL (v5c hard rules)
  → GATE_PASS → 572 → 20c
  → 35 BANKREF → 611 → 611b → 613 (open-debt only)
  → 40 IPP → 92 STG CLOSE → 91/91b/91c/91d (gerektiği kadar)
  → VALIDATE 95/99/97 → 90
```

**Hard rules (geri dönüş yok):**
1. `#temp` yok → fiziksel `MIG_*_STG_*`
2. Hot path’te MGR `LS_OV_ID_MAP` UPDATE yok → `20a` offline
3. Filtered IX: `IOCODE = 0` (`ISNULL(IOCODE,0)` yasak)
4. Scalar `FN_SAFE_SMALLDT_DEP` hot path yok → inline CASE
5. `IMPLICIT_TRANSACTIONS OFF`; dış BEGIN TRAN yok; kısa TRAN sadece MERGE+MAP_OUT
6. FULL: INV+PT NCIX DISABLE → INSERT → GATE → REBUILD
7. Overlay EXEC sadece `*_ALL` (tek INSERT yasak)
8. Deploy: çalışan SP varken ALTER yok; `sqlcmd -f 65001`

---

## 2) Faz planı

### Faz A — Paket bütünlüğü (P0, kod/ops, 1–2 gün)

**Amaç:** “Hangisi güncel?” sorusunu bitirmek.

| # | İş | Kabul |
|---|----|--------|
| A1 | Sync-map’e ekle: `50e_613_RESUME_OPEN_DEBT_ONLY.sql`, `SSMS_POST_613_EXECS.sql`, `SSMS_TAHSILAT_EXECS.sql` | Snapshot’ta NNN_* dosya var |
| A2 | `_sync_snapshot.ps1` çalıştır + `000_ENERGY_INDEX.MD` kontrol | Manifest = kaynak |
| A3 | Tek runbook dokümanı: `CUTOVER_ONE_PAGE.md` (sıra + EXEC + kabul sorguları) | SSMS’te tek giriş |
| A4 | `_tmp_*` heal script’lerinden “pakete alınacaklar”ı ayıkla (LOADED sync kalıbı → ops not) | Scratch ≠ paket |
| A5 | `_deploy_195` sonrası 195 = repo `MIGRATION_SCR_20260708` (CTAS/ENERGY/REPORT; `SRC_*` yok) | Deploy drift yok |

### Faz B — Canlıyı bitir (P0, bu cutover)

**Amaç:** Eksik 613 + post zincir; yeni FULL değil.

| # | İş | Kabul |
|---|----|--------|
| B1 | Eski 50e Cancel → `50e_613_RESUME_OPEN_DEBT_ONLY.sql` | `pending_open_debt→0` |
| B2 | Kabul: açık borçlu AGR’de `INST_NR>0` veya bilinçli skip (ERR log) | `SPLIT_OK` |
| B3 | `40_installment_plan_pay_apply.sql` DRY=1→0 | IPP apply |
| B4 | `35_bankref_resolve_abys.sql` DRY=1→0 | BANKREF LREF |
| B5 | `92_stg_inv_pay_close_apply.sql` DRY=1→0 | STG close |
| B6 | `SP_MIG_597_GATE` + `SP_AGR_FRK_ALL @OnlyDiff=1` + 90/95/99 | FRK kabul bandı |
| B7 | Opsiyonel `20a` (MGR TAH MAP) — cutover bloklamaz | MGR MAP dolu |

### Faz C — 597 motorunu “bir sonraki FULL” için kilitle (P1)

Canlıda doğrulanan iyileştirmeleri kalıcı hale getir.

| # | İş | Not |
|---|----|-----|
| C1 | PAY hint: MERGE OUTPUT + STG_MAP_OUT (zaten var) — regression test pilot AGR | PT JOIN yasak |
| C2 | Batch-first + `FORCE ORDER` tüm post-MERGE UPDATE’lerde | Hint scan olmasın |
| C3 | Adopt path: PT’de LREF var → LOADED/MAP; identity’ye atma | Kısmi run güvenli |
| C4 | GATE: tahsilat kapsamı `IOCODE<>0` (zaten) — checklist’e yaz | False FAIL olmasın |
| C5 | `28_DEPLOY_597` runbook’a 20b/20c sırasını göm (yorum + SSMS step) | Unutulmasın |
| C6 | Log: energy `BACKUP LOG` / grow eşikleri runbook’ta | %85 alarm |
| C7 | ALL FAIL ama GATE sonra PASS → `MIG_STEP_LOG`’a “GATE_HEAL” notu veya ALL’da GATE retry | Operatör kafa karışıklığı |

### Faz D — 613 performans (P1, bir sonraki FULL’ü kurtarır)

| # | İş | Etki |
|---|----|------|
| D1 | Pending = **sadece açık borç** (50e’ye işlendi) — varsayılan kalsın | ~61k boş tur yok |
| D2 | `SP_MIG_INSTALLMENT_SPLIT_*` / NORMALIZE hot SQL: `OPTION (MAXDOP 4)` veya 8 | CXSYNC_PORT ↓ |
| D3 | ERR AGR: swallow yerine `MIG_613_ERR` tablo + özet | Sessiz fail yok |
| D4 | Progress: her N AGR’de `done_inst` / `open_debt_left` RAISERROR | ETA görünür |
| D5 | İsteğe bağlı: AGR paralel worker (dikkatli; PT contention) — varsayılan serial | Sadece ölçüm sonrası |

### Faz E — Operasyon iskeleti (P1)

| # | İş |
|---|----|
| E1 | `SSMS_CUTOVER_RUN` / `SSMS_TAHSILAT_EXECS` / `SSMS_POST_613` tek `session_context` adım numarası şeması |
| E2 | Her faz sonu **kabul sorgusu bloğu** (MAP=MGR, GATE, NCIX, 613 open-debt=0) |
| E3 | Kill politikası: sadece “plan boşa + veri güvenli”; aksi halde Cancel+resume script |
| E4 | Collation: `#temp` / değişken CP1254 (energy) — 597 heal’de öğrenildi |
| E5 | Identity / LOADED sync: MAP dolu STG LOADED=0 → batch `UPDATE TOP` + LOADED NCIX disable (ops runbook) |

### Faz F — Doğrulama matrisi (P0 kabul / P1 otomasyon)

| Kapı | Sorgu / EXEC | Beklenen |
|------|----------------|----------|
| G1 | STG_PAY left / MAP_PAY = MGR_PAY | 0 / eşit |
| G2 | MAP_TAH = MGR_TAH | eşit |
| G3 | `SP_MIG_597_GATE` | GATE_PASS |
| G4 | PAY `IOCODE<>0` CROSSREF NULL | 0 |
| G5 | INV/PT NCIX disabled | 0 (post-20c) |
| G6 | 613 `pending_open_debt` | 0 |
| G7 | EN_PLAN = MGR_PLAN | eşit |
| G8 | `SP_AGR_FRK_ALL @OnlyDiff=1` | kabul bandı (iş kuralı) |
| G9 | 95/99/90 checklist | FAIL=0 veya bilinen istisna listesi |

---

## 3) Öncelik sırası (yapılacaklar)

```text
ŞİMDİ (bu cutover)
  B1 → B2 → B3 → B4 → B5 → B6 → (B7)

PARALEL / hemen sonra (paket)
  A1 → A2 → A3 → A5

BİR SONRAKİ FULL öncesi
  C* + D2–D4 + E1–E2 + F kapılarını SSMS step’lerine göm
```

---

## 4) Bilinçli residual (blok değil — dokümante et)

- Plan `INVOICE_REF` NULL (~10k): iptal/edge; 611b sonrası beklenen bant.
- PAY_PT MAP’te `IOCODE=0` satırlar: debt/overlay doğası; GATE tahsilat kapsamı dışında.
- `E597=FAIL` log satırı + sonraki `E597G=GATE_PASS`: ALL ortasında GATE false-alarm; heal sonrası PASS geçerli.
- Identity path / hint collide: LREF dolu → adopt, yeniden identity insert yok.

---

## 5) Tanım: “eksiksiz aktarım”

Aşağıdakilerin **hepsi** yeşil:

1. EXIT_MAP sırası tamam (dump→…→90)  
2. G1–G9 kapıları PASS  
3. Repo `prodREADY_*` = snapshot `20260708` = sunucu deploy klasörü (diff yok)  
4. Ops scratch (`_tmp`) pakete karışmamış  
5. Bir sonraki FULL, bu nottaki hard rules + 613 open-debt + MAXDOP ile **temiz koşuya** hazır  

---

## 6) Riskler

| Risk | Mitigasyon |
|------|------------|
| 613 sessiz ERR | D3 hata tablosu |
| Log %90+ | E6 / BACKUP LOG runbook |
| Deploy drift | A5 + sync zorunlu |
| ALL FAIL paniği | C7 + G3 tek otorite |
| DOP 48 thrash | D2 |
| Boş 613 turu | D1 (yapıldı) |
