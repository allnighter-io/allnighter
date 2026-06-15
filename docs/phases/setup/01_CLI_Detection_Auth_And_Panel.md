# First-Run Setup — Detection, Auth & Panel Contract

**Status:** Engineering spec (finalized). Pairs with `00_First_Run_Setup_Experience.md`.
**Owner:** Core/Engine + GUI
**Created:** 2026-06-15 · **Finalized:** 2026-06-15 (mentor review folded in)

This is the truth layer behind the Setup experience: how Allnighter finds the
user's CLIs, decides if each is ready, and assembles the panel — and how that
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
- → `loadDefaultRegistry()` returns an **empty registry** (every worker fails
  Doctor with "no manifest"; detection/PATH/auth never run), and
  `loadDefaultPanel()` returns empty → `AppModel` uses `fallbackPanel()`, a single
  hardcoded Opus worker (= the "1 of 1" the user sees).
- The bundled `panel_default.json` actually defines **6 workers across 4 drivers**.
- Unit tests stayed green because they read manifests from the **source tree**
  (`DesignManifestResourceTests`) or inject a registry — the *built-bundle*
  contract was never asserted.

Fix in §3. **Order of operations: fix Cause 0 first**, then layer discovery (1),
shell-aware detection (2), and guided auth (3).

### Cause 1 — No machine discovery (design gap)
Even with the bundle fixed, the panel is a **static file** — not what's installed
on *this* machine. Real Setup scans and builds the roster from what the user
actually has (§4).

### Cause 2 — The PATH / alias gap (surfaces once detection runs)
`WorkerHealthChecker` runs `detect` (`claude --version`) and `smoke`
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

## 2. Entity model — tool/driver vs worker/seat (read this first)

The single most important clarification: **detection is per-tool, the panel is
per-seat.** They are different cardinalities and the docs/UI must not conflate
them.

- **Tool / driver** = one CLI (`claude`, `codex`, `grok`, `agy`). Keyed by
  `driverId`. **Detection, auth, caching, and the Setup roster are per-tool.**
- **Worker / seat** = a model running on a tool (Opus and Sonnet are two seats on
  the one `claude_code` tool). `panel_default.json` = **6 seats on 4 tools**.

Rules:
- The roll-call roster shows **one card per tool**, not per seat. Tally and the
  title-bar badge are **tool-level**: "4 of 4 tools ready" (or "Claude Code ready
  · 2 seats"), never "4 of 6 ready" implying six installs.
- **One smoke probe per tool.** Per-seat differences are model labels passed to
  the same binary; validate a second model only if cheap and necessary — don't
  run 6 smokes for 4 tools.
- **Synthesizer eligibility stays on `Worker.canSynthesize`** (already used by
  `AppModel.judgeWorker`). Do **not** duplicate it on the tool/registry.
- Scene 5 expands each ready tool into its seats from `panel_default` filtered to
  ready `driverId`s.

---

## 3. Cause 0 fix — packaging + an honest safety net (prerequisite)

Three parts, in priority:

1. **Ship the manifests.** Either ship `Resources/Drivers` as a real **folder
   reference** so `Contents/Resources/Drivers/*.json` exists (XcodeGen
   `resources: - path: Resources/Drivers` with `type: folder` — verify exact
   syntax for the pinned XcodeGen), **or** drop the `subdirectory: "Drivers"`
   lookups and load all `*.json` from the bundle root (simpler, build-system
   agnostic). Prefer the latter for robustness.
2. **Honest runtime safety net — never mask packaging failure.** If the bundle
   registry is empty, fall back to the **embedded real manifests**
   (`DefaultConfig.registry` / `DefaultConfig.workers`) — these are the *same real
   manifests* in code, not fakes, so the app is never hollow. **Retire the silent
   one-worker `fallbackPanel()`** — it turned a catastrophic packaging bug into a
   fake "user setup problem." If **both** bundle and embedded sources are empty
   (a truly broken install), show a **hard, reinstall-style error**, not a
   degraded 1-worker council.
3. **Built-bundle Works-Test as the release gate.** A test that loads from the
   built `.app`'s `Bundle.main` and asserts `loadDefaultRegistry().all.count >= 4`
   and the panel has 6 workers — plus a packaging CI step
   (`test -d AllnighterMac.app/Contents/Resources/Drivers`). This is the test that
   would have caught Cause 0; today's source-tree tests cannot.

> **Dual-source caveat:** the default manifests/workers live in **both**
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
detector emits a **`ResolvedInvocation`**, persisted per tool, consumed by **both**
`WorkerHealthChecker` and `WorkerRunner` so a tool that passes Setup actually runs:

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

Replace the binary `WorkerHealth` (healthy/unhealthy/unknown) with a single honest
status that **Doctor, Setup, and the health badge all consume from one probe and
one persistence store** — no forked truths.

```
enum WorkerSetupStatus {
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
- **`ready` is the only status that lets a worker run**, set only when the smoke
  token actually came back. Never infer ready from presence. (AGENTS.md: "a failed
  worker is shown failed, never faked.")
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
- **`canSynthesize` does NOT live here** — synthesizer eligibility is
  `Worker.canSynthesize` (§2).
- **Roster = shipped drivers only.** Today that's `claude_code`, `codex`, `grok`,
  `antigravity` (+ `manual_paste`). **Do not show ghost cards** for tools with no
  manifest. Cursor / Aider / Gemini-CLI are **phase-2**: ship their manifests +
  smoke contracts first, then add them to the roster. (README ground rule "real
  detection" = no placeholder cards.)
- **Glyphs:** Simple Icons for `anthropic`, `googlegemini`, `x`, `cursor`. Simple
  Icons **removed OpenAI** (trademark) — ChatGPT/Codex uses a **neutral terminal
  chip / SF Symbol**, per `docs/design-system/readme.md`. Opus/synthesizer carries
  the amber; other glyphs tint to brand.

---

## 7. First-run gate

Today nothing gates Compose on setup; `RootView` drops into Compose and runs
Doctor in the background — so a polished Setup would be invisible to most users.

- **`SetupStore.setupCompletedAt`** in Application Support (alongside
  `PanelPresetStore` / `AllnighterPaths.config`).
- First launch **or** never-completed **or** registry-was-empty-last-run →
  full-window **Setup** (Experience Scenes 1–6), not silent Doctor behind Compose.
- **Menu-bar app (`LSUIElement`)**: first launch must **auto-open the main window
  at full size** (≥1100×720) — never hide the WOW behind the menu-bar icon.
- **Never skippable to a 0-ready council.** Require ≥1 ready tool; the none-found
  state (Experience §4) is the empty path.
- Re-entry: Settings → "Re-configure council" re-runs the same flow.
- **Interim gate (before the Setup UI exists):** if `registry.all.isEmpty`, show a
  blocking "bundled drivers missing — reinstall" alert with a copyable fix — never
  the silent 0/1 council.

---

## 8. Auto-building the panel

After detection settles:
- **Seat every worker whose tool is `ready`** (enabled by default) — the fix for
  "I have 4 CLIs, the app shows 1."
- Default active preset: **"All ready"** (a.k.a. "Founder's Six") when ready
  seats ≥3, else **"Fast Council."** Tiered presets (`DefaultConfig.tieredPresets`)
  layer on top of the assembled panel.
- **Synthesizer** default = first ready `Worker.canSynthesize` (prefer Opus 4.8);
  user can change it in Scene 5.
- **Scene 5 is confirm, not configure** — toggles only. **No per-worker model
  editing in Setup** (that stays in Settings).
- Persist the assembled set (a `DiscoveredWorkers` / `LastCouncil` store) so later
  launches don't re-ask. `panel_default.json` + `DefaultConfig.workers` remain the
  seed/fallback and the CLI baseline.

---

## 9. Persistence & launch performance

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
| **Driver manifests (Cause 0)** | `Resources/Drivers` shipped as a group → no `Drivers/` subdir → empty registry + fallback panel | folder reference / subdir-free lookup; **DefaultConfig safety net** (real manifests), retire silent `fallbackPanel`; built-bundle release-gate test |
| Shell resolve | `LoginShell.resolvedPath()` (no sentinel/timeout) | hardened sentinel + timeout + batch + shell diversity (shared `ShellResolver` in Engine) |
| Resolve exec | `SubprocessCommandRunner.resolveExecutable` (PATH scan only) | consume cached `Invocation`; add `loginShell` wrapper for aliases/functions |
| Invocation | `WorkerRunner` execs `invoke.command` directly | both runner + health use the detector's `ResolvedInvocation` (health == runs) |
| Health/status | `WorkerHealthChecker` → `WorkerHealth` (2-state) | `CLIDetector` emits canonical `WorkerSetupStatus` (5-state); Doctor + badge map from it |
| Manifests | `Resources/Drivers/*.json` **and** `DefaultConfig.swift` strings | add additive `setup` block; de-duplicate the two sources |
| Default panel | `AppConfig.loadDefaultPanel()` → static / fallback | first run assembles from ready tools; persisted |
| Gate | none (`RootView` → Compose + bg Doctor) | `SetupStore` first-run gate; full-window Setup; badge opens compact roster |
| UI | Doctor sheet (diagnostic) | Setup flow (Experience 1–6); Doctor becomes the recheck/roster surface |

---

## 11. Build sequencing (no shortcuts, but ordered)

Prove detection on a real machine **before** building the WOW UI.

- **Phase 0 — Unblock (hours).** Packaging fix + `DefaultConfig` safety net +
  built-bundle Works-Test. Outcome: 6 workers appear; Doctor shows *real* reasons,
  not "no manifest." (0/10 → ~4/10.)
- **Phase 1 — Detection core (engine).** `ShellResolver` (sentinel/timeout/batch)
  + `CLIDetector` + known-paths fallback + `ResolvedInvocation` + 5-state status,
  persisted. **Prove headless first:** an `allnighter detect` CLI subcommand (or
  enhanced `doctor`) runnable from Terminal **before any UI**.
- **Phase 2 — Wire existing UI.** Doctor + health badge consume the detector;
  runtime uses cached invocations. User opens app → real "4/6 ready", no Setup yet.
- **Phase 3 — Setup UI (GUI Tier C).** Full-window Setup (Experience Scenes 1–6);
  Doctor sheet → compact roster.
- **Phase 4 — Auto-panel.** Assemble + persist from ready tools; Scene 5 pre-select.

---

## 12. Testing & proof wall

| Test | Proves |
| --- | --- |
| **Built-bundle integration test** (release gate) | Cause 0 can't return: `Bundle.main` registry non-empty + 6-worker panel from the built `.app` |
| Packaging CI step | `Drivers/*.json` present in the built bundle |
| `CLIDetector` unit tests (`MockShell` / `MockCommandRunner`) | sentinel parsing on noisy rc; alias/function → `loginShell`, path → `direct`, missing → `notInstalled`; auth classification (`installedNotSignedIn` vs `probeFailed`) |
| Fixture matrix | launchd-minimal PATH; noisy `.zshrc`; Homebrew path; npm-global; volta/asdf shim; alias/function; app-bundle binary; signed-out stderr; wrong model; timeout |
| Shimmed end-to-end | a `loginShell` tool actually completes a real run (health == runs) |
| Founder live first-run | launched via **`open`** (not Xcode) with the real CLIs — detects all incl. shims, assembles the panel, live green flip on sign-in |

Closeout names the **truth owner** (`CLIDetector` + persisted state) and the
**lie-prone layers** (PATH resolution, bundle loading, cache freshness). Until the
Setup UI exists, the none-found and fix-it flows have no UI proof — say so.

---

## 13. Acceptance

- On a machine with Claude Code, Codex, Antigravity (`agy`), and Grok installed +
  signed in: first run detects **all four** (including any installed as
  aliases/shims/app-bundles) and assembles the panel with **no typing**.
- A signed-out tool shows `installedNotSignedIn` with the correct `loginFlow`;
  after the user signs in **in Terminal**, a background re-probe flips it to
  `ready` **without restarting the app** and **without requiring app focus**.
- A missing tool shows `notInstalled` with a working install hint; never blocks.
- Runtime invocation uses the **cached `Invocation`** — health and runs share the
  exact spawn path; neither depends on the ambient GUI PATH.
- No worker is ever shown `ready` (or allowed to run) without a passing smoke probe.
- **Upgrade path:** existing users in the broken state get Setup on next launch
  when `setupCompletedAt` is nil **or** the registry was empty last run.

---

## 14. Out of scope (v1)

- Auto-installing CLIs (we guide; the user installs).
- API-key / BYOK management inside Allnighter (the CLIs own their auth).
- Per-worker **model editing** in Setup (Scene 5 confirms; model tuning lives in
  Settings).
- Custom worker creation, and non-CLI / remote workers.
- Tools without a shipped manifest (Cursor/Aider/Gemini-CLI) — phase-2.
