# IZGAZ2PCMS SQL paketi

**Harita:** [`CANONICAL/README.md`](CANONICAL/README.md)

| Klasör | Rol |
|--------|-----|
| `prodEnergy/` | Canlı düzenleme (kaynak) |
| `MIGRATION_SCR_20260708/` | Temiz paket = 195 (`CTAS`/`ENERGY`/`REPORT`) |
| `BACKUP/oracleCTAS3007/` | CTAS omurga kaynağı |
| `CANONICAL/` | Tek doğru yol listesi |

195: `C:\www\MIGRATION_SCR_20260708` ↔ repo `MIGRATION_SCR_20260708/`  
Sync: `MIGRATION_SCR_20260708/_sync_snapshot.ps1` → `_deploy_195.ps1`
