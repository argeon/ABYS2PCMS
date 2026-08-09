# CTAS full backup — 20260809_CTAS_PRE_IX_RULE

**Pre-change snapshot** (195 senkron kaynak dahil) — terminal-DUMP no-INDEX/no-STATS kuralı uygulanmadan hemen önce.

Contents:
- `oracleCTAS3007/` — canlı CTAS omurga
- `oracleCTAS/` — prodREADY + legacy CTAS
- `20260708_CTAS/` — o anki snapshot CTAS kopyası

Restore (örnek):

```powershell
$B = '...\BACKUP'
$S = Join-Path $B '20260809_CTAS_PRE_IX_RULE'
Remove-Item (Join-Path $B 'oracleCTAS3007') -Recurse -Force
Remove-Item (Join-Path $B 'oracleCTAS') -Recurse -Force
Copy-Item (Join-Path $S 'oracleCTAS3007') (Join-Path $B 'oracleCTAS3007') -Recurse
Copy-Item (Join-Path $S 'oracleCTAS') (Join-Path $B 'oracleCTAS') -Recurse
```
