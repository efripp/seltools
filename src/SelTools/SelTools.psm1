Set-StrictMode -Version Latest

if (-not ("SelTools.StreamPump" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using System.IO;
using System.Threading.Tasks;

namespace SelTools {
    public static class StreamPump {
        public static Task Start(StreamReader reader, ConcurrentQueue<string> queue) {
            return Task.Run(() => {
                var buffer = new char[512];
                while (true) {
                    int read;
                    try {
                        read = reader.Read(buffer, 0, buffer.Length);
                    } catch {
                        break;
                    }
                    if (read <= 0) {
                        break;
                    }
                    queue.Enqueue(new string(buffer, 0, read));
                }
            });
        }
    }
}
"@
}

function Get-SelRepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Get-SelDataPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ChildPath
    )

    return (Join-Path (Get-SelRepoRoot) ("data\" + $ChildPath))
}

function Get-SelSettingsPath {
    return (Get-SelDataPath -ChildPath "settings.json")
}

function Get-SelUiSettings {
    param(
        [string]$Path = (Get-SelSettingsPath)
    )

    $defaults = [pscustomobject]@{
        ConsoleOutputEnabled = $true
    }

    if (-not (Test-Path $Path)) {
        return $defaults
    }

    try {
        $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $defaults
        }

        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        $enabled = $true
        if ($parsed.PSObject.Properties.Name -contains "ConsoleOutputEnabled") {
            $enabled = [bool]$parsed.ConsoleOutputEnabled
        }

        return [pscustomobject]@{
            ConsoleOutputEnabled = $enabled
        }
    }
    catch {
        return $defaults
    }
}

function Set-SelConsoleOutputPreference {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled,
        [string]$Path = (Get-SelSettingsPath)
    )

    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    [pscustomobject]@{
        ConsoleOutputEnabled = [bool]$Enabled
    } | ConvertTo-Json | Set-Content -Path $Path
}

function Test-SelConsoleOutputEnabled {
    param(
        [string]$Path = (Get-SelSettingsPath)
    )

    return [bool](Get-SelUiSettings -Path $Path).ConsoleOutputEnabled
}

$script:SelProgressSequence = 0

function Get-SelProgressFrame {
    $frames = @(">  ", ">> ", ">>>", " >>", "  >")
    $frame = $frames[$script:SelProgressSequence % $frames.Count]
    $script:SelProgressSequence++
    return $frame
}

function Show-SelProgressIndicator {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $frame = Get-SelProgressFrame
    Write-Progress -Id 1 -Activity "SELTools In Progress" -Status $Message -CurrentOperation ("{0} working" -f $frame)
    return $frame
}

function Clear-SelProgressIndicator {
    Write-Progress -Id 1 -Activity "SELTools In Progress" -Completed
}

function Get-SelDefaultsRows {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-SelDataPath -ChildPath "defaults.csv")
    )

    if (-not (Test-Path $Path)) {
        return @()
    }

    return @(Import-Csv -Path $Path)
}

function Get-SelDefaults {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Profile = "factory",
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-SelDataPath -ChildPath "defaults.csv")
    )

    $rows = Get-SelDefaultsRows -Path $Path
    if (-not $rows -or $rows.Count -eq 0) {
        throw "defaults.csv is empty or missing."
    }

    $hasProfile = $rows[0].PSObject.Properties.Name -contains "Profile"
    if (-not $hasProfile) {
        if ($rows.Count -eq 1) {
            return $rows[0]
        }
        throw "defaults.csv has multiple rows but no Profile column."
    }

    $match = $rows | Where-Object { ([string]$_.Profile).Trim().ToLowerInvariant() -eq $Profile.Trim().ToLowerInvariant() } | Select-Object -First 1
    if (-not $match) {
        throw ("Profile '{0}' not found in defaults.csv." -f $Profile)
    }

    return $match
}

function ConvertTo-SelBool {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    switch ($Value.Trim().ToLowerInvariant()) {
        "1" { return $true }
        "true" { return $true }
        "yes" { return $true }
        "y" { return $true }
        "0" { return $false }
        "false" { return $false }
        "no" { return $false }
        "n" { return $false }
        default { return $true }
    }
}

function Remove-SelControlChars {
    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return ""
    }

    # Keep CR/LF/TAB for line-oriented parsing; strip remaining control chars.
    return ($Text -replace "[\x00-\x08\x0B\x0C\x0E-\x1F]", "")
}

function New-SelTraceContext {
    param(
        [switch]$Enabled,
        [string]$Operation = "",
        [string]$HostIp = "",
        [string]$Serial = ""
    )

    $runId = (Get-Date).ToString("yyyyMMdd-HHmmss")

    $logsDir = Join-Path (Get-SelRepoRoot) "logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir | Out-Null
    }

    $logPath = Join-Path $logsDir ("run-{0}.log" -f $runId)

    return [pscustomobject]@{
        Enabled = $true
        Operation = $Operation
        HostIp = $HostIp
        Serial = $Serial
        RunId = $runId
        LogPath = $logPath
    }
}

function Write-SelTrace {
    param(
        [AllowNull()]
        [pscustomobject]$TraceContext,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($null -eq $TraceContext -or -not $TraceContext.Enabled) {
        return
    }

    $ts = (Get-Date).ToString("s")
    $line = "{0} [TRACE] {1}" -f $ts, $Message
    Add-Content -Path $TraceContext.LogPath -Value $line
    if ($TraceContext.Enabled -and (Test-SelConsoleOutputEnabled)) {
        Write-Host $line
    }
}

function Format-SelTraceChunk {
    param(
        [AllowNull()]
        [string]$Text,
        [int]$MaxLen = 240
    )

    if ($null -eq $Text) {
        return ""
    }

    $escaped = $Text.Replace("`r", "\r").Replace("`n", "\n")
    if ($escaped.Length -le $MaxLen) {
        return $escaped
    }
    return ($escaped.Substring(0, $MaxLen) + "...")
}

function Get-SelPlinkPath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$OverridePath = $env:SELTOOLS_PLINK_PATH,
        [Parameter(Mandatory = $false)]
        [string]$RepoDefaultPath = (Join-Path (Get-SelRepoRoot) "tools\plink.exe")
    )

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($OverridePath)) {
        $candidates += [Environment]::ExpandEnvironmentVariables($OverridePath)
    }
    $candidates += [Environment]::ExpandEnvironmentVariables($RepoDefaultPath)

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if (Test-Path -Path $candidate -PathType Leaf) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw ("plink.exe not found. Checked override='{0}' and default='{1}'." -f $OverridePath, $RepoDefaultPath)
}

function Start-SelPlinkSession {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostIp,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    $plinkPath = Get-SelPlinkPath
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $plinkPath
    $psi.Arguments = ("-telnet -P 23 {0}" -f $HostIp)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    if (-not $process.Start()) {
        throw ("Failed to start plink session for host {0}." -f $HostIp)
    }

    $outputQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    $errorQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'

    $stdoutTask = [SelTools.StreamPump]::Start($process.StandardOutput, $outputQueue)
    $stderrTask = [SelTools.StreamPump]::Start($process.StandardError, $errorQueue)

    $process.StandardInput.NewLine = "`r`n"
    Write-SelTrace -TraceContext $TraceContext -Message ("PLINK start host={0} path={1} args=""{2}""" -f $HostIp, $plinkPath, $psi.Arguments)

    return [pscustomobject]@{
        Process = $process
        StdIn = $process.StandardInput
        OutputQueue = $outputQueue
        ErrorQueue = $errorQueue
        OutputHistory = (New-Object System.Text.StringBuilder)
        ErrorHistory = (New-Object System.Text.StringBuilder)
        StdoutTask = $stdoutTask
        StderrTask = $stderrTask
        HostIp = $HostIp
        PlinkPath = $plinkPath
    }
}

function Stop-SelPlinkSession {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Session
    )

    try { $Session.StdIn.Close() } catch {}
    try { [void]$Session.StdoutTask.Wait(500) } catch {}
    try { [void]$Session.StderrTask.Wait(500) } catch {}

    if ($Session.Process) {
        try {
            if (-not $Session.Process.HasExited) {
                $Session.Process.Kill()
                [void]$Session.Process.WaitForExit(1000)
            }
        }
        catch {}
        finally {
            try { $Session.Process.Dispose() } catch {}
        }
    }
}

function Read-SelSessionReaders {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Session,
        [Parameter(Mandatory = $true)]
        [System.Text.StringBuilder]$Accumulator,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    $didRead = $false
    $chunk = ""
    $outChars = 0
    $errChars = 0
    while ($Session.OutputQueue.TryDequeue([ref]$chunk)) {
        [void]$Accumulator.Append($chunk)
        [void]$Session.OutputHistory.Append($chunk)
        $didRead = $true
        $outChars += $chunk.Length
        Write-SelTrace -TraceContext $TraceContext -Message ("RX stdout ""{0}""" -f (Format-SelTraceChunk -Text $chunk))
    }
    while ($Session.ErrorQueue.TryDequeue([ref]$chunk)) {
        [void]$Accumulator.Append($chunk)
        [void]$Session.ErrorHistory.Append($chunk)
        $didRead = $true
        $errChars += $chunk.Length
        Write-SelTrace -TraceContext $TraceContext -Message ("RX stderr ""{0}""" -f (Format-SelTraceChunk -Text $chunk))
    }
    if ($didRead) {
        Write-SelTrace -TraceContext $TraceContext -Message ("RX chars stdout={0} stderr={1}" -f $outChars, $errChars)
    }
    return $didRead
}

function Get-SelSessionErrorSummary {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Session,
        [int]$MaxChars = 240
    )

    $text = Remove-SelControlChars -Text ([string]$Session.ErrorHistory.ToString()).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }
    if ($text.Length -gt $MaxChars) {
        return $text.Substring(0, $MaxChars) + "..."
    }
    return $text
}

function Read-SelSessionAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Session,
        [int]$InitialWaitMs = 300,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    Write-SelTrace -TraceContext $TraceContext -Message ("WAIT available start initialWaitMs={0}" -f $InitialWaitMs)
    Start-Sleep -Milliseconds $InitialWaitMs
    $sb = New-Object System.Text.StringBuilder

    for ($i = 0; $i -lt 20; $i++) {
        $didRead = Read-SelSessionReaders -Session $Session -Accumulator $sb -TraceContext $TraceContext
        if (-not $didRead) {
            break
        }
        Start-Sleep -Milliseconds 40
    }

    $result = Remove-SelControlChars -Text $sb.ToString()
    Write-SelTrace -TraceContext $TraceContext -Message ("WAIT available done chars={0}" -f $result.Length)
    return $result
}

function Read-SelSessionUntil {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Session,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [int]$TimeoutMs = 6000,
        [AllowNull()]
        [pscustomobject]$TraceContext,
        [switch]$ThrowOnTimeout
    )

    Write-SelTrace -TraceContext $TraceContext -Message ("WAIT until start pattern={0} timeoutMs={1}" -f $Pattern, $TimeoutMs)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $sb = New-Object System.Text.StringBuilder
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        $didRead = Read-SelSessionReaders -Session $Session -Accumulator $sb -TraceContext $TraceContext
        $clean = Remove-SelControlChars -Text $sb.ToString()
        if ($clean -match $Pattern) {
            Write-SelTrace -TraceContext $TraceContext -Message ("WAIT until matched elapsedMs={0}" -f $sw.ElapsedMilliseconds)
            return $clean
        }

        if ($Session.Process.HasExited -and -not $didRead) {
            Start-Sleep -Milliseconds 80
            $didRead = Read-SelSessionReaders -Session $Session -Accumulator $sb -TraceContext $TraceContext
            if ($didRead) {
                continue
            }
            $exitCode = $Session.Process.ExitCode
            $errSummary = Get-SelSessionErrorSummary -Session $Session
            Write-SelTrace -TraceContext $TraceContext -Message ("WAIT until process exited early exitCode={0} stderr=""{1}""" -f $exitCode, $errSummary)
            if ($ThrowOnTimeout) {
                if ([string]::IsNullOrWhiteSpace($errSummary)) {
                    throw ("Plink exited before expected prompt on host {0} (exitCode={1})." -f $Session.HostIp, $exitCode)
                }
                throw ("Plink exited before expected prompt on host {0} (exitCode={1}, stderr='{2}')." -f $Session.HostIp, $exitCode, $errSummary)
            }
            break
        }

        Start-Sleep -Milliseconds 80
    }

    $timedOutText = Remove-SelControlChars -Text $sb.ToString()
    $errSummary = Get-SelSessionErrorSummary -Session $Session
    $tail = $timedOutText
    if ($tail.Length -gt 200) {
        $tail = $tail.Substring($tail.Length - 200)
    }
    Write-SelTrace -TraceContext $TraceContext -Message ("WAIT until timeout elapsedMs={0} chars={1} tail=""{2}"" stderr=""{3}""" -f $sw.ElapsedMilliseconds, $timedOutText.Length, (Format-SelTraceChunk -Text $tail), $errSummary)
    if ($ThrowOnTimeout) {
        if ([string]::IsNullOrWhiteSpace($errSummary)) {
            throw ("Timed out waiting for pattern '{0}' on host {1}." -f $Pattern, $Session.HostIp)
        }
        throw ("Timed out waiting for pattern '{0}' on host {1}. plink stderr='{2}'." -f $Pattern, $Session.HostIp, $errSummary)
    }
    return $timedOutText
}

function Send-SelSessionLine {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Session,
        [AllowNull()]
        [string]$Text,
        [AllowNull()]
        [pscustomobject]$TraceContext,
        [switch]$Sensitive
    )

    if ($null -eq $Text) {
        $Text = ""
    }

    if ($Session.Process.HasExited) {
        throw ("Plink session exited before sending input (host={0})." -f $Session.HostIp)
    }

    if ($Sensitive) {
        Write-SelTrace -TraceContext $TraceContext -Message 'TX "<REDACTED_PASSWORD>"'
    }
    else {
        Write-SelTrace -TraceContext $TraceContext -Message ("TX ""{0}""" -f $Text)
    }
    $Session.StdIn.WriteLine($Text)
    $Session.StdIn.Flush()
}

function Write-SelProgress {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    $frame = Show-SelProgressIndicator -Message $Message
    if (Test-SelConsoleOutputEnabled) {
        Write-Host ("{0} {1}" -f $frame, $Message)
    }
    Write-SelTrace -TraceContext $TraceContext -Message $Message
}

function Read-SelPromptWithDefault {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [AllowNull()]
        [string]$DefaultValue
    )

    Clear-SelProgressIndicator

    if ([string]::IsNullOrWhiteSpace($DefaultValue)) {
        return (Read-Host $Prompt)
    }

    $input = Read-Host ("{0} [{1}]" -f $Prompt, $DefaultValue)
    if ([string]::IsNullOrWhiteSpace($input)) {
        return $DefaultValue
    }

    return $input
}

function Read-SelSensitiveValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    $secure = Read-Host $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Get-SelFirmwareLabelFromFid {
    param(
        [AllowNull()]
        [string]$Fid
    )

    if ([string]::IsNullOrWhiteSpace($Fid)) {
        return ""
    }

    if ($Fid -match "^([^-]+-[^-]+-[^-]+)") {
        return $Matches[1]
    }

    return $Fid
}

function ConvertFrom-SelIdOutput {
    param(
        [AllowNull()]
        [string]$Text
    )

    $result = [ordered]@{}
    $clean = Remove-SelControlChars -Text $Text
    $rx = [regex]'"([^=]+)=([^"]*)","[^"]*"'
    $matches = $rx.Matches($clean)
    foreach ($m in $matches) {
        $key = $m.Groups[1].Value.Trim()
        $value = $m.Groups[2].Value.Trim()
        if ($key) {
            $result[$key] = $value
        }
    }
    return [pscustomobject]$result
}

function ConvertFrom-SelStaOutput {
    param(
        [AllowNull()]
        [string]$Text
    )

    $clean = Remove-SelControlChars -Text $Text
    $serial = ""
    $fid = ""
    $cid = ""
    $partNum = ""

    if ($clean -match "Serial\s+N(?:um|o)\s*=\s*(\d+)") { $serial = $Matches[1] }
    if ($clean -match "FID\s*=\s*([A-Za-z0-9\-_]+)") { $fid = $Matches[1] }
    if ($clean -match "CID\s*=\s*([A-Za-z0-9]+)") { $cid = $Matches[1] }
    if ($clean -match "PART NUM\s*=\s*([A-Za-z0-9]+)") { $partNum = $Matches[1] }

    return [pscustomobject]@{
        Serial = $serial
        FID = $fid
        CID = $cid
        PARTNUM = $partNum
    }
}

function ConvertTo-SelPrimaryInterface {
    param(
        [AllowNull()]
        [string]$Selector
    )

    if ([string]::IsNullOrWhiteSpace($Selector)) {
        return ""
    }

    switch ($Selector.Trim().ToUpperInvariant()) {
        "A" { return "1A" }
        "B" { return "1B" }
        "1A" { return "1A" }
        "1B" { return "1B" }
        default { return "" }
    }
}

function ConvertTo-SelNetPortSelector {
    param(
        [AllowNull()]
        [string]$Interface
    )

    if ([string]::IsNullOrWhiteSpace($Interface)) {
        return ""
    }

    switch ($Interface.Trim().ToUpperInvariant()) {
        "A" { return "A" }
        "B" { return "B" }
        "1A" { return "A" }
        "1B" { return "B" }
        default { return "" }
    }
}

function Get-SelEthInterfaceStatus {
    param(
        [AllowNull()]
        [string]$PortLineSuffix
    )

    $raw = ""
    if ($null -ne $PortLineSuffix) {
        $raw = $PortLineSuffix.Trim()
    }

    $linkStatus = ""
    $speed = ""
    $duplex = ""
    $media = ""

    if ($raw -match "(?i)\b(UP|DOWN)\b") { $linkStatus = $Matches[1].ToUpperInvariant() }
    if ($raw -match "(?i)\b(10|100|1000|10/100|100/1000|1G|10G)\b") { $speed = $Matches[1].ToUpperInvariant() }
    if ($raw -match "(?i)\b(HALF|FULL)\b") { $duplex = $Matches[1].ToUpperInvariant() }
    if ($raw -match "(?i)\b(COPPER|FIBER|RJ45|SFP|OPTICAL)\b") { $media = $Matches[1].ToUpperInvariant() }

    return [pscustomobject]@{
        Raw = $raw
        LinkStatus = $linkStatus
        Speed = $speed
        Duplex = $duplex
        Media = $media
    }
}

function ConvertFrom-SelEthOutput {
    param(
        [AllowNull()]
        [string]$Text
    )

    $clean = Remove-SelControlChars -Text $Text
    $mac = ""
    $ip = ""
    $mask = ""
    $gateway = ""
    $netMode = ""
    $primaryPortDisplay = ""
    $activePortDisplay = ""
    $port1ALine = ""
    $port1BLine = ""

    if ($clean -match "MAC:\s*([0-9A-Fa-f\-]+)") { $mac = $Matches[1].ToUpperInvariant() }
    if ($clean -match "IP ADDRESS:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)") { $ip = $Matches[1] }
    if ($clean -match "SUBNET MASK:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)") { $mask = $Matches[1] }
    if ($clean -match "DEFAULT GATEWAY:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)") { $gateway = $Matches[1] }
    if ($clean -match "(?im)^\s*NETMODE:\s*([A-Za-z0-9\-_]+)\s*$") { $netMode = $Matches[1].ToUpperInvariant() }
    if ($clean -match "(?im)^\s*PRIMARY PORT:\s*([1]?[AB])\s*$") { $primaryPortDisplay = $Matches[1].ToUpperInvariant() }
    if ($clean -match "(?im)^\s*ACTIVE PORT:\s*([1]?[AB])\s*$") { $activePortDisplay = $Matches[1].ToUpperInvariant() }
    if ($clean -match "(?im)^\s*PORT\s*1A\b[:\s]*(.*)$") { $port1ALine = $Matches[1] }
    if ($clean -match "(?im)^\s*PORT\s*1B\b[:\s]*(.*)$") { $port1BLine = $Matches[1] }

    $primaryInterface = ConvertTo-SelPrimaryInterface -Selector $primaryPortDisplay
    $activeInterface = ConvertTo-SelPrimaryInterface -Selector $activePortDisplay
    $configuredPrimarySelector = ConvertTo-SelNetPortSelector -Interface $primaryInterface

    return [pscustomobject]@{
        MAC = $mac
        IP = $ip
        Mask = $mask
        Gateway = $gateway
        NetMode = $netMode
        PrimaryPortDisplay = $primaryPortDisplay
        ActivePortDisplay = $activePortDisplay
        PrimaryInterface = $primaryInterface
        ActiveInterface = $activeInterface
        ConfiguredPrimarySelector = $configuredPrimarySelector
        PrimaryPort = $configuredPrimarySelector
        ActivePort = (ConvertTo-SelNetPortSelector -Interface $activeInterface)
        Port1A = (Get-SelEthInterfaceStatus -PortLineSuffix $port1ALine)
        Port1B = (Get-SelEthInterfaceStatus -PortLineSuffix $port1BLine)
    }
}

function Get-SelEthernetModelFromEthParsed {
    param(
        [AllowNull()]
        [pscustomobject]$EthParsed
    )

    $primaryInterface = ""
    $activeInterface = ""
    $netMode = ""
    $configuredPrimarySelector = ""
    $port1A = Get-SelEthInterfaceStatus -PortLineSuffix ""
    $port1B = Get-SelEthInterfaceStatus -PortLineSuffix ""

    if ($EthParsed) {
        $primaryInterface = ConvertTo-SelPrimaryInterface -Selector ([string]$EthParsed.PrimaryInterface)
        if ([string]::IsNullOrWhiteSpace($primaryInterface)) {
            $primaryInterface = ConvertTo-SelPrimaryInterface -Selector ([string]$EthParsed.PrimaryPortDisplay)
        }
        if ([string]::IsNullOrWhiteSpace($primaryInterface)) {
            $primaryInterface = ConvertTo-SelPrimaryInterface -Selector ([string]$EthParsed.PrimaryPort)
        }

        $activeInterface = ConvertTo-SelPrimaryInterface -Selector ([string]$EthParsed.ActiveInterface)
        if ([string]::IsNullOrWhiteSpace($activeInterface)) {
            $activeInterface = ConvertTo-SelPrimaryInterface -Selector ([string]$EthParsed.ActivePortDisplay)
        }
        if ([string]::IsNullOrWhiteSpace($activeInterface)) {
            $activeInterface = ConvertTo-SelPrimaryInterface -Selector ([string]$EthParsed.ActivePort)
        }

        $netMode = [string]$EthParsed.NetMode
        $configuredPrimarySelector = ConvertTo-SelNetPortSelector -Interface $primaryInterface

        if ($EthParsed.PSObject.Properties.Name -contains "Port1A" -and $EthParsed.Port1A) {
            $port1A = $EthParsed.Port1A
        }
        if ($EthParsed.PSObject.Properties.Name -contains "Port1B" -and $EthParsed.Port1B) {
            $port1B = $EthParsed.Port1B
        }
    }

    return [pscustomobject]@{
        portGroup = "1"
        interfaces = @("1A", "1B")
        primaryInterface = $primaryInterface
        activeInterface = $activeInterface
        configuredPrimarySelector = $configuredPrimarySelector
        netMode = $netMode
        interfaceStatus = [pscustomobject]@{
            "1A" = $port1A
            "1B" = $port1B
        }
        primaryPort = $configuredPrimarySelector
        activePort = (ConvertTo-SelNetPortSelector -Interface $activeInterface)
    }
}

function Invoke-SelPlinkInventoryCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostIp,
        [AllowNull()]
        [string]$AccPassword,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    $promptPattern = "(?m)^\s*=(>>|>)?\s*$"
    $session = Start-SelPlinkSession -HostIp $HostIp -TraceContext $TraceContext

    try {
        $banner = Read-SelSessionAvailable -Session $session -InitialWaitMs 500 -TraceContext $TraceContext
        Send-SelSessionLine -Session $session -Text "" -TraceContext $TraceContext
        $prompt = Read-SelSessionUntil -Session $session -Pattern $promptPattern -TraceContext $TraceContext -ThrowOnTimeout

        Send-SelSessionLine -Session $session -Text "ID" -TraceContext $TraceContext
        $idOut = Read-SelSessionUntil -Session $session -Pattern $promptPattern -TraceContext $TraceContext -ThrowOnTimeout

        $accOut = ""
        $accOk = $false
        $serOut = ""
        $ethOut = ""

        Send-SelSessionLine -Session $session -Text "ACC" -TraceContext $TraceContext
        $accPrompt = Read-SelSessionUntil -Session $session -Pattern "Password:|Invalid Access Level|Command Unavailable|$promptPattern" -TraceContext $TraceContext -ThrowOnTimeout

        if ($accPrompt -match "Password:") {
            if (-not [string]::IsNullOrWhiteSpace($AccPassword)) {
                Send-SelSessionLine -Session $session -Text $AccPassword -TraceContext $TraceContext -Sensitive
                $accResult = Read-SelSessionUntil -Session $session -Pattern $promptPattern -TraceContext $TraceContext -ThrowOnTimeout
                $accOut = $accPrompt + "`n" + $accResult
                if ($accResult -match "(?m)^\s*=>\s*$" -or $accResult -match "Level 1") {
                    $accOk = $true
                }
            }
            else {
                $accOut = $accPrompt
            }
        }
        else {
            $accOut = $accPrompt
            if ($accPrompt -match "(?m)^\s*=>\s*$") {
                $accOk = $true
            }
        }

        if ($accOk) {
            # Use SER for serial/FID/CID capture; STA can stall on some devices due long paged sections.
            Send-SelSessionLine -Session $session -Text "SER" -TraceContext $TraceContext
            $serOut = Read-SelSessionUntil -Session $session -Pattern $promptPattern -TimeoutMs 5000 -TraceContext $TraceContext
            if ([string]::IsNullOrWhiteSpace((Remove-SelControlChars -Text $serOut))) {
                throw ("SER output was empty for host {0}." -f $HostIp)
            }
            Send-SelSessionLine -Session $session -Text "ETH" -TraceContext $TraceContext
            # ETH can end on a partial final line in some sessions; accept best-effort capture if non-empty.
            $ethOut = Read-SelSessionUntil -Session $session -Pattern $promptPattern -TimeoutMs 5000 -TraceContext $TraceContext
            if ([string]::IsNullOrWhiteSpace((Remove-SelControlChars -Text $ethOut))) {
                throw ("ETH output was empty for host {0}." -f $HostIp)
            }
        }

        return [pscustomobject]@{
            Banner = $banner
            Prompt = $prompt
            ID = $idOut
            ACC = $accOut
            AccOk = $accOk
            # Keep STA for compatibility with historical payload shape; STA mirrors SER summary text.
            STA = $serOut
            SER = $serOut
            ETH = $ethOut
        }
    }
    catch {
        Write-SelTrace -TraceContext $TraceContext -Message ("inventory capture exception: {0}" -f $_.Exception.Message)
        throw
    }
    finally {
        Stop-SelPlinkSession -Session $session
    }
}

function Resolve-SelReIpHostIp {
    param(
        [string]$Serial,
        [string]$HostIp,
        [string]$ProfileDefaultIp,
        [string]$DevicesDirectory = (Get-SelDataPath -ChildPath "devices"),
        [string]$DesiredStatePath = (Get-SelDataPath -ChildPath "desiredstate.csv")
    )

    if (-not [string]::IsNullOrWhiteSpace($HostIp)) {
        return [pscustomobject]@{
            HostIp = $HostIp
            Source = "cli"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ProfileDefaultIp)) {
        return [pscustomobject]@{
            HostIp = $ProfileDefaultIp
            Source = "profile-default"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        $jsonCandidate = Get-SelInventoryHostFromDeviceHistory -Serial $Serial -DevicesDirectory $DevicesDirectory
        if ($jsonCandidate) {
            return [pscustomobject]@{
                HostIp = $jsonCandidate.Ip
                Source = "json"
            }
        }

        $desiredCandidate = Get-SelInventoryHostFromDesiredState -Serial $Serial -DesiredStatePath $DesiredStatePath
        if ($desiredCandidate) {
            return [pscustomobject]@{
                HostIp = $desiredCandidate.Ip
                Source = "desiredstate"
            }
        }
    }

    $prompted = Read-Host "Current relay IP"
    if ([string]::IsNullOrWhiteSpace($prompted)) {
        throw "Missing current relay IP. Provide -HostIp, configure DefaultIP in defaults.csv, or enter it when prompted."
    }

    return [pscustomobject]@{
        HostIp = $prompted
        Source = "prompt"
    }
}

function Invoke-SelPingCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostIp,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    Write-SelTrace -TraceContext $TraceContext -Message ("PING preflight host={0}" -f $HostIp)
    $output = (& ping.exe -n 1 $HostIp 2>&1 | Out-String)
    $analysis = Analyze-SelPingOutput -Output $output
    Write-SelTrace -TraceContext $TraceContext -Message ("PING preflight success={0} reason={1}" -f $analysis.Success, $analysis.FailureReason)
    return [pscustomobject]@{
        HostIp = $HostIp
        Success = $analysis.Success
        FailureReason = $analysis.FailureReason
        ReplyCount = $analysis.ReplyCount
        Output = $analysis.Output
    }
}

function Wait-SelPingRecovery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostIp,
        [int]$Count = 100,
        [int]$SettleSeconds = 5,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    Write-SelTrace -TraceContext $TraceContext -Message ("PING recovery host={0} count={1}" -f $HostIp, $Count)
    $output = (& ping.exe -n $Count $HostIp 2>&1 | Out-String)
    $analysis = Analyze-SelPingOutput -Output $output
    $success = $analysis.Success
    if ($success -and $SettleSeconds -gt 0) {
        Start-Sleep -Seconds $SettleSeconds
    }

    Write-SelTrace -TraceContext $TraceContext -Message ("PING recovery success={0} replies={1} reason={2}" -f $success, $analysis.ReplyCount, $analysis.FailureReason)
    return [pscustomobject]@{
        HostIp = $HostIp
        Success = $success
        FailureReason = $analysis.FailureReason
        ReplyCount = $analysis.ReplyCount
        SettleSeconds = $SettleSeconds
        Output = $analysis.Output
    }
}

function Analyze-SelPingOutput {
    param(
        [AllowNull()]
        [string]$Output
    )

    $trimmed = if ($null -eq $Output) { "" } else { $Output.Trim() }
    $replyCount = [regex]::Matches($trimmed, "(?im)^Reply from ").Count

    if ($trimmed -match "(?im)\bDestination host unreachable\b") {
        return [pscustomobject]@{
            Success = $false
            FailureReason = "DestinationHostUnreachable"
            ReplyCount = $replyCount
            Output = $trimmed
        }
    }
    if ($trimmed -match "(?im)\bRequest timed out\b") {
        return [pscustomobject]@{
            Success = $false
            FailureReason = "RequestTimedOut"
            ReplyCount = $replyCount
            Output = $trimmed
        }
    }
    if ($trimmed -match "(?im)\bGeneral failure\b") {
        return [pscustomobject]@{
            Success = $false
            FailureReason = "GeneralFailure"
            ReplyCount = $replyCount
            Output = $trimmed
        }
    }
    if ($trimmed -match "(?im)\bcould not find host\b") {
        return [pscustomobject]@{
            Success = $false
            FailureReason = "HostNotFound"
            ReplyCount = $replyCount
            Output = $trimmed
        }
    }
    if ($trimmed -match "(?im)\bTTL=") {
        return [pscustomobject]@{
            Success = $true
            FailureReason = ""
            ReplyCount = $replyCount
            Output = $trimmed
        }
    }

    return [pscustomobject]@{
        Success = $false
        FailureReason = "NoSuccessfulReply"
        ReplyCount = $replyCount
        Output = $trimmed
    }
}

function ConvertTo-SelIpv4UInt32 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Ip
    )

    $address = [System.Net.IPAddress]::Parse($Ip)
    if ($address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw ("IP address '{0}' is not IPv4." -f $Ip)
    }

    $bytes = $address.GetAddressBytes()
    [Array]::Reverse($bytes)
    return [System.BitConverter]::ToUInt32($bytes, 0)
}

function Get-SelIpv4Range {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartIp,
        [Parameter(Mandatory = $true)]
        [string]$EndIp
    )

    $startValue = ConvertTo-SelIpv4UInt32 -Ip $StartIp
    $endValue = ConvertTo-SelIpv4UInt32 -Ip $EndIp
    if ($endValue -lt $startValue) {
        throw ("IP range end {0} is before start {1}." -f $EndIp, $StartIp)
    }

    $ips = New-Object 'System.Collections.Generic.List[string]'
    for ($value = $startValue; $value -le $endValue; $value++) {
        $bytes = [System.BitConverter]::GetBytes([uint32]$value)
        [Array]::Reverse($bytes)
        $ips.Add(([System.Net.IPAddress]::new($bytes)).ToString())
    }

    return @($ips)
}

function Get-SelLocalIpv4Addresses {
    try {
        return @(
            Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace([string]$_.IPAddress) -and
                    [string]$_.IPAddress -notmatch '^169\.254\.' -and
                    [string]$_.IPAddress -ne '127.0.0.1'
                } |
                Select-Object -ExpandProperty IPAddress
        )
    }
    catch {
        return @()
    }
}

function Test-SelLocalIpv4OnTargetNetwork {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetIp,
        [string]$Mask,
        [string[]]$LocalAddresses = (Get-SelLocalIpv4Addresses)
    )

    if ([string]::IsNullOrWhiteSpace($Mask)) {
        return [pscustomobject]@{
            Success = $true
            Checked = $false
            Reason = "mask-missing"
            MatchingLocalIPs = @()
            LocalIPs = @($LocalAddresses)
            TargetIp = $TargetIp
            Mask = $Mask
        }
    }

    $targetValue = ConvertTo-SelIpv4UInt32 -Ip $TargetIp
    $maskValue = ConvertTo-SelIpv4UInt32 -Ip $Mask
    $targetNetwork = $targetValue -band $maskValue
    $matching = New-Object 'System.Collections.Generic.List[string]'
    foreach ($localIp in @($LocalAddresses)) {
        if ([string]::IsNullOrWhiteSpace([string]$localIp)) {
            continue
        }

        $localNetwork = (ConvertTo-SelIpv4UInt32 -Ip $localIp) -band $maskValue
        if ($localNetwork -eq $targetNetwork) {
            $matching.Add([string]$localIp)
        }
    }

    return [pscustomobject]@{
        Success = ($matching.Count -gt 0)
        Checked = $true
        Reason = $(if ($matching.Count -gt 0) { "match" } else { "no-local-address-on-target-network" })
        MatchingLocalIPs = @($matching)
        LocalIPs = @($LocalAddresses)
        TargetIp = $TargetIp
        Mask = $Mask
    }
}

function Normalize-SelMacAddress {
    param(
        [AllowNull()]
        [string]$Mac
    )

    if ([string]::IsNullOrWhiteSpace($Mac)) {
        return ""
    }

    return (($Mac -replace '[^0-9A-Fa-f]', '').ToUpperInvariant())
}

function Test-SelDesiredStateConflicts {
    param(
        [string]$DesiredStatePath = (Get-SelDataPath -ChildPath "desiredstate.csv")
    )

    $rows = @(Get-SelDesiredStateActiveRows -Path $DesiredStatePath)
    $conflicts = New-Object System.Collections.ArrayList

    foreach ($group in @($rows | Group-Object Serial | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Name) -and $_.Count -gt 1 })) {
        [void]$conflicts.Add([pscustomobject]@{
            Type = "duplicate-serial"
            Key = [string]$group.Name
            Count = [int]$group.Count
            DesiredIPs = (@($group.Group | ForEach-Object { [string]$_.DesiredIP } | Where-Object { $_ }) -join ", ")
            Message = ("Serial {0} appears {1} times in desiredstate.csv." -f [string]$group.Name, [int]$group.Count)
        })
    }

    foreach ($group in @($rows | Group-Object { Normalize-SelMacAddress -Mac ([string]$_.Mac) } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Name) -and $_.Count -gt 1 })) {
        [void]$conflicts.Add([pscustomobject]@{
            Type = "duplicate-mac"
            Key = [string]$group.Name
            Count = [int]$group.Count
            DesiredIPs = (@($group.Group | ForEach-Object { [string]$_.DesiredIP } | Where-Object { $_ }) -join ", ")
            Message = ("MAC {0} appears {1} times in desiredstate.csv." -f [string]$group.Name, [int]$group.Count)
        })
    }

    foreach ($group in @($rows | Group-Object DesiredIP | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Name) -and $_.Count -gt 1 })) {
        [void]$conflicts.Add([pscustomobject]@{
            Type = "duplicate-desiredip"
            Key = [string]$group.Name
            Count = [int]$group.Count
            Serials = (@($group.Group | ForEach-Object { [string]$_.Serial } | Where-Object { $_ }) -join ", ")
            Message = ("Desired IP {0} is assigned to {1} rows in desiredstate.csv." -f [string]$group.Name, [int]$group.Count)
        })
    }

    return [pscustomobject]@{
        IsValid = ($conflicts.Count -eq 0)
        Conflicts = @($conflicts)
        Rows = $rows
    }
}

function Resolve-SelDesiredStateProvisionTarget {
    param(
        [string]$Serial,
        [string]$Mac,
        [string]$DesiredStatePath = (Get-SelDataPath -ChildPath "desiredstate.csv")
    )

    $rows = @(Get-SelDesiredStateActiveRows -Path $DesiredStatePath)
    $serialMatches = @()
    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        $serialMatches = @($rows | Where-Object { ([string]$_.Serial).Trim() -eq $Serial.Trim() })
    }
    if ($serialMatches.Count -eq 1) {
        return [pscustomobject]@{
            Success = $true
            MatchType = "serial"
            Row = $serialMatches[0]
            Message = ""
        }
    }
    if ($serialMatches.Count -gt 1) {
        return [pscustomobject]@{
            Success = $false
            MatchType = "serial"
            Row = $null
            Message = ("Serial {0} matches multiple desiredstate rows." -f $Serial)
        }
    }

    $normalizedMac = Normalize-SelMacAddress -Mac $Mac
    $macMatches = @()
    if (-not [string]::IsNullOrWhiteSpace($normalizedMac)) {
        $macMatches = @($rows | Where-Object { (Normalize-SelMacAddress -Mac ([string]$_.Mac)) -eq $normalizedMac })
    }
    if ($macMatches.Count -eq 1) {
        return [pscustomobject]@{
            Success = $true
            MatchType = "mac"
            Row = $macMatches[0]
            Message = ""
        }
    }
    if ($macMatches.Count -gt 1) {
        return [pscustomobject]@{
            Success = $false
            MatchType = "mac"
            Row = $null
            Message = ("MAC {0} matches multiple desiredstate rows." -f $Mac)
        }
    }

    return [pscustomobject]@{
        Success = $false
        MatchType = ""
        Row = $null
        Message = ("No desiredstate row matched Serial={0} or MAC={1}." -f $Serial, $Mac)
    }
}

function New-SelMassProvisioningRow {
    param(
        [int]$Sequence,
        [string]$Mode,
        [string]$Status,
        [string]$Serial,
        [string]$Mac,
        [string]$OldIp,
        [string]$NewIp,
        [string]$TargetMask,
        [string]$TargetGateway,
        [string]$ObservedMask,
        [string]$ObservedGateway,
        [string]$Note
    )

    return [pscustomobject]@{
        Sequence = [int]$Sequence
        Mode = [string]$Mode
        Status = [string]$Status
        Serial = [string]$Serial
        Mac = [string]$Mac
        OldIp = [string]$OldIp
        NewIp = [string]$NewIp
        TargetMask = [string]$TargetMask
        TargetGateway = [string]$TargetGateway
        ObservedMask = [string]$ObservedMask
        ObservedGateway = [string]$ObservedGateway
        Note = [string]$Note
    }
}

function Show-SelMassProvisioningFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Clear-SelProgressIndicator
    Write-Host ("Mass provisioning failed: {0}" -f $Message)
}

function Get-SelMassProvisioningNextTarget {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("range", "interactive", "desiredstate")]
        [string]$Mode,
        [Parameter(Mandatory = $true)]
        [int]$Sequence,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Defaults,
        [AllowNull()]
        [pscustomobject]$Identity,
        [AllowNull()]
        [string[]]$RangeIps,
        [int]$RangeIndex = 0,
        [string]$CurrentMask,
        [string]$CurrentGateway,
        [string]$DesiredStatePath = (Get-SelDataPath -ChildPath "desiredstate.csv"),
        [scriptblock]$ReadInput = { param([string]$Prompt) Read-Host $Prompt }
    )

    switch ($Mode) {
        "range" {
            if ($RangeIndex -ge @($RangeIps).Count) {
                return [pscustomobject]@{
                    Success = $false
                    Exhausted = $true
                    Message = "No remaining IPs in the selected range."
                }
            }

            $targetIp = [string]$RangeIps[$RangeIndex]
            return [pscustomobject]@{
                Success = $true
                Exhausted = $false
                Consumed = $false
                Ip = $targetIp
                Mask = $(if (-not [string]::IsNullOrWhiteSpace($CurrentMask)) { $CurrentMask } else { [string]$Defaults.TargetSubnetMask })
                Gateway = $(if (-not [string]::IsNullOrWhiteSpace($CurrentGateway)) { $CurrentGateway } else { [string]$Defaults.TargetGateway })
                Source = "range"
                Message = ("Next target IP: {0}" -f $targetIp)
            }
        }
        "interactive" {
            Write-Host ("Detected relay: Serial={0}, MAC={1}, Current IP={2}" -f [string]$Identity.Serial, [string]$Identity.Mac, [string]$Identity.CurrentIp)
            $targetIp = & $ReadInput "Target IP"
            if ([string]::IsNullOrWhiteSpace($targetIp)) {
                return [pscustomobject]@{
                    Success = $false
                    Exhausted = $false
                    Consumed = $false
                    Message = "Target IP entry was blank."
                }
            }

            $maskPrompt = if ([string]::IsNullOrWhiteSpace($CurrentMask)) { "Target subnet mask (blank to keep unchanged)" } else { "Target subnet mask [{0}] (blank to keep current default)" -f $CurrentMask }
            $gatewayPrompt = if ([string]::IsNullOrWhiteSpace($CurrentGateway)) { "Target gateway (blank to keep unchanged)" } else { "Target gateway [{0}] (blank to keep current default)" -f $CurrentGateway }
            $enteredMask = & $ReadInput $maskPrompt
            $enteredGateway = & $ReadInput $gatewayPrompt

            return [pscustomobject]@{
                Success = $true
                Exhausted = $false
                Consumed = $false
                Ip = [string]$targetIp
                Mask = $(if ([string]::IsNullOrWhiteSpace($enteredMask)) { $CurrentMask } else { [string]$enteredMask })
                Gateway = $(if ([string]::IsNullOrWhiteSpace($enteredGateway)) { $CurrentGateway } else { [string]$enteredGateway })
                Source = "interactive"
                Message = ""
            }
        }
        "desiredstate" {
            Write-Host ("Detected relay: Serial={0}, MAC={1}, Current IP={2}" -f [string]$Identity.Serial, [string]$Identity.Mac, [string]$Identity.CurrentIp)
            $match = Resolve-SelDesiredStateProvisionTarget -Serial ([string]$Identity.Serial) -Mac ([string]$Identity.Mac) -DesiredStatePath $DesiredStatePath
            if (-not $match.Success) {
                Write-Host ("No desiredstate match found for detected relay: Serial={0}, MAC={1}, Current IP={2}" -f [string]$Identity.Serial, [string]$Identity.Mac, [string]$Identity.CurrentIp)
                if (-not [string]::IsNullOrWhiteSpace([string]$match.Message)) {
                    Write-Host ("  {0}" -f [string]$match.Message)
                }
                return [pscustomobject]@{
                    Success = $false
                    Exhausted = $false
                    Consumed = $false
                    Message = [string]$match.Message
                }
            }

            $row = $match.Row
            $displayMask = if ([string]::IsNullOrWhiteSpace([string]$row.DesiredSubnetMask)) { "(unchanged)" } else { [string]$row.DesiredSubnetMask }
            $displayGateway = if ([string]::IsNullOrWhiteSpace([string]$row.DesiredGateway)) { "(unchanged)" } else { [string]$row.DesiredGateway }
            Write-Host ("Desiredstate match ({0}): Serial={1}, MAC={2}, Target IP={3}, Mask={4}, Gateway={5}" -f [string]$match.MatchType, [string]$row.Serial, [string]$row.Mac, [string]$row.DesiredIP, $displayMask, $displayGateway)
            return [pscustomobject]@{
                Success = $true
                Exhausted = $false
                Consumed = $false
                Ip = [string]$row.DesiredIP
                Mask = [string]$row.DesiredSubnetMask
                Gateway = [string]$row.DesiredGateway
                Source = ("desiredstate-{0}" -f [string]$match.MatchType)
                DesiredStateRow = $row
                Message = ""
            }
        }
    }
}

function Invoke-SelFastReconnectCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostIp,
        [AllowNull()]
        [string]$AccPassword,
        [AllowNull()]
        [string]$TwoAcPassword,
        [switch]$IncludeSer,
        [int]$Attempts = 8,
        [int]$DelayMs = 400,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    $lastError = ""
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Write-SelTrace -TraceContext $TraceContext -Message ("FAST reconnect attempt={0} host={1}" -f $attempt, $HostIp)
        try {
            $capture = Invoke-SelPlinkIdentityCapture -HostIp $HostIp -AccPassword $AccPassword -TwoAcPassword $TwoAcPassword -IncludeSer:$IncludeSer -TraceContext $TraceContext
            return [pscustomobject]@{
                Success = $true
                AttemptCount = $attempt
                Capture = $capture
                ErrorMessage = ""
            }
        }
        catch {
            $lastError = $_.Exception.Message
            Write-SelTrace -TraceContext $TraceContext -Message ("FAST reconnect failed attempt={0} error=""{1}""" -f $attempt, $lastError)
            if ($attempt -lt $Attempts -and $DelayMs -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }
        }
    }

    return [pscustomobject]@{
        Success = $false
        AttemptCount = $Attempts
        Capture = $null
        ErrorMessage = $lastError
    }
}

function Confirm-SelReIpPlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostIp,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Target,
        [AllowNull()]
        [string]$ObservedSerial,
        [AllowNull()]
        [pscustomobject]$PreEthParsed,
        [switch]$AutoConfirm
    )

    Clear-SelProgressIndicator
    Write-Host ""
    Write-Host "Re-IP Confirmation"
    Write-Host ("  Current IP: {0}" -f $HostIp)
    if (-not [string]::IsNullOrWhiteSpace($ObservedSerial)) {
        Write-Host ("  Observed Serial: {0}" -f $ObservedSerial)
    }
    if ($PreEthParsed) {
        if (-not [string]::IsNullOrWhiteSpace([string]$PreEthParsed.IP)) {
            Write-Host ("  Observed ETH IP: {0}" -f ([string]$PreEthParsed.IP))
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$PreEthParsed.PrimaryInterface)) {
            Write-Host ("  Observed Primary Interface: {0}" -f ([string]$PreEthParsed.PrimaryInterface))
        }
    }
    Write-Host ("  Target IP: {0}" -f $Target.Ip)
    Write-Host ("  Target Mask: {0}" -f $(if ([string]::IsNullOrWhiteSpace([string]$Target.Mask)) { "(unchanged)" } else { [string]$Target.Mask }))
    Write-Host ("  Target Gateway: {0}" -f $(if ([string]::IsNullOrWhiteSpace([string]$Target.Gateway)) { "(unchanged)" } else { [string]$Target.Gateway }))

    if ($AutoConfirm) {
        Write-Host "  Auto-confirm: yes"
        return $true
    }

    $choice = Read-Host "Apply these settings? (y/N)"
    return ($choice -match "^(?i)y(es)?$")
}

function Enter-SelAccAccess {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Session,
        [AllowNull()]
        [string]$Password,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    $promptPattern = "(?m)^\s*=(>>|>)?\s*$"
    Send-SelSessionLine -Session $Session -Text "ACC" -TraceContext $TraceContext
    $response = Read-SelSessionUntil -Session $Session -Pattern ("Password:|Invalid Access Level|Command Unavailable|{0}" -f $promptPattern) -TraceContext $TraceContext -ThrowOnTimeout
    if ($response -match "Password:") {
        if ([string]::IsNullOrWhiteSpace($Password)) {
            $Password = Read-SelSensitiveValue -Prompt "ACC Password"
        }
        Send-SelSessionLine -Session $Session -Text $Password -TraceContext $TraceContext -Sensitive
        $response = $response + "`n" + (Read-SelSessionUntil -Session $Session -Pattern $promptPattern -TraceContext $TraceContext -ThrowOnTimeout)
    }

    $ok = ($response -match "(?m)^\s*=>\s*$" -or $response -match "(?m)^\s*=>>\s*$" -or $response -match "Level 1" -or $response -match "Level 2")
    return [pscustomobject]@{
        Success = $ok
        Output = $response
        AccessLevel = $(if ($ok) { "ACC" } else { "" })
    }
}

function Enter-Sel2AcAccess {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Session,
        [AllowNull()]
        [string]$Password,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    $promptPattern = "(?m)^\s*=(>>|>)?\s*$"
    Send-SelSessionLine -Session $Session -Text "2AC" -TraceContext $TraceContext
    $response = Read-SelSessionUntil -Session $Session -Pattern ("Password:|Invalid Access Level|Command Unavailable|{0}" -f $promptPattern) -TraceContext $TraceContext -ThrowOnTimeout
    if ($response -match "Password:") {
        if ([string]::IsNullOrWhiteSpace($Password)) {
            $Password = Read-SelSensitiveValue -Prompt "2AC Password"
        }
        Send-SelSessionLine -Session $Session -Text $Password -TraceContext $TraceContext -Sensitive
        $response = $response + "`n" + (Read-SelSessionUntil -Session $Session -Pattern $promptPattern -TraceContext $TraceContext -ThrowOnTimeout)
    }

    $ok = ($response -match "(?m)^\s*=>>\s*$" -or $response -match "Level 2")
    return [pscustomobject]@{
        Success = $ok
        Output = $response
        AccessLevel = $(if ($ok) { "2AC" } else { "" })
    }
}

function Enter-SelReIpAccess {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Session,
        [AllowNull()]
        [string]$AccPassword,
        [AllowNull()]
        [string]$TwoAcPassword,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    $acc = Enter-SelAccAccess -Session $Session -Password $AccPassword -TraceContext $TraceContext
    if (-not $acc.Success) {
        return [pscustomobject]@{
            Success = $false
            AccessLevel = ""
            ACC = $acc
            TwoAC = $null
        }
    }

    $twoAc = Enter-Sel2AcAccess -Session $Session -Password $TwoAcPassword -TraceContext $TraceContext
    return [pscustomobject]@{
        Success = [bool]$twoAc.Success
        AccessLevel = $(if ($twoAc.Success) { "2AC" } else { "" })
        ACC = $acc
        TwoAC = $twoAc
    }
}

function Invoke-SelReIpSetPort1 {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Session,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Target,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    $promptPattern = "(?m)^\s*=(>>|>)?\s*$"
    $summaryPattern = "(?is)\bPort 1\b[\s\S]*\bIPADDR\s+:=\s*.*\bSUBNETM\s+:=\s*.*\bDEFRTR\s+:="
    $waitPattern = ("Invalid Access Level|Command Unavailable|(?im)\b[A-Z0-9]+\s*:=[\s\S]*?(?:\n\s*\?|\s+\?\s*$)|(?im)Save changes \(Y,N\)\?|(?im)Settings Saved|{0}|{1}" -f $summaryPattern, $promptPattern)
    $desiredByField = @{
        "IPADDR" = $Target.Ip
        "SUBNETM" = $Target.Mask
        "DEFRTR" = $Target.Gateway
    }

    Send-SelSessionLine -Session $Session -Text "SET P 1" -TraceContext $TraceContext
    $response = Read-SelSessionUntil -Session $Session -Pattern $waitPattern -TimeoutMs 10000 -TraceContext $TraceContext -ThrowOnTimeout

    $steps = @()
    $saveSent = $false
    $settingsSaved = $false

    for ($i = 0; $i -lt 200; $i++) {
        $clean = Remove-SelControlChars -Text $response
        if ($clean -match "Invalid Access Level|Command Unavailable") {
            throw "SET P 1 was denied at 2AC."
        }

        if ($clean -match "(?im)Settings Saved") {
            $settingsSaved = $true
            break
        }
        elseif ($clean -match "(?im)Save changes \(Y,N\)\?\s*$") {
            $answer = "Y"
            $saveSent = $true
            $steps += [pscustomobject]@{ Field = "SAVE"; Value = $answer }
            Send-SelSessionLine -Session $Session -Text $answer -TraceContext $TraceContext
        }
        elseif ($clean -match "(?im)\b([A-Z0-9]+)\s*:=[\s\S]*?(?:\n\s*\?|\s+\?)\s*$") {
            $field = $Matches[1].ToUpperInvariant()
            $value = ""
            if ($desiredByField.ContainsKey($field)) {
                $value = [string]$desiredByField[$field]
            }
            $steps += [pscustomobject]@{ Field = $field; Value = $value }
            Send-SelSessionLine -Session $Session -Text $value -TraceContext $TraceContext
        }
        elseif ($clean -match $summaryPattern) {
            $steps += [pscustomobject]@{ Field = "SUMMARY"; Value = "" }
            Send-SelSessionLine -Session $Session -Text "" -TraceContext $TraceContext
        }
        elseif ($saveSent -and $Session.Process.HasExited) {
            break
        }
        elseif ($clean -match $promptPattern) {
            break
        }
        else {
            $steps += [pscustomobject]@{ Field = ""; Value = "" }
            Send-SelSessionLine -Session $Session -Text "" -TraceContext $TraceContext
        }

        if ($saveSent) {
            try {
                $response = Read-SelSessionUntil -Session $Session -Pattern $waitPattern -TimeoutMs 3000 -TraceContext $TraceContext
            }
            catch {
                break
            }
            if ($Session.Process.HasExited) {
                break
            }
        }
        else {
            $response = Read-SelSessionUntil -Session $Session -Pattern $waitPattern -TimeoutMs 6000 -TraceContext $TraceContext -ThrowOnTimeout
        }
    }

    return [pscustomobject]@{
        Success = $true
        SaveSent = $saveSent
        SettingsSaved = $settingsSaved
        Output = $response
        Steps = $steps
    }
}

function Invoke-SelPlinkReIpCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostIp,
        [AllowNull()]
        [string]$AccPassword,
        [AllowNull()]
        [string]$TwoAcPassword,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Target,
        [switch]$IncludeSer,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    $promptPattern = "(?m)^\s*=(>>|>)?\s*$"
    $session = Start-SelPlinkSession -HostIp $HostIp -TraceContext $TraceContext

    try {
        $banner = Read-SelSessionAvailable -Session $session -InitialWaitMs 500 -TraceContext $TraceContext
        Send-SelSessionLine -Session $session -Text "" -TraceContext $TraceContext
        $prompt = Read-SelSessionUntil -Session $session -Pattern $promptPattern -TraceContext $TraceContext -ThrowOnTimeout

        Send-SelSessionLine -Session $session -Text "ID" -TraceContext $TraceContext
        $idOut = Read-SelSessionUntil -Session $session -Pattern $promptPattern -TraceContext $TraceContext -ThrowOnTimeout

        $access = Enter-SelReIpAccess -Session $session -AccPassword $AccPassword -TwoAcPassword $TwoAcPassword -TraceContext $TraceContext
        if (-not $access.Success) {
            throw "Unable to enter ACC/2AC access for re-IP."
        }

        $serOut = ""
        if ($IncludeSer) {
            # Re-IP uses STA for quick serial/FID/CID capture without pulling SER event history.
            Send-SelSessionLine -Session $session -Text "STA" -TraceContext $TraceContext
            $serOut = Read-SelSessionUntil -Session $session -Pattern $promptPattern -TimeoutMs 5000 -TraceContext $TraceContext
        }
        Send-SelSessionLine -Session $session -Text "ETH" -TraceContext $TraceContext
        $ethOut = Read-SelSessionUntil -Session $session -Pattern $promptPattern -TimeoutMs 5000 -TraceContext $TraceContext

        return [pscustomobject]@{
            Banner = $banner
            Prompt = $prompt
            ID = $idOut
            Access = $access
            SER = $serOut
            ETH = $ethOut
            Session = $session
        }
    }
    catch {
        Stop-SelPlinkSession -Session $session
        throw
    }
}

function Invoke-SelPlinkIdentityCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostIp,
        [AllowNull()]
        [string]$AccPassword,
        [AllowNull()]
        [string]$TwoAcPassword,
        [switch]$IncludeSer,
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    $promptPattern = "(?m)^\s*=(>>|>)?\s*$"
    $session = Start-SelPlinkSession -HostIp $HostIp -TraceContext $TraceContext
    try {
        $banner = Read-SelSessionAvailable -Session $session -InitialWaitMs 500 -TraceContext $TraceContext
        Send-SelSessionLine -Session $session -Text "" -TraceContext $TraceContext
        $prompt = Read-SelSessionUntil -Session $session -Pattern $promptPattern -TraceContext $TraceContext -ThrowOnTimeout

        Send-SelSessionLine -Session $session -Text "ID" -TraceContext $TraceContext
        $idOut = Read-SelSessionUntil -Session $session -Pattern $promptPattern -TraceContext $TraceContext -ThrowOnTimeout

        $serOut = ""
        $ethOut = ""
        $access = Enter-SelReIpAccess -Session $session -AccPassword $AccPassword -TwoAcPassword $TwoAcPassword -TraceContext $TraceContext
        if ($access.Success) {
            if ($IncludeSer) {
                # Re-IP uses STA for quick serial/FID/CID capture without pulling SER event history.
                Send-SelSessionLine -Session $session -Text "STA" -TraceContext $TraceContext
                $serOut = Read-SelSessionUntil -Session $session -Pattern $promptPattern -TimeoutMs 5000 -TraceContext $TraceContext
            }
            Send-SelSessionLine -Session $session -Text "ETH" -TraceContext $TraceContext
            $ethOut = Read-SelSessionUntil -Session $session -Pattern $promptPattern -TimeoutMs 5000 -TraceContext $TraceContext
            if ($ethOut -match "(?im)\bMAC:\s|\bIP ADDRESS:\s|\bSUBNET MASK:\s|\bDEFAULT GATEWAY:\s") {
                Write-SelTrace -TraceContext $TraceContext -Message "ETH capture accepted without trailing prompt."
            }
        }

        return [pscustomobject]@{
            Banner = $banner
            Prompt = $prompt
            ID = $idOut
            SER = $serOut
            ETH = $ethOut
            Access = $access
        }
    }
    finally {
        Stop-SelPlinkSession -Session $session
    }
}

function Test-SelDesiredStateRowActive {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Row
    )

    $serial = [string]$Row.Serial
    if ([string]::IsNullOrWhiteSpace($serial)) {
        return $false
    }

    if ($serial.Trim().ToUpperInvariant() -eq "TEMPLATE") {
        return $false
    }

    if ($Row.PSObject.Properties.Name -contains "Active") {
        return (ConvertTo-SelBool -Value ([string]$Row.Active))
    }

    return $true
}

function Get-SelDesiredStateRows {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-SelDataPath -ChildPath "desiredstate.csv")
    )

    if (-not (Test-Path $Path)) {
        return @()
    }

    return @(Import-Csv -Path $Path)
}

function Get-SelDesiredStateActiveRows {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-SelDataPath -ChildPath "desiredstate.csv")
    )

    $rows = Get-SelDesiredStateRows -Path $Path
    return @($rows | Where-Object { Test-SelDesiredStateRowActive -Row $_ })
}

function Get-SelDesiredStateMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Serial,
        [Parameter(Mandatory = $false)]
        [string]$DesiredStatePath = (Get-SelDataPath -ChildPath "desiredstate.csv")
    )

    if ([string]::IsNullOrWhiteSpace($Serial)) {
        return [pscustomobject]@{
            Name = ""
            Description = ""
        }
    }

    $row = Get-SelDesiredStateRows -Path $DesiredStatePath | Where-Object { $_.Serial -eq $Serial } | Select-Object -First 1
    if (-not $row) {
        return [pscustomobject]@{
            Name = ""
            Description = ""
        }
    }

    $name = ""
    if ($row.PSObject.Properties.Name -contains "Name") {
        $name = [string]$row.Name
    }
    $description = ""
    if ($row.PSObject.Properties.Name -contains "Description") {
        $description = [string]$row.Description
    }

    return [pscustomobject]@{
        Name = $name
        Description = $description
    }
}

function Resolve-SelReIpTarget {
    param(
        [string]$Serial,
        [string]$Ip,
        [string]$Mask,
        [string]$Gateway,
        [string]$PrimaryInterface,
        [string]$DesiredStatePath = (Get-SelDataPath -ChildPath "desiredstate.csv"),
        [switch]$PromptIfMissing,
        [string]$DefaultIp
    )

    $resolvedIp = $Ip
    $resolvedMask = $Mask
    $resolvedGateway = $Gateway
    $source = "cli"

    if ((-not $resolvedIp -or -not $resolvedMask -or -not $resolvedGateway) -and $Serial) {
        $row = Get-SelDesiredStateActiveRows -Path $DesiredStatePath | Where-Object { $_.Serial -eq $Serial } | Select-Object -First 1
        if ($row) {
            if (-not $resolvedIp) { $resolvedIp = [string]$row.DesiredIP }
            if (-not $resolvedMask) { $resolvedMask = [string]$row.DesiredSubnetMask }
            if (-not $resolvedGateway) { $resolvedGateway = [string]$row.DesiredGateway }
            if ($resolvedIp -or $resolvedMask -or $resolvedGateway) {
                $source = "desiredstate"
            }
        }
    }

    if ($PromptIfMissing) {
        if (-not $resolvedIp) { $resolvedIp = Read-SelPromptWithDefault -Prompt "Target IP" -DefaultValue $DefaultIp }
        if ($source -eq "cli" -and ($Ip -ne $resolvedIp -or $Mask -ne $resolvedMask -or $Gateway -ne $resolvedGateway)) {
            $source = "prompt"
        }
    }

    if (-not $resolvedIp) {
        throw "Missing reip values. Provide a target IP via CLI, desiredstate.csv, or prompt input."
    }

    return [pscustomobject]@{
        Serial = $Serial
        Ip = $resolvedIp
        Mask = $resolvedMask
        Gateway = $resolvedGateway
        PrimaryInterface = ""
        NetPort = ""
        Source = $source
    }
}

function Update-SelDesiredStateObserved {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $false)]
        [string]$Mac,
        [Parameter(Mandatory = $false)]
        [string]$ObservedIP,
        [Parameter(Mandatory = $false)]
        [string]$ObservedFirmwareLabel,
        [Parameter(Mandatory = $false)]
        [string]$ObservedFid,
        [Parameter(Mandatory = $false)]
        [string]$ObservedPrimaryInterface,
        [Parameter(Mandatory = $false)]
        [string]$ObservedActiveInterface,
        [Parameter(Mandatory = $false)]
        [string]$ObservedNetMode,
        [Parameter(Mandatory = $false)]
        [string]$Name,
        [Parameter(Mandatory = $false)]
        [string]$Description,
        [Parameter(Mandatory = $false)]
        [string]$LastAction = "inventory",
        [Parameter(Mandatory = $false)]
        [string]$LastResult = "success",
        [Parameter(Mandatory = $false)]
        [string]$DesiredStatePath = (Get-SelDataPath -ChildPath "desiredstate.csv")
    )

    $rows = @()
    if (Test-Path $DesiredStatePath) {
        $rows = @(Import-Csv -Path $DesiredStatePath)
    }

    $existing = $rows | Where-Object { $_.Serial -eq $Serial } | Select-Object -First 1
    if (-not $existing) {
        $existing = [ordered]@{
            Serial = $Serial
            Active = "TRUE"
            Name = ""
            Description = ""
            Mac = $Mac
            DesiredIP = ""
            DesiredSubnetMask = ""
            DesiredGateway = ""
            DesiredPrimaryInterface = ""
            DesiredFirmwareLabel = ""
            DesiredConfigSha256 = ""
            ObservedIP = ""
            ObservedPrimaryInterface = ""
            ObservedActiveInterface = ""
            ObservedNetMode = ""
            ObservedFirmwareLabel = ""
            ObservedFid = ""
            LastSeen = ""
            LastAction = ""
            LastResult = ""
            Notes = "Auto-added by inventory"
        }
        $rows += [pscustomobject]$existing
        $existing = $rows[-1]
    }

    if (-not ($existing.PSObject.Properties.Name -contains "Name")) {
        Add-Member -InputObject $existing -MemberType NoteProperty -Name "Name" -Value ""
    }
    if (-not ($existing.PSObject.Properties.Name -contains "Description")) {
        Add-Member -InputObject $existing -MemberType NoteProperty -Name "Description" -Value ""
    }
    if (-not ($existing.PSObject.Properties.Name -contains "DesiredPrimaryInterface")) {
        Add-Member -InputObject $existing -MemberType NoteProperty -Name "DesiredPrimaryInterface" -Value ""
    }
    if (-not ($existing.PSObject.Properties.Name -contains "ObservedPrimaryInterface")) {
        Add-Member -InputObject $existing -MemberType NoteProperty -Name "ObservedPrimaryInterface" -Value ""
    }
    if (-not ($existing.PSObject.Properties.Name -contains "ObservedActiveInterface")) {
        Add-Member -InputObject $existing -MemberType NoteProperty -Name "ObservedActiveInterface" -Value ""
    }
    if (-not ($existing.PSObject.Properties.Name -contains "ObservedNetMode")) {
        Add-Member -InputObject $existing -MemberType NoteProperty -Name "ObservedNetMode" -Value ""
    }

    if ($Name) { $existing.Name = $Name }
    if ($Description) { $existing.Description = $Description }
    if ($Mac) { $existing.Mac = $Mac }
    if ($ObservedIP) { $existing.ObservedIP = $ObservedIP }
    if ($ObservedPrimaryInterface) { $existing.ObservedPrimaryInterface = $ObservedPrimaryInterface }
    if ($ObservedActiveInterface) { $existing.ObservedActiveInterface = $ObservedActiveInterface }
    if ($ObservedNetMode) { $existing.ObservedNetMode = $ObservedNetMode }
    if ($ObservedFirmwareLabel) { $existing.ObservedFirmwareLabel = $ObservedFirmwareLabel }
    if ($ObservedFid) { $existing.ObservedFid = $ObservedFid }
    $existing.LastSeen = (Get-Date).ToString("s")
    $existing.LastAction = $LastAction
    $existing.LastResult = $LastResult

    foreach ($row in $rows) {
        if (-not ($row.PSObject.Properties.Name -contains "Name")) {
            Add-Member -InputObject $row -MemberType NoteProperty -Name "Name" -Value ""
        }
        if (-not ($row.PSObject.Properties.Name -contains "Description")) {
            Add-Member -InputObject $row -MemberType NoteProperty -Name "Description" -Value ""
        }
        if (-not ($row.PSObject.Properties.Name -contains "DesiredPrimaryInterface")) {
            Add-Member -InputObject $row -MemberType NoteProperty -Name "DesiredPrimaryInterface" -Value ""
        }
        if (-not ($row.PSObject.Properties.Name -contains "ObservedPrimaryInterface")) {
            Add-Member -InputObject $row -MemberType NoteProperty -Name "ObservedPrimaryInterface" -Value ""
        }
        if (-not ($row.PSObject.Properties.Name -contains "ObservedActiveInterface")) {
            Add-Member -InputObject $row -MemberType NoteProperty -Name "ObservedActiveInterface" -Value ""
        }
        if (-not ($row.PSObject.Properties.Name -contains "ObservedNetMode")) {
            Add-Member -InputObject $row -MemberType NoteProperty -Name "ObservedNetMode" -Value ""
        }
    }

    $tempPath = $DesiredStatePath + ".tmp"
    $lastError = $null
    for ($i = 0; $i -lt 6; $i++) {
        try {
            $rows | Export-Csv -Path $tempPath -NoTypeInformation -ErrorAction Stop
            if (Test-Path $DesiredStatePath) {
                Remove-Item -Path $DesiredStatePath -Force -ErrorAction Stop
            }
            Move-Item -Path $tempPath -Destination $DesiredStatePath -ErrorAction Stop
            $lastError = $null
            break
        }
        catch {
            $lastError = $_
            Start-Sleep -Milliseconds (200 * ($i + 1))
        }
    }

    if ($lastError) {
        throw ("Failed to write desiredstate.csv after retries: {0}" -f $lastError.Exception.Message)
    }
}

function Add-SelDeviceEvent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Event,
        [Parameter(Mandatory = $false)]
        [string]$DevicesDirectory = (Get-SelDataPath -ChildPath "devices")
    )

    if (-not (Test-Path $DevicesDirectory)) {
        New-Item -ItemType Directory -Path $DevicesDirectory | Out-Null
    }

    $path = Join-Path $DevicesDirectory ($Serial + ".json")
    if (Test-Path $path) {
        $content = Get-Content $path -Raw
        $doc = ConvertFrom-Json $content
    }
    else {
        $doc = [pscustomobject]@{
            serial = $Serial
            name = ""
            description = ""
            events = @()
        }
    }

    if (-not ($doc.PSObject.Properties.Name -contains "name")) {
        Add-Member -InputObject $doc -MemberType NoteProperty -Name "name" -Value ""
    }
    if (-not ($doc.PSObject.Properties.Name -contains "description")) {
        Add-Member -InputObject $doc -MemberType NoteProperty -Name "description" -Value ""
    }
    if ($Event.PSObject.Properties.Name -contains "identity") {
        if ($Event.identity.PSObject.Properties.Name -contains "name" -and -not [string]::IsNullOrWhiteSpace([string]$Event.identity.name)) {
            $doc.name = [string]$Event.identity.name
        }
        if ($Event.identity.PSObject.Properties.Name -contains "description" -and -not [string]::IsNullOrWhiteSpace([string]$Event.identity.description)) {
            $doc.description = [string]$Event.identity.description
        }
    }

    $events = @($doc.events)
    $events += $Event
    $doc.events = $events
    $doc | ConvertTo-Json -Depth 8 | Set-Content $path
}

function Get-SelSha256Hex {
    param(
        [AllowNull()]
        [string]$Text
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
        $hash = $sha.ComputeHash($bytes)
        return (-join ($hash | ForEach-Object { $_.ToString("x2") }))
    }
    finally {
        $sha.Dispose()
    }
}

function Normalize-SelSerText {
    param(
        [AllowNull()]
        [string]$Text
    )

    $v = [string]$Text
    $v = $v.Trim().ToLowerInvariant()
    $v = [regex]::Replace($v, "\s+", " ")
    return $v
}

function Get-SelSerEventKey {
    param(
        [AllowNull()]
        [string]$Ts,
        [AllowNull()]
        [string]$Event,
        [AllowNull()]
        [string]$State,
        [AllowNull()]
        [string]$Code,
        [AllowNull()]
        [string]$Raw
    )

    $normTs = Normalize-SelSerText -Text $Ts
    $normEvent = Normalize-SelSerText -Text $Event
    $normState = Normalize-SelSerText -Text $State
    $normCode = Normalize-SelSerText -Text $Code
    if (-not [string]::IsNullOrWhiteSpace($normTs)) {
        return ("ts|{0}|{1}|{2}|{3}" -f $normTs, $normEvent, $normState, $normCode)
    }

    $normRaw = Normalize-SelSerText -Text $Raw
    return ("raw|{0}" -f (Get-SelSha256Hex -Text $normRaw))
}

function Get-SelSerRecordKey {
    param(
        [AllowNull()]
        [pscustomobject]$Record
    )

    if ($null -eq $Record) {
        return ""
    }

    return (Get-SelSerEventKey -Ts ([string]$Record.ts) -Event ([string]$Record.event) -State ([string]$Record.state) -Code ([string]$Record.code) -Raw ([string]$Record.raw))
}

function Test-SelSerNoiseLine {
    param(
        [AllowNull()]
        [string]$Line
    )

    $clean = Remove-SelControlChars -Text $Line
    $trim = $clean.Trim()
    if ([string]::IsNullOrWhiteSpace($trim)) { return $true }
    if ($trim -match "^\s*=(>>|>)?\s*$") { return $true }
    if ($trim -match "^\s*=?\s*(ID|ACC|SER|ETH|EXIT)\s*$") { return $true }
    if ($trim -match "TERMINAL SERVER") { return $true }
    if ($trim -match "^SEL-\d+") { return $true }
    if ($trim -match "^FEEDER RELAY") { return $true }
    if ($trim -match "^Level\s+\d+") { return $true }
    if ($trim -match "Time Source:") { return $true }
    if ($trim -match "Date:\s*\d{1,2}/\d{1,2}/\d{4}") { return $true }
    if ($trim -match "^Password:") { return $true }
    return $false
}

function ConvertFrom-SelSerEventRecords {
    param(
        [AllowNull()]
        [string]$Text,
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        [Parameter(Mandatory = $true)]
        [string]$RawArchivePath
    )

    $clean = Remove-SelControlChars -Text $Text
    $records = @()
    $lines = $clean -split "`r?`n"
    foreach ($line in $lines) {
        if (Test-SelSerNoiseLine -Line $line) {
            continue
        }

        $raw = $line.Trim()
        $ts = ""
        $eventText = $raw
        $state = ""
        $code = ""

        if ($raw -match "^(?<ts>\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}:\d{2}(?:\.\d+)?)\s+(?<msg>.+)$") {
            $ts = $Matches.ts.Trim()
            $eventText = $Matches.msg.Trim()
        }
        elseif ($raw -match "^(?<ts>\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+\-]\d{2}:\d{2})?)\s+(?<msg>.+)$") {
            $ts = $Matches.ts.Trim()
            $eventText = $Matches.msg.Trim()
        }

        $statePatterns = @(
            "\bDEASSERT(?:ED)?\b",
            "\bASSERT(?:ED)?\b",
            "\bOPEN\b",
            "\bCLOSE\b",
            "\bTRIP\b",
            "\bRESET\b",
            "\bSET\b",
            "\bOFF\b",
            "\bON\b"
        )
        foreach ($pat in $statePatterns) {
            if ($eventText -match $pat) {
                $state = $Matches[0].ToUpperInvariant()
                break
            }
        }
        if ($eventText -match "\b([A-Z]{1,5}\d{1,6})\b") {
            $code = $Matches[1]
        }

        $records += [pscustomobject]@{
            ts = $ts
            serial = $Serial
            source = "SER"
            event = $eventText
            state = $state
            code = $code
            raw = $raw
            runId = $RunId
            rawArchive = $RawArchivePath
        }
    }

    return $records
}

function Write-SelSerEventStore {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [AllowNull()]
        [string]$RawSerText,
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        [Parameter(Mandatory = $false)]
        [string]$EventsRoot = (Get-SelDataPath -ChildPath "events"),
        [AllowNull()]
        [pscustomobject]$TraceContext
    )

    $serialDir = Join-Path $EventsRoot $Serial
    if (-not (Test-Path $serialDir)) {
        New-Item -ItemType Directory -Path $serialDir -Force | Out-Null
    }

    $tsForFile = (Get-Date).ToString("yyyy-MM-ddTHH-mm-ss")
    $rawArchiveName = ("{0}-ser.txt" -f $tsForFile)
    $rawArchiveFullPath = Join-Path $serialDir $rawArchiveName
    $eventStoreFullPath = Join-Path $serialDir "ser.jsonl"
    $rawArchiveRelPath = ("data/events/{0}/{1}" -f $Serial, $rawArchiveName)
    $eventStoreRelPath = ("data/events/{0}/ser.jsonl" -f $Serial)

    $rawClean = Remove-SelControlChars -Text $RawSerText
    Set-Content -Path $rawArchiveFullPath -Value $rawClean -Encoding UTF8
    Write-SelTrace -TraceContext $TraceContext -Message ("ser pull raw archive written: {0}" -f $rawArchiveRelPath)

    $parsed = @(ConvertFrom-SelSerEventRecords -Text $rawClean -Serial $Serial -RunId $RunId -RawArchivePath $rawArchiveRelPath)
    $existingKeys = New-Object 'System.Collections.Generic.HashSet[string]'

    if (Test-Path $eventStoreFullPath) {
        foreach ($line in @(Get-Content -Path $eventStoreFullPath)) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            try {
                $record = $line | ConvertFrom-Json
                $key = Get-SelSerRecordKey -Record $record
                if (-not [string]::IsNullOrWhiteSpace($key)) {
                    [void]$existingKeys.Add($key)
                }
            }
            catch {
                continue
            }
        }
    }

    $entriesAdded = 0
    foreach ($record in $parsed) {
        $key = Get-SelSerRecordKey -Record $record
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }
        if ($existingKeys.Contains($key)) {
            continue
        }
        [void]$existingKeys.Add($key)
        $jsonLine = $record | ConvertTo-Json -Compress
        Add-Content -Path $eventStoreFullPath -Value $jsonLine -Encoding UTF8
        $entriesAdded++
    }

    Write-SelTrace -TraceContext $TraceContext -Message ("ser pull parsed={0} added={1} store={2}" -f $parsed.Count, $entriesAdded, $eventStoreRelPath)
    return [pscustomobject]@{
        Result = "success"
        ParsedCount = $parsed.Count
        EntriesAdded = $entriesAdded
        EventStorePath = $eventStoreRelPath
        RawArchivePath = $rawArchiveRelPath
    }
}

function Get-SelDeviceMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Serial,
        [Parameter(Mandatory = $false)]
        [string]$DevicesDirectory = (Get-SelDataPath -ChildPath "devices")
    )

    if ([string]::IsNullOrWhiteSpace($Serial)) {
        return [pscustomobject]@{
            Name = ""
            Description = ""
        }
    }

    $path = Join-Path $DevicesDirectory ($Serial + ".json")
    if (-not (Test-Path $path)) {
        return [pscustomobject]@{
            Name = ""
            Description = ""
        }
    }

    try {
        $doc = Get-Content $path -Raw | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{
            Name = ""
            Description = ""
        }
    }

    $name = ""
    if ($doc.PSObject.Properties.Name -contains "name") {
        $name = [string]$doc.name
    }
    $description = ""
    if ($doc.PSObject.Properties.Name -contains "description") {
        $description = [string]$doc.description
    }

    return [pscustomobject]@{
        Name = $name
        Description = $description
    }
}

function Resolve-SelMetadata {
    param(
        [AllowNull()]
        [pscustomobject]$DesiredStateMetadata,
        [AllowNull()]
        [pscustomobject]$DeviceMetadata
    )

    $name = ""
    $description = ""

    if ($DesiredStateMetadata) {
        $name = [string]$DesiredStateMetadata.Name
        $description = [string]$DesiredStateMetadata.Description
    }

    if ([string]::IsNullOrWhiteSpace($name) -and $DeviceMetadata) {
        $name = [string]$DeviceMetadata.Name
    }
    if ([string]::IsNullOrWhiteSpace($description) -and $DeviceMetadata) {
        $description = [string]$DeviceMetadata.Description
    }

    return [pscustomobject]@{
        Name = $name
        Description = $description
    }
}

function Get-SelLatestInventorySnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $false)]
        [string]$DevicesDirectory = (Get-SelDataPath -ChildPath "devices")
    )

    $path = Join-Path $DevicesDirectory ($Serial + ".json")
    if (-not (Test-Path $path)) {
        return $null
    }

    try {
        $doc = Get-Content $path -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }

    $latest = @($doc.events |
        Where-Object { $_.action -eq "inventory" } |
        Sort-Object -Property @{ Expression = { [string]$_.timestamp }; Descending = $true } |
        Select-Object -First 1)

    if (-not $latest -or $latest.Count -eq 0) {
        return $null
    }

    $evt = $latest[0]
    $fid = [string]$evt.inventory.STA.FID
    if ([string]::IsNullOrWhiteSpace($fid)) {
        $fid = [string]$evt.inventory.ID.FID
    }
    $cid = [string]$evt.inventory.STA.CID
    if ([string]::IsNullOrWhiteSpace($cid)) {
        $cid = [string]$evt.inventory.ID.CID
    }

    return [pscustomobject]@{
        Timestamp = [string]$evt.timestamp
        HostIp = [string]$evt.hostIp
        ObservedIp = [string]$evt.inventory.ETH.IP
        Mac = [string]$evt.inventory.ETH.MAC
        Fid = $fid
        Cid = $cid
    }
}

function Get-SelInventoryChangeSummary {
    param(
        [AllowNull()]
        [pscustomobject]$Previous,
        [Parameter(Mandatory = $true)]
        [string]$HostIp,
        [Parameter(Mandatory = $true)]
        [string]$ObservedIp,
        [Parameter(Mandatory = $true)]
        [string]$Mac,
        [Parameter(Mandatory = $true)]
        [string]$Fid,
        [Parameter(Mandatory = $true)]
        [string]$Cid
    )

    $changes = @()
    if ($null -eq $Previous) {
        return $changes
    }

    $pairs = @(
        @{ Name = "Host IP"; Old = [string]$Previous.HostIp; New = [string]$HostIp },
        @{ Name = "Observed IP"; Old = [string]$Previous.ObservedIp; New = [string]$ObservedIp },
        @{ Name = "MAC"; Old = [string]$Previous.Mac; New = [string]$Mac },
        @{ Name = "FID"; Old = [string]$Previous.Fid; New = [string]$Fid },
        @{ Name = "CID"; Old = [string]$Previous.Cid; New = [string]$Cid }
    )

    foreach ($p in $pairs) {
        if ($p.Old -ne $p.New) {
            $oldVal = $p.Old
            if ([string]::IsNullOrWhiteSpace($oldVal)) { $oldVal = "<blank>" }
            $newVal = $p.New
            if ([string]::IsNullOrWhiteSpace($newVal)) { $newVal = "<blank>" }
            $changes += ("{0}: {1} -> {2}" -f $p.Name, $oldVal, $newVal)
        }
    }

    return $changes
}

function Get-SelSerialFromIdParsed {
    param(
        [AllowNull()]
        [pscustomobject]$IdParsed
    )

    if ($null -eq $IdParsed) {
        return ""
    }

    $preferredKeys = @("SERIAL", "SERIALNUM", "SERIALNUMBER", "SERNUM", "SN")
    foreach ($key in $preferredKeys) {
        if ($IdParsed.PSObject.Properties.Name -contains $key) {
            $value = [string]$IdParsed.$key
            if ($value -match "^\d{6,}$") {
                return $value
            }
        }
    }

    foreach ($prop in $IdParsed.PSObject.Properties) {
        if ($prop.Name -match "SERIAL|SERNUM|^SN$") {
            $value = [string]$prop.Value
            if ($value -match "^\d{6,}$") {
                return $value
            }
        }
    }

    return ""
}

function Get-SelInventoryHostFromDeviceHistory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $false)]
        [string]$DevicesDirectory = (Get-SelDataPath -ChildPath "devices")
    )

    $path = Join-Path $DevicesDirectory ($Serial + ".json")
    if (-not (Test-Path $path)) {
        return $null
    }

    try {
        $doc = Get-Content $path -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }

    $candidate = @($doc.events |
        Where-Object { $_.action -eq "inventory" -and -not [string]::IsNullOrWhiteSpace([string]$_.hostIp) } |
        Sort-Object -Property @{ Expression = { [string]$_.timestamp }; Descending = $true } |
        Select-Object -First 1)

    if (-not $candidate -or $candidate.Count -eq 0) {
        return $null
    }

    return [pscustomobject]@{
        Ip = [string]$candidate[0].hostIp
        LastUpdated = [string]$candidate[0].timestamp
        Source = "json"
    }
}

function Get-SelInventoryHostFromDesiredState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $false)]
        [string]$DesiredStatePath = (Get-SelDataPath -ChildPath "desiredstate.csv")
    )

    if (-not (Test-Path $DesiredStatePath)) {
        return $null
    }

    $row = @(Import-Csv -Path $DesiredStatePath | Where-Object { $_.Serial -eq $Serial } | Select-Object -First 1)
    if (-not $row -or $row.Count -eq 0) {
        return $null
    }

    $ip = [string]$row[0].ObservedIP
    if ([string]::IsNullOrWhiteSpace($ip)) {
        return $null
    }

    $lastSeen = [string]$row[0].LastSeen
    if ([string]::IsNullOrWhiteSpace($lastSeen)) {
        $lastSeen = "unknown"
    }

    return [pscustomobject]@{
        Ip = $ip
        LastUpdated = $lastSeen
        Source = "desiredstate"
    }
}

function Resolve-SelInventoryHostIp {
    param(
        [string]$Serial,
        [string]$HostIp,
        [string]$DevicesDirectory = (Get-SelDataPath -ChildPath "devices"),
        [string]$DesiredStatePath = (Get-SelDataPath -ChildPath "desiredstate.csv"),
        [scriptblock]$ReadInput = { param([string]$Prompt) Read-Host $Prompt }
    )

    if (-not [string]::IsNullOrWhiteSpace($HostIp)) {
        return [pscustomobject]@{
            HostIp = $HostIp
            Source = "cli"
        }
    }

    if ([string]::IsNullOrWhiteSpace($Serial)) {
        throw "HostIp is required for inventory when Serial is not provided. To discover serial/IP mapping, run inventory collection by IP range."
    }

    $jsonCandidate = Get-SelInventoryHostFromDeviceHistory -Serial $Serial -DevicesDirectory $DevicesDirectory
    $desiredCandidate = Get-SelInventoryHostFromDesiredState -Serial $Serial -DesiredStatePath $DesiredStatePath

    if (-not $jsonCandidate -and -not $desiredCandidate) {
        throw ("No known IP found for serial {0}. Run inventory collection by IP range to discover IP/serial mapping." -f $Serial)
    }

    if ($jsonCandidate -and -not $desiredCandidate) {
        return [pscustomobject]@{
            HostIp = $jsonCandidate.Ip
            Source = "json"
        }
    }

    if ($desiredCandidate -and -not $jsonCandidate) {
        return [pscustomobject]@{
            HostIp = $desiredCandidate.Ip
            Source = "desiredstate"
        }
    }

    if ($jsonCandidate.Ip -eq $desiredCandidate.Ip) {
        return [pscustomobject]@{
            HostIp = $jsonCandidate.Ip
            Source = "json+desiredstate"
        }
    }

    while ($true) {
        Write-Host ("IP conflict for serial {0}:" -f $Serial)
        Write-Host ("  1) JSON IP {0} last updated {1}" -f $jsonCandidate.Ip, $jsonCandidate.LastUpdated)
        Write-Host ("  2) Desiredstate IP {0} last updated {1}" -f $desiredCandidate.Ip, $desiredCandidate.LastUpdated)
        Write-Host "  3) Quit"

        $choice = (& $ReadInput "Select an option (1-3)")
        switch ($choice) {
            "1" {
                return [pscustomobject]@{
                    HostIp = $jsonCandidate.Ip
                    Source = "json"
                }
            }
            "2" {
                return [pscustomobject]@{
                    HostIp = $desiredCandidate.Ip
                    Source = "desiredstate"
                }
            }
            "3" {
                throw "Operation cancelled by user."
            }
            default {
                Write-Host ("Invalid selection '{0}'. Choose 1-3." -f $choice)
            }
        }
    }
}

function Invoke-SelInventory {
    param(
        [string]$Serial,
        [string]$HostIp,
        [string]$Profile = "factory",
        [switch]$DebugTransport,
        [switch]$PassThru
    )

    $trace = New-SelTraceContext -Enabled:$DebugTransport -Operation "inventory" -HostIp $HostIp -Serial $Serial
    Write-SelTrace -TraceContext $trace -Message ("inventory start serial={0} hostIp={1} profile={2}" -f $Serial, $HostIp, $Profile)

    $defaults = Get-SelDefaults -Profile $Profile
    if ($Serial -and $HostIp) {
        Write-Warning "Inventory -Serial is used only for HostIp lookup when HostIp is missing."
        Write-SelTrace -TraceContext $trace -Message "inventory serial provided with hostIp; serial used for lookup only"
    }

    if (-not $HostIp -and -not $Serial) {
        $HostIp = [string]$defaults.DefaultIP
        Write-SelTrace -TraceContext $trace -Message ("inventory hostIp resolved from profile default: {0}" -f $HostIp)
    }

    Write-SelProgress -Message "Resolving inventory target." -TraceContext $trace
    $resolvedHost = Resolve-SelInventoryHostIp -Serial $Serial -HostIp $HostIp
    $HostIp = [string]$resolvedHost.HostIp
    Write-SelTrace -TraceContext $trace -Message ("inventory hostIp final={0} source={1}" -f $HostIp, $resolvedHost.Source)

    Write-SelProgress -Message ("Opening Telnet session to {0} for inventory." -f $HostIp) -TraceContext $trace
    $capture = Invoke-SelPlinkInventoryCapture -HostIp $HostIp -AccPassword ([string]$defaults.ACCPassword) -TraceContext $trace
    Write-SelProgress -Message ("Parsing inventory output from {0}." -f $HostIp) -TraceContext $trace
    $idParsed = ConvertFrom-SelIdOutput -Text $capture.ID
    $serSummaryParsed = ConvertFrom-SelStaOutput -Text $capture.SER
    $ethParsed = ConvertFrom-SelEthOutput -Text $capture.ETH
    $ethernetModel = Get-SelEthernetModelFromEthParsed -EthParsed $ethParsed

    $observedSerial = [string]$serSummaryParsed.Serial
    if (-not $observedSerial) {
        $observedSerial = Get-SelSerialFromIdParsed -IdParsed $idParsed
    }
    if (-not $observedSerial) {
        Write-SelTrace -TraceContext $trace -Message "inventory failed: serial missing in STA and ID"
        throw "Inventory failed: serial was not returned by relay output (STA/ID)."
    }
    Write-SelTrace -TraceContext $trace -Message ("inventory observed serial={0}" -f $observedSerial)
    $desiredStateMetadata = Get-SelDesiredStateMetadata -Serial $observedSerial
    $deviceMetadata = Get-SelDeviceMetadata -Serial $observedSerial
    $metadata = Resolve-SelMetadata -DesiredStateMetadata $desiredStateMetadata -DeviceMetadata $deviceMetadata

    $status = "success"
    if (-not $capture.AccOk) {
        $status = "id-only"
    }
    if ($Serial -and $Serial -ne $observedSerial) {
        $status = "serial-mismatch-warning"
    }

    $observedFid = ""
    if ($serSummaryParsed.FID) {
        $observedFid = [string]$serSummaryParsed.FID
    }
    elseif ($idParsed.PSObject.Properties.Name -contains "FID") {
        $observedFid = [string]$idParsed.FID
    }

    $observedCid = ""
    if ($serSummaryParsed.CID) {
        $observedCid = [string]$serSummaryParsed.CID
    }
    elseif ($idParsed.PSObject.Properties.Name -contains "CID") {
        $observedCid = [string]$idParsed.CID
    }

    $event = [pscustomobject]@{
        timestamp = (Get-Date).ToString("s")
        action = "inventory"
        runId = [string]$trace.RunId
        hostIp = $HostIp
        profile = $Profile
        defaultsDefaultIp = [string]$defaults.DefaultIP
        status = $status
        identity = [pscustomobject]@{
            requestedSerial = $Serial
            observedSerial = $observedSerial
            name = [string]$metadata.Name
            description = [string]$metadata.Description
        }
        inventory = [pscustomobject]@{
            ID = $idParsed
            # Compatibility key retained for existing readers.
            STA = $serSummaryParsed
            ETH = $ethParsed
            Ethernet = $ethernetModel
        }
        protocol = [pscustomobject]@{
            accOk = $capture.AccOk
        }
    }

    $observedIp = [string]$ethParsed.IP
    if (-not $observedIp) {
        $observedIp = $HostIp
    }

    $previousSnapshot = Get-SelLatestInventorySnapshot -Serial $observedSerial

    $serPullResult = [pscustomobject]@{
        Result = "skipped-access"
        ParsedCount = 0
        EntriesAdded = 0
        EventStorePath = ""
        RawArchivePath = ""
        Note = "ACC escalation did not reach Level 1."
    }
    if ($capture.AccOk) {
        Write-SelProgress -Message ("Storing SER event stream for serial {0}." -f $observedSerial) -TraceContext $trace
        $serPullResult = Write-SelSerEventStore -Serial $observedSerial -RawSerText $capture.SER -RunId ([string]$trace.RunId) -TraceContext $trace
        $serPullResult | Add-Member -MemberType NoteProperty -Name Note -Value "" -Force
    }

    Write-SelProgress -Message ("Persisting inventory results for serial {0}." -f $observedSerial) -TraceContext $trace
    Add-SelDeviceEvent -Serial $observedSerial -Event $event
    $serPullEvent = [pscustomobject]@{
        timestamp = (Get-Date).ToString("s")
        action = "ser-pull"
        runId = [string]$trace.RunId
        hostIp = $HostIp
        profile = $Profile
        result = [string]$serPullResult.Result
        entriesAdded = [int]$serPullResult.EntriesAdded
        parsedCount = [int]$serPullResult.ParsedCount
        eventStore = [string]$serPullResult.EventStorePath
        rawArchive = [string]$serPullResult.RawArchivePath
        note = [string]$serPullResult.Note
    }
    Add-SelDeviceEvent -Serial $observedSerial -Event $serPullEvent
    Update-SelDesiredStateObserved -Serial $observedSerial -Name ([string]$metadata.Name) -Description ([string]$metadata.Description) -Mac ([string]$ethParsed.MAC) -ObservedIP $observedIp -ObservedPrimaryInterface ([string]$ethernetModel.primaryInterface) -ObservedActiveInterface ([string]$ethernetModel.activeInterface) -ObservedNetMode ([string]$ethernetModel.netMode) -ObservedFirmwareLabel (Get-SelFirmwareLabelFromFid -Fid $observedFid) -ObservedFid $observedFid
    Write-SelTrace -TraceContext $trace -Message ("inventory persistence complete serial={0} observedIp={1} status={2}" -f $observedSerial, $observedIp, $status)
    Clear-SelProgressIndicator
    if ($PassThru) {
        Write-Host ("Log written: {0}" -f $trace.LogPath)
    }
    else {
        Write-Output ("Log written: {0}" -f $trace.LogPath)
    }

    if ($PassThru) {
        Write-Host ("Inventory collected for serial {0} from {1} (acc={2}, status={3})." -f $observedSerial, $HostIp, $capture.AccOk, $status)
    }
    else {
        Write-Output ("Inventory collected for serial {0} from {1} (acc={2}, status={3})." -f $observedSerial, $HostIp, $capture.AccOk, $status)
    }

    if ($PassThru) {
        $changes = Get-SelInventoryChangeSummary -Previous $previousSnapshot -HostIp $HostIp -ObservedIp $observedIp -Mac ([string]$ethParsed.MAC) -Fid $observedFid -Cid $observedCid
        return [pscustomobject]@{
            Action = "inventory"
            Status = $status
            Serial = $observedSerial
            Name = [string]$metadata.Name
            Description = [string]$metadata.Description
            HostIp = $HostIp
            ObservedIp = $observedIp
            IsNewDevice = ($null -eq $previousSnapshot)
            Changes = $changes
            SerEntriesAdded = [int]$serPullResult.EntriesAdded
            SerParsedCount = [int]$serPullResult.ParsedCount
            SerPullResult = [string]$serPullResult.Result
        }
    }
}

function Invoke-SelReIp {
    param(
        [string]$Serial,
        [string]$HostIp,
        [string]$Ip,
        [string]$Mask,
        [string]$Gateway,
        [string]$PrimaryInterface,
        [string]$Profile = "factory",
        [switch]$DebugTransport,
        [switch]$PassThru,
        [switch]$SkipInventoryUpdate,
        [switch]$AutoConfirm
    )

    $trace = New-SelTraceContext -Enabled:$DebugTransport -Operation "reip" -HostIp $HostIp -Serial $Serial
    $defaults = Get-SelDefaults -Profile $Profile
    if (-not [string]::IsNullOrWhiteSpace($PrimaryInterface)) {
        throw "PrimaryInterface is not used by single reip. Re-run without -PrimaryInterface."
    }
    $resolvedHost = Resolve-SelReIpHostIp -Serial $Serial -HostIp $HostIp -ProfileDefaultIp ([string]$defaults.DefaultIP)
    $HostIp = [string]$resolvedHost.HostIp
    $target = Resolve-SelReIpTarget -Serial $Serial -Ip $Ip -Mask $Mask -Gateway $Gateway -PrimaryInterface $PrimaryInterface -PromptIfMissing -DefaultIp ([string]$defaults.DefaultIP)

    Write-SelProgress -Message ("Resolving re-IP target for serial {0}." -f $Serial) -TraceContext $trace
    Write-SelProgress -Message ("Pinging current relay IP {0} before Telnet." -f $HostIp) -TraceContext $trace
    $preflightPing = Invoke-SelPingCheck -HostIp $HostIp -TraceContext $trace
    if (-not $preflightPing.Success) {
        throw ("Current relay IP {0} is not reachable by ping. Aborting before Telnet." -f $HostIp)
    }

    Write-SelProgress -Message ("Opening Telnet session to {0}." -f $HostIp) -TraceContext $trace
    # Always collect STA for re-IP identity/confirmation; SkipInventoryUpdate only controls persistence.
    $includeSer = $true
    $preCapture = Invoke-SelPlinkReIpCapture -HostIp $HostIp -AccPassword ([string]$defaults.ACCPassword) -TwoAcPassword ([string]$defaults.'2ACPassword') -Target $target -IncludeSer:$includeSer -TraceContext $trace
    $preIdParsed = ConvertFrom-SelIdOutput -Text $preCapture.ID
    $preSerParsed = if ($includeSer) { ConvertFrom-SelStaOutput -Text $preCapture.SER } else { [pscustomobject]@{ Serial = ""; FID = "" } }
    $preEthParsed = ConvertFrom-SelEthOutput -Text $preCapture.ETH
    $preEthModel = Get-SelEthernetModelFromEthParsed -EthParsed $preEthParsed

    $startingSerial = [string]$preSerParsed.Serial
    if (-not $startingSerial) {
        $startingSerial = Get-SelSerialFromIdParsed -IdParsed $preIdParsed
    }
    if (-not [string]::IsNullOrWhiteSpace($startingSerial)) {
        $Serial = $startingSerial
    }

    $confirmed = Confirm-SelReIpPlan -HostIp $HostIp -Target $target -ObservedSerial $startingSerial -PreEthParsed $preEthParsed -AutoConfirm:$AutoConfirm
    if (-not $confirmed) {
        Stop-SelPlinkSession -Session $preCapture.Session
        $cancelEvent = [pscustomobject]@{
            timestamp = (Get-Date).ToString("s")
            action = "reip"
            runId = [string]$trace.RunId
            hostIp = $HostIp
            targetIp = $target.Ip
            targetMask = $target.Mask
            targetGateway = $target.Gateway
            source = $target.Source
            profile = $Profile
            defaultsDefaultIp = [string]$defaults.DefaultIP
            status = "cancelled"
            accessLevelUsed = [string]$preCapture.Access.AccessLevel
            confirmationAccepted = $false
            preflightPing = $preflightPing
            identity = [pscustomobject]@{
                requestedSerial = $Serial
                observedSerial = $startingSerial
            }
            logRef = $trace.LogPath
        }
        if (-not $SkipInventoryUpdate) {
            Add-SelDeviceEvent -Serial $Serial -Event $cancelEvent
        }
        if ($PassThru) {
            return [pscustomobject]@{
                Action = "reip"
                Status = "cancelled"
                Serial = $Serial
                HostIp = $HostIp
                ObservedIp = $HostIp
                IsNewDevice = $false
                Changes = @()
            }
        }
        Write-Output ("Re-IP cancelled for serial {0}." -f $Serial)
        return
    }

    Write-SelProgress -Message "Applying SET P 1 changes at ACC -> 2AC." -TraceContext $trace
    $setResult = $null
    try {
        $setResult = Invoke-SelReIpSetPort1 -Session $preCapture.Session -Target $target -TraceContext $trace
    }
    finally {
        Stop-SelPlinkSession -Session $preCapture.Session
    }

    Write-SelProgress -Message ("Starting reconnect attempts to {0}." -f $target.Ip) -TraceContext $trace
    $reconnect = Invoke-SelFastReconnectCapture -HostIp $target.Ip -AccPassword ([string]$defaults.ACCPassword) -TwoAcPassword ([string]$defaults.'2ACPassword') -IncludeSer:$includeSer -Attempts 8 -DelayMs 400 -TraceContext $trace
    $recoveryPing = $null
    $postCapture = $null
    if ($reconnect.Success) {
        $postCapture = $reconnect.Capture
    }
    else {
        Write-SelProgress -Message ("Immediate reconnect failed; checking whether {0} is reachable." -f $target.Ip) -TraceContext $trace
        $recoveryPing = Invoke-SelPingCheck -HostIp $target.Ip -TraceContext $trace
        if ($recoveryPing.Success) {
            Write-SelProgress -Message ("{0} is reachable. Retrying Telnet reconnect." -f $target.Ip) -TraceContext $trace
            $reconnect = Invoke-SelFastReconnectCapture -HostIp $target.Ip -AccPassword ([string]$defaults.ACCPassword) -TwoAcPassword ([string]$defaults.'2ACPassword') -IncludeSer:$includeSer -Attempts 5 -DelayMs 400 -TraceContext $trace
            if ($reconnect.Success) {
                $postCapture = $reconnect.Capture
            }
        }
    }

    if ($null -eq $postCapture) {
        $failEvent = [pscustomobject]@{
            timestamp = (Get-Date).ToString("s")
            action = "reip"
            runId = [string]$trace.RunId
            hostIp = $HostIp
            targetIp = $target.Ip
            targetMask = $target.Mask
            targetGateway = $target.Gateway
            source = $target.Source
            profile = $Profile
            defaultsDefaultIp = [string]$defaults.DefaultIP
            status = "failed"
            accessLevelUsed = [string]$preCapture.Access.AccessLevel
            confirmationAccepted = $true
            preflightPing = $preflightPing
            recoveryPing = $recoveryPing
            reconnectAttempts = [int]$reconnect.AttemptCount
            preChange = [pscustomobject]@{
                id = $preIdParsed
                sta = $preSerParsed
                eth = $preEthParsed
            }
            setPort1 = $setResult
            note = ("Relay did not become reachable on target IP {0}. Last reconnect error: {1}" -f $target.Ip, [string]$reconnect.ErrorMessage)
            logRef = $trace.LogPath
        }
        if (-not $SkipInventoryUpdate) {
            Add-SelDeviceEvent -Serial $Serial -Event $failEvent
        }
        throw ("Relay did not become reachable on target IP {0}." -f $target.Ip)
    }

    Write-SelProgress -Message ("Reconnecting to {0} for identity verification." -f $target.Ip) -TraceContext $trace
    $postIdParsed = ConvertFrom-SelIdOutput -Text $postCapture.ID
    $postSerParsed = if ($includeSer) { ConvertFrom-SelStaOutput -Text $postCapture.SER } else { [pscustomobject]@{ Serial = ""; FID = "" } }
    $postEthParsed = ConvertFrom-SelEthOutput -Text $postCapture.ETH
    $postEthModel = Get-SelEthernetModelFromEthParsed -EthParsed $postEthParsed
    $postSerial = [string]$postSerParsed.Serial
    if (-not $postSerial) {
        $postSerial = Get-SelSerialFromIdParsed -IdParsed $postIdParsed
    }

    $status = "success"
    $note = ""
    if ([string]::IsNullOrWhiteSpace($postSerial)) {
        $status = "failed"
        $note = "Post-change identity verification did not return a serial number."
    }
    elseif (-not [string]::IsNullOrWhiteSpace($startingSerial) -and $postSerial -ne $startingSerial) {
        $status = "serial-mismatch-warning"
        $note = ("Serial changed from {0} to {1} after re-IP." -f $startingSerial, $postSerial)
    }

    $metadataSerial = ""
    if (-not [string]::IsNullOrWhiteSpace($postSerial)) {
        $metadataSerial = $postSerial
    }
    elseif (-not [string]::IsNullOrWhiteSpace($startingSerial)) {
        $metadataSerial = $startingSerial
    }
    else {
        $metadataSerial = $Serial
    }
    $metadata = Resolve-SelMetadata -DesiredStateMetadata (Get-SelDesiredStateMetadata -Serial $metadataSerial) -DeviceMetadata (Get-SelDeviceMetadata -Serial $metadataSerial)
    $effectiveSerial = ""
    if (-not [string]::IsNullOrWhiteSpace($postSerial)) {
        $effectiveSerial = $postSerial
    }
    elseif (-not [string]::IsNullOrWhiteSpace($startingSerial)) {
        $effectiveSerial = $startingSerial
    }
    else {
        $effectiveSerial = $Serial
    }
    $event = [pscustomobject]@{
        timestamp = (Get-Date).ToString("s")
        action = "reip"
        runId = [string]$trace.RunId
        hostIp = $HostIp
        targetIp = $target.Ip
        targetMask = $target.Mask
        targetGateway = $target.Gateway
        source = $target.Source
        profile = $Profile
        defaultsDefaultIp = [string]$defaults.DefaultIP
        status = $status
        accessLevelUsed = [string]$preCapture.Access.AccessLevel
        confirmationAccepted = $true
        preflightPing = $preflightPing
        recoveryPing = $recoveryPing
        reconnectAttempts = [int]$reconnect.AttemptCount
        preChange = [pscustomobject]@{
            id = $preIdParsed
            sta = $preSerParsed
            eth = $preEthParsed
            ethernet = $preEthModel
        }
        postChange = [pscustomobject]@{
            id = $postIdParsed
            sta = $postSerParsed
            eth = $postEthParsed
            ethernet = $postEthModel
        }
        setPort1 = $setResult
        identity = [pscustomobject]@{
            requestedSerial = $Serial
            observedSerial = $postSerial
            startingSerial = $startingSerial
            name = [string]$metadata.Name
            description = [string]$metadata.Description
        }
        note = $note
        logRef = $trace.LogPath
    }

    if ((-not $SkipInventoryUpdate) -and (-not [string]::IsNullOrWhiteSpace($effectiveSerial))) {
        Add-SelDeviceEvent -Serial $effectiveSerial -Event $event
    }
    if ((-not $SkipInventoryUpdate) -and $status -ne "failed" -and (-not [string]::IsNullOrWhiteSpace($effectiveSerial))) {
        Update-SelDesiredStateObserved -Serial $effectiveSerial -Name ([string]$metadata.Name) -Description ([string]$metadata.Description) -Mac ([string]$postEthParsed.MAC) -ObservedIP ([string]$postEthParsed.IP) -ObservedPrimaryInterface ([string]$postEthModel.primaryInterface) -ObservedActiveInterface ([string]$postEthModel.activeInterface) -ObservedNetMode ([string]$postEthModel.netMode) -ObservedFirmwareLabel (Get-SelFirmwareLabelFromFid -Fid ([string]$postSerParsed.FID)) -ObservedFid ([string]$postSerParsed.FID) -LastAction "reip" -LastResult $status
    }

    $targetMaskDisplay = if ([string]::IsNullOrWhiteSpace([string]$target.Mask)) { "(unchanged)" } else { [string]$target.Mask }
    $targetGatewayDisplay = if ([string]::IsNullOrWhiteSpace([string]$target.Gateway)) { "(unchanged)" } else { [string]$target.Gateway }
    $observedIpDisplay = if ([string]::IsNullOrWhiteSpace([string]$postEthParsed.IP)) { "(unknown)" } else { [string]$postEthParsed.IP }
    $observedMaskDisplay = if ([string]::IsNullOrWhiteSpace([string]$postEthParsed.Mask)) { "(unknown)" } else { [string]$postEthParsed.Mask }
    $observedGatewayDisplay = if ([string]::IsNullOrWhiteSpace([string]$postEthParsed.Gateway)) { "(unknown)" } else { [string]$postEthParsed.Gateway }
    $skipUpdateNote = if ($SkipInventoryUpdate) { " Inventory update skipped." } else { "" }
    $displaySerial = if ([string]::IsNullOrWhiteSpace($effectiveSerial)) { "(unknown)" } else { $effectiveSerial }
    $resultSummary = "Re-IP completed for serial {0}: {1} -> {2} ({3}). Target: IP={4}, Mask={5}, Gateway={6}. Observed: IP={7}, Mask={8}, Gateway={9}.{10}" -f $displaySerial, $HostIp, $target.Ip, $status, $target.Ip, $targetMaskDisplay, $targetGatewayDisplay, $observedIpDisplay, $observedMaskDisplay, $observedGatewayDisplay, $skipUpdateNote

    Clear-SelProgressIndicator
    if ($PassThru) {
        Write-Host ("Log written: {0}" -f $trace.LogPath)
        Write-Host $resultSummary
        return [pscustomobject]@{
            Action = "reip"
            Status = $status
            Serial = $effectiveSerial
            Name = [string]$metadata.Name
            Description = [string]$metadata.Description
            HostIp = $HostIp
            ObservedIp = [string]$postEthParsed.IP
            TargetIp = $target.Ip
            TargetMask = [string]$target.Mask
            TargetGateway = [string]$target.Gateway
            ObservedMask = [string]$postEthParsed.Mask
            ObservedGateway = [string]$postEthParsed.Gateway
            SkipInventoryUpdate = [bool]$SkipInventoryUpdate
            IsNewDevice = $false
            Changes = @()
        }
    }

    Write-Output ("Log written: {0}" -f $trace.LogPath)
    Write-Output $resultSummary
}

function Invoke-SelMassProvisioning {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("range", "interactive", "desiredstate")]
        [string]$Mode,
        [string]$HostIp,
        [string]$StartIp,
        [string]$EndIp,
        [string]$Mask,
        [string]$Gateway,
        [string]$Profile = "factory",
        [switch]$DebugTransport,
        [switch]$PassThru,
        [switch]$SkipInventoryUpdate,
        [string]$DesiredStatePath = (Get-SelDataPath -ChildPath "desiredstate.csv"),
        [scriptblock]$ReadInput = { param([string]$Prompt) Read-Host $Prompt }
    )

    $defaults = Get-SelDefaults -Profile $Profile
    $sourceHostIp = if ([string]::IsNullOrWhiteSpace($HostIp)) { [string]$defaults.DefaultIP } else { [string]$HostIp }
    if ([string]::IsNullOrWhiteSpace($sourceHostIp)) {
        throw "Mass provisioning requires a current/default relay IP."
    }

    $currentMask = if ([string]::IsNullOrWhiteSpace($Mask)) { [string]$defaults.TargetSubnetMask } else { [string]$Mask }
    $currentGateway = if ([string]::IsNullOrWhiteSpace($Gateway)) { [string]$defaults.TargetGateway } else { [string]$Gateway }
    $rangeIps = @()
    if ($Mode -eq "range") {
        if ([string]::IsNullOrWhiteSpace($StartIp) -or [string]::IsNullOrWhiteSpace($EndIp)) {
            throw "Range mode requires both start and end IPs."
        }
        $rangeIps = @(Get-SelIpv4Range -StartIp $StartIp -EndIp $EndIp)
        $rangeMask = if ([string]::IsNullOrWhiteSpace($currentMask)) { [string]$defaults.DefaultSubnetMask } else { $currentMask }
        foreach ($probeIp in @($StartIp, $EndIp)) {
            $networkCheck = Test-SelLocalIpv4OnTargetNetwork -TargetIp $probeIp -Mask $rangeMask
            if ($networkCheck.Checked -and -not $networkCheck.Success) {
                Write-Host ("Warning: local PC does not appear on the target network for {0}/{1}. Local IPv4: {2}" -f $probeIp, $rangeMask, (@($networkCheck.LocalIPs) -join ", "))
                $continueChoice = & $ReadInput "Continue anyway? [y/N]"
                if ($continueChoice -notmatch "^(?i)y(es)?$") {
                    $aborted = [pscustomobject]@{
                        Action = "mass-reip"
                        Mode = $Mode
                        Status = "cancelled"
                        HostIp = $sourceHostIp
                        SkipInventoryUpdate = [bool]$SkipInventoryUpdate
                        Results = @()
                        ExportRows = @()
                    }
                    if ($PassThru) { return $aborted }
                    return
                }
                break
            }
        }
    }
    elseif ($Mode -eq "desiredstate") {
        $conflictCheck = Test-SelDesiredStateConflicts -DesiredStatePath $DesiredStatePath
        if (-not $conflictCheck.IsValid) {
            Write-Host ""
            Write-Host "desiredstate.csv conflicts detected:"
            foreach ($conflict in @($conflictCheck.Conflicts)) {
                Write-Host ("  - {0}" -f [string]$conflict.Message)
            }
            $blocked = [pscustomobject]@{
                Action = "mass-reip"
                Mode = $Mode
                Status = "blocked-conflicts"
                HostIp = $sourceHostIp
                SkipInventoryUpdate = [bool]$SkipInventoryUpdate
                Results = @()
                ExportRows = @()
                Conflicts = @($conflictCheck.Conflicts)
            }
            if ($PassThru) { return $blocked }
            return
        }

        $targetRows = @($conflictCheck.Rows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.DesiredIP) })
        foreach ($row in $targetRows) {
            $effectiveMask = if (-not [string]::IsNullOrWhiteSpace([string]$row.DesiredSubnetMask)) { [string]$row.DesiredSubnetMask } elseif (-not [string]::IsNullOrWhiteSpace([string]$defaults.TargetSubnetMask)) { [string]$defaults.TargetSubnetMask } else { [string]$defaults.DefaultSubnetMask }
            if ([string]::IsNullOrWhiteSpace([string]$effectiveMask)) {
                continue
            }
            $networkCheck = Test-SelLocalIpv4OnTargetNetwork -TargetIp ([string]$row.DesiredIP) -Mask $effectiveMask
            if ($networkCheck.Checked -and -not $networkCheck.Success) {
                Write-Host ("Warning: local PC does not appear on the target network for desired IP {0}/{1}. Local IPv4: {2}" -f [string]$row.DesiredIP, $effectiveMask, (@($networkCheck.LocalIPs) -join ", "))
                $continueChoice = & $ReadInput "Continue anyway? [y/N]"
                if ($continueChoice -notmatch "^(?i)y(es)?$") {
                    $aborted = [pscustomobject]@{
                        Action = "mass-reip"
                        Mode = $Mode
                        Status = "cancelled"
                        HostIp = $sourceHostIp
                        SkipInventoryUpdate = [bool]$SkipInventoryUpdate
                        Results = @()
                        ExportRows = @()
                    }
                    if ($PassThru) { return $aborted }
                    return
                }
                break
            }
        }
    }

    $rows = New-Object System.Collections.ArrayList
    $sessionFailures = New-Object System.Collections.ArrayList
    $rangeIndex = 0
    $sequence = 0

    Write-Host ""
    Write-Host ("1X1 Mass Provisioning ({0})" -f $Mode)

    while ($true) {
        if ($Mode -eq "range" -and $rangeIndex -ge @($rangeIps).Count) {
            break
        }

        $sequence++
        Write-Host ""
        if ($Mode -eq "range") {
            Write-Host ("Source/default relay IP: {0}" -f $sourceHostIp)
            Write-Host ("Next target IP: {0}" -f [string]$rangeIps[$rangeIndex])
            $null = & $ReadInput "Connect one SEL at a time, then press Enter to continue"
        }
        elseif ($Mode -eq "interactive") {
            Write-Host ("Source/default relay IP: {0}" -f $sourceHostIp)
            $null = & $ReadInput "Connect one SEL at a time, then press Enter to continue"
        }

        $trace = New-SelTraceContext -Enabled:$DebugTransport -Operation ("mass-reip-{0}" -f $Mode) -HostIp $sourceHostIp -Serial ""
        Write-SelProgress -Message ("Identifying relay at {0}." -f $sourceHostIp) -TraceContext $trace
        $preflightPing = Invoke-SelPingCheck -HostIp $sourceHostIp -TraceContext $trace
        if (-not $preflightPing.Success) {
            $failureNote = ("Default/current IP {0} is not reachable by ping ({1})." -f $sourceHostIp, [string]$preflightPing.FailureReason)
            Show-SelMassProvisioningFailure -Message $failureNote
            [void]$sessionFailures.Add([pscustomobject]@{
                Sequence = $sequence
                Mode = $Mode
                HostIp = $sourceHostIp
                Note = $failureNote
            })
            $retryChoice = & $ReadInput "Retry this relay? [Y/N]"
            if ($retryChoice -match "^(?i:y|yes)?$") {
                $sequence--
                continue
            }
            break
        }
        else {
            try {
                $capture = Invoke-SelPlinkIdentityCapture -HostIp $sourceHostIp -AccPassword ([string]$defaults.ACCPassword) -TwoAcPassword ([string]$defaults.'2ACPassword') -IncludeSer -TraceContext $trace
                $idParsed = ConvertFrom-SelIdOutput -Text $capture.ID
                $staParsed = ConvertFrom-SelStaOutput -Text $capture.SER
                $ethParsed = ConvertFrom-SelEthOutput -Text $capture.ETH
                $serial = [string]$staParsed.Serial
                if ([string]::IsNullOrWhiteSpace($serial)) {
                    $serial = Get-SelSerialFromIdParsed -IdParsed $idParsed
                }
                $identity = [pscustomobject]@{
                    Serial = [string]$serial
                    Mac = [string]$ethParsed.MAC
                    CurrentIp = [string]$ethParsed.IP
                    CurrentMask = [string]$ethParsed.Mask
                    CurrentGateway = [string]$ethParsed.Gateway
                }

                $effectiveMaskDefault = if (-not [string]::IsNullOrWhiteSpace($currentMask)) { $currentMask } else { [string]$ethParsed.Mask }
                $effectiveGatewayDefault = if (-not [string]::IsNullOrWhiteSpace($currentGateway)) { $currentGateway } else { [string]$ethParsed.Gateway }
                $targetPlan = Get-SelMassProvisioningNextTarget -Mode $Mode -Sequence $sequence -Defaults $defaults -Identity $identity -RangeIps $rangeIps -RangeIndex $rangeIndex -CurrentMask $effectiveMaskDefault -CurrentGateway $effectiveGatewayDefault -DesiredStatePath $DesiredStatePath -ReadInput $ReadInput

                if (-not $targetPlan.Success) {
                    $status = if ($targetPlan.Exhausted) { "completed" } else { "skipped" }
                    [void]$rows.Add((New-SelMassProvisioningRow -Sequence $sequence -Mode $Mode -Status $status -Serial $identity.Serial -Mac $identity.Mac -OldIp $identity.CurrentIp -NewIp "" -TargetMask "" -TargetGateway "" -ObservedMask $identity.CurrentMask -ObservedGateway $identity.CurrentGateway -Note ([string]$targetPlan.Message)))
                    if ($targetPlan.Exhausted) {
                        break
                    }
                }
                else {
                    if ($Mode -eq "desiredstate") {
                        $continueAssignment = & $ReadInput "Continue with this assignment? [Y/N]"
                        if ($continueAssignment -notmatch "^(?i)y(es)?$") {
                            [void]$rows.Add((New-SelMassProvisioningRow -Sequence $sequence -Mode $Mode -Status "skipped" -Serial $identity.Serial -Mac $identity.Mac -OldIp $identity.CurrentIp -NewIp [string]$targetPlan.Ip -TargetMask [string]$targetPlan.Mask -TargetGateway [string]$targetPlan.Gateway -ObservedMask $identity.CurrentMask -ObservedGateway $identity.CurrentGateway -Note "Operator declined desiredstate assignment."))
                            $nextChoice = & $ReadInput "Connect next relay and continue? [Y/N]"
                            if ($nextChoice -notmatch "^(?i:y|yes)?$") {
                                break
                            }
                            continue
                        }
                    }

                    $effectiveNetworkMask = if (-not [string]::IsNullOrWhiteSpace([string]$targetPlan.Mask)) { [string]$targetPlan.Mask } elseif (-not [string]::IsNullOrWhiteSpace([string]$identity.CurrentMask)) { [string]$identity.CurrentMask } else { [string]$defaults.TargetSubnetMask }
                    $networkCheck = Test-SelLocalIpv4OnTargetNetwork -TargetIp ([string]$targetPlan.Ip) -Mask $effectiveNetworkMask
                    if ($networkCheck.Checked -and -not $networkCheck.Success) {
                        Write-Host ("Warning: local PC does not appear on the target network for {0}/{1}. Local IPv4: {2}" -f [string]$targetPlan.Ip, $effectiveNetworkMask, (@($networkCheck.LocalIPs) -join ", "))
                        $continueChoice = & $ReadInput "Continue anyway? [y/N]"
                        if ($continueChoice -notmatch "^(?i)y(es)?$") {
                            [void]$rows.Add((New-SelMassProvisioningRow -Sequence $sequence -Mode $Mode -Status "skipped" -Serial $identity.Serial -Mac $identity.Mac -OldIp $identity.CurrentIp -NewIp [string]$targetPlan.Ip -TargetMask [string]$targetPlan.Mask -TargetGateway [string]$targetPlan.Gateway -ObservedMask $identity.CurrentMask -ObservedGateway $identity.CurrentGateway -Note "Operator declined target-network warning."))
                            if ($Mode -eq "range") {
                                # Keep the same target IP pending for the next relay.
                            }
                        }
                        else {
                            $reipResult = Invoke-SelReIp -Serial $identity.Serial -HostIp $sourceHostIp -Ip ([string]$targetPlan.Ip) -Mask ([string]$targetPlan.Mask) -Gateway ([string]$targetPlan.Gateway) -Profile $Profile -DebugTransport:$DebugTransport -PassThru -SkipInventoryUpdate:$SkipInventoryUpdate -AutoConfirm
                            [void]$rows.Add((New-SelMassProvisioningRow -Sequence $sequence -Mode $Mode -Status ([string]$reipResult.Status) -Serial ([string]$reipResult.Serial) -Mac $identity.Mac -OldIp $identity.CurrentIp -NewIp ([string]$reipResult.TargetIp) -TargetMask ([string]$reipResult.TargetMask) -TargetGateway ([string]$reipResult.TargetGateway) -ObservedMask ([string]$reipResult.ObservedMask) -ObservedGateway ([string]$reipResult.ObservedGateway) -Note ""))
                            if ($Mode -eq "range" -and [string]$reipResult.Status -eq "success") {
                                $rangeIndex++
                            }
                        }
                    }
                    else {
                        $reipResult = Invoke-SelReIp -Serial $identity.Serial -HostIp $sourceHostIp -Ip ([string]$targetPlan.Ip) -Mask ([string]$targetPlan.Mask) -Gateway ([string]$targetPlan.Gateway) -Profile $Profile -DebugTransport:$DebugTransport -PassThru -SkipInventoryUpdate:$SkipInventoryUpdate -AutoConfirm
                        [void]$rows.Add((New-SelMassProvisioningRow -Sequence $sequence -Mode $Mode -Status ([string]$reipResult.Status) -Serial ([string]$reipResult.Serial) -Mac $identity.Mac -OldIp $identity.CurrentIp -NewIp ([string]$reipResult.TargetIp) -TargetMask ([string]$reipResult.TargetMask) -TargetGateway ([string]$reipResult.TargetGateway) -ObservedMask ([string]$reipResult.ObservedMask) -ObservedGateway ([string]$reipResult.ObservedGateway) -Note ""))
                        if ($Mode -eq "range" -and [string]$reipResult.Status -eq "success") {
                            $rangeIndex++
                        }
                    }
                }
            }
            catch {
                $exceptionMessage = [string]$_.Exception.Message
                $failureNote = $exceptionMessage
                if ($exceptionMessage -match "Timed out waiting for pattern") {
                    $failureNote = ("{0} responded to ping but did not present a usable SEL Telnet prompt." -f $sourceHostIp)
                }
                Show-SelMassProvisioningFailure -Message $failureNote
                [void]$sessionFailures.Add([pscustomobject]@{
                    Sequence = $sequence
                    Mode = $Mode
                    HostIp = $sourceHostIp
                    Note = $failureNote
                })
                $retryChoice = & $ReadInput "Retry this relay? [Y/N]"
                if ($retryChoice -match "^(?i:y|yes)?$") {
                    $sequence--
                    continue
                }
                break
            }
        }

        if ($Mode -eq "range" -and $rangeIndex -ge @($rangeIps).Count) {
            break
        }

        $nextChoice = & $ReadInput "Connect next relay and continue? [Y/N]"
        if ($nextChoice -notmatch "^(?i:y|yes)?$") {
            break
        }
    }

    $results = @($rows)
    $failureCount = @($results | Where-Object { $_.Status -eq "failed" }).Count + @($sessionFailures).Count
    $overallStatus = if ($failureCount -gt 0) { "completed-with-failures" } else { "completed" }
    $sessionResult = [pscustomobject]@{
        Action = "mass-reip"
        Mode = $Mode
        Status = $overallStatus
        HostIp = $sourceHostIp
        SkipInventoryUpdate = [bool]$SkipInventoryUpdate
        Results = $results
        ExportRows = $results
        SessionFailures = @($sessionFailures)
        FailureCount = $failureCount
    }

    if ($PassThru) {
        return $sessionResult
    }

    return $null
}

function Invoke-SelFwUpgrade {
    param(
        [string]$Serial,
        [string]$HostIp,
        [string]$Profile = "factory",
        [switch]$DebugTransport
    )

    $null = Get-SelDefaults -Profile $Profile
    throw ("fwupgrade is not implemented in v0.1 scaffold yet (profile={0})." -f $Profile)
}

Export-ModuleMember -Function @(
    "Get-SelPlinkPath",
    "Get-SelSerialFromIdParsed",
    "Get-SelInventoryHostFromDeviceHistory",
    "Get-SelInventoryHostFromDesiredState",
    "Get-SelDeviceMetadata",
    "Resolve-SelMetadata",
    "Resolve-SelInventoryHostIp",
    "Get-SelDefaultsRows",
    "Get-SelDefaults",
    "Get-SelSettingsPath",
    "Get-SelUiSettings",
    "Set-SelConsoleOutputPreference",
    "Test-SelConsoleOutputEnabled",
    "Clear-SelProgressIndicator",
    "Get-SelDesiredStateRows",
    "Get-SelDesiredStateActiveRows",
    "Get-SelDesiredStateMetadata",
    "Test-SelDesiredStateRowActive",
    "ConvertFrom-SelIdOutput",
    "ConvertFrom-SelStaOutput",
    "ConvertTo-SelPrimaryInterface",
    "ConvertTo-SelNetPortSelector",
    "Read-SelPromptWithDefault",
    "Invoke-SelPingCheck",
    "Wait-SelPingRecovery",
    "ConvertTo-SelIpv4UInt32",
    "Get-SelIpv4Range",
    "Get-SelLocalIpv4Addresses",
    "Test-SelLocalIpv4OnTargetNetwork",
    "Normalize-SelMacAddress",
    "Test-SelDesiredStateConflicts",
    "Resolve-SelDesiredStateProvisionTarget",
    "New-SelMassProvisioningRow",
    "Show-SelMassProvisioningFailure",
    "Get-SelMassProvisioningNextTarget",
    "Analyze-SelPingOutput",
    "Invoke-SelFastReconnectCapture",
    "Confirm-SelReIpPlan",
    "Invoke-SelPlinkReIpCapture",
    "Invoke-SelReIpSetPort1",
    "Invoke-SelPlinkIdentityCapture",
    "Stop-SelPlinkSession",
    "ConvertFrom-SelSerEventRecords",
    "ConvertFrom-SelEthOutput",
    "Get-SelEthernetModelFromEthParsed",
    "Resolve-SelReIpHostIp",
    "Resolve-SelReIpTarget",
    "Update-SelDesiredStateObserved",
    "Add-SelDeviceEvent",
    "Write-SelSerEventStore",
    "Invoke-SelInventory",
    "Invoke-SelReIp",
    "Invoke-SelMassProvisioning",
    "Invoke-SelFwUpgrade"
)
