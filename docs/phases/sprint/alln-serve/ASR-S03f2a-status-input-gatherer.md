# ASR-S03f2a — gather the resolver's inputs from the real host

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §5.2,
§6, §7.

**11 of N** in the ASR-S03 cut. S03f1 (`41f39215`) + S03f1b (`bd0e1800`) built
the v2 shape and a pure resolver with 36 tests. Nothing calls it yet.

One deliverable: a gatherer that assembles `ServeStatusJSON.Input` from the real
host. **No CLI file changes** — wiring `alln serve status` / `--health` and the
§5.3 exit codes is S03f2b.

## 1. Goal

The resolver is pure and fully tested; it just has no inputs. This slice is the
I/O half: read each observation from the source that owns it, and hand the
resolver a filled-in `Input`. Every existing reader already exists — this slice
composes them, it does not reimplement any of them.

## 2. Copy-paste prompt

> Add `ServeStatusGatherer`, which assembles `ServeStatusJSON.Input` by calling
> the existing readers (desired state, launch agent status, health client,
> runtime receipts, canonical install identity) and hands it to
> `ServeStatusJSON.resolve`. Inject every dependency. Do not reimplement any
> reader, do not touch any CLI file, and do not change the resolver.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusJSON.swift`
  — the `Input` struct is the contract this slice fills. Read it first; the
  shape of this slice is "one source per field."
- `ServeDesiredState.swift` — desired state + its `Reading` (absent vs unreadable).
- `ServeLaunchAgentStatus.swift` — the launchd observation and authorization.
- `ServeHealthClient.swift` — the **active** handshake (ASR-S03d). This is the
  only thing that may set a live-daemon input. A `kill(pid, 0)` never can.
- `ServeRuntimeReceipts.swift` — `read(...)` and its `Reading` cases.
- `ServeDaemonStore.swift` — the durable record the handshake's daemon id and
  pid are compared against.
- `Packages/AllnighterCore/Sources/AllnighterCore/CanonicalCLIInstall.swift`
  — `CodeIdentity` and the canonical binary path/expectations.
- `ServeDaemonProbe.swift` — **reference only.** It composes several of these
  for v1. Do not modify it and do not route through it; v1 must keep working
  untouched until S03f2b.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusGatherer.swift          (new)
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeStatusGathererTests.swift  (new)
```

## 5. Do not touch

`ServeStatusJSON.swift`, `CoordinatorHealth`, `ServeDaemonProbe`,
`ServeHealthClient`, `ServeDesiredState`, `ServeLaunchAgentStatus`,
`ServeRuntimeReceipts`, `ServeDaemon`, any scheduler, anything under
`Sources/AllnighterCLI`, any script, `Apps/`.

## 6. Steps

1. **One source per field, named.** Each `Input` field is filled from exactly
   one reader. Where two readers could answer (e.g. pid from launchd vs. from
   the daemon record), pick one, and write a one-line comment saying which owns
   it and why. Two sources silently disagreeing is how a status lies.

2. **Every dependency is injected**, with real defaults: home directory, the
   desired-state reader, the launch agent status reader, the health client, the
   receipts store, the daemon store, and the canonical install. Tests must
   compose the gatherer without touching the real host.

3. **Failure to read is an input value, never a thrown error and never a
   default.** Absent, unreadable, timed-out, and "read fine, says no" are four
   different observations. Map each to the explicit `Input` case the resolver
   already understands. Never collapse "could not read" into "not present" —
   that is the §7 fail-closed law, and the resolver is already written to
   degrade on unknown.

4. **The handshake is the only liveness signal.** Use `ServeHealthClient`, with
   a bounded timeout, and compare the response's daemon id and pid against the
   durable record before reporting a matched handshake. A live pid, a listening
   port, or a loaded job must never set it.

5. **Gathering never mutates.** No install, no bootstrap, no repair, no file
   writes, no process spawn. `alln serve status` is read-only per §5.1, and this
   is the code that makes that true.

6. **Expose one entry point** that gathers and returns the resolved
   `ServeStatusJSON`, plus the gathered `Input` for tests to assert against.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'ServeStatusGathererTests|ServeStatusResolverTests'
```

## 8. Done when

- [ ] With every reader faked to a healthy host, the gatherer produces `healthy`.
- [ ] Four distinct failure-to-read cases (absent / unreadable / timeout /
      negative answer) each produce their own `Input` value and are asserted
      separately — not one shared "unknown" assertion.
- [ ] A handshake that answers with a **mismatched daemon id** does not count as
      matched. Same for mismatched pid. Two tests.
- [ ] A live pid with no handshake response never produces a matched handshake.
- [ ] The gatherer performs no writes: a test with a read-only/failing
      filesystem still returns a status and mutates nothing.
- [ ] Every dependency is injectable — proven by the tests running with zero
      real host access.
- [ ] `ServeDaemonProbe` and `CoordinatorHealth` are unmodified, and
      `alln serve --health` still emits v1 exactly as before.
- [ ] No test writes outside a temp directory. One commit, explicit paths.

## 9. Host-state invariant

Inert. Nothing calls the gatherer yet, and it cannot write. `alln serve --health`
still emits `CoordinatorHealth` v1 unchanged, so no command's output changes and
the live daemon is untouched.
