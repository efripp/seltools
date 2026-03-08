# DECISIONS (ADR)

## ADR-0001: Use PowerShell + bundled plink transport
**Decision:** Implement Telnet transport through bundled `tools/plink.exe`; keep FTP on `FtpWebRequest`.
**Alternatives:** `TcpClient`/`NetworkStream`, NuGet Telnet libs, external `telnet.exe`.
**Reason:** Avoid Defender issues from direct socket automation while keeping deployment self-contained.
**Consequence:** Runtime requires `tools/plink.exe` (or `SELTOOLS_PLINK_PATH` override) and stream-driven prompt matching.

## ADR-0002: Serial number is authoritative identity
**Decision:** Use Serial as primary key; MAC is warning/advisory.
**Alternatives:** MAC as primary key.
**Reason:** Dual Ethernet ports can yield MAC mismatches.
**Consequence:** Always capture serial before and after changes.

## ADR-0003: Fail-fast on escalation exhaustion
**Decision:** If required access cannot be obtained for `SET P 1`, close session and instruct front-panel remediation.
**Alternatives:** Retry indefinitely, continue partially.
**Reason:** Prevent partial/unsafe operations.
**Consequence:** Operations stop safely when access is blocked.

## ADR-0004: v0.1 command surface and naming
**Decision:** v0.1 implements `inventory` and `reip`; `fwupgrade` is exposed as a stub (`NotImplemented`).
**Alternatives:** Expose no firmware command; implement full firmware flow now.
**Reason:** Preserve intended command naming while limiting v0.1 scope.
**Consequence:** Future firmware work extends `fwupgrade` and later adds `blupgrade`/`fwdowngrade`.

## ADR-0005: Re-IP target value precedence
**Decision:** Resolve IP/mask/gateway as CLI args > `desiredstate.csv` row by Serial > interactive prompt.
**Alternatives:** CSV-first or prompt-first.
**Reason:** CLI should be deterministic for automation while preserving fallback usability.
**Consequence:** Argument parsing and CSV lookup must share one precedence resolver.

## ADR-0006: Inventory persistence and unknown serials
**Decision:** Inventory writes per-device JSON and updates observed CSV fields; unknown serials are appended to `desiredstate.csv`.
**Alternatives:** JSON-only, CSV-only, or fail on unknown serial.
**Reason:** Keep both operational state and append-only history synchronized.
**Consequence:** CSV upsert behavior is required in v0.1.

## ADR-0007: Reserved or inactive desired-state rows are ignored
**Decision:** Rows with blank Serial, reserved markers (for example `TEMPLATE`), or `Active=false` are ignored by runtime workflows.
**Alternatives:** Treat as errors or as normal device rows.
**Reason:** Allow template guidance without breaking command flows.
**Consequence:** CSV loaders need explicit row-filter rules.

## ADR-0008: Re-IP serial mismatch policy
**Decision:** If serial mismatch is detected after re-IP reconnect, warn and continue while marking the run outcome accordingly.
**Alternatives:** Hard fail or interactive pause.
**Reason:** Maintain field momentum while preserving visibility of risk.
**Consequence:** Result reporting must carry mismatch warning state.

## ADR-0009: Logging default is Compact
**Decision:** Default log level is `Compact`; `Full` is opt-in.
**Alternatives:** Full-by-default.
**Reason:** Compact logs are easier for routine field operations.
**Consequence:** Logger must support explicit verbose override.

## ADR-0010: Defaults update prompt allows full row writes
**Decision:** At run end, prompt whether to update `defaults.csv`; if accepted, all fields may be persisted, including passwords.
**Alternatives:** Never update defaults, or never write secrets.
**Reason:** Operator requested convenience for repeated field operations.
**Consequence:** Logging/redaction must continue to prevent secret leakage.

## ADR-0011: Runtime and test baseline
**Decision:** Target Windows PowerShell 5.1 and use Pester for tests.
**Alternatives:** PowerShell 7+ only, custom script tests.
**Reason:** Max compatibility on commissioning laptops with standard test framework.
**Consequence:** Implementation should avoid PS7-only language/features.

## ADR-0012: Defaults profiles
**Decision:** `defaults.csv` supports multiple rows with a required `Profile` column; CLI selects via `-Profile` and defaults to `factory`.
**Alternatives:** Single-row defaults only.
**Reason:** Preserve factory defaults while allowing site-specific profiles.
**Consequence:** Defaults loader must resolve profile names and fail clearly when profile is missing.

## ADR-0013: Inventory command is live-first in v0.1
**Decision:** `inventory` executes real Telnet capture (`ID` -> `ACC` -> `STA` -> `ETH`) and persists parsed outputs; it is no longer scaffold-only.
**Alternatives:** Keep scaffold inventory until all commands are implemented.
**Reason:** Field validation against real SEL relays is needed early to de-risk parser and protocol assumptions.
**Consequence:** Inventory events now include parsed protocol data and observed-state updates from live relay responses.

## ADR-0014: No-arg CLI uses menu-driven interactive mode
**Decision:** When `seltools.ps1` is run without `-Command`, present a numbered menu loop (`inventory`, `reip`, `fwupgrade`, `help`, `exit`) with guided prompts and prefilled values from any provided options.
**Alternatives:** Single free-text command prompt, or hard error when `-Command` is omitted.
**Reason:** Improve field usability while preserving explicit command-mode automation.
**Consequence:** CLI script includes interactive menu helpers and direct dispatch remains unchanged when `-Command` is provided.

## ADR-0015: Inventory serial can resolve host IP but not identity
**Decision:** For `inventory`, `-Serial` may be used only to resolve a missing host IP from prior state; device identity remains relay-derived from live protocol output.
**Alternatives:** Ignore serial entirely in inventory, or permit manual serial fallback for persistence.
**Reason:** Serial can speed reconnect workflows, but manual serial should not overwrite relay-reported identity.
**Consequence:** Inventory host resolution may prompt when JSON and desiredstate IPs conflict; if no host can be resolved, command fails with range-discovery guidance.

## ADR-0016: Debug transport trace mode
**Decision:** Add `-DebugTransport` switch to CLI command paths to emit live transport+command-flow diagnostics to console and `logs/run-*.log`.
**Alternatives:** Console-only ad hoc output or log-file-only tracing.
**Reason:** Field troubleshooting needs immediate visibility into where Telnet/plink sessions stall.
**Consequence:** Transport helpers include timeout-aware trace points and redacted TX logging for sensitive values.
