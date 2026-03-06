param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet("inventory", "reip", "fwupgrade")]
    [string]$Command,

    [string]$Serial,
    [string]$HostIp,
    [string]$Ip,
    [string]$Mask,
    [string]$Gateway
)

$modulePath = Join-Path $PSScriptRoot "src\SelTools\SelTools.psm1"
Import-Module $modulePath -Force

if (-not $Command) {
    $Command = Read-Host "Command (inventory|reip|fwupgrade)"
}

switch ($Command.ToLowerInvariant()) {
    "inventory" {
        Invoke-SelInventory -Serial $Serial -HostIp $HostIp
    }
    "reip" {
        Invoke-SelReIp -Serial $Serial -HostIp $HostIp -Ip $Ip -Mask $Mask -Gateway $Gateway
    }
    "fwupgrade" {
        Invoke-SelFwUpgrade -Serial $Serial -HostIp $HostIp
    }
    default {
        throw "Unsupported command: $Command"
    }
}
