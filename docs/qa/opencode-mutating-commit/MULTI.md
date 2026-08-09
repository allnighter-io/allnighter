# OpenCode multi-file mutating harness (OMH-S05)

Status: ACTIVE harness — not product SSOT.

## Instructions for the seat

1. Append one Log bullet to **this file** (`MULTI.md`) with ISO-8601 UTC + run id.
2. Append the same stamp line to `MULTI_AUX.md`.
3. Stage **only**:
   - `docs/qa/opencode-mutating-commit/MULTI.md`
   - `docs/qa/opencode-mutating-commit/MULTI_AUX.md`
4. Commit:

```bash
git commit -m "$(cat <<'EOF'
qa(opencode): multi-file mutating commit dogfood

Seat edited MULTI.md + MULTI_AUX.md and committed (OMH-S05).
EOF
)"
```

5. Prove: both paths clean; `git log -1 --oneline` shows the stamp commit.
6. Do not push. Do not touch other files.

## Pro prompt (copy)

Use `SLICE_TEMPLATE.md` with theme “OMH-S05 multi-file harness”, files =
`MULTI.md` + `MULTI_AUX.md`, Works Test = both paths in `repoDelta.files` and
`committed: true`.

## Log

- 2026-08-09T16:50:00Z · scaffold · OMH-S05 harness created
