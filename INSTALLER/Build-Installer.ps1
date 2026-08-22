#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$portablePath = Join-Path $projectRoot 'TOOLBOXV6.6.1.exe'
$scriptPath = Join-Path $PSScriptRoot 'TOOLBOX_v6.6.nsi'
$outputPath = Join-Path $projectRoot 'output\installer\TOOLBOX_Setup_v6.6.1.exe'
$compilerCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'NSIS\makensis.exe'),
    (Join-Path $env:ProgramFiles 'NSIS\makensis.exe')
) | Where-Object { $_ }
$compiler = @($compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)[0]

if (-not $compiler) { throw 'NSIS 3 no esta instalado. Instala el paquete NSIS.NSIS y vuelve a intentarlo.' }
if (-not (Test-Path -LiteralPath $portablePath -PathType Leaf)) { throw "Falta el ejecutable portable: $portablePath" }
if ((Get-Item -LiteralPath $portablePath).VersionInfo.FileVersion -ne '6.6.1.0') {
    throw 'El ejecutable portable no corresponde a la version 6.6.1.0.'
}

$outputDirectory = Split-Path -Parent $outputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

Push-Location $PSScriptRoot
try {
    # El fuente se guarda en UTF-8 sin BOM; indicarlo evita textos como "ediciÃ³n".
    & $compiler /INPUTCHARSET UTF8 /V3 /WX $scriptPath
    if ($LASTEXITCODE -ne 0) { throw "NSIS termino con codigo $LASTEXITCODE." }
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'NSIS no produjo el instalador esperado.' }
$output = Get-Item -LiteralPath $outputPath
if ($output.VersionInfo.FileVersion -ne '6.6.1.0') { throw 'La version del instalador generado no es 6.6.1.0.' }

[PSCustomObject]@{
    Instalador = $output.FullName
    Version = $output.VersionInfo.FileVersion
    TamanoMB = [math]::Round($output.Length / 1MB, 2)
    SHA256 = (Get-FileHash -LiteralPath $output.FullName -Algorithm SHA256).Hash
}
