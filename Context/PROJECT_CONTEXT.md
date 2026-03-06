# PROJECT_CONTEXT

## Product goals
- Automate SEL relay commissioning tasks over Ethernet:
  - Connect via telnet and record inventory info and record to *serial number*.json
  - Re-IP a single unit
  - Upgrade firmware on a single unit
- Support defaults from defaults.csv, interactive(prompts) and automation (CLI args).
- Maintainability and auditability over cleverness.

## Non-goals (for now)
- Bulk re-IP from desiredstate.csv
- Bulk upgrade firmware from desiredstate.csv
- Full fleet orchestration (bulk mode, CSV/JSON history) in v0.1
- GUI
- External dependencies / third-party modules

## Architecture decisions
- PowerShell module + CLI entry script
- Use built-in .NET: TcpClient/NetworkStream for Telnet; FtpWebRequest for FTP
- Prompt-driven Telnet automation using ReadUntil(regex)
- Identity is Serial-first; MAC is logged/warning only (dual ports)

## Constraints
- No external deps
- Must work on typical Windows commissioning laptops
- Access level requirements vary by relay configuration; the tool probes and escalates only as needed (ACC → 2AC → C).
- Telnet MAXACC may block C escalation; remediation is front-panel changes

## Glossary / domain terms
- Default IP: factory IP (often 192.168.x.x)
- Access levels: ACC, 2AC, C
- MAXACC: port setting limiting max access level for the interface
- EETHFWU: port setting enabling Ethernet firmware upgrade
- FID/BFID/CID: firmware/build identifiers from ID command

## Current status
- Spec written and revised
- Next: implement scaffolding + minimal working re-IP and firmware upgrade flows
- Need: capture actual SEL-751 Telnet dialogs for:
  - escalation prompts
  - SET P 1 prompt sequence
  - ID/ETH/STA output format

## Definition of done (v0.1)
- `seltool.ps1 inventory` Pull inventory information and store as *serial number*.JSON
- `seltool.ps1 reip` can set IP/mask/gw and verify by reconnecting
- *Future*`seltool.ps1 upgrade` can FTP PUT firmware file and verify FID change
- Both support interactive prompts if args missing
- Basic tests for parsing and argument handling

## Data Storage Model

The tool uses simple file-based storage (CSV + JSON) to avoid external dependencies.

- `data/defaults.csv` — single-row runtime defaults (network assumptions, credentials, firmware target defaults)
- `data/desiredstate.csv` — desired and last-observed state for each relay (primary key: Serial)
- `data/devices/<serial>.json` — immutable per-device history (append-only events)

See `context/SEL_inventory_context_addendum.md` for starter CSV examples and inventory schema details.


## Re-IP mechanism (SET P 1)

SEL-751 Port 1 network settings are modified using the interactive CLI dialog:

- `SET P 1`

Observed access behavior varies by configuration. On the captured unit:

- At base prompt (`=`): `SET P 1` → `Invalid Access Level`
- After `ACC` (prompt `=>`): `SET P 1` → `Invalid Access Level`
- After `2AC` (prompt `=>>`): `SET P 1` → enters the Port 1 configuration dialog

### Tool behavior

For re-IP operations, the tool must:

1. Run `ID` first (always)
2. Attempt `SET P 1` at current access
3. If denied, escalate in order and retry:
   - `ACC` → retry `SET P 1`
   - `2AC` → retry `SET P 1`
   - `C` (if applicable/available) → retry `SET P 1`
4. If still denied, abort, close session, and instruct front-panel remediation

### Dialog driving

The `SET P 1` dialog is interactive. The tool advances by responding to each `?` prompt:
- send a new value for fields being changed (IPADDR, SUBNETM, DEFRTR, optionally EETHFWU/MAXACC)
- send an empty line to keep the existing value and move to the next field

Expect the Telnet session to drop after saving the new IP; the tool must reconnect to the new IP and verify identity (Serial).

### Key fields

- `IPADDR` — IP address
- `SUBNETM` — subnet mask
- `DEFRTR` — default gateway/router
- `MAXACC` — maximum access level permitted over Telnet (1,2,C)
- `EETHFWU` — enable Ethernet firmware upgrade (Y/N)

Implications:
- If `MAXACC := 2`, C cannot be obtained over Telnet even with the password.
- If `EETHFWU := N`, Ethernet firmware upgrades are disabled until enabled.


## Telnet protocol notes

This project relies on prompt-driven automation over Telnet. Prompts and control characters may vary; captured transcripts are used to build deterministic parsers and tests.

See `context/TELNET_PROTOCOL.md` for prompt tokens, access escalation behavior, denial signatures, and interactive dialog driving guidance.


## Logging Model

The tool writes **one primary log file per run**:

- `logs/run-YYYYMMDD-HHMMSS.log`

A single **RunId** is generated at startup and used in:
- the log file name
- structured JSON history references
- summary/report records

### Why one log per run

One per-run log makes field troubleshooting simpler:
- one file to attach to a ticket
- one place to review Telnet, FTP, parse, and error activity
- easier correlation across multiple devices touched in the same execution

### Optional future enhancement

The project may later add an additional structured per-run log format such as:

- `logs/run-YYYYMMDD-HHMMSS.jsonl`

This is optional and not required for v0.1.

### Logging categories

The run log should include, at minimum, these categories:

- `TELNET` — connect, disconnect, send, receive, prompt detection
- `FTP` — connect, upload/download, status, disconnect
- `PARSE` — extracted identity and configuration fields
- `STATE` — workflow state changes such as inventory, re-IP, upgrade start/end
- `ERROR` — exceptions, timeouts, access denials, parse failures

### Redaction policy

Sensitive values must never be written to logs in plaintext.

At minimum, redact:
- `ACCPassword`
- `2ACPassword`
- `CALPassword`
- `FtpPassword`

When sending a password over Telnet or FTP, log a redacted placeholder instead, for example:

- `TX "<REDACTED_PASSWORD>"`

### Log verbosity

The tool should support at least two log levels:

- `Compact` — operationally useful lines only
- `Full` — full Telnet/FTP activity including raw receive chunks

Recommended default for field use:
- `Compact`

### JSON history references

Per-device JSON history files should remain structured and relatively clean.

Instead of embedding full Telnet and FTP transcripts into every device JSON file, store:
- structured event data
- the `RunId`
- a pointer back to the run log

Example fields:

- `runId`
- `logFile`
- `logStartLine`
- `logEndLine`

This keeps device history queryable while preserving full forensic detail in the run log.

### Logging implementation expectation

A shared logger should be created once per run and used by:
- Telnet session handling
- FTP handling
- parsing functions
- public command workflows

The logger should:
- write timestamped lines
- track line numbers
- support device serial once known
- support redaction


### Per-device JSON vs run log

Per-device JSON files (e.g., `data/devices/<serial>.json`) should contain **only structured facts about the SEL relay over time**:
- identity snapshots (ID/STA/ETH parsed fields)
- observed network state
- change events (re-IP, firmware upgrade) including before/after values and success/failure
- minimal traceability metadata (`timestamp`, `runId`, and a `logRef` pointer)

They must **not** contain full Telnet/FTP transcripts or verbose operational chatter. Full transcripts and detailed errors belong in the per-run log file.


