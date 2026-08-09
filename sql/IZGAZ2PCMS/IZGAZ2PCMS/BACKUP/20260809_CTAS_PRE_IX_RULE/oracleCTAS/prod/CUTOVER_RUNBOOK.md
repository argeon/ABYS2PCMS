# Prod fatura cutover runbook

Pilot dosyalar dokunulmaz. Full paket: `oracleCTAS/prod/0N_*__full.sql` + `590/597__full.sql`.

## Faz 0 — Checklist (kod oncesi)

- [ ] Oracle tablespace / undo / temp serbest alan
- [ ] MSSQL `izgazMGR` + `energy` disk
- [ ] Uzun session: sqlplus / SQL Developer sunucu tarafi; zombie `CREATE` icin `v$session` izle
- [ ] Pilot SP geri donus: `590/597__pilot_agr.sql` deploy yolu hazir
- [ ] TSV dump **yasak** (~350M+)

## Faz 1 — Oracle CTAS (sira)

Tek komut (onerilen):

- sqlplus / SQL Developer: `00_run_all_full.sql` (01..05 + 06 gate)
- RunTah: `.\00_run_all_full.ps1`

Tek tek:

1. `01_LS_INVOICE__full.sql`
2. `02_LS_INVLINES__full.sql`
3. `03_LS_EKSILTEN_OVERLAY__full.sql`
4. `04_LS_TAHSILAT_OVERLAY__full.sql`
5. `05_LS_TAHSILAT_LOG__full.sql`
6. `06_adim5_tahsilat_gate_full.sql` (`PT=ALLOC`, `NO_XREF=0`)

Hata olursa zincir durur (gate `RAISE` dahil).


Opsiyonel dry-run: `TMP_PAY_CANCEL` + `LS_INVOICE` sure olcumu (ilk CTAS oncesi kucuk probe).

## Faz 2 — izgazMGR (Migratorv0 MigrationEngine)

**TSV / probe Dump*.java kullanma.**

1. Repo: `C:\Users\HW5536\source\repos\Migratorv0`
2. Wizard veya `MigrationEngine`: `dotnet run -- --run` (kesilirse `--resume`)
3. Oracle: `connections.json` (izgaz), **schema = `MIGRATION`** (default `SMS` degil)
4. Hedef MSSQL: **`izgazMGR`**
5. Tablolar: `LS_INVOICE`, `LS_INVLINES`, `LS_OV_*` (eksilten + tahsilat); log istege bagli
6. Batch 50k–100k, Fetch 50–100MB; gerekirse parallel partition
7. Dogrula: Oracle `COUNT` ≡ izgazMGR `COUNT`

## Faz 3 — energy

1. `adim3_verify_indexes.sql` (ozellikle `izgazMGR.LS_INVLINES(LREF)` — 581 KEYSET)
2. Deploy: `571` v9+, `575` v3+, `611` key-list, `581`, `590/597__full`, `613`
3. Calistir (onerilen): `adim_full_layer_run.sql` **veya** `adim_full_fatura_run.sql` `@MODE='LAYER'`
   - Katman sira: 571 → 581 → 575 → 611 → 613 (plan AGR) → 590 → 597 — hepsi `@AGR_ID=NULL`
   - `@BATCH=50000`; kesilirse ilgili SP `@RESUME=1`
   - **Full'de `@MODE='LOOP'` kullanmayin** (seyrek AGR ID + eski BETWEEN = saatler)
4. Recon / spot: `adim_post_mig_kontrol.sql` (global COUNT + canary AGR 197168 PASS/FAIL); ek spot: pilot AGR (20811205, 152185118 taksit PAID)


## Bilinen aciklar

- Tip12 emanet cikisi: overlay disi (`EMANET_CIKIS_*` log)
- `PAY_NO_ALLOC` satirlari olabilir
- AGR 276503 installment modeli farkli olabilir

## Rollback

- Energy: CLEAN-by-AGR / zincir silme; veya `590/597__pilot_agr` yeniden deploy
- Oracle: CTAS tablolari `PURGE` + yeniden uret (SMS kaynak kalir)
