# 02 - Copy Apply To Site

Status: Draft fast follow
Owner: Founder + Shared Core + Mac
Updated: 2026-06-15
Depends on: `00_Copy_MVP.md`, Build dispatch

## Founder Intent

Copy should not become a prettier place to copy/paste text. The 10x move is:

```text
pick landing-page copy -> Build applies it to selected site files
```

This is the Copy version of Design's "Build this."

## Product Value

Without apply-to-site, Copy is a good writing surface. With apply-to-site, Copy
belongs inside Allnighter's control loop:

```text
prompt -> copy board -> pick -> copy pack -> Build edits the site
```

The user still chooses the work kind and target files. Allnighter does not become
a CMS, ad platform, or site editor.

## Trusted Workflow Slice

```text
On a completed copy board:
Pick a landing-page option.
Click Apply to site.
Choose working directory and target file(s).
Choose Build worker.
Run.

The Build worker receives the picked copy pack and selected files, then edits the
files in the repo. No manual copy/paste.
```

## Non-Goals

- No auto-publish.
- No external CMS/email/ad integrations.
- No Allnighter-owned AST or localization-file rewriting.
- No repo-wide scan by default.
- No hidden target-file inference.
- No managed worktree/lane safety in this slice.

## Truth Owner

`AllnighterCore` owns the apply request shape and artifact references. The UI
renders it. Build dispatch owns the actual code edit.

Internal code may reuse the existing implementation-handoff model. The UI must
not expose that internal noun; user-facing copy is:

```text
Apply to site
```

## New Semantic Rules

### 1. Apply is explicit

Picking copy does not mutate files. The user must click `Apply to site`, choose
target files, and choose the Build worker.

### 2. Target files are selected, not guessed

The first version requires the user to pick target file(s). Later source-scan work
may suggest files, but it cannot silently route a mutating dispatch.

### 3. Build edits the repo

Allnighter passes the picked copy pack plus selected source context to a Build
worker. Allnighter does not directly patch code, JSON, localization files, or ASTs.

### 4. Source context is bounded

The handoff includes:

- picked copy pack;
- selected option metadata;
- selected target file path(s);
- selected file excerpts or full files within byte caps;
- explicit instruction to preserve behavior and data wiring.

No repo-wide scan is included in this fast follow.

### 5. Failures stay visible

If the Build worker fails, the copy board and copy pack remain intact. The apply
turn records the worker failure and does not mark the copy as applied.

## Artifact Contract

```text
run_<id>/
  copy_pack.md
  apply_to_site_request.json   # selected copy, target files, worker, cwd
  apply_to_site_prompt.md      # derived prompt sent to the Build worker
  dispatch_<n>/                # existing Build dispatch artifacts
```

## Ordered Slices

- [ ] C2-S01 - Core apply request model: selected copy option, copy pack ref,
  target file paths, working directory, Build worker id.
- [ ] C2-S02 - Copy board action: `Apply to site` appears after a picked copy
  option exists.
- [ ] C2-S03 - Target-file picker with explicit selected files and no hidden repo
  scan.
- [ ] C2-S04 - Build handoff prompt builder: copy pack + selected file context +
  preserve-behavior instruction.
- [ ] C2-S05 - Dispatch through existing Build worker path; status and failures
  recorded in the thread/run.
- [ ] C2-S06 - Bundle/export includes apply status and selected file list.

## Works Test

```text
Run `/copy landing` on a pricing-page prompt.
Pick one copy option.
Click Apply to site.
Select the app's pricing page source file.
Choose a healthy Build worker.
Run.

The Build worker receives the copy pack and selected source file, edits only the
selected page or explicitly named supporting files, and the dispatch status is
captured. If the worker fails, the failed status is visible and the copy pack
remains usable.
```

## Proof Command

```text
swift test
```

App proof follows `docs/operations/TechStack.md` once UI code exists.

## Done When

- A picked copy option can start an Apply-to-site turn.
- The user selects target files explicitly.
- Build, not Allnighter, edits the repo.
- No copy/paste is required between copy pack and Build handoff.
- Failures are visible and do not corrupt the copy board.

