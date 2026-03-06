# SEL Relay Inventory Context Addendum

Generated: 2026-03-05T00:42:26.960312

------------------------------------------------------------------------

# Inventory Snapshot Procedure

To collect device inventory information, the tool executes the following
commands:

1.  `ID`
2.  escalate to **ACC**
3.  `STA`
4.  `ETH`

Example sequence:

    ID
    ACC
    STA
    ETH

Behavior rules:

-   `ID` must always run first.
-   `ACC` escalation is attempted once.
-   If ACC fails:
    -   `STA` and `ETH` are skipped
    -   inventory still records the `ID` results.

------------------------------------------------------------------------

# Access Requirements

  Command   Access Required
  --------- -----------------
  ID        none
  STA       ACC
  ETH       ACC

------------------------------------------------------------------------

# Fields from ID Command

SEL `ID` output format:

    "KEY=VALUE","HEX"

The HEX value is an internal SEL identifier and should be stored but not
used for logic.

  Field           Meaning                              Use
  --------------- ------------------------------------ ---------------------------------
  FID             Firmware ID                          Used to verify firmware version
  BFID            Boot firmware identifier             Logged for completeness
  CID             Configuration ID                     Logged for change comparisons
  DEVID           Device model identifier              Inventory
  DEVCODE         Numeric device code                  Inventory
  PARTNO          Hardware part number                 Inventory
  CONFIG          Configuration/options bitmap         Logged
  SPECIAL         Special build features               Logged
  iedName         IEC 61850 IED name                   Logged
  type            IEC 61850 type metadata              Logged
  configVersion   User/project configuration version   Logged
  LIB61850ID      IEC 61850 library identifier         Logged

------------------------------------------------------------------------

# Fields from STA Command

Example output:

    Serial Num = 3241995707
    FID = SEL-751-R401-V0-Z101100-D20240308
    CID = 1D4A
    PART NUM = 751001A1A4A0X851G10

  Field        Meaning                  Use
  ------------ ------------------------ -------------------------------
  Serial Num   Hardware serial number   **Primary device identifier**
  FID          Firmware ID              Firmware verification
  CID          Configuration ID         Change tracking
  PART NUM     Hardware part number     Inventory

Rule:

> Serial Num is the authoritative identity of the relay.

------------------------------------------------------------------------

# Fields from ETH Command

Example output:

    MAC: 00-30-A7-3D-6F-A9
    IP ADDRESS: 192.168.1.2
    SUBNET MASK: 255.255.255.0
    DEFAULT GATEWAY: 192.168.1.1

  Field             Meaning                Use
  ----------------- ---------------------- -------------------------
  MAC               Ethernet MAC address   Inventory reference
  IP ADDRESS        Current relay IP       Connection verification
  SUBNET MASK       Network mask           Logged
  DEFAULT GATEWAY   Gateway                Logged

Additional informational fields may include:

-   NETMODE
-   PRIMARY PORT
-   ACTIVE PORT
-   PORT LINK STATUS

These may be logged but do not need parsing initially.

------------------------------------------------------------------------

# Prompt Behavior

The relay prompts indicate access level:

  Prompt   Meaning
  -------- ----------------------
  `=`      Base access
  `=>`     ACC / Level 1 access

------------------------------------------------------------------------

# Recommended JSON Structure for Inventory Snapshot

Example structure:

``` json
{
  "serial": "3241995707",
  "timestamp": "2026-03-04T17:38:39",
  "inventory": {
    "ID": {
      "FID": "SEL-751-R401-V0-Z101100-D20240308",
      "BFID": "SLBTIND-R101-V0-Z000000-D20230609",
      "CID": "1D4A",
      "DEVID": "SEL-751",
      "DEVCODE": "77",
      "PARTNO": "751001A1A4A0X851G10",
      "CONFIG": "111112010"
    },
    "STA": {
      "serial": "3241995707",
      "FID": "SEL-751-R401-V0-Z101100-D20240308",
      "CID": "1D4A",
      "PARTNUM": "751001A1A4A0X851G10"
    },
    "ETH": {
      "mac": "00-30-A7-3D-6F-A9",
      "ip": "192.168.1.2",
      "mask": "255.255.255.0",
      "gateway": "192.168.1.1"
    }
  }
}
```

------------------------------------------------------------------------

# Parsing Rules

Recommended regex patterns:

    Serial Num\s*=\s*(\d+)
    MAC:\s*([0-9A-F-]+)
    IP ADDRESS:\s*(\d+\.\d+\.\d+\.\d+)
    SUBNET MASK:\s*(\d+\.\d+\.\d+\.\d+)
    DEFAULT GATEWAY:\s*(\d+\.\d+\.\d+\.\d+)

------------------------------------------------------------------------

# Log Cleanup

PuTTY logs contain control characters such as:

    \x02
    \x03

These should be stripped before parsing:

``` powershell
$clean = $text -replace "[\x00-\x1F]", ""
```

------------------------------------------------------------------------

# Networking Notes

The relay may have dual Ethernet ports.

Example:

    NETMODE: FAILOVER
    PRIMARY PORT: 1A
    ACTIVE PORT: 1A
    PORT 1B Down

Because multiple MAC addresses may exist:

> Serial number must be used as the primary device key rather than MAC
> address.

---

# Starter CSV Examples

The project uses two CSV files for local configuration and desired state. Below are sample starter files.

## defaults.csv (profile-based runtime defaults)

- This file contains one row per profile.
- Include a `Profile` column and select rows by profile name (default: `factory`).
- Stores default network assumptions, credentials, and firmware targets.

Example:

```csv
Profile,DefaultIP,DefaultSubnetMask,TargetSubnetMask,TargetGateway,PoolStartIP,PoolEndIP,ACCPassword,2ACPassword,CALPassword,FtpUser,FtpPassword,TargetFirmwareLabel,TargetFirmwareFile,IdentifyEnabledDefault,RequireOUICheckDefault,AllowedOUIs
factory,192.168.1.2,255.255.255.0,255.255.255.0,192.168.1.1,192.168.1.100,192.168.1.199,OTTER,TAIL,CLARKE,ftp,ftp,SEL-751-R401,RELAY.ZDS,true,false,00-30-A7
site-a,10.10.0.10,255.255.255.0,255.255.255.0,10.10.0.1,10.10.0.100,10.10.0.199,,,,ftp,,SEL-751-R401,RELAY.ZDS,true,false,00-30-A7
```

Column notes:

- **Profile**: named defaults profile (for example `factory`, `site-a`)
- **DefaultIP**: expected factory/default IP before commissioning (often 192.168.1.2)
- **PoolStartIP/PoolEndIP**: allocation pool for bulk re-IP modes
- **ACCPassword / 2ACPassword / CALPassword**: access escalation passwords (CAL may be blank if not used)
- **TargetFirmwareLabel**: short label used for comparisons (e.g., SEL-751-R401)
- **TargetFirmwareFile**: expected filename used when uploading firmware (often requires a specific name on the relay)
- **AllowedOUIs**: semicolon-delimited list is also acceptable if multiple OUIs are used

## desiredstate.csv (per-device desired + last observed)

- Primary key is **Serial**.
- Used to track desired state (IP, firmware, config checksum) and last observed state.

Example:

```csv
Serial,Active,Mac,DesiredIP,DesiredSubnetMask,DesiredGateway,DesiredFirmwareLabel,DesiredConfigSha256,ObservedIP,ObservedFirmwareLabel,ObservedFid,LastSeen,LastAction,LastResult,Notes
3241995707,TRUE,00-30-A7-3D-6F-A9,192.168.1.101,255.255.255.0,192.168.1.1,SEL-751-R401,,192.168.1.2,SEL-751-R401,SEL-751-R401-V0-Z101100-D20240308,,,,"Example relay"
```

Field notes:

- **Desired*** fields represent the intended target configuration.
- **Observed*** fields represent what was last measured during inventory.
- **DesiredConfigSha256** should hold the SHA-256 hash of the “golden” configuration/settings file (when you implement config distribution).
- **Mac** is advisory and may include multiple MACs over time (dual-port devices); Serial remains authoritative.

---

# Recommended Repo Data Layout

```text
data/
  defaults.csv
  desiredstate.csv
  devices/
    <serial>.json
```

---

# Re-IP Procedure Context (SET P 1)

This project changes SEL-751 Port 1 network settings using the interactive `SET P 1` command dialog.

## Observed access behavior (from PuTTY transcript)

- `SET P 1` at base access (`=`) returns **Invalid Access Level**
- After `ACC` (Level 1 / prompt `=>`), `SET P 1` still returns **Invalid Access Level**
- After `2AC` (Level 2 / prompt `=>>`), `SET P 1` successfully enters the Port 1 configuration dialog

Therefore, **the tool must probe** and escalate as needed:
1. Try `SET P 1` at current level
2. If denied, attempt `ACC`, retry
3. If denied, attempt `2AC`, retry
4. If denied, attempt `C` (if applicable/available), retry
5. If still denied, abort and instruct front-panel remediation

## Command flow

1. Connect via Telnet
2. Run `ID` (always)
3. Escalate to required access (minimum needed to successfully enter `SET P 1`)
4. Run `SET P 1`
5. Provide new values for:
   - `IPADDR` (IP address)
   - `SUBNETM` (subnet mask)
   - `DEFRTR` (default router / gateway)
6. Continue through prompts and **Save** when prompted
7. Expect Telnet session to drop after applying IP change
8. Reconnect to the new IP and verify identity (Serial via `STA` or equivalent)

## Key fields shown in the SET P 1 dialog

Common items and their short field codes:

### Port Enable
- `EPORT`  — enable port (Y/N)

### Firmware Upgrade Configuration
- `EETHFWU` — enable Ethernet firmware upgrade (Y/N)

### Ethernet Port Settings
- `IPADDR`  — IP address
- `SUBNETM` — subnet mask
- `DEFRTR`  — default router (gateway)
- `ETCPKA`  — TCP keep-alive enable
- `KAIDLE`, `KAINTV`, `KACNT` — keep-alive tuning
- `NETMODE`, `FTIME`, `NETPORT` — port mode/failover behavior

### Telnet Configuration
- `ETELNET` — enable Telnet (Y/N)
- `MAXACC`  — maximum access level allowed over Telnet (1,2,C)
- `TPORT`   — Telnet TCP port
- `TCBAN`   — Telnet connect banner
- `TIDLE`   — idle timeout

### FTP Configuration
- `EFTPSERV` — enable FTP server (Y/N)
- `FTPACC`   — FTP maximum access level (1,2,C)
- `FTPUSER`  — FTP username
- `FTPCBAN`  — FTP banner
- `FTPIDLE`  — FTP idle timeout

## Important implications

- If `MAXACC := 2`, you cannot reach Access Level C over Telnet even if you know the password.
- If `EETHFWU := N`, you cannot upgrade firmware over Ethernet/FTP until enabled.

## Parsing / prompt-driving notes

The dialog is interactive and includes `?` prompts after each field. The tool should:
- treat each `?` as "input requested"
- send either:
  - a new value (for fields being changed), or
  - an empty line to accept the existing value and advance

Recommended detection strings:
- `"Invalid Access Level"`
- `"Password:"`
- `"Level 1"`, `"Level 2"` (as informational, not sole truth)
- Field prompt lines containing `:=` and ending with `?`

Control characters (e.g., `\x02`, `\x03`) should be stripped before parsing.

Generated: 2026-03-05T01:16:29.642404
