# DECISIONS (ADR)

## ADR-0001: Use PowerShell + built-in .NET only
**Decision:** Implement telnet/ftp using TcpClient and FtpWebRequest.  
**Alternatives:** NuGet telnet libs, external telnet.exe, Python.  
**Reason:** No dependencies; auditable; works on locked-down laptops.  
**Consequence:** Must implement prompt matching and minimal telnet negotiation.

## ADR-0002: Serial number is authoritative identity
**Decision:** Use Serial as primary key; MAC used as warning/advisory.  
**Alternatives:** MAC as primary key.  
**Reason:** Dual Ethernet ports can yield MAC mismatches.  
**Consequence:** Always capture serial before/after changes.

## ADR-0003: Fail-fast on C escalation failure
**Decision:** If C required and cannot be obtained, close session and instruct front-panel remediation.  
**Reason:** Prevent partial/unsafe operations.  
**Consequence:** Bulk workflows must handle skips and report clearly.