# Phase 122 — OpenCode Headless Completion & Session Scoping

Status: **SPEC — founder-directed 2026-08-07. Not built.**
Owner: AgentOS (`OpenCodeServeClient`, `OpenCodeSSEParser`,
`OpenCodeRoutingWorkerRunner`, `OpenCodeServeCoordinator`) + Allnighter
(`RunService` outcome gates, `repoDelta`, permission / `blockedOn` surface)
Created: 2026-08-07
Updated: 2026-08-07 (v2 — implementation-ready: pinned session-matching rule,
split client/outcome authority, pinned permission default, reordered slices
for parallel tracks)

**This phase lives in Allnighter `docs/phases/`.** Build work spans
**AgentOS** (OpenCode HTTP/SSE driver) and **Allnighter** (run completion
honesty). Keep the packet here even when editing AgentOS sources.

**Caveat on file:symbol claims:** the paths and line ranges below were
observed during the 2026-08-07 investigation from a different clone than the
one that will implement this. Before coding, re-confirm each `Truth owner`
path and line range still matches HEAD in that repo — do not trust a
citation that is more than a few days old without a fresh grep.

**Related:**

- Allnighter `docs/phases/setup/OpenCode_CLI_Support.md` — original headless /
  serve integration (built; this phase fixes completion bugs on that path)
- Archived `OpenCode_Smoke_Probe_Blocker.md` — why `opencode run` TTY path was
  abandoned for `serve` + HTTP
- OpenCode Go capacity (`OpenCode_Go_Capacity.md`) — metering only; not this bug

**Durable truths graduate to:** AgentOS OpenCode client tests + Allnighter
outcome / `repoDelta` contracts + `alln` help topic for OpenCode headless
completion. Do not teach “use Flash instead of Pro.”

---

## If you only read one thing

DeepSeek V4 Pro (and other OpenCode models) are fine. Headless alln runs were
being **cut mid-turn** by an **unscoped global `session.idle`** on the shared
`opencode serve` event bus, then marked **`done` with the user prompt stored as
the answer**. Fix session-scoped SSE + honest completion gates. Do not demote
Pro or spoon-feed tiny diffs.

---

## Goal

Make OpenCode-backed alln runs (including long investigative DeepSeek V4 Pro
turns) **complete only when this session actually finished**, with:

1. Assistant answer text that is not the prompt echo, **or**
2. A mutating deliverable that is independently true (commits and/or dirty tree),
3. Never a silent green success after a foreign idle, permission hang, or
   tool-only read loop.

---

## Non-Goals

- Changing DeepSeek / OpenCode Go model selection or “prefer Flash for audits.”
- Replacing the HTTP `serve` driver with cold `opencode run` (TTY path stays
  rejected).
- Building a second publish path or Ikiro-side OpenCode integration.
- Full OpenCode ACP driver (still out of scope; see OpenCode CLI Support).
- Cross-project spawn scheduling in general (S122.5 is scoped to OpenCode
  seats only, not a generic job queue).

---

## Evidence (investigation 2026-08-07)

Tagged **BUILT** where traced from entrypoints / artifacts; not from vibes.

### Symptom class A — “reads then produces nothing”

| Run | Model | Observation |
| --- | --- | --- |
| `EB2D7CDC…`, `0C9CF0B1…`, `9BCA81EA…` | `model_opencode_deepseek_v4_pro` | `status: complete/done`, `errors: []`, many `worker.tool` events, **answer.md = prompt** (or mid-task narration), no usable write |
| `opencode export` of EB2D session `ses_0233a313…` | deepseek-v4-pro | Steps 0–7 of tool loop; **last assistant message has no `finish`**, tools still in flight — aborted mid-turn |

**BUILT:** Concurrent Allnighter OpenCode session `ses_0233ada7…` shared the same
`:4096` serve. EB2D’s last tool touch `15:11:07`; alln marked done `15:11:09` —
same second a **new** Allnighter OpenCode session started. Foreign completion on
a global bus is the kill mechanism under test.

### Symptom class B — prompt-as-answer

Worker `output` length matched the founder prompt; `answerDeltaCount: 0`; status
`done`. SSE text accumulation can retain **user** message text parts; if the
turn is cut before assistant text, `!answerText.isEmpty` still passes and the
prompt is filed as the plan/answer.

**BUILT (code):** Plan stage copies worker `output` into plan markdown when
status is `.done` (`RunService` execution path). Tool-only placeholder
(`Completed via N tool actions…`) exists in `OpenCodeServeClient` but the echo
cases observed were **prompt text**, not that placeholder — consistent with
user-part pollution + early idle.

### Symptom class C — permission hang

**BUILT (log):** `~/.local/share/opencode/log/opencode.log` —
`permission=external_directory` → `message=asking` for
`/Users/mike/Documents/GitHub/AgentOS/*` while session permission was only
`[{"permission":"*","pattern":"**","action":"allow"}]`. Headless wait; alln
showed `running` / `alive`; write lock held (~23 min on `B5388841` before
cancel). Founder ruling `blockedOn: permission` recorded earlier; **unbuilt**.

### Symptom class D — no-op / uncommitted “done”

Runs `1E6CC39C`, `F264986D`, `0B84850D`, `0FE1CAF5`: `done`, `errors: []`,
answer ≈ prompt, `repoDelta.filesChanged: 0`.

`C1FBDB46`: edit tools fired; working tree had recoverable edits; still
`repoDelta.changed: false` / `filesChanged: 0` because delta is **commit-only**.

### Counter-evidence (model is capable)

**BUILT:** Sequential `model_opencode_deepseek_v4_pro` read-then-answer probes
(`90A1A865`, `F73A002C`) produced real bullet answers when the seat was not
contended. Mechanical edit runs (e.g. `226CB771`) produced real answers +
commits. Do not treat Pro as weak.

### Parallel OpenCode seats

**BUILT:** Parallel `--read-only` OpenCode models →
`opencode serve: healthCheckTimedOut` for losers; same shared-serve family.

---

## Root causes (fix these)

### RC1 — Unscoped `session.idle` on global `GET /event` (P0)

**Truth owner:** `AgentOS/Sources/AgentOSCLI/OpenCodeServeClient.swift`
(`streamRun`, `isIdleSignal`).

**Lie-prone layer:** IdleGate treats any SSE payload containing `session.idle`
or `"status":"idle"` as **this** turn finished.

**OpenCode schema:** `EventSessionIdle.properties.sessionID` exists. Client
does not filter on it.

**Missing proof:** Two sessions on one serve; A idles; B must keep running.

### RC2 — Answer accumulator includes non-assistant text (P0)

**Truth owner:** `OpenCodeSSEParser.partEvents` (text path).

**Lie-prone layer:** Any `part.type == "text"` updates `answerAccumulator`
without binding `messageID` → assistant role.

**Missing proof:** Fixture with user text part + tools + early idle → must
**not** report `done` with prompt as output.

### RC3 — Tool-only / early-idle success too loose (P0)

**Truth owner:** `OpenCodeServeClient.streamRun` terminal block (~lines
278–294): tools + clean idle ⇒ `done("Completed via N tool actions…")` even
when the ask needed an answer or a write that never happened.

**Missing proof:** Review/answer ask with only `read`/`grep`/`glob` then idle →
`failed` / incomplete, not success.

### RC4 — `external_directory` not covered by auto-approve (P0)

**Truth owner:** session create body
`permission: [["permission":"*","pattern":"**","action":"allow"]]` plus alln
permission / `blockedOn` surface (unbuilt).

**Missing proof:** Prompt that touches a path outside repo root → either
allowed by explicit allow-list rule or terminal `blockedOn: permission`
within seconds; write lock released.

### RC5 — Commit-only `repoDelta` (P1)

**Truth owner:** Allnighter `repoDelta` / terminal JSON mapping.

**Missing proof:** Mutator with dirty tree, zero commits → not clean success.

### RC6 — Shared serve contention (P1)

**Truth owner:** `OpenCodeServeCoordinator` + driver concurrency.

**Missing proof:** Two OpenCode seats either serialize cleanly or use isolated
serves; no `healthCheckTimedOut` false `missing_cli`.

---

## DECIDED defaults (founder: accept or override before coding)

These were ambiguous or self-contradictory in v1. Recommended answers below;
treat as **DECIDED** once the founder confirms, otherwise **PROPOSED**.

- **D1 — session matching rule (S122.0).** `session.*` events (`session.idle`,
  `session.status`, `session.error`) filter on `properties.sessionID`.
  `message.part.*` / `message.updated` events do not reliably carry a
  top-level `sessionID`; resolve them through a `messageID → sessionID` map
  built from `message.created` / `message.updated` events (which do carry
  `sessionID`), scoped to one SSE connection lifetime. A part whose
  `messageID` is not yet in the map is **dropped**, not accepted — unknown
  never defaults to "mine."
- **D2 — mutating vs answer-only intent (S122.2).** Intent is **declared at
  session-create time** from the existing alln run mode (`--read-only` ⇒
  `answerOnly`, default ⇒ `mutating`). It is never inferred after the fact
  from which tools happened to fire — a run can call `write` speculatively
  without being a "mutating ask," and inference is exactly the kind of
  judgment call that produces two different implementations.
- **D3 — client vs outcome authority (S122.2).** `OpenCodeServeClient` never
  itself claims `done` for a `mutating` run. It emits a raw terminal signal
  only: `{ assistantText, toolOnlySummary, idleReason, foreignIdleDetected }`.
  Allnighter `RunService` is the sole authority for final outcome on
  `mutating` runs, combining that signal with `repoDelta` (S122.3). For
  `answerOnly` runs (no `repoDelta` involved), `OpenCodeServeClient` may
  terminal `done`/`failed` directly.
- **D4 — `external_directory` permission (S122.4).** Default **deny-fast**:
  on an uncovered `external_directory` ask, terminal `blockedOn: permission`
  within the bound (default 30s), release the write lock. Layer a **static
  allow-list** of known sibling repos already used in this exact cross-repo
  workflow (AgentOS, Allnighter checkout roots) so the two-repo work this
  phase itself requires is not blocked. Do not blanket-allow arbitrary
  filesystem paths — that trades a hang for an unbounded blast radius, and
  AGENTS.md's High-Risk Stops already treats path/credential scope changes
  as ask-first.
- **D5 — S122.5 priority.** Best-effort, after S122.0–S122.4. It fixes a
  misleading error message (`healthCheckTimedOut` read as `missing_cli`), not
  the mid-turn data-corruption bug — S122.0 already makes cross-talk safe
  without it. Not a phase-exit blocker.

---

## Ordered slices

Two tracks can run in parallel once **D1–D3** above are agreed, because
Track B has no code dependency on Track A — only on the *signal shape* D3
defines.

**Track A (AgentOS, sequential — each slice reuses state from the last):**
S122.0 → S122.1 → S122.2-client

**Track B (Allnighter, parallel to Track A once D3 is agreed):**
S122.3, S122.4, S122.2-outcome (integrates against the D3 signal shape;
can be stubbed until Track A lands, then wired for real before exit gates)

**Track C (optional, last):** S122.5

### S122.0 — Session-scoped SSE filter (AgentOS) — **ship first**

**Files:** `OpenCodeServeClient.swift`, `OpenCodeSSEParser.swift`, tests under
`AgentOSCLITests/`.

**Behavior (per D1):**

1. Remember `sessionID` from `createSession`.
2. Maintain a `messageID → sessionID` map, populated from `message.created` /
   `message.updated` events for the lifetime of one SSE connection.
3. Filter `session.idle`, `session.status`, `session.error` on
   `properties.sessionID == this.sessionID`.
4. Filter `message.part.*` on `messageID` resolving (via the map) to
   `this.sessionID`. A `messageID` not yet in the map is dropped, not
   accepted.
5. `isIdleSignal` must not substring-match foreign JSON — it must parse the
   event and check the resolved session, never regex/contains on raw text.

**Proof:**

- Unit, from a **redacted real capture** of the `EB2D…` / `ses_0233ada7…`
  concurrent-session incident (not hand-authored JSON): foreign
  `session.idle` interleaved with local tool events → gate does not signal
  clean idle for the local session.
- Unit: local `session.idle` with matching `sessionID` → clean idle.
- Unit: a `message.part` event whose `messageID` is unseen (arrives before
  its `message.created`) → dropped, does not leak into either session's
  accumulator.
- Integration (optional dogfood): two live sessions; kill/complete A; B still
  receives parts until B’s own idle.

### S122.1 — Assistant-only answer text (AgentOS)

**Depends on:** the `messageID → sessionID` map from S122.0 (extend it to
also carry role, or add a parallel `messageID → role` map populated from the
same `message.created`/`message.updated` events).

**Behavior:**

1. Track message roles from `message.created` / `message.updated`, resolved
   by `messageID` — never from a convenience `role` field that happens to sit
   on the part event itself (real payloads may not put it there).
2. Accumulate text only for parts whose `messageID` resolves to an
   **assistant** message.
3. Never seed accumulator from the outbound user prompt.

**Proof:** Fixture with **no role field on the part** (forces resolution
through the message map): user text part equaling the prompt, then assistant
text “READY” → accumulated answer is `READY` only. Fixture: user text only +
idle → empty assistant answer (S122.2 decides the outcome from there).

### S122.2 — Honest terminal completion (AgentOS + Allnighter)

Two halves with distinct authority (per D3). Do not let one system decide
the other's job.

**S122.2-client (AgentOS, Track A) — raw signal only, no outcome decision
for `mutating` runs:**

| Signal produced | When |
| --- | --- |
| `assistantText: <text>` | Non-empty assistant text (S122.1) observed before clean idle (this session, S122.0) |
| `toolOnlySummary: "Completed via N tool actions…"` | Only read/grep/glob/todowrite tools fired, no assistant text, clean idle |
| `idleReason: foreignIdle \| streamDrop \| timeout \| localIdle` | How the stream ended |
| `promptEcho: true` | Normalized `assistantText` ≈ normalized outbound prompt (never surfaced as a real answer) |

For `answerOnly` runs (D2), the client terminals directly from this table:
`assistantText` present and not `promptEcho` ⇒ `done`; anything else ⇒
`failed` / `incomplete_no_final_message`. It never emits tool-only success
for a review/answer ask.

**S122.2-outcome (Allnighter, Track B) — sole authority for `mutating`
runs:**

| Client signal | `repoDelta` (S122.3) | Outcome |
| --- | --- | --- |
| `assistantText` present, not `promptEcho`, `idleReason: localIdle` | any | `done` |
| `toolOnlySummary`, `idleReason: localIdle` | commits present | `done` (deliverable is the commit, not text) |
| `toolOnlySummary`, `idleReason: localIdle` | no commits, dirty tree | `incomplete_uncommitted` |
| `toolOnlySummary`, `idleReason: localIdle` | no commits, clean tree | `failed` / `incomplete_no_final_message` |
| `idleReason: foreignIdle \| streamDrop \| timeout` | any | `failed` — never tool-only or partial success |
| `promptEcho: true` | any | `failed` |

**Proof:** Reproduce EB2D-shaped fixture (redacted real capture) → failed/
incomplete. Reproduce successful Pro short-answer fixture (`90A1A865`-shaped)
→ done with bullets. Reproduce `226CB771`-shaped (tool-only + commit) →
done. Reproduce `C1FBDB46`-shaped (tool-only + dirty, no commit) →
`incomplete_uncommitted`.

### S122.3 — `repoDelta` honesty (Allnighter, Track B) — P1

**Behavior:**

- Report `commitsChanged` (existing) **and** `worktreeDirty`, computed from a
  real `git status --porcelain` call (or equivalent), never a mocked git
  wrapper — this is the exact case (C1FBDB46) where a fake status would hide
  the bug this slice exists to catch.
- Mutating run with `worktreeDirty && commits.isEmpty` → `incomplete_uncommitted`
  (fixed name, matches S122.2-outcome table — do not invent a second label).
- Mutating run with zero writes and answer ≈ prompt → `failed` (already
  covered by S122.2-outcome's `promptEcho` row; this is the redundant
  belt-and-suspenders check on the Allnighter side).

**Proof:** Integration test against a real temp git repo: edit + no commit →
`worktreeDirty: true`, gate fails clean-success. Edit + commit → passes.
Must assert against actual `git status` output, not a stubbed flag.

### S122.4 — Permission hang → `blockedOn: permission` (Allnighter + AgentOS,
Track B) — independent of S122.0–S122.3

**Behavior (per D4):**

1. Static allow-list covers known sibling-repo roots (AgentOS, Allnighter)
   for `external_directory`. Everything else is deny-fast.
2. On an uncovered `message=asking` permission event: set
   `blockedOn: permission`, `humanInteraction: true`, stop waiting within 30s,
   release the write lock. Do not silently allow.
3. `alln show` must display the blocked state (not forever `alive` with no
   progress).

**Proof:** Fixture or dogfood path inside the allow-list → proceeds. Path
outside the allow-list → terminals with `blockedOn: permission` within the
bound; lock free. Log line class from `B5388841` must not hang the seat.

### S122.5 — Serve isolation / serialization (AgentOS, Track C) — P1,
optional, ship last

**Scope:** OpenCode seats only — not a general cross-project spawn scheduler
(v1 over-scoped this to "across projects"; S122.0 already makes cross-talk
safe, so this slice is strictly about the `healthCheckTimedOut` /
`missing_cli` false-negative, not correctness).

**Behavior (choose one; document DECIDED):**

- **A (preferred):** `maxConcurrentSpawns: 1` enforced for OpenCode seats on
  one machine, clear queue error instead of `healthCheckTimedOut` /
  `missing_cli`.
- **B:** Per-project serve port / instance so event buses do not cross.

**Proof:** Two parallel `alln run --model model_opencode_*` → second waits or
fails with a typed busy error; never a false `missing_cli` from health
timeout alone without a real missing binary.

---

## Exit gates

1. EB2D-class review ask on DeepSeek V4 Pro completes with a **real critique**
   (not prompt echo) while another OpenCode session exists on the same serve
   **or** proof that foreign idle cannot complete the local turn (S122.0 unit
   proof if live dual-session is flaky).
2. Prompt-echo `done` does not occur in fixtures (S122.1–S122.2).
3. `external_directory` cannot hold the write lock indefinitely, and does not
   blanket-allow arbitrary paths (S122.4).
4. Mutator with dirty tree / no commit is not clean success (S122.3), proven
   against a real git repo, not a mocked status.
5. No product docs or teaching that say “use Flash for real work” as a fix.
6. S122.5 is explicitly **not** required for gate-pass (D5).

---

## Implementation notes (call sites — re-verify against HEAD before coding)

| Piece | Path |
| --- | --- |
| Stream + idle gate | `AgentOS/.../OpenCodeServeClient.swift` |
| SSE parse | `AgentOS/.../OpenCodeSSEParser.swift` |
| Route opencode → HTTP | `AgentOS/.../OpenCodeRoutingWorkerRunner.swift` |
| Serve lifecycle | `AgentOS/.../OpenCodeServeCoordinator.swift` |
| Plan from worker output | Allnighter `RunService` (~execution path writing `.plan`) |
| `repoDelta` | Allnighter `TeamRun` / JSON mapper / git observer |
| Tests to extend | `OpenCodeServeClientTests`, `OpenCodeSSEParserTests`, Allnighter repoDelta / outcome tests |

---

## Works Test (owner-visible)

```text
1. Start (or ensure) opencode serve on :4096.
2. alln run --model model_opencode_deepseek_v4_pro --read-only \
   "Read docs/phases/OpenCode_Headless_Completion_And_Session_Scoping.md
    and write 5 hard bullets: what is over-built, what still fails cold, what
    drifts, highest-leverage change, and one missing proof."
3. While that runs, start a second short OpenCode alln run against another
   registered project (or a second session on the same serve).
4. First run must finish with a real 5-bullet answer ≠ prompt.
5. alln show <id> --json → errors empty only if answer is real; never prompt echo.

Mutator companion: one-line file create + commit under Pro; `repoDelta` shows
commit; if commit skipped, outcome is `incomplete_uncommitted`, not clean
success.

---

## Closeout

- Promote completion rules into Allnighter/AgentOS tests (SSOT).
- Short `alln help` note: OpenCode headless completion is session-scoped; shared
  serve is safe after S122.0.
- Archive this phase when exit gates pass; link from OpenCode CLI Support as
  “completion honesty shipped.”
