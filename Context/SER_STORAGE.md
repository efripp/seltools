# SER_STORAGE

Generated: 2026-03-08T23:42:23.146489

## Scope

Defines how SelTool stores and organizes **SER (Sequence of Events Recorder)** data pulled from SEL relays.

SER data is a chronological event stream and must be stored separately from per-device configuration/change history.

---

## Design Principle

Use separate storage for:

- **Configuration / device history**
- **SER event history**
- **Run logs / raw operational transcripts**

This avoids mixing:
- relay identity and change history
- operational event streams
- verbose logs and transcripts

---

## Storage Model

### Per-device configuration history

Stored in:

- `data/devices/<serial>.json`

Purpose:
- inventory snapshots
- observed network state
- re-IP history
- firmware upgrade history
- references to related logs and SER pulls

This file should remain clean and relatively small.

### Per-device SER event stream

Stored in:

- `data/events/<serial>/ser.jsonl`

Purpose:
- parsed SER event records
- append-only chronological event history
- search/filter/comparison source for future tools

### Raw SER archives

Stored in:

- `data/events/<serial>/<timestamp>-ser.txt`

Purpose:
- preserve original pulled SER text
- provide audit/troubleshooting source
- allow parser improvements later without losing source data

---

## Recommended Directory Layout

```text
data/
  devices/
    3241995707.json
  events/
    3241995707/
      ser.jsonl
      2026-03-05T17-45-00-ser.txt
      2026-03-06T08-10-12-ser.txt
```

---

## Why SER should not live inside serial.json

`serial.json` is intended to store **facts about the relay over time**, such as:

- identity snapshots
- network settings observed
- firmware changes
- re-IP operations
- structured summaries of significant actions

SER is different:

- it is an event stream
- it can grow quickly
- it is chronological rather than configuration-focused
- it is better treated like operational telemetry

Mixing SER into `serial.json` would make that file:
- noisy
- difficult to search
- harder to compare for configuration drift
- expensive to load over time

---

## ser.jsonl format

Use **JSON Lines** (one JSON object per line).

Why:
- naturally append-only
- easy to process incrementally
- easy to search/filter
- large files remain manageable
- a future web UI can stream/load it efficiently

Each line should represent one parsed SER event.

Example:

```json
{"ts":"2026-03-05T17:42:11-05:00","serial":"3241995707","source":"SER","event":"BREAKER OPEN","raw":"BREAKER OPEN ...","runId":"20260305-174000"}
```

---

## Minimum parsed fields for each SER event

Recommended fields:

- `ts` — timestamp of the event (if available)
- `serial` — authoritative relay serial number
- `source` — `"SER"`
- `event` — parsed event name/message
- `state` — asserted/deasserted or equivalent if available
- `code` — event code if available
- `raw` — original raw SER line
- `runId` — run/session identifier that collected the event
- `rawArchive` — path to the raw archive file that contained this event (optional)

Not all SEL outputs will provide all fields; missing values are acceptable.

---

## Raw archive files

When SER is pulled from the relay, store the raw text in a timestamped file:

- `data/events/<serial>/<timestamp>-ser.txt`

Example:

- `data/events/3241995707/2026-03-05T17-45-00-ser.txt`

This gives the project:
- an immutable source record
- the ability to re-parse later
- a simple audit trail

---

## Relationship to serial.json

Do **not** store all SER events in `data/devices/<serial>.json`.

Instead, store only a summary/reference event such as:

```json
{
  "timestamp": "2026-03-05T17:45:00-05:00",
  "event": "ser-pull",
  "result": "success",
  "entriesAdded": 42,
  "eventStore": "data/events/3241995707/ser.jsonl",
  "rawArchive": "data/events/3241995707/2026-03-05T17-45-00-ser.txt",
  "runId": "20260305-174000"
}
```

This keeps `serial.json` clean while still preserving traceability.

---

## Logging relationship

The **run log** remains the authoritative transcript of tool activity.

The run log should record:
- command used to pull SER
- whether pull succeeded or failed
- parser success/failure summary
- number of entries written
- references to raw archive and JSONL file

The per-device history file (`serial.json`) should only store the structured summary/reference event.

---

## Future UI implications

This model supports a future browser-based UI cleanly.

Suggested UI split:

- **Configuration History** tab → reads `data/devices/<serial>.json`
- **SER Events** tab → reads `data/events/<serial>/ser.jsonl`
- **Raw SER Archive** link → opens the corresponding `*-ser.txt` file

---

## Retention and growth

SER data may grow significantly over time.

Future enhancements may include:
- rotating raw SER archives by date
- compacting or deduplicating parsed JSONL
- indexing events for faster search
- retention policies for very old SER data

These are future concerns and are not required for v0.1.

---

## Summary

Recommended storage model:

- `data/devices/<serial>.json`  
  structured relay history and change facts

- `data/events/<serial>/ser.jsonl`  
  parsed append-only SER event stream

- `data/events/<serial>/<timestamp>-ser.txt`  
  raw SER archive files

This keeps the project organized, scalable, and ready for future search/browse/compare tools.
