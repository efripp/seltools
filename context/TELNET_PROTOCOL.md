
# TELNET_PROTOCOL

Generated: 2026-03-05T23:14:48.647679

---

# Scope

Defines the Telnet behaviors and parsing assumptions used by SelTools when interacting with SEL relays (starting with SEL‑751).
Runtime transport is implemented via bundled `tools/plink.exe` in telnet mode.

---

# Initial Telnet Session Behavior

When connecting to an SEL relay via Telnet (TCP port 23), the device **does not present a login prompt**.

Instead, the relay sends an optional **connect banner**, then waits for input.

Example:

TERMINAL SERVER

This text is configured by the Port setting:

TCBAN := TERMINAL SERVER

After the banner appears, the relay **does not immediately display a prompt**.
The client must send a newline to receive the prompt.

Example interaction:

(connect)

TERMINAL SERVER
<client sends newline>

=

---

# Prompt Tokens

The prompt character indicates the current access level.

| Prompt | Access Level | Meaning |
|------|------|------|
| `=` | Base | Non‑privileged command access |
| `=>` | Level 1 | ACC access |
| `=>>` | Level 2 | 2AC access |

---

# Session Initialization Procedure

After establishing the TCP connection, the tool should:

1. Read any banner text.
2. Send a newline (`\r\n`) to elicit the prompt.
3. Wait for a prompt token (`=`, `=>`, or `=>>`).
4. Begin command execution.

Pseudo‑flow:

connect tcp 23  
read banner  
send newline  
read until prompt (=|=>|=>>)

---

# Access Escalation

Access is **command‑based escalation**, not session authentication.

Typical escalation sequence:

= ACC  
Password: *****

=>

=> 2AC  
Password: *****

=>>

The tool should escalate **only when required** for an operation.

---

# Denial Signatures

Common denial outputs:

| Output | Meaning |
|------|------|
| `Invalid Access Level` | insufficient privileges |
| `Command Unavailable` | feature disabled |
| `Command Unavailablewith ACC access level` | command requires higher access |

These signals should trigger escalation or safe abort depending on the operation.

---

# Inventory Command Access

Confirmed via transcript:

| Command | Access |
|------|------|
| ID | Base |
| SER | ACC |
| ETH | ACC |

Inventory sequence:

ID  
ACC  
SER  
ETH

If ACC fails, record **ID only**.

Compatibility note: persisted inventory payloads may still include `STA` key for historical readers; current live capture command is `SER`.

---

# Interactive Dialogs (SET P 1)

Commands such as `SET P 1` enter an interactive configuration dialog.

Port/interface terminology for SEL-751:

- `SET P 1` configures **Port 1** (Ethernet group scope).
- Physical interfaces under Port 1 are **Port 1A** and **Port 1B**.
- Config dialog fields use selector values `A`/`B` (for example `NETPORT := A`).
- Status output (`ETH`) reports `1A`/`1B` values (for example `PRIMARY PORT: 1A`).

The tool should detect field prompts containing `:=` and ending with `?`.

Example:

IPADDR  := 192.168.1.2
?

Behavior:

- Send a **new value** for fields being modified.
- Send an **empty newline** to accept existing value.

Minimum fields required for re‑IP:

| Field | Meaning |
|------|------|
| `IPADDR` | IP address |
| `SUBNETM` | Subnet mask |
| `DEFRTR` | Default gateway |

Optional fields:

| Field | Meaning |
|------|------|
| `EETHFWU` | Enable Ethernet firmware upgrade |
| `MAXACC` | Maximum Telnet access level |
| `NETMODE` | Ethernet mode (`FIXED`/`FAILOVER`/`SWITCHED`/`PRP` etc.) |
| `NETPORT` | Configured primary interface selector (`A` or `B`) |

Interface gotchas:

- `SET P 1` alone does not choose A/B.
- `NETPORT` determines configured primary side.
- `ETH` reflects runtime state; `ACTIVE PORT` can differ from configured primary during failover.

Scripting guidance:

1. Use `ETH` to read runtime interface state (`PRIMARY PORT`, `ACTIVE PORT`, `PORT 1A`, `PORT 1B`).
2. Use `SET P 1` to configure Ethernet group fields.
3. Use `NETPORT` to select preferred primary side.
4. Preserve configured and runtime interface values as separate fields in persistence.

---

# Control Character Stripping

PuTTY logs and Telnet streams include control characters such as:

\x02
\x03

These must be stripped before parsing.

Example:

$clean = $text -replace "[\x00-\x1F]", ""

---

# Connection Drop Handling

Observed transcript detail:

- The save prompt is `Save changes (Y,N)?`
- The relay reports `Settings Saved`
- PuTTY logs may still show trailing prompt text after save

Operational interpretation:

- After saving a new IP address via `SET P 1`, treat the live Telnet session as effectively terminated immediately, even if PuTTY logs captured trailing text or an apparent returned prompt.
- `Settings Saved` plus a logged prompt is not reliable evidence that the session remained usable.
- The relay does not appear to reboot when the IP is changed; behavior is consistent with a near-instant network/session cutover to the new IP.

Tool logic:

1. Treat save as the end of the usable session.
2. Begin reconnect attempts to the new IP almost immediately.
3. Keep a short settle window / retry loop only as a safety margin, not as a reboot wait.
4. Verify device identity using Serial.
