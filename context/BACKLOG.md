# BACKLOG

## Done
- Drafted module spec + safety policies
- Captured v0.1 decisions for command surface, persistence, logging, and CSV handling
- CLI scaffold (`seltools.ps1`) with profile-based defaults selection
- Bundled `plink.exe` transport integrated for Telnet session flow
- Live inventory over Telnet implemented (`ID` -> `ACC` -> `SER` -> `ETH`) with parsing + persistence
- No-arg menu-driven CLI flow implemented (`inventory`, `reip`, `fwupgrade`, `help`, `exit`)
- Baseline parser/preference and CLI helper tests in Pester are passing
- Inventory supports serial-based host lookup using prior JSON/desiredstate observations with conflict chooser
- `-DebugTransport` tracing added for live transport + command-flow diagnostics to console and run log
- End-of-run report added (new devices + detected changes + explicit no-change output)
- Desired-state and JSON metadata support added for `Name` and `Description`
- Inventory Browser menu option now launches local web app host/browser
- Web app `Connect to data` smart flow added (saved handle first, picker fallback)
- Web app folder contract set to data root: browse to `/seltools/data`
- SER event stream stored separately (`data/events/<serial>/ser.jsonl` + raw `*-ser.txt` archives)
- Inventory writes `ser-pull` summary events and no longer persists raw `inventory.SER`
- Inventory Browser can browse SER event stream data per device
- Re-IP scaffold dispatch/prompt flow is wired into CLI/menu paths
- Re-IP target precedence resolver implemented (CLI > desiredstate by serial > prompt)
- Re-IP scaffold event persistence and `-PassThru` run-report object implemented
- Re-IP live `SET P 1` flow implemented for `IPADDR`, `SUBNETM`, `DEFRTR`
- Re-IP now uses `ACC -> 2AC`, `STA`, and `ETH` for confirmation/reconnect verification
- Re-IP menu simplified to host-IP-driven prompts without serial/profile entry
- Re-IP menu now prompts `Update inventory? [N]` and remembers the in-session choice
- Re-IP run report now shows old IP -> new IP and prints immediately after completion
- Real `SET P 1` and `STA` transcripts captured under `context/transcripts/`
- Normalized SEL-751 Ethernet model added to inventory parsing (`portGroup=1`, `interfaces=1A/1B`, `primaryInterface`, `activeInterface`, `configuredPrimarySelector`, `netMode`)
- Desired-state schema extended for interface state (`DesiredPrimaryInterface`, `ObservedPrimaryInterface`, `ObservedActiveInterface`, `ObservedNetMode`)
- CLI/scaffold reip selector added as `-PrimaryInterface 1A|1B` with mapping to relay `NETPORT A|B`
- Backward-compat alias writes retained (`primaryPort`/`activePort`) while normalized fields are preferred

## In progress
- Context/doc cleanup to match the live re-IP workflow and current menu behavior
- Decide local ignore policy for generated runtime artifacts (`logs/`, local device snapshots)

## Next
### 1) CLI scaffolding
**Acceptance:**
- `seltools.ps1` supports `inventory`, `reip`, and `fwupgrade` (stub).
- Missing inputs are prompted interactively.
- Running without `-Command` enters the menu loop and supports guided prompt prefills.
- Command parsing works on Windows PowerShell 5.1.
**Blockers:** none

### 2) Telnet session MVP
**Acceptance:**
- Plink-backed session transport can connect/send/read-until prompt reliably.
- Prompt detection supports `=`, `=>`, and `=>>`.
- Logging uses shared run logger with default Compact mode.
**Blockers:** none

### 3) Inventory workflow (working)
**Acceptance:**
- Command order: `ID`, then `ACC`, then `SER`/`ETH` when available.
- Writes `data/devices/<serial>.json` structured event.
- Maintains top-level JSON metadata (`name`, `description`) from desired state when available.
- Persists compatibility `inventory.STA` plus explicit `inventory.SER`.
- Updates observed columns in `data/desiredstate.csv`.
- Appends a new CSV row when serial is not found.
- Ignores reserved/inactive rows (`TEMPLATE`, blank serial, or `Active=false`).
**Blockers:** none

### 4) Re-IP workflow (next major implementation)
**Acceptance:**
- Keep transcript-backed prompt handling stable as more relay variants are observed.
- Preserve single-device address-change scope (`IPADDR`, `SUBNETM`, `DEFRTR`) unless interface switching is deliberately reintroduced later.
- Serial mismatch remains warning-state (continue + report), not immediate abort.
**Blockers:** none for bench use; more live coverage is still desired before treating re-IP as field-automation ready.

### 5) Firmware command surface (stub)
**Acceptance:**
- `fwupgrade` command exists and returns clear `NotImplemented` guidance.
- Backlog notes future `blupgrade` and `fwdowngrade` commands.
**Blockers:** firmware behavior and device-specific transfer details deferred

### 6) Test baseline
**Acceptance:**
- Pester tests for parser logic, CSV row filtering, and input precedence resolver.
- Pester tests for CLI argument handling and fallback prompting behavior.
**Blockers:** add more transcript/integration-like coverage as Telnet/reip matures
