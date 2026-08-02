# CAR-S00 — Codex → LaunchServices authority harness (TEMPORARY, product-free)

This harness answers one question: can a real default Codex session (seatbelt
sandbox, no `--sandbox danger-full-access`) ask LaunchServices to start a signed
app installed in the canonical location, such that the launched app has
**independent macOS authority** (does not inherit Codex's Seatbelt
restrictions)?

It touches no product source. It is scaffolding for the
`docs/archive/phases/Codex_Alln_Run_Hot_Fix.md` packet and should be deleted once
CAR-S00's verdict has been acted on.

## Contents

- `HarnessApp.swift` — minimal signed app (`com.happymoose.allnighter.harness`).
  On launch it reads a nonce, probes Keychain reachability (non-secret
  `SecItemCopyMatching` expecting `errSecItemNotFound`), writes a byte outside
  any workspace, records pid/ppid/`CODEX_SANDBOX`, writes `receipt.json`, and
  exits. No window, no daemon.
- `build_and_install.sh` — builds with standalone `swiftc`, signs with
  `Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)`, installs to
  `~/Applications/AllnighterHarness.app`, registers with `lsregister -f`.
- `probe.sh` — caller-side probe (single primitive: `open -b`), identical for
  both origins: clears the old receipt, writes a fresh nonce, records whether
  the caller itself is sandboxed (CODEX_SANDBOX + an outside-workspace control
  write), launches the app, polls up to 30s for the receipt, and verifies the
  nonce matches.
- `probe_matrix.sh` — CAR-S00b caller-side probe: tries five launch primitives
  in order (`open -b`, `open <path>`, `open -a <path>`, direct spawn of the
  bundle executable as the inherited-sandbox control, `osascript ... launch`),
  each with a fresh nonce and up to 20s receipt poll, reporting rc, verbatim
  output, and per-receipt authority facts (ppid, `codex_sandbox`, Keychain
  status, non-writable-path fs write).
- `receipts/` — captured raw output of each evidence leg (committed as the
  proof record).

## State paths (CAR-S00b)

Nonce/receipt live under the REAL product state root, which default Codex
seatbelt lists as writable:
`~/Library/Application Support/Allnighter/car_s00_harness/`.
(S00 used `~/Library/Application Support/AllnighterHarness/`, which is NOT
writable inside Codex — that confounded the first leg C: the nonce write
failed before `open` was ever reached.)

The caller control write and the in-app filesystem authority probe
deliberately target the old, genuinely non-writable `AllnighterHarness` dir:
a sandboxed caller/inherited launch must fail that write, a detached
LaunchServices launch must succeed. The asymmetry is the signal.

## How to re-run

```bash
scripts/harness/car_s00/build_and_install.sh   # once, or after editing
scripts/harness/car_s00/probe_matrix.sh        # leg A': matrix from your own shell
codex exec "run bash scripts/harness/car_s00/probe_matrix.sh from the repo root and show its full output"   # leg C'
```

Do not pass `--sandbox danger-full-access`; the default Codex posture is the
whole point. Verdict rules are in the packet (`Codex_Alln_Run_Hot_Fix.md` §2
and the CAR-S00 work order).

## Cleanup

```bash
pkill -x AllnighterHarness 2>/dev/null
rm -rf ~/Applications/AllnighterHarness.app \
       ~/Library/Application\ Support/AllnighterHarness \
       ~/Library/Application\ Support/Allnighter/car_s00_harness
```
