# 10 — Capture to Work Order

Status: Draft
Milestone: C (Mobile floor manager)
Depends on: 01, 05, 09
Owner: iOS + Shared Core
Created: 2026-06-13

## Goal

Let the user capture intent quickly (text, voice, screenshot, share sheet) and
turn it into an **editable interpretation** that becomes a normalized work order,
saved to the backlog or dispatched. Capture is the top of the funnel; it must be
nearly typing-free.

## Non-Goals

- Race/council dispatch UI (Milestone D) — single dispatch + save-to-backlog here.
- Siri/App Intents and full share-sheet matrix can be incremental after text +
  voice + screenshot.

## Approach (per source §10, Principles 1–4)

- **Capture modes:** text; **voice via on-device `Speech` (SFSpeechRecognizer)** —
  keeps audio local, no secret; screenshot/photo; Share Sheet item; pasted
  URL/issue.
- **Interpretation step** (source §10.3): show "Here's what I understood …" with
  inferred title, category, acceptance criteria, constraints, and a proposed
  dispatch mode; buttons: **Dispatch · Edit · Ask council first · Save to backlog**.
- Work order is the Core `Task`/work-order shape (`00` §7) enriched with project
  standing orders + protected paths at construction time.
- Backlog list with source labels, priority, dispatch mode (IOS-3).

## Ordered Slices

- [ ] P10-S01 — Text capture → work-order draft.
- [ ] P10-S02 — On-device voice transcription → work-order draft.
- [ ] P10-S03 — Screenshot/photo attachment as context ref.
- [ ] P10-S04 — Interpretation view (editable) with the four action buttons.
- [ ] P10-S05 — Save to backlog (`POST /projects/:id/tasks`).
- [ ] P10-S06 — Single dispatch (`POST /tasks/:id/dispatch`) → lane appears in Active Lanes.
- [ ] P10-S07 — Share Sheet extension (screenshots, notes, URLs).

## Works Test

```text
Dictate "make the dashboard feel more premium" on the phone. The app shows an
editable interpretation; confirming saves it to the Mac backlog. Dispatching it
creates a lane that appears in Active Lanes and runs to completion.
```

## Exit Gates

- [ ] Works Test passes (voice + text paths).
- [ ] Voice transcription is on-device; no audio leaves the phone.
- [ ] IOS-2, IOS-3, IOS-13, IOS-14 satisfied.
- [ ] Code Audit CLEAN.

## Closeout

Milestone C complete. Activate Phase 11 (Draft Race — the wedge).
