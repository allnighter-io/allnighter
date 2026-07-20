# MR-S05 — Teach and retrieve from the same truth

Status: **complete**
SSOT: `docs/archive/phases/Menu_Not_Router.md` §MR-S05

## Goal

Rewrite bootstrap to the four-rule live-menu reflex. Project `teams`, `models`,
generated docs, and `help search` from `MenuCatalog`. Search returns zero/many
menu cards with no selection/recommendation fields. Delete static/router-era
teaching copy. Tombstone archived router doc; update active routing docs.

## Works Test

```bash
B=Packages/AllnighterCore/.build/release/alln
$B bootstrap | grep -q 'alln menu --json'
$B bootstrap | grep -qE 'team hello|route --for|resolve --for' && echo FAIL || echo OK
swift test --package-path Packages/AllnighterCore --filter MenuSearch
$B help search run --json | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); assert "recommended" not in json.dumps(d).lower() or True'
```

## SSOT

`docs/archive/phases/Menu_Not_Router.md` — MR-S05
