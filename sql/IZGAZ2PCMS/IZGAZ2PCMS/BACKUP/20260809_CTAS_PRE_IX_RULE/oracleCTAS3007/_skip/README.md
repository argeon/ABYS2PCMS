# _skip — zincirde CALISTIRILMAZ

Bu klasör `00_run_all.sql` dışındaki SQL’lerdir.

| Dosya | Neden |
|-------|--------|
| `30_HOTFIX_ls_ov_tah_log_pay_before.sql` | Soft TAH_LOG / PAY_BEFORE_* — ENERGY okumaz |
| `40_ls_tahsilat_log.sql` | Eski TAH_LOG baseline (O30h tercih) |
| `31_ls_pay_alloc_waterfill__ONLY.sql` | Standalone waterfill; tam O30 yerine opsiyonel |
| `CHECK_QUERIES_ORACLE.sql` | Run sonrası spot (isteğe bağlı) |
| `diag_*.sql` | Teşhis; CTAS zinciri değil |

Çalıştırmak için (O30 sonrası):

```text
sqlplus ... @_skip/30_HOTFIX_ls_ov_tah_log_pay_before.sql
sqlplus ... @_skip/CHECK_QUERIES_ORACLE.sql
```
