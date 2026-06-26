# OpenCode CLI Support (Headless Final Output)

Status: **Ready for OC-S01 implementation**
Owner: AllnighterCore + AllnighterCLI + Mac GUI
Updated: 2026-06-26
Pinned OpenCode version for fixtures: **1.17.11** (founder machine)

**Authoritative sources (official docs win on product behavior; code wins on
Allnighter integration):**

- [CLI](https://opencode.ai/docs/cli/) — `run`, `serve`, `attach`, `--format json`
- [Config](https://opencode.ai/docs/config/) — global `~/.config/opencode/opencode.json`
- [Permissions](https://opencode.ai/docs/permissions/) — autonomy / approval
- Reference driver: `Apps/AllnighterMac/Resources/Drivers/antigravity.json`
- Rejected alternative: `docs/archive/phases/setup/Aider_CLI_Support.md`

## Founder Intent

- OpenCode is an autonomous terminal coding agent with BYOK provider routing.
- V1 posture matches **Antigravity**: **final-output only** — no live token
  streaming in Allnighter (`03_Mac_Streaming.md` excludes OpenCode from V1
  stream-capable drivers).
- OpenCode replaces the archived Aider plan: better vibe coding, same Bench
  model-paste story (`featherless/Qwen/Qwen3-Coder-Next`, etc.).

## Why OpenCode Over Aider

| | Aider (rejected) | OpenCode (V1) |
| --- | --- | --- |
| Autonomy | Pair-edit; `--yes-always` still hits confirm paths; founder blocked on per-file/doc approval during real implementation work | `--dangerously-skip-permissions` or global `"permission": "allow"` — built for agentic runs |
| Headless contract | stdout archaeology (`THINKING`/`ANSWER` markers) | Formatted stdout and/or JSON event stream |
| Warm path | Cold subprocess ~3–6s smoke | `serve` + `run --attach` ~2–4s observed in TUI |
| Allnighter fit | Simple one-shot subprocess | **Warm server required** — not `agy`-trivial, but acceptable for V1 |

## Trusted Workflow Slice

```text
run setup/recheck
-> Allnighter finds `opencode` (`opencode --version`)
-> OpenCodeServeCoordinator ensures `opencode serve` on 127.0.0.1:4096 (user-intent / first spawn)
-> smoke: `opencode run --attach http://127.0.0.1:4096 --dir <repo> …` with BYOK config present
-> user enables OpenCode models on the Bench (built-ins off by default)
-> answer + execution teams: same invoke bundle; mutating posture = write lock + repo cwd
-> WorkerRunner extracts visible answer text after run completes
```

## Non-Goals

- No V1 token streaming / `DriverManifest.streaming` block.
- No automatic OpenCode install or API-key storage inside Allnighter.
- No cold `opencode run` as the primary Mac run path (doctor fallback only).
- No `opencode acp` driver (V2+ — long-lived JSON-RPC subprocess).
- No per-model custom driver work — one `opencode` manifest; users paste
  `provider/model` strings on the Bench.

---

## V1 Integration Model (Antigravity-Class, Not Antigravity-Simple)

**Antigravity:** one-shot `agy --print` → stdout is the answer.

**OpenCode V1:** resident server + attach client per run.

Official CLI docs: start `opencode serve`, then `opencode run --attach
http://localhost:4096 "…"` to avoid MCP/plugin cold boot on every invocation.

Allnighter owns server lifecycle:

| Responsibility | Owner |
| --- | --- |
| Start / reuse `opencode serve --port 4096` | `OpenCodeServeCoordinator` (Mac background coordinator seam) |
| Health | HTTP 200 on `http://127.0.0.1:4096/` or coordinator heartbeat |
| Per-run spawn | `opencode run --attach <url> --dir {{workingDir}} …` |
| Shutdown | App quit / explicit coordinator stop (not per-run) |

`maxConcurrentSpawns: 1` — same concurrency posture as `antigravity` (shared
session DB under `~/.local/share/opencode/`).

---

## Recommended Headless Invocation

### Standard run (answer + execution)

```bash
opencode run \
  --attach "http://127.0.0.1:4096" \
  --dir "<REPO_ROOT>" \
  "<PROMPT>" \
  --dangerously-skip-permissions \
  -m "<PROVIDER>/<MODEL>"
```

Example model labels (Featherless via user `opencode.json`):

- `featherless/Qwen/Qwen3-Coder-Next` (default seed)
- `featherless/zai-org/GLM-5.2`

### Flags (from [CLI docs](https://opencode.ai/docs/cli/))

| Flag | V1 | Why |
| --- | --- | --- |
| `--attach` | **Required** | Warm server path |
| `--dir` | **Required** | Repo root; attach alone uses server cwd |
| `--dangerously-skip-permissions` | **Required** | Autonomous runs; matches agy posture |
| `-m` / `--model` | **Required** | Explicit `provider/model` from Bench |
| `--format default` | **Required** | Final formatted answer on stdout (not `json` for V1 primary path) |
| `--pure` | Optional | Skip external plugins for faster/deterministic smoke |
| `-c` / `--continue` | No | V1 one-shot per turn |

**Do not use `--format json` as the primary V1 parser** — observed truncation
(only `step_start` emitted to stdout while answer lived in session DB). JSON
event parsing is a follow-on / fallback slice.

---

## Output Contract (Final Answer)

### Primary path — default formatted stdout

Capture **stdout** after `opencode run --attach` exits 0. Strip ANSI
(`stripAnsi: true`). Visible answer is the assistant text block (not the
`> Build · model · Ns` status line).

Implement `TextUtil.extractOpenCodeVisibleText` with rules:

1. Strip ANSI.
2. Drop lines matching `^> Build ·` / `^> .+ · .+ · [\d.]+s$` metadata footers.
3. Trim leading/trailing whitespace.
4. If empty after strip, fall through to fallback.

### Fallback A — JSON events (doctor / debug only in V1)

Re-run with `--format json`; concatenate `{"type":"text",…}` `text` fields in
order. Ignore `step_start`, `tool_use`, `thinking`, etc.

### Fallback B — session export

`opencode export <sessionID>` when stdout is empty but exit 0. Parse last
assistant message `parts` where `type == "text"`. Session ID from stderr logs
or future manifest capture hook — **not required for smoke** if primary path works.

### Errors

- Non-zero exit → failed worker.
- Classify auth/provider errors from stderr + stdout text
  (`setup.authErrorPatterns`).
- Featherless may return `This model is busy, please try again later` on
  parallel title-generation calls — retry smoke once or ignore title stream.

---

## Auth & Configuration

OpenCode is **BYOK** (like Featherless path, not subscription-first like agy).

User config (global, not owned by Allnighter):

- `~/.config/opencode/opencode.json` — providers, default model, permissions
- `~/.local/share/opencode/auth.json` — `opencode auth login` credentials
- Env vars via `{env:VAR}` in config; founder uses `~/.aider.env` → `OPENAI_API_KEY`

Allnighter V1:

- Does **not** write or merge user `opencode.json`.
- Doctor smoke requires provider keys + model visible to `opencode models`.
- Setup copy: install OpenCode, configure Featherless (or other provider) in
  global config, ensure `opencode serve` is reachable (coordinator handles in app).

Optional global autonomy (user-level, document in setup card):

```json
{
  "permission": "allow"
}
```

---

## Onboarding (User Story)

1. Install OpenCode (`brew install opencode` or npm global).
2. Add provider + models in `~/.config/opencode/opencode.json`.
3. Paste `featherless/Qwen/Qwen3-Coder-Next` (or other) on the Bench.
4. Allnighter starts/reuses local `opencode serve` on first OpenCode run.
5. Smoke proves attach + model without manual approval prompts.

---

## Proposed Driver Manifest

```json
{
  "id": "opencode",
  "manifestVersion": 1,
  "displayName": "OpenCode",
  "kind": "headless_cli",
  "maxConcurrentSpawns": 1,
  "detectCommand": "opencode --version",
  "smokeTestCommand": "opencode run --attach http://127.0.0.1:4096 --dir \"{{workingDir}}\" \"Reply with the single token ALLNIGHTER_READY\" --dangerously-skip-permissions -m \"{{model}}\"",
  "smokeTestExpect": "ALLNIGHTER_READY",
  "invoke": {
    "command": "opencode",
    "args": [
      "run",
      "--attach", "http://127.0.0.1:4096",
      "--dir", "{{workingDir}}",
      "{{prompt}}",
      "--dangerously-skip-permissions",
      "-m", "{{model}}"
    ],
    "promptVia": "arg",
    "env": {},
    "workingDir": "{{workingDir}}",
    "timeoutSeconds": 600
  },
  "output": {
    "capture": "stdout",
    "stripAnsi": true,
    "doneSignal": "exit_code",
    "sentinel": null
  },
  "setup": {
    "bins": ["opencode"],
    "knownPaths": [
      "~/.local/bin",
      "/opt/homebrew/bin",
      "/usr/local/bin"
    ],
    "installHint": "Install with `brew install opencode`. Configure providers in ~/.config/opencode/opencode.json. Allnighter starts a local `opencode serve` automatically.",
    "docsURL": "https://opencode.ai/docs/cli/",
    "authErrorPatterns": [
      "api key",
      "authentication",
      "unauthorized",
      "401",
      "rate limit",
      "model is busy"
    ]
  }
}
```

**Note:** `{{workingDir}}` for smoke must be a real git repo path (temp repo in
`CLIDetector` is fine). Coordinator must be up before smoke.

---

## Built-In Models (V1 Seed)

All **off-Bench by default**.

```text
model_opencode_qwen3_coder_next
  modelLabel: featherless/Qwen/Qwen3-Coder-Next

model_opencode_glm_5_2
  modelLabel: featherless/zai-org/GLM-5.2
```

Model strings must match `opencode models` output for the user's configured
providers.

---

## Implementation Slices

**Implement via sprint work orders** — one slice per agent session (32K-context
safe). Do **not** assign the full OC-S01 checklist in one prompt.

Router: `docs/phases/sprint/README.md`

| Order | Sprint doc | Scope |
| --- | --- | --- |
| 1 | [OC-S01a](../../sprint/opencode/OC-S01a-extractor-tests.md) | Tests + fixture |
| 2 | [OC-S01b](../../sprint/opencode/OC-S01b-worker-runner.md) | WorkerRunner wire |
| 3 | [OC-S01c](../../sprint/opencode/OC-S01c-serve-coordinator.md) | Serve coordinator |
| 4 | [OC-S01d](../../sprint/opencode/OC-S01d-detector-smoke.md) | Detector + spawn hook |
| — | **OC-S02** | `alln detect` / doctor / models (future sprint) |
| — | **OC-S03** | Mac setup card (future sprint) |

Already shipped (prior work): `opencode.json`, `DefaultConfig` embed,
`TextUtil.extractOpenCodeVisibleText`, `ModelCatalog` seeds.

<details>
<summary>Historical monolithic OC-S01 checklist (reference — do not assign whole list)</summary>

1. `OpenCodeServeCoordinator` …
2. Tests + fixture …
3. Manifest + DefaultConfig … **(done)**
4. WorkerRunner extractor …
5. CLIDetector / ModelHealthChecker …
6. DefaultConfigDriftTests …
7. Live `alln doctor --agent opencode` …

</details>

**Reference patterns:** `antigravity.json`, `WorkerRunner` Grok post-exit branch,
`DriverConcurrencyGate`.

---

## Works Test

```bash
# Unit tests (offline fixtures)
swift test --filter OpenCodeVisibleText

# Coordinator + live (requires opencode + keyed config)
alln detect --json | jq '.sources[] | select(.id=="opencode")'
alln doctor --agent opencode --json
alln run --worker <opencode-worker-id> "Reply with the single token ALLNIGHTER_READY"
```

Capture stdout fixture:

```bash
opencode serve --port 4096 &   # or let coordinator start it
sleep 2
source ~/.aider.env
cd /path/to/small-git-repo
opencode run --attach http://127.0.0.1:4096 \
  "Reply with the single token ALLNIGHTER_READY" \
  --dangerously-skip-permissions \
  -m featherless/Qwen/Qwen3-Coder-Next \
  > /tmp/opencode_smoke_stdout.txt 2>/tmp/opencode_smoke_stderr.txt
```

Commit fixture to
`Packages/AllnighterCore/Sources/AllnighterCore/Resources/Fixtures/opencode_stdout_smoke.txt`.

---

## Done When

- `opencode.json` + `DefaultConfig` ship; coordinator starts serve before runs.
- `smokeTestExpect` matches **extracted** stdout text.
- Setup copy explains BYOK global config + autonomous permissions.
- Parser fixtures tied to OpenCode **1.17.11**.
- No `streaming` block on manifest (Antigravity parity).

## Open Questions

- Setup glyph (neutral terminal chip per design system).
- Port collision if user already runs `opencode serve` manually.
- HTTP `serve` API as V2 alternative to CLI attach (same coordinator).

## Routing

| Work | Read |
| --- | --- |
| Driver implementation | This doc → `antigravity.json` → `CLI_Implementation_Contract.md` |
| Streaming posture | `threads/03_Mac_Streaming.md` (OpenCode = final-output V1) |
| Background coordinator | `Mac_Standalone_App_And_Background_Coordinator.md` |
| Setup/detect | `01_CLI_Detection_Auth_And_Bench.md` |
