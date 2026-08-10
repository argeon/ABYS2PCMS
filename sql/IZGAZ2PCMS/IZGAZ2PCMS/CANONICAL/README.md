# CANONICAL — tek çalışma yüzeyi

Bu klasör **harita**. Canlı dosyalar buraya kopyalanmaz; aşağıdaki yollar tek doğrudur.
Eski `BACKUP/*` ağaçlarını silmeden / temizlemeden önce buraya bak.

## 1) Canlı düzenleme (kaynak)

| Ne | Yol |
|----|-----|
| Energy paket | `../prodEnergy/` |
| Overlay 590–597 | `../prodEnergy/prodREADY_ENERGY/` |
| Staging / 613 / SSMS | `../prodEnergy/prodREADY_ENERGY3007/` |
| FRK | `../prodEnergy/90_afl_frk/` |

## 2) Temiz paket yüzeyi (repo ↔ 195 — aynı ad/yapı)

```text
MIGRATION_SCR_20260708/
  CTAS/
  ENERGY/
  REPORT/
```

| Ne | Repo | 195 |
|----|------|-----|
| Kök | `../MIGRATION_SCR_20260708/` | `C:\www\MIGRATION_SCR_20260708` |
| CTAS | `.../CTAS/` | `...\CTAS\` |
| ENERGY | `.../ENERGY/` | `...\ENERGY\` |
| REPORT | `.../REPORT/` | `...\REPORT\` |

Yenile: `_sync_snapshot.ps1` → deploy: `_deploy_195.ps1`  
**Yasak:** `SRC_*`, yan paket — yalnız üç klasör.

## 3) CTAS omurga (Oracle kaynak)

| Ne | Yol |
|----|-----|
| Omurga | `../BACKUP/oracleCTAS3007/` |
| Overlay / diag (prodREADY) | `../BACKUP/oracleCTAS/prodREADY/` |

## 4) Yardımcı (silme)

| Ne | Yol | Not |
|----|-----|-----|
| Mgr2Energy legacy SP | `../BACKUP/ProdIzgazMgr2Energy/` | 611/613 kaynak; henüz silme |
| oracleControl | `../BACKUP/oracleControl/` | Oracle kontrol; henüz silme |
| stage_ops | `../BACKUP/stage_ops/` | Ops config |

## 5) Bilinçli arşiv / çöp

| Ne | Yol |
|----|-----|
| Eski snapshot yolu | `BACKUP/20260708` → taşındı: `MIGRATION_SCR_20260708` |
| Tiny ref yedekleri | `../BACKUP/_backup_*`, `backup_hhd_*` |

## Kural

1. Düzenleme: yalnız `prodEnergy` + `BACKUP/oracleCTAS3007` (+ gerekirse `oracleCTAS/prodREADY`).
2. Paket yüzeyi: `_sync_snapshot.ps1` — kopyalar.
3. 195: `_deploy_195.ps1` — repo `MIGRATION_SCR_20260708` ↔ sunucu aynı yol adı.
4. Repo kök: `VERSION_LOG.md`, `INDEX.md`.
