#Requires -Version 5.1
<#
  Repo MIGRATION_SCR_20260708 → 195 ayni yapi (CTAS + ENERGY + REPORT only).

  Kaynak (repo): ...\MIGRATION_SCR_20260708\{CTAS,ENERGY,REPORT}
  Hedef (195):   \\172.16.1.195\C$\www\MIGRATION_SCR_20260708
                 (= C:\www\MIGRATION_SCR_20260708)

  - CTAS/ENERGY/REPORT: robocopy /MIR
  - SRC_* ve diger yan paketler silinir
  - Kaynak duzenleme: prodEnergy (+ oracleCTAS*); burasi kopya

  Kullanim:
    pwsh -File sql\IZGAZ2PCMS\IZGAZ2PCMS\MIGRATION_SCR_20260708\_deploy_195.ps1
    pwsh -File ...\_deploy_195.ps1 -WhatIf
    pwsh -File ...\_deploy_195.ps1 -SkipSync
#>
param(
    [string]$Dest = '\\172.16.1.195\C$\www\MIGRATION_SCR_20260708',
    [switch]$WhatIf,
    [switch]$SkipSync
)

$ErrorActionPreference = 'Stop'
$Snap = $PSScriptRoot

if (-not $SkipSync) {
    Write-Host ">> snapshot yenile: _sync_snapshot.ps1"
    & (Join-Path $Snap '_sync_snapshot.ps1')
}

foreach ($must in @('CTAS', 'ENERGY', 'REPORT', 'README.md', 'MANIFEST_CTAS.txt', 'MANIFEST_ENERGY.txt', 'MANIFEST_REPORT.txt')) {
    $p = Join-Path $Snap $must
    if (-not (Test-Path -LiteralPath $p)) { throw "Snapshot eksik: $must" }
}

$parent = Split-Path $Dest -Parent
if (-not (Test-Path -LiteralPath $parent)) {
    throw "Hedef ust yol yok / erisilemiyor: $parent"
}
if (-not (Test-Path -LiteralPath $Dest)) {
    if ($WhatIf) {
        Write-Host "WhatIf: New-Item $Dest"
    } else {
        New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    }
}

function Invoke-RoboDir([string]$Src, [string]$Dst) {
    $args = @($Src, $Dst, '/MIR', '/R:2', '/W:2', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($WhatIf) { $args += '/L' }
    Write-Host ("robocopy " + ($args -join ' '))
    & robocopy @args
    $code = $LASTEXITCODE
    if ($code -ge 8) { throw "robocopy failed exit=$code src=$Src dst=$Dst" }
}

$allowedDirs = @('CTAS', 'ENERGY', 'REPORT')
$allowedFiles = @(
    'README.md',
    'MANIFEST_CTAS.txt',
    'MANIFEST_ENERGY.txt',
    'MANIFEST_REPORT.txt',
    '_sync_snapshot.ps1',
    '_deploy_195.ps1'
)

foreach ($dir in $allowedDirs) {
    Invoke-RoboDir (Join-Path $Snap $dir) (Join-Path $Dest $dir)
}

foreach ($f in $allowedFiles) {
    $src = Join-Path $Snap $f
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dst = Join-Path $Dest $f
    Write-Host "copy $f"
    if (-not $WhatIf) {
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}

if (Test-Path -LiteralPath $Dest) {
    Get-ChildItem -LiteralPath $Dest -Force | ForEach-Object {
        if ($_.PSIsContainer) {
            if ($allowedDirs -notcontains $_.Name) {
                Write-Host "REMOVE dirty dir: $($_.Name)"
                if (-not $WhatIf) { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
            }
        } else {
            if ($allowedFiles -notcontains $_.Name) {
                Write-Host "REMOVE dirty file: $($_.Name)"
                if (-not $WhatIf) { Remove-Item -LiteralPath $_.FullName -Force }
            }
        }
    }
}

$ctasN = (Get-ChildItem (Join-Path $Dest 'CTAS') -File -ErrorAction SilentlyContinue).Count
$enN = (Get-ChildItem (Join-Path $Dest 'ENERGY') -File -ErrorAction SilentlyContinue).Count
$repN = (Get-ChildItem (Join-Path $Dest 'REPORT') -File -ErrorAction SilentlyContinue).Count
$top = @(Get-ChildItem -LiteralPath $Dest -Force | Select-Object -ExpandProperty Name | Sort-Object)
Write-Host "OK deploy Dest=$Dest"
Write-Host "  CTAS=$ctasN ENERGY=$enN REPORT=$repN"
Write-Host ("  top-level: " + ($top -join ', '))

$allowed = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]($allowedDirs + $allowedFiles),
    [StringComparer]::OrdinalIgnoreCase
)
$bad = @($top | Where-Object { -not $allowed.Contains($_) })
if ($bad.Count -gt 0) {
    throw "Temizlik basarisiz; kalan kirli: $($bad -join ', ')"
}
