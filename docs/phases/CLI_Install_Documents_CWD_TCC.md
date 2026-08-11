# CLI Install Documents CWD TCC

Status: **OPEN — implementation-ready (v3)** · no code until founder accepts  
Reviews: DeepSeek V4 Pro `995670FC` (v2) · Composer 2.5 `58EF327B` (adversarial final — gems below)  
Owner: CLI install / serve continuity  
Created: 2026-08-11 · Updated: 2026-08-11 (v3)  
Related: archived `Launch_Authority_TCC_Hotfix.md`,
`docs/operations/debugger/2026-07-24-resident-run-tcc-PACKET.md`,
`docs/qa/alln-serve/2026-08-11-gate6-tcc-no-protected-prompt.md`,
archived `Alln_Serve_Hotfixes.md` §3 / gate 6

## Symptom

`bash scripts/rebuild_cli.sh` from `~/Documents/GitHub/Allnighter` → macOS:

> “alln” would like to access files in your Documents folder.

Attributed to **`alln`**, not `Allnighter.app`.

## First principles

1. Documents TCC fires when a process **touches** a protected folder (CWD
   resolve, `getcwd`, relative opens, spawn inheritance)—not because the
   binary was built nearby or the LaunchAgent plist looks correct.
2. `rebuild_cli.sh` builds outside Documents, then `exec`s `install-cli`
   with the shell still in the Documents checkout → foreground `alln`
   inherits that CWD.
3. `ServeLifecycle` live `launchctl` helpers use `Process()` **without**
   `currentDirectoryURL` (unlike `CapacityPaneReader` / probe paths that
   already set ProbeScratch) → children inherit the same CWD.
4. Daemon child is already fine (`WorkingDirectory = ProbeScratch` in
   plist). The bug is the **foreground** install/enable process and its
   immediate children.
5. Separate from resident Team runs whose `repoRoot` is under Documents.

Amplifier (not root cause): uninstall + fresh ad-hoc-signed `alln` can be a
**new TCC client** with no prior consent row; first protected-folder touch
surfaces the dialog.

## What already landed / what lies

| Mitigation | Covers | Does not cover |
| --- | --- | --- |
| Scratch build + canonical `~/.local/share/.../alln` | Binary location | Inherited CWD |
| Refuse Documents **candidates** | Installing a binary that *lives* under Documents | Running install *from* a Documents CWD |
| LaunchAgent `WorkingDirectory` | Daemon child only | Foreground `install-cli` / `serve enable` |
| Gate 6 Desktop/Downloads reset | Those two folders | **Documents** (never reset). Gate 6 evidence §2 (string grep for “Documents”) is **void for CWD safety** |

## Entry-point matrix

| Entry | Today | Fixed by |
| --- | --- | --- |
| `rebuild_cli.sh` → `install-cli` | Documents CWD | **P1** (required) + **P0** optional belt |
| `alln install-cli` from Cursor/agent in repo | Documents CWD | **P1** |
| `alln serve enable\|repair\|disable` from Documents CWD | Same unguarded `Process()` | **P1** (must cover serve-mutate, not only install-cli) |
| `get-alln.sh` / `curl \| sh` from Documents terminal | No CWD escape | **P1** |
| `check-fast.sh` auto-heal → `rebuild_cli` | Same as rebuild | **P1** / **P0** |
| `alln run` with `repoRoot` under Documents | By design | **Out of scope** (resident packet) |

## Implementation plan (one owner)

### P1 — Product seam (required, single owner)

Add one shared helper (reuse `AllnighterPaths.ensuredProbeScratchPath()` —
do **not** hardcode ProbeScratch a third time) that escapes
Documents/Desktop/Downloads CWD before any install or serve-mutate work.

Call it at the top of:

- `runInstallCLI` — **before** `InstallCLI.run` / `beforeBytesChange` /
  `convergeServeAfterInstall`
- `serve enable` / `repair` / `disable` handlers — **before**
  `ServeLifecycle().enable()` / `repair()` / `disable()`

**Acceptable alternative (narrower):** set
`process.currentDirectoryURL = ProbeScratch` on the three
`ServeLifecycle` live `Process()` sites only (`liveBootout` /
`liveBootstrap` / `liveVerifyJobLoaded`), matching `CapacityPaneReader`.
Use this **only if** proven that the parent never resolves protected CWD
before the first spawn; otherwise prefer the shared escape helper (covers
parent `getcwd` too).

Do **not** ship both P1 variants as mandatory. Pick one; the other is
optional belt if a residual is measured.

### P0 — Dogfood script belt (optional, not paired mandatory)

In `scripts/rebuild_cli.sh`, `cd` to ProbeScratch (create via same path
helper / mkdir) **before** `exec … install-cli`. Cheap contract for agents
reading the script. **Not required** if P1 covers all `install-cli`
entry points.

### Cut from v2 (do not implement)

- Mandatory dual S01+S02 for the same hop
- Optional stderr “escaped CWD” disclosure as a slice requirement
- S03 / gate 6 Documents re-close as a **blocking** promote item
- Global chdir in `AllnighterCLI.main` (breaks intentional repo-scoped
  `alln run` / `ps`)

### Founder host measurement (non-blocking)

Outside-Documents clone + `tccutil reset SystemPolicyDocumentsFolder` +
`rebuild_cli` / `install-cli` with **zero** Documents prompt. Record as
empirical closure; do **not** require Documents reset on the dogfood
Documents checkout (bricks the session). Do **not** treat gate 6 grep or
daemon plist inspection as Documents TCC proof.

## Works Test (split claims)

**Structural (CI / agent wall — required):**

1. After P1, before first `launchctl` spawn on install / serve-enable path,
   process CWD is outside Documents/Desktop/Downloads **or** injected
   `Process` seam asserts `currentDirectoryURL == ProbeScratch`.
2. Unit coverage of the shared helper / seam (wall-reachable; fail if
   protected CWD left in place).

**Empirical (founder-only, non-blocking):**

3. Outside-Documents host (or safe Documents reset) → no “alln” Documents
   prompt on `rebuild_cli` / `install-cli` / `serve enable`.
4. Canonical paths + serve healthy unchanged.

Do **not** label (1)/(2) as “no TCC prompt” proof.

## Non-goals

- FDA / entitlements / “click Allow” copy
- Resident `repoRoot` under Documents
- Move git checkout as the only fix
- Disable default `install-cli → serve enable` to avoid TCC
- Treat Desktop/Downloads as this slice’s symptom (Documents is the
  measured dogfood bug; shared helper may include all three for reuse)

## Done when

- **P1** landed with one clear owner (escape helper **or** ServeLifecycle
  `currentDirectoryURL` — not both mandatory).
- Entry-point matrix rows for install-cli + serve-mutate are green under
  structural Works Test.
- Gate 6 Documents banner narrowed: Desktop/Downloads only until founder
  empirical row lands (optional).
- Packet archived after promote; durable note → operations debugger /
  serve install docs.

## Changelog

| Ver | Change |
| --- | --- |
| v1 | Inherited CWD diagnosis; dual S01/S02 + gate 6 re-close. |
| v2 | DeepSeek: CWD/`exec` framing over CDHash; trigger chain; foreground vs daemon. |
| v3 | Composer 2.5 (`58EF327B`) gems: first-principles restatement; drop “exec alone” / dual mandatory; one product owner (install **and** serve-mutate); optional rebuild `cd` only; entry-point matrix; void gate 6 grep for Documents; split structural vs empirical Works Test; reuse `ensuredProbeScratchPath`; demote Documents reset to founder-only; note fresh ad-hoc identity as amplifier. |
