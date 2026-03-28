Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot "..\src\SelTools\SelTools.psm1"
Import-Module $modulePath -Force

Describe "Desired state filtering" {
    It "ignores TEMPLATE, blank serial, and inactive rows" {
        $tmp = Join-Path $TestDrive "desiredstate.csv"
        @'
Serial,Active,Name,Description,Mac,DesiredIP,DesiredSubnetMask,DesiredGateway,DesiredFirmwareLabel,DesiredConfigSha256,ObservedIP,ObservedFirmwareLabel,ObservedFid,LastSeen,LastAction,LastResult,Notes
3241995707,TRUE,Feeder 751,Primary feeder relay,00-30-A7-3D-6F-A9,192.168.1.101,255.255.255.0,192.168.1.1,SEL-751-R401,,,,,,,,
TEMPLATE,FALSE,,,,192.168.1.200,255.255.255.0,192.168.1.1,,,,,,,,
,TRUE,,,,192.168.1.201,255.255.255.0,192.168.1.1,,,,,,,,
3333333333,FALSE,,,,192.168.1.202,255.255.255.0,192.168.1.1,,,,,,,,
'@ | Set-Content $tmp

        $rows = @(Get-SelDesiredStateActiveRows -Path $tmp)
        $rows.Count | Should Be 1
        $rows[0].Serial | Should Be "3241995707"
    }

    It "reads name/description metadata by serial" {
        $tmp = Join-Path $TestDrive "desiredstate.csv"
        @'
Serial,Active,Name,Description,Mac,DesiredIP,DesiredSubnetMask,DesiredGateway,DesiredFirmwareLabel,DesiredConfigSha256,ObservedIP,ObservedFirmwareLabel,ObservedFid,LastSeen,LastAction,LastResult,Notes
3241995707,TRUE,Feeder 751,Primary feeder relay,00-30-A7-3D-6F-A9,192.168.1.101,255.255.255.0,192.168.1.1,SEL-751-R401,,,,,,,,
'@ | Set-Content $tmp

        $meta = Get-SelDesiredStateMetadata -Serial "3241995707" -DesiredStatePath $tmp
        $meta.Name | Should Be "Feeder 751"
        $meta.Description | Should Be "Primary feeder relay"
    }

    It "resolves metadata preferring desiredstate and filling blanks from device json" {
        $desired = [pscustomobject]@{
            Name = ""
            Description = "From desiredstate"
        }
        $device = [pscustomobject]@{
            Name = "From json"
            Description = "From json"
        }

        $resolved = Resolve-SelMetadata -DesiredStateMetadata $desired -DeviceMetadata $device
        $resolved.Name | Should Be "From json"
        $resolved.Description | Should Be "From desiredstate"
    }

    It "updates desiredstate name/description on observed update when provided" {
        $tmp = Join-Path $TestDrive "desiredstate.csv"
        @'
Serial,Active,Name,Description,Mac,DesiredIP,DesiredSubnetMask,DesiredGateway,DesiredFirmwareLabel,DesiredConfigSha256,ObservedIP,ObservedFirmwareLabel,ObservedFid,LastSeen,LastAction,LastResult,Notes
3241995707,TRUE,,,00-30-A7-3D-6F-A9,192.168.1.101,255.255.255.0,192.168.1.1,SEL-751-R401,,,,,,,,
'@ | Set-Content $tmp

        Update-SelDesiredStateObserved -Serial "3241995707" -Name "Feeder 751" -Description "Primary feeder relay" -DesiredStatePath $tmp
        $rows = @(Import-Csv -Path $tmp)
        $rows[0].Name | Should Be "Feeder 751"
        $rows[0].Description | Should Be "Primary feeder relay"
    }

    It "adds observed Ethernet interface columns on update" {
        $tmp = Join-Path $TestDrive "desiredstate.csv"
        @'
Serial,Active,Name,Description,Mac,DesiredIP,DesiredSubnetMask,DesiredGateway,DesiredFirmwareLabel,DesiredConfigSha256,ObservedIP,ObservedFirmwareLabel,ObservedFid,LastSeen,LastAction,LastResult,Notes
3241995707,TRUE,,,00-30-A7-3D-6F-A9,192.168.1.101,255.255.255.0,192.168.1.1,SEL-751-R401,,,,,,,,
'@ | Set-Content $tmp

        Update-SelDesiredStateObserved -Serial "3241995707" -ObservedPrimaryInterface "1A" -ObservedActiveInterface "1B" -ObservedNetMode "FAILOVER" -DesiredStatePath $tmp
        $rows = @(Import-Csv -Path $tmp)
        $rows[0].ObservedPrimaryInterface | Should Be "1A"
        $rows[0].ObservedActiveInterface | Should Be "1B"
        $rows[0].ObservedNetMode | Should Be "FAILOVER"
    }

    It "returns blank device metadata when serial is empty" {
        $meta = Get-SelDeviceMetadata -Serial ""
        $meta.Name | Should Be ""
        $meta.Description | Should Be ""
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

Describe "Plink path resolution" {
    It "prefers override path when provided" {
        $override = Join-Path $TestDrive "plink-override.exe"
        Set-Content -Path $override -Value "placeholder"

        $resolved = Get-SelPlinkPath -OverridePath $override -RepoDefaultPath (Join-Path $TestDrive "missing-default.exe")
        $resolved | Should Be (Resolve-Path $override).Path
    }

    It "falls back to repo default path when override is blank" {
        $repoDefault = Join-Path $TestDrive "plink-default.exe"
        Set-Content -Path $repoDefault -Value "placeholder"

        $resolved = Get-SelPlinkPath -OverridePath "" -RepoDefaultPath $repoDefault
        $resolved | Should Be (Resolve-Path $repoDefault).Path
    }
}

Describe "ReIP precedence" {
    It "prefers CLI values over desiredstate.csv" {
        $tmp = Join-Path $TestDrive "desiredstate.csv"
        @'
Serial,Active,Name,Description,Mac,DesiredIP,DesiredSubnetMask,DesiredGateway,DesiredPrimaryInterface,DesiredFirmwareLabel,DesiredConfigSha256,ObservedIP,ObservedPrimaryInterface,ObservedActiveInterface,ObservedNetMode,ObservedFirmwareLabel,ObservedFid,LastSeen,LastAction,LastResult,Notes
3241995707,TRUE,Feeder 751,Primary feeder relay,00-30-A7-3D-6F-A9,192.168.1.101,255.255.255.0,192.168.1.1,1B,SEL-751-R401,,,,,,,,,,,
'@ | Set-Content $tmp

        $result = Resolve-SelReIpTarget -Serial "3241995707" -Ip "10.1.2.3" -Mask "255.255.255.0" -Gateway "10.1.2.1" -PrimaryInterface "1A" -DesiredStatePath $tmp
        $result.Ip | Should Be "10.1.2.3"
        $result.Mask | Should Be "255.255.255.0"
        $result.Gateway | Should Be "10.1.2.1"
        $result.PrimaryInterface | Should Be ""
        $result.NetPort | Should Be ""
    }

    It "falls back to desiredstate.csv when CLI values are missing" {
        $tmp = Join-Path $TestDrive "desiredstate.csv"
        @'
Serial,Active,Name,Description,Mac,DesiredIP,DesiredSubnetMask,DesiredGateway,DesiredPrimaryInterface,DesiredFirmwareLabel,DesiredConfigSha256,ObservedIP,ObservedPrimaryInterface,ObservedActiveInterface,ObservedNetMode,ObservedFirmwareLabel,ObservedFid,LastSeen,LastAction,LastResult,Notes
3241995707,TRUE,Feeder 751,Primary feeder relay,00-30-A7-3D-6F-A9,192.168.1.101,255.255.255.0,192.168.1.1,1B,SEL-751-R401,,,,,,,,,,,
'@ | Set-Content $tmp

        $result = Resolve-SelReIpTarget -Serial "3241995707" -DesiredStatePath $tmp
        $result.Ip | Should Be "192.168.1.101"
        $result.Mask | Should Be "255.255.255.0"
        $result.Gateway | Should Be "192.168.1.1"
        $result.PrimaryInterface | Should Be ""
        $result.NetPort | Should Be ""
        $result.Source | Should Be "desiredstate"
    }

    It "allows mask and gateway to remain blank when only IP is supplied" {
        $result = Resolve-SelReIpTarget -Ip "10.1.2.3"
        $result.Ip | Should Be "10.1.2.3"
        $result.Mask | Should Be ""
        $result.Gateway | Should Be ""
    }
}

Describe "ReIP prompting and host resolution" {
    It "uses the provided default IP when the prompt input is blank" {
        Mock Read-Host { "" }

        $result = Read-SelPromptWithDefault -Prompt "Target IP" -DefaultValue "192.168.1.2"
        $result | Should Be "192.168.1.2"
    }

    It "prefers profile default IP for current host resolution when HostIp is blank" {
        $result = Resolve-SelReIpHostIp -Serial "3241995707" -HostIp "" -ProfileDefaultIp "192.168.1.2"
        $result.HostIp | Should Be "192.168.1.2"
        $result.Source | Should Be "profile-default"
    }
}

Describe "ReIP persistence control" {
    It "skips device event and desired state updates when SkipInventoryUpdate is set" {
        Mock Get-SelDefaults -ModuleName SelTools {
            [pscustomobject]@{
                DefaultIP = "192.168.1.2"
                ACCPassword = "OTTER"
                '2ACPassword' = "TAIL"
            }
        }
        Mock Resolve-SelReIpHostIp -ModuleName SelTools { [pscustomobject]@{ HostIp = "192.168.1.2"; Source = "cli" } }
        Mock Resolve-SelReIpTarget -ModuleName SelTools {
            [pscustomobject]@{
                Serial = "3250985195"
                Ip = "192.168.1.3"
                Mask = ""
                Gateway = ""
                PrimaryInterface = ""
                NetPort = ""
                Source = "cli"
            }
        }
        Mock Invoke-SelPingCheck -ModuleName SelTools { [pscustomobject]@{ HostIp = "192.168.1.2"; Success = $true } }
        Mock Invoke-SelPlinkReIpCapture -ModuleName SelTools {
            [pscustomobject]@{
                ID = "pre-id"
                SER = "pre-ser"
                ETH = "pre-eth"
                Access = [pscustomobject]@{ AccessLevel = "2AC" }
                Session = [pscustomobject]@{ Process = [pscustomobject]@{ HasExited = $false } }
            }
        }
        Mock ConvertFrom-SelIdOutput -ModuleName SelTools { [pscustomobject]@{} }
        Mock ConvertFrom-SelStaOutput -ModuleName SelTools {
            param([string]$Text)
            if ($Text -eq "pre-ser") {
                return [pscustomobject]@{ Serial = "3250985195"; FID = "FID-PRE" }
            }
            return [pscustomobject]@{ Serial = "3250985195"; FID = "FID-POST" }
        }
        Mock ConvertFrom-SelEthOutput -ModuleName SelTools {
            param([string]$Text)
            if ($Text -eq "pre-eth") {
                return [pscustomobject]@{ IP = "192.168.1.2"; Mask = "255.255.255.0"; Gateway = "192.168.1.1"; MAC = "00-30-A7-42-2F-B2" }
            }
            return [pscustomobject]@{ IP = "192.168.1.3"; Mask = "255.255.255.0"; Gateway = "192.168.1.1"; MAC = "00-30-A7-42-2F-B2" }
        }
        Mock Get-SelEthernetModelFromEthParsed -ModuleName SelTools { [pscustomobject]@{ primaryInterface = "1A"; activeInterface = "1A"; netMode = "FAILOVER" } }
        Mock Get-SelSerialFromIdParsed -ModuleName SelTools { "3250985195" }
        Mock Confirm-SelReIpPlan -ModuleName SelTools { $true }
        Mock Invoke-SelReIpSetPort1 -ModuleName SelTools { [pscustomobject]@{ Success = $true; SaveSent = $true; SettingsSaved = $true; Steps = @() } }
        Mock Stop-SelPlinkSession -ModuleName SelTools { }
        Mock Invoke-SelFastReconnectCapture -ModuleName SelTools {
            [pscustomobject]@{
                Success = $true
                AttemptCount = 1
                Capture = [pscustomobject]@{
                    ID = "post-id"
                    SER = "post-ser"
                    ETH = "post-eth"
                }
                ErrorMessage = ""
            }
        }
        Mock Resolve-SelMetadata -ModuleName SelTools { [pscustomobject]@{ Name = "Feeder 751"; Description = "Primary feeder relay" } }
        Mock Get-SelDesiredStateMetadata -ModuleName SelTools { [pscustomobject]@{} }
        Mock Get-SelDeviceMetadata -ModuleName SelTools { [pscustomobject]@{} }
        Mock Add-SelDeviceEvent -ModuleName SelTools { }
        Mock Update-SelDesiredStateObserved -ModuleName SelTools { }

        $result = Invoke-SelReIp -Serial "3250985195" -HostIp "192.168.1.2" -Ip "192.168.1.3" -Profile "factory" -SkipInventoryUpdate -PassThru

        $result.Status | Should Be "success"
        $result.SkipInventoryUpdate | Should Be $true
        Assert-MockCalled ConvertFrom-SelStaOutput -ModuleName SelTools -Times 2
        Assert-MockCalled Add-SelDeviceEvent -ModuleName SelTools -Times 0
        Assert-MockCalled Update-SelDesiredStateObserved -ModuleName SelTools -Times 0
    }

    It "does not throw when no serial is available after reconnect" {
        Mock Get-SelDefaults -ModuleName SelTools {
            [pscustomobject]@{
                DefaultIP = ""
                ACCPassword = "OTTER"
                '2ACPassword' = "TAIL"
            }
        }
        Mock Resolve-SelReIpHostIp -ModuleName SelTools { [pscustomobject]@{ HostIp = "192.168.1.2"; Source = "cli" } }
        Mock Resolve-SelReIpTarget -ModuleName SelTools {
            [pscustomobject]@{
                Serial = ""
                Ip = "192.168.1.3"
                Mask = ""
                Gateway = ""
                PrimaryInterface = ""
                NetPort = ""
                Source = "cli"
            }
        }
        Mock Invoke-SelPingCheck -ModuleName SelTools { [pscustomobject]@{ HostIp = "192.168.1.2"; Success = $true } }
        Mock Invoke-SelPlinkReIpCapture -ModuleName SelTools {
            [pscustomobject]@{
                ID = "pre-id"
                SER = ""
                ETH = "pre-eth"
                Access = [pscustomobject]@{ AccessLevel = "2AC" }
                Session = [pscustomobject]@{ Process = [pscustomobject]@{ HasExited = $false } }
            }
        }
        Mock ConvertFrom-SelIdOutput -ModuleName SelTools { [pscustomobject]@{} }
        Mock ConvertFrom-SelStaOutput -ModuleName SelTools { [pscustomobject]@{ Serial = ""; FID = "" } }
        Mock ConvertFrom-SelEthOutput -ModuleName SelTools {
            param([string]$Text)
            [pscustomobject]@{ IP = "192.168.1.3"; Mask = "255.255.255.0"; Gateway = "192.168.1.1"; MAC = "00-30-A7-42-2F-B2" }
        }
        Mock Get-SelEthernetModelFromEthParsed -ModuleName SelTools { [pscustomobject]@{ primaryInterface = "1A"; activeInterface = "1A"; netMode = "FAILOVER" } }
        Mock Get-SelSerialFromIdParsed -ModuleName SelTools { "" }
        Mock Confirm-SelReIpPlan -ModuleName SelTools { $true }
        Mock Invoke-SelReIpSetPort1 -ModuleName SelTools { [pscustomobject]@{ Success = $true; SaveSent = $true; SettingsSaved = $true; Steps = @() } }
        Mock Stop-SelPlinkSession -ModuleName SelTools { }
        Mock Invoke-SelFastReconnectCapture -ModuleName SelTools {
            [pscustomobject]@{
                Success = $true
                AttemptCount = 1
                Capture = [pscustomobject]@{
                    ID = "post-id"
                    SER = ""
                    ETH = "post-eth"
                }
                ErrorMessage = ""
            }
        }
        Mock Resolve-SelMetadata -ModuleName SelTools { [pscustomobject]@{ Name = ""; Description = "" } }
        Mock Get-SelDesiredStateMetadata -ModuleName SelTools { [pscustomobject]@{ Name = ""; Description = "" } }
        Mock Get-SelDeviceMetadata -ModuleName SelTools { [pscustomobject]@{ Name = ""; Description = "" } }
        Mock Add-SelDeviceEvent -ModuleName SelTools { }
        Mock Update-SelDesiredStateObserved -ModuleName SelTools { }

        $result = Invoke-SelReIp -HostIp "192.168.1.2" -Ip "192.168.1.3" -Profile "factory" -PassThru

        $result.Status | Should Be "failed"
        $result.Serial | Should Be ""
        Assert-MockCalled Add-SelDeviceEvent -ModuleName SelTools -Times 0
        Assert-MockCalled Update-SelDesiredStateObserved -ModuleName SelTools -Times 0
    }
}

Describe "ReIP capture command selection" {
    It "uses STA and not SER when IncludeSer is set for reip capture" {
        $global:sentLines = @()
        Mock Start-SelPlinkSession -ModuleName SelTools {
            [pscustomobject]@{
                Process = [pscustomobject]@{ HasExited = $false }
            }
        }
        Mock Read-SelSessionAvailable -ModuleName SelTools { "TERMINAL SERVER" }
        Mock Read-SelSessionUntil -ModuleName SelTools { "=" }
        Mock Send-SelSessionLine -ModuleName SelTools {
            param(
                [pscustomobject]$Session,
                [string]$Text
            )
            $global:sentLines += $Text
        }
        Mock Enter-SelReIpAccess -ModuleName SelTools { [pscustomobject]@{ Success = $true; AccessLevel = "2AC" } }
        Mock Stop-SelPlinkSession -ModuleName SelTools { }

        $capture = Invoke-SelPlinkReIpCapture -HostIp "192.168.1.2" -AccPassword "OTTER" -TwoAcPassword "TAIL" -Target ([pscustomobject]@{ Ip = "192.168.1.3" }) -IncludeSer

        ($global:sentLines -contains "STA") | Should Be $true
        ($global:sentLines -contains "SER") | Should Be $false
        ($global:sentLines -contains "ETH") | Should Be $true
    }

    It "fast reconnect passes IncludeSer through to identity capture" {
        Mock Invoke-SelPlinkIdentityCapture -ModuleName SelTools {
            [pscustomobject]@{
                ID = "post-id"
                SER = ""
                ETH = "post-eth"
                Access = [pscustomobject]@{ Success = $true }
            }
        }

        $result = Invoke-SelFastReconnectCapture -HostIp "192.168.1.3" -AccPassword "OTTER" -TwoAcPassword "TAIL" -Attempts 1 -IncludeSer:$false

        $result.Success | Should Be $true
        Assert-MockCalled Invoke-SelPlinkIdentityCapture -ModuleName SelTools -Times 1 -Exactly -ParameterFilter {
            $HostIp -eq "192.168.1.3" -and -not $IncludeSer
        }
    }

    It "uses STA and not SER when IncludeSer is set for identity capture" {
        $global:sentLines = @()
        Mock Start-SelPlinkSession -ModuleName SelTools {
            [pscustomobject]@{
                Process = [pscustomobject]@{ HasExited = $false }
            }
        }
        Mock Read-SelSessionAvailable -ModuleName SelTools { "TERMINAL SERVER" }
        Mock Read-SelSessionUntil -ModuleName SelTools { "=" }
        Mock Send-SelSessionLine -ModuleName SelTools {
            param(
                [pscustomobject]$Session,
                [string]$Text
            )
            $global:sentLines += $Text
        }
        Mock Enter-SelReIpAccess -ModuleName SelTools { [pscustomobject]@{ Success = $true; AccessLevel = "2AC" } }
        Mock Stop-SelPlinkSession -ModuleName SelTools { }

        $capture = Invoke-SelPlinkIdentityCapture -HostIp "192.168.1.2" -AccPassword "OTTER" -TwoAcPassword "TAIL" -IncludeSer

        ($global:sentLines -contains "STA") | Should Be $true
        ($global:sentLines -contains "SER") | Should Be $false
        ($global:sentLines -contains "ETH") | Should Be $true
        $capture.SER | Should Be "="
    }
}

Describe "Ethernet interface mapping" {
    It "maps selector A/B to interface names 1A/1B" {
        (ConvertTo-SelPrimaryInterface -Selector "A") | Should Be "1A"
        (ConvertTo-SelPrimaryInterface -Selector "b") | Should Be "1B"
    }

    It "maps interface names 1A/1B to NETPORT selector A/B" {
        (ConvertTo-SelNetPortSelector -Interface "1A") | Should Be "A"
        (ConvertTo-SelNetPortSelector -Interface "1b") | Should Be "B"
    }
}

Describe "Inventory parsers" {
    It "parses ID key/value fields" {
        $idText = @'
"FID=SEL-751-R401-V0-Z101100-D20240308","08A3"
"CID=1D4A","0267"
"DEVID=SEL-751","03C7"
'@
        $parsed = ConvertFrom-SelIdOutput -Text $idText
        $parsed.FID | Should Be "SEL-751-R401-V0-Z101100-D20240308"
        $parsed.CID | Should Be "1D4A"
        $parsed.DEVID | Should Be "SEL-751"
    }

    It "parses STA summary fields" {
        $staText = @'
Serial Num = 3241995707     FID = SEL-751-R401-V0-Z101100-D20240308
CID = 1D4A                  PART NUM = 751001A1A4A0X851G10
'@
        $parsed = ConvertFrom-SelStaOutput -Text $staText
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
NETMODE: FAILOVER
PRIMARY PORT: 1A
ACTIVE PORT: 1B
PORT 1A Up 100 Full Copper
PORT 1B Down
'@
        $parsed = ConvertFrom-SelEthOutput -Text $ethText
        $parsed.MAC | Should Be "00-30-A7-3D-6F-A9"
        $parsed.IP | Should Be "192.168.1.2"
        $parsed.Mask | Should Be "255.255.255.0"
        $parsed.Gateway | Should Be "192.168.1.1"
        $parsed.NetMode | Should Be "FAILOVER"
        $parsed.PrimaryInterface | Should Be "1A"
        $parsed.ActiveInterface | Should Be "1B"
        $parsed.ConfiguredPrimarySelector | Should Be "A"
        $parsed.Port1A.LinkStatus | Should Be "UP"
        $parsed.Port1B.LinkStatus | Should Be "DOWN"
    }
}

Describe "Inventory serial extraction" {
    It "extracts serial from ID parsed fields when present" {
        $idParsed = [pscustomobject]@{
            SERIALNUM = "3241995707"
        }

        $serial = Get-SelSerialFromIdParsed -IdParsed $idParsed
        $serial | Should Be "3241995707"
    }
}

Describe "Inventory host resolution" {
    It "uses host ip from device history json when no host is provided" {
        $devicesDir = Join-Path $TestDrive "devices"
        New-Item -ItemType Directory -Path $devicesDir -Force | Out-Null
        @'
{
  "serial": "3241995707",
  "events": [
    {
      "timestamp": "2026-03-08T08:30:00",
      "action": "inventory",
      "hostIp": "192.168.1.2"
    }
  ]
}
'@ | Set-Content (Join-Path $devicesDir "3241995707.json")

        $resolved = Resolve-SelInventoryHostIp -Serial "3241995707" -DevicesDirectory $devicesDir -DesiredStatePath (Join-Path $TestDrive "missing.csv")
        $resolved.HostIp | Should Be "192.168.1.2"
        $resolved.Source | Should Be "json"
    }

    It "prompts on json/desiredstate conflict and uses selected option" {
        $devicesDir = Join-Path $TestDrive "devices"
        New-Item -ItemType Directory -Path $devicesDir -Force | Out-Null
        @'
{
  "serial": "3241995707",
  "events": [
    {
      "timestamp": "2026-03-08T08:30:00",
      "action": "inventory",
      "hostIp": "192.168.1.2"
    }
  ]
}
'@ | Set-Content (Join-Path $devicesDir "3241995707.json")

        $desired = Join-Path $TestDrive "desiredstate.csv"
        @'
Serial,Active,Name,Description,Mac,DesiredIP,DesiredSubnetMask,DesiredGateway,DesiredFirmwareLabel,DesiredConfigSha256,ObservedIP,ObservedFirmwareLabel,ObservedFid,LastSeen,LastAction,LastResult,Notes
3241995707,TRUE,Feeder 751,Primary feeder relay,00-30-A7-3D-6F-A9,192.168.1.101,255.255.255.0,192.168.1.1,SEL-751-R401,,192.168.1.10,SEL-751-R401,SEL-751-R401-V0,2026-03-08T08:40:00,inventory,success,Example relay
'@ | Set-Content $desired

        $script:choiceQueue = @("2")
        $readInput = {
            param([string]$Prompt)
            $next = $script:choiceQueue[0]
            if ($script:choiceQueue.Count -gt 1) {
                $script:choiceQueue = @($script:choiceQueue[1..($script:choiceQueue.Count - 1)])
            }
            else {
                $script:choiceQueue = @()
            }
            return $next
        }

        $resolved = Resolve-SelInventoryHostIp -Serial "3241995707" -DevicesDirectory $devicesDir -DesiredStatePath $desired -ReadInput $readInput
        $resolved.HostIp | Should Be "192.168.1.10"
        $resolved.Source | Should Be "desiredstate"
    }
}

Describe "SER event storage" {
    It "parses SER lines and filters transport noise" {
        $serText = @'
TERMINAL SERVER
=SER
SEL-751                                  Date: 03/08/2026   Time: 09:22:33.965
FEEDER RELAY                             Time Source: Internal
03/08/2026 09:22:40.000 BREAKER OPEN ASSERTED
03/08/2026 09:22:41.000 BREAKER OPEN DEASSERTED
=>
'@
        $records = @(ConvertFrom-SelSerEventRecords -Text $serText -Serial "3241995707" -RunId "20260308-120000" -RawArchivePath "data/events/3241995707/2026-03-08T12-00-00-ser.txt")
        $records.Count | Should Be 2
        $records[0].event | Should Be "BREAKER OPEN ASSERTED"
        $records[1].state | Should Be "DEASSERTED"
    }

    It "writes only new events on repeated SER pulls" {
        $eventsRoot = Join-Path $TestDrive "events"
        New-Item -ItemType Directory -Path $eventsRoot -Force | Out-Null
        $raw = @'
03/08/2026 09:22:40.000 BREAKER OPEN ASSERTED
03/08/2026 09:22:41.000 BREAKER OPEN DEASSERTED
'@

        $first = Write-SelSerEventStore -Serial "3241995707" -RawSerText $raw -RunId "20260308-120000" -EventsRoot $eventsRoot
        $second = Write-SelSerEventStore -Serial "3241995707" -RawSerText $raw -RunId "20260308-120500" -EventsRoot $eventsRoot

        $first.EntriesAdded | Should Be 2
        $second.EntriesAdded | Should Be 0

        $serPath = Join-Path $eventsRoot "3241995707\ser.jsonl"
        $lines = @(Get-Content -Path $serPath)
        $lines.Count | Should Be 2
    }
}
