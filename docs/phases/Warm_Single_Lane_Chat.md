# Warm Single-Lane Chat — Latency Parity, One CLI at a Time

**Status:** PLAN (2026-06-21). Evidence proven; build not started.
**Scope:** SINGLE-LANE CHAT ONLY (one model, one thread, one worker). **Send-to-Team is explicitly
OUT of scope** — it is a fundamentally different beast (N parallel models, users already expect it to
take longer, warming N processes is a separate resource problem). Do not let team concerns shape this.
**Companion:** diagnosis in [`Run_Latency_Findings.md`](./Run_Latency_Findings.md); conversation
memory in [`Worker_Session_Continuity.md`](./Worker_Session_Continuity.md).

---

## 1. Why this exists (CODE RED)

We have zero users. A single-lane chat turn in the Allnighter repo takes **~22–26s of dead air**
before the model says a word, while the *interactive* grok CLI in the same folder answers a follow-up
**in <1s**. Nobody will use a tool that is 20× slower than the CLI they already have open. This is the
single most important latency fix in the product.

### Root cause (benchmarked, not guessed)
Allnighter spawns a **fresh `<cli> -p` process per turn**, pointed at the repo root, so every turn pays
a **cold agent-runtime boot + full working-tree walk**. The Allnighter repo has **1,421 tracked files
but 17,143 total on disk** (mostly gitignored `.build/`, 527M) — grok walks all of it, every turn. The
interactive CLI is fast because it keeps a **warm process** (index + tools + auth loaded once). We use
these CLIs as one-shot cold invocations when they are built to be warm long-lived sessions. `--resume`
fixes conversation *memory*; it does **not** skip the cold boot.

Ruled out by benchmark (NOT the cause): our flags, output format, the agentic loop (`--max-turns 1`),
`.claude`/`Agents.md` config, sandbox, MCP.

### Evidence table (grok-build, "say hi", in the Allnighter repo)
| Path | turn latency | notes |
|---|---|---|
| Cold `grok -p --cwd <repo>` (TODAY) | **~22–26s** | fresh boot + walk every turn |
| Cold `grok -p` in a clean dir | ~6–7s | the cold floor (model + auth, no walk) |
| Cold `grok -p` in **lean view** (tracked − ignored, 1,428 files) | **~7.6s** | materialize 1.5s + run; agent still reads real files (verified: returned `WorkerPrompt`) |
| **Warm persistent process**, turn 1 | ~6s | one-time boot/walk |
| **Warm persistent process**, turn 2 | ~4.7s | settling |
| **Warm persistent process**, turn 3 | **~0.7s** | sub-second — parity with interactive |

**Conclusion:** keeping the process warm collapses turn latency from ~22s to **sub-second by turn 3**.
The physics is proven (PTY spike, mechanism-agnostic). The remaining work is *integration*.

---

## 2. Target state (parity)

> Single-lane chat in `~/Documents/GitHub/Allnighter` feels like interactive grok in that folder:
> first reply in a few seconds, every follow-up near-instant, full project knowledge.

NOT parity with `grok -p "hi" --cwd <repo>` in a fresh shell — that is the slow product we are
accidentally matching today.

---

## 3. Architecture — two composable layers + a uniform abstraction

### Layer A — Lean context view (cold-start tax reducer)
Materialize the **current** working tree minus ignored bulk into a per-thread cached directory, and
point a cold spawn at THAT instead of the 17k-file repo.
- Files = `git ls-files` ∪ `git ls-files --others --exclude-standard`, copied at **current (dirty)
  content** — NOT `git archive HEAD` (which silently drops uncommitted work).
- Inject a dirty-state summary (`git status --short`, `git diff --stat`) into the turn prompt so the
  agent knows the real state even though the FS view omits build junk.
- Cache per thread; re-materialize only when the tree changes; delete on thread idle.
- Proven: 22s → 7.6s, fidelity preserved.
- **Read-only turns only.** Never run a mutating turn against a throwaway view (edits would be
  stranded). Mutating execution is out of scope here anyway (chat is read-only).

### Layer B — Warm worker process (boot tax reducer; the parity fix)
Keep **one** persistent CLI process alive per single-lane chat thread; pipe turns into it.
- First turn warms (boot + index once); every later turn is model-thinking time only → sub-second.
- Driven via each CLI's **clean** warm interface (grok: `agent serve` local WebSocket, `--bind`,
  `--secret`). NOT a PTY screen-scrape in production (PTY was only the spike to prove the physics).
- Lifecycle: spawn → health-check → deliver turn → stream back → idle-teardown → crash-restart.
- Resource discipline (same pattern IDEs use for language servers): warm only **active** thread(s),
  idle-TTL teardown, hard cap on concurrent warm workers, LRU eviction.

### Composition (so the user never eats the 22s)
On thread open / first message:
1. Start the warm worker booting **in the background** (pointed at the real repo root → full fidelity,
   no staleness; it eats the one-time walk once).
2. Answer **turn 1** immediately via a cold lean-view spawn (~7s) as a **bridge**.
3. By **turn 2** the warm worker is ready → route through it → sub-second thereafter.

### Uniform abstraction — `WarmWorker` + per-CLI capability
One protocol; each CLI declares whether it supports a warm mode.
- Warm-capable (grok proven) → warm path.
- No warm mode → **lean-view cold spawn fallback** (still ~7s, still a 3× win).
"Fix for every CLI" = every CLI gets the **fastest mode it actually supports**, behind one interface.
The user-facing result (fast turns) is uniform; the per-CLI plumbing will not be identical, and this
doc will not pretend it is.

---

## 4. Invariants (do not break)
- **Single-lane chat only.** No send-to-team warming here.
- **Execution / mutating path untouched.** Warm chat workers are READ-ONLY. The one-mutating-worker +
  write-lock + execution-lane invariants ([`allnighter-pending-execute-lane-safety`]) stay exactly as
  they are. Mutating turns keep the real root, cold, under the lock; their latency is made *visible*
  (ttftMs), not hidden.
- **Session continuity preserved.** The warm process holds conversation state in-memory; we still track
  the vendor session id so a torn-down/restarted thread resumes via `--resume`.
- **Allnighter does not touch the repo's git/files.** The lean view is an isolated copy under tmp; we
  never `mv` the user's `.build`, never mutate their tree.
- **Agent-first.** Any new surface (warm-worker status, latency) is structured + schema-backed.

---

## 5. Build plan — phased, ONE CLI at a time

### Phase 0 — Foundations (CLI-agnostic, lands before any warm work)
- [ ] **S0 — Lean context view (Layer A).** `ContextViewPolicy { realRoot | leanTrackedView }` +
  `ContextViewMaterializer` (current tree − ignored, dirty content, cached per thread, dirty-summary
  injection). Wire at the run-routing layer so the working dir handed to ANY driver can be the view.
  Non-mutating single-lane chat → lean view. **Acceptance:** cold chat turn in the Allnighter repo
  drops ~22s → ~7s; agent still reads real files.
- [ ] **S1 — `WarmWorker` abstraction + lifecycle skeleton.** Protocol (spawn/health/deliver/
  streamback/teardown), a registry keyed by thread, resource cap + idle-TTL + LRU, crash-restart hook.
  No CLI bound yet; unit-tested with a fake warm worker.
- [ ] **S2 — Latency surface + regression harness.** `ttftMs`/`queueMs` already captured (shipped) —
  surface them (warm-vs-cold visible to user + an `alln`/MCP read). Commit a **variance-controlled**
  bench (`scripts/cli-latency-bench`: serialized, median-of-N, stray-process guard) so we never again
  trust a noisy one-off. **Acceptance:** harness reports stable cold/lean/warm numbers per CLI.

### Phase 1 — grok (the proof-of-concept; everything downstream copies this)
- [ ] **S3 — grok warm adapter.** Stand up `grok agent serve` (local WS, `--bind`, `--secret`),
  discover the WS message protocol, drive turn-1 + turn-2 from a client. **Acceptance:** turn-2 < 2s
  through the WS (target sub-second), matching the PTY spike.
- [ ] **S4 — Wire single-lane chat → grok warm worker.** On thread open, boot the warm worker in the
  background; bridge turn-1 via lean-view cold spawn; route turn-2+ through the warm worker. Conversation
  continuity intact. **Acceptance:** in the Allnighter repo, turn-1 < 8s, turn-2+ < 2s, end-to-end in
  the app.
- [ ] **S5 — Hardening.** Crash-restart (warm dies mid-thread → transparent restart + `--resume`),
  idle-teardown, resource cap under multiple open threads, auth/token refresh over long sessions.
  **Acceptance:** kill the warm process mid-thread → next turn recovers without user-visible failure.

### Phases 2…N — each remaining CLI, in order (copy the grok pattern)
For EACH CLI: **(a) de-risk spike** (does a warm process reach sub-second? what's the warm interface?)
→ **(b) warm adapter** → **(c) wire** → **(d) harden** → **(e) acceptance**. A CLI with no usable warm
mode falls back to the S0 lean view (already shipped) — still a 3× win, no extra work.

- [ ] **Phase 2 — claude (Claude Code).** Spike: persistent/SDK/server mode? (`--print` is one-shot;
  investigate the Agent SDK / a long-lived process.) Warm interface TBD.
- [ ] **Phase 3 — codex.** Spike: `codex exec` is one-shot; does the interactive/TUI mode warm? Warm
  interface TBD.
- [ ] **Phase 4 — cursor (`agent`).** Spike: persistent server mode? Warm interface TBD.
- [ ] **Phase 5 — antigravity (`agy`).** Spike: persistent mode? (Already on `session_dir` continuity.)
  Likely lean-view fallback if no warm mode.

---

## 6. Acceptance criteria (the whole effort)
- Single-lane chat, grok, Allnighter repo: **turn-1 < 8s, turn-2+ < 2s** (target sub-second).
- Every supported CLI: at minimum the lean-view 3× win; warm path where the CLI supports it.
- **Zero regression** to execution/mutating, write-lock, execution-lane, session continuity.
- Variance-controlled regression harness green; warm-vs-cold latency visible in the product.

---

## 7. Open questions / risks (settle per phase, don't block the whole plan)
1. **grok WS protocol** — undocumented message format; discover in S3 (sniff the interactive client or
   read grok docs). The *surface* (`agent serve` + secret) is clean; only the wire format is unknown.
2. **Index staleness** in a long-lived warm process — if the user edits files mid-thread, the warm
   index is stale. Mitigation: the agent reads live files on demand via tools; inject fresh `git status`
   each turn. Acceptable for chat; revisit if it bites.
3. **Resource cap policy** — how many concurrent warm workers, idle TTL. Start conservative
   (e.g. ≤3 warm, 10-min idle teardown), tune with data.
4. **Per-CLI warm capability** — some CLIs may have no clean warm mode → lean-view fallback. That is an
   acceptable, documented outcome, not a failure.
5. **Crash/auth over long sessions** — warm process dies or token expires → transparent restart +
   `--resume`. Covered in S5.
6. **First-turn bridge correctness** — turn-1 (lean view, isolated tmp path) vs turn-2+ (warm, real
   root) run in different cwds. For read-only chat this is fine, but verify nothing leaks a tmp path the
   user sees as canonical.

---

## 8. What we are NOT doing
- NOT warming send-to-team (out of scope; different beast).
- NOT running mutating turns against a lean view (edits would be stranded).
- NOT `mv`-ing the user's `.build` aside (mutates their tree; crash-unsafe).
- NOT betting the product on upstream CLI fixes (`git ls-files` fast path, `.grokignore`, index cache
  are worth pushing in parallel, but we ship without them).
- NOT shipping chat from `/tmp` with no project context (the lean view IS the project, minus build junk).
