# Sandbox Hand-off Hot Fix — make `alln` work from inside Codex

Status: **Hot fix packet — reviewed, ready for implementation.**
Owner: AllnighterCLI + AllnighterEngine + AllnighterMac
Updated: 2026-07-24

## The incident

A Codex session was asked to run a spec review through `alln`. It could not. It
reported that Panel was frozen, that the fallback "failed before reviewers
started", and that Allnighter had told it *"your terminal can't sign in to your
AI tools"*. The founder had been told, twice, that running `alln` from inside
Codex was built and proven.

It was not proven. The claim rested on mock tests plus **one** live pass on a
freshly launched app, from an unsandboxed shell. The loop that matters — Codex
sandbox → an app that has been open all day → an authenticated provider → an
answer back in Codex's terminal — has never been run end to end, and no agent in
this repo can run it. Only the founder can.

## Evidence

Reproduced 2026-07-24 by writing requests directly into the hand-off mailbox and
watching the running app.

| Probe | Team / repo root | App | Result |
| --- | --- | --- | --- |
| A | `default_chat` / Allnighter | old (up 5h27m) | claimed, removed, **no run, no error, no log** |
| B | `code_red_two_source` / Allnighter | old | claimed, removed, **no run, no error, no log** |
| C | `code_spec_review` / websitemd.studio | old | claimed, removed, **no run, no error, no log** |
| E | pre-claimed control | old | **survives** — nothing deletes indiscriminately; the claim path is the remover |
| F | bogus preset | old | claimed, removed, no run |
| G | `code_red_two_source` / Allnighter | **fresh** | **complete** — journal written, answer returned |

Probe B is the exact team that succeeded at 14:53 on that same app process. The
only variable between B and G is app uptime.

Three supporting facts, verified rather than assumed:

- **The transport is usable.** The sandboxed Codex process wrote a complete run
  journal into Allnighter's support root (`run_EE79C01F`, `owner.json` →
  `inProcess` pid 66432). That was its own local pre-hand-off attempt, not the
  hand-off — but it proves the sandbox can read and write the support root,
  which is the mailbox and the journal both.
- **The caller side fired.** `HostSandboxAdvice.detect` matched, the request was
  enqueued, and the hand-off message printed.
- **The repo was not the problem.** `websitemd.studio` is a registered project
  (`prj_16580de0`).

## Review — three independent models, 2026-07-24

Reviewed by **Fable 5**, **Gemini 3.6 Flash** (agy) and **Grok 4.5** (grok) via
`alln run`, read-only, each told to disprove the packet against the repo. Every
finding below was verified by hand before being accepted; the draft this replaces
was wrong or imprecise in six ways. Two of the three named the same single
highest-leverage slice (S1); Gemini named observability instead, and lost the
argument — S1 produces the error, S3 only reports around its absence.

| Correction | Verdict |
| --- | --- |
| C1 overstated: some `.failure` paths **do** leave a journal (write-lock timeout saves terminal-failed first) | **Confirmed**, `RunService.swift:812-825`. Narrowed to pre-acceptance failures |
| C2 named only the second lie; the first is printed at **enqueue**, before anything has claimed | **Confirmed**, `SandboxHandoff.swift:69-70`. That is the exact string Codex quoted back |
| C6 overstated: probe records **are** re-read live | **Confirmed**, `RunService.swift:207` → `SetupStore().load().records`. Only `models`/`registry`/`invocations` are frozen |
| Hand-off never fires when the local run returns `.failure` | **Confirmed**, `RunCLI.swift:243` gates on `case .success` |
| The mailbox carries 4 of ~20 `RunRequest` fields | **Confirmed**, `RunService.swift:6-51` vs `SandboxHandoff.swift:59-64` |
| `RunCLI.swift:241-242` comment "same run id, same journal" is false | **Confirmed**, a new `handoff-<uuid>` is minted at `SandboxHandoff.swift:57` |
| `SandboxHandoffRunner.swift:46-47` comment claims failed runs are readable; the next line only handles `.success` | **Confirmed** — an aspirational comment sitting directly on top of the bug |
| H6's detach path was invented; `alln run resume` exists and is vendor-park only | **Confirmed**, `RunCLI.swift:352-363` |
| C4 undercounted the Code Red sweep | **Confirmed** — 11 survivals in `ContractRegistry+Milestone1.swift` alone (`:545-570`, `:997`, `:1049-1052`) |
| The host starts behind `await remoteAccount.bootstrap()` | **Confirmed**, `AllnighterMacApp.swift:117-122` |

## Root causes

### Confirmed

**C1 — a pre-acceptance failure is discarded.** `SandboxHandoffRunner.drainOnce`
(`SandboxHandoffRunner.swift:48-49`) appends only on `.success` and calls
`spool.remove(id:)` unconditionally. For failures that return before the run is
minted — `repoRootUnavailable` (`RunService.swift:643-644`), `canStart == false`
(`:658-663`), idempotency (`:734-741`) — no journal is ever written and the
request evaporates. This is precisely the class a stale bench produces, which is
what the probes hit.

**C2 — the caller lies at both ends of the wait.** At enqueue it prints
*"Allnighter is running this in the app"* (`SandboxHandoff.swift:69-70`) when
nothing may be listening. At timeout it prints *"Allnighter isn't open, so
nothing picked this up"* (`:80-82`) without ever checking claim state. Both are
guesses presented as facts; the first is the string the founder was shown.

**C3 — the hand-off host is invisible.** Not one log line exists in
`SandboxHandoffRunner.swift` or `SandboxHandoffHost.swift`. Combined with C1, the
root cause of the actual founder-facing failure is **unrecoverable**.

**C4 — Panel is hard-dead and still says "Code Red".** `PanelCLI.run`
(`PanelCLI.swift:15-21`) fails unconditionally. Code Red closed (`20a0646d`) and
was archived (`f3a9695c`), but that sweep touched only docs: the freeze, the
file header (`PanelCLI.swift:5`), `HelpTopicRegistry.swift:257-270`, six panel
command summaries (`ContractRegistry+Milestone1.swift:545-570`), the
`CODE_RED_UNSUPPORTED` spec (`:997`) and four `PANEL_*` specs (`:1049-1052`) all
survive. The hand-off wraps `alln run` only (`RunCLI.swift:228,244`), so Panel
never reaches it. This is what sent the Codex session down the fallback path.

**C5 — the tests could not have caught it.** `SandboxHandoffTests` uses a
`MockCommandRunner` and stubbed ready probes (`:31,:37-39`); the claim-once test
(`:68-76`) is sequential and single-process, so it proves nothing about races.

**C6 — the hand-off run id is never printed.** `SandboxHandoff.swift:69-70`
emits no id. A caller killed mid-wait cannot poll for the answer afterwards, even
if the app finished it.

**C7 — the hand-off runs a different request than you asked for.** `RunRequest`
carries ~20 fields; the mailbox carries **four**. `effort`, `threadId`,
`context`, attachments, every timeout override, `lane`, `commitMessage`,
`noCommit`, `advisoryReview` are silently dropped.

**C8 — the hand-off never fires on a preflight failure.** `RunCLI.swift:243`
requires `case .success`. A sandbox that breaks probes hard enough to fail
resolution gets an error and no hand-off at all. Detection also rests on three
hardcoded strings (`HostSandboxAdvice.swift:21-25`); vendor text drift silently
disables the whole mechanism.

**C9 — claims are racy, orphan permanently, and never expire.**
`SandboxHandoffSpool.claim` (`:85-94`) is read-modify-write with no lock, so two
hosts can both win. `claimedBy` is the literal string `"mac-app"` with no owner
identity, so a dead claimant is undetectable — even though `ProcessOwnership`
already exists for exactly this. `unclaimed()` filters `claimedAt == nil`
(`:79`), so a request claimed by an app that then quits is stranded forever. No
TTL: a request enqueued Friday runs Monday. **And the incident's own shape —
a stale instance racing a fresh one — is the worst case: the stale app claims
first, fails silently, and the app that would have succeeded never sees it.**

**C10 — the drain is serial.** `drainOnce` awaits each run inline (`:34-50`). One
long spec review starves every other caller, whose own clock is running.

**C11 — the host may never start.** `SandboxHandoffHost.shared.start()` runs
after `await remoteAccount.bootstrap()` (`AllnighterMacApp.swift:117-122`). A
hung network bootstrap yields an open, visible app that never drains the mailbox.

**C12 — two contradictory product stories.** `HostSandboxAdvice.warningMessage`
still tells the user to open the app and paste a command, while the automatic
hand-off exists. Pick one.

### Inferred, not proven

**C13 — the host holds a stale config snapshot.** `SandboxHandoffHost.start()`
(`SandboxHandoffHost.swift:26-36`) reads `AppConfig.loadConfiguration()` and
`SetupStore().load()` **once** and holds the `RunService` forever. Probe records
*are* re-read live (`RunService.swift:207`), so the frozen pieces are the model
roster, the registry and the invocation map. `model_roster.json` was rewritten at
19:57. A stale roster produces exactly the pre-acceptance `canStart == false`
failure that C1 then destroys — the two dovetail, which is corroboration, not
proof.

It remains an inference **because C1 destroyed the error and C3 destroyed the
trail.** That is the argument for S1 before everything else.

## The plan

Resequenced on review. Each slice makes the next debuggable.

### S1 — never discard a failed start, and print the id *(C1, C6)*

On `.failure`, write a terminal failed `TeamRun` under `request.runId` carrying
the real `RunServiceError`, then remove the request. Print `handoffRunId` to
stderr at enqueue.

The caller already polls for a terminal run and returns it
(`SandboxHandoff.swift:74-76`), and `renderRun` already renders failed runs. So
~15 lines make the real error flow all the way back into the Codex terminal
through code that already exists. **No other slice has that property.** It is
also unit-testable against the real `RunService` with an unresolvable team — no
founder round needed to verify the mechanism — and it will probably settle C13
for free by naming the blocked reason.

*Accept:* a request whose team cannot resolve produces a readable failed run with
the error text, within one poll interval. The run id is printed before the wait.

### S2 — an honest, unbounded wait *(C2, and the old H2+H6 merged)*

Both slices rewrote the same loop, so they are one. The caller: reports observed
state only, distinguishing **never claimed** / **claimed, claimant alive** /
**claimed, claimant dead** / **terminal**; drops the 180-second bound in favour
of polling to terminal with a heartbeat; and re-attaches through the **existing**
`alln run resume` surface, widened to hand-off runs, rather than a second
colliding one.

`waitSeconds = 180` breaks the real use case by itself: a trivial one-seat probe
took 75s and a six-seat `code_spec_review` takes minutes. Note this needs the
caller to retain `Request.id` (or S6's rename-by-runId), which it currently
discards.

*Accept:* a ten-minute hand-off returns its answer to the calling terminal; a
caller killed mid-wait can re-attach and collect; with the app open and the run
failing, the terminal never prints "Allnighter isn't open".

### S3 — make the host observable *(C3)*

One log line each for config load, claim, start, terminal status, error — to the
unified log and `Logs/`.

*Accept:* `log show --predicate 'process == "Allnighter"'` shows the full
lifecycle of a hand-off request.

### S4 — `alln handoff doctor` *(new; cuts founder-test cost)*

A five-second self-check callable from inside Codex. It needs a `kind: ping`
request that `drainOnce` answers directly with a terminal journal and **no**
`RunService` call — otherwise "under ten seconds" is dishonest and every check
burns a seat. It also bypasses `HostSandboxAdvice` entirely, which makes it the
only probe immune to C8's signature drift.

*Accept:* from a Codex sandbox, a typed verdict in under ten seconds
distinguishing app-not-open / host-never-started / claimed-but-failed / healthy.

### S5 — the host must not hold a stale snapshot *(C13)*

Build the `RunService` per drain, or invalidate on config change. Start the host
independently of `remoteAccount.bootstrap()` (C11).

*Accept:* an app whose roster/setup changed after launch runs a hand-off
successfully — the probe-B-vs-G split, as a test.

### S6 — claim safety *(C9, C10)*

**Claim by atomic rename**, not read-modify-write: move `<id>.json` into
`claimed/` (or to `<runId>.claimed-<pid>.json`). `FileManager.moveItem` is atomic
on APFS, the winner is whoever's rename succeeds, and this *deletes* the
`claimedAt`/`claimedBy` mutation code while fixing the race. Put an
`OwnerIdentity` in the destination so a dead claimant is detectable, reclaim
claimed-but-dead requests, add a TTL, and drain concurrently rather than serially.

Collapse `id` and `runId` into one identifier while here — every diagnostic step
in the evidence table above had to correlate the two.

*Accept:* two hosts racing the same mailbox run a request exactly once; killing
the app mid-run leaves a request that the next app instance reclaims.

### S7 — payload fidelity *(C7)*

Carry the whole `RunRequest`, not four fields. Delete `runInAppAfterStream`
(`SandboxHandoff.swift:41-49`) — a pure alias.

*Accept:* a hand-off preserves effort, context, attachments and every timeout
override; a property test fails if a new `RunRequest` field is not carried.

### S8 — trigger coverage *(C8, C12)*

Hand off on the `.failure` path too, not only `.success`. Stop treating three
hardcoded vendor strings as the only signal. Resolve the dual product story:
if the hand-off is automatic, `HostSandboxAdvice` must stop telling the user to
paste a command into the app.

### S9 — resolve Panel *(C4 — founder ruling, not an implementer's call)*

1. **Revive** — route `alln panel` through the hand-off. Unknown size; the
   dispatch path has been frozen for weeks and is unaudited.
2. **Delete** — remove the surface, the help topic, and all 11 Code Red survivals.
3. **Redirect** — fail with the exact working `alln run --team …` command.

Option 3 is the cheap correct move if Panel is not coming back soon. Option 2 is
right if it is never coming back. Either way, **a discoverable surface that can
never work must not survive this packet.**

## What this does not fix

- **Nothing here is verifiable by an implementing agent.** Every acceptance
  criterion that says "from a Codex sandbox" is a **founder-run** gate.
- **The app must be open.** By design; a real operational failure mode with no
  fix in this packet.
- **A mutating hand-off is two writers on one tree.** The app running a mutating
  team against `repoRoot` while the Codex session edits the same worktree is the
  situation the write-lock exists to prevent, and the sandboxed caller is
  invisible to it. Spec review is read-only so the incident missed this; the
  mailbox accepts any team.
- **An abandoned request still spends quota.** No cancel-on-death.
- **The first attempt is taxed.** A full local team must fail before the hand-off
  fires — by design (detection is on observed failure, never environment), but
  it is a real cost the packet does not remove.

## Confidence

Split by what the founder actually runs, because averaging them hides the point.

| Scenario | Confidence |
| --- | --- |
| Small probe (`alln handoff doctor`, one seat) after S1 + S5 | 50–60% it works |
| **A real six-seat spec review** after S1 + S5, without S2 | **near 0%** — the 180s bound reports failure by design while the app is still running |
| A real spec review after S1–S5 | 55–65% |
| Failure is *legible* after S1 + S2 + S3 | 75–85% — residues are the dead-claimant and never-started-host cases, which S4/S6 close |
| Panel (S9) | unscoped — no number until the dispatch path is audited |

The honest framing: **the primary deliverable of S1 is not "it works", it is
"the next failure names itself".** S1 alone guarantees the next founder test is
the last undiagnosed one.

## Working hypotheses

Revisable by founder ruling, never by an implementing agent mid-slice.

- **A silent drop is worse than a failure.** Any path that can consume work must
  leave a readable terminal record, or it does not ship.
- **Never assert an unobserved cause.** Both hand-off messages guess at state
  nobody checked. A message must report what was observed.
- **A mock cannot close a host-boundary claim.** The only evidence that counts
  for "works from inside host X" is a run started from inside host X.
- **A comment is not a contract.** Two comments in this subsystem describe
  behavior the code beneath them does not implement.
- **A surface that cannot work must not be discoverable.** Panel's frozen
  entrypoint cost a full founder session.

## Convergence note

The mailbox stays: it is ~100 lines, it works (probe G), and the tempting
alternative — mint a queued `TeamRun` and let the app resume it — is the RLC
park/resume pattern, which is a draft explicitly sequenced after RLR-S06.
Converging a hot fix on unimplemented draft machinery is how hot fixes die.
**When RLC lands, the mailbox should become a parked-run blocker and
`SandboxHandoffSpool` should be deleted**, or it becomes a permanent second queue.
