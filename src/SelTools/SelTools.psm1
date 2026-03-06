Set-StrictMode -Version Latest

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

function Read-SelTelnetAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.Sockets.NetworkStream]$Stream,
        [Parameter(Mandatory = $true)]
        [byte[]]$Buffer,
        [Parameter(Mandatory = $true)]
        [System.Text.Encoding]$Encoding,
        [int]$InitialWaitMs = 300
    )

    Start-Sleep -Milliseconds $InitialWaitMs
    $sb = New-Object System.Text.StringBuilder

    while ($Stream.DataAvailable) {
        $read = $Stream.Read($Buffer, 0, $Buffer.Length)
        if ($read -le 0) {
            break
        }
        [void]$sb.Append($Encoding.GetString($Buffer, 0, $read))
        Start-Sleep -Milliseconds 40
    }

    return (Remove-SelControlChars -Text $sb.ToString())
}

function Read-SelTelnetUntil {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.Sockets.NetworkStream]$Stream,
        [Parameter(Mandatory = $true)]
        [byte[]]$Buffer,
        [Parameter(Mandatory = $true)]
        [System.Text.Encoding]$Encoding,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [int]$TimeoutMs = 6000
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $sb = New-Object System.Text.StringBuilder
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        while ($Stream.DataAvailable) {
            $read = $Stream.Read($Buffer, 0, $Buffer.Length)
            if ($read -le 0) {
                break
            }
            [void]$sb.Append($Encoding.GetString($Buffer, 0, $read))
            Start-Sleep -Milliseconds 30
        }

        $clean = Remove-SelControlChars -Text $sb.ToString()
        if ($clean -match $Pattern) {
            return $clean
        }

        Start-Sleep -Milliseconds 80
    }

    return (Remove-SelControlChars -Text $sb.ToString())
}

function Send-SelTelnetLine {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.Sockets.NetworkStream]$Stream,
        [Parameter(Mandatory = $true)]
        [System.Text.Encoding]$Encoding,
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        $Text = ""
    }

    $bytes = $Encoding.GetBytes($Text + "`r`n")
    $Stream.Write($bytes, 0, $bytes.Length)
    $Stream.Flush()
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

function Parse-SelIdOutput {
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

function Parse-SelStaOutput {
    param(
        [AllowNull()]
        [string]$Text
    )

    $clean = Remove-SelControlChars -Text $Text
    $serial = ""
    $fid = ""
    $cid = ""
    $partNum = ""

    if ($clean -match "Serial Num\s*=\s*(\d+)") { $serial = $Matches[1] }
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

function Parse-SelEthOutput {
    param(
        [AllowNull()]
        [string]$Text
    )

    $clean = Remove-SelControlChars -Text $Text
    $mac = ""
    $ip = ""
    $mask = ""
    $gateway = ""

    if ($clean -match "MAC:\s*([0-9A-Fa-f\-]+)") { $mac = $Matches[1].ToUpperInvariant() }
    if ($clean -match "IP ADDRESS:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)") { $ip = $Matches[1] }
    if ($clean -match "SUBNET MASK:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)") { $mask = $Matches[1] }
    if ($clean -match "DEFAULT GATEWAY:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)") { $gateway = $Matches[1] }

    return [pscustomobject]@{
        MAC = $mac
        IP = $ip
        Mask = $mask
        Gateway = $gateway
    }
}

function Invoke-SelTelnetInventoryCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostIp,
        [AllowNull()]
        [string]$AccPassword
    )

    $promptPattern = "(?m)^\s*=(>>|>)?\s*$"
    $client = New-Object System.Net.Sockets.TcpClient($HostIp, 23)
    $stream = $client.GetStream()
    $enc = [System.Text.Encoding]::ASCII
    $buf = New-Object byte[] 16384

    try {
        $banner = Read-SelTelnetAvailable -Stream $stream -Buffer $buf -Encoding $enc -InitialWaitMs 500
        Send-SelTelnetLine -Stream $stream -Encoding $enc -Text ""
        $prompt = Read-SelTelnetUntil -Stream $stream -Buffer $buf -Encoding $enc -Pattern $promptPattern

        Send-SelTelnetLine -Stream $stream -Encoding $enc -Text "ID"
        $idOut = Read-SelTelnetUntil -Stream $stream -Buffer $buf -Encoding $enc -Pattern $promptPattern

        $accOut = ""
        $accOk = $false
        $staOut = ""
        $ethOut = ""

        Send-SelTelnetLine -Stream $stream -Encoding $enc -Text "ACC"
        $accPrompt = Read-SelTelnetUntil -Stream $stream -Buffer $buf -Encoding $enc -Pattern "Password:|Invalid Access Level|Command Unavailable|$promptPattern"

        if ($accPrompt -match "Password:") {
            if (-not [string]::IsNullOrWhiteSpace($AccPassword)) {
                Send-SelTelnetLine -Stream $stream -Encoding $enc -Text $AccPassword
                $accResult = Read-SelTelnetUntil -Stream $stream -Buffer $buf -Encoding $enc -Pattern $promptPattern
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
            Send-SelTelnetLine -Stream $stream -Encoding $enc -Text "STA"
            $staOut = Read-SelTelnetUntil -Stream $stream -Buffer $buf -Encoding $enc -Pattern $promptPattern
            Send-SelTelnetLine -Stream $stream -Encoding $enc -Text "ETH"
            $ethOut = Read-SelTelnetUntil -Stream $stream -Buffer $buf -Encoding $enc -Pattern $promptPattern
        }

        return [pscustomobject]@{
            Banner = $banner
            Prompt = $prompt
            ID = $idOut
            ACC = $accOut
            AccOk = $accOk
            STA = $staOut
            ETH = $ethOut
        }
    }
    finally {
        try { $stream.Close() } catch {}
        try { $client.Close() } catch {}
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

function Resolve-SelReIpTarget {
    param(
        [string]$Serial,
        [string]$Ip,
        [string]$Mask,
        [string]$Gateway,
        [string]$DesiredStatePath = (Get-SelDataPath -ChildPath "desiredstate.csv"),
        [switch]$PromptIfMissing
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
        if (-not $resolvedIp) { $resolvedIp = Read-Host "Target IP" }
        if (-not $resolvedMask) { $resolvedMask = Read-Host "Target subnet mask" }
        if (-not $resolvedGateway) { $resolvedGateway = Read-Host "Target gateway" }
        if ($source -eq "cli" -and ($Ip -ne $resolvedIp -or $Mask -ne $resolvedMask -or $Gateway -ne $resolvedGateway)) {
            $source = "prompt"
        }
    }

    if (-not $resolvedIp -or -not $resolvedMask -or -not $resolvedGateway) {
        throw "Missing reip values. Provide CLI values, a desiredstate row for Serial, or use prompts."
    }

    return [pscustomobject]@{
        Serial = $Serial
        Ip = $resolvedIp
        Mask = $resolvedMask
        Gateway = $resolvedGateway
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
            Mac = $Mac
            DesiredIP = ""
            DesiredSubnetMask = ""
            DesiredGateway = ""
            DesiredFirmwareLabel = ""
            DesiredConfigSha256 = ""
            ObservedIP = ""
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

    if ($Mac) { $existing.Mac = $Mac }
    if ($ObservedIP) { $existing.ObservedIP = $ObservedIP }
    if ($ObservedFirmwareLabel) { $existing.ObservedFirmwareLabel = $ObservedFirmwareLabel }
    if ($ObservedFid) { $existing.ObservedFid = $ObservedFid }
    $existing.LastSeen = (Get-Date).ToString("s")
    $existing.LastAction = "inventory"
    $existing.LastResult = "success"

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
            events = @()
        }
    }

    $events = @($doc.events)
    $events += $Event
    $doc.events = $events
    $doc | ConvertTo-Json -Depth 8 | Set-Content $path
}

function Invoke-SelInventory {
    param(
        [string]$Serial,
        [string]$HostIp,
        [string]$Profile = "factory"
    )

    if (-not $Serial) {
        $Serial = Read-Host "Serial"
    }

    $defaults = Get-SelDefaults -Profile $Profile
    if (-not $HostIp) {
        $HostIp = [string]$defaults.DefaultIP
    }

    if (-not $HostIp) {
        throw "HostIp is required for inventory when DefaultIP is not set."
    }

    $capture = Invoke-SelTelnetInventoryCapture -HostIp $HostIp -AccPassword ([string]$defaults.ACCPassword)
    $idParsed = Parse-SelIdOutput -Text $capture.ID
    $staParsed = Parse-SelStaOutput -Text $capture.STA
    $ethParsed = Parse-SelEthOutput -Text $capture.ETH

    $observedSerial = [string]$staParsed.Serial
    if (-not $observedSerial) {
        $observedSerial = $Serial
    }
    if (-not $observedSerial) {
        throw "Could not determine serial from STA output and no Serial argument was provided."
    }

    $status = "success"
    if (-not $capture.AccOk) {
        $status = "id-only"
    }
    if ($Serial -and $staParsed.Serial -and $Serial -ne $staParsed.Serial) {
        $status = "serial-mismatch-warning"
    }

    $observedFid = ""
    if ($staParsed.FID) {
        $observedFid = [string]$staParsed.FID
    }
    elseif ($idParsed.PSObject.Properties.Name -contains "FID") {
        $observedFid = [string]$idParsed.FID
    }

    $event = [pscustomobject]@{
        timestamp = (Get-Date).ToString("s")
        action = "inventory"
        hostIp = $HostIp
        profile = $Profile
        defaultsDefaultIp = [string]$defaults.DefaultIP
        status = $status
        identity = [pscustomobject]@{
            requestedSerial = $Serial
            observedSerial = $observedSerial
        }
        inventory = [pscustomobject]@{
            ID = $idParsed
            STA = $staParsed
            ETH = $ethParsed
        }
        protocol = [pscustomobject]@{
            accOk = $capture.AccOk
        }
    }

    $observedIp = [string]$ethParsed.IP
    if (-not $observedIp) {
        $observedIp = $HostIp
    }

    Add-SelDeviceEvent -Serial $observedSerial -Event $event
    Update-SelDesiredStateObserved -Serial $observedSerial -Mac ([string]$ethParsed.MAC) -ObservedIP $observedIp -ObservedFirmwareLabel (Get-SelFirmwareLabelFromFid -Fid $observedFid) -ObservedFid $observedFid

    Write-Output ("Inventory collected for serial {0} from {1} (acc={2}, status={3})." -f $observedSerial, $HostIp, $capture.AccOk, $status)
}

function Invoke-SelReIp {
    param(
        [string]$Serial,
        [string]$HostIp,
        [string]$Ip,
        [string]$Mask,
        [string]$Gateway,
        [string]$Profile = "factory"
    )

    if (-not $Serial) {
        $Serial = Read-Host "Serial"
    }

    $defaults = Get-SelDefaults -Profile $Profile

    $target = Resolve-SelReIpTarget -Serial $Serial -Ip $Ip -Mask $Mask -Gateway $Gateway -PromptIfMissing

    $event = [pscustomobject]@{
        timestamp = (Get-Date).ToString("s")
        action = "reip"
        hostIp = $HostIp
        targetIp = $target.Ip
        targetMask = $target.Mask
        targetGateway = $target.Gateway
        source = $target.Source
        profile = $Profile
        defaultsDefaultIp = [string]$defaults.DefaultIP
        status = "scaffold"
        note = "SET P 1 automation not implemented yet."
    }

    Add-SelDeviceEvent -Serial $Serial -Event $event
    Write-Output ("ReIP scaffold target resolved: {0}/{1} gw {2} (source={3}, profile={4})" -f $target.Ip, $target.Mask, $target.Gateway, $target.Source, $Profile)
}

function Invoke-SelFwUpgrade {
    param(
        [string]$Serial,
        [string]$HostIp,
        [string]$Profile = "factory"
    )

    $null = Get-SelDefaults -Profile $Profile
    throw ("fwupgrade is not implemented in v0.1 scaffold yet (profile={0})." -f $Profile)
}

Export-ModuleMember -Function @(
    "Get-SelDefaultsRows",
    "Get-SelDefaults",
    "Get-SelDesiredStateRows",
    "Get-SelDesiredStateActiveRows",
    "Test-SelDesiredStateRowActive",
    "Parse-SelIdOutput",
    "Parse-SelStaOutput",
    "Parse-SelEthOutput",
    "Resolve-SelReIpTarget",
    "Update-SelDesiredStateObserved",
    "Add-SelDeviceEvent",
    "Invoke-SelInventory",
    "Invoke-SelReIp",
    "Invoke-SelFwUpgrade"
)
