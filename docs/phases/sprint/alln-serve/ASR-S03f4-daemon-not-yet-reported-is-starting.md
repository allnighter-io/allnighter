# ASR-S03f4 — a daemon that has not answered yet is `starting`, not a mismatch

Status: **ready**
Priority: **P1 — every scripted `install-cli` → `serve status` lands in this window.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §5.2
(the `starting` state exists and is unused here), §5.3 (one **working** recovery
command), and the project law *"Absence of a declared signal yields no
observation, never an inferred one."*

Direct sequel to [ASR-S03f3](ASR-S03f3-code-identity-unrecorded-is-not-mismatch.md)
(`a8db6d2d`), which fixed this exact class one field over. Found on the founder's
live host at `c4df8b83`.

## 1. The defect, measured on the live host

`alln serve status --json` in the first second after `alln serve repair`:

```json
"state": "degraded",
"supervisor": { "loaded": true, "pid": 87035 },
"daemon":     { "pid": 87035, "activeHealthRespondedAt": null },
"binary": {
  "expectedGitSha":      "c4df8b83e2be6fe83d4276cdf6e8fc1c604fc920",
  "runningGitSha":       null,
  "runningCodeIdentity": { "cdhash": "9e5e2f83…" },
  "matches": false
},
"recovery": { "reasonCode": "SERVE_BINARY_IDENTITY_UNRECORDED",
              "command": "alln install-cli" }
```

Exit `69`. One second later, unchanged and untouched, the same command returns
`state: "healthy"`, `matches: true`, `runningGitSha: c4df8b83…`, exit `0`.

Nothing was wrong. The daemon simply had not completed its first health
handshake yet, so it had not reported its git sha.

## 2. Why it matters more than a one-second blink

The prescribed recovery is `alln install-cli`. That **restarts the daemon**,
which re-enters the same startup window, which reports the same thing. The
remedy causes the condition. Measured: 6 consecutive `install-cli` →
`serve status` pairs, all 6 reported `degraded`/exit 69, because the poll always
lands inside the window it just created.

That sequence is not exotic — it is what `rebuild_cli.sh` tells every agent to
do, and it is what a scripted gate does. A status that is red immediately after
the supported install path, with a recovery that re-triggers it, teaches its
reader to ignore status.

`ServeStatusJSON.swift:389-393` is the cause:

```swift
guard let expectedSha = obs.expectedGitSha,
      let runningSha = obs.runningGitSha,
      expectedSha == runningSha else {
    return false          // <- nil runningSha falls in here
}
```

A `nil` running sha means **not yet reported**. It is being read as **differs**.
That is precisely the law S03f3 fixed for `expectedCodeIdentity`; the same guard
one line up was left alone.

## 3. Copy-paste prompt

> In `ServeStatusJSON`, stop treating a not-yet-reported `runningGitSha` as a
> binary mismatch. When the daemon has not completed its first active health
> handshake, the honest reading is that its identity is unknown, not that it is
> wrong. §5.2 already defines a `starting` state for a bounded startup
> observation — use it, bounded, and make sure the window cannot be sat in
> forever: a daemon that never answers must still degrade. Do not prescribe a
> recovery command that restarts the daemon and re-enters the same window.

## 4. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusJSON.swift`
  — `binaryMatches`, `binaryMismatchRecovery`, and the top-level state rule.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusGatherer.swift`
  — where `runningGitSha` and `activeHealthRespondedAt` come from, and what
  distinguishes "no daemon" from "daemon that has not spoken yet".
- `docs/phases/sprint/alln-serve/ASR-S03f3-code-identity-unrecorded-is-not-mismatch.md`
  — the three-state rule this slice extends. Do not re-litigate it.

## 5. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusJSON.swift
Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusGatherer.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeStatusResolverTests.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeStatusGathererTests.swift
```

## 6. Do not touch

`ServeDaemon`, the loopback `/health` body, `ServeLifecycle`, any scheduler, any
CLI file, `ContractRegistry`, any script, `Apps/`.

## 7. Steps

1. **Three states for the sha, as S03f3 did for identity.** Equal, differs, or
   not-yet-reported. `nil` is never `differs`.

2. **Use `starting`, and bound it.** A loaded supervisor with a live pid and no
   handshake yet is `starting`. Decide the ceiling and defend it in the commit
   message — §4.3 step 6 already waits at most 10 seconds for active health, so
   that is the natural bound. Past it, `degraded` with a real reason.

3. **The window must be exitable and non-self-perpetuating.** Whatever recovery
   `starting` carries, it must not be a command that restarts the daemon. If the
   right answer is "no recovery, wait", say that.

4. **A daemon that never answers still fails.** Prove it: a test where the
   handshake never arrives must end `degraded`, not sit in `starting` forever.
   This is the fail-closed half and it is the one most likely to be lost.

5. **Failing-first.** Reproduce the `runningGitSha: nil` → `matches: false` case
   against today's code and record the observed failure in the commit message.

## 8. Works Test

```bash
scripts/swift-test.sh --filter 'ServeStatusResolverTests|ServeStatusGathererTests'
```

Then on the live host:

```bash
alln serve repair --json >/dev/null && alln serve status --json | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d['state'], d['binary']['matches'], (d['recovery'] or {}).get('reasonCode'))"
```

Immediately after a repair this must **not** report `degraded` with
`matches: false` and a daemon-restarting recovery.

## 9. Done when

- [ ] A not-yet-reported `runningGitSha` never sets `matches: false`.
- [ ] The startup window reports `starting`, bounded by an explicit ceiling.
- [ ] A daemon that never answers still reaches `degraded` — proven by test.
- [ ] No recovery command restarts the daemon into the same window.
- [ ] `install-cli` immediately followed by `serve status` reports a
      non-degraded state on a healthy host. Baseline: 6/6 reported degraded.
- [ ] A failing-first test reproduced the defect before the fix.
- [ ] One commit, explicit paths, no test writes outside a temp directory.

## 10. Host-state invariant

Corrective and read-only in effect: only the verdict changes. The daemon, plist,
schedulers, and canonical binary are untouched.
