# AGENTS (Instructions for Codex / agents)

## Mandatory reading before coding
- PROJECT_CONTEXT.md
- DECISIONS.md
- BACKLOG.md

## Coding conventions
- Target Windows PowerShell 5.1; avoid PS7-only features.
- Clarity > cleverness; prefer small functions.
- Main module is `src/SelTools/SelTools.psm1`; CLI entrypoint is `seltools.ps1`.
- Return structured objects (pscustomobject) rather than strings.
- SEL-751 Ethernet naming must be consistent:
  - `SET P 1` = Port 1 Ethernet group scope
  - physical interfaces = `1A`, `1B`
  - config selector = `NETPORT` `A|B`
  - status fields use `1A|1B`
- Prefer normalized fields in persistence:
  - `primaryInterface` / `activeInterface` in `1A|1B`
  - `configuredPrimarySelector` in `A|B`
- Preserve compatibility aliases when practical (`primaryPort`, `activePort`) for existing readers.

## Safety requirements
- If C escalation fails: close session; output remediation steps. 
- Verify identity by Serial before and after re-IP and upgrades.

## Tests
- Add/update Pester tests for parser behavior, argument/input precedence, and CLI helper/dispatch behavior.

## PR format
- Summarize changes
- List tests run
- Note any new safety implications
