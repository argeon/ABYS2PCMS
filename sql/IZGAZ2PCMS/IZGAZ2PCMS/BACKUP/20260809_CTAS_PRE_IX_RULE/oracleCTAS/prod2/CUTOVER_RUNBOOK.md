# Prod2 fatura cutover runbook (energy-yakin)

Pilot dokunulmaz. Full paket: `oracleCTAS/prod2/` + `590/597__full.sql`.

## Faz 0 — Checklist

- [ ] Oracle tablespace / undo / temp (aggregate icin TEMP bol)
- [ ] MSSQL `izgazMGR` + `energy` disk
- [ ] Uzun session: sqlplus / SQL Developer sunucu; `v$session` izle
- [ ] Pilot SP geri donus: `590/597__pilot_agr.sql` hazir
- [ ] TSV dump **yasak** (~350M+)

## Faz 1 — Oracle CTAS prod2

Tek komut:

- sqlplus: `00_run_all.sql`
- RunTah: `.\00_run_all.ps1`

Sira: `00 → 10 → 11 → 12 → 13 → 14 → 20 → 27 → 30 → 40 → 41`

Yeni urunler (prod'a gore):

- `LS_MIG_AGR_LIST` — LOOP AGR listesi
- `LS_DEBT_PAYTRANS` — 575 prefab (borc PT)
- Eksilten/tahsilat **AGR index**
- Anahtar kolonlar `NUMBER(12|10|3|1)` + `ABYS_ID`

## Faz 2 — izgazMGR (MigrationEngine)

1. Repo Migratorv0 — `dotnet run -- --run` (`--resume` kesilirse)
2. Oracle schema **`MIGRATION`**
3. Hedef **`izgazMGR`**
4. Tablolar: `LS_INVOICE`, `LS_INVLINES`, `LS_MIG_AGR_LIST`, `LS_DEBT_PAYTRANS`, `LS_OV_*`
5. Batch 50k–100k; COUNT Oracle ≡ izgazMGR

## Faz 3 — energy

1. `adim3_verify_indexes.sql` (+ OV AGR index mirror onerilir)
2. Deploy: `590__full`, `597__full` (571 `@AGR_ID NULL` destekler)
3. Onerilen:
   - AGR loop: `LS_MIG_AGR_LIST` kullan
   - Borc PT: `LS_DEBT_PAYTRANS` bulk (575 turetimini atla veya sade INSERT)
4. Calistir: `adim_full_fatura_run.sql` (`@MODE='LOOP'`)
5. Recon / spot: pilot AGR

## Bilinen aciklar

- Tip12 emanet cikisi: overlay disi (`EMANET_CIKIS_*` log)
- `PAY_NO_ALLOC` olabilir
- AGR 276503 installment modeli farkli olabilir
- `OWNERREF` energy AGR.LREF wire hâlâ 571/post tarafinda

## Rollback

- Energy: CLEAN-by-AGR / `590/597__pilot_agr` redeploy
- Oracle: CTAS `PURGE` + `prod2` yeniden (veya eski `prod/`)
