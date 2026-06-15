# Code Maintainer Deep-Read Ledger

Lens 7 uses this ledger to pick the stalest area for consistency deep-reads.
`Last deep-read: never` means no dedicated pass has run yet.

| Beat | Last deep-read | Last batch | Notes |
| --- | --- | --- | --- |
| `Packages/AllnighterCore` models + engine | never | - | Shared types, Codable, council/worker orchestration |
| `Packages/AllnighterCore` CLI tools | never | - | ProveCLI, AllnighterCLI entry points |
| `Apps/AllnighterMac` orchestration | never | - | App shell, council UI, driver configs |
| `Apps/AllnighterMac` UI | never | - | Dashboard, menu bar, session views |
| `Allnighter/` iOS scaffold | never | - | Transitional; replace with `Apps/AllnighteriOS/` |
| `docs/mvp` + `docs/phases` contracts | never | - | Contract vs planned code alignment |
| `scripts/` proof + handoff | never | - | check.sh, commit queue, future gates |
