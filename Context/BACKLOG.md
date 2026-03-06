# BACKLOG

## Done
- Drafted module spec + safety policies

## In progress
- Scaffold module + CLI entrypoint

## Next
### 1) CLI scaffolding
**Acceptance:** `seltool.ps1` supports subcommands and prompts when args missing.
**Blockers:** none

### 2) TelnetSession class (MVP)
**Acceptance:** Connect/Send/ReadUntil works; handles basic IAC stripping.
**Blockers:** none

### 3) Ensure-SelAccessC (stub)
**Acceptance:** Function exists; logs/returns structured result; prompt regex TBD.
**Blockers:** need a clean 2AC→C transcript to finalize success detection (if C is required on some units).

### 4) Invoke-SelReIp (stub → working)
**Acceptance:** Runs flow; SET P 1 prompt handling TBD until capture.
**Blockers:** none

### 5) Invoke-SelFirmwareUpgrade (stub → working)
**Acceptance:** FTP upload path implemented; verify reconnect + ID compare.
**Blockers:** need confirmation of target directory/filename behavior on device