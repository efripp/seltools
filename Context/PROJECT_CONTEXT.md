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
- Re-IP primary interface selector:
  - Canonical CLI selector is `-PrimaryInterface` with values `1A` or `1B`.
  - Relay config selector is mapped to/from `NETPORT` values `A` or `B`.
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
- Escalation probe order when `SET P 1` is denied: `ACC` -> `2AC` -> `C`.
- If still denied, abort and instruct front-panel remediation.
- If serial mismatch is detected after reconnect, warn and continue.
- `reip` is not considered field-ready until at least one real `SET P 1` transcript is captured and reviewed.
- The current risk is the interactive dialog tail: exact save/apply confirmation text, full prompt ordering, and disconnect wording still need grounding in a real relay transcript.

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
- `seltools.ps1 reip` applies IP/mask/gateway via `SET P 1`, reconnects, and verifies identity behavior.
- `seltools.ps1 fwupgrade` exists as a stub with explicit `NotImplemented` output.
- Commands support interactive prompts and no-arg menu operation.
- Pester tests cover parser behavior, argument/input precedence, and CLI helper dispatch/prompt defaults.

## Implementation status (2026-03-23)
- Implemented:
  - Profile-based defaults selection (`-Profile`, default `factory`)
  - Plink transport for Telnet session handling (`tools/plink.exe` with `SELTOOLS_PLINK_PATH` override)
  - Live inventory Telnet flow (`ID`, `ACC`, `SER`, `ETH`)
  - Parsing of ID/STA/ETH fields and persistence to:
    - `data/devices/<serial>.json`
    - observed columns in `data/desiredstate.csv`
  - Normalized Ethernet model in inventory events:
    - `inventory.Ethernet.portGroup`, `interfaces`, `primaryInterface`, `activeInterface`, `configuredPrimarySelector`, `netMode`, `interfaceStatus`
    - compatibility aliases retained during transition (`primaryPort`/`activePort`)
  - SER event stream persistence to `data/events/<serial>/ser.jsonl` with raw archives in `data/events/<serial>/`
  - Menu-driven no-arg CLI (`inventory|reip|fwupgrade|help|exit`) with guided prompts and value prefills
  - Inventory sub-menu (`Single IP scan`, `IP Range scan` placeholder, `Inventory Browser` launcher)
  - End-of-run report with:
    - new devices discovered
    - existing devices with detected changes
    - explicit `No changes detected.` line when none are found
  - Name/Description metadata support in desired state and per-device JSON
  - Metadata sync on inventory so Name/Description are carried in both desiredstate and per-device JSON
  - Static browser app (`web/`) with:
    - smart `Connect to data` flow (saved handle first, picker fallback)
    - operators browse to `/seltools/data` (data root containing `desiredstate.csv` and `devices/`)
    - desiredstate editing + device metadata editing
    - read-only inventory browser view
    - SER event stream browser for `data/events/<serial>/ser.jsonl`
  - Re-IP scaffold behavior:
    - command/menu dispatch is wired to `Invoke-SelReIp`
    - target resolution precedence is implemented: CLI > desiredstate by serial > interactive prompt
    - reip events are persisted to per-device JSON with resolved target values and source metadata
    - `-PassThru` returns structured run-report data for menu summary integration
- Current next target:
  - Complete live `reip` over `SET P 1` interactive prompts with reconnect and serial verification.
  - Add access escalation flow for denied `SET P 1` (`ACC` -> `2AC` -> `C`) and fail-safe handling.
  - Add reconnect identity checks and serial mismatch warning/report behavior for reip runs.
  - Capture and retain at least one real `SET P 1` transcript before declaring `reip` ready for field use.
