# MR-S04 — Exact-id dispatch and one-shot repair

Status: **ready** (after MR-S03)
SSOT: `docs/phases/Menu_Not_Router.md` §MR-S04

## Goal

Route every explicit worker/team selector through one exact-id resolver.
Remove display-name matching and silent/default substitution. Unknown ids return
same-kind candidates + discovery/validation commands; never auto-dispatch.
Table-test every identifier flag for honor-or-fail; no process/run on failure.

## Works Test

```bash
B=Packages/AllnighterCore/.build/release/alln
$B run "probe" --worker model_sonnet --dry-run --json
$B run "probe" --worker 'Sonnet 5' --dry-run --json; test $? -ne 0
$B run "probe" --worker model_sonet --json; test $? -ne 0
$B history "probe" --json  # no run created by rejected selectors
swift test --package-path Packages/AllnighterCore --filter ExactIdResolver
```

## SSOT

`docs/phases/Menu_Not_Router.md` — MR-S04
