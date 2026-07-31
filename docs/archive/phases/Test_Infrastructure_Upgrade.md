# Test Infrastructure Upgrade

Status: **Complete** · 2026-07-31 (rev 3) — TIU-S00→S03 shipped; archived  
Sprints: **TIU-S00 → S03**, all core. Implementation order: **S00 → S03 → S01 → S02**  
Authority: `AGENTS.md`, `docs/operations/Execution-Playbook.md`, `docs/operations/TechStack.md`  
Depends on: none — execution stop-gate, not product semantics

**Context:** this repo is **100% AI-run — no human ever runs a test or writes a
line of code.** That is a harder problem than "single dev," not an easier one:
there is no one who will notice a hang and intervene (the 2026-07-31 incident
only ended because the founder manually told an agent to stop), and agents
reliably route around advisory rules — both by cutting corners *and* by
over-running full suites "to be safe" when a filtered one would do. Kanso
(also single-founder, also multi-agent) already hit this exact wall and
learned that documentation and IDE-only hooks are not enough; only mechanisms
that hold regardless of which agent or CLI is talking hold at all.

Goal: **tests finish, do not pile up, and do not stop the day — without a
human ever needing to intervene.**

Spec Review Min (`17E96993`, 2/3 workers) informed rev 1. Rev 2 added a
first-principles pass. Rev 3 corrects for the "100% AI, zero human backstop"
fact and re-reads Kanso's actual enforcement mechanism (not just its docs).

---

## Rev 3 — what changed and why

Rev 2 promoted a deny-list guard to core but implemented it as a **Cursor
hook** — that only covers Cursor-hosted sessions. Given this repo's own
`AGENTS.md` header ("Applies to Claude, Codex, Cursor, humans, and CI") and
that no human is ever the fallback, a guard that only watches one of several
agent hosts leaves most of the actual traffic unguarded. That's not "mostly
solved," it's a false sense of coverage.

Re-reading Kanso's real mechanism (not the summary): the load-bearing piece
was never the Cursor hook. It's `scripts/bin/cargo` — a **PATH shim** that
intercepts *every* `cargo` invocation regardless of which agent or shell
called it, and denies heavy subcommands (`test`, `build`, `nextest`, `check
-p`) unless a short-lived, single-use, HMAC-signed token is present — a token
that only their own approved wrapper mints. The Cursor hook is a cheap,
optional second layer on top, not the mechanism itself.

**Change: S03 is rebuilt around the same pattern, scaled down.**

- Adopted: PATH shim (`scripts/bin/swift`, `scripts/bin/xcodebuild`) that
  passes everything through untouched *except* the `test` subcommand, which
  is denied without a valid token.
- Adopted: a minimal single-use, HMAC-signed, expiring token minted only by
  `scripts/swift-test.sh` (and `check.sh`) immediately before it invokes the
  real binary. No token in the environment = denied, with a remediation
  message telling the agent exactly what to run instead.
- Rejected (kept out, still bloat at this scale): Kanso's 4-mode env-var
  system, multishot tokens, tree-fingerprint validation, a `mint --class`
  CLI, and the audit-log/report tooling. One token shape, one TTL, one
  consumer.
- Rejected as the *primary* mechanism, kept as an optional cheap add-on: the
  Cursor hook. It's a nicer pre-shell-exec deny message for Cursor sessions
  specifically; it is not required for the guard to work everywhere else.

**New honesty requirement, because there's no human to notice a silent gap:**
PATH shims only work if `scripts/bin` is ahead of the real toolchain on PATH
for a given shell session. This machine has no `direnv` and no existing
repo-scoped PATH mechanism today — that has to be installed, and activation
must be *verified*, not assumed. `check-fast.sh` checks and loudly warns (or
fails) if the shim isn't active, every time it runs, so a silently-unguarded
session doesn't go unnoticed for days the way the original incident did.

**Sequencing change:** S00's lock/timeout only protects runs it starts. Until
S03 exists, an agent can just skip the wrapper and those protections are
opt-in. So S03 now ships immediately after S00, before S01/S02 — it's what
makes S00 actually binding instead of advisory.

Everything else from rev 2 (timeout, stale-lock recovery, `check-fast.sh`,
serializing hang-prone suites) is unchanged and still correct.

---

## Problem

Today agents treat `bash scripts/check.sh` as the default proof. That wall is:

1. full `swift test` (~2,700 cases)
2. another filtered `swift test` via `code_red_works_test.sh structural`
3. contracts check
4. `xcodegen` + full Mac `xcodebuild test`

Multiple agents (or one agent looping) start this at once against one `.build/`.
Observed 2026-07-31: four overlapping runners, 17–21 min of apparent hang, Mac
unusable for further proof, and one agent spawning repeated wait-watchers
instead of stopping — resolved only because a human happened to be watching
and told it to stop. That fallback does not exist by design in this project.
Stack sample showed `XCTWaiter` + hundreds of `LoopbackHealthServer` /
`DirectModeCommandServer` accept threads.

Cheap hygiene gates alone finish in **~2 seconds**. The failure is
**orchestration and agent behavior**, not missing test coverage — and nothing
here can rely on a human catching what an agent routes around.

---

## Goal (and non-goal)

```text
edit → one filtered proof (or none) → founder tries app
closeout → check.sh once, one runner
```

**In scope:** make raw/unfiltered `swift test` and `xcodebuild test`
non-functional outside the wrapper, regardless of which agent host is typing
the command; prevent concurrent runners; cap any single hang; recover when
wedged; make iteration proof cheap; make `check.sh` the closeout path only;
make guard activation self-verifying, not assumed.

**Out of scope (struck as bloat at this scale):**

- Kanso's 4-mode env-var verify system, multishot/tree-fingerprint tokens, a
  `mint --class` CLI, audit-log reporting tooling
- Separate `Test-Infra-Runbook.md` and baseline-timing project
- GitHub Actions macOS CI (paid minutes; revisit when local loop is calm)
- Sprint work-order folder sprawl, slow-test profiling project
- Lowering the correctness bar or deleting tests to go green

---

## Rules (binding once S00 + S03 ship)

1. **Raw `swift test` / `xcodebuild test` do not work** outside the wrapper —
   this is enforced by the PATH shim, not a request.
2. **One test run per clone.** Second attempt fails fast with a lock message.
3. **Iteration proof = filtered only:**
   `scripts/swift-test.sh --filter <TouchedTests>`
4. **`bash scripts/check.sh` = closeout only** (or founder-requested). Never
   mid-slice, never in a fix→test→fix loop.
5. **Do not run** `swift test --list-tests` as routine (~8+ min cold).
6. **A lock failure or timeout is a stop signal, not a retry signal.** There
   is no human to report to — do not loop, poll, or spawn a wait watcher.
   Move to unrelated work, or end the turn.
7. If the Mac is wedged: kill stale package runners, then continue — do not
   start another full suite on top.

---

## Commands

```text
# One-time per clone, before any of this is binding
scripts/install-test-guard.sh      # installs direnv if missing, writes
                                    # .envrc, direnv allow, verifies shim active

# Iteration (default)
scripts/swift-test.sh --filter LoopDispatch

# Hygiene only (~2s) — also verifies the guard is active
bash scripts/check-fast.sh

# Closeout / founder-requested full wall — one runner
bash scripts/check.sh

# Emergency
scripts/kill-stale-tests.sh
```

Filter = touched test **class** name (e.g. `LoopDispatch` → `LoopDispatchTests`).
Raw `swift test ...` / `xcodebuild test ...` outside these will be denied by
the shim once S03 lands — that's intended, not a bug.

---

## Sprints

### TIU-S00 — Lock + kill + wrapper (+ timeout, + stale-lock recovery)  *(~1 day)*

Stops recurrence and caps worst-case damage for anything that goes through it.

Deliver:

- `scripts/kill-stale-tests.sh`
  - Match only this package (`AllnighterCorePackageTests`,
    `swift-test` with `AllnighterCore`) — never `alln serve`
  - Stale = older than **30 minutes** (`--max-age-minutes`)
  - `--dry-run` lists; default kills
- Repo-root lock: **`.alln-test.lock`** (not under `.build/` — clean deletes it),
  containing the holder PID
- `scripts/swift-test.sh`:
  - Before acquiring: if the lock file's PID is dead, auto-clear the stale
    lock (`kill -0 $PID` check) instead of blocking forever
  - Mint a single-use token (see S03) → acquire lock → run `swift test
    --disable-sandbox --package-path Packages/AllnighterCore "$@"` wrapped in
    a wall-clock timeout (default ~15 min for `--filter` runs, override env
    var for unfiltered/full runs invoked from `check.sh`) → release lock and
    burn the token on exit/trap/timeout
  - Fail-fast message includes holder PID, started-at, and the Rule-6 text:
    *"another run is in progress — do not retry or wait-loop; stop and
    report"*
  - Take one real timing measurement while building this (a filtered run and
    one full run) to set a sane default — not a separate baseline project
- Wire `check.sh` and `code_red_works_test.sh` structural path through the
  wrapper for every `swift test` call
- Update `AGENTS.md` + Execution Playbook § Green Wall with Rules 1–7

Works Test:

1. Hold lock in terminal A with a long `--filter` run; terminal B exits
   non-zero within 5s with a clear message.
2. Kill terminal A's wrapper process directly (simulate crash) — terminal B's
   next attempt succeeds instead of blocking on the dead lock.
3. A run exceeding the timeout is killed automatically and the lock is
   released without needing the outer kill script.
4. `kill-stale-tests.sh --dry-run` lists only matching stale PIDs; live kill
   clears a known stale runner without touching `alln serve`.

---

### TIU-S03 — PATH shim + single-use token  *(~1 day, core, do right after S00)*

Makes S00's protections non-optional by making the raw command not work.
Without this, the lock/timeout only apply to whoever chooses to use them.

Deliver:

- `scripts/bin/swift` and `scripts/bin/xcodebuild` — thin shims. Every
  subcommand except `test` execs straight through to the real toolchain
  binary unmodified (find it by walking PATH past the shim dir). `test` is
  denied unless a valid token is present.
- `scripts/allnighter_test_token.py` — mint (HMAC-signed, ~2 min TTL,
  single-use, deleted on first successful consume) and validate. Stdlib
  `hmac`/`hashlib` only, no new dependency. No mode system, no class
  hierarchy, no multishot, no CLI surface beyond what the wrapper calls
  internally.
- `scripts/swift-test.sh` / `check.sh` mint the token immediately before
  invoking `swift test` / `xcodebuild test`, pass it via env var, and the
  shim consumes it.
- `scripts/install-test-guard.sh` — one-time per clone: install `direnv` if
  missing (`brew install direnv` + shell hook line, printed if it can't be
  done non-interactively), write `.envrc` prepending `scripts/bin` to PATH,
  run `direnv allow`, then verify the shim actually resolves ahead of the
  real binaries.
- `check-fast.sh` gains a guard-liveness check: confirm `command -v swift`
  resolves inside `scripts/bin`. If not, **print a loud warning** (this
  session is unguarded) rather than silently passing — there is no human
  who will otherwise notice.
- Optional, not required: a Cursor hook mirroring the deny message for a
  faster pre-exec UX in Cursor sessions specifically. Skip it if it adds
  meaningful time; the shim already covers Cursor's shell the same as every
  other host once `.envrc` is active.

Works Test:

1. Fresh shell, guard installed: `swift test --package-path
   Packages/AllnighterCore` (no wrapper) exits non-zero with a remediation
   message naming `scripts/swift-test.sh`.
2. Same shell: `swift build` and `swift package resolve` pass through
   unaffected.
3. `scripts/swift-test.sh --filter X` succeeds (mints and consumes its own
   token transparently).
4. A stolen/replayed token (reused after first consume, or past its TTL) is
   rejected.
5. `bash scripts/check-fast.sh` in a shell where `.envrc` was never allowed
   prints the loud "guard not active" warning instead of passing silently.
6. Repeat Works Test 1 inside whichever agent hosts are actually used day to
   day for this repo (at minimum: Cursor's shell tool, and any Claude
   Code / Codex sessions in use) — do not assume PATH activation carries over
   from one host's shell model to another's; confirm it per host.

---

### TIU-S01 — `check-fast.sh`  *(~2–3 hours)*

Separates the 2s path from the hour-scale wall.

Deliver:

- `scripts/check-fast.sh` — extract cheap gates already inline in `check.sh`
  (architecture policy + self-test, TCC asserts, gui proof, swiftui state,
  ThreadStore allowlist, spawn policy, ASF-S08 deny-list, S03's guard-liveness
  check). **Must not** call `swift test`, `xcodebuild`, or
  `code_red_works_test.sh`.
- `check.sh` runs `check-fast.sh` first, then existing heavy steps unchanged.

Works Test: `time bash scripts/check-fast.sh` < 10s; `rg 'swift test|xcodebuild'`
on `check-fast.sh` (excluding the guard-liveness `command -v` check) is empty.

---

### TIU-S02 — Stop the hang class  *(~half day)*

The timeout (S00) caps damage for wrapped runs; this fixes root cause for the
suites already known, so a normal uncontended closeout doesn't need the
safety net at all.

Deliver (mechanical only):

- Serialize the ~6 test files that use `LoopbackHealthServer` /
  `DirectModeCommandServer` (Swift Testing `.serialized` or XCTest equivalent —
  pick the smallest change that runs them one-at-a-time).
- Drop or fold the **second** `swift test` pass inside
  `code_red_works_test.sh structural` when `check.sh` already ran the full
  suite (structural filters run as part of the main suite, or structural is
  CI/manual only — pick one; do not run full + filtered back-to-back every
  closeout).

Works Test: `scripts/swift-test.sh --filter DirectModeCommandServerTests`
completes cleanly; one uncontended `bash scripts/check.sh` reaches the Mac
stage without stalling on Core well under the S00 timeout.

---

## Deferred separately (not part of core)

- **GitHub Actions CI.** Thin ubuntu `check-fast.sh` job would be cheap, but
  there's no local pain it solves right now — the loop is calm once S00–S03
  land. Revisit only if remote proof independent of the local machine becomes
  worth the cost.
- **`xcodebuild` shim scope beyond `test`.** Only the `test` subcommand is
  gated in S03. If `xcodebuild build`/`archive` ever becomes a hammer-the-Mac
  vector the way `swift test` was, extend the same shim — do not build a
  second mechanism for it.

---

## Emergency triage

```bash
ps aux | rg 'xctest|swift-test|check\.sh'
scripts/kill-stale-tests.sh          # after S00; else: pkill -f AllnighterCorePackageTests
# Do not start another full suite until the previous one is gone
```

---

## Done when

- [x] Second concurrent `scripts/swift-test.sh` fails fast (lock)
- [x] A dead lock holder is auto-recovered, not a permanent block
- [x] Any single wrapped run is capped by a wall-clock timeout
- [x] Raw `swift test` / `xcodebuild test` outside the wrapper are denied by
      the PATH shim, verified per agent host actually in use
- [x] Guard activation is self-verifying: an unguarded session gets a loud
      warning, not silence
- [x] Stale runners clearable in one command
- [x] `check-fast.sh` < 10s and has no compile/test suites
- [x] One uncontended `check.sh` completes without wedging on server suites

Archive this packet to `docs/archive/phases/` when Done when is checked;
promote the Rules + Commands into Execution Playbook (no separate runbook).

---

## Decisions

| Question | Ruling |
| --- | --- |
| Cursor-only hook as the guard? | **No** (rev 3) — most sessions aren't Cursor; PATH shim covers every host uniformly |
| Full Kanso policy engine (modes, multishot, audit log)? | **No** — one token shape, one TTL, one consumer |
| PATH shim needs a new dependency (`direnv`)? | **Yes, accepted** — the alternative (docs-only) is exactly what agents already route around |
| What if shim activation silently fails on some host? | Not acceptable silently — `check-fast.sh` checks and warns loudly every run |
| Dedicated runbook + baseline docs? | **No** — Playbook + AGENTS only; one timing sample taken inline during S00 |
| GitHub Actions full wall? | **Deferred**, separate from core |
| Delete tests to go faster? | **No** |
| Lock path? | Repo root `.alln-test.lock`, holder PID recorded, auto-recovered if holder is dead |
| Stale age? | 30 minutes (outer net); wrapper timeout (~15 min) is the primary cap |
| Correctness bar? | Unchanged — change *when* the wall runs and *what enforces it* |

---

## Impact & effort

| | Today | After S00–S03 |
| --- | --- | --- |
| Raw `swift test` typed by any agent, any host | Runs unfiltered, can hang the machine | Denied outright — the wrapper is the only working path |
| Mid-slice proof | Often full `check.sh` / unfiltered suite; can wedge for 15–20+ min | Filtered wrapper, typically **under a few minutes warm** |
| Concurrent agents | Pile up on `.build/`, Mac stops | Second run **fails in seconds** with a clear stop message |
| Agent bypass / retry-loop | Possible and unrecoverable without a human (this is what happened) | Structurally not possible to bypass the wrapper's protections |
| Any single hang (known or new) | Can run indefinitely, nobody notices | Capped by wrapper timeout |
| Crashed lock holder | Blocks all future runs until manual cleanup | Auto-recovered on next attempt |
| Guard silently not active | N/A (no guard existed) | Impossible to miss — `check-fast.sh` warns every run |
| Wedged Mac recovery | Manual `ps` / guess | One kill script |
| Closeout | Same wall, often started on a dirty/contended machine | Same wall, **one runner**, unlikely to hang on server suites |

**How much better:** The failure mode you actually hit — a wedged Mac plus an
agent that wouldn't stop, saved only because a human happened to notice — can
no longer happen at all, on any agent host, with no human watching. That's
the actual bar for a 100%-AI-run repo: not "agents are told not to," but "the
wrong command doesn't work."

**How long:** **~2.5–3 focused days** for S00–S03 end-to-end (~1 day hardened
lock/kill/timeout wrapper, ~1 day PATH shim + token + per-host verification,
~2–3h check-fast, ~half day hang-class serialization). Up from rev 2's ~2
days because the guard moved from a Cursor-only hook to the real host-agnostic
mechanism — the piece that actually makes everything else binding rather than
advisory.
