# PROJECT_CONTEXT

## Product goals
- Automate SEL relay commissioning tasks over Ethernet:
  - Connect via Telnet and record inventory to `data/devices/<serial>.json`
  - Re-IP a single unit with reconnect and identity verification
  - Prepare firmware command surface using `fwupgrade` naming
- Support defaults from `defaults.csv`, interactive prompts, and CLI automation.
- Maintainability and auditability over cleverness.

## v0.1 scope
- Implement: `inventory`, `reip`
- Expose: `fwupgrade` command as a clear stub (`NotImplemented`)
- Defer: `blupgrade`, `fwdowngrade`, and bulk orchestration

## Non-goals (for now)
- Bulk re-IP from `desiredstate.csv`
- Bulk firmware actions from `desiredstate.csv`
- GUI
- External dependencies / third-party modules

## Architecture decisions
- Single CLI entry script `seltools.ps1` over a reusable PowerShell module.
- Bundled `tools/plink.exe` process transport for Telnet and built-in `FtpWebRequest` for FTP.
- Prompt-driven Telnet automation with best-effort capture fallback for long/partial command outputs.
- Menu-driven interactive CLI is shown when `seltools.ps1` runs without `-Command`.
- Serial is authoritative identity; MAC is advisory only.
- Runtime target: Windows PowerShell 5.1.
- Local static web app under `web/` for browsing/editing data via File System Access API.

## SEL-751 Ethernet interface model
- Port 1 is the Ethernet configuration group (not a specific physical interface).
- Physical interfaces under Port 1 are `1A` and `1B`.
- `SET P 1` enters Ethernet group configuration scope.
- `NETPORT := A|B` selects configured primary side for Port 1.
- `ETH` status uses `1A`/`1B` naming (`PRIMARY PORT`, `ACTIVE PORT`, `PORT 1A`, `PORT 1B`).
- Internal normalized model:
  - `portGroup = "1"`
  - `interfaces = ["1A","1B"]`
  - `primaryInterface = "1A"|"1B"`
  - `activeInterface = "1A"|"1B"`
  - `configuredPrimarySelector = "A"|"B"`
  - `netMode = relay NETMODE value`

## Interface gotchas
- `SET P 1` does not choose `A` or `B` by itself.
- `NETPORT` chooses the configured primary interface.
- `ETH` reports runtime state; `ACTIVE PORT` may differ from configured primary in failover/switching modes.

## Scripting guidance
- Use `ETH` to discover runtime interface state (`PRIMARY PORT`, `ACTIVE PORT`, per-interface rows).
- Use `SET P 1` to configure Ethernet group settings.
- Use `NETPORT` to set preferred primary side.
- Keep configured state and runtime state as separate fields in JSON/desired state.

## Input and persistence policy
- Credentials source policy:
  - Read from `defaults.csv` profile row when present (default profile: `factory`).
  - Prompt securely when missing.
  - `seltools.ps1` supports `-Profile <name>` to select a defaults row.
- Re-IP target precedence:
  1. CLI args
  2. `desiredstate.csv` lookup by Serial
  3. Interactive prompt
- Re-IP scope:
  - single-device address change only
  - active write set is `IPADDR`, `SUBNETM`, `DEFRTR`
  - `NETPORT` / interface switching is out of scope for the current re-IP path
- Inventory persistence:
  - Append structured event to `data/devices/<serial>.json`
  - Maintain top-level device metadata in JSON: `name`, `description`
  - Include inventory payload compatibility field `STA` summary (no raw `inventory.SER` payload)
  - Append SER pull summary events (`action=ser-pull`) with references to event store + raw archive
  - Store SER event stream separately in:
    - `data/events/<serial>/ser.jsonl`
    - `data/events/<serial>/<timestamp>-ser.txt`
  - Update observed fields in `desiredstate.csv`
  - If serial is missing in CSV, append a new row with observed values
  - `desiredstate.csv` includes optional metadata columns: `Name`, `Description`
  - `desiredstate.csv` interface columns:
    - `DesiredPrimaryInterface`
    - `ObservedPrimaryInterface`
    - `ObservedActiveInterface`
    - `ObservedNetMode`
- Inventory host resolution precedence:
  1. CLI `-HostIp`
  2. If `-Serial` is provided and `-HostIp` is missing:
     - latest inventory `hostIp` from `data/devices/<serial>.json`
     - if conflicting with `desiredstate.csv` `ObservedIP`, operator chooses source (json/desiredstate/quit)
  3. Profile `DefaultIP` (when Serial is not provided)
- If no connectable IP can be resolved from the above, inventory fails with guidance to run IP-range discovery.
- Reserved or inactive CSV rows are ignored by runtime processing:
  - `Serial=TEMPLATE` rows
  - blank Serial rows
  - rows where `Active` is false

## Re-IP behavior decisions
- `ID` runs first.
- Re-IP access path is `ACC` -> `2AC`.
- If access escalation fails, abort and instruct remediation.
- If serial mismatch is detected after reconnect, warn and continue.
- `reip` is bench-usable and transcript-grounded, but should still be treated as test-equipment workflow rather than field automation.
- The current risk is the interactive dialog tail: a transcript now confirms `Save changes (Y,N)?` and `Settings Saved`, but PuTTY may still log trailing prompt text even though the usable live session has already ended.
- Current observed behavior suggests IP change is a near-instant session/network cutover, not a relay reboot; reconnect logic should start almost immediately after save.
- Re-IP identity uses `STA` and `ETH`; inventory uses `SER` and `ETH`.
- Re-IP always collects identity needed for confirmation and verification, even when inventory update is skipped.
- In the interactive menu, re-IP prompts for:
  - `Host IP`
  - `Target IP`
  - `Target subnet mask`
  - `Target gateway`
  - `Update inventory? [N]`
- Re-IP prints its run report immediately after completion in the menu flow.

## Logging policy
- One run log file per run: `logs/run-YYYYMMDD-HHMMSS.log`
- Default verbosity: `Compact` (optional `Full`)
- `seltools.ps1` supports `-DebugTransport` for live console+file transport tracing.
- Redact sensitive values in logs during transmission.
- Per-device JSON stores structured facts only and references run log location.

## Defaults file mutability
- At end of run, the tool may prompt whether to update `defaults.csv`.
- If confirmed, all fields may be written, including password fields.

## Definition of done (v0.1)
- `seltools.ps1 inventory` captures ID/ACC/SER/ETH and persists JSON plus observed CSV state.
- `seltools.ps1 reip` applies IP/mask/gateway via `SET P 1`, reconnects, and verifies identity behavior using `STA` plus `ETH`.
- `seltools.ps1 fwupgrade` exists as a stub with explicit `NotImplemented` output.
- Commands support interactive prompts and no-arg menu operation.
- Pester tests cover parser behavior, argument/input precedence, and CLI helper dispatch/prompt defaults.

## Implementation status (2026-03-28)
- Implemented:
  - Profile-based defaults selection (`-Profile`, default `factory`)
  - Plink transport for Telnet session handling (`tools/plink.exe` with `SELTOOLS_PLINK_PATH` override)
  - Live inventory Telnet flow (`ID`, `ACC`, `SER`, `ETH`)
  - Live re-IP identity flow (`ID`, `ACC`, `2AC`, `STA`, `ETH`)
  - Live re-IP address change flow (`SET P 1`) for `IPADDR`, `SUBNETM`, `DEFRTR`
  - Transcript-backed save handling (`Save changes (Y,N)?`, `Settings Saved`)
  - Immediate reconnect after save with serial verification
  - Always-on run logging with `logs/run-YYYYMMDD-HHMMSS.log`
  - Parsing of ID/STA/ETH fields and persistence to:
    - `data/devices/<serial>.json`
    - observed columns in `data/desiredstate.csv`
  - Normalized Ethernet model in inventory events:
    - `inventory.Ethernet.portGroup`, `interfaces`, `primaryInterface`, `activeInterface`, `configuredPrimarySelector`, `netMode`, `interfaceStatus`
    - compatibility aliases retained during transition (`primaryPort`/`activePort`)
  - SER event stream persistence to `data/events/<serial>/ser.jsonl` with raw archives in `data/events/<serial>/`
  - Menu-driven no-arg CLI (`inventory|reip|fwupgrade|help|exit`) with guided prompts and value prefills
  - Re-IP menu simplified to host-IP-driven prompts without serial/profile entry
  - Re-IP menu prompt `Update inventory? [N]` with remembered in-session default
  - Inventory sub-menu (`Single IP scan`, `IP Range scan` placeholder, `Inventory Browser` launcher)
  - Run report with:
    - new devices discovered
    - existing devices with detected changes
    - explicit re-IP action summaries showing old IP -> new IP and status
    - immediate re-IP report emission in menu flow plus exit summary
  - Name/Description metadata support in desired state and per-device JSON
  - Metadata sync on inventory so Name/Description are carried in both desiredstate and per-device JSON
  - Static browser app (`web/`) with:
    - smart `Connect to data` flow (saved handle first, picker fallback)
    - operators browse to `/seltools/data` (data root containing `desiredstate.csv` and `devices/`)
    - desiredstate editing + device metadata editing
    - read-only inventory browser view
    - SER event stream browser for `data/events/<serial>/ser.jsonl`
- Current next target:
  - Keep tightening documentation and transcript coverage around live re-IP behavior.
  - Decide whether generated runtime artifacts (`logs/`, local device snapshots) should remain local-only or become tracked deliverables.
  - Implement real firmware workflow behind `fwupgrade`.
