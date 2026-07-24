@echo off
REM ============================================================
REM 597 resume ? SADECE SQL SERVER UZERINDE (PG-098 local sqlcmd)
REM Sira: 10 deploy 590 ? 20 deploy 597 ? (30 full run VEYA 40/50 resume)
REM Onkosul: rollback bitmis (eski BT100 session yok)
REM ============================================================
setlocal
set SERVER=localhost
set DB=energy
set USER=pcms
set PASS=12345
set SCRIPTDIR=%~dp0
set TS=%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%
set TS=%TS: =0%
set LOG=%SCRIPTDIR%run_597_resume_server_%TS%.log

echo [%date% %time%] 597 resume starting on %COMPUTERNAME% > "%LOG%"
echo LOG=%LOG%
sqlcmd -S %SERVER% -d %DB% -U %USER% -P %PASS% -C -I -t 0 -i "%SCRIPTDIR%40_adim_597_resume.sql" -o "%LOG%"
echo [%date% %time%] sqlcmd exit=%ERRORLEVEL% >> "%LOG%"
echo Done. exit=%ERRORLEVEL% log=%LOG%
endlocal
