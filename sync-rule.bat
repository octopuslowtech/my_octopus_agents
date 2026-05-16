@echo off
where wt >nul 2>nul
if %errorlevel%==0 (
    if "%WT_SESSION%"=="" (
        wt -d "%~dp0" cmd /k "chcp 65001 >nul && powershell -ExecutionPolicy Bypass -File \"%~dp0sync-rule.ps1\" && echo. && pause"
        exit /b
    )
)
chcp 65001 >nul
powershell -ExecutionPolicy Bypass -File "%~dp0sync-rule.ps1" %*
echo.
pause
