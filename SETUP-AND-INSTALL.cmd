@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SETUP-AND-INSTALL.ps1"
set RC=%ERRORLEVEL%
if not "%RC%"=="0" (
  echo.
  echo Installation failed. Exit code: %RC%
  pause
  exit /b %RC%
)
echo.
echo Installation completed successfully.
pause
