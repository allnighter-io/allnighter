# ASR-S06 gate 4 — rollback via injected bootstrap failure — **FAIL**

Date: 2026-08-11 (UTC)
Gate: §8 ASR-S06 **gate 4**, rollback half — "rollback proven with an injected
bootstrap failure."
Host: second Mac (Mac mini), macOS 15.6 (24G84), arm64.
Build under test: `f872ab00`, contract 9.19.0, ad-hoc.
Harness: `works-test-serve-continuity.sh --mutate-product-agent update-rollback`
(ASR-S06d).

**The first execution of §4.3 step 7 on a real host, ever. It does not do what
§4.3 says.**

## Result: FAIL — the binary is not restored

§4.3 step 7:

> On any failure after step 5, restore **binary**, symlink, and plist; bootstrap
> the prior known-good job when one existed; return a nonzero structured failure.

The plist is restored. The prior job is re-bootstrapped. The exit code is
nonzero. **The binary is not restored.**

| Assertion | Result |
| --- | --- |
| install command exits nonzero | **PASS** (exit 1) |
| canonical binary restored to prior bytes | **FAIL** |
| cdhash restored | **FAIL** |
| plist restored to prior bytes | PASS |
| prior LaunchAgent job loaded again | PASS |
| host healthy on original `runningGitSha` | PASS |
| one daemon / one agent / pid match / zero Dock | PASS |
| PATH symlink resolves to canonical | PASS |

## Independently verified, not just harness-reported

A copy of the canonical binary was taken **before** the run, outside the harness:

```text
pre-run copy (the original)            sha256 41b2693afd7b40557a323e5b…
canonical binary after failed install  sha256 fb7522e4be22198424ce58b3…
~/.local/share/allnighter/bin/alln.rollback   sha256 41b2693afd7b40557a323e5b…
```

`.rollback` holds the original bytes, byte-identical to the pre-run copy. The
canonical path holds the **candidate** bytes. The rollback file was written
correctly and then never used.

## Why it looked green on the surface

`runningGitSha` still matched, and the host ended healthy — because the candidate
was built from the same commit as the installed binary (HEAD had not moved), so
the "wrong" binary happened to report the right sha.

**Had HEAD moved, the host would now be running a build that a failed install was
supposed to undo**, with the correct bytes sitting unused in `.rollback` beside
it. The sha check alone would not have caught it; only the byte-level comparison
did.

## Scope of the defect

The failure is in the converge path's restore, not in the seam and not in the
plist handling. ASR-S02f taught `_restorePriorRegistration` to restore the plist
and re-bootstrap honestly — it never restored the binary, and nothing else does
either once `install-cli` has renamed the candidate into place.

Whether the binary rollback belongs in `ServeLifecycle.converge` or in
`CanonicalCLIInstall` (which owns the rename and writes `.rollback`) is a design
question for the fix slice, not a finding here.

## Injection seam behaved correctly

- Announced itself loudly on stderr on every attempt.
- Fired only at the install/converge bootstrap; the restore bootstrap succeeded.
- Produced exactly the §4.3-shaped failure it was meant to.
- Test proves a spawned child never inherits the variable.
- Inert during a normal `rebuild_cli.sh`: no warning, host healthy.

## Host state

Healthy. `runningGitSha f872ab00`, one daemon, one agent, `binary.matches: true`.
The host is running candidate bytes built from the same commit, which is
functionally identical to what it should be running.

`~/.local/share/allnighter/bin/alln.rollback` is **deliberately left in place**
(48 MB). §4.3 step 8 deletes rollback bytes only after health matches the
candidate, and §4.3 keeps them on a failed rollback. It is evidence for the fix
slice; the fix should decide its disposition.

## Harness defect, minor

The script printed `PASS — update-rollback host proof passed` and then
`2 FAILURE(S)` in the same run. A summary line that claims a pass while failures
are outstanding is exactly the kind of contradiction this packet exists to
remove. Folded into the fix slice.

## Follow-up

[`ASR-S06e`](../../phases/sprint/alln-serve/ASR-S06e-restore-the-binary-on-failed-install.md)

## Reproduce

```bash
shasum -a 256 ~/.local/share/allnighter/bin/alln          # record the original
bash scripts/works-test-serve-continuity.sh --mutate-product-agent update-rollback
shasum -a 256 ~/.local/share/allnighter/bin/alln          # must equal the original
shasum -a 256 ~/.local/share/allnighter/bin/alln.rollback
```

## Signature

**No founder signature required.** §8 names gates **7, 8, 9 and 10** as the
ones needing a human at the machine, and only those. This gate was executed
and measured by the PM agent on the live host; the record above is the
evidence. An earlier draft of this file carried a "pending founder
countersignature" line — that was ceremony this packet does not ask for, and
it is removed.
