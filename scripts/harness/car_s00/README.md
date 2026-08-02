# CAR-S00 — Codex → LaunchServices authority harness (TEMPORARY, product-free)

This harness answers one question: can a real default Codex session (seatbelt
sandbox, no `--sandbox danger-full-access`) ask LaunchServices to start a signed
app installed in the canonical location, such that the launched app has
**independent macOS authority** (does not inherit Codex's Seatbelt
restrictions)?

It touches no product source. It is scaffolding for the
`docs/phases/Codex_Alln_Run_Hot_Fix.md` packet and should be deleted once
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
- `probe.sh` — caller-side probe, identical for both origins: clears the old
  receipt, writes a fresh nonce, records whether the caller itself is
  sandboxed (CODEX_SANDBOX + an outside-workspace control write), launches the
  app via `open -b <bundleid>`, polls up to 30s for the receipt, and verifies
  the nonce matches.
- `receipts/` — captured raw output of each evidence leg (committed as the
  proof record).

## How to re-run

```bash
scripts/harness/car_s00/build_and_install.sh   # once, or after editing
scripts/harness/car_s00/probe.sh               # leg A: from your own shell
codex exec "run scripts/harness/car_s00/probe.sh from the repo root and show its full output"   # legs B + C
```

Do not pass `--sandbox danger-full-access`; the default Codex posture is the
whole point. Verdict rules are in the packet (`Codex_Alln_Run_Hot_Fix.md` §2
and the CAR-S00 work order).

## Cleanup

```bash
pkill -x AllnighterHarness 2>/dev/null
rm -rf ~/Applications/AllnighterHarness.app \
       ~/Library/Application\ Support/AllnighterHarness
```
