# Anlik takip — SQL yok (kilitte takilmaz). Her 10 sn PIPELINE_LIVE.txt
# Kaynak: process + log tail + timing dosyalari
$ErrorActionPreference = 'Continue'
$logDir = 'c:\Users\HW5536\source\repos\Migratorv0\sql\IZGAZ2PCMS\IZGAZ2PCMS'
$live = Join-Path $logDir 'PIPELINE_LIVE.txt'
$pid575 = 134532
$pid582 = 85304

function Tail1([string]$path) {
  if (-not (Test-Path $path)) { return '-' }
  try { return ((Get-Content $path -Tail 1 -ErrorAction Stop) + '').Trim() } catch { return '-' }
}
function TailMatch([string]$path, [string]$pattern, [int]$n = 40) {
  if (-not (Test-Path $path)) { return '-' }
  try {
    $hit = Get-Content $path -Tail $n -ErrorAction Stop | Where-Object { $_ -match $pattern } | Select-Object -Last 1
    return (($hit + '').Trim())
  } catch { return '-' }
}

while ($true) {
  $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $p575 = Get-Process -Id $pid575 -ErrorAction SilentlyContinue
  $p582 = Get-Process -Id $pid582 -ErrorAction SilentlyContinue
  $a575 = [bool]$p575
  $a582 = [bool]$p582

  $log575 = Get-ChildItem (Join-Path $logDir '575_run_*.log') -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $path575 = if ($log575) { $log575.FullName } else { '' }
  $path582 = Join-Path $logDir '581_resume_20260723_055423.log'

  $batch575 = TailMatch $path575 'Batch '
  $done575 = TailMatch $path575 '575 DONE|576 DONE|DEBT_PT'
  $batch582 = TailMatch $path582 'Batch |REBUILD|CREATE |POST_INDEX|582 DONE|SP_MIG_INVLINES_POST'
  $err575 = TailMatch $path575 'Msg |Error|failure'
  $err582 = TailMatch $path582 'Msg |Error|failure|Communication link'

  $age575 = if ($log575) { [math]::Round(((Get-Date) - $log575.LastWriteTime).TotalSeconds) } else { -1 }
  $age582 = if (Test-Path $path582) { [math]::Round(((Get-Date) - (Get-Item $path582).LastWriteTime).TotalSeconds) } else { -1 }

  $phase = if ($a575 -and $a582) { '575_AND_582_PARALLEL' }
           elseif ($a575) { '575_RUNNING' }
           elseif ($a582) { '582_RUNNING' }
           else { 'PROCESSES_EXITED' }

  # progress hint from last Batch N
  $hint575 = '-'
  if ($batch575 -match 'Batch\s+(\d+)') { $hint575 = "batch=$($Matches[1]) log_age=${age575}s" }
  elseif ($done575 -and $done575 -ne '-') { $hint575 = "DONE_SIGNAL: $done575" }
  elseif ($a575) { $hint575 = "alive log_age=${age575}s (henuz Batch yok / HARD_RESET veya lock?)" }

  $hint582 = if ($a582) { "alive log_age=${age582}s" } else { 'exited' }
  if ($batch582 -ne '-') { $hint582 = "$hint582 | $batch582" }

  @(
    "UPDATED=$now",
    "PHASE=$phase",
    "",
    "=== 575 DEBT ===",
    "PID=$pid575 alive=$a575",
    "PROGRESS=$hint575",
    "LOG_LAST=$(Tail1 $path575)",
    "LOG_FILE=$(if($path575){$path575}else{'-'})",
    "",
    "=== 582 INVLINES POST INDEX ===",
    "PID=$pid582 alive=$a582",
    "PROGRESS=$hint582",
    "LOG_LAST=$(Tail1 $path582)",
    "LOG_FILE=$path582",
    "",
    "=== HIZLI KOMUT ===",
    "Get-Content ...\PIPELINE_LIVE.txt",
    "Get-Content ...\575_run_*.log -Tail 20",
    "Get-Content ...\581_resume_20260723_055423.log -Tail 20",
    "sqlcmd ... -i adim_status_now.sql",
    "REFRESH=10 sn (otomatik)"
  ) | Set-Content -Encoding utf8 $live

  if ($phase -eq 'PROCESSES_EXITED') {
    Start-Sleep 15
    if (-not (Get-Process -Id $pid575 -EA SilentlyContinue) -and -not (Get-Process -Id $pid582 -EA SilentlyContinue)) {
      @(
        "UPDATED=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "PHASE=BOTH_EXITED",
        "DETAIL=sqlcmd processleri kapandi — loglardan sonuc kontrol et",
        "LOG_575_LAST=$(Tail1 $path575)",
        "LOG_582_LAST=$(Tail1 $path582)",
        "NEXT=575 OK ise 611; 582 OK ise INVLINES index dogrula"
      ) | Set-Content -Encoding utf8 $live
      break
    }
  }

  Start-Sleep 10
}
