# OpenCode Smoke / Probe Blocker — Investigation Handoff

Status: **RESOLVED — OC-B0 + OC-B1 complete; OpenCode works end to end (HTTP-API driver)**
Owner: (done — see commits daedc2e2, 884452e1, 749df0ee)
Updated: 2026-06-26
Severity: **T2 SSOT** (setup truth vs lie-prone probe layer)

Related:
- Driver SSOT: [`setup/OpenCode_CLI_Support.md`](setup/OpenCode_CLI_Support.md)
- Sprint slices (code landed): [`sprint/opencode/`](sprint/opencode/)
- Pair programming (separate track, historical — slice queue deleted R-S09): [`PM_Relay.md`](PM_Relay.md)
- Debugger intake: [`operations/Debugger.md`](../operations/Debugger.md)

---

## Executive summary (zoom out)

**We shipped OC-S01 plumbing** (coordinator, extractor, detector hooks, manifest, unit
tests). **We did not prove the headless integration contract.**

OpenCode was modeled as **Antigravity-class** (final stdout = answer). Live evidence
says headless `opencode run --attach` often returns **empty stdout** with only TUI-style
metadata on stderr (`> build · model · …`). The setup probe checks **stdout only** →
permanent `Probe failed` even when the interactive TUI path works fine.

**Wrong level of fixes attempted:** patch symptoms in `CLIDetector`, `TextUtil`,
`resolvedCommandString`, Mac setup UX, timeouts, and founder manual `opencode serve`.
**Right level:** decide and implement how Allnighter **owns the OpenCode answer channel**
for non-interactive probe + runs — then freeze fixtures and gate CI.

Until that contract is proven CLI-to-CLI, the Mac setup card will keep lying.

---

## RESOLUTION — OC-B0 done, channel proven live (2026-06-26)

**Root cause (proven, not hypothesized):** `opencode run` is a **TTY-interactive TUI
client**, not a headless answer emitter. Piped into a non-TTY subprocess it produces
**zero bytes on stdout AND stderr** — even with `--format json` and `--print-logs` — and
**does not exit** (hangs until killed). It is the wrong tool for automation in *any* output
mode. The earlier "stdout empty / footer regex / `{{workingDir}}`" theories were all
downstream of this: there is no answer on stdout to extract because `run` never renders
without a terminal. (The doctor's "~24s exit" vs the spike's "hangs" is just TTY/Bun
buffering variance — same defect.)

**The real answer channel:** `opencode serve` exposes a **complete documented HTTP API**
(`GET /doc` → OpenAPI 3.1). The TUI is merely a client of it. The answer is obtained
synchronously over HTTP:

```text
POST /session                         -> { "id": "ses_…" }
POST /session/{id}/message            -> { "info": {...}, "parts": [ … ] }
  body: { "model": {"providerID":"featherless","modelID":"<id>"},
          "parts": [ {"type":"text","text":"<prompt>"} ] }
answer = parts.first(where: type=="text").text     // e.g. "ALLNIGHTER_READY"
```

**Proven live, both probe models, in seconds, clean structured text:**

| Model | result |
| --- | --- |
| `featherless/Qwen/Qwen3-Coder-Next` | `parts[type=text].text == "ALLNIGHTER_READY"`, out_tokens 6 |
| `featherless/zai-org/GLM-5.2` (actual probe model) | `parts[type=text].text == "ALLNIGHTER_READY"`, out_tokens 7 |

Response shape is `[step-start, text, step-finish]`; the assistant answer is the `text`
part. No ANSI, no footer, no `> build ·` noise — `TextUtil.extractOpenCodeVisibleText`
is **unnecessary** for OpenCode (it was solving a problem that only exists in the TUI path).

### The law (the one paragraph OC-B0 asked for)

```text
Allnighter treats the assistant `text` part of POST /session/{id}/message (opencode
serve HTTP API) as the OpenCode answer — for BOTH the smoke probe AND worker runs.
OpenCode is an HTTP-API driver, NOT a headless stdout-scrape (Antigravity-class)
driver. `opencode run` is never spawned for automation; readiness/answers are never
inferred from its stdout.
```

### Revised OC-B1 (supersedes the A/B/C/D decision tree below — pick is made)

OpenCode is reclassified from `headless_cli` (spawn + scrape stdout) to an **HTTP-API
driver** against the warm serve `ensureRunning()` already starts.

1. **`OpenCodeServeClient`** (new, or extend `OpenCodeServeCoordinator`): `createSession(directory:)`
   → `sendMessage(sessionID:, prompt:, providerID:, modelID:) async throws -> String`
   (collect `parts` where `type=="text"`, join). Base `http://127.0.0.1:4096`.
2. **Smoke** (`CLIDetector.smokeClassify` / `ModelHealthChecker.smokeTest`): for
   `manifest.id=="opencode"` → `ensureRunning()` → `sendMessage(prompt: smoke, model: probe)`
   → `contains(ALLNIGHTER_READY)`. Delete the `opencode run` subprocess + stdout path.
3. **Runs** (`WorkerRunner.invoke`): same client; create/reuse a session at repo root,
   POST the prompt, return the joined `text` parts as the answer. Capture `info.tokens`
   for timing/usage. For long executor runs (pair hammer), use `POST /session/{id}/prompt_async`
   + `POST /session/{id}/wait` instead of holding a synchronous connection for ~10 min.
4. **Permissions:** headless must auto-approve — set it via session/config (the API has
   `/session/{id}/permission…`); equivalent of `--dangerously-skip-permissions`.
5. **Manifest:** the `smokeTestCommand` / `invoke` `opencode run --attach …` lines are dead
   for automation. Either add an `http` manifest kind, or carry the base URL + model and
   route opencode through the client. `--dir` becomes the session `directory`.

### Reproduce (no Allnighter code)

```bash
BASE=http://127.0.0.1:4096
SID=$(curl -s -X POST $BASE/session -H 'content-type: application/json' -d '{}' \
      | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
curl -s -X POST $BASE/session/$SID/message -H 'content-type: application/json' -d '{
  "model":{"providerID":"featherless","modelID":"zai-org/GLM-5.2"},
  "parts":[{"type":"text","text":"Reply with the single token ALLNIGHTER_READY"}]}' \
  | python3 -c 'import json,sys;d=json.load(sys.stdin);print([p["text"] for p in d["parts"] if p["type"]=="text"])'
# -> ['ALLNIGHTER_READY']
```

### OC-B1 COMPLETE (run path) — 2026-06-26

`WorkerRunner.invoke` now routes opencode through `OpenCodeServeClient` (commit
`749df0ee`). The session is rooted at the run's working dir (`POST /session?directory=…`)
and all tool permissions are auto-approved (`permission:[{*,**,allow}]`), so headless
tool-use never blocks. Proven live, full stack:

| Path | Result |
| --- | --- |
| `alln doctor --agent opencode --full` | authenticated ✓ |
| `alln run --worker model_opencode_qwen3_coder_next` | returned `OPENCODE_RUN_OK` in 4.3s ✓ |
| `alln run --lane code` (execute) | worker wrote a file in the project repo (`EXEC_OK`), auto-approved ✓ |

Remaining (non-blocking) follow-ups: streaming via `/event` SSE + `prompt_async`/`/wait`
for long executor runs (captures ttftMs); `ReasoningPart` already captured into
`WorkerRunOutcome.reasoning`; reclassify the manifest off `headless_cli` (the
`smokeTestCommand`/`invoke` `opencode run` strings are dead — detect still uses
`opencode --version`).

Everything below predates the resolution; kept for history.

---

## What works (proved)

| Layer | Evidence |
| --- | --- |
| `opencode` binary | `opencode --version` → **1.17.11** |
| `opencode serve` | `curl http://127.0.0.1:4096/` → **200** (HTML UI) |
| Featherless BYOK | `~/.config/opencode/opencode.json`; `OPENAI_API_KEY` via `~/.aider.env` |
| Interactive TUI | `opencode run --attach …` in terminal: **~2–4s hi**, GLM/Qwen respond |
| Pair hammer (manual) | GLM delivered OC-S01a/b/c slices with sprint docs (stall/nudge learning) |
| Unit tests (offline) | `OpenCodeVisibleTextTests`, injected `OpenCodeServeCoordinatorTests` pass |
| Serve coordinator code | `OpenCodeServeCoordinator.ensureRunning()` compiles; health GET 127.0.0.1:4096 |

---

## What fails (symptom)

| Surface | Symptom |
| --- | --- |
| Mac Setup → OpenCode | **Probe failed** — `smoke did not return ALLNIGHTER_READY` |
| `alln doctor --agent opencode --full` | `status: critical`; auth check **degraded** |
| Models on card | GLM / Qwen toggles ON but probe still red |

**Latest `alln doctor --full` detail (2026-06-26):**

```text
smoke did not return ALLNIGHTER_READY (stdout empty)
· stderr: > build · zai-org/GLM-5.2
```

Probe duration ~**24s** (not a 60s timeout — process exits quickly with empty answer).

---

## Fingerprint

```text
OpenCode setup smoke + headless attach run + stdout-empty / stderr-metadata-only
→ probeFailed despite working interactive TUI
```

**Truth owner (should be):** driver output contract + smoke capture path in Core.  
**Lie-prone layer:** `CLIDetector.smokeClassify` treating stdout-only `contains(ALLNIGHTER_READY)` as readiness.

---

## Architecture mismatch (the real issue)

### Antigravity / Claude / Grok (works today)

```text
subprocess → stdout → strip/extract → smokeTestExpect match → ready
```

### OpenCode V1 assumption (may be wrong)

```text
opencode serve (warm)
→ opencode run --attach URL … (per probe/run)
→ stdout → extractOpenCodeVisibleText → expect token
```

### What live behavior suggests

| Observation | Implication |
| --- | --- |
| Interactive TUI shows answer + `> Build · model · Ns` footer | Human path works |
| Headless probe: **stdout empty**, stderr has lowercase `> build · …` | Answer may not land on stdout in attach batch mode |
| Prior spike: `--format json` often only `step_start` | Formatted stdout unreliable for automation |
| Prior spike: answer recoverable via **`opencode export`** | Session store may be truth; stdout is not |
| Probe model = **GLM 5.2** (`strengthRank` 75 > Qwen 70) | Smoke uses GLM even when founder tests Qwen in TUI |

**Hypothesis (primary):** smoke checks the wrong channel. Fixing `TextUtil` footers or
`{{workingDir}}` alone cannot pass until we read the same channel the TUI displays.

**Hypothesis (secondary):** probe model selection (`selectProbeLabel` → GLM) is a bad
default for smoke (slower, think-heavy, Featherless busy errors).

**Hypothesis (tertiary):** `OpenCodeServeCoordinator` spawn from XCTest **SIGSEGV** —
live serve from app/probe works; test harness spawn is unsafe (skipped).

---

## What was built (OC-S01 — commit `31a6704b` + uncommitted follow-ups)

| Component | Path | Notes |
| --- | --- | --- |
| Manifest | `Apps/AllnighterMac/Resources/Drivers/opencode.json` | `serve`+`attach`, smoke command |
| Embedded manifest | `DefaultConfig.swift` | CLI `alln` when Mac bundle not loaded |
| Extractor | `TextUtil.extractOpenCodeVisibleText` | Strips `> Build ·` footers (case-sensitive `Build`) |
| WorkerRunner | finalize + `invoke` `ensureRunning` | OC-S01b/d |
| CLIDetector / ModelHealthChecker | `ensureRunning` + extractor on smoke | OC-S01d |
| Coordinator | `OpenCodeServeCoordinator.swift` | Port 4096, health poll |
| Sprint docs | `docs/phases/sprint/opencode/OC-S01a–d` | Pair hammer work orders |
| Aider archived | `docs/archive/phases/setup/Aider_CLI_Support.md` | Rejected driver |

**Uncommitted at handoff (local only):**

- `{{workingDir}}` substitution in `resolvedCommandString` (real bug, fixed locally)
- OpenCode smoke timeout **180s** in detector/health checker
- Richer `smokeTokenMissReason` (stdout/stderr snippet in probe reason)
- Mac setup UX: per-driver reprobe, **Copy log**, reprobing Last proof (partial)
- Live coordinator XCTest → permanent `XCTSkip`

---

## Chronology — what we tried and what failed

### 1. Aider driver → rejected

Autonomy / per-file approval unsuitable. Archived.

### 2. OpenCode + Featherless + GLM pair programming

- Sprint docs + manual GLM hammer: **slices can land** (OC-S01a/b/c) with tight packets.
- GLM stalls on ambiguity (OC-S01a); compaction spirals if scope creeps.
- **Not the probe blocker** — separate learning track.

### 3. OC-S01 driver plumbing

- Landed coordinator, extractor, wiring. **Unit tests green.**
- **Did not** make `alln doctor --full` pass.

### 4. Founder manual `opencode serve`

- Confusion: product should auto-start serve (`ensureRunning`).
- Second `serve` on :4096 → `ServeError` (port in use) — looks broken, is benign.
- **Not root cause** of smoke miss when serve is already up.

### 5. `{{workingDir}}` not substituted in smoke command

- Smoke ran with literal `--dir "{{workingDir}}"`.
- Fixed in `DriverManifest.resolvedCommandString` (uncommitted).
- **Doctor still fails** with correct workingDir — stdout still empty.

### 6. Timeout increases (60s → 180s)

- Doctor failed in **~24s** with empty stdout — not a timeout problem.

### 7. `TextUtil` footer patterns

- Expects `> Build ·` (capital B); doctor stderr shows `> build ·` (lowercase).
- Even if stderr were checked, case mismatch would fail.
- **Probe only inspects stdout today** — stderr footer is diagnostic noise.

### 8. Mac “View log” / probe UX

- Button silently copied one line; felt broken.
- Reprobing showed no in-progress state while `isDetecting` true.
- UX fixes help honesty; **do not fix empty stdout**.

### 9. Automated/manual headless smoke captures

- Long-running `opencode run --attach … ALLNIGHTER_READY` often **hangs minutes** with
  little stdout in automation context.
- Contradicts quick ~24s doctor failure — suggests **environment/path dependent**
  behavior worth re-measuring with frozen commands.

---

## CLI-to-CLI reproduction (next owner should run)

**Prerequisites:** `opencode` 1.17.11, Featherless key loaded, no stale serve confusion.

```bash
# 1. Serve health (optional — coordinator should also do this)
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:4096/

# 2. Doctor (quota-free vs full)
cd /path/to/Allnighter
swift run --package-path Packages/AllnighterCore alln doctor --agent opencode --json
swift run --package-path Packages/AllnighterCore alln doctor --agent opencode --full --json

# 3. Resolve probe scratch dir (same as CLIDetector)
# ~/Library/Application Support/Allnighter/probe-scratch  (see AllnighterPaths.probeScratch)

# 4. Exact smoke command (model label from probeModelLabel — currently GLM)
PROBE="$HOME/Library/Application Support/Allnighter/probe-scratch"
mkdir -p "$PROBE"
opencode run --attach http://127.0.0.1:4096 \
  --dir "$PROBE" \
  'Reply with the single token ALLNIGHTER_READY' \
  --dangerously-skip-permissions \
  -m 'featherless/zai-org/GLM-5.2' \
  > /tmp/oc-smoke-out.txt 2> /tmp/oc-smoke-err.txt
echo exit=$?
wc -c /tmp/oc-smoke-out.txt /tmp/oc-smoke-err.txt
cat /tmp/oc-smoke-out.txt
cat /tmp/oc-smoke-err.txt

# 5. Repeat with Qwen (founder default)
# -m 'featherless/Qwen/Qwen3-Coder-Next'

# 6. If stdout empty — try export (spike path)
opencode export   # after run; document session id / attach semantics per OpenCode 1.17 docs
```

**Capture and commit** real stdout/stderr/exit/json-export into
`Packages/AllnighterCore/Sources/AllnighterCore/Resources/Fixtures/` before changing
extractor or smoke logic again.

---

## Wrong level vs right level

| Wrong level (already tried) | Right level (not done) |
| --- | --- |
| Patch `TextUtil` footer regex | **Define OpenCode headless answer SSOT** (stdout vs export vs json events) |
| Bump smoke timeout | **Prove capture path** with frozen live fixtures |
| Mac Copy log / reprobing UI only | **Probe uses same path as WorkerRunner final answer** |
| Ask founder to run `opencode serve` manually | **Document + test `ensureRunning` idempotency** (spawn vs reuse) |
| Assume Antigravity one-shot | **Spike `opencode acp` / export / `--format json` end-state** per official docs |
| Pick probe model via `strengthRank` | **Explicit probe model policy** for OpenCode (e.g. always Qwen smoke) |

---

## Recommended next steps (ordered)

### OC-B0 — Integration spike (no Allnighter code)

1. Run reproduction script above; save **three** artifacts: success TUI transcript,
   headless stdout/stderr, `opencode export` output if stdout empty.
2. Read OpenCode 1.17 docs: `run`, `attach`, `serve`, `export`, `--format json`.
3. Write **one paragraph law**: “Allnighter treats X as the final answer for OpenCode.”

### OC-B1 — Contract implementation

Depending on B0 outcome (pick one, do not hedge):

- **A)** Post-run `opencode export` (or session API) in `WorkerRunner` + smoke.
- **B)** JSON event stream parser until terminal `text` event (not `step_start` only).
- **C)** Change smoke to health-only when attach works (weaker — loses model proof).
- **D)** Defer OpenCode setup green until **ACP driver** (V2 in SSOT).

### OC-B2 — Gate

- Fixture-backed test for chosen channel (no live network in CI).
- Live Works Test: `alln doctor --agent opencode --full` green on founder machine.
- Mac setup card green without manual terminal steps.

### OC-B3 — Product cleanup

- Pin smoke model to Qwen (or enabled bench model), not `strengthRank` default.
- Merge uncommitted OC-S01 follow-ups or drop if superseded by B1.
- Remove founder-facing “run serve in another tab” from all docs.

---

## Open questions for founder / next engineer

1. Is **setup smoke** allowed to spend Featherless quota on every Re-check?
2. Accept **weaker smoke** (serve health only) for V1, real model proof on first user run?
3. Pair programming hammer: still OpenCode attach, or bypass setup probe entirely for dev?
4. Should stderr footers participate in extraction (case-insensitive `> build ·`)?

---

## Key files

| Area | Path |
| --- | --- |
| Driver SSOT | `docs/phases/setup/OpenCode_CLI_Support.md` |
| Smoke classify | `Packages/AllnighterCore/Sources/AllnighterEngine/CLIDetector.swift` |
| Extractor | `Packages/AllnighterCore/Sources/AllnighterEngine/TextUtil.swift` |
| Coordinator | `Packages/AllnighterCore/Sources/AllnighterEngine/OpenCodeServeCoordinator.swift` |
| Probe model pick | `Packages/AllnighterCore/Sources/AllnighterCore/ModelCatalog.swift` (`probeModelLabel`) |
| Smoke command | `Apps/AllnighterMac/Resources/Drivers/opencode.json` |
| Mac setup UI | `Apps/AllnighterMac/Sources/ReadinessView.swift` |
| Fixture (stale?) | `Packages/AllnighterCore/.../Fixtures/opencode_stdout_smoke.txt` |

---

## Regression law (draft)

```text
OpenCode readiness must not be inferred from stdout.contains(token) until the
headless capture path is fixture-proven for OpenCode 1.17.x attach mode.
```

Wall candidate: fixture test + `scripts/check.sh` gate once B1 lands.

---

## Works Test status

| Test | Status |
| --- | --- |
| `swift test --filter OpenCodeVisibleText` | **PASS** (synthetic fixture) |
| `swift test --filter OpenCodeServeCoordinator` | **PASS** (injected; live skipped) |
| `alln doctor --agent opencode` (no `--full`) | **PASS** (install only) |
| `alln doctor --agent opencode --full` | **FAIL** (stdout empty) |
| Mac Setup OpenCode card | **FAIL** (same smoke) |
| Interactive `opencode` TUI | **PASS** (founder) |

**Bottom line:** We have **plumbing proof**, not **integration proof**. Next owner
starts at OC-B0, not at another regex tweak.
