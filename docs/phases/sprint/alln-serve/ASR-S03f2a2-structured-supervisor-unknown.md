# ASR-S03f2a2 — the supervisor's "can't tell" is structured, not prose

Status: **done** — `fb42dade` (Cursor Grok 4.5)
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §7
(fail closed; absence of a declared signal yields no observation), and the
project law *"Prompt prose may request work; it must not be the only owner of
semantics."*

**12 of N** in the ASR-S03 cut. Corrects one junction shipped in `50c36b30`
(S03f2a). The rest of that slice — 46 tests, injected dependencies, no writes —
is sound.

## 1. The defect

`ServeStatusGatherer.supervisorLoaded` decides whether the supervisor state is
*unknown* by matching a human-readable display string:

```swift
if observation.state == .unknown,
   observation.detail.contains("launchctl print failed") {
    return nil          // unknown -> resolver fails closed to degraded
}
if observation.state == .absent { return false }
return true             // <- everything else, including reworded details
```

`detail` is free-form prose assembled for humans — the producer builds it as
`"\(label) plist present but launchctl print failed (job not loaded)"`. Nothing
declares it a contract. A copy edit to that sentence is an ordinary, invisible
change, and the moment it lands this branch stops matching.

**And the fall-through is optimistic.** When the match fails, control reaches
`return true` — "supervised". So rewording a display string silently converts
*"we could not determine whether launchd has this job"* into *"launchd has this
job"*, which lets `healthy` be reached on a host where the supervisor was never
observed at all.

That inverts §7's fail-closed law through the one path specifically built to
honour it, and it does so with no test failing, because the tests construct the
same prose the producer does.

## 2. Copy-paste prompt

> Give `ServeLaunchAgentStatus.Observation` a structured signal for "launchctl
> could not be consulted", and have `ServeStatusGatherer` read that instead of
> matching `detail` prose. Make the unmatched fall-through fail closed to
> unknown rather than optimistic `true`. Change no display string's wording and
> no other behavior.

## 3. Read only

- `git show 50c36b30 -- .../ServeStatusGatherer.swift` — the junction, around
  `supervisorLoaded`.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeLaunchAgentStatus.swift`
  — `Observation`, its `State` cases, and every site that builds a `detail`.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeLaunchAgentStatus.swift
Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusGatherer.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeStatusGathererTests.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLaunchAgentStatusTests.swift
```

## 5. Do not touch

`ServeStatusJSON.swift`, `ServeDaemonProbe`, `CoordinatorHealth`, `ServeDaemon`,
any scheduler, anything under `Sources/AllnighterCLI`, any script, `Apps/`.

## 6. Steps

1. **Carry the reason in the type.** Add a structured way for `Observation` to
   say "launchctl could not be consulted" — a dedicated `State` case, or a typed
   reason alongside `state`. Prefer whichever makes the illegal state
   unrepresentable. `detail` stays exactly as it is and remains display-only.

2. **Set it where it is known**, at the site that already writes the
   "launchctl print failed" prose. The producer knows the fact; it should
   declare it rather than describe it.

3. **The gatherer reads the structured signal.** Delete the
   `detail.contains(...)` match. No decision in this file may depend on the
   wording of any human-facing string.

4. **Fail closed on the fall-through.** An observation the gatherer cannot
   classify returns unknown (`nil`), never `true`. State the rule in a comment:
   optimism about supervision is the one direction this code may never guess.

5. **No wording changes.** Every `detail` string keeps its current text, so
   human output and v1 are byte-identical. This slice changes what the code
   *decides on*, not what it *says*.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'ServeStatusGathererTests|ServeLaunchAgentStatusTests|ServeStatusResolverTests'
```

## 8. Done when

- [ ] **The rot test, written first and watched to fail against `50c36b30`:**
      an observation carrying the structured "could not consult launchctl"
      signal but a *reworded* detail string still yields unknown. Against the
      current code it returns `true`; that failure is this slice's negative
      proof.
- [ ] An unclassifiable observation yields unknown, not `true` — asserted.
- [ ] No `detail` string's text changed. Prove by diff and say so in the commit.
- [ ] No decision anywhere in `ServeStatusGatherer` reads `detail`. Grep it in
      the commit message.
- [ ] `ServeLaunchAgentStatus`'s existing tests still pass unmodified except
      where the new case genuinely required a line.
- [ ] `alln serve --health` v1 output is unchanged.
- [ ] No test writes outside a temp directory. One commit, explicit paths.

## 9. Host-state invariant

Inert. The gatherer is still called by nothing (CLI wiring is S03f2b), and no
display string changes, so `alln serve --health` v1 output stays byte-identical.

## 10. Closeout — 2026-08-11

Landed `fb42dade`. Re-verified outside the seat: 62 tests green, exit 0.

`supervisorLoaded` now switches on a structured `launchctlConsultability` and
never reads `detail`. The fall-through is closed, with the rule written where a
future editor will see it: *"Optimism about supervision is the one direction
this code may never guess."*

Display wording is intact — the only changes to `detail` lines are trailing
commas from the added parameter, so human output and v1 stay byte-identical.
The remaining `detail` reference in the gatherer is a display passthrough on a
health-failure reason, not a decision.
