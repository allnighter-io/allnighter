# ASR-S05d — bootstrap should mention serve once

Status: **ready**
Priority: **P3 — last surface in §10's "install, doctor, help search, bootstrap teaching, and uninstall agree".**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §8 ASR-S05.

## 1. Measured gap

Of the five surfaces §10 requires to agree:

| Surface | Teaches serve? |
| --- | --- |
| install | **yes** — ASR-S05a discloses on both the enabled and `--no-serve` paths |
| `help search` / `help get serve` | **yes** — ASR-S05b topic, nine search terms route to it |
| `doctor` | **yes** |
| `uninstall` | **yes** — ASR-S05c |
| **`bootstrap`** | **no** — `alln bootstrap` mentions serve **zero** times |

`alln bootstrap` is the paste-ready host context an agent is given as its front
door. An agent that reads it learns nothing about the background scheduler, so it
cannot tell a stalled deferred obligation from a broken one.

## 2. Copy-paste prompt

> Add one line about the background scheduler to the `alln bootstrap` snippet:
> that deferred obligations depend on `alln serve`, how to check it, and that
> `alln help get serve` explains it. One line. `bootstrap` is a front door, not a
> manual.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterCore/Bootstrap.swift` — the snippet
  and how host variants differ.
- The `serve` topic added by ASR-S05b (`alln help get serve`) — the line must
  point at it rather than restate it.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterCore/Bootstrap.swift
Packages/AllnighterCore/Tests/AllnighterCoreTests/BootstrapTests.swift
```

## 5. Do not touch

`HelpTopicRegistry`, `MenuCatalog`, `ContractRegistry`, any command, any script.

## 6. Steps

1. **One line.** Something like: deferred work (pending wake, loop wakes,
   notifications, capacity refresh) needs `alln serve`; check with
   `alln serve status --json`; read `alln help get serve` for detail.
2. **Point, do not duplicate.** The narrative lives in the help topic. If the
   line and the topic ever disagree, the topic wins — so keep the line short
   enough that it cannot drift.
3. **Every host variant** gets it (`--host claude|cursor|codex|generic|hermes|openclaw`),
   or none does. A per-host difference here would be an accident, not a design.
4. **Claim nothing new.** No reliability adjectives. `alln run` does not depend on
   serve — do not imply the CLI is broken without it.
5. **Test** that the snippet contains the serve line for every host variant.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'BootstrapTests'
bash scripts/rebuild_cli.sh
alln bootstrap
alln bootstrap --host claude
```

Read-only. Run them and paste real output.

## 8. Done when

- [ ] `alln bootstrap` mentions serve exactly once, pointing at
      `alln serve status --json` and `alln help get serve`.
- [ ] Present for every host variant, proven by test.
- [ ] No new claims; nothing implying `alln run` needs serve.
- [ ] Focused tests and `rebuild_cli.sh` pass. One commit.

## 9. Host-state invariant

Text only.
