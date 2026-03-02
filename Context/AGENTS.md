# AGENTS (Instructions for Codex / agents)

## Mandatory reading before coding
- PROJECT_CONTEXT.md
- DECISIONS.md
- BACKLOG.md

## Coding conventions
- PowerShell 7+ compatible, but avoid PS7-only features unless needed.
- Clarity > cleverness; prefer small functions.
- Public functions in src/SelTool/Public; internal helpers in Private.
- Return structured objects (pscustomobject) rather than strings.

## Safety requirements
- Never perform destructive ops unless Access C is confirmed.
- If C escalation fails: close session; output remediation steps.
- Verify identity by Serial before and after re-IP and upgrades.

## Tests
- Add Pester tests for parsing functions and argument handling.
- No tests should require network access; use saved transcripts.

## PR format
- Summarize changes
- List tests run
- Note any new safety implications