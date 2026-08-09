# 00_run_all.ps1 — prod2 FULL CTAS (energy-yakin staged)
# sqlplus yerine JDBC RunTah; hata olursa durur.
# Kullanim (prod2 klasorunden):
#   .\00_run_all.ps1

$ErrorActionPreference = 'Stop'
$prod2 = $PSScriptRoot
$probe = Join-Path $prod2 '..\..\oracleControl\_probe_tah' | Resolve-Path
$jar = Get-ChildItem $probe -Filter 'ojdbc*.jar' | Select-Object -First 1
if (-not $jar) { throw "ojdbc jar bulunamadi: $probe" }

$files = @(
  '00_session_parallel.sql',
  '00_mig_param_full.sql',
  '10_stg_inv_acc_inc.sql',
  '11_ls_invoice.sql',
  '12_ls_invlines.sql',
  '13_ls_mig_agr_list.sql',
  '14_ls_debt_paytrans.sql',
  '20_ls_eksilten_overlay.sql',
  '27_gate_eksilten.sql',
  '30_ls_tahsilat_overlay.sql',
  '40_ls_tahsilat_log.sql',
  '41_gate_tahsilat.sql',
  '50_ls_afl_open_debt.sql'
)

Push-Location $probe
try {
  if (-not (Test-Path 'RunTah.class')) {
    javac -cp $jar.FullName RunTah.java
  }
  $i = 0
  foreach ($f in $files) {
    $i++
    $path = Join-Path $prod2 $f
    if (-not (Test-Path $path)) { throw "Eksik: $path" }
    Write-Host ("`n========== {0}/{1} {2} ==========" -f $i, $files.Count, $f) -ForegroundColor Cyan
    java -cp ".;$($jar.FullName)" RunTah $path
    if ($LASTEXITCODE -ne 0) { throw "FAILED: $f (exit=$LASTEXITCODE)" }
  }
  Write-Host "`n========== prod2 00_run_all DONE ==========" -ForegroundColor Green
}
finally {
  Pop-Location
}
