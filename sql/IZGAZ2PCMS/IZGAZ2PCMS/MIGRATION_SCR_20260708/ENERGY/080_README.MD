# prodREADY_ENERGY — izgazMGR → energy

Oracle: `oracleCTAS/prodREADY/`  
Sıra + EXEC: **`RUN_ORDER.sql`**

## Önemli

**590/597 overlay’dir** — ana tahakkuk değil.  
Sıra: **571 → 581 → 575 → sonra `SP_MIG_590_ALL` → `SP_MIG_597_ALL`**

Tek başına INSERT yasak; sadece `*_ALL` EXEC.

**Dump sonrası (izgazMGR):** `00b_align_mgr_varchar.sql` → `00c_enrich_mgr_kismi_lineexp.sql`  
(KISMI `LINEEXP` = `Kismi Eksilten | {gelir} | EKS=…` — Oracle yeniden CTAS gerekmez)

## Sıra

```text
A) SETUP (prodREADY_ENERGY/)
   00_log_setup → 00_map_tables → MAP kopya
   → 00_abys_columns → 01_linenr_smallint

B) ANA YUKLEME (ProdIzgazMgr2Energy/)  ★ ONCE
   EXEC SP_MIGRATE_LS005_INVOICE
   EXEC SP_MIGRATE_LS005_INVLINES
   EXEC SP_MIGRATE_LS005_DEBT_PAYTRANS

C) 590 OVERLAY
   Deploy 10→11→12→19
   EXEC SP_MIG_590_ALL @AGR_ID=NULL, @CLEAN=1, @DEBUG=1

D) 597 OVERLAY  (C PASS sonrası) — v4+ paket
   Deploy: 28_DEPLOY_597.sql   (= 00f → 20 → 21 → 00g → 22 → 29)
   FULL: 20b NCIX off → ALL @BatchSize=250000 → 20c rebuild
   Resume (MAP null, INV dolu): 20a → ALL @CLEAN=0
   Notlar: NOTES_597_PERF_SAFE.md | dış TRAN yok | çalışan SP'de ALTER yok

E) EXEC SP_MIG_LOG_STATUS + CHECK_QUERIES_ENERGY.sql
```

## 597 v4 paket (`prodREADY_ENERGY/`)

| Dosya | Rol |
|--|--|
| `00f_597_v4_indexes.sql` | TAH/PAY/MAP/staging index (bir kez) |
| `00g_597_bankref_indexes.sql` | BANKREF covering (TAH/INV/PT/BANK + STG keyset) |
| `00e_grow_izgazMGR_log.sql` | MGR log grow (op) |
| `20_597_INSERT.sql` | INSERT v4 + LOADED + hızlı TAH MAP resume |
| `20a_597_TAH_MAP_FAST_FILL.sql` | Resume MAP fill (FULL zincire koyma) |
| `20b` / `20c` | PAYTRANS NCIX disable / rebuild (ops) |
| `21_597_WIRE.sql` | WIRE + BANKREF `BANK_LREF` keyset |
| `22_597_GATE.sql` / `29_597_ALL.sql` | GATE / ALL |
| `28_DEPLOY_597.sql` | Tek sefer deploy (`:r` sırası) |
| `NOTES_597_PERF_SAFE.md` | Perf / kabul / FAIL notları |

```text
sqlcmd -S <srv> -d energy -C -I -b -i 28_DEPLOY_597.sql
```

## EXEC (B → C → D)

```sql
USE energy;
GO

-- B1 ana
EXEC dbo.SP_MIGRATE_LS005_INVOICE
    @BATCH_SIZE=50000, @RESUME=1, @AGR_ID=NULL, @DEBUG=1;
GO
-- B2 ana
EXEC dbo.SP_MIGRATE_LS005_INVLINES
    @BATCH_SIZE=100000, @RESUME=1, @RANGE_MODE='KEYSET', @DEBUG=1;
GO
-- B3 ana
EXEC dbo.SP_MIGRATE_LS005_DEBT_PAYTRANS
    @BATCH_SIZE=50000, @RESUME=1, @AGR_ID=NULL, @DEBUG=1;
GO

-- C overlay (deploy 19 sonrası)
EXEC dbo.SP_MIG_590_ALL @AGR_ID=NULL, @CLEAN=1, @DEBUG=1;
GO
-- D overlay (28_DEPLOY_597 veya 20→29 sonrası)
EXEC dbo.SP_MIG_597_ALL @AGR_ID=NULL, @CLEAN=1, @DEBUG=1, @BatchSize=100000;
-- Resume: önce 20a (gerekirse), sonra @CLEAN=0
GO

EXEC dbo.SP_MIG_LOG_STATUS;
GO
```

## Checklist

`CHECKLIST.txt` / `MANUAL_CHECKLIST_ENERGY.txt`
