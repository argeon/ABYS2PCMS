# Orchestrate 613 parallel workers then 590+597
param(
  [int]$WorkerCnt = 6,
  [string]$Server = '172.16.1.192',
  [string]$Db = 'energy',
  [string]$User = 'pcms',
  [string]$Pass = '12345'
)

$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$live = Join-Path $base 'PIPELINE_LIVE.txt'
$workerSql = Join-Path $base 'adim_613_parallel_worker.sql'
$procs = @()

function Set-Live([string]$phase, [string]$detail) {
  @(
    "UPDATED=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "PHASE=$phase"
    "DETAIL=$detail"
    "WORKERS=$WorkerCnt"
    "TS=$ts"
  ) | Set-Content -Path $live -Encoding UTF8
}

Set-Live '613_PARALLEL_START' "launching $WorkerCnt workers"

for ($w = 0; $w -lt $WorkerCnt; $w++) {
  $log = Join-Path $base ("613_w{0}_{1}.log" -f $w, $ts)
  $p = Start-Process -FilePath 'sqlcmd' -ArgumentList @(
    '-S', $Server, '-d', $Db, '-U', $User, '-P', $Pass, '-C',
    '-b', '-I', '-t', '0',
    '-v', "WORKER_ID=$w", '-v', "WORKER_CNT=$WorkerCnt",
    '-i', $workerSql,
    '-o', $log
  ) -WindowStyle Hidden -PassThru
  $procs += [pscustomobject]@{ Id = $p.Id; Worker = $w; Log = $log }
  Write-Host "STARTED worker=$w pid=$($p.Id) log=$log"
}

Set-Live '613_PARALLEL_RUNNING' (($procs | ForEach-Object { "w$($_.Worker)=$($_.Id)" }) -join '; ')

# Wait all
while ($true) {
  $alive = @()
  foreach ($x in $procs) {
    if (Get-Process -Id $x.Id -ErrorAction SilentlyContinue) { $alive += $x }
  }
  $done = $WorkerCnt - $alive.Count
  Set-Live '613_PARALLEL_RUNNING' "done=$done/$WorkerCnt alive=$($alive.Count)"
  if ($alive.Count -eq 0) { break }
  Start-Sleep -Seconds 15
}

# Check worker logs for errors
$failed = $false
foreach ($x in $procs) {
  $tail = Get-Content $x.Log -Tail 5 -ErrorAction SilentlyContinue
  if ($tail -match 'Msg \d+|Level 1[6-9]|Level 2') {
    Write-Host "WORKER $($x.Worker) may have errors: $($tail -join ' | ')"
    $failed = $true
  }
}

if ($failed) {
  Set-Live '613_PARALLEL_FAILED' 'check 613_w*_ logs'
  exit 1
}

Set-Live '613_DONE_START_590' 'all workers exited'

# 590 + 597
$cont = Join-Path $base "continue_590_597_$ts.sql"
@"
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Msg NVARCHAR(400), @t0 DATETIME2(3), @tAll DATETIME2(3)=SYSDATETIME();
SET @Msg = N'===== 590 EKSILTEN START =====';
RAISERROR('%s',0,1,@Msg) WITH NOWAIT;
SET @t0 = SYSDATETIME();
IF OBJECT_ID('energy.dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR','P') IS NOT NULL
   AND OBJECT_ID('izgazMGR.dbo.LS_OV_IADE_INVOICE','U') IS NOT NULL
  EXEC energy.dbo.SP_MIGRATE_EKSILTEN_OVERLAY_AGR @AGR_ID=NULL, @CLEAN=1, @DEBUG=1;
SET @Msg = N'===== 590 DONE sec=' + CAST(DATEDIFF(SECOND,@t0,SYSDATETIME()) AS VARCHAR(20)) + N' =====';
RAISERROR('%s',0,1,@Msg) WITH NOWAIT;

SET @Msg = N'===== 597 TAHSILAT START =====';
RAISERROR('%s',0,1,@Msg) WITH NOWAIT;
SET @t0 = SYSDATETIME();
IF OBJECT_ID('energy.dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR','P') IS NOT NULL
   AND OBJECT_ID('izgazMGR.dbo.LS_OV_PAY_PT','U') IS NOT NULL
  EXEC energy.dbo.SP_MIGRATE_TAHSILAT_OVERLAY_AGR @AGR_ID=NULL, @CLEAN=1, @DEBUG=1;
SET @Msg = N'===== 597 DONE sec=' + CAST(DATEDIFF(SECOND,@t0,SYSDATETIME()) AS VARCHAR(20)) + N' =====';
RAISERROR('%s',0,1,@Msg) WITH NOWAIT;
SET @Msg = N'===== 590+597 ALL DONE total_sec=' + CAST(DATEDIFF(SECOND,@tAll,SYSDATETIME()) AS VARCHAR(20)) + N' =====';
RAISERROR('%s',0,1,@Msg) WITH NOWAIT;
GO
"@ | Set-Content -Path $cont -Encoding UTF8

$log597 = Join-Path $base "continue_590_597_$ts.log"
Set-Live '590_597_RUNNING' $log597
sqlcmd -S $Server -d $Db -U $User -P $Pass -C -b -I -t 0 -i $cont -o $log597
$code = $LASTEXITCODE
Set-Live $(if ($code -eq 0) { 'PIPELINE_LAYER_DONE' } else { '590_597_FAILED' }) "exit=$code log=$log597"
exit $code
