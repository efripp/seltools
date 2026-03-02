# SEL Relay Fleet Management Module Specification

Generated: 2026-03-01T15:22:00.640334

------------------------------------------------------------------------
^^add descriptions by most of these entries.
# Files

## 1) defaultsettings.csv

Single-row run profile (not device specific).

Recommended columns:

-   DefaultIP
-   DefaultSubnetMask
-   TargetIP
-   TargetSubnetMask
-   TargetGateway
-   PoolStartIP
-   PoolEndIP
-   ACCPassword ^^The permissions escalation has to be done one at the time.
-   2ACPassword
-   CALPassword
-   FtpUser 
-   FtpPassword
-   TargetFirmwareFile
-   TargetFirmwareLabel
-   OutputFirmwareFile ^^File must be relabeled before upload. Check the docs.
-   IdentifyEnabledDefault
-   RequireOUICheckDefault
-   AllowedOUIs (semicolon-separated) ^^Why semicolon-separated in csv?

------------------------------------------------------------------------

## 2) desiredstate.csv

Primary key: Serial

### Identity

-   Serial
-   Mac

### Desired

-   DesiredIP
-   DesiredSubnetMask
-   DesiredGateway
-   DesiredFirmwareLabel
-   DesiredConfigSha256
-   Notes

### Observed (Last Known)

-   ObservedIP
-   ObservedFirmwareLabel
-   ObservedFid
-   LastSeen
-   LastAction
-   LastResult

------------------------------------------------------------------------

## 3) Per-Device History JSON

One file per serial: serial#.json

Structure: - events\[\] - timestamp - action type - parsed values
(ID/ETH/STA fields) - raw transcript (optional)

------------------------------------------------------------------------

## 4) Run Reports

-   run-YYYYMMDD-HHMM-summary.csv
-   run-YYYYMMDD-HHMM.jsonl

------------------------------------------------------------------------

# Core Functions

## Networking / Safety

-   Test-HostHasIpInSubnet()
-   Get-ArpMacForIp()
-   Get-ArpMacCandidates()
-   Set-StaticArp()
-   Remove-Arp()
-   Test-Ping()

## Telnet (SEL ASCII)

-   Connect-Telnet()
-   Telnet-EnsureAccessC()
-   Sel-GetID()
-   Sel-GetETH()
-   Sel-GetSTA() ^^I think this is redundant.
-   ^^There should be a get calibration here too.
-   Sel-SetPort1Ip()

## FTP

-   Ftp-PutFirmware()
-   Ftp-GetSettings()
-   Ftp-GetEvents()

## Persistence

-   Load-DefaultSettings()
-   Load-DesiredState()
-   Upsert-DesiredStateRow()
-   Append-DeviceJsonEvent()
-   Write-RunSummaryRow()
-   Write-RunLogJsonl()

------------------------------------------------------------------------

# Modes

## Mode 1 -- Scan Subnet (Inventory Only)

-   Ping sweep pool
-   Telnet ID/STA/ETH
-   Update observed fields
-   Append JSON snapshot
-   Generate run summary

## Mode 2 -- Re-IP List Mode

-   Lock ARP
-   Identify Serial/MAC
-   Match to desiredstate.csv
-   Apply DesiredIP if matched
-   Verify new IP
-   Log results

## Mode 3 -- Bulk Re-IP Pool Mode

-   Confirm isolated network
-   Verify host has IP on default + target subnet
-   Enumerate MACs claiming default IP
-   Lock ARP → Identify → Assign next IP
-   Remove ARP
-   Verify new IP via Telnet
-   Update CSV + JSON
-   Stop when no new MACs found or pool exhausted

## Mode 4 -- Update Firmware (Single) ^^Will use default IP from DefaultSettings.csv. Prompt to to confirm.

-   Pre-snapshot (ID/STA/ETH)
-   Compare firmware
-   FTP PUT firmware
-   Reboot if required
-   Post-snapshot
-   Log result

## Mode 5 -- Update Firmware from List ^^Requires serial # and what else?

-   Iterate desiredstate.csv
-   Upgrade only if mismatch
-   Pre + Post snapshot
-   Generate run summary

------------------------------------------------------------------------

# Collision-Aware Enumeration Algorithm

1.  Discover MACs claiming DefaultIP via ARP over time.
2.  For each MAC:
    -   arp -d DefaultIP
    -   arp -s DefaultIP MAC
    -   Telnet → Verify Serial + MAC
    -   Assign IP from pool
    -   arp -d DefaultIP
    -   Verify device reachable at new IP
    -   Update CSV + JSON
3.  Repeat until no new MACs appear.

------------------------------------------------------------------------

# Safety Rules

-   Always verify Serial + MAC before re-IP. ^^These devices have 2 network ports. That might trip us up here. Consider serial only. 
-   Always verify identity after re-IP (not just ping).
-   Require explicit confirmation for bulk mode.
-   Ensure host has IP on both default and target subnet if different.
-   JSON = immutable history.
-   desiredstate.csv = authoritative desired state + last observed
    snapshot.
