Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot "..\src\SelTools\SelTools.psm1"
Import-Module $modulePath -Force

Describe "Desired state filtering" {
    It "ignores TEMPLATE, blank serial, and inactive rows" {
        $tmp = Join-Path $TestDrive "desiredstate.csv"
        @'
Serial,Active,Mac,DesiredIP,DesiredSubnetMask,DesiredGateway,DesiredFirmwareLabel,DesiredConfigSha256,ObservedIP,ObservedFirmwareLabel,ObservedFid,LastSeen,LastAction,LastResult,Notes
3241995707,TRUE,00-30-A7-3D-6F-A9,192.168.1.101,255.255.255.0,192.168.1.1,SEL-751-R401,,,,,,,,
TEMPLATE,FALSE,,192.168.1.200,255.255.255.0,192.168.1.1,,,,,,,,
,TRUE,,192.168.1.201,255.255.255.0,192.168.1.1,,,,,,,,
3333333333,FALSE,,192.168.1.202,255.255.255.0,192.168.1.1,,,,,,,,
'@ | Set-Content $tmp

        $rows = @(Get-SelDesiredStateActiveRows -Path $tmp)
        $rows.Count | Should Be 1
        $rows[0].Serial | Should Be "3241995707"
    }
}

Describe "ReIP precedence" {
    It "prefers CLI values over desiredstate.csv" {
        $tmp = Join-Path $TestDrive "desiredstate.csv"
        @'
Serial,Active,Mac,DesiredIP,DesiredSubnetMask,DesiredGateway,DesiredFirmwareLabel,DesiredConfigSha256,ObservedIP,ObservedFirmwareLabel,ObservedFid,LastSeen,LastAction,LastResult,Notes
3241995707,TRUE,00-30-A7-3D-6F-A9,192.168.1.101,255.255.255.0,192.168.1.1,SEL-751-R401,,,,,,,,
'@ | Set-Content $tmp

        $result = Resolve-SelReIpTarget -Serial "3241995707" -Ip "10.1.2.3" -Mask "255.255.255.0" -Gateway "10.1.2.1" -DesiredStatePath $tmp
        $result.Ip | Should Be "10.1.2.3"
        $result.Mask | Should Be "255.255.255.0"
        $result.Gateway | Should Be "10.1.2.1"
    }

    It "falls back to desiredstate.csv when CLI values are missing" {
        $tmp = Join-Path $TestDrive "desiredstate.csv"
        @'
Serial,Active,Mac,DesiredIP,DesiredSubnetMask,DesiredGateway,DesiredFirmwareLabel,DesiredConfigSha256,ObservedIP,ObservedFirmwareLabel,ObservedFid,LastSeen,LastAction,LastResult,Notes
3241995707,TRUE,00-30-A7-3D-6F-A9,192.168.1.101,255.255.255.0,192.168.1.1,SEL-751-R401,,,,,,,,
'@ | Set-Content $tmp

        $result = Resolve-SelReIpTarget -Serial "3241995707" -DesiredStatePath $tmp
        $result.Ip | Should Be "192.168.1.101"
        $result.Mask | Should Be "255.255.255.0"
        $result.Gateway | Should Be "192.168.1.1"
        $result.Source | Should Be "desiredstate"
    }
}
