# Sandbox Hand-off Hot Fix — make `alln` work from inside Codex

Status: **Hot fix packet — ready for review, not started.**
Owner: AllnighterCLI + AllnighterEngine + AllnighterMac
Updated: 2026-07-24

## The incident

A Codex session was asked to run a spec review through `alln`. It could not. It
reported back that Panel was frozen, that the fallback "failed before reviewers
started", and that Allnighter had told it *"your terminal can't sign in to your
AI tools"*. The founder had been told, twice, that running `alln` from inside
Codex was built and proven.

It was not proven. The claim rested on mock tests plus **one** live pass on a
freshly launched app, from an unsandboxed shell. The loop that matters — Codex
sandbox → an app that has been open all day → an authenticated provider → an
answer back in Codex's terminal — had never been run end to end, and still has
not been. Only the founder can run it.

## Evidence

Everything below was reproduced by hand on 2026-07-24 by writing requests
directly into the hand-off mailbox and watching the running app.

| Probe | Team / repo root | App | Result |
| --- | --- | --- | --- |
| A | `default_chat` / Allnighter | old (up 5h27m) | claimed, removed, **no run, no error, no log** |
| B | `code_red_two_source` / Allnighter | old | claimed, removed, **no run, no error, no log** |
| C | `code_spec_review` / websitemd.studio | old | claimed, removed, **no run, no error, no log** |
| E | pre-claimed control | old | **survives** — proves nothing deletes indiscriminately |
| F | bogus preset | old | claimed, removed, no run |
| G | `code_red_two_source` / Allnighter | **fresh** | **complete** — run journal written, answer returned |

Probe B is the exact team that succeeded at 14:53 on that same app process. The
only variable between B and G is app uptime.

Three supporting facts, each verified rather than assumed:

- **The transport works.** The sandboxed Codex process wrote a complete run
  journal into Allnighter's support root (`run_EE79C01F`, `owner.json` →
  `inProcess` pid 66432). It can read and write both the mailbox and the
  journal. The part most likely to have been impossible is not.
- **The caller side works.** Inside the sandbox, `HostSandboxAdvice.detect`
  matched, the request was enqueued, and the hand-off message printed.
- **The repo was not the problem.** `websitemd.studio` is a registered project
  (`prj_16580de0`).

## Root causes

### Confirmed

**C1 — a failed start is discarded.** `SandboxHandoffRunner.drainOnce`
(`Packages/AllnighterCore/Sources/AllnighterEngine/SandboxHandoffRunner.swift:44`)
calls `runService.run`, ignores a `.failure` result entirely, and calls
`spool.remove(id:)` regardless. No journal, no error record, no retry. The
request evaporates.

**C2 — the caller then lies.** `SandboxHandoff.handOff`
(`Packages/AllnighterCore/Sources/AllnighterCLI/SandboxHandoff.swift:76`) polls
only for a run journal. On timeout it prints *"Allnighter isn't open, so nothing
picked this up."* The app was open. It did pick it up. The message is a guess
presented as a fact.

**C3 — the hand-off host is invisible.** `log show` for the app process over the
window in question returns nothing. Combined with C1, the root cause of the
actual founder-facing failure is now **unrecoverable**.

**C4 — Panel is still hard-dead.** `PanelCLI.run`
(`Packages/AllnighterCore/Sources/AllnighterCLI/PanelCLI.swift:16`)
unconditionally fails `CODE_RED_UNSUPPORTED`. It checks no state. Code Red was
closed (`20a0646d`) and archived (`f3a9695c`), but that sweep touched only docs —
the code freeze, `HelpTopicRegistry.swift:258`, and four `PANEL_*` error specs in
`ContractRegistry+Milestone1.swift:1049-1052` all still say "during Code Red".
The hand-off wraps `alln run` only (`RunCLI.swift:228,244`), so Panel never
reaches it. This is what sent the Codex session down the fallback path.

**C5 — the tests could not have caught any of this.**
`SandboxHandoffTests` builds a `RunService` with a `MockCommandRunner` and stubbed
ready probe records. It proves enqueue → claim → journal. It cannot observe a
real app refusing a real run.

### Inferred, not proven

**C6 — the host holds a config snapshot for the app's lifetime.**
`SandboxHandoffHost.start()`
(`Apps/AllnighterMac/Sources/SandboxHandoffHost.swift:26-37`) reads
`AppConfig.loadConfiguration()` and `SetupStore().load()` **once**, inside a
`Task.detached`, and holds the resulting `RunService` forever.
`model_roster.json` was rewritten at 19:57 and `cli_setup.json` at 20:29; the
host saw neither. This matches the observed old-app/fresh-app split exactly.

It is an inference. It is not proven, **because C1 destroyed the error and C3
destroyed the trail.** That is the strongest argument for fixing C1–C3 before
anything else: without them the next failure is equally undiagnosable.

## The fix

Ordered so that each slice makes the next one debuggable.

### H1 — never discard a failed start *(fixes C1)*

On `.failure`, `drainOnce` writes a terminal failed `TeamRun` under
`request.runId` carrying the real `RunServiceError`, then removes the request.
The waiting caller reads an answer instead of silence.

*Accept:* a request whose team cannot resolve produces a readable failed run in
the journal, with the error text, within one poll interval.

### H2 — stop guessing on timeout *(fixes C2)*

The caller distinguishes three states, because they are three different
problems: **never claimed** (nothing is listening — the only case that may say
"Allnighter isn't open"), **claimed, no journal yet** (still working), **claimed
and failed** (report the error from H1).

*Accept:* with the app open and the run failing, the terminal never prints
"Allnighter isn't open".

### H3 — make the host observable *(fixes C3)*

The hand-off host logs claim, start, terminal status, and error to the unified
log and to `Logs/`. One line each. Enough that a founder-run test from Codex
leaves a trail even if every other layer misbehaves.

*Accept:* `log show --predicate 'process == "Allnighter"'` shows the full
lifecycle of a hand-off request.

### H4 — the host must not hold a stale snapshot *(fixes C6)*

Build the `RunService` per drain, or invalidate it when config changes. A
long-lived app must behave identically to a freshly launched one.

*Accept:* an app instance whose roster/setup files changed after launch runs a
hand-off request successfully. This is the probe-B-vs-G split, as a test.

### H5 — `alln handoff doctor` *(new, highest leverage)*

A five-second self-check, callable from inside Codex: enqueue a no-op request,
confirm an app claimed it and wrote a terminal journal, print exactly which step
failed if not.

This is the item that cuts iteration cost. Without it, every founder test of this
system costs a full multi-seat panel — minutes of quota — to learn one bit. With
it, the founder types one command and gets a precise verdict.

*Accept:* from a Codex sandbox, `alln handoff doctor` returns a typed verdict in
under ten seconds, distinguishing app-not-open / claimed-but-failed / healthy.

### H6 — kill the 180-second bound

`SandboxHandoff.waitSeconds = 180` breaks the real use case on its own. A trivial
one-seat probe took 75s; a six-seat `code_spec_review` on a real doc takes many
minutes. The caller currently gives up and reports failure while the app is still
working.

Replace with: poll to terminal status with a heartbeat line, plus a detach path
(`alln run --resume <id>`) so a host turn-timeout does not lose the work.

*Accept:* a hand-off run that takes ten minutes returns its answer to the calling
terminal, and a caller that is killed mid-wait can re-attach and collect it.

### H7 — resolve Panel *(C4 — needs a founder ruling)*

Three options, and this one is **not** an implementer's call:

1. **Revive** — route `alln panel` through the same hand-off. Unknown size; the
   Panel dispatch path has been frozen for weeks and its live state is unaudited.
2. **Delete** — remove the surface, the help topic, and the four `PANEL_*` error
   specs. Spec review runs as `alln run --team code_spec_review`, which works.
3. **Redirect** — Panel fails with the exact working `alln run --team …` command
   for what the caller asked, instead of a dead end.

Option 3 is the cheap correct move if Panel is not coming back soon: it costs
little and removes the trap that started this incident. Option 2 is right if it
is never coming back. Whatever the ruling, **a discoverable surface that can
never work must not survive this packet.**

## What this does not fix

Stated plainly, because the last packet's failure was overclaiming:

- **Nothing here is verifiable by an implementing agent.** No agent inside this
  repo can run a Codex sandbox. Every acceptance criterion above that says "from
  a Codex sandbox" is a **founder-run** gate.
- **H1–H4 remove three ways to fail silently and one known cause.** Only H4
  addresses something that was actually stopping work, and it rests on an
  inference (C6).
- **The app must be open.** That is by design, and it is a real operational
  failure mode with no fix in this packet.
- **Panel is unscoped** until H7 is ruled on.

## Confidence

For `alln run` from inside Codex, on the founder's next test:

| Scope | Confidence |
| --- | --- |
| H1–H4 only | ~40% it works; ~95% the failure is *legible* |
| H1–H6 | 70–75% it works |
| Panel (H7) | unscoped — no number until the dispatch path is audited |

The honest framing: **the primary deliverable of H1–H3 is not "it works", it is
"the next failure names itself".** That is what converts an unbounded number of
founder test rounds into two or three.

## Working hypotheses

Revisable by founder ruling, never by an implementing agent mid-slice.

- **A silent drop is worse than a failure.** Any path that can consume work must
  leave a readable terminal record, or it does not ship.
- **Never assert an unobserved cause.** "Allnighter isn't open" was printed
  without checking whether anything had claimed the request. A message that
  guesses at a cause must instead report what was observed.
- **A mock cannot close a host-boundary claim.** The only evidence that counts
  for "works from inside host X" is a run started from inside host X.
- **A surface that cannot work must not be discoverable.** Panel's frozen
  entrypoint cost a full founder session.
