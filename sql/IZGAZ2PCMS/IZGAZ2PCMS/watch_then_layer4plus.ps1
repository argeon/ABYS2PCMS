# Wait for 581+582 (sqlcmd PID), then start layer4+.
# Updates PIPELINE_LIVE.txt every poll for instant checks.
$ErrorActionPreference = 'Continue'
$logDir = 'c:\Users\HW5536\source\repos\Migratorv0\sql\IZGAZ2PCMS\IZGAZ2PCMS'
$live = Join-Path $logDir 'PIPELINE_LIVE.txt'
$auth = @('-S','172.16.1.192','-d','energy','-U','pcms','-P','12345','-C')
$pid581 = 85304
$srcIl = 352853289

function Write-Live([string]$phase, [string]$detail) {
  $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $mig = & sqlcmd @auth -h-1 -W -Q "SET NOCOUNT ON; SELECT TOP 1 MIGRATION_CODE+'|'+STATUS+'|'+ISNULL(CAST(INSERTED_COUNT AS VARCHAR(20)),'?')+'/'+ISNULL(CAST(SOURCE_ROW_COUNT AS VARCHAR(20)),'?') FROM dbo.MIG_RUN WITH (NOLOCK) WHERE MIGRATION_CODE='LS_005_01_INVLINES' ORDER BY STARTED_AT DESC;"
  $migLine = ($mig | Where-Object { $_ -match '\S' } | Select-Object -First 1)
  $batch = & sqlcmd @auth -h-1 -W -Q "SET NOCOUNT ON; SELECT TOP 1 CAST(BATCH_NO AS VARCHAR(20))+' rows='+CAST(ROW_COUNT AS VARCHAR(20))+' ms='+CAST(ELAPSED_MS AS VARCHAR(20))+' @'+CONVERT(VARCHAR(19),LOGGED_AT,120) FROM dbo.MIG_BATCH_LOG WITH (NOLOCK) WHERE MIGRATION_CODE='LS_005_01_INVLINES' ORDER BY LOG_ID DESC;"
  $batchLine = ($batch | Where-Object { $_ -match '\S' } | Select-Object -First 1)
  @(
    "UPDATED=$now",
    "PHASE=$phase",
    "DETAIL=$detail",
    "INVLINES_RUN=$migLine",
    "LAST_BATCH=$batchLine",
    "PID_581=$pid581 alive=$([bool](Get-Process -Id $pid581 -ErrorAction SilentlyContinue))",
    "CHECK=sqlcmd ... -i adim_status_now.sql   OR  Get-Content PIPELINE_LIVE.txt",
    "LOG_581=581_resume_20260723_055423.log"
  ) | Set-Content -Encoding utf8 $live
}

Write-Live 'WAIT_581' 'Waiting for 581 resume + 582 to finish'

$done581 = $false
while (-not $done581) {
  $procAlive = [bool](Get-Process -Id $pid581 -ErrorAction SilentlyContinue)
  $st = & sqlcmd @auth -h-1 -W -Q "SET NOCOUNT ON; SELECT TOP 1 STATUS+'|'+ISNULL(CAST(INSERTED_COUNT AS VARCHAR(20)),'0') FROM dbo.MIG_RUN WITH (NOLOCK) WHERE MIGRATION_CODE='LS_005_01_INVLINES' ORDER BY STARTED_AT DESC;"
  $stLine = (($st | Where-Object { $_ -match '\S' } | Select-Object -First 1) + '')
  $ins = 0
  if ($stLine -match '\|(\d+)$') { $ins = [int64]$Matches[1] }
  $logTail = ''
  $log581 = Join-Path $logDir '581_resume_20260723_055423.log'
  if (Test-Path $log581) { $logTail = (Get-Content $log581 -Tail 3) -join ' | ' }

  if (-not $procAlive) {
    if ($logTail -match '582 DONE|LAYER 3/8 DONE|ALL DONE|ENERGY_IL' -or $ins -ge $srcIl) {
      $done581 = $true
      Write-Live '581_582_DONE' "ins=$ins log=$logTail"
      break
    }
    # process died early?
    if ($ins -lt $srcIl -and $logTail -match 'Communication link failure|Tcp Provider|Msg \d+') {
      Write-Live '581_FAILED' "Process dead early ins=$ins — manual resume needed. $logTail"
      exit 2
    }
    # process gone but maybe 582 still running under different session — wait for COMPLETED
    if ($stLine -match '^COMPLETED' -and $ins -ge $srcIl) {
      Start-Sleep 30
      $done581 = $true
      Write-Live '581_DONE_WAIT_582' $stLine
      break
    }
  }

  $pct = if ($srcIl -gt 0) { [math]::Round(100.0 * $ins / $srcIl, 1) } else { 0 }
  $etaMin = if ($ins -gt 128400000) {
    $sec = ((Get-Date) - [datetime]'2026-07-23 05:54:24').TotalSeconds
    $rate = ($ins - 128400000) / [math]::Max($sec, 1)
    if ($rate -gt 0) { [math]::Round(($srcIl - $ins) / $rate / 60.0, 1) } else { '?' }
  } else { '?' }
  Write-Live 'WAIT_581' "ins=$ins pct=$pct eta_min=$etaMin procAlive=$procAlive"
  Start-Sleep 45
}

# Start layer4+
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$log4 = Join-Path $logDir "layer4plus_$stamp.log"
$meta4 = Join-Path $logDir "layer4plus_$stamp.timing.txt"
$sql4 = Join-Path $logDir 'adim_layer4plus_continue.sql'
"START=$(Get-Date -Format o)" | Set-Content -Encoding utf8 $meta4
"LOG=$log4" | Add-Content $meta4
Write-Live 'START_LAYER4+' "log=$log4"
$args4 = @('-S','172.16.1.192','-d','energy','-U','pcms','-P','12345','-C','-i',$sql4,'-o',$log4)
$p = Start-Process -FilePath sqlcmd -ArgumentList $args4 -PassThru -NoNewWindow
"PID=$($p.Id)" | Add-Content $meta4
Write-Live 'LAYER4+_RUNNING' "PID=$($p.Id) log=$log4"

Wait-Process -Id $p.Id
$exit = $p.ExitCode
"END=$(Get-Date -Format o)" | Add-Content $meta4
"EXIT=$exit" | Add-Content $meta4
Write-Live 'PIPELINE_DONE' "layer4plus exit=$exit log=$log4"
exit $exit
