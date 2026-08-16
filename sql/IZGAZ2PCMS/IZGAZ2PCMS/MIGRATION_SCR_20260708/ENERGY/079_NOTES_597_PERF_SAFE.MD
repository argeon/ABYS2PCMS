# 597 — Performans & Güven yolu (güncel not)

**İlke:** Önce doğruluk/güven (yanlış CROSSREF, log full, dış TRAN), sonra hız (batch, SARG, staging).  
**Deploy kuralı:** Çalışan `SP_MIG_597_INSERT` (örn. session 112) gövdesini değiştirmek o EXEC’i hızlandırmaz. Yeni kod = sonraki `EXEC` veya kill+`@CLEAN=0` restart.

**Ölçüm özeti (2026-08-04):**
| Bulgu | Değer | Etki |
|--|--|--|
| OV_PAY_PT | ~66.7M | FULL maliyet |
| CROSSREF_MAIN null | 0 | OK |
| MAIN→debt PT yok | 0 | OK |
| SRC_KEY unique | 66.7M | MAP yolu güvenli |
| ABYS multi-MAIN | ~434k key | ABYS fallback YASAK (yapıldı) |
| LREF_HINT multi-MAIN | 0 | HINT fallback OK |
| CLEAN MAP NULL→NULL | ~133M, saatlik | INSERT P0 şart |
| TAH tek INSERT | ~66M, log %100 | batch şart |

---

## Durum panosu

| Alan | Durum | Not |
|--|--|--|
| WIRE v4 | **DONE** (deploy) | DEBT_LOOKUP, batch, TAH BANK staging, dış TRAN yok |
| WIRE MAIN/DEBT/PAY/TAH BANKREF keyset | **PAKETTE** (`21`+`00g`) | `BANK_LREF` + keyset; **82 idle** → `28_DEPLOY_597` |
| BANKREF indexes (`00g`) | **PAKETTE** | TAH/INV/PT/BANK covering; 21 DDL sonrası |
| WIRE ABYS single-MAIN | **DONE** | multi-MAIN fanout kapalı |
| GATE mismatch vs OV MAIN | **DONE** | hard FAIL |
| INSERT physical staging | **DONE** (v3) | `#temp` yok; identity MERGE batch var |
| CLEAN filtre+batch | **DONE** (v4 INSERT) | A |
| TAH INSERT batch | **DONE** (v4 INSERT) | B |
| PAY hint batch + DEBT_LOOKUP staging | **DONE** (v4 INSERT) | C |
| Runbook / log grow | **kısmi** | `00e_grow_izgazMGR_log.sql`; energy grow ad-hoc |
| v4 indexes (`00f`) | **DONE** | TAH/PAY SRC_KEY UX; MGR MAP ELREF; STG hint/SRC |
| Deploy paket `28` | **00f→20→21→00g→22→29** | 20b/20c ops (NCIX) pakete dahil değil — runbook |

---

## Yol haritası (sırayla)

### Faz 0 — Operasyon (her zaman, kod gerekmez)
**Güven**
- SSMS / sqlcmd: **dış `BEGIN TRAN` yok** (`open_tran_count=2` uzatır, rollback pahalı).
- Log: energy / izgazMGR `used_pct ≥ 85` → grow (+20–40 GB). Script: `00e_grow_izgazMGR_log.sql`; energy aynı `MODIFY FILE`.
- Kill: sadece veri tamam + statement boşa tarıyorsa ve rollback maliyeti kabul ediliyorsa; aksi halde bekle.
- Retry: overlay/TAH zaten yazıldıysa `@CLEAN=0` (CLEAN’i atla).

**İzleme**
- Messages: `597 INSERT TAH_INV=`, `PAY_PT pending/hint/identity=`, `WIRE … batch=`, `E597G GATE_PASS`.
- `dm_db_log_space_usage` + WhoIsActive (writes artıyor mu?).

---

### Faz 1 — CLEAN güven+hız (`20_597_INSERT`)  ★ öncelik A
**Sorun:** `ENERGY_LREF=NULL` filtresiz → NULL→NULL ~133M, log full (MGR %100 görüldü).

**Uygula**
1. Her iki MAP UPDATE: `AND ENERGY_LREF IS NOT NULL`.
2. Batch: `WHILE` + `UPDATE TOP (@BatchSize)` (veya keyset); statement başına kısa commit.
3. DEBUG: filled before/after (EN + MGR).
4. (P2) `filled=0` ve silinecek overlay yok → CLEAN blok skip + log.

**Kabul:** İkinci CLEAN saniyeler; dolu MAP’te log doğrusal batch.

---

### Faz 2 — PAY_PT staging + hint batch  ★ öncelik C (WIRE’den önce INSERT riski)
**Sorun:** ~66M’nin çoğu hint path → TAH gibi tek `IDENTITY_INSERT`; staging’de satır başına debt `TOP 1`.

**Uygula (güven → perf)**
1. Staging öncesi / WIRE ile aynı: `MIG_597_STG_DEBT_LOOKUP` doldur; `CROSSREF_PT = lookup` **join** (correlated subquery kaldır).
2. Hint INSERT: `@BatchSize` döngüsü (`TOP` + staging batch keys); her batch kendi commit (dış TRAN yok).
3. MAP EN+MGR fill: batch veya hint batch ile birlikte.
4. Identity MERGE batch **koru** (zaten güvenli çizgi).

**Kabul:** Hint batch Messages’te artar; energy log tek 66M spike yerine adım adım; CROSSREF_PT = debt LREF (GATE ile uyumlu).

---

### Faz 3 — TAH_INV batch  ★ öncelik B
**Sorun:** Tek 66M INSERT + `NOT EXISTS` + uzun kapanış (PAGEIOLATCH / log).

**Uygula**
1. Key staging: insert edilecek `LREF_HINT` seti (anti-join bir kez).
2. `IDENTITY_INSERT` batch 20–50k; batch arası commit.
3. MAP TAH EN+MGR: `ENERGY_LREF IS NULL` + batch.
4. Runbook: TAH öncesi energy log headroom (≥%30 boş hedef).

**Kabul:** TAH Messages cumulative; 66M tek statement yok.

---

### Faz 4 — WIRE/GATE (kalan ince iş)
**DONE çekirdek.** İsteğe bağlı:
- CANCEL_PAY / IADE delete hacmi büyürse batch.

**GATE (mevcut):** MAP NULL, CROSSREF NULL, not-debt-PT, **mismatch vs OV MAIN**, CANCEL INVOICEREF.

---

### Faz 4b — WIRE BANKREF staging+batch  ★ 2026-08-04 FULL gözlemi
**Sorun (session 82):** `UPDATE inv.BANKREF … JOIN izgazMGR.LS_INVOICE` tek statement (~59M), `PAGEIOLATCH_SH:izgazMGR`, saatler; `bank_null` commit öncesi ilerlemez.

**Uygula (`21_597_WIRE.sql` — repo’da hazır):**
1. `MIG_597_STG_MAIN_BANK` ← MGR `LS_INVOICE` (LREF, BANK_SMS) bir kez.
2. Energy `UPDATE` `@BatchSize` + `MIG_597_STG_BATCH` (TAH BANK modeli).
3. Aynı kalıp: `MIG_597_STG_DEBT_PT_BANK`, `MIG_597_STG_PAY_BANK`, `MIG_597_STG_BATCH_ABYS`.
4. OV_PAY_PT fallback da stage+batch (sadece `BANKREF IS NULL`).

**Deploy kuralı:** Session 82 / herhangi `SP_MIG_597_*` çalışırken **ALTER YASAK**.  
Bitince (veya KILL sonrası idle): `21_597_WIRE.sql` → gerekirse sadece `EXEC SP_MIG_597_WIRE @CLEAN yok, @BatchSize=100000`.  
Sonra `20c_PAYTRANS_NCIX_REBUILD.sql`.

**Şimdi yapma:** Online index / kill bu statement’ı hızlandırmaz.

---

### Sonraki FULL öncesi (2026-08-04 run notu)
Bu run (session 82): TAH BANKREF eski `SELECT TOP` + mismatch picker ile ilerliyor (Messages örn. `batch=200000 total≈17M+`). Akıyorsa **KILL etme**.  
**KILL + DEPLOY şu an TAH’ı hızlandırmaz** — deploy’daki yeni WIRE MAIN/DEBT/PAY’i düzeltir; TAH hâlâ aynı picker algoritması (keyset henüz yazılmadı). Kill, WIRE’ın önceki adımlarını yeniden koşturur → net süre çoğu zaman uzar.

**Sonraki run / acil WIRE — paket hazır (`28_DEPLOY_597`):**
1. Idle iken: `28_DEPLOY_597.sql` (= `00f` → `20` → `21` keyset → `00g` indexes → `22` → `29`).
2. Index (`00g`) + keyset (`21`) birlikte; index tek başına eski picker’ı çözmez.
3. FULL: `20b` → `ALL @BatchSize=250000` → `20c`.
4. 597 çalışırken `CREATE OR ALTER` YASAK.

**Bu run seçenekleri:**
- Bırak (~2–4 saat TAH) → GATE → `20c` → `28_DEPLOY` → sonraki FULL.
- **Hızlandır:** KILL 82 → `28_DEPLOY_597` →  
  `EXEC SP_MIG_597_WIRE @AGR_ID=NULL, @DEBUG=1, @BatchSize=200000;` → GATE → `20c`.

---

### Faz 5 — Doğrulama sırası
1. Deploy: `20_597_INSERT.sql` (+ gerekirse DDL staging), `29_597_ALL` BatchSize iletimi (WIRE zaten).
2. Smoke: `@AGR_ID=197168, @CLEAN=1, @BatchSize=20000` → GATE_PASS.
3. Retry senaryosu: `@CLEAN=0` hızlı geçer.
4. FULL: log izle; grow eşiği %85.
5. GATE_PASS + spot CROSSREF / BANKREF.

---

## Yapma listesi (kısa)

| # | İş | Dosya | Güven | Perf |
|--|--|--|--|--|
| 1 | CLEAN `IS NOT NULL` + batch | `20_597_INSERT` | ★★★ | ★★★ |
| 2 | PAY DEBT_LOOKUP join staging | `20_597_INSERT` | ★★ | ★★★ |
| 3 | PAY hint INSERT batch | `20_597_INSERT` | ★★★ | ★★★ |
| 4 | TAH INSERT batch + key set | `20_597_INSERT` | ★★★ | ★★★ |
| 5 | MAP fill batch (TAH/PAY) | `20_597_INSERT` | ★★ | ★★ |
| 6 | Runbook: TRAN yasak, `@CLEAN=0`, log grow | `SSMS_CUTOVER_RUN` / `30c` | ★★★ | ★ |
| 7 | energy grow script (00e benzeri) | `00e` / yeni `00f` | ★★ | ★ |
| 8 | MAIN/DEBT/PAY/TAH BANKREF keyset + `BANK_LREF` | `21` (28 paket) | ★★ | ★★★ |
| 9 | BANKREF covering indexes | `00g` (28 paket) | ★ | ★★ |

---

## FULL run 112 — FAIL (2026-08-04 ~15:43)

- **Hata:** `The definition of object 'SP_MIG_597_INSERT' has changed since it was compiled.`
- **Sebep:** INSERT v4, session 112 hâlâ eski `SP_MIG_597_INSERT` içindeyken deploy edildi.
- **Sonuç:** CLEAN + TAH satırları energy’de (`TYPE=101` ≈ MGR); MAP TAH/PAY boş; PAY yok.
- **Kural:** Çalışan `SP_MIG_597_*` varken `CREATE OR ALTER` yapma.
- **Resume:** `@CLEAN=0` (TAH silme). INSERT’te **TAH MAP resume backfill** (INV var + MAP null → batch fill).

```sql
-- dış BEGIN TRAN yok
EXEC dbo.SP_MIG_597_ALL @AGR_ID=NULL, @CLEAN=0, @DEBUG=1, @BatchSize=20000;
```

---

## Referans dosyalar / paket
- **Deploy tek komut:** `28_DEPLOY_597.sql` (`:r` → 00f → 20 → 21 → 22 → 29)
- `00f_597_v4_indexes.sql` — v4 index
- `20_597_INSERT.sql` — v4 INSERT + hızlı TAH MAP resume (500k, INV join yok)
- `20a_597_TAH_MAP_FAST_FILL.sql` — resume MAP (FULL zincire koyma)
- `21_597_WIRE.sql` / `22_597_GATE.sql` / `29_597_ALL.sql`
- `00e_grow_izgazMGR_log.sql` — MGR log grow
- `README.md` / `RUN_ORDER.sql` — D bloğu v4
- Backup: `_backup_597_*` (pakete dahil değil)
