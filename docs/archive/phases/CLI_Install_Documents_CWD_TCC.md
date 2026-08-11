# CLI Install Documents CWD TCC

Status: **Complete** · archived 2026-08-11  
Shipped: `b65a2ea2` (`ProtectedCWDEscape` + CLI call sites + `rebuild_cli` belt)  
Reviews: DeepSeek V4 Pro `995670FC` · Composer 2.5 audit `58EF327B` · implementer `477B272A`  
Owner (runtime): `ProtectedCWDEscape` · `AllnighterCLI` install/serve-mutate · `scripts/rebuild_cli.sh`  
Durable note: `docs/operations/debugger/2026-08-11-cli-install-documents-cwd-tcc.md`

## Symptom (historical)

`bash scripts/rebuild_cli.sh` from `~/Documents/GitHub/Allnighter` → macOS:

> “alln” would like to access files in your Documents folder.

Attributed to **`alln`**, not `Allnighter.app`.

## What shipped

**P1 (product owner):** `ProtectedCWDEscape` escapes Documents/Desktop/Downloads
cwd to `AllnighterPaths.ensuredProbeScratchPath()` (home fallback). Called at
the top of `runInstallCLI`, `runServeEnable`, `runServeRepair`, `runServeDisable`.
ServeLifecycle `currentDirectoryURL` left untouched (one owner).

**P0 (dogfood belt):** `rebuild_cli.sh` `cd`s to ProbeScratch before
`exec install-cli`.

**Structural proof:** `scripts/swift-test.sh --filter ProtectedCWDEscapeTests`
(12/12).

**Empirical Documents no-prompt** after `tccutil reset SystemPolicyDocumentsFolder`
remains founder-only / non-blocking (Documents-hosted checkout bricks on reset).
Gate 6 Desktop/Downloads PASS stands; Documents string-grep evidence stays void
for CWD safety.

## Non-goals (unchanged)

Resident `repoRoot` under Documents; FDA; global main chdir; disable serve-on-install.

## Done when (checked)

- [x] P1 landed — one owner (`ProtectedCWDEscape`)
- [x] Structural Works Test green
- [x] Durable debugger note
- [x] Packet archived; phases board row removed
