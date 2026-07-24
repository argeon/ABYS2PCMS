# Live tracker: continue_from_576 (576→611→613→590→597)
param(
  [string]$LogPattern = 'continue_576_*.log',
  [string]$OutFile = (Join-Path $PSScriptRoot 'PIPELINE_LIVE.txt'),
  [int]$IntervalSec = 10
)

$ErrorActionPreference = 'SilentlyContinue'
$dir = $PSScriptRoot

function Get-TailLine([string]$path) {
  if (-not (Test-Path $path)) { return $null }
  $lines = Get-Content $path -Tail 30
  ($lines | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
}

function Get-Phase([string]$last) {
  if ($last -match 'ALL DONE') { return 'DONE' }
  if ($last -match '597 ') { return '597_TAHSILAT' }
  if ($last -match '590 ') { return '590_EKSILTEN' }
  if ($last -match '613 ') { return '613_NORMALIZE' }
  if ($last -match '611 ') { return '611_INSTALLMENT' }
  if ($last -match '576 ') { return '576_POST_INDEX' }
  return 'RUNNING'
}

while ($true) {
  $log = Get-ChildItem -Path $dir -Filter $LogPattern | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $sql = Get-Process sqlcmd -ErrorAction SilentlyContinue | Sort-Object StartTime -Descending | Select-Object -First 3
  $alive = [bool]($sql)
  $last = if ($log) { Get-TailLine $log.FullName } else { '(no log)' }
  $phase = Get-Phase $last
  $known = if (Test-Path (Join-Path $dir 'PIPELINE_KNOWN_ISSUES.txt')) { 'see PIPELINE_KNOWN_ISSUES.txt' } else { '' }

  @(
    "UPDATED=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "PHASE=$phase"
    "SQLCMD_ALIVE=$alive"
    "LOG=$($log.FullName)"
    "LOG_LAST=$last"
    "DEFERRED=$known"
    "NEXT=576→611→613→590→597 (575 HARD_RESET yok)"
  ) | Set-Content -Path $OutFile -Encoding UTF8

  Start-Sleep -Seconds $IntervalSec
}
