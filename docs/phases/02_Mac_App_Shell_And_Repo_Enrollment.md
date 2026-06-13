# 02 — Mac App Shell and Repo Enrollment

Status: Draft
Milestone: A (Substrate)
Depends on: 01
Owner: Mac
Created: 2026-06-13

## Goal

Stand up the Mac app as a real product shell: a menu bar presence and a command
center window, plus the ability to **enroll a local git repo** as a Project,
detect its git facts, store config in the hidden Allnighter support directory, and
show a Project Detail page. This is the home the factory lives in.

## Non-Goals

- Lanes/worktrees (Phase 03), drivers (Phase 04), networking (Phase 08).
- Races/councils/landing UI — just Projects + Backlog placeholders.

## Approach (per `00`)

- SwiftUI app, `MenuBarExtra` for the menu bar; a separate command center
  `Window`. Unsandboxed, Developer ID later (Phase 23).
- **GRDB** store at `~/Library/Application Support/Allnighter/Projects/<id>/state.sqlite`
  with the first migration (projects table). Establish the migration pattern now.
- Repo enrollment uses a security-scoped file picker; persist the path; run
  `GitClient` read-only probes (default branch, dirty status, last commit). The
  `GitClient` actor (`00` §9.4) is introduced here, read-only operations only.
- Command center tabs scaffolded (Projects, Backlog, Active Lanes, Races,
  Councils, Landing Queue, Workers, Preferences, Diagnostics) — most are stubs;
  Projects + Project Detail are real.

## Ordered Slices

- [ ] P02-S01 — App target via XcodeGen (`project.yml`); menu bar item showing factory status (idle); command center window.
- [ ] P02-S02 — GRDB store + migration framework; `Project` persistence; hidden support dir creation.
- [ ] P02-S03 — `GitClient` actor (read-only): `isRepo`, `defaultBranch`, `status`, `headCommit`.
- [ ] P02-S04 — Repo enrollment flow (picker → validate git → save Project → MAC-2 dirty-tree explanation copy).
- [ ] P02-S05 — Project Detail page: repo status, default branch, dirty status, protected paths, standing orders, preview/test commands (editable, persisted).
- [ ] P02-S06 — Command center tab scaffold with stubs for unbuilt sections.

## Works Test

```text
Enroll a local repo in the Mac app. The app shows the default branch, dirty
status, last commit, and the configured preview/test commands, and persists all
of it across relaunch. The menu bar shows the factory status.
```

## Exit Gates

- [ ] Works Test passes on a real local repo.
- [ ] GRDB migration pattern documented and reused-able.
- [ ] MAC-1, MAC-2 satisfied (enroll; explain main tree is untouched).
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 03. Confirm the support-dir layout matches `00` §7.
