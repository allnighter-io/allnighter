# 06 — Preview and Artifact System

Status: Draft
Milestone: B (Proof and previews)
Depends on: 03, 05
Owner: Mac
Created: 2026-06-13

## Goal

Make lanes produce **artifacts, not logs**: boot each lane's preview on a unique
port, prove it is actually up, capture screenshots (and optional short video),
store them, and expose them via the API. This is the "prefer artifacts over logs"
principle made real and the foundation for races and QA.

## Non-Goals

- Landing (Phase 07), race comparison UI (Phase 11), QA pass/fail logic (Phase 18
  — this phase provides the capture sidecar QA reuses).

## Approach (per `00` §9.5, §9.7)

- **Preview supervisor:** run the project's `preview_command` (port templated in)
  in the lane worktree as a supervised process in the lane's process group.
- **Readiness probe:** poll the port until TCP-accept + HTTP 200 on a configurable
  path; timeout → lane `failed` with a clear reason (do not capture a blank page).
- **Capture sidecar:** Node + Playwright under `Sidecars/capture/`; the Mac
  invokes it to screenshot declared viewports and optionally record a short video;
  outputs land in the lane Artifacts dir and register `Artifact` records.
- **Artifact store + API:** persist artifact metadata; serve via
  `GET /lanes/:id/artifacts`; thumbnails for fast UI.
- **Recovery:** preview processes are reconciled like agent processes (`00` §9.2).

## Ordered Slices

- [ ] P06-S01 — Preview supervisor using project `preview_command` + port broker.
- [ ] P06-S02 — Readiness probe (TCP + HTTP 200) with timeout → `failed` reason.
- [ ] P06-S03 — Node + Playwright capture sidecar (screenshot at viewport set).
- [ ] P06-S04 — Optional short preview recording.
- [ ] P06-S05 — Artifact storage + records + thumbnails.
- [ ] P06-S06 — `GET /lanes/:id/artifacts` API + Mac lane preview view.

## Works Test

```text
A lane boots its preview on a unique port, the readiness probe confirms HTTP 200,
the sidecar captures a screenshot, the artifact is stored and visible in the Mac
lane view, and the preview URL opens the running app. Two lanes run previews on
different ports without collision.
```

## Exit Gates

- [ ] Works Test passes on the bundled sample web app and one real repo.
- [ ] Readiness probe prevents blank/failed captures.
- [ ] MAC-6, MAC-7, MAC-8 satisfied.
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 07. The capture sidecar is now the shared base for QA (Phase 18).
