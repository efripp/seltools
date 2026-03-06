
# TELNET_PROTOCOL

Generated: 2026-03-05T23:14:48.647679

---

# Scope

Defines the Telnet behaviors and parsing assumptions used by SelTools when interacting with SEL relays (starting with SEL‑751).

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
| STA | ACC |
| ETH | ACC |

Inventory sequence:

ID  
ACC  
STA  
ETH

If ACC fails, record **ID only**.

---

# Interactive Dialogs (SET P 1)

Commands such as `SET P 1` enter an interactive configuration dialog.

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

After saving a new IP address via `SET P 1`, the relay will terminate the Telnet connection.

This is expected behavior.

Tool logic:

1. Detect connection drop.
2. Wait briefly.
3. Reconnect to the new IP.
4. Verify device identity using Serial.
