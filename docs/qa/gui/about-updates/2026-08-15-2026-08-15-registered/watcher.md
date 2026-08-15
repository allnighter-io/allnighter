# layout-watcher verdict — About & updates

Reviewed 2026-08-15 against `settings-about-updates.png`, rendered fresh this
session at current HEAD. Reviewed by the PM directly (single-page surface, no
overlays, no dynamic-width lists).

## VERDICT: PASS — no P1, no P2

## Why this view had no proof until today

`AboutUpdatesView` was the only app view with **no runnable fixture**.
`GUIFixture.swift` carried routing for `.about` under two names —
`settings-about-updates` and `studio-about-updates` — but **neither was
registered in the `benchScenarios` catalog**, so `gui_proof.sh` rejected both.
Dead routing. Not a deliberate omission; simply never finished.

It briefly held a waiver stating plainly that it was *unproven, not "probably
fine."* That waiver is now **retired and removed from
`docs/qa/gui/WAIVERS.manifest`**, superseded by this capture-based proof. A
waiver claiming a view cannot be proven must not survive alongside a seal
proving it.

## What was fixed to make it capturable

1. **Registered** `settings-about-updates` in `benchScenarios`, activating the
   existing dead routing rather than inventing a third spelling.
2. **Collapsed** the duplicate `studio-about-updates` name — it appeared in
   exactly one place and nowhere else in the repo. One name, not two half-wired
   ones.
3. **Killed a live network call.** `AboutUpdatesView.onAppear` fires
   `ReleaseUpdateModel.refresh()`, which fetches `get.allnighter.io/latest.json`
   and reads the real on-disk release cache. A proof fixture reaching a live
   vendor violates `Execution-Playbook.md` § Green Wall rule 8 — the rule that
   exists because a "stubbed" test once sent real prompts to a live
   `opencode serve` and burned real quota. Suppressed via the existing
   `ALLN_NO_UPDATE_CHECK` kill-switch, scoped to this fixture only.
4. **Pinned the clock.** "Last checked" read live `Date()`. Now seeded to a
   fixed instant, `2026-08-14 09:41 UTC`, gated on `GUIFixture.active` under
   `#if DEBUG`. Production is untouched: a real user still gets a real
   timestamp. The gate is explicit at the call site and keyed to the fixture
   name — **not** inferred from an injected double, per the seam that previously
   let a live-vendor test through.

## Prediction verified against pixels

The implementing agent predicted the render before any capture existed. The
capture matches: header, "This build" card (App 1.1.5 / CLI identity 1.1.19),
the up-to-date "App is current" card with no CLI-update card, the CLI-on-PATH
card, and the release-channel card, in one scrollable max-width column.

The seeded instant renders as **"Last checked Aug 14, 2026 at 2:41 AM"** —
09:41 UTC formatted to local PDT. The underlying instant is fixed and
machine-independent; only the displayed string passes through the OS locale
formatter. Predicted and observed agree.

## Accepted, with reasoning rather than reflex

The CLI-on-PATH card reads real `PATH` and shows real install paths. Left as-is
deliberately: reading `PATH` is local process introspection, not the live vendor
or real account state Green Wall rule 8 targets. The paths vary machine to
machine as *content*, not *structure* — the same class as version numbers. The
one branch that could alter layout is `pathConflict`, and `settings-use-from-cli`
already ships that exact live-`PATH` branch as accepted precedent. If it is ever
pinned, the same `GUIFixture.active` gate used for the timestamp applies.

Reviewer: PM, direct sighted inspection.
