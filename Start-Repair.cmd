@echo off
setlocal
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 is required. Please install it from Microsoft's official website.
  pause
  exit /b 1
)
pwsh.exe -NoProfile -STA -WindowStyle Hidden -File "%~dp0Repair-Window.ps1"
if errorlevel 1 (
  echo Could not open the repair window. See README.zh-CN.md for downloaded-file instructions.
  pause
)
