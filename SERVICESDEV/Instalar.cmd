@echo off
setlocal
title Instalador ServicesDev

fltmc >nul 2>&1
if errorlevel 1 (
    echo Solicitando permisos de administrador...
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Instalando ServicesDev...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
set "servicesdev_result=%errorlevel%"
echo.
if not "%servicesdev_result%"=="0" echo La instalacion termino con un error.
pause
exit /b %servicesdev_result%
