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

    It "Invoke-SelDispatch routes inventory with expected arguments" {
        Mock Invoke-SelInventory { }

        Invoke-SelDispatch -CommandName "inventory" -Serial "S1" -HostIp "192.168.1.2" -Profile "site-a"

        Assert-MockCalled Invoke-SelInventory -Times 1 -Exactly -ParameterFilter {
            $Serial -eq "S1" -and $HostIp -eq "192.168.1.2" -and $Profile -eq "site-a"
        }
    }

    It "Invoke-SelDispatch routes reip with expected arguments" {
        Mock Invoke-SelReIp { }

        Invoke-SelDispatch -CommandName "reip" -Serial "S1" -HostIp "192.168.1.2" -Ip "10.1.2.3" -Mask "255.255.255.0" -Gateway "10.1.2.1" -PrimaryInterface "1A" -Profile "site-a"

        Assert-MockCalled Invoke-SelReIp -Times 1 -Exactly -ParameterFilter {
            $Serial -eq "S1" -and $HostIp -eq "192.168.1.2" -and $Ip -eq "10.1.2.3" -and $Mask -eq "255.255.255.0" -and $Gateway -eq "10.1.2.1" -and $PrimaryInterface -eq "1A" -and $Profile -eq "site-a"
        }
    }

    It "Invoke-SelDispatch forwards SkipInventoryUpdate for reip" {
        Mock Invoke-SelReIp { }

        Invoke-SelDispatch -CommandName "reip" -Serial "S1" -HostIp "192.168.1.2" -Ip "10.1.2.3" -Profile "site-a" -SkipInventoryUpdate

        Assert-MockCalled Invoke-SelReIp -Times 1 -Exactly -ParameterFilter {
            $Serial -eq "S1" -and $HostIp -eq "192.168.1.2" -and $Ip -eq "10.1.2.3" -and $Profile -eq "site-a" -and $SkipInventoryUpdate
        }
    }

    It "Start-SelInteractiveMenu reip path no longer prompts for primary interface" {
        Mock Invoke-SelDispatch { }

        $inputs = New-Object 'System.Collections.Generic.Queue[string]'
        @("2", "192.168.1.2", "10.1.2.3", "255.255.255.0", "10.1.2.1", "n", "5") | ForEach-Object { $inputs.Enqueue($_) }
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
        Mock Invoke-SelDispatch { }

        $inputs = New-Object 'System.Collections.Generic.Queue[string]'
        @(
            "2", "192.168.1.2", "10.1.2.3", "", "", "y",
            "2", "192.168.1.2", "10.1.2.4", "", "", "",
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
        Mock Invoke-SelDispatch { }

        $inputs = New-Object 'System.Collections.Generic.Queue[string]'
        @("2", "192.168.1.2", "10.1.2.3", "", "", "n", "5") | ForEach-Object { $inputs.Enqueue($_) }
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
        ($seenPrompts -contains "Host IP") | Should Be $true
        ($seenPrompts -contains "Target IP") | Should Be $true
        ($seenPrompts -contains "Update inventory? [N]") | Should Be $true
    }

    It "Invoke-SelDispatch routes reip without requiring Serial" {
        Mock Invoke-SelReIp { }

        Invoke-SelDispatch -CommandName "reip" -HostIp "192.168.1.2" -Ip "10.1.2.3" -Profile "site-a"

        Assert-MockCalled Invoke-SelReIp -Times 1 -Exactly -ParameterFilter {
            [string]::IsNullOrWhiteSpace($Serial) -and $HostIp -eq "192.168.1.2" -and $Ip -eq "10.1.2.3" -and $Profile -eq "site-a"
        }
    }

    It "Invoke-SelDispatch forwards DebugTransport switch" {
        Mock Invoke-SelInventory { }

        Invoke-SelDispatch -CommandName "inventory" -HostIp "192.168.1.2" -Profile "factory" -DebugTransport

        Assert-MockCalled Invoke-SelInventory -Times 1 -Exactly -ParameterFilter {
            $HostIp -eq "192.168.1.2" -and $Profile -eq "factory" -and $DebugTransport
        }
    }

    It "Resolve-SelMenuHostIpDefault uses profile default ip when current is blank" {
        Mock Get-SelDefaults {
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
        Mock Invoke-SelDispatch { throw "forced failure" }

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
}
