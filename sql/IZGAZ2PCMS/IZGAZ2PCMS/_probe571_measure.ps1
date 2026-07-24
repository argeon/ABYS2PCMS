$ErrorActionPreference = 'Continue'
$server = '172.16.1.192'
$auth = @('-S', $server, '-d', 'energy', '-U', 'pcms', '-P', '12345', '-C')

function Scalar([string]$q) {
  $o = & sqlcmd @auth -h-1 -W -Q "SET NOCOUNT ON; $q"
  ($o | Where-Object { $_ -match '\S' } | Select-Object -First 1).ToString().Trim()
}

sqlcmd @auth -Q "KILL 87; KILL 88;" | Out-Null
Start-Sleep 3

$t0 = Get-Date
$inv0 = [int64](Scalar "SELECT COUNT_BIG(*) FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)")
$log0 = [int64](Scalar "SELECT ISNULL(MAX(LOG_ID),0) FROM dbo.MIG_BATCH_LOG WITH (NOLOCK) WHERE MIGRATION_CODE='LS_005_01_INVOICE'")
Write-Host "PROBE t0=$($t0.ToString('o')) inv0=$inv0 log0=$log0"

$ok = 0
while (((Get-Date) - $t0).TotalSeconds -lt 300 -and $ok -lt 5) {
  Start-Sleep 12
  $ok = [int](Scalar "SELECT COUNT(*) FROM dbo.MIG_BATCH_LOG WITH (NOLOCK) WHERE MIGRATION_CODE='LS_005_01_INVOICE' AND LOG_ID>$log0 AND STATUS='OK'")
  $sec = [math]::Round(((Get-Date) - $t0).TotalSeconds, 0)
  Write-Host "elapsed=${sec}s new_ok_batches=$ok"
}

$inv1 = [int64](Scalar "SELECT COUNT_BIG(*) FROM dbo.LS_005_01_INVOICE WITH (NOLOCK)")
$wall = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
$delta = $inv1 - $inv0
$rate = if ($wall -gt 0) { [math]::Round($delta / $wall, 1) } else { 0 }
$etaHr = if ($rate -gt 0) { [math]::Round((73499947 - $inv1) / $rate / 3600, 2) } else { -1 }

Write-Host "==== RESULT ===="
Write-Host "wall_sec=$wall inv_delta=$delta rate_per_sec=$rate eta_inv_hr=$etaHr"
Write-Host "baseline_jul18=73499929 rows in 3200s (~22968/s, ~53 min)"

sqlcmd @auth -W -Q @"
SET NOCOUNT ON;
SELECT TOP 10 BATCH_NO, ROW_COUNT, ELAPSED_MS, STATUS, LOGGED_AT
FROM dbo.MIG_BATCH_LOG WITH (NOLOCK)
WHERE MIGRATION_CODE='LS_005_01_INVOICE' AND LOG_ID > $log0
ORDER BY LOG_ID;
SELECT CASE WHEN EXISTS (
  SELECT 1 FROM sys.dm_exec_requests r
  CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
  WHERE t.text LIKE '%SHRINK%' OR t.text LIKE '%SpaceReclaim%'
) THEN 'SHRINK_STILL_RUNNING' ELSE 'NO_SHRINK' END AS shrink_status;
"@
