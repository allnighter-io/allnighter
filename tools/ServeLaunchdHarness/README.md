# Serve Launchd Harness

Disposable native harness proving whether a per-user LaunchAgent survives
replacement of its executable's bytes when the code identity (cdhash) changes,
and whether `KeepAlive = { SuccessfulExit = false }` behaves as the product
restart contract assumes.

Zero Allnighter imports. Never invokes a vendor CLI. Never touches the product
label `com.allnighter.resident-coordinator`.

## Run

```bash
cd /Users/mike/Documents/GitHub/Allnighter
bash tools/ServeLaunchdHarness/run.sh same-session
```

## What it does

1. Compiles `main.swift` twice per signing track with different build tags to
   produce two genuinely different cdhashes.
2. Signs each binary with one of three identities: ad-hoc (`-`), Apple
   Development, or Developer ID Application.
3. For each of the three signing tracks, runs two replacement cases:
   - **Case (a):** bootout → replace binary → bootstrap → assert new cdhash.
   - **Case (b):** replace binary underneath loaded job → kill -TERM → assert
     whether launchd execs the new bytes.
4. Runs restart-contract cases on the ad-hoc track (exit 0 → no respawn; exit
   nonzero/signal → respawn).
5. Runs baseline primitives: bootstrap, active check, TERM/KILL restart,
   bootout cleanup, PATH, CWD.
6. Cleans up: the label `com.allnighter.serve-launchd-harness` and its plist
   are removed on every exit path via a trap.

## Output

- Test matrix printed to stdout.
- Detailed logs under `$HARNESS_ROOT/logs/<timestamp>/`.
- Final results recorded in
  `docs/qa/alln-serve/ASR-S00-code-identity-matrix.md`.
