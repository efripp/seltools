# LOGGING

Generated: 2026-03-05T23:39:20.521720

## Scope

Defines how SelTool records operational activity to disk.

The logging model is intended to:
- preserve full troubleshooting detail
- keep per-device JSON history files clean
- support both field review and future automation/reporting

---

## Primary Logging Strategy

SelTool writes **one primary log file per run**.

Format:

- `logs/run-YYYYMMDD-HHMMSS.log`

A single `RunId` is generated when the tool starts and is reused throughout the run.

Example:

- `RunId = 20260305-211001`
- `logs/run-20260305-211001.log`

This is the authoritative transcript of the run.

---

## Why One Log Per Run

A per-run log is preferred because it:

- keeps all activity for a session in one place
- simplifies troubleshooting and ticket attachment
- avoids scattering related events across many files
- makes it easier to correlate behavior across multiple devices touched in one execution

---

## Optional Secondary Log Format

The tool may later add an optional structured log file:

- `logs/run-YYYYMMDD-HHMMSS.jsonl`

This is not required for v0.1.

Use cases:
- machine parsing
- dashboards
- later database ingestion

---

## Log Categories

Each log entry should include a category.

Minimum categories:

- `TELNET`
- `FTP`
- `PARSE`
- `STATE`
- `ERROR`

### Category meanings

- `TELNET`  
  Connect, disconnect, TX/RX activity, prompt detection, access escalation steps.

- `FTP`  
  FTP connection, file upload/download, status codes, disconnects.

- `PARSE`  
  Parsed values extracted from `ID`, `STA`, `ETH`, and other command outputs.

- `STATE`  
  High-level workflow events such as inventory started, re-IP started, re-IP complete, firmware upgrade started, firmware upgrade verified.

- `ERROR`  
  Access failures, timeouts, network errors, parse failures, unexpected disconnects, exceptions.

---

## Recommended Log Line Format

Use a single-line, timestamped, human-readable format.

Example:

```text
2026-03-05T21:10:01.234-0500 [RUN 20260305-211001] [DEV ?] [TELNET] CONNECT host=192.168.1.2:23
2026-03-05T21:10:03.102-0500 [RUN 20260305-211001] [DEV ?] [TELNET] RX "TERMINAL SERVER"
2026-03-05T21:10:03.311-0500 [RUN 20260305-211001] [DEV ?] [TELNET] TX "<CRLF>"
2026-03-05T21:10:03.455-0500 [RUN 20260305-211001] [DEV ?] [TELNET] READY prompt="="
```

When the serial number becomes known, replace `DEV ?` with the real device serial.

---

## Log Levels

SelTool should support at least two log levels:

### Compact
Operationally useful events only.

Recommended for normal field use.

Typical Compact entries:
- connect/disconnect
- banners and prompts
- denial messages
- escalation attempts
- key parsed fields
- workflow milestones
- errors

### Full
Full protocol trace.

Recommended for development and difficult troubleshooting.

Typical Full entries:
- all Compact entries
- raw receive chunks
- more detailed FTP status output
- additional parser debugging

---

## Redaction Policy

Sensitive values must never be logged in plaintext.

At minimum, redact:

- `ACCPassword`
- `2ACPassword`
- `CALPassword`
- `FtpPassword`

Examples:

- log `Password:` prompts if useful
- do **not** log the real secret sent in response
- write `TX "<REDACTED_PASSWORD>"` instead

If future configuration files include additional secrets, they must be added to the redaction set.

---

## JSON History Relationship


## Per-device JSON relationship (serial.json)

Per-device history files (e.g., `data/devices/<serial>.json`, sometimes referred to as `serial.json`) should store **only structured facts about the relay over time** (inventory snapshots and change summaries).

They should **not** embed full Telnet/FTP transcripts. Full transcripts, retries, and detailed operational chatter belong in the per-run log file.

Each device event should include a `runId` and a `logRef` pointer back to the per-run log.



Per-device JSON history files should store structured facts, not full transcripts.

Each device event should include:
- event metadata
- parsed values
- result
- `RunId`
- reference to the run log

Recommended fields:

```json
{
  "runId": "20260305-211001",
  "logFile": "logs/run-20260305-211001.log",
  "logStartLine": 120,
  "logEndLine": 210
}
```

This allows:
- compact per-device history
- complete forensic traceability

---

## Line Number Tracking

The logger should track line numbers so JSON events can point into the run log without storing full transcripts.

Recommended approach:
- increment a line counter on each log write
- capture start/end lines for major operations such as:
  - inventory snapshot
  - re-IP
  - firmware upgrade

---

## What Must Be Logged

At minimum, log:

### Telnet
- connect
- banner received
- newline sent to elicit prompt
- prompt detected
- commands sent
- relevant responses
- disconnects
- access escalation attempts and results

### FTP
- connect
- target file name
- upload/download action
- status or result
- disconnect

### Parse
- serial discovered
- MAC discovered
- IP/mask/gateway discovered
- firmware identifiers discovered

### State
- operation start
- operation success
- operation failure
- verify/reconnect results

### Error
- exceptions
- timeouts
- invalid access level
- command unavailable
- front-panel remediation required

---

## Suggested Logger API

The implementation should provide a shared logger object created once per run.

Suggested capabilities:

- create `RunId`
- create/open log file
- write timestamped entries
- redact sensitive values
- track current line number
- attach device serial once known
- support Compact and Full modes

Example conceptual functions:

- `New-RunLogger`
- `Write-RunLog`
- `Start-OperationLogBlock`
- `End-OperationLogBlock`

Exact implementation is up to the codebase, but these responsibilities must exist.

---

## Future Enhancements

Possible later additions:

- JSONL structured run log
- log compression
- export run bundle (log + related device JSON files)
- configurable retention policy
