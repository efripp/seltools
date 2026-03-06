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

Describe "Defaults profile selection" {
    It "selects factory profile by default" {
        $tmp = Join-Path $TestDrive "defaults.csv"
        @'
Profile,DefaultIP,DefaultSubnetMask,TargetSubnetMask,TargetGateway,PoolStartIP,PoolEndIP,ACCPassword,2ACPassword,CALPassword,FtpUser,FtpPassword,TargetFirmwareLabel,TargetFirmwareFile,IdentifyEnabledDefault,RequireOUICheckDefault,AllowedOUIs
factory,192.168.1.2,255.255.255.0,255.255.255.0,192.168.1.1,192.168.1.100,192.168.1.199,OTTER,TAIL,CLARKE,ftp,ftp,SEL-751-R401,RELAY.ZDS,TRUE,FALSE,00-30-A7
site-a,10.10.0.10,255.255.255.0,255.255.255.0,10.10.0.1,10.10.0.100,10.10.0.199,,,,ftp,,SEL-751-R401,RELAY.ZDS,TRUE,FALSE,00-30-A7
'@ | Set-Content $tmp

        $row = Get-SelDefaults -Path $tmp
        $row.Profile | Should Be "factory"
        $row.ACCPassword | Should Be "OTTER"
    }

    It "selects an explicit profile" {
        $tmp = Join-Path $TestDrive "defaults.csv"
        @'
Profile,DefaultIP,DefaultSubnetMask,TargetSubnetMask,TargetGateway,PoolStartIP,PoolEndIP,ACCPassword,2ACPassword,CALPassword,FtpUser,FtpPassword,TargetFirmwareLabel,TargetFirmwareFile,IdentifyEnabledDefault,RequireOUICheckDefault,AllowedOUIs
factory,192.168.1.2,255.255.255.0,255.255.255.0,192.168.1.1,192.168.1.100,192.168.1.199,OTTER,TAIL,CLARKE,ftp,ftp,SEL-751-R401,RELAY.ZDS,TRUE,FALSE,00-30-A7
site-a,10.10.0.10,255.255.255.0,255.255.255.0,10.10.0.1,10.10.0.100,10.10.0.199,,,,ftp,,SEL-751-R401,RELAY.ZDS,TRUE,FALSE,00-30-A7
'@ | Set-Content $tmp

        $row = Get-SelDefaults -Profile "site-a" -Path $tmp
        $row.Profile | Should Be "site-a"
        $row.DefaultIP | Should Be "10.10.0.10"
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

Describe "Inventory parsers" {
    It "parses ID key/value fields" {
        $idText = @'
"FID=SEL-751-R401-V0-Z101100-D20240308","08A3"
"CID=1D4A","0267"
"DEVID=SEL-751","03C7"
'@
        $parsed = Parse-SelIdOutput -Text $idText
        $parsed.FID | Should Be "SEL-751-R401-V0-Z101100-D20240308"
        $parsed.CID | Should Be "1D4A"
        $parsed.DEVID | Should Be "SEL-751"
    }

    It "parses STA summary fields" {
        $staText = @'
Serial Num = 3241995707     FID = SEL-751-R401-V0-Z101100-D20240308
CID = 1D4A                  PART NUM = 751001A1A4A0X851G10
'@
        $parsed = Parse-SelStaOutput -Text $staText
        $parsed.Serial | Should Be "3241995707"
        $parsed.FID | Should Be "SEL-751-R401-V0-Z101100-D20240308"
        $parsed.CID | Should Be "1D4A"
        $parsed.PARTNUM | Should Be "751001A1A4A0X851G10"
    }

    It "parses ETH network fields" {
        $ethText = @'
MAC: 00-30-A7-3D-6F-A9
IP ADDRESS: 192.168.1.2
SUBNET MASK: 255.255.255.0
DEFAULT GATEWAY: 192.168.1.1
'@
        $parsed = Parse-SelEthOutput -Text $ethText
        $parsed.MAC | Should Be "00-30-A7-3D-6F-A9"
        $parsed.IP | Should Be "192.168.1.2"
        $parsed.Mask | Should Be "255.255.255.0"
        $parsed.Gateway | Should Be "192.168.1.1"
    }
}
