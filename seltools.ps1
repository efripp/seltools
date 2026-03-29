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
    [ValidateSet("enabled", "suppressed")]
    [string]$ConsoleOutput,
    [switch]$DebugTransport,
    [switch]$SkipInventoryUpdate
)

$modulePath = Join-Path $PSScriptRoot "src\SelTools\SelTools.psm1"
Import-Module $modulePath -Force -WarningAction SilentlyContinue
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

if ($ConsoleOutput) {
    Set-SelConsoleOutputPreference -Enabled:($ConsoleOutput -eq "enabled")
}

function Get-SelPromptValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [AllowNull()]
        [string]$CurrentValue,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ReadInput
    )

    Clear-SelProgressIndicator
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

    Clear-SelProgressIndicator
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
    Clear-SelProgressIndicator
    Write-Host ""
    Write-Host "SelTools Main Menu"
    Write-Host "  1) inventory"
    Write-Host "  2) reip"
    Write-Host "  3) fwupgrade"
    Write-Host "  4) help"
    Write-Host "  5) exit"
}

function Show-SelInventorySubMenu {
    Clear-SelProgressIndicator
    Write-Host ""
    Write-Host "Inventory Menu"
    Write-Host "  1) Single IP scan"
    Write-Host "  2) IP Range scan"
    Write-Host "  3) Inventory Browser"
}

function Show-SelReIpSubMenu {
    Clear-SelProgressIndicator
    Write-Host ""
    Write-Host "Re-IP Menu"
    Write-Host "  1) Single re-IP"
    Write-Host "  2) 1X1 Mass Provisioning"
}

function Show-SelMassProvisioningSubMenu {
    Clear-SelProgressIndicator
    Write-Host ""
    Write-Host "1X1 Mass Provisioning"
    Write-Host "  One SEL at the time should be added to the network in this mode."
    Write-Host "  1) Assign IP Range one by one"
    Write-Host "  2) Assign IP interactively one by one"
    Write-Host "  3) Assign IP from desiredstate.csv one by one"
}

function Show-SelHelp {
    Clear-SelProgressIndicator
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\seltools.ps1 inventory -HostIp 192.168.1.2"
    Write-Host "  .\seltools.ps1 inventory -Serial 3241995707"
    Write-Host "  .\seltools.ps1 reip -Serial 3241995707 -Ip 192.168.1.101 -Mask 255.255.255.0 -Gateway 192.168.1.1"
    Write-Host "  .\seltools.ps1 -ConsoleOutput suppressed"
    Write-Host "  .\seltools.ps1 -ConsoleOutput enabled"
    Write-Host "  .\seltools.ps1   # menu -> reip -> 1X1 Mass Provisioning"
    Write-Host "  .\seltools.ps1 fwupgrade -Serial 3241995707 -HostIp 192.168.1.2"
}

function Show-SelBanner {
    Clear-SelProgressIndicator
    $consoleEnabled = Test-SelConsoleOutputEnabled
    if (-not [string]::IsNullOrWhiteSpace($script:SelToolsArt)) {
        Write-Host $script:SelToolsArt
    }

    Write-Host ("Author: Eli Fripp <eli@fripp.us>")
    Write-Host ("Version: {0}" -f $script:SelToolsVersion)
    Write-Host ("Run Date: {0}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz"))
    if ($consoleEnabled) {
        Write-Host "Console output: enabled. Use .\seltools.ps1 -ConsoleOutput suppressed to change."
    }
    else {
        Write-Host "Console output: suppressed. Use .\seltools.ps1 -ConsoleOutput enabled to change."
    }
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
        Clear-SelProgressIndicator
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

    Clear-SelProgressIndicator
    $items = @($Results | Where-Object { $null -ne $_ -and $_.PSObject.Properties.Name -contains "Action" })
    Write-Host ""
    Write-Host "Run Report"
    if (-not $items -or $items.Count -eq 0) {
        Write-Host "  No actions recorded."
        return
    }

    $inventoryItems = @($items | Where-Object { $_.Action -eq "inventory" })
    $reipItems = @($items | Where-Object { $_.Action -eq "reip" })
    $massReipItems = @($items | Where-Object { $_.Action -eq "mass-reip" })
    $massReipAssignments = @($massReipItems | ForEach-Object { @($_.Results) } | Where-Object { $null -ne $_ })
    $newItems = @($inventoryItems | Where-Object { $_.IsNewDevice })
    $changedItems = @($inventoryItems | Where-Object { -not $_.IsNewDevice -and $_.Changes -and $_.Changes.Count -gt 0 })

    Write-Host ("  Actions: {0}" -f $items.Count)
    Write-Host ("  New devices discovered: {0}" -f $newItems.Count)
    foreach ($item in $newItems) {
        Write-Host ("    - Serial {0}, IP {1}" -f $item.Serial, $item.ObservedIp)
    }

    Write-Host ("  Existing devices with changes: {0}" -f $changedItems.Count)
    if ($inventoryItems.Count -gt 0 -and $changedItems.Count -eq 0) {
        Write-Host "  No changes detected."
    }
    elseif ($changedItems.Count -gt 0) {
        foreach ($item in $changedItems) {
            Write-Host ("    - Serial {0}, IP {1}" -f $item.Serial, $item.ObservedIp)
            foreach ($change in @($item.Changes)) {
                Write-Host ("      * {0}" -f $change)
            }
        }
    }

    Write-Host ("  Re-IP actions: {0}" -f ($reipItems.Count + $massReipAssignments.Count))
    if ($reipItems.Count -eq 0 -and $massReipAssignments.Count -eq 0) {
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
        if ($reipItems.Count -eq 0 -and $massReipAssignments.Count -gt 0) {
            Write-Host "    - Recorded through 1X1 Mass Provisioning session(s)"
        }
    }

    Write-Host ("  1X1 Mass Provisioning sessions: {0}" -f $massReipItems.Count)
    if ($massReipItems.Count -eq 0) {
        Write-Host "  No mass provisioning sessions recorded."
    }
    else {
        foreach ($session in $massReipItems) {
            $rows = @($session.Results)
            $successCount = @($rows | Where-Object { $_.Status -eq "success" }).Count
            $failedCount = if ($session.PSObject.Properties.Name -contains "FailureCount") { [int]$session.FailureCount } else { @($rows | Where-Object { $_.Status -eq "failed" }).Count }
            $skippedCount = @($rows | Where-Object { $_.Status -eq "skipped" -or $_.Status -eq "completed" }).Count
            Write-Host ("    - Mode={0}, source IP={1}, overall status={2}, success={3}, failed={4}, skipped={5}" -f [string]$session.Mode, [string]$session.HostIp, [string]$session.Status, $successCount, $failedCount, $skippedCount)
            foreach ($row in $rows) {
                $oldIp = if ([string]::IsNullOrWhiteSpace([string]$row.OldIp)) { "(unknown)" } else { [string]$row.OldIp }
                $newIp = if ([string]::IsNullOrWhiteSpace([string]$row.NewIp)) { "(none)" } else { [string]$row.NewIp }
                $serial = if ([string]::IsNullOrWhiteSpace([string]$row.Serial)) { "(unknown)" } else { [string]$row.Serial }
                $mac = if ([string]::IsNullOrWhiteSpace([string]$row.Mac)) { "(unknown)" } else { [string]$row.Mac }
                $note = if ([string]::IsNullOrWhiteSpace([string]$row.Note)) { "" } else { " note=" + [string]$row.Note }
                Write-Host ("      * #{0} Serial {1}, MAC {2}, {3} -> {4}, status={5}{6}" -f [int]$row.Sequence, $serial, $mac, $oldIp, $newIp, [string]$row.Status, $note)
            }
            $sessionFailureNotes = @()
            if ($session.PSObject.Properties.Name -contains "SessionFailures") {
                $sessionFailureNotes = @($session.SessionFailures)
            }
            if (@($sessionFailureNotes).Count -gt 0) {
                Write-Host "      Session-level failures:"
                foreach ($failure in $sessionFailureNotes) {
                    Write-Host ("        - #{0} {1}" -f [int]$failure.Sequence, [string]$failure.Note)
                }
            }
        }
    }
}

function Export-SelMassProvisioningCsv {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Result,
        [scriptblock]$ReadInput = { param([string]$Prompt) Read-Host $Prompt }
    )

    Clear-SelProgressIndicator
    $rows = @($Result.ExportRows)
    if ($rows.Count -eq 0) {
        Write-Host "No mass provisioning rows available to export."
        return
    }

    $exportChoice = (& $ReadInput "Export report to CSV? [Y/N]")
    if ($exportChoice -notmatch "^(?i)y(es)?$") {
        return
    }

    $defaultPath = Join-Path $PSScriptRoot ("data\mass-provisioning-{0}.csv" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))
    $pathInput = (& $ReadInput ("CSV path [{0}]" -f $defaultPath))
    $csvPath = if ([string]::IsNullOrWhiteSpace($pathInput)) { $defaultPath } else { $pathInput }

    $exportDir = Split-Path -Parent $csvPath
    if (-not [string]::IsNullOrWhiteSpace($exportDir) -and -not (Test-Path $exportDir)) {
        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    }

    $rows | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host ("Mass provisioning report exported to {0}" -f $csvPath)
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
                Show-SelReIpSubMenu
                $reipChoice = (& $ReadInput "Select a re-IP option (1-2)")
                switch ($reipChoice) {
                    "1" {
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
                    "2" {
                        Show-SelMassProvisioningSubMenu
                        $massChoice = (& $ReadInput "Select a mass provisioning option (1-3)")
                        $reipUpdateInventory = Get-SelPromptBoolValue -Label "Update inventory?" -CurrentValue $reipUpdateInventory -ReadInput $ReadInput
                        $SkipInventoryUpdate = (-not $reipUpdateInventory)
                        $defaultHostIp = Resolve-SelMenuHostIpDefault -CurrentHostIp $HostIp -Profile $Profile
                        $massHostIp = Get-SelPromptValue -Label "Default/current relay IP" -CurrentValue $defaultHostIp -ReadInput $ReadInput
                        try {
                            $massResult = $null
                            switch ($massChoice) {
                                "1" {
                                    $defaults = Get-SelDefaults -Profile $Profile
                                    $rangeStart = Get-SelPromptValue -Label "Start IP" -CurrentValue ([string]$defaults.PoolStartIP) -ReadInput $ReadInput
                                    $rangeEnd = Get-SelPromptValue -Label "End IP" -CurrentValue ([string]$defaults.PoolEndIP) -ReadInput $ReadInput
                                    $rangeMask = Get-SelPromptValue -Label "Target subnet mask" -CurrentValue ([string]$defaults.TargetSubnetMask) -ReadInput $ReadInput
                                    $rangeGateway = Get-SelPromptValue -Label "Target gateway" -CurrentValue ([string]$defaults.TargetGateway) -ReadInput $ReadInput
                                    $massResult = Invoke-SelMassProvisioning -Mode "range" -HostIp $massHostIp -StartIp $rangeStart -EndIp $rangeEnd -Mask $rangeMask -Gateway $rangeGateway -Profile $Profile -DebugTransport:$DebugTransport -PassThru -SkipInventoryUpdate:$SkipInventoryUpdate -ReadInput $ReadInput
                                }
                                "2" {
                                    $defaults = Get-SelDefaults -Profile $Profile
                                    $interactiveMask = Get-SelPromptValue -Label "Default subnet mask" -CurrentValue ([string]$defaults.TargetSubnetMask) -ReadInput $ReadInput
                                    $interactiveGateway = Get-SelPromptValue -Label "Default gateway" -CurrentValue ([string]$defaults.TargetGateway) -ReadInput $ReadInput
                                    $massResult = Invoke-SelMassProvisioning -Mode "interactive" -HostIp $massHostIp -Mask $interactiveMask -Gateway $interactiveGateway -Profile $Profile -DebugTransport:$DebugTransport -PassThru -SkipInventoryUpdate:$SkipInventoryUpdate -ReadInput $ReadInput
                                }
                                "3" {
                                    $massResult = Invoke-SelMassProvisioning -Mode "desiredstate" -HostIp $massHostIp -Profile $Profile -DebugTransport:$DebugTransport -PassThru -SkipInventoryUpdate:$SkipInventoryUpdate -ReadInput $ReadInput
                                }
                                default {
                                    Write-Host ("Invalid mass provisioning selection '{0}'. Choose 1-3." -f $massChoice)
                                }
                            }

                            if ($null -ne $massResult) {
                                $runResults += $massResult
                                Write-SelRunReport -Results @($massResult)
                                Export-SelMassProvisioningCsv -Result $massResult -ReadInput $ReadInput
                            }
                        }
                        catch {
                            Write-Host ("Mass provisioning failed: {0}" -f $_.Exception.Message)
                        }
                    }
                    default {
                        Write-Host ("Invalid re-IP selection '{0}'. Choose 1-2." -f $reipChoice)
                    }
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
