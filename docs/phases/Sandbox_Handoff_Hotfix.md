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
answer back in Codex's terminal — had never been run end to end, and no agent in
this repo can run it. Only the founder can.

## PROVEN END TO END — 2026-07-24, founder-run

`alln run --team code_red_two_source "Reply with exactly: CODEX_S1_TAKE2"`, typed
inside a sandboxed Codex session in **`websitemd.studio`** — the same repository
where this failed the day before — returned `CODEX_S1_TAKE2` to that terminal.

```text
04:54:35  claimed  run=handoff-B9FF0FB0…  team=code_red_two_source
                   root=/Users/mike/Documents/GitHub/websitemd.studio  by=mac-app
04:54:42  settled  run=handoff-B9FF0FB0…  status=complete
```

`status: complete`, seat `model_chatgpt` `done`, `durationMs 3614`, whole round
trip ~7s. This is the first time the loop has been closed by anyone.

A **stale-binary** false negative preceded it and is worth recording, because it
cost a founder round: `alln` on PATH was a symlink into
`~/Library/Developer/Allnighter/CLI/`, still at `0.9.17 / contract 3.4.0`, while
every build in this packet went to `Packages/AllnighterCore/.build/`. The founder's
first test therefore exercised none of S1 — diagnosed from the message it printed,
which S1 had already deleted. **Before asking for a founder test, verify
`alln version` on PATH matches the build under test.**

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

### S1 — never discard a failed start, and print the id *(C1, C6)* — **SHIPPED**

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

**Done 2026-07-24.** `drainOnce` writes a terminal failed `TeamRun` under
`request.runId` carrying the real `RunServiceError`; the caller prints the id at
enqueue and points at `alln show <id> --json`; `alln show` and `alln run` both
surface `warnings` when a run has no answer (they printed `(run failed)` before,
which is how a specific error became silence). Enqueue failure is no longer
silent either. Live proof: the probe-F case — an unresolvable team, which used to
vanish entirely — now returns
`DEFAULT_TEAM_INVALID: unknown team 'zzz_no_such_team' …` through the ordinary
journal. The new test was confirmed to FAIL against the old discard before being
accepted.

### S2 — an honest, unbounded wait *(C2, and the old H2+H6 merged)* — **SHIPPED**

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

**Done 2026-07-25.** The flat 180s deadline is gone. What replaced it:

- **No work deadline.** Once something claims the request, the run owns its own
  clocks. A 30-minute backstop remains for a host that claimed and died, which
  cannot yet be detected directly — that needs owner identity on the claim (S6).
- **A 30s claim grace**, separate from the work wait. Nothing alive takes longer
  than a poll interval to claim, so a longer grace only makes a closed app look
  like a slow one.
- **A heartbeat every 15s**, so a long review is not mistaken for a hang.
- **Three observed outcomes instead of one guess.** Never claimed → "nothing
  picked this up" (the only case allowed to mention a closed app). Claimed then
  silent → says so, and never blames the app. Claimed and settled with no journal
  → names it as a host older than the S1 repair.
- **Re-attach** converges on the existing `alln run resume <id>` rather than the
  second colliding surface the draft invented. It now covers three cases: a
  vendor park (unchanged), a terminal run (prints it), and a run another host is
  still executing (waits, then prints). New typed error `RUN_NOT_TERMINAL`.
- The caller now retains `Request.id`, without which claim state is unknowable.

Asserted in simulated time (a ticking clock), so the tests state the policy
instead of sleeping through it: a run settling past the retired 180s bound is
still returned, and the two failure states produce different, non-blaming text.

A third copy of the `(run failed)` swallow was found on the resume path and
folded into one `printRunWithoutProject` helper shared by resume and attach.

### S3 — make the host observable *(C3)*

One log line each for config load, claim, start, terminal status, error — to the
unified log and `Logs/`.

*Accept:* `log show --predicate 'process == "Allnighter"'` shows the full
lifecycle of a hand-off request.

### S4 — `alln doctor handoff` *(new; cuts founder-test cost)* — **SHIPPED**

A five-second self-check callable from inside Codex. It needs a `kind: ping`
request that `drainOnce` answers directly with a terminal journal and **no**
`RunService` call — otherwise "under ten seconds" is dishonest and every check
burns a seat. It also bypasses `HostSandboxAdvice` entirely, which makes it the
only probe immune to C8's signature drift.

*Accept:* from a Codex sandbox, a typed verdict in under ten seconds
distinguishing app-not-open / host-never-started / claimed-but-failed / healthy.

**Done 2026-07-24.** Named `alln doctor handoff`, not `alln handoff doctor` — the
`doctor` family already exists (`doctor explain`), so this adds a subcommand
rather than a new top-level family. It is deliberately NOT folded into `alln
doctor` itself, which must stay a read-only report: this one enqueues something.

Three verdicts, all observed rather than inferred: `healthy`, `hostNotRunning`
(nothing claimed it), `claimedButSilent` (something claimed it and never
answered), plus `mailboxUnwritable`. All three verified live: **767ms healthy**
with the app open, `hostNotRunning` with it closed, and `claimedButSilent`
against a host too old to understand pings — which is exactly the orphaned-claim
shape C9 describes.

Two mailbox fixes rode along, both found by writing the tests:
- `unclaimed()` decoded the whole directory with `try` inside a `map`, so ONE
  corrupt or half-written file threw and made the entire mailbox look empty —
  starving every valid request behind it. It now skips unreadable entries.
- `Request` gained `kind` with a hand-written decoder, so a request already in the
  mailbox when this shipped still decodes (as `.run`) instead of silently never
  running.

### S5 — the host must not hold a stale snapshot *(C13)* — **SHIPPED**

Build the `RunService` per drain, or invalidate on config change. Start the host
independently of `remoteAccount.bootstrap()` (C11).

*Accept:* an app whose roster/setup changed after launch runs a hand-off
successfully — the probe-B-vs-G split, as a test.

**Done 2026-07-25.** `SandboxHandoffRunner` now takes a `makeRunService` factory
instead of a held service, and the Mac host reloads `AppConfig` + `SetupStore` for
**each claimed request**. Rebuilding per request rather than per poll keeps the
idle cost at exactly zero — asserted by its own test, because a naive "rebuild
every tick" would reload config files every two seconds forever.

`SandboxHandoffHost.start()` also moved **ahead of** `await remoteAccount
.bootstrap()` (C11): a hung network bootstrap used to leave an open, visible app
that never drained the mailbox, which from the caller's side is indistinguishable
from Allnighter not being open.

Two tests pin the rule so a future change cannot quietly reintroduce a snapshot:
one asserts a fresh service per request, the other that an idle host builds none.

**Still an inference.** C13 was never proven — S1 destroyed the evidence before it
could be. This makes the staleness class impossible rather than proving it was
the cause; if the original failure was something else, S1's journal will now say
so plainly the next time it happens.

### S6 — claim safety *(C9, C10)* — **SHIPPED**

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

**Done 2026-07-25, and driven by a live founder failure.** The app was killed
mid-review (by this agent, during an unrelated relaunch). What that exposed:

- **The drain was serial**, so a six-seat review blocked every later request —
  including the liveness ping, which made `alln doctor handoff` answer "nothing
  is listening" about a host that was visibly busy. The poll tick now never waits
  for work it started; claiming stays serial (exactly-once), execution is
  concurrent.
- **A claim carried no identity** — `claimedBy` was the literal string
  `"mac-app"` — so a claim held by a dead process was permanent. Claims now carry
  pid + start-time and are reclaimed via the existing `isIdentityAlive` rule. A
  claim whose run is already terminal is swept, which also cleans up hosts older
  than this repair.
- **Nothing on the waiting path settled a dead-owner run.** `RunStore.load`
  already PROJECTS one as `interrupted`, but silently, so the caller printed a
  bare status and never learned the app had stopped. The waiter now names it and
  makes the projection durable.
- **A failed run exited 0.** This is the one that made the failure invisible from
  inside Codex: an interrupted six-seat review was indistinguishable, to the
  host, from a command that produced nothing. Exit now follows the frozen
  `RunStatus.lifecycle` axis — `done` (including `partial`) → 0; `failed`,
  `timedOut`, `cancelled` → 1. **This changes `alln run` exit codes for every
  failed run, not just hand-offs.**

Nothing was lost: the killed review's completed seat kept its full 6117-byte
answer, retrievable with `alln run resume <id>`.

*Deferred to a follow-up:* claim-by-atomic-rename and a TTL. The rename closes a
two-host TOCTOU race that needs a second host to exist; identity + reclaim covers
the failure actually observed.

### S7 — payload fidelity *(C7)* — **SHIPPED**

Carry the whole `RunRequest`, not four fields. Delete `runInAppAfterStream`
(`SandboxHandoff.swift:41-49`) — a pure alias.

*Accept:* a hand-off preserves effort, context, attachments and every timeout
override; a property test fails if a new `RunRequest` field is not carried.

**Done 2026-07-25.** The mailbox carried 4 of `RunRequest`'s 26 fields. It now
carries 24, and the two omissions are decisions with reasons rather than
oversights: `timing` (a caller-seeded clock ladder for the CALLER's process — the
host measures itself and must not report times that never happened there) and
`idempotencyKey` (the local attempt that triggered the hand-off may hold it, so
re-using it would make the host refuse its own work as a duplicate of the run it
is replacing).

Found live: the founder ran `--effort low` and the app ran it at default effort.

The drift gate reflects over `RunRequest` and fails on any field that is neither
carried nor consciously omitted — verified by temporarily adding a field, which
named it and told the next person exactly what to do. `runInAppAfterStream`, the
pure alias Fable flagged, is deleted.

### S8 — trigger coverage *(C8, C12)* — **SHIPPED**

Hand off on the `.failure` path too, not only `.success`. Stop treating three
hardcoded vendor strings as the only signal. Resolve the dual product story:
if the hand-off is automatic, `HostSandboxAdvice` must stop telling the user to
paste a command into the app.

**Detection done 2026-07-25, promoted after a live founder run proved it.** A
three-seat TEST team inside Codex lost two seats — `SecItemCopyMatching failed
-67674` and `capacity: authRequired` — and neither matched the three hardcoded
strings. The hand-off never fired, the run reported `partial / completed`, exited
0, and the founder silently received one seat of a three-seat team.

- **A typed signal is now primary.** `capacityAuthRequired` comes from
  `CapacityClassifier`, a classified fact rather than prose a vendor can reword.
  It fires even with no usable failure text at all.
- **The prose list is the fallback and was broadened** to Keychain denials,
  `EPERM` / `Operation not permitted` / `FS_PERMISSION_DENIED`, and
  `not authenticated`.
- **ANY seat lost to the sandbox now triggers the hand-off**, not only a wholly
  failed run — because a partly-degraded team is exactly the case that looked
  like success. Founder ruling: re-run the whole team for now; the partial re-run
  is S11.
- Safe to broaden because the `CODEX_SANDBOX` guard still gates everything: a
  negative test asserts none of these fire in an ordinary terminal, where they
  mean exactly what they say.

**Both remaining halves done 2026-07-25.**

- **The `.failure` path now hands off.** A run that never STARTED produces no
  worker answers, so the signature path could never fire for it — and a sandbox is
  perfectly capable of breaking resolution itself by denying the readiness probes.
  `RunServiceError.retryOutsideRestrictedHost` classifies which preflight failures
  are worth trying elsewhere: `noWorker`, `workerNotAvailable`,
  `repoRootUnavailable` yes; a bad team id no (the app refuses identically),
  lock/lane contention no (a second attempt double-books), journal failure no (the
  mailbox is in the same support root). Being wrong costs one round trip, because
  S1 returns the app's real error.
- **The dual product story is gone.** `warningMessage` opened with "Open
  Allnighter and paste this in: `<command>`" — written before the hand-off
  existed. It contradicted the message printed moments earlier saying the request
  had already been handed off. It now states what was observed and points at
  `alln run resume`. `appCommand` was left referenced only by its own tests, so it
  is deleted with the story it served.

### S9 — resolve Panel *(C4 — founder ruling, not an implementer's call)*

**RULED 2026-07-24: Option 2 — delete.** Shipped in `0656b764`. `alln panel` is
now an ordinary unknown command; 21 files, the help topic and all 11 Code Red
survivals are gone. `PanelPreset`/`PanelPresetStore` were kept deliberately —
same word, unrelated live concept (team presets used by the Mac app). Contract
cut 3.4.0 -> 4.0.0 per the registry's own "major for removals" rule.

### S10 — audit the async team lifecycle — **DONE: nothing to delete**

**The premise of this slice was wrong, and the audit is what proved it.**

It was written claiming `AsyncTeamService.start` had "ZERO callers in either the
CLI or the Mac app — verified, not assumed". That verification was a grep too
narrow to be worth the word: `start` is called by
`RemoteCommandRouter.startRun` (`RemoteCommandRouter.swift:32`, `origin: .ios`),
which is wired into `RemoteMacAgentBootstrap` — the iPhone remote-control path.
The async lifecycle is live; it is simply not reachable from the CLI.

Checked live against a real run rather than by reading:

| Command | Verdict |
| --- | --- |
| `team status` | **KEEP** — returns state plus a `fetchResult` nextAction |
| `team status --persisted` | **KEEP** — reads the journal, `source: "journal"`, `live: false` |
| `team result` | **KEEP** — returns the full `TeamRunJSON` answer |
| `team cancel` | **KEEP** — the stop path for iOS-started runs |
| `team reconcile` | **KEEP** — ownership GC; used in this packet to settle a stranded run |
| `AsyncTeamService.start` | **KEEP** — live via the iOS remote path |

The one real finding is smaller than the slice assumed: since `--detach` was
deleted, **the CLI cannot start an async run**, so `team status` / `result` /
`cancel` are only reachable from the CLI for runs started elsewhere (iOS, GUI) or
for reading finished ones. That is a discoverability nuance, not dead code, and
deleting the commands would have broken the iPhone path.

The genuinely broken thing this slice was chasing — a recipe teaching
`alln run --detach` and bare `alln team` — was already fixed in S9.

*Law reinforced:* "verified, not assumed" has to mean the grep was wide enough to
be wrong. A single narrow search that confirms what you expected is not
verification, and this one nearly deleted a live feature.

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
- ~~**The first attempt is taxed.**~~ **FIXED 2026-07-25 (S12).** Measured on a
  live founder run: a three-seat team inside Codex knew at 1.2s that two seats
  could not start, then waited another **63s** for the one seat that could — and
  the whole run was handed to the app and re-run anyway. 64s paid for a discarded
  result, which is why a ~75s team took 2m49s. `CatalogRunCoordinator` now cancels
  the remaining seats on the FIRST sandbox refusal, so the local attempt costs
  ~1s. `ProcessGroupCommandRunner` terminates the in-flight process groups on
  cancel, so nothing is left running. Detection is still on OBSERVED failure —
  the tax is removed by observing it sooner, not by pre-empting on environment.

## Confidence

Split by what the founder actually runs, because averaging them hides the point.

Revised on evidence after the founder-run proof above.

| Scenario | Confidence |
| --- | --- |
| A short single-seat run from Codex | **PROVEN** — no longer a probability |
| **A real six-seat spec review**, without S2 | **near 0%** — unchanged. The 180s bound reports failure by design while the app is still working, and a six-seat review takes minutes against the ~7s that just worked |
| A real spec review after S2 | 70–80% — the remaining risk is queueing/starvation (C10) and the caller's own host timing out, not the transport |
| Failure is *legible* | S1 shipped; residues are the dead-claimant (C9) and never-started-host (C11) cases, which S4/S6 close |

**What the proof does and does not cover.** It covers the transport, the claim,
execution under real credentials, and the return leg into the calling terminal.
It does **not** cover: a run longer than 180s (S2), a stale long-lived app (S5 —
the app under test was freshly launched), two concurrent callers (C9/C10), or any
request needing a field the mailbox drops (C7).

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
