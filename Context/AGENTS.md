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

## Safety requirements
- If C escalation fails: close session; output remediation steps. 
- Verify identity by Serial before and after re-IP and upgrades.

## Tests
- Add/update Pester tests for parser behavior, argument/input precedence, and CLI helper/dispatch behavior.

## PR format
- Summarize changes
- List tests run
- Note any new safety implications
