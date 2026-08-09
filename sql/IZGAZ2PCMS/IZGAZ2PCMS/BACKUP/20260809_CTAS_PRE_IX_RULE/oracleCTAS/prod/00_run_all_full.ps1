# 00_run_all_full.ps1 — FULL CTAS 01..05 + gate 06 (RunTah sirali)
# sqlplus yerine JDBC runner kullanir; hata olursa durur.
# Kullanim (prod klasorunden):
#   .\00_run_all_full.ps1

$ErrorActionPreference = 'Stop'
$prod = $PSScriptRoot
$probe = Join-Path $prod '..\..\oracleControl\_probe_tah' | Resolve-Path
$jar = Get-ChildItem $probe -Filter 'ojdbc*.jar' | Select-Object -First 1
if (-not $jar) { throw "ojdbc jar bulunamadi: $probe" }

$files = @(
  '01_LS_INVOICE__full.sql',
  '02_LS_INVLINES__full.sql',
  '03_LS_EKSILTEN_OVERLAY__full.sql',
  '04_LS_TAHSILAT_OVERLAY__full.sql',
  '05_LS_TAHSILAT_LOG__full.sql',
  '06_adim5_tahsilat_gate_full.sql'
)

Push-Location $probe
try {
  if (-not (Test-Path 'RunTah.class')) {
    javac -cp $jar.FullName RunTah.java
  }
  $i = 0
  foreach ($f in $files) {
    $i++
    $path = Join-Path $prod $f
    if (-not (Test-Path $path)) { throw "Eksik: $path" }
    Write-Host ("`n========== {0}/{1} {2} ==========" -f $i, $files.Count, $f) -ForegroundColor Cyan
    java -cp ".;$($jar.FullName)" RunTah $path
    if ($LASTEXITCODE -ne 0) { throw "FAILED: $f (exit=$LASTEXITCODE)" }
  }
  Write-Host "`n========== 00_run_all_full DONE ==========" -ForegroundColor Green
}
finally {
  Pop-Location
}
