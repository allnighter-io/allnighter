# Code Maintainer Deep-Read Ledger

Lens 7 uses this ledger to pick the stalest area for consistency deep-reads.
`Last deep-read: never` means no dedicated pass has run yet.

| Beat | Last deep-read | Last batch | Notes |
| --- | --- | --- | --- |
| `Packages/CLILociCore` models + parsers | never | - | Shared types, Codable, output parsers |
| `Packages/CLILociCore` protocol | never | - | WebSocket message types and serialization |
| `Apps/CLILociMac` orchestration | never | - | PTY, process spawn, session store |
| `Apps/CLILociMac` UI | never | - | Dashboard, menu bar, session views |
| `Apps/CLILociIOS` remote | never | - | WebSocket client, session UI, haptics |
| `Docs/product` contracts | never | - | Contract vs planned code alignment |
| `scripts/` proof + handoff | never | - | check.sh, commit queue, future gates |
