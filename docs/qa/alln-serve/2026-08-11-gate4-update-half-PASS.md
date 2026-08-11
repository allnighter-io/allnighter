# ASR-S06 gate 4 — vA → vB update — **update half PASS, rollback half unrun**

Date: 2026-08-11 (UTC)
Gate: §8 ASR-S06 **gate 4** — "vA → vB update: one agent, one daemon, new build
identity, no orphan/staged copy, rollback proven with an injected bootstrap
failure."
Host: second Mac (Mac mini), macOS 15.6 (24G84), arm64.
Harness: `scripts/works-test-serve-continuity.sh --mutate-product-agent update`
(ASR-S06c, `978c6b95`).

**Gate 4 is NOT passed.** Only its update half is. The rollback half needs a
failure-injection seam that does not exist yet and is cut as ASR-S06d.

## Result: update half PASS

Genuine vA → vB: the installed binary was at `1a425085` and the tree at
`978c6b95`, so the rebuild moved the daemon to a different commit.

| Assertion | Result |
| --- | --- |
| `binary.matches` | true |
| `runningGitSha` == expected | `978c6b95…` ✔ |
| build identity changed | `472329d3…` → `cdf1b2a9…` ✔ (see caveat) |
| exactly one daemon process | ✔ |
| exactly one loaded LaunchAgent | ✔ |
| daemon pid == supervisor pid | ✔ (18438) |
| zero Dock `Allnighter` processes | ✔ |
| no staged copy under Application Support | ✔ |
| no orphan `alln serve` process | ✔ |
| PATH symlink resolves to canonical | ✔ |

Host healthy afterwards; daemon 18438, health responded 19:09:55Z.

## Caveat — the "build identity changed" assertion cannot fail

Recorded because a proof that cannot fail is worth less than it looks (§3
Measurement, `docs/operations/Spec_Review.md`).

A second run was made deliberately **with an unchanged tree**, expecting the
no-op guard to fire. It did not: the cdhash moved again,
`cdf1b2a9…` → `10ffb7e7…`, and every assertion passed.

Cause: `rebuild_cli.sh` deletes `BuildInfo.generated.swift` to force
regeneration, and the regenerated file embeds a build timestamp. Different bytes
every time, therefore a different ad-hoc cdhash every time, whether or not any
source changed. The assertion proves *the binary was replaced*; it cannot detect
*a rebuild that installed the same version*.

The load-bearing assertion in this gate is therefore
**`runningGitSha == expected`**, not the cdhash comparison. On the recorded run
that check was meaningful, because the installed sha (`1a425085`) genuinely
differed from HEAD (`978c6b95`). On the second run it passed trivially, since
HEAD had not moved.

Follow-up, folded into ASR-S06d: compare the **git sha** before and after, and
when HEAD has not moved, report the run as a same-version reinstall rather than
letting it read as a vA → vB proof.

## What this does NOT prove

- **The rollback half of gate 4 is unrun.** No bootstrap failure was injected, so
  §4.3 step 7 (restore binary, symlink, plist; bootstrap the prior known-good
  job) is unverified on a real host. ASR-S02f's unit tests cover the logic; the
  host proof does not exist.
- The update path was exercised only from a healthy host with no active
  obligations. `SERVE_BUSY` (§5.3, exit 75) is untested here.
- One update on one host, ad-hoc signing track only.
- §10.1 R1 is untouched and stays open.

## Reproduce

```bash
bash scripts/works-test-serve-continuity.sh --mutate-product-agent update
```

For a meaningful vA → vB the installed binary must be behind HEAD; check with
`alln version --json` against `git rev-parse HEAD` first.

## Signature

Recorded by the PM agent; the mutating run was founder-authorized. Per §8 the
founder is the signer.

**Signed:** _pending founder countersignature._
