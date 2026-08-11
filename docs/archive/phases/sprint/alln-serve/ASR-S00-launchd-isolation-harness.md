# ASR-S00 — native launchd isolation harness

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §8 ASR-S00,
§4.5 (code identity), §4.6 (signing tracks), §4.2 (restart contract).

## 1. Goal

Prove — on this real Mac, with a disposable non-product launchd label — whether a
per-user LaunchAgent survives replacement of its executable's bytes when the code
identity (cdhash) changes, and whether `KeepAlive = { SuccessfulExit = false }`
behaves as the packet's restart contract assumes. **No product lifecycle code is
edited in this slice.**

## 2. Copy-paste prompt

> Build a disposable native launchd harness under `tools/ServeLaunchdHarness/`
> that answers the code-identity and restart-contract questions in the Steps
> below. Model the file layout and safety posture on the existing
> `tools/TCCProjectAccessHarness/` (read it first). Write no product code, touch
> no Swift package, and never touch the label
> `com.allnighter.resident-coordinator`. Then run it and record the results.

## 3. Read only

- `tools/TCCProjectAccessHarness/run.sh` + `main.swift` + `README.md` — style,
  safety posture, receipt shape, cleanup trap.
- `docs/qa/serve-continuity/SC-S04-same-session-keepalive.md` — prior evidence
  format for a launchd experiment record.
- `scripts/build-universal.sh` (lines 1–40 only) — the ad-hoc `codesign --sign -`
  reality this experiment contrasts against.

## 4. Touch only

```text
tools/ServeLaunchdHarness/run.sh          (new)
tools/ServeLaunchdHarness/main.swift      (new)
tools/ServeLaunchdHarness/README.md       (new)
docs/qa/alln-serve/ASR-S00-code-identity-matrix.md   (new, results)
```

## 5. Do not read / do not touch

- Do **not** touch `Packages/`, `Apps/`, `scripts/`, or any existing file.
- Do **not** read `AGENTS.md`, the phase board, or driver docs.
- Do **not** call `launchctl` against `com.allnighter.resident-coordinator`,
  `alln serve`, `alln install-cli`, `tccutil`, or any vendor CLI.
- Do **not** write anywhere outside
  `~/Library/Developer/Allnighter/ServeLaunchdHarness/` and the four files above.

## 6. Steps

1. **Helper (`main.swift`).** A tiny `@main` executable, zero Allnighter imports.
   It writes a JSON heartbeat every second to a path given as argv[1]:
   `{schemaVersion, pid, startedAt, beatAt, beatCount, cdhash, argv0, cwd, path}`
   — `cdhash` read by shelling to `codesign -dvvv` on its own executable path,
   `path` is `$PATH` as inherited. It accepts a second argv: `run` (beat
   forever), `exit-zero` (write one beat, exit `0`), `exit-nonzero` (write one
   beat, exit `3`). It never forks or daemonizes.

2. **Harness (`run.sh`).** Label `com.allnighter.serve-launchd-harness`, root
   `${ALLN_SERVE_HARNESS_ROOT:-$HOME/Library/Developer/Allnighter/ServeLaunchdHarness}`.
   A `cleanup` trap boots out the label and removes the plist on every exit path.
   The generated plist must use `RunAtLoad = true`,
   `KeepAlive = { SuccessfulExit = false }` (dictionary, **not** the bare
   boolean), `ThrottleInterval = 10` (shorter than product's 30 so the matrix
   finishes), `ProcessType = Background`, `WorkingDirectory` at a neutral
   `$ROOT/cwd` directory, and `StandardOutPath`/`StandardErrorPath` under
   `$ROOT/logs/`. `PATH` in the plist environment contains only `$ROOT/bin`,
   `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`.

3. **Build two distinct binaries per signing track.** Compile `main.swift` twice
   with a differing embedded build tag (e.g. `-DBUILD_TAG_A` / `-DBUILD_TAG_B`, or
   simply append a differing comment before compiling) so the bytes truly differ,
   then sign each. Verify with `codesign -dvvv` that the two cdhashes are
   **different** and fail loudly if they are not. Signing tracks, selected by
   `--track`:

   | `--track` | codesign identity |
   | --- | --- |
   | `adhoc` | `codesign --force --sign -` (today's shipping reality) |
   | `apple-dev` | `Apple Development: Michael Reining (7RU34H8XPD)` |
   | `developer-id` | `Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)` |

   The `developer-id` track is included because that certificate **is** present on
   this host; it is the only track that answers the distribution question. Do not
   notarize and do not staple — that is out of scope.

4. **Case matrix.** For each track, run both replacement cases against a freshly
   bootstrapped job running binary A:
   - **case (a)** — `launchctl bootout` → atomically rename B over the
     bootstrapped path → `launchctl bootstrap`; then assert the heartbeat resumes
     with the new cdhash within 20s.
   - **case (b)** — atomically rename B over the path **underneath the loaded
     KeepAlive job**, then `kill -TERM` the running pid to force a respawn with
     no rebind; assert whether launchd execs the new bytes, and capture any
     pre-`main` refusal (exit 78 / LWCR) from `launchctl print` last-exit-status
     and the log files.

   Record for each cell: cdhash before/after, whether a heartbeat resumed, the
   last exit status launchd reports, and any system-log line matching
   `LWCR|lightweight code requirement|Code Signature` (search
   `log show --last 2m --predicate 'process == "launchd"'`).

5. **Restart contract cases** (`adhoc` track is sufficient):
   - `exit-zero`: the helper exits `0`. Assert launchd does **not** respawn —
     poll for 3× `ThrottleInterval` and confirm no new pid and no new beat.
   - `exit-nonzero` and `kill -KILL`: assert launchd **does** respawn with a new
     pid within 3× `ThrottleInterval`.

6. **Baseline primitives** (proven once, `adhoc` track): bootstrap succeeds;
   active check reads a fresh heartbeat; TERM and KILL both restart; bootout
   leaves no process and no plist; the helper's recorded `path` equals the
   minimal plist PATH (no login shell evaluation); the helper's recorded `cwd` is
   the neutral `$ROOT/cwd` and nothing under the repo or an app bundle.

7. **Record.** Write `docs/qa/alln-serve/ASR-S00-code-identity-matrix.md`: date,
   macOS version, one row per cell (track × case) with the raw verdict, the
   restart-contract results, the baseline results, the exact working plist, and a
   closing **"product delta"** section stating which of the packet's branch
   conditions fired (§8 ASR-S00 branch conditions and §10 first checkbox). State
   results as measured; if a cell could not be run, say so — never infer a cell.

## 7. Works Test

```bash
bash tools/ServeLaunchdHarness/run.sh same-session
```

Default (`same-session`) runs the full matrix and prints a pass/fail table plus
the receipt directory. It must exit nonzero if any assertion it can decide
mechanically fails, and it must always leave zero harness launchd state behind.

## 8. Done when

- [ ] `tools/ServeLaunchdHarness/{run.sh,main.swift,README.md}` exist and contain
      no Allnighter package import and no reference to `alln` or the product label.
- [ ] Two genuinely different cdhashes are built and verified per track; the
      script fails loudly if they collide.
- [ ] All six cells (3 tracks × 2 cases) are attempted and recorded.
- [ ] The restart-contract cases (exit 0 → no respawn; nonzero/signal → respawn)
      are recorded.
- [ ] Baseline primitives (bootstrap, active check, TERM/KILL, cleanup, minimal
      PATH, neutral CWD) are recorded.
- [ ] `docs/qa/alln-serve/ASR-S00-code-identity-matrix.md` records the matrix and
      names which packet branch condition fired.
- [ ] `launchctl print gui/$(id -u)/com.allnighter.serve-launchd-harness` returns
      "could not find service" after the run, and
      `com.allnighter.resident-coordinator` is byte-for-byte untouched.
- [ ] One commit, explicit paths only.

## 9. Host-state invariant

With only this slice committed, the founder's host is unchanged: new files under
`tools/` and `docs/qa/` and nothing else. No product binary, plist, or agent is
modified.
