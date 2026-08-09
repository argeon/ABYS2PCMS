# CANONICAL — tek çalışma yüzeyi

Bu klasör **harita**. Canlı dosyalar buraya kopyalanmaz; aşağıdaki yollar tek doğrudur.
Eski `BACKUP/*` ağaçlarını silmeden / temizlemeden önce buraya bak.

## 1) Canlı (195 senkron kaynak)

| Ne | Yol |
|----|-----|
| Energy paket | `../prodEnergy/` |
| Overlay 590–597 | `../prodEnergy/prodREADY_ENERGY/` |
| Staging / 613 / SSMS | `../prodEnergy/prodREADY_ENERGY3007/` |
| FRK | `../prodEnergy/90_afl_frk/` |

## 2) CTAS omurga (Oracle)

| Ne | Yol |
|----|-----|
| Omurga | `../BACKUP/oracleCTAS3007/` |
| Overlay / diag (prodREADY) | `../BACKUP/oracleCTAS/prodREADY/` |
| Snapshot + sync | `../BACKUP/20260708/` (`_sync_snapshot.ps1`) |

O50 `LS_AFL_OPEN_DEBT.GECIKME_BEDELI` → `oracleCTAS3007/50_ls_afl_open_debt.sql`  
O61 `LS_CUSTODY` → `oracleCTAS3007/61_ls_custody.sql`

## 3) Yardımcı (silme)

| Ne | Yol | Not |
|----|-----|-----|
| Mgr2Energy legacy SP | `../BACKUP/ProdIzgazMgr2Energy/` | 611/613 kaynak; henüz silme |
| oracleControl | `../BACKUP/oracleControl/` | Oracle kontrol; henüz silme |
| stage_ops | `../BACKUP/stage_ops/` | Ops config |

## 4) Bilinçli arşiv / çöp (silinebilir)

| Ne | Yol |
|----|-----|
| Pre-IX kural yedeği | _(silindi)_ → git tag `v0.1.0` |
| Tiny ref yedekleri | `../BACKUP/_backup_*`, `backup_hhd_*` |
| Üst seviye dated zip ağaçları | `../../BACKUP/IZGAZ2PCMS_backup_*` (gitignore) |

## Kural

1. Düzenleme: yalnız `prodEnergy` + `BACKUP/oracleCTAS3007` (+ gerekirse `oracleCTAS/prodREADY`).
2. Snapshot: `_sync_snapshot.ps1` — kaynakları taşımaz, kopyalar.
3. 195 deploy ayrı adımdır; bu harita lokal paketi tanımlar.
4. Repo kök: `VERSION_LOG.md`, `INDEX.md`.
