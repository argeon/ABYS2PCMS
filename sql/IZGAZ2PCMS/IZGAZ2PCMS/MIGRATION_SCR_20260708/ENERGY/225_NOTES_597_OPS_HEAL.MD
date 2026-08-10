# 597 ops heal — GATE log + LOADED↔MAP

Paket içi runbook. `_tmp` heal’i paket sayma.

---

## R08 — `E597=FAIL` vs `E597G=GATE_PASS`

**Belirti:** `29_597_ALL` Messages’da `E597 ALL FAIL` / `MIG_STEP_LOG` `E597=FAIL`, sonra ayrı koşuda `E597G | GATE_PASS`.

**Neden:** ALL, GATE’i TRY/CATCH içinde çağırır. Ara aşamada (eski GATE IOCODE=0 CROSSREF false-FAIL, veya kısmi WIRE) GATE 16 severity atar → ALL `FAIL` loglar. Heal / GATE fix sonrası `SP_MIG_597_GATE` tek başına PASS yazar (`E597G`).

**Ne yapma:**
1. `E597=FAIL` satırına bakıp zinciri bitmiş sayma.
2. Otorite: `EXEC dbo.SP_MIG_597_GATE @AGR_ID=NULL` → `GATE_PASS` + `E597G`.
3. GATE gövdesi = dosya: `22_597_GATE.sql` (CROSSREF sadece `IOCODE<>0`). Redeploy: `28_DEPLOY_597.sql` veya en azından `22` + `29`.

**Log okuma:**
```sql
SELECT TOP 30 STEP_ID, STATUS, NOTE, LOG_TS
FROM dbo.MIG_STEP_LOG WITH (NOLOCK)
WHERE STEP_ID IN ('E597','E597G')
ORDER BY LOG_TS DESC;
```

---

## R09 — LOADED↔MAP sync (kısmi run orphan)

**Belirti:** `MIG_OV_ID_MAP` PAY_PT dolu, `MIG_597_STG_PAY.LOADED=0` → INSERT tekrar identity/hint dener veya pending şişer.

**Kalıp:** `20d_597_LOADED_MAP_HEAL.sql` (bu klasör).

1. STG LOADED NCIX disable (büyük keyset UPDATE).
2. MAP’te ENERGY_LREF var → STG `LOADED=1`.
3. PT’de LREF zaten var (adopt) → MAP+LOADED.
4. NCIX reopen.
5. `SP_MIG_597_GATE`.

**Yasak:** hot path’te MGR `LS_OV_ID_MAP` UPDATE (→ `20a` offline).

---

## R15 — PAY_PT map → borç LREF (IOCODE=0) — 195 gap ~30M

**Belirti:** `PAY_PT` ENERGY_LREF dolu ama `PAYTRANS` IOCODE=1 sayısı map’ten ~30M eksik; map join’inde `IOCODE=0` satırlar.

**Kök:** hint path **adopt** `LREF` doluysa IOCODE bakmadan MAP+`LOADED=1` → tahsilat INSERT atlanır (borç LREF collide).

**YASAK:** bozuk map varken `@CLEAN=1` FULL — CLEAN `map→PT DELETE` borç satırını siler.

**Kalıp:** `20e_597_PAY_PT_BAD_MAP_HEAL.sql` + adopt fix (`20_597_INSERT` / `20d`).

### 195 güvenli sıra

```text
0) Probe (beklenen: bad map ~30M, IOCODE=1 ~37M)
1) 20e @DRY_RUN=1 → sayım
2) 20e @DRY_RUN=0 → EN(+MGR) bad PAY* map NULL + STG truncate
   (borç PT silinmez; iyi IOCODE=1 map kalır)
3) 28_DEPLOY_597.sql  (veya en az 20_597_INSERT — adopt IOCODE<>0)
4) 20b_PAYTRANS_NCIX_DISABLE.sql
5) EXEC SP_MIG_597_ALL @AGR_ID=NULL, @CLEAN=0, @DEBUG=1, @BatchSize=250000
   ★ CLEAN=0 zorunlu (TAH/iyi PAY silme; bad map zaten null)
6) EXEC SP_MIG_597_GATE @AGR_ID=NULL
7) 20c_PAYTRANS_NCIX_REBUILD.sql
8) Kabul:
     PAY_PT map → IOCODE=0  = 0
     IOCODE=1 ≈ LS_OV_PAY_PT (~66.8M)
     PT toplam ≈ 196 (~140M)
```

**Yapma:** `20a` (sadece TAH_INV null fill — bu anomaliyi çözmez).  
**Yapma:** `20d` adopt’u heal öncesi eski gövdeyle — borç adopt tekrarlar (redeploy şart).

**Sonraki aktarım:** FULL öncesi A1–A7 + probe C — `NOTES_REVIZYON_BACKLOG.md` →「SONRAKI AKTARIM — hazırlık」.
