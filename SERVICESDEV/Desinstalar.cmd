@echo off
setlocal
title Desinstalador ServicesDev

fltmc >nul 2>&1
if errorlevel 1 (
    echo Solicitando permisos de administrador...
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Desinstalando ServicesDev...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1"
set "servicesdev_result=%errorlevel%"
echo.
if not "%servicesdev_result%"=="0" echo La desinstalacion termino con un error.
pause
exit /b %servicesdev_result%
