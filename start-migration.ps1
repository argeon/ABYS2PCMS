# Oracle to MSSQL Migration Tool - Startup Script
# Bu script hem Web UI hem de Engine'i başlatır

Write-Host "🚀 Starting Oracle → MSSQL Migration Tool..." -ForegroundColor Green
Write-Host ""

# Check if dotnet is available
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "❌ .NET SDK bulunamadı! Lütfen .NET 8 SDK'yı yükleyin." -ForegroundColor Red
    Write-Host "   Download: https://dotnet.microsoft.com/download/dotnet/8.0" -ForegroundColor Yellow
    exit 1
}

# Get current directory
$rootDir = $PSScriptRoot
$webDir = Join-Path $rootDir "Migratorv0"
$engineDir = Join-Path $rootDir "MigrationEngine"

Write-Host "📁 Root Directory: $rootDir" -ForegroundColor Cyan
Write-Host ""

# Build projects individually (to avoid MSBuild node issue)
Write-Host "🔨 Building projects..." -ForegroundColor Yellow

dotnet build "$rootDir\MigrationShared\MigrationShared.csproj" -c Release -v quiet -maxcpucount:1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ MigrationShared build failed!" -ForegroundColor Red
    exit 1
}

dotnet build "$rootDir\MigrationEngine\MigrationEngine.csproj" -c Release -v quiet -maxcpucount:1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ MigrationEngine build failed!" -ForegroundColor Red
    exit 1
}

dotnet build "$rootDir\Migratorv0\Migratorv0.csproj" -c Release -v quiet -maxcpucount:1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ MigrationWeb build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ All projects built successfully!" -ForegroundColor Green
Write-Host ""

# Start Web UI in background
Write-Host "🌐 Starting Web UI..." -ForegroundColor Yellow
$webProcess = Start-Process powershell -ArgumentList @(
    "-NoExit",
    "-Command",
    "cd '$webDir'; Write-Host '🌐 Web UI starting on http://localhost:5000' -ForegroundColor Green; dotnet run --no-build -c Release"
) -PassThru

Start-Sleep -Seconds 3

Write-Host "✅ Web UI started (PID: $($webProcess.Id))" -ForegroundColor Green
Write-Host "   URL: http://localhost:5000" -ForegroundColor Cyan
Write-Host ""

# Instructions
Write-Host "📋 Next Steps:" -ForegroundColor Magenta
Write-Host "   1. Open browser: http://localhost:5000/wizard" -ForegroundColor White
Write-Host "   2. Configure your migration in the wizard" -ForegroundColor White
Write-Host "   3. When ready, the wizard will prompt you to start the Engine" -ForegroundColor White
Write-Host "   4. Or manually start Engine with: cd MigrationEngine; dotnet run" -ForegroundColor White
Write-Host ""
Write-Host "   Dashboard: http://localhost:5000" -ForegroundColor Cyan
Write-Host "   History:   http://localhost:5000/history" -ForegroundColor Cyan
Write-Host "   Docs:      http://localhost:5000/architecture" -ForegroundColor Cyan
Write-Host ""

Write-Host "💡 Tip: Keep this window open. Press Ctrl+C to stop the Web UI." -ForegroundColor Yellow
Write-Host ""

# Optional: Auto-open browser
$openBrowser = Read-Host "Open browser automatically? (Y/n)"
if ($openBrowser -eq "" -or $openBrowser -eq "Y" -or $openBrowser -eq "y") {
    Start-Sleep -Seconds 2
    Start-Process "http://localhost:5000/wizard"
}

# Keep script running
Write-Host "✅ System is ready!" -ForegroundColor Green
Write-Host "   Press Ctrl+C to stop..." -ForegroundColor Gray
Write-Host ""

# Wait for user to stop
try {
    Wait-Process -Id $webProcess.Id
} catch {
    Write-Host "Shutting down..." -ForegroundColor Yellow
}
