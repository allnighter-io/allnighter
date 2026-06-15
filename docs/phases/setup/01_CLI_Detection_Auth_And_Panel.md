# First-Run Setup — Detection, Auth & Panel Contract

**Status:** Engineering spec. Pairs with `00_First_Run_Setup_Experience.md`.
**Owner:** Core/Engine + GUI
**Created:** 2026-06-15

This is the truth layer behind the Setup experience: how Allnighter actually
finds the user's CLIs, decides if each is ready, and assembles the panel — and
how that fixes today's **"works in my terminal, 0/1 healthy in the app"** bug.

---

## 1. Why "0/1 healthy" happens today (root cause)

Two independent gaps:

**A. No discovery.** The panel is hardcoded. `AppConfig.loadDefaultPanel()`
returns a fixed "Fast Council" (Opus/claude only). The app never scans for the
other CLIs the user has, so grok/codex/agy never appear. → "1 of 1".

**B. The PATH / alias gap.** Health runs in `WorkerHealthChecker`:
- `detect`: run `claude --version`, expect exit 0.
- `smoke`: run `claude -p "Reply with ALLNIGHTER_READY" --model …`, expect token.

The app is GUI-launched (Finder/`open`), so it starts with launchd's **minimal
PATH**. `LoginShell.applyToProcessEnvironment()` bridges this by running
`zsh -lic 'printf %s "$PATH"'` and `setenv`-ing the result, and
`SubprocessCommandRunner.resolveExecutable` scans those PATH dirs for a binary.
That still fails when:
- the CLI is a **shell alias or function**, a **version-manager shim**
  (nvm/volta/asdf), or lives in an **app bundle** (`agy` inside Antigravity) —
  `resolveExecutable` only finds plain executables on PATH;
- the login-shell PATH capture is **corrupted** because `.zshrc` prints to stdout
  under `-i`;
- the binary is found but **not signed in** → smoke fails → unhealthy with no
  guidance.

`command -v claude` works in the user's terminal precisely because the shell
resolves aliases/functions/shims — which the app's PATH scan does not. **That is
the core thing to fix.**

---

## 2. Detection strategy (the fix)

Resolve every known CLI **through the user's login+interactive shell**, the same
way their terminal does, then cache the concrete result.

For each candidate `bin` (e.g. `claude`):
1. **Login-shell resolve (primary).** Run
   `"$SHELL" -lic 'command -v <bin> 2>/dev/null'`. `command -v` reports
   aliases, functions, builtins, and PATH binaries — matching terminal behavior.
   - If it returns an absolute path → use it.
   - If it returns an **alias/function** (not a path) → mark `kind = shimmed`;
     invoke at runtime *through the login shell* (`"$SHELL" -lic '<bin> …'`)
     rather than a direct exec, OR resolve the function's target if cheap.
   - Harden the capture: run with a sentinel
     (`printf '<<<%s>>>' "$(command -v <bin>)"`) so stray `.zshrc` output can't be
     mistaken for the answer. Strip everything outside the sentinel.
2. **Known-location fallback.** If the shell resolve is empty, probe a known list
   per tool (see §3): `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`,
   npm/pnpm/bun global prefixes, volta/asdf shim dirs, and app-bundle paths
   (e.g. Antigravity's `agy`).
3. **Cache the absolute path** per CLI (or the shimmed wrapper) so **runtime
   invocation never depends on PATH again** — store it on the driver/worker
   config and pass an explicit `command` path to `SubprocessCommandRunner`
   (which already accepts an absolute path and bypasses PATH resolution).
4. **Manual override.** Always allow the user to point at a binary via a file
   picker (Setup Scene 4, "Locate the binary…"). Persist it.

This belongs in a new `CLIDetector` in `AllnighterEngine` (sibling to
`WorkerHealthChecker`), shell access via a hardened extension of `LoginShell`.

---

## 3. Known-CLI registry

A first-class registry of the CLIs Allnighter knows how to drive — extends the
existing driver manifests (`Apps/AllnighterMac/Resources/Drivers/*.json`). Each
entry adds the Setup-facing fields:

| Field | Purpose |
| --- | --- |
| `id`, `displayName`, `brandSlug` | identity + glyph (Simple Icons: anthropic, openai, googlegemini, x, cursor; SF Symbol fallback) |
| `bins` | candidate command names (e.g. `["claude"]`, `["agy"]`, `["codex"]`, `["grok"]`, `["gemini"]`, `["cursor-agent","composer"]`, `["aider"]`) |
| `knownPaths` | fallback install locations incl. app-bundle paths |
| `detectCommand` / `smokeTestCommand` / `smokeTestExpect` | already in manifests |
| `installHint` | one-line install + docs URL (shown when not installed) |
| `loginCommand` | the exact sign-in command (`claude login`, `codex login`, `agy auth …`, `grok auth …`) shown/launched when found-but-unauthed |
| `canSynthesize` | eligible as the master synthesizer (judge) |

Seed it from the tools the founder uses: **Claude Code, Codex, Antigravity (agy),
Grok**, plus Gemini CLI, Cursor, Aider. The registry is the single place to add a
new tool later.

---

## 4. Auth probe & status classification

Replace the binary healthy/unhealthy with an explicit, **honest** status the UI
maps to the Scene-2/3 card states:

```
enum WorkerSetupStatus {
  case notInstalled                       // no bin resolved anywhere
  case shimmed(path/alias)                // found as alias/function/shim — needs confirm or wrapper
  case installedNotSignedIn(loginCommand) // detect ok, smoke fails with an auth-shaped error
  case probeFailed(reason)                // detect ok, smoke fails for another reason (flags/model/timeout)
  case ready(version)                     // detect ok AND smoke returns the token
}
```

Classification rules:
- `detect` exit≠0 / not resolved → `notInstalled` (unless shimmed).
- `detect` ok, `smoke` ok → `ready(version)`.
- `detect` ok, `smoke` fails with auth-shaped output (matches per-tool auth
  patterns: "not logged in", "unauthenticated", "run X login", 401) →
  `installedNotSignedIn`.
- `detect` ok, `smoke` times out or errors otherwise → `probeFailed(reason)`
  with the real stderr excerpt.
- Auth-shaped detection should be a per-tool pattern set in the registry, with a
  generic fallback.

**Honesty law:** `ready` is the *only* status that lets a worker run; it is set
only when the smoke token actually came back. Never infer "ready" from presence
alone, and never display a CLI as ready that isn't. (Reinforces AGENTS.md "a
failed worker is shown failed, never faked.")

Re-probe is cheap and **idempotent** so Scene 4 can poll after the user signs in
and flip the card live.

---

## 5. Auto-building the panel

After detection:
- Build the panel from **all `ready` workers** (not a hardcoded preset). This is
  the fix for "I have 4 CLIs, the app shows 1."
- Pick the **synthesizer** = the best `canSynthesize` ready worker (prefer Opus
  4.8 via claude-code; fall back sensibly).
- Persist the assembled panel as the user's default (replacing the hardcoded
  `loadDefaultPanel()` for first run; presets still layer on top).
- `shimmed`/`installedNotSignedIn`/`notInstalled` workers are **offered** in the
  roster but not seated until ready.
- Edge: zero ready → don't drop into an empty broken Council; keep the user in
  Setup's none-found state with install guidance.

---

## 6. Persistence

- Per CLI: resolved absolute path (or shim wrapper), last status, version, last
  probe time. Store under Application Support (alongside existing config), not in
  the bundle.
- Re-validate on launch **fast**: a presence check (cached path still exists +
  `--version`), deferring the full smoke to background so launch isn't blocked.
  The badge shows the cached state immediately, then updates.
- Setup is re-runnable; it overwrites this store.

---

## 7. Seams in the current code

| Concern | Today | Change |
| --- | --- | --- |
| PATH bridge | `LoginShell.applyToProcessEnvironment()` (AppConfig.swift) | add hardened `command -v` resolver + sentinel capture |
| Resolve exec | `SubprocessCommandRunner.resolveExecutable` (PATH scan) | accept cached absolute paths from detection; add login-shell wrapper for shims |
| Health | `WorkerHealthChecker` (detect + smoke → 2-state) | feed a new `CLIDetector`; emit the 5-state `WorkerSetupStatus` |
| Default panel | `AppConfig.loadDefaultPanel()` (hardcoded) | first run assembles from detected-ready workers |
| Manifests | `Resources/Drivers/*.json` | extend with `bins`, `knownPaths`, `installHint`, `loginCommand`, `canSynthesize` |
| UI | Doctor sheet (diagnostic only) | Setup flow (Scene 1–6) + Doctor becomes the recheck/roster view; health badge opens it |

---

## 8. Acceptance

- On a machine with Claude Code, Codex, Antigravity (agy), and Grok installed and
  signed in: first run detects **all four** (including any installed as
  aliases/shims/app-bundles) and assembles a 4-worker panel with no typing.
- A CLI that's installed but signed out shows `installedNotSignedIn` with the
  correct `loginCommand`; after the user signs in, a re-probe flips it to `ready`
  **without restarting the app**.
- A missing CLI shows `notInstalled` with a working install hint; never blocks.
- Runtime invocation uses the **cached absolute path** — health/runs do not
  depend on the ambient GUI PATH.
- No worker is ever shown `ready` (or allowed to run) without a passing smoke
  probe.

---

## 9. Out of scope (for now)

- Auto-installing CLIs (we guide; the user installs).
- Managing API keys/BYOK inside Allnighter (these CLIs own their own auth).
- Non-CLI / remote workers.
