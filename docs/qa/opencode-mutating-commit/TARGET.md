# OpenCode Mutating Commit Dogfood

Status: **ACTIVE harness** — not product SSOT. Safe to edit and commit.
Purpose: Prove an OpenCode seat can **edit this file and `git commit`** so a
mutating `alln run` lands `done` with `committed: true`, not
`incomplete_uncommitted`.

## Instructions for the seat (follow exactly)

1. Append one new bullet under **Log** below. Format:

   `- <ISO-8601 UTC> · run <TEAM_RUN_ID or unknown> · <one short note>`

2. Stage **only** this file:

   `git add docs/qa/opencode-mutating-commit/TARGET.md`

3. Commit with this exact style (HEREDOC, no other files):

   ```bash
   git commit -m "$(cat <<'EOF'
   qa(opencode): mutating commit dogfood stamp

   Seat edited TARGET.md and committed so incomplete_uncommitted can clear.
   EOF
   )"
   ```

4. Prove: `git log -1 --oneline` and `git status --short` for this path
   (should be clean).

5. Do not touch other files. Do not push. Do not amend.

## Log

- 2026-08-09T15:34:00Z · scaffold · harness created; awaiting first OpenCode stamp
