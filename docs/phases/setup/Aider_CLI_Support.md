# Aider CLI Support (Headless Final Output)

Status: **Finalized — ready for AID-S01 implementation**
Owner: AllnighterCore + AllnighterCLI + Mac GUI
Updated: 2026-06-26
Pinned Aider version for fixtures: **0.86.2** (founder machine; synced repo `0.86.3.dev`)

**Authoritative sources for this doc (code wins over docs on conflict):**

- Synced Aider repo: `/Users/mike/Documents/GitHub/Aider-GitHub` (upstream:
  https://github.com/aider-ai/aider)
- Official docs: https://aider.chat/docs/ (especially
  [Scripting](https://aider.chat/docs/scripting.html),
  [`.aider.conf.yml`](https://aider.chat/docs/config/aider_conf.html),
  [`.env`](https://aider.chat/docs/config/dotenv.html))
- Repo version at doc time: `0.86.3.dev` (`aider/__init__.py`)

## Founder Intent

- Aider is a real headless coding CLI (`aider --message …`) that routes many
  provider/model strings through LiteLLM.
- Aider must become a first-class Allnighter **Source**, not a hidden sub-mode of
  future OpenRouter/Ollama adapters.
- V1 posture matches Antigravity: **final-output headless runs only** — capture
  complete stdout after process exit; no live token streaming.

## Trusted Workflow Slice

```text
run setup/recheck
-> Allnighter finds `aider` (`aider --version`)
-> smoke probe: `aider --message … --model <modelLabel> …` with BYOK keys present
-> user enables Aider models on the Bench (all built-ins off by default)
-> answer / default chat: `--dry-run` (no file writes; edits may still be shown)
-> execution teams: omit `--dry-run`, cwd = repo root, `--yes-always`
-> WorkerRunner extracts visible answer text from stdout after exit
```

## Non-Goals

- No automatic Aider install or API-key storage inside Allnighter.
- No V1 token streaming / partial live UI.
- No Python `Coder` API integration — Aider's own scripting page marks it
  **unsupported and unstable**.
- No placeholder setup card until manifest + extractor + smoke ship.
- No `--auto-commits` in shipped manifests.
- No treating OpenRouter/Ollama as separate Sources via hidden Aider sub-modes
  (future direct adapters remain separate).
- No per-model custom driver work — one `aider` manifest; users paste model
  strings (`alln models add` / Bench) the same as other BYOK sources.

---

## Onboarding (User Story)

Aider is **not** a subscription CLI like Grok/Antigravity/Cursor. There is no
vendor login flow in Allnighter.

1. User installs `aider` (`uv tool install aider-chat` or `pip install aider-chat`).
2. User configures BYOK keys in their environment (e.g. `~/.aider.env`,
   `OPENAI_API_KEY` + `OPENAI_API_BASE` for Featherless).
3. User adds a model on the Bench with the **exact** `modelLabel` Aider accepts
   (e.g. `openai/Qwen/Qwen3-Coder-Next` for Featherless,
   `anthropic/claude-sonnet-4-20250514` for Anthropic).
4. Setup smoke runs the standard headless bundle; Allnighter auto-appends
   `--env-file ~/.aider.env` when that file exists (driver-level — not a
   per-model user step).

Allnighter does **not** read or merge `~/.aider.conf.yml` into spawns. Pass
critical flags explicitly on every invocation.


## What Aider Actually Supports (Grounded)

### Headless integration surface

**Official:** [Scripting aider](https://aider.chat/docs/scripting.html) documents
CLI `--message` / `--message-file` as the scripting entry point: one instruction,
process reply, exit.

**Code:** `aider/main.py` handles `--message` by calling `coder.run(with_message=…)`
then returning — no interactive REPL.

```python
# aider/main.py (abridged)
if args.message:
    coder.run(with_message=args.message)
    return
```

There is **no** `--output-format json` or other machine-readable headless output
flag in `aider/args.py`. **Subprocess stdout parsing is the only supported
integration path.**

**Python API:** Scripting docs explicitly state the `aider.coders.Coder` Python
API is *not officially supported*, may change without backwards compatibility.
Allnighter uses **subprocess CLI only**.

### Confirmation flag (use `--yes-always`, not `--yes`)

**Code:** `aider/args.py` defines `--yes-always` only (passed to
`InputOutput(..., yes=args.yes_always)` in `main.py`).

**Doc drift:** Official scripting page still mentions `--yes`; the current CLI
uses `--yes-always`. Config files must use `yes-always:` — `yes:` is rejected
(`check_config_files_for_yes` in `main.py`).

Headless runs **require** `--yes-always` or they may block on confirmation
prompts (`io.py` `confirm_*` paths).

### Streaming

**Code defaults** (`args.py`): `--stream` default **True**; `--no-stream` buffers
the full model response before display.

- Non-pretty + streaming: assistant text is written with `sys.stdout.write` in
  `base_coder.show_send_output_stream` — still **human text**, not JSONL.
- Non-streaming: `io.assistant_output`.

**V1 Allnighter posture:** final-output only (Antigravity parity). Do **not**
add `streaming` manifest metadata. `docs/phases/threads/03_Mac_Streaming.md`
excludes Aider from the V1 streaming parser pass.

---

## Stdout Shape (Source of Truth)

Aider stdout is **not** a public API, but the reasoning layout is defined in
source:

```python
# aider/reasoning_tags.py
REASONING_START = "--------------\n► **THINKING**"
REASONING_END = "------------\n► **ANSWER**"
```

`replace_reasoning_tags()` converts model reasoning XML tags into those markers
before display (`base_coder.py`). Reasoning models may emit long THINKING blocks;
visible answer text follows the ANSWER marker.

### Other stdout noise to strip

| Block | Source |
| --- | --- |
| `Aider v{version}` + model line | `base_coder.get_announcements()` → `show_announcements()` |
| `Git repo: …` / `Repo-map: …` | same |
| `Detected dumb terminal, disabling fancy input and pretty output.` | `io.py` when `is_dumb_terminal()` |
| `Did not apply edit to {path} (--dry-run)` | `base_coder.apply_updates()` when `dry_run` |
| `Tokens: … sent, … received.` (+ optional `Cost: $…`) | `base_coder.calculate_and_show_tokens_and_cost()` → `show_usage_report()` → `io.tool_output` |

**Non-TTY behavior:** dumb terminals force `pretty=False` (`io.py`); still emit
explicit `--no-pretty --no-stream` in manifests for determinism.

### `extractAiderVisibleText` (Allnighter)

Implement against **current** `reasoning_tags.py` constants:

1. Strip ANSI (`stripAnsi: true`).
2. If `REASONING_END` (`------------\n► **ANSWER**`) is present: take text after
   the **last** occurrence until a line starting with `Tokens:` or EOF.
3. Else: treat full stdout as degraded fallback; strip known banner prefixes and
   trailing `Tokens:` / `Cost:` footer.
4. Never surface `REASONING_START` / THINKING body as visible answer text.

Add fixture tests using captured stdout from the pinned Aider version. Shipped
fixtures:

- `Packages/AllnighterCore/Sources/AllnighterCore/Resources/Fixtures/aider_stdout_hi.txt`
  — plain answer, no THINKING block (Qwen3-Coder-Next smoke capture).
- `Packages/AllnighterCore/Sources/AllnighterCore/Resources/Fixtures/aider_stdout_with_reasoning.txt`
  — synthetic THINKING/ANSWER layout for extractor tests.

Re-run fixtures on Aider upgrades — layout is **code-defined today** but not
semver-guaranteed as an external contract.

**Implementation:** `WorkerRunner` and `CLIDetector` apply
`TextUtil.extractAiderVisibleText` when `manifest.id == "aider"` (same pattern
as Grok's post-exit parser branch). There is no `extractor` field on
`DriverManifest.OutputSpec` today.

---

## `--dry-run` (Read-Only Answer Teams)

**Official help** (`args.py`): `Perform a dry run without modifying files`.

**Code behavior:**

| Action | Blocked by `--dry-run`? | Source |
| --- | --- | --- |
| Writing edited file content | **Yes** | `io.write_text` returns immediately; `apply_updates` prints "Did not apply edit…" |
| `git commit` / auto-commits | **Yes** | `auto_commit` returns early; `--commit` path prints "Dry run enabled, skipping commit." |
| Chat history append (`.aider.chat.history.md`) | **No** | `io.append_chat_history` always runs; session start writes a header |
| Input history (`.aider.input.history`) | **No** | prompt-toolkit `FileHistory` when fancy input enabled |
| Analytics events | **No** | unless `--no-analytics` / `--analytics-disable` |
| Git read (`git status`, repo map) | **No** | normal repo setup |

**Conclusion:** `--dry-run` is the correct flag for "don't mutate project files /
don't commit", but **not** zero filesystem side effects. Acceptable for V1 answer
teams; document honestly in setup copy.

For mutating execution teams: **omit** `--dry-run`; `WorkerRunner` drops the flag
based on run posture.

---

## Recommended Headless Invocation

### Read-only / answer teams

```bash
aider \
  --message "<PROMPT>" \
  --model "<MODEL>" \
  --yes-always \
  --no-stream \
  --no-pretty \
  --no-suggest-shell-commands \
  --no-detect-urls \
  --disable-playwright \
  --dry-run \
  --no-auto-commits \
  --no-analytics \
  --map-tokens 0 \
  --no-show-model-warnings
```

**Allnighter spawn extras (not in static manifest JSON — applied at runtime):**

| Condition | Append |
| --- | --- |
| `~/.aider.env` exists | `--env-file ~/.aider.env` |
| Smoke probe (no repo) | `--no-git` |
| Smoke probe (avoid `.gitignore` touch) | `--no-gitignore` |
| Real project run | omit `--no-git`; set `workingDir` to repo root |

Add `--no-git` only for **smoke probes outside a git repo**. In a real Project
root, omit `--no-git` so repo context works. For large repos, consider
`--map-tokens 1024` (Aider default) instead of `0` on real runs — `0` disables
repo-map and is preferred for fast smoke.

### Mutating / execution teams

Same bundle, but:

- omit `--dry-run`
- set process `workingDir` to the project/repo root
- pass `--file` / `--read` when Composer `@` refs land (follow-on slice)

### Flag rationale (from `args.py` + `main.py`)

| Flag | Headless | Why |
| --- | --- | --- |
| `--message` | **Required** | Without it, Aider enters interactive chat |
| `--model` | **Required** | Explicit model; don't rely on config defaults |
| `--yes-always` | **Required** | Auto-confirm; avoids stdin prompts |
| `--no-stream` | **Required** | Single stdout blob; simpler parsing |
| `--no-pretty` | **Required** | Less formatting variance (also forced on dumb TTY) |
| `--no-auto-commits` | **Required** | Allnighter owns git semantics |
| `--no-suggest-shell-commands` | Recommended | Default is True; disable noise |
| `--no-detect-urls` | Recommended | Default is True; disable URL scrape prompts |
| `--disable-playwright` | Recommended | Skip Playwright install/scrape path |
| `--no-analytics` | Recommended | Per-session telemetry off |
| `--map-tokens 0` | Smoke | Skips repo-map latency; use `1024+` on real runs if map wanted |
| `--no-show-model-warnings` | Recommended | Less startup noise |
| `--no-gitignore` | Smoke only | Avoids `.aider*` gitignore side effect on first run |
| `--env-file ~/.aider.env` | When file exists | Aider defaults to repo `.env`, not home env file |

**Not used:** `--settings-file` (does not exist). Pin config with `-c` /
`--config` only when needed.

---

## Auth & Configuration

### BYOK (no single vendor login)

Keys via `.env`, `--api-key PROVIDER=KEY`, `--set-env`, YAML (OpenAI/Anthropic
only per docs), or provider env vars. Allnighter does **not** store provider
keys in V1.

OpenRouter: `main.py` checks `OPENROUTER_API_KEY` for `openrouter/` models and
may attempt OAuth interactively — **unsuitable for headless smoke**. Surface
`probeFailed` with BYOK repair copy.

### Config precedence (code + docs aligned)

**`.aider.conf.yml` search** (`main.py`): build `[cwd, git_root, home]`, **reverse**
to load `[home, git_root, cwd]` — **last wins (cwd highest)**. Same as
[official config doc](https://aider.chat/docs/config/aider_conf.html).

**`.env`:** loaded via `load_dotenv_files`; re-parse after load
([dotenv doc](https://aider.chat/docs/config/dotenv.html)).

**CLI args** override config files (configargparse). **Pass critical flags
explicitly** on every Allnighter spawn; don't rely on project `.aider.conf.yml`.

**Env vars:** `AIDER_*` prefix (`auto_env_var_prefix="AIDER_"` in `args.py`).

**`--env-file` default (code):** `default_env_file(git_root)` → `.env` in git
root, **not** `~/.aider.env`. Interactive Aider users often keep keys in
`~/.aider.env`; headless spawns from Allnighter must pass
`--env-file ~/.aider.env` when that file exists, or keys won't load unless
already in the process environment.

**Binary resolution:** spawn the resolved executable from `ToolInvocation`
(`~/.local/bin/aider`), never a shell alias. Aliases can override `--model` and
hide the real binary path.

---

## Model Discovery

```bash
aider --list-models <partial-name>
```

**Code** (`models.print_matching_models`): prints `Models which match "…":` then
lines `- {model}`; exits `0` (`main.py`). Plain text only — no JSON mode.

Uses `fuzzy_match_models(search)` (LiteLLM-backed static lists + metadata).
Allnighter V1: small curated `ModelCatalog` built-ins; optional future
`alln models discover` wrapper — not required for AID-S01.

---

## Session / Multi-Turn (V1 = Stateless)

**Code supports resume:**

- `--chat-history-file` (default `.aider.chat.history.md` in git root)
- `--restore-chat-history` → loads markdown via `split_chat_history_markdown`
  (`base_coder.py`)

**No file locking** in `append_chat_history`. Concurrent processes sharing one
history file can race.

**V1 Allnighter:** one-shot `--message` per run; no resume. Multi-turn is a
follow-on slice with per-thread history paths.

---

## File Context

| Flag | Meaning (`args.py`) |
| --- | --- |
| positional `FILE` | files to edit |
| `--file` | add editable file (repeatable) |
| `--read` | read-only context (repeatable) |

Run from git repo root; paths are relative to git working dir (`main.py` warns
when cwd ≠ git root).

---

## Concurrency

`maxConcurrentSpawns: 1` in manifest. Source does not document safe parallel
`aider --message` in one repo; shared `.aider.*` history files and git state
make parallelism risky. Aligns with Allnighter's per-root mutating write lock.

---

## Exit Codes & Errors

**No published error-code table** in repo. Observed `main.py` patterns:

| Outcome | Typical exit |
| --- | --- |
| Success (`--message` completes) | `0` (`return` / `None`) |
| `--list-models` | `0` |
| Missing model / keys / invalid args | `1` |
| Message file missing / IO error | `1` |

**Critical spike finding:** LiteLLM auth failures can print
`AuthenticationError` (or similar) on **stdout** and still exit **`0`**.
Classify failures by **extracted stdout + stderr text** and
`setup.authErrorPatterns`, not exit code alone. Extend `vendorStdoutFailure` (or
equivalent) for `manifest.id == "aider"` when stdout matches auth patterns
despite exit 0.

`CLIDetector.smokeClassify` must run `extractAiderVisibleText` on stdout
**before** matching `smokeTestExpect` (token may appear only in the ANSWER block).

Capture both streams in `WorkerRunner`.

Tool errors use `io.tool_error` (console); assistant text uses stdout paths above.

---

## Validated Spike (2026-06-26, founder machine)

Environment: Aider **0.86.2**, Featherless (`OPENAI_API_BASE=https://api.featherless.ai/v1`),
model `openai/Qwen/Qwen3-Coder-Next`, `--env-file ~/.aider.env`,
`--map-tokens 0`, small git repo.

| Prompt | Wall time | Tokens (sent → received) | Extracted answer |
| --- | --- | --- | --- |
| "Say hi in one word." | **~3.2s** | 592 → 2 | `Hi` |
| "Reply with exactly: ALLNIGHTER_READY" | **~5.8s** | 596 → 6 | `ALLNIGHTER_READY` |

Compare: `openai/zai-org/GLM-5.2` on same Featherless path was **~9–17s** with
hundreds of received tokens (long THINKING). Qwen3-Coder-Next is non-thinking by
design and suitable for fast smoke.

Auth failure without `--env-file`: `AuthenticationError` on stdout, exit **0**,
~3s — confirms env-file auto-append is required for BYOK users who keep keys in
`~/.aider.env` only.

---

## Proposed Driver Manifest

```json
{
  "id": "aider",
  "manifestVersion": 1,
  "displayName": "Aider",
  "kind": "headless_cli",
  "maxConcurrentSpawns": 1,
  "detectCommand": "aider --version",
  "smokeTestCommand": "aider --message \"Reply with the single token ALLNIGHTER_READY\" --model \"{{model}}\" --yes-always --no-stream --no-pretty --no-suggest-shell-commands --no-detect-urls --disable-playwright --dry-run --no-auto-commits --no-analytics --no-git --no-gitignore --map-tokens 0 --no-show-model-warnings",
  "smokeTestExpect": "ALLNIGHTER_READY",
  "invoke": {
    "command": "aider",
    "args": [
      "--message", "{{prompt}}",
      "--model", "{{model}}",
      "--yes-always",
      "--no-stream",
      "--no-pretty",
      "--no-suggest-shell-commands",
      "--no-detect-urls",
      "--disable-playwright",
      "--dry-run",
      "--no-auto-commits",
      "--no-analytics",
      "--map-tokens",
      "0",
      "--no-show-model-warnings"
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
    "bins": ["aider"],
    "knownPaths": [
      "~/.local/bin",
      "~/.local/share/uv/tools/aider-chat/bin",
      "/opt/homebrew/bin",
      "/usr/local/bin"
    ],
    "installHint": "Install with `uv tool install aider-chat` or `pip install aider-chat`. Add provider API keys via `.env` or your environment.",
    "docsURL": "https://aider.chat/docs/install.html",
    "authErrorPatterns": [
      "api key",
      "authentication",
      "authenticationerror",
      "unauthorized",
      "401",
      "rate limit",
      "openai_api_key",
      "openrouter_api_key"
    ]
  }
}
```

**WorkerRunner / CLIDetector:**

- Drop `--dry-run` for mutating runs (posture-aware arg filter).
- Append `--env-file ~/.aider.env` when `FileManager` finds that path.
- Apply `TextUtil.extractAiderVisibleText` before answer settlement and before
  `smokeTestExpect` matching.
- Treat auth-shaped stdout as failure even when exit code is 0.

**Version policy:** Record the Aider version used to capture parser fixtures
(**0.86.2** on founder machine). Re-run fixtures on upgrade; no floating
`aider>=` in smoke docs.

---

## Built-In Models (V1 Seed)

All **off-Bench by default** (readiness = BYOK per model).

```text
model_aider_claude_sonnet_4
  modelLabel: anthropic/claude-sonnet-4-20250514

model_aider_gpt_4o
  modelLabel: gpt-4o

model_aider_deepseek_chat
  modelLabel: deepseek/deepseek-chat
```

Model strings must match what `aider --list-models` accepts for the user's
providers.

---

## Architect Mode

`--architect` sets `edit_format=architect` (`args.py`) — architect + editor model
pipeline. It **still applies file edits** unless `--dry-run`. Not a separate
plan-only mode. V1 does not use architect for answer teams.

---

## Implementation Slices

| Slice | Scope | Files |
| --- | --- | --- |
| **AID-S01** | Manifest + extractor + posture-aware spawn | `Apps/AllnighterMac/Resources/Drivers/aider.json`; `DefaultConfig.swift`; `TextUtil.extractAiderVisibleText`; `WorkerRunner` (extract + `--dry-run` drop + `--env-file` + auth exit-0); `CLIDetector` / `ModelHealthChecker` (extract before smoke match); fixtures `aider_stdout_*.txt`; `DefaultConfigDriftTests` |
| **AID-S02** | CLI detect/doctor | `alln detect` / `doctor --agent aider` / `models --driver aider`; error catalog |
| **AID-S03** | Mac setup card | BYOK repair copy; GUI proof |

### AID-S01 checklist (implement in this order)

1. `TextUtil.extractAiderVisibleText` + unit tests against both fixtures.
2. `aider.json` manifest (copy from this doc) + `DefaultConfig` embed.
3. `WorkerRunner`: `manifest.id == "aider"` extraction branch; mutating runs omit
   `--dry-run`; append `--env-file ~/.aider.env` when present; auth failure on
   stdout despite exit 0.
4. `CLIDetector` / `ModelHealthChecker`: extract stdout before `smokeTestExpect`
   substring check.
5. `DefaultConfigDriftTests` + bundle resource copy.
6. Live smoke: `alln doctor --agent aider` with a keyed model on the Bench.

## Works Test

```bash
# Unit tests (offline fixtures)
swift test --filter AiderVisibleText

# Live (requires aider + keyed model)
alln detect --json | jq '.sources[] | select(.id=="aider")'
alln doctor --agent aider --json
alln run --worker <aider-worker-id> "Reply with the single token ALLNIGHTER_READY"
```

Capture stdout fixture from:

```bash
aider --message "Reply with the single token ALLNIGHTER_READY" \
  --model "<your-model>" --yes-always --no-stream --no-pretty \
  --no-suggest-shell-commands --no-detect-urls --disable-playwright \
  --dry-run --no-auto-commits --no-analytics --no-git --no-gitignore \
  --map-tokens 0 --no-show-model-warnings \
  --env-file ~/.aider.env
```

## Done When

- Manifest + extractor ship; `smokeTestExpect` matches **extracted** text.
- Answer teams use `--dry-run`; execution teams omit it under write lock.
- `--env-file ~/.aider.env` auto-appended when file exists.
- Auth failures on stdout classified as failed even when exit code is 0.
- Setup copy states BYOK + possible `.aider.*` history side effects on dry-run.
- Parser fixtures tied to pinned Aider version **0.86.2** in repo/CI.

## Open Questions

- Setup glyph (no Simple Icons mark — neutral terminal chip per design system).
- Composer `@` refs via `--read` / `--file` (follow-on slice).

## Routing

| Work | Read |
| --- | --- |
| Driver implementation | This doc → `antigravity.json` → `CLI_Implementation_Contract.md` |
| Streaming posture | `threads/03_Mac_Streaming.md` |
| Setup/detect | `01_CLI_Detection_Auth_And_Bench.md` |

## Source Index (synced repo)

| Topic | File |
| --- | --- |
| CLI args | `aider/args.py` |
| Main flow / `--message` / config load | `aider/main.py` |
| THINKING/ANSWER markers | `aider/reasoning_tags.py` |
| Output / dry-run write guard | `aider/io.py` |
| Stream + token footer | `aider/coders/base_coder.py` |
| Dry-run edit message | `aider/coders/base_coder.py` (`apply_updates`) |
| `--list-models` | `aider/models.py` (`print_matching_models`) |
| Chat history resume | `aider/coders/base_coder.py`, `aider/io.py` |
| Scripting (official) | https://aider.chat/docs/scripting.html |
