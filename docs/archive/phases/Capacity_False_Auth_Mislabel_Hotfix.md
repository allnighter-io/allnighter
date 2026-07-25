# Capacity False Auth Mislabel — Hotfix

Status: **Complete** — CAP-HF-S01+S02 shipped in AgentOS `bec4f9e`. **CAP-HF-S03
dropped** (scope creep — see below). Archived 2026-07-25.
Owner: AgentOSCLI (`CapacityClassifier`, `DefaultWorkerRunner`) + Allnighter mirror tests
Updated: 2026-07-25 (CAP-HF-S01+S02 closeout)
Incident date: 2026-07-25
Related: [`Idle_Stall_False_Kill_Hotfix.md`](Idle_Stall_False_Kill_Hotfix.md) (idle floors — **independent**, ship in parallel)

## Origin

Founder incident (four parallel premise sweeps, Claude Code / Fable seat):

```text
alln bug found: claude_code-driver seats started failing with capacity: authRequired
at spawn — the same seats worked in this morning's max panel and confirm runs, and
a normal Claude Code session on this machine authenticates fine. The run journal
shows the claude CLI init handshake completing and then being classified authRequired.
```

Follow-up triage (same morning) showed this was **not** a sign-in outage. The seat
authenticated, produced answer text, ran tool work, then died on the **idle**
budget. Allnighter then stamped `capacity: authRequired` and treated the failure
like a login blocker.

Operator impact:

- Agents and founders chase `/login` when auth is fine.
- Bench readiness / seat reseat paths may bench healthy Claude seats.
- `HostSandboxAdvice` can fire on typed `authRequired` inside a restricted host —
  even when the real failure was idle timeout + classifier noise.

(Initial triage also mentioned premise sweeps “serializing on the write lock.”
That was a red herring: the manager ran sweeps **one after another** on purpose.
Bare `--worker` → mutating is Law 7, not a bug; parallel read-only work is
already available by launching **multiple answer/research teams** — they do not
contend for the write lock.)

## Product lie

On a nonzero worker exit, Allnighter surfaces `errorReason: capacity: authRequired`
when the worker was **not** asking the user to sign in. The journal snippet shown
is often the Claude `system/init` JSON line — evidence the session **started**, not
that auth failed.

Help and contract text treat `authRequired` as a hard blocker ("sign in to
continue"). That must never fire on timeout prose, agent output discussing
`unauthorized`, or init handshake bytes.

## Evidence (verified 2026-07-25)

Local run journals under `~/Library/Application Support/Allnighter/Runs/`:

| Run | Local time | Preset | Outcome | What actually happened |
| --- | --- | --- | --- | --- |
| `run_04A6D848-84DE-4B34-A40D-877E8C65F618` | ~06:48 | `default_chat` + `--worker model_fable` | `failed` / `capacity: authRequired` | Init + answer text; ~386s; `timeoutKind: idle`, 300s budget; 1.4MB stdout; **zero stderr** |
| `run_CC4799BA` / `run_2EAE1558` / `run_6904D3CC` | ~06:54–06:55 | same sweep pattern | `failed` / `worker exited 1` | Immediate exit; output is **only** init JSON (~4–5KB) — no capacity stamp (classifier found no pattern) |
| `run_C025F212` / `run_80472DFE` | earlier panel | `custom_test_pipe` | `partial` / seat failed `authRequired` | Haiku seat: init-only output, exit 1; same false stamp. Cursor seat: real `SecItemCopyMatching -67674` (Codex sandbox — different disease) |
| `run_3B00A1A7` / `run_DCE9AE48` | morning | spec review panels | `complete` | Same Claude seats succeeded when runs completed normally |

Interactive control: `claude -p … --output-format stream-json` on this machine
returns a healthy `system/init` + `result` success in ~1.6s. Auth is not broken
on the host.

## Root cause

Two layers; fix both.

### 1. `CapacityClassifier` scans the whole transcript (AgentOS)

Code SSOT: `AgentOS/Sources/AgentOSCLI/CapacityClassifier.swift`

- `classify()` joins **stderr + stdout** and runs `classifyBlockers()` on the
  combined blob.
- `authPatterns` includes broad substrings: `unauthorized`, `authentication`,
  `not signed in`, `/login`, `invalid api key`, etc.
- Any match anywhere in stdout — including agent prose, tool payloads, repo file
  contents echoed in stream — can emit `kind: authRequired` with
  `sourceConfidence: messageFallback`.
- `rawSnippet` is `firstNonEmptyLine(text)` after sanitization, which for Claude
  stream-json is almost always the **`system/init`** line, not the matching auth
  string. That makes journals look like "failed at init" when init succeeded.

This is an **AgentOS** bug. Allnighter consumes the typed observation via
`DefaultWorkerRunner` in the AgentOS package dependency.

### 2. Kill reason prefers capacity over the real clock (AgentOS)

Code SSOT: `AgentOS/Sources/AgentOSCLI/DefaultWorkerRunner.swift`

On nonzero exit:

```swift
errorReason = capacity.map { "capacity: \($0.kind.rawValue)" }
    ?? (result.stderr.isEmpty ? "worker exited …" : stderrTail)
```

Any weak `messageFallback` capacity observation **wins** over an idle reaper kill.
There is no guard that says: "if the process was killed for silence, say idle —
do not borrow auth from stdout archaeology."

### Out of scope for this hotfix

| Item | Verdict |
| --- | --- |
| Bare `--worker` → `writePolicy: mutating` | **Not a bug** — Law 7. Answer/research teams are read-only; run several teams in parallel when you want parallel research. Dry-run already steers bare `--worker` asks via `alternatives`. |
| Codex sandbox `SecItemCopyMatching` / `EPERM` | Real restricted-host failures — `HostSandboxAdvice` path; do not regress. |
| Raising idle floors 300→1800 | **Sibling doc** — `Idle_Stall_False_Kill_Hotfix.md` S01 (shipped). Reduces how often exit-1 idle kills happen; does not fix mislabeling. |

## Non-goals

- Do not weaken real `authRequired` detection for genuine `not logged in` /
  structured vendor auth errors on stderr.
- Do not auto-route bare `--worker` asks to answer teams (teaching only).
- Do not move `CapacityClassifier` into AllnighterCore without the Chat Module
  Extraction cutover plan — fix AgentOS, mirror tests in Allnighter.

## Ship order (locked)

```text
CAP-HF-S01  classifier hygiene (auth channel + snippet truth)     ← shipped (AgentOS bec4f9e)
CAP-HF-S02  kill-reason priority (idle/timeout ≠ auth)            ← shipped (same)
CAP-HF-S03  teaching / dry-run steer audit                        ← DROPPED (scope creep)
```

---

### CAP-HF-S01 — Classifier hygiene (AgentOS)

**Authorized now. Blocks false `authRequired` stamps.**

#### Touch

- `AgentOS/Sources/AgentOSCLI/CapacityClassifier.swift`
- `AgentOS/Tests/AgentOSCLITests/CapacityClassifierTests.swift`
- `Packages/AllnighterCore/Tests/AllnighterCoreTests/CapacityClassifierTests.swift`
  (mirror/regression fixtures — Allnighter depends on AgentOS types)

#### Steps

1. **Split auth evidence channels.** `classifyBlockers()` for `authRequired` /
   `manualRequired` must consult, in order:
   - structured vendor error JSON (existing `classifyStructured` path — keep
     authoritative);
   - **stderr only** for `messageFallback` auth/manual patterns;
   - driver `loginFlow.authErrorPatterns` on stderr lines (optional tighten —
     matches manifest intent in `BundledDefaults.swift` for `claude_code`).
   Do **not** scan stdout for auth substring fallbacks. Agent answer text and
   tool payloads live there by design.

2. **Never emit auth from Claude init alone.** Add negative fixtures:
   - stdout = single `{"type":"system","subtype":"init",…}` line, stderr empty,
     exit 1 → **no** observation.
   - stdout = init + agent prose containing the word `unauthorized` (e.g. "route
     returns unauthorized for anon users"), stderr empty, exit 1 → **no**
     `authRequired` (prose is not auth evidence).

3. **Snippet = matching line.** When a blocker matches, `rawSnippet` must be the
   line that matched (stderr preferred), not `firstNonEmptyLine` of the whole
   transcript. Cap length via existing sanitizer.

4. **Keep real auth fixtures green.** Preserve tests for `not signed in — please
   run /login` on **stderr**, structured Claude `rate_limit_error`, Codex usage
   limits, session-limit prose on stderr, etc.

#### Proof (S01)

```bash
# AgentOS package
swift test --package-path AgentOS --filter CapacityClassifierTests

# Allnighter mirror
swift test --package-path Packages/AllnighterCore --filter CapacityClassifierTests
```

**Done when:** a journaled replay of `run_04A6D848`'s stdout/stderr shape would
not emit `authRequired`; real stderr auth strings still classify correctly.

---

### CAP-HF-S02 — Kill reason priority (AgentOS)

**Authorized next (can ship in the same PR as S01).**

#### Touch

- `AgentOS/Sources/AgentOSCLI/DefaultWorkerRunner.swift`
- `AgentOS/Sources/AgentOSCLI/SubprocessCommandRunner.swift` (if idle reaper tags
  exit / termination reason — thread through)
- Tests: worker result / spawn diagnostics fixtures

#### Steps

1. When the subprocess was terminated by the **idle silence watchdog** (or
   `timeoutKind: idle` is already recorded in spawn diagnostics), set
   `errorReason` to an idle/timeout string (`idle timeout after Ns` or reuse
   existing timed-out vocabulary). **Do not** promote a `messageFallback`
   `authRequired` observation over that fact.

2. Capacity observations may still be **recorded** on the attempt for ledger
   analytics, but `errorReason` shown to users/agents must reflect the clock that
   actually killed the worker when they disagree.

3. Regression: nonzero exit + idle kill + init-only stdout → `errorReason` mentions
   idle/timeout, not `capacity: authRequired`.

#### Proof (S02)

```bash
swift test --package-path AgentOS --filter 'DefaultWorkerRunner|CapacityClassifier'
swift test --package-path Packages/AllnighterCore --filter 'RunIdleTimeoutTests|PendingRunExecutorTests'
```

**Done when:** `run_04A6D848` would journal `idle`/`timed_out` as the headline
reason; `capacityObservation` is absent or demoted for that shape.

---

### CAP-HF-S03 — Teaching audit — **DROPPED**

**Not authorized. Do not resume without a new founder ruling.**

**What it was:** Extra warnings so agents pick `--team code_plan` instead of bare
`--worker` for “research-looking” prompts.

**Why dropped:**

1. **Scope creep.** The incident was false `authRequired` and idle kills — not
   agents failing to discover a flag.
2. **Wrong story.** The premise sweeps were run **sequentially by a manager**, not
   blocked by ignorance of `--team`. Serialization was operational, not a product gap.
3. **Already solved for parallelism.** Answer and research teams are read-only by
   construction. You can run **multiple teams at once**; they do not fight over the
   write lock. That is the normal way to fan out parallel research — not a special
   `--worker` teaching path.
4. **Existing steer is enough.** `alln run --dry-run --json` already prints
   `alternatives` with a ready `--team code_plan --worker …` when a bare mutating
   ask would be wrong. No keyword heuristics or new product law required.

---

## Explicitly rejected

| Idea | Why reject |
| --- | --- |
| "Claude lost auth on the Mac — run `/login`" | Disproven by interactive Claude + morning panel successes |
| Scan stdout for `unauthorized` to catch auth | Guarantees false positives on code review / security prose |
| Drop `authRequired` entirely | Real sign-in failures must still block and bench seats |
| Fix only in Allnighter by post-filtering observations | Classifier is AgentOS SSOT; post-filter duplicates truth |
| Fold into IDLE-HF-S01 idle-floor raise | Orthogonal; raising 300→1800 reduces kills, not mislabels |
| CAP-HF-S03 teaching audit / keyword warnings | Scope creep; sweeps were sequential by choice; multiple read-only teams already run in parallel |

## Related

- Idle false kill (floors + demotion): [`Idle_Stall_False_Kill_Hotfix.md`](Idle_Stall_False_Kill_Hotfix.md)
- Sandbox typed `authRequired` handoff: `docs/archive/phases/Sandbox_Handoff_Hotfix.md`
- Rate-limit / capacity continuity: `docs/archive/phases/Rate_Limit_Continuity.md`
- Read-only parallel research: `ResolvedRunInvocation.readOnlyAnswerTeamSteer()` +
  `CLI_Implementation_Contract.md` Law 7 (permission ≠ prompt prose)

## Closeout

**CAP-HF-S01+S02 (2026-07-25):** shipped in AgentOS `bec4f9e` — stderr-only auth/manual
blockers, matching-line snippets, idle/total kills headline `worker timed out`.
Allnighter mirror tests in `CapacityClassifierTests.swift`. Regression anchor:
`run_04A6D848` shape (init + agent prose on stdout, empty stderr, exit 1) no longer
emits `authRequired`.

**Independent of idle hotfix:** `Idle_Stall_False_Kill_Hotfix.md` S01 (1800 floors)
and S04 (stall demotion) can ship in parallel — they reduce false kills; this fix
stops mislabeling whatever kill reason remains.

**CAP-HF-S03 (2026-07-25):** **dropped** — see §CAP-HF-S03 above. No further work.

**Code SSOT:** `AgentOS/Sources/AgentOSCLI/CapacityClassifier.swift`,
`AgentOS/Sources/AgentOSCLI/DefaultWorkerRunner.swift`; Allnighter mirror tests
`CapacityClassifierTests.swift`.
