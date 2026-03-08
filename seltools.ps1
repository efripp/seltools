param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet("inventory", "reip", "fwupgrade")]
    [string]$Command,

    [string]$Serial,
    [string]$HostIp,
    [string]$Ip,
    [string]$Mask,
    [string]$Gateway,
    [string]$Profile = "factory"
)

$modulePath = Join-Path $PSScriptRoot "src\SelTools\SelTools.psm1"
Import-Module $modulePath -Force

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

function Show-SelMenu {
    Write-Host ""
    Write-Host "SelTools Main Menu"
    Write-Host "  1) inventory"
    Write-Host "  2) reip"
    Write-Host "  3) fwupgrade"
    Write-Host "  4) help"
    Write-Host "  5) exit"
}

function Show-SelHelp {
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\seltools.ps1 inventory -Serial 3241995707 -HostIp 192.168.1.2"
    Write-Host "  .\seltools.ps1 reip -Serial 3241995707 -Ip 192.168.1.101 -Mask 255.255.255.0 -Gateway 192.168.1.1"
    Write-Host "  .\seltools.ps1 fwupgrade -Serial 3241995707 -HostIp 192.168.1.2"
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
        [string]$Profile = "factory"
    )

    switch ($CommandName.ToLowerInvariant()) {
        "inventory" {
            Invoke-SelInventory -Serial $Serial -HostIp $HostIp -Profile $Profile
        }
        "reip" {
            Invoke-SelReIp -Serial $Serial -HostIp $HostIp -Ip $Ip -Mask $Mask -Gateway $Gateway -Profile $Profile
        }
        "fwupgrade" {
            Invoke-SelFwUpgrade -Serial $Serial -HostIp $HostIp -Profile $Profile
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
        [string]$Profile = "factory",
        [scriptblock]$ReadInput = { param([string]$Prompt) Read-Host $Prompt }
    )

    while ($true) {
        Show-SelMenu
        $choice = (& $ReadInput "Select an option (1-5)")

        switch ($choice) {
            "1" {
                $Serial = Get-SelPromptValue -Label "Serial" -CurrentValue $Serial -ReadInput $ReadInput
                $HostIp = Get-SelPromptValue -Label "Host IP" -CurrentValue $HostIp -ReadInput $ReadInput
                $Profile = Get-SelPromptValue -Label "Profile" -CurrentValue $Profile -ReadInput $ReadInput
                try {
                    Invoke-SelDispatch -CommandName "inventory" -Serial $Serial -HostIp $HostIp -Profile $Profile
                }
                catch {
                    Write-Error $_
                }
            }
            "2" {
                $Serial = Get-SelPromptValue -Label "Serial" -CurrentValue $Serial -ReadInput $ReadInput
                $HostIp = Get-SelPromptValue -Label "Host IP" -CurrentValue $HostIp -ReadInput $ReadInput
                $Ip = Get-SelPromptValue -Label "Target IP" -CurrentValue $Ip -ReadInput $ReadInput
                $Mask = Get-SelPromptValue -Label "Target subnet mask" -CurrentValue $Mask -ReadInput $ReadInput
                $Gateway = Get-SelPromptValue -Label "Target gateway" -CurrentValue $Gateway -ReadInput $ReadInput
                $Profile = Get-SelPromptValue -Label "Profile" -CurrentValue $Profile -ReadInput $ReadInput
                try {
                    Invoke-SelDispatch -CommandName "reip" -Serial $Serial -HostIp $HostIp -Ip $Ip -Mask $Mask -Gateway $Gateway -Profile $Profile
                }
                catch {
                    Write-Error $_
                }
            }
            "3" {
                $Serial = Get-SelPromptValue -Label "Serial" -CurrentValue $Serial -ReadInput $ReadInput
                $HostIp = Get-SelPromptValue -Label "Host IP" -CurrentValue $HostIp -ReadInput $ReadInput
                $Profile = Get-SelPromptValue -Label "Profile" -CurrentValue $Profile -ReadInput $ReadInput
                try {
                    Invoke-SelDispatch -CommandName "fwupgrade" -Serial $Serial -HostIp $HostIp -Profile $Profile
                }
                catch {
                    Write-Error $_
                }
            }
            "4" {
                Show-SelHelp
            }
            "5" {
                break
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

if ($Command) {
    Invoke-SelDispatch -CommandName $Command -Serial $Serial -HostIp $HostIp -Ip $Ip -Mask $Mask -Gateway $Gateway -Profile $Profile
}
else {
    Start-SelInteractiveMenu -Serial $Serial -HostIp $HostIp -Ip $Ip -Mask $Mask -Gateway $Gateway -Profile $Profile
}
