# OpenCode Serve Attach

Status: **Ready for Implementation — OSA-S00→S03; review hardened**
Owner: AgentOS (`OpenCodeServeCoordinator` / `OpenCodeRoutingWorkerRunner`)
Created: 2026-08-08
Last updated: 2026-08-08

## Review delta (2026-08-08)

DeepSeek V4 Pro doc review (`EB2E560D`) + founder closeout:

**Simplified/hardened:**
- Merged §1 (claim) + §2 (law) + §3 (defect) into one Defect + one Law section; cut redundant prose.
- Replaced vague "Fix shape (one slice)" with explicit OSA-S00 → OSA-S03 slice plan.
- Anchored health probe contract to existing `defaultHealthCheck()` (line 58–71) instead of an undefined "health check passes" reference.
- Formalized refuse taxonomy (exhaustive table) in OSA-S01.
- Added per-slice Works Tests, explicit code touch points (file:line under AgentOSCLI), and affected test names.
- Removed §7 ops note (redundant with law + non-goals); kept the `alln serve` ≠ `opencode serve` disambiguation in a concise note.
- Updated cross-packet link: `OpenCode_Long_Run_Continuity` is archive-ready; CT-05 code is the surviving truth.
- Fixed phases/README.md duplicate/missing Serve Attach router rows.

**Open questions:** none remaining. `portOwnedByForeignProcess` → **remove in OSA-S01**.

---

## 1. Defect

After a successful `alln run` on driver `opencode`, `opencode serve` often stays
listening on `127.0.0.1:4096`. The next `alln run` (new process) refuses with
`opencode serve busy: port owned by pid <N>` instead of attaching to the healthy
leftover. Affects **all** OpenCode seats (Go, Zen, local).

**Root cause:** `OpenCodeServeCoordinator.ensureRunning()` calls
`refuseForeignListenerIfNeeded()` **before** any health gate. That method throws
`portOwnedByForeignProcess` whenever a listener exists on `:4096` but
`currentSpawnedPID == nil` — regardless of whether the listener is a healthy
OpenCode serve from a prior `alln run`. Process-local spawn memory cannot
survive `--no-wait` / multi-process reality, so "I didn't fork that pid" is the
wrong identity check.

**Code references (current):**

| File | Line | What |
| --- | --- | --- |
| AgentOS `Sources/AgentOSCLI/OpenCodeServeCoordinator.swift` | 7 | `portOwnedByForeignProcess(listenerPID:)` error case |
| AgentOS `…/OpenCodeServeCoordinator.swift` | 58–71 | `defaultHealthCheck()` — GET `http://127.0.0.1:4096/`, 2s |
| AgentOS `…/OpenCodeServeCoordinator.swift` | 102 | `refuseForeignListenerIfNeeded()` call in `ensureRunning()` |
| AgentOS `…/OpenCodeServeCoordinator.swift` | 166–169 | `refuseForeignListenerIfNeeded()` — throws on foreign listener |
| AgentOS `…/OpenCodeServeCoordinator.swift` | 172–185 | `isOwnedAndHealthy()` — rejects non-owned healthy listener |
| AgentOS `…/OpenCodeRoutingWorkerRunner.swift` | 93–94 | `serveFailure` → maps `portOwnedByForeignProcess` to user error |
| Allnighter `HelpTopicRegistry.swift` | 403 | "manual orphan serve fails with `portOwnedByForeignProcess`" |

**Repro:**
```text
1. Ensure :4096 free
2. alln run "<prompt>" --model <opencode seat> --json --no-wait  → PASS
3. lsof -iTCP:4096 -sTCP:LISTEN  → opencode still up
4. alln run "<prompt>" --model <opencode seat> → FAIL: opencode serve busy: port owned by pid …
```

---

## 2. Product law

OpenCode on Allnighter is a **warm shared seat server**, not a per-run child CLI.

| Rule | Implementation |
| --- | --- |
| **Attach** | Healthy listener on `:4096` → reuse. Identity is port + health, not spawn provenance. |
| **Start if missing** | No healthy listener → spawn `opencode serve` once (unchanged from today). |
| **Do not tear down per run** | Per-run teardown fights warm-serve design and breaks shared Go/local lanes. |
| **Do not SIGTERM healthy listeners** | CT-05 intent preserved. Never kill a live OpenCode to clear the port. |
| **Refuse only when truly unusable** | Unhealthy listener or non-OpenCode process on the port. Not "foreign PID" alone. |

**Rejected:** tear down the serve after every `alln run` (cold-starts every turn,
nukes shared lanes, and still needs attach for `--no-wait` leftovers).

Note: `alln serve` (Dock scheduler daemon) is **not** `opencode serve` (`:4096`).
This packet has no effect on `alln serve`.

---

## 3. Fix shape — slice plan

### OSA-S00 — Attach healthy serve instead of refusing

**Scope:** Change `OpenCodeServeCoordinator.ensureRunning()` so a listener on
`defaultPort` that passes the health probe is **attached**, regardless of
`currentSpawnedPID`. Remove the pre-flight `refuseForeignListenerIfNeeded`.

**Current flow (bug):**
```
ensureRunning:
  → refuseForeignListenerIfNeeded  ← throws if foreign listener (healthy or not!)
  → isOwnedAndHealthy              ← rejects foreign healthy serves
  → spawn
```

**Target flow:**
```
ensureRunning:
  → reapIfIdle (unchanged; skips if not our child)
  → isHealthy() passes → touchActivity, return
  → listener exists but health failed → throw healthCheckTimedOut
  → no listener → spawn as before
```

**Code changes:**
1. `OpenCodeServeCoordinator.swift:102` — delete `refuseForeignListenerIfNeeded()` call.
2. `OpenCodeServeCoordinator.swift:104` — replace `isOwnedAndHealthy()` with `isHealthy()` (checks health only; no ownership test).
3. `OpenCodeServeCoordinator.swift:166–169` — delete `refuseForeignListenerIfNeeded()` method entirely.
4. `OpenCodeServeCoordinator.swift:172–185` — replace `isOwnedAndHealthy()` with simplified `isHealthy()` (or inline `await healthCheck()`).
5. Before the spawn path: if `portListenerPID(defaultPort) != nil` (unhealthy listener on port), throw `healthCheckTimedOut`.

**Test changes (AgentOS):**
- `testEnsureRunning_refusesForeignPortListenerWithoutKilling` (line 135) → change to `testEnsureRunning_attachesHealthyForeignListener` — expects no error, no launch.
- Add: `testEnsureRunning_refusesUnhealthyForeignListener` — health false, port occupied → throws `healthCheckTimedOut`.
- Add: `testEnsureRunning_attachesHealthyLeftover` — health true, port occupied, `currentSpawnedPID == nil` → returns without spawn.

**Non-goals:** spawn-lock semantics, idle TTL, reaping (unchanged; reaping stays scoped to `spawnedPID`).

**Works Test:**
```
Given:  listener on :4096, health probe passes, currentSpawnedPID == nil
When:   ensureRunning is called
Then:   returns normally (no error); streamRun proceeds
        launchServe is never called
```

---

### OSA-S01 — Remove `portOwnedByForeignProcess` + formalize refuse taxonomy

**Scope:** After OSA-S00, `portOwnedByForeignProcess` is unreachable. Remove the
error case from `OpenCodeServeCoordinatorError`, the `serveFailure` mapping,
and any associated tests. Formalize the closed list of refuse cases.

**Refuse taxonomy (exhaustive — closed list):**

| Case | Health probe | Port listener | Action |
| --- | --- | --- | --- |
| Healthy serve (ours or leftover) | pass | yes | Attach |
| Dead/zombie serve | fail | yes | `healthCheckTimedOut` — refuse, no SIGTERM |
| Non-OpenCode process on port | fail (non-HTTP response) | yes | `healthCheckTimedOut` — refuse, no kill |
| Port free | n/a | no | Spawn as today |

No new error type needed. The existing `healthCheckTimedOut` covers all refuse
cases. Neither case implies the process is "foreign" or "ours" — only whether
the port is usable.

**Code changes:**
1. `OpenCodeServeCoordinator.swift:7` — remove `portOwnedByForeignProcess(listenerPID:)`.
2. `OpenCodeRoutingWorkerRunner.swift:93–94` — remove the `portOwnedByForeignProcess` case from `serveFailure`.
3. `OpenCodeRoutingWorkerRunner.swift:86–100` — verify all remaining cases are correct (they are).

**Works Test:**
```
Given:  listener on :4096, health probe fails
When:   ensureRunning is called
Then:   throws healthCheckTimedOut (not portOwnedByForeignProcess)
        listener process is NOT SIGTERM'd

Given:  listener on :4096, response is non-2xx or non-HTTP
When:   ensureRunning is called
Then:   throws healthCheckTimedOut
        listener process is NOT killed
```

---

### OSA-S02 — Dogfood proof + help/doc cleanup

**Scope:**
1. Run the double-run repro (see Works Test below) on a Go seat. Both invocations
   must succeed without manual `:4096` cleanup.
2. Audit `HelpTopicRegistry` (Allnighter), doctor output, and any agent-facing
   error strings for references to `portOwnedByForeignProcess` or "kill the
   leftover serve" / "clear port" guidance. Replace with "the serve will be
   reused" or equivalent.

**Code changes:**
- `HelpTopicRegistry.swift:402–403` — replace "A manual orphan serve fails with
  `portOwnedByForeignProcess`" with wording that reflects attach behavior.

**Works Test (integration):**
```
Given:  :4096 free, driver opencode ready (Go seat)
When:   Two sequential alln run invocations on any OpenCode model complete
        without manually clearing :4096 between them
Then:   Both succeed; second never reports "port owned by pid"
And:    A healthy serve left running is reused (attach), not SIGTERM'd
And:    No agent-facing text advises killing leftover pids
```

---

### OSA-S03 — Closeout

- [ ] Verify Works Tests for S00–S02 pass.
- [ ] Promote attach law into durable docs (help topic + `docs/operations/` if applicable).
- [ ] Verify AGENTS.md row is correct post-implementation.
- [ ] Archive this packet to `docs/archive/phases/OpenCode_Serve_Attach.md`.
- [ ] Remove row from `docs/phases/README.md` forward board; add to recently archived.

---

## 4. Code touch points

| File | Method / area | Slice |
| --- | --- | --- |
| AgentOS `OpenCodeServeCoordinator.swift:102` | `ensureRunning` — delete `refuseForeignListenerIfNeeded` call | OSA-S00 |
| AgentOS `OpenCodeServeCoordinator.swift:104` | `ensureRunning` — replace `isOwnedAndHealthy` with `isHealthy` | OSA-S00 |
| AgentOS `OpenCodeServeCoordinator.swift:166–169` | Delete `refuseForeignListenerIfNeeded()` | OSA-S00 |
| AgentOS `OpenCodeServeCoordinator.swift:172–185` | Replace `isOwnedAndHealthy()` with simplified health-only check | OSA-S00 |
| AgentOS `OpenCodeServeCoordinator.swift:7` | Remove `portOwnedByForeignProcess` error case | OSA-S01 |
| AgentOS `OpenCodeRoutingWorkerRunner.swift:93–94` | Remove `portOwnedByForeignProcess` from `serveFailure` | OSA-S01 |
| Allnighter `HelpTopicRegistry.swift:402–403` | Replace orphan-serve-fails text | OSA-S02 |

---

## 5. Works Tests (summary)

| Slice | Test | Type |
| --- | --- | --- |
| OSA-S00 | Healthy foreign listener → attach, no spawn | Unit (AgentOS) |
| OSA-S00 | Unhealthy foreign listener → `healthCheckTimedOut`, no SIGTERM | Unit (AgentOS) |
| OSA-S01 | `portOwnedByForeignProcess` removed from error enum + mapping | Compile |
| OSA-S02 | Double `alln run` succeeds without port cleanup (Go seat) | Integration (dogfood) |
| OSA-S02 | No agent-facing text advises killing leftover pids | Audit |

---

## 6. Done when

- [ ] OSA-S00 merged: `ensureRunning` attaches healthy serve regardless of `currentSpawnedPID`
- [ ] OSA-S01 merged: `portOwnedByForeignProcess` removed from compile surface
- [ ] OSA-S02 merged: dogfood double-run passes + help text cleaned
- [ ] OSA-S03 merged: promote + archive
- [ ] CT-05 intent preserved: no SIGTERM of a healthy listener on the port
- [ ] Sequential OpenCode `alln run`s succeed without manual `:4096` cleanup

---

## 7. Open questions

None. Former question (fate of `portOwnedByForeignProcess`) closed: **remove in OSA-S01**.
