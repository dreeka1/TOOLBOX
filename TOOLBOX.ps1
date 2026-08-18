#requires -Version 5.1

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Windows.Forms.DataVisualization -ErrorAction SilentlyContinue
[System.Windows.Forms.Application]::EnableVisualStyles()

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
$consoleWnd = [Win32]::GetConsoleWindow()
if ($consoleWnd -ne [IntPtr]::Zero) {
    [Win32]::ShowWindow($consoleWnd, 0)
}

$Script:Version          = '6.15.1'
$Script:MarcaAgua        = 'Desarrollado por Derek Salinas'
$Script:ColorTitulo      = 'Cyan'
$Script:ColorAcento      = 'White'
$Script:ColorExito       = 'Green'
$Script:ColorAdvertencia = 'Yellow'
$Script:ColorError       = 'Red'
$Script:ColorInfo        = 'DarkGray'
$Script:ColorDestacado   = 'Magenta'
$Script:ColorServidor    = 'Red'
$Script:ColorTerminal    = 'DarkCyan'

$Script:GUIForm      = $null
$Script:LogBox       = $null
$Script:LogHeader    = $null
$Script:HeaderTitle  = $null
$Script:HeaderSub    = $null
$Script:StatusLabel  = $null
$Script:ConsoleMode  = $false
$Script:CurrentPanel = $null
$Script:LogDirectory = Join-Path $env:ProgramData 'CONTPAQiToolbox\Logs'
$Script:ReportDirectory = Join-Path $env:ProgramData 'CONTPAQiToolbox\Reportes'
$Script:LogFile      = $null
$Script:IsBusy       = $false
$Script:LoginUser    = 'Derek'
# SHA-256 de la contraseña autorizada; evita almacenarla como texto legible.
$Script:LoginPasswordHash = '4f557cd8dec11335d75f31726e32d81441983eab5f477eb979b34365e1a72378'
$Script:ServicesDevName       = 'ServicesDev'
$Script:ServicesDevLegacyName = 'ContpaqiWatchdog'
$Script:ServicesDevInstallDir = Join-Path $env:ProgramFiles 'ServicesDev'
$Script:ServicesDevRefreshMs  = 5000

function Initialize-ToolboxLog {
    try {
        if (-not (Test-Path -LiteralPath $Script:LogDirectory)) {
            New-Item -ItemType Directory -Path $Script:LogDirectory -Force -ErrorAction Stop | Out-Null
        }
        if (-not (Test-Path -LiteralPath $Script:ReportDirectory)) {
            New-Item -ItemType Directory -Path $Script:ReportDirectory -Force -ErrorAction Stop | Out-Null
        }
        $Script:LogFile = Join-Path $Script:LogDirectory ("Toolbox_{0}_{1}.log" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
        "CONTPAQi Toolbox v$($Script:Version) | Inicio: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Equipo: $env:COMPUTERNAME | Usuario: $env:USERNAME" |
            Set-Content -LiteralPath $Script:LogFile -Encoding UTF8 -ErrorAction Stop
    } catch {
        $Script:LogFile = $null
    }
}

function Get-TextSha256 {
    param([Parameter(Mandatory)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Convert-ConsoleColorToDrawing {
    param([ConsoleColor]$Color)
    switch ($Color) {
        'Green'        { return [System.Drawing.Color]::FromArgb(56, 224, 143) }
        'Red'          { return [System.Drawing.Color]::FromArgb(255, 93, 115) }
        'Yellow'       { return [System.Drawing.Color]::FromArgb(255, 191, 71) }
        'Cyan'         { return [System.Drawing.Color]::FromArgb(139, 92, 246) }
        'White'        { return [System.Drawing.Color]::FromArgb(241, 245, 249) }
        'Magenta'      { return [System.Drawing.Color]::FromArgb(167, 139, 250) }
        'DarkGray'     { return [System.Drawing.Color]::FromArgb(124, 135, 152) }
        'DarkCyan'     { return [System.Drawing.Color]::FromArgb(91, 33, 182) }
        'DarkRed'      { return [System.Drawing.Color]::FromArgb(204, 55, 82) }
        'DarkYellow'   { return [System.Drawing.Color]::FromArgb(211, 145, 31) }
        'Gray'         { return [System.Drawing.Color]::FromArgb(166, 176, 190) }
        'DarkGreen'    { return [System.Drawing.Color]::FromArgb(34, 168, 103) }
        'DarkMagenta'  { return [System.Drawing.Color]::FromArgb(126, 94, 239) }
        'Blue'         { return [System.Drawing.Color]::FromArgb(124, 58, 237) }
        'DarkBlue'     { return [System.Drawing.Color]::FromArgb(76, 29, 149) }
        default        { return [System.Drawing.Color]::FromArgb(241, 245, 249) }
    }
}

function Write-Host {
    param(
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [Object] $Object = '',
        [ConsoleColor] $ForegroundColor = [ConsoleColor]::Gray,
        [ConsoleColor] $BackgroundColor = [ConsoleColor]::Black,
        [Switch] $NoNewline,
        [Switch] $Separator
    )
    if ($Script:LogBox -and -not $Script:ConsoleMode) {
        $text = $Object.ToString()
        if (-not $NoNewline) { $text += "`r`n" }
        $color = Convert-ConsoleColorToDrawing -Color $ForegroundColor
        $Script:LogBox.SelectionStart = $Script:LogBox.TextLength
        $Script:LogBox.SelectionLength = 0
        $Script:LogBox.SelectionColor = $color
        $Script:LogBox.AppendText($text)
        $Script:LogBox.ScrollToCaret()
        # Las operaciones se ejecutan en el hilo de WinForms; procesar mensajes
        # evita que Windows marque la ventana como bloqueada o la pinte en blanco.
        [System.Windows.Forms.Application]::DoEvents()
    } else {
        $params = @{ Object = $Object; ForegroundColor = $ForegroundColor }
        if ($NoNewline) { $params.NoNewline = $true }
        Microsoft.PowerShell.Utility\Write-Host @params
    }
}

function Clear-Host {
    if ($Script:LogBox -and -not $Script:ConsoleMode) {
        $Script:LogBox.Clear()
    } else {
        try { [Console]::Clear() } catch { }
    }
}

function Refresh-Log {
    [System.Windows.Forms.Application]::DoEvents()
}

function Wait-Responsive {
    param([ValidateRange(0, 3600)][double]$Seconds)
    $until = (Get-Date).AddMilliseconds($Seconds * 1000)
    while ((Get-Date) -lt $until) {
        if ($Script:GUIForm -and -not $Script:ConsoleMode) {
            [System.Windows.Forms.Application]::DoEvents()
        }
        Start-Sleep -Milliseconds 80
    }
}

function Invoke-ResponsiveWorker {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [object[]]$Arguments = @(),
        [ValidateRange(1, 9000)][int]$TimeoutSeconds = 300,
        [string]$Activity = 'Procesando'
    )
    $worker = [PowerShell]::Create()
    $async = $null
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $null = $worker.AddScript($ScriptText)
        foreach ($argument in $Arguments) { $null = $worker.AddArgument($argument) }
        $async = $worker.BeginInvoke()
        while (-not $async.IsCompleted) {
            if ($Script:GUIForm -and -not $Script:ConsoleMode) {
                [System.Windows.Forms.Application]::DoEvents()
                if ($Script:StatusLabel) {
                    $Script:StatusLabel.Text = " $Activity... $([math]::Floor($stopwatch.Elapsed.TotalSeconds)) s | La operacion sigue en ejecucion"
                    $Script:StatusLabel.ForeColor = $Script:GUIColors.Warning
                }
            }
            if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                try { $worker.Stop() } catch { }
                return [PSCustomObject]@{
                    Correcto = $false; Timeout = $true; Resultado = $null
                    Error = "$Activity excedio el limite de $TimeoutSeconds segundos."
                    DuracionSegundos = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
                }
            }
            Start-Sleep -Milliseconds 100
        }
        $output = @($worker.EndInvoke($async))
        $streamErrors = @($worker.Streams.Error | ForEach-Object { $_.Exception.Message })
        $last = if ($output.Count -gt 0) { $output[-1] } else { $null }
        return [PSCustomObject]@{
            Correcto = ($streamErrors.Count -eq 0); Timeout = $false; Resultado = $last
            Error = ($streamErrors -join ' | ')
            DuracionSegundos = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        }
    } catch {
        return [PSCustomObject]@{
            Correcto = $false; Timeout = $false; Resultado = $null
            Error = $_.Exception.Message
            DuracionSegundos = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        }
    } finally {
        $stopwatch.Stop()
        if ($async -and -not $async.IsCompleted) { try { $worker.Stop() } catch { } }
        $worker.Dispose()
        if ($Script:StatusLabel) { $Script:StatusLabel.ForeColor = $Script:GUIColors.TextDim }
    }
}

function Invoke-DnsFlushResponsive {
    $code = @'
$process = New-Object Diagnostics.Process
$process.StartInfo = New-Object Diagnostics.ProcessStartInfo
$process.StartInfo.FileName = "$env:SystemRoot\System32\ipconfig.exe"
$process.StartInfo.Arguments = '/flushdns'
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.CreateNoWindow = $true
$process.StartInfo.RedirectStandardOutput = $true
$process.StartInfo.RedirectStandardError = $true
try {
    if (-not $process.Start()) { throw 'Windows no pudo iniciar ipconfig.exe.' }
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    [PSCustomObject]@{ ExitCode = $process.ExitCode; Output = (($stdout + ' ' + $stderr) -replace '\s+', ' ').Trim() }
} finally { $process.Dispose() }
'@
    $workerResult = Invoke-ResponsiveWorker -ScriptText $code -TimeoutSeconds 30 -Activity 'Limpiando cache DNS'
    if (-not $workerResult.Correcto -or $workerResult.Timeout) {
        return [PSCustomObject]@{ Correcto = $false; Error = $workerResult.Error }
    }
    $result = $workerResult.Resultado
    if (-not $result -or $result.ExitCode -ne 0) {
        $detail = if ($result -and $result.Output) { $result.Output } else { 'ipconfig no devolvio un resultado valido.' }
        return [PSCustomObject]@{ Correcto = $false; Error = $detail }
    }
    return [PSCustomObject]@{ Correcto = $true; Error = $null }
}

function Invoke-ProcessResponsive {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$ArgumentList = '',
        [ValidateRange(1, 7200)][int]$TimeoutSeconds = 900,
        [string]$Activity = 'Ejecutando proceso',
        [switch]$Hidden
    )
    $codigoProceso = @'
param([string]$Executable, [string]$Arguments, [bool]$HideWindow, [int]$MaxSeconds)
try {
    $parametros = @{ FilePath = $Executable; PassThru = $true; ErrorAction = 'Stop' }
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) { $parametros.ArgumentList = $Arguments }
    if ($HideWindow) { $parametros.WindowStyle = 'Hidden' }
    $proceso = Start-Process @parametros
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    while (-not $proceso.HasExited -and $reloj.Elapsed.TotalSeconds -lt $MaxSeconds) {
        Start-Sleep -Milliseconds 200
        $proceso.Refresh()
    }
    if (-not $proceso.HasExited) {
        try { $proceso.Kill() } catch { }
        [PSCustomObject]@{ Correcto = $false; Timeout = $true; ExitCode = -1; Error = "El proceso excedio $MaxSeconds segundos y fue detenido." }
    } else {
        [PSCustomObject]@{ Correcto = $true; Timeout = $false; ExitCode = $proceso.ExitCode; Error = $null }
    }
} catch {
    [PSCustomObject]@{ Correcto = $false; Timeout = $false; ExitCode = -1; Error = $_.Exception.Message }
}
'@
    $worker = Invoke-ResponsiveWorker -ScriptText $codigoProceso `
        -Arguments @($FilePath, $ArgumentList, [bool]$Hidden, $TimeoutSeconds) `
        -TimeoutSeconds ($TimeoutSeconds + 15) -Activity $Activity
    if (-not $worker.Correcto -or $worker.Timeout -or -not $worker.Resultado) {
        return [PSCustomObject]@{ Correcto = $false; ExitCode = -1; Error = $worker.Error }
    }
    return $worker.Resultado
}

# --- COLORES GUI ---
$Script:GUIColors = @{
    BG           = [System.Drawing.Color]::FromArgb(5, 6, 8)
    Sidebar      = [System.Drawing.Color]::FromArgb(9, 11, 15)
    Header       = [System.Drawing.Color]::FromArgb(7, 9, 12)
    Surface      = [System.Drawing.Color]::FromArgb(13, 16, 21)
    SurfaceAlt   = [System.Drawing.Color]::FromArgb(16, 20, 26)
    Button       = [System.Drawing.Color]::FromArgb(17, 21, 27)
    ButtonHover  = [System.Drawing.Color]::FromArgb(24, 32, 42)
    ButtonActive = [System.Drawing.Color]::FromArgb(32, 42, 54)
    Text         = [System.Drawing.Color]::FromArgb(241, 245, 249)
    TextDim      = [System.Drawing.Color]::FromArgb(124, 135, 152)
    Accent       = [System.Drawing.Color]::FromArgb(139, 92, 246)
    AccentDark   = [System.Drawing.Color]::FromArgb(50, 25, 87)
    Success      = [System.Drawing.Color]::FromArgb(56, 224, 143)
    Warning      = [System.Drawing.Color]::FromArgb(255, 191, 71)
    Error        = [System.Drawing.Color]::FromArgb(255, 93, 115)
    LogBG        = [System.Drawing.Color]::FromArgb(2, 3, 4)
    Separator    = [System.Drawing.Color]::FromArgb(26, 32, 41)
    ServerBtn    = [System.Drawing.Color]::FromArgb(27, 12, 17)
    TerminalBtn  = [System.Drawing.Color]::FromArgb(8, 22, 29)
    SupportBtn   = [System.Drawing.Color]::FromArgb(13, 19, 25)
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ToolboxDarkWindow {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
"@ -ErrorAction SilentlyContinue

function Enable-DarkTitleBar {
    param([Parameter(Mandatory)][System.Windows.Forms.Form]$Form)
    $Form.Add_HandleCreated({
        param($sender, $eventArgs)
        try {
            $enabled = 1
            $result = [ToolboxDarkWindow]::DwmSetWindowAttribute($sender.Handle, 20, [ref]$enabled, 4)
            if ($result -ne 0) { $null = [ToolboxDarkWindow]::DwmSetWindowAttribute($sender.Handle, 19, [ref]$enabled, 4) }
        } catch { }
    })
}

function Get-ToolboxAssetPath {
    param([Parameter(Mandatory)][string]$FileName)
    $candidates = @((Join-Path $env:TEMP ("CONTPAQiToolbox\{0}" -f $FileName)))
    if (-not [string]::IsNullOrWhiteSpace([string]$PSScriptRoot)) {
        $candidates += Join-Path $PSScriptRoot ("ASSETS\{0}" -f $FileName)
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$ScriptRoot)) {
        $candidates += Join-Path $ScriptRoot ("ASSETS\{0}" -f $FileName)
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function New-ToolboxLogoPictureBox {
    param([int]$Size = 56)
    $picture = New-Object System.Windows.Forms.PictureBox
    $picture.Size = New-Object System.Drawing.Size($Size, $Size)
    $picture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $picture.BackColor = [System.Drawing.Color]::Transparent
    $logoPath = Get-ToolboxAssetPath -FileName 'DS.png'
    if ($logoPath) {
        try {
            $sourceImage = [System.Drawing.Image]::FromFile($logoPath)
            try { $picture.Image = New-Object System.Drawing.Bitmap($sourceImage) } finally { $sourceImage.Dispose() }
        } catch { }
    }
    return $picture
}

function Set-ModernFormStyle {
    param([Parameter(Mandatory)][System.Windows.Forms.Form]$Form)
    $Form.BackColor = $Script:GUIColors.BG
    $Form.ForeColor = $Script:GUIColors.Text
    $Form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $Form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $iconPath = Get-ToolboxAssetPath -FileName 'DS.ico'
    if ($iconPath) {
        try { $Form.Icon = New-Object System.Drawing.Icon($iconPath) } catch { }
    }
    Enable-DarkTitleBar -Form $Form
}

function Set-ModernButtonStyle {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Button]$Button,
        [System.Drawing.Color]$BaseColor = $Script:GUIColors.Button,
        [System.Drawing.Color]$TextColor = $Script:GUIColors.Text,
        [System.Drawing.Color]$HoverColor = $Script:GUIColors.ButtonHover
    )
    $Button.UseVisualStyleBackColor = $false
    $Button.FlatStyle = 'Flat'
    $Button.FlatAppearance.BorderSize = 1
    $Button.FlatAppearance.BorderColor = $Script:GUIColors.Separator
    $Button.BackColor = $BaseColor
    $Button.ForeColor = $TextColor
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.Tag = [PSCustomObject]@{ Base = $BaseColor; Hover = $HoverColor; Active = [System.Windows.Forms.ControlPaint]::Dark($BaseColor, 0.10) }
    $Button.Add_MouseEnter({ param($sender, $eventArgs) if ($sender.Enabled) { $sender.BackColor = $sender.Tag.Hover } })
    $Button.Add_MouseLeave({ param($sender, $eventArgs) $sender.BackColor = $sender.Tag.Base })
    $Button.Add_MouseDown({ param($sender, $eventArgs) if ($sender.Enabled) { $sender.BackColor = $sender.Tag.Active } })
    $Button.Add_MouseUp({ param($sender, $eventArgs) if ($sender.Enabled) { $sender.BackColor = $sender.Tag.Hover } })
}

function Set-ModernTextBoxStyle {
    param([Parameter(Mandatory)][System.Windows.Forms.TextBox]$TextBox)
    $TextBox.BackColor = $Script:GUIColors.Surface
    $TextBox.ForeColor = $Script:GUIColors.Text
    $TextBox.BorderStyle = 'FixedSingle'
}

# --- CATALOGO DE SERVICIOS TERMINAL ---
$Script:CatalogoTerminal = @(
    @{
        Id              = 'SACI'
        Etiqueta        = 'AuthServer CONTPAQi (SACI)'
        Nombres         = @('Saci_CONTPAQi', 'AuthServer_CONTPAQi')
        PatronesDisplay = @('*AuthServer CONTPAQi*', '*SACI*CONTPAQ*')
    }
    @{
        Id              = 'V4'
        Etiqueta        = 'AuthServer Compac V4'
        Nombres         = @('AppKeyLicenseServer_Compac_V4', 'AuthServer_Compac_V4')
        PatronesDisplay = @('*AuthServer Compac (V4)*', '*Compac_V4*', '*Compac V4*')
    }
    @{
        Id              = 'NOMINAS'
        Etiqueta        = 'AuthServer CONTPAQi NOMINAS'
        Nombres         = @('AppKeyLicenseServer_NOMINAS', 'AuthServer_NOMINAS')
        PatronesDisplay = @('*NOMINAS*', '*Nóminas*', '*NOMINA*')
    }
    @{
        Id              = 'XML_SRV'
        Etiqueta        = 'Servidor CONTPAQi XML en Linea'
        Nombres         = @('AppKeyLicenseServer_XMLenLinea', 'CONTPAQi_XMLenLinea', 'CONTPAQiXMLenLinea', 'XMLService')
        PatronesDisplay = @('*CONTPAQi XML en linea*', '*CONTPAQi XML en línea*', '*XML en linea*', '*XML en línea*', '*XMLService*')
    }
    @{
        Id              = 'XML_AUTH'
        Etiqueta        = 'AuthServer XML en Linea'
        Nombres         = @('AuthServer_XMLenLinea', 'AuthServer_XML')
        PatronesDisplay = @('*AuthServer_XML*', '*AuthServer XML*')
    }
)

function Get-ServiciosMotorSQL {
    # MSSQL* tambien coincide con Full-Text y Launchpad. Solo estos nombres
    # representan una instancia real del motor de base de datos.
    return @(Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'MSSQLSERVER' -or $_.Name -match '^MSSQL\$[^$]+$' } |
        Sort-Object Name)
}

function Get-NombreInstanciaSQL {
    param([Parameter(Mandatory)][string]$NombreServicio)
    if ($NombreServicio -eq 'MSSQLSERVER') { return '.' }
    if ($NombreServicio -match '^MSSQL\$(.+)$') { return ".\$($matches[1])" }
    return $null
}

function Test-ConexionSQLLocal {
    param(
        [Parameter(Mandatory)][string]$Instancia,
        [int]$TimeoutSegundos = 5
    )
    $conexion = New-Object System.Data.SqlClient.SqlConnection
    $comando = $null
    try {
        $conexion.ConnectionString = "Server=$Instancia;Database=master;Integrated Security=True;TrustServerCertificate=True;Connect Timeout=$TimeoutSegundos;Application Name=CONTPAQi Toolbox"
        $conexion.Open()
        $comando = $conexion.CreateCommand()
        $comando.CommandTimeout = $TimeoutSegundos
        $comando.CommandText = "SET NOCOUNT ON; SELECT CAST(SERVERPROPERTY('ServerName') AS nvarchar(128)), CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128));"
        $lector = $comando.ExecuteReader()
        try {
            if ($lector.Read()) {
                return [PSCustomObject]@{
                    Correcto = $true
                    Servidor = $lector.GetString(0)
                    Version  = $lector.GetString(1)
                    Error    = $null
                }
            }
        } finally {
            $lector.Dispose()
        }
        return [PSCustomObject]@{ Correcto = $false; Servidor = $null; Version = $null; Error = 'SQL no devolvio informacion.' }
    } catch {
        return [PSCustomObject]@{ Correcto = $false; Servidor = $null; Version = $null; Error = $_.Exception.Message }
    } finally {
        if ($comando) { $comando.Dispose() }
        $conexion.Dispose()
    }
}

function ConvertTo-SqlIdentifier {
    param([Parameter(Mandatory)][string]$Value)
    return '[' + $Value.Replace(']', ']]') + ']'
}

function ConvertTo-SqlLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return "N'" + $Value.Replace("'", "''") + "'"
}

function Invoke-SqlTable {
    param(
        [Parameter(Mandatory)][string]$Instancia,
        [string]$BaseDatos = 'master',
        [Parameter(Mandatory)][string]$Consulta,
        [int]$TimeoutSegundos = 30
    )
    $conexion = New-Object System.Data.SqlClient.SqlConnection
    $comando = $null
    $adaptador = $null
    try {
        $conexion.ConnectionString = "Server=$Instancia;Database=$BaseDatos;Integrated Security=True;TrustServerCertificate=True;Connect Timeout=8;Application Name=CONTPAQi Toolbox"
        $conexion.Open()
        $comando = $conexion.CreateCommand()
        $comando.CommandTimeout = $TimeoutSegundos
        $comando.CommandText = $Consulta
        $adaptador = New-Object System.Data.SqlClient.SqlDataAdapter($comando)
        $tabla = New-Object System.Data.DataTable
        $null = $adaptador.Fill($tabla)
        return @($tabla.Rows)
    } finally {
        if ($adaptador) { $adaptador.Dispose() }
        if ($comando) { $comando.Dispose() }
        $conexion.Dispose()
    }
}

function Invoke-SqlTableResponsive {
    param(
        [Parameter(Mandatory)][string]$Instancia,
        [string]$BaseDatos = 'master',
        [Parameter(Mandatory)][string]$Consulta,
        [ValidateRange(1, 900)][int]$TimeoutSegundos = 45,
        [string]$Actividad = 'Consultando SQL Server'
    )

    # Las consultas de diagnostico se ejecutan fuera del hilo de WinForms. Ademas,
    # los DataRow se convierten en objetos simples para cruzar el limite del runspace.
    $codigo = @'
param($InstanciaTrabajo, $BaseTrabajo, $ConsultaTrabajo, $TimeoutTrabajo)
$conexion = New-Object System.Data.SqlClient.SqlConnection
$comando = $null
$adaptador = $null
try {
    $conexion.ConnectionString = "Server=$InstanciaTrabajo;Database=$BaseTrabajo;Integrated Security=True;TrustServerCertificate=True;Connect Timeout=8;Application Name=CONTPAQi Toolbox Salud SQL"
    $conexion.Open()
    $comando = $conexion.CreateCommand()
    $comando.CommandTimeout = $TimeoutTrabajo
    $comando.CommandText = $ConsultaTrabajo
    $adaptador = New-Object System.Data.SqlClient.SqlDataAdapter($comando)
    $tabla = New-Object System.Data.DataTable
    $null = $adaptador.Fill($tabla)
    $filas = @()
    foreach ($fila in $tabla.Rows) {
        $valores = [ordered]@{}
        foreach ($columna in $tabla.Columns) {
            $valor = $fila[$columna.ColumnName]
            if ($valor -eq [DBNull]::Value) { $valor = $null }
            $valores[$columna.ColumnName] = $valor
        }
        $filas += [PSCustomObject]$valores
    }
    [PSCustomObject]@{ Correcto = $true; Filas = @($filas); Error = $null }
} catch {
    [PSCustomObject]@{ Correcto = $false; Filas = @(); Error = $_.Exception.Message }
} finally {
    if ($adaptador) { $adaptador.Dispose() }
    if ($comando) { $comando.Dispose() }
    $conexion.Dispose()
}
'@
    $worker = Invoke-ResponsiveWorker -ScriptText $codigo `
        -Arguments @($Instancia, $BaseDatos, $Consulta, $TimeoutSegundos) `
        -TimeoutSeconds ($TimeoutSegundos + 15) -Activity $Actividad
    if (-not $worker.Correcto -or $worker.Timeout -or -not $worker.Resultado) {
        return [PSCustomObject]@{ Correcto = $false; Filas = @(); Error = $worker.Error }
    }
    return $worker.Resultado
}

function Invoke-SqlCommandDetailed {
    param(
        [Parameter(Mandatory)][string]$Instancia,
        [string]$BaseDatos = 'master',
        [Parameter(Mandatory)][string]$Consulta,
        [int]$TimeoutSegundos = 600
    )
    # El trabajo SQL corre en un runspace aislado para que WinForms siga
    # repintando la bitacora durante respaldos, CHECKDB o reconstrucciones largas.
    $codigo = @'
param($InstanciaTrabajo, $BaseTrabajo, $ConsultaTrabajo, $TimeoutTrabajo)
$conexion = New-Object System.Data.SqlClient.SqlConnection
$comando = $null
$mensajes = New-Object System.Collections.Generic.List[string]
$handler = [System.Data.SqlClient.SqlInfoMessageEventHandler]{
    param($sender, $eventArgs)
    foreach ($errorSql in $eventArgs.Errors) { $mensajes.Add($errorSql.Message) }
}
$inicio = Get-Date
try {
    $conexion.ConnectionString = "Server=$InstanciaTrabajo;Database=$BaseTrabajo;Integrated Security=True;TrustServerCertificate=True;Connect Timeout=8;Application Name=CONTPAQi Toolbox"
    $conexion.add_InfoMessage($handler)
    $conexion.Open()
    $comando = $conexion.CreateCommand()
    $comando.CommandTimeout = $TimeoutTrabajo
    $comando.CommandText = $ConsultaTrabajo
    $filas = $comando.ExecuteNonQuery()
    [PSCustomObject]@{
        Correcto = $true
        Filas = $filas
        Mensajes = @($mensajes)
        Error = $null
        DuracionSegundos = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    }
} catch {
    $mensajes.Add($_.Exception.Message)
    [PSCustomObject]@{
        Correcto = $false
        Filas = 0
        Mensajes = @($mensajes)
        Error = $_.Exception.Message
        DuracionSegundos = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    }
} finally {
    if ($conexion) { try { $conexion.remove_InfoMessage($handler) } catch { } }
    if ($comando) { $comando.Dispose() }
    $conexion.Dispose()
}
'@
    $worker = [PowerShell]::Create()
    $async = $null
    try {
        $null = $worker.AddScript($codigo).AddArgument($Instancia).AddArgument($BaseDatos).AddArgument($Consulta).AddArgument($TimeoutSegundos)
        $async = $worker.BeginInvoke()
        while (-not $async.IsCompleted) {
            if ($Script:GUIForm -and -not $Script:ConsoleMode) { [System.Windows.Forms.Application]::DoEvents() }
            Start-Sleep -Milliseconds 120
        }
        $salida = @($worker.EndInvoke($async))
        if ($salida.Count -gt 0) { return $salida[-1] }
        $detalle = ($worker.Streams.Error | ForEach-Object { $_.Exception.Message }) -join ' | '
        if (-not $detalle) { $detalle = 'La operacion SQL no devolvio un resultado.' }
        return [PSCustomObject]@{ Correcto = $false; Filas = 0; Mensajes = @($detalle); Error = $detalle; DuracionSegundos = 0 }
    } catch {
        return [PSCustomObject]@{ Correcto = $false; Filas = 0; Mensajes = @($_.Exception.Message); Error = $_.Exception.Message; DuracionSegundos = 0 }
    } finally {
        if ($async -and -not $async.IsCompleted) { try { $worker.Stop() } catch { } }
        $worker.Dispose()
    }
}

function Get-InventarioBasesSQL {
    param([Parameter(Mandatory)][string]$Instancia)
    $consulta = @"
SELECT
    d.name AS Nombre,
    d.state_desc AS Estado,
    d.user_access_desc AS Acceso,
    d.recovery_model_desc AS Recuperacion,
    d.page_verify_option_desc AS VerificacionPagina,
    d.compatibility_level AS Compatibilidad,
    d.is_read_only AS SoloLectura,
    CAST(SUM(mf.size) / 128.0 AS decimal(18,1)) AS TamanoMB,
    b.UltimoRespaldoCompleto
FROM sys.databases d
LEFT JOIN sys.master_files mf ON d.database_id = mf.database_id
OUTER APPLY (
    SELECT MAX(bs.backup_finish_date) AS UltimoRespaldoCompleto
    FROM msdb.dbo.backupset bs
    WHERE bs.database_name = d.name AND bs.type = 'D'
) b
WHERE d.database_id > 4
GROUP BY d.name, d.state_desc, d.user_access_desc, d.recovery_model_desc,
         d.page_verify_option_desc, d.compatibility_level, d.is_read_only,
         b.UltimoRespaldoCompleto
ORDER BY d.name;
"@
    return @(Invoke-SqlTable -Instancia $Instancia -Consulta $consulta -TimeoutSegundos 30)
}

function Get-RutaRespaldoSQL {
    param([Parameter(Mandatory)][string]$Instancia)
    try {
        $resultado = @(Invoke-SqlTable -Instancia $Instancia -Consulta "SELECT CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(4000)) AS Ruta;" -TimeoutSegundos 15)
        if ($resultado.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$resultado[0].Ruta)) {
            return [string]$resultado[0].Ruta
        }
    } catch { }
    try {
        $resultado = @(Invoke-SqlTable -Instancia $Instancia -Consulta "DECLARE @p nvarchar(4000); EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'BackupDirectory', @p OUTPUT; SELECT @p AS Ruta;" -TimeoutSegundos 15)
        if ($resultado.Count -gt 0) { return [string]$resultado[0].Ruta }
    } catch { }
    return $null
}

function Invoke-RespaldoSQLVerificado {
    param(
        [Parameter(Mandatory)][string]$Instancia,
        [Parameter(Mandatory)][string]$BaseDatos
    )
    $rutaBase = Get-RutaRespaldoSQL -Instancia $Instancia
    if ([string]::IsNullOrWhiteSpace($rutaBase)) {
        return [PSCustomObject]@{ Correcto = $false; Ruta = $null; Error = 'No fue posible obtener la ruta predeterminada de respaldos de SQL Server.'; DuracionSegundos = 0; TamanoMB = 0 }
    }
    if (-not (Test-Path -LiteralPath $rutaBase -PathType Container)) {
        return [PSCustomObject]@{ Correcto = $false; Ruta = $rutaBase; Error = 'La ruta predeterminada de respaldos no existe o no es accesible para el consultor.'; DuracionSegundos = 0; TamanoMB = 0 }
    }

    $dbLiteral = ConvertTo-SqlLiteral -Value $BaseDatos
    try {
        $tamanoFila = @(Invoke-SqlTable -Instancia $Instancia -Consulta "SELECT CAST(SUM(size) * 8.0 / 1024 AS decimal(18,1)) AS TamanoMB FROM sys.master_files WHERE database_id = DB_ID($dbLiteral);" -TimeoutSegundos 15)
        $tamanoBaseMB = if ($tamanoFila.Count -gt 0 -and $tamanoFila[0].TamanoMB -ne [DBNull]::Value) { [double]$tamanoFila[0].TamanoMB } else { 0 }
        $unidad = Split-Path -Path $rutaBase -Qualifier -ErrorAction SilentlyContinue
        if ($unidad -match '^([A-Za-z]):') {
            $disco = Get-PSDrive -Name $matches[1] -PSProvider FileSystem -ErrorAction SilentlyContinue
            $minimoBytes = [math]::Max(512MB, ($tamanoBaseMB * 1.20 * 1MB))
            if ($disco -and $disco.Free -lt $minimoBytes) {
                $libreGB = [math]::Round($disco.Free / 1GB, 1)
                $requeridoGB = [math]::Round($minimoBytes / 1GB, 1)
                return [PSCustomObject]@{ Correcto = $false; Ruta = $rutaBase; Error = "Espacio insuficiente: $libreGB GB libres; se requieren aproximadamente $requeridoGB GB antes de respaldar."; DuracionSegundos = 0; TamanoMB = 0 }
            }
        }
    } catch {
        return [PSCustomObject]@{ Correcto = $false; Ruta = $rutaBase; Error = "No fue posible validar el espacio para el respaldo: $($_.Exception.Message)"; DuracionSegundos = 0; TamanoMB = 0 }
    }
    $nombreSeguro = ($BaseDatos -replace '[^A-Za-z0-9_.-]', '_')
    $rutaBak = Join-Path $rutaBase ("Toolbox_{0}_{1}.bak" -f $nombreSeguro, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $dbId = ConvertTo-SqlIdentifier -Value $BaseDatos
    $bakLiteral = ConvertTo-SqlLiteral -Value $rutaBak
    $consultaBackup = "BACKUP DATABASE $dbId TO DISK = $bakLiteral WITH COPY_ONLY, INIT, CHECKSUM, COMPRESSION, STATS = 10;"
    Write-Log -Mensaje "Creando respaldo CHECKSUM en $rutaBak ..." -Nivel PROGRESS
    $resultado = Invoke-SqlCommandDetailed -Instancia $Instancia -Consulta $consultaBackup -TimeoutSegundos 3600
    if (-not $resultado.Correcto -and $resultado.Error -match 'compression|compresi') {
        Write-Log -Mensaje 'La edicion SQL no admite compresion; reintentando sin COMPRESSION.' -Nivel INFO
        $consultaBackup = "BACKUP DATABASE $dbId TO DISK = $bakLiteral WITH COPY_ONLY, INIT, CHECKSUM, STATS = 10;"
        $resultado = Invoke-SqlCommandDetailed -Instancia $Instancia -Consulta $consultaBackup -TimeoutSegundos 3600
    }
    if (-not $resultado.Correcto) {
        return [PSCustomObject]@{ Correcto = $false; Ruta = $rutaBak; Error = $resultado.Error; DuracionSegundos = $resultado.DuracionSegundos; TamanoMB = 0 }
    }
    Write-Log -Mensaje 'Respaldo creado; ejecutando RESTORE VERIFYONLY con CHECKSUM...' -Nivel PROGRESS
    $verificacion = Invoke-SqlCommandDetailed -Instancia $Instancia -Consulta "RESTORE VERIFYONLY FROM DISK = $bakLiteral WITH CHECKSUM;" -TimeoutSegundos 3600
    $tamanoBakMB = if (Test-Path -LiteralPath $rutaBak -PathType Leaf) { [math]::Round((Get-Item -LiteralPath $rutaBak).Length / 1MB, 1) } else { 0 }
    return [PSCustomObject]@{
        Correcto = $verificacion.Correcto
        Ruta = $rutaBak
        Error = $verificacion.Error
        DuracionSegundos = [math]::Round($resultado.DuracionSegundos + $verificacion.DuracionSegundos, 1)
        TamanoMB = $tamanoBakMB
    }
}

function Invoke-IntegridadBaseSQL {
    param(
        [Parameter(Mandatory)][string]$Instancia,
        [Parameter(Mandatory)][string]$BaseDatos,
        [switch]$Completa
    )
    $dbLiteral = ConvertTo-SqlLiteral -Value $BaseDatos
    $opciones = if ($Completa) { 'NO_INFOMSGS, ALL_ERRORMSGS' } else { 'PHYSICAL_ONLY, NO_INFOMSGS, ALL_ERRORMSGS' }
    Write-Log -Mensaje "Ejecutando DBCC CHECKDB $(if ($Completa) { 'completo' } else { 'PHYSICAL_ONLY' }) sobre $BaseDatos ..." -Nivel PROGRESS
    $resultado = Invoke-SqlCommandDetailed -Instancia $Instancia -Consulta "DBCC CHECKDB ($dbLiteral) WITH $opciones;" -TimeoutSegundos 3600
    $texto = ($resultado.Mensajes -join ' ')
    $erroresAsignacion = 0
    $erroresConsistencia = 0
    if ($texto -match 'CHECKDB found\s+(\d+)\s+allocation errors and\s+(\d+)\s+consistency errors') {
        $erroresAsignacion = [int]$matches[1]
        $erroresConsistencia = [int]$matches[2]
    }
    $saludable = ($resultado.Correcto -and $erroresAsignacion -eq 0 -and $erroresConsistencia -eq 0 -and $texto -notmatch 'Msg\s+89\d{2}')
    return [PSCustomObject]@{
        Correcto = $resultado.Correcto
        Saludable = $saludable
        ErroresAsignacion = $erroresAsignacion
        ErroresConsistencia = $erroresConsistencia
        Mensajes = $resultado.Mensajes
        Error = $resultado.Error
        DuracionSegundos = $resultado.DuracionSegundos
    }
}

function Get-FragmentacionSQL {
    param(
        [Parameter(Mandatory)][string]$Instancia,
        [Parameter(Mandatory)][string]$BaseDatos
    )
    $consulta = @"
SELECT
    s.name AS Esquema,
    t.name AS Tabla,
    i.name AS Indice,
    CAST(ips.avg_fragmentation_in_percent AS decimal(8,2)) AS Fragmentacion,
    ips.page_count AS Paginas
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
INNER JOIN sys.tables t ON i.object_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE ips.index_id > 0
  AND i.type IN (1, 2)
  AND i.is_disabled = 0
  AND ips.page_count >= 1000
  AND ips.avg_fragmentation_in_percent >= 10
ORDER BY ips.avg_fragmentation_in_percent DESC;
"@
    return @(Invoke-SqlTable -Instancia $Instancia -BaseDatos $BaseDatos -Consulta $consulta -TimeoutSegundos 300)
}

function Get-SesionesActivasBaseSQL {
    param(
        [Parameter(Mandatory)][string]$Instancia,
        [Parameter(Mandatory)][string]$BaseDatos
    )
    $dbLiteral = ConvertTo-SqlLiteral -Value $BaseDatos
    $consulta = @"
SELECT
    s.session_id AS IdSesion,
    COALESCE(s.host_name, N'N/D') AS Equipo,
    COALESCE(s.login_name, N'N/D') AS Usuario,
    COALESCE(s.program_name, N'N/D') AS Programa,
    s.status AS Estado
FROM sys.dm_exec_sessions s
WHERE s.is_user_process = 1
  AND s.session_id <> @@SPID
  AND s.database_id = DB_ID($dbLiteral)
ORDER BY s.host_name, s.session_id;
"@
    return @(Invoke-SqlTable -Instancia $Instancia -Consulta $consulta -TimeoutSegundos 20)
}

function Invoke-MantenimientoIndicesSQL {
    param(
        [Parameter(Mandatory)][string]$Instancia,
        [Parameter(Mandatory)][string]$BaseDatos
    )
    $indices = @(Get-FragmentacionSQL -Instancia $Instancia -BaseDatos $BaseDatos)
    if ($indices.Count -eq 0) {
        Write-Log -Mensaje 'No hay indices grandes con fragmentacion igual o mayor a 10%.' -Nivel OK
    } else {
        Write-Log -Mensaje "$($indices.Count) indice(s) requieren mantenimiento." -Nivel INFO
    }
    $correctos = 0
    $fallidos = 0
    foreach ($indice in $indices) {
        $idx = ConvertTo-SqlIdentifier -Value ([string]$indice.Indice)
        $schema = ConvertTo-SqlIdentifier -Value ([string]$indice.Esquema)
        $tabla = ConvertTo-SqlIdentifier -Value ([string]$indice.Tabla)
        $fragmentacion = [double]$indice.Fragmentacion
        $operacion = if ($fragmentacion -ge 30) { 'REBUILD WITH (MAXDOP = 1, SORT_IN_TEMPDB = OFF)' } else { 'REORGANIZE WITH (LOB_COMPACTION = ON)' }
        Write-Log -Mensaje "$($indice.Esquema).$($indice.Tabla) / $($indice.Indice): $fragmentacion% -> $($operacion.Split(' ')[0])" -Nivel PROGRESS
        $resultado = Invoke-SqlCommandDetailed -Instancia $Instancia -BaseDatos $BaseDatos -Consulta "ALTER INDEX $idx ON $schema.$tabla $operacion;" -TimeoutSegundos 1800
        if ($resultado.Correcto) { $correctos++ } else {
            $fallidos++
            Write-Log -Mensaje "Fallo en $($indice.Indice): $($resultado.Error)" -Nivel ERROR
        }
        Refresh-Log
    }
    Write-Log -Mensaje 'Actualizando estadisticas con sp_updatestats...' -Nivel PROGRESS
    $stats = Invoke-SqlCommandDetailed -Instancia $Instancia -BaseDatos $BaseDatos -Consulta 'EXEC sp_updatestats;' -TimeoutSegundos 1800
    if (-not $stats.Correcto) {
        Write-Log -Mensaje "No fue posible actualizar estadisticas: $($stats.Error)" -Nivel ERROR
    } else {
        Write-Log -Mensaje 'Estadisticas actualizadas correctamente.' -Nivel OK
    }
    return [PSCustomObject]@{ Correctos = $correctos; Fallidos = $fallidos; Total = $indices.Count; EstadisticasCorrectas = $stats.Correcto }
}

function Get-ServiciosSQLRelacionados {
    $resultado = @(Get-ServiciosMotorSQL | Select-Object -ExpandProperty Name)
    if (Get-Service -Name 'SQLBrowser' -ErrorAction SilentlyContinue) { $resultado += 'SQLBrowser' }
    return @($resultado | Select-Object -Unique)
}

$ServiciosSACI      = @('Saci_CONTPAQi')
$ServiciosLicencias = @('AppKeyLicenseServer_NOMINAS', 'AppKeyLicenseServer_Compac_V4', 'AppKeyLicenseServer_XMLenLinea', 'AuthServer_XMLenLinea')
$ServiciosSQL       = @(Get-ServiciosSQLRelacionados)

$ProcesosCONTPAQi = @(
    'SRVPAQi', 'Formularios', 'Contabilidad', 'Nominas', 'Bancos',
    'Comercial', 'Facturacion', 'SACI', 'sdk', 'XMLenLinea', 'XMLService*',
    'AdminPaq', 'CONTPAQi', 'AppKey', 'Licencias', 'VisorDocumentos'
)

$PatronesRutaCONTPAQi = @('*CONTPAQi*', '*Compac*', '*COMPAC*')

$Script:MapaModulosProceso = @(
    @{ Modulo = 'AuthServer / SACI';        Patrones = @('*saci*', '*authserver*') }
    @{ Modulo = 'Contabilidad';             Patrones = @('*contabilidad*') }
    @{ Modulo = 'Bancos';                   Patrones = @('*bancos*') }
    @{ Modulo = 'Comercial / Facturacion';  Patrones = @('*comercial*', '*facturacion*') }
    @{ Modulo = 'Nominas';                  Patrones = @('*nomina*') }
    @{ Modulo = 'XML en Linea';             Patrones = @('*xmlenlinea*', '*xmlservice*', '*xml*') }
    @{ Modulo = 'AdminPaq / Utilerias';     Patrones = @('*adminpaq*') }
    @{ Modulo = 'AppKey / Licencias';       Patrones = @('*appkey*', '*licencias*') }
    @{ Modulo = 'Integracion / Background'; Patrones = @('*srvpaqi*', '*contpaqicomercial*', '*contpaqiservidor*') }
    @{ Modulo = 'SDK / VisorDocumentos';    Patrones = @('*sdk*', '*visordocumentos*') }
)

function Get-ModuloProceso {
    param(
        [string]$Nombre,
        [string]$RutaEjecutable = ''
    )
    foreach ($item in $Script:MapaModulosProceso) {
        foreach ($patron in $item.Patrones) {
            if ($Nombre -like $patron) { return $item.Modulo }
            if ($RutaEjecutable -and ($RutaEjecutable -like $patron)) { return $item.Modulo }
        }
    }
    return 'Sin clasificar'
}

$ProcesosPID = @(
    'saci', 'SRVPAQi', 'CONTPAQiComercial', 'CONTPAQiServidor', 'CONTPAQiServer',
    'SrvComercial', 'XMLService*'
)
$PatronesNombrePID  = @('*saci*', '*SRVPAQi*', '*CONTPAQiComercial*', '*CONTPAQiServidor*', '*XMLService*')
$PatronesRutaPID    = @('*\SACI\*', '*CONTPAQiComercial*', '*CONTPAQi*Servidor*', '*Compac*Servidor*', '*XMLService*')
$PatronesServicioPID = @('*Servidor de aplicaciones CONTPAQ*', '*SACI*CONTPAQ*', '*XMLService*', '*XML en linea*', '*XML en línea*')

$Script:SistemasMapa = @{
    '1' = @{
        Nombre   = 'CONTPAQi Contabilidad'
        Patrones = @('*CONTPAQi*Contabilidad*', '*CONTPAQ*Contabilidad*', '*Compac*Contabilidad*', '*Contabilidad*CONTPAQ*')
    }
    '2' = @{
        Nombre   = 'CONTPAQi Bancos'
        Patrones = @('*CONTPAQi*Bancos*', '*CONTPAQ*Bancos*', '*Compac*Bancos*', '*Bancos*CONTPAQ*')
    }
    '3' = @{
        Nombre   = 'CONTPAQi Comercial Premium'
        Patrones = @('*Comercial Premium*', '*CONTPAQi*Comercial*Premium*', '*CONTPAQ*Comercial*Premium*')
    }
    '4' = @{
        Nombre   = 'CONTPAQi Nominas'
        Patrones = @('*CONTPAQi*Nominas*', '*CONTPAQi*Nóminas*', '*CONTPAQ*Nominas*', '*Nominas*CONTPAQ*', '*Nóminas*CONTPAQ*')
    }
    '5' = @{
        Nombre   = 'CONTPAQi XML en Linea'
        Patrones = @('*XML en linea*', '*XML en línea*', '*CONTPAQi*XML*', '*XML*CONTPAQ*')
    }
    '6' = @{
        Nombre   = 'CONTPAQi Factura Electronica'
        Patrones = @('*Factura Electronica*', '*Factura Electrónica*', '*CONTPAQi*Factura*', '*Factura*CONTPAQ*')
    }
}

# --- UTILIDADES DE INTERFAZ ---

function Set-ConsolaTamano {
    if ($Script:ConsoleMode) {
        try {
            $host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(78, 46)
            $host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(78, 9999)
        } catch { }
    }
}

function Write-Linea {
    param([string]$Texto = '', [string]$Color = 'Gray', [switch]$Centrado)
    Write-Host $Texto -ForegroundColor $Color
}

function Write-Separador {
    param([string]$Caracter = '=', [string]$Color = 'DarkCyan')
    Write-Linea -Texto ($Caracter * 78) -Color $Color
}

function Write-Encabezado {
    param(
        [string]$Titulo,
        [string]$Subtitulo = '',
        [string]$Color = $Script:ColorTitulo
    )
    if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        if ($Script:HeaderTitle) { $Script:HeaderTitle.Text = $Titulo }
        if ($Script:HeaderSub) { $Script:HeaderSub.Text = $Subtitulo }
        if ($Script:LogBox) { $Script:LogBox.Clear() }
        [System.Windows.Forms.Application]::DoEvents()
    } else {
        Clear-Host
        Write-Host ''
        Write-Separador -Color $Color
        Write-Linea -Texto $Titulo -Color $Color -Centrado
        if ($Subtitulo) {
            Write-Linea -Texto $Subtitulo -Color $Script:ColorInfo -Centrado
        }
        Write-Separador -Color $Color
        Write-MarcaAgua
        Write-Host ''
    }
}

function Write-MarcaAgua {
    Write-Linea -Texto " @ $($Script:MarcaAgua) @" -Color 'DarkGray' -Centrado
}

function Write-SeccionMenu {
    param(
        [string]$Titulo,
        [string]$Color = $Script:ColorDestacado
    )
    Write-Host ''
    Write-Separador -Caracter '-' -Color $Color
    Write-Linea -Texto " $Titulo" -Color $Color
    Write-Separador -Caracter '-' -Color $Color
}

function Write-OpcionMenu {
    param(
        [string]$Tecla,
        [string]$Descripcion,
        [string]$Color = $Script:ColorAcento,
        [string]$Icono = ' '
    )
    $linea = "  [$Tecla] $Icono$Descripcion"
    Write-Linea -Texto $linea -Color $Color
}

function Write-Log {
    param(
        [string]$Mensaje,
        [ValidateSet('OK', 'INFO', 'WARN', 'ERROR', 'PROGRESS')]
        [string]$Nivel = 'INFO'
    )
    $prefijos = @{
        OK       = '[OK]   '
        INFO     = '[i]    '
        WARN     = '[!]    '
        ERROR    = '[X]    '
        PROGRESS = '[...]  '
    }
    $colores = @{
        OK       = $Script:ColorExito
        INFO     = $Script:ColorAcento
        WARN     = $Script:ColorAdvertencia
        ERROR    = $Script:ColorError
        PROGRESS = 'DarkYellow'
    }
    $linea = "$($prefijos[$Nivel])$Mensaje"
    Write-Host $linea -ForegroundColor $colores[$Nivel]
    if ($Script:LogFile) {
        try {
            "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Nivel, $Mensaje |
                Add-Content -LiteralPath $Script:LogFile -Encoding UTF8 -ErrorAction Stop
        } catch { }
    }
}

function Write-BarraEstado {
    if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        $equipo   = $env:COMPUTERNAME
        $usuario  = $env:USERNAME
        $fecha    = Get-Date -Format 'dd/MM/yyyy HH:mm'
        $perfil   = Get-PerfilEquipo
        if ($Script:StatusLabel) {
            $Script:StatusLabel.Text = " $equipo | $perfil | Op: $usuario | $fecha | v$($Script:Version)  |  $($Script:MarcaAgua)"
        }
    } else {
        $equipo   = $env:COMPUTERNAME
        $usuario  = $env:USERNAME
        $fecha    = Get-Date -Format 'dd/MM/yyyy HH:mm'
        $perfil   = Get-PerfilEquipo
        Write-Host ''
        Write-Separador -Caracter '-' -Color 'DarkGray'
        Write-Linea -Texto " $equipo | $perfil | Op: $usuario | $fecha | v$($Script:Version)" -Color 'DarkGray'
        Write-Linea -Texto " $($Script:MarcaAgua)" -Color 'DarkGray' -Centrado
        Write-Separador -Caracter '-' -Color 'DarkGray'
    }
}

function Show-Pausa {
    param([string]$Mensaje = 'Presiona Enter para continuar...')
    if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        [System.Windows.Forms.MessageBox]::Show($Mensaje, 'Toolbox', 'OK', 'Information') | Out-Null
    } else {
        Write-Host ''
        Read-Host $Mensaje | Out-Null
    }
}

function Confirmar-Accion {
    param([string]$Mensaje)
    if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        $result = [System.Windows.Forms.MessageBox]::Show("$Mensaje`n`n¿Deseas continuar?", 'Toolbox - Confirmacion', 'YesNo', 'Question')
        return ($result -eq 'Yes')
    } else {
        Write-Host ''
        $resp = Read-Host "$Mensaje (S/N)"
        return ($resp -eq 'S' -or $resp -eq 's')
    }
}

function Show-GUIInput {
    param(
        [string]$Titulo = 'Toolbox - Entrada',
        [string]$Mensaje,
        [switch]$IsPassword,
        [string]$DefaultText = ''
    )
    $form = New-Object System.Windows.Forms.Form
    Set-ModernFormStyle -Form $form
    $form.Text = $Titulo
    $form.Size = New-Object System.Drawing.Size(460, 215)
    $form.StartPosition = 'CenterParent'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.BackColor = $Script:GUIColors.BG

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Mensaje
    $lbl.Location = New-Object System.Drawing.Point(15, 20)
    $lbl.Size = New-Object System.Drawing.Size(410, 30)
    $lbl.ForeColor = $Script:GUIColors.Text
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $form.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(15, 58)
    $txt.Size = New-Object System.Drawing.Size(410, 27)
    $txt.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $txt.BackColor = $Script:GUIColors.LogBG
    $txt.ForeColor = $Script:GUIColors.Text
    Set-ModernTextBoxStyle -TextBox $txt
    $txt.Text = $DefaultText
    if ($IsPassword) { $txt.UseSystemPasswordChar = $true }
    $form.Controls.Add($txt)

    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = 'Aceptar'
    $okBtn.Location = New-Object System.Drawing.Point(245, 108)
    $okBtn.Size = New-Object System.Drawing.Size(85, 34)
    $okBtn.BackColor = $Script:GUIColors.Button
    $okBtn.ForeColor = $Script:GUIColors.Text
    $okBtn.FlatStyle = 'Flat'
    Set-ModernButtonStyle -Button $okBtn -BaseColor $Script:GUIColors.AccentDark -TextColor $Script:GUIColors.Text -HoverColor $Script:GUIColors.Accent
    $okBtn.DialogResult = 'OK'
    $form.Controls.Add($okBtn)

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = 'Cancelar'
    $cancelBtn.Location = New-Object System.Drawing.Point(340, 108)
    $cancelBtn.Size = New-Object System.Drawing.Size(85, 34)
    $cancelBtn.BackColor = $Script:GUIColors.Button
    $cancelBtn.ForeColor = $Script:GUIColors.Text
    $cancelBtn.FlatStyle = 'Flat'
    Set-ModernButtonStyle -Button $cancelBtn
    $cancelBtn.DialogResult = 'Cancel'
    $form.Controls.Add($cancelBtn)

    $form.AcceptButton = $okBtn
    $form.CancelButton = $cancelBtn

    $result = $form.ShowDialog()
    if ($result -eq 'OK') { return $txt.Text }
    return $null
}

function Confirmar-Movimiento {
    param(
        [Parameter(Mandatory)][string]$Frase,
        [Parameter(Mandatory)][string]$Accion,
        [string]$Detalle = 'Esta operacion realizara cambios en el equipo.'
    )
    $esperada = $Frase.Trim().ToUpperInvariant()
    $mensaje = "Escribe `"$esperada`" para continuar:"
    $respuesta = if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        Show-GUIInput -Titulo 'Confirmar accion' -Mensaje $mensaje
    } else {
        Write-Host ''
        Read-Host " Escribe `"$esperada`" para continuar"
    }
    $correcta = (-not [string]::IsNullOrWhiteSpace([string]$respuesta) -and $respuesta.Trim().ToUpperInvariant() -ceq $esperada)
    if (-not $correcta) {
        Write-Log -Mensaje "Confirmacion no valida para '$Accion'. No se realizo ningun cambio." -Nivel WARN
    }
    return $correcta
}

function Show-GUIChoice {
    param(
        [string]$Titulo,
        [string]$Mensaje,
        [Parameter(Mandatory)][string[]]$Opciones
    )

    $dialog = New-Object System.Windows.Forms.Form
    Set-ModernFormStyle -Form $dialog
    $dialog.Text = $Titulo
    $dialog.Size = New-Object System.Drawing.Size(570, 235)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = $Script:GUIColors.BG
    $dialog.TopMost = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Mensaje
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(515, 38)
    $label.ForeColor = $Script:GUIColors.Text
    $label.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $dialog.Controls.Add($label)

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Location = New-Object System.Drawing.Point(20, 68)
    $combo.Size = New-Object System.Drawing.Size(515, 30)
    $combo.DropDownStyle = 'DropDownList'
    $combo.BackColor = $Script:GUIColors.Sidebar
    $combo.ForeColor = $Script:GUIColors.Text
    $combo.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    foreach ($opcion in $Opciones) { $null = $combo.Items.Add($opcion) }
    if ($combo.Items.Count -gt 0) { $combo.SelectedIndex = 0 }
    $dialog.Controls.Add($combo)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Continuar'
    $ok.Location = New-Object System.Drawing.Point(315, 125)
    $ok.Size = New-Object System.Drawing.Size(105, 36)
    $ok.BackColor = $Script:GUIColors.Accent
    $ok.ForeColor = $Script:GUIColors.BG
    $ok.FlatStyle = 'Flat'
    Set-ModernButtonStyle -Button $ok -BaseColor $Script:GUIColors.AccentDark -TextColor $Script:GUIColors.Text -HoverColor $Script:GUIColors.Accent
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancelar'
    $cancel.Location = New-Object System.Drawing.Point(430, 125)
    $cancel.Size = New-Object System.Drawing.Size(105, 36)
    $cancel.BackColor = $Script:GUIColors.Button
    $cancel.ForeColor = $Script:GUIColors.Text
    $cancel.FlatStyle = 'Flat'
    Set-ModernButtonStyle -Button $cancel
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dialog.Controls.Add($cancel)

    $dialog.AcceptButton = $ok
    $dialog.CancelButton = $cancel
    $resultado = if ($Script:GUIForm) { $dialog.ShowDialog($Script:GUIForm) } else { $dialog.ShowDialog() }
    $indice = if ($resultado -eq [System.Windows.Forms.DialogResult]::OK) { $combo.SelectedIndex } else { -1 }
    $dialog.Dispose()
    return $indice
}

function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Request-Administrator {
    if (Test-Admin) { return $true }
    try {
        $argumentos = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argumentos -ErrorAction Stop | Out-Null
        return $false
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "La herramienta necesita permisos de administrador.`n`n$($_.Exception.Message)",
            'CONTPAQi Toolbox', 'OK', 'Error'
        ) | Out-Null
        return $false
    }
}

function Get-PerfilEquipo {
    $tieneSQL = ($ServiciosSQL.Count -gt 0)
    $tieneAuth = (Get-ServiciosTerminal).Count -gt 0
    if ($tieneSQL -and $tieneAuth) { return 'Servidor+Terminal' }
    if ($tieneSQL) { return 'Servidor RDS/SQL' }
    if ($tieneAuth) { return 'Terminal/Estacion' }
    return 'Equipo generico'
}

# --- LOGIN GUI ---
function Show-Login {
    if (-not $Script:GUIForm) { return $false }

    $loginForm = New-Object System.Windows.Forms.Form
    Set-ModernFormStyle -Form $loginForm
    $loginForm.Text = 'CONTPAQi Toolbox - Acceso'
    $loginForm.Size = New-Object System.Drawing.Size(480, 440)
    $loginForm.StartPosition = 'CenterScreen'
    $loginForm.FormBorderStyle = 'FixedDialog'
    $loginForm.MaximizeBox = $false
    $loginForm.MinimizeBox = $false
    $loginForm.BackColor = $Script:GUIColors.BG
    $loginForm.TopMost = $true
    $loginForm.KeyPreview = $true

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = 'CONTPAQi TOOLBOX'
    $titleLabel.Location = New-Object System.Drawing.Point(105, 25)
    $titleLabel.Size = New-Object System.Drawing.Size(340, 38)
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 20, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $Script:GUIColors.Accent
    $titleLabel.TextAlign = 'MiddleLeft'
    $loginForm.Controls.Add($titleLabel)

    $subLabel = New-Object System.Windows.Forms.Label
    $subLabel.Text = 'Acceso restringido - Solo personal autorizado'
    $subLabel.Location = New-Object System.Drawing.Point(108, 66)
    $subLabel.Size = New-Object System.Drawing.Size(335, 20)
    $subLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $subLabel.ForeColor = $Script:GUIColors.TextDim
    $subLabel.TextAlign = 'MiddleLeft'
    $loginForm.Controls.Add($subLabel)

    $loginAccent = New-Object System.Windows.Forms.Panel
    $loginAccent.Dock = 'Top'
    $loginAccent.Height = 3
    $loginAccent.BackColor = $Script:GUIColors.Accent
    $loginForm.Controls.Add($loginAccent)

    $loginLogo = New-ToolboxLogoPictureBox -Size 68
    $loginLogo.Location = New-Object System.Drawing.Point(28, 18)
    $loginForm.Controls.Add($loginLogo)

    $loginCard = New-Object System.Windows.Forms.Panel
    $loginCard.Location = New-Object System.Drawing.Point(38, 105)
    $loginCard.Size = New-Object System.Drawing.Size(390, 260)
    $loginCard.BackColor = $Script:GUIColors.Surface
    $loginCard.Add_Paint({
        param($sender, $eventArgs)
        $pen = New-Object System.Drawing.Pen($Script:GUIColors.Separator)
        try { $eventArgs.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1) } finally { $pen.Dispose() }
    })
    $loginForm.Controls.Add($loginCard)

    $userLabel = New-Object System.Windows.Forms.Label
    $userLabel.Text = 'Usuario:'
    $userLabel.Location = New-Object System.Drawing.Point(24, 18)
    $userLabel.Size = New-Object System.Drawing.Size(100, 22)
    $userLabel.ForeColor = $Script:GUIColors.Text
    $userLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $loginCard.Controls.Add($userLabel)

    $userBox = New-Object System.Windows.Forms.TextBox
    $userBox.Location = New-Object System.Drawing.Point(24, 44)
    $userBox.Size = New-Object System.Drawing.Size(342, 29)
    $userBox.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $userBox.BackColor = $Script:GUIColors.LogBG
    $userBox.ForeColor = $Script:GUIColors.Text
    Set-ModernTextBoxStyle -TextBox $userBox
    $loginCard.Controls.Add($userBox)

    $passLabel = New-Object System.Windows.Forms.Label
    $passLabel.Text = 'Contrasena:'
    $passLabel.Location = New-Object System.Drawing.Point(24, 91)
    $passLabel.Size = New-Object System.Drawing.Size(100, 22)
    $passLabel.ForeColor = $Script:GUIColors.Text
    $passLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $loginCard.Controls.Add($passLabel)

    $passBox = New-Object System.Windows.Forms.TextBox
    $passBox.Location = New-Object System.Drawing.Point(24, 117)
    $passBox.Size = New-Object System.Drawing.Size(342, 29)
    $passBox.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $passBox.BackColor = $Script:GUIColors.LogBG
    $passBox.ForeColor = $Script:GUIColors.Text
    Set-ModernTextBoxStyle -TextBox $passBox
    $passBox.UseSystemPasswordChar = $true
    $loginCard.Controls.Add($passBox)

    $loginBtn = New-Object System.Windows.Forms.Button
    $loginBtn.Text = 'Ingresar'
    $loginBtn.Location = New-Object System.Drawing.Point(24, 181)
    $loginBtn.Size = New-Object System.Drawing.Size(162, 42)
    $loginBtn.BackColor = $Script:GUIColors.Accent
    $loginBtn.ForeColor = $Script:GUIColors.BG
    $loginBtn.FlatStyle = 'Flat'
    $loginBtn.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $loginBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    Set-ModernButtonStyle -Button $loginBtn -BaseColor $Script:GUIColors.AccentDark -TextColor $Script:GUIColors.Text -HoverColor $Script:GUIColors.Accent
    $loginBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $loginCard.Controls.Add($loginBtn)

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = 'Cancelar'
    $cancelBtn.Location = New-Object System.Drawing.Point(204, 181)
    $cancelBtn.Size = New-Object System.Drawing.Size(162, 42)
    $cancelBtn.BackColor = $Script:GUIColors.Button
    $cancelBtn.ForeColor = $Script:GUIColors.Text
    $cancelBtn.FlatStyle = 'Flat'
    $cancelBtn.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $cancelBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    Set-ModernButtonStyle -Button $cancelBtn
    $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $loginCard.Controls.Add($cancelBtn)

    $loginForm.AcceptButton = $loginBtn
    $loginForm.CancelButton = $cancelBtn

    $intentosMaximos = 3
    for ($intento = 1; $intento -le $intentosMaximos; $intento++) {
        $titleLabel.Text = "CONTPAQi TOOLBOX  ($intento/$intentosMaximos)"
        $userBox.Text = ''
        $passBox.Text = ''
        $loginForm.Text = "CONTPAQi Toolbox - Intento $intento de $intentosMaximos"

        $result = $loginForm.ShowDialog()
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $false }

        $usuarioInput = $userBox.Text
        $contrasenaInput = $passBox.Text

        $usuarioValido = $usuarioInput.Trim() -ceq $Script:LoginUser
        $hashValido = (Get-TextSha256 -Text $contrasenaInput) -ceq $Script:LoginPasswordHash
        $contrasenaInput = $null

        if ($usuarioValido -and $hashValido) {
            Write-Log -Mensaje "Acceso autorizado para $usuarioInput." -Nivel INFO
            $loginForm.Close()
            return $true
        }

        [System.Windows.Forms.MessageBox]::Show(
            "Usuario o contraseña incorrectos.`n`nIntento $intento de $intentosMaximos.",
            'Error de acceso', 'OK', 'Error'
        ) | Out-Null
    }

    $loginForm.Close()
    return $false
}

# --- GESTION DE SERVICIOS ---

function Find-ServicioCONTPAQi {
    param($EntradaCatalogo)

    foreach ($nombre in $EntradaCatalogo.Nombres) {
        $svc = Get-Service -Name $nombre -ErrorAction SilentlyContinue
        if ($svc) {
            return [PSCustomObject]@{
                Servicio    = $svc
                Etiqueta    = $EntradaCatalogo.Etiqueta
                Id          = $EntradaCatalogo.Id
                EncontradoPor = "Nombre: $nombre"
            }
        }
    }

    $todos = Get-Service -ErrorAction SilentlyContinue
    foreach ($patron in $EntradaCatalogo.PatronesDisplay) {
        $svc = $todos | Where-Object { $_.DisplayName -like $patron } | Select-Object -First 1
        if ($svc) {
            return [PSCustomObject]@{
                Servicio     = $svc
                Etiqueta     = $EntradaCatalogo.Etiqueta
                Id           = $EntradaCatalogo.Id
                EncontradoPor = "Display: $patron"
            }
        }
    }

    return $null
}

function Get-ServiciosTerminal {
    $resultado = @()
    foreach ($item in $Script:CatalogoTerminal) {
        $found = Find-ServicioCONTPAQi -EntradaCatalogo $item
        if ($found) { $resultado += $found }
    }
    return $resultado
}

function Get-NombresServiciosTerminal {
    return (Get-ServiciosTerminal | ForEach-Object { $_.Servicio.Name })
}

function Get-EstadoTexto {
    param([System.ServiceProcess.ServiceController]$Servicio)
    switch ($Servicio.Status) {
        'Running'  { return 'En ejecucion' }
        'Stopped'  { return 'Detenido' }
        'StartPending' { return 'Iniciando...' }
        'StopPending'  { return 'Deteniendo...' }
        default    { return $Servicio.Status.ToString() }
    }
}

function Show-EstadoServiciosTerminal {
    Write-Encabezado -Titulo 'ESTADO SERVICIOS TERMINAL' -Subtitulo 'AuthServer y licencias locales CONTPAQi' -Color $Script:ColorTerminal

    $servicios = @(Get-ServiciosTerminal)
    if ($servicios.Count -eq 0) {
        Write-Log -Mensaje 'No se detectaron servicios AuthServer/Licencias en este equipo.' -Nivel WARN
        Write-Linea -Texto ' Verifica que CONTPAQi este instalado en la terminal.' -Color $Script:ColorInfo
        return
    }

    $activos = 0
    $detenidos = 0
    foreach ($item in $servicios) {
        $svc = $item.Servicio
        $estado = Get-EstadoTexto -Servicio $svc
        $color = if ($svc.Status -eq 'Running') { $Script:ColorExito } else { $Script:ColorError }
        if ($svc.Status -eq 'Running') { $activos++ } else { $detenidos++ }

        Write-Host ''
        Write-Linea -Texto " $($item.Etiqueta)" -Color $Script:ColorAcento
        Write-Log -Mensaje "Nombre: $($svc.Name)" -Nivel INFO
        Write-Log -Mensaje "Visible: $($svc.DisplayName)" -Nivel INFO
        Write-Host "       Estado: $estado" -ForegroundColor $color
        Write-Log -Mensaje "Inicio: $($svc.StartType)" -Nivel INFO
    }

    Write-Host ''
    Write-Separador -Caracter '-' -Color 'DarkGray'
    Write-Log -Mensaje "Resumen: $activos en ejecucion | $detenidos detenidos | $($servicios.Count) detectados" -Nivel OK

    Write-SeccionMenu -Titulo 'PROCESOS PID QUE INTERVIENEN CON CONTPAQi' -Color $Script:ColorAdvertencia
    $procesosPID = @(Get-ProcesosPID | Where-Object { -not $_.EsToolbox })
    if ($procesosPID.Count -eq 0) {
        Write-Log -Mensaje 'Sin procesos PID activos en esta terminal.' -Nivel OK
    } else {
        foreach ($p in $procesosPID) {
            Write-Log -Mensaje "PID $($p.PID) | $($p.Nombre.PadRight(18)) | Modulo: $($p.Modulo.PadRight(24)) | $($p.Usuario)" -Nivel PROGRESS
        }
    }

    $serviciosPID = @(Get-ServiciosPID)
    if ($serviciosPID.Count -gt 0) {
        Write-SeccionMenu -Titulo 'SERVICIOS PID DETECTADOS' -Color $Script:ColorAdvertencia
        foreach ($svc in $serviciosPID) {
            $color = if ($svc.Status -eq 'Running') { $Script:ColorExito } else { $Script:ColorError }
            Write-Host "  $($svc.DisplayName) -> $(Get-EstadoTexto -Servicio $svc)" -ForegroundColor $color
        }
    }
}

function Wait-ServicioEstado {
    param(
        [string]$NombreServicio,
        [ValidateSet('Running', 'Stopped')]
        [string]$EstadoDeseado,
        [int]$MaxIntentos = 40
    )
    $intentos = 0
    do {
        $svc = Get-Service -Name $NombreServicio -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status.ToString() -eq $EstadoDeseado) { return $true }
        Refresh-Log
        Start-Sleep -Milliseconds 300
        $intentos++
    } while ($intentos -lt $MaxIntentos)
    return $false
}

function Start-GrupoServicios {
    param(
        [array]$listaServicios,
        [string]$nombreGrupo,
        [switch]$SoloDetenidos,
        [switch]$ConfirmacionOmitida
    )

    Write-Encabezado -Titulo 'INICIO DE SERVICIOS' -Subtitulo $nombreGrupo -Color $Script:ColorTerminal
    $serviciosEncontrados = @()

    foreach ($svc in $listaServicios) {
        $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($svcObj) { $serviciosEncontrados += $svcObj }
        else { Write-Log -Mensaje "Servicio '$svc' no instalado." -Nivel INFO }
    }

    if ($serviciosEncontrados.Count -eq 0) {
        Write-Log -Mensaje 'No se detectaron servicios.' -Nivel WARN
        return
    }
    if ($SoloDetenidos -and @($serviciosEncontrados | Where-Object Status -ne 'Running').Count -eq 0) {
        Write-Log -Mensaje 'Todos los servicios seleccionados ya estan en ejecucion; no se requiere ningun cambio.' -Nivel OK
        return
    }
    if (-not $ConfirmacionOmitida -and -not (Confirmar-Movimiento -Frase 'INICIAR SERVICIOS' `
        -Accion "Iniciar servicios: $nombreGrupo" `
        -Detalle 'Se modificara el estado de los servicios detenidos seleccionados.')) { return }

    $iniciados = 0
    $fallidos = 0
    foreach ($svc in $serviciosEncontrados) {
        if ($SoloDetenidos -and $svc.Status -eq 'Running') {
            Write-Log -Mensaje "$($svc.DisplayName) ya esta en ejecucion." -Nivel INFO
            continue
        }
        Write-Log -Mensaje "Iniciando $($svc.DisplayName)..." -Nivel PROGRESS
        $resultadoInicio = Invoke-ServiceActionResponsive -Nombre $svc.Name -Accion Start -TimeoutSegundos 75
        if (-not $resultadoInicio.Correcto) {
            $fallidos++
            Write-Log -Mensaje "No se pudo iniciar $($svc.Name): $($resultadoInicio.Error)" -Nivel ERROR
            continue
        }
        Write-Log -Mensaje "$($svc.Name) iniciado." -Nivel OK
        $iniciados++
    }

    $nivelFinal = if ($fallidos -eq 0) { 'OK' } else { 'WARN' }
    Write-Log -Mensaje "Resultado: $iniciados iniciado(s), $fallidos fallido(s)." -Nivel $nivelFinal
}

function Reiniciar-GrupoServicios {
    param(
        [array]$listaServicios,
        [string]$nombreGrupo,
        [switch]$ConfirmacionOmitida
    )

    Write-Encabezado -Titulo 'REINICIO DE SERVICIOS' -Subtitulo $nombreGrupo -Color 'Cyan'
    $serviciosEncontrados = @()

    foreach ($svc in $listaServicios) {
        $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($svcObj) { $serviciosEncontrados += $svcObj }
        else { Write-Log -Mensaje "Servicio '$svc' no instalado." -Nivel INFO }
    }

    if ($serviciosEncontrados.Count -eq 0) {
        Write-Log -Mensaje 'No se detectaron servicios de este grupo.' -Nivel WARN
        return
    }
    if (-not $ConfirmacionOmitida -and -not (Confirmar-Movimiento -Frase 'REINICIAR SERVICIOS' `
        -Accion "Reiniciar servicios: $nombreGrupo" `
        -Detalle 'Los servicios se detendran temporalmente; las aplicaciones conectadas pueden perder su sesion.')) { return }

    $fallidos = 0
    Write-Host ''
    Write-Linea -Texto '--- Deteniendo servicios ---' -Color $Script:ColorAdvertencia
    foreach ($svc in $serviciosEncontrados) {
        $currentSvc = Get-Service -Name $svc.Name
        if ($currentSvc.Status -eq 'Running') {
            Write-Log -Mensaje "Deteniendo $($svc.DisplayName)..." -Nivel PROGRESS
            $resultadoDetener = Invoke-ServiceActionResponsive -Nombre $svc.Name -Accion Stop -TimeoutSegundos 60
            if (-not $resultadoDetener.Correcto) {
                $fallidos++
                Write-Log -Mensaje "No se pudo detener $($svc.Name): $($resultadoDetener.Error)" -Nivel ERROR
                continue
            }
            Write-Log -Mensaje "$($svc.Name) detenido." -Nivel OK
        } else {
            Write-Log -Mensaje "$($svc.DisplayName) ya estaba detenido." -Nivel INFO
        }
    }

    Write-Log -Mensaje 'Espera de seguridad (3 seg)...' -Nivel INFO
    Wait-Responsive -Seconds 3

    Write-Host ''
    Write-Linea -Texto '--- Iniciando servicios ---' -Color $Script:ColorExito
    [array]::Reverse($serviciosEncontrados)
    foreach ($svc in $serviciosEncontrados) {
        Write-Log -Mensaje "Iniciando $($svc.DisplayName)..." -Nivel PROGRESS
        $resultadoInicio = Invoke-ServiceActionResponsive -Nombre $svc.Name -Accion Start -TimeoutSegundos 75
        if (-not $resultadoInicio.Correcto) {
            $fallidos++
            Write-Log -Mensaje "No se pudo iniciar $($svc.Name): $($resultadoInicio.Error)" -Nivel ERROR
            continue
        }
        Write-Log -Mensaje "$($svc.Name) en ejecucion." -Nivel OK
    }

    $nivelFinal = if ($fallidos -eq 0) { 'OK' } else { 'WARN' }
    $mensajeFinal = if ($fallidos -eq 0) {
        "Reinicio de '$nombreGrupo' completado y verificado."
    } else {
        "Reinicio de '$nombreGrupo' finalizado con $fallidos incidencia(s). Revisa el detalle anterior."
    }
    Write-Log -Mensaje $mensajeFinal -Nivel $nivelFinal
}

function Reiniciar-TodosServiciosTerminal {
    param([switch]$ConfirmacionOmitida)
    $nombres = Get-NombresServiciosTerminal
    if ($nombres.Count -eq 0) {
        Write-Encabezado -Titulo 'SIN SERVICIOS TERMINAL' -Subtitulo 'No hay AuthServer/Licencias detectados' -Color $Script:ColorError
        return
    }
    Reiniciar-GrupoServicios -listaServicios $nombres -nombreGrupo 'TODOS LOS AUTHSERVER / LICENCIAS (TERMINAL)' -ConfirmacionOmitida:$ConfirmacionOmitida
}

function Iniciar-ServiciosTerminalDetenidos {
    $nombres = Get-NombresServiciosTerminal
    if ($nombres.Count -eq 0) {
        Write-Encabezado -Titulo 'SIN SERVICIOS TERMINAL' -Subtitulo 'No hay AuthServer/Licencias detectados' -Color $Script:ColorError
        return
    }
    Start-GrupoServicios -listaServicios $nombres -nombreGrupo 'SERVICIOS DETENIDOS (TERMINAL)' -SoloDetenidos
}

function Get-ServiciosReparacionTerminal {
    $encontrados = @{}
    foreach ($item in @(Get-ServiciosTerminal)) {
        if ($item.Servicio) { $encontrados[$item.Servicio.Name] = $item.Servicio }
    }
    foreach ($servicio in @(Get-Service -ErrorAction SilentlyContinue)) {
        $referencia = "$($servicio.Name) $($servicio.DisplayName)"
        $esTerminal = (
            $servicio.Name -match '^(?i)(Saci_CONTPAQi|AuthServer_|AppKeyLicenseServer_|CONTPAQi_XML|XMLService)' -or
            ($referencia -match '(?i)(CONTPAQ|COMPAC)' -and $referencia -match '(?i)(AuthServer|licen|XML en l.nea)')
        )
        if ($esTerminal -and $servicio.Name -notin @($Script:ServicesDevName, $Script:ServicesDevLegacyName)) {
            $encontrados[$servicio.Name] = $servicio
        }
    }
    return @($encontrados.Values | Sort-Object Name)
}

function Start-ServiciosTerminalVerificado {
    param([ValidateRange(1, 3)][int]$Intentos = 2)

    $servicios = @(Get-ServiciosReparacionTerminal | Sort-Object `
        @{ Expression = { Get-OrdenInicioServicioCONTPAQi -Servicio $_ } }, Name)
    $correctos = 0
    $omitidos = 0
    $fallidos = New-Object System.Collections.Generic.List[string]
    foreach ($servicio in $servicios) {
        $nombre = $servicio.Name
        if (Test-ServicioDeshabilitado -Nombre $nombre) {
            $omitidos++
            Write-Log -Mensaje "$nombre esta deshabilitado; se conserva su configuracion." -Nivel WARN
            continue
        }
        $iniciado = $false
        $ultimoError = ''
        for ($intento = 1; $intento -le $Intentos -and -not $iniciado; $intento++) {
            $actual = Get-Service -Name $nombre -ErrorAction SilentlyContinue
            if ($actual -and $actual.Status -eq 'Running') {
                $iniciado = $true
                break
            }
            $resultado = Invoke-ServiceActionResponsive -Nombre $nombre -Accion Start -TimeoutSegundos 75
            $iniciado = $resultado.Correcto
            $ultimoError = $resultado.Error
            if (-not $iniciado -and $intento -lt $Intentos) {
                Write-Log -Mensaje "$nombre no inicio; se realizara un segundo intento." -Nivel WARN
                Wait-Responsive -Seconds 1
            }
        }
        if ($iniciado) {
            $correctos++
            Write-Log -Mensaje "$nombre activo y verificado." -Nivel OK
        } else {
            $fallidos.Add($nombre)
            Write-Log -Mensaje "No se pudo iniciar $($nombre): $ultimoError" -Nivel ERROR
        }
    }
    return [PSCustomObject]@{
        Total = $servicios.Count; Correctos = $correctos; Omitidos = $omitidos
        Fallidos = $fallidos.Count; FallidosNombres = @($fallidos)
    }
}

function Reset-TerminalRapido {
    Write-Encabezado -Titulo 'REPARACION COMPLETA DE TERMINAL' -Subtitulo 'Aplicaciones + servicios + temporales + red + validacion' -Color $Script:ColorTerminal
    Write-Log -Mensaje 'La reparacion trabaja solo sobre esta estacion: no detiene SQL ni servicios del servidor remoto.' -Nivel INFO
    if (-not (Confirmar-Movimiento -Frase 'REPARAR TERMINAL' `
        -Accion 'Reparar esta terminal CONTPAQi' `
        -Detalle 'Se cerraran aplicaciones locales, reiniciaran AuthServer/licencias, limpiaran temporales y validaran red, binarios y permisos.')) { return }

    $inicio = Get-Date
    $incidencias = 0
    $advertencias = 0
    $proteccionServicesDev = Suspend-ServicesDevForRepair
    if (-not $proteccionServicesDev.Correcto) { return }
    try {
        Write-Log -Mensaje '[1/10] Inventario de la terminal y comprobaciones previas...' -Nivel PROGRESS
        $serviciosTerminal = @(Get-ServiciosReparacionTerminal | Sort-Object `
            @{ Expression = { Get-OrdenInicioServicioCONTPAQi -Servicio $_ } }, Name)
        $procesosTerminal = @((Get-ProcesosCONTPAQi) + (Get-ProcesosPID)) |
            Where-Object { -not $_.EsToolbox } | Sort-Object PID -Unique
        $rutasTerminal = @(Get-RutasCONTPAQi)
        Write-Log -Mensaje "Detectados: $($serviciosTerminal.Count) servicios de terminal | $($procesosTerminal.Count) procesos | $($rutasTerminal.Count) rutas CONTPAQi." -Nivel INFO
        if ($serviciosTerminal.Count -eq 0) {
            $advertencias++
            Write-Log -Mensaje 'No se detectaron AuthServer o servicios de licencia locales; se continuara con las demas validaciones.' -Nivel WARN
        }

        Write-Log -Mensaje '[2/10] Cerrando aplicaciones CONTPAQi/PID de esta estacion...' -Nivel PROGRESS
        foreach ($proceso in $procesosTerminal) {
            if (Stop-ProcesoForzado -ProcessId $proceso.PID -TimeoutSegundos 10) {
                Write-Log -Mensaje "PID $($proceso.PID) ($($proceso.Nombre)) cerrado." -Nivel OK
            } else {
                $incidencias++
                Write-Log -Mensaje "No fue posible cerrar PID $($proceso.PID) ($($proceso.Nombre))." -Nivel ERROR
            }
        }
        if ($procesosTerminal.Count -eq 0) { Write-Log -Mensaje 'No habia aplicaciones CONTPAQi abiertas.' -Nivel OK }

        Write-Log -Mensaje '[3/10] Deteniendo servicios locales de licencia y AuthServer...' -Nivel PROGRESS
        $serviciosStop = @($serviciosTerminal)
        [array]::Reverse($serviciosStop)
        foreach ($servicio in $serviciosStop) {
            $actual = Get-Service -Name $servicio.Name -ErrorAction SilentlyContinue
            if (-not $actual -or $actual.Status -eq 'Stopped') { continue }
            $resultadoStop = Invoke-ServiceActionResponsive -Nombre $actual.Name -Accion Stop -TimeoutSegundos 75
            if ($resultadoStop.Correcto) {
                Write-Log -Mensaje "$($actual.Name) detenido." -Nivel OK
            } else {
                $incidencias++
                Write-Log -Mensaje "No se pudo detener $($actual.Name): $($resultadoStop.Error)" -Nivel ERROR
            }
        }

        Write-Log -Mensaje '[4/10] Limpiando temporales seguros de CONTPAQi...' -Nivel PROGRESS
        $temporalesTerminal = @(
            (Join-Path $env:LOCALAPPDATA 'Temp\Compac'),
            (Join-Path $env:LOCALAPPDATA 'Temp\CONTPAQi'),
            'C:\Windows\Temp\Compac',
            'C:\Windows\Temp\CONTPAQi'
        ) | Select-Object -Unique
        $eliminados = 0
        foreach ($ruta in $temporalesTerminal) { $eliminados += Clear-TemporalSeguro -Ruta $ruta }
        Write-Log -Mensaje "Limpieza terminada: $eliminados elemento(s) eliminados; los archivos en uso se conservaron." -Nivel OK

        Write-Log -Mensaje '[5/10] Renovando DNS y recuperando dependencias de Windows...' -Nivel PROGRESS
        $dns = Invoke-DnsFlushResponsive
        if ($dns.Correcto) { Write-Log -Mensaje 'Cache DNS renovada correctamente.' -Nivel OK }
        else { $advertencias++; Write-Log -Mensaje "No se pudo renovar DNS: $($dns.Error)" -Nivel WARN }
        foreach ($nombre in @('Dnscache', 'LanmanWorkstation', 'CryptSvc', 'W32Time')) {
            $dependencia = Get-Service -Name $nombre -ErrorAction SilentlyContinue
            if (-not $dependencia) { continue }
            if (Test-ServicioDeshabilitado -Nombre $nombre) {
                $advertencias++
                Write-Log -Mensaje "$nombre esta deshabilitado; no se modifico su tipo de inicio." -Nivel WARN
                continue
            }
            if ($dependencia.Status -ne 'Running') {
                $resultadoDependencia = Invoke-ServiceActionResponsive -Nombre $nombre -Accion Start -TimeoutSegundos 60
                if (-not $resultadoDependencia.Correcto) {
                    $incidencias++
                    Write-Log -Mensaje "No se pudo iniciar la dependencia $($nombre): $($resultadoDependencia.Error)" -Nivel ERROR
                    continue
                }
            }
            Write-Log -Mensaje "Dependencia $nombre activa." -Nivel OK
        }

        Write-Log -Mensaje '[6/10] Auditando rutas, ejecutables y permisos locales...' -Nivel PROGRESS
        foreach ($servicio in $serviciosTerminal) {
            try {
                $nombreSeguro = $servicio.Name.Replace("'", "''")
                $cim = Get-CimInstance Win32_Service -Filter "Name='$nombreSeguro'" -ErrorAction Stop
                $rutaExe = Get-RutaEjecutableServicio -Comando $cim.PathName
                if ($rutaExe -and (Test-Path -LiteralPath $rutaExe -PathType Leaf)) {
                    Write-Log -Mensaje "$($servicio.Name): ejecutable disponible." -Nivel OK
                } else {
                    $incidencias++
                    Write-Log -Mensaje "$($servicio.Name): ejecutable ausente o ruta invalida ($rutaExe)." -Nivel ERROR
                }
            } catch {
                $advertencias++
                Write-Log -Mensaje "$($servicio.Name): no fue posible auditar su ejecutable." -Nivel WARN
            }
        }
        $rutasPermisos = @(Get-RutasPermisosTerminalCONTPAQi)
        foreach ($rutaPermiso in $rutasPermisos) {
            $permisoCorrecto = Test-PermisoUsuariosCONTPAQi -Ruta $rutaPermiso.Ruta -Derecho $rutaPermiso.Derecho
            if ($permisoCorrecto) {
                Write-Log -Mensaje "Permiso $($rutaPermiso.Derecho) correcto: $($rutaPermiso.Ruta)" -Nivel OK
            } else {
                $advertencias++
                Write-Log -Mensaje "Permiso incompleto: $($rutaPermiso.Ruta). Solicita a un administrador que valide la ACL de esta ruta." -Nivel WARN
            }
        }

        Write-Log -Mensaje '[7/10] Iniciando y verificando AuthServer/licencias...' -Nivel PROGRESS
        $resultadoServicios = Start-ServiciosTerminalVerificado -Intentos 2
        $incidencias += $resultadoServicios.Fallidos
        Write-Log -Mensaje "Terminal: $($resultadoServicios.Correctos) activos, $($resultadoServicios.Fallidos) con incidencia, $($resultadoServicios.Omitidos) deshabilitados de $($resultadoServicios.Total)." -Nivel $(if ($resultadoServicios.Fallidos -eq 0) { 'OK' } else { 'WARN' })

        Write-Log -Mensaje '[8/10] Detectando y validando comunicacion con el servidor...' -Nivel PROGRESS
        $candidatosServidor = @(Find-ServidoresCONTPAQi)
        if ($candidatosServidor.Count -eq 0) {
            $advertencias++
            Write-Log -Mensaje 'No se encontro un servidor configurado. Revisa nombre del servidor, VPN o configuracion de la terminal.' -Nivel WARN
        } else {
            $servidor = $candidatosServidor[0]
            $puertos = @($servidor.PuertosAbiertos)
            if ($servidor.IPs.Count -gt 0 -and $puertos.Count -gt 0) {
                Write-Log -Mensaje "Servidor detectado: $($servidor.Host) -> $($servidor.IPs -join ', ') | Puertos disponibles: $($puertos -join ', ')." -Nivel OK
            } elseif ($servidor.IPs.Count -gt 0) {
                $incidencias++
                Write-Log -Mensaje "El servidor $($servidor.Host) resuelve por DNS, pero no respondio en puertos CONTPAQi/SQL." -Nivel ERROR
            } else {
                $incidencias++
                Write-Log -Mensaje "No fue posible resolver por DNS el servidor configurado $($servidor.Host)." -Nivel ERROR
            }
        }

        Write-Log -Mensaje '[9/10] Auditoria final de la terminal...' -Nivel PROGRESS
        $detenidosFinales = @(Get-ServiciosReparacionTerminal | Where-Object {
            -not (Test-ServicioDeshabilitado -Nombre $_.Name) -and $_.Status -ne 'Running'
        })
        if ($detenidosFinales.Count -gt 0) {
            $incidencias += $detenidosFinales.Count
            Write-Log -Mensaje "Servicios que no quedaron activos: $($detenidosFinales.Name -join ', ')." -Nivel ERROR
        } else {
            Write-Log -Mensaje 'Todos los servicios de terminal habilitados quedaron activos.' -Nivel OK
        }
    } catch {
        $incidencias++
        Write-Log -Mensaje "Error inesperado durante la reparacion de terminal: $($_.Exception.Message)" -Nivel ERROR
    } finally {
        Write-Log -Mensaje '[10/10] Restaurando el monitor ServicesDev...' -Nivel PROGRESS
        if (-not (Restore-ServicesDevAfterRepair -Estados $proteccionServicesDev.Estados)) { $incidencias++ }
    }

    $duracion = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    Write-Host ''
    $colorFinal = if ($incidencias -eq 0) { $Script:ColorExito } else { $Script:ColorAdvertencia }
    Write-Separador -Color $colorFinal
    if ($incidencias -eq 0) {
        Write-Linea -Texto ' REPARACION DE TERMINAL COMPLETADA Y VERIFICADA' -Color $colorFinal -Centrado
        Write-Log -Mensaje "Terminal reparada en $duracion segundos con $advertencias advertencia(s) informativa(s)." -Nivel OK
    } else {
        Write-Linea -Texto " REPARACION DE TERMINAL CON $incidencias INCIDENCIA(S)" -Color $colorFinal -Centrado
        Write-Log -Mensaje "Proceso terminado en $duracion segundos. Revisa las incidencias antes de abrir CONTPAQi." -Nivel WARN
    }
    if (Test-ReinicioPendiente) { Write-Log -Mensaje 'Windows tiene un reinicio pendiente; reinicia la terminal antes de validar nuevamente.' -Nivel WARN }
    else { Write-Log -Mensaje 'Abre CONTPAQi y valida acceso a empresas, licencias, ADD y timbrado desde esta terminal.' -Nivel INFO }
}

# --- PROCESOS Y SESIONES ---

function Get-SesionesActivas {
    $sesiones = @()
    try {
        $salida = query user 2>$null
        if (-not $salida) { return $sesiones }

        foreach ($linea in $salida | Select-Object -Skip 1) {
            $linea = ($linea -replace '\s{2,}', '|').Trim('|')
            $partes = $linea -split '\|'
            if ($partes.Count -ge 4) {
                $sesiones += [PSCustomObject]@{
                    Usuario   = $partes[0].Trim()
                    SessionId = ($partes[2] -replace '\D', '').Trim()
                    Estado    = $partes[3].Trim()
                }
            }
        }
    } catch {
        Write-Log -Mensaje "No se pudieron consultar sesiones: $($_.Exception.Message)" -Nivel WARN
    }
    return $sesiones
}

function Get-ProcesosCONTPAQi {
    $encontrados = @{}
    $rutasPorPid = @{}
    $miPid = $PID

    foreach ($nombre in $ProcesosCONTPAQi) {
        Get-Process -Name $nombre -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $encontrados.ContainsKey($_.Id)) { $encontrados[$_.Id] = $_ }
        }
    }

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            if (-not $_.ExecutablePath) { return ($ProcesosCONTPAQi -contains $_.Name) }
            foreach ($patron in $PatronesRutaCONTPAQi) {
                if ($_.ExecutablePath -like $patron) { return $true }
            }
            return ($ProcesosCONTPAQi -contains $_.Name)
        } |
        ForEach-Object {
            if ($_.ExecutablePath) { $rutasPorPid[$_.ProcessId] = $_.ExecutablePath }
            if (-not $encontrados.ContainsKey($_.ProcessId)) {
                $proc = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
                if ($proc) { $encontrados[$proc.Id] = $proc }
            }
        }

    $resultado = @()
    foreach ($proc in $encontrados.Values) {
        $usuarioProc = 'N/D'
        try {
            $owner = Invoke-CimMethod -InputObject (
                Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue
            ) -MethodName GetOwner -ErrorAction SilentlyContinue
            if ($owner -and $owner.User) {
                $usuarioProc = if ($owner.Domain) { "$($owner.Domain)\$($owner.User)" } else { $owner.User }
            }
        } catch { }

        $rutaProc = if ($rutasPorPid.ContainsKey($proc.Id)) { $rutasPorPid[$proc.Id] } else { '' }

        $resultado += [PSCustomObject]@{
            PID       = $proc.Id
            Nombre    = $proc.ProcessName
            Usuario   = $usuarioProc
            Modulo    = Get-ModuloProceso -Nombre $proc.ProcessName -RutaEjecutable $rutaProc
            EsToolbox = ($proc.Id -eq $miPid)
        }
    }

    return $resultado | Sort-Object Usuario, Nombre
}

function Stop-ProcesoForzado {
    param([int]$ProcessId, [int]$TimeoutSegundos = 8)

    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) { return $true }

    try {
        $proc.CloseMainWindow() | Out-Null
        $limiteCierre = (Get-Date).AddSeconds([math]::Min($TimeoutSegundos, 4))
        while ((Get-Date) -lt $limiteCierre -and (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
            Wait-Responsive -Seconds 0.12
        }
    } catch { }

    if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
        Wait-Responsive -Seconds 0.4
    }

    return -not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

# --- PROCESOS Y SERVICIOS PID (INTEGRACION CONTPAQi) ---

function Get-ProcesosPID {
    $encontrados = @{}
    $rutasPorPid = @{}
    $miPid = $PID

    foreach ($nombre in $ProcesosPID) {
        Get-Process -Name $nombre -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $encontrados.ContainsKey($_.Id)) { $encontrados[$_.Id] = $_ }
        }
    }

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $nombreProc = $_.Name
            $coincideNombre = $false
            foreach ($patron in $PatronesNombrePID) {
                if ($nombreProc -like $patron) { $coincideNombre = $true; break }
            }
            if ($coincideNombre) { return $true }

            if ($_.ExecutablePath) {
                foreach ($patron in $PatronesRutaPID) {
                    if ($_.ExecutablePath -like $patron) { return $true }
                }
            }
            return ($ProcesosPID -contains $nombreProc)
        } |
        ForEach-Object {
            if ($_.ExecutablePath) { $rutasPorPid[$_.ProcessId] = $_.ExecutablePath }
            if (-not $encontrados.ContainsKey($_.ProcessId)) {
                $proc = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
                if ($proc) { $encontrados[$proc.Id] = $proc }
            }
        }

    $resultado = @()
    foreach ($proc in $encontrados.Values) {
        $usuarioProc = 'N/D'
        try {
            $owner = Invoke-CimMethod -InputObject (
                Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue
            ) -MethodName GetOwner -ErrorAction SilentlyContinue
            if ($owner -and $owner.User) {
                $usuarioProc = if ($owner.Domain) { "$($owner.Domain)\$($owner.User)" } else { $owner.User }
            }
        } catch { }

        $rutaProc = if ($rutasPorPid.ContainsKey($proc.Id)) { $rutasPorPid[$proc.Id] } else { '' }

        $resultado += [PSCustomObject]@{
            PID       = $proc.Id
            Nombre    = $proc.ProcessName
            Usuario   = $usuarioProc
            Modulo    = Get-ModuloProceso -Nombre $proc.ProcessName -RutaEjecutable $rutaProc
            EsToolbox = ($proc.Id -eq $miPid)
        }
    }

    return $resultado | Sort-Object Usuario, Nombre
}

function Get-ServiciosPID {
    $encontrados = @{}

    foreach ($nombre in $ProcesosPID) {
        $svc = Get-Service -Name $nombre -ErrorAction SilentlyContinue
        if ($svc -and -not $encontrados.ContainsKey($svc.Name)) { $encontrados[$svc.Name] = $svc }
    }

    $todos = Get-Service -ErrorAction SilentlyContinue
    foreach ($patron in $PatronesServicioPID) {
        $todos | Where-Object { $_.DisplayName -like $patron -or $_.Name -like $patron } | ForEach-Object {
            if (-not $encontrados.ContainsKey($_.Name)) { $encontrados[$_.Name] = $_ }
        }
    }

    return $encontrados.Values | Sort-Object Name
}

function Show-EstadoPIDServidor {
    Write-Encabezado -Titulo 'ESTADO PID - SERVIDOR' -Subtitulo 'Servicios y procesos PID que intervienen con CONTPAQi' -Color $Script:ColorServidor

    Write-SeccionMenu -Titulo 'SERVICIOS PID DETECTADOS' -Color $Script:ColorServidor
    $serviciosPID = @(Get-ServiciosPID)
    if ($serviciosPID.Count -eq 0) {
        Write-Log -Mensaje 'No se detectaron servicios PID en este equipo.' -Nivel INFO
    } else {
        foreach ($svc in $serviciosPID) {
            $color = if ($svc.Status -eq 'Running') { $Script:ColorExito } else { $Script:ColorError }
            Write-Host "  $($svc.DisplayName)" -ForegroundColor $Script:ColorAcento
            Write-Host "    -> $(Get-EstadoTexto -Servicio $svc) | $($svc.Name)" -ForegroundColor $color
        }
    }

    Write-SeccionMenu -Titulo 'PROCESOS PID EN EJECUCION' -Color $Script:ColorAdvertencia
    $procesosPID = @(Get-ProcesosPID | Where-Object { -not $_.EsToolbox })
    if ($procesosPID.Count -eq 0) {
        Write-Log -Mensaje 'Sin procesos PID activos.' -Nivel OK
    } else {
        foreach ($p in $procesosPID) {
            Write-Log -Mensaje "PID $($p.PID) | $($p.Nombre.PadRight(18)) | Modulo: $($p.Modulo.PadRight(24)) | $($p.Usuario)" -Nivel PROGRESS
        }
    }

    Write-Host ''
    Write-Separador -Caracter '-' -Color 'DarkGray'
    Write-Log -Mensaje "Resumen: $($serviciosPID.Count) servicios PID | $($procesosPID.Count) procesos PID activos" -Nivel OK
}

function Expulsar-UsuariosSistemas {
    Write-Encabezado -Titulo 'EXPULSION FORZADA DE USUARIOS' -Subtitulo 'Servidor RDS - Todas las sesiones' -Color $Script:ColorServidor

    Write-Linea -Texto ' Cierra FORZOSAMENTE procesos CONTPAQi en TODAS las sesiones.' -Color $Script:ColorAdvertencia
    Write-Linea -Texto ' Tambien limpia sesiones RDP en estado Desconectado.' -Color $Script:ColorAdvertencia

    if (-not (Confirmar-Movimiento -Frase 'CERRAR SESIONES' `
        -Accion 'Cerrar procesos y sesiones CONTPAQi del servidor' `
        -Detalle 'Se cerraran procesos en todas las sesiones y se desconectaran sesiones RDP inactivas; puede existir trabajo no guardado.')) { return }

    Write-Host ''
    Write-Separador -Caracter '-' -Color 'DarkYellow'
    Write-Linea -Texto ' PASO 1/4 - Sesiones activas' -Color 'DarkYellow'
    Write-Separador -Caracter '-' -Color 'DarkYellow'

    $sesiones = @(Get-SesionesActivas)
    if ($sesiones.Count -eq 0) {
        Write-Log -Mensaje 'No se detectaron sesiones RDP/Terminal.' -Nivel INFO
    } else {
        foreach ($ses in $sesiones) {
            Write-Log -Mensaje "Sesion $($ses.SessionId) | $($ses.Usuario) | $($ses.Estado)" -Nivel INFO
        }
    }

    Write-Host ''
    Write-Separador -Caracter '-' -Color 'DarkYellow'
    Write-Linea -Texto ' PASO 2/4 - Procesos CONTPAQi' -Color 'DarkYellow'
    Write-Separador -Caracter '-' -Color 'DarkYellow'

    $procesos = @(Get-ProcesosCONTPAQi | Where-Object { -not $_.EsToolbox })
    foreach ($p in $procesos) {
        Write-Log -Mensaje "PID $($p.PID) | $($p.Nombre) | Modulo: $($p.Modulo) | $($p.Usuario)" -Nivel PROGRESS
    }
    if ($procesos.Count -eq 0) { Write-Log -Mensaje 'Sin procesos CONTPAQi activos.' -Nivel INFO }

    Write-Host ''
    Write-Separador -Caracter '-' -Color 'DarkYellow'
    Write-Linea -Texto ' PASO 3/4 - Cierre forzado' -Color 'DarkYellow'
    Write-Separador -Caracter '-' -Color 'DarkYellow'

    $cerrados = 0
    $fallidos = 0
    foreach ($p in $procesos) {
        if (Stop-ProcesoForzado -ProcessId $p.PID) {
            Write-Log -Mensaje "$($p.Nombre) (PID $($p.PID)) cerrado." -Nivel OK
            $cerrados++
        } else {
            $null = Invoke-ProcessResponsive -FilePath 'taskkill.exe' -ArgumentList "/PID $($p.PID) /F /T" `
                -TimeoutSeconds 30 -Activity "Cerrando PID $($p.PID)" -Hidden
            if (-not (Get-Process -Id $p.PID -ErrorAction SilentlyContinue)) {
                $cerrados++
            } else {
                $fallidos++
            }
        }
    }

    Write-Host ''
    Write-Separador -Caracter '-' -Color 'DarkYellow'
    Write-Linea -Texto ' PASO 4/4 - Sesiones desconectadas' -Color 'DarkYellow'
    Write-Separador -Caracter '-' -Color 'DarkYellow'

    $desconectadas = 0
    foreach ($ses in ($sesiones | Where-Object { $_.Estado -match 'Disc|Desconect' })) {
        logoff $ses.SessionId /server:localhost 2>$null
        $desconectadas++
        Write-Log -Mensaje "Sesion $($ses.SessionId) ($($ses.Usuario)) cerrada." -Nivel OK
    }

    Write-Host ''
    Write-Separador -Color $Script:ColorExito
    Write-Linea -Texto ' EXPULSION COMPLETADA' -Color $Script:ColorExito -Centrado
    Write-Log -Mensaje "Procesos: $cerrados cerrados, $fallidos fallidos | Sesiones: $desconectadas" -Nivel OK
}

function Set-ContrasenaSQLSa {
    param(
        [Parameter(Mandatory)][string]$Instancia,
        [Parameter(Mandatory)][string]$NuevaContrasena
    )

    $conexion = New-Object System.Data.SqlClient.SqlConnection
    $comando = $null
    $conexion.ConnectionString = "Server=$Instancia;Integrated Security=True;TrustServerCertificate=True;Connect Timeout=8;Application Name=CONTPAQi Toolbox"
    try {
        $conexion.Open()
        $comando = $conexion.CreateCommand()
        $comando.CommandTimeout = 15
        $sqlPassword = $NuevaContrasena.Replace("'", "''")
        $comando.CommandText = "ALTER LOGIN [sa] WITH PASSWORD = N'$sqlPassword'; ALTER LOGIN [sa] ENABLE;"
        $null = $comando.ExecuteNonQuery()
    } finally {
        if ($comando) { $comando.Dispose() }
        $conexion.Dispose()
    }
}

function Restablecer-ContrasenaSQL {
    Write-Encabezado -Titulo 'RESTABLECER CONTRASENA SQL' -Subtitulo 'Login sa en instancias locales' -Color 'Green'

    # Usar exclusivamente servicios reales del motor. Leer el registro con
    # Get-Member tambien devuelve PSPath, PSParentPath y otras propiedades
    # internas que no son instancias SQL.
    $motoresSQL = @(Get-ServiciosMotorSQL)
    if ($motoresSQL.Count -eq 0) {
        Write-Log -Mensaje 'No se detectaron instancias SQL.' -Nivel ERROR
        return
    }
    $nombresInstancias = @($motoresSQL | ForEach-Object {
        if ($_.Name -eq 'MSSQLSERVER') {
            'MSSQLSERVER'
        } elseif ($_.Name -match '^MSSQL\$(.+)$') {
            $matches[1]
        }
    } | Where-Object { $_ } | Sort-Object -Unique)
    Write-Log -Mensaje "Instancias SQL reales detectadas: $($nombresInstancias -join ', ')" -Nivel INFO

    if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        $Script:LogBox.Visible = $false

        $sqlPanel = New-Object System.Windows.Forms.Panel
        $sqlPanel.Dock = 'Fill'
        $sqlPanel.BackColor = $Script:GUIColors.LogBG
        $sqlPanel.Padding = New-Object System.Windows.Forms.Padding(30, 20, 30, 20)
        $Script:LogPanel.Controls.Add($sqlPanel)
        $sqlPanel.BringToFront()
        $Script:CurrentPanel = $sqlPanel

        $titleLbl = New-Object System.Windows.Forms.Label
        $titleLbl.Text = 'RESTABLECER CONTRASENA SA'
        $titleLbl.Dock = 'Top'
        $titleLbl.Height = 40
        $titleLbl.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
        $titleLbl.ForeColor = $Script:GUIColors.Success
        $titleLbl.TextAlign = 'MiddleLeft'
        $titleLbl.BackColor = [System.Drawing.Color]::Transparent
        $sqlPanel.Controls.Add($titleLbl)

        $instPanel = New-Object System.Windows.Forms.GroupBox
        $instPanel.Text = ' Instancias SQL detectadas (selecciona las que deseas cambiar)'
        $instPanel.Dock = 'Top'
        $instPanel.Height = 50 + ($nombresInstancias.Count * 34)
        $instPanel.ForeColor = $Script:GUIColors.Text
        $instPanel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $instPanel.BackColor = [System.Drawing.Color]::Transparent
        $sqlPanel.Controls.Add($instPanel)

        $chkInstances = @()
        $yChk = 25
        foreach ($inst in $nombresInstancias) {
            $serverName = if ($inst -eq 'MSSQLSERVER') { '(Default)' } else { $inst }
            $svcName = if ($inst -eq 'MSSQLSERVER') { 'MSSQLSERVER' } else { "MSSQL`$$inst" }
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            $estado = if ($svc) {
                if ($svc.Status -eq 'Running') { ' [Activo]' } else { ' [Detenido]' }
            } else { ' [Detectado]' }

            $chk = New-Object System.Windows.Forms.CheckBox
            $chk.Text = " $serverName$estado"
            $chk.Location = New-Object System.Drawing.Point(15, $yChk)
            $chk.Size = New-Object System.Drawing.Size(500, 24)
            $chk.ForeColor = $Script:GUIColors.Text
            $chk.Font = New-Object System.Drawing.Font('Segoe UI', 10)
            $chk.Checked = $true
            $chk.BackColor = [System.Drawing.Color]::Transparent
            $instPanel.Controls.Add($chk)
            $chkInstances += @{ CheckBox = $chk; Nombre = $inst }
            $yChk += 34
        }

        $passGroup = New-Object System.Windows.Forms.GroupBox
        $passGroup.Text = ' Nueva contrasena para el login sa'
        $passGroup.Dock = 'Top'
        $passGroup.Height = 125
        $passGroup.ForeColor = $Script:GUIColors.Text
        $passGroup.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $passGroup.BackColor = [System.Drawing.Color]::Transparent
        $passGroup.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
        $sqlPanel.Controls.Add($passGroup)

        $passHint = New-Object System.Windows.Forms.Label
        $passHint.Text = 'Mínimo 8 caracteres. La contraseña no se almacena ni se muestra en procesos.'
        $passHint.Location = New-Object System.Drawing.Point(15, 22)
        $passHint.Size = New-Object System.Drawing.Size(500, 18)
        $passHint.ForeColor = $Script:GUIColors.TextDim
        $passHint.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $passHint.BackColor = [System.Drawing.Color]::Transparent
        $passGroup.Controls.Add($passHint)

        $passBox = New-Object System.Windows.Forms.TextBox
        $passLabelNueva = New-Object System.Windows.Forms.Label
        $passLabelNueva.Text = 'Nueva:'
        $passLabelNueva.Location = New-Object System.Drawing.Point(15, 49)
        $passLabelNueva.Size = New-Object System.Drawing.Size(75, 22)
        $passLabelNueva.ForeColor = $Script:GUIColors.Text
        $passGroup.Controls.Add($passLabelNueva)

        $passBox.Location = New-Object System.Drawing.Point(95, 45)
        $passBox.Size = New-Object System.Drawing.Size(420, 27)
        $passBox.Font = New-Object System.Drawing.Font('Segoe UI', 11)
        $passBox.BackColor = $Script:GUIColors.Sidebar
        $passBox.ForeColor = $Script:GUIColors.Text
        Set-ModernTextBoxStyle -TextBox $passBox
        $passBox.UseSystemPasswordChar = $true
        $passGroup.Controls.Add($passBox)

        $passLabelConfirmar = New-Object System.Windows.Forms.Label
        $passLabelConfirmar.Text = 'Confirmar:'
        $passLabelConfirmar.Location = New-Object System.Drawing.Point(15, 84)
        $passLabelConfirmar.Size = New-Object System.Drawing.Size(75, 22)
        $passLabelConfirmar.ForeColor = $Script:GUIColors.Text
        $passGroup.Controls.Add($passLabelConfirmar)

        $passConfirmBox = New-Object System.Windows.Forms.TextBox
        $passConfirmBox.Location = New-Object System.Drawing.Point(95, 80)
        $passConfirmBox.Size = New-Object System.Drawing.Size(420, 27)
        $passConfirmBox.Font = New-Object System.Drawing.Font('Segoe UI', 11)
        $passConfirmBox.BackColor = $Script:GUIColors.Sidebar
        $passConfirmBox.ForeColor = $Script:GUIColors.Text
        Set-ModernTextBoxStyle -TextBox $passConfirmBox
        $passConfirmBox.UseSystemPasswordChar = $true
        $passGroup.Controls.Add($passConfirmBox)

        $btnPanel = New-Object System.Windows.Forms.FlowLayoutPanel
        $btnPanel.Dock = 'Top'
        $btnPanel.Height = 55
        $btnPanel.FlowDirection = 'LeftToRight'
        $btnPanel.WrapContents = $false
        $btnPanel.BackColor = [System.Drawing.Color]::Transparent
        $btnPanel.Margin = New-Object System.Windows.Forms.Padding(0, 15, 0, 0)
        $sqlPanel.Controls.Add($btnPanel)

        $okBtn = New-Object System.Windows.Forms.Button
        $okBtn.Text = 'Restablecer'
        $okBtn.Size = New-Object System.Drawing.Size(140, 40)
        $okBtn.BackColor = $Script:GUIColors.Success
        $okBtn.ForeColor = $Script:GUIColors.BG
        $okBtn.FlatStyle = 'Flat'
        $okBtn.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
        $okBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
        Set-ModernButtonStyle -Button $okBtn -BaseColor $Script:GUIColors.Success -TextColor $Script:GUIColors.BG -HoverColor ([System.Windows.Forms.ControlPaint]::Light($Script:GUIColors.Success, 0.12))
        $okBtn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 15, 0)
        $btnPanel.Controls.Add($okBtn)

        $cancelBtn = New-Object System.Windows.Forms.Button
        $cancelBtn.Text = 'Cancelar'
        $cancelBtn.Size = New-Object System.Drawing.Size(120, 40)
        $cancelBtn.BackColor = $Script:GUIColors.Button
        $cancelBtn.ForeColor = $Script:GUIColors.Text
        $cancelBtn.FlatStyle = 'Flat'
        $cancelBtn.Font = New-Object System.Drawing.Font('Segoe UI', 10)
        $cancelBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
        Set-ModernButtonStyle -Button $cancelBtn
        $btnPanel.Controls.Add($cancelBtn)

        $cleanup = {
            if ($sqlPanel -and -not $sqlPanel.IsDisposed) { $sqlPanel.Dispose() }
            if ($Script:CurrentPanel -eq $sqlPanel) { $Script:CurrentPanel = $null }
            if ($Script:LogBox) {
                $Script:LogBox.Visible = $true
                $Script:LogBox.BringToFront()
            }
        }

        $cancelBtn.Add_Click({
            & $cleanup
            Write-Log -Mensaje 'Operacion cancelada.' -Nivel WARN
        })

        $okBtn.Add_Click({
            $passInput = $passBox.Text
            if ([string]::IsNullOrWhiteSpace($passInput) -or $passInput.Length -lt 8) {
                [System.Windows.Forms.MessageBox]::Show('La contraseña debe tener al menos 8 caracteres.', 'Contraseña no válida', 'OK', 'Warning') | Out-Null
                return
            }
            if ($passInput -cne $passConfirmBox.Text) {
                [System.Windows.Forms.MessageBox]::Show('Las contraseñas no coinciden.', 'Confirmación no válida', 'OK', 'Warning') | Out-Null
                return
            }

            $seleccionadas = @()
            foreach ($item in $chkInstances) {
                if ($item.CheckBox.Checked) { $seleccionadas += $item.Nombre }
            }
            if ($seleccionadas.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show('Selecciona al menos una instancia.', 'Sin instancias', 'OK', 'Warning') | Out-Null
                return
            }
            if (-not (Confirmar-Movimiento -Frase 'CAMBIAR CONTRASENA' `
                -Accion "Cambiar la contrasena sa en $($seleccionadas.Count) instancia(s)" `
                -Detalle 'Las aplicaciones que utilicen la contrasena anterior deberan actualizar su configuracion.')) { return }

            & $cleanup

            foreach ($inst in $seleccionadas) {
                $serverName = if ($inst -eq 'MSSQLSERVER') { '.' } else { ".\$inst" }
                Write-Log -Mensaje "Conectando a $serverName ..." -Nivel PROGRESS
                try {
                    Set-ContrasenaSQLSa -Instancia $serverName -NuevaContrasena $passInput
                    Write-Log -Mensaje "Contrasena 'sa' restablecida en $serverName" -Nivel OK
                } catch {
                    Write-Log -Mensaje "Error en $($serverName): $($_.Exception.Message)" -Nivel ERROR
                }
            }
            $passInput = $null
        })

        $passBox.Focus() | Out-Null
    } else {
        $secureInput = Read-Host ' Nueva contrasena (minimo 8 caracteres)' -AsSecureString
        $credential = New-Object System.Management.Automation.PSCredential('sa', $secureInput)
        $passInput = $credential.GetNetworkCredential().Password
        if ([string]::IsNullOrWhiteSpace($passInput) -or $passInput.Length -lt 8) {
            Write-Log -Mensaje 'La contraseña debe tener al menos 8 caracteres.' -Nivel ERROR
            return
        }
        $confirmacionSegura = Read-Host ' Confirma la nueva contrasena' -AsSecureString
        $credConfirmacion = New-Object System.Management.Automation.PSCredential('sa', $confirmacionSegura)
        if ($passInput -cne $credConfirmacion.GetNetworkCredential().Password) {
            Write-Log -Mensaje 'Las contrasenas no coinciden.' -Nivel ERROR
            return
        }
        if (-not (Confirmar-Movimiento -Frase 'CAMBIAR CONTRASENA' `
            -Accion "Cambiar la contrasena sa en $($nombresInstancias.Count) instancia(s)" `
            -Detalle 'Las aplicaciones que utilicen la contrasena anterior deberan actualizar su configuracion.')) { return }

        foreach ($inst in $nombresInstancias) {
            $serverName = if ($inst -eq 'MSSQLSERVER') { '.' } else { ".\$inst" }
            Write-Log -Mensaje "Conectando a $serverName ..." -Nivel PROGRESS
            try {
                Set-ContrasenaSQLSa -Instancia $serverName -NuevaContrasena $passInput
                Write-Log -Mensaje "Contrasena 'sa' restablecida en $serverName" -Nivel OK
            } catch {
                Write-Log -Mensaje "Error en $($serverName): $($_.Exception.Message)" -Nivel ERROR
            }
        }
        $passInput = $null
    }
}

function Write-ResultadoIntegridadSQL {
    param($Resultado, [string]$BaseDatos)
    if ($Resultado.Saludable) {
        Write-Log -Mensaje "${BaseDatos}: integridad correcta en $($Resultado.DuracionSegundos) segundos." -Nivel OK
        return
    }
    Write-Log -Mensaje "${BaseDatos}: la revision de integridad requiere atencion." -Nivel ERROR
    Write-Log -Mensaje "Errores de asignacion: $($Resultado.ErroresAsignacion) | Consistencia: $($Resultado.ErroresConsistencia)" -Nivel ERROR
    foreach ($mensaje in @($Resultado.Mensajes | Select-Object -First 8)) {
        $limpio = ($mensaje -replace '[\r\n]+', ' ' -replace '\s+', ' ').Trim()
        if ($limpio) { Write-Log -Mensaje $limpio -Nivel WARN }
    }
    Write-Log -Mensaje 'No se aplico ninguna reparacion destructiva. Conserva el respaldo y escala el caso antes de modificar datos.' -Nivel WARN
}

function New-SqlHealthMetricCard {
    param(
        [Parameter(Mandatory)][string]$Titulo,
        [Parameter(Mandatory)][string]$Valor,
        [Parameter(Mandatory)][string]$Detalle,
        [System.Drawing.Color]$Color = $Script:GUIColors.Accent
    )
    $card = New-Object System.Windows.Forms.Panel
    $card.Dock = 'Fill'
    $card.Margin = New-Object System.Windows.Forms.Padding(5)
    $card.Padding = New-Object System.Windows.Forms.Padding(12, 7, 10, 6)
    $card.BackColor = $Script:GUIColors.Surface

    $accentLine = New-Object System.Windows.Forms.Panel
    $accentLine.Dock = 'Left'
    $accentLine.Width = 3
    $accentLine.BackColor = $Color
    $card.Controls.Add($accentLine)

    $content = New-Object System.Windows.Forms.TableLayoutPanel
    $content.Dock = 'Fill'
    $content.Margin = New-Object System.Windows.Forms.Padding(0)
    $content.Padding = New-Object System.Windows.Forms.Padding(7, 0, 0, 0)
    $content.ColumnCount = 1
    $content.RowCount = 3
    $content.BackColor = $Script:GUIColors.Surface
    $content.RowStyles.Clear()
    $null = $content.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 17)))
    $null = $content.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
    $null = $content.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 17)))

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Dock = 'Fill'
    $titleLabel.Text = $Titulo.ToUpperInvariant()
    $titleLabel.ForeColor = $Script:GUIColors.TextDim
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.2, [System.Drawing.FontStyle]::Bold)
    $titleLabel.TextAlign = 'MiddleLeft'
    $content.Controls.Add($titleLabel, 0, 0)

    $detailLabel = New-Object System.Windows.Forms.Label
    $detailLabel.Dock = 'Fill'
    $detailLabel.Text = $Detalle
    $detailLabel.ForeColor = $Script:GUIColors.TextDim
    $detailLabel.Font = New-Object System.Drawing.Font('Segoe UI', 7.2)
    $detailLabel.AutoEllipsis = $true
    $detailLabel.TextAlign = 'MiddleLeft'
    $content.Controls.Add($detailLabel, 0, 2)

    $valueLabel = New-Object System.Windows.Forms.Label
    $valueLabel.Dock = 'Fill'
    $valueLabel.Text = $Valor
    $valueLabel.ForeColor = $Color
    $valueLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Bold)
    $valueLabel.TextAlign = 'MiddleLeft'
    $valueLabel.AutoEllipsis = $true
    $content.Controls.Add($valueLabel, 0, 1)
    $card.Controls.Add($content)
    $content.BringToFront()
    return $card
}

function Show-SqlCompanyDiagnostic {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.RichTextBox]$Target,
        [Parameter(Mandatory)]$Empresa,
        [Parameter(Mandatory)][hashtable]$Palette,
        [bool]$RespaldosDisponibles
    )

    $Target.Clear()
    $normalFont = $Target.Font
    $boldFont = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
    $append = {
        param([string]$Text, [System.Drawing.Color]$Color, [switch]$Bold)
        $Target.SelectionStart = $Target.TextLength
        $Target.SelectionLength = 0
        $Target.SelectionColor = $Color
        if ($Bold) { $Target.SelectionFont = $boldFont }
        else { $Target.SelectionFont = $normalFont }
        $Target.AppendText($Text)
    }.GetNewClosure()

    & $append "  $($Empresa.Nombre)`r`n" $Palette.Accent -Bold
    $tipo = if ($Empresa.EsAuxiliar) { 'BASE AUXILIAR DE CONTPAQI' } else { 'EMPRESA / BASE PRINCIPAL' }
    & $append "  $tipo  |  Estado: $($Empresa.Estado)  |  Salud: $($Empresa.Salud)`r`n`r`n" $Palette.TextDim
    & $append "  METRICAS`r`n" $Palette.Text -Bold
    & $append ("  Datos: {0:N2} GB usados de {1:N2} GB ({2:N1}%)`r`n" -f ([double]$Empresa.DatosUsadosMB / 1024), ([double]$Empresa.DatosAsignadosMB / 1024), [double]$Empresa.UsoDatosPct) $Palette.TextDim
    & $append ("  Log: {0:N2} GB | Uso interno: {1:N1}%`r`n" -f ([double]$Empresa.LogMB / 1024), [double]$Empresa.LogUsadoPct) $Palette.TextDim
    $backupText = if (-not $RespaldosDisponibles) { 'No disponible por permisos' } elseif ($Empresa.UltimoRespaldo) { ([datetime]$Empresa.UltimoRespaldo).ToString('dd/MM/yyyy HH:mm') } else { 'Sin registro' }
    & $append "  Respaldo completo: $backupText`r`n" $Palette.TextDim
    & $append "  Recuperacion: $($Empresa.Recuperacion) | PAGE_VERIFY: $($Empresa.VerificacionPagina)`r`n`r`n" $Palette.TextDim

    $hallazgos = @()
    if ($Empresa.EsAuxiliar) {
        $claseAuxiliar = if ([string]$Empresa.Nombre -match '(?i)_content$') { 'contenido de documentos digitales' } elseif ([string]$Empresa.Nombre -match '(?i)_metadata$') { 'indices y propiedades de documentos digitales' } else { 'configuracion o catalogos compartidos de CONTPAQi' }
        $hallazgos += [PSCustomObject]@{
            Nivel = 'INFO'; Titulo = 'Base auxiliar necesaria'
            Situacion = "Esta base almacena $claseAuxiliar; no representa una empresa adicional."
            Consecuencia = 'Eliminarla, renombrarla o separarla puede dejar documentos sin consulta, referencias rotas o funciones incompletas.'
            Accion = 'Conservarla, incluirla en los respaldos y atenderla solo junto con la empresa o modulo que la utiliza.'
        }
    }
    if ([string]$Empresa.Estado -ne 'ONLINE') {
        $hallazgos += [PSCustomObject]@{
            Nivel = 'CRITICA'; Titulo = "Estado $($Empresa.Estado)"
            Situacion = 'SQL no tiene la base disponible para operacion normal.'
            Consecuencia = 'Los usuarios pueden no abrir la empresa y las aplicaciones pueden generar errores de conexion o recuperacion.'
            Accion = 'Revisar SQL ERRORLOG, espacio en disco y motivo del estado. Proteger respaldos antes de intentar cambios; no usar reparaciones con perdida de datos.'
        }
    }
    if ([double]$Empresa.DatosAsignadosMB -le 0 -and [string]$Empresa.Estado -eq 'ONLINE') {
        $hallazgos += [PSCustomObject]@{
            Nivel = 'INFO'; Titulo = 'Metricas incompletas'
            Situacion = 'No fue posible leer el espacio interno de los archivos de datos.'
            Consecuencia = 'El diagnostico de capacidad puede ser parcial, aunque la empresa siga funcionando.'
            Accion = 'Validar acceso del usuario de Windows a la base y volver a ejecutar Salud SQL.'
        }
    } elseif ([double]$Empresa.UsoDatosPct -ge 90) {
        $hallazgos += [PSCustomObject]@{
            Nivel = 'CRITICA'; Titulo = 'Archivo de datos casi lleno'
            Situacion = "La empresa utiliza $($Empresa.UsoDatosPct)% del espacio actualmente asignado."
            Consecuencia = 'SQL puede necesitar crecer el archivo; si el disco no tiene espacio, las operaciones y guardados pueden fallar.'
            Accion = 'Validar espacio real del volumen y autogrowth en MB, confirmar respaldo reciente y planear capacidad. No reducir el archivo de forma rutinaria.'
        }
    } elseif ([double]$Empresa.UsoDatosPct -ge 80) {
        $hallazgos += [PSCustomObject]@{
            Nivel = 'ATENCION'; Titulo = 'Capacidad de datos en vigilancia'
            Situacion = "La empresa utiliza $($Empresa.UsoDatosPct)% del espacio asignado."
            Consecuencia = 'Puede ocurrir crecimiento automático durante horas de trabajo, provocando pausas y mayor consumo de disco.'
            Accion = 'Revisar tendencia, espacio del volumen y crecimiento configurado; programar capacidad antes de llegar a 90%.'
        }
    }
    if ([double]$Empresa.LogUsadoPct -ge 90) {
        $hallazgos += [PSCustomObject]@{
            Nivel = 'CRITICA'; Titulo = 'Log de transacciones casi lleno'
            Situacion = "El log esta utilizado al $($Empresa.LogUsadoPct)%."
            Consecuencia = 'El log puede crecer hasta llenar el disco o impedir nuevas transacciones si no puede reutilizar espacio.'
            Accion = 'Revisar log_reuse_wait_desc, transacciones abiertas y estrategia de respaldos de log según el modelo de recuperacion. No aplicar SHRINK como solucion permanente.'
        }
    } elseif ([double]$Empresa.LogUsadoPct -ge 80) {
        $hallazgos += [PSCustomObject]@{
            Nivel = 'ATENCION'; Titulo = 'Uso elevado del log'
            Situacion = "El log esta utilizado al $($Empresa.LogUsadoPct)%."
            Consecuencia = 'Puede crecer pronto y aumentar el consumo de disco o causar pausas.'
            Accion = 'Revisar transacciones activas, modelo de recuperacion, respaldos de log y crecimiento en MB.'
        }
    }
    if ([string]$Empresa.VerificacionPagina -ne 'CHECKSUM') {
        $hallazgos += [PSCustomObject]@{
            Nivel = 'ATENCION'; Titulo = 'PAGE_VERIFY sin CHECKSUM'
            Situacion = "La base utiliza $($Empresa.VerificacionPagina) para verificacion de paginas."
            Consecuencia = 'SQL tiene menor capacidad de detectar daño físico silencioso en paginas de datos.'
            Accion = 'Solicitar al responsable SQL evaluar PAGE_VERIFY CHECKSUM y mantener DBCC CHECKDB y respaldos verificados.'
        }
    }
    if ($RespaldosDisponibles) {
        if (-not $Empresa.UltimoRespaldo) {
            $hallazgos += [PSCustomObject]@{
                Nivel = 'ATENCION'; Titulo = 'Sin respaldo completo registrado'
                Situacion = 'MSDB no contiene un respaldo completo para esta base.'
                Consecuencia = 'Una falla del servidor puede producir perdida total o una recuperacion incompleta.'
                Accion = 'Crear un respaldo completo con CHECKSUM, verificarlo con RESTORE VERIFYONLY y conservar una copia fuera del servidor.'
            }
        } else {
            $dias = [math]::Floor(((Get-Date) - [datetime]$Empresa.UltimoRespaldo).TotalDays)
            if ($dias -gt 7) {
                $hallazgos += [PSCustomObject]@{
                    Nivel = 'ATENCION'; Titulo = 'Respaldo completo antiguo'
                    Situacion = "El ultimo respaldo completo tiene $dias dias."
                    Consecuencia = 'Ante una falla, la ventana de recuperacion puede ser mayor y depender de respaldos diferenciales o de log.'
                    Accion = 'Confirmar la politica de respaldos, ejecutar uno verificable y probar restauracion periodicamente.'
                }
            }
        }
    }

    if ($hallazgos.Count -eq 0) {
        & $append "  SIN RIESGOS IMPORTANTES DETECTADOS`r`n" $Palette.Success -Bold
        & $append "  La empresa esta dentro de los umbrales revisados. Mantener respaldos verificados, vigilancia de disco y mantenimiento preventivo.`r`n" $Palette.TextDim
    } else {
        foreach ($hallazgo in $hallazgos) {
            $colorNivel = if ($hallazgo.Nivel -eq 'CRITICA') { $Palette.Error } elseif ($hallazgo.Nivel -eq 'ATENCION') { $Palette.Warning } else { $Palette.Accent }
            & $append "  [$($hallazgo.Nivel)] $($hallazgo.Titulo)`r`n" $colorNivel -Bold
            & $append "  Que pasa: $($hallazgo.Situacion)`r`n" $Palette.TextDim
            & $append "  Consecuencia: $($hallazgo.Consecuencia)`r`n" $Palette.TextDim
            & $append "  Accion segura: $($hallazgo.Accion)`r`n`r`n" $Palette.Text
        }
    }
    $Target.SelectionStart = 0
    $Target.ScrollToCaret()
    $boldFont.Dispose()
}

function Show-SqlSpaceChartWindow {
    param(
        [Parameter(Mandatory)][string]$Instancia,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Empresas
    )
    $basesGrafica = @($Empresas | Where-Object { -not $_.EsAuxiliar -and $_.DatosAsignadosMB -gt 0 })
    $auxiliares = @($Empresas | Where-Object { $_.EsAuxiliar })
    if ($basesGrafica.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('No se encontraron bases principales con informacion de espacio.', 'Grafica de espacio SQL', 'OK', 'Information') | Out-Null
        return
    }

    $dialog = New-Object System.Windows.Forms.Form
    Set-ModernFormStyle -Form $dialog
    $dialog.Text = "Espacio SQL por empresa - $Instancia"
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $dialog.Width = [math]::Min(1280, [math]::Max(900, $workingArea.Width - 120))
    $dialog.Height = [math]::Min(820, [math]::Max(620, $workingArea.Height - 120))
    $dialog.MinimumSize = New-Object System.Drawing.Size(850, 580)
    $dialog.StartPosition = 'CenterParent'
    $dialog.BackColor = $Script:GUIColors.BG

    $rootLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $rootLayout.Dock = 'Fill'
    $rootLayout.ColumnCount = 1
    $rootLayout.RowCount = 3
    $rootLayout.ColumnStyles.Clear()
    $rootLayout.RowStyles.Clear()
    $null = $rootLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
    $null = $rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 78)))
    $null = $rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
    $null = $rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 31)))
    $rootLayout.BackColor = $Script:GUIColors.BG
    $dialog.Controls.Add($rootLayout)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Top'
    $header.Height = 78
    $header.Padding = New-Object System.Windows.Forms.Padding(18, 10, 14, 10)
    $header.BackColor = $Script:GUIColors.Surface
    $rootLayout.Controls.Add($header, 0, 0)

    $close = New-Object System.Windows.Forms.Button
    $close.Dock = 'Right'
    $close.Width = 105
    $close.Text = 'CERRAR'
    $close.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
    Set-ModernButtonStyle -Button $close -BaseColor $Script:GUIColors.Button -TextColor $Script:GUIColors.Text -HoverColor $Script:GUIColors.ButtonHover
    $header.Controls.Add($close)

    $headerText = New-Object System.Windows.Forms.TableLayoutPanel
    $headerText.Dock = 'Fill'
    $headerText.ColumnCount = 1
    $headerText.RowCount = 2
    $headerText.RowStyles.Clear()
    $null = $headerText.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 58)))
    $null = $headerText.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 42)))
    $headerText.BackColor = $Script:GUIColors.Surface

    $title = New-Object System.Windows.Forms.Label
    $title.Dock = 'Fill'
    $title.Text = 'ESPACIO SQL POR EMPRESA'
    $title.ForeColor = $Script:GUIColors.Accent
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17, [System.Drawing.FontStyle]::Bold)
    $title.TextAlign = 'MiddleLeft'
    $headerText.Controls.Add($title, 0, 0)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Dock = 'Fill'
    $subtitle.Text = "$Instancia  |  $($basesGrafica.Count) empresa(s)  |  $($auxiliares.Count) base(s) auxiliares consolidadas"
    $subtitle.ForeColor = $Script:GUIColors.TextDim
    $subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $subtitle.TextAlign = 'MiddleLeft'
    $headerText.Controls.Add($subtitle, 0, 1)
    $header.Controls.Add($headerText)
    $headerText.BringToFront()

    $footer = New-Object System.Windows.Forms.Label
    $footer.Dock = 'Bottom'
    $footer.Height = 31
    $footer.Padding = New-Object System.Windows.Forms.Padding(14, 0, 0, 0)
    $footer.TextAlign = 'MiddleLeft'
    $footer.BackColor = $Script:GUIColors.Header
    $footer.ForeColor = $Script:GUIColors.TextDim
    $footer.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $totalUsado = [math]::Round((($basesGrafica | Measure-Object DatosUsadosMB -Sum).Sum / 1024), 1)
    $totalAsignado = [math]::Round((($basesGrafica | Measure-Object DatosAsignadosMB -Sum).Sum / 1024), 1)
    $footer.Text = "UTILIZADO: $totalUsado GB  |  ASIGNADO: $totalAsignado GB  |  Usa la barra lateral de la grafica para recorrer las empresas"
    $rootLayout.Controls.Add($footer, 0, 2)

    $scroll = New-Object System.Windows.Forms.Panel
    $scroll.Dock = 'Fill'
    $scroll.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 8)
    $scroll.BackColor = $Script:GUIColors.LogBG
    $scroll.AutoScroll = $false
    $rootLayout.Controls.Add($scroll, 0, 1)

    $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
    $chart.Dock = 'Fill'
    $chart.BackColor = $Script:GUIColors.Surface
    $chart.AntiAliasing = 'All'

    $area = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea('DetalleEspacio')
    $area.BackColor = $Script:GUIColors.Surface
    $area.AxisX.LabelStyle.ForeColor = $Script:GUIColors.Text
    $area.AxisX.LabelStyle.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $area.AxisX.LineColor = $Script:GUIColors.Separator
    $area.AxisX.MajorGrid.Enabled = $false
    $area.AxisX.Interval = 1
    $area.AxisX.IsLabelAutoFit = $true
    $area.AxisX.LabelAutoFitMinFontSize = 7
    $area.AxisX.LabelAutoFitMaxFontSize = 9
    $area.AxisX.ScrollBar.Enabled = ($basesGrafica.Count -gt 12)
    $area.AxisX.ScrollBar.IsPositionedInside = $false
    $area.AxisX.ScrollBar.Size = 15
    $area.AxisX.ScrollBar.ButtonStyle = 'SmallScroll'
    $area.AxisX.ScrollBar.BackColor = $Script:GUIColors.Header
    $area.AxisX.ScrollBar.ButtonColor = $Script:GUIColors.AccentDark
    $area.AxisX.ScrollBar.LineColor = $Script:GUIColors.Separator
    if ($basesGrafica.Count -gt 12) {
        $area.AxisX.ScaleView.Size = 12
        $area.AxisX.ScaleView.MinSize = 6
        $area.AxisX.ScaleView.SmallScrollSize = 1
    }
    $area.AxisY.LabelStyle.ForeColor = $Script:GUIColors.TextDim
    $area.AxisY.LabelStyle.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $area.AxisY.LabelStyle.Format = 'N1'
    $area.AxisY.LineColor = $Script:GUIColors.Separator
    $area.AxisY.MajorGrid.LineColor = $Script:GUIColors.Separator
    $area.AxisY.Title = 'Espacio en GB'
    $area.AxisY.TitleForeColor = $Script:GUIColors.TextDim
    $area.AxisY.TitleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 8)
    $area.Position.Auto = $false
    $area.Position.X = 3
    $area.Position.Y = 3
    $area.Position.Width = 94
    $area.Position.Height = 91
    $area.InnerPlotPosition.Auto = $false
    $area.InnerPlotPosition.X = 31
    $area.InnerPlotPosition.Y = 4
    $area.InnerPlotPosition.Width = 66
    $area.InnerPlotPosition.Height = 86
    $chart.ChartAreas.Add($area)

    $usedSeries = New-Object System.Windows.Forms.DataVisualization.Charting.Series('Utilizado')
    $usedSeries.ChartType = 'StackedBar'
    $usedSeries.Color = $Script:GUIColors.Accent
    $usedSeries.BorderWidth = 0
    $freeSeries = New-Object System.Windows.Forms.DataVisualization.Charting.Series('Disponible dentro del archivo')
    $freeSeries.ChartType = 'StackedBar'
    $freeSeries.Color = [System.Drawing.Color]::FromArgb(48, 55, 68)
    $freeSeries.BorderWidth = 0

    # El grafico de barras invierte visualmente el orden; ordenar ascendente
    # deja las empresas mas grandes en la parte superior.
    foreach ($empresa in @($basesGrafica | Sort-Object DatosAsignadosMB)) {
        $usadoGB = [math]::Round(([double]$empresa.DatosUsadosMB / 1024), 2)
        $libreGB = [math]::Round(([double]$empresa.DatosLibresMB / 1024), 2)
        $idxUsed = $usedSeries.Points.AddXY([string]$empresa.Nombre, $usadoGB)
        $usedPoint = $usedSeries.Points[$idxUsed]
        $usedPoint.ToolTip = "$($empresa.Nombre)`nUtilizado: $usadoGB GB`nUso interno: $($empresa.UsoDatosPct)%"
        if ($basesGrafica.Count -le 35 -and $usadoGB -gt 0) {
            $usedPoint.Label = "$($empresa.UsoDatosPct)%"
            $usedPoint.LabelForeColor = [System.Drawing.Color]::White
            $usedPoint.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7)
        }
        $idxFree = $freeSeries.Points.AddXY([string]$empresa.Nombre, $libreGB)
        $freeSeries.Points[$idxFree].ToolTip = "$($empresa.Nombre)`nDisponible dentro del archivo: $libreGB GB"
    }
    $chart.Series.Add($usedSeries)
    $chart.Series.Add($freeSeries)

    $legend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend('DetalleLeyenda')
    $legend.Docking = 'Bottom'
    $legend.Alignment = 'Center'
    $legend.BackColor = $Script:GUIColors.Surface
    $legend.ForeColor = $Script:GUIColors.TextDim
    $legend.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $chart.Legends.Add($legend)
    $scroll.Controls.Add($chart)

    $close.Add_Click(({ $dialog.Close() }).GetNewClosure())
    $dialog.Add_Shown(({ $chart.Focus() }).GetNewClosure())
    $null = if ($Script:GUIForm) { $dialog.ShowDialog($Script:GUIForm) } else { $dialog.ShowDialog() }
    $dialog.Dispose()
}

function Show-SaludSQLDashboard {
    param(
        [Parameter(Mandatory)][string]$Instancia,
        [Parameter(Mandatory)]$Servidor,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Empresas,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alertas,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Volumenes,
        [Parameter(Mandatory)]$Actividad,
        [ValidateRange(0, 100)][int]$Puntaje,
        [bool]$RespaldosDisponibles
    )
    if (-not $Script:GUIForm -or $Script:ConsoleMode -or -not $Script:LogPanel) { return }

    Close-CurrentPanel
    $Script:LogBox.Visible = $false
    if ($Script:LogHeader) { $Script:LogHeader.Visible = $false }

    $basesPrincipales = @($Empresas | Where-Object { -not $_.EsAuxiliar })
    $basesAuxiliares = @($Empresas | Where-Object { $_.EsAuxiliar })
    $scoreColor = if ($Puntaje -ge 85) { $Script:GUIColors.Success } elseif ($Puntaje -ge 65) { $Script:GUIColors.Warning } else { $Script:GUIColors.Error }
    $datosUsadosGB = [math]::Round((($basesPrincipales | Measure-Object -Property DatosUsadosMB -Sum).Sum / 1024), 1)
    $datosAsignadosGB = [math]::Round((($basesPrincipales | Measure-Object -Property DatosAsignadosMB -Sum).Sum / 1024), 1)
    $datosAuxiliaresGB = [math]::Round((($basesAuxiliares | Measure-Object -Property DatosUsadosMB -Sum).Sum / 1024), 1)
    $empresasCriticas = @($basesPrincipales | Where-Object { $_.Salud -eq 'CRITICA' }).Count
    $empresasAtencion = @($basesPrincipales | Where-Object { $_.Salud -eq 'ATENCION' }).Count
    $empresasPorRevisar = $empresasCriticas + $empresasAtencion

    $dashboard = New-Object System.Windows.Forms.Panel
    $dashboard.Dock = 'Fill'
    $dashboard.BackColor = $Script:GUIColors.LogBG
    $dashboard.Padding = New-Object System.Windows.Forms.Padding(0)

    $header = New-Object System.Windows.Forms.TableLayoutPanel
    $header.Dock = 'Top'
    $header.Height = 72
    $header.Padding = New-Object System.Windows.Forms.Padding(15, 8, 10, 8)
    $header.BackColor = $Script:GUIColors.Surface
    $header.ColumnCount = 3
    $header.RowCount = 1
    $header.ColumnStyles.Clear()
    $header.RowStyles.Clear()
    $null = $header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
    $null = $header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 105)))
    $null = $header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 115)))
    $null = $header.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))

    $headerText = New-Object System.Windows.Forms.TableLayoutPanel
    $headerText.Dock = 'Fill'
    $headerText.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
    $headerText.ColumnCount = 1
    $headerText.RowCount = 2
    $headerText.BackColor = $Script:GUIColors.Surface
    $headerText.RowStyles.Clear()
    $null = $headerText.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 62)))
    $null = $headerText.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 38)))

    $title = New-Object System.Windows.Forms.Label
    $title.Dock = 'Fill'
    $title.Text = 'SALUD DE SQL SERVER'
    $title.ForeColor = $Script:GUIColors.Accent
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Bold)
    $title.TextAlign = 'MiddleLeft'
    $headerText.Controls.Add($title, 0, 0)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Dock = 'Fill'
    $subtitle.Text = "$Instancia  |  $($Servidor.Edicion)  |  Analisis de solo lectura"
    $subtitle.ForeColor = $Script:GUIColors.TextDim
    $subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $subtitle.TextAlign = 'MiddleLeft'
    $subtitle.AutoEllipsis = $true
    $headerText.Controls.Add($subtitle, 0, 1)
    $header.Controls.Add($headerText, 0, 0)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Dock = 'Fill'
    $closeButton.Margin = New-Object System.Windows.Forms.Padding(8, 8, 0, 8)
    $closeButton.Text = 'CERRAR VISTA'
    $closeButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
    Set-ModernButtonStyle -Button $closeButton -BaseColor $Script:GUIColors.Button -TextColor $Script:GUIColors.Text -HoverColor $Script:GUIColors.ButtonHover
    $header.Controls.Add($closeButton, 2, 0)

    $scoreBadge = New-Object System.Windows.Forms.Label
    $scoreBadge.Dock = 'Fill'
    $scoreBadge.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 8)
    $scoreBadge.Text = "$Puntaje / 100"
    $scoreBadge.TextAlign = 'MiddleCenter'
    $scoreBadge.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12, [System.Drawing.FontStyle]::Bold)
    $scoreBadge.ForeColor = $scoreColor
    $scoreBadge.BackColor = $Script:GUIColors.BG
    $header.Controls.Add($scoreBadge, 1, 0)

    $footer = New-Object System.Windows.Forms.Label
    $footer.Dock = 'Bottom'
    $footer.Height = 27
    $footer.Padding = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $footer.TextAlign = 'MiddleLeft'
    $footer.BackColor = $Script:GUIColors.Header
    $footer.ForeColor = $Script:GUIColors.TextDim
    $footer.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $footer.Text = "LECTURA SEGURA  |  Actualizado: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')  |  Las cifras corresponden al espacio asignado dentro de los archivos SQL"

    $body = New-Object System.Windows.Forms.TableLayoutPanel
    $body.Dock = 'Fill'
    $body.Padding = New-Object System.Windows.Forms.Padding(0, 7, 0, 7)
    $body.BackColor = $Script:GUIColors.LogBG
    $body.ColumnCount = 1
    $body.RowCount = 2
    $body.RowStyles.Clear()
    $null = $body.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 96)))
    $null = $body.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))

    $cards = New-Object System.Windows.Forms.TableLayoutPanel
    $cards.Dock = 'Top'
    $cards.Height = 96
    $cards.ColumnCount = 4
    $cards.RowCount = 1
    $cards.Padding = New-Object System.Windows.Forms.Padding(0)
    $cards.BackColor = $Script:GUIColors.LogBG
    $cards.ColumnStyles.Clear()
    $cards.RowStyles.Clear()
    for ($i = 0; $i -lt 4; $i++) { $null = $cards.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 25))) }
    $null = $cards.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
    $cards.Controls.Add((New-SqlHealthMetricCard -Titulo 'Puntaje general' -Valor "$Puntaje / 100" -Detalle $(if ($Puntaje -ge 85) { 'Estado saludable' } elseif ($Puntaje -ge 65) { 'Requiere atencion' } else { 'Intervencion prioritaria' }) -Color $scoreColor), 0, 0)
    $cards.Controls.Add((New-SqlHealthMetricCard -Titulo 'Empresas detectadas' -Valor ([string]$basesPrincipales.Count) -Detalle ("{0} bases auxiliares consolidadas" -f $basesAuxiliares.Count) -Color $Script:GUIColors.Accent), 1, 0)
    $cards.Controls.Add((New-SqlHealthMetricCard -Titulo 'Datos de empresas' -Valor ("{0:N1} GB" -f $datosUsadosGB) -Detalle ("{0:N1} GB asignados | Aux: {1:N1} GB" -f $datosAsignadosGB, $datosAuxiliaresGB) -Color $Script:GUIColors.Success), 2, 0)
    $cards.Controls.Add((New-SqlHealthMetricCard -Titulo 'Empresas por revisar' -Valor ([string]$empresasPorRevisar) -Detalle ("{0} criticas | {1} atencion" -f $empresasCriticas, $empresasAtencion) -Color $(if ($empresasCriticas -gt 0) { $Script:GUIColors.Error } elseif ($empresasAtencion -gt 0) { $Script:GUIColors.Warning } else { $Script:GUIColors.Success })), 3, 0)

    $mainSplit = New-Object System.Windows.Forms.SplitContainer
    $mainSplit.Dock = 'Fill'
    $mainSplit.Orientation = 'Horizontal'
    $mainSplit.SplitterWidth = 5
    $mainSplit.BackColor = $Script:GUIColors.Separator
    $mainSplit.Panel1MinSize = 145
    $mainSplit.Panel2MinSize = 145

    $chartPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $chartPanel.Dock = 'Fill'
    $chartPanel.Padding = New-Object System.Windows.Forms.Padding(9, 4, 9, 4)
    $chartPanel.BackColor = $Script:GUIColors.Surface
    $chartPanel.ColumnCount = 1
    $chartPanel.RowCount = 2
    $chartPanel.RowStyles.Clear()
    $null = $chartPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 30)))
    $null = $chartPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
    $mainSplit.Panel1.Controls.Add($chartPanel)

    $chartHeader = New-Object System.Windows.Forms.TableLayoutPanel
    $chartHeader.Dock = 'Fill'
    $chartHeader.ColumnCount = 2
    $chartHeader.RowCount = 1
    $chartHeader.ColumnStyles.Clear()
    $chartHeader.RowStyles.Clear()
    $null = $chartHeader.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
    $null = $chartHeader.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 145)))
    $null = $chartHeader.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
    $chartHeader.BackColor = $Script:GUIColors.Surface

    $chartTitle = New-Object System.Windows.Forms.Label
    $chartTitle.Dock = 'Top'
    $chartTitle.Height = 30
    $limiteGrafica = [math]::Min(8, $basesPrincipales.Count)
    $chartTitle.Text = if ($basesPrincipales.Count -gt 8) { 'RESUMEN DE ESPACIO  /  8 EMPRESAS CON MAYOR TAMANO' } else { 'ESPACIO UTILIZADO POR EMPRESA' }
    $chartTitle.ForeColor = $Script:GUIColors.Text
    $chartTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    $chartTitle.TextAlign = 'MiddleLeft'
    $chartHeader.Controls.Add($chartTitle, 0, 0)

    $expandChart = New-Object System.Windows.Forms.Button
    $expandChart.Dock = 'Fill'
    $expandChart.Margin = New-Object System.Windows.Forms.Padding(5, 1, 0, 1)
    $expandChart.Text = 'AMPLIAR GRAFICA'
    $expandChart.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7, [System.Drawing.FontStyle]::Bold)
    Set-ModernButtonStyle -Button $expandChart -BaseColor $Script:GUIColors.AccentDark -TextColor $Script:GUIColors.Text -HoverColor $Script:GUIColors.Accent
    $expandChart.Enabled = ($basesPrincipales.Count -gt 0)
    $chartHeader.Controls.Add($expandChart, 1, 0)
    $chartPanel.Controls.Add($chartHeader, 0, 0)

    try {
        $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
        $chart.Dock = 'Fill'
        $chart.BackColor = $Script:GUIColors.Surface
        $chart.AntiAliasing = 'All'
        $area = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea('EspacioSQL')
        $area.BackColor = $Script:GUIColors.Surface
        $area.AxisX.LabelStyle.ForeColor = $Script:GUIColors.TextDim
        $area.AxisX.LabelStyle.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
        $area.AxisX.LineColor = $Script:GUIColors.Separator
        $area.AxisX.MajorGrid.Enabled = $false
        $area.AxisX.Interval = 1
        $area.AxisY.LabelStyle.ForeColor = $Script:GUIColors.TextDim
        $area.AxisY.LabelStyle.Font = New-Object System.Drawing.Font('Segoe UI', 7)
        $area.AxisY.LabelStyle.Format = 'N1'
        $area.AxisY.LineColor = $Script:GUIColors.Separator
        $area.AxisY.MajorGrid.LineColor = $Script:GUIColors.Separator
        $area.AxisY.Title = 'GB'
        $area.AxisY.TitleForeColor = $Script:GUIColors.TextDim
        $chart.ChartAreas.Add($area)

        $usedSeries = New-Object System.Windows.Forms.DataVisualization.Charting.Series('Utilizado')
        $usedSeries.ChartType = 'StackedBar'
        $usedSeries.Color = $Script:GUIColors.Accent
        $usedSeries.BorderWidth = 0
        $freeSeries = New-Object System.Windows.Forms.DataVisualization.Charting.Series('Disponible en archivo')
        $freeSeries.ChartType = 'StackedBar'
        $freeSeries.Color = [System.Drawing.Color]::FromArgb(48, 55, 68)
        $freeSeries.BorderWidth = 0

        $resumenGrafica = @($basesPrincipales | Where-Object { $_.DatosAsignadosMB -gt 0 } | Sort-Object DatosAsignadosMB -Descending | Select-Object -First 8 | Sort-Object DatosAsignadosMB)
        foreach ($empresa in $resumenGrafica) {
            $usadoGB = [math]::Round(([double]$empresa.DatosUsadosMB / 1024), 2)
            $libreGB = [math]::Round(([double]$empresa.DatosLibresMB / 1024), 2)
            $nombreCompleto = [string]$empresa.Nombre
            $nombreGrafica = if ($nombreCompleto.Length -gt 31) { $nombreCompleto.Substring(0, 28) + '...' } else { $nombreCompleto }
            $idxUsed = $usedSeries.Points.AddXY($nombreGrafica, $usadoGB)
            $usedSeries.Points[$idxUsed].ToolTip = "$($empresa.Nombre): $usadoGB GB utilizados ($($empresa.UsoDatosPct)%)"
            $idxFree = $freeSeries.Points.AddXY($nombreGrafica, $libreGB)
            $freeSeries.Points[$idxFree].ToolTip = "$($empresa.Nombre): $libreGB GB disponibles dentro del archivo"
        }
        $chart.Series.Add($usedSeries)
        $chart.Series.Add($freeSeries)
        $legend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend('Leyenda')
        $legend.Docking = 'Bottom'
        $legend.Alignment = 'Center'
        $legend.BackColor = $Script:GUIColors.Surface
        $legend.ForeColor = $Script:GUIColors.TextDim
        $legend.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
        $chart.Legends.Add($legend)
        $chartPanel.Controls.Add($chart, 0, 1)
    } catch {
        $chartFallback = New-Object System.Windows.Forms.Label
        $chartFallback.Dock = 'Fill'
        $chartFallback.TextAlign = 'MiddleCenter'
        $chartFallback.ForeColor = $Script:GUIColors.Warning
        $chartFallback.Text = 'La grafica no esta disponible en esta version de Windows. La informacion completa aparece en la tabla.'
        $chartPanel.Controls.Add($chartFallback, 0, 1)
    }
    $expandChart.Add_Click(({ Show-SqlSpaceChartWindow -Instancia $Instancia -Empresas $Empresas }).GetNewClosure())

    $lowerLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $lowerLayout.Dock = 'Fill'
    $lowerLayout.ColumnCount = 2
    $lowerLayout.RowCount = 1
    $lowerLayout.Padding = New-Object System.Windows.Forms.Padding(0)
    $lowerLayout.BackColor = $Script:GUIColors.LogBG
    $lowerLayout.ColumnStyles.Clear()
    $lowerLayout.RowStyles.Clear()
    $null = $lowerLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 68)))
    $null = $lowerLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 32)))
    $null = $lowerLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
    $mainSplit.Panel2.Controls.Add($lowerLayout)

    $gridPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $gridPanel.Dock = 'Fill'
    $gridPanel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 4, 0)
    $gridPanel.Padding = New-Object System.Windows.Forms.Padding(0)
    $gridPanel.BackColor = $Script:GUIColors.Surface
    $gridPanel.ColumnCount = 1
    $gridPanel.RowCount = 2
    $gridPanel.RowStyles.Clear()
    $null = $gridPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 36)))
    $null = $gridPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
    $lowerLayout.Controls.Add($gridPanel, 0, 0)

    $gridHeader = New-Object System.Windows.Forms.Panel
    $gridHeader.Dock = 'Top'
    $gridHeader.Height = 36
    $gridHeader.Padding = New-Object System.Windows.Forms.Padding(9, 5, 7, 4)
    $gridHeader.BackColor = $Script:GUIColors.Surface

    $gridTitle = New-Object System.Windows.Forms.Label
    $gridTitle.Dock = 'Fill'
    $gridTitle.TextAlign = 'MiddleLeft'
    $gridTitle.Text = "EMPRESAS: $($basesPrincipales.Count)  /  AUXILIARES: $($basesAuxiliares.Count)"
    $gridTitle.ForeColor = $Script:GUIColors.Text
    $gridTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
    $gridHeader.Controls.Add($gridTitle)

    $searchHost = New-Object System.Windows.Forms.TableLayoutPanel
    $searchHost.Dock = 'Right'
    $searchHost.Width = 390
    $searchHost.BackColor = $Script:GUIColors.Surface
    $searchHost.ColumnCount = 3
    $searchHost.RowCount = 1
    $searchHost.ColumnStyles.Clear()
    $searchHost.RowStyles.Clear()
    $null = $searchHost.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 58)))
    $null = $searchHost.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
    $null = $searchHost.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 125)))
    $null = $searchHost.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))

    $searchLabel = New-Object System.Windows.Forms.Label
    $searchLabel.Dock = 'Left'
    $searchLabel.Width = 58
    $searchLabel.Text = 'BUSCAR:'
    $searchLabel.TextAlign = 'MiddleLeft'
    $searchLabel.ForeColor = $Script:GUIColors.TextDim
    $searchLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7, [System.Drawing.FontStyle]::Bold)
    $searchHost.Controls.Add($searchLabel, 0, 0)

    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.Dock = 'Fill'
    $searchBox.Text = ' Buscar empresa...'
    $searchBox.BackColor = $Script:GUIColors.BG
    $searchBox.ForeColor = $Script:GUIColors.TextDim
    $searchBox.BorderStyle = 'FixedSingle'
    $searchBox.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $searchHost.Controls.Add($searchBox, 1, 0)

    $showAux = New-Object System.Windows.Forms.CheckBox
    $showAux.Dock = 'Fill'
    $showAux.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $showAux.Text = 'Incluir auxiliares'
    $showAux.Checked = $false
    $showAux.Enabled = ($basesAuxiliares.Count -gt 0)
    $showAux.ForeColor = $Script:GUIColors.TextDim
    $showAux.BackColor = $Script:GUIColors.Surface
    $showAux.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $showAux.Cursor = [System.Windows.Forms.Cursors]::Hand
    $searchHost.Controls.Add($showAux, 2, 0)
    $gridHeader.Controls.Add($searchHost)
    $searchHost.BringToFront()
    $gridPanel.Controls.Add($gridHeader, 0, 0)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.RowHeadersVisible = $false
    $grid.MultiSelect = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.BackgroundColor = $Script:GUIColors.LogBG
    $grid.BorderStyle = 'None'
    $grid.GridColor = $Script:GUIColors.Separator
    $grid.EnableHeadersVisualStyles = $false
    $grid.ColumnHeadersHeight = 30
    $grid.ColumnHeadersDefaultCellStyle.BackColor = $Script:GUIColors.Header
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = $Script:GUIColors.Accent
    $grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
    $grid.DefaultCellStyle.BackColor = $Script:GUIColors.LogBG
    $grid.DefaultCellStyle.ForeColor = $Script:GUIColors.Text
    $grid.DefaultCellStyle.SelectionBackColor = $Script:GUIColors.AccentDark
    $grid.DefaultCellStyle.SelectionForeColor = $Script:GUIColors.Text
    $grid.DefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $grid.AlternatingRowsDefaultCellStyle.BackColor = $Script:GUIColors.SurfaceAlt
    $grid.RowTemplate.Height = 25
    foreach ($def in @(
        @('Empresa', 'EMPRESA', 145), @('Estado', 'ESTADO', 68), @('Datos', 'DATOS GB', 66),
        @('Uso', 'USO', 54), @('Log', 'LOG GB', 56), @('Backup', 'ULTIMO RESPALDO', 112), @('Salud', 'SALUD', 72)
    )) {
        $column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $column.Name = $def[0]
        $column.HeaderText = $def[1]
        $column.MinimumWidth = 45
        $column.FillWeight = [single]$def[2]
        $null = $grid.Columns.Add($column)
    }
    # Los eventos se ejecutan en un cierre independiente; conservar los colores
    # localmente evita que $Script:GUIColors sea NULL al enfocar el buscador.
    $searchTextColor = $Script:GUIColors.Text
    $searchIdleColor = $Script:GUIColors.TextDim
    $rowCriticalColor = $Script:GUIColors.Error
    $rowWarningColor = $Script:GUIColors.Warning
    $rowNormalColor = $Script:GUIColors.Text
    $gridErrorColor = $Script:GUIColors.Error

    $addEmpresaGridRow = {
        param($empresa)
        $backupText = if (-not $RespaldosDisponibles) { 'No disponible' } elseif ($empresa.UltimoRespaldo) { ([datetime]$empresa.UltimoRespaldo).ToString('dd/MM/yy HH:mm') } else { 'Sin registro' }
        $rowIndex = $grid.Rows.Add(
            [string]$empresa.Nombre,
            [string]$empresa.Estado,
            ("{0:N2}" -f ([double]$empresa.DatosUsadosMB / 1024)),
            ("{0:N1}%" -f [double]$empresa.UsoDatosPct),
            ("{0:N2}" -f ([double]$empresa.LogMB / 1024)),
            $backupText,
            [string]$empresa.Salud
        )
        $row = $grid.Rows[$rowIndex]
        $row.Tag = $empresa
        $row.DefaultCellStyle.ForeColor = if ($empresa.Salud -eq 'CRITICA') { $rowCriticalColor } elseif ($empresa.Salud -eq 'ATENCION') { $rowWarningColor } else { $rowNormalColor }
    }.GetNewClosure()

    $searchBox.Add_GotFocus(({ if ($searchBox.Text -eq ' Buscar empresa...') { $searchBox.Text = ''; $searchBox.ForeColor = $searchTextColor } }).GetNewClosure())
    $searchBox.Add_LostFocus(({ if ([string]::IsNullOrWhiteSpace($searchBox.Text)) { $searchBox.Text = ' Buscar empresa...'; $searchBox.ForeColor = $searchIdleColor } }).GetNewClosure())
    $refreshGridRows = {
        try {
            $textoFiltro = $searchBox.Text.Trim()
            if ($textoFiltro -eq 'Buscar empresa...') { $textoFiltro = '' }
            $incluirAuxiliares = [bool]$showAux.Checked
            $filtradas = @($Empresas | Where-Object {
                $coincideTipo = ($incluirAuxiliares -or -not [bool]$_.EsAuxiliar)
                $coincideTexto = ([string]::IsNullOrWhiteSpace($textoFiltro) -or ([string]$_.Nombre).IndexOf($textoFiltro, [StringComparison]::OrdinalIgnoreCase) -ge 0)
                $coincideTipo -and $coincideTexto
            } | Sort-Object Nombre)

            $grid.SuspendLayout()
            try {
                $grid.Rows.Clear()
                foreach ($empresaFiltrada in $filtradas) { & $addEmpresaGridRow $empresaFiltrada }
                $grid.ClearSelection()
                $grid.CurrentCell = $null
            } finally {
                $grid.ResumeLayout()
            }
            $gridTitle.Text = "MOSTRANDO: $($filtradas.Count)  /  EMPRESAS: $($basesPrincipales.Count)  /  AUX: $($basesAuxiliares.Count)"
        } catch {
            $gridTitle.Text = 'No fue posible aplicar el filtro. Borra la busqueda e intenta nuevamente.'
            $gridTitle.ForeColor = $gridErrorColor
        }
    }.GetNewClosure()
    $searchBox.Add_TextChanged(({ & $refreshGridRows }).GetNewClosure())
    $showAux.Add_CheckedChanged(({ & $refreshGridRows }).GetNewClosure())
    & $refreshGridRows
    $gridPanel.Controls.Add($grid, 0, 1)

    $alertsPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $alertsPanel.Dock = 'Fill'
    $alertsPanel.Margin = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)
    $alertsPanel.BackColor = $Script:GUIColors.Surface
    $alertsPanel.ColumnCount = 1
    $alertsPanel.RowCount = 2
    $alertsPanel.RowStyles.Clear()
    $null = $alertsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 28)))
    $null = $alertsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
    $lowerLayout.Controls.Add($alertsPanel, 1, 0)

    $alertsHeader = New-Object System.Windows.Forms.Label
    $alertsHeader.Dock = 'Top'
    $alertsHeader.Height = 28
    $alertsHeader.Padding = New-Object System.Windows.Forms.Padding(9, 0, 0, 0)
    $alertsHeader.TextAlign = 'MiddleLeft'
    $alertsHeader.Text = 'HALLAZGOS Y CAPACIDAD'
    $alertsHeader.ForeColor = $Script:GUIColors.Text
    $alertsHeader.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
    $alertsPanel.Controls.Add($alertsHeader, 0, 0)

    $alertBox = New-Object System.Windows.Forms.RichTextBox
    $alertBox.Dock = 'Fill'
    $alertBox.ReadOnly = $true
    $alertBox.BorderStyle = 'None'
    $alertBox.BackColor = $Script:GUIColors.Surface
    $alertBox.ForeColor = $Script:GUIColors.TextDim
    $alertBox.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $alertBox.DetectUrls = $false
    $alertBox.WordWrap = $true

    # En instalaciones grandes no se imprime una alerta repetida por cada base.
    # Se agrupan por causa y la tabla conserva el detalle individual completo.
    $resumenHallazgos = @()
    $fueraLinea = @($basesPrincipales | Where-Object { $_.Estado -ne 'ONLINE' })
    if ($fueraLinea.Count -gt 0) { $resumenHallazgos += [PSCustomObject]@{ Nivel = 'CRITICA'; Mensaje = "$($fueraLinea.Count) base(s) no estan ONLINE." } }
    $datosCriticos = @($basesPrincipales | Where-Object { $_.DatosAsignadosMB -gt 0 -and $_.UsoDatosPct -ge 90 })
    if ($datosCriticos.Count -gt 0) { $resumenHallazgos += [PSCustomObject]@{ Nivel = 'CRITICA'; Mensaje = "$($datosCriticos.Count) base(s) superan 90% del espacio de datos asignado." } }
    $datosAtencion = @($basesPrincipales | Where-Object { $_.DatosAsignadosMB -gt 0 -and $_.UsoDatosPct -ge 80 -and $_.UsoDatosPct -lt 90 })
    if ($datosAtencion.Count -gt 0) { $resumenHallazgos += [PSCustomObject]@{ Nivel = 'ATENCION'; Mensaje = "$($datosAtencion.Count) base(s) utilizan entre 80% y 90% del espacio de datos." } }
    $logsCriticos = @($basesPrincipales | Where-Object { $_.LogUsadoPct -ge 90 })
    if ($logsCriticos.Count -gt 0) { $resumenHallazgos += [PSCustomObject]@{ Nivel = 'CRITICA'; Mensaje = "$($logsCriticos.Count) log(s) de transacciones superan 90% de uso." } }
    $logsAtencion = @($basesPrincipales | Where-Object { $_.LogUsadoPct -ge 80 -and $_.LogUsadoPct -lt 90 })
    if ($logsAtencion.Count -gt 0) { $resumenHallazgos += [PSCustomObject]@{ Nivel = 'ATENCION'; Mensaje = "$($logsAtencion.Count) log(s) utilizan entre 80% y 90%." } }
    $sinChecksum = @($basesPrincipales | Where-Object { $_.VerificacionPagina -ne 'CHECKSUM' })
    if ($sinChecksum.Count -gt 0) { $resumenHallazgos += [PSCustomObject]@{ Nivel = 'ATENCION'; Mensaje = "$($sinChecksum.Count) base(s) no utilizan PAGE_VERIFY CHECKSUM." } }
    if ($RespaldosDisponibles) {
        $sinRespaldo = @($basesPrincipales | Where-Object { -not $_.UltimoRespaldo })
        if ($sinRespaldo.Count -gt 0) { $resumenHallazgos += [PSCustomObject]@{ Nivel = 'ATENCION'; Mensaje = "$($sinRespaldo.Count) base(s) no tienen respaldo completo registrado." } }
        $fechaActual = Get-Date
        $respaldosAntiguos = @($basesPrincipales | Where-Object { $_.UltimoRespaldo -and ($fechaActual - [datetime]$_.UltimoRespaldo).TotalDays -gt 7 })
        if ($respaldosAntiguos.Count -gt 0) { $resumenHallazgos += [PSCustomObject]@{ Nivel = 'ATENCION'; Mensaje = "$($respaldosAntiguos.Count) base(s) tienen el ultimo respaldo completo con mas de 7 dias." } }
    }
    try {
        if ([int]$Actividad.SolicitudesBloqueadas -gt 0) { $resumenHallazgos += [PSCustomObject]@{ Nivel = 'CRITICA'; Mensaje = "$($Actividad.SolicitudesBloqueadas) solicitud(es) estan bloqueadas en este momento." } }
    } catch { }
    foreach ($alertaInfo in @($Alertas | Where-Object { $_.Nivel -eq 'INFO' } | Select-Object -First 3)) {
        $resumenHallazgos += $alertaInfo
    }

    if ($resumenHallazgos.Count -eq 0) {
        $alertBox.SelectionColor = $Script:GUIColors.Success
        $alertBox.AppendText("  SIN HALLAZGOS IMPORTANTES`r`n")
        $alertBox.SelectionColor = $Script:GUIColors.TextDim
        $alertBox.AppendText("  SQL se encuentra dentro de los parametros revisados.`r`n")
    } else {
        foreach ($alerta in @($resumenHallazgos | Select-Object -First 12)) {
            $alertBox.SelectionColor = if ($alerta.Nivel -eq 'CRITICA') { $Script:GUIColors.Error } elseif ($alerta.Nivel -eq 'ATENCION') { $Script:GUIColors.Warning } else { $Script:GUIColors.Accent }
            $alertBox.AppendText("  [$($alerta.Nivel)] ")
            $alertBox.SelectionColor = $Script:GUIColors.TextDim
            $alertBox.AppendText("$($alerta.Mensaje)`r`n")
        }
    }
    if ($basesAuxiliares.Count -gt 0) {
        $auxProblema = @($basesAuxiliares | Where-Object { $_.Estado -ne 'ONLINE' -or $_.UsoDatosPct -ge 95 -or $_.LogUsadoPct -ge 95 }).Count
        $alertBox.AppendText("`r`n")
        $alertBox.SelectionColor = $Script:GUIColors.Accent
        $alertBox.AppendText("  BASES AUXILIARES CONSOLIDADAS`r`n")
        $alertBox.SelectionColor = $Script:GUIColors.TextDim
        $alertBox.AppendText("  $($basesAuxiliares.Count) bases de catalogos/documentos no se cuentan como empresas.`r`n")
        if ($auxProblema -gt 0) {
            $alertBox.SelectionColor = $Script:GUIColors.Warning
            $alertBox.AppendText("  $auxProblema auxiliar(es) requieren revision de estado o capacidad.`r`n")
        }
    }
    if ($Volumenes.Count -gt 0) {
        $alertBox.AppendText("`r`n")
        $alertBox.SelectionColor = $Script:GUIColors.Accent
        $alertBox.AppendText("  ALMACENAMIENTO DEL SERVIDOR`r`n")
        foreach ($volumen in $Volumenes) {
            $alertBox.SelectionColor = $Script:GUIColors.TextDim
            $alertBox.AppendText(("  {0}  {1:N1} GB libres de {2:N1} GB ({3:N1}%)`r`n" -f $volumen.Unidad, [double]$volumen.LibreGB, [double]$volumen.TotalGB, [double]$volumen.LibrePct))
        }
    }
    $alertBox.AppendText("`r`n")
    $alertBox.SelectionColor = $Script:GUIColors.Accent
    $alertBox.AppendText("  ACTIVIDAD`r`n")
    $alertBox.SelectionColor = $Script:GUIColors.TextDim
    $alertBox.AppendText("  Sesiones: $($Actividad.SesionesUsuario) | Solicitudes: $($Actividad.SolicitudesActivas) | Bloqueadas: $($Actividad.SolicitudesBloqueadas)")

    $overviewRtf = $alertBox.Rtf
    $detailPalette = @{
        Accent = $Script:GUIColors.Accent; Text = $Script:GUIColors.Text
        TextDim = $Script:GUIColors.TextDim; Success = $Script:GUIColors.Success
        Warning = $Script:GUIColors.Warning; Error = $Script:GUIColors.Error
    }
    $overviewTitle = 'RESUMEN GENERAL  /  SELECCIONA UNA EMPRESA PARA VER EL DIAGNOSTICO'
    $alertsHeader.Text = $overviewTitle
    $showSelectedCompany = {
        try {
            if ($grid.SelectedRows.Count -gt 0 -and $grid.SelectedRows[0].Tag) {
                $empresaSeleccionada = $grid.SelectedRows[0].Tag
                $alertsHeader.Text = "DIAGNOSTICO  /  $($empresaSeleccionada.Nombre)"
                Show-SqlCompanyDiagnostic -Target $alertBox -Empresa $empresaSeleccionada -Palette $detailPalette -RespaldosDisponibles $RespaldosDisponibles
            } else {
                $alertsHeader.Text = $overviewTitle
                $alertBox.Rtf = $overviewRtf
            }
        } catch {
            $alertsHeader.Text = 'No fue posible mostrar el diagnostico de esta empresa.'
            $alertsHeader.ForeColor = $detailPalette.Error
        }
    }.GetNewClosure()
    $grid.Add_SelectionChanged(({ & $showSelectedCompany }).GetNewClosure())
    $grid.Add_CellClick(({ param($sender, $eventArgs) if ($eventArgs.RowIndex -ge 0) { & $showSelectedCompany } }).GetNewClosure())
    $alertsPanel.Controls.Add($alertBox, 0, 1)

    $body.Controls.Add($cards, 0, 0)
    $body.Controls.Add($mainSplit, 0, 1)
    $dashboard.Controls.Add($body)
    $dashboard.Controls.Add($footer)
    $dashboard.Controls.Add($header)
    $Script:LogPanel.Controls.Add($dashboard)
    $dashboard.BringToFront()
    $dashboard.PerformLayout()
    $body.PerformLayout()
    $availableHeight = $mainSplit.ClientSize.Height
    if ($availableHeight -gt 310) {
        $mainSplit.SplitterDistance = [math]::Max(145, [math]::Min(($availableHeight - 150), [int]($availableHeight * 0.47)))
    }
    $resizeHandler = {
        param($sender, $eventArgs)
        try {
            $height = $mainSplit.ClientSize.Height
            if ($height -gt 310) {
                $mainSplit.SplitterDistance = [math]::Max(145, [math]::Min(($height - 150), [int]($height * 0.47)))
            }
        } catch { }
    }.GetNewClosure()
    $dashboard.Add_Resize($resizeHandler)
    $closeButton.Add_Click(({ Close-CurrentPanel }).GetNewClosure())
    $Script:CurrentPanel = $dashboard
}

function Show-SaludSQLProfesional {
    Write-Encabezado -Titulo 'SALUD DE SQL SERVER' -Subtitulo 'Capacidad, respaldos, actividad y estado por empresa' -Color 'Magenta'
    $motores = @(Get-ServiciosMotorSQL)
    if ($motores.Count -eq 0) {
        Write-Log -Mensaje 'No se detectaron instancias reales del motor SQL Server en este equipo.' -Nivel ERROR
        Write-Log -Mensaje 'Ejecuta esta opcion directamente en el servidor que aloja las empresas.' -Nivel INFO
        return
    }

    $opcionesInstancia = @($motores | ForEach-Object {
        $nombreInstancia = Get-NombreInstanciaSQL -NombreServicio $_.Name
        "$nombreInstancia  |  $($_.Status)  |  $($_.DisplayName)"
    })
    $indiceInstancia = if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        Show-GUIChoice -Titulo 'Salud de SQL Server' -Mensaje 'Selecciona la instancia que deseas analizar:' -Opciones $opcionesInstancia
    } else {
        for ($i = 0; $i -lt $opcionesInstancia.Count; $i++) { Write-OpcionMenu -Tecla ($i + 1) -Descripcion $opcionesInstancia[$i] }
        ([int](Read-Host ' Selecciona instancia')) - 1
    }
    if ($indiceInstancia -lt 0 -or $indiceInstancia -ge $motores.Count) {
        Write-Log -Mensaje 'Analisis de salud SQL cancelado.' -Nivel INFO
        return
    }

    $motor = $motores[$indiceInstancia]
    $instancia = Get-NombreInstanciaSQL -NombreServicio $motor.Name
    if ($motor.Status -ne 'Running') {
        Write-Log -Mensaje "$instancia esta detenida; no es posible leer su estado interno." -Nivel ERROR
        Write-Log -Mensaje 'Puedes iniciarla desde Mantenimiento SQL o desde las acciones del servidor.' -Nivel INFO
        return
    }
    if (-not (Confirmar-Movimiento -Frase 'ANALIZAR SQL' -Accion "Analizar salud de $instancia" -Detalle 'El diagnostico es de solo lectura.')) { return }

    Write-Log -Mensaje "Conectando a $instancia sin modificar datos..." -Nivel PROGRESS
    $consultaServidor = @"
SET NOCOUNT ON;
SELECT
    CAST(SERVERPROPERTY('ServerName') AS nvarchar(128)) AS Servidor,
    CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS Version,
    CAST(SERVERPROPERTY('ProductLevel') AS nvarchar(128)) AS Nivel,
    CAST(SERVERPROPERTY('Edition') AS nvarchar(256)) AS Edicion,
    CAST(SERVERPROPERTY('IsClustered') AS int) AS EsCluster,
    (SELECT create_date FROM sys.databases WHERE name = N'tempdb') AS InicioSQL;
"@
    $resultadoServidor = Invoke-SqlTableResponsive -Instancia $instancia -Consulta $consultaServidor -TimeoutSegundos 20 -Actividad 'Leyendo informacion de SQL Server'
    if (-not $resultadoServidor.Correcto -or @($resultadoServidor.Filas).Count -eq 0) {
        Write-Log -Mensaje "No fue posible acceder a $($instancia): $($resultadoServidor.Error)" -Nivel ERROR
        Write-Log -Mensaje 'Verifica que el usuario de Windows tenga acceso a SQL Server.' -Nivel INFO
        return
    }
    $servidor = @($resultadoServidor.Filas)[0]
    Write-Log -Mensaje "Conexion correcta: $($servidor.Servidor) | SQL $($servidor.Version) | $($servidor.Edicion)" -Nivel OK

    $consultaEspacio = @"
SET NOCOUNT ON;
CREATE TABLE #Espacio (
    Nombre sysname NOT NULL,
    DatosAsignadosMB decimal(19,2) NULL,
    DatosUsadosMB decimal(19,2) NULL
);
DECLARE @db sysname, @sql nvarchar(max);
DECLARE dbs CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE database_id > 4 AND state = 0 AND HAS_DBACCESS(name) = 1;
OPEN dbs;
FETCH NEXT FROM dbs INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SET @sql = N'USE ' + QUOTENAME(@db) + N';
            INSERT INTO #Espacio (Nombre, DatosAsignadosMB, DatosUsadosMB)
            SELECT DB_NAME(),
                   CAST(SUM(CASE WHEN type = 0 THEN size ELSE 0 END) * 8.0 / 1024 AS decimal(19,2)),
                   CAST(SUM(CASE WHEN type = 0 THEN ISNULL(FILEPROPERTY(name, ''SpaceUsed''), 0) ELSE 0 END) * 8.0 / 1024 AS decimal(19,2))
            FROM sys.database_files;';
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
    END CATCH;
    FETCH NEXT FROM dbs INTO @db;
END;
CLOSE dbs;
DEALLOCATE dbs;

CREATE TABLE #LogSpace (Nombre sysname, LogSizeMB float, LogUsedPct float, Estado int);
BEGIN TRY
    INSERT INTO #LogSpace EXEC ('DBCC SQLPERF(LOGSPACE) WITH NO_INFOMSGS;');
END TRY
BEGIN CATCH
END CATCH;

SELECT
    d.name AS Nombre,
    d.state_desc AS Estado,
    d.user_access_desc AS Acceso,
    d.recovery_model_desc AS Recuperacion,
    d.page_verify_option_desc AS VerificacionPagina,
    d.compatibility_level AS Compatibilidad,
    d.is_read_only AS SoloLectura,
    CAST(ISNULL(e.DatosAsignadosMB, 0) AS decimal(19,2)) AS DatosAsignadosMB,
    CAST(ISNULL(e.DatosUsadosMB, 0) AS decimal(19,2)) AS DatosUsadosMB,
    CAST(CASE WHEN ISNULL(e.DatosAsignadosMB, 0) > ISNULL(e.DatosUsadosMB, 0)
              THEN e.DatosAsignadosMB - e.DatosUsadosMB ELSE 0 END AS decimal(19,2)) AS DatosLibresMB,
    CAST(CASE WHEN ISNULL(e.DatosAsignadosMB, 0) > 0
              THEN e.DatosUsadosMB * 100.0 / e.DatosAsignadosMB ELSE 0 END AS decimal(9,2)) AS UsoDatosPct,
    CAST(ISNULL(l.LogSizeMB, 0) AS decimal(19,2)) AS LogMB,
    CAST(ISNULL(l.LogUsedPct, 0) AS decimal(9,2)) AS LogUsadoPct
FROM sys.databases d
LEFT JOIN #Espacio e ON e.Nombre = d.name
LEFT JOIN #LogSpace l ON l.Nombre = d.name
WHERE d.database_id > 4
ORDER BY d.name;
"@
    $resultadoBases = Invoke-SqlTableResponsive -Instancia $instancia -Consulta $consultaEspacio -TimeoutSegundos 75 -Actividad 'Calculando espacio por empresa'
    if (-not $resultadoBases.Correcto) {
        Write-Log -Mensaje "No se pudo consultar el espacio de las empresas: $($resultadoBases.Error)" -Nivel ERROR
        return
    }
    $filasBases = @($resultadoBases.Filas)

    $consultaRespaldos = @"
SET NOCOUNT ON;
SELECT d.name AS Nombre,
       MAX(CASE WHEN bs.type = 'D' THEN bs.backup_finish_date END) AS UltimoCompleto,
       MAX(CASE WHEN bs.type = 'I' THEN bs.backup_finish_date END) AS UltimoDiferencial,
       MAX(CASE WHEN bs.type = 'L' THEN bs.backup_finish_date END) AS UltimoLog
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset bs ON bs.database_name = d.name
WHERE d.database_id > 4
GROUP BY d.name;
"@
    $resultadoRespaldos = Invoke-SqlTableResponsive -Instancia $instancia -Consulta $consultaRespaldos -TimeoutSegundos 35 -Actividad 'Revisando historial de respaldos'

    $consultaActividad = @"
SET NOCOUNT ON;
SELECT
    (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1) AS SesionesUsuario,
    (SELECT COUNT(*) FROM sys.dm_exec_requests WHERE session_id <> @@SPID) AS SolicitudesActivas,
    (SELECT COUNT(*) FROM sys.dm_exec_requests WHERE blocking_session_id <> 0) AS SolicitudesBloqueadas;
"@
    $resultadoActividad = Invoke-SqlTableResponsive -Instancia $instancia -Consulta $consultaActividad -TimeoutSegundos 20 -Actividad 'Revisando actividad y bloqueos'

    $consultaVolumenes = @"
SET NOCOUNT ON;
SELECT DISTINCT
    vs.volume_mount_point AS Unidad,
    CAST(vs.total_bytes / 1073741824.0 AS decimal(19,2)) AS TotalGB,
    CAST(vs.available_bytes / 1073741824.0 AS decimal(19,2)) AS LibreGB,
    CAST(CASE WHEN vs.total_bytes > 0 THEN vs.available_bytes * 100.0 / vs.total_bytes ELSE 0 END AS decimal(9,2)) AS LibrePct
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
ORDER BY vs.volume_mount_point;
"@
    $resultadoVolumenes = Invoke-SqlTableResponsive -Instancia $instancia -Consulta $consultaVolumenes -TimeoutSegundos 25 -Actividad 'Validando capacidad de discos SQL'

    $backupMap = @{}
    if ($resultadoRespaldos.Correcto) {
        foreach ($respaldo in @($resultadoRespaldos.Filas)) { $backupMap[[string]$respaldo.Nombre] = $respaldo }
    }
    $respaldosDisponibles = [bool]$resultadoRespaldos.Correcto
    $actividad = if ($resultadoActividad.Correcto -and @($resultadoActividad.Filas).Count -gt 0) {
        @($resultadoActividad.Filas)[0]
    } else {
        [PSCustomObject]@{ SesionesUsuario = 'N/D'; SolicitudesActivas = 'N/D'; SolicitudesBloqueadas = 'N/D' }
    }
    $volumenes = if ($resultadoVolumenes.Correcto) { @($resultadoVolumenes.Filas) } else { @() }

    $alertas = @()
    $empresas = @()
    $deduccion = 0
    if (-not $resultadoRespaldos.Correcto) {
        $alertas += [PSCustomObject]@{ Nivel = 'INFO'; Mensaje = "Historial de respaldos no disponible: $($resultadoRespaldos.Error)" }
    }
    if (-not $resultadoActividad.Correcto) {
        $alertas += [PSCustomObject]@{ Nivel = 'INFO'; Mensaje = 'Actividad y bloqueos no disponibles; se requiere VIEW SERVER STATE.' }
    }
    if (-not $resultadoVolumenes.Correcto) {
        $alertas += [PSCustomObject]@{ Nivel = 'INFO'; Mensaje = 'Capacidad de discos no disponible; se requiere VIEW SERVER STATE.' }
    }

    foreach ($fila in $filasBases) {
        $nombre = [string]$fila.Nombre
        $estado = [string]$fila.Estado
        $asignado = if ($null -ne $fila.DatosAsignadosMB) { [double]$fila.DatosAsignadosMB } else { 0 }
        $usado = if ($null -ne $fila.DatosUsadosMB) { [double]$fila.DatosUsadosMB } else { 0 }
        $libre = if ($null -ne $fila.DatosLibresMB) { [double]$fila.DatosLibresMB } else { 0 }
        $usoPct = if ($null -ne $fila.UsoDatosPct) { [double]$fila.UsoDatosPct } else { 0 }
        $logMB = if ($null -ne $fila.LogMB) { [double]$fila.LogMB } else { 0 }
        $logPct = if ($null -ne $fila.LogUsadoPct) { [double]$fila.LogUsadoPct } else { 0 }
        $ultimoRespaldo = $null
        if ($backupMap.ContainsKey($nombre) -and $backupMap[$nombre].UltimoCompleto) {
            try { $ultimoRespaldo = [datetime]$backupMap[$nombre].UltimoCompleto } catch { $ultimoRespaldo = $null }
        }
        $nivelEmpresa = 0

        if ($estado -ne 'ONLINE') {
            $alertas += [PSCustomObject]@{ Nivel = 'CRITICA'; Mensaje = "$nombre esta en estado $estado." }
            $deduccion += 20
            $nivelEmpresa = 2
        }
        if ($asignado -le 0 -and $estado -eq 'ONLINE') {
            $alertas += [PSCustomObject]@{ Nivel = 'INFO'; Mensaje = "$nombre no devolvio metricas de espacio; revisa permisos de acceso." }
        } elseif ($usoPct -ge 90) {
            $alertas += [PSCustomObject]@{ Nivel = 'CRITICA'; Mensaje = "$nombre utiliza $([math]::Round($usoPct,1))% del espacio asignado a datos." }
            $deduccion += 10
            $nivelEmpresa = 2
        } elseif ($usoPct -ge 80) {
            $alertas += [PSCustomObject]@{ Nivel = 'ATENCION'; Mensaje = "$nombre utiliza $([math]::Round($usoPct,1))% del espacio asignado a datos." }
            $deduccion += 4
            $nivelEmpresa = [math]::Max($nivelEmpresa, 1)
        }
        if ($logPct -ge 90) {
            $alertas += [PSCustomObject]@{ Nivel = 'CRITICA'; Mensaje = "El log de $nombre esta utilizado al $([math]::Round($logPct,1))%." }
            $deduccion += 8
            $nivelEmpresa = 2
        } elseif ($logPct -ge 80) {
            $alertas += [PSCustomObject]@{ Nivel = 'ATENCION'; Mensaje = "El log de $nombre esta utilizado al $([math]::Round($logPct,1))%." }
            $deduccion += 3
            $nivelEmpresa = [math]::Max($nivelEmpresa, 1)
        }
        if ([string]$fila.VerificacionPagina -ne 'CHECKSUM') {
            $alertas += [PSCustomObject]@{ Nivel = 'ATENCION'; Mensaje = "$nombre usa PAGE_VERIFY $($fila.VerificacionPagina), no CHECKSUM." }
            $deduccion += 3
            $nivelEmpresa = [math]::Max($nivelEmpresa, 1)
        }
        if ($respaldosDisponibles) {
            if (-not $ultimoRespaldo) {
                $alertas += [PSCustomObject]@{ Nivel = 'ATENCION'; Mensaje = "$nombre no tiene respaldo completo registrado en SQL." }
                $deduccion += 6
                $nivelEmpresa = [math]::Max($nivelEmpresa, 1)
            } else {
                $diasRespaldo = ((Get-Date) - $ultimoRespaldo).TotalDays
                if ($diasRespaldo -gt 7) {
                    $alertas += [PSCustomObject]@{ Nivel = 'ATENCION'; Mensaje = "El ultimo respaldo completo de $nombre tiene $([math]::Floor($diasRespaldo)) dias." }
                    $deduccion += 5
                    $nivelEmpresa = [math]::Max($nivelEmpresa, 1)
                }
            }
        }
        $salud = if ($nivelEmpresa -ge 2) { 'CRITICA' } elseif ($nivelEmpresa -eq 1) { 'ATENCION' } else { 'SALUDABLE' }
        $esAuxiliar = ($nombre -match '(?i)^document_[0-9a-f-]+_(content|metadata)$' -or
            $nombre -match '(?i)^(ADD_Catalogos|CompacWAdmin|GeneralSQL|dbDocumentosDigitales|CONTPAQ_I_SDK)$')
        $empresas += [PSCustomObject]@{
            Nombre = $nombre; Estado = $estado; Acceso = [string]$fila.Acceso
            Recuperacion = [string]$fila.Recuperacion; VerificacionPagina = [string]$fila.VerificacionPagina
            Compatibilidad = [int]$fila.Compatibilidad; SoloLectura = [bool]$fila.SoloLectura
            DatosAsignadosMB = [math]::Round($asignado, 2); DatosUsadosMB = [math]::Round($usado, 2)
            DatosLibresMB = [math]::Round($libre, 2); UsoDatosPct = [math]::Round($usoPct, 1)
            LogMB = [math]::Round($logMB, 2); LogUsadoPct = [math]::Round($logPct, 1)
            UltimoRespaldo = $ultimoRespaldo; Salud = $salud
            EsAuxiliar = [bool]$esAuxiliar
            TipoBase = $(if ($esAuxiliar) { 'AUXILIAR' } else { 'EMPRESA' })
        }
    }

    if ($resultadoActividad.Correcto -and [int]$actividad.SolicitudesBloqueadas -gt 0) {
        $alertas += [PSCustomObject]@{ Nivel = 'CRITICA'; Mensaje = "Hay $($actividad.SolicitudesBloqueadas) solicitud(es) bloqueada(s) en este momento." }
        $deduccion += 10
    }
    foreach ($volumen in $volumenes) {
        $librePct = [double]$volumen.LibrePct
        $libreGB = [double]$volumen.LibreGB
        if ($librePct -lt 10 -or $libreGB -lt 5) {
            $alertas += [PSCustomObject]@{ Nivel = 'CRITICA'; Mensaje = "La unidad $($volumen.Unidad) solo tiene $([math]::Round($libreGB,1)) GB libres ($([math]::Round($librePct,1))%)." }
            $deduccion += 15
        } elseif ($librePct -lt 20 -or $libreGB -lt 15) {
            $alertas += [PSCustomObject]@{ Nivel = 'ATENCION'; Mensaje = "La unidad $($volumen.Unidad) tiene $([math]::Round($libreGB,1)) GB libres ($([math]::Round($librePct,1))%)." }
            $deduccion += 6
        }
    }
    if ($empresas.Count -eq 0) {
        $alertas += [PSCustomObject]@{ Nivel = 'INFO'; Mensaje = 'La instancia no contiene bases de datos de usuario.' }
    }

    # El puntaje se calcula por categorias y proporcion afectada. Asi, una
    # instancia con cientos de bases no llega a cero por repetir la misma causa.
    $deduccion = 0
    $basesPrincipalesPuntaje = @($empresas | Where-Object { -not $_.EsAuxiliar })
    $basesAuxiliaresPuntaje = @($empresas | Where-Object { $_.EsAuxiliar })
    $basesEvaluadas = if ($basesPrincipalesPuntaje.Count -gt 0) { $basesPrincipalesPuntaje } else { @() }
    $totalEmpresas = [math]::Max(1, $basesEvaluadas.Count)
    $cantidadFueraLinea = @($basesEvaluadas | Where-Object { $_.Estado -ne 'ONLINE' }).Count
    if ($cantidadFueraLinea -gt 0) { $deduccion += [math]::Min(20, 8 + [math]::Ceiling(12 * $cantidadFueraLinea / $totalEmpresas)) }
    $cantidadDatosCriticos = @($basesEvaluadas | Where-Object { $_.DatosAsignadosMB -gt 0 -and $_.UsoDatosPct -ge 90 }).Count
    if ($cantidadDatosCriticos -gt 0) { $deduccion += [math]::Min(20, 5 + [math]::Ceiling(15 * $cantidadDatosCriticos / $totalEmpresas)) }
    $cantidadDatosAtencion = @($basesEvaluadas | Where-Object { $_.DatosAsignadosMB -gt 0 -and $_.UsoDatosPct -ge 80 -and $_.UsoDatosPct -lt 90 }).Count
    if ($cantidadDatosAtencion -gt 0) { $deduccion += [math]::Min(6, [math]::Ceiling(6 * $cantidadDatosAtencion / $totalEmpresas)) }
    $cantidadLogsCriticos = @($basesEvaluadas | Where-Object { $_.LogUsadoPct -ge 90 }).Count
    if ($cantidadLogsCriticos -gt 0) { $deduccion += [math]::Min(14, 4 + [math]::Ceiling(10 * $cantidadLogsCriticos / $totalEmpresas)) }
    $cantidadLogsAtencion = @($basesEvaluadas | Where-Object { $_.LogUsadoPct -ge 80 -and $_.LogUsadoPct -lt 90 }).Count
    if ($cantidadLogsAtencion -gt 0) { $deduccion += [math]::Min(4, [math]::Ceiling(4 * $cantidadLogsAtencion / $totalEmpresas)) }
    $cantidadSinChecksum = @($basesEvaluadas | Where-Object { $_.VerificacionPagina -ne 'CHECKSUM' }).Count
    if ($cantidadSinChecksum -gt 0) { $deduccion += [math]::Min(8, 2 + [math]::Ceiling(6 * $cantidadSinChecksum / $totalEmpresas)) }
    if ($respaldosDisponibles) {
        $ahoraPuntaje = Get-Date
        $cantidadRespaldoRiesgo = @($basesEvaluadas | Where-Object { -not $_.UltimoRespaldo -or ($ahoraPuntaje - [datetime]$_.UltimoRespaldo).TotalDays -gt 7 }).Count
        if ($cantidadRespaldoRiesgo -gt 0) { $deduccion += [math]::Min(15, 3 + [math]::Ceiling(12 * $cantidadRespaldoRiesgo / $totalEmpresas)) }
    }
    if ($resultadoActividad.Correcto -and [int]$actividad.SolicitudesBloqueadas -gt 0) {
        $deduccion += [math]::Min(12, 5 + [int]$actividad.SolicitudesBloqueadas)
    }
    $volumenCritico = @($volumenes | Where-Object { [double]$_.LibrePct -lt 10 -or [double]$_.LibreGB -lt 5 }).Count
    $volumenAtencion = @($volumenes | Where-Object { ([double]$_.LibrePct -ge 10 -and [double]$_.LibrePct -lt 20) -or ([double]$_.LibreGB -ge 5 -and [double]$_.LibreGB -lt 15) }).Count
    if ($volumenCritico -gt 0) { $deduccion += 15 } elseif ($volumenAtencion -gt 0) { $deduccion += 6 }
    $auxiliaresCriticas = @($basesAuxiliaresPuntaje | Where-Object { $_.Estado -ne 'ONLINE' -or $_.UsoDatosPct -ge 95 -or $_.LogUsadoPct -ge 95 }).Count
    if ($auxiliaresCriticas -gt 0) { $deduccion += [math]::Min(8, 2 + [math]::Ceiling(6 * $auxiliaresCriticas / [math]::Max(1, $basesAuxiliaresPuntaje.Count))) }

    $puntaje = [int][math]::Max(0, 100 - [math]::Min(100, $deduccion))
    $nivelPuntaje = if ($puntaje -ge 85) { 'OK' } elseif ($puntaje -ge 65) { 'WARN' } else { 'ERROR' }
    $empresasPorRevisar = @($basesPrincipalesPuntaje | Where-Object { $_.Salud -ne 'SALUDABLE' }).Count
    Write-Log -Mensaje "Salud general: $puntaje/100 | Empresas: $($basesPrincipalesPuntaje.Count) | Auxiliares: $($basesAuxiliaresPuntaje.Count) | Por revisar: $empresasPorRevisar" -Nivel $nivelPuntaje
    $empresasParaBitacora = if ($Script:GUIForm -and -not $Script:ConsoleMode) { @($basesPrincipalesPuntaje | Sort-Object DatosAsignadosMB -Descending | Select-Object -First 30) } else { @($empresas | Sort-Object DatosAsignadosMB -Descending) }
    foreach ($empresa in $empresasParaBitacora) {
        Write-Log -Mensaje ("{0}: {1:N2} GB usados de {2:N2} GB | Datos {3:N1}% | Log {4:N1}% | {5}" -f $empresa.Nombre, ($empresa.DatosUsadosMB / 1024), ($empresa.DatosAsignadosMB / 1024), $empresa.UsoDatosPct, $empresa.LogUsadoPct, $empresa.Salud) -Nivel $(if ($empresa.Salud -eq 'CRITICA') { 'ERROR' } elseif ($empresa.Salud -eq 'ATENCION') { 'WARN' } else { 'OK' })
    }
    foreach ($alerta in @($alertas | Select-Object -First 15)) {
        Write-Log -Mensaje $alerta.Mensaje -Nivel $(if ($alerta.Nivel -eq 'CRITICA') { 'ERROR' } elseif ($alerta.Nivel -eq 'ATENCION') { 'WARN' } else { 'INFO' })
    }

    if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        Show-SaludSQLDashboard -Instancia $instancia -Servidor $servidor -Empresas @($empresas) -Alertas @($alertas) -Volumenes @($volumenes) -Actividad $actividad -Puntaje $puntaje -RespaldosDisponibles $respaldosDisponibles
    }
}

function Invoke-MantenimientoSQLProfesional {
    Write-Encabezado -Titulo 'MANTENIMIENTO SQL PROFESIONAL' -Subtitulo 'Respaldo, integridad, indices y estadisticas' -Color 'Green'
    $motores = @(Get-ServiciosMotorSQL)
    if ($motores.Count -eq 0) {
        Write-Log -Mensaje 'No se detectaron instancias reales del motor SQL Server.' -Nivel ERROR
        return
    }

    $opcionesInstancia = @($motores | ForEach-Object {
        $nombreInstancia = Get-NombreInstanciaSQL -NombreServicio $_.Name
        "$nombreInstancia  |  $($_.Status)  |  $($_.DisplayName)"
    })
    $indiceInstancia = if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        Show-GUIChoice -Titulo 'Instancia SQL' -Mensaje 'Selecciona la instancia que contiene la empresa:' -Opciones $opcionesInstancia
    } else {
        for ($i = 0; $i -lt $opcionesInstancia.Count; $i++) { Write-OpcionMenu -Tecla ($i + 1) -Descripcion $opcionesInstancia[$i] }
        ([int](Read-Host ' Selecciona instancia')) - 1
    }
    if ($indiceInstancia -lt 0 -or $indiceInstancia -ge $motores.Count) {
        Write-Log -Mensaje 'Mantenimiento cancelado.' -Nivel INFO
        return
    }
    $motor = $motores[$indiceInstancia]
    $instancia = Get-NombreInstanciaSQL -NombreServicio $motor.Name
    if ($motor.Status -ne 'Running') {
        Write-Log -Mensaje "$instancia esta detenida." -Nivel WARN
        if (-not (Confirmar-Movimiento -Frase 'INICIAR SQL' -Accion "Iniciar el motor SQL $instancia" `
            -Detalle 'Se cambiara el estado del servicio de SQL Server seleccionado.')) { return }
        $resultadoMotor = Invoke-ServiceActionResponsive -Nombre $motor.Name -Accion Start -TimeoutSegundos 90
        if ($resultadoMotor.Correcto) {
            Write-Log -Mensaje "$instancia iniciada correctamente." -Nivel OK
        } else {
            Write-Log -Mensaje "No se pudo iniciar $($instancia): $($resultadoMotor.Error)" -Nivel ERROR
            return
        }
    }

    $conexion = Test-ConexionSQLLocal -Instancia $instancia -TimeoutSegundos 8
    if (-not $conexion.Correcto) {
        Write-Log -Mensaje "No fue posible acceder a $($instancia): $($conexion.Error)" -Nivel ERROR
        return
    }
    Write-Log -Mensaje "Conexion correcta: $($conexion.Servidor) | SQL $($conexion.Version)" -Nivel OK

    try {
        $bases = @(Get-InventarioBasesSQL -Instancia $instancia)
    } catch {
        Write-Log -Mensaje "No se pudo consultar el inventario de bases: $($_.Exception.Message)" -Nivel ERROR
        return
    }
    if ($bases.Count -eq 0) {
        Write-Log -Mensaje 'La instancia no contiene bases de datos de usuario.' -Nivel WARN
        return
    }

    Write-SeccionMenu -Titulo 'BASES DE DATOS DETECTADAS' -Color 'Cyan'
    $opcionesBase = @()
    foreach ($base in $bases) {
        $ultimo = if ($base.UltimoRespaldoCompleto -and $base.UltimoRespaldoCompleto -ne [DBNull]::Value) {
            ([datetime]$base.UltimoRespaldoCompleto).ToString('dd/MM/yyyy HH:mm')
        } else { 'Sin registro' }
        $texto = "$($base.Nombre) | $($base.Estado) | $($base.TamanoMB) MB | Ultimo respaldo: $ultimo"
        $opcionesBase += $texto
        Write-Log -Mensaje $texto -Nivel $(if ($base.Estado -eq 'ONLINE') { 'INFO' } else { 'WARN' })
    }
    $indiceBase = if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        Show-GUIChoice -Titulo 'Empresa / base de datos' -Mensaje 'Selecciona exactamente la base que deseas revisar:' -Opciones $opcionesBase
    } else {
        for ($i = 0; $i -lt $opcionesBase.Count; $i++) { Write-OpcionMenu -Tecla ($i + 1) -Descripcion $opcionesBase[$i] }
        ([int](Read-Host ' Selecciona base')) - 1
    }
    if ($indiceBase -lt 0 -or $indiceBase -ge $bases.Count) {
        Write-Log -Mensaje 'Mantenimiento cancelado.' -Nivel INFO
        return
    }
    $baseSeleccionada = $bases[$indiceBase]
    $baseDatos = [string]$baseSeleccionada.Nombre
    if ($baseSeleccionada.Estado -ne 'ONLINE') {
        Write-Log -Mensaje "$baseDatos esta en estado $($baseSeleccionada.Estado). No se realizaran operaciones." -Nivel ERROR
        return
    }

    $modos = @(
        'Diagnostico rapido — DBCC CHECKDB PHYSICAL_ONLY, sin cambios',
        'Respaldo verificado — COPY_ONLY + CHECKSUM + VERIFYONLY',
        'Mantenimiento preventivo — respaldo + integridad + indices + estadisticas',
        'Integridad completa — DBCC CHECKDB completo, sin reparar'
    )
    $modo = if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        Show-GUIChoice -Titulo "Mantenimiento de $baseDatos" -Mensaje 'Selecciona el nivel de intervencion:' -Opciones $modos
    } else {
        for ($i = 0; $i -lt $modos.Count; $i++) { Write-OpcionMenu -Tecla ($i + 1) -Descripcion $modos[$i] }
        ([int](Read-Host ' Selecciona nivel')) - 1
    }
    if ($modo -lt 0 -or $modo -ge $modos.Count) {
        Write-Log -Mensaje 'Nivel de mantenimiento no valido; operacion cancelada.' -Nivel WARN
        return
    }

    Write-Encabezado -Titulo 'MANTENIMIENTO SQL' -Subtitulo "$instancia | $baseDatos" -Color 'Green'
    Write-Log -Mensaje "Estado: $($baseSeleccionada.Estado) | Tamaño: $($baseSeleccionada.TamanoMB) MB | Recuperacion: $($baseSeleccionada.Recuperacion) | PAGE_VERIFY: $($baseSeleccionada.VerificacionPagina)" -Nivel INFO
    if ($baseSeleccionada.VerificacionPagina -ne 'CHECKSUM') {
        Write-Log -Mensaje 'PAGE_VERIFY no esta configurado como CHECKSUM. Se recomienda revisarlo con el responsable de la base antes de cambiarlo.' -Nivel WARN
    }

    switch ($modo) {
        0 {
            $integridad = Invoke-IntegridadBaseSQL -Instancia $instancia -BaseDatos $baseDatos
            Write-ResultadoIntegridadSQL -Resultado $integridad -BaseDatos $baseDatos
        }
        1 {
            if (-not (Confirmar-Movimiento -Frase 'RESPALDAR' -Accion "Crear respaldo COPY_ONLY de '$baseDatos'" `
                -Detalle 'Se escribira un archivo BAK y se verificara con RESTORE VERIFYONLY. No se modificaran los datos.')) { return }
            $respaldo = Invoke-RespaldoSQLVerificado -Instancia $instancia -BaseDatos $baseDatos
            if ($respaldo.Correcto) {
                $tamanoTexto = if ($respaldo.TamanoMB -gt 0) { " | $($respaldo.TamanoMB) MB" } else { '' }
                Write-Log -Mensaje "Respaldo verificado correctamente en $($respaldo.DuracionSegundos) segundos${tamanoTexto}: $($respaldo.Ruta)" -Nivel OK
            } else {
                Write-Log -Mensaje "El respaldo no pudo verificarse: $($respaldo.Error)" -Nivel ERROR
            }
        }
        2 {
            if ([bool]$baseSeleccionada.SoloLectura) {
                Write-Log -Mensaje "$baseDatos es de solo lectura; mantenimiento cancelado." -Nivel ERROR
                return
            }
            try {
                $sesionesPrevias = @(Get-SesionesActivasBaseSQL -Instancia $instancia -BaseDatos $baseDatos)
                if ($sesionesPrevias.Count -gt 0) {
                    Write-Log -Mensaje "$($sesionesPrevias.Count) sesion(es) de usuario estan usando $baseDatos." -Nivel WARN
                    foreach ($sesion in @($sesionesPrevias | Select-Object -First 8)) {
                        Write-Log -Mensaje "Sesion $($sesion.IdSesion) | $($sesion.Equipo) | $($sesion.Usuario) | $($sesion.Programa)" -Nivel INFO
                    }
                }
            } catch {
                Write-Log -Mensaje "No se pudo obtener la lista de sesiones activas: $($_.Exception.Message)" -Nivel WARN
            }
            Write-Log -Mensaje 'El mantenimiento cerrara procesos CONTPAQi locales y puede bloquear tablas durante reconstrucciones.' -Nivel WARN
            if (-not (Confirmar-Movimiento -Frase 'MANTENER' -Accion "Ejecutar mantenimiento preventivo en '$baseDatos'" `
                -Detalle 'Se creara y verificara un respaldo; despues se cerraran procesos locales, se mantendran indices y se actualizaran estadisticas.')) { return }

            $respaldo = Invoke-RespaldoSQLVerificado -Instancia $instancia -BaseDatos $baseDatos
            if (-not $respaldo.Correcto) {
                Write-Log -Mensaje "No se realizara mantenimiento porque el respaldo fallo: $($respaldo.Error)" -Nivel ERROR
                return
            }
            Write-Log -Mensaje "Respaldo verificado: $($respaldo.Ruta)" -Nivel OK

            $integridadInicial = Invoke-IntegridadBaseSQL -Instancia $instancia -BaseDatos $baseDatos
            Write-ResultadoIntegridadSQL -Resultado $integridadInicial -BaseDatos $baseDatos
            if (-not $integridadInicial.Saludable) {
                Write-Log -Mensaje 'Mantenimiento detenido: no se modificaran indices mientras existan alertas de integridad.' -Nivel ERROR
                return
            }

            $procesos = @(
                @((Get-ProcesosCONTPAQi) + (Get-ProcesosPID)) |
                    Where-Object { -not $_.EsToolbox } |
                    Sort-Object PID -Unique
            )
            if ($procesos.Count -gt 0) {
                Write-Log -Mensaje "Cerrando $($procesos.Count) proceso(s) CONTPAQi antes de mantener indices..." -Nivel WARN
                foreach ($proceso in $procesos) {
                    if (-not (Stop-ProcesoForzado -ProcessId $proceso.PID)) {
                        Write-Log -Mensaje "No se pudo cerrar $($proceso.Nombre) PID $($proceso.PID)." -Nivel WARN
                    }
                }
            }

            Wait-Responsive -Seconds 2
            try {
                $sesionesRestantes = @(Get-SesionesActivasBaseSQL -Instancia $instancia -BaseDatos $baseDatos)
                if ($sesionesRestantes.Count -gt 0) {
                    Write-Log -Mensaje "Mantenimiento detenido: aun existen $($sesionesRestantes.Count) sesion(es) usando $baseDatos." -Nivel ERROR
                    Write-Log -Mensaje 'Cierra los sistemas en las terminales y vuelve a ejecutar. El Toolbox no elimina sesiones SQL ni transacciones por la fuerza.' -Nivel INFO
                    return
                }
            } catch {
                Write-Log -Mensaje 'No fue posible confirmar que la base quedo sin usuarios; se cancela el mantenimiento por seguridad.' -Nivel ERROR
                return
            }

            $resultadoIndices = Invoke-MantenimientoIndicesSQL -Instancia $instancia -BaseDatos $baseDatos
            Write-Log -Mensaje "Indices: $($resultadoIndices.Correctos) correctos, $($resultadoIndices.Fallidos) fallidos de $($resultadoIndices.Total)." -Nivel $(if ($resultadoIndices.Fallidos -eq 0) { 'OK' } else { 'WARN' })
            Write-Log -Mensaje "Estadisticas: $(if ($resultadoIndices.EstadisticasCorrectas) { 'actualizadas' } else { 'con incidencia' })." -Nivel $(if ($resultadoIndices.EstadisticasCorrectas) { 'OK' } else { 'WARN' })

            $integridadFinal = Invoke-IntegridadBaseSQL -Instancia $instancia -BaseDatos $baseDatos
            Write-ResultadoIntegridadSQL -Resultado $integridadFinal -BaseDatos $baseDatos
            if ($integridadFinal.Saludable -and $resultadoIndices.Fallidos -eq 0 -and $resultadoIndices.EstadisticasCorrectas) {
                Write-Log -Mensaje 'MANTENIMIENTO COMPLETADO: respaldo verificado, integridad correcta, indices y estadisticas actualizados.' -Nivel OK
            } else {
                Write-Log -Mensaje 'Mantenimiento finalizado con incidencias. Revisa la bitacora antes de abrir la empresa.' -Nivel WARN
            }
        }
        3 {
            Write-Log -Mensaje 'La revision completa puede tardar bastante en bases grandes, pero no modifica datos.' -Nivel WARN
            if (-not (Confirmar-Accion -Mensaje "Ejecutar DBCC CHECKDB completo en '$baseDatos'")) { return }
            $integridad = Invoke-IntegridadBaseSQL -Instancia $instancia -BaseDatos $baseDatos -Completa
            Write-ResultadoIntegridadSQL -Resultado $integridad -BaseDatos $baseDatos
        }
    }
}

function Ejecutar-SuperReset {
    Write-Encabezado -Titulo 'REPARACION TOTAL DEL SERVIDOR' -Subtitulo 'Recuperacion integral CONTPAQi + Windows + Red + SQL' -Color $Script:ColorServidor
    Write-Log -Mensaje 'Esta intervencion es superior a Reparacion Profunda: tambien repara Winsock, servicios base de Windows, hora, MSMQ y audita binarios.' -Nivel WARN
    if (-not (Confirmar-Movimiento -Frase 'REPARAR SERVIDOR' `
        -Accion 'Ejecutar reparacion TOTAL del servidor' `
        -Detalle 'Se cerraran aplicaciones, reiniciaran CONTPAQi/SQL, repararan DNS-Winsock y componentes de Windows con DISM/SFC. Guarda todo el trabajo; puede tardar y requerir reinicio.')) { return }

    $inicio = Get-Date
    $incidencias = 0
    $requiereReinicioRed = $false
    $proteccionServicesDev = Suspend-ServicesDevForRepair
    if (-not $proteccionServicesDev.Correcto) { return }
    try {
        Write-Log -Mensaje '[1/14] Inventario y comprobaciones previas...' -Nivel PROGRESS
        $serviciosApp = @(Get-ServiciosAplicacionCONTPAQi | Sort-Object `
            @{ Expression = { Get-OrdenInicioServicioCONTPAQi -Servicio $_ } }, Name)
        $serviciosSql = @(Get-ServiciosSQLRelacionados)
        $procesos = @((Get-ProcesosCONTPAQi) + (Get-ProcesosPID)) |
            Where-Object { -not $_.EsToolbox } | Sort-Object PID -Unique
        Write-Log -Mensaje "Detectados: $($serviciosApp.Count) servicios CONTPAQi | $($serviciosSql.Count) SQL | $($procesos.Count) procesos." -Nivel INFO
        $unidadSistema = Get-PSDrive -Name $env:SystemDrive.TrimEnd(':') -ErrorAction SilentlyContinue
        if ($unidadSistema) {
            $libreGB = [math]::Round($unidadSistema.Free / 1GB, 1)
            Write-Log -Mensaje "Espacio libre en $env:SystemDrive $libreGB GB." -Nivel $(if ($libreGB -ge 10) { 'OK' } else { 'WARN' })
            if ($libreGB -lt 2) { $incidencias++ }
        }
        if (Test-ReinicioPendiente) { Write-Log -Mensaje 'Windows ya tenia un reinicio pendiente antes de iniciar.' -Nivel WARN }

        Write-Log -Mensaje '[2/14] Cerrando procesos CONTPAQi/PID de todas las sesiones...' -Nivel PROGRESS
        foreach ($proceso in $procesos) {
            if (Stop-ProcesoForzado -ProcessId $proceso.PID -TimeoutSegundos 10) {
                Write-Log -Mensaje "PID $($proceso.PID) ($($proceso.Nombre)) cerrado." -Nivel OK
            } else {
                $incidencias++
                Write-Log -Mensaje "No fue posible cerrar PID $($proceso.PID) ($($proceso.Nombre))." -Nivel ERROR
            }
        }

        Write-Log -Mensaje '[3/14] Deteniendo todos los servicios CONTPAQi...' -Nivel PROGRESS
        $serviciosStop = @($serviciosApp)
        [array]::Reverse($serviciosStop)
        foreach ($servicio in $serviciosStop) {
            $actual = Get-Service -Name $servicio.Name -ErrorAction SilentlyContinue
            if ($actual -and $actual.Status -ne 'Stopped') {
                $resultado = Invoke-ServiceActionResponsive -Nombre $actual.Name -Accion Stop -TimeoutSegundos 75
                if ($resultado.Correcto) { Write-Log -Mensaje "$($actual.Name) detenido." -Nivel OK }
                else { $incidencias++; Write-Log -Mensaje "No se pudo detener $($actual.Name): $($resultado.Error)" -Nivel ERROR }
            }
        }

        Write-Log -Mensaje '[4/14] Deteniendo motores y componentes SQL...' -Nivel PROGRESS
        $sqlStopOrder = @($serviciosSql | Sort-Object { if ($_ -eq 'SQLBrowser') { 0 } else { 1 } })
        foreach ($nombre in $sqlStopOrder) {
            $actual = Get-Service -Name $nombre -ErrorAction SilentlyContinue
            if ($actual -and $actual.Status -ne 'Stopped') {
                $resultado = Invoke-ServiceActionResponsive -Nombre $nombre -Accion Stop -TimeoutSegundos 120
                if ($resultado.Correcto) { Write-Log -Mensaje "SQL $nombre detenido." -Nivel OK }
                else { $incidencias++; Write-Log -Mensaje "No se pudo detener SQL $($nombre): $($resultado.Error)" -Nivel ERROR }
            }
        }

        Write-Log -Mensaje '[5/14] Limpieza ampliada de temporales seguros...' -Nivel PROGRESS
        $eliminados = 0
        $rutasTemporales = @(
            $env:TEMP,
            (Join-Path $env:LOCALAPPDATA 'Temp\Compac'),
            (Join-Path $env:LOCALAPPDATA 'Temp\CONTPAQi'),
            'C:\Windows\Temp',
            'C:\Windows\Temp\Compac',
            'C:\Windows\Temp\CONTPAQi'
        ) | Select-Object -Unique
        foreach ($ruta in $rutasTemporales) { $eliminados += Clear-TemporalSeguro -Ruta $ruta }
        Write-Log -Mensaje "Limpieza ampliada finalizada: $eliminados elemento(s) eliminados; archivos en uso conservados." -Nivel OK

        Write-Log -Mensaje '[6/14] Reparando DNS y catalogo Winsock...' -Nivel PROGRESS
        $dns = Invoke-DnsFlushResponsive
        if ($dns.Correcto) { Write-Log -Mensaje 'Cache DNS renovada.' -Nivel OK }
        else { $incidencias++; Write-Log -Mensaje "No se pudo limpiar DNS: $($dns.Error)" -Nivel ERROR }
        $winsock = Invoke-ProcessResponsive -FilePath 'netsh.exe' -ArgumentList 'winsock reset' `
            -TimeoutSeconds 120 -Activity 'Restableciendo Winsock' -Hidden
        if ($winsock.Correcto -and $winsock.ExitCode -eq 0) {
            $requiereReinicioRed = $true
            Write-Log -Mensaje 'Catalogo Winsock restablecido. Windows debera reiniciarse al terminar.' -Nivel OK
        } else {
            $incidencias++
            Write-Log -Mensaje "Winsock no pudo restablecerse: $($winsock.Error) (codigo $($winsock.ExitCode))." -Nivel ERROR
        }

        Write-Log -Mensaje '[7/14] Recuperando dependencias de Windows y CONTPAQi...' -Nivel PROGRESS
        $dependencias = @('RpcSs', 'DcomLaunch', 'RpcEptMapper', 'Dnscache', 'LanmanWorkstation', 'W32Time', 'MSMQ')
        foreach ($nombre in $dependencias) {
            $servicio = Get-Service -Name $nombre -ErrorAction SilentlyContinue
            if (-not $servicio) {
                if ($nombre -eq 'MSMQ') { Write-Log -Mensaje 'MSMQ no esta instalado; valida si los productos CONTPAQi de este servidor lo requieren.' -Nivel WARN }
                continue
            }
            if (Test-ServicioDeshabilitado -Nombre $nombre) {
                Write-Log -Mensaje "$nombre esta deshabilitado; no se cambio su configuracion." -Nivel WARN
                if ($nombre -in @('RpcSs', 'DcomLaunch', 'RpcEptMapper')) { $incidencias++ }
                continue
            }
            if ($servicio.Status -ne 'Running') {
                $resultado = Invoke-ServiceActionResponsive -Nombre $nombre -Accion Start -TimeoutSegundos 75
                if (-not $resultado.Correcto) { $incidencias++; Write-Log -Mensaje "No se pudo iniciar dependencia $($nombre): $($resultado.Error)" -Nivel ERROR; continue }
            }
            Write-Log -Mensaje "Dependencia $nombre activa." -Nivel OK
        }

        Write-Log -Mensaje '[8/14] Iniciando SQL con reintentos y orden de dependencias...' -Nivel PROGRESS
        $sqlStartOrder = @($serviciosSql | Sort-Object { if ($_ -like 'MSSQL*') { 0 } elseif ($_ -eq 'SQLBrowser') { 1 } else { 2 } })
        foreach ($nombre in $sqlStartOrder) {
            if (Test-ServicioDeshabilitado -Nombre $nombre) {
                Write-Log -Mensaje "SQL $nombre esta deshabilitado; se conserva su configuracion." -Nivel WARN
                if ($nombre -like 'MSSQL*') { $incidencias++ }
                continue
            }
            $iniciado = $false
            $ultimoError = ''
            for ($intento = 1; $intento -le 2 -and -not $iniciado; $intento++) {
                $resultado = Invoke-ServiceActionResponsive -Nombre $nombre -Accion Start -TimeoutSegundos 150
                $iniciado = $resultado.Correcto
                $ultimoError = $resultado.Error
                if (-not $iniciado -and $intento -lt 2) { Write-Log -Mensaje "SQL $nombre no inicio; segundo intento en 2 segundos." -Nivel WARN; Wait-Responsive -Seconds 2 }
            }
            if ($iniciado) { Write-Log -Mensaje "SQL $nombre activo y verificado." -Nivel OK }
            else { $incidencias++; Write-Log -Mensaje "No se pudo iniciar SQL $($nombre): $ultimoError" -Nivel ERROR }
        }

        Write-Log -Mensaje '[9/14] Validando conectividad y respuesta de SQL...' -Nivel PROGRESS
        foreach ($motor in @(Get-ServiciosMotorSQL)) {
            $instancia = Get-NombreInstanciaSQL -NombreServicio $motor.Name
            if ($motor.Status -ne 'Running') { $incidencias++; Write-Log -Mensaje "$instancia permanece detenido." -Nivel ERROR; continue }
            $prueba = Test-ConexionSQLLocal -Instancia $instancia -TimeoutSegundos 8
            if ($prueba.Correcto) { Write-Log -Mensaje "$instancia responde correctamente | SQL $($prueba.Version)." -Nivel OK }
            else { $incidencias++; Write-Log -Mensaje "$instancia no acepta conexion integrada: $($prueba.Error)" -Nivel ERROR }
        }

        Write-Log -Mensaje '[10/14] Iniciando y auditando todos los servicios CONTPAQi...' -Nivel PROGRESS
        $resultadoApp = Start-TodosServiciosCONTPAQiVerificado -Intentos 2
        $incidencias += $resultadoApp.Fallidos
        Write-Log -Mensaje "CONTPAQi: $($resultadoApp.Correctos) activos, $($resultadoApp.Fallidos) con incidencia, $($resultadoApp.Omitidos) deshabilitados de $($resultadoApp.Total)." -Nivel $(if ($resultadoApp.Fallidos -eq 0) { 'OK' } else { 'WARN' })

        Write-Log -Mensaje '[11/14] Reparando la imagen de componentes de Windows (DISM)...' -Nivel PROGRESS
        Write-Log -Mensaje 'DISM RestoreHealth puede tardar bastante; la interfaz permanecera activa y mostrara el tiempo transcurrido.' -Nivel INFO
        $dism = Invoke-ProcessResponsive -FilePath 'dism.exe' `
            -ArgumentList '/Online /Cleanup-Image /RestoreHealth /NoRestart /English' `
            -TimeoutSeconds 5400 -Activity 'Reparando imagen de Windows con DISM' -Hidden
        if ($dism.Correcto -and $dism.ExitCode -in @(0, 3010)) {
            Write-Log -Mensaje "DISM RestoreHealth finalizo correctamente (codigo $($dism.ExitCode))." -Nivel OK
            if ($dism.ExitCode -eq 3010) { $requiereReinicioRed = $true }
        } else {
            $incidencias++
            Write-Log -Mensaje "DISM RestoreHealth fallo o excedio el tiempo: $($dism.Error) (codigo $($dism.ExitCode))." -Nivel ERROR
        }

        Write-Log -Mensaje '[12/14] Reparando archivos protegidos de Windows (SFC)...' -Nivel PROGRESS
        $sfc = Invoke-ProcessResponsive -FilePath 'sfc.exe' -ArgumentList '/scannow' `
            -TimeoutSeconds 5400 -Activity 'Reparando archivos de Windows con SFC' -Hidden
        if ($sfc.Correcto -and $sfc.ExitCode -eq 0) {
            Write-Log -Mensaje 'SFC /scannow finalizo correctamente.' -Nivel OK
        } else {
            $incidencias++
            Write-Log -Mensaje "SFC no finalizo correctamente: $($sfc.Error) (codigo $($sfc.ExitCode))." -Nivel ERROR
        }

        Write-Log -Mensaje '[13/14] Sincronizando hora y auditando ejecutables/estado final...' -Nivel PROGRESS
        $hora = Get-Service -Name 'W32Time' -ErrorAction SilentlyContinue
        if ($hora -and $hora.Status -eq 'Running') {
            $resync = Invoke-ProcessResponsive -FilePath 'w32tm.exe' -ArgumentList '/resync /nowait' `
                -TimeoutSeconds 30 -Activity 'Sincronizando hora de Windows' -Hidden
            Write-Log -Mensaje $(if ($resync.Correcto -and $resync.ExitCode -eq 0) { 'Solicitud de sincronizacion de hora enviada.' } else { 'No fue posible resincronizar la hora; revisa el origen NTP/dominio.' }) `
                -Nivel $(if ($resync.Correcto -and $resync.ExitCode -eq 0) { 'OK' } else { 'WARN' })
        }
        foreach ($servicio in @(Get-ServiciosAplicacionCONTPAQi)) {
            try {
                $nombreSeguro = $servicio.Name.Replace("'", "''")
                $cim = Get-CimInstance Win32_Service -Filter "Name='$nombreSeguro'" -ErrorAction Stop
                $rutaExe = Get-RutaEjecutableServicio -Comando $cim.PathName
                if ($rutaExe -and -not (Test-Path -LiteralPath $rutaExe -PathType Leaf)) {
                    $incidencias++
                    Write-Log -Mensaje "$($servicio.Name): ejecutable ausente en $rutaExe." -Nivel ERROR
                }
            } catch { Write-Log -Mensaje "$($servicio.Name): no se pudo auditar la ruta binaria." -Nivel WARN }
        }
        $detenidosFinales = @(Get-ServiciosAplicacionCONTPAQi | Where-Object {
            -not (Test-ServicioDeshabilitado -Nombre $_.Name) -and $_.Status -ne 'Running'
        })
        if ($detenidosFinales.Count -gt 0) {
            $incidencias += $detenidosFinales.Count
            Write-Log -Mensaje "Servicios que no quedaron activos: $($detenidosFinales.Name -join ', ')." -Nivel ERROR
        } else { Write-Log -Mensaje 'Auditoria final: todos los servicios CONTPAQi habilitados estan activos.' -Nivel OK }

    } catch {
        $incidencias++
        Write-Log -Mensaje "Error inesperado durante la reparacion total: $($_.Exception.Message)" -Nivel ERROR
    } finally {
        Write-Log -Mensaje '[14/14] Restaurando el monitor ServicesDev...' -Nivel PROGRESS
        if (-not (Restore-ServicesDevAfterRepair -Estados $proteccionServicesDev.Estados)) { $incidencias++ }
    }

    $duracion = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    Write-Host ''
    $colorFinal = if ($incidencias -eq 0) { $Script:ColorExito } else { $Script:ColorAdvertencia }
    Write-Separador -Color $colorFinal
    if ($incidencias -eq 0) {
        Write-Linea -Texto ' REPARACION TOTAL DEL SERVIDOR COMPLETADA Y VERIFICADA' -Color $colorFinal -Centrado
        Write-Log -Mensaje "Servidor recuperado en $duracion segundos sin incidencias detectadas." -Nivel OK
    } else {
        Write-Linea -Texto " REPARACION TOTAL FINALIZADA CON $incidencias INCIDENCIA(S)" -Color $colorFinal -Centrado
        Write-Log -Mensaje "Intervencion terminada en $duracion segundos. Revisa las incidencias anteriores antes de liberar el servidor." -Nivel WARN
    }
    if ($requiereReinicioRed) { Write-Log -Mensaje 'REINICIO REQUERIDO: reinicia Windows para completar el restablecimiento de Winsock y vuelve a ejecutar el diagnostico.' -Nivel WARN }
}

function Clear-TemporalSeguro {
    param([Parameter(Mandatory)][string]$Ruta)

    if ([string]::IsNullOrWhiteSpace($Ruta) -or -not (Test-Path -LiteralPath $Ruta -PathType Container)) {
        return 0
    }

    $rutaCompleta = [System.IO.Path]::GetFullPath($Ruta).TrimEnd('\')
    $raicesPermitidas = @(
        [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\'),
        [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Temp')).TrimEnd('\'),
        [System.IO.Path]::GetFullPath('C:\Windows\Temp').TrimEnd('\')
    ) | Select-Object -Unique

    $permitida = $false
    foreach ($raiz in $raicesPermitidas) {
        if ($rutaCompleta -ieq $raiz -or $rutaCompleta.StartsWith($raiz + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $permitida = $true
            break
        }
    }
    if (-not $permitida) {
        Write-Log -Mensaje "Limpieza omitida por seguridad: $rutaCompleta" -Nivel WARN
        return 0
    }

    $rutaProtegidaToolbox = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP 'CONTPAQiToolbox')).TrimEnd('\')
    $codigoLimpieza = @'
param([string]$Directorio, [string]$RutaProtegida)
$eliminados = 0
$omitidos = 0
$protegidos = 0
foreach ($elemento in @(Get-ChildItem -LiteralPath $Directorio -Force -ErrorAction SilentlyContinue)) {
    $elementoCompleto = [IO.Path]::GetFullPath($elemento.FullName).TrimEnd('\')
    if ($elementoCompleto -ieq $RutaProtegida -or $RutaProtegida.StartsWith($elementoCompleto + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $protegidos++
        continue
    }
    try {
        Remove-Item -LiteralPath $elemento.FullName -Recurse -Force -ErrorAction Stop
        $eliminados++
    } catch {
        # Los archivos en uso se conservan; no deben cancelar el resto de la reparacion.
        $omitidos++
    }
}
[PSCustomObject]@{ Eliminados = $eliminados; Omitidos = $omitidos; Protegidos = $protegidos }
'@
    $resultadoWorker = Invoke-ResponsiveWorker -ScriptText $codigoLimpieza -Arguments @($rutaCompleta, $rutaProtegidaToolbox) `
        -TimeoutSeconds 1800 -Activity "Limpiando $([IO.Path]::GetFileName($rutaCompleta))"
    if (-not $resultadoWorker.Correcto -or $resultadoWorker.Timeout -or -not $resultadoWorker.Resultado) {
        Write-Log -Mensaje "No se completo la limpieza de ${rutaCompleta}: $($resultadoWorker.Error)" -Nivel WARN
        return 0
    }

    $resultado = $resultadoWorker.Resultado
    if ($resultado.Omitidos -gt 0) {
        Write-Log -Mensaje "${rutaCompleta}: $($resultado.Omitidos) elemento(s) en uso se conservaron." -Nivel INFO
    }
    if ($resultado.Protegidos -gt 0) {
        Write-Log -Mensaje "${rutaCompleta}: se conservaron los recursos temporales activos del Toolbox." -Nivel INFO
    }
    return [int]$resultado.Eliminados
}

function Test-ReinicioPendiente {
    $rutas = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($ruta in $rutas) {
        if (Test-Path -LiteralPath $ruta) { return $true }
    }
    try {
        $valor = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
        return ($null -ne $valor)
    } catch { return $false }
}

function Invoke-ReparacionProfundaCONTPAQi {
    Write-Encabezado -Titulo 'REPARACION PROFUNDA CONTPAQi' -Subtitulo 'Procesos + Servicios + SQL + Temporales + Red' -Color 'Red'

    if (-not (Confirmar-Movimiento -Frase 'REPARAR' -Accion 'Ejecutar reparacion profunda CONTPAQi' `
        -Detalle 'Se cerraran aplicaciones, se reiniciaran servicios y SQL, y se limpiaran temporales y cache DNS. Guarda cualquier trabajo abierto.')) { return }

    $inicio = Get-Date
    $errores = 0
    $proteccionServicesDev = Suspend-ServicesDevForRepair
    if (-not $proteccionServicesDev.Correcto) { return }
    try {
    Write-Log -Mensaje 'Iniciando reparacion profunda. No se eliminaran empresas ni bases de datos.' -Nivel WARN

    Write-Log -Mensaje '[1/8] Registrando estado inicial...' -Nivel PROGRESS
    # Inventario dinamico: incluye servicios CONTPAQi de cualquier version
    # instalada, no solamente los nombres conocidos al abrir la herramienta.
    $serviciosAppObjetos = @(Get-ServiciosAplicacionCONTPAQi | Sort-Object `
        @{ Expression = { Get-OrdenInicioServicioCONTPAQi -Servicio $_ } }, Name)
    $serviciosApp = @($serviciosAppObjetos | Select-Object -ExpandProperty Name -Unique)
    # Refrescar el inventario: la herramienta puede permanecer abierta mientras
    # se instalan o modifican instancias.
    $serviciosSqlDetectados = @(Get-ServiciosSQLRelacionados)
    Write-Log -Mensaje "Servicios de aplicacion detectados: $($serviciosApp.Count) | SQL: $($serviciosSqlDetectados.Count)" -Nivel INFO

    Write-Log -Mensaje '[2/8] Deteniendo servicios de aplicacion...' -Nivel PROGRESS
    $serviciosStop = @($serviciosApp)
    [array]::Reverse($serviciosStop)
    foreach ($nombre in $serviciosStop) {
        $svc = Get-Service -Name $nombre -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Stopped') {
            $resultadoDetener = Invoke-ServiceActionResponsive -Nombre $nombre -Accion Stop -TimeoutSegundos 60
            if ($resultadoDetener.Correcto) {
                Write-Log -Mensaje "$nombre detenido." -Nivel OK
            } else {
                $errores++
                Write-Log -Mensaje "No se pudo detener $($nombre): $($resultadoDetener.Error)" -Nivel ERROR
            }
        }
    }

    Write-Log -Mensaje '[3/8] Cerrando procesos bloqueados...' -Nivel PROGRESS
    $procesosReparacion = @((Get-ProcesosCONTPAQi) + (Get-ProcesosPID)) |
        Where-Object { -not $_.EsToolbox } |
        Sort-Object PID -Unique
    foreach ($proceso in $procesosReparacion) {
        if (Stop-ProcesoForzado -ProcessId $proceso.PID) {
            Write-Log -Mensaje "PID $($proceso.PID) ($($proceso.Nombre)) cerrado." -Nivel OK
        } else {
            $errores++
            Write-Log -Mensaje "PID $($proceso.PID) ($($proceso.Nombre)) no pudo cerrarse." -Nivel WARN
        }
    }

    Write-Log -Mensaje '[4/8] Reiniciando motor SQL...' -Nivel PROGRESS
    $sqlStopOrder = @($serviciosSqlDetectados | Sort-Object { if ($_ -eq 'SQLBrowser') { 0 } else { 1 } })
    foreach ($nombre in $sqlStopOrder) {
        $svc = Get-Service -Name $nombre -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Stopped') {
            $resultadoSqlStop = Invoke-ServiceActionResponsive -Nombre $nombre -Accion Stop -TimeoutSegundos 90
            if (-not $resultadoSqlStop.Correcto) {
                $errores++
                Write-Log -Mensaje "Error deteniendo SQL $($nombre): $($resultadoSqlStop.Error)" -Nivel ERROR
            }
        }
    }

    Write-Log -Mensaje '[5/8] Limpiando temporales seguros y cache DNS...' -Nivel PROGRESS
    $temporales = @(
        $env:TEMP,
        (Join-Path $env:LOCALAPPDATA 'Temp\Compac'),
        (Join-Path $env:LOCALAPPDATA 'Temp\CONTPAQi'),
        'C:\Windows\Temp'
    ) | Select-Object -Unique
    $totalEliminados = 0
    foreach ($ruta in $temporales) {
        $totalEliminados += Clear-TemporalSeguro -Ruta $ruta
    }
    $resultadoDns = Invoke-DnsFlushResponsive
    if ($resultadoDns.Correcto) {
        Write-Log -Mensaje "Temporales eliminados: $totalEliminados | Cache DNS renovada." -Nivel OK
    } else {
        $errores++
        Write-Log -Mensaje "Temporales eliminados: $totalEliminados | No fue posible renovar la cache DNS: $($resultadoDns.Error)" -Nivel WARN
    }

    Write-Log -Mensaje '[6/8] Iniciando SQL en orden...' -Nivel PROGRESS
    $sqlStartOrder = @($serviciosSqlDetectados | Sort-Object { if ($_ -like 'MSSQL*') { 0 } elseif ($_ -eq 'SQLBrowser') { 1 } else { 2 } })
    foreach ($nombre in $sqlStartOrder) {
        if (Test-ServicioDeshabilitado -Nombre $nombre) {
            Write-Log -Mensaje "SQL $nombre esta deshabilitado; se conserva su configuracion." -Nivel WARN
            continue
        }
        $resultadoSqlStart = Invoke-ServiceActionResponsive -Nombre $nombre -Accion Start -TimeoutSegundos 120
        if ($resultadoSqlStart.Correcto) {
            Write-Log -Mensaje "SQL $nombre activo." -Nivel OK
        } else {
            $errores++
            Write-Log -Mensaje "No se pudo iniciar SQL $($nombre): $($resultadoSqlStart.Error)" -Nivel ERROR
        }
    }

    Write-Log -Mensaje '[7/8] Iniciando y verificando todos los servicios CONTPAQi...' -Nivel PROGRESS
    $resultadoServicios = Start-TodosServiciosCONTPAQiVerificado
    $errores += $resultadoServicios.Fallidos
    Write-Log -Mensaje "Auditoria CONTPAQi: $($resultadoServicios.Correctos) activos, $($resultadoServicios.Fallidos) con incidencia, $($resultadoServicios.Omitidos) deshabilitados de $($resultadoServicios.Total) detectados." -Nivel $(if ($resultadoServicios.Fallidos -eq 0) { 'OK' } else { 'WARN' })

    Write-Log -Mensaje '[8/8] Validando SQL y estado final...' -Nivel PROGRESS
    foreach ($nombre in (Get-ServiciosMotorSQL | Select-Object -ExpandProperty Name)) {
        $instancia = Get-NombreInstanciaSQL -NombreServicio $nombre
        if (-not $instancia) { continue }
        $pruebaSql = Test-ConexionSQLLocal -Instancia $instancia -TimeoutSegundos 5
        if ($pruebaSql.Correcto) {
            Write-Log -Mensaje "Conexion SQL correcta en $instancia ($($pruebaSql.Servidor), v$($pruebaSql.Version))." -Nivel OK
        } else {
            $errores++
            Write-Log -Mensaje "SQL esta activo pero no responde en $($instancia): $($pruebaSql.Error)" -Nivel ERROR
        }
    }

    } catch {
        $errores++
        Write-Log -Mensaje "Error inesperado durante la reparacion profunda: $($_.Exception.Message)" -Nivel ERROR
    } finally {
        if (-not (Restore-ServicesDevAfterRepair -Estados $proteccionServicesDev.Estados)) { $errores++ }
    }

    $duracion = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    Write-Separador -Color $(if ($errores -eq 0) { $Script:ColorExito } else { $Script:ColorAdvertencia })
    if ($errores -eq 0) {
        Write-Log -Mensaje "Reparacion profunda completada correctamente en $duracion segundos." -Nivel OK
    } else {
        Write-Log -Mensaje "Reparacion completada con $errores incidencia(s) en $duracion segundos. Revisa la bitacora." -Nivel WARN
    }
    if (Test-ReinicioPendiente) {
        Write-Log -Mensaje 'Windows tiene un reinicio pendiente. Reinicia el equipo antes de validar nuevamente CONTPAQi.' -Nivel WARN
    } else {
        Write-Log -Mensaje 'Abre CONTPAQi y valida acceso a empresa, ADD, timbrado y terminales.' -Nivel INFO
    }
}

function Show-DiagnosticoCompleto {
    Write-Encabezado -Titulo 'DIAGNOSTICO COMPLETO' -Subtitulo 'Servicios, procesos y sesiones' -Color 'Cyan'

    Write-SeccionMenu -Titulo 'SQL SERVER' -Color 'Green'
    if ($ServiciosSQL.Count -eq 0) {
        Write-Log -Mensaje 'Sin instancias SQL detectadas.' -Nivel INFO
    } else {
        foreach ($svc in $ServiciosSQL) {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            $color = if ($s.Status -eq 'Running') { $Script:ColorExito } else { $Script:ColorError }
            Write-Host "  $svc : $(Get-EstadoTexto -Servicio $s)" -ForegroundColor $color
        }
    }

    Write-SeccionMenu -Titulo 'SERVICIOS TERMINAL (AuthServer)' -Color $Script:ColorTerminal
    $terminal = @(Get-ServiciosTerminal)
    if ($terminal.Count -eq 0) {
        Write-Log -Mensaje 'Sin AuthServer/Licencias detectados.' -Nivel INFO
    } else {
        foreach ($item in $terminal) {
            $color = if ($item.Servicio.Status -eq 'Running') { $Script:ColorExito } else { $Script:ColorError }
            Write-Host "  $($item.Etiqueta)" -ForegroundColor $Script:ColorAcento
            Write-Host "    -> $(Get-EstadoTexto -Servicio $item.Servicio) | $($item.Servicio.Name)" -ForegroundColor $color
        }
    }

    Write-SeccionMenu -Titulo 'SESIONES RDP' -Color $Script:ColorServidor
    $sesiones = @(Get-SesionesActivas)
    if ($sesiones.Count -eq 0) {
        Write-Log -Mensaje 'Sin sesiones RDP activas.' -Nivel INFO
    } else {
        foreach ($ses in $sesiones) {
            Write-Log -Mensaje "$($ses.Usuario) | ID $($ses.SessionId) | $($ses.Estado)" -Nivel INFO
        }
    }

    Write-SeccionMenu -Titulo 'PROCESOS CONTPAQi' -Color $Script:ColorAdvertencia
    $procesos = @(Get-ProcesosCONTPAQi | Where-Object { -not $_.EsToolbox })
    if ($procesos.Count -eq 0) {
        Write-Log -Mensaje 'Sin procesos CONTPAQi activos.' -Nivel OK
    } else {
        foreach ($p in $procesos) {
            Write-Log -Mensaje "PID $($p.PID) | $($p.Nombre.PadRight(16)) | Modulo: $($p.Modulo.PadRight(24)) | $($p.Usuario)" -Nivel PROGRESS
        }
    }

    Write-SeccionMenu -Titulo 'PROCESOS Y SERVICIOS PID' -Color $Script:ColorServidor
    $procesosPID = @(Get-ProcesosPID | Where-Object { -not $_.EsToolbox })
    if ($procesosPID.Count -eq 0) {
        Write-Log -Mensaje 'Sin procesos PID activos.' -Nivel OK
    } else {
        foreach ($p in $procesosPID) {
            Write-Log -Mensaje "PID $($p.PID) | $($p.Nombre.PadRight(18)) | Modulo: $($p.Modulo.PadRight(24)) | $($p.Usuario)" -Nivel PROGRESS
        }
    }
    $serviciosPID = @(Get-ServiciosPID)
    foreach ($svc in $serviciosPID) {
        $color = if ($svc.Status -eq 'Running') { $Script:ColorExito } else { $Script:ColorError }
        Write-Host "  $($svc.DisplayName) -> $(Get-EstadoTexto -Servicio $svc)" -ForegroundColor $color
    }
}

# --- DIAGNOSTICO SEGURO PARA TICKETS ---
# Solo recopila evidencia y recomendaciones. No modifica empresas, bases de datos
# ni archivos de CONTPAQi.
function Get-RutasCONTPAQi {
    $rutas = @(
        'C:\Compac',
        'C:\CONTPAQi',
        (Join-Path ${env:ProgramFiles(x86)} 'Compac'),
        (Join-Path $env:ProgramFiles 'Compac'),
        (Join-Path $env:ProgramData 'Compac'),
        (Join-Path $env:ProgramData 'CONTPAQi'),
        (Join-Path $env:PUBLIC 'Documents\Compac')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }

    return @($rutas | Select-Object -Unique)
}

function Get-RutasPermisosTerminalCONTPAQi {
    $candidatas = @(
        [PSCustomObject]@{ Ruta = 'C:\Compac'; Derecho = 'Modify'; Tipo = 'Datos y operacion heredada' },
        [PSCustomObject]@{ Ruta = 'C:\CONTPAQi'; Derecho = 'Modify'; Tipo = 'Datos y operacion heredada' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:ProgramData 'Compac'); Derecho = 'Modify'; Tipo = 'Datos compartidos locales' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:ProgramData 'CONTPAQi'); Derecho = 'Modify'; Tipo = 'Datos compartidos locales' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:PUBLIC 'Documents\Compac'); Derecho = 'Modify'; Tipo = 'Documentos publicos' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:PUBLIC 'Documents\CONTPAQi'); Derecho = 'Modify'; Tipo = 'Documentos publicos' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:LOCALAPPDATA 'Compac'); Derecho = 'Modify'; Tipo = 'Configuracion del usuario' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:LOCALAPPDATA 'CONTPAQi'); Derecho = 'Modify'; Tipo = 'Configuracion del usuario' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:APPDATA 'Compac'); Derecho = 'Modify'; Tipo = 'Configuracion del usuario' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:APPDATA 'CONTPAQi'); Derecho = 'Modify'; Tipo = 'Configuracion del usuario' },
        [PSCustomObject]@{ Ruta = (Join-Path ${env:ProgramFiles(x86)} 'Compac'); Derecho = 'ReadAndExecute'; Tipo = 'Archivos de programa protegidos' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:ProgramFiles 'Compac'); Derecho = 'ReadAndExecute'; Tipo = 'Archivos de programa protegidos' },
        [PSCustomObject]@{ Ruta = (Join-Path ${env:ProgramFiles(x86)} 'CONTPAQi'); Derecho = 'ReadAndExecute'; Tipo = 'Archivos de programa protegidos' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:ProgramFiles 'CONTPAQi'); Derecho = 'ReadAndExecute'; Tipo = 'Archivos de programa protegidos' }
    ) | Where-Object { $_.Ruta -and (Test-Path -LiteralPath $_.Ruta -PathType Container) }

    $unicas = @{}
    foreach ($item in $candidatas) {
        $rutaCompleta = [IO.Path]::GetFullPath($item.Ruta).TrimEnd('\')
        $clave = $rutaCompleta.ToLowerInvariant()
        if (-not $unicas.ContainsKey($clave) -or $item.Derecho -eq 'Modify') {
            $unicas[$clave] = [PSCustomObject]@{ Ruta = $rutaCompleta; Derecho = $item.Derecho; Tipo = $item.Tipo }
        }
    }
    return @($unicas.Values | Sort-Object Ruta)
}

function Test-PermisoUsuariosCONTPAQi {
    param(
        [Parameter(Mandatory)][string]$Ruta,
        [Parameter(Mandatory)][ValidateSet('Modify', 'ReadAndExecute')][string]$Derecho
    )
    try {
        $sidUsuarios = 'S-1-5-32-545'
        $requerido = [Security.AccessControl.FileSystemRights][Enum]::Parse([Security.AccessControl.FileSystemRights], $Derecho)
        $reglas = @(Get-Acl -LiteralPath $Ruta -ErrorAction Stop | Select-Object -ExpandProperty Access)
        $permitido = $false
        foreach ($regla in $reglas) {
            try { $sid = $regla.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { continue }
            if ($sid -ne $sidUsuarios) { continue }
            $incluye = (($regla.FileSystemRights -band $requerido) -eq $requerido)
            if ($incluye -and $regla.AccessControlType -eq 'Deny') { return $false }
            if ($incluye -and $regla.AccessControlType -eq 'Allow') { $permitido = $true }
        }
        return $permitido
    } catch {
        return $false
    }
}

function Invoke-RepararPermisosTerminalCONTPAQi {
    Write-Encabezado -Titulo 'PERMISOS CONTPAQI PARA TERMINALES' -Subtitulo 'Acceso local seguro para usuarios estandar' -Color $Script:ColorTerminal
    Write-Log -Mensaje 'Se concedera Modificar solo en datos/configuracion y Lectura-Ejecucion en archivos de programa. No se otorgara Control total.' -Nivel INFO
    if (-not (Confirmar-Movimiento -Frase 'APLICAR PERMISOS' `
        -Accion 'Corregir permisos locales CONTPAQi' `
        -Detalle 'Se agregaran permisos heredables al grupo Usuarios de Windows sin borrar las reglas existentes.')) { return }

    $rutas = @(Get-RutasPermisosTerminalCONTPAQi)
    if ($rutas.Count -eq 0) {
        Write-Log -Mensaje 'No se encontraron carpetas locales CONTPAQi a las que aplicar permisos.' -Nivel WARN
        return
    }
    $directorioRespaldo = Join-Path $env:ProgramData 'CONTPAQiToolbox\ACL'
    $archivoRespaldo = Join-Path $directorioRespaldo ("Permisos_{0}_{1}.json" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $rutasJson = $rutas | ConvertTo-Json -Depth 4 -Compress
    $codigoPermisos = @'
param([string]$RoutesJson, [string]$BackupFile, [string]$ComputerName)
$rutas = @($RoutesJson | ConvertFrom-Json)
$sidUsuarios = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')
$cuentaUsuarios = $sidUsuarios.Translate([Security.Principal.NTAccount])
$respaldos = @()
foreach ($item in $rutas) {
    $acl = Get-Acl -LiteralPath $item.Ruta -ErrorAction Stop
    $respaldos += [PSCustomObject]@{ Ruta = [string]$item.Ruta; Sddl = $acl.Sddl; Derecho = [string]$item.Derecho }
}
$carpeta = Split-Path -Parent $BackupFile
if (-not (Test-Path -LiteralPath $carpeta)) { New-Item -ItemType Directory -Path $carpeta -Force -ErrorAction Stop | Out-Null }
[PSCustomObject]@{
    Equipo = $ComputerName
    Fecha = (Get-Date).ToString('o')
    Grupo = $cuentaUsuarios.Value
    Rutas = $respaldos
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $BackupFile -Encoding UTF8 -ErrorAction Stop

$resultados = @()
foreach ($item in $rutas) {
    try {
        $acl = Get-Acl -LiteralPath $item.Ruta -ErrorAction Stop
        $derecho = [Security.AccessControl.FileSystemRights][Enum]::Parse([Security.AccessControl.FileSystemRights], [string]$item.Derecho)
        $regla = New-Object Security.AccessControl.FileSystemAccessRule(
            $cuentaUsuarios,
            $derecho,
            ([Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'),
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        $null = $acl.AddAccessRule($regla)
        Set-Acl -LiteralPath $item.Ruta -AclObject $acl -ErrorAction Stop

        $verificado = $false
        foreach ($reglaActual in @((Get-Acl -LiteralPath $item.Ruta -ErrorAction Stop).Access)) {
            try { $sidActual = $reglaActual.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { continue }
            if ($sidActual -ne $sidUsuarios.Value -or $reglaActual.AccessControlType -ne 'Allow') { continue }
            if (($reglaActual.FileSystemRights -band $derecho) -eq $derecho) { $verificado = $true; break }
        }
        $resultados += [PSCustomObject]@{ Ruta = [string]$item.Ruta; Derecho = [string]$item.Derecho; Correcto = $verificado; Error = $null }
    } catch {
        $resultados += [PSCustomObject]@{ Ruta = [string]$item.Ruta; Derecho = [string]$item.Derecho; Correcto = $false; Error = $_.Exception.Message }
    }
}
[PSCustomObject]@{ Resultados = $resultados; ArchivoRespaldo = $BackupFile; Cuenta = $cuentaUsuarios.Value }
'@
    Write-Log -Mensaje "Respaldando ACL y aplicando permisos en $($rutas.Count) ruta(s)..." -Nivel PROGRESS
    $worker = Invoke-ResponsiveWorker -ScriptText $codigoPermisos `
        -Arguments @($rutasJson, $archivoRespaldo, $env:COMPUTERNAME) `
        -TimeoutSeconds 1800 -Activity 'Corrigiendo permisos CONTPAQi'
    if (-not $worker.Correcto -or $worker.Timeout -or -not $worker.Resultado) {
        Write-Log -Mensaje "No se aplicaron los permisos de forma completa: $($worker.Error)" -Nivel ERROR
        return
    }

    $correctos = 0
    $fallidos = 0
    foreach ($resultado in @($worker.Resultado.Resultados)) {
        if ($resultado.Correcto) {
            $correctos++
            Write-Log -Mensaje "$($resultado.Derecho) verificado: $($resultado.Ruta)" -Nivel OK
        } else {
            $fallidos++
            Write-Log -Mensaje "No se pudo corregir $($resultado.Ruta): $($resultado.Error)" -Nivel ERROR
        }
    }
    Write-Log -Mensaje "Respaldo recuperable de permisos: $($worker.Resultado.ArchivoRespaldo)" -Nivel INFO

    $recursosRemotos = @()
    try {
        $recursosRemotos = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=4' -ErrorAction SilentlyContinue |
            Where-Object { $_.ProviderName } | Select-Object -ExpandProperty ProviderName -Unique)
    } catch { }
    if ($recursosRemotos.Count -gt 0) {
        Write-Log -Mensaje "Recursos de red detectados (no modificados): $($recursosRemotos -join ', '). Sus permisos NTFS y de recurso compartido deben corregirse en el servidor." -Nivel WARN
    }
    Write-Separador -Color $(if ($fallidos -eq 0) { $Script:ColorExito } else { $Script:ColorAdvertencia })
    Write-Log -Mensaje "Permisos locales finalizados: $correctos correctos | $fallidos con incidencia." -Nivel $(if ($fallidos -eq 0) { 'OK' } else { 'WARN' })
    if ($fallidos -eq 0) { Write-Log -Mensaje 'Cierra y vuelve a abrir CONTPAQi para que la terminal use los permisos actualizados.' -Nivel INFO }
}

function Get-EventosCONTPAQiRecientes {
    try {
        return @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = (Get-Date).AddDays(-2) } -MaxEvents 250 -ErrorAction Stop |
            Where-Object {
                $_.LevelDisplayName -in @('Error', 'Warning') -and
                (($_.ProviderName -match 'CONTPAQ|COMPAC|SACI|SQL') -or ($_.Message -match 'CONTPAQ|COMPAC|SACI|SQL Server'))
            } |
            Select-Object -First 12)
    } catch {
        Write-Log -Mensaje "No fue posible consultar el Visor de eventos: $($_.Exception.Message)" -Nivel WARN
        return @()
    }
}

function Show-DiagnosticoTicket {
    Write-Encabezado -Titulo 'DIAGNOSTICO PARA TICKET' -Subtitulo 'Revision segura: servicios, espacio, rutas y eventos' -Color 'Cyan'
    $alertas = 0

    Write-SeccionMenu -Titulo 'SERVICIOS CRITICOS' -Color 'Green'
    $servicios = @($ServiciosSQL + $ServiciosSACI + $ServiciosLicencias | Select-Object -Unique)
    if ($servicios.Count -eq 0) {
        Write-Log -Mensaje 'No se detectaron servicios SQL o CONTPAQi en este equipo.' -Nivel INFO
    }
    foreach ($nombre in $servicios) {
        $servicio = Get-Service -Name $nombre -ErrorAction SilentlyContinue
        if (-not $servicio) { continue }
        if ($servicio.Status -eq 'Running') {
            Write-Log -Mensaje "$($nombre): activo." -Nivel OK
        } else {
            $alertas++
            Write-Log -Mensaje "$($nombre): $($servicio.Status). Recomendacion: validar dependencias y reiniciarlo de forma controlada." -Nivel ERROR
        }
    }

    Write-SeccionMenu -Titulo 'ESPACIO EN DISCO' -Color 'Yellow'
    foreach ($unidad in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null })) {
        $libreGB = [math]::Round($unidad.Free / 1GB, 2)
        $totalGB = [math]::Round(($unidad.Used + $unidad.Free) / 1GB, 2)
        if ($libreGB -lt 10) {
            $alertas++
            Write-Log -Mensaje "Unidad $($unidad.Name): $libreGB GB libres de $totalGB GB. Riesgo para SQL, temporales y respaldos." -Nivel WARN
        } else {
            Write-Log -Mensaje "Unidad $($unidad.Name): $libreGB GB libres de $totalGB GB." -Nivel OK
        }
    }

    Write-SeccionMenu -Titulo 'RUTAS LOCALES CONTPAQi' -Color 'Magenta'
    $rutas = @(Get-RutasCONTPAQi)
    if ($rutas.Count -eq 0) {
        Write-Log -Mensaje 'No se encontraron rutas locales comunes de CONTPAQi/Compac.' -Nivel INFO
    } else {
        foreach ($ruta in $rutas) {
            try {
                $acl = Get-Acl -LiteralPath $ruta -ErrorAction Stop
                $reglas = @($acl.Access | Where-Object { $_.AccessControlType -eq 'Allow' })
                Write-Log -Mensaje "$ruta | ACL accesible | reglas permitidas: $($reglas.Count)" -Nivel OK
            } catch {
                $alertas++
                Write-Log -Mensaje "$ruta | no se pudo leer permisos: $($_.Exception.Message)" -Nivel WARN
            }
        }
    }

    Write-SeccionMenu -Titulo 'EVENTOS RECIENTES DE WINDOWS' -Color 'Red'
    $eventos = @(Get-EventosCONTPAQiRecientes)
    if ($eventos.Count -eq 0) {
        Write-Log -Mensaje 'No se detectaron eventos recientes relacionados con CONTPAQi, SACI o SQL.' -Nivel OK
    } else {
        $alertas += $eventos.Count
        foreach ($evento in $eventos) {
            $mensaje = (($evento.Message -replace '[\r\n]+', ' ') -replace '\s+', ' ').Trim()
            if ($mensaje.Length -gt 220) { $mensaje = $mensaje.Substring(0, 220) + '...' }
            Write-Log -Mensaje "$($evento.TimeCreated.ToString('dd/MM HH:mm')) | $($evento.ProviderName) | $mensaje" -Nivel WARN
        }
    }

    Write-SeccionMenu -Titulo 'SQL Y REINICIO PENDIENTE' -Color 'Green'
    $motores = @(Get-ServiciosMotorSQL)
    if ($motores.Count -eq 0) {
        Write-Log -Mensaje 'No se detectaron instancias del motor SQL Server.' -Nivel INFO
    } else {
        foreach ($motor in $motores) {
            $instancia = Get-NombreInstanciaSQL -NombreServicio $motor.Name
            if ($motor.Status -ne 'Running') {
                $alertas++
                Write-Log -Mensaje "${instancia}: motor SQL detenido ($($motor.Name))." -Nivel ERROR
                continue
            }
            $pruebaSql = Test-ConexionSQLLocal -Instancia $instancia -TimeoutSegundos 4
            if ($pruebaSql.Correcto) {
                Write-Log -Mensaje "$instancia responde correctamente | SQL $($pruebaSql.Version)" -Nivel OK
            } else {
                $alertas++
                Write-Log -Mensaje "$instancia esta activo, pero no acepta conexion integrada local: $($pruebaSql.Error)" -Nivel ERROR
            }
        }
    }
    if (Test-ReinicioPendiente) {
        $alertas++
        Write-Log -Mensaje 'Windows tiene un reinicio pendiente.' -Nivel WARN
    } else {
        Write-Log -Mensaje 'Windows no reporta reinicio pendiente.' -Nivel OK
    }

    Write-SeccionMenu -Titulo 'SIGUIENTE PASO SUGERIDO' -Color 'Cyan'
    if ($alertas -eq 0) {
        Write-Log -Mensaje 'Sin alertas locales. Si el problema ocurre en terminal, revisa IP/nombre del SACI, conectividad de red y la version instalada.' -Nivel OK
    } else {
        Write-Log -Mensaje "Se detectaron $alertas alerta(s). Adjunta esta bitacora al ticket antes de reiniciar o reparar componentes." -Nivel WARN
    }
}

function Export-PaqueteSoporte {
    param(
        [string]$DestinationDirectory = [Environment]::GetFolderPath('Desktop'),
        [switch]$NoAbrir
    )
    Write-Encabezado -Titulo 'PAQUETE DE SOPORTE' -Subtitulo 'Evidencia lista para adjuntar al ticket' -Color 'Cyan'

    $marcaTiempo = Get-Date -Format 'yyyyMMdd_HHmmss'
    $desktop = $DestinationDirectory
    if (-not (Test-Path -LiteralPath $desktop -PathType Container)) {
        New-Item -ItemType Directory -Path $desktop -Force -ErrorAction Stop | Out-Null
    }
    $basePaquetes = Join-Path $env:ProgramData 'CONTPAQiToolbox\SupportPackages'
    $staging = Join-Path $basePaquetes ("Staging_{0}" -f ([guid]::NewGuid().ToString('N')))
    $zipPath = Join-Path $desktop ("CONTPAQi_Soporte_{0}_{1}.zip" -f $env:COMPUTERNAME, $marcaTiempo)

    try {
        New-Item -ItemType Directory -Path $staging -Force -ErrorAction Stop | Out-Null
        Write-Log -Mensaje '[1/5] Recopilando resumen del equipo...' -Nivel PROGRESS

        $so = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $resumen = @(
            "CONTPAQi Toolbox v$($Script:Version) - Paquete de soporte",
            "Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "Equipo: $env:COMPUTERNAME",
            "Usuario operador: $env:USERDOMAIN\$env:USERNAME",
            "Perfil detectado: $(Get-PerfilEquipo)",
            "Windows: $($so.Caption) $($so.Version) Build $($so.BuildNumber)",
            "Arquitectura: $env:PROCESSOR_ARCHITECTURE",
            "Ultimo arranque: $($so.LastBootUpTime)",
            "Reinicio pendiente: $(if (Test-ReinicioPendiente) { 'SI' } else { 'NO' })"
        )
        $resumen | Set-Content -LiteralPath (Join-Path $staging '00_Resumen.txt') -Encoding UTF8 -ErrorAction Stop

        Write-Log -Mensaje '[2/5] Exportando servicios, procesos e instalaciones...' -Nivel PROGRESS
        $serviciosSoporte = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match 'CONTPAQ|COMPAC|SACI|AppKey|AuthServer|XML|^MSSQL|^SQLBrowser$' -or
            $_.DisplayName -match 'CONTPAQ|COMPAC|SACI|SQL Server|XML en l.nea'
        } | Sort-Object Name | Select-Object Status, StartType, Name, DisplayName)
        $serviciosSoporte | Export-Csv -LiteralPath (Join-Path $staging '01_Servicios.csv') -NoTypeInformation -Encoding UTF8

        @((Get-ProcesosCONTPAQi) + (Get-ProcesosPID)) |
            Sort-Object PID -Unique |
            Select-Object PID, Nombre, Modulo, Usuario |
            Export-Csv -LiteralPath (Join-Path $staging '02_Procesos.csv') -NoTypeInformation -Encoding UTF8

        Get-ProgramasInstalados |
            Where-Object { $_.DisplayName -match 'CONTPAQ|COMPAC|SQL Server' } |
            Sort-Object DisplayName |
            Export-Csv -LiteralPath (Join-Path $staging '03_Programas.csv') -NoTypeInformation -Encoding UTF8

        Write-Log -Mensaje '[3/5] Exportando eventos y almacenamiento...' -Nivel PROGRESS
        Get-EventosCONTPAQiRecientes |
            Select-Object TimeCreated, LevelDisplayName, ProviderName, Id, Message |
            Export-Csv -LiteralPath (Join-Path $staging '04_Eventos.csv') -NoTypeInformation -Encoding UTF8
        Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue |
            Select-Object DeviceID, VolumeName,
                @{Name='TamanoGB';Expression={[math]::Round($_.Size / 1GB, 2)}},
                @{Name='LibreGB';Expression={[math]::Round($_.FreeSpace / 1GB, 2)}} |
            Export-Csv -LiteralPath (Join-Path $staging '05_Discos.csv') -NoTypeInformation -Encoding UTF8

        Write-Log -Mensaje '[4/5] Exportando configuracion de red y bitacora...' -Nivel PROGRESS
        (& ipconfig.exe /all 2>&1) | Set-Content -LiteralPath (Join-Path $staging '06_Red.txt') -Encoding UTF8
        if ($Script:LogFile -and (Test-Path -LiteralPath $Script:LogFile)) {
            Copy-Item -LiteralPath $Script:LogFile -Destination (Join-Path $staging '07_Bitacora_Toolbox.log') -Force
        }

        Write-Log -Mensaje '[5/5] Comprimiendo evidencia...' -Nivel PROGRESS
        Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force -ErrorAction Stop
        Write-Log -Mensaje "Paquete creado correctamente: $zipPath" -Nivel OK
        if (-not $NoAbrir) {
            try { Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$zipPath`"" -ErrorAction Stop | Out-Null } catch { }
        }
    } catch {
        Write-Log -Mensaje "No se pudo crear el paquete de soporte: $($_.Exception.Message)" -Nivel ERROR
    } finally {
        $baseCompleta = [System.IO.Path]::GetFullPath($basePaquetes).TrimEnd('\')
        $stagingCompleto = [System.IO.Path]::GetFullPath($staging).TrimEnd('\')
        if ($stagingCompleto.StartsWith($baseCompleta + '\', [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $stagingCompleto)) {
            Remove-Item -LiteralPath $stagingCompleto -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- DIAGNOSTICO INTELIGENTE Y REPORTE PROFESIONAL ---
# Todas las pruebas de esta seccion son de solo lectura. El diagnostico explica
# evidencia, consecuencia y siguiente accion, pero nunca aplica reparaciones.
function Get-DiagnosticoInteligenteCONTPAQi {
    $inicio = Get-Date
    $hallazgos = New-Object System.Collections.ArrayList
    $inventario = [ordered]@{}

    function Add-DiagnosticoHallazgo {
        param(
            [ValidateSet('CRITICA','ALTA','MEDIA','INFORMATIVA')][string]$Severidad,
            [string]$Categoria,
            [string]$Titulo,
            [string]$Evidencia,
            [string]$Consecuencia,
            [string]$Accion
        )
        $peso = switch ($Severidad) { 'CRITICA' { 22 }; 'ALTA' { 13 }; 'MEDIA' { 6 }; default { 0 } }
        [void]$hallazgos.Add([PSCustomObject]@{
            Severidad = $Severidad; Categoria = $Categoria; Titulo = $Titulo
            Evidencia = $Evidencia; Consecuencia = $Consecuencia; Accion = $Accion; Peso = $peso
        })
    }

    Write-Log -Mensaje '[1/8] Identificando equipo y sistema operativo...' -Nivel PROGRESS
    try {
        $so = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $equipo = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $inventario.Sistema = "$($so.Caption) | Version $($so.Version) | Build $($so.BuildNumber)"
        $inventario.Hardware = "$($equipo.Manufacturer) $($equipo.Model) | RAM $([math]::Round([double]$equipo.TotalPhysicalMemory / 1GB, 1)) GB"
        $diasActivo = [math]::Round(((Get-Date) - $so.LastBootUpTime).TotalDays, 1)
        $inventario.UltimoArranque = "$($so.LastBootUpTime.ToString('dd/MM/yyyy HH:mm')) | $diasActivo dia(s) activo"
        if ($diasActivo -ge 45) {
            Add-DiagnosticoHallazgo -Severidad MEDIA -Categoria 'Windows' -Titulo 'Tiempo prolongado sin reiniciar' `
                -Evidencia "El equipo lleva $diasActivo dias activo." `
                -Consecuencia 'Actualizaciones, servicios o memoria pendiente pueden causar comportamiento inestable.' `
                -Accion 'Programa un reinicio controlado fuera del horario de trabajo y valida nuevamente.'
        }
    } catch {
        $inventario.Sistema = 'No fue posible consultar Windows.'
        Add-DiagnosticoHallazgo -Severidad MEDIA -Categoria 'Windows' -Titulo 'Inventario de Windows incompleto' `
            -Evidencia $_.Exception.Message -Consecuencia 'El reporte no puede validar todos los recursos del equipo.' `
            -Accion 'Ejecuta Toolbox como administrador y vuelve a generar el diagnostico.'
    }

    Write-Log -Mensaje '[2/8] Revisando productos CONTPAQi instalados...' -Nivel PROGRESS
    $productos = @(Get-ProgramasInstalados | Where-Object {
        $_.DisplayName -match '(?i)CONTPAQ|COMPAC|APPKEY|SACI|XML\s*EN\s*L[IÍ]NEA'
    } | Sort-Object DisplayName, DisplayVersion -Unique)
    $inventario.Productos = @($productos | ForEach-Object {
        "$($_.DisplayName) $(if ($_.DisplayVersion) { 'v' + $_.DisplayVersion } else { '' })".Trim()
    })
    if ($productos.Count -eq 0) {
        Add-DiagnosticoHallazgo -Severidad MEDIA -Categoria 'CONTPAQi' -Titulo 'No se detectaron productos registrados' `
            -Evidencia 'Windows no devolvio productos CONTPAQi o Compac en el registro de programas.' `
            -Consecuencia 'Puede tratarse de una terminal sin instalacion, una instalacion incompleta o datos de registro ausentes.' `
            -Accion 'Confirma el rol del equipo y valida la instalacion desde Programas y caracteristicas.'
    }

    Write-Log -Mensaje '[3/8] Validando servicios y ejecutables...' -Nivel PROGRESS
    $servicios = @(Get-ServiciosCONTPAQiDetectados)
    $inventario.Servicios = @($servicios | ForEach-Object { [PSCustomObject]@{
        Nombre = $_.Name; Descripcion = $_.DisplayName; Estado = [string]$_.Status; Inicio = [string]$_.StartType
    } })
    if ($servicios.Count -eq 0) {
        Add-DiagnosticoHallazgo -Severidad ALTA -Categoria 'Servicios' -Titulo 'No se encontraron servicios de aplicacion o SQL' `
            -Evidencia 'El inventario de servicios relacionados esta vacio.' `
            -Consecuencia 'Los sistemas instalados pueden no iniciar o no conectarse con el servidor.' `
            -Accion 'Valida que la instalacion corresponda al rol del equipo y repara componentes solo si faltan servicios esperados.'
    }
    foreach ($servicio in $servicios) {
        if ($servicio.Status -ne 'Running' -and -not (Test-ServicioDeshabilitado -Nombre $servicio.Name)) {
            $esSql = $servicio.Name -eq 'MSSQLSERVER' -or $servicio.Name -match '^MSSQL\$'
            Add-DiagnosticoHallazgo -Severidad $(if ($esSql) { 'CRITICA' } else { 'ALTA' }) -Categoria 'Servicios' `
                -Titulo "Servicio detenido: $($servicio.Name)" `
                -Evidencia "Estado $($servicio.Status) | Inicio $($servicio.StartType) | $($servicio.DisplayName)" `
                -Consecuencia $(if ($esSql) { 'Las empresas no pueden abrir mientras el motor SQL permanezca detenido.' } else { 'La funcion asociada puede no estar disponible para usuarios o terminales.' }) `
                -Accion 'Revisa dependencias y bitacoras; despues inicia el servicio de forma controlada y valida su estabilidad.'
        }
        try {
            $nombreSeguro = $servicio.Name.Replace("'", "''")
            $svcCim = Get-CimInstance Win32_Service -Filter "Name='$nombreSeguro'" -ErrorAction Stop
            $rutaExe = Get-RutaEjecutableServicio -Comando $svcCim.PathName
            if ($rutaExe -and -not (Test-Path -LiteralPath $rutaExe -PathType Leaf)) {
                Add-DiagnosticoHallazgo -Severidad CRITICA -Categoria 'Servicios' -Titulo "Ejecutable ausente: $($servicio.Name)" `
                    -Evidencia "Windows intenta ejecutar: $rutaExe" `
                    -Consecuencia 'El servicio no podra iniciar y puede indicar archivos eliminados o una instalacion danada.' `
                    -Accion 'No cambies la ruta manualmente; repara o reinstala el componente correspondiente con respaldo previo.'
            }
        } catch { }
    }

    Write-Log -Mensaje '[4/8] Comprobando motores SQL Server...' -Nivel PROGRESS
    $sqlResultados = New-Object System.Collections.ArrayList
    foreach ($motor in @(Get-ServiciosMotorSQL)) {
        $instancia = Get-NombreInstanciaSQL -NombreServicio $motor.Name
        if ($motor.Status -ne 'Running') {
            [void]$sqlResultados.Add([PSCustomObject]@{ Instancia = $instancia; Estado = 'Detenido'; Version = 'N/D' })
            continue
        }
        $prueba = Test-ConexionSQLLocal -Instancia $instancia -TimeoutSegundos 5
        [void]$sqlResultados.Add([PSCustomObject]@{
            Instancia = $instancia; Estado = $(if ($prueba.Correcto) { 'Disponible' } else { 'Sin conexion' })
            Version = $(if ($prueba.Correcto) { $prueba.Version } else { 'N/D' })
        })
        if (-not $prueba.Correcto) {
            Add-DiagnosticoHallazgo -Severidad CRITICA -Categoria 'SQL Server' -Titulo "SQL no acepta conexion: $instancia" `
                -Evidencia $prueba.Error -Consecuencia 'Toolbox no puede validar empresas y los usuarios pueden recibir errores de conexion.' `
                -Accion 'Valida credenciales integradas, protocolos, estado del motor y registro de errores de SQL Server.'
        }
    }
    $inventario.SQL = @($sqlResultados)

    Write-Log -Mensaje '[5/8] Midiendo almacenamiento...' -Nivel PROGRESS
    $discos = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | ForEach-Object {
        $total = [double]$_.Size
        $libre = [double]$_.FreeSpace
        $porcentaje = if ($total -gt 0) { [math]::Round(($libre / $total) * 100, 1) } else { 0 }
        [PSCustomObject]@{ Unidad = $_.DeviceID; TotalGB = [math]::Round($total / 1GB, 1); LibreGB = [math]::Round($libre / 1GB, 1); LibrePorcentaje = $porcentaje }
    })
    $inventario.Discos = $discos
    foreach ($disco in $discos) {
        $severidad = if ($disco.LibrePorcentaje -lt 5 -or $disco.LibreGB -lt 3) { 'CRITICA' } elseif ($disco.LibrePorcentaje -lt 10 -or $disco.LibreGB -lt 10) { 'ALTA' } elseif ($disco.LibrePorcentaje -lt 20) { 'MEDIA' } else { $null }
        if ($severidad) {
            Add-DiagnosticoHallazgo -Severidad $severidad -Categoria 'Almacenamiento' -Titulo "Poco espacio en $($disco.Unidad)" `
                -Evidencia "$($disco.LibreGB) GB libres de $($disco.TotalGB) GB ($($disco.LibrePorcentaje)%)." `
                -Consecuencia 'SQL Server, respaldos, temporales y actualizaciones pueden fallar por falta de espacio.' `
                -Accion 'Libera o amplia espacio de forma planificada; no elimines archivos de bases de datos manualmente.'
        }
    }

    Write-Log -Mensaje '[6/8] Revisando red y resolucion local...' -Nivel PROGRESS
    $adaptadores = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -ErrorAction SilentlyContinue)
    $inventario.Red = @($adaptadores | ForEach-Object { [PSCustomObject]@{
        Adaptador = $_.Description; IP = (@($_.IPAddress | Where-Object { $_ -match '^\d+\.' }) -join ', ')
        Gateway = (@($_.DefaultIPGateway) -join ', '); DNS = (@($_.DNSServerSearchOrder) -join ', ')
    } })
    if ($adaptadores.Count -eq 0) {
        Add-DiagnosticoHallazgo -Severidad ALTA -Categoria 'Red' -Titulo 'No hay adaptadores IP activos' `
            -Evidencia 'Windows no devolvio adaptadores con IP habilitada.' `
            -Consecuencia 'La terminal no puede localizar licencias, SQL ni servicios del servidor.' `
            -Accion 'Valida cable, Wi-Fi, direccion IP y estado del adaptador de red.'
    } elseif (@($adaptadores | Where-Object { $_.DefaultIPGateway }).Count -eq 0) {
        Add-DiagnosticoHallazgo -Severidad MEDIA -Categoria 'Red' -Titulo 'No se detecto puerta de enlace' `
            -Evidencia 'Los adaptadores activos no reportan gateway predeterminado.' `
            -Consecuencia 'El acceso fuera de la subred y algunos servicios en Internet pueden no funcionar.' `
            -Accion 'Confirma que sea una configuracion intencional; de lo contrario revisa DHCP o la IP estatica.'
    }

    Write-Log -Mensaje '[7/8] Revisando temporales y reinicio pendiente...' -Nivel PROGRESS
    $temporales = Get-TamanoCarpetasTemporalesCONTPAQi
    $inventario.TemporalesMB = $temporales.MB
    if ($temporales.MB -ge 2048) {
        Add-DiagnosticoHallazgo -Severidad MEDIA -Categoria 'Mantenimiento' -Titulo 'Temporales CONTPAQi elevados' `
            -Evidencia "$($temporales.MB) MB detectados en rutas temporales especificas." `
            -Consecuencia 'Puede aumentar el tiempo de carga y consumir almacenamiento necesario para otras operaciones.' `
            -Accion 'Usa la limpieza segura de Toolbox fuera de procesos activos y conserva evidencia si existe una incidencia.'
    }
    $reinicioPendiente = Test-ReinicioPendiente
    $inventario.ReinicioPendiente = if ($reinicioPendiente) { 'SI' } else { 'NO' }
    if ($reinicioPendiente) {
        Add-DiagnosticoHallazgo -Severidad MEDIA -Categoria 'Windows' -Titulo 'Reinicio de Windows pendiente' `
            -Evidencia 'Windows registra operaciones que requieren reinicio.' `
            -Consecuencia 'Servicios, actualizaciones o reparaciones pueden quedar aplicados parcialmente.' `
            -Accion 'Programa un reinicio controlado y repite el diagnostico antes de escalar la incidencia.'
    }

    Write-Log -Mensaje '[8/8] Correlacionando eventos recientes...' -Nivel PROGRESS
    $eventos = @(Get-EventosCONTPAQiRecientes)
    $inventario.Eventos = @($eventos | Select-Object -First 8 | ForEach-Object {
        $mensaje = (($_.Message -replace '[\r\n]+', ' ') -replace '\s+', ' ').Trim()
        if ($mensaje.Length -gt 240) { $mensaje = $mensaje.Substring(0, 240) + '...' }
        [PSCustomObject]@{ Fecha = $_.TimeCreated; Origen = $_.ProviderName; Nivel = $_.LevelDisplayName; Id = $_.Id; Mensaje = $mensaje }
    })
    if ($eventos.Count -ge 8) {
        Add-DiagnosticoHallazgo -Severidad ALTA -Categoria 'Eventos' -Titulo 'Errores repetidos en Windows' `
            -Evidencia "Se encontraron al menos $($eventos.Count) eventos recientes relacionados con CONTPAQi o SQL." `
            -Consecuencia 'La repeticion indica una causa persistente y no solamente una falla aislada.' `
            -Accion 'Revisa los eventos incluidos en el reporte y atiende primero el origen con mayor recurrencia.'
    } elseif ($eventos.Count -gt 0) {
        Add-DiagnosticoHallazgo -Severidad MEDIA -Categoria 'Eventos' -Titulo 'Eventos recientes relacionados' `
            -Evidencia "Se encontraron $($eventos.Count) evento(s) reciente(s) de CONTPAQi o SQL." `
            -Consecuencia 'Pueden explicar cierres, lentitud o fallas recientes.' `
            -Accion 'Compara la hora del evento con la incidencia reportada antes de aplicar una reparacion.'
    }

    $deduccion = [int](($hallazgos | Measure-Object -Property Peso -Sum).Sum)
    $puntaje = [math]::Max(0, 100 - $deduccion)
    $estado = if ($puntaje -ge 90) { 'SALUDABLE' } elseif ($puntaje -ge 75) { 'ATENCION' } elseif ($puntaje -ge 50) { 'RIESGO' } else { 'CRITICO' }
    return [PSCustomObject]@{
        Generado = Get-Date; Inicio = $inicio; DuracionSegundos = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
        Equipo = $env:COMPUTERNAME; Usuario = "$env:USERDOMAIN\$env:USERNAME"; Perfil = Get-PerfilEquipo
        Puntaje = $puntaje; Estado = $estado
        Hallazgos = @($hallazgos | Sort-Object @{Expression={ switch ($_.Severidad) { 'CRITICA' { 0 }; 'ALTA' { 1 }; 'MEDIA' { 2 }; default { 3 } } }}, Categoria, Titulo)
        Inventario = [PSCustomObject]$inventario
    }
}

function ConvertTo-HtmlSeguroCONTPAQi {
    param([AllowNull()][object]$Valor)
    if ($null -eq $Valor) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Valor)
}

function Get-EdgeExecutableCONTPAQi {
    $candidatos = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe')
    ) | Where-Object { $_ }
    return @($candidatos | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)[0]
}

function Export-DiagnosticoInteligentePdfCONTPAQi {
    param([Parameter(Mandatory)][object]$Diagnostico)
    if (-not (Test-Path -LiteralPath $Script:ReportDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $Script:ReportDirectory -Force -ErrorAction Stop | Out-Null
    }
    $marcaTiempo = $Diagnostico.Generado.ToString('yyyyMMdd_HHmmss')
    $baseNombre = "Diagnostico_CONTPAQi_$($Diagnostico.Equipo)_$marcaTiempo"
    $htmlPath = Join-Path $Script:ReportDirectory ($baseNombre + '.html')
    $pdfPath = Join-Path $Script:ReportDirectory ($baseNombre + '.pdf')
    $logoHtml = ''
    $logoPath = Get-ToolboxAssetPath -FileName 'DS.png'
    if ($logoPath) {
        try {
            $logo64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($logoPath))
            $logoHtml = "<img class='logo' src='data:image/png;base64,$logo64' alt='DS'>"
        } catch { }
    }
    $severityClass = @{ CRITICA = 'critical'; ALTA = 'high'; MEDIA = 'medium'; INFORMATIVA = 'info' }
    $hallazgosHtml = if ($Diagnostico.Hallazgos.Count -eq 0) {
        "<section class='finding healthy'><div class='finding-title'>Sin hallazgos relevantes</div><p>Las pruebas ejecutadas no detectaron alertas. Conserva este reporte como evidencia y valida la operacion funcional con un usuario.</p></section>"
    } else {
        (@($Diagnostico.Hallazgos | ForEach-Object {
            $clase = $severityClass[$_.Severidad]
            "<section class='finding $clase'><div class='finding-head'><span class='pill'>$((ConvertTo-HtmlSeguroCONTPAQi $_.Severidad))</span><span class='category'>$((ConvertTo-HtmlSeguroCONTPAQi $_.Categoria))</span></div><div class='finding-title'>$((ConvertTo-HtmlSeguroCONTPAQi $_.Titulo))</div><div class='finding-grid'><div><b>EVIDENCIA</b><p>$((ConvertTo-HtmlSeguroCONTPAQi $_.Evidencia))</p></div><div><b>CONSECUENCIA</b><p>$((ConvertTo-HtmlSeguroCONTPAQi $_.Consecuencia))</p></div><div><b>ACCION SUGERIDA</b><p>$((ConvertTo-HtmlSeguroCONTPAQi $_.Accion))</p></div></div></section>"
        })) -join "`n"
    }
    $productosHtml = if (@($Diagnostico.Inventario.Productos).Count) { (@($Diagnostico.Inventario.Productos | ForEach-Object { "<li>$((ConvertTo-HtmlSeguroCONTPAQi $_))</li>" })) -join '' } else { '<li>No detectados</li>' }
    $serviciosHtml = (@($Diagnostico.Inventario.Servicios | ForEach-Object {
        $estadoClase = if ($_.Estado -eq 'Running') { 'ok-text' } else { 'bad-text' }
        "<tr><td>$((ConvertTo-HtmlSeguroCONTPAQi $_.Nombre))</td><td>$((ConvertTo-HtmlSeguroCONTPAQi $_.Descripcion))</td><td class='$estadoClase'>$((ConvertTo-HtmlSeguroCONTPAQi $_.Estado))</td><td>$((ConvertTo-HtmlSeguroCONTPAQi $_.Inicio))</td></tr>"
    })) -join ''
    if (-not $serviciosHtml) { $serviciosHtml = "<tr><td colspan='4'>No se detectaron servicios relacionados.</td></tr>" }
    $discosHtml = (@($Diagnostico.Inventario.Discos | ForEach-Object {
        $ocupado = [math]::Max(0, [math]::Min(100, 100 - [double]$_.LibrePorcentaje))
        "<div class='disk'><div class='disk-row'><b>$((ConvertTo-HtmlSeguroCONTPAQi $_.Unidad))</b><span>$($_.LibreGB) GB libres de $($_.TotalGB) GB</span></div><div class='bar'><i style='width:$ocupado%'></i></div><small>$ocupado% utilizado</small></div>"
    })) -join ''
    $eventosHtml = (@($Diagnostico.Inventario.Eventos | ForEach-Object {
        "<tr><td>$($_.Fecha.ToString('dd/MM/yyyy HH:mm'))</td><td>$((ConvertTo-HtmlSeguroCONTPAQi $_.Origen))</td><td>$((ConvertTo-HtmlSeguroCONTPAQi $_.Id))</td><td>$((ConvertTo-HtmlSeguroCONTPAQi $_.Mensaje))</td></tr>"
    })) -join ''
    if (-not $eventosHtml) { $eventosHtml = "<tr><td colspan='4' class='ok-text'>Sin eventos relacionados en el periodo revisado.</td></tr>" }
    $criticas = @($Diagnostico.Hallazgos | Where-Object Severidad -eq 'CRITICA').Count
    $altas = @($Diagnostico.Hallazgos | Where-Object Severidad -eq 'ALTA').Count
    $medias = @($Diagnostico.Hallazgos | Where-Object Severidad -eq 'MEDIA').Count
    $html = @"
<!doctype html><html lang='es'><head><meta charset='utf-8'><title>Diagnostico CONTPAQi</title><style>
@page{size:A4;margin:13mm;background:#07070b}*{box-sizing:border-box}html,body{margin:0;min-height:100%;background:#07070b;color:#e8eaf2;font:12px 'Segoe UI',Arial,sans-serif;-webkit-print-color-adjust:exact;print-color-adjust:exact}.page{min-height:260mm}.header{display:flex;align-items:center;padding:18px 20px;background:linear-gradient(135deg,#0d0d14,#171126);border:1px solid #2a2040;border-bottom:3px solid #7c3aed}.logo{width:54px;height:54px;object-fit:contain;margin-right:16px}.brand h1{font-size:23px;margin:0;color:#a78bfa;letter-spacing:.3px}.brand p{margin:4px 0 0;color:#8990a3}.version{margin-left:auto;color:#a78bfa;background:#211634;padding:7px 11px}.summary{display:grid;grid-template-columns:1.25fr 1fr 1fr 1fr;gap:10px;margin:13px 0}.card{background:#111119;border:1px solid #272735;padding:13px;min-height:76px}.label{font-size:9px;font-weight:700;color:#9298aa;letter-spacing:.8px}.value{font-size:20px;font-weight:800;margin-top:7px;color:#f3f4f6}.purple{color:#9b6cff}.red{color:#ff5d73}.amber{color:#ffbf47}.green{color:#38e08f}.meta{display:grid;grid-template-columns:1fr 1fr;gap:8px;background:#0e0e15;border:1px solid #252533;padding:12px;margin-bottom:14px}.meta div{color:#a7adbd}.meta b{color:#e8eaf2}.section-title{margin:18px 0 9px;padding:8px 10px;color:#a78bfa;background:#141020;border-left:4px solid #7c3aed;font-size:13px;letter-spacing:.4px;break-after:avoid}.finding{background:#101017;border:1px solid #272733;border-left:4px solid #6b7280;margin:0 0 9px;padding:11px 12px;break-inside:avoid}.finding.critical{border-left-color:#ff5d73}.finding.high{border-left-color:#ff8a5b}.finding.medium{border-left-color:#ffbf47}.finding.info,.finding.healthy{border-left-color:#38e08f}.finding-head{display:flex;gap:8px;align-items:center}.pill{font-size:8px;font-weight:800;padding:3px 7px;background:#2a2139;color:#c4b5fd}.category{font-size:9px;color:#9298aa}.finding-title{font-size:14px;font-weight:750;margin:7px 0 8px}.finding-grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px}.finding-grid>div{border-top:1px solid #292938;padding-top:7px}.finding-grid b{font-size:8px;color:#a78bfa}.finding-grid p{margin:4px 0 0;color:#c9cdd8;line-height:1.35}.two-cols{display:grid;grid-template-columns:1fr 1fr;gap:12px}.panel{background:#101017;border:1px solid #272733;padding:10px;break-inside:avoid}.panel h3{font-size:10px;color:#a78bfa;margin:0 0 7px}.panel ul{margin:0;padding-left:16px;font-size:9.5px;line-height:1.2}.panel li{margin:1px 0}.disk{margin:0 0 9px}.disk-row{display:flex;justify-content:space-between;margin-bottom:4px}.bar{height:7px;background:#292938}.bar i{display:block;height:100%;background:linear-gradient(90deg,#6d28d9,#a78bfa)}small{color:#858b9d}table{width:100%;border-collapse:collapse;background:#101017;font-size:9px}th{color:#a78bfa;background:#181522;text-align:left}th,td{border:1px solid #292938;padding:6px;vertical-align:top}td{color:#c9cdd8}.ok-text{color:#38e08f}.bad-text{color:#ff5d73}.footer{margin-top:16px;padding-top:9px;border-top:1px solid #2a2040;color:#858b9d;font-size:9px;text-align:center}.note{background:#151122;border:1px solid #302346;padding:10px;color:#b9becb;line-height:1.4} @media print{html,body{background:#07070b}.page{min-height:auto}}
</style></head><body><main class='page'>
<header class='header'>$logoHtml<div class='brand'><h1>DIAGNOSTICO INTELIGENTE</h1><p>CONTPAQi Toolbox - Evaluacion tecnica de solo lectura</p></div><div class='version'>v$($Script:Version)</div></header>
<section class='summary'><div class='card'><div class='label'>PUNTAJE GENERAL</div><div class='value purple'>$($Diagnostico.Puntaje) / 100</div></div><div class='card'><div class='label'>ESTADO</div><div class='value'>$((ConvertTo-HtmlSeguroCONTPAQi $Diagnostico.Estado))</div></div><div class='card'><div class='label'>CRITICAS / ALTAS</div><div class='value red'>$criticas / $altas</div></div><div class='card'><div class='label'>ADVERTENCIAS</div><div class='value amber'>$medias</div></div></section>
<section class='meta'><div><b>Equipo:</b> $((ConvertTo-HtmlSeguroCONTPAQi $Diagnostico.Equipo))</div><div><b>Perfil:</b> $((ConvertTo-HtmlSeguroCONTPAQi $Diagnostico.Perfil))</div><div><b>Generado:</b> $($Diagnostico.Generado.ToString('dd/MM/yyyy HH:mm:ss'))</div><div><b>Duracion:</b> $($Diagnostico.DuracionSegundos) segundos</div><div><b>Sistema:</b> $((ConvertTo-HtmlSeguroCONTPAQi $Diagnostico.Inventario.Sistema))</div><div><b>Reinicio pendiente:</b> $((ConvertTo-HtmlSeguroCONTPAQi $Diagnostico.Inventario.ReinicioPendiente))</div></section>
<h2 class='section-title'>HALLAZGOS Y RECOMENDACIONES</h2>$hallazgosHtml
<h2 class='section-title'>SERVICIOS RELACIONADOS</h2><table><thead><tr><th>Servicio</th><th>Descripcion</th><th>Estado</th><th>Inicio</th></tr></thead><tbody>$serviciosHtml</tbody></table>
<h2 class='section-title'>INVENTARIO DEL EQUIPO</h2><section class='two-cols'><div class='panel'><h3>PRODUCTOS DETECTADOS</h3><ul>$productosHtml</ul></div><div class='panel'><h3>ALMACENAMIENTO</h3>$discosHtml</div></section>
<h2 class='section-title'>EVENTOS RECIENTES</h2><table><thead><tr><th>Fecha</th><th>Origen</th><th>ID</th><th>Detalle</th></tr></thead><tbody>$eventosHtml</tbody></table>
<h2 class='section-title'>INTERPRETACION</h2><div class='note'>Este reporte recopila evidencia sin modificar configuraciones. Las acciones son recomendaciones tecnicas y deben validarse de acuerdo con el rol del equipo, respaldos disponibles y ventana de mantenimiento. Despues de cualquier correccion, genera un nuevo diagnostico y realiza una prueba funcional dentro de CONTPAQi.</div>
<footer class='footer'>CONTPAQi Toolbox v$($Script:Version) | $($Script:MarcaAgua) | Reporte $baseNombre</footer>
</main></body></html>
"@
    [IO.File]::WriteAllText($htmlPath, $html, [Text.UTF8Encoding]::new($false))
    $edge = Get-EdgeExecutableCONTPAQi
    if (-not $edge) { throw "Microsoft Edge no esta disponible. El reporte HTML quedo guardado en: $htmlPath" }
    $perfilTemporal = Join-Path $env:TEMP ("CONTPAQiToolbox\EdgePdf_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $perfilTemporal -Force -ErrorAction Stop | Out-Null
    $proceso = New-Object Diagnostics.Process
    try {
        $uri = ([Uri]$htmlPath).AbsoluteUri
        $proceso.StartInfo = New-Object Diagnostics.ProcessStartInfo
        $proceso.StartInfo.FileName = $edge
        $proceso.StartInfo.Arguments = "--headless --disable-gpu --no-first-run --no-pdf-header-footer --print-to-pdf-no-header --user-data-dir=`"$perfilTemporal`" --print-to-pdf=`"$pdfPath`" `"$uri`""
        $proceso.StartInfo.UseShellExecute = $false
        $proceso.StartInfo.CreateNoWindow = $true
        if (-not $proceso.Start()) { throw 'Windows no pudo iniciar el generador PDF.' }
        $limite = (Get-Date).AddSeconds(75)
        while (-not $proceso.HasExited -and (Get-Date) -lt $limite) {
            [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100
        }
        if (-not $proceso.HasExited) { try { $proceso.Kill() } catch { }; throw 'La generacion del PDF excedio 75 segundos.' }
        $limiteArchivo = (Get-Date).AddSeconds(8)
        while (-not (Test-Path -LiteralPath $pdfPath -PathType Leaf) -and (Get-Date) -lt $limiteArchivo) {
            [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100
        }
        if (-not (Test-Path -LiteralPath $pdfPath -PathType Leaf) -or (Get-Item -LiteralPath $pdfPath).Length -lt 1000) {
            throw 'Edge no produjo un archivo PDF valido.'
        }
        Remove-Item -LiteralPath $htmlPath -Force -ErrorAction SilentlyContinue
        return $pdfPath
    } finally {
        $proceso.Dispose()
        if (Test-Path -LiteralPath $perfilTemporal) { Remove-Item -LiteralPath $perfilTemporal -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-DiagnosticoInteligenteCONTPAQi {
    Write-Encabezado -Titulo 'DIAGNOSTICO INTELIGENTE' -Subtitulo 'Evaluacion de solo lectura y reporte profesional PDF' -Color 'Magenta'
    Write-Log -Mensaje 'Iniciando revision. No se realizaran cambios en Windows, SQL ni CONTPAQi.' -Nivel INFO
    try {
        $diagnostico = Get-DiagnosticoInteligenteCONTPAQi
        Write-SeccionMenu -Titulo 'RESULTADO PRIORIZADO' -Color $(if ($diagnostico.Puntaje -ge 75) { 'Green' } elseif ($diagnostico.Puntaje -ge 50) { 'Yellow' } else { 'Red' })
        Write-Log -Mensaje "SALUD: $($diagnostico.Puntaje)/100 | $($diagnostico.Estado) | $($diagnostico.Hallazgos.Count) hallazgo(s)" -Nivel $(if ($diagnostico.Puntaje -ge 75) { 'OK' } elseif ($diagnostico.Puntaje -ge 50) { 'WARN' } else { 'ERROR' })
        foreach ($hallazgo in @($diagnostico.Hallazgos | Select-Object -First 12)) {
            $nivel = if ($hallazgo.Severidad -eq 'CRITICA') { 'ERROR' } elseif ($hallazgo.Severidad -in @('ALTA','MEDIA')) { 'WARN' } else { 'INFO' }
            Write-Log -Mensaje "[$($hallazgo.Severidad)] $($hallazgo.Categoria): $($hallazgo.Titulo)" -Nivel $nivel
            Write-Log -Mensaje "Accion: $($hallazgo.Accion)" -Nivel INFO
        }
        Write-Log -Mensaje 'Generando PDF con el estilo visual de Toolbox...' -Nivel PROGRESS
        $pdfPath = Export-DiagnosticoInteligentePdfCONTPAQi -Diagnostico $diagnostico
        Write-Log -Mensaje "Reporte PDF creado: $pdfPath" -Nivel OK
        try { Start-Process -FilePath $pdfPath -ErrorAction Stop | Out-Null } catch { Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$pdfPath`"" | Out-Null }
    } catch {
        Write-Log -Mensaje "No se pudo completar el diagnostico o generar su PDF: $($_.Exception.Message)" -Nivel ERROR
        Write-Log -Mensaje "Carpeta de reportes: $Script:ReportDirectory" -Nivel INFO
    }
}

function Test-PuertoTCP {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$Port,
        [int]$TimeoutMs = 900
    )

    $cliente = New-Object System.Net.Sockets.TcpClient
    $inicio = Get-Date
    $async = $null
    try {
        $async = $cliente.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return [PSCustomObject]@{ Abierto = $false; Milisegundos = $TimeoutMs; Detalle = 'Tiempo agotado' }
        }
        $cliente.EndConnect($async)
        return [PSCustomObject]@{
            Abierto      = $true
            Milisegundos = [math]::Round(((Get-Date) - $inicio).TotalMilliseconds)
            Detalle      = 'Conexion TCP correcta'
        }
    } catch {
        return [PSCustomObject]@{ Abierto = $false; Milisegundos = 0; Detalle = $_.Exception.Message }
    } finally {
        if ($async -and $async.AsyncWaitHandle) { $async.AsyncWaitHandle.Close() }
        $cliente.Close()
    }
}

function Resolve-HostCONTPAQi {
    param([Parameter(Mandatory)][string]$HostName)
    try {
        return @([System.Net.Dns]::GetHostAddresses($HostName) |
            Where-Object { $_.AddressFamily -in @('InterNetwork', 'InterNetworkV6') } |
            ForEach-Object { $_.IPAddressToString } |
            Select-Object -Unique)
    } catch {
        return @()
    }
}

function ConvertTo-HostServidorCONTPAQi {
    param([string]$Valor)
    if ([string]::IsNullOrWhiteSpace($Valor)) { return $null }
    $hostLimpio = $Valor.Trim().Trim('"').Trim("'").Trim()
    $hostLimpio = $hostLimpio -replace '^(?i)(tcp:|np:)', ''
    if ($hostLimpio -match '^[a-z]+://') {
        try { $hostLimpio = ([uri]$hostLimpio).Host } catch { return $null }
    }
    $hostLimpio = $hostLimpio.TrimStart('\').TrimEnd('\')
    if ($hostLimpio.Contains('\')) { $hostLimpio = $hostLimpio.Split('\')[0] }
    if ($hostLimpio -match '^([^,]+),\d+$') { $hostLimpio = $matches[1] }
    if ($hostLimpio -in @('', '0.0.0.0', '255.255.255.255', '(local)', 'local')) { return $null }
    if ($hostLimpio -in @('.', 'localhost', '127.0.0.1', '::1')) { return $env:COMPUTERNAME }
    $ip = $null
    if ([System.Net.IPAddress]::TryParse($hostLimpio, [ref]$ip)) { return $ip.IPAddressToString }
    if ($hostLimpio -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$') { return $null }
    return $hostLimpio
}

function Add-CandidatoServidorCONTPAQi {
    param(
        [Parameter(Mandatory)][hashtable]$Mapa,
        [string]$HostName,
        [Parameter(Mandatory)][string]$Evidencia,
        [int]$Puntos = 10
    )
    $normalizado = ConvertTo-HostServidorCONTPAQi -Valor $HostName
    if (-not $normalizado) { return }
    $clave = $normalizado.ToLowerInvariant()
    if (-not $Mapa.ContainsKey($clave)) {
        $Mapa[$clave] = [PSCustomObject]@{
            Host = $normalizado
            Puntaje = 0
            Confianza = 'Baja'
            Evidencias = @()
            IPs = @()
            PuertosAbiertos = @()
        }
    }
    $candidato = $Mapa[$clave]
    if ($Evidencia -notin $candidato.Evidencias) {
        $candidato.Evidencias += $Evidencia
        $candidato.Puntaje += $Puntos
    }
}

function Find-ServidoresCONTPAQi {
    $mapa = @{}

    # Las instalaciones Terminal guardan el servidor en estas claves de producto.
    $raicesRegistro = @(
        'HKLM:\SOFTWARE\WOW6432Node\Computación en Acción, SA CV',
        'HKLM:\SOFTWARE\Computación en Acción, SA CV',
        'HKCU:\SOFTWARE\Computación en Acción, SA CV',
        'HKLM:\SOFTWARE\WOW6432Node\CONTPAQ i®',
        'HKLM:\SOFTWARE\CONTPAQ i®'
    )
    foreach ($raiz in $raicesRegistro) {
        if (-not (Test-Path -LiteralPath $raiz)) { continue }
        $claves = @()
        $claveRaiz = Get-Item -LiteralPath $raiz -ErrorAction SilentlyContinue
        if ($claveRaiz) { $claves += $claveRaiz }
        $claves += @(Get-ChildItem -LiteralPath $raiz -Recurse -ErrorAction SilentlyContinue)
        foreach ($clave in $claves) {
            foreach ($nombreValor in $clave.GetValueNames()) {
                if ($nombreValor -notmatch '^(?i)(NOMBRESERVIDOR|SERVIDORIP|DIRECCIONIP)$') { continue }
                $valor = [string]$clave.GetValue($nombreValor)
                Add-CandidatoServidorCONTPAQi -Mapa $mapa -HostName $valor -Evidencia "Registro $($clave.PSChildName): $nombreValor" -Puntos 75
            }
        }
    }

    # Archivos documentados por CONTPAQi para la conexion Terminal/Servidor.
    $raicesCompac = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Compac'),
        (Join-Path $env:ProgramFiles 'Compac')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    foreach ($raizCompac in $raicesCompac) {
        foreach ($carpeta in (Get-ChildItem -LiteralPath $raizCompac -Directory -ErrorAction SilentlyContinue)) {
            foreach ($archivoNombre in @('CompacCliente.properties', 'Contpaq.properties')) {
                $archivo = Join-Path $carpeta.FullName $archivoNombre
                if (-not (Test-Path -LiteralPath $archivo -PathType Leaf)) { continue }
                foreach ($linea in (Get-Content -LiteralPath $archivo -ErrorAction SilentlyContinue)) {
                    if ($linea -match '^\s*servidor\.(?:direccionIP|nombre)\s*=\s*([^#;]+?)\s*$') {
                        Add-CandidatoServidorCONTPAQi -Mapa $mapa -HostName $matches[1] -Evidencia "$archivoNombre en $($carpeta.Name)" -Puntos 70
                    }
                }
            }
        }
        $configSaci = Join-Path $raizCompac 'ConfiguradorADD\ConfigurationClient.config'
        if (Test-Path -LiteralPath $configSaci -PathType Leaf) {
            $textoConfig = Get-Content -LiteralPath $configSaci -Raw -ErrorAction SilentlyContinue
            foreach ($coincidencia in [regex]::Matches($textoConfig, '(?i)(?:key|name)="Saci"\s+value="([^"]+)"')) {
                Add-CandidatoServidorCONTPAQi -Mapa $mapa -HostName $coincidencia.Groups[1].Value -Evidencia 'Configuracion activa de SACI' -Puntos 90
            }
        }
    }

    # Conexiones activas de procesos CONTPAQi: evidencia especialmente util
    # cuando la configuracion se movio o quedo obsoleta.
    try {
        $procesos = @((Get-ProcesosCONTPAQi) + (Get-ProcesosPID)) | Sort-Object PID -Unique
        $pids = @($procesos | Select-Object -ExpandProperty PID)
        $puertosCONTPAQi = @(1099, 1138, 1139, 1775, 2003, 9005, 9020, 9042, 9047, 9079, 9080, 9081, 9082, 9083, 9084, 9120, 9147, 1433)
        if ($pids.Count -gt 0 -and (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
            foreach ($conexion in (Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object {
                $_.OwningProcess -in $pids -and $_.RemotePort -in $puertosCONTPAQi -and $_.RemoteAddress -notin @('0.0.0.0', '127.0.0.1', '::1', '::')
            })) {
                $nombreProceso = @($procesos | Where-Object PID -eq $conexion.OwningProcess | Select-Object -First 1 -ExpandProperty Nombre)
                Add-CandidatoServidorCONTPAQi -Mapa $mapa -HostName $conexion.RemoteAddress -Evidencia "Conexion activa $nombreProceso TCP $($conexion.RemotePort)" -Puntos 85
            }
        }
    } catch { }

    # Recursos de red usados por la terminal pueden revelar el nombre del servidor.
    try {
        foreach ($unidad in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=4' -ErrorAction SilentlyContinue)) {
            if ($unidad.ProviderName -match '^\\\\([^\\]+)\\') {
                Add-CandidatoServidorCONTPAQi -Mapa $mapa -HostName $matches[1] -Evidencia "Recurso de red $($unidad.DeviceID)" -Puntos 25
            }
        }
    } catch { }

    # Alias SQL configurados en clientes de 32/64 bits.
    foreach ($rutaAlias in @(
        'HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSSQLServer\Client\ConnectTo',
        'HKCU:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo'
    )) {
        $alias = Get-Item -LiteralPath $rutaAlias -ErrorAction SilentlyContinue
        if (-not $alias) { continue }
        foreach ($nombreAlias in $alias.GetValueNames()) {
            $valorAlias = [string]$alias.GetValue($nombreAlias)
            $partes = @($valorAlias -split ',')
            $servidorAlias = if ($partes.Count -ge 2) { $partes[1] } else { $nombreAlias }
            Add-CandidatoServidorCONTPAQi -Mapa $mapa -HostName $servidorAlias -Evidencia "Alias SQL $nombreAlias" -Puntos 30
        }
    }

    # Si SACI esta instalado realmente como servicio en este equipo, tambien
    # puede tratarse de una instalacion monousuario o del propio servidor.
    $servicioServidor = Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'Saci_CONTPAQi' -or $_.DisplayName -match '(?i)Servidor de Aplicaciones.*CONTPAQ'
    } | Select-Object -First 1
    if ($servicioServidor) {
        Add-CandidatoServidorCONTPAQi -Mapa $mapa -HostName $env:COMPUTERNAME -Evidencia "Servicio local $($servicioServidor.Name)" -Puntos 100
    }

    $preliminares = @($mapa.Values | Sort-Object Puntaje -Descending | Select-Object -First 6)
    $puertosValidar = @(9079, 9080, 9081, 9082, 9047, 9147, 9020, 9120, 9005, 9042, 1433, 1099)
    foreach ($candidato in $preliminares) {
        $direccionesCandidato = @(Resolve-HostCONTPAQi -HostName $candidato.Host)
        $candidato.IPs = @(
            @($direccionesCandidato | Where-Object { $_ -match '^\d{1,3}(?:\.\d{1,3}){3}$' }) +
            @($direccionesCandidato | Where-Object { $_ -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$' }) |
                Select-Object -First 4
        )
        if ($candidato.IPs.Count -gt 0) { $candidato.Puntaje += 8 }
        foreach ($puerto in $puertosValidar) {
            $prueba = Test-PuertoTCP -HostName $candidato.Host -Port $puerto -TimeoutMs 220
            if ($prueba.Abierto) {
                $candidato.PuertosAbiertos += $puerto
                $candidato.Puntaje += 10
            }
            Refresh-Log
        }
        $candidato.PuertosAbiertos = @($candidato.PuertosAbiertos | Select-Object -Unique)
        $pistasConfiguracion = @($candidato.Evidencias | Where-Object { $_ -match '^(Registro|CompacCliente|Contpaq|Configuracion activa|Conexion activa)' }).Count
        if ($candidato.PuertosAbiertos.Count -ge 2) {
            # Un servidor que responde en varios puertos CONTPAQi prevalece
            # sobre referencias antiguas repetidas en archivos de la terminal.
            $candidato.Puntaje += 600
            $candidato.Confianza = 'Alta'
        } elseif ($candidato.PuertosAbiertos.Count -eq 1) {
            $candidato.Puntaje += 250
            $candidato.Confianza = if ($pistasConfiguracion -gt 0) { 'Alta' } else { 'Media' }
        } elseif ($pistasConfiguracion -ge 2 -and $candidato.IPs.Count -gt 0) {
            $candidato.Puntaje = [math]::Min($candidato.Puntaje, 220)
            $candidato.Confianza = 'Media'
        } elseif ($pistasConfiguracion -gt 0) {
            $candidato.Puntaje = [math]::Min($candidato.Puntaje, 120)
            $candidato.Confianza = 'Baja'
        } else {
            $candidato.Confianza = 'Baja'
        }
        Refresh-Log
    }
    return @($preliminares | Sort-Object -Property @{ Expression = 'Puntaje'; Descending = $true }, @{ Expression = 'Host'; Ascending = $true })
}

function Select-ServidorObjetivoCONTPAQi {
    Write-SeccionMenu -Titulo 'DETECCION AUTOMATICA DEL SERVIDOR' -Color 'Cyan'
    Write-Log -Mensaje 'Buscando configuraciones CONTPAQi, conexiones activas, recursos de red y puertos...' -Nivel PROGRESS
    $candidatos = @(Find-ServidoresCONTPAQi)
    $predeterminado = ''
    if ($candidatos.Count -gt 0) {
        $predeterminado = $candidatos[0].Host
        foreach ($candidato in @($candidatos | Select-Object -First 4)) {
            $ips = if ($candidato.IPs.Count -gt 0) { $candidato.IPs[0] } else { 'sin resolucion DNS' }
            $puertos = if ($candidato.PuertosAbiertos.Count -gt 0) { $candidato.PuertosAbiertos -join ', ' } else { 'sin puertos confirmados' }
            Write-Log -Mensaje "$($candidato.Host) | Confianza $($candidato.Confianza) | IP: $ips | Puertos: $puertos | $($candidato.Evidencias.Count) pista(s)" -Nivel $(if ($candidato.Confianza -eq 'Alta') { 'OK' } else { 'INFO' })
        }
        Write-Log -Mensaje "Mejor candidato: $predeterminado. Confirma el dato antes de diagnosticar." -Nivel OK
    } else {
        Write-Log -Mensaje 'No se encontro un servidor guardado en esta terminal.' -Nivel WARN
    }

    if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        $mensaje = if ($predeterminado) { "Servidor detectado: $predeterminado. Confirma o reemplaza:" } else { 'Escribe el nombre o IP del servidor:' }
        return Show-GUIInput -Titulo 'Servidor CONTPAQi' -Mensaje $mensaje -DefaultText $predeterminado
    }
    $mensajeConsola = if ($predeterminado) { " Nombre o IP del servidor [$predeterminado]" } else { ' Nombre o IP del servidor' }
    $capturado = Read-Host $mensajeConsola
    if ([string]::IsNullOrWhiteSpace($capturado)) { return $predeterminado }
    return $capturado.Trim()
}

function Test-HostCONTPAQiEsLocal {
    param([Parameter(Mandatory)][string]$HostName)
    $objetivo = $HostName.Trim().TrimEnd('.')
    if ($objetivo -in @('.', 'localhost', '127.0.0.1', '::1', $env:COMPUTERNAME)) { return $true }
    try {
        $ipsObjetivo = @(Resolve-HostCONTPAQi -HostName $objetivo)
        $ipsLocales = @(Resolve-HostCONTPAQi -HostName $env:COMPUTERNAME) + @('127.0.0.1', '::1')
        return (@($ipsObjetivo | Where-Object { $_ -in $ipsLocales }).Count -gt 0)
    } catch {
        return $false
    }
}

function Get-CategoriaProgramaCONTPAQi {
    param([Parameter(Mandatory)][string]$Nombre)
    return 'Sistema instalado'
}

function Get-FabricanteSistemaCONTPAQi {
    param(
        [Parameter(Mandatory)][string]$Nombre,
        [string]$Editor = ''
    )
    $referencia = "$Nombre $Editor"
    if ($referencia -match '(?i)CONTPAQ|COMPAC|COMPUTACI[ÓO]N EN ACCI[ÓO]N|APPKEY|SACI') { return 'CONTPAQi' }
    if ($referencia -match '(?i)MICROSOFT|SQL SERVER|ODBC DRIVER.*SQL|SQL NATIVE CLIENT') { return 'Microsoft' }
    $editorLimpio = ($Editor -replace '\s+', ' ').Trim()
    if ($editorLimpio) { return $editorLimpio }
    return 'Otros'
}

function Get-FabricanteServicioCONTPAQi {
    param(
        [string]$Nombre,
        [string]$DisplayName,
        [string]$Ruta,
        [bool]$EsMotorSQL
    )
    $referencia = "$Nombre $DisplayName $Ruta"
    if ($EsMotorSQL -or $referencia -match '(?i)SQLSERVERAGENT|SQLBROWSER|SQLWRITER|MICROSOFT SQL') { return 'Microsoft SQL Server' }
    if ($referencia -match '(?i)CONTPAQ|COMPAC|SACI|APPKEY|XMLSERVICE|AUTHSERVER') { return 'CONTPAQi' }
    return 'Otros'
}

function Get-ProgramasRemotosCONTPAQi {
    param([Parameter(Mandatory)][string]$HostName)
    $programas = @()
    foreach ($vista in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        $base = $null
        $uninstall = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $HostName, $vista)
            $uninstall = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            if (-not $uninstall) { continue }
            foreach ($subNombre in $uninstall.GetSubKeyNames()) {
                $sub = $null
                try {
                    $sub = $uninstall.OpenSubKey($subNombre)
                    $nombre = [string]$sub.GetValue('DisplayName')
                    if ([string]::IsNullOrWhiteSpace($nombre)) { continue }
                    if ($nombre -notmatch '(?i)CONTPAQ|COMPAC|APPKEY|SACI|XML\s*EN\s*L[IÍ]NEA|MICROSOFT SQL SERVER|SQL SERVER NATIVE CLIENT|ODBC DRIVER.*SQL') { continue }
                    $editor = ([string]$sub.GetValue('Publisher')).Trim()
                    $categoria = Get-CategoriaProgramaCONTPAQi -Nombre $nombre
                    $programas += [PSCustomObject]@{
                        Nombre = $nombre.Trim()
                        Version = ([string]$sub.GetValue('DisplayVersion')).Trim()
                        Editor = $editor
                        Categoria = $categoria
                        Fabricante = Get-FabricanteSistemaCONTPAQi -Nombre $nombre -Editor $editor
                    }
                } finally {
                    if ($sub) { $sub.Close() }
                }
            }
        } finally {
            if ($uninstall) { $uninstall.Close() }
            if ($base) { $base.Close() }
        }
    }
    return @($programas | Sort-Object Nombre, Version -Unique)
}

function Get-ServiciosRemotosCONTPAQi {
    param([Parameter(Mandatory)][string]$HostName)
    $estados = @{}
    try {
        foreach ($servicio in (Get-Service -ComputerName $HostName -ErrorAction Stop)) {
            $estados[$servicio.Name] = [string]$servicio.Status
        }
    } catch { }

    $resultado = @()
    $base = $null
    $raiz = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $HostName, [Microsoft.Win32.RegistryView]::Registry64)
        $raiz = $base.OpenSubKey('SYSTEM\CurrentControlSet\Services')
        if (-not $raiz) { return @() }
        foreach ($nombre in $raiz.GetSubKeyNames()) {
            $sub = $null
            try {
                $sub = $raiz.OpenSubKey($nombre)
                $display = [string]$sub.GetValue('DisplayName')
                $imagen = [string]$sub.GetValue('ImagePath')
                $texto = "$nombre $display $imagen"
                $esMotorSQL = ($nombre -eq 'MSSQLSERVER' -or $nombre -match '^MSSQL\$[^$]+$')
                if (-not $esMotorSQL -and $texto -notmatch '(?i)CONTPAQ|COMPAC|SACI|APPKEY|XMLSERVICE|AUTHSERVER|SQLSERVERAGENT|SQLBROWSER|SQLWRITER') { continue }
                $inicio = switch ([int]$sub.GetValue('Start', 3)) {
                    2 { 'Automatico' }
                    3 { 'Manual' }
                    4 { 'Deshabilitado' }
                    default { 'Otro' }
                }
                $resultado += [PSCustomObject]@{
                    Nombre = $nombre
                    DisplayName = $(if ($display) { $display } else { $nombre })
                    Estado = $(if ($estados.ContainsKey($nombre)) { $estados[$nombre] } else { 'No consultado' })
                    Inicio = $inicio
                    ImagePath = $imagen
                    EsMotorSQL = $esMotorSQL
                    Fabricante = Get-FabricanteServicioCONTPAQi -Nombre $nombre -DisplayName $display -Ruta $imagen -EsMotorSQL $esMotorSQL
                }
            } finally {
                if ($sub) { $sub.Close() }
            }
        }
    } finally {
        if ($raiz) { $raiz.Close() }
        if ($base) { $base.Close() }
    }
    return @($resultado | Sort-Object Nombre -Unique)
}

function Get-InstanciasSQLRemotasCONTPAQi {
    param([Parameter(Mandatory)][string]$HostName)
    $resultado = @()
    $base = $null
    $instancias = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $HostName, [Microsoft.Win32.RegistryView]::Registry64)
        $instancias = $base.OpenSubKey('SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL')
        if (-not $instancias) { return @() }
        foreach ($nombre in $instancias.GetValueNames()) {
            $id = [string]$instancias.GetValue($nombre)
            $setup = $null
            $actual = $null
            try {
                $setup = $base.OpenSubKey("SOFTWARE\Microsoft\Microsoft SQL Server\$id\Setup")
                $actual = $base.OpenSubKey("SOFTWARE\Microsoft\Microsoft SQL Server\$id\MSSQLServer\CurrentVersion")
                $version = if ($setup) { [string]$setup.GetValue('Version') } else { '' }
                if ([string]::IsNullOrWhiteSpace($version) -and $actual) { $version = [string]$actual.GetValue('CurrentVersion') }
                $parche = if ($setup) { [string]$setup.GetValue('PatchLevel') } else { '' }
                $edicion = if ($setup) { [string]$setup.GetValue('Edition') } else { '' }
                $resultado += [PSCustomObject]@{
                    Instancia = $(if ($nombre -eq 'MSSQLSERVER') { $HostName } else { "$HostName\$nombre" })
                    Servicio = $(if ($nombre -eq 'MSSQLSERVER') { 'MSSQLSERVER' } else { "MSSQL`$$nombre" })
                    Version = $(if ($parche) { $parche } else { $version })
                    Edicion = $edicion
                }
            } finally {
                if ($actual) { $actual.Close() }
                if ($setup) { $setup.Close() }
            }
        }
    } finally {
        if ($instancias) { $instancias.Close() }
        if ($base) { $base.Close() }
    }
    return @($resultado | Sort-Object Instancia -Unique)
}

function Get-DatosWindowsRemotosCONTPAQi {
    param([Parameter(Mandatory)][string]$HostName)
    $base = $null
    $clave = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $HostName, [Microsoft.Win32.RegistryView]::Registry64)
        $clave = $base.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion')
        if (-not $clave) { return $null }
        $version = [string]$clave.GetValue('DisplayVersion')
        if (-not $version) { $version = [string]$clave.GetValue('ReleaseId') }
        return [PSCustomObject]@{
            Producto = [string]$clave.GetValue('ProductName')
            Version = $version
            Compilacion = [string]$clave.GetValue('CurrentBuildNumber')
        }
    } finally {
        if ($clave) { $clave.Close() }
        if ($base) { $base.Close() }
    }
}

function Get-InventarioServidorCONTPAQi {
    param([Parameter(Mandatory)][string]$HostName)
    $esLocal = Test-HostCONTPAQiEsLocal -HostName $HostName
    if ($esLocal) {
        $programas = @(Get-ProgramasInstalados | Where-Object {
            $_.DisplayName -match '(?i)CONTPAQ|COMPAC|APPKEY|SACI|XML\s*EN\s*L[IÍ]NEA|MICROSOFT SQL SERVER|SQL SERVER NATIVE CLIENT|ODBC DRIVER.*SQL'
        } | ForEach-Object {
            [PSCustomObject]@{
                Nombre = $_.DisplayName
                Version = $_.DisplayVersion
                Editor = $_.Publisher
                Categoria = Get-CategoriaProgramaCONTPAQi -Nombre $_.DisplayName
                Fabricante = Get-FabricanteSistemaCONTPAQi -Nombre $_.DisplayName -Editor $_.Publisher
            }
        } | Sort-Object Nombre, Version -Unique)
        $servicios = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -eq 'MSSQLSERVER' -or $_.Name -match '^MSSQL\$[^$]+$' -or "$($_.Name) $($_.DisplayName) $($_.PathName)" -match '(?i)CONTPAQ|COMPAC|SACI|APPKEY|XMLSERVICE|AUTHSERVER|SQLSERVERAGENT|SQLBROWSER|SQLWRITER'
        } | ForEach-Object {
            [PSCustomObject]@{
                Nombre = $_.Name
                DisplayName = $_.DisplayName
                Estado = $_.State
                Inicio = $_.StartMode
                ImagePath = $_.PathName
                EsMotorSQL = ($_.Name -eq 'MSSQLSERVER' -or $_.Name -match '^MSSQL\$[^$]+$')
                Fabricante = Get-FabricanteServicioCONTPAQi -Nombre $_.Name -DisplayName $_.DisplayName -Ruta $_.PathName -EsMotorSQL ($_.Name -eq 'MSSQLSERVER' -or $_.Name -match '^MSSQL\$[^$]+$')
            }
        } | Sort-Object Nombre -Unique)
        $sql = @()
        foreach ($motor in (Get-ServiciosMotorSQL)) {
            $instanciaLocal = Get-NombreInstanciaSQL -NombreServicio $motor.Name
            $prueba = if ($motor.Status -eq 'Running') { Test-ConexionSQLLocal -Instancia $instanciaLocal -TimeoutSegundos 4 } else { $null }
            $sql += [PSCustomObject]@{
                Instancia = $(if ($instanciaLocal -eq '.') { $env:COMPUTERNAME } else { "$env:COMPUTERNAME$($instanciaLocal.Substring(1))" })
                Servicio = $motor.Name
                Version = $(if ($prueba -and $prueba.Correcto) { $prueba.Version } else { 'No consultada' })
                Edicion = ''
            }
        }
        $so = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $windows = if ($so) { [PSCustomObject]@{ Producto = $so.Caption; Version = $so.Version; Compilacion = $so.BuildNumber } } else { $null }
        return [PSCustomObject]@{ Acceso = $true; EsLocal = $true; Windows = $windows; Programas = $programas; Servicios = $servicios; SQL = $sql; Error = $null }
    }

    $rpc = Test-PuertoTCP -HostName $HostName -Port 135 -TimeoutMs 900
    $smb = Test-PuertoTCP -HostName $HostName -Port 445 -TimeoutMs 900
    if (-not $rpc.Abierto -and -not $smb.Abierto) {
        return [PSCustomObject]@{ Acceso = $false; EsLocal = $false; Windows = $null; Programas = @(); Servicios = @(); SQL = @(); Error = 'Los puertos administrativos RPC/SMB (135/445) no responden; no es posible consultar el registro remoto.' }
    }
    try {
        $windows = Get-DatosWindowsRemotosCONTPAQi -HostName $HostName
        $programas = @(Get-ProgramasRemotosCONTPAQi -HostName $HostName)
        $servicios = @(Get-ServiciosRemotosCONTPAQi -HostName $HostName)
        $sql = @(Get-InstanciasSQLRemotasCONTPAQi -HostName $HostName)
        return [PSCustomObject]@{ Acceso = $true; EsLocal = $false; Windows = $windows; Programas = $programas; Servicios = $servicios; SQL = $sql; Error = $null }
    } catch {
        return [PSCustomObject]@{ Acceso = $false; EsLocal = $false; Windows = $null; Programas = @(); Servicios = @(); SQL = @(); Error = $_.Exception.Message }
    }
}

function Write-InventarioServidorCONTPAQi {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [int[]]$PuertosAbiertos = @(),
        [AllowNull()][object]$InventarioDetectado = $null
    )
    Write-SeccionMenu -Titulo "INVENTARIO DEL SERVIDOR $HostName" -Color 'Magenta'
    Write-Log -Mensaje 'Consultando registro, sistemas instalados, servicios e instancias SQL...' -Nivel PROGRESS
    $inventario = if ($InventarioDetectado) { $InventarioDetectado } else { Get-InventarioServidorCONTPAQi -HostName $HostName }
    if (-not $inventario.Acceso) {
        $detalle = ($inventario.Error -replace '[\r\n]+', ' ' -replace '\s+', ' ').Trim()
        if ($detalle.Length -gt 260) { $detalle = $detalle.Substring(0, 260) + '...' }
        Write-Log -Mensaje 'El servidor responde, pero Windows no permitio leer su inventario administrativo.' -Nivel WARN
        if ($detalle) { Write-Log -Mensaje "Detalle: $detalle" -Nivel INFO }
        Write-Log -Mensaje 'Usa una cuenta administradora del servidor y habilita temporalmente Registro remoto/RPC, o ejecuta el Toolbox directamente en ese servidor.' -Nivel INFO
        if (1433 -in $PuertosAbiertos) {
            $sqlDirecto = Test-ConexionSQLLocal -Instancia $HostName -TimeoutSegundos 4
            if ($sqlDirecto.Correcto) {
                Write-Log -Mensaje "SQL confirmado por conexion: $($sqlDirecto.Servidor) | Version $($sqlDirecto.Version)" -Nivel OK
            } else {
                Write-Log -Mensaje 'SQL responde por red, pero la cuenta actual no pudo consultar su version.' -Nivel INFO
            }
        }
    } else {
        Write-Log -Mensaje $(if ($inventario.EsLocal) { 'Inventario local disponible.' } else { 'Inventario remoto autorizado correctamente.' }) -Nivel OK
        if ($inventario.Windows) {
            Write-Log -Mensaje "Windows: $($inventario.Windows.Producto) | Version $($inventario.Windows.Version) | Build $($inventario.Windows.Compilacion)" -Nivel INFO
        }
        $sistemas = @($inventario.Programas)
        if ($sistemas.Count -eq 0) { Write-Log -Mensaje 'No se encontraron sistemas CONTPAQi registrados.' -Nivel WARN }
        $gruposSistemas = @($sistemas | Group-Object Fabricante | Sort-Object Name)
        foreach ($grupo in $gruposSistemas) {
            Write-Log -Mensaje "SISTEMAS - $($grupo.Name.ToUpper()) ($($grupo.Count))" -Nivel INFO
            foreach ($producto in @($grupo.Group | Sort-Object Nombre, Version)) {
                $version = if ($producto.Version) { $producto.Version } else { 'N/D' }
                Write-Log -Mensaje "Sistema: $($producto.Nombre) | Version $version" -Nivel OK
            }
        }
        $gruposServicios = @($inventario.Servicios | Group-Object Fabricante | Sort-Object Name)
        foreach ($grupo in $gruposServicios) {
            Write-Log -Mensaje "SERVICIOS - $($grupo.Name.ToUpper()) ($($grupo.Count))" -Nivel INFO
            foreach ($servicio in @($grupo.Group | Sort-Object Nombre)) {
                $nivel = if ($servicio.Estado -in @('Running', 'En ejecucion')) { 'OK' } elseif ($servicio.Estado -eq 'No consultado') { 'INFO' } else { 'WARN' }
                Write-Log -Mensaje "Servicio: $($servicio.Nombre) | $($servicio.Estado) | Inicio $($servicio.Inicio)" -Nivel $nivel
            }
        }
        if ($inventario.SQL.Count -gt 0) { Write-Log -Mensaje "INSTANCIAS SQL - MICROSOFT ($($inventario.SQL.Count))" -Nivel INFO }
        foreach ($instancia in $inventario.SQL) {
            $version = if ($instancia.Version) { $instancia.Version } else { 'N/D' }
            $edicion = if ($instancia.Edicion) { " | $($instancia.Edicion)" } else { '' }
            Write-Log -Mensaje "SQL: $($instancia.Instancia) | Version $version$edicion" -Nivel OK
        }
        $resumenFabricantes = @($gruposSistemas | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ' | '
        Write-Log -Mensaje "Resumen sistemas: $resumenFabricantes" -Nivel INFO
        Write-Log -Mensaje "Resumen tecnico: $($inventario.Servicios.Count) servicio(s), $($inventario.SQL.Count) instancia(s) SQL." -Nivel INFO
    }

    if ($PuertosAbiertos.Count -gt 0) {
        $probables = @()
        if (@($PuertosAbiertos | Where-Object { $_ -in @(9047, 9147) }).Count) { $probables += 'Contabilidad/Bancos' }
        if (@($PuertosAbiertos | Where-Object { $_ -in @(9020, 9120) }).Count) { $probables += 'Comercial/Factura Electronica' }
        if (9005 -in $PuertosAbiertos) { $probables += 'Nominas' }
        if (9042 -in $PuertosAbiertos) { $probables += 'XML en Linea' }
        if (@($PuertosAbiertos | Where-Object { $_ -in @(9079, 9080) }).Count) { $probables += 'SACI/Servidor de Aplicaciones' }
        if (@($PuertosAbiertos | Where-Object { $_ -in @(9081, 9082) }).Count) { $probables += 'Administrador de Documentos Digitales' }
        if (1433 -in $PuertosAbiertos) { $probables += 'SQL Server en puerto estatico' }
        if ($probables.Count -gt 0) {
            Write-Log -Mensaje "Servicios probables por puertos: $(($probables | Select-Object -Unique) -join ', ')." -Nivel INFO
            Write-Log -Mensaje 'La deteccion por puerto es una pista de red; el inventario de Windows es el que confirma producto y version.' -Nivel INFO
        }
    }
}

function Get-InfraestructuraServidorCONTPAQi {
    param([Parameter(Mandatory)][string]$HostName)
    $sesionCim = $null
    try {
        $argumentosCim = @{ ErrorAction = 'Stop' }
        if (-not (Test-HostCONTPAQiEsLocal -HostName $HostName)) {
            $opcionesCim = New-CimSessionOption -Protocol Dcom
            $sesionCim = New-CimSession -ComputerName $HostName -SessionOption $opcionesCim -OperationTimeoutSec 7 -ErrorAction Stop
            $argumentosCim.CimSession = $sesionCim
        }
        $so = Get-CimInstance -ClassName Win32_OperatingSystem @argumentosCim
        $equipo = Get-CimInstance -ClassName Win32_ComputerSystem @argumentosCim
        $procesadores = @(Get-CimInstance -ClassName Win32_Processor @argumentosCim)
        $discos = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' @argumentosCim)
        $red = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' @argumentosCim)
        $recursos = @(Get-CimInstance -ClassName Win32_Share @argumentosCim | Where-Object { $_.Name -notmatch '\$$' } | Select-Object -First 30)
        return [PSCustomObject]@{
            Acceso = $true
            Error = $null
            Nombre = $equipo.Name
            Dominio = $equipo.Domain
            Fabricante = $equipo.Manufacturer
            Modelo = $equipo.Model
            RAMGB = [math]::Round([double]$equipo.TotalPhysicalMemory / 1GB, 1)
            SistemaOperativo = $so.Caption
            VersionSO = $so.Version
            BuildSO = $so.BuildNumber
            UltimoArranque = $so.LastBootUpTime
            Procesadores = $procesadores
            Discos = $discos
            Red = $red
            Recursos = $recursos
        }
    } catch {
        return [PSCustomObject]@{ Acceso = $false; Error = $_.Exception.Message }
    } finally {
        if ($sesionCim) { Remove-CimSession -CimSession $sesionCim -ErrorAction SilentlyContinue }
    }
}

function Show-AnalisisProfundoServidorCONTPAQi {
    Write-Encabezado -Titulo 'ANALISIS PROFUNDO DEL SERVIDOR' -Subtitulo 'Deteccion, conectividad, sistemas, servicios, infraestructura y SQL' -Color 'Magenta'
    $inicio = Get-Date
    $hostObjetivo = Select-ServidorObjetivoCONTPAQi
    if ([string]::IsNullOrWhiteSpace($hostObjetivo)) {
        Write-Log -Mensaje 'Analisis del servidor cancelado.' -Nivel WARN
        return
    }
    $hostObjetivo = ConvertTo-HostServidorCONTPAQi -Valor $hostObjetivo
    if (-not $hostObjetivo) {
        Write-Log -Mensaje 'El nombre o IP indicado no es valido.' -Nivel ERROR
        return
    }

    Write-SeccionMenu -Titulo "1. IDENTIDAD Y CONECTIVIDAD - $hostObjetivo" -Color 'Cyan'
    $direcciones = @(Resolve-HostCONTPAQi -HostName $hostObjetivo)
    if ($direcciones.Count -eq 0) {
        Write-Log -Mensaje "No fue posible resolver $hostObjetivo por DNS." -Nivel ERROR
        return
    }
    $ipv4 = @($direcciones | Where-Object { $_ -match '^\d{1,3}(?:\.\d{1,3}){3}$' })
    Write-Log -Mensaje "Servidor: $hostObjetivo | IP: $(if ($ipv4.Count) { $ipv4 -join ', ' } else { $direcciones[0] })" -Nivel OK

    $catalogoPuertos = @(
        @{ Puerto = 135;  Uso = 'Administracion remota RPC' },
        @{ Puerto = 445;  Uso = 'SMB / inventario administrativo' },
        @{ Puerto = 3389; Uso = 'Escritorio remoto' },
        @{ Puerto = 1099; Uso = 'Servidor de aplicaciones legado' },
        @{ Puerto = 1138; Uso = 'Servidor de aplicaciones alterno' },
        @{ Puerto = 1139; Uso = 'Servidor de aplicaciones alterno' },
        @{ Puerto = 1775; Uso = 'Servidor de aplicaciones alterno' },
        @{ Puerto = 2003; Uso = 'Servidor de aplicaciones alterno' },
        @{ Puerto = 9005; Uso = 'Licenciamiento Nominas' },
        @{ Puerto = 9020; Uso = 'Licenciamiento Comercial / Factura' },
        @{ Puerto = 9042; Uso = 'XML en Linea' },
        @{ Puerto = 9047; Uso = 'Licenciamiento Contabilidad / Bancos' },
        @{ Puerto = 9079; Uso = 'SACI SSL' },
        @{ Puerto = 9080; Uso = 'SACI' },
        @{ Puerto = 9081; Uso = 'Administrador de Documentos Digitales' },
        @{ Puerto = 9082; Uso = 'Administrador de Documentos Digitales SSL' },
        @{ Puerto = 9083; Uso = 'SSCI' },
        @{ Puerto = 9084; Uso = 'SSCI SSL' },
        @{ Puerto = 9120; Uso = 'AuthServer Comercial / Factura' },
        @{ Puerto = 9147; Uso = 'AuthServer Contabilidad / Bancos' },
        @{ Puerto = 1433; Uso = 'SQL Server TCP estatico' }
    )
    $puertosAbiertos = @()
    foreach ($item in $catalogoPuertos) {
        $prueba = Test-PuertoTCP -HostName $hostObjetivo -Port $item.Puerto -TimeoutMs 350
        if ($prueba.Abierto) {
            $puertosAbiertos += $item.Puerto
            Write-Log -Mensaje "TCP $($item.Puerto) abierto | $($item.Uso) | $($prueba.Milisegundos) ms" -Nivel OK
        }
        Refresh-Log
    }
    Write-Log -Mensaje "Puertos confirmados: $($puertosAbiertos.Count) de $($catalogoPuertos.Count)." -Nivel $(if ($puertosAbiertos.Count) { 'OK' } else { 'WARN' })

    Write-SeccionMenu -Titulo '2. SISTEMAS, SERVICIOS E INSTANCIAS' -Color 'Magenta'
    $inventario = Get-InventarioServidorCONTPAQi -HostName $hostObjetivo
    Write-InventarioServidorCONTPAQi -HostName $hostObjetivo -PuertosAbiertos $puertosAbiertos -InventarioDetectado $inventario

    Write-SeccionMenu -Titulo '3. INFRAESTRUCTURA DEL SERVIDOR' -Color 'Yellow'
    $infraestructura = Get-InfraestructuraServidorCONTPAQi -HostName $hostObjetivo
    if ($infraestructura.Acceso) {
        $horasActivo = [math]::Round(((Get-Date) - [datetime]$infraestructura.UltimoArranque).TotalHours, 1)
        Write-Log -Mensaje "Equipo: $($infraestructura.Nombre) | Dominio: $($infraestructura.Dominio)" -Nivel OK
        Write-Log -Mensaje "Hardware: $($infraestructura.Fabricante) $($infraestructura.Modelo) | RAM: $($infraestructura.RAMGB) GB" -Nivel INFO
        Write-Log -Mensaje "Windows: $($infraestructura.SistemaOperativo) | $($infraestructura.VersionSO) | Build $($infraestructura.BuildSO)" -Nivel INFO
        Write-Log -Mensaje "Ultimo arranque: $([datetime]$infraestructura.UltimoArranque) | Activo: $horasActivo horas" -Nivel INFO
        foreach ($cpu in $infraestructura.Procesadores) {
            Write-Log -Mensaje "CPU: $($cpu.Name.Trim()) | $($cpu.NumberOfCores) nucleos / $($cpu.NumberOfLogicalProcessors) logicos" -Nivel INFO
        }
        foreach ($disco in $infraestructura.Discos) {
            $libreGB = [math]::Round([double]$disco.FreeSpace / 1GB, 1)
            $totalGB = [math]::Round([double]$disco.Size / 1GB, 1)
            $porcentaje = if ([double]$disco.Size -gt 0) { [math]::Round(([double]$disco.FreeSpace / [double]$disco.Size) * 100, 1) } else { 0 }
            Write-Log -Mensaje "Disco $($disco.DeviceID) | $libreGB GB libres de $totalGB GB ($porcentaje%)" -Nivel $(if ($porcentaje -ge 15) { 'OK' } else { 'WARN' })
        }
        foreach ($adaptador in $infraestructura.Red) {
            $ipsAdaptador = @($adaptador.IPAddress | Where-Object { $_ -match '^\d{1,3}(?:\.\d{1,3}){3}$' }) -join ', '
            if ($ipsAdaptador) { Write-Log -Mensaje "Red: $($adaptador.Description) | IP $ipsAdaptador | DNS $($adaptador.DNSServerSearchOrder -join ', ')" -Nivel INFO }
        }
        foreach ($recurso in $infraestructura.Recursos) {
            Write-Log -Mensaje "Recurso compartido: \\$hostObjetivo\$($recurso.Name) | $($recurso.Path)" -Nivel INFO
        }
    } else {
        Write-Log -Mensaje "No se pudo obtener hardware, discos y red por CIM/DCOM: $($infraestructura.Error)" -Nivel WARN
    }

    Write-SeccionMenu -Titulo '4. SESIONES DEL SERVIDOR' -Color 'Cyan'
    try {
        $salidaSesiones = @(& quser.exe "/server:$hostObjetivo" 2>&1)
        if ($LASTEXITCODE -eq 0 -and $salidaSesiones.Count -gt 1) {
            $sesiones = @($salidaSesiones | Select-Object -Skip 1 | Where-Object { $_.ToString().Trim() })
            Write-Log -Mensaje "Sesiones RDP detectadas: $($sesiones.Count)." -Nivel INFO
            foreach ($sesion in @($sesiones | Select-Object -First 15)) {
                Write-Log -Mensaje (($sesion.ToString() -replace '\s+', ' ').Trim()) -Nivel INFO
            }
        } else {
            Write-Log -Mensaje 'No se detectaron sesiones RDP o la consulta remota no fue autorizada.' -Nivel INFO
        }
    } catch {
        Write-Log -Mensaje 'No fue posible consultar sesiones RDP del servidor.' -Nivel INFO
    }

    Write-SeccionMenu -Titulo '5. BASES DE DATOS SQL' -Color 'Green'
    $instanciasRevisar = @()
    if ($inventario.Acceso) { $instanciasRevisar += @($inventario.SQL | Select-Object -ExpandProperty Instancia) }
    if ($instanciasRevisar.Count -eq 0 -and 1433 -in $puertosAbiertos) { $instanciasRevisar += $hostObjetivo }
    $instanciasRevisar = @($instanciasRevisar | Where-Object { $_ } | Select-Object -Unique)
    if ($instanciasRevisar.Count -eq 0) {
        Write-Log -Mensaje 'No se pudo identificar una instancia SQL consultable.' -Nivel WARN
    }
    foreach ($instancia in $instanciasRevisar) {
        $conexion = Test-ConexionSQLLocal -Instancia $instancia -TimeoutSegundos 5
        if (-not $conexion.Correcto) {
            Write-Log -Mensaje "$instancia no permite inventario SQL con la cuenta actual: $($conexion.Error)" -Nivel WARN
            continue
        }
        Write-Log -Mensaje "$instancia | SQL $($conexion.Version) | Conexion integrada correcta" -Nivel OK
        try {
            $bases = @(Get-InventarioBasesSQL -Instancia $instancia)
            if ($bases.Count -eq 0) { Write-Log -Mensaje 'Sin bases de datos de usuario visibles.' -Nivel INFO }
            foreach ($base in $bases) {
                $ultimo = if ($base.UltimoRespaldoCompleto -and $base.UltimoRespaldoCompleto -ne [DBNull]::Value) { ([datetime]$base.UltimoRespaldoCompleto).ToString('dd/MM/yyyy HH:mm') } else { 'Sin registro' }
                Write-Log -Mensaje "Base: $($base.Nombre) | $($base.Estado) | $($base.TamanoMB) MB | Recuperacion $($base.Recuperacion) | Respaldo: $ultimo" -Nivel $(if ($base.Estado -eq 'ONLINE') { 'OK' } else { 'WARN' })
            }
        } catch {
            Write-Log -Mensaje "No se pudo consultar bases en $($instancia): $($_.Exception.Message)" -Nivel WARN
        }
    }

    $duracion = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    Write-Separador -Color 'Green'
    Write-Log -Mensaje "ANALISIS DEL SERVIDOR COMPLETADO en $duracion segundos | $hostObjetivo | $($puertosAbiertos.Count) puerto(s) confirmado(s)." -Nivel OK
    Write-Log -Mensaje 'El analisis fue de solo lectura; no se modificaron servicios, sesiones ni bases de datos.' -Nivel INFO
}

function Get-CatalogoConectividadCONTPAQi {
    return @(
        [PSCustomObject]@{ Puerto = 135;  Grupo = 'Administracion'; Uso = 'RPC / administracion remota' },
        [PSCustomObject]@{ Puerto = 445;  Grupo = 'Administracion'; Uso = 'SMB / recursos e inventario' },
        [PSCustomObject]@{ Puerto = 1099; Grupo = 'SACI/ADD'; Uso = 'Servidor de aplicaciones legado' },
        [PSCustomObject]@{ Puerto = 1138; Grupo = 'SACI/ADD'; Uso = 'Servidor de aplicaciones alterno' },
        [PSCustomObject]@{ Puerto = 1139; Grupo = 'SACI/ADD'; Uso = 'Servidor de aplicaciones alterno' },
        [PSCustomObject]@{ Puerto = 1775; Grupo = 'SACI/ADD'; Uso = 'Servidor de aplicaciones alterno' },
        [PSCustomObject]@{ Puerto = 2003; Grupo = 'SACI/ADD'; Uso = 'Servidor de aplicaciones alterno' },
        [PSCustomObject]@{ Puerto = 9005; Grupo = 'Nominas'; Uso = 'Licenciamiento Nominas' },
        [PSCustomObject]@{ Puerto = 9020; Grupo = 'Comercial/Factura'; Uso = 'Licenciamiento Comercial / Factura' },
        [PSCustomObject]@{ Puerto = 9042; Grupo = 'XML en Linea'; Uso = 'Servicio XML en Linea' },
        [PSCustomObject]@{ Puerto = 9047; Grupo = 'Contabilidad/Bancos'; Uso = 'Licenciamiento Contabilidad / Bancos' },
        [PSCustomObject]@{ Puerto = 9079; Grupo = 'SACI/ADD'; Uso = 'SACI SSL' },
        [PSCustomObject]@{ Puerto = 9080; Grupo = 'SACI/ADD'; Uso = 'SACI' },
        [PSCustomObject]@{ Puerto = 9081; Grupo = 'SACI/ADD'; Uso = 'Administrador de Documentos Digitales' },
        [PSCustomObject]@{ Puerto = 9082; Grupo = 'SACI/ADD'; Uso = 'Administrador de Documentos Digitales SSL' },
        [PSCustomObject]@{ Puerto = 9083; Grupo = 'SACI/ADD'; Uso = 'SSCI' },
        [PSCustomObject]@{ Puerto = 9084; Grupo = 'SACI/ADD'; Uso = 'SSCI SSL' },
        [PSCustomObject]@{ Puerto = 9120; Grupo = 'Comercial/Factura'; Uso = 'AuthServer Comercial / Factura' },
        [PSCustomObject]@{ Puerto = 9147; Grupo = 'Contabilidad/Bancos'; Uso = 'AuthServer Contabilidad / Bancos' },
        [PSCustomObject]@{ Puerto = 1433; Grupo = 'SQL'; Uso = 'SQL Server TCP estatico' }
    )
}

function Get-GruposConectividadEsperadosCONTPAQi {
    $productos = @(Get-ProgramasInstalados | Select-Object -ExpandProperty DisplayName)
    $texto = $productos -join ' | '
    $grupos = @()
    if ($texto -match '(?i)contabilidad|bancos') { $grupos += 'Contabilidad/Bancos' }
    if ($texto -match '(?i)comercial|factura|adminpaq') { $grupos += 'Comercial/Factura' }
    if ($texto -match '(?i)n[oó]minas') { $grupos += 'Nominas' }
    if ($texto -match '(?i)XML\s*en\s*l[ií]nea') { $grupos += 'XML en Linea' }
    if ($texto -match '(?i)CONTPAQ|COMPAC|SACI|APPKEY') { $grupos += @('SACI/ADD', 'SQL') }
    return @($grupos | Select-Object -Unique)
}

function Get-EstadoRedLocalResponsive {
    $codigo = @'
$adaptadores = @()
try {
    $adaptadores = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -ErrorAction Stop | ForEach-Object {
        [PSCustomObject]@{
            Descripcion = $_.Description
            DHCP = [bool]$_.DHCPEnabled
            IPs = @($_.IPAddress)
            Mascara = @($_.IPSubnet)
            Gateways = @($_.DefaultIPGateway)
            DNS = @($_.DNSServerSearchOrder)
            MAC = $_.MACAddress
        }
    })
} catch { }
$perfiles = @()
try {
    if (Get-Command Get-NetConnectionProfile -ErrorAction SilentlyContinue) {
        $perfiles = @(Get-NetConnectionProfile -ErrorAction Stop | ForEach-Object {
            [PSCustomObject]@{ Interfaz = $_.InterfaceAlias; Categoria = $_.NetworkCategory; IPv4 = $_.IPv4Connectivity; IPv6 = $_.IPv6Connectivity }
        })
    }
} catch { }
$firewall = @()
try {
    if (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
        $firewall = @(Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object {
            [PSCustomObject]@{ Perfil = $_.Name; Habilitado = [bool]$_.Enabled; Entrada = $_.DefaultInboundAction; Salida = $_.DefaultOutboundAction }
        })
    }
} catch { }
$rutas = @()
try {
    if (Get-Command Get-NetRoute -ErrorAction SilentlyContinue) {
        $rutas = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
            Sort-Object RouteMetric, InterfaceMetric | ForEach-Object {
                [PSCustomObject]@{ Interfaz = $_.InterfaceAlias; Gateway = $_.NextHop; Metrica = ([int]$_.RouteMetric + [int]$_.InterfaceMetric) }
            })
    }
} catch { }
$proxy = ''
try { $proxy = ((& netsh.exe winhttp show proxy 2>&1) -join ' ' -replace '\s+', ' ').Trim() } catch { }
[PSCustomObject]@{ Adaptadores = $adaptadores; Perfiles = $perfiles; Firewall = $firewall; Rutas = $rutas; Proxy = $proxy }
'@
    $worker = Invoke-ResponsiveWorker -ScriptText $codigo -TimeoutSeconds 45 -Activity 'Revisando configuracion de red local'
    if (-not $worker.Correcto -or -not $worker.Resultado) {
        return [PSCustomObject]@{ Correcto = $false; Error = $worker.Error; Adaptadores = @(); Perfiles = @(); Firewall = @(); Rutas = @(); Proxy = '' }
    }
    $resultado = $worker.Resultado
    $resultado | Add-Member -NotePropertyName Correcto -NotePropertyValue $true -Force
    $resultado | Add-Member -NotePropertyName Error -NotePropertyValue $null -Force
    return $resultado
}

function Invoke-PruebasConectividadCONTPAQi {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][object[]]$Catalogo
    )
    $catalogoJson = $Catalogo | ConvertTo-Json -Depth 5 -Compress
    $codigo = @'
param([string]$TargetHost, [string]$PortsJson)
function Test-TcpPortInternal {
    param([string]$HostValue, [int]$PortValue, [int]$TimeoutMs = 650)
    $cliente = New-Object Net.Sockets.TcpClient
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    $async = $null
    try {
        $async = $cliente.BeginConnect($HostValue, $PortValue, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return [PSCustomObject]@{ Puerto = $PortValue; Abierto = $false; Milisegundos = $TimeoutMs; Detalle = 'Tiempo agotado' }
        }
        $cliente.EndConnect($async)
        return [PSCustomObject]@{ Puerto = $PortValue; Abierto = $true; Milisegundos = [math]::Round($reloj.Elapsed.TotalMilliseconds); Detalle = 'Conexion TCP correcta' }
    } catch {
        $detalle = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        return [PSCustomObject]@{ Puerto = $PortValue; Abierto = $false; Milisegundos = [math]::Round($reloj.Elapsed.TotalMilliseconds); Detalle = $detalle }
    } finally {
        if ($async -and $async.AsyncWaitHandle) { $async.AsyncWaitHandle.Close() }
        $cliente.Close()
        $reloj.Stop()
    }
}
$catalogo = $PortsJson | ConvertFrom-Json
$ips = @()
$dnsError = $null
try {
    $ips = @([Net.Dns]::GetHostAddresses($TargetHost) | ForEach-Object { $_.IPAddressToString } | Select-Object -Unique)
} catch { $dnsError = $_.Exception.Message }
$esIp = $false
$ipTemporal = $null
$esIp = [Net.IPAddress]::TryParse($TargetHost, [ref]$ipTemporal)
$destinoResoluble = ($esIp -or $ips.Count -gt 0)
$nombreInverso = $null
if ($esIp) { try { $nombreInverso = [Net.Dns]::GetHostEntry($TargetHost).HostName } catch { } }
$pingEstado = if ($destinoResoluble) { 'No responde' } else { 'NameResolutionFailure' }
$pingMs = 0
$pingDetalle = ''
$ping = $null
if ($destinoResoluble) {
    $ping = New-Object Net.NetworkInformation.Ping
    try {
        $respuestaPing = $ping.Send($TargetHost, 1500)
        $pingEstado = $respuestaPing.Status.ToString()
        $pingMs = $respuestaPing.RoundtripTime
    } catch { $pingDetalle = $_.Exception.Message } finally { if ($ping) { $ping.Dispose() } }
}
$pruebas = @()
foreach ($item in $catalogo) {
    $tcp = if ($destinoResoluble) {
        Test-TcpPortInternal -HostValue $TargetHost -PortValue ([int]$item.Puerto)
    } else {
        [PSCustomObject]@{ Puerto = [int]$item.Puerto; Abierto = $false; Milisegundos = 0; Detalle = 'DNS no resolvio el destino' }
    }
    $pruebas += [PSCustomObject]@{
        Puerto = [int]$item.Puerto; Grupo = [string]$item.Grupo; Uso = [string]$item.Uso
        Abierto = $tcp.Abierto; Milisegundos = $tcp.Milisegundos; Detalle = $tcp.Detalle
    }
}
$sqlBrowser = $false
$sqlBrowserDetalle = ''
$puertosSql = @()
$udp = $null
if ($destinoResoluble) {
    $udp = New-Object Net.Sockets.UdpClient
    try {
        $udp.Client.ReceiveTimeout = 1800
        $udp.Connect($TargetHost, 1434)
        [byte[]]$solicitud = @(2)
        $null = $udp.Send($solicitud, $solicitud.Length)
        $remoto = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
        $respuesta = $udp.Receive([ref]$remoto)
        $sqlBrowserDetalle = [Text.Encoding]::ASCII.GetString($respuesta)
        $sqlBrowser = ($respuesta.Length -gt 0)
        $puertosSql = @([regex]::Matches($sqlBrowserDetalle, '(?i)(?:^|;)tcp;(\d+)') | ForEach-Object { [int]$_.Groups[1].Value } | Select-Object -Unique)
    } catch { $sqlBrowserDetalle = $_.Exception.Message } finally { if ($udp) { $udp.Close() } }
} else { $sqlBrowserDetalle = 'DNS no resolvio el destino' }
$pruebasSql = @()
foreach ($puerto in $puertosSql) {
    if ($puerto -eq 1433) { continue }
    $tcp = Test-TcpPortInternal -HostValue $TargetHost -PortValue $puerto -TimeoutMs 900
    $pruebasSql += [PSCustomObject]@{ Puerto = $puerto; Abierto = $tcp.Abierto; Milisegundos = $tcp.Milisegundos; Detalle = $tcp.Detalle }
}
[PSCustomObject]@{
    EsIP = $esIp; IPs = $ips; DnsError = $dnsError; NombreInverso = $nombreInverso
    PingEstado = $pingEstado; PingMs = $pingMs; PingDetalle = $pingDetalle
    Puertos = $pruebas; SqlBrowser = $sqlBrowser; SqlBrowserDetalle = $sqlBrowserDetalle
    PuertosSqlDinamicos = $puertosSql; PruebasSqlDinamicos = $pruebasSql
}
'@
    $worker = Invoke-ResponsiveWorker -ScriptText $codigo -Arguments @($HostName, $catalogoJson) `
        -TimeoutSeconds 120 -Activity "Diagnosticando conectividad con $HostName"
    if (-not $worker.Correcto -or -not $worker.Resultado) {
        return [PSCustomObject]@{ Correcto = $false; Error = $worker.Error }
    }
    $resultado = $worker.Resultado
    $resultado | Add-Member -NotePropertyName Correcto -NotePropertyValue $true -Force
    $resultado | Add-Member -NotePropertyName Error -NotePropertyValue $null -Force
    return $resultado
}

function Show-DiagnosticoPuertosCONTPAQi {
    Write-Encabezado -Titulo 'DIAGNOSTICO PROFESIONAL DE CONECTIVIDAD' -Subtitulo 'Equipo local + DNS + ruta + firewall + SQL + puertos CONTPAQi' -Color 'Cyan'
    $inicio = Get-Date
    $hostObjetivo = Select-ServidorObjetivoCONTPAQi
    if ([string]::IsNullOrWhiteSpace($hostObjetivo)) {
        Write-Log -Mensaje 'Diagnostico cancelado.' -Nivel WARN
        return
    }
    $hostObjetivo = ConvertTo-HostServidorCONTPAQi -Valor $hostObjetivo
    if (-not $hostObjetivo) { Write-Log -Mensaje 'El nombre o IP indicado no es valido.' -Nivel ERROR; return }

    $catalogo = @(Get-CatalogoConectividadCONTPAQi)
    $gruposEsperados = @(Get-GruposConectividadEsperadosCONTPAQi)
    $redLocal = Get-EstadoRedLocalResponsive
    $pruebas = Invoke-PruebasConectividadCONTPAQi -HostName $hostObjetivo -Catalogo $catalogo
    if (-not $pruebas.Correcto) {
        Write-Log -Mensaje "No fue posible completar las pruebas: $($pruebas.Error)" -Nivel ERROR
        return
    }

    $criticos = 0
    $advertencias = 0
    Write-SeccionMenu -Titulo '1. RED DEL EQUIPO ACTUAL' -Color 'Cyan'
    if (-not $redLocal.Correcto -or @($redLocal.Adaptadores).Count -eq 0) {
        $criticos++
        Write-Log -Mensaje 'No se encontro un adaptador IP activo o Windows no permitio consultarlo.' -Nivel ERROR
    } else {
        foreach ($adaptador in @($redLocal.Adaptadores)) {
            $ipv4 = @($adaptador.IPs | Where-Object { $_ -match '^\d{1,3}(?:\.\d{1,3}){3}$' })
            $gateway = @($adaptador.Gateways | Where-Object { $_ })
            $dns = @($adaptador.DNS | Where-Object { $_ })
            Write-Log -Mensaje "$($adaptador.Descripcion) | IPv4: $(if ($ipv4.Count) { $ipv4 -join ', ' } else { 'sin IPv4' }) | DHCP: $(if ($adaptador.DHCP) { 'Si' } else { 'No' })" -Nivel $(if ($ipv4.Count) { 'OK' } else { 'WARN' })
            Write-Log -Mensaje "Gateway: $(if ($gateway.Count) { $gateway -join ', ' } else { 'no configurado' }) | DNS: $(if ($dns.Count) { $dns -join ', ' } else { 'no configurado' })" -Nivel $(if ($dns.Count) { 'INFO' } else { 'WARN' })
            if (-not $dns.Count) { $advertencias++ }
        }
    }
    foreach ($perfil in @($redLocal.Perfiles)) {
        Write-Log -Mensaje "Perfil: $($perfil.Interfaz) | $($perfil.Categoria) | IPv4 $($perfil.IPv4)" -Nivel $(if ($perfil.IPv4 -match 'Internet|LocalNetwork') { 'OK' } else { 'INFO' })
    }
    foreach ($ruta in @($redLocal.Rutas | Select-Object -First 3)) {
        Write-Log -Mensaje "Ruta predeterminada: $($ruta.Interfaz) -> $($ruta.Gateway) | metrica $($ruta.Metrica)" -Nivel INFO
    }
    foreach ($perfilFirewall in @($redLocal.Firewall)) {
        Write-Log -Mensaje "Firewall $($perfilFirewall.Perfil): $(if ($perfilFirewall.Habilitado) { 'Activo' } else { 'Desactivado' }) | Entrada $($perfilFirewall.Entrada) | Salida $($perfilFirewall.Salida)" -Nivel INFO
    }

    Write-SeccionMenu -Titulo "2. IDENTIDAD DEL SERVIDOR - $hostObjetivo" -Color 'Magenta'
    $ips = @($pruebas.IPs)
    if (-not $pruebas.EsIP -and $ips.Count -eq 0) {
        $criticos++
        Write-Log -Mensaje "DNS no pudo resolver '$hostObjetivo'." -Nivel ERROR
        Write-Log -Mensaje 'Causa probable: nombre incorrecto, DNS local, VPN desconectada o registro DNS ausente.' -Nivel INFO
    } elseif ($pruebas.EsIP) {
        Write-Log -Mensaje "Objetivo por IP directa: $hostObjetivo$(if ($pruebas.NombreInverso) { " | Nombre inverso: $($pruebas.NombreInverso)" } else { '' })" -Nivel OK
    } else {
        Write-Log -Mensaje "Resolucion DNS correcta: $hostObjetivo -> $($ips -join ', ')" -Nivel OK
        if ($ips.Count -gt 1) { $advertencias++; Write-Log -Mensaje 'El nombre devuelve varias IP. Si la falla es intermitente, valida que todas pertenezcan al servidor correcto.' -Nivel WARN }
    }
    $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $entradaHosts = @()
    if (-not $pruebas.EsIP -and (Test-Path -LiteralPath $hostsPath)) {
        $nombreRegex = [regex]::Escape($hostObjetivo)
        $entradaHosts = @(Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue | Where-Object { $_ -match "(?i)^\s*[^#].*\s$nombreRegex(?:\s|$)" })
    }
    if ($entradaHosts.Count) { $advertencias++; Write-Log -Mensaje "El archivo HOSTS contiene una entrada para $hostObjetivo; valida que no apunte a una IP antigua." -Nivel WARN }
    if ($pruebas.PingEstado -eq 'Success') {
        Write-Log -Mensaje "ICMP responde en $($pruebas.PingMs) ms." -Nivel OK
    } else {
        Write-Log -Mensaje 'El servidor no responde a ping. Esto no confirma una falla: ICMP puede estar bloqueado.' -Nivel INFO
    }

    Write-SeccionMenu -Titulo '3. SQL SERVER Y DESCUBRIMIENTO DE INSTANCIAS' -Color 'Green'
    if ($pruebas.SqlBrowser) {
        Write-Log -Mensaje "SQL Browser UDP 1434 respondio. Puertos anunciados: $(if (@($pruebas.PuertosSqlDinamicos).Count) { @($pruebas.PuertosSqlDinamicos) -join ', ' } else { 'sin puerto TCP publicado' })." -Nivel OK
        foreach ($sqlTcp in @($pruebas.PruebasSqlDinamicos)) {
            Write-Log -Mensaje "SQL dinamico TCP $($sqlTcp.Puerto): $(if ($sqlTcp.Abierto) { "abierto ($($sqlTcp.Milisegundos) ms)" } else { 'sin respuesta' })" -Nivel $(if ($sqlTcp.Abierto) { 'OK' } else { 'WARN' })
        }
    } else {
        Write-Log -Mensaje 'SQL Browser UDP 1434 no respondio. Puede estar detenido, bloqueado o no ser necesario para una instancia con puerto fijo.' -Nivel INFO
    }

    Write-SeccionMenu -Titulo '4. PUERTOS Y SERVICIOS CONTPAQi' -Color 'Yellow'
    $abiertos = @($pruebas.Puertos | Where-Object Abierto)
    foreach ($grupo in @($pruebas.Puertos | Group-Object Grupo)) {
        $grupoEsperado = ($grupo.Name -in $gruposEsperados)
        $abiertosGrupo = @($grupo.Group | Where-Object Abierto)
        Write-Log -Mensaje "$($grupo.Name): $($abiertosGrupo.Count) de $($grupo.Count) puerto(s) con respuesta$(if ($grupoEsperado) { ' | producto relacionado detectado' } else { '' })." -Nivel $(if ($abiertosGrupo.Count) { 'OK' } elseif ($grupoEsperado) { 'WARN' } else { 'INFO' })
        if ($grupoEsperado -and $abiertosGrupo.Count -eq 0) { $advertencias++ }
        foreach ($puerto in $grupo.Group) {
            $nivel = if ($puerto.Abierto) { 'OK' } elseif ($grupoEsperado) { 'WARN' } else { 'INFO' }
            Write-Log -Mensaje "TCP $($puerto.Puerto) $(if ($puerto.Abierto) { "ABIERTO $($puerto.Milisegundos) ms" } else { 'sin respuesta' }) | $($puerto.Uso)" -Nivel $nivel
        }
    }

    Write-SeccionMenu -Titulo '5. DIAGNOSTICO Y SIGUIENTE PASO' -Color 'Cyan'
    $hayPuertoAplicacion = @($abiertos | Where-Object Grupo -notin @('Administracion', 'SQL')).Count -gt 0
    $haySql = (@($abiertos | Where-Object Grupo -eq 'SQL').Count -gt 0) -or (@($pruebas.PruebasSqlDinamicos | Where-Object Abierto).Count -gt 0)
    if ($criticos -gt 0) {
        Write-Log -Mensaje 'CAUSA PROBABLE: configuracion local o resolucion DNS. Corrige esta capa antes de reiniciar servicios.' -Nivel ERROR
    } elseif (-not $hayPuertoAplicacion -and -not $haySql) {
        $advertencias++
        Write-Log -Mensaje 'CAUSA PROBABLE: servidor equivocado, VPN/ruta ausente, firewall intermedio o servicios remotos detenidos.' -Nivel WARN
    } elseif (-not $hayPuertoAplicacion -and $haySql) {
        $advertencias++
        Write-Log -Mensaje 'CAUSA PROBABLE: SQL es accesible, pero los servicios de aplicaciones/licenciamiento CONTPAQi no responden.' -Nivel WARN
    } elseif ($hayPuertoAplicacion -and -not $haySql) {
        $advertencias++
        Write-Log -Mensaje 'CAUSA PROBABLE: el servidor CONTPAQi responde, pero SQL usa otro puerto, SQL Browser esta bloqueado o el motor esta detenido.' -Nivel WARN
    } elseif ($pruebas.PingEstado -ne 'Success') {
        Write-Log -Mensaje 'La conectividad TCP funciona aunque ping no responda; ICMP esta probablemente bloqueado y no es la causa.' -Nivel OK
    } else {
        Write-Log -Mensaje 'Conectividad base correcta. Si la aplicacion falla, el siguiente paso es revisar salud SQL, servicios y credenciales.' -Nivel OK
    }
    if (@($redLocal.Firewall | Where-Object { $_.Habilitado -and $_.Salida -match 'Block' }).Count) {
        $advertencias++
        Write-Log -Mensaje 'El firewall local tiene salida bloqueada por defecto; valida reglas de salida para los puertos reportados.' -Nivel WARN
    }
    $duracion = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    Write-Separador -Color $(if ($criticos) { $Script:ColorError } elseif ($advertencias) { $Script:ColorAdvertencia } else { $Script:ColorExito })
    Write-Log -Mensaje "DIAGNOSTICO FINAL: $criticos problema(s) critico(s), $advertencias advertencia(s), $($abiertos.Count) puerto(s) TCP abierto(s) | $duracion s." -Nivel $(if ($criticos) { 'ERROR' } elseif ($advertencias) { 'WARN' } else { 'OK' })
    Write-Log -Mensaje 'Analisis de solo lectura: no se modificaron DNS, firewall, adaptadores, servicios ni configuraciones.' -Nivel INFO
}

function Show-DiagnosticoTimbrado {
    Write-Encabezado -Titulo 'TIMBRADO E INTERNET' -Subtitulo 'DNS, HTTPS, reloj y proxy' -Color 'Magenta'
    $destinos = @(
        @{ Host = 'www.contpaqi.com'; Puerto = 443; Uso = 'Portal CONTPAQi' },
        @{ Host = 'osb.contpaqi.com'; Puerto = 443; Uso = 'Servicios en linea CONTPAQi' },
        @{ Host = 'www.sat.gob.mx'; Puerto = 443; Uso = 'Portal SAT' }
    )
    $correctos = 0
    foreach ($destino in $destinos) {
        $ips = @(Resolve-HostCONTPAQi -HostName $destino.Host)
        if ($ips.Count -eq 0) {
            Write-Log -Mensaje "$($destino.Host): no resuelve por DNS." -Nivel ERROR
            continue
        }
        $prueba = Test-PuertoTCP -HostName $destino.Host -Port $destino.Puerto -TimeoutMs 2500
        if ($prueba.Abierto) {
            $correctos++
            Write-Log -Mensaje "$($destino.Uso): HTTPS accesible ($($prueba.Milisegundos) ms)." -Nivel OK
        } else {
            Write-Log -Mensaje "$($destino.Uso): no fue posible conectar al puerto 443." -Nivel ERROR
        }
    }

    Write-SeccionMenu -Titulo 'RELOJ Y PROXY' -Color 'Yellow'
    $w32time = Get-Service -Name 'W32Time' -ErrorAction SilentlyContinue
    if ($w32time) {
        $nivelTiempo = if ($w32time.Status -eq 'Running') { 'OK' } else { 'WARN' }
        Write-Log -Mensaje "Servicio de hora de Windows: $($w32time.Status) | Zona: $([TimeZoneInfo]::Local.DisplayName)" -Nivel $nivelTiempo
    }
    $proxy = (& netsh.exe winhttp show proxy 2>&1) -join ' '
    $proxy = ($proxy -replace '\s+', ' ').Trim()
    if ($proxy.Length -gt 300) { $proxy = $proxy.Substring(0, 300) + '...' }
    Write-Log -Mensaje "Proxy WinHTTP: $proxy" -Nivel INFO
    Write-Log -Mensaje "Conectividad externa: $correctos de $($destinos.Count) destinos disponibles." -Nivel $(if ($correctos -eq $destinos.Count) { 'OK' } else { 'WARN' })
    Write-Log -Mensaje 'Si la red funciona, valida CSD vigente, contraseña del certificado, manifiesto y estado del documento antes de reintentar el timbrado.' -Nivel INFO
}

function Get-UtileriasCONTPAQi {
    $nombres = @('CONTPAQiUsuarios.exe', 'NomTerminalSql.exe')
    $raices = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Compac'),
        (Join-Path $env:ProgramFiles 'Compac'),
        (Join-Path ${env:ProgramFiles(x86)} 'Compacw'),
        'C:\Compacw'
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    $resultado = @()
    foreach ($raiz in $raices) {
        foreach ($nombre in $nombres) {
            $resultado += Get-ChildItem -LiteralPath $raiz -Filter $nombre -File -Recurse -ErrorAction SilentlyContinue |
                Select-Object @{Name='Nombre';Expression={$_.BaseName}}, @{Name='Ruta';Expression={$_.FullName}}
        }
    }
    return @($resultado | Sort-Object Ruta -Unique)
}

function Show-UtileriasCONTPAQi {
    Write-Encabezado -Titulo 'UTILERIAS OFICIALES DETECTADAS' -Subtitulo 'Herramientas instaladas junto con CONTPAQi' -Color 'Green'
    $utilerias = @(Get-UtileriasCONTPAQi)
    if ($utilerias.Count -eq 0) {
        Write-Log -Mensaje 'No se encontraron CONTPAQiUsuarios ni NomTerminalSql en las rutas instaladas.' -Nivel WARN
        return
    }
    foreach ($utilidad in $utilerias) { Write-Log -Mensaje "$($utilidad.Nombre) | $($utilidad.Ruta)" -Nivel OK }
    $opciones = @($utilerias | ForEach-Object { "$($_.Nombre)  —  $($_.Ruta)" })
    $indice = if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        Show-GUIChoice -Titulo 'Abrir utileria CONTPAQi' -Mensaje 'Selecciona una utileria. Se ejecutara con los permisos actuales:' -Opciones $opciones
    } else { -1 }
    if ($indice -ge 0 -and $indice -lt $utilerias.Count) {
        $seleccion = $utilerias[$indice]
        if (Confirmar-Accion -Mensaje "Abrir $($seleccion.Nombre)") {
            try {
                Start-Process -FilePath $seleccion.Ruta -WorkingDirectory (Split-Path -Parent $seleccion.Ruta) -ErrorAction Stop | Out-Null
                Write-Log -Mensaje "$($seleccion.Nombre) iniciada correctamente." -Nivel OK
            } catch {
                Write-Log -Mensaje "No se pudo iniciar la utileria: $($_.Exception.Message)" -Nivel ERROR
            }
        }
    }
}

function Show-SaludWindowsSoporte {
    Write-Encabezado -Titulo 'SALUD DE WINDOWS' -Subtitulo 'Revision segura para servidores y VDI' -Color 'Yellow'
    $so = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($so) {
        $uptime = [math]::Round(((Get-Date) - $so.LastBootUpTime).TotalDays, 1)
        $memoriaLibre = [math]::Round(($so.FreePhysicalMemory * 1KB) / 1GB, 2)
        $memoriaTotal = [math]::Round(($so.TotalVisibleMemorySize * 1KB) / 1GB, 2)
        Write-Log -Mensaje "Windows: $($so.Caption) Build $($so.BuildNumber) | Uptime: $uptime dias" -Nivel INFO
        Write-Log -Mensaje "Memoria disponible: $memoriaLibre GB de $memoriaTotal GB" -Nivel $(if ($memoriaLibre -ge 2) { 'OK' } else { 'WARN' })
    }
    if (Test-ReinicioPendiente) {
        Write-Log -Mensaje 'Existe un reinicio pendiente de Windows.' -Nivel WARN
    } else {
        Write-Log -Mensaje 'No se detecta reinicio pendiente.' -Nivel OK
    }
    foreach ($nombre in @('Dnscache', 'W32Time', 'LanmanWorkstation')) {
        $servicio = Get-Service -Name $nombre -ErrorAction SilentlyContinue
        if ($servicio) {
            Write-Log -Mensaje "$($servicio.DisplayName): $($servicio.Status)" -Nivel $(if ($servicio.Status -eq 'Running') { 'OK' } else { 'WARN' })
        }
    }

    Write-SeccionMenu -Titulo 'ALMACENAMIENTO' -Color 'Yellow'
    foreach ($disco in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)) {
        $libre = [math]::Round($disco.FreeSpace / 1GB, 1)
        $total = [math]::Round($disco.Size / 1GB, 1)
        Write-Log -Mensaje "$($disco.DeviceID) $libre GB libres de $total GB" -Nivel $(if ($libre -ge 10) { 'OK' } else { 'WARN' })
    }

    Write-SeccionMenu -Titulo 'IMAGEN DE WINDOWS' -Color 'Cyan'
    Write-Log -Mensaje 'Ejecutando DISM CheckHealth (solo diagnostico)...' -Nivel PROGRESS
    $codigoDismWorker = @'
$salida = & dism.exe /Online /Cleanup-Image /CheckHealth /English 2>&1
[PSCustomObject]@{ ExitCode = $LASTEXITCODE; Texto = (($salida -join ' ') -replace '\s+', ' ').Trim() }
'@
    $resultadoDismWorker = Invoke-ResponsiveWorker -ScriptText $codigoDismWorker -TimeoutSeconds 900 -Activity 'Revisando imagen de Windows'
    $codigoDism = if ($resultadoDismWorker.Correcto -and $resultadoDismWorker.Resultado) { $resultadoDismWorker.Resultado.ExitCode } else { -1 }
    $textoDism = if ($resultadoDismWorker.Resultado) { $resultadoDismWorker.Resultado.Texto } else { $resultadoDismWorker.Error }
    if ($codigoDism -eq 0 -and $textoDism -match 'No component store corruption detected') {
        Write-Log -Mensaje 'DISM no reporto corrupcion reparable en la imagen de Windows.' -Nivel OK
    } elseif ($codigoDism -eq 0 -and $textoDism -match 'component store is repairable') {
        Write-Log -Mensaje 'DISM detecto que la imagen de Windows es reparable. Programa DISM RestoreHealth.' -Nivel WARN
    } elseif ($codigoDism -eq 0) {
        Write-Log -Mensaje 'DISM CheckHealth finalizo correctamente; revisa la salida detallada si el problema continua.' -Nivel INFO
    } else {
        Write-Log -Mensaje "DISM finalizo con codigo $codigoDism. Ejecuta RestoreHealth en una ventana de mantenimiento." -Nivel WARN
        if ($textoDism) { Write-Log -Mensaje $textoDism -Nivel INFO }
    }
    Write-Log -Mensaje 'SFC /scannow, DISM /RestoreHealth y Winsock Reset no se ejecutan automaticamente porque pueden tardar o requerir reinicio.' -Nivel INFO
}

function Show-CentroSoluciones {
    Write-Encabezado -Titulo 'CENTRO DE SOLUCIONES' -Subtitulo 'Asistentes basados en casos reales de soporte' -Color 'Cyan'
    $opciones = @(
        'Conectividad, servidor y puertos de licenciamiento',
        'Timbrado, Internet, DNS, reloj y proxy',
        'Buscar y abrir utilerias oficiales instaladas',
        'Revisar salud de Windows, VDI y almacenamiento'
    )
    $indice = if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        Show-GUIChoice -Titulo 'Centro de soluciones CONTPAQi' -Mensaje 'Elige el tipo de problema que deseas diagnosticar:' -Opciones $opciones
    } else {
        Write-OpcionMenu -Tecla '1' -Descripcion $opciones[0]
        Write-OpcionMenu -Tecla '2' -Descripcion $opciones[1]
        Write-OpcionMenu -Tecla '3' -Descripcion $opciones[2]
        Write-OpcionMenu -Tecla '4' -Descripcion $opciones[3]
        ([int](Read-Host ' Selecciona una opcion')) - 1
    }
    switch ($indice) {
        0 { Show-DiagnosticoPuertosCONTPAQi }
        1 { Show-DiagnosticoTimbrado }
        2 { Show-UtileriasCONTPAQi }
        3 { Show-SaludWindowsSoporte }
        default { Write-Log -Mensaje 'Centro de soluciones cerrado sin realizar cambios.' -Nivel INFO }
    }
}

function Get-ServiciosCONTPAQiDetectados {
    $encontrados = @{}
    $todos = @(Get-Service -ErrorAction SilentlyContinue)
    foreach ($servicio in $todos) {
        $coincide = (
            $servicio.Name -match 'CONTPAQ|COMPAC|SACI|AppKey|AuthServer|XMLenLinea|XMLService|SRVPAQi' -or
            $servicio.DisplayName -match 'CONTPAQ|COMPAC|SACI|XML en l.nea'
        )
        if ($coincide -and -not $encontrados.ContainsKey($servicio.Name)) {
            $encontrados[$servicio.Name] = $servicio
        }
    }
    foreach ($servicio in (Get-ServiciosMotorSQL)) {
        if (-not $encontrados.ContainsKey($servicio.Name)) { $encontrados[$servicio.Name] = $servicio }
    }
    $browser = Get-Service -Name 'SQLBrowser' -ErrorAction SilentlyContinue
    if ($browser -and -not $encontrados.ContainsKey($browser.Name)) { $encontrados[$browser.Name] = $browser }
    return @($encontrados.Values | Sort-Object Name)
}

function Get-ServiciosAplicacionCONTPAQi {
    # El inventario se obtiene en cada reparacion para incluir productos o
    # versiones instalados mientras el Toolbox permanece abierto.
    $candidatos = @(
        @(Get-ServiciosCONTPAQiDetectados) +
        @(Get-ServiciosTerminal | ForEach-Object { $_.Servicio }) +
        @(Get-ServiciosPID) +
        @($ServiciosLicencias + $ServiciosSACI | ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue })
    ) | Where-Object { $_ } | Sort-Object Name -Unique
    return @($candidatos | Where-Object {
        $nombre = $_.Name
        $visible = $_.DisplayName
        -not (
            $nombre -in @($Script:ServicesDevName, $Script:ServicesDevLegacyName) -or
            $nombre -match '^(MSSQLSERVER$|MSSQL\$|SQLAgent\$|SQLSERVERAGENT$|SQLBrowser$|SQLWriter$)' -or
            $visible -match '^SQL Server($|\s|\()'
        )
    })
}

function Get-OrdenInicioServicioCONTPAQi {
    param([Parameter(Mandatory)]$Servicio)
    $texto = "$($Servicio.Name) $($Servicio.DisplayName)"
    if ($texto -match '(?i)licen|AppKey|AuthServer|SRVPAQi') { return 0 }
    if ($texto -match '(?i)SACI|XML\s*en\s*l.nea|XMLService') { return 2 }
    if ($texto -match '(?i)Watchdog|ServicesDev') { return 3 }
    return 1
}

function Test-ServicioDeshabilitado {
    param([Parameter(Mandatory)][string]$Nombre)
    try {
        $nombreSeguro = $Nombre.Replace("'", "''")
        $cim = Get-CimInstance Win32_Service -Filter "Name='$nombreSeguro'" -ErrorAction Stop
        return ($cim.StartMode -eq 'Disabled')
    } catch {
        $svc = Get-Service -Name $Nombre -ErrorAction SilentlyContinue
        return ($svc -and $svc.PSObject.Properties['StartType'] -and $svc.StartType -eq 'Disabled')
    }
}

function Invoke-ServiceActionResponsive {
    param(
        [Parameter(Mandatory)][string]$Nombre,
        [Parameter(Mandatory)][ValidateSet('Start', 'Stop')][string]$Accion,
        [ValidateRange(5, 300)][int]$TimeoutSegundos = 60
    )
    $codigoServicio = @'
param([string]$ServiceName, [string]$Action, [int]$TimeoutSeconds)
try {
    $servicio = Get-Service -Name $ServiceName -ErrorAction Stop
    $estadoDeseadoTexto = if ($Action -eq 'Start') { 'Running' } else { 'Stopped' }
    if ($servicio.Status.ToString() -ne $estadoDeseadoTexto) {
        if ($Action -eq 'Start') {
            Start-Service -Name $ServiceName -ErrorAction Stop
        } else {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
        }
        $estadoDeseado = [Enum]::Parse([System.ServiceProcess.ServiceControllerStatus], $estadoDeseadoTexto)
        $servicio.WaitForStatus($estadoDeseado, [TimeSpan]::FromSeconds($TimeoutSeconds))
    }
    $servicio.Refresh()
    [PSCustomObject]@{
        Correcto = ($servicio.Status.ToString() -eq $estadoDeseadoTexto)
        Estado = $servicio.Status.ToString()
        Error = $null
    }
} catch {
    [PSCustomObject]@{ Correcto = $false; Estado = 'Desconocido'; Error = $_.Exception.Message }
}
'@
    $verbo = if ($Accion -eq 'Start') { 'Iniciando' } else { 'Deteniendo' }
    $worker = Invoke-ResponsiveWorker -ScriptText $codigoServicio -Arguments @($Nombre, $Accion, $TimeoutSegundos) `
        -TimeoutSeconds ($TimeoutSegundos + 10) -Activity "$verbo $Nombre"
    if (-not $worker.Correcto -or $worker.Timeout -or -not $worker.Resultado) {
        return [PSCustomObject]@{ Correcto = $false; Estado = 'Desconocido'; Error = $worker.Error }
    }
    return $worker.Resultado
}

function Suspend-ServicesDevForRepair {
    $estados = @()
    $nombres = @($Script:ServicesDevName, $Script:ServicesDevLegacyName) | Where-Object { $_ } | Select-Object -Unique
    foreach ($nombre in $nombres) {
        $servicio = Get-Service -Name $nombre -ErrorAction SilentlyContinue
        if (-not $servicio) { continue }

        $estabaActivo = ($servicio.Status -in @('Running', 'StartPending'))
        $estados += [PSCustomObject]@{ Nombre = $nombre; EstabaActivo = $estabaActivo }
        if ($servicio.Status -eq 'Stopped') {
            Write-Log -Mensaje "$nombre ya estaba detenido; se conservara ese estado al terminar." -Nivel INFO
            continue
        }

        Write-Log -Mensaje "Deteniendo temporalmente $nombre para evitar que interfiera con la reparacion..." -Nivel PROGRESS
        $resultado = Invoke-ServiceActionResponsive -Nombre $nombre -Accion Stop -TimeoutSegundos 60
        if (-not $resultado.Correcto) {
            Write-Log -Mensaje "No se pudo detener $($nombre): $($resultado.Error). La reparacion no continuara." -Nivel ERROR
            Restore-ServicesDevAfterRepair -Estados @($estados) | Out-Null
            return [PSCustomObject]@{ Correcto = $false; Instalado = $true; Estados = @($estados); Error = $resultado.Error }
        }
        Write-Log -Mensaje "$nombre detenido y verificado. La reparacion puede continuar." -Nivel OK
    }

    return [PSCustomObject]@{
        Correcto = $true
        Instalado = ($estados.Count -gt 0)
        Estados = @($estados)
        Error = $null
    }
}

function Restore-ServicesDevAfterRepair {
    param([AllowNull()][object[]]$Estados)
    $fallidos = 0
    foreach ($estado in @($Estados)) {
        if (-not $estado -or -not $estado.EstabaActivo) { continue }
        $servicio = Get-Service -Name $estado.Nombre -ErrorAction SilentlyContinue
        if (-not $servicio) {
            $fallidos++
            Write-Log -Mensaje "$($estado.Nombre) ya no esta instalado; no fue posible restaurarlo." -Nivel ERROR
            continue
        }
        if ($servicio.Status -eq 'Running') {
            Write-Log -Mensaje "$($estado.Nombre) ya se encuentra activo nuevamente." -Nivel OK
            continue
        }

        Write-Log -Mensaje "Reactivando $($estado.Nombre) al finalizar la reparacion..." -Nivel PROGRESS
        $resultado = Invoke-ServiceActionResponsive -Nombre $estado.Nombre -Accion Start -TimeoutSegundos 75
        if ($resultado.Correcto) {
            Write-Log -Mensaje "$($estado.Nombre) iniciado y verificado correctamente." -Nivel OK
        } else {
            $fallidos++
            Write-Log -Mensaje "La reparacion termino, pero no se pudo iniciar $($estado.Nombre): $($resultado.Error)" -Nivel ERROR
        }
    }
    return ($fallidos -eq 0)
}

function Start-TodosServiciosCONTPAQiVerificado {
    param([ValidateRange(1, 3)][int]$Intentos = 2)

    $servicios = @(Get-ServiciosAplicacionCONTPAQi | Sort-Object `
        @{ Expression = { Get-OrdenInicioServicioCONTPAQi -Servicio $_ } }, Name)
    $correctos = 0
    $omitidos = 0
    $fallidos = New-Object System.Collections.Generic.List[string]

    foreach ($servicioInicial in $servicios) {
        $nombre = $servicioInicial.Name
        $actual = Get-Service -Name $nombre -ErrorAction SilentlyContinue
        if (-not $actual) { continue }
        if (Test-ServicioDeshabilitado -Nombre $nombre) {
            $omitidos++
            Write-Log -Mensaje "$nombre esta deshabilitado en Windows; se conserva su configuracion." -Nivel WARN
            continue
        }
        if ($actual.Status -eq 'Running') {
            $correctos++
            Write-Log -Mensaje "$nombre ya estaba activo." -Nivel OK
            continue
        }

        $ultimoError = ''
        $iniciado = $false
        for ($intento = 1; $intento -le $Intentos -and -not $iniciado; $intento++) {
            $resultado = Invoke-ServiceActionResponsive -Nombre $nombre -Accion Start -TimeoutSegundos 75
            if ($resultado.Correcto) {
                $iniciado = $true
                break
            }
            $ultimoError = $resultado.Error
            if ($intento -lt $Intentos) {
                Write-Log -Mensaje "$nombre no inicio en el intento $intento; se reintentara." -Nivel WARN
                Wait-Responsive -Seconds 1
            }
        }
        if ($iniciado) {
            $correctos++
            Write-Log -Mensaje "$nombre iniciado y verificado." -Nivel OK
        } else {
            $fallidos.Add($nombre)
            Write-Log -Mensaje "No se pudo iniciar $($nombre): $ultimoError" -Nivel ERROR
        }
    }

    # Auditoria final independiente: evita declarar exito con un servicio que
    # se haya detenido nuevamente durante el arranque de sus dependencias.
    $noActivos = @(Get-ServiciosAplicacionCONTPAQi | Where-Object {
        -not (Test-ServicioDeshabilitado -Nombre $_.Name) -and $_.Status -ne 'Running'
    } | Select-Object -ExpandProperty Name -Unique)
    foreach ($nombre in $noActivos) {
        if (-not $fallidos.Contains($nombre)) { $fallidos.Add($nombre) }
    }

    return [PSCustomObject]@{
        Total = $servicios.Count
        Correctos = $correctos
        Omitidos = $omitidos
        Fallidos = $fallidos.Count
        FallidosNombres = @($fallidos)
    }
}

function Get-TamanoCarpetasTemporalesCONTPAQi {
    $rutas = @(
        (Join-Path $env:LOCALAPPDATA 'Temp\Compac'),
        (Join-Path $env:LOCALAPPDATA 'Temp\CONTPAQi'),
        'C:\Windows\Temp\Compac',
        'C:\Windows\Temp\CONTPAQi'
    ) | Select-Object -Unique
    $codigoMedicion = @'
param([object[]]$Paths)
$total = 0L
foreach ($path in $Paths) {
    if (Test-Path -LiteralPath $path -PathType Container) {
        $medida = Get-ChildItem -LiteralPath $path -File -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum
        if ($medida.Sum) { $total += [long]$medida.Sum }
    }
}
[PSCustomObject]@{ Bytes = $total }
'@
    $medicion = Invoke-ResponsiveWorker -ScriptText $codigoMedicion -Arguments @(,([object[]]$rutas)) `
        -TimeoutSeconds 600 -Activity 'Midiendo temporales CONTPAQi'
    $bytes = if ($medicion.Correcto -and $medicion.Resultado) { [long]$medicion.Resultado.Bytes } else { 0L }
    if (-not $medicion.Correcto) {
        Write-Log -Mensaje "No se pudo medir por completo el espacio temporal: $($medicion.Error)" -Nivel WARN
    }
    return [PSCustomObject]@{ Rutas = $rutas; Bytes = $bytes; MB = [math]::Round($bytes / 1MB, 1) }
}

# --- ANALISIS INTELIGENTE DE BITACORAS CONTPAQi ---
# Esta capa es deliberadamente conservadora: muestra evidencia y solo ofrece
# reparaciones reversibles. Nunca modifica tablas, colas MSMQ, ACL ni archivos
# de programa a partir de una coincidencia de texto.
function Protect-TextoBitacoraCONTPAQi {
    param(
        [AllowEmptyString()][string]$Texto,
        [int]$LongitudMaxima = 900
    )
    if ([string]::IsNullOrWhiteSpace($Texto)) { return '' }

    $limpio = $Texto -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ' '
    $limpio = $limpio -replace '(?i)(authorization\s*[:=])\s*[^;\r\n]+', '$1 ***'
    $limpio = $limpio -replace '(?i)(password|passwd|pwd|clave|contrasena|contrase.a|token|secret|api[_-]?key)\s*=\s*([^;\r\n]+)', '$1=***'
    $limpio = $limpio -replace '(?i)(password|passwd|pwd|clave|contrasena|contrase.a|token|secret|api[_-]?key)\s*:\s*([^;\s,]+)', '$1:***'
    $limpio = $limpio -replace '(?i)(["''](?:password|passwd|pwd|token|secret|api[_-]?key)["'']\s*:\s*["''])[^"'']+', '$1***'
    $limpio = $limpio -replace '(?i)(User\s*ID|UID)\s*=\s*([^;]+)', '$1=***'
    $limpio = $limpio -replace '(?i)([?&](?:token|key|secret|password|pwd)=)[^&\s]+', '$1***'
    $limpio = (($limpio -replace '[\r\n]+', ' ') -replace '\s+', ' ').Trim()
    if ($limpio.Length -gt $LongitudMaxima) {
        $limpio = $limpio.Substring(0, $LongitudMaxima) + '...'
    }
    return $limpio
}

function Get-RutasBitacoraCONTPAQi {
    $candidatas = @(
        'C:\Compac',
        'C:\CONTPAQi',
        (Join-Path ${env:ProgramFiles(x86)} 'Compac'),
        (Join-Path $env:ProgramFiles 'Compac'),
        (Join-Path $env:ProgramData 'Compac'),
        (Join-Path $env:ProgramData 'CONTPAQi'),
        (Join-Path $env:LOCALAPPDATA 'Compac'),
        (Join-Path $env:LOCALAPPDATA 'CONTPAQi'),
        (Join-Path $env:APPDATA 'Compac'),
        (Join-Path $env:APPDATA 'CONTPAQi')
    )
    return @($candidatas | Where-Object {
        $_ -and (Test-Path -LiteralPath $_ -PathType Container) -and
        $_ -notlike "$($Script:LogDirectory)*"
    } | Select-Object -Unique)
}

function Get-RutasERRORLOGSQLLocal {
    $rutas = New-Object System.Collections.Generic.List[string]
    foreach ($baseRegistro in @(
        'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server'
    )) {
        try {
            $claveInstancias = Join-Path $baseRegistro 'Instance Names\SQL'
            if (-not (Test-Path -LiteralPath $claveInstancias)) { continue }
            $instancias = Get-ItemProperty -LiteralPath $claveInstancias -ErrorAction Stop
            foreach ($propiedad in @($instancias.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })) {
                $id = [string]$propiedad.Value
                if ([string]::IsNullOrWhiteSpace($id)) { continue }
                $claveParametros = Join-Path $baseRegistro "$id\MSSQLServer\Parameters"
                if (Test-Path -LiteralPath $claveParametros) {
                    $parametros = Get-ItemProperty -LiteralPath $claveParametros -ErrorAction SilentlyContinue
                    foreach ($parametro in @($parametros.PSObject.Properties | Where-Object { $_.Name -match '^SQLArg\d+$' })) {
                        $valor = [Environment]::ExpandEnvironmentVariables(([string]$parametro.Value).Trim())
                        if ($valor -match '(?i)^-e\s*"?(.+?ERRORLOG)"?$') { $rutas.Add($matches[1].Trim('"')) }
                    }
                }
                $rutas.Add((Join-Path $env:ProgramFiles "Microsoft SQL Server\$id\MSSQL\Log\ERRORLOG"))
            }
        } catch { }
    }

    foreach ($servicio in @(Get-ServiciosMotorSQL)) {
        try {
            $imagen = [Environment]::ExpandEnvironmentVariables([string](Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($servicio.Name)" -Name ImagePath -ErrorAction Stop).ImagePath)
            if ($imagen -match '(?i)(?:^|\s)-e\s*"([^"]+ERRORLOG)"') { $rutas.Add($matches[1]) }
            elseif ($imagen -match '(?i)(?:^|\s)-e\s*([^\s]+ERRORLOG)') { $rutas.Add($matches[1].Trim('"')) }
        } catch { }
    }
    return @($rutas | Where-Object { $_ } | Select-Object -Unique)
}

function Get-ArchivosBitacoraCONTPAQi {
    param(
        [ValidateRange(1, 365)][int]$Dias = 30,
        [ValidateRange(10, 500)][int]$MaxArchivos = 150
    )
    $payload = [PSCustomObject]@{
        Raices = @(Get-RutasBitacoraCONTPAQi)
        ErrorLogs = @(Get-RutasERRORLOGSQLLocal)
        Corte = (Get-Date).AddDays(-$Dias).ToString('o')
        MaxArchivos = $MaxArchivos
        LogActual = [string]$Script:LogFile
    } | ConvertTo-Json -Depth 5 -Compress
    $codigoBusqueda = @'
param([string]$Json)
$config = $Json | ConvertFrom-Json
$corte = [DateTime]::Parse($config.Corte)
$encontrados = New-Object System.Collections.Generic.List[object]
foreach ($raiz in @($config.Raices)) {
    try {
        foreach ($archivo in @(Get-ChildItem -LiteralPath $raiz -File -Recurse -Force -ErrorAction SilentlyContinue)) {
            if ($archivo.LastWriteTime -lt $corte -or $archivo.Length -le 0 -or $archivo.Length -gt 20MB) { continue }
            if ($archivo.Extension -notin @('.log', '.txt', '.err', '.trace', '.json')) { continue }
            if ($archivo.FullName -match '(?i)\\(Idiomas?|Languages?|Reportes?|Reports?|SAT|ms-playwright|node_modules|packages?|Help|Ayuda|Samples?|Ejemplos?|Cache)\\') { continue }
            if ($archivo.Name -match '(?i)^(install|installer|inst[-_.]|setup|uninstall)') { continue }
            if ($archivo.Extension -in @('.txt', '.json') -and
                $archivo.Name -notmatch '(?i)(log|bitac|error|trace|saci|excep)' -and
                $archivo.DirectoryName -notmatch '(?i)\\(log|logs|bitacora|bitacoras)($|\\)') { continue }
            if ($config.LogActual -and $archivo.FullName -eq $config.LogActual) { continue }
            $encontrados.Add($archivo)
        }
    } catch { }
}
foreach ($rutaERRORLOG in @($config.ErrorLogs)) {
    try {
        $directorio = Split-Path -Path $rutaERRORLOG -Parent
        if (-not (Test-Path -LiteralPath $directorio -PathType Container)) { continue }
        foreach ($archivo in @(Get-ChildItem -LiteralPath $directorio -File -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match '(?i)^ERRORLOG(?:\.\d+)?$|^SQLAGENT\.OUT$'
        })) {
            if ($archivo.LastWriteTime -ge $corte -and $archivo.Length -gt 0 -and $archivo.Length -le 20MB) {
                $encontrados.Add($archivo)
            }
        }
    } catch { }
}
$unicos = @{}
foreach ($archivo in @($encontrados | Sort-Object LastWriteTime -Descending)) {
    if (-not $unicos.ContainsKey($archivo.FullName)) { $unicos[$archivo.FullName] = $archivo }
}
[PSCustomObject]@{ Archivos = @($unicos.Values | Sort-Object LastWriteTime -Descending | Select-Object -First ([int]$config.MaxArchivos)) }
'@
    $busqueda = Invoke-ResponsiveWorker -ScriptText $codigoBusqueda -Arguments @($payload) `
        -TimeoutSeconds 900 -Activity 'Buscando bitacoras CONTPAQi'
    if (-not $busqueda.Correcto -or -not $busqueda.Resultado) {
        Write-Log -Mensaje "No se completo la busqueda de bitacoras: $($busqueda.Error)" -Nivel WARN
        return @()
    }
    return @($busqueda.Resultado.Archivos)
}

function Resolve-ErrorBitacoraCONTPAQi {
    param([AllowEmptyString()][string]$Texto)
    if ([string]::IsNullOrWhiteSpace($Texto)) { return $null }
    $t = $Texto

    if ($t -match '(?i)\b(0|zero)\s+(error|errors|errores)\b|\bsin\s+errores?\b|no\s+se\s+(detectaron|encontraron|presentaron)\s+errores?|error\s*(count|code|c[oó]digo)?\s*[:=]\s*0\b|errorlevel\s*[:=]\s*0\b|dbcc.*found\s+0\s+allocation\s+errors?.*0\s+consistency\s+errors?|error\s+log\s+has\s+been\s+reinitialized|logging\s+sql\s+server\s+messages\s+in\s+file|informational\s+message\s+only.*no\s+user\s+action\s+is\s+required') { return $null }

    $categoria = $null
    $severidad = 'MEDIA'
    $diagnostico = ''
    $solucion = ''
    $accion = 'NINGUNA'
    $confianza = 'Media'

    if ($t -match '(?i)(\berror\s+82[345]\b|\berror\s+3414\b|severity\s+(2[1-5])\b|checksum|consistency\s+(error|check)|corrup(t|ci[oó]n)|dbcc\s+checkdb.*(fail|error)|torn\s+page|database.*(suspect|recovery\s+pending)|base\s+de\s+datos.*(sospechosa|recuperaci[oó]n\s+pendiente))') {
        $categoria = 'Integridad de base de datos'; $severidad = 'CRITICA'; $confianza = 'Alta'
        $diagnostico = 'SQL reporta posible dano fisico o logico en una base de datos.'
        $solucion = 'Deten la operacion sobre la empresa, protege un respaldo verificable y ejecuta Mantenimiento SQL / CHECKDB. No uses REPAIR_ALLOW_DATA_LOSS ni edites tablas directamente.'
    } elseif ($t -match '(?i)(\berror\s+9002\b|transaction\s+log.*(full|is\s+full)|log\s+de\s+transacciones.*lleno)') {
        $categoria = 'Log de transacciones lleno'; $severidad = 'ALTA'; $confianza = 'Alta'
        $diagnostico = 'La base no puede registrar mas transacciones por crecimiento, espacio, respaldo de log o una transaccion abierta.'
        $solucion = 'Valida espacio y autogrowth, modelo de recuperacion, respaldos del log y transacciones abiertas. No reduzcas archivos ni cambies el modelo sin definir la recuperacion.'
    } elseif ($t -match '(?i)(\berror\s+(3201|3013)\b|backup.*(failed|failure|fall[oó])|cannot\s+open\s+backup\s+device)') {
        $categoria = 'Respaldo SQL fallido'; $severidad = 'ALTA'; $confianza = 'Alta'
        $diagnostico = 'SQL no pudo crear o leer un respaldo por ruta, espacio, permisos o dispositivo.'
        $solucion = 'Valida la ruta desde la cuenta del servicio SQL, espacio disponible y permisos del destino; despues genera y verifica un respaldo nuevo.'
    } elseif ($t -match '(?i)(\berror\s+1205\b|deadlock\s+victim|interbloqueo)') {
        $categoria = 'Interbloqueo SQL'; $severidad = 'MEDIA'; $confianza = 'Alta'
        $diagnostico = 'SQL cancelo una transaccion porque dos procesos se bloquearon mutuamente.'
        $solucion = 'Correlaciona usuarios y operacion, revisa indices/estadisticas y bloqueos repetitivos. Mantenimiento SQL puede ayudar, pero primero conserva la hora y base afectada.'
    } elseif ($t -match '(?i)(disk\s+full|no\s+space\s+left|espacio\s+(en\s+disco\s+)?insuficiente|insufficient\s+disk|error\s+112\b|could\s+not\s+allocate\s+space)') {
        $categoria = 'Espacio en disco'; $severidad = 'ALTA'; $confianza = 'Alta'; $accion = 'LIMPIAR_TEMP_CONTPAQ'
        $diagnostico = 'El sistema no pudo escribir datos, temporales o respaldos por falta de espacio.'
        $solucion = 'Libera espacio en la unidad afectada y valida crecimiento de archivos SQL. La reparacion automatica solo limpia temporales propios de CONTPAQi.'
    } elseif ($t -match '(?i)(duplicate\s+key|clave\s+duplicada|duplicate\s+entry|[ií]ndice\s+duplicad|cannot\s+insert\s+duplicate)') {
        $categoria = 'Llave o indice duplicado'; $severidad = 'ALTA'; $confianza = 'Alta'
        $diagnostico = 'La aplicacion intento guardar una llave que ya existe; puede ser una inconsistencia conocida o una version desactualizada.'
        $solucion = 'Genera respaldo, valida la version/parches del producto y usa utilerias oficiales o soporte CONTPAQi. No elimines registros ni indices manualmente.'
    } elseif ($t -match '(?i)(collation|conflict.*intercalaci[oó]n|intercalaci[oó]n.*conflict)') {
        $categoria = 'Intercalacion SQL'; $severidad = 'ALTA'; $confianza = 'Alta'
        $diagnostico = 'Existe un conflicto de intercalacion entre SQL, tablas o expresiones.'
        $solucion = 'Respalda y revisa la intercalacion con Configuracion ADD o las utilerias oficiales. No ejecutes ALTER masivos sin un plan de recuperacion.'
    } elseif ($t -match '(?i)(\blogin\s+failed\b|error\s+18456\b|inicio\s+de\s+sesi[oó]n.*(fall|error)|usuario.*no.*asociado.*conexi[oó]n)') {
        $categoria = 'Autenticacion SQL'; $severidad = 'ALTA'; $confianza = 'Alta'
        $diagnostico = 'SQL rechazo las credenciales o el modo de autenticacion configurado.'
        $solucion = 'Confirma servidor/instancia, usuario, modo mixto y estado del login. No cambies contrasenas hasta identificar que configuracion consume cada sistema.'
    } elseif ($t -match '(?i)(cannot\s+generate\s+sspi|sspi\s+context|principal\s+name\s+is\s+incorrect|nombre\s+principal.*incorrect)') {
        $categoria = 'Identidad Windows / SSPI'; $severidad = 'ALTA'; $confianza = 'Alta'
        $diagnostico = 'Windows no pudo validar la identidad Kerberos usada para conectarse a SQL.'
        $solucion = 'Valida hora, dominio, DNS, cuenta del servicio SQL y SPN. Prueba nombre FQDN e IP para aislar el problema; no reinicies SQL a ciegas.'
    } elseif ($t -match '(?i)(host\s+not\s+found|no\s+se\s+pudo\s+resolver|name\s+or\s+service\s+not\s+known|dns.*(fail|error)|nombre.*servidor.*no.*encontr)') {
        $categoria = 'Resolucion de nombre / DNS'; $severidad = 'ALTA'; $confianza = 'Alta'; $accion = 'LIMPIAR_DNS'
        $diagnostico = 'El equipo no puede convertir el nombre del servidor en una IP valida.'
        $solucion = 'Valida el nombre configurado, DNS e IP del servidor. Se puede limpiar la cache DNS local y volver a probar conectividad.'
    } elseif ($t -match '(?i)(network-related|instance-specific|server\s+was\s+not\s+found|error\s+(26|40)\b|sql.*(connection|conexi[oó]n).*(fail|error|timeout)|no\s+se\s+pudo\s+(abrir|establecer).*(sql|base\s+de\s+datos))') {
        $categoria = 'Conexion con SQL Server'; $severidad = 'ALTA'; $confianza = 'Alta'; $accion = 'INICIAR_SQL'
        $diagnostico = 'La instancia SQL no responde, el nombre es incorrecto o la red/puerto bloquea la conexion.'
        $solucion = 'Valida instancia, servicio SQL, SQL Browser cuando aplique, TCP/IP, firewall y conectividad con el servidor detectado.'
    } elseif ($t -match '(?i)(msmq|message\s+queu(e|ing)|cola(s)?\s+de\s+mensajes?)') {
        $categoria = 'Colas de mensajes MSMQ'; $severidad = 'ALTA'; $confianza = 'Alta'; $accion = 'INICIAR_MSMQ'
        $diagnostico = 'La comunicacion interna de CONTPAQi no puede usar Microsoft Message Queuing.'
        $solucion = 'Valida que la caracteristica MSMQ y su servicio esten instalados y activos. El Toolbox no elimina colas porque podrian contener trabajo pendiente.'
    } elseif ($t -match '(?i)((licen(c|s)|appkey|authserver).*(error|fail|fall|no\s+se\s+pudo|denegad|vencid)|(error|fail|fall).*(licen(c|s)|appkey|authserver))') {
        $categoria = 'Licenciamiento CONTPAQi'; $severidad = 'ALTA'; $confianza = 'Alta'; $accion = 'INICIAR_CONTPAQ'
        $diagnostico = 'El sistema no puede validar la licencia o comunicarse con AuthServer/AppKey.'
        $solucion = 'Valida servicios de licenciamiento, servidor configurado, puertos y que cliente/servidor tengan versiones compatibles.'
    } elseif ($t -match '(?i)((saci|servidor\s+de\s+aplicaciones).*(error|fail|fall|timeout|interrump|no\s+se\s+pudo|rechaz)|(error|fail|fall|interrump).*(saci|servidor\s+de\s+aplicaciones))') {
        $categoria = 'Servidor de aplicaciones SACI'; $severidad = 'ALTA'; $confianza = 'Alta'; $accion = 'INICIAR_CONTPAQ'
        $diagnostico = 'Se interrumpio la comunicacion con el Servidor de Aplicaciones CONTPAQi.'
        $solucion = 'Valida el servidor detectado, conectividad, puertos y servicios SACI. Si se requiere reinicio, cierra primero los sistemas y confirma que no haya usuarios trabajando.'
    } elseif ($t -match '(?i)(access\s+denied|acceso\s+denegado|unauthori[sz]ed|permiso(s)?\s+(insuficiente|denegado)|no\s+tiene\s+permisos?)') {
        $categoria = 'Permisos de archivos o Windows'; $severidad = 'ALTA'; $confianza = 'Alta'
        $diagnostico = 'La cuenta que ejecuta el sistema no tiene acceso al recurso indicado.'
        $solucion = 'Identifica la ruta o recurso exacto y valida permisos de recurso compartido y NTFS. No otorgues Control total de forma general.'
    } elseif ($t -match '(?i)(could\s+not\s+load\s+(file|assembly)|file\s+not\s+found|dll\s+not\s+found|no\s+se\s+encontr[oó].*(archivo|dll|m[oó]dulo)|m[oó]dulo.*no\s+se\s+encontr)') {
        $categoria = 'Archivo o componente faltante'; $severidad = 'ALTA'; $confianza = 'Alta'
        $diagnostico = 'Falta un archivo, DLL o componente requerido, o su version no coincide.'
        $solucion = 'Comprueba antivirus/cuarentena y ejecuta Reparar desde el instalador oficial de la misma version. No descargues DLL individuales de sitios externos.'
    } elseif ($t -match '(?i)(timeout|timed\s+out|tiempo\s+de\s+espera|se\s+excedi[oó].*tiempo)') {
        $categoria = 'Tiempo de espera agotado'; $severidad = 'MEDIA'; $confianza = 'Media'
        $diagnostico = 'Una operacion tardo mas de lo permitido por red, carga del servidor, bloqueo o consulta lenta.'
        $solucion = 'Correlaciona la hora con SQL, red y eventos de Windows; revisa bloqueos, recursos y latencia antes de aumentar tiempos de espera.'
    } elseif ($t -match '(?i)(outofmemory|out\s+of\s+memory|memoria\s+insuficiente)') {
        $categoria = 'Memoria insuficiente'; $severidad = 'ALTA'; $confianza = 'Alta'
        $diagnostico = 'El proceso o el sistema operativo no pudo reservar memoria.'
        $solucion = 'Revisa memoria disponible, procesos CONTPAQi/SQL y paginacion. Actualiza el sistema si el fallo se repite con una operacion concreta.'
    } elseif ($t -match '(?i)(unhandled\s+exception|nullreference|stackoverflow|excepci[oó]n\s+no\s+controlada|\bfatal\b|\bcritical\b)') {
        $categoria = 'Excepcion de la aplicacion'; $severidad = 'ALTA'; $confianza = 'Media'
        $diagnostico = 'Un modulo termino de forma inesperada; el texto y la hora permiten ubicar el componente responsable.'
        $solucion = 'Repite el flujo controladamente, valida version/parches y correlaciona con servicios, SQL y Visor de eventos.'
    } elseif ($t -match '(?i)(\bexception\b|\berror\b|\bfailed\b|\bfailure\b|\bfall[oó]\b|\bfallido\b|no\s+se\s+pudo)') {
        $categoria = 'Error de aplicacion'; $severidad = 'MEDIA'; $confianza = 'Media'
        $diagnostico = 'La bitacora registro una operacion fallida que requiere correlacion con su modulo y hora.'
        $solucion = 'Revisa el origen mostrado, el paso que ejecutaba el usuario y los eventos de Windows de la misma hora. Conserva esta evidencia antes de reparar.'
    }

    if (-not $categoria) { return $null }
    return [PSCustomObject]@{
        Categoria  = $categoria
        Severidad  = $severidad
        Diagnostico = $diagnostico
        Solucion   = $solucion
        Accion     = $accion
        Confianza  = $confianza
    }
}

function Get-FirmaErrorBitacoraCONTPAQi {
    param([string]$Texto, [string]$Categoria)
    $firma = (Protect-TextoBitacoraCONTPAQi -Texto $Texto -LongitudMaxima 500).ToLowerInvariant()
    $firma = $firma -replace '\b\d{1,4}[-/]\d{1,2}[-/]\d{1,4}\b', '<fecha>'
    $firma = $firma -replace '\b\d{1,2}:\d{2}(:\d{2})?(\.\d+)?\s*(a\.?\s*m\.?|p\.?\s*m\.?)?\b', '<hora>'
    $firma = $firma -replace '\b[0-9a-f]{8}-[0-9a-f-]{27,36}\b', '<guid>'
    $firma = $firma -replace '\b\d{4,}\b', '<n>'
    $firma = $firma -replace '\s+', ' '
    return "$Categoria|$($firma.Trim())"
}

function Get-FechaTextoBitacoraCONTPAQi {
    param([string]$Texto, [datetime]$FechaPredeterminada)
    if ([string]::IsNullOrWhiteSpace($Texto)) { return $FechaPredeterminada }
    $coincidencia = [regex]::Match($Texto, '(?i)\b(?<fecha>(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{4})\s+\d{1,2}:\d{2}(?::\d{2})?(?:\.\d+)?(?:\s*[ap]\.?\s*m\.?)?)')
    if (-not $coincidencia.Success) { return $FechaPredeterminada }
    $valor = $coincidencia.Groups['fecha'].Value -replace '(?i)a\.?\s*m\.?', 'AM' -replace '(?i)p\.?\s*m\.?', 'PM'
    $fecha = [datetime]::MinValue
    foreach ($cultura in @([Globalization.CultureInfo]::CurrentCulture, [Globalization.CultureInfo]::InvariantCulture, [Globalization.CultureInfo]::GetCultureInfo('es-MX'))) {
        if ([datetime]::TryParse($valor, $cultura, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$fecha)) { return $fecha }
    }
    return $FechaPredeterminada
}

function Get-AnalisisBitacorasCONTPAQi {
    param(
        [ValidateRange(1, 365)][int]$Dias = 30,
        [ValidateRange(10, 500)][int]$MaxArchivos = 150,
        [ValidateRange(100, 10000)][int]$LineasPorArchivo = 2000,
        [ValidateRange(5, 100)][int]$MaxHallazgos = 35
    )
    $archivos = @(Get-ArchivosBitacoraCONTPAQi -Dias $Dias -MaxArchivos $MaxArchivos)
    $hallazgosCrudos = New-Object System.Collections.Generic.List[object]
    $lineasRevisadas = 0
    $eventosRevisados = 0
    $patronCandidato = '(?i)(\berror\b|\bexception\b|\bfatal\b|\bcritical\b|\bfailed\b|\bfailure\b|\bfall[oó]\b|\bfallido\b|no\s+se\s+pudo|could\s+not|not\s+found|denegad|access\s+denied|unauthori[sz]ed|timeout|timed\s+out|tiempo\s+de\s+espera|checksum|corrup|18456|82[345]|3414|9002|3201|3013|1205|severity\s+2[1-5]|suspect|recovery\s+pending|deadlock|interbloqueo|sspi|duplicate\s+key|clave\s+duplicada|collation|intercalaci[oó]n|msmq|message\s+queu|disk\s+full|no\s+space|out\s+of\s+memory|memoria\s+insuficiente|network-related|instance-specific|host\s+not\s+found|interrump|vencid)'

    foreach ($archivo in $archivos) {
        try {
            $lineas = @(Get-Content -LiteralPath $archivo.FullName -Tail $LineasPorArchivo -ErrorAction Stop)
            $lineasRevisadas += $lineas.Count
            for ($i = 0; $i -lt $lineas.Count; $i++) {
                if (($i % 250) -eq 0) { Refresh-Log }
                $linea = [string]$lineas[$i]
                if ([string]::IsNullOrWhiteSpace($linea) -or $linea -notmatch $patronCandidato) { continue }
                $fragmentos = New-Object System.Collections.Generic.List[string]
                $fragmentos.Add($linea)
                for ($avance = 1; $avance -le 2 -and ($i + $avance) -lt $lineas.Count; $avance++) {
                    $siguiente = [string]$lineas[$i + $avance]
                    if ([string]::IsNullOrWhiteSpace($siguiente)) { break }
                    $esContinuacion = ($siguiente -match '(?i)^\s*(at\s|en\s|--->|caused\s+by|inner\s*exception|detalle\s*[:=]|message\s*[:=]|mensaje\s*[:=]|system\.[a-z].*exception)')
                    if (-not $esContinuacion -and $linea.Length -ge 100) { break }
                    if ($siguiente -match '^\s*\d{1,4}[-/]\d{1,2}[-/]\d{1,4}\s+\d{1,2}:\d{2}' -and -not $esContinuacion) { break }
                    $fragmentos.Add($siguiente.Trim())
                }
                $texto = Protect-TextoBitacoraCONTPAQi -Texto ($fragmentos -join ' | ')
                $regla = Resolve-ErrorBitacoraCONTPAQi -Texto $texto
                if (-not $regla) { continue }
                $hallazgosCrudos.Add([PSCustomObject]@{
                    Fecha = Get-FechaTextoBitacoraCONTPAQi -Texto $linea -FechaPredeterminada $archivo.LastWriteTime
                    Fuente = $archivo.FullName; TipoFuente = 'Archivo'
                    Texto = $texto; Categoria = $regla.Categoria; Severidad = $regla.Severidad
                    Diagnostico = $regla.Diagnostico; Solucion = $regla.Solucion
                    Accion = $regla.Accion; Confianza = $regla.Confianza
                    Firma = Get-FirmaErrorBitacoraCONTPAQi -Texto $texto -Categoria $regla.Categoria
                })
            }
        } catch { }
        Refresh-Log
    }

    foreach ($nombreLog in @('Application', 'System')) {
        try {
            $eventos = @(Get-WinEvent -FilterHashtable @{ LogName = $nombreLog; StartTime = (Get-Date).AddDays(-[Math]::Min($Dias, 14)); Level = @(1, 2, 3) } -MaxEvents 350 -ErrorAction Stop)
            $eventosRevisados += $eventos.Count
            $indiceEvento = 0
            foreach ($evento in $eventos) {
                $indiceEvento++
                if (($indiceEvento % 50) -eq 0) { Refresh-Log }
                $mensaje = Protect-TextoBitacoraCONTPAQi -Texto $evento.Message
                $relacionado = ($evento.ProviderName -match '(?i)CONTPAQ|COMPAC|SACI|APPKEY|AUTHSERVER|MSSQL|SQLSERVER|SQLBROWSER|MSMQ') -or
                    ($mensaje -match '(?i)CONTPAQ|COMPAC|SACI|APPKEY|AUTHSERVER|SQL\s+SERVER|MSMQ')
                if (-not $relacionado) { continue }
                $regla = Resolve-ErrorBitacoraCONTPAQi -Texto $mensaje
                if (-not $regla) { continue }
                $fuente = "Visor de eventos/$nombreLog/$($evento.ProviderName) (Id $($evento.Id))"
                $hallazgosCrudos.Add([PSCustomObject]@{
                    Fecha = $evento.TimeCreated; Fuente = $fuente; TipoFuente = 'Evento'
                    Texto = $mensaje; Categoria = $regla.Categoria; Severidad = $regla.Severidad
                    Diagnostico = $regla.Diagnostico; Solucion = $regla.Solucion
                    Accion = $regla.Accion; Confianza = $regla.Confianza
                    Firma = Get-FirmaErrorBitacoraCONTPAQi -Texto $mensaje -Categoria $regla.Categoria
                })
            }
        } catch { }
    }

    $agrupados = New-Object System.Collections.Generic.List[object]
    foreach ($grupo in @($hallazgosCrudos | Group-Object Firma)) {
        $ultimo = @($grupo.Group | Sort-Object Fecha -Descending | Select-Object -First 1)[0]
        $fuentes = @($grupo.Group | Select-Object -ExpandProperty Fuente -Unique)
        $agrupados.Add([PSCustomObject]@{
            Fecha = $ultimo.Fecha; Fuente = $ultimo.Fuente; Fuentes = $fuentes
            TipoFuente = $ultimo.TipoFuente; Texto = $ultimo.Texto
            Categoria = $ultimo.Categoria; Severidad = $ultimo.Severidad
            Diagnostico = $ultimo.Diagnostico; Solucion = $ultimo.Solucion
            Accion = $ultimo.Accion; Confianza = $ultimo.Confianza
            Repeticiones = $grupo.Count
        })
    }
    $ordenados = @($agrupados | Sort-Object @{ Expression = {
        switch ($_.Severidad) { 'CRITICA' { 0 } 'ALTA' { 1 } default { 2 } }
    } }, @{ Expression = { $_.Fecha }; Descending = $true } | Select-Object -First $MaxHallazgos)

    return [PSCustomObject]@{
        Dias = $Dias; Archivos = $archivos; ArchivosRevisados = $archivos.Count
        LineasRevisadas = $lineasRevisadas; EventosRevisados = $eventosRevisados
        Hallazgos = $ordenados; HallazgosTotales = $hallazgosCrudos.Count
    }
}

function Invoke-ReparacionesBitacoraCONTPAQi {
    param([object[]]$Hallazgos)
    $accionesSolicitadas = @($Hallazgos | Where-Object { $_.Accion -and $_.Accion -ne 'NINGUNA' } | Select-Object -ExpandProperty Accion -Unique)
    $acciones = New-Object System.Collections.Generic.List[object]

    if ('INICIAR_SQL' -in $accionesSolicitadas -and (Get-PerfilEquipo) -match 'Servidor') {
        foreach ($servicio in @(Get-ServiciosMotorSQL | Where-Object { $_.Status -ne 'Running' -and $_.StartType -ne 'Disabled' })) {
            $acciones.Add([PSCustomObject]@{ Codigo = 'SERVICIO'; Objetivo = $servicio.Name; Descripcion = "Iniciar motor SQL detenido: $($servicio.Name)" })
        }
        $browser = Get-Service -Name 'SQLBrowser' -ErrorAction SilentlyContinue
        if ($browser -and $browser.Status -ne 'Running' -and $browser.StartType -ne 'Disabled') {
            $acciones.Add([PSCustomObject]@{ Codigo = 'SERVICIO'; Objetivo = $browser.Name; Descripcion = 'Iniciar SQL Server Browser detenido' })
        }
    }
    if ('INICIAR_CONTPAQ' -in $accionesSolicitadas) {
        foreach ($servicio in @(Get-ServiciosCONTPAQiDetectados | Where-Object {
            $_.Status -ne 'Running' -and $_.StartType -ne 'Disabled' -and
            ($_.Name -notmatch '^MSSQL|^SQLBrowser$')
        })) {
            $acciones.Add([PSCustomObject]@{ Codigo = 'SERVICIO'; Objetivo = $servicio.Name; Descripcion = "Iniciar servicio CONTPAQi detenido: $($servicio.Name)" })
        }
    }
    if ('INICIAR_MSMQ' -in $accionesSolicitadas) {
        $msmq = Get-Service -Name 'MSMQ' -ErrorAction SilentlyContinue
        if ($msmq -and $msmq.Status -ne 'Running' -and $msmq.StartType -ne 'Disabled') {
            $acciones.Add([PSCustomObject]@{ Codigo = 'SERVICIO'; Objetivo = 'MSMQ'; Descripcion = 'Iniciar Microsoft Message Queuing (MSMQ)' })
        }
    }
    if ('LIMPIAR_DNS' -in $accionesSolicitadas) {
        $acciones.Add([PSCustomObject]@{ Codigo = 'DNS'; Objetivo = ''; Descripcion = 'Limpiar la cache DNS local' })
    }
    if ('LIMPIAR_TEMP_CONTPAQ' -in $accionesSolicitadas) {
        $temp = Get-TamanoCarpetasTemporalesCONTPAQi
        if ($temp.Bytes -gt 0) {
            $acciones.Add([PSCustomObject]@{ Codigo = 'TEMP'; Objetivo = ''; Descripcion = "Limpiar solo temporales CONTPAQi ($($temp.MB) MB)" })
        }
    }

    $accionesUnicas = @($acciones | Sort-Object Codigo, Objetivo -Unique)
    if ($accionesUnicas.Count -eq 0) {
        Write-Log -Mensaje 'No hay cambios automaticos aplicables. El diagnostico conserva pasos manuales seguros.' -Nivel INFO
        return
    }

    Write-SeccionMenu -Titulo 'REPARACIONES SEGURAS DISPONIBLES' -Color 'Green'
    foreach ($accion in $accionesUnicas) { Write-Log -Mensaje $accion.Descripcion -Nivel INFO }
    Write-Log -Mensaje 'No se modificaran bases, colas MSMQ, permisos ni archivos de programa.' -Nivel WARN
    if (-not (Confirmar-Movimiento -Frase 'APLICAR REPARACIONES' `
        -Accion "Aplicar $($accionesUnicas.Count) reparacion(es) sugerida(s) por las bitacoras" `
        -Detalle 'Se iniciaran servicios y/o se limpiaran DNS y temporales, segun los hallazgos mostrados.')) {
        Write-Log -Mensaje 'Diagnostico finalizado sin realizar cambios.' -Nivel INFO
        return
    }

    $correctas = 0; $fallidas = 0
    foreach ($accion in $accionesUnicas) {
        try {
            switch ($accion.Codigo) {
                'SERVICIO' {
                    $resultadoServicio = Invoke-ServiceActionResponsive -Nombre $accion.Objetivo -Accion Start -TimeoutSegundos 75
                    if (-not $resultadoServicio.Correcto) { throw $resultadoServicio.Error }
                }
                'DNS' {
                    $resultadoDns = Invoke-DnsFlushResponsive
                    if (-not $resultadoDns.Correcto) { throw $resultadoDns.Error }
                }
                'TEMP' {
                    $eliminados = 0
                    foreach ($ruta in (Get-TamanoCarpetasTemporalesCONTPAQi).Rutas) { $eliminados += Clear-TemporalSeguro -Ruta $ruta }
                    Write-Log -Mensaje "Temporales retirados: $eliminados elemento(s)." -Nivel OK
                }
            }
            $correctas++
            Write-Log -Mensaje "$($accion.Descripcion): verificado." -Nivel OK
        } catch {
            $fallidas++
            Write-Log -Mensaje "$($accion.Descripcion): $($_.Exception.Message)" -Nivel ERROR
        }
    }
    Write-Log -Mensaje "Resultado de reparacion: $correctas correcta(s), $fallidas fallida(s)." -Nivel $(if ($fallidas -eq 0) { 'OK' } else { 'WARN' })
}

function Invoke-AnalisisBitacorasCONTPAQi {
    Write-Encabezado -Titulo 'ANALISIS DE ERRORES CONTPAQi' -Subtitulo 'Bitacoras y eventos del equipo actual' -Color 'Cyan'
    Write-Log -Mensaje "Buscando evidencia local de los ultimos 30 dias en $env:COMPUTERNAME..." -Nivel PROGRESS
    $analisis = Get-AnalisisBitacorasCONTPAQi -Dias 30 -MaxArchivos 150 -LineasPorArchivo 2500 -MaxHallazgos 35

    Write-SeccionMenu -Titulo 'COBERTURA' -Color 'Magenta'
    Write-Log -Mensaje "Archivos revisados: $($analisis.ArchivosRevisados) | Lineas recientes: $($analisis.LineasRevisadas) | Eventos de Windows: $($analisis.EventosRevisados)" -Nivel INFO
    if ($analisis.ArchivosRevisados -eq 0) {
        Write-Log -Mensaje 'No se localizaron bitacoras recientes en las rutas conocidas de CONTPAQi.' -Nivel WARN
    } else {
        foreach ($archivo in @($analisis.Archivos | Select-Object -First 8)) {
            Write-Log -Mensaje "Bitacora: $($archivo.FullName) | $($archivo.LastWriteTime.ToString('dd/MM/yyyy HH:mm'))" -Nivel INFO
        }
        if ($analisis.ArchivosRevisados -gt 8) {
            Write-Log -Mensaje "... y $($analisis.ArchivosRevisados - 8) archivo(s) adicional(es)." -Nivel INFO
        }
    }

    $hallazgos = @($analisis.Hallazgos)
    if ($hallazgos.Count -eq 0) {
        Write-SeccionMenu -Titulo 'RESULTADO' -Color 'Green'
        Write-Log -Mensaje 'No se encontraron errores reconocibles en la evidencia reciente.' -Nivel OK
        Write-Log -Mensaje 'Esto no descarta un problema sin bitacora; reproduce el fallo y ejecuta nuevamente este analisis.' -Nivel INFO
        return
    }

    Write-SeccionMenu -Titulo 'ERRORES, PISTAS Y SOLUCIONES' -Color 'Red'
    $indice = 0
    foreach ($hallazgo in $hallazgos) {
        $indice++
        $nivel = if ($hallazgo.Severidad -eq 'CRITICA') { 'ERROR' } elseif ($hallazgo.Severidad -eq 'ALTA') { 'WARN' } else { 'INFO' }
        Write-Log -Mensaje "#$indice [$($hallazgo.Severidad)] $($hallazgo.Categoria) | Repeticiones: $($hallazgo.Repeticiones) | Ultimo: $($hallazgo.Fecha.ToString('dd/MM/yyyy HH:mm'))" -Nivel $nivel
        Write-Log -Mensaje "Fuente: $($hallazgo.Fuente)" -Nivel INFO
        Write-Log -Mensaje "Error detectado: $($hallazgo.Texto)" -Nivel $nivel
        Write-Log -Mensaje "Pista ($($hallazgo.Confianza)): $($hallazgo.Diagnostico)" -Nivel INFO
        Write-Log -Mensaje "Solucion sugerida: $($hallazgo.Solucion)" -Nivel INFO
        if ($hallazgo.Accion -ne 'NINGUNA') {
            Write-Log -Mensaje 'Hay una reparacion local segura que puede evaluarse al final.' -Nivel OK
        }
        Write-Host ''
    }

    $criticas = @($hallazgos | Where-Object Severidad -eq 'CRITICA').Count
    $altas = @($hallazgos | Where-Object Severidad -eq 'ALTA').Count
    $medias = @($hallazgos | Where-Object Severidad -eq 'MEDIA').Count
    Write-Separador -Color $(if ($criticas -gt 0) { $Script:ColorError } else { $Script:ColorAdvertencia })
    Write-Log -Mensaje "RESUMEN: $criticas critica(s), $altas alta(s), $medias media(s) | $($analisis.HallazgosTotales) registro(s) agrupados en $($hallazgos.Count) causa(s)." -Nivel $(if ($criticas -gt 0) { 'ERROR' } else { 'WARN' })
    if ($criticas -gt 0) {
        Write-Log -Mensaje 'Se detecto riesgo de integridad: no se aplicaran cambios automaticos sobre bases de datos.' -Nivel ERROR
    }
    Invoke-ReparacionesBitacoraCONTPAQi -Hallazgos $hallazgos
}

function Invoke-EscaneoInteligenteCONTPAQi {
    Write-Encabezado -Titulo 'ESCANEO Y REPARACION LOCAL' -Subtitulo 'Diagnostico y reparacion del equipo actual' -Color 'Cyan'
    $inicio = Get-Date
    $alertas = 0
    $advertencias = 0
    $serviciosReparables = @()

    Write-SeccionMenu -Titulo '1. PRODUCTOS Y RUTAS' -Color 'Magenta'
    $productos = @(Get-ProgramasInstalados | Where-Object {
        $_.DisplayName -match '(?i)CONTPAQ|COMPAC|APPKEY|SACI|XML\s*EN\s*L[IÍ]NEA|MICROSOFT SQL SERVER|SQL SERVER NATIVE CLIENT|ODBC DRIVER.*SQL'
    } | Sort-Object DisplayName, DisplayVersion -Unique)
    if ($productos.Count -eq 0) {
        $advertencias++
        Write-Log -Mensaje 'No se detectaron productos CONTPAQi en el registro de programas.' -Nivel WARN
    } else {
        $gruposProductos = @($productos | Group-Object -Property {
            Get-FabricanteSistemaCONTPAQi -Nombre $_.DisplayName -Editor $_.Publisher
        } | Sort-Object Name)
        foreach ($grupo in $gruposProductos) {
            Write-Log -Mensaje "SISTEMAS - $($grupo.Name.ToUpper()) ($($grupo.Count))" -Nivel INFO
            foreach ($producto in @($grupo.Group | Sort-Object DisplayName, DisplayVersion)) {
                $version = if ($producto.DisplayVersion) { $producto.DisplayVersion } else { 'N/D' }
                Write-Log -Mensaje "Sistema: $($producto.DisplayName) | Version $version" -Nivel OK
            }
        }
    }
    $rutas = @(Get-RutasCONTPAQi)
    foreach ($ruta in $rutas) { Write-Log -Mensaje "Ruta detectada: $ruta" -Nivel INFO }

    Write-SeccionMenu -Titulo '2. SERVICIOS Y EJECUTABLES' -Color 'Green'
    $servicios = @(Get-ServiciosCONTPAQiDetectados)
    if ($servicios.Count -eq 0) {
        $advertencias++
        Write-Log -Mensaje 'No se detectaron servicios CONTPAQi o motores SQL.' -Nivel WARN
    }
    $gruposServicios = @($servicios | Group-Object -Property {
        $esMotor = ($_.Name -eq 'MSSQLSERVER' -or $_.Name -match '^MSSQL\$[^$]+$')
        Get-FabricanteServicioCONTPAQi -Nombre $_.Name -DisplayName $_.DisplayName -Ruta '' -EsMotorSQL $esMotor
    } | Sort-Object Name)
    foreach ($grupo in $gruposServicios) {
        Write-Log -Mensaje "SERVICIOS - $($grupo.Name.ToUpper()) ($($grupo.Count))" -Nivel INFO
        foreach ($servicio in @($grupo.Group | Sort-Object Name)) {
            $nivel = if ($servicio.Status -eq 'Running') { 'OK' } else { 'WARN' }
            Write-Log -Mensaje "Servicio: $($servicio.Name) | $($servicio.Status) | Inicio: $($servicio.StartType)" -Nivel $nivel
            if ($servicio.Status -ne 'Running') {
                $advertencias++
                if (-not (Test-ServicioDeshabilitado -Nombre $servicio.Name)) { $serviciosReparables += $servicio.Name }
            }
            try {
                $cimServicio = Get-CimInstance Win32_Service -Filter "Name='$($servicio.Name)'" -ErrorAction Stop
                $rutaExe = Get-RutaEjecutableServicio -Comando $cimServicio.PathName
                if ($rutaExe -and -not (Test-Path -LiteralPath $rutaExe -PathType Leaf)) {
                    $alertas++
                    Write-Log -Mensaje "$($servicio.Name): ejecutable ausente en $rutaExe" -Nivel ERROR
                }
            } catch {
                Write-Log -Mensaje "$($servicio.Name): no se pudo validar la ruta binaria." -Nivel INFO
            }
        }
    }
    foreach ($servicioApp in @(Get-ServiciosAplicacionCONTPAQi | Where-Object {
        $_.Status -ne 'Running' -and -not (Test-ServicioDeshabilitado -Nombre $_.Name)
    })) {
        $serviciosReparables += $servicioApp.Name
    }
    $serviciosReparables = @($serviciosReparables | Select-Object -Unique)

    Write-SeccionMenu -Titulo '3. SQL SERVER' -Color 'Green'
    $motores = @(Get-ServiciosMotorSQL)
    foreach ($motor in $motores) {
        $instancia = Get-NombreInstanciaSQL -NombreServicio $motor.Name
        if ($motor.Status -ne 'Running') {
            $alertas++
            Write-Log -Mensaje "$instancia detenido; no se puede validar la base de datos." -Nivel ERROR
            continue
        }
        $pruebaSql = Test-ConexionSQLLocal -Instancia $instancia -TimeoutSegundos 4
        if ($pruebaSql.Correcto) {
            Write-Log -Mensaje "$instancia responde | SQL $($pruebaSql.Version) | $($pruebaSql.Servidor)" -Nivel OK
        } else {
            $alertas++
            Write-Log -Mensaje "$instancia no acepta conexion integrada: $($pruebaSql.Error)" -Nivel ERROR
        }
    }

    Write-SeccionMenu -Titulo '4. RECURSOS, EVENTOS Y TEMPORALES' -Color 'Yellow'
    foreach ($unidad in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null })) {
        $libreGB = [math]::Round($unidad.Free / 1GB, 1)
        $nivelDisco = if ($libreGB -ge 10) { 'OK' } else { 'WARN' }
        if ($libreGB -lt 10) { $advertencias++ }
        Write-Log -Mensaje "Unidad $($unidad.Name): $libreGB GB libres." -Nivel $nivelDisco
    }
    if (Test-ReinicioPendiente) {
        $advertencias++
        Write-Log -Mensaje 'Windows tiene un reinicio pendiente.' -Nivel WARN
    } else {
        Write-Log -Mensaje 'Sin reinicio pendiente.' -Nivel OK
    }
    $analisisLogs = Get-AnalisisBitacorasCONTPAQi -Dias 7 -MaxArchivos 80 -LineasPorArchivo 1000 -MaxHallazgos 12
    $hallazgosLogs = @($analisisLogs.Hallazgos)
    if ($hallazgosLogs.Count -gt 0) {
        $criticosLogs = @($hallazgosLogs | Where-Object Severidad -eq 'CRITICA').Count
        $altosLogs = @($hallazgosLogs | Where-Object Severidad -eq 'ALTA').Count
        if ($criticosLogs -gt 0) { $alertas += [Math]::Min(2, $criticosLogs) } else { $advertencias++ }
        Write-Log -Mensaje "Bitacoras: $($hallazgosLogs.Count) causa(s) reciente(s) | $criticosLogs critica(s) | $altosLogs alta(s)." -Nivel $(if ($criticosLogs -gt 0) { 'ERROR' } else { 'WARN' })
        foreach ($categoria in @($hallazgosLogs | Group-Object Categoria | Sort-Object Count -Descending | Select-Object -First 3)) {
            Write-Log -Mensaje "Pista: $($categoria.Name) ($($categoria.Count))" -Nivel INFO
        }
        Write-Log -Mensaje 'Abre la carpeta de reportes para consultar el mensaje exacto y conservar evidencia del escaneo.' -Nivel INFO
    } else {
        Write-Log -Mensaje "Bitacoras: sin errores reconocibles en $($analisisLogs.ArchivosRevisados) archivo(s) y $($analisisLogs.EventosRevisados) evento(s) revisados." -Nivel OK
    }
    $temporales = Get-TamanoCarpetasTemporalesCONTPAQi
    Write-Log -Mensaje "Temporales especificos de CONTPAQi: $($temporales.MB) MB." -Nivel $(if ($temporales.MB -ge 250) { 'WARN' } else { 'OK' })
    $limpiarTemporales = ($temporales.MB -ge 250)
    if ($limpiarTemporales) { $advertencias++ }

    $puntaje = [math]::Max(0, 100 - ($alertas * 15) - ($advertencias * 5))
    $duracion = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    Write-Separador -Color $(if ($puntaje -ge 80) { $Script:ColorExito } elseif ($puntaje -ge 55) { $Script:ColorAdvertencia } else { $Script:ColorError })
    Write-Log -Mensaje "SALUD DEL EQUIPO: $puntaje/100 | $alertas alerta(s) | $advertencias advertencia(s) | $duracion s" -Nivel $(if ($puntaje -ge 80) { 'OK' } elseif ($puntaje -ge 55) { 'WARN' } else { 'ERROR' })

    $cantidadReparaciones = $serviciosReparables.Count + $(if ($limpiarTemporales) { 1 } else { 0 })
    if ($cantidadReparaciones -eq 0) {
        Write-Log -Mensaje 'No se encontraron reparaciones automaticas seguras pendientes.' -Nivel OK
        Write-Log -Mensaje 'Si la incidencia continua, abre las bitacoras y revisa el detalle del escaneo.' -Nivel INFO
        return
    }

    Write-SeccionMenu -Titulo 'REPARACIONES SEGURAS DISPONIBLES' -Color 'Green'
    foreach ($nombre in $serviciosReparables) { Write-Log -Mensaje "Iniciar y verificar servicio detenido: $nombre" -Nivel INFO }
    if ($limpiarTemporales) { Write-Log -Mensaje 'Limpiar solo temporales de CONTPAQi/Compac.' -Nivel INFO }
    if (-not (Confirmar-Movimiento -Frase 'APLICAR REPARACIONES' `
        -Accion "Aplicar $cantidadReparaciones reparacion(es) del escaneo" `
        -Detalle 'Se iniciaran los servicios detenidos detectados y/o se limpiaran temporales CONTPAQi.')) {
        Write-Log -Mensaje 'Escaneo terminado sin realizar cambios.' -Nivel INFO
        return
    }

    $reparadas = 0
    $fallidas = 0
    $nombresApp = @(Get-ServiciosAplicacionCONTPAQi | Select-Object -ExpandProperty Name -Unique)
    $appPendientes = @($serviciosReparables | Where-Object { $_ -in $nombresApp })
    if ($appPendientes.Count -gt 0) {
        $resultadoApp = Start-TodosServiciosCONTPAQiVerificado
        $fallosApp = @($appPendientes | Where-Object { $_ -in $resultadoApp.FallidosNombres })
        $reparadas += ($appPendientes.Count - $fallosApp.Count)
        $fallidas += $resultadoApp.Fallidos
        Write-Log -Mensaje "Comprobacion final CONTPAQi: $($resultadoApp.Correctos) activo(s), $($resultadoApp.Fallidos) con incidencia." -Nivel $(if ($resultadoApp.Fallidos -eq 0) { 'OK' } else { 'WARN' })
    }

    $otrosPendientes = @($serviciosReparables | Where-Object { $_ -notin $nombresApp } | Sort-Object {
        if ($_ -match '^MSSQL') { return -2 }
        if ($_ -eq 'SQLBrowser') { return -1 }
        return 0
    })
    foreach ($nombre in $otrosPendientes) {
        $resultadoInicio = Invoke-ServiceActionResponsive -Nombre $nombre -Accion Start -TimeoutSegundos 90
        if ($resultadoInicio.Correcto) {
            $reparadas++
            Write-Log -Mensaje "$nombre iniciado y verificado." -Nivel OK
        } else {
            $fallidas++
            Write-Log -Mensaje "No se pudo iniciar $($nombre): $($resultadoInicio.Error)" -Nivel ERROR
        }
    }
    if ($limpiarTemporales) {
        $eliminados = 0
        foreach ($ruta in $temporales.Rutas) { $eliminados += Clear-TemporalSeguro -Ruta $ruta }
        $reparadas++
        Write-Log -Mensaje "Temporales limpiados: $eliminados elemento(s)." -Nivel OK
    }
    Write-Separador -Color $(if ($fallidas -eq 0) { $Script:ColorExito } else { $Script:ColorAdvertencia })
    Write-Log -Mensaje "REPARACION FINAL: $reparadas correcta(s), $fallidas fallida(s)." -Nivel $(if ($fallidas -eq 0) { 'OK' } else { 'WARN' })
}

# --- DESINSTALACION DE SISTEMAS CONTPAQi ---

function Get-ProgramasInstalados {
    $rutas = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $programas = @()
    foreach ($ruta in $rutas) {
        Get-ItemProperty -Path $ruta -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            ForEach-Object {
                $programas += [PSCustomObject]@{
                    DisplayName          = $_.DisplayName
                    DisplayVersion       = $_.DisplayVersion
                    Publisher            = $_.Publisher
                    InstallLocation      = $_.InstallLocation
                    UninstallString      = $_.UninstallString
                    QuietUninstallString = $_.QuietUninstallString
                    PSChildName          = $_.PSChildName
                }
            }
    }
    return $programas
}

function Find-SistemasCoincidentes {
    param([array]$Patrones)

    $instalados = Get-ProgramasInstalados
    $coincidencias = @()
    foreach ($prog in $instalados) {
        foreach ($patron in $Patrones) {
            if ($prog.DisplayName -like $patron) {
                $coincidencias += $prog
                break
            }
        }
    }
    return $coincidencias | Sort-Object DisplayName -Unique
}

function Invoke-DesinstalacionSilenciosa {
    param($Programa)

    Write-Log -Mensaje "Desinstalando: $($Programa.DisplayName)..." -Nivel PROGRESS

    try {
        if ($Programa.QuietUninstallString) {
            $cmd = $Programa.QuietUninstallString
        } else {
            $cmd = $Programa.UninstallString
        }

        if (-not $cmd) {
            Write-Log -Mensaje "No se encontro comando de desinstalacion para $($Programa.DisplayName)." -Nivel ERROR
            return $false
        }

        if ($Programa.PSChildName -match '^\{[0-9A-Fa-f\-]+\}$' -and $cmd -match 'msiexec') {
            $proceso = Invoke-ProcessResponsive -FilePath 'msiexec.exe' -ArgumentList "/x $($Programa.PSChildName) /qn /norestart" `
                -TimeoutSeconds 3600 -Activity "Desinstalando $($Programa.DisplayName)" -Hidden
            if (-not $proceso.Correcto) { throw $proceso.Error }
            if ($proceso.ExitCode -notin @(0, 1641, 3010)) { throw "msiexec finalizo con codigo $($proceso.ExitCode)." }
            Write-Log -Mensaje "$($Programa.DisplayName) desinstalado (MSI silencioso)." -Nivel OK
            return $true
        }

        if ($cmd -match '^"([^"]+)"(.*)$') {
            $exe  = $matches[1]
            $args = $matches[2].Trim()
        } elseif ($cmd -match '^(\S+)(.*)$') {
            $exe  = $matches[1]
            $args = $matches[2].Trim()
        } else {
            $exe  = $cmd
            $args = ''
        }

        $esInnoSetup = ($exe -match 'unins\d*\.exe$')

        if ($esInnoSetup) {
            if ($args -notmatch '/verysilent|/silent') {
                $args = "$args /VERYSILENT /SUPPRESSMSGBOXES /NORESTART".Trim()
            }
            $proceso = Invoke-ProcessResponsive -FilePath $exe -ArgumentList $args `
                -TimeoutSeconds 3600 -Activity "Desinstalando $($Programa.DisplayName)" -Hidden
            if (-not $proceso.Correcto) { throw $proceso.Error }
            if ($proceso.ExitCode -notin @(0, 1641, 3010)) { throw "El desinstalador finalizo con codigo $($proceso.ExitCode)." }
            Write-Log -Mensaje "$($Programa.DisplayName) desinstalado (Inno Setup, modo silencioso)." -Nivel OK
        } else {
            Write-Log -Mensaje 'Desinstalador nativo detectado: se abrira su propia ventana/consola. No la cierres, se cerrara sola al terminar.' -Nivel WARN
            $proceso = Invoke-ProcessResponsive -FilePath $exe -ArgumentList $args `
                -TimeoutSeconds 3600 -Activity "Desinstalando $($Programa.DisplayName)"
            if (-not $proceso.Correcto) { throw $proceso.Error }
            if ($proceso.ExitCode -notin @(0, 1641, 3010)) { throw "El desinstalador finalizo con codigo $($proceso.ExitCode)." }
            Write-Log -Mensaje "$($Programa.DisplayName) desinstalado (modo nativo)." -Nivel OK
        }

        return $true
    } catch {
        Write-Log -Mensaje "Error al desinstalar $($Programa.DisplayName): $($_.Exception.Message)" -Nivel ERROR
        return $false
    }
}

function Get-RutaEjecutableServicio {
    param([string]$Comando)
    if ([string]::IsNullOrWhiteSpace($Comando)) { return $null }

    $expandido = [Environment]::ExpandEnvironmentVariables($Comando.Trim())
    if ($expandido -match '^"([^"]+\.exe)"') { return $matches[1] }
    if ($expandido -match '^(.+?\.exe)(?:\s|$)') { return $matches[1].Trim('"') }
    return $null
}

function Remove-ServiciosResiduales {
    Write-Log -Mensaje 'Verificando servicios residuales tras la desinstalacion...' -Nivel PROGRESS
    $limpiados = 0

    $serviciosRevisar = @()
    $serviciosRevisar += (Get-ServiciosTerminal | ForEach-Object { $_.Servicio })
    $serviciosRevisar += (Get-ServiciosPID)

    foreach ($svc in ($serviciosRevisar | Sort-Object Name -Unique)) {
        try {
            $wmi = Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue
            $rutaBin = $wmi.PathName
            $ejecutableExiste = $false
            if ($rutaBin) {
                $rutaLimpia = Get-RutaEjecutableServicio -Comando $rutaBin
                if ($rutaLimpia) {
                    $ejecutableExiste = Test-Path -LiteralPath $rutaLimpia -PathType Leaf -ErrorAction SilentlyContinue
                } else {
                    Write-Log -Mensaje "No se pudo validar la ruta del servicio $($svc.Name); se conserva por seguridad." -Nivel WARN
                    continue
                }
            }
            if (-not $ejecutableExiste) {
                Write-Log -Mensaje "Servicio residual detectado: $($svc.Name) (ejecutable ausente). Eliminando..." -Nivel WARN
                if ($svc.Status -eq 'Running') { $null = Invoke-ServiceActionResponsive -Nombre $svc.Name -Accion Stop -TimeoutSegundos 60 }
                sc.exe delete $svc.Name | Out-Null
                $limpiados++
            }
        } catch { }
    }

    if ($limpiados -gt 0) {
        Write-Log -Mensaje "$limpiados servicio(s) residual(es) eliminado(s)." -Nivel OK
    } else {
        Write-Log -Mensaje 'Sin servicios residuales detectados.' -Nivel OK
    }
}

function Preparar-SistemaParaDesinstalar {
    Write-Log -Mensaje 'Cerrando procesos CONTPAQi/PID antes de desinstalar...' -Nivel PROGRESS
    foreach ($p in (Get-ProcesosCONTPAQi | Where-Object { -not $_.EsToolbox })) {
        Stop-ProcesoForzado -ProcessId $p.PID | Out-Null
    }
    foreach ($p in (Get-ProcesosPID | Where-Object { -not $_.EsToolbox })) {
        Stop-ProcesoForzado -ProcessId $p.PID | Out-Null
    }
}

function Desinstalar-SistemaPorId {
    param([string]$IdSistema)

    $entrada = $Script:SistemasMapa[$IdSistema]
    if (-not $entrada) {
        Write-Log -Mensaje "Sistema '$IdSistema' no reconocido." -Nivel ERROR
        return
    }

    Write-Encabezado -Titulo 'DESINSTALACION CONTPAQi' -Subtitulo $entrada.Nombre -Color $Script:ColorServidor

    $coincidencias = @(Find-SistemasCoincidentes -Patrones $entrada.Patrones)
    if ($coincidencias.Count -eq 0) {
        Write-Log -Mensaje "No se encontro '$($entrada.Nombre)' instalado (cualquier version) en este equipo." -Nivel WARN
        return
    }

    Write-Linea -Texto " Se encontraron $($coincidencias.Count) coincidencia(s):" -Color $Script:ColorAcento
    foreach ($c in $coincidencias) { Write-Log -Mensaje $c.DisplayName -Nivel INFO }

    if (-not (Confirmar-Movimiento -Frase 'DESINSTALAR' `
        -Accion "Desinstalar '$($entrada.Nombre)'" `
        -Detalle "Se eliminaran todas las versiones detectadas de este producto y sus servicios residuales verificables.")) {
        Write-Log -Mensaje 'Cancelado.' -Nivel WARN
        return
    }

    Preparar-SistemaParaDesinstalar

    $ok = 0; $fallidos = 0
    foreach ($prog in $coincidencias) {
        if (Invoke-DesinstalacionSilenciosa -Programa $prog) { $ok++ } else { $fallidos++ }
    }

    Remove-ServiciosResiduales

    Write-Host ''
    Write-Separador -Color $Script:ColorExito
    Write-Linea -Texto " DESINSTALACION DE '$($entrada.Nombre.ToUpper())' COMPLETADA" -Color $Script:ColorExito -Centrado
    Write-Log -Mensaje "Resultado: $ok exitosos, $fallidos fallidos" -Nivel OK
}

function Desinstalar-TodosLosSistemas {
    Write-Encabezado -Titulo 'DESINSTALACION TOTAL' -Subtitulo 'TODOS los sistemas CONTPAQi (cualquier version)' -Color $Script:ColorServidor

    $patronesTotales = @()
    foreach ($id in $Script:SistemasMapa.Keys) { $patronesTotales += $Script:SistemasMapa[$id].Patrones }
    $patronesTotales += @('*CONTPAQi*', '*CONTPAQ*', '*Compac*')

    $coincidencias = @(Find-SistemasCoincidentes -Patrones $patronesTotales)
    if ($coincidencias.Count -eq 0) {
        Write-Log -Mensaje 'No se detectaron sistemas CONTPAQi instalados en este equipo.' -Nivel WARN
        return
    }

    Write-Linea -Texto " Se encontraron $($coincidencias.Count) programa(s) a desinstalar:" -Color $Script:ColorAdvertencia
    foreach ($c in $coincidencias) { Write-Log -Mensaje $c.DisplayName -Nivel INFO }

    if (-not (Confirmar-Movimiento -Frase 'DESINSTALAR TODO' `
        -Accion 'Desinstalar todos los sistemas CONTPAQi listados' `
        -Detalle 'Esta accion retirara todos los productos detectados y puede requerir reiniciar Windows.')) {
        Write-Log -Mensaje 'Cancelado.' -Nivel WARN
        return
    }

    Preparar-SistemaParaDesinstalar

    $ok = 0; $fallidos = 0
    foreach ($prog in $coincidencias) {
        if (Invoke-DesinstalacionSilenciosa -Programa $prog) { $ok++ } else { $fallidos++ }
    }

    Remove-ServiciosResiduales

    Write-Host ''
    Write-Separador -Color $Script:ColorExito
    Write-Linea -Texto ' DESINSTALACION TOTAL COMPLETADA' -Color $Script:ColorExito -Centrado
    Write-Log -Mensaje "Resultado: $ok exitosos, $fallidos fallidos" -Nivel OK
}

function Show-MenuDesinstalar {
    Write-Encabezado -Titulo 'DESINSTALAR SISTEMAS CONTPAQi' -Subtitulo 'Cualquier version detectada automaticamente' -Color $Script:ColorServidor

    Write-SeccionMenu -Titulo 'SELECCIONA EL SISTEMA A DESINSTALAR' -Color $Script:ColorAdvertencia
    foreach ($id in ($Script:SistemasMapa.Keys | Sort-Object)) {
        Write-OpcionMenu -Tecla $id -Descripcion $Script:SistemasMapa[$id].Nombre -Color 'Yellow'
    }
    Write-OpcionMenu -Tecla '7' -Descripcion 'TODOS los sistemas CONTPAQi (desinstalacion masiva)' -Color 'Red' -Icono '[!!] '
    Write-OpcionMenu -Tecla '0' -Descripcion 'Volver al menu principal' -Color 'White'

    $sel = ''
    if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        $sel = Show-GUIInput -Titulo 'Toolbox - Desinstalar' -Mensaje 'Selecciona una opcion (1-7, 0=Volver):'
    } else {
        $sel = (Read-Host ' Selecciona una opcion').Trim()
    }

    switch ($sel) {
        '0' { return }
        '7' { Desinstalar-TodosLosSistemas }
        default {
            if ($Script:SistemasMapa.ContainsKey($sel)) {
                Desinstalar-SistemaPorId -IdSistema $sel
            } else {
                Write-Log -Mensaje 'Opcion no valida.' -Nivel ERROR
            }
        }
    }
}

# --- SERVICESDEV: INSTALACION, CONTROL Y MONITOREO ---

function Get-ServicesDevSourceExe {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$PSScriptRoot)) {
        $candidates += Join-Path $PSScriptRoot 'SERVICESDEV\app\ServicesDev.exe'
    }
    # PS2EXE expone ScriptRoot como la carpeta del ejecutable compilado.
    if (-not [string]::IsNullOrWhiteSpace([string]$ScriptRoot)) {
        $candidates += Join-Path $ScriptRoot 'SERVICESDEV\app\ServicesDev.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$PSCommandPath)) {
        $candidates += Join-Path (Split-Path -Parent $PSCommandPath) 'SERVICESDEV\app\ServicesDev.exe'
    }
    # La compilacion portable inyecta ServicesDev aqui como recurso embebido.
    $candidates += Join-Path $env:TEMP 'CONTPAQiToolbox\ServicesDev.exe'
    $candidates = @($candidates | Select-Object -Unique)
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    return $null
}

function Get-ServicesDevConfiguredNames {
    $configPath = Join-Path $Script:ServicesDevInstallDir 'watchdog.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return @() }
    try {
        return @((Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop | ConvertFrom-Json).ServiceNames |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    } catch {
        return @()
    }
}

function Get-ServicesDevDetectedNames {
    return @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -match '(?i)CONTPAQ|Compac|AuthServer' -and
            $_.Name -notin @($Script:ServicesDevName, $Script:ServicesDevLegacyName) -and
            $_.Name -notmatch '(?i)MSSQL|SQLAgent|SQLBrowser|SQLWriter' -and
            $_.DisplayName -notmatch '(?i)SQL\s*Server|SQL\s*Agent|SQL\s*Browser|SQL\s*Writer'
        } |
        Sort-Object DisplayName |
        Select-Object -ExpandProperty Name -Unique)
}

function Install-OrUpdateServicesDev {
    $sourceExe = Get-ServicesDevSourceExe
    if (-not $sourceExe) {
        throw "No se encontro SERVICESDEV\app\ServicesDev.exe junto a Toolbox. Conserva esa carpeta al distribuir la herramienta."
    }

    $serviceNames = @(Get-ServicesDevConfiguredNames)
    if ($serviceNames.Count -eq 0) { $serviceNames = @(Get-ServicesDevDetectedNames) }
    if ($serviceNames.Count -eq 0) {
        throw 'No se detectaron servicios CONTPAQi/Compac/AuthServer para vigilar.'
    }

    $visibleNames = foreach ($name in $serviceNames) {
        $item = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($item) { "- $($item.DisplayName) [$name]" } else { "- $name [NO EXISTE]" }
    }
    $existing = Get-Service -Name $Script:ServicesDevName -ErrorAction SilentlyContinue
    $verb = if ($existing) { 'actualizar' } else { 'instalar' }
    $question = "Se va a $verb ServicesDev con revision cada 5 segundos y estos servicios:`n`n$($visibleNames -join "`n")"
    $fraseConfirmacion = if ($existing) { 'ACTUALIZAR MONITOR' } else { 'INSTALAR MONITOR' }
    if (-not (Confirmar-Movimiento -Frase $fraseConfirmacion -Accion "$($verb.ToUpperInvariant()) ServicesDev" `
        -Detalle $question)) { return $false }

    $legacy = Get-Service -Name $Script:ServicesDevLegacyName -ErrorAction SilentlyContinue
    if ($legacy) {
        if ($legacy.Status -ne 'Stopped') { $null = Invoke-ServiceActionResponsive -Nombre $Script:ServicesDevLegacyName -Accion Stop -TimeoutSegundos 60 }
        & sc.exe delete $Script:ServicesDevLegacyName | Out-Null
    }
    if ($existing -and $existing.Status -ne 'Stopped') {
        $resultadoDetenerMonitor = Invoke-ServiceActionResponsive -Nombre $Script:ServicesDevName -Accion Stop -TimeoutSegundos 60
        if (-not $resultadoDetenerMonitor.Correcto) { throw "No se pudo detener ServicesDev: $($resultadoDetenerMonitor.Error)" }
    }

    if (-not (Test-Path -LiteralPath $Script:ServicesDevInstallDir -PathType Container)) {
        New-Item -ItemType Directory -Path $Script:ServicesDevInstallDir -Force -ErrorAction Stop | Out-Null
    }
    $destinationExe = Join-Path $Script:ServicesDevInstallDir 'ServicesDev.exe'
    Copy-Item -LiteralPath $sourceExe -Destination $destinationExe -Force -ErrorAction Stop

    $config = [ordered]@{
        CheckIntervalSeconds   = 5
        StartTimeoutSeconds    = 45
        FailureCooldownMinutes = 5
        ServiceNames           = @($serviceNames)
    }
    $configPath = Join-Path $Script:ServicesDevInstallDir 'watchdog.json'
    $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding UTF8 -ErrorAction Stop

    if (-not $existing) {
        New-Service -Name $Script:ServicesDevName -BinaryPathName ('"' + $destinationExe + '"') `
            -DisplayName 'ServicesDev - Monitor CONTPAQi' `
            -Description 'Vigila e inicia los servicios configurados de CONTPAQi.' `
            -StartupType Automatic -ErrorAction Stop | Out-Null
    } else {
        & sc.exe config $Script:ServicesDevName binPath= ('"' + $destinationExe + '"') start= auto | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'No fue posible actualizar la configuracion del servicio ServicesDev.' }
    }
    & sc.exe description $Script:ServicesDevName 'Vigila e inicia los servicios configurados de CONTPAQi.' | Out-Null
    & sc.exe failure $Script:ServicesDevName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
    & sc.exe failureflag $Script:ServicesDevName 1 | Out-Null
    $resultadoIniciarMonitor = Invoke-ServiceActionResponsive -Nombre $Script:ServicesDevName -Accion Start -TimeoutSegundos 75
    if (-not $resultadoIniciarMonitor.Correcto) { throw "No se pudo iniciar ServicesDev: $($resultadoIniciarMonitor.Error)" }
    Write-Log -Mensaje "ServicesDev $verb correctamente; vigila $($serviceNames.Count) servicio(s) cada 5 segundos." -Nivel OK
    return $true
}

function Invoke-ServicesDevControl {
    param([ValidateSet('Start', 'Stop', 'Restart')][string]$Action)
    $service = Get-Service -Name $Script:ServicesDevName -ErrorAction SilentlyContinue
    if (-not $service) { throw 'ServicesDev no esta instalado. Usa Instalar desde el monitor.' }
    if ($Action -eq 'Start' -and $service.Status -eq 'Running') {
        Write-Log -Mensaje 'ServicesDev ya esta en ejecucion; no se realizo ningun cambio.' -Nivel INFO
        return
    }
    if ($Action -eq 'Stop' -and $service.Status -eq 'Stopped') {
        Write-Log -Mensaje 'ServicesDev ya esta detenido; no se realizo ningun cambio.' -Nivel INFO
        return
    }
    $datosConfirmacion = @{
        Start = @{ Frase = 'INICIAR MONITOR'; Accion = 'Iniciar ServicesDev'; Detalle = 'El monitor volvera a vigilar e iniciar automaticamente los servicios configurados.' }
        Stop = @{ Frase = 'DETENER MONITOR'; Accion = 'Detener ServicesDev'; Detalle = 'El monitoreo automatico quedara suspendido hasta que se inicie nuevamente.' }
        Restart = @{ Frase = 'REINICIAR MONITOR'; Accion = 'Reiniciar ServicesDev'; Detalle = 'El monitoreo se detendra brevemente y volvera a iniciar.' }
    }[$Action]
    if (-not (Confirmar-Movimiento -Frase $datosConfirmacion.Frase -Accion $datosConfirmacion.Accion -Detalle $datosConfirmacion.Detalle)) { return }
    switch ($Action) {
        'Start' {
            if ($service.Status -ne 'Running') {
                $resultado = Invoke-ServiceActionResponsive -Nombre $Script:ServicesDevName -Accion Start -TimeoutSegundos 75
                if (-not $resultado.Correcto) { throw $resultado.Error }
            }
        }
        'Stop' {
            if ($service.Status -ne 'Stopped') {
                $resultado = Invoke-ServiceActionResponsive -Nombre $Script:ServicesDevName -Accion Stop -TimeoutSegundos 60
                if (-not $resultado.Correcto) { throw $resultado.Error }
            }
        }
        'Restart' {
            if ($service.Status -ne 'Stopped') {
                $resultadoDetener = Invoke-ServiceActionResponsive -Nombre $Script:ServicesDevName -Accion Stop -TimeoutSegundos 60
                if (-not $resultadoDetener.Correcto) { throw $resultadoDetener.Error }
            }
            $resultadoIniciar = Invoke-ServiceActionResponsive -Nombre $Script:ServicesDevName -Accion Start -TimeoutSegundos 75
            if (-not $resultadoIniciar.Correcto) { throw $resultadoIniciar.Error }
        }
    }
    $past = @{ Start = 'iniciado'; Stop = 'detenido'; Restart = 'reiniciado' }[$Action]
    Write-Log -Mensaje "ServicesDev se ha $past correctamente." -Nivel OK
}


function Show-ServicesDevMonitor {
    # Capturar estos valores localmente es importante: GetNewClosure crea un
    # modulo dinamico y las referencias $Script: ya no apuntan al modulo Toolbox.
    $palette = $Script:GUIColors
    $serviceName = $Script:ServicesDevName
    $installDir = $Script:ServicesDevInstallDir
    $refreshMs = $Script:ServicesDevRefreshMs

    $dialog = New-Object System.Windows.Forms.Form
    Set-ModernFormStyle -Form $dialog
    $dialog.Text = 'ServicesDev - Monitor de servicios CONTPAQi'
    $dialog.Size = New-Object System.Drawing.Size(1040, 720)
    $dialog.MinimumSize = New-Object System.Drawing.Size(900, 620)
    $dialog.StartPosition = 'CenterParent'
    $dialog.BackColor = $palette.BG
    $dialog.ForeColor = $palette.Text
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $dialog.ShowIcon = $true

    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = 'Top'
    $headerPanel.Height = 82
    $headerPanel.BackColor = $palette.Header
    $dialog.Controls.Add($headerPanel)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.AutoSize = $true
    $titleLabel.Location = New-Object System.Drawing.Point(84, 13)
    $titleLabel.Text = 'ServicesDev'
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $palette.Text
    $titleLabel.BackColor = [System.Drawing.Color]::Transparent
    $headerPanel.Controls.Add($titleLabel)

    $subtitleLabel = New-Object System.Windows.Forms.Label
    $subtitleLabel.Location = New-Object System.Drawing.Point(86, 48)
    $subtitleLabel.Size = New-Object System.Drawing.Size(660, 21)
    $subtitleLabel.Text = 'Supervision automatica de servicios CONTPAQi'
    $subtitleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $subtitleLabel.ForeColor = $palette.TextDim
    $subtitleLabel.BackColor = [System.Drawing.Color]::Transparent
    $headerPanel.Controls.Add($subtitleLabel)

    $monitorLogo = New-ToolboxLogoPictureBox -Size 54
    $monitorLogo.Location = New-Object System.Drawing.Point(18, 13)
    $headerPanel.Controls.Add($monitorLogo)

    $stateBadge = New-Object System.Windows.Forms.Label
    $stateBadge.Location = New-Object System.Drawing.Point(790, 21)
    $stateBadge.Size = New-Object System.Drawing.Size(210, 38)
    $stateBadge.Anchor = 'Top,Right'
    $stateBadge.Text = 'ACTUALIZANDO...'
    $stateBadge.TextAlign = 'MiddleCenter'
    $stateBadge.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Bold)
    $stateBadge.ForeColor = $palette.BG
    $stateBadge.BackColor = $palette.Accent
    $headerPanel.Controls.Add($stateBadge)

    $footer = New-Object System.Windows.Forms.FlowLayoutPanel
    $footer.Dock = 'Bottom'
    $footer.Height = 64
    $footer.FlowDirection = 'LeftToRight'
    $footer.WrapContents = $false
    $footer.Padding = New-Object System.Windows.Forms.Padding(10, 8, 6, 6)
    $footer.BackColor = $palette.Header
    $dialog.Controls.Add($footer)

    $status = New-Object System.Windows.Forms.Label
    $status.Dock = 'Bottom'
    $status.Height = 27
    $status.TextAlign = 'MiddleLeft'
    $status.Padding = New-Object System.Windows.Forms.Padding(13, 0, 0, 0)
    $status.ForeColor = $palette.TextDim
    $status.BackColor = $palette.BG
    $dialog.Controls.Add($status)

    $split = New-Object System.Windows.Forms.SplitContainer
    $split.Dock = 'Fill'
    $split.Orientation = 'Horizontal'
    $split.SplitterDistance = 260
    $split.SplitterWidth = 5
    $split.BackColor = $palette.Separator
    $split.Panel1.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 8)
    $split.Panel2.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 10)
    $dialog.Controls.Add($split)
    $split.BringToFront()

    $servicesTitle = New-Object System.Windows.Forms.Label
    $servicesTitle.Dock = 'Top'
    $servicesTitle.Height = 30
    $servicesTitle.Text = '  SERVICIOS VIGILADOS'
    $servicesTitle.TextAlign = 'MiddleLeft'
    $servicesTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $servicesTitle.ForeColor = $palette.Accent
    $servicesTitle.BackColor = $palette.Button
    $split.Panel1.Controls.Add($servicesTitle)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.SelectionMode = 'FullRowSelect'
    $grid.BackgroundColor = $palette.LogBG
    $grid.BorderStyle = 'None'
    $grid.EnableHeadersVisualStyles = $false
    $grid.ColumnHeadersHeight = 34
    $grid.ColumnHeadersDefaultCellStyle.BackColor = $palette.Header
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = $palette.TextDim
    $grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $grid.DefaultCellStyle.BackColor = $palette.LogBG
    $grid.DefaultCellStyle.ForeColor = $palette.Text
    $grid.DefaultCellStyle.SelectionBackColor = $palette.ButtonActive
    $grid.DefaultCellStyle.SelectionForeColor = $palette.Text
    $grid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(5, 0, 5, 0)
    $grid.RowTemplate.Height = 30
    $grid.AlternatingRowsDefaultCellStyle.BackColor = $palette.Surface
    $null = $grid.Columns.Add('Name', 'Nombre interno')
    $null = $grid.Columns.Add('Status', 'Estado')
    $null = $grid.Columns.Add('DisplayName', 'Nombre visible')
    $grid.Columns['Name'].FillWeight = 35
    $grid.Columns['Status'].FillWeight = 18
    $grid.Columns['DisplayName'].FillWeight = 47
    $gridStatusFont = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $split.Panel1.Controls.Add($grid)
    $servicesTitle.BringToFront()

    $logsTitle = New-Object System.Windows.Forms.Label
    $logsTitle.Dock = 'Top'
    $logsTitle.Height = 30
    $logsTitle.Text = '  SERVICESDEV - DIAGNOSTICO EN VIVO'
    $logsTitle.TextAlign = 'MiddleLeft'
    $logsTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $logsTitle.ForeColor = $palette.Accent
    $logsTitle.BackColor = $palette.Button
    $split.Panel2.Controls.Add($logsTitle)

    $logBox = New-Object System.Windows.Forms.RichTextBox
    $logBox.Dock = 'Fill'
    $logBox.ReadOnly = $true
    $logBox.BackColor = $palette.LogBG
    $logBox.ForeColor = $palette.TextDim
    $logBox.BorderStyle = 'None'
    $logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
    $logBoldFont = New-Object System.Drawing.Font($logBox.Font, [System.Drawing.FontStyle]::Bold)
    $logBox.DetectUrls = $false
    $logBox.WordWrap = $true
    $logBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
    $split.Panel2.Controls.Add($logBox)
    $logsTitle.BringToFront()

    $newButton = {
        param($text, $color, $textColor)
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $text
        $button.Size = New-Object System.Drawing.Size(118, 40)
        $button.Margin = New-Object System.Windows.Forms.Padding(4, 2, 4, 2)
        $button.BackColor = $color
        $button.ForeColor = $textColor
        $button.FlatStyle = 'Flat'
        $button.FlatAppearance.BorderSize = 0
        $button.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
        $button.Cursor = [System.Windows.Forms.Cursors]::Hand
        Set-ModernButtonStyle -Button $button -BaseColor $color -TextColor $textColor -HoverColor ([System.Windows.Forms.ControlPaint]::Light($color, 0.12))
        $footer.Controls.Add($button)
        return $button
    }
    $btnInstall = & $newButton 'Instalar' $palette.Accent $palette.BG
    $btnUpdate  = & $newButton 'Actualizar app' $palette.ButtonActive $palette.Text
    $btnStart   = & $newButton 'Iniciar' $palette.Success $palette.BG
    $btnStop    = & $newButton 'Detener' $palette.Error $palette.BG
    $btnRestart = & $newButton 'Reiniciar' $palette.Warning $palette.BG
    $btnRefresh = & $newButton 'Refrescar' $palette.ButtonActive $palette.Text
    $btnExit    = & $newButton 'Salir' $palette.Button $palette.Text
    foreach ($pendingButton in @($btnInstall, $btnUpdate, $btnStart, $btnStop, $btnRestart)) {
        $pendingButton.Enabled = $false
    }

    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.SetToolTip($btnInstall, 'Instala ServicesDev por primera vez y detecta los servicios CONTPAQi.')
    $toolTip.SetToolTip($btnUpdate, 'Actualiza el ejecutable y conserva los servicios vigilados.')
    $toolTip.SetToolTip($btnStart, 'Inicia el watchdog. No modifica directamente los servicios vigilados.')
    $toolTip.SetToolTip($btnStop, 'Detiene el watchdog. Los servicios CONTPAQi permanecen en su estado actual.')
    $toolTip.SetToolTip($btnRestart, 'Reinicia ServicesDev para recargar su configuracion.')
    $toolTip.SetToolTip($btnRefresh, 'Actualiza esta vista inmediatamente.')

    $footer.Add_Resize({
        param($sender, $eventArgs)
        $buttons = @($sender.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] })
        if ($buttons.Count -eq 0) { return }
        $available = $sender.ClientSize.Width - $sender.Padding.Horizontal - ($buttons.Count * 8)
        $buttonWidth = [Math]::Max(88, [Math]::Floor($available / $buttons.Count))
        foreach ($footerButton in $buttons) { $footerButton.Width = $buttonWidth }
    })

    $refreshing = $false
    $refreshView = {
        if ($refreshing -or $dialog.IsDisposed) { return }
        $refreshing = $true
        try {
            $status.ForeColor = $palette.TextDim
            $watchdog = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
            $sourceAvailable = -not [string]::IsNullOrWhiteSpace([string](Get-ServicesDevSourceExe))
            if ($watchdog) {
                $stateText = switch ($watchdog.State) {
                    'Running' { 'EN EJECUCION' }
                    'Stopped' { 'DETENIDO' }
                    default { 'EN TRANSICION' }
                }
                $stateColor = switch ($watchdog.State) {
                    'Running' { $palette.Success }
                    'Stopped' { $palette.Error }
                    default { $palette.Warning }
                }
                $stateBadge.Text = $stateText
                $stateBadge.BackColor = $stateColor
                $stateBadge.ForeColor = $palette.BG
                $subtitleLabel.Text = "Inicio: $($watchdog.StartMode)   |   PID: $($watchdog.ProcessId)   |   Ruta: $installDir"
                $btnInstall.Enabled = $false
                $btnUpdate.Enabled = $sourceAvailable
                $btnStart.Enabled = ($watchdog.State -eq 'Stopped')
                $btnStop.Enabled = ($watchdog.State -eq 'Running')
                $btnRestart.Enabled = ($watchdog.State -eq 'Running')
            } else {
                $stateBadge.Text = 'NO INSTALADO'
                $stateBadge.BackColor = $palette.Error
                $stateBadge.ForeColor = $palette.BG
                $subtitleLabel.Text = if ($sourceAvailable) { 'Listo para instalar y detectar servicios CONTPAQi automaticamente' } else { 'No se encontro el componente ServicesDev incluido con Toolbox' }
                $btnInstall.Enabled = $sourceAvailable
                $btnUpdate.Enabled = $false
                $btnStart.Enabled = $false
                $btnStop.Enabled = $false
                $btnRestart.Enabled = $false
            }

            $grid.Rows.Clear()
            $names = @(Get-ServicesDevConfiguredNames)
            $serviceRows = @()
            foreach ($name in $names) {
                $item = Get-Service -Name $name -ErrorAction SilentlyContinue
                if ($item) {
                    $friendlyStatus = if ($item.Status -eq 'Running') { 'ACTIVO' } else { 'DETENIDO' }
                    $index = $grid.Rows.Add($item.Name, $friendlyStatus, $item.DisplayName)
                    $grid.Rows[$index].Cells['Status'].Style.ForeColor = if ($item.Status -eq 'Running') { $palette.Success } else { $palette.Error }
                    $grid.Rows[$index].Cells['Status'].Style.Font = $gridStatusFont
                    $serviceRows += [PSCustomObject]@{ Name = $item.Name; State = [string]$item.Status; DisplayName = $item.DisplayName }
                } else {
                    $index = $grid.Rows.Add($name, 'NO EXISTE', '-')
                    $grid.Rows[$index].Cells['Status'].Style.ForeColor = $palette.Error
                    $serviceRows += [PSCustomObject]@{ Name = $name; State = 'NO EXISTE'; DisplayName = '-' }
                }
            }
            if ($names.Count -eq 0) { $null = $grid.Rows.Add('-', 'SIN CONFIGURAR', 'Instala ServicesDev para detectar los servicios') }

            $latestLog = Get-ChildItem -LiteralPath (Join-Path $installDir 'logs') -Filter 'watchdog-*.log' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1

            # Construir la misma salida que muestra Diagnostico.cmd, pero con color.
            $diagnosticLines = New-Object System.Collections.Generic.List[object]
            $diagnosticLines.Add([PSCustomObject]@{ Text = ('=' * 76); Color = $palette.Accent; Bold = $false })
            $diagnosticLines.Add([PSCustomObject]@{ Text = '                    SERVICESDEV - DIAGNOSTICO EN VIVO'; Color = $palette.Accent; Bold = $true })
            $diagnosticLines.Add([PSCustomObject]@{ Text = '                           Dev Derek Salinas'; Color = $palette.Text; Bold = $false })
            $diagnosticLines.Add([PSCustomObject]@{ Text = ('=' * 76); Color = $palette.Accent; Bold = $false })
            $diagnosticLines.Add([PSCustomObject]@{ Text = ("Equipo: {0}    Actualizado: {1:yyyy-MM-dd HH:mm:ss}" -f $env:COMPUTERNAME, (Get-Date)); Color = $palette.Text; Bold = $false })
            $diagnosticLines.Add([PSCustomObject]@{ Text = ("Carpeta: {0}" -f $installDir); Color = $palette.TextDim; Bold = $false })
            $diagnosticLines.Add([PSCustomObject]@{ Text = ''; Color = $palette.Text; Bold = $false })

            if ($watchdog) {
                $watchdogColor = if ($watchdog.State -eq 'Running') { $palette.Success } elseif ($watchdog.State -match 'Pending') { $palette.Warning } else { $palette.Error }
                $diagnosticLines.Add([PSCustomObject]@{ Text = ("Watchdog: {0,-12} Inicio: {1,-12} PID: {2}" -f $watchdog.State, $watchdog.StartMode, $watchdog.ProcessId); Color = $watchdogColor; Bold = $true })
                if ($watchdog.ProcessId -gt 0) {
                    $watchdogProcess = Get-Process -Id $watchdog.ProcessId -ErrorAction SilentlyContinue
                    if ($watchdogProcess) {
                        $diagnosticLines.Add([PSCustomObject]@{ Text = ("Proceso iniciado: {0:yyyy-MM-dd HH:mm:ss}  Memoria: {1:N1} MB" -f $watchdogProcess.StartTime, ($watchdogProcess.WorkingSet64 / 1MB)); Color = $palette.TextDim; Bold = $false })
                    }
                }
            } else {
                $diagnosticLines.Add([PSCustomObject]@{ Text = 'Watchdog: NO INSTALADO'; Color = $palette.Error; Bold = $true })
            }

            $diagnosticLines.Add([PSCustomObject]@{ Text = ''; Color = $palette.Text; Bold = $false })
            $diagnosticLines.Add([PSCustomObject]@{ Text = 'SERVICIOS VIGILADOS'; Color = $palette.Accent; Bold = $true })
            $diagnosticLines.Add([PSCustomObject]@{ Text = ('{0,-30} {1,-13} {2}' -f 'Nombre interno', 'Estado', 'Nombre visible'); Color = $palette.TextDim; Bold = $false })
            $diagnosticLines.Add([PSCustomObject]@{ Text = ('-' * 76); Color = $palette.TextDim; Bold = $false })
            foreach ($serviceRow in $serviceRows) {
                $serviceColor = if ($serviceRow.State -eq 'Running') { $palette.Success } else { $palette.Error }
                $diagnosticLines.Add([PSCustomObject]@{ Text = ('{0,-30} {1,-13} {2}' -f $serviceRow.Name, $serviceRow.State, $serviceRow.DisplayName); Color = $serviceColor; Bold = $false })
            }
            if ($serviceRows.Count -eq 0) {
                $diagnosticLines.Add([PSCustomObject]@{ Text = 'No hay servicios configurados.'; Color = $palette.Warning; Bold = $false })
            }

            $diagnosticLines.Add([PSCustomObject]@{ Text = ''; Color = $palette.Text; Bold = $false })
            $diagnosticLines.Add([PSCustomObject]@{ Text = 'ULTIMAS ACCIONES (ultimas 12 lineas)'; Color = $palette.Accent; Bold = $true })
            $diagnosticLines.Add([PSCustomObject]@{ Text = ('-' * 76); Color = $palette.TextDim; Bold = $false })
            if ($latestLog) {
                foreach ($line in @(Get-Content -LiteralPath $latestLog.FullName -Tail 12 -ErrorAction SilentlyContinue)) {
                    $lineColor = $palette.TextDim
                    $isBold = $false
                    if ($line -match '(?i)\[ERROR\]|error|fallo|no pudo|no se pudo') {
                        $lineColor = $palette.Error
                    } elseif ($line -match '(?i)reinici|inicio correctamente|iniciado correctamente|se inicio|running') {
                        $lineColor = $palette.Success
                        $isBold = $true
                    } elseif ($line -match '(?i)intentando iniciar|detenido|\[WARN\]|advertencia') {
                        $lineColor = $palette.Warning
                    }
                    $diagnosticLines.Add([PSCustomObject]@{ Text = $line; Color = $lineColor; Bold = $isBold })
                }
            } else {
                $diagnosticLines.Add([PSCustomObject]@{ Text = 'Todavia no existe una bitacora.'; Color = $palette.TextDim; Bold = $false })
            }

            $logBox.Clear()
            foreach ($diagnosticLine in $diagnosticLines) {
                $logBox.SelectionStart = $logBox.TextLength
                $logBox.SelectionLength = 0
                $logBox.SelectionColor = $diagnosticLine.Color
                $logBox.SelectionFont = if ($diagnosticLine.Bold) { $logBoldFont } else { $logBox.Font }
                $logBox.AppendText("$($diagnosticLine.Text)`r`n")
            }
            $logBox.SelectionStart = 0
            $logBox.ScrollToCaret()
            $logsTitle.Text = if ($latestLog) { "  SERVICESDEV - DIAGNOSTICO EN VIVO  |  $($latestLog.Name)" } else { '  SERVICESDEV - DIAGNOSTICO EN VIVO' }
            $status.Text = " Actualizado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')   |   Automatico cada 5 s   |   $($names.Count) servicio(s) vigilado(s)"
        } catch {
            $status.Text = " Error al actualizar: $($_.Exception.Message)"
            $status.ForeColor = $palette.Error
        } finally {
            $refreshing = $false
        }
    }.GetNewClosure()

    $runControl = {
        param($action)
        try {
            $dialog.UseWaitCursor = $true
            Invoke-ServicesDevControl -Action $action
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'ServicesDev', 'OK', 'Error') | Out-Null
        } finally {
            $dialog.UseWaitCursor = $false
            & $refreshView
        }
    }.GetNewClosure()

    $runInstallOrUpdate = {
        try {
            $dialog.UseWaitCursor = $true
            $null = Install-OrUpdateServicesDev
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'ServicesDev', 'OK', 'Error') | Out-Null
            Write-Log -Mensaje "No fue posible instalar/actualizar ServicesDev: $($_.Exception.Message)" -Nivel ERROR
        } finally {
            $dialog.UseWaitCursor = $false
            & $refreshView
        }
    }.GetNewClosure()

    $btnInstall.Add_Click(({ & $runInstallOrUpdate }).GetNewClosure())
    $btnUpdate.Add_Click(({ & $runInstallOrUpdate }).GetNewClosure())
    $btnStart.Add_Click(({ & $runControl 'Start' }).GetNewClosure())
    $btnStop.Add_Click(({ & $runControl 'Stop' }).GetNewClosure())
    $btnRestart.Add_Click(({ & $runControl 'Restart' }).GetNewClosure())
    $btnRefresh.Add_Click(({ & $refreshView }).GetNewClosure())
    $btnExit.Add_Click(({ $dialog.Close() }).GetNewClosure())

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $refreshMs
    $timer.Add_Tick(({ & $refreshView }).GetNewClosure())
    $dialog.Add_FormClosed(({ $timer.Stop(); $timer.Dispose(); $toolTip.Dispose(); $logBoldFont.Dispose(); $gridStatusFont.Dispose() }).GetNewClosure())
    $dialog.Add_Shown(({ & $refreshView; $timer.Start() }).GetNewClosure())
    $null = if ($Script:GUIForm) { $dialog.ShowDialog($Script:GUIForm) } else { $dialog.ShowDialog() }
    $dialog.Dispose()
}

# --- FUNCIONES GUI PARA ACCIONES ---

function Close-CurrentPanel {
    if ($Script:CurrentPanel) {
        try {
            if (-not $Script:CurrentPanel.IsDisposed) { $Script:CurrentPanel.Dispose() }
        } catch { }
        $Script:CurrentPanel = $null
    }
    if ($Script:LogBox) {
        $Script:LogBox.Visible = $true
        $Script:LogBox.BringToFront()
    }
    if ($Script:LogHeader) {
        $Script:LogHeader.Visible = $true
        $Script:LogHeader.BringToFront()
    }
}

function Show-Accion {
    param(
        [string]$Titulo,
        [string]$Subtitulo,
        [scriptblock]$Accion,
        [string]$Color = 'Cyan'
    )
    if ($Script:IsBusy) { return }
    if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        Close-CurrentPanel
        $Script:LogBox.Clear()
        [System.Windows.Forms.Application]::DoEvents()
    }
    $Script:IsBusy = $true
    if ($Script:GUIForm) {
        $Script:GUIForm.UseWaitCursor = $true
        if ($Script:StatusLabel) {
            $Script:StatusLabel.Text = " Trabajando: $Titulo... Por favor espera."
            $Script:StatusLabel.ForeColor = $Script:GUIColors.Warning
        }
        $Script:GUIForm.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
    try {
        & $Accion
    } catch {
        Write-Log -Mensaje "Error inesperado: $($_.Exception.Message)" -Nivel ERROR
    } finally {
        if ($Script:GUIForm) {
            $Script:GUIForm.UseWaitCursor = $false
            if ($Script:StatusLabel) {
                $Script:StatusLabel.ForeColor = $Script:GUIColors.TextDim
            }
            $Script:GUIForm.Activate()
        }
        $Script:IsBusy = $false
        Write-BarraEstado
    }
}

function Show-Bienvenida {
    Write-Encabezado -Titulo 'CONTPAQi TOOLBOX' -Subtitulo "Equipo detectado: $(Get-PerfilEquipo)" -Color 'Cyan'
    Write-Log -Mensaje 'La herramienta esta lista para trabajar.' -Nivel OK
    Write-Host ''
    Write-SeccionMenu -Titulo 'FLUJO RECOMENDADO' -Color 'Green'
    Write-Log -Mensaje '1. Ejecuta Escaneo y Reparacion para revisar solamente este equipo.' -Nivel INFO
    Write-Log -Mensaje '2. Usa Diagnostico de Red para separar fallas locales, DNS, firewall, SQL o servicios remotos.' -Nivel INFO
    Write-Log -Mensaje '3. Usa Reparar Terminal para recuperar servicios, temporales, red y comunicacion de la estacion.' -Nivel INFO
    Write-Log -Mensaje '4. Usa Analisis del Servidor para localizarlo y obtener su inventario remoto.' -Nivel INFO
    Write-Log -Mensaje '5. Para una base lenta o inestable, usa Mantenimiento SQL directamente en el servidor.' -Nivel INFO
    Write-Log -Mensaje '6. Aplica acciones avanzadas solo despues de revisar el diagnostico y la bitacora.' -Nivel INFO
    Write-Host ''
    Write-Log -Mensaje 'Las acciones avanzadas solicitan confirmacion y muestran su validacion final.' -Nivel WARN
}

# --- CONSTRUCCION DEL FORMULARIO GUI ---

function New-GUIButton {
    param(
        [string]$Text,
        [int]$W = 226, [int]$H = 34,
        [System.Drawing.Color]$BgColor,
        [System.Drawing.Color]$TextColor,
        [System.Drawing.Font]$Font,
        [scriptblock]$OnClick
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Size = New-Object System.Drawing.Size($W, $H)
    $btn.MinimumSize = New-Object System.Drawing.Size($W, $H)
    $btn.MaximumSize = New-Object System.Drawing.Size($W, $H)
    Set-ModernButtonStyle -Button $btn -BaseColor $BgColor -TextColor $TextColor
    if ($Font) { $btn.Font = $Font } else { $btn.Font = New-Object System.Drawing.Font('Segoe UI', 9) }
    $btn.TextAlign = 'MiddleLeft'
    $btn.Padding = New-Object System.Windows.Forms.Padding(12, 0, 8, 0)
    $btn.Margin = New-Object System.Windows.Forms.Padding(6, 2, 6, 2)
    $btn.Add_Click($OnClick)
    return $btn
}

function New-GUILabel {
    param(
        [string]$Text,
        [int]$W = 238, [int]$H = 24,
        [System.Drawing.Color]$TextColor,
        [System.Drawing.Font]$Font,
        [string]$Align = 'MiddleLeft'
    )
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Size = New-Object System.Drawing.Size($W, $H)
    $lbl.MinimumSize = New-Object System.Drawing.Size($W, $H)
    $lbl.MaximumSize = New-Object System.Drawing.Size($W, $H)
    $lbl.ForeColor = $TextColor
    if ($Font) { $lbl.Font = $Font } else { $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9) }
    $lbl.TextAlign = $Align
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.Margin = New-Object System.Windows.Forms.Padding(4, 2, 4, 0)
    return $lbl
}

function New-GUISeccionLabel {
    param([string]$Text)
    $lbl = New-GUILabel -Text ("  " + $Text) -W 226 -H 30 -TextColor $Script:GUIColors.Accent -Font (New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold))
    $lbl.BackColor = $Script:GUIColors.Surface
    $lbl.Margin = New-Object System.Windows.Forms.Padding(6, 14, 6, 4)
    return $lbl
}

function Build-GUIForm {
    $form = New-Object System.Windows.Forms.Form
    Set-ModernFormStyle -Form $form
    $form.Text = "CONTPAQi TOOLBOX v$($Script:Version)"
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $initialWidth = [Math]::Min(1240, [Math]::Max(920, $workingArea.Width - 80))
    $initialHeight = [Math]::Min(820, [Math]::Max(650, $workingArea.Height - 80))
    $form.Size = New-Object System.Drawing.Size($initialWidth, $initialHeight)
    $form.MinimumSize = New-Object System.Drawing.Size(920, 650)
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = $Script:GUIColors.BG
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $form.ShowIcon = $true
    $form.Add_FormClosing({
        param($sender, $e)
        if ($Script:IsBusy) {
            $e.Cancel = $true
            [System.Windows.Forms.MessageBox]::Show(
                'Hay una operacion en curso. Espera a que termine antes de cerrar la herramienta.',
                'CONTPAQi Toolbox', 'OK', 'Warning'
            ) | Out-Null
        }
    })

    # --- HEADER PANEL ---
    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = 'Top'
    $headerPanel.Height = 78
    $headerPanel.BackColor = $Script:GUIColors.Header
    $form.Controls.Add($headerPanel)

    $Script:HeaderTitle = New-Object System.Windows.Forms.Label
    $Script:HeaderTitle.Text = 'CONTPAQi  //  TOOLBOX'
    $Script:HeaderTitle.Location = New-Object System.Drawing.Point(92, 12)
    $Script:HeaderTitle.Size = New-Object System.Drawing.Size(620, 32)
    $Script:HeaderTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 20, [System.Drawing.FontStyle]::Bold)
    $Script:HeaderTitle.ForeColor = $Script:GUIColors.Accent
    $Script:HeaderTitle.BackColor = [System.Drawing.Color]::Transparent
    $headerPanel.Controls.Add($Script:HeaderTitle)

    $Script:HeaderSub = New-Object System.Windows.Forms.Label
    $Script:HeaderSub.Text = 'Diagnostico y mantenimiento profesional CONTPAQi'
    $Script:HeaderSub.Location = New-Object System.Drawing.Point(94, 47)
    $Script:HeaderSub.Size = New-Object System.Drawing.Size(620, 20)
    $Script:HeaderSub.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $Script:HeaderSub.ForeColor = $Script:GUIColors.TextDim
    $Script:HeaderSub.BackColor = [System.Drawing.Color]::Transparent
    $headerPanel.Controls.Add($Script:HeaderSub)

    $mainLogo = New-ToolboxLogoPictureBox -Size 58
    $mainLogo.Location = New-Object System.Drawing.Point(20, 9)
    $headerPanel.Controls.Add($mainLogo)

    $verLabel = New-Object System.Windows.Forms.Label
    $verLabel.Text = "v$($Script:Version)"
    $verLabel.Location = New-Object System.Drawing.Point(1120, 22)
    $verLabel.Size = New-Object System.Drawing.Size(82, 32)
    $verLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $verLabel.ForeColor = $Script:GUIColors.Accent
    $verLabel.TextAlign = 'MiddleCenter'
    $verLabel.BackColor = $Script:GUIColors.Surface
    $verLabel.Anchor = 'Top, Right'
    $headerPanel.Controls.Add($verLabel)

    $headerAccent = New-Object System.Windows.Forms.Panel
    $headerAccent.Dock = 'Bottom'
    $headerAccent.Height = 2
    $headerAccent.BackColor = $Script:GUIColors.Accent
    $headerPanel.Controls.Add($headerAccent)

    # --- STATUS BAR ---
    $statusPanel = New-Object System.Windows.Forms.Panel
    $statusPanel.Dock = 'Bottom'
    $statusPanel.Height = 34
    $statusPanel.BackColor = $Script:GUIColors.Header
    $form.Controls.Add($statusPanel)

    $Script:StatusLabel = New-Object System.Windows.Forms.Label
    $Script:StatusLabel.Text = " $($Script:MarcaAgua)"
    $Script:StatusLabel.Location = New-Object System.Drawing.Point(14, 7)
    $Script:StatusLabel.Size = New-Object System.Drawing.Size(1180, 20)
    $Script:StatusLabel.ForeColor = $Script:GUIColors.TextDim
    $Script:StatusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $Script:StatusLabel.BackColor = [System.Drawing.Color]::Transparent
    $Script:StatusLabel.Anchor = 'Top, Left, Right'
    $statusPanel.Controls.Add($Script:StatusLabel)

    # --- MAIN SPLIT PANEL ---
    $mainSplit = New-Object System.Windows.Forms.SplitContainer
    $mainSplit.Dock = 'Fill'
    $mainSplit.SplitterDistance = 276
    $mainSplit.FixedPanel = 'Panel1'
    $mainSplit.Panel1MinSize = 250
    $mainSplit.BackColor = $Script:GUIColors.BG
    $mainSplit.SplitterWidth = 1
    $mainSplit.SplitterIncrement = 1
    $form.Controls.Add($mainSplit)

    # --- SIDEBAR ---
    $sidebarOuter = $mainSplit.Panel1
    $sidebarOuter.BackColor = $Script:GUIColors.Sidebar

$sidebar = New-Object System.Windows.Forms.FlowLayoutPanel
$sidebar.Dock = 'Fill'
$sidebar.FlowDirection = 'TopDown'
$sidebar.WrapContents = $false
$sidebar.AutoScroll = $true
$sidebar.BackColor = $Script:GUIColors.Sidebar
$sidebar.Padding = New-Object System.Windows.Forms.Padding(10, 8, 8, 12)
$sidebar.HorizontalScroll.Enabled = $false
$sidebar.HorizontalScroll.Visible = $false
$sidebarOuter.Controls.Add($sidebar)

    $sidebar.Add_Resize({
        param($sender, $eventArgs)
        $availableWidth = [Math]::Max(180, $sender.ClientSize.Width - $sender.Padding.Horizontal - 14)
        foreach ($control in $sender.Controls) {
            if ($control -is [System.Windows.Forms.Button] -or $control -is [System.Windows.Forms.Label]) {
                $height = $control.Height
                $control.MinimumSize = New-Object System.Drawing.Size($availableWidth, $height)
                $control.MaximumSize = New-Object System.Drawing.Size($availableWidth, $height)
                $control.Width = $availableWidth
            }
        }
        $sender.HorizontalScroll.Enabled = $false
        $sender.HorizontalScroll.Visible = $false
    })

    $btnFont = New-Object System.Drawing.Font('Segoe UI', 9.2)

    # --- ESCANEO PRIMERO: diagnosticar antes de modificar ---
    $sidebar.Controls.Add((New-GUISeccionLabel -Text 'ESCANEO Y BITACORAS'))

    $sidebar.Controls.Add((New-GUIButton -Text '[8] Escaneo y Reparacion' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Success -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Escaneo y Reparacion' -Subtitulo 'Solo este equipo: detectar, reparar y verificar' -Color 'Green' -Accion { Invoke-EscaneoInteligenteCONTPAQi }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[J] Diagnostico Inteligente + PDF' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Accent -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Diagnostico Inteligente' -Subtitulo 'Analisis priorizado y reporte PDF profesional' -Color 'Magenta' -Accion { Invoke-DiagnosticoInteligenteCONTPAQi }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[C] Diagnostico de Red' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Accent -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Diagnostico de Conectividad' -Subtitulo 'DNS + ruta + firewall + SQL + puertos CONTPAQi' -Color 'Cyan' -Accion { Show-DiagnosticoPuertosCONTPAQi }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[L] Abrir Reportes' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Text -Font $btnFont -OnClick {
        try {
            if (-not (Test-Path -LiteralPath $Script:ReportDirectory -PathType Container)) {
                New-Item -ItemType Directory -Path $Script:ReportDirectory -Force -ErrorAction Stop | Out-Null
            }
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$Script:ReportDirectory`"" -ErrorAction Stop | Out-Null
        } catch {
            Write-Log -Mensaje "No se pudo abrir la carpeta de reportes: $($_.Exception.Message)" -Nivel ERROR
        }
    }))

    # --- TERMINAL ---
    $sidebar.Controls.Add((New-GUISeccionLabel -Text 'TERMINAL - SOLUCIONES RAPIDAS'))

    $sidebar.Controls.Add((New-GUIButton -Text '[G] Revisar Terminal' -BgColor $Script:GUIColors.Button -TextColor $Script:GUIColors.Text -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Estado Terminal' -Subtitulo 'AuthServer' -Color 'DarkCyan' -Accion { Show-EstadoServiciosTerminal }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[B] Iniciar Servicios' -BgColor $Script:GUIColors.Button -TextColor $Script:GUIColors.Success -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Iniciar Detenidos' -Subtitulo 'Sin tocar activos' -Color 'Green' -Accion { Iniciar-ServiciosTerminalDetenidos }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[A] Reiniciar Licencias' -BgColor $Script:GUIColors.TerminalBtn -TextColor $Script:GUIColors.Accent -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Reiniciar AuthServer' -Subtitulo 'Licencias' -Color 'Cyan' -Accion { Reiniciar-TodosServiciosTerminal }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[H] Reparar Terminal' -BgColor $Script:GUIColors.TerminalBtn -TextColor $Script:GUIColors.Accent -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Reparacion de Terminal' -Subtitulo 'Servicios + temporales + red + validacion' -Color 'DarkCyan' -Accion { Reset-TerminalRapido }
    }))

    # --- SERVIDOR ---
    $sidebar.Controls.Add((New-GUISeccionLabel -Text 'SERVIDOR - ACCIONES AVANZADAS'))

    $sidebar.Controls.Add((New-GUIButton -Text '[I] Revisar Servidor' -BgColor $Script:GUIColors.Button -TextColor $Script:GUIColors.Text -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Estado PID' -Subtitulo 'Servidor' -Color 'Red' -Accion { Show-EstadoPIDServidor }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[D] Analisis del Servidor' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Accent -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Analisis del Servidor' -Subtitulo 'Autodeteccion e inventario remoto profundo' -Color 'Magenta' -Accion { Show-AnalisisProfundoServidorCONTPAQi }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[S] Salud de SQL' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Accent -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Salud de SQL Server' -Subtitulo 'Capacidad, respaldos, actividad y espacio por empresa' -Color 'Magenta' -Accion { Show-SaludSQLProfesional }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[M] Mantenimiento SQL' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Success -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Mantenimiento SQL' -Subtitulo 'Respaldo, integridad, indices y estadisticas' -Color 'Green' -Accion { Invoke-MantenimientoSQLProfesional }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[R] Reparacion Profunda' -BgColor $Script:GUIColors.ServerBtn -TextColor ([System.Drawing.Color]::White) -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Reparacion Profunda' -Subtitulo 'Reinicio controlado y validacion completa' -Color 'Red' -Accion { Invoke-ReparacionProfundaCONTPAQi }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[1] Reiniciar Servidor y SQL' -BgColor $Script:GUIColors.ServerBtn -TextColor $Script:GUIColors.Error -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Reiniciar Servicios y SQL' -Subtitulo 'CONTPAQi + Licencias + SQL Server' -Color 'Red' -Accion { Reiniciar-GrupoServicios -listaServicios ($ServiciosSACI + $ServiciosLicencias + (Get-ServiciosSQLRelacionados)) -nombreGrupo 'TODOS (CONTPAQi + SQL)' }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[5] Cerrar Sesiones CONTPAQi' -BgColor $Script:GUIColors.ServerBtn -TextColor $Script:GUIColors.Error -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Expulsar Usuarios' -Subtitulo 'Servidor RDS' -Color 'Red' -Accion { Expulsar-UsuariosSistemas }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[!] Reparacion Total Servidor' -BgColor $Script:GUIColors.ServerBtn -TextColor $Script:GUIColors.Error -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Reparacion Total del Servidor' -Subtitulo '14 etapas: DISM/SFC + Red + SQL + CONTPAQi' -Color 'Red' -Accion { Ejecutar-SuperReset }
    }))

    # --- MONITOREO AUTOMATICO ---
    $sidebar.Controls.Add((New-GUISeccionLabel -Text 'MONITOREO AUTOMATICO'))

    $sidebar.Controls.Add((New-GUIButton -Text '[W] ServicesDev' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Success -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-ServicesDevMonitor
    }))

    # --- ADMINISTRACION ---
    $sidebar.Controls.Add((New-GUISeccionLabel -Text 'ADMINISTRACION'))

    $sidebar.Controls.Add((New-GUIButton -Text '[7] Cambiar Contrasena SQL' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Warning -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Restablecer Contrasena SQL' -Subtitulo 'Login sa' -Color 'Green' -Accion { Restablecer-ContrasenaSQL }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text '[U] Desinstalar CONTPAQi' -BgColor $Script:GUIColors.ServerBtn -TextColor $Script:GUIColors.Error -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Desinstalar' -Subtitulo 'Cualquier version' -Color 'Red' -Accion { Show-MenuDesinstalar }
    }))

    # --- BOTON SALIR ---
    $sidebar.Controls.Add((New-GUIButton -Text '[SALIR]' -H 38 -BgColor $Script:GUIColors.Error -TextColor ([System.Drawing.Color]::White) -Font (New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Bold)) -OnClick {
        $form.Close()
    }))

    # --- LOG OUTPUT PANEL ---
    $Script:LogPanel = $mainSplit.Panel2
    $Script:LogPanel.BackColor = $Script:GUIColors.LogBG
    $Script:LogPanel.Padding = New-Object System.Windows.Forms.Padding(18, 14, 18, 16)

    $logHeader = New-Object System.Windows.Forms.Label
    $logHeader.Dock = 'Top'
    $logHeader.Height = 36
    $logHeader.Text = '  CENTRO DE DIAGNOSTICO  /  ACTIVIDAD EN VIVO'
    $logHeader.TextAlign = 'MiddleLeft'
    $logHeader.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $logHeader.ForeColor = $Script:GUIColors.Accent
    $logHeader.BackColor = $Script:GUIColors.Surface
    $Script:LogPanel.Controls.Add($logHeader)
    $Script:LogHeader = $logHeader

    $Script:LogBox = New-Object System.Windows.Forms.RichTextBox
    $Script:LogBox.Dock = 'Fill'
    $Script:LogBox.BackColor = $Script:GUIColors.LogBG
    $Script:LogBox.ForeColor = $Script:GUIColors.Text
    $Script:LogBox.Font = New-Object System.Drawing.Font('Cascadia Mono', 10)
    $Script:LogBox.ReadOnly = $true
    $Script:LogBox.BorderStyle = 'None'
    $Script:LogBox.ScrollBars = 'Vertical'
    $Script:LogBox.WordWrap = $true
    $Script:LogPanel.Controls.Add($Script:LogBox)
    $logHeader.BringToFront()

    $form.Controls.SetChildIndex($mainSplit, 0)
    $form.PerformLayout()
    $mainSplit.SplitterDistance = 276

    $Script:GUIForm = $form
    return $form
}

# --- INICIO ---

$Script:ConsoleMode = $false

# Verificar permisos de administrador y solicitar elevacion UAC.
if (-not (Test-Admin)) {
    if (-not (Request-Administrator)) { exit 0 }
}

Initialize-ToolboxLog

if (-not (Test-Admin)) {
    $msgForm = New-Object System.Windows.Forms.Form
    Set-ModernFormStyle -Form $msgForm
    $msgForm.Text = 'Toolbox - Error'
    $msgForm.Size = New-Object System.Drawing.Size(400, 180)
    $msgForm.StartPosition = 'CenterScreen'
    $msgForm.FormBorderStyle = 'FixedDialog'
    $msgForm.MaximizeBox = $false
    $msgForm.BackColor = $Script:GUIColors.BG
    $msgForm.TopMost = $true

    $errLbl = New-Object System.Windows.Forms.Label
    $errLbl.Text = 'Se requieren privilegios de Administrador para ejecutar este herramienta.'
    $errLbl.Location = New-Object System.Drawing.Point(20, 20)
    $errLbl.Size = New-Object System.Drawing.Size(350, 40)
    $errLbl.ForeColor = $Script:GUIColors.Error
    $errLbl.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $errLbl.BackColor = [System.Drawing.Color]::Transparent
    $msgForm.Controls.Add($errLbl)

    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = 'Aceptar'
    $okBtn.Location = New-Object System.Drawing.Point(140, 90)
    $okBtn.Size = New-Object System.Drawing.Size(100, 35)
    $okBtn.BackColor = $Script:GUIColors.Error
    $okBtn.ForeColor = [System.Drawing.Color]::White
    $okBtn.FlatStyle = 'Flat'
    $okBtn.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $okBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    Set-ModernButtonStyle -Button $okBtn -BaseColor $Script:GUIColors.Error -TextColor ([System.Drawing.Color]::White) -HoverColor ([System.Windows.Forms.ControlPaint]::Light($Script:GUIColors.Error, 0.10))
    $okBtn.Add_Click({ $msgForm.Close() })
    $msgForm.Controls.Add($okBtn)

    $msgForm.ShowDialog() | Out-Null
    exit 1
}

$form = Build-GUIForm

if (-not (Show-Login)) { exit 1 }

Write-BarraEstado
Show-Bienvenida
if ($Script:LogFile) {
    Write-Log -Mensaje "Bitacora de esta sesion: $Script:LogFile" -Nivel INFO
}
$form.ShowDialog() | Out-Null
exit 0
