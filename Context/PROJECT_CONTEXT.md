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
- Prompt-driven Telnet automation using read-until prompt matching.
- Serial is authoritative identity; MAC is advisory only.
- Runtime target: Windows PowerShell 5.1.

## Input and persistence policy
- Credentials source policy:
  - Read from `defaults.csv` profile row when present (default profile: `factory`).
  - Prompt securely when missing.
  - `seltools.ps1` supports `-Profile <name>` to select a defaults row.
- Re-IP target precedence:
  1. CLI args
  2. `desiredstate.csv` lookup by Serial
  3. Interactive prompt
- Inventory persistence:
  - Append structured event to `data/devices/<serial>.json`
  - Update observed fields in `desiredstate.csv`
  - If serial is missing in CSV, append a new row with observed values
- Reserved or inactive CSV rows are ignored by runtime processing:
  - `Serial=TEMPLATE` rows
  - blank Serial rows
  - rows where `Active` is false

## Re-IP behavior decisions
- `ID` runs first.
- Escalation probe order when `SET P 1` is denied: `ACC` -> `2AC` -> `C`.
- If still denied, abort and instruct front-panel remediation.
- If serial mismatch is detected after reconnect, warn and continue.

## Logging policy
- One run log file per run: `logs/run-YYYYMMDD-HHMMSS.log`
- Default verbosity: `Compact` (optional `Full`)
- Redact sensitive values in logs during transmission.
- Per-device JSON stores structured facts only and references run log location.

## Defaults file mutability
- At end of run, the tool may prompt whether to update `defaults.csv`.
- If confirmed, all fields may be written, including password fields.

## Definition of done (v0.1)
- `seltools.ps1 inventory` captures ID/STA/ETH (or ID-only fallback) and persists JSON plus observed CSV state.
- `seltools.ps1 reip` applies IP/mask/gateway via `SET P 1`, reconnects, and verifies identity behavior.
- `seltools.ps1 fwupgrade` exists as a stub with explicit `NotImplemented` output.
- Commands support interactive prompts when args are missing.
- Pester tests cover parser behavior and argument/input precedence.

## Implementation status (2026-03-05)
- Implemented:
  - Profile-based defaults selection (`-Profile`, default `factory`)
  - Live inventory Telnet flow (`ID`, `ACC`, `STA`, `ETH`)
  - Parsing of ID/STA/ETH fields and persistence to:
    - `data/devices/<serial>.json`
    - observed columns in `data/desiredstate.csv`
- Current next target:
  - Implement live `reip` over `SET P 1` interactive prompts with reconnect and serial verification.
