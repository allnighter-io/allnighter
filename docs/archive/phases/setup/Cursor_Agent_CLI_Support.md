# Cursor Agent CLI Support

Status: **BUILT** / archived
Owner: AllnighterCore + AllnighterCLI + Mac GUI
Updated: 2026-06-19

Archived: 2026-06-19

Final status:
CUR-S01 (Core manifest + model catalog), CUR-S02 (CLI/MCP projection), and
CUR-S03 (Mac setup/GUI presentation) are built. `cursor_agent` ships as a
first-class headless CLI with Composer 2.5 as the default team answerer and
smoke/probe model; Auto is on-Bench by default as an opt-in router; Composer 2.5
Fast stays off-Bench unless explicitly enabled. GUI proof:
`docs/qa/gui/setup/2026-06-19-cursor-agent-gui/`. GUI-launched live smoke passed.

## Founder Intent

Raw request:

- Cursor has a real CLI, exposed locally as `agent` and `cursor-agent`.
- Cursor must become a first-class Allnighter CLI source, not an experimental
  adapter. It should be the #1 default Code worker candidate when ready.
- Composer 2.5 is founder-rated as highly capable and roughly 10-20x cheaper
  than GPT 5.5 / Opus-class workers for many Code tasks. Verify exact pricing
  before public copy, but build the product default around this cost posture.
- Regular Composer 2.5 is the default. Founder input says Cursor Fast mode is
  roughly 6x more expensive, so it must be explicit opt-in only.
- Capture the discovered model/fast-mode behavior before it is lost in chat.

Product value:

Allnighter should treat Cursor Agent as a first-class Source the user already
pays for. Once ready, Cursor Composer 2.5 should be the preferred default Code
worker because it combines strong coding ability with a much better expected
quota/cost profile. Cursor still flows through the same Source -> Model -> Skill
-> Worker -> Team model; it must not become a separate workflow or terminal
viewer.

Trusted workflow slice:

```text
run setup/recheck
-> Allnighter finds `agent`
-> validates Cursor auth and a headless prompt
-> lists Cursor models in `alln models --json`
-> Composer 2.5 is enabled as the default Cursor model
-> the default Code team can use Cursor / Composer 2.5 as its first worker
-> Composer 2.5 Fast remains available/off-Bench unless the user explicitly opts in
```

Non-goals:

- No automatic Cursor install, update, login, or config mutation.
- No direct edits to `~/.cursor/cli-config.json` from Allnighter.
- No use of Cursor Agent cloud worker mode as a hidden coordinator.
- No extra public noun beyond Source, Model, Skill, Worker, Team.
- No placeholder setup card until the manifest and smoke contract ship.
- No automatic selection of `composer-2.5-fast`.
- No silent fallback from regular Composer 2.5 to Fast.

## Current State

Observed local facts:

- `agent --help` works and starts "Cursor Agent".
- `agent` and `cursor-agent` exist under `~/.local/bin/`.
- Headless/script mode is `agent -p` or `agent --print`.
- Model selection is `--model <model>`.
- The CLI supports parameterized model overrides such as
  `composer-2.5[fast=false]`.
- `--output-format text|json|stream-json` is available with `--print`.
- `--workspace <path>` and `--trust` exist for headless runs.
- Read-only planning modes exist (`--mode plan`, `--mode ask`), but worker runs
  should use the normal headless run path unless a future team explicitly wants
  review-only posture.

Live proof from dev smoke:

- Binary path: `agent` and `cursor-agent` are present at `~/.local/bin/`, with
  `cursor-agent` resolving into `~/.local/share/cursor-agent/versions/<version>/`.
- Version observed: `2026.06.16-20-30-07-a07d3ac`.
- Auth observed in Terminal: `agent status` reports logged in on an Ultra tier
  account.
- `agent -p --output-format text --model composer-2.5 --trust "Reply with the
  single token ALLNIGHTER_READY"` returned `ALLNIGHTER_READY` in about 6s.
- `agent -p --output-format text --model composer-2.5-fast ...` returned the
  expected smoke token for Fast.
- `agent -p --output-format text --model 'composer-2.5[fast=false]' ...`
  returned the expected token, confirming the bracket override path.
- `--workspace /Users/mike/Documents/GitHub/Allnighter` correctly grounded the
  worker in the Allnighter repo.
- A mutating run with `--trust` successfully created a temp file under `/tmp`,
  proving headless writes are technically viable.
- Direct `Process` launch of `~/.local/bin/agent` returned the expected token,
  matching the path `WorkerRunner` would use.
- `--output-format json` returned an object with a stable-looking `result`
  field, but v1 should still use text capture until a parser contract lands.

Founder-discovered model facts:

- Regular Composer 2.5 is selected with `--model composer-2.5`.
- Composer 2.5 Fast is a separate model id: `composer-2.5-fast`.
- Regular mode can also be forced as
  `--model 'composer-2.5[fast=false]'`.
- `~/.cursor/cli-config.json` may show `modelId: "composer-2.5"` and
  `fast: "false"` while display strings still say "Composer 2.5 Fast"; code
  must trust the model id and parameter values, not the display label.

Observed readiness caveat:

- In this Codex-launched shell, account-backed commands (`agent models`,
  `agent --list-models`, `agent status`, `agent about`) returned
  `ERROR: SecItemCopyMatching failed -67674`.
- Treat this as a Cursor auth/Keychain/readiness failure until a smoke probe
  proves otherwise. Do not infer ready from binary presence or from a config
  file.

Existing Allnighter hooks:

- `DriverManifest` already supports headless CLI invocation, output capture,
  setup metadata, and model effort flags.
- Setup detection already resolves candidate bins through the user's shell and
  persists the concrete invocation.
- `ModelCatalog` owns built-in/custom models and Bench membership.
- `alln models --json` is the public machine contract for visible/enabled/ready
  model state.

Existing gaps:

- `docs/phases/setup/01_CLI_Detection_Auth_And_Bench.md` still names Cursor as
  phase-2 because no manifest/smoke contract had shipped when that doc was
  written. This packet supersedes that priority: Cursor is the next first-class
  CLI to implement.
- There is no `cursor_agent` driver manifest.
- There are no built-in Cursor model definitions.
- The app has no Cursor glyph asset wired to a setup card.
- Built-in manifests still live in both app JSON and embedded `DefaultConfig`
  JSON; adding Cursor must update both or remove that duplication first.

## SSOT

Truth owner:

```text
AllnighterCore.DriverManifest(id: "cursor_agent")
AllnighterCore.ModelCatalog
AllnighterEngine.CLIDetector + SetupStore
alln models JSON
```

Lie-prone layers:

- Cursor's display strings for Composer 2.5 Fast vs `fast=false`.
- `~/.cursor/cli-config.json`.
- `agent about` human text.
- PATH aliases/shell shims for `agent`.
- Keychain or Cursor account state when Allnighter is launched outside Terminal.
- SwiftUI setup rows.

New semantic rules:

- Cursor is a Source/driver, not a Team or lane.
- Cursor is a first-class shipped Source once `cursor_agent` lands; it should
  appear alongside Claude Code, Codex, Grok, and Antigravity, not behind an
  "experimental" label.
- Cursor models must use driver-scoped model ids, e.g.
  `model_cursor_composer_25`, not the existing generic `model_composer`.
- `composer-2.5` and `composer-2.5-fast` are distinct built-in model definitions
  if both are shipped.
- The default built-in Cursor model is regular Composer 2.5 (`composer-2.5`,
  equivalent to `fast=false`), enabled on fresh installs once the driver is ready.
- Composer 2.5 Fast (`composer-2.5-fast`) is always off-Bench by default and may
  be enabled only by explicit user action. It is not a "better default"; it is a
  higher-cost explicit choice.
- Allnighter must never silently fall back from `composer-2.5` to
  `composer-2.5-fast`, because that changes quota/cost behavior.
- Cursor Composer 2.5 should be the first default Code answerer candidate when
  ready. Higher-cost GPT 5.5 / Opus-class workers remain valuable for plan
  writing, review, escalation, or custom teams, but not as the default first
  spend path.
- `fast=false` is Cursor model-parameter state, not Allnighter reasoning effort.
  Do not route it through `EffortLevel`.
- Cursor readiness requires a successful headless smoke output, not `agent
  --help`, `agent about`, or config presence.
- Allnighter may pass `--model composer-2.5`; it must not rewrite the user's
  default Cursor config.

Duplicate truth to delete or avoid:

- Do not encode Cursor models only in a setup view.
- Do not scrape `agent models` output as the only source of built-in model truth.
- Do not add a Cursor-only JSON shape outside `ModelCatalog` and `TeamRunJSON`.
- Do not maintain separate Cursor manifest JSON unless the existing
  `DefaultConfig` duplication is intentionally preserved for the current build.

## CLI/MCP Surface

Required `alln` CLI surface:

```bash
alln doctor --agent cursor_agent --json
alln doctor explain source.cursor_agent.auth --json
alln models --driver cursor_agent --json
alln models enable model_cursor_composer_25
alln team --lane code --team <team-id> "Use Cursor as one Code worker."
```

`alln doctor --agent cursor_agent --json` must report:

```json
{
  "sources": [
    {
      "id": "cursor_agent",
      "displayName": "Cursor Agent",
      "status": "ready | notInstalled | installedNotSignedIn | probeFailed | shimmedNeedsConfirm",
      "version": "string or null",
      "path": "redacted invocation summary",
      "requiresManual": true
    }
  ]
}
```

`alln models --driver cursor_agent --json` must report Cursor model definitions
through the existing model-list schema. It must not expose Cursor config as a
parallel contract.

Required MCP surface:

- The existing model/doctor MCP projections must include `cursor_agent` once the
  CLI contract does.
- No Cursor-only MCP tool.
- Team-run MCP tools consume Cursor workers through the same `team.run`
  contract and `TeamRunJSON`.

Exit/error behavior:

- Missing `agent`/`cursor-agent`: source status `notInstalled`; setup hint points
  to Cursor Agent install/update docs.
- `SecItemCopyMatching failed -67674`: source status `installedNotSignedIn` or a
  specific auth/keychain check once the error catalog has one.
- Headless smoke timeout: `probeFailed` with a retryable recovery action.
- Model id rejected: `probeFailed` with action "try composer-2.5-fast or refresh
  Cursor models"; do not silently fall back. Any Fast retry must be explicit.

## Proposed Driver Shape

Candidate manifest:

```json
{
  "id": "cursor_agent",
  "manifestVersion": 1,
  "displayName": "Cursor Agent",
  "kind": "headless_cli",
  "detectCommand": "agent --version",
  "smokeTestCommand": "agent -p --output-format text --model composer-2.5 --trust \"Reply with the single token ALLNIGHTER_READY\"",
  "smokeTestExpect": "ALLNIGHTER_READY",
  "invoke": {
    "command": "agent",
    "args": [
      "-p",
      "--output-format",
      "text",
      "--model",
      "{{model}}",
      "--trust",
      "--workspace",
      "{{workingDir}}",
      "{{prompt}}"
    ],
    "promptVia": "arg",
    "env": {},
    "workingDir": null,
    "timeoutSeconds": 300
  },
  "output": {
    "capture": "stdout",
    "stripAnsi": true,
    "doneSignal": "exit_code",
    "sentinel": null
  },
  "setup": {
    "bins": ["agent", "cursor-agent"],
    "knownPaths": ["~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"],
    "installHint": "Install Cursor CLI with `curl https://cursor.com/install -fsS | bash`, then run `agent` or `agent login` if needed.",
    "docsURL": "https://cursor.com/docs/cli/installation",
    "loginFlow": {
      "interactiveCommand": "agent login",
      "instructions": "Run `agent login` and complete Cursor sign-in. If account-backed commands fail with Keychain errors, open Cursor once and retry setup.",
      "authErrorPatterns": ["SecItemCopyMatching failed", "not authenticated", "not signed in", "login", "unauthorized", "401"],
      "docsURL": "https://cursor.com/docs/cli/using"
    }
  }
}
```

Implementation notes:

- Prefer `agent` as the command because it is what the installed shell
  integration exposes; keep `cursor-agent` as a fallback bin.
- Do not include `/Applications/Cursor.app/Contents/Resources/app/bin` in
  `knownPaths`; live proof found `cursor`/`code` there, not `agent` or
  `cursor-agent`.
- `--workspace ""` works but is sloppy. Omit `--workspace` unless `workingDir`
  is non-nil, or add conditional arg expansion before shipping.
- `--trust` is technically required for headless mutation; without it, workers
  may stall on workspace approval. Product policy must still decide whether
  `--trust` belongs in every mutating Code run or only after Project-specific
  readiness/approval.
- Prefer `--output-format text` for the first smoke. `json` or `stream-json` can
  be added after a parser contract and fixtures exist. Live JSON returned a
  `result` field, so the follow-up parser path is viable.

## Proposed Built-In Models

Initial built-ins:

```text
model_cursor_auto
  displayName: Auto
  modelLabel: auto
  driverId: cursor_agent
  role: answerer
  defaultEnabled: true on fresh installs

model_cursor_composer_25
  displayName: Composer 2.5
  modelLabel: composer-2.5
  driverId: cursor_agent
  role: answerer
  defaultEnabled: true on fresh installs

model_cursor_composer_25_fast
  displayName: Composer 2.5 Fast
  modelLabel: composer-2.5-fast
  driverId: cursor_agent
  role: answerer
  defaultEnabled: false
```

Do not add every model from `agent models` as a built-in in the first slice.
Start with Auto + Composer 2.5 and add custom models through the existing model
catalog workflow when the user needs account-specific variants.

Default policy (shipped):

- Fresh install: `model_cursor_auto` and `model_cursor_composer_25` are on the
  Bench when `cursor_agent` is ready; `model_cursor_composer_25_fast` is
  available/off-Bench.
- Team defaults and smoke/probe always use **Composer 2.5** (`composer-2.5`), not
  Auto or Fast — deterministic health checks and preferred Code answerer.
- Fast mode: `model_cursor_composer_25_fast` remains available/off-Bench for all
  users unless explicitly enabled.
- Team defaults: built-in Code teams prefer `model_cursor_composer_25` when ready.

## Auth, Privacy, And Permissions

- Cursor auth remains owned by Cursor.
- Allnighter may run `agent login` only as a user-visible repair action.
- Allnighter must not read, write, or display Cursor auth tokens.
- Allnighter must not persist Cursor email/account ids from `agent about` or
  `agent status`.
- Keychain failures are readiness facts, not permission prompts to auto-fix.
- `--force`, `--yolo`, `--sandbox disabled`, `--approve-mcps`, and cloud
  `worker` mode are out of scope for the first manifest.
- Fast mode has quota/cost implications. Do not enable it by default, do not
  auto-switch to it, and do not hide a Fast retry behind a generic fallback.

## Proof

Works Test:

```text
From a GUI-launched Allnighter session with Cursor Agent installed:
alln doctor --agent cursor_agent --json reports cursor_agent ready only after
`agent -p --model composer-2.5 ...` returns ALLNIGHTER_READY.
Then `alln models --driver cursor_agent --json` lists Composer 2.5, and a Code
team run can include one Cursor worker whose worker answer is captured in
TeamRunJSON.
Fresh-install model projection shows `model_cursor_auto` and
`model_cursor_composer_25` on-Bench and `model_cursor_composer_25_fast`
available/off-Bench.
```

Supporting checks (all green):

- Unit fixture for `agent` found at `~/.local/bin/agent`.
- Unit fixture for `cursor-agent` fallback when `agent` is absent.
- Auth classifier fixture for `SecItemCopyMatching failed -67674`.
- Smoke fixture where `composer-2.5` succeeds.
- Negative fixture where `composer-2.5` is rejected and no silent fallback to
  Fast occurs.
- Roster fixture proving Auto + Composer 2.5 default enabled on fresh install
  and Fast defaults disabled.
- Team resolver fixture proving ready Cursor Composer 2.5 is the first default
  Code answerer candidate.
- `ModelCatalog` test that Cursor model ids are driver-scoped.
- Manifest round-trip test for `cursor_agent`.
- Generated contract drift check after CLI/MCP descriptors change.
- GUI visual proof: `docs/qa/gui/setup/2026-06-19-cursor-agent-gui/`.
- GUI-launched live smoke: `cursor_agent` ready in `cli_setup.json` after
  Re-check all from `open Allnighter.app` (no Keychain failure).

Remaining follow-ups (not blockers):

- Official install/usage routes exist at `https://cursor.com/docs/cli/installation`
  and `https://cursor.com/docs/cli/using`; model ids and `fast=false`
  parameter semantics are live-smoked locally but still need official-doc or
  version-pinned contract verification before public support copy.

## Shipped Slices (complete)

CUR-S01 - Core manifest and model catalog — **BUILT**

CUR-S02 - CLI/MCP projection — **BUILT**

CUR-S03 - Setup/GUI presentation — **BUILT**

## Open Questions

- Does Cursor Agent provide official, stable documentation for model ids and
  bracket parameters such as `fast=false`, or do we treat those as version-pinned
  smoke-tested implementation facts?
- Is `agent -p --trust --workspace <project>` acceptable for a mutating Code
  worker, or should Allnighter require a Project-specific readiness approval
  first?
- Should `--workspace` be conditionally emitted only for Project-root runs, or
  should the driver manifest learn conditional args first?
- Can `agent -p --output-format json` be promoted after v1 with a stable
  final-answer parser around `result`?
- Should model refresh parse `agent models`, or should Cursor variants enter only
  through manual custom model add until a stable machine-readable model list is
  confirmed?
- How should public copy phrase the cost advantage once current Cursor,
  GPT 5.5, and Opus pricing is verified?
