#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$InstallDir = "$env:ProgramFiles\ServicesDev",
    [string[]]$ServiceNames
)
$ErrorActionPreference = 'Stop'
$watchdogService = 'ServicesDev'
$legacyService = 'ContpaqiWatchdog'

if (-not $ServiceNames) {
    $ServiceNames = Get-CimInstance Win32_Service |
        Where-Object {
            $_.DisplayName -match '(?i)CONTPAQ|Compac|AuthServer' -and
            $_.Name -notin @($watchdogService, $legacyService) -and
            $_.Name -notmatch '(?i)MSSQL|SQLAgent|SQLBrowser|SQLWriter' -and
            $_.DisplayName -notmatch '(?i)SQL\s*Server|SQL\s*Agent|SQL\s*Browser|SQL\s*Writer'
        } |
        Sort-Object DisplayName |
        Select-Object -ExpandProperty Name
}
if (-not $ServiceNames) { throw 'No se detectaron servicios de CONTPAQi/Compac/AuthServer. Use -ServiceNames nombre1,nombre2.' }

Write-Host 'Servicios internos que serán vigilados:' -ForegroundColor Cyan
$ServiceNames | ForEach-Object { Get-Service -Name $_ | Format-Table Name, DisplayName, Status -AutoSize }
$answer = Read-Host 'Escriba SI para instalar'
if ($answer -cne 'SI') { throw 'Instalación cancelada.' }

if (Get-Service -Name $legacyService -ErrorAction SilentlyContinue) {
    Write-Host 'Actualizando la version anterior ContpaqiWatchdog...' -ForegroundColor Yellow
    Stop-Service -Name $legacyService -Force -ErrorAction SilentlyContinue
    sc.exe delete $legacyService | Out-Null
    Start-Sleep -Seconds 2
}

if (Get-Service -Name $watchdogService -ErrorAction SilentlyContinue) {
    Stop-Service -Name $watchdogService -Force -ErrorAction SilentlyContinue
    sc.exe delete $watchdogService | Out-Null
    Start-Sleep -Seconds 2
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path "$PSScriptRoot\app\*" -Destination $InstallDir -Recurse -Force
$config = Get-Content "$PSScriptRoot\watchdog.json" -Raw | ConvertFrom-Json
$config.ServiceNames = @($ServiceNames)
$config | ConvertTo-Json -Depth 5 | Set-Content "$InstallDir\watchdog.json" -Encoding UTF8

$exe = Join-Path $InstallDir 'ServicesDev.exe'
New-Service -Name $watchdogService -BinaryPathName ('"' + $exe + '"') -DisplayName 'ServicesDev - Monitor CONTPAQi' `
    -Description 'Vigila e inicia los servicios configurados de CONTPAQi.' -StartupType Automatic | Out-Null
sc.exe failure $watchdogService reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
sc.exe failureflag $watchdogService 1 | Out-Null
Start-Service $watchdogService
Write-Host "ServicesDev instalado y ejecutándose. Configuración: $InstallDir\watchdog.json" -ForegroundColor Green
