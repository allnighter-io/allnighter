# MR-S06 — Cold-agent proof

Status: **ready** (after MR-S05)
SSOT: `docs/phases/Menu_Not_Router.md` §MR-S06 + Cold-agent acceptance matrix

## Goal

Replace the router-era harness with pinned-binary, out-of-distribution tests.
Record binary SHA, menu bytes/counts, every command attempted, dry-run JSON,
whether a run/provider process was created, and final exact command. Fail on
stale binary, invented grammar, discovery loops, wrong spend, display-name
execution, incompleteness, or common path requiring hydration.

## Works Test

```bash
swift build -c release --package-path Packages/AllnighterCore --product alln
B=Packages/AllnighterCore/.build/release/alln
scripts/agent_eval.sh --suite menu-not-router --binary "$B"
scripts/check.sh
```

Then run the full phase Works Test from `Menu_Not_Router.md`.

## Phase closeout

On green: mark phase Complete, archive per Execution-Playbook §Phase Archive,
update `docs/phases/README.md` + archive README + routed references.

## SSOT

`docs/phases/Menu_Not_Router.md` — MR-S06 + Done when
