[CmdletBinding()]
param(
    [string]$InstallDir = "$env:ProgramFiles\ServicesDev",
    [int]$RefreshSeconds = 5,
    [int]$LogLines = 12,
    [switch]$Once
)

$watchdogName = 'ServicesDev'
$RefreshSeconds = [Math]::Max(1, $RefreshSeconds)

function Write-State {
    param([string]$Text, [string]$State)
    $color = switch ($State) {
        'Running' { 'Green' }
        'StartPending' { 'Yellow' }
        'ContinuePending' { 'Yellow' }
        default { 'Red' }
    }
    Write-Host $Text -ForegroundColor $color
}

while ($true) {
    Clear-Host
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host '              SERVICESDEV - DIAGNOSTICO EN VIVO' -ForegroundColor Cyan
    Write-Host '                     Dev Derek Salinas' -ForegroundColor Magenta
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host ("Equipo: {0}    Actualizado: {1:yyyy-MM-dd HH:mm:ss}" -f $env:COMPUTERNAME, (Get-Date))
    Write-Host ("Carpeta: {0}" -f $InstallDir) -ForegroundColor DarkGray
    Write-Host ''

    $watchdog = Get-CimInstance Win32_Service -Filter "Name='$watchdogName'" -ErrorAction SilentlyContinue
    if ($watchdog) {
        Write-State ("Watchdog: {0,-10}  Inicio: {1,-12}  PID: {2}" -f $watchdog.State, $watchdog.StartMode, $watchdog.ProcessId) $watchdog.State
        if ($watchdog.ProcessId -gt 0) {
            $process = Get-Process -Id $watchdog.ProcessId -ErrorAction SilentlyContinue
            if ($process) {
                Write-Host ("Proceso iniciado: {0:yyyy-MM-dd HH:mm:ss}  Memoria: {1:N1} MB" -f $process.StartTime, ($process.WorkingSet64 / 1MB))
            }
        }
    } else {
        Write-Host 'Watchdog: NO INSTALADO' -ForegroundColor Red
    }

    Write-Host ''
    Write-Host 'SERVICIOS VIGILADOS' -ForegroundColor Cyan
    Write-Host ('{0,-28} {1,-13} {2}' -f 'Nombre interno', 'Estado', 'Nombre visible') -ForegroundColor DarkGray
    Write-Host ('-' * 76) -ForegroundColor DarkGray

    $configPath = Join-Path $InstallDir 'watchdog.json'
    $serviceNames = @()
    if (Test-Path $configPath) {
        try { $serviceNames = @((Get-Content $configPath -Raw | ConvertFrom-Json).ServiceNames) }
        catch { Write-Host "Configuracion invalida: $($_.Exception.Message)" -ForegroundColor Red }
    } else {
        Write-Host "No existe $configPath" -ForegroundColor Red
    }

    foreach ($name in $serviceNames) {
        $service = Get-CimInstance Win32_Service -Filter "Name='$($name.Replace("'", "''"))'" -ErrorAction SilentlyContinue
        if ($service) {
            Write-State ('{0,-28} {1,-13} {2}' -f $service.Name, $service.State, $service.DisplayName) $service.State
        } else {
            Write-Host ('{0,-28} {1,-13} {2}' -f $name, 'NO EXISTE', '-') -ForegroundColor Red
        }
    }
    if ($serviceNames.Count -eq 0) { Write-Host 'No hay servicios configurados.' -ForegroundColor Yellow }

    Write-Host ''
    Write-Host "ULTIMAS ACCIONES (ultimas $LogLines lineas)" -ForegroundColor Cyan
    Write-Host ('-' * 76) -ForegroundColor DarkGray
    $latestLog = Get-ChildItem (Join-Path $InstallDir 'logs\watchdog-*.log') -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestLog) {
        Get-Content $latestLog.FullName -Tail $LogLines | ForEach-Object {
            $color = if ($_ -match '\[ERROR\]') { 'Red' } elseif ($_ -match 'inicio correctamente') { 'Green' } else { 'Gray' }
            Write-Host $_ -ForegroundColor $color
        }
    } else {
        Write-Host 'Todavia no existe una bitacora.' -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host ("Actualizacion automatica cada {0} s | [Q] Salir | [R] Actualizar ahora" -f $RefreshSeconds) -ForegroundColor Yellow
    if ($Once) { return }
    $until = (Get-Date).AddSeconds($RefreshSeconds)
    do {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true).Key
            if ($key -eq 'Q') { return }
            if ($key -eq 'R') { break }
        }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $until)
}
