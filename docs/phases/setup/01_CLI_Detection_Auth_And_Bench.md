# First-Run Setup — Detection, Auth & Bench Contract

**Status:** Engineering spec (finalized). Pairs with `00_First_Run_Setup_Experience.md`.
**Owner:** Core/Engine + GUI
**Created:** 2026-06-15 · **Finalized:** 2026-06-15 (mentor review folded in)

This is the truth layer behind the Setup experience: how Allnighter finds the
user's CLIs, decides if each is ready, and assembles the Bench/default Team — and how that
fixes today's **"works in my terminal, 0/1 healthy in the app"** disaster. The
guiding principle: **Setup must be a thin skin over detection that already works
on a real machine — never a beautiful wrapper around flaky probes.**

---

## 1. Why "0/1 healthy" happens today (root cause)

Four layered causes. **Cause 0 is the actual current blocker — confirmed from
Doctor and the built bundle — and nothing else even runs until it's fixed.**

### Cause 0 — Packaging: the driver manifests aren't in the bundle (CONFIRMED)
Doctor reports **"No driver manifest 'claude_code' is installed."** Evidence:
- `AppConfig.loadDefaultRegistry()` / `loadDefaultPanel()` look up resources via
  `Bundle.main.url(…subdirectory: "Drivers")`.
- The built `.app` has **no `Drivers/` subdirectory** — XcodeGen
  `resources: - path: Resources/Drivers` shipped the JSONs as a flattened group.
- → `loadDefaultRegistry()` returns an **empty registry** (every legacy worker fails
  Doctor with "no manifest"; detection/PATH/auth never run), and
  `loadDefaultPanel()` returns empty → `AppModel` uses `fallbackPanel()`, a single
  hardcoded Opus worker (= the "1 of 1" the user sees). These are legacy symbol
  names until the vocabulary cleanup lands.
- The legacy bundled `team_default.json` currently defines the default team:
  **6 workers across 4 drivers**. The vocabulary cleanup renames this seed to
  `team_default.json`.
- Unit tests stayed green because they read manifests from the **source tree**
  (`DesignManifestResourceTests`) or inject a registry — the *built-bundle*
  contract was never asserted.

Fix in §3. **Order of operations: fix Cause 0 first**, then layer discovery (1),
shell-aware detection (2), and guided auth (3).

### Cause 1 — No machine discovery (design gap)
Even with the bundle fixed, the default team is a **static file** — not what's installed
on *this* machine. Real Setup scans and builds the roster from what the user
actually has (§4).

### Cause 2 — The PATH / alias gap (surfaces once detection runs)
`ModelHealthChecker` runs `detect` (`claude --version`) and `smoke`
(`claude -p … --model …`). GUI-launched (Finder/`open`), the app starts with
launchd's **minimal PATH**. `LoginShell.applyToProcessEnvironment()` bridges PATH
(`zsh -lic 'printf %s "$PATH"'` → `setenv`) and
`SubprocessCommandRunner.resolveExecutable` scans those dirs for a **binary**.
That still fails when the CLI is a **shell alias/function**, a **version-manager
shim** (nvm/volta/asdf), or an **app-bundle binary** (`agy` inside Antigravity),
or when the captured PATH is **corrupted** by `.zshrc` stdout under `-i`.
`command -v claude` works in the terminal precisely because the shell resolves
those — which the app's PATH scan does not. §4 closes this.

### Cause 3 — Auth (the honest "not signed in" case)
A found CLI can be installed but **not signed in**; smoke then fails. Today that's
an opaque "unhealthy"; Setup turns it into a guided, live fix (§5, Experience §4).

---

## 2. Entity model — source vs model vs worker (read this first)

The single most important clarification: **detection is per source, the Bench is
per model, and a Team is per worker.** They are different cardinalities and the
docs/UI must not conflate them.

- **Source / driver** = one CLI or local runtime (`claude`, `codex`, `grok`,
  `agy`). Keyed by `driverId`. **Detection, auth, caching, and the Setup roster
  are per source.**
- **Model** = a model available through a source (Opus and Sonnet are two models
  on the one `claude_code` source).
- **Worker** = a runtime assignment for a team run: `model + skill`.
- Legacy `team_default.json` currently seeds the default Team: **6 workers on 4
  sources**. Target fixture name after the cleanup is `team_default.json`.

Rules:
- The roll-call roster shows **one card per source**, not per model or worker.
  Tally and the title-bar badge are **source-level**: "4 of 4 tools ready" (or
  "Claude Code ready · 2 models"), never "4 of 6 ready" implying six installs.
- **One smoke probe per source.** Per-model differences are model labels passed
  to the same binary; validate a second model only if cheap and necessary — do
  not run 6 smokes for 4 sources.
- **Plan-writer eligibility stays on the model/team config.** Do **not**
  duplicate it on the source/registry.
- Scene 5 expands each ready source into default workers from the configured team
  filtered to ready `driverId`s.

CLI/Doctor rule:

- `alln doctor --json` reports `sources[]` and `models[]`. It must not report
  Bench models as workers. `workers[]` appears only in team/team-run output after
  a model has been paired with a skill.

---

## 3. Cause 0 fix — packaging + an honest safety net (prerequisite)

Three parts, in priority:

1. **Ship the manifests.** Driver JSONs are copied into the app bundle via
   XcodeGen `sources` with `buildPhase: resources` (the top-level `resources:`
   key did not generate a copy phase). Lookups use subdir-free bundle-root paths
   first, then `Drivers/` as a fallback.
2. **Honest runtime safety net — never mask packaging failure.** If the bundle
   registry is empty, fall back to the **embedded real manifests**
   (`DefaultConfig.registry` / `DefaultConfig.workers`) — these are the *same real
   manifests* in code, not fakes, so the app is never hollow. **Retire the silent
   one-worker `fallbackPanel()`** — it turned a catastrophic packaging bug into a
   fake "user setup problem." If **both** bundle and embedded sources are empty
   (a truly broken install), show a **hard, reinstall-style error**, not a
   degraded 1-worker team.
3. **Built-bundle Works-Test as the release gate.** A test that loads from the
   built `.app`'s `Bundle.main` and asserts `loadDefaultRegistry().all.count >= 4`
   and the default team has 6 workers — plus a packaging CI step asserting the built
   bundle's **resource root** contains `claude_code.json`, `team_default.json`,
   and the other driver manifests (subdir-free lookup; no `Drivers/` folder
   required). This is the test that would have caught Cause 0; today's source-tree
   tests cannot.

> **Dual-source caveat:** the default manifests/team live in **both**
> `Resources/Drivers/*.json` and `DefaultConfig.swift` (hardcoded strings). Any
> schema change must update both (and fixtures). Strongly consider generating the
> Swift defaults from the JSON at build, or loading the JSON in both surfaces, so
> they cannot drift.

---

## 4. Detection strategy (the fix)

Resolve every known tool **through the user's login shell** (as their terminal
does), classify it honestly, and **cache a concrete invocation plan** so runtime
never depends on the ambient GUI PATH again.

### 4.1 Tiered probe budget (fast-first, parallel, honest)
Full smoke is up to 60s per tool; "scan all, smoke-first" would feel broken.
Probe in stages, run tools **concurrently** (cap ~2–3 smokes), reveal progress
truthfully:

| Stage | What | Target | Card state |
| --- | --- | --- | --- |
| **Resolve** | login-shell `command -v` + known paths | <300ms/tool | ghost → found (path) |
| **Detect** | `--version` via the resolved path | <2s/tool | version snaps in |
| **Auth/status** | tool's status command if it has one | <2s | "signed in" if known |
| **Smoke** | token probe with a model | 5–60s, capped, parallel | checking… → ready / needs-login / failed |
| **Cache** | persist plan + status | — | instant on next launch, background re-smoke |

Scene-2 stagger is **cosmetic** (120–160ms reveals); probe order is fastest-first
so glyphs ignite on *found* long before smoke resolves. A probe over ~8s shows
"still checking (unusual for this tool)" + a manual skip — never an infinite
spinner.

### 4.2 Resolve, hardened (the real fix for Cause 2)

> **Probe-authority binding (Launch Authority TCC hotfix, rule 8 · Track 0.1):**
> interactive `-lic` resolve is allowed ONLY on an explicit, user-initiated
> setup/recheck probe (one-time TCC prompt acceptable). Any launch/background
> path must stay cache-only or use non-interactive `-lc`. In code this is
> `CLIDetector(interactive:)` / `ShellResolver(interactive:)`, default `false`
> (`-lc`); set `true` only at explicit setup (`runFullSetupProbe`, `alln
> detect`/`doctor`). Runs reuse the cached absolute `ToolInvocation` (health ==
> runs), so no per-run shell is spawned.

For each candidate `bin`:
1. **Login-shell resolve (primary):** `"$SHELL" -lic` running
   `printf '<<<AL:%s>>>' "$(command -v <bin> 2>/dev/null)"`. The **sentinel**
   isolates the answer so noisy `.zshrc`/`.zprofile` stdout (starship, banners)
   can't corrupt it. `command -v` matches terminal behavior (aliases, functions,
   builtins, PATH binaries).
2. **Timeout + fallback:** bound the shell call (2–3s). On timeout/empty, probe a
   per-tool **known-paths** list (§6) — never hang the first scan.
3. **Batch:** resolve **all** bins in **one** shell session, not one login shell
   per tool (a full `-lic` per tool is slow). Consider `-l` (login, non-interactive)
   when interactive hooks aren't needed, falling back to `-lic`; test both, since
   some tools only load under `-i`.
4. **Shell diversity:** always use `$SHELL`; if unset, fall back to
   `dscl . -read /Users/$USER UserShell`. **zsh/bash supported; fish best-effort**
   (its `command -v` differs) — document, don't pretend.

### 4.3 Invocation plan (the seam that makes health == runs)
`command -v` returns one of: an absolute path, an alias, or a function. The
detector emits a **`ResolvedInvocation`**, persisted per source, consumed by
health checks and the runner so a source that passes Setup actually runs:

```
enum Invocation {
  case direct(path: String, args: [String])              // absolute exec — current fast path
  case shim(path: String, args: [String])                // resolved shim/version-manager binary
  case loginShell(commandName: String, args: [String])   // alias/function — run via "$SHELL" -lic
}
```

- `direct`/`shim` keep today's no-injection guarantee (argv elements, never a
  shell string). `loginShell` must preserve it too: strict quoting, prompt content
  still passed as args/stdin — never concatenated into the shell command.
- Standard shims resolve to `direct`/`shim` with **zero user clicks**. Only an
  **ambiguous alias** (`alias claude='something weird'`, or `command -v` returns
  non-path text we can't resolve) surfaces a one-click "use it anyway / locate the
  binary…" confirmation.
- Always allow a manual **"Locate the binary…"** file-picker override; persist it.

---

## 5. Status model — one canonical classification

Replace the binary legacy `WorkerHealth` (healthy/unhealthy/unknown) with a
single honest status that **Doctor, Setup, and the health badge all consume from
one probe and one persistence store** — no forked truths.

```
enum SourceSetupStatus {
  case notInstalled                          // no bin resolved anywhere
  case shimmedNeedsConfirm(resolved)         // ambiguous alias/function — needs one-click confirm
  case installedNotSignedIn(loginFlow)       // detect ok, smoke fails with an auth-shaped error
  case probeFailed(reason)                    // detect ok, smoke fails otherwise (flag/model/timeout)
  case ready(version)                         // detect ok AND smoke returned the token
}
```

- Classify on **exit code + per-tool auth patterns** (registry `authErrorPatterns`),
  not just generic stderr heuristics. **Separate `installedNotSignedIn` from
  `probeFailed`** — users treat "sign in" and "unknown flag" very differently, and
  Scene 4's fix-it differs.
- **`ready` is the only status that lets models from that source be used in a
  team run**, set only when the smoke token actually came back. Never infer ready
  from presence.
- **Codex smoke runs from a neutral temp dir** (app-support scratch), with
  `--skip-git-repo-check`, so it never depends on the user's current git repo.
- `WorkerHealth`/`WorkerDiagnosis` become a view-layer mapping of this status (or
  are replaced). Re-probe is **idempotent and cheap** so Scene 4 can poll.

---

## 6. Known-CLI registry

Drivers describe **how to run** a tool; Setup needs **how to find, install, sign
in, and display** it — different churn rates. Extend `DriverManifest` to v2 with
an **additive, optional `setup` block** (single co-located source of truth; a
sibling `setup_registry.json` keyed by `driverId` is the acceptable alternative if
the invoke schema must stay lean):

| Field | Purpose |
| --- | --- |
| `setup.bins` | candidate command names (`["claude"]`, `["agy"]`, `["codex"]`, `["grok"]`) |
| `setup.knownPaths` | fallback locations: `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, npm/pnpm/bun global prefixes, volta/asdf shim dirs, **app bundles** (e.g. `/Applications/Antigravity.app/…` for `agy`) |
| `setup.installHint` | one-line install + docs URL (shown only when not installed) |
| `setup.loginFlow` | how to authenticate (below) |
| `displayName`, `brandSlug` | identity + glyph |

**`loginFlow` (not a single `loginCommand`)** — real tools rarely have a clean
`foo login`:
```
loginFlow {
  interactiveCommand     // e.g. start `claude` then use /login; `codex` prompts on first run; `gemini` OAuth/API-key
  instructions           // human steps, sentence case
  expectedCredentialArtifact?  // a path/file whose presence implies signed-in, for cheap re-checks
  authErrorPatterns      // stderr/exit patterns that mean "not signed in"
  docsURL
}
```

Registry scope for v1:
- **Plan-writer eligibility does NOT live here** — eligibility is model/team
  config (§2), not source setup metadata.
- **Roster = shipped drivers only.** Today that's `claude_code`, `codex`, `grok`,
  `antigravity` (+ `manual_paste`). **Do not show ghost cards** for tools with no
  manifest. Cursor Agent shipped — see
  `docs/archive/phases/setup/Cursor_Agent_CLI_Support.md`. Aider / Gemini-CLI remain future manifest work.
  (README ground rule "real detection" = no placeholder cards.)
- **Glyphs:** Simple Icons for `anthropic`, `googlegemini`, `x`, `cursor`. Simple
  Icons **removed OpenAI** (trademark) — ChatGPT/Codex uses a **neutral terminal
  chip / SF Symbol**, per `docs/design-system/readme.md`. Opus/plan-writer carries
  the amber; other glyphs tint to brand.

---

## 7. First-run gate

Current product decision: ordinary launch lands on clean Home and is
process-quiet. Setup is reachable by user intent from the team dropdown / health
badge; it does not auto-open and it does not run Doctor in the background.

- **`SetupStore.setupCompletedAt`** in Application Support (alongside
  `TeamPresetStore` / `AllnighterPaths.config`).
- Never-completed setup remains persisted truth for future routing/copy, but it
  does not currently force a launch gate.
- **Menu-bar app (`LSUIElement`)**: first launch must **auto-open the main window
  at full size** (≥1100×720) — never hide the product behind the menu-bar icon.
- **Non-trapping.** The user can leave setup with 0 ready tools; the app remains
  honest and the team dropdown/health badge keeps a visible path back.
- Re-entry: team dropdown / health badge -> CLI setup.
- **Interim gate (before the Setup UI exists):** if `registry.all.isEmpty`, show a
  blocking "bundled drivers missing — reinstall" alert with a copyable fix —
  never the silent 0/1 team.

---

## 8. Auto-building the Bench and default Team

After detection settles:
- Add every model whose source is `ready` to the Bench.
- Build the default Team from ready models and the default skills — the fix for
  "I have 4 CLIs, the app shows 1."
- Default active team preset: **"All ready"** when ready workers ≥3, else
  **"Fast Team."** Tiered presets layer on top of the assembled team.
- **Plan writer** default = first ready eligible worker from the assembled team
  (prefer Opus 4.8 wearing the Plan Writer skill); user can change it in Scene 5.
- **Scene 5 is confirm, not configure** — toggles only. **No model editing in
  Setup** (that stays in Settings).
- Persist the assembled set (a `DiscoveredModels` / `LastTeam` store) so later
  launches don't re-ask. Legacy `team_default.json` + `DefaultConfig.workers`
  remain the seed/fallback until the fixture rename.

---

## 9. Persistence & launch performance

**2026-06-16 launch-authority note:**
`../../archive/phases/Launch_Authority_TCC_Hotfix.md` supersedes this section
where it allows background full smoke on ordinary app launch. Launch may render
cached/unknown state only until explicit setup/recheck/run user intent.

- Per tool: `{ invocation, status, version, lastProbeAt }` under
  `AllnighterPaths.config`.
- On launch (and Setup re-entry): a **fast re-validate** — cached path still
  executable + a quick `--version` — so the sidebar/badge populate **instantly
  from cache**, then a full smoke runs in the background and updates. Setup forces
  a fresh sweep.
- Opportunistic fast re-validate on app foreground/wake so the badge is never
  stale.

---

## 10. Seams in current code

| Concern | Today | Change |
| --- | --- | --- |
| **Driver manifests (Cause 0)** | `Resources/Drivers` shipped as a group → no `Drivers/` subdir → empty registry + fallback team | folder reference / subdir-free lookup; **DefaultConfig safety net** (real manifests), retire silent `fallbackPanel`; built-bundle release-gate test |
| Shell resolve | `LoginShell.resolvedPath()` (no sentinel/timeout) | hardened sentinel + timeout + batch + shell diversity (shared `ShellResolver` in Engine) |
| Resolve exec | `SubprocessCommandRunner.resolveExecutable` (PATH scan only) | consume cached `Invocation`; add `loginShell` wrapper for aliases/functions |
| Invocation | `WorkerRunner` execs `invoke.command` directly | both runner + health use the detector's `ResolvedInvocation` (health == runs) |
| Health/status | `ModelHealthChecker` → `WorkerHealth` (2-state) | `CLIDetector` emits canonical `SourceSetupStatus` (5-state); Doctor + badge map from it |
| Manifests | `Resources/Drivers/*.json` **and** `DefaultConfig.swift` strings | add additive `setup` block; de-duplicate the two sources |
| Default team | `AppConfig.loadDefaultPanel()` legacy static / fallback | first run assembles from ready sources/models; persisted |
| Gate | none (`RootView` → Compose + bg Doctor) | `SetupStore` first-run gate; full-window Setup; badge opens compact roster |
| UI | Doctor sheet (diagnostic) | Setup flow (Experience 1–6); Doctor becomes the recheck/roster surface |

---

## 11. Build sequencing (no shortcuts, but ordered)

Prove detection on a real machine **before** building the WOW UI.

- **Phase 0 — Unblock (hours).** Packaging fix + `DefaultConfig` safety net +
  built-bundle Works-Test. Outcome: default models/team appear; Doctor shows *real* reasons,
  not "no manifest." (0/10 → ~4/10.)
  - **Done (2026-06-15):** subdir-free bundle lookup (`AppConfig` tries resource
    root, then `Drivers/`); XcodeGen `buildPhase: resources` fix so JSONs ship
    to `Contents/Resources/*.json`; `DefaultConfig` safety net replaces silent
    `fallbackPanel()`; blocking alert when both sources fail; `BuiltBundleConfigTests`
    + `DefaultConfigDriftTests`; interim Doctor runs against real manifests.
  - **Not yet:** Setup UI; auto-team. (`CLIDetector`/`ShellResolver` landed in
    Phase 1, below.)
- **Phase 1 — Detection core (engine). BUILT (2026-06-15).** `ShellResolver`
  (sentinel/timeout/batch) + `CLIDetector` + known-paths fallback +
  `ToolInvocation` (direct/shim/loginShell) + 5-state `ModelSetupStatus`,
  persisted via `SetupStore` (`cli_setup.json`). Covered by `CLIDetectorTests`.
  Headless proof reachable via `alln detect`. **Still pending:** the live founder
  smoke run against real CLIs (§12 "Founder live first-run").
- **Phase 2 — Wire existing UI + health == runs. BUILT (2026-06-15).** `AppModel`
  runs `CLIDetector.probeAll` + caches; and **`WorkerRunner` now spawns through the
  cached `ToolInvocation`** (direct/shim → absolute path; loginShell → `$SHELL -lic`
  with argv via `"$@"`, no injection), threaded `TeamService(invocations:)` ←
  `ToolRuntime` from `SetupStore`. Empty map → legacy bare command. (The Mac
  run-path adopting the cached invocation is app integration.)
- **Phase 3 — Setup UI (GUI Tier C).** Full-window Setup (Experience Scenes 1–6);
  Doctor sheet → compact roster. **Blocked on designer mocks.**
- **Phase 4 — Auto-team. BUILT (2026-06-15).** `TeamAssembler` assembles Bench +
  default Team from ready sources with a truthful plan writer; persisted in
  `SetupStore.assembledTeam`; `alln detect` detects → assembles → persists. Scene 5
  pre-select is UI (Phase 3).

---

## 12. Testing & proof wall

| Test | Proves |
| --- | --- |
| **Built-bundle integration test** (release gate) | Cause 0 can't return: `Bundle.main` registry non-empty + default team from the built `.app` |
| Packaging CI step | Driver `*.json` manifests present at the built bundle **resource root** (subdir-free; `BuiltBundleConfigTests`) |
| `CLIDetector` unit tests (`MockShell` / `MockCommandRunner`) | sentinel parsing on noisy rc; alias/function → `loginShell`, path → `direct`, missing → `notInstalled`; auth classification (`installedNotSignedIn` vs `probeFailed`) |
| Fixture matrix | launchd-minimal PATH; noisy `.zshrc`; Homebrew path; npm-global; volta/asdf shim; alias/function; app-bundle binary; signed-out stderr; wrong model; timeout |
| Shimmed end-to-end | a `loginShell` tool actually completes a real run (health == runs) |
| Founder live first-run | launched via **`open`** (not Xcode) with the real CLIs — detects all incl. shims, assembles the team, live green flip on sign-in |

Closeout names the **truth owner** (`CLIDetector` + persisted state) and the
**lie-prone layers** (PATH resolution, bundle loading, cache freshness). Until the
Setup UI exists, the none-found and fix-it flows have no UI proof — say so.

---

## 13. Acceptance

- On a machine with Claude Code, Codex, Antigravity (`agy`), and Grok installed +
  signed in: first run detects **all four** (including any installed as
  aliases/shims/app-bundles) and assembles the Bench/default Team with **no typing**.
- A signed-out tool shows `installedNotSignedIn` with the correct `loginFlow`;
  after the user signs in **in Terminal**, a background re-probe flips it to
  `ready` **without restarting the app** and **without requiring app focus**.
- A missing tool shows `notInstalled` with a working install hint; never blocks.
- Runtime invocation uses the **cached `Invocation`** — health and runs share the
  exact spawn path; neither depends on the ambient GUI PATH.
- No source/model is ever shown `ready` (or allowed into a team run) without a
  passing smoke probe.
- **Upgrade path:** existing users in the broken state get Setup on next launch
  when `setupCompletedAt` is nil **or** the registry was empty last run.

---

## 14. Out of scope (v1)

- Auto-installing CLIs (we guide; the user installs).
- API-key / BYOK management inside Allnighter (the CLIs own their auth).
- Per-model editing in Setup (Scene 5 confirms; model tuning lives in Settings).
- Custom model/source creation, and non-CLI / remote models.
- Tools without a shipped manifest remain hidden until real detection exists.
  Cursor Agent is documented in
  `docs/archive/phases/setup/Cursor_Agent_CLI_Support.md`; Aider and
  Gemini-CLI remain future manifest work.
