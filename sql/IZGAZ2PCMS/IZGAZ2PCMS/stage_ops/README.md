# Stage Ops — SSMS yerine ince orchestrator + 3 takip UI

Mevcut `oracleCTAS` / `SP_MIGRATE_*` / `MIG_LOG` koduna **dokunulmaz**. Bu klasör sadece çalıştırır, izler, arşivler.

## Bağlantılar (zorunlu)

Web: **`/stage-ops/connections`**

| Slot | Kullanım |
|------|----------|
| **CTAS · Oracle** | sqlplus `user/pass@host:1521/SERVICE` |
| **MSSQL Stage 1** | Kaynak (ör. `izgazMGR`) |
| **MSSQL Stage 2** | Hedef / SP runtime (ör. `energy`) |
| **PROD** | Opsiyonel PROD hedef |

Kayıt: `stage_ops.connections.json` — runner önce bunu okur.

## Web UI

| Route | Açıklama |
|-------|----------|
| `/stage-ops` | Hub |
| `/stage-ops/connections` | Bağlantı tanımları |
| `/stage-ops/ctas` | Oracle CTAS board |
| `/stage-ops/transfer-sql` | SP_MIGRATE + MIG_RUN |
| `/stage-ops/prod-sql` | PROD |
| `/stage-ops/results` | Run arşivi |

## CLI

```powershell
.\Invoke-StageOps.ps1 -Surface ctas -StageIds "CTAS_LS_AGREEMENT" -MaxParallel 2
```
