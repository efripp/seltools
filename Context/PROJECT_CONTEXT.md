# PROJECT_CONTEXT

## Product goals
- Automate SEL relay commissioning tasks over Ethernet:
  - Single device re-IP (Port 1)
  - Single device firmware upgrade
- Support both interactive use (prompts) and automation (CLI args).
- Maintainability and auditability over cleverness.

## Non-goals (for now)
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
- Some operations require Access Level C (via 2AC then C)
- Telnet MAXACC may block C escalation; remediation is front-panel changes

## Glossary / domain terms
- Default IP: factory IP (often 192.168.x.x)
- Access levels: ACC, 2AC, C, CAL
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
- `seltool.ps1 reip` can set IP/mask/gw and verify by reconnecting
- `seltool.ps1 upgrade` can FTP PUT firmware file and verify FID change
- Both support interactive prompts if args missing
- Basic tests for parsing and argument handling