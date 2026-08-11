# CLI Install Documents CWD TCC

Status: **OPEN — recommended fix (v2)** · no code authorized until founder accepts  
Second opinion: DeepSeek V4 Pro run `995670FC` — **agree-with-amendments** (folded in below)  
Owner: CLI install / serve continuity (`install-cli`, `rebuild_cli.sh`, LaunchAgent)  
Created: 2026-08-11 · Updated: 2026-08-11 (v2)  
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

## Verdict

**Avoidable install-path footgun — not unavoidable OS tax on every CLI install.**

Separate from the open resident/project-Documents problem (real Team runs whose
`repoRoot` is under `~/Documents`). Do not conflate the two.

## Mechanism (corrected in v2)

The TCC trigger is **not** “`alln` read a file inside the checkout.” The
**foreground** `alln install-cli` process inherits a CWD under `~/Documents`.
On `exec`, or on filesystem syscalls that resolve that CWD (including
`getcwd` / `FileManager.default.currentDirectoryPath`), the kernel treats the
process as accessing a protected folder and prompts.

A foreground process whose CWD is under `~/Documents` can trigger this on
`exec` alone — code identity does **not** gate this prompt the way Full Disk
Access / Automation categories do. Even an identical binary would prompt when
started with a Documents CWD. (v1 overstated ad-hoc CDHash churn as the reason
prior “Allow” fails; strike that framing.)

The LaunchAgent plist’s `WorkingDirectory = ProbeScratch` only covers the
**daemon child** launched by `launchd`. It does **not** cover the foreground
install process that writes that plist.

## What already landed (and the hole)

| Mitigation | Status | Effect |
| --- | --- | --- |
| Build scratch outside Documents (`ALLNIGHTER_CLI_SCRATCH`) | Shipped | Binary image not born under Documents |
| Canonical home `~/.local/share/allnighter/bin/alln` | Shipped | PATH + serve share one install |
| Refuse Documents/Desktop/Downloads **candidates** | Shipped | `CanonicalCLIInstall.refusalReason` |
| LaunchAgent `WorkingDirectory = ProbeScratch` + minimal PATH | Shipped | **Daemon child only** — foreground `install-cli` is not covered by this plist key |
| ASR gate 6 “no protected prompt” | **Partial PASS** | Desktop/Downloads reset + empirical quiet; **Documents TCC never reset** (repo lives there) |

The remaining hole: `rebuild_cli.sh` builds outside Documents, then
`exec "$ALLN_BIN" install-cli` while the **shell CWD is still the Documents
checkout**. Foreground `alln` inherits that CWD.

## Trigger chain (code)

```text
rebuild_cli.sh          # CWD = Documents checkout
  → exec alln install-cli
    → CanonicalCLIInstall.install()
      → beforeBytesChange → ServeLifecycle.liveBootout  # spawn launchctl; inherits CWD
    → convergeServeAfterInstall()
      → ServeLifecycle().enable()                       # spawn launchctl bootstrap/verify; inherits CWD
```

Each `Process()` from a Documents CWD can independently surface the prompt.
No checkout file read is required.

Evidence anchors:
- `scripts/rebuild_cli.sh` (final `exec … install-cli`)
- `AllnighterCLI.swift` `runInstallCLI` / `beforeBytesChange` bootout /
  `convergeServeAfterInstall`
- `CanonicalCLIInstall.swift` `refusalReason` (candidate path only — not CWD)

## Truth owner / lie-prone layer

- **Truth owner:** process CWD of any foreground `alln` that runs install and
  serve enable — especially `rebuild_cli.sh` → `install-cli` →
  `beforeBytesChange` / `convergeServeAfterInstall`.
- **Lie-prone layer:** gate 6 PASS banner (Documents half waived); “binary not
  under Documents ⇒ no Documents TCC”; “LaunchAgent WorkingDirectory is set ⇒
  install is quiet.”

## Recommended fix (do this)

### S01 — Escape Documents CWD before any `alln` work in rebuild

In `scripts/rebuild_cli.sh`, after resolving `ALLN_BIN` and **before**
`install-cli`:

1. Ensure ProbeScratch exists
   (`~/Library/Application Support/Allnighter/ProbeScratch`).
2. `cd` there (or `$HOME` if ProbeScratch cannot be created).
3. Then run `"$ALLN_BIN" install-cli` (do not inherit the checkout CWD).

Same rule for any other script that exec’s a freshly built `alln` from a
Documents checkout. Cold-install fixture proof already isolates via scratch
`HOME` / `ALLN_INSTALL_DIR` (`scripts/test-get-alln.sh` — `assert_scratch_home`,
`HOME="$home_dir"`).

### S02 — Defense in depth inside `install-cli`

At the **top** of `runInstallCLI` (before `InstallCLI.run` / any serve work):

1. If `FileManager.default.currentDirectoryPath` resolves under
   `~/Documents`, `~/Desktop`, or `~/Downloads`, **chdir** to ProbeScratch
   (create if needed) before any further filesystem / serve work.
2. Optional disclosure (stderr, one line): escaped protected CWD → ProbeScratch.
3. Do **not** require FDA, entitlements, or “Allow” copy as the fix.

Placement requirement: chdir must happen **before** the `beforeBytesChange`
bootout closure (`AllnighterCLI.swift` ~2769) and **before**
`convergeServeAfterInstall` (~2805) spawns serve enable children. One chdir at
the top of `runInstallCLI` covers both.

### S03 — Re-close gate 6 for Documents

After S01/S02, re-measure the Documents half. Prefer a checkout **outside**
Documents so a Documents TCC reset does not brick the working tree session.

```bash
tccutil reset SystemPolicyDocumentsFolder
bash scripts/rebuild_cli.sh
alln serve status --json
# Expect: zero “alln” Documents prompts; serve healthy; canonical paths unchanged
```

Do not waive Documents again under a PASS banner.

### Non-goals

- Full Disk Access / broad TCC entitlements.
- Solving resident Team runs whose project root is under Documents (separate
  packet / harness).
- Moving the git checkout out of Documents as the only fix (nice for dogfood;
  not the product fix).
- Disabling default `install-cli` → serve enable to “avoid” TCC.
- Changing `ServeLifecycle` to chdir the daemon path (not needed — it already
  writes LaunchAgent `WorkingDirectory` to ProbeScratch; the hole is the
  **foreground** install process).

## Works Test

**WARNING:** Resetting `SystemPolicyDocumentsFolder` on a host where the git
checkout lives under `~/Documents` may brick the terminal session. Preferred
proof: disposable or permanent clone outside Documents (e.g. `~/src/Allnighter`).
That is the only low-risk empirical Documents reset path.

1. `tccutil reset SystemPolicyDocumentsFolder` (or host with no prior grant).
2. From a Documents checkout **or** after S01/S02, run `bash scripts/rebuild_cli.sh`
   (post-fix, Documents checkout must still be quiet because of chdir).
3. **No** Documents prompt attributed to `alln`.
4. `command -v alln` → canonical home; `alln serve status` healthy;
   LaunchAgent `WorkingDirectory` still ProbeScratch.
5. Unit/script proof: rebuild or install-cli path asserts post-chdir CWD is
   outside Documents/Desktop/Downloads (wall-reachable; not mock-only).

## Done when

- S01 + S02 landed.
- Gate 6 Documents half re-measured (empirical outside-Documents host or
  chdir-safe reset) and the waiver is removed or narrowed to a dated residual.
- This packet promoted/archived; durable note stays in operations debugger or
  serve install docs — not living law in `phases/`.

## Changelog

| Ver | Change |
| --- | --- |
| v1 | Initial recommended fix (inherited CWD + S01–S03). |
| v2 | DeepSeek V4 Pro (`995670FC`): correct TCC mechanism (CWD/`exec`, not CDHash); name full trigger chain including `beforeBytesChange` / `convergeServeAfterInstall`; foreground vs daemon LaunchAgent note; S02 placement requirement; cite `test-get-alln.sh`; Works Test operational warning; non-goal: no ServeLifecycle chdir. |
