# OpenCode Serve Attach

Status: **Ready for Implementation — not started**
Owner: AgentOS (`OpenCodeServeCoordinator` / `OpenCodeRoutingWorkerRunner`)
Created: 2026-08-08
Origin: Dogfood — after a successful `alln run` on driver `opencode`, a healthy
`opencode serve` often remains on `127.0.0.1:4096`. The next `alln run` (new
process) refuses with `opencode serve busy: port owned by pid …` instead of
attaching. Affects **all** OpenCode seats (Go, Zen, local providers) — not an
Ollama-specific defect.

Related: [`OpenCode_Long_Run_Continuity.md`](OpenCode_Long_Run_Continuity.md)
(warm serve + spawn lock), CT-05 foreign-listener refuse in
`OpenCodeServeCoordinator`.

Phases are ephemeral. At closeout: promote the attach law into help / operations;
code remains SSOT; archive this packet.

---

## 1. One claim

`ensureRunning` for OpenCode means: **if `:4096` is healthy, use it; else start
it once.** A healthy listener is never “busy” merely because this `alln`
process did not spawn it.

Trusted workflow:

```text
alln run … --model <any opencode seat>   # starts or attaches to serve
  → run completes
  → opencode serve may still listen on :4096
alln run … --model <any opencode seat>   # MUST attach and succeed
  → never: opencode serve busy: port owned by pid <leftover>
```

---

## 2. Product law (binding)

OpenCode on Allnighter is a **warm shared seat server**, not a per-run child CLI.

| Law | Meaning |
| --- | --- |
| **Attach** | Healthy `:4096` ⇒ reuse. Ownership is port + health, not “which process forked the pid.” |
| **Start if missing** | No healthy listener ⇒ spawn `opencode serve` once. |
| **Do not tear down per run** | Per-run teardown fights the warm-serve design and breaks Go + other providers sharing one serve. |
| **Do not SIGTERM healthy listeners to “make room”** | CT-05 intent preserved: never kill a live OpenCode to clear the port. |
| **Refuse only when truly unusable** | Unhealthy listener, wrong process shape, or proven contended incompatible owner — not “foreign PID” alone. |

**Rejected alternative:** tear down the serve after every `alln run`. Wrong altitude:
cold-starts every turn, nukes a shared Go/local lane, and still needs attach for
humans / leftovers / `--no-wait` process exits.

---

## 3. Defect (live code)

Code SSOT (AgentOS):

- `OpenCodeServeCoordinator.refuseForeignListenerIfNeeded` — if this process has
  no `currentSpawnedPID` but `lsof` shows a listener on `:4096`, throw
  `portOwnedByForeignProcess`.
- `OpenCodeRoutingWorkerRunner.serveFailure` maps that to
  `opencode serve busy: port owned by pid \(pid)`.

That refuse was aimed at **not killing** another live OpenCode (CT-05). It overreached:
a leftover serve from a **prior successful Allnighter-owned run** is healthy shared
infrastructure, not a foreign threat. Process-local spawn memory cannot survive
`--no-wait` / multi-process reality, so “I didn’t spawn this pid” is the wrong
identity check.

Repro (model-independent):

```text
1. Ensure :4096 free
2. alln run "<trivial prompt>" --model <opencode seat> --json --no-wait
3. Attach/show until done — PASS
4. lsof -iTCP:4096 -sTCP:LISTEN  → opencode still up
5. alln run "<trivial prompt>" --model <same or other opencode seat> …
6. FAIL: opencode serve busy: port owned by pid …
```

---

## 4. Fix shape (one slice)

**Truth owner:** AgentOS `OpenCodeServeCoordinator.ensureRunning` / health path.

**Change:** When a listener is already on `defaultPort` and **health check passes**,
treat it as the warm serve — adopt/attach (record listener pid if useful for
diagnostics) and proceed to `OpenCodeServeClient.streamRun`. Do **not** throw
`portOwnedByForeignProcess` solely because `currentSpawnedPID == nil`.

**Keep refusing when:**

- health check fails (dead/hung serve), or
- a future typed case proves the listener is incompatible (document the predicate;
  do not invent “kill it”).

**Non-goals:**

- Idle TTL redesign (already exists; orthogonal)
- Changing `OpenCodeSpawnLock` cross-process mutex semantics (still one hammer)
- Ollama / provider / catalog work
- Killing `alln serve` or any non-OpenCode daemon
- Teaching agents to `kill` leftover pids as the product fix

---

## 5. Works Test

```text
Given: :4096 free, driver opencode ready
When:  two sequential alln run invocations on any OpenCode model complete
       without manually clearing the port between them
Then:  both succeed; second never reports port owned by pid …
And:   a healthy serve left running is reused (attach), not SIGTERM’d
```

Negative: if something non-healthy holds the port, fail closed with a clear
reason — still no automatic SIGTERM of a healthy listener.

Proof: filtered AgentOS / Allnighter tests around coordinator attach + one live
dogfood double-run on any OpenCode seat (Go is enough).

---

## 6. Done when

- [ ] Sequential OpenCode `alln run`s succeed without manual `:4096` cleanup
- [ ] CT-05 preserved: no SIGTERM of healthy foreign/live OpenCode to clear port
- [ ] Help or doctor text (if any) does not tell agents to kill leftover serves as the fix
- [ ] Promote attach law; archive this packet

---

## 7. Ops note (agents)

`alln serve` (scheduler daemon) is **not** `opencode serve` (`:4096`). A terminal
run’s `identityAlive` may point at long-lived `alln serve` — never kill by pid
without `ps`. Clearing a stuck **OpenCode** leftover is a temporary human
workaround only until this packet ships; the product fix is attach.
