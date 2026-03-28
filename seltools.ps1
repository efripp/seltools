param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet("inventory", "reip", "fwupgrade")]
    [string]$Command,

    [string]$Serial,
    [string]$HostIp,
    [string]$Ip,
    [string]$Mask,
    [string]$Gateway,
    [string]$PrimaryInterface,
    [string]$Profile = "factory",
    [switch]$DebugTransport,
    [switch]$SkipInventoryUpdate
)

$modulePath = Join-Path $PSScriptRoot "src\SelTools\SelTools.psm1"
Import-Module $modulePath -Force
$script:SelToolsVersion = "v0.1.0"
$script:SelToolsArt = @'
      ::::::::  :::::::::: :::       ::::::::::: ::::::::   ::::::::  :::        :::::::: 
    :+:    :+: :+:        :+:           :+:    :+:    :+: :+:    :+: :+:       :+:    :+: 
   +:+        +:+        +:+           +:+    +:+    +:+ +:+    +:+ +:+       +:+         
  +#++:++#++ +#++:++#   +#+           +#+    +#+    +:+ +#+    +:+ +#+       +#++:++#++   
        +#+ +#+        +#+           +#+    +#+    +#+ +#+    +#+ +#+              +#+    
#+#+#+#+# #+#        #+#           #+#    #+#    #+# #+#    #+# #+#       #+#    #+#     
########  ########## ##########    ###     ########   ########  ########## ########       
'@

function Get-SelPromptValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [AllowNull()]
        [string]$CurrentValue,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ReadInput
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        $input = (& $ReadInput $Label)
    }
    else {
        $input = (& $ReadInput ("{0} [{1}]" -f $Label, $CurrentValue))
    }

    if ([string]::IsNullOrWhiteSpace($input)) {
        return $CurrentValue
    }

    return $input
}

function Get-SelPromptBoolValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [bool]$CurrentValue,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ReadInput
    )

    $defaultLabel = if ($CurrentValue) { "Y" } else { "N" }
    $input = (& $ReadInput ("{0} [{1}]" -f $Label, $defaultLabel))
    if ([string]::IsNullOrWhiteSpace($input)) {
        return $CurrentValue
    }

    switch -Regex ($input.Trim()) {
        '^(?i:y|yes|true|1)$' { return $true }
        '^(?i:n|no|false|0)$' { return $false }
        default { return $CurrentValue }
    }
}

function Show-SelMenu {
    Write-Host ""
    Write-Host "SelTools Main Menu"
    Write-Host "  1) inventory"
    Write-Host "  2) reip"
    Write-Host "  3) fwupgrade"
    Write-Host "  4) help"
    Write-Host "  5) exit"
}

function Show-SelInventorySubMenu {
    Write-Host ""
    Write-Host "Inventory Menu"
    Write-Host "  1) Single IP scan"
    Write-Host "  2) IP Range scan"
    Write-Host "  3) Inventory Browser"
}

function Show-SelHelp {
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\seltools.ps1 inventory -HostIp 192.168.1.2"
    Write-Host "  .\seltools.ps1 inventory -Serial 3241995707"
    Write-Host "  .\seltools.ps1 reip -Serial 3241995707 -Ip 192.168.1.101 -Mask 255.255.255.0 -Gateway 192.168.1.1"
    Write-Host "  .\seltools.ps1 fwupgrade -Serial 3241995707 -HostIp 192.168.1.2"
}

function Show-SelBanner {
    if (-not [string]::IsNullOrWhiteSpace($script:SelToolsArt)) {
        Write-Host $script:SelToolsArt
    }

    Write-Host ("Author: Eli Fripp <eli@fripp.us>")
    Write-Host ("Version: {0}" -f $script:SelToolsVersion)
    Write-Host ("Run Date: {0}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz"))
    Write-Host ""
}

function Start-SelInventoryBrowser {
    param(
        [int]$Port = 8080
    )

    $webDir = Join-Path $PSScriptRoot "web"
    $hostScript = Join-Path $webDir "start-web.ps1"
    if (-not (Test-Path -Path $hostScript -PathType Leaf)) {
        throw ("Inventory Browser host script not found: {0}" -f $hostScript)
    }

    $url = "http://localhost:{0}/" -f $Port
    $isUp = $false
    try {
        $probe = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2
        if ($probe.StatusCode -eq 200) {
            $isUp = $true
        }
    }
    catch {
        $isUp = $false
    }

    if (-not $isUp) {
        Start-Process -FilePath "powershell" -ArgumentList ("-ExecutionPolicy Bypass -NoProfile -File `"{0}`" -Port {1}" -f $hostScript, $Port) -WorkingDirectory $webDir -WindowStyle Minimized | Out-Null
        Start-Sleep -Milliseconds 1200
    }

    $chromePath = Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"
    $chromePathX86 = Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"
    $edgePath = Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe"
    $edgePathX86 = Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"

    $browserPath = $null
    foreach ($candidate in @($chromePath, $chromePathX86, $edgePath, $edgePathX86)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -Path $candidate -PathType Leaf)) {
            $browserPath = $candidate
            break
        }
    }

    if ($browserPath) {
        Start-Process -FilePath $browserPath -ArgumentList $url | Out-Null
        Write-Host ("Inventory Browser opened in Chromium browser: {0}" -f $url)
        Write-Host "In the web app, click Connect to data and browse to /seltools/data."
    }
    else {
        Start-Process $url | Out-Null
        Write-Warning ("No Chrome/Edge executable found. Open this URL in Chrome or Edge: {0}" -f $url)
        Write-Host "In the web app, click Connect to data and browse to /seltools/data."
    }
}

function Stop-SelInventoryBrowserService {
    $stopped = 0
    $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "powershell" -and $_.CommandLine -match "start-web\.ps1"
    }

    foreach ($proc in @($processes)) {
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
            $stopped++
        }
        catch {}
    }

    return $stopped
}

function Show-SelInventoryBrowserExitMenu {
    param(
        [scriptblock]$ReadInput = { param([string]$Prompt) Read-Host $Prompt }
    )

    while ($true) {
        Write-Host ""
        Write-Host "Inventory Browser Service"
        Write-Host "  1) Stop the web service"
        Write-Host "  2) Leave it running and return to main menu"
        $choice = (& $ReadInput "Select an option (1-2)")
        switch ($choice) {
            "1" {
                $stoppedCount = Stop-SelInventoryBrowserService
                if ($stoppedCount -gt 0) {
                    Write-Host ("Stopped {0} web service process(es)." -f $stoppedCount)
                }
                else {
                    Write-Host "Web service is not running."
                }
                return
            }
            "2" {
                Write-Host "Leaving Inventory Browser web service running."
                return
            }
            default {
                Write-Host ("Invalid selection '{0}'. Choose 1-2." -f $choice)
            }
        }
    }
}

function Resolve-SelMenuHostIpDefault {
    param(
        [string]$CurrentHostIp,
        [string]$Profile = "factory"
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentHostIp)) {
        return $CurrentHostIp
    }

    try {
        $defaults = Get-SelDefaults -Profile $Profile
        return [string]$defaults.DefaultIP
    }
    catch {
        return $CurrentHostIp
    }
}

function Invoke-SelDispatch {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("inventory", "reip", "fwupgrade")]
        [string]$CommandName,
        [string]$Serial,
        [string]$HostIp,
        [string]$Ip,
        [string]$Mask,
        [string]$Gateway,
        [string]$PrimaryInterface,
        [string]$Profile = "factory",
        [switch]$DebugTransport,
        [switch]$PassThru,
        [switch]$SkipInventoryUpdate
    )

    switch ($CommandName.ToLowerInvariant()) {
        "inventory" {
            Invoke-SelInventory -Serial $Serial -HostIp $HostIp -Profile $Profile -DebugTransport:$DebugTransport -PassThru:$PassThru
        }
        "reip" {
            Invoke-SelReIp -Serial $Serial -HostIp $HostIp -Ip $Ip -Mask $Mask -Gateway $Gateway -PrimaryInterface $PrimaryInterface -Profile $Profile -DebugTransport:$DebugTransport -PassThru:$PassThru -SkipInventoryUpdate:$SkipInventoryUpdate
        }
        "fwupgrade" {
            Invoke-SelFwUpgrade -Serial $Serial -HostIp $HostIp -Profile $Profile -DebugTransport:$DebugTransport
        }
    }
}

function Write-SelRunReport {
    param(
        [object[]]$Results = @()
    )

    $items = @($Results | Where-Object { $null -ne $_ -and $_.PSObject.Properties.Name -contains "Action" })
    Write-Host ""
    Write-Host "Run Report"
    if (-not $items -or $items.Count -eq 0) {
        Write-Host "  No actions recorded."
        return
    }

    $inventoryItems = @($items | Where-Object { $_.Action -eq "inventory" })
    $reipItems = @($items | Where-Object { $_.Action -eq "reip" })
    $newItems = @($inventoryItems | Where-Object { $_.IsNewDevice })
    $changedItems = @($inventoryItems | Where-Object { -not $_.IsNewDevice -and $_.Changes -and $_.Changes.Count -gt 0 })

    Write-Host ("  Actions: {0}" -f $items.Count)
    Write-Host ("  New devices discovered: {0}" -f $newItems.Count)
    foreach ($item in $newItems) {
        Write-Host ("    - Serial {0}, IP {1}" -f $item.Serial, $item.ObservedIp)
    }

    Write-Host ("  Existing devices with changes: {0}" -f $changedItems.Count)
    if ($changedItems.Count -eq 0) {
        Write-Host "  No changes detected."
    }
    else {
        foreach ($item in $changedItems) {
            Write-Host ("    - Serial {0}, IP {1}" -f $item.Serial, $item.ObservedIp)
            foreach ($change in @($item.Changes)) {
                Write-Host ("      * {0}" -f $change)
            }
        }
    }

    Write-Host ("  Re-IP actions: {0}" -f $reipItems.Count)
    if ($reipItems.Count -eq 0) {
        Write-Host "  No re-IP actions recorded."
    }
    else {
        foreach ($item in $reipItems) {
            $serialLabel = if ([string]::IsNullOrWhiteSpace([string]$item.Serial)) { "(unknown)" } else { [string]$item.Serial }
            $sourceIp = if ([string]::IsNullOrWhiteSpace([string]$item.HostIp)) { "(unknown)" } else { [string]$item.HostIp }
            $targetIp = if ([string]::IsNullOrWhiteSpace([string]$item.TargetIp)) { "(unknown)" } else { [string]$item.TargetIp }
            $statusLabel = if ([string]::IsNullOrWhiteSpace([string]$item.Status)) { "unknown" } else { [string]$item.Status }
            $skipLabel = if ($item.PSObject.Properties.Name -contains "SkipInventoryUpdate" -and $item.SkipInventoryUpdate) { " [inventory update skipped]" } else { "" }
            Write-Host ("    - Serial {0}, {1} -> {2}, status={3}{4}" -f $serialLabel, $sourceIp, $targetIp, $statusLabel, $skipLabel)
        }
    }
}

function Start-SelInteractiveMenu {
    param(
        [string]$Serial,
        [string]$HostIp,
        [string]$Ip,
        [string]$Mask,
        [string]$Gateway,
        [string]$PrimaryInterface,
        [string]$Profile = "factory",
        [switch]$DebugTransport,
        [switch]$SkipInventoryUpdate,
        [scriptblock]$ReadInput = { param([string]$Prompt) Read-Host $Prompt }
    )

    $runResults = @()
    $reipUpdateInventory = $false

    while ($true) {
        Show-SelMenu
        $choice = (& $ReadInput "Select an option (1-5)")

        switch ($choice) {
            "1" {
                Show-SelInventorySubMenu
                $inventoryChoice = (& $ReadInput "Select an inventory option (1-3)")

                switch ($inventoryChoice) {
                    "1" {
                        $HostIp = Resolve-SelMenuHostIpDefault -CurrentHostIp $HostIp -Profile $Profile
                        $HostIp = Get-SelPromptValue -Label "Host IP" -CurrentValue $HostIp -ReadInput $ReadInput
                        $Profile = Get-SelPromptValue -Label "Profile" -CurrentValue $Profile -ReadInput $ReadInput
                        $Serial = Get-SelPromptValue -Label "Serial (optional lookup when Host IP is blank)" -CurrentValue $Serial -ReadInput $ReadInput
                        try {
                            $result = Invoke-SelDispatch -CommandName "inventory" -Serial $Serial -HostIp $HostIp -Profile $Profile -DebugTransport:$DebugTransport -PassThru
                            if ($null -ne $result) {
                                $runResults += $result
                            }
                        }
                        catch {
                            Write-Host ("Inventory failed: {0}" -f $_.Exception.Message)
                        }
                    }
                    "2" {
                        Write-Host "IP Range scan is not implemented yet."
                    }
                    "3" {
                        try {
                            Start-SelInventoryBrowser
                            Show-SelInventoryBrowserExitMenu -ReadInput $ReadInput
                        }
                        catch {
                            Write-Host ("Inventory Browser failed: {0}" -f $_.Exception.Message)
                        }
                    }
                    default {
                        Write-Host ("Invalid inventory selection '{0}'. Choose 1-3." -f $inventoryChoice)
                    }
                }
            }
            "2" {
                $HostIp = Get-SelPromptValue -Label "Host IP" -CurrentValue $HostIp -ReadInput $ReadInput
                $Ip = Get-SelPromptValue -Label "Target IP" -CurrentValue $Ip -ReadInput $ReadInput
                $Mask = Get-SelPromptValue -Label "Target subnet mask" -CurrentValue $Mask -ReadInput $ReadInput
                $Gateway = Get-SelPromptValue -Label "Target gateway" -CurrentValue $Gateway -ReadInput $ReadInput
                $reipUpdateInventory = Get-SelPromptBoolValue -Label "Update inventory?" -CurrentValue $reipUpdateInventory -ReadInput $ReadInput
                $SkipInventoryUpdate = (-not $reipUpdateInventory)
                try {
                    $result = Invoke-SelDispatch -CommandName "reip" -Serial $Serial -HostIp $HostIp -Ip $Ip -Mask $Mask -Gateway $Gateway -PrimaryInterface $PrimaryInterface -Profile $Profile -DebugTransport:$DebugTransport -PassThru -SkipInventoryUpdate:$SkipInventoryUpdate
                    if ($null -ne $result) {
                        $runResults += $result
                        Write-SelRunReport -Results @($result)
                    }
                }
                catch {
                    Write-Host ("Re-IP failed: {0}" -f $_.Exception.Message)
                }
            }
            "3" {
                $HostIp = Resolve-SelMenuHostIpDefault -CurrentHostIp $HostIp -Profile $Profile
                $Serial = Get-SelPromptValue -Label "Serial" -CurrentValue $Serial -ReadInput $ReadInput
                $HostIp = Get-SelPromptValue -Label "Host IP" -CurrentValue $HostIp -ReadInput $ReadInput
                $Profile = Get-SelPromptValue -Label "Profile" -CurrentValue $Profile -ReadInput $ReadInput
                try {
                    Invoke-SelDispatch -CommandName "fwupgrade" -Serial $Serial -HostIp $HostIp -Profile $Profile -DebugTransport:$DebugTransport
                }
                catch {
                    Write-Host ("Firmware upgrade failed: {0}" -f $_.Exception.Message)
                }
            }
            "4" {
                Show-SelHelp
            }
            "5" {
                Write-SelRunReport -Results $runResults
                return
            }
            default {
                Write-Host ("Invalid selection '{0}'. Choose 1-5." -f $choice)
            }
        }
    }
}

if ($MyInvocation.InvocationName -eq ".") {
    return
}

Show-SelBanner

if ($Command) {
    $result = Invoke-SelDispatch -CommandName $Command -Serial $Serial -HostIp $HostIp -Ip $Ip -Mask $Mask -Gateway $Gateway -PrimaryInterface $PrimaryInterface -Profile $Profile -DebugTransport:$DebugTransport -PassThru -SkipInventoryUpdate:$SkipInventoryUpdate
    Write-SelRunReport -Results @($result)
}
else {
    Start-SelInteractiveMenu -Serial $Serial -HostIp $HostIp -Ip $Ip -Mask $Mask -Gateway $Gateway -PrimaryInterface $PrimaryInterface -Profile $Profile -DebugTransport:$DebugTransport -SkipInventoryUpdate:$SkipInventoryUpdate
}
