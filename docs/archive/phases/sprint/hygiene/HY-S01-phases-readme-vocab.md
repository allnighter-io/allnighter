# HY-S01 — Phases README product laws vocabulary

Status: ready
Owner: hygiene / doc truth
Updated: 2026-08-03

## Goal

Align `docs/phases/README.md` Post-MVP Product Laws with standing vocabulary:
**agent** (not retired **worker**) for human-facing product prose.

## Copy-paste prompt

```text
You are implementing sprint HY-S01 only. Read this file and the allowlist below.
Do not read AGENTS.md or grep the repo for other "worker" strings.

Goal: Fix the "Post-MVP Product Laws" bullet list in docs/phases/README.md
(lines ~107–115). Replace retired user-facing "worker" with "agent" where it
means a staffed seat or mutating run seat — match docs/workflows/Product_Vocabulary.md.

Touch ONLY: docs/phases/README.md (that section only).

Replacements (product prose):
- "coordinates workers the user already pays for" → "coordinates the agents the
  user already pays for" (coding agents on paid CLI seats)
- "one mutating worker" → "one mutating agent"
- "one Running worker per repo root" → "one mutating run per repo root" (or
  equivalent — execution lane = one mutator, not "worker")
- "Workers fail honestly. A failed worker" → "Agents fail honestly. A failed
  agent" (or "Failed runs are shown failed" if clearer)

Do NOT change other sections of the file. Do NOT touch code. Do NOT rename
machine-layer symbols (TeamRun.workers, workerId, etc.) — this slice is docs only.

Works Test: none required (docs-only). Sanity: re-read the five bullets; no
"worker" remains in that section.

Commit:
git add docs/phases/README.md
git commit -m "docs: align phases README product laws with agent vocabulary"
```

## Read only

- This file
- `docs/workflows/Product_Vocabulary.md` — §Team model nouns, retired Worker line

## Touch only

- `docs/phases/README.md` — `## Post-MVP Product Laws` bullets only

## Do not read / do not touch

- Swift sources, generated contracts, GUI, archive docs, other README sections

## Steps

1. Open `docs/phases/README.md`, find `## Post-MVP Product Laws`.
2. Edit only the five bullets under that heading (keep "Full laws:" line as-is).
3. Verify no `worker` in those bullets.
4. Stage explicit path and commit.

## Works Test

Docs-only — no test command. Optional: `rg worker docs/phases/README.md` and
confirm matches are outside the edited section only.

## Done when

- [ ] Five product-law bullets use agent / mutating-run vocabulary, not worker
- [ ] No other edits in the file
- [ ] One commit on explicit path

## SSOT

`docs/workflows/Product_Vocabulary.md` — Worker retired user-facing.
