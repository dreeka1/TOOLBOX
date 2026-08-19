@echo off
title ServicesDev - Diagnostico CONTPAQi
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Diagnostico.ps1"
if errorlevel 1 (
  echo.
  echo No fue posible abrir el diagnostico.
  pause
)
