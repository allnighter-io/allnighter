# GUI Visual Proof Gate

Status: **Standing GUI law** (promoted from phases 2026-07-26)
Owner: GUI workflow + Mac app native proof harness
Updated: 2026-08-15 — S06 diff-scoped gate + ratchet (see § below)

Closed phase packet history: was `docs/phases/GUI_Visual_Proof_Gate.md`
(moved here — no separate archive copy).

Founder intent:
Stop the productivity-killing loop where an AI agent says "fixed" and hands
back broken GUI. The founder must not be the agent's first pair of eyes.

Product value:
Preserve the native Swift app path without accepting blind UI development.
Allnighter is a local Mac/iPhone Project Manager; native Swift remains the right
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
shape is a native Mac app plus iOS Project Manager.

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

After a watcher PASS, seal the packet — this is what the wall checks. Name
BOTH the fixtures rendered AND the exact view files those fixtures reviewed
(never "everything that happens to be dirty" — see § Seal only what was
reviewed below):

```text
bash scripts/gui_proof_seal.sh <surface> <slug> \
    --fixtures <fixture> [<fixture>...] \
    --views <file> [<file>...]
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
  <slug> --fixtures <fixture>... --views <file>...` — paste the verdict into
  the packet's `watcher.md`, then say `fixed` with the closeout language above.
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
  mixed-health rows, deep-links the captured state, and composites the app's OWN
  windows to a PNG (`ALLNIGHTER_GUI_PROOF_OUT`) with no probes, no network, no
  quota.
- `scripts/gui_proof.sh <fixture>` — builds, launches the fixture, waits for the
  PNG, prints its path.

**Capture (2026-06-17+): tiered, native overlays for compose only.**
- Fixtures without native popovers (`home-*`, `thread-*`, `team-*`, readiness,
  doctor, etc.) use an in-process main-window bitmap snapshot of the primary
  content view (`cacheDisplay` on the contentView). Deterministic, no Screen
  Recording permission, no TCC dialog, no grant.
- `compose-*` (and the diagnostic `tcc-probe`) use the full composite of the
  app's own windows via **ScreenCaptureKit** (`SCScreenshotManager.captureImage`)
  so native SwiftUI `.alPopover` popovers (separate OS
  windows created by AppKit) appear in proofs. These are the only cases that
  require the one-time Screen Recording grant for the Debug bundle.

This preserves the invariant that native popovers are used and provable, while
unblocking layout proofs for conversation shell / home / thread surfaces (CR4)
that have no popovers in the captured state. The first cut used only main-window
self-capture (insufficient for popovers) then moved everything to composite
(over-constrained the non-popover cases). Tiering is the minimal durable fix.

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

Status: Done 2026-06-16. Superseded in its exact mechanics by S06 below — read
S06 for current behavior; this entry is kept for history.

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

### S06 - Diff-Scoped Gate + Ratchet (fixed 4 real incidents, 2026-08-15)

Status: Done 2026-08-15.

S05's "changed since `scripts/.gui_proof_baseline`" scope was a fixed commit
from the gate's introduction (2026-06-16). Months later that baseline is
thousands of commits behind HEAD, so "changed since baseline" had quietly
become "differs from a stale snapshot of the whole repo" — in practice,
nearly the whole repo. Four concrete incidents on 2026-08-14/15 forced a
rework:

1. A CLI-only packet (zero GUI edits) was blocked by `BoostWindowView` debt
   left behind by an unrelated packet.
2. Running `gui_proof_seal.sh` after reviewing ONE surface bound ALL ~67
   visible views into that packet's manifest as `watcher: PASS` — silently
   attesting unreviewed views, some with real P1 bugs. Caught by accident;
   the seal had to be deleted.
3. The gate ran inside `check-fast.sh`, which runs before `swift test` in
   `check.sh` and hard-stops on any non-zero exit. While any view lacked
   proof, nobody could get a full Swift-suite result at all.
4. Commit `dcec8b0f` (a 24-line mechanical string refactor across 9 view
   files, wiring SwiftUI chrome labels to a copy SSOT) invalidated 9 content
   hashes at once and blocked every later closeout until someone froze them
   into `DEBT.manifest`.

**A. Block on the diff, report the repo.** `ALLNIGHTER_GUI_PROOF_BASE`
now defaults to `HEAD` — i.e. your diff is your own uncommitted change
(staged + unstaged + untracked), not "everything since some ancient
baseline". Only a visible view *your diff* touches can fail *your* run. A
change that touches no view under `Apps/AllnighterMac/Sources` exits 0
immediately: "no visible GUI surface in your diff". Repo-wide pre-existing
debt (any current view whose content isn't covered by a proof/waiver,
whether or not it's in your diff) is still computed and printed every run —
names + count — so nobody has to go spelunking to find out what's owed, but
it never gates an unrelated change. `scripts/.gui_proof_baseline` (the old
grandfather SHA) is no longer read by the gate; CI still overrides
`ALLNIGHTER_GUI_PROOF_BASE` explicitly (e.g. `origin/main`) for full-PR
scope, since CI has no uncommitted state of its own to diff against `HEAD`.

**B. Ratchet.** Repo-wide debt (the same full scan used for the report
above) is compared against a persisted ceiling: `scripts/.gui_proof_debt_baseline`
— a single integer, committed. If the current count ever exceeds it, the
whole gate fails with a `RATCHET FAILED` message, *even on an empty diff* —
this is a backstop against debt sneaking in some way other than an honest
diff (a bypassed local gate, a manual manifest edit, a force-push). The
ceiling only ever moves **down**: `scripts/gui_proof_seal.sh` tightens it
automatically whenever a seal reduces total debt below the current ceiling;
nothing in this gate ever raises it. Raising it is a deliberate, reviewed
edit to that one file, same as raising any other budget in this repo (see
`scripts/check-fast.sh`'s `AGENTS.md` byte budget for the same pattern).

**C. Seal only what was reviewed.** `gui_proof_seal.sh` no longer
auto-binds "every view that differs from `BASE`" into the sealed packet —
that is exactly the mechanism that caused incident 2. It now requires an
explicit `--views <file>...` list; only those files are bound as `watcher:
PASS`. We looked at whether `GUIFixture.swift`'s capture path (in-process
main-window bitmap / ScreenCaptureKit composite) could emit a sidecar
listing which SwiftUI view types actually mounted during a fixture render —
it cannot without new Swift instrumentation (SwiftUI does not expose a
mounted-view-identity hook, and this fix's scope was scripts-only). So the
fallback in the original ask is what shipped: any OTHER view that changed in
the same diff but was **not** named in `--views` is never marked proven — if
it isn't already covered by some other proof, it's recorded into
`docs/qa/gui/DEBT.manifest` at its current hash and printed loudly as
collateral debt. It still gates the current run if it's genuinely in your
diff (the diff-scoped check in `check_gui_proof.sh` runs independently of
what any seal decided). Nothing is ever silently upgraded to proven.

**D. Tests after the gate, not before.** The gate call moved out of
`check-fast.sh` (which runs first in `check.sh` and hard-stops the whole
wall on any non-zero exit) and into `check.sh` directly, positioned after
every Swift/Mac test phase. Its exit code is captured non-fatally
(`bash scripts/check_gui_proof.sh || gui_proof_status=$?`) so the Swift
suite, the structural works test, the contract-export check, and the Mac
`xcodebuild test` phase all run and report **regardless of GUI gate state**.
`check.sh` still fails the wall overall if the gate failed — that check is
deferred to the very end, after the timing footer, so a red GUI gate is
never hidden, it just no longer prevents the rest of the wall from being
measured.

Config surface for `scripts/check_gui_proof.sh` / `scripts/gui_proof_seal.sh`
/ `scripts/gui_proof_waive.sh`:

```text
ALLNIGHTER_GUI_PROOF_BASE            diff base (default HEAD; CI: origin/main)
ALLNIGHTER_GUI_PROOF_WAIVER          one-shot bypass, non-empty reason (local only)
ALLNIGHTER_GUI_PROOF_ROOT            override repo root       (works-tests only)
ALLNIGHTER_GUI_PROOF_SRC_DIR         override gated source dir (works-tests only)
ALLNIGHTER_GUI_PROOF_PACKET_ROOT     override proof packet root (works-tests only)
ALLNIGHTER_GUI_PROOF_DEBT_BASELINE   override the ratchet ceiling file (works-tests only)
```

Proof: `scripts/works-test-gui-proof-gate.sh` — a throwaway temp-git-repo
harness (never touches the real checkout's `Apps/` or `docs/qa/gui/`) proving
all four of A-D plus the check.sh ordering, run with `bash
scripts/works-test-gui-proof-gate.sh`.

Exit gate (met): a repo with pre-existing debt and a change touching no view
passes; a change touching one view requires only that view; sealing one
surface never marks an unrelated changed-but-unreviewed view as proven; the
ratchet rejects a debt increase even on an empty diff; the Swift/Mac test
phases in `check.sh` run and report even when the gate is red.

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
  quota-bearing invocations.
- **Screen-Recording permission (dev machine only, compose popovers only).**
  Most proof fixtures use a pure in-process main-window snapshot and require
  zero extra permissions. Only `compose-*` fixtures (native SwiftUI popovers via
  `.alPopover`) and the `tcc-probe` diagnostic take the composite path over the
  app's own windows via ScreenCaptureKit and therefore needs the Screen Recording grant
  (one time, via `gui_proof_grant.sh`, for the Debug `com.allnighter.mac`
  bundle). The harness is DEBUG-only and gated behind the proof request file /
  env; the Release app never contains or executes any of this code. Grant is
  attributed via Launch Services launch of the .app bundle. Without the grant,
  compose proofs fail hard (no silent PNG missing the popover); non-compose
  proofs continue to work.
- Captures must not include credentials, secret-bearing paths, or private user
  content — fixtures use mock data only, and only the app's own windows are
  composited (not the wider desktop).

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
  `bash scripts/check.sh` (S05), running after the Swift/Mac test phases,
  diff-scoped, with a repo-wide debt ratchet (S06).

## Open Questions

None blocking. All build items (S00-S06) are done. Golden pixel diffs stay
deferred until a watcher miss proves they are needed. A future slice could
revisit "sealing only what was reviewed" if `GUIFixture.swift` grows a real
mounted-view sidecar — see S06 §C for why that's out of scope today.
