# Migratorv0 — sqlcmd ile T-SQL deploy (tum SP/setup)
# Kullanim: .\deploy.ps1 -Server "172.16.1.192" -User pcms -Password ***
# Tercih: tek dosya deploy_create_all_sps.sql (SSMS :r)
param(
    [Parameter(Mandatory = $true)]
    [string]$Server,
    [string]$Database = "energy",
    [switch]$UseIntegratedSecurity,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$entry = Join-Path $scriptDir "deploy_create_all_sps.sql"
if (-not (Test-Path $entry)) { throw "Bulunamadi: $entry" }

$sqlcmdArgs = @("-S", $Server, "-d", $Database, "-b", "-I", "-C")
if ($UseIntegratedSecurity) {
    $sqlcmdArgs += "-E"
} else {
    if (-not $User -or -not $Password) {
        throw "SQL auth icin -User ve -Password gerekli (veya -UseIntegratedSecurity)"
    }
    $sqlcmdArgs += @("-U", $User, "-P", $Password)
}

Push-Location $scriptDir
try {
    Write-Host ">>> deploy_create_all_sps.sql ($scriptDir)"
    & sqlcmd @sqlcmdArgs -i $entry
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed: deploy_create_all_sps.sql" }
    Write-Host "Deploy tamamlandi."
}
finally {
    Pop-Location
}
