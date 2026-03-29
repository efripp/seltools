Set-StrictMode -Version Latest

$scriptPath = Join-Path $PSScriptRoot "..\seltools.ps1"
$modulePath = Join-Path $PSScriptRoot "..\src\SelTools\SelTools.psm1"
Import-Module $modulePath -Force

Describe "CLI helper behavior" {
    BeforeEach {
        . $scriptPath
    }

    It "Get-SelPromptValue keeps existing value when input is blank" {
        $readInput = { param([string]$Prompt) "" }
        $result = Get-SelPromptValue -Label "Profile" -CurrentValue "site-a" -ReadInput $readInput
        $result | Should Be "site-a"
    }

    It "Get-SelPromptValue uses entered value when provided" {
        $readInput = { param([string]$Prompt) "new-value" }
        $result = Get-SelPromptValue -Label "Profile" -CurrentValue "site-a" -ReadInput $readInput
        $result | Should Be "new-value"
    }

    It "Show-SelBanner still prints branding when console output is suppressed" {
        Mock Test-SelConsoleOutputEnabled { $false }

        $output = & {
            Show-SelBanner
        } 6>&1

        (($output | ForEach-Object { $_.ToString() }) -join "`n") | Should Match "Author: Eli Fripp"
        (($output | ForEach-Object { $_.ToString() }) -join "`n") | Should Match "Console output: suppressed"
        (($output | ForEach-Object { $_.ToString() }) -join "`n") | Should Match "::::::::"
    }

    It "Invoke-SelDispatch routes inventory with expected arguments" {
        $script:calledInventory = $null
        function Invoke-SelInventory {
            param($Serial, $HostIp, $Profile)
            $script:calledInventory = [pscustomobject]@{ Serial = $Serial; HostIp = $HostIp; Profile = $Profile }
        }

        Invoke-SelDispatch -CommandName "inventory" -Serial "S1" -HostIp "192.168.1.2" -Profile "site-a"

        $script:calledInventory.Serial | Should Be "S1"
        $script:calledInventory.HostIp | Should Be "192.168.1.2"
        $script:calledInventory.Profile | Should Be "site-a"
    }

    It "Invoke-SelDispatch routes reip with expected arguments" {
        $script:calledReIp = $null
        function Invoke-SelReIp {
            param($Serial, $HostIp, $Ip, $Mask, $Gateway, $PrimaryInterface, $Profile)
            $script:calledReIp = [pscustomobject]@{
                Serial = $Serial; HostIp = $HostIp; Ip = $Ip; Mask = $Mask; Gateway = $Gateway; PrimaryInterface = $PrimaryInterface; Profile = $Profile
            }
        }

        Invoke-SelDispatch -CommandName "reip" -Serial "S1" -HostIp "192.168.1.2" -Ip "10.1.2.3" -Mask "255.255.255.0" -Gateway "10.1.2.1" -PrimaryInterface "1A" -Profile "site-a"

        $script:calledReIp.Serial | Should Be "S1"
        $script:calledReIp.HostIp | Should Be "192.168.1.2"
        $script:calledReIp.Ip | Should Be "10.1.2.3"
        $script:calledReIp.Mask | Should Be "255.255.255.0"
        $script:calledReIp.Gateway | Should Be "10.1.2.1"
        $script:calledReIp.PrimaryInterface | Should Be "1A"
        $script:calledReIp.Profile | Should Be "site-a"
    }

    It "Invoke-SelDispatch forwards SkipInventoryUpdate for reip" {
        $script:calledReIp = $null
        function Invoke-SelReIp {
            param($Serial, $HostIp, $Ip, $Profile, [switch]$SkipInventoryUpdate)
            $script:calledReIp = [pscustomobject]@{ Serial = $Serial; HostIp = $HostIp; Ip = $Ip; Profile = $Profile; SkipInventoryUpdate = [bool]$SkipInventoryUpdate }
        }

        Invoke-SelDispatch -CommandName "reip" -Serial "S1" -HostIp "192.168.1.2" -Ip "10.1.2.3" -Profile "site-a" -SkipInventoryUpdate

        $script:calledReIp.SkipInventoryUpdate | Should Be $true
    }

    It "Start-SelInteractiveMenu reip path no longer prompts for primary interface" {
        function Invoke-SelReIp { [pscustomobject]@{ Action = "reip"; Status = "success"; Serial = "S1"; HostIp = "192.168.1.2"; TargetIp = "10.1.2.3" } }

        $inputs = New-Object 'System.Collections.Generic.Queue[string]'
        @("2", "1", "192.168.1.2", "10.1.2.3", "255.255.255.0", "10.1.2.1", "n", "5") | ForEach-Object { $inputs.Enqueue($_) }
        $seenPrompts = New-Object 'System.Collections.Generic.List[string]'
        $readInput = {
            param([string]$Prompt)
            [void]$seenPrompts.Add($Prompt)
            if ($inputs.Count -gt 0) {
                return $inputs.Dequeue()
            }
            return "5"
        }

        { Start-SelInteractiveMenu -ReadInput $readInput } | Should Not Throw
        ($seenPrompts -contains "Primary interface (1A or 1B)") | Should Be $false
        ($seenPrompts -contains "Serial") | Should Be $false
        ($seenPrompts -contains "Profile") | Should Be $false
    }

    It "Start-SelInteractiveMenu reip path remembers SkipInventoryUpdate selection" {
        function Invoke-SelReIp { [pscustomobject]@{ Action = "reip"; Status = "success"; Serial = "S1"; HostIp = "192.168.1.2"; TargetIp = "10.1.2.3" } }

        $inputs = New-Object 'System.Collections.Generic.Queue[string]'
        @(
            "2", "1", "192.168.1.2", "10.1.2.3", "", "", "y",
            "2", "1", "192.168.1.2", "10.1.2.4", "", "", "",
            "5"
        ) | ForEach-Object { $inputs.Enqueue($_) }
        $seenPrompts = New-Object 'System.Collections.Generic.List[string]'
        $readInput = {
            param([string]$Prompt)
            [void]$seenPrompts.Add($Prompt)
            if ($inputs.Count -gt 0) {
                return $inputs.Dequeue()
            }
            return "5"
        }

        { Start-SelInteractiveMenu -ReadInput $readInput } | Should Not Throw
        @($seenPrompts | Where-Object { $_ -eq "Update inventory? [Y]" }).Count | Should BeGreaterThan 0
    }

    It "Start-SelInteractiveMenu reip path no longer prompts for serial or profile" {
        function Invoke-SelReIp { [pscustomobject]@{ Action = "reip"; Status = "success"; Serial = "S1"; HostIp = "192.168.1.2"; TargetIp = "10.1.2.3" } }

        $inputs = New-Object 'System.Collections.Generic.Queue[string]'
        @("2", "1", "192.168.1.2", "10.1.2.3", "", "", "n", "5") | ForEach-Object { $inputs.Enqueue($_) }
        $seenPrompts = New-Object 'System.Collections.Generic.List[string]'
        $readInput = {
            param([string]$Prompt)
            [void]$seenPrompts.Add($Prompt)
            if ($inputs.Count -gt 0) {
                return $inputs.Dequeue()
            }
            return "5"
        }

        { Start-SelInteractiveMenu -ReadInput $readInput } | Should Not Throw
        ($seenPrompts -contains "Serial") | Should Be $false
        ($seenPrompts -contains "Profile") | Should Be $false
        ($seenPrompts -contains "Select a re-IP option (1-2)") | Should Be $true
        ($seenPrompts -contains "Host IP") | Should Be $true
        ($seenPrompts -contains "Target IP") | Should Be $true
        ($seenPrompts -contains "Update inventory? [N]") | Should Be $true
    }

    It "Start-SelInteractiveMenu reip path offers 1X1 mass provisioning and export prompt" {
        function Get-SelDefaults {
            [pscustomobject]@{
                DefaultIP = "192.168.1.2"
                PoolStartIP = "192.168.1.100"
                PoolEndIP = "192.168.1.101"
                TargetSubnetMask = "255.255.255.0"
                TargetGateway = "192.168.1.1"
            }
        }
        function Invoke-SelMassProvisioning {
            [pscustomobject]@{
                Action = "mass-reip"
                Mode = "range"
                Status = "completed"
                HostIp = "192.168.1.2"
                SkipInventoryUpdate = $true
                Results = @(
                    [pscustomobject]@{
                        Sequence = 1
                        Status = "success"
                        Serial = "3250985195"
                        Mac = "00-30-A7-42-2F-B2"
                        OldIp = "192.168.1.2"
                        NewIp = "192.168.1.100"
                        Note = ""
                    }
                )
                ExportRows = @(
                    [pscustomobject]@{
                        Sequence = 1
                        Status = "success"
                        Serial = "3250985195"
                        Mac = "00-30-A7-42-2F-B2"
                        OldIp = "192.168.1.2"
                        NewIp = "192.168.1.100"
                    }
                )
            }
        }

        $inputs = New-Object 'System.Collections.Generic.Queue[string]'
        @("2", "2", "1", "n", "192.168.1.2", "192.168.1.100", "192.168.1.101", "255.255.255.0", "192.168.1.1", "n", "5") | ForEach-Object { $inputs.Enqueue($_) }
        $seenPrompts = New-Object 'System.Collections.Generic.List[string]'
        $readInput = {
            param([string]$Prompt)
            [void]$seenPrompts.Add($Prompt)
            if ($inputs.Count -gt 0) {
                return $inputs.Dequeue()
            }
            return "5"
        }

        { Start-SelInteractiveMenu -ReadInput $readInput } | Should Not Throw
        ($seenPrompts -contains "Select a re-IP option (1-2)") | Should Be $true
        ($seenPrompts -contains "Select a mass provisioning option (1-3)") | Should Be $true
        ($seenPrompts -contains "Export report to CSV? [Y/N]") | Should Be $true
    }

    It "Invoke-SelDispatch routes reip without requiring Serial" {
        $script:calledReIp = $null
        function Invoke-SelReIp {
            param($Serial, $HostIp, $Ip, $Profile)
            $script:calledReIp = [pscustomobject]@{ Serial = $Serial; HostIp = $HostIp; Ip = $Ip; Profile = $Profile }
        }

        Invoke-SelDispatch -CommandName "reip" -HostIp "192.168.1.2" -Ip "10.1.2.3" -Profile "site-a"

        [string]::IsNullOrWhiteSpace($script:calledReIp.Serial) | Should Be $true
        $script:calledReIp.HostIp | Should Be "192.168.1.2"
        $script:calledReIp.Ip | Should Be "10.1.2.3"
        $script:calledReIp.Profile | Should Be "site-a"
    }

    It "Invoke-SelDispatch forwards DebugTransport switch" {
        $script:calledInventory = $null
        function Invoke-SelInventory {
            param($HostIp, $Profile, [switch]$DebugTransport)
            $script:calledInventory = [pscustomobject]@{ HostIp = $HostIp; Profile = $Profile; DebugTransport = [bool]$DebugTransport }
        }

        Invoke-SelDispatch -CommandName "inventory" -HostIp "192.168.1.2" -Profile "factory" -DebugTransport

        $script:calledInventory.HostIp | Should Be "192.168.1.2"
        $script:calledInventory.Profile | Should Be "factory"
        $script:calledInventory.DebugTransport | Should Be $true
    }

    It "Resolve-SelMenuHostIpDefault uses profile default ip when current is blank" {
        function Get-SelDefaults {
            [pscustomobject]@{ DefaultIP = "192.168.1.2" }
        }

        $result = Resolve-SelMenuHostIpDefault -CurrentHostIp "" -Profile "factory"
        $result | Should Be "192.168.1.2"
    }

    It "Start-SelInteractiveMenu exits on option 5" {
        $callsRef = [ref]0
        $readInput = {
            param([string]$Prompt)
            $callsRef.Value++
            if ($callsRef.Value -eq 1) { return "5" }
            throw "ReadInput called unexpectedly after exit selection."
        }

        { Start-SelInteractiveMenu -ReadInput $readInput } | Should Not Throw
    }

    It "Start-SelInteractiveMenu handles operation exceptions without throwing" {
        function Invoke-SelInventory { throw "forced failure" }

        $inputs = New-Object 'System.Collections.Generic.Queue[string]'
        @("1", "1", "", "", "", "5") | ForEach-Object { $inputs.Enqueue($_) }
        $readInput = {
            param([string]$Prompt)
            if ($inputs.Count -gt 0) {
                return $inputs.Dequeue()
            }
            return "5"
        }

        { Start-SelInteractiveMenu -ReadInput $readInput } | Should Not Throw
    }

    It "Start-SelInteractiveMenu inventory option 3 can leave browser service running" {
        Mock Start-SelInventoryBrowser { }
        Mock Stop-SelInventoryBrowserService { 0 }

        $inputs = New-Object 'System.Collections.Generic.Queue[string]'
        @("1", "3", "2", "5") | ForEach-Object { $inputs.Enqueue($_) }
        $readInput = {
            param([string]$Prompt)
            if ($inputs.Count -gt 0) {
                return $inputs.Dequeue()
            }
            return "5"
        }

        { Start-SelInteractiveMenu -ReadInput $readInput } | Should Not Throw
        Assert-MockCalled Start-SelInventoryBrowser -Times 1 -Exactly
        Assert-MockCalled Stop-SelInventoryBrowserService -Times 0
    }

    It "Inventory browser exit menu can stop browser service" {
        Mock Stop-SelInventoryBrowserService { 1 }
        $inputs = New-Object 'System.Collections.Generic.Queue[string]'
        @("1") | ForEach-Object { $inputs.Enqueue($_) }
        $readInput = {
            param([string]$Prompt)
            return $inputs.Dequeue()
        }

        { Show-SelInventoryBrowserExitMenu -ReadInput $readInput } | Should Not Throw
    }

    It "Inventory browser exit menu re-prompts on invalid selection" {
        Mock Stop-SelInventoryBrowserService { 0 }
        $inputs = New-Object 'System.Collections.Generic.Queue[string]'
        @("x", "2") | ForEach-Object { $inputs.Enqueue($_) }
        $readInput = {
            param([string]$Prompt)
            return $inputs.Dequeue()
        }

        { Show-SelInventoryBrowserExitMenu -ReadInput $readInput } | Should Not Throw
        Assert-MockCalled Stop-SelInventoryBrowserService -Times 0
    }

    It "Write-SelRunReport includes reip IP transition details" {
        $result = [pscustomobject]@{
            Action = "reip"
            Status = "success"
            Serial = "3250985195"
            HostIp = "192.168.1.2"
            TargetIp = "192.168.1.3"
            SkipInventoryUpdate = $true
        }

        $output = & {
            Write-SelRunReport -Results @($result)
        } 6>&1

        (($output | ForEach-Object { $_.ToString() }) -join "`n") | Should Match "Re-IP actions: 1"
        (($output | ForEach-Object { $_.ToString() }) -join "`n") | Should Match "192\.168\.1\.2 -> 192\.168\.1\.3"
        (($output | ForEach-Object { $_.ToString() }) -join "`n") | Should Match "inventory update skipped"
    }

    It "Write-SelRunReport includes mass provisioning mapping details" {
        $result = [pscustomobject]@{
            Action = "mass-reip"
            Mode = "desiredstate"
            Status = "completed-with-failures"
            HostIp = "192.168.1.80"
            FailureCount = 1
            Results = @(
                [pscustomobject]@{
                    Sequence = 1
                    Status = "success"
                    Serial = "3250985195"
                    Mac = "00-30-A7-42-2F-B2"
                    OldIp = "192.168.1.80"
                    NewIp = "192.168.1.10"
                    Note = ""
                }
            )
            SessionFailures = @(
                [pscustomobject]@{
                    Sequence = 2
                    Note = "Default/current IP 192.168.1.80 is not reachable by ping (DestinationHostUnreachable)."
                }
            )
        }

        $output = & {
            Write-SelRunReport -Results @($result)
        } 6>&1

        (($output | ForEach-Object { $_.ToString() }) -join "`n") | Should Match "1X1 Mass Provisioning sessions: 1"
        (($output | ForEach-Object { $_.ToString() }) -join "`n") | Should Match "Mode=desiredstate"
        (($output | ForEach-Object { $_.ToString() }) -join "`n") | Should Match "3250985195"
        (($output | ForEach-Object { $_.ToString() }) -join "`n") | Should Match "192\.168\.1\.80 -> 192\.168\.1\.10"
        (($output | ForEach-Object { $_.ToString() }) -join "`n") | Should Match "Session-level failures:"
        (($output | ForEach-Object { $_.ToString() }) -join "`n") | Should Match "192\.168\.1\.80 is not reachable by ping"
    }
}
