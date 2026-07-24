<#
.SYNOPSIS
  Thin Stage Ops orchestrator — runs existing CTAS/SP scripts via Invoke-StageOne.ps1.
  CTAS supports -MaxParallel workers. Does not modify script contents.
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('ctas', 'transfer-sql', 'prod-sql')][string]$Surface,
    [Parameter(Mandatory = $true)][string]$StageIds,
    [int]$MaxParallel = 2,
    [switch]$Resume,
    [switch]$HardReset,
    [switch]$DryRun,
    [string]$RunUuid = ([guid]::NewGuid().ToString('N')),
    [string]$ConfigPath = ""
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ConfigPath) { $ConfigPath = Join-Path $here 'stage_ops.config.json' }

$manifestName = switch ($Surface) {
    'ctas' { 'ctas_manifest.json' }
    'transfer-sql' { 'transfer_sql_manifest.json' }
    'prod-sql' { 'prod_sql_manifest.json' }
}
$manifest = Get-Content (Join-Path $here $manifestName) -Raw | ConvertFrom-Json
$wanted = $StageIds.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$stages = @($manifest.stages | Where-Object { $wanted -contains $_.id } | Sort-Object sortOrder)
if ($stages.Count -eq 0) { throw "No matching stages for: $StageIds" }

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$artRoot = Join-Path (Join-Path (Join-Path $here $config.artifactsRoot) $Surface) $RunUuid
New-Item -ItemType Directory -Force -Path $artRoot | Out-Null

$parallel = if ($Surface -eq 'ctas') { [Math]::Max(1, $MaxParallel) } else { 1 }
Write-Host "StageOps surface=$Surface count=$($stages.Count) parallel=$parallel run=$RunUuid"

$oneScript = Join-Path $here 'Invoke-StageOne.ps1'
$summary = [System.Collections.Generic.List[object]]::new()

if ($parallel -eq 1) {
    foreach ($stage in $stages) {
        Write-Host "START $($stage.id)"
        $json = $stage | ConvertTo-Json -Compress -Depth 8
        $out = & $oneScript -Surface $Surface -StageJson $json -ConfigPath $ConfigPath -RunUuid $RunUuid -Resume:$Resume -HardReset:$HardReset -DryRun:$DryRun
        $parsed = $out | ConvertFrom-Json
        $summary.Add($parsed)
        Write-Host "$($parsed.status) $($stage.id) $($parsed.elapsedMs)ms"
    }
}
else {
    $pool = [runspacefactory]::CreateRunspacePool(1, $parallel)
    $pool.Open()
    $workers = @()
    foreach ($stage in $stages) {
        Write-Host "QUEUE $($stage.id)"
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        $json = $stage | ConvertTo-Json -Compress -Depth 8
        [void]$ps.AddScript({
            param($oneScript, $Surface, $json, $ConfigPath, $RunUuid, $Resume, $HardReset, $DryRun)
            $raw = & $oneScript -Surface $Surface -StageJson $json -ConfigPath $ConfigPath -RunUuid $RunUuid -Resume:$Resume -HardReset:$HardReset -DryRun:$DryRun 2>&1 | Out-String
            # Last JSON line
            $lines = $raw -split "`n" | Where-Object { $_.Trim().StartsWith('{') }
            if ($lines) { $lines[-1].Trim() } else { '{"status":"Failed","exitCode":1}' }
        }).AddArgument($oneScript).AddArgument($Surface).AddArgument($json).AddArgument($ConfigPath).AddArgument($RunUuid).AddArgument([bool]$Resume).AddArgument([bool]$HardReset).AddArgument([bool]$DryRun)
        $workers += [PSCustomObject]@{ Pipe = $ps; Handle = $ps.BeginInvoke(); StageId = $stage.id }
    }
    foreach ($w in $workers) {
        $raw = $w.Pipe.EndInvoke($w.Handle) | Out-String
        $w.Pipe.Dispose()
        try {
            $summary.Add(($raw.Trim() | ConvertFrom-Json))
        }
        catch {
            $summary.Add([pscustomobject]@{ stageId = $w.StageId; status = 'Failed'; exitCode = 1; elapsedMs = 0 })
        }
        Write-Host "DONE $($w.StageId)"
    }
    $pool.Close()
    $pool.Dispose()
}

$summaryPath = Join-Path $artRoot 'run_summary.json'
($summary | ConvertTo-Json -Depth 6) | Set-Content -Path $summaryPath -Encoding UTF8
Write-Host "Summary: $summaryPath"
$failed = @($summary | Where-Object { $_.status -ne 'Done' }).Count
exit $(if ($failed -gt 0) { 1 } else { 0 })
