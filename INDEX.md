# Migratorv0 — dizin indeksi

Sol paneli temiz tutmak için çalışma yüzeyi daraltıldı. Aradığın şey buradan:

## Canlı çalışma (195 ile senkron)

| Ne | Yol |
|----|-----|
| Energy paket (asıl) | `sql/IZGAZ2PCMS/IZGAZ2PCMS/prodEnergy/` |
| Run order / 3007 | `.../prodEnergy/prodREADY_ENERGY3007/` |
| Overlay / 590–597 | `.../prodEnergy/prodREADY_ENERGY/` |
| FRK / kontrol | `.../prodEnergy/90_afl_frk/` |
| Bağlantı / deploy | `sql/IZGAZ2PCMS/IZGAZ2PCMS/connections.json`, `deploy.ps1` |
| Pipeline notları | `PIPELINE_LIVE.txt`, `CUTOVER_MANUAL_CHECKLIST.txt` |

## Uygulama kodu

| Ne | Yol |
|----|-----|
| Engine | `MigrationEngine/` |
| UI | `Migratorv0/` |
| Shared | `MigrationShared/` |
| MSSQL copy | `MssqlCopyEngine/` |
| Araçlar | `tools/` |

## Çöp / arşiv (sol panelde genelde kapalı tut)

| Ne | Yol |
|----|-----|
| Scratch (`_tmp_*`) | `_tmp/` |
| Loglar | `logs/` (+ `logs/sql/`) |
| Publish / build çıktı | `_artifacts/` |
| Eski SQL ağacı + snapshot | `sql/IZGAZ2PCMS/IZGAZ2PCMS/BACKUP/` |
| Üst seviye SQL yedekleri | `sql/IZGAZ2PCMS/BACKUP/` |
| Eski kök MD/TXT | `docs/legacy/` |

### BACKUP içinde sık arananlar

| Ne | Yol |
|----|-----|
| 20260708 snapshot | `.../BACKUP/20260708/` (`_sync_snapshot.ps1`) |
| oracleCTAS / CTAS3007 | `.../BACKUP/oracleCTAS*`, `oracleControl` |
| Eski düz pipeline SQL | `.../BACKUP/*.sql` (1xx–6xx) |
| ProdIzgazMgr2Energy | `.../BACKUP/ProdIzgazMgr2Energy/` |
| stage_ops | `.../BACKUP/stage_ops/` |

## Başlangıç dokümanları (kökte kalan)

- `README.md` — genel
- `BASLANGIC.md` / `QUICK_START.md` / `BUILD_AND_RUN.md`
- Eski feature notları → `docs/legacy/`

## Kural

- Canlı düzenleme: **yalnızca** `prodEnergy` (+ gerekirse deploy/checklist kök dosyaları).
- Scratch → `_tmp/`, log → `logs/`, eski paket → `BACKUP/`.
- Snapshot yenilemek için: `BACKUP/20260708/_sync_snapshot.ps1` (kaynak hâlâ `prodEnergy`).
