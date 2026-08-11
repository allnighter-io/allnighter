# ASR-S03f3 — an unrecorded code identity is not a mismatch

Status: **ready**
Priority: **P0 — blocks ASR-S06 gates 7, 8, 9.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §5.2
(`binary.matches`), §7 (`version -> identity`), and the project law *"Absence of
a declared signal yields no observation, never an inferred one."*

**14 of N** in the ASR-S03 cut. Found by dogfooding `2f1ee6a4` on the founder's
live host minutes after it landed.

## 1. The defect, measured on the live host

`alln serve status --json`, immediately after `scripts/rebuild_cli.sh`:

```json
"state": "degraded",
"supervisor": { "loaded": true, "authorization": "enabled", "pid": 29603 },
"daemon":     { "pid": 29603, "activeHealthRespondedAt": "2026-08-11T15:16:44Z" },
"binary": {
  "expectedGitSha":      "83737c8a29952dd7cc48e8980eb5e5a3ddb47fca",
  "runningGitSha":       "83737c8a29952dd7cc48e8980eb5e5a3ddb47fca",
  "expectedCodeIdentity": {},                      // <- never populated
  "runningCodeIdentity":  { "version": "1.0.1" },
  "matches": false
},
"recovery": { "reasonCode": "SERVE_BINARY_MISMATCH", "command": "alln serve repair" }
```

Exit `69`.

Everything real is right: supervisor loaded, authorization enabled, active
handshake answering, every scheduler advancing with live timestamps, and the
**git sha of the running daemon equals the expected one**. The host is healthy.

Status calls it `degraded`, names `SERVE_BINARY_MISMATCH`, and prescribes
`alln serve repair` — which cannot help, because nothing is mismatched and
repair does not record an identity. So `serve status` is permanently red on a
healthy machine with no path back to green.

## 2. Why this is the same bug as the last two, pointed the other way

S03f1b and S03f2a2 each fixed a junction that guessed **optimistically** when it
could not tell. This one guesses **pessimistically**: it has no recorded expected
identity, and reports the positive claim "these are different executables."

We do not know that. We know the git shas are equal and the identity was never
recorded. Reporting a mismatch asserts a fact nobody observed — the same law
violation, opposite direction. Fail-closed means *withhold the healthy verdict*,
not *invent the failure*.

The practical cost is worse than a wrong word: a status that is always red
teaches its reader to ignore it, and gates 7, 8, and 9 all assert
`state == healthy`, so none of them can pass until this is fixed.

## 3. Copy-paste prompt

> Distinguish "code identity unrecorded" from "code identity differs" in
> `ServeStatusJSON` / `ServeStatusGatherer`. Only a comparison of two **known**
> identities may set `matches: false` with `SERVE_BINARY_MISMATCH`. When either
> side is unrecorded, use a distinct reason code whose recovery command actually
> resolves it. Then populate the expected identity from the canonical install
> record so the steady state on a freshly installed host is `healthy`.

## 4. Read only

- `Packages/AllnighterCore/Sources/AllnighterCore/CanonicalCLIInstall.swift`
  — `CodeIdentity` and whatever the install transaction records today. Find out
  whether an identity is recorded at install time at all; that answer decides
  step 3.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusGatherer.swift`
  — where `expectedCodeIdentity` / `runningCodeIdentity` are filled.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusJSON.swift`
  — the `binary` block and the `matches` rule.
- `docs/qa/alln-serve/ASR-S00-code-identity-matrix.md` — what ASR-S00 measured
  about cdhash behaviour. Do not re-litigate it.

## 5. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusJSON.swift
Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusGatherer.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeStatusResolverTests.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeStatusGathererTests.swift
```

If populating the expected identity genuinely requires touching
`CanonicalCLIInstall`, stop and say so in the commit message rather than
widening silently — that is an install-transaction change and belongs in its own
slice.

## 6. Do not touch

`ServeDaemon`, the loopback `/health` body, `CoordinatorHealth`, any scheduler,
any CLI file, `ContractRegistry`, any script, `Apps/`.

## 7. Steps

1. **Three states, not two.** Identity comparison yields *equal*, *differs*, or
   *unrecorded* (either side missing). Make the third unrepresentable as the
   second — an empty/absent identity is never "differs".

2. **`SERVE_BINARY_MISMATCH` requires two known identities that differ.**
   Nothing else may set it. §7's `version -> identity` ban still holds: equal
   version strings never prove sameness, so a `version`-only identity is not a
   comparable identity.

3. **Unrecorded gets its own reason code and a command that works.** Pick the
   command that actually records an identity — the install path, not
   `serve repair`. §5.3 requires the human line to end in one working recovery
   command; a command that cannot fix the named condition is a false receipt.

4. **Decide the state for unrecorded, and defend it in the commit message.**
   Fail-closed argues for `degraded`; the equal-git-sha evidence argues the host
   is fine. Whichever you choose, it must be reachable-to-green: a state a
   correctly installed host can never leave is not acceptable. If you choose
   `degraded`, step 5 must make the steady state `healthy` on a freshly
   installed host, and a test must prove that.

5. **Populate the expected identity** from whatever the canonical install
   already records. If it records nothing today, do **not** invent a recording
   mechanism here — say so in the commit message and make unrecorded resolve to
   a state a healthy host can sit in, so the gates are unblocked.

6. **Keep the running identity honest.** `runningCodeIdentity` currently carries
   only `version`. Do not upgrade a version string into an identity claim.

## 8. Works Test

```bash
scripts/swift-test.sh --filter 'ServeStatusResolverTests|ServeStatusGathererTests'
```

Then, on the live host, the real proof:

```bash
alln serve status --json    # expect state=healthy, exit 0, on this machine
```

## 9. Done when

- [ ] Two known, differing identities → `matches: false`,
      `SERVE_BINARY_MISMATCH`. Unchanged.
- [ ] Either identity unrecorded → **not** `SERVE_BINARY_MISMATCH`, and a
      distinct reason code whose command can actually resolve it.
- [ ] A `version`-only identity is not treated as comparable.
- [ ] **The founder's live host reports `state: "healthy"` and exit `0`** with
      the supervisor loaded, handshake answering, schedulers advancing, and git
      shas equal. This is the acceptance test; the unit tests do not replace it.
- [ ] A test proves the unrecorded state is reachable-to-green — a correctly
      installed host is not stuck degraded forever.
- [ ] No test writes outside a temp directory. One commit, explicit paths.

## 10. Host-state invariant

Corrective. `alln serve status` stops reporting a false mismatch on the
founder's healthy machine. The daemon, plist, schedulers, and canonical binary
are untouched — only the verdict changes.
