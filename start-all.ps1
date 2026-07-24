# Start ALL - Web UI + Engine (Automatic)
# Bu script her iki projeyi de otomatik başlatır

Write-Host "🚀 Starting COMPLETE Migration System..." -ForegroundColor Green
Write-Host ""

$rootDir = $PSScriptRoot
$webDir = Join-Path $rootDir "Migratorv0"
$engineDir = Join-Path $rootDir "MigrationEngine"

# Build projects individually (to avoid MSBuild node issue)
Write-Host "🔨 Building projects..." -ForegroundColor Yellow

dotnet build "$rootDir\MigrationShared\MigrationShared.csproj" -c Release -v quiet -maxcpucount:1
dotnet build "$rootDir\MigrationEngine\MigrationEngine.csproj" -c Release -v quiet -maxcpucount:1
dotnet build "$rootDir\Migratorv0\Migratorv0.csproj" -c Release -v quiet -maxcpucount:1

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ All projects built successfully!" -ForegroundColor Green
Write-Host ""

# Start Web UI
Write-Host "🌐 Starting Web UI..." -ForegroundColor Yellow
$webProcess = Start-Process powershell -ArgumentList @(
    "-NoExit",
    "-Command",
    "cd '$webDir'; `$host.UI.RawUI.WindowTitle='Migration Web UI'; Write-Host '🌐 Web UI running on http://localhost:5000' -ForegroundColor Green; dotnet run --no-build -c Release"
) -PassThru

Start-Sleep -Seconds 3
Write-Host "✅ Web UI started (PID: $($webProcess.Id))" -ForegroundColor Green
Write-Host ""

# Check if appsettings.json exists in Engine
$engineConfig = Join-Path $engineDir "appsettings.json"
if (-not (Test-Path $engineConfig)) {
    Write-Host "⚠️  Engine configuration not found!" -ForegroundColor Yellow
    Write-Host "   Please configure migration first using the wizard:" -ForegroundColor White
    Write-Host "   → http://localhost:5000/wizard" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   After configuration, run this script again." -ForegroundColor White
    Write-Host ""
    
    # Open wizard
    Start-Sleep -Seconds 2
    Start-Process "http://localhost:5000/wizard"
    
    Write-Host "Press any key to continue (Web UI will keep running)..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

# Start Migration Engine
Write-Host "⚙️  Starting Migration Engine..." -ForegroundColor Yellow
$engineProcess = Start-Process powershell -ArgumentList @(
    "-NoExit",
    "-Command",
    "cd '$engineDir'; `$host.UI.RawUI.WindowTitle='Migration Engine'; Write-Host '⚙️  Migration Engine starting...' -ForegroundColor Green; dotnet run --no-build -c Release"
) -PassThru

Start-Sleep -Seconds 2
Write-Host "✅ Engine started (PID: $($engineProcess.Id))" -ForegroundColor Green
Write-Host ""

# All running
Write-Host "===============================================" -ForegroundColor Green
Write-Host "  🎉 ALL SYSTEMS RUNNING!" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Web UI:    http://localhost:5000 (PID: $($webProcess.Id))" -ForegroundColor Cyan
Write-Host "⚙️  Engine:    Running in separate window (PID: $($engineProcess.Id))" -ForegroundColor Cyan
Write-Host ""
Write-Host "📋 Quick Links:" -ForegroundColor Magenta
Write-Host "   Dashboard: http://localhost:5000" -ForegroundColor White
Write-Host "   History:   http://localhost:5000/history" -ForegroundColor White
Write-Host "   Wizard:    http://localhost:5000/wizard" -ForegroundColor White
Write-Host ""
Write-Host "💡 Both windows will stay open." -ForegroundColor Yellow
Write-Host "   Close windows manually to stop." -ForegroundColor Yellow
Write-Host ""

# Open dashboard
Start-Sleep -Seconds 3
Start-Process "http://localhost:5000"

Write-Host "✅ System ready! Monitor progress on Dashboard." -ForegroundColor Green
Write-Host "   This script will exit now." -ForegroundColor Gray
Write-Host ""
