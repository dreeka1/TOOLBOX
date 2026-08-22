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

$Script:Version          = '6.6.1'
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
$Script:Sidebar      = $null
$Script:ConsoleMode  = $false
$Script:CurrentPanel = $null
$Script:LogDirectory = Join-Path $env:ProgramData 'CONTPAQiToolbox\Logs'
$Script:ReportDirectory = Join-Path $env:ProgramData 'CONTPAQiToolbox\Reportes'
$Script:LogFile      = $null
$Script:IsBusy       = $false
$Script:LogMaxChars  = 300000
$Script:InstanceMutex = $null
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

function Enter-ToolboxSingleInstance {
    $creado = $false
    foreach ($nombre in @('Global\CONTPAQiToolbox.SingleInstance', 'Local\CONTPAQiToolbox.SingleInstance')) {
        try {
            $mutex = [System.Threading.Mutex]::new($true, $nombre, [ref]$creado)
            if ($creado) {
                $Script:InstanceMutex = $mutex
                return $true
            }
            $mutex.Dispose()
            return $false
        } catch [System.UnauthorizedAccessException] {
            # Algunos dominios restringen mutex globales; se intenta el ámbito de sesión.
            continue
        } catch {
            continue
        }
    }
    # No se impide trabajar si Windows no permite crear el mecanismo de exclusión.
    return $true
}

function Exit-ToolboxSingleInstance {
    if (-not $Script:InstanceMutex) { return }
    try { $Script:InstanceMutex.ReleaseMutex() } catch { }
    try { $Script:InstanceMutex.Dispose() } catch { }
    $Script:InstanceMutex = $null
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
    if ($Script:LogBox -and -not $Script:ConsoleMode -and -not $Script:LogBox.IsDisposed) {
        $text = if ($null -eq $Object) { '' } else { [string]$Object }
        if (-not $NoNewline) { $text += "`r`n" }
        $color = Convert-ConsoleColorToDrawing -Color $ForegroundColor
        # Evita que sesiones extensas degraden progresivamente la interfaz.
        # Se conserva aproximadamente el 80 % más reciente y se corta en una
        # línea completa para no dejar fragmentos difíciles de interpretar.
        if ($Script:LogMaxChars -gt 0 -and ($Script:LogBox.TextLength + $text.Length) -gt $Script:LogMaxChars) {
            $objetivoConservado = [Math]::Max(0, [int]($Script:LogMaxChars * 0.75))
            $minimoAEliminar = [Math]::Max(0, $Script:LogBox.TextLength + $text.Length - $objetivoConservado)
            $corte = $Script:LogBox.Text.IndexOf("`n", $minimoAEliminar)
            if ($corte -lt 0) { $corte = [Math]::Min($minimoAEliminar, $Script:LogBox.TextLength) }
            elseif ($corte -lt $Script:LogBox.TextLength) { $corte++ }
            if ($corte -gt 0) {
                $eraSoloLectura = $Script:LogBox.ReadOnly
                try {
                    if ($eraSoloLectura) { $Script:LogBox.ReadOnly = $false }
                    $Script:LogBox.Select(0, $corte)
                    $Script:LogBox.SelectedText = ''
                } finally {
                    if ($eraSoloLectura) { $Script:LogBox.ReadOnly = $true }
                }
            }
        }
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
    BG           = [System.Drawing.Color]::FromArgb(7, 8, 12)
    Sidebar      = [System.Drawing.Color]::FromArgb(10, 12, 17)
    Header       = [System.Drawing.Color]::FromArgb(7, 8, 12)
    Surface      = [System.Drawing.Color]::FromArgb(17, 19, 27)
    SurfaceAlt   = [System.Drawing.Color]::FromArgb(24, 27, 38)
    Button       = [System.Drawing.Color]::FromArgb(18, 21, 29)
    ButtonHover  = [System.Drawing.Color]::FromArgb(30, 33, 45)
    ButtonActive = [System.Drawing.Color]::FromArgb(40, 35, 60)
    Text         = [System.Drawing.Color]::FromArgb(241, 245, 249)
    TextDim      = [System.Drawing.Color]::FromArgb(139, 148, 165)
    Accent       = [System.Drawing.Color]::FromArgb(151, 112, 255)
    AccentDark   = [System.Drawing.Color]::FromArgb(64, 42, 112)
    Success      = [System.Drawing.Color]::FromArgb(60, 218, 151)
    Warning      = [System.Drawing.Color]::FromArgb(255, 190, 82)
    Error        = [System.Drawing.Color]::FromArgb(255, 96, 120)
    LogBG        = [System.Drawing.Color]::FromArgb(4, 5, 8)
    Separator    = [System.Drawing.Color]::FromArgb(31, 34, 44)
    ServerBtn    = [System.Drawing.Color]::FromArgb(34, 18, 24)
    TerminalBtn  = [System.Drawing.Color]::FromArgb(14, 27, 31)
    SupportBtn   = [System.Drawing.Color]::FromArgb(23, 20, 34)
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
    if ($BaseColor.IsEmpty) { $BaseColor = $Script:GUIColors.Button }
    if ($TextColor.IsEmpty) { $TextColor = $Script:GUIColors.Text }
    if ($HoverColor.IsEmpty) { $HoverColor = $Script:GUIColors.ButtonHover }
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

    try {
        $result = if ($Script:GUIForm -and -not $Script:GUIForm.IsDisposed) {
            $form.ShowDialog($Script:GUIForm)
        } else {
            $form.ShowDialog()
        }
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return [string]$txt.Text }
        return $null
    } finally {
        $form.Dispose()
    }
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
    param([switch]$Actualizar)
    if (-not $Actualizar -and $Script:PerfilEquipoCache -and $Script:PerfilEquipoCacheFecha -and
        ((Get-Date) - $Script:PerfilEquipoCacheFecha).TotalSeconds -lt 60) {
        return $Script:PerfilEquipoCache
    }
    $tieneSQL = (@(Get-ServiciosMotorSQL).Count -gt 0)
    $tieneAuth = (Get-ServiciosTerminal).Count -gt 0
    $perfil = if ($tieneSQL -and $tieneAuth) { 'Servidor+Terminal' }
        elseif ($tieneSQL) { 'Servidor RDS/SQL' }
        elseif ($tieneAuth) { 'Terminal/Estacion' }
        else { 'Equipo generico' }
    $Script:PerfilEquipoCache = $perfil
    $Script:PerfilEquipoCacheFecha = Get-Date
    return $perfil
}

# --- LOGIN GUI ---
function Show-Login {
    if (-not $Script:GUIForm) { return $false }

    $loginForm = New-Object System.Windows.Forms.Form
    Set-ModernFormStyle -Form $loginForm
    $loginForm.Text = 'CONTPAQi Toolbox - Acceso'
    $loginForm.ClientSize = New-Object System.Drawing.Size(820, 450)
    $loginForm.StartPosition = 'CenterScreen'
    $loginForm.FormBorderStyle = 'FixedDialog'
    $loginForm.MaximizeBox = $false
    $loginForm.MinimizeBox = $false
    $loginForm.BackColor = $Script:GUIColors.BG
    $loginForm.TopMost = $true
    $loginForm.KeyPreview = $true

    $bannerImage = $null
    $bannerPath = Get-ToolboxAssetPath -FileName 'DSBANER.png'
    $bannerPicture = New-Object System.Windows.Forms.PictureBox
    $bannerPicture.Dock = 'Fill'
    $bannerPicture.BackColor = $Script:GUIColors.BG
    $bannerPicture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    if ($bannerPath) {
        try {
            $sourceBanner = [System.Drawing.Image]::FromFile($bannerPath)
            try { $bannerImage = New-Object System.Drawing.Bitmap($sourceBanner) } finally { $sourceBanner.Dispose() }
            $bannerPicture.Image = $bannerImage
        } catch { $bannerImage = $null }
    }
    $loginForm.Controls.Add($bannerPicture)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = 'CONTPAQi TOOLBOX'
    $titleLabel.Location = New-Object System.Drawing.Point(25, 20)
    $titleLabel.Size = New-Object System.Drawing.Size(310, 34)
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $Script:GUIColors.Accent
    $titleLabel.TextAlign = 'MiddleLeft'

    $subLabel = New-Object System.Windows.Forms.Label
    $subLabel.Text = 'Acceso seguro para personal autorizado'
    $subLabel.Location = New-Object System.Drawing.Point(28, 58)
    $subLabel.Size = New-Object System.Drawing.Size(305, 20)
    $subLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $subLabel.ForeColor = $Script:GUIColors.TextDim
    $subLabel.TextAlign = 'MiddleLeft'

    $loginCard = New-Object System.Windows.Forms.Panel
    $loginCard.Location = New-Object System.Drawing.Point(30, 35)
    $loginCard.Size = New-Object System.Drawing.Size(360, 380)
    $loginCard.BackColor = $Script:GUIColors.Surface
    $loginCard.Add_Paint({
        param($sender, $eventArgs)
        $pen = New-Object System.Drawing.Pen($Script:GUIColors.AccentDark)
        try { $eventArgs.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1) } finally { $pen.Dispose() }
    })
    $loginForm.Controls.Add($loginCard)
    $bannerPicture.SendToBack()
    $loginCard.BringToFront()
    $loginForm.Add_Shown({ $loginCard.BringToFront() }.GetNewClosure())
    $loginCard.Controls.Add($titleLabel)
    $loginCard.Controls.Add($subLabel)

    $cardAccent = New-Object System.Windows.Forms.Panel
    $cardAccent.Dock = 'Left'
    $cardAccent.Width = 4
    $cardAccent.BackColor = $Script:GUIColors.Accent
    $loginCard.Controls.Add($cardAccent)

    $cardSeparator = New-Object System.Windows.Forms.Panel
    $cardSeparator.Location = New-Object System.Drawing.Point(28, 92)
    $cardSeparator.Size = New-Object System.Drawing.Size(304, 1)
    $cardSeparator.BackColor = $Script:GUIColors.Separator
    $loginCard.Controls.Add($cardSeparator)

    $userLabel = New-Object System.Windows.Forms.Label
    $userLabel.Text = 'Usuario:'
    $userLabel.Location = New-Object System.Drawing.Point(28, 110)
    $userLabel.Size = New-Object System.Drawing.Size(100, 22)
    $userLabel.ForeColor = $Script:GUIColors.Text
    $userLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $loginCard.Controls.Add($userLabel)

    $userBox = New-Object System.Windows.Forms.TextBox
    $userBox.Location = New-Object System.Drawing.Point(28, 136)
    $userBox.Size = New-Object System.Drawing.Size(304, 29)
    $userBox.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $userBox.BackColor = $Script:GUIColors.LogBG
    $userBox.ForeColor = $Script:GUIColors.Text
    Set-ModernTextBoxStyle -TextBox $userBox
    $loginCard.Controls.Add($userBox)

    $passLabel = New-Object System.Windows.Forms.Label
    $passLabel.Text = 'Contraseña:'
    $passLabel.Location = New-Object System.Drawing.Point(28, 184)
    $passLabel.Size = New-Object System.Drawing.Size(100, 22)
    $passLabel.ForeColor = $Script:GUIColors.Text
    $passLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $loginCard.Controls.Add($passLabel)

    $passBox = New-Object System.Windows.Forms.TextBox
    $passBox.Location = New-Object System.Drawing.Point(28, 210)
    $passBox.Size = New-Object System.Drawing.Size(304, 29)
    $passBox.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $passBox.BackColor = $Script:GUIColors.LogBG
    $passBox.ForeColor = $Script:GUIColors.Text
    Set-ModernTextBoxStyle -TextBox $passBox
    $passBox.UseSystemPasswordChar = $true
    $loginCard.Controls.Add($passBox)

    $loginBtn = New-Object System.Windows.Forms.Button
    $loginBtn.Text = 'Ingresar'
    $loginBtn.Location = New-Object System.Drawing.Point(28, 274)
    $loginBtn.Size = New-Object System.Drawing.Size(145, 42)
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
    $cancelBtn.Location = New-Object System.Drawing.Point(187, 274)
    $cancelBtn.Size = New-Object System.Drawing.Size(145, 42)
    $cancelBtn.BackColor = $Script:GUIColors.Button
    $cancelBtn.ForeColor = $Script:GUIColors.Text
    $cancelBtn.FlatStyle = 'Flat'
    $cancelBtn.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $cancelBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    Set-ModernButtonStyle -Button $cancelBtn
    $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $loginCard.Controls.Add($cancelBtn)

    $loginHint = New-Object System.Windows.Forms.Label
    $loginHint.Text = 'Tus credenciales se validan localmente.'
    $loginHint.Location = New-Object System.Drawing.Point(28, 337)
    $loginHint.Size = New-Object System.Drawing.Size(304, 20)
    $loginHint.TextAlign = 'MiddleCenter'
    $loginHint.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $loginHint.ForeColor = $Script:GUIColors.TextDim
    $loginCard.Controls.Add($loginHint)

    $loginForm.AcceptButton = $loginBtn
    $loginForm.CancelButton = $cancelBtn

    try {
        $intentosMaximos = 3
        for ($intento = 1; $intento -le $intentosMaximos; $intento++) {
            $titleLabel.Text = "CONTPAQi TOOLBOX  ($intento/$intentosMaximos)"
            $userBox.Clear()
            $passBox.Clear()
            # ShowDialog conserva DialogResult entre aperturas. Restablecerlo
            # evita consumir automáticamente los intentos tras un acceso fallido.
            $loginForm.DialogResult = [System.Windows.Forms.DialogResult]::None
            $loginForm.Text = "CONTPAQi Toolbox - Intento $intento de $intentosMaximos"

            $result = $loginForm.ShowDialog()
            if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $false }

            $usuarioInput = [string]$userBox.Text
            $contrasenaInput = [string]$passBox.Text

            $usuarioValido = $usuarioInput.Trim() -ceq $Script:LoginUser
            $hashValido = (Get-TextSha256 -Text $contrasenaInput) -ceq $Script:LoginPasswordHash
            $contrasenaInput = $null
            $passBox.Clear()

            if ($usuarioValido -and $hashValido) {
                Write-Log -Mensaje "Acceso autorizado para $usuarioInput." -Nivel INFO
                return $true
            }

            [System.Windows.Forms.MessageBox]::Show(
                "Usuario o contraseña incorrectos.`n`nIntento $intento de $intentosMaximos.",
                'Error de acceso', 'OK', 'Error'
            ) | Out-Null
        }
        return $false
    } finally {
        $passBox.Clear()
        $loginForm.Dispose()
        if ($bannerImage) { $bannerImage.Dispose() }
    }
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
    param(
        [ValidateRange(1, 3)][int]$Intentos = 2,
        [switch]$RecuperarDeshabilitados
    )

    $servicios = @(Get-ServiciosReparacionTerminal | Sort-Object `
        @{ Expression = { Get-OrdenInicioServicioCONTPAQi -Servicio $_ } }, Name)
    $correctos = 0
    $omitidos = 0
    $fallidos = New-Object System.Collections.Generic.List[string]
    foreach ($servicio in $servicios) {
        $nombre = $servicio.Name
        if (Test-ServicioDeshabilitado -Nombre $nombre) {
            if (-not $RecuperarDeshabilitados) {
                $omitidos++
                Write-Log -Mensaje "$nombre esta deshabilitado; se conserva su configuracion." -Nivel WARN
                continue
            }
            try {
                Set-Service -Name $nombre -StartupType Manual -ErrorAction Stop
                Write-Log -Mensaje "$nombre estaba deshabilitado; se restablecio a inicio Manual." -Nivel WARN
            } catch {
                $fallidos.Add($nombre)
                Write-Log -Mensaje "No se pudo recuperar $($nombre): $($_.Exception.Message)" -Nivel ERROR
                continue
            }
        }
        $actualDependencias = Get-Service -Name $nombre -ErrorAction SilentlyContinue
        foreach ($dependencia in @($actualDependencias.ServicesDependedOn)) {
            if ($dependencia.Status -eq 'Running' -or (Test-ServicioDeshabilitado -Nombre $dependencia.ServiceName)) { continue }
            $resultadoDep = Invoke-ServiceActionResponsive -Nombre $dependencia.ServiceName -Accion Start -TimeoutSegundos 60
            Write-Log -Mensaje $(if ($resultadoDep.Correcto) { "Dependencia $($dependencia.ServiceName) activa para $nombre." } else { "Dependencia $($dependencia.ServiceName) con incidencia: $($resultadoDep.Error)" }) -Nivel $(if ($resultadoDep.Correcto) { 'OK' } else { 'WARN' })
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
    Wait-Responsive -Seconds 2
    foreach ($servicioFinal in @(Get-ServiciosReparacionTerminal)) {
        if ((Test-ServicioDeshabilitado -Nombre $servicioFinal.Name) -or $servicioFinal.Status -eq 'Running') { continue }
        if (-not $fallidos.Contains($servicioFinal.Name)) { $fallidos.Add($servicioFinal.Name) }
        Write-Log -Mensaje "$($servicioFinal.Name) no permanecio activo despues de la reparacion." -Nivel ERROR
    }
    return [PSCustomObject]@{
        Total = $servicios.Count; Correctos = $correctos; Omitidos = $omitidos
        Fallidos = $fallidos.Count; FallidosNombres = @($fallidos)
    }
}

function Invoke-ReparacionComponentesWindowsTerminal {
    $codigo = @'
$resultadosSfc = @()
$dismCheck = & dism.exe /Online /Cleanup-Image /CheckHealth /English 2>&1
$dismCheckCode = $LASTEXITCODE
$dismCheckText = (($dismCheck -join ' ') -replace '\s+', ' ').Trim()
$dismRestoreCode = $null
$dismRestoreText = ''
$repairable = ($dismCheckText -match '(?i)component store is repairable|corruption detected')
if ($dismCheckCode -eq 0 -and $repairable) {
    $dismRestore = & dism.exe /Online /Cleanup-Image /RestoreHealth /English 2>&1
    $dismRestoreCode = $LASTEXITCODE
    $dismRestoreText = (($dismRestore -join ' ') -replace '\s+', ' ').Trim()
}
$archivos = @(
    (Join-Path $env:SystemRoot 'System32\msxml6.dll'),
    (Join-Path $env:SystemRoot 'System32\winhttp.dll'),
    (Join-Path $env:SystemRoot 'System32\crypt32.dll')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
foreach ($archivo in $archivos) {
    $salida = & sfc.exe "/scanfile=$archivo" 2>&1
    $resultadosSfc += [PSCustomObject]@{
        Archivo = $archivo; ExitCode = $LASTEXITCODE
        Salida = (($salida -join ' ') -replace '\s+', ' ').Trim()
    }
}
[PSCustomObject]@{
    DismCheckCode = $dismCheckCode; DismCheckText = $dismCheckText; ReparacionNecesaria = $repairable
    DismRestoreCode = $dismRestoreCode; DismRestoreText = $dismRestoreText; Sfc = $resultadosSfc
}
'@
    $worker = Invoke-ResponsiveWorker -ScriptText $codigo -TimeoutSeconds 2400 -Activity 'Validando componentes de Windows'
    if (-not $worker.Correcto -or $worker.Timeout -or -not $worker.Resultado) {
        return [PSCustomObject]@{ Correcto = $false; Error = $worker.Error; Resultado = $worker.Resultado }
    }
    $resultado = $worker.Resultado
    $dismCorrecto = ($resultado.DismCheckCode -eq 0 -and ($null -eq $resultado.DismRestoreCode -or $resultado.DismRestoreCode -eq 0))
    $sfcFallidos = @($resultado.Sfc | Where-Object { $_.ExitCode -ne 0 })
    return [PSCustomObject]@{
        Correcto = ($dismCorrecto -and $sfcFallidos.Count -eq 0); Error = $null; Resultado = $resultado
        DismCorrecto = $dismCorrecto; SfcFallidos = $sfcFallidos.Count
    }
}

function Reset-TerminalRapido {
    Write-Encabezado -Titulo 'REPARACION AVANZADA DE TERMINAL' -Subtitulo 'Procesos + servicios + ACL + Windows + red + verificacion real' -Color $Script:ColorTerminal
    Write-Log -Mensaje 'La reparacion trabaja solo sobre esta estacion: no detiene SQL ni servicios del servidor remoto.' -Nivel INFO
    if (-not (Confirmar-Movimiento -Frase 'REPARAR TERMINAL' `
        -Accion 'Reparar esta terminal CONTPAQi' `
        -Detalle 'Se cerraran aplicaciones locales, repararan permisos con respaldo, validaran componentes Windows y reiniciaran AuthServer/licencias. Puede tardar varios minutos.')) { return }

    $inicio = Get-Date
    $incidencias = 0
    $advertencias = 0
    $servidorValidado = $null
    $archivoAcl = $null
    $proteccionServicesDev = Suspend-ServicesDevForRepair
    if (-not $proteccionServicesDev.Correcto) { return }
    try {
        Write-Log -Mensaje '[1/13] Inventario, espacio y estado previo de la terminal...' -Nivel PROGRESS
        $serviciosTerminal = @(Get-ServiciosReparacionTerminal | Sort-Object `
            @{ Expression = { Get-OrdenInicioServicioCONTPAQi -Servicio $_ } }, Name)
        $procesosTerminal = @((Get-ProcesosCONTPAQi) + (Get-ProcesosPID)) |
            Where-Object { -not $_.EsToolbox } | Sort-Object PID -Unique
        $rutasTerminal = @(Get-RutasCONTPAQi)
        Write-Log -Mensaje "Detectados: $($serviciosTerminal.Count) servicios de terminal | $($procesosTerminal.Count) procesos | $($rutasTerminal.Count) rutas CONTPAQi." -Nivel INFO
        $unidadSistema = Get-PSDrive -Name ([IO.Path]::GetPathRoot($env:SystemRoot).TrimEnd(':\')) -PSProvider FileSystem -ErrorAction SilentlyContinue
        if ($unidadSistema) {
            $libresGB = [math]::Round($unidadSistema.Free / 1GB, 2)
            Write-Log -Mensaje "Espacio disponible en $($unidadSistema.Name): $libresGB GB." -Nivel $(if ($libresGB -ge 5) { 'OK' } else { 'WARN' })
            if ($libresGB -lt 5) { $advertencias++ }
        }
        if ($serviciosTerminal.Count -eq 0) {
            $advertencias++
            Write-Log -Mensaje 'No se detectaron AuthServer o servicios de licencia locales; se continuara con las demas validaciones.' -Nivel WARN
        }

        Write-Log -Mensaje '[2/13] Cerrando aplicaciones CONTPAQi/PID de esta estacion...' -Nivel PROGRESS
        foreach ($proceso in $procesosTerminal) {
            if (Stop-ProcesoForzado -ProcessId $proceso.PID -TimeoutSegundos 10) {
                Write-Log -Mensaje "PID $($proceso.PID) ($($proceso.Nombre)) cerrado." -Nivel OK
            } else {
                $incidencias++
                Write-Log -Mensaje "No fue posible cerrar PID $($proceso.PID) ($($proceso.Nombre))." -Nivel ERROR
            }
        }
        if ($procesosTerminal.Count -eq 0) { Write-Log -Mensaje 'No habia aplicaciones CONTPAQi abiertas.' -Nivel OK }

        Write-Log -Mensaje '[3/13] Deteniendo servicios locales de licencia y AuthServer...' -Nivel PROGRESS
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

        Write-Log -Mensaje '[4/13] Limpiando caches y temporales seguros de CONTPAQi...' -Nivel PROGRESS
        $temporalesTerminal = @(
            (Join-Path $env:TEMP 'Compac'),
            (Join-Path $env:TEMP 'CONTPAQi'),
            (Join-Path $env:LOCALAPPDATA 'Temp\Compac'),
            (Join-Path $env:LOCALAPPDATA 'Temp\CONTPAQi'),
            (Join-Path $env:ProgramData 'Compac\Temp'),
            (Join-Path $env:ProgramData 'CONTPAQi\Temp'),
            'C:\Windows\Temp\Compac',
            'C:\Windows\Temp\CONTPAQi'
        ) | Select-Object -Unique
        $eliminados = 0
        foreach ($ruta in $temporalesTerminal) { $eliminados += Clear-TemporalSeguro -Ruta $ruta }
        Write-Log -Mensaje "Limpieza terminada: $eliminados elemento(s) eliminados; los archivos en uso se conservaron." -Nivel OK

        Write-Log -Mensaje '[5/13] Renovando DNS y recuperando dependencias de Windows...' -Nivel PROGRESS
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
        $servicioHora = Get-Service -Name 'W32Time' -ErrorAction SilentlyContinue
        if ($servicioHora -and $servicioHora.Status -eq 'Running') {
            $sincronizacion = Invoke-ProcessResponsive -FilePath (Join-Path $env:SystemRoot 'System32\w32tm.exe') `
                -ArgumentList '/resync /nowait' -TimeoutSeconds 30 -Activity 'Sincronizando hora de Windows' -Hidden
            if ($sincronizacion.Correcto -and $sincronizacion.ExitCode -eq 0) {
                Write-Log -Mensaje 'Sincronizacion de hora solicitada correctamente.' -Nivel OK
            } else {
                $advertencias++
                Write-Log -Mensaje 'Windows no acepto la resincronizacion inmediata; se conserva el servicio activo.' -Nivel WARN
            }
        }

        Write-Log -Mensaje '[6/13] Auditando rutas, ejecutables y permisos locales...' -Nivel PROGRESS
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

        Write-Log -Mensaje '[7/13] Aplicando permisos oficiales y Centro de confianza de Excel con respaldo...' -Nivel PROGRESS
        $resultadoPermisos = Invoke-RepararPermisosTerminalCONTPAQi -ConfirmacionOmitida -ModoIntegrado
        if ($resultadoPermisos) {
            $archivoAcl = $resultadoPermisos.ArchivoRespaldo
            if ($resultadoPermisos.Correcto) {
                Write-Log -Mensaje "Permisos verificados: $($resultadoPermisos.Correctos) ruta(s) correcta(s)." -Nivel OK
            } else {
                $incidencias += [math]::Max(1, [int]$resultadoPermisos.Fallidos)
                Write-Log -Mensaje "La reparacion de permisos termino con $($resultadoPermisos.Fallidos) incidencia(s)." -Nivel ERROR
            }
        } else {
            $incidencias++
            Write-Log -Mensaje 'La reparacion de permisos no devolvio un resultado verificable.' -Nivel ERROR
        }
        $resultadoExcel = Invoke-ConfigurarCentroConfianzaExcelCONTPAQi -ConfirmacionOmitida -ModoIntegrado
        if (-not $resultadoExcel.Correcto) {
            $incidencias += [math]::Max(1, [int]$resultadoExcel.Fallidos)
            Write-Log -Mensaje 'El Centro de confianza de Excel no quedo completamente configurado.' -Nivel ERROR
        } elseif (-not $resultadoExcel.Omitido) {
            Write-Log -Mensaje "Centro de confianza de Excel verificado en $($resultadoExcel.Correctos) version(es)." -Nivel OK
        }

        Write-Log -Mensaje '[8/13] Validando y reparando componentes Windows usados por CONTPAQi...' -Nivel PROGRESS
        $resultadoWindows = Invoke-ReparacionComponentesWindowsTerminal
        if ($resultadoWindows.Correcto) {
            if ($resultadoWindows.Resultado.ReparacionNecesaria) {
                Write-Log -Mensaje 'DISM detecto corrupcion y RestoreHealth finalizo correctamente.' -Nivel OK
            } else {
                Write-Log -Mensaje 'DISM no detecto corrupcion pendiente en la imagen de Windows.' -Nivel OK
            }
            Write-Log -Mensaje 'SFC valido MSXML, WinHTTP y Crypt32 sin incidencias.' -Nivel OK
        } else {
            $advertencias++
            $detalleWindows = if ($resultadoWindows.Error) { $resultadoWindows.Error } else { "DISM correcto: $($resultadoWindows.DismCorrecto) | SFC con incidencia: $($resultadoWindows.SfcFallidos)" }
            Write-Log -Mensaje "Windows termino con observaciones: $detalleWindows" -Nivel WARN
        }

        Write-Log -Mensaje '[9/13] Iniciando y verificando AuthServer/licencias...' -Nivel PROGRESS
        $resultadoServicios = Start-ServiciosTerminalVerificado -Intentos 3 -RecuperarDeshabilitados
        $incidencias += $resultadoServicios.Fallidos
        Write-Log -Mensaje "Terminal: $($resultadoServicios.Correctos) activos, $($resultadoServicios.Fallidos) con incidencia, $($resultadoServicios.Omitidos) deshabilitados de $($resultadoServicios.Total)." -Nivel $(if ($resultadoServicios.Fallidos -eq 0) { 'OK' } else { 'WARN' })

        Write-Log -Mensaje '[10/13] Detectando y validando comunicacion con el servidor...' -Nivel PROGRESS
        $candidatosServidor = @(Find-ServidoresCONTPAQi)
        if ($candidatosServidor.Count -eq 0) {
            $advertencias++
            Write-Log -Mensaje 'No se encontro un servidor configurado. Revisa nombre del servidor, VPN o configuracion de la terminal.' -Nivel WARN
        } else {
            $servidor = $candidatosServidor[0]
            $servidorValidado = $servidor
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

        Write-Log -Mensaje '[11/13] Segunda auditoria de servicios y comunicacion...' -Nivel PROGRESS
        $detenidosFinales = @(Get-ServiciosReparacionTerminal | Where-Object {
            -not (Test-ServicioDeshabilitado -Nombre $_.Name) -and $_.Status -ne 'Running'
        })
        if ($detenidosFinales.Count -gt 0) {
            $incidencias += $detenidosFinales.Count
            Write-Log -Mensaje "Servicios que no quedaron activos: $($detenidosFinales.Name -join ', ')." -Nivel ERROR
        } else {
            Write-Log -Mensaje 'Todos los servicios de terminal habilitados quedaron activos.' -Nivel OK
        }

        Write-Log -Mensaje '[12/13] Revisando eventos generados durante la reparacion...' -Nivel PROGRESS
        $eventosNuevos = @(Get-EventosCONTPAQiRecientes | Where-Object { $_.TimeCreated -ge $inicio } | Select-Object -First 8)
        if ($eventosNuevos.Count -eq 0) {
            Write-Log -Mensaje 'No se generaron errores nuevos de CONTPAQi/SQL en el Visor de eventos durante el proceso.' -Nivel OK
        } else {
            $advertencias += $eventosNuevos.Count
            Write-Log -Mensaje "Windows registro $($eventosNuevos.Count) evento(s) relevante(s) durante la reparacion." -Nivel WARN
            foreach ($evento in $eventosNuevos) {
                $mensajeEvento = (($evento.Message -replace '[\r\n]+', ' ') -replace '\s+', ' ').Trim()
                if ($mensajeEvento.Length -gt 220) { $mensajeEvento = $mensajeEvento.Substring(0, 220) + '...' }
                Write-Log -Mensaje "$($evento.TimeCreated.ToString('HH:mm:ss')) | $($evento.ProviderName) | $mensajeEvento" -Nivel INFO
            }
        }
    } catch {
        $incidencias++
        Write-Log -Mensaje "Error inesperado durante la reparacion de terminal: $($_.Exception.Message)" -Nivel ERROR
    } finally {
        Write-Log -Mensaje '[13/13] Restaurando y verificando el monitor ServicesDev...' -Nivel PROGRESS
        if (-not (Restore-ServicesDevAfterRepair -Estados $proteccionServicesDev.Estados)) { $incidencias++ }
    }

    $duracion = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    Write-Host ''
    $colorFinal = if ($incidencias -eq 0 -and $advertencias -eq 0) { $Script:ColorExito } else { $Script:ColorAdvertencia }
    Write-Separador -Color $colorFinal
    if ($incidencias -eq 0 -and $advertencias -eq 0) {
        Write-Linea -Texto ' REPARACION DE TERMINAL COMPLETADA Y VERIFICADA' -Color $colorFinal -Centrado
        Write-Log -Mensaje "Terminal reparada y validada sin incidencias en $duracion segundos." -Nivel OK
    } elseif ($incidencias -eq 0) {
        Write-Linea -Texto " REPARACION COMPLETADA CON $advertencias ADVERTENCIA(S)" -Color $colorFinal -Centrado
        Write-Log -Mensaje "La reparacion termino en $duracion segundos; revisa las advertencias antes de validar CONTPAQi." -Nivel WARN
    } else {
        Write-Linea -Texto " REPARACION DE TERMINAL CON $incidencias INCIDENCIA(S)" -Color $colorFinal -Centrado
        Write-Log -Mensaje "Proceso terminado en $duracion segundos. Revisa las incidencias antes de abrir CONTPAQi." -Nivel WARN
    }
    try {
        $directorioEvidencia = Join-Path $env:ProgramData 'CONTPAQiToolbox\TerminalRepair'
        if (-not (Test-Path -LiteralPath $directorioEvidencia -PathType Container)) {
            New-Item -ItemType Directory -Path $directorioEvidencia -Force -ErrorAction Stop | Out-Null
        }
        $archivoEvidencia = Join-Path $directorioEvidencia ("Terminal_{0}_{1}.json" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $serviciosEvidencia = @(Get-ServiciosReparacionTerminal | ForEach-Object {
            [PSCustomObject]@{ Nombre = $_.Name; Visible = $_.DisplayName; Estado = $_.Status.ToString(); Inicio = $_.StartType.ToString() }
        })
        [PSCustomObject]@{
            Equipo = $env:COMPUTERNAME; Inicio = $inicio; Fin = Get-Date; DuracionSegundos = $duracion
            Incidencias = $incidencias; Advertencias = $advertencias; RespaldoACL = $archivoAcl
            Servidor = if ($servidorValidado) { $servidorValidado.Host } else { $null }
            Servicios = $serviciosEvidencia
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $archivoEvidencia -Encoding UTF8 -ErrorAction Stop
        Write-Log -Mensaje "Evidencia tecnica guardada: $archivoEvidencia" -Nivel OK
    } catch {
        Write-Log -Mensaje "No se pudo guardar la evidencia tecnica: $($_.Exception.Message)" -Nivel WARN
    }
    $estadoReinicioTerminal = Write-EstadoReinicioPendiente
    if (-not $estadoReinicioTerminal.Pendiente) { Write-Log -Mensaje 'Abre CONTPAQi y valida acceso a empresas, licencias, ADD y timbrado desde esta terminal.' -Nivel INFO }
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

function Invoke-SetContrasenaSQLSaResponsive {
    param(
        [Parameter(Mandatory)][string]$Instancia,
        [Parameter(Mandatory)][string]$NuevaContrasena
    )
    $codigo = @'
param([string]$SqlInstance, [string]$NewPassword)
$connection = New-Object System.Data.SqlClient.SqlConnection
$command = $null
try {
    $connection.ConnectionString = "Server=$SqlInstance;Integrated Security=True;TrustServerCertificate=True;Connect Timeout=8;Application Name=CONTPAQi Toolbox"
    $connection.Open()

    function Get-SaStateInternal {
        param([System.Data.SqlClient.SqlConnection]$SqlConnection)
        $stateCommand = $SqlConnection.CreateCommand()
        try {
            $stateCommand.CommandTimeout = 10
            $stateCommand.CommandText = @"
SELECT CAST(is_disabled AS int),
       CONVERT(datetime2, LOGINPROPERTY(N'sa', 'PasswordLastSetTime')),
       CAST(SERVERPROPERTY('IsIntegratedSecurityOnly') AS int)
FROM sys.sql_logins WHERE name = N'sa';
"@
            $reader = $stateCommand.ExecuteReader()
            try {
                if (-not $reader.Read()) { throw "El login sa no existe en $SqlInstance." }
                [PSCustomObject]@{
                    Deshabilitado = ([int]$reader.GetValue(0) -eq 1)
                    FechaPassword = if ($reader.IsDBNull(1)) { $null } else { [datetime]$reader.GetValue(1) }
                    SoloWindows = ([int]$reader.GetValue(2) -eq 1)
                }
            } finally { $reader.Dispose() }
        } finally { $stateCommand.Dispose() }
    }

    $before = Get-SaStateInternal -SqlConnection $connection
    $command = $connection.CreateCommand()
    $command.CommandTimeout = 15
    $escapedPassword = $NewPassword.Replace("'", "''")
    $command.CommandText = "ALTER LOGIN [sa] WITH PASSWORD = N'$escapedPassword'; ALTER LOGIN [sa] ENABLE;"
    $null = $command.ExecuteNonQuery()
    $after = Get-SaStateInternal -SqlConnection $connection
    $fechaActualizada = ($null -ne $after.FechaPassword -and ($null -eq $before.FechaPassword -or $after.FechaPassword -gt $before.FechaPassword))
    $loginHabilitado = -not $after.Deshabilitado

    $autenticacionVerificada = $false
    $detalleAutenticacion = ''
    if ($after.SoloWindows) {
        $detalleAutenticacion = 'La contraseña cambió, pero SQL Server está configurado únicamente para autenticación de Windows.'
    } else {
        $authConnection = New-Object System.Data.SqlClient.SqlConnection
        try {
            $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
            $builder.DataSource = $SqlInstance
            $builder.InitialCatalog = 'master'
            $builder.UserID = 'sa'
            $builder.Password = $NewPassword
            $builder.IntegratedSecurity = $false
            $builder.TrustServerCertificate = $true
            $builder.ConnectTimeout = 8
            $builder.ApplicationName = 'CONTPAQi Toolbox Password Verification'
            $authConnection.ConnectionString = $builder.ConnectionString
            $authConnection.Open()
            $verifyCommand = $authConnection.CreateCommand()
            try {
                $verifyCommand.CommandText = 'SELECT 1;'
                $verifyCommand.CommandTimeout = 8
                $autenticacionVerificada = ([int]$verifyCommand.ExecuteScalar() -eq 1)
            } finally { $verifyCommand.Dispose() }
        } catch {
            $detalleAutenticacion = $_.Exception.Message
        } finally { $authConnection.Dispose() }
    }

    $cambioVerificado = ($fechaActualizada -and $loginHabilitado)
    $correcto = ($cambioVerificado -and ($after.SoloWindows -or $autenticacionVerificada))
    $errorFinal = if (-not $fechaActualizada) {
        'SQL ejecutó la instrucción, pero no confirmó una nueva fecha de contraseña.'
    } elseif (-not $loginHabilitado) {
        'La contraseña cambió, pero el login sa permanece deshabilitado.'
    } elseif (-not $after.SoloWindows -and -not $autenticacionVerificada) {
        "La contraseña cambió, pero la conexión de comprobación con sa falló: $detalleAutenticacion"
    } else { $null }
    [PSCustomObject]@{
        Correcto = $correcto; CambioVerificado = $cambioVerificado
        AutenticacionVerificada = $autenticacionVerificada; SoloWindows = $after.SoloWindows
        FechaPassword = $after.FechaPassword; Detalle = $detalleAutenticacion; Error = $errorFinal
    }
} catch {
    [PSCustomObject]@{
        Correcto = $false; CambioVerificado = $false; AutenticacionVerificada = $false
        SoloWindows = $false; FechaPassword = $null; Detalle = ''; Error = $_.Exception.Message
    }
} finally {
    if ($command) { $command.Dispose() }
    $connection.Dispose()
}
'@
    $worker = Invoke-ResponsiveWorker -ScriptText $codigo -Arguments @($Instancia, $NuevaContrasena) `
        -TimeoutSeconds 35 -Activity "Restableciendo login sa en $Instancia"
    if (-not $worker.Correcto -or $worker.Timeout -or -not $worker.Resultado) {
        return [PSCustomObject]@{ Correcto = $false; Error = $(if ($worker.Error) { $worker.Error } else { 'SQL no devolvio un resultado valido.' }) }
    }
    return $worker.Resultado
}

function Write-SqlPasswordActivity {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.RichTextBox]$ActivityBox,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','PROGRESS','OK','WARN','ERROR')][string]$Level = 'INFO'
    )
    if ($ActivityBox.IsDisposed) { return }
    $prefix = @{ INFO = '[INFO]'; PROGRESS = '[....]'; OK = '[ OK ]'; WARN = '[WARN]'; ERROR = '[FAIL]' }[$Level]
    $color = switch ($Level) {
        'OK'       { [Drawing.Color]::FromArgb(56, 224, 143) }
        'WARN'     { [Drawing.Color]::FromArgb(255, 191, 71) }
        'ERROR'    { [Drawing.Color]::FromArgb(255, 93, 115) }
        'PROGRESS' { [Drawing.Color]::FromArgb(167, 139, 250) }
        default    { [Drawing.Color]::FromArgb(148, 163, 184) }
    }
    $ActivityBox.SelectionStart = $ActivityBox.TextLength
    $ActivityBox.SelectionLength = 0
    $ActivityBox.SelectionColor = $color
    $ActivityBox.AppendText("$(Get-Date -Format 'HH:mm:ss') $prefix $Message`r`n")
    $ActivityBox.SelectionColor = $ActivityBox.ForeColor
    $ActivityBox.SelectionStart = $ActivityBox.TextLength
    $ActivityBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Restablecer-ContrasenaSQL {
    Write-Encabezado -Titulo 'CAMBIAR CONTRASENA SQL' -Subtitulo 'Login sa en instancias locales' -Color 'Green'

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
        $okBtn.Text = 'Aplicar cambio'
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

        $activityGroup = New-Object System.Windows.Forms.GroupBox
        $activityGroup.Text = ' ACTIVIDAD SQL EN VIVO'
        $activityGroup.Dock = 'Fill'
        $activityGroup.MinimumSize = New-Object System.Drawing.Size(0, 150)
        $activityGroup.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 10)
        $activityGroup.ForeColor = $Script:GUIColors.Accent
        $activityGroup.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
        $activityGroup.BackColor = [System.Drawing.Color]::Transparent
        $sqlPanel.Controls.Add($activityGroup)
        # En el orden de acoplamiento de WinForms, Fill debe quedar al frente en
        # el Z-order para respetar el espacio consumido por los controles Top.
        $activityGroup.BringToFront()

        $activityBox = New-Object System.Windows.Forms.RichTextBox
        $activityBox.Dock = 'Fill'
        $activityBox.ReadOnly = $true
        $activityBox.BackColor = [System.Drawing.Color]::FromArgb(2, 3, 4)
        $activityBox.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
        $activityBox.BorderStyle = 'FixedSingle'
        $activityBox.Font = New-Object System.Drawing.Font('Consolas', 9)
        $activityBox.WordWrap = $true
        $activityBox.ScrollBars = 'Vertical'
        $activityBox.DetectUrls = $false
        $activityGroup.Controls.Add($activityBox)
        Write-SqlPasswordActivity -ActivityBox $activityBox -Message 'Consola preparada. La contraseña nunca se mostrará en esta actividad.' -Level INFO
        Write-SqlPasswordActivity -ActivityBox $activityBox -Message "Instancias disponibles: $($nombresInstancias -join ', ')" -Level INFO

        # El cierre de vistas se centraliza para no intentar ejecutar una
        # variable local que ya dejo de existir cuando ocurre el clic.
        $cancelBtn.Add_Click({
            Close-CurrentPanel
            Write-Log -Mensaje 'Operacion cancelada.' -Nivel WARN
        })

        # Guardar el estado en el propio boton evita depender del alcance tardio
        # de variables locales en los eventos de Windows Forms.
        $formState = [PSCustomObject]@{
            PasswordBox = $passBox
            ConfirmBox = $passConfirmBox
            Instances = @($chkInstances)
            ActivityBox = $activityBox
            CancelButton = $cancelBtn
        }
        # Set-ModernButtonStyle utiliza Tag para Base/Hover/Active. Agregar el
        # estado como una propiedad conserva esos colores y evita valores NULL.
        $okBtn.Tag | Add-Member -NotePropertyName FormState -NotePropertyValue $formState -Force
        $okBtn.Add_Click({
            param($sender, $eventArgs)
            $formState = $sender.Tag.FormState
            $activityBox = $formState.ActivityBox
            $passInput = [string]$formState.PasswordBox.Text
            if ($formState.PasswordBox.TextLength -lt 8) {
                Write-SqlPasswordActivity -ActivityBox $activityBox -Message 'Validación detenida: la contraseña contiene menos de 8 caracteres.' -Level WARN
                [System.Windows.Forms.MessageBox]::Show('La contraseña debe tener al menos 8 caracteres.', 'Contraseña no válida', 'OK', 'Warning') | Out-Null
                return
            }
            if ($passInput -cne [string]$formState.ConfirmBox.Text) {
                Write-SqlPasswordActivity -ActivityBox $activityBox -Message 'Validación detenida: las contraseñas no coinciden.' -Level WARN
                [System.Windows.Forms.MessageBox]::Show('Las contraseñas no coinciden.', 'Confirmación no válida', 'OK', 'Warning') | Out-Null
                return
            }

            $seleccionadas = @()
            foreach ($item in @($formState.Instances)) {
                if ($item.CheckBox.Checked) { $seleccionadas += $item.Nombre }
            }
            if ($seleccionadas.Count -eq 0) {
                Write-SqlPasswordActivity -ActivityBox $activityBox -Message 'Validación detenida: no hay instancias seleccionadas.' -Level WARN
                [System.Windows.Forms.MessageBox]::Show('Selecciona al menos una instancia.', 'Sin instancias', 'OK', 'Warning') | Out-Null
                return
            }
            if (-not (Confirmar-Movimiento -Frase 'CAMBIAR' `
                -Accion "Cambiar la contrasena sa en $($seleccionadas.Count) instancia(s)" `
                -Detalle 'Las aplicaciones que utilicen la contrasena anterior deberan actualizar su configuracion.')) {
                Write-SqlPasswordActivity -ActivityBox $activityBox -Message 'Operación cancelada en la confirmación de seguridad.' -Level WARN
                return
            }

            $sender.Enabled = $false
            $formState.CancelButton.Enabled = $false
            $formState.PasswordBox.Enabled = $false
            $formState.ConfirmBox.Enabled = $false
            $correctas = 0
            $fallidas = 0
            try {
                Write-SqlPasswordActivity -ActivityBox $activityBox -Message "Iniciando cambio y verificación en $($seleccionadas.Count) instancia(s)." -Level PROGRESS
                foreach ($inst in $seleccionadas) {
                    $serverName = if ($inst -eq 'MSSQLSERVER') { '.' } else { ".\$inst" }
                    Write-SqlPasswordActivity -ActivityBox $activityBox -Message "Conectando con $serverName mediante autenticación integrada..." -Level PROGRESS
                    $resultadoCambio = Invoke-SetContrasenaSQLSaResponsive -Instancia $serverName -NuevaContrasena $passInput
                    if ($resultadoCambio.Correcto) {
                        $correctas++
                        if ($resultadoCambio.AutenticacionVerificada) {
                            Write-SqlPasswordActivity -ActivityBox $activityBox -Message "Cambio validado: conexión real con 'sa' y la nueva contraseña correcta en $serverName." -Level OK
                        } else {
                            Write-SqlPasswordActivity -ActivityBox $activityBox -Message "Cambio confirmado por SQL y login 'sa' habilitado. La instancia usa solo autenticación de Windows, por lo que no admite probar el acceso SQL." -Level WARN
                        }
                        Write-Log -Mensaje "Contrasena 'sa' cambiada y verificada en $serverName" -Nivel OK
                    } else {
                        $fallidas++
                        $detalleError = if ($resultadoCambio.Error) { [string]$resultadoCambio.Error } else { 'SQL no devolvió detalles.' }
                        $nivelFallo = if ($resultadoCambio.CambioVerificado) { 'WARN' } else { 'ERROR' }
                        Write-SqlPasswordActivity -ActivityBox $activityBox -Message "$serverName no superó toda la validación: $detalleError" -Level $nivelFallo
                        Write-Log -Mensaje "Error en $($serverName): $detalleError" -Nivel ERROR
                    }
                }
                $nivelResumen = if ($fallidas -eq 0) { 'OK' } elseif ($correctas -gt 0) { 'WARN' } else { 'ERROR' }
                Write-SqlPasswordActivity -ActivityBox $activityBox -Message "Proceso finalizado: $correctas correcta(s), $fallidas fallida(s)." -Level $nivelResumen
            } finally {
                $passInput = $null
                $formState.PasswordBox.Clear()
                $formState.ConfirmBox.Clear()
                $formState.PasswordBox.Enabled = $true
                $formState.ConfirmBox.Enabled = $true
                $formState.CancelButton.Enabled = $true
                $sender.Enabled = $true
                $formState.PasswordBox.Focus()
            }
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
        if (-not (Confirmar-Movimiento -Frase 'CAMBIAR' `
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
        $null = Write-EstadoReinicioPendiente -SoloSiExiste

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

        Write-Log -Mensaje '[7/14] Recuperando dependencias y aplicando permisos/Excel oficiales...' -Nivel PROGRESS
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
        $permisosServidor = Invoke-RepararPermisosTerminalCONTPAQi -ConfirmacionOmitida -ModoIntegrado
        if (-not $permisosServidor.Correcto) { $incidencias += [math]::Max(1, [int]$permisosServidor.Fallidos) }
        $excelServidor = Invoke-ConfigurarCentroConfianzaExcelCONTPAQi -ConfirmacionOmitida -ModoIntegrado
        if (-not $excelServidor.Correcto) { $incidencias += [math]::Max(1, [int]$excelServidor.Fallidos) }

        Write-Log -Mensaje '[8/14] Iniciando SQL con reintentos y orden de dependencias...' -Nivel PROGRESS
        $sqlStartOrder = @($serviciosSql | Sort-Object { if ($_ -like 'MSSQL*') { 0 } elseif ($_ -eq 'SQLBrowser') { 1 } else { 2 } })
        foreach ($nombre in $sqlStartOrder) {
            if (Test-ServicioDeshabilitado -Nombre $nombre) {
                try {
                    Set-Service -Name $nombre -StartupType Manual -ErrorAction Stop
                    Write-Log -Mensaje "SQL $nombre estaba deshabilitado; se restablecio a inicio Manual para repararlo." -Nivel WARN
                } catch {
                    $incidencias++
                    Write-Log -Mensaje "SQL $nombre sigue deshabilitado y no pudo recuperarse: $($_.Exception.Message)" -Nivel ERROR
                    continue
                }
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
        $resultadoApp = Start-TodosServiciosCONTPAQiVerificado -Intentos 3 -RecuperarDeshabilitados
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

function ConvertTo-RutaReinicioLegible {
    param([AllowEmptyString()][string]$Ruta)
    if ([string]::IsNullOrWhiteSpace($Ruta)) { return '' }
    $valor = $Ruta.Trim()
    if ($valor -match '(?i)([A-Z]:\\.*)$') { return $matches[1] }
    return ($valor -replace '^[*!0-9]*\\\?\?\\', '')
}

function Get-EstadoReinicioPendiente {
    $razonesConfirmadas = New-Object System.Collections.ArrayList
    $operacionesResiduales = New-Object System.Collections.ArrayList

    function Add-RazonReinicio {
        param([string]$Fuente, [string]$Detalle, [string]$Accion)
        [void]$razonesConfirmadas.Add([PSCustomObject]@{
            Fuente = $Fuente; Detalle = $Detalle; Accion = $Accion
        })
    }

    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        Add-RazonReinicio -Fuente 'Mantenimiento de componentes (CBS)' `
            -Detalle 'Windows termino de instalar o reparar componentes y dejo la marca RebootPending.' `
            -Accion 'Reinicia Windows. Si la marca continua, ejecuta DISM RestoreHealth y revisa CBS.log.'
    }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        Add-RazonReinicio -Fuente 'Windows Update' `
            -Detalle 'Windows Update registra RebootRequired, aunque la pantalla de actualizaciones no muestre descargas pendientes.' `
            -Accion 'Reinicia y abre Windows Update para buscar nuevamente. Si persiste, revisa el historial y los servicios de actualizacion.'
    }
    try {
        $updateExe = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Updates' -Name UpdateExeVolatile -ErrorAction SilentlyContinue).UpdateExeVolatile
        if ($null -ne $updateExe -and [int]$updateExe -ne 0) {
            Add-RazonReinicio -Fuente 'Instalador de Windows' `
                -Detalle "UpdateExeVolatile conserva el valor $updateExe despues de una instalacion." `
                -Accion 'Termina o repara el instalador que genero la marca y reinicia una vez.'
        }
    } catch { }
    try {
        $nombreActivo = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
        $nombreConfigurado = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
        if ($nombreActivo -and $nombreConfigurado -and $nombreActivo -ne $nombreConfigurado) {
            Add-RazonReinicio -Fuente 'Cambio de nombre del equipo' `
                -Detalle "Nombre activo: $nombreActivo | Nombre configurado: $nombreConfigurado." `
                -Accion 'Reinicia para aplicar el nuevo nombre del equipo y valida dominio, recursos compartidos y SQL.'
        }
    } catch { }

    # PendingFileRenameOperations es una pista debil: navegadores, antivirus y
    # Gaming Services pueden recrearla o dejar residuos despues de reiniciar.
    # Por si sola no debe afirmar que Windows necesita otro reinicio.
    foreach ($nombreValor in @('PendingFileRenameOperations', 'PendingFileRenameOperations2')) {
        try {
            $entradas = @((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name $nombreValor -ErrorAction SilentlyContinue).$nombreValor)
            for ($indice = 0; $indice -lt $entradas.Count; $indice += 2) {
                $origen = ConvertTo-RutaReinicioLegible -Ruta ([string]$entradas[$indice])
                $destino = if (($indice + 1) -lt $entradas.Count) { ConvertTo-RutaReinicioLegible -Ruta ([string]$entradas[$indice + 1]) } else { '' }
                if (-not $origen -and -not $destino) { continue }
                $texto = if ($destino) { "$origen -> $destino" } else { "$origen (eliminacion pendiente)" }
                $responsable = if ($texto -match '(?i)Google\\Chrome|Chrome\\Temp') { 'Google Chrome' }
                    elseif ($texto -match '(?i)Microsoft\\Edge|EdgeUpdate') { 'Microsoft Edge' }
                    elseif ($texto -match '(?i)gamingservices|Xbox') { 'Gaming Services / Xbox' }
                    elseif ($texto -match '(?i)\\Temp\\') { 'Instalador o carpeta temporal' }
                    elseif ($texto -match '(?i)CONTPAQ|COMPAC') { 'CONTPAQi / Compac' }
                    else { 'Aplicacion no identificada' }
                [void]$operacionesResiduales.Add([PSCustomObject]@{
                    Fuente = $nombreValor; Responsable = $responsable; Detalle = $texto
                })
            }
        } catch { }
    }

    $confirmado = ($razonesConfirmadas.Count -gt 0)
    $residual = ($operacionesResiduales.Count -gt 0)
    $estado = if ($confirmado) { 'CONFIRMADO' } elseif ($residual) { 'NO CONFIRMADO - SENAL RESIDUAL' } else { 'NO' }
    $accionResidual = if ($residual) {
        'No reinicies repetidamente solo por esta señal. Actualiza o repara la aplicacion responsable. Si las rutas ya no existen y la marca persiste, un tecnico puede exportar la clave Session Manager y retirar unicamente los pares obsoletos.'
    } else { '' }
    return [PSCustomObject]@{
        Pendiente = $confirmado
        Estado = $estado
        Razones = @($razonesConfirmadas)
        OperacionesResiduales = @($operacionesResiduales)
        AccionResidual = $accionResidual
    }
}


function Write-EstadoReinicioPendiente {
    param([switch]$SoloSiExiste)
    $estado = Get-EstadoReinicioPendiente
    if ($estado.Pendiente) {
        Write-Log -Mensaje "Reinicio pendiente CONFIRMADO por $($estado.Razones.Count) fuente(s)." -Nivel WARN
        foreach ($razon in $estado.Razones) {
            Write-Log -Mensaje "$($razon.Fuente): $($razon.Detalle)" -Nivel WARN
            Write-Log -Mensaje "Accion: $($razon.Accion)" -Nivel INFO
        }
    } elseif ($estado.OperacionesResiduales.Count -gt 0) {
        Write-Log -Mensaje 'No existe un reinicio confirmado. Windows conserva operaciones de archivo residuales que no justifican reiniciar por si solas.' -Nivel INFO
        foreach ($operacion in @($estado.OperacionesResiduales | Select-Object -First 6)) {
            Write-Log -Mensaje "$($operacion.Responsable): $($operacion.Detalle)" -Nivel INFO
        }
        Write-Log -Mensaje "Accion: $($estado.AccionResidual)" -Nivel INFO
    } elseif (-not $SoloSiExiste) {
        Write-Log -Mensaje 'Windows no reporta un reinicio pendiente.' -Nivel OK
    }
    return $estado
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

    Write-Log -Mensaje '[5/8] Limpiando temporales, DNS y reparando permisos/Excel...' -Nivel PROGRESS
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
    $permisosProfundos = Invoke-RepararPermisosTerminalCONTPAQi -ConfirmacionOmitida -ModoIntegrado
    if (-not $permisosProfundos.Correcto) { $errores += [math]::Max(1, [int]$permisosProfundos.Fallidos) }
    $excelProfundo = Invoke-ConfigurarCentroConfianzaExcelCONTPAQi -ConfirmacionOmitida -ModoIntegrado
    if (-not $excelProfundo.Correcto) { $errores += [math]::Max(1, [int]$excelProfundo.Fallidos) }

    Write-Log -Mensaje '[6/8] Iniciando SQL en orden...' -Nivel PROGRESS
    $sqlStartOrder = @($serviciosSqlDetectados | Sort-Object { if ($_ -like 'MSSQL*') { 0 } elseif ($_ -eq 'SQLBrowser') { 1 } else { 2 } })
    foreach ($nombre in $sqlStartOrder) {
        if (Test-ServicioDeshabilitado -Nombre $nombre) {
            try {
                Set-Service -Name $nombre -StartupType Manual -ErrorAction Stop
                Write-Log -Mensaje "SQL $nombre estaba deshabilitado; se restablecio a inicio Manual para repararlo." -Nivel WARN
            } catch {
                $errores++
                Write-Log -Mensaje "SQL $nombre sigue deshabilitado y no pudo recuperarse: $($_.Exception.Message)" -Nivel ERROR
                continue
            }
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
    $resultadoServicios = Start-TodosServiciosCONTPAQiVerificado -Intentos 3 -RecuperarDeshabilitados
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
    $estadoReinicioFinal = Write-EstadoReinicioPendiente
    if (-not $estadoReinicioFinal.Pendiente) {
        Write-Log -Mensaje 'Abre CONTPAQi y valida acceso a empresa, ADD, timbrado y terminales.' -Nivel INFO
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
        [PSCustomObject]@{ Ruta = 'C:\Compac'; Tipo = 'Carpeta oficial de datos' },
        [PSCustomObject]@{ Ruta = 'C:\Compacw'; Tipo = 'Carpeta oficial heredada' },
        [PSCustomObject]@{ Ruta = 'C:\CONTPAQi'; Tipo = 'Carpeta de datos' },
        [PSCustomObject]@{ Ruta = (Join-Path ${env:ProgramFiles(x86)} 'Compac'); Tipo = 'Archivos de programa oficiales' },
        [PSCustomObject]@{ Ruta = (Join-Path ${env:ProgramFiles(x86)} 'Compacw'); Tipo = 'Archivos de programa heredados' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:ProgramFiles 'Compac'); Tipo = 'Archivos de programa' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:ProgramFiles 'CONTPAQi'); Tipo = 'Archivos de programa' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:ProgramData 'Compac'); Tipo = 'Datos compartidos locales' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:ProgramData 'CONTPAQi'); Tipo = 'Datos compartidos locales' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:PUBLIC 'Documents\Compac'); Tipo = 'Documentos publicos' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:PUBLIC 'Documents\CONTPAQi'); Tipo = 'Documentos publicos' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:LOCALAPPDATA 'Compac'); Tipo = 'Configuracion del usuario' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:LOCALAPPDATA 'CONTPAQi'); Tipo = 'Configuracion del usuario' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:APPDATA 'Compac'); Tipo = 'Configuracion del usuario' },
        [PSCustomObject]@{ Ruta = (Join-Path $env:APPDATA 'CONTPAQi'); Tipo = 'Configuracion del usuario' }
    ) | Where-Object { $_.Ruta -and (Test-Path -LiteralPath $_.Ruta -PathType Container) } | ForEach-Object {
        [PSCustomObject]@{ Ruta = $_.Ruta; Derecho = 'FullControl'; Tipo = $_.Tipo; TipoObjeto = 'Directory' }
    }

    $raicesAccesos = @(
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('DesktopDirectory'),
        [Environment]::GetFolderPath('CommonStartMenu'),
        [Environment]::GetFolderPath('StartMenu')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    foreach ($raizAcceso in $raicesAccesos) {
        foreach ($acceso in @(Get-ChildItem -LiteralPath $raizAcceso -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)CONTPAQ|COMPAC' })) {
            $candidatas += [PSCustomObject]@{
                Ruta = $acceso.FullName; Derecho = 'FullControl'; Tipo = 'Acceso directo CONTPAQi'; TipoObjeto = 'File'
            }
        }
    }

    $unicas = @{}
    foreach ($item in $candidatas) {
        $rutaCompleta = [IO.Path]::GetFullPath($item.Ruta).TrimEnd('\')
        $clave = $rutaCompleta.ToLowerInvariant()
        if (-not $unicas.ContainsKey($clave)) {
            $unicas[$clave] = [PSCustomObject]@{
                Ruta = $rutaCompleta; Derecho = 'FullControl'; Tipo = $item.Tipo
                TipoObjeto = $(if ($item.TipoObjeto) { $item.TipoObjeto } else { 'Directory' })
            }
        }
    }
    return @($unicas.Values | Sort-Object Ruta)
}

function Get-ClavesRegistroCONTPAQi {
    $bases = @('HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node', 'HKCU:\Software')
    $claves = New-Object System.Collections.Generic.List[object]
    foreach ($base in $bases) {
        if (-not (Test-Path -LiteralPath $base)) { continue }
        foreach ($clave in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | Where-Object {
            $_.PSChildName -match '(?i)computaci[oó]n en acci[oó]n|compac|contpaqi'
        })) {
            $claves.Add([PSCustomObject]@{ Ruta = ("Registry::{0}" -f $clave.Name); Visible = $clave.Name })
        }
    }
    return @($claves | Sort-Object Ruta -Unique)
}

function Test-PermisoUsuariosCONTPAQi {
    param(
        [Parameter(Mandatory)][string]$Ruta,
        [Parameter(Mandatory)][ValidateSet('Modify', 'ReadAndExecute', 'FullControl')][string]$Derecho
    )
    try {
        $sidsRequeridos = @('S-1-1-0','S-1-5-32-544','S-1-5-32-545','S-1-5-11','S-1-5-13','S-1-5-18','S-1-3-0')
        try {
            $sidAdministrador = Get-CimInstance Win32_UserAccount -Filter 'LocalAccount=True' -ErrorAction Stop |
                Where-Object { $_.SID -match '-500$' } | Select-Object -First 1 -ExpandProperty SID
            if ($sidAdministrador) { $sidsRequeridos += [string]$sidAdministrador }
        } catch { }
        $sidsRequeridos = @($sidsRequeridos | Select-Object -Unique)
        $requerido = [Security.AccessControl.FileSystemRights][Enum]::Parse([Security.AccessControl.FileSystemRights], $Derecho)
        $reglas = @(Get-Acl -LiteralPath $Ruta -ErrorAction Stop | Select-Object -ExpandProperty Access)
        $permitidos = @{}
        foreach ($regla in $reglas) {
            try { $sid = $regla.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { continue }
            if ($sid -notin $sidsRequeridos) { continue }
            $incluye = (($regla.FileSystemRights -band $requerido) -eq $requerido)
            if ($incluye -and $regla.AccessControlType -eq 'Deny') { return $false }
            if ($incluye -and $regla.AccessControlType -eq 'Allow') { $permitidos[$sid] = $true }
        }
        return (@($sidsRequeridos | Where-Object { -not $permitidos.ContainsKey($_) }).Count -eq 0)
    } catch {
        return $false
    }
}

function Invoke-RepararPermisosTerminalCONTPAQi {
    param(
        [switch]$ConfirmacionOmitida,
        [switch]$ModoIntegrado
    )
    if (-not $ModoIntegrado) {
        Write-Encabezado -Titulo 'PERMISOS CONTPAQI PARA TERMINALES' -Subtitulo 'Acceso local seguro para usuarios estandar' -Color $Script:ColorTerminal
    }
    Write-Log -Mensaje 'Se aplicara Control total en rutas oficiales CONTPAQi, accesos directos y claves del fabricante, con respaldo SDDL previo.' -Nivel WARN
    if (-not $ConfirmacionOmitida -and -not (Confirmar-Movimiento -Frase 'APLICAR PERMISOS' `
        -Accion 'Corregir permisos locales CONTPAQi' `
        -Detalle 'Se agregaran permisos oficiales a las identidades indicadas sin borrar reglas existentes y se respaldaran las ACL.')) {
        return [PSCustomObject]@{ Correcto = $false; Cancelado = $true; Correctos = 0; Fallidos = 0; ArchivoRespaldo = $null }
    }

    $rutas = @(Get-RutasPermisosTerminalCONTPAQi)
    $clavesRegistro = @(Get-ClavesRegistroCONTPAQi)
    if ($rutas.Count -eq 0 -and $clavesRegistro.Count -eq 0) {
        Write-Log -Mensaje 'No se encontraron rutas ni claves locales CONTPAQi a las que aplicar permisos.' -Nivel WARN
        return [PSCustomObject]@{ Correcto = $true; Cancelado = $false; Correctos = 0; Fallidos = 0; ArchivoRespaldo = $null }
    }
    $directorioRespaldo = Join-Path $env:ProgramData 'CONTPAQiToolbox\ACL'
    $archivoRespaldo = Join-Path $directorioRespaldo ("Permisos_{0}_{1}.json" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $rutasJson = ConvertTo-Json -InputObject @($rutas) -Depth 4 -Compress
    $registroJson = ConvertTo-Json -InputObject @($clavesRegistro) -Depth 4 -Compress
    $codigoPermisos = @'
param([string]$RoutesJson, [string]$RegistryJson, [string]$BackupFile, [string]$ComputerName)
function ConvertTo-FlatList {
    param([string]$Json)
    $lista = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($Json) -or $Json -eq 'null') { return @() }
    $parsed = ConvertFrom-Json -InputObject $Json
    if ($parsed -is [System.Array]) { foreach ($entry in $parsed) { if ($null -ne $entry) { $lista.Add($entry) } } }
    elseif ($null -ne $parsed) { $lista.Add($parsed) }
    return @($lista | ForEach-Object { $_ })
}
$rutas = @(ConvertTo-FlatList -Json $RoutesJson)
$clavesRegistro = @(ConvertTo-FlatList -Json $RegistryJson)
$sidValues = New-Object System.Collections.Generic.List[string]
foreach ($sidValue in @('S-1-1-0','S-1-5-32-544','S-1-5-32-545','S-1-5-11','S-1-5-13','S-1-5-18','S-1-3-0')) { $sidValues.Add($sidValue) }
try {
    $administradorLocal = Get-CimInstance Win32_UserAccount -Filter 'LocalAccount=True' -ErrorAction Stop |
        Where-Object { $_.SID -match '-500$' } | Select-Object -First 1 -ExpandProperty SID
    if ($administradorLocal -and -not $sidValues.Contains([string]$administradorLocal)) { $sidValues.Add([string]$administradorLocal) }
} catch { }
$identidades = @($sidValues | ForEach-Object { New-Object Security.Principal.SecurityIdentifier($_) })
function Open-RegistryKeyInternal {
    param([string]$NativePath, [bool]$Writable)
    if ($NativePath -match '^HKEY_LOCAL_MACHINE\\(.+)$') { return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($matches[1], $Writable) }
    if ($NativePath -match '^HKEY_CURRENT_USER\\(.+)$') { return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($matches[1], $Writable) }
    return $null
}
$respaldos = @()
foreach ($item in $rutas) {
    try {
        $acl = Get-Acl -LiteralPath $item.Ruta -ErrorAction Stop
        $respaldos += [PSCustomObject]@{ Tipo = 'Archivo'; Ruta = [string]$item.Ruta; Sddl = $acl.Sddl; Derecho = 'FullControl'; Error = $null }
    } catch {
        $respaldos += [PSCustomObject]@{ Tipo = 'Archivo'; Ruta = [string]$item.Ruta; Sddl = $null; Derecho = 'FullControl'; Error = $_.Exception.Message }
    }
}
foreach ($item in $clavesRegistro) {
    try {
        $nativePath = [string](@($item.Visible)[0])
        $registryKey = Open-RegistryKeyInternal -NativePath $nativePath -Writable $false
        if (-not $registryKey) { throw "No se pudo abrir $nativePath." }
        try { $acl = $registryKey.GetAccessControl() } finally { $registryKey.Dispose() }
        $respaldos += [PSCustomObject]@{ Tipo = 'Registro'; Ruta = $nativePath; Sddl = $acl.Sddl; Derecho = 'FullControl'; Error = $null }
    } catch {
        $respaldos += [PSCustomObject]@{ Tipo = 'Registro'; Ruta = [string](@($item.Visible)[0]); Sddl = $null; Derecho = 'FullControl'; Error = $_.Exception.Message }
    }
}
$carpeta = Split-Path -Parent $BackupFile
if (-not (Test-Path -LiteralPath $carpeta)) { New-Item -ItemType Directory -Path $carpeta -Force -ErrorAction Stop | Out-Null }
[PSCustomObject]@{
    Equipo = $ComputerName
    Fecha = (Get-Date).ToString('o')
    Identidades = @($identidades | ForEach-Object { $_.Value })
    Rutas = $respaldos
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $BackupFile -Encoding UTF8 -ErrorAction Stop

$resultados = @()
foreach ($item in $rutas) {
    try {
        $ruta = [string](@($item.Ruta)[0])
        $tipoObjeto = [string](@($item.TipoObjeto)[0])
        $acl = Get-Acl -LiteralPath $ruta -ErrorAction Stop
        $cambios = 0
        $denegacionesEliminadas = 0
        foreach ($identidad in $identidades) {
            $sidObjetivo = $identidad.Value
            $tienePermiso = $false
            foreach ($reglaActual in @($acl.Access)) {
                try { $sidActual = $reglaActual.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { continue }
                if ($sidActual -ne $sidObjetivo) { continue }
                $incluyeTotal = (($reglaActual.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl)
                $interfiere = (($reglaActual.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -ne 0)
                if ($reglaActual.AccessControlType -eq 'Allow' -and $incluyeTotal) { $tienePermiso = $true }
                if ($reglaActual.AccessControlType -eq 'Deny' -and $interfiere -and -not $reglaActual.IsInherited) {
                    $acl.RemoveAccessRuleSpecific($reglaActual)
                    $denegacionesEliminadas++
                    $cambios++
                }
            }
            if ($tienePermiso) { continue }
            $herencia = if ($tipoObjeto -eq 'File') { [Security.AccessControl.InheritanceFlags]::None } else { [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit' }
            $regla = New-Object Security.AccessControl.FileSystemAccessRule(
                $identidad, [Security.AccessControl.FileSystemRights]::FullControl, $herencia,
                [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow
            )
            $null = $acl.AddAccessRule($regla)
            $cambios++
        }
        if ($cambios -gt 0) { Set-Acl -LiteralPath $ruta -AclObject $acl -ErrorAction Stop }
        $presentes = @{}
        $bloqueos = New-Object System.Collections.Generic.List[string]
        foreach ($reglaActual in @((Get-Acl -LiteralPath $ruta -ErrorAction Stop).Access)) {
            try { $sidActual = $reglaActual.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { continue }
            if ($reglaActual.AccessControlType -eq 'Allow' -and (($reglaActual.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl)) { $presentes[$sidActual] = $true }
            if ($sidActual -in @($identidades.Value) -and $reglaActual.AccessControlType -eq 'Deny' -and (($reglaActual.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -ne 0)) {
                $bloqueos.Add("$sidActual$(if ($reglaActual.IsInherited) { ' (heredado)' } else { '' })")
            }
        }
        $faltantes = @($identidades | Where-Object { -not $presentes.ContainsKey($_.Value) } | ForEach-Object { $_.Value })
        $correcto = ($faltantes.Count -eq 0 -and $bloqueos.Count -eq 0)
        $estado = if (-not $correcto) { 'Fallido' } elseif ($cambios -eq 0) { 'YaCorrecto' } else { 'Corregido' }
        $resultados += [PSCustomObject]@{
            Tipo = 'Archivo'; Ruta = $ruta; Derecho = 'FullControl'; Correcto = $correcto; Estado = $estado
            Cambios = $cambios; DenegacionesEliminadas = $denegacionesEliminadas
            Faltantes = $faltantes; Bloqueos = @($bloqueos); Error = $(if ($bloqueos.Count) { "Denegaciones vigentes: $($bloqueos -join ', ')" } else { $null })
        }
    } catch {
        $resultados += [PSCustomObject]@{ Tipo = 'Archivo'; Ruta = [string](@($item.Ruta)[0]); Derecho = 'FullControl'; Correcto = $false; Estado = 'Fallido'; Cambios = 0; DenegacionesEliminadas = 0; Faltantes = @(); Bloqueos = @(); Error = $_.Exception.Message }
    }
}
foreach ($item in $clavesRegistro) {
    try {
        $ruta = [string](@($item.Visible)[0])
        $registryKey = Open-RegistryKeyInternal -NativePath $ruta -Writable $true
        if (-not $registryKey) { throw "No se pudo abrir $ruta con permisos de escritura." }
        try {
            $acl = $registryKey.GetAccessControl()
            $cambios = 0
            $denegacionesEliminadas = 0
            foreach ($identidad in $identidades) {
                $sidObjetivo = $identidad.Value
                $tienePermiso = $false
                foreach ($reglaActual in @($acl.Access)) {
                    try { $sidActual = $reglaActual.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { continue }
                    if ($sidActual -ne $sidObjetivo) { continue }
                    $incluyeTotal = (($reglaActual.RegistryRights -band [Security.AccessControl.RegistryRights]::FullControl) -eq [Security.AccessControl.RegistryRights]::FullControl)
                    $interfiere = (($reglaActual.RegistryRights -band [Security.AccessControl.RegistryRights]::FullControl) -ne 0)
                    if ($reglaActual.AccessControlType -eq 'Allow' -and $incluyeTotal) { $tienePermiso = $true }
                    if ($reglaActual.AccessControlType -eq 'Deny' -and $interfiere -and -not $reglaActual.IsInherited) {
                        $acl.RemoveAccessRuleSpecific($reglaActual)
                        $denegacionesEliminadas++
                        $cambios++
                    }
                }
                if ($tienePermiso) { continue }
                $regla = New-Object Security.AccessControl.RegistryAccessRule(
                    $identidad, [Security.AccessControl.RegistryRights]::FullControl,
                    [Security.AccessControl.InheritanceFlags]::ContainerInherit,
                    [Security.AccessControl.PropagationFlags]::None,
                    [Security.AccessControl.AccessControlType]::Allow
                )
                $null = $acl.AddAccessRule($regla)
                $cambios++
            }
            if ($cambios -gt 0) { $registryKey.SetAccessControl($acl) }
            $aclVerificada = $registryKey.GetAccessControl()
        } finally { $registryKey.Dispose() }
        $presentes = @{}
        $bloqueos = New-Object System.Collections.Generic.List[string]
        foreach ($reglaActual in @($aclVerificada.Access)) {
            try { $sidActual = $reglaActual.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { continue }
            if ($reglaActual.AccessControlType -eq 'Allow' -and (($reglaActual.RegistryRights -band [Security.AccessControl.RegistryRights]::FullControl) -eq [Security.AccessControl.RegistryRights]::FullControl)) { $presentes[$sidActual] = $true }
            if ($sidActual -in @($identidades.Value) -and $reglaActual.AccessControlType -eq 'Deny' -and (($reglaActual.RegistryRights -band [Security.AccessControl.RegistryRights]::FullControl) -ne 0)) {
                $bloqueos.Add("$sidActual$(if ($reglaActual.IsInherited) { ' (heredado)' } else { '' })")
            }
        }
        $faltantes = @($identidades | Where-Object { -not $presentes.ContainsKey($_.Value) } | ForEach-Object { $_.Value })
        $correcto = ($faltantes.Count -eq 0 -and $bloqueos.Count -eq 0)
        $estado = if (-not $correcto) { 'Fallido' } elseif ($cambios -eq 0) { 'YaCorrecto' } else { 'Corregido' }
        $resultados += [PSCustomObject]@{
            Tipo = 'Registro'; Ruta = $ruta; Derecho = 'FullControl'; Correcto = $correcto; Estado = $estado
            Cambios = $cambios; DenegacionesEliminadas = $denegacionesEliminadas
            Faltantes = $faltantes; Bloqueos = @($bloqueos); Error = $(if ($bloqueos.Count) { "Denegaciones vigentes: $($bloqueos -join ', ')" } else { $null })
        }
    } catch {
        $resultados += [PSCustomObject]@{ Tipo = 'Registro'; Ruta = [string](@($item.Ruta)[0]); Derecho = 'FullControl'; Correcto = $false; Estado = 'Fallido'; Cambios = 0; DenegacionesEliminadas = 0; Faltantes = @(); Bloqueos = @(); Error = $_.Exception.Message }
    }
}
[PSCustomObject]@{ Resultados = $resultados; ArchivoRespaldo = $BackupFile; Identidades = @($identidades | ForEach-Object { $_.Value }) }
'@
    Write-Log -Mensaje "Respaldando ACL y aplicando permisos en $($rutas.Count) ruta(s) y $($clavesRegistro.Count) clave(s) de registro..." -Nivel PROGRESS
    $worker = Invoke-ResponsiveWorker -ScriptText $codigoPermisos `
        -Arguments @($rutasJson, $registroJson, $archivoRespaldo, $env:COMPUTERNAME) `
        -TimeoutSeconds 1800 -Activity 'Corrigiendo permisos CONTPAQi'
    if (-not $worker.Correcto -or $worker.Timeout -or -not $worker.Resultado) {
        Write-Log -Mensaje "No se aplicaron los permisos de forma completa: $($worker.Error)" -Nivel ERROR
        return [PSCustomObject]@{ Correcto = $false; Cancelado = $false; Correctos = 0; Fallidos = ($rutas.Count + $clavesRegistro.Count); ArchivoRespaldo = $archivoRespaldo }
    }

    $correctos = 0
    $yaCorrectos = 0
    $corregidos = 0
    $fallidos = 0
    foreach ($resultado in @($worker.Resultado.Resultados)) {
        if ($resultado.Correcto) {
            $correctos++
            if ($resultado.Estado -eq 'YaCorrecto') {
                $yaCorrectos++
                Write-Log -Mensaje "Permisos ya correctos, sin cambios: $($resultado.Ruta)" -Nivel OK
            } else {
                $corregidos++
                $detalleCambio = if ([int]$resultado.DenegacionesEliminadas -gt 0) { " | $($resultado.DenegacionesEliminadas) denegacion(es) explicita(s) retirada(s)" } else { '' }
                Write-Log -Mensaje "Permisos corregidos y verificados: $($resultado.Ruta)$detalleCambio" -Nivel OK
            }
        } else {
            $fallidos++
            $faltantesTexto = if (@($resultado.Faltantes).Count) { " | SID faltantes: $(@($resultado.Faltantes) -join ', ')" } else { '' }
            Write-Log -Mensaje "No se pudo validar $($resultado.Ruta): $($resultado.Error)$faltantesTexto" -Nivel ERROR
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
    Write-Log -Mensaje "Permisos locales finalizados: $yaCorrectos ya correctos | $corregidos corregidos | $fallidos con incidencia." -Nivel $(if ($fallidos -eq 0) { 'OK' } else { 'WARN' })
    if ($fallidos -eq 0) { Write-Log -Mensaje 'Cierra y vuelve a abrir CONTPAQi para que la terminal use los permisos actualizados.' -Nivel INFO }
    return [PSCustomObject]@{
        Correcto = ($fallidos -eq 0); Cancelado = $false; Correctos = $correctos; YaCorrectos = $yaCorrectos; Corregidos = $corregidos; Fallidos = $fallidos
        ArchivoRespaldo = [string]$worker.Resultado.ArchivoRespaldo
    }
}

function Invoke-ConfigurarCentroConfianzaExcelCONTPAQi {
    param([switch]$ConfirmacionOmitida, [switch]$ModoIntegrado)
    $versiones = @('16.0','15.0','14.0') | Where-Object {
        (Test-Path -LiteralPath "HKCU:\Software\Microsoft\Office\$_\Excel") -or
        (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Office\$_\Excel") -or
        (Test-Path -LiteralPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\$_\Excel")
    }
    if ($versiones.Count -eq 0) {
        Write-Log -Mensaje 'Excel no esta instalado; se omite la configuracion del Centro de confianza.' -Nivel INFO
        return [PSCustomObject]@{ Correcto = $true; Omitido = $true; Correctos = 0; Fallidos = 0; Respaldos = @() }
    }
    $ubicaciones = @('C:\Compacw', (Join-Path ${env:ProgramFiles(x86)} 'Compacw')) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    if (-not $ModoIntegrado) {
        Write-Encabezado -Titulo 'CENTRO DE CONFIANZA EXCEL' -Subtitulo 'Compatibilidad con herramientas CONTPAQi' -Color 'Yellow'
    }
    Write-Log -Mensaje 'SEGURIDAD: las ubicaciones de confianza y macros/ActiveX habilitados reducen la proteccion de Office. Solo se aplicaran al usuario actual y con respaldo.' -Nivel WARN
    if (-not $ConfirmacionOmitida -and -not (Confirmar-Movimiento -Frase 'CONFIGURAR EXCEL' `
        -Accion 'Configurar Centro de confianza de Excel para CONTPAQi' `
        -Detalle 'Se habilitaran macros, ActiveX y acceso VBA para el usuario actual; las claves anteriores se respaldaran.')) {
        return [PSCustomObject]@{ Correcto = $false; Omitido = $true; Correctos = 0; Fallidos = 0; Respaldos = @() }
    }
    $versionesJson = ConvertTo-Json -InputObject @($versiones) -Compress
    $ubicacionesJson = ConvertTo-Json -InputObject @($ubicaciones) -Compress
    $directorioRespaldo = Join-Path $env:ProgramData ("CONTPAQiToolbox\ExcelTrust\{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $codigo = @'
param([string]$VersionsJson, [string]$LocationsJson, [string]$BackupDirectory)
function Expand-JsonArray([string]$Json) {
    $list = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($Json) -or $Json -eq 'null') { return @() }
    $value = ConvertFrom-Json -InputObject $Json
    if ($value -is [Array]) { foreach ($entry in $value) { $list.Add($entry) } } else { $list.Add($value) }
    return @($list | ForEach-Object { $_ })
}
$versions = @(Expand-JsonArray $VersionsJson | ForEach-Object { [string]$_ })
$locations = @(Expand-JsonArray $LocationsJson | ForEach-Object { [string]$_ })
if (-not (Test-Path -LiteralPath $BackupDirectory)) { New-Item -ItemType Directory -Path $BackupDirectory -Force -ErrorAction Stop | Out-Null }
$results = @()
foreach ($version in $versions) {
    try {
        $security = "HKCU:\Software\Microsoft\Office\$version\Excel\Security"
        $commonSecurity = "HKCU:\Software\Microsoft\Office\$version\Common\Security"
        $trustedRoot = Join-Path $security 'Trusted Locations'
        $securityNative = "HKCU\Software\Microsoft\Office\$version\Excel\Security"
        $commonNative = "HKCU\Software\Microsoft\Office\$version\Common\Security"
        $backups = @()
        if (Test-Path -LiteralPath $security) {
            $file = Join-Path $BackupDirectory "Excel_${version}_Security.reg"
            & reg.exe export $securityNative $file /y 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $backups += $file }
        }
        if (Test-Path -LiteralPath $commonSecurity) {
            $file = Join-Path $BackupDirectory "Office_${version}_CommonSecurity.reg"
            & reg.exe export $commonNative $file /y 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $backups += $file }
        }
        foreach ($key in @($security, $commonSecurity, $trustedRoot)) {
            if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force -ErrorAction Stop | Out-Null }
        }
        New-ItemProperty -Path $security -Name 'VBAWarnings' -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $security -Name 'AccessVBOM' -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $commonSecurity -Name 'UFIControls' -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null

        $index = 90
        foreach ($location in $locations) {
            $normalized = [IO.Path]::GetFullPath($location).TrimEnd('\') + '\'
            $existing = @(Get-ChildItem -LiteralPath $trustedRoot -ErrorAction SilentlyContinue | Where-Object {
                try { ([IO.Path]::GetFullPath([string](Get-ItemPropertyValue -LiteralPath $_.PSPath -Name Path -ErrorAction Stop)).TrimEnd('\') + '\') -ieq $normalized } catch { $false }
            } | Select-Object -First 1)
            $locationKey = if ($existing.Count) { $existing[0].PSPath } else {
                while (Test-Path -LiteralPath (Join-Path $trustedRoot "Location$index")) { $index++ }
                $newKey = Join-Path $trustedRoot "Location$index"
                New-Item -Path $newKey -Force -ErrorAction Stop | Out-Null
                $index++
                $newKey
            }
            New-ItemProperty -Path $locationKey -Name Path -Value $normalized -PropertyType String -Force -ErrorAction Stop | Out-Null
            New-ItemProperty -Path $locationKey -Name AllowSubfolders -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            New-ItemProperty -Path $locationKey -Name Description -Value 'CONTPAQi Toolbox - ubicacion oficial' -PropertyType String -Force -ErrorAction Stop | Out-Null
        }

        $fileBlock = Join-Path $security 'FileBlock'
        if (Test-Path -LiteralPath $fileBlock) { Remove-Item -LiteralPath $fileBlock -Recurse -Force -ErrorAction Stop }
        $policy = Test-Path -LiteralPath "HKCU:\Software\Policies\Microsoft\Office\$version\Excel\Security"
        $verifySecurity = Get-ItemProperty -LiteralPath $security -ErrorAction Stop
        $verifyCommon = Get-ItemProperty -LiteralPath $commonSecurity -ErrorAction Stop
        $ok = ([int]$verifySecurity.VBAWarnings -eq 1 -and [int]$verifySecurity.AccessVBOM -eq 1 -and [int]$verifyCommon.UFIControls -eq 1)
        $results += [PSCustomObject]@{ Version = $version; Correcto = $ok; PoliticaDetectada = $policy; Respaldos = $backups; Error = $null }
    } catch {
        $results += [PSCustomObject]@{ Version = $version; Correcto = $false; PoliticaDetectada = $false; Respaldos = @(); Error = $_.Exception.Message }
    }
}
[PSCustomObject]@{ Resultados = $results; DirectorioRespaldo = $BackupDirectory }
'@
    $worker = Invoke-ResponsiveWorker -ScriptText $codigo -Arguments @($versionesJson, $ubicacionesJson, $directorioRespaldo) `
        -TimeoutSeconds 180 -Activity 'Configurando Centro de confianza de Excel'
    if (-not $worker.Correcto -or $worker.Timeout -or -not $worker.Resultado) {
        Write-Log -Mensaje "No se pudo configurar Excel: $($worker.Error)" -Nivel ERROR
        return [PSCustomObject]@{ Correcto = $false; Omitido = $false; Correctos = 0; Fallidos = $versiones.Count; Respaldos = @() }
    }
    $correctos = 0; $fallidos = 0; $respaldos = New-Object System.Collections.Generic.List[string]
    foreach ($resultado in @($worker.Resultado.Resultados)) {
        foreach ($respaldo in @($resultado.Respaldos)) { if ($respaldo) { $respaldos.Add([string]$respaldo) } }
        if ($resultado.Correcto) {
            $correctos++
            Write-Log -Mensaje "Excel $($resultado.Version): Centro de confianza configurado y verificado para el usuario actual." -Nivel OK
            if ($resultado.PoliticaDetectada) { Write-Log -Mensaje "Excel $($resultado.Version): una directiva de grupo puede reemplazar estos valores." -Nivel WARN }
        } else {
            $fallidos++
            Write-Log -Mensaje "Excel $($resultado.Version): no se pudo completar la configuracion: $($resultado.Error)" -Nivel ERROR
        }
    }
    Write-Log -Mensaje "Respaldos de Excel: $($worker.Resultado.DirectorioRespaldo)" -Nivel INFO
    return [PSCustomObject]@{ Correcto = ($fallidos -eq 0); Omitido = $false; Correctos = $correctos; Fallidos = $fallidos; Respaldos = @($respaldos) }
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


# --- DIAGNOSTICO INTELIGENTE Y REPORTE PROFESIONAL ---
# Todas las pruebas de esta seccion son de solo lectura. El diagnostico explica
# evidencia, consecuencia y siguiente accion, pero nunca aplica reparaciones.
function Get-NombreOfficeLegible {
    param([AllowEmptyString()][string]$ProductReleaseId)
    if ([string]::IsNullOrWhiteSpace($ProductReleaseId)) { return 'Microsoft Office / Excel' }
    $principal = @($ProductReleaseId -split ',' | Where-Object { $_ } | Select-Object -First 1)[0]
    switch -Regex ($principal) {
        '^O365ProPlusRetail$'       { return 'Microsoft 365 Apps para empresas' }
        '^O365BusinessRetail$'      { return 'Microsoft 365 Apps para negocios' }
        '^Professional2024Retail$'  { return 'Microsoft Office Professional 2024' }
        '^ProPlus2024Volume$'       { return 'Microsoft Office Professional Plus 2024' }
        '^Professional2021Retail$'  { return 'Microsoft Office Professional 2021' }
        '^ProPlus2021Volume$'       { return 'Microsoft Office Professional Plus 2021' }
        '^Professional2019Retail$'  { return 'Microsoft Office Professional 2019' }
        '^ProPlus2019Volume$'       { return 'Microsoft Office Professional Plus 2019' }
        '^HomeBusiness(2019|2021|2024)Retail$' { return "Microsoft Office Hogar y Empresas $($matches[1])" }
        '^Excel(2019|2021|2024)Retail$' { return "Microsoft Excel $($matches[1])" }
        default { return "Microsoft Office ($principal)" }
    }
}

function Get-MicrosoftExcelInfo {
    $configuracion = $null
    foreach ($ruta in @(
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration'
    )) {
        if (Test-Path -LiteralPath $ruta) {
            try { $configuracion = Get-ItemProperty -LiteralPath $ruta -ErrorAction Stop; break } catch { }
        }
    }

    $excelPath = $null
    foreach ($ruta in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\excel.exe'
    )) {
        if (-not (Test-Path -LiteralPath $ruta)) { continue }
        try {
            $candidate = [string](Get-ItemProperty -LiteralPath $ruta -ErrorAction Stop).'(default)'
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { $excelPath = $candidate; break }
        } catch { }
    }
    if (-not $excelPath -and $configuracion.InstallationPath) {
        $candidate = Join-Path ([string]$configuracion.InstallationPath) 'Root\Office16\EXCEL.EXE'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $excelPath = $candidate }
    }

    $productoRegistrado = if ($configuracion) { [string]$configuracion.ProductReleaseIds } else { '' }
    $producto = Get-NombreOfficeLegible -ProductReleaseId $productoRegistrado
    $version = if ($configuracion.VersionToReport) { [string]$configuracion.VersionToReport } elseif ($excelPath) { [Diagnostics.FileVersionInfo]::GetVersionInfo($excelPath).FileVersion } else { 'N/D' }
    $plataforma = if ($configuracion.Platform) { [string]$configuracion.Platform } elseif ($excelPath -match '(?i)Program Files \(x86\)') { 'x86' } elseif ($excelPath) { 'x64' } else { '' }
    $arquitectura = if ($plataforma -eq 'x86') { '32 bits' } elseif ($plataforma -eq 'x64') { '64 bits' } else { 'No determinada' }

    $consultaLicencia = @'
Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='0ff1ce15-a989-479d-af46-f275c6370663'" -ErrorAction Stop |
    Where-Object {
        ($_.PartialProductKey -or $_.LicenseStatus -ne 0) -and
        "$($_.Name) $($_.Description)" -match '(?i)Office|Excel|O365|Microsoft 365'
    } |
    Sort-Object @{Expression={ if ([int]$_.LicenseStatus -eq 1) { 0 } else { 1 } }}, Name |
    Select-Object -First 1 Name, Description, LicenseStatus, LicenseStatusReason, GracePeriodRemaining
'@
    $resultadoLicencia = Invoke-ResponsiveWorker -ScriptText $consultaLicencia -TimeoutSeconds 30 -Activity 'Validando licencia de Microsoft Office'
    $licencia = if ($resultadoLicencia.Correcto) { $resultadoLicencia.Resultado } else { $null }
    $estadoLicencia = if (-not $excelPath) { 'NO APLICA' } elseif (-not $licencia) { 'NO SE PUDO CONFIRMAR' } else {
        switch ([int]$licencia.LicenseStatus) {
            1 { 'ACTIVADA' }
            2 { 'PERIODO DE GRACIA' }
            3 { 'GRACIA VENCIDA' }
            4 { 'NO ORIGINAL / GRACIA' }
            5 { 'MODO NOTIFICACION' }
            6 { 'GRACIA EXTENDIDA' }
            default { 'NO ACTIVADA' }
        }
    }
    $tipoLicencia = if (-not $licencia) { 'No determinado' } elseif ($licencia.Description -match '(?i)KMSCLIENT') { 'Volumen KMS' } elseif ($licencia.Description -match '(?i)MAK') { 'Volumen MAK' } elseif ($licencia.Description -match '(?i)RETAIL') { 'Retail' } elseif ($productoRegistrado -match '(?i)O365') { 'Suscripcion Microsoft 365' } else { 'Licencia de Office' }
    $compatibilidad = if (-not $excelPath) { 'Excel no detectado' } elseif ($arquitectura -eq '32 bits') { 'RECOMENDADO PARA CONTPAQi' } elseif ($arquitectura -eq '64 bits') { 'VALIDAR COMPLEMENTOS CONTPAQi' } else { 'ARQUITECTURA POR CONFIRMAR' }
    return [PSCustomObject]@{
        Detectado = [bool]$excelPath
        Producto = $producto
        Version = $version
        Arquitectura = $arquitectura
        Ejecutable = $excelPath
        Licencia = $estadoLicencia
        TipoLicencia = $tipoLicencia
        Compatibilidad = $compatibilidad
        ProductReleaseId = $productoRegistrado
    }
}

function Get-PrincipalesBasesDiagnosticoCONTPAQi {
    param([AllowEmptyCollection()][string[]]$Instancias = @())

    $resultados = New-Object System.Collections.Generic.List[object]
    $consulta = @"
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

CREATE TABLE #Respaldos (Nombre sysname PRIMARY KEY, UltimoRespaldo datetime NULL);
BEGIN TRY
    INSERT INTO #Respaldos (Nombre, UltimoRespaldo)
    SELECT database_name, MAX(backup_finish_date)
    FROM msdb.dbo.backupset
    WHERE type = 'D'
    GROUP BY database_name;
END TRY
BEGIN CATCH
END CATCH;

SELECT TOP (5)
    d.name AS Nombre,
    d.state_desc AS Estado,
    CAST(ISNULL(e.DatosAsignadosMB, ISNULL(m.AsignadoMB, 0)) AS decimal(19,2)) AS DatosAsignadosMB,
    CAST(ISNULL(e.DatosUsadosMB, 0) AS decimal(19,2)) AS DatosUsadosMB,
    CAST(CASE WHEN ISNULL(e.DatosAsignadosMB, ISNULL(m.AsignadoMB, 0)) > ISNULL(e.DatosUsadosMB, 0)
              THEN ISNULL(e.DatosAsignadosMB, ISNULL(m.AsignadoMB, 0)) - ISNULL(e.DatosUsadosMB, 0) ELSE 0 END AS decimal(19,2)) AS DatosLibresMB,
    CAST(CASE WHEN ISNULL(e.DatosAsignadosMB, ISNULL(m.AsignadoMB, 0)) > 0
              THEN ISNULL(e.DatosUsadosMB, 0) * 100.0 / ISNULL(e.DatosAsignadosMB, m.AsignadoMB) ELSE 0 END AS decimal(9,2)) AS UsoDatosPct,
    CAST(ISNULL(l.LogSizeMB, 0) AS decimal(19,2)) AS LogMB,
    CAST(ISNULL(l.LogUsedPct, 0) AS decimal(9,2)) AS LogUsadoPct,
    r.UltimoRespaldo
FROM sys.databases d
LEFT JOIN #Espacio e ON e.Nombre = d.name
LEFT JOIN #LogSpace l ON l.Nombre = d.name
LEFT JOIN #Respaldos r ON r.Nombre = d.name
OUTER APPLY (
    SELECT SUM(CASE WHEN type = 0 THEN size ELSE 0 END) * 8.0 / 1024 AS AsignadoMB
    FROM sys.master_files
    WHERE database_id = d.database_id
) m
WHERE d.database_id > 4
  AND NOT (d.name LIKE 'document[_]%' AND (d.name LIKE '%[_]content' OR d.name LIKE '%[_]metadata'))
  AND d.name NOT IN ('ADD_Catalogos','CompacWAdmin','GeneralSQL','dbDocumentosDigitales','CONTPAQ_I_SDK')
ORDER BY ISNULL(e.DatosUsadosMB, 0) DESC,
         ISNULL(e.DatosAsignadosMB, ISNULL(m.AsignadoMB, 0)) DESC,
         d.name;
"@

    foreach ($instancia in @($Instancias | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        $resultado = Invoke-SqlTableResponsive -Instancia $instancia -Consulta $consulta -TimeoutSegundos 55 -Actividad "Leyendo empresas principales de $instancia"
        if (-not $resultado.Correcto) {
            Write-Log -Mensaje "No fue posible obtener empresas de $($instancia): $($resultado.Error)" -Nivel WARN
            continue
        }
        foreach ($fila in @($resultado.Filas)) {
            $respaldo = $null
            if ($null -ne $fila.UltimoRespaldo -and $fila.UltimoRespaldo -isnot [DBNull]) {
                try { $respaldo = [datetime]$fila.UltimoRespaldo } catch { $respaldo = $null }
            }
            [void]$resultados.Add([PSCustomObject]@{
                Instancia = $instancia
                Nombre = [string]$fila.Nombre
                Estado = [string]$fila.Estado
                DatosAsignadosMB = [math]::Round([double]$fila.DatosAsignadosMB, 2)
                DatosUsadosMB = [math]::Round([double]$fila.DatosUsadosMB, 2)
                DatosLibresMB = [math]::Round([double]$fila.DatosLibresMB, 2)
                UsoDatosPct = [math]::Round([double]$fila.UsoDatosPct, 1)
                LogMB = [math]::Round([double]$fila.LogMB, 2)
                LogUsadoPct = [math]::Round([double]$fila.LogUsadoPct, 1)
                UltimoRespaldo = $respaldo
            })
        }
    }
    return @($resultados | Sort-Object DatosUsadosMB, DatosAsignadosMB -Descending | Select-Object -First 5)
}

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

    Write-Log -Mensaje '[1/9] Identificando equipo y sistema operativo...' -Nivel PROGRESS
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

    Write-Log -Mensaje '[2/9] Revisando productos CONTPAQi instalados...' -Nivel PROGRESS
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

    Write-Log -Mensaje '[3/9] Identificando Excel, arquitectura y licencia...' -Nivel PROGRESS
    $excel = Get-MicrosoftExcelInfo
    $inventario.Excel = $excel
    if (-not $excel.Detectado) {
        Add-DiagnosticoHallazgo -Severidad INFORMATIVA -Categoria 'Microsoft Excel' -Titulo 'Microsoft Excel no detectado' `
            -Evidencia 'No se encontro EXCEL.EXE mediante las rutas registradas de Windows y Office.' `
            -Consecuencia 'Las funciones de exportacion o integraciones que dependan de Excel pueden no estar disponibles.' `
            -Accion 'Instala Excel solamente si los procesos del cliente lo requieren; para integraciones CONTPAQi, valida primero la edicion compatible.'
    } elseif ($excel.Arquitectura -eq '64 bits') {
        Add-DiagnosticoHallazgo -Severidad MEDIA -Categoria 'Microsoft Excel' -Titulo 'Excel de 64 bits detectado' `
            -Evidencia "$($excel.Producto) | Version $($excel.Version) | $($excel.Arquitectura)." `
            -Consecuencia 'Algunos complementos, SDK, reportes o integraciones heredadas de CONTPAQi pueden requerir Office de 32 bits.' `
            -Accion 'Confirma los complementos utilizados. Si requieren 32 bits, respalda plantillas y configuracion, desinstala Office de 64 bits e instala la misma edicion de 32 bits con licencia valida.'
    }
    if ($excel.Detectado -and $excel.Licencia -notin @('ACTIVADA','NO SE PUDO CONFIRMAR')) {
        Add-DiagnosticoHallazgo -Severidad ALTA -Categoria 'Microsoft Excel' -Titulo "Licencia de Office: $($excel.Licencia)" `
            -Evidencia "$($excel.Producto) | Tipo: $($excel.TipoLicencia)." `
            -Consecuencia 'Excel puede mostrar avisos, entrar en modo reducido o impedir edicion y automatizaciones.' `
            -Accion 'Abre Excel con el usuario final, revisa Archivo > Cuenta y reactiva con la cuenta, MAK o servidor KMS autorizado.'
    } elseif ($excel.Detectado -and $excel.Licencia -eq 'NO SE PUDO CONFIRMAR') {
        Add-DiagnosticoHallazgo -Severidad INFORMATIVA -Categoria 'Microsoft Excel' -Titulo 'Activacion de Office no confirmada por Windows' `
            -Evidencia "$($excel.Producto) esta instalado, pero SoftwareLicensingProduct no devolvio una licencia verificable." `
            -Consecuencia 'No significa necesariamente que Office carezca de licencia; algunas suscripciones se validan por usuario.' `
            -Accion 'Abre Excel con el usuario habitual y confirma Producto activado en Archivo > Cuenta.'
    }
    Write-Log -Mensaje "Excel: $($excel.Producto) | $($excel.Arquitectura) | Licencia $($excel.Licencia) | $($excel.Compatibilidad)." -Nivel $(if ($excel.Detectado -and $excel.Arquitectura -eq '32 bits' -and $excel.Licencia -eq 'ACTIVADA') { 'OK' } elseif ($excel.Detectado) { 'WARN' } else { 'INFO' })

    Write-Log -Mensaje '[4/9] Validando servicios y ejecutables...' -Nivel PROGRESS
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

    Write-Log -Mensaje '[5/9] Comprobando motores SQL Server...' -Nivel PROGRESS
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
    $instanciasDisponibles = @($sqlResultados | Where-Object { $_.Estado -eq 'Disponible' } | ForEach-Object { [string]$_.Instancia })
    $inventario.EmpresasPrincipales = @(Get-PrincipalesBasesDiagnosticoCONTPAQi -Instancias $instanciasDisponibles)
    if ($inventario.EmpresasPrincipales.Count -gt 0) {
        Write-Log -Mensaje "Empresas principales incluidas en el reporte: $($inventario.EmpresasPrincipales.Count)." -Nivel OK
    } elseif ($instanciasDisponibles.Count -gt 0) {
        Write-Log -Mensaje 'SQL esta disponible, pero no fue posible obtener empresas principales con los permisos actuales.' -Nivel WARN
    }

    Write-Log -Mensaje '[6/9] Midiendo almacenamiento...' -Nivel PROGRESS
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

    Write-Log -Mensaje '[7/9] Revisando red y resolucion local...' -Nivel PROGRESS
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

    Write-Log -Mensaje '[8/9] Revisando temporales y reinicio pendiente...' -Nivel PROGRESS
    $temporales = Get-TamanoCarpetasTemporalesCONTPAQi
    $inventario.TemporalesMB = $temporales.MB
    if ($temporales.MB -ge 2048) {
        Add-DiagnosticoHallazgo -Severidad MEDIA -Categoria 'Mantenimiento' -Titulo 'Temporales CONTPAQi elevados' `
            -Evidencia "$($temporales.MB) MB detectados en rutas temporales especificas." `
            -Consecuencia 'Puede aumentar el tiempo de carga y consumir almacenamiento necesario para otras operaciones.' `
            -Accion 'Usa la limpieza segura de Toolbox fuera de procesos activos y conserva evidencia si existe una incidencia.'
    }
    $estadoReinicio = Get-EstadoReinicioPendiente
    $inventario.ReinicioPendiente = $estadoReinicio.Estado
    if ($estadoReinicio.Pendiente) {
        $evidenciaReinicio = @($estadoReinicio.Razones | ForEach-Object { "$($_.Fuente): $($_.Detalle)" }) -join ' | '
        $accionesReinicio = @($estadoReinicio.Razones | ForEach-Object { $_.Accion } | Select-Object -Unique) -join ' '
        Add-DiagnosticoHallazgo -Severidad MEDIA -Categoria 'Windows' -Titulo 'Reinicio de Windows pendiente' `
            -Evidencia $evidenciaReinicio `
            -Consecuencia 'Servicios, actualizaciones o reparaciones pueden quedar aplicados parcialmente.' `
            -Accion $accionesReinicio
    } elseif ($estadoReinicio.OperacionesResiduales.Count -gt 0) {
        $detalleResidual = @($estadoReinicio.OperacionesResiduales | Select-Object -First 6 | ForEach-Object { "$($_.Responsable): $($_.Detalle)" }) -join ' | '
        Add-DiagnosticoHallazgo -Severidad INFORMATIVA -Categoria 'Windows' -Titulo 'Operaciones de archivo residuales; reinicio no confirmado' `
            -Evidencia $detalleResidual `
            -Consecuencia 'Esta señal puede permanecer despues de reiniciar y no reduce el puntaje de salud por si sola.' `
            -Accion $estadoReinicio.AccionResidual
    }

    Write-Log -Mensaje '[9/9] Correlacionando eventos recientes...' -Nivel PROGRESS
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
    $excel = $Diagnostico.Inventario.Excel
    $licenciaClase = if ($excel.Licencia -eq 'ACTIVADA') { 'ok-text' } elseif ($excel.Licencia -eq 'NO SE PUDO CONFIRMAR') { 'warning-text' } else { 'bad-text' }
    $arquitecturaClase = if ($excel.Arquitectura -eq '32 bits') { 'ok-text' } elseif ($excel.Arquitectura -eq '64 bits') { 'warning-text' } else { '' }
    $excelHtml = "<section class='office'><div class='office-title'>MICROSOFT EXCEL Y LICENCIA</div><div class='office-grid'><div><span>PRODUCTO</span><b>$((ConvertTo-HtmlSeguroCONTPAQi $excel.Producto))</b></div><div><span>VERSION</span><b>$((ConvertTo-HtmlSeguroCONTPAQi $excel.Version))</b></div><div><span>ARQUITECTURA</span><b class='$arquitecturaClase'>$((ConvertTo-HtmlSeguroCONTPAQi $excel.Arquitectura))</b></div><div><span>LICENCIA</span><b class='$licenciaClase'>$((ConvertTo-HtmlSeguroCONTPAQi $excel.Licencia))</b><small>$((ConvertTo-HtmlSeguroCONTPAQi $excel.TipoLicencia))</small></div><div><span>CONTPAQI</span><b class='$arquitecturaClase'>$((ConvertTo-HtmlSeguroCONTPAQi $excel.Compatibilidad))</b></div></div></section>"
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
    $empresasPrincipales = @($Diagnostico.Inventario.EmpresasPrincipales | Select-Object -First 5)
    $empresasHtml = (@($empresasPrincipales | ForEach-Object {
        $estadoClase = if ($_.Estado -eq 'ONLINE') { 'ok-text' } else { 'bad-text' }
        $usoClase = if ([double]$_.UsoDatosPct -ge 90) { 'bad-text' } elseif ([double]$_.UsoDatosPct -ge 80) { 'warning-text' } else { 'ok-text' }
        $usoBarra = [math]::Max(0, [math]::Min(100, [int][math]::Round([double]$_.UsoDatosPct)))
        $respaldoTexto = if ($_.UltimoRespaldo) { ([datetime]$_.UltimoRespaldo).ToString('dd/MM/yyyy HH:mm') } else { 'Sin registro o sin permiso' }
        $usadoGB = [math]::Round([double]$_.DatosUsadosMB / 1024, 2)
        $asignadoGB = [math]::Round([double]$_.DatosAsignadosMB / 1024, 2)
        $libreGB = [math]::Round([double]$_.DatosLibresMB / 1024, 2)
        $logGB = [math]::Round([double]$_.LogMB / 1024, 2)
        "<tr class='company-row'><td><b class='company-name'>$((ConvertTo-HtmlSeguroCONTPAQi $_.Nombre))</b><small class='company-meta'>Instancia: $((ConvertTo-HtmlSeguroCONTPAQi $_.Instancia))</small></td><td class='$estadoClase'>$((ConvertTo-HtmlSeguroCONTPAQi $_.Estado))</td><td><b>$usadoGB GB</b><small class='company-meta'>de $asignadoGB GB | Log $logGB GB ($($_.LogUsadoPct)%)</small></td><td>$libreGB GB</td><td><b class='$usoClase'>$($_.UsoDatosPct)%</b><div class='mini-bar'><i class='$usoClase' style='width:$usoBarra%'></i></div></td><td>$((ConvertTo-HtmlSeguroCONTPAQi $respaldoTexto))</td></tr>"
    })) -join ''
    if (-not $empresasHtml) {
        $empresasHtml = "<tr><td colspan='6'>No se obtuvo informacion de empresas. Ejecuta el diagnostico en el servidor SQL con un usuario de Windows que tenga acceso a las bases.</td></tr>"
    }
    $criticas = @($Diagnostico.Hallazgos | Where-Object Severidad -eq 'CRITICA').Count
    $altas = @($Diagnostico.Hallazgos | Where-Object Severidad -eq 'ALTA').Count
    $medias = @($Diagnostico.Hallazgos | Where-Object Severidad -eq 'MEDIA').Count
    $html = @"
<!doctype html><html lang='es'><head><meta charset='utf-8'><title>Diagnostico CONTPAQi</title><style>
@page{size:A4;margin:13mm;background:#07070b}*{box-sizing:border-box}html,body{margin:0;min-height:100%;background:#07070b;color:#e8eaf2;font:12px 'Segoe UI',Arial,sans-serif;-webkit-print-color-adjust:exact;print-color-adjust:exact}.page{min-height:260mm}.header{display:flex;align-items:center;padding:18px 20px;background:linear-gradient(135deg,#0d0d14,#171126);border:1px solid #2a2040;border-bottom:3px solid #7c3aed}.logo{width:54px;height:54px;object-fit:contain;margin-right:16px}.brand h1{font-size:23px;margin:0;color:#a78bfa;letter-spacing:.3px}.brand p{margin:4px 0 0;color:#8990a3}.version{margin-left:auto;color:#a78bfa;background:#211634;padding:7px 11px}.summary{display:grid;grid-template-columns:1.25fr 1fr 1fr 1fr;gap:10px;margin:13px 0}.card{background:#111119;border:1px solid #272735;padding:13px;min-height:76px}.label{font-size:9px;font-weight:700;color:#9298aa;letter-spacing:.8px}.value{font-size:20px;font-weight:800;margin-top:7px;color:#f3f4f6}.purple{color:#9b6cff}.red{color:#ff5d73}.amber{color:#ffbf47}.green{color:#38e08f}.meta{display:grid;grid-template-columns:1fr 1fr;gap:8px;background:#0e0e15;border:1px solid #252533;padding:12px;margin-bottom:14px}.meta div{color:#a7adbd}.meta b{color:#e8eaf2}.section-title{margin:18px 0 9px;padding:8px 10px;color:#a78bfa;background:#141020;border-left:4px solid #7c3aed;font-size:13px;letter-spacing:.4px;break-after:avoid}.finding{background:#101017;border:1px solid #272733;border-left:4px solid #6b7280;margin:0 0 9px;padding:11px 12px;break-inside:avoid}.finding.critical{border-left-color:#ff5d73}.finding.high{border-left-color:#ff8a5b}.finding.medium{border-left-color:#ffbf47}.finding.info,.finding.healthy{border-left-color:#38e08f}.finding-head{display:flex;gap:8px;align-items:center}.pill{font-size:8px;font-weight:800;padding:3px 7px;background:#2a2139;color:#c4b5fd}.category{font-size:9px;color:#9298aa}.finding-title{font-size:14px;font-weight:750;margin:7px 0 8px}.finding-grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px}.finding-grid>div{border-top:1px solid #292938;padding-top:7px}.finding-grid b{font-size:8px;color:#a78bfa}.finding-grid p{margin:4px 0 0;color:#c9cdd8;line-height:1.35}.office{background:#101017;border:1px solid #302841;margin:0 0 10px;break-inside:avoid}.office-title{padding:7px 10px;background:#181522;color:#a78bfa;font-size:9px;font-weight:800;letter-spacing:.5px}.office-grid{display:grid;grid-template-columns:1.35fr .75fr .75fr .9fr 1.15fr}.office-grid>div{padding:9px;border-right:1px solid #292938;min-width:0}.office-grid>div:last-child{border-right:0}.office-grid span{display:block;color:#858b9d;font-size:7px;font-weight:800;margin-bottom:4px}.office-grid b{display:block;font-size:9px;line-height:1.25;overflow-wrap:anywhere}.office-grid small{display:block;font-size:7px;margin-top:3px}.warning-text{color:#ffbf47}.two-cols{display:grid;grid-template-columns:1fr 1fr;gap:12px}.panel{background:#101017;border:1px solid #272733;padding:10px;break-inside:avoid}.panel h3{font-size:10px;color:#a78bfa;margin:0 0 7px}.panel ul{margin:0;padding-left:16px;font-size:9.5px;line-height:1.2}.panel li{margin:1px 0}.disk{margin:0 0 9px}.disk-row{display:flex;justify-content:space-between;margin-bottom:4px}.bar{height:7px;background:#292938}.bar i{display:block;height:100%;background:linear-gradient(90deg,#6d28d9,#a78bfa)}small{color:#858b9d}table{width:100%;border-collapse:collapse;background:#101017;font-size:9px}th{color:#a78bfa;background:#181522;text-align:left}th,td{border:1px solid #292938;padding:6px;vertical-align:top}td{color:#c9cdd8}.company-table{table-layout:fixed;font-size:7.8px}.company-table th,.company-table td{padding:4px;overflow-wrap:anywhere}.company-table th:nth-child(1){width:24%}.company-table th:nth-child(2){width:14%}.company-table th:nth-child(3){width:18%}.company-table th:nth-child(4){width:10%}.company-table th:nth-child(5){width:11%}.company-table th:nth-child(6){width:23%}.company-row{break-inside:avoid}.company-name{display:block;color:#e8eaf2;overflow-wrap:anywhere}.company-meta{display:block;margin-top:2px;font-size:6.5px;color:#858b9d;overflow-wrap:anywhere}.mini-bar{height:4px;margin-top:3px;background:#292938}.mini-bar i{display:block;height:100%;background:#38e08f}.mini-bar i.warning-text{background:#ffbf47}.mini-bar i.bad-text{background:#ff5d73}.ok-text{color:#38e08f}.bad-text{color:#ff5d73}.footer{margin-top:16px;padding-top:9px;border-top:1px solid #2a2040;color:#858b9d;font-size:9px;text-align:center}.note{background:#151122;border:1px solid #302346;padding:10px;color:#b9becb;line-height:1.4} @media print{html,body{background:#07070b}.page{min-height:auto}}
</style></head><body><main class='page'>
<header class='header'>$logoHtml<div class='brand'><h1>DIAGNOSTICO INTELIGENTE</h1><p>CONTPAQi Toolbox - Evaluacion tecnica de solo lectura</p></div><div class='version'>v$($Script:Version)</div></header>
<section class='summary'><div class='card'><div class='label'>PUNTAJE GENERAL</div><div class='value purple'>$($Diagnostico.Puntaje) / 100</div></div><div class='card'><div class='label'>ESTADO</div><div class='value'>$((ConvertTo-HtmlSeguroCONTPAQi $Diagnostico.Estado))</div></div><div class='card'><div class='label'>CRITICAS / ALTAS</div><div class='value red'>$criticas / $altas</div></div><div class='card'><div class='label'>ADVERTENCIAS</div><div class='value amber'>$medias</div></div></section>
<section class='meta'><div><b>Equipo:</b> $((ConvertTo-HtmlSeguroCONTPAQi $Diagnostico.Equipo))</div><div><b>Perfil:</b> $((ConvertTo-HtmlSeguroCONTPAQi $Diagnostico.Perfil))</div><div><b>Generado:</b> $($Diagnostico.Generado.ToString('dd/MM/yyyy HH:mm:ss'))</div><div><b>Duracion:</b> $($Diagnostico.DuracionSegundos) segundos</div><div><b>Sistema:</b> $((ConvertTo-HtmlSeguroCONTPAQi $Diagnostico.Inventario.Sistema))</div><div><b>Reinicio pendiente:</b> $((ConvertTo-HtmlSeguroCONTPAQi $Diagnostico.Inventario.ReinicioPendiente))</div></section>
<h2 class='section-title'>HALLAZGOS Y RECOMENDACIONES</h2>$hallazgosHtml
<h2 class='section-title'>SERVICIOS RELACIONADOS</h2><table><thead><tr><th>Servicio</th><th>Descripcion</th><th>Estado</th><th>Inicio</th></tr></thead><tbody>$serviciosHtml</tbody></table>
<h2 class='section-title'>INVENTARIO DEL EQUIPO</h2>$excelHtml
<h2 class='section-title'>5 EMPRESAS PRINCIPALES POR ESPACIO UTILIZADO</h2><div class='note'>Se muestran bases principales de usuario; las bases auxiliares de contenido, metadata y catalogos tecnicos no se cuentan como empresas.</div><table class='company-table'><thead><tr><th>Empresa / instancia</th><th>Estado</th><th>Datos y log</th><th>Disponible</th><th>Uso</th><th>Ultimo respaldo</th></tr></thead><tbody>$empresasHtml</tbody></table>
<section class='two-cols'><div class='panel'><h3>PRODUCTOS DETECTADOS</h3><ul>$productosHtml</ul></div><div class='panel'><h3>ALMACENAMIENTO</h3>$discosHtml</div></section>
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

function Get-NmapExecutableCONTPAQi {
    param([switch]$Actualizar)
    if (-not $Actualizar -and $Script:NmapCache -and $Script:NmapCacheFecha -and
        ((Get-Date) - $Script:NmapCacheFecha).TotalSeconds -lt 60) {
        return $Script:NmapCache
    }

    $candidatos = @()
    if ($env:CONTPAQI_NMAP_PATH) { $candidatos += $env:CONTPAQI_NMAP_PATH }
    $comandoNmap = Get-Command nmap.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($comandoNmap) { $candidatos += $comandoNmap.Source }
    $candidatos += @(
        (Join-Path $env:ProgramFiles 'Nmap\nmap.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Nmap\nmap.exe')
    )
    if ($PSScriptRoot) { $candidatos += Join-Path $PSScriptRoot 'Nmap\nmap.exe' }
    try {
        $baseAplicacion = [IO.Path]::GetDirectoryName([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
        if ($baseAplicacion) { $candidatos += Join-Path $baseAplicacion 'Nmap\nmap.exe' }
    } catch { }

    $resultado = $null
    foreach ($ruta in @($candidatos | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { continue }
        try {
            $salidaVersion = @(& $ruta --version 2>&1)
            if ($LASTEXITCODE -ne 0) { continue }
            $lineaVersion = [string]($salidaVersion | Where-Object { $_ -match '(?i)^Nmap version' } | Select-Object -First 1)
            $version = if ($lineaVersion -match '(?i)Nmap version\s+([^\s]+)') { $matches[1] } else { 'Detectada' }
            $resultado = [PSCustomObject]@{ Disponible = $true; Ruta = $ruta; Version = $version; Error = $null }
            break
        } catch { }
    }
    if (-not $resultado) {
        $resultado = [PSCustomObject]@{
            Disponible = $false; Ruta = $null; Version = $null
            Error = 'Nmap no esta instalado. Se utilizara el motor TCP integrado.'
        }
    }
    $Script:NmapCache = $resultado
    $Script:NmapCacheFecha = Get-Date
    return $resultado
}

function ConvertFrom-NmapXmlCONTPAQi {
    param(
        [Parameter(Mandatory)][string]$XmlText,
        [int[]]$PuertosEsperados = @()
    )
    if ([string]::IsNullOrWhiteSpace($XmlText)) { throw 'Nmap no genero contenido XML.' }

    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $settings.XmlResolver = $null
    $stringReader = New-Object IO.StringReader($XmlText)
    $reader = [Xml.XmlReader]::Create($stringReader, $settings)
    $documento = New-Object Xml.XmlDocument
    $documento.XmlResolver = $null
    try { $documento.Load($reader) } finally { $reader.Dispose(); $stringReader.Dispose() }

    $hostNode = $documento.SelectSingleNode('/nmaprun/host')
    $estadoHostNode = if ($hostNode) { $hostNode.SelectSingleNode('status') } else { $null }
    $resultados = New-Object System.Collections.Generic.List[object]
    if ($hostNode) {
        foreach ($puertoNode in @($hostNode.SelectNodes('ports/port'))) {
            $estadoNode = $puertoNode.SelectSingleNode('state')
            $servicioNode = $puertoNode.SelectSingleNode('service')
            $servicio = if ($servicioNode) { [string]$servicioNode.GetAttribute('name') } else { '' }
            $producto = if ($servicioNode) { [string]$servicioNode.GetAttribute('product') } else { '' }
            $version = if ($servicioNode) { [string]$servicioNode.GetAttribute('version') } else { '' }
            $extra = if ($servicioNode) { [string]$servicioNode.GetAttribute('extrainfo') } else { '' }
            $resultados.Add([PSCustomObject]@{
                Puerto = [int]$puertoNode.GetAttribute('portid')
                Protocolo = [string]$puertoNode.GetAttribute('protocol')
                Estado = $(if ($estadoNode) { [string]$estadoNode.GetAttribute('state') } else { 'unknown' })
                Razon = $(if ($estadoNode) { [string]$estadoNode.GetAttribute('reason') } else { 'sin-respuesta' })
                Servicio = $servicio; Producto = $producto; Version = $version; Extra = $extra
                Metodo = $(if ($servicioNode) { [string]$servicioNode.GetAttribute('method') } else { '' })
                Confianza = $(if ($servicioNode -and $servicioNode.HasAttribute('conf')) { [int]$servicioNode.GetAttribute('conf') } else { 0 })
            })
        }

        # Nmap puede resumir en extraports los estados repetidos. Como el
        # Toolbox conoce la lista solicitada, reconstruye cada puerto omitido.
        $presentes = @($resultados | Select-Object -ExpandProperty Puerto)
        $faltantes = @($PuertosEsperados | Where-Object { $_ -notin $presentes })
        $extras = @($hostNode.SelectNodes('ports/extraports'))
        if ($faltantes.Count -gt 0 -and $extras.Count -gt 0) {
            $extraPrincipal = $extras | Sort-Object { [int]$_.GetAttribute('count') } -Descending | Select-Object -First 1
            $razonExtraNode = $extraPrincipal.SelectSingleNode('extrareasons')
            foreach ($puerto in $faltantes) {
                $resultados.Add([PSCustomObject]@{
                    Puerto = [int]$puerto; Protocolo = 'tcp'; Estado = [string]$extraPrincipal.GetAttribute('state')
                    Razon = $(if ($razonExtraNode) { [string]$razonExtraNode.GetAttribute('reason') } else { 'sin-respuesta' })
                    Servicio = ''; Producto = ''; Version = ''; Extra = ''; Metodo = ''; Confianza = 0
                })
            }
        }
    }
    $runNode = $documento.SelectSingleNode('/nmaprun/runstats/finished')
    return [PSCustomObject]@{
        HostActivo = ($estadoHostNode -and $estadoHostNode.GetAttribute('state') -eq 'up')
        EstadoHost = $(if ($estadoHostNode) { [string]$estadoHostNode.GetAttribute('state') } else { 'unknown' })
        RazonHost = $(if ($estadoHostNode) { [string]$estadoHostNode.GetAttribute('reason') } else { 'sin-respuesta' })
        Puertos = @($resultados | Sort-Object Puerto)
        DuracionSegundos = $(if ($runNode -and $runNode.HasAttribute('elapsed')) { [double]::Parse($runNode.GetAttribute('elapsed'), [Globalization.CultureInfo]::InvariantCulture) } else { 0 })
    }
}

function Invoke-EscaneoPuertosNmapCONTPAQi {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][int[]]$Puertos,
        [switch]$SinVersiones,
        [ValidateRange(15, 180)][int]$TimeoutSegundos = 90
    )
    $nmap = Get-NmapExecutableCONTPAQi
    if (-not $nmap.Disponible) {
        return [PSCustomObject]@{ Disponible = $false; Correcto = $false; Motor = 'TCP integrado'; Puertos = @(); Error = $nmap.Error }
    }
    $hostSeguro = ConvertTo-HostServidorCONTPAQi -Valor $HostName
    if (-not $hostSeguro) {
        return [PSCustomObject]@{ Disponible = $true; Correcto = $false; Motor = 'Nmap'; Puertos = @(); Error = 'El host no es valido.' }
    }
    $listaPuertos = @($Puertos | Where-Object { $_ -ge 1 -and $_ -le 65535 } | Sort-Object -Unique)
    if ($listaPuertos.Count -eq 0) {
        return [PSCustomObject]@{ Disponible = $true; Correcto = $false; Motor = 'Nmap'; Puertos = @(); Error = 'No se proporcionaron puertos validos.' }
    }

    $directorioTemporal = Join-Path $env:TEMP 'CONTPAQiToolbox\Nmap'
    if (-not (Test-Path -LiteralPath $directorioTemporal)) { New-Item -ItemType Directory -Path $directorioTemporal -Force | Out-Null }
    $archivoXml = Join-Path $directorioTemporal ("scan_{0}.xml" -f [guid]::NewGuid().ToString('N'))
    try {
        $opcionesVersion = if ($SinVersiones) { '' } else { '-sV --version-light' }
        $argumentos = "-sT -Pn -n --reason $opcionesVersion -T4 --max-retries 2 --host-timeout 60s --no-stylesheet -p $($listaPuertos -join ',') -oX `"$archivoXml`" $hostSeguro"
        $proceso = Invoke-ProcessResponsive -FilePath $nmap.Ruta -ArgumentList $argumentos `
            -TimeoutSeconds $TimeoutSegundos -Activity "Nmap analizando $hostSeguro" -Hidden
        if (-not $proceso.Correcto -or $proceso.ExitCode -ne 0) {
            throw "Nmap termino con codigo $($proceso.ExitCode): $($proceso.Error)"
        }
        if (-not (Test-Path -LiteralPath $archivoXml -PathType Leaf)) { throw 'Nmap no genero el archivo XML esperado.' }
        $xmlText = Get-Content -LiteralPath $archivoXml -Raw -ErrorAction Stop
        $analisis = ConvertFrom-NmapXmlCONTPAQi -XmlText $xmlText -PuertosEsperados $listaPuertos
        return [PSCustomObject]@{
            Disponible = $true; Correcto = $true; Motor = "Nmap $($nmap.Version)"; RutaNmap = $nmap.Ruta
            HostActivo = $analisis.HostActivo; EstadoHost = $analisis.EstadoHost; RazonHost = $analisis.RazonHost
            Puertos = @($analisis.Puertos); DuracionSegundos = $analisis.DuracionSegundos; Error = $null
        }
    } catch {
        return [PSCustomObject]@{ Disponible = $true; Correcto = $false; Motor = "Nmap $($nmap.Version)"; Puertos = @(); Error = $_.Exception.Message }
    } finally {
        if (Test-Path -LiteralPath $archivoXml) { Remove-Item -LiteralPath $archivoXml -Force -ErrorAction SilentlyContinue }
    }
}

function Get-CatalogoPuertosTerminalCONTPAQi {
    return @(
        [PSCustomObject]@{ Puerto = 135;  Grupo = 'Administracion'; Uso = 'RPC / inventario administrativo' },
        [PSCustomObject]@{ Puerto = 445;  Grupo = 'Archivos'; Uso = 'SMB / carpetas compartidas' },
        [PSCustomObject]@{ Puerto = 3389; Grupo = 'Administracion'; Uso = 'Escritorio remoto' },
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

function Get-RequisitosTerminalCONTPAQi {
    $nombresProductos = @(Get-ProgramasInstalados | Select-Object -ExpandProperty DisplayName) -join ' | '
    $serviciosTerminal = @(Get-ServiciosTerminal)
    $requisitos = New-Object System.Collections.Generic.List[object]
    $requisitos.Add([PSCustomObject]@{ Grupo = 'Archivos SMB'; Puertos = @(445); Motivo = 'Acceso a carpetas compartidas del servidor' })

    if ($nombresProductos -match '(?i)Contabilidad|Bancos' -or @($serviciosTerminal | Where-Object { $_.Id -eq 'V4' }).Count) {
        $requisitos.Add([PSCustomObject]@{ Grupo = 'Contabilidad/Bancos'; Puertos = @(9047,9147); Motivo = 'Licenciamiento y AuthServer' })
    }
    if ($nombresProductos -match '(?i)Comercial|Factura') {
        $requisitos.Add([PSCustomObject]@{ Grupo = 'Comercial/Factura'; Puertos = @(9020,9120); Motivo = 'Licenciamiento y AuthServer' })
    }
    if ($nombresProductos -match '(?i)N[oó]mina' -or @($serviciosTerminal | Where-Object { $_.Id -eq 'NOMINAS' }).Count) {
        $requisitos.Add([PSCustomObject]@{ Grupo = 'Nominas'; Puertos = @(9005); Motivo = 'Licenciamiento de Nominas' })
    }
    if ($nombresProductos -match '(?i)XML' -or @($serviciosTerminal | Where-Object { $_.Id -match '^XML' }).Count) {
        $requisitos.Add([PSCustomObject]@{ Grupo = 'XML en Linea'; Puertos = @(9042); Motivo = 'Servicio XML en Linea' })
    }
    if ($nombresProductos -match '(?i)CONTPAQ|COMPAC' -or $serviciosTerminal.Count -gt 0) {
        $requisitos.Add([PSCustomObject]@{ Grupo = 'SACI/ADD'; Puertos = @(1099,1138,1139,1775,2003,9079,9080,9081,9082,9083,9084); Motivo = 'Servidor de aplicaciones y ADD' })
    }
    return @($requisitos | Group-Object Grupo | ForEach-Object { $_.Group[0] })
}

function Get-RutasServidorTerminalCONTPAQi {
    param([Parameter(Mandatory)][string]$HostName)
    $rutas = New-Object System.Collections.Generic.List[object]
    $unicas = @{}
    function Add-RutaTerminalInterna {
        param([string]$Ruta, [string]$Origen, [bool]$Obligatoria = $true)
        if ([string]::IsNullOrWhiteSpace($Ruta) -or $Ruta -notmatch '^\\\\([^\\]+)\\') { return }
        $servidorRuta = ConvertTo-HostServidorCONTPAQi -Valor $matches[1]
        $servidorObjetivo = ConvertTo-HostServidorCONTPAQi -Valor $HostName
        if ($servidorRuta -and $servidorObjetivo -and $servidorRuta -ne $servidorObjetivo) { return }
        $normalizada = $Ruta.TrimEnd('\')
        $clave = $normalizada.ToLowerInvariant()
        if (-not $unicas.ContainsKey($clave)) {
            $unicas[$clave] = $true
            $rutas.Add([PSCustomObject]@{ Ruta = $normalizada; Origen = $Origen; Obligatoria = $Obligatoria })
        }
    }

    try {
        foreach ($unidad in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=4' -ErrorAction SilentlyContinue)) {
            if ($unidad.ProviderName) { Add-RutaTerminalInterna -Ruta $unidad.ProviderName -Origen "Unidad $($unidad.DeviceID)" }
        }
    } catch { }
    if (Get-Command Get-SmbMapping -ErrorAction SilentlyContinue) {
        foreach ($mapeo in @(Get-SmbMapping -ErrorAction SilentlyContinue)) {
            if ($mapeo.RemotePath) { Add-RutaTerminalInterna -Ruta $mapeo.RemotePath -Origen "Mapeo SMB $($mapeo.LocalPath)" }
        }
    }

    # Recursos visibles para el usuario actual. Solo se agregan los que por
    # nombre corresponden a CONTPAQi/Compac para evitar probar carpetas ajenas.
    $codigoRecursos = @'
param([string]$ServerName)
$salida = @(& "$env:SystemRoot\System32\net.exe" view "\\$ServerName" 2>&1)
$recursos = @()
if ($LASTEXITCODE -eq 0) {
    foreach ($linea in $salida) {
        $texto = [string]$linea
        if ($texto -match '^\s*(.+?)\s{2,}(?:Disk|Disco)\s*(?:\s{2,}.*)?$') {
            $nombre = $matches[1].Trim()
            if ($nombre -match '(?i)CONTPAQ|COMPAC') { $recursos += $nombre }
        }
    }
}
[PSCustomObject]@{ Correcto = ($LASTEXITCODE -eq 0); Recursos = @($recursos | Select-Object -Unique); Error = $(if ($LASTEXITCODE -eq 0) { $null } else { ($salida -join ' ') }) }
'@
    $recursosWorker = Invoke-ResponsiveWorker -ScriptText $codigoRecursos -Arguments @($HostName) -TimeoutSeconds 15 -Activity "Enumerando recursos de $HostName"
    if ($recursosWorker.Correcto -and $recursosWorker.Resultado -and $recursosWorker.Resultado.Correcto) {
        foreach ($recurso in @($recursosWorker.Resultado.Recursos)) {
            Add-RutaTerminalInterna -Ruta "\\$HostName\$recurso" -Origen 'Recurso compartido visible'
        }
    }

    # Rutas UNC guardadas directamente por productos CONTPAQi.
    foreach ($raiz in @(
        'HKLM:\SOFTWARE\WOW6432Node\Computación en Acción, SA CV',
        'HKLM:\SOFTWARE\Computación en Acción, SA CV',
        'HKCU:\SOFTWARE\Computación en Acción, SA CV'
    )) {
        if (-not (Test-Path -LiteralPath $raiz)) { continue }
        foreach ($clave in @((Get-Item -LiteralPath $raiz -ErrorAction SilentlyContinue)) + @(Get-ChildItem -LiteralPath $raiz -Recurse -ErrorAction SilentlyContinue)) {
            if (-not $clave) { continue }
            foreach ($nombreValor in $clave.GetValueNames()) {
                $valor = $clave.GetValue($nombreValor)
                if ($valor -is [string] -and $valor -match '^\\\\[^\\]+\\[^\r\n]+') {
                    Add-RutaTerminalInterna -Ruta $valor -Origen "Registro: $nombreValor"
                }
            }
        }
    }

    # Si no hay rutas configuradas visibles, se prueban nombres comunes solo
    # como referencia; su ausencia no se considera una falla por si sola.
    if ($rutas.Count -eq 0) {
        foreach ($recursoComun in @('Compac','Compacw','CONTPAQi')) {
            Add-RutaTerminalInterna -Ruta "\\$HostName\$recursoComun" -Origen 'Nombre comun (opcional)' -Obligatoria $false
        }
    }
    return @($rutas | ForEach-Object { $_ })
}

function Test-AccesoRutaServidorCONTPAQi {
    param([Parameter(Mandatory)][string]$Ruta)
    $codigo = @'
param([string]$NetworkPath)
try {
    $item = Get-Item -LiteralPath $NetworkPath -Force -ErrorAction Stop
    if (-not $item.PSIsContainer) { throw 'La ruta no es una carpeta.' }
    $null = @(Get-ChildItem -LiteralPath $NetworkPath -Force -ErrorAction Stop | Select-Object -First 1)
    [PSCustomObject]@{ Existe = $true; Lectura = $true; Error = $null }
} catch [System.UnauthorizedAccessException] {
    [PSCustomObject]@{ Existe = $true; Lectura = $false; Error = $_.Exception.Message }
} catch {
    [PSCustomObject]@{ Existe = $false; Lectura = $false; Error = $_.Exception.Message }
}
'@
    $worker = Invoke-ResponsiveWorker -ScriptText $codigo -Arguments @($Ruta) -TimeoutSeconds 15 -Activity "Validando $Ruta"
    if (-not $worker.Correcto -or $worker.Timeout -or -not $worker.Resultado) {
        return [PSCustomObject]@{ Existe = $false; Lectura = $false; Error = $(if ($worker.Error) { $worker.Error } else { 'Tiempo agotado.' }) }
    }
    return $worker.Resultado
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
                if ($nombreValor -notmatch '^(?i)(NOMBRESERVIDOR|SERVERNAME|SERVIDOR|SERVIDORIP|IPSERVER|DIRECCIONIP|HOST)$') { continue }
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

    # Algunas versiones guardan los mismos archivos varios niveles debajo de
    # Compac/ProgramData. Se limita la cantidad para no congelar equipos lentos.
    $raicesConfiguracion = @(
        $raicesCompac,
        'C:\Compac', 'C:\Compacw',
        (Join-Path $env:ProgramData 'Compac'), (Join-Path $env:ProgramData 'CONTPAQi')
    ) | ForEach-Object { $_ } | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    $archivosConfiguracion = New-Object System.Collections.Generic.List[object]
    foreach ($raizConfiguracion in $raicesConfiguracion) {
        foreach ($nombreArchivo in @('CompacCliente.properties','Contpaq.properties','ConfigurationClient.config')) {
            foreach ($archivoConfig in @(Get-ChildItem -LiteralPath $raizConfiguracion -Filter $nombreArchivo -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 80)) {
                if (-not @($archivosConfiguracion.FullName).Contains($archivoConfig.FullName)) { $archivosConfiguracion.Add($archivoConfig) }
            }
        }
    }
    foreach ($archivoConfig in $archivosConfiguracion) {
        $textoConfig = Get-Content -LiteralPath $archivoConfig.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $textoConfig) { continue }
        foreach ($coincidencia in [regex]::Matches($textoConfig, '(?im)^\s*(?:servidor\.(?:direccionIP|nombre)|servidor|server|host)\s*[=:]\s*["'']?([^\s"''#;<>]+)')) {
            Add-CandidatoServidorCONTPAQi -Mapa $mapa -HostName $coincidencia.Groups[1].Value -Evidencia "$($archivoConfig.Name) en $($archivoConfig.Directory.Name)" -Puntos 70
        }
        foreach ($coincidencia in [regex]::Matches($textoConfig, '(?i)(?:value|address)\s*=\s*"(?:https?://)?([A-Za-z0-9][A-Za-z0-9._-]{0,252})(?::\d+)?(?:/[^" ]*)?"')) {
            Add-CandidatoServidorCONTPAQi -Mapa $mapa -HostName $coincidencia.Groups[1].Value -Evidencia "Endpoint en $($archivoConfig.Name)" -Puntos 55
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

    # DSN ODBC usados por instalaciones antiguas o integraciones locales.
    foreach ($rutaOdbc in @(
        'HKLM:\SOFTWARE\ODBC\ODBC.INI',
        'HKLM:\SOFTWARE\WOW6432Node\ODBC\ODBC.INI',
        'HKCU:\SOFTWARE\ODBC\ODBC.INI'
    )) {
        foreach ($dsn in @(Get-ChildItem -LiteralPath $rutaOdbc -ErrorAction SilentlyContinue)) {
            foreach ($nombreValor in @('Server','SERVER','Address','Network Address')) {
                $valorServidor = [string]$dsn.GetValue($nombreValor)
                if ($valorServidor) {
                    Add-CandidatoServidorCONTPAQi -Mapa $mapa -HostName $valorServidor -Evidencia "DSN ODBC $($dsn.PSChildName)" -Puntos 35
                }
            }
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
        return [PSCustomObject]@{
            Acceso = $true; AccesoParcial = $false; EsLocal = $true; Windows = $windows
            Programas = $programas; Servicios = $servicios; SQL = $sql; Error = $null
            Errores = @(); Fuentes = @('Inventario local'); PuertosAdministrativos = @()
        }
    }

    $rpc = Test-PuertoTCP -HostName $HostName -Port 135 -TimeoutMs 900
    $smb = Test-PuertoTCP -HostName $HostName -Port 445 -TimeoutMs 900
    $winrmHttp = Test-PuertoTCP -HostName $HostName -Port 5985 -TimeoutMs 700
    $winrmHttps = Test-PuertoTCP -HostName $HostName -Port 5986 -TimeoutMs 700
    $puertosAdministrativos = @()
    if ($rpc.Abierto) { $puertosAdministrativos += 135 }
    if ($smb.Abierto) { $puertosAdministrativos += 445 }
    if ($winrmHttp.Abierto) { $puertosAdministrativos += 5985 }
    if ($winrmHttps.Abierto) { $puertosAdministrativos += 5986 }

    $errores = New-Object System.Collections.Generic.List[string]
    $fuentes = New-Object System.Collections.Generic.List[string]
    $windows = $null
    $programas = @()
    $servicios = @()
    $sql = @()
    $sesionCim = $null

    try {
        # DCOM suele estar disponible aun cuando WinRM no esta configurado. Si
        # no funciona, se intenta WSMan. El inventario no depende de una sola via.
        if ($rpc.Abierto) {
            try {
                $opcionesCim = New-CimSessionOption -Protocol Dcom
                $sesionCim = New-CimSession -ComputerName $HostName -SessionOption $opcionesCim -OperationTimeoutSec 8 -ErrorAction Stop
                $fuentes.Add('CIM/DCOM')
            } catch { $errores.Add("CIM/DCOM: $($_.Exception.Message)") }
        }
        if (-not $sesionCim -and ($winrmHttp.Abierto -or $winrmHttps.Abierto)) {
            try {
                $sesionCim = New-CimSession -ComputerName $HostName -OperationTimeoutSec 8 -ErrorAction Stop
                $fuentes.Add('CIM/WSMan')
            } catch { $errores.Add("CIM/WSMan: $($_.Exception.Message)") }
        }

        if ($rpc.Abierto -or $smb.Abierto) {
            try {
                $windows = Get-DatosWindowsRemotosCONTPAQi -HostName $HostName
                if ($windows) { $fuentes.Add('Registro remoto de Windows') }
            } catch { $errores.Add("Windows/Registro remoto: $($_.Exception.Message)") }
            try {
                $programas = @(Get-ProgramasRemotosCONTPAQi -HostName $HostName)
                $fuentes.Add('Programas/Registro remoto')
            } catch { $errores.Add("Programas instalados: $($_.Exception.Message)") }
            try {
                $servicios = @(Get-ServiciosRemotosCONTPAQi -HostName $HostName)
                if ($servicios.Count -gt 0) { $fuentes.Add('Servicios remotos') }
            } catch { $errores.Add("Servicios/Registro remoto: $($_.Exception.Message)") }
            try {
                $sql = @(Get-InstanciasSQLRemotasCONTPAQi -HostName $HostName)
                if ($sql.Count -gt 0) { $fuentes.Add('Instancias SQL/Registro remoto') }
            } catch { $errores.Add("Instancias SQL: $($_.Exception.Message)") }
        } else {
            $errores.Add('RPC/SMB no disponibles; el Registro remoto no se pudo consultar.')
        }

        # Recuperacion parcial por CIM: una clase fallida no elimina las demas.
        if ($sesionCim) {
            if (-not $windows) {
                try {
                    $soCim = Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $sesionCim -OperationTimeoutSec 10 -ErrorAction Stop
                    $windows = [PSCustomObject]@{ Producto = $soCim.Caption; Version = $soCim.Version; Compilacion = $soCim.BuildNumber }
                } catch { $errores.Add("Windows/CIM: $($_.Exception.Message)") }
            }
            if ($servicios.Count -eq 0) {
                try {
                    $servicios = @(Get-CimInstance -ClassName Win32_Service -CimSession $sesionCim -OperationTimeoutSec 12 -ErrorAction Stop | Where-Object {
                        $_.Name -eq 'MSSQLSERVER' -or $_.Name -match '^MSSQL\$[^$]+$' -or
                        "$($_.Name) $($_.DisplayName) $($_.PathName)" -match '(?i)CONTPAQ|COMPAC|SACI|APPKEY|XMLSERVICE|AUTHSERVER|SQLSERVERAGENT|SQLBROWSER|SQLWRITER'
                    } | ForEach-Object {
                        $esMotor = ($_.Name -eq 'MSSQLSERVER' -or $_.Name -match '^MSSQL\$[^$]+$')
                        [PSCustomObject]@{
                            Nombre = $_.Name; DisplayName = $_.DisplayName; Estado = $_.State
                            Inicio = $_.StartMode; ImagePath = $_.PathName; EsMotorSQL = $esMotor
                            Fabricante = Get-FabricanteServicioCONTPAQi -Nombre $_.Name -DisplayName $_.DisplayName -Ruta $_.PathName -EsMotorSQL $esMotor
                        }
                    } | Sort-Object Nombre -Unique)
                    if ($servicios.Count -gt 0) { $fuentes.Add('Servicios/CIM') }
                } catch { $errores.Add("Servicios/CIM: $($_.Exception.Message)") }
            }
        } elseif (-not $rpc.Abierto -and -not $winrmHttp.Abierto -and -not $winrmHttps.Abierto) {
            $errores.Add('No hay un canal de administracion CIM disponible (135, 5985 o 5986).')
        }

        # Incluso sin acceso al registro SQL, los nombres de servicio permiten
        # entregar las instancias detectadas en vez de una seccion vacia.
        if ($sql.Count -eq 0) {
            foreach ($motor in @($servicios | Where-Object { $_.EsMotorSQL })) {
                $nombreServicio = [string]$motor.Nombre
                $instancia = if ($nombreServicio -eq 'MSSQLSERVER') { $HostName } else { "$HostName\$($nombreServicio.Substring(6))" }
                $sql += [PSCustomObject]@{
                    Instancia = $instancia; Servicio = $nombreServicio
                    Version = 'No consultada'; Edicion = 'Detectada por servicio'
                }
            }
            if ($sql.Count -gt 0) { $fuentes.Add('Instancias inferidas por servicios') }
        }
    } finally {
        if ($sesionCim) { Remove-CimSession -CimSession $sesionCim -ErrorAction SilentlyContinue }
    }

    $hayDatos = ($null -ne $windows -or $programas.Count -gt 0 -or $servicios.Count -gt 0 -or $sql.Count -gt 0)
    $mensajeError = if ($errores.Count -gt 0) { $errores -join ' | ' } else { $null }
    return [PSCustomObject]@{
        Acceso = $hayDatos; AccesoParcial = ($hayDatos -and $errores.Count -gt 0); EsLocal = $false
        Windows = $windows; Programas = @($programas); Servicios = @($servicios); SQL = @($sql)
        Error = $mensajeError; Errores = @($errores); Fuentes = @($fuentes | Select-Object -Unique)
        PuertosAdministrativos = @($puertosAdministrativos)
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
        Write-Log -Mensaje 'Usa una cuenta administradora del servidor y habilita Registro remoto, RPC/DCOM o WinRM, o ejecuta el Toolbox directamente en ese servidor.' -Nivel INFO
        if (1433 -in $PuertosAbiertos) {
            $sqlDirecto = Test-ConexionSQLLocal -Instancia $HostName -TimeoutSegundos 4
            if ($sqlDirecto.Correcto) {
                Write-Log -Mensaje "SQL confirmado por conexion: $($sqlDirecto.Servidor) | Version $($sqlDirecto.Version)" -Nivel OK
            } else {
                Write-Log -Mensaje 'SQL responde por red, pero la cuenta actual no pudo consultar su version.' -Nivel INFO
            }
        }
    } else {
        $mensajeAcceso = if ($inventario.EsLocal) { 'Inventario local disponible.' } elseif ($inventario.AccesoParcial) { 'Inventario remoto parcial: se conservaron todas las fuentes que si respondieron.' } else { 'Inventario remoto autorizado correctamente.' }
        Write-Log -Mensaje $mensajeAcceso -Nivel $(if ($inventario.AccesoParcial) { 'WARN' } else { 'OK' })
        if (@($inventario.Fuentes).Count -gt 0) {
            Write-Log -Mensaje "Fuentes disponibles: $(@($inventario.Fuentes) -join ', ')." -Nivel INFO
        }
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
        foreach ($errorFuente in @($inventario.Errores)) {
            if ([string]::IsNullOrWhiteSpace([string]$errorFuente)) { continue }
            $detalleFuente = ([string]$errorFuente -replace '[\r\n]+', ' ' -replace '\s+', ' ').Trim()
            if ($detalleFuente.Length -gt 300) { $detalleFuente = $detalleFuente.Substring(0, 300) + '...' }
            Write-Log -Mensaje "Fuente no disponible: $detalleFuente" -Nivel WARN
        }
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
    $errores = New-Object System.Collections.Generic.List[string]
    $protocolo = 'Local'
    $argumentosCim = @{ ErrorAction = 'Stop' }
    try {
        if (-not (Test-HostCONTPAQiEsLocal -HostName $HostName)) {
            try {
                $opcionesCim = New-CimSessionOption -Protocol Dcom
                $sesionCim = New-CimSession -ComputerName $HostName -SessionOption $opcionesCim -OperationTimeoutSec 8 -ErrorAction Stop
                $protocolo = 'DCOM'
            } catch {
                $errores.Add("Sesion DCOM: $($_.Exception.Message)")
                try {
                    $sesionCim = New-CimSession -ComputerName $HostName -OperationTimeoutSec 8 -ErrorAction Stop
                    $protocolo = 'WSMan'
                } catch { $errores.Add("Sesion WSMan: $($_.Exception.Message)") }
            }
            if (-not $sesionCim) {
                return [PSCustomObject]@{
                    Acceso = $false; AccesoParcial = $false; Error = ($errores -join ' | '); Errores = @($errores)
                    Protocolo = 'No disponible'; Nombre = $HostName; Dominio = ''; Fabricante = ''; Modelo = ''; RAMGB = 0
                    SistemaOperativo = ''; VersionSO = ''; BuildSO = ''; UltimoArranque = $null
                    Procesadores = @(); Discos = @(); Red = @(); Recursos = @()
                }
            }
            $argumentosCim.CimSession = $sesionCim
        }

        $so = $null; $equipo = $null; $procesadores = @(); $discos = @(); $red = @(); $recursos = @()
        try { $so = Get-CimInstance -ClassName Win32_OperatingSystem @argumentosCim } catch { $errores.Add("Sistema operativo: $($_.Exception.Message)") }
        try { $equipo = Get-CimInstance -ClassName Win32_ComputerSystem @argumentosCim } catch { $errores.Add("Equipo/RAM: $($_.Exception.Message)") }
        try { $procesadores = @(Get-CimInstance -ClassName Win32_Processor @argumentosCim) } catch { $errores.Add("Procesadores: $($_.Exception.Message)") }
        try { $discos = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' @argumentosCim) } catch { $errores.Add("Discos: $($_.Exception.Message)") }
        try { $red = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' @argumentosCim) } catch { $errores.Add("Adaptadores de red: $($_.Exception.Message)") }
        try { $recursos = @(Get-CimInstance -ClassName Win32_Share @argumentosCim | Where-Object { $_.Name -notmatch '\$$' } | Select-Object -First 30) } catch { $errores.Add("Recursos compartidos: $($_.Exception.Message)") }

        $hayDatos = ($null -ne $so -or $null -ne $equipo -or $procesadores.Count -gt 0 -or $discos.Count -gt 0 -or $red.Count -gt 0 -or $recursos.Count -gt 0)
        return [PSCustomObject]@{
            Acceso = $hayDatos; AccesoParcial = ($hayDatos -and $errores.Count -gt 0)
            Error = $(if ($errores.Count) { $errores -join ' | ' } else { $null }); Errores = @($errores); Protocolo = $protocolo
            Nombre = $(if ($equipo) { $equipo.Name } else { $HostName })
            Dominio = $(if ($equipo) { $equipo.Domain } else { '' })
            Fabricante = $(if ($equipo) { $equipo.Manufacturer } else { '' })
            Modelo = $(if ($equipo) { $equipo.Model } else { '' })
            RAMGB = $(if ($equipo) { [math]::Round([double]$equipo.TotalPhysicalMemory / 1GB, 1) } else { 0 })
            SistemaOperativo = $(if ($so) { $so.Caption } else { '' })
            VersionSO = $(if ($so) { $so.Version } else { '' })
            BuildSO = $(if ($so) { $so.BuildNumber } else { '' })
            UltimoArranque = $(if ($so) { $so.LastBootUpTime } else { $null })
            Procesadores = @($procesadores); Discos = @($discos); Red = @($red); Recursos = @($recursos)
        }
    } catch {
        $errores.Add($_.Exception.Message)
        return [PSCustomObject]@{
            Acceso = $false; AccesoParcial = $false; Error = ($errores -join ' | '); Errores = @($errores)
            Protocolo = $protocolo; Nombre = $HostName; Dominio = ''; Fabricante = ''; Modelo = ''; RAMGB = 0
            SistemaOperativo = ''; VersionSO = ''; BuildSO = ''; UltimoArranque = $null
            Procesadores = @(); Discos = @(); Red = @(); Recursos = @()
        }
    } finally {
        if ($sesionCim) { Remove-CimSession -CimSession $sesionCim -ErrorAction SilentlyContinue }
    }
}

function Invoke-DiagnosticoTerminalServidorCONTPAQi {
    Write-Encabezado -Titulo 'VALIDACION TERMINAL HACIA SERVIDOR' -Subtitulo 'DNS + puertos + firewall + carpetas + licencias locales' -Color $Script:ColorTerminal
    Write-Log -Mensaje 'Diagnostico de solo lectura desde esta terminal. No se modificaran carpetas, servicios ni configuraciones.' -Nivel INFO
    $inicio = Get-Date
    $incidencias = 0
    $advertencias = 0

    $hostObjetivo = Select-ServidorObjetivoCONTPAQi
    if ([string]::IsNullOrWhiteSpace($hostObjetivo)) {
        Write-Log -Mensaje 'Validacion cancelada.' -Nivel WARN
        return
    }
    $hostObjetivo = ConvertTo-HostServidorCONTPAQi -Valor $hostObjetivo
    if (-not $hostObjetivo) {
        Write-Log -Mensaje 'El nombre o IP del servidor no es valido.' -Nivel ERROR
        return
    }

    Write-SeccionMenu -Titulo '1. IDENTIDAD Y RESOLUCION' -Color 'Cyan'
    $direcciones = @(Resolve-HostCONTPAQi -HostName $hostObjetivo)
    if ($direcciones.Count -gt 0) {
        Write-Log -Mensaje "Servidor $hostObjetivo resuelto como $($direcciones -join ', ')." -Nivel OK
    } elseif ($hostObjetivo -match '^\d{1,3}(?:\.\d{1,3}){3}$') {
        Write-Log -Mensaje "Se utilizara directamente la IP $hostObjetivo." -Nivel OK
    } else {
        $incidencias++
        Write-Log -Mensaje "DNS no puede resolver $hostObjetivo. Revisa DNS, VPN, sufijo de dominio o el nombre configurado en CONTPAQi." -Nivel ERROR
    }

    Write-SeccionMenu -Titulo '2. PUERTOS NECESARIOS DESDE ESTA TERMINAL' -Color 'Magenta'
    $catalogo = @(Get-CatalogoPuertosTerminalCONTPAQi)
    $requisitos = @(Get-RequisitosTerminalCONTPAQi)
    if ($requisitos.Count -eq 1) {
        $advertencias++
        Write-Log -Mensaje 'No se identifico con precision el producto CONTPAQi instalado; se revisara el catalogo completo y SMB.' -Nivel WARN
    } else {
        foreach ($requisito in $requisitos) {
            Write-Log -Mensaje "Requisito detectado: $($requisito.Grupo) | $($requisito.Motivo) | TCP $($requisito.Puertos -join '/')." -Nivel INFO
        }
    }

    $resultadosPuertos = @()
    $nmapInfo = Get-NmapExecutableCONTPAQi
    $nmapScan = $null
    if ($nmapInfo.Disponible) {
        $nmapScan = Invoke-EscaneoPuertosNmapCONTPAQi -HostName $hostObjetivo `
            -Puertos @($catalogo | Select-Object -ExpandProperty Puerto) -TimeoutSegundos 90
    }
    if ($nmapScan -and $nmapScan.Correcto) {
        Write-Log -Mensaje "Motor: $($nmapScan.Motor) | $($nmapScan.DuracionSegundos) segundos." -Nivel OK
        $resultadosPuertos = @($nmapScan.Puertos)
        foreach ($puerto in $resultadosPuertos) {
            $catalogado = $catalogo | Where-Object Puerto -eq $puerto.Puerto | Select-Object -First 1
            $uso = if ($catalogado) { $catalogado.Uso } else { 'Servicio no catalogado' }
            $identidad = @($puerto.Servicio,$puerto.Producto,$puerto.Version) | Where-Object { $_ }
            $detalleIdentidad = if ($identidad.Count) { " | $($identidad -join ' ')" } else { '' }
            $nivel = if ($puerto.Estado -eq 'open') { 'OK' } elseif ($puerto.Estado -match 'filtered') { 'WARN' } else { 'INFO' }
            Write-Log -Mensaje "TCP $($puerto.Puerto) $($puerto.Estado.ToUpper()) | $uso | $($puerto.Razon)$detalleIdentidad" -Nivel $nivel
        }
    } else {
        $motivo = if ($nmapScan) { $nmapScan.Error } else { $nmapInfo.Error }
        Write-Log -Mensaje "Nmap no disponible: $motivo" -Nivel INFO
        Write-Log -Mensaje 'Motor TCP integrado activo; confirma aperturas, pero un puerto sin respuesta puede estar cerrado o filtrado.' -Nivel INFO
        foreach ($item in $catalogo) {
            $prueba = Test-PuertoTCP -HostName $hostObjetivo -Port $item.Puerto -TimeoutMs 500
            $resultadosPuertos += [PSCustomObject]@{
                Puerto = $item.Puerto; Protocolo = 'tcp'; Estado = $(if ($prueba.Abierto) { 'open' } else { 'unknown' })
                Razon = $prueba.Detalle; Servicio = ''; Producto = ''; Version = ''; Extra = ''; Metodo = 'TCP'; Confianza = 0
            }
            if ($prueba.Abierto) { Write-Log -Mensaje "TCP $($item.Puerto) ABIERTO | $($item.Uso) | $($prueba.Milisegundos) ms" -Nivel OK }
            Refresh-Log
        }
    }

    foreach ($requisito in $requisitos) {
        $estadosGrupo = @($resultadosPuertos | Where-Object { $_.Puerto -in $requisito.Puertos })
        $abiertosGrupo = @($estadosGrupo | Where-Object Estado -eq 'open')
        if ($abiertosGrupo.Count -gt 0) {
            Write-Log -Mensaje "[$($requisito.Grupo)] Disponible por TCP $($abiertosGrupo.Puerto -join ', ')." -Nivel OK
            continue
        }
        $filtrados = @($estadosGrupo | Where-Object { $_.Estado -match 'filtered' })
        $incidencias++
        if ($filtrados.Count -gt 0) {
            Write-Log -Mensaje "[$($requisito.Grupo)] Posible bloqueo de firewall/VPN/ACL en TCP $($filtrados.Puerto -join ', ')." -Nivel ERROR
        } else {
            $estadosTexto = @($estadosGrupo | ForEach-Object { "$($_.Puerto)=$($_.Estado)" }) -join ', '
            Write-Log -Mensaje "[$($requisito.Grupo)] No hay un puerto disponible ($estadosTexto). Valida servicio, puerto configurado y firewall del servidor." -Nivel ERROR
        }
    }

    Write-SeccionMenu -Titulo '3. CARPETAS Y RECURSOS COMPARTIDOS' -Color 'Yellow'
    $smbDisponible = @($resultadosPuertos | Where-Object { $_.Puerto -eq 445 -and $_.Estado -eq 'open' }).Count -gt 0
    $rutasServidor = if ($smbDisponible) { @(Get-RutasServidorTerminalCONTPAQi -HostName $hostObjetivo) } else { @() }
    $rutasAccesibles = 0
    $rutasObligatorias = @($rutasServidor | Where-Object Obligatoria)
    if (-not $smbDisponible) {
        Write-Log -Mensaje 'SMB TCP 445 no esta disponible; se omiten esperas adicionales sobre rutas UNC hasta corregir conectividad/firewall.' -Nivel WARN
    } else {
        foreach ($ruta in $rutasServidor) {
            $pruebaRuta = Test-AccesoRutaServidorCONTPAQi -Ruta $ruta.Ruta
            if ($pruebaRuta.Lectura) {
                $rutasAccesibles++
                Write-Log -Mensaje "Lectura correcta: $($ruta.Ruta) | $($ruta.Origen)." -Nivel OK
            } elseif ($ruta.Obligatoria) {
                $incidencias++
                Write-Log -Mensaje "Sin acceso de lectura: $($ruta.Ruta) | $($pruebaRuta.Error)" -Nivel ERROR
            } else {
                Write-Log -Mensaje "Recurso opcional no disponible: $($ruta.Ruta)." -Nivel INFO
            }
        }
    }
    if ($smbDisponible -and $rutasObligatorias.Count -eq 0 -and $rutasAccesibles -eq 0) {
        $advertencias++
        Write-Log -Mensaje 'No se encontro una ruta compartida configurada o accesible. Confirma con el servidor cuál recurso usa esta terminal.' -Nivel WARN
    }
    Write-Log -Mensaje 'La prueba valida existencia y lectura. Por seguridad no crea archivos para probar escritura.' -Nivel INFO

    Write-SeccionMenu -Titulo '4. SERVICIOS LOCALES DE LA TERMINAL' -Color 'Green'
    $serviciosTerminal = @(Get-ServiciosTerminal)
    if ($serviciosTerminal.Count -eq 0) {
        $advertencias++
        Write-Log -Mensaje 'No se detectaron AuthServer/licencias locales; algunos productos pueden no requerirlos en esta estación.' -Nivel WARN
    } else {
        foreach ($item in $serviciosTerminal) {
            $servicio = Get-Service -Name $item.Servicio.Name -ErrorAction SilentlyContinue
            if ($servicio -and $servicio.Status -eq 'Running') {
                Write-Log -Mensaje "$($item.Etiqueta): activo." -Nivel OK
            } else {
                $incidencias++
                Write-Log -Mensaje "$($item.Etiqueta): detenido o no disponible." -Nivel ERROR
            }
        }
    }

    $duracion = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    $estadoFinal = if ($incidencias -eq 0 -and $advertencias -eq 0) { 'TERMINAL LISTA' } elseif ($incidencias -eq 0) { 'TERMINAL CON OBSERVACIONES' } else { 'TERMINAL NO LISTA' }
    $nivelFinal = if ($incidencias -gt 0) { 'ERROR' } elseif ($advertencias -gt 0) { 'WARN' } else { 'OK' }
    Write-Separador -Color $(if ($incidencias -gt 0) { $Script:ColorError } elseif ($advertencias -gt 0) { $Script:ColorAdvertencia } else { $Script:ColorExito })
    Write-Log -Mensaje "$estadoFinal | $incidencias incidencia(s) | $advertencias observacion(es) | $duracion s | Servidor $hostObjetivo" -Nivel $nivelFinal
    if ($incidencias -gt 0) { Write-Log -Mensaje 'Corrige los puntos en rojo y vuelve a ejecutar esta validacion antes de abrir CONTPAQi.' -Nivel INFO }
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
        Write-Log -Mensaje "DNS no pudo resolver $hostObjetivo; se continuara usando el nombre/IP capturado para no perder el resto del diagnostico." -Nivel WARN
    } else {
        $ipv4 = @($direcciones | Where-Object { $_ -match '^\d{1,3}(?:\.\d{1,3}){3}$' })
        Write-Log -Mensaje "Servidor: $hostObjetivo | IP: $(if ($ipv4.Count) { $ipv4 -join ', ' } else { $direcciones[0] })" -Nivel OK
    }

    $catalogoPuertos = @(Get-CatalogoPuertosTerminalCONTPAQi)
    $puertosAbiertos = @()
    $motorNmap = Get-NmapExecutableCONTPAQi
    $escaneoNmap = $null
    if ($motorNmap.Disponible) {
        Write-Log -Mensaje "Motor avanzado disponible: Nmap $($motorNmap.Version). Analizando estados, razones y servicios..." -Nivel PROGRESS
        $escaneoNmap = Invoke-EscaneoPuertosNmapCONTPAQi -HostName $hostObjetivo `
            -Puertos @($catalogoPuertos | Select-Object -ExpandProperty Puerto) -TimeoutSegundos 90
    }
    if ($escaneoNmap -and $escaneoNmap.Correcto) {
        $estadosNmap = @($escaneoNmap.Puertos)
        foreach ($item in $catalogoPuertos) {
            $resultadoPuerto = $estadosNmap | Where-Object Puerto -eq $item.Puerto | Select-Object -First 1
            if (-not $resultadoPuerto) {
                Write-Log -Mensaje "TCP $($item.Puerto) sin clasificacion | $($item.Uso)" -Nivel INFO
                continue
            }
            $identidadServicio = @($resultadoPuerto.Servicio, $resultadoPuerto.Producto, $resultadoPuerto.Version, $resultadoPuerto.Extra) |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            $detalleServicio = if ($identidadServicio.Count) { " | Detectado: $($identidadServicio -join ' ')" } else { '' }
            $detalle = "TCP $($item.Puerto) $($resultadoPuerto.Estado.ToUpper()) | $($item.Uso) | Razon: $($resultadoPuerto.Razon)$detalleServicio"
            switch -Regex ($resultadoPuerto.Estado) {
                '^open$' {
                    $puertosAbiertos += $item.Puerto
                    Write-Log -Mensaje $detalle -Nivel OK
                }
                '^closed$' { Write-Log -Mensaje $detalle -Nivel INFO }
                'filtered' { Write-Log -Mensaje $detalle -Nivel WARN }
                '^unfiltered$' { Write-Log -Mensaje $detalle -Nivel WARN }
                default { Write-Log -Mensaje $detalle -Nivel INFO }
            }
        }
        $puertosFiltrados = @($estadosNmap | Where-Object { $_.Estado -match 'filtered' } | Select-Object -ExpandProperty Puerto -Unique)
        $puertosCerrados = @($estadosNmap | Where-Object Estado -eq 'closed' | Select-Object -ExpandProperty Puerto -Unique)
        Write-Log -Mensaje "Nmap finalizado en $($escaneoNmap.DuracionSegundos) s: $($puertosAbiertos.Count) abierto(s), $($puertosCerrados.Count) cerrado(s), $($puertosFiltrados.Count) filtrado(s)." -Nivel $(if ($puertosFiltrados.Count) { 'WARN' } else { 'OK' })
        if ($puertosFiltrados.Count) {
            Write-Log -Mensaje "Posible bloqueo de firewall/ACL en: $($puertosFiltrados -join ', '). 'Filtrado' describe lo observado desde este equipo; revisa firewall local, perimetral, VPN y reglas de red." -Nivel WARN
        }
        if ($puertosCerrados.Count) {
            Write-Log -Mensaje "Puertos cerrados: $($puertosCerrados -join ', '). El servidor es alcanzable, pero no existe un servicio escuchando en esos puertos." -Nivel INFO
        }
    } else {
        $motivoFallback = if ($escaneoNmap) { $escaneoNmap.Error } else { $motorNmap.Error }
        Write-Log -Mensaje "Nmap no disponible para este analisis: $motivoFallback" -Nivel INFO
        Write-Log -Mensaje 'Usando comprobacion TCP integrada. Este metodo confirma aperturas, pero no siempre diferencia cerrado de filtrado.' -Nivel INFO
        foreach ($item in $catalogoPuertos) {
            $prueba = Test-PuertoTCP -HostName $hostObjetivo -Port $item.Puerto -TimeoutMs 350
            if ($prueba.Abierto) {
                $puertosAbiertos += $item.Puerto
                Write-Log -Mensaje "TCP $($item.Puerto) abierto | $($item.Uso) | $($prueba.Milisegundos) ms" -Nivel OK
            }
            Refresh-Log
        }
        Write-Log -Mensaje "Puertos confirmados: $($puertosAbiertos.Count) de $($catalogoPuertos.Count)." -Nivel $(if ($puertosAbiertos.Count) { 'OK' } else { 'WARN' })
        $sinRespuesta = @($catalogoPuertos | Where-Object { $_.Puerto -notin $puertosAbiertos } | Select-Object -ExpandProperty Puerto)
        if ($sinRespuesta.Count -gt 0) {
            Write-Log -Mensaje "Sin respuesta TCP: $($sinRespuesta -join ', '). Esto no confirma una falla si el producto correspondiente no esta instalado." -Nivel INFO
        }
    }

    Write-SeccionMenu -Titulo '2. SISTEMAS, SERVICIOS E INSTANCIAS' -Color 'Magenta'
    $inventario = Get-InventarioServidorCONTPAQi -HostName $hostObjetivo
    Write-InventarioServidorCONTPAQi -HostName $hostObjetivo -PuertosAbiertos $puertosAbiertos -InventarioDetectado $inventario

    Write-SeccionMenu -Titulo '3. INFRAESTRUCTURA DEL SERVIDOR' -Color 'Yellow'
    $infraestructura = Get-InfraestructuraServidorCONTPAQi -HostName $hostObjetivo
    if ($infraestructura.Acceso) {
        Write-Log -Mensaje "Canal de inventario: $($infraestructura.Protocolo)$(if ($infraestructura.AccesoParcial) { ' | informacion parcial' } else { '' })." -Nivel $(if ($infraestructura.AccesoParcial) { 'WARN' } else { 'OK' })
        Write-Log -Mensaje "Equipo: $($infraestructura.Nombre)$(if ($infraestructura.Dominio) { " | Dominio: $($infraestructura.Dominio)" } else { '' })" -Nivel OK
        if ($infraestructura.Fabricante -or $infraestructura.Modelo -or $infraestructura.RAMGB) {
            Write-Log -Mensaje "Hardware: $($infraestructura.Fabricante) $($infraestructura.Modelo) | RAM: $($infraestructura.RAMGB) GB" -Nivel INFO
        }
        if ($infraestructura.SistemaOperativo) {
            Write-Log -Mensaje "Windows: $($infraestructura.SistemaOperativo) | $($infraestructura.VersionSO) | Build $($infraestructura.BuildSO)" -Nivel INFO
        }
        if ($infraestructura.UltimoArranque) {
            $horasActivo = [math]::Round(((Get-Date) - [datetime]$infraestructura.UltimoArranque).TotalHours, 1)
            Write-Log -Mensaje "Ultimo arranque: $([datetime]$infraestructura.UltimoArranque) | Activo: $horasActivo horas" -Nivel INFO
        }
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
        foreach ($errorInfra in @($infraestructura.Errores)) {
            if ($errorInfra) { Write-Log -Mensaje "Dato de infraestructura no disponible: $errorInfra" -Nivel WARN }
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
    $analisisParcial = ((-not $inventario.Acceso) -or $inventario.AccesoParcial -or (-not $infraestructura.Acceso) -or $infraestructura.AccesoParcial)
    Write-Log -Mensaje "ANALISIS DEL SERVIDOR COMPLETADO$(if ($analisisParcial) { ' CON INFORMACION PARCIAL' } else { '' }) en $duracion segundos | $hostObjetivo | $($puertosAbiertos.Count) puerto(s) confirmado(s)." -Nivel $(if ($analisisParcial) { 'WARN' } else { 'OK' })
    Write-Log -Mensaje 'El analisis fue de solo lectura; no se modificaron servicios, sesiones ni bases de datos.' -Nivel INFO
}


function Get-CatalogoSatCfdi {
    return @(
        [PSCustomObject]@{ Nombre = 'Control Microsoft'; Grupo = 'CONTROL'; Url = 'https://www.microsoft.com/'; Modo = 'PAGINA' },
        [PSCustomObject]@{ Nombre = 'Control Google'; Grupo = 'CONTROL'; Url = 'https://www.google.com/generate_204'; Modo = 'PAGINA' },
        [PSCustomObject]@{ Nombre = 'Portal SAT'; Grupo = 'SAT_PORTAL'; Url = 'https://www.sat.gob.mx/'; Modo = 'PAGINA' },
        [PSCustomObject]@{ Nombre = 'Verificador CFDI SAT'; Grupo = 'SAT_PORTAL'; Url = 'https://verificacfdi.facturaelectronica.sat.gob.mx/'; Modo = 'PAGINA' },
        [PSCustomObject]@{ Nombre = 'Portal CFDI SAT'; Grupo = 'SAT_PORTAL'; Url = 'https://portalcfdi.facturaelectronica.sat.gob.mx/'; Modo = 'PAGINA' },
        [PSCustomObject]@{ Nombre = 'Autenticacion descarga SAT'; Grupo = 'SAT_DESCARGA'; Url = 'https://cfdidescargamasivasolicitud.clouda.sat.gob.mx/Autenticacion/Autenticacion.svc?wsdl'; Modo = 'SERVICIO' },
        [PSCustomObject]@{ Nombre = 'Solicitud descarga SAT'; Grupo = 'SAT_DESCARGA'; Url = 'https://cfdidescargamasivasolicitud.clouda.sat.gob.mx/SolicitaDescargaService.svc?wsdl'; Modo = 'SERVICIO' },
        [PSCustomObject]@{ Nombre = 'Verificacion descarga SAT'; Grupo = 'SAT_DESCARGA'; Url = 'https://cfdidescargamasivasolicitud.clouda.sat.gob.mx/VerificaSolicitudDescargaService.svc?wsdl'; Modo = 'SERVICIO' },
        [PSCustomObject]@{ Nombre = 'Entrega paquetes SAT'; Grupo = 'SAT_DESCARGA'; Url = 'https://cfdidescargamasiva.clouda.sat.gob.mx/DescargaMasivaService.svc?wsdl'; Modo = 'SERVICIO' },
        [PSCustomObject]@{ Nombre = 'Portal CONTPAQi'; Grupo = 'CONTPAQI'; Url = 'https://www.contpaqi.com/'; Modo = 'PAGINA' },
        [PSCustomObject]@{ Nombre = 'Servicios en linea CONTPAQi'; Grupo = 'CONTPAQI'; Url = 'https://osb.contpaqi.com/'; Modo = 'SERVICIO' }
    )
}

function Invoke-PruebasSatCfdiResponsive {
    param(
        [Parameter(Mandatory)][object[]]$Catalogo,
        [ValidateRange(2, 5)][int]$Muestras = 3
    )
    # Fuerza una sola cadena JSON incluso bajo Windows PowerShell 5.1.
    $catalogoNormalizado = @($Catalogo | Where-Object { $null -ne $_ })
    $catalogoJson = ConvertTo-Json -InputObject $catalogoNormalizado -Depth 5 -Compress
    $codigo = @'
param([string]$CatalogJson, [int]$SampleCount)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$parsedCatalog = ConvertFrom-Json -InputObject $CatalogJson
$catalog = @($parsedCatalog | ForEach-Object { $_ })
$results = @()
foreach ($endpoint in $catalog) {
    # Normaliza la propiedad antes de convertirla. Esto protege el diagnostico
    # contra Object[] en Windows PowerShell 5.1 o datos de catalogo mal formados.
    $urlText = @($endpoint.PSObject.Properties['Url'].Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    $urlText = if ($urlText.Count) { [string]$urlText[0] } else { '' }
    $endpointUri = $null
    if (-not [Uri]::TryCreate($urlText, [UriKind]::Absolute, [ref]$endpointUri) -or $endpointUri.Scheme -notin @('http','https')) {
        $results += [PSCustomObject]@{
            Nombre = [string]$endpoint.Nombre; Grupo = [string]$endpoint.Grupo; Url = $urlText
            Host = ''; DNS = $false; IPs = @(); Disponible = $false; Exitos = 0; Muestras = $SampleCount
            PromedioMs = 0; MaximoMs = 0; EstadosHttp = @()
            Errores = @('La direccion configurada no es una URL HTTP/HTTPS valida.'); DesfaseSegundos = $null
        }
        continue
    }
    $hostName = $endpointUri.DnsSafeHost
    $ips = @()
    try { $ips = @([Net.Dns]::GetHostAddresses($hostName) | ForEach-Object { $_.IPAddressToString } | Select-Object -Unique) } catch { }
    $samples = @()
    for ($sample = 1; $sample -le $SampleCount; $sample++) {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $status = 0
        $errorText = ''
        $dateOffset = $null
        try {
            $request = [Net.HttpWebRequest]::Create($endpointUri)
            $request.Method = 'GET'
            $request.Timeout = 8000
            $request.ReadWriteTimeout = 8000
            $request.AllowAutoRedirect = $true
            $request.MaximumAutomaticRedirections = 4
            $request.UserAgent = 'CONTPAQi-Toolbox-SAT-Diagnostic/1.0'
            $request.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
            $response = $request.GetResponse()
            try {
                $status = [int]$response.StatusCode
                $dateHeader = [string]$response.Headers['Date']
                if ($dateHeader) {
                    $remoteDate = [datetime]::Parse($dateHeader).ToUniversalTime()
                    [double]$ageSeconds = 0
                    $ageHeader = [string]$response.Headers['Age']
                    if ($ageHeader) { [void][double]::TryParse($ageHeader, [ref]$ageSeconds) }
                    if ($ageSeconds -gt 0) { $remoteDate = $remoteDate.AddSeconds($ageSeconds) }
                    $dateOffset = [math]::Round(([datetime]::UtcNow - $remoteDate).TotalSeconds, 1)
                }
            } finally { $response.Dispose() }
        } catch [Net.WebException] {
            if ($_.Exception.Response) {
                try { $status = [int]$_.Exception.Response.StatusCode } finally { $_.Exception.Response.Dispose() }
            } else { $errorText = $_.Exception.Message }
        } catch { $errorText = $_.Exception.Message }
        $watch.Stop()
        $transportOk = ($status -ge 200 -and $status -le 499)
        $expectedOk = if ([string]$endpoint.Modo -eq 'SERVICIO') { $transportOk } else { ($status -ge 200 -and $status -le 399) }
        $samples += [PSCustomObject]@{
            Numero = $sample; EstadoHttp = $status; Milisegundos = [int]$watch.ElapsedMilliseconds
            Transporte = $transportOk; Correcto = $expectedOk; Error = $errorText; DesfaseSegundos = $dateOffset
        }
        Start-Sleep -Milliseconds 120
    }
    $success = @($samples | Where-Object Correcto).Count
    $latencies = @($samples | Where-Object Transporte | Select-Object -ExpandProperty Milisegundos)
    $offsets = @($samples | Where-Object { $null -ne $_.DesfaseSegundos } | Select-Object -ExpandProperty DesfaseSegundos)
    $results += [PSCustomObject]@{
        Nombre = [string]$endpoint.Nombre; Grupo = [string]$endpoint.Grupo; Url = $endpointUri.AbsoluteUri
        Host = $hostName; DNS = ($ips.Count -gt 0); IPs = $ips; Disponible = ($success -ge [math]::Ceiling($SampleCount / 2))
        Exitos = $success; Muestras = $SampleCount
        PromedioMs = if ($latencies.Count) { [math]::Round(($latencies | Measure-Object -Average).Average, 0) } else { 0 }
        MaximoMs = if ($latencies.Count) { ($latencies | Measure-Object -Maximum).Maximum } else { 0 }
        EstadosHttp = @($samples | Select-Object -ExpandProperty EstadoHttp -Unique)
        Errores = @($samples | Where-Object Error | Select-Object -ExpandProperty Error -Unique)
        DesfaseSegundos = if ($offsets.Count) { [math]::Round(($offsets | Measure-Object -Average).Average, 1) } else { $null }
    }
}
[PSCustomObject]@{ Resultados = $results }
'@
    $worker = Invoke-ResponsiveWorker -ScriptText $codigo -Arguments @($catalogoJson, $Muestras) -TimeoutSeconds 150 -Activity 'Comprobando SAT, CFDI y CONTPAQi'
    if (-not $worker.Correcto -or -not $worker.Resultado) {
        return [PSCustomObject]@{ Correcto = $false; Error = $worker.Error; Resultados = @() }
    }
    return [PSCustomObject]@{ Correcto = $true; Error = $null; Resultados = @($worker.Resultado.Resultados) }
}

function Get-ContextoLocalSatCfdi {
    $w32time = Get-Service -Name 'W32Time' -ErrorAction SilentlyContinue
    $proxyWinHttp = ''
    try { $proxyWinHttp = ((& netsh.exe winhttp show proxy 2>&1) -join ' ' -replace '\s+', ' ').Trim() } catch { }
    if ($proxyWinHttp.Length -gt 300) { $proxyWinHttp = $proxyWinHttp.Substring(0, 300) + '...' }
    $proxyUsuario = ''
    try {
        $internet = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ([int]$internet.ProxyEnable -eq 1) { $proxyUsuario = [string]$internet.ProxyServer }
        elseif ($internet.AutoConfigURL) { $proxyUsuario = "PAC: $($internet.AutoConfigURL)" }
        else { $proxyUsuario = 'Sin proxy explicito' }
    } catch { $proxyUsuario = 'No consultado' }
    $serviciosXml = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
        "$($_.Name) $($_.DisplayName) $($_.PathName)" -match '(?i)XMLenLineaService|XMLService|XML\s*en\s*l[ií]nea'
    } | ForEach-Object {
        [PSCustomObject]@{ Nombre = $_.Name; Descripcion = $_.DisplayName; Estado = $_.State; Inicio = $_.StartMode; Ruta = $_.PathName }
    })
    $productoXml = @(Get-ProgramasInstalados | Where-Object { $_.DisplayName -match '(?i)XML\s*en\s*l[ií]nea' } | Sort-Object DisplayVersion -Descending | Select-Object -First 1)
    return [PSCustomObject]@{
        HoraServicio = if ($w32time) { [string]$w32time.Status } else { 'No instalado' }
        ZonaHoraria = [TimeZoneInfo]::Local.DisplayName
        HoraLocal = Get-Date
        ProxyWinHttp = $proxyWinHttp
        ProxyUsuario = $proxyUsuario
        ServiciosXml = $serviciosXml
        ProductoXml = @($productoXml | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)".Trim() })
    }
}

function Save-HistorialSatCfdi {
    param([Parameter(Mandatory)][object]$Resumen)
    $directorio = Join-Path $env:ProgramData 'CONTPAQiToolbox\SatCfdi'
    $archivo = Join-Path $directorio 'historial_sat_cfdi.jsonl'
    try {
        if (-not (Test-Path -LiteralPath $directorio -PathType Container)) { New-Item -ItemType Directory -Path $directorio -Force -ErrorAction Stop | Out-Null }
        $linea = $Resumen | ConvertTo-Json -Depth 7 -Compress
        Add-Content -LiteralPath $archivo -Value $linea -Encoding UTF8 -ErrorAction Stop
        $lineas = @(Get-Content -LiteralPath $archivo -ErrorAction Stop)
        if ($lineas.Count -gt 200) { $lineas | Select-Object -Last 200 | Set-Content -LiteralPath $archivo -Encoding UTF8 -ErrorAction Stop }
        return [PSCustomObject]@{ Correcto = $true; Archivo = $archivo; Registros = [math]::Min(200, $lineas.Count) }
    } catch { return [PSCustomObject]@{ Correcto = $false; Archivo = $archivo; Registros = 0; Error = $_.Exception.Message } }
}

function Show-DiagnosticoTimbrado {
    Write-Encabezado -Titulo 'CENTRO SAT / CFDI' -Subtitulo 'Distingue equipo, CONTPAQi, PAC y servicios oficiales del SAT' -Color 'Magenta'
    $inicio = Get-Date
    Write-Log -Mensaje 'Prueba de solo lectura: no se enviaran RFC, XML, CSD, e.firma, contrasenas ni documentos.' -Nivel INFO

    Write-SeccionMenu -Titulo '1. EQUIPO, RELOJ Y CONFIGURACION LOCAL' -Color 'Yellow'
    $contexto = Get-ContextoLocalSatCfdi
    Write-Log -Mensaje "Hora local: $($contexto.HoraLocal.ToString('dd/MM/yyyy HH:mm:ss')) | Zona: $($contexto.ZonaHoraria) | W32Time: $($contexto.HoraServicio)" -Nivel $(if ($contexto.HoraServicio -eq 'Running') { 'OK' } else { 'WARN' })
    Write-Log -Mensaje "Proxy WinHTTP: $($contexto.ProxyWinHttp)" -Nivel INFO
    Write-Log -Mensaje "Proxy del usuario: $($contexto.ProxyUsuario)" -Nivel INFO
    if ($contexto.ProductoXml.Count) { Write-Log -Mensaje "Producto XML detectado: $($contexto.ProductoXml -join ', ')" -Nivel OK }
    else { Write-Log -Mensaje 'CONTPAQi XML en Linea no aparece en el inventario de programas.' -Nivel INFO }
    if ($contexto.ServiciosXml.Count -eq 0) {
        Write-Log -Mensaje 'No se detecto XMLenLineaService/XMLService en este equipo.' -Nivel INFO
    } else {
        foreach ($servicio in $contexto.ServiciosXml) {
            Write-Log -Mensaje "$($servicio.Nombre): $($servicio.Estado) | Inicio $($servicio.Inicio)" -Nivel $(if ($servicio.Estado -eq 'Running') { 'OK' } else { 'WARN' })
        }
    }

    Write-SeccionMenu -Titulo '2. MUESTREO DE DISPONIBILIDAD - 3 INTENTOS' -Color 'Cyan'
    $pruebas = Invoke-PruebasSatCfdiResponsive -Catalogo (Get-CatalogoSatCfdi) -Muestras 3
    if (-not $pruebas.Correcto) {
        Write-Log -Mensaje "No se completo el muestreo: $($pruebas.Error)" -Nivel ERROR
        return
    }
    foreach ($grupo in @('CONTROL','SAT_PORTAL','SAT_DESCARGA','CONTPAQI')) {
        $titulo = switch ($grupo) { 'CONTROL' { 'CONTROL DE INTERNET' }; 'SAT_PORTAL' { 'PORTALES OFICIALES SAT' }; 'SAT_DESCARGA' { 'DESCARGA MASIVA SAT' }; default { 'CONTPAQI / PAC' } }
        Write-SeccionMenu -Titulo $titulo -Color $(if ($grupo -eq 'SAT_DESCARGA') { 'Magenta' } else { 'Green' })
        foreach ($resultado in @($pruebas.Resultados | Where-Object Grupo -eq $grupo)) {
            $nivel = if ($resultado.Disponible) { 'OK' } elseif (-not $resultado.DNS) { 'ERROR' } else { 'WARN' }
            $http = if (@($resultado.EstadosHttp | Where-Object { $_ -gt 0 }).Count) { @($resultado.EstadosHttp | Where-Object { $_ -gt 0 }) -join '/' } else { 'sin respuesta HTTP' }
            Write-Log -Mensaje "$($resultado.Nombre): $($resultado.Exitos)/$($resultado.Muestras) correcto(s) | HTTP $http | Promedio $($resultado.PromedioMs) ms | Maximo $($resultado.MaximoMs) ms" -Nivel $nivel
            if (-not $resultado.DNS) { Write-Log -Mensaje "DNS no resolvio $($resultado.Host)." -Nivel ERROR }
            foreach ($errorRed in @($resultado.Errores | Select-Object -First 2)) { Write-Log -Mensaje "Detalle: $errorRed" -Nivel INFO }
        }
    }

    $control = @($pruebas.Resultados | Where-Object Grupo -eq 'CONTROL')
    $satPortal = @($pruebas.Resultados | Where-Object Grupo -eq 'SAT_PORTAL')
    $satDescarga = @($pruebas.Resultados | Where-Object Grupo -eq 'SAT_DESCARGA')
    $contpaqi = @($pruebas.Resultados | Where-Object Grupo -eq 'CONTPAQI')
    $controlOk = (@($control | Where-Object Disponible).Count -ge [math]::Ceiling($control.Count / 2))
    $portalOk = (@($satPortal | Where-Object Disponible).Count -ge [math]::Ceiling($satPortal.Count / 2))
    $descargaOk = (@($satDescarga | Where-Object Disponible).Count -ge [math]::Ceiling($satDescarga.Count / 2))
    $servicioContpaqi = @($contpaqi | Where-Object Nombre -eq 'Servicios en linea CONTPAQi' | Select-Object -First 1)[0]
    $contpaqiOk = if ($servicioContpaqi) { [bool]$servicioContpaqi.Disponible } else { (@($contpaqi | Where-Object Disponible).Count -ge [math]::Ceiling($contpaqi.Count / 2)) }
    $xmlDetenido = (@($contexto.ServiciosXml | Where-Object Estado -ne 'Running').Count -gt 0)
    # Solo se usan controles y servicios dinamicos para estimar la hora. Los
    # portales web pueden entregar HTML almacenado en cache durante horas.
    $desfases = @($pruebas.Resultados | Where-Object { $_.Grupo -in @('CONTROL','SAT_DESCARGA') -and $null -ne $_.DesfaseSegundos } | Select-Object -ExpandProperty DesfaseSegundos)
    $desfasePromedio = if ($desfases.Count) { [math]::Round(($desfases | Measure-Object -Average).Average, 1) } else { $null }

    $clasificacion = 'SIN FALLA EXTERNA AL MOMENTO'
    $confianza = 'MEDIA'
    $explicacion = 'Internet, SAT y CONTPAQi respondieron durante las muestras. La incidencia pudo ser intermitente o depender del documento, CSD, e.firma, PAC o cola de descarga.'
    $accion = 'Conserva la hora exacta y el mensaje original. Repite el diagnostico durante la falla y revisa el historial antes de reiniciar servicios.'
    $nivelFinal = 'OK'
    if (-not $controlOk) {
        $clasificacion = 'EQUIPO, DNS, PROXY O RED LOCAL'
        $confianza = 'ALTA'
        $explicacion = 'Los controles independientes de Internet tambien fallaron; no existe evidencia suficiente para atribuir la incidencia al SAT.'
        $accion = 'Revisa DNS, gateway, proxy, firewall, antivirus, VPN y salida HTTPS del equipo antes de tocar CONTPAQi.'
        $nivelFinal = 'ERROR'
    } elseif (-not $portalOk -and -not $descargaOk) {
        $clasificacion = 'PROBABLE INTERMITENCIA GENERAL DEL SAT'
        $confianza = 'ALTA'
        $explicacion = 'Internet funciona, pero fallaron repetidamente portales y servicios oficiales independientes del SAT.'
        $accion = 'No reinstales ni reinicies SQL. Espera, conserva evidencia, repite en 5 a 10 minutos y compara desde otra red.'
        $nivelFinal = 'ERROR'
    } elseif ($portalOk -and -not $descargaOk) {
        $clasificacion = 'PROBABLE INTERMITENCIA EN DESCARGA MASIVA SAT'
        $confianza = 'ALTA'
        $explicacion = 'Los portales del SAT responden, pero autenticacion, solicitud, verificacion o entrega de paquetes presentan fallas repetidas.'
        $accion = 'Conserva la solicitud; no generes peticiones duplicadas. Reintenta despues y revisa si el SAT la mantiene pendiente.'
        $nivelFinal = 'WARN'
    } elseif (-not $contpaqiOk) {
        $clasificacion = 'PROBABLE SERVICIO CONTPAQI / PAC'
        $confianza = 'MEDIA'
        $explicacion = 'Internet y SAT responden, pero los destinos de CONTPAQi no tuvieron disponibilidad consistente.'
        $accion = 'Valida avisos de CONTPAQi/PAC, bitacora de timbrado, folios y el error exacto antes de modificar certificados.'
        $nivelFinal = 'WARN'
    } elseif ($xmlDetenido) {
        $clasificacion = 'SERVICIO LOCAL XML EN LINEA'
        $confianza = 'ALTA'
        $explicacion = 'Los servicios externos responden, pero XMLenLineaService/XMLService esta detenido en este equipo.'
        $accion = 'Revisa su bitacora y ruta ejecutable; despues inicia el servicio de forma controlada y valida una solicitud existente.'
        $nivelFinal = 'WARN'
    } elseif ($null -ne $desfasePromedio -and [math]::Abs($desfasePromedio) -gt 300) {
        $clasificacion = 'RELOJ LOCAL FUERA DE SINCRONIA'
        $confianza = 'ALTA'
        $explicacion = "El reloj difiere aproximadamente $([math]::Abs($desfasePromedio)) segundos de las respuestas HTTPS. Esto puede invalidar tokens, CSD y e.firma."
        $accion = 'Corrige zona horaria y sincronizacion de Windows antes de reintentar autenticacion o timbrado.'
        $nivelFinal = 'ERROR'
    }

    Write-SeccionMenu -Titulo '3. DIAGNOSTICO CORRELACIONADO' -Color $(if ($nivelFinal -eq 'ERROR') { 'Red' } elseif ($nivelFinal -eq 'WARN') { 'Yellow' } else { 'Green' })
    Write-Log -Mensaje "CAUSA PROBABLE: $clasificacion | Confianza $confianza" -Nivel $nivelFinal
    Write-Log -Mensaje $explicacion -Nivel INFO
    Write-Log -Mensaje "ACCION: $accion" -Nivel INFO
    if ($null -ne $desfasePromedio) { Write-Log -Mensaje "Desfase aproximado del reloj frente a servidores HTTPS: $desfasePromedio segundos." -Nivel $(if ([math]::Abs($desfasePromedio) -le 300) { 'OK' } else { 'WARN' }) }
    Write-Log -Mensaje 'Una respuesta HTTPS solo confirma disponibilidad tecnica; no valida credenciales, CSD, e.firma, saldos de timbres ni reglas fiscales del documento.' -Nivel WARN

    $resumenHistorial = [PSCustomObject]@{
        Fecha = Get-Date; Equipo = $env:COMPUTERNAME; Clasificacion = $clasificacion; Confianza = $confianza
        ControlDisponible = $controlOk; PortalSatDisponible = $portalOk; DescargaSatDisponible = $descargaOk
        ContpaqiDisponible = $contpaqiOk; ServicioXmlDetenido = $xmlDetenido
        Resultados = @($pruebas.Resultados | Select-Object Nombre, Grupo, Disponible, Exitos, Muestras, PromedioMs, MaximoMs, EstadosHttp)
    }
    $historial = Save-HistorialSatCfdi -Resumen $resumenHistorial
    if ($historial.Correcto) { Write-Log -Mensaje "Historial guardado: $($historial.Archivo) | $($historial.Registros) registro(s)." -Nivel OK }
    else { Write-Log -Mensaje "No se pudo guardar historial SAT/CFDI: $($historial.Error)" -Nivel WARN }
    $duracion = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    Write-Log -Mensaje "Diagnostico SAT/CFDI finalizado en $duracion segundos con 3 muestras por destino." -Nivel INFO
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
    $estadoDeseado = [Enum]::Parse([System.ServiceProcess.ServiceControllerStatus], $estadoDeseadoTexto)
    $espera = [TimeSpan]::FromSeconds($TimeoutSeconds)
    $servicio.Refresh()
    if ($Action -eq 'Start') {
        if ($servicio.Status.ToString() -eq 'StopPending') {
            $servicio.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, $espera)
            $servicio.Refresh()
        }
        if ($servicio.Status.ToString() -eq 'StartPending') {
            $servicio.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, $espera)
        } elseif ($servicio.Status.ToString() -ne 'Running') {
            try { Start-Service -Name $ServiceName -ErrorAction Stop }
            catch {
                $salidaSc = @(& "$env:SystemRoot\System32\sc.exe" start $ServiceName 2>&1)
                if ($LASTEXITCODE -notin @(0, 1056)) { throw "Start-Service: $($_.Exception.Message) | sc.exe: $($salidaSc -join ' ')" }
            }
            $servicio.WaitForStatus($estadoDeseado, $espera)
        }
    } else {
        if ($servicio.Status.ToString() -eq 'StartPending') {
            $servicio.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, $espera)
            $servicio.Refresh()
        }
        if ($servicio.Status.ToString() -eq 'StopPending') {
            $servicio.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, $espera)
        } elseif ($servicio.Status.ToString() -ne 'Stopped') {
            try { Stop-Service -Name $ServiceName -Force -ErrorAction Stop }
            catch {
                $salidaSc = @(& "$env:SystemRoot\System32\sc.exe" stop $ServiceName 2>&1)
                if ($LASTEXITCODE -notin @(0, 1062)) { throw "Stop-Service: $($_.Exception.Message) | sc.exe: $($salidaSc -join ' ')" }
            }
            $servicio.WaitForStatus($estadoDeseado, $espera)
        }
    }
    $servicio.Refresh()
    [PSCustomObject]@{
        Correcto = ($servicio.Status.ToString() -eq $estadoDeseadoTexto)
        Estado = $servicio.Status.ToString()
        Error = $null
    }
} catch {
    $detalle = $_.Exception.Message
    try {
        $nombreSeguro = $ServiceName.Replace("'", "''")
        $cim = Get-CimInstance Win32_Service -Filter "Name='$nombreSeguro'" -ErrorAction Stop
        $detalle += " | Estado=$($cim.State), Inicio=$($cim.StartMode), Win32Exit=$($cim.ExitCode), ServiceExit=$($cim.ServiceSpecificExitCode)"
    } catch { }
    [PSCustomObject]@{ Correcto = $false; Estado = 'Desconocido'; Error = $detalle }
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
    param(
        [ValidateRange(1, 3)][int]$Intentos = 2,
        [switch]$RecuperarDeshabilitados
    )

    $servicios = @(Get-ServiciosAplicacionCONTPAQi | Sort-Object `
        @{ Expression = { Get-OrdenInicioServicioCONTPAQi -Servicio $_ } }, Name)
    $omitidos = 0
    $erroresInicio = @{}

    foreach ($servicioInicial in $servicios) {
        $nombre = $servicioInicial.Name
        $actual = Get-Service -Name $nombre -ErrorAction SilentlyContinue
        if (-not $actual) { continue }
        if (Test-ServicioDeshabilitado -Nombre $nombre) {
            if (-not $RecuperarDeshabilitados) {
                $omitidos++
                Write-Log -Mensaje "$nombre esta deshabilitado en Windows; se conserva su configuracion." -Nivel WARN
                continue
            }
            try {
                Set-Service -Name $nombre -StartupType Manual -ErrorAction Stop
                Write-Log -Mensaje "$nombre estaba deshabilitado; se restablecio a inicio Manual para permitir su recuperacion." -Nivel WARN
                $actual = Get-Service -Name $nombre -ErrorAction Stop
            } catch {
                $erroresInicio[$nombre] = "No se pudo recuperar el tipo de inicio: $($_.Exception.Message)"
                Write-Log -Mensaje "$nombre sigue deshabilitado: $($_.Exception.Message)" -Nivel ERROR
                continue
            }
        }
        if ($actual.Status -eq 'Running') {
            Write-Log -Mensaje "$nombre ya estaba activo." -Nivel OK
            continue
        }

        # Las dependencias se recuperan primero. Esto evita falsos fallos 1068
        # cuando el servicio CONTPAQi esta bien pero una dependencia se detuvo.
        try {
            foreach ($dependencia in @($actual.ServicesDependedOn)) {
                $depActual = Get-Service -Name $dependencia.ServiceName -ErrorAction SilentlyContinue
                if (-not $depActual -or $depActual.Status -eq 'Running' -or (Test-ServicioDeshabilitado -Nombre $depActual.Name)) { continue }
                $resultadoDep = Invoke-ServiceActionResponsive -Nombre $depActual.Name -Accion Start -TimeoutSegundos 60
                if ($resultadoDep.Correcto) { Write-Log -Mensaje "Dependencia $($depActual.Name) iniciada para $nombre." -Nivel OK }
                else { Write-Log -Mensaje "Dependencia $($depActual.Name) no pudo iniciarse: $($resultadoDep.Error)" -Nivel WARN }
            }
        } catch { Write-Log -Mensaje "No se pudieron enumerar todas las dependencias de $($nombre): $($_.Exception.Message)" -Nivel WARN }

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
            Write-Log -Mensaje "$nombre iniciado y verificado." -Nivel OK
        } else {
            $erroresInicio[$nombre] = $ultimoError
            Write-Log -Mensaje "No se pudo iniciar $($nombre): $ultimoError" -Nivel ERROR
        }
    }

    # Prueba de estabilidad y segunda oportunidad independiente: no se declara
    # exito hasta comprobar que el servicio permanece activo despues del lote.
    Wait-Responsive -Seconds 2
    $segundaVuelta = @(Get-ServiciosAplicacionCONTPAQi | Where-Object {
        -not (Test-ServicioDeshabilitado -Nombre $_.Name) -and $_.Status -ne 'Running'
    } | Select-Object -ExpandProperty Name -Unique)
    foreach ($nombre in $segundaVuelta) {
        Write-Log -Mensaje "$nombre no permanecio activo; ejecutando recuperacion final." -Nivel WARN
        $resultadoFinal = Invoke-ServiceActionResponsive -Nombre $nombre -Accion Start -TimeoutSegundos 90
        if ($resultadoFinal.Correcto) {
            $erroresInicio.Remove($nombre)
            Write-Log -Mensaje "$nombre recuperado y estable en la segunda verificacion." -Nivel OK
        } else {
            $erroresInicio[$nombre] = $resultadoFinal.Error
            Write-Log -Mensaje "Fallo definitivo en $($nombre): $($resultadoFinal.Error)" -Nivel ERROR
        }
    }

    Wait-Responsive -Seconds 1
    $finales = @(Get-ServiciosAplicacionCONTPAQi)
    $fallidos = @($finales | Where-Object {
        -not (Test-ServicioDeshabilitado -Nombre $_.Name) -and $_.Status -ne 'Running'
    } | Select-Object -ExpandProperty Name -Unique)
    $correctos = @($finales | Where-Object { $_.Status -eq 'Running' }).Count

    return [PSCustomObject]@{
        Total = $servicios.Count
        Correctos = $correctos
        Omitidos = $omitidos
        Fallidos = @($fallidos).Count
        FallidosNombres = @($fallidos)
        Errores = $erroresInicio
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
    if ($Script:IsBusy) {
        if ($Script:StatusLabel) { $Script:StatusLabel.Text = ' Hay una operacion en curso; espera a que finalice.' }
        [System.Media.SystemSounds]::Exclamation.Play()
        return
    }
    if ($Script:GUIForm -and -not $Script:ConsoleMode) {
        Close-CurrentPanel
        $Script:LogBox.Clear()
        [System.Windows.Forms.Application]::DoEvents()
    }
    $Script:IsBusy = $true
    if ($Script:Sidebar) {
        foreach ($control in $Script:Sidebar.Controls) {
            if ($control -is [System.Windows.Forms.Button]) { $control.Enabled = $false }
        }
    }
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
        if ($Script:Sidebar -and -not $Script:Sidebar.IsDisposed) {
            foreach ($control in $Script:Sidebar.Controls) {
                if ($control -is [System.Windows.Forms.Button]) { $control.Enabled = $true }
            }
        }
        Write-BarraEstado
    }
}

function Show-Bienvenida {
    Write-Encabezado -Titulo 'CONTPAQi TOOLBOX' -Subtitulo "Equipo detectado: $(Get-PerfilEquipo)" -Color 'Cyan'
    Write-Log -Mensaje 'La herramienta esta lista para trabajar.' -Nivel OK
    Write-Host ''
    Write-SeccionMenu -Titulo 'FLUJO RECOMENDADO' -Color 'Green'
    Write-Log -Mensaje '1. Usa Diagnostico Inteligente para obtener hallazgos priorizados y un reporte PDF.' -Nivel INFO
    Write-Log -Mensaje '2. Usa Centro SAT / CFDI para distinguir equipo, CONTPAQi, PAC y servicios oficiales del SAT.' -Nivel INFO
    Write-Log -Mensaje '3. Desde una terminal, valida primero servidor, puertos, firewall y carpetas compartidas.' -Nivel INFO
    Write-Log -Mensaje '4. Usa Reparar Terminal solo si la validacion detecta problemas en la estacion.' -Nivel INFO
    Write-Log -Mensaje '5. Usa Analisis del Servidor para localizarlo y obtener su inventario remoto.' -Nivel INFO
    Write-Log -Mensaje '6. Para una base lenta o inestable, usa Mantenimiento SQL directamente en el servidor.' -Nivel INFO
    Write-Log -Mensaje '7. Aplica acciones avanzadas solo despues de revisar el diagnostico y la bitacora.' -Nivel INFO
    Write-Host ''
    Write-Log -Mensaje 'Las acciones avanzadas solicitan confirmacion y muestran su validacion final.' -Nivel WARN
}

# --- CONSTRUCCION DEL FORMULARIO GUI ---

function New-GUIButton {
    param(
        [string]$Text,
        [int]$W = 226, [int]$H = 40,
        [System.Drawing.Color]$BgColor = $Script:GUIColors.Button,
        [System.Drawing.Color]$TextColor = $Script:GUIColors.Text,
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
    $btn.Padding = New-Object System.Windows.Forms.Padding(14, 0, 8, 0)
    $btn.Margin = New-Object System.Windows.Forms.Padding(6, 3, 6, 3)
    $btn.Add_Click($OnClick)
    return $btn
}

function New-GUILabel {
    param(
        [string]$Text,
        [int]$W = 238, [int]$H = 24,
        [System.Drawing.Color]$TextColor = $Script:GUIColors.Text,
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
    $lbl = New-GUILabel -Text ($Text.ToUpperInvariant()) -W 226 -H 26 -TextColor $Script:GUIColors.Accent -Font (New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold))
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $lbl.Margin = New-Object System.Windows.Forms.Padding(6, 15, 6, 2)
    return $lbl
}

function New-ToolboxCardButton {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][System.Drawing.Color]$AccentColor,
        [Parameter(Mandatory)][scriptblock]$OnClick
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Size = New-Object System.Drawing.Size(236, 82)
    $button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 12)
    $button.Text = "$Title`r`n$Description"
    $button.TextAlign = 'MiddleLeft'
    $button.Padding = New-Object System.Windows.Forms.Padding(16, 7, 10, 7)
    $button.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.2)
    Set-ModernButtonStyle -Button $button -BaseColor $Script:GUIColors.Surface -TextColor $Script:GUIColors.Text -HoverColor $Script:GUIColors.SurfaceAlt
    $button.FlatAppearance.BorderColor = $AccentColor
    $button.FlatAppearance.BorderSize = 1
    $button.Add_Click($OnClick)
    return $button
}

function Show-ToolboxHome {
    if (-not $Script:LogPanel -or $Script:LogPanel.IsDisposed) { return }
    Close-CurrentPanel
    if ($Script:LogBox) { $Script:LogBox.Visible = $false }
    if ($Script:LogHeader) { $Script:LogHeader.Visible = $false }

    $homePanel = New-Object System.Windows.Forms.Panel
    $homePanel.Dock = 'Fill'
    $homePanel.AutoScroll = $false
    $homePanel.BackColor = $Script:GUIColors.BG
    $homePanel.Padding = New-Object System.Windows.Forms.Padding(28, 24, 24, 22)

    $content = New-Object System.Windows.Forms.FlowLayoutPanel
    $content.Dock = 'Fill'
    $content.FlowDirection = 'TopDown'
    $content.WrapContents = $false
    $content.AutoScroll = $true
    $content.HorizontalScroll.Enabled = $false
    $content.HorizontalScroll.Visible = $false
    $content.BackColor = $Script:GUIColors.BG
    $homePanel.Controls.Add($content)

    $hero = New-Object System.Windows.Forms.Panel
    $hero.Size = New-Object System.Drawing.Size(820, 128)
    $hero.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 18)
    $hero.BackColor = $Script:GUIColors.Surface

    $heroAccent = New-Object System.Windows.Forms.Panel
    $heroAccent.Dock = 'Left'
    $heroAccent.Width = 4
    $heroAccent.BackColor = $Script:GUIColors.Accent
    $hero.Controls.Add($heroAccent)

    $eyebrow = New-Object System.Windows.Forms.Label
    $eyebrow.Text = 'CENTRO DE SOPORTE'
    $eyebrow.Location = New-Object System.Drawing.Point(24, 18)
    $eyebrow.Size = New-Object System.Drawing.Size(500, 18)
    $eyebrow.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
    $eyebrow.ForeColor = $Script:GUIColors.Accent
    $hero.Controls.Add($eyebrow)

    $welcome = New-Object System.Windows.Forms.Label
    $welcome.Text = '¿Qué necesitas resolver hoy?'
    $welcome.Location = New-Object System.Drawing.Point(21, 42)
    $welcome.Size = New-Object System.Drawing.Size(600, 34)
    $welcome.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 20, [System.Drawing.FontStyle]::Bold)
    $welcome.ForeColor = $Script:GUIColors.Text
    $hero.Controls.Add($welcome)

    $profile = New-Object System.Windows.Forms.Label
    $profile.Text = "Equipo: $env:COMPUTERNAME   |   Perfil detectado: $(Get-PerfilEquipo)"
    $profile.Location = New-Object System.Drawing.Point(25, 83)
    $profile.Size = New-Object System.Drawing.Size(740, 24)
    $profile.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $profile.ForeColor = $Script:GUIColors.TextDim
    $hero.Controls.Add($profile)

    $readyBadge = New-Object System.Windows.Forms.Label
    $readyBadge.Text = '  LISTO  |  ADMINISTRADOR  '
    $readyBadge.Location = New-Object System.Drawing.Point(590, 20)
    $readyBadge.Size = New-Object System.Drawing.Size(198, 30)
    $readyBadge.Anchor = 'Top, Right'
    $readyBadge.TextAlign = 'MiddleCenter'
    $readyBadge.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
    $readyBadge.ForeColor = $Script:GUIColors.Success
    $readyBadge.BackColor = $Script:GUIColors.SurfaceAlt
    $hero.Controls.Add($readyBadge)
    $content.Controls.Add($hero)

    $quickTitle = New-Object System.Windows.Forms.Label
    $quickTitle.Text = 'ACCESOS RÁPIDOS'
    $quickTitle.Size = New-Object System.Drawing.Size(820, 26)
    $quickTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $quickTitle.ForeColor = $Script:GUIColors.TextDim
    $quickTitle.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $content.Controls.Add($quickTitle)

    $quick = New-Object System.Windows.Forms.FlowLayoutPanel
    $quick.Size = New-Object System.Drawing.Size(820, 188)
    $quick.FlowDirection = 'LeftToRight'
    $quick.WrapContents = $true
    $quick.BackColor = $Script:GUIColors.BG
    $quick.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
    $quick.Controls.Add((New-ToolboxCardButton -Title 'Diagnóstico inteligente' -Description 'Revisión completa + reporte PDF' -AccentColor $Script:GUIColors.Accent -OnClick {
        Show-Accion -Titulo 'Diagnostico Inteligente' -Subtitulo 'Analisis priorizado y reporte PDF profesional' -Color 'Magenta' -Accion { Invoke-DiagnosticoInteligenteCONTPAQi }
    }))
    $quick.Controls.Add((New-ToolboxCardButton -Title 'Revisar terminal' -Description 'Servicios y licenciamiento local' -AccentColor $Script:GUIColors.Success -OnClick {
        Show-Accion -Titulo 'Estado Terminal' -Subtitulo 'AuthServer' -Color 'DarkCyan' -Accion { Show-EstadoServiciosTerminal }
    }))
    $quick.Controls.Add((New-ToolboxCardButton -Title 'Validar conexión' -Description 'Servidor, puertos y carpetas' -AccentColor $Script:GUIColors.Warning -OnClick {
        Show-Accion -Titulo 'Terminal hacia Servidor' -Subtitulo 'Puertos + firewall + carpetas + licencias' -Color 'DarkCyan' -Accion { Invoke-DiagnosticoTerminalServidorCONTPAQi }
    }))
    $quick.Controls.Add((New-ToolboxCardButton -Title 'Salud de SQL' -Description 'Capacidad, respaldos y actividad' -AccentColor $Script:GUIColors.Accent -OnClick {
        Show-Accion -Titulo 'Salud de SQL Server' -Subtitulo 'Capacidad, respaldos, actividad y espacio por empresa' -Color 'Magenta' -Accion { Show-SaludSQLProfesional }
    }))
    $quick.Controls.Add((New-ToolboxCardButton -Title 'Centro SAT / CFDI' -Description 'Equipo, PAC y servicios SAT' -AccentColor $Script:GUIColors.Warning -OnClick {
        Show-Accion -Titulo 'Centro SAT / CFDI' -Subtitulo 'Equipo vs CONTPAQi vs PAC vs SAT' -Color 'Magenta' -Accion { Show-DiagnosticoTimbrado }
    }))
    $quick.Controls.Add((New-ToolboxCardButton -Title 'Abrir reportes' -Description 'Consulta diagnósticos anteriores' -AccentColor $Script:GUIColors.TextDim -OnClick {
        try {
            if (-not (Test-Path -LiteralPath $Script:ReportDirectory -PathType Container)) { New-Item -ItemType Directory -Path $Script:ReportDirectory -Force | Out-Null }
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$Script:ReportDirectory`"" | Out-Null
        } catch { Write-Log -Mensaje "No se pudo abrir la carpeta de reportes: $($_.Exception.Message)" -Nivel ERROR }
    }))
    $content.Controls.Add($quick)

    $tip = New-Object System.Windows.Forms.Label
    $tip.Text = 'Consejo: comienza con un diagnóstico. Las reparaciones avanzadas están agrupadas y protegidas para evitar cambios accidentales.'
    $tip.Size = New-Object System.Drawing.Size(820, 48)
    $tip.Padding = New-Object System.Windows.Forms.Padding(16, 0, 14, 0)
    $tip.TextAlign = 'MiddleLeft'
    $tip.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $tip.ForeColor = $Script:GUIColors.TextDim
    $tip.BackColor = $Script:GUIColors.Surface
    $content.Controls.Add($tip)

    $welcomeFontNormal = New-Object System.Drawing.Font('Segoe UI Semibold', 20, [System.Drawing.FontStyle]::Bold)
    $welcomeFontCompact = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Bold)
    $homePanel.Add_Disposed({
        $welcomeFontNormal.Dispose()
        $welcomeFontCompact.Dispose()
    }.GetNewClosure())

    $resizeHome = {
        $available = [Math]::Max(340, $content.ClientSize.Width - 24)
        $hero.Width = $available
        $quickTitle.Width = $available
        $quick.Width = $available
        $tip.Width = $available

        $columns = if ($available -ge 760) { 3 } elseif ($available -ge 510) { 2 } else { 1 }
        $gap = 12
        $cardWidth = [Math]::Max(220, [int](($available - (($columns - 1) * $gap)) / $columns))
        foreach ($card in $quick.Controls) {
            if ($card -is [System.Windows.Forms.Button]) { $card.Width = $cardWidth }
        }
        $rows = [Math]::Ceiling($quick.Controls.Count / [double]$columns)
        $quick.Height = [int]($rows * 94)

        $compact = $available -lt 650
        $readyBadge.Visible = -not $compact
        $welcome.Font = if ($compact) { $welcomeFontCompact } else { $welcomeFontNormal }
        $welcome.Width = if ($compact) { [Math]::Max(260, $available - 48) } else { 550 }
        $profile.Width = [Math]::Max(260, $available - 50)
        $content.HorizontalScroll.Enabled = $false
        $content.HorizontalScroll.Visible = $false
    }.GetNewClosure()
    $homePanel.Add_Resize($resizeHome)
    $content.Add_Resize($resizeHome)

    $Script:LogPanel.Controls.Add($homePanel)
    $homePanel.BringToFront()
    $Script:CurrentPanel = $homePanel
    & $resizeHome
}

function Build-GUIForm {
    $form = New-Object System.Windows.Forms.Form
    Set-ModernFormStyle -Form $form
    $form.Text = "CONTPAQi TOOLBOX v$($Script:Version)"
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $minimumWidth = [Math]::Min(860, [Math]::Max(640, $workingArea.Width - 20))
    $minimumHeight = [Math]::Min(620, [Math]::Max(500, $workingArea.Height - 20))
    $initialWidth = [Math]::Min(1240, [Math]::Max($minimumWidth, $workingArea.Width - 60))
    $initialHeight = [Math]::Min(820, [Math]::Max($minimumHeight, $workingArea.Height - 60))
    $form.Size = New-Object System.Drawing.Size($initialWidth, $initialHeight)
    $form.MinimumSize = New-Object System.Drawing.Size($minimumWidth, $minimumHeight)
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = $Script:GUIColors.BG
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $form.ShowIcon = $true
    $form.KeyPreview = $true
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
    $headerPanel.Height = 74
    $headerPanel.BackColor = $Script:GUIColors.Header
    $form.Controls.Add($headerPanel)

    $Script:HeaderTitle = New-Object System.Windows.Forms.Label
    $Script:HeaderTitle.Text = 'CONTPAQi Toolbox'
    $Script:HeaderTitle.Location = New-Object System.Drawing.Point(86, 10)
    $Script:HeaderTitle.Size = New-Object System.Drawing.Size(620, 32)
    $Script:HeaderTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18, [System.Drawing.FontStyle]::Bold)
    $Script:HeaderTitle.ForeColor = $Script:GUIColors.Accent
    $Script:HeaderTitle.BackColor = [System.Drawing.Color]::Transparent
    $headerPanel.Controls.Add($Script:HeaderTitle)

    $Script:HeaderSub = New-Object System.Windows.Forms.Label
    $Script:HeaderSub.Text = 'Diagnóstico, mantenimiento y monitoreo en un solo lugar'
    $Script:HeaderSub.Location = New-Object System.Drawing.Point(88, 43)
    $Script:HeaderSub.Size = New-Object System.Drawing.Size(620, 20)
    $Script:HeaderSub.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $Script:HeaderSub.ForeColor = $Script:GUIColors.TextDim
    $Script:HeaderSub.BackColor = [System.Drawing.Color]::Transparent
    $headerPanel.Controls.Add($Script:HeaderSub)

    $mainLogo = New-ToolboxLogoPictureBox -Size 50
    $mainLogo.Location = New-Object System.Drawing.Point(20, 11)
    $headerPanel.Controls.Add($mainLogo)

    $verLabel = New-Object System.Windows.Forms.Label
    $verLabel.Text = "  ADMIN  •  v$($Script:Version)  "
    $verLabel.Location = New-Object System.Drawing.Point(1050, 20)
    $verLabel.Size = New-Object System.Drawing.Size(152, 32)
    $verLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $verLabel.ForeColor = $Script:GUIColors.Success
    $verLabel.TextAlign = 'MiddleCenter'
    $verLabel.BackColor = $Script:GUIColors.Surface
    $verLabel.Anchor = 'Top, Right'
    $headerPanel.Controls.Add($verLabel)

    $headerTitleControl = $Script:HeaderTitle
    $headerSubControl = $Script:HeaderSub
    $resizeHeader = {
        $ancho = [Math]::Max(0, $headerPanel.ClientSize.Width)
        $verLabel.Left = [Math]::Max(94, $ancho - $verLabel.Width - 20)
        $anchoTexto = [Math]::Max(140, $verLabel.Left - $headerTitleControl.Left - 14)
        $headerTitleControl.Width = $anchoTexto
        $headerSubControl.Width = $anchoTexto
    }.GetNewClosure()
    $headerPanel.Add_Resize($resizeHeader)
    & $resizeHeader

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
    $mainSplit.SplitterDistance = [Math]::Min(264, [Math]::Max(230, [int]($initialWidth * 0.25)))
    $mainSplit.FixedPanel = 'Panel1'
    $mainSplit.Panel1MinSize = 220
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
$sidebar.Padding = New-Object System.Windows.Forms.Padding(10, 12, 8, 14)
$sidebar.HorizontalScroll.Enabled = $false
$sidebar.HorizontalScroll.Visible = $false
$sidebarOuter.Controls.Add($sidebar)
$Script:Sidebar = $sidebar

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

    $sidebar.Controls.Add((New-GUIButton -Text 'Inicio' -H 44 -BgColor $Script:GUIColors.AccentDark -TextColor $Script:GUIColors.Text -Font (New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-ToolboxHome
    }))

    # --- DIAGNOSTICO Y REPORTES ---
    $sidebar.Controls.Add((New-GUISeccionLabel -Text 'Diagnóstico'))

    $sidebar.Controls.Add((New-GUIButton -Text 'Diagnóstico inteligente + PDF' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Accent -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Diagnostico Inteligente' -Subtitulo 'Analisis priorizado y reporte PDF profesional' -Color 'Magenta' -Accion { Invoke-DiagnosticoInteligenteCONTPAQi }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text 'Centro SAT / CFDI' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Warning -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Centro SAT / CFDI' -Subtitulo 'Equipo vs CONTPAQi vs PAC vs SAT' -Color 'Magenta' -Accion { Show-DiagnosticoTimbrado }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text 'Abrir reportes' -BgColor $Script:GUIColors.Button -TextColor $Script:GUIColors.Text -Font $btnFont -OnClick {
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
    $sidebar.Controls.Add((New-GUISeccionLabel -Text 'Terminal'))

    $sidebar.Controls.Add((New-GUIButton -Text 'Revisar terminal' -BgColor $Script:GUIColors.Button -TextColor $Script:GUIColors.Text -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Estado Terminal' -Subtitulo 'AuthServer' -Color 'DarkCyan' -Accion { Show-EstadoServiciosTerminal }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text 'Validar servidor y accesos' -BgColor $Script:GUIColors.TerminalBtn -TextColor $Script:GUIColors.Success -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Terminal hacia Servidor' -Subtitulo 'Puertos + firewall + carpetas + licencias' -Color 'DarkCyan' -Accion { Invoke-DiagnosticoTerminalServidorCONTPAQi }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text 'Reparar terminal' -BgColor $Script:GUIColors.TerminalBtn -TextColor $Script:GUIColors.Accent -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Reparacion Avanzada de Terminal' -Subtitulo 'Servicios + ACL + Windows + red + verificacion real' -Color 'DarkCyan' -Accion { Reset-TerminalRapido }
    }))

    # --- SERVIDOR ---
    $sidebar.Controls.Add((New-GUISeccionLabel -Text 'Servidor y SQL'))

    $sidebar.Controls.Add((New-GUIButton -Text 'Revisar servidor' -BgColor $Script:GUIColors.Button -TextColor $Script:GUIColors.Text -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Estado PID' -Subtitulo 'Servidor' -Color 'Red' -Accion { Show-EstadoPIDServidor }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text 'Análisis del servidor' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Accent -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Analisis del Servidor' -Subtitulo 'Autodeteccion e inventario remoto profundo' -Color 'Magenta' -Accion { Show-AnalisisProfundoServidorCONTPAQi }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text 'Salud de SQL' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Accent -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Salud de SQL Server' -Subtitulo 'Capacidad, respaldos, actividad y espacio por empresa' -Color 'Magenta' -Accion { Show-SaludSQLProfesional }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text 'Mantenimiento SQL' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Success -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Mantenimiento SQL' -Subtitulo 'Respaldo, integridad, indices y estadisticas' -Color 'Green' -Accion { Invoke-MantenimientoSQLProfesional }
    }))

    $advancedToggle = New-GUIButton -Text 'Mostrar acciones avanzadas' -BgColor $Script:GUIColors.Button -TextColor $Script:GUIColors.Warning -Font (New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)) -OnClick { }
    $sidebar.Controls.Add($advancedToggle)

    $deepRepairButton = New-GUIButton -Text 'Reparación profunda' -BgColor $Script:GUIColors.ServerBtn -TextColor ([System.Drawing.Color]::White) -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-Accion -Titulo 'Reparacion Profunda' -Subtitulo 'Reinicio controlado y validacion completa' -Color 'Red' -Accion { Invoke-ReparacionProfundaCONTPAQi }
    }
    $deepRepairButton.Visible = $false
    $sidebar.Controls.Add($deepRepairButton)

    $closeSessionsButton = New-GUIButton -Text 'Cerrar sesiones CONTPAQi' -BgColor $Script:GUIColors.ServerBtn -TextColor $Script:GUIColors.Error -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Expulsar Usuarios' -Subtitulo 'Servidor RDS' -Color 'Red' -Accion { Expulsar-UsuariosSistemas }
    }
    $closeSessionsButton.Visible = $false
    $sidebar.Controls.Add($closeSessionsButton)

    $totalRepairButton = New-GUIButton -Text 'Reparación total del servidor' -BgColor $Script:GUIColors.ServerBtn -TextColor $Script:GUIColors.Error -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Reparacion Total del Servidor' -Subtitulo '14 etapas: DISM/SFC + Red + SQL + CONTPAQi' -Color 'Red' -Accion { Ejecutar-SuperReset }
    }
    $totalRepairButton.Visible = $false
    $sidebar.Controls.Add($totalRepairButton)

    $advancedButtons = @($deepRepairButton, $closeSessionsButton, $totalRepairButton)
    $advancedToggle.Add_Click({
        $show = -not $advancedButtons[0].Visible
        foreach ($button in $advancedButtons) { $button.Visible = $show }
        $advancedToggle.Text = if ($show) { 'Ocultar acciones avanzadas' } else { 'Mostrar acciones avanzadas' }
        $sidebar.PerformLayout()
    }.GetNewClosure())

    # --- MONITOREO AUTOMATICO ---
    $sidebar.Controls.Add((New-GUISeccionLabel -Text 'Monitoreo'))

    $sidebar.Controls.Add((New-GUIButton -Text 'ServicesDev' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Success -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        Show-ServicesDevMonitor
    }))

    # --- ADMINISTRACION ---
    $sidebar.Controls.Add((New-GUISeccionLabel -Text 'Administración'))

    $sidebar.Controls.Add((New-GUIButton -Text 'Cambiar contraseña SQL' -BgColor $Script:GUIColors.SupportBtn -TextColor $Script:GUIColors.Warning -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Cambiar Contrasena SQL' -Subtitulo 'Login sa' -Color 'Green' -Accion { Restablecer-ContrasenaSQL }
    }))

    $sidebar.Controls.Add((New-GUIButton -Text 'Desinstalar CONTPAQi' -BgColor $Script:GUIColors.ServerBtn -TextColor $Script:GUIColors.Error -Font $btnFont -OnClick {
        Show-Accion -Titulo 'Desinstalar' -Subtitulo 'Cualquier version' -Color 'Red' -Accion { Show-MenuDesinstalar }
    }))

    # --- BOTON SALIR ---
    $sidebar.Controls.Add((New-GUIButton -Text 'Cerrar Toolbox' -H 40 -BgColor $Script:GUIColors.Button -TextColor $Script:GUIColors.TextDim -Font (New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)) -OnClick {
        $form.Close()
    }))

    # --- LOG OUTPUT PANEL ---
    $Script:LogPanel = $mainSplit.Panel2
    $Script:LogPanel.BackColor = $Script:GUIColors.LogBG
    $Script:LogPanel.Padding = New-Object System.Windows.Forms.Padding(20, 18, 20, 18)

    $logHeader = New-Object System.Windows.Forms.Panel
    $logHeader.Dock = 'Top'
    $logHeader.Height = 46
    $logHeader.BackColor = $Script:GUIColors.Surface
    $Script:LogPanel.Controls.Add($logHeader)
    $Script:LogHeader = $logHeader

    $logTitle = New-Object System.Windows.Forms.Label
    $logTitle.Dock = 'Fill'
    $logTitle.Text = '   Actividad y resultados'
    $logTitle.TextAlign = 'MiddleLeft'
    $logTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)
    $logTitle.ForeColor = $Script:GUIColors.Text
    $logTitle.BackColor = $Script:GUIColors.Surface
    $logHeader.Controls.Add($logTitle)

    $clearLogButton = New-Object System.Windows.Forms.Button
    $clearLogButton.Dock = 'Right'
    $clearLogButton.Width = 82
    $clearLogButton.Text = 'Limpiar'
    $clearLogButton.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    Set-ModernButtonStyle -Button $clearLogButton -BaseColor $Script:GUIColors.Surface -TextColor $Script:GUIColors.TextDim -HoverColor $Script:GUIColors.SurfaceAlt
    $clearLogButton.FlatAppearance.BorderSize = 0
    $clearLogButton.Add_Click({ if ($Script:LogBox) { $Script:LogBox.Clear() } })
    $logHeader.Controls.Add($clearLogButton)

    $copyLogButton = New-Object System.Windows.Forms.Button
    $copyLogButton.Dock = 'Right'
    $copyLogButton.Width = 82
    $copyLogButton.Text = 'Copiar'
    $copyLogButton.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    Set-ModernButtonStyle -Button $copyLogButton -BaseColor $Script:GUIColors.Surface -TextColor $Script:GUIColors.Accent -HoverColor $Script:GUIColors.SurfaceAlt
    $copyLogButton.FlatAppearance.BorderSize = 0
    $copyLogButton.Add_Click({
        if ($Script:LogBox -and -not [string]::IsNullOrWhiteSpace($Script:LogBox.Text)) {
            try { [System.Windows.Forms.Clipboard]::SetText($Script:LogBox.Text) } catch { }
        }
    })
    $logHeader.Controls.Add($copyLogButton)
    $copyLogButton.BringToFront()

    $Script:LogBox = New-Object System.Windows.Forms.RichTextBox
    $Script:LogBox.Dock = 'Fill'
    $Script:LogBox.BackColor = $Script:GUIColors.LogBG
    $Script:LogBox.ForeColor = $Script:GUIColors.Text
    $Script:LogBox.Font = New-Object System.Drawing.Font('Cascadia Mono', 9.5)
    $Script:LogBox.ReadOnly = $true
    $Script:LogBox.BorderStyle = 'None'
    $Script:LogBox.ScrollBars = 'Vertical'
    $Script:LogBox.WordWrap = $true
    $Script:LogPanel.Controls.Add($Script:LogBox)
    $logHeader.BringToFront()

    $form.Controls.SetChildIndex($mainSplit, 0)
    $form.PerformLayout()
    $mainSplit.Panel2MinSize = 320
    $mainSplit.SplitterDistance = [Math]::Min(264, [Math]::Max(230, [int]($form.ClientSize.Width * 0.25)))

    $Script:GUIForm = $form
    return $form
}

# --- INICIO ---

$Script:ConsoleMode = $false

# Verificar permisos de administrador y solicitar elevacion UAC.
if (-not (Test-Admin)) {
    if (-not (Request-Administrator)) { exit 0 }
}

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

if (-not (Enter-ToolboxSingleInstance)) {
    [System.Windows.Forms.MessageBox]::Show(
        'CONTPAQi Toolbox ya esta abierto en este equipo.',
        'CONTPAQi Toolbox', 'OK', 'Information'
    ) | Out-Null
    exit 0
}

Initialize-ToolboxLog
$form = Build-GUIForm
$codigoSalida = 0
try {
    if (-not (Show-Login)) {
        $codigoSalida = 1
    } else {
        Write-BarraEstado
        Show-Bienvenida
        if ($Script:LogFile) {
            Write-Log -Mensaje "Bitacora de esta sesion: $Script:LogFile" -Nivel INFO
        }
        Show-ToolboxHome
        $form.ShowDialog() | Out-Null
    }
} finally {
    if ($form -and -not $form.IsDisposed) { $form.Dispose() }
    Exit-ToolboxSingleInstance
}
exit $codigoSalida
