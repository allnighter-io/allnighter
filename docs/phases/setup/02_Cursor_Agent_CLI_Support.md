# Cursor Agent CLI Support

Status: Founder input packet - draft implementation spec
Owner: AllnighterCore + AllnighterCLI + Mac GUI
Updated: 2026-06-19

## Founder Intent

Raw request:

- Cursor has a real CLI, exposed locally as `agent` and `cursor-agent`.
- That is strategically important because Allnighter was missing Cursor as a
  runnable source.
- Capture the discovered model/fast-mode behavior before it is lost in chat.

Product value:

Allnighter should treat Cursor Agent as another Source the user already pays
for. Once ready, Cursor models can sit on the Bench and become Workers inside
Code teams, without Cursor becoming a separate workflow or terminal viewer.

Trusted workflow slice:

```text
run setup/recheck
-> Allnighter finds `agent`
-> validates Cursor auth and a headless prompt
-> lists Cursor models in `alln models --json`
-> enables Composer 2.5 as a Cursor model
-> a Code team can use Cursor / Composer 2.5 as one worker
```

Non-goals:

- No automatic Cursor install, update, login, or config mutation.
- No direct edits to `~/.cursor/cli-config.json` from Allnighter.
- No use of Cursor Agent cloud worker mode as a hidden coordinator.
- No extra public noun beyond Source, Model, Skill, Worker, Team.
- No placeholder setup card until the manifest and smoke contract ship.

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
  phase-2 because no manifest/smoke contract has shipped.
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
- Cursor models must use driver-scoped model ids, e.g.
  `model_cursor_composer_25`, not the existing generic `model_composer`.
- `composer-2.5` and `composer-2.5-fast` are distinct built-in model definitions
  if both are shipped.
- The default built-in Cursor model should be regular Composer 2.5 unless live
  smoke proves that the user's account only exposes Fast.
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
  Cursor models"; do not silently fall back.

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
    "knownPaths": ["~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/Applications/Cursor.app/Contents/Resources/app/bin"],
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
- Confirm whether `--workspace "{{workingDir}}"` is valid when `workingDir` is
  nil before shipping the manifest. If nil is not safe, omit the flag unless a
  Project root is known.
- Confirm whether `--trust` is required, sufficient, or too permissive for
  Allnighter's safety posture. A mutating Code worker may need it; read-only
  probes should not imply user approval for future mutation.
- Prefer `--output-format text` for the first smoke. `json` or `stream-json` can
  be added after a parser contract and fixtures exist.

## Proposed Built-In Models

Initial built-ins:

```text
model_cursor_composer_25
  displayName: Composer 2.5
  modelLabel: composer-2.5
  driverId: cursor_agent
  role: answerer
  defaultEnabled: false until live smoke proves reliable

model_cursor_composer_25_fast
  displayName: Composer 2.5 Fast
  modelLabel: composer-2.5-fast
  driverId: cursor_agent
  role: answerer
  defaultEnabled: false
```

Do not add every model from `agent models` as a built-in in the first slice.
Start with Composer 2.5 and add custom models through the existing model catalog
workflow when the user needs account-specific variants.

## Auth, Privacy, And Permissions

- Cursor auth remains owned by Cursor.
- Allnighter may run `agent login` only as a user-visible repair action.
- Allnighter must not read, write, or display Cursor auth tokens.
- Allnighter must not persist Cursor email/account ids from `agent about` or
  `agent status`.
- Keychain failures are readiness facts, not permission prompts to auto-fix.
- `--force`, `--yolo`, `--sandbox disabled`, `--approve-mcps`, and cloud
  `worker` mode are out of scope for the first manifest.

## Proof

Works Test:

```text
From a GUI-launched Allnighter session with Cursor Agent installed:
alln doctor --agent cursor_agent --json reports cursor_agent ready only after
`agent -p --model composer-2.5 ...` returns ALLNIGHTER_READY.
Then `alln models --driver cursor_agent --json` lists Composer 2.5, and a Code
team run can include one Cursor worker whose worker answer is captured in
TeamRunJSON.
```

Supporting checks:

- Unit fixture for `agent` found at `~/.local/bin/agent`.
- Unit fixture for `cursor-agent` fallback when `agent` is absent.
- Auth classifier fixture for `SecItemCopyMatching failed -67674`.
- Smoke fixture where `composer-2.5` succeeds.
- Negative fixture where `composer-2.5` is rejected and no silent fallback to
  Fast occurs.
- `ModelCatalog` test that Cursor model ids are driver-scoped.
- Manifest round-trip test for `cursor_agent`.
- Generated contract drift check after CLI/MCP descriptors change.

Missing proof / waiver:

- No live smoke has been run from the Mac app launch context yet.
- Official install/usage routes exist at `https://cursor.com/docs/cli/installation`
  and `https://cursor.com/docs/cli/using`; model ids and `fast=false`
  parameter semantics still need direct verification before implementation.

## Next Slice

CUR-S00 - Discovery packet:

- Verify official Cursor Agent model-id and parameter docs.
- Run live `agent -p --model composer-2.5` from Terminal and from the same launch
  authority Allnighter uses.
- Decide `--trust` posture for smoke vs mutating Code worker runs.

CUR-S01 - Core manifest and model catalog:

- Add `cursor_agent` manifest to app resources and embedded default config.
- Add Cursor built-in model definitions to `ModelCatalog`.
- Add manifest/model tests and auth classifier fixtures.

CUR-S02 - CLI/MCP projection:

- Expose Cursor through `alln doctor --agent`, `alln models --driver`, and
  existing MCP doctor/model tools.
- Regenerate generated contracts from the registry.

CUR-S03 - Setup/GUI presentation:

- Add Cursor setup card only after CUR-S01/CUR-S02 are green.
- Use the existing source readiness states and model roster UI.

## Open Questions

- Does Cursor Agent provide an official stable docs URL for CLI install, login,
  model ids, and config parameters?
- Should regular Composer 2.5 be built-in default-on after smoke, or remain
  available/off-Bench until the user enables it?
- Is `agent -p --trust --workspace <project>` acceptable for a mutating Code
  worker, or should Allnighter require a Project-specific readiness approval
  first?
- Can `agent -p --output-format json` provide a stable final-answer field, or is
  text stdout the safer v1 capture?
- Should model refresh parse `agent models`, or should Cursor variants enter only
  through manual custom model add until a stable machine-readable model list is
  confirmed?
