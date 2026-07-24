@echo off
REM Oracle to MSSQL Migration Tool - Startup Script (Windows Batch)
REM This script starts both Web UI and provides instructions for Engine

echo.
echo ===============================================
echo   Oracle to MSSQL Migration Tool
echo ===============================================
echo.

REM Check if dotnet is available
where dotnet >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] .NET SDK not found!
    echo Please install .NET 8 SDK from: https://dotnet.microsoft.com/download/dotnet/8.0
    pause
    exit /b 1
)

REM Build projects individually
echo [INFO] Building projects...
dotnet build MigrationShared\MigrationShared.csproj -c Release -v quiet -maxcpucount:1
dotnet build MigrationEngine\MigrationEngine.csproj -c Release -v quiet -maxcpucount:1
dotnet build Migratorv0\Migratorv0.csproj -c Release -v quiet -maxcpucount:1

if %errorlevel% neq 0 (
    echo [ERROR] Build failed!
    pause
    exit /b 1
)

echo [OK] All projects built successfully!
echo.

REM Start Web UI in new window
echo [INFO] Starting Web UI...
start "Migration Web UI" cmd /k "cd Migratorv0 && echo Web UI running on http://localhost:5000 && dotnet run --no-build -c Release"

timeout /t 3 /nobreak >nul

echo [OK] Web UI started!
echo.
echo ===============================================
echo   NEXT STEPS:
echo ===============================================
echo.
echo 1. Open browser: http://localhost:5000/wizard
echo 2. Configure migration in the wizard
echo 3. Follow wizard instructions to start Engine
echo.
echo    Dashboard: http://localhost:5000
echo    History:   http://localhost:5000/history
echo    Docs:      http://localhost:5000/architecture
echo.
echo ===============================================
echo.

REM Ask to open browser
set /p OPEN_BROWSER="Open browser automatically? (Y/n): "
if /i "%OPEN_BROWSER%"=="n" goto :skip_browser
if /i "%OPEN_BROWSER%"=="no" goto :skip_browser

timeout /t 2 /nobreak >nul
start http://localhost:5000/wizard

:skip_browser
echo.
echo [OK] System is ready!
echo     Press any key to exit...
echo.
pause >nul
