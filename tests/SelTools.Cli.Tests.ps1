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

        Invoke-SelDispatch -CommandName "reip" -Serial "S1" -HostIp "192.168.1.2" -Ip "10.1.2.3" -Mask "255.255.255.0" -Gateway "10.1.2.1" -Profile "site-a"

        Assert-MockCalled Invoke-SelReIp -Times 1 -Exactly -ParameterFilter {
            $Serial -eq "S1" -and $HostIp -eq "192.168.1.2" -and $Ip -eq "10.1.2.3" -and $Mask -eq "255.255.255.0" -and $Gateway -eq "10.1.2.1" -and $Profile -eq "site-a"
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
        @("1", "", "", "", "5") | ForEach-Object { $inputs.Enqueue($_) }
        $readInput = {
            param([string]$Prompt)
            if ($inputs.Count -gt 0) {
                return $inputs.Dequeue()
            }
            return "5"
        }

        { Start-SelInteractiveMenu -ReadInput $readInput } | Should Not Throw
    }
}
