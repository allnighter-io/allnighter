# CLI Install Documents CWD TCC

Status: **OPEN — recommended fix (v1)** · no code authorized until founder accepts
Owner: CLI install / serve continuity (`install-cli`, `rebuild_cli.sh`, LaunchAgent)
Created: 2026-08-11
Related: archived `Launch_Authority_TCC_Hotfix.md`,
`docs/operations/debugger/2026-07-24-resident-run-tcc-PACKET.md`,
`docs/qa/alln-serve/2026-08-11-gate6-tcc-no-protected-prompt.md`,
archived `Alln_Serve_Hotfixes.md` §3 / gate 6

## Symptom

After `scripts/uninstall-allnighter.sh` + `scripts/rebuild_cli.sh` (CLI-only
reinstall), macOS shows:

> “alln” would like to access files in your Documents folder.

Attributed to **`alln`**, not `Allnighter.app`. Dogfood checkout lives at
`~/Documents/GitHub/Allnighter`.

## Verdict (v1)

**Avoidable install-path footgun — not unavoidable OS tax on every CLI install.**

Separate from the open resident/project-Documents problem (real Team runs whose
`repoRoot` is under `~/Documents`). Do not conflate the two.

## What already landed (and the hole)

| Mitigation | Status | Effect |
| --- | --- | --- |
| Build scratch outside Documents (`ALLNIGHTER_CLI_SCRATCH`) | Shipped | Binary image not born under Documents |
| Canonical home `~/.local/share/allnighter/bin/alln` | Shipped | PATH + serve share one install |
| Refuse Documents/Desktop/Downloads **candidates** | Shipped | `CanonicalCLIInstall.refusalReason` |
| LaunchAgent `WorkingDirectory = ProbeScratch` + minimal PATH | Shipped | Daemon start is protected-folder-clean |
| ASR gate 6 “no protected prompt” | **Partial PASS** | Desktop/Downloads reset + empirical quiet; **Documents TCC never reset** (repo lives there) |

The remaining hole: `rebuild_cli.sh` builds outside Documents, then
`exec "$ALLN_BIN" install-cli` while the **shell CWD is still the Documents
checkout**. Foreground `alln` inherits that CWD. Ad-hoc signing gives a **new
CDHash every rebuild**, so prior Documents “Allow” often does not stick.

Serve’s LaunchAgent on this host is already correct
(`WorkingDirectory` → Application Support `ProbeScratch`). The install-time
process is not.

## Truth owner / lie-prone layer

- **Truth owner:** process CWD + code identity of any `alln` that runs before /
  during install and serve enable — especially `scripts/rebuild_cli.sh` →
  `alln install-cli` → `convergeServeAfterInstall`.
- **Lie-prone layer:** gate 6 PASS banner (Documents half waived); “binary not
  under Documents ⇒ no Documents TCC”; green LaunchAgent plist alone.

## Recommended fix (do this)

### S01 — Escape Documents CWD before any `alln` work in rebuild

In `scripts/rebuild_cli.sh`, after resolving `ALLN_BIN` and **before**
`install-cli`:

1. Ensure ProbeScratch exists
   (`~/Library/Application Support/Allnighter/ProbeScratch`).
2. `cd` there (or `$HOME` if ProbeScratch cannot be created).
3. Then run `"$ALLN_BIN" install-cli` (do not inherit the checkout CWD).

Same rule for any other script that exec’s a freshly built `alln` from a
Documents checkout (`get-alln` fixture runners already use scratch HOMEs).

### S02 — Defense in depth inside `install-cli`

At the start of `runInstallCLI` (or `InstallCLI.run` / serve converge entry):

1. If `FileManager.default.currentDirectoryPath` resolves under
   `~/Documents`, `~/Desktop`, or `~/Downloads`, **chdir** to ProbeScratch
   (create if needed) before any further filesystem / serve work.
2. Optional disclosure (stderr, one line): escaped protected CWD → ProbeScratch.
3. Do **not** require FDA, entitlements, or “Allow” copy as the fix.

### S03 — Re-close gate 6 for Documents

After S01/S02:

```bash
# Prefer: chdir-first so Documents reset does not brick the checkout session
tccutil reset SystemPolicyDocumentsFolder
bash scripts/rebuild_cli.sh
alln serve status --json
# Expect: zero “alln” Documents prompts; serve healthy; canonical paths unchanged
```

If Documents reset is still operationally unsafe on this host, run the same
proof on a checkout **outside** Documents. Record the empirical half; do not
waive it again under a PASS banner.

### Non-goals

- Full Disk Access / broad TCC entitlements.
- Solving resident Team runs whose project root is under Documents (separate
  packet / harness).
- Moving the git checkout out of Documents as the only fix (nice for dogfood;
  not the product fix).
- Disabling default `install-cli` → serve enable to “avoid” TCC.

## Works Test

1. `tccutil reset SystemPolicyDocumentsFolder` (or host with no prior grant).
2. From `~/Documents/GitHub/Allnighter`, run `bash scripts/rebuild_cli.sh`.
3. **No** Documents prompt attributed to `alln`.
4. `command -v alln` → canonical home; `alln serve status` healthy;
   LaunchAgent `WorkingDirectory` still ProbeScratch.
5. Unit/script proof: rebuild or install-cli path asserts post-chdir CWD is
   outside Documents/Desktop/Downloads (wall-reachable; not mock-only).

## Done when

- S01 + S02 landed.
- Gate 6 Documents half re-measured (empirical or explicit host-outside-Documents
  proof) and the waiver is removed or narrowed to a dated residual.
- This packet promoted/archived; durable note stays in operations debugger or
  serve install docs — not living law in `phases/`.
