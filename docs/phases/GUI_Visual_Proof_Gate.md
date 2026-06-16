# GUI Visual Proof Gate

Status: Founder packet / execution-ready policy phase
Owner: GUI workflow + Mac app native proof harness
Updated: 2026-06-16

Founder intent:
Stop the productivity-killing loop where an AI agent says "fixed" and hands
back broken GUI. The founder must not be the agent's first pair of eyes.

Product value:
Preserve the native Swift app path without accepting blind UI development.
Allnighter is a local Mac/iPhone floor manager; native Swift remains the right
production stack. The fix is a hard visual proof gate, not a rewrite.

Trusted workflow slice:
Any GUI slice that changes visible layout, copy hierarchy, component state,
popover/sheet behavior, navigation, or a user-facing workflow can close only
after the agent renders the changed surface to a screenshot and a disinterested
**layout-watcher** agent looks at it and returns no P1 breakage.

Non-goals:
- Do not migrate the production app to Tauri as the immediate fix.
- Do not make the founder perform first-line QA.
- Do not treat SwiftUI build success, previews, or code inspection as visual
  proof.
- Do not require XCUITest, golden-image pixel diffs, or content/accessibility
  assertions. CLI/Core tests own content and data truth; this gate owns LAYOUT
  only (is it visible, aligned, on-screen, stacked right).
- Do not add broad cleanup to GUI bug fixes.
- Do not block non-visual Core/CLI work on this gate.

## Decision

Keep the production app native SwiftUI. Add a mandatory sighted workflow around
it.

The bug is not "Swift is bad." The bug is that the workflow allowed agents to
close GUI work from code confidence. A build can pass while the user sees an
empty list, clipped popover, wrong subtitle, dimmed overlay, or broken z-order.
That permission is revoked.

Tauri is rejected for the current crisis. It would make screenshots marginally
easier, but it would not remove the need for a native render and a sighted
watcher — and it would add a second platform stack while Allnighter's strategic
shape is a native Mac app plus iOS floor manager.

The mechanism is sight, not machinery. An LLM has good eyes; the failure was
never that it could not see — it was that the building agent, motivated to close
the ticket, was never required to look. So: render the surface to a real
screenshot, then spawn a **separate, disinterested layout-watcher** that looks at
the pixels and hunts for breakage. The separation is what keeps the eyes honest —
the watcher did not write the code and gains nothing by passing it. The founder
is the final taste and business check, not the first discovery of broken pixels.

## Bug Packet

Tier: T3 repeated workflow bug

Symptom / repro:
Agent claims a GUI fix is done. Founder opens the Mac app and sees first-order
visual failure: missing rows, zero-height list, clipped/dropdown layout, wrong
information architecture, scrim/z-order damage, or copy jammed into the wrong
element.

Bug fingerprint:
`Apps/AllnighterMac GUI surface + "fixed" without rendered proof + missing visual gate`

Truth owner:
- Product/domain truth: `AllnighterCore`, `TeamRunJSON`, phase docs.
- Visual truth: `docs/design-system/readme.md`,
  `docs/design-system/production.md`, and the relevant UI kit.
- GUI engineering truth: `docs/gui/GUI_Workflow.md` plus this phase doc.
- Proof truth: `docs/qa/gui/<surface>/<date>-<slug>/` proof packets once S00
  creates that path.

Lie-prone layer:
- SwiftUI views that can compile while rendering empty, clipped, overlapped, or
  offscreen content.
- Agent closeout language that says "fixed" after build/test only.
- HTML handoff packs treated as optional reference instead of a visual gate.
- Founder review used as the first visual test.

RCA:
The process had no wall that forced rendered evidence before closeout. Agents
could read specs, edit Swift, run compiler tests, and call the result fixed
without seeing the surface. The founder became the screenshot harness.

Regression law:
No GUI-visible slice is fixed until a rendered proof packet exists. If the
agent cannot render or inspect the changed surface, closeout says
`implemented, visually unverified` or `blocked`, never `fixed`.

## First Principles

Build success has zero visual content. A view compiles while rendering empty,
clipped, overlapped, or off-screen.

An LLM has good eyes. The failure was never that it could not see — it was that
the building agent, motivated to close the ticket, was never required to look,
and so judged its work from code confidence. Fix the incentive: render real
pixels and hand them to a separate agent that gains nothing by passing them.

The native render is mandatory because only it catches Swift-specific failures:
`ScrollView` sizing, z-order/scrim, popover clipping, title-bar/AppKit bridge
behavior. A browser mock cannot show these; it is only a comparison reference.

Layout is this gate's whole job. Content and data truth — wrong subtitle, fake
success, wrong count — belong to CLI/Core tests, which already own them. Do not
rebuild that ownership here as accessibility assertions; keep the gate fast.

Founder review is a taste and strategy checkpoint. It is not the first proof of
basic rendering.

## New Semantic Rules

1. `Fixed` is a reserved word for GUI work. It requires a native render that a
   layout-watcher has looked at and passed.
2. The agent that wrote the change does not get to be its own watcher. Spawn a
   separate layout-watcher; the building agent's own "I looked, it's fine" is the
   same lie as "fixed."
3. The watcher judges LAYOUT only — visible, aligned, on-screen, stacked right.
   Content and data correctness belong to CLI/Core tests, not this gate.
4. A P1 (clipped, overlapping, collapsed, off-screen, scrim/z-order, detached,
   missing) blocks closeout. A P2 (minor misalignment/spacing/proportion/ugly
   truncation) is advisory and does not block.
5. A known P2 delta is allowed only when named in the closeout and tied to a
   follow-up or explicit waiver.
6. A failed worker, missing login, unavailable model, timeout, or unknown state
   must render honestly in the fixture so the watcher can see it.
7. If an agent lacks a working render path (the fixture or capture is broken), it
   must stop and say the GUI proof gate is blocked — never `fixed`.
8. Founder screenshots are evidence of a failure, not agent proof of a fix.

## Proof Packet Contract

Kept deliberately small so the gate adds velocity, not paperwork. The only
non-negotiable artifact is **a native render the watcher looked at**.

Captures land at a stable path during iteration:

```text
docs/qa/gui/_captures/<fixture>.png      (overwritten each run; git-ignored)
```

After a watcher PASS, seal the packet — this is what the wall checks:

```text
bash scripts/gui_proof_seal.sh <surface> <slug> <fixture> [<fixture>...]
```

```text
docs/qa/gui/<surface>/<YYYY-MM-DD>-<slug>/
  native.png        # the rendered fixture state that passed (native-<fixture>.png if many)
  proof.manifest    # binds each proven view to its exact git blob hash + watcher: PASS
  watcher.md        # the layout-watcher's verdict (PASS, P1=none, P2 notes)
  mockup.png        # OPTIONAL — only if a rendered visual target exists
```

**Proof is bound to content, not to "a packet exists."** `proof.manifest` records
the git blob hash of each view it proved. The wall requires every *currently
changed* view's *current* hash to be covered by some manifest. So a Team-dropdown
packet can never satisfy a Composer change (different file, different hash), and
re-editing any view makes its old proof stale — you must re-render and re-seal.
A non-visible change to a view file (comment, pure-logic refactor) is waived
content-bound instead: `bash scripts/gui_proof_waive.sh "<reason>" <file>...`.

Closeout language:

```text
Visual proof:
- Fixture: <fixture-name>
- Command: bash scripts/gui_proof.sh <fixture-name>
- Render: docs/qa/gui/.../native.png
- Watcher: PASS (P1: none)
Known deltas (P2): <named, or none>
Founder test: <one gesture to confirm feel>
```

No watcher PASS means no `fixed`.

## Workflow

### 1. Route

Classify the GUI work through `docs/gui/GUI_Workflow.md`. Tier A (tiny
paint/copy/icon) needs one render the watcher passes. Tier B-D needs the same,
in each affected fixture state. Tier D still owes Core/contract tests for
behavior — the layout gate never replaces those.

### 2. Build

Implement the smallest Swift change. Views consume named design tokens and
Core/presenter state. They do not invent model labels, worker counts, health
states, readiness, quota, or progress.

### 3. Render

Capture the changed surface in a deterministic fixture state:

```text
bash scripts/gui_proof.sh <fixture-name>
```

This builds the app, launches it probe-free in `ALLNIGHTER_GUI_FIXTURE=<name>`,
deep-links the target state (e.g. the Team dropdown open), self-captures its own
window to a PNG (no Screen-Recording TCC), exits, and prints the PNG path.
Fixtures live in `Apps/AllnighterMac/Sources/GUIFixture.swift`. If the surface
has multiple visible states (empty, mixed, error), render each.

### 4. Look

Spawn the **layout-watcher** (`.claude/agents/layout-watcher.md`) on the
render(s). It is a separate agent — never the one that wrote the code. Give it
the PNG path(s) and the mockup path if a rendered one exists. It returns a
verdict: P1 breakage (blocks) and P2 notes (advisory).

### 5. Seal Or Block

- Watcher PASS (no P1): seal it — `bash scripts/gui_proof_seal.sh <surface>
  <slug> <fixture>...` — paste the verdict into the packet's `watcher.md`, then
  say `fixed` with the closeout language above.
- Watcher FAIL (P1): not fixed. Fix and re-render until PASS.
- Capture/fixture broken: `blocked on visual proof harness`, never `fixed`.

Render and seal the surface(s) you actually touched — not every screen. A global
token change uses one or a few representative impacted fixtures. The wall binds
each changed view to its content hash, so stale or unrelated proof will not pass.

## Immediate Stop-Bleed Rule

Any GUI work touching a visible view in `Apps/AllnighterMac/Sources/*.swift` must
end in one of:

1. a sealed packet whose `proof.manifest` covers each changed view's current
   hash (a layout-watcher PASS on a render of those surfaces);
2. a content-bound waiver (`gui_proof_waive.sh`) for a non-visible view change;
3. a blocker saying the render/watcher path could not be produced.

The founder should not accept "fixed" for a visible GUI change without the
watcher verdict and the fixture name to reproduce it.

## Implementation Plan

### S00 - Policy And Routing

Status: Done 2026-06-16

Make the rule durable: this phase doc, routed from `docs/phases/README.md`;
`docs/gui/GUI_Workflow.md` binds GUI closeout to the gate; `docs/qa/gui/README.md`
carries the packet contract; debugger backlog row added.

### S01 - Native Render + Self-Capture Harness

Status: Done 2026-06-16

This is the eyes, and it shipped as ONE command instead of an XCTest
investment:

- `Apps/AllnighterMac/Sources/GUIFixture.swift` — env-gated designer mock
  (`ALLNIGHTER_GUI_FIXTURE`). Inert on every real launch. Seeds deterministic
  mixed-health rows, deep-links the captured state, and self-renders the window
  to a PNG (`ALLNIGHTER_GUI_PROOF_OUT`) with no probes, no network, no quota,
  and no Screen-Recording TCC prompt.
- `scripts/gui_proof.sh <fixture>` — builds, launches the fixture, waits for the
  PNG, prints its path.

Why self-capture, not `screencapture`/XCUITest: grabbing another process's
window needs Screen-Recording permission — re-opening the launch-TCC code red —
and XCUITest is slow, flaky, and built to assert content, which the CLI already
owns. Rendering our own window is permission-free and deterministic.

Fixtures: `team-open-ready`, `team-open-mixed` (more added per surface).

Exit gate (met): one command produces a native screenshot of a deep-linked
state with no founder involvement.

### S02 - Layout Watcher

Status: Done 2026-06-16

`.claude/agents/layout-watcher.md` — a disinterested agent that LOOKS at the
render and hunts layout breakage (P1 blocks, P2 advisory), cites evidence, and
compares to a mockup when one is supplied. Separation from the building agent is
what keeps the verdict honest.

Exit gate (met): a clipped/collapsed/detached/overlapping/off-screen surface
fails before founder review. Proven on the Team dropdown — FAIL (clipped header,
detached popover) → fix → PASS.

### S03 - Pilot: Team Dropdown

Status: Done 2026-06-16

The broken Team dropdown was the pilot because it carried the whole failure
class (collapse, overlay alignment, z-order, footer affordances). The gate
caught the top-clip + detach, the panel was moved to a top-level RootView
overlay below the title bar (the proven `showDoctor` pattern), and a re-run
returned PASS. Capture: `docs/qa/gui/_captures/team-open-mixed.png`.

### S04 - Deferred: Golden Diffs (only if needed)

Status: Deferred — not built, and not built unless a regression proves it
necessary.

The live watcher is the gate. Golden-image pixel diffs are regression hardening
with real cost (threshold tuning, retina noise) and are explicitly out of scope
until the watcher misses a layout regression the founder then finds. Content and
accessibility assertions are NOT planned here at all — CLI/Core tests own truth.

### S05 - Meta-Gate

Status: Done 2026-06-16

`scripts/check_gui_proof.sh` (wired into `scripts/check.sh`) fails the wall when a
visible SwiftUI surface changed without a proof packet or an explicit waiver:

- Visible = a changed `Sources/*.swift` declaring a `View`/`App`/Preview; pure
  logic/model/presenter files are not gated.
- **Content-bound, not packet-presence.** Each changed view's *current* git blob
  hash must appear in some `proof.manifest` (with `watcher: PASS`) or in
  `WAIVERS.manifest`. Re-editing a view changes its hash → old proof goes stale;
  a packet for one surface can't satisfy a different surface's view. This is what
  keeps the wall true after the first packet exists.
- Grandfathered to `scripts/.gui_proof_baseline` (the gate commit) so it does not
  retroactively flag pre-gate GUI work — only changes after the baseline count.
- Detects untracked packets, so the commit-first workflow can't slip past.
- Resolutions: seal a packet (`gui_proof_seal.sh`), a content-bound waiver
  (`gui_proof_waive.sh`), or one-shot `ALLNIGHTER_GUI_PROOF_WAIVER="reason"` (CI
  can't use it). CI may set `ALLNIGHTER_GUI_PROOF_BASE=origin/main` for full-PR
  scope.

It enforces that the evidence ritual happened — not that pixels are correct. The
layout-watcher PASS remains the real check; this makes producing one mandatory.

Exit gate (met): a visible GUI change without a packet or waiver fails
`bash scripts/check.sh`.

## Tauri Revisit Trigger

No Tauri migration now.

Revisit only if all are true:
- S00-S03 are implemented;
- agents still produce two founder-found P1 visual regressions after claiming
  `fixed` with proof packets;
- the failures are caused by inability to render/inspect native SwiftUI, not by
  ignored process rules;
- a founder approves a scoped design-lab phase.

Even then, Tauri is evaluated as a design/proof lab first, not as an automatic
production rewrite.

## Implementation Impact

Mac app impact:
- `GUIFixture.swift` adds an env-gated fixture launch + self-capture path. Inert
  on real launches; keeps production SwiftUI native.

iOS app impact:
- Same pattern when iOS resumes: a fixture launch + simulator self-capture (or
  `xcrun simctl io ... screenshot`) feeding the same layout-watcher.

Driver/protocol impact:
- None for the layout gate.
- Tier D surfaces still need Core/TeamRunJSON/state tests for behavior.

Auth/privacy/permissions impact:
- Fixture mode disables real CLI probes, shells, auth checks, network, and
  quota-bearing invocations, and never captures another process's window (no
  Screen-Recording TCC).
- Captures must not include credentials, secret-bearing paths, or private user
  content — fixtures use mock data only.

Design-system impact:
- A rendered mockup, when one exists, is the watcher's comparison reference. A
  stale mockup yields only advisory P2 deltas, never a block.

## Works Test (met)

Team dropdown, fixture `team-open-mixed`: six seeded workers, mixed health,
dropdown deep-linked open, probes disabled.

Required result — all confirmed by the watcher on the post-fix render:
- dropdown has non-zero height and hangs below the title bar, fully on-screen;
- all expected worker rows visible; ready rows show the green dot; broken rows
  show the issue badge + Repair;
- "Your bench" header and "Manage team" footer present and not clipped;
- no scrim dims the active popover; no overlap.

Founder pass condition: the founder opens the app, clicks the Team control, and
finds no first-order visual failure the watcher should have caught.

## Proof Commands

```text
# Render a fixture and capture its window (prints the PNG path):
bash scripts/gui_proof.sh team-open-mixed

# Then spawn .claude/agents/layout-watcher.md on that PNG for the verdict.

# Behavior wall (unchanged — owns content/state truth):
swift test --package-path Packages/AllnighterCore
xcodebuild test -scheme AllnighterMac -destination 'platform=macOS'
bash scripts/check.sh
```

If `gui_proof.sh` cannot produce a PNG, the GUI work is `blocked on visual proof
harness`, never `fixed`.

## Done When

- [x] This phase is routed from `docs/phases/README.md`.
- [x] `docs/gui/GUI_Workflow.md` binds GUI closeout to a layout-watcher PASS.
- [x] `docs/qa/gui/README.md` exists.
- [x] Native render + self-capture harness exists (`GUIFixture.swift` +
  `scripts/gui_proof.sh`).
- [x] Layout-watcher agent exists (`.claude/agents/layout-watcher.md`).
- [x] Team dropdown pilot rendered, caught (FAIL), fixed, and re-verified (PASS).
- [x] Debugger binds GUI-visible bugs to the layout gate.
- [x] GUI proof meta-gate (`scripts/check_gui_proof.sh`) is wired into
  `bash scripts/check.sh` (S05).

## Open Questions

None blocking. All build items (S00-S05) are done. Golden pixel diffs stay
deferred until a watcher miss proves they are needed.
