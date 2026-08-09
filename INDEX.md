# Migratorv0 — dizin indeksi

**Tek paket haritası:** [`sql/IZGAZ2PCMS/IZGAZ2PCMS/CANONICAL/README.md`](sql/IZGAZ2PCMS/IZGAZ2PCMS/CANONICAL/README.md)  
**Sürüm logu:** [`VERSION_LOG.md`](VERSION_LOG.md)

## Canlı

| Ne | Yol |
|----|-----|
| Energy | `sql/IZGAZ2PCMS/IZGAZ2PCMS/prodEnergy/` |
| CTAS omurga | `.../BACKUP/oracleCTAS3007/` |
| Snapshot | `.../BACKUP/20260708/` |
| Engine / UI | `MigrationEngine/`, `Migratorv0/`, `MigrationShared/` |

## Arşiv / çöp

| Ne | Yol |
|----|-----|
| Scratch | `_tmp/` |
| Log | `logs/` |
| Eski SQL | `sql/IZGAZ2PCMS/IZGAZ2PCMS/BACKUP/` (detay → CANONICAL) |
| Legacy MD | `docs/legacy/` |

## Kural

- Canlı düzenleme: **prodEnergy** + **oracleCTAS3007**.
- Snapshot: `BACKUP/20260708/_sync_snapshot.ps1`.
- Eski BACKUP silmeden önce: **CANONICAL**.
